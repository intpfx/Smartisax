#!/usr/bin/env python3
"""Audit launcher-entry hiding targets for the Smartisan R2 hard-ROM route.

This helper is read-only. It does not build images, touch devices, flash,
reboot, erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import importlib.util
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
INDEXES = KB / "indexes"
OUT_TSV = KB / "manifest" / "launcher-entry-hide-audit.tsv"
OUT_MD = ROOT / "docs" / "research" / "launcher-entry-hide-audit.md"
PREFLIGHT_PATH = ROOT / "tools" / "r2-rom-mod-preflight.py"

MAIN = "android.intent.action.MAIN"
LAUNCHER = "android.intent.category.LAUNCHER"


@dataclass(frozen=True)
class Target:
    feature: str
    package: str
    launcher_component: str
    stage: str
    risk_note: str
    preserve: str
    recommendation: str


TARGETS = [
    Target(
        feature="视频播放器",
        package="com.smartisanos.videoplayerproject",
        launcher_component="com.smartisanos.videoplayerproject.MainActivity",
        stage="v0.26a first manifest-only candidate",
        risk_note="priv-app but no sensitive sharedUserId; same activity keeps VIEW video/http/content/file filters",
        preserve="preserve VIEW/BROWSABLE video and playlist handlers plus VideoProvider",
        recommendation="remove only android.intent.category.LAUNCHER from MainActivity filter 1; keep MainActivity enabled",
    ),
    Target(
        feature="屏幕录制",
        package="com.smartisanos.screenrecorder",
        launcher_component="com.smartisanos.screenrecorder.EmptyActivity",
        stage="v0.26a first manifest-only candidate",
        risk_note="priv-app launcher trampoline; recording services/settings activities must remain resolvable",
        preserve="preserve ScreenRecorderService, ScreenshotToolService, settings/options/countdown/permission activities, and provider",
        recommendation="remove only android.intent.category.LAUNCHER from EmptyActivity launcher filter; keep services and settings components",
    ),
    Target(
        feature="搜索",
        package="com.smartisanos.quicksearch",
        launcher_component="com.android.quicksearchbox.SearchActivity",
        stage="v0.26a first manifest-only candidate",
        risk_note="system app with boot receiver and providers; launcher filter is separate from GLOBAL_SEARCH/SEARCH filters",
        preserve="preserve GLOBAL_SEARCH, SEARCH, launchSpeech, TNTSearchActivity, providers, and boot receiver",
        recommendation="remove only android.intent.category.LAUNCHER from SearchActivity MAIN launcher filter; keep search intent filters",
    ),
    Target(
        feature="闪念胶囊",
        package="com.smartisanos.sara",
        launcher_component="com.smartisanos.sara.bubble.SettingActivity",
        stage="v0.26b after first batch passes live",
        risk_note="large priv-app VoiceAssistant package with speech, provider, locale, accessibility, and Smartisan shortcut coupling",
        preserve="preserve bubble/shell/voice command activities, providers, receivers, services, and idea-pill settings routes",
        recommendation="after source review, remove only android.intent.category.LAUNCHER from SettingActivity launcher filter",
    ),
    Target(
        feature="一步",
        package="com.smartisanos.sidebar",
        launcher_component="com.smartisanos.sidebar.setting.SettingActivity",
        stage="deferred single-package RED gate",
        risk_note="priv-app coreApp with sharedUserId android.uid.system; do not batch with lower-risk targets",
        preserve="preserve SidebarService, boot/keyguard/top-area receivers, providers, sticky activities, and explicit settings routes",
        recommendation="after focused source/graph review and a dedicated gate, remove only LAUNCHER from SettingActivity; keep DEFAULT/explicit access",
    ),
]


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict[str, str]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({col: row.get(col, "") for col in columns})


def load_preflight() -> Any:
    spec = importlib.util.spec_from_file_location("r2_rom_mod_preflight", PREFLIGHT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {PREFLIGHT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_indexes() -> dict[str, list[dict[str, str]]]:
    names = [
        "packages",
        "components",
        "intent-filters",
        "uses-permissions",
        "privapp-permissions",
        "sysconfig-packages",
        "overlays",
        "signatures",
    ]
    return {name: read_rows(INDEXES / f"{name}.tsv") for name in names}


def package_rows(indexes: dict[str, list[dict[str, str]]], package: str) -> list[dict[str, str]]:
    return [row for row in indexes["packages"] if row.get("package") == package]


def group_filters(rows: list[dict[str, str]]) -> dict[tuple[str, str, str], list[dict[str, str]]]:
    grouped: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for row in rows:
        key = (row.get("component_type", ""), row.get("component_name", ""), row.get("filter_index", ""))
        grouped.setdefault(key, []).append(row)
    return grouped


def values_for(rows: list[dict[str, str]], entry_type: str) -> list[str]:
    return sorted(row.get("value", "") for row in rows if row.get("entry_type") == entry_type and row.get("value"))


def data_for(rows: list[dict[str, str]]) -> list[str]:
    return sorted(row.get("value", "") for row in rows if row.get("entry_type") == "data" and row.get("value"))


def summarize_filter(rows: list[dict[str, str]]) -> str:
    actions = values_for(rows, "action")
    categories = values_for(rows, "category")
    data = data_for(rows)
    parts = []
    if actions:
        parts.append("actions=" + ",".join(actions))
    if categories:
        parts.append("categories=" + ",".join(categories))
    if data:
        parts.append("data=" + ",".join(data[:8]) + ("..." if len(data) > 8 else ""))
    return "; ".join(parts)


def non_launcher_summary(package: str, component: str, filters: dict[tuple[str, str, str], list[dict[str, str]]]) -> str:
    summaries = []
    for (component_type, component_name, filter_index), rows in sorted(filters.items()):
        if component_type != "activity" or component_name != component:
            continue
        categories = values_for(rows, "category")
        if LAUNCHER in categories:
            continue
        summaries.append(f"filter {filter_index}: {summarize_filter(rows)}")
    if summaries:
        return " | ".join(summaries[:6])
    return f"no non-launcher filters on {component}; preserve other package components"


def package_risk(preflight: Any, indexes: dict[str, list[dict[str, str]]], package: str) -> tuple[str, str]:
    pkgs = preflight.package_rows(indexes, package)
    rel = preflight.related_rows(indexes, package, preflight.source_names(pkgs))
    risks = preflight.assess("replace", package, pkgs, rel)
    level = preflight.worst_level(risks)
    return level, "; ".join(f"{risk_level}: {text}" for risk_level, text in risks[:6])


def build_rows() -> list[dict[str, str]]:
    preflight = load_preflight()
    indexes = load_indexes()
    all_filters = group_filters(indexes["intent-filters"])
    rows: list[dict[str, str]] = []

    for target in TARGETS:
        pkgs = package_rows(indexes, target.package)
        pkg = pkgs[0] if pkgs else {}
        package_filters = {
            key: value
            for key, value in all_filters.items()
            if value and value[0].get("package") == target.package
        }
        launcher_filters = []
        for (component_type, component_name, filter_index), filter_rows in package_filters.items():
            if component_type != "activity":
                continue
            actions = values_for(filter_rows, "action")
            categories = values_for(filter_rows, "category")
            if MAIN in actions and LAUNCHER in categories:
                launcher_filters.append((component_name, filter_index, filter_rows))

        level, risk_flags = package_risk(preflight, indexes, target.package)
        components = [row for row in indexes["components"] if row.get("package") == target.package]
        providers = [row for row in components if row.get("type") == "provider"]
        exported = [row for row in components if row.get("exported") == "true"]

        if not launcher_filters:
            rows.append(
                {
                    "feature": target.feature,
                    "package": target.package,
                    "source_name": pkg.get("name", ""),
                    "partition": pkg.get("partition", ""),
                    "rel_path": pkg.get("rel_path", ""),
                    "priv_app": pkg.get("priv_app", ""),
                    "shared_uid": pkg.get("sharedUserId", ""),
                    "static_replace_level": level,
                    "launcher_component": "",
                    "filter_index": "",
                    "launcher_filter": "no MAIN/LAUNCHER filter found",
                    "preserved_non_launcher_filters": "",
                    "component_counts": f"components={len(components)} providers={len(providers)} exported={len(exported)}",
                    "stage": target.stage,
                    "risk_note": target.risk_note,
                    "recommendation": "do not build until launcher filter mismatch is resolved",
                    "preserve": target.preserve,
                    "risk_flags": risk_flags,
                }
            )
            continue

        for component_name, filter_index, filter_rows in launcher_filters:
            rows.append(
                {
                    "feature": target.feature,
                    "package": target.package,
                    "source_name": pkg.get("name", ""),
                    "partition": pkg.get("partition", ""),
                    "rel_path": pkg.get("rel_path", ""),
                    "priv_app": pkg.get("priv_app", ""),
                    "shared_uid": pkg.get("sharedUserId", ""),
                    "static_replace_level": level,
                    "launcher_component": component_name,
                    "filter_index": filter_index,
                    "launcher_filter": summarize_filter(filter_rows),
                    "preserved_non_launcher_filters": non_launcher_summary(target.package, component_name, package_filters),
                    "component_counts": f"components={len(components)} providers={len(providers)} exported={len(exported)}",
                    "stage": target.stage,
                    "risk_note": target.risk_note,
                    "recommendation": target.recommendation,
                    "preserve": target.preserve,
                    "risk_flags": risk_flags,
                }
            )
    return rows


def markdown_table(rows: list[dict[str, str]]) -> str:
    columns = [
        "feature",
        "package",
        "static_replace_level",
        "launcher_component",
        "filter_index",
        "stage",
    ]
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join("---" for _ in columns) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(row.get(col, "").replace("|", "\\|") for col in columns) + " |")
    return "\n".join(lines)


def write_markdown(rows: list[dict[str, str]]) -> None:
    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    first_batch = [row for row in rows if row.get("stage", "").startswith("v0.26a")]
    deferred = [row for row in rows if not row.get("stage", "").startswith("v0.26a")]
    body = f"""# Launcher Entry Hide Audit

