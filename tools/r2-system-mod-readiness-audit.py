#!/usr/bin/env python3
"""Audit readiness for the two active Smartisan system-modification goals.

This script is read-only. It checks current files, hashes, verifier reports,
and locale coverage data to show which requirements are proven, which are only
offline candidates, and which still need live-device or broader hard-prune work.
"""

from __future__ import annotations

import csv
import hashlib
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/system-modification-readiness-audit.tsv"
OUT_MD = ROOT / "docs/research/system-modification-readiness-audit.md"
APK_ONLY_MANIFEST = ROOT / "hard-rom/build/apk/locale-prune-apk-only-manifest.tsv"


@dataclass(frozen=True)
class Check:
    area: str
    requirement: str
    status: str
    evidence: str
    gap: str


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def exists_with_hash(path: str, expected: str) -> tuple[str, str]:
    target = ROOT / path
    if not target.exists():
        return "missing", f"{path} is missing"
    actual = sha256(target)
    if actual != expected:
        return "contradicted", f"{path} sha256={actual}, expected={expected}"
    return "proven_offline", f"{path} sha256={actual}"


def retired_local_sparse_status(path: str, expected: str, replacement: str) -> tuple[str, str]:
    target = ROOT / path
    if target.exists():
        actual = sha256(target)
        if actual == expected:
            return "proven_offline", f"{path} sha256={actual}"
        return "contradicted", f"{path} sha256={actual}, expected={expected}"
    replacement_path = ROOT / replacement
    if replacement_path.exists():
        return (
            "retired_local",
            f"{path} removed from Mac working tree after cleanup; current retained combined target is {replacement}",
        )
    return "missing", f"{path} is missing and replacement {replacement} is also missing"


def retired_local_artifact_status(path: str, expected: str, replacement: str) -> tuple[str, str]:
    target = ROOT / path
    if target.exists():
        actual = sha256(target)
        if actual == expected:
            return "proven_offline", f"{path} sha256={actual}"
        return "contradicted", f"{path} sha256={actual}, expected={expected}"
    replacement_path = ROOT / replacement
    if replacement_path.exists():
        return (
            "retired_local",
            f"{path} removed from Mac working tree after cleanup; retained replacement evidence is {replacement}",
        )
    return "missing", f"{path} is missing and retained replacement {replacement} is also missing"


def read_apk_only_manifest() -> dict[str, dict[str, str]]:
    if not APK_ONLY_MANIFEST.exists():
        return {}
    with APK_ONLY_MANIFEST.open(encoding="utf-8", newline="") as fh:
        return {
            row.get("package", ""): row
            for row in csv.DictReader(fh, delimiter="\t")
            if row.get("package")
        }


def apk_only_candidate_status(package: str, expected_variant: str) -> tuple[str, str]:
    rows = read_apk_only_manifest()
    row = rows.get(package)
    if not row:
        return "missing", f"{APK_ONLY_MANIFEST.relative_to(ROOT)} has no row for {package}"
    variant = row.get("variant", "")
    if variant != expected_variant:
        return "contradicted", f"{package} variant={variant}, expected={expected_variant}"
    rel_apk = row.get("apk", "")
    expected_sha = row.get("sha256", "")
    if not rel_apk or not expected_sha:
        return "missing", f"{package} APK-only manifest row is incomplete"
    status, evidence = exists_with_hash(rel_apk, expected_sha)
    if status == "proven_offline":
        return status, f"{package} {variant}; {evidence}"
    return status, f"{package} {variant}; {evidence}"


def latest_report(pattern: str) -> Path | None:
    reports = sorted(ROOT.glob(pattern))
    return reports[-1] if reports else None


def report_has_pass(pattern: str, pass_text: str = "PASS") -> tuple[str, str]:
    report = latest_report(pattern)
    if report is None:
        return "missing", f"no report matches {pattern}"
    text = report.read_text(encoding="utf-8", errors="replace")
    if pass_text not in text:
        return "weak_or_failed", f"{report.relative_to(ROOT)} does not contain {pass_text!r}"
    return "proven_offline", f"{report.relative_to(ROOT)} contains {pass_text!r}"


def report_has_markers(pattern: str, markers: list[str]) -> tuple[str, str]:
    report = latest_report(pattern)
    if report is None:
        return "missing", f"no report matches {pattern}"
    text = report.read_text(encoding="utf-8", errors="replace")
    missing = [marker for marker in markers if marker not in text]
    if missing:
        return "weak_or_failed", f"{report.relative_to(ROOT)} missing markers: {', '.join(missing)}"
    return "proven_offline", f"{report.relative_to(ROOT)} contains required structured markers"


def live_report_has_pass(pattern: str, pass_text: str = "PASS") -> tuple[str, str]:
    status, evidence = report_has_pass(pattern, pass_text)
    if status == "proven_offline":
        return "proven_live", evidence
    return status, evidence


def live_report_has_markers(pattern: str, markers: list[str]) -> tuple[str, str]:
    status, evidence = report_has_markers(pattern, markers)
    if status == "proven_offline":
        return "proven_live", evidence
    return status, evidence


def darkmode_live_state_status() -> tuple[str, str]:
    pattern = "hard-rom/inspect/darkmode-live-state/darkmode-live-state-*.txt"
    report = latest_report(pattern)
    if report is None:
        return "missing", f"no report matches {pattern}"
    text = report.read_text(encoding="utf-8", errors="replace")
    if "result=PASS_READ_ONLY" in text:
        required = [
            "secure.ui_night_mode=",
            "system.ui_night_mode=",
            "global.ui_night_mode=",
            "system.expanded_widget_buttons=",
            "system.expanded_widget_buttons_additional=",
            "secure.expanded_widget_buttons=",
            "secure.expanded_widget_buttons_additional=",
            "system.expanded_widget_buttons.count=",
            "system.expanded_widget_buttons.has_toggleDarkMode=",
            "system.expanded_widget_buttons.over20=",
            "secure.sysui_qs_tiles=",
        ]
        missing = [marker for marker in required if marker not in text]
        if missing:
            return "weak_or_failed", f"{report.relative_to(ROOT)} missing markers: {', '.join(missing)}"
        return "proven_live", f"{report.relative_to(ROOT)} contains read-only UiMode/QS system-setting summary"
    if "result=DEVICE_NOT_AVAILABLE" in text:
        return "missing", f"{report.relative_to(ROOT)} reports DEVICE_NOT_AVAILABLE"
    return "weak_or_failed", f"{report.relative_to(ROOT)} has no PASS_READ_ONLY or DEVICE_NOT_AVAILABLE marker"


