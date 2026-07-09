# 当前 LC-OCT FPGA + RK3588 + Qt 面板交接说明

更新时间：2026-07-09

本文档说明当前已经整理进仓库的两部分源码：

- FPGA 图像处理/PCIe 工程：`hardware/fpga_tuxiang_pcie_current/`
- RK3588 Qt 采集面板工程：`software/rk3588_qt_panel_current/`

仓库只保存源码、约束、IP 配置和构建入口；不保存 Vivado 生成目录、bitstream、Flash 镜像、RKNN/ONNX/PT 模型、数据集、诊断缓存或视频结果。

## 1. 项目整体流程

当前系统的目标是让 RK3588 与升腾 Pro FPGA 通过 PCIe/XDMA 组成一条 LC-OCT 图像处理和识别链路。

主流程如下：

1. RK3588 Qt 面板读取桌面数据集或相机数据。
2. 左侧实时窗口显示逆向后的 OCT 预览图，当前默认来自 `/home/elf/Desktop/input_preview/test`。
3. Qt 面板找到同名 FPGA 输入 raw 数据，当前默认来自 `/home/elf/Desktop/raw_fpga_current_names/test`。
4. RK3588 通过 XDMA H2C 把一帧 `2048 x 4096` 的 16-bit OCT 数据送进 FPGA。
5. FPGA 内部执行图像处理：64-bit XDMA 输入拆成 16-bit OCT 样本，经过 FFT/Hilbert/IFFT 相关处理，再封装为 C2H 输出流。
6. RK3588 接收 FPGA C2H 结果，缓存为诊断目录下的 `fpga_processed_images/*.pgm`。
7. 右侧实时 FPGA 图像从缓存下来的 `fpga_processed_images/*.pgm` 生成，以保证和后续 YOLO 分析视频使用同一批 FPGA 处理结果。
8. 点击“分析识别”后，Qt 面板调用 `/home/elf/Desktop/yolo/03_rk3588_model/predict_batch.py`，输入为诊断目录里的 FPGA processed 图像，输出并打开 YOLO/RKNN 标注视频。

关键点：分析识别的视频流应该来自 FPGA 处理后的 `fpga_processed_images/*.pgm`，不要接 `input_preview`、普通数据集预览图、raw 线图或其他中间路径。

## 2. FPGA 工程说明

源码目录：`hardware/fpga_tuxiang_pcie_current/`

来源目录：`D:\FPGA20251016\tuxiang_pcie`

主要文件：

- `pcie/xilinx_dma_pcie_ep.sv`：顶层模块，连接 XDMA IP 与图像处理应用。
- `pcie/ascent_pcie_ph_app.v`：RK3588 <-> FPGA 图像处理 PCIe 应用层，包含寄存器、H2C/C2H 计数、bypass/processing 选择和帧封装。
- `pcie/ascent_h2c64_to_u16_axis.v`：把 XDMA H2C 64-bit 数据拆成单像素 16-bit OCT 样本流。
- `pcie/axis_line_to_frame.v`：把逐行 `tlast` 转成整帧 `tlast`。
- `ph_pcie_ip/ph_ip.v`：图像处理 IP 顶层包装。
- `ph_pcie_ip/ph_core_pipeline.v`：图像处理核心流水线。
- `ph_pcie_ip/hilbert_filter.v`：Hilbert 相关处理模块。
- `ph_pcie_ip/xfft*_*/`：Xilinx FFT IP 配置文件 `.xci`。
- `constraints/ascent_pro_xdma_pcie.xdc`：升腾 Pro PCIe/XDMA 约束。
- `prj/create_project.tcl`：重建 Vivado 工程。
- `prj/build_bitstream.tcl`：综合、实现并生成 bitstream。

当前关键参数：

- FPGA 器件：`xc7a35tfgg484-2`
- Vivado：当前工程按 Vivado 2025.2 使用
- Top：`xilinx_dma_pcie_ep`
- 单帧尺寸：`2048 x 4096`
- `FRAME_CFG`：`0x10000800`
- `VERSION`：`0x20260619`
- 正常 `PH_EVENTS`：`0`

重建方法：

```tcl
cd hardware/fpga_tuxiang_pcie_current/prj
source create_project.tcl
source build_bitstream.tcl
```

生成的 bitstream 会在：

`hardware/fpga_tuxiang_pcie_current/prj/tuxiang_pcie.runs/impl_1/xilinx_dma_pcie_ep.bit`

这些生成文件不进 Git，需要本地 Vivado 重新生成。

## 3. FPGA 下载和链路检查

下载 bitstream 后，RK3588 端应能枚举 XDMA 设备。基础检查标准：

- 读 PCIe `resource0` 寄存器，确认 `FRAME_CFG = 0x10000800`
- 确认 `VERSION = 0x20260619`
- 确认 `PH_EVENTS = 0`
- 独立跑一帧 XDMA 测试后确认 `H2C_LINES = 4096`
- 确认 `C2H_FRAMES = 1`

如果 FPGA 固化到 Flash 后没有枚举 PCIe，通常需要整机重新上电再看 PCIe 枚举；单纯热复位有时不够。

