// ============================================================================
// Module    : i2c_master
// File      : i2c_master.v
// Project   : FPGA I2C Sensor Library
// Purpose   : I2C Master Controller menggunakan FSM
//
// Deskripsi :
//   Module ini mengimplementasikan I2C Master yang bisa:
//   - Menghasilkan kondisi START dan STOP
//   - Mengirim byte (8 bit) dan menerima ACK dari slave
//   - Menerima byte (8 bit) dan mengirim ACK/NACK ke slave
//   - Mendukung Repeated START untuk transaksi write-then-read
//
//   Konsep open-drain:
//     sda_o = 1 → lepas jalur (pull-up membuat HIGH)
//     sda_o = 0 → tarik jalur ke LOW
//     Sama untuk scl_o.
//
//   Cara pakai (dari sensor driver):
//     1. Set cmd dan data_in, lalu pulse cmd_valid selama 1 clock cycle
//     2. Tunggu sinyal done (pulse 1 cycle)
//     3. Baca data_out (untuk read) atau ack_error (untuk write)
//     4. Ulangi untuk command berikutnya
//
// Parameter :
//   HALF_PERIOD - Jumlah clock cycle untuk setengah periode SCL.
//                 Contoh: Untuk clock 50MHz dan I2C 100kHz:
//                 SCL period = 10us, half = 5us, HALF_PERIOD = 250
//                 Untuk simulasi: gunakan nilai kecil (misal 4)
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