def darkmode_functional_status() -> tuple[str, str]:
    pattern = "hard-rom/inspect/v0.11-native-darkmode-functional/v0.11-darkmode-functional-[0-9]*.txt"
    report = latest_report(pattern)
    if report is None:
        return "missing", f"no report matches {pattern}"
    text = report.read_text(encoding="utf-8", errors="replace")
    required = [
        "ui_mode_yes=PASS",
        "ui_mode_no=PASS",
        "systemui_toggleDarkMode_tile_creation=PASS",
        "restore_original_quick_settings=PASS",
        "result=PASS_WRITE_APPROVED_FUNCTIONAL",
        "Creating tile: toggleDarkMode",
    ]
    missing = [marker for marker in required if marker not in text]
    if missing:
        return "weak_or_failed", f"{report.relative_to(ROOT)} missing markers: {', '.join(missing)}"
    return "proven_live", f"{report.relative_to(ROOT)} proves UiMode yes/no, SystemUI toggleDarkMode tile creation, and restored QS data"


def language_live_state_status() -> tuple[str, str]:
    pattern = "hard-rom/inspect/language-live-state/language-live-state-*.txt"
    report = latest_report(pattern)
    if report is None:
        return "missing", f"no report matches {pattern}"
    text = report.read_text(encoding="utf-8", errors="replace")
    if "result=PASS_READ_ONLY" in text:
        required = [
            "persist.sys.locale=",
            "ro.product.locale=",
            "system.system_locales=",
            "secure.system_locales=",
            "global.system_locales=",
            "secure.default_input_method=",
            "secure.selected_input_method_subtype=",
            "updated_system_shadow=",
        ]
        missing = [marker for marker in required if marker not in text]
        if missing:
            return "weak_or_failed", f"{report.relative_to(ROOT)} missing markers: {', '.join(missing)}"
        return "proven_live", f"{report.relative_to(ROOT)} contains read-only locale/package shadow summary"
    if "result=DEVICE_NOT_AVAILABLE" in text:
        return "missing", f"{report.relative_to(ROOT)} reports DEVICE_NOT_AVAILABLE"
    return "weak_or_failed", f"{report.relative_to(ROOT)} has no PASS_READ_ONLY or DEVICE_NOT_AVAILABLE marker"


def add(
    checks: list[Check],
    area: str,
    requirement: str,
    status: str,
    evidence: str,
    gap: str = "",
) -> None:
    checks.append(Check(area, requirement, status, evidence, gap))


