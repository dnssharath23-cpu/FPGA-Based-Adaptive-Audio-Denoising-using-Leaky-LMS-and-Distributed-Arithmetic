################################################################################
# EDGE Artix-7 XC7A35T LLMS Project Constraints
################################################################################

###############################################################################
# 1. 50 MHz On-board Clock (N11)
###############################################################################
# Clock pin N11 from EDGE Artix-7 manual (50 MHz oscillator)
set_property PACKAGE_PIN N11 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# 50 MHz clock period = 20 ns
create_clock -name sys_clk -period 50.000 [get_ports clk]


###############################################################################
# 2. Reset Button (active-low) - use SW3 at L5
###############################################################################
# Slide switch SW3 connected to FPGA pin L5 (from manual)
set_property PACKAGE_PIN L5 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]


###############################################################################
# 3. Status LED - use D3 at J3
###############################################################################
# LED D3 connected to FPGA pin J3 (from manual)
set_property PACKAGE_PIN J3 [get_ports led_active]
set_property IOSTANDARD LVCMOS33 [get_ports led_active]


###############################################################################
# 4. USB-UART Interface (FT2232H)
###############################################################################
# According to manual: C4 = TXD (FPGA output), D4 = RXD (FPGA input)

# FPGA receives data from PC on uart_rx_pin (RXD line of FTDI)
set_property PACKAGE_PIN D4 [get_ports uart_rx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]

# FPGA sends data to PC on uart_tx_pin (TXD line of FTDI)
set_property PACKAGE_PIN C4 [get_ports uart_tx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]


###############################################################################
# 5. (Optional) Additional debug IO
###############################################################################
# You can later map more switches or LEDs if needed, e.g.:
# set_property PACKAGE_PIN L4 [get_ports debug_sw0]  ; SW4
# set_property IOSTANDARD LVCMOS33 [get_ports debug_sw0]
#
# set_property PACKAGE_PIN H3 [get_ports debug_led0] ; D4
# set_property IOSTANDARD LVCMOS33 [get_ports debug_led0]

###############################################################################
# End of file
###############################################################################