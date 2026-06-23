#!/usr/bin/env python3
"""Compare TextBoom legacy OCR evidence with official PP-OCR benchmark output.

This report is intentionally conservative: a TextBoom UI dump is only a
user-visible legacy baseline, and a failed standalone CamScanner probe remains
a failed raw baseline rather than a quality score.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = ROOT / "hard-rom" / "inspect" / "textboom-ocr-compare"
DEFAULT_DOC = ROOT / "docs" / "research" / "textboom-ocr-baseline-comparison.md"
DEFAULT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "textboom-ocr-baseline-comparison.tsv"
DEFAULT_PPOCR = ROOT / "hard-rom" / "inspect" / "textboom-ppocr-official-bench-live" / "20260621-ppocr-official-small-opencv490-live-smoke" / "last-result.json"
DEFAULT_CSOCR = ROOT / "hard-rom" / "inspect" / "textboom-csocr-baseline-live" / "20260621-csocr-imageboom-smoke" / "csocr-baseline-results.json"
DEFAULT_UI_BASELINES = [
    ROOT / "hard-rom" / "inspect" / "textboom-ppocr-live-capture" / "20260620-230945-unlocked-boom-image" / "textboom-ui-result-baseline.json",
]


@dataclass(frozen=True)
class TextMetrics:
    expected_chars: int
    predicted_chars: int
    edit_distance: int
    char_error_rate: float | None
    containment: str


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def relpath(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def normalize_text(value: Any) -> str:
    text = "" if value is None else str(value)
    return re.sub(r"\s+", "", text.replace("\r", ""))


def levenshtein(left: str, right: str) -> int:
    if left == right:
        return 0
    if not left:
        return len(right)
    if not right:
        return len(left)
    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            current.append(
                min(
                    previous[right_index] + 1,
                    current[right_index - 1] + 1,
                    previous[right_index - 1] + (0 if left_char == right_char else 1),
                )
            )
        previous = current
    return previous[-1]


def text_metrics(expected: str, predicted: str) -> TextMetrics:
    expected_norm = normalize_text(expected)
    predicted_norm = normalize_text(predicted)
    distance = levenshtein(expected_norm, predicted_norm)
    cer = None if not expected_norm else distance / len(expected_norm)
    if expected_norm and expected_norm in predicted_norm:
        containment = "expected_in_predicted"
    elif predicted_norm and predicted_norm in expected_norm:
        containment = "predicted_in_expected"
    elif expected_norm == predicted_norm:
        containment = "equal"
    else:
        containment = "none"
    return TextMetrics(
        expected_chars=len(expected_norm),
        predicted_chars=len(predicted_norm),
        edit_distance=distance,
        char_error_rate=cer,
        containment=containment,
    )


def prefix_char_error_rate(expected: str, predicted: str) -> float | None:
    expected_norm = normalize_text(expected)
    predicted_norm = normalize_text(predicted)
    if not expected_norm:
        return None
    return levenshtein(expected_norm, predicted_norm[: len(expected_norm)]) / len(expected_norm)


def first_numeric(*values: Any) -> Any:
    for value in values:
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return value
    return None


def line_text_from_ppocr(sample: dict[str, Any]) -> str:
    lines = sample.get("ppocr")
    if not isinstance(lines, list):
        return ""
    return "\n".join(str(line.get("text", "")) for line in lines if isinstance(line, dict))


def line_count_from_ppocr(sample: dict[str, Any]) -> int:
    metrics = sample.get("native_metrics")
    if isinstance(metrics, dict) and isinstance(metrics.get("line_count"), int):
        return int(metrics["line_count"])
    lines = sample.get("ppocr")
    return len(lines) if isinstance(lines, list) else 0


def ppocr_sample_row(sample: dict[str, Any], source: Path) -> dict[str, Any]:
    metrics = sample.get("native_metrics") if isinstance(sample.get("native_metrics"), dict) else {}
    return {
        "id": str(sample.get("id") or "sample"),
        "source": relpath(source),
        "status": sample.get("status"),
        "image_size": sample.get("image_size"),
        "image_sha256": sample.get("image_sha256"),
        "line_count": line_count_from_ppocr(sample),
        "latency_ms": sample.get("latency_ms"),
        "det_ms": metrics.get("det_ms"),
        "rec_ms": metrics.get("rec_ms"),
        "peak_pss_kb": sample.get("peak_pss_kb"),
        "text": line_text_from_ppocr(sample),
    }


def extract_ppocr(paths: list[Path]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for path in paths:
        payload = load_json(path)
        samples = payload.get("samples", []) if isinstance(payload, dict) else []
        for sample in samples:
            if not isinstance(sample, dict):
                continue
            row = ppocr_sample_row(sample, path)
            rows[row["id"]] = row
    return rows


def csocr_text(sample: dict[str, Any]) -> str:
    csocr = sample.get("csocr")
    if isinstance(csocr, dict):
        full_text = csocr.get("full_text")
        if isinstance(full_text, str):
            return full_text
        lines = csocr.get("lines")
        if isinstance(lines, list):
            return "\n".join(str(line.get("text", "")) for line in lines if isinstance(line, dict))
    return ""


def csocr_sample_row(sample: dict[str, Any], source: Path) -> dict[str, Any]:
    csocr = sample.get("csocr") if isinstance(sample.get("csocr"), dict) else {}
    return {
        "id": str(sample.get("id") or "sample"),
        "source": relpath(source),
        "status": sample.get("status"),
        "activity_result_code": sample.get("activity_result_code"),
        "response_code": sample.get("response_code"),
        "raw_response_size": sample.get("raw_response_size"),
        "line_count": csocr.get("line_count"),
        "latency_ms": sample.get("latency_ms"),
        "peak_pss_kb": sample.get("peak_pss_kb"),
        "camscanner_total_pss_kb": sample.get("camscanner_meminfo_total_pss_kb"),
        "text": csocr_text(sample),
    }


def extract_csocr(paths: list[Path]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for path in paths:
        payload = load_json(path)
        if isinstance(payload, dict) and isinstance(payload.get("samples"), list):
            samples = payload["samples"]
        else:
            samples = []
        for sample in samples:
            if not isinstance(sample, dict):
                continue
            row = csocr_sample_row(sample, path)
            rows[row["id"]] = row
    return rows


def ui_sample_row(payload: dict[str, Any], source: Path) -> dict[str, Any]:
    sample = payload.get("sample") if isinstance(payload.get("sample"), dict) else {}
    tokens = sample.get("tokens") if isinstance(sample.get("tokens"), list) else []
    source_image = sample.get("source_image")
    sample_id = str(sample.get("id") or "sample")
    if isinstance(source_image, str) and source_image:
        sample_id = Path(source_image).stem or sample_id
    return {
        "id": sample_id,
        "source": relpath(source),
        "title": sample.get("title"),
        "total_size_text": sample.get("total_size_text"),
        "token_count": len(tokens),
        "image_size": sample.get("image_size"),
        "text": sample.get("normalized_text") or sample.get("displayed_text") or "",
    }


def extract_ui(paths: list[Path]) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for path in paths:
        payload = load_json(path)
        row = ui_sample_row(payload, path)
        if row["id"] not in rows:
            rows[row["id"]] = row
            continue
        existing = rows[row["id"]]
        if row.get("text"):
            if existing.get("text"):
                existing["text"] = str(existing["text"]) + "\n" + str(row["text"])
            else:
                existing["text"] = row["text"]
        existing["token_count"] = int(existing.get("token_count") or 0) + int(row.get("token_count") or 0)
        existing["source"] = ", ".join(value for value in (str(existing.get("source") or ""), str(row.get("source") or "")) if value)
        if not existing.get("total_size_text") and row.get("total_size_text"):
            existing["total_size_text"] = row["total_size_text"]
    return rows


def best_row(rows: dict[str, dict[str, Any]], sample_id: str) -> dict[str, Any] | None:
    if sample_id in rows:
        return rows[sample_id]
    return None


def format_float(value: Any) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.4g}"
    return str(value)


def build_rows(ppocr: dict[str, dict[str, Any]], csocr: dict[str, dict[str, Any]], ui: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    sample_ids = sorted(set(ppocr) | set(csocr) | set(ui))
    rows: list[dict[str, Any]] = []
    for sample_id in sample_ids:
        ppocr_row = best_row(ppocr, sample_id)
        csocr_row = best_row(csocr, sample_id)
        ui_row = best_row(ui, sample_id)
        ppocr_text = ppocr_row.get("text", "") if ppocr_row else ""
        csocr_text_value = csocr_row.get("text", "") if csocr_row else ""
        ui_text = ui_row.get("text", "") if ui_row else ""
        ui_vs_ppocr = text_metrics(ui_text, ppocr_text) if ui_text and ppocr_text else None
        ui_vs_ppocr_prefix_cer = prefix_char_error_rate(ui_text, ppocr_text) if ui_text and ppocr_text else None
        csocr_vs_ppocr = text_metrics(csocr_text_value, ppocr_text) if csocr_text_value and ppocr_text else None
        rows.append(
            {
                "id": sample_id,
                "ppocr_status": ppocr_row.get("status") if ppocr_row else None,
                "ppocr_line_count": ppocr_row.get("line_count") if ppocr_row else None,
                "ppocr_latency_ms": ppocr_row.get("latency_ms") if ppocr_row else None,
                "ppocr_det_ms": ppocr_row.get("det_ms") if ppocr_row else None,
                "ppocr_rec_ms": ppocr_row.get("rec_ms") if ppocr_row else None,
                "ppocr_peak_pss_kb": ppocr_row.get("peak_pss_kb") if ppocr_row else None,
                "csocr_status": csocr_row.get("status") if csocr_row else None,
                "csocr_response_code": csocr_row.get("response_code") if csocr_row else None,
                "csocr_raw_response_size": csocr_row.get("raw_response_size") if csocr_row else None,
                "csocr_line_count": csocr_row.get("line_count") if csocr_row else None,
                "csocr_latency_ms": csocr_row.get("latency_ms") if csocr_row else None,
                "camscanner_total_pss_kb": csocr_row.get("camscanner_total_pss_kb") if csocr_row else None,
                "ui_token_count": ui_row.get("token_count") if ui_row else None,
                "ui_total_size_text": ui_row.get("total_size_text") if ui_row else None,
                "ui_vs_ppocr_cer": ui_vs_ppocr.char_error_rate if ui_vs_ppocr else None,
                "ui_vs_ppocr_prefix_cer": ui_vs_ppocr_prefix_cer,
                "ui_vs_ppocr_containment": ui_vs_ppocr.containment if ui_vs_ppocr else None,
                "csocr_vs_ppocr_cer": csocr_vs_ppocr.char_error_rate if csocr_vs_ppocr else None,
                "csocr_vs_ppocr_containment": csocr_vs_ppocr.containment if csocr_vs_ppocr else None,
                "ppocr_text_preview": ppocr_text[:240],
                "csocr_text_preview": csocr_text_value[:240],
                "ui_text_preview": ui_text[:240],
            }
        )
    return rows


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    ppocr_ok = [row for row in rows if row.get("ppocr_status") == "OK"]
    csocr_ok = [row for row in rows if row.get("csocr_status") == "OK"]
    ppocr_latencies = [row.get("ppocr_latency_ms") for row in rows if isinstance(row.get("ppocr_latency_ms"), (int, float))]
    ppocr_pss = [row.get("ppocr_peak_pss_kb") for row in rows if isinstance(row.get("ppocr_peak_pss_kb"), (int, float))]
    camscanner_pss = [row.get("camscanner_total_pss_kb") for row in rows if isinstance(row.get("camscanner_total_pss_kb"), (int, float))]
    return {
        "sample_count": len(rows),
        "ppocr_ok_count": len(ppocr_ok),
        "csocr_raw_ok_count": len(csocr_ok),
        "csocr_raw_blocked_count": len([row for row in rows if row.get("csocr_status") and row.get("csocr_status") != "OK"]),
        "ppocr_max_latency_ms": max(ppocr_latencies) if ppocr_latencies else None,
        "ppocr_max_peak_pss_kb": max(ppocr_pss) if ppocr_pss else None,
        "camscanner_max_total_pss_kb": max(camscanner_pss) if camscanner_pss else None,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_tsv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "id",
        "ppocr_status",
        "ppocr_line_count",
        "ppocr_latency_ms",
        "ppocr_det_ms",
        "ppocr_rec_ms",
        "ppocr_peak_pss_kb",
        "csocr_status",
        "csocr_response_code",
        "csocr_raw_response_size",
        "csocr_line_count",
        "csocr_latency_ms",
        "camscanner_total_pss_kb",
        "ui_token_count",
        "ui_total_size_text",
        "ui_vs_ppocr_cer",
        "ui_vs_ppocr_prefix_cer",
        "ui_vs_ppocr_containment",
    ]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in columns})


def write_markdown(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = [
        "| Sample | PP-OCR | PP-OCR ms | PSS KB | CsOcr raw | CsOcr ms | CamScanner PSS KB | UI visible comparison |",
        "| --- | --- | ---: | ---: | --- | ---: | ---: | --- |",
    ]
    for row in payload["rows"]:
        ui_note = "n/a"
        if row.get("ui_token_count") is not None:
            ui_note = (
                f"tokens={row.get('ui_token_count')}, "
                f"full CER={format_float(row.get('ui_vs_ppocr_cer'))}, "
                f"prefix CER={format_float(row.get('ui_vs_ppocr_prefix_cer'))}, "
                f"{row.get('ui_vs_ppocr_containment')}"
            )
        rows.append(
            "| {id} | {ppocr_status} lines={ppocr_lines} | {ppocr_ms} | {ppocr_pss} | {csocr_status} rc={rc} raw={raw} | {csocr_ms} | {cam_pss} | {ui_note} |".format(
                id=row["id"],
                ppocr_status=row.get("ppocr_status") or "n/a",
                ppocr_lines=row.get("ppocr_line_count") if row.get("ppocr_line_count") is not None else "n/a",
                ppocr_ms=format_float(row.get("ppocr_latency_ms")),
                ppocr_pss=format_float(row.get("ppocr_peak_pss_kb")),
                csocr_status=row.get("csocr_status") or "n/a",
                rc=row.get("csocr_response_code") if row.get("csocr_response_code") is not None else "n/a",
                raw=row.get("csocr_raw_response_size") if row.get("csocr_raw_response_size") is not None else "n/a",
                csocr_ms=format_float(row.get("csocr_latency_ms")),
                cam_pss=format_float(row.get("camscanner_total_pss_kb")),
                ui_note=ui_note,
            )
        )
    summary = payload["summary"]
    body = f"""# TextBoom OCR Baseline Comparison

