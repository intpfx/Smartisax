#!/usr/bin/env python3
"""Audit the stock BrowserChrome and WebView modernization contracts.

This helper is read-only. It does not build images, touch devices, flash,
reboot, erase partitions, write settings, or modify /data. It turns the stock
Smartisan BrowserChrome/WebView state into a repeatable contract checklist for
future modern WebView or browser donor APK work.
"""

from __future__ import annotations

import csv
import hashlib
import importlib.util
import re
import zipfile
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
INDEXES = KB / "indexes"
OUT_TSV = KB / "manifest" / "browser-webview-modernization-audit.tsv"
OUT_MD = ROOT / "docs" / "research" / "browser-webview-modernization-audit.md"
PREFLIGHT_PATH = ROOT / "tools" / "r2-rom-mod-preflight.py"

BROWSER_PACKAGE = "com.android.browser"
WEBVIEW_PACKAGE = "com.android.webview"
BROWSER_SOURCE = "system__system__app__BrowserChrome__BrowserChrome.apk"
WEBVIEW_SOURCE = "product__app__webview__webview.apk"

BROWSER_JADX = KB / "jadx" / BROWSER_SOURCE
WEBVIEW_JADX = KB / "jadx" / WEBVIEW_SOURCE
FRAMEWORK_RES_JADX = KB / "jadx" / "system__system__framework__framework-res.apk"
SERVICES_JADX = KB / "jadx" / "system__system__framework__services.jar"
SETTINGS_JADX = KB / "jadx" / "system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"

WEBVIEW_CONFIG = FRAMEWORK_RES_JADX / "resources/res/xml/config_webview_packages.xml"
SYSTEM_IMPL = SERVICES_JADX / "sources/com/android/server/webkit/SystemImpl.java"
WEBVIEW_UPDATER = SERVICES_JADX / "sources/com/android/server/webkit/WebViewUpdater.java"
WEBVIEW_FRAGMENT = SETTINGS_JADX / "sources/com/android/settings/WebViewImplementationFragment.java"

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


@dataclass(frozen=True)
class ContractRow:
    domain: str
    item: str
    stock_value: str
    evidence: str
    risk: str
    candidate_requirement: str
    next_gate: str


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def write_tsv(path: Path, rows: list[ContractRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "domain",
        "item",
        "stock_value",
        "evidence",
        "risk",
        "candidate_requirement",
        "next_gate",
    ]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row.__dict__)


