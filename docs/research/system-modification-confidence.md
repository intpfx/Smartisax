# System Modification Confidence

Date: 2026-06-18.

This note records the current confidence boundary for the user's two active
system goals:

```text
1. smooth system light/dark mode integration
2. keep only English, Simplified Chinese, and Traditional Chinese visible and,
   later, prune non-target language resources from the ROM
```

The conclusion is intentionally split into what is ready to implement, what is
ready to build only behind a gate, and what is not yet safe.

For the current machine-checkable status, use:

```text
tools/r2-darkmode-source-coupling-audit.py
docs/research/darkmode-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-source-coupling-audit.tsv
tools/r2-darkmode-qs-strategy-audit.py
docs/research/darkmode-qs-strategy-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-qs-strategy-audit.tsv
docs/research/darkmode-integration-map.md
tools/r2-darkmode-live-state-audit.sh
hard-rom/inspect/darkmode-live-state/

tools/r2-language-source-coupling-audit.py
docs/research/language-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-source-coupling-audit.tsv
docs/research/language-prune-integration-map.md
tools/r2-language-full-prune-coverage-audit.py
docs/research/language-full-prune-coverage-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv
tools/r2-language-live-state-audit.sh
hard-rom/inspect/language-live-state/

tools/r2-system-mod-readiness-audit.py
docs/research/system-modification-readiness-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/system-modification-readiness-audit.tsv

tools/r2-system-modification-route-audit.py
docs/research/system-modification-route-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/system-modification-route-audit.tsv
```

The readiness audit is stricter than this narrative note: it treats offline APK
and image evidence as proof only for the layer it actually covers, and keeps the
full user goal incomplete until dark-mode live-state, live gates, and full
language-prune coverage pass.

## Current Confidence

I am confident about the control chains now:

```text
dark mode:
  Settings or QS entry
  -> UiModeManager / IUiModeManager
  -> UiModeManagerService
  -> Settings.Secure.ui_night_mode
  -> Configuration.uiMode night bits
  -> ActivityTaskManager.updateConfiguration()

language picker:
  Smartisan Settings language page
  -> LocalePickerFragment.constructAdapter()
  -> Resources.getSystem().getAssets().getLocales()
  -> regioned framework asset locales such as en_US, ja_JP, ko_KR, zh_CN, zh_TW
```

I am not yet treating core APK replacement as live-proven. The blocker is not
finding or editing the code. The blocker is proving the original-cert-preserving
system-partition replacement path on the device without breaking package-manager
shared-UID state.

## 2026-06-18 Deepening Update

The static ROM KB and graphify corpora are now strong enough to support
targeted system modification planning:

```text
static ROM KB:
  decompile targets: 430
  decoded manifests: 289
  java index rows: about 256k
  review gate: Hooke V1.1 Q&A 10/10 PASS

modification-critical graph:
  nodes: 52788
  edges: 130295
  communities: 1643

feature-control graph:
  nodes: 10888
  edges: 27882
  communities: 358
```

Recent graph/source checks agree with the existing route:

```text
language:
  LocalePickerFragment.constructAdapter()
  -> Resources.getSystem().getAssets().getLocales()
  -> framework AssetManager locale configs
  -> framework-res/framework-smartisanos-res/product android overlays

dark mode:
  SettingsSmartisan BrightnessSettingsFragment
  -> UiModeManager.setNightModeActivated(boolean)
  -> UiModeManagerService.updateConfigurationLocked()
  -> ActivityTaskManager configuration update

native quick settings:
  SmartisanSystemUI QSTileHost.createTile(String)
  -> known toggle... keys or CustomTile specs
  SettingsSmartisan QuickWidgetFactory.getWidget(String)
  -> known toggle... keys for editor rendering
```

The confidence boundary is therefore no longer "can we find the code?" The
boundary is now live acceptance of specific replacement layers:

```text
v0.12-framework-res-noop:
  proves framework-res.apk replacement can boot before v0.10 language prune.

v0.6-settings-noop:
  proves SettingsSmartisan original-cert-preserving replacement can boot before
  v0.7/v0.8/v0.11 Settings behavior patches.

systemui-certprobe-noop:
  proves SmartisanSystemUI original-cert-readable no-op replacement can boot
  before v0.11 native toggleDarkMode SystemUI patches.
```

`docs/research/system-modification-route-audit.md` now records the route-level
translation layer between user requests and ROM gates. It keeps delete,
same-package replacement, core shared-UID APK patching, app resource hard-prune,
framework resource replacement, SettingsProvider defaults, boot UI surfaces,
and phone/telephony work separate so a live pass in one layer is not borrowed by
another.

