// ============================================================================
// Testbench : tb_i2c_master
// File      : tb_i2c_master.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Verifikasi I2C Master Controller dengan Model I2C Slave sederhana
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

`timescale 1ns / 1ps

module tb_i2c_master;

    // ========================================================================
    // PARAMETER SIMULASI
    // ========================================================================
    // CLK 50 MHz (periode 20 ns)
    // HALF_PERIOD = 5 clock cycle agar simulasi cepat namun jelas terlihat
    parameter CLK_PERIOD  = 20;
    parameter HALF_PERIOD = 5;

    // Command Codes (harus sinkron dengan i2c_master.v)
    localparam [2:0] CMD_START     = 3'd1;
    localparam [2:0] CMD_WRITE     = 3'd2;
    localparam [2:0] CMD_READ_ACK  = 3'd3;
    localparam [2:0] CMD_READ_NACK = 3'd4;
    localparam [2:0] CMD_STOP      = 3'd5;

    // ========================================================================
    // SINYAL TESTBENCH
    // ========================================================================
    reg        clk;
    reg        rst_n;

    reg        cmd_valid;
    reg  [2:0] cmd;
    reg  [7:0] data_in;

    wire [7:0] data_out;
    wire       busy;
    wire       done;
    wire       ack_error;

    wire       scl_o;
    wire       sda_o;
    wire       sda_i;

    // Jalur fisik I2C (Tri-state / Open-Drain dengan pull-up)
    wire       scl;
    wire       sda;

    // Slave internal response signal
    reg        slave_sda_drive_low;

    // ========================================================================
    // MODEL OPEN-DRAIN & PULL-UP RESISTOR
    // ========================================================================
    // Jika master atau slave menarik '0', jalur menjadi 0.
    // Jika keduanya melepas ('1' / 'Z'), pull-up menarik jalur menjadi '1'.
    assign scl   = (scl_o == 1'b0) ? 1'b0 : 1'bz;
    assign sda   = (sda_o == 1'b0 || slave_sda_drive_low == 1'b1) ? 1'b0 : 1'bz;

    // Model Pull-Up Resistor (lemah tapi pasti bernilai 1 jika z)
    pullup(scl);
    pullup(sda);

    // Input pembacaan ke Master
    assign sda_i = sda;

    // ========================================================================
    // INSTANSIASI DUT (Device Under Test)
    // ========================================================================
    i2c_master #(
        .HALF_PERIOD(HALF_PERIOD)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .cmd_valid (cmd_valid),
        .cmd       (cmd),
        .data_in   (data_in),
        .data_out  (data_out),
        .busy      (busy),
        .done      (done),
        .ack_error (ack_error),
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
    // MODEL SEDERHANA I2C SLAVE (Alamat: 0x23)
    // ========================================================================
    // Merespons ACK saat menerima alamat 0x23 (Write: 0x46 / Read: 0x47)
    // Mengirimkan data dummy (0xAB) saat dibaca oleh Master
    // ========================================================================
    reg [7:0] slave_rx_shift;
    reg [7:0] slave_tx_data;
    integer   s_bit_idx;

    initial begin
        slave_sda_drive_low = 1'b0;
        slave_tx_data       = 8'hAB; // Dummy data sensor

        forever begin
            // 1. Deteksi START Condition (SDA jatuh saat SCL tinggi)
            @(negedge sda);
            if (scl == 1'b1) begin
                // Baca 8 bit (Alamat + R/W)
                for (s_bit_idx = 7; s_bit_idx >= 0; s_bit_idx = s_bit_idx - 1) begin
                    @(posedge scl);
                    slave_rx_shift[s_bit_idx] = sda;
                end

                // Periksa apakah alamat cocok (0x23 -> 7-bit addr)
                if (slave_rx_shift[7:1] == 7'h23) begin
                    // Cocok! Berikan ACK pada siklus clock ke-9
                    @(negedge scl);
                    slave_sda_drive_low = 1'b1; // ACK (tarik SDA ke 0)
                    @(negedge scl);
                    slave_sda_drive_low = 1'b0; // Lepas ACK

                    // Cek apakah mode Read atau Write
                    if (slave_rx_shift[0] == 1'b1) begin
                        // Mode READ: Slave mengirim byte data 0xAB ke Master
                        for (s_bit_idx = 7; s_bit_idx >= 0; s_bit_idx = s_bit_idx - 1) begin
                            if (slave_tx_data[s_bit_idx] == 1'b0)
                                slave_sda_drive_low = 1'b1;
                            else
                                slave_sda_drive_low = 1'b0;
                            @(negedge scl);
                        end
                        // Lepas jalur untuk membaca Master ACK / NACK
                        slave_sda_drive_low = 1'b0;
                        @(posedge scl); // Master memberikan ACK/NACK di sini
                    end else begin
                        // Mode WRITE: Baca 1 byte data berikutnya dari Master
                        for (s_bit_idx = 7; s_bit_idx >= 0; s_bit_idx = s_bit_idx - 1) begin
                            @(posedge scl);
                            slave_rx_shift[s_bit_idx] = sda;
                        end
                        // Berikan ACK untuk data byte
                        @(negedge scl);
                        slave_sda_drive_low = 1'b1;
                        @(negedge scl);
                        slave_sda_drive_low = 1'b0;
                    end
                end
            end
        end
    end

    // ========================================================================
    // TASK HELPER: Eksekusi Command
    // ========================================================================
    task send_i2c_cmd(input [2:0] c, input [7:0] din);
    begin
        @(posedge clk);
        cmd_valid <= 1'b1;
        cmd       <= c;
        data_in   <= din;
        @(posedge clk);
        cmd_valid <= 1'b0;

        // Tunggu sampai master selesai mengerjakan command
        @(posedge done);
        @(posedge clk);
    end
    endtask

    // ========================================================================
    // SKENARIO PENGUJIAN
    // ========================================================================
    initial begin
        $timeformat(-9, 0, " ns", 10);
        cmd_valid = 1'b0;
        cmd       = 3'd0;
        data_in   = 8'd0;
        rst_n     = 1'b0;

        $display("==================================================");
        $display("   TESTBENCH I2C MASTER CONTROLLER (Tahap 3)");
        $display("==================================================");

        // Reset sistem selama 5 clock cycle
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // --------------------------------------------------------------------
        // UJI 1: WRITE TRANSACTION KE SENSOR (Alamat 0x23 + W = 0x46, Data = 0x01)
        // --------------------------------------------------------------------
        $display("\n[%0t] --- UJI 1: WRITE Transaksi (Addr 0x23 + W, Data 0x01) ---", $time);
        
        // 1. START
        send_i2c_cmd(CMD_START, 8'h00);
        $display("[%0t] START terkirim", $time);

        // 2. WRITE Alamat Slave (0x23 << 1 | 0 = 0x46)
        send_i2c_cmd(CMD_WRITE, 8'h46);
        if (ack_error == 1'b0)
            $display("[%0t] [OK] Alamat 0x46 di-ACK oleh Slave", $time);
        else begin
            $display("[%0t] [GAGAL] Alamat NACK!", $time);
            $finish;
        end

        // 3. WRITE Data Perintah (0x01)
        send_i2c_cmd(CMD_WRITE, 8'h01);
        if (ack_error == 1'b0)
            $display("[%0t] [OK] Data 0x01 di-ACK oleh Slave", $time);
        else begin
            $display("[%0t] [GAGAL] Data NACK!", $time);
            $finish;
        end

        // 4. STOP
        send_i2c_cmd(CMD_STOP, 8'h00);
        $display("[%0t] STOP terkirim", $time);

        repeat (10) @(posedge clk);

        // --------------------------------------------------------------------
        // UJI 2: READ TRANSACTION DARI SENSOR (Alamat 0x23 + R = 0x47)
        // --------------------------------------------------------------------
        $display("\n[%0t] --- UJI 2: READ Transaksi (Addr 0x23 + R, Baca Data) ---", $time);

        // 1. START
        send_i2c_cmd(CMD_START, 8'h00);
        $display("[%0t] START terkirim", $time);

        // 2. WRITE Alamat Slave + Read (0x23 << 1 | 1 = 0x47)
        send_i2c_cmd(CMD_WRITE, 8'h47);
        if (ack_error == 1'b0)
            $display("[%0t] [OK] Alamat 0x47 di-ACK oleh Slave", $time);
        else begin
            $display("[%0t] [GAGAL] Alamat Read NACK!", $time);
            $finish;
        end

        // 3. READ DATA (Dengan NACK karena membaca byte terakhir)
        send_i2c_cmd(CMD_READ_NACK, 8'h00);
        $display("[%0t] Data terbaca: 0x%02X (Harapan: 0xAB)", $time, data_out);
        if (data_out == 8'hAB)
            $display("[%0t] [OK] Data yang dibaca sesuai!", $time);
        else begin
            $display("[%0t] [GAGAL] Data tidak cocok!", $time);
            $finish;
        end

        // 4. STOP
        send_i2c_cmd(CMD_STOP, 8'h00);
        $display("[%0t] STOP terkirim", $time);

        repeat (15) @(posedge clk);

        $display("\n==================================================");
        $display("   HASIL AKHIR: SEMUA TEST I2C MASTER BERHASIL! (PASSED)");
        $display("==================================================");
        $finish;
    end

endmodule
