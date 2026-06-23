# WebView Donor Source Plan

Generated: 2026-06-19 03:18:38

This is a read-only offline planning report. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Current Baseline

| Item | Value |
| --- | --- |
| stock package | com.android.webview |
| stock version | 75.0.3770.156 / 377015630 |
| stock SDK | min=21 target=30 |
| stock ABIs | arm64-v8a, armeabi-v7a |
| Android 11 factory class present | True |
| stock route | adapt-in-place: replace stock com.android.webview provider under /product/app/webview |
| stock bundle audit | PASS_STANDALONE / standalone-webview |
| inbox candidates | 0 |
| inbox generated | 2026-06-19 03:12:23 |

Current inbox scan result: no external modern donor package is present in
the project donor inboxes or Downloads.

## Public Source Snapshot

| Source | Snapshot | Use |
| --- | --- | --- |
| Google Play stable Android System WebView | Google LLC listing; updated on 2026-06-17 in the 2026-06-19 web snapshot. | Confirms the stable Google WebView channel is active, but the Play page is metadata only and not a raw APK source. URL: https://play.google.com/store/apps/details?id=com.google.android.webview |
| Google Play Android System WebView Dev | Google LLC listing; dev channel says it updates weekly and was updated on 2026-06-18 in the 2026-06-19 web snapshot. | Useful for shape/probing only; do not use dev/canary as the first stable ROM donor. URL: https://play.google.com/store/apps/details?id=com.google.android.webview.dev |
| Chrome for Developers WebView overview | Last updated 2024-12-18 in the page snapshot. | Confirms WebView is Chromium-based, shares the rendering engine with Chrome for Android, and is updateable separately from Android. URL: https://developer.chrome.com/docs/webview |

## Donor Route Priority

| Route | Priority | Donor material | ROM design | Blockers | Next gate |
| --- | --- | --- | --- | --- | --- |
| A | P0 preferred first donor class | Standalone or source-built provider whose manifest package is already com.android.webview. | Adapt in place under /product/app/webview after v0.31 live proof. | Modern public Google builds may no longer be standalone com.android.webview; if static libraries appear, route A is invalid. | Run r2-webview-donor-inbox-audit.py, require donor audit PASS or an explicitly accepted WARN, then design a product_b replacement candidate. |
| B | P1 likely modern Google stable route | com.google.android.webview stable donor from a user-provided Play or device-extraction bundle. | Framework provider add: patch framework-res config_webview_packages.xml and ship the provider as a product/system app. | framework-res is a RED early-boot asset; provider package is not whitelisted by stock config; first framework resource no-op/live gate is required before this route is flashable. | Audit donor with --allow-framework-config-patch only for design; build a framework/provider no-op chain before behavior integration. |
| C | P2 common current Google package shape | Trichrome/static shared-library WebView bundle, normally provider plus com.google.android.trichromelibrary and matching splits. | Multi-package product/system ROM design plus framework provider add or package adaptation. | Not a single APK replacement. Missing or mismatched static libraries can break package scan before WebViewUpdateService is reached. | Run r2-webview-trichrome-bundle-audit.py on the actual bundle and require resolved provider/library/static cert/version evidence before any image build. |
| D | P3 controlled but heavy route | Self-built Chromium/AOSP WebView for Android 11/R, targeting com.android.webview. | Adapt in place under /product/app/webview, potentially safest long-term once build reproducibility exists. | High build cost, toolchain storage/time, Chromium branch compatibility, and signing/package metadata details. | Only start after route A/B/C donor audit proves public packages are blocked or too coupled. |
| E | Reject for first integration | Chrome/Browser APK or stock BrowserChrome as a WebView donor. | Do not use as WebView donor. | Stock BrowserChrome negative audit already FAILs WebView donor gates; v0.3/v0.3.1 browser replacement broke boot/user UI. | Keep BrowserChrome as a separate later no-op gate, not part of WebView provider modernization. |

## Version And Compatibility Rules