Use `tools/r2-live-flash-preflight.sh <variant>` immediately before any live
gate. It is read-only and checks candidate hashes, v0.4 rollback readiness,
latest offline evidence, verifier scripts, and live adb/fastboot state when
available.

## Dark Mode Route

### Source-Coupling Audit

The dark-mode route now has a dedicated read-only source audit:

```text
tools/r2-darkmode-source-coupling-audit.py
docs/research/darkmode-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-source-coupling-audit.tsv
```

Current result:

```text
stock_supported: 1
stock_slot_available: 1
stock_factory_supported: 1
stock_host_supported: 1
stock_resource_available: 4
stock_persistence_supported: 5
stock_restore_path_mapped: 1
stock_widget_registry_limited: 1
stock_default_capacity_full: 1
stock_missing_entry: 3
default_seeding_gap: 1
candidate_proven_offline: 2
missing_live_state: 1
missing_live_gate: 2
missing_rom_image: 1
```

This means the backend and UI insertion points are understood well enough to
make targeted patches. It also confirms that default QS visibility is a
separate SettingsProvider/user-data seeding decision: the stock phone default
page is already at the 20-tile cap, the stock SettingsSmt widget registry does
not know `toggleDarkMode`, and backup/restore can normalize widget lists across
the 20-tile split. It does not replace live-state or live no-op gates: the
current device UiMode/QS state still must be captured, and Settings/SystemUI
shared-UID replacement still must be proven on the device before a behavior ROM
is built or flashed.

### QS Strategy Audit

The native QS route now has a dedicated strategy audit:

```text
tools/r2-darkmode-qs-strategy-audit.py
docs/research/darkmode-qs-strategy-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-qs-strategy-audit.tsv
```

Current result:

```text
capacity_full=1
stock_missing_native_key=1
requires_framework_registry_patch=1
settingssmartisan_local_candidate_patch_available=1
candidate_injection_proven_offline=1
requires_displacement=1
missing_live_state=1
restore_split_mapped=1
registry_limited=1
```

### Integration Map

The native dark-mode route also has a source-backed implementation map:

```text
docs/research/darkmode-integration-map.md
```

Use it before editing SettingsSmartisan, SmartisanSystemUI, SettingsProvider
defaults, QS reset/restore behavior, or live tile migration. It treats
`Settings.System expanded_widget_buttons` and
`expanded_widget_buttons_additional` as mandatory live-state evidence because
both QSTileHost and NotificationCustomView read the Smartisan widget order from
the system namespace.

This turns the QS question into three explicit routes:

```text
1. Editor/additional route:
   add toggleDarkMode to SystemUI and QuickWidgetFactory, then inject the key
   into SettingsSmartisan's NotificationCustomView additional/default/reset
   paths. This avoids displacing a stock first-page phone tile and avoids
   changing smartisanos.jar first. A SettingsSmt registry patch remains the
   broader framework route, not the preferred first route.

2. Default-visible route:
   replace exactly one key in def_notification_widget_buttons. Do not append a
   21st entry because QSTileHost truncates the phone list at 20.

3. Live migration route:
   after live no-op gates and live-state capture, migrate existing
   expanded_widget_buttons with a rollback/data plan.
```

### Backend Evidence

`UiModeManagerService` is present and wired:

```text
services.jar/com/android/server/UiModeManagerService.java
  SYSTEM_PROPERTY_DEVICE_THEME = "persist.sys.theme"
  observes Settings.Secure.ui_night_mode
  persists ui_night_mode
  applies Configuration.uiMode through ActivityTaskManager.updateConfiguration()

framework-res.apk
  config_enableNightMode=true
  config_lockDayNightMode=true
  config_lockUiMode=false
  config_defaultNightMode=1
```

Important implementation detail:

```text
UiModeManagerService.setNightMode(int)
  checks android.permission.MODIFY_DAY_NIGHT_MODE when night mode is locked.

UiModeManagerService.setNightModeActivated(boolean)
  has no matching permission check in this build's service implementation,
  updates configuration, and persists ui_night_mode.
```

That makes `setNightModeActivated(boolean)` the preferred first API for an
in-Settings switch. It avoids changing the Settings manifest just to add
`MODIFY_DAY_NIGHT_MODE`.

### Lowest-Risk Live Probe

The current low-risk probe is still the additive ROM app:

```text
apps/SmartisaxControls/
  package: com.smartisax.controls
  requests: android.permission.MODIFY_DAY_NIGHT_MODE
  exposes: android.service.quicksettings.action.QS_TILE
  tile service: .DarkModeTileService
```

Smartisan SystemUI can render Android custom tile specs:

```text
SmartisanSystemUI QSTileHost.createTile(String)
  if tileSpec starts with CustomTile.PREFIX:
    CustomTile.create(...)
```

