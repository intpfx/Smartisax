# System Modification Gates

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Debloat Strategy

Current next-candidate document:

```text
docs/README.md
docs/v0.5-debloat-candidates.md
```

Use this order of aggression:

```text
1. Disabled product overlays and test/demo apps
2. Optional user features such as print, dreams, weather, wallet, cloud
3. Smartisan AI/search/text assistant stack
4. Telemetry/push/tracking and OEM add-ons
5. Input/location/security/file stacks only after focused dependency review
6. Framework/services/SystemUI/Launcher/Keyguard only after graph/reverse work
```

For updated-system packages whose current code path is under `/data/app`, ROM
removal alone is not enough. Plan post-boot package/data cleanup and validation.

Keep at least one working keyboard. Do not remove both Smartisan IME and
LatinIME in the same test.

## Source Intelligence And Modification Gate

Before new package, overlay, resource, framework, or same-package replacement
work, use the static ROM knowledge base and focused graph:

```text
reverse/smartisan-8.5.3-rom-static/
reverse/smartisan-8.5.3-rom-static/modification-confidence-map.md
reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/
docs/research/resource-loading-map.md
docs/research/system-modification-playbook.md
docs/research/system-modification-route-audit.md
docs/research/language-prune-integration-map.md
docs/research/darkmode-integration-map.md
```

Run the read-only package preflight first:

```bash
tools/r2-rom-mod-preflight.py <package> --action inspect
tools/r2-rom-mod-preflight.py <package> --action delete
tools/r2-rom-mod-preflight.py <package> --action replace
tools/r2-rom-mod-preflight.py <package> --action overlay
```

Treat the preflight level as a gate:

```text
GREEN/YELLOW: small isolated hard-ROM experiment may be acceptable after normal
              rollback and image checks.
ORANGE: source and graph review are mandatory before build.
RED/BLOCK: do not build or flash from package-index evidence alone.
```

For route-level planning, run the read-only system modification route audit:

```bash
tools/r2-system-modification-route-audit.py
tools/r2-system-modification-route-audit.py --package-action com.android.phone:replace
```

Canonical output maps current change classes, static risk levels, required
live/no-op gates, and next safe steps. Ad hoc package-action output goes under
`hard-rom/inspect/system-modification-route-audit/` so the canonical route
matrix remains stable.

Use graphify as an impact navigator, not as proof. Confirm graph findings with
static indexes, decoded manifests/resources, source paths, partition extents,
and post-boot device checks.

For resource, language, overlay, icon-sensitive package, or same-package
replacement work, read `docs/research/resource-loading-map.md` first. The
current model is that zygote system assets load framework-res,
framework-smartisanos-res, and immutable framework idmaps; app assets layer
package/split/lib/overlay resources on top; and Smartisan's icon redirection
state participates in ResourcesImpl cache freshness.

For any new delete, same-package replacement, core APK patch, app resource
prune, framework resource replacement, SettingsProvider default/migration
change, or boot UI surface change, read
`docs/research/system-modification-playbook.md` first. Do not transfer live-gate
confidence from one core package to another; SettingsSmartisan, SystemUI,
SettingsProvider, Keyguard, Launcher, Phone, PackageInstaller, and framework
assets each need their own gate.

Before live testing a built candidate, use the read-only flash preflight:

```bash
tools/r2-live-flash-preflight.sh v0.12-framework-res-noop
tools/r2-live-flash-preflight.sh v0.10-framework-locale-prune
tools/r2-live-flash-preflight.sh v0.25-settings-noop-on-v0.24
tools/r2-live-flash-preflight.sh systemui-certprobe-noop-on-v0.24
tools/r2-live-flash-preflight.sh v0.11-native-darkmode
tools/r2-live-flash-preflight.sh v0.11.1-native-darkmode-settings-row
tools/r2-live-flash-preflight.sh v0.24-cleaner-apk-only-locale-prune
tools/r2-live-flash-preflight.sh v0.22-all-apk-only-locale-prune
tools/r2-live-flash-preflight.sh v0.6-settings-noop
tools/r2-live-flash-preflight.sh systemui-certprobe-noop
```

The preflight checks candidate hashes, v0.4 rollback readiness, latest offline
evidence, verifier scripts, and adb/fastboot state when available. It never
flashes, reboots, erases misc, or changes `/data`.

Before claiming the two active user-facing goals are close to complete, run the
read-only dark-mode live-state audit, dark-mode source-coupling audit,
dark-mode QS strategy audit, dark-mode persistence audit, language live-state
audit, language full-prune coverage audit, language next-batch plan,
language P1 source-review audit, language source-coupling audit, and top-level
readiness audit:

