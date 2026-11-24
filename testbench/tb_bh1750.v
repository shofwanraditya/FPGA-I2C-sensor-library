// ============================================================================
// Testbench : tb_bh1750
// File      : tb_bh1750.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Verifikasi Integrasi bh1750_driver dan i2c_master
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

`timescale 1ns / 1ps

module tb_bh1750;

    parameter CLK_PERIOD       = 20; // 50 MHz
    parameter HALF_PERIOD      = 4;  // I2C SCL clock divider cepat untuk simulasi
    parameter CONV_WAIT_CYCLES = 30; // Siklus waktu tunggu konversi sensor

    reg         clk;
    reg         rst_n;
    reg         start_meas;

    wire        busy;
    wire        data_valid;
    wire [15:0] data_lux;
    wire        error;

    // Sinyal penghubung antara bh1750_driver dan i2c_master
    wire        i2c_cmd_valid;
    wire [2:0]  i2c_cmd;
    wire [7:0]  i2c_data_in;
    wire [7:0]  i2c_data_out;
    wire        i2c_busy;
    wire        i2c_done;
    wire        i2c_ack_error;

    // Sinyal Bus I2C
    wire        scl_o;
    wire        sda_o;
    wire        sda_i;
    wire        scl;
    wire        sda;

    reg         slave_sda_drive_low;

    // Open-Drain & Pull-up
    assign scl   = (scl_o == 1'b0) ? 1'b0 : 1'bz;
    assign sda   = (sda_o == 1'b0 || slave_sda_drive_low == 1'b1) ? 1'b0 : 1'bz;
    assign sda_i = sda;

    pullup(scl);
    pullup(sda);

    // ========================================================================
    // INSTANSIASI DRIVER BH1750 (DUT 1)
    // ========================================================================
    bh1750_driver #(
        .CONV_WAIT_CYCLES(CONV_WAIT_CYCLES)
    ) u_bh1750 (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_meas    (start_meas),
        .busy          (busy),
        .data_valid    (data_valid),
        .data_lux      (data_lux),
        .error         (error),
        .i2c_cmd_valid (i2c_cmd_valid),
        .i2c_cmd       (i2c_cmd),
        .i2c_data_in   (i2c_data_in),
        .i2c_data_out  (i2c_data_out),
        .i2c_busy      (i2c_busy),
        .i2c_done      (i2c_done),
        .i2c_ack_error (i2c_ack_error)
    );

    // ========================================================================
    // INSTANSIASI I2C MASTER (DUT 2)
    // ========================================================================
    i2c_master #(
        .HALF_PERIOD(HALF_PERIOD)
    ) u_i2c_master (
        .clk       (clk),
        .rst_n     (rst_n),
        .cmd_valid (i2c_cmd_valid),
        .cmd       (i2c_cmd),
        .data_in   (i2c_data_in),
        .data_out  (i2c_data_out),
        .busy      (i2c_busy),
        .done      (i2c_done),
        .ack_error (i2c_ack_error),
        .scl_o     (scl_o),
        .sda_o     (sda_o),
        .sda_i     (sda_i)
    );

    // ========================================================================
    // CLOCK GENERATOR
    // ========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ========================================================================
    // MODEL EMULATOR BH1750 SENSOR SLAVE (0x23)
    // ========================================================================
    reg [7:0] rx_shift;
    integer   b;

    // Nilai uji intensitas cahaya: 0x0145 (325 lux)
    localparam [7:0] MOCK_LUX_HIGH = 8'h01;
    localparam [7:0] MOCK_LUX_LOW  = 8'h45;

    initial begin
        slave_sda_drive_low = 1'b0;

        forever begin
            // Deteksi START
            @(negedge sda);
            if (scl == 1'b1) begin
                // Baca Alamat (8-bit)
                for (b = 7; b >= 0; b = b - 1) begin
                    @(posedge scl);
                    rx_shift[b] = sda;
                end

                if (rx_shift[7:1] == 7'h23) begin
                    // ACK Alamat
                    @(negedge scl);
                    slave_sda_drive_low = 1'b1;
                    @(negedge scl);
                    slave_sda_drive_low = 1'b0;

                    if (rx_shift[0] == 1'b0) begin
                        // Transaksi WRITE: Baca Opcode
                        for (b = 7; b >= 0; b = b - 1) begin
                            @(posedge scl);
                            rx_shift[b] = sda;
                        end
                        // ACK Opcode
                        @(negedge scl);
                        slave_sda_drive_low = 1'b1;
                        @(negedge scl);
                        slave_sda_drive_low = 1'b0;
                    end else begin
                        // Transaksi READ: Kirim MSB lalu LSB
                        // 1. Kirim High Byte
                        for (b = 7; b >= 0; b = b - 1) begin
                            slave_sda_drive_low = (MOCK_LUX_HIGH[b] == 1'b0);
                            @(negedge scl);
                        end
                        slave_sda_drive_low = 1'b0; // Lepas untuk Master ACK
                        @(posedge scl); // Master memberikan ACK

                        // 2. Kirim Low Byte
                        @(negedge scl);
                        for (b = 7; b >= 0; b = b - 1) begin
                            slave_sda_drive_low = (MOCK_LUX_LOW[b] == 1'b0);
                            @(negedge scl);
                        end
                        slave_sda_drive_low = 1'b0; // Lepas untuk Master NACK
                        @(posedge scl); // Master memberikan NACK
                    end
                end
            end
        end
    end

    // ========================================================================
    // SKENARIO PENGUJIAN
    // ========================================================================
    initial begin
        $timeformat(-9, 0, " ns", 10);
        rst_n      = 1'b0;
        start_meas = 1'b0;

        $display("==================================================");
        $display("     TESTBENCH BH1750 SENSOR DRIVER (Tahap 4)     ");
        $display("==================================================");

        // Reset sistem
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // Trigger mulai pengukuran
        $display("[%0t] Memicu pengukuran sensor (start_meas)...", $time);
        @(posedge clk);
        start_meas <= 1'b1;
        @(posedge clk);
        start_meas <= 1'b0;

        // Tunggu hingga data_valid aktif
        @(posedge data_valid);
        $display("[%0t] Data Pengukuran Selesai! data_valid = 1", $time);
        $display("[%0t] Hasil Pembacaan Lux : 0x%04X (%0d)", $time, data_lux, data_lux);

        // Verifikasi hasil
        if (data_lux == 16'h0145) begin
            $display("[%0t] [OK] Data Lux SESUAI ekspektasi sensor (0x0145)", $time);
            $display("\n==================================================");
            $display("   HASIL AKHIR: DRIVER BH1750 BERHASIL! (PASSED)  ");
            $display("==================================================");
        end else begin
            $display("[%0t] [GAGAL] Data Lux SALAH!", $time);
            $display("Status: FAILED");
        end

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule
