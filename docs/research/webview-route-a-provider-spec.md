# WebView Route A Provider Spec

Generated: 2026-06-19 23:53:59

This is a read-only offline specification for a future Route A WebView
provider. It does not download donors, build images, touch a device,
flash, reboot, erase partitions, write settings, or modify `/data`.

## Decision

Route A means: keep the provider package as `com.android.webview` and
replace `/product/app/webview` only after the v0.31 live provider gate
has passed. This avoids early framework XML/provider-add risk.

The spec is now ready for donor/source-build intake, but no donor-backed
image is authorized from the current state.

## Stock Reference

| Item | Value |
| --- | --- |
| package | com.android.webview |
| version | 75.0.3770.156 / 377015630 |
| sdk | min=21 target=30 |
| application | com.android.webview.chromium.WebViewApplication |
| WebViewLibrary | libwebviewchromium.so |
| ABIs | arm64-v8a,armeabi-v7a |
| sandbox | 40/40 |
| privileged | 0/0 |
| stock apk sha256 | 11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97 |

## Source Evidence

| Source | Status | Evidence |
| --- | --- | --- |
| framework_contract | PASS | hard-rom/inspect/browser-webview-framework-contract/webview-framework-contract-audit.json |
| target_matrix | ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW | hard-rom/inspect/browser-webview-donor-target-matrix/webview-donor-target-matrix.json |
| stock_donor_selftest | PASS | hard-rom/inspect/browser-webview-donor/stock-webview-selftest/webview-donor-audit.json |
| stock_bundle_selftest | PASS_STANDALONE | hard-rom/inspect/browser-webview-trichrome-bundle/stock-webview-standalone/trichrome-bundle-audit.json |
| integration_plan | build_ready=2 | hard-rom/inspect/browser-webview-integration-plan/webview-integration-plan.json |
| v0.31_offline_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt |
| browser_webview_live_state | PASS | hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt |
| v0.31_live_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt |

## Requirements

### artifact_identity

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-ID-01 | MUST | The Route A provider package name must be com.android.webview. | framework config_webview_packages.xml whitelists only com.android.webview. | Donor audit package_identity PASS and bundle audit framework_provider_route PASS. | Base provider package is com.google.android.webview, com.android.browser, or any package other than com.android.webview. | Non-com.android.webview material moves to Route B/C and must not be built as Route A. |
| A-ID-02 | MUST | The provider must be standalone for Route A: one WebView provider package plus optional splits for the same package, with no unresolved uses-static-library dependencies. | stock WebView bundle classification is standalone-webview. | Trichrome bundle audit bundle_classification PASS with standalone-webview and static_library_resolution PASS. | Any com.google.android.trichromelibrary or uses-static-library dependency is present. | Move to Route C multi-package design. |

### live_verification

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-LIVE-01 | MUST | Before any donor-backed flash, capture current Browser/WebView live state and live-verify v0.31 stock provider near-noop. | current matrix has live-state and v0.31 live gates PASS; this baseline must be preserved and rerun after any donor-backed flash. | browser-webview-live-state report PASS and v0.31 device verifier PASS. | Donor image is built/flashed without current live-state and v0.31 stock-provider baseline evidence. | Cannot distinguish donor regression from existing USB/package-cache state. |
| A-LIVE-02 | MUST | After donor-backed boot, verify sys.boot_completed, slot, root, keyguard/launcher, package path/hash, cmd webviewupdate, relro/native load, Settings WebView selector, and Smartisan Big Bang/WebView surfaces. | SettingsSmartisan source delegates to IWebViewUpdateService and warns that non-built-in WebView can affect Big Bang/WebView features. | Device verifier report covers all listed surfaces with no fatal WebView/PackageManager logs. | Verifier checks only package installation or only boot completion. | A broad WebView provider regression can be missed. |