def read_locale_coverage() -> tuple[int, int, int, int, int, int, int, int, int]:
    path = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv"
    if not path.exists():
        return (0, 0, 0, 0, 0, 0, 0, 0, 0)
    rows = list(csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"))
    stock_pkgs = len(rows)
    stock_dirs = sum(int(row.get("ja_ko_dirs") or 0) for row in rows)
    covered = [
        row
        for row in rows
        if row.get("coverage_status")
        in {
            "removed_in_v0.2_v0.4",
            "pruned_in_v0.10_candidate",
            "pruned_in_v0.13_system_image",
            "pruned_in_v0.17a_system_image",
            "pruned_in_v0.17b_product_system_ext_image",
            "pruned_in_v0.22_all_system_image",
            "pruned_in_v0.24_system_image",
        }
    ]
    remaining = [row for row in rows if row.get("coverage_status") == "remaining_after_v0.4_v0.10"]
    v013 = [row for row in rows if row.get("coverage_status") == "pruned_in_v0.13_system_image"]
    apk_only = [
        row
        for row in rows
        if row.get("apk_only_variant") and row.get("coverage_status") == "remaining_after_v0.4_v0.10"
    ]
    return (
        stock_pkgs,
        stock_dirs,
        len(covered),
        sum(int(row.get("ja_ko_dirs") or 0) for row in covered),
        len(remaining),
        sum(int(row.get("ja_ko_dirs") or 0) for row in remaining),
        len(v013),
        len(apk_only),
        sum(int(row.get("ja_ko_dirs") or 0) for row in apk_only),
    )


def read_full_language_coverage() -> tuple[int, int, int, int, int, int, int, int, int, int, int, int]:
    path = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv"
    if not path.exists():
        return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    rows = list(csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"))
    stock_pkgs = len(rows)
    stock_dirs = sum(int(row.get("non_target_dirs") or 0) for row in rows)
    ja_ko_dirs = sum(int(row.get("ja_ko_dirs") or 0) for row in rows)
    other_dirs = sum(int(row.get("other_locale_dirs") or 0) for row in rows)
    covered = [
        row
        for row in rows
        if row.get("coverage_status")
        in {
            "removed_in_v0.2_v0.4",
            "pruned_in_v0.10_candidate",
            "pruned_in_v0.13_system_image",
            "pruned_in_v0.17a_system_image",
            "pruned_in_v0.17b_product_system_ext_image",
            "pruned_in_v0.22_all_system_image",
            "pruned_in_v0.24_system_image",
        }
    ]
    remaining = [row for row in rows if row.get("coverage_status") == "remaining_after_current_candidates"]
    visible_only = [row for row in rows if row.get("coverage_status") == "visible_filter_only_v0.7"]
    apk_only = [
        row
        for row in rows
        if row.get("apk_only_variant") and row.get("coverage_status") == "remaining_after_current_candidates"
    ]
    return (
        stock_pkgs,
        stock_dirs,
        ja_ko_dirs,
        other_dirs,
        len(covered),
        sum(int(row.get("non_target_dirs") or 0) for row in covered),
        len(remaining),
        sum(int(row.get("non_target_dirs") or 0) for row in remaining),
        len(visible_only),
        sum(int(row.get("non_target_dirs") or 0) for row in visible_only),
        len(apk_only),
        sum(int(row.get("non_target_dirs") or 0) for row in apk_only),
    )


def audit() -> list[Check]:
    checks: list[Check] = []

    status, evidence = exists_with_hash(
        "hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img",
        "313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5",
    )
    add(checks, "rollback", "local v0.4 rollback sparse image is ready", status, evidence)

    status, evidence = report_has_markers(
        "docs/research/system-modification-route-audit.md",
        [
            "# System Modification Route Audit",
            "routes=11",
            "settings_core_apk_patch",
            "systemui_core_apk_patch",
            "language_framework_assets",
            "phone_telephony_surface",
        ],
    )
    add(
        checks,
        "route_control",
        "system modification route audit maps core change classes, gates, and red-zone surfaces",
        status,
        evidence,
        "route audit is a planning gate; live proof still belongs to each component gate" if status == "proven_offline" else "run tools/r2-system-modification-route-audit.py",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk",
        "8a4472dbfe90c16dc3cdf01eb2a41bdcb951b5c0da1b07d57dba19373812a7f0",
    )
    settings_live_status, _settings_live_evidence = live_report_has_pass(
        "hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-*.txt",
        "PASS: v0.25-settings-noop-on-v0.24 verification",
    )
    systemui_live_status, _systemui_live_evidence = live_report_has_pass(
        "hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-*.txt",
        "PASS: systemui-certprobe-noop-on-v0.24 device read-only verification",
    )
    add(
        checks,
        "dark_mode",
        "SettingsSmartisan native dark-mode UI APK candidate exists",
        status,
        evidence,
        "included in the combined v0.11 ROM candidate; live package/hash proof and UiMode/SystemUI functional proof now exist; Settings row UX still needs manual proof"
        if status == "proven_offline" and settings_live_status == "proven_live" and systemui_live_status == "proven_live"
        else "Settings no-op live gate passed; rebuild exact-current behavior image after SystemUI gate"
        if status == "proven_offline" and settings_live_status == "proven_live"
        else "needs v0.25 current-base Settings no-op live gate before any behavior flash"
        if status == "proven_offline"
        else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk",
        "c80904f85acf15ca706d4a40b1dad9f5c556ff69affa7fe270a9221889a7de26",
    )
    add(
        checks,
        "dark_mode",
        "SmartisanSystemUI native toggleDarkMode APK candidate exists",
        status,
        evidence,
        "included in the combined v0.11 ROM candidate; live package/hash proof and reversible SystemUI tile-creation proof now exist"
        if status == "proven_offline" and systemui_live_status == "proven_live"
        else "needs SystemUI no-op live gate before any behavior flash"
        if status == "proven_offline"
        else "",
    )

    status, evidence = report_has_pass(
        "hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-*.txt"
    )
    add(
        checks,
        "dark_mode",
        "v0.11 APK semantic verifier proves intended Settings/SystemUI call sites",
        status,
        evidence,
        "semantic APK proof is not live PackageManager/shared-UID proof" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "docs/research/darkmode-source-coupling-audit.md",
        [
            "stock_supported: 1",
            "stock_persistence_supported: 5",
            "stock_restore_path_mapped: 1",
            "stock_widget_registry_limited: 1",
            "stock_default_capacity_full: 1",
            "stock_missing_entry: 3",
            "candidate_proven_offline: 2",
            "proven_live: 5",
        ],
    )
    add(
        checks,
        "dark_mode",
        "dark-mode source coupling audit maps stock framework, Settings, SystemUI, resources, and gates",
        status,
        evidence,
        "source-coupling proof now includes live boot/package/hash plus reversible UiMode/SystemUI functional evidence; Settings row/editor UX still needs manual proof"
        if status == "proven_offline"
        else "run tools/r2-darkmode-source-coupling-audit.py",
    )

    status, evidence = report_has_markers(
        "docs/research/darkmode-qs-strategy-audit.md",
        [
            "capacity_full: 1",
            "stock_missing_native_key: 1",
            "requires_framework_registry_patch: 1",
            "settingssmartisan_local_candidate_patch_available: 1",
            "candidate_injection_proven_offline: 1",
            "requires_displacement: 1",
            "captured: 1",
            "restore_split_mapped: 1",
            "registry_limited: 1",
        ],
    )
    add(
        checks,
        "dark_mode",
        "dark-mode QS default/editor strategy audit maps the native-key integration routes",
        status,
        evidence,
        "candidate injection is offline-proven; default visibility, live editor availability, and data migration still need live gates" if status == "proven_offline" else "run tools/r2-darkmode-qs-strategy-audit.py",
    )

    status, evidence = report_has_markers(
        "docs/research/darkmode-persistence-audit.md",
        [
            "stock_default_missing_target: 1",
            "stock_registry_missing_target: 1",
            "candidate_editor_persistence_proven_offline: 1",
            "upgrade_cleanup_path_mapped: 1",
            "restore_not_target_aware: 1",
            "systemui_first_page_cap_mapped: 1",
            "editor_additional_first: 1",
        ],
    )
    add(
        checks,
        "dark_mode",
        "dark-mode persistence audit maps SettingsProvider seed, editor reset, restore, and SystemUI truncation paths",
        status,
        evidence,
        "editor/additional route is offline-mapped; default-visible behavior still needs live state and later policy" if status == "proven_offline" else "run tools/r2-darkmode-persistence-audit.py",
    )

    status, evidence = darkmode_live_state_status()
    add(
        checks,
        "dark_mode",
        "current device UiMode and Smartisan QS settings have been captured read-only",
        status,
        evidence,
        "required before choosing a default tile replacement, SettingsProvider seed, or live QS data migration",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-*.txt",
        [
            "verify_variants=v0.25-settings-noop-on-v0.24",
            "v0.25-settings-noop-on-v0.24/SettingsSmartisan.apk",
            "system_b\timage=ae6870e3d1109673fea6c8857d1c00bbf2866926d772e9bebb6218be1d4e4bbb\t"
            "sparse_slice=ae6870e3d1109673fea6c8857d1c00bbf2866926d772e9bebb6218be1d4e4bbb",
            "PASS",
        ],
    )
    add(
        checks,
        "dark_mode",
        "v0.25 current-base SettingsSmartisan no-op image verifies offline",
        status,
        evidence,
        "offline image proof is not live PackageManager/shared-UID proof"
        if status == "proven_offline"
        else "run VERIFY_VARIANTS=v0.25-settings-noop-on-v0.24 tools/r2-verify-settingssmartisan-offline-images.sh",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-offline-*.txt",
        [
            "systemui_noop_variant=systemui-certprobe-noop-on-v0.24",
            "system_ext_b\timage=133655b1b88440d942d473b1f14971acf657b379540fa12ca8fd5efe9c3d8f32\t"
            "sparse_slice=133655b1b88440d942d473b1f14971acf657b379540fa12ca8fd5efe9c3d8f32",
            "PASS",
        ],
    )
    add(
        checks,
        "dark_mode",
        "current-base SmartisanSystemUI no-op image verifies offline",
        status,
        evidence,
        "offline image proof is not live PackageManager/shared-UID proof"
        if status == "proven_offline"
        else "run SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24 tools/r2-verify-systemui-certprobe-noop.sh --offline-image",
    )

    status, evidence = live_report_has_pass(
        "hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-*.txt",
        "PASS: v0.25-settings-noop-on-v0.24 verification",
    )
    add(
        checks,
        "dark_mode",
        "v0.25 current-base SettingsSmartisan no-op replacement has booted and verified live",
        status,
        evidence,
        "required before rebuilding or flashing v0.8/v0.11 Settings behavior patches on the v0.24 line",
    )

    status, evidence = live_report_has_pass(
        "hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-*.txt",
        "PASS: systemui-certprobe-noop-on-v0.24 device read-only verification",
    )
    add(
        checks,
        "dark_mode",
        "current-base SmartisanSystemUI no-op replacement has booted and verified live",
        status,
        evidence,
        "required before native toggleDarkMode SystemUI patch",
    )

    v011_live_status, v011_live_evidence = live_report_has_pass(
        "hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-*.txt",
        "PASS: v0.11 native dark-mode device read-only verification",
    )
    add(
        checks,
        "dark_mode",
        "v0.11 native dark-mode behavior ROM booted and verified patched APKs live",
        v011_live_status,
        v011_live_evidence,
        "next needs manual user-facing proof for Settings row and Smartisan QS editor behavior"
        if v011_live_status == "proven_live"
        else "after v0.11 flash, run tools/r2-verify-v0.11-native-darkmode.sh --read-only",
    )

    status, evidence = darkmode_functional_status()
    add(
        checks,
        "dark_mode",
        "v0.11 reversible functional write test proves UiMode yes/no and SystemUI toggleDarkMode tile creation",
        status,
        evidence,
        "SettingsSmartisan dark-mode row visibility/click behavior and QS editor candidate UX still need manual device proof"
        if status == "proven_live"
        else "run tools/r2-darkmode-functional-test.sh --write-approved only after explicit /data-write approval",
    )

    v011_super = ROOT / "hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img"
    add(
        checks,
        "dark_mode",
        "combined v0.11 exact-current dark-mode ROM image exists",
        "missing" if not v011_super.exists() else "proven_live" if v011_live_status == "proven_live" else "candidate_offline",
        str(v011_super.relative_to(ROOT)) if v011_super.exists() else "no combined v0.11 super image yet",
        "already flashed and matched live APK hashes; UiMode/SystemUI tile functional proof now exists"
        if v011_live_status == "proven_live"
        else "build only after SettingsSmartisan and SmartisanSystemUI live no-op gates pass",
    )

    status, evidence = report_has_pass("hard-rom/inspect/v0.7-locale-filter/verify-settingssmartisan-locale-filter-apk-*.txt")
    add(
        checks,
        "language",
        "v0.7 Settings language picker filter APK semantics are proven offline",
        status,
        evidence,
        "visible filter is not resource hard-prune" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "docs/research/language-source-coupling-audit.md",
        [
            "stock_visible_picker_coupled_to_assets: 1",
            "stock_system_asset_source_mapped: 1",
            "stock_package_asset_source_mapped: 1",
            "stock_resource_fallback_coupled_to_assets: 1",
            "stock_non_ui_locale_coupling: 3",
            "candidate_proven_offline: 6",
            "coverage_measured_incomplete: 1",
            "full_coverage_measured_incomplete: 1",
            "missing_live_gate: 2",
            "missing_rom_image: 1",
        ],
    )
    add(
        checks,
        "language",
        "language source coupling audit maps Settings picker, framework AssetManager, ResourcesImpl, non-UI locale users, and gates",
        status,
        evidence,
        "source-coupling proof is not live framework/package-manager proof" if status == "proven_offline" else "run tools/r2-language-source-coupling-audit.py",
    )

    status, evidence = report_has_markers(
        "docs/research/language-prune-integration-map.md",
        [
            "User-visible system language choices:",
            "visible locale list:",
            "first-stage resource retention:",
            "Smartisan visible language picker:",
            "System AssetManager:",
            "Per-package resources:",
            "Non-UI locale users:",
            "Stage L0:",
            "Stage L7:",
        ],
    )
    add(
        checks,
        "language",
        "language prune integration map defines visible-list, framework, package, fallback, and live gates",
        status,
        evidence,
        "integration map is not live PackageManager/resource proof" if status == "proven_offline" else "update docs/research/language-prune-integration-map.md",
    )

    status, evidence = report_has_markers(
        "docs/research/language-next-batch-plan.md",
        [
            "P0a_rebuild_v013_tier1a_stored: 3 packages, 6 non-target dirs",
            "P1_build_small_apk_only: 10 packages, 20 non-target dirs",
            "P2_build_green_full_language_apk_only: 22 packages, 1555 non-target dirs",
            "P4_amber_package_gate: 56 packages, 1840 non-target dirs",
            "P5_red_core_gate: 45 packages, 1098 non-target dirs",
        ],
    )
    add(
        checks,
        "language",
        "language next-batch plan separates existing APK-only promotion, new APK candidates, and package/core gates",
        status,
        evidence,
        "planning proof only; packages still need review, image builds, live gates, and device validation" if status == "proven_offline" else "run tools/r2-language-next-batch-plan.py",
    )

    status, evidence = report_has_markers(
        "docs/research/language-p1-source-review-audit.md",
        [
            "candidates: 10",
            "P1c_defer_focused_package_review: 10",
            "library_source_marker_candidate_count: 7",
            "telephony_carrier_api_candidate_count: 4",
        ],
    )
    add(
        checks,
        "language",
        "language P1 source-review audit ranks the small APK-only candidates by manifest and source coupling",
        status,
        evidence,
        "source-review proof only; selected packages still need APK build, verifier, image insertion, and live validation"
        if status == "proven_offline"
        else "run tools/r2-language-p1-source-review-audit.py",
    )

    status, evidence = language_live_state_status()
    add(
        checks,
        "language",
        "current device locale, package path, and updated-system shadow state have been captured read-only",
        status,
        evidence,
        "required before validating visible language behavior, /data updated-system shadows, or live language migration",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img",
        "d5c63890f27f6609b09667cc0bee0dd4b55c5c335abeb530650c16fbce9d94d9",
    )
    add(
        checks,
        "language",
        "v0.12 framework-res no-op replacement image exists",
        status,
        evidence,
        "must boot live before v0.10 framework language hard-prune" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-offline-image-*.txt",
        [
            "signature_boundary=ok",
            "zip_integrity=ok",
            "system_b\timage=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0\t"
            "sparse_slice=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0",
        ],
    )
    add(
        checks,
        "language",
        "v0.12 framework-res no-op image verifies offline",
        status,
        evidence,
        "offline image proof is not early-boot live proof" if status == "proven_offline" else "",
    )

    status, evidence = live_report_has_pass("hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-device-*.txt")
    add(
        checks,
        "language",
        "v0.12 framework-res no-op has booted and verified live",
        status,
        evidence,
        "required before treating v0.10 failure/success as language-prune behavior",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img",
        "62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae",
    )
    add(
        checks,
        "language",
        "v0.10 framework/product language hard-prune image exists",
        status,
        evidence,
        "RED early-boot candidate; use only after v0.12 live pass" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.10-framework-locale-prune/verify-v0.10-offline-image-*.txt",
        [
            "signature_boundary=ok",
            "bad_locale_chunk_count=0",
            "system_b\timage=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351\t"
            "sparse_slice=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351",
            "product_b\timage=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2\t"
            "sparse_slice=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2",
        ],
    )
    add(
        checks,
        "language",
        "v0.10 framework/product language hard-prune image verifies offline",
        status,
        evidence,
        "offline image proof is not live boot or full-ROM language completion" if status == "proven_offline" else "",
    )

    coverage = read_locale_coverage()
    if len(coverage) == 9:
        (
            stock_pkgs,
            stock_dirs,
            covered_pkgs,
            covered_dirs,
            remaining_pkgs,
            remaining_dirs,
            v013_pkgs,
            apk_only_pkgs,
            apk_only_dirs,
        ) = coverage
        add(
            checks,
            "language",
            "ja/ko subset resource coverage is measured",
            "proven_offline",
            (
                f"stock={stock_pkgs} packages/{stock_dirs} dirs; "
                f"covered={covered_pkgs} packages/{covered_dirs} dirs; "
                f"remaining={remaining_pkgs} packages/{remaining_dirs} dirs; "
                f"v0.13={v013_pkgs} packages; "
                f"apk_only={apk_only_pkgs} packages/{apk_only_dirs} dirs"
            ),
            "ja/ko is only a subset of the English/Chinese-only target",
        )
    else:
        add(
            checks,
            "language",
            "ja/ko subset resource coverage is measured",
            "missing",
            "locale-prune coverage audit TSV missing or unreadable",
            "run tools/r2-locale-prune-coverage-audit.py",
        )

    full_coverage = read_full_language_coverage()
    if len(full_coverage) == 12 and full_coverage[0] > 0:
        (
            full_stock_pkgs,
            full_stock_dirs,
            full_ja_ko_dirs,
            full_other_dirs,
            full_covered_pkgs,
            full_covered_dirs,
            full_remaining_pkgs,
            full_remaining_dirs,
            full_visible_pkgs,
            full_visible_dirs,
            full_apk_only_pkgs,
            full_apk_only_dirs,
        ) = full_coverage
        add(
            checks,
            "language",
            "full non-English/non-Chinese ROM language-resource coverage is measured",
            "proven_offline",
            (
                f"stock={full_stock_pkgs} packages/{full_stock_dirs} dirs; "
                f"ja_ko={full_ja_ko_dirs} dirs; other_non_target={full_other_dirs} dirs; "
                f"covered={full_covered_pkgs} packages/{full_covered_dirs} dirs; "
                f"remaining={full_remaining_pkgs} packages/{full_remaining_dirs} dirs; "
                f"visible_only={full_visible_pkgs} packages/{full_visible_dirs} dirs; "
                f"apk_only={full_apk_only_pkgs} packages/{full_apk_only_dirs} dirs"
            ),
            "remaining packages mean the English/Chinese-only physical prune goal is not complete",
        )
        add(
            checks,
            "language",
            "all non-English/non-Chinese ROM resources have been physically pruned",
            "not_achieved",
            f"{full_remaining_pkgs} packages and {full_remaining_dirs} non-English/non-Chinese dirs remain outside current ROM coverage",
            "continue staged package/resource pruning and live framework gates",
        )
    else:
        add(
            checks,
            "language",
            "full non-English/non-Chinese ROM language-resource coverage is measured",
            "missing",
            "language full-prune coverage audit TSV missing or unreadable",
            "run tools/r2-language-full-prune-coverage-audit.py",
        )

    status, evidence = report_has_pass(
        "hard-rom/inspect/tier1a-locale-prune-apks/verify-tier1a-locale-prune-apks-*.txt"
    )
    add(
        checks,
        "language",
        "tier1a minimal-exposure APK language hard-prune candidates verify offline",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.android.wallpaper.livepicker",
        "v0.14a-livewallpaperpicker-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.14a LiveWallpapersPicker APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.android.htmlviewer",
        "v0.14b-htmlviewer-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.14b HTMLViewer APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.android.dreams.basic",
        "v0.15a-basicdreams-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.15a BasicDreams APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.android.dreams.phototable",
        "v0.15b-phototable-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.15b PhotoTable APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.qualcomm.qti.confdialer",
        "v0.16a-confdialer-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.16a ConferenceDialer APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.android.simappdialog",
        "v0.18a-simappdialog-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.18a SimAppDialog APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.android.companiondevicemanager",
        "v0.19a-companiondevicemanager-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.19a CompanionDeviceManager APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.smartisanos.share.browser",
        "v0.20a-smartisan-share-browser-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.20a SmartisanShareBrowser APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = apk_only_candidate_status(
        "com.smartisanos.tracker",
        "v0.21a-tracker-locale-prune-apk",
    )
    add(
        checks,
        "language",
        "v0.21a TrackerSmartisan APK language hard-prune candidate exists",
        status,
        evidence,
        "APK proof is not ROM image or live boot proof" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-*.txt",
        [
            "package=com.android.wallpaper.livepicker",
            "resources_arsc_zip_method=stored",
            "bad_locale_chunk_count=0",
        ],
    )
    add(
        checks,
        "language",
        "v0.14a LiveWallpapersPicker APK verifies offline",
        status,
        evidence,
        "APK-only evidence remains outside ROM coverage until a matching image is built" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-*.txt",
        [
            "package=com.android.dreams.basic",
            "package=com.android.dreams.phototable",
            "package=com.android.wallpaper.livepicker",
            "package=com.android.htmlviewer",
            "package=com.android.printspooler",
            "package=com.qualcomm.qti.confdialer",
            "package=com.android.simappdialog",
            "package=com.android.companiondevicemanager",
            "package=com.smartisanos.share.browser",
            "package=com.smartisanos.tracker",
            "package=com.smartisanos.cleaner",
            "resources_arsc_zip_method=stored",
            "apk_only_candidate_count=11",
            "result=PASS_OFFLINE_APK_ONLY_BATCH",
        ],
    )
    add(
        checks,
        "language",
        "APK-only language hard-prune candidate batch verifies offline",
        status,
        evidence,
        "APK-only evidence remains outside ROM coverage until matching images are built" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "docs/research/v0.17-apk-only-promotion-audit.md",
        [
            "v0.17a-system-apk-only-locale-prune",
            "v0.17b-product-system_ext-apk-only-locale-prune",
            "v0.17-all-apk-only-locale-prune",
            "v0.24 promoted APK-only candidates in this audit: 1",
            "future APK-only candidates outside promoted images: 0",
            "com.qualcomm.qti.confdialer",
            "same_size_in_place_offline_proven_for_reference_inode",
            "same_size_inplace_proven_offline",
            "flashable_super_feasible_now",
        ],
    )
    add(
        checks,
        "language",
        "v0.17 APK-only ROM promotion audit maps partition ownership, space gates, and system_ext replacement risk",
        status,
        evidence,
        "planning proof only; built-image and live proofs are tracked separately" if status == "proven_offline" else "run tools/r2-v017-apk-only-promotion-audit.py",
    )

    v017a_scripts = [
        ROOT / "tools/r2-hardrom-build-v0.17a-system-apk-only-locale-prune.sh",
        ROOT / "tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh",
    ]
    missing_scripts = [str(path.relative_to(ROOT)) for path in v017a_scripts if not path.exists()]
    add(
        checks,
        "language",
        "v0.17a system APK-only ROM build and verification scripts exist",
        "missing" if missing_scripts else "proven_offline",
        "missing: " + ", ".join(missing_scripts)
        if missing_scripts
        else ", ".join(str(path.relative_to(ROOT)) for path in v017a_scripts),
        "scripts alone are not a flashable image" if not missing_scripts else "",
    )

    status, evidence = retired_local_artifact_status(
        "hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img",
        "d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5",
        "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
    )
    add(
        checks,
        "language",
        "v0.17a system APK-only language hard-prune system_b image exists or is intentionally retired",
        status,
        evidence,
        "system image is not the flash target; sparse super and live boot proof are separate gates"
        if status == "proven_offline"
        else ("rebuild only if the partition image itself must be reverified" if status == "retired_local" else ""),
    )

    status, evidence = retired_local_sparse_status(
        "hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img",
        "2ebe837f314c35b02d5bab3bdd21d8661cf85b8cba8816e99d8d9744d2f5100a",
        "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
    )
    add(
        checks,
        "language",
        "v0.17a standalone system APK-only sparse is either present or intentionally retired",
        status,
        evidence,
        "rebuild only if a smaller system-only live test is deliberately selected"
        if status == "retired_local"
        else ("not flashed or live-verified; explicit confirmation required before any flash" if status == "proven_offline" else ""),
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.17a-system-apk-only-locale-prune/verify-v0.17a-offline-image-*.txt",
        [
            "PASS: v0.17a offline image verification",
            "system/BasicDreams.apk\t2512094b9ac6ab042e97f37b74eb305b44e354a7fb341bcb5ceb4860dd7d0129",
            "system/HTMLViewer.apk\tfcfdd58b5fb92bfc05b6eba8cfc13759e3175d0e3db3cca7c129fec528282e35",
            "system/LiveWallpapersPicker.apk\tacf2131fe283817b61e1f99ebaceddc2973caaaaddae0e86cd070d20dbb10130",
            "system/PrintSpooler.apk\t3f7ee66118b7e5acab0a8aad71e8efcc086535887250da4af0e723c1b11c9d38",
            "system/SimAppDialog.apk\t3eb68792a4edecb94920915e7e50bd19a11da887a04c88eb7069293a4b905cad",
            "system_b\timage=d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5\t"
            "sparse_slice=d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5",
        ],
    )
    add(
        checks,
        "language",
        "v0.17a system APK-only image verifies offline",
        status,
        evidence,
        "offline image proof is not live boot proof" if status == "proven_offline" else "",
    )

    v017b_scripts = [
        ROOT / "tools/r2-hardrom-build-v0.17b-product-system_ext-apk-only-locale-prune.sh",
        ROOT / "tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh",
    ]
    missing_scripts = [str(path.relative_to(ROOT)) for path in v017b_scripts if not path.exists()]
    add(
        checks,
        "language",
        "v0.17b product/system_ext APK-only ROM build and verification scripts exist",
        "missing" if missing_scripts else "proven_offline",
        "missing: " + ", ".join(missing_scripts)
        if missing_scripts
        else ", ".join(str(path.relative_to(ROOT)) for path in v017b_scripts),
        "scripts alone are not a flashable image" if not missing_scripts else "",
    )

    status, evidence = retired_local_artifact_status(
        "hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img",
        "7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
        "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
    )
    add(
        checks,
        "language",
        "v0.17b product APK-only language hard-prune product_b image exists or is intentionally retired",
        status,
        evidence,
        "partition image is not live proof; sparse super and boot proof are separate gates"
        if status == "proven_offline"
        else ("rebuild only if the partition image itself must be reverified" if status == "retired_local" else ""),
    )

    status, evidence = retired_local_artifact_status(
        "hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img",
        "742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
        "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
    )
    add(
        checks,
        "language",
        "v0.17b system_ext APK-only language hard-prune system_ext_b image exists or is intentionally retired",
        status,
        evidence,
        "partition image is not live proof; sparse super and boot proof are separate gates"
        if status == "proven_offline"
        else ("rebuild only if the partition image itself must be reverified" if status == "retired_local" else ""),
    )

    status, evidence = retired_local_sparse_status(
        "hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img",
        "f7e1c18b1023714731c714557ee5ed6763426882901026f3e914d79469c20e45",
        "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
    )
    add(
        checks,
        "language",
        "v0.17b standalone product/system_ext APK-only sparse is either present or intentionally retired",
        status,
        evidence,
        "rebuild only if a smaller product/system_ext-only live test is deliberately selected"
        if status == "retired_local"
        else ("not flashed or live-verified; explicit confirmation required before any flash" if status == "proven_offline" else ""),
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune/verify-v0.17b-offline-image-*.txt",
        [
            "PASS: v0.17b offline image verification",
            "confdialer_same_size_scope=ok",
            "product/PhotoTable.apk\tc48ca2f6c3c95b1e0a7cbad3de2df3a7db5a78742a8cf77b3f847aa33f32a27f",
            "system_ext/ConferenceDialer.apk\te91d53b1cf1124896a3e8a0bfd577c8b1a9ef222435061bcfdafa93d3e3765c5",
            "product_b\timage=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8\t"
            "sparse_slice=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
            "system_ext_b\timage=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb\t"
            "sparse_slice=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
        ],
    )
    add(
        checks,
        "language",
        "v0.17b product/system_ext APK-only image verifies offline",
        status,
        evidence,
        "offline image proof is not live boot proof" if status == "proven_offline" else "",
    )

    v017all_scripts = [
        ROOT / "tools/r2-hardrom-build-v0.17-all-apk-only-locale-prune.sh",
        ROOT / "tools/r2-verify-v0.17-all-apk-only-locale-prune.sh",
    ]
    missing_scripts = [str(path.relative_to(ROOT)) for path in v017all_scripts if not path.exists()]
    add(
        checks,
        "language",
        "v0.17-all combined APK-only ROM build and verification scripts exist",
        "missing" if missing_scripts else "proven_offline",
        "missing: " + ", ".join(missing_scripts)
        if missing_scripts
        else ", ".join(str(path.relative_to(ROOT)) for path in v017all_scripts),
        "scripts alone are not a flashable image" if not missing_scripts else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
        "942da9469ccf9a24ff390912f26d76673415d2a500482d060a89c11847faf819",
    )
    add(
        checks,
        "language",
        "v0.17-all combined APK-only language hard-prune flashable sparse super exists",
        status,
        evidence,
        "not flashed or live-verified; explicit confirmation required before any flash" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.17-all-apk-only-locale-prune/verify-v0.17-all-offline-image-*.txt",
        [
            "PASS: v0.17-all offline image verification",
            "v0.17a_report_pass=ok",
            "v0.17b_report_pass=ok",
            "system_b\timage=d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5\t"
            "sparse_slice=d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5",
            "product_b\timage=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8\t"
            "sparse_slice=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
            "system_ext_b\timage=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb\t"
            "sparse_slice=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
        ],
    )
    add(
        checks,
        "language",
        "v0.17-all combined APK-only image verifies offline",
        status,
        evidence,
        "offline image proof is not live boot proof" if status == "proven_offline" else "",
    )

    v022_scripts = [
        ROOT / "tools/r2-hardrom-build-v0.22-all-apk-only-locale-prune.sh",
        ROOT / "tools/r2-verify-v0.22-all-apk-only-locale-prune.sh",
    ]
    missing_scripts = [str(path.relative_to(ROOT)) for path in v022_scripts if not path.exists()]
    add(
        checks,
        "language",
        "v0.22 combined APK-only ROM build and verification scripts exist",
        "missing" if missing_scripts else "proven_offline",
        "missing: " + ", ".join(missing_scripts)
        if missing_scripts
        else ", ".join(str(path.relative_to(ROOT)) for path in v022_scripts),
        "scripts alone are not a flashable image" if not missing_scripts else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img",
        "bd1670d117b124aa70220068a031b2a608b2373fab149da5020b1a71bc312e86",
    )
    add(
        checks,
        "language",
        "v0.22 combined APK-only language hard-prune flashable sparse super exists",
        status,
        evidence,
        "not flashed or live-verified; explicit confirmation required before any flash" if status == "proven_offline" else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/system-otatrust-v0.22-all-apk-only-locale-prune.img",
        "ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316",
    )
    add(
        checks,
        "language",
        "v0.22 combined APK-only system_b image exists",
        status,
        evidence,
        "system image is local verifier evidence; sparse super and live boot proof are separate gates"
        if status == "proven_offline"
        else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.22-all-apk-only-locale-prune/verify-v0.22-all-offline-image-*.txt",
        [
            "PASS: v0.22-all offline image verification",
            "system/BasicDreams.apk\t2512094b9ac6ab042e97f37b74eb305b44e354a7fb341bcb5ceb4860dd7d0129",
            "system/CompanionDeviceManager.apk\t07213606d5293d7fb363776afc8eab330c84ef31255cfb85fbd9e8d9b47ab2ad",
            "system/SmartisanShareBrowser.apk\td62475f2713e8454b8a9bf43fe7a3f0581aec1dd050baee0dc408c55dd8623e8",
            "system/TrackerSmartisan.apk\t9040314bd46e953e43827ab8d9102fe306a06c62516f0a19ec779ff078a1626c",
            "product/PhotoTable.apk\tc48ca2f6c3c95b1e0a7cbad3de2df3a7db5a78742a8cf77b3f847aa33f32a27f",
            "system_ext/ConferenceDialer.apk\te91d53b1cf1124896a3e8a0bfd577c8b1a9ef222435061bcfdafa93d3e3765c5",
            "system_b\timage=ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316\t"
            "sparse_slice=ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316",
            "product_b\timage=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8\t"
            "sparse_slice=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
            "system_ext_b\timage=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb\t"
            "sparse_slice=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
        ],
    )
    add(
        checks,
        "language",
        "v0.22 combined APK-only image verifies offline",
        status,
        evidence,
        "offline image proof is not live boot proof" if status == "proven_offline" else "",
    )

    v024_scripts = [
        ROOT / "tools/r2-hardrom-build-v0.24-cleaner-apk-only-locale-prune.sh",
        ROOT / "tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh",
    ]
    missing_scripts = [str(path.relative_to(ROOT)) for path in v024_scripts if not path.exists()]
    add(
        checks,
        "language",
        "v0.24 CleanerSmartisan APK-only ROM build and verification scripts exist",
        "missing" if missing_scripts else "proven_offline",
        "missing: " + ", ".join(missing_scripts)
        if missing_scripts
        else ", ".join(str(path.relative_to(ROOT)) for path in v024_scripts),
        "scripts alone are not a flashable image" if not missing_scripts else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img",
        "d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e",
    )
    add(
        checks,
        "language",
        "v0.24 CleanerSmartisan language hard-prune flashable sparse super exists",
        status,
        evidence,
        "live boot/package proof is tracked by the separate v0.24 device verifier gate"
        if status == "proven_offline"
        else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/system-otatrust-v0.24-cleaner-apk-only-locale-prune.img",
        "4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6",
    )
    add(
        checks,
        "language",
        "v0.24 CleanerSmartisan system_b image exists",
        status,
        evidence,
        "system image is local verifier evidence; sparse super and live boot proof are separate gates"
        if status == "proven_offline"
        else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-offline-image-*.txt",
        [
            "PASS: v0.24 offline image verification",
            "system/CleanerSmartisan.apk\td0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc",
            "held_stock_path=/system/app/CleanerSmartisan/.CleanerSmartisan.apk.smartisax-v024-stock-held",
            "system_b\timage=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6\t"
            "sparse_slice=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6",
            "product_b\timage=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8\t"
            "sparse_slice=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
            "system_ext_b\timage=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb\t"
            "sparse_slice=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
        ],
    )
    add(
        checks,
        "language",
        "v0.24 CleanerSmartisan image verifies offline",
        status,
        evidence,
        "offline image proof is complemented by the separate v0.24 device verifier gate"
        if status == "proven_offline"
        else "",
    )

    status, evidence = live_report_has_markers(
        "hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-device-*.txt",
        [
            "PASS: v0.24 device read-only verification",
            "sys.boot_completed=1",
            "ro.boot.slot_suffix=_b",
            "init.svc.bootanim=stopped",
            "uid=0(root)",
            "isKeyguardShowing=false",
            "system/BasicDreams.apk\tpackage=com.android.dreams.basic\t",
            "system/HTMLViewer.apk\tpackage=com.android.htmlviewer\t",
            "system/LiveWallpapersPicker.apk\tpackage=com.android.wallpaper.livepicker\t",
            "system/PrintSpooler.apk\tpackage=com.android.printspooler\t",
            "system/SimAppDialog.apk\tpackage=com.android.simappdialog\t",
            "system/CompanionDeviceManager.apk\tpackage=com.android.companiondevicemanager\t",
            "system/SmartisanShareBrowser.apk\tpackage=com.smartisanos.share.browser\t",
            "system/TrackerSmartisan.apk\tpackage=com.smartisanos.tracker\t",
            "system/CleanerSmartisan.apk\tpackage=com.smartisanos.cleaner\t",
            "product/PhotoTable.apk\tpackage=com.android.dreams.phototable\t",
            "system_ext/ConferenceDialer.apk\tpackage=com.qualcomm.qti.confdialer\t",
            "expected=d0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc\t"
            "actual=d0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc\tshadow=no",
            "expected=e91d53b1cf1124896a3e8a0bfd577c8b1a9ef222435061bcfdafa93d3e3765c5\t"
            "actual=e91d53b1cf1124896a3e8a0bfd577c8b1a9ef222435061bcfdafa93d3e3765c5\tshadow=no",
        ],
    )
    add(
        checks,
        "language",
        "v0.24 combined APK-only language hard-prune image has booted and verified live",
        status,
        evidence,
        "live proof covers the eleven promoted APK-only replacements; full English/Chinese hard-prune still has remaining packages"
        if status == "proven_live"
        else "after an authorized v0.24 flash and successful boot, run tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh --read-only",
    )

    v013_scripts = [
        ROOT / "tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh",
        ROOT / "tools/r2-verify-v0.13-tier1a-locale-prune.sh",
    ]
    missing_scripts = [str(path.relative_to(ROOT)) for path in v013_scripts if not path.exists()]
    add(
        checks,
        "language",
        "v0.13 Tier1a ROM build and verification scripts exist",
        "missing" if missing_scripts else "proven_offline",
        "missing: " + ", ".join(missing_scripts)
        if missing_scripts
        else ", ".join(str(path.relative_to(ROOT)) for path in v013_scripts),
        "scripts alone are not a flashable image" if not missing_scripts else "",
    )

    status, evidence = exists_with_hash(
        "hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img",
        "e77643153a9e03fc48b5e47a0841c6322dc390eb3381ff40a24e98ae03f905bb",
    )
    add(
        checks,
        "language",
        "v0.13 Tier1a language hard-prune system_b image exists",
        status,
        evidence,
        "system image is not directly flashable; sparse super still needs BUILD_SUPER=1" if status == "proven_offline" else "",
    )

    status, evidence = report_has_markers(
        "hard-rom/inspect/v0.13-tier1a-locale-prune/verify-v0.13-offline-system-image-*.txt",
        [
            "PASS: v0.13 offline system image verification",
            "system/Protips.apk\t12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d",
            "system/PrintRecommendationService.apk\t3d92952e74308a3402e0debb5a0ca0a1c909b5cc1990968ccfcbe73377ceb806",
            "system/OsuLogin.apk\t4e3059205ea37596aa9957f6b96a26517eeb09b2b7055d15344edf70e4dfb65c",
            "bad_locale_chunk_count=0",
        ],
    )
    add(
        checks,
        "language",
        "v0.13 Tier1a system_b image verifies offline",
        status,
        evidence,
        "offline system_b proof is not sparse-super proof or live boot proof" if status == "proven_offline" else "",
    )

    v013_super = ROOT / "hard-rom/build/super-otatrust-v0.13-tier1a-locale-prune-exact-current.sparse.img"
    add(
        checks,
        "language",
        "v0.13 Tier1a flashable sparse super exists",
        "missing" if not v013_super.exists() else "candidate_offline",
        str(v013_super.relative_to(ROOT)) if v013_super.exists() else "not built; BUILD_SUPER=1 not run",
        "build only when local free space is sufficient, then run --offline-image",
    )

    return checks


def write_tsv(checks: list[Check]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            ["area", "requirement", "status", "evidence", "gap"],
            delimiter="\t",
        )
        writer.writeheader()
        for check in checks:
            writer.writerow(check.__dict__)


def write_markdown(checks: list[Check]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    status_order = {
        "proven_live": 0,
        "proven_offline": 1,
        "candidate_offline": 2,
        "retired_local": 3,
        "missing": 4,
        "weak_or_failed": 5,
        "contradicted": 6,
        "not_achieved": 7,
    }
    lines = [
        "# System Modification Readiness Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit tracks readiness for two active goals: native",
        "system-level light/dark mode integration and English/Chinese-only ROM",
        "language hard-pruning. It does not modify APKs, images, partitions,",
        "the live device, or `/data`.",
        "",
        f"TSV output: `{OUT_TSV.relative_to(ROOT)}`",
        "",
        "## Summary",
        "",
    ]
    counts: dict[str, int] = {}
    for check in checks:
        counts[check.status] = counts.get(check.status, 0) + 1
    for status, count in sorted(counts.items(), key=lambda item: status_order.get(item[0], 99)):
        lines.append(f"- {status}: {count}")

    lines.extend(
        [
            "",
            "## Completion Boundary",
            "",
            "- Dark mode is not complete until SettingsSmartisan and SystemUI live no-op",
            "  gates pass, the current UiMode/QS state is captured, a combined exact-",
            "  current ROM image exists, it boots, UiMode/SystemUI functional writes",
            "  pass, and the remaining Settings row/QS editor UX is verified on device.",
            "- Language hard-prune is not complete while any non-English/non-Chinese",
            "  resource packages remain outside deletion or verified hard-prune coverage,",
            "  and v0.12/v0.10 have not passed live framework gates. Current live",
            "  locale/package-shadow state must also be captured before validating a",
            "  language build.",
            "",
        ]
    )

    for area in ("rollback", "dark_mode", "language"):
        area_rows = [check for check in checks if check.area == area]
        lines.extend([f"## {area}", "", "| status | requirement | evidence | gap |", "| --- | --- | --- | --- |"])
        for check in sorted(area_rows, key=lambda item: status_order.get(item.status, 99)):
            lines.append(
                "| "
                + " | ".join(
                    cell.replace("|", "\\|")
                    for cell in (check.status, check.requirement, check.evidence, check.gap)
                )
                + " |"
            )
        lines.append("")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    checks = audit()
    write_tsv(checks)
    write_markdown(checks)
    print(f"checks={len(checks)}")
    for status in sorted({check.status for check in checks}):
        print(f"{status}={sum(1 for check in checks if check.status == status)}")
    print(f"tsv={OUT_TSV.relative_to(ROOT)}")
    print(f"markdown={OUT_MD.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
