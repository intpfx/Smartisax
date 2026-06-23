# WebView System Space Source Audit

Generated: 2026-06-20 01:40:29

This is an offline/read-only audit. It does not build images, touch a
device, flash, reboot, erase partitions, write settings, delete files,
or modify `/data`.

## Result

The user-selected non-BrowserChrome and non-TNT/projection `system_b` space source is `user_selected_no_projection_print_preserving`. It preserves the Android print stack (`BuiltInPrintService`, `PrintSpooler`, and `PrintRecommendationService`) while avoiding BrowserChrome, TNT/projection packages, speech/assistant/text features, and core boot/UI packages. It covers the current bare WebView full-ABI shortfall, but it does not cover the 8 MiB planning reserve.

The safest newly recorded extra source is `smartisan_wallpapers_resource_pack`: a GREEN preflight, no-component, no-permission Smartisan wallpaper resource APK. It appears to be a user-visible asset loss rather than a boot/service dependency, and it can also stand alone as a reserve-covering space source if the user prefers not to delete the larger telemetry/push/debug bundle.

This does not authorize deletion or image construction. It records the
selected deletion set and the remaining reserve/layout decision.

## Capacity Target

| Item | Bytes |
| --- | --- |
| system_b free bytes | 218636288 |
| candidate APK without WebView libs | 15531662 |
| M150 arm64 lib bytes | 166464072 |
| M150 armeabi-v7a lib bytes | 80635596 |
| full-ABI external layout need | 262631330 |
| bare shortfall | 43995042 |
| planning reserve | 8388608 |
| reserved target | 52383650 |

## Gates

| Gate | Status | Evidence | Next step |
| --- | --- | --- | --- |
| SPACE-GATE-01-system-shortfall-recorded | PASS | system_free=218636288; shortfall=43995042; reserve=8388608; reserved_target=52383650 | Use the reserved target, not just the bare shortfall, when choosing a space source. |
| SPACE-GATE-02-browserchrome-not-space-source | REJECTED | browserchrome_allocated=244908032 | Keep BrowserChrome on its separate RED modernization track; do not delete it just to fund WebView. |
| SPACE-GATE-03-user-selected-source-recorded | SELECTED_LOW_RESERVE | source=user_selected_no_projection_print_preserving; allocated=45912064; margin_to_shortfall=1917022; margin_to_reserved_target=-6471586 | Find extra reserve, reduce WebView footprint, or explicitly accept a low-reserve image layout before build. |
| SPACE-GATE-04-no-build-authorization | BLOCKED_IMAGE_DESIGN | this audit is read-only and does not delete packages or build images | After preflights and reserve/layout decision, build a separate candidate image with explicit user confirmation. |

## Space Source Candidates

