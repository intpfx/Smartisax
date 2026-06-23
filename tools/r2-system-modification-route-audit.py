#!/usr/bin/env python3
"""Build a route-level audit for Smartisan hard-ROM system modifications.

This helper is read-only. It does not build images, touch devices, flash,
reboot, erase partitions, or modify /data. It translates user-facing change
classes into the project's gate language so future modifications start from a
consistent confidence boundary.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse/smartisan-8.5.3-rom-static"
OUT_TSV = KB / "manifest/system-modification-route-audit.tsv"
OUT_MD = ROOT / "docs/research/system-modification-route-audit.md"
INSPECT_DIR = ROOT / "hard-rom/inspect/system-modification-route-audit"
PREFLIGHT_PATH = ROOT / "tools/r2-rom-mod-preflight.py"


@dataclass(frozen=True)
class Route:
    route_id: str
    request_class: str
    target: str
    package: str
    action: str
    route: str
    confidence: str
    evidence: str
    required_gate: str
    next_step: str


def load_preflight() -> Any:
    spec = importlib.util.spec_from_file_location("r2_rom_mod_preflight", PREFLIGHT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {PREFLIGHT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict[str, str]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({col: row.get(col, "") for col in columns})


def readiness_rows() -> list[dict[str, str]]:
    return read_rows(KB / "manifest/system-modification-readiness-audit.tsv")


def readiness_match(needles: list[str]) -> tuple[str, str]:
    rows = readiness_rows()
    matches = []
    for row in rows:
        haystack = "\n".join([row.get("area", ""), row.get("requirement", ""), row.get("evidence", ""), row.get("gap", "")]).lower()
        if all(needle.lower() in haystack for needle in needles):
            matches.append(row)
    if not matches:
        return "missing", "no matching readiness row"
    parts = []
    for row in matches[:3]:
        gap = row.get("gap") or "no gap recorded"
        parts.append(f"{row.get('status')}: {row.get('requirement')} ({gap})")
    return matches[0].get("status", ""), "; ".join(parts)


def locale_summary() -> str:
    rows = read_rows(KB / "manifest/locale-prune-coverage-audit.tsv")
    if not rows:
        return "locale coverage audit missing"
    stock_dirs = sum(int(row.get("ja_ko_dirs") or 0) for row in rows)
    remaining = [row for row in rows if row.get("coverage_status") == "remaining_after_v0.4_v0.10"]
    remaining_dirs = sum(int(row.get("ja_ko_dirs") or 0) for row in remaining)
    apk_only = [row for row in rows if row.get("apk_only_variant")]
    v013 = [row for row in rows if row.get("coverage_status") == "pruned_in_v0.13_system_image"]
    return (
        f"stock={len(rows)} packages/{stock_dirs} ja-ko dirs; "
        f"remaining={len(remaining)} packages/{remaining_dirs} dirs; "
        f"v0.13={len(v013)} packages; apk_only={len(apk_only)} packages"
    )


def package_context(preflight: Any, indexes: dict[str, list[dict[str, str]]], package: str, action: str) -> dict[str, str]:
    if not package:
        return {
            "partition": "",
            "rel_path": "",
            "static_level": "N/A",
            "risk_flags": "",
        }
    pkgs = preflight.package_rows(indexes, package)
    sources = preflight.source_names(pkgs)
    rel = preflight.related_rows(indexes, package, sources)
    preflight_action = "replace" if action == "resource-prune" else action
    if preflight_action not in {"delete", "replace", "overlay", "inspect"}:
        preflight_action = "inspect"
    risks = preflight.assess(preflight_action, package, pkgs, rel)
    level = preflight.worst_level(risks)
    first = pkgs[0] if pkgs else {}
    return {
        "partition": first.get("partition", ""),
        "rel_path": first.get("rel_path", ""),
        "static_level": level,
        "risk_flags": "; ".join(f"{risk_level}: {text}" for risk_level, text in risks[:5]),
    }


def active_routes() -> list[Route]:
    settings_noop_status, settings_noop = readiness_match(["SettingsSmartisan no-op replacement", "booted and verified live"])
    systemui_noop_status, systemui_noop = readiness_match(["SmartisanSystemUI no-op replacement", "booted and verified live"])
    framework_noop_status, framework_noop = readiness_match(["framework-res no-op", "booted and verified live"])
    dark_live_status, dark_live = readiness_match(["UiMode", "QS settings", "read-only"])
    dark_functional_status, dark_functional = readiness_match(["reversible functional write", "toggleDarkMode tile creation"])
    lang_live_status, lang_live = readiness_match(["locale", "package path", "updated-system"])
    v011_status, v011 = readiness_match(["combined v0.11", "dark-mode ROM image"])
    v010_status, v010 = readiness_match(["v0.10 framework/product", "image verifies"])
    v013_super_status, v013_super = readiness_match(["v0.13 Tier1a", "flashable sparse super"])

    settings_gate = (
        "v0.25 current-base SettingsSmartisan no-op has booted and verified live."
        if settings_noop_status == "proven_live"
        else "v0.25 current-base SettingsSmartisan no-op must boot and verify live."
    )
    settings_next = (
        "For native dark mode, v0.11 has boot/package/hash plus UiMode/SystemUI functional proof; next manually validate the Settings row and QS editor UX."
        if dark_functional_status == "proven_live"
        else "For native dark mode, v0.11 has boot/package/hash proof; next validate Settings row, UiMode state changes, and QS editor/tile behavior."
        if v011_status == "proven_live"
        else "For native dark mode, run preflight and flash the combined v0.11 image only after explicit confirmation."
        if settings_noop_status == "proven_live" and systemui_noop_status == "proven_live"
        else "For Settings-only behavior patches, rebuild the exact-current behavior image and verify offline; for native dark mode, finish the SystemUI no-op live gate first."
        if settings_noop_status == "proven_live"
        else "Run tools/r2-live-flash-preflight.sh v0.25-settings-noop-on-v0.24, then request explicit flash confirmation."
    )
    systemui_gate = (
        "current-base SmartisanSystemUI certprobe no-op has booted and verified live."
        if systemui_noop_status == "proven_live"
        else "SmartisanSystemUI certprobe no-op must boot and verify live."
    )
    systemui_next = (
        "SystemUI tile creation is functionally proven on v0.11; next validate the Smartisan QS editor candidate path, then decide whether default-visible QS seeding or SettingsSmt registry patching is needed."
        if dark_functional_status == "proven_live"
        else "Validate the live v0.11 SystemUI tile creation/editor path, then decide whether default-visible QS seeding or SettingsSmt registry patching is needed."
        if v011_status == "proven_live"
        else "Run preflight and flash the combined v0.11 native dark-mode behavior image only after explicit confirmation."
        if systemui_noop_status == "proven_live"
        else "Run tools/r2-live-flash-preflight.sh systemui-certprobe-noop-on-v0.24 before any SystemUI behavior ROM."
    )
    darkmode_next = (
        "Manually validate Settings dark-mode row visibility/click behavior and Smartisan QS editor candidate behavior; then choose default-visible seeding or leave editor-first."
        if dark_functional_status == "proven_live"
        else "Run reversible functional testing for Settings dark-mode switch, UiModeManager night state, and Smartisan QS editor/toggleDarkMode behavior."
        if v011_status == "proven_live"
        else "Run tools/r2-live-flash-preflight.sh v0.11-native-darkmode, then ask for exact flash confirmation before any behavior flash."
        if v011_status == "candidate_offline"
        else "Build the exact-current v0.11 native dark-mode ROM image and verify it offline before any behavior flash."
        if settings_noop_status == "proven_live" and systemui_noop_status == "proven_live"
        else "Do not build v0.11 super until both component no-op gates pass live."
    )
    language_next = (
        "After dark-mode priority work allows, rebuild/test the visible list before coupling it to framework resource pruning."
        if settings_noop_status == "proven_live"
        else "After v0.25 passes and dark-mode priority work allows, rebuild/test visible list before coupling it to framework resource pruning."
    )

    return [
        Route(
            "delete_optional_app",
            "hard delete",
            "optional stock/system app",
            "com.smartisanos.appstore",
            "delete",
            "Remove package from the owning partition image, rebuild exact-current super, boot, verify package absence and launcher cleanup.",
            "proven_live_pattern",
            "v0.4 hard debloat proved the class on a low-coupling app; still run per-package preflight for every new target.",
            "Package-specific preflight plus local v0.4 rollback sparse image.",
            "Use tools/r2-rom-mod-preflight.py <package> --action delete, then build a small isolated ROM variant.",
        ),
        Route(
            "same_package_browser_replace",
            "same-package APK replacement",
            "BrowserChrome same package",
            "com.android.browser",
            "replace",
            "Do not reuse the old browser replacement path as a template; preserve package identity only after source/cache/icon/user-data coupling is mapped.",
            "known_failed_red",
            "v0.3/v0.3.1 reached a no-lockscreen/no-desktop state; same package name was not enough.",
            "Fresh package-source graph review, no-op/minimal probe, and explicit rollback plan.",
            "Prefer lower-risk modern browser routes unless the user explicitly wants another same-package browser experiment.",
        ),
        Route(
            "settings_core_apk_patch",
            "core shared-UID APK replacement",
            "SettingsSmartisan behavior patches",
            "com.android.settings",
            "replace",
            "Original-cert-preserving system-partition APK patch only; no self-signing. Behavior patches must wait behind the exact Settings no-op gate.",
            "ready_for_live_noop_gate" if settings_noop_status == "missing" else settings_noop_status,
            settings_noop,
            settings_gate,
            settings_next,
        ),
        Route(
            "systemui_core_apk_patch",
            "core shared-UID APK replacement",
            "SmartisanSystemUI behavior patches",
            "com.android.systemui",
            "replace",
            "Same-size/original-cert-readable SystemUI gate first, then native tile behavior patches.",
            "ready_for_live_noop_gate" if systemui_noop_status == "missing" else systemui_noop_status,
            systemui_noop,
            systemui_gate,
            systemui_next,
        ),
        Route(
            "native_dark_mode",
            "feature integration",
            "native toggleDarkMode across SettingsSmartisan and SystemUI",
            "",
            "multi-apk-code",
            "Use UiModeManager backend, Settings hidden row, SystemUI native tile key, QuickWidgetFactory rendering, and NotificationCustomView candidate injection.",
            "live_functional_ux_pending"
            if dark_functional_status == "proven_live" and v011_status == "proven_live"
            else "apk_semantics_proven_offline_gated",
            f"{v011_status}: {v011}; live-state: {dark_live}; functional: {dark_functional_status}: {dark_functional}",
            "Dark-mode live-state, Settings no-op live gate, SystemUI no-op live gate, combined v0.11 live boot/package proof, reversible UiMode/SystemUI functional proof, then manual Settings/QS editor UX proof.",
            darkmode_next,
        ),
        Route(
            "settingsprovider_defaults",
            "settings/default migration",
            "SettingsProvider widget/default settings",
            "com.android.providers.settings",
            "replace",
            "Treat defaults and migrations as data-contract changes, not just APK edits; backup/restore and upgrade cleanup can rewrite QS lists.",
            "mapped_but_no_component_gate",
            "Playbook maps DatabaseHelper, SettingsProvider upgrade, and SettingsBackupAgent paths; no no-op live gate exists yet.",
            "Build and live-verify a SettingsProvider no-op gate before default seeding or migrations.",
            "Keep default-visible dark-mode tile as a later decision after live QS state is captured.",
        ),
        Route(
            "language_visible_picker",
            "Settings behavior patch",
            "Smartisan visible language picker",
            "com.android.settings",
            "replace",
            "Patch LocalePickerFragment visible list only after SettingsSmartisan no-op gate; this hides entries but does not prune resources.",
            "apk_semantics_proven_offline_gated",
            "v0.7 locale-filter verifier proves constructAdapter skip logic offline; visible filter is not physical hard-prune.",
            "v0.25 current-base SettingsSmartisan no-op live gate plus language live-state capture.",
            language_next,
        ),
        Route(
            "language_framework_assets",
            "framework resource replacement",
            "framework-res, framework-smartisanos-res, android static overlays",
            "android",
            "resource-prune",
            "Use framework-res no-op as early-boot gate; use binary resources.arsc pruning for Smartisan framework resources.",
            "framework_candidate_offline_gated",
            f"framework live gate: {framework_noop}; v0.10 verifier: {v010_status}: {v010}",
            "v0.12 framework-res no-op must boot live before v0.10 language hard-prune.",
            "Flash only after explicit confirmation; verify Resources.getSystem().getAssets().getLocales() and boot UI.",
        ),
        Route(
            "language_app_resource_prune",
            "app resource hard-prune",
            "package-local non-English/non-Chinese resources",
            "",
            "resource-prune",
            "Preserve APK shell, manifest, and code; change resources.arsc only; promote APK-only candidates into ROM images in small batches.",
            "toolchain_offline_proven_coverage_incomplete",
            f"{locale_summary()}; v0.13 sparse: {v013_super_status}: {v013_super}",
            "Build sparse super for v0.13, then verify and live-test selected low-exposure package batch.",
            "Continue from Tier1a/Tier1b candidates before core APEX, provider, keyboard, phone, or permission packages.",
        ),
        Route(
            "keyguard_launcher_boot_surface",
            "boot UI surface",
            "Keyguard and Launcher",
            "",
            "replace",
            "Treat as boot-critical UI; no package-index-only build is acceptable.",
            "red_requires_new_gates",
            "Keyguard uses android.uid.system and Launcher owns HOME; previous browser failure showed lockscreen/desktop coupling can surface indirectly.",
            "Focused graph/source review plus per-component no-op gate and rollback strategy.",
            "Do not edit until the user explicitly chooses this risk tier.",
        ),
        Route(
            "phone_telephony_surface",
            "phone/telephony surface",
            "TeleService, Telecom, TelephonyProvider, InCallUI, MMS",
            "com.android.phone",
            "replace",
            "Treat calls, SIM, MCC, provider state, permissions, and shared UIDs as one coupled surface.",
            "red_requires_new_gates",
            "Phone uses android.uid.phone; language pruning also touches SIM/MCC locale helpers.",
            "Separate source graph, no-op gates, and live call/SIM validation before behavior changes.",
            "Defer until lower-risk language/resource gates have passed.",
        ),
    ]


def parse_package_action(value: str) -> tuple[str, str]:
    if ":" not in value:
        return value, "inspect"
    package, action = value.split(":", 1)
    return package, action or "inspect"


def ad_hoc_routes(package_actions: list[str], preflight: Any, indexes: dict[str, list[dict[str, str]]]) -> list[Route]:
    routes: list[Route] = []
    for item in package_actions:
        package, action = parse_package_action(item)
        ctx = package_context(preflight, indexes, package, action)
        level = ctx["static_level"]
        if level in {"BLOCK", "RED"}:
            confidence = "red_or_blocked_static_preflight"
            gate = "Focused source/graph review and an explicit live no-op or rollback gate are required."
        elif level == "ORANGE":
            confidence = "requires_source_graph_review"
            gate = "Small isolated build only after source review and exact-current rollback readiness."
        elif level == "YELLOW":
            confidence = "candidate_after_standard_gates"
            gate = "Image verifier, rollback image, and focused post-boot smoke."
        else:
            confidence = "low_static_risk_candidate"
            gate = "Normal image verifier and flash protocol."
        routes.append(
            Route(
                f"adhoc_{package}_{action}".replace(".", "_").replace("-", "_"),
                "ad hoc package request",
                package,
                package,
                action,
                f"Package-action preflight imported from r2-rom-mod-preflight.py; static level {level}.",
                confidence,
                ctx["risk_flags"] or "no risk flags",
                gate,
                f"Run tools/r2-rom-mod-preflight.py {package} --action {action} for the full table.",
            )
        )
    return routes


def render_rows(routes: list[Route], preflight: Any, indexes: dict[str, list[dict[str, str]]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for route in routes:
        ctx = package_context(preflight, indexes, route.package, route.action)
        rows.append(
            {
                "route_id": route.route_id,
                "request_class": route.request_class,
                "target": route.target,
                "package": route.package,
                "partition": ctx["partition"],
                "rel_path": ctx["rel_path"],
                "action": route.action,
                "static_level": ctx["static_level"],
                "confidence": route.confidence,
                "route": route.route,
                "evidence": route.evidence,
                "risk_flags": ctx["risk_flags"],
                "required_gate": route.required_gate,
                "next_step": route.next_step,
            }
        )
    return rows


def md_table(rows: list[dict[str, str]]) -> list[str]:
    columns = ["route_id", "target", "action", "static_level", "confidence", "required_gate", "next_step"]
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    for row in rows:
        values = []
        for col in columns:
            value = (row.get(col, "") or "").replace("|", "\\|").replace("\n", " ")
            if len(value) > 180:
                value = value[:177] + "..."
            values.append(value)
        lines.append("| " + " | ".join(values) + " |")
    return lines


def write_markdown(rows: list[dict[str, str]], out_md: Path, out_tsv: Path) -> None:
    status_counts: dict[str, int] = {}
    for row in rows:
        status_counts[row["confidence"]] = status_counts.get(row["confidence"], 0) + 1
    summary = ", ".join(f"{key}={value}" for key, value in sorted(status_counts.items()))
    lines: list[str] = [
        "# System Modification Route Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "Purpose:",
        "",
        "```text",
        "Translate user-facing system modification requests into concrete hard-ROM",
        "routes, current confidence, required no-op/live gates, and the next safe",
        "step. This report is generated read-only and does not authorize flashing.",
        "```",
        "",
        "Summary:",
        "",
        "```text",
        f"routes={len(rows)}",
        f"confidence_counts={summary}",
        "```",
        "",
        "Core conclusion:",
        "",
        "```text",
        "We now have enough source and graph structure to choose precise edit",
        "surfaces. The remaining confidence boundary is live acceptance of each",
        "replacement layer: SettingsSmartisan, SmartisanSystemUI, framework-res,",
        "and later SettingsProvider/Keyguard/Launcher/Phone each need their own",
        "gate. Do not transfer a pass from one layer to another.",
        "```",
        "",
        "How to use:",
        "",
        "```bash",
        "tools/r2-system-modification-route-audit.py",
        "tools/r2-system-modification-route-audit.py --package-action com.android.phone:replace",
        "tools/r2-rom-mod-preflight.py <package> --action delete",
        "tools/r2-live-flash-preflight.sh <variant>",
        "```",
        "",
        "## Route Matrix",
        "",
        *md_table(rows),
        "",
        "## Gate Order For Current Goals",
        "",
        "```text",
        "1. Capture dark-mode and language live-state read-only when the phone is visible to adb.",
        "2. Keep the v0.25 current-base SettingsSmartisan live proof as the Settings behavior patch gate.",
        "3. Keep the current-base SmartisanSystemUI live proof as the SystemUI behavior patch gate.",
        "4. Treat v0.11 boot/package/hash plus UiMode/SystemUI functional proof as live; next manually prove Settings row and QS editor UX.",
        "5. Flash/verify v0.12 framework-res no-op before v0.10 framework language pruning.",
        "6. Promote low-exposure APK-only language prune candidates into ROM images in small batches.",
        "7. Only then move toward SettingsProvider defaults, Keyguard/Launcher, or phone/telephony surfaces.",
        "```",
        "",
        "Generated TSV:",
        "",
        "```text",
        str(out_tsv.relative_to(ROOT)),
        "```",
    ]
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--package-action",
        action="append",
        default=[],
        help="Add an ad hoc package route as PACKAGE:ACTION, e.g. com.android.phone:replace.",
    )
    args = parser.parse_args()

    preflight = load_preflight()
    indexes = preflight.load_indexes(KB)
    routes = active_routes() + ad_hoc_routes(args.package_action, preflight, indexes)
    rows = render_rows(routes, preflight, indexes)
    if args.package_action:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        out_tsv = INSPECT_DIR / f"system-modification-route-audit-{stamp}.tsv"
        out_md = INSPECT_DIR / f"system-modification-route-audit-{stamp}.md"
    else:
        out_tsv = OUT_TSV
        out_md = OUT_MD
    columns = [
        "route_id",
        "request_class",
        "target",
        "package",
        "partition",
        "rel_path",
        "action",
        "static_level",
        "confidence",
        "route",
        "evidence",
        "risk_flags",
        "required_gate",
        "next_step",
    ]
    write_tsv(out_tsv, rows, columns)
    write_markdown(rows, out_md, out_tsv)

    print(f"routes={len(rows)}")
    for key in sorted({row["confidence"] for row in rows}):
        print(f"{key}={sum(1 for row in rows if row['confidence'] == key)}")
    print(f"tsv={out_tsv.relative_to(ROOT)}")
    print(f"markdown={out_md.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
