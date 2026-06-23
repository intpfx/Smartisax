#!/usr/bin/env python3
"""Audit Smartisan QS default-entry strategy for native dark mode.

This script is read-only. It connects the stock quick-widget default lists,
SystemUI tile creation, SettingsSmartisan editor rendering, and SettingsSmt
candidate registry so the native dark-mode tile can be integrated without
blindly appending a 21st default tile.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/darkmode-qs-strategy-audit.tsv"
OUT_MD = ROOT / "docs/research/darkmode-qs-strategy-audit.md"

SETTINGS_PROVIDER_STRINGS = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "resources/res/values/strings.xml"
)
SYSTEMUI_QS_HOST = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk"
    / "sources/com/android/systemui/statusbar/phone/QSTileHost.java"
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
SMARTISAN_SETTINGS_SMT = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar"
    / "sources/smartisanos/api/SettingsSmt.java"
)
SMARTISAN_SETTINGS_UTIL = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar"
    / "sources/smartisanos/util/SettingsUtil.java"
)
SETTINGS_BACKUP_AGENT = (
    ROOT
    / "reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk"
    / "sources/com/android/providers/settings/SettingsBackupAgent.java"
)
LIVE_STATE_PATTERN = "hard-rom/inspect/darkmode-live-state/darkmode-live-state-*.txt"
V011_EVIDENCE_DIR_PATTERN = "hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-*"

TARGET_KEY = "toggleDarkMode"
MAX_FIRST_PAGE = 20


@dataclass(frozen=True)
class TileRow:
    list_name: str
    position: int
    key: str
    qstilehost: str
    quickwidget: str
    settingssmt: str
    default_presence: str
    displacement_class: str
    recommendation: str


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


def xml_string(text: str, name: str) -> str:
    match = re.search(rf'<string name="{re.escape(name)}"(?:\s+[^>]*)?>(.*?)</string>', text, re.DOTALL)
    if not match:
        return ""
    return re.sub(r"\s+", "", match.group(1).strip())


def split_widgets(value: str) -> list[str]:
    return [item for item in value.split("|") if item]


def literal_toggle_set(text: str) -> set[str]:
    return set(re.findall(r'"(toggle[A-Za-z0-9]+|togglerrecordscreen|togglepowersave)"', text))


def qstilehost_supported(text: str) -> set[str]:
    constants = dict(re.findall(r'public static final String (TILE_[A-Z0-9_]+) = "(.*?)";', text))
    supported: set[str] = set()
    for constant, key in constants.items():
        if f"tileSpec.equals({constant})" in text:
            supported.add(key)
    return supported


def settingssmt_registry(text: str) -> set[str]:
    block = text
    start = text.find("public static final class NOTIFICATION_WIDGET")
    if start != -1:
        block = text[start : text.find("public static final class SHORTCUT_KEY_VALUE", start)]
    return set(re.findall(r'(?:sAllWidgets|arrayList)\.add\("(.*?)"\)', block))


def notification_custom_view_features(text: str) -> dict[str, bool]:
    return {
        "reads_additional_setting": '"expanded_widget_buttons_additional"' in text
        and "Settings.System.getString" in text,
        "falls_back_to_settingsutil": "SettingsUtil.getAdditionalNotificationWidgets(context, getCurrentQuickWidgetSettings(context))"
        in text,
        "candidate_uses_factory": "QuickWidgetFactory.getWidget(getContext()" in text,
        "saves_additional_setting": 'Settings.System.putString(contentResolver, "expanded_widget_buttons_additional", str2)'
        in text,
        "reset_uses_default_additional": "saveWidgetButtonsAndNotify(defaultOrderSettings, getDefaultAdditionalOrderSettings())"
        in text,
        "validity_reset_bypasses_local_default_helper": "SettingsUtil.getAdditionalNotificationWidgets(getContext(), defaultNotificationWidgets)"
        in text,
        "stock_mentions_target": TARGET_KEY in text,
    }


def latest_report(pattern: str) -> Path | None:
    reports = sorted(ROOT.glob(pattern))
    return reports[-1] if reports else None


def latest_dir(pattern: str) -> Path | None:
    dirs = sorted(path for path in ROOT.glob(pattern) if path.is_dir())
    return dirs[-1] if dirs else None


def v011_candidate_injection_status() -> tuple[str, str]:
    evidence_dir = latest_dir(V011_EVIDENCE_DIR_PATTERN)
    if evidence_dir is None:
        return "requires_settingssmartisan_candidate_injection", f"no evidence dir matches {V011_EVIDENCE_DIR_PATTERN}"
    view = evidence_dir / "Settings-NotificationCustomView.smali"
    if not view.exists():
        return "requires_settingssmartisan_candidate_injection", f"{rel(evidence_dir)} missing Settings-NotificationCustomView.smali"
    text = read_text(view)
    markers = [
        "appendDarkModeCandidate",
        'const-string v0, "toggleDarkMode"',
        "getCurrentQuickWidgetSettings",
        "getDefaultNotificationWidgets",
        "expanded_widget_buttons_additional",
        "invoke-static {v3, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate",
        "invoke-static {p1, p2}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate",
    ]
    missing = [marker for marker in markers if marker not in text]
    if missing:
        return "requires_settingssmartisan_candidate_injection", f"{rel(view)} missing markers: {', '.join(missing)}"
    return "candidate_injection_proven_offline", f"{rel(view)} contains NotificationCustomView dark-mode candidate injection markers"


def live_state_status() -> tuple[str, str]:
    report = latest_report(LIVE_STATE_PATTERN)
    if report is None:
        return "missing_live_state", f"no report matches {LIVE_STATE_PATTERN}"
    text = read_text(report)
    if "result=PASS_READ_ONLY" in text:
        markers = [
            "system.expanded_widget_buttons=",
            "system.expanded_widget_buttons_additional=",
            "system.expanded_widget_buttons.count=",
            "system.expanded_widget_buttons.has_toggleDarkMode=",
            "system.expanded_widget_buttons.over20=",
        ]
        missing = [marker for marker in markers if marker not in text]
        if missing:
            return "weak_or_failed", f"{rel(report)} missing Smartisan system QS markers: {', '.join(missing)}"
        return "captured", f"{rel(report)} contains PASS_READ_ONLY and Smartisan system QS markers"
    if "result=DEVICE_NOT_AVAILABLE" in text:
        return "missing_live_state", f"{rel(report)} reports DEVICE_NOT_AVAILABLE"
    return "weak_or_failed", f"{rel(report)} has no recognized result marker"


def default_lists() -> dict[str, list[str]]:
    text = read_text(SETTINGS_PROVIDER_STRINGS)
    return {
        "phone": split_widgets(xml_string(text, "def_notification_widget_buttons")),
        "boston": split_widgets(xml_string(text, "def_notification_widget_buttons_boston")),
        "tnt": split_widgets(xml_string(text, "def_notification_widget_buttons_tnt")),
    }


def displacement_class(key: str) -> str:
    essential = {
        "toggleAirplane",
        "toggleWifi",
        "toggleMobileData",
        "toggleVpn",
        "toggleWifiAp",
        "toggleBluetooth",
        "toggleGPS",
    }
    system_utility = {
        "toggleAutoRotate",
        "toggleAutoBrightness",
        "toggleFlashlight",
        "toggleVibrate",
        "toggleMute",
        "togglepowersave",
        "togglerrecordscreen",
        "toggleScreenShot",
        "toggleDisableButtons",
    }
    display_optional = {"toggleProtectEyes", "toggleReadingMode", "toggleKeepScreenOn"}
    device_or_accessibility_specific = {"toggleWirelessTNT", "toggleRealtimeSubtitle", "toggleRelay", "toggleChargePhone"}
    if key in essential:
        return "avoid_displacing_connectivity"
    if key in display_optional:
        return "possible_display_policy_tradeoff"
    if key in device_or_accessibility_specific:
        return "possible_special_feature_tradeoff"
    if key in system_utility:
        return "use_caution_system_utility"
    return "unknown_review_required"


def recommendation_for(key: str, list_name: str) -> str:
    cls = displacement_class(key)
    if list_name != "phone":
        return "non_phone_default_list_review"
    if cls == "possible_special_feature_tradeoff":
        return "candidate_only_after_live_usage_review"
    if cls == "possible_display_policy_tradeoff":
        return "candidate_if_dark_mode_replaces_display_comfort_slot"
    if cls == "use_caution_system_utility":
        return "not_first_choice_without_user_preference"
    if cls == "avoid_displacing_connectivity":
        return "do_not_displace_for_dark_mode"
    return "review_required"


def build_rows(defaults: dict[str, list[str]], qshost: set[str], quickwidget: set[str], registry: set[str]) -> list[TileRow]:
    rows: list[TileRow] = []
    list_presence = {
        key: ",".join(name for name, values in defaults.items() if key in values)
        for values in defaults.values()
        for key in values
    }
    for list_name, values in defaults.items():
        for position, key in enumerate(values, 1):
            rows.append(
                TileRow(
                    list_name=list_name,
                    position=position,
                    key=key,
                    qstilehost="yes" if key in qshost else "no",
                    quickwidget="yes" if key in quickwidget else "no",
                    settingssmt="yes" if key in registry else "no",
                    default_presence=list_presence.get(key, ""),
                    displacement_class=displacement_class(key),
                    recommendation=recommendation_for(key, list_name),
                )
            )
    return rows


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


def audit_findings(
    defaults: dict[str, list[str]],
    qshost: set[str],
    quickwidget: set[str],
    registry: set[str],
    notification_view_text: str,
) -> list[Finding]:
    findings: list[Finding] = []
    phone = defaults.get("phone", [])
    boston = defaults.get("boston", [])
    tnt = defaults.get("tnt", [])

    add(
        findings,
        "default_lists",
        "stock phone quick-widget default page uses all first-page slots",
        "capacity_full" if len(phone) >= MAX_FIRST_PAGE else "capacity_available",
        f"phone={len(phone)}, boston={len(boston)}, tnt={len(tnt)}, max_first_page={MAX_FIRST_PAGE}",
        "A default-visible dark-mode tile cannot be appended on phone; it must replace a key, stay in additional/editor path, or use live migration.",
        "Capture live QS state before choosing a displacement.",
    )

    missing_from = []
    if TARGET_KEY not in qshost:
        missing_from.append("QSTileHost")
    if TARGET_KEY not in quickwidget:
        missing_from.append("QuickWidgetFactory")
    if TARGET_KEY not in registry:
        missing_from.append("SettingsSmt.NOTIFICATION_WIDGET")
    if any(TARGET_KEY in values for values in defaults.values()):
        default_status = "stock_default_seeded"
    else:
        default_status = "stock_not_default_seeded"
    add(
        findings,
        "target_key",
        "stock toggleDarkMode registration state",
        "stock_missing_native_key" if missing_from else "stock_supported",
        f"missing_from={','.join(missing_from) or 'none'}; default_status={default_status}",
        "The final native route needs one stable key across SystemUI creation, Settings editor rendering, and the optional candidate registry/default seeding path.",
        "v0.11 covers QSTileHost and QuickWidgetFactory offline; SettingsSmt/default seeding remain separate decisions.",
    )

    add(
        findings,
        "route",
        "editor-candidate integration route",
        "requires_framework_registry_patch" if TARGET_KEY not in registry else "candidate_route_available",
        f"SettingsUtil.getAdditionalNotificationWidgets uses SettingsSmt.NOTIFICATION_WIDGET; toggleDarkMode registry={'yes' if TARGET_KEY in registry else 'no'}",
        "This route avoids displacing a default first-page tile, but dark mode will appear in the editor/additional set only if SettingsSmt or an equivalent candidate path knows the key.",
        "Patch SettingsSmt registry only after framework/core gates are accepted, or patch SettingsSmartisan candidate generation locally.",
    )

    view_features = notification_custom_view_features(notification_view_text)
    local_route_available = all(
        view_features[key]
        for key in (
            "reads_additional_setting",
            "falls_back_to_settingsutil",
            "candidate_uses_factory",
            "saves_additional_setting",
            "reset_uses_default_additional",
        )
    )
    feature_summary = ",".join(f"{key}={'yes' if value else 'no'}" for key, value in sorted(view_features.items()))
    injection_status, injection_evidence = v011_candidate_injection_status()
    local_route_action = (
        "Candidate injection is offline-proven; live no-op gates have passed, so next manually verify the editor/additional UX route."
        if injection_status == "candidate_injection_proven_offline"
        else "Extend the v0.11 SettingsSmartisan patch and verifier to cover NotificationCustomView additional/default/reset paths."
    )
    add(
        findings,
        "route",
        "SettingsSmartisan-local editor candidate route",
        "settingssmartisan_local_candidate_patch_available" if local_route_available else "settingssmartisan_local_candidate_route_unclear",
        f"{rel(SETTINGS_NOTIFICATION_CUSTOM_VIEW)}: {feature_summary}",
        "SettingsSmartisan owns the visible candidate list and persists the additional list, so a local helper can append toggleDarkMode without modifying smartisanos.jar.",
        local_route_action,
    )

    add(
        findings,
        "route",
        "current stock/v0.11 candidate injection coverage",
        injection_status if not view_features["stock_mentions_target"] else "candidate_injection_present",
        f"stock NotificationCustomView mentions toggleDarkMode={'yes' if view_features['stock_mentions_target'] else 'no'}; {injection_evidence}",
        "QuickWidgetFactory rendering alone is not enough; the additional list must contain the key before the editor can offer it.",
        "" if injection_status == "candidate_injection_proven_offline" else "Patch getCurrentAdditionalQuickWidgetSettings(), getDefaultAdditionalOrderSettings()/reset, and checkValidity reset behavior consistently.",
    )

    add(
        findings,
        "route",
        "default-visible phone route",
        "requires_displacement",
        f"phone default list has {len(phone)} entries; QSTileHost truncates to first {MAX_FIRST_PAGE}",
        "Default visibility is a product decision, not a pure code requirement. Replacing a key is safer than appending a 21st entry.",
        "Use the candidate matrix and live-state report before choosing the displaced key.",
    )

    live_status, live_evidence = live_state_status()
    add(
        findings,
        "live_state",
        "current live QS state is available for migration/default decision",
        live_status,
        live_evidence,
        "A live data migration should not be designed from stock defaults alone because existing user data may differ.",
        "Run tools/r2-darkmode-live-state-audit.sh on a booted device.",
    )

    backup_text = read_text(SETTINGS_BACKUP_AGENT)
    if "arrayList.size() > 20" in backup_text and "expanded_widget_buttons_additional" in backup_text:
        add(
            findings,
            "restore",
            "backup/restore can split widget lists at 20 entries",
            "restore_split_mapped",
            f"{rel(SETTINGS_BACKUP_AGENT)}: arrayList.size() > 20@L{line_for(backup_text, 'arrayList.size() > 20')}",
            "Any default or migration plan must survive restore normalization into first-page and additional lists.",
        )

    util_text = read_text(SMARTISAN_SETTINGS_UTIL)
    if "getAdditionalNotificationWidgets" in util_text and "SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets()" in util_text:
        add(
            findings,
            "candidate_generation",
            "additional-widget generation is registry limited",
            "registry_limited",
            f"{rel(SMARTISAN_SETTINGS_UTIL)}: SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets@L{line_for(util_text, 'SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets()')}",
            "A native key added only to SystemUI will not automatically become selectable in the Smartisan editor.",
        )

    return findings


def write_tsv(rows: list[TileRow]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            [
                "list_name",
                "position",
                "key",
                "qstilehost",
                "quickwidget",
                "settingssmt",
                "default_presence",
                "displacement_class",
                "recommendation",
            ],
            delimiter="\t",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(row.__dict__)


def write_markdown(rows: list[TileRow], findings: list[Finding], defaults: dict[str, list[str]]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.status] = counts.get(finding.status, 0) + 1

    lines = [
        "# Dark Mode QS Strategy Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit maps how a native Smartisan `toggleDarkMode` QS",
        "entry can fit into the existing SettingsProvider defaults, SystemUI",
        "tile factory, SettingsSmartisan quick-widget editor, SettingsSmt",
        "candidate registry, and backup/restore split behavior. It does not",
        "modify APKs, images, the live device, or `/data`.",
        "",
        f"TSV output: `{OUT_TSV.relative_to(ROOT)}`",
        "",
        "## Summary",
        "",
    ]
    for status, count in sorted(counts.items()):
        lines.append(f"- {status}: {count}")

    lines.extend(
        [
            "",
            "## Default Lists",
            "",
            "| list | count | values |",
            "| --- | ---: | --- |",
        ]
    )
    for name, values in defaults.items():
        lines.append(f"| {name} | {len(values)} | `{' | '.join(values)}` |")

    lines.extend(
        [
            "",
            "## Findings",
            "",
            "| status | area | target | evidence | implication | next gate |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
    )
    for finding in findings:
        lines.append(
            "| "
            + " | ".join(
                cell.replace("|", "\\|")
                for cell in (
                    finding.status,
                    finding.area,
                    finding.target,
                    finding.evidence,
                    finding.implication,
                    finding.next_gate,
                )
            )
            + " |"
        )

    phone_candidates = [
        row
        for row in rows
        if row.list_name == "phone"
        and row.recommendation
        in {
            "candidate_only_after_live_usage_review",
            "candidate_if_dark_mode_replaces_display_comfort_slot",
        }
    ]
    lines.extend(
        [
            "",
            "## Phone Displacement Candidates",
            "",
            "These are static source candidates only. They do not choose a final",
            "product policy without live-state and user preference review.",
            "",
            "| position | key | class | recommendation | SystemUI | Settings editor | registry |",
            "| ---: | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in phone_candidates:
        lines.append(
            f"| {row.position} | `{row.key}` | {row.displacement_class} | {row.recommendation} | {row.qstilehost} | {row.quickwidget} | {row.settingssmt} |"
        )

    lines.extend(
        [
            "",
            "## Integration Routes",
            "",
            "1. Editor/additional route: add `toggleDarkMode` to SystemUI,",
            "   QuickWidgetFactory, and the SettingsSmt registry or an equivalent",
            "   SettingsSmartisan candidate path. This avoids displacing a stock",
            "   first-page phone tile.",
            "2. Default-visible route: replace exactly one key in",
            "   `def_notification_widget_buttons`; do not append a 21st key.",
            "   Candidate displacement needs live-state and product preference review.",
            "3. Live migration route: after the core APK no-op gates pass and live",
            "   QS state is captured, migrate existing `expanded_widget_buttons`",
            "   only with an explicit rollback/data plan.",
            "",
            "## Boundary",
            "",
            "- `toggleDarkMode` should remain one stable native Smartisan key.",
            "- A SystemUI-only tile is not enough for a polished integration because",
            "  the Settings editor and additional-widget generation are separate.",
            "- Default visibility is a seeding/migration decision, not part of the",
            "  current v0.11 APK-only behavior proof.",
        ]
    )

    OUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    defaults = default_lists()
    qshost = qstilehost_supported(read_text(SYSTEMUI_QS_HOST))
    quickwidget = literal_toggle_set(read_text(SETTINGS_WIDGET_FACTORY))
    registry = settingssmt_registry(read_text(SMARTISAN_SETTINGS_SMT))
    notification_view_text = read_text(SETTINGS_NOTIFICATION_CUSTOM_VIEW)
    rows = build_rows(defaults, qshost, quickwidget, registry)
    findings = audit_findings(defaults, qshost, quickwidget, registry, notification_view_text)
    write_tsv(rows)
    write_markdown(rows, findings, defaults)
    print(f"rows={len(rows)}")
    for status in sorted({finding.status for finding in findings}):
        print(f"{status}={sum(1 for finding in findings if finding.status == status)}")
    print(f"tsv={OUT_TSV.relative_to(ROOT)}")
    print(f"markdown={OUT_MD.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
