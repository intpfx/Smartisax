# Dark Mode Persistence Audit

Date: 2026-06-18.

This read-only audit checks whether the native `toggleDarkMode` QS key can survive Smartisan SettingsProvider seeding, upgrade cleanup, Settings editor reset, backup/restore normalization, and SystemUI first-page loading. It does not modify APKs, images, the live device, or `/data`.

TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/darkmode-persistence-audit.tsv`

## Summary

- additional_generation_path_mapped: 1
- candidate_editor_persistence_proven_offline: 1
- editor_additional_first: 1
- editor_duplicate_reset_path_mapped: 1
- editor_stock_paths_mapped: 1
- fresh_seed_path_mapped: 1
- live_state_captured: 1
- restore_not_target_aware: 1
- stock_default_missing_target: 1
- stock_registry_missing_target: 1
- systemui_first_page_cap_mapped: 1
- ui_mode_restore_broadcast_mapped: 1
- upgrade_cleanup_path_mapped: 1

## Interpretation

- Stock ROM defaults and the SettingsSmt widget registry do not contain `toggleDarkMode`.
- The phone first QS page already uses 20 slots, so appending a 21st key is not a visible default route.
- The current v0.11 APK-only candidate has offline evidence for a SettingsSmartisan-local additional/editor injection route.
- A polished default-visible route is a later decision: replace one default key, patch framework/default/restore paths, or run a live data migration after no-op gates pass.

## fresh_seed

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_default_missing_target | SettingsProvider fresh database seeds Smartisan QS defaults | phone_count=20; target_in_phone=False; default_line=reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/resources/res/values/strings.xml:73 | A fresh database will not show toggleDarkMode on the first QS page unless SettingsProvider defaults or live data are changed. | Keep default seeding out of the first behavior ROM, or replace one stock key deliberately after live state is captured. |
| fresh_seed_path_mapped | DatabaseHelper writes first-page and additional widget settings | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/DatabaseHelper.java:1911:getString(R.string.def_notification_widget_buttons); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/DatabaseHelper.java:1912:loadSetting(sQLiteStatementCompileStatement, "expanded_widget_buttons", string); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/DatabaseHelper.java:1913:loadSetting(sQLiteStatementCompileStatement, "expanded_widget_buttons_additional", SettingsUtil.getAdditionalNotificationWidgets(this.mContext, string)) | The first-page and additional lists are coupled at database creation time. |  |

## registry

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_registry_missing_target | SettingsSmt.NOTIFICATION_WIDGET registry contains selectable keys | registry_count=23; target_in_registry=False; stock_additional_count=3; settingssmt=reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/smartisanos/api/SettingsSmt.java | SettingsUtil cannot generate toggleDarkMode as an additional candidate from stock framework.jar. | v0.11 currently uses a SettingsSmartisan-local candidate injection route instead of a framework.jar registry patch. |
| additional_generation_path_mapped | SettingsUtil additional-widget generation is registry-limited | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar/sources/smartisanos/util/SettingsUtil.java:82:SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets(); reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar/sources/smartisanos/util/SettingsUtil.java:86:!widgetButtonList.contains(widget); reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar/sources/smartisanos/util/SettingsUtil.java:86:isNotificationWidgetSupport(context, widget); reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar/sources/smartisanos/util/SettingsUtil.java:129:SettingsSmt.NOTIFICATION_WIDGET.isWidgetButton(widget) | A SystemUI-only native tile is insufficient for a polished Smartisan editor path. |  |

## settings_editor

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| editor_stock_paths_mapped | Stock SettingsSmartisan editor reads/falls back/resets additional widgets | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java:271:Settings.System.getString(context.getContentResolver(), "expanded_widget_buttons_additional"); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java:272:SettingsUtil.getAdditionalNotificationWidgets(context, getCurrentQuickWidgetSettings(context)); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java:299:getDefaultAdditionalOrderSettings(); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java:361:saveWidgetButtonsAndNotify(defaultOrderSettings, getDefaultAdditionalOrderSettings()) | Stock editor reset and empty-additional fallback will not offer toggleDarkMode unless default/additional generation or local injection knows the key. |  |
| editor_duplicate_reset_path_mapped | Stock duplicate validity reset falls back to default/additional lists | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java:401:saveWidgetButtonsAndNotify(defaultNotificationWidgets, isPCMode ? "" : SettingsUtil.getAdditionalNotificationWidgets(getContext(), defaultNotificationWidgets)); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java:399:checkValidity got duplicate | If the stock reset path is triggered, a target key not present in defaults/additional generation can be dropped. | The v0.11 local injection must cover checkValidity/reset paths, and live validation should intentionally test editor reset. |

## candidate

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| candidate_editor_persistence_proven_offline | v0.11 SettingsSmartisan local injection covers additional/reset/save paths | hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:772:appendDarkModeCandidate; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:775:const-string v0, "toggleDarkMode"; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:1607:getCurrentAdditionalQuickWidgetSettings; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:1842:getDefaultAdditionalOrderSettings; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:849:checkValidity; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:1009:saveWidgetButtonsAndNotify; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:1003:invoke-static {v3, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate; hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441/Settings-NotificationCustomView.smali:3771:invoke-static {p1, p2}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate | The current APK-only candidate tries to make the editor/additional route survive stock fallbacks without patching smartisanos.jar first. | Live no-op and v0.11 behavior gates have passed; still needs manual Settings editor/additional UX proof. |

## settings_provider_upgrade

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| upgrade_cleanup_path_mapped | SettingsProvider upgrade can seed ui_night_mode and reset dirty widget data | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java:2708:getSecureSettingsLocked(i).insertSettingLocked("ui_night_mode", String.valueOf(1); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java:2712:cleanDirtyWidgetButton(i); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java:2855:SettingsUtil.widgetListToString(arrayList.subList(0, 20)); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java:2863:SettingsUtil.getDefaultNotificationWidgets(SettingsProvider.this.getContext()); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java:2866:SettingsUtil.getAdditionalNotificationWidgets(SettingsProvider.this.getContext(), defaultNotificationWidgets) | A durable default-visible route must decide whether upgrade cleanup should preserve, inject, or intentionally ignore toggleDarkMode. | Do not treat a working editor route as proof that upgrade cleanup will preserve default visibility. |

## backup_restore

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| ui_mode_restore_broadcast_mapped | Settings restore broadcasts ui_night_mode changes | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsHelper.java:51:sBroadcastOnRestore.add("ui_night_mode"); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsHelper.java:102:android.os.action.SETTING_RESTORED | The platform night-mode value participates in Android restore notifications; the QS widget list is a separate Smartisan path. |  |
| restore_not_target_aware | SettingsBackupAgent normalizes Smartisan widget lists on restore | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1580:"expanded_widget_buttons_additional"; reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1607:SettingsUtil.getAdditionalNotificationWidgets(this, strValueOf); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1655:arrayList.contains("toggleReadingMode"); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1662:arrayList.contains("toggleWirelessTNT"); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1665:arrayList.contains("toggleRealtimeSubtitle"); reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1672:arrayList.size() > 20; reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java:1679:toRestore(uri, hashSet, contentValues, settingsHelper2, contentResolver, "expanded_widget_buttons_additional" | Stock restore explicitly handles several Smartisan keys but does not know toggleDarkMode, so default-visible durability needs a restore test or patch plan. | After behavior ROM live proof, test backup/restore or add a target-aware restore normalization patch before claiming polished default behavior. |

## systemui_load

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| systemui_first_page_cap_mapped | SystemUI loads first-page widget order and truncates at 20 | reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java:506:SmartisanApi.WIDGET_BUTTONS; reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java:510:SettingsUtil.getDefaultNotificationWidgets(context); reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java:532:if (result.size() > 20); reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java:533:return result.subList(0, 20) | Appending toggleDarkMode as a 21st key will not make it visible on the phone first page. | Default-visible integration must replace a key or migrate live data; editor/additional integration can remain non-default. |

## live_state

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| live_state_captured | Current live QS and ui_night_mode state is captured | hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-170426.txt contains PASS_READ_ONLY and Smartisan QS markers | The stock/current user data can differ from ROM defaults, so migration and displacement decisions require live capture. | Run tools/r2-darkmode-live-state-audit.sh on a booted device before default seeding or migration. |

## route_decision

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| editor_additional_first | Lowest-risk next dark-mode behavior route | stock defaults omit target; registry omits target; v0.11 local injection covers editor additional paths offline; phone default list is full | The next behavior ROM should first prove Settings row, editor/additional availability, SystemUI tile creation, and UiMode persistence without patching SettingsProvider defaults. | Default-visible behavior should be a later D5 decision after manual Settings/QS editor UX proof and product preference review. |
