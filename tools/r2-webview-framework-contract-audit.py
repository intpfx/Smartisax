#!/usr/bin/env python3
"""Generate the Smartisax WebView framework contract audit.

This helper is read-only. It inspects local decoded framework, services,
SettingsSmartisan, and stock WebView sources. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write settings,
or modify /data.
"""

from __future__ import annotations

import csv
import json
import re
import zipfile
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
OUT_MD = ROOT / "docs" / "research" / "webview-framework-contract-audit.md"
OUT_TSV = KB / "manifest" / "webview-framework-contract-audit.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-framework-contract"
OUT_JSON = OUT_DIR / "webview-framework-contract-audit.json"

CONFIG_XML = (
    KB
    / "jadx"
    / "system__system__framework__framework-res.apk"
    / "resources"
    / "res"
    / "xml"
    / "config_webview_packages.xml"
)
SYSTEM_IMPL = (
    KB
    / "jadx"
    / "system__system__framework__services.jar"
    / "sources"
    / "com"
    / "android"
    / "server"
    / "webkit"
    / "SystemImpl.java"
)
WEBVIEW_UPDATER = (
    KB
    / "jadx"
    / "system__system__framework__services.jar"
    / "sources"
    / "com"
    / "android"
    / "server"
    / "webkit"
    / "WebViewUpdater.java"
)
USER_PACKAGE = (
    KB
    / "jadx"
    / "system__system__framework__framework.jar"
    / "sources"
    / "android"
    / "webkit"
    / "UserPackage.java"
)
WEBVIEW_FACTORY = (
    KB
    / "jadx"
    / "system__system__framework__framework.jar"
    / "sources"
    / "android"
    / "webkit"
    / "WebViewFactory.java"
)
WEBVIEW_LIBRARY_LOADER = (
    KB
    / "jadx"
    / "system__system__framework__framework.jar"
    / "sources"
    / "android"
    / "webkit"
    / "WebViewLibraryLoader.java"
)
SETTINGS_WEBVIEW_FRAGMENT = (
    KB
    / "jadx"
    / "system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "sources"
    / "com"
    / "android"
    / "settings"
    / "WebViewImplementationFragment.java"
)
SETTINGS_STRINGS = (
    KB
    / "jadx"
    / "system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
    / "resources"
    / "res"
    / "values"
    / "strings.xml"
)
STOCK_WEBVIEW_MANIFEST = (
    KB
    / "jadx"
    / "product__app__webview__webview.apk"
    / "resources"
    / "AndroidManifest.xml"
)
STOCK_WEBVIEW_APK = KB / "raw" / "product" / "app" / "webview" / "webview.apk"

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
WEBVIEW_PACKAGE = "com.android.webview"
WEBVIEW_LIBRARY_META = "com.android.webview.WebViewLibrary"
WEBVIEW_LIBRARY = "libwebviewchromium.so"
FACTORY_PROVIDER_R = "com.android.webview.chromium.WebViewChromiumFactoryProviderForR"
MIN_TARGET_SDK = 30
VERSION_CODE_DIVISOR = 100000


@dataclass(frozen=True)
class ProviderConfig:
    package_name: str
    description: str
    available_by_default: bool
    fallback: bool
    signature_count: int


@dataclass(frozen=True)
class StockWebViewFacts:
    package: str
    version_code: int
    version_name: str
    min_sdk: int
    target_sdk: int
    compile_sdk: int
    application_name: str
    library_meta: str
    sandbox_meta: int
    sandbox_service_count: int
    privileged_meta: int
    privileged_service_count: int
    provider_authorities: list[str]
    libs_by_abi: dict[str, list[str]]
    has_factory_provider_for_r: bool


@dataclass(frozen=True)
class ContractRow:
    area: str
    gate: str
    status: str
    observed: str
    requirement: str
    source: str
    route_impact: str
    next_gate: str


def rel(path: Path | None) -> str:
    if path is None:
        return "missing"
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def android_attr(node: ET.Element | None, name: str) -> str:
    if node is None:
        return ""
    return node.attrib.get(ANDROID_NS + name, "")


