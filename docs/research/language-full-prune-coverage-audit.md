# Full English/Chinese Language Prune Coverage Audit

Date: 2026-06-18.

This read-only audit measures the full ROM language-prune target:
keep `en*` and `zh*` resource configurations and remove every other
compiled language configuration. It does not modify APKs, images,
partitions, the live device, or `/data`.

## Scope Boundary

- This is stricter than the older ja/ko coverage audit.
- `non_target_dirs = ja_ko_dirs + other_locale_dirs`, recomputed by scanning decoded resource directories.
- v0.10, v0.13, v0.17a, v0.17b, v0.22, and v0.24 are counted as offline image candidates, not live proof.
- Remaining APK-only candidates are listed but not counted as ROM coverage until promoted.
- TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv`

## Summary

- stock static ROM packages with non-English/non-Chinese resources: 179
- stock non-English/non-Chinese values-dir count: 5650
- ja/ko subset: 515 dirs
- other non-target languages: 5135 dirs
- covered by deletion or v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 hard-prune candidates: 40 packages, 895 dirs
- visible-filter only, not resource-pruned: 1 packages, 81 dirs
- remaining APK-only built offline, not in ROM coverage: 0 packages, 0 dirs
- remaining full language-prune work: 138 packages, 4674 dirs

Coverage by status:

- pruned_in_v0.10_candidate: 7 packages, 73 dirs
- pruned_in_v0.13_system_image: 3 packages, 6 dirs
- pruned_in_v0.17a_system_image: 5 packages, 85 dirs
- pruned_in_v0.17b_product_system_ext_image: 2 packages, 4 dirs
- pruned_in_v0.22_all_system_image: 3 packages, 6 dirs
- pruned_in_v0.24_system_image: 1 packages, 2 dirs
- remaining_after_current_candidates: 138 packages, 4674 dirs
- removed_in_v0.2_v0.4: 19 packages, 719 dirs
- visible_filter_only_v0.7: 1 packages, 81 dirs

Remaining work by next frontier:

- amber_requires_package_gate: 56 packages, 1840 dirs
- defer_green_coupled_or_large_locale_table: 5 packages, 161 dirs
- red_requires_core_gate: 45 packages, 1098 dirs
- tier1_small_green_apk_resource_prune: 10 packages, 20 dirs
- tier2_green_full_language_prune: 22 packages, 1555 dirs

## Important Result

The current ROM language work is not close to full English/Chinese-only
physical pruning yet. The ja/ko subset is only a small part of the real
target. Large non-target language tables remain in apps such as Contacts,
BrowserChrome, TalkBack, Calendar, LatinIME, SettingsSmartisan, Launcher,
and many OEM apps. Those packages need separate risk gates.

## Best Full-Language Green Frontiers

These are GREEN/YELLOW packages that are not on the known deferral list.
They are ranked by low exposure score first, then by larger non-target
directory removal. They still need package-specific review and ROM image
promotion before any flash.

| exposure_gate | exposure_score | non_target_dirs | ja_ko_dirs | other_locale_dirs | package | partition | rel_path | exposure_reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| needs_extra_package_review | 15 | 1 | 0 | 1 | com.qualcomm.embms | system_ext | `app/embms/embms.apk` | 1 exported components |
| needs_extra_package_review | 31 | 1 | 0 | 1 | com.qualcomm.qti.qccauthmgr | system_ext | `app/QCC-AUTHMGR/QCC-AUTHMGR.apk` | 1 exported components; 1 providers; 1 core intent entries; 2 components |
| needs_extra_package_review | 34 | 79 | 4 | 75 | com.smartisanos.keymapping | system | `system/app/KeyMapping/KeyMapping.apk` | 1 exported components; 1 providers; 10 requested permissions; 3 components |
| needs_extra_package_review | 52 | 77 | 2 | 75 | com.smartisan.unionpush.proxy | system | `system/app/UnionPushProxy/UnionPushProxy.apk` | 3 exported components; 1 core intent entries; 8 requested permissions; 3 components |
| needs_extra_package_review | 54 | 75 | 2 | 73 | com.bytedance.wirelesscast | system | `system/app/SmartisanWirelessCast/SmartisanWirelessCast.apk` | package-index status is recoverable-errors; 1 exported components; 18 requested permissions; 5 components |
| needs_extra_package_review | 58 | 77 | 2 | 75 | com.smartisan.table.setupwizard | system | `system/app/TableSetupWizard/TableSetupWizard.apk` | package-index status is recoverable-errors; 2 exported components; 9 requested permissions; 6 components |
| needs_extra_package_review | 69 | 75 | 2 | 73 | com.smartisanos.previewer | system | `system/app/FilePreviewerSmartisan/FilePreviewerSmartisan.apk` | package-index status is recoverable-errors; 1 exported components; 1 providers; 2 core intent entries; 14 requested permissions; 2 components |
| needs_extra_package_review | 70 | 78 | 3 | 75 | com.smartisanos.weather | system | `system/app/WeatherSmartisan/WeatherSmartisan.apk` | package-index status is recoverable-errors; 1 exported components; 2 core intent entries; 21 requested permissions; 6 components |
| needs_extra_package_review | 75 | 77 | 2 | 75 | com.smartisan.smpush | system | `system/app/SMPushService/SMPushService.apk` | 3 exported components; 1 providers; 1 core intent entries; 16 requested permissions; 8 components |
| needs_extra_package_review | 80 | 86 | 2 | 84 | com.smartisanos.smartfolder.aoa | system | `system/app/HandShaker/HandShaker.apk` | package-index status is recoverable-errors; 1 exported components; 1 providers; 2 core intent entries; 14 requested permissions; 13 components |
| needs_extra_package_review | 96 | 77 | 2 | 75 | com.android.providers.weather | system | `system/app/WeatherProvider/WeatherProvider.apk` | package-index status is recoverable-errors; 2 exported components; 2 providers; 2 core intent entries; 15 requested permissions; 6 components |
| needs_extra_package_review | 99 | 79 | 4 | 75 | com.android.camera2 | system | `system/app/CameraSmartisan3/CameraSmartisan3.apk` | package-index status is recoverable-errors; 1 exported components; 1 providers; 3 core intent entries; 22 requested permissions; 18 components |
| needs_extra_package_review | 107 | 77 | 2 | 75 | com.smartisanos.hearingaid | system | `system/app/HearingAid/HearingAid.apk` | package-index status is recoverable-errors; 2 exported components; 1 providers; 4 core intent entries; 20 requested permissions; 10 components |
| needs_extra_package_review | 129 | 77 | 2 | 75 | com.smartisanos.textboom | system | `system/app/TextBoom/TextBoom.apk` | package-index status is recoverable-errors; 1 exported components; 2 providers; 2 core intent entries; 48 requested permissions; 18 components |
| needs_extra_package_review | 151 | 79 | 4 | 75 | com.smartisanos.boston.phone | system | `system/app/BostonScreenMirror/BostonScreenMirror.apk` | package-index status is recoverable-errors; 4 exported components; 1 providers; 2 core intent entries; 40 requested permissions; 22 components |
| needs_extra_package_review | 178 | 80 | 4 | 76 | com.smartisanos.magicflow | system | `system/app/MagicFlow/MagicFlow.apk` | package-index status is recoverable-errors; 3 exported components; 4 providers; 46 requested permissions; 37 components |
| needs_extra_package_review | 178 | 75 | 2 | 73 | com.smartisan.crashreport | system | `system/app/CrashReport/CrashReport.apk` | 11 exported components; 2 core intent entries; 20 requested permissions; 15 components |
| needs_extra_package_review | 239 | 77 | 2 | 75 | com.smartisanos.quicksearch | system | `system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk` | package-index status is recoverable-errors; 6 exported components; 5 providers; 5 core intent entries; 54 requested permissions; 14 components |
| needs_extra_package_review | 270 | 77 | 2 | 75 | com.smartisanos.filemanager | system | `system/app/FileManagerSmartisan/FileManagerSmartisan.apk` | package-index status is recoverable-errors; 7 exported components; 7 providers; 6 core intent entries; 37 requested permissions; 24 components |
| needs_extra_package_review | 301 | 77 | 2 | 75 | com.redteamobile.global.roaming | vendor | `app/Redtea-app/Redtea-app.apk` | package-index status is recoverable-errors; 13 exported components; 3 providers; 6 core intent entries; 19 requested permissions; 41 components |
| needs_extra_package_review | 425 | 77 | 2 | 75 | com.android.gallery3d | system | `system/app/GallerySmartisan/GallerySmartisan.apk` | package-index status is recoverable-errors; 15 exported components; 5 providers; 13 core intent entries; 47 requested permissions; 51 components |
| needs_extra_package_review | 630 | 77 | 2 | 75 | com.smartisanos.security | system | `system/app/PermissionManager/PermissionManager.apk` | package-index status is recoverable-errors; 24 exported components; 6 providers; 25 core intent entries; 63 requested permissions; 50 components |

## APK-Only Offline Candidates

| non_target_dirs | package | apk_only_variant | apk_only_apk | apk_only_sha256 | coverage_note |
| --- | --- | --- | --- | --- | --- |

## Top Remaining Packages

| next_frontier | risk | non_target_dirs | ja_ko_dirs | other_locale_dirs | package | partition | rel_path |
| --- | --- | --- | --- | --- | --- | --- | --- |
| amber_requires_package_gate | AMBER_SHARED_UID | 188 | 8 | 180 | com.android.contacts | system | `system/priv-app/ContactsSmartisan/ContactsSmartisan.apk` |
| amber_requires_package_gate | AMBER_SHARED_UID | 108 | 2 | 106 | com.google.android.marvin.talkback | system | `system/app/talkback.apk` |
| defer_green_coupled_or_large_locale_table | GREEN_OR_YELLOW_APP | 105 | 2 | 103 | com.android.browser | system | `system/app/BrowserChrome/BrowserChrome.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 105 | 2 | 103 | com.android.calendar | system | `system/priv-app/CalendarSmartisan/CalendarSmartisan.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 86 | 2 | 84 | com.smartisanos.smartfolder.aoa | system | `system/app/HandShaker/HandShaker.apk` |
| red_requires_core_gate | RED_CORE_APP | 84 | 2 | 82 | com.android.inputmethod.latin | product | `app/LatinIME/LatinIME.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 82 | 2 | 80 | com.smartisanos.videoplayerproject | system | `system/priv-app/VideoPlayer/VideoPlayer.apk` |
| red_requires_core_gate | RED_CORE_APP | 81 | 6 | 75 | com.android.desktop.systemui | system | `system/priv-app/SmartisanDesktopSystemUI/SmartisanDesktopSystemUI.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 80 | 4 | 76 | com.smartisanos.expandservice | system | `system/priv-app/SmartisanExpandService/SmartisanExpandService.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 80 | 4 | 76 | com.smartisanos.launcher | system | `system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 80 | 4 | 76 | com.smartisanos.magicflow | system | `system/app/MagicFlow/MagicFlow.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 79 | 4 | 75 | com.android.camera2 | system | `system/app/CameraSmartisan3/CameraSmartisan3.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 79 | 4 | 75 | com.smartisanos.boston.phone | system | `system/app/BostonScreenMirror/BostonScreenMirror.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 79 | 4 | 75 | com.smartisanos.clock | system | `system/priv-app/ClockSmartisan/ClockSmartisan.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 79 | 4 | 75 | com.smartisanos.keymapping | system | `system/app/KeyMapping/KeyMapping.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 79 | 4 | 75 | com.smartisanos.wallet | system | `system/priv-app/WalletSmartisan/WalletSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 78 | 2 | 76 | com.qti.ltebc | system_ext | `priv-app/QAS_DVC_MSP/QAS_DVC_MSP.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 78 | 3 | 75 | com.smartisanos.weather | system | `system/app/WeatherSmartisan/WeatherSmartisan.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.android.gallery3d | system | `system/app/GallerySmartisan/GallerySmartisan.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.android.providers.weather | system | `system/app/WeatherProvider/WeatherProvider.apk` |
| red_requires_core_gate | RED_SHARED_UID | 77 | 2 | 75 | com.bytedance.os.slardar | system | `system/app/SlardarOsClient/SlardarOsClient.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.redteamobile.global.roaming | vendor | `app/Redtea-app/Redtea-app.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisan.smpush | system | `system/app/SMPushService/SMPushService.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisan.table.setupwizard | system | `system/app/TableSetupWizard/TableSetupWizard.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisan.unionpush.proxy | system | `system/app/UnionPushProxy/UnionPushProxy.apk` |
| red_requires_core_gate | RED_SHARED_UID | 77 | 2 | 75 | com.smartisanos.backup | system | `system/app/Backup/Backup.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 77 | 2 | 75 | com.smartisanos.cloudsyncshare | system | `system/priv-app/CloudServiceShare/CloudServiceShare.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisanos.filemanager | system | `system/app/FileManagerSmartisan/FileManagerSmartisan.apk` |
| red_requires_core_gate | RED_SHARED_UID | 77 | 2 | 75 | com.smartisanos.filemanagerservice | system | `system/app/FileManagerService/FileManagerService.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisanos.hearingaid | system | `system/app/HearingAid/HearingAid.apk` |
| red_requires_core_gate | RED_CORE_APP | 77 | 2 | 75 | com.smartisanos.ideapills | system | `system/priv-app/IdeaPills/IdeaPills.apk` |
| red_requires_core_gate | RED_CORE_APP | 77 | 2 | 75 | com.smartisanos.ime | system | `system/app/IMESmartisan/IMESmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 77 | 2 | 75 | com.smartisanos.music | system | `system/priv-app/MusicPlayer/MusicPlayer.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 77 | 2 | 75 | com.smartisanos.numberassistant | system | `system/priv-app/NumberAssistant/NumberAssistant.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisanos.quicksearch | system | `system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 77 | 2 | 75 | com.smartisanos.sara | system | `system/priv-app/VoiceAssistant/VoiceAssistant.apk` |
| amber_requires_package_gate | AMBER_PRIV_APP | 77 | 2 | 75 | com.smartisanos.screenrecorder | system | `system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk` |
| tier2_green_full_language_prune | GREEN_OR_YELLOW_APP | 77 | 2 | 75 | com.smartisanos.security | system | `system/app/PermissionManager/PermissionManager.apk` |
| red_requires_core_gate | RED_CORE_APP | 77 | 2 | 75 | com.smartisanos.security.ime | system | `system/app/IMESecurity/IMESecurity.apk` |
| red_requires_core_gate | RED_SHARED_UID | 77 | 2 | 75 | com.smartisanos.securitycenter | system | `system/priv-app/SecurityCenter/SecurityCenter.apk` |

## Deferrals

- SettingsSmartisan remains a core shared-UID Settings gate, even for resource-only language work.
- Framework assets remain behind v0.12/v0.10 live framework gates.
- Keyboard, Browser/WebView, Launcher, Keyguard, phone, permission, provider, and APEX packages need focused gates.
- Remaining APK-only outputs prove resource surgery but not ROM boot behavior.