| Source | Status | Risk | Allocated bytes | Margin to shortfall | Margin to reserved target | Tradeoff |
| --- | --- | --- | --- | --- | --- | --- |
| projection_cast_stack | REJECTED_USER_PROTECTED_TNT_PROJECTION | RED_USER_PROTECTED_CORE_TNT | 44642304 | 647262 | -7741346 | removes Smartisan/Boston wireless projection and cast surfaces |
| projection_plus_low_value_debug_reserve | REJECTED_USER_PROTECTED_TNT_PROJECTION | RED_USER_PROTECTED_CORE_TNT | 57819136 | 13824094 | 5435486 | removes projection/cast plus OEM bugreport, on-device tracing UI, Easter egg, tips, and CTS shim apps |
| no_projection_low_value_service_reserve | COVERS_SHORTFALL_WITH_RESERVE | YELLOW_ORANGE | 54571008 | 10575966 | 2187358 | removes telemetry/push/debug plus print, dream, live wallpaper, HTML viewer, Exchange remnants, CTS shims, and SmartisanShareManual |
| user_selected_no_projection_print_preserving | USER_SELECTED_COVERS_SHORTFALL_LOW_RESERVE | YELLOW_ORANGE_LOW_RESERVE | 45912064 | 1917022 | -6471586 | removes telemetry/push/debug plus dream, live wallpaper, HTML viewer, Exchange remnants, CTS shims, and SmartisanShareManual while preserving Android printing |
| smartisan_wallpapers_resource_pack | COVERS_SHORTFALL_WITH_RESERVE | GREEN_USER_VISIBLE_WALLPAPER_ASSETS | 86925312 | 42930270 | 34541662 | removes the bundled Smartisan wallpaper resource APK; existing /data wallpaper image should survive, but the stock wallpaper picker may lose built-in choices |
| user_selected_plus_smartisan_wallpapers_reserve | COVERS_SHORTFALL_WITH_RESERVE | YELLOW_ORANGE_PLUS_GREEN_WALLPAPER_ASSETS | 132837376 | 88842334 | 80453726 | uses the user-selected no-projection/print-preserving deletion set and also removes the bundled Smartisan wallpaper resource APK |
| user_selected_plus_weather_pair_reserve | COVERS_SHORTFALL_WITH_RESERVE | YELLOW_ORANGE_USER_FEATURE | 61255680 | 17260638 | 8872030 | uses the user-selected no-projection/print-preserving deletion set and also removes the stock weather app/provider base |
| telemetry_push_print_debug_bundle | COVERS_SHORTFALL_LOW_RESERVE | YELLOW_ORANGE | 52174848 | 8179806 | -208802 | removes telemetry/push/debug plus print, dream, live wallpaper, HTML viewer, and Exchange remnants |
| speech_suite_only | COVERS_SHORTFALL_WITH_RESERVE | ORANGE_RED | 85438464 | 41443422 | 33054814 | removes Iflytek speech suite; likely affects voice input, speech recognition, and assistant features |
| weather_pair | NOT_ENOUGH_ALONE | YELLOW | 15343616 | -28651426 | -37040034 | removes stock weather app and weather provider base |
| setupwizard_pair | DEFERRED_FEATURE_OR_FACTORY_RISK | RED_FACTORY_RESET | 64856064 | 20861022 | 12472414 | removes first-boot/factory-reset setup surfaces |
| browserchrome | REJECTED_RED_BROWSER_TRACK | RED_REJECTED_FOR_SPACE_SOURCE | 244908032 | 200912990 | 192524382 | removes the stock default browser track |
| smartisan_ai_text_stack | DEFERRED_FEATURE_OR_FACTORY_RISK | RED_USER_FEATURE_CONFLICT | 285454336 | 241459294 | 233070686 | removes or damages Sara, Big Bang/text intelligence, voice assistant, and search-related features |

## projection_cast_stack

| Field | Value |
| --- | --- |
| status | REJECTED_USER_PROTECTED_TNT_PROJECTION |
| risk | RED_USER_PROTECTED_CORE_TNT |
| logical bytes | 44625999 |
| allocated bytes | 44642304 |
| margin to bare shortfall | 647262 |
| margin to reserved target | -7741346 |
| packages | com.bytedance.casthal, com.bytedance.wirelesscast, com.smartisanos.boston.phone |
| feature tradeoff | removes Smartisan/Boston wireless projection and cast surfaces |
| rationale | offline evidence links Boston/WirelessCast surfaces to TNT/wireless projection settings and components; the user marked this as a core feature |
| next gate | Do not use this as a WebView space source unless the user explicitly reopens the TNT/projection feature boundary. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/BostonScreenMirror | True | 33306440 | 33296384 | 3 | 3 | com.smartisanos.boston.phone |
| /system/priv-app/BostonCastHalService | True | 3622997 | 3637248 | 3 | 3 | com.bytedance.casthal |
| /system/app/SmartisanWirelessCast | True | 7696562 | 7708672 | 3 | 3 | com.bytedance.wirelesscast |

## projection_plus_low_value_debug_reserve

| Field | Value |
| --- | --- |
| status | REJECTED_USER_PROTECTED_TNT_PROJECTION |
| risk | RED_USER_PROTECTED_CORE_TNT |
| logical bytes | 57772740 |
| allocated bytes | 57819136 |
| margin to bare shortfall | 13824094 |
| margin to reserved target | 5435486 |
| packages | com.android.cts.ctsshim, com.android.cts.priv.ctsshim, com.android.egg, com.android.protips, com.android.traceur, com.bytedance.casthal, com.bytedance.wirelesscast, com.smartisanos.boston.phone, com.smartisanos.bug2go |
| feature tradeoff | removes projection/cast plus OEM bugreport, on-device tracing UI, Easter egg, tips, and CTS shim apps |
| rationale | covers the space target but contains user-protected TNT/projection packages, so it is rejected despite the capacity margin |
| next gate | Do not use this bundle. Recompute without BostonScreenMirror, BostonCastHalService, and SmartisanWirelessCast. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/BostonScreenMirror | True | 33306440 | 33296384 | 3 | 3 | com.smartisanos.boston.phone |
| /system/priv-app/BostonCastHalService | True | 3622997 | 3637248 | 3 | 3 | com.bytedance.casthal |
| /system/app/SmartisanWirelessCast | True | 7696562 | 7708672 | 3 | 3 | com.bytedance.wirelesscast |
| /system/app/SMTBugreport | True | 4867760 | 4870144 | 1 | 1 | com.smartisanos.bug2go |
| /system/app/Traceur | True | 3532756 | 3543040 | 3 | 3 | com.android.traceur |
| /system/app/EasterEgg | True | 4557270 | 4562944 | 3 | 3 | com.android.egg |
| /system/app/Protips | True | 143256 | 151552 | 3 | 3 | com.android.protips |
| /system/app/CtsShimPrebuilt | True | 9526 | 12288 | 1 | 1 | com.android.cts.ctsshim |
| /system/priv-app/CtsShimPrivPrebuilt | True | 36173 | 36864 | 1 | 1 | com.android.cts.priv.ctsshim |

