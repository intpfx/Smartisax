#!/usr/bin/env python3
"""Generate the WebView same-package signing transition plan.

This helper is read-only. It turns the current Route A WebView blocker
(`A-SIG-01`) into concrete offline evidence, transition routes, and gates for a
future source-built `com.android.webview` candidate. It does not download
donors, build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import struct
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
STOCK_WEBVIEW_APK = KB / "raw" / "product" / "app" / "webview" / "webview.apk"
STOCK_WEBVIEW_SHA256 = "11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"
STOCK_WEBVIEW_PACKAGE = "com.android.webview"
STOCK_WEBVIEW_VERSION = "75.0.3770.156"

PRESERVE_TOOL = ROOT / "tools" / "r2-apk-preserve-v2-signing-block.py"
CARRIER_ADAPT_TOOL = ROOT / "tools" / "r2-apk-v2-carrier-adapt.py"
SIGCHECK_TOOL = ROOT / "tools" / "r2-apk-signature-boundary-check.sh"

ROUTE_A_SPEC_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-route-a-provider-spec" / "webview-route-a-provider-spec.json"
SOURCE_BUILD_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-source-build-readiness"
    / "webview-source-build-readiness-plan.json"
)
ROUTE_A_CANDIDATE_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-candidate-audit"
    / "webview-route-a-candidate-audit.json"
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
A_SIG_PM_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-a-sig-package-manager"
    / "webview-a-sig-package-manager-audit.json"
)
A_SIG_PM_MD = ROOT / "docs" / "research" / "webview-a-sig-package-manager-audit.md"

SYSTEM_SIGNATURE_MD = ROOT / "docs" / "research" / "system-apk-signature-boundary.md"
ROUTE_A_SPEC_MD = ROOT / "docs" / "research" / "webview-route-a-provider-spec.md"
SOURCE_BUILD_MD = ROOT / "docs" / "research" / "webview-source-build-readiness-plan.md"

V026A_FAIL = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "v0.26a-launcher-entry-hide"
    / "verify-v0.26a-launcher-entry-hide-device-20260618-182037.txt"
)
V026A1_PASS = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "v0.26a.1-launcher-entry-hide-v2cert"
    / "verify-v0.26a.1-launcher-entry-hide-v2cert-device-20260618-183927.txt"
)
V026A2_PASS = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "v0.26a.2-launcher-entry-hide-v2cert-cachebump"
    / "verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump-device-20260618-190207.txt"
)

OUT_MD = ROOT / "docs" / "research" / "webview-signing-transition-plan.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-signing-transition-plan.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-signing-transition"
OUT_JSON = OUT_DIR / "webview-signing-transition-plan.json"
OUT_STOCK_SIG = OUT_DIR / "stock-webview-signature-boundary.txt"

EOCD_MAGIC = b"PK\x05\x06"
APK_SIG_MAGIC = b"APK Sig Block 42"


@dataclass(frozen=True)
class SourceEvidence:
    source_id: str
    status: str
    evidence: str
    impact: str


@dataclass(frozen=True)
class ApkSignatureShape:
    apk_id: str
    path: str
    status: str
    sha256: str
    size_bytes: int
    apk_sig_block_magic: str
    apk_sig_block_offset: int
    apk_sig_block_bytes: int
    central_directory_offset: int
    keytool_status: str
    jarsigner_status: str
    cert_sha256: str
    cert_owner: str
    notes: str


@dataclass(frozen=True)
class TransitionRoute:
    route_id: str
    status: str
    description: str
    current_evidence: str
    required_next_evidence: str
    risk: str
    blocks: str


@dataclass(frozen=True)
class Gate:
    gate_id: str
    phase: str
    status: str
    required_evidence: str
    blocks: str


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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_eocd(data: bytes) -> int:
    start = max(0, len(data) - 0xFFFF - 22)
    for offset in range(len(data) - 22, start - 1, -1):
        if data[offset : offset + 4] != EOCD_MAGIC:
            continue
        comment_len = struct.unpack_from("<H", data, offset + 20)[0]
        if offset + 22 + comment_len == len(data):
            return offset
    raise ValueError("EOCD not found")


def central_dir_offset(data: bytes, eocd_offset: int) -> int:
    return struct.unpack_from("<I", data, eocd_offset + 16)[0]


def apk_sig_block_info(path: Path) -> dict[str, int | str]:
    if not path.exists():
        return {
            "status": "MISSING",
            "magic": "missing",
            "magic_offset": -1,
            "block_bytes": 0,
            "central_directory_offset": -1,
            "notes": "apk missing",
        }
    data = path.read_bytes()
    try:
        eocd_offset = find_eocd(data)
        cd_offset = central_dir_offset(data, eocd_offset)
    except (ValueError, struct.error) as exc:
        return {
            "status": "ERROR",
            "magic": "unknown",
            "magic_offset": -1,
            "block_bytes": 0,
            "central_directory_offset": -1,
            "notes": str(exc),
        }
    magic_offset = cd_offset - len(APK_SIG_MAGIC)
    if cd_offset >= len(APK_SIG_MAGIC) and data[magic_offset:cd_offset] == APK_SIG_MAGIC:
        size2_offset = magic_offset - 8
        try:
            size2 = struct.unpack_from("<Q", data, size2_offset)[0]
            block_start = cd_offset - size2 - 8
            size1 = struct.unpack_from("<Q", data, block_start)[0] if block_start >= 0 else -1
        except struct.error as exc:
            return {
                "status": "ERROR",
                "magic": "present",
                "magic_offset": magic_offset,
                "block_bytes": 0,
                "central_directory_offset": cd_offset,
                "notes": f"invalid signing block size: {exc}",
            }
        if block_start < 0 or size1 != size2:
            return {
                "status": "ERROR",
                "magic": "present",
                "magic_offset": magic_offset,
                "block_bytes": 0,
                "central_directory_offset": cd_offset,
                "notes": f"invalid signing block size head={size1} tail={size2}",
            }
        return {
            "status": "PASS",
            "magic": "present",
            "magic_offset": magic_offset,
            "block_bytes": cd_offset - block_start,
            "central_directory_offset": cd_offset,
            "notes": "APK Sig Block 42 is immediately before the central directory",
        }
    return {
        "status": "ABSENT",
        "magic": "absent",
        "magic_offset": -1,
        "block_bytes": 0,
        "central_directory_offset": cd_offset,
        "notes": "no APK Sig Block 42 immediately before the central directory",
    }


def parse_field(text: str, prefix: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            return stripped.split("=", 1)[1] if "=" in stripped else stripped[len(prefix) :].strip()
    return ""


def parse_cert_line(text: str, needle: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(needle):
            return stripped
    return ""


def run_sigcheck(path: Path) -> tuple[str, str]:
    if not SIGCHECK_TOOL.exists():
        return "MISSING", f"missing {rel(SIGCHECK_TOOL)}"
    if not path.exists():
        return "MISSING", f"missing {rel(path)}"
    try:
        result = subprocess.run(
            [str(SIGCHECK_TOOL), str(path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=120,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "ERROR", str(exc)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    body = result.stdout
    if result.stderr:
        body += "\n# stderr\n" + result.stderr
    OUT_STOCK_SIG.write_text(body, encoding="utf-8")
    return f"EXIT_{result.returncode}", body


def apk_shape(apk_id: str, path: Path, run_boundary_check: bool = False) -> ApkSignatureShape:
    if not path.exists():
        return ApkSignatureShape(
            apk_id,
            rel(path),
            "MISSING",
            "",
            0,
            "missing",
            -1,
            0,
            -1,
            "",
            "",
            "",
            "",
            "apk missing",
        )
    info = apk_sig_block_info(path)
    sig_status = ""
    sig_text = ""
    if run_boundary_check:
        sig_status, sig_text = run_sigcheck(path)
    cert_sha256 = parse_cert_line(sig_text, "SHA256:")
    cert_owner = parse_cert_line(sig_text, "Owner:")
    keytool_status = parse_field(sig_text, "keytool_status")
    jarsigner_status = parse_field(sig_text, "jarsigner_status")
    sha256 = sha256_file(path)
    status_parts = []
    if sha256 == STOCK_WEBVIEW_SHA256 or apk_id != "stock_webview":
        status_parts.append("HASH_OK" if apk_id == "stock_webview" else "RECORDED")
    else:
        status_parts.append("HASH_MISMATCH")
    status_parts.append(str(info["status"]))
    if run_boundary_check:
        status_parts.append(sig_status)
    return ApkSignatureShape(
        apk_id=apk_id,
        path=rel(path),
        status="+".join(status_parts),
        sha256=sha256,
        size_bytes=path.stat().st_size,
        apk_sig_block_magic=str(info["magic"]),
        apk_sig_block_offset=int(info["magic_offset"]),
        apk_sig_block_bytes=int(info["block_bytes"]),
        central_directory_offset=int(info["central_directory_offset"]),
        keytool_status=keytool_status,
        jarsigner_status=jarsigner_status,
        cert_sha256=cert_sha256,
        cert_owner=cert_owner,
        notes=str(info["notes"]),
    )


def source_gate_status(data: dict, gate_id: str) -> str:
    for row in data.get("gates", []):
        if row.get("gate_id") == gate_id:
            return str(row.get("status", "MISSING"))
    return "MISSING"


def source_evidence(candidate_shape: ApkSignatureShape | None) -> list[SourceEvidence]:
    spec = read_json(ROUTE_A_SPEC_JSON)
    source = read_json(SOURCE_BUILD_JSON)
    route_candidate = read_json(ROUTE_A_CANDIDATE_JSON)
    donor = read_json(DONOR_SELFTEST_JSON)
    bundle = read_json(BUNDLE_SELFTEST_JSON)
    a_sig_pm = read_json(A_SIG_PM_JSON)
    preserve_text = PRESERVE_TOOL.read_text(encoding="utf-8") if PRESERVE_TOOL.exists() else ""
    refuses_existing_block = "edited APK already has an APK signing block" in preserve_text
    carrier_text = CARRIER_ADAPT_TOOL.read_text(encoding="utf-8") if CARRIER_ADAPT_TOOL.exists() else ""
    carrier_has_selftest = "--self-test" in carrier_text and "strip + graft" in carrier_text
    has_candidate_shape = candidate_shape is not None
    source_material_status = "RECORDED" if has_candidate_shape else source_gate_status(source, "SB-GATE-03")
    source_material_evidence = candidate_shape.path if candidate_shape else rel(SOURCE_BUILD_JSON)
    source_material_impact = (
        "A source-built SystemWebView.apk is recorded; signing transition proof is now the active blocker before image design."
        if has_candidate_shape
        else "No source-built SystemWebView.apk is present yet, so this plan can only define proof gates."
    )
    signing_status = "PENDING_A_SIG_REVIEW" if has_candidate_shape else source_gate_status(source, "SB-GATE-04")
    return [
        SourceEvidence(
            "route_a_spec_a_sig_01",
            "RECORDED" if any(row.get("requirement_id") == "A-SIG-01" for row in spec.get("requirements", [])) else "MISSING",
            rel(ROUTE_A_SPEC_JSON),
            "Route A already blocks source-built same-package promotion until signing transition proof exists.",
        ),
        SourceEvidence(
            "source_build_material",
            source_material_status,
            source_material_evidence,
            source_material_impact,
        ),
        SourceEvidence(
            "source_build_signing_gate",
            signing_status,
            rel(SOURCE_BUILD_JSON),
            "PackageManager signing transition remains the active blocker for ROM image design.",
        ),
        SourceEvidence(
            "route_a_candidate_audit",
            str(route_candidate.get("verdict", "MISSING")),
            rel(ROUTE_A_CANDIDATE_JSON),
            "The current Route A candidate audit records the modern source-built candidate shape, but does not authorize image work."
            if str(route_candidate.get("verdict", "")) in {"CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE", "CANDIDATE_SHAPE_WARN_BLOCKED_BY_LIVE"}
            else "The only current Route A candidate audit is stock-shape baseline, not a modern candidate.",
        ),
        SourceEvidence(
            "stock_webview_donor_selftest",
            str(donor.get("verdict", "MISSING")),
            rel(DONOR_SELFTEST_JSON),
            "Stock WebView is a valid standalone com.android.webview reference shape.",
        ),
        SourceEvidence(
            "stock_webview_bundle_selftest",
            str(bundle.get("verdict", "MISSING")),
            rel(BUNDLE_SELFTEST_JSON),
            "Stock WebView bundle classification is standalone-webview.",
        ),
        SourceEvidence(
            "system_apk_signature_boundary",
            "RECORDED" if SYSTEM_SIGNATURE_MD.exists() else "MISSING",
            rel(SYSTEM_SIGNATURE_MD),
            "System partition scans may collect certs without full APK content verification, but signature identity still matters.",
        ),
        SourceEvidence(
            "a_sig_package_manager_audit",
            str(a_sig_pm.get("a_sig_01_status", "MISSING")),
            rel(A_SIG_PM_JSON),
            "The stock-carrier candidate has Android-style cert-only PackageManager evidence for /product system scans."
            if a_sig_pm.get("a_sig_01_status") == "OFFLINE_PM_ACCEPTANCE_RECORDED"
            else "The PackageManager acceptance audit has not yet recorded stock-carrier system-scan evidence.",
        ),
        SourceEvidence(
            "v0.26a_without_v2_carrier",
            "FAIL_RECORDED" if V026A_FAIL.exists() else "MISSING",
            rel(V026A_FAIL),
            "The no-v2-carrier launcher-entry-hide image booted but PackageManager lost the target package paths.",
        ),
        SourceEvidence(
            "v0.26a.1_with_v2_carrier",
            "PASS_RECORDED" if V026A1_PASS.exists() else "MISSING",
            rel(V026A1_PASS),
            "Preserving the v2 cert carrier allowed PackageManager to keep same-package replacements.",
        ),
        SourceEvidence(
            "v0.26a.2_with_cache_bump",
            "PASS_RECORDED" if V026A2_PASS.exists() else "MISSING",
            rel(V026A2_PASS),
            "Adding package directory mtime/cache invalidation stabilized the launcher/package state.",
        ),
        SourceEvidence(
            "v2_preserver_tool",
            "READY_LIMITED" if PRESERVE_TOOL.exists() and refuses_existing_block else "MISSING_OR_UNKNOWN",
            rel(PRESERVE_TOOL),
            "The current tool can copy stock APK Sig Block 42 into an edited APK only if the edited APK has no existing APK signing block.",
        ),
        SourceEvidence(
            "v2_strip_graft_tool",
            "READY_SELFTESTABLE" if CARRIER_ADAPT_TOOL.exists() and carrier_has_selftest else "MISSING_OR_UNKNOWN",
            rel(CARRIER_ADAPT_TOOL),
            "The strip/graft tool can remove an existing candidate APK Sig Block 42 before inserting the stock WebView carrier; its stock self-test verifies strip plus graft can reproduce the original bytes.",
        ),
    ]


def transition_routes(candidate: ApkSignatureShape | None) -> list[TransitionRoute]:
    candidate_note = "no source-built candidate provided"
    carrier_status = "BLOCKED_WAITING_FOR_SOURCE_BUILT_APK"
    a_sig_pm = read_json(A_SIG_PM_JSON)
    pm_status = str(a_sig_pm.get("a_sig_01_status", "MISSING"))
    if candidate:
        carrier_status = "BLOCKED_PENDING_CARRIER_PROOF_REVIEW"
        if candidate.apk_sig_block_magic == "present":
            candidate_note = "candidate has its own APK Sig Block 42 and needs a strip/unsigned-output step before current preserver can insert stock carrier"
        elif candidate.apk_sig_block_magic == "absent":
            candidate_note = "candidate has no APK Sig Block 42 and can enter a stock-cert-carrier graft proof"
        else:
            candidate_note = f"candidate signing shape is {candidate.apk_sig_block_magic}"
        if pm_status == "OFFLINE_PM_ACCEPTANCE_RECORDED":
            carrier_status = "OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE"
            candidate_note += "; A-SIG PackageManager audit records stock-carrier system-scan cert-only acceptance offline"
    return [
        TransitionRoute(
            "STOCK_CERT_CARRIER_ADAPTATION",
            carrier_status,
            "Preferred first experiment: adapt the source-built standalone SystemWebView.apk in place under /product/app/webview while preserving the stock WebView APK Sig Block 42 as the certificate carrier.",
            f"stock WebView carrier, preserver tool, and strip/graft tool are recorded; {candidate_note}",
            "A real SystemWebView.apk, a generated adapted APK from r2-apk-v2-carrier-adapt.py or an equivalent reproducible no-signing-block output, parsed certificate evidence from Android-compatible tooling, and a no-op/live PackageManager proof before ROM design.",
            "This preserves a certificate carrier for Android's cert-only system scan path, but it is not a cryptographically valid re-signing of the modified payload.",
            "Route A ROM image design.",
        ),
        TransitionRoute(
            "SAME_CERT_SIGNED_BUILD",
            "BLOCKED_KEYS_UNAVAILABLE",
            "Build or sign the modern WebView with the original Smartisan/Android signing certificate.",
            "No Smartisan private signing key is present in the project; OTA public certificates do not sign APKs.",
            "Original private APK signing key or a vendor-signed modern WebView package with matching cert lineage.",
            "Treat as unavailable unless the real private key appears; do not confuse public otacerts with APK signing keys.",
            "Direct same-package replacement without carrier adaptation.",
        ),
        TransitionRoute(
            "PACKAGE_SETTING_MIGRATION_GATE",
            "DEFERRED_LIVE_DATA_RISK",
            "Allow a different signing identity only with an explicit package-setting/cache migration experiment.",
            "Current project rules require explicit user confirmation before any /data mutation; this plan is offline only.",
            "A separately approved live-device experiment that snapshots relevant /data/system package state, clears or migrates package_cache/settings for com.android.webview, and verifies rollback.",
            "High risk: a bad package-setting transition can break provider visibility before WebViewUpdateService runs.",
            "Only considered if stock-cert carrier adaptation fails.",
        ),
        TransitionRoute(
            "FRAMEWORK_SIGNATURE_CONFIG_ROUTE",
            "RED_DEFERRED",
            "Patch framework WebView provider config/signature policy to accept a new provider signature.",
            "Route A intentionally avoids framework-res/provider-add risk for the first modern WebView candidate.",
            "Framework-res config_webview_packages.xml signature semantics mapped, overlay/framework patch designed, and separate no-op framework gate passed.",
            "Touches framework/provider selection and may affect every WebView user; this belongs after a source-built candidate exists.",
            "Route B/C or future policy-based provider work.",
        ),
        TransitionRoute(
            "DIRECT_RESIGN_WITH_OUR_KEY",
            "REJECTED",
            "Re-sign source-built com.android.webview with an arbitrary local key and place it over stock.",
            "System APK signature boundary evidence says package identity, shared state, signature permissions, and SELinux policy remain certificate-aware.",
            "None for the current route; this is a rejected shortcut.",
            "Likely PackageManager rejection or stale-cache mismatch for the same package.",
            "Not allowed for Route A.",
        ),
    ]


def gates(candidate: ApkSignatureShape | None) -> list[Gate]:
    candidate_status = "RECORDED" if candidate else "MISSING"
    candidate_evidence = candidate.path if candidate else "source-built SystemWebView.apk is not present"
    adapted_status = "MISSING"
    adapted_evidence = "Adapted candidate APK with stock carrier inserted, parsed signing certificate evidence, donor/bundle audit re-run, and artifact hashes."
    a_sig_pm = read_json(A_SIG_PM_JSON)
    a_sig_pm_status = str(a_sig_pm.get("a_sig_01_status", "MISSING"))
    if candidate:
        candidate_path = Path(candidate.path)
        if not candidate_path.is_absolute():
            candidate_path = ROOT / candidate_path
        adapted_path = candidate_path.parent / "SystemWebView-stock-carrier.apk"
        if adapted_path.exists():
            adapted_status = "RECORDED_PARTIAL"
            adapted_evidence = (
                f"{rel(adapted_path)} exists; still requires Android-compatible parsed signer evidence, "
                "accepted donor/bundle review, and PackageManager/live proof before this gate can be PASS."
            )
            if a_sig_pm_status == "OFFLINE_PM_ACCEPTANCE_RECORDED":
                adapted_status = "OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_LIVE"
                adapted_evidence = (
                    f"{rel(adapted_path)} exists; {rel(A_SIG_PM_JSON)} records Android-style v3 cert-only "
                    "PackageManager evidence for /product system scans. apksigner full verification fails as "
                    "expected for the stock-carrier payload, so live PackageManager/WebViewUpdateService proof "
                    "is still required before acceptance."
                )
    return [
        Gate(
            "SIG-GATE-01",
            "stock-carrier",
            "RECORDED",
            f"Stock WebView APK hash, APK Sig Block 42 offset/size, and signature boundary report: {rel(OUT_STOCK_SIG)}",
            "candidate carrier proof",
        ),
        Gate(
            "SIG-GATE-02",
            "tool-boundary",
            "RECORDED",
            "tools/r2-apk-preserve-v2-signing-block.py limitation recorded, and tools/r2-apk-v2-carrier-adapt.py provides the strip/graft path for candidates that already contain APK Sig Block 42.",
            "source-built packaging instructions",
        ),
        Gate(
            "SIG-GATE-03",
            "candidate-material",
            candidate_status,
            candidate_evidence,
            "stock-cert-carrier adaptation proof",
        ),
        Gate(
            "SIG-GATE-04",
            "candidate-adaptation",
            adapted_status,
            adapted_evidence,
            "Route A integration plan and ROM design plan.",
        ),
        Gate(
            "SIG-GATE-05",
            "package-cache",
            "READY_SPEC",
            "Reuse v0.31/v0.26 package directory mtime/cache-bump rule for /product/app/webview and remove stale oat/vdex when code changes.",
            "offline image verifier.",
        ),
        Gate(
            "SIG-GATE-06",
            "live-noop",
            "FUTURE_REQUIRED",
            "After explicit user confirmation, flash only an offline-verified candidate and verify boot, PM path/hash/signatures, webviewupdate, relro, Settings selector, keyguard, launcher, and logs.",
            "accepting a modern WebView provider.",
        ),
        Gate(
            "SIG-GATE-07",
            "decision",
            "BLOCKED_IMAGE_LIVE_GATE" if a_sig_pm_status == "OFFLINE_PM_ACCEPTANCE_RECORDED" else "BLOCKED",
            "A-SIG offline PackageManager acceptance is recorded; no donor/source-built ROM image is accepted until explicit image review and live regression proof."
            if a_sig_pm_status == "OFFLINE_PM_ACCEPTANCE_RECORDED"
            else "No donor/source-built ROM image is allowed until SIG-GATE-03 and SIG-GATE-04 are PASS.",
            "ROM image design.",
        ),
    ]


def plan_verdict(gate_rows: list[Gate]) -> str:
    gate_status = {row.gate_id: row.status for row in gate_rows}
    if gate_status.get("SIG-GATE-04") == "OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_LIVE":
        return "A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE"
    return "BLOCKED_A_SIG_01"


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|").replace("\n", " ") for cell in row) + " |")
    return lines


def write_tsv(
    path: Path,
    sources: list[SourceEvidence],
    shapes: list[ApkSignatureShape],
    routes: list[TransitionRoute],
    gate_rows: list[Gate],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "status", "evidence_or_description", "required_or_risk", "blocks_or_impact"])
        for row in sources:
            writer.writerow(["source", row.source_id, row.status, row.evidence, "", row.impact])
        for row in shapes:
            writer.writerow(
                [
                    "apk_signature_shape",
                    row.apk_id,
                    row.status,
                    f"{row.path}; sha256={row.sha256}; sig_block={row.apk_sig_block_magic}@{row.apk_sig_block_offset}; block_bytes={row.apk_sig_block_bytes}",
                    f"keytool={row.keytool_status}; jarsigner={row.jarsigner_status}; cert={row.cert_sha256}",
                    row.notes,
                ]
            )
        for row in routes:
            writer.writerow(["transition_route", row.route_id, row.status, row.description, row.required_next_evidence, f"{row.risk}; blocks={row.blocks}"])
        for row in gate_rows:
            writer.writerow(["gate", row.gate_id, row.status, row.required_evidence, "", row.blocks])


def write_markdown(
    path: Path,
    sources: list[SourceEvidence],
    shapes: list[ApkSignatureShape],
    routes: list[TransitionRoute],
    gate_rows: list[Gate],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView Signing Transition Plan")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline plan for the Route A WebView")
    lines.append("same-package signing blocker. It does not download donors, build images,")
    lines.append("touch a device, flash, reboot, erase partitions, write settings, or")
    lines.append("modify `/data`.")
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    has_candidate = any(row.apk_id == "candidate_webview" for row in shapes)
    verdict = plan_verdict(gate_rows)
    if verdict == "A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE":
        lines.append("A modern `com.android.webview` source-built provider is recorded,")
        lines.append("and A-SIG now has offline PackageManager evidence for the")
        lines.append("stock-cert carrier route. The current blocker has moved from")
        lines.append("`A-SIG-01` proof collection to explicit ROM-image acceptance and")
        lines.append("live PackageManager/WebViewUpdateService regression proof.")
    elif has_candidate:
        lines.append("A modern `com.android.webview` source-built provider is now recorded,")
        lines.append("but it is still blocked at `A-SIG-01`. The preferred first route is")
        lines.append("stock-cert carrier adaptation, followed by Android-compatible signer")
        lines.append("evidence and PackageManager/live proof before image design.")
    else:
        lines.append("A modern `com.android.webview` source-built provider is still blocked at")
        lines.append("`A-SIG-01`. The preferred first route is stock-cert carrier adaptation,")
        lines.append("but it cannot be proven until a real `SystemWebView.apk` exists.")
    lines.append("")
    if verdict == "A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE":
        lines.append("ROM design review may proceed from this state, but no WebView")
        lines.append("donor/source-built image is accepted or flashable without the next")
        lines.append("explicit image and live-verification gates.")
    else:
        lines.append("No WebView donor/source-built ROM image is allowed from the current state.")
    lines.append("")
    lines.append("## Why This Exists")
    lines.append("")
    lines.append("Route A keeps the package name `com.android.webview` and replaces")
    lines.append("`/product/app/webview` in place. That avoids an early framework provider")
    lines.append("XML change, but it means PackageManager must reconcile the new APK with the")
    lines.append("existing same-package system identity. The v0.26 launcher-entry-hide series")
    lines.append("proved this is not automatic: package cache and certificate-carrier behavior")
    lines.append("both mattered.")
    lines.append("")
    lines.append("## Source Evidence")
    lines.append("")
    lines.extend(md_table(["Source", "Status", "Evidence", "Impact"], [[row.source_id, row.status, row.evidence, row.impact] for row in sources]))
    lines.append("")
    lines.append("## APK Signature Shapes")
    lines.append("")
    lines.extend(
        md_table(
            [
                "APK",
                "Status",
                "Path",
                "SHA256",
                "Size",
                "APK Sig Block 42",
                "Block bytes",
                "Keytool",
                "Jarsigner",
                "Cert SHA256",
                "Notes",
            ],
            [
                [
                    row.apk_id,
                    row.status,
                    row.path,
                    row.sha256,
                    row.size_bytes,
                    f"{row.apk_sig_block_magic}@{row.apk_sig_block_offset}",
                    row.apk_sig_block_bytes,
                    row.keytool_status,
                    row.jarsigner_status,
                    row.cert_sha256,
                    row.notes,
                ]
                for row in shapes
            ],
        )
    )
    lines.append("")
    lines.append("## Transition Routes")
    lines.append("")
    lines.extend(
        md_table(
            ["Route", "Status", "Description", "Current evidence", "Required next evidence", "Risk", "Blocks"],
            [[row.route_id, row.status, row.description, row.current_evidence, row.required_next_evidence, row.risk, row.blocks] for row in routes],
        )
    )
    lines.append("")
    lines.append("## Gate Order")
    lines.append("")
    lines.extend(md_table(["Gate", "Phase", "Status", "Required evidence", "Blocks"], [[row.gate_id, row.phase, row.status, row.required_evidence, row.blocks] for row in gate_rows]))
    lines.append("")
    lines.append("## Required First Proof")
    lines.append("")
    if has_candidate:
        lines.append("The current `SystemWebView.apk` has already been recorded by this plan.")
        lines.append("The next proof is the stock-carrier adapted APK plus Android-compatible")
        lines.append("signer evidence and a PackageManager/live gate before any image design.")
    else:
        lines.append("After a Linux builder produces `SystemWebView.apk`, run this plan with the")
        lines.append("candidate path and inspect whether the candidate already has an APK signing")
        lines.append("block:")
        lines.append("")
        lines.append("```bash")
        lines.append("tools/r2-webview-signing-transition-plan.py \\")
        lines.append("  --candidate apks/webview-donor-inbox/SystemWebView.apk")
        lines.append("```")
    lines.append("")
    lines.append("If the candidate has no APK Sig Block 42, the current preserver can be used")
    lines.append("for a throwaway adaptation proof. If the candidate has its own signing")
    lines.append("block, use `tools/r2-apk-v2-carrier-adapt.py --strip-existing-candidate`")
    lines.append("or an equivalent reproducible no-signing-block output first. Either way,")
    lines.append("the proof must record Android-compatible certificate parsing evidence, not")
    lines.append("only `keytool` output.")
    lines.append("")
    lines.append("## Source Reports")
    lines.append("")
    lines.append(f"- Route A provider spec: `{rel(ROUTE_A_SPEC_MD)}`")
    lines.append(f"- Source-build readiness: `{rel(SOURCE_BUILD_MD)}`")
    lines.append(f"- System APK signature boundary: `{rel(SYSTEM_SIGNATURE_MD)}`")
    lines.append(f"- A-SIG PackageManager audit: `{rel(A_SIG_PM_MD)}`")
    lines.append(f"- Stock signature boundary snapshot: `{rel(OUT_STOCK_SIG)}`")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--candidate",
        type=Path,
        help="Optional future source-built/adapted SystemWebView.apk to record signing shape only.",
    )
    args = parser.parse_args()

    stock_shape = apk_shape("stock_webview", STOCK_WEBVIEW_APK, run_boundary_check=True)
    shapes = [stock_shape]
    candidate_shape = None
    if args.candidate:
        candidate_path = args.candidate if args.candidate.is_absolute() else ROOT / args.candidate
        candidate_shape = apk_shape("candidate_webview", candidate_path, run_boundary_check=False)
        shapes.append(candidate_shape)
    sources = source_evidence(candidate_shape)

    routes = transition_routes(candidate_shape)
    gate_rows = gates(candidate_shape)
    verdict = plan_verdict(gate_rows)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_tsv(OUT_TSV, sources, shapes, routes, gate_rows)
    write_markdown(OUT_MD, sources, shapes, routes, gate_rows)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "verdict": verdict,
                "a_sig_01_status": "OFFLINE_PM_ACCEPTANCE_RECORDED"
                if verdict == "A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE"
                else "BLOCKED",
                "route": "ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW",
                "package_target": STOCK_WEBVIEW_PACKAGE,
                "stock_version": STOCK_WEBVIEW_VERSION,
                "donor_backed_image_allowed": False,
                "rom_design_review_allowed": verdict == "A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE",
                "stock_cert_carrier_route_preferred": True,
                "sources": [asdict(row) for row in sources],
                "apk_signature_shapes": [asdict(row) for row in shapes],
                "transition_routes": [asdict(row) for row in routes],
                "gates": [asdict(row) for row in gate_rows],
                "next_actions": [
                    "design the first stock-carrier ROM candidate with /product/app/webview package-directory mtime bump",
                    "remove stale WebView oat/vdex artifacts in the candidate image",
                    "rerun Route A candidate audit, integration plan, ROM design plan, and target matrix",
                    "flash only after explicit image confirmation and then run the live WebView regression gate",
                ],
                "outputs": {
                    "markdown": rel(OUT_MD),
                    "tsv": rel(OUT_TSV),
                    "json": rel(OUT_JSON),
                    "stock_signature_boundary": rel(OUT_STOCK_SIG),
                },
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"verdict={verdict}")
    print(
        "a_sig_01_status="
        + (
            "OFFLINE_PM_ACCEPTANCE_RECORDED"
            if verdict == "A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE"
            else "BLOCKED"
        )
    )
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    print(f"stock_signature_boundary={rel(OUT_STOCK_SIG)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
