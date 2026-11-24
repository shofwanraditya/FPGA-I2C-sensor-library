// ============================================================================
// Module    : bmp280_driver
// File      : bmp280_driver.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Driver Sensor Tekanan & Temperatur BMP280 berbasis FSM
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

module bmp280_driver #(
    parameter CONV_WAIT_CYCLES = 50
)(
    input  wire        clk,
    input  wire        rst_n,

    // Interface Pengendali / User
    input  wire        start_meas,     // Pulsa 1 cycle: mulai siklus inisialisasi / baca
    output reg         busy,           // 1 = sedang bertransaksi
    output reg         data_valid,     // Pulsa 1 cycle: data suhu & tekanan siap
    output reg  [19:0] temp_raw,       // Raw ADC 20-bit Temperature
    output reg  [19:0] press_raw,      // Raw ADC 20-bit Pressure
    output reg         chip_id_ok,     // 1 = Sensor terverifikasi (Chip ID == 0x58)
    output reg         error,          // 1 = terjadi error I2C (NACK)

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
    // KONSTANTA BMP280 (SDO = GND -> 0x76)
    // ========================================================================
    localparam [7:0] BMP280_ADDR_W = 8'hEC; // 0x76 << 1 | 0
    localparam [7:0] BMP280_ADDR_R = 8'hED; // 0x76 << 1 | 1
    
    localparam [7:0] REG_ID        = 8'hD0;
    localparam [7:0] EXPECTED_ID   = 8'h58;
    localparam [7:0] REG_CTRL_MEAS = 8'hF4;
    localparam [7:0] VAL_CTRL_MEAS = 8'h27; // osrs_t x1, osrs_p x1, Normal Mode
    localparam [7:0] REG_PRESS_MSB = 8'hF7;

    // ========================================================================
    // FSM STATES
    // ========================================================================
    localparam [4:0] ST_IDLE          = 5'd0;

    // Tahap 1: Verifikasi Chip ID
    localparam [4:0] ST_ID_START      = 5'd1;
    localparam [4:0] ST_ID_ADDR_W     = 5'd2;
    localparam [4:0] ST_ID_REG        = 5'd3;
    localparam [4:0] ST_ID_RESTART    = 5'd4;
    localparam [4:0] ST_ID_ADDR_R     = 5'd5;
    localparam [4:0] ST_ID_READ       = 5'd6;
    localparam [4:0] ST_ID_STOP       = 5'd7;

    // Tahap 2: Konfigurasi Mode Sensor
    localparam [4:0] ST_CFG_START     = 5'd8;
    localparam [4:0] ST_CFG_ADDR_W    = 5'd9;
    localparam [4:0] ST_CFG_REG       = 5'd10;
    localparam [4:0] ST_CFG_VAL       = 5'd11;
    localparam [4:0] ST_CFG_STOP      = 5'd12;

    // Tahap 3: Tunggu Waktu Pengukuran
    localparam [4:0] ST_WAIT_CONV     = 5'd13;

    // Tahap 4: Pembacaan Burst 6-Byte (0xF7 - 0xFC)
    localparam [4:0] ST_DATA_START    = 5'd14;
    localparam [4:0] ST_DATA_ADDR_W   = 5'd15;
    localparam [4:0] ST_DATA_REG      = 5'd16;
    localparam [4:0] ST_DATA_RESTART  = 5'd17;
    localparam [4:0] ST_DATA_ADDR_R   = 5'd18;
    localparam [4:0] ST_RD_P_MSB      = 5'd19;
    localparam [4:0] ST_RD_P_LSB      = 5'd20;
    localparam [4:0] ST_RD_P_XLSB     = 5'd21;
    localparam [4:0] ST_RD_T_MSB      = 5'd22;
    localparam [4:0] ST_RD_T_LSB      = 5'd23;
    localparam [4:0] ST_RD_T_XLSB     = 5'd24;
    localparam [4:0] ST_DATA_STOP     = 5'd25;

    localparam [4:0] ST_DONE          = 5'd26;

    // ========================================================================
    // INTERNAL REGISTERS
    // ========================================================================
    reg [4:0]  state;
    reg [$clog2(CONV_WAIT_CYCLES+1)-1:0] wait_cnt;

    // Penampung sementara data burst
    reg [7:0] p_msb, p_lsb, p_xlsb;
    reg [7:0] t_msb, t_lsb;

    // ========================================================================
    // LOGIKA FSM BMP280
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            busy          <= 1'b0;
            data_valid    <= 1'b0;
            chip_id_ok    <= 1'b0;
            error         <= 1'b0;
            temp_raw      <= 20'd0;
            press_raw     <= 20'd0;
            wait_cnt      <= 0;
            i2c_cmd_valid <= 1'b0;
            i2c_cmd       <= 3'd0;
            i2c_data_in   <= 8'd0;
            p_msb         <= 8'd0;
            p_lsb         <= 8'd0;
            p_xlsb        <= 8'd0;
            t_msb         <= 8'd0;
            t_lsb         <= 8'd0;
        end else begin
            i2c_cmd_valid <= 1'b0;
            data_valid    <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start_meas) begin
                        busy       <= 1'b1;
                        error      <= 1'b0;
                        chip_id_ok <= 1'b0;

                        // Mulai dengan membaca Chip ID
                        i2c_cmd       <= CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_ID_START;
                    end
                end

                // ------------------------------------------------------------
                // 1. CEK CHIP ID
                // ------------------------------------------------------------
                ST_ID_START: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BMP280_ADDR_W;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_ID_ADDR_W;
                    end
                end

                ST_ID_ADDR_W: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            i2c_cmd       <= CMD_WRITE;
                            i2c_data_in   <= REG_ID;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_ID_REG;
                        end
                    end
                end

                ST_ID_REG: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            // Repeated START untuk membaca ID
                            i2c_cmd       <= CMD_START;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_ID_RESTART;
                        end
                    end
                end

                ST_ID_RESTART: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BMP280_ADDR_R;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_ID_ADDR_R;
                    end
                end

                ST_ID_ADDR_R: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            // Baca 1 byte ID dengan NACK
                            i2c_cmd       <= CMD_READ_NACK;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_ID_READ;
                        end
                    end
                end

                ST_ID_READ: begin
                    if (i2c_done) begin
                        if (i2c_data_out == EXPECTED_ID)
                            chip_id_ok <= 1'b1;
                        else
                            chip_id_ok <= 1'b0;

                        i2c_cmd       <= CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_ID_STOP;
                    end
                end

                ST_ID_STOP: begin
                    if (i2c_done) begin
                        // Lanjut ke konfigurasi sensor
                        i2c_cmd       <= CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_CFG_START;
                    end
                end

                // ------------------------------------------------------------
                // 2. KONFIGURASI SENSOR (ctrl_meas = 0x27)
                // ------------------------------------------------------------
                ST_CFG_START: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BMP280_ADDR_W;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_CFG_ADDR_W;
                    end
                end

                ST_CFG_ADDR_W: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            i2c_cmd       <= CMD_WRITE;
                            i2c_data_in   <= REG_CTRL_MEAS;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_CFG_REG;
                        end
                    end
                end

                ST_CFG_REG: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            i2c_cmd       <= CMD_WRITE;
                            i2c_data_in   <= VAL_CTRL_MEAS;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_CFG_VAL;
                        end
                    end
                end

                ST_CFG_VAL: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            i2c_cmd       <= CMD_STOP;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_CFG_STOP;
                        end
                    end
                end

                ST_CFG_STOP: begin
                    if (i2c_done) begin
                        wait_cnt <= 0;
                        state    <= ST_WAIT_CONV;
                    end
                end

                // ------------------------------------------------------------
                // 3. TUNGGU KONVERSI
                // ------------------------------------------------------------
                ST_WAIT_CONV: begin
                    if (wait_cnt == CONV_WAIT_CYCLES - 1) begin
                        // Mulai pembacaan burst data tekanan dan temperatur
                        i2c_cmd       <= CMD_START;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_DATA_START;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                // ------------------------------------------------------------
                // 4. PEMBACAAN BURST DATA 6-BYTE (0xF7 - 0xFC)
                // ------------------------------------------------------------
                ST_DATA_START: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BMP280_ADDR_W;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_DATA_ADDR_W;
                    end
                end

                ST_DATA_ADDR_W: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            i2c_cmd       <= CMD_WRITE;
                            i2c_data_in   <= REG_PRESS_MSB; // Mulai dari 0xF7
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_DATA_REG;
                        end
                    end
                end

                ST_DATA_REG: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            // Repeated START untuk switch ke Mode Read
                            i2c_cmd       <= CMD_START;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_DATA_RESTART;
                        end
                    end
                end

                ST_DATA_RESTART: begin
                    if (i2c_done) begin
                        i2c_cmd       <= CMD_WRITE;
                        i2c_data_in   <= BMP280_ADDR_R;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_DATA_ADDR_R;
                    end
                end

                ST_DATA_ADDR_R: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            error <= 1'b1; busy <= 1'b0; state <= ST_IDLE;
                        end else begin
                            // Byte 1: Press MSB (ACK)
                            i2c_cmd       <= CMD_READ_ACK;
                            i2c_cmd_valid <= 1'b1;
                            state         <= ST_RD_P_MSB;
                        end
                    end
                end

                ST_RD_P_MSB: begin
                    if (i2c_done) begin
                        p_msb         <= i2c_data_out;
                        // Byte 2: Press LSB (ACK)
                        i2c_cmd       <= CMD_READ_ACK;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_RD_P_LSB;
                    end
                end

                ST_RD_P_LSB: begin
                    if (i2c_done) begin
                        p_lsb         <= i2c_data_out;
                        // Byte 3: Press XLSB (ACK)
                        i2c_cmd       <= CMD_READ_ACK;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_RD_P_XLSB;
                    end
                end

                ST_RD_P_XLSB: begin
                    if (i2c_done) begin
                        p_xlsb        <= i2c_data_out;
                        // Byte 4: Temp MSB (ACK)
                        i2c_cmd       <= CMD_READ_ACK;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_RD_T_MSB;
                    end
                end

                ST_RD_T_MSB: begin
                    if (i2c_done) begin
                        t_msb         <= i2c_data_out;
                        // Byte 5: Temp LSB (ACK)
                        i2c_cmd       <= CMD_READ_ACK;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_RD_T_LSB;
                    end
                end

                ST_RD_T_LSB: begin
                    if (i2c_done) begin
                        t_lsb         <= i2c_data_out;
                        // Byte 6: Temp XLSB (NACK - byte terakhir)
                        i2c_cmd       <= CMD_READ_NACK;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_RD_T_XLSB;
                    end
                end

                ST_RD_T_XLSB: begin
                    if (i2c_done) begin
                        // Gabungkan menjadi nilai 20-bit: {MSB, LSB, XLSB[7:4]}
                        press_raw     <= {p_msb, p_lsb, p_xlsb[7:4]};
                        temp_raw      <= {t_msb, t_lsb, i2c_data_out[7:4]};

                        i2c_cmd       <= CMD_STOP;
                        i2c_cmd_valid <= 1'b1;
                        state         <= ST_DATA_STOP;
                    end
                end

                ST_DATA_STOP: begin
                    if (i2c_done) begin
                        data_valid <= 1'b1;
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
