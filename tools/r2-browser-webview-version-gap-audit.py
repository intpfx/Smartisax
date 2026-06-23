#!/usr/bin/env python3
"""Generate a BrowserChrome/WebView version and route gap audit.

This helper is read-only. It inspects the stock Smartisan BrowserChrome and
WebView APKs plus existing offline gate reports. It does not download donors,
build images, touch devices, flash, reboot, erase partitions, write settings,
or modify /data.
"""

from __future__ import annotations

import csv
import glob
import hashlib
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
INDEXES = KB / "indexes"
OUT_MD = ROOT / "docs" / "research" / "browser-webview-version-gap-audit.md"
OUT_TSV = KB / "manifest" / "browser-webview-version-gap-audit.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-version-gap-audit"
OUT_JSON = OUT_DIR / "browser-webview-version-gap-audit.json"

BROWSER_PACKAGE = "com.android.browser"
WEBVIEW_PACKAGE = "com.android.webview"
BROWSER_SOURCE = "system__system__app__BrowserChrome__BrowserChrome.apk"
WEBVIEW_SOURCE = "product__app__webview__webview.apk"
BROWSER_APK = KB / "raw" / "system" / "system" / "app" / "BrowserChrome" / "BrowserChrome.apk"
WEBVIEW_APK = KB / "raw" / "product" / "app" / "webview" / "webview.apk"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

V031_DIR = ROOT / "hard-rom" / "inspect" / "v0.31-webview-stock-near-noop"
V032_DIR = ROOT / "hard-rom" / "inspect" / "v0.32-browserchrome-stock-near-noop"
LIVE_STATE_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-live-state"
INBOX_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-inbox" / "webview-donor-inbox-audit.json"
INTEGRATION_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-integration-plan" / "webview-integration-plan.json"


@dataclass(frozen=True)
class ApkFacts:
    label: str
    package: str
    apk: str
    sha256: str
    size_bytes: int
    version_code: str
    version_name: str
    min_sdk: str
    target_sdk: str
    compile_sdk: str
    engine_versions: list[str]
    engine_milestones: list[int]
    version_confidence: str
    dex_count: int
    lib_count: int
    libs_by_abi: dict[str, int]
    key_libs: list[str]
    asset_count: int
    notable_assets: list[str]
    zip_entry_count: int
    component_summary: str
    provider_count: int
    exported_count: int


@dataclass(frozen=True)
class GapRow:
    track: str
    item: str
    status: str
    observed: str
    evidence: str
    implication: str
    next_gate: str


def rel(path: Path | None) -> str:
    if path is None:
        return "missing"
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def latest(pattern: str) -> Path | None:
    matches = [Path(path) for path in glob.glob(pattern)]
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def manifest_path(source: str) -> Path:
    return KB / "jadx" / source / "resources" / "AndroidManifest.xml"


def parse_manifest(source: str) -> ET.Element:
    return ET.parse(manifest_path(source)).getroot()


def attr(node: ET.Element | None, name: str) -> str:
    if node is None:
        return ""
    return node.attrib.get(ANDROID_NS + name, "")


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def components(package: str) -> list[dict[str, str]]:
    return [row for row in read_rows(INDEXES / "components.tsv") if row.get("package") == package]


def component_summary(package: str) -> tuple[str, int, int]:
    rows = components(package)
    counts = Counter(row.get("type", "") for row in rows)
    exported = sum(1 for row in rows if row.get("exported") == "true")
    providers = counts.get("provider", 0)
    summary = ", ".join(f"{kind}={counts[kind]}" for kind in sorted(counts))
    return f"{summary}, exported={exported}, total={len(rows)}", providers, exported


def ascii_strings(data: bytes, *, min_len: int = 4) -> list[str]:
    return [match.decode("utf-8", errors="ignore") for match in re.findall(rb"[ -~]{4,}", data)]


def version_key(version: str) -> tuple[int, int, int, int]:
    parts = [int(part) for part in version.split(".")[:4]]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)  # type: ignore[return-value]


