# Tahap 2 — Memahami Protokol I2C

## Daftar Isi
- [1. Apa itu I2C?](#1-apa-itu-i2c)
- [2. Jalur SDA dan SCL](#2-jalur-sda-dan-scl)
- [3. Master dan Slave](#3-master-dan-slave)
- [4. Open-Drain dan Pull-Up Resistor](#4-open-drain-dan-pull-up-resistor)
- [5. START dan STOP Condition](#5-start-dan-stop-condition)
- [6. Format Data dan 7-Bit Address](#6-format-data-dan-7-bit-address)
- [7. ACK dan NACK](#7-ack-dan-nack)
- [8. Transaksi I2C Lengkap](#8-transaksi-i2c-lengkap)
- [9. Timing Diagram I2C](#9-timing-diagram-i2c)
- [10. Contoh Transaksi Sensor Kita](#10-contoh-transaksi-sensor-kita)
- [11. Indikator Keberhasilan](#11-indikator-keberhasilan)

---

## 1. Apa itu I2C?

### Definisi Sederhana

**I2C (Inter-Integrated Circuit)**, dibaca "I-squared-C" atau "I-two-C", adalah sebuah
**protokol komunikasi** yang memungkinkan beberapa chip (IC) saling berkomunikasi
menggunakan **hanya 2 kabel**.

Protokol ini diciptakan oleh **Philips (sekarang NXP)** pada tahun 1982 dan sampai
sekarang masih sangat populer, terutama untuk sensor, EEPROM, RTC, dan LCD.

### Analogi Sederhana

Bayangkan sebuah **ruang kelas**:

```
  ┌──────────────────────────────────────────────────┐
  │                  RUANG KELAS                      │
  │                                                   │
  │   ┌──────────┐                                    │
  │   │  GURU    │  ← Master (yang bertanya/meminta)  │
  │   │ (FPGA)   │                                    │
  │   └──────────┘                                    │
  │        │                                          │
  │   ═════╪══════════════════════════╗  ← 2 kabel    │
  │        │                         ║    (SDA + SCL) │
  │   ┌────┴─────┐  ┌───────────┐  ┌─╨──────────┐    │
  │   │ MURID A  │  │  MURID B  │  │  MURID C   │    │
  │   │ (BH1750) │  │ (BMP280)  │  │ (Sensor X) │    │
  │   │ Kursi #23│  │ Kursi #76 │  │ Kursi #48  │    │
  │   └──────────┘  └───────────┘  └────────────┘    │
  │                                                   │
  │   Setiap murid punya NOMOR KURSI (= alamat I2C)  │
  └──────────────────────────────────────────────────┘
```

- **Guru (Master)** = FPGA kita. Dialah yang memulai percakapan.
- **Murid (Slave)** = Sensor (BH1750, BMP280). Mereka hanya merespons jika dipanggil.
- **2 kabel** = Cukup 2 kabel untuk guru berkomunikasi dengan SEMUA murid.
- **Nomor kursi** = Alamat I2C. Setiap murid punya alamat unik.

Cara kerjanya:
1. Guru berkata: **"Murid di kursi 23, berikan data intensitas cahaya!"**
2. Hanya murid di kursi 23 (BH1750) yang merespons.
3. Murid lainnya diam saja.

---

## 2. Jalur SDA dan SCL

I2C hanya menggunakan **2 jalur sinyal** (plus ground):

### SCL — Serial Clock Line

```
         ┌───┐   ┌───┐   ┌───┐   ┌───┐
SCL      │   │   │   │   │   │   │   │
     ────┘   └───┘   └───┘   └───┘   └───
```

- **Dikendalikan oleh Master** (FPGA kita).
- Berfungsi sebagai **detak sinkronisasi**.
- Slave membaca/menulis data **berdasarkan irama SCL**.
- Seperti "ketukan" guru: "Sekarang baca! ... Sekarang baca! ..."

### SDA — Serial Data Line

```
         ┌───────┐       ┌───┐   ┌───────┐
SDA      │ BIT 1 │ BIT 0 │ 1 │ 0 │ BIT 1 │
     ────┘       └───────┘   └───┘       └───
```

- **Bisa dikendalikan oleh Master ATAU Slave** (bergantian).
- Membawa **data sesungguhnya** (bit 0 dan 1).
- Seperti "papan tulis" yang bisa dipakai guru maupun murid.

### Aturan Penting: Kapan SDA Boleh Berubah?

```
         ┌───────────┐           ┌───────────┐
SCL      │           │           │           │
     ────┘           └───────────┘           └────
         ↑                       ↑
         │  SDA HARUS STABIL     │  SDA HARUS STABIL
         │  saat SCL HIGH        │  saat SCL HIGH
         │                       │
     ════╪═══════════════════════╪════════════════
         │                       │
              ┌───────────┐
              │ SDA boleh │
              │ berubah   │
              │ DI SINI   │
              └───────────┘
              Saat SCL LOW
```

> **ATURAN EMAS:**
> - SDA hanya boleh berubah saat **SCL LOW**.
> - Saat **SCL HIGH**, SDA **HARUS STABIL** (tidak boleh berubah).
> - Jika SDA berubah saat SCL HIGH → itu adalah **START atau STOP condition** (bukan data biasa).

---

## 3. Master dan Slave

### Master (Tuan)
- **Memulai** dan **mengakhiri** komunikasi.
- **Menghasilkan clock** (SCL).
- **Menentukan** siapa yang diajak bicara (memilih alamat slave).
- Dalam project kita: **FPGA** adalah Master.

### Slave (Budak/Hamba)
- **Hanya merespons** jika alamatnya dipanggil.
- **Tidak bisa memulai** komunikasi sendiri.
- Punya **alamat unik** (7-bit).
- Dalam project kita: **BH1750** dan **BMP280** adalah Slave.

### Siapa Mengendalikan SDA?

| Fase | Siapa yang mengendalikan SDA? |
|------|-------------------------------|
| START condition | Master |
| Kirim alamat (7 bit) | Master |
| Kirim R/W bit | Master |
| ACK setelah alamat | **Slave** |
| Kirim data (write) | Master |
| ACK setelah data write | **Slave** |
| Terima data (read) | **Slave** |
| ACK setelah data read | **Master** |
| STOP condition | Master |

Perhatikan: **SDA dipakai bergantian!** Inilah mengapa I2C menggunakan konsep open-drain (dijelaskan di bawah).

---

## 4. Open-Drain dan Pull-Up Resistor

Ini adalah konsep **PALING PENTING** yang sering membingungkan pemula.

### Masalah: Bagaimana Jika Master dan Slave Sama-sama Mengendalikan SDA?

Bayangkan kalau Master ingin mengirim "1" (HIGH) tapi Slave ingin mengirim "0" (LOW)
secara bersamaan. Jika keduanya mendorong kabel secara aktif, akan terjadi **konflik**
(short circuit)!

### Solusi: Open-Drain

Konsep open-drain:
- Perangkat **hanya bisa MENARIK kabel ke LOW (0)**.
- Perangkat **TIDAK BISA mendorong kabel ke HIGH (1)**.
- Untuk membuat kabel HIGH, perangkat **MELEPAS kabel** (high-impedance, dilambangkan `Z`).
- Sebuah **pull-up resistor** yang terhubung ke VCC akan **menarik kabel ke HIGH** secara otomatis saat tidak ada yang menariknya ke LOW.

```
        VCC (3.3V)
         │
         ┣━━ Pull-up Resistor (4.7kΩ) ━━┓
         │                               │
         │                          ═════╪═══════ SDA Line
         │                               │
         │              ┌────────────────┤
         │              │                │
     ┌───┴───┐    ┌─────┴────┐    ┌──────┴─────┐
     │       │    │          │    │            │
     │Master │    │ Slave A  │    │  Slave B   │
     │(FPGA) │    │ (BH1750) │    │  (BMP280)  │
     │       │    │          │    │            │
     └───────┘    └──────────┘    └────────────┘

     Semua perangkat terhubung ke kabel SDA yang SAMA.
     Pull-up resistor menarik SDA ke HIGH saat tidak ada yang
     menariknya ke LOW.
```

### Tabel Kebenaran Open-Drain

| Master ingin | Slave ingin | SDA aktual | Penjelasan |
|---|---|---|---|
| Lepas (Z) | Lepas (Z) | **HIGH** (1) | Pull-up menarik ke HIGH |
| Lepas (Z) | Tarik LOW | **LOW** (0) | Slave menang |
| Tarik LOW | Lepas (Z) | **LOW** (0) | Master menang |
| Tarik LOW | Tarik LOW | **LOW** (0) | Keduanya LOW, aman |

> **Prinsip:** LOW selalu menang. Ini disebut **"wired-AND"**.

### Implementasi di Verilog (Preview)

Di Verilog, open-drain diimplementasikan seperti ini:

```verilog
// SALAH — jangan lakukan ini!
assign sda = data_bit;        // Ini mendorong HIGH secara aktif!

// BENAR — open-drain
assign sda = data_bit ? 1'bz : 1'b0;
//           │                   │
//           │                   └── Jika bit = 0: tarik SDA ke LOW
//           └── Jika bit = 1: lepas SDA (high-impedance)
//                              Pull-up resistor akan menarik ke HIGH
```

Kita akan mengimplementasikan ini di Tahap 3.

---

## 5. START dan STOP Condition

START dan STOP adalah "sinyal spesial" di I2C. Mereka melanggar aturan emas
(SDA berubah saat SCL HIGH) dan itulah yang membuatnya spesial.

### START Condition

**SDA turun dari HIGH ke LOW saat SCL HIGH.**

```
     SDA  ───────╲
                  ╲
                   ╲──────────
     SCL  ─────────────────────
                       │
               HIGH    │   HIGH
                       │
                  START CONDITION
                  "Perhatian semua! Komunikasi dimulai!"
```

Urutan:
1. SDA = HIGH, SCL = HIGH (keadaan idle/diam)
2. SDA ditarik ke LOW ← **ini START**
3. Kemudian SCL ditarik ke LOW
4. Komunikasi dimulai

### STOP Condition

**SDA naik dari LOW ke HIGH saat SCL HIGH.**

```
                   ╱──────────
                  ╱
     SDA  ───────╱
     SCL  ─────────────────────
                       │
               HIGH    │   HIGH
                       │
                  STOP CONDITION
                  "Komunikasi selesai. Kabel dibebaskan."
```

Urutan:
1. SCL naik ke HIGH
2. SDA naik ke HIGH ← **ini STOP**
3. Bus kembali ke keadaan idle

### Repeated START

Kadang Master ingin **melanjutkan komunikasi** tanpa melepas bus (tanpa STOP).
Ini disebut **Repeated START (Sr)**.

Contoh penggunaan: membaca data dari sensor.
1. Master **menulis** alamat register yang ingin dibaca (START → Write)
2. Master **membaca** data dari register tersebut (Repeated START → Read)
3. Master mengirim STOP

Ini **sangat penting** untuk sensor kita (BH1750 dan BMP280).

---

## 6. Format Data dan 7-Bit Address

### Byte Pertama: Alamat + R/W

Setelah START condition, Master mengirim **1 byte pertama** yang berisi:

```
     Byte pertama yang dikirim setelah START:

     ┌────┬────┬────┬────┬────┬────┬────┬────┐
     │ A6 │ A5 │ A4 │ A3 │ A2 │ A1 │ A0 │R/W │
     └────┴────┴────┴────┴────┴────┴────┴────┘
      MSB                             LSB
     ├──────────── 7 bit ────────────┤│1 bit│
              Alamat Slave            │
                                      │
                              0 = Write (Master → Slave)
                              1 = Read  (Slave → Master)
```

**7-bit address** berarti ada maksimal 128 alamat (0-127), tapi beberapa
alamat reserved, jadi sekitar **112 perangkat** bisa terhubung di satu bus.

### Alamat Sensor Kita

| Sensor | Alamat 7-bit | Alamat + Write (8-bit) | Alamat + Read (8-bit) |
|--------|-------------|----------------------|---------------------|
| BH1750 (ADDR LOW) | `0x23` (0100011) | `0x46` (01000110) | `0x47` (01000111) |
| BH1750 (ADDR HIGH) | `0x5C` (1011100) | `0xB8` (10111000) | `0xB9` (10111001) |
| BMP280 (SDO LOW) | `0x76` (1110110) | `0xEC` (11101100) | `0xED` (11101101) |
| BMP280 (SDO HIGH) | `0x77` (1110111) | `0xEE` (11101110) | `0xEF` (11101111) |

> Perhatikan: Alamat 7-bit digeser ke kiri 1 posisi, lalu bit paling kanan
> diisi dengan 0 (write) atau 1 (read). Contoh BH1750:
> `0x23` = `0100011` → geser kiri → `01000110` = `0x46` (write)

### Pengiriman Data: MSB First

Data dikirim **bit paling tinggi (MSB) duluan**:

```
     SCL:  ↑    ↑    ↑    ↑    ↑    ↑    ↑    ↑    ↑
           │    │    │    │    │    │    │    │    │
     SDA:  A6   A5   A4   A3   A2   A1   A0  R/W  ACK
           │    │    │    │    │    │    │    │    │
           MSB ──────────────────────────── LSB   │
                     7-bit address          │     │
                                         R/W bit  │
                                              Slave merespons
```

Setiap bit dibaca saat **SCL rising edge** (transisi LOW → HIGH).

---

## 7. ACK dan NACK

Setelah setiap **8 bit** (1 byte) dikirim, penerima harus memberikan respons:

### ACK (Acknowledge) — "Diterima!"

- Penerima **menarik SDA ke LOW** pada clock cycle ke-9.
- Artinya: "Saya menerima data dengan benar."

### NACK (Not Acknowledge) — "Tidak diterima!" atau "Cukup!"

- Penerima **membiarkan SDA tetap HIGH** pada clock cycle ke-9.
- Artinya bisa bermacam-macam:
  - Slave tidak ada di alamat tersebut.
  - Slave sedang sibuk.
  - Master sudah selesai membaca (sengaja NACK untuk menghentikan).

```
     Pengiriman 1 byte + ACK/NACK:

     SCL:  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑
           │  │  │  │  │  │  │  │  │
     SDA:  D7 D6 D5 D4 D3 D2 D1 D0 ACK
           │                        │
           │  8 bit data            │
           │  (dikirim pengirim)    │
           │                        │
           │                   SDA LOW = ACK  (penerima)
           │                   SDA HIGH = NACK (penerima)
           │
      Pengirim mengendalikan SDA     Penerima mengendalikan SDA
```

### Siapa yang Memberikan ACK?

| Situasi | Siapa pengirim? | Siapa yang ACK? |
|---|---|---|
| Master mengirim alamat | Master | **Slave** |
| Master menulis data | Master | **Slave** |
| Master membaca data | **Slave** | **Master** |
| Master selesai membaca (byte terakhir) | **Slave** | Master kirim **NACK** |

> **Penting:** Saat Master selesai membaca, Master mengirim **NACK** (bukan ACK)
> untuk memberitahu Slave: "Cukup, saya sudah selesai membaca."

---

## 8. Transaksi I2C Lengkap

### 8.1 Transaksi WRITE (Master → Slave)

Contoh: Master menulis 1 byte data ke BH1750.

```
Master menulis perintah "Power On" (0x01) ke BH1750 (alamat 0x23):

  │START│  Alamat + W   │ACK│   Data      │ACK│STOP│
  │     │               │   │             │   │    │
  │ S   │ 0 1 0 0 0 1 1  0 │ A │ 0 0 0 0 0 0 0 1 │ A │ P  │
  │     │ └─ 0x23 ────┘ W│   │ └── 0x01 ──────┘ │   │    │
  │     │                 │   │                   │   │    │
  │Master              Master│Slave           Master│Slave│Master
  │                        │                      │      │
  │     Fase 1: Alamat     │  Fase 2: Data        │      │
```

Langkah-langkah:
1. Master kirim **START**.
2. Master kirim **alamat 0x23 + bit Write (0)** = `01000110`.
3. Slave BH1750 merespons dengan **ACK** (menarik SDA LOW).
4. Master kirim **data 0x01** (perintah Power On).
5. Slave merespons dengan **ACK**.
6. Master kirim **STOP**.

### 8.2 Transaksi READ (Slave → Master)

Contoh: Master membaca 2 byte data dari BH1750.

```
Master membaca 2 byte intensitas cahaya dari BH1750:

  │START│  Alamat + R   │ACK│   Data 1    │ACK│   Data 2    │NACK│STOP│
  │     │               │   │             │   │             │    │    │
  │ S   │ 0 1 0 0 0 1 1  1 │ A │ X X X X X X X X │ A │ X X X X X X X X │ N  │ P  │
  │     │ └─ 0x23 ────┘ R│   │ └ byte HIGH ────┘ │   │ └ byte LOW ─────┘ │    │    │
  │     │                 │   │                   │   │                   │    │    │
  │Master              Master│Slave            Slave│Master            Slave│Master│Master
  │                        │                      │                      │         │
  │     Fase 1: Alamat     │  Fase 2: Data 1      │  Fase 3: Data 2      │         │
  │                        │  (Slave kirim)        │  (Slave kirim)        │         │
  │                        │  Master ACK           │  Master NACK          │         │
  │                        │  = "Lanjut kirim"     │  = "Cukup, terima kasih"       │
```

Langkah-langkah:
1. Master kirim **START**.
2. Master kirim **alamat 0x23 + bit Read (1)** = `01000111`.
3. Slave BH1750 merespons dengan **ACK**.
4. Slave mengirim **byte pertama** (High byte intensitas cahaya).
5. Master merespons dengan **ACK** ("Lanjut, kirim byte berikutnya").
6. Slave mengirim **byte kedua** (Low byte intensitas cahaya).
7. Master merespons dengan **NACK** ("Cukup, saya sudah selesai").
8. Master kirim **STOP**.

### 8.3 Transaksi WRITE lalu READ (dengan Repeated START)

Ini adalah pola yang **paling sering digunakan** untuk membaca register sensor.

Contoh: Membaca register dari BMP280.

```
  │START│ Alamat + W │ACK│ Reg Addr │ACK│ Sr │ Alamat + R │ACK│ Data │NACK│STOP│
  │     │            │   │          │   │    │            │   │      │    │    │
  │ S   │ 1110110  0 │ A │ 11111010 │ A │ Sr │ 1110110  1 │ A │ XXXX │ N  │ P  │
  │     │ 0x76    W  │   │  0xFA    │   │    │ 0x76    R  │   │      │    │    │
  │                  │   │          │   │    │            │   │      │    │    │
  │Master         Master│S│ Master  │S  │ M  │ Master     │S  │Slave │ M  │ M  │

  Sr = Repeated START (START tanpa STOP sebelumnya)
  S = Slave merespons
  M = Master merespons

  Fase 1: "Hai BMP280, saya mau baca register 0xFA"
  Fase 2: "OK, sekarang kirimkan datanya"
```

Langkah-langkah:
1. Master kirim **START**.
2. Master kirim **alamat BMP280 (0x76) + Write** → Slave ACK.
3. Master kirim **alamat register (0xFA)** → Slave ACK.
4. Master kirim **Repeated START** (tanpa STOP dulu!).
5. Master kirim **alamat BMP280 (0x76) + Read** → Slave ACK.
6. Slave mengirim **data register** → Master NACK.
7. Master kirim **STOP**.

> **Mengapa pakai Repeated START?**
> Karena Master perlu melakukan 2 hal:
> 1. WRITE: memberitahu slave register mana yang ingin dibaca.
> 2. READ: membaca data dari register tersebut.
> Tanpa Repeated START, Master harus STOP dulu lalu START lagi, dan slave
> lain bisa "menyerobot" bus di antara kedua transaksi.

---

## 9. Timing Diagram I2C

### Diagram Lengkap: Write 1 Byte

```
     ┌─── START                                                    STOP ───┐
     │                                                                     │
SDA ─╲   ┌───┐   ┌───┐       ┌───┐   ┌───┐       ┌───┐               ╱───
      ╲──┤ A6├───┤ A5├─ ... ─┤ A0├───┤ W ├───┐   │ACK│   ...    ╱───╱
         └───┘   └───┘       └───┘   └───┘   │   │   │      ╱──╱
                                              └───┘   └──────╱
                                                      Slave
                                                      menarik LOW

SCL ──────┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐──────────────
          └───┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───┘
           1       2       3       7       8       9
                                                   │
                                               ACK clock
```

### Timing Parameter Penting

| Parameter | Simbol | Standard Mode (100 kHz) | Fast Mode (400 kHz) |
|-----------|--------|------------------------|-------------------|
| Frekuensi SCL | f_SCL | ≤ 100 kHz | ≤ 400 kHz |
| Periode SCL | t_SCL | ≥ 10 µs | ≥ 2.5 µs |
| SCL HIGH time | t_HIGH | ≥ 4.0 µs | ≥ 0.6 µs |
| SCL LOW time | t_LOW | ≥ 4.7 µs | ≥ 1.3 µs |
| START hold time | t_HD;STA | ≥ 4.0 µs | ≥ 0.6 µs |
| START setup time | t_SU;STA | ≥ 4.7 µs | ≥ 0.6 µs |
| STOP setup time | t_SU;STO | ≥ 4.0 µs | ≥ 0.6 µs |
| Data hold time | t_HD;DAT | ≥ 0 µs | ≥ 0 µs |
| Data setup time | t_SU;DAT | ≥ 250 ns | ≥ 100 ns |

> Untuk project kita, kita akan menggunakan **Standard Mode (100 kHz)** karena
> lebih mudah diimplementasikan dan kedua sensor (BH1750, BMP280) mendukungnya.

---

## 10. Contoh Transaksi Sensor Kita

### 10.1 BH1750 — Membaca Intensitas Cahaya

Datasheet BH1750 (berdasarkan datasheet resmi):

| Item | Nilai |
|------|-------|
| Alamat I2C | 0x23 (ADDR pin = LOW) |
| Power On command | 0x01 |
| Continuous H-Resolution Mode | 0x10 |
| Waktu pengukuran | Maks. 180 ms |
| Format data | 2 byte (High byte, Low byte) |
| Rumus | Lux = (High_Byte × 256 + Low_Byte) / 1.2 |

Urutan lengkap membaca cahaya:

```
LANGKAH 1: Power On
  S → [0x46] → ACK → [0x01] → ACK → P
       addr+W          Power On cmd

LANGKAH 2: Set Mode (Continuous H-Resolution)
  S → [0x46] → ACK → [0x10] → ACK → P
       addr+W          Mode cmd

LANGKAH 3: Tunggu 180ms (waktu pengukuran)

LANGKAH 4: Baca Data (2 byte)
  S → [0x47] → ACK → [High Byte] → ACK → [Low Byte] → NACK → P
       addr+R          Slave kirim    Master    Slave kirim   Master
                                      ACK                     NACK
```

### 10.2 BMP280 — Membaca Temperatur dan Tekanan

Datasheet BMP280 (berdasarkan datasheet resmi):

| Item | Nilai |
|------|-------|
| Alamat I2C | 0x76 (SDO = LOW) atau 0x77 (SDO = HIGH) |
| Chip ID register | 0xD0 (berisi nilai 0x58) |
| Control register | 0xF4 |
| Temp data register | 0xFA (msb), 0xFB (lsb), 0xFC (xlsb) |
| Press data register | 0xF7 (msb), 0xF8 (lsb), 0xF9 (xlsb) |
| Calibration data | Register 0x88 - 0x9F (26 byte) |
| Resolusi | 20-bit (temperatur dan tekanan) |

Urutan membaca temperatur (disederhanakan):

```
LANGKAH 1: Baca Chip ID (untuk verifikasi sensor terhubung)
  S → [0xEC] → ACK → [0xD0] → ACK → Sr → [0xED] → ACK → [0x58] → NACK → P
       addr+W          reg addr        Sr    addr+R          chip ID
  Jika data = 0x58, sensor BMP280 terdeteksi!

LANGKAH 2: Baca Calibration Data (register 0x88-0x9F)
  S → [0xEC] → ACK → [0x88] → ACK → Sr → [0xED] → ACK → [26 byte cal data] → NACK → P
  Data ini digunakan untuk kompensasi pengukuran.

LANGKAH 3: Konfigurasi Sensor
  S → [0xEC] → ACK → [0xF4] → ACK → [config_value] → ACK → P
       addr+W          ctrl_meas reg    osrs_t, osrs_p, mode

LANGKAH 4: Baca Data Temperatur (3 byte mulai dari 0xFA)
  S → [0xEC] → ACK → [0xFA] → ACK → Sr → [0xED] → ACK → [msb][lsb][xlsb] → NACK → P
```

> **Catatan:** BMP280 lebih kompleks dari BH1750 karena:
> 1. Membutuhkan pembacaan **calibration coefficients** (26 byte).
> 2. Membutuhkan **kompensasi** menggunakan rumus dari datasheet.
> 3. Data temperatur dan tekanan masing-masing **20 bit** (3 register).
>
> Itulah mengapa di Tahap 4, kita akan membuat BH1750 driver **terlebih dahulu**
> (lebih sederhana), baru kemudian BMP280.

---

## 11. Indikator Keberhasilan Tahap 2

Sebelum lanjut ke Tahap 3, pastikan Anda memahami semua konsep berikut:

- [ ] Fungsi **SDA** (data) dan **SCL** (clock).
- [ ] Perbedaan **Master** (memulai komunikasi) dan **Slave** (merespons).
- [ ] Konsep **open-drain**: perangkat hanya bisa menarik LOW, HIGH berasal dari pull-up.
- [ ] **START condition**: SDA turun saat SCL HIGH.
- [ ] **STOP condition**: SDA naik saat SCL HIGH.
- [ ] **Repeated START**: START baru tanpa STOP sebelumnya.
- [ ] **7-bit address** + 1 bit R/W = 8 bit pertama setelah START.
- [ ] **ACK**: penerima menarik SDA LOW setelah 8 bit.
- [ ] **NACK**: penerima membiarkan SDA HIGH.
- [ ] Data dikirim **MSB first**, dibaca saat **SCL rising edge**.
- [ ] Urutan transaksi **Write**: S → Addr+W → ACK → Data → ACK → P
- [ ] Urutan transaksi **Read**: S → Addr+R → ACK → Data → NACK → P
- [ ] Urutan transaksi **Write lalu Read**: S → Addr+W → ACK → Reg → ACK → Sr → Addr+R → ACK → Data → NACK → P
- [ ] Memahami perbedaan kompleksitas BH1750 (sederhana) vs BMP280 (lebih kompleks).

> Jika ada konsep yang belum jelas, tanyakan sebelum lanjut ke Tahap 3.
> Tahap 3 adalah implementasi I2C Master di Verilog, dan membutuhkan
> pemahaman yang kuat tentang semua konsep di atas.
