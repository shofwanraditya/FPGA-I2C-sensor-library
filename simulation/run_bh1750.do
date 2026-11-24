# ============================================================================
# Script Questa/ModelSim: run_bh1750.do
# ============================================================================

quit -sim

vlib work

# Kompilasi RTL dan Testbench
vlog -work work ../rtl/i2c_master.v
vlog -work work ../rtl/bh1750_driver.v
vlog -work work ../testbench/tb_bh1750.v

# Muat simulasi
vsim -voptargs="+acc" work.tb_bh1750

# Waveform setup
add wave -divider "BH1750 DRIVER"
add wave -color Yellow /tb_bh1750/clk
add wave -color Orange /tb_bh1750/rst_n
add wave /tb_bh1750/start_meas
add wave /tb_bh1750/busy
add wave /tb_bh1750/data_valid
add wave -radix hexadecimal /tb_bh1750/data_lux
add wave -radix unsigned /tb_bh1750/u_bh1750/state

add wave -divider "I2C BUS"
add wave -color Cyan /tb_bh1750/scl
add wave -color Cyan /tb_bh1750/sda

run -all
wave zoom full
