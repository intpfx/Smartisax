# Browser/WebView Version Gap Audit

Generated: 2026-06-19 12:01:47

This is a read-only offline audit. It inspects stock APKs and existing
Smartisax gate reports. It does not download donors, build images, touch a
device, flash, reboot, erase partitions, write settings, or modify `/data`.

## Decision

The first real modernization target should be the system WebView provider, not
the full BrowserChrome app shell.

- BrowserChrome stock app version is `9.0.6.4` and its Chromium
  payload exposes version signal(s) `90.0.4430.82, 90.0.4430.210`. It has a large
  Smartisan/Chromium app-shell surface: `6` dex files,
  `28` native libraries, `13` providers,
  and `35` exported components.
- WebView stock version is `75.0.3770.156` with engine signal(s)
  `75.0.3770.156`. It is much older but has a narrower Android WebView
  provider contract under `/product/app/webview`.
- Therefore, the next donor-backed work should prefer a standalone
  `com.android.webview` Route A/adapt-in-place candidate after v0.31 live proof.
  BrowserChrome engine replacement remains behind the v0.32 live no-op gate and
  a separate candidate-diff audit.

## Baseline

| Item | Status | Observed | Implication | Next gate |
| --- | --- | --- | --- | --- |
| stock BrowserChrome version | RECORDED | package=com.android.browser; appVersion=9.0.6.4/20211218; targetSdk=28; compileSdk=30; engineVersions=90.0.4430.82, 90.0.4430.210; milestones=90; confidence=payload-string | BrowserChrome is a Smartisan browser shell with Chromium payload signals around M90, targetSdk 28, 13 providers, and 35 exported components. | Keep BrowserChrome behind v0.32 stock near-noop/live proof before any behavior or engine replacement. |
| stock WebView version | RECORDED | package=com.android.webview; appVersion=75.0.3770.156/377015630; targetSdk=30; compileSdk=29; engineVersions=75.0.3770.156; milestones=75; confidence=manifest | System WebView is much older at M75 even though it already targets Android 11 WebViewUpdater's targetSdk 30 gate. | Prioritize WebView provider modernization before BrowserChrome engine replacement. |

## Version Gap

| Item | Status | Observed | Implication | Next gate |
| --- | --- | --- | --- | --- |
| BrowserChrome versus WebView engine gap | ACTIONABLE | BrowserChrome milestone=90; WebView milestone=75; delta=15 | The default browser is roughly 15 Chromium milestones newer than the system WebView. Updating WebView is the larger compatibility win and has a cleaner provider contract. | Treat WebView Route A/B/C donor selection as the next real modernization track. |

## Payload Shape

| Item | Status | Observed | Implication | Next gate |
| --- | --- | --- | --- | --- |
| BrowserChrome payload shape | RED | size=244579729; dex=6; libs=28; libs_by_abi={'arm64-v8a': 28}; key_libs=['libchrome.so']; assets=376 | BrowserChrome modernization cannot be a libchrome.so-only transplant; Java glue, resources, providers, OAT/VDEX, icon redirection, and app data have to move as a version-matched unit. | After v0.32 live proof, build a candidate diff auditor before attempting a BrowserChrome behavior APK. |
| WebView payload shape | ORANGE | size=141674094; dex=1; libs=2; libs_by_abi={'arm64-v8a': 1, 'armeabi-v7a': 1}; key_libs=['libwebviewchromium.so']; assets=60 | WebView is a narrower provider unit, but Java/native/assets/sandbox services must still remain version-matched. Split APK or Trichrome donors widen the ROM design. | Use donor and Trichrome bundle audits before image design. |

## Route Decisions

| Item | Status | Observed | Implication | Next gate |
| --- | --- | --- | --- | --- |
| preferred first modernization route | ROUTE_A_FIRST | Adapt or source-build a standalone com.android.webview provider into /product/app/webview after v0.31 live proof. | This avoids framework-res provider whitelist edits and keeps the first real image product_b-only if the donor can satisfy the stock com.android.webview contract. | Choose an actual donor and rerun inbox, donor, bundle, integration, and ROM-design plans. |
| rejected shortcut routes | BLOCKED | BrowserChrome-as-WebView, lib-only swaps, direct com.google.android.webview without framework config, and Trichrome single-APK overwrite. | These routes violate WebViewUpdater provider rules, static-library/package-group requirements, or BrowserChrome same-package contracts. | Keep route-specific gates instead of forcing a simpler-looking replacement. |

## Current Gates

| Item | Status | Observed | Implication | Next gate |
| --- | --- | --- | --- | --- |
| v0.31 stock WebView provider near-noop | PASS_OFFLINE | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-032353.txt | Offline product_b mtime-only WebView provider gate exists but is not live-verified. | Resolve ADB/live-state or use explicit manual fastboot flow only with clear reduced verification. |
| v0.32 stock BrowserChrome near-noop | PASS_OFFLINE | hard-rom/inspect/v0.32-browserchrome-stock-near-noop/verify-v0.32-browserchrome-stock-near-noop-offline-image-20260619-115109.txt | Offline system_b mtime-only BrowserChrome gate exists but is not live-verified. | Do not build BrowserChrome behavior replacements until this gate boots and verifies through keyguard/launcher/resolver. |
| live-state and live no-op proof | MISSING | live_state=hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-112934.txt; v0.31_device=missing; v0.32_device=missing | ADB currently blocks automated live-state capture and post-flash verification. This does not block offline analysis, but it blocks treating any provider/browser gate as proven on device. | Treat ADB recovery as a separate live-device task before flashing modernization candidates. |

## Donor State

| Item | Status | Observed | Implication | Next gate |
| --- | --- | --- | --- | --- |
| modern donor inventory | MISSING | candidate_count=0; build_ready=0 | No actual modern donor material is currently in the project inbox, so the only build plan remains stock baseline/design-only. | Put a donor APK/APKM/APKS/XAPK into apks/webview-donor-inbox or provide a source-built output directory, then rerun the donor pipeline. |

## Next Offline Step

Create or obtain actual WebView donor material, then run:

```bash
tools/r2-webview-donor-inbox-audit.py --include-downloads
tools/r2-webview-integration-plan.py
tools/r2-webview-rom-design-plan.py
```

Do not build a donor-backed image until the donor audit, Trichrome/static
library bundle audit, integration plan, and ROM design plan all agree on the
same route.

## Outputs

- Markdown report: `docs/research/browser-webview-version-gap-audit.md`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/browser-webview-version-gap-audit.tsv`
- JSON report: `hard-rom/inspect/browser-webview-version-gap-audit/browser-webview-version-gap-audit.json`
