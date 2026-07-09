from __future__ import annotations

import argparse
from pathlib import Path

from ultralytics import YOLO


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train YOLOv8n on FPGA-processed LC-OCT images.")
    parser.add_argument("--data", required=True, help="Path to YOLO data.yaml.")
    parser.add_argument("--weights", default="yolov8n.pt", help="Initial weights.")
    parser.add_argument("--imgsz", type=int, default=640, help="Input image size.")
    parser.add_argument("--epochs", type=int, default=60, help="Training epochs.")
    parser.add_argument("--batch", type=int, default=8, help="Batch size.")
    parser.add_argument("--device", default="cpu", help="Training device, e.g. cpu, 0.")
    parser.add_argument("--project", default="runs", help="Output project directory.")
    parser.add_argument("--name", default="train_lcoct_yolov8n", help="Run name.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    data = Path(args.data)
    if not data.exists():
        raise FileNotFoundError(data)

    model = YOLO(args.weights)
    model.train(
        data=str(data),
        imgsz=args.imgsz,
        epochs=args.epochs,
        batch=args.batch,
        device=args.device,
        project=args.project,
        name=args.name,
        exist_ok=True,
    )


if __name__ == "__main__":
    main()

