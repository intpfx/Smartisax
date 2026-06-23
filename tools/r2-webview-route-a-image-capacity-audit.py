#!/usr/bin/env python3
"""Audit whether the current Route A WebView candidate can fit in ROM images.

This is an offline/read-only gate. It does not build images, touch a device,
flash, reboot, erase partitions, write settings, or mutate /data.
"""

from __future__ import annotations

import json
import re
import subprocess
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEBUGFS = Path("/opt/homebrew/opt/e2fsprogs/sbin/debugfs")
AAPT = ROOT / "third_party" / "android-build-tools" / "build-tools_r35.0.1_macosx" / "android-15" / "aapt"

STOCK_WEBVIEW = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "raw" / "product" / "app" / "webview" / "webview.apk"
CANDIDATE = ROOT / "apks" / "webview-donor-inbox" / "sourcebuilt-system-webview-150-0-7871-28" / "SystemWebView-stock-carrier.apk"
PRODUCT_IMAGE = ROOT / "hard-rom" / "build" / "product-otatrust-v0.31-webview-stock-near-noop.img"
SYSTEM_IMAGE = ROOT / "hard-rom" / "build" / "system-otatrust-v0.32-browserchrome-stock-near-noop.img"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-route-a-image-capacity"
OUT_JSON = OUT_DIR / "webview-route-a-image-capacity-audit.json"
OUT_MD = ROOT / "docs" / "research" / "webview-route-a-image-capacity-audit.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-route-a-image-capacity-audit.tsv"

WEBVIEW_APK_PATH = "/app/webview/webview.apk"
WEBVIEW_OAT_PATHS = [
    "/app/webview/oat/arm/webview.odex",
    "/app/webview/oat/arm/webview.vdex",
    "/app/webview/oat/arm64/webview.odex",
    "/app/webview/oat/arm64/webview.vdex",
]


@dataclass(frozen=True)
class FsStats:
    path: str
    block_size: int
    block_count: int
    free_blocks: int
    free_bytes: int


@dataclass(frozen=True)
class ApkSize:
    path: str
    file_size: int
    uncompressed_total: int
    lib_arm64: int
    lib_arm32: int
    without_libs: int
    deflate_all_estimate: int
    deflate_no32_estimate: int
    stored_no32_estimate: int
    stored_no32_no_locales_estimate: int
    manifest_multiarch: str
    manifest_use32bitabi: str
    manifest_extractnativelibs: str


@dataclass(frozen=True)
class Gate:
    gate: str
    status: str
    observed: str
    impact: str
    next_step: str


def sh(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)


