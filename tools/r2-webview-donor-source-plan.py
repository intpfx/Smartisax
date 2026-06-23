#!/usr/bin/env python3
"""Generate the Smartisax WebView donor source and route plan.

This helper is read-only. It does not download donors, build images, touch a
device, flash, reboot, erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_MD = ROOT / "docs" / "research" / "webview-donor-source-plan.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-donor-source-plan.tsv"
STOCK_AUDIT_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-donor" / "stock-webview-selftest" / "webview-donor-audit.json"
STOCK_BUNDLE_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-trichrome-bundle"
    / "stock-webview-standalone"
    / "trichrome-bundle-audit.json"
)
INBOX_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-inbox" / "webview-donor-inbox-audit.json"

WEB_SOURCES = [
    {
        "name": "Google Play stable Android System WebView",
        "url": "https://play.google.com/store/apps/details?id=com.google.android.webview",
        "snapshot": "Google LLC listing; updated on 2026-06-17 in the 2026-06-19 web snapshot.",
        "use": "Confirms the stable Google WebView channel is active, but the Play page is metadata only and not a raw APK source.",
    },
    {
        "name": "Google Play Android System WebView Dev",
        "url": "https://play.google.com/store/apps/details?id=com.google.android.webview.dev",
        "snapshot": "Google LLC listing; dev channel says it updates weekly and was updated on 2026-06-18 in the 2026-06-19 web snapshot.",
        "use": "Useful for shape/probing only; do not use dev/canary as the first stable ROM donor.",
    },
    {
        "name": "Chrome for Developers WebView overview",
        "url": "https://developer.chrome.com/docs/webview",
        "snapshot": "Last updated 2024-12-18 in the page snapshot.",
        "use": "Confirms WebView is Chromium-based, shares the rendering engine with Chrome for Android, and is updateable separately from Android.",
    },
]


@dataclass(frozen=True)
class RouteRow:
    route_id: str
    priority: str
    donor_material: str
    package_shape: str
    rom_design: str
    static_requirements: str
    blockers: str
    next_gate: str


@dataclass(frozen=True)
class RuleRow:
    rule_id: str
    category: str
    requirement: str
    reason: str
    evidence: str


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def stock_summary() -> dict[str, str]:
    data = read_json(STOCK_AUDIT_JSON)
    apks = data.get("apks", [])
    base = apks[0] if apks else {}
    return {
        "package": str(base.get("package", "unknown")),
        "version_name": str(base.get("version_name", "unknown")),
        "version_code": str(base.get("version_code", "unknown")),
        "target_sdk": str(base.get("target_sdk", "unknown")),
        "min_sdk": str(base.get("min_sdk", "unknown")),
        "abis": ", ".join(sorted((base.get("libs_by_abi") or {}).keys())) or "unknown",
        "factory_class": str(base.get("factory_provider_class_present", "unknown")),
        "route": str(data.get("adaptation_route", "unknown")),
        "bundle_verdict": str(read_json(STOCK_BUNDLE_JSON).get("verdict", "missing")),
        "bundle_classification": str(read_json(STOCK_BUNDLE_JSON).get("classification", "missing")),
    }


def inbox_summary() -> dict[str, str]:
    data = read_json(INBOX_JSON)
    candidates = data.get("candidates", [])
    audits = data.get("audits", [])
    return {
        "candidate_count": str(len(candidates)),
        "audit_count": str(len(audits)),
        "generated": str(data.get("generated", "missing")),
        "scan_roots": "; ".join(data.get("scan_roots", [])),
    }


def route_rows() -> list[RouteRow]:
    return [
        RouteRow(
            "A",
            "P0 preferred first donor class",
            "Standalone or source-built provider whose manifest package is already com.android.webview.",
            "One base APK or one base APK plus splits for the same package; no unrelated package names.",
            "Adapt in place under /product/app/webview after v0.31 live proof.",
            "targetSdk >= 30; minSdk <= 30; versionCode cohort >= stock; WebViewLibrary metadata; WebViewChromiumFactoryProviderForR; arm64-v8a libwebviewchromium.so; keep Java/native/splits version-matched.",
            "Modern public Google builds may no longer be standalone com.android.webview; if static libraries appear, route A is invalid.",
            "Run r2-webview-donor-inbox-audit.py, require donor audit PASS or an explicitly accepted WARN, then design a product_b replacement candidate.",
        ),
        RouteRow(
            "B",
            "P1 likely modern Google stable route",
            "com.google.android.webview stable donor from a user-provided Play or device-extraction bundle.",
            "Provider APK/APKM/APKS/XAPK, possibly split, package remains com.google.android.webview.",
            "Framework provider add: patch framework-res config_webview_packages.xml and ship the provider as a product/system app.",
            "All route A runtime gates plus framework provider XML gate, WebView selector behavior, package path/mtime, and system-app/signature validity.",
            "framework-res is a RED early-boot asset; provider package is not whitelisted by stock config; first framework resource no-op/live gate is required before this route is flashable.",
            "Audit donor with --allow-framework-config-patch only for design; build a framework/provider no-op chain before behavior integration.",
        ),
        RouteRow(
            "C",
            "P2 common current Google package shape",
            "Trichrome/static shared-library WebView bundle, normally provider plus com.google.android.trichromelibrary and matching splits.",
            "Multi-package bundle; all packages must be version-matched and certificate/static-library metadata must agree.",
            "Multi-package product/system ROM design plus framework provider add or package adaptation.",
            "All route B gates plus uses-static-library version/certDigest validation, TrichromeLibrary package install location, split layout, and PackageManager shared-library resolution.",
            "Not a single APK replacement. Missing or mismatched static libraries can break package scan before WebViewUpdateService is reached.",
            "Run r2-webview-trichrome-bundle-audit.py on the actual bundle and require resolved provider/library/static cert/version evidence before any image build.",
        ),
        RouteRow(
            "D",
            "P3 controlled but heavy route",
            "Self-built Chromium/AOSP WebView for Android 11/R, targeting com.android.webview.",
            "Source-built provider with known ABI outputs and no unexpected external package dependency.",
            "Adapt in place under /product/app/webview, potentially safest long-term once build reproducibility exists.",
            "Must produce Android 11-compatible WebView glue, WebViewChromiumFactoryProviderForR, relro-compatible native library, arm64-v8a and preferably armeabi-v7a, targetSdk >= 30.",
            "High build cost, toolchain storage/time, Chromium branch compatibility, and signing/package metadata details.",
            "Only start after route A/B/C donor audit proves public packages are blocked or too coupled.",
        ),
        RouteRow(
            "E",
            "Reject for first integration",
            "Chrome/Browser APK or stock BrowserChrome as a WebView donor.",
            "Browser package, not a WebView provider package.",
            "Do not use as WebView donor.",
            "Would need WebViewLibrary metadata, factory provider class, native WebView library, target/version/provider gates.",
            "Stock BrowserChrome negative audit already FAILs WebView donor gates; v0.3/v0.3.1 browser replacement broke boot/user UI.",
            "Keep BrowserChrome as a separate later no-op gate, not part of WebView provider modernization.",
        ),
    ]


def rule_rows() -> list[RuleRow]:
    return [
        RuleRow("R1", "version", "Prefer stable WebView channel for the first donor-backed ROM.", "Dev/Beta/Canary are useful for shape reconnaissance but too volatile for a base ROM provider.", "Google Play stable/dev listings and project rollback policy."),
        RuleRow("R2", "version", "Donor versionCode / 100000 must be >= stock factory cohort.", "Smartisan Android 11 WebViewUpdater compares provider cohorts against the minimum available-by-default provider.", "services.jar WebViewUpdater and stock donor audit."),
        RuleRow("R3", "sdk", "targetSdkVersion must be >= 30 and minSdkVersion must be <= 30.", "R2 is Android 11/API 30 and WebViewUpdater enforces correct target SDK.", "stock WebView donor audit gates."),
        RuleRow("R4", "runtime", "Donor must include WebViewLibrary metadata and matching libwebviewchromium.so.", "WebViewFactory.getWebViewLibrary must resolve a native library that exists in the provider or split set.", "stock WebView donor audit gates."),
        RuleRow("R5", "runtime", "Donor dex must contain com.android.webview.chromium.WebViewChromiumFactoryProviderForR or an explicitly framework-compatible substitute.", "R2 framework.jar loads the Android 11/R factory provider class.", "framework.jar WebViewFactory and donor audit."),
        RuleRow("R6", "abi", "arm64-v8a is mandatory; retain armeabi-v7a unless a live audit proves all dependent app paths are 64-bit-only.", "Stock WebView ships both arm64 and 32-bit libraries, and the ROM may still run 32-bit apps.", "stock APK inventory."),
        RuleRow("R7", "package", "One-package donors can use adapt-in-place only if package is com.android.webview.", "Stock framework-res whitelists only com.android.webview.", "config_webview_packages.xml."),
        RuleRow("R8", "package", "Any com.google.android.webview donor needs framework-provider-add or package adaptation.", "The provider is invisible to WebViewUpdateService until framework config exposes it.", "config_webview_packages.xml and donor route model."),
        RuleRow("R9", "package", "Any uses-static-library or Trichrome reference turns the work into a multi-package ROM design.", "PackageManager must resolve static shared libraries before the provider can even be considered valid.", "donor audit static_library_dependencies gate."),
        RuleRow("R9b", "package", "Trichrome bundles must pass the dedicated bundle audit before image design.", "The package group must prove one provider, one base APK per package, matching static-library versions, certDigest evidence when available, and arm64 WebView native code.", "tools/r2-webview-trichrome-bundle-audit.py."),
        RuleRow("R10", "rom", "Bump provider package directory mtime and remove/regenerate stale oat/vdex when dex/native code changes.", "Android 11 PackageCacher can reuse stale parsed package data when directory mtimes do not advance.", "v0.26a.1/v0.26a.2 lessons and v0.31 design."),
        RuleRow("R11", "live", "v0.31 stock provider must be live-proven before a donor-backed image.", "Need to prove WebViewUpdateService and PackageCacher tolerate the product_b mtime-only gate on this device.", "v0.31 offline candidate status."),
        RuleRow("R12", "regression", "Post-boot gates must include relro/webviewupdate, Settings WebView selector, Smartisan Big Bang/WebView surfaces, browser resolver, keyguard, and launcher.", "WebView is a core runtime provider and Smartisan Settings warns non-built-in WebView can affect Big Bang/WebView features.", "v0.30 audit and SettingsSmartisan source."),
    ]


def write_tsv(path: Path, routes: list[RouteRow], rules: list[RuleRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "priority_or_category", "requirement_or_material", "rom_design_or_reason", "evidence_or_next_gate"])
        for row in routes:
            writer.writerow(["route", row.route_id, row.priority, row.donor_material, row.rom_design, row.next_gate])
        for row in rules:
            writer.writerow(["rule", row.rule_id, row.category, row.requirement, row.reason, row.evidence])


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
    return lines


def write_markdown(path: Path, routes: list[RouteRow], rules: list[RuleRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    stock = stock_summary()
    inbox = inbox_summary()
    lines: list[str] = []
    lines.append("# WebView Donor Source Plan")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline planning report. It does not download donors,")
    lines.append("build images, touch a device, flash, reboot, erase partitions, write")
    lines.append("settings, or modify `/data`.")
    lines.append("")
    lines.append("## Current Baseline")
    lines.append("")
    lines.extend(
        md_table(
            ["Item", "Value"],
            [
                ["stock package", stock["package"]],
                ["stock version", f"{stock['version_name']} / {stock['version_code']}"],
                ["stock SDK", f"min={stock['min_sdk']} target={stock['target_sdk']}"],
                ["stock ABIs", stock["abis"]],
                ["Android 11 factory class present", stock["factory_class"]],
                ["stock route", stock["route"]],
                ["stock bundle audit", f"{stock['bundle_verdict']} / {stock['bundle_classification']}"],
                ["inbox candidates", inbox["candidate_count"]],
                ["inbox generated", inbox["generated"]],
            ],
        )
    )
    lines.append("")
    lines.append("Current inbox scan result: no external modern donor package is present in")
    lines.append("the project donor inboxes or Downloads.")
    lines.append("")
    lines.append("## Public Source Snapshot")
    lines.append("")
    lines.extend(md_table(["Source", "Snapshot", "Use"], [[s["name"], s["snapshot"], f"{s['use']} URL: {s['url']}"] for s in WEB_SOURCES]))
    lines.append("")
    lines.append("## Donor Route Priority")
    lines.append("")
    lines.extend(
        md_table(
            ["Route", "Priority", "Donor material", "ROM design", "Blockers", "Next gate"],
            [[row.route_id, row.priority, row.donor_material, row.rom_design, row.blockers, row.next_gate] for row in routes],
        )
    )
    lines.append("")
    lines.append("## Version And Compatibility Rules")
    lines.append("")
    lines.extend(md_table(["Rule", "Category", "Requirement", "Reason", "Evidence"], [[row.rule_id, row.category, row.requirement, row.reason, row.evidence] for row in rules]))
    lines.append("")
    lines.append("## Immediate Next Step")
    lines.append("")
    lines.append("1. Keep v0.31 as the next live provider gate; it is still the proof that")
    lines.append("   stock WebView survives product_b package-directory mtime refresh on R2.")
    lines.append("2. For donor work, place the actual stable donor bundle under")
    lines.append("   `apks/webview-donor-inbox/` and run")
    lines.append("   `tools/r2-webview-donor-inbox-audit.py --include-downloads`.")
    lines.append("3. If the donor reports any Trichrome/static-library refs, run")
    lines.append("   `tools/r2-webview-trichrome-bundle-audit.py <bundle>` and treat it as")
    lines.append("   route C, not as a single-APK product replacement.")
    lines.append("4. If the donor package is `com.google.android.webview`, treat it as route B")
    lines.append("   or C until framework/provider config work is explicitly gated.")
    lines.append("5. Run `tools/r2-webview-integration-plan.py` after donor intake to turn")
    lines.append("   donor/bundle audit outputs into explicit Route A/B/C image-design")
    lines.append("   blockers and next gates.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    routes = route_rows()
    rules = rule_rows()
    write_tsv(OUT_TSV, routes, rules)
    write_markdown(OUT_MD, routes, rules)
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"routes={len(routes)}")
    print(f"rules={len(rules)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
