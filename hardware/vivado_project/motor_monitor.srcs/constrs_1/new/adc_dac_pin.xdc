# ============================================================
# ADC / DAC pin constraints for synthesized BD top: system_wrapper
# Generated from current synthesized external port names:
#   adc_burst_0
#   adc_busy_0
#   adc_chsel_0[2:0]
#   adc_convst_0
#   adc_cs_n_0
#   adc_data_bus_0[15:0]
#   adc_hw_rngsel_0[1:0]
#   adc_rd_n_0
#   adc_refsel_0
#   adc_reset_n_0
#   adc_seqen_0
#   adc_ser1w_0
#   adc_ser_par_0
#   dac_m1_cs_0
#   dac_m1_sclk_0
#   dac_m1_sdi_0
#   dac_m2_cs_0
#   dac_m2_sclk_0
#   dac_m2_sdi_0
#   dac_cam_cs_0
#   dac_cam_sclk_0
#   dac_cam_sdi_0
#
# Pin source:
#   C:\Users\sjxdjba\Desktop\fpgastudy\zynq\motor_monitor\XDC寮曡剼绾︽潫.txt
#
# Important:
# - The txt only provides AD7616 module pins.
# - No FPGA pins were provided for DAC or for adc_refsel_0 / adc_seqen_0 / adc_ser1w_0.
# - Those unresolved ports are intentionally left unconstrained below.
# ============================================================

# -----------------------------
# I/O standard assumptions
# -----------------------------
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data_bus_0[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports adc_busy_0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_convst_0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_cs_n_0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_rd_n_0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_reset_n_0]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_chsel_0[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_hw_rngsel_0[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports adc_burst_0]
set_property IOSTANDARD LVCMOS33 [get_ports adc_ser_par_0]

# -----------------------------
# AD7616 data bus
# txt mapping:
#   D0  - Y13
#   D1  - Y12
#   D2  - V11
#   D3  - V10
#   D4  - W10
#   D5  - W9
#   D6  - Y9
#   D7  - Y8
#   D8  - Y7
#   D9  - Y6
#   D10 - W6
#   D11 - V6
#   D12 - U10
#   D13 - T9
#   D14 - U9
#   D15 - U8
# -----------------------------
set_property PACKAGE_PIN Y13 [get_ports {adc_data_bus_0[0]}]
set_property PACKAGE_PIN Y12 [get_ports {adc_data_bus_0[1]}]
set_property PACKAGE_PIN V11 [get_ports {adc_data_bus_0[2]}]
set_property PACKAGE_PIN V10 [get_ports {adc_data_bus_0[3]}]
set_property PACKAGE_PIN W10 [get_ports {adc_data_bus_0[4]}]
set_property PACKAGE_PIN W9  [get_ports {adc_data_bus_0[5]}]
set_property PACKAGE_PIN Y9  [get_ports {adc_data_bus_0[6]}]
set_property PACKAGE_PIN Y8  [get_ports {adc_data_bus_0[7]}]
set_property PACKAGE_PIN Y7  [get_ports {adc_data_bus_0[8]}]
set_property PACKAGE_PIN Y6  [get_ports {adc_data_bus_0[9]}]
set_property PACKAGE_PIN W6  [get_ports {adc_data_bus_0[10]}]
set_property PACKAGE_PIN V6  [get_ports {adc_data_bus_0[11]}]
set_property PACKAGE_PIN U10 [get_ports {adc_data_bus_0[12]}]
set_property PACKAGE_PIN T9  [get_ports {adc_data_bus_0[13]}]
set_property PACKAGE_PIN U9  [get_ports {adc_data_bus_0[14]}]
set_property PACKAGE_PIN U8  [get_ports {adc_data_bus_0[15]}]

# -----------------------------
# AD7616 control / status
# txt mapping:
#   BUSY - Y11
#   CONV - W13
#   CS   - U13
#   RD   - V13
#   RST  - U15
# -----------------------------
set_property PACKAGE_PIN Y11 [get_ports adc_busy_0]
set_property PACKAGE_PIN W13 [get_ports adc_convst_0]
set_property PACKAGE_PIN U13 [get_ports adc_cs_n_0]
set_property PACKAGE_PIN V13 [get_ports adc_rd_n_0]
set_property PACKAGE_PIN U15 [get_ports adc_reset_n_0]

# -----------------------------
# Channel select
# txt mapping:
#   CHS0 - U14
#   CHS1 - V12
#   CHS2 - W14
# -----------------------------
set_property PACKAGE_PIN U14 [get_ports {adc_chsel_0[0]}]
set_property PACKAGE_PIN V12 [get_ports {adc_chsel_0[1]}]
set_property PACKAGE_PIN W14 [get_ports {adc_chsel_0[2]}]

# -----------------------------
# Range select
# txt mapping:
#   RNG0 - V15
#   RNG1 - W15
# -----------------------------
set_property PACKAGE_PIN V15 [get_ports {adc_hw_rngsel_0[0]}]
set_property PACKAGE_PIN W15 [get_ports {adc_hw_rngsel_0[1]}]

# -----------------------------
# Mode pins
# txt mapping:
#   WD  - W11  (used as BURST in current hardware parallel mode)
#   SER - Y14
# -----------------------------
set_property PACKAGE_PIN W11 [get_ports adc_burst_0]
set_property PACKAGE_PIN Y14 [get_ports adc_ser_par_0]

# -----------------------------
# Unresolved / not provided by pin txt
# -----------------------------
# adc_refsel_0
# adc_seqen_0
# adc_ser1w_0

# -----------------------------
# DAC8830 module pins
# txt mapping:
#   M1 cs/sclk/sdi -> M19/U19/J14
#   M2 cs/sclk/sdi -> U20/N17/V20
#   CAM cs/sclk/sdi -> R17/W19/P16
# -----------------------------
set_property IOSTANDARD LVCMOS33 [get_ports dac_m1_cs_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_m1_sclk_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_m1_sdi_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_m2_cs_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_m2_sclk_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_m2_sdi_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_cam_cs_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_cam_sclk_0]
set_property IOSTANDARD LVCMOS33 [get_ports dac_cam_sdi_0]

set_property PACKAGE_PIN M19 [get_ports dac_m1_cs_0]
set_property PACKAGE_PIN U19 [get_ports dac_m1_sclk_0]
set_property PACKAGE_PIN J14 [get_ports dac_m1_sdi_0]

set_property PACKAGE_PIN U20 [get_ports dac_m2_cs_0]
set_property PACKAGE_PIN N17 [get_ports dac_m2_sclk_0]
set_property PACKAGE_PIN V20 [get_ports dac_m2_sdi_0]

set_property PACKAGE_PIN R17 [get_ports dac_cam_cs_0]
set_property PACKAGE_PIN W19 [get_ports dac_cam_sclk_0]
set_property PACKAGE_PIN P16 [get_ports dac_cam_sdi_0]


#set_property IOSTANDARD LVCMOS33 [get_ports adc_refsel_0]
#set_property IOSTANDARD LVCMOS33 [get_ports adc_ser1w_0]
#set_property IOSTANDARD LVCMOS33 [get_ports adc_seqen_0]

# -----------------------------
# UART0 EMIO
#   TXD -> T15
#   RXD -> W16
# -----------------------------
set_property IOSTANDARD LVCMOS33 [get_ports uart_rtl_0_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rtl_0_txd]
set_property PACKAGE_PIN W16 [get_ports uart_rtl_0_txd]
set_property PACKAGE_PIN T15 [get_ports uart_rtl_0_rxd]
