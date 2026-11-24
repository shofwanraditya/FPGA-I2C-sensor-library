# ============================================================================
# Script Questa/ModelSim: run_top_module.do
# ============================================================================

quit -sim

vlib work

# Kompilasi seluruh file RTL modular
vlog -work work ../rtl/i2c_master.v
vlog -work work ../rtl/bh1750_driver.v
vlog -work work ../rtl/bmp280_driver.v
vlog -work work ../rtl/uart_tx.v
vlog -work work ../rtl/top_module.v

# Kompilasi Testbench Top Module
vlog -work work ../testbench/tb_top_module.v

# Muat simulasi
vsim -voptargs="+acc" work.tb_top_module

# Waveform setup
add wave -divider "TOP CONTROL & STATUS"
add wave -color Yellow /tb_top_module/clk
add wave -color Orange /tb_top_module/rst_n
add wave /tb_top_module/trigger_btn
add wave /tb_top_module/led_busy
add wave /tb_top_module/led_error
add wave -radix unsigned /tb_top_module/dut/top_state

add wave -divider "I2C BUS (SHARED)"
add wave -color Cyan /tb_top_module/i2c_scl
add wave -color Cyan /tb_top_module/i2c_sda

add wave -divider "UART TRANSMITTER"
add wave -color Magenta /tb_top_module/uart_tx_pin

run -all
wave zoom full
