# System Modification Readiness Audit

Date: 2026-06-18.

This read-only audit tracks readiness for two active goals: native
system-level light/dark mode integration and English/Chinese-only ROM
language hard-pruning. It does not modify APKs, images, partitions,
the live device, or `/data`.

TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/system-modification-readiness-audit.tsv`

## Summary

- proven_live: 8
- proven_offline: 49
- retired_local: 5
- missing: 5
- not_achieved: 1

## Completion Boundary

- Dark mode is not complete until SettingsSmartisan and SystemUI live no-op
  gates pass, the current UiMode/QS state is captured, a combined exact-
  current ROM image exists, it boots, UiMode/SystemUI functional writes
  pass, and the remaining Settings row/QS editor UX is verified on device.
- Language hard-prune is not complete while any non-English/non-Chinese
  resource packages remain outside deletion or verified hard-prune coverage,
  and v0.12/v0.10 have not passed live framework gates. Current live
  locale/package-shadow state must also be captured before validating a
  language build.

## rollback

| status | requirement | evidence | gap |
| --- | --- | --- | --- |
| proven_offline | local v0.4 rollback sparse image is ready | hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img sha256=313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5 |  |

## dark_mode

| status | requirement | evidence | gap |
| --- | --- | --- | --- |
| proven_live | current device UiMode and Smartisan QS settings have been captured read-only | hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-170426.txt contains read-only UiMode/QS system-setting summary | required before choosing a default tile replacement, SettingsProvider seed, or live QS data migration |
| proven_live | v0.25 current-base SettingsSmartisan no-op replacement has booted and verified live | hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-20260618-155616.txt contains 'PASS: v0.25-settings-noop-on-v0.24 verification' | required before rebuilding or flashing v0.8/v0.11 Settings behavior patches on the v0.24 line |
| proven_live | current-base SmartisanSystemUI no-op replacement has booted and verified live | hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-20260618-160919.txt contains 'PASS: systemui-certprobe-noop-on-v0.24 device read-only verification' | required before native toggleDarkMode SystemUI patch |
| proven_live | v0.11 native dark-mode behavior ROM booted and verified patched APKs live | hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-20260618-165423.txt contains 'PASS: v0.11 native dark-mode device read-only verification' | next needs manual user-facing proof for Settings row and Smartisan QS editor behavior |
| proven_live | v0.11 reversible functional write test proves UiMode yes/no and SystemUI toggleDarkMode tile creation | hard-rom/inspect/v0.11-native-darkmode-functional/v0.11-darkmode-functional-20260618-170411.txt proves UiMode yes/no, SystemUI toggleDarkMode tile creation, and restored QS data | SettingsSmartisan dark-mode row visibility/click behavior and QS editor candidate UX still need manual device proof |
| proven_live | combined v0.11 exact-current dark-mode ROM image exists | hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img | already flashed and matched live APK hashes; UiMode/SystemUI tile functional proof now exists |
| proven_offline | SettingsSmartisan native dark-mode UI APK candidate exists | hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk sha256=8a4472dbfe90c16dc3cdf01eb2a41bdcb951b5c0da1b07d57dba19373812a7f0 | included in the combined v0.11 ROM candidate; live package/hash proof and UiMode/SystemUI functional proof now exist; Settings row UX still needs manual proof |
| proven_offline | SmartisanSystemUI native toggleDarkMode APK candidate exists | hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk sha256=c80904f85acf15ca706d4a40b1dad9f5c556ff69affa7fe270a9221889a7de26 | included in the combined v0.11 ROM candidate; live package/hash proof and reversible SystemUI tile-creation proof now exist |
| proven_offline | v0.11 APK semantic verifier proves intended Settings/SystemUI call sites | hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-20260618-163441.txt contains 'PASS' | semantic APK proof is not live PackageManager/shared-UID proof |
| proven_offline | dark-mode source coupling audit maps stock framework, Settings, SystemUI, resources, and gates | docs/research/darkmode-source-coupling-audit.md contains required structured markers | source-coupling proof now includes live boot/package/hash plus reversible UiMode/SystemUI functional evidence; Settings row/editor UX still needs manual proof |
| proven_offline | dark-mode QS default/editor strategy audit maps the native-key integration routes | docs/research/darkmode-qs-strategy-audit.md contains required structured markers | candidate injection is offline-proven; default visibility, live editor availability, and data migration still need live gates |
| proven_offline | dark-mode persistence audit maps SettingsProvider seed, editor reset, restore, and SystemUI truncation paths | docs/research/darkmode-persistence-audit.md contains required structured markers | editor/additional route is offline-mapped; default-visible behavior still needs live state and later policy |
| proven_offline | v0.25 current-base SettingsSmartisan no-op image verifies offline | hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-152320.txt contains required structured markers | offline image proof is not live PackageManager/shared-UID proof |
| proven_offline | current-base SmartisanSystemUI no-op image verifies offline | hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-offline-20260618-154040.txt contains required structured markers | offline image proof is not live PackageManager/shared-UID proof |

## language

| status | requirement | evidence | gap |
| --- | --- | --- | --- |
| proven_live | current device locale, package path, and updated-system shadow state have been captured read-only | hard-rom/inspect/language-live-state/language-live-state-20260618-151050.txt contains read-only locale/package shadow summary | required before validating visible language behavior, /data updated-system shadows, or live language migration |
| proven_live | v0.24 combined APK-only language hard-prune image has booted and verified live | hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-device-20260618-151156.txt contains required structured markers | live proof covers the eleven promoted APK-only replacements; full English/Chinese hard-prune still has remaining packages |
| proven_offline | v0.7 Settings language picker filter APK semantics are proven offline | hard-rom/inspect/v0.7-locale-filter/verify-settingssmartisan-locale-filter-apk-20260618-073901.txt contains 'PASS' | visible filter is not resource hard-prune |
| proven_offline | language source coupling audit maps Settings picker, framework AssetManager, ResourcesImpl, non-UI locale users, and gates | docs/research/language-source-coupling-audit.md contains required structured markers | source-coupling proof is not live framework/package-manager proof |
| proven_offline | language prune integration map defines visible-list, framework, package, fallback, and live gates | docs/research/language-prune-integration-map.md contains required structured markers | integration map is not live PackageManager/resource proof |
| proven_offline | language next-batch plan separates existing APK-only promotion, new APK candidates, and package/core gates | docs/research/language-next-batch-plan.md contains required structured markers | planning proof only; packages still need review, image builds, live gates, and device validation |
| proven_offline | language P1 source-review audit ranks the small APK-only candidates by manifest and source coupling | docs/research/language-p1-source-review-audit.md contains required structured markers | source-review proof only; selected packages still need APK build, verifier, image insertion, and live validation |
| proven_offline | v0.12 framework-res no-op image verifies offline | hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-offline-image-20260618-071439.txt contains required structured markers | offline image proof is not early-boot live proof |
| proven_offline | v0.10 framework/product language hard-prune image verifies offline | hard-rom/inspect/v0.10-framework-locale-prune/verify-v0.10-offline-image-20260618-071729.txt contains required structured markers | offline image proof is not live boot or full-ROM language completion |
| proven_offline | ja/ko subset resource coverage is measured | stock=175 packages/509 dirs; covered=40 packages/141 dirs; remaining=134 packages/362 dirs; v0.13=3 packages; apk_only=0 packages/0 dirs | ja/ko is only a subset of the English/Chinese-only target |
| proven_offline | full non-English/non-Chinese ROM language-resource coverage is measured | stock=179 packages/5650 dirs; ja_ko=515 dirs; other_non_target=5135 dirs; covered=40 packages/895 dirs; remaining=138 packages/4674 dirs; visible_only=1 packages/81 dirs; apk_only=0 packages/0 dirs | remaining packages mean the English/Chinese-only physical prune goal is not complete |
| proven_offline | tier1a minimal-exposure APK language hard-prune candidates verify offline | hard-rom/inspect/tier1a-locale-prune-apks/verify-tier1a-locale-prune-apks-20260618-115520.txt contains 'PASS' | APK proof is not ROM image or live boot proof |
| proven_offline | v0.14a LiveWallpapersPicker APK language hard-prune candidate exists | com.android.wallpaper.livepicker v0.14a-livewallpaperpicker-locale-prune-apk; hard-rom/build/apk/com.android.wallpaper.livepicker-locale-prune-en-zh.apk sha256=acf2131fe283817b61e1f99ebaceddc2973caaaaddae0e86cd070d20dbb10130 | APK proof is not ROM image or live boot proof |
| proven_offline | v0.14b HTMLViewer APK language hard-prune candidate exists | com.android.htmlviewer v0.14b-htmlviewer-locale-prune-apk; hard-rom/build/apk/com.android.htmlviewer-locale-prune-en-zh.apk sha256=fcfdd58b5fb92bfc05b6eba8cfc13759e3175d0e3db3cca7c129fec528282e35 | APK proof is not ROM image or live boot proof |
| proven_offline | v0.15a BasicDreams APK language hard-prune candidate exists | com.android.dreams.basic v0.15a-basicdreams-locale-prune-apk; hard-rom/build/apk/com.android.dreams.basic-locale-prune-en-zh.apk sha256=2512094b9ac6ab042e97f37b74eb305b44e354a7fb341bcb5ceb4860dd7d0129 | APK proof is not ROM image or live boot proof |
| proven_offline | v0.15b PhotoTable APK language hard-prune candidate exists | com.android.dreams.phototable v0.15b-phototable-locale-prune-apk; hard-rom/build/apk/com.android.dreams.phototable-locale-prune-en-zh.apk sha256=c48ca2f6c3c95b1e0a7cbad3de2df3a7db5a78742a8cf77b3f847aa33f32a27f | APK proof is not ROM image or live boot proof |
| proven_offline | v0.16a ConferenceDialer APK language hard-prune candidate exists | com.qualcomm.qti.confdialer v0.16a-confdialer-locale-prune-apk; hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh.apk sha256=ee1bb729fe3bf2577ba898c91fbb088b0942a0ecf5c60183bf0fb6046d5914db | APK proof is not ROM image or live boot proof |
| proven_offline | v0.18a SimAppDialog APK language hard-prune candidate exists | com.android.simappdialog v0.18a-simappdialog-locale-prune-apk; hard-rom/build/apk/com.android.simappdialog-locale-prune-en-zh.apk sha256=3eb68792a4edecb94920915e7e50bd19a11da887a04c88eb7069293a4b905cad | APK proof is not ROM image or live boot proof |
| proven_offline | v0.19a CompanionDeviceManager APK language hard-prune candidate exists | com.android.companiondevicemanager v0.19a-companiondevicemanager-locale-prune-apk; hard-rom/build/apk/com.android.companiondevicemanager-locale-prune-en-zh.apk sha256=07213606d5293d7fb363776afc8eab330c84ef31255cfb85fbd9e8d9b47ab2ad | APK proof is not ROM image or live boot proof |
| proven_offline | v0.20a SmartisanShareBrowser APK language hard-prune candidate exists | com.smartisanos.share.browser v0.20a-smartisan-share-browser-locale-prune-apk; hard-rom/build/apk/com.smartisanos.share.browser-locale-prune-en-zh.apk sha256=d62475f2713e8454b8a9bf43fe7a3f0581aec1dd050baee0dc408c55dd8623e8 | APK proof is not ROM image or live boot proof |
| proven_offline | v0.21a TrackerSmartisan APK language hard-prune candidate exists | com.smartisanos.tracker v0.21a-tracker-locale-prune-apk; hard-rom/build/apk/com.smartisanos.tracker-locale-prune-en-zh.apk sha256=9040314bd46e953e43827ab8d9102fe306a06c62516f0a19ec779ff078a1626c | APK proof is not ROM image or live boot proof |
| proven_offline | v0.14a LiveWallpapersPicker APK verifies offline | hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-144724.txt contains required structured markers | APK-only evidence remains outside ROM coverage until a matching image is built |
| proven_offline | APK-only language hard-prune candidate batch verifies offline | hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-144724.txt contains required structured markers | APK-only evidence remains outside ROM coverage until matching images are built |
| proven_offline | v0.17 APK-only ROM promotion audit maps partition ownership, space gates, and system_ext replacement risk | docs/research/v0.17-apk-only-promotion-audit.md contains required structured markers | planning proof only; built-image and live proofs are tracked separately |
| proven_offline | v0.17a system APK-only ROM build and verification scripts exist | tools/r2-hardrom-build-v0.17a-system-apk-only-locale-prune.sh, tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh | scripts alone are not a flashable image |
| proven_offline | v0.17a system APK-only image verifies offline | hard-rom/inspect/v0.17a-system-apk-only-locale-prune/verify-v0.17a-offline-image-20260618-124311.txt contains required structured markers | offline image proof is not live boot proof |
| proven_offline | v0.17b product/system_ext APK-only ROM build and verification scripts exist | tools/r2-hardrom-build-v0.17b-product-system_ext-apk-only-locale-prune.sh, tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh | scripts alone are not a flashable image |
| proven_offline | v0.17b product/system_ext APK-only image verifies offline | hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune/verify-v0.17b-offline-image-20260618-130101.txt contains required structured markers | offline image proof is not live boot proof |
| proven_offline | v0.17-all combined APK-only ROM build and verification scripts exist | tools/r2-hardrom-build-v0.17-all-apk-only-locale-prune.sh, tools/r2-verify-v0.17-all-apk-only-locale-prune.sh | scripts alone are not a flashable image |
| proven_offline | v0.17-all combined APK-only language hard-prune flashable sparse super exists | hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img sha256=942da9469ccf9a24ff390912f26d76673415d2a500482d060a89c11847faf819 | not flashed or live-verified; explicit confirmation required before any flash |
| proven_offline | v0.17-all combined APK-only image verifies offline | hard-rom/inspect/v0.17-all-apk-only-locale-prune/verify-v0.17-all-offline-image-20260618-131151.txt contains required structured markers | offline image proof is not live boot proof |
| proven_offline | v0.22 combined APK-only ROM build and verification scripts exist | tools/r2-hardrom-build-v0.22-all-apk-only-locale-prune.sh, tools/r2-verify-v0.22-all-apk-only-locale-prune.sh | scripts alone are not a flashable image |
| proven_offline | v0.22 combined APK-only language hard-prune flashable sparse super exists | hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img sha256=bd1670d117b124aa70220068a031b2a608b2373fab149da5020b1a71bc312e86 | not flashed or live-verified; explicit confirmation required before any flash |
| proven_offline | v0.22 combined APK-only system_b image exists | hard-rom/build/system-otatrust-v0.22-all-apk-only-locale-prune.img sha256=ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316 | system image is local verifier evidence; sparse super and live boot proof are separate gates |
| proven_offline | v0.22 combined APK-only image verifies offline | hard-rom/inspect/v0.22-all-apk-only-locale-prune/verify-v0.22-all-offline-image-20260618-141813.txt contains required structured markers | offline image proof is not live boot proof |
| proven_offline | v0.24 CleanerSmartisan APK-only ROM build and verification scripts exist | tools/r2-hardrom-build-v0.24-cleaner-apk-only-locale-prune.sh, tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh | scripts alone are not a flashable image |
| proven_offline | v0.24 CleanerSmartisan language hard-prune flashable sparse super exists | hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img sha256=d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e | live boot/package proof is tracked by the separate v0.24 device verifier gate |
| proven_offline | v0.24 CleanerSmartisan system_b image exists | hard-rom/build/system-otatrust-v0.24-cleaner-apk-only-locale-prune.img sha256=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6 | system image is local verifier evidence; sparse super and live boot proof are separate gates |
| proven_offline | v0.24 CleanerSmartisan image verifies offline | hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-offline-image-20260618-144855.txt contains required structured markers | offline image proof is complemented by the separate v0.24 device verifier gate |
| proven_offline | v0.13 Tier1a ROM build and verification scripts exist | tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh, tools/r2-verify-v0.13-tier1a-locale-prune.sh | scripts alone are not a flashable image |
| proven_offline | v0.13 Tier1a system_b image verifies offline | hard-rom/inspect/v0.13-tier1a-locale-prune/verify-v0.13-offline-system-image-20260618-081444.txt contains required structured markers | offline system_b proof is not sparse-super proof or live boot proof |
| retired_local | v0.17a system APK-only language hard-prune system_b image exists or is intentionally retired | hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img removed from Mac working tree after cleanup; retained replacement evidence is hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img | rebuild only if the partition image itself must be reverified |
| retired_local | v0.17a standalone system APK-only sparse is either present or intentionally retired | hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img removed from Mac working tree after cleanup; current retained combined target is hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img | rebuild only if a smaller system-only live test is deliberately selected |
| retired_local | v0.17b product APK-only language hard-prune product_b image exists or is intentionally retired | hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img removed from Mac working tree after cleanup; retained replacement evidence is hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img | rebuild only if the partition image itself must be reverified |
| retired_local | v0.17b system_ext APK-only language hard-prune system_ext_b image exists or is intentionally retired | hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img removed from Mac working tree after cleanup; retained replacement evidence is hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img | rebuild only if the partition image itself must be reverified |
| retired_local | v0.17b standalone product/system_ext APK-only sparse is either present or intentionally retired | hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img removed from Mac working tree after cleanup; current retained combined target is hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img | rebuild only if a smaller product/system_ext-only live test is deliberately selected |
| missing | v0.12 framework-res no-op replacement image exists | hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img is missing |  |
| missing | v0.12 framework-res no-op has booted and verified live | no report matches hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-device-*.txt | required before treating v0.10 failure/success as language-prune behavior |
| missing | v0.10 framework/product language hard-prune image exists | hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img is missing |  |
| missing | v0.13 Tier1a language hard-prune system_b image exists | hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img is missing |  |
| missing | v0.13 Tier1a flashable sparse super exists | not built; BUILD_SUPER=1 not run | build only when local free space is sufficient, then run --offline-image |
| not_achieved | all non-English/non-Chinese ROM resources have been physically pruned | 138 packages and 4674 non-English/non-Chinese dirs remain outside current ROM coverage | continue staged package/resource pruning and live framework gates |