Generated: {generated}

This read-only audit covers the user's next requested target: keep the
features working, but remove their desktop launcher entries for 闪念胶囊,
视频播放器, 屏幕录制, 搜索, and 一步.

This is not a hard delete and not a runtime `pm disable` plan. The safer ROM
route is manifest-only launcher-surface surgery: remove only
`android.intent.category.LAUNCHER` from the identified `MAIN` launcher
intent-filter while keeping the activity enabled and preserving non-launcher
intent filters, services, providers, receivers, permissions, and explicit
settings routes.

## Summary

{markdown_table(rows)}

## Proposed Staging

First live candidate:

```text
v0.26a: 视频播放器 + 屏幕录制 + 搜索
```

Reason: these three are the smallest set with clear launcher-only surfaces and
without `android.uid.system`. They still need package-specific manifest-only
APK build and offline verification before any flash authorization.

Deferred candidates:

```text
v0.26b: 闪念胶囊 / com.smartisanos.sara
single-package RED gate: 一步 / com.smartisanos.sidebar
```

Reason: Sara is a large VoiceAssistant priv-app with speech/provider/shortcut
coupling. Sidebar/One Step is a core priv-app using
`sharedUserId=android.uid.system`, so it must not be batched with lower-risk
targets.

## Candidate Details

