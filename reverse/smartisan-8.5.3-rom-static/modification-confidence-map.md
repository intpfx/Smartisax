# Smartisan OS 8.5.3 Modification Confidence Map

This file is the working gate for deciding whether a requested ROM change is
ready for build and flash. It connects the static ROM knowledge base, the
modification-critical graph, and the exact-current hard-ROM build flow.

Scope:

```text
device: Smartisan R2, Smartisan OS 8.5.3, Android 11
ROM layer: OTA-extracted system, system_ext, product, vendor, odm images
excluded: /data/app live updated-system APKs
current stable rollback: v0.4 hard debloat sparse image
```

## Current Source Intelligence

Static source knowledge base:

```text
reverse/smartisan-8.5.3-rom-static
partition files listed: 8332
APK/JAR/APEX targets: 430
decoded APK manifests: 289
java files: 256009
class index rows: 255808
public resource rows: 355751
review gate: Hooke V1.1 Q&A 10/10 PASS, COMPLETE
```

Modification-critical graph corpus:

```text
reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical
corpus files: 2061
missing expected files: 0
graph: 52788 nodes, 130295 edges, 1643 communities
extraction: 92% extracted, 8% inferred, 0% ambiguous
graph report:
  reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/GRAPH_REPORT.md
graph json:
  reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/graph.json
```

The graph is an impact navigator. Static indexes, decoded manifests,
resources, image extents, and live-device checks remain the evidence source.

Feature-control focused graph and locale inventory:

```text
reverse/smartisan-8.5.3-rom-static/graph-corpus/feature-control
docs/research/feature-control-map.md
docs/research/system-modification-confidence.md
tools/r2-locale-resource-inventory.py
reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv
docs/research/locale-pruning-map.md
```

## First Command

Every package-level change starts with the read-only preflight helper:

```bash
tools/r2-rom-mod-preflight.py <package> --action inspect
tools/r2-rom-mod-preflight.py <package> --action delete
tools/r2-rom-mod-preflight.py <package> --action replace
tools/r2-rom-mod-preflight.py <package> --action overlay
```

The helper reads these static indexes:

```text
packages.tsv
components.tsv
intent-filters.tsv
uses-permissions.tsv
privapp-permissions.tsv
sysconfig-packages.tsv
overlays.tsv
signatures.tsv
```

It reports package path, partition, priv-app state, sharedUserId, components,
exported components, core intents, requested permissions, privapp grants,
sysconfig references, overlays, signatures, graphify follow-up queries, and a
build gate.

## Confidence Levels

GREEN means a small hard-ROM experiment is acceptable after normal image and
rollback checks:

```text
non-priv optional package
no sensitive sharedUserId
no privapp permission entries
no sysconfig references
no overlays targeting or provided by the package
no core boot/home/browser/installer/default intent role
no graph path into keyguard, launcher, SystemUI, PackageManager, or resources
```

YELLOW means the change can be tested as a small isolated variant:

```text
exported components exist
content providers exist
BOOT_COMPLETED, VIEW, BROWSABLE, or LAUNCHER intents exist
the package is user-facing but not priv-app and has no system sharedUserId
other packages may hold shortcuts, provider data, or preferred activities
```

ORANGE means source and graph review are mandatory before build:

```text
priv-app package
privapp permission config entries
sysconfig references
sharedUserId that is not clearly harmless
package is an overlay
same-package replacement with manifest/authority/resource/ABI/signature risk
```

RED means no build or flash from package-index evidence alone:

```text
framework-res.apk or framework-smartisanos-res.apk direct repack
framework.jar, services.jar, smartisanos.jar, sys-framework.jar, sys-services.jar edits
Keyguard, SystemUI, Launcher, Settings, PackageInstaller, PermissionController
TeleService, Telecom, TelephonyProvider, InCallUI, MMS, SettingsProvider
BrowserChrome same-package replacement
packages using android.uid.system, android.uid.systemui, or android.uid.phone
```

`framework-res.apk` currently passes offline no-op and locale-prune probes, but
that does not lower the flash gate: it remains early-boot framework resource
work. `framework-smartisanos-res.apk` should use the binary resources.arsc
locale-config pruning route because apktool/aapt2 does not preserve Smartisan's
private `^attr-private` type id as a normal rebuild target.

`SettingsSmartisan.apk` remains RED for direct in-place code patches until an
original-cert-preserving no-op replacement boots cleanly. Re-signing it with
our own key is not a safe shared-UID path. The current safer path for dark-mode
control is the separate `SmartisaxControls` ROM priv-app plus a custom QS
tile. A later Settings patch should target the smaller
`BrightnessSettingsFragment` page before attempting to alter
`MainSettingsFragment` home-screen routing.

System-partition source review found a possible certs-only parsing route for
core APK experiments:

