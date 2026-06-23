# PackageManager Policy Map

This note maps the PackageManager surfaces that have repeatedly constrained the
Smartisax hard-ROM route. It is a design map, not live proof. Any framework
change still needs a services.jar no-op gate, image-level verification, live
preflight, explicit flash confirmation, and post-boot validation.

## Current Finding

Several recent failures were PackageManager state decisions rather than app
logic failures:

```text
v0.26a.1 launcher-entry hide:
  manifest edits were present in /system, but /data/system/package_cache reused
  stale ParsedPackage data until the package directory mtime was bumped.

v0.36 Smartisax shell:
  PackageManager rejected the system APK because Android 11 requires
  resources.arsc to be STORED and 4-byte aligned for target R+ packages.

v0.37a TextBoom promotion:
  ROM TextBoom existed, but the active package still resolved from a /data/app
  updated-system shadow until PackageManager state was repaired.

v0.43a TextBoom manifest ocr_key removal:
  the system APK existed and matched hash, but PackageManager ignored the
  package after the manifest edit.

v0.43c and v0.43d TextBoom ABI forcing:
  removing arm64 libs and moving codePath did not force armeabi-v7a; the live
  PackageManager kept primaryCpuAbi=arm64-v8a from package settings/state.
```

The practical conclusion is that future deep customization needs a narrow
Smartisax PackageManager policy layer. It should not globally disable Android
package safety checks.

## Source Map

| Surface | Source | Observed behavior | Smartisax policy direction |
| --- | --- | --- | --- |
| Parsed package cache | `com.android.server.pm.parsing.PackageCacher` | Cache key is `packageFile.getName() + '-' + flags`; cache is accepted when package mtime is older than cache mtime. | For allowlisted packages, bypass or clean cache when codePath/resource-critical ROM changes are detected. |
| ABI reuse | `PackageManagerService.scanPackageOnlyLI` | If PackageSetting already has `primaryCpuAbiString` and scan flags do not force derive, PMS reuses the stored ABI. | For allowlisted packages, force ABI re-derive or apply explicit ABI override. |
| Bundled system ABI selection | `PackageAbiHelperImpl.getBundledAppAbi` | System bundled APKs derive ABI from `/system/lib64/<apkName>`, `/system/lib/<apkName>`, package-local `lib/<isa>`, and oat dirs. | For TextBoom-like packages, define a deterministic ABI policy before runtime libs are selected. |
| Code path expectation | `PackageManagerService` codePath consistency checks | A known package found at a different path can be ignored when existing package settings expect the old path. | For allowlisted migrations, update settings/cache coherently instead of only moving files in ROM. |
| Updated-system shadow | `PackageSetting`, disabled-system package state, install-from-system paths | A `/data/app` updated-system copy can shadow the ROM package. | For selected system packages, prefer the ROM copy and clear/update stale updated-system state with an explicit live repair step. |
| Signature reconciliation | `PackageManagerService.reconcilePackagesLocked` and `PackageManagerServiceUtils.verifySignatures` | System partition parsing can skip full APK verification, but signatures are still compared with previous package/shared-user signing details. | Do not bypass globally. If needed, use a very narrow allowlist plus original certificate carrier evidence. |
| Manifest/resource parse validity | Package parser and Android 11 install rules | Some manifest/resource edits make PMS ignore packages even when the APK exists. | Keep manifest edits behind no-op probes and cache/signature carrier checks. |

## First Framework Gate

The first safe gate is `v0.pm0-services-jar-noop`:

```text
input:
  /system/framework/services.jar from the stock static ROM corpus

process:
  apktool decode stock services.jar
  rebuild without smali edits
  merge rebuilt classes.dex/classes2.dex into the stock jar shell
  preserve non-dex entries from the stock shell
  verify ZIP, dex, and key PMS smali evidence

scope:
  offline jar only first
  no system image
  no super image
  no flash
  no live-device mutation
```

This gate has now passed through image-level build, sparse super packing,
B-slot flash, and live read-only verification as
`v0.pm0-services-jar-noop`. The services.jar roundtrip boundary is therefore
closed, and the next branch may add a real but narrow PMS policy.

## Policy Order

Use this order so each policy has a concrete failure sample and a small
rollback surface:

```text
pm0:
  services.jar no-op roundtrip, then image/live boot gate.

pm1:
  package_cache bypass or cleanup for Smartisax-managed package paths.
  Selected first policy: allowlisted PackageParser cache read-bypass in
  ParallelPackageParser, documented in
  docs/research/package-manager-pm1-cache-policy-design.md.
  First acceptance sample: launcher-entry/cachebump behavior.

pm2:
  ABI rederive or ABI override for TextBoom only.
  First acceptance sample: v0.43c/v0.43d primaryCpuAbi=arm64-v8a failure.

pm3:
  updated-system shadow preference/repair for selected system packages.
  First acceptance sample: TextBoom /data/app shadow from v0.37a.

pm4:
  manifest/signature carrier strategy for selected packages.
  First acceptance sample: TextBoom ocr_key boundary and future Browser/WebView
  carrier work.
```

## Guardrails

```text
Never:
  globally disable signature verification
  globally ignore sharedUserId signing checks
  globally prefer ROM packages over /data/app packages
  modify PackageManager without a services.jar no-op boot gate

Always:
  keep the allowlist explicit
  log when a Smartisax policy branch is used
  verify /data/system/packages.xml, package_cache, codePath/resourcePath,
  primaryCpuAbi, nativeLibraryDir, and pm path after live boot
```