## no_projection_low_value_service_reserve

| Field | Value |
| --- | --- |
| status | COVERS_SHORTFALL_WITH_RESERVE |
| risk | YELLOW_ORANGE |
| logical bytes | 54415178 |
| allocated bytes | 54571008 |
| margin to bare shortfall | 10575966 |
| margin to reserved target | 2187358 |
| packages | com.android.bips, com.android.cts.ctsshim, com.android.cts.priv.ctsshim, com.android.dreams.basic, com.android.egg, com.android.exchange, com.android.htmlviewer, com.android.printservice.recommendation, com.android.printspooler, com.android.protips, com.android.traceur, com.android.wallpaper.livepicker, com.android.wallpaperbackup, com.bytedance.os.slardar, com.smartisan.crashreport, com.smartisan.smpush, com.smartisan.unionpush.proxy, com.smartisanos.bug2go, com.smartisanos.manual, com.smartisanos.teatracker, com.smartisanos.tracker |
| feature tradeoff | removes telemetry/push/debug plus print, dream, live wallpaper, HTML viewer, Exchange remnants, CTS shims, and SmartisanShareManual |
| rationale | smallest reviewed no-projection bundle that covers the WebView full-ABI shortfall plus reserve while preserving TNT/projection, BrowserChrome, speech, assistant/text, setup, Launcher, Keyguard, Settings, SystemUI, and phone |
| next gate | Rejected by user selection because the user explicitly preserved the Android print stack: BuiltInPrintService, PrintSpooler, and PrintRecommendationService. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SMTBugreport | True | 4867760 | 4870144 | 1 | 1 | com.smartisanos.bug2go |
| /system/app/CrashReport | True | 2325145 | 2330624 | 3 | 3 | com.smartisan.crashreport |
| /system/app/SlardarOsClient | True | 8325448 | 8335360 | 3 | 3 | com.bytedance.os.slardar |
| /system/app/SMPushService | True | 3149539 | 3153920 | 3 | 3 | com.smartisan.smpush |
| /system/app/UnionPushProxy | True | 2732209 | 2740224 | 3 | 3 | com.smartisan.unionpush.proxy |
| /system/app/TrackerSmartisan | True | 199854 | 208896 | 4 | 3 | com.smartisanos.tracker |
| /system/priv-app/TeaTracker | True | 3403597 | 3411968 | 3 | 3 | com.smartisanos.teatracker |
| /system/app/BuiltInPrintService | True | 2017283 | 2023424 | 3 | 5 | com.android.bips |
| /system/app/PrintSpooler | True | 6475518 | 6483968 | 4 | 3 | com.android.printspooler |
| /system/app/PrintRecommendationService | True | 145294 | 151552 | 3 | 3 | com.android.printservice.recommendation |
| /system/app/BasicDreams | True | 99230 | 110592 | 4 | 3 | com.android.dreams.basic |
| /system/app/HTMLViewer | True | 58883 | 69632 | 4 | 3 | com.android.htmlviewer |
| /system/app/LiveWallpapersPicker | True | 5762679 | 5775360 | 4 | 3 | com.android.wallpaper.livepicker |
| /system/app/WallpaperBackup | True | 76813 | 86016 | 3 | 3 | com.android.wallpaperbackup |
| /system/app/Exchange2 | True | 4108470 | 4116480 | 3 | 3 | com.android.exchange |
| /system/app/Traceur | True | 3532756 | 3543040 | 3 | 3 | com.android.traceur |
| /system/app/EasterEgg | True | 4557270 | 4562944 | 3 | 3 | com.android.egg |
| /system/app/Protips | True | 143256 | 151552 | 3 | 3 | com.android.protips |
| /system/app/CtsShimPrebuilt | True | 9526 | 12288 | 1 | 1 | com.android.cts.ctsshim |
| /system/priv-app/CtsShimPrivPrebuilt | True | 36173 | 36864 | 1 | 1 | com.android.cts.priv.ctsshim |
| /system/priv-app/SmartisanShareManual | True | 2388475 | 2396160 | 3 | 3 | com.smartisanos.manual |