### manifest_runtime

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-MAN-01 | MUST | AndroidManifest.xml must expose com.android.webview.WebViewLibrary=libwebviewchromium.so or an intentionally framework-compatible equivalent backed by the same native library name. | stock WebViewLibrary metadata points to libwebviewchromium.so. | Donor audit webview_library_metadata and webview_native_library_present PASS. | WebViewLibrary metadata is missing, empty, or points to a library absent from the package/splits. | WebViewFactory.getWebViewLibrary returns null or native load fails. |
| A-MAN-02 | MUST | Dex must contain com.android.webview.chromium.WebViewChromiumFactoryProviderForR or proven Android 11-compatible glue for that class name. | R2 framework.jar loads WebViewChromiumFactoryProviderForR. | Donor audit android11_factory_provider_class PASS. | Factory provider class is absent and no compatibility bridge is provided. | WebViewFactory cannot instantiate the provider. |
| A-MAN-03 | MUST | Sandbox and privileged service metadata must match declared service counts. | stock sandbox services are 40/40 and privileged services are 0/0. | Donor audit sandbox_service_contract PASS and bundle audit records matching metadata/service declarations. | NUM_SANDBOXED_SERVICES or NUM_PRIVILEGED_SERVICES disagrees with manifest declarations. | Chromium renderer service launch can fail after boot. |

### native_abi

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-ABI-01 | MUST | arm64-v8a libwebviewchromium.so must be present and version-matched with Java/resources. | R2/kona is arm64 and stock WebView includes arm64-v8a libwebviewchromium.so. | Donor audit arm64_runtime PASS and native library hash inventory recorded. | arm64 libwebviewchromium.so is missing or borrowed from a different version set. | Native WebView load or relro creation can fail. |
| A-ABI-02 | SHOULD | Retain armeabi-v7a libwebviewchromium.so unless a live audit proves all relevant app paths are 64-bit-only. | stock WebView includes armeabi-v7a and use32bitAbi=true. | Donor audit arm32_app_compat PASS, or a documented accepted warning before image design. | 32-bit library missing with no accepted compatibility review. | 32-bit WebView users may regress. |

### package_cache

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-CACHE-01 | MUST | Bump /product/app/webview package directory mtime beyond stale package_cache entries. | v0.26a.1 proved Android 11 PackageCacher can reuse stale ParsedPackage data when directory mtime is old. | Offline verifier records package directory mtime and live verifier confirms PackageManager sees expected package/hash. | APK changes but package directory mtime is not advanced. | PackageManager can parse stale WebView metadata. |
| A-CACHE-02 | MUST | Remove or regenerate stale /product/app/webview/oat/vdex artifacts when dex/native code changes. | target matrix records stale oat/vdex handling as a Route A image action. | Image verifier records oat/vdex absence or expected regenerated state. | Changed dex/native package leaves stock oat/vdex in place without proof it is ignored. | Boot/runtime can execute mismatched optimized code. |

### package_signature

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-SIG-01 | MUST | A source-built same-package WebView must have an explicit PackageManager signing transition plan before ROM image design. | v0.26a/v0.26a.1 proved Android 11 system-package scans depend on a readable APK v2 signing block as the certificate carrier when payload digests no longer verify. | Candidate intake records either stock-cert-carrier adaptation evidence, a same-cert signed build, or a deliberately tested package-setting migration gate. | Source-built SystemWebView.apk is promoted directly with a different signing certificate and no same-package transition proof. | PackageManager may reject or stale-cache the provider before WebViewUpdateService can evaluate it. |

### rejected_shortcuts

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-REJ-01 | MUST_NOT | Do not treat BrowserChrome, Chrome, Quark, or a native-library-only swap as a Route A WebView provider. | BrowserChrome negative audit fails provider whitelist, targetSdk, WebViewLibrary/native lib, and factory class gates; target matrix rejects lib-only swaps. | Candidate source is explicitly com.android.webview and passes donor/bundle audits. | Candidate is a browser APK or only libwebviewchromium.so is replaced. | This reopens the v0.3/v0.3.1 failure class or creates Java/native ABI mismatch. |

