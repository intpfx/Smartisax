#!/usr/bin/env python3
"""Generate the WebView source-build readiness plan for Smartisax.

This helper is read-only. It turns official Chromium/WebView build guidance
plus local R2 Route A gates into a concrete plan for a future source-built
standalone com.android.webview candidate. It may fetch a small Chromium Dash
release-metadata JSON, but it does not fetch Chromium source, download donors,
build images, touch a device, flash, reboot, erase partitions, write settings,
or modify /data.
"""

from __future__ import annotations

import csv
import json
import subprocess
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_MD = ROOT / "docs" / "research" / "webview-source-build-readiness-plan.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-source-build-readiness-plan.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-source-build-readiness"
OUT_JSON = OUT_DIR / "webview-source-build-readiness-plan.json"
OUT_RELEASE_JSON = OUT_DIR / "chromiumdash-android-stable-latest.json"

CHROMIUM_DASH_ANDROID_STABLE_URL = "https://chromiumdash.appspot.com/fetch_releases?platform=Android&channel=Stable&num=5"
CHROMIUM_SRC_URL = "https://chromium.googlesource.com/chromium/src"

TARGET_MATRIX_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-target-matrix" / "webview-donor-target-matrix.json"
ROUTE_A_SPEC_JSON = ROOT / "hard-rom" / "inspect" / "browser-webview-route-a-provider-spec" / "webview-route-a-provider-spec.json"
ROUTE_A_CANDIDATE_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-candidate-audit"
    / "webview-route-a-candidate-audit.json"
)
LIVE_STATE_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-live-state"
V031_DIR = ROOT / "hard-rom" / "inspect" / "v0.31-webview-stock-near-noop"


@dataclass(frozen=True)
class OfficialFinding:
    finding_id: str
    topic: str
    finding: str
    source: str
    local_impact: str


@dataclass(frozen=True)
class BuildInput:
    input_id: str
    category: str
    requirement: str
    expected_value: str
    local_reason: str
    status: str


@dataclass(frozen=True)
class Gate:
    gate_id: str
    phase: str
    status: str
    required_evidence: str
    blocks: str


@dataclass(frozen=True)
class StableRelease:
    status: str
    version: str
    milestone: str
    channel: str
    platform: str
    previous_version: str
    chromium_hash: str
    branch_position: str
    release_time_ms: str
    tag_ref: str
    tag_status: str
    checkout_revision: str
    source_url: str
    snapshot_path: str
    error: str = ""


@dataclass(frozen=True)
class BuilderStep:
    step_id: str
    phase: str
    command: str
    purpose: str


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


def latest_matching(path: Path, pattern: str) -> Path | None:
    if not path.exists():
        return None
    matches = sorted(path.glob(pattern))
    return max(matches, key=lambda item: item.stat().st_mtime) if matches else None