So the first live dark-mode test does not need a SystemUI replacement. It only
needs the v0.5-control additive app to boot, receive its privileged permission,
and toggle `ui_night_mode`.

This is a backend/permission probe, not the final native QS integration.
SystemUI accepts `custom(...)`, but SettingsSmartisan's quick-widget editor
renders known Smartisan `toggle...` keys through `QuickWidgetFactory`. A custom
tile spec could be valid for SystemUI while still unsafe or invisible in the
editor.

### Native Settings Integration

The natural Settings location is:

```text
SettingsSmartisan BrightnessSettingsFragment
  layout: res/layout/brightness_setting.xml
  code: com/android/settings/BrightnessSettingsFragment.java
```

Patch shape after v0.6 passes:

```text
1. Add a SettingItemSwitch near read mode / eye protection:
     @+id/switch_dark_mode
     title: dark mode

2. Add a field:
     private SettingItemSwitch mDarkModeSwitch;

3. Bind it in onCreateView().

4. Refresh state in onSupportVisible():
     UiModeManager.getNightMode() == MODE_NIGHT_YES

5. Register an observer for Settings.Secure.ui_night_mode.

6. Handle switch changes:
     UiModeManager.setNightModeActivated(checked)
```

This is a compact Settings patch, but SettingsSmartisan is still a RED target:

```text
package: com.android.settings
partition: system
path: system/priv-app/SettingsSmartisan/SettingsSmartisan.apk
sharedUserId: android.uid.system
coreApp=true
```

Therefore the gate order is:

```text
1. v0.6-settings-noop live boot probe
2. v0.7-locale-filter live behavior probe
3. only then consider flashing v0.8-darkmode-ui
```

Current offline candidate:

```text
v0.8-darkmode-ui:
  super sparse:
    hard-rom/build/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img
  sha256:
    44fed5e231d8a5525fbe748c25fe89ca3e50319054ade76e3ce6a4901259f435
  patched APK:
    hard-rom/build/apk/SettingsSmartisan-darkmode-ui.apk
  sha256:
    3b232687bfd3205e4dc6daf43be12dc09b61f3eda8644eaa9dad18d231d9f92d
  implementation:
    reuses the existing hidden switch_dc row in BrightnessSettingsFragment;
    retitles it with the existing night_mode_yes resource;
    refreshes from UiModeManager.getNightMode();
    writes through UiModeManager.setNightModeActivated(boolean).
  scope:
    code-only classes.dex replacement; no resources.arsc change.
  status:
    shared_blocks-safe offline image checks passed; not flash-authorized until
    v0.6 passes live.
```

SettingsSmartisan v0.6/v0.7/v0.8 were rebuilt with the shared_blocks-safe
held-stock-inode replacement pattern after the ext4 shared-block boundary was
identified. The current offline verification report is:

```text
tools/r2-verify-settingssmartisan-offline-images.sh
hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-072027.txt
result: PASS
note: verifies sparse system_b logical slices directly; no raw-super expansion
```

Focused graph/source audit confirms the v0.8 patch shape:

```text
SettingsSmartisan BrightnessSettingsFragment.java
  fields:
    mReduceStrobeSwitch
    mReduceStrobeSwitchTips
  onCreateView():
    binds R.id.switch_dc and R.id.switch_dc_tips
    stock code only makes switch_dc visible when !isDarwin && isSupportDC()
  onSupportVisible():
    stock code refreshes switch_dc from Settings.Global.reduce_screen_strobe
  onCheckedChanged():
    stock code writes reduce_screen_strobe and calls Calibration

SettingsSmartisan resources/res/layout/brightness_setting.xml
  switch_dc and switch_dc_tips already exist and are android:visibility="gone"
```

Because the R2 is darwin, reusing `switch_dc` is a conservative UI carrier: the
row exists in resources and code, but stock display settings do not normally
surface it on this device. The real risk is no longer resource ID creation; it
is proving the SettingsSmartisan core-APK trust gate and ensuring the patched
handler no longer calls the old DC-strobe path.

### Native QS Integration

SmartisanSystemUI remains a RED target:

```text
package: com.android.systemui
partition: system_ext
sharedUserId: android.uid.systemui
coreApp=true
```

The correct native shape is now clearer:

```text
SystemUI:
  QSTileHost.createTile("toggleDarkMode")
  -> com.android.systemui.qs.tiles.DarkModeTile

SettingsSmartisan:
  QuickWidgetFactory.getWidget("toggleDarkMode")
  -> render a normal Smartisan quick-widget row for the same key

  NotificationCustomView
  -> inject toggleDarkMode into additional/default/reset candidate paths
```

Current APK-only candidate:

