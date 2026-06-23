#!/usr/bin/env python3
"""Audit ROM locale-prune coverage against the current hard-ROM baseline.

This script is read-only. It combines the static locale inventory, package
index, and the known v0.2/v0.4/v0.7/v0.10 candidate boundaries to answer:

* which Japanese/Korean resources are already gone because the package was
  removed from the current v0.4 baseline;
* which are covered by the v0.10 framework/product hard-prune candidate;
* which remain as true hard-prune work.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable


REMOVED_BY_V02_V04 = {
    "com.smartisanos.appstore",
    "com.smartisanos.gamestore",
    "com.smartisanos.compass",
    "com.sohu.inputmethod.sogou.chuizi",
    "com.iflytek.inputmethod.smartisan",
    "com.android.email",
    "com.smartisanos.handinhand",
    "com.smartisanos.writer",
    "com.smartisanos.notes",
    "com.smartisanos.calculator",
    "com.smartisanos.recharge",
    "com.smartisanos.cloudgallery",
    "com.smartisanos.recorder",
    "com.smartisanos.launcher.themes",
    "com.smartisanos.launcher.theme.aero",
    "com.smartisanos.launcher.theme.lightblue",
    "com.smartisanos.launcher.theme.trans",
    "com.smartisanos.launcher.theme.bamboo",
    "com.smartisanos.launcher.theme.glime",
    "com.smartisanos.launcher.theme.leaf",
    "com.smartisanos.launcher.theme.raven",
}

PRUNED_BY_V010 = {
    "system__system__framework__framework-res.apk",
    "system__system__framework__framework-smartisanos-res__framework-smartisanos-res.apk",
    "product__overlay__DisplayCutoutEmulationCorner__DisplayCutoutEmulationCornerOverlay.apk",
    "product__overlay__DisplayCutoutEmulationDouble__DisplayCutoutEmulationDoubleOverlay.apk",
    "product__overlay__DisplayCutoutEmulationHole__DisplayCutoutEmulationHoleOverlay.apk",
    "product__overlay__DisplayCutoutEmulationTall__DisplayCutoutEmulationTallOverlay.apk",
    "product__overlay__DisplayCutoutEmulationWaterfall__DisplayCutoutEmulationWaterfallOverlay.apk",
}

PRUNED_BY_V013_SYSTEM_IMAGE = {
    "com.android.hotspot2.osulogin",
    "com.android.printservice.recommendation",
    "com.android.protips",
}

PRUNED_BY_V017A_SYSTEM_IMAGE = {
    "com.android.dreams.basic",
    "com.android.htmlviewer",
    "com.android.printspooler",
    "com.android.simappdialog",
    "com.android.wallpaper.livepicker",
}

PRUNED_BY_V017B_PRODUCT_SYSTEM_EXT_IMAGE = {
    "com.android.dreams.phototable",
    "com.qualcomm.qti.confdialer",
}

PRUNED_BY_V022_SYSTEM_IMAGE = {
    "com.android.companiondevicemanager",
    "com.smartisanos.share.browser",
    "com.smartisanos.tracker",
}

PRUNED_BY_V024_SYSTEM_IMAGE = {
    "com.smartisanos.cleaner",
}

VISIBLE_FILTER_ONLY_V07 = {
    "com.android.settings",
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

# These are not good early APK resource-prune probes even when the static risk
# label is GREEN/YELLOW; they are coupled to boot/web/input/security flows or to
# previously observed failed same-package browser replacement work.
DEFER_GREEN_PACKAGES = {
    "com.android.browser",
    "com.android.webview",
    "com.android.inputmethod.latin",
    "com.android.captiveportallogin",
    "com.android.certinstaller",
    "com.android.ons",
    "com.android.traceur",
    "com.smartisanos.desktop",
    "com.smartisanos.launcher",
    "com.android.launcher3",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--locale-inventory",
        default="reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv",
    )
    parser.add_argument(
        "--package-index",
        default="reverse/smartisan-8.5.3-rom-static/indexes/packages.tsv",
    )
    parser.add_argument(
        "--component-index",
        default="reverse/smartisan-8.5.3-rom-static/indexes/components.tsv",
    )
    parser.add_argument(
        "--intent-index",
        default="reverse/smartisan-8.5.3-rom-static/indexes/intent-filters.tsv",
    )
    parser.add_argument(
        "--permission-index",
        default="reverse/smartisan-8.5.3-rom-static/indexes/uses-permissions.tsv",
    )
    parser.add_argument(
        "--out-tsv",
        default="reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv",
    )
    parser.add_argument(
        "--markdown",
        default="docs/research/locale-prune-coverage-audit.md",
    )
    parser.add_argument(
        "--apk-only-manifest",
        default="hard-rom/build/apk/locale-prune-apk-only-manifest.tsv",
    )
    return parser.parse_args()


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def read_apk_only_manifest(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    out: dict[str, dict[str, str]] = {}
    with path.open(encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            package = row.get("package", "")
            if not package:
                continue
            out[package] = {
                "variant": row.get("variant", ""),
                "apk": row.get("apk", ""),
                "sha256": row.get("sha256", ""),
                "note": row.get("note", ""),
            }
    return out


def int_field(row: dict[str, str], key: str) -> int:
    try:
        return int(row.get(key, "") or 0)
    except ValueError:
        return 0


def package_index_by_name(rows: Iterable[dict[str, str]]) -> dict[str, dict[str, str]]:
    return {row["name"]: row for row in rows}


def rows_by_package(rows: Iterable[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    out: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        out[row.get("package", "")].append(row)
    return out


def status_for(row: dict[str, str]) -> tuple[str, str]:
    package = row.get("package", "")
    decoded_dir = row.get("decoded_dir", "")
    if package in REMOVED_BY_V02_V04:
        return "removed_in_v0.2_v0.4", "package hard-removed from current v0.4 baseline"
    if decoded_dir in PRUNED_BY_V010:
        return "pruned_in_v0.10_candidate", "resources.arsc hard-pruned in v0.10 candidate"
    if package in PRUNED_BY_V013_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.13_system_image",
            "resources.arsc hard-pruned in v0.13 Tier1a system_b image; flashable sparse super not built",
        )
    if package in PRUNED_BY_V017A_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.17a_system_image",
            "resources.arsc hard-pruned in v0.17a system_b image and flashable sparse super; not live-tested",
        )
    if package in PRUNED_BY_V017B_PRODUCT_SYSTEM_EXT_IMAGE:
        return (
            "pruned_in_v0.17b_product_system_ext_image",
            "resources.arsc hard-pruned in v0.17b product_b/system_ext_b image and flashable sparse super; not live-tested",
        )
    if package in PRUNED_BY_V022_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.22_all_system_image",
            "resources.arsc hard-pruned in v0.22 combined system_b image and flashable sparse super; not live-tested",
        )
    if package in PRUNED_BY_V024_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.24_system_image",
            "resources.arsc hard-pruned in v0.24 system_b image and flashable sparse super; not live-tested",
        )
    if package in VISIBLE_FILTER_ONLY_V07:
        return "visible_filter_only_v0.7", "Settings UI hides ja_JP/ko_KR but APK resources remain"
    return "remaining_after_v0.4_v0.10", "still needs delete, APK resource prune, or deeper gate"


def frontier_for(row: dict[str, str], status: str) -> str:
    if status != "remaining_after_v0.4_v0.10":
        return "covered_or_not_hard_pruned"
    risk = row.get("risk", "")
    package = row.get("package", "")
    ja_ko_dirs = int_field(row, "ja_ko_dirs")
    other_locale_dirs = int_field(row, "other_locale_dirs")

    if risk == "GREEN_OR_YELLOW_APP" and package not in DEFER_GREEN_PACKAGES and other_locale_dirs == 0:
        if ja_ko_dirs <= 4:
            return "tier1_small_green_apk_resource_prune"
        return "tier2_large_green_apk_resource_prune"
    if risk == "GREEN_OR_YELLOW_APP":
        return "defer_green_coupled_or_large_locale_table"
    if risk.startswith("AMBER_"):
        return "amber_requires_package_gate"
    return "red_requires_core_gate"


def tier1_gate_for(
    row: dict[str, str],
    package_row: dict[str, str],
    frontier: str,
    components_by_pkg: dict[str, list[dict[str, str]]],
    intents_by_pkg: dict[str, list[dict[str, str]]],
    permissions_by_pkg: dict[str, list[dict[str, str]]],
) -> tuple[str, int, dict[str, int]]:
    package = row.get("package", "")
    components = components_by_pkg.get(package, [])
    intents = intents_by_pkg.get(package, [])
    permissions = permissions_by_pkg.get(package, [])
    package_status = package_row.get("status", "")
    counts = {
        "component_count": len(components),
        "exported_component_count": sum(1 for item in components if item.get("exported") == "true"),
        "provider_count": sum(1 for item in components if item.get("type") == "provider"),
        "core_intent_count": sum(1 for item in intents if item.get("value") in CORE_INTENT_VALUES),
        "requested_permission_count": len(permissions),
        "package_status_problem": 1 if package_status and package_status != "ok" else 0,
    }
    if frontier != "tier1_small_green_apk_resource_prune":
        return "", 0, counts

    score = (
        counts["exported_component_count"] * 12
        + counts["provider_count"] * 10
        + counts["core_intent_count"] * 6
        + counts["requested_permission_count"]
        + counts["package_status_problem"] * 20
        + max(0, counts["component_count"] - 1)
    )
    if counts["package_status_problem"]:
        return "tier1c_needs_extra_package_review", score, counts
    if (
        counts["exported_component_count"] == 0
        and counts["provider_count"] == 0
        and counts["core_intent_count"] == 0
        and counts["component_count"] <= 1
        and counts["requested_permission_count"] <= 4
    ):
        return "tier1a_minimal_exposure", score, counts
    if (
        counts["exported_component_count"] == 0
        and counts["provider_count"] == 0
        and counts["core_intent_count"] == 0
    ):
        return "tier1b_low_exposure", score, counts
    return "tier1c_needs_extra_package_review", score, counts


def tier1_gate_reason(
    row: dict[str, str], package_row: dict[str, str], gate: str, counts: dict[str, int]
) -> str:
    if not gate:
        return ""
    reasons: list[str] = []
    if counts["package_status_problem"]:
        reasons.append(f"package-index status is {package_row.get('status') or 'not ok'}")
    if counts["exported_component_count"]:
        reasons.append(f"{counts['exported_component_count']} exported components")
    if counts["provider_count"]:
        reasons.append(f"{counts['provider_count']} providers")
    if counts["core_intent_count"]:
        reasons.append(f"{counts['core_intent_count']} core intent entries")
    if counts["requested_permission_count"] > 4:
        reasons.append(f"{counts['requested_permission_count']} requested permissions")
    if counts["component_count"] > 1:
        reasons.append(f"{counts['component_count']} components")
    if gate == "tier1b_low_exposure" and not reasons:
        reasons.append("low exposure but not minimal by static score")
    if gate == "tier1b_low_exposure":
        return "low-exposure review: " + "; ".join(reasons)
    return "extra review: " + "; ".join(reasons)


def enrich_rows(
    locale_rows: list[dict[str, str]],
    packages: dict[str, dict[str, str]],
    components_by_pkg: dict[str, list[dict[str, str]]],
    intents_by_pkg: dict[str, list[dict[str, str]]],
    permissions_by_pkg: dict[str, list[dict[str, str]]],
    apk_only_by_package: dict[str, dict[str, str]],
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for row in locale_rows:
        ja_ko_dirs = int_field(row, "ja_ko_dirs")
        if ja_ko_dirs <= 0:
            continue
        decoded_dir = row.get("decoded_dir", "")
        package_row = packages.get(decoded_dir, {})
        status, note = status_for(row)
        frontier = frontier_for(row, status)
        tier1_gate, tier1_score, gate_counts = tier1_gate_for(
            row, package_row, frontier, components_by_pkg, intents_by_pkg, permissions_by_pkg
        )
        out = dict(row)
        apk_only = apk_only_by_package.get(row.get("package", ""), {})
        out.update(
            {
                "coverage_status": status,
                "coverage_note": note,
                "apk_only_variant": apk_only.get("variant", ""),
                "apk_only_apk": apk_only.get("apk", ""),
                "apk_only_sha256": apk_only.get("sha256", ""),
                "apk_only_note": apk_only.get("note", ""),
                "next_frontier": frontier,
                "tier1_gate": tier1_gate,
                "tier1_gate_score": str(tier1_score),
                "tier1_gate_reason": tier1_gate_reason(row, package_row, tier1_gate, gate_counts),
                "component_count": str(gate_counts["component_count"]),
                "exported_component_count": str(gate_counts["exported_component_count"]),
                "provider_count": str(gate_counts["provider_count"]),
                "core_intent_count": str(gate_counts["core_intent_count"]),
                "requested_permission_count": str(gate_counts["requested_permission_count"]),
                "package_status_problem": str(gate_counts["package_status_problem"]),
                "partition": package_row.get("partition", ""),
                "rel_path": package_row.get("rel_path", ""),
                "apk_size": package_row.get("size", ""),
                "package_index_status": package_row.get("status", ""),
                "priv_app": package_row.get("priv_app", ""),
                "package_index_sharedUserId": package_row.get("sharedUserId", ""),
                "overlayTarget": package_row.get("overlayTarget", ""),
            }
        )
        rows.append(out)
    return rows


def write_tsv(rows: list[dict[str, str]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "coverage_status",
        "apk_only_variant",
        "apk_only_apk",
        "apk_only_sha256",
        "next_frontier",
        "tier1_gate",
        "tier1_gate_score",
        "tier1_gate_reason",
        "risk",
        "ja_ko_dirs",
        "other_locale_dirs",
        "component_count",
        "exported_component_count",
        "provider_count",
        "core_intent_count",
        "requested_permission_count",
        "package_status_problem",
        "package",
        "decoded_dir",
        "partition",
        "rel_path",
        "apk_size",
        "package_index_status",
        "sharedUserId",
        "coreApp",
        "priv_app",
        "targetPackage",
        "overlayTarget",
        "locales",
        "ja_ko_values_dirs",
        "apk_only_note",
        "coverage_note",
    ]
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fields, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def sum_dirs(rows: Iterable[dict[str, str]]) -> int:
    return sum(int_field(row, "ja_ko_dirs") for row in rows)


def count_rows(rows: Iterable[dict[str, str]]) -> int:
    return sum(1 for _ in rows)


def top_rows(rows: list[dict[str, str]], limit: int = 20) -> list[dict[str, str]]:
    return sorted(
        rows,
        key=lambda row: (
            row.get("next_frontier", ""),
            row.get("risk", ""),
            -int_field(row, "ja_ko_dirs"),
            row.get("package", ""),
        ),
    )[:limit]


def tier1_rows(rows: list[dict[str, str]], gate: str = "") -> list[dict[str, str]]:
    candidates = [row for row in rows if row["next_frontier"] == "tier1_small_green_apk_resource_prune"]
    if gate:
        candidates = [row for row in candidates if row.get("tier1_gate") == gate]
    return sorted(
        candidates,
        key=lambda row: (
            int_field(row, "tier1_gate_score"),
            int_field(row, "requested_permission_count"),
            int_field(row, "component_count"),
            row.get("package", ""),
        ),
    )


def tier1_best_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    order = {
        "tier1a_minimal_exposure": 0,
        "tier1b_low_exposure": 1,
        "tier1c_needs_extra_package_review": 2,
    }
    return sorted(
        [row for row in rows if row["next_frontier"] == "tier1_small_green_apk_resource_prune"],
        key=lambda row: (
            order.get(row.get("tier1_gate", ""), 99),
            int_field(row, "tier1_gate_score"),
            int_field(row, "requested_permission_count"),
            int_field(row, "component_count"),
            row.get("package", ""),
        ),
    )


def write_markdown(rows: list[dict[str, str]], tsv: Path, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    by_status: dict[str, list[dict[str, str]]] = defaultdict(list)
    by_frontier: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_status[row["coverage_status"]].append(row)
        by_frontier[row["next_frontier"]].append(row)

    stock_packages = len(rows)
    stock_dirs = sum_dirs(rows)
    covered_statuses = {
        "removed_in_v0.2_v0.4",
        "pruned_in_v0.10_candidate",
        "pruned_in_v0.13_system_image",
        "pruned_in_v0.17a_system_image",
        "pruned_in_v0.17b_product_system_ext_image",
        "pruned_in_v0.22_all_system_image",
        "pruned_in_v0.24_system_image",
    }
    covered_rows = [row for row in rows if row["coverage_status"] in covered_statuses]
    remaining_rows = [row for row in rows if row["coverage_status"] == "remaining_after_v0.4_v0.10"]
    visible_only_rows = [row for row in rows if row["coverage_status"] == "visible_filter_only_v0.7"]
    apk_only_rows = [
        row
        for row in rows
        if row.get("apk_only_variant") and row["coverage_status"] == "remaining_after_v0.4_v0.10"
    ]
    v013_rows = by_status.get("pruned_in_v0.13_system_image", [])
    tier1 = by_frontier.get("tier1_small_green_apk_resource_prune", [])

    lines = [
        "# Locale Prune Coverage Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit measures Japanese/Korean locale-resource coverage",
        "against the current hard-ROM route. It does not modify APKs, images,",
        "partitions, the live device, or `/data`.",
        "",
        "## Scope Boundary",
        "",
        "- Baseline removal state: v0.2 no-appstore plus v0.4 hard debloat.",
        "- Resource hard-prune coverage: v0.10 framework/product candidate,",
        "  v0.13 Tier1a system_b image candidate, v0.17a system APK-only",
        "  promotion image candidate, and v0.17b product/system_ext APK-only",
        "  promotion image candidate.",
        "- v0.13 is counted as system-image coverage only; its flashable sparse",
        "  super has not been built or live-tested. v0.17a has a flashable",
        "  sparse super but still has not been live-tested. v0.17b, v0.22, and v0.24",
        "  also have flashable sparse supers but still have not been live-tested.",
        "- Remaining APK-only locale-prune outputs are listed as offline evidence",
        "  but are not counted as ROM hard-prune coverage until a matching image exists.",
        "- Visible language filtering: v0.7 SettingsSmartisan candidate, counted",
        "  separately because it does not remove APK resources.",
        f"- TSV output: `{tsv}`",
        "",
        "## Summary",
        "",
        f"- stock static ROM packages with ja/ko resources: {stock_packages}",
        f"- stock ja/ko values-dir count: {stock_dirs}",
        f"- covered by deletion or v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 hard-prune candidates: {len(covered_rows)} packages, {sum_dirs(covered_rows)} dirs",
        f"- visible-filter only, not resource-pruned: {len(visible_only_rows)} packages, {sum_dirs(visible_only_rows)} dirs",
        f"- remaining APK-only built offline, not in ROM coverage: {len(apk_only_rows)} packages, {sum_dirs(apk_only_rows)} dirs",
        f"- remaining hard-prune work: {len(remaining_rows)} packages, {sum_dirs(remaining_rows)} dirs",
        "",
        "Coverage by status:",
        "",
    ]
    for status, group in sorted(by_status.items()):
        lines.append(f"- {status}: {len(group)} packages, {sum_dirs(group)} dirs")

    if v013_rows:
        lines.extend(
            [
                "",
                "v0.13 system-image hard-prune batch:",
                "",
                "| ja/ko dirs | package | path | status |",
                "| ---: | --- | --- | --- |",
            ]
        )
        for row in sorted(v013_rows, key=lambda r: r.get("package", "")):
            lines.append(
                f"| {row['ja_ko_dirs']} | {row['package']} | `{row.get('partition','')}/{row.get('rel_path','')}` | {row['coverage_note']} |"
            )

    if apk_only_rows:
        lines.extend(
            [
                "",
                "APK-only offline candidates, not counted as ROM coverage:",
                "",
                "| ja/ko dirs | package | variant | APK | sha256 | note |",
                "| ---: | --- | --- | --- | --- | --- |",
            ]
        )
        for row in sorted(apk_only_rows, key=lambda r: r.get("package", "")):
            lines.append(
                f"| {row['ja_ko_dirs']} | {row['package']} | `{row.get('apk_only_variant','')}` | `{row.get('apk_only_apk','')}` | `{row.get('apk_only_sha256','')}` | {row.get('apk_only_note','')} |"
            )

    lines.extend(["", "Remaining work by risk tier:", ""])
    risk_counts = Counter(row["risk"] for row in remaining_rows)
    for risk, count in sorted(risk_counts.items()):
        dirs = sum_dirs(row for row in remaining_rows if row["risk"] == risk)
        lines.append(f"- {risk}: {count} packages, {dirs} dirs")

    lines.extend(["", "Remaining work by next frontier:", ""])
    for frontier, group in sorted(by_frontier.items()):
        if frontier == "covered_or_not_hard_pruned":
            continue
        lines.append(f"- {frontier}: {len(group)} packages, {sum_dirs(group)} dirs")

    lines.extend(["", "Tier1 package-gate split:", ""])
    tier1_gate_counts = Counter(row.get("tier1_gate", "") for row in tier1 if row.get("tier1_gate"))
    for gate, count in sorted(tier1_gate_counts.items()):
        group = [row for row in tier1 if row.get("tier1_gate") == gate]
        lines.append(f"- {gate}: {count} packages, {sum_dirs(group)} dirs")

    lines.extend(
        [
            "",
            "## Next Safe Frontier",
            "",
            "The safest next offline frontier is small GREEN/YELLOW APK resource",
            "pruning, not core shared-UID or framework work. These are APK-level",
            "resources.arsc candidates only; a built APK still does not authorize",
            "flashing.",
            "",
            "| ja/ko dirs | package | path | note |",
            "| ---: | --- | --- | --- |",
        ]
    )
    for row in sorted(tier1, key=lambda r: (-int_field(r, "ja_ko_dirs"), r.get("package", "")))[:25]:
        lines.append(
            f"| {row['ja_ko_dirs']} | {row['package']} | `{row.get('partition','')}/{row.get('rel_path','')}` | {row['coverage_note']} |"
        )

    lines.extend(
        [
            "",
            "## Best First APK Resource-Prune Probes",
            "",
            "These candidates are still same-package APK replacements, so they are",
            "offline probes until a ROM image and flash are explicitly authorized.",
            "The v0.13 batch consumed the last `tier1a_minimal_exposure` packages,",
            "so the next safe frontier is review-gated rather than fully automatic.",
            "",
            "| gate | score | ja/ko dirs | package | components | exported | providers | core intents | permissions | reason | path |",
            "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |",
        ]
    )
    for row in tier1_best_rows(rows)[:12]:
        lines.append(
            f"| {row['tier1_gate']} | {row['tier1_gate_score']} | {row['ja_ko_dirs']} | {row['package']} | {row['component_count']} | {row['exported_component_count']} | {row['provider_count']} | {row['core_intent_count']} | {row['requested_permission_count']} | {row.get('tier1_gate_reason','')} | `{row.get('partition','')}/{row.get('rel_path','')}` |"
        )

    if apk_only_rows:
        lines.extend(
            [
                "",
                "Current APK-only offline probes:",
                "",
                "| package | variant | gate | reason | APK | sha256 |",
                "| --- | --- | --- | --- | --- | --- |",
            ]
        )
        for row in sorted(apk_only_rows, key=lambda r: r.get("package", "")):
            lines.append(
                f"| `{row['package']}` | `{row.get('apk_only_variant','')}` | `{row.get('tier1_gate','')}` | {row.get('tier1_gate_reason','')} | `{row.get('apk_only_apk','')}` | `{row.get('apk_only_sha256','')}` |"
            )
        lines.extend(
            [
                "",
                "Boundary: these are APK-level resources.arsc prune probes only.",
                "classes.dex and AndroidManifest.xml must remain byte-identical.",
                "No APK-only output authorizes a ROM image or flash by itself.",
            ]
        )

    lines.extend(
        [
            "",
            "## Important Deferrals",
            "",
            "- `visible_filter_only_v0.7` is not counted as hard-pruned. It proves the",
            "  Settings language picker can hide ja/ko, but resources remain in the APK.",
            "- Browser/WebView/input/launcher/security-adjacent packages are deferred even",
            "  if their static risk label is GREEN/YELLOW.",
            "- AMBER packages need package-level gates before build.",
            "- RED packages need core shared-UID/framework live gates before behavior or",
            "  resource replacement.",
            "",
            "## Top Remaining Packages",
            "",
            "| frontier | risk | ja/ko dirs | package | path |",
            "| --- | --- | ---: | --- | --- |",
        ]
    )
    for row in top_rows(remaining_rows, 40):
        lines.append(
            f"| {row['next_frontier']} | {row['risk']} | {row['ja_ko_dirs']} | {row['package']} | `{row.get('partition','')}/{row.get('rel_path','')}` |"
        )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    locale_rows = read_tsv(Path(args.locale_inventory))
    package_rows = read_tsv(Path(args.package_index))
    component_rows = read_tsv(Path(args.component_index))
    intent_rows = read_tsv(Path(args.intent_index))
    permission_rows = read_tsv(Path(args.permission_index))
    apk_only_rows = read_apk_only_manifest(Path(args.apk_only_manifest))
    enriched = enrich_rows(
        locale_rows,
        package_index_by_name(package_rows),
        rows_by_package(component_rows),
        rows_by_package(intent_rows),
        rows_by_package(permission_rows),
        apk_only_rows,
    )
    out_tsv = Path(args.out_tsv)
    out_md = Path(args.markdown)
    write_tsv(enriched, out_tsv)
    write_markdown(enriched, out_tsv, out_md)
    print(f"ja_ko_packages={len(enriched)}")
    print(f"ja_ko_dirs={sum_dirs(enriched)}")
    print(f"tsv={out_tsv}")
    print(f"markdown={out_md}")


if __name__ == "__main__":
    main()
