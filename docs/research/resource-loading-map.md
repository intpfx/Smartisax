# Smartisan Resource Loading Map

Purpose:

```text
Capture the current static-source and graphify-backed model for how Smartisan
OS 8.5.3 loads framework resources, app resources, overlays, locale tables, and
Smartisan icon redirection. Use this before changing framework resources,
package resources, icon-related packages, language resources, or same-package
system apps.
```

Evidence inputs:

```text
graphify corpus:
  reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/

graphify query:
  Trace how Android ResourcesManager, ResourcesImpl, AssetManager,
  framework-res, framework-smartisanos-res, static overlays, and per-package APK
  resources interact for locale selection and what this implies for safely
  pruning Japanese/Korean resources on Smartisan OS.

direct source reads:
  graph-input/java/framework.jar/android/content/res/AssetManager.java
  graph-input/java/framework.jar/android/app/ResourcesManager.java
  graph-input/java/framework.jar/android/content/res/ResourcesImpl.java
  graph-input/java/framework.jar/android/content/res/AssetManagerSmtEx.java
  graph-input/java/framework.jar/android/app/ResourcesManagerSmtEx.java
  graph-input/java/framework.jar/android/content/res/ResourcesImplSmtEx.java
```

## Resource Stack

System assets are created in zygote:

```text
AssetManager.createSystemAssetsInZygoteLocked()
  loads /system/framework/framework-res.apk
  loads /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
  loads immutable framework idmaps from OverlayConfig
  stores the result as sSystemApkAssets and sSystem
```

Application resources are layered on top of system assets:

```text
AssetManager.Builder.build()
  starts from AssetManager.getSystem().getApkAssets()
  appends user/app ApkAssets from ResourcesKey.mResDir
  appends split resource dirs
  appends lib dirs
  appends loader assets

ResourcesManager.createAssetManager(ResourcesKey)
  adds mResDir
  adds mSplitResDirs
  adds mLibDirs
  adds mOverlayDirs through idmap loading
```

Practical consequence:

```text
Framework resource pruning changes the global asset universe.
Package resource pruning changes that package's non-system resource universe.
Static android overlays change framework lookups but do not remove locale
configurations already compiled into framework resource tables.
```

## Locale Behavior

`AssetManager.getLocales()` returns all locales from the current asset set.
`AssetManager.getNonSystemLocales()` asks only for non-system locale assets.

`ResourcesImpl.updateConfiguration()` uses this flow:

```text
if locale config changes and more than one preferred locale exists:
  availableLocales = mAssets.getNonSystemLocales()
  if only pseudo-locales:
    availableLocales = mAssets.getLocales()
  bestLocale = preferredLocales.getFirstMatchWithEnglishSupported(availableLocales)
  if bestLocale differs from the first preferred locale:
    put bestLocale first in the configuration
```

Practical consequence:

```text
App-level APK resource pruning can affect that app's resource fallback and
displayed strings, but it does not by itself shrink Smartisan's global language
picker or framework AssetManager locale list.

Framework/framework-smartisanos/static-overlay pruning affects the global system
asset list and is therefore much higher risk. It must stay behind framework
no-op and early-boot live gates.
```

## Visible Language Picker

The current v0.7 verifier proves the Smartisan visible language-list path at
the smali level:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  uses Resources.getSystem().getAssets().getLocales()
  keeps the length==5 locale processing shape
  skips ja_JP and ko_KR in the candidate output
```

Practical consequence:

```text
Visible filtering is a Settings behavior patch. It hides choices from the UI,
but it is not a hard-ROM language resource prune.
```

## Smartisan Resource Extensions

Smartisan adds icon redirection to the resource path:

```text
ResourcesManager.createResourcesImpl()
  create AssetManager for the ResourcesKey
  call ResourcesManagerSmtEx.attachIconAssets(assets)
  then construct ResourcesImpl

ResourcesManagerSmtEx.attachIconAssets()
  enumerates package IDs inside the AssetManager
  asks the icon service for blocked packages and redirection maps
  attaches RedirectionForDrawableMap objects to AssetManagerSmtEx
  sets try-to-get-redirected-drawable state

ResourcesImplSmtEx.loadDrawableByFileName()
  asks AssetManagerSmtEx for redirected icons before falling back to stock
  drawable loading
```

`ResourcesManager.findResourcesImplForKeyLocked()` also rejects cached
`ResourcesImpl` objects when `AssetManagerSmtEx.isUpToDateGlobal()` reports the
asset or icon redirection state is stale.

Practical consequence:

```text
Same-package app replacement and icon-bearing package changes can interact with
Smartisan's icon redirection service and package resource table identity. This
matches the browser/keyguard failure pattern better than a simple Java-language
problem.
```

## Modification Rules

Use these rules until live gates prove a wider route:

```text
1. For low-exposure package language pruning, prefer resources.arsc-only APK
   surgery with unchanged classes.dex and AndroidManifest.xml.

2. For framework-res/framework-smartisanos-res/static android overlays, keep the
   staged gates:
     v0.12 framework-res no-op
     v0.10 framework/product locale-prune candidate
     live boot, keyguard, launcher, root, logcat, and rollback verification

3. For Settings/SystemUI behavior, preserve the no-op replacement gates before
   real dex behavior patches.

4. For icon-sensitive packages or same-package replacements, check
   /data/system/icon and redirection_policy live state before and after flash.

5. Do not treat a Rust rewrite as a shortcut around Android resource, package,
   overlay, signing, zygote, or SELinux contracts. The risk is mostly system
   integration and runtime state, not the Java language by itself.
```

Current confidence:

```text
APK-level resources.arsc pruning is now a well-understood, verifier-backed
operation for selected low-exposure packages.

Framework/global asset pruning is understood well enough to stage, but not
safe to generalize until v0.12/v0.10 live gates pass.

Same-package core or icon-sensitive app replacement remains high-risk until the
Smartisan icon redirection and package-state live gates are added to the flash
protocol.
```
