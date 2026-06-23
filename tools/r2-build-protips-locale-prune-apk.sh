#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
STOCK_APK="${RAW}/system/system/app/Protips/Protips.apk"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.9-protips-locale-prune-apktool"
FRAMEWORK_DIR="${WORK_DIR}/framework"
DECODED_DIR="${WORK_DIR}/Protips"
CHECK_DIR="${WORK_DIR}/Protips-merged-check"
REBUILT_UNSIGNED="${WORK_DIR}/Protips-locale-prune-rebuilt-unsigned.apk"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/Protips-locale-prune-ja-ko.apk"
SIG_REPORT="${OUT_DIR}/Protips-locale-prune-ja-ko.signature.txt"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-protips-locale-prune-apk.sh

Build an offline Protips.apk resource-prune candidate that removes Japanese and
Korean compiled values resources while keeping English, Simplified Chinese, and
Traditional Chinese.

This is an L2 language hard-prune toolchain probe. It changes only
resources.arsc in the stock Protips APK shell; classes.dex and
AndroidManifest.xml must remain byte-identical to stock.

The output APK is not a standalone installable app and is not flash-authorized.
It intentionally breaks ordinary JAR digest verification for resources.arsc and
tests the same original-cert-preserving system-partition boundary needed for
broader ROM language pruning.
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

prune_decoded_locales() {
  need_file "${DECODED_DIR}/apktool.yml"

  find "${DECODED_DIR}/res" -maxdepth 1 -type d \
    \( -name 'values-ja*' -o -name 'values-ko*' \) -print | sort > "${WORK_DIR}/removed-locale-dirs.txt"

  grep -q 'values-ja' "${WORK_DIR}/removed-locale-dirs.txt" || die "no Japanese values dirs found"
  grep -q 'values-ko' "${WORK_DIR}/removed-locale-dirs.txt" || die "no Korean values dirs found"

  rm -rf "${DECODED_DIR}/res"/values-ja* "${DECODED_DIR}/res"/values-ko*

  ! find "${DECODED_DIR}/res" -maxdepth 1 -type d \
    \( -name 'values-ja*' -o -name 'values-ko*' \) | grep -q . \
    || die "Japanese/Korean values dirs remained after prune"
  [ -d "${DECODED_DIR}/res/values-zh-rCN" ] || die "missing zh-rCN values dir after prune"
  [ -d "${DECODED_DIR}/res/values-zh-rTW" ] || die "missing zh-rTW values dir after prune"
}

merge_resources_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-protips-locale-prune-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$OUT_DIR"
  cp "$STOCK_APK" "${OUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" resources.arsc > "${tmp}/resources.arsc"
  touch -t 200901010000 "${tmp}/resources.arsc"
  (
    cd "$tmp"
    zip -X -q -0 "${OUT_APK}.tmp" resources.arsc
  )
  mv "${OUT_APK}.tmp" "$OUT_APK"

  local rebuilt_res_hash
  local out_res_hash
  rebuilt_res_hash="$(unzip -p "$REBUILT_UNSIGNED" resources.arsc | shasum -a 256 | awk '{print $1}')"
  out_res_hash="$(unzip -p "$OUT_APK" resources.arsc | shasum -a 256 | awk '{print $1}')"
  [ "$rebuilt_res_hash" = "$out_res_hash" ] || die "merged resources.arsc hash mismatch"

  for entry in classes.dex AndroidManifest.xml; do
    stock_hash="$(unzip -p "$STOCK_APK" "$entry" | shasum -a 256 | awk '{print $1}')"
    out_hash="$(unzip -p "$OUT_APK" "$entry" | shasum -a 256 | awk '{print $1}')"
    [ "$stock_hash" = "$out_hash" ] || die "${entry} changed unexpectedly"
  done
}

verify_merged_resources() {
  rm -rf "$CHECK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$CHECK_DIR" "$OUT_APK" >/dev/null

  ! find "${CHECK_DIR}/res" -maxdepth 1 -type d \
    \( -name 'values-ja*' -o -name 'values-ko*' \) | grep -q . \
    || die "merged APK still decodes Japanese/Korean values dirs"
  [ -d "${CHECK_DIR}/res/values-zh-rCN" ] || die "merged APK missing zh-rCN values dir"
  [ -d "${CHECK_DIR}/res/values-zh-rTW" ] || die "merged APK missing zh-rTW values dir"
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
need_file "$STOCK_APK"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT" "${OUT_APK}.signature.txt"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding Protips..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$STOCK_APK" >/dev/null

echo "Pruning Japanese/Korean values resources..."
prune_decoded_locales

echo "Rebuilding Protips resource-prune intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging pruned resources.arsc into stock Protips shell..."
merge_resources_into_stock_shell

echo "Verifying merged resource table..."
verify_merged_resources

echo "Writing signature boundary report..."
"$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"
grep -q '^keytool_status=1$' "$SIG_REPORT" \
  || die "unexpected Protips keytool boundary; review ${SIG_REPORT}"
grep -q 'SHA-256 digest error for resources.arsc' "$SIG_REPORT" \
  || die "Protips signature report does not show the expected resources.arsc digest boundary"

{
  echo "built_apk=${OUT_APK}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "signature_report=${SIG_REPORT}"
  echo "removed_locale_dirs=${WORK_DIR}/removed-locale-dirs.txt"
  shasum -a 256 "$OUT_APK" "$REBUILT_UNSIGNED" "$STOCK_APK"
  echo
  sed -n '1,60p' "$SIG_REPORT"
} >&2

echo "$OUT_APK"
