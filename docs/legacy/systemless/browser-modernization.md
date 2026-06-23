# Browser Modernization Package

`updates/modern-browser` installs Cromite as a modern Chromium-based browser
and makes it the default handler for normal web links.

## Scope

This package deliberately does not replace the system WebView provider. On this
Smartisan OS build, `dumpsys webviewupdate` reports only `com.android.webview`
as a valid provider, and the current version is `75.0.3770.156`. Replacing that
component is higher risk because Android's WebView Update Service enforces
provider package names, signatures, target SDK, and version rules.

Instead, this package improves user-facing browsing by installing:

```text
org.cromite.cromite 148.0.7778.168
```

The package source is Cromite release:

```text
https://github.com/uazo/cromite/releases/tag/v148.0.7778.168-cb3baf14f52eb4365d017f640f85310735c19b79
```

APK SHA256:

```text
77af7db8f0a02e8d8cd2099d1f9b5c8266d6ae4cba06924bda5c73f980dc6894
```

Packaged update artifact:

```text
dist/modern-browser-148.0.7778.168-1.zip
sha256: 18ca64809458dc3ce7546e279a1878cb230facc2ac9e95fb5663272ec7910a07
```

## Commands

```sh
tools/r2-update.sh validate updates/modern-browser
tools/r2-update.sh pack updates/modern-browser
tools/r2-update.sh install updates/modern-browser
tools/r2-update.sh list
tools/r2-update.sh uninstall modern-browser
```

## Device Checks

```sh
adb -s bb12d264 shell 'cmd package resolve-activity --brief -a android.intent.action.VIEW -d https://example.com'
adb -s bb12d264 shell 'dumpsys package org.cromite.cromite | grep -E "versionName|versionCode|minSdk|targetSdk"'
```

The installer records the previous default browser and restores it on uninstall.
If Cromite was not present before this package, uninstall also removes Cromite.

After the first launch, unlock the device and complete Cromite's first-run
screen once. Future web links should open directly in Cromite.