```text
v0.11-native-darkmode-integration-apks:
  SmartisanSystemUI patched APK:
    hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
    sha256=1b937ea392d997ac2dc84e59a2a7e62bc3a4c655c7a61bb1bf2a73cdbf91a3ad
  SettingsSmartisan patched APK:
    hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
    sha256=ebdeb3edc2630ea21d5de7a97c616a03999d66c220f6a4c4eb61c1d46c5d4817
  verifier:
    tools/r2-verify-v0.11-native-darkmode-tile-apks.sh
  report:
    hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-20260618-095726.txt
  status:
    offline APK verification passed. No super image generated and no device
    action performed.
```

The verifier was strengthened on 2026-06-18:

```text
checks:
  SmartisanSystemUI:
    only classes10.dex changed
    DarkModeTile.smali exists
    DarkModeTile calls UiModeManager.setNightModeActivated(boolean)
    DarkModeTile has setNightMode(int) fallback
    DarkModeTile reads UiModeManager.getNightMode()
    QSTileHost has a "toggleDarkMode" branch that constructs DarkModeTile

  SettingsSmartisan:
    only classes.dex and classes2.dex changed
    BrightnessSettingsFragment has getUiModeManager(), onDarkModeChanged(), and
    setDarkModeActivated(boolean)
    BrightnessSettingsFragment calls UiModeManager.setNightModeActivated(boolean)
    BrightnessSettingsFragment reads UiModeManager.getNightMode()
    hidden switch_dc row is reused with the night_mode_yes title
    old reduce_screen_strobe/Calibration path is absent
    QuickWidgetFactory renders "toggleDarkMode" as a QuickWidget
    NotificationCustomView appends "toggleDarkMode" into additional/default/reset
    candidate paths through appendDarkModeCandidate()

evidence:
  hard-rom/inspect/v0.11-native-darkmode-tile/smali-evidence-20260618-095726/
```

This improves confidence that the APK-only candidate implements the intended
native route. It still does not prove PackageManager/shared-UID live acceptance
or SystemUI boot behavior; those remain behind v0.6 Settings no-op and
SystemUI certprobe no-op live gates.

Focused graph/source audit adds two constraints:

```text
SmartisanSystemUI QSTileHost.createTile(String)
  maps known Smartisan toggle... keys to native tile classes
  accepts IntentTile specs
  accepts CustomTile specs through CustomTile.PREFIX

SettingsSmartisan QuickWidgetFactory.getWidget(Context, String)
  renders only known Smartisan toggle... keys in the quick-widget editor

SettingsProvider
  seeds expanded_widget_buttons from def_notification_widget_buttons
  stores expanded_widget_buttons_additional
  seeds Settings.Secure.ui_night_mode=1 during the stock upgrade path
  upgrade code can clean duplicate/dirty widget button data

SettingsUtil / SettingsSmt
  builds additional widget candidates from SettingsSmt.NOTIFICATION_WIDGET
  stock SettingsSmt.NOTIFICATION_WIDGET does not include toggleDarkMode
  stock phone default widget list already has 20 entries
  backup/restore can split widget lists into first 20 plus additional entries
```

Therefore a custom QS TileService is valid for backend probing, but the final
native Smartisan route should use one new stable `toggleDarkMode` key across
SystemUI creation, SettingsSmartisan quick-widget rendering, and any optional
default widget seeding. If default visibility is required, `toggleDarkMode`
must replace an existing first-page default tile, be placed through a controlled
live data migration, or gain an explicit candidate-list path; it should not be
blindly appended to the stock 20-item phone default.

Safer QS order from here:

```text
1. Prove v0.5-control if a live backend/permission probe is still useful.
2. Run tools/r2-darkmode-live-state-audit.sh on the booted device and capture
   current UiMode/QS settings before choosing default seeding or migration.
3. Use tools/r2-darkmode-qs-strategy-audit.py to choose editor/additional,
   default-visible, or live-migration route explicitly.
4. Keep the v0.11 editor/additional route behind the SettingsSmartisan and
   SmartisanSystemUI live no-op gates; NotificationCustomView candidate
   injection is already offline-proven.
5. Prove v0.6-settings-noop before any real SettingsSmartisan behavior patch.
6. Build and prove a separate SmartisanSystemUI no-op replacement gate.
7. Only after both core-APK gates pass live, build an exact-current v0.11 ROM
   candidate that replaces both APKs. Default seeding of toggleDarkMode is a
   separate SettingsProvider/resource decision, not part of the current APK-only
   candidate.
```

The SystemUI no-op gate now exists as an offline-verified ROM candidate:

```text
SmartisanSystemUI-certprobe-noop.apk:
  hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk
  sha256=654ff82819cf6a7bf42a3463cb9559196f871234800ad74ee0030963ce487d69
  build=tools/r2-build-systemui-certprobe-noop-apk.sh
  verify=tools/r2-verify-systemui-certprobe-noop-apk.sh
  result=PASS; one-byte same-size APK v2 magic patch, 6137 ZIP/JAR entries
  byte-identical, keytool/jarsigner still read the Smartisan Android cert.

SystemUI no-op ROM:
  hard-rom/build/super-otatrust-systemui-certprobe-noop-exact-current.sparse.img
  sha256=836e8e7d2377580dc6237b617471084710d6b90c649f764b5f09681fd459cc60
  build=tools/r2-hardrom-build-systemui-certprobe-noop.sh
  verify=tools/r2-verify-systemui-certprobe-noop.sh --offline-image
  report=hard-rom/inspect/systemui-certprobe-noop/verify-systemui-certprobe-noop-offline-20260618-072149.txt
  result=PASS; sparse system_ext_b logical slice matches system_ext image, and
  SmartisanSystemUI.apk inside it matches the same-size no-op APK.
  status=not flashed; explicit user confirmation required.
```

## Language Route

### Source-Coupling Audit

The language route now has a dedicated read-only source audit:

```text
tools/r2-language-source-coupling-audit.py
docs/research/language-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-source-coupling-audit.tsv
```

Current result:

```text
findings=25
stock_visible_picker_coupled_to_assets=1
settings_locale_resource_coupling=1
stock_framework_picker_coupled_to_assets=1
stock_system_asset_source_mapped=1
stock_package_asset_source_mapped=1
stock_resource_fallback_coupled_to_assets=1
stock_framework_locale_arrays_broad=1
stock_android_static_overlay_mapped=1
stock_locale_resources_present=4
stock_non_ui_locale_coupling=3
candidate_proven_offline=5
coverage_measured_incomplete=1
full_coverage_measured_incomplete=1
missing_live_gate=2
missing_rom_image=1
```

The language route also has an implementation map and live-state audit:

```text
docs/research/language-prune-integration-map.md
tools/r2-language-live-state-audit.sh
hard-rom/inspect/language-live-state/
```

The map defines two separate policies:

```text
visible system languages:
  en-US
  zh-Hans-CN
  zh-Hant-TW

first-stage resource retention:
  keep en* and zh*
  remove non-English/non-Chinese resource configs
```

The live-state audit is required before validating a language build because it
checks current locale properties, activity configuration, package code paths,
and whether any target ROM package is shadowed by an updated `/data/app` copy.

This confirms that the language goal is not one switch. The visible Smartisan
Settings list, the framework system AssetManager locale set, per-package
resource tables, APK-only probes such as v0.14a/v0.14b/v0.14c/v0.15a/v0.15b/
v0.16a, static android overlays, and non-UI telephony/SIM locale readers are coupled but
distinct. That is why v0.7, v0.10, v0.12, v0.13, the current APK-only manifest
batch, and the remaining APK-prune batches must stay staged instead of being
collapsed into a single broad patch.

### Picker Evidence

Smartisan's visible language picker does not use only
`android.R.array.supported_locales`:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter(Context)
  Resources.getSystem().getAssets().getLocales()
  sort locales
  keep strings where length == 5
  create LocaleInfo rows
```

Focused source audit confirms this is SettingsSmartisan's own picker, not just
the AOSP framework picker:

```text
SettingsSmartisan inputmethod/LocalePickerFragment.java
  constructAdapter(Context):
    String[] locales = Resources.getSystem().getAssets().getLocales()
    Arrays.sort(locales)
    for each locale string:
      if str.length() == 5:
        new Locale(language, country)
        create LocaleInfo row
```

`Resources.getSystem()` is backed by the zygote system AssetManager:

```text
AssetManager.createSystemAssetsInZygoteLocked()
  /system/framework/framework-res.apk
  /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
  immutable static overlays targeting android
```

So an overlay of `supported_locales` is incomplete. It may affect AOSP locale
editor paths, but it cannot hide locales compiled into the framework asset set
that `AssetManager.getLocales()` returns.

### Current Candidate

v0.7 is the correct first behavior patch after v0.6:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  skip ja_JP
  skip ko_KR
  before LocaleInfo row creation
```

This hides Japanese and Korean from the visible Smartisan picker while avoiding
an early-boot `framework-res.apk` patch.

It is not a full resource prune. Non-English/non-Chinese resource directories
still exist in framework and app resource packages.

### Full Hard Prune

The generated locale inventory currently shows:

```text
decoded APK/resource packages scanned: 289
packages with locale-qualified values dirs: 190
packages with Japanese/Korean resource dirs: 175
framework-res visible regioned locales: en_US, ja_JP, ko_KR, zh_CN, zh_TW
framework-smartisanos-res locales: ja, ko, zh_CN, zh_TW
```

The current coverage audit makes the hard-prune boundary explicit:

