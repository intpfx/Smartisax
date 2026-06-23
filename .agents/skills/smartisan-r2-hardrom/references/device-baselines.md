# Device State And Baselines

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Current Device Facts

```text
serial: bb12d264
device: Smartisan R2, aries/darwin, Snapdragon 865/kona
OS: Smartisan OS 8.5.3, Android 11
active working slot: B
bootloader: unlocked
root: APatch/kp available on successful hard-ROM builds
fastboot boot: unsupported, returns unknown command
fastbootd: fastboot reboot fastboot enters stock recovery, not userspace fastboot
stock recovery: no adb sideload, only retry/factory reset style UI
```

Always verify live state instead of assuming:

```bash
adb -s bb12d264 shell 'getprop ro.boot.slot_suffix; getprop sys.boot_completed'
tools/r2-root.sh status
fastboot -s bb12d264 getvar current-slot
fastboot -s bb12d264 getvar is-userspace
```

## Stable Baselines

Fast local rollback:

```text
v0.4 hard debloat
hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
sha256: 313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5
result: boot_completed=1, slot=_b, root available, launcher focused
```

Current local large-image retention after the latest cleanup:

```text
keep as direct flash/rollback targets:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img
    current live-proven WebView cleanup image; removes old product WebView
    backup/oat residue on top of v0.35.1
  hard-rom/build/super-otatrust-v0.36.1-smartisax-shell-debloat-arsc-align.sparse.img
    current live-verified Smartisax browser/Home system-shell follow-up; fixes
    v0.36 target R+ resources.arsc alignment failure
  hard-rom/build/super-otatrust-v0.37a-textboom-live-system-base.sparse.img
    flashed and pre-clean live-verified TextBoom v3.2.2 live APK system-base
    promotion; the first PackageManager cleanup attempt failed, so active
    TextBoom still resolves from the /data/app updated-system shadow
  hard-rom/build/super-otatrust-v0.37b-textboom-live-system-libs-deodex.sparse.img
    built, offline-verified, live-preflighted, flashed, read-only verified, and
    post-shadow-repair verified follow-up that keeps the TextBoom v3.2.2
    system APK byte-identical, adds the 13 system-side armeabi-v7a native
    libraries under /system/app/TextBoom/lib/arm, removes stale TextBoom
    oat/vdex, and has Big Bang BOOM_TEXT functional proof from the system
    package
  hard-rom/build/super-otatrust-v0.38-sidebar-font-ocr-disabled.sparse.img
    previous live-verified Sidebar font OCR stage-1 behavioral stop; retained
    Sidebar/One Step panel, Big Bang/TextBoom, M150 WebView, BrowserChrome,
    and Smartisax
  hard-rom/build/super-otatrust-v0.39-sidebar-font-ocr-deleted.sparse.img
    current live-verified B-slot target; deletes Sidebar/One Step font OCR
    classes and Sidebar-local Intsig/CamScanner SDK copy while retaining the
    Sidebar panel, Big Bang/TextBoom, M150 WebView, BrowserChrome, and
    Smartisax

retired local verifier partition intermediates:
  hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img
  hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  hard-rom/build/system-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump.img
  hard-rom/build/system-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.img
  hard-rom/build/system-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.img
  hard-rom/build/system-otatrust-v0.27-cloud-service-debloat.img
  hard-rom/build/system-otatrust-v0.28-wallet-handshaker-debloat.img
  hard-rom/build/system-otatrust-v0.29-sidebar-topbar-hide.img

removed from Mac-local direct flash targets:
  v0.5, v0.6, v0.7, v0.8, v0.10, v0.12, SystemUI certprobe no-op,
  v0.17a sparse, v0.17b sparse, v0.17-all, v0.22, v0.24, v0.25,
  SystemUI certprobe no-op on v0.24, v0.11, v0.11.1, v0.26a.2,
  v0.26b, v0.26c, v0.27, v0.28, v0.34 sparse, v0.35 sparse,
  v0.35.1 sparse, and the v0.17a/v0.17b partition intermediates listed above.
Check docs/rom-archive.md before assuming a historical sparse path exists.
```

