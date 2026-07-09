# Hardware

## Zynq-7020 PZT Control

`zynq7020_pzt_control/` contains the control-side Verilog IP package for ADC/DAC/PZT capture and closed-loop control.

## XC7A35T Image Processing / PCIe

`xc7a35t_image_pcie/` contains the image-processing FPGA project snapshot for the Ascent Pro XC7A35T board.

Important entry points:

- Top module: `fpga_tuxiang_pcie_current/pcie/xilinx_dma_pcie_ep.sv`
- PCIe image app: `fpga_tuxiang_pcie_current/pcie/ascent_pcie_ph_app.v`
- LC-OCT processing wrapper: `fpga_tuxiang_pcie_current/ph_pcie_ip/ph_ip.v`
- Core pipeline: `fpga_tuxiang_pcie_current/ph_pcie_ip/ph_core_pipeline.v`
- Build scripts: `fpga_tuxiang_pcie_current/prj/create_project.tcl`, `fpga_tuxiang_pcie_current/prj/build_bitstream.tcl`
