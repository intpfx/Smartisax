#!/usr/bin/env python3
"""Review P1 language-prune APK candidates from static ROM sources.

This script is read-only. It consumes the staged language next-batch plan and
the static ROM knowledge-base indexes, then ranks the P1 small APK-only
candidates by manifest exposure and source-level locale/resource coupling.
"""

from __future__ import annotations

import csv
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse/smartisan-8.5.3-rom-static"
JADX = KB / "jadx"
PLAN_TSV = KB / "manifest/language-next-batch-plan.tsv"
FULL_COVERAGE_TSV = KB / "manifest/language-full-prune-coverage-audit.tsv"
OUT_TSV = KB / "manifest/language-p1-source-review-audit.tsv"
OUT_MD = ROOT / "docs/research/language-p1-source-review-audit.md"

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

SOURCE_MARKERS: dict[str, tuple[str, ...]] = {
    "direct_asset_locale_api": (
        "getAssets().getLocales",
        ".getLocales()",
        "getLocales(",
    ),
    "locale_runtime_api": (
        "Locale.getDefault",
        "LocaleList",
        "getConfiguration().locale",
        "getConfiguration().getLocales",
        "onConfigurationChanged",
    ),
    "locale_change_event": (
        "LOCALE_CHANGED",
        "ACTION_LOCALE_CHANGED",
    ),
    "telephony_carrier_api": (
        "CarrierConfigManager",
        "TelephonyManager",
        "SubscriptionManager",
        "EuiccManager",
        "MccTable",
        "IccRecords",
        "Uicc",
    ),
    "dynamic_resource_lookup": (
        "Resources.getSystem",
        "createPackageContext(",
        "getIdentifier(",
        "AssetManager",
    ),
}

LIBRARY_SOURCE_PATH_PARTS = (
    "/android/support/",
    "/androidx/",
    "/com/android/setupwizardlib/",
    "/com/alibaba/fastjson/",
    "/com/bumptech/",
    "/com/google/",
    "/com/subao/",
    "/com/tencent/",
    "/okhttp3/",
    "/okio/",
    "/org/apache/",
    "/org/json/",
    "/kotlin/",
)


@dataclass(frozen=True)
class ReviewRow:
    package: str
    verdict: str
    manifest_gate: str
    source_gate: str
    partition: str
    rel_path: str
    decoded_dir: str
    exposure_score: int
    non_target_dirs: int
    ja_ko_dirs: int
    other_locale_dirs: int
    apk_size: int
    package_index_status: str
    component_count: int
    exported_component_count: int
    provider_count: int
    core_intent_count: int
    requested_permission_count: int
    sysconfig_refs: int
    privapp_permission_refs: int
    overlay_refs: int
    source_file_count: int
    library_source_marker_hits: int
    direct_asset_locale_api: int
    locale_runtime_api: int
    locale_change_event: int
    telephony_carrier_api: int
    dynamic_resource_lookup: int
    source_examples: str
    blockers: str
    next_step: str


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def int_field(row: dict[str, str], key: str) -> int:
    try:
        return int(row.get(key, "") or 0)
    except ValueError:
        return 0


def rows_by(rows: list[dict[str, str]], key: str) -> dict[str, list[dict[str, str]]]:
    out: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        out[row.get(key, "")].append(row)
    return out


def load_indexes() -> dict[str, list[dict[str, str]]]:
    indexes = KB / "indexes"
    return {
        "components": read_tsv(indexes / "components.tsv"),
        "intent_filters": read_tsv(indexes / "intent-filters.tsv"),
        "uses_permissions": read_tsv(indexes / "uses-permissions.tsv"),
        "privapp_permissions": read_tsv(indexes / "privapp-permissions.tsv"),
        "sysconfig_packages": read_tsv(indexes / "sysconfig-packages.tsv"),
        "overlays": read_tsv(indexes / "overlays.tsv"),
    }


def source_files(decoded_dir: str) -> list[Path]:
    base = JADX / decoded_dir / "sources"
    if not base.is_dir():
        return []
    return sorted(
        path
        for path in base.rglob("*")
        if path.is_file() and path.suffix in {".java", ".kt"}
    )