Generated by `tools/r2-textboom-ocr-compare-report.py` on {payload['generated_at']}.

## Verdict

`{payload['result']}`

The standalone CamScanner OpenAPI probe did not recover raw `RESPONSE_DATA`
when called from the benchmark package. Treat that as a real compatibility
finding, not as a CsOcr quality score. The user-visible TextBoom UI dump remains
useful only as a partial legacy viewport baseline.

## Summary

- samples: {summary['sample_count']}
- PP-OCR OK samples: {summary['ppocr_ok_count']}
- raw CsOcr OK samples: {summary['csocr_raw_ok_count']}
- raw CsOcr blocked samples: {summary['csocr_raw_blocked_count']}
- PP-OCR max latency ms: {format_float(summary['ppocr_max_latency_ms'])}
- PP-OCR max peak PSS KB: {format_float(summary['ppocr_max_peak_pss_kb'])}
- CamScanner max total PSS KB: {format_float(summary['camscanner_max_total_pss_kb'])}

## Comparison

{chr(10).join(rows)}

## Adapter Implication

The first TextBoom adapter should be a local `IOcrApi` replacement that feeds
official PP-OCR line results into a tested pure `OcrInfo` mapper. Raw CsOcr
character-level coordinates remain unavailable from the standalone probe, so
exact legacy parity needs a TextBoom-internal instrumentation candidate if we
decide that raw CamScanner output is still required.

