# RK3588 Deployment Notes

## Files

- PyTorch model: `models/yolov8n_lcoct_fpga_best.pt`
- ONNX model: `models/yolov8n_lcoct_fpga_best.onnx`

## Preprocess

Use standard YOLO preprocessing:

1. Read the FPGA-processed LC-OCT image.
2. Convert grayscale input to 3-channel RGB if needed.
3. Apply letterbox resize to 640 x 640.
4. Normalize pixel values to 0.0 to 1.0.
5. Use NCHW layout.

## Postprocess

1. Decode YOLOv8 boxes.
2. Run NMS with IoU threshold 0.50.
3. Keep class id 0 only.
4. Keep boxes with confidence >= 0.40.
5. If no box remains, output `no lesion`.

## RKNN conversion

Use RKNN-Toolkit2 to convert the ONNX model.

Recommended settings:

- Fixed input shape: `[1, 3, 640, 640]`
- Quantization calibration images: FPGA-processed training images
- Include both positive and negative images in the calibration set

Before integrating into the Qt application, test the ONNX model on a small
batch of FPGA-processed images and compare the boxes with the Python output.