```bash
tools/r2-darkmode-live-state-audit.sh
tools/r2-darkmode-source-coupling-audit.py
tools/r2-darkmode-qs-strategy-audit.py
tools/r2-darkmode-persistence-audit.py
tools/r2-language-live-state-audit.sh
tools/r2-language-full-prune-coverage-audit.py
tools/r2-language-next-batch-plan.py
tools/r2-language-p1-source-review-audit.py
tools/r2-language-source-coupling-audit.py
tools/r2-system-modification-route-audit.py
tools/r2-system-mod-readiness-audit.py
```

It writes:

```text
docs/research/darkmode-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-source-coupling-audit.tsv
docs/research/darkmode-qs-strategy-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-qs-strategy-audit.tsv
docs/research/darkmode-persistence-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/darkmode-persistence-audit.tsv
docs/research/darkmode-integration-map.md
docs/research/language-prune-integration-map.md
hard-rom/inspect/language-live-state/
docs/research/language-full-prune-coverage-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv
docs/research/language-next-batch-plan.md
reverse/smartisan-8.5.3-rom-static/manifest/language-next-batch-plan.tsv
docs/research/language-p1-source-review-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-p1-source-review-audit.tsv
docs/research/language-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/language-source-coupling-audit.tsv
docs/research/system-modification-route-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/system-modification-route-audit.tsv
docs/research/system-modification-readiness-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/system-modification-readiness-audit.tsv
```

Treat this audit as the guardrail for the current objective. Offline-proven APK
or image candidates are not live completion. Missing dark-mode live-state,
missing language live-state, missing live no-op gates, and remaining ja/ko
resource packages mean the objective is still incomplete.

## Core APK Signature Gate

Do not replace core shared-UID APKs with unsigned or self-signed rebuilds.
This includes:

```text
SettingsSmartisan.apk
SettingsProvider.apk
SmartisanSystemUI.apk
framework-res.apk
framework-smartisanos-res.apk
```

Current source finding:

```text
system partition scan -> skipVerify=true
ParsingPackageUtils.getSigningDetails(..., skipVerify=true)
  -> ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)
PackageManagerServiceUtils.verifySignatures()
  -> still compares previous package and shared-user signing details
```

Therefore a possible deep-modification route is original-cert-preserving
system-partition patching, not re-signing with our own key. Before any real
Settings/SystemUI/framework behavior patch, build and flash a no-op replacement
probe for that exact APK and verify boot, package state, shared UID, Settings
launch, SELinux/logcat, and rollback. Use:

```bash
tools/r2-apk-signature-boundary-check.sh <apk>
```

Reference:

```text
docs/research/system-apk-signature-boundary.md
```

Current SettingsSmartisan gate:

```text
v0.6-settings-noop:
  no-op replacement; keytool/jarsigner can still read the Smartisan cert.
  historical v0.4-based no-op gate. Do not use as the next current-line dark
  mode gate unless deliberately rolling back to v0.4.

v0.25-settings-noop-on-v0.24:
  current v0.24-baseline no-op replacement; keytool/jarsigner can still read
  the Smartisan cert. This gate has passed live on the dark-mode line.
  Preflight:
    tools/r2-live-flash-preflight.sh v0.25-settings-noop-on-v0.24
  Post-flash verifier:
    SETTINGS_NOOP_VARIANT=v0.25-settings-noop-on-v0.24 tools/r2-verify-v0.6-settings-noop.sh --read-only
  Latest live evidence:
    hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-20260618-155616.txt
    PASS; launcher focused and keyguard not showing.

v0.7-locale-filter:
  classes.dex replacement; keytool/jarsigner report SHA-256 digest error for
  classes.dex. It relies on the source-confirmed system-partition certs-only
  scan path and must not be flashed until the current-line behavior image is
  rebuilt after the required no-op gates.
  APK semantic verifier:
    tools/r2-verify-settingssmartisan-locale-filter-apk.sh
    hard-rom/inspect/v0.7-locale-filter/verify-settingssmartisan-locale-filter-apk-20260618-073901.txt
    PASS; verifies concrete smali skip logic for ja_JP and ko_KR in
    LocalePickerFragment.constructAdapter().

v0.8-darkmode-ui:
  classes.dex replacement; keytool/jarsigner report SHA-256 digest error for
  classes.dex. It reuses an existing Settings row and does not alter
  resources.arsc. It must not be flashed until the current-line behavior image
  is rebuilt after the required no-op gates.

All three SettingsSmartisan exact-current builders now use the shared_blocks-
safe replacement pattern and post-fsck APK hash plus ZIP verification:

  tools/r2-hardrom-build-v0.6-settings-noop.sh
  tools/r2-hardrom-build-v0.7-locale-filter.sh
  tools/r2-hardrom-build-v0.8-darkmode-ui.sh
  tools/r2-verify-settingssmartisan-offline-images.sh

Latest offline report:
  hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-072027.txt
  result=PASS; uses sparse logical-slice verification instead of raw-super
  expansion
```

