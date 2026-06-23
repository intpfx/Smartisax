# Native Dark Mode Integration Map

Purpose:

```text
Define the source-level route for making system light/dark mode feel native on
Smartisan OS 8.5.3. This is the working map for the user-facing goal: a Settings
entry, a Smartisan QS tile, stable persistence, editor/reset behavior, and live
verification without breaking boot, Keyguard, Launcher, or SystemUI.
```

Boundary:

```text
This document is source analysis and integration design. It is not live proof.
The current v0.11 APKs are still APK-only candidates until the SettingsSmartisan
and SmartisanSystemUI no-op live gates pass.
```

## Silkiness Requirements

A native dark-mode ROM build is not complete until all of these are true on the
live device:

```text
1. Settings has a visible display/brightness row for dark mode.
2. Toggling that row calls UiModeManager and updates ui_night_mode through the
   framework backend.
3. SystemUI has a native Smartisan key, toggleDarkMode, not only a custom(...)
   tile spec.
4. The Smartisan quick-widget editor can render and offer toggleDarkMode.
5. SystemUI reloads tiles after Settings writes widget order and broadcasts
   com.smartisanos.action.WIDGET_BUTTONS_CHANGED.
6. The default-visible route either deliberately replaces one existing phone
   first-page tile or stays out of the default list.
7. Reset, SettingsProvider upgrade cleanup, and backup/restore normalization do
   not silently delete or duplicate toggleDarkMode.
8. Reboot, Keyguard, Launcher, Settings, SystemUI, package state, root, and
   logcat checks pass after flashing.
```

## Framework Backend

The platform side already exists:

```text
UiModeManagerService
  observes Settings.Secure ui_night_mode
  writes persist.sys.theme from ui_night_mode
  exposes setNightMode(int)
  exposes setNightModeActivated(boolean)
  persists ui_night_mode and override keys
  computes Configuration.uiMode night bits
  applies the new configuration through ActivityTaskManager
```

Source anchors:

```text
UiModeManagerService.java
  mDarkThemeObserver observes ui_night_mode
  updateSystemProperties() sets persist.sys.theme
  setNightMode(int) persists the requested mode
  setNightModeActivated(boolean) switches day/night and persists
  updateConfigurationLocked() computes uiMode
  applyConfigurationExternallyLocked() pushes configuration externally
```

Implication:

```text
Do not invent a parallel setting. Settings and SystemUI should talk to
UiModeManager. The durable storage key is Settings.Secure ui_night_mode.
```

## Settings Entry

Stock SettingsSmartisan has a hidden display-row slot on Darwin/R2:

```text
BrightnessSettingsFragment
  finds R.id.switch_dc and R.id.switch_dc_tips
  only shows the DC row when !SettingsFeature.isDarwin() && isSupportDC()
  handles the stock row by writing reduce_screen_strobe and calling Calibration
```

v0.8/v0.11 route:

```text
Reuse the hidden switch_dc row on Darwin.
Retitle/rebind behavior in dex code.
Call UiModeManager.setNightModeActivated(boolean).
Read UiModeManager.getNightMode() for initial checked state.
Avoid SettingsSmartisan resources.arsc changes for the first behavior gate.
```

Current proof:

```text
hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-20260618-095726.txt
  verifies BrightnessSettingsFragment dark-mode call sites.
```

Remaining gate:

```text
SettingsSmartisan v0.6 no-op must boot and verify live before this behavior APK
is allowed into a ROM image.
```

## SystemUI Tile

Stock SmartisanSystemUI uses Smartisan native tile keys:

```text
QSTileHost
  registers com.smartisanos.action.WIDGET_BUTTONS_CHANGED
  loads SmartisanApi.WIDGET_BUTTONS, which maps to expanded_widget_buttons
  reads Settings.System expanded_widget_buttons
  falls back to SettingsUtil.getDefaultNotificationWidgets()
  deduplicates tile keys
  truncates first-page tiles to 20
  creates first-class native tiles in createTile(String)
```

Stock gap:

```text
QSTileHost has no toggleDarkMode branch.
```

v0.11 route:

```text
Add a native toggleDarkMode branch in QSTileHost.createTile().
Add DarkModeTile that calls UiModeManager.setNightModeActivated(boolean), with a
setNightMode(int) fallback and getNightMode() state read.
Use existing dark-mode icon color resources in SystemUI.
```

Remaining gate:

```text
SmartisanSystemUI same-size no-op certprobe must boot and verify live before a
behavior patch is allowed.
```

## Editor And Additional Route

The Smartisan quick-widget editor is not just SystemUI:

```text
QuickWidgetFactory
  maps known toggle keys to QuickWidget title/icon objects
  returns null for unknown keys

NotificationCustomView
  reads Settings.System expanded_widget_buttons
  reads Settings.System expanded_widget_buttons_additional
  falls back to SettingsUtil additional-widget generation
  renders candidates with QuickWidgetFactory
  saves both settings through Settings.System.putString()
  broadcasts com.smartisanos.action.WIDGET_BUTTONS_CHANGED to SystemUI

SettingsUtil
  builds additional candidates from SettingsSmt.NOTIFICATION_WIDGET.getAllWidgets()

SettingsSmt.NOTIFICATION_WIDGET
  does not contain toggleDarkMode in stock framework.jar
```

v0.11 route:

```text
Patch QuickWidgetFactory so toggleDarkMode renders as a native QuickWidget.
Patch NotificationCustomView locally so toggleDarkMode is appended to additional
candidate strings when absent.
Avoid smartisanos.jar SettingsSmt registry patch as the first route.
```

Why this route is preferred first:

```text
It avoids framework.jar behavior changes while still making the key visible in
the editor/additional path after SettingsSmartisan and SystemUI gates pass.
```

## Default Visibility

Stock default phone list is full:

```text
def_notification_widget_buttons has 20 entries.
QSTileHost returns only the first 20 formatted keys.
```

Therefore:

```text
Do not append toggleDarkMode to def_notification_widget_buttons.
Default-visible integration must replace exactly one existing phone key.
```

Static displacement candidates:

```text
toggleProtectEyes
toggleReadingMode
toggleKeepScreenOn
toggleWirelessTNT
toggleRealtimeSubtitle
```

Policy boundary:

```text
Choosing the displaced key is a product decision, not a pure code decision.
Live state must be captured first, because the user's current
expanded_widget_buttons may differ from stock defaults.
```

## SettingsProvider And Restore

SettingsProvider owns fresh defaults and cleanup:

```text
DatabaseHelper
  seeds Settings.System expanded_widget_buttons from def_notification_widget_buttons
  seeds expanded_widget_buttons_additional from SettingsUtil

SettingsProvider upgrade
  rewrites expanded_widget_buttons and expanded_widget_buttons_additional
  seeds Settings.Secure ui_night_mode as day mode during upgrade < 180
  runs cleanDirtyWidgetButton()

cleanDirtyWidgetButton()
  merges first-page and additional lists
  removes duplicates
  splits to first 20 and overflow
  can reset both settings to defaults

SettingsBackupAgent
  restores and normalizes widget lists
  splits lists larger than 20 into expanded_widget_buttons and
  expanded_widget_buttons_additional
```

Implication:

```text
A final default-visible ROM must include tests for reset, upgrade cleanup, and
restore normalization. A first v0.11 behavior ROM should avoid default seeding
until live gates prove core APK replacement is safe.
```

The current persistence audit is the executable source for this boundary:

```text
tools/r2-darkmode-persistence-audit.py
docs/research/darkmode-persistence-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-persistence-audit.tsv
```

Current result:

```text
Stock SettingsProvider defaults and SettingsSmt.NOTIFICATION_WIDGET omit
toggleDarkMode; stock SettingsSmartisan reset/checkValidity paths can fall back
to target-missing defaults; v0.11 local NotificationCustomView injection is
offline-proven for additional/reset/save paths; SettingsBackupAgent restore
normalization is not target-aware. Therefore the first behavior ROM should stay
editor/additional-first and defer default-visible policy.
```

## Live-State Audit Requirements

`tools/r2-darkmode-live-state-audit.sh` must capture these read-only facts before
default seeding or live migration:

```text
cmd uimode night
dumpsys uimode
secure.ui_night_mode
system.ui_night_mode
global.ui_night_mode
system.expanded_widget_buttons
system.expanded_widget_buttons_additional
secure.expanded_widget_buttons
secure.expanded_widget_buttons_additional
parsed system expanded_widget_buttons count
parsed system expanded_widget_buttons has_toggleDarkMode
parsed system expanded_widget_buttons over20
parsed duplicate keys
SystemUI/SettingsProvider package state
window/keyguard focus
recent UiMode/QSTileHost/SettingsProvider logs
```

The system namespace is mandatory because both QSTileHost and
NotificationCustomView use `Settings.System` for Smartisan widget order.

## Recommended Stage Order

```text
Stage D0: Capture live state with the strengthened read-only audit.
Stage D1: Flash and verify v0.6 SettingsSmartisan no-op only.
Stage D2: Flash and verify SmartisanSystemUI certprobe no-op only.
Stage D3: Build a combined v0.11 exact-current sparse super only after D1/D2.
Stage D4: Flash v0.11 and verify boot, Settings row, QS editor, tile toggle,
          ui_night_mode persistence, keyguard, launcher, root, package state,
          and logcat.
Stage D5: Decide default-visible behavior after live proof:
          keep editor/additional only, replace one default tile, or run a live
          data migration with rollback.
```

Current confidence:

```text
The source route is coherent and the APK call sites are offline-proven.
The user-facing feature is still not complete because live no-op gates,
live-state capture, combined ROM build, flash, and on-device behavior checks are
missing.
```
