# Browser/WebView Modernization Audit

Generated: 2026-06-19 02:09:01

This is a read-only offline audit for the Smartisax browser/WebView
modernization backport. It does not build images, touch a device, flash,
reboot, erase partitions, write settings, or modify `/data`.

## Decision

BrowserChrome and WebView must be modernized as two separate tracks:

- `com.android.browser` is the stock Smartisan default browser package. It owns
  browser UI, default URL intent handling, bookmark/history providers,
  Smartisan resources, Chromium Java glue, native libraries, app data, package
  cache, and icon redirection coupling. The previous v0.3/v0.3.1 same-package
  replacement failure keeps this path RED until a no-op gate boots through
  keyguard and launcher.
- `com.android.webview` is the system WebView provider under `/product`. It is
  selected by `framework-res` `config_webview_packages.xml` and validated by
  `WebViewUpdateService`. A downloaded modern WebView APK is only donor
  material until it satisfies provider whitelist, target SDK, version, library,
  ABI, sandbox, and system-app/signature rules.

## BrowserChrome Contract

| Item | Risk | Stock value | Candidate requirement | Next gate |
| --- | --- | --- | --- | --- |
| stock package identity | RED | {'package': 'com.android.browser', 'versionCode': '20211218', 'versionName': '9.0.6.4', 'compileSdkVersion': '30', 'minSdkVersion': '24', 'targetSdkVersion': '28'}; path=system/system/app/BrowserChrome/BrowserChrome.apk; sha256=0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c | A same-package candidate must keep package identity or explicitly migrate every default-browser/provider/user-data contract. | Build BrowserChrome no-op/minimal gate only after source/cache/icon coupling is mapped. |
| static risk flags | RED | RED: package is on the project high-risk package list; YELLOW: package declares 13 content providers; YELLOW: package exposes 35 exported components; YELLOW: package participates in core intent resolution: android.intent.action.BOOT_COMPLETED, android.intent.action.LOCALE_CHANGED, android.intent.action.MAIN, android.intent.action.MY_PACKAGE_REPLACED, android.intent.action.VIEW, android.intent.category.BROWSABLE, android.intent.category.LAUNCHER; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior; RED: BrowserChrome same-package replacements v0.3/v0.3.1 previously failed before lockscreen | BrowserChrome replacement must be treated as RED until a no-op gate boots through keyguard/launcher. | No browser behavior APK should be flashed before a BrowserChrome no-op gate. |
| application and chromium preload | RED | {'name': 'org.chromium.chrome.browser.smartisan.application.SmartisanApplication', 'label': '@string/smartisan_browser_name', 'icon': '@mipmap/ic_launcher_browser', 'zygotePreloadName': 'org.chromium.content.app.ZygotePreload', 'networkSecurityConfig': '@xml/network_security_config', 'meta': 'windowParams=0,1,1,-1,900,640,900,640; smartisan_tracker_appid=11; bookmark_provider.authorities=com.android.browser; org.chromium.content.browser.NUM_CHROMETABBED_ACTIVITIES=15; org.chromium.content.browser.SMART_CLIP_PROVIDER=org.chromium.content_public.browser.SmartClipProvider; org.chromium.content.browser.NUM_SANDBOXED_SERVICES=40; org.chromium.content.browser.NUM_PRIVILEGED_SERVICES=5; preloaded_fonts=@array/chrome_preloaded_google_sans_fonts; android.allow_multiple_resumed_activities=true; com.samsung.android.sdk.multiwindow.enable=true; com.samsung.android.sdk.multiwindow.multiinstance.enable=true; com.samsung.android.sdk.multiwindow.multiinstance.launchmode=singleTask; com.samsung.android.sdk.multiwindow.penwindow.enable=true; android.content.APP_RESTRICTIONS=@xml/app_restrictions; com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME=org.chromium.components.media_router.caf.CastOptionsProvider; com.google.android.gms.version=@integer/google_play_services_version; com.google.ar.core.min_apk_version=191106000'} | Preserve or intentionally replace SmartisanApplication, zygotePreloadName, network config, app icon/label, and Chromium tab metadata. | Candidate audit must diff application/meta-data before any image build. |
| provider authorities | RED | org.chromium.chrome.browser.util.ChromeFileProvider -> com.android.browser.FileProvider exported=false \| org.chromium.chrome.browser.download.DownloadFileProvider -> com.android.browser.DownloadFileProvider exported=false \| org.chromium.chrome.browser.provider.ChromeBrowserProvider -> com.android.browser.ChromeBrowserProvider;com.android.browser.browser exported=true \| org.chromium.chrome.browser.smartisan.tab.restore.RestoreTabContentProvider -> com.android.browser.RestoreTabContentProvider exported=true \| org.chromium.chrome.browser.smartisan.provider.FileShareProvider -> com.android.browser.FileShareProvider exported=false \| org.chromium.chrome.browser.smartisan.datashare.DataShareProvider -> com.android.browser.smartisan.datashare exported=true \| com.bytedance.sdk.openadsdk.TTFileProvider -> com.android.browser.TTFileProvider exported=false \| com.bytedance.sdk.openadsdk.multipro.TTMultiProvider -> com.android.browser.TTMultiProvider exported=false \| com.android.browser.search.provider.SearchEngineProvider -> com.android.browser.provider.search_engine exported=true \| com.android.browser.download_impl.util.ChromeFileProvider -> com.android.browser.download_impl.FileProvider exported=false \| com.android.browser.bookmark_impl.provider.BrowserProvider2 -> com.android.browser exported=true \| com.google.firebase.provider.FirebaseInitProvider -> com.android.browser.firebaseinitprovider exported=false \| com.bytedance.frameworks.core.apm.MonitorContentProvider -> com.android.browser.apm exported=false | Preserve content provider authorities such as com.android.browser and com.android.browser.browser unless a data migration exists. | Add a provider-invariant verifier for BrowserChrome candidates. |
| default browser intent surface | RED | launcher=activity-alias:com.android.browser.BrowserActivity#1; web=activity-alias:com.google.android.apps.chrome.IntentDispatcher#2 data=scheme=about,scheme=googlechrome,scheme=http,scheme=https,scheme=javascript \| activity-alias:com.google.android.apps.chrome.IntentDispatcher#3 data=mimeType=application/xhtml+xml,mimeType=text/html,mimeType=text/plain,scheme=about,scheme=content,scheme=file,scheme=googlechrome,scheme=http \| activity-alias:com.google.android.apps.chrome.IntentDispatcher#4 data=mimeType=multipart/related,scheme=file \| activity-alias:com.google.android.apps.chrome.IntentDispatcher#7 data=host=*,scheme=file \| activity-alias:com.google.android.apps.chrome.IntentDispatcher#8 data=host=*,mimeType=*/*,scheme=file \| activity-alias:com.google.android.apps.chrome.IntentDispatcher#16 data=mimeType=application/msword,mimeType=application/octet-stream,mimeType=application/pdf,mimeType=application/vnd.ms-excel,mimeType=application/vnd.ms-excel.sheet.macroenabled.12,mimeType=application/vnd.ms-powerpoint,mimeType=application/vnd.ms-powerpoint.presentation.macroenabled.12,mimeType=application/vnd.ms-word.document.macroenabled.12 | Preserve http/https/BROWSABLE/APP_BROWSER/default launcher behavior or rebuild default-browser resolver state deliberately. | Browser no-op live gate must verify resolver, launcher, keyguard, and URL open behavior. |
| boot and package-state receivers | ORANGE | receiver:org.chromium.chrome.browser.sharing.click_to_call.ClickToCallMessageHandler.PhoneUnlockedReceiver#1 values=android.intent.action.USER_PRESENT \| receiver:org.chromium.chrome.browser.upgrade.PackageReplacedBroadcastReceiver#1 values=android.intent.action.MY_PACKAGE_REPLACED \| receiver:org.chromium.chrome.browser.locale.LocaleChangedBroadcastReceiver#1 values=android.intent.action.LOCALE_CHANGED \| receiver:com.android.browser.clipboard_impl.BootupMonitor#1 values=android.intent.action.BOOT_COMPLETED | Preserve MY_PACKAGE_REPLACED, USER_PRESENT, LOCALE_CHANGED, and related receivers or understand startup side effects. | Candidate source review must inspect receiver side effects and app data/cache interactions. |
| native/dex/assets shape | RED | dex=6; libs=28 abis=arm64-v8a:28 key_libs=libchrome.so assets=assets/new_user_agent_config_default.json, assets/poker_search_engines_config.json, assets/quick_navigation_default.json, assets/search_engine/360_search_icon.png, assets/search_engine/baidu_search_icon.png, assets/search_engine/bing_search_icon.png, assets/search_engine/google_search_icon.png, assets/search_engine/sougou_search_icon.png, assets/search_engine/toutiao_search_icon.png, assets/search_engines_config.json, assets/ttwebview_config.json | A donor cannot be reduced to a few native libraries; Java glue, native ABI, assets, resources, and dex must remain version-matched. | Compare candidate APK zip shape before any BrowserChrome patch plan. |
| preoptimized oat/vdex | ORANGE | system/app/BrowserChrome/oat/arm64/BrowserChrome.odex \| system/app/BrowserChrome/oat/arm64/BrowserChrome.vdex | If BrowserChrome dex changes, stale oat/vdex must be removed, regenerated, or proven ignored. | No-op gate should record package dir mtime and oat/vdex handling. |

