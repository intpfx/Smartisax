# Locale Pruning Map

Date: 2026-06-18.

This note is generated from decoded static ROM resources. It maps locale
resource qualifiers for ROM-level language pruning research. It does not
modify any image or device state.

## Summary

- decoded APK/resource packages scanned: 289
- packages with locale-qualified values dirs: 190
- packages with Japanese/Korean resource dirs: 175
- TSV inventory: `reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv`
- current coverage audit: `docs/research/locale-prune-coverage-audit.md`
- coverage TSV: `reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv`

Japanese/Korean hits by risk tier:

- AMBER_ANDROID_STATIC_OVERLAY: 5
- AMBER_PRIV_APP: 40
- AMBER_SHARED_UID: 18
- GREEN_OR_YELLOW_APP: 66
- RED_CORE_APP: 25
- RED_FRAMEWORK_SYSTEM_ASSET: 1
- RED_SHARED_UID: 19
- RED_SMARTISAN_FRAMEWORK_ASSET: 1

## Core Findings

- Smartisan's main language picker uses
  `Resources.getSystem().getAssets().getLocales()`, not only
  `android.R.array.supported_locales`.
- The system AssetManager is built from `framework-res.apk`,
  `framework-smartisanos-res.apk`, and immutable static overlays
  targeting `android`.
- A product/vendor RRO can override arrays such as `supported_locales`,
  but it cannot hide locale configurations already compiled into
  framework resource APKs.
- A true hard prune of visible Smartisan system locales therefore needs
  either framework resource repacking, a framework/Settings code patch,
  or an equivalent hook that filters `AssetManager.getLocales()`.

2026-06-18 source recheck:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  reads Resources.getSystem().getAssets().getLocales()
  sorts the raw locale strings
  keeps regioned entries where str.length() == 5
  creates Locale(language, country)

framework ResourcesImpl.updateConfiguration()
  reads AssetManager.getNonSystemLocales()
  falls back to AssetManager.getLocales()
  writes the chosen adjusted language tag back to AssetManager.setConfiguration()

AssetManagerSmtEx / ResourcesImplSmtEx
  Smartisan resource extension code is present, but the observed extension body
  is icon/drawable redirection and screen-mode plumbing, not a simple locale
  filter hook.
```

Practical result:

```text
To hide languages only in Settings, the SettingsSmartisan v0.7 filter is the
smallest behavior patch, but it is still gated by v0.6 Settings no-op.

To hard-prune the ROM so AssetManager no longer exposes ja/ko framework locale
configs, v0.10 is the correct first combined candidate, but it is gated by the
smaller v0.12 framework-res no-op live test.

For package-by-package hard pruning after v0.10, use
tools/r2-locale-prune-coverage-audit.py first. The 2026-06-18 audit reports:
  stock ja/ko resource packages: 175 packages, 509 dirs
  covered by v0.2/v0.4 deletion or v0.10/v0.13 hard-prune candidates: 29 packages, 119 dirs
  v0.7 visible-filter only, not resource-pruned: 1 package, 6 dirs
  remaining hard-prune work: 145 packages, 384 dirs
  first safe offline frontier: 19 small GREEN/YELLOW APK resource-prune candidates
  v0.13 completed minimal-exposure system-image batch: 3 packages
    com.android.protips
    com.android.printservice.recommendation
    com.android.hotspot2.osulogin
