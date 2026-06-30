# Current State

This file holds the long status ledger split out of the root `README.md`. It is a navigational summary, not a replacement for the chronological evidence log. For exact experiment evidence, use `docs/hard-rom-ota-trust.md` and `docs/index/hard-rom-log-toc.md`.

## ROM And Feature Status

Device:

```text
model: Smartisan R2
serial: bb12d264
SoC: Snapdragon 865 / kona
OS: Smartisan OS 8.5.3, Android 11
active slot: B
bootloader: unlocked
root: APatch/kp available on the current ROM
```

Known stable ROM states:

```text
v0.2: no-appstore, stable cold rollback baseline archived on SSDUSB
v0.4: hard debloat, stable boot on B slot and current local rollback image
v0.5-control: built offline from v0.4; not flashed or live-verified yet
v0.6-settings-noop: built offline from v0.4; not flashed or live-verified yet
v0.7-locale-filter: built offline from v0.4; not flashed or live-verified yet
v0.8-darkmode-ui: built offline from v0.4; not flashed or live-verified yet
v0.9-protips-locale-prune: APK built offline; super builder prepared, not run
v0.10-framework-locale-prune: built offline from v0.4; not flashed or live-verified yet
SystemUI certprobe no-op: built offline from v0.4; not flashed or live-verified yet
v0.11-native-darkmode: built from live-verified v0.24, flashed to B slot, live-verified at boot/package/hash level, and passed reversible UiMode/SystemUI toggleDarkMode functional write testing; later audit found the Settings row exposure can be skipped by the Darwin branch, so keep it as live UiMode/SystemUI proof rather than final Settings UX proof
v0.11.1-native-darkmode-settings-row: built from live-verified v0.24, flashed to B slot, live-verified at boot/package/hash level, and UI-proven to expose the reachable SettingsSmartisan dark-mode row on R2; the row currently displays "Dark", so a native Chinese label polish remains before calling the UX final
v0.12-framework-res-noop: built offline from v0.4; not flashed or live-verified yet
v0.13-tier1a-locale-prune: previous system_b image built and verified offline; APK inputs were rebuilt with STORED resources.arsc and the image must be rebuilt before flashable promotion
v0.14a-livewallpaperpicker-locale-prune: APK built offline; promoted in v0.17a image
v0.14b-htmlviewer-locale-prune: APK built offline; promoted in v0.17a image
v0.14c-printspooler-locale-prune: strict APK built offline; promoted in v0.17a image
v0.15a-basicdreams-locale-prune: APK built offline; promoted in v0.17a image
v0.15b-phototable-locale-prune: APK built offline; promoted in v0.17b image
v0.16a-confdialer-locale-prune: APK built offline; same-size payload promoted in v0.17b image
v0.17a-system-apk-only-locale-prune: built and verified offline from v0.4; local sparse removed after v0.17-all cleanup; not flashed or live-verified yet
v0.17b-product-system_ext-apk-only-locale-prune: built and verified offline from v0.4; local sparse removed after v0.17-all cleanup; not flashed or live-verified yet
v0.17-all-apk-only-locale-prune: built and verified offline from v0.4; retained previous combined sparse; not flashed or live-verified yet
v0.18a-simappdialog-locale-prune: APK built offline; promoted in v0.17a image
v0.19a-companiondevicemanager-locale-prune: APK built offline; promoted in v0.22 image
v0.20a-smartisan-share-browser-locale-prune: APK built offline; promoted in v0.22 image
v0.21a-tracker-locale-prune: APK built offline; promoted in v0.22 image
v0.22-all-apk-only-locale-prune: built and verified offline from v0.17-all; previous ten-package combined sparse; not separately flashed, but its promoted content is included in live-verified v0.24
v0.23a-cleaner-locale-prune: APK built offline with binary resources.arsc prune; promoted in v0.24 image
v0.24-cleaner-apk-only-locale-prune: built and verified offline from v0.22-all; flashed to B slot and live-verified with all 11 promoted APK hashes matching device state
v0.25-settings-noop-on-v0.24: built from live-verified v0.24, flashed to B slot, and live-verified as the current SettingsSmartisan no-op gate for dark-mode work
systemui-certprobe-noop-on-v0.24: built from live-verified v0.24, flashed to B slot, and live-verified as the current SmartisanSystemUI no-op gate for dark-mode work
v0.26a.2-launcher-entry-hide-v2cert-cachebump: flashed to B slot and live-verified after unlock; VideoPlayer, ScreenRecorderSmartisan, and QuickSearch remain installed from /system with expected hashes and no /data/app shadows, while their desktop launcher entries are absent
v0.26b-sara-launcher-entry-hide-v2cert-cachebump: built from live-verified v0.26a.2, flashed to B slot, and live-verified; VideoPlayer, ScreenRecorderSmartisan, QuickSearch, and Sara/VoiceAssistant remain installed from /system with expected hashes and no /data/app shadows, while their desktop launcher entries are absent
v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump: built from live-verified v0.26b, flashed to B slot, and live-verified; VideoPlayer, ScreenRecorderSmartisan, QuickSearch, Sara/VoiceAssistant, and Sidebar/One Step remain installed from /system with expected hashes and no /data/app shadows, while their desktop launcher entries are absent; SidebarService remains bound from system, providers remain present, explicit SettingActivity resolves, and sidebar windows remain present
v0.27-cloud-service-debloat: built from live-verified v0.26c, flashed to B slot, cleaned approved updated-system /data cloudsync residue, and live-verified; Smartisan cloud service packages and cloud launcher/sync/authenticator/account-center provider surfaces are absent while core Settings/Contacts/Phone/Launcher/SystemUI remain present
v0.28-wallet-handshaker-debloat: built from live-verified v0.27, flashed to B slot, cleaned approved updated-system /data Wallet residue, and live-verified; Wallet and HandShaker are absent while MTP/ADB, MediaProvider, and core packages remain present
v0.29-sidebar-topbar-hide: built from live-verified v0.28, flashed to B slot, and live-verified; deletes the stock One Step topbar buttons/text and removes their code bindings while preserving a blank topbar slot for future features. Screenshot evidence confirms the old topbar controls/text are gone while Sidebar windows remain present
v0.31-webview-stock-near-noop: built from live-verified v0.29, flashed to B slot, and live-verified after explicit confirmation. It keeps /product/app/webview/webview.apk byte-identical to stock and bumps only the WebView package directory mtime in product_b. Device verification proves the live WebView hash remains stock, /product/app/webview mtime is 2026-06-19 03:00 +0800, WebViewUpdateService keeps com.android.webview valid/current, relro is clean, keyguard is not showing, and launcher is focused
v0.32-browserchrome-stock-near-noop: built offline from live-verified v0.29; not flashed or live-verified. It keeps /system/app/BrowserChrome/BrowserChrome.apk byte-identical to stock and bumps only the BrowserChrome package directory mtime in system_b to test PackageCacher/default-browser freshness before any BrowserChrome behavior or engine replacement
v0.33-system-b-grow-noop: built from live-verified v0.31, flashed to B slot, and live-verified after explicit confirmation. It is the first dynamic-partition expansion gate: grows system_b by 128 MiB, moves the AVB footer with avbtool resize_image, rebuilds full super metadata with lpmake, and keeps ext4 block count, APKs, and critical system files byte-identical. Device verification proves the live system_b mapper size is 3183276032 bytes, boot completes on B slot, root remains available, WebView/BrowserChrome hashes remain stock, and post-unlock launcher focus returns with keyguard hidden. It does not yet make /system df larger
v0.34-system-b-ext4-grow-fec: built from live-verified v0.33, flashed to B slot, and live-verified after explicit confirmation. It keeps the v0.33 system_b partition size, erases the old system_b AVB footer, expands ext4 from 3000860672 to 3132964864 bytes, rebuilds the hashtree footer with Android FEC roots=2, and preserves all checked system APK/critical-file payloads. Device verification proves system_b mapper size is 3183276032 bytes, /system reports 3057952 1K blocks, root remains available, WebView/BrowserChrome hashes remain stock, WebViewUpdateService remains valid/current with relro 2/2, keyguard is hidden, and launcher is focused
v0.35-webview-m150-system-provider: built from live-verified v0.34, flashed to B slot, and live-verified after explicit confirmation. It is the first donor-backed WebView modernization candidate: installs the source-built Chromium M150 stock-carrier `com.android.webview` APK at `/system/app/webview/webview.apk`, hides the old product public WebView APK behind a non-`.apk` held stock path, bumps the system/product WebView package directory mtimes, rebuilds both system_b and product_b AVB hashtree footers with FEC roots=2, and keeps BrowserChrome plus framework `config_webview_packages` unchanged. Device verification proves PackageManager uses the system_b WebView path, the product public APK is absent, WebViewUpdateService selects com.android.webview 150.0.7871.28 with relro 2/2 and dirty=false, BrowserChrome remains stock, keyguard is hidden, and launcher is focused. Functional regression then reproduced the stock browser white-loading page: BrowserChrome's sandbox renderer crashes on `/system/app/BrowserChrome/oat/arm64/BrowserChrome.odex`, while Smartisan Big Bang remains normal
v0.35.1-webview-m150-browserchrome-deodex: built from v0.35, flashed to B slot, and live-verified after explicit confirmation. It keeps the M150 system WebView provider and stock BrowserChrome APK unchanged, removes `/system/app/BrowserChrome/oat/arm64/BrowserChrome.odex` plus `.vdex`, removes the empty oat directories, bumps `/system/app/BrowserChrome` mtime, rebuilds system_b FEC, and keeps product_b byte-identical to v0.35. Device verification proves BrowserChrome APK hash remains stock, BrowserChrome oat paths are absent, WebView M150 remains present, product public WebView remains absent, product held stock WebView remains present, WebViewUpdateService stays clean, keyguard/launcher state is normal after unlock, and stock BrowserChrome renders `https://www.example.com` with zero BrowserChrome-only crash markers. This fixes the v0.35 stock browser white-loading regression
v0.35.2-webview-m150-clean-product-residue: built from live-proven v0.35.1, flashed to B slot, and live-verified after explicit confirmation. It keeps v0.35.1 system_b byte-for-byte, rebuilds only product_b, removes the old `/product/app/webview` directory entirely including `.webview.apk.smartisax-v035-stock-held` and stale oat/vdex files, rebuilds product_b FEC roots=2, and produces sparse hash `977f753dee7b84adc7218f5f0f4a8fd7b4403e8e39b24c77da013c8c6b7ec2f5`. Device verification proves current WebView is `/system/app/webview/webview.apk` version 150.0.7871.28, `/product/app/webview` is absent, BrowserChrome oat is absent, relro is 2/2 with dirty=false, keyguard is hidden, and Launcher is focused. Functional checks prove stock BrowserChrome renders `https://www.example.com`, system HtmlViewer loads M150 WebView, Big Bang BOOM_TEXT starts and segments text, and WPS as a third-party host loads M150 WebView.
v0.36-smartisax-shell-debloat: flashed to B slot and booted after explicit confirmation. The hard-debloat portion passed live checks: all 19 selected ROM paths are absent, M150 WebView/stock BrowserChrome/stock Launcher/print/TNT-projection paths remain present, WebViewUpdateService still selects com.android.webview 150.0.7871.28, keyguard is hidden, and Launcher is focused. The Smartisax app did not register because PackageManager rejected `/system/app/SmartisaxShell` with the Android 11 target R+ `resources.arsc` stored/aligned requirement. The failed v0.36 sparse/system images were removed locally after v0.36.1 superseded them; reports remain under `hard-rom/inspect/v0.36-smartisax-shell-debloat/`.
v0.36.1-smartisax-shell-debloat-arsc-align: built from the same v0.35.2 baseline, flashed to B slot, and live-verified after explicit confirmation. It keeps the v0.36 debloat scope and Smartisax shell but rebuilds `SmartisaxShell.apk` with `resources.arsc` STORED and 4-byte aligned (`data_offset=3204`), fixing the Android 11 PackageManager rejection. Device verification proves `com.smartisax.browser` is served from `/system/app/SmartisaxShell/SmartisaxShell.apk`, all 19 selected ROM paths are absent, M150 WebView remains `/system/app/webview/webview.apk` version 150.0.7871.28 with relro 2/2 and dirty=false, stock BrowserChrome/Launcher/print/TNT-projection paths remain present, keyguard is hidden, and Launcher is focused.
v0.37a-textboom-live-system-base: built from live-verified v0.36.1, offline-verified, live-preflighted, flashed to B slot, booted, and passed the read-only pre-clean verifier. It promotes the live `/data/app` TextBoom v3.2.2 APK byte-for-byte into `/system/app/TextBoom/TextBoom.apk` without manifest/code/resource edits, preserving the original v1/JAR Smartisan signature and avoiding the known manifest-edit certificate-collection failure. Device verification proves the system TextBoom APK hash matches the live v3.2.2 APK. The separately confirmed PackageManager cleanup attempt failed: both `cmd package uninstall-system-updates` and `pm uninstall -k` leave the active package served from `/data/app`, so post-clean Big Bang/TextBoom testing is still blocked until a safer PM-state repair plan is approved.
v0.37b-textboom-live-system-libs-deodex: built from v0.37a, offline-verified, live-preflighted, flashed to B slot, booted, read-only verified, and then repaired after separate explicit approval so TextBoom is served from `/system/app/TextBoom/TextBoom.apk` rather than the old `/data/app` updated-system shadow. It keeps the v3.2.2 TextBoom system APK byte-identical, adds the APK's 13 `armeabi-v7a` native libraries under `/system/app/TextBoom/lib/arm`, removes stale `/system/app/TextBoom/oat`, rebuilds system_b FEC roots=2, and preserves M150 WebView, stock BrowserChrome, stock Launcher, and Smartisax hashes. Device verification proves the system package has all 13 native libs, no TextBoom oat, no `UPDATED_SYSTEM_APP` flag, and Big Bang BOOM_TEXT starts from the system package and segments the test text.
v0.38-sidebar-font-ocr-disabled: built from live-verified v0.37b, flashed to B slot, and live-verified after explicit confirmation. It is the stage-1 behavioral stop for Sidebar/One Step font OCR: `/system/priv-app/Sidebar/Sidebar.apk` is replaced with the font-OCR-disabled APK, `BoomFontActivity` is disabled, `ACTION_BOOM_FONT` no longer resolves, the font tool-button layout is hidden, the launch path is no-oped, Sidebar package mtimes are bumped, and system_b FEC roots=2 is rebuilt. Device verification proves the live Sidebar APK hash matches `b0a7c046...`, SidebarService remains bound from system, Sidebar providers and overlay windows remain present, `font_lookup_switch=0`, and manual corner-swipe verification confirms the One Step panel still opens with `sidebar_switch_status=1` and `side_bar_zoom_type=2`; TextBoom/Big Bang, M150 WebView, stock BrowserChrome rendering, and Smartisax remain functional. This is the previous stable stage-1 stop before v0.39's code deletion.
v0.39-sidebar-font-ocr-deleted: built from live-verified v0.37b, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, and live-verified. It replaces `/system/priv-app/Sidebar/Sidebar.apk` with the v0.39 Sidebar APK whose hash is `9a249c33...`. The APK/image/device verifiers prove `BoomFontActivity`/`FontResultActivity` manifest declarations, `ocr_key`, Sidebar `open/font` classes, Sidebar-local `com/intsig/csopen`, `IdentifyFontView`, `METHOD_FONT_REQUEST -> FontUtils`, and ToolButtonAdapter type=1 layout mapping are removed while TextBoom v3.2.2, TextBoom `lib/arm`, M150 WebView, BrowserChrome, Smartisax, and system_b/product_b FEC roots=2 are retained. Device verification proves slot `_b`, boot complete, root available, keyguard hidden, SidebarService/providers/windows present, `ACTION_BOOM_FONT` unresolved, and manual corner-swipe verification confirms the One Step panel still opens with its blank reserved top area. Big Bang/TextBoom, M150 WebView live-state, BrowserChrome rendering, and Smartisax shell all pass functional checks. Sparse super hash is `a3672c3d32e7acedaf83051b289df86c729e91eb3e24f4e958b3fa4b42560f79`. TextBoom/CamScanner image OCR code is intentionally left for the later PP-OCR adapter/benchmark gate.
v0.40-textboom-ppocr-noop-adapter: built from live-verified v0.39, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and live-verified. It replaces only `/system/app/TextBoom/TextBoom.apk` with a stock-shell TextBoom APK whose changed payload is `classes2.dex` only and whose hash is `e2f659ae...`. The APK, image, and live verifiers prove `BoomOcrActivity.initView()` and `BoomAccessOcrActivity.initOcr()` instantiate `LocalPpOcrApi` instead of `CsOcr`; `LocalPpOcrApi` implements `IOcrApi` and returns `onResultSuccess(empty ArrayList)`; legacy `CsOcr`, TextBoom-local `com.intsig.csopen`, and `ocr_key` remain present for this no-op gate. Device verification proves slot `_b`, boot complete, root available, SELinux Enforcing, TextBoom served from `/system/app/TextBoom/TextBoom.apk` without `UPDATED_SYSTEM_APP`, Sidebar v0.39, M150 WebView, Smartisax, and TextBoom `lib/arm` retained. Functional smoke proves BOOM_TEXT starts and segments text, BrowserChrome renders `https://www.example.com`, WebViewUpdateService selects com.android.webview 150.0.7871.28, Smartisax reports M150/WebGPU/WebGL2/localStorage ready, and image OCR enters `BoomOcrActivity`, triggers `startOcrCropped`, then returns empty/no-result behavior without CamScanner/CSOpenApi crash markers. Sparse super hash is `e1dd20fb38d7e8e49b7e111d8a92c59e1142a1bd6fe992cb1fb752a51e54ab7b`.
v0.41-textboom-ppocr-runtime-adapter: built from live-stable v0.39, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, and boot/package verified. It replaces `/system/app/TextBoom/TextBoom.apk` with a stock-shell TextBoom APK whose changed stock payload is `classes2.dex`, and whose added payloads are `classes4.dex`, PP-OCRv6 small det/rec ONNX models plus `inference.yml`, and four arm64 runtime libraries. The APK hash is `6f0d3964234f57c059f70446ba330e9dcb8a3741ae9ce97dfdc8d6fe7ce880a6`; sparse super hash is `f65fd372c8ac4642d8ed0ead7abe8535f904f740a6020b19019590ef3eacbce4`. Flashing wrote 9/9 sparse chunks, erased `misc`, and rebooted normally. The first read-only verifier was blocked by keyguard; the user manually swiped into the desktop, then the final read-only verifier passed with Smartisax focused and keyguard hidden. Device verification proves slot `_b`, boot complete, root available, SELinux Enforcing, TextBoom served from `/system/app/TextBoom/TextBoom.apk` without `UPDATED_SYSTEM_APP`, Sidebar v0.39, M150 WebView, Smartisax, arm64 ORT/OpenCV runtime libs, and TextBoom `lib/arm` retained. BOOM_TEXT starts `com.smartisanos.textboom/.BoomActivity` and segments the test text. Real image OCR enters `BoomOcrActivity`, but fails before PP-OCR inference because TextBoom runs as `armeabi-v7a`/`app_process32` while v0.41 only added ORT/OpenCV libs under `/system/app/TextBoom/lib/arm64`; logcat reports OpenCV init failed with `library "libopencv_java4.so" not found`, then `CSOCR onError errorCode:-101`. The next candidate is v0.41.1: add 32-bit ORT/OpenCV runtime libs under `/system/app/TextBoom/lib/arm` while keeping the v0.41 APK hash stable.
v0.41.1-textboom-ppocr-runtime-arm32-libs: built from v0.41, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, and live-verified through the first TextBoom PP-OCR image result. It keeps the v0.41 TextBoom APK hash `6f0d3964...` unchanged, retains the existing 32-bit TextBoom `libc++_shared.so` hash `c93fd24d...`, retains the v0.41 arm64 ORT/OpenCV libs, and adds 32-bit `libonnxruntime.so`, `libonnxruntime4j_jni.so`, and `libopencv_java4.so` under `/system/app/TextBoom/lib/arm` for TextBoom's `armeabi-v7a`/`app_process32` runtime. The sparse super hash is `1517f5acc76554b8537938daf99938ad6d17916088c4e8e73c787fc1007eee58`; system_b hash is `00908fe7a218300211d1e42084faf85e9e934412180da5fdd038a5ebe79c7f8f`. Flashing wrote 9/9 sparse chunks, erased `misc`, and rebooted normally. Read-only verification proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, Smartisax focused, keyguard hidden, TextBoom served from `/system/app/TextBoom/TextBoom.apk` without `UPDATED_SYSTEM_APP`, `primaryCpuAbi=armeabi-v7a`, TextBoom APK hash unchanged, all expected arm32/arm64 runtime library hashes match, and product_b remains the v0.35.2 WebView cleanup image. BOOM_TEXT starts `com.smartisanos.textboom/.BoomActivity` and segments the test string. BOOM_IMAGE starts `com.smartisanos.textboom/.ocr.BoomOcrActivity`, runs PP-OCR/ORT without the v0.41 `libopencv_java4.so not found` failure, and lands on a result page with visible OCR text from the Smartisax screenshot (`SMARTISAX`, `Refresh`, `Browser`, `WebGPU`, `WebGL2`, etc.) totaling 115 UI-reported characters. First OCR memory capture reports TextBoom total PSS about 269 MB and native heap PSS about 97 MB. Residual observations: one unrelated `mediaserver` fatal signal appeared during BOOM_TEXT log capture and one `java.io.IOException: Permission denied` appeared near the end of BOOM_IMAGE logs; neither is currently a TextBoom blocker. Next gate is broader corpus/quality/latency/memory/regression validation before deleting legacy CsOcr/Intsig/ocr_key.
v0.42-textboom-ppocr-preview-path: built from offline/live-proven v0.41.1, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and passed the read-only verifier. It kept the v0.41.1 PP-OCR runtime/APK bridge and arm32/arm64 ORT/OpenCV library hashes, changed only TextBoom `classes2.dex`, and moved `FileUtils.OCR_IMAGE_DIR` from stale public `/sdcard/.boom` to `/sdcard/Android/data/com.smartisanos.textboom/files/.boom`. Live BOOM_IMAGE regression then proved OCR was still healthy but the preview-file gate failed: all three cold cases launched `com.smartisanos.textboom/.ocr.BoomOcrActivity`, produced matching OCR chips, reported no TextBoom fatal/native-link failures, but `/sdcard/Android/data/com.smartisanos.textboom/files/.boom/imageboom.jpg` was missing and `BoomChipPage` logged `BitmapFactory` ENOENT for that path. v0.42 is therefore a live-stable but preview-path-failed experiment, not the next flash target.
v0.42.1-textboom-ppocr-preview-media-path: built from v0.41.1 as a minimal follow-up after v0.42's Android/data ENOENT result, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and passed the read-only verifier. It moved `FileUtils.OCR_IMAGE_DIR` to `/sdcard/Android/media/com.smartisanos.textboom/.boom` and kept the same PP-OCR runtime/APK bridge plus arm32/arm64 ORT/OpenCV library hashes. Live BOOM_IMAGE regression still failed the preview-file gate: all three cases launched `BoomOcrActivity`, produced matching PP-OCR chips, and had no TextBoom fatal/native-link failures, but `/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg` was missing and result-page `BitmapFactory` logged ENOENT. Static smali/log inspection proved the live `startOcrCropped(1)` path calls `dealSaveBitmapResult(bitmap)`, which starts `LocalPpOcrApi` without entering the old `TaskHandler -> saveBMtoLocal -> dealQrcode` branch. v0.42.1 is therefore live-stable but preview-save-missing, not the next flash target.
v0.42.2-textboom-ppocr-preview-save-before-ocr: built from v0.41.1 after v0.42.1 proved the Android/media path was read but never written; offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and live-verified. It keeps the Android/media preview path and patches `BoomOcrActivity.dealSaveBitmapResult(bitmap)` to call `FileUtils.saveBMtoLocal(bitmap, "imageboom.jpg")` before `IOcrApi.startOcr(...)`, so the PP-OCR runtime still receives the in-memory bitmap and the result page can read the same bitmap from disk. APK hash is `b783bb1face44039a8065991ef0274ae717bad3ef889618df995409baf4ebc98`; sparse super hash is `e74e76960e15eb9a608742cafdf1bbfda597b9277f922ed019c6b525f328cb40`; system_b hash is `4ee52779f4e176c4ac8df33061aa197aae40482afe2e065b7e22ce4c3b7c93c7`. The APK builder proves only `classes2.dex` changes, the stock-shell signature boundary remains v1/JAR with classes2 digest mismatch, `dealSaveBitmapResult` saves before startOcr, legacy CsOcr/Intsig/ocr_key remain, and the offline image verifier proves sparse/system/product hashes, system_b/product_b FEC roots=2, TextBoom preview-path literal, retained LocalPpOcrApi/LocalPpOcrRuntime, and retained arm32/arm64 runtime library hashes. The live read-only verifier proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, TextBoom APK/runtime hashes, Android/media preview-path literal, and retained WebView/Smartisax/Sidebar state. The live BOOM_IMAGE regression proves the result-page preview bug is fixed for the current fixed filename route: `smartisax_home`, `settings_main`, and `textboom_app_details` all launch `BoomOcrActivity`, produce matching PP-OCR chips, write distinct `/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg` hashes (`85c8d407...`, `18970a68...`, `5907f5ad...`), report `unchanged_image_file_cases=[]`, and show no TextBoom fatal/native-link failure.
v0.43a-textboom-csocr-intsig-delete: built offline from the v0.42.2 behavior boundary using the v0.41.1 PP-OCR runtime source APK plus the v0.42.2 Android/media preview-save patch, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, and rejected after post-boot verification. It kept LocalPpOcrApi/LocalPpOcrRuntime, PP-OCRv6 small models, Android/media preview path, and arm32/arm64 ORT/OpenCV library hashes, while deleting TextBoom `CsOcr` smali, deleting TextBoom-local `com.intsig.csopen` smali, removing manifest `ocr_key`, and changing the remaining OCR error log prefix from `CSOCR` to `PPOCR`. APK hash was `dbde0433b9a4bbec84ebb226a28b86188ece2c90a15f69c5099ddee6a6d6cd0e`; sparse super hash was `5384e2964de7105db2adbf26d42ae0529af26ce4d0666b97a062578762a7f097`; system_b hash was `41eded90f93a306550f9301a0a675845511cdc242e4383596b5a89780dd20a25`. The phone booted normally on B slot with root, but PackageManager did not register `com.smartisanos.textboom`: `/system/app/TextBoom/TextBoom.apk` existed and matched hash, while `pm path com.smartisanos.textboom` and BOOM intent resolution returned no package/activity. Root cause is attributed to changing `AndroidManifest.xml` inside this original-cert stock-shell APK. The large v0.43a sparse/system images were removed after v0.43b superseded it; reports remain under `hard-rom/inspect/v0.43a-textboom-csocr-intsig-delete/`.
v0.43b-textboom-csocr-intsig-delete-manifest-retained: built as the v0.43a repair, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and live-verified. It retains the original `AndroidManifest.xml` and `ocr_key`, changes only `classes2.dex`, removes TextBoom `CsOcr` smali, removes TextBoom-local `com.intsig.csopen` smali, changes the remaining OCR error log prefix from `CSOCR` to `PPOCR`, and keeps the v0.42.2 Android/media preview-save behavior plus PP-OCR runtime. APK hash is `44d4f4393e061faf77ace20073d460dc8102797dd0847351a84e18fec886b192`; sparse super hash is `e88559e276cb9c4fec68f63687af90bee937dde04e05ec6a7320b6d0645e226c`; system_b hash is `404922eb1a96e0616d781872cc5bdd2150ad26952e880026fae8b87ce1f0d15d`. Device verification proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, TextBoom served from `/system/app/TextBoom/TextBoom.apk` without `UPDATED_SYSTEM_APP`, `primaryCpuAbi=arm64-v8a`, TextBoom APK hash `44d4f439...`, and retained arm32/arm64 ORT/OpenCV hashes. BOOM_IMAGE live regression passed three cold-start cases (`smartisax_home`, `settings_main`, `textboom_app_details`): all launch `com.smartisanos.textboom/.ocr.BoomOcrActivity`, update `/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg`, show OCR text counts, and report zero fatal/native-link markers. BOOM_TEXT launches `com.smartisanos.textboom/.BoomActivity` and segments the test text. Smartisax, Sidebar package path, M150 WebView provider, keyguard hidden state, and B-slot boot state are retained. Residual note: the live PackageManager now selects `arm64-v8a`, with TextBoom total PSS around 359-386 MB in the three image OCR cases; decide separately whether to accept this or force `armeabi-v7a` in a follow-up image.
v0.43c-textboom-force-arm32-abi: built from the v0.43b behavior boundary as an ABI-control candidate, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and rejected after live validation. It keeps the original `AndroidManifest.xml`/`ocr_key`, keeps the v0.43b CsOcr/Intsig code deletion and v0.42.2 Android/media preview-save behavior, removes APK-internal `lib/arm64-v8a/*`, removes system `/system/app/TextBoom/lib/arm64`, and retains the arm32 ORT/OpenCV runtime libraries under `/system/app/TextBoom/lib/arm`. APK hash is `0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7`; sparse super hash is `0b42d185cfdc187b1065be15a3b0cf897be85dd05dceac9569e03341dda9ace2`; system_b hash is `2b57378c560de0f4dddaee3b49d40bb45b0b44610c56e41301bcf1a9ed621e01`. Flashing wrote 9/9 sparse chunks, erased `misc`, and rebooted normally on B slot. The intended post-flash verifier failed because PackageManager still records `primaryCpuAbi=arm64-v8a`, even though `/system/app/TextBoom/lib/arm64` is absent and the APK no longer has `lib/arm64-v8a/*`. A truth-state verifier recorded `WARN_READ_ONLY_V043C_TEXTBOOM_ARM64_PM_WITH_ARM64_LIBS_ABSENT`: boot complete, root uid=0, SELinux Enforcing, TextBoom served from `/system/app/TextBoom`, APK hash `0627630d...`, retained arm32 runtime hashes, and absent arm64 lib dir. BOOM_TEXT starts and focuses `com.smartisanos.textboom/.BoomActivity`; WebView M150, Smartisax, Sidebar, and keyguard-hidden state remain normal. BOOM_IMAGE is not accepted: all three fixed cases launch `BoomOcrActivity` and write a new `imageboom.jpg`, but focus returns to the source app, UI result text is just source-screen text, and logcat shows `OpenCVUtils: Failed to initialize OpenCV: dlopen failed: library "libopencv_java4.so" not found` plus `TextBoomLocalPpOcr: local PP-OCR failed`. Conclusion: removing arm64 native libs alone is insufficient to force TextBoom into `armeabi-v7a`; accepted TextBoom/OCR base remains v0.43b unless v0.43d live validation succeeds. The large v0.43c sparse/system/work artifacts were removed after v0.43d superseded it; manifests and reports remain.
v0.43d-textboom-codepath-arm32-abi: built offline from the v0.43b/v0.43c behavior boundary, verified offline, live-preflighted, flashed to B slot after explicit confirmation, booted, and rejected after live validation. It keeps the original `AndroidManifest.xml`/`ocr_key`, keeps the v0.43b CsOcr/Intsig code deletion and v0.42.2 Android/media preview-save behavior, reuses the v0.43c force-arm32 APK hash `0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7`, moves the public system app path to `/system/app/TextBoomArm32/TextBoomArm32.apk`, removes the old public `/system/app/TextBoom/TextBoom.apk`, retains the old stock TextBoom APK only as hidden non-`.apk` held path `/system/app/TextBoom/.TextBoom.apk.smartisax-v0.43d-textboom-codepath-arm32-abi-old-codepath-held`, removes `/system/app/TextBoom/lib/arm64`, and hardlinks the retained arm32 ORT/OpenCV libraries under `/system/app/TextBoomArm32/lib/arm`. Sparse super hash is `c9c2d6013a933f5fcf1374bcb0c1df6940c4110d3ae138192236cf5865801bc2`; system_b hash is `d34e00f433497405af81438d8c7bb1763b75d623820123c7e7c1fb57e42ecda7`. Offline verifier `PASS_OFFLINE_IMAGE_V043D_TEXTBOOM_CODEPATH_ARM32_ABI` proves system_b/product_b FEC roots are retained, the target APK/hash matches, old public TextBoom APK is absent, the hidden held stock APK matches the original hash, target arm64 libs are absent, and the Android/media preview path plus LocalPpOcrApi/LocalPpOcrRuntime remain. Live truth-state verifier `WARN_READ_ONLY_V043D_CODEPATH_CHANGED_ABI_STILL_ARM64` proves boot complete, slot `_b`, root uid=0, SELinux Enforcing, TextBoom served from `/system/app/TextBoomArm32`, old public TextBoom APK absent, target arm64 lib dir absent, but `primaryCpuAbi=arm64-v8a`. `/data/system/packages.xml` records `codePath="/system/app/TextBoomArm32"` and `primaryCpuAbi="arm64-v8a"`, the live process runs as `/system/bin/app_process64`, and dalvik-cache is under `arm64/system@app@TextBoomArm32@TextBoomArm32.apk`. BOOM_TEXT starts `com.smartisanos.textboom/.BoomActivity`, but BOOM_IMAGE is not accepted: all three fixed cases launch `BoomOcrActivity` and write a new `imageboom.jpg`, then return source-screen UI text while logcat shows `OpenCVUtils: Failed to initialize OpenCV: dlopen failed: library "libopencv_java4.so" not found`. Conclusion: changing codePath alone is insufficient to force TextBoom into `armeabi-v7a`; accepted TextBoom/OCR base remains v0.43b unless a v0.43e plan succeeds.
v0.43e-textboom-codepath-arm64-runtime-repair: built offline from the v0.43d behavior boundary, offline-verified, live-preflighted, flashed to B slot after explicit confirmation, booted, and live-verified. It keeps the v0.43d public TextBoom path `/system/app/TextBoomArm32/TextBoomArm32.apk`, old public `/system/app/TextBoom/TextBoom.apk` absence, hidden held stock APK, v0.43b CsOcr/Intsig code deletion, v0.42.2 Android/media preview-save behavior, and the force-arm32 APK hash `0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7`. Unlike v0.43d, it accepts PackageManager's observed `primaryCpuAbi=arm64-v8a` and restores target system arm64 ORT/OpenCV runtime libraries under `/system/app/TextBoomArm32/lib/arm64` while leaving APK-internal `lib/arm64-v8a/*` absent. Sparse super hash is `d646db5c6462a80735327a3ba8bda2acc60b540df18f150c2d2cf70320f40863`; system_b hash is `858e9922e126444c66c04e94515bc3fd16e8991c45d557cfac926e2d2d9fa01f`. Build verifier `PASS_BUILD_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR`, offline verifier `PASS_OFFLINE_IMAGE_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR`, and live verifier `PASS_READ_ONLY_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR` prove system_b/product_b FEC roots are retained, the target APK/hash matches, old public TextBoom APK is absent, the hidden held stock APK matches the original hash, arm32 libs remain, target arm64 libs are present with expected hashes, APK-internal arm64 libs are absent, TextBoom PackageManager codePath/resourcePath are `/system/app/TextBoomArm32`, and `primaryCpuAbi=arm64-v8a`. Flashing wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on B slot. BOOM_TEXT starts `com.smartisanos.textboom/.BoomActivity`. BOOM_IMAGE regression passes three cold-start cases (`smartisax_home`, `settings_main`, `textboom_app_details`): all launch `com.smartisanos.textboom/.ocr.BoomOcrActivity`, update `/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg`, show OCR text counts, and report `fatal_marker_count=0` plus `unsatisfied_link_marker_count=0`. WebView M150 remains current/clean with relro 2/2, Smartisax remains the default Home, SidebarService remains bound from `/system/priv-app/Sidebar/Sidebar.apk`, keyguard is hidden, and the device was returned to Smartisax Home after validation. TextBoom image-OCR PSS in this live run is about 350-385 MB, so broader PP-OCR quality/memory work should continue from this accepted arm64 line.
v0.44-textboom-ppocr-legacy-ocr-cleanup: APK-only candidate built from the live-proven v0.43e TextBoom APK and verified offline. It keeps the original AndroidManifest.xml and manifest `ocr_key` because v0.43a proved manifest edits make PackageManager ignore TextBoom, changes only `classes2.dex` and `resources.arsc`, forces `BoomAccessOcrActivity` accessibility OCR to use `LocalPpOcrApi` rather than the old connectivity-triggered online branch, removes the hardcoded `imgs-sandbox.intsig.net` URL from classes2.dex, removes CamScanner/扫描全能王 wording from OCR resource strings, and renames inert `ocr_camscanner_*` resource symbols to storage-neutral names while preserving IDs. APK hash is `fe761609aac2be4eade7bc747bfdc429497f5e43627a4f19b4d76b5ce22faa26`. Offline APK checks prove changed ZIP entries are exactly `classes2.dex,resources.arsc`, `resources.arsc` is STORED and 4-byte aligned, `LocalPpOcrApi`/`LocalPpOcrRuntime` remain, old Intsig/CsOcr/CamScanner executable strings are absent, CamScanner wording is absent from resources, and manifest `ocr_key` is retained. This is not yet a ROM image, live preflight, or flash target.
v0.pm0-services-jar-noop: PackageManager framework no-op gate built, live-preflighted, flashed to B slot after exact confirmation, booted, and read-only verified. `tools/r2-build-services-pm-noop-jar.sh` decoded stock `/system/framework/services.jar`, rebuilt it without smali edits, merged only rebuilt `classes.dex` and `classes2.dex` into the stock jar shell, zipaligned the result, verified all entries are STORED, retained stock non-dex entries including `META-INF/MANIFEST.MF`, and copied PMS smali evidence for `PackageManagerService`, `PackageAbiHelperImpl`, `PackageCacher`, `PackageManagerServiceUtils`, and `Settings`. Output jar is `hard-rom/build/framework/services-pm-noop-roundtrip.jar` with hash `30ff020c9dead1afba480dfc075b50454723296376feae0b20a1a58e82f763bc`. `tools/r2-hardrom-build-v0.pm0-services-jar-noop.sh` then started from live-proven v0.43e system_b, audited unique block ownership for public stock `services.jar` and arm64 `services.art/odex/vdex`, removed those public paths as narrow shared-block exceptions, wrote the no-op services.jar, rebuilt system_b FEC roots=2, and produced a system_b image hash `e6341016f5f453f5734916c88fa3efaa51c937f9533f58b9e36cf36a3a43440e`. Offline verifier `PASS_OFFLINE_IMAGE_V0PM0_SERVICES_JAR_NOOP` proves AVB/FEC, fsck, public services.jar hash, changed entries `classes.dex,classes2.dex`, retained `META-INF/MANIFEST.MF`, and absence of public stale services preopt. `tools/r2-hardrom-pack-super-v0.pm0-services-jar-noop.sh` packed the flashable sparse super `hard-rom/build/super-otatrust-v0.pm0-services-jar-noop.sparse.img` with hash `4834d9d233e7243f61211b81b73e15fb3f293d45d80fcecbc7612bad6c4cf1c7`; lpdump/sparse range verification proves all nine partition slices match their source hashes, including system_b at start sector 8306688 with sector count 6217336. The B-slot flash wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on `_b`. Live verifier `PASS_READ_ONLY_V0PM0_SERVICES_JAR_NOOP` proves root uid=0, SELinux Enforcing, system_server `start_count=1`, live `/system/framework/services.jar` hash `30ff020c9dead1afba480dfc075b50454723296376feae0b20a1a58e82f763bc`, public stale `/system/framework/oat/arm64/services.{art,odex,vdex}` absent, key packages still resolving from `/system/app/webview`, `/system/app/TextBoomArm32`, `/system/app/SmartisaxShell`, and `/system/priv-app/Sidebar`, WebView M150 current with relro 2/2 and dirty=false, and no recent fatal markers. Automated unlock did not dismiss Keyguard, but Smartisax is focused behind it; this is not a boot/PMS failure. The raw v0.pm0 system_b intermediate and older v0.41.1/v0.43b image artifacts were removed after sparse packing to restore local free space; the flashable v0.pm0 sparse remains local as the current live image.
v0.pm1-pms-cache-allowlist: first real PackageManager behavior-policy candidate after the live-proven v0.pm0 services.jar no-op. It is built, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, and live-verified. `tools/r2-build-services-pm1-cache-allowlist-jar.sh` starts from `services-pm-noop-roundtrip.jar`, adds `com.android.server.pm.SmartisaxPackagePolicy`, and patches only `ParallelPackageParser.parsePackage(File,int)` so `/system/app/SmartisaxShell`, `/system/app/TextBoomArm32`, `/system/app/TextBoom`, and `/system/priv-app/Sidebar` bypass PackageParser cache reads during boot scan. The final services.jar hash is `84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40` and only `classes.dex` changes. `tools/r2-hardrom-build-v0.pm1-pms-cache-allowlist.sh` extracts the true pm0 `system_b` lpdump slice `system_b=8306688:6217336`, replaces only `/system/framework/services.jar`, keeps public services preopt absent, and rebuilds AVB/FEC roots=2. system_b hash is `8b22c971bfb63d506104df3096031b6524aa738952294fb294aaac1fac98228c`. Sparse super hash is `dd64f8a741dc434763bf6d9518bd0ee74c33cbcf3471121056883f591fc34f52`. Offline verifier `PASS_OFFLINE_IMAGE_V0PM1_PMS_CACHE_ALLOWLIST` proves AVB/FEC, fsck, sparse system_b slice equality, services.jar hash, `SmartisaxPackagePolicy`, `ParallelPackageParser` policy call, public preopt absence, and PMS neighbor classes byte-identical or const-string-jumbo equivalent. Flashing wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on `_b` with system_server `start_count=1`. Live verifier `PASS_READ_ONLY_V0PM1_PMS_CACHE_ALLOWLIST` proves root uid=0, SELinux Enforcing, live services.jar hash `84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40`, public services preopt absent, key packages resolving from `/system/app/webview`, `/system/app/TextBoomArm32`, `/system/app/SmartisaxShell`, and `/system/priv-app/Sidebar`, WebView M150 current/clean with relro 2/2, fatal package-scan markers absent, and SmartisaxPMS boot logs for Sidebar, TextBoom, TextBoomArm32, and SmartisaxShell cache-bypass decisions. Keyguard is showing while Smartisax is focused behind it; this is not a boot/PMS failure.
v0.kg1-smartisax-skip-keyguard: built, offline-verified, flashed to B slot after exact confirmation, booted, and live-verified. It keeps pm1's PackageManager policy and changes only `services.jar` `classes2.dex`: `SmartisaxKeyguardPolicy` reads `persist.smartisax.skip_keyguard` with default true, and `KeyguardServiceDelegate$1.onServiceConnected()` sets `KeyguardState.enabled=false` before the stock `KeyguardServiceWrapper.setKeyguardEnabled(false)` replay. Smartisan's stock `KeyguardViewMediator.setKeyguardEnabled(false)` still refuses disabling when a secure keyguard or SIM PIN is active. The kg1 services.jar hash is `0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6`; system_b hash is `fd88c39e3716dcd7f6d018b651ec69c3e2457995afb78a6bc6c5ae5a95c513b2`; sparse super hash is `450c5e1e34b20a7fd66422c96e359bf949e3968a62c3f6f73db81a229706518c`. Offline verifier `PASS_VERIFY_V0KG1_SMARTISAX_SKIP_KEYGUARD_OFFLINE_IMAGE` proves AVB/FEC, fsck, sparse system_b slice equality, services.jar hash, retained pm1 policy, kg1 Keyguard hook, and public services preopt absence. Flashing wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on `_b`. Live verifier `PASS_READ_ONLY_V0KG1_SMARTISAX_SKIP_KEYGUARD` proves root uid=0, SELinux Enforcing, live `/system/framework/services.jar` hash `0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6`, `isKeyguardShowing=false`, and current focus `com.smartisax.browser/.ShellActivity`, so the no-password boot now lands directly in Smartisax Home.
v0.usb1-no-smartisan-cdrom: built offline from live-proven v0.kg1, live-preflighted, flashed to B slot after exact confirmation, booted, and live-verified. It patches only `vendor_b`, keeps `/vendor/etc/cdrom_install.iso` retained as inert payload, removes the four `mass_storage.0` configfs symlink lines from `/vendor/etc/init/hw/init.qcom.usb.rc`, changes the charger fallback in `/vendor/etc/init/hw/init.qcom.rc` from `mass_storage` to `charging`, preserves ADB/MTP routes, and rebuilds vendor_b AVB/FEC roots=2. The final candidate uses direct replacement only after unique-block owner audit because a rejected trial showed `debugfs ln` can create inode-0 directory entries in this vendor image. Candidate sparse hash is `1608da03f036a4e9d4972d7c892fd018903e603a299040e5464a1512547829bc`; vendor_b hash is `92cc0620019295f7e2ceeb982c011441ba81d65a46376c07eab032827d668afd`. Offline verifier `PASS_OFFLINE_IMAGE_V0USB1_NO_SMARTISAN_CDROM` proves fsck, vendor FEC, USB text patches, ISO retention, and sparse vendor_b slice equality. Flashing wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on `_b`. Live verifier `PASS_READ_ONLY_V0USB1_NO_SMARTISAN_CDROM` proves ADB remains online, root uid=0, SELinux Enforcing, Smartisax Home focused with `isKeyguardShowing=false`, and active `/config/usb_gadget/g1/configs/b.1` links MTP, diag, diag_mdm, and ADB but not `mass_storage.0`; macOS volume read-only check reports `NO_SMARTISAN_TRANSFER_TOOL_VOLUME_OBSERVED`.
v0.usb2-physical-cdrom-iso-delete: built offline from live-proven v0.usb1, live-preflighted, flashed to B slot after exact confirmation, booted, and live-verified. It patches only `vendor_b`, removes `/vendor/etc/cdrom_install.iso`, keeps the v0.usb1 USB init behavior, rebuilds vendor_b AVB/FEC roots=2, and produces sparse hash `239b95b7ebbb467858c40b8e40a268cb1d83be145f5e9cddd8e2dc66a78153d0` plus vendor_b hash `f97230d6c810f08008180b9e1a56ec95d51bf7cc63df78ceffec9e2a37dca44f`. The block audit found ISO inode 536, size 41353216, 9462 logical block entries, 9392 unique physical blocks, and 70 internal duplicate block entries. After deletion and e2fsck, 9391 old ISO blocks were free and zeroed; one old block was reassigned to existing `/media/icon/cn.kuwo.player/logo` and preserved. Offline verifier `PASS_OFFLINE_IMAGE_V0USB2_PHYSICAL_CDROM_ISO_DELETE` proves fsck, vendor FEC, `cdrom_iso_absent=ok`, old HandShaker/transfer-guide payload strings absent, v0.usb1 USB text retained, and sparse vendor_b slice equality. Flashing wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on `_b`. Live verifier `PASS_READ_ONLY_V0USB2_PHYSICAL_CDROM_ISO_DELETE` proves `/vendor/etc/cdrom_install.iso` is absent, mass_storage LUN `file` is empty, active configfs links MTP, diag, diag_mdm, and ADB but not `mass_storage.0`, root uid=0, SELinux Enforcing, Smartisax focused, and `isKeyguardShowing=false`. macOS volume check reports `NO_SMARTISAN_TRANSFER_TOOL_VOLUME_OBSERVED`.
v0.wadb1-smartisax-priv-wireless-adb: built offline from live-proven v0.usb2, live-preflighted, flashed to B slot after exact confirmation, booted, and live-verified. It patches only `system_b`, moves `com.smartisax.browser` from `/system/app/SmartisaxShell/SmartisaxShell.apk` to `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, installs `/system/etc/permissions/privapp-permissions-com.smartisax.browser.xml`, and adds a guarded Smartisax Shell wireless ADB control entry while retaining v0.usb2 vendor cleanup and v0.kg1 services.jar behavior. The Smartisax APK is versionCode 2/versionName 0.2.0 with `MANAGE_DEBUGGING`, `WRITE_SECURE_SETTINGS`, and `ACCESS_WIFI_STATE`; its Javascript bridge is only attached for the local `file:///android_asset/shell/` surface and is removed before external page loads. Sparse super hash is `12e0a42afe1a39fa63948568a7bce84804052019584eaacb46b37151c6ae18cc`; system_b hash is `013d335d8ed3bda9420f553b62eb5ca7de0c23cb21b9d3a35da664e8dfee0f8b`; APK hash is `181536893fb03a6081e1e1cbee284348f6f395daef2f900942b02dafb2541314`. Offline verifier `PASS_OFFLINE_IMAGE_V0WADB1_SMARTISAX_PRIV_WIRELESS_ADB` proves fsck, system_b AVB/FEC roots=2, APK semantics, privapp XML contents, and sparse system_b slice equality. Flashing wrote 9/9 sparse chunks, erased `misc`, rebooted normally, and reached `sys.boot_completed=1` on `_b`. Live verifier `PASS_READ_ONLY_V0WADB1_SMARTISAX_PRIV_WIRELESS_ADB` proves Smartisax is served from `/system/priv-app/SmartisaxShell`, privateFlags includes `PRIVILEGED`, `WRITE_SECURE_SETTINGS` and `MANAGE_DEBUGGING` are granted, the old `/system/app/SmartisaxShell` path is absent, the privapp XML is present, current focus and HOME resolution are Smartisax, and `isKeyguardShowing=false`. Wireless ADB is off after reboot (`adb_wifi_enabled=0`, port unavailable), so the new Smartisax control can be tested from the UI as the next feature smoke.
v0.wadb2.2-smartisax-wireless-adb-binder-transact: built from the v0.wadb2.1 services.jar line, flashed to B slot, and live-verified as the first fully working Smartisax wireless ADB control build. It keeps v0.usb2 vendor cleanup, v0.kg1 Keyguard behavior, and Smartisax as a privileged system app, but changes Smartisax's ADB call path to raw Binder transact calls so hidden API reflection no longer blocks `IAdbManager`. Device verification proves Smartisax versionCode=5 from `/system/priv-app/SmartisaxShell`, services.jar hash `366bf1c3d0d25d195a51a265064d4a648b3656f4d703e507e86652072262e864`, APK hash `b560c84e918bf49e2836194a807266bc745a4f0760957c0a7045149764c1cb77`, `sys.boot_completed=1`, and slot `_b`. Live Smartisax UI testing enabled wireless ADB, returned port `42701`, connected from the Mac to `192.168.31.103:42701`, and verified a wireless shell with `sys.boot_completed=1`, slot `_b`, and product device `darwin`.
v0.mirror0-scrcpy-live-proof: no ROM change; installed scrcpy 4.0 on the Mac and proved HandShaker replacement screen mirroring/control over both USB and the v0.wadb2.2 wireless ADB transport. USB no-window recording, USB control smoke, wireless recording, and an interactive Metal-rendered scrcpy window all completed. `tools/r2-mirror.sh` is the first Mac-side wrapper and can launch USB/wireless mirrors or create short no-window recordings.
v0.portal1-smartisax-lan-portal-noop: built from live-proven v0.wadb2.2, offline-verified, live-preflighted, flashed to B slot after exact confirmation, and live-verified. It updates Smartisax to v0.3.0/versionCode 6, adds a Wi-Fi-bound `DevicePortalService`, serves `GET /`, `POST /api/pair`, and token-gated `GET /api/status` on port `37601`, and deliberately excludes file APIs, screen streaming, input control, and root filesystem access from this first gate. Sparse super hash is `8af6630b1911e9c697b02b4cca458f0d6609f8900046063c4372494d4a1ddd76`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL1_SMARTISAX_LAN_PORTAL_NOOP`; live result is `PASS_READ_ONLY_V0PORTAL1_SMARTISAX_LAN_PORTAL_NOOP`. Live smoke proves Smartisax is focused with Keyguard hidden, WebView M150/WebGPU/WebGL2 remain available, the Portal UI enables the service, Mac can open `http://192.168.31.103:37601` directly over LAN without adb forward, missing token returns 401, pairing returns a token plus status JSON, authorized `/api/status` returns device status, and `ss -ltnp` shows the service bound to `[::ffff:192.168.31.103]:37601` rather than `0.0.0.0`. The only noted cosmetic issue is that the Smartisax in-page label still says `SMARTISAX 0.2` despite PackageManager reporting v0.3.0/versionCode 6.
v0.portal2-smartisax-remote-screen-control: built offline from live-proven v0.portal1, offline-verified, and live-preflighted, but not flashed yet. It updates Smartisax to v0.4.0/versionCode 7, keeps `services.jar` hash `366bf1c3d0d25d195a51a265064d4a648b3656f4d703e507e86652072262e864`, and adds token-gated `GET /api/screen.png` backed by `kp -c "screencap -p"` plus `POST /api/input` backed by `kp -c "input tap/swipe ..."`. Sparse super hash is `24a2955b962595509e6799d79da299b068480815e81ddffa2a221b77a71a2cbc`; system_b hash is `8b6add09cf63da59cfe93cda433180fff0622a7be87ec14a145594e7abab3317`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL2_SMARTISAX_REMOTE_SCREEN_CONTROL`. Live preflight passed with the device online on slot `_b`, boot completed, root available, and v0.4 rollback sparse ready. Required confirmation before flashing: `确认刷入 v0.portal2-smartisax-remote-screen-control B 槽`.
v0.portal2.2-smartisax-remote-screen-control-bufferfix: flashed to B slot and live-verified as the current live Portal line. Smartisax v0.4.2/versionCode 9 is served from `/system/priv-app/SmartisaxShell`, Portal pairing/status works over LAN, and `/api/input` tap/swipe succeeds through `privileged-inputmanager`. `/api/screen.png` still returns 500 with `surfacecontrol_screenshot_returned_null`, and logcat reports `SurfaceControl: Failed to take screenshot`; the likely boundary is that `READ_FRAME_BUFFER` is signature-only and not granted to the self-signed Smartisax priv-app.
v0.portal2.3-smartisax-framebuffer-grant: built, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, and live-verified. It keeps the v0.portal2.2 Smartisax APK unchanged and replaces only `/system/framework/services.jar` with a narrow PackageManager signature-permission policy granting `android.permission.READ_FRAME_BUFFER` only to `com.smartisax.browser`. Services jar hash is `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a`; system_b hash is `0fb6bb063aeb72ee84a60ad5f5a0afd61146df06e6a03fc7d4fa2c0ed85f7a7e`; sparse super hash is `500b37a0e080b94dc50ae6d59c8265982998e4e6e8a3f98301e34472c347ef4b`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL23_SMARTISAX_FRAMEBUFFER_GRANT`; live result is `PASS_READ_ONLY_V0PORTAL23_SMARTISAX_FRAMEBUFFER_GRANT`. Device verification proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, live services.jar hash matches, public services preopt remains absent, Smartisax remains served from `/system/priv-app/SmartisaxShell`, and `android.permission.READ_FRAME_BUFFER: granted=true`. Portal live smoke proves direct LAN access at `http://192.168.31.103:37601`, pairing/status OK, `/api/screen.png` returns 200 `image/png` frames at 1080 x 2340, and `/api/input` tap/swipe returns `privileged-inputmanager`.
v0.portal3a-webrtc-capability-probe: built from live-proven v0.portal2.3, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, and live-verified. It updates Smartisax to v0.5.0/versionCode 10 and keeps the v0.portal2.3 `/system/framework/services.jar` hash `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a`. It retains the token-gated `/api/status`, `/api/screen.png`, and `/api/input` Portal contract while adding `/api/media/capabilities` for Android MediaCodec H.264/H.265 encoder probing plus browser-side WebRTC/WebCodecs capability probing. APK hash is `6bb9b510be2ed30e909a2b9d306e636f5cea9a7f07b559d9f85d7ea8df890724`; system_b hash is `70b753d1bf7af25d5131782f554860a81297afd6f9dc17ed1629696e101d31e0`; sparse super hash is `5f399322d4e5955edaeb4d1114b2e43384c86f45645e225c8873010fd435b820`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL3A_WEBRTC_CAPABILITY_PROBE`; live result is `PASS_READ_ONLY_V0PORTAL3A_WEBRTC_CAPABILITY_PROBE`; LAN smoke result is `PORTAL_SMOKE_V0PORTAL3A_COMPLETED`. Device verification proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, live services.jar hash matches, public services preopt remains absent, Smartisax remains served from `/system/priv-app/SmartisaxShell`, versionCode=10, and `android.permission.READ_FRAME_BUFFER: granted=true`. Portal smoke at `http://192.168.31.103:37601` proves pairing/status OK, `/api/status` reports `portalVersion=0.5.0`, `webrtc=capability-probe`, and `webrtcCodec=H264`, `/api/media/capabilities` reports screen 1080 x 2340 rotation 0, four AVC encoders, three HEVC encoders, and two hardware AVC encoders, `/api/screen.png` returns 1080 x 2340 PNG frames, and `/api/input` tap/swipe returns `privileged-inputmanager`. Focused logcat shows `READ_FRAME_BUFFER` granted and QCOM Codec2 encoder interfaces created; no Portal fatal or SurfaceControl screenshot failure marker was observed.
v0.portal3b-h264-http-stream-prototype: built from live-proven v0.portal3a, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, and LAN-smoke verified. It updates Smartisax to v0.5.1/versionCode 11, keeps the v0.portal2.3 `/system/framework/services.jar` hash `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a`, and retains the token-gated `/api/status`, `/api/media/capabilities`, `/api/screen.png`, and `/api/input` Portal contract while adding `/api/video/h264` H.264 Annex-B HTTP output. APK hash is `fd926ebf5f9470d1b265d97d2933b431a56af637577ab9a7c3dea4b339613ac8`; system_b hash is `c5479f2c19b041fe3ccd150cbf3af1c77d2417fbff34abe419a01935199b8e79`; sparse super hash is `6ca5e87676adebcfcf1cee26ad13403617bd40a7db4509bf84459adf88b22e07`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL3B_H264_HTTP_STREAM_PROTOTYPE`; live result is `PASS_READ_ONLY_V0PORTAL3B_H264_HTTP_STREAM_PROTOTYPE`; LAN smoke result is `PORTAL_SMOKE_V0PORTAL3B_COMPLETED`. Device verification proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, live services.jar hash matches, public services preopt remains absent, Smartisax remains served from `/system/priv-app/SmartisaxShell`, versionCode=11, and `android.permission.READ_FRAME_BUFFER: granted=true`. Portal smoke at `http://192.168.31.103:37601` with code `066642` proves pairing/status OK, `/api/status` reports `portalVersion=0.5.1`, `webrtc=h264-http-prototype`, `webrtcCodec=H264`, and `videoStream=/api/video/h264`, `/api/media/capabilities` reports screen 1080 x 2340 rotation 0, four AVC encoders, three HEVC encoders, and two hardware AVC encoders, `/api/video/h264?frames=8&fps=4&width=720` returns 125086 bytes with 12 Annex-B start codes and NAL types `7,8,7,8,5,1,1,1,5,1,1,1`, ffprobe parses the stream as H.264 High 720x1568 yuv420p level 3.2, `/api/screen.png` returns 1080 x 2340 PNG frames, and `/api/input` tap/swipe returns `privileged-inputmanager`. Focused logcat shows `OMX.qcom.video.encoder.avc` selected and configured with width 720, height 1568, frame-rate 4, bitrate 1200000; no Portal fatal marker was observed in the focused post-smoke log slice.
v0.portal3c-h264-webcodecs-playback: built from live-proven v0.portal3b, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, LAN-smoke verified, and Safari playback verified. It updates Smartisax to v0.5.2/versionCode 12, keeps the v0.portal2.3 `/system/framework/services.jar` hash `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a`, moves the Portal page into `assets/portal/index.html`, keeps `/api/status`, `/api/media/capabilities`, `/api/screen.png`, `/api/input`, and `/api/video/h264`, and adds `/api/video/mp4` backed by Android `MediaMuxer` for direct-LAN HTTP browser playback through a normal video element. The raw Annex-B H.264 path remains available as WebCodecs diagnostic input, but it is not the default direct-LAN route because browser `VideoDecoder` requires a secure context. APK hash is `9b04db3baf43eae822338bad2e45d17fe81f300cb54e4548e490e587861adb3b`; system_b hash is `d51192fe6df61783239b46ce487b516cc2e22202233cccdec29daf5f2bc36b1b`; sparse super hash is `41f15da085dcbe272c990ccfff046931fd7adc00f31215e413a4d8267255827c`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL3C_H264_WEBCODECS_PLAYBACK`; live result is `PASS_READ_ONLY_V0PORTAL3C_H264_WEBCODECS_PLAYBACK`; LAN smoke result is `PORTAL_SMOKE_V0PORTAL3C_COMPLETED`. Device verification proves slot `_b`, boot complete, root uid=0, SELinux Enforcing, live services.jar hash matches, public services preopt remains absent, Smartisax remains served from `/system/priv-app/SmartisaxShell`, versionCode=12, and `WRITE_SECURE_SETTINGS`, `MANAGE_DEBUGGING`, `ACCESS_WIFI_STATE`, and `READ_FRAME_BUFFER` are granted. Portal smoke at `http://192.168.31.103:37601` with code `243143` proves pairing/status OK, `/api/status` reports `portalVersion=0.5.2`, `webrtc=h264-mp4-browser-playback`, `webrtcCodec=H264`, `browserPlayback=mp4-video-element`, `videoStream=/api/video/h264`, and `videoClip=/api/video/mp4`, `/api/media/capabilities` reports screen 1080 x 2340 rotation 0, four AVC encoders, three HEVC encoders, and two hardware AVC encoders, `/api/video/h264?frames=8&fps=4&width=720` returns 124878 bytes with 12 Annex-B start codes and NAL types `7,8,7,8,5,1,1,1,5,1,1,1`, `/api/video/mp4?frames=8&fps=4&width=720` returns 128048 bytes with `ftyp`, `moov`, `mdat`, and `avc1` markers, ffprobe parses the MP4 as H.264 High 720x1568 yuv420p at 4 fps, `/api/screen.png` returns 1080 x 2340 PNG frames, and `/api/input` tap/swipe returns `privileged-inputmanager`. Safari direct-LAN visual playback also paired automatically with `?code=243143&autoplay=mp4` and reported `MP4 playing 111376 bytes` while showing the R2 screen through a normal video element. Focused logcat shows repeated `OMX.qcom.video.encoder.avc` selection and configuration with width 720, height 1568, frame-rate 6, bitrate 1200000; no Portal fatal/exception/error marker was observed in the focused post-smoke log slice. The first smoke used the old default tap coordinate and incidentally enabled Smartisax Wireless ADB on port 37991; the smoke script default tap coordinate was moved to a lower-risk bottom-right point afterward.
v0.portal4a-webrtc-rtp-probe: built from live-proven v0.portal3c, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, LAN-smoke verified twice, and clean-logcat checked. It updates Smartisax to v0.5.3/versionCode 13, keeps the v0.portal2.3 `/system/framework/services.jar` hash unchanged, preserves `/api/status`, `/api/media/capabilities`, `/api/screen.png`, `/api/input`, `/api/video/h264`, and `/api/video/mp4`, and adds token-gated `/api/webrtc/offer` plus `/api/rtp/h264` diagnostic endpoints. `/api/webrtc/offer` parses the posted SDP offer and reports whether it contains video, H.264, ICE ufrag, and DTLS fingerprint while explicitly marking `nativeWebRtcRuntime=false`, `dtlsSrtp=false`, and `ice=not-started`. `/api/rtp/h264` wraps the existing H.264 Annex-B encoder output as a length-prefixed RTP packet dump using payload type 96 and FU-A fragmentation for large NAL units; this is a packetizer/signaling probe, not full WebRTC media transport. APK hash is `8e5bc6e1ecea382e93023f3ca7e2db56d3fc40ae3ef7a3b288be7f6b8942c3aa`; system_b hash is `a9ae296781e159bd353ea77df6582155a1b08743eddcd8f997ccf06382c342da`; sparse super hash is `a1c24a085f604966ddd500a7cb88a26aad81697efc524fbe83d287fbb4243ae3`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL4A_WEBRTC_RTP_PROBE`; live result is `PASS_READ_ONLY_V0PORTAL4A_WEBRTC_RTP_PROBE`; LAN smoke result is `PORTAL_SMOKE_V0PORTAL4A_COMPLETED`. Flashing wrote 9/9 sparse chunks, erased misc, rebooted, and reached `sys.boot_completed=1` on `_b`. Device verification proves Smartisax is served from `/system/priv-app/SmartisaxShell/SmartisaxShell.apk` as versionCode 13 with `WRITE_SECURE_SETTINGS`, `MANAGE_DEBUGGING`, `ACCESS_WIFI_STATE`, and `READ_FRAME_BUFFER` granted. Portal smoke at `http://192.168.31.103:37601` with code `177512` proves pairing/status OK, `/api/webrtc/offer` accepts a mock H.264 SDP offer and reports `hasVideo=true`, `hasH264=true`, `hasIceUfrag=true`, and `hasFingerprint=true`; `/api/media/capabilities` reports screen 1080 x 2340 plus four AVC encoders, three HEVC encoders, and two hardware AVC encoders; `/api/video/h264` returns H.264 Annex-B SPS/PPS/IDR/P-slice NALs; `/api/video/mp4` returns an MP4 with `ftyp`, `moov`, `mdat`, and `avc1`; `/api/rtp/h264` returns 45 RTP packets with payload type 96 and marker packets; `/api/screen.png` returns 1080 x 2340 PNG frames; and `/api/input` tap/swipe returns `privileged-inputmanager`. After clearing logcat and rerunning smoke, no matching fatal/AndroidRuntime/SurfaceControl screenshot error marker appears; QCOM H.264 encoder selection/configuration is visible.
v0.portal4b-mp4-control-polish: built offline from live-proven v0.portal4a, verified offline, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, LAN-smoke verified twice, static `autoplay=live` route checked, and clean-logcat checked. It updates Smartisax to v0.5.4/versionCode 14, keeps the v0.portal2.3 `/system/framework/services.jar` hash unchanged, preserves `/api/status`, `/api/media/capabilities`, `/api/screen.png`, `/api/input`, `/api/video/h264`, `/api/video/mp4`, `/api/webrtc/offer`, and `/api/rtp/h264`, and changes only the Smartisax APK/Portal behavior. The Portal page adds `Start Live`, accepts `autoplay=live`, keeps MP4 video-element playback as the direct-LAN default, records live loop metrics, and leaves WebCodecs/WebRTC/RTP paths as diagnostics. `/api/status` reports `portalVersion=0.5.4`, `webrtc=signaling-rtp-probe-mp4-live-polish`, and `browserPlayback=mp4-live-loop-fallback`; `/api/media/capabilities` and `/api/webrtc/offer` report variant `v0.portal4b-mp4-control-polish`. APK hash is `81470570b23022d30893cb2b4a9b592158c7b94f9fbd056aae806a74b30d84f9`; system_b hash is `2c06a8295b4fb629464ed28190b4546774e444ed5982b1b9e054be9feb2a0826`; sparse super hash is `2a1b702184d351dc5b74b139f1b2961fb429702d7f857865a07680b3277d9fa6`; build result is `PASS_BUILD_V0PORTAL4B_MP4_CONTROL_POLISH`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL4B_MP4_CONTROL_POLISH`; live result is `PASS_READ_ONLY_V0PORTAL4B_MP4_CONTROL_POLISH`; LAN smoke result is `PORTAL_SMOKE_V0PORTAL4B_COMPLETED`. Device verification proves Smartisax is served from `/system/priv-app/SmartisaxShell/SmartisaxShell.apk` as versionCode 14 with `WRITE_SECURE_SETTINGS`, `MANAGE_DEBUGGING`, `ACCESS_WIFI_STATE`, and `READ_FRAME_BUFFER` granted. Portal smoke at `http://192.168.31.103:37601` with code `509664` proves pairing/status OK, `/api/webrtc/offer` accepts a mock H.264 SDP offer, `/api/media/capabilities` reports screen 1080 x 2340 plus four AVC encoders, three HEVC encoders, and two hardware AVC encoders, `/api/video/h264` returns Annex-B SPS/PPS/IDR/P-slice NALs, `/api/video/mp4` returns an MP4 with `ftyp`, `moov`, `mdat`, and `avc1`, `/api/rtp/h264` returns 45 RTP packets with payload type 96 and marker packets, `/api/screen.png` returns 1080 x 2340 PNG frames, and `/api/input` tap/swipe returns `privileged-inputmanager`. After clearing logcat and rerunning smoke, no matching fatal/AndroidRuntime/SurfaceControl screenshot error marker appears. Static `?code=509664&autoplay=live` route evidence proves the page contains Start Live, live metrics, autoplay handling, and `/api/video/mp4`; browser automation visual playback remains a tooling/manual validation item.
v0.portal4c-session-hardening: built offline from live-proven v0.portal4b, verified offline, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, LAN-smoke verified, and clean-logcat checked. It updates Smartisax to v0.5.5/versionCode 15, keeps the v0.portal2.3 `/system/framework/services.jar` hash unchanged, preserves `/api/status`, `/api/media/capabilities`, `/api/screen.png`, `/api/input`, `/api/video/h264`, `/api/video/mp4`, `/api/webrtc/offer`, and `/api/rtp/h264`, and changes only Smartisax APK/Portal behavior. The new Portal boundary hardens the MP4 fallback with pairing-code rotation after successful pairing, bad-pair lockout, session metadata in `/api/status`, browser-side Forget Session/local token clearing, constant-time Bearer-token comparison, and `Content-Security-Policy`/`Referrer-Policy`/same-origin response headers. APK hash is `70f3c205b4d4cd9183384b1aeb638be1b8bde86e29aaba34005c96ba03d6d2b0`; system_b hash is `7234bc2dbf266715e8cff1d507352694a133d820338bac96821d058943e88a5a`; sparse super hash is `66693df65d84e4ef775ff5a2e8b364aa87a4bd6cb203934fa81226bf2146f672`; build result is `PASS_BUILD_V0PORTAL4C_SESSION_HARDENING`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL4C_SESSION_HARDENING`; live read-only result is `PASS_READ_ONLY_V0PORTAL4C_SESSION_HARDENING`; LAN smoke result is `PORTAL_SMOKE_V0PORTAL4C_COMPLETED`; clean-logcat result is `PASS_CLEAN_LOGCAT_V0PORTAL4C`. Offline verification proves Smartisax versionCode 15/versionName 0.5.5, `v0.portal4c-session-hardening`, `signaling-rtp-probe-mp4-live-session-hardening`, `bearer-token-pair-code-rotation`, `rotates-after-success`, `pairing_temporarily_locked`, `constantTimeEquals`, security headers, Forget Session/sessionState UI, retained services.jar policy, FEC/AVB, and sparse system_b slice equality. Live verification proves boot_completed=1, slot `_b`, Smartisax served from `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, READ_FRAME_BUFFER granted, pairing-code replay rejected after successful pairing, session metadata, WebRTC offer probe, media capabilities, H.264 Annex-B, browser-playable MP4, RTP dump, PNG screen, privileged tap/swipe input, and no matching fatal/AndroidRuntime/SurfaceControl/DevicePortalService markers after a fresh logcat clear.
v0.portal4d-autostart-policy: APK-only/source-ready draft on top of the v0.portal4c code line; no ROM image, live preflight, or flash target exists yet. It updates Smartisax to v0.5.6/versionCode 16, adds `PortalBootReceiver`, declares `RECEIVE_BOOT_COMPLETED`, adds explicit Shell Auto On/Auto Off controls, persists opt-in autostart in Smartisax SharedPreferences, and starts DevicePortalService after `BOOT_COMPLETED` or `MY_PACKAGE_REPLACED` only when that opt-in is enabled. APK build passes with hash `b7deaf25d19f5f787ccd24f24a9d1031ad87108e6c1ab2bdea0b499b4d0033f4`.
v0.portal5a-native-webrtc-runtime: flashed to B slot and live-verified through the Portal fallback layer. It updates Smartisax to v0.6.0/versionCode 17 and adds `io.github.webrtc-sdk:android:125.6422.07` plus a native `PeerConnectionFactory` answer path. APK hash is `2711742cf2d0ee1bf8ee04884a0b0b737db49ba981fd07ad4d25ff65fcdd2cbc`; system_b hash is `df7d2e4aac9b392224e91bfd798d3fb940e4ae1806db0a6ebd9cfca7ec237604`; sparse super hash is `c6b7f1d5605ff7e69a4d785bab91a10baa1af65d48b54d9c11bd9bb43061b814`; build result is `PASS_BUILD_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME`; live read-only result is `PASS_READ_ONLY_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME`; curl smoke result is `PORTAL_SMOKE_V0PORTAL5A_CURL_COMPLETED`. Chrome RTCPeerConnection smoke reached `/api/webrtc/offer` with a real browser offer but failed with `UnsatisfiedLinkError: library "libjingle_peerconnection_so.so" not found`; PackageManager reported `legacyNativeLibraryDir=/system/priv-app/SmartisaxShell/lib` and `primaryCpuAbi=null`.
v0.portal5b-native-webrtc-system-libs: historical native-library-loading repair. It is built from v0.portal5a, flashed to B slot after exact confirmation, booted, read-only verified, and LAN/Chrome-smoke verified. It keeps Smartisax v0.6.0/versionCode 17 but installs `libjingle_peerconnection_so.so` under `/system/priv-app/SmartisaxShell/lib/arm64` and `/system/priv-app/SmartisaxShell/lib/arm`. system_b hash is `5495b80bc8ef8b1d6a14e75d12615944026834743cb35bd3688916c0f2a5d87f`; sparse super hash is `39b7d30bb628671f82a1bd358c44d71e2b675f5cac843ba690141f1ffd567544`; build result is `PASS_BUILD_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS`; live read-only result is `PASS_READ_ONLY_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS`; curl smoke result is `PORTAL_SMOKE_V0PORTAL5B_CURL_COMPLETED`. Chrome RTCPeerConnection smoke proves `connectionState=connected`, `iceConnectionState=connected`, `remoteTrack=true`, `nativeWebRtcRuntime=true`, `dtlsSrtp=true`, `srtp=true`, `localCandidateCount=4`, and a browser-installable answer with candidate/fingerprint/setup. Remaining issue: `framesDecoded=0` because the frame pump cannot `getPixels()` from Config#HARDWARE screenshot bitmaps.
v0.portal5c-webrtc-software-bitmap-frames: historical Canvas conversion failure. It is built from live-proven v0.portal5b, flashed to B slot after exact confirmation, booted, read-only verified, and LAN/Chrome-smoke verified. It updates Smartisax to v0.6.1/versionCode 18, runtime marker `v0.portal5c-webrtc-software-bitmap-frames`, APK hash `62eadb1b5e1d06b43f4df647a428b13898abd733d2d6f88f3ac3f1bea2768781`, system_b hash `e82258355f4544797bbbea401c09e864207c7467bd51c74529af9b9956eb6e80`, and sparse super hash `429816c1ebf2d8e0ea3e152d6b7a7d1d19dcddc9c12049ad990eff07c19652c9`. It keeps the external WebRTC system libs and adds `SmartisaxWebRtcRuntime.readableArgb8888(...)` using `Canvas.drawBitmap(...)` into an ARGB_8888 software bitmap before I420 conversion. Offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5C_WEBRTC_SOFTWARE_BITMAP_FRAMES`; live read-only result is `PASS_READ_ONLY_V0PORTAL5C_WEBRTC_SOFTWARE_BITMAP_FRAMES`; curl smoke result is `PORTAL_SMOKE_V0PORTAL5C_CURL_COMPLETED`. Chrome RTCPeerConnection smoke still proves ICE/DTLS/SRTP connected, but `framesDecoded=0` because Android rejects drawing a HARDWARE bitmap into a software Canvas with `Software rendering doesn't support hardware bitmaps`.
v0.portal5d-webrtc-bitmap-copy-frames: previous native WebRTC sustained-stream line. It is built from live v0.portal5c, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, curl-smoke verified, and Chrome WebRTC-smoke verified. It updates Smartisax to v0.6.2/versionCode 19, runtime marker `v0.portal5d-webrtc-bitmap-copy-frames`, APK hash `f369fd67dca1a6e8b8ccf629463d11e780c5d51acfa1b2c655eca5a5d41744fc`, system_b hash `bea2172046907c5d0457d15c8014bf765841d010ca901106ea49b455b34fc5d7`, and sparse super hash `c6e1d7107bce64fa647786aa8838a3e13f5996ac105494ee14a7666be31a71be`. It keeps the external WebRTC system libs and changes `SmartisaxWebRtcRuntime.readableArgb8888(...)` to use `Bitmap.copy(Bitmap.Config.ARGB_8888, false)`, matching the PNG/MP4 conversion path already proven on the device. Offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5D_WEBRTC_BITMAP_COPY_FRAMES`; live read-only result is `PASS_READ_ONLY_V0PORTAL5D_WEBRTC_BITMAP_COPY_FRAMES`; curl smoke result is `PORTAL_SMOKE_V0PORTAL5D_CURL_COMPLETED`. Chrome RTCPeerConnection smoke proves `connectionState=connected`, `iceConnectionState=connected`, `remoteTrack=true`, `nativeWebRtcRuntime=true`, `dtlsSrtp=true`, `srtp=true`, `firstFrame=true`, and no frame-pump error. A 60s sustained Chrome smoke reports 224 decoded frames, 2372 received packets, and zero packet loss. An H.264-preferred Chrome smoke reports `selectedCodec=H264`, 58 decoded frames in 15s, zero packet loss, and logcat confirms `OMX.qcom.video.encoder.avc` was selected.
v0.portal5e-webrtc-h264-session-control: previous live ROM line. It is built from live-proven v0.portal5d, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, curl-smoke verified, and Chrome WebRTC-smoke verified. It updates Smartisax to v0.6.3/versionCode 20, runtime marker `v0.portal5e-webrtc-h264-session-control`, APK hash `8204453fb77a355de6796a60b88ce17bf8c67cbd518f667af5500e2020414b25`, system_b hash `624ab39d6a0a15d915853fffe0ed49c78f5e9a80a62b76f26afdd561ba67e7a9`, and sparse super hash `d495f67bd1a342ae9ff063e8ffaa5730f5f041cb0dae45e5e9166ccf1cfe8666`. It makes the Portal page call `preferVideoCodec(transceiver, "H264")` before creating the WebRTC offer, exposes `/api/webrtc/sessions` and `/api/webrtc/close`, publishes those endpoints through status/capabilities, sends the native WebRTC `sessionId` back to `/api/webrtc/close` on stop, adds `selectedCodec` to native WebRTC answers, keeps `Bitmap.copy(...)` frame conversion, keeps external libwebrtc system libraries, and retains services.jar unchanged. Build result is `PASS_BUILD_V0PORTAL5E_WEBRTC_H264_SESSION_CONTROL`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5E_WEBRTC_H264_SESSION_CONTROL`; live result is `PASS_READ_ONLY_V0PORTAL5E_WEBRTC_H264_SESSION_CONTROL`. Curl smoke proves Portal pairing/status/capabilities/PNG/MP4/input plus session cleanup; dedicated Chrome smoke proves H.264 ICE/DTLS/SRTP playback with 61 decoded frames and zero packet loss.
v0.portal5f-webrtc-datachannel-input: previous live ROM line. It is built from live-proven v0.portal5e, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, curl-smoke verified, and Chrome WebRTC-smoke verified. It updates Smartisax to v0.6.4/versionCode 21, runtime marker `v0.portal5f-webrtc-datachannel-input`, APK hash `27a6672dc6abbf8789607d4f92ffb37909095dcefd20d82d11b44cf1c7ef3be3`, system_b hash `dbbdb34b39a27420043c0a0b22147bb8709e0d395acdf0359e98b8552f70b9d2`, and sparse super hash `b3b633b97f218a713dd09980b85a8d566914c4ac604121214e1961e2b40a93a0`. It removes the token-gated HTTP `POST /api/input` route, moves Portal tap/swipe delivery into the WebRTC `smartisax-input` RTCDataChannel, publishes `input=webrtc-datachannel-input`, `inputTransport=RTCDataChannel`, `inputChannel=smartisax-input`, and `httpInput=false` through status/capabilities/native WebRTC answers, keeps v0.portal5e default H.264/session cleanup, keeps `Bitmap.copy(...)` frame conversion, keeps external libwebrtc system libraries, and retains services.jar unchanged. Build result is `PASS_BUILD_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT`; live result is `PASS_READ_ONLY_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT`. Curl smoke proves Portal pairing/status/capabilities/PNG/MP4 and `/api/input` removal with HTTP 404. Chrome smoke proves native WebRTC ICE/DTLS/SRTP H.264 playback with decoded frames and `smartisax-input` RTCDataChannel ping/ack.
v0.portal5g-webrtc-touch-quality: previous live ROM line. It is built from live-proven v0.portal5f, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, curl-smoke verified, Chrome WebRTC-smoke verified, and post-test session-cleanup verified. It updates Smartisax to v0.6.5/versionCode 22, runtime marker `v0.portal5g-webrtc-touch-quality`, APK hash `24122dceb927dd6bbc7cdba2da60bccadd90e733bdfd44e192a7eeff74023715`, system_b hash `b3cdb42a8d964fd35fa6302bc76e0b041464dacbb291692d06d659bfccb37213`, and sparse super hash `cbe9d5ff93fcf1ab492dbf0a86ee3524daad72ec320f60c30a8588cb1db00cb0`. It keeps v0.portal5f's HTTP `/api/input` removal and `smartisax-input` RTCDataChannel control route, adds a transparent browser `touchOverlay` mapped to display coordinates, includes `displayWidth`/`displayHeight` in DataChannel tap/swipe payloads, publishes display geometry in status and WebRTC answers, and raises the default WebRTC frame pump to 540x1170 at 8 fps. Build result is `PASS_BUILD_V0PORTAL5G_WEBRTC_TOUCH_QUALITY`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5G_WEBRTC_TOUCH_QUALITY`; live result is `PASS_READ_ONLY_V0PORTAL5G_WEBRTC_TOUCH_QUALITY`; curl smoke result is `PASS_PORTAL_SMOKE_V0PORTAL5G_CURL`. Chrome smoke proves native WebRTC ICE/DTLS/SRTP H.264 playback, 125 decoded frames in 15s, 0 packet loss, DataChannel ping/tap/swipe acks, `inputGestureOk=true`, and device answer frame pump 540x1170@8fps. Runtime status during the session reports 375 captured frames with no frame-pump error. Health capture shows Smartisax PSS around 198MB during the active session and around 174MB after closing the session; focused logcat shows the hardware H.264 encoder configured at 540x1170@8fps and bitrate 300000. The WebRTC close endpoint returns activeSessions=0 after cleanup.
v0.portal5h-webrtc-bitrate-quality: previous fully Portal-smoke-proven ROM line. It is built from live-proven v0.portal5g, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, curl-smoke verified, Chrome WebRTC-smoke verified, and post-test session-cleanup verified. It updates Smartisax to v0.6.6/versionCode 23, runtime marker `v0.portal5h-webrtc-bitrate-quality`, APK hash `d434f4d7ca4a1c3625d27c8788781018b6e349458f4f7eab81a5869b0c999308`, system_b hash `1180edf2b4bd401819e4dc3a860b3193d849fc79208b9ef33f5cc768cb0ffa22`, and sparse super hash `9d193755098feb70e283b445aa741412ce35017e28b12931be42015d045a17bd`. It keeps v0.portal5g's DataChannel input and 540x1170@8fps frame pump, removes visible MP4/WebCodecs/PNG/RTP transport choices from the Portal UI, defaults pairing/status recovery to native WebRTC, removes browser video controls, and writes explicit H.264 RtpSender min/target bitrate parameters of 600kbps/1.2Mbps. Build result is `PASS_BUILD_V0PORTAL5H_WEBRTC_BITRATE_QUALITY`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5H_WEBRTC_BITRATE_QUALITY`; live result is `PASS_READ_ONLY_V0PORTAL5H_WEBRTC_BITRATE_QUALITY`; curl smoke result is `PASS_PORTAL_SMOKE_V0PORTAL5H_CURL`. Chrome smoke proves native WebRTC ICE/DTLS/SRTP H.264 playback, first frame, 127 decoded frames in 15s, DataChannel ping/tap/swipe acks, device answer `bitrateApplied=true`, targetBitrateBps=1200000, and frame pump 540x1170@8fps. Focused logcat proves the H.264 encoder accepted explicit bitrate configuration but initialized at `bitrate=600000`, the minBitrateBps value. Health capture shows Smartisax PSS around 201MB during the active session and around 189MB after closing the session. The WebRTC close endpoint returns activeSessions=0 after cleanup.
v0.portal5i-webrtc-runtime-tuning: previous live ROM line, flashed to B slot, read-only verified, and Portal-smoke verified. It is built from live-proven v0.portal5h, offline-verified, live-preflighted, flashed after exact confirmation, booted, and read-only verified. It updates Smartisax to v0.6.7/versionCode 24, runtime marker `v0.portal5i-webrtc-runtime-tuning`, APK hash `8b6c4b7a2bf5e3fb49ff2ceba01427d8d0e1277a80c81d421f29cd73d174f751`, system_b hash `f93449427c47e87fb566b30a7c87ee869496b7ec5e01b19b9b1b832b825ade1d`, and sparse super hash `7461215ef7403d005be3fe3c13ec711e9129998d28f11736fd3e1474e304aaf7`. It keeps WebRTC-only UI, default native WebRTC startup, `smartisax-input` RTCDataChannel control, and HTTP `/api/input` removal. It adds token-gated `GET/POST /api/webrtc/config`, publishes `runtime-tuning` status/capabilities metadata, keeps stable defaults of 540px portrait width, 720px landscape width, 8fps, 600kbps min bitrate, and 1.2Mbps target/max bitrate, and exposes Portal controls with limits maxFrameWidth=1080, maxFps=30, and maxBitrateBps=12000000. Build result is `PASS_BUILD_V0PORTAL5I_WEBRTC_RUNTIME_TUNING`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5I_WEBRTC_RUNTIME_TUNING`; live read-only result is `PASS_READ_ONLY_V0PORTAL5I_WEBRTC_RUNTIME_TUNING`. Post-flash checks prove boot_completed=1, slot `_b`, Smartisax Shell focused, Keyguard not showing, READ_FRAME_BUFFER granted, and libwebrtc arm64/arm system libraries intact. Portal runtime tuning smoke with `tools/r2-portal5i-runtime-tuning-smoke.sh` proves `/api/webrtc/config`, H.264 WebRTC connection, first frame, and DataChannel ping/tap/swipe acks across Stable, Sharp, and 1080/30. Stable reports 540x1170@8 with 127 decoded frames, estimated 7.97fps, zero packet loss, and Smartisax PSS around 188MB. Sharp reports 720x1560@15 with 216 decoded frames, estimated 13.74fps, three lost packets, and Smartisax PSS around 212MB. 1080/30 reports 1080x2340@30 with 180 decoded frames, estimated 11.31fps, zero packet loss, and Smartisax PSS around 213MB. Focused logcat contains no fatal crash markers; encoder logcat confirms OMX.qcom.video.encoder.avc accepted the requested 2.5Mbps and 8Mbps profile inputs for Sharp and 1080/30. The device was restored to Stable config and active WebRTC sessions were closed after the smoke.
v0.portal5j-projection-texture-probe: previous live flashed ROM line and focused MediaProjection permission failure boundary. It starts from live-proven v0.portal5i, updates Smartisax to v0.6.8/versionCode 25, runtime marker `v0.portal5j-projection-texture-probe`, APK hash `5f23dd62ff25829a02f4bbefdb994d67c13df3a31e02ee733054140e3f621e4e`, system_b hash `7d75d7cdcaba49a7cda17daf0fa350f34fa6590cff80984732ca3779bac641a2`, and sparse super hash `d51213324cebd9eca4b7dec58a509618949ebc598dcefa9aff6481f2e2921f28`. It adds `SmartisaxProjectionCapture`, a MediaProjection + VirtualDisplay + WebRTC SurfaceTextureHelper capture backend, backend modes `projection-auto`, `projection-texture`, and `bitmap-i420`, token-gated `/api/webrtc/capture/probe`, 60fps runtime tuning limit, capture backend selection in the Portal UI, and `android.permission.MANAGE_MEDIA_PROJECTION` in the Smartisax manifest/privapp XML. It keeps services.jar byte-identical to `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a` and keeps the old Bitmap/I420 capture path as `projection-auto` fallback. Build result is `PASS_BUILD_V0PORTAL5J_PROJECTION_TEXTURE_PROBE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5J_PROJECTION_TEXTURE_PROBE`; live preflight passed; it was flashed to B slot after exact confirmation and booted with boot_completed=1, slot `_b`, bootanim stopped, Smartisax Shell focused, Keyguard not showing, and READ_FRAME_BUFFER granted. Live read-only verification failed narrowly because `MANAGE_MEDIA_PROJECTION` is not granted; package dump also showed `CAPTURE_VIDEO_OUTPUT` and `INJECT_EVENTS` absent. This proves privapp XML alone is insufficient for the self-signed Smartisax package and the next route must use a narrow services.jar signature-permission policy before treating the texture capture path as real.
v0.portal5j.1-projection-permission-grant: previous live flashed ROM line, built, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, and read-only verified. It keeps the v0.portal5j Smartisax APK unchanged, uses services.jar candidate hash `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, system_b hash `b803a6ac467e855ed3b3abb0cd021d0409d6f50c207ebac79ee8d8522b62f136`, and sparse super hash `3a89aca9fb029cc8cddfeba78d163ad533a6578ae13b8c229e54f11daafa39bc`. It changes only services.jar policy relative to v0.portal5j: `SmartisaxPackagePolicy.shouldGrantSignaturePermission(...)` grants `READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and `MANAGE_MEDIA_PROJECTION` only to `com.smartisax.browser`, and does not grant `INJECT_EVENTS`. Build result is `PASS_BUILD_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT`; offline proof includes `smartisax_projection_permission_policy=ok`, `smartisax_privapp_xml=ok`, and `smartisax_system_webrtc_libs=ok`. Live preflight passed, flash wrote all 9 sparse chunks, erased misc, and rebooted. Post-boot state is `sys.boot_completed=1`, slot `_b`, bootanim stopped, verified boot orange, and root available under enforcing SELinux. Live read-only result is `PASS_READ_ONLY_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT`: Smartisax is served from `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode 25/versionName 0.6.8, `WRITE_SECURE_SETTINGS`, `MANAGE_DEBUGGING`, `READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and `MANAGE_MEDIA_PROJECTION` are granted=true, and libwebrtc arm64/arm hashes match. `INJECT_EVENTS` may appear in requested permissions from the APK manifest, but this policy does not grant it.
v0.portal5j.1 projection capture probe: live-run on the current B-slot ROM and failed before token creation. Portal started from Smartisax Shell at `http://192.168.31.103:37601` with startReason `shell_enable`; pairing evidence was redacted after use. `/api/webrtc/capture/probe` reports classes present and runtime config `maxFps=60`, but `hasProjectionPermission=false`, `binderCreateProjection=failed`, `createProjection=failed`, and the concrete error is `java.lang.NoSuchMethodException: android.media.projection.IMediaProjectionManager$Stub.asInterface [interface android.os.IBinder]`. This means the permission repair is live-proven, but Smartisax's token-creation code still uses a hidden-API reflection path blocked on Android 11. Evidence is in `hard-rom/inspect/v0.portal5j.1-projection-permission-grant/portal-projection-live/`. The next candidate should be v0.portal5j.2, replacing hidden Stub reflection with raw Binder transact calls for `hasProjectionPermission` transaction 1 and `createProjection` transaction 2 before rerunning the 1080/30 and 1080/60 `projection-texture` WebRTC tests.
v0.portal5j.2-projection-binder-transact: previous live flashed ROM line, built offline, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, Portal capture-probe verified, and 1080/30 plus 1080/60 `projection-texture` WebRTC-smoke tested. It updates Smartisax to v0.6.9/versionCode 26, runtime marker `v0.portal5j.2-projection-binder-transact`, APK hash `b1b9f3db5b26e64de5fb469c490b86b9cc2b1fcee35f0353a4376aac2c50998c`, keeps the v0.portal5j.1 services.jar hash `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, system_b hash `5bb2b36d15b6befdfbb0c990b816adbfe488b9e5eafa38463437058635fd6c3b`, and sparse super hash `789bb849e7bc849271958b3b6dd6e01a7c707d06373f6d4d72e88564acd83b66`. It changes only the Smartisax APK relative to v0.portal5j.1: `SmartisaxProjectionCapture` now uses raw Binder transact calls to `media_projection` with descriptor `android.media.projection.IMediaProjectionManager`, transaction 1 for `hasProjectionPermission`, transaction 2 for `createProjection`, and passes the returned `IBinder` through `MediaProjectionManager.getMediaProjection(...)`. Build result is `PASS_BUILD_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT`; flash wrote all 9 sparse chunks, erased misc, and rebooted. Live read-only result is `PASS_READ_ONLY_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT`: boot_completed=1, slot `_b`, bootanim stopped, verified boot orange, root available, Smartisax served from `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode 26/versionName 0.6.9, `READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and `MANAGE_MEDIA_PROJECTION` granted=true, libwebrtc arm64/arm hashes match, Smartisax Shell is focused, and `isKeyguardShowing=false`. Live Portal proof is in `hard-rom/inspect/v0.portal5j.2-projection-binder-transact/portal-projection-live-rawbinder/`: root-started non-exported DevicePortalService, paired with redacted token, `/api/webrtc/capture/probe` returned HTTP 200 with `ok=true`, `hasProjectionPermission=true`, `binderCreateProjection=available`, `tokenRoute=raw-binder-transact-media-projection`, and `createProjection=ok`. Formal projection-texture smoke evidence is in `hard-rom/inspect/v0.portal5j.2-projection-binder-transact/portal-projection-texture-smoke-live/`: both 1080/30 and 1080/60 connect, select H.264, display 1080x2340, report zero packet-loss delta, and pass `smartisax-input` DataChannel tap/swipe acks, but both stall after the initial frame burst. 1080/30 decodes 27 frames in the 20s observation window, estimated about 1.1fps, while the device session reports 80 captured frames; 1080/60 decodes 18 frames, estimated about 0.89fps, while the device session reports 27 captured frames. Logcat shows the VirtualDisplay and hardware AVC encoder initialize in surface mode, with metadata-mode fallback warnings. This failure led to the v0.portal5k frame-pump continuity candidate; do not treat 1080p30/60 as achieved until a later route passes live smoke.
v0.portal5k-frame-pump-continuity: previous live flashed ROM line, built offline, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, and 1080/30 `projection-texture` smoke tested. It starts from v0.portal5j.2, changes only Smartisax APK to v0.6.10/versionCode 27, keeps the services.jar hash `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, keeps raw Binder MediaProjection token creation, and repairs projection-texture continuity by scheduling `SurfaceTextureHelper.forceFrame()` on the helper handler at the requested WebRTC fps. The APK hash is `4181d040b473a83c12a2be25d07a706e29c5b0e0749487dfd1c9ef13c4c7f619`, system_b hash is `57302f32c4ccd0f9c1ee9a18791761261d775ef2ac542928871c35236b511958`, and sparse super hash is `cc9f9921c510ce471d46a24ac786684b03b7e5bb5cf2d801865bd4d3f8dfe14a`. Build result is `PASS_BUILD_V0PORTAL5K_FRAME_PUMP_CONTINUITY`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5K_FRAME_PUMP_CONTINUITY`; live read-only result is `PASS_READ_ONLY_V0PORTAL5K_FRAME_PUMP_CONTINUITY`. The 1080/30 smoke still does not pass the sustained target: Chrome connects, selects H.264, reports 1080x2340, and passes DataChannel tap/swipe, but browser decode stalls at 26 frames, estimated about 0.83fps, while the device-side frame pump continues to `capturedFrames=638`, `sourceFrames=718`, and `continuityFrames=633` over the observation window. This proves the continuity cadence runs on device, but browser/encoder delivery still needs timestamp repair before treating 1080/30 as stable. 1080/60 was intentionally not run after the 1080/30 target failed.
v0.portal5k.1-frame-timestamp-retain: previous live flashed ROM line and current projection-texture performance baseline, built offline, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, and smoke-proven at 1080/30 plus 1080/60 `projection-texture`. It starts from v0.portal5k, changes only Smartisax APK to v0.6.11/versionCode 28, keeps the services.jar hash `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, keeps raw Binder MediaProjection token creation, preserves the v0.portal5k `SurfaceTextureHelper.forceFrame()` cadence, and wraps each retained texture frame with a fresh `System.nanoTime()` timestamp before passing it to WebRTC. The APK hash is `d99026b525f57daa9b7a85ebdca8752e9d2312d11ca485055cec2ec258d0fc35`, system_b hash is `e1d3dddd36dceea72d2cacc0df2d58ed91669f8680f6738f7b8e4b957c481174`, and sparse super hash is `e60e756bc805190ea7e43244fac6c5701be2b4bf0891f3e90d20ac20b524d451`. Build result is `PASS_BUILD_V0PORTAL5K1_FRAME_TIMESTAMP_RETAIN`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5K1_FRAME_TIMESTAMP_RETAIN`; live read-only result is `PASS_READ_ONLY_V0PORTAL5K1_FRAME_TIMESTAMP_RETAIN`. 1080/30 `projection-texture` passes with H.264, 1080x2340 browser video, 606 decoded frames, estimated 29.7fps, packet-loss delta 0, and DataChannel tap/swipe PASS; the device session reports `capturedFrames=627`, `sourceFrames=709`, `continuityFrames=620`, and `timestampRewriteFrames=627`. 1080/60 `projection-texture` passes with H.264, 1080x2340 browser video, 1249 decoded frames, estimated 60.15fps, packet-loss delta 0, and DataChannel tap/swipe PASS; the device session reports `capturedFrames=1322`, `sourceFrames=1380`, `continuityFrames=1316`, and `timestampRewriteFrames=1322`.
The first no-flash 1080/60 latency/input metrics pass also passed on this line: decoded fps 59.99, packet-loss delta 0, source frames 4091, continuity frames 4027, captured frames 4033, DataChannel ping ack p50 15.25ms/p95 71.09ms, tap ack 80.8ms, swipe ack 21.1ms, connected at 853ms, and first frame at 1088ms. It also exposed the next performance target: RVFC callback fps was 39.67, frame interval p95 was 49.72ms, max interval was 6866.4ms, and 135 presentation gaps exceeded 34ms. The next Portal performance experiment should add true touch-to-photon marker evidence and move-stream reverse-control input while investigating Chrome presentation gaps versus the now-stable decoded-frame continuity.
v0.portal5l-touch-photon-move-stream: previous live flashed and smoke-proven Portal line, built offline, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, and 1080/60 touch-to-photon/move-stream smoke verified. It starts from v0.portal5k.1, changes only Smartisax APK to v0.6.12/versionCode 29, keeps the services.jar hash `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, keeps raw Binder MediaProjection token creation, keeps the v0.portal5k.1 retained/fresh timestamp projection-texture frame path, adds `SmartisaxTouchMarker` as a visible device-side overlay marker, publishes `touchPhotonMarker` and `inputMoveStream` status metadata, includes marker region/color/display metadata in input acks, and upgrades WebRTC DataChannel control from legacy tap/swipe gestures to `touchStart`/`touchMove`/`touchEnd` down/move/up stream injection. The Portal asset sends pointer moves at a throttled high-rate stream, uses coalesced pointer events when available, and drops move frames when `webRtcInputChannel.bufferedAmount` is above the backpressure threshold. The Chrome smoke helper now supports `--touch-photon-test`, `--move-stream-test`, marker-pixel sampling through `requestVideoFrameCallback`, move-stream ack counts, and a touch-to-photon summary table. APK hash is `c7f4487f4bfa2a1b06cc0be4ffeeb81b418b1b9a248200a20849c503b8f1301a`, system_b hash is `0f8398b5fa42409e104979b8ee37baefe2ba6316ad98283bc6ed763f1b849877`, and sparse super hash is `680a8c78299706996a4a96ada98e4c24606d76df94e4683fadeb9ec8780886c9`. Build result is `PASS_BUILD_V0PORTAL5L_TOUCH_PHOTON_MOVE_STREAM`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5L_TOUCH_PHOTON_MOVE_STREAM`; live read-only result is `PASS_READ_ONLY_V0PORTAL5L_TOUCH_PHOTON_MOVE_STREAM`; smoke result is PASS. Flash evidence: fastboot current-slot `b`, unlocked `yes`, is-userspace `no`, sparse super 1/9 through 9/9 OK, `erase misc` OK, reboot OK, post-boot `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root available with SELinux Enforcing. Device APK hash matches the candidate APK hash. 1080/60 smoke evidence: H.264, browser video 1080x2340, decoded frames 3922, estimated fps 60.05, estimated bitrate 1888370bps, packet-loss delta 0, session source frames 4188, continuity frames 4075, captured frames 4085, dropped frames 103, timestampRewriteFrames 4085, DataChannel ack count 74, ping ack p50 14.1ms/p95 229.75ms, tap ack 15.1ms, swipe ack 10.6ms, move-stream PASS with 30/30 touchMove acks plus down/up PASS, touch-to-photon PASS with 2/2 marker detections and latency p50 202.85ms/p95 286.59ms/max 295.9ms. Browser RVFC callback fps is 47.26 with frame interval p50 16.7ms, p95 34.29ms, max 250.3ms, and 172 gaps over 34ms, so v0.portal5m is measured against this latency/jitter and presentation-gap baseline.
v0.portal5m-latency-follow-rate: previous live flashed/read-only/smoke-proven Portal line. It starts from live-proven v0.portal5l, changes Smartisax APK to v0.6.13/versionCode 30, keeps services.jar unchanged at `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, and targets the v0.portal5l measured issues: touch-to-photon p50/p95 measurement skew from waiting on marker ack, DataChannel ack jitter/HOL pressure from one-message-per-move plus bulky marker status acks, and Chrome presentation gaps amplified by smoke-page DOM logging. The repair adds predictive marker status in the Chrome smoke path through a token-gated `/status` proxy, compact move acks that omit marker JSON unless flashing/requested, first-class `touchMoveBatch` with `pointCount` and `injectedEvents`, frame-aligned Portal move batching with an 8-point queue cap, move-event rather than move-ack summary accounting, and throttled smoke log rendering. APK hash is `04b46c757e0cd0a0a5a2c58b1525ded25fc34a7dd13ff4d159123911f6bfad72`, system_b hash is `b37ff12f06e5cc304810b7a718fc4b9b8dc501d11326a23bd7475ff463d1f7f2`, and sparse super hash is `8ea6074817bd376ae0d2d17aeaf1ddd9432c3fb294d63f914d6bc02b06b564e8`. Build result is `PASS_BUILD_V0PORTAL5M_LATENCY_FOLLOW_RATE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5M_LATENCY_FOLLOW_RATE`; live read-only result is `PASS_READ_ONLY_V0PORTAL5M_LATENCY_FOLLOW_RATE`; latency/follow-rate smoke result is PASS. Flash evidence: final preflight passed, fastboot current-slot `b`, unlocked `yes`, is-userspace `no`, sparse super 1/9 through 9/9 OK in 232.378s, `erase misc` OK, reboot OK, post-boot `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root available with SELinux Enforcing. Device package path is `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode/versionName is `30`/`0.6.13`, READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION are granted=true, libwebrtc arm64/arm hashes match, device APK hash matches the candidate APK hash, current focus is `com.smartisax.browser/.ShellActivity`, and `isKeyguardShowing=false`. Smoke evidence: 1080/30 projection-texture PASS with H.264 1080x2340, decoded frames 1955, estimated fps 29.81, estimated bitrate 867426bps, packet-loss delta 0, source frames 2105, continuity frames 1960, captured frames 1974, dropped frames 131, timestampRewriteFrames 1974, ping ack p50 15.15ms/p95 97.67ms, input ack p50 15.15ms/p95 97.51ms, RVFC 28.11fps, frame interval p50 33.5ms/p95 66.6ms/max 150.1ms, 904 gaps over 34ms, move-stream PASS with batch size 5, injected move events 30/30, 26 move ack packets, down/up PASS, and touch-to-photon PASS with 2/2 detections and p50 192.4ms/p95 193.03ms/max 193.1ms. 1080/60 projection-texture PASS with H.264 1080x2340, decoded frames 3919, estimated fps 59.94, estimated bitrate 1619159bps, packet-loss delta 0, source frames 4212, continuity frames 4076, captured frames 4085, dropped frames 127, timestampRewriteFrames 4085, ping ack p50 15.25ms/p95 97.04ms, input ack p50 15.4ms/p95 99.5ms, RVFC 52.28fps, frame interval p50 16.7ms/p95 33.5ms/max 183.4ms, 80 gaps over 34ms, 24 over 50ms, move-stream PASS with batch size 5, injected move events 30/30, 25 move ack packets, down/up PASS, and touch-to-photon PASS with 2/2 detections and p50 154.45ms/p95 158.1ms/max 158.5ms. Compared with the v0.portal5l 1080/60 marker/move-stream baseline, v0.portal5m retains about-60fps decode and packet-loss delta 0 while improving touch-to-photon p95 from 286.59ms to 158.1ms, ping ack p95 from 229.75ms to 97.04ms, RVFC from 47.26fps to 52.28fps, gaps over 34ms from 172 to 80, and gaps over 50ms from 122 to 24.
v0.portal5n-latency-budget-queue-collapse: previous live flashed/read-only and smoke-tested Portal latency-budget line. It was built offline from the live-proven v0.portal5m line, changes only Smartisax APK to v0.6.14/versionCode 31, keeps services.jar unchanged at `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, keeps the measured H264-first codec cascade, and targets the remaining interactive latency budget by changing projection-texture continuity to latest-frame-only queue collapse, limiting pending continuity frames to one, exposing `continuityFrameSkips`/`maxPendingContinuityFrames`, splitting high-frequency move input onto low-retransmit `smartisax-input-move`, compacting move backpressure to the newest point, reducing the Portal move batch cap from 8 to 4, and reporting move channel state in Chrome smoke results. APK hash is `fb35e386649a51ff83eda8914fd02a9ffee3ca42c924d54b237b579c5abd6d7f`, system_b hash is `502e18835efe3d7a085f5cd9ac3b063f02bf129128a6c3f0ae05c982f9f2fc70`, and sparse super hash is `639e7cfcb7ca8c4f7a4b55fba18335714c291a9fa828951adf1e9363c7b11339`. Build result is `PASS_BUILD_V0PORTAL5N_LATENCY_BUDGET_QUEUE_COLLAPSE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5N_LATENCY_BUDGET_QUEUE_COLLAPSE`; live read-only result is `PASS_READ_ONLY_V0PORTAL5N_LATENCY_BUDGET_QUEUE_COLLAPSE`. Flash evidence: final preflight passed, fastboot current-slot `b`, unlocked `yes`, is-userspace `no`, sparse super 1/9 through 9/9 OK in 233.026s, `erase misc` OK, reboot OK, post-boot `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root available with SELinux Enforcing. Device package path is `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode/versionName is `31`/`0.6.14`, READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION are granted=true, libwebrtc arm64/arm hashes match, device APK hash matches the candidate APK hash, current focus is `com.smartisax.browser/.ShellActivity`, and `isKeyguardShowing=false`. Strict smoke result is PASS with move channel open, but not a final latency win: 1080/30 H264 decodes 1989 frames at 29.85fps with packet-loss delta 0, RVFC 23.99fps, 273 gaps over 34ms, ping ack p50/p95 18.05/144.41ms, and T2P p50/p95 221.7/221.7ms from 1/2 detections; 1080/60 decodes 3875 frames at 59.33fps with packet-loss delta 2, RVFC 45.23fps, 46 gaps over 34ms, 34 gaps over 50ms, ping ack p50/p95 16.05/91.73ms, and T2P p50/p95 205.85/208.6ms. Compared with v0.portal5m, 1080/60 gap count improves but T2P and RVFC regress.
v0.portal5o-input-frame-boost: previous live flashed/read-only Portal latency candidate; strict smoke was diagnostic rather than accepted. It starts from v0.portal5n, changes Smartisax APK to v0.6.15/versionCode 32, keeps services.jar unchanged at `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, keeps latest-frame-only queue collapse plus the dual move DataChannel, and adds input-frame-boost: after touch marker draw or non-marker high-frequency input, it requests an urgent projection `forceFrame()` near the next safe frame boundary and exposes `inputFrameBoostRequests`, `inputFrameBoostSkips`, and `inputFrameBoostFrames`. APK hash is `05c30d70bd4ed0401d4cc7885f63086b8a511e30ee73f6deb2f49fb36860df38`, system_b hash is `b0df788c0d548cb853c5ab22512e34499728b05876ac1f2ff3805d634d0af69d`, and sparse super hash is `1886be1676562e91e5860b14faeaf00d3cd4534b86b001596ff6a9638f60eec4`. Build result is `PASS_BUILD_V0PORTAL5O_INPUT_FRAME_BOOST`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5O_INPUT_FRAME_BOOST` with `smartisax_input_frame_boost=ok`; live read-only result is `PASS_READ_ONLY_V0PORTAL5O_INPUT_FRAME_BOOST`. Flash evidence: final preflight passed, fastboot current-slot `b`, unlocked `yes`, is-userspace `no`, sparse super 1/9 through 9/9 OK in 232.163s, `erase misc` OK, reboot OK, post-boot `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root available with SELinux Enforcing. Device package path is `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode/versionName is `32`/`0.6.15`, READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION are granted=true, libwebrtc arm64/arm hashes match, device APK hash matches the candidate APK hash, current focus is `com.smartisax.browser/.ShellActivity`, and `isKeyguardShowing=false`. Full strict smoke failed due profile-sequence instability: 1080/30 had no touch-to-photon detections and no move events, while 1080/60 then missed RVFC/loss gates. Clean single-profile 1080/60 rerun passed with H264, decoded fps 60.2, RVFC 54.2fps, packet-loss delta 0, gaps over 34ms 56, move-stream 30/30, input boost frames 14, and touch-to-photon p50/p95 133.25/138.51ms. Clean single-profile 1080/30 rerun kept H264 decoded fps 29.84, RVFC 27.76fps, packet-loss delta 0, move-stream 30/30, and input boost proof, but failed with 911 gaps over 34ms and touch-to-photon p50/p95 181.85/205.66ms.
v0.portal5p-dual-phase-input-boost: previous live flashed/read-only Portal latency candidate; no dedicated smoke was run before it was superseded by v0.portal5s. It starts from v0.portal5o, changes only Smartisax APK to v0.6.16/versionCode 33, keeps services.jar unchanged at `3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`, keeps latest-frame-only queue collapse plus dual move DataChannel, and changes input-frame boost to a dual-phase path: request `touch-marker-injected` boost immediately after marker-backed input injection, retain `touch-marker-drawn` boost after the overlay draw, and coalesce pending forceFrame work into the next continuity frame. APK hash is `d2c23440cdef4181422643520bfe5009f30b33df4903d6c65186a35f8961ac8a`, system_b hash is `354246abbac4ee418b78580ef75682cc9bc089be067c57066a397e602821e58a`, and sparse super hash is `4c7d83fbb34a5f9aa76edd65cc5088f9decb190d341f1b14f302f46f86d1c1ef`. Build result is `PASS_BUILD_V0PORTAL5P_DUAL_PHASE_INPUT_BOOST`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5P_DUAL_PHASE_INPUT_BOOST` with `smartisax_dual_phase_input_boost=ok`, `smartisax_input_frame_boost=ok`, and `smartisax_latest_frame_queue=ok`; live preflight result was PASS before flashing. Flash evidence: after the exact confirmation `确认刷入 v0.portal5p-dual-phase-input-boost B 槽`, fastboot current-slot was `b`, unlocked `yes`, is-userspace `no`, sparse super chunks 1/9 through 9/9 were written successfully in 232.609s, `erase misc` returned OK, and reboot returned OK. Post-boot read-only verification proves `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, package path `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode/versionName `33`/`0.6.16`, WRITE_SECURE_SETTINGS/MANAGE_DEBUGGING/READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION all granted=true, libwebrtc arm64/arm hashes match, device APK hash matches the candidate, current focus is `com.smartisax.browser/com.smartisax.browser.ShellActivity`, and `isKeyguardShowing=false`. Live result is `PASS_READ_ONLY_V0PORTAL5P_DUAL_PHASE_INPUT_BOOST`.
v0.portal5r-refresh-rate-60-90hz: unflashed Portal comparison candidate, built offline, offline-verified, and live-preflighted, but not flashed, read-only verified, or smoked. It starts from v0.portal5p and changes Smartisax to v0.6.18/versionCode 35. The target profile set changes from 1080/30 plus 1080/60 to hardware-aligned 1080/60 plus 1080/90, runtime maxFps becomes 90, max bitrate becomes 18000000, default target becomes 1080p90, and status/config expose `refreshRateProfiles=1080p60+1080p90`. It keeps dual-phase input boost and adds boost-token-retain semantics: capture-throttled early frames no longer consume pending input boost tokens until a frame is actually captured. APK hash is `29fbc902ada4f8b309c6c5f93fa8f9eaf0780fa7e9ddb6ddd2fe0a8514ed2a02`, system_b hash is `28f2a293b578e2c61c1c1aa5d4c566590f6d8d07c6c5f985e1e00965831dba86`, and sparse super hash is `157c4ebb19b5331b13492a464a0d15a0074f22af3b9ac8ff0894b48afeb6bfd7`. Build result is `PASS_BUILD_V0PORTAL5R_REFRESH_RATE_60_90HZ`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5R_REFRESH_RATE_60_90HZ` with `smartisax_boost_token_retain=ok`, `smartisax_dual_phase_input_boost=ok`, and `smartisax_apk_semantics=ok`; live preflight result is PASS and recorded current read-only state `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, and SELinux Enforcing. It remains a retained 60/90Hz comparison image; v0.portal5s has already been flashed and supersedes it for live evidence.
v0.portal5s-event-time-input-priority: previous live flashed/read-only Portal latency experiment; strict smoke is diagnostic FAIL, not accepted as the latency win. It starts directly from live/read-only v0.portal5p and includes the v0.portal5r 1080/60 plus 1080/90 target, runtime maxFps 90, max bitrate 18000000, default 1080p90, and boost-token-retain behavior while changing Smartisax to v0.6.19/versionCode 36. Its new latency repair preserves browser pointer/coalesced event timing through move-stream payloads and maps those deltas onto device MotionEvent uptime from the touchStart; it also lets input-triggered projection forceFrame captures use a half-frame interval while ordinary continuity remains paced to 60/90Hz. APK hash is `32727a16d70c15cbd7f4c20e0e953bf59555a57b91e96a22df03b7386992d6f0`, system_b hash is `2ae129226d18c10e7e7331bc01842305b7ab32d794b20aad7d92f00ba6d23191`, and sparse super hash is `b947a9456c11284810b1f976691c689d2158798c5c3ed504865bfaecb851a5f2`. Build result is `PASS_BUILD_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY` with `smartisax_event_time_input=ok`, `smartisax_input_priority_frame=ok`, `smartisax_boost_token_retain=ok`, `smartisax_dual_phase_input_boost=ok`, and `smartisax_apk_semantics=ok`; live preflight result was PASS before flashing. Flash evidence: after exact confirmation `确认刷入 v0.portal5s-event-time-input-priority B 槽`, fastboot current-slot was `b`, unlocked `yes`, is-userspace `no`, sparse super chunks 1/9 through 9/9 were written successfully in 232.184s, `erase misc` returned OK, and reboot returned OK. Post-boot read-only verification proves `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, package path `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode/versionName `36`/`0.6.19`, WRITE_SECURE_SETTINGS/MANAGE_DEBUGGING/READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION all granted=true, libwebrtc arm64/arm hashes match, device APK hash matches the candidate, current focus is `com.smartisax.browser/com.smartisax.browser.ShellActivity`, and `isKeyguardShowing=false`. Live result is `PASS_READ_ONLY_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY`. Strict smoke evidence: the full 1080/60 plus 1080/90 run connected both profiles with H264, packet-loss delta 0, move-stream PASS, and input-frame-boost PASS, but failed gates. 1080/60 decoded 3944 frames at 60.01fps with RVFC 44.46fps, 117 gaps over 34ms, and T2P p50/p95 160.1/165.86ms; 1080/90 decoded 5568 frames at 85.14fps with RVFC 31.62fps, 33 gaps over 34ms, and T2P p50/p95 213.6/298.92ms. A clean single 1080/60 rerun decoded 3947 frames at 60.13fps with packet-loss delta 0 and 34 gaps over 34ms, but still failed RVFC 47.98fps and T2P p50/p95 266.85/370.85ms.
v0.portal5t-marker-burst-presentation: prepared next Portal latency candidate; built, offline-verified, and live-preflighted from the current live/read-only v0.portal5s image, but not flashed or smoked yet. It updates Smartisax to v0.6.20/versionCode 37, keeps the 1080/60 plus 1080/90 target, event-time move-stream input, boost-token-retain, and input-priority half-frame capture, then replaces the marker-drawn single boost with a short marker-visible burst of up to four input-priority projection frames. APK hash is `4d55ff08af4e656b8a1218645b1e7e44746c550f126084d4b3ec165685606c31`, system_b hash is `2ab359e6b6c16e0f0e8335c045df6a422c879c5da6b5294c334f815bbf76a1d6`, and sparse super hash is `7417c6abcabca10dacf77d50e6dbdb84bf54414b074e23f7737c3ec929843bdd`. Build result is `PASS_BUILD_V0PORTAL5T_MARKER_BURST_PRESENTATION`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5T_MARKER_BURST_PRESENTATION` with `smartisax_marker_burst_boost=ok`, `smartisax_input_priority_frame=ok`, `smartisax_event_time_input=ok`, `smartisax_boost_token_retain=ok`, and `smartisax_apk_semantics=ok`; live preflight result is PASS and recorded current device state as `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing. Required exact flash confirmation: `确认刷入 v0.portal5t-marker-burst-presentation B 槽`.
v0.portal5u-burst-reschedule-presentation: previous live flashed/read-only Portal latency candidate; built, offline-verified, live-preflighted from the current live/read-only v0.portal5s image, flashed to B slot after exact confirmation, booted, read-only verified, and strict-smoked. It updates Smartisax to v0.6.21/versionCode 38, keeps the v0.portal5t marker-visible burst, and changes the burst scheduler so pending burst budget is only decremented after an input-priority frame request is accepted by the projection frame pump; coalesced pending/scheduled boost work is retried and exposed through `inputFrameBoostBurstRetries`, `inputFrameBoostBurstPendingFrames`, `inputFrameBoostBurstActiveFrames`, and `lastInputFrameBoostBurstRetryElapsedMs`. APK hash is `31f75eb17d5800cf325e21d0d5e543d58b6234e5cbfc25422c0391a58bd3b6ed`, system_b hash is `7a0542497e74e323354bdfacd6ba366e929531d5e2678e995592fc6af796a5d5`, and sparse super hash is `4515ab16ff5dc443c91cd455c6361aeac3016fd728bc8abd9dbe70d3d7ac3db8`. Build result is `PASS_BUILD_V0PORTAL5U_BURST_RESCHEDULE_PRESENTATION`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5U_BURST_RESCHEDULE_PRESENTATION` with `smartisax_marker_burst_reschedule=ok`, `smartisax_marker_burst_boost=ok`, `smartisax_input_priority_frame=ok`, `smartisax_event_time_input=ok`, `smartisax_boost_token_retain=ok`, and `smartisax_apk_semantics=ok`; live preflight result was PASS before flashing. Flash evidence: after exact confirmation `确认刷入 v0.portal5u-burst-reschedule-presentation B 槽`, fastboot current-slot was `b`, unlocked `yes`, is-userspace `no`, sparse super chunks 1/9 through 9/9 were written successfully in 234.097s, `erase misc` returned OK, and reboot returned OK. Post-boot read-only verification proves `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, package path `/system/priv-app/SmartisaxShell/SmartisaxShell.apk`, versionCode/versionName `38`/`0.6.21`, WRITE_SECURE_SETTINGS/MANAGE_DEBUGGING/READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION all granted=true, libwebrtc arm64/arm hashes match, device APK hash matches the candidate, current focus is `com.smartisax.browser/com.smartisax.browser.ShellActivity`, and `isKeyguardShowing=false`. Live result is `PASS_READ_ONLY_V0PORTAL5U_BURST_RESCHEDULE_PRESENTATION`. Strict smoke result is diagnostic FAIL, not accepted: both 1080/60 and 1080/90 H264 sessions connected with packet-loss delta 0, move-stream PASS, and input-frame-boost PASS; 1080/60 decoded 3881 frames at 59.23fps but failed RVFC 46.98fps, 161 gaps over 34ms, and T2P p50/p95 239.35/265.04ms; 1080/90 decoded 5603 frames at 85.4fps and T2P p50/p95 128.35/134.61ms passed, but RVFC 47.96fps and 158 gaps over 34ms failed. The next Portal repair should target Chrome presentation/RVFC cadence rather than more input boost alone.
v0.portal5v-presentation-cadence: prepared next Portal presentation-cadence candidate; built, offline-verified, and read-only preflighted from the current live/read-only v0.portal5s image, but not flashed or smoked yet. It updates Smartisax to v0.6.22/versionCode 39, keeps v0.portal5u's marker-burst-reschedule behavior, and changes the browser/receiver side by setting RTCRtpReceiver `playoutDelayHint=0` where supported, applying `contentHint="motion"` to the remote video track, disabling remote playback on the Portal video element, and carrying RTC jitter buffer/playout/drop/freeze fields into the strict smoke summary. APK hash is `3da3b86d74a4c78a3b98d0095bb7718a951f06c0feee96974d383207334e2509`, system_b hash is `bd6f4f2d6a4ae028d1096a065942bfe7fb543b445c5b4ae6522cccec936470c5`, and sparse super hash is `9fbef52aee9ecffd146f0d949047107be6bbbfb1ca6ebb4762a00c7387742fff`. Build result is `PASS_BUILD_V0PORTAL5V_PRESENTATION_CADENCE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5V_PRESENTATION_CADENCE` with `smartisax_presentation_cadence=ok`, `smartisax_marker_burst_reschedule=ok`, and `smartisax_apk_semantics=ok`; read-only preflight result passed in the current terminal run but is not persisted to a report file because the follow-up tee/redirect escalation was rejected. Required exact flash confirmation: `确认刷入 v0.portal5v-presentation-cadence B 槽`.
v0.portal5w-quiet-presentation: previous live flashed/read-only Portal quiet-presentation candidate; built, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, and strict-smoked before being superseded by v0.portal5x. It updates Smartisax to v0.6.23/versionCode 40, keeps v0.portal5u's marker-burst-reschedule behavior and v0.portal5v's receiver presentation cadence repair, then reduces browser-side presentation noise by suppressing WebRTC DOM/log churn, using a quiet presentation surface with video containment/compositor hints, and adding RAF main-thread drift diagnostics beside RVFC cadence in the strict smoke summary. APK hash is `04c3e0ad784278ce82e31aecb89f9e1fe73b0dc312f9a6ad3f285ec5a6e1672d`, system_b hash is `0c54440dcfde80c389dce5b40f854a94eae8e5c10f6c7634861063fbf35e823b`, and sparse super hash is `bf7145e79050d65cba96b1c0451c8b5c246957f8ef2fb9c513cc2966db77b593`. Build result is `PASS_BUILD_V0PORTAL5W_QUIET_PRESENTATION`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5W_QUIET_PRESENTATION` with `smartisax_quiet_presentation=ok`, `smartisax_presentation_cadence=ok`, `smartisax_marker_burst_reschedule=ok`, and `smartisax_apk_semantics=ok`; live result is `PASS_READ_ONLY_V0PORTAL5W_QUIET_PRESENTATION`. Strict smoke result is diagnostic FAIL, not accepted: both 1080/60 and 1080/90 H264 sessions connected with packet-loss delta 0, move-stream PASS, input-frame-boost PASS, and RAF near 59.9fps; 1080/60 decoded 59.16fps with RVFC 50.45fps, 103 gaps over 34ms, and T2P p95 1050.39ms; 1080/90 decoded 86.8fps but RVFC fell to 30.27fps, gaps over 34ms rose to 461, and T2P p95 was 290.71ms. The bottleneck remains video presentation/VirtualDisplay/WebRTC renderer cadence rather than transport, input, or Chrome RAF alone.