## user_selected_no_projection_print_preserving

| Field | Value |
| --- | --- |
| status | USER_SELECTED_COVERS_SHORTFALL_LOW_RESERVE |
| risk | YELLOW_ORANGE_LOW_RESERVE |
| logical bytes | 45777083 |
| allocated bytes | 45912064 |
| margin to bare shortfall | 1917022 |
| margin to reserved target | -6471586 |
| packages | com.android.cts.ctsshim, com.android.cts.priv.ctsshim, com.android.dreams.basic, com.android.egg, com.android.exchange, com.android.htmlviewer, com.android.protips, com.android.traceur, com.android.wallpaper.livepicker, com.android.wallpaperbackup, com.bytedance.os.slardar, com.smartisan.crashreport, com.smartisan.smpush, com.smartisan.unionpush.proxy, com.smartisanos.bug2go, com.smartisanos.manual, com.smartisanos.teatracker, com.smartisanos.tracker |
| feature tradeoff | removes telemetry/push/debug plus dream, live wallpaper, HTML viewer, Exchange remnants, CTS shims, and SmartisanShareManual while preserving Android printing |
| rationale | user-selected no-projection bundle from the low-value review set; it preserves BuiltInPrintService, PrintSpooler, and PrintRecommendationService, and still avoids TNT/projection, BrowserChrome, speech, assistant/text, setup, Launcher, Keyguard, Settings, SystemUI, and phone |
| next gate | Run package-specific delete preflights for this selected set. It covers the bare full-ABI WebView shortfall, but does not cover the 8 MiB reserve; choose an extra space source, a smaller WebView build, or explicitly accept the low-reserve layout before image build. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SMTBugreport | True | 4867760 | 4870144 | 1 | 1 | com.smartisanos.bug2go |
| /system/app/CrashReport | True | 2325145 | 2330624 | 3 | 3 | com.smartisan.crashreport |
| /system/app/SlardarOsClient | True | 8325448 | 8335360 | 3 | 3 | com.bytedance.os.slardar |
| /system/app/SMPushService | True | 3149539 | 3153920 | 3 | 3 | com.smartisan.smpush |
| /system/app/UnionPushProxy | True | 2732209 | 2740224 | 3 | 3 | com.smartisan.unionpush.proxy |
| /system/app/TrackerSmartisan | True | 199854 | 208896 | 4 | 3 | com.smartisanos.tracker |
| /system/priv-app/TeaTracker | True | 3403597 | 3411968 | 3 | 3 | com.smartisanos.teatracker |
| /system/app/BasicDreams | True | 99230 | 110592 | 4 | 3 | com.android.dreams.basic |
| /system/app/HTMLViewer | True | 58883 | 69632 | 4 | 3 | com.android.htmlviewer |
| /system/app/LiveWallpapersPicker | True | 5762679 | 5775360 | 4 | 3 | com.android.wallpaper.livepicker |
| /system/app/WallpaperBackup | True | 76813 | 86016 | 3 | 3 | com.android.wallpaperbackup |
| /system/app/Exchange2 | True | 4108470 | 4116480 | 3 | 3 | com.android.exchange |
| /system/app/Traceur | True | 3532756 | 3543040 | 3 | 3 | com.android.traceur |
| /system/app/EasterEgg | True | 4557270 | 4562944 | 3 | 3 | com.android.egg |
| /system/app/Protips | True | 143256 | 151552 | 3 | 3 | com.android.protips |
| /system/app/CtsShimPrebuilt | True | 9526 | 12288 | 1 | 1 | com.android.cts.ctsshim |
| /system/priv-app/CtsShimPrivPrebuilt | True | 36173 | 36864 | 1 | 1 | com.android.cts.priv.ctsshim |
| /system/priv-app/SmartisanShareManual | True | 2388475 | 2396160 | 3 | 3 | com.smartisanos.manual |

## smartisan_wallpapers_resource_pack

| Field | Value |
| --- | --- |
| status | COVERS_SHORTFALL_WITH_RESERVE |
| risk | GREEN_USER_VISIBLE_WALLPAPER_ASSETS |
| logical bytes | 86922558 |
| allocated bytes | 86925312 |
| margin to bare shortfall | 42930270 |
| margin to reserved target | 34541662 |
| packages | com.smartisanos.wallpapers |
| feature tradeoff | removes the bundled Smartisan wallpaper resource APK; existing /data wallpaper image should survive, but the stock wallpaper picker may lose built-in choices |
| rationale | delete preflight is GREEN, the APK has no components, no requested permissions, and no sysconfig references; static search found no hard-coded package references in the generated ROM knowledge base; the archive is almost entirely drawable assets |
| next gate | Best extra-space candidate found so far. Before image build, run a focused WallpaperProvider/resource lookup review and live-check current wallpaper plus wallpaper picker behavior on a small isolated variant. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SmartisanWallpapers | True | 86922558 | 86925312 | 1 | 1 | com.smartisanos.wallpapers |

