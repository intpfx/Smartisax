# Language Next Batch Plan

Date: 2026-06-18.

This read-only plan turns the full English/Chinese language-prune coverage audit into concrete next batches. It does not build APKs, rebuild images, flash, reboot, write settings, or touch `/data`.

Input: `reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv`
TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/language-next-batch-plan.tsv`

## Summary

- planned rows: 141
- current local free space: 76660998144 bytes

- P0a_rebuild_v013_tier1a_stored: 3 packages, 6 non-target dirs
- P1_build_small_apk_only: 10 packages, 20 non-target dirs
- P2_build_green_full_language_apk_only: 22 packages, 1555 non-target dirs
- P3_deferred_green_coupled: 5 packages, 161 non-target dirs
- P4_amber_package_gate: 56 packages, 1840 non-target dirs
- P5_red_core_gate: 45 packages, 1098 non-target dirs

## Recommended Order

1. Rebuild the v0.13 Tier1a system image with the current STORED resources.arsc APK inputs before any flashable promotion.
2. The existing APK-only promotion queue is empty in the current coverage TSV; next combined-image work should merge already built v0.17 partition images only if a single flashable test target is needed.
3. Build only a few new small APK-only candidates at a time, starting with the lowest exposure rows in P1.
4. Treat high-yield GREEN rows in P2 as package-review work first; they remove many more directories but have broader app coupling.
5. Keep AMBER/RED rows behind their package, framework, Settings, SystemUI, launcher, input, phone, provider, or live no-op gates.

## P0a Rebuild Existing v0.13 Inputs

| package | partition | non_target_dirs | rel_path | command_hint |
| --- | --- | --- | --- | --- |
| com.android.protips | system | 2 | `system/app/Protips/Protips.apk` | rebuild v0.13 system_b with current STORED APK inputs, then verify offline before any super promotion |
| com.android.printservice.recommendation | system | 2 | `system/app/PrintRecommendationService/PrintRecommendationService.apk` | rebuild v0.13 system_b with current STORED APK inputs, then verify offline before any super promotion |
| com.android.hotspot2.osulogin | system | 2 | `system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk` | rebuild v0.13 system_b with current STORED APK inputs, then verify offline before any super promotion |

## P0b Promote Existing APK-Only Candidates

| package | partition | non_target_dirs | apk_only_variant | apk_only_apk | blockers |
| --- | --- | --- | --- | --- | --- |
| current none |  |  |  |  |  |

## P1 New Small APK-Only Candidates

| package | partition | exposure_score | non_target_dirs | apk_size | package_index_status | blockers |
| --- | --- | --- | --- | --- | --- | --- |
| com.android.carrierdefaultapp | system | 41 | 2 | 49911 | ok | 1 exported components; 3 core intent entries; 8 permissions |
| com.smartisanos.filepreview | system | 43 | 2 | 871661 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 1 core intent entries; 5 permissions |
| com.android.bips | system | 44 | 2 | 1930156 | ok | 2 exported components; 15 permissions |
| com.qualcomm.qti.simcontacts | system_ext | 66 | 2 | 3071976 | recoverable-errors | package-index status recoverable-errors; 2 exported components; 2 core intent entries; system_ext space/extent gate |
| com.smartisanos.nodisturb | system | 70 | 2 | 504305 | ok | 3 exported components; 1 providers; 11 permissions |
| com.smartisanos.gamespeedup | system | 74 | 2 | 1255596 | recoverable-errors | package-index status recoverable-errors; 2 exported components; 1 providers; 15 permissions |
| com.smartisanos.setupwizard | system | 90 | 2 | 4760482 | ok | 4 exported components; 2 core intent entries; 20 permissions |
| com.android.exchange | system | 123 | 2 | 3950003 | recoverable-errors | package-index status recoverable-errors; 5 exported components; 1 providers; 23 permissions |
| com.smartisanos.bug2go | system | 149 | 2 | 4863664 | recoverable-errors | package-index status recoverable-errors; 3 exported components; 2 providers; 1 core intent entries; 32 permissions |
| com.android.egg | system | 150 | 2 | 4451022 | recoverable-errors | package-index status recoverable-errors; 7 exported components; 1 providers; 4 core intent entries |

## P2 High-Yield GREEN Candidates

| package | partition | exposure_score | non_target_dirs | apk_size | package_index_status | blockers |
| --- | --- | --- | --- | --- | --- | --- |
| com.qualcomm.embms | system_ext | 15 | 1 | 49566 | ok | 1 exported components |
| com.qualcomm.qti.qccauthmgr | system_ext | 31 | 1 | 125038 | ok | 1 exported components; 1 providers; 1 core intent entries |
| com.smartisanos.keymapping | system | 34 | 79 | 12279317 | ok | 1 exported components; 1 providers; 10 permissions |
| com.smartisan.unionpush.proxy | system | 52 | 77 | 2643929 | ok | 3 exported components; 1 core intent entries; 8 permissions |
| com.bytedance.wirelesscast | system | 54 | 75 | 7561812 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 18 permissions |
| com.smartisan.table.setupwizard | system | 58 | 77 | 59837550 | recoverable-errors | package-index status recoverable-errors; 2 exported components; 9 permissions |
| com.smartisanos.previewer | system | 69 | 75 | 5619168 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 1 providers; 2 core intent entries; 14 permissions |
| com.smartisanos.weather | system | 70 | 78 | 9720595 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 2 core intent entries; 21 permissions |
| com.smartisan.smpush | system | 75 | 77 | 3059334 | ok | 3 exported components; 1 providers; 1 core intent entries; 16 permissions |
| com.smartisanos.smartfolder.aoa | system | 80 | 86 | 7108011 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 1 providers; 2 core intent entries; 14 permissions |
| com.android.providers.weather | system | 96 | 77 | 5397612 | recoverable-errors | package-index status recoverable-errors; 2 exported components; 2 providers; 2 core intent entries; 15 permissions |
| com.android.camera2 | system | 99 | 79 | 101827317 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 1 providers; 3 core intent entries; 22 permissions |
| com.smartisanos.hearingaid | system | 107 | 77 | 16643177 | recoverable-errors | package-index status recoverable-errors; 2 exported components; 1 providers; 4 core intent entries; 20 permissions |
| com.smartisanos.textboom | system | 129 | 77 | 30551544 | recoverable-errors | package-index status recoverable-errors; 1 exported components; 2 providers; 2 core intent entries; 48 permissions |
| com.smartisanos.boston.phone | system | 151 | 79 | 32992526 | recoverable-errors | package-index status recoverable-errors; 4 exported components; 1 providers; 2 core intent entries; 40 permissions |
| com.smartisanos.magicflow | system | 178 | 80 | 17699131 | recoverable-errors | package-index status recoverable-errors; 3 exported components; 4 providers; 46 permissions |
| com.smartisan.crashreport | system | 178 | 75 | 2238207 | ok | 11 exported components; 2 core intent entries; 20 permissions |
| com.smartisanos.quicksearch | system | 239 | 77 | 8154012 | recoverable-errors | package-index status recoverable-errors; 6 exported components; 5 providers; 5 core intent entries; 54 permissions |
| com.smartisanos.filemanager | system | 270 | 77 | 28526294 | recoverable-errors | package-index status recoverable-errors; 7 exported components; 7 providers; 6 core intent entries; 37 permissions |
| com.redteamobile.global.roaming | vendor | 301 | 77 | 8221600 | recoverable-errors | package-index status recoverable-errors; 13 exported components; 3 providers; 6 core intent entries; 19 permissions |
| com.android.gallery3d | system | 425 | 77 | 84208413 | recoverable-errors | package-index status recoverable-errors; 15 exported components; 5 providers; 13 core intent entries; 47 permissions |
| com.smartisanos.security | system | 630 | 77 | 17406595 | recoverable-errors | package-index status recoverable-errors; 24 exported components; 6 providers; 25 core intent entries; 63 permissions |

## Gate Buckets

- P3_deferred_green_coupled: 5 packages, 161 dirs
- P4_amber_package_gate: 56 packages, 1840 dirs
- P5_red_core_gate: 45 packages, 1098 dirs

## Boundary

- APK-only output is not ROM coverage until it is inserted into the correct partition image and verified.
- Local disk space changes quickly because each flashable sparse super is about 8 GiB; run the v0.17 promotion audit before starting another image build.
- Do not promote core/shared-UID/launcher/input/phone/framework rows without their specific gates.
