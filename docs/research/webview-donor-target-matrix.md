# WebView Donor Target Matrix

Generated: 2026-06-20 01:40:23

This is a read-only offline route matrix. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Current Decision

The first real WebView modernization target remains Route A1: a source-built or adapted standalone `com.android.webview` provider under `/product/app/webview`. It is preferred because the R2 framework whitelists only `com.android.webview`, so it can avoid framework XML work if the package contract is preserved.

The route has live-state proof, v0.31 stock provider proof,
source-built WebView material, offline A-SIG PackageManager
evidence, and the user-selected print-preserving system_b
space source. The current full M150 product_b-only image remains
blocked, and the next step is delete preflight plus extra
reserve, a smaller WebView build, or explicit low-reserve layout
acceptance.

## Evidence Gates

| Gate | Status | Evidence | Impact |
| --- | --- | --- | --- |
| framework_contract_audit | PASS | providers=com.android.webview; report=docs/research/webview-framework-contract-audit.md | Route A is valid only when the provider remains or is adapted to com.android.webview; other package names need framework work. |
| stock_webview_contract | RECORDED | package=com.android.webview; version=75.0.3770.156/377015630; sdk=min21/target30; library=libwebviewchromium.so; factoryProviderForR=True; abis=arm64-v8a,armeabi-v7a; sandbox=40/40 | This is the compatibility floor every donor/source-build target must preserve or intentionally replace. |
| v0.31_offline_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt | Offline product_b mtime-only proof exists, but it is not live proof. |
| browser_webview_live_state_capture | PASS | hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt | Current live Browser/WebView baseline is captured; rerun after v0.31 and every donor-backed flash. |
| v0.31_live_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt | No donor-backed WebView image should be built until the stock provider live gate passes or a deliberate alternate recovery path is chosen. |
| modern_donor_inbox | PASS | candidate_count=2; audit_count=2; generated=2026-06-19 23:52:02; report=hard-rom/inspect/browser-webview-donor-inbox/webview-donor-inbox-audit.json | Modern source-built/donor material is present; signing, ROM design review, and live regression gates still decide whether it can become an image. |
| a_sig_package_manager_gate | OFFLINE_PM_ACCEPTANCE_RECORDED | verdict=OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE; report=docs/research/webview-a-sig-package-manager-audit.md | Stock-carrier system-scan PackageManager acceptance is recorded offline; explicit image and live proof still gate acceptance. |
| rom_design_plan | NOT_READY | designs=3; ready_for_design_review=0; report=docs/research/webview-rom-design-plan.md | No donor-backed design is ready yet; inspect candidate blockers before image work. |
| route_a_provider_spec | RECORDED | requirements=17; gates=6; status=READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE; report=docs/research/webview-route-a-provider-spec.md | This turns Route A into concrete donor/source-build acceptance requirements before any image design. |
| route_a_candidate_audit | PASS_SHAPE | verdict=CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE; package=com.android.webview; version=150.0.7871.28/787102801; classification=standalone-webview; report=docs/research/webview-route-a-candidate-audit.md | This maps an actual or baseline candidate onto the Route A provider spec using donor and bundle audits. |
| route_a_image_capacity | BLOCKED_CAPACITY | verdict=PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY; candidate_apk=262686911; product_free=28672; report=docs/research/webview-route-a-image-capacity-audit.md | This blocks or clears physical image construction after donor shape, signing, and design review gates. |
| system_b_space_source_audit | SELECTED_LOW_RESERVE | verdict=SYSTEM_B_SPACE_SOURCE_USER_SELECTED_LOW_RESERVE; recommended=user_selected_no_projection_print_preserving; allocated=45912064; margin_to_reserved_target=-6471586; preferred_extra=smartisan_wallpapers_resource_pack; extra_allocated=86925312; extra_margin_to_reserved_target=34541662; report=docs/research/webview-system-space-source-audit.md | The user-selected print-preserving system_b space source covers the bare full-ABI shortfall, but reserve/layout acceptance or an extra source is still required. The audit currently records SmartisanWallpapers as the preferred extra-space candidate. |

## Route Matrix