def parse_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def source_anchor(path: Path, pattern: str) -> str:
    text = read_text(path)
    for index, line in enumerate(text.splitlines(), start=1):
        if pattern in line:
            return f"{rel(path)}:{index}"
    return rel(path)


def grep_present(path: Path, pattern: str) -> bool:
    return pattern in read_text(path)


def parse_provider_config() -> list[ProviderConfig]:
    if not CONFIG_XML.exists():
        return []
    root = ET.parse(CONFIG_XML).getroot()
    providers = []
    for node in root.findall("webviewprovider"):
        providers.append(
            ProviderConfig(
                package_name=node.attrib.get("packageName", ""),
                description=node.attrib.get("description", ""),
                available_by_default=node.attrib.get("availableByDefault") == "true",
                fallback=node.attrib.get("isFallback") == "true"
                or node.attrib.get("fallback") == "true",
                signature_count=len(node.findall("signature")),
            )
        )
    return providers


def parse_stock_webview() -> StockWebViewFacts:
    manifest = ET.parse(STOCK_WEBVIEW_MANIFEST).getroot()
    application = manifest.find("application")
    uses_sdk = manifest.find("uses-sdk")
    metadata = {}
    sandbox_service_count = 0
    privileged_service_count = 0
    provider_authorities: list[str] = []
    if application is not None:
        for node in application.findall("meta-data"):
            name = android_attr(node, "name")
            value = android_attr(node, "value")
            if name:
                metadata[name] = value
        for node in application.findall("service"):
            name = android_attr(node, "name")
            if "SandboxedProcessService" in name:
                sandbox_service_count += 1
            if "PrivilegedProcessService" in name:
                privileged_service_count += 1
        for node in application.findall("provider"):
            authority = android_attr(node, "authorities")
            if authority:
                provider_authorities.append(authority)
    libs_by_abi: dict[str, list[str]] = {}
    with zipfile.ZipFile(STOCK_WEBVIEW_APK) as zf:
        for name in zf.namelist():
            if not name.startswith("lib/") or not name.endswith(".so"):
                continue
            parts = name.split("/")
            if len(parts) >= 3:
                libs_by_abi.setdefault(parts[1], []).append(parts[-1])
    libs_by_abi = {abi: sorted(set(values)) for abi, values in sorted(libs_by_abi.items())}
    has_factory = grep_present(
        KB
        / "jadx"
        / "product__app__webview__webview.apk"
        / "sources"
        / "com"
        / "android"
        / "webview"
        / "chromium"
        / "WebViewChromiumFactoryProviderForR.java",
        "return new WebViewChromiumFactoryProviderForR",
    )
    return StockWebViewFacts(
        package=manifest.attrib.get("package", ""),
        version_code=parse_int(android_attr(manifest, "versionCode")),
        version_name=android_attr(manifest, "versionName"),
        min_sdk=parse_int(android_attr(uses_sdk, "minSdkVersion")),
        target_sdk=parse_int(android_attr(uses_sdk, "targetSdkVersion")),
        compile_sdk=parse_int(android_attr(manifest, "compileSdkVersion")),
        application_name=android_attr(application, "name"),
        library_meta=metadata.get(WEBVIEW_LIBRARY_META, ""),
        sandbox_meta=parse_int(metadata.get("org.chromium.content.browser.NUM_SANDBOXED_SERVICES", "")),
        sandbox_service_count=sandbox_service_count,
        privileged_meta=parse_int(metadata.get("org.chromium.content.browser.NUM_PRIVILEGED_SERVICES", "")),
        privileged_service_count=privileged_service_count,
        provider_authorities=sorted(provider_authorities),
        libs_by_abi=libs_by_abi,
        has_factory_provider_for_r=has_factory,
    )


def provider_summary(providers: list[ProviderConfig]) -> str:
    if not providers:
        return "no providers parsed"
    return "; ".join(
        (
            f"{item.package_name} desc={item.description} "
            f"default={item.available_by_default} fallback={item.fallback} "
            f"signatures={item.signature_count}"
        )
        for item in providers
    )


