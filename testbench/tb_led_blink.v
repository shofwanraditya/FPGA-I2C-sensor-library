// ============================================================================
// Testbench : tb_led_blink
// File      : tb_led_blink.v
// Project   : FPGA I2C Sensor Library
// Purpose   : Testbench untuk menguji module led_blink
//
// Deskripsi :
//   Testbench BUKAN desain hardware. Testbench adalah kode simulasi yang:
//   1. Membuat sinyal stimulus (clock, reset, dll).
//   2. Menghubungkannya ke module yang diuji (DUT = Design Under Test).
//   3. Mengamati output dan memeriksa apakah hasilnya benar.
//
//   Testbench hanya berjalan di simulator (Questa/ModelSim), 
//   TIDAK disintesis menjadi hardware.
//
//   Karena ini hanya simulasi, kita bisa menggunakan fitur yang tidak
//   bisa disintesis, seperti: $display, $monitor, #delay, initial block.
//
// Revisi    :
//   v1.0 - Versi awal
//   v1.1 - Perbaikan 2 bug:
//          1. Off-by-one toggle count (repeat 40 → formula yang benar)
//          2. Timestamp display (menambah $timeformat)
//
// Author    : [Nama Anda]
// Date      : 2026-11-24
// ============================================================================

// 'timescale menentukan satuan waktu dan presisi simulasi.
// 1ns / 1ps artinya:
//   - 1 unit waktu = 1 nanosecond
//   - Presisi = 1 picosecond
// Ini penting agar delay seperti #5 berarti "5 nanosecond".
`timescale 1ns / 1ps

module tb_led_blink;

    // ========================================================================
    // PARAMETER TESTBENCH
    // ========================================================================
    // Kita menggunakan BLINK_PERIOD kecil (5) agar simulasi cepat selesai.
    // CLK_PERIOD = 10ns → frekuensi clock = 100 MHz (1/10ns = 100 MHz).
    //
    // [PERBAIKAN v1.1]
    // EXPECTED_TOGGLES: Jumlah toggle yang kita harapkan.
    // Kita menghitung mundur dari sini, bukan menghitung maju dari
    // jumlah clock cycle. Ini menghindari error off-by-one.
    // ========================================================================
    parameter BLINK_PERIOD     = 5;
    parameter CLK_PERIOD       = 10; // dalam nanosecond
    parameter EXPECTED_TOGGLES = 8;  // jumlah toggle yang ingin diamati

    // ========================================================================
    // SINYAL TESTBENCH
    // ========================================================================
    // 'reg' untuk sinyal yang kita KENDALIKAN (drive) → input ke DUT.
    // 'wire' untuk sinyal yang kita AMATI (observe) → output dari DUT.
    //
    // Aturan sederhana:
    //   - Input DUT → deklarasikan sebagai 'reg' di testbench
    //   - Output DUT → deklarasikan sebagai 'wire' di testbench
    // ========================================================================
    reg  clk;      // Clock yang kita generate
    reg  rst_n;    // Reset yang kita kendalikan
    wire led;      // Output LED yang kita amati

    // ========================================================================
    // INSTANTIATION (Menghubungkan DUT)
    // ========================================================================
    // Ini seperti "memasang chip ke breadboard".
    // Kita membuat instance dari module led_blink dan menghubungkan
    // port-portnya ke sinyal testbench.
    //
    // Sintaks:
    //   module_name #(parameter) instance_name (port connections);
    //
    // .clk(clk) artinya: hubungkan port 'clk' dari DUT ke sinyal 'clk'
    // di testbench ini.
    // ========================================================================
    led_blink #(
        .BLINK_PERIOD(BLINK_PERIOD)   // Override parameter default
    ) dut (
        .clk   (clk),     // Port clk DUT ← sinyal clk testbench
        .rst_n (rst_n),    // Port rst_n DUT ← sinyal rst_n testbench
        .led   (led)       // Port led DUT → sinyal led testbench
    );

    // ========================================================================
    // CLOCK GENERATOR
    // ========================================================================
    // 'initial' block berjalan SEKALI saat simulasi dimulai (waktu 0).
    // Block ini TIDAK bisa disintesis (hanya untuk testbench/simulasi).
    //
    // 'forever' adalah loop tak terbatas.
    // '#(CLK_PERIOD/2)' adalah delay = setengah periode clock.
    //
    // Cara kerjanya:
    //   1. clk dimulai dari 0
    //   2. Tunggu 5ns → clk berubah jadi 1 (rising edge)
    //   3. Tunggu 5ns → clk berubah jadi 0 (falling edge)
    //   4. Ulangi terus → menghasilkan clock 100 MHz
    //
    //       ___     ___     ___     ___
    //  clk |   |   |   |   |   |   |   |
    //  ____|   |___|   |___|   |___|   |___
    //      ^       ^       ^       ^
    //      rising  rising  rising  rising
    //      edge    edge    edge    edge
    // ========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ========================================================================
    // VARIABEL UNTUK VERIFIKASI
    // ========================================================================
    integer toggle_count;    // Menghitung berapa kali LED toggle
    reg     prev_led;        // Menyimpan nilai LED sebelumnya

    // ========================================================================
    // TEST SEQUENCE (Urutan Pengujian)
    // ========================================================================
    // Block initial kedua ini berisi skenario pengujian.
    // Kita akan menguji:
    //   1. Reset berfungsi dengan benar (LED = 0 saat reset)
    //   2. LED toggle setelah BLINK_PERIOD clock cycles
    //   3. LED toggle beberapa kali dengan timing yang benar
    //
    // [PERBAIKAN v1.1 - OBSERVE_CYCLES]
    //
    //   Mengapa rumusnya EXPECTED_TOGGLES * BLINK_PERIOD + 1?
    //
    //   Karena ada "detection delay" sebesar 1 clock cycle.
    //   Ketika DUT menjalankan 'led <= ~led' (non-blocking assignment),
    //   nilai LED baru TIDAK langsung terlihat di clock cycle yang sama.
    //   Testbench baru bisa MELIHAT perubahan di clock cycle BERIKUTNYA.
    //
    //   Contoh dengan BLINK_PERIOD=5:
    //   - Counter menghitung: 0,1,2,3,4 → toggle terjadi (5 cycle)
    //   - Tapi testbench baru mendeteksi di cycle ke-6
    //   - Toggle berikutnya terdeteksi 5 cycle kemudian (cycle ke-11)
    //   - dst.
    //
    //   Jadi untuk mendeteksi N toggle:
    //     Cycle yang dibutuhkan = N × BLINK_PERIOD + 1
    //                           = 8 × 5 + 1
    //                           = 41 cycle
    //
    //   Dengan repeat(40) kita hanya punya 40 cycle → kurang 1!
    //   Itulah sebab toggle ke-8 tidak terdeteksi.
    // ========================================================================
    localparam OBSERVE_CYCLES = EXPECTED_TOGGLES * BLINK_PERIOD + 1;

    initial begin
        // ------------------------------------------------------------------
        // [PERBAIKAN v1.1 - $timeformat]
        //
        // $timeformat mengatur bagaimana %t menampilkan waktu.
        // Parameter:
        //   -9     → satuan = nanosecond (10^-9)
        //            (-12 = ps, -9 = ns, -6 = us, -3 = ms, 0 = s)
        //   0      → jumlah digit di belakang koma (0 = tanpa desimal)
        //   " ns"  → suffix yang ditambahkan otomatis setelah angka
        //   10     → lebar minimum field untuk angka
        //
        // Tanpa $timeformat, %t menggunakan satuan RESOLUSI timescale
        // (dalam kasus kita: 1ps). Sehingga 25ns ditampilkan sebagai
        // "25000". Dengan $timeformat(-9,...), 25ns ditampilkan sebagai "25".
        // ------------------------------------------------------------------
        $timeformat(-9, 0, " ns", 10);

        // ------------------------------------------------------------------
        // Inisialisasi
        // ------------------------------------------------------------------
        toggle_count = 0;
        prev_led     = 1'b0;

        // ------------------------------------------------------------------
        // STEP 1: Aktifkan Reset
        // ------------------------------------------------------------------
        // Mulai dengan reset aktif (rst_n = 0).
        // Ini memastikan sistem dimulai dari keadaan yang diketahui.
        // ------------------------------------------------------------------
        $display("==============================================");
        $display(" Testbench LED Blink - Mulai Simulasi");
        $display("==============================================");
        $display("Waktu      | Aksi");
        $display("-----------|--------------------------------------");

        rst_n = 1'b0;  // Aktifkan reset
        $display("%0t | Reset AKTIF (rst_n = 0)", $time);

        // Tahan reset selama 3 clock cycle
        // '@(posedge clk)' artinya "tunggu sampai rising edge clock berikutnya"
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // ------------------------------------------------------------------
        // VERIFIKASI 1: Cek kondisi reset
        // ------------------------------------------------------------------
        if (led !== 1'b0) begin
            $display("%0t | [GAGAL] LED seharusnya 0 saat reset, tapi = %b", $time, led);
            $finish;
        end else begin
            $display("%0t | [OK] LED = 0 saat reset (benar)", $time);
        end

        // ------------------------------------------------------------------
        // STEP 2: Lepaskan Reset
        // ------------------------------------------------------------------
        @(posedge clk);
        rst_n = 1'b1;  // Lepaskan reset (sistem mulai berjalan)
        $display("%0t | Reset DILEPAS (rst_n = 1)", $time);

        // ------------------------------------------------------------------
        // STEP 3: Amati LED toggle beberapa kali
        // ------------------------------------------------------------------
        // [PERBAIKAN v1.1]
        // Sebelumnya: repeat(40)  → hanya cukup untuk 7 toggle
        // Sekarang:   repeat(OBSERVE_CYCLES) = repeat(41)
        //             → cukup untuk 8 toggle
        //
        // Rumus: OBSERVE_CYCLES = EXPECTED_TOGGLES × BLINK_PERIOD + 1
        //      = 8 × 5 + 1 = 41
        //
        // "+1" memperhitungkan detection delay 1 cycle akibat
        // non-blocking assignment di DUT.
        // ------------------------------------------------------------------
        $display("%0t | Mengamati LED selama %0d clock cycle...", $time, OBSERVE_CYCLES);
        $display("-----------|--------------------------------------");

        prev_led = led;
        repeat (OBSERVE_CYCLES) begin
            @(posedge clk);
            // Periksa apakah LED berubah
            if (led !== prev_led) begin
                toggle_count = toggle_count + 1;
                $display("%0t | LED toggle! LED = %b (toggle ke-%0d)",
                         $time, led, toggle_count);
                prev_led = led;
            end
        end

        // ------------------------------------------------------------------
        // VERIFIKASI 2: Cek jumlah toggle
        // ------------------------------------------------------------------
        $display("==============================================");
        $display(" Hasil Verifikasi");
        $display("==============================================");
        $display("BLINK_PERIOD    = %0d clock cycles", BLINK_PERIOD);
        $display("Total observasi = %0d clock cycles", OBSERVE_CYCLES);
        $display("Toggle terjadi  = %0d kali", toggle_count);
        $display("Toggle expected = %0d kali", EXPECTED_TOGGLES);

        if (toggle_count == EXPECTED_TOGGLES) begin
            $display("Status          = PASSED");
        end else begin
            $display("Status          = FAILED");
        end

        $display("==============================================");
        $display(" Simulasi Selesai");
        $display("==============================================");

        // Tunggu sedikit lagi sebelum selesai (agar waveform lebih rapi)
        #(CLK_PERIOD * 5);
        $finish;
    end

    // ========================================================================
    // WAVEFORM DUMP (untuk melihat sinyal di Questa)
    // ========================================================================
    // $dumpfile → nama file VCD (Value Change Dump)
    // $dumpvars → sinyal mana yang direkam
    //
    // VCD adalah format standar untuk merekam perubahan sinyal.
    // File ini bisa dibuka di Questa untuk melihat waveform.
    //
    // Argumen $dumpvars(0, tb_led_blink):
    //   0 = rekam SEMUA hierarki di bawah module ini
    //   tb_led_blink = module yang direkam
    // ========================================================================
    initial begin
        $dumpfile("led_blink_wave.vcd");
        $dumpvars(0, tb_led_blink);
    end

endmodule