| Route | Status | Class | Package target | Partition scope | Risk |
| --- | --- | --- | --- | --- | --- |
| ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW | BLOCKED_CAPACITY | preferred first real modernization target | com.android.webview | product_b /product/app/webview | ORANGE |
| ROUTE_A2_PREBUILT_STANDALONE_COM_ANDROID_WEBVIEW | ACCEPTABLE_IF_DONOR_EXISTS | acceptable if an actual standalone donor exists | com.android.webview | product_b /product/app/webview | ORANGE |
| ROUTE_B_GOOGLE_WEBVIEW_PROVIDER_ADD | DEFERRED_FRAMEWORK_GATE | framework-provider-add route | com.google.android.webview | framework-res plus product_b/system_b provider package | RED |
| ROUTE_C_TRICHROME_MULTI_PACKAGE | DEFERRED_MULTI_PACKAGE_GATE | multi-package static-library route | provider plus com.google.android.trichromelibrary or equivalent static-library package(s) | product_b/system_b multi-package layout plus possible framework provider config | RED |
| ROUTE_D_BROWSERCHROME_ENGINE_REPLACEMENT | DEFERRED_SEPARATE_TRACK | separate browser track, not a WebView provider route | com.android.browser | system_b /system/app/BrowserChrome | RED |
| ROUTE_E_LIB_ONLY_SWAP | REJECTED | rejected shortcut | com.android.webview or com.android.browser native libraries only | none | BLACK |

## ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW

| Field | Value |
| --- | --- |
| status | BLOCKED_CAPACITY |
| class | preferred first real modernization target |
| package target | com.android.webview |
| partition scope | product_b /product/app/webview |
| material needed | Source-built or adapted standalone Android 11-compatible WebView provider with package com.android.webview. |
| contract requirements | targetSdk>=30; versionCode cohort>=3770; com.android.webview.WebViewLibrary=libwebviewchromium.so; WebViewChromiumFactoryProviderForR; arm64-v8a libwebviewchromium.so; preferably keep armeabi-v7a; sandbox metadata/service count coherent; Java/native/resources version-matched. |
| image actions | Replace /product/app/webview as one version-matched provider set, bump /product/app/webview directory mtime, remove or regenerate stale oat/vdex when dex/native code changes, verify relro/webviewupdate/settings/Big Bang surfaces. |
| blockers | ROM design plan has no ready donor-backed design; current Route A product_b-only image is blocked by capacity/native-library layout; Route A candidate shape and offline A-SIG PackageManager evidence are recorded; explicit image acceptance and post-flash live regression still block acceptance |
| next offline gate | Run delete preflights for user_selected_no_projection_print_preserving, then choose extra reserve, a smaller WebView source build, or explicitly accept the low-reserve full-ABI layout before image build. |
| next live gate | After a future donor-backed image is built and explicitly confirmed, rerun the full Browser/WebView live regression suite. |
| risk | ORANGE |

## ROUTE_A2_PREBUILT_STANDALONE_COM_ANDROID_WEBVIEW

| Field | Value |
| --- | --- |
| status | ACCEPTABLE_IF_DONOR_EXISTS |
| class | acceptable if an actual standalone donor exists |
| package target | com.android.webview |
| partition scope | product_b /product/app/webview |
| material needed | A stable standalone APK/APKM/APKS/XAPK whose base provider package is com.android.webview and has no unresolved static-library dependency. |
| contract requirements | Same as Route A1, plus split layout must contain exactly one provider package and all splits/native libraries must be version-matched. |
| image actions | Promote the audited standalone donor into /product/app/webview, preserve split/base relationship, bump package directory mtime, handle stale oat/vdex, then run the full WebView live regression suite. |
| blockers | ROM design plan has no ready donor-backed design; current Route A product_b-only image is blocked by capacity/native-library layout; no local prebuilt standalone com.android.webview donor is present |
| next offline gate | Place the donor under apks/webview-donor-inbox/ and run donor inbox, donor audit, and Trichrome bundle audit. |
| next live gate | Same as Route A1: donor-backed live regression after an audited prebuilt donor image exists. |
| risk | ORANGE |

## ROUTE_B_GOOGLE_WEBVIEW_PROVIDER_ADD

| Field | Value |
| --- | --- |
| status | DEFERRED_FRAMEWORK_GATE |
| class | framework-provider-add route |
| package target | com.google.android.webview |
| partition scope | framework-res plus product_b/system_b provider package |
| material needed | Stable com.google.android.webview donor package or split bundle that passes provider/runtime gates. |
| contract requirements | All Route A runtime gates plus framework config_webview_packages.xml provider entry, provider selector behavior, system-app/signature validity, package path/mtime, and framework resource no-op/live proof. |
| image actions | Patch framework WebView provider config, ship provider as a ROM app, bump changed package directories, verify boot invariants, WebViewUpdateService valid package list, Settings selector, and rollback path. |
| blockers | ROM design plan has no ready donor-backed design; current Route A product_b-only image is blocked by capacity/native-library layout; requires framework-res config_webview_packages.xml/provider-add gate |
| next offline gate | Only design this after a real com.google.android.webview donor audit; prepare a separate framework-provider-add no-op gate. |
| next live gate | Framework/provider no-op live gate after v0.31 stock provider live proof. |
| risk | RED |

