# Language Prune Integration Map

Date: 2026-06-18.

Purpose:

```text
Define the end-to-end route for making Smartisan OS 8.5.3 expose only English,
Simplified Chinese, and Traditional Chinese as system languages while pruning
non-English/non-Chinese ROM language resources without breaking boot, resource
fallback, telephony/SIM locale handling, Settings, Launcher, Keyguard, or
PackageManager.
```

Boundary:

```text
This document is source analysis and implementation planning. It is not live
proof. The current ROM is not English/Chinese-only: coverage audit still reports
remaining non-English/non-Chinese resources outside deletion or hard-prune
coverage.
```

## Policy

User-visible system language choices:

```text
English
Simplified Chinese
Traditional Chinese
```

Implementation targets:

```text
visible locale list:
  en-US
  zh-Hans-CN
  zh-Hant-TW

first-stage resource retention:
  keep all en* and zh* compiled resource configs
  remove non-English/non-Chinese configs such as ja*, ko*, ar*, de*, fr*, etc.
```

Why resource retention is broader than the visible list:

```text
Chinese resource fallback may use region/script variants such as zh-rCN,
zh-rTW, or zh-rHK. The user's requested language family is English/Chinese, so
the safe first hard-prune policy is language-family based: keep en and zh,
remove everything else. Region-level Chinese narrowing can be considered only
after the family-level route is live-proven.
```

## Completion Requirements

The language goal is not complete until all of these are true:

```text
1. Settings visible language picker offers only English, Simplified Chinese,
   and Traditional Chinese.
2. AOSP locale paths are consistent with the same visible policy.
3. framework-res.apk supported_locales is narrowed to the target visible set.
4. Resources.getSystem().getAssets().getLocales() no longer exposes
   non-English/non-Chinese framework or android-overlay locale configs.
5. All retained ROM APK/resource packages either have no non-English/non-Chinese
   resource chunks or are explicitly documented as deferred/unchanged.
6. App-level resource fallback still works for English and Chinese.
7. Telephony/SIM/MCC locale helpers fall back safely after non-target locales
   are removed.
8. Updated-system packages under /data/app do not override the pruned ROM copy.
9. Boot, Keyguard, Launcher, Settings, PackageManager, root, and logcat checks
   pass after each live gate.
10. Rollback image and recovery path are ready before every flash.
```

## Source Chain

Smartisan visible language picker:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  reads Resources.getSystem().getAssets().getLocales()
  sorts raw locale strings
  keeps regioned entries where str.length() == 5
  creates Locale(language, country)
```

Implication:

```text
Filtering only android.R.array.supported_locales is insufficient for the main
Smartisan language picker. v0.7's SettingsSmartisan code filter can hide ja_JP
and ko_KR visually, but it does not physically remove resources.
```

AOSP locale picker:

```text
com.android.internal.app.LocalePicker
  getSystemAssetLocales() -> Resources.getSystem().getAssets().getLocales()
  getSupportedLocales(context) -> R.array.supported_locales
```

Implication:

```text
Both raw AssetManager locales and supported_locales arrays matter. A complete
route needs framework resource pruning plus array narrowing.
```

System AssetManager:

```text
AssetManager.createSystemAssetsInZygoteLocked()
  loads /system/framework/framework-res.apk
  loads /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
  loads immutable framework idmaps from OverlayConfig
```

Implication:

```text
To remove ja/ko from the global system asset universe, framework-res,
framework-smartisanos-res, and android-targeting static overlays must be handled
behind framework live gates.
```

Per-package resources:

```text
ResourcesManager.createAssetManager(ResourcesKey)
  adds package resDir
  adds split resource dirs
  adds lib resource dirs
  adds overlay idmaps

ResourcesImpl.updateConfiguration()
  uses mAssets.getNonSystemLocales()
  falls back to mAssets.getLocales()
  picks a best locale with English support
```

Implication:

```text
Framework pruning does not remove package-local ja/ko resources. App-level APK
resource pruning must proceed package by package, with fallback verification.
```

Non-UI locale users:

```text
MccTable.getLocaleForLanguageCountry()
  checks context.getAssets().getLocales()

IccRecords.setSimLanguage()
  checks this.mContext.getAssets().getLocales()

RuimRecords.getAssetLanguages()
  checks context.getAssets().getLocales()
```

Implication:

```text
Validation cannot stop at the visible Settings picker. SIM/MCC language helpers
must continue to fall back into English/Chinese after non-target locales are
removed.
```

## Existing Candidates

Visible list gate:

```text
v0.7-locale-filter
  SettingsSmartisan LocalePickerFragment skips ja_JP and ko_KR.
  APK semantics are proven offline.
  Requires v0.6 SettingsSmartisan no-op live gate before flash.
```

Framework/global asset gate:

```text
v0.12-framework-res-noop
  proves framework-res replacement can boot before language behavior is tested.
  Built and offline-verified; not live-verified.

