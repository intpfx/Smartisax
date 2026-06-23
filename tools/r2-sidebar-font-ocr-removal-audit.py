#!/usr/bin/env python3
"""Generate the Sidebar/One Step font OCR removal plan.

This is an offline audit helper. It reads local JADX output and writes a small
markdown/TSV/JSON evidence bundle. It does not build images, touch the phone,
flash, reboot, erase partitions, or modify /data.
"""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
SIDEBAR = KB / "jadx" / "system__system__priv-app__Sidebar__Sidebar.apk"
OUT_MD = ROOT / "docs" / "research" / "sidebar-font-ocr-removal-plan.md"
OUT_TSV = KB / "manifest" / "sidebar-font-ocr-removal-plan.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "sidebar-font-ocr-removal-plan"
OUT_JSON = OUT_DIR / "sidebar-font-ocr-removal-plan.json"


@dataclass(frozen=True)
class EvidenceRow:
    area: str
    component: str
    file: str
    lines: str
    finding: str
    patch_decision: str
    required_tokens: tuple[str, ...]


ROWS: tuple[EvidenceRow, ...] = (
    EvidenceRow(
        "default-state",
        "SidebarApplication",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/SidebarApplication.java",
        "44-59",
        "Application startup already writes Settings.System font_lookup_switch=0.",
        "Keep this behavior. The removal patch should also make direct launch paths inert in case stale DB/settings state survives.",
        ("font_lookup_switch", "putInt"),
    ),
    EvidenceRow(
        "settings-ui",
        "ToolsSwitchActivity",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/setting/ToolsSwitchActivity.java",
        "45-55,69-81",
        "The settings page finds font_lookup_switch_root and sets it to GONE, but still observes font_lookup_switch.",
        "No user-visible settings row is expected. Keep it hidden and avoid relying on this as the only guard.",
        ("font_lookup_switch_root", "setVisibility", "font_lookup_switch"),
    ),
    EvidenceRow(
        "top-entry",
        "ToolButtonManager",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/util/ToolButtonManager.java",
        "56-68,70-76,194-210",
        "ToolButtonManager can still add type 1 when font_lookup_switch is true or stale DB state includes it.",
        "Do not hard-delete type 1 in the first patch. Hide/no-op the view and call path so stale state cannot crash Sidebar.",
        ("font_lookup_switch", "update(1", "ToolsHelper.isFontLookupOn"),
    ),
    EvidenceRow(
        "top-entry",
        "ToolButtonAdapter",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/toparea/view/ToolButtonAdapter.java",
        "31-37,229-236",
        "Type 1 maps to tool_button_item_identify_font and the adapter expects R.id.tool_button inside the inflated view.",
        "Keep R.id.tool_button present, but mark the layout root GONE/0dp so the entry disappears without a NullSafe/NPE risk.",
        ("tool_button_item_identify_font", "R.id.tool_button"),
    ),
    EvidenceRow(
        "top-entry",
        "IdentifyFontView",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/toparea/view/IdentifyFontView.java",
        "67-105",
        "The top-area button directly calls FontUtils.startOcrActivity after UI checks.",
        "Patch onClick to return immediately or rely on FontUtils no-op plus hidden view; verify startOcrActivity is no longer referenced from the method.",
        ("onClick", "FontUtils.startOcrActivity"),
    ),
    EvidenceRow(
        "provider-entry",
        "SidebarCallProvider",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/storage/SidebarCallProvider.java",
        "134-140",
        "METHOD_FONT_REQUEST can still reach FontUtils.toggleFont, including on external display contexts.",
        "Make FontUtils.toggleFont inert so this provider branch remains stable but cannot launch font OCR.",
        ("METHOD_FONT_REQUEST", "FontUtils.toggleFont"),
    ),
    EvidenceRow(
        "launch-contract",
        "FontUtils",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/open/font/FontUtils.java",
        "16-58,74-115",
        "FontUtils exposes ACTION_BOOM_FONT launch and ACTION_BOOM_FONT_DISMISS cleanup.",
        "No-op startOcrActivity and toggleFont; keep isShowing/exit/dismiss safe for any already-running activity cleanup.",
        ("ACTION_BOOM_FONT", "startOcrActivity", "toggleFont", "ACTION_BOOM_FONT_DISMISS"),
    ),
    EvidenceRow(
        "manifest-contract",
        "BoomFontActivity",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/resources/AndroidManifest.xml",
        "282-298",
        "BoomFontActivity is exported through smartisanos.intent.action.BOOM_FONT and carries an Intsig ocr_key.",
        "Remove the implicit intent-filter and set BoomFontActivity android:enabled=false in the APK candidate.",
        ("BoomFontActivity", "smartisanos.intent.action.BOOM_FONT", "ocr_key"),
    ),
    EvidenceRow(
        "backend-retired",
        "BoomFontActivity/OCRhelper/FontHelper",
        "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/sources/com/smartisanos/sidebar/open/font/BoomFontActivity.java",
        "142-148,207-220,299-374",
        "The retired flow creates OCRhelper, calls CamScanner OCR, then posts font lookup data to qiuziti.com.",
        "Do not integrate PP-OCR here. Leave backend code inert first; deep-delete classes/resources only after Sidebar stability is proven.",
        ("OCRhelper", "startOcr", "FontHelper"),
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


def read_excerpt(path: Path, lines: str) -> str:
    if not path.exists():
        return ""
    source = path.read_text(encoding="utf-8", errors="replace").splitlines()
    chunks: list[str] = []
    for start, end in parse_ranges(lines):
        chunks.extend(source[max(start - 1, 0) : min(end, len(source))])
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


def build_payload() -> dict[str, object]:
    rows = []
    for row in ROWS:
        data = asdict(row)
        status, note = row_status(row)
        data["status"] = status
        data["status_note"] = note
        rows.append(data)
    result = "PASS" if all(row["status"] == "PASS" for row in rows) else "WARN"
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "result": "SIDEBAR_FONT_OCR_REMOVAL_PLAN_OFFLINE_" + result,
        "rows": rows,
        "selected_strategy": [
            "keep Sidebar package/component identity",
            "hide top-area font button layout root while preserving R.id.tool_button",
            "no-op IdentifyFontView.onClick",
            "no-op FontUtils.startOcrActivity and make toggleFont cleanup-only",
            "remove ACTION_BOOM_FONT intent-filter and disable BoomFontActivity",
            "do not delete backend classes/resources until live stability is proven",
        ],
    }


def write_tsv(payload: dict[str, object]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "area",
        "component",
        "status",
        "status_note",
        "file",
        "lines",
        "finding",
        "patch_decision",
    ]
    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in payload["rows"]:  # type: ignore[index]
            writer.writerow({col: row.get(col, "") for col in columns})  # type: ignore[union-attr]


def md_table(rows: list[dict[str, object]]) -> str:
    out = [
        "| Area | Component | Status | Evidence | Finding | Patch decision |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        finding = str(row["finding"]).replace("|", "\\|")
        decision = str(row["patch_decision"]).replace("|", "\\|")
        out.append(
            f"| {row['area']} | {row['component']} | {row['status']} | "
            f"`{row['file']}:{row['lines']}` | {finding} | {decision} |"
        )
    return "\n".join(out)


def write_md(payload: dict[str, object]) -> None:
    rows = payload["rows"]  # type: ignore[assignment]
    strategy = "\n".join(f"- {item}" for item in payload["selected_strategy"])  # type: ignore[index]
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(
        f"""# Sidebar Font OCR Removal Plan

Generated by `tools/r2-sidebar-font-ocr-removal-audit.py` on {payload['generated_at']}.

## Verdict

Sidebar/One Step font OCR should be retired, not migrated to PP-OCR. It is not
the same path as TextBoom image OCR: it starts from the One Step tool button or
`METHOD_FONT_REQUEST`, launches `BoomFontActivity`, delegates OCR to the
CamScanner/Intsig SDK, then uploads cropped glyphs and recognized text to
`qiuziti.com` for font matching.

The first ROM-safe removal should be behavioral, not a broad resource purge:
hide the entry, make launch helpers inert, and remove the implicit manifest
contract. Leave legacy classes/resources present until a live boot proves
Sidebar remains stable.

## Selected Strategy

{strategy}

## Flow

```mermaid
flowchart TD
  APP["SidebarApplication"] -->|writes font_lookup_switch=0| SET["Settings.System"]
  SET --> TBM["ToolButtonManager"]
  TBM --> TBA["ToolButtonAdapter type 1"]
  TBA --> IDF["IdentifyFontView"]
  IDF -->|retired/no-op| FU["FontUtils"]
  SCP["SidebarCallProvider METHOD_FONT_REQUEST"] -->|retired/no-op| FU
  FU -.->|old ACTION_BOOM_FONT removed| BFA["BoomFontActivity disabled"]
  BFA -.-> OCRH["OCRhelper / CamScanner"]
  BFA -.-> QZ["FontHelper / qiuziti.com"]
```

## Evidence

{md_table(rows)}

## Build Gate

The APK candidate is allowed to change only:

- `AndroidManifest.xml`
- `classes.dex`
- `res/layout/tool_button_item_identify_font.xml`

The package name, shared UID, signing-certificate carrier, existing Sidebar
launcher-entry hide, and v0.29 topbar blank-slot behavior must remain intact.

## Next Step

Build the APK-only candidate first. After the APK verifies, wire it into a
v0.38 super image based on the current v0.37b FEC-preserving build path.
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