def stock_summary(stock: StockWebViewFacts) -> str:
    return (
        f"package={stock.package}; version={stock.version_name}/{stock.version_code}; "
        f"targetSdk={stock.target_sdk}; library={stock.library_meta}; "
        f"sandbox={stock.sandbox_service_count}/{stock.sandbox_meta}; "
        f"privileged={stock.privileged_service_count}/{stock.privileged_meta}; "
        f"libs={stock.libs_by_abi}"
    )


def has_current_provider(providers: list[ProviderConfig]) -> bool:
    return any(item.package_name == WEBVIEW_PACKAGE for item in providers)


def build_rows(providers: list[ProviderConfig], stock: StockWebViewFacts) -> list[ContractRow]:
    available_count = sum(1 for item in providers if item.available_by_default)
    fallback_count = sum(1 for item in providers if item.fallback)
    min_version_floor = stock.version_code // VERSION_CODE_DIVISOR
    signature_config = next((item.signature_count for item in providers if item.package_name == stock.package), 0)
    settings_tips = "web_view_provider_tips" if grep_present(SETTINGS_STRINGS, "web_view_provider_tips") else "missing"
    rows = [
        ContractRow(
            "framework_config",
            "provider_whitelist",
            "ROUTE_A_AVAILABLE" if has_current_provider(providers) else "FAIL",
            provider_summary(providers),
            "A no-framework route must keep packageName=com.android.webview. Any other provider package needs config_webview_packages.xml work.",
            rel(CONFIG_XML),
            "Route A can stay product_b-only only when the donor is adapted to com.android.webview.",
            "Reject direct com.google.android.webview drop-in unless a framework-provider-add gate is planned.",
        ),
        ContractRow(
            "framework_config",
            "provider_config_boot_invariants",
            "PASS" if available_count >= 1 and fallback_count <= 1 else "FAIL",
            f"availableByDefault={available_count}; fallback={fallback_count}",
            "SystemImpl requires at least one available-by-default WebView package and at most one fallback; fallback must also be available by default.",
            source_anchor(SYSTEM_IMPL, "There must be at least one WebView package"),
            "Framework XML edits are boot-sensitive; avoid them for the first real donor if Route A is feasible.",
            "Keep the first donor-backed candidate on Route A when possible.",
        ),
        ContractRow(
            "validity",
            "target_sdk",
            "PASS" if stock.target_sdk >= MIN_TARGET_SDK else "FAIL",
            f"stock targetSdk={stock.target_sdk}; framework minimum={MIN_TARGET_SDK}",
            "WebViewUpdater rejects providers whose applicationInfo.targetSdkVersion is below 30.",
            source_anchor(USER_PACKAGE, "targetSdkVersion >= 30"),
            "Modern donors usually pass; BrowserChrome fails because it targets 28.",
            "Keep targetSdk >= 30 as a hard donor audit gate.",
        ),
        ContractRow(
            "validity",
            "minimum_version_code_cohort",
            "PASS",
            f"stock versionCode={stock.version_code}; floor comparison uses versionCode/{VERSION_CODE_DIVISOR}={min_version_floor}",
            "WebViewUpdater compares version codes by dividing both sides by 100000, using the lowest available-by-default factory package as the floor.",
            source_anchor(WEBVIEW_UPDATER, "versionCode1 / 100000"),
            "A modern donor should exceed the stock floor; malformed/backported version codes can still fail.",
            "Donor audit must compare longVersionCode cohorts, not only versionName.",
        ),
        ContractRow(
            "validity",
            "signature_or_system_app",
            "SYSTEM_APP_ROUTE_REQUIRED" if signature_config == 0 else "SIGNATURE_ROUTE_AVAILABLE",
            f"config signatures for {stock.package}={signature_config}; providerHasValidSignature accepts system apps",
            "A ROM system app is accepted regardless of config signatures; a non-system provider must match configured signatures.",
            source_anchor(WEBVIEW_UPDATER, "packageInfo.applicationInfo.isSystemApp()"),
            "Route A should install the provider as a ROM system product app; user-installed donors are not enough.",
            "Keep donor-backed WebView inside product_b or add explicit framework signature config work.",
        ),
        ContractRow(
            "validity",
            "webview_library_metadata",
            "PASS" if stock.library_meta == WEBVIEW_LIBRARY else "FAIL",
            f"stock meta {WEBVIEW_LIBRARY_META}={stock.library_meta}",
            "WebViewFactory.getWebViewLibrary(applicationInfo) must return the native library name.",
            source_anchor(WEBVIEW_FACTORY, WEBVIEW_LIBRARY_META),
            "Java manifest glue and native library must remain version-matched; lib-only swaps are invalid.",
            "Require the donor base manifest to expose WebViewLibrary and the APK/splits to contain that library.",
        ),
        ContractRow(
            "runtime",
            "factory_provider_class",
            "PASS" if stock.has_factory_provider_for_r else "FAIL",
            f"framework loads {FACTORY_PROVIDER_R}; stock class present={stock.has_factory_provider_for_r}",
            "Android 11 WebViewFactory loads WebViewChromiumFactoryProviderForR from the provider classloader.",
            source_anchor(WEBVIEW_FACTORY, "CHROMIUM_WEBVIEW_FACTORY"),
            "Modern donors that only ship newer factory class names need compatibility glue or a source build targeting Android 11.",
            "Keep this as a hard donor audit gate before ROM design.",
        ),
        ContractRow(
            "runtime",
            "native_relro_libraries",
            "PASS" if all(WEBVIEW_LIBRARY in values for values in stock.libs_by_abi.values()) else "FAIL",
            f"library={stock.library_meta}; libs_by_abi={stock.libs_by_abi}",
            "WebViewLibraryLoader creates relro files for 32-bit and 64-bit ABIs using the WebViewLibrary metadata value.",
            source_anchor(WEBVIEW_LIBRARY_LOADER, "createRelros"),
            "The donor must carry matching native libraries for the device ABI set or relro/native loading can fail after boot.",
            "Verify relro creation and WebView load on device after v0.31 live proof.",
        ),
        ContractRow(
            "runtime",
            "sandbox_service_count",
            "PASS" if stock.sandbox_meta == stock.sandbox_service_count else "FAIL",
            f"NUM_SANDBOXED_SERVICES={stock.sandbox_meta}; declarations={stock.sandbox_service_count}",
            "Chromium process launch code relies on the NUM_SANDBOXED_SERVICES manifest metadata matching declared SandboxedProcessService entries.",
            rel(STOCK_WEBVIEW_MANIFEST),
            "Split or source-built donors must keep metadata and service declarations together.",
            "Donor audit should fail mismatched metadata/service counts.",
        ),
        ContractRow(
            "settings",
            "settings_provider_selector",
            "RECORDED",
            "SettingsSmartisan lists getValidWebViewPackages filtered by Utils.isPackageEnabled; tip string=" + settings_tips,
            "Settings UI does not independently bless providers; it delegates validity to webviewupdate and warns about Big Bang/WebView surfaces for non-built-in WebView.",
            source_anchor(SETTINGS_WEBVIEW_FRAGMENT, "getValidWebViewPackages"),
            "Even a valid provider needs Settings selector and Smartisan Big Bang/WebView regression testing.",
            "Capture Settings WebView selector and Big Bang/WebView surfaces during live verification.",
        ),
        ContractRow(
            "route",
            "route_a_contract",
            "PREFERRED_AFTER_V031_LIVE",
            stock_summary(stock),
            "First real donor image should adapt/source-build a standalone com.android.webview-compatible provider in /product/app/webview after v0.31 live proof.",
            f"{rel(CONFIG_XML)}; {rel(WEBVIEW_UPDATER)}; {rel(WEBVIEW_FACTORY)}",
            "This keeps the first modernization candidate product_b-only and avoids early framework-res provider XML risk.",
            "Next offline work is donor material intake or source-build planning; next live gate is v0.31 stock near-noop.",
        ),
    ]
    return rows