## Boundary

This report aggregates saved benchmark and UI evidence only. It does not run
OCR, patch TextBoom, build a ROM image, flash, reboot, erase, uninstall, or
clear data.
"""
    path.write_text(body, encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare saved TextBoom CsOcr/UI baselines with PP-OCR results.")
    parser.add_argument("--ppocr", action="append", type=Path, default=None, help="Official PP-OCR result JSON or aggregate JSON. Repeatable.")
    parser.add_argument("--csocr", action="append", type=Path, default=None, help="CsOcr/CamScanner result JSON or aggregate JSON. Repeatable.")
    parser.add_argument("--ui-baseline", action="append", type=Path, default=None, help="TextBoom UI-result baseline JSON. Repeatable.")
    parser.add_argument("--label", default="textboom-ocr-baseline-comparison")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--docs-md", type=Path, default=None)
    parser.add_argument("--manifest-tsv", type=Path, default=None)
    return parser.parse_args(argv)


def expand_inputs(paths: list[Path] | None, defaults: list[Path]) -> list[Path]:
    values = paths if paths else defaults
    missing = [path for path in values if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing input(s): " + ", ".join(str(path) for path in missing))
    return values


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    ppocr_paths = expand_inputs(args.ppocr, [DEFAULT_PPOCR])
    csocr_paths = expand_inputs(args.csocr, [DEFAULT_CSOCR])
    ui_paths = expand_inputs(args.ui_baseline, DEFAULT_UI_BASELINES)
    rows = build_rows(extract_ppocr(ppocr_paths), extract_csocr(csocr_paths), extract_ui(ui_paths))
    summary = summarize(rows)
    result = "TEXTBOOM_OCR_BASELINE_COMPARE_PARTIAL" if summary["csocr_raw_ok_count"] == 0 else "TEXTBOOM_OCR_BASELINE_COMPARE_READY"
    payload = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "kind": "textboom-ocr-baseline-comparison",
        "label": args.label,
        "inputs": {
            "ppocr": [relpath(path) for path in ppocr_paths],
            "csocr": [relpath(path) for path in csocr_paths],
            "ui_baseline": [relpath(path) for path in ui_paths],
        },
        "summary": summary,
        "rows": rows,
        "result": result,
    }
    out_json = args.out_dir / f"{args.label}.json"
    out_md = args.out_dir / f"{args.label}.md"
    out_tsv = args.out_dir / f"{args.label}.tsv"
    write_json(out_json, payload)
    write_markdown(out_md, payload)
    write_tsv(out_tsv, rows)
    if args.docs_md is not None:
        write_markdown(args.docs_md, payload)
    if args.manifest_tsv is not None:
        write_tsv(args.manifest_tsv, rows)
    print(f"result={result}")
    print(f"json={out_json}")
    print(f"markdown={out_md}")
    print(f"tsv={out_tsv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