## WebView Provider Contract

| Item | Risk | Stock value | Candidate requirement | Next gate |
| --- | --- | --- | --- | --- |
| stock package identity | ORANGE | {'package': 'com.android.webview', 'versionCode': '377015630', 'versionName': '75.0.3770.156', 'compileSdkVersion': '29', 'minSdkVersion': '21', 'targetSdkVersion': '30'}; path=product/app/webview/webview.apk; sha256=11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97 | A system WebView candidate must either stay com.android.webview or be added to framework config_webview_packages. | Start with a WebView stock no-op/near-no-op provider gate. |
| static risk flags | ORANGE | YELLOW: package declares 1 content providers; YELLOW: package exposes 44 exported components; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior | Even though WebView is not high-risk in the package list, provider validity and relro/zygote behavior make it a core runtime gate. | Add WebView-specific offline and live verifiers before donor work. |
| framework provider whitelist | RED | com.android.webview default=true fallback=false signatures=0 | Downloaded com.google.android.webview will not be a valid provider unless config_webview_packages is patched or the donor is adapted to com.android.webview. | v0.31 should prove framework config/provider listing with stock before adding a donor. |
| provider validity checks | RED | UserPackage.hasCorrectTargetSdkVersion; getMinimumVersionCode; providerHasValidSignature; WebViewFactory.getWebViewLibrary; Minimum targetSdkVersion: %d", 30 | Candidate must pass targetSdk >= 30, minimum version-code cohort, signature/system-app rule, and WebViewLibrary metadata. | Build a candidate auditor that fails fast on these WebViewUpdater checks. |
| application and WebViewLibrary metadata | RED | {'name': 'com.android.webview.chromium.WebViewApplication', 'label': 'Android System WebView', 'icon': '@drawable/icon_webview', 'multiArch': 'true', 'extractNativeLibs': 'true', 'use32bitAbi': 'true', 'meta': 'com.android.webview.WebViewLibrary=libwebviewchromium.so; org.chromium.content.browser.NUM_SANDBOXED_SERVICES=40; org.chromium.content.browser.NUM_PRIVILEGED_SERVICES=0; com.google.android.gms.version=@integer/google_play_services_version'} | Preserve WebViewApplication or equivalent glue and meta-data com.android.webview.WebViewLibrary=libwebviewchromium.so. | WebView candidate audit must verify library name, ABI libs, and sandbox services. |
| sandbox service contract | ORANGE | components=activity=2, provider=1, service=44, exported=44, total=47; intent={'main_launcher': 'none', 'web_view': 'none', 'boot_state': 'none'} | Keep NUM_SANDBOXED_SERVICES and matching SandboxedProcessService declarations compatible with Android 11 WebViewFactory. | No-op gate must verify dumpsys webviewupdate and WebView-using apps after boot. |
| native/dex shape | RED | dex=1; libs=2 abis=arm64-v8a:1, armeabi-v7a:1 key_libs=libwebviewchromium.so assets=assets/webview_licenses.notice | Do not mix donor Java glue with stock native libs or stock Java glue with donor native libs. | Compare donor WebView APK/APKM splits before choosing adapt-in-place vs framework-whitelist route. |
| Settings provider selector | YELLOW | IWebViewUpdateService; getValidWebViewPackages; changeProviderAndSetting; getCurrentWebViewPackageName | Settings UI already delegates to webviewupdate; additional providers should appear if framework and validity checks pass. | Read-only live audit should capture current Settings/WebView provider page before changing ROM. |
| Smartisan Big Bang warning | ORANGE | 当使用非系统自带 WebView 时，部分应用中基于 WebView 开发的大爆炸等系统功能将不再支持 | Non-built-in WebView can break Smartisan WebView-based Big Bang surfaces; treat Big Bang as a regression test area. | After WebView provider gate, test Settings warning path and Big Bang/WebView surfaces before integration ROM. |