```text
ja/ko subset script:
  tools/r2-locale-prune-coverage-audit.py
ja/ko subset report:
  docs/research/locale-prune-coverage-audit.md
ja/ko subset tsv:
  reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv
ja/ko subset result:
  stock ja/ko resource packages: 175 packages, 509 dirs
  covered by v0.2/v0.4 deletion or v0.10/v0.13 hard-prune candidates:
    29 packages, 119 dirs
  v0.7 visible-filter only, not resource-pruned:
    1 package, 6 dirs
  remaining hard-prune work:
    145 packages, 384 dirs
  first safe offline frontier:
    19 small GREEN/YELLOW APK resources.arsc prune candidates
  v0.13 completed minimal-exposure system-image batch:
    3 packages:
      com.android.protips
      com.android.printservice.recommendation
      com.android.hotspot2.osulogin

full English/Chinese-only script:
  tools/r2-language-full-prune-coverage-audit.py
full English/Chinese-only report:
  docs/research/language-full-prune-coverage-audit.md
full English/Chinese-only tsv:
  reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv
full English/Chinese-only result:
  stock non-English/non-Chinese resource packages: 179 packages, 5650 dirs
  ja/ko subset: 515 dirs
  other non-target languages: 5135 dirs
  covered by deletion or v0.10/v0.13 hard-prune candidates:
    29 packages, 798 dirs
  visible-filter only, not resource-pruned:
    1 package, 81 dirs
  APK-only built offline, not ROM coverage:
    6 packages, 87 dirs
  remaining full language-prune work:
    149 packages, 4771 dirs
```

True pruning should be staged:

