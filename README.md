# LC-OCT FPGA Design

This repository contains the current FPGA hardware source snapshot and the latest Vitis software application for the LC-OCT motor/PZT control design.

## Layout

- `hardware/vivado_project/` - Vivado project entry files, block design, current top-level wrapper source, selected XCI customizations, and active XDC constraints.
- `hardware/ip/model_capture_axi_top_v4_1_rev6/` - HDL source snapshot for the active custom IP instance used by the Vivado block design.
- `hardware/export/` - hardware handoff files used by the latest Vitis platform/application.
- `software/vitis_closed_1_1/` - latest standalone Vitis application source, `Dual PZT Closed Loop Control App 1.1`.

## Current Versions

- Target FPGA: `xc7z020clg400-2`
- Vivado tool version: `2025.2`
- Hardware top module: `system_iobuf_top`
- Active custom IP instance: `xilinx.com:user:model_capture_axi_top:4.1`, IP revision `6`
- Latest software application: `closed_1_1`
- Software platform: `closed_loop`, based on `hardware/export/pzt_ctl_closed_loop.xsa`

## Notes

The original workspace contains many Vivado/Vitis generated directories. They are intentionally not committed here except for small handoff/configuration files that help preserve the current hardware/software interface.

The older `motor_monitor_ip/component.xml` package in the original workspace reports `model_capture_axi_top` version `3.0`; the active block-design instance is `model_capture_axi_top:4.1 Rev 6`, so this repository uses the `4.1 Rev 6` HDL snapshot.