def is_library_source(path: Path) -> bool:
    try:
        text = "/" + str(path.relative_to(JADX))
    except ValueError:
        text = str(path)
    return any(part in text for part in LIBRARY_SOURCE_PATH_PARTS)


def marker_hits(decoded_dir: str) -> tuple[Counter[str], int, list[str], int]:
    counts: Counter[str] = Counter()
    library_hits = 0
    examples: list[str] = []
    files = source_files(decoded_dir)
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line_no, line in enumerate(lines, 1):
            for category, patterns in SOURCE_MARKERS.items():
                if any(pattern in line for pattern in patterns):
                    if is_library_source(path):
                        library_hits += 1
                    else:
                        counts[category] += 1
                    if len(examples) < 8 and not is_library_source(path):
                        rel_path = path.relative_to(ROOT)
                        examples.append(f"{category}:{rel_path}:{line_no}")
    return counts, library_hits, examples, len(files)


def compact(items: list[str]) -> str:
    return "; ".join(item for item in items if item)


def manifest_gate(blockers: list[str], exposure_score: int, status: str) -> str:
    high_markers = (
        "provider",
        "core intent",
        "telephony/carrier",
        "high exposure",
        "package-index",
    )
    if exposure_score >= 90 or status != "ok" or any(any(marker in item for marker in high_markers) for item in blockers):
        return "HIGH_REVIEW"
    if blockers:
        return "MEDIUM_REVIEW"
    return "LOW"


def source_gate(counts: Counter[str], decoded_dir: str) -> str:
    if not decoded_dir:
        return "MISSING_DECODED_DIR"
    if counts["direct_asset_locale_api"] or counts["locale_change_event"] or counts["telephony_carrier_api"]:
        return "FOCUSED_REVIEW"
    if counts["locale_runtime_api"] or counts["dynamic_resource_lookup"]:
        return "LIGHT_REVIEW"
    return "NO_DIRECT_SOURCE_COUPLING_FOUND"


def verdict_for(gate: str, source: str, blockers: list[str], exposure_score: int) -> str:
    if gate == "LOW" and source in {"NO_DIRECT_SOURCE_COUPLING_FOUND", "LIGHT_REVIEW"}:
        return "P1a_lowest_risk_apk_only_reviewed"
    if exposure_score >= 90 or gate == "HIGH_REVIEW" or source in {"FOCUSED_REVIEW", "MISSING_DECODED_DIR"}:
        return "P1c_defer_focused_package_review"
    return "P1b_apk_only_after_focused_review"


def next_step_for(package: str, verdict: str) -> str:
    if verdict == "P1a_lowest_risk_apk_only_reviewed":
        return (
            f"tools/r2-rom-mod-preflight.py {package} --action replace && "
            f"tools/r2-build-apk-locale-prune.sh --package {package} "
            "--apk-only-variant <next-p1a-variant> "
            "--apk-only-note 'P1a source-reviewed APK-only language prune; not in ROM image'"
        )
    if verdict == "P1b_apk_only_after_focused_review":
        return "finish focused source note for blockers, then build APK-only candidate if the review stays narrow"
    return "defer from the next APK-only mini-batch until package-specific source/graph review is complete"


