from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np

from common import nms, preprocess, read_image, scale_boxes, xywh_to_xyxy


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ONNXRuntime inference reference for YOLOv8n.")
    parser.add_argument("--model", required=True, help="Path to ONNX model.")
    parser.add_argument("--source", required=True, help="Image file or image directory.")
    parser.add_argument("--output", default="runs/onnx_predict")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--conf", type=float, default=0.40)
    parser.add_argument("--iou", type=float, default=0.50)
    return parser.parse_args()


def iter_images(source: Path) -> list[Path]:
    if source.is_file():
        return [source]
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".pgm"}
    return sorted(path for path in source.rglob("*") if path.suffix.lower() in exts)


def decode_output(output: np.ndarray, conf_threshold: float) -> tuple[np.ndarray, np.ndarray]:
    pred = np.squeeze(output)
    if pred.ndim != 2:
        raise ValueError(f"Unexpected ONNX output shape: {output.shape}")
    if pred.shape[0] < pred.shape[1]:
        pred = pred.T

    boxes_xywh = pred[:, :4]
    class_scores = pred[:, 4:]
    if class_scores.shape[1] == 0:
        raise ValueError(f"No class scores in ONNX output shape: {output.shape}")

    scores = class_scores.max(axis=1)
    mask = scores >= conf_threshold
    boxes = xywh_to_xyxy(boxes_xywh[mask])
    return boxes, scores[mask]


def draw_detections(image: np.ndarray, boxes: np.ndarray, scores: np.ndarray) -> np.ndarray:
    output = image.copy()
    if len(boxes) == 0:
        cv2.putText(output, "no lesion", (20, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (40, 180, 80), 2)
        return output

    for box, score in zip(boxes, scores):
        x1, y1, x2, y2 = [int(round(v)) for v in box]
        cv2.rectangle(output, (x1, y1), (x2, y2), (0, 0, 255), 3)
        label = f"lesion {score:.3f}"
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        y_text = max(0, y1 - th - 10)
        cv2.rectangle(output, (x1, y_text), (x1 + tw + 10, y_text + th + 10), (0, 0, 255), -1)
        cv2.putText(output, label, (x1 + 5, y_text + th + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    return output


def main() -> None:
    args = parse_args()
    try:
        import onnxruntime as ort
    except ImportError as exc:
        raise SystemExit("onnxruntime is required. Install it with: pip install onnxruntime") from exc

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    session = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    image_paths = iter_images(Path(args.source))
    if not image_paths:
        raise FileNotFoundError(args.source)

    for image_path in image_paths:
        image = read_image(str(image_path))
        tensor, info = preprocess(image, size=args.imgsz)
        raw_output = session.run(None, {input_name: tensor})[0]
        boxes, scores = decode_output(raw_output, args.conf)
        boxes = scale_boxes(boxes, info)
        keep = nms(boxes, scores, args.iou)
        boxes = boxes[keep]
        scores = scores[keep]

        rendered = draw_detections(image, boxes, scores)
        cv2.imwrite(str(output_dir / image_path.name), rendered)
        print(f"{image_path.name}: {len(boxes)} boxes")


if __name__ == "__main__":
    main()
