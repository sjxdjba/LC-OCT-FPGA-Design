# LC-OCT FPGA YOLOv8n Lesion Detection

This package contains the YOLO part of the LC-OCT embedded imaging demo.
It includes training, evaluation, prediction, ONNX export, and a lightweight
ONNX inference reference for deployment on RK3588.

## Directory

```text
yolo_code_package/
  configs/
    data.yaml.example
    model_metadata.json
  docs/
    RK3588_deployment_notes.md
    model_card.md
  models/
    yolov8n_lcoct_fpga_best.pt
    yolov8n_lcoct_fpga_best.onnx
  src/
    common.py
    train.py
    evaluate.py
    predict.py
    export_onnx.py
    onnx_infer.py
  requirements.txt
```

## Model

- Architecture: YOLOv8n
- Input size: 640 x 640
- Class count: 1
- Class name: lesion
- Recommended confidence threshold: 0.40
- Recommended NMS IoU threshold: 0.50

## Input requirement

The model input must be the FPGA-processed LC-OCT structural image. Keep the
same image domain in training, validation, and RK3588 deployment.

## Quick use

Install dependencies:

```bash
pip install -r requirements.txt
```

Run prediction with PyTorch weights:

```bash
python src/predict.py --weights models/yolov8n_lcoct_fpga_best.pt --source samples --output runs/predict
```

Run ONNX inference reference:

```bash
python src/onnx_infer.py --model models/yolov8n_lcoct_fpga_best.onnx --source samples --output runs/onnx_predict
```

Train from a dataset:

```bash
python src/train.py --data configs/data.yaml.example --weights yolov8n.pt --epochs 60 --batch 8
```

Export PT to ONNX:

```bash
python src/export_onnx.py --weights models/yolov8n_lcoct_fpga_best.pt
```

## Dataset format

The training dataset follows standard YOLO format:

```text
dataset/
  train/images/*.png
  train/labels/*.txt
  valid/images/*.png
  valid/labels/*.txt
  test/images/*.png
  test/labels/*.txt
```

Empty label files are used for negative samples.

## Results

- Train images: 455
- Valid images: 97
- Test images: 98
- Valid mAP50: 0.9947
- Test mAP50: 0.9772
- Test positive detected at conf 0.40: 75 / 75
- Test negative false positives at conf 0.40: 0 / 23

