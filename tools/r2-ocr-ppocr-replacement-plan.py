#!/usr/bin/env python3
"""Generate the OCR full-removal and PP-OCR replacement plan.

This helper is read-only with respect to ROM inputs. It consumes local decoded
APK/JADX evidence and writes a markdown/TSV/JSON bundle for the next build
gates. It does not build images, touch a device, flash, reboot, erase
partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Sequence


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
JADX = KB / "jadx"

SIDEBAR_V038 = ROOT / "hard-rom" / "work" / "v0.38-sidebar-font-ocr-disabled" / "verify" / "sidebar-decoded"
TEXTBOOM_LIVE_DECODED = ROOT / "hard-rom" / "work" / "textboom-live-decode" / "decoded"
TEXTBOOM_JADX = JADX / "system__system__app__TextBoom__TextBoom.apk"

OUT_MD = ROOT / "docs" / "research" / "ocr-ppocr-replacement-plan.md"
OUT_TSV = KB / "manifest" / "ocr-ppocr-replacement-plan.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "ocr-ppocr-replacement-plan"
OUT_JSON = OUT_DIR / "ocr-ppocr-replacement-plan.json"


@dataclass(frozen=True)
class SourceFact:
    name: str
    url: str
    fact: str
    use: str


@dataclass(frozen=True)
class DeletionGate:
    track: str
    package: str
    component: str
    current_role: str
    action: str
    preserve: str
    proof: str
    scan_root: str
    file_globs: tuple[str, ...]
    legacy_tokens: tuple[str, ...]


@dataclass(frozen=True)
class ReplacementGate:
    track: str
    component: str
    shape: str
    action: str
    proof: str
    benchmark_first: str
    benchmark_second: str


PPOCR_SOURCE_FACTS: tuple[SourceFact, ...] = (
    SourceFact(
        "PaddleOCR 3.7.0",
        "https://github.com/PaddlePaddle/PaddleOCR",
        "Official README records a 2026-06-11 PaddleOCR 3.7.0 release and PP-OCRv6 tiny/small/medium tiers.",
        "Use PP-OCRv6 small as the main TextBoom replacement candidate; keep tiny only as a speed/power fallback.",
    ),
    SourceFact(
        "PP-OCRv6 multilingual model",
        "https://github.com/PaddlePaddle/PaddleOCR",
        "Official README describes PP-OCRv6 as one model supporting 50 languages.",
        "Prefer one local OCR engine for mixed Chinese/English TextBoom crops instead of separate legacy branches.",
    ),
    SourceFact(
        "PaddleOCR PP-OCRv6 Android demo",
        "https://github.com/PaddlePaddle/PaddleOCR/tree/main/deploy/ppocr-android",
        "The current official PP-OCRv6 Android demo uses ONNX Runtime, separates ppocr-sdk from the demo app, and provides preprocessing, DB postprocess, crop, CTC decode, timing, and AAR integration.",
        "Use deploy/ppocr-android/ppocr-sdk as the main implementation reference instead of hand-rolling the full pipeline or relying on the old PaddleLite android_demo.",
    ),
)


DELETION_GATES: tuple[DeletionGate, ...] = (
    DeletionGate(
        "sidebar-font-ocr",
        "com.smartisanos.sidebar",
        "BoomFontActivity manifest contract",
        "v0.38 disables the activity and removes ACTION_BOOM_FONT resolution, but the component declaration remains.",
        "v0.39 should remove the BoomFontActivity declaration and Intsig ocr_key metadata from Sidebar's manifest.",
        "Sidebar package name, shared UID, providers, SidebarService, one-step windows, and topbar blank slot.",
        "Decoded v0.39 Sidebar manifest contains no BoomFontActivity, BOOM_FONT, or Intsig ocr_key.",
        "hard-rom/work/v0.38-sidebar-font-ocr-disabled/verify/sidebar-decoded",
        ("AndroidManifest.xml",),
        ("BoomFontActivity", "ocr_key"),
    ),
    DeletionGate(
        "sidebar-font-ocr",
        "com.smartisanos.sidebar",
        "font OCR backend classes",
        "BoomFontActivity, OCRhelper, FontHelper, FileHelper, FontResultActivity, and crop/font views remain in DEX.",
        "Delete the unreachable font-recognition class cluster after removing all adapter/provider references.",
        "Core Sidebar top area, side area, app binding, word lookup, three-in-one app, providers, and service boot.",
        "No smali class under com/smartisanos/sidebar/open/font remains unless a tiny no-op compatibility stub is justified by a reference scan.",
        "hard-rom/work/v0.38-sidebar-font-ocr-disabled/verify/sidebar-decoded/smali/com/smartisanos/sidebar/open/font",
        ("*.smali",),
        ("BoomFontActivity", "OCRhelper", "FontHelper", "qiuziti.com", "CSOpenAPI"),
    ),
    DeletionGate(
        "sidebar-font-ocr",
        "com.smartisanos.sidebar",
        "Sidebar Intsig SDK copy",
        "The separate Sidebar copy of com.intsig.csopen still contains ACTION_OCR, CSOpenAPI, and CamScanner package references.",
        "Delete com/intsig/csopen from Sidebar once no remaining Sidebar class references it.",
        "TextBoom's separate OCR work must not be inferred from Sidebar's SDK deletion.",
        "No Sidebar smali file references Lcom/intsig/csopen and the com/intsig/csopen directory is absent.",
        "hard-rom/work/v0.38-sidebar-font-ocr-disabled/verify/sidebar-decoded/smali/com/intsig/csopen",
        ("*.smali",),
        ("CSOpenAPI", "ACTION_OCR", "com.intsig.camscanner", "CSOcrResult"),
    ),
    DeletionGate(
        "sidebar-font-ocr",
        "com.smartisanos.sidebar",
        "tool-button type 1 reachability",
        "ToolButtonManager can still update type=1 and ToolButtonAdapter still maps type=1 to tool_button_item_identify_font.",
        "Remove type=1 from manager updates and adapter layout mapping, and filter stale DB type=1 rows during read.",
        "Other tool-button types 0, 2, and 3 must keep stable order, drag, and animation behavior.",
        "Stale tool_list DB rows with type=1 cannot inflate IdentifyFontView and cannot crash the top-area adapter.",
        "hard-rom/work/v0.38-sidebar-font-ocr-disabled/verify/sidebar-decoded/smali/com/smartisanos/sidebar",
        ("*.smali",),
        ("tool_button_item_identify_font", "isFontLookupOn", "update(IZ)V"),
    ),
    DeletionGate(
        "textboom-camscanner",
        "com.smartisanos.textboom",
        "CsOcr implementation",
        "BoomOcrActivity and BoomAccessOcrActivity instantiate CsOcr, which delegates to Intsig/CamScanner.",
        "Replace the instantiation with a local IOcrApi-compatible PP-OCR adapter after benchmark acceptance, then delete CsOcr.",
        "TextBoom actions, FileProvider authority, OcrFloatViewService, OcrInfo coordinate semantics, and Big Bang text segmentation.",
        "TextBoom DEX contains no CsOcr class or new-instance CsOcr opcode; replacement class implements IOcrApi.",
        "hard-rom/work/textboom-live-decode/decoded",
        ("*.smali",),
        ("CsOcr", "Lcom/smartisanos/textboom/ocr/CsOcr;", "startActivityForOCR", "CSOpenAPI"),
    ),
    DeletionGate(
        "textboom-camscanner",
        "com.smartisanos.textboom",
        "TextBoom Intsig SDK copy",
        "TextBoom's com.intsig.csopen copy owns CamScanner package probing, ACTION_OCR, and RESPONSE_DATA parsing.",
        "Delete com/intsig/csopen from TextBoom after the PP-OCR adapter no longer depends on CSOcrResult conversion.",
        "Any unrelated import from com.intsig.csopen.ReturnCode must be reviewed and removed or replaced first.",
        "No TextBoom smali/java source references Lcom/intsig/csopen and no com/intsig/csopen directory remains in decoded APK.",
        "hard-rom/work/textboom-live-decode/decoded/smali_classes2/com/intsig/csopen",
        ("*.smali",),
        ("ACTION_OCR", "RESPONSE_DATA", "com.intsig.camscanner", "CSOcrResult"),
    ),
    DeletionGate(
        "textboom-camscanner",
        "com.smartisanos.textboom",
        "manifest Intsig metadata",
        "TextBoom manifest still carries ocr_key metadata for the CamScanner OpenAPI route.",
        "Remove ocr_key only after CsOcr and Intsig SDK references are gone.",
        "TextBoom BOOM_IMAGE, BOOM_ACCESSBILITY, BOOM_OPTION, FileProvider, and call provider contracts.",
        "TextBoom manifest contains no ocr_key while all non-Intsig TextBoom entry points remain declared.",
        "hard-rom/work/textboom-live-decode/decoded",
        ("AndroidManifest.xml",),
        ("ocr_key",),
    ),
    DeletionGate(
        "textboom-remote-ocr",
        "com.smartisanos.textboom",
        "BoomAccessOcrActivity online OcrThread",
        "Accessibility OCR has a separate online OcrThread branch before falling back to mOcrApi.",
        "Decide whether local-only PP-OCR should also replace the online branch; if yes, delete OcrThread and network URL parsing.",
        "Accessibility label flow and dialog behavior should still return useful text or a clean failure.",
        "No online OCR branch remains, or the branch is explicitly documented as non-CamScanner and kept for a separate reason.",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/ocr",
        ("BoomAccessOcrActivity.java",),
        ("OcrThread", "getDataFromOnLine", "sendOcrMessage"),
    ),
)


REPLACEMENT_GATES: tuple[ReplacementGate, ...] = (
    ReplacementGate(
        "textboom-ppocr",
        "LocalPpOcrApi",
        "Kotlin/Java adapter around official deploy/ppocr-android/ppocr-sdk; implements the existing IOcrApi boundary.",
        "Keep the impure Android side thin: bitmap intake, model lifecycle, callback dispatch. Reuse official preprocess/DB/CTC/crop code and keep TextBoom result mapping pure.",
        "Unit tests cover OCR line/box normalization and OcrInfo conversion before smali/APK integration.",
        "PP-OCRv6 small on R2 screenshots",
        "PP-OCRv6 tiny only as speed/power fallback",
    ),
    ReplacementGate(
        "textboom-ppocr",
        "Benchmark harness",
        "Temporary local APK/service or standalone harness that can run without modifying TextBoom first.",
        "Measure CsOcr baseline and PP-OCR candidates on the same screenshot corpus.",
        "Record latency, memory, model footprint, Chinese/English accuracy, coordinate quality, and crash behavior.",
        "current CsOcr route as baseline",
        "official ppocr-android + PP-OCRv6 small + ONNX Runtime Android",
    ),
    ReplacementGate(
        "textboom-ppocr",
        "ROM integration",
        "Patch TextBoom only after benchmark PASS; rebuild APK and image through the existing v1/JAR/signing-carrier workflow.",
        "Remove CamScanner code in the same candidate that switches to PP-OCR so the app cannot silently fall back to Intsig.",
        "Live verification proves BOOM_TEXT, image OCR crop, WebView/Smartisax, Sidebar, and boot/keyguard all remain healthy.",
        "v0.39 Sidebar deletion if independent",
        "v0.40 TextBoom PP-OCR integration if model benchmark passes",
    ),
)


def parse_ranges(spec: str) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            ranges.append((int(start), int(end)))
        else:
            value = int(part)
            ranges.append((value, value))
    return ranges


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def path_matches(path: Path, globs: Sequence[str]) -> bool:
    name = path.name
    return any(path.match(pattern) or name == pattern or name.endswith(pattern.removeprefix("*")) for pattern in globs)


def iter_scan_files(root: Path, globs: Sequence[str]) -> Iterable[Path]:
    if root.is_file():
        if path_matches(root, globs):
            yield root
        return
    if not root.exists():
        return
    for path in root.rglob("*"):
        if path.is_file() and path_matches(path, globs):
            yield path


def token_hits(text: str, tokens: Sequence[str]) -> tuple[str, ...]:
    return tuple(token for token in tokens if token in text)


def summarize_hits(root: Path, globs: Sequence[str], tokens: Sequence[str], *, max_files: int = 8) -> dict[str, object]:
    files = list(iter_scan_files(root, globs))
    matched_files: list[dict[str, object]] = []
    token_set: set[str] = set()
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        hits = token_hits(text, tokens)
        if hits:
            token_set.update(hits)
            if len(matched_files) < max_files:
                matched_files.append({"file": rel(path), "tokens": list(hits)})
    missing_tokens = sorted(set(tokens) - token_set)
    return {
        "root": rel(root),
        "exists": root.exists(),
        "scanned_files": len(files),
        "matched_file_count": len(matched_files),
        "matched_files": matched_files,
        "tokens_present": sorted(token_set),
        "tokens_missing": missing_tokens,
    }


def current_state_from_hits(hit_summary: dict[str, object]) -> str:
    if not hit_summary["exists"]:
        return "evidence_missing"
    if hit_summary["tokens_present"]:
        return "legacy_present_in_current_baseline"
    return "legacy_absent_in_current_baseline"


def deletion_gate_status(hit_summary: dict[str, object]) -> str:
    if not hit_summary["exists"]:
        return "WARN_EVIDENCE_MISSING"
    if hit_summary["tokens_present"]:
        return "TARGET_PENDING_DELETE"
    return "TARGET_ALREADY_ABSENT"


def overall_result(rows: Sequence[dict[str, object]]) -> str:
    if any(row["status"] == "WARN_EVIDENCE_MISSING" for row in rows):
        return "OCR_PPOCR_REPLACEMENT_PLAN_OFFLINE_WARN"
    return "OCR_PPOCR_REPLACEMENT_PLAN_OFFLINE_PASS"


def build_payload() -> dict[str, object]:
    rows: list[dict[str, object]] = []
    for gate in DELETION_GATES:
        root = ROOT / gate.scan_root
        hits = summarize_hits(root, gate.file_globs, gate.legacy_tokens)
        row = asdict(gate)
        row["current_state"] = current_state_from_hits(hits)
        row["status"] = deletion_gate_status(hits)
        row["evidence"] = hits
        rows.append(row)

    payload = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "result": overall_result(rows),
        "sources": [asdict(source) for source in PPOCR_SOURCE_FACTS],
        "deletion_gates": rows,
        "replacement_gates": [asdict(gate) for gate in REPLACEMENT_GATES],
        "next_versions": {
            "v0.39": "Sidebar font OCR code-level deletion candidate, independent from TextBoom PP-OCR.",
            "v0.40": "TextBoom PP-OCR candidate only after model/runtime benchmark PASS.",
        },
        "implementation_style": [
            "Prefer pure mapping functions for OCR result normalization and OcrInfo conversion.",
            "Keep Android Activity, Bitmap, native runtime, and callback dispatch in thin impure adapters.",
            "Write unit tests before replacing CsOcr with LocalPpOcrApi.",
        ],
    }
    return payload


def write_tsv(payload: dict[str, object]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "track",
        "package",
        "component",
        "status",
        "current_state",
        "scan_root",
        "current_role",
        "action",
        "preserve",
        "proof",
        "tokens_present",
    ]
    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in payload["deletion_gates"]:  # type: ignore[index]
            evidence = row["evidence"]  # type: ignore[index]
            writer.writerow(
                {
                    "track": row["track"],
                    "package": row["package"],
                    "component": row["component"],
                    "status": row["status"],
                    "current_state": row["current_state"],
                    "scan_root": row["scan_root"],
                    "current_role": row["current_role"],
                    "action": row["action"],
                    "preserve": row["preserve"],
                    "proof": row["proof"],
                    "tokens_present": ",".join(evidence["tokens_present"]),  # type: ignore[index]
                }
            )


def md_table(rows: list[dict[str, object]]) -> str:
    out = [
        "| Track | Component | Status | Current state | Action | Proof |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        out.append(
            "| {track} | {component} | {status} | {current_state} | {action} | {proof} |".format(
                track=row["track"],
                component=row["component"],
                status=row["status"],
                current_state=row["current_state"],
                action=str(row["action"]).replace("|", "\\|"),
                proof=str(row["proof"]).replace("|", "\\|"),
            )
        )
    return "\n".join(out)


def source_lines(sources: list[dict[str, object]]) -> str:
    lines = []
    for source in sources:
        lines.append(f"- [{source['name']}]({source['url']}): {source['fact']} Use: {source['use']}")
    return "\n".join(lines)


def replacement_table(rows: list[dict[str, object]]) -> str:
    out = [
        "| Track | Component | Shape | Action | Proof |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        out.append(
            "| {track} | {component} | {shape} | {action} | {proof} |".format(
                track=row["track"],
                component=row["component"],
                shape=str(row["shape"]).replace("|", "\\|"),
                action=str(row["action"]).replace("|", "\\|"),
                proof=str(row["proof"]).replace("|", "\\|"),
            )
        )
    return "\n".join(out)


def evidence_summary(rows: list[dict[str, object]]) -> str:
    chunks: list[str] = []
    for row in rows:
        evidence = row["evidence"]
        files = evidence["matched_files"]  # type: ignore[index]
        file_lines = []
        for item in files:  # type: ignore[union-attr]
            file_lines.append(f"  - `{item['file']}` tokens={','.join(item['tokens'])}")
        if not file_lines:
            file_lines.append("  - no matching token files in current baseline")
        chunks.append(
            "\n".join(
                [
                    f"### {row['track']} / {row['component']}",
                    f"- root: `{evidence['root']}`",
                    f"- status: `{row['status']}`",
                    f"- tokens present: `{', '.join(evidence['tokens_present']) or 'none'}`",
                    *file_lines,
                ]
            )
        )
    return "\n\n".join(chunks)


def write_md(payload: dict[str, object]) -> None:
    rows = payload["deletion_gates"]  # type: ignore[assignment]
    sources = payload["sources"]  # type: ignore[assignment]
    replacements = payload["replacement_gates"]  # type: ignore[assignment]
    style = "\n".join(f"- {item}" for item in payload["implementation_style"])  # type: ignore[index]
    implemented_boundaries = """## Implemented Local Mapping Boundary