v0.portal5x-presenter-mode: previous live flashed/read-only Portal presenter-mode candidate; built, offline-verified, live-preflighted, flashed to B slot after exact confirmation, booted, read-only verified, and strict-smoked before being superseded by v0.portal5y. It updates Smartisax to v0.6.24/versionCode 41 and adds `PRESENTER_MODE=canvas` support so WebRTC video can keep decoding while a RAF-driven canvas becomes the visible surface for marker pixel detection. The smoke records video RVFC, RAF drift, canvas draw cadence, canvas media-change cadence, and detection source. APK hash is `370090e6647d3e07e3defb7a459295413a5465bc729ee9c08452c902225ac450`, system_b hash is `3dcdd89252b549184cb41bc044de7d64377987fc5e91b65347b685afcd97aa09`, and sparse super hash is `3d72fe25ae50542edca42edc0472f70f16deef320fc5dde0a8ecc6eebfad2f6d`. Build result is `PASS_BUILD_V0PORTAL5X_PRESENTER_MODE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5X_PRESENTER_MODE` with `smartisax_presenter_mode=ok`; live result is `PASS_READ_ONLY_V0PORTAL5X_PRESENTER_MODE`. Strict smoke result is diagnostic FAIL, not accepted: both 1080/60 and 1080/90 H264 sessions connected with move-stream PASS, input-frame-boost PASS, and RAF/canvas draw near 60fps. 1080/60 decoded 59.8fps with packet-loss delta 0, RVFC 42.26fps, 167 RVFC gaps over 34ms, canvas gaps over 34ms = 1, and T2P p50/p95 144.1/173.08ms. 1080/90 decoded 86.64fps but had packet-loss delta 176, RVFC 35.05fps, 310 RVFC gaps over 34ms, canvas gaps over 34ms = 0, and T2P p50/p95 140.45/143.65ms. The visible canvas-presenter feedback path is healthier than v0.portal5w and motivated the v0.portal5y 60fps transport pacing experiment.
v0.portal5y-presentation-transport-pacing: previous live flashed/read-only Portal presentation/transport pacing candidate; built, offline-verified, live-preflighted from the live/read-only v0.portal5x image, flashed to B slot after exact confirmation, booted, read-only verified, and strict-smoked before being superseded by v0.portal5z. It updates Smartisax to v0.6.25/versionCode 42, keeps 5x canvas presenter and marker T2P diagnostics, and decouples requested/input cadence from WebRTC video cadence: 1080/90 keeps requested `fps=90` and `inputRefreshHz=90`, but `presentationFps=60`/`transportFps=60` drives VirtualDisplay/WebRTC video capture/send at 60fps while capping the 90-profile bitrate to 6/9/10Mbps. Status/config now expose `requestedFps`, `presentationFps`, `transportFps`, `inputRefreshHz`, `maxPresentationFps`, and `transportPacing=virtualdisplay-60fps-presentation-paced-90hz-input`. APK hash is `17221eab917d34b4327ce59385765211c91335e59d89d959bf9aefd672dabbe6`, system_b hash is `05454c258274b9c1f3b69bf875b60bd5deea6957d6dc6ed1e2a6e1ab0d04cfcd`, and sparse super hash is `c20ad88972c3395b848f5941b5bf12f8b5674d00da3cf9ccd6fca673ca28e4dc`. Build result is `PASS_BUILD_V0PORTAL5Y_PRESENTATION_TRANSPORT_PACING`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5Y_PRESENTATION_TRANSPORT_PACING` with `smartisax_presentation_transport_pacing=ok` and `smartisax_presenter_mode=ok`; final live preflight PASS is `preflight-v0.portal5y-presentation-transport-pacing-20260624-231831.txt`; live result is `PASS_READ_ONLY_V0PORTAL5Y_PRESENTATION_TRANSPORT_PACING`. Strict smoke result is diagnostic FAIL, not accepted: both 1080/60 and 1080/90 H264 sessions connected with projection-texture 1080x2340, input PASS, move-stream PASS, input-frame-boost PASS, and packet-loss delta 0. 1080/60 decoded 60.04fps with RVFC 43.5fps, 21 RVFC gaps over 34ms, RAF 60fps, canvas draw 59.95fps, ping ack p50/p95 15.8/101.39ms, and T2P p50/p95 205.35/253.82ms. 1080/90 decoded 55.14fps with RVFC 31.45fps, 91 RVFC gaps over 34ms, max frame delta 14016.7ms, 133 dropped frames, 15 freezes, 7080ms freeze time, ping ack p50/p95 16.65/97.78ms, and T2P p50/p95 175.15/176.99ms. The 5y experiment solves the 5x 1080/90 packet-loss boundary but exposes Chrome presentation/main-thread freeze and RVFC/media-change cadence as the next bottleneck.
v0.portal5z-video-primary-roi-probe: previous live flashed/read-only Portal presentation/latency candidate and current comparison boundary; built, offline-verified, live-preflighted from the v0.portal5y sparse, flashed to B slot after exact confirmation, booted, read-only verified, and strict-smoked diagnostically. It updates Smartisax to v0.6.26/versionCode 43, preserves v0.portal5y presentation/transport pacing, and adds a probe presenter mode where Chrome keeps the video element as the primary visible presenter while the smoke harness samples only the marker ROI and drives pending-marker touch-to-photon detection from RAF. The host-side smoke path avoids duplicate RVFC pixel sampling when RAF T2P detection is enabled, leaving RVFC as metric-only cadence/gap evidence. The target is to reduce smoke-page observation overhead and separate real presentation latency from full-frame canvas readback cost. APK hash is `9a6280585c996d9f54d0fb03cd1c43b5d49d4487b40b52dbf1780cde76d718ad`, system_b hash is `930e1b9aad2794527d4e34871073654393fca8cd5636e9e1902851cf3a14a6ed`, and sparse super hash is `3a622e32a540c077075d0e9259a6245338e38a24b65342a09c212a6032fda0df`. Build result is `PASS_BUILD_V0PORTAL5Z_VIDEO_PRIMARY_ROI_PROBE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL5Z_VIDEO_PRIMARY_ROI_PROBE` with `smartisax_video_primary_roi_probe=ok`, `smartisax_presentation_transport_pacing=ok`, and `smartisax_apk_semantics=ok`; live preflight result is PASS at `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/preflight-v0.portal5z-video-primary-roi-probe-20260625-000755.txt`; live result is `PASS_READ_ONLY_V0PORTAL5Z_VIDEO_PRIMARY_ROI_PROBE`. Flash evidence: after exact confirmation `确认刷入 v0.portal5z-video-primary-roi-probe B 槽`, the helper reran preflight, confirmed sparse hash `3a622e32a540c077075d0e9259a6245338e38a24b65342a09c212a6032fda0df`, fastboot current-slot was `b`, unlocked `yes`, is-userspace `no`, sparse super chunks 1/9 through 9/9 were written successfully in 236.102s, `erase misc` returned OK, and reboot returned OK. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, Smartisax Shell focus, `isKeyguardShowing=false`, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. Strict smoke result is diagnostic FAIL, not accepted: both 1080/60 and 1080/90 H264 sessions connected with projection-texture 1080x2340, input PASS, move-stream PASS, and input-frame-boost PASS. The original 5z smoke showed 1080/60 decoded 59.3fps but RVFC was 31.41fps, packet-loss delta 4, RVFC gaps over 34ms 95, ping ack p50/p95 17.85/79.58ms, and T2P p50/p95 153.9/192.96ms; 1080/90 decoded 59.38fps with packet-loss delta 0 and RAF 59.99fps, but RVFC was 49.09fps, RVFC gaps over 34ms 111, ping ack p50/p95 21/297.16ms, and T2P p50/p95 357.7/401.98ms. A no-flash rerun after adding Chrome anti-throttle launch flags, fixed window sizing, compact summary output, and page lifecycle/RVFC/RAF timeline fields kept packet-loss delta 0 on both profiles and RAF near 60fps, but still failed gates: 1080/60 decoded 59.76fps with RVFC 49.79fps, 79 RVFC gaps over 34ms, ping p50/p95 16.6/95.31ms, and T2P p50/p95 409.25/591.54ms; 1080/90 decoded 60.03fps with RVFC 48.38fps, 146 RVFC gaps over 34ms, ping p50/p95 14.95/95.55ms, and T2P p50/p95 189.1/214.03ms. `document.hidden` stayed false and RAF stayed clean, so the original 22s-class presentation gap is now classified as host-window/background noise; video RVFC cadence and marker-visible tail latency remain the blocker. The Chrome foreground activation path is present in the smoke harness but still unvalidated until a fresh pairing code or explicit Portal restart. Summary evidence is `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/portal-video-primary-roi-probe-smoke-live/projection-texture-summary.md`.
v0.portal6a-marker-draw-sync: previous live flashed/read-only Portal latency candidate; built, offline-verified, live-preflighted from the previous live/read-only v0.portal5z image, flashed to B slot after exact confirmation, booted, and read-only verified, but superseded by v0.portal6b before strict smoke. It updates Smartisax to v0.6.27/versionCode 44, preserves v0.portal5z video-primary ROI probe, H264/default codec policy, move-stream, input-frame boost, and 60/90Hz input with 60fps video transport pacing, then changes the marker boost timing so each marker flash arms an Android `OnDrawListener`, records `lastDrawnElapsedMs`/`lastDrawLatencyMs`, and requests marker capture boost plus burst after the marker view participates in the draw pass. APK hash is `25a4c9f05e61983911761668915cdfd9af6b0fe7e61cd68cd89bc8e7866ecd70`, system_b hash is `a35a82f194eb06a7f6199562ff87ea9db4f5875ccf536275993d864fc917f5a0`, and sparse super hash is `b8d2bbe12c3d889fa83963ea8d8e31e2a47b2a460c075d11b29ba4d1676fcc2a`. Build result is `PASS_BUILD_V0PORTAL6A_MARKER_DRAW_SYNC`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL6A_MARKER_DRAW_SYNC` with `smartisax_marker_draw_sync=ok`, `smartisax_video_primary_roi_probe=ok`, and `smartisax_apk_semantics=ok`; live preflight result is PASS at `hard-rom/inspect/v0.portal6a-marker-draw-sync/preflight-v0.portal6a-marker-draw-sync-20260625-012222.txt`; live result is `PASS_READ_ONLY_V0PORTAL6A_MARKER_DRAW_SYNC`. Flash evidence: after exact confirmation `确认刷入 v0.portal6a-marker-draw-sync B 槽`, the helper reran preflight, confirmed sparse hash `b8d2bbe12c3d889fa83963ea8d8e31e2a47b2a460c075d11b29ba4d1676fcc2a`, fastboot current-slot was `b`, unlocked `yes`, is-userspace `no`, sparse super chunks 1/9 through 9/9 were written successfully in 233.534s, `erase misc` returned OK, and reboot returned OK. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, Smartisax Shell focus, `isKeyguardShowing=false`, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. Evidence: `hard-rom/inspect/v0.portal6a-marker-draw-sync/flash-v0.portal6a-marker-draw-sync-20260625-013740.txt`, `hard-rom/inspect/v0.portal6a-marker-draw-sync/boot-wait-v0.portal6a-marker-draw-sync-20260625-013740.txt`, `hard-rom/inspect/v0.portal6a-marker-draw-sync/verify-v0.portal6a-marker-draw-sync-device-read-only-20260625-014307.txt`, and `hard-rom/inspect/v0.portal6a-marker-draw-sync/post-flash-focus-v0.portal6a-marker-draw-sync-20260625-013740.txt`.
v0.portal6b-draw-urgent-boost: previous live flashed/read-only Portal latency candidate and current performance diagnostic boundary; built, offline-verified, read-only preflighted from v0.portal6a, flashed to B slot after exact confirmation, booted, read-only verified, and strict-smoked diagnostically, but not accepted. It updates Smartisax to v0.6.28/versionCode 45 and keeps 6a marker draw-sync telemetry, then adds `draw-urgent-input-frame-boost`: after marker OnDraw, `touch-marker-drawn-urgent` can upgrade or issue an input boost with 0ms minimum spacing instead of the ordinary half-frame input boost spacing, while normal continuity cadence and burst retry limits remain intact. APK hash is `6484d7eb882f04e7a73ae7fb8539c070697abbd1235f1a598894b07230f9cc34`, system_b hash is `3956bfcd006b5448008088af4fc839847cdd85ca4c12ada77bc436c29237161a`, and sparse super hash is `057930f125ce07e5fc3c2940af4ac348102df7e8acbfe83d6a25467e4c3ee235`. Build result is `PASS_BUILD_V0PORTAL6B_DRAW_URGENT_BOOST`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL6B_DRAW_URGENT_BOOST` with `smartisax_marker_draw_sync=ok` and `smartisax_draw_urgent_boost=ok`; live result is `PASS_READ_ONLY_V0PORTAL6B_DRAW_URGENT_BOOST`. Flash evidence: after exact confirmation `确认刷入 v0.portal6b-draw-urgent-boost B 槽`, the helper reran preflight, confirmed sparse hash `057930f125ce07e5fc3c2940af4ac348102df7e8acbfe83d6a25467e4c3ee235`, fastboot current-slot was `b`, unlocked `yes`, is-userspace `no`, sparse super chunks 1/9 through 9/9 were written successfully in 231.766s, `erase misc` returned OK, and reboot returned OK. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, `isKeyguardShowing=false`, Smartisax Shell resumed, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. Strict smoke result is diagnostic FAIL: both 1080/60 and 1080/90 H264 sessions connected with projection-texture 1080x2340, input PASS, move-stream PASS, marker draw-sync PASS, and draw-urgent counters PASS. 1080/60 decoded 3602 frames at 55.03fps but failed RVFC 43.78fps, packet-loss delta 560, 127 RVFC gaps over 34ms, and T2P p50/p95 189.8/197.99ms; its urgent boost requests/frames were 4/4. 1080/90 decoded 3872 frames at 59.64fps with packet-loss delta 0 and RVFC 50.39fps PASS, but failed 102 RVFC gaps over 34ms and T2P p50/p95 183.75/186.86ms; its urgent boost requests/frames were 4/4. Evidence: `hard-rom/inspect/v0.portal6b-draw-urgent-boost/build-v0.portal6b-draw-urgent-boost-20260625-020852.txt`, `hard-rom/inspect/v0.portal6b-draw-urgent-boost/verify-v0.portal6b-draw-urgent-boost-offline-image-20260625-021233.txt`, `hard-rom/inspect/v0.portal6b-draw-urgent-boost/flash-v0.portal6b-draw-urgent-boost-20260625-022145.txt`, `hard-rom/inspect/v0.portal6b-draw-urgent-boost/boot-wait-v0.portal6b-draw-urgent-boost-20260625-022145.txt`, `hard-rom/inspect/v0.portal6b-draw-urgent-boost/verify-v0.portal6b-draw-urgent-boost-device-read-only-20260625-022709.txt`, `hard-rom/inspect/v0.portal6b-draw-urgent-boost/post-flash-focus-v0.portal6b-draw-urgent-boost-20260625-022145.txt`, and `hard-rom/inspect/v0.portal6b-draw-urgent-boost/portal-draw-urgent-boost-smoke-live/projection-texture-summary.md`. Next performance proof should repair 1080/60 packet loss and encoder/transport burst first, then reduce RVFC gap cadence and marker-visible T2P tail rather than adding more input boosts.
v0.portal6c-visible-screenbox: previous live flashed/read-only Portal UI visibility repair; built, offline-verified, read-only preflighted from v0.portal6b, flashed to B slot after exact confirmation, booted, read-only verified, and read-only checked through the served Portal homepage. It updates Smartisax to v0.6.29/versionCode 46 and preserves v0.portal6b WebRTC/draw-urgent/input behavior, but repairs the real Portal page `.screenBox` by removing parent `size` containment, adding stable `aspect-ratio: 1080 / 2340`, and keeping media elements filled at `height: 100%`. This addresses the user-visible Chrome/Safari symptom where pairing succeeded but no screen was visible, while the independent smoke harness could still see frames. APK hash is `d90161ce3a15a88b272ade654fdef131597114eb79a1f00ef32ca1d7cb12fe46`, system_b hash is `0854bd2deb455759baee791b4860f8be2cf1686675d32e662126c913a1c76c7c`, and sparse super hash is `df7912827b4201bcff601edcc300fe79654ffdc571dda860272eb6485a247a9a`. Build result is `PASS_BUILD_V0PORTAL6C_VISIBLE_SCREENBOX`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL6C_VISIBLE_SCREENBOX` with `smartisax_visible_screenbox=ok`, `smartisax_draw_urgent_boost=ok`, and `smartisax_apk_semantics=ok`; live result is `PASS_READ_ONLY_V0PORTAL6C_VISIBLE_SCREENBOX`. Flash evidence: after exact confirmation `确认刷入 v0.portal6c-visible-screenbox B 槽`, the helper reran preflight, confirmed sparse hash `df7912827b4201bcff601edcc300fe79654ffdc571dda860272eb6485a247a9a`, wrote sparse super chunks 1/9 through 9/9 successfully in 232.043s, erased `misc`, and rebooted. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, `isKeyguardShowing=false`, Smartisax Shell resumed, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. A read-only GET `/` after flashing proves the served asset includes `aspect-ratio: 1080 / 2340` and `contain: layout paint;`. Evidence: `hard-rom/inspect/v0.portal6c-visible-screenbox/build-v0.portal6c-visible-screenbox-20260625-134721.txt`, `hard-rom/inspect/v0.portal6c-visible-screenbox/verify-v0.portal6c-visible-screenbox-offline-image-20260625-135024.txt`, `hard-rom/inspect/v0.portal6c-visible-screenbox/flash-v0.portal6c-visible-screenbox-20260625-152802.txt`, `hard-rom/inspect/v0.portal6c-visible-screenbox/boot-wait-v0.portal6c-visible-screenbox-20260625-152802.txt`, `hard-rom/inspect/v0.portal6c-visible-screenbox/verify-v0.portal6c-visible-screenbox-device-read-only-20260625-153326.txt`, and `hard-rom/inspect/v0.portal6c-visible-screenbox/post-flash-focus-v0.portal6c-visible-screenbox-20260625-152802.txt`. This line is superseded by live v0.portal6d-display-wake-guard; use 6d for the next fresh-code real Portal visual smoke and the v0.portal6b/v0.portal6d 1080/60 plus 1080/90 performance gates.
v0.portal6d-display-wake-guard: previous live flashed/read-only Portal display wake repair; built, offline-verified, read-only preflighted from v0.portal6c, flashed to B slot after exact confirmation, booted, read-only verified, display/power probed, and real-Portal visual-smoked. It updates Smartisax to v0.6.30/versionCode 47, preserves the v0.portal6c visible screenBox repair, and adds `WAKE_LOCK`, ShellActivity screen-on/turn-screen-on behavior, and a `Smartisax:PortalWebRtc` display wake lock held during active WebRTC runtime sessions. A fresh-code real Portal Chrome visual smoke passed with non-black H264 1080x2340 video and both input DataChannels open. This line is superseded by live v0.portal6e for the 1080/60 packet-loss and encoder/transport burst gate. Evidence remains under `hard-rom/inspect/v0.portal6d-display-wake-guard/`.
v0.portal6e-encoder-transport-burst: previous live flashed/read-only Portal performance-gate candidate. It is the first returned 1080/60 plus 1080/90 performance candidate after live 6d real-Portal visibility PASS. It starts from live/read-only v0.portal6d, updates Smartisax to v0.6.31/versionCode 48, preserves the display wake guard and visible screenBox repairs, clamps the 1080p60/90 WebRTC sender bitrate window, sets sender degradation preference to `MAINTAIN_FRAMERATE`, and late-starts the projection frame pump after local SDP to target 1080/60 packet loss and encoder/transport burst before RVFC/T2P work. APK hash is `90421ef5613f5dafa5491735848ebe6588e2fe5d95ffb79929bfe00329a921ef`, system_b hash is `04cfe9746848f5daee752a13efb18ba3cb938d8c7969d5b48333c965f319a6b7`, and sparse super hash is `5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83`. Build result is `PASS_BUILD_V0PORTAL6E_ENCODER_TRANSPORT_BURST`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL6E_ENCODER_TRANSPORT_BURST`; live result is `PASS_READ_ONLY_V0PORTAL6E_ENCODER_TRANSPORT_BURST`; flash result is `PASS_FLASH_V0PORTAL6E_ENCODER_TRANSPORT_BURST`. Flash evidence: after exact confirmation `确认刷入 v0.portal6e-encoder-transport-burst B 槽`, the helper reran preflight, confirmed sparse hash `5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83`, wrote sparse super chunks 1/9 through 9/9 successfully in 234.467s, erased `misc`, and rebooted. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, `isKeyguardShowing=false`, Smartisax Shell focused after settling, `WAKE_LOCK: granted=true`, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. Display/window probe after flashing proves `mWakefulness=Awake`, `mHalInteractiveModeEnabled=true`, `mDisplayReady=true`, `mGlobalDisplayState=ON`, built-in display `state ON`, and current focus `com.smartisax.browser/com.smartisax.browser.ShellActivity`. Evidence: `hard-rom/inspect/v0.portal6e-encoder-transport-burst/build-v0.portal6e-encoder-transport-burst-20260625-165309.txt`, `hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-offline-image-20260625-170017.txt`, `hard-rom/inspect/v0.portal6e-encoder-transport-burst/preflight-v0.portal6e-encoder-transport-burst-20260625-170235.txt`, `hard-rom/inspect/v0.portal6e-encoder-transport-burst/flash-v0.portal6e-encoder-transport-burst-20260625-171510.txt`, `hard-rom/inspect/v0.portal6e-encoder-transport-burst/boot-wait-v0.portal6e-encoder-transport-burst-20260625-171510.txt`, `hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-device-read-only-20260625-172037.txt`, `hard-rom/inspect/v0.portal6e-encoder-transport-burst/post-flash-focus-v0.portal6e-encoder-transport-burst-20260625-171510.txt`, and `hard-rom/inspect/v0.portal6e-encoder-transport-burst/display-window-state-after-flash-20260625-172135.txt`.
v0.portal6e strict smoke with fresh pairing code `666132` has now run. Result is diagnostic FAIL, not accepted. The WebRTC/control path connected on both H264 profiles and 6e proved the intended 1080/60 packet-loss/encoder-transport burst repair: 1080/60 packetLossDelta is `0`, down from v0.portal6b's `560`. Remaining strict blockers are video presentation/RVFC cadence and marker-visible T2P tail. 1080/60 decoded `3590` frames at `54.54fps`, RVFC `41.92fps`, had `158` RVFC gaps over 34ms, ping ack p50/p95 `16.3/97.69ms`, and T2P p50/p95 `347.5/471.07ms`. 1080/90 decoded `3884` frames at `59.14fps`, T2P p50/p95 `138.55/163.98ms` PASS, ping ack p50/p95 `14.05/67.58ms`, but packetLossDelta was `2`, RVFC was `47.7fps`, and RVFC gaps over 34ms were `126`. Summary evidence: `hard-rom/inspect/v0.portal6e-encoder-transport-burst/portal-encoder-transport-burst-smoke-live/projection-texture-summary.md`. This led to the current live 6f RVFC/presentation cadence and 1080/60 marker-visible T2P-tail candidate rather than adding more input boost.
v0.portal6f-presentation-tail-cadence: previous live flashed/read-only Portal presentation-tail candidate. It builds from live/read-only v0.portal6e, updates Smartisax to v0.6.32/versionCode 49, and targets the remaining RVFC/presentation cadence plus 1080/60 marker-visible T2P tail blockers. It paces marker-visible tail boost frames at full presentation-frame cadence instead of half-frame input-boost cadence, extends the marker visible window to 1200ms, requests the draw-urgent frame immediately inside marker `onDraw()`, adds `inputFrameBoostBurstCadenceMs` diagnostics, and records receiver `jitterBufferTarget` plus `rvfc-presentation-cadence-lite` browser diagnostics. APK hash is `98b517b37cfcccce93f0724464b3d874c911efe9a6166e9775c345bceffb0db5`, system_b hash is `0cd94324a512d5cb1fd9eed87f7aa82b49e586062033c08a81a96e7c0ab937b2`, and sparse super hash is `d0bd5eb4653d8e019fdfea6fbe7815895c9ab57b87bc441b38ed7b8112465d9a`. Build result is `PASS_BUILD_V0PORTAL6F_PRESENTATION_TAIL_CADENCE`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL6F_PRESENTATION_TAIL_CADENCE` with `smartisax_presentation_tail_cadence=ok`; live result is `PASS_READ_ONLY_V0PORTAL6F_PRESENTATION_TAIL_CADENCE`; flash result is `PASS_FLASH_V0PORTAL6F_PRESENTATION_TAIL_CADENCE`. Flash evidence: after exact confirmation `确认刷入 v0.portal6f-presentation-tail-cadence B 槽`, the helper reran preflight, confirmed sparse hash `d0bd5eb4653d8e019fdfea6fbe7815895c9ab57b87bc441b38ed7b8112465d9a`, wrote sparse super chunks 1/9 through 9/9 successfully in 233.343s, erased `misc`, and rebooted. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, `isKeyguardShowing=false`, Smartisax Shell focused after settling, `WAKE_LOCK: granted=true`, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. Display/window probe after flashing proves `mWakefulness=Awake`, `mHalInteractiveModeEnabled=true`, `mDisplayReady=true`, display power `state=ON`, current focus `com.smartisax.browser/com.smartisax.browser.ShellActivity`, and the ShellActivity window is on-screen/visible. Evidence: `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/build-v0.portal6f-presentation-tail-cadence-20260625-190344.txt`, `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/verify-v0.portal6f-presentation-tail-cadence-offline-image-20260625-190751.txt`, `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/preflight-v0.portal6f-presentation-tail-cadence-20260625-191141.txt`, `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/flash-v0.portal6f-presentation-tail-cadence-20260625-202928.txt`, `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/boot-wait-v0.portal6f-presentation-tail-cadence-20260625-202928.txt`, `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/verify-v0.portal6f-presentation-tail-cadence-device-read-only-20260625-203453.txt`, `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/post-flash-focus-v0.portal6f-presentation-tail-cadence-20260625-202928.txt`, and `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/display-window-state-after-flash-20260625-203526.txt`. Safari fallback strict smoke with pairing code `176725` passes both 1080/60 and 1080/90 visibility/playback/control/T2P gates; in-app browser Chrome-side smoke with pairing code `998599` is diagnostic FAIL only because 1080/60 RVFC gaps over 34ms are 123 against the <=60 gate, while 1080/90 passes.
v0.portal6f Safari fallback strict smoke has now passed with pairing code `176725`, using a Safari wrapper because Google Chrome is not installed on this Mac. Both profiles selected H264 and displayed 1080x2340: 1080/60 decoded 3855 frames at 59.77fps with packetLossDelta 0, RVFC 55.65fps, 18 RVFC gaps over 34ms, move-stream PASS, and T2P p50/p95/max 115.5/116.85/117ms; 1080/90 decoded 3855 frames at 59.93fps with packetLossDelta 0, RVFC 56.16fps, 10 RVFC gaps over 34ms, move-stream PASS, and T2P p50/p95/max 128/140.6/142ms. Evidence: `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-safari-176725/projection-texture-summary.md`. Treat this as Safari visibility/playback/control/T2P PASS.
v0.portal6f in-app browser Chrome-side cadence smoke with pairing code `998599` has now run at 540x1170 viewport. It is diagnostic FAIL overall, but proves low packet loss, low input ack, and low T2P on the Chrome-like receiver path. 1080/60 selected H264, displayed 1080x2340, decoded 3878 frames at 59.76fps, packetLossDelta 0, RVFC 51.2fps, RAF 60fps, move-stream PASS, and T2P p50/p95/max 102.95/124.42/126.8ms; the failing gate is RVFC gaps over 34ms = 123 against <=60. 1080/90 selected H264, displayed 1080x2340, decoded 3874 frames at 59.93fps, packetLossDelta 0, RVFC 53.79fps, RVFC gaps over 34ms 63, move-stream PASS, and T2P p50/p95/max 113.55/129.26/131ms; it passes. Evidence: `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-iab-998599/projection-texture-summary.md`. Next work should reduce 1080/60 RVFC/media callback tail clustering while preserving the clean packet-loss and T2P results.

