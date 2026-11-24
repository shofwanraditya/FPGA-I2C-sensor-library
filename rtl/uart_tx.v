// ============================================================================
// Module    : uart_tx
// File      : uart_tx.v
// Project   : FPGA I2C Sensor Library
// Purpose   : UART Transmitter (8-N-1: 8 data bits, No parity, 1 stop bit)
//
// Parameter :
//   CLKS_PER_BIT = Frekuensi Clock / Baud Rate
//   Contoh: Clock 50 MHz, Baud 115200 -> 50_000_000 / 115_200 = 434
//   Untuk simulasi cepat di testbench, gunakan nilai kecil (misal 4 atau 8).
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

module uart_tx #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire       clk,
    input  wire       rst_n,

    // Interface Pengendali
    input  wire       tx_start,  // Pulsa 1 cycle: mulai kirim 1 byte
    input  wire [7:0] tx_data,   // Byte data ASCII yang akan dikirim
    output reg        tx_busy,   // 1 = sedang mengirim
    output reg        tx_done,   // Pulsa 1 cycle: pengiriman 1 byte selesai

    // Pin Fisik Serial
    output reg        uart_txd   // Pin TX serial (Idle = 1)
);

    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_START = 3'd1;
    localparam [2:0] S_DATA  = 3'd2;
    localparam [2:0] S_STOP  = 3'd3;
    localparam [2:0] S_DONE  = 3'd4;

    reg [2:0]  state;
    reg [$clog2(CLKS_PER_BIT+1)-1:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            uart_txd <= 1'b1; // Idle line is HIGH
            tx_busy  <= 1'b0;
            tx_done  <= 1'b0;
            clk_cnt  <= 0;
            bit_idx  <= 3'd0;
            data_buf <= 8'd0;
        end else begin
            tx_done <= 1'b0; // Default pulse

            case (state)
                S_IDLE: begin
                    uart_txd <= 1'b1;
                    clk_cnt  <= 0;
                    bit_idx  <= 3'd0;
                    if (tx_start) begin
                        tx_busy  <= 1'b1;
                        data_buf <= tx_data;
                        state    <= S_START;
                    end else begin
                        tx_busy  <= 1'b0;
                    end
                end

                // Kirim START Bit (0)
                S_START: begin
                    uart_txd <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // Kirim 8 Data Bit (LSB First: bit 0 s/d bit 7)
                S_DATA: begin
                    uart_txd <= data_buf[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // Kirim STOP Bit (1)
                S_STOP: begin
                    uart_txd <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= S_DONE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DONE: begin
                    tx_done <= 1'b1;
                    tx_busy <= 1'b0;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
