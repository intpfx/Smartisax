#!/usr/bin/env python3
"""Generate a focused TextBoom/Sidebar OCR backend map.

This helper is read-only with respect to ROM inputs. It consumes the local
JADX output and APK inventory, then writes a markdown report plus TSV/JSON
evidence artifacts. It does not build images, touch a device, flash, reboot,
erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
JADX = KB / "jadx"
OUT_MD = ROOT / "docs" / "research" / "textboom-ocr-backend-map.md"
OUT_TSV = KB / "manifest" / "textboom-ocr-backend-map.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "textboom-ocr-backend-map"
OUT_JSON = OUT_DIR / "textboom-ocr-backend-map.json"

TEXTBOOM_APK = JADX / "system__system__app__TextBoom__TextBoom.apk"
SIDEBAR_APK = JADX / "system__system__priv-app__Sidebar__Sidebar.apk"
FRAMEWORK_JAR = JADX / "system__system__framework__framework.jar"
SERVICES_JAR = JADX / "system__system__framework__services.jar"
LIVE_TEXTBOOM_APK = ROOT / "apks" / "textboom-live" / "TextBoom-live-v3.2.2-base.apk"


@dataclass(frozen=True)
class EvidenceRow:
    area: str
    component: str
    backend: str
    branch: str
    file: str
    lines: str
    finding: str
    patch_implication: str
    required_tokens: tuple[str, ...]


@dataclass(frozen=True)
class DecisionRow:
    option: str
    status: str
    reason: str
    first_gate: str


ROWS: tuple[EvidenceRow, ...] = (
    EvidenceRow(
        "framework-trigger",
        "PressGestureDetector",
        "TextBoom service launch",
        "long-press image boom",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/smartisanos/view/PressGestureDetector.java",
        "204-244,1395-1440,1718-1741",
        "Framework starts com.smartisanos.textboom/.ocr.OcrFloatViewService and gates it through text_boom plus big_bang_ocr settings, keyguard state, launcher category, and OCR whitelist/blacklist checks.",
        "Backend replacement should not start in framework; preserve the existing OcrFloatViewService contract and settings observers.",
        ("OcrFloatViewService", "big_bang_ocr", "canImageBoom"),
    ),
    EvidenceRow(
        "settings-trigger",
        "TextBoomConfigObserver",
        "settings bundle",
        "TextBoomUtils settings source",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/textboom/TextBoomConfigObserver.java",
        "96-199,286-303,324-338",
        "Services observes text_boom, big_bang_ocr, and trigger-area settings, then publishes them to framework-side gesture code. Stock default for big_bang_ocr is disabled.",
        "Settings code changes can expose or default OCR, but there is no stock backend selector here.",
        ("big_bang_ocr", "text_boom", "toBundle"),
    ),
    EvidenceRow(
        "textboom-entry",
        "OcrFloatViewService",
        "TextBoom menu",
        "ACTION_BOOM_OPTION",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/ocr/OcrFloatViewService.java",
        "57-58,91-105,166-197,200-217",
        "The foreground service takes screenshots and shows the option UI. When image OCR is chosen it delegates to VoiceUtils.onBoomMenuClick.",
        "Keep this service and its ACTION_BOOM_OPTION path intact while replacing the OCR engine behind BoomOcrActivity.",
        ("ACTION_BOOM_OPTION", "TAG_IMAGE", "onBoomMenuClick"),
    ),
    EvidenceRow(
        "textboom-entry",
        "VoiceUtils",
        "TextBoom activity launch",
        "TAG_IMAGE -> ACTION_BOOM_IMAGE",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/voice/VoiceUtils.java",
        "529-570",
        "TAG_IMAGE creates an intent with Constant.ACTION_BOOM_IMAGE and starts the OCR activity after a short UI delay.",
        "The TextBoom UI-to-OCR edge is an intent boundary; a local backend should implement IOcrApi, not replace this launcher edge first.",
        ("TAG_IMAGE", "ACTION_BOOM_IMAGE", "startActivity"),
    ),
    EvidenceRow(
        "textboom-entry",
        "AndroidManifest",
        "TextBoom exposed contracts",
        "BOOM_IMAGE / BOOM_ACCESSBILITY / BOOM_OPTION",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/resources/AndroidManifest.xml",
        "73-78,115-124,141-149,166-175,202-209",
        "Manifest exposes BoomOcrActivity, BoomAccessOcrActivity, OcrFloatViewService, TextBoomCallProvider, FileProvider, and an Intsig OCR key.",
        "Preserve activity actions, provider authority, FileProvider authority, and metadata when repacking TextBoom.",
        ("ocr_key", "BOOM_IMAGE", "BOOM_ACCESSBILITY", "OcrFloatViewService", "fileprovider"),
    ),
    EvidenceRow(
        "textboom-backend",
        "BoomOcrActivity",
        "CsOcr",
        "normal and extended crop OCR",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/ocr/BoomOcrActivity.java",
        "209-212,344-349,505-534,614-648",
        "initView hard-codes new CsOcr. Both main crop and extended crop call mOcrApi.startOcr, and onActivityResult delegates to mOcrApi.handleOcrResult.",
        "Primary low-surface patch point is the IOcrApi implementation assignment, but the new implementation must return OcrInfo with compatible coordinates and error codes.",
        ("new CsOcr", "mOcrApi.startOcr", "handleOcrResult"),
    ),
    EvidenceRow(
        "textboom-backend",
        "BoomAccessOcrActivity",
        "CsOcr fallback plus online OCR",
        "accessibility OCR",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/ocr/BoomAccessOcrActivity.java",
        "222-237,279-300,338-340",
        "initOcr hard-codes new CsOcr. doOcr uses an online OcrThread when connected and falls back to mOcrApi.startOcr when offline.",
        "Accessibility OCR has an extra network branch. A local engine replacement should explicitly decide whether to bypass the online branch or keep it as a fallback.",
        ("new CsOcr", "OcrThread", "mOcrApi.startOcr", "handleOcrResult"),
    ),
    EvidenceRow(
        "textboom-backend",
        "CsOcr",
        "Intsig/CamScanner OpenAPI",
        "external activity OCR",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/ocr/CsOcr.java",
        "25-35,36-81,83-123,125-145,152-174",
        "CsOcr implements IOcrApi, creates CSOpenAPI, checks CamScanner install/availability, writes imageboom.jpg, grants FileProvider Uri permission, starts Intsig OCR, then converts CSOcrResult lines into TextBoom OcrInfo.",
        "This is the clean compatibility shape for a new local backend: implement IOcrApi and preserve listener, language, bitmap, and coordinate semantics.",
        ("implements IOcrApi", "CSOpenAPI", "startActivityForOCR", "CSOcrResult", "OcrInfo"),
    ),
    EvidenceRow(
        "textboom-backend",
        "CSOpenApiV1 (TextBoom copy)",
        "Intsig/CamScanner OpenAPI",
        "FileProvider Uri OCR",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/intsig/csopen/sdk/CSOpenApiV1.java",
        "19-31,49-83,216-245,253-289",
        "TextBoom's bundled SDK requires CamScanner version >= 53500, grants Uri permission only to com.intsig.camscanner, sends ACTION_OCR, and parses RESPONSE_DATA JSON.",
        "Removing CamScanner without replacing CSOpenAPI will break CsOcr. The local engine should avoid ACTION_OCR entirely or provide a compatible explicit shim.",
        ("CS_MIN_VERSION_CODE_FOR_CURRENT_SDK", "grantUriPermission", "ACTION_OCR", "RESPONSE_DATA"),
    ),
    EvidenceRow(
        "textboom-unused",
        "SmashOcr",
        "ByteDance smash native OCR",
        "unused IOcrApi implementation",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/smartisanos/textboom/ocr/SmashOcr.java",
        "25-36,39-67,71-110",
        "SmashOcr is an IOcrApi implementation, but its static initializer loads libsmash_ocr_lib.so and its process path wraps a ByteDance GeneralOcrWrapper model.",
        "Switching BoomOcrActivity from CsOcr to SmashOcr will likely crash unless the matching native library and ABI dependencies are present.",
        ("implements IOcrApi", "System.loadLibrary", "smash_ocr_lib", "tt_general_ocr_v1.0.model"),
    ),
    EvidenceRow(
        "textboom-unused",
        "GeneralOcrWrapper",
        "JNI wrapper",
        "SmashOcr native calls",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/sources/com/bytedance/smash/ocr/GeneralOcrWrapper.java",
        "34-51",
        "GeneralOcrWrapper is a JNI wrapper around InitModel and Process; it does not load the missing native library by itself.",
        "A native-loader bypass would need a replacement implementation with the same Java result objects or a broader IOcrApi patch.",
        ("GeneralOcrWrapper", "InitModel", "Process"),
    ),
    EvidenceRow(
        "sidebar-entry",
        "IdentifyFontView",
        "Sidebar font OCR entry",
        "top-area button",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/toparea/view/IdentifyFontView.java",
        "67-105",
        "The One Step top-area font button toggles FontUtils.startOcrActivity after fullscreen and sidebar-state checks.",
        "User decision on 2026-06-20 retires Sidebar font OCR. Do not route PP-OCR into this feature; hide/no-op the UI/provider/activity entry points instead.",
        ("FontUtils.startOcrActivity", "FontUtils.exitOcrActivity", "isFocusedWinFullScreen"),
    ),
    EvidenceRow(
        "sidebar-entry",
        "SidebarCallProvider",
        "Sidebar font OCR entry",
        "METHOD_FONT_REQUEST",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/storage/SidebarCallProvider.java",
        "134-140",
        "The provider METHOD_FONT_REQUEST also reaches FontUtils.toggleFont, including external-display context handling.",
        "After retiring Sidebar font OCR, this provider branch should not launch OCR. Keep provider stability, but make the font request path inert.",
        ("METHOD_FONT_REQUEST", "FontUtils.toggleFont", "SmtPCUtils"),
    ),
    EvidenceRow(
        "sidebar-entry",
        "FontUtils",
        "Sidebar font OCR activity launch",
        "ACTION_BOOM_FONT",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/open/font/FontUtils.java",
        "16-58,74-115",
        "FontUtils toggles smartisanos.intent.action.BOOM_FONT, tracks active activities per display, and broadcasts dismiss state.",
        "After retiring Sidebar font OCR, make start/toggle inert and keep dismiss cleanup harmless. Do not preserve ACTION_BOOM_FONT as a launch contract.",
        ("ACTION_BOOM_FONT", "startOcrActivity", "ACTION_BOOM_FONT_DISMISS"),
    ),
    EvidenceRow(
        "sidebar-backend",
        "AndroidManifest",
        "Sidebar font OCR contract",
        "BoomFontActivity",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/resources/AndroidManifest.xml",
        "282-298",
        "Sidebar declares BoomFontActivity for ACTION_BOOM_FONT and embeds a separate Intsig OCR key.",
        "Remove the implicit ACTION_BOOM_FONT exposure or disable the activity so external/internal callers cannot revive the retired font OCR feature.",
        ("BoomFontActivity", "BOOM_FONT", "ocr_key"),
    ),
    EvidenceRow(
        "sidebar-backend",
        "BoomFontActivity",
        "OCRhelper / Intsig OCR plus qiuziti font lookup",
        "crop -> OCR -> font-upload",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/open/font/BoomFontActivity.java",
        "94-118,142-148,207-220,299-374",
        "BoomFontActivity creates OCRhelper, runs OCR on the crop, asks the user to confirm text, then uploads character image slices plus text to a font-recognition service.",
        "This path is retired rather than modernized. Leave code/resources inert in the first ROM patch; avoid deep deletion until Sidebar remains boot-stable.",
        ("OCRhelper", "startOcr", "showTextComfirmDialog", "FontHelper.uploadFile"),
    ),
    EvidenceRow(
        "sidebar-backend",
        "OCRhelper",
        "Intsig/CamScanner OpenAPI",
        "file-path OCR",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/open/font/OCRhelper.java",
        "31-33,50-71,82-111",
        "OCRhelper reads ocr_key metadata, creates CSOpenAPI, checks CamScanner availability, starts OCR on FileHelper.OCR_IMAGE_PATH, and returns CSOcrResult to BoomFontActivity.",
        "No adapter is planned for this path because the feature is retired. PP-OCR work should target TextBoom's IOcrApi-compatible image OCR instead.",
        ("ocr_key", "CSOpenApiFactory", "isCamScannerAvailable", "startActivityForOCR", "CSOcrResult"),
    ),
    EvidenceRow(
        "sidebar-backend",
        "CSOpenApiV1 (Sidebar copy)",
        "Intsig/CamScanner OpenAPI",
        "file-path OCR",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/intsig/csopen/sdk/CSOpenApiV1.java",
        "41-79,202-230,239-276",
        "Sidebar's bundled SDK checks providers/version, starts ACTION_OCR with Uri.fromFile/image_src, and parses RESPONSE_DATA JSON into CSOcrResult.",
        "Do not build a Sidebar adapter first. This copy stays as inactive legacy code unless a later cleanup proves it can be deleted safely.",
        ("isCamScannerAvailable", "ACTION_OCR", "Uri.fromFile", "RESPONSE_DATA"),
    ),
    EvidenceRow(
        "sidebar-network",
        "FontHelper",
        "remote font-recognition service",
        "post-OCR font match",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/open/font/FontHelper.java",
        "19-58,93-107,118-136",
        "After OCR, Sidebar uploads cropped character JPEGs and recognized text to http://www.qiuziti.com/s/uploadOne.ashx for font lookup.",
        "This remote font lookup is one reason the feature is retired. PP-OCR does not solve the qiuziti.com dependency.",
        ("FONT_URL", "searchChars", "uploaded_file"),
    ),
)


DECISIONS: tuple[DecisionRow, ...] = (
    DecisionRow(
        "Add libsmash_ocr_lib.so and switch to SmashOcr",
        "retired",
        "User decision on 2026-06-20 stops the SmashOcr route. The native library is absent and this branch is no longer worth engineering time.",
        "No further SmashOcr work. Keep only as reverse-engineering evidence.",
    ),
    DecisionRow(
        "Bypass SmashOcr native loader",
        "retired",
        "Bypassing the native loader would still spend work on an abandoned branch. A new IOcrApi-compatible local backend is cleaner.",
        "Do not patch SmashOcr internals.",
    ),
    DecisionRow(
        "Keep CsOcr and preserve CamScanner dependency",
        "temporary baseline",
        "This is current behavior and probably why v0.37b can run TextBoom, but it keeps an external OCR provider and old dependency chain.",
        "Use it only to compare PP-OCR latency/accuracy and to prove feature parity.",
    ),
    DecisionRow(
        "Remove Sidebar/One Step font OCR",
        "selected",
        "This is separate from TextBoom image OCR and still depends on CamScanner plus qiuziti.com font lookup. The feature is not worth modernizing.",
        "Build an APK-level Sidebar patch that hides the top-area font button, makes FontUtils font launch inert, and removes ACTION_BOOM_FONT exposure.",
    ),
    DecisionRow(
        "Integrate Baidu/PaddleOCR local engine",
        "selected TextBoom route",
        "Current official PaddleOCR deploy/ppocr-android is a PP-OCRv6 Android Demo using ONNX Runtime. PP-OCRv6 small is the main TextBoom replacement candidate; tiny is only a speed/power fallback.",
        "Intake official ppocr-sdk first, compare CsOcr baseline vs PP-OCRv6 small on R2 screenshots, then patch TextBoom only after PASS.",
    ),
)


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def parse_ranges(spec: str) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            out.append((int(start), int(end)))
        else:
            value = int(part)
            out.append((value, value))
    return out


def read_excerpt(path: Path, lines: str) -> str:
    if not path.exists():
        return ""
    source = path.read_text(encoding="utf-8", errors="replace").splitlines()
    chunks: list[str] = []
    for start, end in parse_ranges(lines):
        lo = max(start - 1, 0)
        hi = min(end, len(source))
        chunks.extend(source[lo:hi])
    return "\n".join(chunks)


def row_status(row: EvidenceRow) -> tuple[str, str]:
    path = ROOT / row.file
    if not path.exists():
        return "FAIL", "file missing"
    excerpt = read_excerpt(path, row.lines)
    missing = [token for token in row.required_tokens if token not in excerpt]
    if missing:
        return "WARN", "token drift: " + ", ".join(missing)
    return "PASS", "required tokens present"


def textboom_apk_inventory() -> dict[str, object]:
    if not LIVE_TEXTBOOM_APK.exists():
        return {
            "apk": rel(LIVE_TEXTBOOM_APK),
            "status": "MISSING",
            "has_tt_general_model": False,
            "has_libsmash_ocr_lib": False,
            "native_lib_count": 0,
            "native_libs": [],
        }
    with zipfile.ZipFile(LIVE_TEXTBOOM_APK) as zf:
        names = zf.namelist()
    libs = sorted(name for name in names if name.startswith("lib/") and name.endswith(".so"))
    return {
        "apk": rel(LIVE_TEXTBOOM_APK),
        "status": "PASS",
        "has_tt_general_model": "assets/tt_general_ocr_v1.0.model" in names,
        "has_libsmash_ocr_lib": any(name.endswith("/libsmash_ocr_lib.so") for name in libs),
        "native_lib_count": len(libs),
        "native_libs": libs,
    }


def build_payload() -> dict[str, object]:
    row_payload = []
    for row in ROWS:
        status, note = row_status(row)
        data = asdict(row)
        data["status"] = status
        data["status_note"] = note
        row_payload.append(data)
    apk_inventory = textboom_apk_inventory()
    overall = "PASS" if all(row["status"] == "PASS" for row in row_payload) else "WARN"
    if apk_inventory["status"] != "PASS":
        overall = "WARN"
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "result": "TEXTBOOM_OCR_BACKEND_MAP_OFFLINE_" + overall,
        "rows": row_payload,
        "textboom_apk_inventory": apk_inventory,
        "decisions": [asdict(row) for row in DECISIONS],
    }


def write_tsv(payload: dict[str, object]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "area",
        "component",
        "backend",
        "branch",
        "status",
        "status_note",
        "file",
        "lines",
        "finding",
        "patch_implication",
    ]
    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in payload["rows"]:  # type: ignore[index]
            writer.writerow({col: row.get(col, "") for col in columns})  # type: ignore[union-attr]


def md_table(rows: list[dict[str, object]]) -> str:
    lines = [
        "| Area | Component | Backend | Branch | Status | Evidence | Finding |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        evidence = f"`{row['file']}:{row['lines']}`"
        finding = str(row["finding"]).replace("|", "\\|")
        lines.append(
            "| {area} | {component} | {backend} | {branch} | {status} | {evidence} | {finding} |".format(
                area=row["area"],
                component=row["component"],
                backend=row["backend"],
                branch=row["branch"],
                status=row["status"],
                evidence=evidence,
                finding=finding,
            )
        )
    return "\n".join(lines)


def write_md(payload: dict[str, object]) -> None:
    rows = payload["rows"]  # type: ignore[assignment]
    apk_inventory = payload["textboom_apk_inventory"]  # type: ignore[assignment]
    decisions = payload["decisions"]  # type: ignore[assignment]

    decision_lines = [
        "| Option | Status | Reason | First gate |",
        "| --- | --- | --- | --- |",
    ]
    for row in decisions:  # type: ignore[union-attr]
        decision_lines.append(
            f"| {row['option']} | {row['status']} | {row['reason']} | {row['first_gate']} |"
        )

    lib_list = apk_inventory.get("native_libs", [])  # type: ignore[union-attr]
    lib_summary = ", ".join(Path(name).name for name in lib_list) if lib_list else "none"

    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(
        f"""# TextBoom OCR Backend Map

