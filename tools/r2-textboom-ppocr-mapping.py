#!/usr/bin/env python3
"""Pure PP-OCR -> TextBoom OCR result mapping helpers.

This module intentionally has no Android, APK, native-library, or filesystem
dependencies. It captures the stable semantic boundary we need before replacing
TextBoom's CamScanner-backed CsOcr route with a local PP-OCR adapter.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Iterable, Sequence


Number = int | float
Point = tuple[float, float]
ImageSize = tuple[int, int]


@dataclass(frozen=True)
class Rect:
    left: float
    top: float
    right: float
    bottom: float

    def normalized(self) -> "Rect":
        return Rect(
            left=min(self.left, self.right),
            top=min(self.top, self.bottom),
            right=max(self.left, self.right),
            bottom=max(self.top, self.bottom),
        )

    def clamped(self, image_size: ImageSize | None) -> "Rect":
        if image_size is None:
            return self
        width, height = image_size
        return Rect(
            left=max(0.0, min(float(width), self.left)),
            top=max(0.0, min(float(height), self.top)),
            right=max(0.0, min(float(width), self.right)),
            bottom=max(0.0, min(float(height), self.bottom)),
        ).normalized()


@dataclass(frozen=True)
class TextBoomOcrLine:
    text: str
    rect: Rect
    score: float | None = None

    def to_json(self) -> dict[str, Any]:
        return {"text": self.text, "rect": asdict(self.rect), "score": self.score}

    def to_ocrinfo_json(self) -> dict[str, Any]:
        return {"mText": self.text, "mRect": asdict(self.rect), "score": self.score}


def normalize_text(value: Any) -> str:
    """Match the legacy CsOcr cleanup: trim and remove carriage returns."""
    if value is None:
        return ""
    return str(value).replace("\r", "").strip()


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def coerce_score(value: Any) -> float | None:
    if is_number(value):
        return float(value)
    return None


def coerce_points(raw: Any) -> tuple[Point, ...]:
    """Accept PP-OCR quadrilaterals in nested or flat point form."""
    if raw is None:
        return ()
    if isinstance(raw, dict):
        for key in ("points", "box", "bbox", "poly", "dt_poly", "dt_polys"):
            if key in raw:
                return coerce_points(raw[key])
        return ()
    if not isinstance(raw, (list, tuple)):
        return ()
    if len(raw) == 8 and all(is_number(item) for item in raw):
        values = [float(item) for item in raw]
        return tuple((values[index], values[index + 1]) for index in range(0, 8, 2))
    points: list[Point] = []
    for item in raw:
        if isinstance(item, (list, tuple)) and len(item) >= 2 and is_number(item[0]) and is_number(item[1]):
            points.append((float(item[0]), float(item[1])))
    return tuple(points)


def rect_from_points(points: Sequence[Point], image_size: ImageSize | None = None) -> Rect:
    if not points:
        return Rect(0.0, 0.0, 0.0, 0.0)
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return Rect(min(xs), min(ys), max(xs), max(ys)).normalized().clamped(image_size)


def dict_record_to_line(record: dict[str, Any], image_size: ImageSize | None) -> TextBoomOcrLine:
    text = normalize_text(
        record.get("text")
        or record.get("rec_text")
        or record.get("transcription")
        or record.get("label")
    )
    score = coerce_score(record.get("score") or record.get("rec_score") or record.get("confidence"))
    points = coerce_points(record)
    return TextBoomOcrLine(text=text, rect=rect_from_points(points, image_size), score=score)


def pair_record_to_line(record: Sequence[Any], image_size: ImageSize | None) -> TextBoomOcrLine:
    points = coerce_points(record[0] if record else None)
    text = ""
    score: float | None = None
    if len(record) >= 2:
        payload = record[1]
        if isinstance(payload, (list, tuple)):
            if payload:
                text = normalize_text(payload[0])
            if len(payload) >= 2:
                score = coerce_score(payload[1])
        else:
            text = normalize_text(payload)
    return TextBoomOcrLine(text=text, rect=rect_from_points(points, image_size), score=score)


def looks_like_ppocr_pair(value: Any) -> bool:
    return (
        isinstance(value, (list, tuple))
        and len(value) >= 2
        and bool(coerce_points(value[0]))
        and not isinstance(value[1], dict)
    )


def iter_ppocr_records(result: Any) -> Iterable[Any]:
    """Yield logical OCR-line records from common PaddleOCR result shapes."""
    if isinstance(result, dict):
        texts = result.get("rec_texts")
        boxes = result.get("dt_polys") or result.get("rec_polys") or result.get("boxes")
        scores = result.get("rec_scores") or result.get("scores")
        if isinstance(texts, list) and isinstance(boxes, list):
            for index, text in enumerate(texts):
                yield {
                    "text": text,
                    "points": boxes[index] if index < len(boxes) else None,
                    "score": scores[index] if isinstance(scores, list) and index < len(scores) else None,
                }
            return
        yield result
        return
    if not isinstance(result, (list, tuple)):
        return
    if looks_like_ppocr_pair(result):
        yield result
        return
    for item in result:
        if looks_like_ppocr_pair(item) or isinstance(item, dict):
            yield item
        elif isinstance(item, (list, tuple)):
            yield from iter_ppocr_records(item)


def record_to_line(record: Any, image_size: ImageSize | None = None) -> TextBoomOcrLine:
    if isinstance(record, dict):
        return dict_record_to_line(record, image_size)
    if isinstance(record, (list, tuple)):
        return pair_record_to_line(record, image_size)
    return TextBoomOcrLine(text="", rect=Rect(0.0, 0.0, 0.0, 0.0), score=None)


def should_keep_line(line: TextBoomOcrLine, min_score: float | None) -> bool:
    if not line.text:
        return False
    if min_score is not None and line.score is not None and line.score < min_score:
        return False
    return True


def sort_reading_order(lines: Iterable[TextBoomOcrLine]) -> list[TextBoomOcrLine]:
    return sorted(lines, key=lambda line: (round(line.rect.top, 1), line.rect.left, line.rect.right))


def map_ppocr_to_textboom(
    result: Any,
    image_size: ImageSize | None = None,
    min_score: float | None = 0.0,
) -> list[TextBoomOcrLine]:
    lines = [record_to_line(record, image_size) for record in iter_ppocr_records(result)]
    return sort_reading_order(line for line in lines if should_keep_line(line, min_score))


def map_ppocr_to_textboom_json(
    result: Any,
    image_size: ImageSize | None = None,
    min_score: float | None = 0.0,
) -> list[dict[str, Any]]:
    return [line.to_json() for line in map_ppocr_to_textboom(result, image_size, min_score)]


def map_ppocr_to_ocrinfo_json(
    result: Any,
    image_size: ImageSize | None = None,
    min_score: float | None = 0.0,
) -> list[dict[str, Any]]:
    return [line.to_ocrinfo_json() for line in map_ppocr_to_textboom(result, image_size, min_score)]
