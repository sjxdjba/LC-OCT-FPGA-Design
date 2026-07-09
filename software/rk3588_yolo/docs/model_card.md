# Model Card

## Purpose

This YOLOv8n model detects lesion regions in FPGA-processed LC-OCT structural
images for an embedded imaging demonstration system.

## Input

- Image type: FPGA-processed LC-OCT structural image
- Recommended size: 640 x 640 after YOLO letterbox
- Color layout: RGB for the model input pipeline
- Pixel normalization: 0.0 to 1.0

## Output

Each detection contains:

- class id: 0
- class name: lesion
- confidence score
- bounding box coordinates

If no detection is above the confidence threshold, the application should
report `no lesion`.

## Recommended thresholds

- Confidence: 0.40
- NMS IoU: 0.50

## Validation summary

- Valid mAP50: 0.9947
- Test mAP50: 0.9772
- Test positives detected: 75 / 75
- Test negatives false positives: 0 / 23

## Limitation

This model is for the embedded LC-OCT imaging demo and is not a clinical
diagnosis model.

