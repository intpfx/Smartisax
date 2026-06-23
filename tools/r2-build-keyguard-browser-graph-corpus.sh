#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/reverse/smartisan-8.5.3-core"}"
JADX="$OUT/jadx"
FRAMEWORK_SELECTED="$OUT/jadx-framework-selected"
CORPUS="$OUT/graph-corpus/keyguard-browser-coupling"
SERVICES_PM="$JADX/services/sources/com/android/server/pm"

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "missing required path: $path" >&2
    exit 1
  fi
}

copy_tree() {
  local src="$1"
  local dst="$2"
  require_path "$src"
  mkdir -p "$(dirname "$dst")"
  rsync -a --delete "$src/" "$dst/"
}

copy_file() {
  local src="$1"
  local dst="$2"
  require_path "$src"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

rm -rf "$CORPUS"
mkdir -p "$CORPUS"

copy_tree "$JADX/KeyguardSmartisan/sources/com/smartisanos" \
  "$CORPUS/java/KeyguardSmartisan/com/smartisanos"

copy_tree "$JADX/SmartisanWallpaperProvider/sources/com/smartisanos/wallpaperprovider" \
  "$CORPUS/java/SmartisanWallpaperProvider/com/smartisanos/wallpaperprovider"

copy_file "$JADX/SmartisanSystemUI/sources/com/android/systemui/util/SmartisanApi.java" \
  "$CORPUS/java/SmartisanSystemUI/com/android/systemui/util/SmartisanApi.java"
copy_file "$JADX/SmartisanSystemUI/sources/com/android/systemui/recents/misc/SystemServicesProxy.java" \
  "$CORPUS/java/SmartisanSystemUI/com/android/systemui/recents/misc/SystemServicesProxy.java"
copy_file "$JADX/SmartisanDesktopSystemUI/sources/com/android/desktop/systemui/w0/d0.java" \
  "$CORPUS/java/SmartisanDesktopSystemUI/com/android/desktop/systemui/w0/d0.java"
copy_file "$JADX/LauncherSmartisanNew/sources/com/smartisanos/launcher/h.java" \
  "$CORPUS/java/LauncherSmartisanNew/com/smartisanos/launcher/h.java"
copy_file "$JADX/LauncherSmartisanNew/sources/com/smartisanos/launcher/provider/a.java" \
  "$CORPUS/java/LauncherSmartisanNew/com/smartisanos/launcher/provider/a.java"

copy_tree "$FRAMEWORK_SELECTED" "$CORPUS/java/framework-selected"

for rel in \
  PackageManagerServiceSmtEx.java \
  SettingsSmtEx.java \
  PackageManagerService.java \
  Settings.java \
  PackageSetting.java \
  PackageSettingBase.java \
  PackageSettingBaseSmtEx.java \
  ComponentResolverSmtEx.java \
  PreferredActivity.java
do
  copy_file "$SERVICES_PM/$rel" "$CORPUS/java/services/com/android/server/pm/$rel"
done

for rel in \
  AndroidManifest.xml \
  res/values/public.xml \
  res/values/strings.xml \
  res/layout/faceid_tips.xml \
  res/drawable/animation_faceid_detecting.xml \
  res/drawable/animation_faceid_failed.xml \
  res/drawable/animation_faceid_refresh.xml \
  res/drawable/animation_faceid_success.xml \
  res/drawable/faceid_retry_selector.xml
do
  copy_file "$JADX/KeyguardSmartisan/resources/$rel" \
    "$CORPUS/resources/KeyguardSmartisan/$rel"
done

for version in BrowserChrome-system-9.0.6.4 BrowserChrome-data-9.0.6.8; do
  for rel in \
    AndroidManifest.xml \
    res/values/public.xml \
    res/values/strings.xml \
    res/xml/searchable.xml \
    res/xml/launchershortcuts.xml
  do
    copy_file "$JADX/$version/resources/$rel" \
      "$CORPUS/resources/$version/$rel"
  done
done

copy_file "$OUT/reverse-manifest.tsv" "$CORPUS/reverse-manifest.tsv"

cat > "$CORPUS/README.graphify-note" <<'README'
# Smartisan R2 Keyguard/Browser Coupling Corpus

Focused corpus for investigating the lockscreen failure observed after replacing
`/system/app/BrowserChrome/BrowserChrome.apk` on Smartisan OS 8.5.3.

Included:

- KeyguardSmartisan Java sources under `com.smartisanos`.
- Selected Smartisan framework package/resource extension classes.
- Selected package-manager service classes implementing Smartisan system-package
  removal, package lock/session state, preferred activities, and system-package
  restore paths.
- SmartisanSystemUI, DesktopSystemUI, Launcher, and WallpaperProvider bridge code
  that touches package state, keyguard, wallpaper, or Smartisan package APIs.
- Keyguard face ID resources, including `animation_faceid_detecting` with
  resource ID `0x7f070097`.
- BrowserChrome 9.0.6.4 and 9.0.6.8 manifest/resource comparison inputs.

Known live failure:

- v0.3 Cromite same-package replacement and v0.3.1 official Smartisan browser
  update-as-system both caused `com.smartisanos.keyguard` to crash while
  creating `KeyguardService`.
- The crash point was `FaceIDIconManager.<init>`, where keyguard calls
  `context.getDrawable(R.drawable.animation_faceid_detecting)`.
- The missing resource ID reported by Android was `0x7f070097`, which maps to
  `animation_faceid_detecting` in the stock KeyguardSmartisan resources.
README

echo "corpus: $CORPUS"
find "$CORPUS" -type f | wc -l | awk '{print "files: " $1}'