def markdown_table(rows: list[ContractRow], area: str) -> str:
    subset = [row for row in rows if row.area == area]
    lines = [
        "| Gate | Status | Observed | Requirement | Route impact | Next gate |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in subset:
        values = [row.gate, row.status, row.observed, row.requirement, row.route_impact, row.next_gate]
        lines.append("| " + " | ".join(value.replace("|", "\\|").replace("\n", " ") for value in values) + " |")
    return "\n".join(lines)


def write_tsv(rows: list[ContractRow]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    columns = ["area", "gate", "status", "observed", "requirement", "source", "route_impact", "next_gate"]
    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def write_json(providers: list[ProviderConfig], stock: StockWebViewFacts, rows: list[ContractRow]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "providers": [asdict(item) for item in providers],
        "stock_webview": asdict(stock),
        "rows": [asdict(row) for row in rows],
    }
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_markdown(providers: list[ProviderConfig], stock: StockWebViewFacts, rows: list[ContractRow]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    source_list = [
        CONFIG_XML,
        SYSTEM_IMPL,
        WEBVIEW_UPDATER,
        USER_PACKAGE,
        WEBVIEW_FACTORY,
        WEBVIEW_LIBRARY_LOADER,
        SETTINGS_WEBVIEW_FRAGMENT,
        STOCK_WEBVIEW_MANIFEST,
    ]
    sources = "\n".join(f"- `{rel(path)}`" for path in source_list)
    content = f"""# WebView Framework Contract Audit

Generated: {generated}

This is a read-only offline audit. It inspects the local decoded R2 framework,
services, SettingsSmartisan, and stock WebView artifacts. It does not download
donors, build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Decision

Route A remains the preferred first real WebView modernization route:
adapt or source-build a standalone `com.android.webview` provider in place
under `/product/app/webview`, after the v0.31 stock provider near-noop gate is
live-proven.

Why: the stock framework whitelist contains only `{WEBVIEW_PACKAGE}`, Android 11
`WebViewUpdater` already accepts ROM system apps without configured signatures,
and the framework expects the Android 11 Chromium factory class
`{FACTORY_PROVIDER_R}` plus `{WEBVIEW_LIBRARY_META}` metadata.

## Source Files

{sources}

## Provider Config

{markdown_table(rows, "framework_config")}

## Validity Gates

{markdown_table(rows, "validity")}

## Runtime Gates

{markdown_table(rows, "runtime")}

## Settings And Smartisan Surfaces

{markdown_table(rows, "settings")}

## Route Contract

{markdown_table(rows, "route")}

## Stock WebView Shape

```text
{stock_summary(stock)}
providers={provider_summary(providers)}
```

## Donor Acceptance Checklist

For a donor to enter ROM image design without framework provider XML work, it
must satisfy all of these conditions:

1. Package identity or adapted manifest is `com.android.webview`.
2. `targetSdkVersion >= 30`.
3. `longVersionCode / 100000` is at least the stock provider cohort.
4. The package is installed as a ROM system app under product/system, or a
   separate framework signature route is designed.
5. Manifest metadata includes `{WEBVIEW_LIBRARY_META}` with a matching native
   WebView library.
6. Dex contains `{FACTORY_PROVIDER_R}` or compatible Android 11 factory glue.
7. Native WebView libraries cover the required device ABIs and can create relro
   files.
8. Sandboxed/privileged process metadata matches declared Chromium services.
9. Splits, native libraries, resources, and Java glue remain version-matched.
10. Live verification covers `cmd webviewupdate`, Settings selector, Big
    Bang/WebView surfaces, keyguard, launcher, resolver, and WebView-using apps.

## Outputs

- Markdown report: `{rel(OUT_MD)}`
- TSV manifest: `{rel(OUT_TSV)}`
- JSON snapshot: `{rel(OUT_JSON)}`
"""
    OUT_MD.write_text(content, encoding="utf-8")


def main() -> int:
    providers = parse_provider_config()
    stock = parse_stock_webview()
    rows = build_rows(providers, stock)
    write_tsv(rows)
    write_json(providers, stock, rows)
    write_markdown(providers, stock, rows)
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    print(f"providers={provider_summary(providers)}")
    print(f"stock={stock_summary(stock)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