def build_rows() -> list[ReviewRow]:
    plan_rows = [row for row in read_tsv(PLAN_TSV) if row.get("batch") == "P1_build_small_apk_only"]
    coverage_by_package = {row.get("package", ""): row for row in read_tsv(FULL_COVERAGE_TSV)}
    indexes = load_indexes()
    components = rows_by(indexes["components"], "package")
    intents = rows_by(indexes["intent_filters"], "package")
    permissions = rows_by(indexes["uses_permissions"], "package")
    privapp_permissions = rows_by(indexes["privapp_permissions"], "package")
    sysconfig = rows_by(indexes["sysconfig_packages"], "package")
    overlays_by_package = rows_by(indexes["overlays"], "package")
    overlays_by_target = rows_by(indexes["overlays"], "targetPackage")

    out: list[ReviewRow] = []
    for plan in plan_rows:
        package = plan.get("package", "")
        coverage = coverage_by_package.get(package, {})
        decoded_dir = coverage.get("decoded_dir", "")
        comp_rows = components.get(package, [])
        intent_rows = intents.get(package, [])
        permission_rows = permissions.get(package, [])
        sysconfig_rows = sysconfig.get(package, [])
        privapp_rows = privapp_permissions.get(package, [])
        overlay_refs = overlays_by_package.get(package, []) + overlays_by_target.get(package, [])
        core_intents = [row for row in intent_rows if row.get("value") in CORE_INTENT_VALUES]
        provider_rows = [row for row in comp_rows if row.get("type") == "provider"]
        exported_rows = [row for row in comp_rows if row.get("exported") == "true"]
        counts, library_hits, examples, source_count = marker_hits(decoded_dir)

        blockers: list[str] = []
        status = plan.get("package_index_status", "")
        exposure_score = int_field(plan, "exposure_score")
        if status and status != "ok":
            blockers.append(f"package-index status {status}")
        if len(exported_rows) > 1:
            blockers.append(f"{len(exported_rows)} exported components")
        if provider_rows:
            blockers.append(f"{len(provider_rows)} providers")
        if core_intents:
            blockers.append(f"{len(core_intents)} core intent entries")
        if len(permission_rows) > 8:
            blockers.append(f"{len(permission_rows)} permissions")
        if sysconfig_rows:
            blockers.append(f"{len(sysconfig_rows)} sysconfig references")
        if privapp_rows:
            blockers.append(f"{len(privapp_rows)} privapp-permission references")
        if overlay_refs:
            blockers.append(f"{len(overlay_refs)} overlay refs")
        if counts["direct_asset_locale_api"]:
            blockers.append(f"{counts['direct_asset_locale_api']} direct asset locale API hits")
        if counts["locale_change_event"]:
            blockers.append(f"{counts['locale_change_event']} locale-change event hits")
        if counts["telephony_carrier_api"]:
            blockers.append(f"{counts['telephony_carrier_api']} telephony/carrier API hits")
        if exposure_score >= 90:
            blockers.append(f"high exposure score {exposure_score}")

        gate = manifest_gate(blockers, exposure_score, status)
        src_gate = source_gate(counts, decoded_dir)
        verdict = verdict_for(gate, src_gate, blockers, exposure_score)

        out.append(
            ReviewRow(
                package=package,
                verdict=verdict,
                manifest_gate=gate,
                source_gate=src_gate,
                partition=plan.get("partition", ""),
                rel_path=plan.get("rel_path", ""),
                decoded_dir=decoded_dir,
                exposure_score=exposure_score,
                non_target_dirs=int_field(plan, "non_target_dirs"),
                ja_ko_dirs=int_field(plan, "ja_ko_dirs"),
                other_locale_dirs=int_field(plan, "other_locale_dirs"),
                apk_size=int_field(plan, "apk_size"),
                package_index_status=status,
                component_count=len(comp_rows),
                exported_component_count=len(exported_rows),
                provider_count=len(provider_rows),
                core_intent_count=len(core_intents),
                requested_permission_count=len(permission_rows),
                sysconfig_refs=len(sysconfig_rows),
                privapp_permission_refs=len(privapp_rows),
                overlay_refs=len(overlay_refs),
                source_file_count=source_count,
                library_source_marker_hits=library_hits,
                direct_asset_locale_api=counts["direct_asset_locale_api"],
                locale_runtime_api=counts["locale_runtime_api"],
                locale_change_event=counts["locale_change_event"],
                telephony_carrier_api=counts["telephony_carrier_api"],
                dynamic_resource_lookup=counts["dynamic_resource_lookup"],
                source_examples=compact(examples),
                blockers=compact(blockers),
                next_step=next_step_for(package, verdict),
            )
        )

    return sorted(out, key=lambda row: (row.verdict, row.exposure_score, row.package))


def write_tsv(rows: list[ReviewRow]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    fields = list(ReviewRow.__dataclass_fields__)
    with OUT_TSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row.__dict__)