def chromium_like(version: str) -> bool:
    major, minor, build, patch = version_key(version)
    return 30 <= major <= 150 and minor == 0 and build >= 100 and patch >= 1


def version_signals(apk: Path, interesting_entries: set[str]) -> list[str]:
    versions: set[str] = set()
    ua_versions: set[str] = set()
    with zipfile.ZipFile(apk) as zf:
        for info in zf.infolist():
            name = info.filename
            if name not in interesting_entries and not re.fullmatch(r"classes(\d*)\.dex", name):
                continue
            with zf.open(info) as fh:
                data = fh.read()
            for text in ascii_strings(data):
                for match in re.findall(r"(?:Chrome|Chromium|WebView)/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)", text):
                    ua_versions.add(match)
                for match in re.findall(r"\b([0-9]{2,3}\.[0-9]{1,4}\.[0-9]{1,5}\.[0-9]{1,5})\b", text):
                    versions.add(match)
    filtered = [value for value in (ua_versions | versions) if chromium_like(value)]
    if not filtered:
        return []
    # APKs can contain old user-agent examples or compatibility resources.
    # The highest Chromium milestone is the useful engine signal for this audit.
    max_major = max(version_key(value)[0] for value in filtered)
    return sorted({value for value in filtered if version_key(value)[0] == max_major}, key=version_key)


def zip_facts(apk: Path) -> tuple[int, int, dict[str, int], list[str], int, list[str], int]:
    with zipfile.ZipFile(apk) as zf:
        names = zf.namelist()
        dex_count = sum(1 for name in names if re.fullmatch(r"classes(\d*)\.dex", name))
        libs = [name for name in names if name.startswith("lib/") and name.endswith(".so")]
        libs_by_abi = Counter(name.split("/")[1] for name in libs if len(name.split("/")) >= 3)
        lib_names = sorted({Path(name).name for name in libs})
        key_libs = [
            name
            for name in lib_names
            if name in {
                "libchrome.so",
                "libwebviewchromium.so",
                "libmonochrome.so",
                "libchromium_android_linker.so",
                "libcrashpad_handler_trampoline.so",
            }
        ]
        assets = [name for name in names if name.startswith("assets/")]
        notable_assets = [
            name
            for name in assets
            if any(token in name.lower() for token in ["webview", "chrome_100", "resources.pak", "icudtl", "search", "ttwebview"])
        ][:20]
        return dex_count, len(libs), dict(sorted(libs_by_abi.items())), key_libs, len(assets), notable_assets, len(names)


def apk_facts(label: str, package: str, source: str, apk: Path, interesting_entries: set[str]) -> ApkFacts:
    manifest = parse_manifest(source)
    uses_sdk = manifest.find("uses-sdk")
    versions = version_signals(apk, interesting_entries)
    version_name = attr(manifest, "versionName")
    if package == WEBVIEW_PACKAGE and version_name and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", version_name):
        versions = sorted(set(versions + [version_name]), key=version_key)
        confidence = "manifest+payload" if len(versions) > 1 else "manifest"
    elif versions:
        confidence = "payload-string"
    else:
        confidence = "missing"
    milestones = sorted({version_key(value)[0] for value in versions})
    dex_count, lib_count, libs_by_abi, key_libs, asset_count, notable_assets, zip_count = zip_facts(apk)
    summary, provider_count, exported_count = component_summary(package)
    return ApkFacts(
        label=label,
        package=package,
        apk=rel(apk),
        sha256=sha256(apk),
        size_bytes=apk.stat().st_size,
        version_code=attr(manifest, "versionCode"),
        version_name=version_name,
        min_sdk=attr(uses_sdk, "minSdkVersion"),
        target_sdk=attr(uses_sdk, "targetSdkVersion"),
        compile_sdk=attr(manifest, "compileSdkVersion"),
        engine_versions=versions,
        engine_milestones=milestones,
        version_confidence=confidence,
        dex_count=dex_count,
        lib_count=lib_count,
        libs_by_abi=libs_by_abi,
        key_libs=key_libs,
        asset_count=asset_count,
        notable_assets=notable_assets,
        zip_entry_count=zip_count,
        component_summary=summary,
        provider_count=provider_count,
        exported_count=exported_count,
    )


