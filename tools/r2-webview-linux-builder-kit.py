#!/usr/bin/env python3
"""Generate the isolated Linux builder kit for Smartisax WebView.

This helper is read-only with respect to devices and ROM images. It writes a
small reproducible handoff kit for a future x86-64 Linux Chromium/WebView build
host. It does not fetch Chromium source, build WebView, download donors, touch a
device, flash, reboot, erase partitions, write settings, or modify `/data`.
"""

from __future__ import annotations

import csv
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

SOURCE_BUILD_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-source-build-readiness"
    / "webview-source-build-readiness-plan.json"
)
SIGNING_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-signing-transition"
    / "webview-signing-transition-plan.json"
)
ROUTE_A_SPEC_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-provider-spec"
    / "webview-route-a-provider-spec.json"
)

OUT_MD = ROOT / "docs" / "research" / "webview-linux-builder-kit.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-linux-builder-kit.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-linux-builder-kit"
OUT_JSON = OUT_DIR / "webview-linux-builder-kit.json"
KIT_DIR = OUT_DIR / "kit"

DEFAULT_CHROMIUM_VERSION = "150.0.7871.28"
DEFAULT_CHROMIUM_MILESTONE = "150"
DEFAULT_CHROMIUM_HASH = "48db307645dcbaa0bb5ccee0cd096cf22971bb84"
DEFAULT_CHROMIUM_TAG = f"refs/tags/{DEFAULT_CHROMIUM_VERSION}"
DEFAULT_TAG_STATUS = f"PASS {DEFAULT_CHROMIUM_HASH}"


@dataclass(frozen=True)
class KitInput:
    input_id: str
    status: str
    value: str
    evidence: str


@dataclass(frozen=True)
class KitFile:
    file_id: str
    path: str
    purpose: str
    run_where: str


@dataclass(frozen=True)
class Gate:
    gate_id: str
    status: str
    requirement: str
    evidence: str
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


def release_info() -> dict[str, str]:
    source = read_json(SOURCE_BUILD_JSON)
    release = source.get("stable_release") or {}
    version = str(release.get("version") or DEFAULT_CHROMIUM_VERSION)
    tag = str(release.get("checkout_revision") or release.get("tag_ref") or DEFAULT_CHROMIUM_TAG)
    return {
        "version": version,
        "milestone": str(release.get("milestone") or DEFAULT_CHROMIUM_MILESTONE),
        "chromium_hash": str(release.get("chromium_hash") or DEFAULT_CHROMIUM_HASH),
        "checkout_revision": tag,
        "tag_status": str(release.get("tag_status") or DEFAULT_TAG_STATUS),
        "source_snapshot": rel(SOURCE_BUILD_JSON),
    }


def gn_args_text() -> str:
    return "\n".join(
        [
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
            "",
        ]
    )