```text
Stage L1:
  prove v0.7 visible picker filtering.

Stage L2:
  prune Japanese/Korean resources from low-risk non-core APKs only, one small
  package group at a time, with original-cert-preserving APK surgery and
  package preflight.
  Current generic APK-level tool:
    tools/r2-build-apk-locale-prune.sh
  Verified offline samples:
    com.android.protips
      hard-rom/build/apk/com.android.protips-locale-prune-en-zh.apk
      sha256=12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d
      removed values-ja and values-ko
      output matches the earlier Protips-only script exactly
    com.android.printservice.recommendation
      hard-rom/build/apk/com.android.printservice.recommendation-locale-prune-en-zh.apk
      sha256=3d92952e74308a3402e0debb5a0ca0a1c909b5cc1990968ccfcbe73377ceb806
      removed values-ja and values-ko
    com.android.hotspot2.osulogin
      hard-rom/build/apk/com.android.hotspot2.osulogin-locale-prune-en-zh.apk
      sha256=4e3059205ea37596aa9957f6b96a26517eeb09b2b7055d15344edf70e4dfb65c
      removed values-ja and values-ko
    com.android.printspooler
      hard-rom/build/apk/com.android.printspooler-locale-prune-en-zh.apk
      sha256=a2ff64e2c2d2b2587a92f04169b2c677c718c3c8a76e411a7f1270f5d42b9555
      removed 77 non-English/non-Chinese locale dirs and kept 9 en/zh dirs
    com.android.wallpaper.livepicker
      hard-rom/build/apk/com.android.wallpaper.livepicker-locale-prune-en-zh.apk
      sha256=aef8b6bcd7d76de0448b1c70e4239173c079f998f8090bf49084acff95cbd0d2
      removed values-ja and values-ko
    com.android.htmlviewer
      hard-rom/build/apk/com.android.htmlviewer-locale-prune-en-zh.apk
      sha256=c9535948e1369eb51c65325931075fa96fdca97f5cb3add57ee57ed591e753ac
      removed values-ja and values-ko
    com.android.dreams.basic
      hard-rom/build/apk/com.android.dreams.basic-locale-prune-en-zh.apk
      sha256=7fdb6f4a33e34ac32277642e52f7d3afe52255b492a3a5f90ada85698b796b42
      removed values-ja and values-ko
    com.android.dreams.phototable
      hard-rom/build/apk/com.android.dreams.phototable-locale-prune-en-zh.apk
      sha256=d1fbbbb10ba19b0dbcd2938fecd9d220a52ff921fc53c637e936362e0e6789a2
      removed values-ja and values-ko
    com.qualcomm.qti.confdialer
      hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh.apk
      sha256=31828ce79656c9aa3e3e83d30f387cb740a3e36b299bad65d3f40d171e06c441
      removed values-ja and values-ko, kept values-zh/values-zh-rCN/values-zh-rTW
  Tier1a verifier:
    tools/r2-verify-tier1a-locale-prune-apks.sh
    hard-rom/inspect/tier1a-locale-prune-apks/verify-tier1a-locale-prune-apks-20260618-080340.txt
    result=PASS
  APK-only manifest verifier:
    tools/r2-verify-apk-only-locale-prune-candidates.sh
    hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-111308.txt
    result=PASS_OFFLINE_APK_ONLY_BATCH
  In verified APK-level samples:
    changed entry: resources.arsc only
    classes.dex and AndroidManifest.xml are byte-identical to stock
    signature boundary: SHA-256 digest error for resources.arsc
  ROM builder prepared but not run:
    tools/r2-hardrom-build-v0.9-protips-locale-prune.sh

Stage L3:
  build dedicated framework-res resource-table probes.
  Current result:
    tools/r2-build-framework-res-locale-probe.sh
    noop output:
      hard-rom/build/apk/framework-res-rebuild-noop.apk
      sha256=319cd91f8a29c88e8c1058a15bdcd2fbd159a82107add92daf87cbd40fd4240a
    locale-prune output:
      hard-rom/build/apk/framework-res-locale-prune-en-zh.apk
      sha256=10fc36befd0acdb1a1530c6e676cc154170de1bebac5d7eb84b73c24f164aedd
    locale-prune behavior:
      removes 61 non-English/non-Chinese framework-res locale resource dirs,
      including raw-ja and raw-ko
      keeps 63 English/Chinese locale resource dirs
      narrows supported_locales to en-US, zh-Hans-CN, zh-Hant-TW
      removes ar_EG from special_locale_codes/special_locale_names
    verification:
      AndroidManifest.xml remains byte-identical to stock
      public.xml diff after decode/rebuild is empty
      binary resources.arsc policy check reports only en/zh locale chunks
      ordinary keytool/jarsigner fail at resources.arsc digest as expected
    status:
      offline resource-table control passed
      superseded by v0.10 combined framework/product ROM candidate for image
      packaging evidence
      not flashed or live-verified

Stage L4:
  package framework-res, framework-smartisanos-res, and android static overlay
  locale prunes into a real exact-current super candidate.
  Current result:
    tools/r2-hardrom-build-v0.10-framework-locale-prune.sh
    tools/r2-verify-v0.10-framework-locale-prune.sh
    super sparse:
      hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
      sha256=62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
    system image:
      sha256=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351
    product image:
      sha256=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2
    patched files:
      framework-res.apk
      framework-smartisanos-res.apk
      five product DisplayCutoutEmulation static overlays targeting android
    verification:
      offline image verification passed
      all seven APKs dumped from final system/product images match expected
      all seven dumped APK resources.arsc files pass the en/zh binary locale
      policy verifier
      post-fsck APK hash and ZIP integrity are enforced during build
    ext4 boundary:
      system/product images use shared_blocks
      debugfs rm + write is unsafe for these images because it can free shared
      stock blocks before writing the replacement
      v0.10 uses a hidden hard-link stock-inode hold before swapping the public
      path to the new inode
    status:
      not flashed or live-verified
      RED early-boot framework resource candidate

Stage L4a:
  prove the smaller framework-res replacement boundary before v0.10.
  Prepared gate:
    tools/r2-hardrom-build-v0.12-framework-res-noop.sh
    tools/r2-verify-v0.12-framework-res-noop.sh
  Expected replacement:
    hard-rom/build/apk/framework-res-rebuild-noop.apk
    sha256=319cd91f8a29c88e8c1058a15bdcd2fbd159a82107add92daf87cbd40fd4240a
  Scope:
    replaces only /system/framework/framework-res.apk with a no-op rebuilt
    resources.arsc in the stock APK shell
  Status:
    system image built with BUILD_SUPER=0 and verified offline
    flashable sparse super built by direct sparse rewrite and verified offline
  Output:
    hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img
    sha256=d5c63890f27f6609b09667cc0bee0dd4b55c5c335abeb530650c16fbce9d94d9
    hard-rom/build/system-otatrust-v0.12-framework-res-noop.img
    sha256=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0
    verifier:
      tools/r2-verify-v0.12-framework-res-noop.sh --offline-image
    report:
      hard-rom/inspect/v0.12-framework-res-noop/verify-v0.12-offline-image-20260618-071439.txt
  Sparse note:
    v0.4 sparse system_b crosses FILL chunks, so v0.12 was produced with
    tools/r2-sparse-partition-patch.py rewrite-sparse mode instead of raw super
    expansion or raw-only clone patching.
  Purpose:
    if this boots live, v0.10 risk narrows from "framework-res replacement
    itself may break early boot" to "language-pruned resources may break early
    boot or runtime locale/resource expectations"

Stage L4b:
  prove a low-exposure package resource-prune batch at ROM system_b image level.
  Prepared gate:
    tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh
    tools/r2-verify-v0.13-tier1a-locale-prune.sh
  Scope:
    replaces only:
      /system/app/Protips/Protips.apk
      /system/app/PrintRecommendationService/PrintRecommendationService.apk
      /system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk
    with previously verified English/Chinese-only resources.arsc APK variants.
  Status:
    system_b image built with BUILD_SUPER=0 and verified offline.
    flashable sparse super not built yet because local free space is tight.
    not flashed or live-verified.
  Output:
    hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img
    sha256=e77643153a9e03fc48b5e47a0841c6322dc390eb3381ff40a24e98ae03f905bb
    verifier:
      tools/r2-verify-v0.13-tier1a-locale-prune.sh --offline-system-image
    report:
      hard-rom/inspect/v0.13-tier1a-locale-prune/verify-v0.13-offline-system-image-20260618-081444.txt
  Sparse note:
    tools/r2-sparse-partition-patch.py now supports --extract-image, so v0.13
    avoided a full raw-super expansion while still reconstructing FILL-backed
    logical partition bytes correctly.
  Purpose:
    this is the package-level hard-prune lane for low-exposure APK resources.
    It does not replace the v0.12/v0.10 framework live gates.

Stage L5:
  handle framework-smartisanos-res without aapt2 rebuild.
  Current result:
    tools/r2-arsc-prune-locales.py
    tools/r2-build-smartisanos-framework-res-locale-probe.sh
    output:
      hard-rom/build/apk/framework-smartisanos-res-locale-prune-en-zh.apk
      sha256=eefab348089210bba963c69f5966052a65b11fdd1bf198084c60cc005a45b228
    raw rebuild failure:
      aapt2 cannot link public ^attr-private symbols at IDs
      0x020b0000..0x020b0004
    binary prune behavior:
      removes 6 ja/ko RES_TABLE_TYPE_TYPE chunks:
        string ja, string ko, dimen ja, array ja, array ko, integer ja
      keeps zh-rCN and zh-rTW resources
    verification:
      decoded output has no values-ja or values-ko dirs
      AndroidManifest.xml remains byte-identical to stock
      public.xml diff is 0 bytes
      ^attr-private public IDs remain 0x020b0000..0x020b0004
      ordinary keytool/jarsigner fail at resources.arsc digest as expected
    status:
      offline resource-table control passed
      incorporated into v0.10 image packaging
      not flashed or live-verified
```

