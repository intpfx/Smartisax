#!/usr/bin/env python3
"""Audit full English/Chinese-only ROM language-resource coverage.

This read-only audit measures the user's real target: keep English and Chinese
resource configurations, and physically remove every other compiled language
configuration from ROM packages. It complements the older ja/ko-focused audit.
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
DECODED_RES_ROOT = ROOT / "reverse/smartisan-8.5.3-rom-static/jadx"

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
    parser = argparse.ArgumentParser(description=__doc__)
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
        "--apk-only-manifest",
        default="hard-rom/build/apk/locale-prune-apk-only-manifest.tsv",
    )
    parser.add_argument(
        "--out-tsv",
        default="reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv",
    )
    parser.add_argument(
        "--markdown",
        default="docs/research/language-full-prune-coverage-audit.md",
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


def locale_from_res_dir(name: str) -> tuple[str, str | None] | None:
    if "-" not in name:
        return None
    parts = name.split("-")[1:]
    for index, part in enumerate(parts):
        if part.startswith("b+"):
            tags = part.split("+")
            if len(tags) > 1 and re.fullmatch(r"[a-z]{2,3}", tags[1]):
                return tags[1], None
        if not re.fullmatch(r"[a-z]{2}", part):
            continue
        region = None
        if index + 1 < len(parts) and re.fullmatch(r"r[A-Z]{2}", parts[index + 1]):
            region = parts[index + 1][1:]
        return part, region
    return None


def locale_label(lang: str, region: str | None) -> str:
    return f"{lang}_{region}" if region else lang


def scan_res_locale_dirs(row: dict[str, str]) -> dict[str, str]:
    decoded_dir = row.get("decoded_dir", "")
    res_dir = DECODED_RES_ROOT / decoded_dir / "resources/res"
    if not decoded_dir or not res_dir.is_dir():
        total = int_field(row, "ja_ko_dirs") + int_field(row, "other_locale_dirs")
        return {
            "non_target_dirs": str(total),
            "ja_ko_dirs": row.get("ja_ko_dirs", "0") or "0",
            "other_locale_dirs": row.get("other_locale_dirs", "0") or "0",
            "locale_dirs": row.get("locale_dirs", "0") or "0",
            "keep_dirs": row.get("keep_dirs", "0") or "0",
            "locales": row.get("locales", ""),
            "ja_ko_values_dirs": row.get("ja_ko_values_dirs", ""),
            "non_target_values_dirs": row.get("ja_ko_values_dirs", ""),
        }

    locale_dirs: list[tuple[str, str, str | None]] = []
    keep_dirs: list[str] = []
    ja_ko_dirs: list[str] = []
    other_dirs: list[str] = []
    locales: set[str] = set()
    for child in sorted(res_dir.iterdir(), key=lambda path: path.name):
        if not child.is_dir():
            continue
        parsed = locale_from_res_dir(child.name)
        if parsed is None:
            continue
        lang, region = parsed
        locale_dirs.append((child.name, lang, region))
        locales.add(locale_label(lang, region))
        if lang in {"en", "zh"}:
            keep_dirs.append(child.name)
        elif lang in {"ja", "ko"}:
            ja_ko_dirs.append(child.name)
        else:
            other_dirs.append(child.name)

    non_target = ja_ko_dirs + other_dirs
    return {
        "non_target_dirs": str(len(non_target)),
        "ja_ko_dirs": str(len(ja_ko_dirs)),
        "other_locale_dirs": str(len(other_dirs)),
        "locale_dirs": str(len(locale_dirs)),
        "keep_dirs": str(len(keep_dirs)),
        "locales": ",".join(sorted(locales)),
        "ja_ko_values_dirs": ",".join(ja_ko_dirs),
        "non_target_values_dirs": ",".join(non_target),
    }


def rows_by_package(rows: Iterable[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    out: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        out[row.get("package", "")].append(row)
    return out


def package_index_by_name(rows: Iterable[dict[str, str]]) -> dict[str, dict[str, str]]:
    return {row["name"]: row for row in rows}


def status_for(row: dict[str, str]) -> tuple[str, str]:
    package = row.get("package", "")
    decoded_dir = row.get("decoded_dir", "")
    if package in REMOVED_BY_V02_V04:
        return "removed_in_v0.2_v0.4", "package hard-removed from current v0.4 baseline"
    if decoded_dir in PRUNED_BY_V010:
        return "pruned_in_v0.10_candidate", "non-English/non-Chinese resources hard-pruned in v0.10 candidate"
    if package in PRUNED_BY_V013_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.13_system_image",
            "non-English/non-Chinese resources hard-pruned in v0.13 Tier1a system_b image; flashable sparse super not built",
        )
    if package in PRUNED_BY_V017A_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.17a_system_image",
            "non-English/non-Chinese resources hard-pruned in v0.17a system_b image and flashable sparse super; not live-tested",
        )
    if package in PRUNED_BY_V017B_PRODUCT_SYSTEM_EXT_IMAGE:
        return (
            "pruned_in_v0.17b_product_system_ext_image",
            "non-English/non-Chinese resources hard-pruned in v0.17b product_b/system_ext_b image and flashable sparse super; not live-tested",
        )
    if package in PRUNED_BY_V022_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.22_all_system_image",
            "non-English/non-Chinese resources hard-pruned in v0.22 combined system_b image and flashable sparse super; not live-tested",
        )
    if package in PRUNED_BY_V024_SYSTEM_IMAGE:
        return (
            "pruned_in_v0.24_system_image",
            "non-English/non-Chinese resources hard-pruned in v0.24 system_b image and flashable sparse super; not live-tested",
        )
    if package in VISIBLE_FILTER_ONLY_V07:
        return "visible_filter_only_v0.7", "Settings UI hides ja_JP/ko_KR but package resources remain"
    return "remaining_after_current_candidates", "still needs delete, APK resource prune, or deeper gate"


def non_target_dirs(row: dict[str, str]) -> int:
    return int_field(row, "ja_ko_dirs") + int_field(row, "other_locale_dirs")


def frontier_for(row: dict[str, str], status: str) -> str:
    if status != "remaining_after_current_candidates":
        return "covered_or_not_hard_pruned"
    risk = row.get("risk", "")
    package = row.get("package", "")
    total = non_target_dirs(row)
    other_dirs = int_field(row, "other_locale_dirs")

    if risk == "GREEN_OR_YELLOW_APP" and package not in DEFER_GREEN_PACKAGES:
        if total <= 4 and other_dirs == 0:
            return "tier1_small_green_apk_resource_prune"
        return "tier2_green_full_language_prune"
    if risk == "GREEN_OR_YELLOW_APP":
        return "defer_green_coupled_or_large_locale_table"
    if risk.startswith("AMBER_"):
        return "amber_requires_package_gate"
    return "red_requires_core_gate"


def exposure_counts(
    package: str,
    components_by_pkg: dict[str, list[dict[str, str]]],
    intents_by_pkg: dict[str, list[dict[str, str]]],
    permissions_by_pkg: dict[str, list[dict[str, str]]],
    package_row: dict[str, str],
) -> dict[str, int]:
    components = components_by_pkg.get(package, [])
    intents = intents_by_pkg.get(package, [])
    permissions = permissions_by_pkg.get(package, [])
    package_status = package_row.get("status", "")
    return {
        "component_count": len(components),
        "exported_component_count": sum(1 for item in components if item.get("exported") == "true"),
        "provider_count": sum(1 for item in components if item.get("type") == "provider"),
        "core_intent_count": sum(1 for item in intents if item.get("value") in CORE_INTENT_VALUES),
        "requested_permission_count": len(permissions),
        "package_status_problem": 1 if package_status and package_status != "ok" else 0,
    }


def exposure_score(counts: dict[str, int]) -> int:
    return (
        counts["exported_component_count"] * 12
        + counts["provider_count"] * 10
        + counts["core_intent_count"] * 6
        + counts["requested_permission_count"]
        + counts["package_status_problem"] * 20
        + max(0, counts["component_count"] - 1)
    )


def tier_gate(frontier: str, counts: dict[str, int]) -> str:
    if frontier not in {"tier1_small_green_apk_resource_prune", "tier2_green_full_language_prune"}:
        return ""
    if counts["package_status_problem"]:
        return "needs_extra_package_review"
    if (
        counts["exported_component_count"] == 0
        and counts["provider_count"] == 0
        and counts["core_intent_count"] == 0
        and counts["component_count"] <= 1
        and counts["requested_permission_count"] <= 4
    ):
        return "minimal_exposure"
    if (
        counts["exported_component_count"] == 0
        and counts["provider_count"] == 0
        and counts["core_intent_count"] == 0
    ):
        return "low_exposure"
    return "needs_extra_package_review"


def gate_reason(counts: dict[str, int], package_row: dict[str, str]) -> str:
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
    return "; ".join(reasons)


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
        locale_scan = scan_res_locale_dirs(row)
        total = int_field(locale_scan, "non_target_dirs")
        if total <= 0:
            continue
        scanned_row = dict(row)
        scanned_row.update(locale_scan)
        decoded_dir = row.get("decoded_dir", "")
        package = row.get("package", "")
        package_row = packages.get(decoded_dir, {})
        status, note = status_for(row)
        frontier = frontier_for(scanned_row, status)
        counts = exposure_counts(package, components_by_pkg, intents_by_pkg, permissions_by_pkg, package_row)
        gate = tier_gate(frontier, counts)
        apk_only = apk_only_by_package.get(package, {})
        out = scanned_row
        out.update(
            {
                "coverage_status": status,
                "coverage_note": note,
                "apk_only_variant": apk_only.get("variant", ""),
                "apk_only_apk": apk_only.get("apk", ""),
                "apk_only_sha256": apk_only.get("sha256", ""),
                "apk_only_note": apk_only.get("note", ""),
                "next_frontier": frontier,
                "exposure_gate": gate,
                "exposure_score": str(exposure_score(counts)),
                "exposure_reason": gate_reason(counts, package_row),
                "component_count": str(counts["component_count"]),
                "exported_component_count": str(counts["exported_component_count"]),
                "provider_count": str(counts["provider_count"]),
                "core_intent_count": str(counts["core_intent_count"]),
                "requested_permission_count": str(counts["requested_permission_count"]),
                "package_status_problem": str(counts["package_status_problem"]),
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


def sum_field(rows: Iterable[dict[str, str]], field: str) -> int:
    return sum(int_field(row, field) for row in rows)


def write_tsv(rows: list[dict[str, str]], path: Path) -> None:
    fields = [
        "coverage_status",
        "next_frontier",
        "exposure_gate",
        "exposure_score",
        "risk",
        "non_target_dirs",
        "ja_ko_dirs",
        "other_locale_dirs",
        "locale_dirs",
        "keep_dirs",
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
        "non_target_values_dirs",
        "apk_only_variant",
        "apk_only_apk",
        "apk_only_sha256",
        "apk_only_note",
        "coverage_note",
        "exposure_reason",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fields, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def md_table(rows: list[dict[str, str]], columns: list[str]) -> list[str]:
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    for row in rows:
        values = []
        for col in columns:
            value = (row.get(col, "") or "").replace("|", "\\|").replace("\n", " ")
            if col in {"rel_path", "apk_only_apk"} and value:
                value = f"`{value}`"
            values.append(value)
        lines.append("| " + " | ".join(values) + " |")
    return lines


def top_remaining(rows: list[dict[str, str]], limit: int = 30) -> list[dict[str, str]]:
    remaining = [row for row in rows if row["coverage_status"] == "remaining_after_current_candidates"]
    return sorted(remaining, key=lambda row: (-int_field(row, "non_target_dirs"), row.get("package", "")))[:limit]


def best_frontier(rows: list[dict[str, str]], frontier: str, limit: int = 25) -> list[dict[str, str]]:
    targets = [row for row in rows if row["next_frontier"] == frontier]
    return sorted(
        targets,
        key=lambda row: (
            int_field(row, "exposure_score"),
            -int_field(row, "non_target_dirs"),
            row.get("package", ""),
        ),
    )[:limit]


def write_markdown(rows: list[dict[str, str]], tsv: Path, path: Path) -> None:
    by_status: dict[str, list[dict[str, str]]] = defaultdict(list)
    by_frontier: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_status[row["coverage_status"]].append(row)
        by_frontier[row["next_frontier"]].append(row)

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
    remaining_rows = [row for row in rows if row["coverage_status"] == "remaining_after_current_candidates"]
    visible_only_rows = [row for row in rows if row["coverage_status"] == "visible_filter_only_v0.7"]
    apk_only_rows = [
        row
        for row in rows
        if row.get("apk_only_variant") and row["coverage_status"] == "remaining_after_current_candidates"
    ]

    lines = [
        "# Full English/Chinese Language Prune Coverage Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit measures the full ROM language-prune target:",
        "keep `en*` and `zh*` resource configurations and remove every other",
        "compiled language configuration. It does not modify APKs, images,",
        "partitions, the live device, or `/data`.",
        "",
        "## Scope Boundary",
        "",
        "- This is stricter than the older ja/ko coverage audit.",
        "- `non_target_dirs = ja_ko_dirs + other_locale_dirs`, recomputed by scanning decoded resource directories.",
        "- v0.10, v0.13, v0.17a, v0.17b, v0.22, and v0.24 are counted as offline image candidates, not live proof.",
        "- Remaining APK-only candidates are listed but not counted as ROM coverage until promoted.",
        f"- TSV output: `{tsv}`",
        "",
        "## Summary",
        "",
        f"- stock static ROM packages with non-English/non-Chinese resources: {len(rows)}",
        f"- stock non-English/non-Chinese values-dir count: {sum_field(rows, 'non_target_dirs')}",
        f"- ja/ko subset: {sum_field(rows, 'ja_ko_dirs')} dirs",
        f"- other non-target languages: {sum_field(rows, 'other_locale_dirs')} dirs",
        f"- covered by deletion or v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 hard-prune candidates: {len(covered_rows)} packages, {sum_field(covered_rows, 'non_target_dirs')} dirs",
        f"- visible-filter only, not resource-pruned: {len(visible_only_rows)} packages, {sum_field(visible_only_rows, 'non_target_dirs')} dirs",
        f"- remaining APK-only built offline, not in ROM coverage: {len(apk_only_rows)} packages, {sum_field(apk_only_rows, 'non_target_dirs')} dirs",
        f"- remaining full language-prune work: {len(remaining_rows)} packages, {sum_field(remaining_rows, 'non_target_dirs')} dirs",
        "",
        "Coverage by status:",
        "",
    ]
    for status, group in sorted(by_status.items()):
        lines.append(f"- {status}: {len(group)} packages, {sum_field(group, 'non_target_dirs')} dirs")

    lines.extend(["", "Remaining work by next frontier:", ""])
    for frontier, group in sorted(by_frontier.items()):
        if frontier == "covered_or_not_hard_pruned":
            continue
        lines.append(f"- {frontier}: {len(group)} packages, {sum_field(group, 'non_target_dirs')} dirs")

    lines.extend(
        [
            "",
            "## Important Result",
            "",
            "The current ROM language work is not close to full English/Chinese-only",
            "physical pruning yet. The ja/ko subset is only a small part of the real",
            "target. Large non-target language tables remain in apps such as Contacts,",
            "BrowserChrome, TalkBack, Calendar, LatinIME, SettingsSmartisan, Launcher,",
            "and many OEM apps. Those packages need separate risk gates.",
            "",
            "## Best Full-Language Green Frontiers",
            "",
            "These are GREEN/YELLOW packages that are not on the known deferral list.",
            "They are ranked by low exposure score first, then by larger non-target",
            "directory removal. They still need package-specific review and ROM image",
            "promotion before any flash.",
            "",
            *md_table(
                best_frontier(rows, "tier2_green_full_language_prune"),
                [
                    "exposure_gate",
                    "exposure_score",
                    "non_target_dirs",
                    "ja_ko_dirs",
                    "other_locale_dirs",
                    "package",
                    "partition",
                    "rel_path",
                    "exposure_reason",
                ],
            ),
            "",
            "## APK-Only Offline Candidates",
            "",
            *md_table(
                sorted(apk_only_rows, key=lambda row: row.get("package", "")),
                [
                    "non_target_dirs",
                    "package",
                    "apk_only_variant",
                    "apk_only_apk",
                    "apk_only_sha256",
                    "coverage_note",
                ],
            ),
            "",
            "## Top Remaining Packages",
            "",
            *md_table(
                top_remaining(rows, 40),
                [
                    "next_frontier",
                    "risk",
                    "non_target_dirs",
                    "ja_ko_dirs",
                    "other_locale_dirs",
                    "package",
                    "partition",
                    "rel_path",
                ],
            ),
            "",
            "## Deferrals",
            "",
            "- SettingsSmartisan remains a core shared-UID Settings gate, even for resource-only language work.",
            "- Framework assets remain behind v0.12/v0.10 live framework gates.",
            "- Keyboard, Browser/WebView, Launcher, Keyguard, phone, permission, provider, and APEX packages need focused gates.",
            "- Remaining APK-only outputs prove resource surgery but not ROM boot behavior.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    locale_rows = read_tsv(Path(args.locale_inventory))
    packages = package_index_by_name(read_tsv(Path(args.package_index)))
    components_by_pkg = rows_by_package(read_tsv(Path(args.component_index)))
    intents_by_pkg = rows_by_package(read_tsv(Path(args.intent_index)))
    permissions_by_pkg = rows_by_package(read_tsv(Path(args.permission_index)))
    apk_only_by_package = read_apk_only_manifest(Path(args.apk_only_manifest))
    rows = enrich_rows(
        locale_rows,
        packages,
        components_by_pkg,
        intents_by_pkg,
        permissions_by_pkg,
        apk_only_by_package,
    )
    out_tsv = Path(args.out_tsv)
    out_md = Path(args.markdown)
    write_tsv(rows, out_tsv)
    write_markdown(rows, out_tsv, out_md)

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
    remaining_rows = [row for row in rows if row["coverage_status"] == "remaining_after_current_candidates"]
    print(f"non_target_packages={len(rows)}")
    print(f"non_target_dirs={sum_field(rows, 'non_target_dirs')}")
    print(f"ja_ko_dirs={sum_field(rows, 'ja_ko_dirs')}")
    print(f"other_locale_dirs={sum_field(rows, 'other_locale_dirs')}")
    print(f"covered_packages={len(covered_rows)}")
    print(f"covered_non_target_dirs={sum_field(covered_rows, 'non_target_dirs')}")
    print(f"remaining_packages={len(remaining_rows)}")
    print(f"remaining_non_target_dirs={sum_field(remaining_rows, 'non_target_dirs')}")
    print(f"tsv={out_tsv}")
    print(f"markdown={out_md}")


if __name__ == "__main__":
    main()