v0.portal6g-rvfc-media-tail: current live flashed/read-only Portal 1080/60 RVFC/media callback tail repair candidate. It builds from live/read-only v0.portal6f, updates Smartisax to v0.6.33/versionCode 50, and targets the in-app browser Chrome-side 1080/60 `frameGapsOver34ms=123` failure. The exact 1080/60 runtime branch now reports `1080p60-rvfc-media-callback-tail-dephase+sender-59fps+7mbps-window+full-frame-forceFrame-spacing`, explicitly preserves `inputRefreshHz=90` in the smoke profile, caps the 1080p60 sender at 59fps, narrows the 1080p60 target/max bitrate window to 7000000bps, removes the normal continuity forceFrame early margin for that branch, spaces continuity/marker tail forceFrame cadence at the full media-frame interval, and adds `mediaCallbackTailRepair`, `mediaCallbackTailFrameSpacingMs`, and `senderMaxFramerate` runtime diagnostics. 1080/90 remains on the 6f presentation/transport pacing path. APK hash is `442276dfaf1e70ecf0209818ed61b207bae72194fc490f8c601471b6a43f9f6a`, system_b hash is `941c660259f32270eaf4e3a8a5778b8518d4035e0f5efb73a8b704fd7d4b4241`, and sparse super hash is `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`. Valid build result is `PASS_BUILD_V0PORTAL6G_RVFC_MEDIA_TAIL`; offline result is `PASS_OFFLINE_IMAGE_V0PORTAL6G_RVFC_MEDIA_TAIL` with `smartisax_media_callback_tail_repair=ok`; live result is `PASS_READ_ONLY_V0PORTAL6G_RVFC_MEDIA_TAIL`; flash result is `PASS_FLASH_V0PORTAL6G_RVFC_MEDIA_TAIL`. Flash evidence: after exact confirmation `确认刷入 v0.portal6g-rvfc-media-tail B 槽`, the helper reran preflight, confirmed sparse hash `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`, wrote sparse super chunks 1/9 through 9/9 successfully in 232.720s, erased `misc`, and rebooted. Post-boot checks prove `sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`, root uid=0, SELinux Enforcing, `isKeyguardShowing=false`, Smartisax Shell focused after settling, `WAKE_LOCK: granted=true`, device APK hash matches the candidate, and device libwebrtc arm64/arm hashes match. Display/window probe after flashing proves `mWakefulness=Awake`, `mHalInteractiveModeEnabled=true`, `mDisplayReady=true`, built-in display `state ON`, `mCurrentFocus=com.smartisax.browser/com.smartisax.browser.ShellActivity`, and the ShellActivity window is on-screen/visible. Evidence: `hard-rom/inspect/v0.portal6g-rvfc-media-tail/build-v0.portal6g-rvfc-media-tail-20260629-202323.txt`, `hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-offline-image-20260629-202657.txt`, `hard-rom/inspect/v0.portal6g-rvfc-media-tail/preflight-v0.portal6g-rvfc-media-tail-20260629-202908.txt`, `hard-rom/inspect/v0.portal6g-rvfc-media-tail/flash-v0.portal6g-rvfc-media-tail-20260629-203737.txt`, `hard-rom/inspect/v0.portal6g-rvfc-media-tail/boot-wait-v0.portal6g-rvfc-media-tail-20260629-203737.txt`, `hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-device-read-only-20260629-204302.txt`, `hard-rom/inspect/v0.portal6g-rvfc-media-tail/post-flash-focus-v0.portal6g-rvfc-media-tail-20260629-203737.txt`, and `hard-rom/inspect/v0.portal6g-rvfc-media-tail/display-window-state-after-flash-20260629-204340.txt`. An earlier local build report `build-v0.portal6g-rvfc-media-tail-20260629-202003.txt` used the stale 6f APK hash and was superseded by the valid 20:23 build after rebuilding the APK.