def builder_script(release: dict[str, str]) -> str:
    version = release["version"]
    checkout = release["checkout_revision"]
    return f"""#!/usr/bin/env bash
set -euo pipefail

# Run this on an isolated x86-64 Linux builder, not inside production service
# directories. Chromium Android/WebView builds are large and network-heavy.

CHROMIUM_VERSION="${{CHROMIUM_VERSION:-{version}}}"
CHECKOUT_REVISION="${{CHECKOUT_REVISION:-{checkout}}}"
WEBVIEW_BUILD_ROOT="${{WEBVIEW_BUILD_ROOT:-$PWD/smartisax-webview-build}}"
DEPOT_TOOLS_DIR="${{DEPOT_TOOLS_DIR:-$WEBVIEW_BUILD_ROOT/depot_tools}}"
CHROMIUM_PARENT="${{CHROMIUM_PARENT:-$WEBVIEW_BUILD_ROOT/chromium-webview}}"
CHROMIUM_SRC="${{CHROMIUM_SRC:-$CHROMIUM_PARENT/src}}"
OUT_DIR="${{OUT_DIR:-out/SmartisaxWebView}}"
INSTALL_BUILD_DEPS_ARGS="${{INSTALL_BUILD_DEPS_ARGS:---android --no-prompt}}"
GCLIENT_SYNC_ARGS="${{GCLIENT_SYNC_ARGS:---no-history --jobs 4}}"

SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
LOG_DIR="${{LOG_DIR:-$SCRIPT_DIR/logs}}"
mkdir -p "$WEBVIEW_BUILD_ROOT" "$LOG_DIR"
LOG="$LOG_DIR/build-system-webview-${{CHROMIUM_VERSION}}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

echo "smartisax_webview_build_start=$(date -Is)"
echo "build_root=$WEBVIEW_BUILD_ROOT"
echo "checkout_revision=$CHECKOUT_REVISION"
echo "out_dir=$OUT_DIR"

if [ ! -d "$DEPOT_TOOLS_DIR/.git" ]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
else
  git -C "$DEPOT_TOOLS_DIR" fetch origin main
  git -C "$DEPOT_TOOLS_DIR" checkout -B main origin/main
fi

export PATH="$DEPOT_TOOLS_DIR:$PATH"
mkdir -p "$CHROMIUM_PARENT"

if [ ! -d "$CHROMIUM_SRC/.git" ]; then
  cd "$CHROMIUM_PARENT"
  fetch --nohooks --no-history android
fi

cd "$CHROMIUM_SRC"
git fetch --depth=1 origin "$CHECKOUT_REVISION"
git checkout -B "smartisax-webview-${{CHROMIUM_VERSION}}" FETCH_HEAD

# Android WebView builds need the Android dependency set; keep it noninteractive
# for remote builders and CI-style self-hosted runners.
build/install-build-deps.sh $INSTALL_BUILD_DEPS_ARGS
# Keep default sync concurrency modest; some public Chromium remotes return
# short-term quota failures when a fresh cloud IP fans out too aggressively.
gclient sync $GCLIENT_SYNC_ARGS

# fetch android creates a minimal .gclient with no checkout_pgo_profiles custom
# var. Official Android/WebView builds still enable AFDO/PGO and V8 builtins
# optimization, so explicitly fetch the public profile inputs before GN/Ninja.
python3 tools/download_optimization_profile.py \
  --newest_state=chrome/android/profiles/newest.txt \
  --local_state=chrome/android/profiles/local.txt \
  --output_name=chrome/android/profiles/afdo.prof \
  --gs_url_base=chromeos-prebuilt/afdo-job/llvm
python3 tools/download_optimization_profile.py \
  --newest_state=chrome/android/profiles/arm.newest.txt \
  --local_state=chrome/android/profiles/arm.local.txt \
  --output_name=chrome/android/profiles/arm.afdo.prof \
  --gs_url_base=chromeos-prebuilt/afdo-job/llvm
python3 tools/update_pgo_profiles.py \
  --target=android-arm32 \
  update \
  --gs-url-base=chromium-optimization-profiles/pgo_profiles
python3 tools/update_pgo_profiles.py \
  --target=android-desktop-x64 \
  update \
  --gs-url-base=chromium-optimization-profiles/pgo_profiles
python3 v8/tools/builtins-pgo/download_profiles.py \
  download \
  --depot-tools third_party/depot_tools \
  --check-v8-revision \
  --quiet

gclient runhooks

mkdir -p "$OUT_DIR"
cp "$SCRIPT_DIR/gn.args" "$OUT_DIR/args.gn"
gn gen "$OUT_DIR"
autoninja -C "$OUT_DIR" system_webview_apk

echo "smartisax_webview_build_end=$(date -Is)"
echo "log=$LOG"
find "$OUT_DIR" -name 'SystemWebView.apk' -o -name '*WebView*.apk'
"""