## user_selected_plus_smartisan_wallpapers_reserve

| Field | Value |
| --- | --- |
| status | COVERS_SHORTFALL_WITH_RESERVE |
| risk | YELLOW_ORANGE_PLUS_GREEN_WALLPAPER_ASSETS |
| logical bytes | 132699641 |
| allocated bytes | 132837376 |
| margin to bare shortfall | 88842334 |
| margin to reserved target | 80453726 |
| packages | com.android.cts.ctsshim, com.android.cts.priv.ctsshim, com.android.dreams.basic, com.android.egg, com.android.exchange, com.android.htmlviewer, com.android.protips, com.android.traceur, com.android.wallpaper.livepicker, com.android.wallpaperbackup, com.bytedance.os.slardar, com.smartisan.crashreport, com.smartisan.smpush, com.smartisan.unionpush.proxy, com.smartisanos.bug2go, com.smartisanos.manual, com.smartisanos.teatracker, com.smartisanos.tracker, com.smartisanos.wallpapers |
| feature tradeoff | uses the user-selected no-projection/print-preserving deletion set and also removes the bundled Smartisan wallpaper resource APK |
| rationale | covers the bare WebView full-ABI shortfall, restores a comfortable reserve, keeps Android printing and TNT/projection, and avoids BrowserChrome, speech/assistant/text, setup, Launcher, Keyguard, Settings, SystemUI, and phone |
| next gate | Run delete preflights for the user-selected set plus a focused wallpaper asset review; this remains a candidate, not deletion authorization. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SMTBugreport | True | 4867760 | 4870144 | 1 | 1 | com.smartisanos.bug2go |
| /system/app/CrashReport | True | 2325145 | 2330624 | 3 | 3 | com.smartisan.crashreport |
| /system/app/SlardarOsClient | True | 8325448 | 8335360 | 3 | 3 | com.bytedance.os.slardar |
| /system/app/SMPushService | True | 3149539 | 3153920 | 3 | 3 | com.smartisan.smpush |
| /system/app/UnionPushProxy | True | 2732209 | 2740224 | 3 | 3 | com.smartisan.unionpush.proxy |
| /system/app/TrackerSmartisan | True | 199854 | 208896 | 4 | 3 | com.smartisanos.tracker |
| /system/priv-app/TeaTracker | True | 3403597 | 3411968 | 3 | 3 | com.smartisanos.teatracker |
| /system/app/BasicDreams | True | 99230 | 110592 | 4 | 3 | com.android.dreams.basic |
| /system/app/HTMLViewer | True | 58883 | 69632 | 4 | 3 | com.android.htmlviewer |
| /system/app/LiveWallpapersPicker | True | 5762679 | 5775360 | 4 | 3 | com.android.wallpaper.livepicker |
| /system/app/WallpaperBackup | True | 76813 | 86016 | 3 | 3 | com.android.wallpaperbackup |
| /system/app/Exchange2 | True | 4108470 | 4116480 | 3 | 3 | com.android.exchange |
| /system/app/Traceur | True | 3532756 | 3543040 | 3 | 3 | com.android.traceur |
| /system/app/EasterEgg | True | 4557270 | 4562944 | 3 | 3 | com.android.egg |
| /system/app/Protips | True | 143256 | 151552 | 3 | 3 | com.android.protips |
| /system/app/CtsShimPrebuilt | True | 9526 | 12288 | 1 | 1 | com.android.cts.ctsshim |
| /system/priv-app/CtsShimPrivPrebuilt | True | 36173 | 36864 | 1 | 1 | com.android.cts.priv.ctsshim |
| /system/priv-app/SmartisanShareManual | True | 2388475 | 2396160 | 3 | 3 | com.smartisanos.manual |
| /system/app/SmartisanWallpapers | True | 86922558 | 86925312 | 1 | 1 | com.smartisanos.wallpapers |

## user_selected_plus_weather_pair_reserve

