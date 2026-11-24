// ============================================================================
// Module    : top_module
// File      : top_module.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Top-Level Integrasi: I2C Master, BH1750, BMP280, UART TX
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

module top_module #(
    parameter I2C_HALF_PERIOD  = 250, // I2C 100 kHz @ 50 MHz
    parameter SENSOR_WAIT_CYC  = 50,  // Waktu tunggu konversi
    parameter UART_CLKS_BIT    = 434  // Baud 115200 @ 50 MHz
)(
    input  wire clk,
    input  wire rst_n,

    // Tombol pemicu pembacaan (atau bisa auto-periodic)
    input  wire trigger_btn,

    // Status LED
    output wire led_heartbeat,
    output reg  led_busy,
    output reg  led_error,

    // Pin Bus I2C Fisik (Bi-directional inout)
    inout  wire i2c_scl,
    inout  wire i2c_sda,

    // Pin Fisik Serial UART
    output wire uart_tx_pin
);

    // ========================================================================
    // HEARTBEAT LED (Blink sebagai tanda FPGA hidup)
    // ========================================================================
    reg [23:0] heartbeat_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) heartbeat_cnt <= 24'd0;
        else        heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign led_heartbeat = heartbeat_cnt[23];

    // ========================================================================
    // SINYAL I2C MASTER & ARBITRASE
    // ========================================================================
    reg         i2c_cmd_valid;
    reg  [2:0]  i2c_cmd;
    reg  [7:0]  i2c_data_in;
    wire [7:0]  i2c_data_out;
    wire        i2c_busy;
    wire        i2c_done;
    wire        i2c_ack_error;

    wire        scl_o;
    wire        sda_o;
    wire        sda_i;

    // Buffer Open-Drain I2C:
    // Jika 0, drive ke 0. Jika 1, lepas menjadi high-impedance (pull-up eksternal)
    assign i2c_scl = (scl_o == 1'b0) ? 1'b0 : 1'bz;
    assign i2c_sda = (sda_o == 1'b0) ? 1'b0 : 1'bz;
    assign sda_i   = i2c_sda;

    i2c_master #(
        .HALF_PERIOD(I2C_HALF_PERIOD)
    ) u_master (
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
    // DRIVER BH1750
    // ========================================================================
    reg         bh1750_start;
    wire        bh1750_busy;
    wire        bh1750_valid;
    wire [15:0] bh1750_lux;
    wire        bh1750_err;

    wire        bh1750_i2c_cmd_valid;
    wire [2:0]  bh1750_i2c_cmd;
    wire [7:0]  bh1750_i2c_din;

    bh1750_driver #(
        .CONV_WAIT_CYCLES(SENSOR_WAIT_CYC)
    ) u_bh1750 (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_meas    (bh1750_start),
        .busy          (bh1750_busy),
        .data_valid    (bh1750_valid),
        .data_lux      (bh1750_lux),
        .error         (bh1750_err),
        .i2c_cmd_valid (bh1750_i2c_cmd_valid),
        .i2c_cmd       (bh1750_i2c_cmd),
        .i2c_data_in   (bh1750_i2c_din),
        .i2c_data_out  (i2c_data_out),
        .i2c_busy      (i2c_busy),
        .i2c_done      (i2c_done),
        .i2c_ack_error (i2c_ack_error)
    );

    // ========================================================================
    // DRIVER BMP280
    // ========================================================================
    reg         bmp280_start;
    wire        bmp280_busy;
    wire        bmp280_valid;
    wire [19:0] bmp280_temp;
    wire [19:0] bmp280_press;
    wire        bmp280_chip_ok;
    wire        bmp280_err;

    wire        bmp280_i2c_cmd_valid;
    wire [2:0]  bmp280_i2c_cmd;
    wire [7:0]  bmp280_i2c_din;

    bmp280_driver #(
        .CONV_WAIT_CYCLES(SENSOR_WAIT_CYC)
    ) u_bmp280 (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_meas    (bmp280_start),
        .busy          (bmp280_busy),
        .data_valid    (bmp280_valid),
        .temp_raw      (bmp280_temp),
        .press_raw     (bmp280_press),
        .chip_id_ok    (bmp280_chip_ok),
        .error         (bmp280_err),
        .i2c_cmd_valid (bmp280_i2c_cmd_valid),
        .i2c_cmd       (bmp280_i2c_cmd),
        .i2c_data_in   (bmp280_i2c_din),
        .i2c_data_out  (i2c_data_out),
        .i2c_busy      (i2c_busy),
        .i2c_done      (i2c_done),
        .i2c_ack_error (i2c_ack_error)
    );

    // ========================================================================
    // UART TRANSMITTER
    // ========================================================================
    reg        uart_start;
    reg  [7:0] uart_data;
    wire       uart_busy;
    wire       uart_done;

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_BIT)
    ) u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (uart_start),
        .tx_data  (uart_data),
        .tx_busy  (uart_busy),
        .tx_done  (uart_done),
        .uart_txd (uart_tx_pin)
    );

    // ========================================================================
    // FUNGSI KONVERSI NIBBLE KE HEX ASCII
    // ========================================================================
    function [7:0] to_hex_ascii(input [3:0] nibble);
        begin
            if (nibble < 4'd10) to_hex_ascii = 8'd48 + nibble;        // '0' - '9'
            else                to_hex_ascii = 8'd65 + (nibble - 10); // 'A' - 'F'
        end
    endfunction

    // ========================================================================
    // TOP SCHEDULER & UART PACKET FORMATTER FSM
    // ========================================================================
    localparam [3:0] TOP_IDLE       = 4'd0;
    localparam [3:0] TOP_BH1750_RUN = 4'd1;
    localparam [3:0] TOP_BMP280_RUN = 4'd2;
    localparam [3:0] TOP_UART_START = 4'd3;
    localparam [3:0] TOP_UART_SEND  = 4'd4;
    localparam [3:0] TOP_UART_WAIT  = 4'd5;
    localparam [3:0] TOP_DONE       = 4'd6;

    reg [3:0]  top_state;
    reg [15:0] reg_lux;
    reg [19:0] reg_press;
    reg [19:0] reg_temp;
    reg [4:0]  char_idx;

    // Buffer 24 karakter string output: "L:xxxx P:xxxxx T:xxxxx\r\n"
    reg [7:0] tx_string [0:23];

    // Multiplexer I2C Bus Command ke Master
    reg active_sensor; // 0 = BH1750, 1 = BMP280

    always @(*) begin
        if (active_sensor == 1'b0) begin
            i2c_cmd_valid = bh1750_i2c_cmd_valid;
            i2c_cmd       = bh1750_i2c_cmd;
            i2c_data_in   = bh1750_i2c_din;
        end else begin
            i2c_cmd_valid = bmp280_i2c_cmd_valid;
            i2c_cmd       = bmp280_i2c_cmd;
            i2c_data_in   = bmp280_i2c_din;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_state     <= TOP_IDLE;
            bh1750_start  <= 1'b0;
            bmp280_start  <= 1'b0;
            uart_start    <= 1'b0;
            uart_data     <= 8'd0;
            active_sensor <= 1'b0;
            led_busy      <= 1'b0;
            led_error     <= 1'b0;
            reg_lux       <= 16'd0;
            reg_press     <= 20'd0;
            reg_temp      <= 20'd0;
            char_idx      <= 5'd0;
        end else begin
            bh1750_start <= 1'b0;
            bmp280_start <= 1'b0;
            uart_start   <= 1'b0;

            case (top_state)
                TOP_IDLE: begin
                    led_busy <= 1'b0;
                    if (trigger_btn) begin
                        led_busy      <= 1'b1;
                        led_error     <= 1'b0;
                        active_sensor <= 1'b0; // Pilih BH1750
                        bh1750_start  <= 1'b1;
                        top_state     <= TOP_BH1750_RUN;
                    end
                end

                // 1. Jalankan pembacaan BH1750
                TOP_BH1750_RUN: begin
                    if (bh1750_valid) begin
                        reg_lux       <= bh1750_lux;
                        active_sensor <= 1'b1; // Alihkan ke BMP280
                        bmp280_start  <= 1'b1;
                        top_state     <= TOP_BMP280_RUN;
                    end else if (bh1750_err) begin
                        led_error <= 1'b1;
                        top_state <= TOP_IDLE;
                    end
                end

                // 2. Jalankan pembacaan BMP280
                TOP_BMP280_RUN: begin
                    if (bmp280_valid) begin
                        reg_press <= bmp280_press;
                        reg_temp  <= bmp280_temp;
                        top_state <= TOP_UART_START;
                    end else if (bmp280_err) begin
                        led_error <= 1'b1;
                        top_state <= TOP_IDLE;
                    end
                end

                // 3. Format String Serial "L:xxxx P:xxxxx T:xxxxx\r\n"
                TOP_UART_START: begin
                    tx_string[0]  <= "L"; tx_string[1]  <= ":";
                    tx_string[2]  <= to_hex_ascii(reg_lux[15:12]);
                    tx_string[3]  <= to_hex_ascii(reg_lux[11:8]);
                    tx_string[4]  <= to_hex_ascii(reg_lux[7:4]);
                    tx_string[5]  <= to_hex_ascii(reg_lux[3:0]);
                    tx_string[6]  <= " ";

                    tx_string[7]  <= "P"; tx_string[8]  <= ":";
                    tx_string[9]  <= to_hex_ascii(reg_press[19:16]);
                    tx_string[10] <= to_hex_ascii(reg_press[15:12]);
                    tx_string[11] <= to_hex_ascii(reg_press[11:8]);
                    tx_string[12] <= to_hex_ascii(reg_press[7:4]);
                    tx_string[13] <= to_hex_ascii(reg_press[3:0]);
                    tx_string[14] <= " ";

                    tx_string[15] <= "T"; tx_string[16] <= ":";
                    tx_string[17] <= to_hex_ascii(reg_temp[19:16]);
                    tx_string[18] <= to_hex_ascii(reg_temp[15:12]);
                    tx_string[19] <= to_hex_ascii(reg_temp[11:8]);
                    tx_string[20] <= to_hex_ascii(reg_temp[7:4]);
                    tx_string[21] <= to_hex_ascii(reg_temp[3:0]);
                    tx_string[22] <= 8'h0D; // Carriage Return '\r'
                    tx_string[23] <= 8'h0A; // Line Feed '\n'

                    char_idx  <= 5'd0;
                    top_state <= TOP_UART_SEND;
                end

                // 4. Kirim karakter demi karakter via UART
                TOP_UART_SEND: begin
                    if (!uart_busy) begin
                        uart_data  <= tx_string[char_idx];
                        uart_start <= 1'b1;
                        top_state  <= TOP_UART_WAIT;
                    end
                end

                TOP_UART_WAIT: begin
                    if (uart_done) begin
                        if (char_idx == 5'd23) begin
                            top_state <= TOP_DONE;
                        end else begin
                            char_idx  <= char_idx + 1'b1;
                            top_state <= TOP_UART_SEND;
                        end
                    end
                end

                TOP_DONE: begin
                    led_busy  <= 1'b0;
                    top_state <= TOP_IDLE;
                end

                default: top_state <= TOP_IDLE;
            endcase
        end
    end

endmodule