Generated by `tools/r2-textboom-ocr-backend-map.py` on {payload['generated_at']}.

## Verdict

- Current TextBoom image OCR is hard-wired to `CsOcr`, which calls the Intsig/CamScanner OpenAPI.
- `SmashOcr` is present as an unused `IOcrApi` implementation, but it requires `libsmash_ocr_lib.so`; this branch is now retired.
- The current live TextBoom APK inventory has `assets/tt_general_ocr_v1.0.model={apk_inventory.get('has_tt_general_model')}` and `libsmash_ocr_lib.so={apk_inventory.get('has_libsmash_ocr_lib')}`.
- Sidebar/One Step font OCR is a separate route: `IdentifyFontView -> FontUtils -> BoomFontActivity -> OCRhelper -> CSOpenAPI -> CamScanner`.
- Sidebar font lookup has a second remote dependency after OCR: `FontHelper` uploads cropped glyph images plus confirmed text to `qiuziti.com`.
- Decision on 2026-06-20: retire Sidebar/One Step font OCR; PP-OCR is reserved for TextBoom image OCR modernization.

## Call Graph

```mermaid
flowchart TD
  PGD["framework.jar PressGestureDetector"] -->|ACTION_BOOM_OPTION| OFVS["TextBoom OcrFloatViewService"]
  OFVS -->|TAG_IMAGE| VU["VoiceUtils.onBoomMenuClick"]
  VU -->|ACTION_BOOM_IMAGE| BOA["BoomOcrActivity"]
  BOA -->|new CsOcr| CSO["CsOcr"]
  BAC["BoomAccessOcrActivity"] -->|online branch| NET["OcrThread remote OCR"]
  BAC -->|offline branch: new CsOcr| CSO
  CSO -->|ACTION_OCR| CAM["com.intsig.camscanner / camscanner_cn"]
  CAM -->|RESPONSE_DATA JSON| CSO
  CSO -->|List<OcrInfo>| BOA
  SM["SmashOcr retired"] -.->|System.loadLibrary| MISS["missing libsmash_ocr_lib.so"]
  IDF["Sidebar IdentifyFontView retired"] --> FU["FontUtils ACTION_BOOM_FONT retired"]
  SCP["SidebarCallProvider METHOD_FONT_REQUEST"] --> FU
  FU --> BFA["BoomFontActivity"]
  BFA --> OCRH["OCRhelper"]
  OCRH -->|ACTION_OCR| CAM
  BFA -->|after OCR text confirmation| QZ["FontHelper qiuziti.com font lookup"]
```

