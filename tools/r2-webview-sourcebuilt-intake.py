#!/usr/bin/env python3
"""Intake a returned source-built SystemWebView.apk.

This is the local Mac-side handoff after an isolated Linux builder returns a
`SystemWebView.apk` dist directory. It copies the artifact into the donor inbox,
records signing shape, produces a stock-cert-carrier adapted APK, and runs the
Route A audits. It does not touch a device, flash, reboot, erase partitions,
build images, write settings, or modify `/data`.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INBOX_ROOT = ROOT / "apks" / "webview-donor-inbox"
OUT_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-sourcebuilt-intake"
STOCK_WEBVIEW_APK = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "raw" / "product" / "app" / "webview" / "webview.apk"

SIGNING_PLAN = ROOT / "tools" / "r2-webview-signing-transition-plan.py"
CARRIER_ADAPT = ROOT / "tools" / "r2-apk-v2-carrier-adapt.py"
A_SIG_PM_AUDIT = ROOT / "tools" / "r2-webview-a-sig-package-manager-audit.py"
CANDIDATE_AUDIT = ROOT / "tools" / "r2-webview-route-a-candidate-audit.py"
INTEGRATION_PLAN = ROOT / "tools" / "r2-webview-integration-plan.py"
ROM_DESIGN_PLAN = ROOT / "tools" / "r2-webview-rom-design-plan.py"
TARGET_MATRIX = ROOT / "tools" / "r2-webview-donor-target-matrix.py"
SIGCHECK = ROOT / "tools" / "r2-apk-signature-boundary-check.sh"
SOURCE_BUILD_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-source-build-readiness"
    / "webview-source-build-readiness-plan.json"
)

EXPECTED_GN_ARGS = [
    'target_os = "android"',
    'target_cpu = "arm64"',
    "is_debug = false",
    "is_official_build = true",
    "disable_fieldtrial_testing_config = true",
    "is_component_build = false",
    "is_chrome_branded = false",
    "use_official_google_api_keys = false",
    'android_channel = "stable"',
    'system_webview_package_name = "com.android.webview"',
]

DIST_REQUIRED_FILES = [
    "SystemWebView.apk",
    "artifact-manifest.json",
    "SHA256SUMS.txt",
    "args.gn",
    "chromium-revision.txt",
    "gn-args-expanded.txt",
]


@dataclass(frozen=True)
class IntakeStep:
    step_id: str
    status: str
    command: str
    evidence: str
    blocks: str


@dataclass(frozen=True)
class DistProvenance:
    status: str
    input_path: str
    evidence: str
    findings: list[str]
    details: dict[str, object]


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def sanitize_label(label: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-")
    return cleaned or "sourcebuilt-system-webview"


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def source_build_expected() -> dict[str, str]:
    data = read_json(SOURCE_BUILD_JSON)
    release = data.get("stable_release") or {}
    version = str(release.get("version") or "150.0.7871.28")
    return {
        "version": version,
        "checkout_revision": str(release.get("checkout_revision") or release.get("tag_ref") or f"refs/tags/{version}"),
        "chromium_hash": str(release.get("chromium_hash") or ""),
        "package_target": "com.android.webview",
        "artifact_kind": "sourcebuilt_system_webview",
        "gn_target": "system_webview_apk",
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_sha256s(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        sha, name = parts
        out[name.lstrip("*").strip()] = sha.lower()
    return out


def validate_dist_provenance(input_path: Path | None) -> DistProvenance:
    if input_path is None:
        return DistProvenance(
            "READY_SPEC",
            "<returned SystemWebView.apk or dist>",
            "source-built dist provenance validation is specified for future input",
            [],
            {"required_files": DIST_REQUIRED_FILES, "expected_gn_args": EXPECTED_GN_ARGS},
        )
    if input_path.is_file():
        return DistProvenance(
            "WARN_FILE_INPUT",
            rel(input_path),
            "single APK input has no builder manifest, SHA256SUMS, GN args, or Chromium revision metadata",
            [
                "full source-built provenance cannot be verified from a lone APK; prefer the Linux builder dist directory",
            ],
            {"required_files": DIST_REQUIRED_FILES, "file_input_allowed_for_manual_audit": True},
        )

    expected = source_build_expected()
    findings: list[str] = []
    details: dict[str, object] = {
        "expected": expected,
        "required_files": DIST_REQUIRED_FILES,
        "expected_gn_args": EXPECTED_GN_ARGS,
    }

    missing = [name for name in DIST_REQUIRED_FILES if not (input_path / name).is_file()]
    if missing:
        findings.append(f"missing required dist file(s): {', '.join(missing)}")
        return DistProvenance("FAIL", rel(input_path), "missing dist provenance files", findings, details)

    manifest_path = input_path / "artifact-manifest.json"
    manifest = read_json(manifest_path)
    details["manifest"] = manifest
    for key, expected_value in [
        ("artifact_kind", expected["artifact_kind"]),
        ("version", expected["version"]),
        ("package_target", expected["package_target"]),
        ("apk", "SystemWebView.apk"),
    ]:
        actual = manifest.get(key)
        if actual != expected_value:
            findings.append(f"artifact-manifest.json {key}={actual!r}, expected {expected_value!r}")
    if manifest.get("generated_on_builder") is not True:
        findings.append("artifact-manifest.json generated_on_builder is not true")
    if manifest.get("gn_target") not in (None, expected["gn_target"]):
        findings.append(f"artifact-manifest.json gn_target={manifest.get('gn_target')!r}, expected {expected['gn_target']!r}")

    revision = (input_path / "chromium-revision.txt").read_text(encoding="utf-8", errors="replace").strip()
    details["chromium_revision"] = revision
    expected_hash = expected["chromium_hash"]
    if expected_hash and revision != expected_hash:
        findings.append(f"chromium-revision.txt={revision!r}, expected {expected_hash!r}")
    manifest_revision = manifest.get("chromium_revision")
    if manifest_revision not in (None, revision):
        findings.append(f"artifact-manifest.json chromium_revision={manifest_revision!r}, expected {revision!r}")

    args_lines = {
        line.strip()
        for line in (input_path / "args.gn").read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip() and not line.strip().startswith("#")
    }
    missing_args = [line for line in EXPECTED_GN_ARGS if line not in args_lines]
    if missing_args:
        findings.append(f"args.gn missing expected line(s): {', '.join(missing_args)}")

    expanded = (input_path / "gn-args-expanded.txt").read_text(encoding="utf-8", errors="replace")
    for marker in ["system_webview_package_name", "target_cpu"]:
        if marker not in expanded:
            findings.append(f"gn-args-expanded.txt missing marker {marker!r}")

    sha_entries = parse_sha256s(input_path / "SHA256SUMS.txt")
    details["sha256sum_entries"] = sorted(sha_entries)
    for name in ["SystemWebView.apk", "args.gn", "chromium-revision.txt", "gn-args-expanded.txt"]:
        recorded = sha_entries.get(name)
        if not recorded:
            findings.append(f"SHA256SUMS.txt missing {name}")
            continue
        actual = sha256_file(input_path / name)
        if actual != recorded:
            findings.append(f"SHA256SUMS.txt mismatch for {name}: recorded {recorded}, actual {actual}")

    files = manifest.get("files")
    if isinstance(files, list):
        for name in ["SystemWebView.apk", "args.gn", "chromium-revision.txt", "gn-args-expanded.txt", "SHA256SUMS.txt"]:
            if name not in files:
                findings.append(f"artifact-manifest.json files[] missing {name}")

    status = "FAIL" if findings else "PASS"
    evidence = "source-built dist provenance verified" if status == "PASS" else "source-built dist provenance failed"
    return DistProvenance(status, rel(input_path), evidence, findings, details)


def write_provenance_report(inspect_dir: Path, provenance: DistProvenance) -> tuple[Path, Path]:
    inspect_dir.mkdir(parents=True, exist_ok=True)
    out_json = inspect_dir / "sourcebuilt-dist-provenance.json"
    out_md = inspect_dir / "sourcebuilt-dist-provenance.md"
    out_json.write_text(json.dumps(asdict(provenance), ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    lines = [
        "# WebView Source-Built Dist Provenance",
        "",
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        f"Status: `{provenance.status}`",
        f"Input: `{provenance.input_path}`",
        f"Evidence: {provenance.evidence}",
        "",
        "## Findings",
        "",
    ]
    if provenance.findings:
        lines.extend(f"- {item}" for item in provenance.findings)
    else:
        lines.append("- none")
    lines.extend(
        [
            "",
            "## Boundary",
            "",
            "This gate verifies the returned Linux-builder dist metadata only. It does",
            "not prove Android PackageManager acceptance, WebViewUpdateService behavior,",
            "or ROM image safety.",
            "",
        ]
    )
    out_md.write_text("\n".join(lines), encoding="utf-8")
    return out_json, out_md


def discover_apk(input_path: Path) -> Path:
    if input_path.is_file():
        return input_path
    direct = input_path / "SystemWebView.apk"
    if direct.exists():
        return direct
    matches = sorted(input_path.rglob("SystemWebView.apk"))
    if matches:
        return matches[0]
    raise SystemExit(f"error: SystemWebView.apk not found under {input_path}")


def default_label(input_path: Path) -> str:
    manifest = read_json(input_path / "artifact-manifest.json") if input_path.is_dir() else {}
    version = str(manifest.get("version") or "")
    if version:
        return sanitize_label(f"sourcebuilt-system-webview-{version}")
    return sanitize_label(input_path.stem)


def run(cmd: list[str], log_path: Path | None = None, allow_failure: bool = False) -> tuple[int, str]:
    result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    text = result.stdout
    if result.stderr:
        text += "\n# stderr\n" + result.stderr
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(text, encoding="utf-8")
    if result.returncode != 0 and not allow_failure:
        raise SystemExit(f"error: command failed ({result.returncode}): {' '.join(cmd)}\n{ text[:2000] }")
    return result.returncode, text


def copy_input(input_path: Path, apk_path: Path, inbox_dir: Path) -> Path:
    inbox_dir.mkdir(parents=True, exist_ok=True)
    if input_path.is_dir():
        dist_dir = inbox_dir / "dist"
        if dist_dir.exists():
            shutil.rmtree(dist_dir)
        shutil.copytree(input_path, dist_dir)
    else:
        dist_dir = inbox_dir / "dist"
        dist_dir.mkdir(exist_ok=True)
        shutil.copy2(input_path, dist_dir / input_path.name)
    target_apk = inbox_dir / "SystemWebView.apk"
    shutil.copy2(apk_path, target_apk)
    return target_apk


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|").replace("\n", " ") for cell in row) + " |")
    return lines


def write_reports(
    label: str,
    dry_run: bool,
    inbox_dir: Path,
    inspect_dir: Path,
    steps: list[IntakeStep],
    verdict: str | None = None,
    extra_outputs: dict[str, str] | None = None,
) -> None:
    inspect_dir.mkdir(parents=True, exist_ok=True)
    out_md = inspect_dir / "sourcebuilt-intake.md"
    out_tsv = inspect_dir / "sourcebuilt-intake.tsv"
    out_json = inspect_dir / "sourcebuilt-intake.json"

    lines: list[str] = []
    lines.append("# WebView Source-Built Intake")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append(f"Label: `{label}`")
    lines.append(f"Dry run: `{str(dry_run).lower()}`")
    lines.append("")
    lines.append("This report covers local Mac-side intake only. It does not touch a device,")
    lines.append("flash, reboot, erase partitions, build images, write settings, or modify")
    lines.append("`/data`.")
    lines.append("")
    lines.append("## Paths")
    lines.append("")
    lines.extend(md_table(["Item", "Path"], [["inbox", rel(inbox_dir)], ["inspect", rel(inspect_dir)]]))
    lines.append("")
    lines.append("## Steps")
    lines.append("")
    lines.extend(md_table(["Step", "Status", "Command", "Evidence", "Blocks"], [[row.step_id, row.status, row.command, row.evidence, row.blocks] for row in steps]))
    lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("A returned APK does not authorize a ROM image by itself. Route A remains")
    lines.append("behind candidate audit, stock-cert-carrier adaptation evidence, ROM design,")
    lines.append("offline image verification, and explicit live-device confirmation.")
    lines.append("")
    out_md.write_text("\n".join(lines), encoding="utf-8")

    with out_tsv.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["step", "status", "command", "evidence", "blocks"])
        for row in steps:
            writer.writerow([row.step_id, row.status, row.command, row.evidence, row.blocks])

    outputs = {
        "markdown": rel(out_md),
        "tsv": rel(out_tsv),
        "json": rel(out_json),
    }
    if extra_outputs:
        outputs.update(extra_outputs)

    out_json.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "label": label,
                "dry_run": dry_run,
                "verdict": verdict or ("DRY_RUN_READY" if dry_run else "INTAKE_RAN_REVIEW_OUTPUTS"),
                "donor_backed_image_allowed": False,
                "inbox_dir": rel(inbox_dir),
                "inspect_dir": rel(inspect_dir),
                "steps": [asdict(row) for row in steps],
                "outputs": outputs,
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def dry_run_steps(label: str, input_path: Path | None, inbox_dir: Path, inspect_dir: Path) -> list[IntakeStep]:
    candidate = rel(input_path) if input_path else "<returned SystemWebView.apk or dist>"
    adapted = inbox_dir / "SystemWebView-stock-carrier.apk"
    return [
        IntakeStep(
            "INTAKE-00",
            "READY_SPEC",
            "validate artifact-manifest.json, SHA256SUMS.txt, args.gn, chromium-revision.txt, and gn-args-expanded.txt",
            rel(inspect_dir / "sourcebuilt-dist-provenance.json"),
            "candidate copy",
        ),
        IntakeStep("INTAKE-01", "READY_SPEC", f"copy {candidate} -> {rel(inbox_dir)}", rel(inbox_dir), "candidate audit"),
        IntakeStep("INTAKE-02", "READY_SPEC", f"{rel(SIGNING_PLAN)} --candidate {rel(inbox_dir / 'SystemWebView.apk')}", rel(inspect_dir), "carrier adaptation"),
        IntakeStep(
            "INTAKE-03",
            "READY_SPEC",
            f"{rel(CARRIER_ADAPT)} --stock {rel(STOCK_WEBVIEW_APK)} --candidate {rel(inbox_dir / 'SystemWebView.apk')} --strip-existing-candidate --out {rel(adapted)}",
            rel(adapted),
            "adapted candidate audit",
        ),
        IntakeStep("INTAKE-04", "READY_SPEC", f"{rel(SIGCHECK)} {rel(adapted)}", rel(inspect_dir / "SystemWebView-stock-carrier.signature.txt"), "A-SIG review"),
        IntakeStep("INTAKE-04-a-sig-package-manager", "READY_SPEC", rel(A_SIG_PM_AUDIT), rel(inspect_dir / "a-sig-package-manager.log"), "candidate audit"),
        IntakeStep("INTAKE-05", "READY_SPEC", f"{rel(CANDIDATE_AUDIT)} {rel(inbox_dir / 'SystemWebView.apk')} --label {label}-original", rel(inspect_dir), "comparison"),
        IntakeStep("INTAKE-06", "READY_SPEC", f"{rel(CANDIDATE_AUDIT)} {rel(adapted)} --label {label}-stock-carrier", rel(inspect_dir), "integration plan"),
        IntakeStep("INTAKE-07-integration-plan", "READY_SPEC", rel(INTEGRATION_PLAN), rel(inspect_dir), "ROM image design review"),
        IntakeStep("INTAKE-07-rom-design-plan", "READY_SPEC", rel(ROM_DESIGN_PLAN), rel(inspect_dir), "ROM image design review"),
        IntakeStep("INTAKE-07-target-matrix", "READY_SPEC", rel(TARGET_MATRIX), rel(inspect_dir), "ROM image design review"),
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", type=Path, help="Returned Linux builder dist directory or SystemWebView.apk.")
    parser.add_argument("--label", help="Stable label for inbox/audit outputs.")
    parser.add_argument("--dry-run", action="store_true", help="Write the intake plan without copying or running sub-audits.")
    parser.add_argument("--validate-only", action="store_true", help="Validate a returned builder dist and write provenance reports only.")
    args = parser.parse_args()

    input_path = args.input.resolve() if args.input else None
    label = sanitize_label(args.label or (default_label(input_path) if input_path else "sourcebuilt-system-webview"))
    inbox_dir = INBOX_ROOT / label
    inspect_dir = OUT_ROOT / label

    if args.dry_run:
        steps = dry_run_steps(label, input_path, inbox_dir, inspect_dir)
        write_reports(label, True, inbox_dir, inspect_dir, steps)
        print("verdict=DRY_RUN_READY")
        print(f"inspect={rel(inspect_dir)}")
        print(f"inbox={rel(inbox_dir)}")
        return 0

    if input_path is None:
        raise SystemExit("error: input dist directory or APK is required unless --dry-run is used")

    provenance = validate_dist_provenance(input_path)
    provenance_json, provenance_md = write_provenance_report(inspect_dir, provenance)
    steps: list[IntakeStep] = [
        IntakeStep(
            "INTAKE-00",
            provenance.status,
            "validate source-built dist provenance",
            rel(provenance_json),
            "candidate copy",
        )
    ]
    if args.validate_only:
        verdict = f"VALIDATE_ONLY_{provenance.status}"
        write_reports(
            label,
            False,
            inbox_dir,
            inspect_dir,
            steps,
            verdict=verdict,
            extra_outputs={"provenance_json": rel(provenance_json), "provenance_markdown": rel(provenance_md)},
        )
        print(f"verdict={verdict}")
        print(f"provenance={rel(provenance_json)}")
        return 0 if provenance.status != "FAIL" else 1
    if provenance.status == "FAIL":
        write_reports(
            label,
            False,
            inbox_dir,
            inspect_dir,
            steps,
            verdict="INTAKE_BLOCKED_PROVENANCE_FAIL",
            extra_outputs={"provenance_json": rel(provenance_json), "provenance_markdown": rel(provenance_md)},
        )
        raise SystemExit(f"error: source-built dist provenance failed; see {rel(provenance_json)}")

    apk_path = discover_apk(input_path)
    copied_apk = copy_input(input_path, apk_path, inbox_dir)
    adapted_apk = inbox_dir / "SystemWebView-stock-carrier.apk"

    steps.append(IntakeStep("INTAKE-01", "PASS", f"copy {input_path} -> {inbox_dir}", rel(copied_apk), "signing transition"))

    code, _ = run([str(SIGNING_PLAN), "--candidate", str(copied_apk)], inspect_dir / "signing-transition.log")
    steps.append(IntakeStep("INTAKE-02", f"PASS_EXIT_{code}", f"{rel(SIGNING_PLAN)} --candidate {rel(copied_apk)}", rel(inspect_dir / "signing-transition.log"), "carrier adaptation"))

    code, _ = run(
        [
            str(CARRIER_ADAPT),
            "--stock",
            str(STOCK_WEBVIEW_APK),
            "--candidate",
            str(copied_apk),
            "--strip-existing-candidate",
            "--out",
            str(adapted_apk),
        ],
        inspect_dir / "carrier-adapt.log",
    )
    steps.append(IntakeStep("INTAKE-03", f"PASS_EXIT_{code}", f"{rel(CARRIER_ADAPT)} --stock ... --candidate {rel(copied_apk)} --strip-existing-candidate --out {rel(adapted_apk)}", rel(inspect_dir / "carrier-adapt.log"), "adapted candidate audit"))

    code, _ = run([str(SIGCHECK), str(adapted_apk)], inspect_dir / "SystemWebView-stock-carrier.signature.txt", allow_failure=True)
    steps.append(IntakeStep("INTAKE-04", f"EXIT_{code}", f"{rel(SIGCHECK)} {rel(adapted_apk)}", rel(inspect_dir / "SystemWebView-stock-carrier.signature.txt"), "A-SIG review"))

    code, _ = run([str(A_SIG_PM_AUDIT)], inspect_dir / "a-sig-package-manager.log")
    steps.append(IntakeStep("INTAKE-04-a-sig-package-manager", f"PASS_EXIT_{code}", rel(A_SIG_PM_AUDIT), rel(inspect_dir / "a-sig-package-manager.log"), "candidate audit"))

    code, _ = run([str(CANDIDATE_AUDIT), str(copied_apk), "--label", f"{label}-original"], inspect_dir / "candidate-audit-original.log")
    steps.append(IntakeStep("INTAKE-05", f"PASS_EXIT_{code}", f"{rel(CANDIDATE_AUDIT)} {rel(copied_apk)} --label {label}-original", rel(inspect_dir / "candidate-audit-original.log"), "comparison"))

    code, _ = run([str(CANDIDATE_AUDIT), str(adapted_apk), "--label", f"{label}-stock-carrier"], inspect_dir / "candidate-audit-stock-carrier.log")
    steps.append(IntakeStep("INTAKE-06", f"PASS_EXIT_{code}", f"{rel(CANDIDATE_AUDIT)} {rel(adapted_apk)} --label {label}-stock-carrier", rel(inspect_dir / "candidate-audit-stock-carrier.log"), "integration plan"))

    for tool, name in [(INTEGRATION_PLAN, "integration-plan"), (ROM_DESIGN_PLAN, "rom-design-plan"), (TARGET_MATRIX, "target-matrix")]:
        code, _ = run([str(tool)], inspect_dir / f"{name}.log")
        steps.append(IntakeStep(f"INTAKE-07-{name}", f"PASS_EXIT_{code}", rel(tool), rel(inspect_dir / f"{name}.log"), "ROM image design review"))

    write_reports(
        label,
        False,
        inbox_dir,
        inspect_dir,
        steps,
        extra_outputs={"provenance_json": rel(provenance_json), "provenance_markdown": rel(provenance_md)},
    )
    print("verdict=INTAKE_RAN_REVIEW_OUTPUTS")
    print(f"inbox={rel(inbox_dir)}")
    print(f"adapted_apk={rel(adapted_apk)}")
    print(f"inspect={rel(inspect_dir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
