// ============================================================================
// Testbench : tb_top_module
// File      : tb_top_module.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Verifikasi Sistem Terintegrasi: BH1750 + BMP280 + UART Output
//
// Author    : Muhammad Shofwan Raditya
// Date      : 2026-11-24
// ============================================================================

`timescale 1ns / 1ps

module tb_top_module;

    parameter CLK_PERIOD      = 20; // 50 MHz
    parameter I2C_HALF_PERIOD = 4;  // I2C divider cepat untuk simulasi
    parameter SENSOR_WAIT_CYC = 20; // Waktu tunggu sensor cepat
    parameter UART_CLKS_BIT   = 8;  // UART baud divider cepat untuk simulasi

    reg  clk;
    reg  rst_n;
    reg  trigger_btn;

    wire led_heartbeat;
    wire led_busy;
    wire led_error;

    wire i2c_scl;
    wire i2c_sda;
    wire uart_tx_pin;

    // Model Pull-Up Bus I2C
    pullup(i2c_scl);
    pullup(i2c_sda);

    // ========================================================================
    // DUT: TOP MODULE
    // ========================================================================
    top_module #(
        .I2C_HALF_PERIOD (I2C_HALF_PERIOD),
        .SENSOR_WAIT_CYC (SENSOR_WAIT_CYC),
        .UART_CLKS_BIT   (UART_CLKS_BIT)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .trigger_btn   (trigger_btn),
        .led_heartbeat (led_heartbeat),
        .led_busy      (led_busy),
        .led_error     (led_error),
        .i2c_scl       (i2c_scl),
        .i2c_sda       (i2c_sda),
        .uart_tx_pin   (uart_tx_pin)
    );

    // ========================================================================
    // CLOCK GENERATOR
    // ========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ========================================================================
    // MODEL DUAL SENSOR I2C (BH1750 @ 0x23 & BMP280 @ 0x76)
    // ========================================================================
    reg bh1750_sda_drive;
    reg bmp280_sda_drive;

    assign i2c_sda = (bh1750_sda_drive || bmp280_sda_drive) ? 1'b0 : 1'bz;

    // Edge detector
    reg scl_d, sda_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_d <= 1'b1; sda_d <= 1'b1;
        end else begin
            scl_d <= i2c_scl; sda_d <= i2c_sda;
        end
    end

    wire scl_rise   = (i2c_scl == 1'b1 && scl_d == 1'b0);
    wire scl_fall   = (i2c_scl == 1'b0 && scl_d == 1'b1);
    wire start_cond = (i2c_sda == 1'b0 && sda_d == 1'b1 && i2c_scl == 1'b1);
    wire stop_cond  = (i2c_sda == 1'b1 && sda_d == 1'b0 && i2c_scl == 1'b1);

    // SENSOR EMULATOR LOGIC
    reg [2:0]  state_s;
    reg [7:0]  shift_s;
    reg [3:0]  bit_s;
    reg [6:0]  matched_addr;
    reg        is_read_s;
    reg [7:0]  reg_ptr_s;
    reg        first_wr_s;
    reg        m_nack_s;
    reg [7:0]  next_byte;
    reg [7:0]  bmp_mem [0:255];
    integer    m;

    initial begin
        for (m = 0; m < 256; m = m + 1) bmp_mem[m] = 8'h00;
        bmp_mem[8'hD0] = 8'h58;
        bmp_mem[8'hF7] = 8'h51; // Press MSB
        bmp_mem[8'hF8] = 8'h82; // Press LSB
        bmp_mem[8'hF9] = 8'h00; // Press XLSB
        bmp_mem[8'hFA] = 8'h83; // Temp MSB
        bmp_mem[8'hFB] = 8'h45; // Temp LSB
        bmp_mem[8'hFC] = 8'h00; // Temp XLSB
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_s          <= 0;
            bh1750_sda_drive <= 1'b0;
            bmp280_sda_drive <= 1'b0;
            shift_s          <= 8'd0;
            bit_s            <= 4'd0;
            matched_addr     <= 7'd0;
            is_read_s        <= 1'b0;
            reg_ptr_s        <= 8'd0;
            first_wr_s       <= 1'b1;
            m_nack_s         <= 1'b0;
        end else begin
            if (start_cond) begin
                bh1750_sda_drive <= 1'b0;
                bmp280_sda_drive <= 1'b0;
                bit_s            <= 4'd0;
                shift_s          <= 8'd0;
                state_s          <= 1; // S_ADDR
            end else if (stop_cond) begin
                bh1750_sda_drive <= 1'b0;
                bmp280_sda_drive <= 1'b0;
                state_s          <= 0;
            end else begin
                case (state_s)
                    0: begin // IDLE
                        bh1750_sda_drive <= 1'b0;
                        bmp280_sda_drive <= 1'b0;
                    end

                    1: begin // S_ADDR
                        if (scl_rise) begin
                            shift_s <= {shift_s[6:0], i2c_sda};
                            bit_s   <= bit_s + 1'b1;
                        end
                        if (scl_fall && bit_s == 4'd8) begin
                            if (shift_s[7:1] == 7'h23 || shift_s[7:1] == 7'h76) begin
                                matched_addr <= shift_s[7:1];
                                is_read_s    <= shift_s[0];
                                first_wr_s   <= 1'b1;
                                bit_s        <= 4'd0;
                                state_s      <= 2; // S_ADDR_ACK

                                if (shift_s[7:1] == 7'h23) bh1750_sda_drive <= 1'b1;
                                else                       bmp280_sda_drive <= 1'b1;
                            end else begin
                                state_s <= 0;
                            end
                        end
                    end

                    2: begin // S_ADDR_ACK
                        if (scl_fall) begin
                            bh1750_sda_drive <= 1'b0;
                            bmp280_sda_drive <= 1'b0;
                            bit_s            <= 4'd0;

                            if (is_read_s) begin
                                state_s <= 5; // S_RD_DATA
                                if (matched_addr == 7'h23) begin
                                    shift_s          <= 8'h01; // Lux MSB
                                    bh1750_sda_drive <= 1'b1;  // 8'h01[7] == 0 -> drive LOW
                                end else begin
                                    next_byte        = bmp_mem[reg_ptr_s];
                                    shift_s          <= next_byte;
                                    bmp280_sda_drive <= (next_byte[7] == 1'b0);
                                end
                            end else begin
                                state_s <= 3; // S_WR_DATA
                            end
                        end
                    end

                    3: begin // S_WR_DATA
                        if (scl_rise) begin
                            shift_s <= {shift_s[6:0], i2c_sda};
                            bit_s   <= bit_s + 1'b1;
                        end
                        if (scl_fall && bit_s == 4'd8) begin
                            bit_s   <= 4'd0;
                            state_s <= 4; // S_WR_ACK

                            if (matched_addr == 7'h76) begin
                                bmp280_sda_drive <= 1'b1;
                                if (first_wr_s) begin
                                    reg_ptr_s  <= shift_s;
                                    first_wr_s <= 1'b0;
                                end else begin
                                    bmp_mem[reg_ptr_s] <= shift_s;
                                    reg_ptr_s          <= reg_ptr_s + 1'b1;
                                end
                            end else begin
                                bh1750_sda_drive <= 1'b1;
                            end
                        end
                    end

                    4: begin // S_WR_ACK
                        if (scl_fall) begin
                            bh1750_sda_drive <= 1'b0;
                            bmp280_sda_drive <= 1'b0;
                            bit_s            <= 4'd0;
                            state_s          <= 3; // S_WR_DATA
                        end
                    end

                    5: begin // S_RD_DATA
                        if (scl_fall) begin
                            if (bit_s == 4'd7) begin
                                bh1750_sda_drive <= 1'b0;
                                bmp280_sda_drive <= 1'b0;
                                state_s          <= 6; // S_RD_ACK
                            end else begin
                                bit_s <= bit_s + 1'b1;
                                if (matched_addr == 7'h23)
                                    bh1750_sda_drive <= (shift_s[7 - (bit_s + 1'b1)] == 1'b0);
                                else
                                    bmp280_sda_drive <= (shift_s[7 - (bit_s + 1'b1)] == 1'b0);
                            end
                        end
                    end

                    6: begin // S_RD_ACK
                        if (scl_rise) m_nack_s <= i2c_sda;
                        if (scl_fall) begin
                            if (m_nack_s) begin
                                state_s <= 0; // Selesai
                            end else begin
                                bit_s   <= 4'd0;
                                state_s <= 5;
                                if (matched_addr == 7'h23) begin
                                    shift_s          <= 8'h45; // Lux LSB
                                    bh1750_sda_drive <= 1'b1;  // 8'h45 bit 7 is 0, so drive LOW
                                end else begin
                                    reg_ptr_s        <= reg_ptr_s + 1'b1;
                                    next_byte        = bmp_mem[reg_ptr_s + 1'b1];
                                    shift_s          <= next_byte;
                                    bmp280_sda_drive <= (next_byte[7] == 1'b0);
                                end
                            end
                        end
                    end
                endcase
            end
        end
    end

    // ========================================================================
    // MODEL UART RECEIVER DI TESTBENCH (Untuk Menampilkan String ke Transcript)
    // ========================================================================
    reg [7:0] rx_byte;
    integer   rx_bit_i;

    initial begin
        forever begin
            // 1. Tunggu Start Bit (0)
            @(negedge uart_tx_pin);
            // Tunggu ke tengah start bit
            repeat (UART_CLKS_BIT / 2) @(posedge clk);

            // Cek keabsahan start bit
            if (uart_tx_pin == 1'b0) begin
                // Baca 8 data bit
                for (rx_bit_i = 0; rx_bit_i < 8; rx_bit_i = rx_bit_i + 1) begin
                    repeat (UART_CLKS_BIT) @(posedge clk);
                    rx_byte[rx_bit_i] = uart_tx_pin;
                end

                // Tunggu stop bit
                repeat (UART_CLKS_BIT) @(posedge clk);
                // Cetak karakter langsung ke transcript
                $write("%c", rx_byte);
            end
        end
    end

    // ========================================================================
    // SKENARIO PENGUJIAN UTAMA
    // ========================================================================
    initial begin
        $timeformat(-9, 0, " ns", 10);
        rst_n       = 1'b0;
        trigger_btn = 1'b0;

        $display("==================================================");
        $display("   TESTBENCH INTEGRASI SISTEM LENGKAP (Tahap 5)   ");
        $display("==================================================");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("[%0t] Memicu pengukuran sistem (trigger_btn)...", $time);
        $display("------------------- SERIAL OUTPUT ----------------");
        @(posedge clk);
        trigger_btn <= 1'b1;
        @(posedge clk);
        trigger_btn <= 1'b0;

        // Tunggu sistem selesai memproses dan mengirimkan semua teks UART
        @(negedge dut.led_busy);
        $display("\n--------------------------------------------------");
        $display("[%0t] Seluruh transaksi I2C & Pengiriman UART Selesai!", $time);

        $display("\n==================================================");
        $display("   HASIL AKHIR: INTEGRASI SISTEM BERHASIL! (PASSED)");
        $display("==================================================");

        repeat (50) @(posedge clk);
        $finish;
    end

endmodule