## Evidence

{md_table(rows)}

## Current APK Inventory

- APK: `{apk_inventory.get('apk')}`
- native libs: {apk_inventory.get('native_lib_count')} ({lib_summary})
- `assets/tt_general_ocr_v1.0.model`: {apk_inventory.get('has_tt_general_model')}
- `libsmash_ocr_lib.so`: {apk_inventory.get('has_libsmash_ocr_lib')}

## Route Decisions

{chr(10).join(decision_lines)}

## Benchmark Plan Before Replacement

Targets:

1. Current `CsOcr` route as the live baseline. This measures user-visible latency and failure modes, but it includes CamScanner activity launch overhead and any provider/network behavior.
2. Baidu/PaddleOCR local route using official `deploy/ppocr-android/ppocr-sdk`, PP-OCRv6 small, and ONNX Runtime Android native CPU inference. The already-proven PP-OCRv6 tiny zero-tensor smoke is only a compatibility proof and speed/power fallback.
3. Sidebar/One Step font OCR is not a benchmark target. It is retired because its end-to-end feature still depends on the separate qiuziti.com font-recognition service after OCR.

Metrics:

- cold init time, warm inference time, p50/p95 end-to-end latency
- PSS/RSS memory during first OCR and repeated OCR
- model/APK/system partition footprint
- line recall and character error rate on R2 screenshots
- coordinate quality for TextBoom `OcrInfo` click targets
- crash/fallback behavior when OCR receives empty, tiny, rotated, mixed Chinese/English, and browser-page crops

Harness outline:

1. Capture a small labeled R2 screenshot corpus with adb/root only after explicit live-device confirmation.
2. Keep `CsOcr` as baseline and collect logcat/timing around `startOcr` and `handleOcrResult`.
3. Build a standalone benchmark APK or service by reusing official ppocr-sdk preprocessing, DB postprocess, crop, and CTC decode.
4. Run PP-OCRv6 small on device, record latency/memory/accuracy, and only then patch TextBoom. Test tiny only if small is too slow or too heavy.
5. After TextBoom passes, do not backport PP-OCR into Sidebar font lookup unless the feature is explicitly revived.

## Immediate Next Step

Do not patch `new CsOcr` directly to `new SmashOcr`. The next Sidebar build should remove the retired font OCR entry points. The next OCR modernization build should be a no-ROM benchmark harness for a local `IOcrApi`-compatible PP-OCR engine, with `CsOcr` as the baseline.
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
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    return 0 if str(payload["result"]).endswith("_PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