`tools/r2-textboom-ppocr-mapping.py` defines the pure PP-OCR-to-TextBoom
result mapping boundary for the future `LocalPpOcrApi` adapter. It accepts
classic PaddleOCR line pairs and dictionary-style result arrays, normalizes text
with the same carriage-return removal used by legacy `CsOcr`, converts
quadrilateral boxes into TextBoom-style axis-aligned rectangles, optionally
clamps them to bitmap bounds, filters empty/low-confidence lines, and sorts
rows in reading order.

Tests live in `tests/test_r2_textboom_ppocr_mapping.py`. This does not
integrate PP-OCR into TextBoom yet and does not authorize deletion of TextBoom's
`CsOcr`/Intsig code by itself; it provides the tested pure-function layer that
the Android/native adapter should call.

## Implemented Offline Benchmark Boundary

`tools/r2-textboom-ppocr-benchmark.py` defines the saved-result benchmark
boundary for the future TextBoom OCR replacement gate. It consumes a labeled
screenshot corpus JSON plus saved predictions from the current CsOcr baseline
or a future PP-OCR result, reuses the pure mapping layer, and scores line
recall, character error rate, rectangle IoU, latency, and peak PSS when those
fields are available.

`tools/r2-textboom-ppocr-corpus-template.py` covers the input-template side of
the same gate. `tools/r2-textboom-live-ocr-capture.sh` covers non-mutating live
capture of screenshots, UI dumps, TextBoom/CamScanner logcat, and package/focus
state. These helpers do not flash, reboot, erase, uninstall, clear app data, or
mutate ROM images.

