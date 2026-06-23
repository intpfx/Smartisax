# Research Index

This file was split out of `docs/README.md`; it groups project research notes and generated audits.

## Research Notes

```text
research/bootloader-diagnosis.md
  Bootloader unlock and fastboot diagnosis.

research/device-info.txt
  Raw getprop/device info used by early diagnosis.

research/ota-verification.md
  Early SmartisanUpdater URL-injection and OTA verification notes.

research/smartisan-updater-reverse.md
  Decompiled SmartisanUpdater behavior and installer boundary notes.

research/feature-control-map.md
  Current confidence map for dark mode, language selection, Settings/SystemUI
  apktool rebuild smoke, and the signing boundary for core shared-UID packages.

research/system-apk-signature-boundary.md
  Source and offline-experiment evidence for system-partition certs-only APK
  parsing, sharedUserId signature checks, and the no-op replacement gate needed
  before Settings/SystemUI/framework APK patches. Also records the v0.7
  SettingsSmartisan locale-filter candidate and its classes.dex digest boundary.

research/package-manager-policy-map.md
  Focused PackageManager strategy map for Smartisax framework-level policy
  work. It ties prior package-cache, updated-system shadow, manifest parse, and
  TextBoom ABI failures to PMS source surfaces, defines the v0.pm0 services.jar
  no-op gate, and keeps future policies behind explicit allowlists instead of
  global signature or package safety bypasses.

research/package-manager-pm1-cache-policy-design.md
  First real PMS policy design after the live-proven v0.pm0 services.jar
  no-op. It selects an allowlisted boot-scan package parser cache read-bypass
  for Smartisax-managed paths and explicitly excludes ABI, signature,
  updated-system shadow, and package safety behavior changes.

research/smartisax-keyguard-skip-design.md
  Services.jar-only Keyguard skip design for booting directly into Smartisax
  when no secure credential is configured. It records the live pre-build
  Keyguard state, Smartisan Keyguard source guards, v0.kg1 smali hook,
  offline image proof, and the blocked live-preflight authorization boundary.

research/locale-pruning-map.md
  Generated ROM locale-resource inventory and current boundary for reducing the
  system to English, Simplified Chinese, and Traditional Chinese. Also records
  the v0.9 Protips resources.arsc prune probe and the v0.10 framework/product
  hard-prune ROM candidate.

research/locale-prune-coverage-audit.md
  Read-only coverage audit that compares the stock ja/ko resource inventory with
  the current v0.2/v0.4 deletion baseline, v0.7 visible-language filter, v0.10
  framework/product candidate, v0.13 package-image candidate, and v0.17a/v0.17b
  APK-only promotion images. Use this before choosing the next language
  hard-prune package.

research/language-prune-integration-map.md
  End-to-end route for keeping only English, Simplified Chinese, and
  Traditional Chinese visible while pruning non-English/non-Chinese ROM
  resources. It separates visible locale policy, framework AssetManager
  pruning, per-package resource pruning, fallback behavior, updated-system
  package shadows, and live verification gates.

research/language-full-prune-coverage-audit.md
  Read-only full coverage audit for the real English/Chinese-only target. It
  measures all non-English/non-Chinese resource directories, not only the ja/ko
  subset, and separates current ROM coverage, APK-only probes, green frontiers,
  and red/amber gated surfaces.

research/language-next-batch-plan.md
  Read-only staged plan for the remaining English/Chinese-only hard-prune work.
  It separates stale v0.13 image rebuilds, current v0.17-all combined-image
  live-gate work,
  new small APK candidates, high-yield GREEN candidates, AMBER package gates,
  and RED core gates.

research/language-p1-source-review-audit.md
  Read-only source-review audit for the remaining P1 small APK-only
  language-prune candidates. After v0.20a SmartisanShareBrowser, all remaining
  P1 rows still need deeper package-specific review before any APK-only build.

research/v0.17-apk-only-promotion-audit.md
  Read-only promotion audit for turning APK-only language-prune candidates into
  exact-current ROM partition images. It maps each candidate to `system_b`,
  `product_b`, or `system_ext_b`, estimates current space gates, and records the
  Confdialer/system_ext same-size in-place replacement evidence plus the
  boundary that v0.17-all is now the retained local combined sparse test
  target, while standalone v0.17a/v0.17b sparse files were removed from the Mac
  working tree after cleanup.

research/resource-loading-map.md
  Static-source and graphify-backed model for framework resources, app
  resources, overlays, locale fallback, and Smartisan icon redirection. Use this
  before framework resources, package resources, language resources, or
  icon-sensitive same-package replacements.

research/system-modification-playbook.md
  Reusable confidence model for future hard-ROM changes. It separates hard
  delete, same-package replacement, core shared-UID APK replacement, app
  resource pruning, framework resource replacement, SettingsProvider
  defaults/migrations, and boot UI surfaces into distinct gates.

research/system-modification-route-audit.md
  Generated route matrix that translates requested system changes into current
  hard-ROM paths, static risk levels, required live/no-op gates, and red-zone
  surfaces such as Settings, SystemUI, framework resources, Keyguard/Launcher,
  and phone/telephony.

research/cloud-service-debloat-audit.md
  Focused audit for the v0.27 Smartisan cloud service hard-debloat candidate.
  It records the three removed ROM package directories, hiddenapi whitelist
  cleanup, updated-system `/data/app` cloudsync boundary, offline verifier,
  preflight result, and the separate user-approved data-cleanup gate.

research/wallet-handshaker-debloat-audit.md
  Focused audit for the v0.28 Wallet and HandShaker hard-debloat candidate.
  Read-only audit for deleting Smartisan Wallet and HandShaker. It separates
  Wallet's updated-system/priv-app/NFC/lockscreen-payment boundary from
  HandShaker's Smartisan-specific USB accessory and PC-mode display surfaces,
  and records why ordinary ADB/MTP connectivity belongs to system USB/MTP
  components instead of HandShaker.

research/handshaker-replacement-mirroring-plan.md
  Replacement route for the removed HandShaker desktop-assistant feature. It
  records the live `v0.mirror0` scrcpy USB/wireless proof, the
  `tools/r2-mirror.sh` Mac wrapper, and the later browser portal plus TNT
  research split.

research/smartisax-device-portal-design.md
  v0.portal0 design for a browser-accessible Smartisax device portal over the
  same LAN. It scopes the portal to explicit-enable token-gated endpoints,
  records the live-proven v0.portal1 pairing/status-only candidate, and records
  the v0.portal2 PNG screen stream plus tap/swipe control candidate as built
  and live-preflighted but not flashed. File APIs, WebRTC/H.264 streaming,
  MediaProjection, and TNT reuse remain later gates.

research/usb-mass-storage-source-audit.md
  Focused audit for the Mac-visible Smartisan transfer-tool virtual disk after
  HandShaker APK deletion. It proves the disk is vendor USB gadget
  mass_storage backed by `/vendor/etc/cdrom_install.iso`, not the HandShaker
  Android package, defines a separate vendor-image removal boundary, and now
  points to the v0.usb1 vendor_b-only candidate that disables active
  mass_storage config symlinks while retaining the ISO as inert payload. It
  also records the live-verified v0.usb2 physical ISO removal, including the
  free-only zeroing rule after one old ISO block was reassigned to
  `/media/icon/cn.kuwo.player/logo` after deletion and fsck.

research/language-source-coupling-audit.md
  Read-only source-coupling audit for English/Chinese-only language pruning. It
  checks Smartisan Settings locale selection, AOSP LocalePicker, framework
  AssetManager, ResourcesImpl fallback, android static overlays, non-UI
  telephony locale users, current candidates, coverage, and live gates.

research/system-modification-confidence.md
  Current confidence boundary and executable route for the active system
  changes: native light/dark mode integration and English/Chinese-only language
  customization. Also records the v0.8 code-only Settings dark-mode UI
  candidate and the v0.11 native toggleDarkMode Settings/SystemUI ROM
  candidate.

research/darkmode-source-coupling-audit.md
  Read-only source-coupling audit for native dark-mode integration. It checks
  stock UiModeManagerService, SettingsSmartisan, SmartisanSystemUI, existing
  dark-mode resources, v0.11 smali/ROM evidence, and the remaining behavior
  live gate.

research/darkmode-persistence-audit.md
  Read-only persistence audit for native dark-mode integration. It maps
  SettingsProvider fresh seeding and upgrade cleanup, SettingsSmartisan editor
  reset/checkValidity, Settings backup/restore normalization, SystemUI
  first-page truncation, and the v0.11 local candidate injection evidence.

research/darkmode-integration-map.md
  Source-backed implementation map for making dark mode feel native across
  SettingsSmartisan, UiModeManagerService, SmartisanSystemUI, the Smartisan
  quick-widget editor, SettingsProvider defaults, reset/restore normalization,
  and the required live-state markers before default seeding or migration.

research/system-modification-readiness-audit.md
  Read-only current-state audit for the two active end goals. It checks file
  hashes, verifier reports, live-gate evidence, and locale coverage, then marks
  each requirement as offline-proven, missing, or not achieved.

research/launcher-entry-hide-audit.md
  Read-only manifest-surface audit for hiding desktop launcher entries while
  preserving function for 闪念胶囊, 视频播放器, 屏幕录制, 搜索, and 一步. It
  separates the lower-risk first manifest-only candidate from the deferred
  Sara and Sidebar/One Step gates.

research/sidebar-one-step-source-audit.md
  Focused RED-gate source and live-baseline audit for Sidebar/One Step. It
  maps SettingActivity, SidebarService, framework sidebar binding, providers,
  windows, settings keys, the v0.26c launcher-entry-hide live PASS, and the
  v0.29 live-verified topbar cleanup that preserves a blank topbar slot while
  deleting stock controls/text and their code bindings.

research/sidebar-font-ocr-removal-plan.md
  Focused removal plan for retiring the Sidebar/One Step font OCR feature. It
  maps the default-off setting state, stale tool-button database risk, top-area
  IdentifyFontView entry, METHOD_FONT_REQUEST provider entry, FontUtils launch
  helper, BoomFontActivity manifest contract, and the CamScanner/qiuziti.com
  backend that is now deliberately not being migrated to PP-OCR.

research/textboom-ocr-backend-map.md
  Focused static map for TextBoom, Sidebar/One Step, scan/OCR entry points, and
  the current CsOcr/SmashOcr backend branches. It records why current TextBoom
  OCR is still CsOcr/Intsig-CamScanner backed, why SmashOcr is retired instead
  of repaired, how Sidebar font OCR reaches its own OCRhelper/CSOpenAPI and
  qiuziti.com path, why that Sidebar feature is being removed, and why
  Baidu/PaddleOCR should be benchmarked through a local IOcrApi-compatible
  harness before TextBoom ROM integration.

research/ocr-ppocr-replacement-plan.md
  Read-only stage-2 OCR plan that corrects the v0.38 boundary: v0.38 is a
  stable launch/behavior stop, not a complete code deletion. It records the
  remaining Sidebar font OCR classes, Sidebar-local Intsig SDK copy, stale
  tool-button type=1 reachability, TextBoom CsOcr/Intsig metadata, and
  BoomAccessOcrActivity online OCR branch that must be handled before PP-OCR
  fully replaces the CamScanner path. It now also records the offline PP-OCR
  benchmark harness as the next v0.40 gate before TextBoom APK integration.

research/textboom-ppocr-runtime-readiness.md
  Current runtime-readiness note for TextBoom PP-OCR replacement. It records the
  installed local Android SDK/NDK tooling, historical Paddle Lite and ONNX
  smoke evidence, the current official PP-OCRv6 small benchmark APK, the
  2026-06-21 R2 corpus PASS, and the standalone CamScanner raw-baseline block.

research/textboom-ocr-baseline-comparison.md
  Saved comparison report for the current OCR replacement gate. It compares the
  official PP-OCRv6 small corpus run, the standalone CamScanner/CsOcr OpenAPI
  probe, and the partial TextBoom UI-result baseline. Current result is partial
  because CamScanner rejects the standalone raw-response probe with response
  code 4003.

research/textboom-ppocr-adapter-design.md
  Current design spec for replacing TextBoom's `CsOcr` with a local
  `LocalPpOcrApi implements IOcrApi` adapter. It records the existing
  `IOcrApi`/`OcrInfo` contract, cropped-bitmap coordinate policy, error mapping,
  deletion scope, and no-op/real-adapter/CamScanner-deletion gates.

research/textboom-csocr-intsig-deletion.md
  Focused design and evidence note for the accepted v0.43b repair that removes
  TextBoom's `CsOcr` and TextBoom-local `com.intsig.csopen` code while
  retaining the original manifest `ocr_key` package-parse boundary. It records
  the rejected v0.43a manifest-edit result and why CamScanner resource strings
  are deferred to a later resource-table cleanup gate.

research/smartisantech-open-source-audit.md
  Read-only review of the public SmartisanTech GitHub organization. It records
  which historical Android 6 / Nexus 6 One Step, Smartisan framework, SDK,
  native, build, and SELinux repositories can help future Sidebar/framework
  analysis, and why they do not provide a direct R2 Android 11 BrowserChrome,
  WebView, SmartisanUpdater, or ROM-builder shortcut.

research/browser-webview-modernization-audit.md
  Read-only v0.30 entry audit for the Smartisax BrowserChrome/WebView
  modernization backport. It separates the default browser and system WebView
  tracks, records BrowserChrome provider/default-intent/oat-vdex contracts,
  records the `com.android.webview` provider whitelist and WebViewUpdateService
  checks, and defines the next no-op/donor-analysis gates.

research/browser-webview-version-gap-audit.md
  Read-only version-gap and route-priority audit for BrowserChrome/WebView
  modernization. It records stock BrowserChrome app/Chromium payload signals,
  stock WebView provider version, payload shape differences, route priority,
  rejected shortcuts, and the missing live/donor gates before any donor-backed
  image is built.

research/webview-framework-contract-audit.md
  Read-only framework contract audit for WebView donors. It extracts the local
  R2 `config_webview_packages.xml`, WebViewUpdater validity checks,
  WebViewFactory factory/library requirements, WebViewLibraryLoader relro ABI
  requirements, SettingsSmartisan selector behavior, and stock WebView provider
  shape into donor acceptance gates before ROM design.

research/webview-donor-source-plan.md
  Read-only donor source and route plan for the WebView modernization
  backport. It records the stock WebView baseline, current donor inbox state,
  public Google WebView source metadata snapshot, preferred donor classes,
  rejected routes, and version/package/static-library rules before any
  donor-backed ROM design.

research/webview-donor-target-matrix.md
  Read-only WebView donor/source-build target matrix. It consumes framework
  contract, donor inbox, integration-plan, ROM-design, image-capacity, and
  system_b space-source evidence, then splits Route A into source-built/adapted
  and prebuilt standalone targets while deferring framework-provider-add,
  Trichrome multi-package, and BrowserChrome tracks. It explicitly rejects
  native-library-only swaps. The original full M150 product_b-only path remains
  blocked, while the v0.33/v0.34 capacity gates make the v0.35 system-provider
  relocation candidate possible without deleting TNT/projection or print
  packages.

research/webview-route-a-provider-spec.md
  Read-only Route A provider acceptance spec for a future source-built or
  adapted standalone `com.android.webview` package under `/product/app/webview`.
  It turns the preferred route into concrete identity, SDK/version, manifest,
  ABI, ROM-layout, PackageCacher, same-package signing-transition,
  live-verification, and rejected-shortcut requirements before
  donor/source-build intake.

research/webview-route-a-candidate-audit.md
  Read-only Route A candidate intake audit. It runs the donor and
  Trichrome/static-library audits, maps their evidence onto the Route A
  provider spec, and distinguishes stock shape self-tests from real modern
  WebView candidate material before ROM image design.

research/webview-route-a-image-capacity-audit.md
  Read-only Route A image capacity gate. It measures the stock product_b
  replacement budget, current M150 stock-carrier APK/native-library sizes,
  system_b alternatives, and rejected compressed-native/64-bit-only shortcuts.
  Current verdict: PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY.

research/webview-v0.35-system-provider-image-design.md
  Design and live-evidence note for the v0.35 WebView M150 candidate. It
  records why the product_b-only layout is still blocked, why the live-proven
  v0.34 system_b capacity baseline is used instead, the exact system/product
  filesystem actions, duplicate-package mitigation, FEC rebuild policy, image
  outputs, offline/preflight evidence, B-slot flash evidence, read-only live
  verification, the BrowserChrome white-loading regression caused by the stock
  browser renderer crashing on its prebuilt odex, and the v0.35.1 deodex
  follow-up candidate. It also records the v0.35.2 product-residue cleanup
  candidate, which removes the old `/product/app/webview` backup/oat tree and
  is flashed/live-verified with BrowserChrome, HtmlViewer, Big Bang, and WPS
  embedded-WebView functional proof.

research/webview-system-space-source-audit.md
  Read-only system_b space-source audit for the full-ABI external-native-library
  WebView layout. It measures real ext4 allocation for candidate removable
  system_b package bundles, treats the Boston/WirelessCast stack as
  user-protected TNT/projection dependencies, preserves the Android print
  stack, and records `user_selected_no_projection_print_preserving` as the
  selected no-projection source. It covers the bare WebView full-ABI shortfall
  but not the 8 MiB reserve, so package deletion and image building remain
  blocked until preflight plus reserve/layout acceptance. It also records
  `/system/app/SmartisanWallpapers` as the safest newly found extra-space
  candidate: GREEN preflight, no components, no permissions, and enough
  allocated bytes to cover the reserve by itself.

research/webview-super-capacity-audit.md
  Read-only dynamic-super capacity audit for growing `system_b` instead of
  relying only on deletion. It parses the current slot-1 lpdump, records
  qti_dynamic_partitions_b free capacity, the physical super tail hole, a
  978,509,824-byte system_b growth ceiling, and a suggested +128 MiB no-op
  growth gate before any WebView content is combined with metadata resizing.

research/webview-application-class-audit.md
  Read-only analysis of the stock M75 WebView Application class versus the
  source-built M150
  `org.chromium.android_webview.nonembedded.WebViewApkApplication` class. It
  records local framework loading evidence and ECS Chromium source evidence,
  concludes that the M150 nonembedded class is a normal standalone
  SystemWebView shape, and removes application_class as an image blocker.

research/webview-source-build-readiness-plan.md
  Read-only source-build intake/readiness plan for Route A. It records the
  current Chromium Dash Android Stable release, verifies the Chromium tag,
  defines the isolated Linux builder command plan and GN args for
  `system_webview_apk`, and records same-package signing-transition gates
  before ROM image design. The first ECS-built APK has returned, but this plan
  remains non-authorizing.

research/webview-signing-transition-plan.md
  Read-only A-SIG-01 signing-transition plan for a future source-built
  `com.android.webview` candidate. It records the stock WebView APK Sig Block
  42/certificate-carrier shape, v0.26 v2cert/package-cache lessons, accepted
  transition routes, rejected shortcuts, and the current offline
  PackageManager acceptance state before candidate image/live gates.

research/webview-a-sig-package-manager-audit.md
  Read-only A-SIG PackageManager acceptance audit. It compares stock WebView,
  source-built M150 WebView, and `SystemWebView-stock-carrier.apk` with
  apksigner full verification plus Android-style v2/v3 cert-only signer
  parsing, then records why the stock-carrier path is suitable only for
  system-partition ROM design review and still requires live proof.

research/webview-linux-builder-kit.md
  Read-only/off-device handoff kit for producing the source-built
  `SystemWebView.apk` input on an isolated x86-64 Linux builder. It records the
  exact release target, GN args, Linux preflight/build/collection scripts, dist
  provenance metadata, and Mac local intake script. The first Alibaba ECS build
  returned an M150 APK; explicit ROM-image/live gates still block image
  acceptance.

research/webview-github-builder-workflow.md
  Manual GitHub Actions wrapper for the WebView Linux builder kit. It is meant
  for a large self-hosted Linux x86-64 runner or GitHub larger Ubuntu runner,
  first regenerates the ignored `hard-rom/inspect` kit on the runner, defaults
  to preflight-only, and records why the default standard `ubuntu-latest`
  runner is not sufficient for a full Chromium build.

hard-rom/inspect/browser-webview-sourcebuilt-intake/sourcebuilt-system-webview-150-0-7871-28/sourcebuilt-intake.md
  Real Mac-side source-built `SystemWebView.apk` intake report. It records
  INTAKE-00 dist provenance validation, copy, signing-shape,
  stock-cert-carrier adaptation, original/adapted Route A audit, integration
  plan, ROM design plan, and target matrix steps without touching the device.

research/webview-integration-plan.md
  Read-only WebView donor-to-ROM integration plan. It consumes existing donor,
  Trichrome bundle, inbox, and v0.31 evidence, then records current gate
  status, Route A/B/C classification, build-readiness blockers, ROM design
  requirements, and next gates before any donor-backed image is built.

research/webview-rom-design-plan.md
  Read-only ROM design preflight for WebView donor integration. It translates
  the integration-plan candidates into partition scope, filesystem actions,
  package-cache/oat-vdex actions, verification gates, and blockers. Treat the
  older product_b-only plan as capacity-blocked historical input; the current
  concrete candidate image is v0.35, which relocates the provider to system_b
  on top of the live-proven v0.34 FEC capacity baseline. BrowserChrome uses a
  separate v0.32 stock near-noop gate before any same-package behavior
  replacement.

research/nut_r2_ota_findings.md
  Official OTA/package search notes.

research/android_exploit_research.md
  Pre-root exploit research. Historical only now that APatch root works.
```
