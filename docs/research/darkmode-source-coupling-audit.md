# Dark Mode Source Coupling Audit

Date: 2026-06-18.

This read-only audit checks the static Smartisan OS 8.5.3 source
knowledge base and existing v0.11 verification evidence for native
system light/dark mode integration. It does not modify APKs, images,
the live device, or `/data`.

TSV output: `reverse/smartisan-8.5.3-rom-static/manifest/darkmode-source-coupling-audit.tsv`

## Summary

- stock_supported: 1
- stock_slot_available: 1
- stock_factory_supported: 1
- stock_resource_available: 4
- stock_host_supported: 1
- stock_persistence_supported: 5
- stock_restore_path_mapped: 1
- stock_widget_registry_limited: 1
- stock_default_capacity_full: 1
- stock_missing_entry: 3
- default_seeding_gap: 1
- candidate_proven_offline: 2
- live_state_captured: 1
- proven_live: 5

## Interpretation

- The stock framework already contains Android's UiModeManager night-mode backend.
- Stock Smartisan Settings/SystemUI do not expose a native dark-mode switch or tile.
- The clean integration route is a native Smartisan `toggleDarkMode` key plus a Settings display-row patch, not an unknown custom tile as the final path.
- Default QS visibility is a separate SettingsProvider/user-data seeding decision; the stock phone default page is already at 20 tiles, and the stock SettingsSmt widget registry does not know `toggleDarkMode`.
- A durable default strategy must account for fresh SettingsProvider seeding, Settings editor reset, additional-widget generation, and backup/restore normalization.
- The current live device state must be considered before deciding whether to seed, replace, or migrate QS tile data.
- v0.11 is now live-proven at the boot/package/hash level and has reversible functional proof for UiModeManager yes/no plus SystemUI `toggleDarkMode` tile creation.
- The remaining dark-mode UX proof is manual/user-facing: Settings row visibility/click behavior and Smartisan QS editor candidate behavior.

## framework

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_supported | stock UiModeManagerService has Android night-mode backend | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/UiModeManagerService.java: SYSTEM_PROPERTY_DEVICE_THEME = "persist.sys.theme"@L72, mDarkThemeObserver@L90, "ui_night_mode"@L261, "dark_theme_custom_start_time"@L261, "dark_theme_custom_end_time"@L261, public void setNightMode(int mode)@L576, public boolean setNightModeActivated(boolean active)@L643, public void persistNightMode(int user)@L890, public void persistNightModeOverrides(int i)@L900, public void updateConfigurationLocked()@L909, private int getComputedUiModeConfiguration(int uiMode)@L966, public void applyConfigurationExternallyLocked()@L975 | The platform side can store, compute, and apply UI night mode without a new framework service. |  |

## settings

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_slot_available | stock BrightnessSettingsFragment has a hidden reusable display-row slot | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/BrightnessSettingsFragment.java: private SettingItemSwitch mReduceStrobeSwitch;@L70, R.id.switch_dc@L203, R.id.switch_dc_tips@L204, !SettingsFeature.isDarwin() && SettingsFeature.isSupportDC()@L225, "reduce_screen_strobe"@L288, Calibration.setReduceScreenStrobeEnable(z)@L454 | R2/Darwin hides the DC row, so v0.8/v0.11 can reuse an existing row without a resource-table change. | SettingsSmartisan no-op live gate must pass before behavior patching this shared-UID APK. |
| stock_factory_supported | stock QuickWidgetFactory renders Smartisan native toggle keys | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/notificationcustom/QuickWidgetFactory.java: getWidgetTitle(Context context, String str)@L14, "toggleAutoBrightness"@L80, "toggleReadingMode"@L86, "toggleRealtimeSubtitle"@L89, return null;@L98 | The quick-widget editor is a Smartisan toggle-key factory, so a native toggleDarkMode key is the clean route. | Patch QuickWidgetFactory only after SettingsSmartisan no-op live gate. |
| stock_missing_entry | stock BrightnessSettingsFragment does not expose UiModeManager | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/BrightnessSettingsFragment.java does not contain: UiModeManager, setNightModeActivated, ui_night_mode | The stock Settings app needs a behavior patch to expose native dark mode. | Use the original-cert-preserving SettingsSmartisan route, not a self-signed rebuild. |
| stock_missing_entry | stock QuickWidgetFactory has no toggleDarkMode entry | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/notificationcustom/QuickWidgetFactory.java does not contain: toggleDarkMode | Unknown custom tile specs may not render in the Smartisan editor; v0.11 adds the native key path. |  |

