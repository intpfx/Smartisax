#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/reverse/smartisan-8.5.3-core"}"
FRAMEWORK_JAR="$OUT/raw/system/framework/framework.jar"
DEST="$OUT/jadx-framework-resource-selected"
LOG_DIR="$OUT/logs/framework-resource-selected"

if [[ ! -f "$FRAMEWORK_JAR" ]]; then
  echo "missing framework.jar: $FRAMEWORK_JAR" >&2
  exit 1
fi

rm -rf "$DEST" "$LOG_DIR"
mkdir -p "$DEST" "$LOG_DIR"

classes=(
  android.app.ActivityThread
  android.app.ApplicationPackageManager
  android.app.ContextImpl
  android.app.LoadedApk
  android.app.ResourcesManager
  android.app.ResourcesManagerSmtEx
  android.content.pm.ApplicationInfo
  android.content.pm.ApplicationInfoSmtEx
  android.content.pm.PackageParser
  android.content.pm.PackageParserSmtEx
  android.content.pm.PackageParserSmto
  android.content.res.ApkAssets
  android.content.res.AssetManager
  android.content.res.AssetManagerSmtEx
  android.content.res.CompatibilityInfo
  android.content.res.IIconManager
  android.content.res.IResourcesCallbackSmto
  android.content.res.IconManager
  android.content.res.RedirectionForDrawableMap
  android.content.res.Resources
  android.content.res.ResourcesImpl
  android.content.res.ResourcesImplSmtEx
  android.content.res.ResourcesKey
  android.content.res.ResourcesSmtEx
  android.content.res.ResourcesSmto
)

for class_name in "${classes[@]}"; do
  log="$LOG_DIR/${class_name//./_}.log"
  echo "jadx single: $class_name"
  if ! jadx --show-bad-code \
      --single-class "$class_name" \
      --single-class-output "$DEST" \
      "$FRAMEWORK_JAR" >"$log" 2>&1; then
    echo "  skip/failed: $class_name (see $log)" >&2
  fi
done

find "$DEST" -type f -name '*.java' | sort > "$DEST/FILES.txt"
echo "out: $DEST"
wc -l "$DEST/FILES.txt" | awk '{print "files: " $1}'
