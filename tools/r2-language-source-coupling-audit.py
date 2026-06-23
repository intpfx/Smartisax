#!/usr/bin/env python3
"""Audit Smartisan language/locale source coupling from static sources.

This script is read-only. It connects the visible language picker, framework
AssetManager locale exposure, resource fallback, non-UI locale users, and the
current hard-prune gates so language pruning is not treated as a simple string
or overlay edit.
"""

from __future__ import annotations

import csv
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/language-source-coupling-audit.tsv"
OUT_MD = ROOT / "docs/research/language-source-coupling-audit.md"

SETTINGS_LOCALE_PICKER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "sources/com/android/settings/inputmethod/LocalePickerFragment.java"
)
SETTINGS_RES_DIR = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "resources/res"
)
FRAMEWORK_LOCALE_PICKER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/com/android/internal/app/LocalePicker.java"
)
ASSET_MANAGER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/android/content/res/AssetManager.java"
)
RESOURCES_MANAGER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/android/app/ResourcesManager.java"
)
RESOURCES_IMPL = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/android/content/res/ResourcesImpl.java"
)
FRAMEWORK_ARRAYS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework-res.apk"
    / "resources/res/values/arrays.xml"
)
FRAMEWORK_RES_DIR = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework-res.apk/resources/res"
)
SM_FRAMEWORK_RES_DIR = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework-smartisanos-res__framework-smartisanos-res.apk/resources/res"
)
DISPLAY_CUTOUT_OVERLAY_MANIFEST = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/product__overlay__DisplayCutoutEmulationCorner__DisplayCutoutEmulationCornerOverlay.apk/resources/AndroidManifest.xml"
)
DISPLAY_CUTOUT_OVERLAY_RES_DIR = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/product__overlay__DisplayCutoutEmulationCorner__DisplayCutoutEmulationCornerOverlay.apk/resources/res"
)
MCC_TABLE = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__ContactsSmartisan__ContactsSmartisan.apk"
    / "sources/com/android/internal/telephony/MccTable.java"
)
ICC_RECORDS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__ContactsSmartisan__ContactsSmartisan.apk"
    / "sources/com/android/internal/telephony/uicc/IccRecords.java"
)
RUIM_RECORDS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__ContactsSmartisan__ContactsSmartisan.apk"
    / "sources/com/android/internal/telephony/uicc/RuimRecords.java"
)
COVERAGE_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv"
FULL_COVERAGE_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv"

COVERED_CANDIDATE_STATUSES = {
    "removed_in_v0.2_v0.4",
    "pruned_in_v0.10_candidate",
    "pruned_in_v0.13_system_image",
    "pruned_in_v0.17a_system_image",
    "pruned_in_v0.17b_product_system_ext_image",
    "pruned_in_v0.22_all_system_image",
    "pruned_in_v0.24_system_image",
}


@dataclass(frozen=True)
class Finding:
    area: str
    target: str
    status: str
    evidence: str
    implication: str
    next_gate: str


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def line_for(text: str, marker: str) -> int | None:
    for idx, line in enumerate(text.splitlines(), 1):
        if marker in line:
            return idx
    return None


def marker_summary(text: str, markers: list[str]) -> tuple[list[str], list[str]]:
    present: list[str] = []
    missing: list[str] = []
    for marker in markers:
        line = line_for(text, marker)
        if line is None:
            missing.append(marker)
        else:
            present.append(f"{marker}@L{line}")
    return present, missing


def latest_report(pattern: str) -> Path | None:
    reports = sorted(ROOT.glob(pattern))
    return reports[-1] if reports else None


def add(
    findings: list[Finding],
    area: str,
    target: str,
    status: str,
    evidence: str,
    implication: str,
    next_gate: str = "",
) -> None:
    findings.append(Finding(area, target, status, evidence, implication, next_gate))


