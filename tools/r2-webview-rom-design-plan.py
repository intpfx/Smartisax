#!/usr/bin/env python3
"""Generate the Smartisax WebView donor-to-ROM design plan.

This helper is read-only. It consumes existing WebView donor, Trichrome bundle,
inbox, integration-plan, and live-state reports. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write settings,
or modify /data.
"""

from __future__ import annotations

import csv
import glob
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_MD = ROOT / "docs" / "research" / "webview-rom-design-plan.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-rom-design-plan.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-rom-design-plan"
OUT_JSON = OUT_DIR / "webview-rom-design-plan.json"

INTEGRATION_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-integration-plan" / "webview-integration-plan.json"
DONOR_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-donor"
BUNDLE_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-trichrome-bundle"
LIVE_STATE_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-live-state"
V031_DIR = ROOT / "hard-rom" / "inspect" / "v0.31-webview-stock-near-noop"
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

STOCK_PRODUCT_WEBVIEW_DIR = "/product/app/webview"
STOCK_PRODUCT_WEBVIEW_APK = "/product/app/webview/webview.apk"
STOCK_PRODUCT_WEBVIEW_IMAGE_DIR = "/app/webview"
STOCK_PRODUCT_WEBVIEW_IMAGE_APK = "/app/webview/webview.apk"


@dataclass(frozen=True)
class EvidenceRow:
    gate: str
    status: str
    evidence: str
    impact: str


@dataclass(frozen=True)
class DesignRow:
    candidate: str
    route: str
    status: str
    partition_scope: str
    rom_actions: str
    filesystem_actions: str
    package_cache_actions: str
    verification_gates: str
    blockers: str


@dataclass(frozen=True)
class PlanRow:
    section: str
    item: str
    status: str
    detail: str
    next_step: str


def rel(path: Path | None) -> str:
    if path is None:
        return ""
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


def read_text(path: Path | None) -> str:
    if path is None or not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def latest_matching(pattern: str) -> Path | None:
    matches = [Path(path) for path in glob.glob(pattern)]
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def donor_json_path(label: str) -> Path:
    return DONOR_ROOT / label / "webview-donor-audit.json"


def bundle_json_path(label: str) -> Path:
    return BUNDLE_ROOT / label / "trichrome-bundle-audit.json"


def base_apk(data: dict) -> dict:
    base_name = str(data.get("base_apk", ""))
    apks = data.get("apks", [])
    for apk in apks:
        if apk.get("name") == base_name:
            return apk
    return apks[0] if apks else {}


def package_names(data: dict) -> list[str]:
    packages = data.get("packages")
    if isinstance(packages, dict):
        return sorted(packages)
    names = {str(apk.get("package", "")) for apk in data.get("apks", []) if apk.get("package")}
    return sorted(names)


def static_library_summary(bundle: dict) -> str:
    refs: list[str] = []
    provides: list[str] = []
    for apk in bundle.get("apks", []):
        owner = apk.get("package", "unknown")
        for ref in apk.get("uses_static_libraries", []):
            name = ref.get("name", "")
            version = ref.get("version")
            required = ref.get("required", "")
            refs.append(f"{owner} uses {name}@{version} required={required}")
        for provide in apk.get("static_libraries", []):
            name = provide.get("name", "")
            version = provide.get("version")
            provides.append(f"{owner} provides {name}@{version}")
    parts = []
    if refs:
        parts.append("refs: " + "; ".join(refs))
    if provides:
        parts.append("provides: " + "; ".join(provides))
    return " | ".join(parts) if parts else "no static-library refs/provides"


