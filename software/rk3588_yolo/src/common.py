from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class LetterboxInfo:
    scale: float
    pad_x: float
    pad_y: float
    original_shape: tuple[int, int]


def read_image(path: str) -> np.ndarray:
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if image is None:
        raise FileNotFoundError(path)
    if image.ndim == 2:
        image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    elif image.shape[2] == 4:
        image = cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)
    return image


def letterbox(image: np.ndarray, size: int = 640, pad_value: int = 114) -> tuple[np.ndarray, LetterboxInfo]:
    height, width = image.shape[:2]
    scale = min(size / width, size / height)
    new_w = int(round(width * scale))
    new_h = int(round(height * scale))
    resized = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

    canvas = np.full((size, size, 3), pad_value, dtype=np.uint8)
    pad_x = (size - new_w) / 2
    pad_y = (size - new_h) / 2
    x0 = int(round(pad_x - 0.1))
    y0 = int(round(pad_y - 0.1))
    canvas[y0 : y0 + new_h, x0 : x0 + new_w] = resized
    return canvas, LetterboxInfo(scale=scale, pad_x=x0, pad_y=y0, original_shape=(height, width))


def preprocess(image: np.ndarray, size: int = 640) -> tuple[np.ndarray, LetterboxInfo]:
    boxed, info = letterbox(image, size=size)
    rgb = cv2.cvtColor(boxed, cv2.COLOR_BGR2RGB)
    tensor = rgb.astype(np.float32) / 255.0
    tensor = np.transpose(tensor, (2, 0, 1))[None, ...]
    return tensor, info


def xywh_to_xyxy(boxes: np.ndarray) -> np.ndarray:
    converted = np.empty_like(boxes)
    converted[:, 0] = boxes[:, 0] - boxes[:, 2] / 2
    converted[:, 1] = boxes[:, 1] - boxes[:, 3] / 2
    converted[:, 2] = boxes[:, 0] + boxes[:, 2] / 2
    converted[:, 3] = boxes[:, 1] + boxes[:, 3] / 2
    return converted


def scale_boxes(boxes: np.ndarray, info: LetterboxInfo) -> np.ndarray:
    boxes = boxes.copy()
    boxes[:, [0, 2]] = (boxes[:, [0, 2]] - info.pad_x) / info.scale
    boxes[:, [1, 3]] = (boxes[:, [1, 3]] - info.pad_y) / info.scale
    height, width = info.original_shape
    boxes[:, [0, 2]] = boxes[:, [0, 2]].clip(0, width - 1)
    boxes[:, [1, 3]] = boxes[:, [1, 3]].clip(0, height - 1)
    return boxes


def nms(boxes: np.ndarray, scores: np.ndarray, iou_threshold: float) -> list[int]:
    if len(boxes) == 0:
        return []

    x1, y1, x2, y2 = boxes.T
    areas = (x2 - x1).clip(min=0) * (y2 - y1).clip(min=0)
    order = scores.argsort()[::-1]
    keep: list[int] = []

    while order.size > 0:
        i = int(order[0])
        keep.append(i)
        if order.size == 1:
            break

        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])

        inter_w = (xx2 - xx1).clip(min=0)
        inter_h = (yy2 - yy1).clip(min=0)
        inter = inter_w * inter_h
        union = areas[i] + areas[order[1:]] - inter + 1e-6
        iou = inter / union
        order = order[1:][iou <= iou_threshold]

    return keep

