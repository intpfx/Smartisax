# WebView Source-Build Readiness Plan

Generated: 2026-06-19 23:39:31

This is a read-only offline readiness plan for a future source-built
standalone WebView candidate. It may fetch a small Chromium Dash
release-metadata JSON, but it does not fetch Chromium source, download
donors, build images, touch a device, flash, reboot, erase partitions,
write settings, or modify `/data`.

## Current Decision

The first source-build route should target Chromium's public
`system_webview_apk` output, keep the default `com.android.webview`
package name, and treat the resulting `SystemWebView.apk` as Route A
candidate material. This matches R2's stock WebView provider whitelist
and avoids framework-provider-add work for the first modernization gate.

Source-built material is now recorded, but no donor-backed image is
allowed until A-SIG review, ROM design review, explicit image
acceptance, and live-device regression testing pass.

## Current Android Stable Release

| Item | Value |
| --- | --- |
| status | RECORDED |
| platform/channel | Android / Stable |
| version | 150.0.7871.28 |
| milestone | 150 |
| previous version | 149.0.7827.159 |
| chromium hash | 48db307645dcbaa0bb5ccee0cd096cf22971bb84 |
| branch position | 1639810 |
| tag ref | refs/tags/150.0.7871.28 |
| tag verification | PASS 48db307645dcbaa0bb5ccee0cd096cf22971bb84 |
| checkout revision | refs/tags/150.0.7871.28 |
| source | https://chromiumdash.appspot.com/fetch_releases?platform=Android&channel=Stable&num=5 |
| snapshot | hard-rom/inspect/browser-webview-source-build-readiness/chromiumdash-android-stable-latest.json |
| error |  |

## Current Local Gates

| Gate | Value |
| --- | --- |
| target_matrix | ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW |
| route_a_spec | READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE |
| route_a_candidate | CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE |
| live_state | hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt |
| v031_live | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt |
| v031_offline | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt |

## Official Source Findings

| ID | Topic | Finding | Source | Local impact |
| --- | --- | --- | --- | --- |
| OFFICIAL-01 | host | Chromium Android builds are documented for x86-64 Linux, not macOS, with at least 100 GB free space and more than 16 GB RAM recommended. | https://chromium.googlesource.com/chromium/src/+/main/docs/android_build_instructions.md | Do not try to turn the Mac Smartisax workspace into the Chromium build host. Use an isolated Linux builder if source-build work starts. |
| OFFICIAL-02 | target | The public WebView build target is system_webview_apk. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/build-instructions.md | A source-built Route A candidate should come from system_webview_apk, not Chrome, BrowserChrome, Monochrome, or a lib-only output. |
| OFFICIAL-03 | variant | AOSP system integrator guidance says most AOSP devices should use standalone WebView and that system_webview_apk produces SystemWebView.apk. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/aosp-system-integration.md | This reinforces Route A over Trichrome for the first R2 modernization candidate. |
| OFFICIAL-04 | package | system_webview_apk uses com.android.webview by default. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/build-instructions.md | This matches R2 stock config_webview_packages.xml and avoids a framework-provider-add change for the first candidate. |
| OFFICIAL-05 | release | For user-facing distribution, official guidance prefers a recent stable release tag and stable channel settings. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/aosp-system-integration.md | The first serious candidate should be stable-channel source material, not dev/canary, unless explicitly used only for shape probing. |
| OFFICIAL-06 | gn_args | Release-suitable guidance includes target_os=android, target_cpu=arm64, is_debug=false, is_official_build=true, disable_fieldtrial_testing_config=true, is_component_build=false, is_chrome_branded=false, use_official_google_api_keys=false, and android_channel=stable. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/aosp-system-integration.md | These become the minimum source-build manifest fields to capture before a source-built APK can enter Route A candidate audit. |
| OFFICIAL-07 | abi | For arm64 WebView builds, official guidance says 64-bit builds include code for both 64-bit and corresponding 32-bit architecture, and arm64 devices must use a 64-bit build. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/aosp-system-integration.md | This aligns with the R2 requirement to keep arm64-v8a mandatory and prefer retaining armeabi-v7a compatibility. |
| OFFICIAL-08 | framework | AOSP WebView providers are restricted by framework config_webview_packages.xml, and providers without configured signatures must be preinstalled or installed as updates to a preinstalled provider. | https://chromium.googlesource.com/chromium/src/+/main/android_webview/docs/aosp-system-integration.md | The R2 hard-ROM route can keep com.android.webview preinstalled in /product/app/webview and defer signature XML work. |