Current native dark-mode QS candidate:

```text
v0.11-native-darkmode:
  SmartisanSystemUI classes10.dex replacement; adds
  com.android.systemui.qs.tiles.DarkModeTile and maps toggleDarkMode in
  QSTileHost.createTile().

  SettingsSmartisan classes.dex/classes2.dex replacement; exposes a native
  dark-mode row in BrightnessSettingsFragment, teaches QuickWidgetFactory to
  render toggleDarkMode in the Smartisan quick-widget editor, and teaches
  NotificationCustomView to inject toggleDarkMode into additional/default/reset
  candidate paths.

  ordinary keytool/jarsigner report SHA-256 digest errors for the changed dex
  files. This is expected for stock-shell dex replacement, but it is not live
  proof.

    tools/r2-build-native-darkmode-tile-apks.sh
    tools/r2-verify-v0.11-native-darkmode-tile-apks.sh
    tools/r2-hardrom-build-v0.11.1-native-darkmode-settings-row.sh
    tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh --offline-image
    tools/r2-live-flash-preflight.sh v0.11.1-native-darkmode-settings-row
    tools/r2-hardrom-build-v0.11-native-darkmode.sh
    tools/r2-verify-v0.11-native-darkmode.sh --offline-image
    tools/r2-live-flash-preflight.sh v0.11-native-darkmode

  Latest APK semantics evidence:
    hard-rom/inspect/v0.11-native-darkmode-tile/verify-v0.11-native-darkmode-tile-apks-20260618-171710.txt
    PASS; includes brightness_darkmode_row_reachability=ok so the dark-mode
    Settings row is after the Darwin :cond_5 branch target.

  Latest ROM image evidence:
    hard-rom/inspect/v0.11.1-native-darkmode-settings-row/verify-v0.11.1-native-darkmode-settings-row-offline-image-20260618-172253.txt
    PASS; super sparse sha256=2f1a4d8b8579551bf04246d00099f15c5c5a42146336cd6a00d129bbcffb8fa0.
    This v0.11.1 image has now also passed live device read-only verification
    and a Settings row UI visibility probe on B slot.

  Previous live ROM image evidence:
    hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-offline-image-20260618-163441.txt
    PASS; super sparse sha256=a0afc5b979db769137a01d581848b3d30f653197665f5ce0958b4b2809a05ebb.
    Device verifier:
    hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-device-20260618-165423.txt
    PASS; the behavior ROM boots on B slot and patched APK hashes match live.

  Flash preflight:
    tools/r2-live-flash-preflight.sh v0.11.1-native-darkmode-settings-row
    PASS; required confirmation phrase is:
    确认刷入 v0.11.1-native-darkmode-settings-row B 槽

  Source-coupling audit:
    tools/r2-darkmode-source-coupling-audit.py
    docs/research/darkmode-source-coupling-audit.md
    PASS-equivalent structured result: stock framework backend and reusable
    dark-mode resources exist; stock Settings/SystemUI entries are missing;
    SettingsProvider/QS persistence is mapped; default toggleDarkMode visibility
    is a separate seeding decision; the stock phone default QS list is already
    at the 20-tile cap; SettingsSmt.NOTIFICATION_WIDGET does not know
    toggleDarkMode, so v0.11 uses a SettingsSmartisan-local
    NotificationCustomView injection route instead of changing smartisanos.jar
    first; v0.11.1 is call-site proven offline; the read-only dark-mode
    live-state audit captured current UiMode/QS settings; the SettingsSmartisan
    and SmartisanSystemUI live no-op gates have passed; the previous combined
    exact-current v0.11 ROM image is built, flashed, and live-verified at the
    boot/package/hash level. The reversible functional test now proves
    UiModeManager night yes/no and SystemUI toggleDarkMode tile creation on
    the live device, with original QS data restored. The next live target is
    v0.11.1 because it fixes the Settings row reachability bug.

  QS strategy audit:
    tools/r2-darkmode-qs-strategy-audit.py
    docs/research/darkmode-qs-strategy-audit.md
    PASS-equivalent structured result: phone default list has 20 entries;
    toggleDarkMode is absent from stock SystemUI, Settings editor, SettingsSmt
    registry, and defaults; editor/additional integration is now
    candidate-injection proven offline through NotificationCustomView;
    SettingsSmt remains unpatched; default-visible integration requires
    replacing one existing phone key, not appending a 21st; live-state capture
    is still required before displacement or migration.

  Persistence audit:
    tools/r2-darkmode-persistence-audit.py
    docs/research/darkmode-persistence-audit.md
    PASS-equivalent structured result: stock SettingsProvider defaults and the
    SettingsSmt registry omit toggleDarkMode; stock SettingsSmartisan
    reset/checkValidity paths can fall back to target-missing defaults; v0.11
    local NotificationCustomView injection is offline-proven for additional,
    reset, and save paths; backup/restore normalization is not target-aware;
    the first behavior ROM should stay editor/additional-first and defer
    default-visible policy until live no-op gates and live state are available.

  Integration map:
    docs/research/darkmode-integration-map.md
    Source-backed route for Settings row, UiModeManager backend, native
    toggleDarkMode key, Smartisan quick-widget editor, SettingsProvider
    defaults, reset/restore normalization, and the exact live-state markers
    required before default seeding or migration.

  The verifier now checks concrete smali semantics, not only strings:
    SystemUI-DarkModeTile.smali
      UiModeManager.setNightModeActivated(boolean)
      UiModeManager.setNightMode(int) fallback
      UiModeManager.getNightMode()
      long-click intent to BrightnessSettingsActivity

    SystemUI-QSTileHost.smali
      "toggleDarkMode" branch constructs DarkModeTile

    Settings-BrightnessSettingsFragment.smali
      setDarkModeActivated(boolean)
      onDarkModeChanged()
      UiModeManager.getNightMode()
      hidden switch_dc row reused as the dark-mode switch
      old reduce_screen_strobe/Calibration path absent

    Settings-QuickWidgetFactory.smali
      "toggleDarkMode" renders a QuickWidget with night_mode_yes title

    Settings-NotificationCustomView.smali
      containsWidget(String, String)
      appendDarkModeCandidate(String current, String additional)
      getCurrentAdditionalQuickWidgetSettings() appends toggleDarkMode
      getDefaultAdditionalOrderSettings()/checkValidity()/save paths append
      toggleDarkMode for the additional/editor candidate route

  Both current-base no-op replacement gates have passed live independently for
  SettingsSmartisan and SmartisanSystemUI, and v0.11 has now passed live
  read-only package/hash verification plus reversible UiMode/SystemUI
  functional testing. The next dark-mode step is manual user-facing validation
  of the Settings row and Smartisan QS editor candidate behavior.
```

