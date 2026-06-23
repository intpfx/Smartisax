# Feature Control Modification Map

Date: 2026-06-18.

This note records the current confidence boundary for user-facing system
control changes, especially system dark mode and language selection. It is
based on the static Smartisan OS 8.5.3 ROM corpus plus apktool rebuild smoke
tests. Live-device reads still need to be refreshed when ADB is available.

## Corpus

Focused corpus builder:

```text
tools/r2-build-feature-control-graph-corpus.py
```

Current output:

```text
reverse/smartisan-8.5.3-rom-static/graph-corpus/feature-control
copied files: 473
missing expected files: 0
graphify extract: 10956 nodes, 101010 extracted edges
graphify cluster-only: 10888 nodes, 27882 clustered edges, 358 communities
```

Use graphify here as a navigation index. Final modification decisions still
come from the decompiled source, resources, manifests, and live-device checks.

## Dark Mode

The Android backend exists. `UiModeManagerService` starts from `SystemServer`
and exposes `cmd uimode night [yes|no|auto|custom]`. `setNightMode()` enforces
`android.permission.MODIFY_DAY_NIGHT_MODE` when day/night mode is locked.

Important sources:

```text
framework.jar/sources/android/app/UiModeManager.java
services.jar/sources/com/android/server/UiModeManagerService.java
framework-res.apk/resources/res/values/bools.xml
framework-res.apk/resources/res/values/integers.xml
```

Important framework resources:

```text
config_enableNightMode=true
config_lockDayNightMode=true
config_lockUiMode=false
config_defaultNightMode=1
```

The permission declaration is:

```text
android.permission.MODIFY_DAY_NIGHT_MODE protectionLevel=system|signature
```

This makes a ROM-bundled system app a plausible normal caller for
`UiModeManager.setNightMode()` on this build. It is still not evidence that
Settings/SystemUI APK replacement is safe.

Settings integration points:

```text
SettingsSmartisan MainSettingsFragment.initItems()
  -> ID_BRIGHTNESS=18
  -> BrightnessSettingsFragment

BrightnessSettingsFragment
  -> res/layout/brightness_setting.xml
  -> Smartisan SettingItemSwitch / SettingItemText layout style
```

The most natural in-Settings location for a dark-mode item is the
Brightness/Display page, near color profile, eye protection, read mode, refresh
rate, and font/display size. Doing that inside the existing page requires a
safe plan for modifying `SettingsSmartisan.apk`, which is currently a
shared-UID core package.

Read-only package preflight confirms that boundary:

```text
tools/r2-rom-mod-preflight.py com.android.settings --action inspect
tools/r2-rom-mod-preflight.py com.android.settings --action replace

overall_level:
  RED
key flags:
  priv-app
  sharedUserId=android.uid.system
  sysconfig and privapp-permissions references
  overlays target this package
  8 providers, 106 exported components
  core intents include MAIN, LAUNCHER, HOME, BOOT_COMPLETED, LOCALE_CHANGED,
  PACKAGE_REPLACED, VIEW
```

Deeper Settings source findings:

```text
MainSettingsFragment:
  the settings home screen is not an XML preference screen.
  it hard-codes SettingItem rows and click routing in Java.
  ID_BRIGHTNESS=18 calls start(BrightnessSettingsFragment.class).

BrightnessSettingsFragment:
  onCreateView inflates R.layout.brightness_setting.
  existing controls are bound by id and handled in onClick/onCheckedChanged.
  a dark-mode switch here needs both layout/resource IDs and code handling.

SettingsActivity:
  supports :settings:show_fragment but validates against ENTRY_FRAGMENTS for
  external shortcut-style launches.
  BrightnessSettingsFragment is reached through Smartisan's SupportFragment
  stack from MainSettingsFragment rather than through the AOSP dashboard.
```

There is also a lower-risk search integration route:

```text
SettingItemsProvider:
  SQLite table settingitems stores name/alias/intent/extra/search metadata.

SettingItemsLauncher:
  content://com.android.settings.settingitemssuggestions/settingitems/...
  can launch either a component or a full intent=... URI.
```

That route can make `SmartisaxControls` discoverable from system search
without modifying Settings home or the Brightness page.

Smartisan SystemUI is not AOSP QS tile wiring. AOSP resource strings contain a
`night` stock tile, but `QSTileHost.createTile()` only recognizes Smartisan
`toggle...` specs. Adding `night` to a resource string would produce a bad tile
spec.

Actual Smartisan QS default flow:

```text
SettingsProvider DatabaseHelper seeds system setting expanded_widget_buttons.
SmartisanSystemUI QSTileHost reads SmartisanApi.WIDGET_BUTTONS.
QSTileHost.createTile() maps toggle... specs to tile classes.
```

Relevant files:

```text
SettingsProvider.apk/sources/com/android/providers/settings/DatabaseHelper.java
SettingsProvider.apk/resources/res/values/strings.xml
SmartisanSystemUI.apk/sources/com/android/systemui/statusbar/phone/QSTileHost.java
SmartisanSystemUI.apk/sources/com/android/systemui/util/SmartisanApi.java
raw/system_ext/etc/permissions/com.android.systemui.xml
```

`QSTileHost.createTile()` also supports Android custom tile specs:

```text
custom(package/.TileService)
```

`TileQueryHelper` discovers services with
`android.service.quicksettings.action.QS_TILE` and requires the service
permission `android.permission.BIND_QUICK_SETTINGS_TILE`. Therefore a ROM
priv-app can expose a normal `TileService` and SystemUI can render it without
patching `SmartisanSystemUI.apk`.

However, this is not yet a safe final default-tile route. SettingsSmartisan's
quick-widget customization page uses `QuickWidgetFactory.getWidget()` to render
known Smartisan `toggle...` keys. Unknown or `custom(...)` specs may be valid
for SystemUI but still unsafe in the SettingsSmartisan editor. Do not directly
seed `custom(com.smartisax.controls/.DarkModeTileService)` into
`expanded_widget_buttons` until that editor path is either patched or proven
live.

`com.android.systemui.xml` allowlists `MODIFY_DAY_NIGHT_MODE`, but the static
uses-permission index currently shows only `com.android.shell` requesting that
permission. A SystemUI code patch would need manifest work too.

Recommended first dark-mode implementation route:

```text
Create a small Smartisax system priv-app with a QS TileService and settings
activity. Request MODIFY_DAY_NIGHT_MODE, expose a BIND_QUICK_SETTINGS_TILE
service, and call UiModeManager directly. Use it as a backend/permission probe,
not as the final native quick-widget default.
```

This is an intermediate low-risk implementation path, not the final definition
of "system-level integration". The final in-place Settings page integration
still requires an original-cert-preserving SettingsSmartisan no-op replacement
probe, or a framework route that does not break shared-UID package
verification.

Current implementation artifact:

```text
source:
  apps/SmartisaxControls/
build:
  tools/r2-build-smartisax-controls.sh
signed APK:
  hard-rom/build/apk/SmartisaxControls.apk
sha256:
  c6a8f0f267d8e9aeb300c3c2eeecc952c51df56c8b9e5c165169f0314b85eb32
manifest:
  package=com.smartisax.controls
  uses-permission android.permission.MODIFY_DAY_NIGHT_MODE
  activity .DarkModeActivity handles QS_TILE_PREFERENCES
  service .DarkModeTileService handles QS_TILE with BIND_QUICK_SETTINGS_TILE
allowlist template:
  apps/SmartisaxControls/privapp-permissions-com.smartisax.controls.xml
system image file template:
  directory mode 0755, uid/gid 0:0
  file mode 0644, uid/gid 0:0
  security.selinux=u:object_r:system_file:s0
```

This APK is not flashed or live-tested yet.

Current native QS APK-only candidate:

```text
variant:
  v0.11-native-darkmode-integration-apks
build:
  tools/r2-build-native-darkmode-tile-apks.sh
verify:
  tools/r2-verify-v0.11-native-darkmode-tile-apks.sh
SystemUI patch:
  QSTileHost.createTile() maps toggleDarkMode to
  com.android.systemui.qs.tiles.DarkModeTile.
  DarkModeTile uses UiModeManager.setNightModeActivated(boolean), falls back to
  setNightMode(yes/no), and reuses existing night-display strings/icons.
SettingsSmartisan patch:
  BrightnessSettingsFragment exposes a native dark-mode row backed by
  UiModeManager, and QuickWidgetFactory.getWidget() renders toggleDarkMode with
  existing dark-mode title/icon resources. NotificationCustomView also injects
  toggleDarkMode into the additional/default/reset candidate paths so the editor
  can offer the native key without a smartisanos.jar registry patch.
patched APKs:
  hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
    sha256=1b937ea392d997ac2dc84e59a2a7e62bc3a4c655c7a61bb1bf2a73cdbf91a3ad
  hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
    sha256=ebdeb3edc2630ea21d5de7a97c616a03999d66c220f6a4c4eb61c1d46c5d4817
offline verification:
  only SmartisanSystemUI classes10.dex changed.
  only SettingsSmartisan classes.dex and classes2.dex changed.
  patched tile, settings-row, widget, and NotificationCustomView strings are
  present.
  expected keytool/jarsigner digest boundary is recorded for the changed dex.
status:
  APK-only candidate. No super image has been generated, and this is not
  flash-authorized before live no-op gates for the core APKs.
```

