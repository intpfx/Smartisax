#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-apktool-rebuild-smoke.sh FrameworkRes
  tools/r2-apktool-rebuild-smoke.sh SmartisanFrameworkRes
  tools/r2-apktool-rebuild-smoke.sh SettingsProvider
  tools/r2-apktool-rebuild-smoke.sh SettingsSmartisan
  tools/r2-apktool-rebuild-smoke.sh SmartisanSystemUI
  tools/r2-apktool-rebuild-smoke.sh all

This is an offline apktool smoke test. It decodes and rebuilds selected stock
APKs in /tmp to verify the repack toolchain. It does not sign APKs, modify ROM
images, or touch the device.
USAGE
}

require_file() {
  local path="$1"
  [ -f "$path" ] || {
    echo "missing file: $path" >&2
    exit 1
  }
}

install_frameworks() {
  local framework_dir="$1"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$framework_dir" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$framework_dir" "$FW_SMARTISAN" >/dev/null
}

target_apk() {
  case "$1" in
    FrameworkRes)
      printf '%s\n' "$FW_ANDROID"
      ;;
    SmartisanFrameworkRes)
      printf '%s\n' "$FW_SMARTISAN"
      ;;
    SettingsProvider)
      printf '%s\n' "${RAW}/system/system/priv-app/SettingsProvider/SettingsProvider.apk"
      ;;
    SettingsSmartisan)
      printf '%s\n' "${RAW}/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
      ;;
    SmartisanSystemUI)
      printf '%s\n' "${RAW}/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
      ;;
    *)
      echo "unknown target: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

fixup_decoded_tree() {
  local name="$1"
  local decoded_dir="$2"

  if [ "$name" = "SettingsSmartisan" ]; then
    # apktool decodes this private enum attr as boolean. aapt2 rejects it when
    # rebuilding; the original activity still inherits a normal framework theme.
    perl -0pi -e 's/\s+androidprv:quickContactWindowSize="true"//g' \
      "${decoded_dir}/AndroidManifest.xml"
  fi

  if [ "$name" = "SmartisanFrameworkRes" ]; then
    # apktool exposes Smartisan private attributes as a synthetic
    # ^attr-private type. aapt2 cannot link public.xml entries of that type
    # when rebuilding this framework package itself, so normalize them to attr
    # for offline buildability checks.
    if [ -f "${decoded_dir}/res/values/attrs-private.xml" ]; then
      perl -0pi -e 's/<\^attr-private\b/<attr/g; s#</\^attr-private>#</attr>#g' \
        "${decoded_dir}/res/values/attrs-private.xml"
    fi
    perl -0pi -e 's/type="\^attr-private"/type="attr"/g; s/name="\^attr-private\./name="/g' \
      "${decoded_dir}/res/values/public.xml" \
      "${decoded_dir}/res/values/styles.xml"
  fi
}

smoke_one() {
  local name="$1"
  local apk
  apk="$(target_apk "$name")"
  require_file "$apk"

  local tmp
  tmp="$(mktemp -d "/tmp/r2-apktool-${name}.XXXXXX")"
  local framework_dir="${tmp}/framework"
  local decoded_dir="${tmp}/${name}"
  local rebuilt="${tmp}/${name}-rebuilt-unsigned.apk"

  install_frameworks "$framework_dir"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$framework_dir" -f -o "$decoded_dir" "$apk" >/dev/null
  fixup_decoded_tree "$name" "$decoded_dir"
  "$JAVA_BIN" -jar "$APKTOOL" b -p "$framework_dir" -o "$rebuilt" "$decoded_dir" >/dev/null

  printf '%s\n' "target=${name}"
  printf '%s\n' "rebuilt_unsigned=${rebuilt}"
  shasum -a 256 "$rebuilt"
}

main() {
  local target="${1:-}"
  if [ -z "$target" ] || [ "$target" = "-h" ] || [ "$target" = "--help" ]; then
    usage
    exit 0
  fi

  require_file "$APKTOOL"
  require_file "$FW_ANDROID"
  require_file "$FW_SMARTISAN"
  [ -x "$JAVA_BIN" ] || {
    echo "missing executable Java runtime: $JAVA_BIN" >&2
    exit 1
  }

  if [ "$target" = "all" ]; then
    smoke_one FrameworkRes
    smoke_one SmartisanFrameworkRes
    smoke_one SettingsProvider
    smoke_one SettingsSmartisan
    smoke_one SmartisanSystemUI
  else
    smoke_one "$target"
  fi
}

main "$@"