| Field | Value |
| --- | --- |
| status | COVERS_SHORTFALL_WITH_RESERVE |
| risk | YELLOW_ORANGE_USER_FEATURE |
| logical bytes | 61105369 |
| allocated bytes | 61255680 |
| margin to bare shortfall | 17260638 |
| margin to reserved target | 8872030 |
| packages | com.android.cts.ctsshim, com.android.cts.priv.ctsshim, com.android.dreams.basic, com.android.egg, com.android.exchange, com.android.htmlviewer, com.android.protips, com.android.providers.weather, com.android.traceur, com.android.wallpaper.livepicker, com.android.wallpaperbackup, com.bytedance.os.slardar, com.smartisan.crashreport, com.smartisan.smpush, com.smartisan.unionpush.proxy, com.smartisanos.bug2go, com.smartisanos.manual, com.smartisanos.teatracker, com.smartisanos.tracker, com.smartisanos.weather |
| feature tradeoff | uses the user-selected no-projection/print-preserving deletion set and also removes the stock weather app/provider base |
| rationale | weather is a larger optional feature pair; WeatherSmartisan delete preflight is YELLOW and WeatherProvider is ORANGE because of provider/sysconfig hiddenapi references, so this is viable but less clean than the pure wallpaper resource pack |
| next gate | Use only if the user prefers deleting Weather over deleting bundled wallpapers; pair ROM deletion with post-boot updated-system/data-state validation if live /data weather shadows exist. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SMTBugreport | True | 4867760 | 4870144 | 1 | 1 | com.smartisanos.bug2go |
| /system/app/CrashReport | True | 2325145 | 2330624 | 3 | 3 | com.smartisan.crashreport |
| /system/app/SlardarOsClient | True | 8325448 | 8335360 | 3 | 3 | com.bytedance.os.slardar |
| /system/app/SMPushService | True | 3149539 | 3153920 | 3 | 3 | com.smartisan.smpush |
| /system/app/UnionPushProxy | True | 2732209 | 2740224 | 3 | 3 | com.smartisan.unionpush.proxy |
| /system/app/TrackerSmartisan | True | 199854 | 208896 | 4 | 3 | com.smartisanos.tracker |
| /system/priv-app/TeaTracker | True | 3403597 | 3411968 | 3 | 3 | com.smartisanos.teatracker |
| /system/app/BasicDreams | True | 99230 | 110592 | 4 | 3 | com.android.dreams.basic |
| /system/app/HTMLViewer | True | 58883 | 69632 | 4 | 3 | com.android.htmlviewer |
| /system/app/LiveWallpapersPicker | True | 5762679 | 5775360 | 4 | 3 | com.android.wallpaper.livepicker |
| /system/app/WallpaperBackup | True | 76813 | 86016 | 3 | 3 | com.android.wallpaperbackup |
| /system/app/Exchange2 | True | 4108470 | 4116480 | 3 | 3 | com.android.exchange |
| /system/app/Traceur | True | 3532756 | 3543040 | 3 | 3 | com.android.traceur |
| /system/app/EasterEgg | True | 4557270 | 4562944 | 3 | 3 | com.android.egg |
| /system/app/Protips | True | 143256 | 151552 | 3 | 3 | com.android.protips |
| /system/app/CtsShimPrebuilt | True | 9526 | 12288 | 1 | 1 | com.android.cts.ctsshim |
| /system/priv-app/CtsShimPrivPrebuilt | True | 36173 | 36864 | 1 | 1 | com.android.cts.priv.ctsshim |
| /system/priv-app/SmartisanShareManual | True | 2388475 | 2396160 | 3 | 3 | com.smartisanos.manual |
| /system/app/WeatherSmartisan | True | 9837440 | 9846784 | 3 | 3 | com.smartisanos.weather |
| /system/app/WeatherProvider | True | 5490846 | 5496832 | 3 | 3 | com.android.providers.weather |

## telemetry_push_print_debug_bundle