## System Coupling

| Item | Risk | Stock value | Candidate requirement | Next gate |
| --- | --- | --- | --- | --- |
| Smartisan resource/icon/package-cache coupling | RED | ResourcesManagerSmtEx/AssetManagerSmtEx icon redirection and Android 11 PackageCacher are known project coupling points. | Browser/WebView candidates must bump package directory mtimes and account for /data/system/icon and package_cache state. | Before any flash, prepare read-only live capture for package_cache, icon redirection, keyguard, launcher, and webviewupdate. |

## Roadmap

| Item | Risk | Stock value | Candidate requirement | Next gate |
| --- | --- | --- | --- | --- |
| next offline gates | YELLOW | v0.30 audit -> v0.31 WebView stock near-noop gate -> donor WebView audit -> BrowserChrome no-op gate -> version-gap route audit -> integration candidate | Advance by proving system contracts one gate at a time; no direct donor overwrite. | Version-gap audit now prioritizes WebView Route A first: adapt/source-build a standalone com.android.webview-compatible provider under /product/app/webview after v0.31 live proof. |

## Immediate Offline Next Steps

Completed:

- `tools/r2-webview-donor-audit.py` now provides the WebView donor APK/APKM
  static gate. It accepts single APKs, APKM/APKS/XAPK/ZIP archives, or
  directories of split APKs, then checks provider whitelist/package identity,
  Android 11 min/target SDK gates, WebViewUpdater version-code cohort,
  WebViewLibrary metadata, native ABI/library presence, sandbox service
  declarations, split layout, Android 11
  `WebViewChromiumFactoryProviderForR` class presence, Trichrome/static shared
  library dependencies, multi-package bundle shape, local aapt parser
  coverage, and a recommended ROM adaptation route.
