#!/usr/bin/env python3
"""Plan the next English/Chinese-only language prune batches.

This script is read-only. It consumes the full language coverage TSV and turns
the remaining work into actionable batches: rebuild already-proven image
inputs, promote existing APK-only candidates, build the next small APK-only
candidates, and keep larger or riskier packages behind explicit review gates.
"""

from __future__ import annotations

import csv
import shutil
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv"
OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/language-next-batch-plan.tsv"
OUT_MD = ROOT / "docs/research/language-next-batch-plan.md"


@dataclass(frozen=True)
class PlanRow:
    priority: int
    batch: str
    action: str
    package: str
    partition: str
    rel_path: str
    risk: str
    next_frontier: str
    exposure_gate: str
    exposure_score: int
    non_target_dirs: int
    ja_ko_dirs: int
    other_locale_dirs: int
    apk_size: int
    package_index_status: str
    apk_only_variant: str
    apk_only_apk: str
    apk_only_sha256: str
    blockers: str
    command_hint: str


def read_rows() -> list[dict[str, str]]:
    with INPUT_TSV.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def int_field(row: dict[str, str], key: str) -> int:
    try:
        return int(row.get(key, "") or 0)
    except ValueError:
        return 0


def command_hint(row: dict[str, str], batch: str) -> str:
    package = row.get("package", "")
    if batch == "P0a_rebuild_v013_tier1a_stored":
        return "rebuild v0.13 system_b with current STORED APK inputs, then verify offline before any super promotion"
    if batch == "P0b_promote_existing_apk_only":
        if package == "com.qualcomm.qti.confdialer":
            return "promote via v0.17b product/system_ext plan; use same-size system_ext in-place proof for Confdialer"
        return "promote existing APK-only output into its partition image with the v0.17 image path when space allows"
    if batch.startswith("P1_") or batch.startswith("P2_"):
        return (
            f"tools/r2-rom-mod-preflight.py {package} --action replace && "
            f"tools/r2-build-apk-locale-prune.sh --package {package} "
            "--apk-only-variant <next-variant> --apk-only-note '<reviewed APK-only language prune; not in ROM image>'"
        )
    if batch == "P3_deferred_green_coupled":
        return "perform focused source review before APK build; package is green-ish but known coupled/deferred"
    if batch == "P4_amber_package_gate":
        return "run package preflight plus focused source/graph review before any resource prune build"
    if batch == "P5_red_core_gate":
        return "requires component-specific no-op/live gate; do not start with APK resource prune"
    return ""


def blockers_for(row: dict[str, str], batch: str) -> str:
    blockers: list[str] = []
    if row.get("package_index_status") and row.get("package_index_status") != "ok":
        blockers.append(f"package-index status {row['package_index_status']}")
    if int_field(row, "exported_component_count"):
        blockers.append(f"{row['exported_component_count']} exported components")
    if int_field(row, "provider_count"):
        blockers.append(f"{row['provider_count']} providers")
    if int_field(row, "core_intent_count"):
        blockers.append(f"{row['core_intent_count']} core intent entries")
    if int_field(row, "requested_permission_count") > 4:
        blockers.append(f"{row['requested_permission_count']} permissions")
    if row.get("partition") == "system_ext" and batch in {"P0b_promote_existing_apk_only", "P1_build_small_apk_only"}:
        blockers.append("system_ext space/extent gate")
    if batch.startswith("P0"):
        blockers.append("local disk space for partition/super image")
    if batch.startswith("P5"):
        blockers.append("core/shared-UID/live gate")
    return "; ".join(blockers)


