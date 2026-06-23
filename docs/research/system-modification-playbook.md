# System Modification Playbook

Date: 2026-06-18.

Purpose:

```text
Define the reusable confidence model for future Smartisan R2 hard-ROM changes.
This playbook turns a user request such as "delete this app", "replace this
system component", "change Settings behavior", or "make a framework resource
smaller" into a concrete gate sequence before build and flash.
```

Boundary:

```text
This is a source-backed planning document. It does not authorize flashing by
itself. The live device, exact-current image verifiers, and post-boot checks
remain the source of truth.
```

## Core Model

Every system modification must first answer five questions:

```text
1. Which partition and package/resource actually owns the behavior?
2. Is the change a delete, resource-only prune, same-package APK replacement,
   framework resource replacement, SettingsProvider migration/default change,
   or boot-surface change?
3. Does PackageManager need the package identity, certificate lineage,
   sharedUserId, SELinux seInfo, privileged permission, or static overlay
   relationship to remain stable?
4. Does Resources/AssetManager, SettingsProvider, backup/restore, SystemUI,
   Keyguard, Launcher, or user data cache normalize or override the change at
   runtime?
5. Which live no-op gate must pass before the first behavior patch?
```

Do not collapse these into a generic "BL unlocked plus root" answer. Bootloader
unlock lets us flash images; it does not make Android package, resource,
settings, overlay, SELinux, or boot-order contracts disappear.

## Source Anchors

Package/signature layer:

```text
framework.jar/android/content/pm/parsing/ParsingPackageUtils.java
  getSigningDetails(..., skipVerify)
  skipVerify calls ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)
  split APKs still need matching certificates.

services.jar/com/android/server/pm/PackageManagerServiceUtils.java
  verifySignatures(...)
  rejects mismatch with the previously installed package.
  rejects mismatch with sharedUserId signing details.

services.jar/com/android/server/pm/PackageManagerService.java
  reconcile path can throw signature mismatch for shared users on system
  packages, and sharedUserSetting affects SELinux seInfo and ABI handling.
```

Resource layer:

```text
framework.jar/android/content/res/AssetManager.java
  createSystemAssetsInZygoteLocked(...)
  system assets load framework-res.apk, framework-smartisanos-res.apk, and
  immutable framework idmaps.

AssetManager.Builder.build()
  app Resources include system assets first, then package/user APK assets and
  loader assets.

AssetManager.isUpToDate()
  runtime resource objects can detect stale ApkAssets; resource changes are not
  only file replacement questions.
```

Settings/default layer:

```text
SettingsProvider/DatabaseHelper.java
  seeds expanded_widget_buttons and expanded_widget_buttons_additional.

SettingsProvider.java
  upgrade steps can rewrite widget settings, seed ui_night_mode, and run
  cleanDirtyWidgetButton().

SettingsBackupAgent.java
  restore can merge, dedupe, replace, append required keys, and split widget
  lists across the 20-entry first page and the additional list.
```

Boot/UI layer:

```text
SmartisanSystemUI/QSTileHost.java
  Smartisan QS reads Settings.System expanded_widget_buttons and truncates the
  first page to 20 keys.

services.jar/com/android/server/policy/PhoneWindowManager.java
  owns the KeyguardServiceDelegate and HOME resolution paths.

LauncherSmartisanNew/AndroidManifest.xml
  com.smartisanos.launcher is the HOME activity and carries many
  signature/system permissions.

KeyguardSmartisan/AndroidManifest.xml
  com.smartisanos.keyguard is coreApp=true, sharedUserId=android.uid.system,
  and has signature/system permissions.
```

## Change Classes

### A. Hard Delete

Use when the package is optional and not a boot, provider, permission, shared
UID, launcher, keyguard, installer, framework, or SystemUI dependency.

Required gates:

```text
tools/r2-rom-mod-preflight.py <package> --action delete
static manifest/provider/permission review for YELLOW and above
exact-current image verifier
post-boot package absence plus launcher/shortcut cleanup check
```

Current proven example:

```text
v0.4 hard debloat and no-appstore route proved this class can work when package
coupling is low and rollback is ready.
```

### B. Same-Package Non-Core Replacement

Use when keeping package name, code path, permissions, and public user-visible
role matters.

Required gates:

```text
preflight --action replace
signature/sharedUserId check
classes.dex/manifest/resource diff review
no-op or minimal same-size probe if the package is boot-relevant
post-boot PackageManager state and focused UI validation
```

Risk lesson:

```text
The same-package browser attempts caused a no-lockscreen/no-desktop failure.
Same package does not mean safe. Smartisan icon redirection, user data state,
resources, and boot focus can couple in non-obvious ways.
```

### C. Core Shared-UID APK Replacement

Use for SettingsSmartisan, SettingsProvider, SmartisanSystemUI, Keyguard,
Launcher, PackageInstaller, PermissionController, or other system/shared UID
packages.