def preflight_script() -> str:
    return """#!/usr/bin/env bash
set -euo pipefail

# Run on the isolated Linux builder before any Chromium fetch/build. This is a
# local host sanity check only; it does not download source or touch a device.

MIN_FREE_GB="${MIN_FREE_GB:-250}"
MIN_RAM_GB="${MIN_RAM_GB:-16}"
WEBVIEW_BUILD_ROOT="${WEBVIEW_BUILD_ROOT:-$PWD/smartisax-webview-build}"

echo "smartisax_webview_builder_preflight_start=$(date -Is)"
echo "build_root=$WEBVIEW_BUILD_ROOT"
echo "min_free_gb=$MIN_FREE_GB"
echo "min_ram_gb=$MIN_RAM_GB"

if [ "$(uname -s)" != "Linux" ]; then
  echo "error: Chromium Android/WebView build must run on Linux" >&2
  exit 1
fi

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) ;;
  *)
    echo "error: expected x86-64 Linux builder, got arch=$arch" >&2
    exit 1
    ;;
esac

case "$WEBVIEW_BUILD_ROOT" in
  *" "*)
    echo "error: WEBVIEW_BUILD_ROOT must not contain spaces" >&2
    exit 1
    ;;
esac

for cmd in awk df git id mkdir python3 sed uname; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command missing: $cmd" >&2
    exit 1
  fi
done

if ! mkdir -p "$WEBVIEW_BUILD_ROOT" 2>/dev/null; then
  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$WEBVIEW_BUILD_ROOT"
    sudo chown "$(id -u):$(id -g)" "$WEBVIEW_BUILD_ROOT"
  else
    echo "error: cannot create WEBVIEW_BUILD_ROOT and sudo is unavailable: $WEBVIEW_BUILD_ROOT" >&2
    exit 1
  fi
fi

if [ ! -w "$WEBVIEW_BUILD_ROOT" ]; then
  echo "error: WEBVIEW_BUILD_ROOT is not writable by current user: $WEBVIEW_BUILD_ROOT" >&2
  exit 1
fi

free_gb="$(df -Pk "$WEBVIEW_BUILD_ROOT" | awk 'NR == 2 { printf "%d", $4 / 1024 / 1024 }')"
echo "free_gb=$free_gb"
if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
  echo "error: free disk ${free_gb}G is below required ${MIN_FREE_GB}G" >&2
  exit 1
fi

if [ -r /proc/meminfo ]; then
  ram_gb="$(awk '/MemTotal:/ { printf "%d", $2 / 1024 / 1024 }' /proc/meminfo)"
  echo "ram_gb=$ram_gb"
  if [ "$ram_gb" -lt "$MIN_RAM_GB" ]; then
    echo "error: RAM ${ram_gb}G is below required ${MIN_RAM_GB}G" >&2
    exit 1
  fi
else
  echo "warning: /proc/meminfo unavailable; RAM check skipped"
fi

echo "result=PASS"
echo "smartisax_webview_builder_preflight_end=$(date -Is)"
"""


def collect_script(release: dict[str, str]) -> str:
    version = release["version"]
    return f"""#!/usr/bin/env bash
set -euo pipefail

# Run on the same isolated Linux builder after build-system-webview.sh finishes.

CHROMIUM_VERSION="${{CHROMIUM_VERSION:-{version}}}"
WEBVIEW_BUILD_ROOT="${{WEBVIEW_BUILD_ROOT:-$PWD/smartisax-webview-build}}"
CHROMIUM_SRC="${{CHROMIUM_SRC:-$WEBVIEW_BUILD_ROOT/chromium-webview/src}}"
OUT_DIR="${{OUT_DIR:-out/SmartisaxWebView}}"
SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
DIST="${{DIST:-$SCRIPT_DIR/dist/sourcebuilt-system-webview-${{CHROMIUM_VERSION}}}}"

mkdir -p "$DIST"
cd "$CHROMIUM_SRC"

APK="$(find "$OUT_DIR" -name 'SystemWebView.apk' -type f -print -quit)"
if [ -z "$APK" ]; then
  echo "error: SystemWebView.apk not found under $OUT_DIR" >&2
  exit 1
fi

cp "$APK" "$DIST/SystemWebView.apk"
cp "$OUT_DIR/args.gn" "$DIST/args.gn"
git rev-parse HEAD > "$DIST/chromium-revision.txt"
git status --short > "$DIST/chromium-status.txt"
gn args "$OUT_DIR" --list > "$DIST/gn-args-expanded.txt"
find "$OUT_DIR" -maxdepth 4 -type f \\( -name 'SystemWebView.apk' -o -name '*WebView*.apk' \\) > "$DIST/webview-apk-paths.txt"

(
  cd "$DIST"
  sha256sum SystemWebView.apk args.gn chromium-revision.txt gn-args-expanded.txt > SHA256SUMS.txt
)

python3 - "$DIST" "$CHROMIUM_VERSION" "$OUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

dist = Path(sys.argv[1])
version = sys.argv[2]
out_dir = sys.argv[3]
chromium_revision = (dist / "chromium-revision.txt").read_text(encoding="utf-8").strip()
manifest = {{
    "artifact_kind": "sourcebuilt_system_webview",
    "version": version,
    "package_target": "com.android.webview",
    "gn_target": "system_webview_apk",
    "out_dir": out_dir,
    "chromium_revision": chromium_revision,
    "apk": "SystemWebView.apk",
    "sha256s": "SHA256SUMS.txt",
    "files": sorted(p.name for p in dist.iterdir() if p.is_file()),
    "generated_on_builder": True,
}}
(dist / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\\n")
PY

echo "dist=$DIST"
echo "copy this dist directory back into the Smartisax Mac workspace, then run the local intake commands recorded in local-intake-after-copy.sh"
"""