## Source-Build Input Manifest

| ID | Category | Status | Requirement | Expected value | Local reason |
| --- | --- | --- | --- | --- | --- |
| SB-IN-01 | host | NEEDED | Build host | isolated x86-64 Linux builder, not the Mac workspace | Chromium Android build on macOS is unsupported and the checkout/build can be very large. |
| SB-IN-02 | source | RECORDED | Chromium stable release | 150.0.7871.28 / milestone 150; checkout refs/tags/150.0.7871.28 | A stable tag keeps the WebView payload closer to a user-facing security/stability baseline. |
| SB-IN-03 | target | READY_SPEC | GN/Ninja target | system_webview_apk | This is the standalone public WebView target that keeps package com.android.webview by default. |
| SB-IN-04 | gn_args | READY_SPEC | target_os | android | Required by Chromium Android/WebView build. |
| SB-IN-05 | gn_args | READY_SPEC | target_cpu | arm64 | R2/kona is arm64 and official guidance requires arm64 WebView on arm64 devices. |
| SB-IN-06 | gn_args | READY_SPEC | package name | com.android.webview; keep default or set system_webview_package_name explicitly to this value | R2 framework whitelist already allows only com.android.webview. |
| SB-IN-07 | gn_args | READY_SPEC | release shape | is_debug=false; is_official_build=true; disable_fieldtrial_testing_config=true; is_component_build=false; android_channel=stable | Matches official release-suitable WebView guidance and avoids development-only package shape. |
| SB-IN-08 | gn_args | READY_SPEC | branding/API keys | is_chrome_branded=false; use_official_google_api_keys=false | Public AOSP-style WebView route must avoid Google-internal assumptions. |
| SB-IN-09 | artifact | RECORDED | output APK | SystemWebView.apk plus build args/version manifest | The APK alone is not enough; we need reproducibility metadata for future rebuilds. |
| SB-IN-10 | artifact | READY_SPEC | Route A audit input | place APK under apks/webview-donor-inbox/ or pass it to r2-webview-route-a-candidate-audit.py | All source-build material must pass the same candidate intake as prebuilts. |
| SB-IN-11 | artifact | NEEDED | PackageManager signing transition | stock-cert carrier adaptation, same-cert build, or a separately tested package-setting migration gate | Same-package system WebView replacement can fail before WebViewUpdateService if PackageManager cannot reconcile signatures/cached package state. |

## Gate Order

| Gate | Phase | Status | Required evidence | Blocks |
| --- | --- | --- | --- | --- |
| SB-GATE-01 | source-build-intake | READY_SPEC | Route A provider spec: READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE | source-built APK intake |
| SB-GATE-02 | stable-release-selection | RECORDED | Chromium Android Stable release: 150.0.7871.28; tag=PASS 48db307645dcbaa0bb5ccee0cd096cf22971bb84; snapshot=hard-rom/inspect/browser-webview-source-build-readiness/chromiumdash-android-stable-latest.json | Linux builder checkout |
| SB-GATE-03 | source-build-material | RECORDED | Stable release tag, GN args, build command transcript, SystemWebView.apk, and artifact hashes from an isolated Linux builder. | Route A candidate audit |
| SB-GATE-04 | source-build-adaptation | PENDING_A_SIG_REVIEW | PackageManager signing transition evidence for same-package com.android.webview replacement. | ROM image design |
| SB-GATE-05 | candidate-audit | CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE | Current Route A candidate audit: CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE | integration and ROM design plan |
| SB-GATE-06 | live-baseline | RECORDED | Browser/WebView live-state evidence: hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt | donor-backed image design |
| SB-GATE-07 | v0.31-live-provider-proof | RECORDED | v0.31 live provider proof: hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt; offline proof: hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt | donor-backed image build/flash |

