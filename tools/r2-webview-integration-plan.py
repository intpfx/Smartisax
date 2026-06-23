#!/usr/bin/env python3
"""Generate the Smartisax WebView donor integration plan.

This helper is read-only. It consumes existing donor, Trichrome bundle, inbox,
and v0.31 gate reports. It does not download donors, build images, touch a
device, flash, reboot, erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_MD = ROOT / "docs" / "research" / "webview-integration-plan.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-integration-plan.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-integration-plan"
OUT_JSON = OUT_DIR / "webview-integration-plan.json"

DONOR_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-donor"
BUNDLE_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-trichrome-bundle"
INBOX_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-inbox" / "webview-donor-inbox-audit.json"
SOURCE_PLAN_MD = ROOT / "docs" / "research" / "webview-donor-source-plan.md"
FRAMEWORK_CONTRACT_MD = ROOT / "docs" / "research" / "webview-framework-contract-audit.md"
FRAMEWORK_CONTRACT_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-framework-contract"
    / "webview-framework-contract-audit.json"
)
A_SIG_PM_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-a-sig-package-manager"
    / "webview-a-sig-package-manager-audit.json"
)
A_SIG_PM_MD = ROOT / "docs" / "research" / "webview-a-sig-package-manager-audit.md"
V031_DIR = ROOT / "hard-rom" / "inspect" / "v0.31-webview-stock-near-noop"
LIVE_STATE_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-live-state"

STOCK_DONOR_LABEL = "stock-webview-selftest"
STOCK_BUNDLE_LABEL = "stock-webview-standalone"
STOCK_WEBVIEW_PACKAGE = "com.android.webview"
GOOGLE_WEBVIEW_PREFIX = "com.google.android.webview"


@dataclass(frozen=True)
class Evidence:
    gate: str
    status: str
    evidence: str
    next_step: str


@dataclass(frozen=True)
class CandidatePlan:
    label: str
    source: str
    package: str
    version: str
    donor_verdict: str
    bundle_verdict: str
    bundle_classification: str
    route: str
    build_readiness: str
    blockers: list[str]
    required_rom_design: list[str]
    next_gates: list[str]
    donor_report: str
    bundle_report: str


@dataclass(frozen=True)
class PlanRow:
    section: str
    item: str
    status: str
    evidence: str
    next_step: str


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


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def latest_matching(pattern: str) -> Path | None:
    matches = [Path(path) for path in glob.glob(pattern)]
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def report_has_pass(path: Path | None) -> bool:
    if path is None:
        return False
    text = read_text(path)
    return "PASS" in text and "FAIL" not in text.splitlines()[:8]


def framework_contract_status() -> tuple[str, str]:
    data = read_json(FRAMEWORK_CONTRACT_JSON)
    if not data:
        return "MISSING", "framework contract audit JSON missing"
    failures = [row for row in data.get("rows", []) if str(row.get("status", "")) == "FAIL"]
    if failures:
        gates = ", ".join(str(row.get("gate", "unknown")) for row in failures)
        return "FAIL", f"contract FAIL gates={gates}; report={rel(FRAMEWORK_CONTRACT_MD)}"
    return "PASS", rel(FRAMEWORK_CONTRACT_MD)


def donor_json_path(label: str) -> Path:
    return DONOR_ROOT / label / "webview-donor-audit.json"


def bundle_json_path(label: str) -> Path:
    return BUNDLE_ROOT / label / "trichrome-bundle-audit.json"


def donor_md_path(label: str) -> Path:
    return DONOR_ROOT / label / "webview-donor-audit.md"


def bundle_md_path(label: str) -> Path:
    return BUNDLE_ROOT / label / "trichrome-bundle-audit.md"


def base_apk(donor: dict) -> dict:
    base_name = str(donor.get("base_apk", ""))
    apks = donor.get("apks", [])
    for apk in apks:
        if apk.get("name") == base_name:
            return apk
    return apks[0] if apks else {}


def gate_failures(data: dict, *, fail_only: bool) -> list[str]:
    out = []
    bad = {"FAIL"} if fail_only else {"FAIL", "WARN"}
    for row in data.get("checks", []):
        status = str(row.get("status", ""))
        if status in bad:
            out.append(f"{row.get('gate', 'unknown')}: {status} ({row.get('observed', '')})")
    return out


def evidence_state() -> list[Evidence]:
    v031_offline = latest_matching(str(V031_DIR / "verify-v0.31-webview-stock-near-noop-offline-image-*.txt"))
    v031_device = latest_matching(str(V031_DIR / "verify-v0.31-webview-stock-near-noop-device-*.txt"))
    live_state = latest_matching(str(LIVE_STATE_DIR / "browser-webview-live-state-*.txt"))
    inbox = read_json(INBOX_JSON)
    a_sig_pm = read_json(A_SIG_PM_JSON)
    candidate_count = len(inbox.get("candidates", []))
    contract_status, contract_evidence = framework_contract_status()
    a_sig_status = str(a_sig_pm.get("a_sig_01_status", "MISSING"))
    a_sig_next = (
        "Use the stock-carrier candidate only as a system-partition cert carrier, then prove it on-device with PackageManager/WebViewUpdateService logs."
        if a_sig_status == "OFFLINE_PM_ACCEPTANCE_RECORDED"
        else "Run tools/r2-webview-a-sig-package-manager-audit.py before any donor-backed ROM image design."
    )

    live_state_pass = bool(live_state and "result=DEVICE_NOT_AVAILABLE" not in read_text(live_state))
    live_state_next = (
        "Keep this as the current pre-v0.31 Browser/WebView baseline and rerun it after v0.31 or donor-backed flashes."
        if live_state_pass
        else "Run tools/r2-browser-webview-live-state-audit.sh on a booted, unlocked device before v0.31 flash/live verification."
    )
    v031_live_pass = report_has_pass(v031_device)
    donor_next = (
        "Modern source-built/donor material is present; review donor/bundle audit rows and signing evidence before ROM image design."
        if candidate_count > 0
        else "Place a stable donor APK/APKM/APKS/XAPK under apks/webview-donor-inbox/ and rerun tools/r2-webview-donor-inbox-audit.py --include-downloads."
    )

    return [
        Evidence(
            "framework_contract_audit",
            contract_status,
            contract_evidence,
            "Run tools/r2-webview-framework-contract-audit.py after framework/source changes and before donor-backed ROM design.",
        ),
        Evidence(
            "v0.31_offline_provider_gate",
            "PASS" if report_has_pass(v031_offline) else "MISSING",
            rel(v031_offline) if v031_offline else "no offline v0.31 PASS report found",
            "Keep this as the stock WebView product_b mtime-only image gate.",
        ),
        Evidence(
            "browser_webview_live_state_capture",
            "PASS" if live_state_pass else "MISSING",
            rel(live_state) if live_state else "no live-state capture report found",
            live_state_next,
        ),
        Evidence(
            "v0.31_live_provider_gate",
            "PASS" if v031_live_pass else "MISSING",
            rel(v031_device) if v031_device else "no device v0.31 verifier PASS report found",
            "Keep this as the stock provider live proof before donor-backed images."
            if v031_live_pass
            else "Flash v0.31 only after explicit confirmation, then run tools/r2-verify-v0.31-webview-stock-near-noop.sh --read-only.",
        ),
        Evidence(
            "modern_donor_inbox",
            "PASS" if candidate_count > 0 else "MISSING",
            f"candidate_count={candidate_count}; report={rel(INBOX_JSON)}" if INBOX_JSON.exists() else "inbox report missing",
            donor_next,
        ),
        Evidence(
            "a_sig_package_manager_gate",
            a_sig_status,
            f"verdict={a_sig_pm.get('verdict', 'MISSING')}; report={rel(A_SIG_PM_MD)}"
            if A_SIG_PM_JSON.exists()
            else "A-SIG PackageManager audit missing",
            a_sig_next,
        ),
    ]


def route_for(package: str, classification: str, donor_verdict: str, bundle_verdict: str) -> str:
    if donor_verdict == "FAIL" or bundle_verdict == "FAIL":
        return "REJECT"
    if not package:
        return "NO_PROVIDER"
    if classification == "trichrome-static-library-bundle":
        return "ROUTE_C_TRICHROME_MULTI_PACKAGE"
    if package == STOCK_WEBVIEW_PACKAGE and classification == "standalone-webview":
        return "ROUTE_A_ADAPT_IN_PLACE"
    if package.startswith(GOOGLE_WEBVIEW_PREFIX):
        return "ROUTE_B_FRAMEWORK_PROVIDER_ADD"
    if classification.startswith("multi-package"):
        return "ROUTE_C_MULTI_PACKAGE"
    return "ROUTE_UNKNOWN_REQUIRES_MANUAL_REVIEW"


def plan_for_candidate(label: str, donor_label: str, bundle_label: str, source: str, evidence: list[Evidence]) -> CandidatePlan:
    donor_path = donor_json_path(donor_label)
    bundle_path = bundle_json_path(bundle_label)
    donor = read_json(donor_path)
    bundle = read_json(bundle_path)
    base = base_apk(donor)
    package = str(base.get("package", ""))
    version = f"{base.get('version_name', 'unknown')} / {base.get('version_code', 'unknown')}"
    donor_verdict = str(donor.get("verdict", "MISSING"))
    bundle_verdict = str(bundle.get("verdict", "MISSING"))
    classification = str(bundle.get("classification", "missing"))
    route = route_for(package, classification, donor_verdict, bundle_verdict)

    blockers: list[str] = []
    blockers.extend(gate_failures(donor, fail_only=False))
    blockers.extend(gate_failures(bundle, fail_only=False))
    if any(item.status != "PASS" for item in evidence if item.gate == "framework_contract_audit"):
        blockers.append("framework contract audit is not PASS")
    if any(item.status != "PASS" for item in evidence if item.gate == "browser_webview_live_state_capture"):
        blockers.append("browser/WebView live-state capture is not proven")
    if any(item.status != "PASS" for item in evidence if item.gate == "v0.31_live_provider_gate"):
        blockers.append("v0.31 stock WebView live provider gate is not proven")
    if source == "stock-baseline":
        blockers.append("stock baseline is only a shape/reference candidate, not a modern donor")
    if route == "ROUTE_B_FRAMEWORK_PROVIDER_ADD":
        blockers.append("framework-res config_webview_packages.xml patch and framework resource live gate are required")
    if route.startswith("ROUTE_C"):
        blockers.append("multi-package ROM layout and static-library install resolution must be designed before image build")
    if route == "ROUTE_A_ADAPT_IN_PLACE" and not any(
        item.gate == "a_sig_package_manager_gate" and item.status == "OFFLINE_PM_ACCEPTANCE_RECORDED"
        for item in evidence
    ):
        blockers.append("A-SIG PackageManager stock-carrier acceptance is not recorded")
    if route == "REJECT":
        blockers.append("donor or bundle audit has hard FAIL gates")
    if donor_verdict == "MISSING" or bundle_verdict == "MISSING":
        blockers.append("missing donor or bundle audit JSON")

    required_rom_design = [
        "satisfy the R2 framework contract audit before image design",
        "start from live-verified v0.31, not directly from stock v0.29",
        "preserve provider Java/native/resources/splits as one version-matched set",
        "bump every changed package directory mtime so PackageCacher reparses",
        "remove or regenerate stale oat/vdex for changed provider packages",
        "verify relro, cmd webviewupdate, Settings WebView selector, Big Bang/WebView surfaces, resolver, keyguard, and launcher after boot",
    ]
    if route == "ROUTE_A_ADAPT_IN_PLACE":
        required_rom_design.insert(1, "replace /product/app/webview as com.android.webview under product_b")
    elif route == "ROUTE_B_FRAMEWORK_PROVIDER_ADD":
        required_rom_design.insert(1, "add provider package as a ROM app and patch framework-res config_webview_packages.xml")
    elif route.startswith("ROUTE_C"):
        required_rom_design.insert(1, "ship provider plus Trichrome/static-library package(s) as a product/system multi-package set")

    live_state_pass = any(item.gate == "browser_webview_live_state_capture" and item.status == "PASS" for item in evidence)
    v031_live_pass = any(item.gate == "v0.31_live_provider_gate" and item.status == "PASS" for item in evidence)
    next_gates = [
        "keep the current Browser/WebView live-state PASS as the pre-v0.31 baseline"
        if live_state_pass
        else "run live-state capture on current v0.29 before v0.31 flash",
        "keep the v0.31 stock WebView near-noop live proof as the product_b provider gate"
        if v031_live_pass
        else "live-verify v0.31 stock WebView near-noop after explicit confirmation",
        "rerun donor and Trichrome bundle audits on the actual stable donor material",
        "generate a donor-specific image design only after all audit FAIL gates and the A-SIG PackageManager gate are resolved",
    ]
    if route == "ROUTE_B_FRAMEWORK_PROVIDER_ADD":
        next_gates.append("prepare a separate framework-provider-add no-op gate before behavior image work")
    if route.startswith("ROUTE_C"):
        next_gates.append("install-plan audit for provider/static-library packages, versions, certDigest evidence, and package paths")

    build_readiness = "NOT_BUILD_READY" if blockers else "READY_FOR_OFFLINE_IMAGE_DESIGN"
    return CandidatePlan(
        label=label,
        source=source,
        package=package or "unknown",
        version=version,
        donor_verdict=donor_verdict,
        bundle_verdict=bundle_verdict,
        bundle_classification=classification,
        route=route,
        build_readiness=build_readiness,
        blockers=blockers,
        required_rom_design=required_rom_design,
        next_gates=next_gates,
        donor_report=rel(donor_md_path(donor_label)) if donor_md_path(donor_label).exists() else rel(donor_path),
        bundle_report=rel(bundle_md_path(bundle_label)) if bundle_md_path(bundle_label).exists() else rel(bundle_path),
    )


def inbox_plans(evidence: list[Evidence]) -> list[CandidatePlan]:
    inbox = read_json(INBOX_JSON)
    plans = []
    for audit in inbox.get("audits", []):
        label = str(audit.get("label", ""))
        if not label:
            continue
        plans.append(plan_for_candidate(label, label, label, "inbox", evidence))
    return plans


def build_plan_rows(evidence: list[Evidence], candidates: list[CandidatePlan]) -> list[PlanRow]:
    rows = [
        PlanRow("gate", item.gate, item.status, item.evidence, item.next_step)
        for item in evidence
    ]
    for candidate in candidates:
        rows.append(
            PlanRow(
                "candidate",
                candidate.label,
                candidate.build_readiness,
                f"{candidate.route}; package={candidate.package}; donor={candidate.donor_verdict}; bundle={candidate.bundle_verdict}/{candidate.bundle_classification}",
                "; ".join(candidate.next_gates),
            )
        )
        for blocker in candidate.blockers:
            rows.append(PlanRow("blocker", candidate.label, "BLOCKED", blocker, "Resolve before ROM image design."))
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
            fieldnames=["section", "item", "status", "evidence", "next_step"],
            lineterminator="\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def write_markdown(path: Path, evidence: list[Evidence], candidates: list[CandidatePlan], rows: list[PlanRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView Integration Plan")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline planning report. It does not download donors,")
    lines.append("build images, touch a device, flash, reboot, erase partitions, write")
    lines.append("settings, or modify `/data`.")
    lines.append("")
    lines.append("## Current Gate State")
    lines.append("")
    lines.extend(md_table(["Gate", "Status", "Evidence", "Next step"], [[e.gate, e.status, e.evidence, e.next_step] for e in evidence]))
    lines.append("")
    lines.append("## Candidate Plans")
    lines.append("")
    if not candidates:
        lines.append("No external donor candidate is available from the current inbox report.")
        lines.append("")
    else:
        lines.extend(
            md_table(
                ["Candidate", "Source", "Package", "Version", "Route", "Readiness", "Reports"],
                [
                    [
                        c.label,
                        c.source,
                        c.package,
                        c.version,
                        c.route,
                        c.build_readiness,
                        f"donor: `{c.donor_report}`; bundle: `{c.bundle_report}`",
                    ]
                    for c in candidates
                ],
            )
        )
        lines.append("")
        for candidate in candidates:
            lines.append(f"### {candidate.label}")
            lines.append("")
            lines.append("Required ROM design:")
            for item in candidate.required_rom_design:
                lines.append(f"- {item}")
            lines.append("")
            lines.append("Blockers:")
            if candidate.blockers:
                for blocker in candidate.blockers:
                    lines.append(f"- {blocker}")
            else:
                lines.append("- none")
            lines.append("")
            lines.append("Next gates:")
            for gate in candidate.next_gates:
                lines.append(f"- {gate}")
            lines.append("")
    lines.append("## Route Boundary")
    lines.append("")
    lines.append("- Route A is adapt-in-place for `com.android.webview` under `/product/app/webview` after v0.31 live proof.")
    lines.append("- Route B is `com.google.android.webview` via framework-provider-add; it needs a separate framework config gate.")
    lines.append("- Route C is Trichrome/static-library multi-package; it is never a single APK replacement.")
    lines.append("- BrowserChrome remains a separate browser no-op gate and must not be treated as a WebView provider donor.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--donor-label", help="Donor audit label under hard-rom/inspect/browser-webview-donor.")
    parser.add_argument("--bundle-label", help="Bundle audit label under hard-rom/inspect/browser-webview-trichrome-bundle.")
    parser.add_argument("--label", help="Plan label for the explicit donor/bundle pair.")
    parser.add_argument(
        "--skip-stock-baseline",
        action="store_true",
        help="Do not include the stock WebView self-test as a reference candidate.",
    )
    args = parser.parse_args()

    evidence = evidence_state()
    candidates: list[CandidatePlan] = []
    if not args.skip_stock_baseline:
        candidates.append(plan_for_candidate("stock-webview-baseline", STOCK_DONOR_LABEL, STOCK_BUNDLE_LABEL, "stock-baseline", evidence))
    if args.donor_label:
        bundle_label = args.bundle_label or args.donor_label
        candidates.append(plan_for_candidate(args.label or args.donor_label, args.donor_label, bundle_label, "explicit", evidence))
    candidates.extend(inbox_plans(evidence))

    rows = build_plan_rows(evidence, candidates)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(OUT_TSV, rows)
    write_markdown(OUT_MD, evidence, candidates, rows)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "source_plan": rel(SOURCE_PLAN_MD),
                "framework_contract": rel(FRAMEWORK_CONTRACT_MD),
                "evidence": [asdict(item) for item in evidence],
                "candidates": [asdict(candidate) for candidate in candidates],
                "rows": [asdict(row) for row in rows],
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
    print(f"candidates={len(candidates)}")
    print(f"build_ready={sum(1 for candidate in candidates if candidate.build_readiness == 'READY_FOR_OFFLINE_IMAGE_DESIGN')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
