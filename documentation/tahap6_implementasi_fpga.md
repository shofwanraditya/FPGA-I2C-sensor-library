# Tahap 6 — Panduan Implementasi FPGA di Intel Quartus Prime Lite

Dokumen ini memandu Anda dalam melakukan proses **Sintesis (Synthesis)**, **Fitting (Place & Route)**, dan **Analisis Penggunaan Sumber Daya (Resource Utilization)** pada Intel Quartus Prime Lite 25.1.

---

## 1. Membuka Project di Intel Quartus Prime

1. Buka aplikasi **Intel Quartus Prime Lite Edition 25.1**.
2. Pilih menu **File** $\rightarrow$ **Open Project...**
3. Masuk ke direktori proyek:
   ```
   C:/Users/LENOVO/.gemini/antigravity/scratch/FPGA_I2C_SENSOR_LIBRARY/quartus/
   ```
4. Pilih file project: **`fpga_i2c_sensor.qpf`** lalu klik **Open**.

---

## 2. Menjalankan Kompilasi Lengkap (Full Compilation)

1. Pada toolbar atas atau jendela **Tasks** di sebelah kiri, klik dua kali pada menu:
   - **Compile Design** (ikon tombol Play berwarna ungu/hijau)
   - Atau gunakan tombol pintas keyboard: **Ctrl + L**.
2. Proses kompilasi akan menjalankan beberapa tahapan:
   - **Analysis & Synthesis**: Menerjemahkan kode Verilog menjadi gerbang logika silikon (LUT & Register).
   - **Fitter (Place & Route)**: Menempatkan logika ke blok LAB (Logic Array Block) pada chip FPGA dan menghubungkan jalur routing.
   - **Assembler**: Menghasilkan file konfigurasi biner (file `.sof` untuk SRAM programming via JTAG, dan `.pof` untuk flash SPI).
   - **Timing Analysis**: Memastikan clock 50 MHz dapat dipenuhi tanpa pelanggaran setup/hold time.

---

## 3. Memeriksa Laporan Sintesis (Compilation Report)

Setelah kompilasi selesai dengan tanda centang hijau (**Successful**), periksa jendela **Flow Summary**:

| Parameter Laporan | Keterangan |
|---|---|
| **Top-level Entity Name** | `top_module` |
| **Family / Device** | `Cyclone IV E` / `EP4CE6E22C8` |
| **Total Logic Elements** | Menunjukkan jumlah LUT & Flip-Flop yang dipakai (tipikal < 600 LEs, sangat hemat! < 10% dari kapasitas FPGA). |
| **Total Registers** | Jumlah D-Flip-Flop yang digunakan oleh state FSM dan register data sensor. |
| **Total Pins** | 8 pin (clk, rst_n, trigger_btn, led_heartbeat, led_busy, led_error, i2c_scl, i2c_sda, uart_tx_pin). |
| **Total Memory Bits** | 0 bits (seluruh data buffer ditangani register flip-flop, tidak membebani Block RAM M9K). |

---

## 4. Penugasan Pin Fisik (Pin Assignment)

Jika Anda memiliki board FPGA fisik (misalnya: *Cyclone IV Minimum Development Board*, *DE10-Lite*, *Alchitry*, atau *Xilinx/Gowin*):
1. Anda dapat menyesuaikan lokasi pin pada file `fpga_i2c_sensor.qsf` atau melalui menu:
   **Assignments** $\rightarrow$ **Pin Planner** (Ctrl + Shift + N).
2. Diagram pengkabelan fisik untuk pengujian hardware:
   ```
   +------------------+                    +------------------+
   |   BOARD FPGA     |                    |   SENSOR BH1750  |
   |                  |                    |                  |
   |      PIN_112 (SCL)+------------------->+ SCL             |
   |      PIN_113 (SDA)+<==================>+ SDA             |
   |              3.3V+------------------->+ VCC             |
   |               GND+------------------->+ GND             |
   +------------------+                    +------------------+
            |                                       |
            |                              +------------------+
            | (Jalur SCL/SDA Paralel)      |   SENSOR BMP280  |
            +----------------------------->+ SCL             |
            +=============================>+ SDA             |
            |                              | VCC & GND        |
            |                              +------------------+
            |
            | PIN_115 (UART TX)            +------------------+
            +----------------------------->+ RXD (USB-TTL PC) |
                           GND ------------+ GND              |
                                           +------------------+
   ```

*Catatan Penting Jalur I2C:*
- Jalur SDA dan SCL pada modul sensor (board breakout GY-30 / GY-BMP280) biasanya sudah dilengkapi resistor pull-up 4.7 kΩ atau 10 kΩ ke 3.3V di modulnya, sehingga dapat langsung dihubungkan paralel ke pin FPGA.
- Pastikan pin VCC sensor menggunakan tegangan **3.3V** (sesuai standar I/O FPGA Cyclone IV).