def pass_report(path: Path | None, marker: str = "PASS") -> bool:
    if path is None:
        return False
    text = read_text(path)
    return marker in text


def facts_summary(facts: ApkFacts) -> str:
    engine = ", ".join(facts.engine_versions) or "unknown"
    milestones = ", ".join(str(value) for value in facts.engine_milestones) or "unknown"
    return (
        f"package={facts.package}; appVersion={facts.version_name}/{facts.version_code}; "
        f"targetSdk={facts.target_sdk}; compileSdk={facts.compile_sdk}; "
        f"engineVersions={engine}; milestones={milestones}; confidence={facts.version_confidence}"
    )


def build_rows(browser: ApkFacts, webview: ApkFacts) -> list[GapRow]:
    v031_offline = latest(str(V031_DIR / "verify-v0.31-webview-stock-near-noop-offline-image-*.txt"))
    v031_device = latest(str(V031_DIR / "verify-v0.31-webview-stock-near-noop-device-*.txt"))
    v032_offline = latest(str(V032_DIR / "verify-v0.32-browserchrome-stock-near-noop-offline-image-*.txt"))
    v032_device = latest(str(V032_DIR / "verify-v0.32-browserchrome-stock-near-noop-device-*.txt"))
    live_state = latest(str(LIVE_STATE_DIR / "browser-webview-live-state-*.txt"))
    inbox = read_json(INBOX_JSON)
    integration = read_json(INTEGRATION_JSON)
    donor_count = len(inbox.get("candidates", []))
    build_ready = sum(1 for candidate in integration.get("candidates", []) if candidate.get("build_readiness") == "BUILD_READY")

    browser_milestone = max(browser.engine_milestones) if browser.engine_milestones else 0
    webview_milestone = max(webview.engine_milestones) if webview.engine_milestones else 0
    gap = browser_milestone - webview_milestone if browser_milestone and webview_milestone else 0

    rows = [
        GapRow(
            "baseline",
            "stock BrowserChrome version",
            "RECORDED",
            facts_summary(browser),
            browser.apk,
            "BrowserChrome is a Smartisan browser shell with Chromium payload signals around M90, targetSdk 28, 13 providers, and 35 exported components.",
            "Keep BrowserChrome behind v0.32 stock near-noop/live proof before any behavior or engine replacement.",
        ),
        GapRow(
            "baseline",
            "stock WebView version",
            "RECORDED",
            facts_summary(webview),
            webview.apk,
            "System WebView is much older at M75 even though it already targets Android 11 WebViewUpdater's targetSdk 30 gate.",
            "Prioritize WebView provider modernization before BrowserChrome engine replacement.",
        ),
        GapRow(
            "gap",
            "BrowserChrome versus WebView engine gap",
            "ACTIONABLE",
            f"BrowserChrome milestone={browser_milestone or 'unknown'}; WebView milestone={webview_milestone or 'unknown'}; delta={gap if gap else 'unknown'}",
            f"{browser.apk}; {webview.apk}",
            "The default browser is roughly 15 Chromium milestones newer than the system WebView. Updating WebView is the larger compatibility win and has a cleaner provider contract.",
            "Treat WebView Route A/B/C donor selection as the next real modernization track.",
        ),
        GapRow(
            "payload",
            "BrowserChrome payload shape",
            "RED",
            f"size={browser.size_bytes}; dex={browser.dex_count}; libs={browser.lib_count}; libs_by_abi={browser.libs_by_abi}; key_libs={browser.key_libs}; assets={browser.asset_count}",
            browser.apk,
            "BrowserChrome modernization cannot be a libchrome.so-only transplant; Java glue, resources, providers, OAT/VDEX, icon redirection, and app data have to move as a version-matched unit.",
            "After v0.32 live proof, build a candidate diff auditor before attempting a BrowserChrome behavior APK.",
        ),
        GapRow(
            "payload",
            "WebView payload shape",
            "ORANGE",
            f"size={webview.size_bytes}; dex={webview.dex_count}; libs={webview.lib_count}; libs_by_abi={webview.libs_by_abi}; key_libs={webview.key_libs}; assets={webview.asset_count}",
            webview.apk,
            "WebView is a narrower provider unit, but Java/native/assets/sandbox services must still remain version-matched. Split APK or Trichrome donors widen the ROM design.",
            "Use donor and Trichrome bundle audits before image design.",
        ),
        GapRow(
            "route",
            "preferred first modernization route",
            "ROUTE_A_FIRST",
            "Adapt or source-build a standalone com.android.webview provider into /product/app/webview after v0.31 live proof.",
            rel(INTEGRATION_JSON) if INTEGRATION_JSON.exists() else "integration plan missing",
            "This avoids framework-res provider whitelist edits and keeps the first real image product_b-only if the donor can satisfy the stock com.android.webview contract.",
            "Choose an actual donor and rerun inbox, donor, bundle, integration, and ROM-design plans.",
        ),
        GapRow(
            "route",
            "rejected shortcut routes",
            "BLOCKED",
            "BrowserChrome-as-WebView, lib-only swaps, direct com.google.android.webview without framework config, and Trichrome single-APK overwrite.",
            "docs/research/webview-donor-source-plan.md; docs/research/browser-webview-modernization-audit.md",
            "These routes violate WebViewUpdater provider rules, static-library/package-group requirements, or BrowserChrome same-package contracts.",
            "Keep route-specific gates instead of forcing a simpler-looking replacement.",
        ),
        GapRow(
            "gate",
            "v0.31 stock WebView provider near-noop",
            "PASS_OFFLINE" if pass_report(v031_offline, "PASS_OFFLINE_IMAGE") else "MISSING",
            rel(v031_offline),
            rel(v031_offline),
            "Offline product_b mtime-only WebView provider gate exists but is not live-verified.",
            "Resolve ADB/live-state or use explicit manual fastboot flow only with clear reduced verification.",
        ),
        GapRow(
            "gate",
            "v0.32 stock BrowserChrome near-noop",
            "PASS_OFFLINE" if pass_report(v032_offline, "PASS_OFFLINE_IMAGE") else "MISSING",
            rel(v032_offline),
            rel(v032_offline),
            "Offline system_b mtime-only BrowserChrome gate exists but is not live-verified.",
            "Do not build BrowserChrome behavior replacements until this gate boots and verifies through keyguard/launcher/resolver.",
        ),
        GapRow(
            "gate",
            "live-state and live no-op proof",
            "MISSING",
            f"live_state={rel(live_state)}; v0.31_device={rel(v031_device)}; v0.32_device={rel(v032_device)}",
            rel(live_state),
            "ADB currently blocks automated live-state capture and post-flash verification. This does not block offline analysis, but it blocks treating any provider/browser gate as proven on device.",
            "Treat ADB recovery as a separate live-device task before flashing modernization candidates.",
        ),
        GapRow(
            "donor",
            "modern donor inventory",
            "MISSING" if donor_count == 0 else "PRESENT",
            f"candidate_count={donor_count}; build_ready={build_ready}",
            rel(INBOX_JSON) if INBOX_JSON.exists() else "inbox report missing",
            "No actual modern donor material is currently in the project inbox, so the only build plan remains stock baseline/design-only.",
            "Put a donor APK/APKM/APKS/XAPK into apks/webview-donor-inbox or provide a source-built output directory, then rerun the donor pipeline.",
        ),
    ]
    return rows


