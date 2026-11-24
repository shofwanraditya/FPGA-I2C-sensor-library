# Design and Implementation of a Modular I2C Sensor Library on FPGA Using Verilog HDL

Proyek ini merupakan perancangan dan implementasi **Library Sensor berbasis Protokol I2C** yang modular pada FPGA menggunakan bahasa **Verilog HDL**. Sistem ini mengintegrasikan satu kontroler *I2C Master* tunggal untuk membaca beberapa sensor I2C secara bergantian (*shared-bus*) dan mentransmisikan data hasil pengukuran ke PC melalui antarmuka serial UART.

---

## 🌟 Fitur Utama

1. **Modular I2C Master Controller (`i2c_master.v`)**:
   - Berbasis Finite State Machine (FSM) yang deterministik.
   - Mendukung kondisi *START*, *STOP*, dan *Repeated START*.
   - Sifat fisik *Open-Drain* (tri-state buffer `1'bz` & `1'b0`) dengan dukungan pull-up resistor.
   - Deteksi *ACK/NACK* otomatis untuk transmisi dan penerimaan data.
2. **BH1750 Ambient Light Sensor Driver (`bh1750_driver.v`)**:
   - Mendukung inisialisasi *Power ON* (`0x01`) dan mode *Continuously H-Resolution* (`0x10`).
   - Pembacaan data intensitas cahaya 16-bit lux presisi tinggi.
3. **BMP280 Barometric & Temperature Driver (`bmp280_driver.v`)**:
   - Validasi Chip ID (`0x58`) melalui *Repeated START*.
   - Konfigurasi register `ctrl_meas` (`0xF4`).
   - Pembacaan *burst* 6-byte data register untuk data ADC Tekanan (20-bit) dan Suhu (20-bit).
4. **UART Transmitter (`uart_tx.v`)**:
   - Format standar 8-N-1 (8 Data bits, No Parity, 1 Stop bit).
   - Baud rate terkonfigurasi (default 115200 bps @ 50 MHz).
5. **Top Module Orchestrator (`top_module.v`)**:
   - Penjadwalan giliran akses bus I2C antara BH1750 dan BMP280.
   - Konversi data biner sensor menjadi format string ASCII:
     ```text
     L:0145 P:51820 T:83450\r\n
     ```
   - Dilengkapi *Heartbeat LED* sebagai indikator operasional FPGA.

---

## 📁 Struktur Direktori

```text
FPGA_I2C_SENSOR_LIBRARY/
├── rtl/                          # Source code sirkuit digital Verilog HDL
│   ├── i2c_master.v              # Core I2C Master Controller
│   ├── bh1750_driver.v           # Driver Sensor Cahaya BH1750
│   ├── bmp280_driver.v           # Driver Sensor Suhu & Tekanan BMP280
│   ├── uart_tx.v                 # Pemancar Serial UART
│   ├── led_blink.v               # Modul Dasar Verifikasi Clock
│   └── top_module.v              # Top-Level System Integration
├── testbench/                    # File Testbench untuk Verifikasi Fungsional
│   ├── tb_i2c_master.v           # Testbench I2C Master
│   ├── tb_bh1750.v               # Testbench BH1750
│   ├── tb_bmp280.v               # Testbench BMP280
│   ├── tb_led_blink.v            # Testbench LED Blink
│   └── tb_top_module.v           # Testbench Sistem Penuh
├── simulation/                   # Macro script Questa / ModelSim
│   ├── run_i2c_master.do
│   ├── run_bh1750.do
│   ├── run_bmp280.do
│   └── run_top_module.do
├── quartus/                      # File Project Intel Quartus Prime
│   ├── fpga_i2c_sensor.qpf       # Quartus Project File
│   └── fpga_i2c_sensor.qsf       # Quartus Settings File
└── documentation/                # Laporan & Panduan Pengembangan
```

---

## 🛠️ Software & Tools yang Digunakan

- **OS**: Windows 11
- **Synthesis Tool**: Intel Quartus Prime Lite Edition 25.1
- **Simulation Tool**: Questa Intel FPGA Edition
- **Language**: Verilog HDL (IEEE 1364-2001)

---

## 🚀 Panduan Menjalankan Simulasi (Questa)

1. Buka Questa Prime.
2. Pada tab **Transcript**, masuk ke direktori simulasi:
   ```tcl
   cd {path_ke_folder}/simulation
   ```
3. Jalankan salah satu skenario simulasi:
   - Uji Sistem Penuh (Top Module + UART Output):
     ```tcl
     do run_top_module.do
     ```
   - Uji Sensor BMP280:
     ```tcl
     do run_bmp280.do
     ```
   - Uji Sensor BH1750:
     ```tcl
     do run_bh1750.do
     ```

---

## 📊 Hasil Sintesis Hardware (Intel MAX 10 FPGA)

Berdasarkan hasil kompilasi **Intel Quartus Prime Lite 25.1** pada chip **10M08DAF484C8G**:
- **Total Logic Elements**: ~785 Logic Cells (< 10% utilisasi, sangat hemat dan optimal).
- **Total Registers**: 267 Flip-Flop.
- **Total User I/O Pins**: 9 Pin (3 Input, 4 Output, 2 Bidirectional).
- **Status Kompilasi**: **Full Compilation Successful (0 Errors)**.