- `tools/r2-webview-donor-inbox-audit.py` now provides the local donor inbox
  gate. It scans `apks/webview-donor-inbox/`, related project donor
  directories, and optionally `~/Downloads`, computes hashes, runs both the
  donor analyzer and the Trichrome bundle analyzer for each local candidate,
  and writes the inbox manifest under
  `hard-rom/inspect/browser-webview-donor-inbox/`. The current default scan
  found no external modern donor package.
- `tools/r2-webview-trichrome-bundle-audit.py` now provides the dedicated
  package-group gate for Trichrome/static-library donors. Stock WebView is
  classified as `PASS_STANDALONE`, while BrowserChrome is rejected as
  `not-webview-bundle`; future Trichrome donors must prove one provider,
  one base APK per package, resolved static-library references, matching
  static-library versions, certDigest evidence when available, and arm64
  WebView native code before image design.
- `tools/r2-webview-donor-source-plan.py` now provides the donor source and
  route plan. It records the stock WebView baseline, public Google WebView
  metadata snapshot, route A/B/C/D/E priorities, and version/package/static
  library rules before any donor-backed ROM design.
- `tools/r2-webview-donor-target-matrix.py` now provides the practical donor
  target matrix. It consumes framework contract, donor inbox, integration-plan,
  and ROM-design evidence, then splits Route A into source-built/adapted and
  prebuilt standalone `com.android.webview` targets, defers
  `com.google.android.webview` framework-provider-add and Trichrome
  multi-package routes, keeps BrowserChrome as a separate browser track, and
  rejects native-library-only swaps.
- `tools/r2-webview-route-a-provider-spec.py` now provides the Route A provider
  acceptance spec. It defines 16 requirements and 6 gates for a future
  source-built/adapted standalone `com.android.webview` provider under
  `/product/app/webview`, and marks the current state ready for donor/source
  build intake but not image build.
- `tools/r2-webview-route-a-candidate-audit.py` now provides the Route A
  candidate intake audit. It runs the donor and Trichrome/static-library
  audits, maps their evidence onto the Route A provider spec, and marks stock
  WebView as `BASELINE_SHAPE_PASS_NOT_MODERN` instead of a real modernization
  candidate.