Required gates:

```text
original-cert-preserving patch only; do not self-sign
tools/r2-apk-signature-boundary-check.sh <apk>
exact APK no-op live gate for that component
post-boot package state, shared UID, SELinux/logcat, UI launch, and rollback
behavior patch only after the matching no-op gate passes
```

Current gates:

```text
SettingsSmartisan:
  v0.6-settings-noop built offline; not live-verified.

SmartisanSystemUI:
  systemui-certprobe-noop built offline; not live-verified.

SettingsProvider, Keyguard, Launcher:
  no live no-op gate exists yet. Treat as higher-risk until one is built and
  verified.
```

### D. App-Level Resource Hard-Prune

Use for removing non-target locale chunks from non-core APK resources.

Required gates:

```text
preflight package exposure
classes.dex and AndroidManifest.xml byte-identical if the intent is resources-only
binary resources.arsc locale-policy verifier
APK-only verifier first, then ROM image replacement verifier
post-boot package/resource smoke
```

Current proven offline examples:

```text
Protips, PrintRecommendationService, OsuLogin, PrintSpooler,
LiveWallpapersPicker, HTMLViewer, BasicDreams, PhotoTable.
```

### E. Framework Resource Replacement

Use for framework-res.apk, framework-smartisanos-res.apk, android static
overlays, and language/resource changes that affect Resources.getSystem().

Required gates:

```text
framework-res no-op live gate before behavior/resource prune
binary arsc policy for locale changes
public.xml/package ID/resource ID stability
post-fsck dumped APK hash and ZIP verification
early boot, Keyguard, Launcher, SystemUI, Settings, app launch checks
```

Current gates:

```text
v0.12-framework-res-noop is built and offline-verified; not live-verified.
v0.10 framework/product language hard-prune is built and offline-verified; do
not flash it before v0.12 passes live.
```

### F. SettingsProvider Defaults Or Migrations

Use for default QS tiles, default dark-mode state, default feature flags,
language defaults, database upgrades, or backup/restore behavior.

Required gates:

```text
identify namespace: system, secure, or global
identify fresh install seed, upgrade migration, cleanup, validator, backup, and
restore paths
capture current live values before designing migration
prefer no-op live gate for SettingsProvider before behavior patch
define rollback/data plan before writing or deleting live settings
```

Dark-mode implication:

```text
Do not default-insert toggleDarkMode by appending a 21st QS key. The first page
is capped at 20. A default-visible route must replace one key or perform a
live migration after current Settings.System values are captured.
```

### G. SystemUI, Keyguard, Launcher, Phone, And Other Boot Surfaces

Use for anything that can affect lockscreen, notification shade, HOME, recents,
phone service, emergency affordances, or system navigation.

Required gates:

```text
source/graph dependency map
component-specific original-cert-preserving no-op gate
logcat focus around boot, PackageManager, SystemUI, WindowManager, Keyguard,
Launcher, and the target package
dumpsys window keyguard/focus checks
launcher HOME resolution and package state checks
root/APatch verification
rollback image local and verified
```

Current policy:

```text
Do not directly patch Keyguard or Launcher for convenience. They are boot/UI
surfaces. Build a component-specific no-op gate first, then a minimal behavior
patch, then a broader feature.
```

## Confidence Ladder

```text
0. Unknown:
   only a user-facing request exists.

1. Located:
   owner package/class/resource and partition are identified.

2. Source-mapped:
   call chain, settings/resource/data owners, and boot/UI coupling are mapped.

3. Offline-proven:
   APK/image candidate builds and verifiers prove intended byte/code/resource
   changes.

4. Live no-op proven:
   the exact replacement layer boots and verifies live with no behavior change.

5. Live behavior proven:
   the real patch boots and verifies on device.

6. Durable:
   reboot, reset/defaults, backup/restore, user-data migration, rollback, and
   logs are checked.
```

We should only say "confident enough to flash" at level 4 or higher for core
components, and only say "feature complete" at level 5 or 6 depending on the
user-facing surface.

## Current Application To Active Goals

Native dark mode:

```text
level: 3 offline-proven
reason: Settings/SystemUI APK call sites and source route are proven, but live
state and no-op gates are missing.
next: successful live-state capture, v0.6 Settings no-op, SystemUI certprobe
no-op, then combined v0.11 ROM build.
```

English/Chinese-only hard prune:

```text
level: mixed 2-3
reason: language/resource loading model and many APK-level probes are proven,
but full ROM coverage remains incomplete and framework live gates are missing.
next: v0.12 framework-res no-op live gate before v0.10; build v0.13 sparse
super only when disk space allows and then verify offline before flash.
```

Future phone/Settings/SystemUI/Keyguard/Launcher modifications:

```text
level: 1-2 until each target has its own source map and no-op gate.
rule: do not transfer confidence from SettingsSmartisan or SystemUI to another
core package. Each core package gets its own no-op gate.
```
