# ============================================================================
# Script Questa/ModelSim: run_bmp280.do
# ============================================================================

quit -sim

vlib work

# Kompilasi RTL dan Testbench
vlog -work work ../rtl/i2c_master.v
vlog -work work ../rtl/bmp280_driver.v
vlog -work work ../testbench/tb_bmp280.v

# Muat simulasi
vsim -voptargs="+acc" work.tb_bmp280

# Waveform setup
add wave -divider "BMP280 DRIVER"
add wave -color Yellow /tb_bmp280/clk
add wave -color Orange /tb_bmp280/rst_n
add wave /tb_bmp280/start_meas
add wave /tb_bmp280/busy
add wave /tb_bmp280/chip_id_ok
add wave /tb_bmp280/data_valid
add wave -radix hexadecimal /tb_bmp280/press_raw
add wave -radix hexadecimal /tb_bmp280/temp_raw
add wave -radix unsigned /tb_bmp280/u_bmp280/state

add wave -divider "I2C BUS"
add wave -color Cyan /tb_bmp280/scl
add wave -color Cyan /tb_bmp280/sda

run -all
wave zoom full