```

## First High-Risk Targets

| risk | ja/ko dirs | package | decoded dir |
| --- | ---: | --- | --- |
| AMBER_ANDROID_STATIC_OVERLAY | 2 | com.android.internal.display.cutout.emulation.corner | `product__overlay__DisplayCutoutEmulationCorner__DisplayCutoutEmulationCornerOverlay.apk` |
| AMBER_ANDROID_STATIC_OVERLAY | 2 | com.android.internal.display.cutout.emulation.double | `product__overlay__DisplayCutoutEmulationDouble__DisplayCutoutEmulationDoubleOverlay.apk` |
| AMBER_ANDROID_STATIC_OVERLAY | 2 | com.android.internal.display.cutout.emulation.hole | `product__overlay__DisplayCutoutEmulationHole__DisplayCutoutEmulationHoleOverlay.apk` |
| AMBER_ANDROID_STATIC_OVERLAY | 2 | com.android.internal.display.cutout.emulation.tall | `product__overlay__DisplayCutoutEmulationTall__DisplayCutoutEmulationTallOverlay.apk` |
| AMBER_ANDROID_STATIC_OVERLAY | 2 | com.android.internal.display.cutout.emulation.waterfall | `product__overlay__DisplayCutoutEmulationWaterfall__DisplayCutoutEmulationWaterfallOverlay.apk` |
| AMBER_PRIV_APP | 36 | com.android.cellbroadcastreceiver.module | `system__system__apex__com.android.cellbroadcast__priv-app__CellBroadcastApp__CellBroadcastApp.apk` |
| AMBER_PRIV_APP | 4 | com.smartisanos.clock | `system__system__priv-app__ClockSmartisan__ClockSmartisan.apk` |
| AMBER_PRIV_APP | 4 | com.smartisanos.desktop | `system__system__priv-app__Desktop__Desktop.apk` |
| AMBER_PRIV_APP | 4 | com.android.launcher3 | `system__system__priv-app__LauncherOrigSmartisan__LauncherOrigSmartisan.apk` |
| AMBER_PRIV_APP | 4 | com.smartisanos.launcher | `system__system__priv-app__LauncherSmartisanNew__LauncherSmartisanNew.apk` |
| AMBER_PRIV_APP | 4 | com.smartisanos.powersaving.launcher | `system__system__priv-app__PowerSavingLauncher__PowerSavingLauncher.apk` |
| AMBER_PRIV_APP | 4 | com.smartisanos.expandservice | `system__system__priv-app__SmartisanExpandService__SmartisanExpandService.apk` |
| AMBER_PRIV_APP | 4 | com.smartisanos.wallet | `system__system__priv-app__WalletSmartisan__WalletSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.android.settings.intelligence | `product__priv-app__SettingsIntelligence__SettingsIntelligence.apk` |
| AMBER_PRIV_APP | 2 | com.android.providers.media.module | `system__system__apex__com.android.mediaprovider__priv-app__MediaProvider__MediaProvider.apk` |
| AMBER_PRIV_APP | 2 | com.android.backupconfirm | `system__system__priv-app__BackupRestoreConfirmation__BackupRestoreConfirmation.apk` |
| AMBER_PRIV_APP | 2 | com.android.calendar | `system__system__priv-app__CalendarSmartisan__CalendarSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.android.cellbroadcastreceiver | `system__system__priv-app__CellBroadcastLegacyApp__CellBroadcastLegacyApp.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.cloudsyncshare | `system__system__priv-app__CloudServiceShare__CloudServiceShare.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.cloudsync | `system__system__priv-app__CloudServiceSmartisan__CloudServiceSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.cloudagent | `system__system__priv-app__CloudSyncAgent__CloudSyncAgent.apk` |
| AMBER_PRIV_APP | 2 | com.android.documentsui | `system__system__priv-app__DocumentsUI__DocumentsUI.apk` |
| AMBER_PRIV_APP | 2 | com.android.externalstorage | `system__system__priv-app__ExternalStorageProvider__ExternalStorageProvider.apk` |
| AMBER_PRIV_APP | 2 | com.android.managedprovisioning | `system__system__priv-app__ManagedProvisioning__ManagedProvisioning.apk` |
| AMBER_PRIV_APP | 2 | com.android.mms | `system__system__priv-app__MmsSmartisan__MmsSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.android.musicfx | `system__system__priv-app__MusicFX__MusicFX.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.music | `system__system__priv-app__MusicPlayer__MusicPlayer.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.numberassistant | `system__system__priv-app__NumberAssistant__NumberAssistant.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.recharge | `system__system__priv-app__RechargeSmartisan__RechargeSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.screenrecorder | `system__system__priv-app__ScreenRecorderSmartisan__ScreenRecorderSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.smartisanbrain | `system__system__priv-app__SmartisanBrain__SmartisanBrain.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.manual | `system__system__priv-app__SmartisanShareManual__SmartisanShareManual.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.updater | `system__system__priv-app__SmartisanUpdater__SmartisanUpdater.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.smsparser | `system__system__priv-app__SmsParser__SmsParser.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.recorder | `system__system__priv-app__SoundRecorderSmartisan__SoundRecorderSmartisan.apk` |
| AMBER_PRIV_APP | 2 | com.android.apps.tag | `system__system__priv-app__Tag__Tag.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.teatracker | `system__system__priv-app__TeaTracker__TeaTracker.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.videoplayerproject | `system__system__priv-app__VideoPlayer__VideoPlayer.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.sara | `system__system__priv-app__VoiceAssistant__VoiceAssistant.apk` |
| AMBER_PRIV_APP | 2 | com.smartisanos.whiteboard | `system__system__priv-app__WhiteBoardSmartisan__WhiteBoardSmartisan.apk` |

## Practical Boundary

Restricting the selectable language list is easier than physically removing
all non-target translations from the ROM. Full ROM language slimming needs
package-by-package signing and boot-risk handling, especially for core
shared-UID packages.

Current first hard-ROM behavior candidate:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  source:
    reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/inputmethod/LocalePickerFragment.java
  behavior:
    Resources.getSystem().getAssets().getLocales()
    filters locale strings by length == 5
  v0.7 patch:
    skip ja_JP and ko_KR before LocaleInfo creation
```

