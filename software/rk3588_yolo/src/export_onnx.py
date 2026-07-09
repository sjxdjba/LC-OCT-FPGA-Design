from __future__ import annotations

import argparse

from ultralytics import YOLO


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export YOLOv8 model to ONNX.")
    parser.add_argument("--weights", required=True, help="Path to .pt weights.")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--opset", type=int, default=12)
    parser.add_argument("--dynamic", action="store_true", help="Export dynamic input shape.")
    parser.add_argument("--simplify", action="store_true", help="Simplify ONNX graph.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = YOLO(args.weights)
    output = model.export(
        format="onnx",
        imgsz=args.imgsz,
        opset=args.opset,
        dynamic=args.dynamic,
        simplify=args.simplify,
    )
    print(output)


if __name__ == "__main__":
    main()

