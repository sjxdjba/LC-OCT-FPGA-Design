from __future__ import annotations

import argparse

from ultralytics import YOLO


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run YOLO prediction.")
    parser.add_argument("--weights", required=True, help="Path to .pt model.")
    parser.add_argument("--source", required=True, help="Image, directory, or video source.")
    parser.add_argument("--output", default="runs/predict", help="Output directory.")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--conf", type=float, default=0.40)
    parser.add_argument("--iou", type=float, default=0.50)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--save-txt", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = YOLO(args.weights)
    model.predict(
        source=args.source,
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        device=args.device,
        project=args.output,
        name="images",
        exist_ok=True,
        save=True,
        save_txt=args.save_txt,
        line_width=3,
    )


if __name__ == "__main__":
    main()

