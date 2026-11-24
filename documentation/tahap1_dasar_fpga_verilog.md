# Tahap 1 — Dasar FPGA dan Verilog HDL

## Daftar Isi
- [1. Apa itu FPGA?](#1-apa-itu-fpga)
- [2. FPGA vs Mikrokontroler](#2-fpga-vs-mikrokontroler)
- [3. Dasar Verilog HDL](#3-dasar-verilog-hdl)
- [4. Latihan: LED Blink](#4-latihan-led-blink)
- [5. Cara Menjalankan Simulasi](#5-cara-menjalankan-simulasi)
- [6. Memahami Waveform](#6-memahami-waveform)
- [7. Indikator Keberhasilan](#7-indikator-keberhasilan)

---

## 1. Apa itu FPGA?

### Definisi Sederhana

**FPGA (Field-Programmable Gate Array)** adalah sebuah chip yang berisi ribuan hingga jutaan **gerbang logika** (AND, OR, NOT, XOR, dll) yang bisa **dikonfigurasi ulang** oleh pengguna.

Bayangkan seperti ini:
- **ASIC (Application-Specific IC)**: Sebuah bangunan yang sudah jadi dan tidak bisa diubah.
- **FPGA**: Sebuah lahan kosong yang penuh dengan **batu bata (gerbang logika)**. Anda bisa menyusun batu bata tersebut menjadi bangunan apa saja yang Anda inginkan.

### Komponen Utama FPGA

```
┌─────────────────────────────────────────────────────┐
│                      FPGA Chip                       │
│                                                      │
│   ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐     │
│   │ CLB │──│ CLB │──│ CLB │──│ CLB │──│ CLB │     │
│   └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘     │
│      │        │        │        │        │          │
│   ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐     │
│   │ CLB │──│ CLB │──│ CLB │──│ CLB │──│ CLB │     │
│   └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘     │
│      │        │        │        │        │          │
│   ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐     │
│   │ IOB │  │ IOB │  │ IOB │  │ IOB │  │ IOB │     │
│   └─────┘  └─────┘  └─────┘  └─────┘  └─────┘     │
│                                                      │
│  CLB = Configurable Logic Block (gerbang logika)     │
│  IOB = I/O Block (koneksi ke pin luar)               │
│  ─── = Programmable Interconnect (jalur koneksi)     │
└─────────────────────────────────────────────────────┘
```

1. **CLB (Configurable Logic Block)**: Blok logika yang bisa dikonfigurasi menjadi fungsi logika apa saja. Berisi **LUT (Look-Up Table)** dan **Flip-Flop**.

2. **IOB (I/O Block)**: Blok yang menghubungkan logika internal ke pin fisik chip. Di sinilah FPGA berkomunikasi dengan dunia luar.

3. **Programmable Interconnect**: Jalur koneksi yang menghubungkan CLB satu dengan lainnya. Jalur ini juga bisa dikonfigurasi.

4. **Block RAM**: Memori internal yang bisa digunakan untuk menyimpan data.

5. **DSP Block**: Blok khusus untuk operasi matematika (perkalian, penjumlahan).

6. **PLL/Clock Manager**: Untuk mengelola dan menghasilkan sinyal clock.

### Bagaimana FPGA "Diprogram"?

> [!IMPORTANT]
> FPGA **bukan diprogram** seperti mikrokontroler. FPGA **dikonfigurasi**. Perbedaannya sangat fundamental:
> - **Program (mikrokontroler)**: CPU menjalankan instruksi satu per satu secara berurutan.
> - **Konfigurasi (FPGA)**: Gerbang logika disusun ulang untuk membentuk sirkuit digital. Semua sirkuit **berjalan paralel secara bersamaan**.

Proses kerja FPGA:

```
Kode Verilog HDL
       │
       ▼
   Synthesis (Quartus)
   "Menerjemahkan kode menjadi gerbang logika"
       │
       ▼
   Place & Route (Quartus)
   "Menempatkan gerbang logika di posisi CLB dan menghubungkannya"
       │
       ▼
   Bitstream Generation
   "Menghasilkan file konfigurasi (.sof/.pof)"
       │
       ▼
   FPGA Programming
   "Mengirim bitstream ke chip FPGA"
       │
       ▼
   FPGA berjalan!
   "Sirkuit digital aktif dan bekerja"
```

---

## 2. FPGA vs Mikrokontroler

| Aspek | Mikrokontroler (Arduino, STM32) | FPGA |
|-------|--------------------------------|------|
| **Eksekusi** | Sekuensial (instruksi dijalankan satu per satu) | Paralel (semua sirkuit aktif bersamaan) |
| **Bahasa** | C/C++, Python | Verilog HDL, VHDL |
| **Pemrosesan** | Software (CPU menjalankan program) | Hardware (sirkuit digital langsung) |
| **Fleksibilitas** | Mudah diprogram ulang | Bisa dikonfigurasi ulang, tapi lebih kompleks |
| **Kecepatan** | Dibatasi clock CPU dan instruksi | Sangat cepat karena operasi paralel |
| **Cocok untuk** | Aplikasi umum, prototipe cepat | Pemrosesan sinyal, komunikasi, prototipe ASIC |
| **Harga** | Murah (\$1-\$30) | Lebih mahal (\$20-\$10000+) |
| **Kesulitan** | Relatif mudah | Lebih sulit (perlu memahami desain digital) |

### Kapan Menggunakan FPGA?

- Ketika membutuhkan **kecepatan tinggi** (misalnya pemrosesan video real-time).
- Ketika membutuhkan **paralelisme** (banyak operasi bersamaan).
- Ketika membutuhkan **kontrol timing yang presisi** (misalnya protokol komunikasi).
- Untuk **prototyping** sebelum membuat chip ASIC.
- Untuk **pendidikan** desain sirkuit digital.

### Mengapa Kita Menggunakan FPGA untuk I2C Sensor Library?

Dalam project ini, kita menggunakan FPGA untuk:
1. **Belajar desain digital** — memahami cara membuat sirkuit dari level rendah.
2. **Kontrol timing I2C yang presisi** — FPGA memberikan kontrol penuh atas timing sinyal.
3. **Paralelisme** — bisa membaca beberapa sensor secara bersamaan jika diperlukan.
4. **Modularitas** — setiap komponen (I2C Master, Sensor Driver, UART) adalah sirkuit terpisah.

---

## 3. Dasar Verilog HDL

### Apa itu Verilog HDL?

**Verilog HDL (Hardware Description Language)** adalah bahasa untuk **mendeskripsikan sirkuit digital**. Bukan bahasa pemrograman biasa!

> [!WARNING]
> Kesalahan umum pemula: menganggap Verilog seperti C/C++. Di C, kode dieksekusi baris per baris. Di Verilog, kode **menggambarkan sirkuit** yang **semuanya aktif bersamaan**.

### Konsep Dasar

#### 3.1 Module

Module adalah **unit dasar** di Verilog. Setiap desain terdiri dari satu atau lebih module. Module seperti sebuah "kotak hitam" yang memiliki input dan output.

```verilog
module nama_module (
    input  wire sinyal_masuk,
    output wire sinyal_keluar
);
    // Deskripsi sirkuit di sini
endmodule
```

#### 3.2 Wire vs Reg

| Tipe | Analoginya | Kapan Digunakan |
|------|-----------|-----------------|
| `wire` | Kabel listrik | Untuk koneksi (tidak menyimpan nilai). Dipakai di luar `always` block. |
| `reg` | Flip-flop / register | Untuk menyimpan nilai. Dipakai di dalam `always` block. |

```verilog
wire koneksi;      // Seperti kabel, nilainya ditentukan oleh sumber yang terhubung
reg  penyimpanan;  // Seperti register, nilainya disimpan sampai diubah
```

> [!NOTE]
> Nama `reg` agak menyesatkan. `reg` **tidak selalu** menjadi register (flip-flop) di hardware. Jika digunakan di `always @(*)` (kombinasional), ia bisa menjadi logika murni tanpa penyimpanan. Hanya di `always @(posedge clk)` (sekuensial) ia menjadi flip-flop.

#### 3.3 Assign (Continuous Assignment)

`assign` digunakan untuk logika **kombinasional** (tidak ada clock, langsung bereaksi).

```verilog
wire a, b, c;
assign c = a & b;  // c = a AND b (selalu aktif, bukan hanya sekali)
```

#### 3.4 Always Block

Ada dua jenis `always` block:

**Kombinasional** (tanpa clock):
```verilog
always @(*) begin
    // Semua input di dalam block ini otomatis masuk sensitivity list
    // Gunakan '=' (blocking assignment)
    result = a + b;
end
```

**Sekuensial** (dengan clock):
```verilog
always @(posedge clk or negedge rst_n) begin
    // Aktif saat rising edge clock ATAU falling edge reset
    // Gunakan '<=' (non-blocking assignment)
    if (!rst_n)
        q <= 0;
    else
        q <= d;
end
```

#### 3.5 Clock dan Reset

**Clock** adalah sinyal persegi yang berulang terus-menerus. Ini adalah "detak jantung" sistem digital.

```
         ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐
Clock    │   │   │   │   │   │   │   │   │   │
     ────┘   └───┘   └───┘   └───┘   └───┘   └────
         ↑       ↑       ↑       ↑       ↑
     Rising   Rising  Rising  Rising  Rising
      Edge    Edge    Edge    Edge    Edge
```

**Reset** memastikan sistem dimulai dari keadaan yang diketahui. Dua jenis:
- **Active High**: Reset aktif saat sinyal = 1.
- **Active Low** (`rst_n`): Reset aktif saat sinyal = 0. Lebih umum di FPGA.

#### 3.6 Bilangan di Verilog

Format: `<lebar>'<basis><nilai>`

| Contoh | Lebar | Basis | Nilai | Desimal |
|--------|-------|-------|-------|---------|
| `4'b1010` | 4 bit | Binary | 1010 | 10 |
| `8'hFF` | 8 bit | Hexadecimal | FF | 255 |
| `8'd200` | 8 bit | Decimal | 200 | 200 |
| `1'b0` | 1 bit | Binary | 0 | 0 |
| `32'd1000` | 32 bit | Decimal | 1000 | 1000 |

#### 3.7 FSM (Finite State Machine)

FSM adalah **mesin dengan jumlah state terbatas**. Ini SANGAT penting di project kita karena I2C Master Controller menggunakan FSM.

```
         ┌──────────┐
    ┌───→│  IDLE    │←──────────────────────┐
    │    │ (diam)   │                        │
    │    └────┬─────┘                        │
    │         │ tombol ditekan               │
    │    ┌────▼─────┐                        │
    │    │  STATE_A │                        │
    │    │ (proses) │                        │
    │    └────┬─────┘                        │
    │         │ selesai                      │
    │    ┌────▼─────┐                        │
    │    │  STATE_B │────────────────────────┘
    │    │ (kirim)  │      selesai kirim
    │    └──────────┘
    │
    └── reset
```

Implementasi FSM di Verilog:

```verilog
// Definisi state menggunakan parameter (konstanta)
localparam IDLE    = 2'b00;
localparam STATE_A = 2'b01;
localparam STATE_B = 2'b10;

reg [1:0] state;  // Register untuk menyimpan state saat ini

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        case (state)
            IDLE:    if (start) state <= STATE_A;
            STATE_A: if (done)  state <= STATE_B;
            STATE_B: state <= IDLE;
            default: state <= IDLE;
        endcase
    end
end
```

---

## 4. Latihan: LED Blink

### Deskripsi

Kita akan membuat module yang membuat LED berkedip. Ini adalah **"Hello World"** di dunia FPGA.

### Cara Kerja

```
Clock:  ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑
         1 2 3 4 5 1 2 3 4 5 1 2 3 4 5 1 2 3 4 5    ← counter
LED:    ___________|‾‾‾‾‾‾‾‾‾‾‾|___________|‾‾‾‾‾‾
        0 0 0 0 0  1 1 1 1 1   0 0 0 0 0   1 1 1
                   ↑           ↑           ↑
               toggle       toggle      toggle
            (counter=5)  (counter=5) (counter=5)
```

Dengan `BLINK_PERIOD = 5`:
1. Counter menghitung dari 0 sampai 4 (5 clock cycle).
2. Saat counter = 4, LED di-toggle dan counter reset ke 0.
3. Proses berulang terus-menerus.

### File yang Sudah Dibuat

| File | Lokasi | Fungsi |
|------|--------|--------|
| `led_blink.v` | `rtl/` | Module LED Blink (desain utama) |
| `tb_led_blink.v` | `testbench/` | Testbench untuk verifikasi |
| `run_led_blink.do` | `simulation/` | Script simulasi Questa |

Silakan buka dan baca setiap file. Semua baris kode sudah dilengkapi komentar penjelasan.

---

## 5. Cara Menjalankan Simulasi di Questa

### Metode 1: Menggunakan Script .do (Recommended)

1. Buka **Questa** (Intel FPGA Edition) atau **ModelSim**.

2. Di jendela **Transcript** (command line Questa), navigasi ke folder simulation:
   ```tcl
   cd {C:/Users/LENOVO/.gemini/antigravity/scratch/FPGA_I2C_SENSOR_LIBRARY/simulation}
   ```

3. Jalankan script simulasi:
   ```tcl
   do run_led_blink.do
   ```

4. Questa akan:
   - Mengompilasi `led_blink.v` dan `tb_led_blink.v`.
   - Menjalankan simulasi.
   - Menampilkan waveform.
   - Menampilkan log di jendela **Transcript**.

### Metode 2: Manual Step-by-Step

Jika Anda ingin memahami setiap langkah:

```tcl
# 1. Navigasi ke folder
cd {C:/Users/LENOVO/.gemini/antigravity/scratch/FPGA_I2C_SENSOR_LIBRARY/simulation}

# 2. Buat library kerja
vlib work

# 3. Kompilasi file RTL
vlog -work work ../rtl/led_blink.v

# 4. Kompilasi testbench
vlog -work work ../testbench/tb_led_blink.v

# 5. Mulai simulasi
vsim -voptargs=+acc work.tb_led_blink

# 6. Tambahkan sinyal ke waveform
add wave sim:/tb_led_blink/*
add wave sim:/tb_led_blink/dut/counter

# 7. Jalankan simulasi
run -all

# 8. Zoom fit waveform
wave zoom full
```

### Output yang Diharapkan di Transcript

```
==============================================
 Testbench LED Blink - Mulai Simulasi
==============================================
Waktu | Aksi
------|--------------------------------------
0 ns | Reset AKTIF (rst_n = 0)
30 ns | [OK] LED = 0 saat reset (benar)
40 ns | Reset DILEPAS (rst_n = 1)
40 ns | Memulai pengamatan LED...
------|--------------------------------------
90 ns | LED toggle! LED = 1 (toggle ke-1)
140 ns | LED toggle! LED = 0 (toggle ke-2)
190 ns | LED toggle! LED = 1 (toggle ke-3)
240 ns | LED toggle! LED = 0 (toggle ke-4)
290 ns | LED toggle! LED = 1 (toggle ke-5)
340 ns | LED toggle! LED = 0 (toggle ke-6)
390 ns | LED toggle! LED = 1 (toggle ke-7)
440 ns | LED toggle! LED = 0 (toggle ke-8)
==============================================
 Hasil Verifikasi
==============================================
BLINK_PERIOD    = 5 clock cycles
Total observasi = 40 clock cycles
Toggle terjadi  = 8 kali
Toggle expected = 8 kali
Status          = PASSED ✓
==============================================
 Simulasi Selesai
==============================================
```

---

## 6. Memahami Waveform

Setelah simulasi berjalan, Anda akan melihat waveform di Questa. Berikut cara membacanya:

### Sinyal yang Harus Diamati

```
Waktu (ns)   0  10  20  30  40  50  60  70  80  90  100 110 120 ...
              │   │   │   │   │   │   │   │   │   │   │   │   │
clk        ┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐┌┐  ← Clock 100MHz
              │   │   │   │   │   │   │   │   │   │   │   │   │
rst_n      ──┘           ┌────────────────────────────────────── ← Reset lepas di ~40ns
           ──────────────┘
              │   │   │   │   │   │   │   │   │   │   │   │   │
counter    0  0   0   0   0   1   2   3   4   0   1   2   3   4  ← Menghitung 0-4
              │   │   │   │   │   │   │   │   │   │   │   │   │
led        ──────────────────────────────────┌────────────────── ← Toggle setiap 5 cycle
           ──────────────────────────────────┘
```

### Yang Harus Diperiksa

1. **rst_n**: Saat LOW (0), counter dan LED harus 0.
2. **counter**: Harus menghitung 0 → 1 → 2 → 3 → 4 → 0 → 1 → ...
3. **led**: Harus toggle setiap kali counter mencapai 4 (BLINK_PERIOD - 1).
4. **Timing**: LED berubah tepat di rising edge clock saat counter = BLINK_PERIOD - 1.

---

## 7. Indikator Keberhasilan Tahap 1

Sebelum lanjut ke Tahap 2, pastikan semua item berikut terpenuhi:

- [ ] Memahami perbedaan FPGA dan mikrokontroler.
- [ ] Memahami konsep: module, wire, reg, assign, always block, clock, reset.
- [ ] Memahami cara membaca kode `led_blink.v` dan mengerti fungsi setiap baris.
- [ ] Memahami cara membaca kode `tb_led_blink.v` dan mengerti bagaimana testbench bekerja.
- [ ] Berhasil menjalankan simulasi di Questa tanpa error kompilasi.
- [ ] Output transcript menunjukkan "Status = PASSED ✓".
- [ ] Dapat melihat waveform dan memverifikasi bahwa LED toggle setiap 5 clock cycle.
- [ ] Memahami konsep FSM (akan digunakan di tahap selanjutnya).

> [!TIP]
> Jika ada konsep yang belum dipahami, jangan ragu untuk bertanya sebelum lanjut ke Tahap 2 (Protokol I2C). Pemahaman yang kuat di tahap ini akan sangat membantu di tahap-tahap selanjutnya.