def classify(row: dict[str, str]) -> tuple[int, str, str] | None:
    status = row.get("coverage_status", "")
    frontier = row.get("next_frontier", "")
    if status == "pruned_in_v0.13_system_image":
        return (0, "P0a_rebuild_v013_tier1a_stored", "rebuild_image_with_current_apk_inputs")
    if status != "remaining_after_current_candidates":
        return None
    if row.get("apk_only_variant"):
        return (1, "P0b_promote_existing_apk_only", "promote_existing_apk_only_to_rom_image")
    if frontier == "tier1_small_green_apk_resource_prune":
        return (2, "P1_build_small_apk_only", "build_new_small_apk_only_candidate_after_review")
    if frontier == "tier2_green_full_language_prune":
        return (3, "P2_build_green_full_language_apk_only", "build_high_yield_green_candidate_after_review")
    if frontier == "defer_green_coupled_or_large_locale_table":
        return (4, "P3_deferred_green_coupled", "focused_source_review_before_build")
    if frontier == "amber_requires_package_gate":
        return (5, "P4_amber_package_gate", "package_gate_before_build")
    if frontier == "red_requires_core_gate":
        return (6, "P5_red_core_gate", "core_gate_before_build")
    return None


def build_plan(rows: list[dict[str, str]]) -> list[PlanRow]:
    plan: list[PlanRow] = []
    for row in rows:
        classified = classify(row)
        if classified is None:
            continue
        priority, batch, action = classified
        plan.append(
            PlanRow(
                priority=priority,
                batch=batch,
                action=action,
                package=row.get("package", ""),
                partition=row.get("partition", ""),
                rel_path=row.get("rel_path", ""),
                risk=row.get("risk", ""),
                next_frontier=row.get("next_frontier", ""),
                exposure_gate=row.get("exposure_gate", ""),
                exposure_score=int_field(row, "exposure_score"),
                non_target_dirs=int_field(row, "non_target_dirs"),
                ja_ko_dirs=int_field(row, "ja_ko_dirs"),
                other_locale_dirs=int_field(row, "other_locale_dirs"),
                apk_size=int_field(row, "apk_size"),
                package_index_status=row.get("package_index_status", ""),
                apk_only_variant=row.get("apk_only_variant", ""),
                apk_only_apk=row.get("apk_only_apk", ""),
                apk_only_sha256=row.get("apk_only_sha256", ""),
                blockers=blockers_for(row, batch),
                command_hint=command_hint(row, batch),
            )
        )
    return sorted(
        plan,
        key=lambda item: (
            item.priority,
            item.exposure_score,
            -item.non_target_dirs,
            item.package,
        ),
    )


