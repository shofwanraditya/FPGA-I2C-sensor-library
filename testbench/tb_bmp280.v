// ============================================================================
// Testbench : tb_bmp280
// File      : tb_bmp280.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Verifikasi Integrasi bmp280_driver dan i2c_master
//
// Revisi    : v2.2 - Sinkronisasi edge SCL yang tepat (count on scl_rise)
// Author    : Muhammad Shofwan Raditya
// Date      : 2026-11-24
// ============================================================================

`timescale 1ns / 1ps

module tb_bmp280;

    parameter CLK_PERIOD       = 20; // 50 MHz
    parameter HALF_PERIOD      = 4;  // I2C clock divider cepat untuk simulasi
    parameter CONV_WAIT_CYCLES = 30;

    reg         clk;
    reg         rst_n;
    reg         start_meas;

    wire        busy;
    wire        data_valid;
    wire [19:0] temp_raw;
    wire [19:0] press_raw;
    wire        chip_id_ok;
    wire        error;

    // Sinyal penghubung antar modul
    wire        i2c_cmd_valid;
    wire [2:0]  i2c_cmd;
    wire [7:0]  i2c_data_in;
    wire [7:0]  i2c_data_out;
    wire        i2c_busy;
    wire        i2c_done;
    wire        i2c_ack_error;

    // Sinyal Bus Fisik
    wire        scl_o;
    wire        sda_o;
    wire        sda_i;
    wire        scl;
    wire        sda;

    reg         slave_sda_drive_low;

    // Open-drain & pullup
    assign scl   = (scl_o == 1'b0) ? 1'b0 : 1'bz;
    assign sda   = (sda_o == 1'b0 || slave_sda_drive_low == 1'b1) ? 1'b0 : 1'bz;
    assign sda_i = sda;

    pullup(scl);
    pullup(sda);

    // ========================================================================
    // DUT: BMP280 Driver
    // ========================================================================
    bmp280_driver #(
        .CONV_WAIT_CYCLES(CONV_WAIT_CYCLES)
    ) u_bmp280 (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_meas    (start_meas),
        .busy          (busy),
        .data_valid    (data_valid),
        .temp_raw      (temp_raw),
        .press_raw     (press_raw),
        .chip_id_ok    (chip_id_ok),
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
    // DUT: I2C Master
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
    // SYNCHRONOUS I2C SLAVE MODEL (BMP280 @ 0x76)
    // ========================================================================
    reg scl_d, sda_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_d <= 1'b1;
            sda_d <= 1'b1;
        end else begin
            scl_d <= scl;
            sda_d <= sda;
        end
    end

    wire scl_rise   = (scl == 1'b1 && scl_d == 1'b0);
    wire scl_fall   = (scl == 1'b0 && scl_d == 1'b1);
    wire start_cond = (sda == 1'b0 && sda_d == 1'b1 && scl == 1'b1);
    wire stop_cond  = (sda == 1'b1 && sda_d == 1'b0 && scl == 1'b1);

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_ADDR      = 3'd1;
    localparam [2:0] S_ADDR_ACK  = 3'd2;
    localparam [2:0] S_WR_DATA   = 3'd3;
    localparam [2:0] S_WR_ACK    = 3'd4;
    localparam [2:0] S_RD_DATA   = 3'd5;
    localparam [2:0] S_RD_ACK    = 3'd6;

    reg [2:0]  slv_state;
    reg [7:0]  slv_shift;
    reg [3:0]  slv_bit_cnt;
    reg [7:0]  slv_reg_ptr;
    reg        slv_is_read;
    reg        slv_first_byte;
    reg        master_nack;
    reg [7:0]  slv_mem [0:255];
    integer    m;

    initial begin
        for (m = 0; m < 256; m = m + 1) slv_mem[m] = 8'h00;
        slv_mem[8'hD0] = 8'h58; // Chip ID
        slv_mem[8'hF7] = 8'h51; // Press MSB
        slv_mem[8'hF8] = 8'h82; // Press LSB
        slv_mem[8'hF9] = 8'h00; // Press XLSB
        slv_mem[8'hFA] = 8'h83; // Temp MSB
        slv_mem[8'hFB] = 8'h45; // Temp LSB
        slv_mem[8'hFC] = 8'h00; // Temp XLSB
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slv_state           <= S_IDLE;
            slave_sda_drive_low <= 1'b0;
            slv_shift           <= 8'd0;
            slv_bit_cnt         <= 4'd0;
            slv_reg_ptr         <= 8'd0;
            slv_is_read         <= 1'b0;
            slv_first_byte      <= 1'b1;
            master_nack         <= 1'b0;
        end else begin
            if (start_cond) begin
                slave_sda_drive_low <= 1'b0;
                slv_bit_cnt         <= 4'd0;
                slv_shift           <= 8'd0;
                slv_state           <= S_ADDR;
            end else if (stop_cond) begin
                slave_sda_drive_low <= 1'b0;
                slv_state           <= S_IDLE;
            end else begin
                case (slv_state)
                    S_IDLE: begin
                        slave_sda_drive_low <= 1'b0;
                    end

                    // Menerima 8 bit Alamat (7-bit Addr + R/W)
                    S_ADDR: begin
                        if (scl_rise) begin
                            slv_shift   <= {slv_shift[6:0], sda};
                            slv_bit_cnt <= slv_bit_cnt + 1'b1;
                        end
                        if (scl_fall && slv_bit_cnt == 4'd8) begin
                            if (slv_shift[7:1] == 7'h76) begin
                                slave_sda_drive_low <= 1'b1; // Tarik ACK
                                slv_is_read         <= slv_shift[0];
                                slv_first_byte      <= 1'b1;
                                slv_bit_cnt         <= 4'd0;
                                slv_state           <= S_ADDR_ACK;
                            end else begin
                                slv_state           <= S_IDLE;
                            end
                        end
                    end

                    // Lepas ACK Alamat setelah clock 9 selesai
                    S_ADDR_ACK: begin
                        if (scl_fall) begin
                            slave_sda_drive_low <= 1'b0; // Lepas ACK
                            slv_bit_cnt         <= 4'd0;
                            if (slv_is_read) begin
                                slv_shift           <= slv_mem[slv_reg_ptr];
                                slave_sda_drive_low <= (slv_mem[slv_reg_ptr][7] == 1'b0);
                                slv_state           <= S_RD_DATA;
                            end else begin
                                slv_state           <= S_WR_DATA;
                            end
                        end
                    end

                    // Menerima data byte dari Master (Write)
                    S_WR_DATA: begin
                        if (scl_rise) begin
                            slv_shift   <= {slv_shift[6:0], sda};
                            slv_bit_cnt <= slv_bit_cnt + 1'b1;
                        end
                        if (scl_fall && slv_bit_cnt == 4'd8) begin
                            slave_sda_drive_low <= 1'b1; // Tarik ACK
                            if (slv_first_byte) begin
                                slv_reg_ptr    <= slv_shift;
                                slv_first_byte <= 1'b0;
                            end else begin
                                slv_mem[slv_reg_ptr] <= slv_shift;
                                slv_reg_ptr          <= slv_reg_ptr + 1'b1;
                            end
                            slv_bit_cnt <= 4'd0;
                            slv_state   <= S_WR_ACK;
                        end
                    end

                    // Lepas ACK Write
                    S_WR_ACK: begin
                        if (scl_fall) begin
                            slave_sda_drive_low <= 1'b0; // Lepas ACK
                            slv_bit_cnt         <= 4'd0;
                            slv_state           <= S_WR_DATA;
                        end
                    end

                    // Mengirim data byte ke Master (Read)
                    S_RD_DATA: begin
                        if (scl_fall) begin
                            if (slv_bit_cnt == 4'd7) begin
                                slave_sda_drive_low <= 1'b0; // Lepas untuk Master ACK/NACK
                                slv_state           <= S_RD_ACK;
                            end else begin
                                slv_bit_cnt         <= slv_bit_cnt + 1'b1;
                                slave_sda_drive_low <= (slv_shift[7 - (slv_bit_cnt + 1'b1)] == 1'b0);
                            end
                        end
                    end

                    // Menangkap ACK/NACK dari Master
                    S_RD_ACK: begin
                        if (scl_rise) begin
                            master_nack <= sda; // 1 = NACK, 0 = ACK
                        end
                        if (scl_fall) begin
                            if (master_nack) begin
                                slv_state <= S_IDLE;
                            end else begin
                                slv_reg_ptr         <= slv_reg_ptr + 1'b1;
                                slv_shift           <= slv_mem[slv_reg_ptr + 1'b1];
                                slave_sda_drive_low <= (slv_mem[slv_reg_ptr + 1'b1][7] == 1'b0);
                                slv_bit_cnt         <= 4'd0;
                                slv_state           <= S_RD_DATA;
                            end
                        end
                    end

                    default: slv_state <= S_IDLE;
                endcase
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
        $display("     TESTBENCH BMP280 SENSOR DRIVER (Tahap 4)     ");
        $display("==================================================");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("[%0t] Memicu pengukuran sensor BMP280 (start_meas)...", $time);
        @(posedge clk);
        start_meas <= 1'b1;
        @(posedge clk);
        start_meas <= 1'b0;

        // Monitoring dengan timeout pengaman
        fork : wait_result
            begin
                @(posedge data_valid);
                $display("[%0t] Pengukuran Selesai! data_valid = 1", $time);
                $display("[%0t] Chip ID Validasi : %s (chip_id_ok = %0b)", $time, chip_id_ok ? "BERHASIL (0x58)" : "GAGAL", chip_id_ok);
                $display("[%0t] Raw Pressure ADC : 0x%05X (%0d)", $time, press_raw, press_raw);
                $display("[%0t] Raw Temp ADC     : 0x%05X (%0d)", $time, temp_raw, temp_raw);

                if (chip_id_ok == 1'b1 && press_raw == 20'h51820 && temp_raw == 20'h83450) begin
                    $display("[%0t] [OK] Data BMP280 100%% SESUAI ekspektasi!", $time);
                    $display("\n==================================================");
                    $display("   HASIL AKHIR: DRIVER BMP280 BERHASIL! (PASSED)  ");
                    $display("==================================================");
                end else begin
                    $display("[%0t] [GAGAL] Data BMP280 tidak cocok!", $time);
                    $display("Status: FAILED");
                end
                disable wait_result;
            end
            begin
                @(posedge error);
                $display("[%0t] [ERROR] Driver melaporkan I2C ACK Error!", $time);
                $display("Status: FAILED");
                disable wait_result;
            end
            begin
                #100000; // Timeout 100 us
                $display("[%0t] [TIMEOUT] Waktu simulasi habis tanpa respon!", $time);
                $display("Status: TIMEOUT / FAILED");
                disable wait_result;
            end
        join

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule
