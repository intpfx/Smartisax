#!/usr/bin/env python3
"""Generate the Route A WebView provider specification for Smartisax.

This helper is read-only. It turns current framework-contract, stock donor,
bundle, target-matrix, and v0.31 evidence into a concrete acceptance
specification for a future source-built or adapted standalone
com.android.webview provider. It does not download donors, build images, touch
a device, flash, reboot, erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_MD = ROOT / "docs" / "research" / "webview-route-a-provider-spec.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-route-a-provider-spec.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-route-a-provider-spec"
OUT_JSON = OUT_DIR / "webview-route-a-provider-spec.json"

FRAMEWORK_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-framework-contract"
    / "webview-framework-contract-audit.json"
)
TARGET_MATRIX_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-donor-target-matrix"
    / "webview-donor-target-matrix.json"
)
DONOR_SELFTEST_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-donor"
    / "stock-webview-selftest"
    / "webview-donor-audit.json"
)
BUNDLE_SELFTEST_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-trichrome-bundle"
    / "stock-webview-standalone"
    / "trichrome-bundle-audit.json"
)
INTEGRATION_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-integration-plan" / "webview-integration-plan.json"
V031_OFFLINE_DIR = ROOT / "hard-rom" / "inspect" / "v0.31-webview-stock-near-noop"
LIVE_STATE_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-live-state"

FRAMEWORK_MD = ROOT / "docs" / "research" / "webview-framework-contract-audit.md"
TARGET_MATRIX_MD = ROOT / "docs" / "research" / "webview-donor-target-matrix.md"
INTEGRATION_MD = ROOT / "docs" / "research" / "webview-integration-plan.md"
ROM_DESIGN_MD = ROOT / "docs" / "research" / "webview-rom-design-plan.md"

STOCK_VERSION_CODE_COHORT = 3770


@dataclass(frozen=True)
class SpecRequirement:
    section: str
    requirement_id: str
    level: str
    requirement: str
    stock_reference: str
    acceptance_evidence: str
    fail_condition: str
    route_impact: str


@dataclass(frozen=True)
class Gate:
    phase: str
    gate_id: str
    status: str
    expected_evidence: str
    blocks: str


@dataclass(frozen=True)
class SourceInput:
    source: str
    status: str
    evidence: str


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def latest_v031_offline() -> Path | None:
    return latest_matching(V031_OFFLINE_DIR, "verify-v0.31-webview-stock-near-noop-offline-image-*.txt")


def latest_v031_live() -> Path | None:
    return latest_matching(V031_OFFLINE_DIR, "verify-v0.31-webview-stock-near-noop-device-*.txt")


def latest_live_state() -> Path | None:
    return latest_matching(LIVE_STATE_DIR, "browser-webview-live-state-*.txt")


def latest_matching(directory: Path, pattern: str) -> Path | None:
    if not directory.exists():
        return None
    matches = sorted(directory.glob(pattern))
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def source_inputs() -> list[SourceInput]:
    framework = read_json(FRAMEWORK_JSON)
    matrix = read_json(TARGET_MATRIX_JSON)
    donor = read_json(DONOR_SELFTEST_JSON)
    bundle = read_json(BUNDLE_SELFTEST_JSON)
    integration = read_json(INTEGRATION_JSON)
    v031 = latest_v031_offline()
    v031_live = latest_v031_live()
    live_state = latest_live_state()
    return [
        SourceInput(
            "framework_contract",
            "PASS" if framework and not [row for row in framework.get("rows", []) if row.get("status") == "FAIL"] else "MISSING_OR_FAIL",
            rel(FRAMEWORK_JSON) if framework else f"missing {rel(FRAMEWORK_JSON)}",
        ),
        SourceInput(
            "target_matrix",
            str((matrix.get("summary") or {}).get("preferred_route", "missing")),
            rel(TARGET_MATRIX_JSON) if matrix else f"missing {rel(TARGET_MATRIX_JSON)}",
        ),
        SourceInput(
            "stock_donor_selftest",
            str(donor.get("verdict", "MISSING")),
            rel(DONOR_SELFTEST_JSON) if donor else f"missing {rel(DONOR_SELFTEST_JSON)}",
        ),
        SourceInput(
            "stock_bundle_selftest",
            str(bundle.get("verdict", "MISSING")),
            rel(BUNDLE_SELFTEST_JSON) if bundle else f"missing {rel(BUNDLE_SELFTEST_JSON)}",
        ),
        SourceInput(
            "integration_plan",
            f"build_ready={sum(1 for item in integration.get('candidates', []) if item.get('build_readiness') == 'READY_FOR_OFFLINE_IMAGE_DESIGN')}",
            rel(INTEGRATION_JSON) if integration else f"missing {rel(INTEGRATION_JSON)}",
        ),
        SourceInput(
            "v0.31_offline_gate",
            "PASS" if v031 else "MISSING",
            rel(v031) if v031 else f"missing {rel(V031_OFFLINE_DIR)} offline report",
        ),
        SourceInput(
            "browser_webview_live_state",
            "PASS" if live_state else "MISSING",
            rel(live_state) if live_state else f"missing {rel(LIVE_STATE_DIR)} live-state report",
        ),
        SourceInput(
            "v0.31_live_provider_gate",
            "PASS" if v031_live else "MISSING",
            rel(v031_live) if v031_live else f"missing {rel(V031_OFFLINE_DIR)} device verifier",
        ),
    ]


def stock_reference() -> dict:
    framework = read_json(FRAMEWORK_JSON)
    stock = framework.get("stock_webview", {})
    donor = read_json(DONOR_SELFTEST_JSON)
    base = {}
    for apk in donor.get("apks", []):
        if apk.get("name") == donor.get("base_apk") or not base:
            base = apk
    return {
        "package": stock.get("package") or base.get("package", "com.android.webview"),
        "version_name": stock.get("version_name") or base.get("version_name", "75.0.3770.156"),
        "version_code": stock.get("version_code") or base.get("version_code", 377015630),
        "target_sdk": stock.get("target_sdk") or base.get("target_sdk", 30),
        "min_sdk": stock.get("min_sdk") or base.get("min_sdk", 21),
        "application_name": stock.get("application_name") or base.get("application_name", "com.android.webview.chromium.WebViewApplication"),
        "library_meta": stock.get("library_meta") or "libwebviewchromium.so",
        "sandbox": f"{stock.get('sandbox_service_count', 40)}/{stock.get('sandbox_meta', 40)}",
        "privileged": f"{stock.get('privileged_service_count', 0)}/{stock.get('privileged_meta', 0)}",
        "abis": ",".join(sorted((stock.get("libs_by_abi") or base.get("libs_by_abi") or {}).keys())),
        "sha256": base.get("sha256", "unknown"),
    }


def spec_requirements() -> list[SpecRequirement]:
    stock = stock_reference()
    stock_summary = (
        f"stock={stock['package']} {stock['version_name']}/{stock['version_code']}; "
        f"sdk=min{stock['min_sdk']}/target{stock['target_sdk']}; "
        f"library={stock['library_meta']}; abis={stock['abis']}; "
        f"sandbox={stock['sandbox']}; sha256={stock['sha256']}"
    )
    return [
        SpecRequirement(
            "artifact_identity",
            "A-ID-01",
            "MUST",
            "The Route A provider package name must be com.android.webview.",
            "framework config_webview_packages.xml whitelists only com.android.webview.",
            "Donor audit package_identity PASS and bundle audit framework_provider_route PASS.",
            "Base provider package is com.google.android.webview, com.android.browser, or any package other than com.android.webview.",
            "Non-com.android.webview material moves to Route B/C and must not be built as Route A.",
        ),
        SpecRequirement(
            "artifact_identity",
            "A-ID-02",
            "MUST",
            "The provider must be standalone for Route A: one WebView provider package plus optional splits for the same package, with no unresolved uses-static-library dependencies.",
            "stock WebView bundle classification is standalone-webview.",
            "Trichrome bundle audit bundle_classification PASS with standalone-webview and static_library_resolution PASS.",
            "Any com.google.android.trichromelibrary or uses-static-library dependency is present.",
            "Move to Route C multi-package design.",
        ),
        SpecRequirement(
            "version_sdk",
            "A-SDK-01",
            "MUST",
            "targetSdkVersion must be >= 30 and minSdkVersion must be <= 30.",
            "stock targetSdk=30, minSdk=21; Android 11 WebViewUpdater enforces targetSdk >= 30.",
            "Donor audit min_sdk_device_compat and target_sdk_webviewupdater PASS.",
            "targetSdkVersion < 30 or minSdkVersion > 30.",
            "Provider is rejected before runtime loading.",
        ),
        SpecRequirement(
            "version_sdk",
            "A-VER-01",
            "MUST",
            f"versionCode / 100000 cohort must be >= stock floor {STOCK_VERSION_CODE_COHORT}.",
            "stock versionCode=377015630; framework floor cohort=3770.",
            "Donor audit version_code_cohort PASS and records donor versionName/versionCode.",
            "Donor versionCode cohort is below 3770 or malformed.",
            "WebViewUpdater can reject the provider even if versionName looks modern.",
        ),
        SpecRequirement(
            "manifest_runtime",
            "A-MAN-01",
            "MUST",
            "AndroidManifest.xml must expose com.android.webview.WebViewLibrary=libwebviewchromium.so or an intentionally framework-compatible equivalent backed by the same native library name.",
            "stock WebViewLibrary metadata points to libwebviewchromium.so.",
            "Donor audit webview_library_metadata and webview_native_library_present PASS.",
            "WebViewLibrary metadata is missing, empty, or points to a library absent from the package/splits.",
            "WebViewFactory.getWebViewLibrary returns null or native load fails.",
        ),
        SpecRequirement(
            "manifest_runtime",
            "A-MAN-02",
            "MUST",
            "Dex must contain com.android.webview.chromium.WebViewChromiumFactoryProviderForR or proven Android 11-compatible glue for that class name.",
            "R2 framework.jar loads WebViewChromiumFactoryProviderForR.",
            "Donor audit android11_factory_provider_class PASS.",
            "Factory provider class is absent and no compatibility bridge is provided.",
            "WebViewFactory cannot instantiate the provider.",
        ),
        SpecRequirement(
            "manifest_runtime",
            "A-MAN-03",
            "MUST",
            "Sandbox and privileged service metadata must match declared service counts.",
            "stock sandbox services are 40/40 and privileged services are 0/0.",
            "Donor audit sandbox_service_contract PASS and bundle audit records matching metadata/service declarations.",
            "NUM_SANDBOXED_SERVICES or NUM_PRIVILEGED_SERVICES disagrees with manifest declarations.",
            "Chromium renderer service launch can fail after boot.",
        ),
        SpecRequirement(
            "native_abi",
            "A-ABI-01",
            "MUST",
            "arm64-v8a libwebviewchromium.so must be present and version-matched with Java/resources.",
            "R2/kona is arm64 and stock WebView includes arm64-v8a libwebviewchromium.so.",
            "Donor audit arm64_runtime PASS and native library hash inventory recorded.",
            "arm64 libwebviewchromium.so is missing or borrowed from a different version set.",
            "Native WebView load or relro creation can fail.",
        ),
        SpecRequirement(
            "native_abi",
            "A-ABI-02",
            "SHOULD",
            "Retain armeabi-v7a libwebviewchromium.so unless a live audit proves all relevant app paths are 64-bit-only.",
            "stock WebView includes armeabi-v7a and use32bitAbi=true.",
            "Donor audit arm32_app_compat PASS, or a documented accepted warning before image design.",
            "32-bit library missing with no accepted compatibility review.",
            "32-bit WebView users may regress.",
        ),
        SpecRequirement(
            "rom_layout",
            "A-ROM-01",
            "MUST",
            "First Route A image scope is product_b /product/app/webview only after v0.31 live proof.",
            "v0.31 stock near-noop is the current product_b WebView freshness gate.",
            "ROM design plan references v0.31 live PASS before donor-backed image generation.",
            "A donor-backed image is built directly from v0.29 or changes framework/system without a separate gate.",
            "Build path bypasses the WebView package-cache freshness proof.",
        ),
        SpecRequirement(
            "rom_layout",
            "A-ROM-02",
            "MUST",
            "Use the shared-block-safe replacement pattern for product ext4 contents and verify dumped APK hashes after e2fsck.",
            "project build rules require held-stock inode replacement on shared_blocks images.",
            "Offline verifier records e2fsck, dumped APK sha256, ZIP integrity, and sparse product_b slice equality.",
            "debugfs rm + write is used on shared_blocks without held-stock protection.",
            "e2fsck can repair shared blocks by corrupting the replacement APK.",
        ),
        SpecRequirement(
            "package_cache",
            "A-CACHE-01",
            "MUST",
            "Bump /product/app/webview package directory mtime beyond stale package_cache entries.",
            "v0.26a.1 proved Android 11 PackageCacher can reuse stale ParsedPackage data when directory mtime is old.",
            "Offline verifier records package directory mtime and live verifier confirms PackageManager sees expected package/hash.",
            "APK changes but package directory mtime is not advanced.",
            "PackageManager can parse stale WebView metadata.",
        ),
        SpecRequirement(
            "package_cache",
            "A-CACHE-02",
            "MUST",
            "Remove or regenerate stale /product/app/webview/oat/vdex artifacts when dex/native code changes.",
            "target matrix records stale oat/vdex handling as a Route A image action.",
            "Image verifier records oat/vdex absence or expected regenerated state.",
            "Changed dex/native package leaves stock oat/vdex in place without proof it is ignored.",
            "Boot/runtime can execute mismatched optimized code.",
        ),
        SpecRequirement(
            "package_signature",
            "A-SIG-01",
            "MUST",
            "A source-built same-package WebView must have an explicit PackageManager signing transition plan before ROM image design.",
            "v0.26a/v0.26a.1 proved Android 11 system-package scans depend on a readable APK v2 signing block as the certificate carrier when payload digests no longer verify.",
            "Candidate intake records either stock-cert-carrier adaptation evidence, a same-cert signed build, or a deliberately tested package-setting migration gate.",
            "Source-built SystemWebView.apk is promoted directly with a different signing certificate and no same-package transition proof.",
            "PackageManager may reject or stale-cache the provider before WebViewUpdateService can evaluate it.",
        ),
        SpecRequirement(
            "live_verification",
            "A-LIVE-01",
            "MUST",
            "Before any donor-backed flash, capture current Browser/WebView live state and live-verify v0.31 stock provider near-noop.",
            "current matrix has live-state and v0.31 live gates PASS; this baseline must be preserved and rerun after any donor-backed flash.",
            "browser-webview-live-state report PASS and v0.31 device verifier PASS.",
            "Donor image is built/flashed without current live-state and v0.31 stock-provider baseline evidence.",
            "Cannot distinguish donor regression from existing USB/package-cache state.",
        ),
        SpecRequirement(
            "live_verification",
            "A-LIVE-02",
            "MUST",
            "After donor-backed boot, verify sys.boot_completed, slot, root, keyguard/launcher, package path/hash, cmd webviewupdate, relro/native load, Settings WebView selector, and Smartisan Big Bang/WebView surfaces.",
            "SettingsSmartisan source delegates to IWebViewUpdateService and warns that non-built-in WebView can affect Big Bang/WebView features.",
            "Device verifier report covers all listed surfaces with no fatal WebView/PackageManager logs.",
            "Verifier checks only package installation or only boot completion.",
            "A broad WebView provider regression can be missed.",
        ),
        SpecRequirement(
            "rejected_shortcuts",
            "A-REJ-01",
            "MUST_NOT",
            "Do not treat BrowserChrome, Chrome, Quark, or a native-library-only swap as a Route A WebView provider.",
            "BrowserChrome negative audit fails provider whitelist, targetSdk, WebViewLibrary/native lib, and factory class gates; target matrix rejects lib-only swaps.",
            "Candidate source is explicitly com.android.webview and passes donor/bundle audits.",
            "Candidate is a browser APK or only libwebviewchromium.so is replaced.",
            "This reopens the v0.3/v0.3.1 failure class or creates Java/native ABI mismatch.",
        ),
    ]


def gates() -> list[Gate]:
    return [
        Gate(
            "donor_intake",
            "A-GATE-01",
            "READY_FOR_FUTURE_INPUT",
            "Run tools/r2-webview-donor-inbox-audit.py on actual donor/source-build output, then inspect donor and bundle JSON.",
            "Any Route A donor/source-build promotion.",
        ),
        Gate(
            "donor_intake",
            "A-GATE-02",
            "REQUIRED",
            "Donor audit verdict PASS and Trichrome bundle audit verdict PASS_STANDALONE.",
            "ROM image design.",
        ),
        Gate(
            "image_design",
            "A-GATE-03",
            "REQUIRED",
            "tools/r2-webview-integration-plan.py and tools/r2-webview-rom-design-plan.py report a modern candidate ready for design review.",
            "ROM builder implementation.",
        ),
        Gate(
            "live_precondition",
            "A-GATE-04",
            "RECORDED_BASELINE",
            "Browser/WebView live-state capture PASS and v0.31 stock provider live verifier PASS.",
            "Future donor-backed image build/flash still needs a real modern candidate and image verifier.",
        ),
        Gate(
            "offline_image",
            "A-GATE-05",
            "FUTURE_REQUIRED",
            "Offline image verifier proves product_b-only scope, e2fsck, dumped provider hashes, package directory mtime, oat/vdex policy, donor/bundle audit PASS, and sparse slice equality.",
            "Flash preflight.",
        ),
        Gate(
            "live_candidate",
            "A-GATE-06",
            "FUTURE_REQUIRED",
            "Post-boot verifier covers boot, slot, root, keyguard/launcher, PackageManager path/hash, webviewupdate, relro/native load, Settings selector, Big Bang/WebView surfaces, and logs.",
            "Accepting a modern WebView provider candidate.",
        ),
    ]


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
    return lines


def write_tsv(path: Path, sources: list[SourceInput], requirements: list[SpecRequirement], gate_rows: list[Gate]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "status_or_level", "requirement_or_evidence", "acceptance_or_blocks", "fail_condition"])
        for source in sources:
            writer.writerow(["source", source.source, source.status, source.evidence, "", ""])
        for row in requirements:
            writer.writerow(["requirement", row.requirement_id, row.level, row.requirement, row.acceptance_evidence, row.fail_condition])
        for row in gate_rows:
            writer.writerow(["gate", row.gate_id, row.status, row.expected_evidence, row.blocks, ""])


def write_markdown(path: Path, sources: list[SourceInput], requirements: list[SpecRequirement], gate_rows: list[Gate]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    stock = stock_reference()
    lines: list[str] = []
    lines.append("# WebView Route A Provider Spec")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline specification for a future Route A WebView")
    lines.append("provider. It does not download donors, build images, touch a device,")
    lines.append("flash, reboot, erase partitions, write settings, or modify `/data`.")
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    lines.append("Route A means: keep the provider package as `com.android.webview` and")
    lines.append("replace `/product/app/webview` only after the v0.31 live provider gate")
    lines.append("has passed. This avoids early framework XML/provider-add risk.")
    lines.append("")
    lines.append("The spec is now ready for donor/source-build intake, but no donor-backed")
    lines.append("image is authorized from the current state.")
    lines.append("")
    lines.append("## Stock Reference")
    lines.append("")
    lines.extend(
        md_table(
            ["Item", "Value"],
            [
                ["package", str(stock["package"])],
                ["version", f"{stock['version_name']} / {stock['version_code']}"],
                ["sdk", f"min={stock['min_sdk']} target={stock['target_sdk']}"],
                ["application", str(stock["application_name"])],
                ["WebViewLibrary", str(stock["library_meta"])],
                ["ABIs", str(stock["abis"])],
                ["sandbox", str(stock["sandbox"])],
                ["privileged", str(stock["privileged"])],
                ["stock apk sha256", str(stock["sha256"])],
            ],
        )
    )
    lines.append("")
    lines.append("## Source Evidence")
    lines.append("")
    lines.extend(md_table(["Source", "Status", "Evidence"], [[row.source, row.status, row.evidence] for row in sources]))
    lines.append("")
    lines.append("## Requirements")
    lines.append("")
    for section in sorted({row.section for row in requirements}):
        lines.append(f"### {section}")
        lines.append("")
        rows = [
            [
                row.requirement_id,
                row.level,
                row.requirement,
                row.stock_reference,
                row.acceptance_evidence,
                row.fail_condition,
                row.route_impact,
            ]
            for row in requirements
            if row.section == section
        ]
        lines.extend(md_table(["ID", "Level", "Requirement", "Stock reference", "Acceptance evidence", "Fail condition", "Route impact"], rows))
        lines.append("")
    lines.append("## Gate Order")
    lines.append("")
    lines.extend(md_table(["Phase", "Gate", "Status", "Expected evidence", "Blocks"], [[row.phase, row.gate_id, row.status, row.expected_evidence, row.blocks] for row in gate_rows]))
    lines.append("")
    lines.append("## Current Blockers")
    lines.append("")
    lines.append("- No modern source-built/adapted standalone `com.android.webview` output is present yet.")
    lines.append("- Source-built same-package signing/certificate-carrier transition is not proven yet.")
    lines.append("- Donor-backed image generation is still deferred until a real candidate passes Route A intake, integration, and ROM design gates.")
    lines.append("")
    lines.append("## Next Offline Step")
    lines.append("")
    lines.append("Produce or obtain one Route A candidate directory/archive, then run donor")
    lines.append("and Trichrome bundle audits against it. The candidate must not enter ROM")
    lines.append("image design until every MUST requirement above has concrete evidence.")
    lines.append("")
    lines.append("## Source Reports")
    lines.append("")
    lines.append(f"- Framework contract: `{rel(FRAMEWORK_MD)}`")
    lines.append(f"- Target matrix: `{rel(TARGET_MATRIX_MD)}`")
    lines.append(f"- Integration plan: `{rel(INTEGRATION_MD)}`")
    lines.append(f"- ROM design plan: `{rel(ROM_DESIGN_MD)}`")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    sources = source_inputs()
    requirements = spec_requirements()
    gate_rows = gates()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(OUT_TSV, sources, requirements, gate_rows)
    write_markdown(OUT_MD, sources, requirements, gate_rows)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "route": "ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW",
                "package_target": "com.android.webview",
                "partition_scope": "product_b /product/app/webview",
                "donor_backed_image_allowed": False,
                "spec_status": "READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE",
                "stock_reference": stock_reference(),
                "sources": [asdict(row) for row in sources],
                "requirements": [asdict(row) for row in requirements],
                "gates": [asdict(row) for row in gate_rows],
                "current_blockers": [
                    "no modern standalone com.android.webview donor/source-build output is present",
                    "source-built same-package signing/certificate-carrier transition is not proven",
                ],
                "outputs": {
                    "markdown": rel(OUT_MD),
                    "tsv": rel(OUT_TSV),
                    "json": rel(OUT_JSON),
                },
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    print(f"requirements={len(requirements)}")
    print(f"gates={len(gate_rows)}")
    print("status=READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
