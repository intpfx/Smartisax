#!/usr/bin/env python3
"""Offline TextBoom PP-OCR benchmark harness.

This tool does not run an OCR model and does not touch a device. It evaluates
saved OCR predictions against a labeled screenshot corpus, using the pure
PP-OCR -> TextBoom mapping boundary from r2-textboom-ppocr-mapping.py.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = ROOT / "hard-rom" / "inspect" / "textboom-ppocr-benchmark"
DEFAULT_DOC = ROOT / "docs" / "research" / "textboom-ppocr-benchmark.md"
DEFAULT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "textboom-ppocr-benchmark.tsv"
MAPPING_SCRIPT = ROOT / "tools" / "r2-textboom-ppocr-mapping.py"


def load_mapping_module():
    spec = importlib.util.spec_from_file_location("r2_textboom_ppocr_mapping", MAPPING_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load mapping module: {MAPPING_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


MAPPING = load_mapping_module()


@dataclass(frozen=True)
class BenchmarkThresholds:
    min_line_recall: float = 0.85
    max_corpus_cer: float = 0.08
    min_mean_iou: float = 0.50
    line_match_max_cer: float = 0.34
    max_p95_latency_ms: float | None = None
    max_peak_pss_kb: int | None = None


@dataclass(frozen=True)
class ExpectedLine:
    text: str
    rect: Any


@dataclass(frozen=True)
class LineMatch:
    expected_index: int
    predicted_index: int
    expected_text: str
    predicted_text: str
    char_error_rate: float
    iou: float


def normalize_compare_text(value: Any) -> str:
    return re.sub(r"\s+", "", "" if value is None else str(value).replace("\r", ""))


def levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    previous = list(range(len(b) + 1))
    for index_a, char_a in enumerate(a, start=1):
        current = [index_a]
        for index_b, char_b in enumerate(b, start=1):
            current.append(
                min(
                    previous[index_b] + 1,
                    current[index_b - 1] + 1,
                    previous[index_b - 1] + (0 if char_a == char_b else 1),
                )
            )
        previous = current
    return previous[-1]


def char_error_rate(expected: Any, predicted: Any) -> float:
    expected_text = normalize_compare_text(expected)
    predicted_text = normalize_compare_text(predicted)
    if not expected_text and not predicted_text:
        return 0.0
    if not expected_text:
        return 1.0
    return levenshtein(expected_text, predicted_text) / len(expected_text)


def coerce_rect(value: Any) -> Any:
    if isinstance(value, MAPPING.Rect):
        return value
    if isinstance(value, dict):
        return MAPPING.Rect(
            float(value.get("left", 0.0)),
            float(value.get("top", 0.0)),
            float(value.get("right", 0.0)),
            float(value.get("bottom", 0.0)),
        ).normalized()
    if isinstance(value, (list, tuple)) and len(value) == 4:
        return MAPPING.Rect(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
    return MAPPING.Rect(0.0, 0.0, 0.0, 0.0)


def rect_area(rect: Any) -> float:
    rect = coerce_rect(rect)
    return max(0.0, rect.right - rect.left) * max(0.0, rect.bottom - rect.top)


def rect_iou(left: Any, right: Any) -> float:
    left_rect = coerce_rect(left)
    right_rect = coerce_rect(right)
    inter_left = max(left_rect.left, right_rect.left)
    inter_top = max(left_rect.top, right_rect.top)
    inter_right = min(left_rect.right, right_rect.right)
    inter_bottom = min(left_rect.bottom, right_rect.bottom)
    intersection = rect_area(MAPPING.Rect(inter_left, inter_top, inter_right, inter_bottom))
    union = rect_area(left_rect) + rect_area(right_rect) - intersection
    if union <= 0:
        return 0.0
    return intersection / union


def percentile(values: Iterable[float], percent: float) -> float | None:
    ordered = sorted(float(value) for value in values if value is not None and math.isfinite(float(value)))
    if not ordered:
        return None
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * percent
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[int(rank)]
    weight = rank - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def image_size_for_sample(sample: dict[str, Any]) -> tuple[int, int] | None:
    raw = sample.get("image_size") or sample.get("size")
    if isinstance(raw, (list, tuple)) and len(raw) == 2:
        return int(raw[0]), int(raw[1])
    width = sample.get("width")
    height = sample.get("height")
    if isinstance(width, int) and isinstance(height, int):
        return width, height
    return None


def expected_lines_for_sample(sample: dict[str, Any]) -> list[ExpectedLine]:
    raw_lines = sample.get("expected") or sample.get("lines") or sample.get("labels") or []
    lines: list[ExpectedLine] = []
    if not isinstance(raw_lines, list):
        return lines
    for line in raw_lines:
        if isinstance(line, dict):
            lines.append(ExpectedLine(text=str(line.get("text", "")), rect=coerce_rect(line.get("rect") or line.get("box"))))
    return lines


def corpus_samples(corpus: Any) -> list[dict[str, Any]]:
    if isinstance(corpus, dict):
        samples = corpus.get("samples") or corpus.get("images")
        if isinstance(samples, list):
            return [sample for sample in samples if isinstance(sample, dict)]
        if "id" in corpus:
            return [corpus]
    if isinstance(corpus, list):
        return [sample for sample in corpus if isinstance(sample, dict)]
    return []


def prediction_samples(predictions: Any) -> list[dict[str, Any]]:
    if isinstance(predictions, dict):
        samples = predictions.get("samples") or predictions.get("images") or predictions.get("results")
        if isinstance(samples, list):
            return [sample for sample in samples if isinstance(sample, dict)]
        return []
    if isinstance(predictions, list):
        return [sample for sample in predictions if isinstance(sample, dict)]
    return []


def prediction_for_sample(predictions: Any, sample_id: str, sample_index: int) -> dict[str, Any]:
    samples = prediction_samples(predictions)
    for sample in samples:
        if str(sample.get("id") or sample.get("image_id") or "") == sample_id:
            return sample
    if samples and sample_index < len(samples):
        return samples[sample_index]
    if isinstance(predictions, dict):
        direct = predictions.get(sample_id)
        if isinstance(direct, dict):
            return direct
        if direct is not None:
            return {"ppocr": direct}
    return {}


def ppocr_payload(sample_prediction: dict[str, Any]) -> Any:
    for key in ("ppocr", "result", "ocr", "prediction", "predictions", "lines"):
        if key in sample_prediction:
            return sample_prediction[key]
    return sample_prediction


def numeric_metric(sample_prediction: dict[str, Any], *keys: str) -> float | None:
    for key in keys:
        value = sample_prediction.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return float(value)
    metrics = sample_prediction.get("metrics")
    if isinstance(metrics, dict):
        for key in keys:
            value = metrics.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                return float(value)
    return None


def match_lines(expected: list[ExpectedLine], predicted: list[Any], thresholds: BenchmarkThresholds) -> list[LineMatch]:
    candidates: list[tuple[float, float, int, int, float, float]] = []
    for expected_index, expected_line in enumerate(expected):
        for predicted_index, predicted_line in enumerate(predicted):
            cer = char_error_rate(expected_line.text, predicted_line.text)
            if cer > thresholds.line_match_max_cer:
                continue
            iou = rect_iou(expected_line.rect, predicted_line.rect)
            cost = cer + (1.0 - iou) * 0.25
            candidates.append((cost, cer, expected_index, predicted_index, iou, predicted_line.rect.left))
    matches: list[LineMatch] = []
    used_expected: set[int] = set()
    used_predicted: set[int] = set()
    for _, cer, expected_index, predicted_index, iou, _ in sorted(candidates):
        if expected_index in used_expected or predicted_index in used_predicted:
            continue
        used_expected.add(expected_index)
        used_predicted.add(predicted_index)
        matches.append(
            LineMatch(
                expected_index=expected_index,
                predicted_index=predicted_index,
                expected_text=expected[expected_index].text,
                predicted_text=predicted[predicted_index].text,
                char_error_rate=cer,
                iou=iou,
            )
        )
    return sorted(matches, key=lambda match: match.expected_index)


def evaluate_sample(
    sample: dict[str, Any],
    sample_prediction: dict[str, Any],
    thresholds: BenchmarkThresholds,
) -> dict[str, Any]:
    sample_id = str(sample.get("id") or sample.get("image_id") or sample.get("name") or "sample")
    image_size = image_size_for_sample(sample)
    expected = expected_lines_for_sample(sample)
    predicted = MAPPING.map_ppocr_to_textboom(ppocr_payload(sample_prediction), image_size=image_size, min_score=None)
    matches = match_lines(expected, predicted, thresholds)
    expected_text = "".join(line.text for line in expected)
    predicted_text = "".join(line.text for line in predicted)
    line_recall = len(matches) / len(expected) if expected else (1.0 if not predicted else 0.0)
    mean_iou = sum(match.iou for match in matches) / len(matches) if matches else (1.0 if not expected and not predicted else 0.0)
    cer = char_error_rate(expected_text, predicted_text)
    passed = (
        line_recall >= thresholds.min_line_recall
        and cer <= thresholds.max_corpus_cer
        and mean_iou >= thresholds.min_mean_iou
    )
    latency_ms = numeric_metric(sample_prediction, "latency_ms", "warm_latency_ms", "end_to_end_latency_ms")
    peak_pss_kb = numeric_metric(sample_prediction, "peak_pss_kb", "pss_kb", "memory_pss_kb")
    return {
        "id": sample_id,
        "expected_count": len(expected),
        "predicted_count": len(predicted),
        "matched_count": len(matches),
        "missed_count": max(0, len(expected) - len(matches)),
        "extra_count": max(0, len(predicted) - len(matches)),
        "line_recall": line_recall,
        "char_error_rate": cer,
        "mean_iou": mean_iou,
        "latency_ms": latency_ms,
        "peak_pss_kb": peak_pss_kb,
        "result": "PASS" if passed else "FAIL",
        "matches": [asdict(match) for match in matches],
        "predicted": [line.to_json() for line in predicted],
    }


def summarize_samples(samples: list[dict[str, Any]], thresholds: BenchmarkThresholds) -> dict[str, Any]:
    sample_count = len(samples)
    failed = [sample for sample in samples if sample["result"] != "PASS"]
    expected_count = sum(int(sample["expected_count"]) for sample in samples)
    matched_count = sum(int(sample["matched_count"]) for sample in samples)
    line_recall = matched_count / expected_count if expected_count else 1.0
    cer_values = [float(sample["char_error_rate"]) for sample in samples if sample["expected_count"]]
    iou_values = [float(sample["mean_iou"]) for sample in samples if sample["matched_count"]]
    latency_values = [sample["latency_ms"] for sample in samples if sample.get("latency_ms") is not None]
    pss_values = [sample["peak_pss_kb"] for sample in samples if sample.get("peak_pss_kb") is not None]
    corpus_cer = sum(cer_values) / len(cer_values) if cer_values else 0.0
    mean_iou = sum(iou_values) / len(iou_values) if iou_values else (1.0 if not expected_count else 0.0)
    p95_latency = percentile(latency_values, 0.95)
    peak_pss = max(pss_values) if pss_values else None
    latency_pass = thresholds.max_p95_latency_ms is None or (p95_latency is not None and p95_latency <= thresholds.max_p95_latency_ms)
    memory_pass = thresholds.max_peak_pss_kb is None or (peak_pss is not None and peak_pss <= thresholds.max_peak_pss_kb)
    quality_pass = (
        not failed
        and line_recall >= thresholds.min_line_recall
        and corpus_cer <= thresholds.max_corpus_cer
        and mean_iou >= thresholds.min_mean_iou
    )
    return {
        "sample_count": sample_count,
        "failed_sample_count": len(failed),
        "expected_line_count": expected_count,
        "matched_line_count": matched_count,
        "line_recall": line_recall,
        "mean_sample_char_error_rate": corpus_cer,
        "mean_matched_iou": mean_iou,
        "p50_latency_ms": percentile(latency_values, 0.50),
        "p95_latency_ms": p95_latency,
        "peak_pss_kb": peak_pss,
        "quality_pass": quality_pass,
        "latency_pass": latency_pass,
        "memory_pass": memory_pass,
        "result": "PASS" if quality_pass and latency_pass and memory_pass else "FAIL",
    }


def evaluate_corpus(corpus: Any, predictions: Any, thresholds: BenchmarkThresholds, label: str) -> dict[str, Any]:
    samples = corpus_samples(corpus)
    evaluated = [
        evaluate_sample(sample, prediction_for_sample(predictions, str(sample.get("id") or sample.get("image_id") or sample.get("name") or f"sample-{index}"), index), thresholds)
        for index, sample in enumerate(samples)
    ]
    summary = summarize_samples(evaluated, thresholds)
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "label": label,
        "engine": predictions.get("engine") if isinstance(predictions, dict) else None,
        "model": predictions.get("model") if isinstance(predictions, dict) else None,
        "thresholds": asdict(thresholds),
        "summary": summary,
        "samples": evaluated,
        "result": "TEXTBOOM_PPOCR_BENCHMARK_" + summary["result"],
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_tsv(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "id",
        "result",
        "expected_count",
        "predicted_count",
        "matched_count",
        "missed_count",
        "extra_count",
        "line_recall",
        "char_error_rate",
        "mean_iou",
        "latency_ms",
        "peak_pss_kb",
    ]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for sample in payload["samples"]:
            writer.writerow({column: sample.get(column, "") for column in columns})


def format_number(value: Any) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.4g}"
    return str(value)


def write_markdown(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    summary = payload["summary"]
    sample_rows = [
        "| Sample | Result | Recall | CER | IoU | Latency ms | PSS KB |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for sample in payload["samples"]:
        sample_rows.append(
            "| {id} | {result} | {recall} | {cer} | {iou} | {latency} | {pss} |".format(
                id=sample["id"],
                result=sample["result"],
                recall=format_number(sample["line_recall"]),
                cer=format_number(sample["char_error_rate"]),
                iou=format_number(sample["mean_iou"]),
                latency=format_number(sample["latency_ms"]),
                pss=format_number(sample["peak_pss_kb"]),
            )
        )
    body = f"""# TextBoom PP-OCR Benchmark

