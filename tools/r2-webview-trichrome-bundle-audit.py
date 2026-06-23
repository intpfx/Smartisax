#!/usr/bin/env python3
"""Audit a WebView Trichrome/static-library donor bundle.

This helper is read-only. It accepts an APK, APKM/APKS/XAPK/ZIP archive, or a
directory of APKs. It does not download donors, build images, touch devices,
flash, reboot, erase partitions, write settings, or modify /data.
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
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
AAPT = ROOT / "third_party" / "android-build-tools" / "build-tools_r35.0.1_macosx" / "android-15" / "aapt"
APKSIGNER = ROOT / "third_party" / "android-build-tools" / "build-tools_r35.0.1_macosx" / "android-15" / "apksigner"
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
OUT_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-trichrome-bundle"

WEBVIEW_PROVIDER_PACKAGES = {
    "com.android.webview",
    "com.google.android.webview",
    "com.google.android.webview.beta",
    "com.google.android.webview.dev",
    "com.google.android.webview.canary",
}
STOCK_WEBVIEW_PACKAGE = "com.android.webview"
GOOGLE_WEBVIEW_PACKAGE = "com.google.android.webview"
WEBVIEW_LIBRARY_META = "com.android.webview.WebViewLibrary"
WEBVIEW_FACTORY_PROVIDER_CLASS = "com.android.webview.chromium.WebViewChromiumFactoryProviderForR"
TRICHROME_LIBRARY_PACKAGE = "com.google.android.trichromelibrary"
MIN_TARGET_SDK = 30
DEVICE_API = 30


@dataclass(frozen=True)
class XmlNode:
    kind: str
    attrs: dict[str, str]
    indent: int


@dataclass(frozen=True)
class StaticRef:
    owner_apk: str
    owner_package: str
    name: str
    version: int | None
    required: str
    cert_digest: str


@dataclass(frozen=True)
class StaticProvide:
    owner_apk: str
    owner_package: str
    name: str
    version: int | None


@dataclass(frozen=True)
class ApkInfo:
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
    metadata: dict[str, str]
    uses_static_libraries: list[StaticRef]
    static_libraries: list[StaticProvide]
    dex_entries: list[str]
    factory_provider_class_present: bool
    libs_by_abi: dict[str, list[str]]
    zip_entry_count: int
    signer_sha256_digests: list[str]
    signer_notes: list[str]
    parser_notes: list[str]


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


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sanitize_label(label: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-")
    return cleaned or "webview-trichrome-bundle"


def parse_int(value: str) -> int | None:
    value = (value or "").strip()
    if not value:
        return None
    if value.startswith("0x"):
        try:
            return int(value, 16)
        except ValueError:
            return None
    if value.isdigit():
        return int(value)
    return None


def normalize_digest(value: str) -> str:
    return re.sub(r"[^0-9a-fA-F]", "", value or "").lower()


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
    pkg = re.search(
        r"^package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'.*?(?:compileSdkVersion='([^']*)')?",
        text,
        re.M,
    )
    if pkg:
        data["package"] = pkg.group(1)
        data["versionCode"] = pkg.group(2)
        data["versionName"] = pkg.group(3)
        data["compileSdkVersion"] = pkg.group(4) or ""
    for key, output_key in [("sdkVersion", "minSdkVersion"), ("targetSdkVersion", "targetSdkVersion")]:
        found = re.search(rf"^{key}:'([^']*)'", text, re.M)
        if found:
            data[output_key] = found.group(1)
    return data


def zip_inventory(path: Path) -> tuple[list[str], dict[str, list[str]], int]:
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
        return dex, {abi: sorted(set(values)) for abi, values in libs.items()}, len(names)


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


def signer_digests(path: Path) -> tuple[list[str], list[str]]:
    if not APKSIGNER.exists():
        return [], [f"missing apksigner at {rel(APKSIGNER)}"]
    result = sh([str(APKSIGNER), "verify", "--print-certs", str(path)])
    output = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode != 0:
        first = next((line.strip() for line in output.splitlines() if line.strip()), "apksigner failed")
        return [], [first]
    digests = []
    for match in re.findall(r"SHA-256 digest:\s*([0-9A-Fa-f: ]+)", output):
        normalized = normalize_digest(match)
        if normalized:
            digests.append(normalized)
    return sorted(set(digests)), []


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
            out = work_dir / sanitize_label(Path(name).name)
            with zf.open(name) as src, out.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            extracted.append(out)
    if not extracted:
        die(f"no APK entries found inside {input_path}")
    return extracted


def parse_static_ref(node: XmlNode, apk_name: str, package: str) -> StaticRef:
    return StaticRef(
        owner_apk=apk_name,
        owner_package=package,
        name=node.attrs.get("name", ""),
        version=parse_int(node.attrs.get("version", "")),
        required=node.attrs.get("required", ""),
        cert_digest=normalize_digest(node.attrs.get("certDigest", "")),
    )


def parse_static_provide(node: XmlNode, apk_name: str, package: str) -> StaticProvide:
    return StaticProvide(
        owner_apk=apk_name,
        owner_package=package,
        name=node.attrs.get("name", ""),
        version=parse_int(node.attrs.get("version", "")),
    )


def analyze_apk(path: Path) -> ApkInfo:
    notes: list[str] = []
    badging = sh([str(AAPT), "dump", "badging", str(path)])
    badging_data: dict[str, str] = {}
    if badging.returncode == 0:
        badging_data = parse_badging(badging.stdout)
    else:
        notes.append("aapt dump badging failed: " + ((badging.stderr or badging.stdout).strip().splitlines() or [""])[0])

    xmltree = sh([str(AAPT), "dump", "xmltree", str(path), "AndroidManifest.xml"])
    nodes: list[XmlNode] = []
    if xmltree.returncode == 0:
        nodes = parse_xmltree(xmltree.stdout)
    else:
        notes.append("aapt dump xmltree failed: " + ((xmltree.stderr or xmltree.stdout).strip().splitlines() or [""])[0])

    manifest = next((node for node in nodes if node.kind == "manifest"), XmlNode("manifest", {}, 0))
    metadata = {
        node.attrs.get("name", ""): node.attrs.get("value", "") or node.attrs.get("resource", "")
        for node in nodes
        if node.kind == "meta-data" and node.attrs.get("name")
    }
    package = badging_data.get("package", "") or manifest.attrs.get("package", "")
    dex, libs_by_abi, zip_entry_count = zip_inventory(path)
    signers, signer_notes = signer_digests(path)
    apk_name = path.name
    return ApkInfo(
        name=apk_name,
        path=rel(path),
        size=path.stat().st_size,
        sha256=sha256(path),
        package=package,
        split=manifest.attrs.get("split", ""),
        version_code=parse_int(badging_data.get("versionCode", "") or manifest.attrs.get("versionCode", "")),
        version_name=badging_data.get("versionName", "") or manifest.attrs.get("versionName", ""),
        min_sdk=parse_int(badging_data.get("minSdkVersion", "")),
        target_sdk=parse_int(badging_data.get("targetSdkVersion", "")),
        compile_sdk=parse_int(badging_data.get("compileSdkVersion", "") or manifest.attrs.get("compileSdkVersion", "")),
        metadata=metadata,
        uses_static_libraries=[
            parse_static_ref(node, apk_name, package) for node in nodes if node.kind == "uses-static-library"
        ],
        static_libraries=[parse_static_provide(node, apk_name, package) for node in nodes if node.kind == "static-library"],
        dex_entries=dex,
        factory_provider_class_present=zip_dex_contains(path, WEBVIEW_FACTORY_PROVIDER_CLASS),
        libs_by_abi=libs_by_abi,
        zip_entry_count=zip_entry_count,
        signer_sha256_digests=signers,
        signer_notes=signer_notes,
        parser_notes=notes,
    )


def all_libs(apks: list[ApkInfo]) -> dict[str, list[str]]:
    merged: dict[str, set[str]] = defaultdict(set)
    for apk in apks:
        for abi, libs in apk.libs_by_abi.items():
            merged[abi].update(libs)
    return {abi: sorted(values) for abi, values in sorted(merged.items())}


def package_names(apks: list[ApkInfo]) -> list[str]:
    return sorted({apk.package for apk in apks if apk.package})


def static_refs(apks: list[ApkInfo]) -> list[StaticRef]:
    return [ref for apk in apks for ref in apk.uses_static_libraries]


def static_provides(apks: list[ApkInfo]) -> list[StaticProvide]:
    return [provided for apk in apks for provided in apk.static_libraries]


def provider_candidates(apks: list[ApkInfo]) -> list[ApkInfo]:
    candidates = []
    for apk in apks:
        has_webview_lib = WEBVIEW_LIBRARY_META in apk.metadata
        looks_provider = apk.package in WEBVIEW_PROVIDER_PACKAGES or has_webview_lib or apk.factory_provider_class_present
        if looks_provider and not apk.split:
            candidates.append(apk)
    if candidates:
        return sorted(candidates, key=lambda apk: (apk.package not in WEBVIEW_PROVIDER_PACKAGES, apk.name))
    split_only = [apk for apk in apks if apk.package in WEBVIEW_PROVIDER_PACKAGES or WEBVIEW_LIBRARY_META in apk.metadata]
    return sorted(split_only, key=lambda apk: apk.name)


def trichrome_library_apks(apks: list[ApkInfo]) -> list[ApkInfo]:
    result = []
    for apk in apks:
        provided_names = {provided.name for provided in apk.static_libraries}
        if apk.package == TRICHROME_LIBRARY_PACKAGE or TRICHROME_LIBRARY_PACKAGE in provided_names:
            result.append(apk)
    return sorted(result, key=lambda apk: apk.name)


def classify(apks: list[ApkInfo], providers: list[ApkInfo]) -> str:
    refs = static_refs(apks)
    packages = package_names(apks)
    if not providers:
        return "not-webview-bundle"
    if any(TRICHROME_LIBRARY_PACKAGE in {ref.name, ref.owner_package} for ref in refs) or trichrome_library_apks(apks):
        return "trichrome-static-library-bundle"
    if len(packages) > 1:
        return "multi-package-webview-bundle"
    return "standalone-webview"


def add_check(rows: list[CheckRow], gate: str, status: str, observed: str, requirement: str, evidence: str) -> None:
    rows.append(CheckRow(gate=gate, status=status, observed=observed, requirement=requirement, evidence=evidence))


def library_filename(apk: ApkInfo) -> str:
    return apk.metadata.get(WEBVIEW_LIBRARY_META, "")


def find_library_apk_for_ref(ref: StaticRef, apks: list[ApkInfo]) -> ApkInfo | None:
    for apk in apks:
        if apk.package == ref.name:
            return apk
        if any(provided.name == ref.name for provided in apk.static_libraries):
            return apk
    return None


def provided_version_for_ref(ref: StaticRef, apk: ApkInfo | None) -> int | None:
    if apk is None:
        return None
    for provided in apk.static_libraries:
        if provided.name == ref.name:
            return provided.version
    return apk.version_code


def static_ref_summary(refs: list[StaticRef]) -> str:
    if not refs:
        return "none"
    values = []
    for ref in refs:
        parts = [ref.name or "unknown"]
        if ref.version is not None:
            parts.append(f"version={ref.version}")
        if ref.required:
            parts.append(f"required={ref.required}")
        if ref.cert_digest:
            parts.append(f"certDigest={ref.cert_digest[:16]}...")
        parts.append(f"owner={ref.owner_package or ref.owner_apk}")
        values.append(" ".join(parts))
    return "; ".join(values)


def rom_route(provider: ApkInfo | None, classification: str, allow_framework_config_patch: bool) -> tuple[str, list[str]]:
    if provider is None:
        return "blocked: no WebView provider candidate", ["provide exactly one WebView provider candidate"]
    requirements = [
        "keep provider, static-library package, splits, Java, native libs, and resources version-matched",
        "bump every changed package directory mtime to invalidate PackageCacher",
        "remove or regenerate stale oat/vdex when dex/native code changes",
        "verify relro creation, cmd webviewupdate, Settings selector, and Smartisan Big Bang/WebView surfaces after boot",
    ]
    if provider.package == STOCK_WEBVIEW_PACKAGE:
        route = "adapt-in-place under /product/app/webview"
    elif allow_framework_config_patch:
        route = f"framework-provider-add for {provider.package}"
        requirements.append("patch framework-res config_webview_packages.xml and pass a framework resource gate")
    else:
        route = f"blocked-unless-framework-config-or-package-adaptation for {provider.package}"
        requirements.append("rerun with --allow-framework-config-patch only for explicit framework/provider design")
    if classification == "trichrome-static-library-bundle":
        route += " + multi-package Trichrome/static-library ROM layout"
        requirements.append("ship TrichromeLibrary/static shared-library package(s) beside the provider and verify static library resolution")
    elif classification == "multi-package-webview-bundle":
        route += " + multi-package bundle layout"
    return route, requirements


def evaluate(apks: list[ApkInfo], allow_framework_config_patch: bool) -> tuple[list[CheckRow], str, str]:
    rows: list[CheckRow] = []
    providers = provider_candidates(apks)
    provider = providers[0] if len(providers) == 1 else None
    packages = package_names(apks)
    refs = static_refs(apks)
    provides = static_provides(apks)
    libs = all_libs(apks)
    classification = classify(apks, providers)

    add_check(
        rows,
        "input_package_inventory",
        "PASS" if packages else "FAIL",
        ", ".join(packages) or "none",
        "Bundle audit needs readable APK package identities.",
        "aapt dump badging/xmltree",
    )

    if len(providers) == 1:
        provider_status = "PASS"
        provider_observed = f"{providers[0].package} ({providers[0].name})"
    elif not providers:
        provider_status = "FAIL"
        provider_observed = "none"
    else:
        provider_status = "FAIL"
        provider_observed = ", ".join(f"{apk.package}:{apk.name}" for apk in providers)
    add_check(
        rows,
        "webview_provider_candidate_count",
        provider_status,
        provider_observed,
        "A donor bundle must contain exactly one base WebView provider candidate.",
        "package name, WebViewLibrary metadata, and factory provider class scan",
    )

    add_check(
        rows,
        "bundle_classification",
        "PASS" if classification in {"standalone-webview", "trichrome-static-library-bundle"} else "WARN",
        classification,
        "Classify the donor as standalone WebView, Trichrome/static-library, or blocked/non-WebView before ROM design.",
        "package inventory and uses-static-library graph",
    )

    grouped: dict[str, list[ApkInfo]] = defaultdict(list)
    for apk in apks:
        grouped[apk.package].append(apk)
    split_errors = []
    for package, group in sorted(grouped.items()):
        bases = [apk for apk in group if not apk.split]
        if len(bases) != 1:
            split_errors.append(f"{package}: base_count={len(bases)}")
    add_check(
        rows,
        "split_base_layout",
        "PASS" if not split_errors else "FAIL",
        "; ".join(split_errors) if split_errors else "one base APK per package",
        "Every package in a bundle needs exactly one base APK plus optional splits.",
        "AndroidManifest.xml split attributes",
    )

    if provider is not None:
        if provider.package == STOCK_WEBVIEW_PACKAGE:
            status = "PASS"
            observed = provider.package
        elif allow_framework_config_patch:
            status = "WARN"
            observed = f"{provider.package}; framework provider config patch required"
        else:
            status = "FAIL"
            observed = f"{provider.package}; stock config only whitelists {STOCK_WEBVIEW_PACKAGE}"
        add_check(
            rows,
            "framework_provider_route",
            status,
            observed,
            "Smartisan stock framework-res exposes only com.android.webview unless config_webview_packages.xml is patched.",
            rel(WEBVIEW_CONFIG),
        )

        min_ok = provider.min_sdk is not None and provider.min_sdk <= DEVICE_API
        target_ok = provider.target_sdk is not None and provider.target_sdk >= MIN_TARGET_SDK
        add_check(
            rows,
            "provider_min_sdk",
            "PASS" if min_ok else "FAIL",
            str(provider.min_sdk) if provider.min_sdk is not None else "unknown",
            "Provider minSdkVersion must be <= Android 11 API 30.",
            provider.path,
        )
        add_check(
            rows,
            "provider_target_sdk",
            "PASS" if target_ok else "FAIL",
            str(provider.target_sdk) if provider.target_sdk is not None else "unknown",
            "Android 11 WebViewUpdater requires targetSdkVersion >= 30.",
            provider.path,
        )

        webview_lib = library_filename(provider)
        flat_libs = sorted({lib for values in libs.values() for lib in values})
        if webview_lib and webview_lib in flat_libs:
            lib_status = "PASS"
            lib_observed = f"{webview_lib} present"
        elif webview_lib:
            lib_status = "FAIL"
            lib_observed = f"{webview_lib} missing from bundle native libs"
        else:
            lib_status = "FAIL"
            lib_observed = "WebViewLibrary metadata missing"
        add_check(
            rows,
            "provider_webview_library",
            lib_status,
            lib_observed,
            "Provider manifest must expose com.android.webview.WebViewLibrary and the named native lib must exist in the bundle.",
            "AndroidManifest.xml and ZIP lib inventory",
        )

        factory_present = any(apk.factory_provider_class_present for apk in apks)
        add_check(
            rows,
            "android11_factory_provider_class",
            "PASS" if factory_present else "FAIL",
            WEBVIEW_FACTORY_PROVIDER_CLASS if factory_present else "missing",
            "R2 Android 11 WebViewFactory loads WebViewChromiumFactoryProviderForR.",
            "bundle dex scan",
        )

    add_check(
        rows,
        "arm64_runtime_libs",
        "PASS" if libs.get("arm64-v8a") else "FAIL",
        ", ".join(libs.get("arm64-v8a", [])) or "missing",
        "R2/kona needs arm64 WebView native code.",
        "ZIP lib inventory",
    )
    add_check(
        rows,
        "arm32_compat_libs",
        "PASS" if libs.get("armeabi-v7a") else "WARN",
        ", ".join(libs.get("armeabi-v7a", [])) or "missing",
        "Stock WebView carries armeabi-v7a; missing 32-bit libs may affect 32-bit app paths.",
        "ZIP lib inventory",
    )

    trichrome_refs = [ref for ref in refs if ref.name == TRICHROME_LIBRARY_PACKAGE]
    trichrome_apks = trichrome_library_apks(apks)
    if refs:
        missing = [ref.name for ref in refs if find_library_apk_for_ref(ref, apks) is None]
        add_check(
            rows,
            "static_library_resolution",
            "PASS" if not missing else "FAIL",
            static_ref_summary(refs) if not missing else "missing: " + ", ".join(sorted(set(missing))),
            "Every uses-static-library reference must resolve to a package/static-library shipped in the ROM bundle.",
            "AndroidManifest.xml uses-static-library/static-library graph",
        )
    else:
        add_check(
            rows,
            "static_library_resolution",
            "PASS",
            "no uses-static-library refs",
            "Standalone WebView donors do not need static shared-library resolution.",
            "AndroidManifest.xml",
        )

    if trichrome_refs and not trichrome_apks:
        status = "FAIL"
        observed = "provider references com.google.android.trichromelibrary but bundle has no library package"
    elif trichrome_refs and trichrome_apks:
        status = "PASS"
        observed = ", ".join(f"{apk.package}:{apk.name}" for apk in trichrome_apks)
    elif trichrome_apks:
        status = "WARN"
        observed = "Trichrome library package exists but no provider uses-static-library ref was parsed"
    else:
        status = "PASS"
        observed = "standalone/no Trichrome package"
    add_check(
        rows,
        "trichrome_library_presence",
        status,
        observed,
        "A Trichrome provider must be bundled with the matching TrichromeLibrary/static shared-library package.",
        "package names and static-library declarations",
    )

    version_mismatches = []
    version_unknown = []
    for ref in refs:
        library_apk = find_library_apk_for_ref(ref, apks)
        provided_version = provided_version_for_ref(ref, library_apk)
        if ref.version is None or provided_version is None:
            version_unknown.append(ref.name)
        elif ref.version != provided_version:
            version_mismatches.append(f"{ref.name}: ref={ref.version} provided={provided_version}")
    if version_mismatches:
        status = "FAIL"
        observed = "; ".join(version_mismatches)
    elif version_unknown:
        status = "WARN"
        observed = "unknown static version for " + ", ".join(sorted(set(version_unknown)))
    else:
        status = "PASS"
        observed = "matched" if refs else "no static refs"
    add_check(
        rows,
        "static_library_version_match",
        status,
        observed,
        "uses-static-library android:version must match the provided static-library version when present.",
        "AndroidManifest.xml static library metadata",
    )

    digest_fail = []
    digest_warn = []
    for ref in refs:
        if not ref.cert_digest:
            digest_warn.append(f"{ref.name}: ref has no certDigest")
            continue
        library_apk = find_library_apk_for_ref(ref, apks)
        if library_apk is None:
            continue
        if not library_apk.signer_sha256_digests:
            digest_warn.append(f"{ref.name}: signer digest unavailable")
        elif ref.cert_digest not in library_apk.signer_sha256_digests:
            digest_fail.append(f"{ref.name}: ref digest not in library signer digests")
    if digest_fail:
        status = "FAIL"
        observed = "; ".join(digest_fail)
    elif digest_warn:
        status = "WARN"
        observed = "; ".join(digest_warn)
    else:
        status = "PASS"
        observed = "matched" if refs else "no static refs"
    add_check(
        rows,
        "static_library_cert_digest_match",
        status,
        observed,
        "uses-static-library certDigest should match the library package signing certificate digest; unavailable signer tooling is a warning, not flash authorization.",
        "apksigner verify --print-certs",
    )

    signer_notes = "; ".join(note for apk in apks for note in apk.signer_notes)
    parser_notes = "; ".join(note for apk in apks for note in apk.parser_notes)
    signer_status = "PASS" if (not refs or not signer_notes) else "WARN"
    signer_observed = signer_notes or "signer SHA-256 digests extracted"
    if not refs and signer_notes:
        signer_observed = "not required for standalone/no-static-library donor; " + signer_observed
    add_check(
        rows,
        "signer_cert_extraction",
        signer_status,
        signer_observed,
        "Cert digest checks should be backed by apksigner when the bundle declares uses-static-library certDigest values.",
        "apksigner output",
    )
    add_check(
        rows,
        "parser_completeness",
        "PASS" if not parser_notes else "WARN",
        parser_notes or "aapt badging/xmltree OK for all APKs",
        "All APKs should be readable by local aapt before donor promotion.",
        "aapt output",
    )

    route, requirements = rom_route(provider, classification, allow_framework_config_patch)
    add_check(
        rows,
        "recommended_rom_route",
        "INFO",
        route,
        "; ".join(requirements),
        "Smartisax WebView backport route model",
    )

    if any(row.status == "FAIL" for row in rows):
        verdict = "FAIL"
    elif any(row.status == "WARN" for row in rows):
        verdict = "WARN"
    elif classification == "trichrome-static-library-bundle":
        verdict = "PASS_TRICHROME"
    else:
        verdict = "PASS_STANDALONE"
    return rows, verdict, classification


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
    apks: list[ApkInfo],
    checks: list[CheckRow],
    verdict: str,
    classification: str,
    allow_framework_config_patch: bool,
) -> None:
    providers = provider_candidates(apks)
    provider = providers[0] if len(providers) == 1 else None
    refs = static_refs(apks)
    provides = static_provides(apks)
    route, requirements = rom_route(provider, classification, allow_framework_config_patch)
    lines: list[str] = []
    lines.append(f"# WebView Trichrome Bundle Audit: {label}")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline audit. It does not download donors, build")
    lines.append("images, touch a device, flash, reboot, erase partitions, write settings,")
    lines.append("or modify `/data`.")
    lines.append("")
    lines.append(f"Verdict: **{verdict}**")
    lines.append(f"Classification: **{classification}**")
    lines.append("")
    lines.append("## Input")
    lines.append("")
    lines.append(f"- input: `{rel(input_path)}`")
    lines.append(f"- label: `{label}`")
    lines.append(f"- allow framework config patch: `{str(allow_framework_config_patch).lower()}`")
    lines.append(f"- provider candidate count: `{len(providers)}`")
    lines.append(f"- package count: `{len(package_names(apks))}`")
    lines.append("")
    lines.append("## Provider")
    lines.append("")
    if provider is None:
        lines.append("No single base WebView provider candidate was selected.")
    else:
        lines.append("| Field | Value |")
        lines.append("| --- | --- |")
        lines.append(f"| APK | `{provider.name}` |")
        lines.append(f"| package | `{provider.package}` |")
        lines.append(f"| version | `{provider.version_name}` / `{provider.version_code}` |")
        lines.append(f"| SDK | `min={provider.min_sdk} target={provider.target_sdk} compile={provider.compile_sdk}` |")
        lines.append(f"| WebViewLibrary | `{library_filename(provider) or 'missing'}` |")
        lines.append(f"| factory provider class | `{provider.factory_provider_class_present}` |")
    lines.append("")
    lines.append("## Static Library Graph")
    lines.append("")
    lines.append("| Kind | Owner | Name | Version | Required | Cert digest |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    if not refs and not provides:
        lines.append("| none | none | none | none | none | none |")
    for ref in refs:
        lines.append(
            f"| uses-static-library | `{ref.owner_package or ref.owner_apk}` | `{ref.name}` | `{ref.version}` | `{ref.required or 'implicit'}` | `{ref.cert_digest or 'missing'}` |"
        )
    for provided in provides:
        lines.append(
            f"| static-library | `{provided.owner_package or provided.owner_apk}` | `{provided.name}` | `{provided.version}` | n/a | n/a |"
        )
    lines.append("")
    lines.append("## Recommended ROM Route")
    lines.append("")
    lines.append(f"- route: `{route}`")
    for requirement in requirements:
        lines.append(f"- requirement: {requirement}")
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
    lines.append("| APK | split | package | version | sha256 | signers | libs | dex |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for apk in apks:
        libs = "; ".join(f"{abi}: {', '.join(values)}" for abi, values in apk.libs_by_abi.items()) or "none"
        signers = ", ".join(digest[:16] + "..." for digest in apk.signer_sha256_digests) or "; ".join(apk.signer_notes) or "none"
        lines.append(
            f"| {apk.name} | {apk.split or 'base'} | {apk.package} | {apk.version_name} / {apk.version_code} | {apk.sha256} | {signers} | {libs} | {', '.join(apk.dex_entries) or 'none'} |"
        )
    lines.append("")
    lines.append("## Next Gate")
    lines.append("")
    lines.append("This report is not flash authorization. A PASS or WARN bundle still needs")
    lines.append("v0.31 stock WebView live proof, a concrete ROM layout plan, package mtime")
    lines.append("handling, oat/vdex policy, and post-boot `cmd webviewupdate`/relro tests")
    lines.append("before any donor-backed image is built.")
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
    parser.add_argument("--label", help="Output label under hard-rom/inspect/browser-webview-trichrome-bundle.")
    parser.add_argument(
        "--allow-framework-config-patch",
        action="store_true",
        help="Downgrade non-com.android.webview provider route from FAIL to WARN for explicit framework-provider design.",
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

    with tempfile.TemporaryDirectory(prefix="r2-webview-trichrome-") as tmp:
        apk_paths = extract_input(args.input, Path(tmp))
        reports = [analyze_apk(path) for path in apk_paths]

    checks, verdict, classification = evaluate(reports, args.allow_framework_config_patch)

    tsv_path = out_dir / "trichrome-bundle-audit.tsv"
    md_path = out_dir / "trichrome-bundle-audit.md"
    json_path = out_dir / "trichrome-bundle-audit.json"
    write_tsv(tsv_path, checks)
    write_markdown(md_path, label, args.input.resolve(), reports, checks, verdict, classification, args.allow_framework_config_patch)
    json_path.write_text(
        json.dumps(
            {
                "label": label,
                "input": rel(args.input.resolve()),
                "verdict": verdict,
                "classification": classification,
                "allow_framework_config_patch": args.allow_framework_config_patch,
                "provider_candidates": [apk.name for apk in provider_candidates(reports)],
                "packages": package_names(reports),
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
    print(f"classification={classification}")
    print(f"markdown={rel(md_path)}")
    print(f"tsv={rel(tsv_path)}")
    print(f"json={rel(json_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
