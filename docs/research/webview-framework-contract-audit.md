# WebView Framework Contract Audit

Generated: 2026-06-19 12:07:19

This is a read-only offline audit. It inspects the local decoded R2 framework,
services, SettingsSmartisan, and stock WebView artifacts. It does not download
donors, build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Decision

Route A remains the preferred first real WebView modernization route:
adapt or source-build a standalone `com.android.webview` provider in place
under `/product/app/webview`, after the v0.31 stock provider near-noop gate is
live-proven.

Why: the stock framework whitelist contains only `com.android.webview`, Android 11
`WebViewUpdater` already accepts ROM system apps without configured signatures,
and the framework expects the Android 11 Chromium factory class
`com.android.webview.chromium.WebViewChromiumFactoryProviderForR` plus `com.android.webview.WebViewLibrary` metadata.

## Source Files

- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework-res.apk/resources/res/xml/config_webview_packages.xml`
- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/webkit/SystemImpl.java`
- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/webkit/WebViewUpdater.java`
- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/webkit/UserPackage.java`
- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/webkit/WebViewFactory.java`
- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/webkit/WebViewLibraryLoader.java`
- `reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/WebViewImplementationFragment.java`
- `reverse/smartisan-8.5.3-rom-static/jadx/product__app__webview__webview.apk/resources/AndroidManifest.xml`

## Provider Config

| Gate | Status | Observed | Requirement | Route impact | Next gate |
| --- | --- | --- | --- | --- | --- |
| provider_whitelist | ROUTE_A_AVAILABLE | com.android.webview desc=Android WebView default=True fallback=False signatures=0 | A no-framework route must keep packageName=com.android.webview. Any other provider package needs config_webview_packages.xml work. | Route A can stay product_b-only only when the donor is adapted to com.android.webview. | Reject direct com.google.android.webview drop-in unless a framework-provider-add gate is planned. |
| provider_config_boot_invariants | PASS | availableByDefault=1; fallback=0 | SystemImpl requires at least one available-by-default WebView package and at most one fallback; fallback must also be available by default. | Framework XML edits are boot-sensitive; avoid them for the first real donor if Route A is feasible. | Keep the first donor-backed candidate on Route A when possible. |

## Validity Gates

| Gate | Status | Observed | Requirement | Route impact | Next gate |
| --- | --- | --- | --- | --- | --- |
| target_sdk | PASS | stock targetSdk=30; framework minimum=30 | WebViewUpdater rejects providers whose applicationInfo.targetSdkVersion is below 30. | Modern donors usually pass; BrowserChrome fails because it targets 28. | Keep targetSdk >= 30 as a hard donor audit gate. |
| minimum_version_code_cohort | PASS | stock versionCode=377015630; floor comparison uses versionCode/100000=3770 | WebViewUpdater compares version codes by dividing both sides by 100000, using the lowest available-by-default factory package as the floor. | A modern donor should exceed the stock floor; malformed/backported version codes can still fail. | Donor audit must compare longVersionCode cohorts, not only versionName. |
| signature_or_system_app | SYSTEM_APP_ROUTE_REQUIRED | config signatures for com.android.webview=0; providerHasValidSignature accepts system apps | A ROM system app is accepted regardless of config signatures; a non-system provider must match configured signatures. | Route A should install the provider as a ROM system product app; user-installed donors are not enough. | Keep donor-backed WebView inside product_b or add explicit framework signature config work. |
| webview_library_metadata | PASS | stock meta com.android.webview.WebViewLibrary=libwebviewchromium.so | WebViewFactory.getWebViewLibrary(applicationInfo) must return the native library name. | Java manifest glue and native library must remain version-matched; lib-only swaps are invalid. | Require the donor base manifest to expose WebViewLibrary and the APK/splits to contain that library. |

## Runtime Gates