def check_markers(
    findings: list[Finding],
    area: str,
    target: str,
    path: Path,
    markers: list[str],
    ok_status: str,
    implication: str,
    next_gate: str = "",
) -> None:
    text = read_text(path)
    if not text:
        add(findings, area, target, "missing_source", f"{rel(path)} is missing", implication, next_gate)
        return
    present, missing = marker_summary(text, markers)
    if missing:
        add(
            findings,
            area,
            target,
            "weak_or_changed",
            f"{rel(path)} missing: {', '.join(missing)}; present: {', '.join(present)}",
            implication,
            next_gate,
        )
    else:
        add(findings, area, target, ok_status, f"{rel(path)}: {', '.join(present)}", implication, next_gate)


def check_report_markers(
    findings: list[Finding],
    area: str,
    target: str,
    pattern: str,
    markers: list[str],
    ok_status: str,
    implication: str,
    next_gate: str = "",
) -> None:
    report = latest_report(pattern)
    if report is None:
        add(findings, area, target, "missing_report", f"no report matches {pattern}", implication, next_gate)
        return
    text = read_text(report)
    present, missing = marker_summary(text, markers)
    if missing:
        add(
            findings,
            area,
            target,
            "weak_or_failed",
            f"{rel(report)} missing: {', '.join(missing)}; present: {', '.join(present)}",
            implication,
            next_gate,
        )
    else:
        add(findings, area, target, ok_status, f"{rel(report)}: {', '.join(present)}", implication, next_gate)


def locale_dirs(path: Path) -> list[str]:
    if not path.exists():
        return []
    return sorted(
        child.name
        for child in path.iterdir()
        if child.is_dir()
        and (
            child.name in {"values", "raw"}
            or child.name.startswith("values-")
            or child.name.startswith("raw-")
        )
    )


def language_status_for_dirs(path: Path) -> tuple[str, str]:
    dirs = locale_dirs(path)
    if not dirs:
        return "missing_source", f"{rel(path)} has no decoded resource dirs"
    ja_ko = [name for name in dirs if "-ja" in name or "-ko" in name]
    zh = [name for name in dirs if "-zh" in name]
    return (
        "stock_locale_resources_present" if ja_ko else "stock_no_ja_ko_dirs",
        f"{rel(path)} ja/ko={len(ja_ko)} [{', '.join(ja_ko)}]; zh={len(zh)} [{', '.join(zh[:8])}]",
    )