def local_intake_script(release: dict[str, str]) -> str:
    version_label = release["version"].replace(".", "-")
    return f"""#!/usr/bin/env bash
set -euo pipefail

# Run this from the Smartisax Mac workspace after copying the Linux builder
# dist directory back. This is offline/local only; it does not touch a device.

ROOT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")/../../../.." && pwd)"
DIST="${{1:-}}"
if [ -z "$DIST" ]; then
  echo "usage: $0 /path/to/sourcebuilt-system-webview-{release['version']}" >&2
  exit 2
fi

cd "$ROOT_DIR"
tools/r2-webview-sourcebuilt-intake.py "$DIST" --label "sourcebuilt-system-webview-{version_label}"
"""


def kit_readme(release: dict[str, str]) -> str:
    return f"""# Smartisax WebView Linux Builder Kit

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

This kit prepares the missing source-built `SystemWebView.apk` input for the
Smartisan R2 WebView Route A backport. It is not a ROM image and it does not
touch the phone.

## Builder Boundary

Run the Linux scripts only on an isolated x86-64 Linux builder with enough disk
and RAM. Do not run them inside a production service directory or in a path
shared with LiveSystem runtime data.

The build script fetches Chromium source and dependencies, so it is intentionally
separate from the Mac Smartisax workspace.

The preflight script checks Linux/x86-64, required base commands, disk, RAM, and
build-root writability before the fetch/build step. If a configured path such as
`/mnt/webview-build` is not creatable by the runner user, it tries a narrow
`sudo mkdir` plus `chown` fallback and then verifies the directory is writable.

## Target

```text
Chromium Android Stable: {release['version']}
Checkout revision: {release['checkout_revision']}
Milestone: {release['milestone']}
Chromium hash: {release['chromium_hash']}
Tag status: {release['tag_status']}
GN/Ninja target: system_webview_apk
Package target: com.android.webview
```

## Linux Builder Steps

```bash
chmod +x preflight-linux-builder.sh build-system-webview.sh collect-system-webview-artifact.sh
MIN_FREE_GB=250 MIN_RAM_GB=16 WEBVIEW_BUILD_ROOT=/mnt/webview-build ./preflight-linux-builder.sh
./build-system-webview.sh
./collect-system-webview-artifact.sh
```

Then copy the generated `dist/sourcebuilt-system-webview-{release['version']}`
directory back to the Mac workspace.

## Mac Intake Step

From the Smartisax workspace, run:

```bash
hard-rom/inspect/browser-webview-linux-builder-kit/kit/local-intake-after-copy.sh \\
  /path/to/sourcebuilt-system-webview-{release['version']}
```

The collection step writes `artifact-manifest.json`, `SHA256SUMS.txt`,
`args.gn`, `chromium-revision.txt`, and `gn-args-expanded.txt`. The intake step
validates those provenance files before copying the APK, then records signing
shape, runs Route A candidate audit, and refreshes the integration/ROM
design/target matrix. It still does not build or flash a donor-backed ROM
image.
"""


def inputs(release: dict[str, str]) -> list[KitInput]:
    source = read_json(SOURCE_BUILD_JSON)
    signing = read_json(SIGNING_JSON)
    spec = read_json(ROUTE_A_SPEC_JSON)
    return [
        KitInput("KIT-IN-01", "RECORDED", release["version"], rel(SOURCE_BUILD_JSON)),
        KitInput("KIT-IN-02", "RECORDED", release["checkout_revision"], rel(SOURCE_BUILD_JSON)),
        KitInput("KIT-IN-03", "RECORDED", "system_webview_apk / com.android.webview", rel(SOURCE_BUILD_JSON)),
        KitInput("KIT-IN-04", str(source.get("donor_backed_image_allowed", False)), "donor-backed image allowed flag", rel(SOURCE_BUILD_JSON)),
        KitInput("KIT-IN-05", str(signing.get("verdict", "MISSING")), "A-SIG-01 signing-transition state", rel(SIGNING_JSON)),
        KitInput("KIT-IN-06", str(spec.get("spec_status", "MISSING")), "Route A provider spec", rel(ROUTE_A_SPEC_JSON)),
    ]