- `tools/r2-webview-integration-plan.py` now provides the donor-to-ROM
  integration plan. It consumes donor, Trichrome bundle, inbox, live-state,
  and v0.31 evidence, then records Route A/B/C classification,
  build-readiness blockers, ROM design requirements, and next gates. Current
  output has `candidates=1` only because stock WebView is included as a shape
  baseline; it reports `build_ready=0`.
- Stock self-test:
  `tools/r2-webview-donor-audit.py --label stock-webview-selftest` -> PASS.
- Trichrome/standalone self-test:
  `tools/r2-webview-trichrome-bundle-audit.py --label stock-webview-standalone`
  -> `PASS_STANDALONE`.
- Negative self-test:
  BrowserChrome as a fake WebView donor -> FAIL on provider whitelist,
  targetSdkVersion, version-code cohort, missing WebViewLibrary metadata,
  missing native WebView library, and missing Android 11 factory provider
  class. The dedicated bundle audit also rejects BrowserChrome as
  `not-webview-bundle`.
- Current stock/v0.31 route recommendation:
  adapt in place under `/product/app/webview`, keep APK/splits version-matched,
  bump package directory mtime, remove or regenerate stale
  `/product/app/webview/oat/*` files when dex/native code changes, verify
  relro creation and `cmd webviewupdate` after boot, then test Settings WebView
  selector and Smartisan Big Bang/WebView surfaces.
- `tools/r2-browser-webview-live-state-audit.sh` now provides the read-only
  live-state capture plan for the stock BrowserChrome/WebView gate. It records
  `webviewupdate`, WebView settings, package paths/mtimes, default browser
  resolver state, package_cache/icon redirection evidence, keyguard/launcher
  state, and recent Browser/WebView logs without writing settings or mutating
  `/data`.
- `tools/r2-hardrom-build-v0.31-webview-stock-near-noop.sh` and
  `tools/r2-verify-v0.31-webview-stock-near-noop.sh` now provide the first
  WebView provider image gate. The image starts from live-verified v0.29,
  patches only product_b, keeps `/product/app/webview/webview.apk`
  byte-identical to stock, and bumps only `/app/webview` directory mtime to
  `0x6a344030` for PackageCacher/WebViewUpdateService freshness validation.
- `tools/r2-hardrom-build-v0.32-browserchrome-stock-near-noop.sh` and
  `tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh` now provide the
  first BrowserChrome image gate. The image starts from live-verified v0.29,
  patches only system_b, keeps
  `/system/app/BrowserChrome/BrowserChrome.apk` byte-identical to stock, and
  bumps only `/system/app/BrowserChrome` directory mtime to `0x6a34dae0` for
  PackageCacher/default-browser freshness validation.
- `tools/r2-browser-webview-version-gap-audit.py` now provides the route-priority
  gap audit. It records stock BrowserChrome as app 9.0.6.4 with Chromium payload
  signals 90.0.4430.82/90.0.4430.210, stock WebView as 75.0.3770.156/M75, and
  recommends WebView Route A as the first real modernization route after v0.31
  live proof.
- `tools/r2-webview-framework-contract-audit.py` now provides the framework
  contract gate. It extracts the single-provider framework whitelist, Android
  11 targetSdk/versionCode/signature/WebViewLibrary gates, factory-provider
  class requirement, relro/native ABI expectations, sandbox service count, and
  SettingsSmartisan selector behavior. The current report is PASS and is now
  consumed by `tools/r2-webview-integration-plan.py`.
- Latest v0.31 offline verifier:
  `hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-032353.txt`
  -> `result=PASS_OFFLINE_IMAGE`, `dumped_webview_donor_audit=PASS`,
  `dumped_webview_bundle_audit=PASS_STANDALONE`, and
  `webview_integration_plan_build_ready=0`.
- Latest v0.32 offline verifier:
  `hard-rom/inspect/v0.32-browserchrome-stock-near-noop/verify-v0.32-browserchrome-stock-near-noop-offline-image-20260619-115109.txt`
  -> `result=PASS_OFFLINE_IMAGE`, `patched_partitions=system_b`,
  `browser_apk_bytes=stock`, and sparse system_b slice equality.
