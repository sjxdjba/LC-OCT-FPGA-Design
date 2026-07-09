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
