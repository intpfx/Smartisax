# Dark Mode QS Strategy Audit

Date: 2026-06-18.

This read-only audit maps how a native Smartisan `toggleDarkMode` QS
entry can fit into the existing SettingsProvider defaults, SystemUI
tile factory, SettingsSmartisan quick-widget editor, SettingsSmt
candidate registry, and backup/restore split behavior. It does not
modify APKs, images, the live device, or `/data`.

TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/darkmode-qs-strategy-audit.tsv`

## Summary

- candidate_injection_proven_offline: 1
- capacity_full: 1
- captured: 1
- registry_limited: 1
- requires_displacement: 1
- requires_framework_registry_patch: 1
- restore_split_mapped: 1
- settingssmartisan_local_candidate_patch_available: 1
- stock_missing_native_key: 1

## Default Lists

| list | count | values |
| --- | ---: | --- |
| phone | 20 | `toggleAirplane | toggleWifi | toggleMobileData | toggleVpn | toggleWifiAp | toggleBluetooth | toggleWirelessTNT | toggleGPS | toggleProtectEyes | toggleReadingMode | toggleKeepScreenOn | toggleAutoBrightness | toggleVibrate | toggleMute | toggleDisableButtons | togglepowersave | togglerrecordscreen | toggleFlashlight | toggleRealtimeSubtitle | toggleAutoRotate` |
| boston | 17 | `toggleDisableButtons | toggleScreenShot | togglerrecordscreen | toggleReadingMode | toggleAirplane | toggleWirelessTNT | toggleKeepScreenOn | toggleProtectEyes | toggleWifi | toggleMobileData | toggleVpn | toggleWifiAp | toggleBluetooth | toggleGPS | toggleRealtimeSubtitle | toggleRelay | toggleChargePhone` |
| tnt | 15 | `toggleDisableButtons | toggleScreenShot | togglerrecordscreen | toggleReadingMode | toggleAirplane | toggleWirelessTNT | toggleKeepScreenOn | toggleProtectEyes | toggleWifi | toggleMobileData | toggleVpn | toggleWifiAp | toggleBluetooth | toggleGPS | toggleRealtimeSubtitle` |

## Findings

| status | area | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- | --- |
| capacity_full | default_lists | stock phone quick-widget default page uses all first-page slots | phone=20, boston=17, tnt=15, max_first_page=20 | A default-visible dark-mode tile cannot be appended on phone; it must replace a key, stay in additional/editor path, or use live migration. | Capture live QS state before choosing a displacement. |
| stock_missing_native_key | target_key | stock toggleDarkMode registration state | missing_from=QSTileHost,QuickWidgetFactory,SettingsSmt.NOTIFICATION_WIDGET; default_status=stock_not_default_seeded | The final native route needs one stable key across SystemUI creation, Settings editor rendering, and the optional candidate registry/default seeding path. | v0.11 covers QSTileHost and QuickWidgetFactory offline; SettingsSmt/default seeding remain separate decisions. |
| requires_framework_registry_patch | route | editor-candidate integration route | SettingsUtil.getAdditionalNotificationWidgets uses SettingsSmt.NOTIFICATION_WIDGET; toggleDarkMode registry=no | This route avoids displacing a default first-page tile, but dark mode will appear in the editor/additional set only if SettingsSmt or an equivalent candidate path knows the key. | Patch SettingsSmt registry only after framework/core gates are accepted, or patch SettingsSmartisan candidate generation locally. |
| settingssmartisan_local_candidate_patch_available | route | SettingsSmartisan-local editor candidate route | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java: candidate_uses_factory=yes,falls_back_to_settingsutil=yes,reads_additional_setting=yes,reset_uses_default_additional=yes,saves_additional_setting=yes,stock_mentions_target=no,validity_reset_bypasses_local_default_helper=yes | SettingsSmartisan owns the visible candidate list and persists the additional list, so a local helper can append toggleDarkMode without modifying smartisanos.jar. | Candidate injection is offline-proven; live no-op gates have passed, so next manually verify the editor/additional UX route. |
| candidate_injection_proven_offline | route | current stock/v0.11 candidate injection coverage | stock NotificationCustomView mentions toggleDarkMode=no; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali contains NotificationCustomView dark-mode candidate injection markers | QuickWidgetFactory rendering alone is not enough; the additional list must contain the key before the editor can offer it. |  |
| requires_displacement | route | default-visible phone route | phone default list has 20 entries; QSTileHost truncates to first 20 | Default visibility is a product decision, not a pure code requirement. Replacing a key is safer than appending a 21st entry. | Use the candidate matrix and live-state report before choosing the displaced key. |
| captured | live_state | current live QS state is available for migration/default decision | hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-170426.txt contains PASS_READ_ONLY and Smartisan system QS markers | A live data migration should not be designed from stock defaults alone because existing user data may differ. | Run tools/r2-darkmode-live-state-audit.sh on a booted device. |
| restore_split_mapped | restore | backup/restore can split widget lists at 20 entries | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java: arrayList.size() > 20@L1672 | Any default or migration plan must survive restore normalization into first-page and additional lists. |  |
| registry_limited | candidate_generation | additional-widget generation is registry limited | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar/sources/smartisanos/util/SettingsUtil.java: SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets@L82 | A native key added only to SystemUI will not automatically become selectable in the Smartisan editor. |  |

## Phone Displacement Candidates

These are static source candidates only. They do not choose a final
product policy without live-state and user preference review.

| position | key | class | recommendation | SystemUI | Settings editor | registry |
| ---: | --- | --- | --- | --- | --- | --- |
| 7 | `toggleWirelessTNT` | possible_special_feature_tradeoff | candidate_only_after_live_usage_review | yes | yes | yes |
| 9 | `toggleProtectEyes` | possible_display_policy_tradeoff | candidate_if_dark_mode_replaces_display_comfort_slot | yes | yes | yes |
| 10 | `toggleReadingMode` | possible_display_policy_tradeoff | candidate_if_dark_mode_replaces_display_comfort_slot | yes | yes | yes |
| 11 | `toggleKeepScreenOn` | possible_display_policy_tradeoff | candidate_if_dark_mode_replaces_display_comfort_slot | yes | yes | yes |
| 19 | `toggleRealtimeSubtitle` | possible_special_feature_tradeoff | candidate_only_after_live_usage_review | yes | yes | yes |

## Integration Routes

1. Editor/additional route: add `toggleDarkMode` to SystemUI,
   QuickWidgetFactory, and the SettingsSmt registry or an equivalent
   SettingsSmartisan candidate path. This avoids displacing a stock
   first-page phone tile.
2. Default-visible route: replace exactly one key in
   `def_notification_widget_buttons`; do not append a 21st key.
   Candidate displacement needs live-state and product preference review.
3. Live migration route: after the core APK no-op gates pass and live
   QS state is captured, migrate existing `expanded_widget_buttons`
   only with an explicit rollback/data plan.

## Boundary

- `toggleDarkMode` should remain one stable native Smartisan key.
- A SystemUI-only tile is not enough for a polished integration because
  the Settings editor and additional-widget generation are separate.
- Default visibility is a seeding/migration decision, not part of the
  current v0.11 APK-only behavior proof.