- Latest integration plan:
  `docs/research/webview-integration-plan.md` -> v0.31 offline provider gate
  PASS, browser/WebView live-state capture MISSING, v0.31 live provider gate
  MISSING, modern donor inbox MISSING, stock WebView baseline
  `NOT_BUILD_READY`.
- Latest version-gap audit:
  `docs/research/browser-webview-version-gap-audit.md` -> BrowserChrome M90
  payload signals vs WebView M75, `route_priority=ROUTE_A_FIRST`, and no modern
  donor currently available.
- Latest framework contract audit:
  `docs/research/webview-framework-contract-audit.md` -> `framework_contract_audit=PASS`,
  Route A available for adapted/source-built `com.android.webview`, ROM system
  app signature route required, and Android 11 factory/library gates recorded.
- Latest donor target matrix:
  `docs/research/webview-donor-target-matrix.md` -> preferred route
  `ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW`,
  `route_a_provider_spec=RECORDED`,
  `route_a_candidate_audit=BASELINE_ONLY`, `ready_routes=0`,
  `donor_backed_image_allowed=false`; live-state capture, v0.31 live provider
  proof, and real modern donor/source-build material remain missing.
- Latest Route A provider spec:
  `docs/research/webview-route-a-provider-spec.md` ->
  `READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE`, 16 requirements, 6 gates, and
  product_b-only Route A scope after v0.31 live proof.
- Latest Route A candidate audit:
  `docs/research/webview-route-a-candidate-audit.md` ->
  `BASELINE_SHAPE_PASS_NOT_MODERN`; stock WebView passes the Route A shape
  mapping through donor and bundle audits, but A-MOD-01 marks it
  `BASELINE_ONLY` because it is still the stock M75 payload.
- Latest integration/design plans:
  `docs/research/webview-integration-plan.md` and
  `docs/research/webview-rom-design-plan.md` now record
  `framework_contract_audit=PASS`, while live-state, v0.31 live proof, and
  modern donor material remain missing.
- `tools/r2-webview-rom-design-plan.py` now provides the donor-to-image design
  preflight. Current output is `docs/research/webview-rom-design-plan.md`,
  with one stock WebView Route A design row marked `DESIGN_ONLY` and
  `ready_for_design_review=0`.
- Latest live-state capture attempt:
  `hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-112934.txt`
  -> `result=DEVICE_NOT_AVAILABLE` because adb was not online. Later USB
  probing saw `KONA-MTP` / `bb12d264`, so MTP was visible but ADB was not
  exposed.

Remaining:

1. Run `tools/r2-browser-webview-live-state-audit.sh` on a connected, booted,
   unlocked device before flashing or live-verifying v0.31 and before any donor
   WebView integration work.
2. Flash v0.31 only after explicit user confirmation, then run
   `tools/r2-verify-v0.31-webview-stock-near-noop.sh --read-only` to prove
   boot, package path/hash, WebView directory mtime, `webviewupdate`, Settings
   WebView provider state, resolver/keyguard/window state, and absence of
   unexpected Browser/WebView regressions.
3. Read `docs/research/webview-donor-source-plan.md`, then put an actual
   modern donor APK/APKM/APKS/XAPK into `apks/webview-donor-inbox/` or provide
   an explicit donor directory and run `tools/r2-webview-donor-inbox-audit.py`.
   Treat any Trichrome/static-library route as a separate package-group gate
   through `tools/r2-webview-trichrome-bundle-audit.py`, and treat any
   framework-provider-add route as a separate framework gate, not a simple
   stock WebView overwrite.
4. Run `tools/r2-webview-route-a-provider-spec.py`,
   `tools/r2-webview-route-a-candidate-audit.py <candidate>`,
   `tools/r2-webview-donor-target-matrix.py`, and
   `tools/r2-webview-integration-plan.py` after donor intake to translate the
   audit results into concrete source-build/prebuilt/framework/Trichrome route
   blockers and next gates.
5. Live-verify the separate BrowserChrome stock near-noop gate after explicit
   confirmation before any BrowserChrome behavior candidate. Provider
   authorities, default intent filters, OAT/VDEX handling, package cache, and
   icon redirection live-state capture remain required before behavior or
   engine replacement.

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/browser-webview-modernization-audit.tsv`
- Markdown report: `docs/research/browser-webview-modernization-audit.md`
