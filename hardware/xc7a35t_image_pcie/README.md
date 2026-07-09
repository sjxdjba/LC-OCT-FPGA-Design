# Hardware

## Vivado Project Snapshot

`vivado_project/` contains the current Vivado project metadata needed to identify the active hardware design:

- `motor_monitor.xpr`
- `motor_monitor.srcs/sources_1/bd/system/system.bd`
- `motor_monitor.srcs/sources_1/bd/system/ip/*.xci`
- `motor_monitor.srcs/sources_1/new/system_iobuf_top.v`
- `motor_monitor.srcs/constrs_1/new/adc_dac_pin.xdc`
- `motor_monitor.gen/sources_1/bd/system/hdl/system_wrapper.v`

## Active Custom IP

`ip/model_capture_axi_top_v4_1_rev6/ipshared_1423/` is the HDL source snapshot for the actual BD instance:

- VLNV: `xilinx.com:user:model_capture_axi_top:4.1`
- IP revision: `6`
- Instance XCI: `vivado_project/motor_monitor.srcs/sources_1/bd/system/ip/system_model_capture_axi_top_0_5.xci`

This IP includes the closed-loop PZT velocity-control path and the matching AXI-Lite register map used by `software/vitis_closed_1_1`.

## LC-OCT Image Processing / PCIe Snapshot

`fpga_tuxiang_pcie_current/` is the current Ascent Pro FPGA image-processing design snapshot used with RK3588 over PCIe/XDMA.

Key entry points:

- Top module: `pcie/xilinx_dma_pcie_ep.sv`
- PCIe image app: `pcie/ascent_pcie_ph_app.v`
- Image core wrapper: `ph_pcie_ip/ph_ip.v`
- Core pipeline: `ph_pcie_ip/ph_core_pipeline.v`
- Build scripts: `prj/create_project.tcl` and `prj/build_bitstream.tcl`

This directory intentionally stores source and IP configuration files only. Vivado generated outputs under `.Xil/`, `*.runs/`, `*.cache/`, bitstreams, and Flash images are not committed.