Current v0.5-control image candidate:

```text
build script:
  tools/r2-hardrom-build-v0.5-control.sh
source baseline:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
patched partition:
  system_b
system image:
  hard-rom/build/system-otatrust-v0.5-control.img
  sha256=b4ee6966ba70e7fb8c19dd48e8bd3f4dd9380a702217fd1cade6bfe9704b5dee
sparse super:
  hard-rom/build/super-otatrust-v0.5-control-exact-current.sparse.img
  sha256=6acf9ed5e9f14bc1ef6f2a2a87af9006176ad2cc4862b909fc2fb7b57f5a1fa8
offline verification:
  inserted APK/XML dump hashes match inputs.
  file mode 0644, uid/gid 0:0, security.selinux=u:object_r:system_file:s0.
  e2fsck -fn passed.
  patched system_b hash matched the source system image.
live status:
  not flashed yet.
```

## Language Selection

There are two locale-selection paths.

AOSP path:

```text
LocalePicker.getSupportedLocales(context)
  -> context.getResources().getStringArray(android.R.array.supported_locales)
LocaleStore.fillCache(context)
LocaleListEditor
```

Smartisan path:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter(context)
  -> Resources.getSystem().getAssets().getLocales()
  -> filters str.length() == 5
```

Therefore a static overlay of `android.R.array.supported_locales` is not enough
to guarantee the visible Smartisan language picker only shows English,
Simplified Chinese, and Traditional Chinese. It covers the AOSP list editor,
but Smartisan's main picker enumerates system asset locales directly.

`Resources.getSystem()` is built by `AssetManager.createSystemAssetsInZygote`:

```text
/system/framework/framework-res.apk
/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
immutable static overlays targeting android
```

Current static inventory:

```text
tools/r2-locale-resource-inventory.py
reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv
docs/research/locale-pruning-map.md

decoded APK/resource packages scanned: 289
packages with locale-qualified values dirs: 190
packages with Japanese/Korean resource dirs: 175
framework-res locales visible to Smartisan picker:
  en_US, ja_JP, ko_KR, zh_CN, zh_TW
framework-smartisanos-res locales:
  ja, ko, zh_CN, zh_TW
```

Because `LocalePickerFragment` filters `str.length() == 5`, the first likely
ROM-level language-list target is `framework-res.apk`'s regioned Japanese and
Korean configs (`ja_JP`, `ko_KR`). A full hard prune of all Japanese/Korean
translation resources is much broader and touches 175 decoded packages,
including many shared-UID and core packages.

Safer near-term functional route:

```text
Expose a restricted locale chooser in our own privileged control app.
Use CHANGE_CONFIGURATION / LocalePicker APIs to apply only en_US, zh_CN,
and zh_TW.
```

True ROM-level language-list pruning requires one of:

```text
1. framework-res resource rebuild with ja_JP/ko_KR configs removed
2. a safe SettingsSmartisan code patch to filter locales
3. a framework/AssetManager filtering hook
```

Option 1 is now the narrowest route for the visible picker, but it is still
early-boot framework resource work and must be tested as a dedicated rollback
variant.

## APK Rebuild Toolchain

OpenJDK exists but is not on `/usr/bin/java`'s default path. Use:

```text
/opt/homebrew/opt/openjdk/bin/java
```

apktool:

```text
third_party/apktool/apktool_3.0.2.jar
```

Required framework resources for Smartisan APKs:

```text
framework-res.apk -> package id 1
framework-smartisanos-res.apk -> package id 2
```

Smoke results:

```text
framework-res.apk: decode/rebuild OK.
framework-smartisanos-res.apk: decode OK, rebuild blocked by apktool/aapt2
  handling of Smartisan private ^attr-private type id 0x0b. Do not normalize
  these attrs to ordinary attr because that changes type identity.
SettingsProvider.apk: decode/rebuild OK.
SettingsSmartisan.apk: decode/rebuild OK after removing decoded
  androidprv:quickContactWindowSize="true" manifest attr.