| Rule | Category | Requirement | Reason | Evidence |
| --- | --- | --- | --- | --- |
| R1 | version | Prefer stable WebView channel for the first donor-backed ROM. | Dev/Beta/Canary are useful for shape reconnaissance but too volatile for a base ROM provider. | Google Play stable/dev listings and project rollback policy. |
| R2 | version | Donor versionCode / 100000 must be >= stock factory cohort. | Smartisan Android 11 WebViewUpdater compares provider cohorts against the minimum available-by-default provider. | services.jar WebViewUpdater and stock donor audit. |
| R3 | sdk | targetSdkVersion must be >= 30 and minSdkVersion must be <= 30. | R2 is Android 11/API 30 and WebViewUpdater enforces correct target SDK. | stock WebView donor audit gates. |
| R4 | runtime | Donor must include WebViewLibrary metadata and matching libwebviewchromium.so. | WebViewFactory.getWebViewLibrary must resolve a native library that exists in the provider or split set. | stock WebView donor audit gates. |
| R5 | runtime | Donor dex must contain com.android.webview.chromium.WebViewChromiumFactoryProviderForR or an explicitly framework-compatible substitute. | R2 framework.jar loads the Android 11/R factory provider class. | framework.jar WebViewFactory and donor audit. |
| R6 | abi | arm64-v8a is mandatory; retain armeabi-v7a unless a live audit proves all dependent app paths are 64-bit-only. | Stock WebView ships both arm64 and 32-bit libraries, and the ROM may still run 32-bit apps. | stock APK inventory. |
| R7 | package | One-package donors can use adapt-in-place only if package is com.android.webview. | Stock framework-res whitelists only com.android.webview. | config_webview_packages.xml. |
| R8 | package | Any com.google.android.webview donor needs framework-provider-add or package adaptation. | The provider is invisible to WebViewUpdateService until framework config exposes it. | config_webview_packages.xml and donor route model. |
| R9 | package | Any uses-static-library or Trichrome reference turns the work into a multi-package ROM design. | PackageManager must resolve static shared libraries before the provider can even be considered valid. | donor audit static_library_dependencies gate. |
| R9b | package | Trichrome bundles must pass the dedicated bundle audit before image design. | The package group must prove one provider, one base APK per package, matching static-library versions, certDigest evidence when available, and arm64 WebView native code. | tools/r2-webview-trichrome-bundle-audit.py. |
| R10 | rom | Bump provider package directory mtime and remove/regenerate stale oat/vdex when dex/native code changes. | Android 11 PackageCacher can reuse stale parsed package data when directory mtimes do not advance. | v0.26a.1/v0.26a.2 lessons and v0.31 design. |
| R11 | live | v0.31 stock provider must be live-proven before a donor-backed image. | Need to prove WebViewUpdateService and PackageCacher tolerate the product_b mtime-only gate on this device. | v0.31 offline candidate status. |
| R12 | regression | Post-boot gates must include relro/webviewupdate, Settings WebView selector, Smartisan Big Bang/WebView surfaces, browser resolver, keyguard, and launcher. | WebView is a core runtime provider and Smartisan Settings warns non-built-in WebView can affect Big Bang/WebView features. | v0.30 audit and SettingsSmartisan source. |

## Immediate Next Step

1. Keep v0.31 as the next live provider gate; it is still the proof that
   stock WebView survives product_b package-directory mtime refresh on R2.
2. For donor work, place the actual stable donor bundle under
   `apks/webview-donor-inbox/` and run
   `tools/r2-webview-donor-inbox-audit.py --include-downloads`.
3. If the donor reports any Trichrome/static-library refs, run
   `tools/r2-webview-trichrome-bundle-audit.py <bundle>` and treat it as
   route C, not as a single-APK product replacement.
4. If the donor package is `com.google.android.webview`, treat it as route B
   or C until framework/provider config work is explicitly gated.
5. Run `tools/r2-webview-integration-plan.py` after donor intake to turn
   donor/bundle audit outputs into explicit Route A/B/C image-design
   blockers and next gates.

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-source-plan.tsv`
- Markdown report: `docs/research/webview-donor-source-plan.md`