v0.10-framework-locale-prune
  framework-res + framework-smartisanos-res + five android static overlays.
  Narrows supported_locales and removes non-English/non-Chinese framework
  resource chunks.
  Built and offline-verified; RED early-boot candidate.
  Must wait for v0.12 live pass.
```

App-level resource gate:

```text
v0.13-tier1a-locale-prune
  Protips, PrintRecommendationService, OsuLogin.
  system_b image built and offline-verified.
  Sparse super not built yet.

APK-only candidates
  BasicDreams, PhotoTable, HTMLViewer, PrintSpooler, LiveWallpapersPicker,
  ConferenceDialer, SimAppDialog, CompanionDeviceManager,
  SmartisanShareBrowser, and TrackerSmartisan.
  APK-only verifiers pass. The seven v0.17-promoted candidates are ROM coverage
  in v0.17-all, and CompanionDeviceManager, SmartisanShareBrowser, and
  TrackerSmartisan are ROM coverage in the v0.22 combined sparse. None of these
  are live proof until flashed and boot-verified.
```

## Live-State Audit Requirements

Before choosing a live language migration or claiming a language build works,
capture these facts read-only:

```text
adb state
sys.boot_completed
ro.boot.slot_suffix
persist.sys.locale
persist.sys.language
persist.sys.country
ro.product.locale*
am get-config or cmd activity get-config output
dumpsys activity configuration snippets
Settings.System/Secure/Global system_locales if present
current input method and selected subtype
package paths for SettingsSmartisan, SettingsProvider, framework-adjacent
packages, and language-prune candidates
whether any target package currently resolves to /data/app instead of ROM
current window/keyguard focus
recent logs for LocalePicker, AssetManager, ResourcesImpl, PackageManager,
SettingsProvider, MccTable, IccRecords, and RuimRecords
```

The updated-system package check matters because a ROM-pruned APK under
`/system`, `/product`, or `/system_ext` can be shadowed by an updated package
under `/data/app`.

## Recommended Stage Order

```text
Stage L0: Capture read-only language live-state on stable v0.4.
Stage L1: Flash and verify v0.6 SettingsSmartisan no-op.
Stage L2: Flash and verify v0.7 visible-language filter.
Stage L3: Flash and verify v0.12 framework-res no-op.
Stage L4: Flash and verify v0.10 framework/product language prune.
Stage L5: Build v0.13 sparse super and verify offline before any flash.
Stage L6: Promote APK-only candidates into ROM images in small batches.
Stage L7: Repeat coverage audit until no non-English/non-Chinese ROM resource
          packages remain outside deletion or verified hard-prune coverage.
```

Stage ordering can be interleaved for safety, but claims must stay precise:

```text
v0.7 proves visible Settings filtering only.
v0.10 proves framework/product resource hard-prune only after v0.12 live gate.
v0.13, v0.17a, and v0.17b package images prove package resource pruning only
for their own packages; v0.17a and v0.17b are separate v0.4-based sparse
candidates until a combined v0.17-all image is built.
Full ROM language completion requires all retained packages to pass coverage.
```

## Next Batch Plan

The current executable batch plan is:

```text
tools/r2-language-next-batch-plan.py
tools/r2-language-p1-source-review-audit.py
docs/research/language-next-batch-plan.md
docs/research/language-p1-source-review-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-next-batch-plan.tsv
reverse/smartisan-8.5.3-rom-static/manifest/language-p1-source-review-audit.tsv
```

Current staging result:

```text
P0a_rebuild_v013_tier1a_stored: 3 packages / 6 dirs
P1_build_small_apk_only: 11 packages / 22 dirs
P2_build_green_full_language_apk_only: 22 packages / 1555 dirs
P3_deferred_green_coupled: 5 packages / 161 dirs
P4_amber_package_gate: 56 packages / 1840 dirs
P5_red_core_gate: 45 packages / 1098 dirs
```

Interpretation:

```text
The next ROM-language move should not pick randomly from 142 remaining
packages. First rebuild stale v0.13 image inputs with current STORED APKs,
then decide whether a single v0.17-all flash target is needed to combine the
already built v0.17a system image with the v0.17b product/system_ext image.
The current APK-only promotion queue has com.android.companiondevicemanager and
com.smartisanos.share.browser. New APK-only work should start with the P1
source-review result: the remaining 12 P1 rows are deferred behind
package-specific source/graph review. High-yield P2 rows remove many more
resource dirs, but their package coupling must be reviewed before build.
P4/P5 rows remain behind explicit gates.
```

## Current Confidence

```text
We understand the source chain well enough to implement and stage the language
route. We are not done: v0.12/v0.10 live framework gates are missing, v0.13
still lacks a flashable sparse super after cleanup, v0.17a/v0.17b have offline
ROM-image coverage but no live boot proof, and the full-prune coverage audit
reports 142 packages / 4682 non-English/non-Chinese dirs outside current ROM coverage.
The older ja/ko subset remains useful as a staged metric, but it is not the
full English/Chinese-only target.
```