module i2c_master #(
    parameter HALF_PERIOD = 250
)(
    input  wire       clk,       // System clock
    input  wire       rst_n,     // Active-low reset

    // === Command Interface ===
    input  wire       cmd_valid, // Pulse 1 cycle: mulai eksekusi command
    input  wire [2:0] cmd,       // Jenis command (lihat localparam di bawah)
    input  wire [7:0] data_in,   // Data yang akan dikirim (untuk CMD_WRITE)

    output reg  [7:0] data_out,  // Data yang diterima (dari CMD_READ_ACK/NACK)
    output reg        busy,      // 1 = sedang memproses command
    output reg        done,      // Pulse 1 cycle: command selesai
    output reg        ack_error, // 1 = slave mengirim NACK (setelah CMD_WRITE)

    // === I2C Bus (Open-Drain) ===
    // 1 = lepas jalur (HIGH via pull-up)
    // 0 = tarik jalur ke LOW
    output reg        scl_o,     // SCL output
    output reg        sda_o,     // SDA output
    input  wire       sda_i      // SDA input (membaca dari bus)
);

    // ========================================================================
    // COMMAND DEFINITIONS
    // ========================================================================
    // Ini adalah "perintah" yang bisa diberikan ke I2C Master.
    // Sensor driver akan menggunakan command ini secara berurutan.
    //
    // Contoh urutan untuk menulis 1 byte ke sensor:
    //   CMD_START → CMD_WRITE(addr+W) → CMD_WRITE(data) → CMD_STOP
    //
    // Contoh urutan untuk membaca 2 byte dari sensor:
    //   CMD_START → CMD_WRITE(addr+R) → CMD_READ_ACK → CMD_READ_NACK → CMD_STOP
    // ========================================================================
    localparam [2:0] CMD_START     = 3'd1; // Kirim START condition
    localparam [2:0] CMD_WRITE     = 3'd2; // Kirim 8 bit, terima ACK dari slave
    localparam [2:0] CMD_READ_ACK  = 3'd3; // Terima 8 bit, kirim ACK ke slave
    localparam [2:0] CMD_READ_NACK = 3'd4; // Terima 8 bit, kirim NACK ke slave
    localparam [2:0] CMD_STOP      = 3'd5; // Kirim STOP condition

    // ========================================================================
    // FSM STATE DEFINITIONS
    // ========================================================================
    //
    // Diagram FSM (simplified):
    //
    //  IDLE ──┬── CMD_START ──→ START_0 → START_1 → START_2 → START_3 → IDLE
    //         │
    //         ├── CMD_WRITE ──→ WRITE_LOW → WRITE_HIGH ─┐ (×8 bit)
    //         │                      ↑──────────────────┘
    //         │                      └→ ACK_LOW → ACK_HIGH → IDLE
    //         │
    //         ├── CMD_READ  ──→ READ_LOW → READ_HIGH ───┐ (×8 bit)
    //         │                      ↑──────────────────┘
    //         │                      └→ RACK_LOW → RACK_HIGH → IDLE
    //         │
    //         └── CMD_STOP  ──→ STOP_0 → STOP_1 → STOP_2 → IDLE
    //
    // Setiap state berlangsung selama HALF_PERIOD clock cycle.
    // ========================================================================
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_START_0    = 4'd1;  // Lepas SDA, SCL masih LOW
    localparam [3:0] ST_START_1    = 4'd2;  // Lepas SCL → keduanya HIGH
    localparam [3:0] ST_START_2    = 4'd3;  // Tarik SDA LOW → START!
    localparam [3:0] ST_START_3    = 4'd4;  // Tarik SCL LOW → siap kirim data
    localparam [3:0] ST_WRITE_LOW  = 4'd5;  // SCL LOW, set SDA ke nilai bit
    localparam [3:0] ST_WRITE_HIGH = 4'd6;  // SCL HIGH, slave membaca SDA
    localparam [3:0] ST_ACK_LOW    = 4'd7;  // SCL LOW, lepas SDA untuk slave ACK
    localparam [3:0] ST_ACK_HIGH   = 4'd8;  // SCL HIGH, baca ACK/NACK dari slave
    localparam [3:0] ST_READ_LOW   = 4'd9;  // SCL LOW, lepas SDA untuk slave kirim
    localparam [3:0] ST_READ_HIGH  = 4'd10; // SCL HIGH, baca bit dari slave
    localparam [3:0] ST_RACK_LOW   = 4'd11; // SCL LOW, set SDA untuk ACK/NACK
    localparam [3:0] ST_RACK_HIGH  = 4'd12; // SCL HIGH, slave baca ACK/NACK kita
    localparam [3:0] ST_STOP_0     = 4'd13; // SDA LOW, SCL LOW (persiapan)
    localparam [3:0] ST_STOP_1     = 4'd14; // SDA LOW, SCL HIGH
    localparam [3:0] ST_STOP_2     = 4'd15; // SDA HIGH, SCL HIGH → STOP!

    // ========================================================================
    // INTERNAL REGISTERS
    // ========================================================================
    reg [3:0]  state;      // State FSM saat ini
    reg [7:0]  shift_reg;  // Shift register untuk kirim/terima data
    reg [3:0]  bit_cnt;    // Penghitung bit (7 downto 0)
    reg        send_nack;  // 0 = kirim ACK, 1 = kirim NACK

    // Clock divider: menghitung sampai HALF_PERIOD - 1
    // Lebar register dihitung otomatis menggunakan $clog2
    reg [$clog2(HALF_PERIOD)-1:0] clk_cnt;

    // Tick: sinyal yang aktif 1 cycle setiap HALF_PERIOD
    // Setiap state FSM menunggu tick sebelum berpindah state
    wire tick = (clk_cnt == HALF_PERIOD - 1);

    // ========================================================================
    // CLOCK DIVIDER
    // ========================================================================
    // Counter berjalan saat TIDAK di IDLE.
    // Reset ke 0 saat di IDLE atau saat tick tercapai.
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_cnt <= 0;
        else if (state == ST_IDLE)
            clk_cnt <= 0;
        else if (tick)
            clk_cnt <= 0;
        else
            clk_cnt <= clk_cnt + 1;
    end

    // ========================================================================
    // MAIN FSM
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset semua register ke kondisi awal
            state     <= ST_IDLE;
            scl_o     <= 1'b1;   // Lepas SCL (bus idle = HIGH)
            sda_o     <= 1'b1;   // Lepas SDA (bus idle = HIGH)
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;
            bit_cnt   <= 4'd0;
            shift_reg <= 8'd0;
            data_out  <= 8'd0;
            send_nack <= 1'b0;
        end else begin
            // Default: done hanya aktif 1 cycle (pulse)
            done <= 1'b0;

            case (state)
                // ============================================================
                // IDLE: Menunggu command dari sensor driver
                // ============================================================
                ST_IDLE: begin
                    if (cmd_valid) begin
                        busy <= 1'b1;
                        case (cmd)
                            CMD_START: begin
                                sda_o <= 1'b1;        // Lepas SDA
                                state <= ST_START_0;
                            end
                            CMD_WRITE: begin
                                shift_reg <= data_in;  // Simpan data yang akan dikirim
                                bit_cnt   <= 4'd7;     // Mulai dari bit 7 (MSB)
                                sda_o     <= data_in[7];// Set bit pertama
                                scl_o     <= 1'b0;     // SCL LOW
                                state     <= ST_WRITE_LOW;
                            end
                            CMD_READ_ACK: begin
                                bit_cnt   <= 4'd7;
                                send_nack <= 1'b0;     // Akan kirim ACK
                                sda_o     <= 1'b1;     // Lepas SDA (slave yang kirim)
                                scl_o     <= 1'b0;
                                state     <= ST_READ_LOW;
                            end
                            CMD_READ_NACK: begin
                                bit_cnt   <= 4'd7;
                                send_nack <= 1'b1;     // Akan kirim NACK
                                sda_o     <= 1'b1;
                                scl_o     <= 1'b0;
                                state     <= ST_READ_LOW;
                            end
                            CMD_STOP: begin
                                sda_o <= 1'b0;         // Pastikan SDA LOW
                                scl_o <= 1'b0;         // Pastikan SCL LOW
                                state <= ST_STOP_0;
                            end
                            default: busy <= 1'b0;
                        endcase
                    end
                end

                // ============================================================
                // START SEQUENCE (4 state, masing-masing HALF_PERIOD cycle)
                // ============================================================
                // Mendukung baik START pertama maupun Repeated START.
                //
                // Timeline:
                //   START_0: SDA=1, SCL=? (lepas SDA dulu saat SCL LOW)
                //   START_1: SDA=1, SCL=1 (keduanya HIGH, seperti idle)
                //   START_2: SDA=0, SCL=1 (SDA turun saat SCL HIGH = START!)
                //   START_3: SDA=0, SCL=0 (siap untuk kirim data)
                // ============================================================
                ST_START_0: begin
                    if (tick) begin
                        scl_o <= 1'b1;     // Lepas SCL → HIGH
                        state <= ST_START_1;
                    end
                end

                ST_START_1: begin
                    if (tick) begin
                        sda_o <= 1'b0;     // Tarik SDA → LOW (START condition!)
                        state <= ST_START_2;
                    end
                end

                ST_START_2: begin
                    if (tick) begin
                        scl_o <= 1'b0;     // Tarik SCL → LOW (siap kirim data)
                        state <= ST_START_3;
                    end
                end

                ST_START_3: begin
                    if (tick) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                // ============================================================
                // WRITE SEQUENCE (kirim 8 bit + terima ACK)
                // ============================================================
                // Untuk setiap bit:
                //   WRITE_LOW:  SCL=0, SDA=bit_value (setup data)
                //   WRITE_HIGH: SCL=1, slave membaca SDA (sample data)
                //
                // Data dikirim MSB first (bit 7 dulu, bit 0 terakhir).
                // Setelah 8 bit, masuk ke ACK phase.
                // ============================================================
                ST_WRITE_LOW: begin
                    if (tick) begin
                        scl_o <= 1'b1;     // SCL naik → slave membaca SDA
                        state <= ST_WRITE_HIGH;
                    end
                end

                ST_WRITE_HIGH: begin
                    if (tick) begin
                        scl_o <= 1'b0;     // SCL turun
                        if (bit_cnt == 0) begin
                            // Semua 8 bit sudah dikirim → masuk ACK phase
                            sda_o <= 1'b1; // Lepas SDA agar slave bisa ACK
                            state <= ST_ACK_LOW;
                        end else begin
                            // Masih ada bit yang perlu dikirim
                            bit_cnt   <= bit_cnt - 1'b1;
                            shift_reg <= {shift_reg[6:0], 1'b0}; // Shift kiri
                            sda_o     <= shift_reg[6]; // Bit berikutnya
                            state     <= ST_WRITE_LOW;
                        end
                    end
                end

                // ACK phase: slave merespons
                ST_ACK_LOW: begin
                    // SCL LOW, SDA dilepas → slave yang mengendalikan SDA
                    if (tick) begin
                        scl_o <= 1'b1;     // SCL naik → baca ACK dari slave
                        state <= ST_ACK_HIGH;
                    end
                end

                ST_ACK_HIGH: begin
                    if (tick) begin
                        // Baca SDA: 0 = ACK (berhasil), 1 = NACK (gagal)
                        ack_error <= sda_i;
                        scl_o     <= 1'b0;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= ST_IDLE;
                    end
                end

                // ============================================================
                // READ SEQUENCE (terima 8 bit + kirim ACK/NACK)
                // ============================================================
                // Untuk setiap bit:
                //   READ_LOW:  SCL=0, SDA dilepas (slave yang mengendalikan)
                //   READ_HIGH: SCL=1, baca SDA dari slave
                //
                // Data diterima MSB first. Setelah 8 bit, kirim ACK atau NACK.
                // ============================================================
                ST_READ_LOW: begin
                    if (tick) begin
                        scl_o <= 1'b1;     // SCL naik → baca SDA dari slave
                        state <= ST_READ_HIGH;
                    end
                end

                ST_READ_HIGH: begin
                    if (tick) begin
                        // Geser bit yang dibaca ke shift register
                        shift_reg <= {shift_reg[6:0], sda_i};
                        scl_o     <= 1'b0; // SCL turun
                        if (bit_cnt == 0) begin
                            // Semua 8 bit sudah diterima
                            data_out <= {shift_reg[6:0], sda_i};
                            sda_o    <= send_nack; // 0=ACK, 1=NACK
                            state    <= ST_RACK_LOW;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                            state   <= ST_READ_LOW;
                        end
                    end
                end

                // RACK phase: master merespons ke slave
                ST_RACK_LOW: begin
                    // SCL LOW, SDA = ACK(0) atau NACK(1)
                    if (tick) begin
                        scl_o <= 1'b1;     // SCL naik → slave baca ACK/NACK kita
                        state <= ST_RACK_HIGH;
                    end
                end

                ST_RACK_HIGH: begin
                    if (tick) begin
                        scl_o <= 1'b0;
                        sda_o <= 1'b1;     // Lepas SDA
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                // ============================================================
                // STOP SEQUENCE (3 state)
                // ============================================================
                // Timeline:
                //   STOP_0: SDA=0, SCL=0 (pastikan SDA LOW)
                //   STOP_1: SDA=0, SCL=1 (SCL naik duluan)
                //   STOP_2: SDA=1, SCL=1 (SDA naik saat SCL HIGH = STOP!)
                // ============================================================
                ST_STOP_0: begin
                    if (tick) begin
                        scl_o <= 1'b1;     // Lepas SCL → HIGH
                        state <= ST_STOP_1;
                    end
                end

                ST_STOP_1: begin
                    if (tick) begin
                        sda_o <= 1'b1;     // Lepas SDA → HIGH (STOP condition!)
                        state <= ST_STOP_2;
                    end
                end

                ST_STOP_2: begin
                    if (tick) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