## ROUTE_C_TRICHROME_MULTI_PACKAGE

| Field | Value |
| --- | --- |
| status | DEFERRED_MULTI_PACKAGE_GATE |
| class | multi-package static-library route |
| package target | provider plus com.google.android.trichromelibrary or equivalent static-library package(s) |
| partition scope | product_b/system_b multi-package layout plus possible framework provider config |
| material needed | Version-matched provider/static-library bundle with base APKs, splits, static-library versions, and certDigest evidence when present. |
| contract requirements | All Route B gates plus PackageManager uses-static-library resolution, static library package install location, matching versions/certDigest, arm64 WebView native code, and deterministic package scan order. |
| image actions | Ship all provider/library APKs as a coherent ROM package group, preserve splits, bump all package directory mtimes, prove PackageManager static-library resolution before WebViewUpdateService selection. |
| blockers | ROM design plan has no ready donor-backed design; current Route A product_b-only image is blocked by capacity/native-library layout; requires provider plus static-library package group and install-order/cert/version proof |
| next offline gate | Run r2-webview-trichrome-bundle-audit.py on the actual bundle and produce a package-group install plan. |
| next live gate | Multi-package no-op/live package-scan gate before provider selection testing. |
| risk | RED |

## ROUTE_D_BROWSERCHROME_ENGINE_REPLACEMENT

| Field | Value |
| --- | --- |
| status | DEFERRED_SEPARATE_TRACK |
| class | separate browser track, not a WebView provider route |
| package target | com.android.browser |
| partition scope | system_b /system/app/BrowserChrome |
| material needed | BrowserChrome behavior/engine candidate that preserves Smartisan browser package, provider, resolver, icon, cache, and data contracts. |
| contract requirements | Default browser resolver, provider authorities, SmartisanApplication glue, native/dex/assets version matching, oat/vdex handling, package cache and icon redirection state. |
| image actions | Start only from v0.32 BrowserChrome stock near-noop live proof, then use candidate diff audit and package/cache regression checks. |
| blockers | v0.32 is offline-only; BrowserChrome previous same-package replacement broke boot/user UI; not a WebView modernization donor |
| next offline gate | Build a BrowserChrome candidate diff audit after v0.32 live proof, separate from WebView provider work. |
| next live gate | Live-verify v0.32 stock BrowserChrome near-noop before any behavior/engine candidate. |
| risk | RED |

## ROUTE_E_LIB_ONLY_SWAP

| Field | Value |
| --- | --- |
| status | REJECTED |
| class | rejected shortcut |
| package target | com.android.webview or com.android.browser native libraries only |
| partition scope | none |
| material needed | None; do not pursue as a ROM route. |
| contract requirements | WebView/Chromium Java glue, resources, manifest metadata, native libraries, sandbox services, and relro behavior must stay version-matched. |
| image actions | No image action should be generated for this route. |
| blockers | Java/native/resource ABI mismatch risk; cannot satisfy WebViewFactory/WebViewLibrary/sandbox/provider contracts by swapping libwebviewchromium.so alone |
| next offline gate | Keep this rejection in donor/design audits so it does not re-enter as a candidate. |
| next live gate | none |
| risk | BLACK |

## Immediate Next Step

- Current best offline step: Run delete preflights for user_selected_no_projection_print_preserving, then choose extra reserve, a smaller WebView source build, or explicitly accept the low-reserve full-ABI layout before image build.
- Current best live step: After a future donor-backed image is built and explicitly confirmed, rerun the full Browser/WebView live regression suite.
- Do not build donor-backed WebView images from the current state.
- Do not treat BrowserChrome or a native-library-only swap as a WebView provider route.

## Source Reports

- Framework contract: `docs/research/webview-framework-contract-audit.md`
- Donor source plan: `docs/research/webview-donor-source-plan.md`
- Integration plan: `docs/research/webview-integration-plan.md`
- ROM design plan: `docs/research/webview-rom-design-plan.md`
- Route A provider spec: `docs/research/webview-route-a-provider-spec.md`
- Route A candidate audit: `docs/research/webview-route-a-candidate-audit.md`
- System_b space source audit: `docs/research/webview-system-space-source-audit.md`
- Version-gap audit: `docs/research/browser-webview-version-gap-audit.md`

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-target-matrix.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-donor-target-matrix/webview-donor-target-matrix.json`
- Markdown report: `docs/research/webview-donor-target-matrix.md`