def kit_files() -> list[KitFile]:
    return [
        KitFile("KIT-FILE-01", rel(KIT_DIR / "README.md"), "builder instructions and boundaries", "read on Mac and Linux"),
        KitFile("KIT-FILE-02", rel(KIT_DIR / "gn.args"), "exact WebView GN args", "Linux builder"),
        KitFile("KIT-FILE-03", rel(KIT_DIR / "preflight-linux-builder.sh"), "check Linux/x86-64, disk, RAM, and build path before fetch/build", "isolated Linux builder"),
        KitFile("KIT-FILE-04", rel(KIT_DIR / "build-system-webview.sh"), "fetch and build system_webview_apk", "isolated Linux builder"),
        KitFile("KIT-FILE-05", rel(KIT_DIR / "collect-system-webview-artifact.sh"), "collect SystemWebView.apk plus manifest/SHA256/GN/revision metadata", "isolated Linux builder"),
        KitFile("KIT-FILE-06", rel(KIT_DIR / "local-intake-after-copy.sh"), "delegate returned dist to tools/r2-webview-sourcebuilt-intake.py", "Mac Smartisax workspace"),
    ]


def gates() -> list[Gate]:
    return [
        Gate("KIT-GATE-01", "RECORDED", "Stable Chromium release and checkout revision are recorded.", rel(SOURCE_BUILD_JSON), "Linux build start"),
        Gate("KIT-GATE-02", "RECORDED", "GN args, Linux builder scripts, and builder preflight are generated.", rel(KIT_DIR), "builder execution"),
        Gate("KIT-GATE-03", "MISSING", "Linux builder has not returned SystemWebView.apk yet.", "dist/sourcebuilt-system-webview-*/SystemWebView.apk", "Route A candidate audit"),
        Gate("KIT-GATE-04", "MISSING", "Returned artifact has not passed local intake.", rel(KIT_DIR / "local-intake-after-copy.sh"), "signing transition proof"),
        Gate("KIT-GATE-05", "BLOCKED_A_SIG_01", "A-SIG-01 remains blocked until candidate signing shape and adaptation proof exist.", rel(SIGNING_JSON), "ROM image design"),
    ]


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|").replace("\n", " ") for cell in row) + " |")
    return lines


