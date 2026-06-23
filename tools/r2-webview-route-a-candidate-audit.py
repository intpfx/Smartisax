#!/usr/bin/env python3
"""Audit a Route A WebView candidate against the Smartisax provider spec.

This helper is read-only. It runs the existing WebView donor audit and
Trichrome/static-library bundle audit on a future source-built or adapted
provider, then maps their evidence onto the Route A provider spec. It does not
download donors, build images, touch a device, flash, reboot, erase partitions,
write settings, or modify /data.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
STOCK_WEBVIEW_APK = KB / "raw" / "product" / "app" / "webview" / "webview.apk"
STOCK_WEBVIEW_SHA256 = "11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"
STOCK_WEBVIEW_VERSION_CODE = 377015630
STOCK_WEBVIEW_VERSION_NAME = "75.0.3770.156"

DONOR_AUDIT = ROOT / "tools" / "r2-webview-donor-audit.py"
BUNDLE_AUDIT = ROOT / "tools" / "r2-webview-trichrome-bundle-audit.py"
SPEC_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-provider-spec"
    / "webview-route-a-provider-spec.json"
)
SPEC_MD = ROOT / "docs" / "research" / "webview-route-a-provider-spec.md"
TARGET_MATRIX_MD = ROOT / "docs" / "research" / "webview-donor-target-matrix.md"

OUT_MD = ROOT / "docs" / "research" / "webview-route-a-candidate-audit.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-route-a-candidate-audit.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-route-a-candidate-audit"
OUT_JSON = OUT_DIR / "webview-route-a-candidate-audit.json"


@dataclass(frozen=True)
class RequirementResult:
    requirement_id: str
    level: str
    status: str
    observed: str
    requirement: str
    evidence: str
    impact: str


@dataclass(frozen=True)
class GateResult:
    gate_id: str
    status: str
    observed: str
    evidence: str
    blocks: str


@dataclass(frozen=True)
class InputSummary:
    input: str
    label: str
    donor_label: str
    bundle_label: str
    base_package: str
    base_apk: str
    version_name: str
    version_code: int | None
    base_sha256: str
    bundle_classification: str
    donor_verdict: str
    bundle_verdict: str


def die(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def sanitize_label(label: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-")
    return cleaned or "route-a-candidate"


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def run_child(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)


def run_subaudits(input_path: Path, label: str) -> tuple[dict, dict, str, str]:
    donor_label = f"route-a-candidate-{label}-donor"
    bundle_label = f"route-a-candidate-{label}-bundle"
    donor_result = run_child([str(DONOR_AUDIT), str(input_path), "--label", donor_label])
    bundle_result = run_child([str(BUNDLE_AUDIT), str(input_path), "--label", bundle_label])

    donor_json = ROOT / "hard-rom" / "inspect" / "browser-webview-donor" / donor_label / "webview-donor-audit.json"
    bundle_json = (
        ROOT
        / "hard-rom"
        / "inspect"
        / "browser-webview-trichrome-bundle"
        / bundle_label
        / "trichrome-bundle-audit.json"
    )
    donor = read_json(donor_json)
    bundle = read_json(bundle_json)
    if not donor:
        first = (donor_result.stderr or donor_result.stdout).strip().splitlines()[:1]
        die(f"donor audit did not produce JSON: {first[0] if first else rel(donor_json)}")
    if not bundle:
        first = (bundle_result.stderr or bundle_result.stdout).strip().splitlines()[:1]
        die(f"bundle audit did not produce JSON: {first[0] if first else rel(bundle_json)}")
    return donor, bundle, donor_label, bundle_label


def checks_by_gate(data: dict) -> dict[str, dict]:
    return {str(row.get("gate", "")): row for row in data.get("checks", []) if row.get("gate")}


def gate_status(data: dict, gate: str) -> str:
    return str(checks_by_gate(data).get(gate, {}).get("status", "MISSING"))


def gate_observed(data: dict, gate: str) -> str:
    return str(checks_by_gate(data).get(gate, {}).get("observed", "missing"))


def pass_gate(data: dict, gate: str) -> bool:
    return gate_status(data, gate) == "PASS"


def base_apk(donor: dict) -> dict:
    base_name = donor.get("base_apk")
    apks = donor.get("apks", [])
    for apk in apks:
        if apk.get("name") == base_name:
            return apk
    return apks[0] if apks else {}


def both_pass(donor: dict, bundle: dict, donor_gate: str, bundle_gate: str) -> tuple[str, str]:
    donor_status = gate_status(donor, donor_gate)
    bundle_status = gate_status(bundle, bundle_gate)
    status = "PASS" if donor_status == "PASS" and bundle_status == "PASS" else "FAIL"
    observed = f"{donor_gate}={donor_status}; {bundle_gate}={bundle_status}"
    return status, observed


def one_or_more_pass(data: dict, gates: list[str]) -> tuple[str, str]:
    statuses = [f"{gate}={gate_status(data, gate)}" for gate in gates]
    status = "PASS" if all(gate_status(data, gate) == "PASS" for gate in gates) else "FAIL"
    return status, "; ".join(statuses)


def candidate_modernity(apk: dict) -> tuple[str, str]:
    version_code = apk.get("version_code")
    version_name = str(apk.get("version_name", ""))
    sha256 = str(apk.get("sha256", ""))
    if sha256 == STOCK_WEBVIEW_SHA256:
        return "BASELINE_ONLY", f"sha256 matches stock WebView; version={version_name}/{version_code}"
    if isinstance(version_code, int) and version_code > STOCK_WEBVIEW_VERSION_CODE:
        return "PASS", f"version={version_name}/{version_code} > stock {STOCK_WEBVIEW_VERSION_NAME}/{STOCK_WEBVIEW_VERSION_CODE}"
    if version_name and version_name != STOCK_WEBVIEW_VERSION_NAME:
        return "WARN", f"versionName differs from stock but versionCode is not newer: {version_name}/{version_code}"
    return "BASELINE_ONLY", f"no newer-version evidence: {version_name}/{version_code}"


def evaluate_requirements(donor: dict, bundle: dict, spec: dict) -> list[RequirementResult]:
    apk = base_apk(donor)
    donor_json = (
        ROOT
        / "hard-rom"
        / "inspect"
        / "browser-webview-donor"
        / str(donor.get("label", "unknown"))
        / "webview-donor-audit.json"
    )
    bundle_json = (
        ROOT
        / "hard-rom"
        / "inspect"
        / "browser-webview-trichrome-bundle"
        / str(bundle.get("label", "unknown"))
        / "trichrome-bundle-audit.json"
    )

    requirements = {row.get("requirement_id"): row for row in spec.get("requirements", [])}

    def req(req_id: str, status: str, observed: str, evidence: str, impact: str = "") -> RequirementResult:
        item = requirements.get(req_id, {})
        return RequirementResult(
            requirement_id=req_id,
            level=str(item.get("level", "MUST")),
            status=status,
            observed=observed,
            requirement=str(item.get("requirement", req_id)),
            evidence=evidence,
            impact=impact or str(item.get("route_impact", "")),
        )

    results: list[RequirementResult] = []
    status, observed = both_pass(donor, bundle, "package_identity", "framework_provider_route")
    results.append(req("A-ID-01", status, observed, f"{rel(donor_json)}; {rel(bundle_json)}"))

    standalone = bundle.get("verdict") == "PASS_STANDALONE" and bundle.get("classification") == "standalone-webview"
    static_ok = pass_gate(bundle, "static_library_resolution")
    results.append(
        req(
            "A-ID-02",
            "PASS" if standalone and static_ok else "FAIL",
            f"verdict={bundle.get('verdict')}; classification={bundle.get('classification')}; static_library_resolution={gate_status(bundle, 'static_library_resolution')}",
            rel(bundle_json),
        )
    )

    status, observed = one_or_more_pass(donor, ["min_sdk_device_compat", "target_sdk_webviewupdater"])
    results.append(req("A-SDK-01", status, observed, rel(donor_json)))

    results.append(req("A-VER-01", gate_status(donor, "version_code_cohort"), gate_observed(donor, "version_code_cohort"), rel(donor_json)))

    metadata_ok = pass_gate(donor, "webview_library_metadata") and pass_gate(donor, "webview_native_library_present")
    bundle_lib_ok = pass_gate(bundle, "provider_webview_library")
    results.append(
        req(
            "A-MAN-01",
            "PASS" if metadata_ok and bundle_lib_ok else "FAIL",
            f"donor metadata={gate_status(donor, 'webview_library_metadata')}; donor native={gate_status(donor, 'webview_native_library_present')}; bundle library={gate_status(bundle, 'provider_webview_library')}",
            f"{rel(donor_json)}; {rel(bundle_json)}",
        )
    )

    status, observed = both_pass(donor, bundle, "android11_factory_provider_class", "android11_factory_provider_class")
    results.append(req("A-MAN-02", status, observed, f"{rel(donor_json)}; {rel(bundle_json)}"))

    results.append(
        req(
            "A-MAN-03",
            gate_status(donor, "sandbox_service_contract"),
            gate_observed(donor, "sandbox_service_contract"),
            rel(donor_json),
        )
    )

    status, observed = both_pass(donor, bundle, "arm64_runtime", "arm64_runtime_libs")
    results.append(req("A-ABI-01", status, observed, f"{rel(donor_json)}; {rel(bundle_json)}"))

    donor_arm32 = gate_status(donor, "arm32_app_compat")
    bundle_arm32 = gate_status(bundle, "arm32_compat_libs")
    if donor_arm32 == "PASS" and bundle_arm32 == "PASS":
        arm32_status = "PASS"
    elif donor_arm32 in {"PASS", "WARN"} and bundle_arm32 in {"PASS", "WARN"}:
        arm32_status = "WARN"
    else:
        arm32_status = "FAIL"
    results.append(req("A-ABI-02", arm32_status, f"donor={donor_arm32}; bundle={bundle_arm32}", f"{rel(donor_json)}; {rel(bundle_json)}"))

    modern_status, modern_observed = candidate_modernity(apk)
    results.append(
        RequirementResult(
            requirement_id="A-MOD-01",
            level="PROJECT_MUST",
            status=modern_status,
            observed=modern_observed,
            requirement="A real modernization candidate must differ from stock WebView and carry newer WebView/Chromium version evidence.",
            evidence=rel(donor_json),
            impact="Stock WebView can validate the Route A shape, but it is not a modernization payload.",
        )
    )

    deferred = [
        ("A-CACHE-01", "DEFERRED_IMAGE_GATE", "package directory mtime is checked by the future ROM image verifier"),
        ("A-CACHE-02", "DEFERRED_IMAGE_GATE", "oat/vdex policy is checked by the future ROM image verifier"),
        ("A-SIG-01", "DEFERRED_ADAPTATION_GATE", "source-built same-package signing/certificate-carrier transition is checked before image design"),
        ("A-ROM-01", "RECORDED_BASELINE", "Browser/WebView live-state capture and v0.31 live proof exist; future donor image still needs candidate-specific image gates"),
        ("A-ROM-02", "DEFERRED_IMAGE_GATE", "shared-block-safe product_b replacement is checked by the future image verifier"),
        ("A-LIVE-01", "RECORDED_BASELINE", "current Browser/WebView live-state and v0.31 live verifier are recorded; rerun after any donor-backed flash"),
        ("A-LIVE-02", "FUTURE_LIVE_GATE", "post-boot donor verification cannot run in this offline candidate audit"),
        ("A-REJ-01", "PASS", "candidate audit explicitly requires donor/bundle Route A gates and rejects non-WebView/lib-only shortcuts"),
    ]
    for req_id, status, observed in deferred:
        results.append(req(req_id, status, observed, rel(SPEC_JSON)))

    return results


def evaluate_gates(requirements: list[RequirementResult], donor: dict, bundle: dict) -> list[GateResult]:
    must_failures = [row.requirement_id for row in requirements if row.level in {"MUST", "PROJECT_MUST"} and row.status == "FAIL"]
    baseline = any(row.requirement_id == "A-MOD-01" and row.status == "BASELINE_ONLY" for row in requirements)
    donor_ok = donor.get("verdict") == "PASS"
    bundle_ok = bundle.get("verdict") == "PASS_STANDALONE"
    shape_ok = not must_failures and donor_ok and bundle_ok
    return [
        GateResult(
            "A-GATE-01",
            "PASS" if donor and bundle else "FAIL",
            f"donor_verdict={donor.get('verdict')}; bundle_verdict={bundle.get('verdict')}",
            "donor and bundle audit JSON",
            "candidate intake",
        ),
        GateResult(
            "A-GATE-02",
            "PASS" if shape_ok else "FAIL",
            f"must_failures={','.join(must_failures) if must_failures else 'none'}; baseline_only={baseline}",
            "Route A mapped requirements",
            "ROM image design",
        ),
        GateResult(
            "A-GATE-03",
            "BLOCKED_BASELINE_ONLY" if baseline else "BLOCKED_PENDING_INTEGRATION_PLAN",
            "candidate is stock baseline only" if baseline else "run integration/ROM design plans after a real modern candidate audit",
            "integration and ROM design plans",
            "ROM builder implementation",
        ),
        GateResult(
            "A-GATE-04",
            "RECORDED_BASELINE",
            "Browser/WebView live-state capture and v0.31 live provider proof are recorded; rerun after a future donor-backed image",
            rel(SPEC_JSON),
            "future donor-backed image live acceptance",
        ),
    ]


def overall_verdict(requirements: list[RequirementResult], donor: dict, bundle: dict) -> str:
    if donor.get("verdict") == "FAIL" or str(bundle.get("verdict", "")).startswith("FAIL"):
        return "FAIL"
    if any(row.level in {"MUST", "PROJECT_MUST"} and row.status == "FAIL" for row in requirements):
        return "FAIL"
    if any(row.requirement_id == "A-MOD-01" and row.status == "BASELINE_ONLY" for row in requirements):
        return "BASELINE_SHAPE_PASS_NOT_MODERN"
    if any(row.status == "WARN" for row in requirements):
        return "CANDIDATE_SHAPE_WARN_BLOCKED_BY_LIVE"
    return "CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE"


def input_summary(input_path: Path, label: str, donor_label: str, bundle_label: str, donor: dict, bundle: dict) -> InputSummary:
    apk = base_apk(donor)
    return InputSummary(
        input=rel(input_path.resolve()),
        label=label,
        donor_label=donor_label,
        bundle_label=bundle_label,
        base_package=str(apk.get("package", "")),
        base_apk=str(donor.get("base_apk", "")),
        version_name=str(apk.get("version_name", "")),
        version_code=apk.get("version_code") if isinstance(apk.get("version_code"), int) else None,
        base_sha256=str(apk.get("sha256", "")),
        bundle_classification=str(bundle.get("classification", "")),
        donor_verdict=str(donor.get("verdict", "")),
        bundle_verdict=str(bundle.get("verdict", "")),
    )


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|") for cell in row) + " |")
    return lines


def write_tsv(path: Path, summary: InputSummary, verdict: str, requirements: list[RequirementResult], gates: list[GateResult]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "level", "status", "observed", "requirement", "evidence", "impact"])
        writer.writerow(["summary", summary.label, "", verdict, summary.input, summary.base_package, summary.base_sha256, summary.bundle_classification])
        for row in requirements:
            writer.writerow(["requirement", row.requirement_id, row.level, row.status, row.observed, row.requirement, row.evidence, row.impact])
        for row in gates:
            writer.writerow(["gate", row.gate_id, "", row.status, row.observed, row.blocks, row.evidence, ""])


def write_markdown(path: Path, summary: InputSummary, verdict: str, requirements: list[RequirementResult], gates: list[GateResult]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView Route A Candidate Audit")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline candidate intake audit. It does not")
    lines.append("download donors, build images, touch a device, flash, reboot, erase")
    lines.append("partitions, write settings, or modify `/data`.")
    lines.append("")
    lines.append(f"Verdict: **{verdict}**")
    lines.append("")
    if verdict == "BASELINE_SHAPE_PASS_NOT_MODERN":
        lines.append("The input validates the Route A provider shape, but it is the stock")
        lines.append("M75 WebView baseline and is not a modernization payload.")
    elif verdict.endswith("BLOCKED_BY_LIVE"):
        lines.append("The input passes the offline Route A shape gate, but donor-backed")
        lines.append("image work is still blocked by live-state and v0.31 live proof.")
    elif verdict == "FAIL":
        lines.append("The input does not satisfy the Route A candidate gate.")
    lines.append("")
    lines.append("## Input")
    lines.append("")
    lines.extend(
        md_table(
            ["Field", "Value"],
            [
                ["input", summary.input],
                ["label", summary.label],
                ["base package", summary.base_package],
                ["base APK", summary.base_apk],
                ["version", f"{summary.version_name} / {summary.version_code}"],
                ["base sha256", summary.base_sha256],
                ["donor verdict", summary.donor_verdict],
                ["bundle verdict", summary.bundle_verdict],
                ["bundle classification", summary.bundle_classification],
            ],
        )
    )
    lines.append("")
    lines.append("## Requirement Mapping")
    lines.append("")
    lines.extend(
        md_table(
            ["ID", "Level", "Status", "Observed", "Evidence"],
            [[row.requirement_id, row.level, row.status, row.observed, row.evidence] for row in requirements],
        )
    )
    lines.append("")
    lines.append("## Gate Mapping")
    lines.append("")
    lines.extend(
        md_table(
            ["Gate", "Status", "Observed", "Blocks"],
            [[row.gate_id, row.status, row.observed, row.blocks] for row in gates],
        )
    )
    lines.append("")
    lines.append("## Source Reports")
    lines.append("")
    lines.append(f"- Route A provider spec: `{rel(SPEC_MD)}`")
    lines.append(f"- Target matrix: `{rel(TARGET_MATRIX_MD)}`")
    lines.append(f"- Donor audit JSON: `hard-rom/inspect/browser-webview-donor/{summary.donor_label}/webview-donor-audit.json`")
    lines.append(
        f"- Bundle audit JSON: `hard-rom/inspect/browser-webview-trichrome-bundle/{summary.bundle_label}/trichrome-bundle-audit.json`"
    )
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
    parser.add_argument(
        "input",
        nargs="?",
        type=Path,
        default=STOCK_WEBVIEW_APK,
        help="APK, APKM/APKS/XAPK/ZIP, or directory. Defaults to stock WebView as a baseline self-test.",
    )
    parser.add_argument("--label", help="Output label. Defaults to input stem, or stock-webview-route-a-baseline.")
    args = parser.parse_args()

    if not DONOR_AUDIT.exists():
        die(f"missing donor audit script at {rel(DONOR_AUDIT)}")
    if not BUNDLE_AUDIT.exists():
        die(f"missing bundle audit script at {rel(BUNDLE_AUDIT)}")
    if not SPEC_JSON.exists():
        die(f"missing Route A provider spec JSON at {rel(SPEC_JSON)}")
    if not args.input.exists():
        die(f"input not found: {args.input}")

    default_stock = args.input.resolve() == STOCK_WEBVIEW_APK.resolve()
    label = sanitize_label(args.label or ("stock-webview-route-a-baseline" if default_stock else args.input.stem))
    donor, bundle, donor_label, bundle_label = run_subaudits(args.input, label)
    spec = read_json(SPEC_JSON)
    requirements = evaluate_requirements(donor, bundle, spec)
    gates = evaluate_gates(requirements, donor, bundle)
    verdict = overall_verdict(requirements, donor, bundle)
    summary = input_summary(args.input, label, donor_label, bundle_label, donor, bundle)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(OUT_TSV, summary, verdict, requirements, gates)
    write_markdown(OUT_MD, summary, verdict, requirements, gates)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "verdict": verdict,
                "summary": asdict(summary),
                "requirements": [asdict(row) for row in requirements],
                "gates": [asdict(row) for row in gates],
                "source_reports": {
                    "route_a_provider_spec": rel(SPEC_MD),
                    "target_matrix": rel(TARGET_MATRIX_MD),
                    "donor_audit_json": f"hard-rom/inspect/browser-webview-donor/{donor_label}/webview-donor-audit.json",
                    "bundle_audit_json": f"hard-rom/inspect/browser-webview-trichrome-bundle/{bundle_label}/trichrome-bundle-audit.json",
                },
                "donor_backed_image_allowed": False,
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"verdict={verdict}")
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    print(f"donor_json=hard-rom/inspect/browser-webview-donor/{donor_label}/webview-donor-audit.json")
    print(f"bundle_json=hard-rom/inspect/browser-webview-trichrome-bundle/{bundle_label}/trichrome-bundle-audit.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
