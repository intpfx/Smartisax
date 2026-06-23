# WebView v0.35 System-provider Image Design

## Goal

Build the first donor-backed WebView modernization candidate on top of the
live-proven `v0.34-system-b-ext4-grow-fec` capacity baseline, without changing
BrowserChrome or framework `config_webview_packages`.

This image was flashed to B slot after explicit user confirmation on
2026-06-20 and passed the read-only live PackageManager/WebViewUpdateService
gate. It is still a high-risk first modern WebView provider replacement until
user-facing browser, WebView, Settings selector, and Smartisan Big Bang/WebView
regressions are checked.

## Route

The original Route A1 plan replaced `/product/app/webview/webview.apk` in
place. That layout remains blocked because the M150 stock-carrier APK is larger
than the product_b replacement budget.

The v0.35 design therefore keeps the same package identity,
`com.android.webview`, but relocates the provider to system_b:

```text
new provider:
  /system/app/webview/webview.apk

old product provider:
  /product/app/webview/webview.apk is absent from the public scan path

held stock inode:
  /product/app/webview/.webview.apk.smartisax-v035-stock-held
```

The stock product WebView is held under a non-`.apk` name so ext4 shared-block
references stay safe while PackageManager does not scan a duplicate
`com.android.webview` package from product_b.

## Candidate Input

```text
donor APK:
  apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView-stock-carrier.apk
sha256:
  2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95
identity:
  package=com.android.webview
  versionName=150.0.7871.28
  versionCode=787102801
donor audit:
  PASS
bundle audit:
  PASS_STANDALONE
```

## Capacity Evidence

```text
v0.34 system_b free bytes before candidate:
  350674944
M150 stock-carrier APK size:
  262686911
estimated margin before filesystem overhead:
  87988033
v0.35 system_b free blocks after install:
  21564
```

The design avoids deleting TNT/projection, print, wallpaper, or other
user-facing system packages for this first provider replacement.

## Filesystem Actions

```text
system_b:
  add /system/app/webview/webview.apk
  set package directory mtime to 0x6a363a70

product_b:
  link old /app/webview/webview.apk to
    /app/webview/.webview.apk.smartisax-v035-stock-held
  unlink public /app/webview/webview.apk
  set /app/webview mtime to 0x6a363a70

AVB:
  rebuild system_b hashtree footer with Android FEC roots=2
  rebuild product_b hashtree footer with Android FEC roots=2
```

`0x6a363a70` corresponds to 2026-06-20 15:00:00 +0800 and is used to make
Android 11 PackageCacher reparse both the new system provider directory and the
old product WebView directory.

## Outputs

```text
super sparse:
  hard-rom/build/super-otatrust-v0.35-webview-m150-system-provider.sparse.img
  sha256=e3e122faec2c01e1c710e9ad4661bbfd2c072573aa0e398eeb7afb5fa57c06ed

system_b image:
  hard-rom/build/system-otatrust-v0.35-webview-m150-system-provider.img
  sha256=37a1d97782b0edbe31d0f4fc572ef22ac6a74c7548bc693c0eae853900279560

product_b image:
  hard-rom/build/product-otatrust-v0.35-webview-m150-system-provider.img
  sha256=1122ee932f1aca8305cdc258fa3e6ab1638fcc9640de7b29dfb4e7f04e212e83
```

## Verification

Offline verifier:

```text
tools/r2-verify-v0.35-webview-m150-system-provider.sh --offline-image
result=PASS_OFFLINE_IMAGE_V035_WEBVIEW_SYSTEM_PROVIDER
report:
  hard-rom/inspect/v0.35-webview-m150-system-provider/verify-v0.35-webview-m150-system-provider-offline-image-20260620-125012.txt
```

Verified points:

```text
system_b_avb_fec=ok
product_b_avb_fec=ok
/system/app/webview mtime ok
/app/webview mtime ok
aapt identity ok: com.android.webview 150.0.7871.28 / 787102801
product public WebView absent
product held stock WebView ok
dumped provider donor audit PASS
dumped provider bundle audit PASS_STANDALONE
```

Live preflight:

```text
tools/r2-live-flash-preflight.sh v0.35-webview-m150-system-provider
result=PASS
required confirmation phrase:
  确认刷入 v0.35-webview-m150-system-provider B 槽
```

## Live Verification

Flash:

```text
confirmation:
  确认刷入 v0.35-webview-m150-system-provider B 槽
log:
  hard-rom/inspect/v0.35-webview-m150-system-provider/flash-v0.35-webview-m150-system-provider-20260620-130108.txt
result:
  sparse super 1/9 through 9/9 OK
  erase misc OK
  reboot OK
```

Boot wait:

```text
log:
  hard-rom/inspect/v0.35-webview-m150-system-provider/boot-wait-v0.35-webview-m150-system-provider-20260620-130541.txt
result:
  BOOT_COMPLETED on attempt 3
  slot=_b
  bootanim=stopped
  verified=orange
```

