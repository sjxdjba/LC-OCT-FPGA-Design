# LC-OCT Intelligent Imaging System Source

This repository is the organized source snapshot for the LC-OCT intelligent imaging system based on a three-chip heterogeneous architecture.

## Repository Layout

- `hardware/zynq7020_pzt_control/` - Zynq-7020-side PZT/ADC/DAC control HDL IP source.
- `software/zynq7020_closed_loop_app/` - latest Zynq-7020 standalone Vitis closed-loop control application.
- `hardware/xc7a35t_image_pcie/` - XC7A35T image-processing and PCIe/XDMA FPGA design snapshot.
- `software/rk3588_qt_panel/` - RK3588 Qt capture/control panel source.
- `software/rk3588_yolo/` - RK3588 YOLOv8n lesion-detection source package, including the current PT/ONNX model artifacts.
- `docs/handover/` - current hardware/software handover notes.

## Main Subsystems

### Zynq-7020 Control Side

The Zynq-7020 side contains the motor/PZT control, ADC/DAC interface, capture control IP, and the `closed_1_1` Vitis application.

Key paths:

- `hardware/zynq7020_pzt_control/hdl/motor_monitor_ip/`
- `software/zynq7020_closed_loop_app/src/`

### XC7A35T Image / PCIe Side

The XC7A35T side contains the LC-OCT image-processing pipeline and PCIe/XDMA data path used with RK3588.

Key paths:

- `hardware/xc7a35t_image_pcie/fpga_tuxiang_pcie_current/pcie/`
- `hardware/xc7a35t_image_pcie/fpga_tuxiang_pcie_current/ph_pcie_ip/`
- `hardware/xc7a35t_image_pcie/fpga_tuxiang_pcie_current/prj/`

### RK3588 Application Side

The RK3588 side contains the Qt panel and YOLO source package used for embedded acquisition, preview, and lesion detection.

Key paths:

- `software/rk3588_qt_panel/`
- `software/rk3588_yolo/`

## What Is Excluded

Generated outputs are intentionally excluded from the latest tree:

- Vivado runs/caches/bitstreams
- Vitis/CMake build folders
- `BOOT.bin`, `.bit`, `.elf`, object files, and local logs

The YOLO `.pt` and `.onnx` model files are retained because they are small enough for GitHub and are part of the runnable RK3588 demo snapshot.