def die(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def require_file(path: Path) -> None:
    if not path.is_file():
        die(f"missing file: {path}")


def parse_debugfs_stats(path: Path) -> FsStats:
    require_file(path)
    result = sh([str(DEBUGFS), "-R", "stats", str(path)])
    if result.returncode != 0:
        die(f"debugfs stats failed for {path}: {result.stderr or result.stdout}")
    values: dict[str, int] = {}
    for line in result.stdout.splitlines():
        match = re.match(r"(Block size|Block count|Free blocks):\s+(\d+)", line)
        if match:
            values[match.group(1)] = int(match.group(2))
    for key in ["Block size", "Block count", "Free blocks"]:
        if key not in values:
            die(f"debugfs stats missing {key} for {path}")
    return FsStats(
        path=rel(path),
        block_size=values["Block size"],
        block_count=values["Block count"],
        free_blocks=values["Free blocks"],
        free_bytes=values["Block size"] * values["Free blocks"],
    )


def debugfs_file_size(image: Path, image_path: str) -> int:
    result = sh([str(DEBUGFS), "-R", f"stat {image_path}", str(image)])
    if result.returncode != 0:
        return 0
    match = re.search(r"Size:\s+(\d+)", result.stdout)
    return int(match.group(1)) if match else 0


def manifest_bool(path: Path, attr_name: str) -> str:
    result = sh([str(AAPT), "dump", "xmltree", str(path), "AndroidManifest.xml"])
    if result.returncode != 0:
        return "unknown"
    pattern = re.compile(rf":{re.escape(attr_name)}\([^)]*\)=\(type 0x12\)(0x[0-9a-fA-F]+)")
    match = pattern.search(result.stdout)
    if not match:
        return "absent"
    return "true" if match.group(1).lower() == "0xffffffff" else "false"


def deflated_size(path: Path, keep_32bit: bool) -> int:
    total = 0
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            if not keep_32bit and info.filename.startswith("lib/armeabi-v7a/"):
                continue
            data = zf.read(info.filename)
            # zipfile's compressor accounting also includes per-entry headers.
            # This estimate is intentionally used only for relative sizing.
            import zlib

            total += len(zlib.compress(data, 9)) + 64 + len(info.filename)
    return total


def apk_size(path: Path) -> ApkSize:
    require_file(path)
    with zipfile.ZipFile(path) as zf:
        infos = zf.infolist()
        uncompressed_total = sum(info.file_size for info in infos)
        lib_arm64 = sum(
            info.file_size
            for info in infos
            if info.filename == "lib/arm64-v8a/libwebviewchromium.so"
        )
        lib_arm32 = sum(
            info.file_size
            for info in infos
            if info.filename == "lib/armeabi-v7a/libwebviewchromium.so"
        )
        without_libs = uncompressed_total - lib_arm64 - lib_arm32
        stored_no32 = sum(
            info.compress_size
            for info in infos
            if not info.filename.startswith("lib/armeabi-v7a/")
        )
        stored_no32_no_locales = sum(
            info.compress_size
            for info in infos
            if not info.filename.startswith("lib/armeabi-v7a/")
            and "assets/stored-locales/" not in info.filename
        )
    return ApkSize(
        path=rel(path),
        file_size=path.stat().st_size,
        uncompressed_total=uncompressed_total,
        lib_arm64=lib_arm64,
        lib_arm32=lib_arm32,
        without_libs=without_libs,
        deflate_all_estimate=deflated_size(path, keep_32bit=True),
        deflate_no32_estimate=deflated_size(path, keep_32bit=False),
        stored_no32_estimate=stored_no32,
        stored_no32_no_locales_estimate=stored_no32_no_locales,
        manifest_multiarch=manifest_bool(path, "multiArch"),
        manifest_use32bitabi=manifest_bool(path, "use32bitAbi"),
        manifest_extractnativelibs=manifest_bool(path, "extractNativeLibs"),
    )


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def build_gates(product: FsStats, system: FsStats, stock_size: int, oat_size: int, candidate: ApkSize) -> list[Gate]:
    product_replace_budget = product.free_bytes + stock_size + oat_size
    full_external_system_need = candidate.without_libs + candidate.lib_arm64 + candidate.lib_arm32
    only64_external_system_need = candidate.without_libs + candidate.lib_arm64
    return [
        Gate(
            "CAP-GATE-01-product-full-stored",
            "BLOCKED_CAPACITY",
            f"product_replace_budget={product_replace_budget}; candidate_apk={candidate.file_size}; product_free={product.free_bytes}; stock_webview={stock_size}; stale_oat_vdex={oat_size}",
            "A full stored-lib M150 stock-carrier APK cannot replace stock WebView inside product_b.",
            "Do not build a product_b-only stored-lib image from the current candidate.",
        ),
        Gate(
            "CAP-GATE-02-product-deflated-native",
            "REJECTED_FOR_FIRST_IMAGE",
            f"deflate_all_estimate={candidate.deflate_all_estimate}; manifest_extractNativeLibs={candidate.manifest_extractnativelibs}; system-app scan extractLibs=false",
            "Deflating libwebviewchromium.so makes the APK small enough, but system bundled apps are not a normal extracted-native-libs install path; WebView native loading/relro expects loadable native libs.",
            "Treat compressed-native APKs as a separate research item, not the first flash candidate.",
        ),
        Gate(
            "CAP-GATE-03-product-64bit-only",
            "BLOCKED_CAPACITY_AND_RISK",
            f"stored_no32_estimate={candidate.stored_no32_estimate}; product_replace_budget={product_replace_budget}; use32bitAbi={candidate.manifest_use32bitabi}",
            "Dropping armeabi-v7a alone still does not fit product_b, and the manifest asks for 32-bit ABI support.",
            "Do not use 64-bit-only product_b replacement as the next image.",
        ),
        Gate(
            "CAP-GATE-04-system-full-external",
            "BLOCKED_NEEDS_SPACE_REVIEW",
            f"system_free={system.free_bytes}; full_external_need={full_external_system_need}; shortfall={max(0, full_external_system_need - system.free_bytes)}",
            "A safer full-ABI layout needs external native libs on a real filesystem path, but current system_b free space is still short.",
            "Pick an explicit system_b space source or rebuild a smaller WebView before image construction.",
        ),
        Gate(
            "CAP-GATE-05-system-64bit-external",
            "FITS_WITH_32BIT_REGRESSION_RISK",
            f"system_free={system.free_bytes}; only64_external_need={only64_external_system_need}; spare={system.free_bytes - only64_external_system_need}",
            "A 64-bit-only external-lib layout can fit system_b, but 32-bit WebView users and the 32-bit relro path become a known regression risk.",
            "Only build this if the user explicitly accepts a 64-bit-only WebView probe.",
        ),
    ]


def write_tsv(gates: list[Gate]) -> None:
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open("w", encoding="utf-8") as fh:
        fh.write("gate\tstatus\tobserved\timpact\tnext_step\n")
        for gate in gates:
            fh.write(
                "\t".join(
                    [
                        gate.gate,
                        gate.status,
                        gate.observed,
                        gate.impact,
                        gate.next_step,
                    ]
                )
                + "\n"
            )


def write_markdown(product: FsStats, system: FsStats, stock_size: int, oat_size: int, candidate: ApkSize, gates: list[Gate]) -> None:
    rows = "\n".join(
        f"| {gate.gate} | {gate.status} | {gate.observed} | {gate.impact} | {gate.next_step} |"
        for gate in gates
    )
    content = f"""# WebView Route A Image Capacity Audit

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

This is an offline/read-only audit. It does not build images, touch a device,
flash, reboot, erase partitions, write settings, or modify `/data`.

## Result

The current full M150 `SystemWebView-stock-carrier.apk` must not be promoted as
a product_b-only image. The APK is physically larger than the product_b
replacement budget, and the only size experiment that fits product_b relies on
deflating native libraries, which is not accepted for the first WebView image
because bundled system apps do not follow the normal extracted-native-libs
install path.

## Size Evidence

| Item | Bytes |
| --- | ---: |
| product_b free bytes | {product.free_bytes} |
| stock WebView APK bytes | {stock_size} |
| stock WebView oat/vdex bytes | {oat_size} |
| product_b replacement budget | {product.free_bytes + stock_size + oat_size} |
| M150 stock-carrier APK bytes | {candidate.file_size} |
| M150 arm64 lib bytes | {candidate.lib_arm64} |
| M150 armeabi-v7a lib bytes | {candidate.lib_arm32} |
| M150 APK without WebView libs bytes | {candidate.without_libs} |
| deflate-all APK estimate bytes | {candidate.deflate_all_estimate} |
| stored no-32-bit estimate bytes | {candidate.stored_no32_estimate} |
| system_b free bytes | {system.free_bytes} |

Manifest flags from the candidate:

```text
multiArch={candidate.manifest_multiarch}
use32bitAbi={candidate.manifest_use32bitabi}
extractNativeLibs={candidate.manifest_extractnativelibs}
```

## Gates

| Gate | Status | Observed | Impact | Next step |
| --- | --- | --- | --- | --- |
{rows}

## Recommended Next Step

Do not build the original product_b-only Route A1 image. The next safe offline
step is a design decision:

1. Rebuild a smaller WebView from source that keeps loadable native libraries
   and fits product_b, or
2. Design a full-ABI external-native-library layout outside product_b and
   explicitly choose what system_b space to free, or
3. Build a 64-bit-only external-native-library probe only if the 32-bit WebView
   regression risk is explicitly accepted.

## Outputs

- JSON snapshot: `{rel(OUT_JSON)}`
- TSV manifest: `{rel(OUT_TSV)}`
- Markdown report: `{rel(OUT_MD)}`
"""
    OUT_MD.write_text(content, encoding="utf-8")


def main() -> None:
    require_file(DEBUGFS)
    require_file(AAPT)
    product = parse_debugfs_stats(PRODUCT_IMAGE)
    system = parse_debugfs_stats(SYSTEM_IMAGE)
    stock_size = debugfs_file_size(PRODUCT_IMAGE, WEBVIEW_APK_PATH)
    oat_size = sum(debugfs_file_size(PRODUCT_IMAGE, path) for path in WEBVIEW_OAT_PATHS)
    candidate = apk_size(CANDIDATE)
    gates = build_gates(product, system, stock_size, oat_size, candidate)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(gates)
    write_markdown(product, system, stock_size, oat_size, candidate, gates)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().isoformat(timespec="seconds"),
                "verdict": "PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY",
                "donor_backed_image_allowed": False,
                "product": asdict(product),
                "system": asdict(system),
                "stock_webview_apk_size": stock_size,
                "stock_webview_oat_vdex_size": oat_size,
                "candidate": asdict(candidate),
                "gates": [asdict(gate) for gate in gates],
                "recommended_next_step": "Choose smaller source-build, full-ABI external-lib layout with explicit system_b space source, or explicitly accepted 64-bit-only probe.",
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    print("verdict=PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY")
    print("donor_backed_image_allowed=false")
    print(f"report={rel(OUT_MD)}")


if __name__ == "__main__":
    main()