"""
    for row in rows:
        body += f"""### {row['feature']} / `{row['package']}`

```text
source: {row['partition']}:{row['rel_path']}
source_name: {row['source_name']}
launcher_component: {row['launcher_component']}
launcher_filter_index: {row['filter_index']}
launcher_filter: {row['launcher_filter']}
preserve: {row['preserve']}
preserved_non_launcher_filters: {row['preserved_non_launcher_filters']}
component_counts: {row['component_counts']}
static_replace_level: {row['static_replace_level']}
risk_note: {row['risk_note']}
recommendation: {row['recommendation']}
preflight_flags: {row['risk_flags']}
```

"""

    body += f"""## Build Gate

For a manifest-only candidate, the APK-level verifier must prove:

```text
AndroidManifest.xml changed only as expected
classes*.dex byte-identical
resources.arsc byte-identical
native libraries/assets byte-identical
package name/version/sharedUserId/permissions/providers/services/receivers unchanged
the original signing material remains readable by the system-partition parser
the edited manifest no longer resolves MAIN+LAUNCHER for selected components
all preserved feature intents still resolve
```

This is a new gate. The v0.24 live result proves resources-only APK replacement
on the current line, but it does not by itself prove manifest component changes.

## Live Verification After Any Future Flash

Run read-only checks after boot:

```bash
adb -s bb12d264 shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim'
tools/r2-root.sh status
adb -s bb12d264 shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head"
adb -s bb12d264 shell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER'
```

Expected launcher result for the selected package subset: the removed desktop
components are absent from `MAIN + LAUNCHER` resolution, while package paths
remain under `/system` and feature-specific intent filters still resolve.

## Generated Files

```text
{OUT_MD.relative_to(ROOT)}
{OUT_TSV.relative_to(ROOT)}
```
"""
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(body, encoding="utf-8")


def main() -> None:
    rows = build_rows()
    columns = [
        "feature",
        "package",
        "source_name",
        "partition",
        "rel_path",
        "priv_app",
        "shared_uid",
        "static_replace_level",
        "launcher_component",
        "filter_index",
        "launcher_filter",
        "preserved_non_launcher_filters",
        "component_counts",
        "stage",
        "risk_note",
        "recommendation",
        "preserve",
        "risk_flags",
    ]
    write_tsv(OUT_TSV, rows, columns)
    write_markdown(rows)
    print(f"wrote {OUT_MD}")
    print(f"wrote {OUT_TSV}")


if __name__ == "__main__":
    main()
