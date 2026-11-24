# ============================================================================
# Script Questa/ModelSim: run_i2c_master.do
# ============================================================================

quit -sim

# Buat library work jika belum ada
vlib work

# Kompilasi file RTL dan Testbench
vlog -work work ../rtl/i2c_master.v
vlog -work work ../testbench/tb_i2c_master.v

# Muat simulasi
vsim -voptargs="+acc" work.tb_i2c_master

# Tambahkan sinyal penting ke waveform
add wave -divider "MASTER CONTROL"
add wave -color Yellow /tb_i2c_master/clk
add wave -color Orange /tb_i2c_master/rst_n
add wave -radix hexadecimal /tb_i2c_master/cmd
add wave /tb_i2c_master/cmd_valid
add wave /tb_i2c_master/busy
add wave /tb_i2c_master/done
add wave -radix hexadecimal /tb_i2c_master/data_in
add wave -radix hexadecimal /tb_i2c_master/data_out
add wave /tb_i2c_master/ack_error

add wave -divider "I2C BUS (PHYSICAL)"
add wave -color Cyan /tb_i2c_master/scl
add wave -color Cyan /tb_i2c_master/sda

add wave -divider "FSM STATE"
add wave -radix unsigned /tb_i2c_master/dut/state
add wave -radix unsigned /tb_i2c_master/dut/bit_cnt

# Jalankan simulasi sampai selesai
run -all

# Zoom waveform agar terlihat penuh
wave zoom full
