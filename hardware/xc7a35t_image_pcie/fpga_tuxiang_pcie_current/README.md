# LC-OCT FPGA Image Processing / PCIe Snapshot

This folder is a clean source snapshot of the current FPGA image-processing project originally kept at:

`D:\FPGA20251016\tuxiang_pcie`

It targets the Ascent Pro FPGA board and is used by the RK3588 panel through PCIe/XDMA.

## Contents

- `constraints/` - Ascent Pro PCIe/XDMA pin and timing constraints.
- `pcie/` - XDMA endpoint top level and RK3588 H2C/C2H image-stream adapter.
- `ph_pcie_ip/` - LC-OCT image-processing core, including FFT/Hilbert/IFFT envelope path and Xilinx FFT IP `.xci` files.
- `prj/` - Vivado project entry and build Tcl scripts.
- `README_FPGA_IMAGE_PACKAGE.md` - earlier local package note.

## Current FPGA Parameters

- Vivado part: `xc7a35tfgg484-2`
- Top module: `xilinx_dma_pcie_ep`
- Frame size: `2048 x 4096`
- `FRAME_CFG`: `0x10000800`
- `VERSION`: `0x20260619`
- Normal `PH_EVENTS`: `0`

Data path:

`RK3588 XDMA H2C 64-bit -> 16-bit OCT samples -> FFT/Hilbert/IFFT processing -> frame wrapper -> XDMA C2H 64-bit -> RK3588`

## Rebuild

Open Vivado 2025.2 or newer from this folder:

```tcl
cd hardware/fpga_tuxiang_pcie_current/prj
source create_project.tcl
source build_bitstream.tcl
```

The generated bitstream path is:

`hardware/fpga_tuxiang_pcie_current/prj/tuxiang_pcie.runs/impl_1/xilinx_dma_pcie_ep.bit`

Generated runs, caches, bitstreams, and Flash images are ignored by Git. Regenerate them locally when needed.

## Basic Link Check

After programming the FPGA and booting/enumerating PCIe on RK3588, the expected one-frame check is:

- `FRAME_CFG = 0x10000800`
- `VERSION = 0x20260619`
- `PH_EVENTS = 0`
- after one XDMA frame: `H2C_LINES = 4096`, `C2H_FRAMES = 1`
