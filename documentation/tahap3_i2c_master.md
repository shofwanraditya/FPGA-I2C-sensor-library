# Tahap 3 — Membuat I2C Master Controller

## Deskripsi Singkat Modul `i2c_master.v`

Modul `i2c_master` bertindak sebagai pengendali utama bus I2C berbasis FSM. Modul ini menerima perintah tingkat transaksi dari sensor driver berupa:
1. `CMD_START` (3'd1): Menghasilkan START condition (SDA turun saat SCL tinggi).
2. `CMD_WRITE` (3'd2): Mengirim 8-bit data seri (MSB first) dan menangkap ACK/NACK dari Slave.
3. `CMD_READ_ACK` (3'd3): Menerima 8-bit data seri dari Slave lalu mengirimkan ACK.
4. `CMD_READ_NACK` (3'd4): Menerima 8-bit data seri dari Slave lalu mengirimkan NACK (penanda byte terakhir).
5. `CMD_STOP` (3'd5): Menghasilkan STOP condition (SDA naik saat SCL tinggi).

## Sinyal Open-Drain

Bus I2C membutuhkan pin tri-state:
- Ketika master ingin mengirim bit `0`, ia meng-drive output ke `0`.
- Ketika master ingin mengirim bit `1` (atau membaca data dari slave), ia meng-drive output ke status high-impedance `1'bz` (di mana pull-up resistor akan menarik jalur ke tegangan VCC `1`).

## Cara Menjalankan Simulasi di Questa

1. Buka Questa Prime.
2. Pada tab **Transcript**, pindah ke direktori simulasi:
   ```tcl
   cd {C:/Users/LENOVO/.gemini/antigravity/scratch/FPGA_I2C_SENSOR_LIBRARY/simulation}
   ```
3. Eksekusi script `.do`:
   ```tcl
   do run_i2c_master.do
   ```
4. Periksa log hasil simulasi dan amati waveform bus `scl` serta `sda`.