```text
PackageManagerService scanSystemPartition -> skipVerify=true
ParsingPackageUtils.getSigningDetails(..., skipVerify=true)
  -> ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)
PackageManagerServiceUtils.verifySignatures()
  -> still compares previous package and shared-user signing details
```

Use this as a gate, not as permission to patch blindly:

```text
docs/research/system-apk-signature-boundary.md
tools/r2-apk-signature-boundary-check.sh
```

BLOCK means the static KB cannot establish the target:

```text
package absent from the static ROM package index
target is actually a /data/app updated-system package
target partition or image path is unknown
```

## Modification Playbooks

### Delete A System App

Required evidence:

```bash
tools/r2-rom-mod-preflight.py <package> --action delete
tools/r2-rom-kb-query.py package <package> --exact
tools/r2-rom-kb-query.py component <package> --exact
tools/r2-rom-kb-query.py intent <package> --exact
tools/r2-rom-kb-query.py permission <package> --exact
tools/r2-rom-kb-query.py privapp <package> --exact
tools/r2-rom-kb-query.py sysconfig <package> --exact
tools/r2-rom-kb-query.py overlay <package> --exact
```

Build is acceptable only when the package path maps to a known partition image
and the rollback sparse image is present locally.

Validated example:

```text
com.smartisanos.appstore:
  preflight level: YELLOW
  reason: non-priv app, no privapp grants, no sysconfig references,
          but exported providers/components and core intents exist
  result: deletion flow was boot-valid after hard-ROM flash
```

### Replace A Same-Package APK

Treat this as RED until proven otherwise. File replacement is not enough.

Required comparisons:

```text
package name
sharedUserId
signing certificate lineage, original-cert preservation, or acceptable
system-package certs-only behavior
versionCode/versionName strategy
uses-sdk
native ABI and libraries
providers and authorities
activities, services, receivers, exported state
intent filters and preferred/default roles
permissions and app-ops expectations
public resources and resource package assumptions
data directory and package cache compatibility
```

Required source/graph areas:

```text
PackageManagerService
PackageManagerServiceSmtEx
PackageManagerServiceSmtBase
PackageParserSmtEx
PackageSetting and package restrictions
ResourcesManagerSmtEx
AssetManagerSmtEx
IconManager
OverlayManagerService
SystemConfig
target app manifest/resources
keyguard, launcher, SystemUI if the app has default/home/browser/lockscreen touchpoints
```

Known failed example:

```text
com.android.browser:
  BrowserChrome v0.3/v0.3.1 same-package replacement booted into no-lockscreen.
  The package is non-priv, but it has 241 static components, 35 exported
  components, browser VIEW/BROWSABLE/default intents, provider authorities,
  BOOT_COMPLETED/LOCALE/PACKAGE replacement receivers, and Smartisan browser
  code. Do not reuse it as a generic replacement template.
```

### Add Or Remove Product Overlays

Required evidence:

```bash
tools/r2-rom-kb-query.py overlay <target-package> --exact
tools/r2-rom-kb-query.py resource <resource-name> --exact
tools/r2-rom-mod-preflight.py <target-package> --action overlay
```

Prefer static RRO overlays under `product/overlay` for resource changes. Direct
framework resource repack remains RED until an apktool/smali/repack tier exists
and resource ID stability is verified.

Use `tools/r2-super-exact-patch.py` for product_b, system_ext_b, vendor_b, or
multi-partition super patching.

### Framework Or Services Edit

Framework and services edits are RED by default.

Minimum additional evidence before considering a build:

```text
exact decompiled class and method source paths
smali/apktool or dex patching toolchain installed and tested
boot classpath and jar signing/zip alignment behavior understood
SELinux and system_server crash rollback plan
logcat collection plan before and after boot
cold rollback image available locally or restored from SSDUSB
```

### Settings And Locale Customization

Language-list customization should not start with full ROM resource pruning.
The lowest practical first hard-ROM target is currently a SettingsSmartisan
code filter:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  Resources.getSystem().getAssets().getLocales()
  skip ja_JP and ko_KR before LocaleInfo row creation
```

This still requires the SettingsSmartisan no-op replacement gate. Static RRO
overrides of `android` arrays can affect AOSP locale paths, but Smartisan's
main visible picker enumerates `AssetManager.getLocales()` directly. The full
hard-prune route now has a v0.10 offline image candidate with binary
resources.arsc locale-policy verification, but it remains a RED early-boot
framework resource test until flashed and verified live.

Known source:

```text
framework-res.apk package android array supported_locales id 0x010700cf
v0.10 framework/product hard-prune candidate:
  super sha256=62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
  system sha256=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351
  product sha256=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2
  offline verifier report:
    hard-rom/inspect/v0.10-framework-locale-prune/verify-v0.10-offline-image-20260618-065440.txt
