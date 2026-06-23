#!/usr/bin/env python3
"""Audit Smartisan native dark-mode coupling points from static sources.

This script is read-only. It checks the stock ROM decompilation, existing
v0.11 APK semantic evidence, and live-gate report presence so the native
dark-mode route is documented as reproducible evidence instead of memory.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/darkmode-source-coupling-audit.tsv"
OUT_MD = ROOT / "docs/research/darkmode-source-coupling-audit.md"

SERVICE = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar"
    / "sources/com/android/server/UiModeManagerService.java"
)
SETTINGS_BRIGHTNESS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "sources/com/android/settings/BrightnessSettingsFragment.java"
)
SETTINGS_WIDGET_FACTORY = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "sources/com/android/settings/notificationcustom/QuickWidgetFactory.java"
)
SETTINGS_NOTIFICATION_CUSTOM_VIEW = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "sources/com/android/settings/widget/NotificationCustomView.java"
)
SYSTEMUI_QS_HOST = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk"
    / "sources/com/android/systemui/statusbar/phone/QSTileHost.java"
)
SETTINGS_PROVIDER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/SettingsProvider.java"
)
SETTINGS_PROVIDER_DB = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/DatabaseHelper.java"
)
SETTINGS_PROVIDER_STRINGS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "resources/res/values/strings.xml"
)
SETTINGS_BACKUP_AGENT = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/SettingsBackupAgent.java"
)
SMARTISAN_SETTINGS_UTIL = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar"
    / "sources/smartisanos/util/SettingsUtil.java"
)
SMARTISAN_SETTINGS_SMT = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/smartisanos/api/SettingsSmt.java"
)
SETTINGS_STRINGS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "resources/res/values/strings.xml"
)
SETTINGS_PUBLIC = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "resources/res/values/public.xml"
)
SYSTEMUI_COLORS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk"
    / "resources/res/values/colors.xml"
)
SYSTEMUI_PUBLIC = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk"
    / "resources/res/values/public.xml"
)
V011_REPORT_PATTERN = "hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-*.txt"
V011_EVIDENCE_DIR_PATTERN = "hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-*"
V011_DEVICE_REPORT_PATTERN = "hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-*.txt"
V011_FUNCTIONAL_REPORT_PATTERN = "hard-rom/inspect/v0.11-native-darkmode-functional/v0.11-darkmode-functional-[0-9]*.txt"
LIVE_STATE_REPORT_PATTERN = "hard-rom/inspect/darkmode-live-state/darkmode-live-state-*.txt"


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


def latest_dir(pattern: str) -> Path | None:
    dirs = sorted(path for path in ROOT.glob(pattern) if path.is_dir())
    return dirs[-1] if dirs else None


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


def check_required_markers(
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


def check_absent_markers(
    findings: list[Finding],
    area: str,
    target: str,
    path: Path,
    absent_markers: list[str],
    ok_status: str,
    implication: str,
    next_gate: str = "",
) -> None:
    text = read_text(path)
    if not text:
        add(findings, area, target, "missing_source", f"{rel(path)} is missing", implication, next_gate)
        return
    unexpected, _ = marker_summary(text, absent_markers)
    if unexpected:
        add(
            findings,
            area,
            target,
            "source_changed",
            f"{rel(path)} unexpectedly contains: {', '.join(unexpected)}",
            implication,
            next_gate,
        )
    else:
        add(
            findings,
            area,
            target,
            ok_status,
            f"{rel(path)} does not contain: {', '.join(absent_markers)}",
            implication,
            next_gate,
        )


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


def check_live_state_report(findings: list[Finding]) -> None:
    report = latest_report(LIVE_STATE_REPORT_PATTERN)
    target = "current device dark-mode/QS state is captured by read-only audit"
    implication = (
        "Native dark-mode integration and default QS visibility need the current "
        "ui_night_mode and expanded_widget_buttons state before a data migration "
        "or SettingsProvider seeding patch is designed."
    )
    if report is None:
        add(
            findings,
            "live_state",
            target,
            "missing_live_state",
            f"no report matches {LIVE_STATE_REPORT_PATTERN}",
            implication,
            "Connect the booted device and run tools/r2-darkmode-live-state-audit.sh.",
        )
        return

    text = read_text(report)
    if "result=PASS_READ_ONLY" in text:
        markers = [
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
        present, missing = marker_summary(text, markers)
        if missing:
            add(
                findings,
                "live_state",
                target,
                "weak_or_failed",
                f"{rel(report)} missing summary markers: {', '.join(missing)}; present: {', '.join(present)}",
                implication,
                "Re-run tools/r2-darkmode-live-state-audit.sh on a booted device.",
            )
        else:
            add(
                findings,
                "live_state",
                target,
                "live_state_captured",
                f"{rel(report)}: result=PASS_READ_ONLY; {', '.join(present)}",
                implication,
            )
        return

    if "result=DEVICE_NOT_AVAILABLE" in text:
        add(
            findings,
            "live_state",
            target,
            "missing_live_state",
            f"{rel(report)} reports DEVICE_NOT_AVAILABLE",
            implication,
            "Connect the booted device and re-run tools/r2-darkmode-live-state-audit.sh.",
        )
        return

    add(
        findings,
        "live_state",
        target,
        "weak_or_failed",
        f"{rel(report)} has no PASS_READ_ONLY or DEVICE_NOT_AVAILABLE marker",
        implication,
        "Inspect the report and re-run the read-only audit if needed.",
    )


def xml_string_value(text: str, name: str) -> str:
    match = re.search(rf'<string name="{re.escape(name)}">(.*?)</string>', text, re.DOTALL)
    return match.group(1).strip() if match else ""


def widget_count(value: str) -> int:
    return len([item for item in value.split("|") if item])


def audit() -> list[Finding]:
    findings: list[Finding] = []

    check_required_markers(
        findings,
        "framework",
        "stock UiModeManagerService has Android night-mode backend",
        SERVICE,
        [
            "SYSTEM_PROPERTY_DEVICE_THEME = \"persist.sys.theme\"",
            "mDarkThemeObserver",
            "\"ui_night_mode\"",
            "\"dark_theme_custom_start_time\"",
            "\"dark_theme_custom_end_time\"",
            "public void setNightMode(int mode)",
            "public boolean setNightModeActivated(boolean active)",
            "public void persistNightMode(int user)",
            "public void persistNightModeOverrides(int i)",
            "public void updateConfigurationLocked()",
            "private int getComputedUiModeConfiguration(int uiMode)",
            "public void applyConfigurationExternallyLocked()",
        ],
        "stock_supported",
        "The platform side can store, compute, and apply UI night mode without a new framework service.",
    )

    check_required_markers(
        findings,
        "settings",
        "stock BrightnessSettingsFragment has a hidden reusable display-row slot",
        SETTINGS_BRIGHTNESS,
        [
            "private SettingItemSwitch mReduceStrobeSwitch;",
            "R.id.switch_dc",
            "R.id.switch_dc_tips",
            "!SettingsFeature.isDarwin() && SettingsFeature.isSupportDC()",
            "\"reduce_screen_strobe\"",
            "Calibration.setReduceScreenStrobeEnable(z)",
        ],
        "stock_slot_available",
        "R2/Darwin hides the DC row, so v0.8/v0.11 can reuse an existing row without a resource-table change.",
        "SettingsSmartisan no-op live gate must pass before behavior patching this shared-UID APK.",
    )

    check_absent_markers(
        findings,
        "settings",
        "stock BrightnessSettingsFragment does not expose UiModeManager",
        SETTINGS_BRIGHTNESS,
        ["UiModeManager", "setNightModeActivated", "ui_night_mode"],
        "stock_missing_entry",
        "The stock Settings app needs a behavior patch to expose native dark mode.",
        "Use the original-cert-preserving SettingsSmartisan route, not a self-signed rebuild.",
    )

    check_required_markers(
        findings,
        "settings",
        "stock QuickWidgetFactory renders Smartisan native toggle keys",
        SETTINGS_WIDGET_FACTORY,
        [
            "getWidgetTitle(Context context, String str)",
            "\"toggleAutoBrightness\"",
            "\"toggleReadingMode\"",
            "\"toggleRealtimeSubtitle\"",
            "return null;",
        ],
        "stock_factory_supported",
        "The quick-widget editor is a Smartisan toggle-key factory, so a native toggleDarkMode key is the clean route.",
        "Patch QuickWidgetFactory only after SettingsSmartisan no-op live gate.",
    )

    check_absent_markers(
        findings,
        "settings",
        "stock QuickWidgetFactory has no toggleDarkMode entry",
        SETTINGS_WIDGET_FACTORY,
        ["toggleDarkMode"],
        "stock_missing_entry",
        "Unknown custom tile specs may not render in the Smartisan editor; v0.11 adds the native key path.",
    )

    check_required_markers(
        findings,
        "systemui",
        "stock QSTileHost uses Smartisan expanded_widget_buttons and native toggle keys",
        SYSTEMUI_QS_HOST,
        [
            "ACTION_WIDGET_BUTTONS_CHANGED",
            "SmartisanApi.WIDGET_BUTTONS",
            "tilesSettingChanged(loadSmartisanTileSpecs(context))",
            "public QSTile<?> createTile(String tileSpec)",
            "CustomTile.PREFIX",
            "IntentTile.PREFIX",
        ],
        "stock_host_supported",
        "SystemUI can load Smartisan tile settings and also parse custom tiles, but native keys are first-class.",
        "SmartisanSystemUI no-op live gate must pass before adding a native tile branch.",
    )

    check_required_markers(
        findings,
        "qs_persistence",
        "stock SettingsProvider seeds expanded_widget_buttons from def_notification_widget_buttons",
        SETTINGS_PROVIDER_DB,
        [
            "R.string.def_notification_widget_buttons",
            "loadSetting(sQLiteStatementCompileStatement, \"expanded_widget_buttons\", string)",
            "\"expanded_widget_buttons_additional\"",
            "SettingsUtil.getAdditionalNotificationWidgets(this.mContext, string)",
        ],
        "stock_persistence_supported",
        "Default QS button order is seeded by SettingsProvider resources, not by QSTileHost alone.",
        "Adding toggleDarkMode to the default list should be a separate SettingsProvider/resource or live data migration decision.",
    )

    check_required_markers(
        findings,
        "qs_persistence",
        "stock SettingsProvider upgrade path rewrites expanded_widget_buttons",
        SETTINGS_PROVIDER,
        [
            "getSettingLocked(\"expanded_widget_buttons\")",
            "getSettingLocked(\"expanded_widget_buttons_additional\")",
            "insertSettingLocked(\"expanded_widget_buttons\"",
            "insertSettingLocked(\"expanded_widget_buttons_additional\"",
            "cleanDirtyWidgetButton",
            "SettingsUtil.getDefaultNotificationWidgets(SettingsProvider.this.getContext())",
        ],
        "stock_persistence_supported",
        "Existing upgrade/cleanup code can replace or reset widget-button data, so default seeding must be tested independently.",
        "Do not bundle default seeding into the first v0.11 behavior ROM without a separate verification plan.",
    )

    check_required_markers(
        findings,
        "qs_persistence",
        "stock SettingsProvider upgrade path seeds explicit ui_night_mode day value",
        SETTINGS_PROVIDER,
        [
            "if (i2 < 180)",
            "getSecureSettingsLocked(i).insertSettingLocked(\"ui_night_mode\", String.valueOf(1), null, true, \"android\")",
        ],
        "stock_persistence_supported",
        "Smartisan already owns the secure ui_night_mode default during SettingsProvider upgrades; dark-mode integration should write through UiModeManager instead of inventing a parallel setting.",
    )

    check_required_markers(
        findings,
        "qs_persistence",
        "stock Settings quick-widget editor writes settings and broadcasts SystemUI reload",
        SETTINGS_NOTIFICATION_CUSTOM_VIEW,
        [
            "Settings.System.putString(contentResolver, \"expanded_widget_buttons\", str)",
            "Settings.System.putString(contentResolver, \"expanded_widget_buttons_additional\", str2)",
            "new Intent(ACTION_WIDGET_BUTTONS_CHANGED)",
            "intent.setPackage(\"com.android.systemui\")",
            "context.sendBroadcast(intent)",
        ],
        "stock_persistence_supported",
        "The editor can persist a new native key after QuickWidgetFactory knows how to render it.",
        "Live validation should inspect expanded_widget_buttons before and after editing.",
    )

    check_required_markers(
        findings,
        "qs_persistence",
        "stock SettingsUtil builds additional widget candidates from SettingsSmt registry",
        SMARTISAN_SETTINGS_UTIL,
        [
            "SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets()",
            "!widgetButtonList.contains(widget)",
            "isNotificationWidgetSupport(context, widget)",
            "SettingsSmt.NOTIFICATION_WIDGET.isWidgetButton(widget)",
        ],
        "stock_persistence_supported",
        "The Settings editor candidate list is registry-limited, so a new native key must be default-seeded, added to the registry path, or inserted by a SettingsSmartisan-specific candidate patch.",
    )

    check_absent_markers(
        findings,
        "qs_persistence",
        "stock SettingsSmt notification-widget registry does not know toggleDarkMode",
        SMARTISAN_SETTINGS_SMT,
        ["toggleDarkMode"],
        "stock_widget_registry_limited",
        "The stock framework registry route still will not offer toggleDarkMode, so v0.11 uses a SettingsSmartisan-local NotificationCustomView candidate-injection path instead.",
        "If default visibility is required, use a controlled default-list replacement or live migration after live gates.",
    )

    strings_text = read_text(SETTINGS_PROVIDER_STRINGS)
    host_text = read_text(SYSTEMUI_QS_HOST)
    default_count = widget_count(xml_string_value(strings_text, "def_notification_widget_buttons"))
    boston_count = widget_count(xml_string_value(strings_text, "def_notification_widget_buttons_boston"))
    tnt_count = widget_count(xml_string_value(strings_text, "def_notification_widget_buttons_tnt"))
    max_line = line_for(host_text, "MAX_QUICK_SETTING_NUM = 20")
    if default_count == 20 and max_line is not None:
        add(
            findings,
            "qs_persistence",
            "stock phone default quick-widget page is already at the 20-tile cap",
            "stock_default_capacity_full",
            (
                f"{rel(SETTINGS_PROVIDER_STRINGS)} def_notification_widget_buttons={default_count}, "
                f"boston={boston_count}, tnt={tnt_count}; {rel(SYSTEMUI_QS_HOST)} MAX_QUICK_SETTING_NUM@L{max_line}"
            ),
            "Default-visible toggleDarkMode cannot be appended to the phone page; it must replace a default tile, live-migrate user data, or stay in the additional/editor path.",
            "Do not patch the default list until the replacement choice and rollback behavior are explicit.",
        )
    else:
        add(
            findings,
            "qs_persistence",
            "stock phone default quick-widget page is already at the 20-tile cap",
            "weak_or_changed",
            (
                f"{rel(SETTINGS_PROVIDER_STRINGS)} def_notification_widget_buttons={default_count}, "
                f"boston={boston_count}, tnt={tnt_count}; MAX_QUICK_SETTING_NUM line={max_line}"
            ),
            "The default capacity boundary changed or could not be read.",
        )

    check_absent_markers(
        findings,
        "qs_persistence",
        "stock default quick-widget strings do not seed toggleDarkMode",
        SETTINGS_PROVIDER_STRINGS,
        ["toggleDarkMode"],
        "default_seeding_gap",
        "v0.11 makes the key creatable, renderable, and selectable in the editor, but it will not be default-visible unless seeded or added in user settings.",
        "Decide later whether to patch def_notification_widget_buttons or apply a live data migration.",
    )

    check_required_markers(
        findings,
        "qs_persistence",
        "stock settings backup/restore can normalize widget button lists across the 20-tile split",
        SETTINGS_BACKUP_AGENT,
        [
            "\"expanded_widget_buttons_additional\"",
            "SettingsUtil.getAdditionalNotificationWidgets(this, strValueOf)",
            "if (arrayList.size() > 20)",
            "SettingsUtil.widgetListToString(arrayList.subList(0, 20))",
            "SettingsUtil.widgetListToString(arrayList.subList(20, arrayList.size()))",
        ],
        "stock_restore_path_mapped",
        "Backup/restore is another path that can reshuffle widget buttons, so a durable default strategy must survive restore normalization as well as fresh database seeding.",
    )

    check_absent_markers(
        findings,
        "systemui",
        "stock QSTileHost has no toggleDarkMode branch",
        SYSTEMUI_QS_HOST,
        ["toggleDarkMode", "DarkModeTile"],
        "stock_missing_entry",
        "A SystemUI behavior patch is required for a native Smartisan dark-mode QS tile.",
    )

    check_required_markers(
        findings,
        "resources",
        "stock Settings resources already include a dark-mode title",
        SETTINGS_STRINGS,
        ["<string name=\"night_mode_yes\">Dark</string>"],
        "stock_resource_available",
        "The Settings-side title can reuse an existing public string instead of adding resources.",
    )

    check_required_markers(
        findings,
        "resources",
        "stock Settings public IDs expose night_mode_yes and dark icon colors",
        SETTINGS_PUBLIC,
        [
            "name=\"dark_mode_icon_color_dual_tone_background\"",
            "name=\"dark_mode_icon_color_dual_tone_fill\"",
            "name=\"night_mode_yes\"",
        ],
        "stock_resource_available",
        "The current candidate can stay dex-only on SettingsSmartisan.",
    )

    check_required_markers(
        findings,
        "resources",
        "stock SystemUI resources include dark-mode icon colors",
        SYSTEMUI_COLORS,
        [
            "dark_mode_icon_color_dual_tone_background_old",
            "dark_mode_icon_color_dual_tone_fill_old",
            "dark_mode_icon_color_single_tone",
        ],
        "stock_resource_available",
        "SystemUI already carries dark icon palette resources; v0.11 does not need a resource-table edit.",
    )

    check_required_markers(
        findings,
        "resources",
        "stock SystemUI public IDs expose dark-mode icon colors",
        SYSTEMUI_PUBLIC,
        [
            "name=\"dark_mode_icon_color_dual_tone_background\"",
            "name=\"dark_mode_icon_color_dual_tone_fill\"",
            "name=\"dark_mode_icon_color_single_tone\"",
        ],
        "stock_resource_available",
        "This supports a dex-only tile candidate before any SystemUI resource change.",
    )

    check_report_markers(
        findings,
        "candidate",
        "v0.11 APK semantic verifier proves the intended patched call sites",
        V011_REPORT_PATTERN,
        [
            "SmartisanSystemUI: only classes10.dex changed",
            "SettingsSmartisan: only classes.dex and classes2.dex changed",
            "SystemUI: DarkModeTile and QSTileHost toggleDarkMode branch verified",
            "SettingsSmartisan: BrightnessSettingsFragment, QuickWidgetFactory, and NotificationCustomView dark-mode call sites verified",
            "SHA-256 digest error for classes10.dex",
            "SHA-256 digest error for classes.dex",
            "PASS",
        ],
        "candidate_proven_offline",
        "The v0.11 APKs match the intended integration points, but APK semantics are not live boot proof.",
        "Do not build/flash v0.11 ROM until SettingsSmartisan and SmartisanSystemUI no-op live gates pass.",
    )

    evidence_dir = latest_dir(V011_EVIDENCE_DIR_PATTERN)
    if evidence_dir is None:
        add(
            findings,
            "candidate",
            "v0.11 smali evidence files exist",
            "missing_report",
            f"no evidence dir matches {V011_EVIDENCE_DIR_PATTERN}",
            "The APK verifier should preserve focused smali snippets for review.",
        )
    else:
        expected = [
            "SystemUI-DarkModeTile.smali",
            "SystemUI-QSTileHost.smali",
            "Settings-BrightnessSettingsFragment.smali",
            "Settings-QuickWidgetFactory.smali",
            "Settings-NotificationCustomView.smali",
        ]
        missing = [name for name in expected if not (evidence_dir / name).exists()]
        status = "candidate_proven_offline" if not missing else "weak_or_failed"
        evidence = f"{rel(evidence_dir)}" if not missing else f"{rel(evidence_dir)} missing {', '.join(missing)}"
        add(
            findings,
            "candidate",
            "v0.11 smali evidence files exist",
            status,
            evidence,
            "Focused smali files make the candidate reviewable without re-decoding large APKs.",
        )

    check_live_state_report(findings)

    for target, pattern, gate in [
        (
            "SettingsSmartisan no-op live gate",
            "hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-*.txt",
            "Flash v0.25 only after explicit confirmation, then run the live verifier with SETTINGS_NOOP_VARIANT=v0.25-settings-noop-on-v0.24.",
        ),
        (
            "current-base SmartisanSystemUI no-op live gate",
            "hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-*.txt",
            "Flash systemui-certprobe-noop-on-v0.24 only after explicit confirmation, then run SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24 tools/r2-verify-systemui-certprobe-noop.sh --read-only.",
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
                "Live PackageManager/shared-UID/boot behavior is still unproven.",
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
                "This gate controls whether the corresponding behavior APK can be flashed next.",
            )

    v011_device_report = latest_report(V011_DEVICE_REPORT_PATTERN)
    v011_device_live = False
    if v011_device_report is None:
        add(
            findings,
            "live_gate",
            "v0.11 native dark-mode behavior ROM live verification",
            "missing_live_gate",
            f"no report matches {V011_DEVICE_REPORT_PATTERN}",
            "The behavior ROM is not yet proven on a booted device.",
            "Flash v0.11 only after exact confirmation, then run tools/r2-verify-v0.11-native-darkmode.sh --read-only.",
        )
    else:
        text = read_text(v011_device_report)
        v011_device_live = "PASS: v0.11 native dark-mode device read-only verification" in text
        add(
            findings,
            "live_gate",
            "v0.11 native dark-mode behavior ROM live verification",
            "proven_live" if v011_device_live else "weak_or_failed",
            f"{rel(v011_device_report)} {'contains PASS' if v011_device_live else 'does not contain PASS'}",
            "The combined Settings/SystemUI behavior ROM boots and PackageManager accepts the patched shared-UID APKs."
            if v011_device_live
            else "The behavior ROM device verifier did not produce the expected PASS marker.",
            "Next prove user-facing interaction: Settings row behavior, UiMode change, and Smartisan QS editor/tile behavior."
            if v011_device_live
            else "Re-run the v0.11 read-only verifier and inspect package/logcat failures.",
        )

    check_report_markers(
        findings,
        "live_gate",
        "v0.11 reversible functional UiMode/SystemUI tile test",
        V011_FUNCTIONAL_REPORT_PATTERN,
        [
            "ui_mode_yes=PASS",
            "ui_mode_no=PASS",
            "systemui_toggleDarkMode_tile_creation=PASS",
            "restore_original_quick_settings=PASS",
            "result=PASS_WRITE_APPROVED_FUNCTIONAL",
            "Creating tile: toggleDarkMode",
        ],
        "proven_live",
        "The live device accepted reversible /data writes: UiModeManager changed yes/no, SystemUI instantiated DarkModeTile, and original QS data was restored.",
        "Still manually validate the Settings row and Smartisan QS editor candidate surface before calling the whole native dark-mode UX complete.",
    )

    v011_super = ROOT / "hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img"
    v011_super_exists = v011_super.exists()
    add(
        findings,
        "rom_gate",
        "combined v0.11 native dark-mode sparse super",
        "proven_live" if v011_super_exists and v011_device_live else "candidate_offline" if v011_super_exists else "missing_rom_image",
        rel(v011_super) if v011_super_exists else "not built",
        "The flashable ROM image has booted and matched the expected patched Settings/SystemUI APK hashes on device."
        if v011_super_exists and v011_device_live
        else "A flashable ROM image exists and remains offline-only until live behavior testing."
        if v011_super_exists
        else "A flashable ROM image is intentionally missing until both core APK live no-op gates pass.",
        "Run reversible functional testing for Settings UiMode and Smartisan QS tile/editor behavior."
        if v011_super_exists and v011_device_live
        else "Run tools/r2-live-flash-preflight.sh v0.11-native-darkmode, then ask for exact flash confirmation."
        if v011_super_exists
        else "After live gates pass, build an exact-current sparse super and verify it offline before asking to flash.",
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
        "stock_supported": 0,
        "stock_slot_available": 1,
        "stock_factory_supported": 2,
        "stock_resource_available": 3,
        "stock_host_supported": 4,
        "stock_persistence_supported": 5,
        "stock_restore_path_mapped": 6,
        "stock_widget_registry_limited": 7,
        "stock_default_capacity_full": 8,
        "stock_missing_entry": 9,
        "default_seeding_gap": 10,
        "candidate_proven_offline": 11,
        "candidate_offline": 12,
        "live_state_captured": 13,
        "proven_live": 14,
        "missing_live_state": 15,
        "missing_live_gate": 16,
        "missing_rom_image": 17,
        "missing_source": 18,
        "missing_report": 19,
        "weak_or_changed": 20,
        "weak_or_failed": 21,
        "source_changed": 22,
    }
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.status] = counts.get(finding.status, 0) + 1

    lines = [
        "# Dark Mode Source Coupling Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit checks the static Smartisan OS 8.5.3 source",
        "knowledge base and existing v0.11 verification evidence for native",
        "system light/dark mode integration. It does not modify APKs, images,",
        "the live device, or `/data`.",
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
            "- The stock framework already contains Android's UiModeManager night-mode backend.",
            "- Stock Smartisan Settings/SystemUI do not expose a native dark-mode switch or tile.",
            "- The clean integration route is a native Smartisan `toggleDarkMode` key plus a Settings display-row patch, not an unknown custom tile as the final path.",
            "- Default QS visibility is a separate SettingsProvider/user-data seeding decision; the stock phone default page is already at 20 tiles, and the stock SettingsSmt widget registry does not know `toggleDarkMode`.",
            "- A durable default strategy must account for fresh SettingsProvider seeding, Settings editor reset, additional-widget generation, and backup/restore normalization.",
            "- The current live device state must be considered before deciding whether to seed, replace, or migrate QS tile data.",
            "- v0.11 is now live-proven at the boot/package/hash level and has reversible functional proof for UiModeManager yes/no plus SystemUI `toggleDarkMode` tile creation.",
            "- The remaining dark-mode UX proof is manual/user-facing: Settings row visibility/click behavior and Smartisan QS editor candidate behavior.",
            "",
        ]
    )

    for area in ("framework", "settings", "systemui", "qs_persistence", "resources", "candidate", "live_state", "live_gate", "rom_gate"):
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
