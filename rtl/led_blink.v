// ============================================================================
// Module    : led_blink
// File      : led_blink.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Latihan Tahap 1 - LED Blink menggunakan Verilog HDL
// 
// Deskripsi :
//   Module ini membuat LED berkedip dengan cara membagi frekuensi clock.
//   Sebuah counter menghitung naik setiap rising edge clock. Ketika counter
//   mencapai nilai tertentu, sinyal LED di-toggle (berubah dari 0 ke 1 
//   atau sebaliknya).
//
//   Untuk SIMULASI, kita menggunakan parameter BLINK_PERIOD yang kecil
//   agar hasilnya cepat terlihat di waveform.
//
//   Untuk FPGA sesungguhnya (misalnya clock 50 MHz), BLINK_PERIOD bisa
//   diatur ke 25_000_000 agar LED berkedip setiap 0.5 detik.
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

module led_blink #(
    // ========================================================================
    // PARAMETER
    // ========================================================================
    // Parameter adalah "konstanta yang bisa diubah" saat module digunakan.
    // Ini membuat module lebih fleksibel (reusable).
    //
    // BLINK_PERIOD menentukan setelah berapa cycle clock LED akan toggle.
    // Default: 10 (untuk simulasi). Untuk FPGA 50MHz: gunakan 25_000_000.
    // ========================================================================
    parameter BLINK_PERIOD = 10
)(
    // ========================================================================
    // PORT (Input dan Output)
    // ========================================================================
    // 'input' = sinyal yang MASUK ke module ini dari luar.
    // 'output' = sinyal yang KELUAR dari module ini ke luar.
    //
    // Bayangkan module seperti sebuah chip IC:
    //   - Pin input: menerima sinyal dari luar
    //   - Pin output: mengirim sinyal ke luar
    // ========================================================================

    input  wire clk,    // Clock: sinyal detak yang berulang terus-menerus.
                        // Ini adalah "jantung" dari sistem digital.
                        // Semua operasi sinkron terjadi pada rising edge clock.

    input  wire rst_n,  // Reset (Active Low): ketika rst_n = 0, sistem di-reset.
                        // '_n' artinya "active low" (aktif saat bernilai 0).
                        // Konvensi ini umum digunakan di dunia FPGA.
                        // Saat rst_n = 1, sistem berjalan normal.

    output reg  led     // LED output: sinyal yang mengontrol LED.
                        // led = 1 → LED menyala
                        // led = 0 → LED mati
                        // Dideklarasikan sebagai 'reg' karena nilainya diatur
                        // di dalam blok 'always' (prosedural).
);

    // ========================================================================
    // INTERNAL SIGNAL (Sinyal Internal)
    // ========================================================================
    // 'reg' digunakan untuk sinyal yang nilainya disimpan (memiliki memori).
    // Sinyal internal tidak terlihat dari luar module.
    //
    // Counter digunakan untuk menghitung jumlah clock cycle.
    // Lebar counter harus cukup untuk menyimpan nilai BLINK_PERIOD.
    //
    // $clog2(N) = ceiling of log base 2 of N
    // Fungsi ini menghitung berapa bit yang diperlukan untuk merepresentasikan
    // nilai N. Contoh: $clog2(10) = 4 (karena 2^4 = 16 >= 10)
    // ========================================================================
    reg [$clog2(BLINK_PERIOD)-1:0] counter;

    // ========================================================================
    // ALWAYS BLOCK - Logika Sekuensial
    // ========================================================================
    // 'always @(posedge clk or negedge rst_n)' artinya:
    //   "Jalankan blok ini setiap kali ada:"
    //   - Rising edge (transisi 0→1) pada sinyal clk, ATAU
    //   - Falling edge (transisi 1→0) pada sinyal rst_n
    //
    // Ini disebut "logika sekuensial" karena operasinya terjadi secara
    // berurutan, disinkronkan oleh clock.
    //
    // Pola reset + counter + toggle ini adalah pola yang SANGAT UMUM
    // dalam desain digital FPGA.
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ==============================================================
            // RESET CONDITION
            // ==============================================================
            // Ketika rst_n = 0 (active low), semua register dikembalikan
            // ke kondisi awal. Ini penting untuk memastikan sistem mulai
            // dari keadaan yang diketahui (known state).
            //
            // '<=' adalah "non-blocking assignment", digunakan di dalam
            // always block sekuensial. Berbeda dengan '=' (blocking).
            // Aturan: gunakan '<=' untuk logika sekuensial (always @posedge).
            // ==============================================================
            counter <= 0;    // Reset counter ke 0
            led     <= 1'b0; // Reset LED ke kondisi mati (0)
                             // 1'b0 artinya: 1 bit, format binary, nilai 0

        end else begin
            // ==============================================================
            // NORMAL OPERATION (saat rst_n = 1)
            // ==============================================================
            if (counter == BLINK_PERIOD - 1) begin
                // Counter sudah mencapai target.
                // Saatnya toggle LED dan reset counter.
                counter <= 0;        // Reset counter untuk mulai menghitung lagi
                led     <= ~led;     // Toggle LED: ~ adalah operator NOT
                                     // Jika led = 0, maka ~led = 1 (dan sebaliknya)
            end else begin
                // Counter belum mencapai target.
                // Terus hitung naik.
                counter <= counter + 1;
            end
        end
    end

endmodule