Storage cleanup policy:

```text
Do not make disk cleanup a routine step. Continue the ROM/reverse-engineering
goal unless free space drops below 20 GiB or the user explicitly asks for
cleanup. When cleanup is needed, keep the latest stable rollback sparse and the
current next-test sparse local unless the user chooses archive/migration.
```

Offline candidates, not flashed or live-verified:

```text
v0.5-control
hard-rom/build/super-otatrust-v0.5-control-exact-current.sparse.img
sha256: 6acf9ed5e9f14bc1ef6f2a2a87af9006176ad2cc4862b909fc2fb7b57f5a1fa8
purpose: add SmartisaxControls privileged dark-mode/QS validation app.

v0.6-settings-noop
hard-rom/build/super-otatrust-v0.6-settings-noop-exact-current.sparse.img
sha256: a06c2e81862c837bef53a4dc2f67c5dea7f0acf78dc7fbbecb6ae4ece26483db
purpose: replace SettingsSmartisan.apk with an original-cert-readable no-op
         probe before real Settings/locale patches. Rebuilt with the
         shared_blocks-safe held-stock-inode replacement path. Historical
         v0.4-based gate; use v0.25 for the current v0.24 dark-mode line.

v0.25-settings-noop-on-v0.24
hard-rom/build/super-otatrust-v0.25-settings-noop-on-v0.24-exact-current.sparse.img
sha256: 09fdd9c0ffe6184623938356ce2b837751079963c2d98990434eb708ecf69d88
purpose: current v0.24-baseline SettingsSmartisan original-cert-readable no-op
         gate before real Settings/dark-mode behavior patches. It starts from
         the live-verified v0.24 APK-only language-prune ROM and replaces only
         SettingsSmartisan.apk with the certprobe no-op APK.
offline verifier:
         hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-152320.txt
         PASS; verifies SettingsSmartisan APK hash, ZIP integrity, and sparse
         system_b slice equality.
live verifier:
         hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-20260618-155616.txt
         PASS; v0.25 was flashed to B slot after explicit confirmation,
         boot_completed=1, slot=_b, root available, launcher focused, keyguard
         not showing, shared UID/system signatures present, and the pulled
         SettingsSmartisan APK hash matched the no-op probe.

systemui-certprobe-noop-on-v0.24
hard-rom/build/super-otatrust-systemui-certprobe-noop-on-v0.24-exact-current.sparse.img
sha256: 0749a4f19c34fa4bc89bcf1ed9a65fe027fce32479ae9b37be7a40e7a9895bfc
purpose: current v0.24-baseline SmartisanSystemUI original-cert-readable no-op
         gate before native toggleDarkMode SystemUI patches. It starts from
         the live-verified v0.24 APK-only language-prune ROM and applies the
         same one-byte in-place SmartisanSystemUI certprobe patch to system_ext_b.
offline verifier:
         hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-offline-20260618-154040.txt
         PASS; verifies the APK gate, ZIP/signature boundary, SmartisanSystemUI
         APK hash inside the system_ext image, and sparse system_ext_b slice
         equality.
live verifier:
         hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-20260618-160919.txt
         PASS; systemui-certprobe-noop-on-v0.24 was flashed to B slot after
         explicit confirmation, boot_completed=1, slot=_b, root available,
         launcher focused, keyguard not showing, shared UID/systemui
         signatures present, and the pulled SmartisanSystemUI APK hash matched
         the no-op probe.

v0.7-locale-filter
hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img
sha256: d3dfef95d52dd1a26b399b2ef8a375c2645edfb08de46e4431e68cb5f823f9e4
purpose: first real SettingsSmartisan behavior patch candidate; filters ja_JP
         and ko_KR from the visible language picker. Historical v0.4-based
         image; keep behind the dark-mode priority unless explicitly selected.
         Rebuild on the v0.24 line only after v0.25 passes live validation.
apk semantics verifier:
         hard-rom/inspect/v0.7-locale-filter/verify-settingssmartisan-locale-filter-apk-20260618-073901.txt
         PASS; decodes the APK to temporary smali and verifies
         LocalePickerFragment.constructAdapter() keeps AssetManager.getLocales()
         but skips ja_JP and ko_KR before the length==5 locale processing.

v0.8-darkmode-ui
hard-rom/build/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img
sha256: 44fed5e231d8a5525fbe748c25fe89ca3e50319054ade76e3ce6a4901259f435
purpose: first native SettingsSmartisan dark-mode UI candidate; reuses the
         hidden switch_dc row in BrightnessSettingsFragment and routes changes
         through UiModeManager.setNightModeActivated(boolean). Historical
         v0.4-based image; rebuild on the v0.24 line only after
         v0.25-settings-noop-on-v0.24 passes live validation.
         Rebuilt with the shared_blocks-safe held-stock-inode replacement path.

v0.9-protips-locale-prune
hard-rom/build/apk/Protips-locale-prune-ja-ko.apk
sha256: 12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d
purpose: legacy first APK-level resources.arsc hard-prune probe; removes Protips
         values-ja and values-ko while preserving values, values-zh-rCN, and
         values-zh-rTW. Superseded for future ROM promotion by the generic
         com.android.protips en/zh output that keeps resources.arsc STORED.

v0.10-framework-locale-prune
hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
sha256: 62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
purpose: first combined framework/product language-resource hard-prune ROM
         candidate; replaces framework-res.apk, framework-smartisanos-res.apk,
         and five product DisplayCutout static android overlays with
         English/Chinese-only resources.arsc variants. Offline image
         verification now includes binary resources.arsc locale-policy checks
         on APKs dumped from generated images plus sparse system_b/product_b
         logical-slice checks. RED early-boot candidate; not flashed or
         live-verified.

v0.12-framework-res-noop
tools/r2-hardrom-build-v0.12-framework-res-noop.sh
tools/r2-verify-v0.12-framework-res-noop.sh
purpose: smaller framework-res replacement gate before v0.10. Replaces only
         /system/framework/framework-res.apk with framework-res-rebuild-noop.apk
         to separate resource-table replacement boot risk from language-prune
         behavior. The flashable sparse super is built by direct sparse rewrite
         and offline-verified; not flashed or live-verified.
super sparse:
         hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img
         sha256=d5c63890f27f6609b09667cc0bee0dd4b55c5c335abeb530650c16fbce9d94d9
system image:
         hard-rom/build/system-otatrust-v0.12-framework-res-noop.img
         sha256=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0
offline verifier:
         hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-offline-image-20260618-071439.txt
         PASS

v0.13-tier1a-locale-prune
tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh
tools/r2-verify-v0.13-tier1a-locale-prune.sh
purpose: low-exposure ROM-level language hard-prune batch. Replaces
         /system/app/Protips/Protips.apk,
         /system/app/PrintRecommendationService/PrintRecommendationService.apk,
         and /system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk with
         verified English/Chinese-only resources.arsc variants using the
         shared_blocks-safe held-stock-inode replacement path.
system image:
         hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img
         sha256=e77643153a9e03fc48b5e47a0841c6322dc390eb3381ff40a24e98ae03f905bb
offline verifier:
         hard-rom/inspect/v0.13-tier1a-locale-prune/verify-v0.13-offline-system-image-20260618-081444.txt
         PASS
status: previous system_b image built and verified offline. Tier1a APK inputs
        were later rebuilt with STORED resources.arsc, so rebuild the system_b
        image before any flashable promotion. The local system image
        intermediate was removed during cleanup to save disk space. Not flashed
        or live-verified.

v0.14a-livewallpaperpicker-locale-prune-apk
hard-rom/build/apk/com.android.wallpaper.livepicker-locale-prune-en-zh.apk
sha256: acf2131fe283817b61e1f99ebaceddc2973caaaaddae0e86cd070d20dbb10130
purpose: APK-only low-exposure language resource-prune probe for
         com.android.wallpaper.livepicker. Removes values-ja and values-ko
         from LiveWallpapersPicker while preserving AndroidManifest.xml and
         classes.dex byte-identical to stock. Standalone APK evidence is now
         promoted into the v0.17a system_b image; not flashed or live-verified.
offline verifier:
         hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-115520.txt
         PASS_OFFLINE_APK_ONLY_BATCH; resources.arsc is STORED, ZIP integrity
         OK, binary arsc policy reports bad_locale_chunk_count=0, and the
         expected signature boundary is a resources.arsc digest error.

v0.14b-htmlviewer-locale-prune-apk
hard-rom/build/apk/com.android.htmlviewer-locale-prune-en-zh.apk
sha256: fcfdd58b5fb92bfc05b6eba8cfc13759e3175d0e3db3cca7c129fec528282e35
purpose: APK-only language resource-prune probe for com.android.htmlviewer
         after ORANGE replace preflight. Removes values-ja and values-ko while
         preserving AndroidManifest.xml and classes.dex byte-identical to
         stock. Standalone APK evidence is now promoted into the v0.17a
         system_b image; not flashed or live-verified.
offline verifier:
         hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-124601.txt
         PASS_OFFLINE_APK_ONLY_BATCH; verifies all seven manifest-listed
         APK-only candidates as a batch.

v0.14c-printspooler-locale-prune-apk
hard-rom/build/apk/com.android.printspooler-locale-prune-en-zh.apk
sha256: 3f7ee66118b7e5acab0a8aad71e8efcc086535887250da4af0e723c1b11c9d38
purpose: strict rebuilt APK-only language resource-prune probe for
         com.android.printspooler. Removes all non-English/non-Chinese locale
         chunks, including Serbian resources that the older output missed.
         Standalone APK evidence is now promoted into the v0.17a system_b
         image; not flashed or live-verified.

v0.15a-basicdreams-locale-prune-apk
hard-rom/build/apk/com.android.dreams.basic-locale-prune-en-zh.apk
sha256: 2512094b9ac6ab042e97f37b74eb305b44e354a7fb341bcb5ceb4860dd7d0129
purpose: APK-only dream screensaver resource-prune probe for
         com.android.dreams.basic after ORANGE source review. Standalone APK
         evidence is now promoted into the v0.17a system_b image; not flashed
         or live-verified.

v0.15b-phototable-locale-prune-apk
hard-rom/build/apk/com.android.dreams.phototable-locale-prune-en-zh.apk
sha256: c48ca2f6c3c95b1e0a7cbad3de2df3a7db5a78742a8cf77b3f847aa33f32a27f
purpose: APK-only PhotoTable dream resource-prune probe after ORANGE source
         review. Standalone APK evidence is now promoted into the v0.17b
         product_b image; not flashed or live-verified.

v0.16a-confdialer-locale-prune-apk
hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh.apk
sha256: ee1bb729fe3bf2577ba898c91fbb088b0942a0ecf5c60183bf0fb6046d5914db
purpose: APK-only ConferenceDialer full English/Chinese resource-prune probe
         after ORANGE sysconfig/source/graph review. Removes values-ja and
         values-ko while preserving values-zh, values-zh-rCN, values-zh-rTW,
         AndroidManifest.xml, and classes.dex. The same-size payload derived
         from this evidence is now promoted into the v0.17b system_ext_b image;
         not flashed or live-verified.

v0.17a-system-apk-only-locale-prune
tools/r2-hardrom-build-v0.17a-system-apk-only-locale-prune.sh
tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh
purpose: system-only ROM promotion for five APK-only language hard-prune
         candidates: BasicDreams, HTMLViewer, LiveWallpapersPicker,
         PrintSpooler, and SimAppDialog. Uses held-stock inodes for ext4
         shared_blocks safety and direct sparse rewrite for system_b.
super sparse:
         hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img
         sha256=2ebe837f314c35b02d5bab3bdd21d8661cf85b8cba8816e99d8d9744d2f5100a
retired local system image:
         hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img
         sha256=d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5
offline verifier:
         hard-rom/inspect/v0.17a-system-apk-only-locale-prune/verify-v0.17a-offline-image-20260618-124311.txt
         PASS; verifies all five dumped APK hashes, ZIP integrity, English/
         Chinese locale policy, held-stock hidden paths, and sparse system_b
         slice equality. Not flashed or live-verified. The standalone v0.17a
         sparse and system_b image were removed during local cleanup after
         v0.17-all was built.

v0.17b-product-system_ext-apk-only-locale-prune
tools/r2-hardrom-build-v0.17b-product-system_ext-apk-only-locale-prune.sh
tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh
purpose: product/system_ext ROM promotion for the APK-only language hard-prune
         candidates PhotoTable and ConferenceDialer.
         PhotoTable uses the held-stock inode pattern on product_b.
         ConferenceDialer uses the same-size in-place system_ext_b strategy.
super sparse:
         hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img
         sha256=f7e1c18b1023714731c714557ee5ed6763426882901026f3e914d79469c20e45
retired local product image:
         hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
         sha256=7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8
retired local system_ext image:
         hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
         sha256=742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb
offline verifier:
         hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune/verify-v0.17b-offline-image-20260618-130101.txt
         PASS; verifies PhotoTable, same-size ConferenceDialer scope, dumped
         APK hashes, ZIP integrity, English/Chinese locale policy, PhotoTable
         held-stock path, and sparse product_b/system_ext_b slice equality.
         Not flashed or live-verified. The standalone v0.17b sparse was
         removed during local cleanup after v0.17-all was built, together with
         the product_b and system_ext_b partition intermediates.

v0.17-all-apk-only-locale-prune
tools/r2-hardrom-build-v0.17-all-apk-only-locale-prune.sh
tools/r2-verify-v0.17-all-apk-only-locale-prune.sh
purpose: combined one-flash test target for all seven APK-only language prune
         promotions from v0.17a and v0.17b.
super sparse:
         hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img
         sha256=942da9469ccf9a24ff390912f26d76673415d2a500482d060a89c11847faf819
offline verifier:
         hard-rom/inspect/v0.17-all-apk-only-locale-prune/verify-v0.17-all-offline-image-20260618-131151.txt
         PASS; verifies the combined sparse contains the v0.17a system_b,
         v0.17b product_b, and v0.17b system_ext_b slices. Not flashed or
         live-verified.

v0.18a-simappdialog-locale-prune-apk
hard-rom/build/apk/com.android.simappdialog-locale-prune-en-zh.apk
sha256: 3eb68792a4edecb94920915e7e50bd19a11da887a04c88eb7069293a4b905cad
purpose: APK-only SimAppDialog English/Chinese resource-prune probe after
         ORANGE replace preflight plus source/graph review. Removes values-ja
         and values-ko while preserving AndroidManifest.xml and classes.dex.
         Standalone APK evidence is now promoted into the v0.17a system_b
         image; not flashed or live-verified.

v0.19a-companiondevicemanager-locale-prune-apk
hard-rom/build/apk/com.android.companiondevicemanager-locale-prune-en-zh.apk
sha256: 07213606d5293d7fb363776afc8eab330c84ef31255cfb85fbd9e8d9b47ab2ad
purpose: P1b focused source-reviewed CompanionDeviceManager resources.arsc
         prune. Removes values-ja and values-ko while preserving
         AndroidManifest.xml and classes.dex. This is APK-only evidence
         outside v0.17-all and not live-tested.

v0.20a-smartisan-share-browser-locale-prune-apk
hard-rom/build/apk/com.smartisanos.share.browser-locale-prune-en-zh.apk
sha256: d62475f2713e8454b8a9bf43fe7a3f0581aec1dd050baee0dc408c55dd8623e8
purpose: P1c focused source/graph-reviewed SmartisanShareBrowser
         resources.arsc prune. Removes values-ja and values-ko while
         preserving AndroidManifest.xml and classes.dex. This is APK-only
         evidence outside v0.17-all and not live-tested.

v0.21a-tracker-locale-prune-apk
hard-rom/build/apk/com.smartisanos.tracker-locale-prune-en-zh.apk
sha256: 9040314bd46e953e43827ab8d9102fe306a06c62516f0a19ec779ff078a1626c
purpose: P1d focused source/graph-reviewed TrackerSmartisan resources.arsc
         prune. Removes values-ja and values-ko app_name resources while
         preserving AndroidManifest.xml and classes.dex. This is APK-only
         evidence outside v0.17-all and not live-tested.

v0.22-all-apk-only-locale-prune
tools/r2-hardrom-build-v0.22-all-apk-only-locale-prune.sh
tools/r2-verify-v0.22-all-apk-only-locale-prune.sh
purpose: combined one-flash test target for all ten APK-only language prune
         promotions. It starts from verified v0.17-all, keeps product_b and
         system_ext_b, and adds CompanionDeviceManager, SmartisanShareBrowser,
         and TrackerSmartisan into system_b with the held-stock inode pattern.
super sparse:
         hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img
         sha256=bd1670d117b124aa70220068a031b2a608b2373fab149da5020b1a71bc312e86
system image:
         hard-rom/build/system-otatrust-v0.22-all-apk-only-locale-prune.img
         sha256=ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316
offline verifier:
         hard-rom/inspect/v0.22-all-apk-only-locale-prune/verify-v0.22-all-offline-image-20260618-141813.txt
         PASS; verifies all eight system_b APK hashes, PhotoTable and
         ConferenceDialer retained from v0.17-all, ZIP integrity, English/
         Chinese locale policy, held-stock paths, and sparse system_b/product_b/
         system_ext_b slice equality. Not flashed or live-verified.

v0.23a-cleaner-locale-prune-apk
hard-rom/build/apk/com.smartisanos.cleaner-locale-prune-en-zh.apk
sha256: d0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc
purpose: P1c focused source/graph-reviewed CleanerSmartisan binary
         resources.arsc prune. The generic apktool/aapt2 rebuild path failed
         on Smartisan private attrs, so this candidate uses
         tools/r2-build-apk-locale-prune-binary-arsc.sh to remove ja/ko
         config chunks directly from resources.arsc while preserving
         AndroidManifest.xml and classes*.dex. This APK-only evidence is now
         promoted into the v0.24 system_b image and live-verified as part of
         the v0.24 B-slot flash.

v0.24-cleaner-apk-only-locale-prune
tools/r2-hardrom-build-v0.24-cleaner-apk-only-locale-prune.sh
tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh
purpose: latest combined one-flash test target for all eleven APK-only language
         prune promotions. It starts from verified v0.22-all, keeps product_b
         and system_ext_b, and adds CleanerSmartisan into system_b with the
         held-stock inode pattern.
super sparse:
         hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img
         sha256=d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e
system image:
         hard-rom/build/system-otatrust-v0.24-cleaner-apk-only-locale-prune.img
         sha256=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6
offline verifier:
         hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-offline-image-20260618-144855.txt
         PASS; verifies all nine system_b APK hashes, PhotoTable and
         ConferenceDialer retained from v0.17-all/v0.22, ZIP integrity,
         English/Chinese locale policy, held-stock paths, and sparse
         system_b/product_b/system_ext_b slice equality.
live verifier:
         hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-device-20260618-151156.txt
         PASS; v0.24 was flashed to B slot after explicit confirmation,
         boot_completed=1, root available, launcher focused, keyguard not
         showing, and all eleven promoted APK package paths report expected
         hashes with shadow=no.

v0.11.1-native-darkmode-settings-row
tools/r2-hardrom-build-v0.11.1-native-darkmode-settings-row.sh
tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh
purpose: follow-up native dark-mode ROM candidate on top of live-verified
         v0.24. It preserves the v0.11 UiMode/SystemUI toggleDarkMode path but
         fixes SettingsSmartisan brightness-row reachability on Darwin/R2 by
         inserting the dark-mode row exposure after the :cond_5 branch target.
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
         hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
         sha256=4ac46df43c08737a36a366a6ac36349d6b69437b49e53b25f79b2f0ebe353012
         hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
         sha256=d3fe00a4e0433ab43921f66d8cc4fcc649576f81bd05e5468a37e24e6b0b187c
         hard-rom/build/apk/SmartisanSystemUI-darkmode-tile-samesize.apk
         sha256=9e8604788326e035acd2f86a69693cf4ec5a3a415258af2f177b82262fdad0da
offline verifier:
         hard-rom/inspect/v0.11.1-native-darkmode-settings-row/verify-v0.11.1-native-darkmode-settings-row-offline-image-20260618-172253.txt
         PASS; verifies APK semantics including
         brightness_darkmode_row_reachability=ok, same-size SystemUI member
         equivalence, expected dex signature-boundary failures, dumped APK
         hashes, held-stock Settings path, and sparse system_b/system_ext_b
         slice equality.
preflight:
         tools/r2-live-flash-preflight.sh v0.11.1-native-darkmode-settings-row
         PASS; required confirmation phrase:
         确认刷入 v0.11.1-native-darkmode-settings-row B 槽
status:
         flashed to B slot after explicit confirmation and live-verified at
         boot/package/hash level. A UI hierarchy probe on the 屏幕和字体 page
         proves the reachable switch_dc dark-mode row is visible and owns a
         real SwitchEx. No v0.11.1 row tap/toggle has been performed yet
         because that writes /data and requires explicit approval. The row
         currently displays the default "Dark" resource text, so native Chinese
         label polish remains before treating the Settings UX as final.
live verifier:
         hard-rom/inspect/v0.11.1-native-darkmode-settings-row/verify-v0.11.1-native-darkmode-settings-row-device-20260618-174034.txt
         PASS; boot_completed=1, slot=_b, root available, keyguard not
         showing, shared UID/signatures present, and pulled SettingsSmartisan
         and SmartisanSystemUI APK hashes match expected v0.11.1 outputs.
live-state audit:
         hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-174034.txt
         PASS_READ_ONLY; Night mode: no, secure.ui_night_mode=1, and original
         20-slot Smartisan QS data remains restored with toggleDarkMode absent.
UI visibility:
         hard-rom/inspect/v0.11.1-native-darkmode-settings-row/settings-row-ui-visibility-20260618-1740.txt
         PASS_UI_VISIBLE; Settings -> 屏幕和字体 shows the v0.11.1 row as
         text='Dark' and `smartisanos.widget.SwitchEx checked=false`.

v0.11-native-darkmode
tools/r2-hardrom-build-v0.11-native-darkmode.sh
tools/r2-verify-v0.11-native-darkmode.sh
purpose: combined native dark-mode ROM candidate on top of live-verified v0.24.
         Replaces SettingsSmartisan with the dark-mode Settings/editor APK and
         SmartisanSystemUI with the toggleDarkMode tile APK. It has now booted
         and passed live read-only package/hash verification plus reversible
         UiMode/SystemUI toggleDarkMode functional write testing. Settings row
         and Smartisan QS editor UX proof remains.
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
         hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
         sha256=8a4472dbfe90c16dc3cdf01eb2a41bdcb951b5c0da1b07d57dba19373812a7f0
         hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
         sha256=c80904f85acf15ca706d4a40b1dad9f5c556ff69affa7fe270a9221889a7de26
         hard-rom/build/apk/SmartisanSystemUI-darkmode-tile-samesize.apk
         sha256=42996f1c39b5a7bf3775c7da59982b385ced43a74dcb431b1973e64ffd19fe1f
offline verifier:
         hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-offline-image-20260618-163441.txt
         PASS; verifies APK semantics, same-size SystemUI member equivalence,
         expected dex signature-boundary failures, dumped SettingsSmartisan and
         SmartisanSystemUI APK hashes, held-stock Settings path, and sparse
         system_b/system_ext_b slice equality.
preflight:
         tools/r2-live-flash-preflight.sh v0.11-native-darkmode
         PASS; required confirmation phrase:
         确认刷入 v0.11-native-darkmode B 槽
live verifier:
         hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-20260618-165423.txt
         PASS; v0.11 was flashed to B slot after exact confirmation,
         boot_completed=1, slot=_b, root available, launcher focused after
         Home, keyguard not showing, shared UID/signatures present, and pulled
         SettingsSmartisan/SmartisanSystemUI APK hashes matched expected v0.11
         outputs.
functional verifier:
         tools/r2-darkmode-functional-test.sh --write-approved
         hard-rom/inspect/v0.11-native-darkmode-functional/v0.11-darkmode-functional-20260618-170411.txt
         PASS_WRITE_APPROVED_FUNCTIONAL; after explicit /data-write approval,
         UiModeManager accepted night yes/no, secure.ui_night_mode moved
         1->2->1, SystemUI instantiated toggleDarkMode after a temporary
         20-slot expanded_widget_buttons replacement, and original UiMode/QS
         settings were restored. Follow-up read-only state:
         hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-170426.txt
         PASS_READ_ONLY with Night mode: no, secure.ui_night_mode=1, and
         toggleDarkMode absent from restored main/additional QS data.
boundary:
         a later APK reachability audit found the v0.11 Settings row exposure
         was inserted before the Darwin :cond_5 branch target, so R2 can jump
         over it. Treat v0.11 as live proof for boot/package/hash,
         UiModeManager yes/no, and SystemUI toggleDarkMode tile creation only.
         Use v0.11.1-native-darkmode-settings-row for the Settings row UX gate.

SmartisanSystemUI-certprobe-noop-apk
hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk
sha256: 654ff82819cf6a7bf42a3463cb9559196f871234800ad74ee0030963ce487d69
purpose: same-size APK-level SystemUI no-op gate. Changes only the first byte
         of the APK v2 signing block magic at offset 56852464. All 6137
         ZIP/JAR entries remain byte-identical, and keytool/jarsigner still
         read the Smartisan Android cert.

systemui-certprobe-noop ROM gate
hard-rom/build/super-otatrust-systemui-certprobe-noop-exact-current.sparse.img
sha256: 836e8e7d2377580dc6237b617471084710d6b90c649f764b5f09681fd459cc60
purpose: exact-current system_ext_b no-op gate for SmartisanSystemUI. Offline
         verification passed. Not flashed or live-verified.
```

Cold rollback archive:

```text
v0.2 no-appstore
/Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/hard-rom/build/super-otatrust-v0.2-no-appstore-exact-current.sparse.img
sha256: 63bbc29f53d06adc5450cab2628430b67bd8feaf5ab8a578d1180fa60c2fb485
restore target: hard-rom/build/super-otatrust-v0.2-no-appstore-exact-current.sparse.img
```

Pre-hard-ROM raw super cold archive:

```text
/Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img
sha256: f0e7d91c422e5467b0c628fea9a3824c8187b6079967cfa5171c17b9c92ca03a
restore target: backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img
```
