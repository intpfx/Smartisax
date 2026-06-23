# WebView Linux Builder Kit

Generated: 2026-06-19 16:10:22

This is a read-only/off-device handoff kit for producing the missing
source-built `SystemWebView.apk` input. It does not fetch Chromium source,
build WebView, download donors, build images, touch a device, flash, reboot,
erase partitions, write settings, or modify `/data` on the Mac workspace.

## Decision

The next real WebView modernization input is a source-built standalone
`system_webview_apk` artifact with package `com.android.webview`. This kit
turns the current readiness plan into Linux commands and a Mac intake loop,
while keeping ROM image design blocked until the returned APK passes
A-SIG-01 and Route A candidate gates.

## Release Target

| Item | Value |
| --- | --- |
| version | 150.0.7871.28 |
| milestone | 150 |
| checkout revision | refs/tags/150.0.7871.28 |
| chromium hash | 48db307645dcbaa0bb5ccee0cd096cf22971bb84 |
| tag status | PASS 48db307645dcbaa0bb5ccee0cd096cf22971bb84 |

## Inputs

| Input | Status | Value | Evidence |
| --- | --- | --- | --- |
| KIT-IN-01 | RECORDED | 150.0.7871.28 | hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json |
| KIT-IN-02 | RECORDED | refs/tags/150.0.7871.28 | hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json |
| KIT-IN-03 | RECORDED | system_webview_apk / com.android.webview | hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json |
| KIT-IN-04 | False | donor-backed image allowed flag | hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json |
| KIT-IN-05 | BLOCKED_A_SIG_01 | A-SIG-01 signing-transition state | hard-rom/inspect/browser-webview-signing-transition/webview-signing-transition-plan.json |
| KIT-IN-06 | READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE | Route A provider spec | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |

## Kit Files

| File | Path | Purpose | Run where |
| --- | --- | --- | --- |
| KIT-FILE-01 | hard-rom/inspect/browser-webview-linux-builder-kit/kit/README.md | builder instructions and boundaries | read on Mac and Linux |
| KIT-FILE-02 | hard-rom/inspect/browser-webview-linux-builder-kit/kit/gn.args | exact WebView GN args | Linux builder |
| KIT-FILE-03 | hard-rom/inspect/browser-webview-linux-builder-kit/kit/preflight-linux-builder.sh | check Linux/x86-64, disk, RAM, and build path before fetch/build | isolated Linux builder |
| KIT-FILE-04 | hard-rom/inspect/browser-webview-linux-builder-kit/kit/build-system-webview.sh | fetch and build system_webview_apk | isolated Linux builder |
| KIT-FILE-05 | hard-rom/inspect/browser-webview-linux-builder-kit/kit/collect-system-webview-artifact.sh | collect SystemWebView.apk plus manifest/SHA256/GN/revision metadata | isolated Linux builder |
| KIT-FILE-06 | hard-rom/inspect/browser-webview-linux-builder-kit/kit/local-intake-after-copy.sh | delegate returned dist to tools/r2-webview-sourcebuilt-intake.py | Mac Smartisax workspace |

## Gate State

| Gate | Status | Requirement | Evidence | Blocks |
| --- | --- | --- | --- | --- |
| KIT-GATE-01 | RECORDED | Stable Chromium release and checkout revision are recorded. | hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json | Linux build start |
| KIT-GATE-02 | RECORDED | GN args, Linux builder scripts, and builder preflight are generated. | hard-rom/inspect/browser-webview-linux-builder-kit/kit | builder execution |
| KIT-GATE-03 | MISSING | Linux builder has not returned SystemWebView.apk yet. | dist/sourcebuilt-system-webview-*/SystemWebView.apk | Route A candidate audit |
| KIT-GATE-04 | MISSING | Returned artifact has not passed local intake. | hard-rom/inspect/browser-webview-linux-builder-kit/kit/local-intake-after-copy.sh | signing transition proof |
| KIT-GATE-05 | BLOCKED_A_SIG_01 | A-SIG-01 remains blocked until candidate signing shape and adaptation proof exist. | hard-rom/inspect/browser-webview-signing-transition/webview-signing-transition-plan.json | ROM image design |

## Usage

On the isolated Linux builder:

```bash
cd /isolated/path/webview-kit
chmod +x preflight-linux-builder.sh build-system-webview.sh collect-system-webview-artifact.sh
MIN_FREE_GB=250 MIN_RAM_GB=16 WEBVIEW_BUILD_ROOT=/mnt/webview-build ./preflight-linux-builder.sh
./build-system-webview.sh
./collect-system-webview-artifact.sh
```

If the build root is under `/mnt` and the runner user cannot create it,
the preflight script tries a narrow `sudo mkdir`/`chown` fallback before
checking free space and RAM.

The collection script writes `artifact-manifest.json`,
`SHA256SUMS.txt`, `args.gn`, `chromium-revision.txt`, and
`gn-args-expanded.txt` beside `SystemWebView.apk`. After copying the
generated `dist/sourcebuilt-system-webview-*` directory back to this
Mac workspace:

```bash
hard-rom/inspect/browser-webview-linux-builder-kit/kit/local-intake-after-copy.sh \
  /path/to/sourcebuilt-system-webview-<version>
```

The local script delegates to `tools/r2-webview-sourcebuilt-intake.py`,
which validates the dist provenance files, copies the returned artifact
into the donor inbox, records signing shape, prepares the stock-cert
carrier adaptation path, runs Route A candidate audits, and refreshes
the integration/design/target matrix gates.

## Boundary

This kit creates the missing source-build input path only. It does not
authorize a donor-backed ROM image. Image design remains blocked until
local intake produces a real candidate audit PASS and A-SIG-01 adaptation
proof.

## Outputs

- Markdown report: `docs/research/webview-linux-builder-kit.md`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-linux-builder-kit.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-linux-builder-kit/webview-linux-builder-kit.json`
- Kit directory: `hard-rom/inspect/browser-webview-linux-builder-kit/kit`