def route_design(candidate: dict, donor: dict, bundle: dict) -> DesignRow:
    label = str(candidate.get("label", "unknown"))
    route = str(candidate.get("route", "UNKNOWN"))
    readiness = str(candidate.get("build_readiness", "NOT_BUILD_READY"))
    package = str(candidate.get("package", "unknown"))
    classification = str(candidate.get("bundle_classification", "missing"))
    donor_verdict = str(candidate.get("donor_verdict", "MISSING"))
    bundle_verdict = str(candidate.get("bundle_verdict", "MISSING"))
    blockers = list(candidate.get("blockers", []))
    capacity = read_json(CAPACITY_JSON)
    product_b_capacity_blocked = (
        route == "ROUTE_A_ADAPT_IN_PLACE"
        and str(capacity.get("verdict", "")) == "PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY"
    )
    base = base_apk(donor)
    apk_count = len(donor.get("apks", [])) or len(bundle.get("apks", []))
    packages = package_names(bundle) or package_names(donor) or ([package] if package else [])
    static_summary = static_library_summary(bundle)

    verification = [
        "offline donor audit PASS",
        "offline bundle audit PASS/PASS_STANDALONE",
        "v0.31 live-state capture PASS",
        "v0.31 live provider gate PASS",
        "post-boot cmd webviewupdate and dumpsys webviewupdate",
        "Settings WebView selector",
        "Big Bang/WebView surfaces",
        "browser resolver",
        "keyguard and launcher",
    ]

    if route == "ROUTE_A_ADAPT_IN_PLACE":
        partition_scope = "product_b only for the first donor-backed image if no framework/provider config changes are needed"
        rom_actions = (
            f"replace {STOCK_PRODUCT_WEBVIEW_DIR} as package {package}; keep public base path "
            f"{STOCK_PRODUCT_WEBVIEW_APK} for the first gate; preserve all version-matched splits/native libs/resources"
        )
        filesystem = (
            f"write package cluster under image path {STOCK_PRODUCT_WEBVIEW_IMAGE_DIR}; restore uid/gid/mode/SELinux; "
            "e2fsck -fy then -fn; dump every installed APK and verify sha256/unzip"
        )
        cache = (
            f"bump {STOCK_PRODUCT_WEBVIEW_DIR} directory mtime beyond live package_cache; remove/regenerate stale oat/vdex "
            "inside the provider package directory if present; do not clear /data package_cache without explicit approval"
        )
    elif route == "ROUTE_B_FRAMEWORK_PROVIDER_ADD":
        partition_scope = "product_b for provider package plus system_b/framework work for config_webview_packages.xml"
        rom_actions = (
            f"add provider package {package} as a ROM app and patch framework-res config_webview_packages.xml; "
            "prepare a separate framework provider no-op/live gate before behavior image work"
        )
        filesystem = (
            "ship provider as a complete cluster with base/splits/native libs; preserve framework resource IDs; verify "
            "framework-res signature boundary and sparse system_b/product_b slices"
        )
        cache = (
            "bump provider package directory mtime and framework package/resource mtimes as applicable; remove stale oat/vdex "
            "for changed provider; expect PackageManager/WebViewUpdateService reparse"
        )
        verification.append("framework provider XML no-op/live gate")
    elif route.startswith("ROUTE_C"):
        partition_scope = "multi-package product_b/system_b design, plus framework provider add if package is not adapted to com.android.webview"
        rom_actions = (
            "ship provider plus every required Trichrome/static-library package as one version-matched set; "
            f"packages={', '.join(packages) or 'unknown'}; {static_summary}"
        )
        filesystem = (
            "one package directory per package; exactly one base APK per package; keep split names/version set together; "
            "verify static-library provider package is installed before WebView provider is accepted"
        )
        cache = (
            "bump every changed package directory mtime; remove/regenerate stale oat/vdex for provider and library packages; "
            "do not rely on single-APK replacement"
        )
        verification.extend(["static shared-library resolution", "signer/certDigest evidence or explicit accepted warning"])
    elif route == "REJECT":
        partition_scope = "none"
        rom_actions = "do not build from this candidate"
        filesystem = "none"
        cache = "none"
    else:
        partition_scope = "manual review required"
        rom_actions = f"unknown route for package={package} classification={classification} apk_count={apk_count}"
        filesystem = "manual image design required"
        cache = "manual cache/oat/vdex plan required"

    if readiness != "READY_FOR_OFFLINE_IMAGE_DESIGN" and not blockers:
        blockers.append("candidate is not marked build-ready by integration plan")
    if product_b_capacity_blocked:
        blockers.append(
            "current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit"
        )
    if donor_verdict == "MISSING" or bundle_verdict == "MISSING":
        blockers.append("missing donor or bundle audit JSON")

    if product_b_capacity_blocked and readiness == "READY_FOR_OFFLINE_IMAGE_DESIGN":
        status = "BLOCKED_CAPACITY"
    else:
        status = "DESIGN_ONLY" if readiness != "READY_FOR_OFFLINE_IMAGE_DESIGN" else "READY_FOR_DESIGN_REVIEW"
    return DesignRow(
        candidate=label,
        route=route,
        status=status,
        partition_scope=partition_scope,
        rom_actions=rom_actions,
        filesystem_actions=filesystem,
        package_cache_actions=cache,
        verification_gates="; ".join(verification),
        blockers="; ".join(blockers) if blockers else "none",
    )