Next 6g live gate: prefer a direct-in-Portal in-app-browser harness that reuses the already paired tab at `http://192.168.31.103:37601/`, then run the strict 1080/60 + 1080/90 schema from that page. Acceptance target remains 1080/60 RVFC gaps over 34ms <=60 while keeping packetLossDelta 0, low DataChannel ack, and T2P p95 near the 6f 125ms level. The older localhost receiver harness can still be used as a comparison once tab attach/control is reliable again.

Latest 6g smoke attempts: pairing codes `829543` and `808364` on 2026-06-30 are consumed, but produced only `CONTROL_FAIL` evidence. `829543` could not create/attach a Codex in-app-browser tab for the generated local receiver page. `808364` used manual-open fallback after the user opened the in-app browser, generated receiver URLs `http://127.0.0.1:60826/` for 1080/60 and `http://127.0.0.1:60958/` for 1080/90, but both profiles timed out after `180000ms` without a WebRTC answer. Pair/config/probe and runtime config passed; no decoded frames, RVFC, DataChannel ack, or T2P sample was produced, so neither attempt is a 6g performance result. Evidence is under `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-iab-829543/` and `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-iab-808364/`.

Direct 6g Portal diagnostic: reusing the already paired Codex in-app browser tab at `http://192.168.31.103:37601/` worked. A simplified no-pixel-T2P run connected both profiles with H264 1080x2340, packetLossDelta 0, open input/move DataChannels, and complete down/move/up acks. 1080/60 decoded at 55.66fps with RVFC 44.43fps and 61 RVFC gaps over 34ms; 1080/90 decoded at 57.36fps with RVFC 43.48fps and 83 gaps over 34ms. RAF stayed clean near 59.7fps with 0 gaps. Pixel T2P was intentionally disabled after a first marker-pixel probe stalled under in-app-browser automation throttling, so this is diagnostic evidence, not strict acceptance. Evidence is under `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-direct-in-app-browser-20260630-808364-session/`.