```

Settings APK itself is a RED package for direct replacement because it is a
priv-app with `android.uid.system`, privapp permission entries, sysconfig
references, many exported settings entry points, and overlays targeting it.

## Graphify Query Set

Package manager impact:

```bash
graphify query "What PackageManagerService and PackageManagerServiceSmtEx paths affect delete or replace for <package>?" --graph reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/graph.json --budget 2400
```

Resource and icon impact:

```bash
graphify query "What ResourcesManagerSmtEx AssetManagerSmtEx IconManager paths can affect <package> resources and icons?" --graph reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/graph.json --budget 2400
```

Overlay and config impact:

```bash
graphify query "What OverlayManager and SystemConfig paths affect <package> overlays permissions or sysconfig?" --graph reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/graph.json --budget 2400
```

Browser/WebView/keyguard impact:

```bash
graphify query "What WebView browser default intent keyguard and launcher paths can be affected by replacing com.android.browser?" --graph reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/graph.json --budget 2600
```

When graphify returns a broad traversal, use exact class queries and source
walks instead of accepting the broad output as proof.

## Build Gate

Before building:

```text
1. preflight output saved or summarized
2. target package/resource path maps to a known partition image
3. risk level accepted for the experiment size
4. graph/source walk completed for ORANGE or RED targets
5. latest stable sparse rollback exists locally
6. expected partition extents printed or recorded
7. package/cache/data cleanup plan exists when replacing or deleting defaults
```

Before flashing:

```text
1. user explicitly confirms the exact variant and slot
2. sparse image SHA256 is printed
3. raw super partition slice hash matches the source image
4. lpdump before/after or generated manifest is present
5. rollback command is known
```

After boot:

```bash
adb -s bb12d264 shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim'
tools/r2-root.sh status
adb -s bb12d264 shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head"
adb -s bb12d264 shell 'pm list packages -f | sort'
```

For package changes, also verify:

```bash
adb -s bb12d264 shell 'pm path <package> || true'
adb -s bb12d264 shell 'cmd package resolve-activity android.intent.action.MAIN -c android.intent.category.HOME || true'
adb -s bb12d264 shell 'cmd package query-intent-activities -a android.intent.action.VIEW -d https://example.com || true'
```

## Current Confidence Statement

The project is now ready to confidently evaluate and execute low-to-medium
risk hard-ROM changes, especially optional app deletion and product overlay
experiments. It is not yet ready to blindly patch framework jars, direct
framework resources, Keyguard, SystemUI, Settings, or same-package browser
replacement. Those are possible directions, but they require a focused source
walk, patch toolchain validation, and a tighter rollback/data cleanup plan for
each target.

SettingsSmartisan has now crossed the offline patch-toolchain gate. The current
v0.6/v0.7/v0.8 images were rebuilt after the shared_blocks boundary was
identified, using the held-stock-inode replacement pattern instead of debugfs
rm + write:

```text
v0.6-settings-noop:
  no-op replacement super built offline; waits for live boot validation.
  super sha256=a06c2e81862c837bef53a4dc2f67c5dea7f0acf78dc7fbbecb6ae4ece26483db

v0.7-locale-filter:
  first behavior-patch super built offline; filters ja_JP and ko_KR in
  LocalePickerFragment.constructAdapter(); waits behind v0.6 because ordinary
  keytool/jarsigner verification reports a classes.dex digest error.
  super sha256=d3dfef95d52dd1a26b399b2ef8a375c2645edfb08de46e4431e68cb5f823f9e4

v0.8-darkmode-ui:
  first native Settings dark-mode UI super built offline; reuses the existing
  hidden switch_dc row in BrightnessSettingsFragment and routes changes through
  UiModeManager.setNightModeActivated(boolean); waits behind v0.6 because
  ordinary keytool/jarsigner verification reports a classes.dex digest error.
  super sha256=44fed5e231d8a5525fbe748c25fe89ca3e50319054ade76e3ce6a4901259f435

offline verifier:
  tools/r2-verify-settingssmartisan-offline-images.sh
  hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-061432.txt
  result=PASS
```

So the current blocker for Settings behavior patches is no longer locating and
editing the code. It is proving the core APK replacement trust boundary on the
live device without breaking package-manager/shared-UID state.

For the active dark-mode and language goals, use:

```text
docs/research/system-modification-confidence.md
```

Current implementation preference:

```text
dark mode Settings switch:
  v0.8-darkmode-ui is built offline; flash only after v0.6 passes;
  prefer UiModeManager.setNightModeActivated(boolean) before adding a new
  MODIFY_DAY_NIGHT_MODE manifest dependency.

language picker:
  validate v0.7 LocalePickerFragment ja_JP/ko_KR filter before any
  framework-res or framework-smartisanos-res pruning attempt.

language resource pruning:
  v0.10-framework-locale-prune is the first complete offline hard-prune ROM
  candidate. It patches framework-res.apk, framework-smartisanos-res.apk, and
  five product DisplayCutout static overlays with English/Chinese-only
  resources. It is RED early-boot framework work and waits for explicit
  authorization plus v0.4 rollback readiness before any flash.
```