This should hide Japanese and Korean from Smartisan's visible picker while
leaving framework resources intact. It is preferable to a first
`framework-res.apk` patch because SettingsSmartisan is less early-boot than
framework resources, but it remains a core shared-UID APK.

The v0.7 offline candidate has been built:

```text
build script:
  tools/r2-hardrom-build-v0.7-locale-filter.sh
super sparse:
  hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img
  sha256=d3dfef95d52dd1a26b399b2ef8a375c2645edfb08de46e4431e68cb5f823f9e4
verification script:
  tools/r2-verify-v0.7-locale-filter.sh
```

APK-level semantic verification:

```text
script:
  tools/r2-verify-settingssmartisan-locale-filter-apk.sh

report:
  hard-rom/inspect/v0.7-locale-filter/verify-settingssmartisan-locale-filter-apk-20260618-073901.txt

smali evidence:
  hard-rom/inspect/v0.7-locale-filter/smali-evidence-20260618-073901/

checks:
  only classes.dex changed from stock SettingsSmartisan
  LocalePickerFragment.constructAdapter() still calls AssetManager.getLocales()
  constructAdapter() compares each locale string to ja_JP and ko_KR
  both matches jump to the existing skip branch before length==5 processing and
  LocaleInfo creation
  expected classes.dex digest-error signature boundary remains

result:
  PASS
```

It must wait for the v0.6 SettingsSmartisan no-op replacement gate described in:

```text
docs/research/system-apk-signature-boundary.md
```

## First Resource-Table Probe

The first low-risk L2 resource-table hard-prune target is:

```text
package: com.android.protips
path: /system/app/Protips/Protips.apk
risk:
  delete preflight: GREEN
  replace preflight: ORANGE only because same-package replacement must preserve
                    manifest/resources/signature/cache behavior
components:
  one receiver
  no requested permissions
  no exported components
  no sharedUserId
```

Why this target:

```text
Protips is still present on the live v0.4 package list.
It is not Settings, SystemUI, framework, launcher, WebView, browser, installer,
permission controller, telephony, or provider infrastructure.
It has small compiled locale resources:
  values-ja
  values-ko
  values-zh-rCN
  values-zh-rTW
```

APK-level probe result:

```text
build script:
  tools/r2-build-protips-locale-prune-apk.sh
patched APK:
  hard-rom/build/apk/Protips-locale-prune-ja-ko.apk
sha256:
  12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d
stock APK sha256:
  6c17dafe725cbe31b1c256078b719fc5accd6b66e23e05ebac28e6d283dd93d1
signature boundary:
  keytool_status=1
  SHA-256 digest error for resources.arsc
resource verification:
  decoded patched APK keeps:
    values
    values-zh-rCN
    values-zh-rTW
  decoded patched APK no longer has:
    values-ja
    values-ko
```

The prepared but not-yet-run ROM builder is:

```text
tools/r2-hardrom-build-v0.9-protips-locale-prune.sh
```

This probe does not make the whole ROM English/Chinese-only. It proves the APK
resource-table surgery needed for later package groups.

## Generic APK Locale-Prune Tool

The one-off Protips script has been generalized into:

```text
tools/r2-build-apk-locale-prune.sh
```

Supported inputs:

