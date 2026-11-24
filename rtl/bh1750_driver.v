// ============================================================================
// Module    : bh1750_driver
// File      : bh1750_driver.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Driver Sensor Cahaya BH1750 berbasis FSM
//
// Deskripsi :
//   Modul ini mengendalikan urutan inisialisasi dan pembacaan sensor BH1750:
//   1. Power ON (Opcode: 0x01)
//   2. Set Continuously H-Resolution Mode (Opcode: 0x10)
//   3. Menunggu waktu konversi sensor (parameter CONV_WAIT_CYCLES)
//   4. Membaca 2 byte data intensitas cahaya (High Byte & Low Byte)
//   5. Menggabungkan data menjadi data_raw 16-bit
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

module bh1750_driver #(
    // Waktu tunggu konversi sensor.
    // Datasheet: typical 120ms, max 180ms.
    // Untuk simulasi cepat, kita gunakan nilai kecil (misal 50 cycle).
    parameter CONV_WAIT_CYCLES = 50
)(
    input  wire        clk,
    input  wire        rst_n,

    // Interface Pengendali / User
    input  wire        start_meas,   // Pulsa 1 cycle: mulai siklus pembacaan
    output reg         busy,         // 1 = sedang melakukan transaksi
    output reg         data_valid,   // Pulsa 1 cycle: data_lux siap dibaca
    output reg  [15:0] data_lux,     // Raw 16-bit data intensitas cahaya
    output reg         error,        // 1 = terjadi error I2C (NACK)

    // Interface ke I2C Master Controller
    output reg         i2c_cmd_valid,
    output reg  [2:0]  i2c_cmd,
    output reg  [7:0]  i2c_data_in,
    input  wire [7:0]  i2c_data_out,
    input  wire        i2c_busy,
    input  wire        i2c_done,
    input  wire        i2c_ack_error
);

    // ========================================================================
    // KONSTANTA I2C MASTER COMMAND
    // ========================================================================
    localparam [2:0] CMD_START     = 3'd1;
    localparam [2:0] CMD_WRITE     = 3'd2;
    localparam [2:0] CMD_READ_ACK  = 3'd3;
    localparam [2:0] CMD_READ_NACK = 3'd4;
    localparam [2:0] CMD_STOP      = 3'd5;

    // ========================================================================
    // KONSTANTA BH1750
    // ========================================================================
    localparam [7:0] BH1750_ADDR_W = 8'h46; // 0x23 << 1 | 0
    localparam [7:0] BH1750_ADDR_R = 8'h47; // 0x23 << 1 | 1
    localparam [7:0] OP_POWER_ON   = 8'h01; // Power On
    localparam [7:0] OP_H_MODE     = 8'h10; // Continuous H-Resolution Mode

    // ========================================================================
    // STATE FSM
    // ========================================================================
    localparam [4:0] ST_IDLE          = 5'd0;
    
    // Tahap 1: Power ON
    localparam [4:0] ST_PWR_START     = 5'd1;
    localparam [4:0] ST_PWR_ADDR      = 5'd2;
    localparam [4:0] ST_PWR_CMD       = 5'd3;
    localparam [4:0] ST_PWR_STOP      = 5'd4;

    // Tahap 2: Set Mode Pengukuran
    localparam [4:0] ST_MODE_START    = 5'd5;
    localparam [4:0] ST_MODE_ADDR     = 5'd6;
    localparam [4:0] ST_MODE_CMD      = 5'd7;
    localparam [4:0] ST_MODE_STOP     = 5'd8;

    // Tahap 3: Tunggu Waktu Pengukuran Selesai
    localparam [4:0] ST_WAIT_CONV     = 5'd9;

    // Tahap 4: Baca Data 2-Byte
    localparam [4:0] ST_READ_START    = 5'd10;
    localparam [4:0] ST_READ_ADDR     = 5'd11;
    localparam [4:0] ST_READ_MSB      = 5'd12;
    localparam [4:0] ST_READ_LSB      = 5'd13;
    localparam [4:0] ST_READ_STOP     = 5'd14;

    localparam [4:0] ST_DONE          = 5'd15;

    // ========================================================================
    // REGISTER INTERNAL
    // ========================================================================
    reg [4:0]  state;
    reg [7:0]  msb_data;
    reg [$clog2(CONV_WAIT_CYCLES+1)-1:0] wait_cnt;

    // ========================================================================
    // LOGIKA FSM DRIVER
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            busy          <= 1'b0;
            data_valid    <= 1'b0;
            data_lux      <= 16'd0;
            error         <= 1'b0;
            msb_data      <= 8'd0;
            wait_cnt      <= 0;
            i2c_cmd_valid <= 1'b0;
            i2c_cmd       <= 3'd0;
            i2c_data_in   <= 8'd0;
        end else begin
            // Pulsa default 1 siklus
            i2c_cmd_valid <= 1'b0;
            data_valid    <= 1'b0;

            case (state)
                // ------------------------------------------------------------
                // 0. IDLE: Menunggu trigger mulai pengukuran
                // ------------------------------------------------------------
                ST_IDLE: begin
                    if (start_meas) begin
                        busy  <= 1'b1;
                        error <= 1'b0;
                        
                        // Kirim START pertama untuk Power On
                        i2c_cmd       <= CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_PWR_START;
                    end
                end

                // ------------------------------------------------------------
                // 1. POWER ON SEQUENCE (START -> Addr_W -> 0x01 -> STOP)
                // ------------------------------------------------------------
                ST_PWR_START: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BH1750_ADDR_W;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_PWR_ADDR;
                    end
                end

                ST_PWR_ADDR: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1;
                            state <= ST_IDLE;
                            busy  <= 1'b0;
                        end else begin
                            i2c_cmd       <= CMD_WRITE;
                            i2c_data_in   <= OP_POWER_ON;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_PWR_CMD;
                        end
                    end
                end

                ST_PWR_CMD: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1;
                            state <= ST_IDLE;
                            busy  <= 1'b0;
                        end else begin
                            i2c_cmd       <= CMD_STOP;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_PWR_STOP;
                        end
                    end
                end

                ST_PWR_STOP: begin
                    if (i2c_done) begin
                        // Lanjut ke konfigurasi Mode
                        i2c_cmd       <= CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_MODE_START;
                    end
                end

                // ------------------------------------------------------------
                // 2. SET MODE SEQUENCE (START -> Addr_W -> 0x10 -> STOP)
                // ------------------------------------------------------------
                ST_MODE_START: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BH1750_ADDR_W;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_MODE_ADDR;
                    end
                end

                ST_MODE_ADDR: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1;
                            state <= ST_IDLE;
                            busy  <= 1'b0;
                        end else begin
                            i2c_cmd       <= CMD_WRITE;
                            i2c_data_in   <= OP_H_MODE;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_MODE_CMD;
                        end
                    end
                end

                ST_MODE_CMD: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1;
                            state <= ST_IDLE;
                            busy  <= 1'b0;
                        end else begin
                            i2c_cmd       <= CMD_STOP;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_MODE_STOP;
                        end
                    end
                end

                ST_MODE_STOP: begin
                    if (i2c_done) begin
                        wait_cnt <= 0;
                        state    <= ST_WAIT_CONV;
                    end
                end

                // ------------------------------------------------------------
                // 3. TUNGGU WAKTU KONVERSI SENSOR
                // ------------------------------------------------------------
                ST_WAIT_CONV: begin
                    if (wait_cnt == CONV_WAIT_CYCLES - 1) begin
                        // Konversi selesai, mulai transaksi READ
                        i2c_cmd       <= CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_READ_START;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                // ------------------------------------------------------------
                // 4. READ DATA SEQUENCE (START -> Addr_R -> Read MSB (ACK) -> Read LSB (NACK) -> STOP)
                // ------------------------------------------------------------
                ST_READ_START: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BH1750_ADDR_R;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_READ_ADDR;
                    end
                end

                ST_READ_ADDR: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1;
                            state <= ST_IDLE;
                            busy  <= 1'b0;
                        end else begin
                            // Minta High Byte (Master beri ACK)
                            i2c_cmd       <= CMD_READ_ACK;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_READ_MSB;
                        end
                    end
                end

                ST_READ_MSB: begin
                    if (i2c_done) begin
                        msb_data      <= i2c_data_out; // Simpan High Byte
                        // Minta Low Byte (Master beri NACK karena ini byte terakhir)
                        i2c_cmd       <= CMD_READ_NACK;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_READ_LSB;
                    end
                end

                ST_READ_LSB: begin
                    if (i2c_done) begin
                        // Gabungkan High Byte & Low Byte
                        data_lux      <= {msb_data, i2c_data_out};
                        // Kirim STOP
                        i2c_cmd       <= CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_READ_STOP;
                    end
                end

                ST_READ_STOP: begin
                    if (i2c_done) begin
                        data_valid <= 1'b1; // Tandai data siap
                        busy       <= 1'b0;
                        state      <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
