# Locale Prune Coverage Audit

Date: 2026-06-18.

This read-only audit measures Japanese/Korean locale-resource coverage
against the current hard-ROM route. It does not modify APKs, images,
partitions, the live device, or `/data`.

## Scope Boundary

- Baseline removal state: v0.2 no-appstore plus v0.4 hard debloat.
- Resource hard-prune coverage: v0.10 framework/product candidate,
  v0.13 Tier1a system_b image candidate, v0.17a system APK-only
  promotion image candidate, and v0.17b product/system_ext APK-only
  promotion image candidate.
- v0.13 is counted as system-image coverage only; its flashable sparse
  super has not been built or live-tested. v0.17a has a flashable
  sparse super but still has not been live-tested. v0.17b, v0.22, and v0.24
  also have flashable sparse supers but still have not been live-tested.
- Remaining APK-only locale-prune outputs are listed as offline evidence
  but are not counted as ROM hard-prune coverage until a matching image exists.
- Visible language filtering: v0.7 SettingsSmartisan candidate, counted
  separately because it does not remove APK resources.
- TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv`

## Summary

- stock static ROM packages with ja/ko resources: 175
- stock ja/ko values-dir count: 509
- covered by deletion or v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 hard-prune candidates: 40 packages, 141 dirs
- visible-filter only, not resource-pruned: 1 packages, 6 dirs
- remaining APK-only built offline, not in ROM coverage: 0 packages, 0 dirs
- remaining hard-prune work: 134 packages, 362 dirs

Coverage by status:

- pruned_in_v0.10_candidate: 7 packages, 71 dirs
- pruned_in_v0.13_system_image: 3 packages, 6 dirs
- pruned_in_v0.17a_system_image: 5 packages, 10 dirs
- pruned_in_v0.17b_product_system_ext_image: 2 packages, 4 dirs
- pruned_in_v0.22_all_system_image: 3 packages, 6 dirs
- pruned_in_v0.24_system_image: 1 packages, 2 dirs
- remaining_after_v0.4_v0.10: 134 packages, 362 dirs
- removed_in_v0.2_v0.4: 19 packages, 42 dirs
- visible_filter_only_v0.7: 1 packages, 6 dirs

v0.13 system-image hard-prune batch:

| ja/ko dirs | package | path | status |
| ---: | --- | --- | --- |
| 2 | com.android.hotspot2.osulogin | `system/system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk` | resources.arsc hard-pruned in v0.13 Tier1a system_b image; flashable sparse super not built |
| 2 | com.android.printservice.recommendation | `system/system/app/PrintRecommendationService/PrintRecommendationService.apk` | resources.arsc hard-pruned in v0.13 Tier1a system_b image; flashable sparse super not built |
| 2 | com.android.protips | `system/system/app/Protips/Protips.apk` | resources.arsc hard-pruned in v0.13 Tier1a system_b image; flashable sparse super not built |

Remaining work by risk tier:

- AMBER_PRIV_APP: 38 packages, 124 dirs
- AMBER_SHARED_UID: 18 packages, 44 dirs
- GREEN_OR_YELLOW_APP: 35 packages, 79 dirs
- RED_CORE_APP: 24 packages, 74 dirs
- RED_SHARED_UID: 19 packages, 41 dirs

Remaining work by next frontier:

- amber_requires_package_gate: 56 packages, 168 dirs
- defer_green_coupled_or_large_locale_table: 25 packages, 59 dirs
- red_requires_core_gate: 43 packages, 115 dirs
- tier1_small_green_apk_resource_prune: 10 packages, 20 dirs

Tier1 package-gate split:

- tier1c_needs_extra_package_review: 10 packages, 20 dirs

## Next Safe Frontier

The safest next offline frontier is small GREEN/YELLOW APK resource
pruning, not core shared-UID or framework work. These are APK-level
resources.arsc candidates only; a built APK still does not authorize
flashing.

| ja/ko dirs | package | path | note |
| ---: | --- | --- | --- |
| 2 | com.android.bips | `system/system/app/BuiltInPrintService/BuiltInPrintService.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.android.carrierdefaultapp | `system/system/app/CarrierDefaultApp/CarrierDefaultApp.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.android.egg | `system/system/app/EasterEgg/EasterEgg.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.android.exchange | `system/system/app/Exchange2/Exchange2.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.qualcomm.qti.simcontacts | `system_ext/app/SimContact/SimContact.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.smartisanos.bug2go | `system/system/app/SMTBugreport/SMTBugreport.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.smartisanos.filepreview | `system/system/app/FilePreviewSmartisan/FilePreviewSmartisan.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.smartisanos.gamespeedup | `system/system/app/GameSpeedUp/GameSpeedUp.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.smartisanos.nodisturb | `system/system/app/NoDisturb/NoDisturb.apk` | still needs delete, APK resource prune, or deeper gate |
| 2 | com.smartisanos.setupwizard | `system/system/app/SetupWizard/SetupWizard.apk` | still needs delete, APK resource prune, or deeper gate |

## Best First APK Resource-Prune Probes

These candidates are still same-package APK replacements, so they are
offline probes until a ROM image and flash are explicitly authorized.
The v0.13 batch consumed the last `tier1a_minimal_exposure` packages,
so the next safe frontier is review-gated rather than fully automatic.

| gate | score | ja/ko dirs | package | components | exported | providers | core intents | permissions | reason | path |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| tier1c_needs_extra_package_review | 41 | 2 | com.android.carrierdefaultapp | 4 | 1 | 0 | 3 | 8 | extra review: 1 exported components; 3 core intent entries; 8 requested permissions; 4 components | `system/system/app/CarrierDefaultApp/CarrierDefaultApp.apk` |
| tier1c_needs_extra_package_review | 43 | 2 | com.smartisanos.filepreview | 1 | 1 | 0 | 1 | 5 | extra review: package-index status is recoverable-errors; 1 exported components; 1 core intent entries; 5 requested permissions | `system/system/app/FilePreviewSmartisan/FilePreviewSmartisan.apk` |
| tier1c_needs_extra_package_review | 44 | 2 | com.android.bips | 6 | 2 | 0 | 0 | 15 | extra review: 2 exported components; 15 requested permissions; 6 components | `system/system/app/BuiltInPrintService/BuiltInPrintService.apk` |
| tier1c_needs_extra_package_review | 66 | 2 | com.qualcomm.qti.simcontacts | 7 | 2 | 0 | 2 | 4 | extra review: package-index status is recoverable-errors; 2 exported components; 2 core intent entries; 7 components | `system_ext/app/SimContact/SimContact.apk` |
| tier1c_needs_extra_package_review | 70 | 2 | com.smartisanos.nodisturb | 14 | 3 | 1 | 0 | 11 | extra review: 3 exported components; 1 providers; 11 requested permissions; 14 components | `system/system/app/NoDisturb/NoDisturb.apk` |
| tier1c_needs_extra_package_review | 74 | 2 | com.smartisanos.gamespeedup | 6 | 2 | 1 | 0 | 15 | extra review: package-index status is recoverable-errors; 2 exported components; 1 providers; 15 requested permissions; 6 components | `system/system/app/GameSpeedUp/GameSpeedUp.apk` |
| tier1c_needs_extra_package_review | 90 | 2 | com.smartisanos.setupwizard | 11 | 4 | 0 | 2 | 20 | extra review: 4 exported components; 2 core intent entries; 20 requested permissions; 11 components | `system/system/app/SetupWizard/SetupWizard.apk` |
| tier1c_needs_extra_package_review | 123 | 2 | com.android.exchange | 11 | 5 | 1 | 0 | 23 | extra review: package-index status is recoverable-errors; 5 exported components; 1 providers; 23 requested permissions; 11 components | `system/system/app/Exchange2/Exchange2.apk` |
| tier1c_needs_extra_package_review | 149 | 2 | com.smartisanos.bug2go | 36 | 3 | 2 | 1 | 32 | extra review: package-index status is recoverable-errors; 3 exported components; 2 providers; 1 core intent entries; 32 requested permissions; 36 components | `system/system/app/SMTBugreport/SMTBugreport.apk` |
| tier1c_needs_extra_package_review | 150 | 2 | com.android.egg | 9 | 7 | 1 | 4 | 4 | extra review: package-index status is recoverable-errors; 7 exported components; 1 providers; 4 core intent entries; 9 components | `system/system/app/EasterEgg/EasterEgg.apk` |

## Important Deferrals

- `visible_filter_only_v0.7` is not counted as hard-pruned. It proves the
  Settings language picker can hide ja/ko, but resources remain in the APK.
- Browser/WebView/input/launcher/security-adjacent packages are deferred even
  if their static risk label is GREEN/YELLOW.
- AMBER packages need package-level gates before build.
- RED packages need core shared-UID/framework live gates before behavior or
  resource replacement.

## Top Remaining Packages

| frontier | risk | ja/ko dirs | package | path |
| --- | --- | ---: | --- | --- |
| amber_requires_package_gate | AMBER_PRIV_APP | 36 | com.android.cellbroadcastreceiver.module | `system/system/apex/com.android.cellbroadcast/priv-app/CellBroadcastApp/CellBroadcastApp.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.android.launcher3 | `system/system/priv-app/LauncherOrigSmartisan/LauncherOrigSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.smartisanos.clock | `system/system/priv-app/ClockSmartisan/ClockSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.smartisanos.desktop | `system/system/priv-app/Desktop/Desktop.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.smartisanos.expandservice | `system/system/priv-app/SmartisanExpandService/SmartisanExpandService.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.smartisanos.launcher | `system/system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.smartisanos.powersaving.launcher | `system/system/priv-app/PowerSavingLauncher/PowerSavingLauncher.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 4 | com.smartisanos.wallet | `system/system/priv-app/WalletSmartisan/WalletSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.apps.tag | `system/system/priv-app/Tag/Tag.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.backupconfirm | `system/system/priv-app/BackupRestoreConfirmation/BackupRestoreConfirmation.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.calendar | `system/system/priv-app/CalendarSmartisan/CalendarSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.cellbroadcastreceiver | `system/system/priv-app/CellBroadcastLegacyApp/CellBroadcastLegacyApp.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.documentsui | `system/system/priv-app/DocumentsUI/DocumentsUI.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.externalstorage | `system/system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.managedprovisioning | `system/system/priv-app/ManagedProvisioning/ManagedProvisioning.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.mms | `system/system/priv-app/MmsSmartisan/MmsSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.musicfx | `system/system/priv-app/MusicFX/MusicFX.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.providers.media.module | `system/system/apex/com.android.mediaprovider/priv-app/MediaProvider/MediaProvider.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.settings.intelligence | `product/priv-app/SettingsIntelligence/SettingsIntelligence.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.storagemanager | `system_ext/priv-app/StorageManager/StorageManager.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.wallpapercropper | `system_ext/priv-app/WallpaperCropper/WallpaperCropper.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.android.wifiauthorize | `system_ext/priv-app/WifiAuthorize/WifiAuthorize.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.qti.ltebc | `system_ext/priv-app/QAS_DVC_MSP/QAS_DVC_MSP.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.qualcomm.location | `system_ext/priv-app/com.qualcomm.location/com.qualcomm.location.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.cloudagent | `system/system/priv-app/CloudSyncAgent/CloudSyncAgent.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.cloudsync | `system/system/priv-app/CloudServiceSmartisan/CloudServiceSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.cloudsyncshare | `system/system/priv-app/CloudServiceShare/CloudServiceShare.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.manual | `system/system/priv-app/SmartisanShareManual/SmartisanShareManual.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.music | `system/system/priv-app/MusicPlayer/MusicPlayer.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.numberassistant | `system/system/priv-app/NumberAssistant/NumberAssistant.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.sara | `system/system/priv-app/VoiceAssistant/VoiceAssistant.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.screenrecorder | `system/system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.smartisanbrain | `system/system/priv-app/SmartisanBrain/SmartisanBrain.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.smsparser | `system/system/priv-app/SmsParser/SmsParser.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.teatracker | `system/system/priv-app/TeaTracker/TeaTracker.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.updater | `system/system/priv-app/SmartisanUpdater/SmartisanUpdater.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.videoplayerproject | `system/system/priv-app/VideoPlayer/VideoPlayer.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 2 | com.smartisanos.whiteboard | `system/system/priv-app/WhiteBoardSmartisan/WhiteBoardSmartisan.apk` |
| amber_requires_package_gate | AMBER_SHARED_UID | 6 | com.android.contacts | `system/system/priv-app/ContactsSmartisan/ContactsSmartisan.apk` |
| amber_requires_package_gate | AMBER_SHARED_UID | 6 | com.android.networkstack.tethering | `system/system/apex/com.android.tethering/priv-app/Tethering/Tethering.apk` |
