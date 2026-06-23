#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

STOCK_SETTINGS_APK="${RAW}/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
OUT_APK="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-locale-filter-ja-ko.apk"
SIG_REPORT="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-locale-filter-ja-ko.signature.txt"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.7-locale-filter"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

sha256_zip_member() {
  local apk="$1"
  local member="$2"
  unzip -p "$apk" "$member" | shasum -a 256 | awk '{print $1}'
}

assert_changed_dex_only() {
  local changed=()
  local dex
  while IFS= read -r dex; do
    local stock_hash
    local out_hash
    stock_hash="$(sha256_zip_member "$STOCK_SETTINGS_APK" "$dex")"
    out_hash="$(sha256_zip_member "$OUT_APK" "$dex")"
    if [ "$stock_hash" != "$out_hash" ]; then
      changed+=("$dex")
    fi
  done < <(zipinfo -1 "$STOCK_SETTINGS_APK" 'classes*.dex' | sort)

  [ "${#changed[@]}" -eq 1 ] || die "expected one changed dex, got ${changed[*]:-none}"
  [ "${changed[0]}" = "classes.dex" ] || die "expected changed classes.dex, got ${changed[0]}"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || die "${file} missing: ${needle}"
}

assert_locale_filter_smali() {
  local smali="$1"
  assert_contains "$smali" '.method public constructAdapter(Landroid/content/Context;)[Lcom/android/settings/inputmethod/LocalePickerFragment$LocaleInfo;'
  assert_contains "$smali" '    .locals 13'
  assert_contains "$smali" 'Landroid/content/res/AssetManager;->getLocales()[Ljava/lang/String;'
  assert_contains "$smali" 'const-string v12, "ja_JP"'
  assert_contains "$smali" 'const-string v12, "ko_KR"'
  assert_contains "$smali" 'invoke-virtual {v7, v12}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z'
  assert_contains "$smali" 'if-nez v12, :cond_3'
  assert_contains "$smali" 'invoke-virtual {v7}, Ljava/lang/String;->length()I'
  assert_contains "$smali" 'new-instance v8, Lcom/android/settings/inputmethod/LocalePickerFragment$LocaleInfo;'
  assert_contains "$smali" 'Lcom/android/settings/inputmethod/LocalePickerFragment$LocaleInfo;-><init>(Lcom/android/settings/inputmethod/LocalePickerFragment;Ljava/lang/String;Ljava/util/Locale;)V'
}

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-settingssmartisan-locale-filter-apk.sh

Read-only APK-level verifier for the v0.7 SettingsSmartisan locale-filter
candidate. It verifies that only classes.dex changed, decodes the candidate to
temporary smali, copies LocalePickerFragment.smali into hard-rom/inspect, and
checks the concrete ja_JP/ko_KR skip logic inside constructAdapter().

It does not build images, modify ROM files, touch the device, or change /data.
USAGE
}

case "${1:-}" in
  "")
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

need_file "$STOCK_SETTINGS_APK"
need_file "$OUT_APK"
need_file "$SIG_REPORT"
need_file "$APKTOOL"
need_executable "$JAVA_BIN"

mkdir -p "$INSPECT_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
report="${INSPECT_DIR}/verify-settingssmartisan-locale-filter-apk-${timestamp}.txt"
evidence_dir="${INSPECT_DIR}/smali-evidence-${timestamp}"
decode_tmp="$(mktemp -d "/tmp/r2-v0.7-locale-filter.XXXXXX")"
trap 'rm -rf "$decode_tmp"' EXIT
mkdir -p "$evidence_dir"

{
  echo "# v0.7 SettingsSmartisan locale-filter APK verification"
  echo "timestamp=${timestamp}"
  echo

  echo "## sha256"
  shasum -a 256 "$OUT_APK" "$STOCK_SETTINGS_APK"
  echo

  echo "## zip integrity"
  unzip -t "$OUT_APK" | tail -n 3
  echo

  echo "## dex changes"
  assert_changed_dex_only
  echo "SettingsSmartisan: only classes.dex changed"
  echo

  echo "## patched strings"
  unzip -p "$OUT_APK" classes.dex | strings > "${evidence_dir}/classes.strings"
  grep -q 'ja_JP' "${evidence_dir}/classes.strings" || die "missing ja_JP constant"
  grep -q 'ko_KR' "${evidence_dir}/classes.strings" || die "missing ko_KR constant"
  echo "ja_JP and ko_KR constants present"
  echo

  echo "## smali semantics"
  "$JAVA_BIN" -jar "$APKTOOL" d -r --no-assets -f \
    -o "${decode_tmp}/SettingsSmartisan" "$OUT_APK" > "${evidence_dir}/decode-settings-locale-filter.log" 2>&1
  cp "${decode_tmp}/SettingsSmartisan/smali/com/android/settings/inputmethod/LocalePickerFragment.smali" \
    "${evidence_dir}/Settings-LocalePickerFragment.smali"
  assert_locale_filter_smali "${evidence_dir}/Settings-LocalePickerFragment.smali"
  echo "smali_evidence=${evidence_dir}"
  echo "LocalePickerFragment.constructAdapter ja_JP/ko_KR skip logic verified"
  echo

  echo "## signature boundary"
  grep -q 'SHA-256 digest error for classes.dex' "$SIG_REPORT" \
    || die "signature report missing classes.dex digest boundary"
  sed -n '1,28p' "$SIG_REPORT"
  echo

  echo "PASS"
} | tee "$report"

echo "Report: ${report}"