def md_table(rows: list[ReviewRow], columns: list[str]) -> list[str]:
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    for row in rows:
        data = row.__dict__
        values: list[str] = []
        for column in columns:
            value = str(data.get(column, "") or "").replace("|", "\\|").replace("\n", " ")
            if column in {"rel_path", "decoded_dir"} and value:
                value = f"`{value}`"
            values.append(value)
        lines.append("| " + " | ".join(values) + " |")
    return lines


def write_md(rows: list[ReviewRow]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    verdict_counts = Counter(row.verdict for row in rows)
    marker_candidate_counts = {
        category: sum(1 for row in rows if getattr(row, category) > 0)
        for category in SOURCE_MARKERS
    }
    library_marker_candidates = sum(1 for row in rows if row.library_source_marker_hits > 0)
    library_marker_hits = sum(row.library_source_marker_hits for row in rows)
    lines = [
        "# Language P1 Source Review Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit reviews the P1 small APK-only language-prune candidates from static ROM sources. It does not build APKs, rebuild images, flash, reboot, write settings, or touch `/data`.",
        "",
        f"Input plan: `{PLAN_TSV.relative_to(ROOT)}`",
        f"TSV output: `{OUT_TSV.relative_to(ROOT)}`",
        "",
        "## Summary",
        "",
        f"- candidates: {len(rows)}",
    ]
    for verdict, count in sorted(verdict_counts.items()):
        lines.append(f"- {verdict}: {count}")
    lines.append(f"- library_source_marker_candidate_count: {library_marker_candidates}")
    lines.append(f"- library_source_marker_hits: {library_marker_hits}")
    for category, count in sorted(marker_candidate_counts.items()):
        lines.append(f"- {category}_candidate_count: {count}")

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- P1a rows have no direct source-level locale/resource coupling in the static decompile and only low manifest exposure; they are the best APK-only mini-batch candidates.",
            "- P1b rows remain plausible APK-only candidates, but need a focused source note for the listed blockers before building.",
            "- P1c rows should wait behind package-specific source/graph review; they are still P1 in the global plan, but not the next safest mini-batch.",
            "- APK-only output is still not ROM coverage until inserted into a matching partition image and verified.",
            "",
            "## P1a Suggested First Mini-Batch",
            "",
        ]
    )
    lines.extend(
        md_table(
            [row for row in rows if row.verdict == "P1a_lowest_risk_apk_only_reviewed"],
            ["package", "partition", "exposure_score", "non_target_dirs", "source_gate", "blockers"],
        )
    )
    lines.extend(
        [
            "",
            "## All P1 Rows",
            "",
        ]
    )
    lines.extend(
        md_table(
            rows,
            [
                "package",
                "verdict",
                "manifest_gate",
                "source_gate",
                "exposure_score",
                "non_target_dirs",
                "blockers",
            ],
        )
    )
    lines.extend(
        [
            "",
            "## Source Marker Examples",
            "",
        ]
    )
    example_rows = [row for row in rows if row.source_examples]
    if example_rows:
        lines.extend(md_table(example_rows, ["package", "source_examples"]))
    else:
        lines.append("No P1 source marker examples were found.")
    lines.extend(
        [
            "",
            "## Boundary",
            "",
            "- This is source-review evidence only; it does not build APKs or prove PackageManager/live boot behavior.",
            "- Same-package resource replacement still follows the ORANGE replace gate: preserve manifest, classes, signature-readable stock shell, ZIP method, and resource-table policy.",
            "- Run package preflight and the APK-only verifier for each selected package before promoting it beyond this review.",
        ]
    )
    OUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    rows = build_rows()
    write_tsv(rows)
    write_md(rows)
    verdict_counts = Counter(row.verdict for row in rows)
    print(f"candidates={len(rows)}")
    for verdict, count in sorted(verdict_counts.items()):
        print(f"{verdict}={count}")
    print(f"library_source_marker_candidate_count={sum(1 for row in rows if row.library_source_marker_hits > 0)}")
    print(f"library_source_marker_hits={sum(row.library_source_marker_hits for row in rows)}")
    for category in sorted(SOURCE_MARKERS):
        print(f"{category}_candidate_count={sum(1 for row in rows if getattr(row, category) > 0)}")
    print(f"tsv={OUT_TSV.relative_to(ROOT)}")
    print(f"markdown={OUT_MD.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