## 4. RK3588 Qt 面板说明

源码目录：`software/rk3588_qt_panel_current/`

来源目录：`/home/elf/rk3568_capture/qt_panel`

主要文件：

- `main.cpp`：Qt 程序入口。
- `mainwindow.cpp/.h`：主窗口 UI、采集按钮、诊断目录、PCIe/电机控制、分析识别调用、视频打开逻辑。
- `capture_worker.cpp/.h`：采集线程、数据集循环、XDMA 传输、FPGA processed PGM 缓存、左右实时图生成。
- `CMakeLists.txt`：CMake 构建入口。
- `oct_qt_panel.pro`：qmake 构建入口。

当前面板重要行为：

- 采集参数里不再显示 `FPGA Image processing` 开关，保持当前默认流程。
- 点击“分析识别”只打开 YOLO/RKNN 标注视频，不再额外打开 raw/fpga 中间视频。
- 左侧实时图来自 `input_preview/test`。
- 右侧实时图来自本次诊断目录缓存下来的 `fpga_processed_images/*.pgm`，并采用和分析视频一致的 FPGA processed 图像来源。
- 分析识别同样使用 `fpga_processed_images/*.pgm` 作为输入。

构建方法：

```bash
cd /home/elf/rk3568_capture/qt_panel
mkdir -p build
cd build
cmake ..
make -j4
```

生成程序：

`/home/elf/rk3568_capture/qt_panel/build/oct_qt_panel`

依赖：

- Qt5 或 Qt6 Widgets/Core
- `pthread`
- `rt`
- `gentlcamcmosoctusb3`
- `camcmosoctusb3`
- 相机 SDK 头文件：`/usr/include/camcmosoctusb3`
- 相机 SDK 库：`/usr/local/lib/camcmosoctusb3_1.2`

## 5. 当前数据和模型路径

当前仓库不保存数据和模型，只记录运行时约定路径。

RK3588 当前必要路径：

- 逆向 OCT 预览图：`/home/elf/Desktop/input_preview/test`
- FPGA 输入 raw：`/home/elf/Desktop/raw_fpga_current_names/test`
- 当前 YOLO/RKNN 运行目录：`/home/elf/Desktop/yolo/03_rk3588_model`
- 当前 YOLO 推理脚本：`/home/elf/Desktop/yolo/03_rk3588_model/predict_batch.py`

一次诊断/采集会生成：

- `fpga_processed_images/*.pgm`：FPGA 处理后的 PGM 缓存，右侧实时图和 YOLO 分析应以它为准。
- `analysis/`：分析输出目录。
- `yolo_rknn_annotated_stream.avi` 或 `yolo_rknn_annotated_stream.mp4`：Qt 面板点击“分析识别”后应打开的视频。

注意：不要把旧模型、备用数据集、测试视频和诊断缓存提交到仓库。

## 6. 为什么要转 RKNN

RK3588 上的 NPU 推理需要 RKNN 格式。训练端一般给出 YOLO 的 `.pt` 或 `.onnx`，这些文件不能直接作为 RK3588 NPU 的最终部署格式。部署到板端时，需要用 Rockchip 的 RKNN-Toolkit2 转成 `.rknn`，再由板端 Python 推理脚本调用 RKNN Runtime。

通常流程：

1. 训练端导出 YOLO ONNX。
2. 使用 RKNN-Toolkit2 加载 ONNX。
3. 配置输入尺寸、量化方式和目标平台，例如 RK3588。
4. build/export 得到 `.rknn`。
5. 把 `.rknn` 和 `predict_batch.py` 放到 `/home/elf/Desktop/yolo/03_rk3588_model`。
6. Qt 面板点击“分析识别”时调用该目录下的脚本，输出 YOLO 标注视频。

如果模型部署异常，优先检查：

- 模型输入图像是否来自 `fpga_processed_images/*.pgm`。
- 训练时使用的 FPGA processed 图像风格是否和板端当前 FPGA 输出一致。
- 类别名、输入尺寸、归一化/反相逻辑是否和训练脚本一致。
- 输出视频文件名是否仍为面板会查找的 `yolo_rknn_annotated_stream.avi/mp4`。

## 7. 仓库整理原则

本次整理进仓库的是源码快照，不是完整运行数据包。

已放入：

- FPGA HDL、XDC、XCI、Vivado Tcl 和 `.xpr` 工程入口。
- RK3588 Qt 面板当前源码、CMake/qmake 文件和截图辅助脚本。
- 中文说明文件。

未放入：

- Vivado `.Xil/`、`*.runs/`、`*.cache/`、bitstream、mcs、日志。
- Qt `build/` 目录和历史 `.bak`、`before_*`、`_codex_backups/`。
- RKNN/ONNX/PT 模型。
- 数据集、测试集、诊断结果、截图、视频、PGM/RAW 中间文件。

这样做的目的是让同门能清楚看到 FPGA 内部处理流程和 Qt 面板调用逻辑，同时避免 GitHub 仓库被大文件和临时数据污染。