def evidence_rows(integration: dict) -> list[EvidenceRow]:
    rows = []
    for item in integration.get("evidence", []):
        gate = str(item.get("gate", "unknown"))
        status = str(item.get("status", "unknown"))
        evidence = str(item.get("evidence", ""))
        if gate == "modern_donor_inbox" and status == "PASS":
            impact = "modern source-built/donor material is present; candidate-specific signing and live gates still control design promotion"
        elif gate == "a_sig_package_manager_gate" and status == "OFFLINE_PM_ACCEPTANCE_RECORDED":
            impact = "stock-carrier system-scan PackageManager acceptance is recorded offline; live proof is still required"
        elif status == "PASS":
            impact = "unblocks the corresponding design precondition"
        elif gate == "browser_webview_live_state_capture":
            impact = "blocks v0.31 flash/live-provider proof and all donor-backed image design until adb live capture succeeds"
        elif gate == "v0.31_live_provider_gate":
            impact = "blocks donor-backed WebView image design"
        elif gate == "modern_donor_inbox":
            impact = "blocks modern WebView upgrade candidate selection"
        else:
            impact = "required evidence is missing or incomplete"
        rows.append(EvidenceRow(gate, status, evidence, impact))

    latest_live = latest_matching(str(LIVE_STATE_DIR / "browser-webview-live-state-*.txt"))
    latest_live_text = read_text(latest_live)
    if latest_live and "result=DEVICE_NOT_AVAILABLE" in latest_live_text:
        rows.append(
            EvidenceRow(
                "latest_live_state_attempt",
                "DEVICE_NOT_AVAILABLE",
                rel(latest_live),
                "USB/MTP may be visible, but adb was not online for live-state capture",
            )
        )

    latest_v031 = latest_matching(str(V031_DIR / "verify-v0.31-webview-stock-near-noop-offline-image-*.txt"))
    if latest_v031:
        rows.append(
            EvidenceRow(
                "latest_v0.31_offline_report",
                "RECORDED",
                rel(latest_v031),
                "stock provider near-noop image remains offline-only until live flash/verification",
            )
        )
    capacity = read_json(CAPACITY_JSON)
    if capacity:
        candidate = capacity.get("candidate", {})
        product = capacity.get("product", {})
        rows.append(
            EvidenceRow(
                "route_a_image_capacity",
                str(capacity.get("verdict", "UNKNOWN")),
                (
                    f"candidate_apk={candidate.get('file_size', 'unknown')}; "
                    f"product_free={product.get('free_bytes', 'unknown')}; "
                    f"report={rel(CAPACITY_MD)}"
                ),
                "blocks the current product_b-only Route A image even though donor shape and A-SIG evidence are ready",
            )
        )
    space_source = read_json(SPACE_SOURCE_JSON)
    if space_source:
        recommended = space_source.get("recommended_source_id", "unknown")
        preferred_extra = space_source.get("preferred_extra_source_id", "none")
        preferred = next(
            (
                item
                for item in space_source.get("sources", [])
                if item.get("source_id") == recommended
            ),
            {},
        )
        extra = next(
            (
                item
                for item in space_source.get("sources", [])
                if item.get("source_id") == preferred_extra
            ),
            {},
        )
        rows.append(
            EvidenceRow(
                "system_b_space_source_audit",
                str(space_source.get("verdict", "UNKNOWN")),
                (
                    f"recommended={recommended}; "
                    f"allocated={preferred.get('allocated_bytes', 'unknown')}; "
                    f"margin_to_reserved_target={preferred.get('margin_to_reserved_target', 'unknown')}; "
                    f"preferred_extra={preferred_extra}; "
                    f"extra_allocated={extra.get('allocated_bytes', 'unknown')}; "
                    f"extra_margin_to_reserved_target={extra.get('margin_to_reserved_target', 'unknown')}; "
                    f"report={rel(SPACE_SOURCE_MD)}"
                ),
                "records the selected system_b space source plus the current preferred extra source for a full-ABI layout; user selection and reserve/layout acceptance still gate image work",
            )
        )
    return rows


def build_rows(evidence: list[EvidenceRow], designs: list[DesignRow]) -> list[PlanRow]:
    rows: list[PlanRow] = []
    for item in evidence:
        rows.append(PlanRow("evidence", item.gate, item.status, item.evidence, item.impact))
    for item in designs:
        rows.append(PlanRow("design", item.candidate, item.status, f"{item.route}: {item.partition_scope}", item.blockers))
        rows.append(PlanRow("rom_action", item.candidate, item.status, item.rom_actions, item.verification_gates))
    return rows


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
    return lines