Generated by `tools/r2-textboom-ppocr-benchmark.py` on {payload['generated_at']}.

## Verdict

`{payload['result']}`

Label: `{payload['label']}`
Engine: `{payload.get('engine') or 'unknown'}`
Model: `{payload.get('model') or 'unknown'}`

## Summary

- samples: {summary['sample_count']}
- failed samples: {summary['failed_sample_count']}
- line recall: {format_number(summary['line_recall'])}
- mean sample CER: {format_number(summary['mean_sample_char_error_rate'])}
- mean matched IoU: {format_number(summary['mean_matched_iou'])}
- p50 latency ms: {format_number(summary['p50_latency_ms'])}
- p95 latency ms: {format_number(summary['p95_latency_ms'])}
- peak PSS KB: {format_number(summary['peak_pss_kb'])}

## Samples

{chr(10).join(sample_rows)}

## Boundary

This report scores saved OCR predictions only. It does not run PP-OCR, patch
TextBoom, build a ROM image, touch a live device, or authorize removal of
TextBoom's CsOcr/CamScanner code.
"""
    path.write_text(body, encoding="utf-8")


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be non-negative")
    return parsed


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate saved PP-OCR predictions against a TextBoom screenshot corpus.")
    parser.add_argument("--corpus", required=True, type=Path, help="Labeled corpus JSON.")
    parser.add_argument("--predictions", required=True, type=Path, help="Saved OCR predictions JSON.")
    parser.add_argument("--label", default="textboom-ppocr-benchmark", help="Report label.")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help="Directory for JSON/markdown report outputs.")
    parser.add_argument("--docs-md", type=Path, default=None, help="Optional markdown docs path to refresh.")
    parser.add_argument("--manifest-tsv", type=Path, default=None, help="Optional TSV manifest path to refresh.")
    parser.add_argument("--min-line-recall", type=positive_float, default=0.85)
    parser.add_argument("--max-corpus-cer", type=positive_float, default=0.08)
    parser.add_argument("--min-mean-iou", type=positive_float, default=0.50)
    parser.add_argument("--line-match-max-cer", type=positive_float, default=0.34)
    parser.add_argument("--max-p95-latency-ms", type=positive_float, default=None)
    parser.add_argument("--max-peak-pss-kb", type=int, default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    thresholds = BenchmarkThresholds(
        min_line_recall=args.min_line_recall,
        max_corpus_cer=args.max_corpus_cer,
        min_mean_iou=args.min_mean_iou,
        line_match_max_cer=args.line_match_max_cer,
        max_p95_latency_ms=args.max_p95_latency_ms,
        max_peak_pss_kb=args.max_peak_pss_kb,
    )
    corpus = load_json(args.corpus)
    predictions = load_json(args.predictions)
    payload = evaluate_corpus(corpus, predictions, thresholds, args.label)
    out_json = args.out_dir / f"{args.label}.json"
    out_md = args.out_dir / f"{args.label}.md"
    out_tsv = args.out_dir / f"{args.label}.tsv"
    write_json(out_json, payload)
    write_markdown(out_md, payload)
    write_tsv(out_tsv, payload)
    if args.docs_md is not None:
        write_markdown(args.docs_md, payload)
    if args.manifest_tsv is not None:
        write_tsv(args.manifest_tsv, payload)
    print(f"result={payload['result']}")
    print(f"json={out_json}")
    print(f"markdown={out_md}")
    print(f"tsv={out_tsv}")
    return 0 if payload["summary"]["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
