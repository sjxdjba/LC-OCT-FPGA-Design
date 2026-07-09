# RK3588 Qt Capture Panel Snapshot

This folder is the current active Qt panel source copied from RK3588:

`/home/elf/rk3568_capture/qt_panel`

It contains only current source files and helper scripts. Local build output, historical `.bak` files, `_codex_backups/`, datasets, videos, and model files are not included.

## Files

- `main.cpp` - Qt application entry.
- `mainwindow.cpp/.h` - main panel UI, diagnosis management, XDMA status/control, YOLO/RKNN analysis launch, and video opening logic.
- `capture_worker.cpp/.h` - capture/dataset playback worker, XDMA H2C/C2H transfer, FPGA processed cache generation, and realtime preview generation.
- `CMakeLists.txt` and `oct_qt_panel.pro` - CMake/qmake build entries.
- `capture_current_panel_screenshots.sh`, `xwd_to_png.py` - screenshot helper scripts used during remote validation.

## Build On RK3588

```bash
cd /home/elf/rk3568_capture/qt_panel
mkdir -p build
cd build
cmake ..
make -j4
```

The expected binary is:

`/home/elf/rk3568_capture/qt_panel/build/oct_qt_panel`

The CMake project links the local camera SDK libraries:

- `/usr/include/camcmosoctusb3`
- `/usr/local/lib/camcmosoctusb3_1.2`

## Current Runtime Assumptions

- Default left realtime image source: `/home/elf/Desktop/input_preview/test`
- Matching FPGA raw input source: `/home/elf/Desktop/raw_fpga_current_names/test`
- FPGA processed diagnosis cache: `fpga_processed_images/*.pgm`
- YOLO/RKNN runtime directory expected by the panel: `/home/elf/Desktop/yolo/03_rk3588_model`
- YOLO script expected by the panel: `predict_batch.py`
- Analysis video opened by the panel: `yolo_rknn_annotated_stream.avi` or `yolo_rknn_annotated_stream.mp4`

The right realtime FPGA preview is intentionally generated from the cached FPGA processed PGM path so that it matches the image source used by the YOLO/RKNN analysis video.