## systemui

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_host_supported | stock QSTileHost uses Smartisan expanded_widget_buttons and native toggle keys | reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java: ACTION_WIDGET_BUTTONS_CHANGED@L81, SmartisanApi.WIDGET_BUTTONS@L506, tilesSettingChanged(loadSmartisanTileSpecs(context))@L178, public QSTile<?> createTile(String tileSpec)@L421, CustomTile.PREFIX@L408, IntentTile.PREFIX@L494 | SystemUI can load Smartisan tile settings and also parse custom tiles, but native keys are first-class. | SmartisanSystemUI no-op live gate must pass before adding a native tile branch. |
| stock_missing_entry | stock QSTileHost has no toggleDarkMode branch | reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java does not contain: toggleDarkMode, DarkModeTile | A SystemUI behavior patch is required for a native Smartisan dark-mode QS tile. |  |

## qs_persistence

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_persistence_supported | stock SettingsProvider seeds expanded_widget_buttons from def_notification_widget_buttons | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/DatabaseHelper.java: R.string.def_notification_widget_buttons@L1911, loadSetting(sQLiteStatementCompileStatement, "expanded_widget_buttons", string)@L1912, "expanded_widget_buttons_additional"@L1913, SettingsUtil.getAdditionalNotificationWidgets(this.mContext, string)@L1913 | Default QS button order is seeded by SettingsProvider resources, not by QSTileHost alone. | Adding toggleDarkMode to the default list should be a separate SettingsProvider/resource or live data migration decision. |
| stock_persistence_supported | stock SettingsProvider upgrade path rewrites expanded_widget_buttons | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java: getSettingLocked("expanded_widget_buttons")@L2686, getSettingLocked("expanded_widget_buttons_additional")@L2687, insertSettingLocked("expanded_widget_buttons"@L2690, insertSettingLocked("expanded_widget_buttons_additional"@L2691, cleanDirtyWidgetButton@L2712, SettingsUtil.getDefaultNotificationWidgets(SettingsProvider.this.getContext())@L2863 | Existing upgrade/cleanup code can replace or reset widget-button data, so default seeding must be tested independently. | Do not bundle default seeding into the first v0.11 behavior ROM without a separate verification plan. |
| stock_persistence_supported | stock SettingsProvider upgrade path seeds explicit ui_night_mode day value | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsProvider.java: if (i2 < 180)@L2707, getSecureSettingsLocked(i).insertSettingLocked("ui_night_mode", String.valueOf(1), null, true, "android")@L2708 | Smartisan already owns the secure ui_night_mode default during SettingsProvider upgrades; dark-mode integration should write through UiModeManager instead of inventing a parallel setting. |  |
| stock_persistence_supported | stock Settings quick-widget editor writes settings and broadcasts SystemUI reload | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/sources/com/android/settings/widget/NotificationCustomView.java: Settings.System.putString(contentResolver, "expanded_widget_buttons", str)@L379, Settings.System.putString(contentResolver, "expanded_widget_buttons_additional", str2)@L380, new Intent(ACTION_WIDGET_BUTTONS_CHANGED)@L382, intent.setPackage("com.android.systemui")@L383, context.sendBroadcast(intent)@L384 | The editor can persist a new native key after QuickWidgetFactory knows how to render it. | Live validation should inspect expanded_widget_buttons before and after editing. |
| stock_persistence_supported | stock SettingsUtil builds additional widget candidates from SettingsSmt registry | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__smartisanos.jar/sources/smartisanos/util/SettingsUtil.java: SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets()@L82, !widgetButtonList.contains(widget)@L86, isNotificationWidgetSupport(context, widget)@L86, SettingsSmt.NOTIFICATION_WIDGET.isWidgetButton(widget)@L129 | The Settings editor candidate list is registry-limited, so a new native key must be default-seeded, added to the registry path, or inserted by a SettingsSmartisan-specific candidate patch. |  |
| stock_restore_path_mapped | stock settings backup/restore can normalize widget button lists across the 20-tile split | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/sources/com/android/providers/settings/SettingsBackupAgent.java: "expanded_widget_buttons_additional"@L1580, SettingsUtil.getAdditionalNotificationWidgets(this, strValueOf)@L1607, if (arrayList.size() > 20)@L1672, SettingsUtil.widgetListToString(arrayList.subList(0, 20))@L1673, SettingsUtil.widgetListToString(arrayList.subList(20, arrayList.size()))@L1679 | Backup/restore is another path that can reshuffle widget buttons, so a durable default strategy must survive restore normalization as well as fresh database seeding. |  |
| stock_widget_registry_limited | stock SettingsSmt notification-widget registry does not know toggleDarkMode | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/smartisanos/api/SettingsSmt.java does not contain: toggleDarkMode | The stock framework registry route still will not offer toggleDarkMode, so v0.11 uses a SettingsSmartisan-local NotificationCustomView candidate-injection path instead. | If default visibility is required, use a controlled default-list replacement or live migration after live gates. |
| stock_default_capacity_full | stock phone default quick-widget page is already at the 20-tile cap | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/resources/res/values/strings.xml def_notification_widget_buttons=20, boston=17, tnt=15; reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java MAX_QUICK_SETTING_NUM@L85 | Default-visible toggleDarkMode cannot be appended to the phone page; it must replace a default tile, live-migrate user data, or stay in the additional/editor path. | Do not patch the default list until the replacement choice and rollback behavior are explicit. |
| default_seeding_gap | stock default quick-widget strings do not seed toggleDarkMode | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsProvider__SettingsProvider.apk/resources/res/values/strings.xml does not contain: toggleDarkMode | v0.11 makes the key creatable, renderable, and selectable in the editor, but it will not be default-visible unless seeded or added in user settings. | Decide later whether to patch def_notification_widget_buttons or apply a live data migration. |

## resources

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| stock_resource_available | stock Settings resources already include a dark-mode title | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/resources/res/values/strings.xml: <string name="night_mode_yes">Dark</string>@L3360 | The Settings-side title can reuse an existing public string instead of adding resources. |  |
| stock_resource_available | stock Settings public IDs expose night_mode_yes and dark icon colors | reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk/resources/res/values/public.xml: name="dark_mode_icon_color_dual_tone_background"@L1030, name="dark_mode_icon_color_dual_tone_fill"@L1031, name="night_mode_yes"@L10920 | The current candidate can stay dex-only on SettingsSmartisan. |  |
| stock_resource_available | stock SystemUI resources include dark-mode icon colors | reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/resources/res/values/colors.xml: dark_mode_icon_color_dual_tone_background_old@L58, dark_mode_icon_color_dual_tone_fill_old@L59, dark_mode_icon_color_single_tone@L60 | SystemUI already carries dark icon palette resources; v0.11 does not need a resource-table edit. |  |
| stock_resource_available | stock SystemUI public IDs expose dark-mode icon colors | reverse/smartisan-8.5.3-rom-static/jadx/system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk/resources/res/values/public.xml: name="dark_mode_icon_color_dual_tone_background"@L1433, name="dark_mode_icon_color_dual_tone_fill"@L1435, name="dark_mode_icon_color_single_tone"@L1437 | This supports a dex-only tile candidate before any SystemUI resource change. |  |

## candidate

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| candidate_proven_offline | v0.11 APK semantic verifier proves the intended patched call sites | hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-20260618-163441.txt: SmartisanSystemUI: only classes10.dex changed@L19, SettingsSmartisan: only classes.dex and classes2.dex changed@L20, SystemUI: DarkModeTile and QSTileHost toggleDarkMode branch verified@L28, SettingsSmartisan: BrightnessSettingsFragment, QuickWidgetFactory, and NotificationCustomView dark-mode call sites verified@L29, SHA-256 digest error for classes10.dex@L41, SHA-256 digest error for classes.dex@L55, PASS@L60 | The v0.11 APKs match the intended integration points, but APK semantics are not live boot proof. | Do not build/flash v0.11 ROM until SettingsSmartisan and SmartisanSystemUI no-op live gates pass. |
| candidate_proven_offline | v0.11 smali evidence files exist | hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-163441 | Focused smali files make the candidate reviewable without re-decoding large APKs. |  |

## live_state

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| live_state_captured | current device dark-mode/QS state is captured by read-only audit | hard-rom/inspect/darkmode-live-state/darkmode-live-state-20260618-170426.txt: result=PASS_READ_ONLY; secure.ui_night_mode=@L39, system.ui_night_mode=@L53, global.ui_night_mode=@L67, system.expanded_widget_buttons=@L61, system.expanded_widget_buttons_additional=@L62, secure.expanded_widget_buttons=@L47, secure.expanded_widget_buttons_additional=@L48, system.expanded_widget_buttons.count=@L83, system.expanded_widget_buttons.has_toggleDarkMode=@L84, system.expanded_widget_buttons.over20=@L85, secure.sysui_qs_tiles=@L43 | Native dark-mode integration and default QS visibility need the current ui_night_mode and expanded_widget_buttons state before a data migration or SettingsProvider seeding patch is designed. |  |

## live_gate

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| proven_live | SettingsSmartisan no-op live gate | hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-20260618-155616.txt contains PASS | This gate controls whether the corresponding behavior APK can be flashed next. |  |
| proven_live | current-base SmartisanSystemUI no-op live gate | hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-20260618-160919.txt contains PASS | This gate controls whether the corresponding behavior APK can be flashed next. |  |
| proven_live | v0.11 native dark-mode behavior ROM live verification | hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-20260618-165423.txt contains PASS | The combined Settings/SystemUI behavior ROM boots and PackageManager accepts the patched shared-UID APKs. | Next prove user-facing interaction: Settings row behavior, UiMode change, and Smartisan QS editor/tile behavior. |
| proven_live | v0.11 reversible functional UiMode/SystemUI tile test | hard-rom/inspect/v0.11-native-darkmode-functional/v0.11-darkmode-functional-20260618-170411.txt: ui_mode_yes=PASS@L98, ui_mode_no=PASS@L99, systemui_toggleDarkMode_tile_creation=PASS@L100, restore_original_quick_settings=PASS@L101, result=PASS_WRITE_APPROVED_FUNCTIONAL@L102, Creating tile: toggleDarkMode@L70 | The live device accepted reversible /data writes: UiModeManager changed yes/no, SystemUI instantiated DarkModeTile, and original QS data was restored. | Still manually validate the Settings row and Smartisan QS editor candidate surface before calling the whole native dark-mode UX complete. |

## rom_gate

| status | target | evidence | implication | next gate |
| --- | --- | --- | --- | --- |
| proven_live | combined v0.11 native dark-mode sparse super | hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img | The flashable ROM image has booted and matched the expected patched Settings/SystemUI APK hashes on device. | Run reversible functional testing for Settings UiMode and Smartisan QS tile/editor behavior. |