## Linux Builder Command Plan

Run this only on an isolated x86-64 Linux builder with enough disk and RAM,
not on the Mac project workspace.

### SB-CMD-01 host

```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
```

Install depot_tools on the isolated Linux builder.

### SB-CMD-02 host

```bash
export PATH="$PWD/depot_tools:$PATH"
```

Put depot_tools in PATH for fetch/gclient/autoninja.

### SB-CMD-03 checkout

```bash
mkdir chromium-webview && cd chromium-webview
```

Create a checkout root with no spaces in the path.

### SB-CMD-04 checkout

```bash
fetch --nohooks --no-history android
```

Fetch Android Chromium source with reduced history.

### SB-CMD-05 checkout

```bash
cd src
```

Enter the Chromium source root.

### SB-CMD-06 checkout

```bash
git fetch origin refs/tags/150.0.7871.28
```

Fetch the selected Android Stable release revision.

### SB-CMD-07 checkout

```bash
git checkout -b smartisax-webview-150.0.7871.28 refs/tags/150.0.7871.28
```

Create a named local branch for reproducibility.

### SB-CMD-08 deps

```bash
build/install-build-deps.sh
```

Install Linux and Android build dependencies on the builder.

### SB-CMD-09 deps

```bash
gclient sync --no-history
```

Sync dependencies at the selected Chromium revision.

### SB-CMD-10 deps

```bash
gclient runhooks
```

Run Chromium hooks after dependency sync.

### SB-CMD-11 config

```bash
mkdir -p out/SmartisaxWebView
```

Create the dedicated WebView output directory.

### SB-CMD-12 config

```bash
gn args out/SmartisaxWebView
```

Open GN args and paste the source-build manifest values below.

### SB-CMD-13 config

```gn
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_official_build = true
disable_fieldtrial_testing_config = true
is_component_build = false
is_chrome_branded = false
use_official_google_api_keys = false
android_channel = "stable"
system_webview_package_name = "com.android.webview"
```

GN args for the first R2 Route A source-built standalone WebView candidate.

### SB-CMD-14 build

```bash
autoninja -C out/SmartisaxWebView system_webview_apk
```

Build the standalone WebView APK.

### SB-CMD-15 artifact

```bash
find out/SmartisaxWebView -name 'SystemWebView.apk' -o -name '*WebView*.apk'
```

Locate the APK output and copy it plus build metadata back to Smartisax.

## First Candidate Intake Command

After a Linux builder produces a stable `SystemWebView.apk`, copy only the
APK and a small build manifest into `apks/webview-donor-inbox/`, then run:

```bash
tools/r2-webview-route-a-candidate-audit.py \
  apks/webview-donor-inbox/SystemWebView.apk \
  --label sourcebuilt-system-webview-150-0-7871-28
tools/r2-webview-donor-inbox-audit.py
tools/r2-webview-donor-target-matrix.py
tools/r2-webview-integration-plan.py
tools/r2-webview-rom-design-plan.py
```

Before a ROM image can be designed, also prove the same-package signing
transition for `com.android.webview`: stock-cert carrier adaptation, a
same-cert build, or a separately tested package-setting migration gate.

## Boundary

This plan authorizes only future source-build intake and static auditing.
It does not authorize Chromium checkout on the Mac, use of the LiveSystem
server, ROM image generation, flashing, or any `/data` write. A real
candidate still needs signing-transition proof,
Route A candidate review, integration-plan readiness, and ROM-design
readiness before image work. Browser/WebView live-state and v0.31 stock
provider proof are currently recorded, and must be rerun after any future
donor-backed flash.

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-source-build-readiness-plan.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json`
- Markdown report: `docs/research/webview-source-build-readiness-plan.md`