| Field | Value |
| --- | --- |
| status | COVERS_SHORTFALL_LOW_RESERVE |
| risk | YELLOW_ORANGE |
| logical bytes | 52026703 |
| allocated bytes | 52174848 |
| margin to bare shortfall | 8179806 |
| margin to reserved target | -208802 |
| packages | com.android.bips, com.android.cts.ctsshim, com.android.cts.priv.ctsshim, com.android.dreams.basic, com.android.egg, com.android.exchange, com.android.htmlviewer, com.android.printservice.recommendation, com.android.printspooler, com.android.protips, com.android.traceur, com.android.wallpaper.livepicker, com.android.wallpaperbackup, com.bytedance.os.slardar, com.smartisan.crashreport, com.smartisan.smpush, com.smartisan.unionpush.proxy, com.smartisanos.bug2go, com.smartisanos.teatracker, com.smartisanos.tracker |
| feature tradeoff | removes telemetry/push/debug plus print, dream, live wallpaper, HTML viewer, and Exchange remnants |
| rationale | does not touch browser or core boot UI, but it removes many independent surfaces and may affect OEM push/diagnostics |
| next gate | Use only after deciding that OEM push/tracking and print/dream/viewer features are not needed. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SMTBugreport | True | 4867760 | 4870144 | 1 | 1 | com.smartisanos.bug2go |
| /system/app/CrashReport | True | 2325145 | 2330624 | 3 | 3 | com.smartisan.crashreport |
| /system/app/SlardarOsClient | True | 8325448 | 8335360 | 3 | 3 | com.bytedance.os.slardar |
| /system/app/SMPushService | True | 3149539 | 3153920 | 3 | 3 | com.smartisan.smpush |
| /system/app/UnionPushProxy | True | 2732209 | 2740224 | 3 | 3 | com.smartisan.unionpush.proxy |
| /system/app/TrackerSmartisan | True | 199854 | 208896 | 4 | 3 | com.smartisanos.tracker |
| /system/priv-app/TeaTracker | True | 3403597 | 3411968 | 3 | 3 | com.smartisanos.teatracker |
| /system/app/BuiltInPrintService | True | 2017283 | 2023424 | 3 | 5 | com.android.bips |
| /system/app/PrintSpooler | True | 6475518 | 6483968 | 4 | 3 | com.android.printspooler |
| /system/app/PrintRecommendationService | True | 145294 | 151552 | 3 | 3 | com.android.printservice.recommendation |
| /system/app/BasicDreams | True | 99230 | 110592 | 4 | 3 | com.android.dreams.basic |
| /system/app/HTMLViewer | True | 58883 | 69632 | 4 | 3 | com.android.htmlviewer |
| /system/app/LiveWallpapersPicker | True | 5762679 | 5775360 | 4 | 3 | com.android.wallpaper.livepicker |
| /system/app/WallpaperBackup | True | 76813 | 86016 | 3 | 3 | com.android.wallpaperbackup |
| /system/app/Exchange2 | True | 4108470 | 4116480 | 3 | 3 | com.android.exchange |
| /system/app/Traceur | True | 3532756 | 3543040 | 3 | 3 | com.android.traceur |
| /system/app/EasterEgg | True | 4557270 | 4562944 | 3 | 3 | com.android.egg |
| /system/app/Protips | True | 143256 | 151552 | 3 | 3 | com.android.protips |
| /system/app/CtsShimPrebuilt | True | 9526 | 12288 | 1 | 1 | com.android.cts.ctsshim |
| /system/priv-app/CtsShimPrivPrebuilt | True | 36173 | 36864 | 1 | 1 | com.android.cts.priv.ctsshim |

## speech_suite_only

| Field | Value |
| --- | --- |
| status | COVERS_SHORTFALL_WITH_RESERVE |
| risk | ORANGE_RED |
| logical bytes | 85475504 |
| allocated bytes | 85438464 |
| margin to bare shortfall | 41443422 |
| margin to reserved target | 33054814 |
| packages | com.iflytek.speechsuite |
| feature tradeoff | removes Iflytek speech suite; likely affects voice input, speech recognition, and assistant features |
| rationale | large enough alone, but conflicts with the prior goal of keeping Smartisan assistant-style features working |
| next gate | Defer unless the user explicitly accepts speech/voice feature loss. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SpeechSuite | True | 85475504 | 85438464 | 7 | 3 | com.iflytek.speechsuite |

## weather_pair

| Field | Value |
| --- | --- |
| status | NOT_ENOUGH_ALONE |
| risk | YELLOW |
| logical bytes | 15328286 |
| allocated bytes | 15343616 |
| margin to bare shortfall | -28651426 |
| margin to reserved target | -37040034 |
| packages | com.android.providers.weather, com.smartisanos.weather |
| feature tradeoff | removes stock weather app and weather provider base |
| rationale | optional feature pair, but too small to solve the WebView space problem by itself |
| next gate | Can be combined with another bundle only if the user wants deeper debloat. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/WeatherSmartisan | True | 9837440 | 9846784 | 3 | 3 | com.smartisanos.weather |
| /system/app/WeatherProvider | True | 5490846 | 5496832 | 3 | 3 | com.android.providers.weather |

## setupwizard_pair

