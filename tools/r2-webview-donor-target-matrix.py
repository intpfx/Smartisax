#!/usr/bin/env python3
"""Generate the Smartisax WebView donor/source-build target matrix.

This helper is read-only. It consumes existing WebView framework contract,
donor inbox, integration-plan, and ROM-design evidence. It does not download
donors, build images, touch a device, flash, reboot, erase partitions, write
settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_MD = ROOT / "docs" / "research" / "webview-donor-target-matrix.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-donor-target-matrix.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-target-matrix"
OUT_JSON = OUT_DIR / "webview-donor-target-matrix.json"

FRAMEWORK_CONTRACT_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-framework-contract"
    / "webview-framework-contract-audit.json"
)
FRAMEWORK_CONTRACT_MD = ROOT / "docs" / "research" / "webview-framework-contract-audit.md"
INBOX_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-inbox" / "webview-donor-inbox-audit.json"
INTEGRATION_JSON = (
    ROOT / "hard-rom" / "inspect" / "browser-webview-integration-plan" / "webview-integration-plan.json"
)
INTEGRATION_MD = ROOT / "docs" / "research" / "webview-integration-plan.md"
ROM_DESIGN_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-rom-design-plan" / "webview-rom-design-plan.json"
ROM_DESIGN_MD = ROOT / "docs" / "research" / "webview-rom-design-plan.md"
SOURCE_PLAN_MD = ROOT / "docs" / "research" / "webview-donor-source-plan.md"
VERSION_GAP_MD = ROOT / "docs" / "research" / "browser-webview-version-gap-audit.md"
ROUTE_A_SPEC_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-provider-spec"
    / "webview-route-a-provider-spec.json"
)
ROUTE_A_SPEC_MD = ROOT / "docs" / "research" / "webview-route-a-provider-spec.md"
ROUTE_A_CANDIDATE_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-candidate-audit"
    / "webview-route-a-candidate-audit.json"
)
ROUTE_A_CANDIDATE_MD = ROOT / "docs" / "research" / "webview-route-a-candidate-audit.md"
CAPACITY_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-image-capacity"
    / "webview-route-a-image-capacity-audit.json"
)
CAPACITY_MD = ROOT / "docs" / "research" / "webview-route-a-image-capacity-audit.md"
SPACE_SOURCE_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-system-space-source"
    / "webview-system-space-source-audit.json"
)
SPACE_SOURCE_MD = ROOT / "docs" / "research" / "webview-system-space-source-audit.md"


@dataclass(frozen=True)
class EvidenceRow:
    gate: str
    status: str
    evidence: str
    impact: str


@dataclass(frozen=True)
class RouteTarget:
    route_id: str
    route_class: str
    status: str
    package_target: str
    partition_scope: str
    material_needed: str
    contract_requirements: str
    image_actions: str
    blockers: str
    next_offline_gate: str
    next_live_gate: str
    risk: str


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


def evidence_lookup(data: dict) -> dict[str, dict]:
    return {str(item.get("gate", "")): item for item in data.get("evidence", []) if item.get("gate")}


def framework_contract_status(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(FRAMEWORK_CONTRACT_JSON)}"
    failures = [row for row in data.get("rows", []) if str(row.get("status", "")) == "FAIL"]
    if failures:
        gates = ", ".join(str(row.get("gate", "unknown")) for row in failures)
        return "FAIL", f"failures={gates}; report={rel(FRAMEWORK_CONTRACT_MD)}"
    providers = data.get("providers", [])
    provider_names = ", ".join(str(item.get("package_name", "unknown")) for item in providers) or "none"
    return "PASS", f"providers={provider_names}; report={rel(FRAMEWORK_CONTRACT_MD)}"


def stock_webview_summary(data: dict) -> str:
    stock = data.get("stock_webview", {})
    if not stock:
        return "missing stock_webview facts"
    libs = stock.get("libs_by_abi") or {}
    abi_summary = ",".join(sorted(libs.keys())) or "unknown"
    return (
        f"package={stock.get('package', 'unknown')}; "
        f"version={stock.get('version_name', 'unknown')}/{stock.get('version_code', 'unknown')}; "
        f"sdk=min{stock.get('min_sdk', 'unknown')}/target{stock.get('target_sdk', 'unknown')}; "
        f"library={stock.get('library_meta', 'unknown')}; "
        f"factoryProviderForR={stock.get('has_factory_provider_for_r', 'unknown')}; "
        f"abis={abi_summary}; sandbox={stock.get('sandbox_service_count', 'unknown')}/{stock.get('sandbox_meta', 'unknown')}"
    )


def donor_inbox_status(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(INBOX_JSON)}"
    candidates = data.get("candidates", [])
    audits = data.get("audits", [])
    status = "PASS" if candidates else "MISSING"
    return (
        status,
        f"candidate_count={len(candidates)}; audit_count={len(audits)}; generated={data.get('generated', 'unknown')}; report={rel(INBOX_JSON)}",
    )


def plan_gate_status(integration: dict, gate: str) -> tuple[str, str]:
    item = evidence_lookup(integration).get(gate)
    if not item:
        return "MISSING", f"{gate} missing from {rel(INTEGRATION_JSON)}"
    return str(item.get("status", "UNKNOWN")), str(item.get("evidence", ""))


def rom_design_summary(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(ROM_DESIGN_JSON)}"
    designs = data.get("designs", [])
    ready = sum(
        1
        for item in designs
        if item.get("status") == "READY_FOR_DESIGN_REVIEW"
        or item.get("design_readiness") == "READY_FOR_DESIGN_REVIEW"
    )
    status = "PASS" if ready else "NOT_READY"
    return (
        status,
        f"designs={len(designs)}; ready_for_design_review={ready}; report={rel(ROM_DESIGN_MD)}",
    )


def route_a_spec_summary(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(ROUTE_A_SPEC_JSON)}"
    requirements = data.get("requirements", [])
    gates = data.get("gates", [])
    return (
        "RECORDED",
        f"requirements={len(requirements)}; gates={len(gates)}; status={data.get('spec_status', 'unknown')}; report={rel(ROUTE_A_SPEC_MD)}",
    )


def route_a_candidate_summary(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(ROUTE_A_CANDIDATE_JSON)}"
    verdict = str(data.get("verdict", "UNKNOWN"))
    summary = data.get("summary") or {}
    if verdict == "BASELINE_SHAPE_PASS_NOT_MODERN":
        status = "BASELINE_ONLY"
    elif verdict == "CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE":
        status = "PASS_SHAPE"
    elif verdict == "CANDIDATE_SHAPE_WARN_BLOCKED_BY_LIVE":
        status = "WARN_SHAPE"
    elif verdict == "FAIL":
        status = "FAIL"
    else:
        status = "UNKNOWN"
    return (
        status,
        f"verdict={verdict}; package={summary.get('base_package', 'unknown')}; "
        f"version={summary.get('version_name', 'unknown')}/{summary.get('version_code', 'unknown')}; "
        f"classification={summary.get('bundle_classification', 'unknown')}; report={rel(ROUTE_A_CANDIDATE_MD)}",
    )


def route_a_capacity_summary(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(CAPACITY_JSON)}"
    verdict = str(data.get("verdict", "UNKNOWN"))
    candidate = data.get("candidate") or {}
    product = data.get("product") or {}
    if verdict == "PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY":
        status = "BLOCKED_CAPACITY"
    else:
        status = "UNKNOWN"
    return (
        status,
        f"verdict={verdict}; candidate_apk={candidate.get('file_size', 'unknown')}; "
        f"product_free={product.get('free_bytes', 'unknown')}; report={rel(CAPACITY_MD)}",
    )


def system_space_source_summary(data: dict) -> tuple[str, str]:
    if not data:
        return "MISSING", f"missing {rel(SPACE_SOURCE_JSON)}"
    verdict = str(data.get("verdict", "UNKNOWN"))
    recommended = str(data.get("recommended_source_id", "unknown"))
    preferred_extra = str(data.get("preferred_extra_source_id", "none"))
    sources = data.get("sources", [])
    preferred = next((item for item in sources if item.get("source_id") == recommended), {})
    extra = next((item for item in sources if item.get("source_id") == preferred_extra), {})
    if verdict == "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_COVERS_RESERVE":
        status = "SELECTED_WITH_RESERVE"
    elif verdict == "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_LOW_RESERVE":
        status = "SELECTED_LOW_RESERVE"
    elif verdict == "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_NOT_ENOUGH":
        status = "SELECTED_NOT_ENOUGH"
    elif verdict == "SYSTEM_B_SPACE_SOURCES_RECORDED_PENDING_USER_SELECTION":
        status = "RECORDED_PENDING_USER_SELECTION"
    else:
        status = "UNKNOWN"
    return (
        status,
        f"verdict={verdict}; recommended={recommended}; "
        f"allocated={preferred.get('allocated_bytes', 'unknown')}; "
        f"margin_to_reserved_target={preferred.get('margin_to_reserved_target', 'unknown')}; "
        f"preferred_extra={preferred_extra}; "
        f"extra_allocated={extra.get('allocated_bytes', 'unknown')}; "
        f"extra_margin_to_reserved_target={extra.get('margin_to_reserved_target', 'unknown')}; "
        f"report={rel(SPACE_SOURCE_MD)}",
    )


def collect_evidence() -> list[EvidenceRow]:
    framework = read_json(FRAMEWORK_CONTRACT_JSON)
    inbox = read_json(INBOX_JSON)
    integration = read_json(INTEGRATION_JSON)
    rom_design = read_json(ROM_DESIGN_JSON)
    route_a_spec = read_json(ROUTE_A_SPEC_JSON)
    route_a_candidate = read_json(ROUTE_A_CANDIDATE_JSON)
    capacity = read_json(CAPACITY_JSON)
    space_source = read_json(SPACE_SOURCE_JSON)

    framework_status, framework_evidence = framework_contract_status(framework)
    inbox_status, inbox_evidence = donor_inbox_status(inbox)
    v031_offline_status, v031_offline_evidence = plan_gate_status(integration, "v0.31_offline_provider_gate")
    live_state_status, live_state_evidence = plan_gate_status(integration, "browser_webview_live_state_capture")
    v031_live_status, v031_live_evidence = plan_gate_status(integration, "v0.31_live_provider_gate")
    a_sig_status, a_sig_evidence = plan_gate_status(integration, "a_sig_package_manager_gate")
    rom_status, rom_evidence = rom_design_summary(rom_design)
    route_a_spec_status, route_a_spec_evidence = route_a_spec_summary(route_a_spec)
    route_a_candidate_status, route_a_candidate_evidence = route_a_candidate_summary(route_a_candidate)
    capacity_status, capacity_evidence = route_a_capacity_summary(capacity)
    space_source_status, space_source_evidence = system_space_source_summary(space_source)
    if space_source_status == "SELECTED_LOW_RESERVE":
        space_source_impact = (
            "The user-selected print-preserving system_b space source covers the bare full-ABI shortfall, "
            "but reserve/layout acceptance or an extra source is still required. The audit currently records "
            "SmartisanWallpapers as the preferred extra-space candidate."
        )
    elif space_source_status == "SELECTED_WITH_RESERVE":
        space_source_impact = (
            "The selected system_b space source covers the full-ABI shortfall plus reserve; package delete preflights and image acceptance remain."
        )
    elif space_source_status == "SELECTED_NOT_ENOUGH":
        space_source_impact = "The selected system_b source is not enough alone; choose more space or a smaller WebView build."
    else:
        space_source_impact = (
            "This records possible system_b space sources for the full-ABI external-native-library layout; user selection is still required."
        )

    live_capture_impact = (
        "Current live Browser/WebView baseline is captured; rerun after v0.31 and every donor-backed flash."
        if live_state_status == "PASS"
        else "Current live capture is blocked or missing; adb/device state must be fixed before v0.31 live proof."
    )
    donor_inbox_impact = (
        "Modern source-built/donor material is present; signing, ROM design review, and live regression gates still decide whether it can become an image."
        if inbox_status == "PASS"
        else "No actual modern donor material is present yet; all donor-backed routes remain design-only."
    )
    rom_design_impact = (
        "A donor-backed design is ready for review."
        if rom_status == "PASS"
        else "No donor-backed design is ready yet; inspect candidate blockers before image work."
    )

    return [
        EvidenceRow(
            "framework_contract_audit",
            framework_status,
            framework_evidence,
            "Route A is valid only when the provider remains or is adapted to com.android.webview; other package names need framework work.",
        ),
        EvidenceRow(
            "stock_webview_contract",
            "RECORDED" if framework else "MISSING",
            stock_webview_summary(framework),
            "This is the compatibility floor every donor/source-build target must preserve or intentionally replace.",
        ),
        EvidenceRow(
            "v0.31_offline_provider_gate",
            v031_offline_status,
            v031_offline_evidence,
            "Offline product_b mtime-only proof exists, but it is not live proof.",
        ),
        EvidenceRow(
            "browser_webview_live_state_capture",
            live_state_status,
            live_state_evidence,
            live_capture_impact,
        ),
        EvidenceRow(
            "v0.31_live_provider_gate",
            v031_live_status,
            v031_live_evidence,
            "No donor-backed WebView image should be built until the stock provider live gate passes or a deliberate alternate recovery path is chosen.",
        ),
        EvidenceRow(
            "modern_donor_inbox",
            inbox_status,
            inbox_evidence,
            donor_inbox_impact,
        ),
        EvidenceRow(
            "a_sig_package_manager_gate",
            a_sig_status,
            a_sig_evidence,
            "Stock-carrier system-scan PackageManager acceptance is recorded offline; explicit image and live proof still gate acceptance."
            if a_sig_status == "OFFLINE_PM_ACCEPTANCE_RECORDED"
            else "Blocks Route A same-package stock-carrier image design until the A-SIG PackageManager audit records acceptance.",
        ),
        EvidenceRow(
            "rom_design_plan",
            rom_status,
            rom_evidence,
            rom_design_impact,
        ),
        EvidenceRow(
            "route_a_provider_spec",
            route_a_spec_status,
            route_a_spec_evidence,
            "This turns Route A into concrete donor/source-build acceptance requirements before any image design.",
        ),
        EvidenceRow(
            "route_a_candidate_audit",
            route_a_candidate_status,
            route_a_candidate_evidence,
            "This maps an actual or baseline candidate onto the Route A provider spec using donor and bundle audits.",
        ),
        EvidenceRow(
            "route_a_image_capacity",
            capacity_status,
            capacity_evidence,
            "This blocks or clears physical image construction after donor shape, signing, and design review gates.",
        ),
        EvidenceRow(
            "system_b_space_source_audit",
            space_source_status,
            space_source_evidence,
            space_source_impact,
        ),
    ]


def evidence_status(evidence: list[EvidenceRow], gate: str) -> str:
    for row in evidence:
        if row.gate == gate:
            return row.status
    return "MISSING"


def missing_core_blockers(evidence: list[EvidenceRow]) -> list[str]:
    blockers: list[str] = []
    if evidence_status(evidence, "framework_contract_audit") != "PASS":
        blockers.append("framework_contract_audit is not PASS")
    if evidence_status(evidence, "browser_webview_live_state_capture") != "PASS":
        blockers.append("browser/WebView live-state capture is missing")
    if evidence_status(evidence, "v0.31_live_provider_gate") != "PASS":
        blockers.append("v0.31 stock WebView live provider gate is missing")
    if evidence_status(evidence, "modern_donor_inbox") != "PASS":
        blockers.append("no actual modern donor material is present")
    if evidence_status(evidence, "a_sig_package_manager_gate") != "OFFLINE_PM_ACCEPTANCE_RECORDED":
        blockers.append("A-SIG PackageManager stock-carrier acceptance is not recorded")
    if evidence_status(evidence, "rom_design_plan") != "PASS":
        blockers.append("ROM design plan has no ready donor-backed design")
    if evidence_status(evidence, "route_a_image_capacity") == "BLOCKED_CAPACITY":
        blockers.append("current Route A product_b-only image is blocked by capacity/native-library layout")
    return blockers


def join_blockers(*items: str) -> str:
    cleaned = [item for item in items if item and item != "none"]
    return "; ".join(cleaned) if cleaned else "none"


def build_targets(evidence: list[EvidenceRow]) -> list[RouteTarget]:
    core_blockers = missing_core_blockers(evidence)
    live_material_blockers = "; ".join(core_blockers) if core_blockers else "none"
    route_a_spec_ready = evidence_status(evidence, "route_a_provider_spec") == "RECORDED"
    candidate_status = evidence_status(evidence, "route_a_candidate_audit")
    route_a_candidate_ready = candidate_status == "PASS_SHAPE"
    a_sig_ready = evidence_status(evidence, "a_sig_package_manager_gate") == "OFFLINE_PM_ACCEPTANCE_RECORDED"
    capacity_blocked = evidence_status(evidence, "route_a_image_capacity") == "BLOCKED_CAPACITY"
    space_source_status = evidence_status(evidence, "system_b_space_source_audit")
    space_source_recorded = space_source_status in {
        "RECORDED_PENDING_USER_SELECTION",
        "SELECTED_WITH_RESERVE",
        "SELECTED_LOW_RESERVE",
        "SELECTED_NOT_ENOUGH",
    }
    space_source_selected_low_reserve = space_source_status == "SELECTED_LOW_RESERVE"
    if route_a_candidate_ready:
        no_donor_blocker = (
            "Route A candidate shape and offline A-SIG PackageManager evidence are recorded; explicit image acceptance and post-flash live regression still block acceptance"
            if a_sig_ready
            else "Route A candidate shape audit passed, but A-SIG review, explicit image acceptance, and post-flash live regression still block image work"
        )
    elif candidate_status == "BASELINE_ONLY":
        no_donor_blocker = "only stock WebView baseline has passed Route A shape audit; no modern candidate is present"
    else:
        no_donor_blocker = "no standalone modern com.android.webview donor/source-build output is present"
    framework_gate_blocker = "requires framework-res config_webview_packages.xml/provider-add gate"
    trichrome_blocker = "requires provider plus static-library package group and install-order/cert/version proof"
    live_state_ready = evidence_status(evidence, "browser_webview_live_state_capture") == "PASS"
    v031_live_ready = evidence_status(evidence, "v0.31_live_provider_gate") == "PASS"
    route_a_next_live = (
        "After a future donor-backed image is built and explicitly confirmed, rerun the full Browser/WebView live regression suite."
        if v031_live_ready
        else "Live-verify v0.31 stock WebView near-noop after explicit confirmation, then rerun Browser/WebView live-state capture."
        if live_state_ready
        else "Capture current Browser/WebView live state, then live-verify v0.31 after explicit confirmation."
    )

    return [
        RouteTarget(
            route_id="ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW",
            route_class="preferred first real modernization target",
            status=(
                "BLOCKED_CAPACITY"
                if capacity_blocked and route_a_candidate_ready and a_sig_ready
                else "READY_FOR_DESIGN_REVIEW"
                if not core_blockers and route_a_candidate_ready and a_sig_ready
                else "PREFERRED_BUT_NOT_READY"
            ),
            package_target="com.android.webview",
            partition_scope="product_b /product/app/webview",
            material_needed="Source-built or adapted standalone Android 11-compatible WebView provider with package com.android.webview.",
            contract_requirements=(
                "targetSdk>=30; versionCode cohort>=3770; com.android.webview.WebViewLibrary=libwebviewchromium.so; "
                "WebViewChromiumFactoryProviderForR; arm64-v8a libwebviewchromium.so; preferably keep armeabi-v7a; "
                "sandbox metadata/service count coherent; Java/native/resources version-matched."
            ),
            image_actions=(
                "Replace /product/app/webview as one version-matched provider set, bump /product/app/webview directory mtime, "
                "remove or regenerate stale oat/vdex when dex/native code changes, verify relro/webviewupdate/settings/Big Bang surfaces."
            ),
            blockers=join_blockers(live_material_blockers, no_donor_blocker),
            next_offline_gate=(
                "Run delete preflights for user_selected_no_projection_print_preserving, then choose extra reserve, a smaller WebView source build, or explicitly accept the low-reserve full-ABI layout before image build."
                if capacity_blocked and space_source_selected_low_reserve and route_a_candidate_ready and a_sig_ready
                else "Run delete preflights for the selected system_b space source, then build only after explicit image acceptance."
                if capacity_blocked and space_source_status == "SELECTED_WITH_RESERVE" and route_a_candidate_ready and a_sig_ready
                else "Ask the user whether to use the recorded no_projection_low_value_service_reserve system_b space source, choose a smaller WebView source build, or explicitly accept another layout; do not build until a space source is selected."
                if capacity_blocked and space_source_recorded and route_a_candidate_ready and a_sig_ready
                else "Choose a smaller WebView source build, a full-ABI external-native-library layout with explicit system_b space source, or an explicitly accepted 64-bit-only probe; do not build the current product_b-only image."
                if capacity_blocked and route_a_candidate_ready and a_sig_ready
                else "Build the first offline candidate design from the stock-carrier WebView, with package-directory mtime bump and oat/vdex cleanup, then require explicit image acceptance."
                if route_a_candidate_ready and a_sig_ready
                else "Regenerate integration and ROM design plans from the audited modern Route A candidate."
                if route_a_candidate_ready
                else "Audit a real source-build/adapted output against the Route A provider spec with donor plus bundle audits."
                if route_a_spec_ready
                else "Define the Route A donor specification and audit a real source-build/adapted output with donor plus bundle audits."
            ),
            next_live_gate=route_a_next_live,
            risk="ORANGE",
        ),
        RouteTarget(
            route_id="ROUTE_A2_PREBUILT_STANDALONE_COM_ANDROID_WEBVIEW",
            route_class="acceptable if an actual standalone donor exists",
            status="ACCEPTABLE_IF_DONOR_EXISTS",
            package_target="com.android.webview",
            partition_scope="product_b /product/app/webview",
            material_needed="A stable standalone APK/APKM/APKS/XAPK whose base provider package is com.android.webview and has no unresolved static-library dependency.",
            contract_requirements=(
                "Same as Route A1, plus split layout must contain exactly one provider package and all splits/native libraries must be version-matched."
            ),
            image_actions=(
                "Promote the audited standalone donor into /product/app/webview, preserve split/base relationship, bump package directory mtime, "
                "handle stale oat/vdex, then run the full WebView live regression suite."
            ),
            blockers=join_blockers(live_material_blockers, "no local prebuilt standalone com.android.webview donor is present"),
            next_offline_gate="Place the donor under apks/webview-donor-inbox/ and run donor inbox, donor audit, and Trichrome bundle audit.",
            next_live_gate=(
                "Same as Route A1: donor-backed live regression after an audited prebuilt donor image exists."
                if v031_live_ready
                else "Same as Route A1: v0.31 live proof before any donor-backed image."
            ),
            risk="ORANGE",
        ),
        RouteTarget(
            route_id="ROUTE_B_GOOGLE_WEBVIEW_PROVIDER_ADD",
            route_class="framework-provider-add route",
            status="DEFERRED_FRAMEWORK_GATE",
            package_target="com.google.android.webview",
            partition_scope="framework-res plus product_b/system_b provider package",
            material_needed="Stable com.google.android.webview donor package or split bundle that passes provider/runtime gates.",
            contract_requirements=(
                "All Route A runtime gates plus framework config_webview_packages.xml provider entry, provider selector behavior, "
                "system-app/signature validity, package path/mtime, and framework resource no-op/live proof."
            ),
            image_actions=(
                "Patch framework WebView provider config, ship provider as a ROM app, bump changed package directories, "
                "verify boot invariants, WebViewUpdateService valid package list, Settings selector, and rollback path."
            ),
            blockers=join_blockers(live_material_blockers, framework_gate_blocker),
            next_offline_gate="Only design this after a real com.google.android.webview donor audit; prepare a separate framework-provider-add no-op gate.",
            next_live_gate="Framework/provider no-op live gate after v0.31 stock provider live proof.",
            risk="RED",
        ),
        RouteTarget(
            route_id="ROUTE_C_TRICHROME_MULTI_PACKAGE",
            route_class="multi-package static-library route",
            status="DEFERRED_MULTI_PACKAGE_GATE",
            package_target="provider plus com.google.android.trichromelibrary or equivalent static-library package(s)",
            partition_scope="product_b/system_b multi-package layout plus possible framework provider config",
            material_needed="Version-matched provider/static-library bundle with base APKs, splits, static-library versions, and certDigest evidence when present.",
            contract_requirements=(
                "All Route B gates plus PackageManager uses-static-library resolution, static library package install location, "
                "matching versions/certDigest, arm64 WebView native code, and deterministic package scan order."
            ),
            image_actions=(
                "Ship all provider/library APKs as a coherent ROM package group, preserve splits, bump all package directory mtimes, "
                "prove PackageManager static-library resolution before WebViewUpdateService selection."
            ),
            blockers=join_blockers(live_material_blockers, trichrome_blocker),
            next_offline_gate="Run r2-webview-trichrome-bundle-audit.py on the actual bundle and produce a package-group install plan.",
            next_live_gate="Multi-package no-op/live package-scan gate before provider selection testing.",
            risk="RED",
        ),
        RouteTarget(
            route_id="ROUTE_D_BROWSERCHROME_ENGINE_REPLACEMENT",
            route_class="separate browser track, not a WebView provider route",
            status="DEFERRED_SEPARATE_TRACK",
            package_target="com.android.browser",
            partition_scope="system_b /system/app/BrowserChrome",
            material_needed="BrowserChrome behavior/engine candidate that preserves Smartisan browser package, provider, resolver, icon, cache, and data contracts.",
            contract_requirements=(
                "Default browser resolver, provider authorities, SmartisanApplication glue, native/dex/assets version matching, oat/vdex handling, "
                "package cache and icon redirection state."
            ),
            image_actions=(
                "Start only from v0.32 BrowserChrome stock near-noop live proof, then use candidate diff audit and package/cache regression checks."
            ),
            blockers="v0.32 is offline-only; BrowserChrome previous same-package replacement broke boot/user UI; not a WebView modernization donor",
            next_offline_gate="Build a BrowserChrome candidate diff audit after v0.32 live proof, separate from WebView provider work.",
            next_live_gate="Live-verify v0.32 stock BrowserChrome near-noop before any behavior/engine candidate.",
            risk="RED",
        ),
        RouteTarget(
            route_id="ROUTE_E_LIB_ONLY_SWAP",
            route_class="rejected shortcut",
            status="REJECTED",
            package_target="com.android.webview or com.android.browser native libraries only",
            partition_scope="none",
            material_needed="None; do not pursue as a ROM route.",
            contract_requirements=(
                "WebView/Chromium Java glue, resources, manifest metadata, native libraries, sandbox services, and relro behavior must stay version-matched."
            ),
            image_actions="No image action should be generated for this route.",
            blockers="Java/native/resource ABI mismatch risk; cannot satisfy WebViewFactory/WebViewLibrary/sandbox/provider contracts by swapping libwebviewchromium.so alone",
            next_offline_gate="Keep this rejection in donor/design audits so it does not re-enter as a candidate.",
            next_live_gate="none",
            risk="BLACK",
        ),
    ]


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
    return lines


def write_tsv(path: Path, evidence: list[EvidenceRow], targets: list[RouteTarget]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "section",
                "id",
                "status",
                "class_or_evidence",
                "package_target",
                "partition_scope",
                "blockers",
                "next_offline_gate",
                "next_live_gate",
                "risk",
            ]
        )
        for row in evidence:
            writer.writerow(["evidence", row.gate, row.status, row.evidence, "", "", "", "", "", ""])
        for row in targets:
            writer.writerow(
                [
                    "route",
                    row.route_id,
                    row.status,
                    row.route_class,
                    row.package_target,
                    row.partition_scope,
                    row.blockers,
                    row.next_offline_gate,
                    row.next_live_gate,
                    row.risk,
                ]
            )


def write_markdown(path: Path, evidence: list[EvidenceRow], targets: list[RouteTarget]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    preferred = targets[0]
    lines: list[str] = []
    lines.append("# WebView Donor Target Matrix")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline route matrix. It does not download donors,")
    lines.append("build images, touch a device, flash, reboot, erase partitions, write")
    lines.append("settings, or modify `/data`.")
    lines.append("")
    lines.append("## Current Decision")
    lines.append("")
    lines.append(
        "The first real WebView modernization target remains Route A1: a source-built "
        "or adapted standalone `com.android.webview` provider under `/product/app/webview`. "
        "It is preferred because the R2 framework whitelists only `com.android.webview`, "
        "so it can avoid framework XML work if the package contract is preserved."
    )
    lines.append("")
    live_ready = evidence_status(evidence, "browser_webview_live_state_capture") == "PASS"
    v031_ready = evidence_status(evidence, "v0.31_live_provider_gate") == "PASS"
    donor_ready = evidence_status(evidence, "modern_donor_inbox") == "PASS"
    a_sig_ready = evidence_status(evidence, "a_sig_package_manager_gate") == "OFFLINE_PM_ACCEPTANCE_RECORDED"
    capacity_blocked = evidence_status(evidence, "route_a_image_capacity") == "BLOCKED_CAPACITY"
    space_source_status = evidence_status(evidence, "system_b_space_source_audit")
    space_source_selected_low_reserve = space_source_status == "SELECTED_LOW_RESERVE"
    space_source_recorded = space_source_status in {
        "RECORDED_PENDING_USER_SELECTION",
        "SELECTED_WITH_RESERVE",
        "SELECTED_LOW_RESERVE",
        "SELECTED_NOT_ENOUGH",
    }
    rom_ready = evidence_status(evidence, "rom_design_plan") == "PASS"
    if live_ready and v031_ready and donor_ready and a_sig_ready and capacity_blocked and space_source_selected_low_reserve:
        lines.append("The route has live-state proof, v0.31 stock provider proof,")
        lines.append("source-built WebView material, offline A-SIG PackageManager")
        lines.append("evidence, and the user-selected print-preserving system_b")
        lines.append("space source. The current full M150 product_b-only image remains")
        lines.append("blocked, and the next step is delete preflight plus extra")
        lines.append("reserve, a smaller WebView build, or explicit low-reserve layout")
        lines.append("acceptance.")
    elif live_ready and v031_ready and donor_ready and a_sig_ready and capacity_blocked and space_source_recorded:
        lines.append("The route has live-state proof, v0.31 stock provider proof,")
        lines.append("source-built WebView material, offline A-SIG PackageManager")
        lines.append("evidence, and a recorded system_b space-source audit. The current")
        lines.append("full M150 product_b-only image remains blocked, and the next step is")
        lines.append("user selection of the recorded space source or another layout/build-size")
        lines.append("path.")
    elif live_ready and v031_ready and donor_ready and a_sig_ready and capacity_blocked:
        lines.append("The route has live-state proof, v0.31 stock provider proof,")
        lines.append("source-built WebView material, and offline A-SIG PackageManager")
        lines.append("evidence. The current full M150 stock-carrier product_b-only image")
        lines.append("is now blocked by partition/native-library capacity, so the next")
        lines.append("offline step is a layout/build-size decision rather than a flashable")
        lines.append("candidate image.")
    elif live_ready and v031_ready and donor_ready and a_sig_ready:
        lines.append("The route now has live-state proof, v0.31 stock provider proof,")
        lines.append("source-built WebView material, and offline A-SIG PackageManager")
        lines.append("evidence. Route A1 is ready for candidate image design review,")
        lines.append("but not accepted for flashing until explicit ROM-image acceptance")
        lines.append("and post-flash live-device validation.")
    elif live_ready and v031_ready and donor_ready:
        lines.append("The route now has live-state proof, v0.31 stock provider proof,")
        lines.append("and source-built WebView material. It is still not image-ready")
        lines.append("because A-SIG review, explicit ROM-image acceptance,")
        lines.append("and post-flash live-device validation remain open.")
    elif live_ready:
        lines.append("The route is not build-ready yet because v0.31 live provider proof")
        lines.append("and actual modern donor/source-build material are still missing.")
        lines.append("The current Browser/WebView live-state baseline is already captured.")
    else:
        lines.append("The route is not build-ready yet because live-state capture, v0.31 live")
        lines.append("provider proof, and actual modern donor/source-build material are still")
        lines.append("missing.")
    if rom_ready:
        lines.append("The ROM design plan reports at least one design ready for review.")
    lines.append("")
    lines.append("## Evidence Gates")
    lines.append("")
    lines.extend(
        md_table(
            ["Gate", "Status", "Evidence", "Impact"],
            [[row.gate, row.status, row.evidence, row.impact] for row in evidence],
        )
    )
    lines.append("")
    lines.append("## Route Matrix")
    lines.append("")
    lines.extend(
        md_table(
            ["Route", "Status", "Class", "Package target", "Partition scope", "Risk"],
            [[row.route_id, row.status, row.route_class, row.package_target, row.partition_scope, row.risk] for row in targets],
        )
    )
    lines.append("")
    for row in targets:
        lines.append(f"## {row.route_id}")
        lines.append("")
        lines.extend(
            md_table(
                ["Field", "Value"],
                [
                    ["status", row.status],
                    ["class", row.route_class],
                    ["package target", row.package_target],
                    ["partition scope", row.partition_scope],
                    ["material needed", row.material_needed],
                    ["contract requirements", row.contract_requirements],
                    ["image actions", row.image_actions],
                    ["blockers", row.blockers],
                    ["next offline gate", row.next_offline_gate],
                    ["next live gate", row.next_live_gate],
                    ["risk", row.risk],
                ],
            )
        )
        lines.append("")
    lines.append("## Immediate Next Step")
    lines.append("")
    lines.append(f"- Current best offline step: {preferred.next_offline_gate}")
    lines.append(f"- Current best live step: {preferred.next_live_gate}")
    lines.append("- Do not build donor-backed WebView images from the current state.")
    lines.append("- Do not treat BrowserChrome or a native-library-only swap as a WebView provider route.")
    lines.append("")
    lines.append("## Source Reports")
    lines.append("")
    lines.append(f"- Framework contract: `{rel(FRAMEWORK_CONTRACT_MD)}`")
    lines.append(f"- Donor source plan: `{rel(SOURCE_PLAN_MD)}`")
    lines.append(f"- Integration plan: `{rel(INTEGRATION_MD)}`")
    lines.append(f"- ROM design plan: `{rel(ROM_DESIGN_MD)}`")
    lines.append(f"- Route A provider spec: `{rel(ROUTE_A_SPEC_MD)}`")
    lines.append(f"- Route A candidate audit: `{rel(ROUTE_A_CANDIDATE_MD)}`")
    lines.append(f"- System_b space source audit: `{rel(SPACE_SOURCE_MD)}`")
    lines.append(f"- Version-gap audit: `{rel(VERSION_GAP_MD)}`")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    evidence = collect_evidence()
    targets = build_targets(evidence)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(OUT_TSV, evidence, targets)
    write_markdown(OUT_MD, evidence, targets)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "source_reports": {
                    "framework_contract": rel(FRAMEWORK_CONTRACT_MD),
                    "donor_source_plan": rel(SOURCE_PLAN_MD),
                    "integration_plan": rel(INTEGRATION_MD),
                    "rom_design_plan": rel(ROM_DESIGN_MD),
                    "route_a_provider_spec": rel(ROUTE_A_SPEC_MD),
                    "route_a_candidate_audit": rel(ROUTE_A_CANDIDATE_MD),
                    "system_b_space_source_audit": rel(SPACE_SOURCE_MD),
                    "version_gap_audit": rel(VERSION_GAP_MD),
                },
                "current_best_next_offline_step": targets[0].next_offline_gate,
                "current_best_next_live_step": targets[0].next_live_gate,
                "evidence": [asdict(row) for row in evidence],
                "routes": [asdict(row) for row in targets],
                "summary": {
                    "preferred_route": targets[0].route_id,
                    "ready_route_count": sum(1 for row in targets if row.status in {"READY", "READY_FOR_DESIGN_REVIEW"}),
                    "rejected_route_count": sum(1 for row in targets if row.status == "REJECTED"),
                    "donor_backed_image_allowed": False,
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
    print(f"routes={len(targets)}")
    print(f"ready_routes={sum(1 for row in targets if row.status in {'READY', 'READY_FOR_DESIGN_REVIEW'})}")
    print(f"preferred={targets[0].route_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