```text
tools/r2-build-apk-locale-prune.sh --package <package.name> [--out <apk>]
tools/r2-build-apk-locale-prune.sh --apk <path/to/app.apk> --label <name> [--out <apk>]
```

Resource policy:

```text
keep:
  res/values
  res/values-en*
  res/values-zh*
  non-locale values qualifiers, such as values-night or values-v31

remove:
  every other locale-qualified values dir, such as values-ja, values-ko,
  values-fr, values-pt-rBR, values-mcc001-ja
```

Implementation boundary:

```text
decode stock APK with apktool
remove non-target locale values dirs from decoded resources
rebuild an unsigned intermediate
merge only resources.arsc back into the stock APK shell
verify classes.dex and AndroidManifest.xml remain byte-identical when present
decode the merged APK and confirm no non-target locale values dirs remain
record the expected resources.arsc digest failure from keytool/jarsigner
```

Verified samples:

```text
package:
  com.android.protips
output:
  hard-rom/build/apk/com.android.protips-locale-prune-en-zh.apk
sha256:
  12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d
resource result:
  removed values-ja and values-ko
  kept values-zh-rCN and values-zh-rTW
equivalence:
  output hash matches the earlier Protips-only script exactly
  classes.dex and AndroidManifest.xml remain byte-identical to stock
```

```text
package:
  com.android.printservice.recommendation
reason for sample:
  Tier1a minimal-exposure locale-prune candidate; one service, no exported
  components, package-index status ok, but sysconfig hiddenapi-whitelist
  reference means ROM flashing still needs a focused package gate.
output:
  hard-rom/build/apk/com.android.printservice.recommendation-locale-prune-en-zh.apk
sha256:
  3d92952e74308a3402e0debb5a0ca0a1c909b5cc1990968ccfcbe73377ceb806
resource result:
  removed values-ja and values-ko
  kept values-zh-rCN and values-zh-rTW
equivalence:
  classes.dex and AndroidManifest.xml remain byte-identical to stock
```

```text
package:
  com.android.hotspot2.osulogin
reason for sample:
  Tier1a minimal-exposure locale-prune candidate; one non-exported activity,
  package-index status ok, located under the Wi-Fi APEX app directory, so ROM
  flashing still needs a focused package gate.
output:
  hard-rom/build/apk/com.android.hotspot2.osulogin-locale-prune-en-zh.apk
sha256:
  4e3059205ea37596aa9957f6b96a26517eeb09b2b7055d15344edf70e4dfb65c
resource result:
  removed values-ja and values-ko
  kept values-zh-rCN and values-zh-rTW
equivalence:
  classes.dex and AndroidManifest.xml remain byte-identical to stock
```

```text
package:
  com.android.printspooler
reason for sample:
  non-core system app with a large locale table, used as an offline pressure
  test for the generic tool rather than as a flash candidate
preflight:
  replace ORANGE because it is sysconfig-referenced, exports one service, and
  is still a same-package replacement
output:
  hard-rom/build/apk/com.android.printspooler-locale-prune-en-zh.apk
sha256:
  a2ff64e2c2d2b2587a92f04169b2c677c718c3c8a76e411a7f1270f5d42b9555
resource result:
  removed 77 non-English/non-Chinese locale values dirs
  kept 9 English/Chinese locale values dirs:
    values-en-rAU, values-en-rCA, values-en-rGB, values-en-rIN,
    values-en-rUS, values-en-rXC, values-zh-rCN, values-zh-rHK,
    values-zh-rTW
equivalence:
  classes.dex and AndroidManifest.xml remain byte-identical to stock
```

Tier1a batch verifier:

```text
tools/r2-verify-tier1a-locale-prune-apks.sh
hard-rom/inspect/tier1a-locale-prune-apks/verify-tier1a-locale-prune-apks-20260618-080340.txt
result=PASS
```

APK-only batch verifier:

```text
tools/r2-verify-apk-only-locale-prune-candidates.sh
hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-101346.txt
result=PASS_OFFLINE_APK_ONLY_BATCH
packages:
  com.android.dreams.basic
  com.android.dreams.phototable
  com.android.htmlviewer
  com.android.printspooler
  com.android.wallpaper.livepicker
```

The generic tool raises confidence for L2 package-group pruning. It does not
remove framework AssetManager locales and therefore does not by itself produce
an English/Chinese-only system language universe.