def write_tsv(rows: list[GapRow]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    columns = ["track", "item", "status", "observed", "evidence", "implication", "next_gate"]
    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def markdown_table(rows: list[GapRow], track: str) -> str:
    subset = [row for row in rows if row.track == track]
    lines = [
        "| Item | Status | Observed | Implication | Next gate |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in subset:
        lines.append(
            "| "
            + " | ".join(
                value.replace("|", "\\|").replace("\n", " ")
                for value in [row.item, row.status, row.observed, row.implication, row.next_gate]
            )
            + " |"
        )
    return "\n".join(lines)


def write_json(browser: ApkFacts, webview: ApkFacts, rows: list[GapRow]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "browser": asdict(browser),
        "webview": asdict(webview),
        "rows": [asdict(row) for row in rows],
    }
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_markdown(browser: ApkFacts, webview: ApkFacts, rows: list[GapRow]) -> None:
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    browser_engine = ", ".join(browser.engine_versions) or "unknown"
    webview_engine = ", ".join(webview.engine_versions) or "unknown"
    content = f"""# Browser/WebView Version Gap Audit

Generated: {generated}

This is a read-only offline audit. It inspects stock APKs and existing
Smartisax gate reports. It does not download donors, build images, touch a
device, flash, reboot, erase partitions, write settings, or modify `/data`.

## Decision

The first real modernization target should be the system WebView provider, not
the full BrowserChrome app shell.

- BrowserChrome stock app version is `{browser.version_name}` and its Chromium
  payload exposes version signal(s) `{browser_engine}`. It has a large
  Smartisan/Chromium app-shell surface: `{browser.dex_count}` dex files,
  `{browser.lib_count}` native libraries, `{browser.provider_count}` providers,
  and `{browser.exported_count}` exported components.
- WebView stock version is `{webview.version_name}` with engine signal(s)
  `{webview_engine}`. It is much older but has a narrower Android WebView
  provider contract under `/product/app/webview`.
- Therefore, the next donor-backed work should prefer a standalone
  `com.android.webview` Route A/adapt-in-place candidate after v0.31 live proof.
  BrowserChrome engine replacement remains behind the v0.32 live no-op gate and
  a separate candidate-diff audit.

## Baseline

{markdown_table(rows, "baseline")}

## Version Gap

{markdown_table(rows, "gap")}

## Payload Shape

{markdown_table(rows, "payload")}

## Route Decisions

{markdown_table(rows, "route")}

## Current Gates

{markdown_table(rows, "gate")}

## Donor State

{markdown_table(rows, "donor")}

## Next Offline Step

Create or obtain actual WebView donor material, then run:

```bash
tools/r2-webview-donor-inbox-audit.py --include-downloads
tools/r2-webview-integration-plan.py
tools/r2-webview-rom-design-plan.py
```

Do not build a donor-backed image until the donor audit, Trichrome/static
library bundle audit, integration plan, and ROM design plan all agree on the
same route.

## Outputs

- Markdown report: `{rel(OUT_MD)}`
- TSV manifest: `{rel(OUT_TSV)}`
- JSON report: `{rel(OUT_JSON)}`
"""
    OUT_MD.write_text(content, encoding="utf-8")


def main() -> None:
    browser = apk_facts(
        "BrowserChrome",
        BROWSER_PACKAGE,
        BROWSER_SOURCE,
        BROWSER_APK,
        {"lib/arm64-v8a/libchrome.so", "assets/new_user_agent_config_default.json"},
    )
    webview = apk_facts(
        "WebView",
        WEBVIEW_PACKAGE,
        WEBVIEW_SOURCE,
        WEBVIEW_APK,
        {"lib/arm64-v8a/libwebviewchromium.so", "assets/webview_licenses.notice"},
    )
    rows = build_rows(browser, webview)
    write_tsv(rows)
    write_json(browser, webview, rows)
    write_markdown(browser, webview, rows)
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    print(f"browser_engine_versions={','.join(browser.engine_versions) or 'unknown'}")
    print(f"webview_engine_versions={','.join(webview.engine_versions) or 'unknown'}")


if __name__ == "__main__":
    main()