Read-only verifier:

```text
tools/r2-verify-v0.35-webview-m150-system-provider.sh --read-only
result=PASS_READ_ONLY_V035_WEBVIEW_SYSTEM_PROVIDER
report:
  hard-rom/inspect/v0.35-webview-m150-system-provider/verify-v0.35-webview-m150-system-provider-device-read-only-20260620-130601.txt
```

Live-state capture:

```text
tools/r2-browser-webview-live-state-audit.sh
result=PASS_READ_ONLY
report:
  hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260620-130615.txt
```

Verified live points:

```text
PackageManager path:
  package:/system/app/webview/webview.apk
provider hash:
  2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95
BrowserChrome hash:
  0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c
WebViewUpdateService:
  Current WebView package (name, version): (com.android.webview, 150.0.7871.28)
  Number of relros started: 2
  Number of relros finished: 2
  WebView package dirty: false
UI:
  keyguard=false
  launcher focused
```

## Remaining Regression Gates

Read-only acceptance has proved the core provider integration. Remaining
functional checks:

```text
open several modern WebView pages through an app that embeds WebView
open Settings WebView implementation selector
exercise BrowserChrome on modern pages
WebView-based apps and Settings selector do not regress
Big Bang/WebView-dependent Smartisan features still behave acceptably
```

## BrowserChrome Regression

The first user-facing BrowserChrome regression check failed on v0.35 after the
read-only provider gate had passed.

Observed behavior:

```text
Stock BrowserChrome opens, the address bar shows a loading spinner, and the page
content remains white. Smartisan Big Bang still works normally.
```

Reproduction capture:

```text
command:
  adb shell am start -W -a android.intent.action.VIEW -d https://www.example.com -p com.android.browser
report:
  hard-rom/inspect/browser-webview-v035-regression/browserchrome-repro-20260620-131404.txt
screenshot:
  hard-rom/inspect/browser-webview-v035-regression/browserchrome-repro-20260620-131404.png
```

Key crash evidence:

```text
mCurrentFocus=Window{... com.android.browser/com.android.browser.BrowserActivity}
Start proc ... com.android.browser:sandboxed_process1:org.chromium.content.app.SmartisanSandboxedProcessService1:4
Check failed: status <= ClassStatus::kLast ... at /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex
Abort message: 'Check failed: status <= ClassStatus::kLast ... at /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex'
Process com.android.browser:sandboxed_process1:org.chromium.content.app.SmartisanSandboxedProcessService1:4 has died
```

Interpretation:

```text
The M150 WebView provider is accepted by WebViewUpdateService and Big Bang still
works, so the provider path is not globally dead. The stock browser's renderer
process is crashing while loading BrowserChrome's own prebuilt system odex. The
next smallest candidate is therefore BrowserChrome deodex, not another WebView
provider swap.
```

The Settings WebView selector exists as:

```text
action:
  android.settings.WEBVIEW_SETTINGS
component:
  com.android.settings/.WebViewImplementation
direct command:
  adb -s bb12d264 shell am start -a android.settings.WEBVIEW_SETTINGS
```

## v0.35.1 Follow-up Candidate

v0.35.1 is a follow-up candidate built from v0.35 and live-verified on B slot:

```text
variant:
  v0.35.1-webview-m150-browserchrome-deodex
builder:
  tools/r2-hardrom-build-v0.35.1-webview-m150-browserchrome-deodex.sh
super sparse:
  hard-rom/build/super-otatrust-v0.35.1-webview-m150-browserchrome-deodex.sparse.img
sha256:
  c86a1f734ebb243d279291023a2427c2c0d0cf183d99aec8e8bf6af8573e9559
build report:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/build-v0.35.1-webview-m150-browserchrome-deodex-20260620-131904.txt
manual offline verifier:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/verify-v0.35.1-webview-m150-browserchrome-deodex-offline-manual-20260620-132329.txt
preflight:
  tools/r2-live-flash-preflight.sh v0.35.1-webview-m150-browserchrome-deodex
  PASS
flash:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/flash-v0.35.1-webview-m150-browserchrome-deodex-20260620-133057.txt
  PASS; sparse super 1/9 through 9/9 OK, erase misc OK, reboot OK
boot:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/boot-wait-v0.35.1-webview-m150-browserchrome-deodex-20260620-133526.txt
  BOOT_COMPLETED on attempt 7, slot=_b, bootanim=stopped, verified=orange
live verifier:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/verify-v0.35.1-webview-m150-browserchrome-deodex-device-oat-read-only-20260620-133607.txt
  PASS_READ_ONLY_V0351_OAT_ABSENT
```

Filesystem delta:

```text
kept:
  /system/app/BrowserChrome/BrowserChrome.apk
  /system/app/webview/webview.apk
  product_b from v0.35
removed:
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.vdex
  empty BrowserChrome oat directories
bumped:
  /system/app/BrowserChrome mtime=0x6a363d18
```