Safari 6g fresh-code strict smoke with pairing code `223229`: diagnostic FAIL overall because 1080/90 was visibility-contaminated, but 1080/60 is a strict Safari PASS. Preflight/config/probe passed. 1080/60 selected H264, displayed 1080x2340, decoded 3754 frames at 57.94fps, packetLossDelta 0, RVFC 56.18fps, RVFC gaps over 34ms = 6 against the <=60 gate, RAF 60.01fps with 0 gaps, T2P p50/p95/max 133/149.2/151ms, ping ack p50/p95 9/14ms, move stream PASS with 36/36 moves and 18 move acks, marker draw-sync PASS, inputFrameBoost PASS, urgent PASS, and page visibility stayed foreground with hiddenEvents 0 and blurEvents 0. 1080/90 selected H264, displayed 1080x2340, decoded 3859 frames at 59.72fps, packetLossDelta 0, T2P p50/p95/max 116/135.8/138ms, ping ack p50/p95 9/13.15ms, move stream PASS, marker draw-sync PASS, inputFrameBoost PASS, and urgent PASS, but RVFC was 38.93fps and RVFC gaps over 34ms were 163 after the receiver page entered `document.hidden=true`, `visibilityState=hidden`, and `hasFocus=false`; lifecycle events show blur at about 33315ms and visibilitychange hidden at about 33642ms. Treat 1080/90 as a Safari foreground/visibility contamination sample, not a clean 6g media failure. Evidence: `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-safari-223229/projection-texture-summary.md`.

