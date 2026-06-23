#!/usr/bin/env python3
"""Extract TextBoom result-page OCR tokens from a saved UIAutomator XML dump.

This is an offline evidence helper. It does not recover the raw CamScanner
RESPONSE_DATA payload; it records what TextBoom actually rendered to the user
after CsOcr/CamScanner returned.
"""

from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "hard-rom" / "inspect" / "textboom-ppocr-live-capture" / "textboom-ui-result-baseline.json"
BOUNDS_RE = re.compile(r"^\[(?P<left>-?\d+),(?P<top>-?\d+)\]\[(?P<right>-?\d+),(?P<bottom>-?\d+)\]$")
TOKEN_REPLACEMENTS = {
    "英文分号": ";",
    "英文逗号": ",",
    "英文句号": ".",
    "英文冒号": ":",
}
NO_SPACE_BEFORE = {")", ",", ".", ";", ":", "%"}
NO_SPACE_AFTER = {"(", "/", "."}


@dataclass(frozen=True)
class Bounds:
    left: int
    top: int
    right: int
    bottom: int


@dataclass(frozen=True)
class UiToken:
    text: str
    normalized_text: str
    bounds: Bounds


def relpath(path: Path | None) -> str | None:
    if path is None:
        return None
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(ROOT))
    except ValueError:
        return str(resolved)


def parse_bounds(value: str) -> Bounds | None:
    match = BOUNDS_RE.match(value or "")
    if match is None:
        return None
    return Bounds(
        left=int(match.group("left")),
        top=int(match.group("top")),
        right=int(match.group("right")),
        bottom=int(match.group("bottom")),
    )


def normalize_token(value: str) -> str:
    return TOKEN_REPLACEMENTS.get(value, value)


def is_result_token_node(attributes: dict[str, str]) -> bool:
    desc = attributes.get("content-desc", "").strip()
    if not desc:
        return False
    if attributes.get("resource-id", "").strip():
        return False
    return parse_bounds(attributes.get("bounds", "")) is not None


def join_tokens(tokens: list[UiToken]) -> str:
    pieces: list[str] = []
    for token in tokens:
        value = token.normalized_text
        if not value:
            continue
        if not pieces:
            pieces.append(value)
            continue
        previous = pieces[-1]
        if value in NO_SPACE_BEFORE or previous in NO_SPACE_AFTER:
            pieces[-1] = previous + value
        else:
            pieces.append(value)
    return " ".join(pieces)


def extract_title(root: ET.Element) -> str | None:
    for node in root.iter("node"):
        attributes = node.attrib
        if attributes.get("resource-id", "").endswith("/titlebar_center_text"):
            text = attributes.get("text", "").strip()
            return text or None
    return None


def extract_total_size(root: ET.Element) -> str | None:
    for node in root.iter("node"):
        attributes = node.attrib
        if attributes.get("resource-id", "").endswith("/total_size"):
            text = attributes.get("text", "").strip()
            return text or None
    return None


def extract_tokens(root: ET.Element) -> list[UiToken]:
    tokens: list[UiToken] = []
    for node in root.iter("node"):
        attributes = node.attrib
        if not is_result_token_node(attributes):
            continue
        bounds = parse_bounds(attributes.get("bounds", ""))
        if bounds is None:
            continue
        text = attributes.get("content-desc", "").strip()
        tokens.append(UiToken(text=text, normalized_text=normalize_token(text), bounds=bounds))
    return tokens


def build_baseline(
    xml_path: Path,
    sample_id: str,
    image_path: Path | None = None,
    screenshot_path: Path | None = None,
    image_size: list[int] | None = None,
) -> dict[str, Any]:
    root = ET.parse(xml_path).getroot()
    tokens = extract_tokens(root)
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "kind": "textboom-result-ui-baseline",
        "boundary": "offline UI-result extraction only; not raw CsOcr RESPONSE_DATA and not a ROM/APK/device operation",
        "sample": {
            "id": sample_id,
            "source_xml": relpath(xml_path),
            "source_screenshot": relpath(screenshot_path),
            "source_image": relpath(image_path),
            "image_size": image_size,
            "title": extract_title(root),
            "total_size_text": extract_total_size(root),
            "displayed_text": " ".join(token.text for token in tokens),
            "normalized_text": join_tokens(tokens),
            "tokens": [
                {
                    "text": token.text,
                    "normalized_text": token.normalized_text,
                    "bounds": asdict(token.bounds),
                }
                for token in tokens
            ],
        },
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_image_size(value: str | None) -> list[int] | None:
    if value is None:
        return None
    parts = [part.strip() for part in value.lower().split("x")]
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("image size must look like WIDTHxHEIGHT")
    return [int(parts[0]), int(parts[1])]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract TextBoom UI-result OCR baseline from a UIAutomator XML dump.")
    parser.add_argument("xml", type=Path, help="UIAutomator XML dump from a TextBoom result page.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output baseline JSON path.")
    parser.add_argument("--sample-id", default=None, help="Stable sample id. Defaults to XML filename stem.")
    parser.add_argument("--image", type=Path, default=None, help="Original imageboom.jpg path, if available.")
    parser.add_argument("--screenshot", type=Path, default=None, help="Result-page screenshot path, if available.")
    parser.add_argument("--image-size", default=None, help="Original OCR image size as WIDTHxHEIGHT.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    sample_id = args.sample_id or args.xml.stem
    payload = build_baseline(
        args.xml,
        sample_id,
        image_path=args.image,
        screenshot_path=args.screenshot,
        image_size=parse_image_size(args.image_size),
    )
    write_json(args.out, payload)
    print(f"baseline={args.out}")
    print(f"tokens={len(payload['sample']['tokens'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