def coverage_summary() -> tuple[dict[str, int], str]:
    if not COVERAGE_TSV.exists():
        return {}, f"{rel(COVERAGE_TSV)} is missing"
    with COVERAGE_TSV.open(encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    status_counts = Counter(row.get("coverage_status", "") for row in rows)
    stock_pkgs = len(rows)
    stock_dirs = sum(int(row.get("ja_ko_dirs") or 0) for row in rows)
    covered = [
        row
        for row in rows
        if row.get("coverage_status") in COVERED_CANDIDATE_STATUSES
    ]
    visible = [row for row in rows if row.get("coverage_status") == "visible_filter_only_v0.7"]
    remaining = [row for row in rows if row.get("coverage_status") == "remaining_after_v0.4_v0.10"]
    apk_only = [row for row in remaining if row.get("apk_only_variant")]
    values = {
        "stock_pkgs": stock_pkgs,
        "stock_dirs": stock_dirs,
        "covered_pkgs": len(covered),
        "covered_dirs": sum(int(row.get("ja_ko_dirs") or 0) for row in covered),
        "visible_pkgs": len(visible),
        "visible_dirs": sum(int(row.get("ja_ko_dirs") or 0) for row in visible),
        "apk_only_pkgs": len(apk_only),
        "apk_only_dirs": sum(int(row.get("ja_ko_dirs") or 0) for row in apk_only),
        "remaining_pkgs": len(remaining),
        "remaining_dirs": sum(int(row.get("ja_ko_dirs") or 0) for row in remaining),
        "v010_pkgs": status_counts.get("pruned_in_v0.10_candidate", 0),
        "v013_pkgs": status_counts.get("pruned_in_v0.13_system_image", 0),
        "v017a_pkgs": status_counts.get("pruned_in_v0.17a_system_image", 0),
        "v017b_pkgs": status_counts.get("pruned_in_v0.17b_product_system_ext_image", 0),
        "v022_pkgs": status_counts.get("pruned_in_v0.22_all_system_image", 0),
        "v024_pkgs": status_counts.get("pruned_in_v0.24_system_image", 0),
    }
    evidence = (
        f"{rel(COVERAGE_TSV)}: stock={values['stock_pkgs']} packages/{values['stock_dirs']} dirs; "
        f"covered={values['covered_pkgs']} packages/{values['covered_dirs']} dirs; "
        f"visible_filter_only={values['visible_pkgs']} packages/{values['visible_dirs']} dirs; "
        f"apk_only_pending={values['apk_only_pkgs']} packages/{values['apk_only_dirs']} dirs; "
        f"remaining={values['remaining_pkgs']} packages/{values['remaining_dirs']} dirs; "
        f"v0.10={values['v010_pkgs']} packages; v0.13={values['v013_pkgs']} packages; "
        f"v0.17a={values['v017a_pkgs']} packages; v0.17b={values['v017b_pkgs']} packages; "
        f"v0.22={values['v022_pkgs']} packages; v0.24={values['v024_pkgs']} packages"
    )
    return values, evidence


def full_coverage_summary() -> tuple[dict[str, int], str]:
    if not FULL_COVERAGE_TSV.exists():
        return {}, f"{rel(FULL_COVERAGE_TSV)} is missing"
    with FULL_COVERAGE_TSV.open(encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    stock_pkgs = len(rows)
    stock_dirs = sum(int(row.get("non_target_dirs") or 0) for row in rows)
    ja_ko_dirs = sum(int(row.get("ja_ko_dirs") or 0) for row in rows)
    other_dirs = sum(int(row.get("other_locale_dirs") or 0) for row in rows)
    covered = [
        row
        for row in rows
        if row.get("coverage_status") in COVERED_CANDIDATE_STATUSES
    ]
    remaining = [row for row in rows if row.get("coverage_status") == "remaining_after_current_candidates"]
    visible = [row for row in rows if row.get("coverage_status") == "visible_filter_only_v0.7"]
    apk_only = [row for row in remaining if row.get("apk_only_variant")]
    status_counts = Counter(row.get("coverage_status", "") for row in rows)
    values = {
        "stock_pkgs": stock_pkgs,
        "stock_dirs": stock_dirs,
        "ja_ko_dirs": ja_ko_dirs,
        "other_dirs": other_dirs,
        "covered_pkgs": len(covered),
        "covered_dirs": sum(int(row.get("non_target_dirs") or 0) for row in covered),
        "remaining_pkgs": len(remaining),
        "remaining_dirs": sum(int(row.get("non_target_dirs") or 0) for row in remaining),
        "visible_pkgs": len(visible),
        "visible_dirs": sum(int(row.get("non_target_dirs") or 0) for row in visible),
        "apk_only_pkgs": len(apk_only),
        "apk_only_dirs": sum(int(row.get("non_target_dirs") or 0) for row in apk_only),
        "v010_pkgs": status_counts.get("pruned_in_v0.10_candidate", 0),
        "v013_pkgs": status_counts.get("pruned_in_v0.13_system_image", 0),
        "v017a_pkgs": status_counts.get("pruned_in_v0.17a_system_image", 0),
        "v017b_pkgs": status_counts.get("pruned_in_v0.17b_product_system_ext_image", 0),
        "v022_pkgs": status_counts.get("pruned_in_v0.22_all_system_image", 0),
        "v024_pkgs": status_counts.get("pruned_in_v0.24_system_image", 0),
    }
    evidence = (
        f"{rel(FULL_COVERAGE_TSV)}: stock={values['stock_pkgs']} packages/{values['stock_dirs']} dirs; "
        f"ja_ko={values['ja_ko_dirs']} dirs; other_non_target={values['other_dirs']} dirs; "
        f"covered={values['covered_pkgs']} packages/{values['covered_dirs']} dirs; "
        f"visible_filter_only={values['visible_pkgs']} packages/{values['visible_dirs']} dirs; "
        f"apk_only_pending={values['apk_only_pkgs']} packages/{values['apk_only_dirs']} dirs; "
        f"remaining={values['remaining_pkgs']} packages/{values['remaining_dirs']} dirs; "
        f"v0.10={values['v010_pkgs']} packages; v0.13={values['v013_pkgs']} packages; "
        f"v0.17a={values['v017a_pkgs']} packages; v0.17b={values['v017b_pkgs']} packages; "
        f"v0.22={values['v022_pkgs']} packages; v0.24={values['v024_pkgs']} packages"
    )
    return values, evidence


def audit() -> list[Finding]:
    findings: list[Finding] = []

    check_markers(
        findings,
        "visible_picker",
        "Smartisan Settings language picker enumerates system AssetManager locales",
        SETTINGS_LOCALE_PICKER,
        [
            "Resources.getSystem().getAssets().getLocales()",
            "Arrays.sort(locales)",
            "if (str.length() == 5)",
            "new Locale(strSubstring, str.substring(3, 5))",
            "LocalePicker.updateLocales(localeList)",
        ],
        "stock_visible_picker_coupled_to_assets",
        "Visible Smartisan languages come from system AssetManager locale configs, not only a resource array.",
        "v0.7 can hide ja_JP/ko_KR visually, but framework resources still need hard-prune gates.",
    )

    check_markers(
        findings,
        "visible_picker",
        "Smartisan Settings language change path also checks locale-specific font scale arrays",
        SETTINGS_LOCALE_PICKER,
        [
            "updateFontScale(locale)",
            "createConfigurationContext(configuration).getResources().getStringArray(R.array.font_scale_values)",
            "configuration.setLocale(locale)",
            "setFontSize(fFloatValue)",
        ],
        "settings_locale_resource_coupling",
        "Pruning SettingsSmartisan resources must preserve English/Chinese font-scale resources and fallback behavior.",
    )

    status, evidence = language_status_for_dirs(SETTINGS_RES_DIR)
    add(
        findings,
        "visible_picker",
        "stock SettingsSmartisan still contains ja/ko locale resources",
        status,
        evidence,
        "v0.7 is a visible-list filter only; it is not a SettingsSmartisan resource prune.",
        "A future SettingsSmartisan resource prune requires the Settings core APK live gate.",
    )

    check_markers(
        findings,
        "framework",
        "AOSP LocalePicker also reads system AssetManager locales",
        FRAMEWORK_LOCALE_PICKER,
        [
            "return Resources.getSystem().getAssets().getLocales()",
            "getSupportedLocales(Context context)",
            "R.array.supported_locales",
            "public static void updateLocales(LocaleList locales)",
            "am.updatePersistentConfiguration(config)",
        ],
        "stock_framework_picker_coupled_to_assets",
        "AOSP paths expose both supported_locales and raw asset locales; overlays cannot be the only mechanism.",
    )

    check_markers(
        findings,
        "framework",
        "system AssetManager is built from framework-res, Smartisan framework-res, and immutable android overlays",
        ASSET_MANAGER,
        [
            "FRAMEWORK_APK_PATH = \"/system/framework/framework-res.apk\"",
            "SM_FRAMEWORK_APK_PATH = \"/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk\"",
            "createSystemAssetsInZygoteLocked(boolean reinitialize, String frameworkPath)",
            "ApkAssets.loadFromPath(frameworkPath, 1)",
            "ApkAssets.loadFromPath(SM_FRAMEWORK_APK_PATH, 1)",
            "createImmutableFrameworkIdmapsInZygote()",
            "nativeGetLocales(this.mObject, false)",
        ],
        "stock_system_asset_source_mapped",
        "To stop framework AssetManager from exposing ja/ko, framework resource APKs and android static overlays must be handled.",
        "v0.12 framework-res no-op live gate should precede v0.10 language prune.",
    )

    check_markers(
        findings,
        "framework",
        "per-package ResourcesManager adds app resources, split resources, libs, and overlays",
        RESOURCES_MANAGER,
        [
            "protected AssetManager createAssetManager(ResourcesKey key)",
            "builder.addApkAssets(loadApkAssets(key.mResDir, false, false))",
            "builder.addApkAssets(loadApkAssets(splitResDir, false, false))",
            "builder.addApkAssets(loadApkAssets(idmapPath, false, true))",
            "return builder.build()",
        ],
        "stock_package_asset_source_mapped",
        "App-level ja/ko resource dirs remain independently visible to each package until those APKs are pruned or removed.",
    )

    check_markers(
        findings,
        "framework",
        "ResourcesImpl uses available asset locales for best-locale fallback and native configuration",
        RESOURCES_IMPL,
        [
            "this.mAssets.getNonSystemLocales()",
            "this.mAssets.getLocales()",
            "getFirstMatchWithEnglishSupported(availableLocales)",
            "this.mConfiguration.setLocales(new LocaleList(bestLocale, locales))",
            "this.mAssets.setConfiguration(",
        ],
        "stock_resource_fallback_coupled_to_assets",
        "Locale pruning must preserve coherent English/Chinese fallback; broken partial pruning can affect runtime resource selection.",
    )

    check_markers(
        findings,
        "framework_resources",
        "stock framework-res supported_locales and special locale arrays still include non-target locales",
        FRAMEWORK_ARRAYS,
        [
            "<array name=\"special_locale_codes\">",
            "<array name=\"special_locale_names\">",
            "<array name=\"supported_locales\">",
            "<item>en-US</item>",
            "<item>ja-JP</item>",
            "<item>ko-KR</item>",
            "<item>zh-Hans-CN</item>",
            "<item>zh-Hant-TW</item>",
        ],
        "stock_framework_locale_arrays_broad",
        "supported_locales must be narrowed for AOSP-visible lists, but that alone does not remove compiled locale configs.",
        "The v0.10 framework/product candidate already narrows the framework arrays offline.",
    )

    for target, path in [
        ("stock framework-res resource dirs include ja/ko and zh configs", FRAMEWORK_RES_DIR),
        ("stock framework-smartisanos-res resource dirs include ja/ko and zh configs", SM_FRAMEWORK_RES_DIR),
        ("stock product android static overlay resource dirs include ja/ko and zh configs", DISPLAY_CUTOUT_OVERLAY_RES_DIR),
    ]:
        status, evidence = language_status_for_dirs(path)
        add(
            findings,
            "framework_resources",
            target,
            status,
            evidence,
            "These compiled resource configs are why overlay-only language pruning is incomplete.",
            "v0.10 covers these framework/product targets offline; live framework gate still missing.",
        )

    check_markers(
        findings,
        "framework_resources",
        "DisplayCutout overlay is a static android overlay",
        DISPLAY_CUTOUT_OVERLAY_MANIFEST,
        [
            "android:targetPackage=\"android\"",
            "android:category=\"com.android.internal.display_cutout_emulation\"",
            "android:hasCode=\"false\"",
        ],
        "stock_android_static_overlay_mapped",
        "Static overlays targeting android participate in system resources and must follow framework/resource gates.",
    )

    check_markers(
        findings,
        "non_ui_locale_users",
        "telephony MCC locale helper checks context asset locales",
        MCC_TABLE,
        [
            "context.getAssets().getLocales()",
            "Locale.forLanguageTag",
            "getLocaleForLanguageCountry",
        ],
        "stock_non_ui_locale_coupling",
        "Locale pruning can affect SIM/MCC locale matching, not only the Settings UI.",
    )

    check_markers(
        findings,
        "non_ui_locale_users",
        "UICC/SIM language code handling checks context asset locales",
        ICC_RECORDS,
        [
            "String[] locales = this.mContext.getAssets().getLocales()",
            "findBestLanguage",
            "getSimLanguage()",
        ],
        "stock_non_ui_locale_coupling",
        "Keep-language policy must still allow SIM language fallback into English/Chinese.",
    )

    check_markers(
        findings,
        "non_ui_locale_users",
        "RUIM language helper checks context asset locales",
        RUIM_RECORDS,
        [
            "String[] locales = context.getAssets().getLocales()",
            "getAssetLanguages(Context context)",
            "strArr[i] = str.substring(0, iIndexOf)",
        ],
        "stock_non_ui_locale_coupling",
        "Language pruning should be validated beyond the visible Settings picker.",
    )

    check_report_markers(
        findings,
        "candidate",
        "v0.7 SettingsSmartisan visible ja/ko filter is proven offline",
        "hard-rom/inspect/v0.7-locale-filter/verify-settingssmartisan-locale-filter-apk-*.txt",
        [
            "SettingsSmartisan: only classes.dex changed",
            "LocalePickerFragment.constructAdapter ja_JP/ko_KR skip logic verified",
            "SHA-256 digest error for classes.dex",
            "PASS",
        ],
        "candidate_proven_offline",
        "This proves only the visible Settings list filter; it does not hard-prune resources.",
        "Requires v0.25 current-base SettingsSmartisan no-op live gate before behavior flash; language behavior stays behind the dark-mode priority line.",
    )

    check_report_markers(
        findings,
        "candidate",
        "v0.10 framework/product language hard-prune image is proven offline",
        "hard-rom/inspect/v0.10-framework-locale-prune/verify-v0.10-offline-image-*.txt",
        [
            "signature_boundary=ok",
            "system/framework-res.apk",
            "system/framework-smartisanos-res.apk",
            "bad_locale_chunk_count=0",
            "system_b\timage=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351",
            "product_b\timage=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2",
        ],
        "candidate_proven_offline",
        "v0.10 is the first complete framework/product locale hard-prune image, but it is RED early-boot and not live-proof.",
        "Flash only after v0.12 framework-res no-op live gate and explicit confirmation.",
    )

    check_report_markers(
        findings,
        "candidate",
        "v0.13 Tier1a package language hard-prune system image is proven offline",
        "hard-rom/inspect/v0.13-tier1a-locale-prune/verify-v0.13-offline-system-image-*.txt",
        [
            "system/Protips.apk",
            "system/PrintRecommendationService.apk",
            "system/OsuLogin.apk",
            "bad_locale_chunk_count=0",
            "result=PASS",
        ],
        "candidate_proven_offline",
        "v0.13 proves low-exposure package pruning at system_b image level; it is not a flashable sparse super yet.",
        "Build sparse super only after freeing space, then verify --offline-image before any flash request.",
    )

    check_report_markers(
        findings,
        "candidate",
        "v0.14a LiveWallpapersPicker APK-only language hard-prune candidate is proven offline",
        "hard-rom/inspect/v0.14a-livewallpaperpicker-locale-prune-apk/verify-v0.14a-livewallpaperpicker-locale-prune-apk-*.txt",
        [
            "result=PASS_OFFLINE_APK_ONLY",
            "android_manifest_cmp=0",
            "classes_dex_cmp=0",
            "resources_arsc_cmp=1",
            "bad_locale_chunk_count=0",
            "keytool_error=java.lang.SecurityException: SHA-256 digest error for resources.arsc",
        ],
        "candidate_proven_offline",
        "v0.14a proves the next low-exposure app-level resource prune as APK-only evidence; it is not ROM coverage yet.",
        "Build a matching system_b/sparse image only after local free space is sufficient.",
    )

    check_report_markers(
        findings,
        "candidate",
        "APK-only language hard-prune candidate batch is proven offline",
        "hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-*.txt",
        [
            "package=com.android.dreams.basic",
            "package=com.android.dreams.phototable",
            "package=com.android.companiondevicemanager",
            "package=com.android.wallpaper.livepicker",
            "package=com.android.htmlviewer",
            "package=com.android.printspooler",
            "package=com.qualcomm.qti.confdialer",
            "package=com.android.simappdialog",
            "package=com.smartisanos.share.browser",
            "package=com.smartisanos.tracker",
            "package=com.smartisanos.cleaner",
            "apk_only_candidate_count=11",
            "classes_and_manifest=unchanged",
            "resources_arsc=changed",
            "bad_locale_chunk_count=0",
            "result=PASS_OFFLINE_APK_ONLY_BATCH",
        ],
        "candidate_proven_offline",
        "The APK-only verifier proves all manifest-listed APK-only resource-prune candidates as a batch; v0.24 promotes the current system_b pending candidate into ROM image evidence, but APK-only proof by itself remains separate from live boot proof.",
        "Use the v0.24 image verifier and live flash gates before treating this as device behavior.",
    )

    check_report_markers(
        findings,
        "candidate",
        "v0.24 CleanerSmartisan ROM promotion image is proven offline",
        "hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-offline-image-*.txt",
        [
            "PASS: v0.24 offline image verification",
            "system/CleanerSmartisan.apk\td0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc",
            "held_stock_path=/system/app/CleanerSmartisan/.CleanerSmartisan.apk.smartisax-v024-stock-held",
            "system_b\timage=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6",
            "product_b\timage=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
            "system_ext_b\timage=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
        ],
        "candidate_proven_offline",
        "v0.24 proves CleanerSmartisan resource pruning at system_b image and sparse-super level, but it is not live boot proof.",
        "Flash only after explicit confirmation and run the live verifier gates.",
    )

    values, evidence = coverage_summary()
    if values:
        add(
            findings,
            "coverage",
            "ja/ko subset hard-prune coverage is measured and still incomplete",
            "coverage_measured_incomplete",
            evidence,
            "The ja/ko subset is a useful stage metric but not the full English/Chinese-only target.",
            "Continue staged package pruning and live framework gates.",
        )
    else:
        add(
            findings,
            "coverage",
            "ja/ko subset hard-prune coverage is measured and still incomplete",
            "missing_report",
            evidence,
            "Run tools/r2-locale-prune-coverage-audit.py.",
        )

    full_values, full_evidence = full_coverage_summary()
    if full_values:
        add(
            findings,
            "coverage",
            "full non-English/non-Chinese hard-prune coverage is measured and still incomplete",
            "full_coverage_measured_incomplete",
            full_evidence,
            "The ROM is not English/Chinese-only while remaining non-target language resources are outside deletion or hard-prune coverage.",
            "Continue staged package pruning, APK-to-ROM promotion, and live framework gates.",
        )
    else:
        add(
            findings,
            "coverage",
            "full non-English/non-Chinese hard-prune coverage is measured and still incomplete",
            "missing_report",
            full_evidence,
            "Run tools/r2-language-full-prune-coverage-audit.py.",
        )

    for target, pattern, gate in [
        (
            "SettingsSmartisan no-op live gate for visible language filter",
            "hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-*.txt",
            "Flash v0.25 only after explicit confirmation, then run the live verifier with SETTINGS_NOOP_VARIANT=v0.25-settings-noop-on-v0.24.",
        ),
        (
            "framework-res no-op live gate before v0.10",
            "hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-device-*.txt",
            "Flash v0.12 only after explicit confirmation, then run the live verifier.",
        ),
    ]:
        report = latest_report(pattern)
        if report is None:
            add(
                findings,
                "live_gate",
                target,
                "missing_live_gate",
                f"no report matches {pattern}",
                "Live PackageManager/boot/resource behavior is still unproven.",
                gate,
            )
        else:
            text = read_text(report)
            status = "proven_live" if "PASS" in text else "weak_or_failed"
            add(
                findings,
                "live_gate",
                target,
                status,
                f"{rel(report)} {'contains PASS' if status == 'proven_live' else 'does not contain PASS'}",
                "This gate controls whether the corresponding language behavior/resource patch can be flashed next.",
            )

    v013_super = ROOT / "hard-rom/build/super-otatrust-v0.13-tier1a-locale-prune-exact-current.sparse.img"
    add(
        findings,
        "live_gate",
        "v0.13 Tier1a flashable sparse super exists",
        "candidate_offline" if v013_super.exists() else "missing_rom_image",
        rel(v013_super) if v013_super.exists() else "not built; BUILD_SUPER=1 not run",
        "v0.13 has a verified system_b image but no flashable sparse super.",
        "Build only when local free space is sufficient, then run --offline-image.",
    )

    return findings


def write_tsv(findings: list[Finding]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            ["area", "target", "status", "evidence", "implication", "next_gate"],
            delimiter="\t",
        )
        writer.writeheader()
        for finding in findings:
            writer.writerow(finding.__dict__)


def write_markdown(findings: list[Finding]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    status_order = {
        "stock_visible_picker_coupled_to_assets": 0,
        "settings_locale_resource_coupling": 1,
        "stock_framework_picker_coupled_to_assets": 2,
        "stock_system_asset_source_mapped": 3,
        "stock_package_asset_source_mapped": 4,
        "stock_resource_fallback_coupled_to_assets": 5,
        "stock_framework_locale_arrays_broad": 6,
        "stock_android_static_overlay_mapped": 7,
        "stock_locale_resources_present": 8,
        "stock_non_ui_locale_coupling": 9,
        "candidate_proven_offline": 10,
        "coverage_measured_incomplete": 11,
        "full_coverage_measured_incomplete": 12,
        "missing_live_gate": 13,
        "missing_rom_image": 14,
        "candidate_offline": 15,
        "proven_live": 16,
        "stock_no_ja_ko_dirs": 17,
        "missing_source": 18,
        "missing_report": 19,
        "weak_or_changed": 20,
        "weak_or_failed": 21,
    }
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.status] = counts.get(finding.status, 0) + 1

    lines = [
        "# Language Source Coupling Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit checks the static Smartisan OS 8.5.3 source",
        "knowledge base and existing language-prune evidence. It does not modify",
        "APKs, images, the live device, partitions, or `/data`.",
        "",
        f"TSV output: `{OUT_TSV.relative_to(ROOT)}`",
        "",
        "## Summary",
        "",
    ]
    for status, count in sorted(counts.items(), key=lambda item: status_order.get(item[0], 99)):
        lines.append(f"- {status}: {count}")

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- Smartisan Settings and AOSP locale paths both depend on system AssetManager locales.",
            "- The system AssetManager is built from framework-res, framework-smartisanos-res, and immutable android overlays.",
            "- Per-package resources still contribute their own locale configs through ResourcesManager.",
            "- Telephony/SIM locale code also checks asset locales, so validation cannot stop at the visible Settings list.",
            "- The current hard-prune route is correctly split into visible filter, framework/product prune gates, and staged package resource pruning.",
            "",
        ]
    )

    for area in (
        "visible_picker",
        "framework",
        "framework_resources",
        "non_ui_locale_users",
        "candidate",
        "coverage",
        "live_gate",
    ):
        rows = [finding for finding in findings if finding.area == area]
        if not rows:
            continue
        lines.extend([f"## {area}", "", "| status | target | evidence | implication | next gate |", "| --- | --- | --- | --- | --- |"])
        for finding in sorted(rows, key=lambda item: status_order.get(item.status, 99)):
            lines.append(
                "| "
                + " | ".join(
                    cell.replace("|", "\\|")
                    for cell in (
                        finding.status,
                        finding.target,
                        finding.evidence,
                        finding.implication,
                        finding.next_gate,
                    )
                )
                + " |"
            )
        lines.append("")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    findings = audit()
    write_tsv(findings)
    write_markdown(findings)
    print(f"findings={len(findings)}")
    for status in sorted({finding.status for finding in findings}):
        print(f"{status}={sum(1 for finding in findings if finding.status == status)}")
    print(f"tsv={OUT_TSV.relative_to(ROOT)}")
    print(f"markdown={OUT_MD.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