| Gate | Status | Observed | Requirement | Route impact | Next gate |
| --- | --- | --- | --- | --- | --- |
| factory_provider_class | PASS | framework loads com.android.webview.chromium.WebViewChromiumFactoryProviderForR; stock class present=True | Android 11 WebViewFactory loads WebViewChromiumFactoryProviderForR from the provider classloader. | Modern donors that only ship newer factory class names need compatibility glue or a source build targeting Android 11. | Keep this as a hard donor audit gate before ROM design. |
| native_relro_libraries | PASS | library=libwebviewchromium.so; libs_by_abi={'arm64-v8a': ['libwebviewchromium.so'], 'armeabi-v7a': ['libwebviewchromium.so']} | WebViewLibraryLoader creates relro files for 32-bit and 64-bit ABIs using the WebViewLibrary metadata value. | The donor must carry matching native libraries for the device ABI set or relro/native loading can fail after boot. | Verify relro creation and WebView load on device after v0.31 live proof. |
| sandbox_service_count | PASS | NUM_SANDBOXED_SERVICES=40; declarations=40 | Chromium process launch code relies on the NUM_SANDBOXED_SERVICES manifest metadata matching declared SandboxedProcessService entries. | Split or source-built donors must keep metadata and service declarations together. | Donor audit should fail mismatched metadata/service counts. |

## Settings And Smartisan Surfaces

| Gate | Status | Observed | Requirement | Route impact | Next gate |
| --- | --- | --- | --- | --- | --- |
| settings_provider_selector | RECORDED | SettingsSmartisan lists getValidWebViewPackages filtered by Utils.isPackageEnabled; tip string=web_view_provider_tips | Settings UI does not independently bless providers; it delegates validity to webviewupdate and warns about Big Bang/WebView surfaces for non-built-in WebView. | Even a valid provider needs Settings selector and Smartisan Big Bang/WebView regression testing. | Capture Settings WebView selector and Big Bang/WebView surfaces during live verification. |

## Route Contract

| Gate | Status | Observed | Requirement | Route impact | Next gate |
| --- | --- | --- | --- | --- | --- |
| route_a_contract | PREFERRED_AFTER_V031_LIVE | package=com.android.webview; version=75.0.3770.156/377015630; targetSdk=30; library=libwebviewchromium.so; sandbox=40/40; privileged=0/0; libs={'arm64-v8a': ['libwebviewchromium.so'], 'armeabi-v7a': ['libwebviewchromium.so']} | First real donor image should adapt/source-build a standalone com.android.webview-compatible provider in /product/app/webview after v0.31 live proof. | This keeps the first modernization candidate product_b-only and avoids early framework-res provider XML risk. | Next offline work is donor material intake or source-build planning; next live gate is v0.31 stock near-noop. |

## Stock WebView Shape

```text
package=com.android.webview; version=75.0.3770.156/377015630; targetSdk=30; library=libwebviewchromium.so; sandbox=40/40; privileged=0/0; libs={'arm64-v8a': ['libwebviewchromium.so'], 'armeabi-v7a': ['libwebviewchromium.so']}
providers=com.android.webview desc=Android WebView default=True fallback=False signatures=0
```

## Donor Acceptance Checklist

For a donor to enter ROM image design without framework provider XML work, it
must satisfy all of these conditions:

1. Package identity or adapted manifest is `com.android.webview`.
2. `targetSdkVersion >= 30`.
3. `longVersionCode / 100000` is at least the stock provider cohort.
4. The package is installed as a ROM system app under product/system, or a
   separate framework signature route is designed.
5. Manifest metadata includes `com.android.webview.WebViewLibrary` with a matching native
   WebView library.
6. Dex contains `com.android.webview.chromium.WebViewChromiumFactoryProviderForR` or compatible Android 11 factory glue.
7. Native WebView libraries cover the required device ABIs and can create relro
   files.
8. Sandboxed/privileged process metadata matches declared Chromium services.
9. Splits, native libraries, resources, and Java glue remain version-matched.
10. Live verification covers `cmd webviewupdate`, Settings selector, Big
    Bang/WebView surfaces, keyguard, launcher, resolver, and WebView-using apps.

## Outputs

- Markdown report: `docs/research/webview-framework-contract-audit.md`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-framework-contract-audit.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-framework-contract/webview-framework-contract-audit.json`
