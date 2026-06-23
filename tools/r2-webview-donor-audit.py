#!/usr/bin/env python3
"""Audit a WebView donor APK/APKM before any Smartisax ROM build.

This helper is read-only. It accepts a single APK, an APKM/APKS/XAPK/ZIP
containing split APKs, or a directory containing APKs. It does not download
donors, build images, touch devices, flash, reboot, erase partitions, write
settings, or modify /data.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
AAPT = ROOT / "third_party" / "android-build-tools" / "build-tools_r35.0.1_macosx" / "android-15" / "aapt"
WEBVIEW_CONFIG = (
    KB
    / "jadx"
    / "system__system__framework__framework-res.apk"
    / "resources"
    / "res"
    / "xml"
    / "config_webview_packages.xml"
)
STOCK_WEBVIEW_APK = KB / "raw" / "product" / "app" / "webview" / "webview.apk"
OUT_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-donor"

WEBVIEW_PACKAGE = "com.android.webview"
WEBVIEW_LIBRARY_META = "com.android.webview.WebViewLibrary"
WEBVIEW_FACTORY_PROVIDER_CLASS = "com.android.webview.chromium.WebViewChromiumFactoryProviderForR"
STOCK_WEBVIEW_APPLICATION_CLASS = "com.android.webview.chromium.WebViewApplication"
CHROMIUM_NONEMBEDDED_APPLICATION_CLASS = "org.chromium.android_webview.nonembedded.WebViewApkApplication"
TRICHROME_LIBRARY_PACKAGE = "com.google.android.trichromelibrary"
STOCK_WEBVIEW_VERSION_CODE = 377015630
MIN_TARGET_SDK = 30
DEVICE_API = 30


@dataclass(frozen=True)
class XmlNode:
    kind: str
    attrs: dict[str, str]
    indent: int


@dataclass(frozen=True)
class ApkReport:
    name: str
    path: str
    size: int
    sha256: str
    package: str
    split: str
    version_code: int | None
    version_name: str
    min_sdk: int | None
    target_sdk: int | None
    compile_sdk: int | None
    application_name: str
    application_attrs: dict[str, str]
    metadata: dict[str, str]
    uses_libraries: list[str]
    uses_static_libraries: list[str]
    component_counts: dict[str, int]
    sandbox_service_count: int
    sandbox_service_meta: int | None
    privileged_service_meta: int | None
    provider_authorities: list[str]
    dex_entries: list[str]
    factory_provider_class_present: bool
    application_class_present: bool
    libs_by_abi: dict[str, list[str]]
    asset_markers: list[str]
    zip_entry_count: int
    aapt_badging_ok: bool
    aapt_xmltree_ok: bool
    notes: list[str]


@dataclass(frozen=True)
class CheckRow:
    gate: str
    status: str
    observed: str
    requirement: str
    evidence: str


def die(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sh(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def sanitize_label(label: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-")
    return cleaned or "webview-donor"


def parse_int(value: str) -> int | None:
    if not value:
        return None
    value = value.strip()
    if value.startswith("0x"):
        try:
            return int(value, 16)
        except ValueError:
            return None
    if value.isdigit():
        return int(value)
    return None


def parse_aapt_value(line: str) -> str:
    raw = re.search(r'\(Raw: "([^"]*)"\)', line)
    if raw:
        return raw.group(1)
    quoted = re.search(r'="([^"]*)"', line)
    if quoted:
        return quoted.group(1)
    resource = re.search(r"=(@0x[0-9a-fA-F]+)", line)
    if resource:
        return resource.group(1)
    typed = re.search(r"=\(type 0x([0-9a-fA-F]+)\)(0x[0-9a-fA-F]+)", line)
    if typed:
        kind = typed.group(1).lower()
        raw_value = typed.group(2).lower()
        if kind == "12":
            return "true" if raw_value == "0xffffffff" else "false"
        parsed = parse_int(raw_value)
        return str(parsed) if parsed is not None else raw_value
    bare = line.split("=", 1)
    return bare[1].strip() if len(bare) == 2 else ""


def normalize_aapt_attr_name(name: str) -> str:
    android_prefix = "http://schemas.android.com/apk/res/android:"
    if name.startswith(android_prefix):
        return name[len(android_prefix) :]
    if name.startswith("android:"):
        return name.split(":", 1)[1]
    return name


def parse_xmltree(text: str) -> list[XmlNode]:
    nodes: list[XmlNode] = []
    stack: list[XmlNode] = []
    for line in text.splitlines():
        elem = re.match(r"(\s*)E: ([A-Za-z0-9_.:-]+)", line)
        if elem:
            indent = len(elem.group(1))
            while stack and stack[-1].indent >= indent:
                stack.pop()
            node = XmlNode(kind=elem.group(2), attrs={}, indent=indent)
            nodes.append(node)
            stack.append(node)
            continue
        attr = re.match(r"\s*A: ([^\s(=]+)(?:\([^)]*\))?=", line)
        if attr and stack:
            name = normalize_aapt_attr_name(attr.group(1))
            stack[-1].attrs[name] = parse_aapt_value(line)
    return nodes


def parse_badging(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    pkg = re.search(r"^package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'.*?(?:compileSdkVersion='([^']*)')?", text, re.M)
    if pkg:
        data["package"] = pkg.group(1)
        data["versionCode"] = pkg.group(2)
        data["versionName"] = pkg.group(3)
        data["compileSdkVersion"] = pkg.group(4) or ""
    for key, output_key in [
        ("sdkVersion", "minSdkVersion"),
        ("targetSdkVersion", "targetSdkVersion"),
    ]:
        found = re.search(rf"^{key}:'([^']*)'", text, re.M)
        if found:
            data[output_key] = found.group(1)
    native = re.search(r"^native-code:(.*)$", text, re.M)
    if native:
        data["nativeCode"] = native.group(1)
    alt_native = re.search(r"^alt-native-code:(.*)$", text, re.M)
    if alt_native:
        data["altNativeCode"] = alt_native.group(1)
    return data


def quote_list(value: str) -> list[str]:
    return re.findall(r"'([^']+)'", value)


def zip_inventory(path: Path) -> tuple[list[str], dict[str, list[str]], list[str], int]:
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        dex = sorted(name for name in names if re.fullmatch(r"classes(\d*)\.dex", name))
        libs: dict[str, list[str]] = {}
        for name in names:
            if not name.startswith("lib/") or not name.endswith(".so"):
                continue
            parts = name.split("/")
            if len(parts) >= 3:
                libs.setdefault(parts[1], []).append(parts[-1])
        markers = sorted(
            name
            for name in names
            if name.startswith("assets/")
            and any(token in name.lower() for token in ["webview", "license", "variations", "trichrome"])
        )
        return dex, {abi: sorted(set(values)) for abi, values in libs.items()}, markers[:24], len(names)


def zip_dex_contains(path: Path, needle: str) -> bool:
    needles = {
        needle.encode("utf-8"),
        needle.replace(".", "/").encode("utf-8"),
        needle.rsplit(".", 1)[-1].encode("utf-8"),
    }
    with zipfile.ZipFile(path) as zf:
        for name in zf.namelist():
            if re.fullmatch(r"classes(\d*)\.dex", name):
                with zf.open(name) as fh:
                    data = fh.read()
                    if any(wanted in data for wanted in needles):
                        return True
    return False


def library_ref(node: XmlNode) -> str:
    name = node.attrs.get("name", "")
    optional = node.attrs.get("required", "")
    version = node.attrs.get("version", "")
    cert = node.attrs.get("certDigest", "")
    parts = [name or "unknown"]
    if optional:
        parts.append(f"required={optional}")
    if version:
        parts.append(f"version={version}")
    if cert:
        parts.append(f"certDigest={cert[:16]}...")
    return " ".join(parts)


def provider_config() -> list[dict[str, str]]:
    root = ET.parse(WEBVIEW_CONFIG).getroot()
    providers = []
    for node in root.findall("webviewprovider"):
        providers.append(
            {
                "packageName": node.attrib.get("packageName", ""),
                "availableByDefault": node.attrib.get("availableByDefault", "false"),
                "isFallback": node.attrib.get("isFallback", "false"),
                "description": node.attrib.get("description", ""),
                "signatureCount": str(len(node.findall("signature"))),
            }
        )
    return providers


def extract_input(input_path: Path, work_dir: Path) -> list[Path]:
    input_path = input_path.resolve()
    if input_path.is_dir():
        apks = sorted(path for path in input_path.rglob("*.apk") if path.is_file())
        if not apks:
            die(f"no APK files found in {input_path}")
        return apks
    if input_path.suffix.lower() == ".apk":
        return [input_path]
    if input_path.suffix.lower() not in {".apkm", ".apks", ".xapk", ".zip"}:
        die(f"unsupported input suffix: {input_path}")
    extracted: list[Path] = []
    with zipfile.ZipFile(input_path) as zf:
        for name in sorted(zf.namelist()):
            if not name.lower().endswith(".apk"):
                continue
            safe_name = sanitize_label(Path(name).name)
            out = work_dir / safe_name
            with zf.open(name) as src, out.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            extracted.append(out)
    if not extracted:
        die(f"no APK entries found inside {input_path}")
    return extracted


def analyze_apk(path: Path) -> ApkReport:
    notes: list[str] = []
    badging = sh([str(AAPT), "dump", "badging", str(path)])
    badging_data: dict[str, str] = {}
    if badging.returncode == 0:
        badging_data = parse_badging(badging.stdout)
    else:
        notes.append("aapt dump badging failed: " + (badging.stderr or badging.stdout).strip().splitlines()[0])

    xmltree = sh([str(AAPT), "dump", "xmltree", str(path), "AndroidManifest.xml"])
    nodes: list[XmlNode] = []
    if xmltree.returncode == 0:
        nodes = parse_xmltree(xmltree.stdout)
    else:
        notes.append("aapt dump xmltree failed: " + (xmltree.stderr or xmltree.stdout).strip().splitlines()[0])

    manifest = next((node for node in nodes if node.kind == "manifest"), XmlNode("manifest", {}, 0))
    app = next((node for node in nodes if node.kind == "application"), XmlNode("application", {}, 0))
    metadata_nodes = [node for node in nodes if node.kind == "meta-data"]
    metadata = {
        node.attrs.get("name", ""): node.attrs.get("value", "") or node.attrs.get("resource", "")
        for node in metadata_nodes
        if node.attrs.get("name")
    }
    uses_libraries = sorted(library_ref(node) for node in nodes if node.kind == "uses-library")
    uses_static_libraries = sorted(library_ref(node) for node in nodes if node.kind == "uses-static-library")
    components = Counter(node.kind for node in nodes if node.kind in {"activity", "activity-alias", "provider", "receiver", "service"})
    provider_authorities = [
        f"{node.attrs.get('name', '')} -> {node.attrs.get('authorities', '')} exported={node.attrs.get('exported', 'implicit')}"
        for node in nodes
        if node.kind == "provider"
    ]
    sandbox_names = [
        node.attrs.get("name", "")
        for node in nodes
        if node.kind == "service" and "SandboxedProcessService" in node.attrs.get("name", "")
    ]

    dex, libs_by_abi, asset_markers, zip_entry_count = zip_inventory(path)
    version_code = parse_int(badging_data.get("versionCode", "") or manifest.attrs.get("versionCode", ""))
    min_sdk = parse_int(badging_data.get("minSdkVersion", ""))
    target_sdk = parse_int(badging_data.get("targetSdkVersion", ""))
    compile_sdk = parse_int(badging_data.get("compileSdkVersion", "") or manifest.attrs.get("compileSdkVersion", ""))

    return ApkReport(
        name=path.name,
        path=rel(path),
        size=path.stat().st_size,
        sha256=sha256(path),
        package=badging_data.get("package", "") or manifest.attrs.get("package", ""),
        split=manifest.attrs.get("split", ""),
        version_code=version_code,
        version_name=badging_data.get("versionName", "") or manifest.attrs.get("versionName", ""),
        min_sdk=min_sdk,
        target_sdk=target_sdk,
        compile_sdk=compile_sdk,
        application_name=app.attrs.get("name", ""),
        application_attrs=dict(app.attrs),
        metadata=metadata,
        uses_libraries=uses_libraries,
        uses_static_libraries=uses_static_libraries,
        component_counts=dict(sorted(components.items())),
        sandbox_service_count=len(set(sandbox_names)),
        sandbox_service_meta=parse_int(metadata.get("org.chromium.content.browser.NUM_SANDBOXED_SERVICES", "")),
        privileged_service_meta=parse_int(metadata.get("org.chromium.content.browser.NUM_PRIVILEGED_SERVICES", "")),
        provider_authorities=provider_authorities,
        dex_entries=dex,
        factory_provider_class_present=zip_dex_contains(path, WEBVIEW_FACTORY_PROVIDER_CLASS),
        application_class_present=bool(app.attrs.get("name", "")) and zip_dex_contains(path, app.attrs.get("name", "")),
        libs_by_abi=libs_by_abi,
        asset_markers=asset_markers,
        zip_entry_count=zip_entry_count,
        aapt_badging_ok=badging.returncode == 0,
        aapt_xmltree_ok=xmltree.returncode == 0,
        notes=notes,
    )


def select_base(apks: list[ApkReport]) -> ApkReport:
    webview_meta = [apk for apk in apks if WEBVIEW_LIBRARY_META in apk.metadata]
    if len(webview_meta) == 1:
        return webview_meta[0]
    webview_meta_no_split = [apk for apk in webview_meta if not apk.split]
    if webview_meta_no_split:
        return webview_meta_no_split[0]
    no_split = [apk for apk in apks if not apk.split]
    if len(no_split) == 1:
        return no_split[0]
    named_base = [apk for apk in apks if apk.name.lower() == "base.apk"]
    if named_base:
        return named_base[0]
    if no_split:
        return no_split[0]
    return apks[0]


def all_libs(apks: list[ApkReport]) -> dict[str, list[str]]:
    merged: dict[str, set[str]] = {}
    for apk in apks:
        for abi, libs in apk.libs_by_abi.items():
            merged.setdefault(abi, set()).update(libs)
    return {abi: sorted(values) for abi, values in sorted(merged.items())}


def package_names(apks: list[ApkReport]) -> list[str]:
    return sorted({apk.package for apk in apks if apk.package})


def static_library_refs(apks: list[ApkReport]) -> list[str]:
    return sorted({ref for apk in apks for ref in apk.uses_static_libraries})


def uses_trichrome(apks: list[ApkReport]) -> bool:
    packages = package_names(apks)
    refs = static_library_refs(apks)
    return TRICHROME_LIBRARY_PACKAGE in packages or any(TRICHROME_LIBRARY_PACKAGE in ref for ref in refs)


def adaptation_route(base: ApkReport, apks: list[ApkReport], allow_framework_config_patch: bool) -> tuple[str, list[str]]:
    requirements: list[str] = [
        "keep provider APK/splits version-matched",
        "bump package directory mtime to invalidate PackageCacher",
        "remove or regenerate stale product/app/webview oat/vdex when dex/native code changes",
        "verify relro creation and cmd webviewupdate after boot",
        "test Settings WebView selector and Smartisan Big Bang/WebView surfaces",
    ]
    if base.package == WEBVIEW_PACKAGE:
        route = "adapt-in-place: replace stock com.android.webview provider under /product/app/webview"
    elif allow_framework_config_patch:
        route = f"framework-provider-add: add {base.package} to framework-res config_webview_packages.xml and ship it as a ROM system/product app"
        requirements.append("patch framework-res config_webview_packages.xml and pass a framework resource no-op/live gate first")
    else:
        route = f"blocked-unless-config-patched-or-renamed: {base.package} is not whitelisted by stock framework-res"
        requirements.append("rerun with --allow-framework-config-patch only for explicit framework-provider exploration")
    if uses_trichrome(apks):
        route += " + Trichrome/static-library bundle"
        requirements.append("bundle and validate TrichromeLibrary/static shared-library package(s), versions, and cert digests")
    if len(package_names(apks)) > 1:
        requirements.append("build a multi-package ROM layout instead of treating every APK as split APKs for one package")
    return route, requirements


def add_check(rows: list[CheckRow], gate: str, status: str, observed: str, requirement: str, evidence: str) -> None:
    rows.append(CheckRow(gate=gate, status=status, observed=observed, requirement=requirement, evidence=evidence))


def evaluate(apks: list[ApkReport], allow_framework_config_patch: bool) -> tuple[list[CheckRow], str]:
    base = select_base(apks)
    providers = provider_config()
    provider_names = [row["packageName"] for row in providers]
    libs = all_libs(apks)
    flat_libs = sorted({lib for values in libs.values() for lib in values})
    packages = package_names(apks)
    rows: list[CheckRow] = []

    if len(packages) <= 1:
        status = "PASS"
        observed = ", ".join(packages) or "unknown"
    else:
        status = "WARN"
        observed = ", ".join(packages)
    add_check(
        rows,
        "bundle_package_shape",
        status,
        observed,
        "A simple product/app WebView candidate should be one package plus optional splits; multi-package bundles need a dedicated ROM layout.",
        "input package inventory",
    )

    if base.package in provider_names:
        status = "PASS"
        observed = base.package
    elif allow_framework_config_patch:
        status = "WARN"
        observed = f"{base.package} not in stock provider config; would require framework-res config patch"
    else:
        status = "FAIL"
        observed = f"{base.package} not in stock provider config {provider_names}"
    add_check(
        rows,
        "framework_provider_whitelist",
        status,
        observed,
        "Stock Smartisan framework-res lists only allowed WebView provider packages.",
        rel(WEBVIEW_CONFIG),
    )

    add_check(
        rows,
        "package_identity",
        "PASS" if base.package == WEBVIEW_PACKAGE else "WARN",
        base.package or "unknown",
        f"Adapt-in-place candidate should use {WEBVIEW_PACKAGE}; other packages require framework config and selector policy.",
        base.path,
    )

    if base.min_sdk is None:
        status = "FAIL"
        observed = "unknown"
    elif base.min_sdk <= DEVICE_API:
        status = "PASS"
        observed = str(base.min_sdk)
    else:
        status = "FAIL"
        observed = f"{base.min_sdk} > device API {DEVICE_API}"
    add_check(rows, "min_sdk_device_compat", status, observed, "minSdkVersion must be <= Android 11 API 30.", base.path)

    if base.target_sdk is None:
        status = "FAIL"
        observed = "unknown"
    elif base.target_sdk >= MIN_TARGET_SDK:
        status = "PASS"
        observed = str(base.target_sdk)
    else:
        status = "FAIL"
        observed = f"{base.target_sdk} < {MIN_TARGET_SDK}"
    add_check(rows, "target_sdk_webviewupdater", status, observed, "UserPackage.hasCorrectTargetSdkVersion requires targetSdkVersion >= 30.", base.path)

    stock_cohort = STOCK_WEBVIEW_VERSION_CODE // 100000
    if base.version_code is None:
        status = "FAIL"
        observed = "unknown"
    elif base.version_code // 100000 >= stock_cohort:
        status = "PASS"
        observed = f"{base.version_code} cohort={base.version_code // 100000}"
    else:
        status = "FAIL"
        observed = f"{base.version_code} cohort={base.version_code // 100000} < stock cohort={stock_cohort}"
    add_check(
        rows,
        "version_code_cohort",
        status,
        observed,
        "WebViewUpdater compares versionCode / 100000 against the factory provider minimum.",
        "services.jar WebViewUpdater.versionCodeGE",
    )

    library = base.metadata.get(WEBVIEW_LIBRARY_META, "")
    if library:
        status = "PASS"
        observed = f"{WEBVIEW_LIBRARY_META}={library}"
    else:
        similar = {key: value for key, value in base.metadata.items() if "webview" in key.lower() and "library" in key.lower()}
        status = "FAIL"
        observed = json.dumps(similar, ensure_ascii=True) if similar else "missing"
    add_check(
        rows,
        "webview_library_metadata",
        status,
        observed,
        f"Manifest must expose {WEBVIEW_LIBRARY_META}; WebViewFactory.getWebViewLibrary must not return null.",
        base.path,
    )

    if library and library in flat_libs:
        status = "PASS"
        observed = f"{library} present"
    elif library:
        status = "FAIL"
        observed = f"{library} not found in APK/split native libraries"
    else:
        status = "FAIL"
        observed = "library metadata missing"
    add_check(rows, "webview_native_library_present", status, observed, "The manifest WebView library must exist in base or split native libs.", "APK ZIP inventory")

    factory_present = any(apk.factory_provider_class_present for apk in apks)
    if factory_present:
        status = "PASS"
        observed = WEBVIEW_FACTORY_PROVIDER_CLASS
    else:
        status = "FAIL"
        observed = "missing from dex entries"
    add_check(
        rows,
        "android11_factory_provider_class",
        status,
        observed,
        "R2 Android 11 WebViewFactory loads com.android.webview.chromium.WebViewChromiumFactoryProviderForR.",
        "framework.jar android.webkit.WebViewFactory",
    )

    if "arm64-v8a" in libs and libs["arm64-v8a"]:
        status = "PASS"
        observed = ", ".join(libs["arm64-v8a"])
    else:
        status = "FAIL"
        observed = "no arm64-v8a native libs"
    add_check(rows, "arm64_runtime", status, observed, "R2/kona needs arm64 WebView native code.", "APK ZIP inventory")

    if "armeabi-v7a" in libs and libs["armeabi-v7a"]:
        status = "PASS"
        observed = ", ".join(libs["armeabi-v7a"])
    else:
        status = "WARN"
        observed = "no armeabi-v7a native libs"
    add_check(rows, "arm32_app_compat", status, observed, "Stock WebView carries armeabi-v7a; missing 32-bit libs may affect 32-bit apps if enabled.", "APK ZIP inventory")

    declared = base.sandbox_service_meta
    actual = sum(apk.sandbox_service_count for apk in apks)
    if declared is None:
        status = "WARN"
        observed = f"metadata missing; service declarations={actual}"
    elif actual >= declared:
        status = "PASS"
        observed = f"metadata={declared}; declarations={actual}"
    else:
        status = "FAIL"
        observed = f"metadata={declared}; declarations={actual}"
    add_check(rows, "sandbox_service_contract", status, observed, "NUM_SANDBOXED_SERVICES should be backed by matching SandboxedProcessService declarations.", "AndroidManifest.xml")

    if not base.application_name:
        status = "FAIL"
        observed = "missing"
    elif not base.application_class_present:
        status = "FAIL"
        observed = f"{base.application_name} declared but not found in dex"
    elif base.application_name == CHROMIUM_NONEMBEDDED_APPLICATION_CLASS:
        status = "PASS"
        observed = f"{base.application_name} (Chromium standalone nonembedded WebView glue)"
    elif base.application_name == STOCK_WEBVIEW_APPLICATION_CLASS or "WebViewApplication" in base.application_name:
        status = "PASS"
        observed = f"{base.application_name} (legacy WebView application glue)"
    else:
        status = "WARN"
        observed = f"{base.application_name} (class present, not a known WebView application glue)"
    add_check(
        rows,
        "application_class",
        status,
        observed,
        "Manifest Application class must be present in dex and match a known Chromium WebView APK process glue; Android 11 provider loading itself is gated by the factory provider class.",
        base.path,
    )

    split_count = len(apks) - 1
    if split_count == 0:
        status = "PASS"
        observed = "single APK"
    else:
        status = "WARN"
        observed = f"{split_count} split APK(s): " + ", ".join(apk.name for apk in apks if apk is not base)
    add_check(rows, "split_installation_plan", status, observed, "Split donors are acceptable only after the ROM builder preserves base/split layout and codePath mtimes.", "input package inventory")

    if any(apk.notes for apk in apks):
        observed = "; ".join(note for apk in apks for note in apk.notes)
        add_check(rows, "parser_completeness", "WARN", observed, "All APKs should be readable by local aapt before a donor is promoted.", "aapt output")
    else:
        add_check(
            rows,
            "parser_completeness",
            "PASS",
            "aapt badging/xmltree OK for all APKs",
            "All APKs should be readable by local aapt before a donor is promoted.",
            "aapt output",
        )

    static_refs = static_library_refs(apks)
    if static_refs:
        status = "WARN"
        observed = "; ".join(static_refs)
    else:
        status = "PASS"
        observed = "none"
    add_check(
        rows,
        "static_library_dependencies",
        status,
        observed,
        "Trichrome/static shared-library donors require bundling and validating the provider plus its library package(s).",
        "AndroidManifest.xml uses-static-library",
    )

    route, requirements = adaptation_route(base, apks, allow_framework_config_patch)
    add_check(
        rows,
        "recommended_adaptation_route",
        "INFO",
        route,
        "; ".join(requirements),
        "Smartisax WebView backport route model",
    )

    if any(row.status == "FAIL" for row in rows):
        verdict = "FAIL"
    elif any(row.status == "WARN" for row in rows):
        verdict = "WARN"
    else:
        verdict = "PASS"
    return rows, verdict


def write_tsv(path: Path, rows: list[CheckRow]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            delimiter="\t",
            fieldnames=["gate", "status", "observed", "requirement", "evidence"],
            lineterminator="\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def write_markdown(
    path: Path,
    label: str,
    input_path: Path,
    apks: list[ApkReport],
    checks: list[CheckRow],
    verdict: str,
    allow_framework_config_patch: bool,
) -> None:
    base = select_base(apks)
    providers = provider_config()
    libs = all_libs(apks)
    lines: list[str] = []
    lines.append(f"# WebView Donor Audit: {label}")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline audit. It does not download donors, build")
    lines.append("images, touch a device, flash, reboot, erase partitions, write settings,")
    lines.append("or modify `/data`.")
    lines.append("")
    lines.append(f"Verdict: **{verdict}**")
    lines.append("")
    if verdict == "PASS":
        lines.append("The donor satisfies the first-pass static WebView provider gates. It still")
        lines.append("requires a stock no-op/near-no-op ROM gate and live `webviewupdate` testing")
        lines.append("before integration.")
    elif verdict == "WARN":
        lines.append("The donor has no hard static blocker in this audit, but it has warnings")
        lines.append("that must be resolved or explicitly accepted before any ROM image work.")
    else:
        lines.append("The donor has at least one hard static blocker. Do not build a ROM image")
        lines.append("from this donor until the failed gates are addressed.")
    lines.append("")
    lines.append("## Input")
    lines.append("")
    lines.append(f"- input: `{rel(input_path)}`")
    lines.append(f"- label: `{label}`")
    lines.append(f"- allow framework config patch: `{str(allow_framework_config_patch).lower()}`")
    lines.append(f"- base APK: `{base.name}`")
    lines.append(f"- split APK count: `{max(0, len(apks) - 1)}`")
    lines.append("")
    lines.append("## Stock Framework Provider Config")
    lines.append("")
    lines.append("| packageName | availableByDefault | isFallback | signatures | description |")
    lines.append("| --- | --- | --- | --- | --- |")
    for row in providers:
        lines.append(
            f"| {row['packageName']} | {row['availableByDefault']} | {row['isFallback']} | {row['signatureCount']} | {row['description']} |"
        )
    lines.append("")
    lines.append("## Base APK")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("| --- | --- |")
    lines.append(f"| package | `{base.package}` |")
    lines.append(f"| split | `{base.split or 'base'}` |")
    lines.append(f"| versionName | `{base.version_name}` |")
    lines.append(f"| versionCode | `{base.version_code}` |")
    lines.append(f"| minSdkVersion | `{base.min_sdk}` |")
    lines.append(f"| targetSdkVersion | `{base.target_sdk}` |")
    lines.append(f"| compileSdkVersion | `{base.compile_sdk}` |")
    lines.append(f"| application | `{base.application_name}` |")
    lines.append(f"| application class present | `{base.application_class_present}` |")
    lines.append(f"| WebViewLibrary | `{base.metadata.get(WEBVIEW_LIBRARY_META, '')}` |")
    lines.append(f"| Android 11 factory class present | `{any(apk.factory_provider_class_present for apk in apks)}` |")
    lines.append(f"| NUM_SANDBOXED_SERVICES | `{base.sandbox_service_meta}` |")
    lines.append(f"| declared sandbox services | `{sum(apk.sandbox_service_count for apk in apks)}` |")
    lines.append(f"| uses-library | `{'; '.join(base.uses_libraries) or 'none'}` |")
    lines.append(f"| uses-static-library | `{'; '.join(static_library_refs(apks)) or 'none'}` |")
    lines.append(f"| package names in input | `{', '.join(package_names(apks)) or 'unknown'}` |")
    lines.append("")
    route, requirements = adaptation_route(base, apks, allow_framework_config_patch)
    lines.append("## Adaptation Route")
    lines.append("")
    lines.append(f"- route: `{route}`")
    for requirement in requirements:
        lines.append(f"- requirement: {requirement}")
    lines.append("")
    lines.append("## Native/Dex/Split Inventory")
    lines.append("")
    lines.append("| Item | Value |")
    lines.append("| --- | --- |")
    abi_summary = "; ".join(f"{abi}: {', '.join(values)}" for abi, values in libs.items())
    lines.append(f"| ABI libraries | `{abi_summary}` |")
    lines.append(f"| base dex entries | `{', '.join(base.dex_entries) or 'none'}` |")
    lines.append(f"| asset markers | `{', '.join(base.asset_markers) or 'none'}` |")
    lines.append("")
    lines.append("## Gate Results")
    lines.append("")
    lines.append("| Gate | Status | Observed | Requirement | Evidence |")
    lines.append("| --- | --- | --- | --- | --- |")
    for row in checks:
        lines.append(
            "| "
            + " | ".join(
                cell.replace("|", "\\|").replace("\n", " ")
                for cell in [row.gate, row.status, row.observed, row.requirement, row.evidence]
            )
            + " |"
        )
    lines.append("")
    lines.append("## APK Files")
    lines.append("")
    lines.append("| APK | split | package | versionCode | sha256 | zip entries | factory class | components |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for apk in apks:
        components = ", ".join(f"{key}={value}" for key, value in sorted(apk.component_counts.items()))
        lines.append(
            f"| {apk.name} | {apk.split or 'base'} | {apk.package} | {apk.version_code} | {apk.sha256} | {apk.zip_entry_count} | {apk.factory_provider_class_present} | {components} |"
        )
    lines.append("")
    lines.append("## Next Gate")
    lines.append("")
    lines.append("A donor that reaches PASS/WARN here is still not flash-ready. The next safe")
    lines.append("work remains: stock WebView no-op or near-no-op gate, live `cmd")
    lines.append("webviewupdate` capture, product package mtime handling, and only then a")
    lines.append("donor-backed ROM candidate.")
    lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "input",
        nargs="?",
        type=Path,
        default=STOCK_WEBVIEW_APK,
        help="APK, APKM/APKS/XAPK/ZIP, or directory of APKs. Defaults to stock WebView APK.",
    )
    parser.add_argument("--label", help="Output label under hard-rom/inspect/browser-webview-donor.")
    parser.add_argument(
        "--allow-framework-config-patch",
        action="store_true",
        help="Downgrade provider-whitelist package mismatch from FAIL to WARN for explicit config-patch exploration.",
    )
    args = parser.parse_args()

    if not AAPT.exists():
        die(f"missing aapt at {AAPT}")
    if not WEBVIEW_CONFIG.exists():
        die(f"missing WebView provider config at {WEBVIEW_CONFIG}")
    if not args.input.exists():
        die(f"input not found: {args.input}")

    label = sanitize_label(args.label or args.input.stem)
    out_dir = OUT_ROOT / label
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="r2-webview-donor-") as tmp:
        apk_paths = extract_input(args.input, Path(tmp))
        reports = [analyze_apk(path) for path in apk_paths]

    checks, verdict = evaluate(reports, args.allow_framework_config_patch)

    tsv_path = out_dir / "webview-donor-audit.tsv"
    md_path = out_dir / "webview-donor-audit.md"
    json_path = out_dir / "webview-donor-audit.json"
    write_tsv(tsv_path, checks)
    write_markdown(md_path, label, args.input.resolve(), reports, checks, verdict, args.allow_framework_config_patch)
    json_path.write_text(
        json.dumps(
            {
                "label": label,
                "input": rel(args.input.resolve()),
                "verdict": verdict,
                "allow_framework_config_patch": args.allow_framework_config_patch,
                "base_apk": select_base(reports).name,
                "adaptation_route": adaptation_route(select_base(reports), reports, args.allow_framework_config_patch)[0],
                "adaptation_requirements": adaptation_route(select_base(reports), reports, args.allow_framework_config_patch)[1],
                "apks": [asdict(report) for report in reports],
                "checks": [asdict(row) for row in checks],
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"verdict={verdict}")
    print(f"markdown={rel(md_path)}")
    print(f"tsv={rel(tsv_path)}")
    print(f"json={rel(json_path)}")
    return 0 if verdict in {"PASS", "WARN", "FAIL"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