def write_tsv(plan: list[PlanRow]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    fields = list(PlanRow.__dataclass_fields__)
    with OUT_TSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in plan:
            writer.writerow(row.__dict__)


def md_table(rows: list[PlanRow], columns: list[str]) -> list[str]:
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    if not rows:
        lines.append("| " + " | ".join("current none" if index == 0 else "" for index, _ in enumerate(columns)) + " |")
        return lines
    for row in rows:
        values: list[str] = []
        data = row.__dict__
        for col in columns:
            value = str(data.get(col, "") or "").replace("|", "\\|").replace("\n", " ")
            if col in {"rel_path", "apk_only_apk"} and value:
                value = f"`{value}`"
            values.append(value)
        lines.append("| " + " | ".join(values) + " |")
    return lines


def group(plan: list[PlanRow]) -> dict[str, list[PlanRow]]:
    out: dict[str, list[PlanRow]] = defaultdict(list)
    for row in plan:
        out[row.batch].append(row)
    return out


def sum_dirs(rows: list[PlanRow]) -> int:
    return sum(row.non_target_dirs for row in rows)


def write_md(plan: list[PlanRow]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    grouped = group(plan)
    disk = shutil.disk_usage(ROOT)
    p0b_count = len(grouped.get("P0b_promote_existing_apk_only", []))
    p0b_dirs = sum_dirs(grouped.get("P0b_promote_existing_apk_only", []))
    if p0b_count:
        p0b_recommendation = (
            "2. Promote the "
            f"{p0b_count} existing APK-only candidates ({p0b_dirs} non-target dirs) "
            "into ROM partition images when disk space allows; this converts "
            "already-reviewed APK surgery into real ROM coverage."
        )
    else:
        p0b_recommendation = (
            "2. The existing APK-only promotion queue is empty in the current "
            "coverage TSV; next combined-image work should merge already built "
            "v0.17 partition images only if a single flashable test target is needed."
        )
    lines = [
        "# Language Next Batch Plan",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only plan turns the full English/Chinese language-prune coverage audit into concrete next batches. It does not build APKs, rebuild images, flash, reboot, write settings, or touch `/data`.",
        "",
        f"Input: `{INPUT_TSV.relative_to(ROOT)}`",
        f"TSV output: `{OUT_TSV.relative_to(ROOT)}`",
        "",
        "## Summary",
        "",
        f"- planned rows: {len(plan)}",
        f"- current local free space: {disk.free} bytes",
        "",
    ]
    for batch, rows in sorted(grouped.items()):
        lines.append(f"- {batch}: {len(rows)} packages, {sum_dirs(rows)} non-target dirs")

    lines.extend(
        [
            "",
            "## Recommended Order",
            "",
            "1. Rebuild the v0.13 Tier1a system image with the current STORED resources.arsc APK inputs before any flashable promotion.",
            p0b_recommendation,
            "3. Build only a few new small APK-only candidates at a time, starting with the lowest exposure rows in P1.",
            "4. Treat high-yield GREEN rows in P2 as package-review work first; they remove many more directories but have broader app coupling.",
            "5. Keep AMBER/RED rows behind their package, framework, Settings, SystemUI, launcher, input, phone, provider, or live no-op gates.",
            "",
            "## P0a Rebuild Existing v0.13 Inputs",
            "",
            *md_table(
                grouped.get("P0a_rebuild_v013_tier1a_stored", []),
                ["package", "partition", "non_target_dirs", "rel_path", "command_hint"],
            ),
            "",
            "## P0b Promote Existing APK-Only Candidates",
            "",
            *md_table(
                grouped.get("P0b_promote_existing_apk_only", []),
                [
                    "package",
                    "partition",
                    "non_target_dirs",
                    "apk_only_variant",
                    "apk_only_apk",
                    "blockers",
                ],
            ),
            "",
            "## P1 New Small APK-Only Candidates",
            "",
            *md_table(
                grouped.get("P1_build_small_apk_only", [])[:25],
                [
                    "package",
                    "partition",
                    "exposure_score",
                    "non_target_dirs",
                    "apk_size",
                    "package_index_status",
                    "blockers",
                ],
            ),
            "",
            "## P2 High-Yield GREEN Candidates",
            "",
            *md_table(
                grouped.get("P2_build_green_full_language_apk_only", [])[:25],
                [
                    "package",
                    "partition",
                    "exposure_score",
                    "non_target_dirs",
                    "apk_size",
                    "package_index_status",
                    "blockers",
                ],
            ),
            "",
            "## Gate Buckets",
            "",
        ]
    )
    for batch in ["P3_deferred_green_coupled", "P4_amber_package_gate", "P5_red_core_gate"]:
        rows = grouped.get(batch, [])
        lines.append(f"- {batch}: {len(rows)} packages, {sum_dirs(rows)} dirs")
    lines.extend(
        [
            "",
            "## Boundary",
            "",
            "- APK-only output is not ROM coverage until it is inserted into the correct partition image and verified.",
            "- Local disk space changes quickly because each flashable sparse super is about 8 GiB; run the v0.17 promotion audit before starting another image build.",
            "- Do not promote core/shared-UID/launcher/input/phone/framework rows without their specific gates.",
        ]
    )
    OUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    rows = read_rows()
    plan = build_plan(rows)
    write_tsv(plan)
    write_md(plan)
    grouped = group(plan)
    for batch, rows_for_batch in sorted(grouped.items()):
        print(f"{batch}={len(rows_for_batch)} packages/{sum_dirs(rows_for_batch)} dirs")
    print(f"planned_rows={len(plan)}")
    print(f"tsv={OUT_TSV.relative_to(ROOT)}")
    print(f"markdown={OUT_MD.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
