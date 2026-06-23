#!/usr/bin/env bash
set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/reverse/smartisan-8.5.3-core"}"
RAW="$OUT/raw"
JADX_OUT="$OUT/jadx"
LOG_DIR="$OUT/logs"
MANIFEST="$OUT/reverse-manifest.tsv"

mkdir -p "$RAW" "$JADX_OUT" "$LOG_DIR"

SYSTEM_IMG="$ROOT/hard-rom/extracted/system.img"
SYSTEM_EXT_IMG="$ROOT/hard-rom/extracted/system_ext.img"
PRODUCT_IMG="$ROOT/hard-rom/extracted/product.img"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing required file: $path" >&2
    exit 1
  fi
}

extract_from_img() {
  local image="$1"
  local rel="$2"
  local dest="$RAW/$rel"

  require_file "$image"
  if [[ -f "$dest" ]]; then
    echo "extract: exists $rel"
    return 0
  fi

  echo "extract: $rel"
  mkdir -p "$(dirname "$dest")"
  7z x -y "$image" "-o$RAW" "$rel" > "$LOG_DIR/extract-$(basename "$rel").log" 2>&1
  require_file "$dest"
}

decompile_one() {
  local name="$1"
  local input="$2"
  local out_dir="$JADX_OUT/$name"
  local log="$LOG_DIR/jadx-$name.log"

  require_file "$input"
  if [[ -d "$out_dir" ]]; then
    echo "jadx: exists $name"
    return 0
  fi

  echo "jadx: $name"
  jadx --show-bad-code -d "$out_dir" "$input" > "$log" 2>&1
  local status=$?
  if [[ "$status" -ne 0 && "$status" -ne 3 ]]; then
    echo "jadx failed for $name with status $status; see $log" >&2
    exit "$status"
  fi
  if [[ "$status" -eq 3 ]]; then
    echo "jadx: $name completed with recoverable decompile errors; see $log"
  fi
}

record_manifest() {
  local name="$1"
  local input="$2"
  local sha
  sha="$(shasum -a 256 "$input" | awk '{print $1}')"
  printf '%s\t%s\t%s\n' "$name" "$sha" "$input" >> "$MANIFEST"
}

rm -f "$MANIFEST"
printf 'name\tsha256\tinput\n' > "$MANIFEST"

while IFS='|' read -r name image rel; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  extract_from_img "$image" "$rel"
  input="$RAW/$rel"
  decompile_one "$name" "$input"
  record_manifest "$name" "$input"
done <<EOF
KeyguardSmartisan|$SYSTEM_IMG|system/priv-app/KeyguardSmartisan/KeyguardSmartisan.apk
BrowserChrome-system-9.0.6.4|$SYSTEM_IMG|system/app/BrowserChrome/BrowserChrome.apk
SmartisanSystemUI|$SYSTEM_EXT_IMG|priv-app/SmartisanSystemUI/SmartisanSystemUI.apk
SmartisanDesktopSystemUI|$SYSTEM_IMG|system/priv-app/SmartisanDesktopSystemUI/SmartisanDesktopSystemUI.apk
SmartisanWallpaperProvider|$SYSTEM_IMG|system/app/SmartisanWallpaperProvider/SmartisanWallpaperProvider.apk
SmartisanShareBrowser|$SYSTEM_IMG|system/app/SmartisanShareBrowser/SmartisanShareBrowser.apk
LauncherSmartisanNew|$SYSTEM_IMG|system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk
SmartisanUpdater|$SYSTEM_IMG|system/priv-app/SmartisanUpdater/SmartisanUpdater.apk
framework-res|$SYSTEM_IMG|system/framework/framework-res.apk
framework-smartisanos-res|$SYSTEM_IMG|system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
smartisanos|$SYSTEM_IMG|system/framework/smartisanos.jar
smartisan-framework-tnt|$SYSTEM_IMG|system/framework/smartisan-framework-tnt.jar
smartisan-services-tnt|$SYSTEM_IMG|system/framework/smartisan-services-tnt.jar
services|$SYSTEM_IMG|system/framework/services.jar
sys-framework|$SYSTEM_IMG|system/framework/sys-framework.jar
sys-services|$SYSTEM_IMG|system/framework/sys-services.jar
SystemUIResCommon|$PRODUCT_IMG|overlay/SystemUIResCommon.apk
EOF

official_update="$ROOT/hard-rom/inspect/browser-same-package/com.android.browser-data-9.0.6.8.apk"
if [[ -f "$official_update" ]]; then
  decompile_one "BrowserChrome-data-9.0.6.8" "$official_update"
  record_manifest "BrowserChrome-data-9.0.6.8" "$official_update"
else
  echo "skip: official browser data update not found: $official_update"
fi

echo "done"
echo "raw: $RAW"
echo "jadx: $JADX_OUT"
echo "manifest: $MANIFEST"