### rom_layout

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-ROM-01 | MUST | First Route A image scope is product_b /product/app/webview only after v0.31 live proof. | v0.31 stock near-noop is the current product_b WebView freshness gate. | ROM design plan references v0.31 live PASS before donor-backed image generation. | A donor-backed image is built directly from v0.29 or changes framework/system without a separate gate. | Build path bypasses the WebView package-cache freshness proof. |
| A-ROM-02 | MUST | Use the shared-block-safe replacement pattern for product ext4 contents and verify dumped APK hashes after e2fsck. | project build rules require held-stock inode replacement on shared_blocks images. | Offline verifier records e2fsck, dumped APK sha256, ZIP integrity, and sparse product_b slice equality. | debugfs rm + write is used on shared_blocks without held-stock protection. | e2fsck can repair shared blocks by corrupting the replacement APK. |

### version_sdk

| ID | Level | Requirement | Stock reference | Acceptance evidence | Fail condition | Route impact |
| --- | --- | --- | --- | --- | --- | --- |
| A-SDK-01 | MUST | targetSdkVersion must be >= 30 and minSdkVersion must be <= 30. | stock targetSdk=30, minSdk=21; Android 11 WebViewUpdater enforces targetSdk >= 30. | Donor audit min_sdk_device_compat and target_sdk_webviewupdater PASS. | targetSdkVersion < 30 or minSdkVersion > 30. | Provider is rejected before runtime loading. |
| A-VER-01 | MUST | versionCode / 100000 cohort must be >= stock floor 3770. | stock versionCode=377015630; framework floor cohort=3770. | Donor audit version_code_cohort PASS and records donor versionName/versionCode. | Donor versionCode cohort is below 3770 or malformed. | WebViewUpdater can reject the provider even if versionName looks modern. |

## Gate Order

| Phase | Gate | Status | Expected evidence | Blocks |
| --- | --- | --- | --- | --- |
| donor_intake | A-GATE-01 | READY_FOR_FUTURE_INPUT | Run tools/r2-webview-donor-inbox-audit.py on actual donor/source-build output, then inspect donor and bundle JSON. | Any Route A donor/source-build promotion. |
| donor_intake | A-GATE-02 | REQUIRED | Donor audit verdict PASS and Trichrome bundle audit verdict PASS_STANDALONE. | ROM image design. |
| image_design | A-GATE-03 | REQUIRED | tools/r2-webview-integration-plan.py and tools/r2-webview-rom-design-plan.py report a modern candidate ready for design review. | ROM builder implementation. |
| live_precondition | A-GATE-04 | RECORDED_BASELINE | Browser/WebView live-state capture PASS and v0.31 stock provider live verifier PASS. | Future donor-backed image build/flash still needs a real modern candidate and image verifier. |
| offline_image | A-GATE-05 | FUTURE_REQUIRED | Offline image verifier proves product_b-only scope, e2fsck, dumped provider hashes, package directory mtime, oat/vdex policy, donor/bundle audit PASS, and sparse slice equality. | Flash preflight. |
| live_candidate | A-GATE-06 | FUTURE_REQUIRED | Post-boot verifier covers boot, slot, root, keyguard/launcher, PackageManager path/hash, webviewupdate, relro/native load, Settings selector, Big Bang/WebView surfaces, and logs. | Accepting a modern WebView provider candidate. |

## Current Blockers

- No modern source-built/adapted standalone `com.android.webview` output is present yet.
- Source-built same-package signing/certificate-carrier transition is not proven yet.
- Donor-backed image generation is still deferred until a real candidate passes Route A intake, integration, and ROM design gates.

## Next Offline Step

Produce or obtain one Route A candidate directory/archive, then run donor
and Trichrome bundle audits against it. The candidate must not enter ROM
image design until every MUST requirement above has concrete evidence.

## Source Reports

- Framework contract: `docs/research/webview-framework-contract-audit.md`
- Target matrix: `docs/research/webview-donor-target-matrix.md`
- Integration plan: `docs/research/webview-integration-plan.md`
- ROM design plan: `docs/research/webview-rom-design-plan.md`

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-provider-spec.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json`
- Markdown report: `docs/research/webview-route-a-provider-spec.md`