WebView donor adaptation audit: enhanced offline; stock WebView and v0.31 dumped WebView PASS with adapt-in-place route, stock/v0.31 dumped WebView Trichrome bundle audit PASS_STANDALONE, BrowserChrome negative FAIL, and modern donors are now checked for Android 11 factory provider class, known WebView Application glue classes, Trichrome/static-library dependencies, multi-package bundle shape, static-library version/certDigest evidence, stale oat/vdex handling, and framework-provider-add vs adapt-in-place route. A local donor inbox scanner, dedicated Trichrome bundle gate, source/route plan, WebView integration plan generator, WebView ROM design plan generator, image-capacity gate, system_b space-source audit, super growth gate, FEC ext4-capacity baseline, and BrowserChrome stock near-noop/no-op gate are prepared. The original full M150 product_b-only image path remains blocked by product_b capacity, but v0.34 made a reviewed system_b provider-relocation candidate possible; v0.35 has now passed the read-only live PackageManager/WebViewUpdateService gate.
Browser/WebView version-gap audit: generated offline; stock BrowserChrome is app 9.0.6.4 with Chromium payload signals 90.0.4430.82/90.0.4430.210, while stock WebView is 75.0.3770.156/M75. The first real modernization route should therefore prioritize WebView Route A, adapting a standalone com.android.webview-compatible provider in place under /product/app/webview after v0.31 live proof; BrowserChrome behavior/engine replacement remains behind v0.32 live proof and a candidate diff audit
WebView framework contract audit: generated offline from framework-res, services.jar, framework.jar, SettingsSmartisan, and stock WebView. It proves the R2 framework whitelist contains only com.android.webview, Route A can avoid framework XML if the donor is adapted to com.android.webview, ROM system apps pass the signature gate, targetSdk must be >=30, versionCode is compared by /100000 cohort, WebViewLibrary metadata must point to libwebviewchromium.so, Android 11 requires WebViewChromiumFactoryProviderForR, and stock sandbox/native library counts are internally consistent. Integration and ROM design plans now treat this as a PASS gate; v0.31 live proof is also PASS. Modern source-built M150 WebView material is present, application_class is no longer a blocker, and A-SIG has offline PackageManager acceptance evidence for the stock-carrier path; image work still requires explicit ROM image acceptance and live-regression gates
WebView donor target matrix: generated offline from framework contract, donor inbox, integration plan, ROM design, and capacity evidence. It splits the practical routes into Route A1 source-built/adapted standalone com.android.webview as the preferred first target, Route A2 prebuilt standalone com.android.webview if a real donor exists, Route B com.google.android.webview via framework-provider-add, Route C Trichrome/static-library multi-package, Route D BrowserChrome as a separate browser track, and Route E native-library-only swap as rejected. The original product_b-only Route A1 layout remains capacity-blocked. v0.33 and v0.34 proved the safer capacity route by growing system_b metadata and ext4 with FEC; v0.35 uses that space for a system-provider relocation candidate instead of deleting TNT/projection or print packages. The live read-only provider gate has passed; donor-backed acceptance still needs user-facing browser/WebView/Big Bang regression testing
WebView Route A provider spec: generated offline; 17 requirements and 6 gates now define the acceptance contract for a future source-built/adapted standalone com.android.webview provider under /product/app/webview, including the same-package PackageManager signing/certificate-carrier transition gate. The spec is READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE and the target matrix now records route_a_provider_spec=RECORDED; current M150 source-built and stock-carrier candidates pass shape/design review inputs, but donor_backed_image_allowed remains false until an explicit candidate image and live proof exist
WebView Route A candidate audit: generated offline; the returned source-built M150 `SystemWebView-stock-carrier.apk` now maps to Route A as package com.android.webview, version 150.0.7871.28/787102801, donor PASS, bundle PASS_STANDALONE, and verdict CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE. It is still not image-authorized because signing/ROM/live gates remain open
WebView source-build readiness plan: generated offline with small official metadata fetch; current Chromium Dash Android Stable is 150.0.7871.28/M150 and the Chromium tag resolves to 48db307645dcbaa0bb5ccee0cd096cf22971bb84. The plan targets source-built standalone system_webview_apk as com.android.webview on an isolated x86-64 Linux builder and records GN args and candidate intake commands. The Alibaba ECS run has returned the APK; donor_backed_image_allowed remains false because explicit ROM image acceptance and live proof are still incomplete
WebView signing transition plan: generated offline for A-SIG-01; stock /product/app/webview/webview.apk is hash-verified, has APK Sig Block 42 present at offset 141623280 with 4096 block bytes, and keytool/jarsigner read the Smartisan Android certificate. The source-built `SystemWebView.apk` and `SystemWebView-stock-carrier.apk` are recorded. The A-SIG PackageManager audit proves offline that `/product/app/webview` is scanned as a system partition and that the stock-carrier candidate exposes the stock Smartisan WebView cert through Android-style v3 cert-only parsing, while apksigner full verification fails as expected. Current verdict is A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE and donor_backed_image_allowed=false
WebView A-SIG PackageManager audit: generated offline; compares stock WebView, source-built M150 WebView, and `SystemWebView-stock-carrier.apk` with apksigner full verification plus Android-style v2/v3 signer parsing. Verdict is OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE: good enough for Route A1 candidate image design review, not a user-installable APK and not live acceptance
WebView Linux builder kit: generated offline and executed on an Alibaba ECS x86-64 Linux builder. The builder produced Chromium 150.0.7871.28 `SystemWebView.apk` plus provenance metadata, which was copied back into `apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/`. The kit remains useful for reproducible rebuilds, but current image authorization is blocked by explicit ROM-image acceptance/live gates, not by missing APK material
WebView GitHub builder workflow: added offline; .github/workflows/webview-source-build.yml is a manual workflow_dispatch wrapper around the Linux builder kit for a large self-hosted or GitHub larger Ubuntu runner. It first regenerates the ignored hard-rom/inspect kit on the runner, defaults to mode=preflight, calls preflight-linux-builder.sh to require Linux x86-64 plus configured disk/RAM before any Chromium fetch/build, and uploads the returned dist only in mode=build. It does not authorize donor-backed images
WebView source-built local intake: completed for Chromium 150.0.7871.28. tools/r2-webview-sourcebuilt-intake.py validated returned dist provenance, copied the source-built APK, produced `SystemWebView-stock-carrier.apk`, reran signing-shape, A-SIG PackageManager audit, original/adapted Route A audits, integration plan, ROM design plan, and target matrix, and writes hard-rom/inspect/browser-webview-sourcebuilt-intake/sourcebuilt-system-webview-150-0-7871-28/sourcebuilt-intake.{md,tsv,json}; current verdict is INTAKE_RAN_REVIEW_OUTPUTS with donor_backed_image_allowed=false
generic APK locale-prune tool: verified offline on Protips, Tier1a first batch, LiveWallpapersPicker, HTMLViewer, PrintSpooler, BasicDreams, PhotoTable, ConferenceDialer, SimAppDialog, CompanionDeviceManager, SmartisanShareBrowser, TrackerSmartisan, and CleanerSmartisan
binary APK resources.arsc locale-prune fallback: verified offline on CleanerSmartisan after apktool/aapt2 rebuild failed on Smartisan private attrs
Confdialer same-size/in-place system_ext strategy: offline-proven and used in the v0.17b system_ext_b image; not live-verified yet
framework-res locale-prune probe: APK built offline; not a ROM image
framework-smartisanos-res locale-prune probe: binary arsc prune built offline
locale-prune coverage audit: generated from static ROM inventory and current gates
language full-prune coverage audit: generated full non-English/non-Chinese resource coverage
language next-batch plan: generated P0/P1/P2/P3/P4/P5 staged package queue; v0.24 consumes the CleanerSmartisan APK-only promotion and leaves 10 small P1 candidates
language P1 source-review audit: generated manifest/source-coupling review for the remaining 10 P1 small APK-only candidates
resource-loading map: graphify/static-source model for framework/app resources, overlays, locales, and Smartisan icon redirection
system-modification playbook: reusable gates for delete, replace, resources, framework, SettingsProvider, and boot surfaces
system-modification route audit: generated change-class route matrix for current gates and red-zone surfaces
launcher entry hide audit: generated manifest-only plan for hiding selected desktop app entries while preserving features
language source coupling audit: generated from stock sources and locale-prune evidence
language prune integration map: source-backed visible-list/framework/package/live-gate route
v0.17 APK-only promotion audit: generated partition/space/replacement-risk plan for promoting APK-only candidates into ROM images
language live-state audit: latest read-only live run passed on B slot and captured current locale/package shadow baseline
dark-mode source coupling audit: generated from stock sources and v0.11 evidence
dark-mode QS strategy audit: generated from stock QS defaults and Settings/SystemUI sources
dark-mode persistence audit: generated from SettingsProvider seed/reset/restore paths and v0.11 evidence
dark-mode integration map: source-backed Settings/UiMode/SystemUI/QS editor route
dark-mode live-state audit: latest read-only live run passed and captured UiMode/QS baseline
system-modification readiness audit: generated from current offline/live evidence
```

Latest verified v0.4 result:

```text
super sparse:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
sha256:
  313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5
