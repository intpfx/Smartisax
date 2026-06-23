#!/usr/bin/env python3
"""Audit Smartisan dark-mode QS persistence and reset paths.

This script is read-only. It connects SettingsProvider fresh seeding,
SettingsProvider upgrade cleanup, SettingsSmartisan editor reset/validity,
Settings backup/restore normalization, SystemUI first-page loading, and the
current v0.11 smali evidence for the native ``toggleDarkMode`` key.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGET_KEY = "toggleDarkMode"
MAX_FIRST_PAGE = 20

OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/darkmode-persistence-audit.tsv"
OUT_MD = ROOT / "docs/research/darkmode-persistence-audit.md"

SETTINGS_PROVIDER_STRINGS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "resources/res/values/strings.xml"
)
SETTINGS_PROVIDER_DB = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/DatabaseHelper.java"
)
SETTINGS_PROVIDER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/SettingsProvider.java"
)
SETTINGS_BACKUP_AGENT = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/SettingsBackupAgent.java"
)
SETTINGS_HELPER = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/SettingsHelper.java"
)
SETTINGS_UTIL = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar"
    / "sources/smartisanos/util/SettingsUtil.java"
)
SETTINGS_SMT = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/smartisanos/api/SettingsSmt.java"
)
NOTIFICATION_CUSTOM_VIEW = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "sources/com/android/settings/widget/NotificationCustomView.java"
)
QS_TILE_HOST = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk"
    / "sources/com/android/systemui/statusbar/phone/QSTileHost.java"
)
V011_EVIDENCE_DIR_PATTERN = "hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-*"
LIVE_STATE_PATTERN = "hard-rom/inspect/darkmode-live-state/darkmode-live-state-*.txt"


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


def marker_evidence(path: Path, markers: list[str]) -> tuple[list[str], list[str]]:
    text = read_text(path)
    present: list[str] = []
    missing: list[str] = []
    for marker in markers:
        line = line_for(text, marker)
        if line is None:
            missing.append(marker)
        else:
            present.append(f"{rel(path)}:{line}:{marker}")
    return present, missing


def xml_string(text: str, name: str) -> str:
    match = re.search(rf'<string name="{re.escape(name)}"(?:\s+[^>]*)?>(.*?)</string>', text, re.DOTALL)
    if not match:
        return ""
    return re.sub(r"\s+", "", match.group(1).strip())


def split_widgets(value: str) -> list[str]:
    return [item for item in value.split("|") if item]


def default_lists() -> dict[str, list[str]]:
    text = read_text(SETTINGS_PROVIDER_STRINGS)
    return {
        "phone": split_widgets(xml_string(text, "def_notification_widget_buttons")),
        "boston": split_widgets(xml_string(text, "def_notification_widget_buttons_boston")),
        "tnt": split_widgets(xml_string(text, "def_notification_widget_buttons_tnt")),
    }


def settingssmt_registry() -> list[str]:
    text = read_text(SETTINGS_SMT)
    start = text.find("public static final class NOTIFICATION_WIDGET")
    if start != -1:
        end = text.find("public static final class SHORTCUT_KEY_VALUE", start)
        block = text[start:end] if end != -1 else text[start:]
    else:
        block = text
    return re.findall(r'(?:sAllWidgets|arrayList)\.add\("(.*?)"\)', block)


def latest_path(pattern: str, directory: bool = False) -> Path | None:
    paths = ROOT.glob(pattern)
    if directory:
        items = sorted(path for path in paths if path.is_dir())
    else:
        items = sorted(paths)
    return items[-1] if items else None


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


def source_status(path: Path, markers: list[str], ok_status: str, weak_status: str) -> tuple[str, str]:
    present, missing = marker_evidence(path, markers)
    if not read_text(path):
        return "missing_source", f"{rel(path)} is missing"
    if missing:
        return weak_status, f"missing={', '.join(missing)}; present={'; '.join(present)}"
    return ok_status, "; ".join(present)


def v011_candidate_status() -> tuple[str, str]:
    evidence_dir = latest_path(V011_EVIDENCE_DIR_PATTERN, directory=True)
    if evidence_dir is None:
        return "missing_candidate_evidence", f"no directory matches {V011_EVIDENCE_DIR_PATTERN}"
    view = evidence_dir / "Settings-NotificationCustomView.smali"
    if not view.exists():
        return "missing_candidate_evidence", f"{rel(view)} is missing"
    markers = [
        "appendDarkModeCandidate",
        'const-string v0, "toggleDarkMode"',
        "getCurrentAdditionalQuickWidgetSettings",
        "getDefaultAdditionalOrderSettings",
        "checkValidity",
        "saveWidgetButtonsAndNotify",
        "invoke-static {v3, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate",
        "invoke-static {p1, p2}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate",
    ]
    present, missing = marker_evidence(view, markers)
    if missing:
        return "candidate_injection_incomplete", f"missing={', '.join(missing)}; present={'; '.join(present)}"
    return "candidate_editor_persistence_proven_offline", "; ".join(present)


def live_state_status() -> tuple[str, str]:
    report = latest_path(LIVE_STATE_PATTERN)
    if report is None:
        return "missing_live_state", f"no report matches {LIVE_STATE_PATTERN}"
    text = read_text(report)
    if "result=PASS_READ_ONLY" in text:
        markers = [
            "system.expanded_widget_buttons=",
            "system.expanded_widget_buttons_additional=",
            "system.expanded_widget_buttons.has_toggleDarkMode=",
            "system.expanded_widget_buttons_additional.has_toggleDarkMode=",
        ]
        missing = [marker for marker in markers if marker not in text]
        if missing:
            return "weak_live_state", f"{rel(report)} missing markers: {', '.join(missing)}"
        return "live_state_captured", f"{rel(report)} contains PASS_READ_ONLY and Smartisan QS markers"
    if "result=DEVICE_NOT_AVAILABLE" in text:
        return "missing_live_state", f"{rel(report)} reports DEVICE_NOT_AVAILABLE"
    return "weak_live_state", f"{rel(report)} has no recognized result marker"


def audit() -> list[Finding]:
    findings: list[Finding] = []
    defaults = default_lists()
    phone = defaults["phone"]
    registry = settingssmt_registry()
    target_in_defaults = {name: TARGET_KEY in values for name, values in defaults.items()}
    stock_additional = [key for key in registry if key not in phone]

    add(
        findings,
        "fresh_seed",
        "SettingsProvider fresh database seeds Smartisan QS defaults",
        "stock_default_missing_target" if not target_in_defaults["phone"] else "stock_default_contains_target",
        f"phone_count={len(phone)}; target_in_phone={target_in_defaults['phone']}; default_line={rel(SETTINGS_PROVIDER_STRINGS)}:{line_for(read_text(SETTINGS_PROVIDER_STRINGS), 'def_notification_widget_buttons')}",
        "A fresh database will not show toggleDarkMode on the first QS page unless SettingsProvider defaults or live data are changed.",
        "Keep default seeding out of the first behavior ROM, or replace one stock key deliberately after live state is captured.",
    )

    status, evidence = source_status(
        SETTINGS_PROVIDER_DB,
        [
            'getString(R.string.def_notification_widget_buttons)',
            'loadSetting(sQLiteStatementCompileStatement, "expanded_widget_buttons", string)',
            'loadSetting(sQLiteStatementCompileStatement, "expanded_widget_buttons_additional", SettingsUtil.getAdditionalNotificationWidgets(this.mContext, string))',
        ],
        "fresh_seed_path_mapped",
        "fresh_seed_path_changed",
    )
    add(
        findings,
        "fresh_seed",
        "DatabaseHelper writes first-page and additional widget settings",
        status,
        evidence,
        "The first-page and additional lists are coupled at database creation time.",
    )

    add(
        findings,
        "registry",
        "SettingsSmt.NOTIFICATION_WIDGET registry contains selectable keys",
        "stock_registry_missing_target" if TARGET_KEY not in registry else "stock_registry_contains_target",
        f"registry_count={len(registry)}; target_in_registry={TARGET_KEY in registry}; stock_additional_count={len(stock_additional)}; settingssmt={rel(SETTINGS_SMT)}",
        "SettingsUtil cannot generate toggleDarkMode as an additional candidate from stock framework.jar.",
        "v0.11 currently uses a SettingsSmartisan-local candidate injection route instead of a framework.jar registry patch.",
    )

    status, evidence = source_status(
        SETTINGS_UTIL,
        [
            "SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets()",
            "!widgetButtonList.contains(widget)",
            "isNotificationWidgetSupport(context, widget)",
            "SettingsSmt.NOTIFICATION_WIDGET.isWidgetButton(widget)",
        ],
        "additional_generation_path_mapped",
        "additional_generation_path_changed",
    )
    add(
        findings,
        "registry",
        "SettingsUtil additional-widget generation is registry-limited",
        status,
        evidence,
        "A SystemUI-only native tile is insufficient for a polished Smartisan editor path.",
    )

    status, evidence = source_status(
        NOTIFICATION_CUSTOM_VIEW,
        [
            'Settings.System.getString(context.getContentResolver(), "expanded_widget_buttons_additional")',
            "SettingsUtil.getAdditionalNotificationWidgets(context, getCurrentQuickWidgetSettings(context))",
            "getDefaultAdditionalOrderSettings()",
            "saveWidgetButtonsAndNotify(defaultOrderSettings, getDefaultAdditionalOrderSettings())",
        ],
        "editor_stock_paths_mapped",
        "editor_stock_paths_changed",
    )
    add(
        findings,
        "settings_editor",
        "Stock SettingsSmartisan editor reads/falls back/resets additional widgets",
        status,
        evidence,
        "Stock editor reset and empty-additional fallback will not offer toggleDarkMode unless default/additional generation or local injection knows the key.",
    )

    status, evidence = source_status(
        NOTIFICATION_CUSTOM_VIEW,
        [
            'saveWidgetButtonsAndNotify(defaultNotificationWidgets, isPCMode ? "" : SettingsUtil.getAdditionalNotificationWidgets(getContext(), defaultNotificationWidgets))',
            "checkValidity got duplicate",
        ],
        "editor_duplicate_reset_path_mapped",
        "editor_duplicate_reset_path_changed",
    )
    add(
        findings,
        "settings_editor",
        "Stock duplicate validity reset falls back to default/additional lists",
        status,
        evidence,
        "If the stock reset path is triggered, a target key not present in defaults/additional generation can be dropped.",
        "The v0.11 local injection must cover checkValidity/reset paths, and live validation should intentionally test editor reset.",
    )

    status, evidence = v011_candidate_status()
    add(
        findings,
        "candidate",
        "v0.11 SettingsSmartisan local injection covers additional/reset/save paths",
        status,
        evidence,
        "The current APK-only candidate tries to make the editor/additional route survive stock fallbacks without patching smartisanos.jar first.",
        "Live no-op and v0.11 behavior gates have passed; still needs manual Settings editor/additional UX proof.",
    )

    status, evidence = source_status(
        SETTINGS_PROVIDER,
        [
            'getSecureSettingsLocked(i).insertSettingLocked("ui_night_mode", String.valueOf(1)',
            "cleanDirtyWidgetButton(i)",
            "SettingsUtil.widgetListToString(arrayList.subList(0, 20))",
            "SettingsUtil.getDefaultNotificationWidgets(SettingsProvider.this.getContext())",
            "SettingsUtil.getAdditionalNotificationWidgets(SettingsProvider.this.getContext(), defaultNotificationWidgets)",
        ],
        "upgrade_cleanup_path_mapped",
        "upgrade_cleanup_path_changed",
    )
    add(
        findings,
        "settings_provider_upgrade",
        "SettingsProvider upgrade can seed ui_night_mode and reset dirty widget data",
        status,
        evidence,
        "A durable default-visible route must decide whether upgrade cleanup should preserve, inject, or intentionally ignore toggleDarkMode.",
        "Do not treat a working editor route as proof that upgrade cleanup will preserve default visibility.",
    )

    status, evidence = source_status(
        SETTINGS_HELPER,
        [
            'sBroadcastOnRestore.add("ui_night_mode")',
            "android.os.action.SETTING_RESTORED",
        ],
        "ui_mode_restore_broadcast_mapped",
        "ui_mode_restore_broadcast_changed",
    )
    add(
        findings,
        "backup_restore",
        "Settings restore broadcasts ui_night_mode changes",
        status,
        evidence,
        "The platform night-mode value participates in Android restore notifications; the QS widget list is a separate Smartisan path.",
    )

    status, evidence = source_status(
        SETTINGS_BACKUP_AGENT,
        [
            '"expanded_widget_buttons_additional"',
            "SettingsUtil.getAdditionalNotificationWidgets(this, strValueOf)",
            'arrayList.contains("toggleReadingMode")',
            'arrayList.contains("toggleWirelessTNT")',
            'arrayList.contains("toggleRealtimeSubtitle")',
            "arrayList.size() > 20",
            'toRestore(uri, hashSet, contentValues, settingsHelper2, contentResolver, "expanded_widget_buttons_additional"',
        ],
        "restore_widget_normalization_mapped",
        "restore_widget_normalization_changed",
    )
    add(
        findings,
        "backup_restore",
        "SettingsBackupAgent normalizes Smartisan widget lists on restore",
        "restore_not_target_aware" if status == "restore_widget_normalization_mapped" and TARGET_KEY not in read_text(SETTINGS_BACKUP_AGENT) else status,
        evidence,
        "Stock restore explicitly handles several Smartisan keys but does not know toggleDarkMode, so default-visible durability needs a restore test or patch plan.",
        "After behavior ROM live proof, test backup/restore or add a target-aware restore normalization patch before claiming polished default behavior.",
    )

    status, evidence = source_status(
        QS_TILE_HOST,
        [
            "SmartisanApi.WIDGET_BUTTONS",
            "SettingsUtil.getDefaultNotificationWidgets(context)",
            "if (result.size() > 20)",
            "return result.subList(0, 20)",
        ],
        "systemui_first_page_cap_mapped",
        "systemui_first_page_cap_changed",
    )
    add(
        findings,
        "systemui_load",
        "SystemUI loads first-page widget order and truncates at 20",
        status,
        evidence,
        "Appending toggleDarkMode as a 21st key will not make it visible on the phone first page.",
        "Default-visible integration must replace a key or migrate live data; editor/additional integration can remain non-default.",
    )

    status, evidence = live_state_status()
    add(
        findings,
        "live_state",
        "Current live QS and ui_night_mode state is captured",
        status,
        evidence,
        "The stock/current user data can differ from ROM defaults, so migration and displacement decisions require live capture.",
        "Run tools/r2-darkmode-live-state-audit.sh on a booted device before default seeding or migration.",
    )

    add(
        findings,
        "route_decision",
        "Lowest-risk next dark-mode behavior route",
        "editor_additional_first",
        "stock defaults omit target; registry omits target; v0.11 local injection covers editor additional paths offline; phone default list is full",
        "The next behavior ROM should first prove Settings row, editor/additional availability, SystemUI tile creation, and UiMode persistence without patching SettingsProvider defaults.",
        "Default-visible behavior should be a later D5 decision after manual Settings/QS editor UX proof and product preference review.",
    )

    return findings


def write_tsv(findings: list[Finding]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["area", "target", "status", "evidence", "implication", "next_gate"],
            delimiter="\t",
        )
        writer.writeheader()
        for finding in findings:
            writer.writerow(finding.__dict__)


def write_md(findings: list[Finding]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.status] = counts.get(finding.status, 0) + 1

    grouped: dict[str, list[Finding]] = {}
    for finding in findings:
        grouped.setdefault(finding.area, []).append(finding)

    lines: list[str] = [
        "# Dark Mode Persistence Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit checks whether the native `toggleDarkMode` QS key can survive Smartisan SettingsProvider seeding, upgrade cleanup, Settings editor reset, backup/restore normalization, and SystemUI first-page loading. It does not modify APKs, images, the live device, or `/data`.",
        "",
        f"TSV output: `{rel(OUT_TSV)}`",
        "",
        "## Summary",
        "",
    ]
    for status, count in sorted(counts.items()):
        lines.append(f"- {status}: {count}")
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- Stock ROM defaults and the SettingsSmt widget registry do not contain `toggleDarkMode`.",
            "- The phone first QS page already uses 20 slots, so appending a 21st key is not a visible default route.",
            "- The current v0.11 APK-only candidate has offline evidence for a SettingsSmartisan-local additional/editor injection route.",
            "- A polished default-visible route is a later decision: replace one default key, patch framework/default/restore paths, or run a live data migration after no-op gates pass.",
            "",
        ]
    )

    for area, rows in grouped.items():
        lines.extend(
            [
                f"## {area}",
                "",
                "| status | target | evidence | implication | next gate |",
                "| --- | --- | --- | --- | --- |",
            ]
        )
        for row in rows:
            lines.append(
                "| "
                + " | ".join(
                    cell.replace("|", "\\|").replace("\n", " ")
                    for cell in (row.status, row.target, row.evidence, row.implication, row.next_gate)
                )
                + " |"
            )
        lines.append("")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    findings = audit()
    write_tsv(findings)
    write_md(findings)
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.status] = counts.get(finding.status, 0) + 1
    for status, count in sorted(counts.items()):
        print(f"{status}={count}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"markdown={rel(OUT_MD)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
