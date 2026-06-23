#!/usr/bin/env python3
"""Preflight a Smartisan ROM package modification from static KB indexes.

This is a read-only helper. It does not touch images, devices, or /data.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
GRAPH = DEFAULT_KB / "graph-corpus" / "modification-critical" / "graphify-out" / "graph.json"

HIGH_RISK_PACKAGES = {
    "android",
    "com.android.browser",
    "com.android.settings",
    "com.android.systemui",
    "com.android.packageinstaller",
    "com.android.permissioncontroller",
    "com.android.phone",
    "com.android.server.telecom",
    "com.android.providers.settings",
    "com.android.providers.telephony",
    "com.android.incallui",
    "com.android.mms",
    "com.smartisanos.keyguard",
    "com.smartisanos.launcher",
}

CORE_INTENT_VALUES = {
    "android.intent.action.MAIN",
    "android.intent.action.VIEW",
    "android.intent.category.HOME",
    "android.intent.category.LAUNCHER",
    "android.intent.category.BROWSABLE",
    "android.intent.action.BOOT_COMPLETED",
    "android.intent.action.PACKAGE_REPLACED",
    "android.intent.action.MY_PACKAGE_REPLACED",
    "android.intent.action.LOCALE_CHANGED",
}

SENSITIVE_SHARED_UIDS = {
    "android.uid.system",
    "android.uid.systemui",
    "android.uid.phone",
    "android.uid.bluetooth",
    "android.uid.nfc",
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def load_indexes(kb: Path) -> dict[str, list[dict[str, str]]]:
    indexes = kb / "indexes"
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
    return {name: read_rows(indexes / f"{name}.tsv") for name in names}


def package_rows(indexes: dict[str, list[dict[str, str]]], package: str) -> list[dict[str, str]]:
    return [row for row in indexes["packages"] if row.get("package") == package]


def source_names(rows: list[dict[str, str]]) -> set[str]:
    return {row.get("name", "") for row in rows if row.get("name")}


def related_rows(
    indexes: dict[str, list[dict[str, str]]],
    package: str,
    package_sources: set[str],
) -> dict[str, list[dict[str, str]]]:
    return {
        "components": [row for row in indexes["components"] if row.get("package") == package],
        "intent-filters": [row for row in indexes["intent-filters"] if row.get("package") == package],
        "uses-permissions": [row for row in indexes["uses-permissions"] if row.get("package") == package],
        "privapp-permissions": [row for row in indexes["privapp-permissions"] if row.get("package") == package],
        "sysconfig-packages": [row for row in indexes["sysconfig-packages"] if row.get("package") == package],
        "overlays-as-package": [row for row in indexes["overlays"] if row.get("package") == package],
        "overlays-targeting": [row for row in indexes["overlays"] if row.get("targetPackage") == package],
        "signatures": [
            row for row in indexes["signatures"]
            if row.get("source_name") in package_sources or row.get("rel_path") in package_sources
        ],
    }


def add_risk(risks: list[tuple[str, str]], level: str, text: str) -> None:
    risks.append((level, text))


def assess(action: str, package: str, pkgs: list[dict[str, str]], rel: dict[str, list[dict[str, str]]]) -> list[tuple[str, str]]:
    risks: list[tuple[str, str]] = []
    if not pkgs:
        add_risk(risks, "BLOCK", "package is absent from the static ROM package index")
        return risks

    if len(pkgs) > 1:
        add_risk(risks, "RED", "multiple static APK rows share this package name")

    if package in HIGH_RISK_PACKAGES:
        add_risk(risks, "RED", "package is on the project high-risk package list")

    if any(row.get("priv_app") == "yes" for row in pkgs):
        add_risk(risks, "ORANGE", "package is a priv-app")

    shared_uids = {row.get("sharedUserId", "") for row in pkgs if row.get("sharedUserId")}
    for uid in sorted(shared_uids & SENSITIVE_SHARED_UIDS):
        add_risk(risks, "RED", f"package uses sensitive sharedUserId {uid}")
    for uid in sorted(shared_uids - SENSITIVE_SHARED_UIDS):
        add_risk(risks, "ORANGE", f"package uses sharedUserId {uid}")

    if rel["privapp-permissions"]:
        add_risk(risks, "ORANGE", "package has privapp permission config entries")
    if rel["sysconfig-packages"]:
        add_risk(risks, "ORANGE", "package is referenced by sysconfig")
    if rel["overlays-as-package"]:
        add_risk(risks, "ORANGE", "package is itself an overlay package")
    if rel["overlays-targeting"]:
        add_risk(risks, "YELLOW", "other overlays target this package")

    exported = [row for row in rel["components"] if row.get("exported") == "true"]
    providers = [row for row in rel["components"] if row.get("type") == "provider"]
    if providers:
        add_risk(risks, "YELLOW", f"package declares {len(providers)} content providers")
    if exported:
        add_risk(risks, "YELLOW", f"package exposes {len(exported)} exported components")

    intent_values = {row.get("value", "") for row in rel["intent-filters"]}
    core_values = sorted(intent_values & CORE_INTENT_VALUES)
    if core_values:
        add_risk(risks, "YELLOW", "package participates in core intent resolution: " + ", ".join(core_values[:8]))

    if action == "replace":
        add_risk(risks, "ORANGE", "same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior")
        if package == "com.android.browser":
            add_risk(risks, "RED", "BrowserChrome same-package replacements v0.3/v0.3.1 previously failed before lockscreen")

    if not risks:
        add_risk(risks, "GREEN", "no static ROM risk flags found in the package indexes")

    return risks


def worst_level(risks: list[tuple[str, str]]) -> str:
    order = {"GREEN": 0, "YELLOW": 1, "ORANGE": 2, "RED": 3, "BLOCK": 4}
    return max(risks, key=lambda item: order.get(item[0], 0))[0]


def print_rows(title: str, rows: list[dict[str, str]], columns: list[str], limit: int) -> None:
    print(f"\n## {title}")
    if not rows:
        print("none")
        return
    print("| " + " | ".join(columns) + " |")
    print("| " + " | ".join("---" for _ in columns) + " |")
    for row in rows[:limit]:
        print("| " + " | ".join((row.get(col, "") or "").replace("|", "\\|") for col in columns) + " |")
    if len(rows) > limit:
        print(f"\n... {len(rows) - limit} more rows")


def graph_queries(package: str, action: str) -> list[str]:
    base = [
        f'graphify query "What PackageManagerService and PackageManagerServiceSmtEx paths affect {action} for {package}?" --graph {GRAPH} --budget 2400',
        f'graphify query "What ResourcesManagerSmtEx AssetManagerSmtEx IconManager paths can affect {package} resources and icons?" --graph {GRAPH} --budget 2400',
        f'graphify query "What OverlayManager and SystemConfig paths affect {package} overlays permissions or sysconfig?" --graph {GRAPH} --budget 2400',
    ]
    if package == "com.android.browser":
        base.append(
            f'graphify query "What WebView browser default intent keyguard and launcher paths can be affected by replacing {package}?" --graph {GRAPH} --budget 2600'
        )
    elif action == "replace":
        base.append(
            f'graphify query "What package cache preferred activity resource loading and boot-order paths can be affected by replacing {package}?" --graph {GRAPH} --budget 2600'
        )
    return base


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package")
    parser.add_argument("--action", choices=["delete", "replace", "overlay", "inspect"], default="inspect")
    parser.add_argument("--kb", type=Path, default=DEFAULT_KB)
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    indexes = load_indexes(args.kb)
    pkgs = package_rows(indexes, args.package)
    rel = related_rows(indexes, args.package, source_names(pkgs))
    risks = assess(args.action, args.package, pkgs, rel)
    level = worst_level(risks)

    print(f"# ROM Modification Preflight: {args.package}")
    print(f"\naction: {args.action}")
    print(f"static_kb: {args.kb}")
    print(f"overall_level: {level}")

    print("\n## Risk Flags")
    for risk_level, text in risks:
        print(f"- {risk_level}: {text}")

    print_rows("Package Rows", pkgs, ["package", "partition", "rel_path", "priv_app", "versionCode", "versionName", "sharedUserId", "status", "sha256"], args.limit)

    component_counts = Counter(row.get("type", "") for row in rel["components"])
    print("\n## Component Summary")
    if component_counts:
        for kind, count in sorted(component_counts.items()):
            print(f"- {kind}: {count}")
    else:
        print("none")

    print_rows("Exported Components", [row for row in rel["components"] if row.get("exported") == "true"], ["type", "name", "exported"], args.limit)
    print_rows("Core Intent Filters", [row for row in rel["intent-filters"] if row.get("value") in CORE_INTENT_VALUES], ["component_type", "component_name", "entry_type", "value"], args.limit)
    print_rows("Requested Permissions", rel["uses-permissions"], ["permission", "source_name"], args.limit)
    print_rows("Privapp Permission Config", rel["privapp-permissions"], ["source_file", "entry_type", "permission"], args.limit)
    print_rows("Sysconfig References", rel["sysconfig-packages"], ["source_file", "tag", "attrs"], args.limit)
    print_rows("Overlays As Package", rel["overlays-as-package"], ["package", "targetPackage", "isStatic", "priority", "partition", "rel_path"], args.limit)
    print_rows("Overlays Targeting Package", rel["overlays-targeting"], ["package", "targetPackage", "isStatic", "priority", "partition", "rel_path"], args.limit)
    print_rows("Signatures", rel["signatures"], ["source_name", "signature_status", "cert_sha256", "owner", "algorithm"], args.limit)

    print("\n## Required Graphify Follow-Up")
    for query in graph_queries(args.package, args.action):
        print(f"- `{query}`")

    print("\n## Gate")
    if level in {"BLOCK", "RED"}:
        print("Do not build or flash from this package-only evidence. Perform a focused source walk and define rollback plus package/cache cleanup first.")
    elif level == "ORANGE":
        print("Build only as a small isolated variant after graph/source review, with a local sparse rollback image verified.")
    elif level == "YELLOW":
        print("Acceptable candidate for a small hard-ROM experiment after confirming partition target and rollback.")
    else:
        print("Acceptable low-risk static candidate, subject to image and flash protocol checks.")


if __name__ == "__main__":
    main()