post-flash:
  boot_completed=1, slot=_b, root available, launcher focused
```

Latest verified v0.24 result:

```text
super sparse:
  hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img
sha256:
  d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e
post-flash:
  flashed to B slot after explicit confirmation; boot_completed=1, slot=_b,
  root available, launcher focused, keyguard not showing
device verifier:
  hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-device-20260618-151156.txt
result:
  PASS: v0.24 device read-only verification
scope:
  all 11 promoted APK-only language-prune replacements match expected hashes
  on device and report shadow=no
rollback:
  keep v0.4 sparse local as fast rollback
```

Current local large-image retention:

```text
current local direct flash/rollback targets:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
    cold rollback sparse image
  hard-rom/build/super-otatrust-v0.portal5y-presentation-transport-pacing.sparse.img
    older presentation-transport pacing comparison image; read-only PASS, strict smoke diagnostic FAIL
  hard-rom/build/super-otatrust-v0.portal5z-video-primary-roi-probe.sparse.img
    previous live-flashed video-primary ROI probe image; read-only PASS, strict smoke diagnostic FAIL
  hard-rom/build/super-otatrust-v0.portal6a-marker-draw-sync.sparse.img
    previous live-flashed marker draw-sync image; read-only PASS, superseded before strict smoke
  hard-rom/build/super-otatrust-v0.portal6b-draw-urgent-boost.sparse.img
    previous live-flashed draw-urgent boost image; read-only PASS, strict smoke diagnostic FAIL
  hard-rom/build/super-otatrust-v0.portal6c-visible-screenbox.sparse.img
    previous live-flashed visible screenBox repair image; read-only PASS
  hard-rom/build/super-otatrust-v0.portal6d-display-wake-guard.sparse.img
    previous live-flashed display wake guard image; read-only PASS, real Portal visual smoke PASS
  hard-rom/build/super-otatrust-v0.portal6e-encoder-transport-burst.sparse.img
    previous live-flashed 1080/60 packet-loss and encoder-transport burst candidate; read-only PASS, strict smoke diagnostic FAIL
  hard-rom/build/super-otatrust-v0.portal6f-presentation-tail-cadence.sparse.img
    current live-flashed RVFC/presentation cadence and marker-visible T2P tail candidate; read-only PASS

current retained verifier/source partition images:
  no large portal raw system_b images are currently retained. They were removed
  after sparse build/offline verification to recover space. Rebuild them from
  their scripts/retained sparse sources when a fresh verifier/debug partition
  image is needed.

recently removed local large build outputs:
  v0.portal4c, v0.portal5b, v0.portal5c, and superseded portal sparse images
  through v0.portal5w were removed after newer retained sparse/report evidence
  replaced their local rollback value.
  The old product v0.35.2 verifier image and USB vendor v0.usb1/v0.usb2
  intermediate images were removed when free space dropped below the 20 GiB
  threshold during the strengthened v0.portal5e rebuild. Their scripts,
  verifiers, docs, and inspect reports remain.
  v0.portal5d/v0.portal5e/v0.portal5f/v0.portal5g sparse images plus
  v0.portal5d through v0.portal5h raw system_b verifier images were removed
  after v0.portal5i and v0.portal5j became the active retained Portal line and
  free space again dropped below the 20 GiB threshold.
  v0.portal5i, v0.portal5j, and v0.portal5j.1 raw system_b verifier images were
  removed after v0.portal5j.1 sparse/offline/preflight evidence was retained and
  free space dropped below the 20 GiB threshold.
  The v0.portal5j raw source extraction plus v0.portal5j.2 raw system_b image
  were removed after v0.portal5j.2 offline verification, and the superseded
  local v0.portal5j sparse image was removed when free space remained below the
  threshold. Scripts, manifests, docs, and inspect reports remain.
  The superseded local v0.portal5j.1 and v0.portal5j.2 sparse images, old
  v0.portal5k-through-v0.portal5p work dirs, and old v0.portal5k-through-v0.portal5o
  raw system_b images were removed before the v0.portal5r super build to restore
  local build headroom. Scripts, manifests, docs, and inspect reports remain.
  Superseded local v0.portal5h through v0.portal5w sparse images, unflashed
  v0.portal5r/v0.portal5s/v0.portal5t/v0.portal5v sparse images, old portal raw
  system_b images, `hard-rom/work/*`, and `hard-rom/extracted` were removed on
  2026-06-24 to restore free space. After the 5z offline PASS, regenerated 5z
  raw/work intermediates and the superseded local v0.portal5x sparse were also
  removed. v0.portal5x scripts, manifests, docs, and inspect reports remain.
  The v0.4 rollback sparse, previous live v0.portal5y/v0.portal5z/v0.portal6a
  sparse images, previous live v0.portal6b/v0.portal6c/v0.portal6d sparse
  images, previous live v0.portal6e/v0.portal6f sparse images, and current live
  v0.portal6g sparse remain local.
retired local verifier partition intermediates:
  hard-rom/build/super-otatrust-v0.42.2-textboom-ppocr-preview-save-before-ocr.sparse.img
  hard-rom/build/system-otatrust-v0.42.2-textboom-ppocr-preview-save-before-ocr.img
  hard-rom/build/system-otatrust-v0.42-textboom-ppocr-preview-path.img
  hard-rom/build/super-otatrust-v0.42.1-textboom-ppocr-preview-media-path.sparse.img
  hard-rom/build/system-otatrust-v0.42.1-textboom-ppocr-preview-media-path.img
  hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img
  hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  hard-rom/build/system-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump.img
  hard-rom/build/system-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.img
  hard-rom/build/system-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.img
  hard-rom/build/super-otatrust-v0.38-sidebar-font-ocr-disabled.sparse.img
  hard-rom/build/system-otatrust-v0.38-sidebar-font-ocr-disabled.img
  hard-rom/build/super-otatrust-v0.37b-textboom-live-system-libs-deodex.sparse.img
  hard-rom/build/system-otatrust-v0.37b-textboom-live-system-libs-deodex.img
  hard-rom/build/system-otatrust-v0.40-textboom-ppocr-noop-adapter.img
  hard-rom/build/system-otatrust-v0.39-sidebar-font-ocr-deleted.img
  hard-rom/build/system-otatrust-v0.41-textboom-ppocr-runtime-adapter.img
  hard-rom/build/super-otatrust-v0.43c-textboom-force-arm32-abi.sparse.img
  hard-rom/build/system-otatrust-v0.43c-textboom-force-arm32-abi.img
  hard-rom/work/v0.43c-textboom-force-arm32-abi/
  hard-rom/work/v0.43c-textboom-force-arm32-abi-apk/
  hard-rom/build/system-otatrust-v0.27-cloud-service-debloat.img
  hard-rom/build/system-otatrust-v0.28-wallet-handshaker-debloat.img
  hard-rom/build/system-otatrust-v0.29-sidebar-topbar-hide.img
  hard-rom/build/super-otatrust-v0.43d-textboom-codepath-arm32-abi.sparse.img
  hard-rom/build/system-otatrust-v0.43d-textboom-codepath-arm32-abi.img
  hard-rom/work/v0.43d-textboom-codepath-arm32-abi/
note:
  older unflashed and superseded sparse candidates were removed from the Mac
  working tree during local cleanup to restore disk space. Check
  docs/rom-archive.md before assuming a historical image path is present
  locally.
```

Current WebView M150 / BrowserChrome fix candidates:

```text
live variant:
  v0.35-webview-m150-system-provider
super sparse:
  removed locally after v0.35.2/v0.36.1 superseded it
sha256:
  e3e122faec2c01e1c710e9ad4661bbfd2c072573aa0e398eeb7afb5fa57c06ed
source baseline:
  v0.34-system-b-ext4-grow-fec live-proven B-slot capacity baseline
provider:
  /system/app/webview/webview.apk
  com.android.webview 150.0.7871.28 versionCode=787102801
product handling:
  /product/app/webview/webview.apk is absent from the product public scan path;
  the stock M75 APK is retained as a non-.apk held inode for rollback/evidence
status:
  flashed to B slot and live-verified at boot/package/WebViewUpdateService/
  relro/keyguard/launcher level. Stock BrowserChrome then reproduced a white
  loading page because its sandbox renderer aborts against
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex. Big Bang is normal,
  so the WebView provider path is not globally broken.
live fix variant:
  v0.35.1-webview-m150-browserchrome-deodex
super sparse:
  removed locally after v0.35.2/v0.36.1 superseded it
sha256:
  c86a1f734ebb243d279291023a2427c2c0d0cf183d99aec8e8bf6af8573e9559
fix:
  keep BrowserChrome.apk and WebView M150 unchanged, remove BrowserChrome
  prebuilt oat/vdex so ART falls back to APK dex for renderer processes
status:
  flashed to B slot and live-verified. BrowserChrome.apk remains stock,
  BrowserChrome oat/odex/vdex are absent, M150 WebView remains selected with
  relro 2/2 and dirty=false, and BrowserChrome renders example.com without
  BrowserChrome-only crash markers
current live cleanup variant:
  v0.35.2-webview-m150-clean-product-residue
super sparse:
  hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img
sha256:
  977f753dee7b84adc7218f5f0f4a8fd7b4403e8e39b24c77da013c8c6b7ec2f5
delta:
  keep v0.35.1 system_b, remove /product/app/webview entirely from product_b,
  rebuild product_b FEC
status:
  flashed to B slot and live-verified. /product/app/webview is absent,
  WebViewUpdateService selects com.android.webview 150.0.7871.28 with relro
  2/2 and dirty=false, BrowserChrome renders example.com, HtmlViewer renders
  a local WebView test page, Big Bang BOOM_TEXT segments text, and WPS loads
  the M150 WebView as a third-party host
current live Smartisax candidate:
  v0.36.1-smartisax-shell-debloat-arsc-align
super sparse:
  hard-rom/build/super-otatrust-v0.36.1-smartisax-shell-debloat-arsc-align.sparse.img
sha256:
  1dc67299b86a4dde63dc44d2620ce1fe6b6421790bdec082fb12c4c32cc83c03
delta:
  install com.smartisax.browser as a WebView-backed browser/Home candidate;
  remove the user-selected no-projection print-preserving debloat set plus
  SmartisanWallpapers; keep stock Launcher, stock BrowserChrome, M150 WebView,
  print, and TNT/projection; fix v0.36 target R+ PackageManager parse failure
  by storing and 4-byte aligning Smartisax resources.arsc
status:
  flashed to B slot and live-verified. Smartisax now registers from
  /system/app/SmartisaxShell/SmartisaxShell.apk, all selected hard-debloat
  packages are absent, M150 WebView remains current/clean, BrowserChrome and
  Launcher remain stock system packages, keyguard is hidden, and Launcher is
  focused. Smartisax functional UX testing passes: it is the default Home,
  renders its WebView shell with Chrome/150 UA plus WebGPU/WebGL2/localStorage
  availability, opens example.com through ACTION_VIEW, returns to its shell
  page on Back, and receives Home after leaving Settings.
```

Latest high-risk framework/product offline build candidate:

```text
variant:
  v0.10-framework-locale-prune
purpose:
  first true framework/product language-resource hard-prune ROM candidate;
  replaces framework-res.apk, framework-smartisanos-res.apk, and five
  product DisplayCutout static overlays with English/Chinese-only
  resources.arsc variants
super sparse:
  hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
sha256:
  62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
status:
  offline image checks passed, including post-fsck APK hash/ZIP verification
  and binary resources.arsc locale-policy verification on APKs dumped from the
  generated images plus sparse system_b/product_b logical-slice verification;
  RED early-boot framework resource candidate; requires explicit user
  confirmation before flash
shared-block note:
  system/product ext4 images use shared_blocks. v0.10 uses a hidden hard-link
  stock-inode hold before replacing files so debugfs never frees shared blocks.
```

Dark-mode additive app candidate:

```text
variant:
  v0.5-control
purpose:
  add the ROM-bundled SmartisaxControls priv-app for dark-mode/QS tile
  validation without patching SettingsSmartisan or SystemUI yet
super sparse:
  hard-rom/build/super-otatrust-v0.5-control-exact-current.sparse.img
sha256:
  6acf9ed5e9f14bc1ef6f2a2a87af9006176ad2cc4862b909fc2fb7b57f5a1fa8
status:
  offline image checks passed; requires explicit user confirmation before flash
```

Latest live-proven launcher-entry-hide candidate:

```text
variant:
  v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
purpose:
  keep Sidebar/One Step installed and functional while removing only its
  desktop launcher entry. This starts from live-verified v0.26b, preserves the
  four already live-proven launcher-entry-hide packages, copies the stock
  Sidebar v2 signing block as the certificate carrier, and bumps the Sidebar
  package directory mtime so PackageCacher reparses the launcher-hidden
  manifest.
base sparse:
  hard-rom/build/super-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=599578445026fbf8d35edffc014b71e7507eba9ce2921a82d0d298465e020ff1
super sparse:
  hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1
retired local system image:
  hard-rom/build/system-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.img
  sha256=c0aaf672f208cf11d8849d1459b5eef571a1710e21d8672e62c45725c012f945
patched APK:
  com.smartisanos.sidebar-launcher-hidden-v2cert.apk
    sha256=0c238bfb79a786ee28a325ca6983c5f4bc5d8877a19756a912968da9ecae93f2
package directory mtime bump:
  /system/priv-app/Sidebar
  mtime=0x6a33f9e0 (2026-06-18 22:00:00 +0800)
source audit:
  docs/research/sidebar-one-step-source-audit.md
offline verifier:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-194804.txt
  PASS; verifies v0.26b APKs are retained, Sidebar changes only
  AndroidManifest.xml, MAIN remains while LAUNCHER is removed from
  SettingActivity, non-manifest ZIP members remain byte-identical, native
  library offsets remain stable, APK Sig Block 42 is present, expected
  manifest digest boundaries are present, held-stock paths exist, package
  directory mtimes are correct, system_b sparse slice matches the generated
  system image, and system_ext_b is retained from v0.26b.
preflight:
  tools/r2-live-flash-preflight.sh v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
  PASS; required confirmation phrase:
  确认刷入 v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump B 槽
status:
  flashed to B slot after explicit confirmation and live-verified. The first
  post-boot verifier run was blocked by RUNNING_LOCKED/keyguard state, and a
  second run exposed a verifier-only SidebarService check that was too narrow.
  After the user unlocked the device and the verifier was corrected to check
  the live ServiceRecord, v0.26c passed the full read-only gate.
live flash:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/flash-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-20260618-200032.txt
boot wait:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/boot-wait-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-20260618-200633.txt
live verifier:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-device-20260618-200821.txt
  PASS; all five edited packages match expected /system hashes with shadow=no,
  user 0 is RUNNING_UNLOCKED, keyguard is not showing, all five launcher
  entries are absent, Sidebar shared UID is intact, SidebarService is live and
  system-bound, the four providers are present, explicit SettingActivity
  resolves, and sidebar_content_area/sidebar_top_area/sidebar_side_area windows
  are present.
```

Latest live-proven cloud-service hard-debloat result:

```text
variant:
  v0.27-cloud-service-debloat
purpose:
  hard-remove Smartisan cloud account/sync/share/find-phone ROM packages on top
  of the live-verified v0.26c launcher-entry-hide baseline.
base sparse:
  hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1
super sparse:
  hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img
  sha256=11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1
retired local system image:
  hard-rom/build/system-otatrust-v0.27-cloud-service-debloat.img
  sha256=e81e02caa9009b74138860f5c8c51ef66401ad863c119572d5cb97a574038bad
removed ROM paths:
  /system/priv-app/CloudServiceSmartisan
  /system/priv-app/CloudServiceShare
  /system/priv-app/CloudSyncAgent
offline verifier:
  hard-rom/inspect/v0.27-cloud-service-debloat/verify-v0.27-cloud-service-debloat-offline-image-20260618-202805.txt
  PASS; verifies the three ROM directories and hiddenapi whitelist entries are
  absent, system_b sparse slice matches, and system_ext_b is retained from
  v0.26c.
preflight:
  hard-rom/inspect/v0.27-cloud-service-debloat/preflight-v0.27-cloud-service-debloat-20260618-203558.txt
  PASS; required confirmation phrase:
  确认刷入 v0.27-cloud-service-debloat B 槽
live flash:
  hard-rom/inspect/v0.27-cloud-service-debloat/flash-v0.27-cloud-service-debloat-20260618-203648.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed sparse
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.27-cloud-service-debloat/boot-wait-v0.27-cloud-service-debloat-20260618-204255.txt
  PASS; boot_completed=1, slot=_b, bootanim=stopped, verified=orange.
approved data cleanup:
  hard-rom/inspect/v0.27-cloud-service-debloat/cloud-service-data-clean-20260618-204428.txt
  PASS-equivalent; PackageManager cleanup removed the updated-system
  com.smartisanos.cloudsync /data app for user 0. Smartisan's
  uninstall-system-updates shell path throws a NullPointerException when the
  system base is already gone, but pm uninstall --user 0 succeeded and the
  post-cleanup package/resolver surfaces were empty.
live verifier:
  hard-rom/inspect/v0.27-cloud-service-debloat/verify-v0.27-cloud-service-debloat-device-20260618-204534.txt
  PASS; boot_completed=1, slot=_b, root available, keyguard not showing,
  cloudsync/cloudsyncshare/cloudagent absent, cloud launcher/sync adapter/
  account authenticator/account-center provider surfaces absent, and core
  Settings, Contacts, providers, MMS, Phone, Launcher, and SystemUI present.
status:
  accepted as the current live-proven cloud-service hard-debloat state.
```

Current offline/preflight hard-debloat candidate:

```text
variant:
  v0.28-wallet-handshaker-debloat
purpose:
  hard-remove Smartisan Wallet and HandShaker ROM packages on top of the
  live-verified v0.27 cloud-service hard-debloat baseline.
source audit:
  docs/research/wallet-handshaker-debloat-audit.md
base sparse:
  hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img
  sha256=11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1
super sparse:
  hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img
  sha256=705c42c5b639ed9f08e8555749e6b7abaf9d281a2f7f2324e2ef29ceec561728
retired local system image:
  hard-rom/build/system-otatrust-v0.28-wallet-handshaker-debloat.img
  sha256=334f7e32491c2a43f524d3112807c19cf6f104a20fae2d2eb9f749aee9b73daf
removed ROM paths:
  /system/priv-app/WalletSmartisan
  /system/app/HandShaker
offline verifier:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/verify-v0.28-wallet-handshaker-debloat-offline-image-20260618-214643.txt
  PASS; verifies the removed directories and hiddenapi rows are absent,
  MtpService, MediaProvider, and MediaProviderLegacy paths are retained,
  system_b sparse slice matches, and system_ext_b/product_b are retained from
  v0.27.
preflight:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/preflight-v0.28-wallet-handshaker-debloat-20260618-214903.txt
  PASS; required confirmation phrase:
  确认刷入 v0.28-wallet-handshaker-debloat B 槽
status:
  flashed to B slot after explicit confirmation and live-verified at the
  read-only pre-clean gate; after separate explicit approval, the Wallet
  updated-system /data residue was cleaned and the final verifier passed.
live flash:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/flash-v0.28-wallet-handshaker-debloat-20260618-215337.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed sparse
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/boot-wait-v0.28-wallet-handshaker-debloat-20260618-215908.txt
  PASS; boot_completed=1, slot=_b, bootanim=stopped, verified=orange.
live pre-clean verifier:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/verify-v0.28-wallet-handshaker-debloat-device-pre-clean-20260618-215940.txt
  PASS; boot_completed=1, root available, keyguard not showing, launcher
  focused, sys.usb.state includes mtp and adb, MtpService/MediaProvider/
  MediaProviderLegacy are present, HandShaker is absent, and Wallet is present
  only as the expected /data/app updated-system residue.
approved data cleanup:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/wallet-data-clean-20260618-220153.txt
  PackageManager cleanup removed the updated-system com.smartisanos.wallet
  /data app for user 0. Smartisan's uninstall-system-updates shell path throws
  the same NullPointerException seen in v0.27 after the system base is gone,
  but pm uninstall --user 0 succeeded and post-cleanup Wallet paths/resolver
  surfaces were empty.
live final verifier:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/verify-v0.28-wallet-handshaker-debloat-device-20260618-220158.txt
  PASS; boot_completed=1, root available, keyguard not showing, sys.usb.state
  includes mtp and adb, MtpService/MediaProvider/MediaProviderLegacy are
  present, and both com.smartisanos.wallet and com.smartisanos.smartfolder.aoa
  are absent.
```

Previous live-proven launcher-entry-hide candidate:

```text
variant:
  v0.26b-sara-launcher-entry-hide-v2cert-cachebump
purpose:
  keep Sara/VoiceAssistant installed and functional while removing only the
  闪念胶囊 desktop launcher entry. This starts from live-verified v0.26a.2,
  keeps the three lower-risk launcher-entry-hide packages unchanged, copies
  the stock VoiceAssistant v2 signing block as the certificate carrier, and
  bumps the VoiceAssistant package directory mtime so PackageCacher reparses
  the launcher-hidden manifest.
base sparse:
  hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=a96006fcd6c53b82aa3638411e01a36ce0bb92b02737aa5351fdd8827578e792
super sparse:
  hard-rom/build/super-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=599578445026fbf8d35edffc014b71e7507eba9ce2921a82d0d298465e020ff1
retired local system image:
  hard-rom/build/system-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.img
  sha256=59dfbf3e5c15f95ee15b32624dd6fd03efd38a0f35325611c63b66da473e5fca
patched APK:
  com.smartisanos.sara-launcher-hidden-v2cert.apk
    sha256=f87e00479cdeb4dcfcd4215235349d8b18ac42096279f656bdeb8ce7a62a7637