def verify_chromium_tag(version: str, expected_hash: str) -> tuple[str, str]:
    if not version:
        return "MISSING", ""
    try:
        result = subprocess.run(
            ["git", "ls-remote", "--tags", CHROMIUM_SRC_URL, version],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "ERROR", str(exc)
    if result.returncode != 0:
        return "ERROR", (result.stderr or result.stdout).strip()
    line = (result.stdout or "").strip().splitlines()
    if not line:
        return "MISSING", ""
    observed_hash = line[0].split()[0]
    if expected_hash and observed_hash != expected_hash:
        return "HASH_MISMATCH", observed_hash
    return "PASS", observed_hash


def stable_release_from_record(record: dict, status: str, error: str = "") -> StableRelease:
    version = str(record.get("version", ""))
    hashes = record.get("hashes") or {}
    chromium_hash = str(hashes.get("chromium", ""))
    tag_ref = f"refs/tags/{version}" if version else ""
    tag_status, observed_hash = verify_chromium_tag(version, chromium_hash) if status == "RECORDED" else ("NOT_CHECKED", "")
    checkout_revision = tag_ref if tag_status == "PASS" else (chromium_hash or tag_ref)
    return StableRelease(
        status=status,
        version=version,
        milestone=str(record.get("milestone", "")),
        channel=str(record.get("channel", "")),
        platform=str(record.get("platform", "")),
        previous_version=str(record.get("previous_version", "")),
        chromium_hash=chromium_hash,
        branch_position=str(record.get("chromium_main_branch_position", "")),
        release_time_ms=str(record.get("time", "")),
        tag_ref=tag_ref,
        tag_status=tag_status if tag_status != "PASS" else f"PASS {observed_hash}",
        checkout_revision=checkout_revision,
        source_url=CHROMIUM_DASH_ANDROID_STABLE_URL,
        snapshot_path=rel(OUT_RELEASE_JSON),
        error=error,
    )


def fetch_latest_stable_release() -> StableRelease:
    try:
        with urllib.request.urlopen(CHROMIUM_DASH_ANDROID_STABLE_URL, timeout=30) as response:
            releases = json.load(response)
        if not isinstance(releases, list) or not releases:
            raise ValueError("Chromium Dash returned no Android Stable releases")
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        OUT_RELEASE_JSON.write_text(
            json.dumps(
                {
                    "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "source_url": CHROMIUM_DASH_ANDROID_STABLE_URL,
                    "releases": releases,
                },
                ensure_ascii=True,
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        return stable_release_from_record(releases[0], "RECORDED")
    except (OSError, urllib.error.URLError, ValueError, json.JSONDecodeError) as exc:
        snapshot = read_json(OUT_RELEASE_JSON)
        releases = snapshot.get("releases") or []
        if releases:
            return stable_release_from_record(releases[0], "SNAPSHOT_ONLY", str(exc))
        return StableRelease(
            status="MISSING",
            version="",
            milestone="",
            channel="",
            platform="",
            previous_version="",
            chromium_hash="",
            branch_position="",
            release_time_ms="",
            tag_ref="",
            tag_status="NOT_CHECKED",
            checkout_revision="",
            source_url=CHROMIUM_DASH_ANDROID_STABLE_URL,
            snapshot_path=rel(OUT_RELEASE_JSON),
            error=str(exc),
        )


def source_status() -> dict[str, str]:
    matrix = read_json(TARGET_MATRIX_JSON)
    spec = read_json(ROUTE_A_SPEC_JSON)
    candidate = read_json(ROUTE_A_CANDIDATE_JSON)
    live_state = latest_matching(LIVE_STATE_DIR, "browser-webview-live-state-*.txt")
    v031_live = latest_matching(V031_DIR, "verify-v0.31-webview-stock-near-noop-device-*.txt")
    v031_offline = latest_matching(V031_DIR, "verify-v0.31-webview-stock-near-noop-offline-image-*.txt")
    return {
        "target_matrix": (matrix.get("summary") or {}).get("preferred_route", "MISSING"),
        "route_a_spec": spec.get("spec_status") or spec.get("status", "MISSING"),
        "route_a_candidate": candidate.get("verdict", "MISSING"),
        "live_state": rel(live_state) if live_state else "MISSING",
        "v031_live": rel(v031_live) if v031_live else "MISSING",
        "v031_offline": rel(v031_offline) if v031_offline else "MISSING",
    }


def official_findings() -> list[OfficialFinding]:
    android_build = "https://chromium.googlesource.com/chromium/src/+/main/docs/android_build_instructions.md"
    webview_build = "https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/build-instructions.md"
    aosp_integration = "https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/aosp-system-integration.md"
    return [
        OfficialFinding(
            "OFFICIAL-01",
            "host",
            "Chromium Android builds are documented for x86-64 Linux, not macOS, with at least 100 GB free space and more than 16 GB RAM recommended.",
            android_build,
            "Do not try to turn the Mac Smartisax workspace into the Chromium build host. Use an isolated Linux builder if source-build work starts.",
        ),
        OfficialFinding(
            "OFFICIAL-02",
            "target",
            "The public WebView build target is system_webview_apk.",
            webview_build,
            "A source-built Route A candidate should come from system_webview_apk, not Chrome, BrowserChrome, Monochrome, or a lib-only output.",
        ),
        OfficialFinding(
            "OFFICIAL-03",
            "variant",
            "AOSP system integrator guidance says most AOSP devices should use standalone WebView and that system_webview_apk produces SystemWebView.apk.",
            aosp_integration,
            "This reinforces Route A over Trichrome for the first R2 modernization candidate.",
        ),
        OfficialFinding(
            "OFFICIAL-04",
            "package",
            "system_webview_apk uses com.android.webview by default.",
            webview_build,
            "This matches R2 stock config_webview_packages.xml and avoids a framework-provider-add change for the first candidate.",
        ),
        OfficialFinding(
            "OFFICIAL-05",
            "release",
            "For user-facing distribution, official guidance prefers a recent stable release tag and stable channel settings.",
            aosp_integration,
            "The first serious candidate should be stable-channel source material, not dev/canary, unless explicitly used only for shape probing.",
        ),
        OfficialFinding(
            "OFFICIAL-06",
            "gn_args",
            "Release-suitable guidance includes target_os=android, target_cpu=arm64, is_debug=false, is_official_build=true, disable_fieldtrial_testing_config=true, is_component_build=false, is_chrome_branded=false, use_official_google_api_keys=false, and android_channel=stable.",
            aosp_integration,
            "These become the minimum source-build manifest fields to capture before a source-built APK can enter Route A candidate audit.",
        ),
        OfficialFinding(
            "OFFICIAL-07",
            "abi",
            "For arm64 WebView builds, official guidance says 64-bit builds include code for both 64-bit and corresponding 32-bit architecture, and arm64 devices must use a 64-bit build.",
            aosp_integration,
            "This aligns with the R2 requirement to keep arm64-v8a mandatory and prefer retaining armeabi-v7a compatibility.",
        ),
        OfficialFinding(
            "OFFICIAL-08",
            "framework",
            "AOSP WebView providers are restricted by framework config_webview_packages.xml, and providers without configured signatures must be preinstalled or installed as updates to a preinstalled provider.",
            aosp_integration,
            "The R2 hard-ROM route can keep com.android.webview preinstalled in /product/app/webview and defer signature XML work.",
        ),
    ]


def build_inputs(release: StableRelease, status: dict[str, str]) -> list[BuildInput]:
    release_status = "RECORDED" if release.status in {"RECORDED", "SNAPSHOT_ONLY"} else "NEEDED"
    source_material_ready = status["route_a_candidate"] in {
        "CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE",
        "CANDIDATE_SHAPE_WARN_BLOCKED_BY_LIVE",
    }
    release_value = (
        f"{release.version} / milestone {release.milestone}; checkout {release.checkout_revision}"
        if release.version
        else "stable release tag selected and recorded"
    )
    return [
        BuildInput("SB-IN-01", "host", "Build host", "isolated x86-64 Linux builder, not the Mac workspace", "Chromium Android build on macOS is unsupported and the checkout/build can be very large.", "NEEDED"),
        BuildInput("SB-IN-02", "source", "Chromium stable release", release_value, "A stable tag keeps the WebView payload closer to a user-facing security/stability baseline.", release_status),
        BuildInput("SB-IN-03", "target", "GN/Ninja target", "system_webview_apk", "This is the standalone public WebView target that keeps package com.android.webview by default.", "READY_SPEC"),
        BuildInput("SB-IN-04", "gn_args", "target_os", "android", "Required by Chromium Android/WebView build.", "READY_SPEC"),
        BuildInput("SB-IN-05", "gn_args", "target_cpu", "arm64", "R2/kona is arm64 and official guidance requires arm64 WebView on arm64 devices.", "READY_SPEC"),
        BuildInput("SB-IN-06", "gn_args", "package name", "com.android.webview; keep default or set system_webview_package_name explicitly to this value", "R2 framework whitelist already allows only com.android.webview.", "READY_SPEC"),
        BuildInput("SB-IN-07", "gn_args", "release shape", "is_debug=false; is_official_build=true; disable_fieldtrial_testing_config=true; is_component_build=false; android_channel=stable", "Matches official release-suitable WebView guidance and avoids development-only package shape.", "READY_SPEC"),
        BuildInput("SB-IN-08", "gn_args", "branding/API keys", "is_chrome_branded=false; use_official_google_api_keys=false", "Public AOSP-style WebView route must avoid Google-internal assumptions.", "READY_SPEC"),
        BuildInput("SB-IN-09", "artifact", "output APK", "SystemWebView.apk plus build args/version manifest", "The APK alone is not enough; we need reproducibility metadata for future rebuilds.", "RECORDED" if source_material_ready else "NEEDED"),
        BuildInput("SB-IN-10", "artifact", "Route A audit input", "place APK under apks/webview-donor-inbox/ or pass it to r2-webview-route-a-candidate-audit.py", "All source-build material must pass the same candidate intake as prebuilts.", "READY_SPEC"),
        BuildInput("SB-IN-11", "artifact", "PackageManager signing transition", "stock-cert carrier adaptation, same-cert build, or a separately tested package-setting migration gate", "Same-package system WebView replacement can fail before WebViewUpdateService if PackageManager cannot reconcile signatures/cached package state.", "NEEDED"),
    ]


def gates(status: dict[str, str], release: StableRelease) -> list[Gate]:
    route_a_spec_ready = status["route_a_spec"] == "READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE"
    candidate_is_baseline = status["route_a_candidate"] == "BASELINE_SHAPE_PASS_NOT_MODERN"
    source_material_ready = status["route_a_candidate"] in {
        "CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE",
        "CANDIDATE_SHAPE_WARN_BLOCKED_BY_LIVE",
    }
    live_missing = status["live_state"] == "MISSING"
    v031_live_missing = status["v031_live"] == "MISSING"
    release_ready = release.status in {"RECORDED", "SNAPSHOT_ONLY"} and bool(release.version)
    return [
        Gate(
            "SB-GATE-01",
            "source-build-intake",
            "READY_SPEC" if route_a_spec_ready else "MISSING_SPEC",
            f"Route A provider spec: {status['route_a_spec']}",
            "source-built APK intake",
        ),
        Gate(
            "SB-GATE-02",
            "stable-release-selection",
            "RECORDED" if release_ready else "MISSING",
            f"Chromium Android Stable release: {release.version or 'missing'}; tag={release.tag_status}; snapshot={release.snapshot_path}",
            "Linux builder checkout",
        ),
        Gate(
            "SB-GATE-03",
            "source-build-material",
            "RECORDED" if source_material_ready else "MISSING",
            "Stable release tag, GN args, build command transcript, SystemWebView.apk, and artifact hashes from an isolated Linux builder.",
            "Route A candidate audit",
        ),
        Gate(
            "SB-GATE-04",
            "source-build-adaptation",
            "PENDING_A_SIG_REVIEW" if source_material_ready else "MISSING",
            "PackageManager signing transition evidence for same-package com.android.webview replacement.",
            "ROM image design",
        ),
        Gate(
            "SB-GATE-05",
            "candidate-audit",
            "BASELINE_ONLY_READY_FOR_REAL_INPUT" if candidate_is_baseline else status["route_a_candidate"],
            f"Current Route A candidate audit: {status['route_a_candidate']}",
            "integration and ROM design plan",
        ),
        Gate(
            "SB-GATE-06",
            "live-baseline",
            "MISSING" if live_missing else "RECORDED",
            f"Browser/WebView live-state evidence: {status['live_state']}",
            "donor-backed image design",
        ),
        Gate(
            "SB-GATE-07",
            "v0.31-live-provider-proof",
            "MISSING" if v031_live_missing else "RECORDED",
            f"v0.31 live provider proof: {status['v031_live']}; offline proof: {status['v031_offline']}",
            "donor-backed image build/flash",
        ),
    ]


def builder_steps(release: StableRelease) -> list[BuilderStep]:
    version = release.version or "<stable-version>"
    checkout = release.checkout_revision or f"refs/tags/{version}"
    out_dir = "out/SmartisaxWebView"
    gn_args = "\\n".join(
        [
            'target_os = "android"',
            'target_cpu = "arm64"',
            'is_debug = false',
            'is_official_build = true',
            'disable_fieldtrial_testing_config = true',
            'is_component_build = false',
            'is_chrome_branded = false',
            'use_official_google_api_keys = false',
            'android_channel = "stable"',
            'system_webview_package_name = "com.android.webview"',
        ]
    )
    return [
        BuilderStep("SB-CMD-01", "host", "git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git", "Install depot_tools on the isolated Linux builder."),
        BuilderStep("SB-CMD-02", "host", 'export PATH="$PWD/depot_tools:$PATH"', "Put depot_tools in PATH for fetch/gclient/autoninja."),
        BuilderStep("SB-CMD-03", "checkout", "mkdir chromium-webview && cd chromium-webview", "Create a checkout root with no spaces in the path."),
        BuilderStep("SB-CMD-04", "checkout", "fetch --nohooks --no-history android", "Fetch Android Chromium source with reduced history."),
        BuilderStep("SB-CMD-05", "checkout", "cd src", "Enter the Chromium source root."),
        BuilderStep("SB-CMD-06", "checkout", f"git fetch origin {checkout}", "Fetch the selected Android Stable release revision."),
        BuilderStep("SB-CMD-07", "checkout", f"git checkout -b smartisax-webview-{version} {checkout}", "Create a named local branch for reproducibility."),
        BuilderStep("SB-CMD-08", "deps", "build/install-build-deps.sh", "Install Linux and Android build dependencies on the builder."),
        BuilderStep("SB-CMD-09", "deps", "gclient sync --no-history", "Sync dependencies at the selected Chromium revision."),
        BuilderStep("SB-CMD-10", "deps", "gclient runhooks", "Run Chromium hooks after dependency sync."),
        BuilderStep("SB-CMD-11", "config", f"mkdir -p {out_dir}", "Create the dedicated WebView output directory."),
        BuilderStep("SB-CMD-12", "config", f"gn args {out_dir}", "Open GN args and paste the source-build manifest values below."),
        BuilderStep("SB-CMD-13", "config", gn_args, "GN args for the first R2 Route A source-built standalone WebView candidate."),
        BuilderStep("SB-CMD-14", "build", f"autoninja -C {out_dir} system_webview_apk", "Build the standalone WebView APK."),
        BuilderStep("SB-CMD-15", "artifact", f"find {out_dir} -name 'SystemWebView.apk' -o -name '*WebView*.apk'", "Locate the APK output and copy it plus build metadata back to Smartisax."),
    ]


def write_tsv(path: Path, release: StableRelease, findings: list[OfficialFinding], inputs: list[BuildInput], gate_rows: list[Gate], steps: list[BuilderStep]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "topic_or_phase", "status", "requirement_or_finding", "evidence_or_impact"])
        writer.writerow(["release", release.version, release.platform, release.status, f"milestone={release.milestone}; channel={release.channel}; previous={release.previous_version}", f"hash={release.chromium_hash}; tag={release.tag_status}; snapshot={release.snapshot_path}"])
        for row in findings:
            writer.writerow(["official", row.finding_id, row.topic, "", row.finding, f"{row.source}; {row.local_impact}"])
        for row in inputs:
            writer.writerow(["input", row.input_id, row.category, row.status, row.requirement, f"{row.expected_value}; {row.local_reason}"])
        for row in gate_rows:
            writer.writerow(["gate", row.gate_id, row.phase, row.status, row.required_evidence, row.blocks])
        for row in steps:
            writer.writerow(["builder_step", row.step_id, row.phase, "", row.command, row.purpose])


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|") for cell in row) + " |")
    return lines


def write_markdown(path: Path, status: dict[str, str], release: StableRelease, findings: list[OfficialFinding], inputs: list[BuildInput], gate_rows: list[Gate], steps: list[BuilderStep]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView Source-Build Readiness Plan")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline readiness plan for a future source-built")
    lines.append("standalone WebView candidate. It may fetch a small Chromium Dash")
    lines.append("release-metadata JSON, but it does not fetch Chromium source, download")
    lines.append("donors, build images, touch a device, flash, reboot, erase partitions,")
    lines.append("write settings, or modify `/data`.")
    lines.append("")
    lines.append("## Current Decision")
    lines.append("")
    lines.append("The first source-build route should target Chromium's public")
    lines.append("`system_webview_apk` output, keep the default `com.android.webview`")
    lines.append("package name, and treat the resulting `SystemWebView.apk` as Route A")
    lines.append("candidate material. This matches R2's stock WebView provider whitelist")
    lines.append("and avoids framework-provider-add work for the first modernization gate.")
    lines.append("")
    source_material_ready = status["route_a_candidate"] in {
        "CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE",
        "CANDIDATE_SHAPE_WARN_BLOCKED_BY_LIVE",
    }
    if source_material_ready:
        lines.append("Source-built material is now recorded, but no donor-backed image is")
        lines.append("allowed until A-SIG review, ROM design review, explicit image")
        lines.append("acceptance, and live-device regression testing pass.")
    else:
        lines.append("No source-built material is present yet, so no donor-backed image is")
        lines.append("allowed from this state.")
    lines.append("")
    lines.append("## Current Android Stable Release")
    lines.append("")
    lines.extend(
        md_table(
            ["Item", "Value"],
            [
                ["status", release.status],
                ["platform/channel", f"{release.platform} / {release.channel}"],
                ["version", release.version or "missing"],
                ["milestone", release.milestone or "missing"],
                ["previous version", release.previous_version or "missing"],
                ["chromium hash", release.chromium_hash or "missing"],
                ["branch position", release.branch_position or "missing"],
                ["tag ref", release.tag_ref or "missing"],
                ["tag verification", release.tag_status],
                ["checkout revision", release.checkout_revision or "missing"],
                ["source", release.source_url],
                ["snapshot", release.snapshot_path],
                ["error", release.error or ""],
            ],
        )
    )
    lines.append("")
    lines.append("## Current Local Gates")
    lines.append("")
    lines.extend(md_table(["Gate", "Value"], [[key, value] for key, value in status.items()]))
    lines.append("")
    lines.append("## Official Source Findings")
    lines.append("")
    lines.extend(
        md_table(
            ["ID", "Topic", "Finding", "Source", "Local impact"],
            [[row.finding_id, row.topic, row.finding, row.source, row.local_impact] for row in findings],
        )
    )
    lines.append("")
    lines.append("## Source-Build Input Manifest")
    lines.append("")
    lines.extend(
        md_table(
            ["ID", "Category", "Status", "Requirement", "Expected value", "Local reason"],
            [[row.input_id, row.category, row.status, row.requirement, row.expected_value, row.local_reason] for row in inputs],
        )
    )
    lines.append("")
    lines.append("## Gate Order")
    lines.append("")
    lines.extend(
        md_table(
            ["Gate", "Phase", "Status", "Required evidence", "Blocks"],
            [[row.gate_id, row.phase, row.status, row.required_evidence, row.blocks] for row in gate_rows],
        )
    )
    lines.append("")
    lines.append("## Linux Builder Command Plan")
    lines.append("")
    lines.append("Run this only on an isolated x86-64 Linux builder with enough disk and RAM,")
    lines.append("not on the Mac project workspace.")
    lines.append("")
    for step in steps:
        if step.step_id == "SB-CMD-13":
            lines.append(f"### {step.step_id} {step.phase}")
            lines.append("")
            lines.append("```gn")
            lines.extend(step.command.split("\\n"))
            lines.append("```")
        else:
            lines.append(f"### {step.step_id} {step.phase}")
            lines.append("")
            lines.append("```bash")
            lines.append(step.command)
            lines.append("```")
        lines.append("")
        lines.append(step.purpose)
        lines.append("")
    lines.append("## First Candidate Intake Command")
    lines.append("")
    lines.append("After a Linux builder produces a stable `SystemWebView.apk`, copy only the")
    lines.append("APK and a small build manifest into `apks/webview-donor-inbox/`, then run:")
    lines.append("")
    lines.append("```bash")
    lines.append("tools/r2-webview-route-a-candidate-audit.py \\")
    lines.append("  apks/webview-donor-inbox/SystemWebView.apk \\")
    label_version = release.version.replace(".", "-") if release.version else "stable"
    lines.append(f"  --label sourcebuilt-system-webview-{label_version}")
    lines.append("tools/r2-webview-donor-inbox-audit.py")
    lines.append("tools/r2-webview-donor-target-matrix.py")
    lines.append("tools/r2-webview-integration-plan.py")
    lines.append("tools/r2-webview-rom-design-plan.py")
    lines.append("```")
    lines.append("")
    lines.append("Before a ROM image can be designed, also prove the same-package signing")
    lines.append("transition for `com.android.webview`: stock-cert carrier adaptation, a")
    lines.append("same-cert build, or a separately tested package-setting migration gate.")
    lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("This plan authorizes only future source-build intake and static auditing.")
    lines.append("It does not authorize Chromium checkout on the Mac, use of the LiveSystem")
    lines.append("server, ROM image generation, flashing, or any `/data` write. A real")
    lines.append("candidate still needs signing-transition proof,")
    lines.append("Route A candidate review, integration-plan readiness, and ROM-design")
    lines.append("readiness before image work. Browser/WebView live-state and v0.31 stock")
    lines.append("provider proof are currently recorded, and must be rerun after any future")
    lines.append("donor-backed flash.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    release = fetch_latest_stable_release()
    status = source_status()
    findings = official_findings()
    inputs = build_inputs(release, status)
    gate_rows = gates(status, release)
    steps = builder_steps(release)
    write_tsv(OUT_TSV, release, findings, inputs, gate_rows, steps)
    write_markdown(OUT_MD, status, release, findings, inputs, gate_rows, steps)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "status": status,
                "stable_release": asdict(release),
                "official_findings": [asdict(row) for row in findings],
                "build_inputs": [asdict(row) for row in inputs],
                "gates": [asdict(row) for row in gate_rows],
                "builder_steps": [asdict(row) for row in steps],
                "donor_backed_image_allowed": False,
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print("source_build_route=system_webview_apk")
    print("package_target=com.android.webview")
    print(f"stable_release={release.version or 'missing'}")
    print(f"stable_release_status={release.status}")
    print(f"stable_release_tag={release.tag_status}")
    print("donor_backed_image_allowed=false")
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
