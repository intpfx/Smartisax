#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
STOCK_SETTINGS_APK="${RAW}/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.7-locale-filter-apktool"
FRAMEWORK_DIR="${WORK_DIR}/framework"
DECODED_DIR="${WORK_DIR}/SettingsSmartisan"
REBUILT_UNSIGNED="${WORK_DIR}/SettingsSmartisan-locale-filter-rebuilt-unsigned.apk"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/SettingsSmartisan-locale-filter-ja-ko.apk"
SIG_REPORT="${OUT_DIR}/SettingsSmartisan-locale-filter-ja-ko.signature.txt"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-settingssmartisan-locale-filter-apk.sh

Build an offline SettingsSmartisan.apk behavior-patch candidate that hides
ja_JP and ko_KR in Smartisan's visible language picker by patching:

  com.android.settings.inputmethod.LocalePickerFragment.constructAdapter()

The output APK is not a standalone installable app and is not flash-authorized.
It replaces classes.dex while keeping the stock APK shell. That intentionally
breaks ordinary JAR digest verification for classes.dex; it is only useful for
the Android system-partition certs-only experiment path and must not be flashed
until the v0.6 SettingsSmartisan no-op probe has passed live validation.
USAGE
}

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

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

fixup_decoded_tree() {
  # apktool decodes this private enum attr as boolean. aapt2 rejects it when
  # rebuilding; the original activity still inherits a normal framework theme.
  perl -0pi -e 's/\s+androidprv:quickContactWindowSize="true"//g' \
    "${DECODED_DIR}/AndroidManifest.xml"
}

patch_locale_picker() {
  local smali="${DECODED_DIR}/smali/com/android/settings/inputmethod/LocalePickerFragment.smali"
  need_file "$smali"

  perl -0pi -e '
    my $old = ".method public constructAdapter(Landroid/content/Context;)[Lcom/android/settings/inputmethod/LocalePickerFragment\$LocaleInfo;\n    .locals 12";
    my $new = ".method public constructAdapter(Landroid/content/Context;)[Lcom/android/settings/inputmethod/LocalePickerFragment\$LocaleInfo;\n    .locals 13";
    s/\Q$old\E/$new/ or die "failed to update constructAdapter locals\n";
  ' "$smali"

  perl -0pi -e '
    my $old = "    .line 332\n    aget-object v7, v0, v5\n\n    .line 333\n    invoke-virtual {v7}, Ljava/lang/String;->length()I";
    my $new = "    .line 332\n    aget-object v7, v0, v5\n\n    const-string v12, \"ja_JP\"\n\n    invoke-virtual {v7, v12}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n    move-result v12\n\n    if-nez v12, :cond_3\n\n    const-string v12, \"ko_KR\"\n\n    invoke-virtual {v7, v12}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n    move-result v12\n\n    if-nez v12, :cond_3\n\n    .line 333\n    invoke-virtual {v7}, Ljava/lang/String;->length()I";
    s/\Q$old\E/$new/ or die "failed to insert locale filter\n";
  ' "$smali"

  grep -q 'const-string v12, "ja_JP"' "$smali" || die "missing ja_JP filter"
  grep -q 'const-string v12, "ko_KR"' "$smali" || die "missing ko_KR filter"
}

merge_classes_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-settings-locale-filter-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$OUT_DIR"
  cp "$STOCK_SETTINGS_APK" "${OUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" classes.dex > "${tmp}/classes.dex"
  (
    cd "$tmp"
    zip -q "${OUT_APK}.tmp" classes.dex
  )
  mv "${OUT_APK}.tmp" "$OUT_APK"

  local rebuilt_class_hash
  local out_class_hash
  rebuilt_class_hash="$(unzip -p "$REBUILT_UNSIGNED" classes.dex | shasum -a 256 | awk '{print $1}')"
  out_class_hash="$(unzip -p "$OUT_APK" classes.dex | shasum -a 256 | awk '{print $1}')"
  [ "$rebuilt_class_hash" = "$out_class_hash" ] || die "merged classes.dex hash mismatch"

  unzip -p "$OUT_APK" classes.dex | strings > "${tmp}/classes.strings"
  grep -q 'ja_JP' "${tmp}/classes.strings" || die "missing ja_JP constant in merged classes.dex"
  grep -q 'ko_KR' "${tmp}/classes.strings" || die "missing ko_KR constant in merged classes.dex"
}

case "${1:-}" in
  "" )
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

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$STOCK_SETTINGS_APK"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding SettingsSmartisan..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$STOCK_SETTINGS_APK" >/dev/null

echo "Applying SettingsSmartisan rebuild fixups..."
fixup_decoded_tree

echo "Patching LocalePickerFragment..."
patch_locale_picker

echo "Rebuilding patched SettingsSmartisan as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging patched classes.dex into stock SettingsSmartisan shell..."
merge_classes_into_stock_shell

echo "Writing signature boundary report..."
"$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"

{
  echo "built_apk=${OUT_APK}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "signature_report=${SIG_REPORT}"
  shasum -a 256 "$OUT_APK" "$REBUILT_UNSIGNED" "$STOCK_SETTINGS_APK"
  echo
  sed -n '1,60p' "$SIG_REPORT"
} >&2

echo "$OUT_APK"