def write_tsv(path: Path, rows: list[PlanRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            delimiter="\t",
            fieldnames=["section", "item", "status", "detail", "next_step"],
            lineterminator="\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def write_markdown(path: Path, evidence: list[EvidenceRow], designs: list[DesignRow], rows: list[PlanRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView ROM Design Plan")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline planning report. It does not download donors,")
    lines.append("build images, touch a device, flash, reboot, erase partitions, write")
    lines.append("settings, or modify `/data`.")
    lines.append("")
    lines.append("## Evidence State")
    lines.append("")
    lines.extend(md_table(["Gate", "Status", "Evidence", "Impact"], [[e.gate, e.status, e.evidence, e.impact] for e in evidence]))
    lines.append("")
    lines.append("## Candidate ROM Designs")
    lines.append("")
    lines.extend(
        md_table(
            ["Candidate", "Route", "Status", "Partition scope", "ROM actions", "Blockers"],
            [[d.candidate, d.route, d.status, d.partition_scope, d.rom_actions, d.blockers] for d in designs],
        )
    )
    lines.append("")
    for design in designs:
        lines.append(f"### {design.candidate}")
        lines.append("")
        lines.append(f"- Route: `{design.route}`")
        lines.append(f"- Status: `{design.status}`")
        lines.append(f"- Partition scope: {design.partition_scope}")
        lines.append(f"- Filesystem actions: {design.filesystem_actions}")
        lines.append(f"- Package/cache actions: {design.package_cache_actions}")
        lines.append(f"- Verification gates: {design.verification_gates}")
        lines.append(f"- Blockers: {design.blockers}")
        lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("- This report is not build authorization. It translates audited donor shapes into ROM design requirements.")
    lines.append("- Stock WebView remains a shape/reference candidate, not a modern donor.")
    capacity_blocked = any(
        item.gate == "route_a_image_capacity"
        and item.status == "PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY"
        for item in evidence
    )
    if capacity_blocked:
        lines.append("- The current full M150 stock-carrier candidate is blocked as a product_b-only image by partition/native-library capacity; choose a smaller build, a reviewed external-native-library layout, or an explicitly accepted 64-bit-only probe before image construction.")
    space_source_status = next(
        (
            item.status
            for item in evidence
            if item.gate == "system_b_space_source_audit"
        ),
        "",
    )
    if space_source_status == "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_LOW_RESERVE":
        lines.append("- The system_b space-source audit now records user_selected_no_projection_print_preserving: TNT/projection and Android printing are preserved, the bare WebView full-ABI shortfall is covered, and the remaining blocker is reserve/layout acceptance plus package delete preflights. The audit also records SmartisanWallpapers as the current preferred extra-space candidate.")
    elif space_source_status == "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_COVERS_RESERVE":
        lines.append("- The system_b space-source audit records a user-selected no-projection source that covers the WebView full-ABI shortfall plus reserve; deletion still needs package preflights and explicit image acceptance.")
    elif space_source_status:
        lines.append("- A system_b space-source audit exists, but no donor-backed image is authorized until its package deletion and reserve/layout gates are resolved.")
    live_state_ready = any(item.gate == "browser_webview_live_state_capture" and item.status == "PASS" for item in evidence)
    v031_ready = any(item.gate == "v0.31_live_provider_gate" and item.status == "PASS" for item in evidence)
    donor_ready = any(item.gate == "modern_donor_inbox" and item.status == "PASS" for item in evidence)
    if live_state_ready and v031_ready and donor_ready:
        a_sig_ready = any(item.gate == "a_sig_package_manager_gate" and item.status == "OFFLINE_PM_ACCEPTANCE_RECORDED" for item in evidence)
        if a_sig_ready:
            lines.append("- Live-state, v0.31 stock provider proof, modern source-built material, and offline A-SIG PackageManager evidence are present; donor-backed image work still needs explicit ROM-image acceptance and live proof.")
        else:
            lines.append("- Live-state, v0.31 stock provider proof, and modern source-built material are present; donor-backed image work is still blocked by A-SIG review and explicit ROM-image acceptance.")
    elif live_state_ready:
        lines.append("- Current Browser/WebView live-state capture is PASS; donor-backed image work remains blocked until v0.31 proof and modern donor/source-build material are both present.")
    else:
        lines.append("- A donor-backed image remains blocked until live-state capture, v0.31 live provider proof, and real donor/source-build material are available.")
    lines.append("- Trichrome/static-library donors are multi-package ROM designs, never single APK replacements.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    integration = read_json(INTEGRATION_JSON)
    evidence = evidence_rows(integration)
    designs = []
    for candidate in integration.get("candidates", []):
        donor_label = str(candidate.get("label", ""))
        if candidate.get("source") == "stock-baseline":
            donor_label = "stock-webview-selftest"
            bundle_label = "stock-webview-standalone"
        else:
            bundle_label = donor_label
        donor = read_json(donor_json_path(donor_label))
        bundle = read_json(bundle_json_path(bundle_label))
        designs.append(route_design(candidate, donor, bundle))

    rows = build_rows(evidence, designs)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(OUT_TSV, rows)
    write_markdown(OUT_MD, evidence, designs, rows)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "integration_plan": rel(INTEGRATION_JSON),
                "evidence": [asdict(item) for item in evidence],
                "designs": [asdict(item) for item in designs],
                "rows": [asdict(row) for row in rows],
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    ready = sum(1 for design in designs if design.status == "READY_FOR_DESIGN_REVIEW")
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    print(f"designs={len(designs)}")
    print(f"ready_for_design_review={ready}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
