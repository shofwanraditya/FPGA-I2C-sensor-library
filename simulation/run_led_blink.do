### ============================================================================
### File     : run_sim.do
### Project  : FPGA I2C Sensor Library
### Purpose  : Script simulasi Questa untuk tb_led_blink
###
### Cara Menjalankan:
###   1. Buka Questa (atau ModelSim)
###   2. Navigasi ke folder simulation:
###      cd {C:/Users/LENOVO/.gemini/antigravity/scratch/FPGA_I2C_SENSOR_LIBRARY/simulation}
###   3. Jalankan script ini:
###      do ../simulation/run_led_blink.do
### ============================================================================

# Keluar dari simulasi sebelumnya (jika ada)
quit -sim

# Buat work library (tempat penyimpanan hasil kompilasi)
# 'work' adalah nama default library di ModelSim/Questa
vlib work

# Kompilasi file Verilog
# vlog = Verilog Compiler
# -work work = simpan hasil ke library 'work'
vlog -work work ../rtl/led_blink.v
vlog -work work ../testbench/tb_led_blink.v

# Jalankan simulasi
# vsim = simulator
# work.tb_led_blink = module testbench yang akan disimulasikan
vsim -voptargs=+acc work.tb_led_blink

# Tambahkan sinyal ke waveform viewer
# add wave * = tambahkan SEMUA sinyal dari top level testbench
# add wave /tb_led_blink/dut/* = tambahkan sinyal internal dari DUT
add wave -position insertpoint sim:/tb_led_blink/*
add wave -position insertpoint sim:/tb_led_blink/dut/counter

# Jalankan simulasi
# 'run -all' menjalankan sampai $finish dipanggil di testbench
run -all

# Zoom fit waveform agar terlihat semua
wave zoom full