## Implemented Runtime Proofs

`apps/TextBoomPpOcrBench/` proved a real local Paddle Lite PP-OCR v2 mobile slim
runtime on R2. It remains useful as native pipeline evidence, but it is not the
selected final model route because the user explicitly chose latest-model
benchmarking.

`apps/TextBoomOnnxSmokeBench/` proved PP-OCRv6 tiny/small conversion to ONNX and
live R2 runtime loading through native ONNX Runtime Android plus WebView/WASM.
That smoke uses zero tensors and tiny assets, so it is compatibility proof only:
tiny is now a speed/power fallback, and WebView/ORT Web remains a Smartisax
Shell experiment.

## Official SDK Intake Boundary

`tools/r2-fetch-official-ppocr-android.sh` records the current official
`deploy/ppocr-android` source under
`third_party/_downloads/paddleocr-ppocr-android/` and writes
`third_party/_downloads/paddleocr-ppocr-android/ppocr-android-manifest.txt`.
The first TextBoom replacement benchmark should reuse official `ppocr-sdk`
preprocess, DB postprocess, crop, CTC decode, model-directory, and config
handling with PP-OCRv6 small before any TextBoom APK mutation.
"""

    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(
        f"""# OCR PP-OCR Replacement Plan

Generated by `tools/r2-ocr-ppocr-replacement-plan.py` on {payload['generated_at']}.