## Framework-Res L3 Probe

The next offline probe is:

```text
tools/r2-build-framework-res-locale-probe.sh
```

Modes:

```text
noop:
  rebuild framework-res.apk without source edits, merge only resources.arsc into
  the stock APK shell, and verify that public.xml remains stable after decoding
  the merged output.

locale-prune:
  remove non-English/non-Chinese framework-res locale values dirs and narrow
  framework locale arrays.
```

Verified outputs:

```text
mode:
  noop
output:
  hard-rom/build/apk/framework-res-rebuild-noop.apk
sha256:
  319cd91f8a29c88e8c1058a15bdcd2fbd159a82107add92daf87cbd40fd4240a
result:
  AndroidManifest.xml remains byte-identical to stock
  public.xml diff after decode/rebuild is empty
  resources.arsc is rebuilt, stock size 4377436 bytes -> output size 4349908
  expected signature boundary: SHA-256 digest error for resources.arsc
```

```text
mode:
  locale-prune
output:
  hard-rom/build/apk/framework-res-locale-prune-en-zh.apk
sha256:
  10fc36befd0acdb1a1530c6e676cc154170de1bebac5d7eb84b73c24f164aedd
resource result:
  removed 61 non-English/non-Chinese framework-res locale resource dirs,
  including raw-ja/raw-ko
  kept 63 English/Chinese locale resource dirs
  decoded merged output has no non-target locale resource dirs
  binary resources.arsc policy check reports languages=en,zh and
  bad_locale_chunk_count=0
array result:
  supported_locales=en-US,zh-Hans-CN,zh-Hant-TW
  special_locale_codes=zh_CN,zh_TW
equivalence:
  AndroidManifest.xml remains byte-identical to stock
  public.xml diff after decode/rebuild is empty
  resources.arsc stock size 4377436 bytes -> output size 3518900
signature boundary:
  keytool_status=1
  SHA-256 digest error for resources.arsc
```

This is the strongest evidence so far that the `framework-res.apk` side of a
true language hard prune is mechanically controllable offline. It is still not
a boot proof. `framework-res.apk` remains an early-boot RED system asset.

Remaining full-prune blockers:

```text
framework-smartisanos-res.apk:
  normal apktool/aapt2 rebuild still fails because aapt2 cannot link
  Smartisan's synthetic ^attr-private type id 0x0b
  binary resources.arsc locale-config pruning now works offline

package groups:
  the generic APK locale-prune tool can handle ordinary APK resources, but each
  package group still needs package-manager, signature, and boot validation

live boot:
  no framework-res replacement has been flashed or live-verified
```

## Smartisan Framework-Res L3 Probe

`framework-smartisanos-res.apk` has only four locale directories:

```text
values-ja
values-ko
values-zh-rCN
values-zh-rTW
```

A normal raw rebuild still fails:

```text
aapt2 error:
  no definition for declared symbol
  smartisanos:^attr-private/backgroundShadow
  smartisanos:^attr-private/backgroundStyle
  smartisanos:^attr-private/itemSwitchTitleColor
  smartisanos:^attr-private/shadowButtonStyle
  smartisanos:^attr-private/shadowColors

public IDs:
  0x020b0000..0x020b0004
```

The safe offline route is not aapt2 rebuild. It is binary `resources.arsc`
config-chunk pruning:

```text
tools/r2-arsc-prune-locales.py
tools/r2-build-smartisanos-framework-res-locale-probe.sh
```

Verified output:

```text
output:
  hard-rom/build/apk/framework-smartisanos-res-locale-prune-en-zh.apk
sha256:
  eefab348089210bba963c69f5966052a65b11fdd1bf198084c60cc005a45b228
stock APK sha256:
  121a762867be00a65c3781e30c6d14f44ffe64f0f1281b75d90589a8289ebe42
stock resources.arsc sha256:
  b81a5517d5bc048b53ba14ca9b6981bb1534285d143f2982682dc11338a816ce
pruned resources.arsc sha256:
  3b814e36fe1f614aecefb19376713cd0272bc67aae5b70270f261e45aafc2628
```

Removed chunks:

```text
string ja
string ko
dimen ja
array ja
array ko
integer ja
```

Verification:

```text
decoded merged output has no values-ja or values-ko dirs
values-zh-rCN and values-zh-rTW remain
AndroidManifest.xml remains byte-identical to stock
public.xml diff is 0 bytes
^attr-private public IDs remain 0x020b0000..0x020b0004 after decode
signature boundary is the expected resources.arsc digest error
```

This completed the offline APK-level mechanical side of framework
language-resource pruning for both framework resource APKs. It did not by
itself prove boot safety.

## v0.10 Framework/Product ROM Candidate

The first combined framework/product hard-ROM language-prune candidate is:

```text
build script:
  tools/r2-hardrom-build-v0.10-framework-locale-prune.sh
verify script:
  tools/r2-verify-v0.10-framework-locale-prune.sh
baseline:
  v0.4 hard debloat exact-current super
patched partitions:
  system_b
  product_b
```

Inserted system_b APKs:

```text
/system/framework/framework-res.apk
  hard-rom/build/apk/framework-res-locale-prune-en-zh.apk
  sha256=10fc36befd0acdb1a1530c6e676cc154170de1bebac5d7eb84b73c24f164aedd

/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
  hard-rom/build/apk/framework-smartisanos-res-locale-prune-en-zh.apk
  sha256=eefab348089210bba963c69f5966052a65b11fdd1bf198084c60cc005a45b228
```

Inserted product_b static overlays:

```text
/overlay/DisplayCutoutEmulationCorner/DisplayCutoutEmulationCornerOverlay.apk
  sha256=5a129a160840a85e60414cceb6660f4b9f2f70ff3e696ab76ad8ed82cffecac9
/overlay/DisplayCutoutEmulationDouble/DisplayCutoutEmulationDoubleOverlay.apk
  sha256=8a9297b28103bac5e8fbe213dab7c343da7ad51b6a35eaedde1e0ced82a3c9c7
/overlay/DisplayCutoutEmulationHole/DisplayCutoutEmulationHoleOverlay.apk
  sha256=267f087749a9d4c39c67beb7ed914c1822bca753c13ee6ad00de87631a965d50
/overlay/DisplayCutoutEmulationTall/DisplayCutoutEmulationTallOverlay.apk
  sha256=43e0bac75c2ae20fb923182cb29e6a23982828c8e58ca45437e6f513c35e55de
/overlay/DisplayCutoutEmulationWaterfall/DisplayCutoutEmulationWaterfallOverlay.apk
  sha256=a0658eef1eba44150fb0d3d8085fd58feb6260c8139498788af24e07e9c1ae7e
```

Output:

```text
super sparse:
  hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
  sha256=62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
system image:
  hard-rom/build/system-otatrust-v0.10-framework-locale-prune.img
  sha256=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351
product image:
  hard-rom/build/product-otatrust-v0.10-framework-locale-prune.img
  sha256=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2
```

Important ext4 lesson:

```text
system/product ext4 images use shared_blocks.
Do not replace files with debugfs rm + write on these images.
That can free shared blocks from the old inode, let a new APK reuse them, and
then let e2fsck repair the conflict by corrupting the new APK payload.

v0.10 uses:
  1. hard-link old inode to a hidden non-.apk stock-held path
  2. write new APK to a temporary hidden path
  3. unlink the public old path
  4. link the temporary inode to the public path
  5. unlink the temporary path

This keeps the stock inode referenced and avoids freeing shared blocks.
```

Offline verification:

```text
tools/r2-verify-v0.10-framework-locale-prune.sh --offline-image
  PASS
report:
  hard-rom/inspect/v0.10-framework-locale-prune/verify-v0.10-offline-image-20260618-071729.txt

checks:
  expected resources.arsc signature boundary for all seven APKs
  framework-res and framework-smartisanos-res dumped from system image match
    expected hashes
  all five DisplayCutout overlay APKs dumped from product image match expected
    hashes
  all seven dumped APK resources.arsc files pass
    tools/r2-verify-apk-locale-policy.py --keep-languages en,zh
  sparse super system_b/product_b logical slices match the generated
    system/product images
  post-fsck replacement hashes and ZIP integrity are also enforced during build
```

Status:

```text
v0.10 is a RED early-boot framework resource candidate.
It has not been flashed or live-verified.
Flash only after explicit user confirmation and rollback readiness.
```