| Field | Value |
| --- | --- |
| status | DEFERRED_FEATURE_OR_FACTORY_RISK |
| risk | RED_FACTORY_RESET |
| logical bytes | 64841530 |
| allocated bytes | 64856064 |
| margin to bare shortfall | 20861022 |
| margin to reserved target | 12472414 |
| packages | com.smartisan.table.setupwizard, com.smartisanos.setupwizard |
| feature tradeoff | removes first-boot/factory-reset setup surfaces |
| rationale | large enough, but factory reset and provisioning workflows become risky |
| next gate | Defer until a separate factory-reset/provisioning rollback plan exists. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/SetupWizard | True | 4804953 | 4812800 | 3 | 3 | com.smartisanos.setupwizard |
| /system/app/TableSetupWizard | True | 60036577 | 60043264 | 3 | 3 | com.smartisan.table.setupwizard |

## browserchrome

| Field | Value |
| --- | --- |
| status | REJECTED_RED_BROWSER_TRACK |
| risk | RED_REJECTED_FOR_SPACE_SOURCE |
| logical bytes | 245724404 |
| allocated bytes | 244908032 |
| margin to bare shortfall | 200912990 |
| margin to reserved target | 192524382 |
| packages | com.android.browser |
| feature tradeoff | removes the stock default browser track |
| rationale | very large, but BrowserChrome is a RED separate modernization track and should not be used as a casual space source for WebView |
| next gate | Do not use BrowserChrome as the v0.33 space source. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/app/BrowserChrome | True | 245724404 | 244908032 | 3 | 3 | com.android.browser |

## smartisan_ai_text_stack

| Field | Value |
| --- | --- |
| status | DEFERRED_FEATURE_OR_FACTORY_RISK |
| risk | RED_USER_FEATURE_CONFLICT |
| logical bytes | 286025169 |
| allocated bytes | 285454336 |
| margin to bare shortfall | 241459294 |
| margin to reserved target | 233070686 |
| packages | com.iflytek.speechsuite, com.smartisanos.ideapills, com.smartisanos.intelligenwords, com.smartisanos.quicksearch, com.smartisanos.sara, com.smartisanos.smartisanbrain, com.smartisanos.textboom, com.smartisanos.textparticiple, com.smartisanos.voice |
| feature tradeoff | removes or damages Sara, Big Bang/text intelligence, voice assistant, and search-related features |
| rationale | huge space source, but it collides with previously preserved Smartisan features and should not be a WebView prerequisite |
| next gate | Defer unless the user explicitly chooses to abandon these Smartisan feature surfaces. |

| Path | Present | Logical bytes | Allocated bytes | Files | Dirs | Packages |
| --- | --- | --- | --- | --- | --- | --- |
| /system/priv-app/VoiceAssistant | True | 92308496 | 92102656 | 2 | 1 | com.smartisanos.sara |
| /system/app/VoiceAssistantService | True | 20422141 | 20422656 | 1 | 1 | com.smartisanos.voice |
| /system/app/SpeechSuite | True | 85475504 | 85438464 | 7 | 3 | com.iflytek.speechsuite |
| /system/priv-app/SmartisanBrain | True | 14839959 | 14848000 | 1 | 1 | com.smartisanos.smartisanbrain |
| /system/priv-app/IdeaPills | True | 11648459 | 11489280 | 1 | 1 | com.smartisanos.ideapills |
| /system/app/TextBoom | True | 30826636 | 30834688 | 3 | 5 | com.smartisanos.textboom |
| /system/app/TextParticiple | True | 14122134 | 14131200 | 3 | 5 | com.smartisanos.textparticiple |
| /system/app/IntelligenWords | True | 88889 | 98304 | 3 | 5 | com.smartisanos.intelligenwords |
| /system/app/QuickSearchBoxSmartisan | True | 16292951 | 16089088 | 2 | 1 | com.smartisanos.quicksearch |

## Boundary

- Do not use BostonScreenMirror, BostonCastHalService, or SmartisanWirelessCast as WebView space sources; they are treated as user-protected TNT/wireless projection dependencies.
- Do not use BrowserChrome as a space source for WebView; it is the separate RED browser modernization track.
- Do not use SpeechSuite or the broader Smartisan AI/text stack unless the user explicitly accepts assistant, speech, Big Bang, and search feature loss.
- Do not use SetupWizard/TableSetupWizard without a factory-reset/provisioning rollback plan.
- Preserve BuiltInPrintService, PrintSpooler, and PrintRecommendationService unless the user explicitly reopens the Android print feature boundary.
- The selected source covers the bare WebView full-ABI shortfall but not the 8 MiB reserve; choose extra space, a smaller WebView build, or explicit low-reserve acceptance before image work.
- After the selected source is preflighted, build a dedicated image; this report is not a flash gate.

## Outputs

- JSON snapshot: `hard-rom/inspect/browser-webview-system-space-source/webview-system-space-source-audit.json`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-system-space-source-audit.tsv`
- Markdown report: `docs/research/webview-system-space-source-audit.md`
