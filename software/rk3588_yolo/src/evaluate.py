from __future__ import annotations

import argparse
import json
from pathlib import Path

from ultralytics import YOLO


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate a YOLO model.")
    parser.add_argument("--weights", required=True, help="Path to .pt model.")
    parser.add_argument("--data", required=True, help="Path to data.yaml.")
    parser.add_argument("--split", default="test", choices=["train", "val", "test"], help="Dataset split.")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--conf", type=float, default=0.001)
    parser.add_argument("--iou", type=float, default=0.50)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--output", default="runs/eval_metrics.json")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = YOLO(args.weights)
    metrics = model.val(
        data=args.data,
        split=args.split,
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        device=args.device,
    )
    result = {str(k): float(v) for k, v in metrics.results_dict.items() if isinstance(v, (int, float))}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

