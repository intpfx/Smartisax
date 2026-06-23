#!/usr/bin/env python3
"""Create a labeled screenshot corpus template for TextBoom PP-OCR benchmarking.

This helper is offline-only. It reads local screenshot files and writes a JSON
corpus skeleton consumed by tools/r2-textboom-ppocr-benchmark.py. It does not
touch a device, run OCR, patch APKs, build images, or flash ROMs.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "hard-rom" / "inspect" / "textboom-ppocr-corpus" / "corpus-template.json"
SUPPORTED_SUFFIXES = (".png", ".jpg", ".jpeg")


@dataclass(frozen=True)
class ImageInfo:
    path: str
    size: tuple[int, int] | None
    warning: str | None = None


def relpath(path: Path) -> str:
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(ROOT))
    except ValueError:
        return str(resolved)


def sample_id_for_path(path: Path) -> str:
    return path.stem.replace(" ", "-")


def read_png_size(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as fh:
        header = fh.read(24)
    if len(header) < 24 or not header.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    if header[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", header[16:24])
    return int(width), int(height)


def read_jpeg_size(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as fh:
        if fh.read(2) != b"\xff\xd8":
            return None
        while True:
            marker_prefix = fh.read(1)
            if not marker_prefix:
                return None
            if marker_prefix != b"\xff":
                continue
            marker = fh.read(1)
            while marker == b"\xff":
                marker = fh.read(1)
            if not marker:
                return None
            marker_value = marker[0]
            if marker_value in (0xD8, 0xD9):
                continue
            length_raw = fh.read(2)
            if len(length_raw) != 2:
                return None
            segment_length = struct.unpack(">H", length_raw)[0]
            if segment_length < 2:
                return None
            if 0xC0 <= marker_value <= 0xC3 or 0xC5 <= marker_value <= 0xC7 or 0xC9 <= marker_value <= 0xCB or 0xCD <= marker_value <= 0xCF:
                payload = fh.read(5)
                if len(payload) != 5:
                    return None
                height, width = struct.unpack(">HH", payload[1:5])
                return int(width), int(height)
            fh.seek(segment_length - 2, 1)


def read_image_info(path: Path) -> ImageInfo:
    suffix = path.suffix.lower()
    try:
        if suffix == ".png":
            return ImageInfo(path=relpath(path), size=read_png_size(path))
        if suffix in (".jpg", ".jpeg"):
            return ImageInfo(path=relpath(path), size=read_jpeg_size(path))
        return ImageInfo(path=relpath(path), size=None, warning=f"unsupported image suffix: {suffix}")
    except OSError as exc:
        return ImageInfo(path=relpath(path), size=None, warning=str(exc))


def iter_image_paths(inputs: Iterable[Path]) -> list[Path]:
    paths: list[Path] = []
    for item in inputs:
        if item.is_dir():
            for suffix in SUPPORTED_SUFFIXES:
                paths.extend(sorted(item.rglob(f"*{suffix}")))
        elif item.is_file():
            paths.append(item)
    return sorted(dict.fromkeys(path.resolve() for path in paths), key=lambda path: str(path))


def existing_expected_by_id(existing: Any) -> dict[str, Any]:
    if not isinstance(existing, dict):
        return {}
    samples = existing.get("samples")
    if not isinstance(samples, list):
        return {}
    result: dict[str, Any] = {}
    for sample in samples:
        if not isinstance(sample, dict):
            continue
        sample_id = str(sample.get("id") or "")
        if sample_id:
            result[sample_id] = sample.get("expected", [])
    return result


def load_existing(path: Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {}
    return existing_expected_by_id(json.loads(path.read_text(encoding="utf-8")))


def build_corpus(
    images: list[Path],
    label: str,
    source: str,
    preserve_expected: dict[str, Any] | None = None,
) -> dict[str, Any]:
    preserved = preserve_expected or {}
    samples = []
    for image in images:
        info = read_image_info(image)
        sample_id = sample_id_for_path(image)
        sample: dict[str, Any] = {
            "id": sample_id,
            "image": info.path,
            "image_size": list(info.size) if info.size is not None else None,
            "expected": preserved.get(sample_id, []),
        }
        if info.warning:
            sample["warning"] = info.warning
        samples.append(sample)
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "label": label,
        "source": source,
        "boundary": "offline corpus template only; does not run OCR, patch TextBoom, build ROM images, touch a device, or authorize CsOcr/CamScanner removal",
        "samples": samples,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a TextBoom PP-OCR labeled screenshot corpus template.")
    parser.add_argument("inputs", nargs="+", type=Path, help="Screenshot files or directories.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output corpus JSON path.")
    parser.add_argument("--label", default="textboom-ppocr-r2-corpus", help="Corpus label.")
    parser.add_argument("--source", default="r2-live-screenshot", help="Human-readable corpus source.")
    parser.add_argument("--preserve-existing", action="store_true", help="Keep existing expected labels for matching sample ids from --out.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    images = iter_image_paths(args.inputs)
    preserved = load_existing(args.out) if args.preserve_existing else {}
    payload = build_corpus(images, args.label, args.source, preserved)
    write_json(args.out, payload)
    print(f"corpus={args.out}")
    print(f"samples={len(payload['samples'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