## Core APK Trust Gate

Source review confirms why the current v0.6 gate is necessary:

```text
PackageManagerService scanSystemPartition
  -> skipVerify=true
  -> ParsingPackageUtils.getSigningDetails(..., skipVerify=true)
  -> ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)

PackageManagerServiceUtils.verifySignatures()
  -> still checks the parsed cert against previous package signing details
  -> still checks sharedUserId signing details
```

Practical meaning:

```text
unsafeGetCertsWithoutVerification is not a signature bypass.
It only makes original-cert-preserving modified system APKs plausible.
The live device must prove that path before Settings/SystemUI/framework patches.
```

Current gate variants:

```text
v0.6-settings-noop:
  original-cert-readable no-op SettingsSmartisan replacement.

v0.7-locale-filter:
  real SettingsSmartisan behavior patch.
  classes.dex digest is intentionally invalid under ordinary jarsigner checks.
  It depends on the system-partition certs-only path, so it waits behind v0.6.

v0.8-darkmode-ui:
  real SettingsSmartisan behavior patch.
  exposes a native dark-mode switch without adding resources.arsc changes.
  It depends on the same system-partition certs-only path, so it waits behind
  v0.6.
```

## Next Executable Sequence

Recommended order:

```text
1. Flash and verify v0.6-settings-noop.
2. If v0.6 passes, flash and verify v0.7-locale-filter.
3. Separately flash and verify v0.5-control for dark-mode permission and QS
   TileService behavior.
4. Run tools/r2-darkmode-live-state-audit.sh while the stable ROM is booted so
   default QS and ui_night_mode state are recorded before native QS seeding.
5. If v0.6 passes, consider flashing v0.8-darkmode-ui, then run
   tools/r2-verify-v0.8-darkmode-ui.sh --read-only before any interactive
   Settings launch or night-mode exercise.
6. For true language resource pruning, v0.10 is now the first complete offline
   image candidate. Prefer first flashing v0.12 as the smaller framework-res
   replacement gate. If v0.12 passes live, then flash v0.10 only as an
   explicitly authorized RED framework-resource test with v0.4 local rollback
   ready, then verify with
   tools/r2-verify-v0.10-framework-locale-prune.sh --read-only.
```

I am confident enough to implement the Settings dark-mode switch and the visible
language filter. I am now confident enough to build a full offline
framework/product language-resource prune candidate without corrupting ext4
shared_blocks. I am not yet claiming it is live-safe until v0.10 boots and
passes device verification.