Offline proof:

```text
BrowserChrome.apk sha256:
  0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c
BrowserChrome oat:
  /system/app/BrowserChrome/oat: File not found
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex: File not found
WebView M150 sha256:
  2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95
product held WebView sha256:
  11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97
AVB/FEC:
  system_b FEC num roots=2
  product_b FEC num roots=2
```

Live regression result:

```text
repro:
  adb shell am start -W -a android.intent.action.VIEW -d https://www.example.com -p com.android.browser
report:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/browserchrome-repro-v0.35.1-webview-m150-browserchrome-deodex-20260620-133640.txt
screenshot:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/browserchrome-repro-v0.35.1-webview-m150-browserchrome-deodex-20260620-133640.png
browser-only crash check:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/browserchrome-repro-v0.35.1-webview-m150-browserchrome-deodex-browser-only-crash-check-20260620-133757.txt
result:
  BrowserChrome renders Example Domain
  browser_only_crash_marker_count=0
  PASS_BROWSERCHROME_RENDERED_NO_BROWSER_CRASH
```

## v0.35.2 Product-residue Cleanup Candidate

v0.35.2 is built from live-proven v0.35.1, offline/preflight verified, flashed
to B slot, and live-verified:

```text
variant:
  v0.35.2-webview-m150-clean-product-residue
builder:
  tools/r2-hardrom-build-v0.35.2-webview-m150-clean-product-residue.sh
verifier:
  tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh
super sparse:
  hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img
sha256:
  977f753dee7b84adc7218f5f0f4a8fd7b4403e8e39b24c77da013c8c6b7ec2f5
product_b image:
  hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img
sha256:
  21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57
build report:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/build-v0.35.2-webview-m150-clean-product-residue-20260620-135245.txt
offline verifier:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/verify-v0.35.2-webview-m150-clean-product-residue-offline-image-20260620-135658.txt
preflight:
  tools/r2-live-flash-preflight.sh v0.35.2-webview-m150-clean-product-residue
  PASS
flash:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/flash-v0.35.2-webview-m150-clean-product-residue-20260620-140256.txt
boot wait:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/boot-wait-v0.35.2-webview-m150-clean-product-residue-20260620-140724.txt
device verifier:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/verify-v0.35.2-webview-m150-clean-product-residue-device-read-only-20260620-140800.txt
```

Filesystem delta:

```text
retained:
  v0.35.1 system_b
  /system/app/webview/webview.apk
  /system/app/BrowserChrome/BrowserChrome.apk
  BrowserChrome oat absence from v0.35.1
removed from product_b:
  /app/webview
  /app/webview/.webview.apk.smartisax-v035-stock-held
  /app/webview/oat
result:
  product_webview_dir=absent
  product_b_sparse_slice=ok
  product_b FEC num roots=2
  product free blocks 7 -> 34512 before AVB footer rebuild
```

Live B-slot result:

```text
boot:
  sys.boot_completed=1
  slot=_b
  bootanim=stopped
  verifiedbootstate=orange
root:
  uid=0(root)
  SELinux Enforcing
package paths:
  package:/system/app/webview/webview.apk
  product_webview_dir=absent
  browserchrome_oat=absent
WebViewUpdateService:
  Current WebView package (name, version): (com.android.webview, 150.0.7871.28)
  Number of relros started: 2
  Number of relros finished: 2
  WebView package dirty: false
window:
  Launcher focused
  isKeyguardShowing=false
result:
  PASS_READ_ONLY_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN
```

Functional checks:

```text
browser repro:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/browserchrome-repro-v0.35.2-webview-m150-clean-product-residue-20260620-140817.txt
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/browserchrome-repro-v0.35.2-webview-m150-clean-product-residue-20260620-140817.png
  Stock BrowserChrome renders https://www.example.com.
system WebView host:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/htmlviewer-webview-test-mediastore-v0.35.2-webview-m150-clean-product-residue-20260620-140945.txt
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/htmlviewer-webview-test-mediastore-v0.35.2-webview-m150-clean-product-residue-20260620-140945.png
  HtmlViewer loads com.android.webview 150.0.7871.28 and renders the local test page.
Big Bang:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/bigbang-boomtext-test-v0.35.2-webview-m150-clean-product-residue-20260620-141025.txt
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/bigbang-boomtext-test-v0.35.2-webview-m150-clean-product-residue-20260620-141025.png
  BOOM_TEXT starts com.smartisanos.textboom/.BoomActivity and segments text.
third-party host:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/thirdparty-wps-html-test-v0.35.2-webview-m150-clean-product-residue-20260620-141053.txt
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/thirdparty-wps-html-test-v0.35.2-webview-m150-clean-product-residue-20260620-141053.png
  WPS writer process loads com.android.webview 150.0.7871.28 and starts a WebView sandboxed process.
```