Current SmartisanSystemUI no-op APK gate:

```text
SmartisanSystemUI-certprobe-noop-apk:
  tools/r2-build-systemui-certprobe-noop-apk.sh
  tools/r2-verify-systemui-certprobe-noop-apk.sh
  tools/r2-hardrom-build-systemui-certprobe-noop.sh
  tools/r2-verify-systemui-certprobe-noop.sh --offline-image

  current v0.24-line output:
    hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk
    sha256=654ff82819cf6a7bf42a3463cb9559196f871234800ad74ee0030963ce487d69
    hard-rom/build/super-otatrust-systemui-certprobe-noop-on-v0.24-exact-current.sparse.img
    sha256=0749a4f19c34fa4bc89bcf1ed9a65fe027fce32479ae9b37be7a40e7a9895bfc
    hard-rom/build/system_ext-otatrust-systemui-certprobe-noop-on-v0.24.img
    sha256=133655b1b88440d942d473b1f14971acf657b379540fa12ca8fd5efe9c3d8f32

  offline verifier:
    hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-offline-20260618-154040.txt
    PASS; final sparse system_ext_b logical slice matches the system_ext image, and
    SmartisanSystemUI.apk inside that image matches the same-size no-op APK.

  system_ext_b has shared_blocks and zero free blocks, so do not use held-inode
  replacement here. The gate uses a same-size one-byte in-place APK patch.
  Use SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24 for the current
  dark-mode line. The older systemui-certprobe-noop is v0.4-based historical
  evidence. The current v0.24-line SystemUI no-op gate has passed live.
```

SystemUI supports Android `custom(...)` tile specs, but SettingsSmartisan's
quick-widget editor renders known Smartisan `toggle...` keys through
QuickWidgetFactory. Do not auto-write an unknown custom tile into
`expanded_widget_buttons` as the final native route; use a native
`toggleDarkMode` key if the SystemUI/Settings gates are being tested.
For the editor/additional route, prefer patching SettingsSmartisan's
NotificationCustomView additional/default/reset paths to inject `toggleDarkMode`
before attempting a broader smartisanos.jar SettingsSmt.NOTIFICATION_WIDGET
registry patch. v0.11 currently proves the SettingsSmartisan-local route
offline.
The combined v0.11 ROM image is also built, flashed, and live-verified at the
boot/package/hash level, and `tools/r2-darkmode-functional-test.sh --write-approved`
has proven UiMode yes/no plus SystemUI `toggleDarkMode` creation while restoring
the original `/data` settings.
For default visibility, do not blindly append `toggleDarkMode` to
`def_notification_widget_buttons`: the phone default list already has 20
entries and QSTileHost caps the first page at 20. Choose an explicit
replacement tile, a live data migration, or a patched candidate-list path after
the relevant live no-op gates pass.