SmartisanSystemUI.apk: decode/rebuild OK.
```

Reusable smoke script:

```text
tools/r2-apktool-rebuild-smoke.sh SettingsProvider
tools/r2-apktool-rebuild-smoke.sh SettingsSmartisan
tools/r2-apktool-rebuild-smoke.sh SmartisanSystemUI
tools/r2-apktool-rebuild-smoke.sh FrameworkRes
tools/r2-apktool-rebuild-smoke.sh SmartisanFrameworkRes
tools/r2-build-smartisax-controls.sh
```

These rebuilt APKs are unsigned. Passing apktool smoke does not make a package
safe to flash.

## Signing Boundary

Settings and SystemUI are not ordinary APK replacement targets:

```text
com.android.settings  sharedUserId=android.uid.system
com.android.systemui  sharedUserId=android.uid.systemui, coreApp=true
com.android.providers.settings  sharedUserId=android.uid.system, coreApp=true
framework-res.apk  package=android, sharedUserId=android.uid.system, coreApp=true
framework-smartisanos-res.apk  package=smartisanos, sharedUserId=android.uid.system, coreApp=true
```

Both use the Smartisan Android certificate:

```text
99CB9A0ECE39C4301E22150E5D7238EE9B4073042054C60BAAFD68F3A7C57574
EMAILADDRESS=smartisancm@smartisan.com, CN=Android, OU=Software,
O=Smartisan, L=Wangjiang, ST=BeiJing, C=CN
```

We have the public cert but not the private key. Re-signing these shared-UID
core packages with our own key is not a safe ROM path.

The deeper package-manager source walk now shows a narrower possible route:

```text
system partition scan -> skipVerify=true
ParsingPackageUtils.getSigningDetails(..., skipVerify=true)
  -> ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)
```

This does not ignore signatures. It still extracts a certificate and then
`PackageManagerServiceUtils.verifySignatures()` compares it with previous
package and shared-user signing details. The practical implication is:

```text
bad path:
  apktool rebuild -> unsigned or self-signed core APK replacement

possible path, not live-proven yet:
  original-cert-preserving system-partition patch
  -> no-op replacement boot probe
  -> one-behavior patch only if the no-op probe boots cleanly
```

Current offline evidence is recorded in:

```text
docs/research/system-apk-signature-boundary.md
tools/r2-apk-signature-boundary-check.sh
```

Current SettingsSmartisan candidates:

```text
v0.6-settings-noop:
  no-op replacement, offline-built, not live-verified.
  keytool/jarsigner still read the Smartisan cert.

v0.7-locale-filter:
  first behavior patch candidate, offline-built, not live-verified.
  hides ja_JP and ko_KR in LocalePickerFragment.constructAdapter().
  keytool/jarsigner fail with SHA-256 digest error for classes.dex, so this
  must wait until v0.6 proves the system-partition cert-only path live.
```

## Confidence Table

```text
GREEN
  - Hard-delete already validated low-risk packages.
  - Add a new Smartisax privileged system app with its own signature and
    explicit privapp allowlist.

AMBER
  - Static framework/product overlays for android or SystemUI resources.
  - Dark-mode control via our own privileged app and QS TileService.
  - Restricted language switcher in our own privileged app.

RED UNTIL ORIGINAL-CERT NO-OP BOOT PROBE PASSES
  - Replacing SettingsSmartisan.apk with modified resources/dex.
  - Replacing SmartisanSystemUI.apk with modified resources/dex.
  - Replacing SettingsProvider.apk with modified resources/dex.
  - Same-package replacement of BrowserChrome.

RED UNTIL BOOTCHAIN PLAN EXISTS
  - framework-res.apk or framework-smartisanos-res.apk direct repack.
  - framework.jar/services.jar behavior patches.
  - PackageManager signature bypass patches.
```

## Next Gate

1. For SettingsSmartisan core-APK patching, flash and verify v0.6-settings-noop
   first. Do not jump directly to v0.7.

2. If v0.6 passes, consider v0.7-locale-filter as the first one-behavior
   Settings patch.

3. For the separate feature-control path, restore ADB visibility and collect
   read-only runtime state:

```text
adb -s bb12d264 shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix'
adb -s bb12d264 shell 'cmd uimode night; dumpsys uimode | head -120'
adb -s bb12d264 shell 'settings get system expanded_widget_buttons'
adb -s bb12d264 shell 'settings get secure ui_night_mode'
```

4. Build or flash the tiny `SmartisaxControls` privileged app as a feature
experiment, not as a replacement for Settings/SystemUI.

5. Use it first for a dark-mode toggle. If that boots and receives the intended
privileged permission, extend the same app with the restricted locale switcher.