## Verdict

`v0.38-sidebar-font-ocr-disabled` was a stable behavioral stop, not a complete
code deletion. The v0.38 evidence below remains useful because it shows exactly
which Sidebar font-OCR and TextBoom CamScanner tokens existed before deletion.
`v0.39-sidebar-font-ocr-deleted` has since removed the Sidebar/One Step font OCR
branch and passed live verification; TextBoom's image OCR still routes through
CamScanner-backed `CsOcr`.

The current clean split is:

- Sidebar font OCR: completed in `v0.39-sidebar-font-ocr-deleted`.
- TextBoom PP-OCR: continue only through a no-ROM benchmark harness until
  official `ppocr-sdk` + PP-OCRv6 small proves local model latency, memory,
  accuracy, and coordinate quality against the CsOcr baseline.

## Current External Facts

{source_lines(sources)}

## Deletion Gates

{md_table(rows)}

## Replacement Gates

{replacement_table(replacements)}

{implemented_boundaries}

## Pure-Function Refactor Boundary

{style}

## Evidence Snapshot

{evidence_summary(rows)}

## Build Authorization Boundary

This report does not authorize a flash. It also does not authorize TextBoom APK
repacking yet. Sidebar v0.39 is already live-proven; the next allowed OCR
engineering step is a no-ROM official-SDK benchmark harness that runs PP-OCRv6
small on the same R2 screenshots as the CsOcr baseline. TextBoom APK/ROM work
remains blocked until the replacement adapter passes quality, coordinate,
latency, memory, and crash-behavior gates.
""",
        encoding="utf-8",
    )


def write_json(payload: dict[str, object]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    payload = build_payload()
    write_tsv(payload)
    write_json(payload)
    write_md(payload)
    print(payload["result"])
    print(f"markdown={OUT_MD.relative_to(ROOT)}")
    print(f"tsv={OUT_TSV.relative_to(ROOT)}")
    print(f"json={OUT_JSON.relative_to(ROOT)}")
    return 0 if str(payload["result"]).endswith("_PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