def write_markdown(path: Path, release: dict[str, str], input_rows: list[KitInput], files: list[KitFile], gate_rows: list[Gate]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView Linux Builder Kit")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only/off-device handoff kit for producing the missing")
    lines.append("source-built `SystemWebView.apk` input. It does not fetch Chromium source,")
    lines.append("build WebView, download donors, build images, touch a device, flash, reboot,")
    lines.append("erase partitions, write settings, or modify `/data` on the Mac workspace.")
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    lines.append("The next real WebView modernization input is a source-built standalone")
    lines.append("`system_webview_apk` artifact with package `com.android.webview`. This kit")
    lines.append("turns the current readiness plan into Linux commands and a Mac intake loop,")
    lines.append("while keeping ROM image design blocked until the returned APK passes")
    lines.append("A-SIG-01 and Route A candidate gates.")
    lines.append("")
    lines.append("## Release Target")
    lines.append("")
    lines.extend(
        md_table(
            ["Item", "Value"],
            [
                ["version", release["version"]],
                ["milestone", release["milestone"]],
                ["checkout revision", release["checkout_revision"]],
                ["chromium hash", release["chromium_hash"]],
                ["tag status", release["tag_status"]],
            ],
        )
    )
    lines.append("")
    lines.append("## Inputs")
    lines.append("")
    lines.extend(md_table(["Input", "Status", "Value", "Evidence"], [[row.input_id, row.status, row.value, row.evidence] for row in input_rows]))
    lines.append("")
    lines.append("## Kit Files")
    lines.append("")
    lines.extend(md_table(["File", "Path", "Purpose", "Run where"], [[row.file_id, row.path, row.purpose, row.run_where] for row in files]))
    lines.append("")
    lines.append("## Gate State")
    lines.append("")
    lines.extend(md_table(["Gate", "Status", "Requirement", "Evidence", "Blocks"], [[row.gate_id, row.status, row.requirement, row.evidence, row.blocks] for row in gate_rows]))
    lines.append("")
    lines.append("## Usage")
    lines.append("")
    lines.append("On the isolated Linux builder:")
    lines.append("")
    lines.append("```bash")
    lines.append("cd /isolated/path/webview-kit")
    lines.append("chmod +x preflight-linux-builder.sh build-system-webview.sh collect-system-webview-artifact.sh")
    lines.append("MIN_FREE_GB=250 MIN_RAM_GB=16 WEBVIEW_BUILD_ROOT=/mnt/webview-build ./preflight-linux-builder.sh")
    lines.append("./build-system-webview.sh")
    lines.append("./collect-system-webview-artifact.sh")
    lines.append("```")
    lines.append("")
    lines.append("If the build root is under `/mnt` and the runner user cannot create it,")
    lines.append("the preflight script tries a narrow `sudo mkdir`/`chown` fallback before")
    lines.append("checking free space and RAM.")
    lines.append("")
    lines.append("The collection script writes `artifact-manifest.json`,")
    lines.append("`SHA256SUMS.txt`, `args.gn`, `chromium-revision.txt`, and")
    lines.append("`gn-args-expanded.txt` beside `SystemWebView.apk`. After copying the")
    lines.append("generated `dist/sourcebuilt-system-webview-*` directory back to this")
    lines.append("Mac workspace:")
    lines.append("")
    lines.append("```bash")
    lines.append("hard-rom/inspect/browser-webview-linux-builder-kit/kit/local-intake-after-copy.sh \\")
    lines.append("  /path/to/sourcebuilt-system-webview-<version>")
    lines.append("```")
    lines.append("")
    lines.append("The local script delegates to `tools/r2-webview-sourcebuilt-intake.py`,")
    lines.append("which validates the dist provenance files, copies the returned artifact")
    lines.append("into the donor inbox, records signing shape, prepares the stock-cert")
    lines.append("carrier adaptation path, runs Route A candidate audits, and refreshes")
    lines.append("the integration/design/target matrix gates.")
    lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("This kit creates the missing source-build input path only. It does not")
    lines.append("authorize a donor-backed ROM image. Image design remains blocked until")
    lines.append("local intake produces a real candidate audit PASS and A-SIG-01 adaptation")
    lines.append("proof.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Kit directory: `{rel(KIT_DIR)}`")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def write_tsv(path: Path, input_rows: list[KitInput], files: list[KitFile], gate_rows: list[Gate]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "status_or_path", "value_or_purpose", "evidence_or_location", "blocks"])
        for row in input_rows:
            writer.writerow(["input", row.input_id, row.status, row.value, row.evidence, ""])
        for row in files:
            writer.writerow(["file", row.file_id, row.path, row.purpose, row.run_where, ""])
        for row in gate_rows:
            writer.writerow(["gate", row.gate_id, row.status, row.requirement, row.evidence, row.blocks])


def write_kit_files(release: dict[str, str]) -> None:
    KIT_DIR.mkdir(parents=True, exist_ok=True)
    files = {
        "README.md": kit_readme(release),
        "gn.args": gn_args_text(),
        "preflight-linux-builder.sh": preflight_script(),
        "build-system-webview.sh": builder_script(release),
        "collect-system-webview-artifact.sh": collect_script(release),
        "local-intake-after-copy.sh": local_intake_script(release),
    }
    for name, text in files.items():
        path = KIT_DIR / name
        path.write_text(text, encoding="utf-8")
        if name.endswith(".sh"):
            path.chmod(0o755)


def main() -> int:
    release = release_info()
    input_rows = inputs(release)
    file_rows = kit_files()
    gate_rows = gates()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_kit_files(release)
    write_markdown(OUT_MD, release, input_rows, file_rows, gate_rows)
    write_tsv(OUT_TSV, input_rows, file_rows, gate_rows)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "verdict": "BUILDER_KIT_READY_ARTIFACT_MISSING",
                "donor_backed_image_allowed": False,
                "release": release,
                "inputs": [asdict(row) for row in input_rows],
                "kit_files": [asdict(row) for row in file_rows],
                "gates": [asdict(row) for row in gate_rows],
                "outputs": {
                    "markdown": rel(OUT_MD),
                    "tsv": rel(OUT_TSV),
                    "json": rel(OUT_JSON),
                    "kit_dir": rel(KIT_DIR),
                },
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print("verdict=BUILDER_KIT_READY_ARTIFACT_MISSING")
    print(f"kit_dir={rel(KIT_DIR)}")
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
