# PackageManager pm1 Cache Policy Design

This is the first real PackageManager behavior policy after the live-proven
`v0.pm0-services-jar-noop` framework gate. It is an offline design note only:
no services.jar behavior build, no ROM image, no flash target, and no live
device mutation yet.

## Decision

Implement `pm1` as an allowlisted package parser cache read-bypass for
Smartisax-managed system package paths.

Initial allowlist:

```text
/system/app/SmartisaxShell
/system/app/TextBoomArm32
/system/app/TextBoom
/system/priv-app/Sidebar
```

Do not include Settings, SystemUI, Launcher, Keyguard, Phone, PackageInstaller,
PermissionController, WebView, BrowserChrome, or arbitrary `/system/app`
packages in `pm1`. Add those only behind their own focused policy notes and
no-op gates.

## Why This Is The First Policy

`pm1` targets the lowest-risk PackageManager pain point we have already seen:
stale parsed-package cache during boot-time directory scans.

This policy does not:

```text
disable signature verification
change sharedUserId checks
prefer ROM packages over /data/app packages
modify PackageSetting primaryCpuAbi
rewrite packages.xml
delete /data/system/package_cache
change install, reconcile, permission, or user-state logic
```

It only changes whether selected boot-scan packages may read an existing
serialized `ParsedPackage` from `/data/system/package_cache`.

## Source Facts

`PackageCacher` keys cache entries only by package file name plus parse flags,
then accepts the cache when the package mtime is older than the cache mtime:

```text
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageCacher.java:30
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageCacher.java:64
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageCacher.java:77
```

`PackageParser2.parsePackage(packageFile, flags, useCaches)` only uses
`useCaches` for the cache read. It still writes a fresh cache entry after a real
parse when `mCacher` exists:

```text
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageParser2.java:94
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageParser2.java:97
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageParser2.java:108
```

Boot-time directory scans use a shared parser with a real cache directory:

```text
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:2440
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:2447
```

Single-package scan paths already parse without cache:

```text
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:9256
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:9259
```

The narrowest call site is `ParallelPackageParser.parsePackage(...)`, which
currently forwards `useCaches=true` for every boot-scan file:

```text
reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/ParallelPackageParser.java:84
hard-rom/work/v0.pm0-services-jar-noop/decoded/smali/com/android/server/pm/ParallelPackageParser.smali:202
```

## Proposed Implementation

Add one small helper class inside `services.jar`:

```text
com.android.server.pm.SmartisaxPackagePolicy
```

Required helper API:

```java
static boolean shouldBypassPackageCache(File scanFile)
```

The function is intentionally pure: it returns true only when `scanFile` is
under one of the explicit allowlisted paths. Future PMS policies can add new
pure helpers instead of mixing unrelated logic into PackageManagerService.

Patch only `ParallelPackageParser.parsePackage(File scanFile, int parseFlags)`:

```java
boolean useCaches = !SmartisaxPackagePolicy.shouldBypassPackageCache(scanFile);
if (!useCaches) {
    Slog.i("SmartisaxPMS", "Bypass package parser cache for " + scanFile);
}
return mPackageParser.parsePackage(scanFile, parseFlags, useCaches);
```

Smali-level shape:

```text
hard-rom/work/v0.pm0-services-jar-noop/decoded/smali/com/android/server/pm/ParallelPackageParser.smali
  method: protected parsePackage(Ljava/io/File;I)Lcom/android/server/pm/parsing/pkg/ParsedPackage;
  current locals: 2
  likely new locals: 3 or 4
  replace const/4 v1, 0x1 with allowlist-derived useCaches boolean

new file:
  smali/com/android/server/pm/SmartisaxPackagePolicy.smali
```

`useCaches=false` in this call path should:

```text
skip reading stale ParsedPackage cache for allowlisted packages
force a real manifest/resources parse for those packages on every boot scan
write a fresh package_cache entry after the parse
leave every non-allowlisted package on stock cache behavior
```

## Candidate Variant

```text
variant:
  v0.pm1-pms-cache-allowlist

baseline:
  v0.pm0-services-jar-noop

changed services.jar entries:
  classes.dex
  classes2.dex

expected new class:
  com/android/server/pm/SmartisaxPackagePolicy.smali

expected edited class:
  com/android/server/pm/ParallelPackageParser.smali
```

`v0.pm1` should not modify `PackageCacher`, `PackageParser2`,
`PackageManagerService.scanPackageOnlyLI`, `Settings`, `PackageAbiHelperImpl`,
or `PackageManagerServiceUtils`.

## Verification Plan

Offline verifier must prove:

```text
services.jar changed entries are exactly classes.dex and classes2.dex
SmartisaxPackagePolicy exists in final decoded services.jar
ParallelPackageParser calls SmartisaxPackagePolicy.shouldBypassPackageCache
allowlist literals are exactly the approved paths
PackageCacher.smali is byte-identical to v0.pm0
PackageParser2.smali is byte-identical to v0.pm0
PackageManagerService.smali is byte-identical to v0.pm0
stale services.art/odex/vdex remain absent from system_b
system_b AVB/FEC roots are retained
```

Live read-only verifier must prove:

```text
boot_completed=1
slot=_b
system_server start_count=1
services.jar hash matches v0.pm1
public services.art/odex/vdex are absent
pm path com.smartisax.browser resolves to /system/app/SmartisaxShell/SmartisaxShell.apk
pm path com.smartisanos.textboom resolves to /system/app/TextBoomArm32/TextBoomArm32.apk
pm path com.smartisanos.sidebar resolves to /system/priv-app/Sidebar/Sidebar.apk
WebView M150 remains current with relro 2/2 and dirty=false
logcat contains SmartisaxPMS cache-bypass lines for allowlisted packages
logcat does not contain PackageManager fatal scan failures
```

Optional post-unlock functional smoke:

```text
Smartisax Home launches
Sidebar/One Step still opens
TextBoom BOOM_TEXT starts
TextBoom BOOM_IMAGE still reaches PP-OCR result page
```

## Rollback

Use the current local rollback image if `v0.pm1` fails boot:

```bash
fastboot -s bb12d264 flash super hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
fastboot -s bb12d264 erase misc
fastboot -s bb12d264 reboot
```

For a closer functional rollback, use the retained `v0.pm0` sparse once its
retention path is confirmed before flashing `v0.pm1`.

## Non-Goals

`pm1` does not solve the TextBoom ABI-selection problem. That remains `pm2`.

`pm1` does not solve updated-system shadow preference or `/data/app` cleanup.
That remains `pm3` and still needs explicit user approval for any `/data`
mutation.

`pm1` does not make unsafe manifest edits safe. Manifest/resource validity and
certificate carrier strategy remain `pm4`.