def load_preflight() -> Any:
    spec = importlib.util.spec_from_file_location("r2_rom_mod_preflight", PREFLIGHT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {PREFLIGHT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_indexes() -> dict[str, list[dict[str, str]]]:
    names = [
        "packages",
        "components",
        "intent-filters",
        "uses-permissions",
        "privapp-permissions",
        "sysconfig-packages",
        "overlays",
        "signatures",
    ]
    return {name: read_rows(INDEXES / f"{name}.tsv") for name in names}


def package_row(indexes: dict[str, list[dict[str, str]]], package: str) -> dict[str, str]:
    for row in indexes["packages"]:
        if row.get("package") == package:
            return row
    return {}


def package_risk(indexes: dict[str, list[dict[str, str]]], package: str, action: str) -> tuple[str, str]:
    preflight = load_preflight()
    pkgs = preflight.package_rows(indexes, package)
    related = preflight.related_rows(indexes, package, preflight.source_names(pkgs))
    risks = preflight.assess(action, package, pkgs, related)
    level = preflight.worst_level(risks)
    return level, "; ".join(f"{risk_level}: {text}" for risk_level, text in risks)


def parse_xml(path: Path) -> ET.Element:
    return ET.parse(path).getroot()


def attr(node: ET.Element, name: str) -> str:
    return node.attrib.get(ANDROID_NS + name, "")


def manifest_path(source: str) -> Path:
    return KB / "jadx" / source / "resources" / "AndroidManifest.xml"


def raw_apk(indexes: dict[str, list[dict[str, str]]], package: str) -> Path:
    row = package_row(indexes, package)
    return Path(row["raw_path"])


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def zip_summary(path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        dex = [name for name in names if re.fullmatch(r"classes(\d*)\.dex", name)]
        libs = [name for name in names if name.startswith("lib/") and name.endswith(".so")]
        assets = [name for name in names if name.startswith("assets/")]
        by_abi = Counter(name.split("/")[1] for name in libs if len(name.split("/")) > 2)
        lib_names = sorted({Path(name).name for name in libs})
        interesting_assets = [
            name
            for name in assets
            if any(token in name.lower() for token in ["search", "webview", "agent", "navigation", "quick", "ttwebview"])
        ]
        return {
            "entry_count": len(names),
            "dex_count": len(dex),
            "lib_count": len(libs),
            "abis": ", ".join(f"{abi}:{count}" for abi, count in sorted(by_abi.items())),
            "key_libs": ", ".join(name for name in lib_names if name in {
                "libwebviewchromium.so",
                "libmonochrome.so",
                "libchrome.so",
                "libchromium_android_linker.so",
                "libcrashpad_handler_trampoline.so",
            }),
            "asset_markers": ", ".join(sorted(interesting_assets)[:12]),
        }


def component_counts(indexes: dict[str, list[dict[str, str]]], package: str) -> str:
    rows = [row for row in indexes["components"] if row.get("package") == package]
    counts = Counter(row.get("type", "") for row in rows)
    exported = sum(1 for row in rows if row.get("exported") == "true")
    return ", ".join(f"{key}={counts[key]}" for key in sorted(counts)) + f", exported={exported}, total={len(rows)}"


def provider_contracts(manifest: ET.Element) -> list[str]:
    app = manifest.find("application")
    if app is None:
        return []
    providers = []
    for node in app.findall("provider"):
        name = attr(node, "name")
        authorities = attr(node, "authorities")
        exported = attr(node, "exported") or "implicit"
        providers.append(f"{name} -> {authorities} exported={exported}")
    return providers


def application_contract(manifest: ET.Element) -> dict[str, str]:
    app = manifest.find("application")
    if app is None:
        return {}
    data = {
        "name": attr(app, "name"),
        "label": attr(app, "label"),
        "icon": attr(app, "icon"),
        "multiArch": attr(app, "multiArch"),
        "extractNativeLibs": attr(app, "extractNativeLibs"),
        "use32bitAbi": attr(app, "use32bitAbi"),
        "zygotePreloadName": attr(app, "zygotePreloadName"),
        "networkSecurityConfig": attr(app, "networkSecurityConfig"),
    }
    meta = []
    for node in app.findall("meta-data"):
        name = attr(node, "name")
        value = attr(node, "value") or attr(node, "resource")
        if name:
            meta.append(f"{name}={value}")
    data["meta"] = "; ".join(meta)
    return {key: value for key, value in data.items() if value}


def manifest_core(manifest: ET.Element) -> dict[str, str]:
    sdk = manifest.find("uses-sdk")
    return {
        "package": manifest.attrib.get("package", ""),
        "versionCode": attr(manifest, "versionCode"),
        "versionName": attr(manifest, "versionName"),
        "compileSdkVersion": attr(manifest, "compileSdkVersion"),
        "minSdkVersion": attr(sdk, "minSdkVersion") if sdk is not None else "",
        "targetSdkVersion": attr(sdk, "targetSdkVersion") if sdk is not None else "",
    }


def intent_filter_summary(indexes: dict[str, list[dict[str, str]]], package: str) -> dict[str, str]:
    rows = [row for row in indexes["intent-filters"] if row.get("package") == package]
    groups: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for row in rows:
        key = (row.get("component_type", ""), row.get("component_name", ""), row.get("filter_index", ""))
        groups.setdefault(key, []).append(row)

    main_launcher = []
    web_view = []
    boot_state = []
    for (kind, component, index), entries in groups.items():
        values = {entry.get("value", "") for entry in entries}
        data_values = sorted(entry.get("value", "") for entry in entries if entry.get("entry_type") == "data" and entry.get("value"))
        if "android.intent.action.MAIN" in values and "android.intent.category.LAUNCHER" in values:
            main_launcher.append(f"{kind}:{component}#{index}")
        if "android.intent.action.VIEW" in values and (
            "scheme=http" in data_values or "scheme=https" in data_values or "android.intent.category.BROWSABLE" in values
        ):
            web_view.append(f"{kind}:{component}#{index} data={','.join(data_values[:8])}")
        if values & {
            "android.intent.action.BOOT_COMPLETED",
            "android.intent.action.MY_PACKAGE_REPLACED",
            "android.intent.action.USER_PRESENT",
            "android.intent.action.LOCALE_CHANGED",
        }:
            boot_state.append(f"{kind}:{component}#{index} values={','.join(sorted(values))}")
    return {
        "main_launcher": " | ".join(main_launcher) or "none",
        "web_view": " | ".join(web_view[:8]) or "none",
        "boot_state": " | ".join(boot_state[:8]) or "none",
    }


def webview_providers() -> list[dict[str, str]]:
    root = parse_xml(WEBVIEW_CONFIG)
    rows = []
    for node in root.findall("webviewprovider"):
        signatures = [child.text or "" for child in node.findall("signature")]
        rows.append(
            {
                "packageName": node.attrib.get("packageName", ""),
                "description": node.attrib.get("description", ""),
                "availableByDefault": node.attrib.get("availableByDefault", "false"),
                "isFallback": node.attrib.get("isFallback", "false"),
                "signature_count": str(len(signatures)),
            }
        )
    return rows


def string_value(path: Path, name: str) -> str:
    if not path.exists():
        return ""
    try:
        root = parse_xml(path)
    except ET.ParseError:
        return ""
    for node in root.findall("string"):
        if node.attrib.get("name") == name:
            return "".join(node.itertext()).strip()
    return ""


def text_markers(path: Path, markers: list[str]) -> list[str]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    return [marker for marker in markers if marker in text]


def oat_vdex_paths() -> list[str]:
    base = KB / "raw/system/system/app/BrowserChrome"
    raw_paths = [rel(path) for path in sorted(base.rglob("*")) if path.suffix in {".odex", ".vdex", ".art"}] if base.exists() else []
    partition_rows = []
    for row in read_rows(KB / "manifest/partition-files.tsv"):
        rel_path = row.get("rel_path", "")
        if rel_path.startswith("system/app/BrowserChrome/") and Path(rel_path).suffix in {".odex", ".vdex", ".art"}:
            partition_rows.append(rel_path)
    return raw_paths or sorted(partition_rows)


def build_rows() -> list[ContractRow]:
    indexes = load_indexes()
    browser_manifest = parse_xml(manifest_path(BROWSER_SOURCE))
    webview_manifest = parse_xml(manifest_path(WEBVIEW_SOURCE))
    browser_pkg = package_row(indexes, BROWSER_PACKAGE)
    webview_pkg = package_row(indexes, WEBVIEW_PACKAGE)
    browser_apk = raw_apk(indexes, BROWSER_PACKAGE)
    webview_apk = raw_apk(indexes, WEBVIEW_PACKAGE)
    browser_zip = zip_summary(browser_apk)
    webview_zip = zip_summary(webview_apk)
    browser_core = manifest_core(browser_manifest)
    webview_core = manifest_core(webview_manifest)
    browser_app = application_contract(browser_manifest)
    webview_app = application_contract(webview_manifest)
    browser_intents = intent_filter_summary(indexes, BROWSER_PACKAGE)
    webview_intents = intent_filter_summary(indexes, WEBVIEW_PACKAGE)
    webview_config_rows = webview_providers()
    browser_risk, browser_flags = package_risk(indexes, BROWSER_PACKAGE, "replace")
    webview_risk, webview_flags = package_risk(indexes, WEBVIEW_PACKAGE, "replace")
    provider_packages = ", ".join(
        f"{row['packageName']} default={row['availableByDefault']} fallback={row['isFallback']} signatures={row['signature_count']}"
        for row in webview_config_rows
    )
    settings_tip = string_value(
        SETTINGS_JADX / "resources/res/values-zh-rCN/strings.xml",
        "web_view_provider_tips",
    ) or string_value(SETTINGS_JADX / "resources/res/values/strings.xml", "web_view_provider_tips")

    rows = [
        ContractRow(
            "scope",
            "modernization boundary",
            "BrowserChrome and WebView are separate modernization tracks",
            "docs/research/system-modification-route-audit.md; stock manifests",
            "RED",
            "Do not treat a browser APK donor as a WebView provider donor, or vice versa.",
            "Keep v0.30 audit as the entry gate before downloading or adapting donors.",
        ),
        ContractRow(
            "browser",
            "stock package identity",
            f"{browser_core}; path={browser_pkg.get('partition')}/{browser_pkg.get('rel_path')}; sha256={sha256(browser_apk)}",
            rel(browser_apk),
            browser_risk,
            "A same-package candidate must keep package identity or explicitly migrate every default-browser/provider/user-data contract.",
            "Build BrowserChrome no-op/minimal gate only after source/cache/icon coupling is mapped.",
        ),
        ContractRow(
            "browser",
            "static risk flags",
            browser_flags,
            rel(PREFLIGHT_PATH),
            browser_risk,
            "BrowserChrome replacement must be treated as RED until a no-op gate boots through keyguard/launcher.",
            "No browser behavior APK should be flashed before a BrowserChrome no-op gate.",
        ),
        ContractRow(
            "browser",
            "application and chromium preload",
            str(browser_app),
            rel(manifest_path(BROWSER_SOURCE)),
            "RED",
            "Preserve or intentionally replace SmartisanApplication, zygotePreloadName, network config, app icon/label, and Chromium tab metadata.",
            "Candidate audit must diff application/meta-data before any image build.",
        ),
        ContractRow(
            "browser",
            "provider authorities",
            " | ".join(provider_contracts(browser_manifest)),
            rel(manifest_path(BROWSER_SOURCE)),
            "RED",
            "Preserve content provider authorities such as com.android.browser and com.android.browser.browser unless a data migration exists.",
            "Add a provider-invariant verifier for BrowserChrome candidates.",
        ),
        ContractRow(
            "browser",
            "default browser intent surface",
            f"launcher={browser_intents['main_launcher']}; web={browser_intents['web_view']}",
            rel(INDEXES / "intent-filters.tsv"),
            "RED",
            "Preserve http/https/BROWSABLE/APP_BROWSER/default launcher behavior or rebuild default-browser resolver state deliberately.",
            "Browser no-op live gate must verify resolver, launcher, keyguard, and URL open behavior.",
        ),
        ContractRow(
            "browser",
            "boot and package-state receivers",
            browser_intents["boot_state"],
            rel(INDEXES / "intent-filters.tsv"),
            "ORANGE",
            "Preserve MY_PACKAGE_REPLACED, USER_PRESENT, LOCALE_CHANGED, and related receivers or understand startup side effects.",
            "Candidate source review must inspect receiver side effects and app data/cache interactions.",
        ),
        ContractRow(
            "browser",
            "native/dex/assets shape",
            f"dex={browser_zip['dex_count']}; libs={browser_zip['lib_count']} abis={browser_zip['abis']} key_libs={browser_zip['key_libs']} assets={browser_zip['asset_markers']}",
            rel(browser_apk),
            "RED",
            "A donor cannot be reduced to a few native libraries; Java glue, native ABI, assets, resources, and dex must remain version-matched.",
            "Compare candidate APK zip shape before any BrowserChrome patch plan.",
        ),
        ContractRow(
            "browser",
            "preoptimized oat/vdex",
            " | ".join(oat_vdex_paths()) or "none found",
            rel(KB / "raw/system/system/app/BrowserChrome"),
            "ORANGE",
            "If BrowserChrome dex changes, stale oat/vdex must be removed, regenerated, or proven ignored.",
            "No-op gate should record package dir mtime and oat/vdex handling.",
        ),
        ContractRow(
            "webview",
            "stock package identity",
            f"{webview_core}; path={webview_pkg.get('partition')}/{webview_pkg.get('rel_path')}; sha256={sha256(webview_apk)}",
            rel(webview_apk),
            webview_risk,
            "A system WebView candidate must either stay com.android.webview or be added to framework config_webview_packages.",
            "Start with a WebView stock no-op/near-no-op provider gate.",
        ),
        ContractRow(
            "webview",
            "static risk flags",
            webview_flags,
            rel(PREFLIGHT_PATH),
            webview_risk,
            "Even though WebView is not high-risk in the package list, provider validity and relro/zygote behavior make it a core runtime gate.",
            "Add WebView-specific offline and live verifiers before donor work.",
        ),
        ContractRow(
            "webview",
            "framework provider whitelist",
            provider_packages,
            rel(WEBVIEW_CONFIG),
            "RED",
            "Downloaded com.google.android.webview will not be a valid provider unless config_webview_packages is patched or the donor is adapted to com.android.webview.",
            "v0.31 should prove framework config/provider listing with stock before adding a donor.",
        ),
        ContractRow(
            "webview",
            "provider validity checks",
            "; ".join(text_markers(WEBVIEW_UPDATER, [
                "UserPackage.hasCorrectTargetSdkVersion",
                "getMinimumVersionCode",
                "providerHasValidSignature",
                "WebViewFactory.getWebViewLibrary",
                "Minimum targetSdkVersion: %d\", 30",
            ])),
            rel(WEBVIEW_UPDATER),
            "RED",
            "Candidate must pass targetSdk >= 30, minimum version-code cohort, signature/system-app rule, and WebViewLibrary metadata.",
            "Use r2-webview-donor-audit.py before any donor-backed image; it now fails fast on WebViewUpdater, factory-class, static-library, and bundle-shape blockers.",
        ),
        ContractRow(
            "webview",
            "application and WebViewLibrary metadata",
            str(webview_app),
            rel(manifest_path(WEBVIEW_SOURCE)),
            "RED",
            "Preserve WebViewApplication or equivalent glue and meta-data com.android.webview.WebViewLibrary=libwebviewchromium.so.",
            "WebView candidate audit must verify library name, ABI libs, and sandbox services.",
        ),
        ContractRow(
            "webview",
            "sandbox service contract",
            f"components={component_counts(indexes, WEBVIEW_PACKAGE)}; intent={webview_intents}",
            rel(INDEXES / "components.tsv"),
            "ORANGE",
            "Keep NUM_SANDBOXED_SERVICES and matching SandboxedProcessService declarations compatible with Android 11 WebViewFactory.",
            "No-op gate must verify dumpsys webviewupdate and WebView-using apps after boot.",
        ),
        ContractRow(
            "webview",
            "native/dex shape",
            f"dex={webview_zip['dex_count']}; libs={webview_zip['lib_count']} abis={webview_zip['abis']} key_libs={webview_zip['key_libs']} assets={webview_zip['asset_markers']}",
            rel(webview_apk),
            "RED",
            "Do not mix donor Java glue with stock native libs or stock Java glue with donor native libs; Android 11 also requires WebViewChromiumFactoryProviderForR.",
            "Compare donor WebView APK/APKM splits, factory class, static-library dependencies, and route before choosing adapt-in-place vs framework-whitelist.",
        ),
        ContractRow(
            "webview",
            "Settings provider selector",
            "; ".join(text_markers(WEBVIEW_FRAGMENT, [
                "IWebViewUpdateService",
                "getValidWebViewPackages",
                "changeProviderAndSetting",
                "getCurrentWebViewPackageName",
            ])),
            rel(WEBVIEW_FRAGMENT),
            "YELLOW",
            "Settings UI already delegates to webviewupdate; additional providers should appear if framework and validity checks pass.",
            "Read-only live audit should capture current Settings/WebView provider page before changing ROM.",
        ),
        ContractRow(
            "webview",
            "Smartisan Big Bang warning",
            settings_tip,
            rel(SETTINGS_JADX / "resources/res/values-zh-rCN/strings.xml"),
            "ORANGE",
            "Non-built-in WebView can break Smartisan WebView-based Big Bang surfaces; treat Big Bang as a regression test area.",
            "After WebView provider gate, test Settings warning path and Big Bang/WebView surfaces before integration ROM.",
        ),
        ContractRow(
            "system",
            "Smartisan resource/icon/package-cache coupling",
            "ResourcesManagerSmtEx/AssetManagerSmtEx icon redirection and Android 11 PackageCacher are known project coupling points.",
            "docs/research/resource-loading-map.md; v0.26a.1 package-cache evidence",
            "RED",
            "Browser/WebView candidates must bump package directory mtimes and account for /data/system/icon and package_cache state.",
            "Before any flash, prepare read-only live capture for package_cache, icon redirection, keyguard, launcher, and webviewupdate.",
        ),
        ContractRow(
            "roadmap",
            "next offline gates",
            "v0.30 audit -> donor adaptation audit -> v0.31 WebView stock near-noop gate -> live-state/live v0.31 gate -> donor-backed integration candidate -> BrowserChrome no-op gate",
            rel(OUT_MD),
            "YELLOW",
            "Advance by proving system contracts one gate at a time; no direct donor overwrite.",
            "Next donor-backed work must start from r2-webview-donor-audit.py output and preserve package mtime, stale oat/vdex handling, relro, webviewupdate, Settings selector, and Big Bang/WebView regression checks.",
        ),
    ]
    return rows


def markdown_table(rows: list[ContractRow], domain: str) -> str:
    subset = [row for row in rows if row.domain == domain]
    lines = [
        "| Item | Risk | Stock value | Candidate requirement | Next gate |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in subset:
        lines.append(
            "| "
            + " | ".join(
                text.replace("|", "\\|").replace("\n", " ")
                for text in [
                    row.item,
                    row.risk,
                    row.stock_value,
                    row.candidate_requirement,
                    row.next_gate,
                ]
            )
            + " |"
        )
    return "\n".join(lines)


def write_markdown(path: Path, rows: list[ContractRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    content = f"""# Browser/WebView Modernization Audit

Generated: {generated}

This is a read-only offline audit for the Smartisax browser/WebView
modernization backport. It does not build images, touch a device, flash,
reboot, erase partitions, write settings, or modify `/data`.

## Decision

BrowserChrome and WebView must be modernized as two separate tracks:

- `com.android.browser` is the stock Smartisan default browser package. It owns
  browser UI, default URL intent handling, bookmark/history providers,
  Smartisan resources, Chromium Java glue, native libraries, app data, package
  cache, and icon redirection coupling. The previous v0.3/v0.3.1 same-package
  replacement failure keeps this path RED until a no-op gate boots through
  keyguard and launcher.
- `com.android.webview` is the system WebView provider under `/product`. It is
  selected by `framework-res` `config_webview_packages.xml` and validated by
  `WebViewUpdateService`. A downloaded modern WebView APK is only donor
  material until it satisfies provider whitelist, target SDK, version, library,
  ABI, sandbox, and system-app/signature rules.

## BrowserChrome Contract

{markdown_table(rows, "browser")}

## WebView Provider Contract

{markdown_table(rows, "webview")}

## System Coupling

{markdown_table(rows, "system")}

## Roadmap

{markdown_table(rows, "roadmap")}

## Immediate Offline Next Steps

Completed:

- `tools/r2-webview-donor-audit.py` accepts APK/APKM/APKS/XAPK/ZIP inputs and
  checks WebViewUpdater gates, Android 11 factory class presence,
  Trichrome/static-library dependencies, multi-package bundle shape, split
  inventory, and the recommended adaptation route.
- `tools/r2-webview-donor-inbox-audit.py` scans local donor inboxes, computes
  hashes, forwards each APK/APKM/APKS/XAPK/ZIP candidate to the donor auditor
  and Trichrome bundle auditor, and writes the inbox manifest under
  `hard-rom/inspect/browser-webview-donor-inbox/`.
- `tools/r2-webview-trichrome-bundle-audit.py` classifies standalone WebView
  versus Trichrome/static-library package groups before image design.
- `tools/r2-webview-donor-source-plan.py` generates the donor source/route
  plan that separates stable com.android.webview adapt-in-place, framework
  provider-add, Trichrome/static-library, source-built Chromium, and rejected
  browser-APK routes.
- `tools/r2-webview-integration-plan.py` consumes donor, Trichrome bundle,
  inbox, live-state, and v0.31 evidence to produce Route A/B/C build-readiness
  blockers before any donor-backed image work.
- `tools/r2-browser-webview-live-state-audit.sh` captures the read-only live
  stock WebView/Browser state when a device is connected.
- `tools/r2-hardrom-build-v0.31-webview-stock-near-noop.sh` and
  `tools/r2-verify-v0.31-webview-stock-near-noop.sh` build and verify the
  stock WebView provider mtime-only image gate offline.

Remaining:

1. Run `tools/r2-browser-webview-live-state-audit.sh` on a connected, booted,
   unlocked device before flashing or live-verifying v0.31 and before any
   donor-backed WebView integration work.
2. Flash v0.31 only after explicit user confirmation, then run
   `tools/r2-verify-v0.31-webview-stock-near-noop.sh --read-only`.
3. Read `docs/research/webview-donor-source-plan.md`, then put the actual
   modern donor bundle into `apks/webview-donor-inbox/` or pass an explicit
   donor path to `tools/r2-webview-donor-inbox-audit.py`. Treat
   framework-provider-add and Trichrome/static-library routes as separate gated
   designs, not as a simple stock APK overwrite.
4. Run `tools/r2-webview-integration-plan.py` after donor intake to translate
   audit results into Route A/B/C image-design blockers and next gates.
5. Prepare a separate BrowserChrome no-op gate only after provider authorities,
   default intent filters, OAT/VDEX handling, package cache, and icon
   redirection live-state capture are specified.

## Outputs

- TSV manifest: `{rel(OUT_TSV)}`
- Markdown report: `{rel(OUT_MD)}`
"""
    path.write_text(content, encoding="utf-8")


def main() -> None:
    rows = build_rows()
    write_tsv(OUT_TSV, rows)
    write_markdown(OUT_MD, rows)
    print(f"wrote {OUT_TSV}")
    print(f"wrote {OUT_MD}")


if __name__ == "__main__":
    main()