package directory mtime bump:
  /system/priv-app/VoiceAssistant
  mtime=0x6a33ebd0 (2026-06-18 21:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-191608.txt
  PASS; verifies v0.26a.2 APKs are retained, Sara changes only
  AndroidManifest.xml, MAIN remains while LAUNCHER is removed,
  non-manifest ZIP members remain byte-identical, native library offsets
  remain stable, APK Sig Block 42 is present, expected manifest digest
  boundaries are present, held-stock paths exist, package directory mtimes are
  correct, system_b sparse slice matches the generated system image, and
  system_ext_b is retained from v0.26a.2.
preflight:
  tools/r2-live-flash-preflight.sh v0.26b-sara-launcher-entry-hide-v2cert-cachebump
  PASS; required confirmation phrase:
  确认刷入 v0.26b-sara-launcher-entry-hide-v2cert-cachebump B 槽
live flash:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/flash-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-20260618-192548.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/boot-wait-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-20260618-193145.txt
  PASS; boot=1, slot=_b, bootanim=stopped on attempt 4.
live verifier:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-device-20260618-193214.txt
  PASS; all four edited packages match expected /system hashes with shadow=no,
  user 0 is RUNNING_UNLOCKED, keyguard is not showing, launcher focus is
  smt_launcher, VideoPlayer, ScreenRecorderSmartisan, QuickSearch, and
  VoiceAssistant launcher entries are absent, and Sara provider/shortcut
  feature surfaces remain present.
status:
  accepted as the current live-proven launcher-entry-hide baseline. Sidebar/
  One Step remains a separate shared-UID RED gate.
```

Previous live-proven launcher-entry-hide baseline:

```text
variant:
  v0.26a.2-launcher-entry-hide-v2cert-cachebump
purpose:
  keep VideoPlayer, ScreenRecorderSmartisan, and QuickSearchBoxSmartisan
  installed and functional while removing only their desktop launcher entries.
  This keeps the v0.26a.1 v2 signing-block carrier fix and additionally bumps
  the three package directory mtimes so PackageCacher ignores stale pre-ROM
  ParsedPackage cache and reparses the launcher-hidden manifests.
base sparse:
  hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img
  sha256=2f1a4d8b8579551bf04246d00099f15c5c5a42146336cd6a00d129bbcffb8fa0
super sparse:
  hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=a96006fcd6c53b82aa3638411e01a36ce0bb92b02737aa5351fdd8827578e792
retired local system image:
  hard-rom/build/system-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump.img
  sha256=5282661df53643800601e816882b31113b96991340d701c1598feefa89285ae7
patched APKs:
  com.smartisanos.videoplayerproject-launcher-hidden-v2cert.apk
    sha256=482d05dbe82611e7dedd6eed0964e85cf6882ea22709981cec101311489d2734
  com.smartisanos.screenrecorder-launcher-hidden-v2cert.apk
    sha256=36782cff3384242e1560b3f9748ce86ef426ab9e904967c1b35011db989a4e4d
  com.smartisanos.quicksearch-launcher-hidden-v2cert.apk
    sha256=deb179992f9886dbf34ba44814a7456eb26515d9bf8bc8ab33b205519477c604
package directory mtime bump:
  /system/priv-app/VideoPlayer
  /system/priv-app/ScreenRecorderSmartisan
  /system/app/QuickSearchBoxSmartisan
  mtime=0x6a33ddc0 (2026-06-18 20:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.26a.2-launcher-entry-hide-v2cert-cachebump/verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-184855.txt
  PASS; verifies AndroidManifest.xml-only changes, MAIN remains while
  LAUNCHER is removed, non-manifest ZIP members remain byte-identical,
  native library offsets remain stable, APK Sig Block 42 is present,
  expected manifest digest boundaries are present, held-stock paths exist,
  the package directory mtimes are bumped, system_b sparse slice matches the
  generated system image, and system_ext_b is retained from v0.11.1.
preflight:
  tools/r2-live-flash-preflight.sh v0.26a.2-launcher-entry-hide-v2cert-cachebump
  PASS; required confirmation phrase:
  确认刷入 v0.26a.2-launcher-entry-hide-v2cert-cachebump B 槽
status:
  flashed to B slot and live-verified after user 0 was RUNNING_UNLOCKED;
  packages remain installed from /system with expected hashes and no /data/app
  shadows, and the three desktop launcher entries are absent. Sara/
  VoiceAssistant is now covered by the live-verified v0.26b baseline, and
  Sidebar/One Step is now covered by the live-verified v0.26c baseline.
v0.26a live failure:
  flashed to B slot and booted, but PackageManager logged Failed collecting
  certificates for the three edited APKs and removed the packages from the
  live package set. The launcher entries disappeared, but the feature-preserve
  requirement failed, so v0.26a is not accepted.
v0.26a.1 live partial failure:
  flashed to B slot and booted. PackageManager accepted the three v2cert APKs
  and device APK manifests truly lacked LAUNCHER, but after user unlock the
  launcher entries reappeared because PackageManager reused stale
  /data/system/package_cache ParsedPackage data. The root cause is
  PackageCacher validating directory packages by package directory mtime; the
  three ROM package directories still had 2009-01-01 mtimes while old cache
  files were newer.
```

Latest verified current-base SettingsSmartisan core-APK gate:

```text
variant:
  v0.25-settings-noop-on-v0.24
purpose:
  replace SettingsSmartisan.apk with an original-cert-readable no-op probe to
  test whether core shared-UID Settings APK patching is viable on the
  live-verified v0.24 line
super sparse:
  hard-rom/build/super-otatrust-v0.25-settings-noop-on-v0.24-exact-current.sparse.img
sha256:
  09fdd9c0ffe6184623938356ce2b837751079963c2d98990434eb708ecf69d88
system image:
  hard-rom/build/system-otatrust-v0.25-settings-noop-on-v0.24.img
sha256:
  ae6870e3d1109673fea6c8857d1c00bbf2866926d772e9bebb6218be1d4e4bbb
probe APK:
  hard-rom/build/apk/SettingsSmartisan-certprobe-noop.apk
sha256:
  19e6341addf021d42293ae41f65cc6bf01ec55601f94bdfe9b037f62a6b1c449
offline verifier:
  hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-152320.txt
live verifier:
  hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-20260618-155616.txt
status:
  shared_blocks-safe offline image checks passed on top of v0.24; flashed to
  B slot after explicit confirmation; live read-only verifier passed with
  boot_completed=1, slot=_b, root available, launcher focused, keyguard not
  showing, and SettingsSmartisan APK hash matching the no-op probe
legacy:
  v0.6-settings-noop is the older v0.4-based SettingsSmartisan no-op candidate.
  Keep it as historical evidence, but use v0.25 for the current dark-mode line.
```

Latest Settings behavior-patch candidates:

```text
variant:
  v0.7-locale-filter
purpose:
  patch SettingsSmartisan LocalePickerFragment.constructAdapter() so the
  visible language picker skips ja_JP and ko_KR
super sparse:
  hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img
sha256:
  d3dfef95d52dd1a26b399b2ef8a375c2645edfb08de46e4431e68cb5f823f9e4
patched APK:
  hard-rom/build/apk/SettingsSmartisan-locale-filter-ja-ko.apk
sha256:
  352794d2413d269799afac88dc3bead17cb587fefd2513378d99618461b10d9e
signature boundary:
  ordinary keytool/jarsigner verification fails with a classes.dex digest error;
  this variant is gated behind the v0.25 current-base no-op live boot probe
status:
  older v0.4-based image checks passed; rebuild on the v0.24 line only after
  v0.25 passes live
```

```text
variant:
  v0.8-darkmode-ui
purpose:
  patch SettingsSmartisan BrightnessSettingsFragment so the hidden DC dimming
  switch row becomes a native dark-mode switch backed by UiModeManager
super sparse:
  hard-rom/build/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img
sha256:
  44fed5e231d8a5525fbe748c25fe89ca3e50319054ade76e3ce6a4901259f435
patched APK:
  hard-rom/build/apk/SettingsSmartisan-darkmode-ui.apk
sha256:
  3b232687bfd3205e4dc6daf43be12dc09b61f3eda8644eaa9dad18d231d9f92d
signature boundary:
  ordinary keytool/jarsigner verification fails with a classes.dex digest error;
  this variant is gated behind the v0.25 current-base no-op live boot probe
status:
  older v0.4-based image checks passed; rebuild on the v0.24 line only after
  v0.25 passes live
```

Legacy first language resource-prune toolchain probe:

```text
variant:
  v0.9-protips-locale-prune
purpose:
  patch Protips.apk resources.arsc so compiled Japanese/Korean values resources
  are removed while English, Simplified Chinese, and Traditional Chinese remain
patched APK:
  hard-rom/build/apk/Protips-locale-prune-ja-ko.apk
sha256:
  12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d
signature boundary:
  ordinary keytool/jarsigner verification fails with a resources.arsc digest
  error; the stock APK has a v2 block, and the patched stock-shell output no
  longer carries that block
status:
  APK build and resource verification passed at the time. This early probe is
  superseded for future ROM promotion by the generic com.android.protips
  en/zh output below, which keeps resources.arsc STORED like stock APKs.
```

Latest generic APK locale-prune toolchain probe:

```text
tool:
  tools/r2-build-apk-locale-prune.sh
  tools/r2-build-apk-locale-prune-binary-arsc.sh
purpose:
  remove non-English/non-Chinese compiled values resources from a selected APK,
  while preserving the stock APK shell and changing only resources.arsc. Future
  rebuilds keep resources.arsc STORED like the stock system APKs instead of
  deflating it. If apktool/aapt2 cannot rebuild because of Smartisan private
  attrs or package-id quirks, the binary-arsc fallback edits only
  resources.arsc chunks and merges them into the stock APK shell.
verified outputs:
  hard-rom/build/apk/com.android.protips-locale-prune-en-zh.apk
    sha256=71ed25c64babd01e07cec4263aa1ea88ddb0a1bf74c1a03e3dc45c67ae5850d5
  hard-rom/build/apk/com.android.printservice.recommendation-locale-prune-en-zh.apk
    sha256=06628867eba1a7451a0afdb866eeb18b8d1bc36b6521a894331a4b2194b5c383
  hard-rom/build/apk/com.android.hotspot2.osulogin-locale-prune-en-zh.apk
    sha256=fa09b52598733e680abc21cd77dde6e953fdaf676f2fb835b99f5361c9476e6e
  hard-rom/build/apk/com.android.printspooler-locale-prune-en-zh.apk
    sha256=3f7ee66118b7e5acab0a8aad71e8efcc086535887250da4af0e723c1b11c9d38
  hard-rom/build/apk/com.android.wallpaper.livepicker-locale-prune-en-zh.apk
    sha256=acf2131fe283817b61e1f99ebaceddc2973caaaaddae0e86cd070d20dbb10130
  hard-rom/build/apk/com.android.htmlviewer-locale-prune-en-zh.apk
    sha256=fcfdd58b5fb92bfc05b6eba8cfc13759e3175d0e3db3cca7c129fec528282e35
  hard-rom/build/apk/com.android.dreams.basic-locale-prune-en-zh.apk
    sha256=2512094b9ac6ab042e97f37b74eb305b44e354a7fb341bcb5ceb4860dd7d0129
  hard-rom/build/apk/com.android.dreams.phototable-locale-prune-en-zh.apk
    sha256=c48ca2f6c3c95b1e0a7cbad3de2df3a7db5a78742a8cf77b3f847aa33f32a27f
  hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh.apk
    sha256=ee1bb729fe3bf2577ba898c91fbb088b0942a0ecf5c60183bf0fb6046d5914db
  hard-rom/build/apk/com.android.simappdialog-locale-prune-en-zh.apk
    sha256=3eb68792a4edecb94920915e7e50bd19a11da887a04c88eb7069293a4b905cad
  hard-rom/build/apk/com.android.companiondevicemanager-locale-prune-en-zh.apk
    sha256=07213606d5293d7fb363776afc8eab330c84ef31255cfb85fbd9e8d9b47ab2ad
  hard-rom/build/apk/com.smartisanos.share.browser-locale-prune-en-zh.apk
    sha256=d62475f2713e8454b8a9bf43fe7a3f0581aec1dd050baee0dc408c55dd8623e8
  hard-rom/build/apk/com.smartisanos.tracker-locale-prune-en-zh.apk
    sha256=9040314bd46e953e43827ab8d9102fe306a06c62516f0a19ec779ff078a1626c
  hard-rom/build/apk/com.smartisanos.cleaner-locale-prune-en-zh.apk
    sha256=d0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc
  hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh-samesize.apk
    sha256=e91d53b1cf1124896a3e8a0bfd577c8b1a9ef222435061bcfdafa93d3e3765c5
    note=same-size resources.arsc-stored candidate for system_ext in-place testing
verification:
  tools/r2-verify-tier1a-locale-prune-apks.sh verifies the three Tier1a
  minimal-exposure APK candidates; classes.dex and AndroidManifest.xml remain
  byte-identical to stock, resources.arsc changes, and binary locale-policy
  reports bad_locale_chunk_count=0. Ordinary keytool/jarsigner fail only at
  resources.arsc digest.
  tools/r2-verify-apk-only-locale-prune-candidates.sh verifies all APK-only
  candidates listed in the APK-only locale-prune manifest; latest batch verifies
  BasicDreams, PhotoTable, LiveWallpapersPicker, HTMLViewer, PrintSpooler,
  ConferenceDialer, SimAppDialog, CompanionDeviceManager, and
  SmartisanShareBrowser, TrackerSmartisan, and CleanerSmartisan.
report:
  hard-rom/inspect/tier1a-locale-prune-apks/verify-tier1a-locale-prune-apks-20260618-115520.txt
  hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-144236.txt
status:
  offline APK toolchain passed; no new super image generated and nothing flashed
```

Latest v0.17a system APK-only ROM promotion image:

```text
variant:
  v0.17a-system-apk-only-locale-prune
purpose:
  promote five already verified system APK-only English/Chinese resources.arsc
  prunes into system_b: BasicDreams, HTMLViewer, LiveWallpapersPicker,
  PrintSpooler, and SimAppDialog
build script:
  tools/r2-hardrom-build-v0.17a-system-apk-only-locale-prune.sh
verify script:
  tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh
super sparse:
  hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img
  sha256=2ebe837f314c35b02d5bab3bdd21d8661cf85b8cba8816e99d8d9744d2f5100a
retired local system image:
  hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img
  sha256=d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5
offline verification:
  tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh --offline-image passed
  report=hard-rom/inspect/v0.17a-system-apk-only-locale-prune/verify-v0.17a-offline-image-20260618-124311.txt
status:
  built and offline-verified; local v0.17a sparse and system_b image were
  removed during cleanup after v0.17-all was built. Rebuild if the partition
  image itself must be reverified, or use v0.17-all for a single combined test.
  Not flashed or live-verified.
```

Latest Tier1a ROM-level language hard-prune system image:

```text
variant:
  v0.13-tier1a-locale-prune
purpose:
  first low-exposure package batch moved from APK-level proof into a modified
  system_b image; replaces Protips, PrintRecommendationService, and OsuLogin
  with English/Chinese-only resources.arsc variants
build script:
  tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh
verify script:
  tools/r2-verify-v0.13-tier1a-locale-prune.sh
system image:
  hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img
sha256:
  e77643153a9e03fc48b5e47a0841c6322dc390eb3381ff40a24e98ae03f905bb
offline verification:
  tools/r2-verify-v0.13-tier1a-locale-prune.sh --offline-system-image passed
  report=hard-rom/inspect/v0.13-tier1a-locale-prune/verify-v0.13-offline-system-image-20260618-081444.txt
status:
  system_b image was generated and verified offline, then removed during local
  cleanup to save disk space; rebuild it before flashable promotion. Flashable
  sparse super is still not built; not flashed or live-verified
```

Latest framework-res language resource probe:

```text
tool:
  tools/r2-build-framework-res-locale-probe.sh
purpose:
  test whether framework-res.apk can be rebuilt with only English/Chinese
  locale resources and a narrowed supported_locales array
verified outputs:
  hard-rom/build/apk/framework-res-rebuild-noop.apk
    sha256=319cd91f8a29c88e8c1058a15bdcd2fbd159a82107add92daf87cbd40fd4240a
  hard-rom/build/apk/framework-res-locale-prune-en-zh.apk
    sha256=10fc36befd0acdb1a1530c6e676cc154170de1bebac5d7eb84b73c24f164aedd
verification:
  public.xml diff is empty for both outputs; AndroidManifest.xml remains
  byte-identical to stock; locale-prune removes 61 non-English/non-Chinese
  resource dirs, including raw-ja/raw-ko; narrows supported_locales to en-US,
  zh-Hans-CN, zh-Hant-TW; binary resources.arsc policy check reports only
  en/zh locale chunks
status:
  offline framework-res resource-table probe passed; no super image generated
  and nothing flashed
```

Latest Smartisan framework resource probe:

```text
tool:
  tools/r2-build-smartisanos-framework-res-locale-probe.sh
  tools/r2-arsc-prune-locales.py
purpose:
  remove Japanese/Korean locale configs from framework-smartisanos-res.apk
  without rebuilding through aapt2, preserving Smartisan's ^attr-private
  resource type identity
verified output:
  hard-rom/build/apk/framework-smartisanos-res-locale-prune-en-zh.apk
    sha256=eefab348089210bba963c69f5966052a65b11fdd1bf198084c60cc005a45b228
verification:
  binary resources.arsc prune removed 6 ja/ko config chunks; decoded output has
  no values-ja/values-ko dirs; values-zh-rCN and values-zh-rTW remain;
  public.xml diff is empty; AndroidManifest.xml remains byte-identical to stock
status:
  offline Smartisan framework resource-table probe passed; no super image
  generated and nothing flashed
```

Latest framework/product language hard-prune ROM candidate:

```text
variant:
  v0.10-framework-locale-prune
build script:
  tools/r2-hardrom-build-v0.10-framework-locale-prune.sh
verify script:
  tools/r2-verify-v0.10-framework-locale-prune.sh
super sparse:
  hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
sha256:
  62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
system image sha256:
  1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351
product image sha256:
  78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2
offline verification:
  tools/r2-verify-v0.10-framework-locale-prune.sh --offline-image passed
  report=hard-rom/inspect/v0.10-framework-locale-prune/verify-v0.10-offline-image-20260618-071729.txt
status:
  not flashed or live-verified; explicit confirmation required
```

Latest v0.17b product/system_ext APK-only ROM promotion image:

```text
variant:
  v0.17b-product-system_ext-apk-only-locale-prune
purpose:
  promote the remaining APK-only language-prune candidates into product_b and
  system_ext_b: PhotoTable and ConferenceDialer. PhotoTable uses the held-stock
  inode path; ConferenceDialer uses the same-size in-place system_ext path.
build script:
  tools/r2-hardrom-build-v0.17b-product-system_ext-apk-only-locale-prune.sh
verify script:
  tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh
super sparse:
  hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img
  sha256=f7e1c18b1023714731c714557ee5ed6763426882901026f3e914d79469c20e45
retired local product image:
  hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  sha256=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8
retired local system_ext image:
  hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  sha256=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb
offline verification:
  tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh --offline-image passed
  report=hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune/verify-v0.17b-offline-image-20260618-130101.txt
status:
  local v0.17b sparse plus product_b/system_ext_b images were removed during
  cleanup after v0.17-all was built. Rebuild if a separate
  product/system_ext-only flash test or partition reverify is needed, or use
  v0.17-all for a single combined test. Not flashed or live-verified.
```

Latest language hard-prune coverage audit:

```text
script:
  tools/r2-locale-prune-coverage-audit.py
outputs:
  reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv
  docs/research/locale-prune-coverage-audit.md
result:
  stock ja/ko resource packages: 175 packages, 509 dirs
  covered by v0.2/v0.4 deletion or v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 hard-prune candidates:
    40 packages, 141 dirs
  v0.7 visible-filter only, not resource-pruned:
    1 package, 6 dirs
  remaining APK-only built offline, not in ROM coverage:
    0 packages, 0 dirs
  remaining hard-prune work:
    134 packages, 362 dirs
next safe offline frontier:
  18 small GREEN/YELLOW APK resources.arsc prune candidates, before AMBER/RED
  package gates or live framework replacement gates
  completed v0.13 minimal-exposure system-image subset:
    com.android.protips
    com.android.printservice.recommendation
    com.android.hotspot2.osulogin
  completed v0.17a system-image subset:
    com.android.dreams.basic
    com.android.htmlviewer
    com.android.printspooler
    com.android.wallpaper.livepicker
    com.android.simappdialog
  completed v0.17b product/system_ext-image subset:
    com.android.dreams.phototable
    com.qualcomm.qti.confdialer
  completed v0.22 system-image subset:
    com.android.companiondevicemanager
    com.smartisanos.share.browser
    com.smartisanos.tracker
  completed v0.24 system-image subset:
    com.smartisanos.cleaner
```

Latest language source-coupling audit:

```text
script:
  tools/r2-language-source-coupling-audit.py
outputs:
  docs/research/language-source-coupling-audit.md
  reverse/smartisan-8.5.3-rom-static/manifest/language-source-coupling-audit.tsv
result:
  findings=26
  stock_visible_picker_coupled_to_assets=1
  settings_locale_resource_coupling=1
  stock_framework_picker_coupled_to_assets=1
  stock_system_asset_source_mapped=1
  stock_package_asset_source_mapped=1
  stock_resource_fallback_coupled_to_assets=1
  stock_framework_locale_arrays_broad=1
  stock_android_static_overlay_mapped=1
  stock_locale_resources_present=4
  stock_non_ui_locale_coupling=3
  candidate_proven_offline=6
  coverage_measured_incomplete=1
  full_coverage_measured_incomplete=1
  missing_live_gate=2
  missing_rom_image=1
meaning:
  visible Settings language filtering, framework AssetManager hard-pruning,
  app-level resource pruning, APK-only probes, full non-English/non-Chinese
  coverage, and live framework/package gates are separate work streams;
  telephony/SIM paths also read asset locales
```

Latest language next-batch plan:

```text
script:
  tools/r2-language-next-batch-plan.py
outputs:
  docs/research/language-next-batch-plan.md
  reverse/smartisan-8.5.3-rom-static/manifest/language-next-batch-plan.tsv
result:
  P0a_rebuild_v013_tier1a_stored=3 packages/6 dirs
  P1_build_small_apk_only=10 packages/20 dirs
  P2_build_green_full_language_apk_only=22 packages/1555 dirs
  P3_deferred_green_coupled=5 packages/161 dirs
  P4_amber_package_gate=56 packages/1840 dirs
  P5_red_core_gate=45 packages/1098 dirs
meaning:
  the next language route is staged: rebuild stale v0.13 inputs, live-test a
  combined sparse when authorized, then build small APK-only candidates a few at
  a time while keeping AMBER/RED rows behind their gates.
```

Latest language P1 source-review audit:

```text
script:
  tools/r2-language-p1-source-review-audit.py
outputs:
  docs/research/language-p1-source-review-audit.md
  reverse/smartisan-8.5.3-rom-static/manifest/language-p1-source-review-audit.tsv
result:
  P1c_defer_focused_package_review=10
  library_source_marker_candidate_count=7
  telephony_carrier_api_candidate_count=4
meaning:
  com.android.simappdialog, com.android.companiondevicemanager,
  com.smartisanos.share.browser, com.smartisanos.tracker, and
  com.smartisanos.cleaner have moved out of P1 after offline builds, image
  promotion, and batch verification. The remaining 10 P1
  rows need package-specific source/graph review before APK-only language-prune
  builds.
```

Latest framework-res replacement gate:

```text
variant:
  v0.12-framework-res-noop
purpose:
  replace only /system/framework/framework-res.apk with the no-op rebuilt
  resource-table APK, separating "framework-res replacement can boot" from
  "language-pruned framework resources can boot"
build script:
  tools/r2-hardrom-build-v0.12-framework-res-noop.sh
verify script:
  tools/r2-verify-v0.12-framework-res-noop.sh
expected APK:
  hard-rom/build/apk/framework-res-rebuild-noop.apk
  sha256=319cd91f8a29c88e8c1058a15bdcd2fbd159a82107add92daf87cbd40fd4240a
status:
  flashable sparse super built with direct sparse rewrite and offline-verified;
  not flashed or live-verified yet
super sparse:
  hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img
sha256:
  d5c63890f27f6609b09667cc0bee0dd4b55c5c335abeb530650c16fbce9d94d9
system image:
  hard-rom/build/system-otatrust-v0.12-framework-res-noop.img
sha256:
  26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0
local status:
  system image intermediate was removed during local cleanup; the flashable
  sparse super remains local and offline-verified
verification:
  tools/r2-verify-v0.12-framework-res-noop.sh --offline-image passed
  report=hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-offline-image-20260618-071439.txt
```

Latest native dark-mode integration ROM candidate:

```text
variant:
  v0.11.1-native-darkmode-settings-row
purpose:
  v0.11 follow-up that keeps the live-proven UiMode/SystemUI toggleDarkMode
  behavior and moves the SettingsSmartisan Display/Brightness dark-mode row
  exposure after the Darwin :cond_5 branch, so the row is reachable on R2
build script:
  tools/r2-hardrom-build-v0.11.1-native-darkmode-settings-row.sh
verify script:
  tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh
base sparse:
  hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img
  sha256=d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e
super sparse:
  hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img
  sha256=2f1a4d8b8579551bf04246d00099f15c5c5a42146336cd6a00d129bbcffb8fa0
system image:
  hard-rom/build/system-otatrust-v0.11.1-native-darkmode-settings-row.img
  sha256=971163161ed1658f9face9bd225492fb3f1f4ee9faa384d86a69fe38d73b954b
system_ext image:
  hard-rom/build/system_ext-otatrust-v0.11.1-native-darkmode-settings-row.img
  sha256=3f994cb1a7f2e82af007969ce7035e0ded83da90a0bef20f6142ac7e303c4f6a
patched APKs:
  hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
    sha256=d3fe00a4e0433ab43921f66d8cc4fcc649576f81bd05e5468a37e24e6b0b187c
  hard-rom/build/apk/SmartisanSystemUI-darkmode-tile-samesize.apk
    sha256=9e8604788326e035acd2f86a69693cf4ec5a3a415258af2f177b82262fdad0da
  hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
    sha256=4ac46df43c08737a36a366a6ac36349d6b69437b49e53b25f79b2f0ebe353012
verification:
  hard-rom/inspect/v0.11.1-native-darkmode-settings-row/verify-v0.11.1-native-darkmode-settings-row-offline-image-20260618-172253.txt
  PASS; checks APK semantics including brightness_darkmode_row_reachability=ok,
  same-size SystemUI member equivalence, expected dex signature-boundary
  failures, dumped SettingsSmartisan/SystemUI APK hashes, held-stock
  SettingsSmartisan path, and sparse system_b/system_ext_b slices.
preflight:
  tools/r2-live-flash-preflight.sh v0.11.1-native-darkmode-settings-row
  PASS; printed required confirmation phrase:
  confirm: 确认刷入 v0.11.1-native-darkmode-settings-row B 槽
live status:
  flashed to B slot after explicit confirmation; boot_completed=1, slot=_b,
  root available, keyguard not showing, SettingsSmartisan and SmartisanSystemUI
  APK hashes match expected v0.11.1 outputs
live verifier:
  hard-rom/inspect/v0.11.1-native-darkmode-settings-row/verify-v0.11.1-native-darkmode-settings-row-device-20260618-174034.txt
  PASS: v0.11.1 native dark-mode settings-row device read-only verification
live-state audit:
  hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-174034.txt
  PASS_READ_ONLY; Night mode: no, secure.ui_night_mode=1, original 20-slot
  expanded_widget_buttons state retained, and toggleDarkMode absent from
  restored main/additional QS data
UI visibility:
  hard-rom/inspect/v0.11.1-native-darkmode-settings-row/settings-row-ui-visibility-20260618-1740.txt
  PASS_UI_VISIBLE; the 屏幕和字体 page contains the reused switch_dc row with a
  real SwitchEx. The title currently resolves to "Dark", so a Chinese
  native-label follow-up remains.

previous live reference:
variant:
  v0.11-native-darkmode
purpose:
  add a native Smartisan toggleDarkMode QS key by patching SystemUI tile
  creation; patch the same SettingsSmartisan APK so the Display/Brightness page
  exposes a native dark-mode switch, the quick-widget editor renders that key,
  and NotificationCustomView injects it into the additional/default/reset
  candidate paths
build script:
  tools/r2-hardrom-build-v0.11-native-darkmode.sh
verify script:
  tools/r2-verify-v0.11-native-darkmode.sh
base sparse:
  hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img
  sha256=d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e
super sparse:
  hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img
  sha256=a0afc5b979db769137a01d581848b3d30f653197665f5ce0958b4b2809a05ebb
system image:
  hard-rom/build/system-otatrust-v0.11-native-darkmode.img
  sha256=fd78a14ba0dfde33d6c87021d7cd8aa3adebe892daba0c438c78b663670e3df9
system_ext image:
  hard-rom/build/system_ext-otatrust-v0.11-native-darkmode.img
  sha256=0d5990969cf74e5c0073e1819862688bf20a406d4d41dd8242175f4ac5575aae
patched APKs:
  hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
    sha256=c80904f85acf15ca706d4a40b1dad9f5c556ff69affa7fe270a9221889a7de26
  hard-rom/build/apk/SmartisanSystemUI-darkmode-tile-samesize.apk
    sha256=42996f1c39b5a7bf3775c7da59982b385ced43a74dcb431b1973e64ffd19fe1f
  hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
    sha256=8a4472dbfe90c16dc3cdf01eb2a41bdcb951b5c0da1b07d57dba19373812a7f0
verification:
  hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-offline-image-20260618-163441.txt
  PASS; checks APK semantics, same-size SystemUI member equivalence, expected
  dex signature-boundary failures, dumped SettingsSmartisan/SystemUI APK hashes,
  held-stock SettingsSmartisan path, and sparse system_b/system_ext_b slices.
preflight:
  tools/r2-live-flash-preflight.sh v0.11-native-darkmode
  PASS; printed required confirmation phrase:
  confirm: 确认刷入 v0.11-native-darkmode B 槽
source coupling audit:
  tools/r2-darkmode-source-coupling-audit.py
  docs/research/darkmode-source-coupling-audit.md
  result: stock framework backend and reusable Settings/SystemUI resources are
  present; stock Settings/SystemUI entries are missing; v0.11 is call-site
  proven offline; QS default visibility is a separate SettingsProvider or
  user-data seeding decision; the stock phone default QS page is already at the
  20-tile cap, and the stock SettingsSmt widget registry does not know
  toggleDarkMode; the current device UiMode/QS state has been captured; both
  current-base SettingsSmartisan and SystemUI no-op gates passed live; the
  combined v0.11 ROM image now has live boot/package/hash proof
QS strategy audit:
  tools/r2-darkmode-qs-strategy-audit.py
  docs/research/darkmode-qs-strategy-audit.md
  result: stock phone QS default list is full at 20 entries; toggleDarkMode is
  absent from QSTileHost, QuickWidgetFactory, SettingsSmt registry, and defaults;
  the SettingsSmartisan-local editor/additional route is now candidate-injection
  proven offline through NotificationCustomView; the stock SettingsSmt registry
  still lacks the key; the default-visible route must replace one existing key
  rather than append a 21st key; live state is still missing before displacement
  or migration
persistence audit:
  tools/r2-darkmode-persistence-audit.py
  docs/research/darkmode-persistence-audit.md
  result: stock SettingsProvider defaults and SettingsSmt registry omit
  toggleDarkMode; SettingsSmartisan stock reset/checkValidity paths can fall
  back to target-missing defaults; v0.11 local injection is offline-proven for
  additional/reset/save paths; restore is not target-aware; first behavior ROM
  should stay editor/additional-first and defer default-visible policy
integration map:
  docs/research/darkmode-integration-map.md
  result: defines the complete native route across SettingsSmartisan,
  UiModeManagerService, SmartisanSystemUI, QuickWidgetFactory,
  NotificationCustomView, SettingsProvider defaults, reset/restore behavior,
  and the live-state markers required before default seeding or data migration
status:
  flashed to B slot after exact confirmation; live read-only verifier passed
  with boot_completed=1, slot=_b, root available, keyguard not showing,
  launcher focused after Home, and SettingsSmartisan/SmartisanSystemUI APK
  hashes matching the v0.11 patched outputs. User-facing functional proof
  remains: Settings row behavior, UiMode state change, and Smartisan QS
  editor/toggleDarkMode behavior.
live verifier:
  hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-20260618-165423.txt
```

Latest current-base SystemUI no-op gate:

```text
variant:
  systemui-certprobe-noop-on-v0.24
purpose:
  verify a no-op original-cert-readable SmartisanSystemUI boundary on the
  live-verified v0.24 baseline before any live SystemUI behavior patch
ROM build script:
  SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24 \
  BASE_SPARSE=hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img \
  tools/r2-hardrom-build-systemui-certprobe-noop.sh
verify script:
  SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24 \
  tools/r2-verify-systemui-certprobe-noop.sh --offline-image
super sparse:
  hard-rom/build/super-otatrust-systemui-certprobe-noop-on-v0.24-exact-current.sparse.img
sha256:
  0749a4f19c34fa4bc89bcf1ed9a65fe027fce32479ae9b37be7a40e7a9895bfc
system_ext image:
  hard-rom/build/system_ext-otatrust-systemui-certprobe-noop-on-v0.24.img
sha256:
  133655b1b88440d942d473b1f14971acf657b379540fa12ca8fd5efe9c3d8f32
probe APK:
  hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk
sha256:
  654ff82819cf6a7bf42a3463cb9559196f871234800ad74ee0030963ce487d69
verification:
  hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-offline-20260618-154040.txt
live verification:
  hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-20260618-160919.txt
result:
  PASS; final sparse system_ext_b logical slice matches the system_ext image, and
  SmartisanSystemUI.apk inside that image matches the same-size no-op APK
mutation:
  one byte in the APK v2 signing block magic at offset 56852464:
  "APK Sig Block 42" -> "XPK Sig Block 42"; all 6137 ZIP/JAR entries remain
  byte-identical and keytool/jarsigner still read the Smartisan Android cert
status:
  offline image checks passed; flashed to B slot after explicit confirmation;
  live read-only verifier passed with boot_completed=1, slot=_b, root
  available, launcher focused, keyguard not showing, shared UID/systemui
  signatures present, and SmartisanSystemUI APK hash matching the no-op probe
legacy:
  systemui-certprobe-noop is the older v0.4-based SystemUI no-op candidate.
  Keep it as historical evidence, but use systemui-certprobe-noop-on-v0.24 for
  the current dark-mode line.
```
