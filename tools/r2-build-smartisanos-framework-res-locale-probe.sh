#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
LOCALE_POLICY="${LOCALE_POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
ARSC_PRUNER="${ROOT_DIR}/tools/r2-arsc-prune-locales.py"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

OUTPUT_APK=""

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-smartisanos-framework-res-locale-probe.sh [--out <apk>]

Build an offline framework-smartisanos-res.apk locale-prune probe without
rebuilding the package through aapt2.

Why this exists:
  framework-smartisanos-res.apk contains a Smartisan private resource type:
    ^attr-private, type id 0x0b

  apktool/aapt2 can decode it but cannot safely rebuild it without normalizing
  the type to ordinary attr, which would change type identity. This tool avoids
  aapt2. It edits resources.arsc directly by removing locale-specific
  RES_TABLE_TYPE_TYPE chunks whose language is not English or Chinese.

The output changes only resources.arsc in the stock APK shell. AndroidManifest.xml
must remain byte-identical to stock. public.xml must remain stable after
decoding the merged output.

This is an offline high-risk framework probe. It does not build a system image,
does not build a super image, and is not flash-authorized by itself.
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

entry_exists() {
  local apk="$1"
  local entry="$2"
  unzip -Z1 "$apk" | awk -v entry="$entry" '$0 == entry { found = 1 } END { exit found ? 0 : 1 }'
}

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

merge_resources_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-smartisanos-framework-res-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  cp "$FW_SMARTISAN" "${OUTPUT_APK}.tmp"
  cp "$PRUNED_ARSC" "${tmp}/resources.arsc"
  touch -t 200901010000 "${tmp}/resources.arsc"
  (
    cd "$tmp"
    zip -X -q -0 "${OUTPUT_APK}.tmp" resources.arsc
  )
  mv "${OUTPUT_APK}.tmp" "$OUTPUT_APK"

  local pruned_hash
  local output_hash
  pruned_hash="$(shasum -a 256 "$PRUNED_ARSC" | awk '{print $1}')"
  output_hash="$(unzip -p "$OUTPUT_APK" resources.arsc | shasum -a 256 | awk '{print $1}')"
  [ "$pruned_hash" = "$output_hash" ] || die "merged resources.arsc hash mismatch"

  entry_exists "$OUTPUT_APK" AndroidManifest.xml || die "AndroidManifest.xml missing from output"
  stock_manifest_hash="$(unzip -p "$FW_SMARTISAN" AndroidManifest.xml | shasum -a 256 | awk '{print $1}')"
  out_manifest_hash="$(unzip -p "$OUTPUT_APK" AndroidManifest.xml | shasum -a 256 | awk '{print $1}')"
  [ "$stock_manifest_hash" = "$out_manifest_hash" ] || die "AndroidManifest.xml changed unexpectedly"
}

verify_decoded_output() {
  rm -rf "$CHECK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$CHECK_DIR" "$OUTPUT_APK" >/dev/null

  if find "$CHECK_DIR/res" -maxdepth 1 -type d \( -name 'values-ja*' -o -name 'values-ko*' \) | grep -q .; then
    find "$CHECK_DIR/res" -maxdepth 1 -type d \( -name 'values-ja*' -o -name 'values-ko*' \) | sort >&2
    die "decoded merged output still has ja/ko locale resource dirs"
  fi
  [ -d "$CHECK_DIR/res/values-zh-rCN" ] || die "decoded merged output missing values-zh-rCN"
  [ -d "$CHECK_DIR/res/values-zh-rTW" ] || die "decoded merged output missing values-zh-rTW"

  if ! diff -u "${STOCK_DECODED_DIR}/res/values/public.xml" "${CHECK_DIR}/res/values/public.xml" \
    > "${WORK_DIR}/public-xml.diff"; then
    die "public.xml changed after binary arsc prune; review ${WORK_DIR}/public-xml.diff"
  fi

  {
    echo "removed_locale_dirs=absent"
    echo "values-zh-rCN=present"
    echo "values-zh-rTW=present"
    echo "public_xml_diff_bytes=$(wc -c < "${WORK_DIR}/public-xml.diff" | tr -d ' ')"
  } > "$POLICY_CHECK"
  "$LOCALE_POLICY" --keep-languages en,zh "$OUTPUT_APK" > "$ARSC_POLICY_CHECK"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out)
      [ "$#" -ge 2 ] || die "--out requires a value"
      OUTPUT_APK="$2"
      shift 2
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
done

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$ARSC_PRUNER"
need_file "$LOCALE_POLICY"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"
need_executable "$LOCALE_POLICY"

WORK_DIR="${ROOT_DIR}/hard-rom/work/framework-smartisanos-res-locale-prune"
FRAMEWORK_DIR="${WORK_DIR}/framework"
STOCK_DECODED_DIR="${WORK_DIR}/stock-decoded"
CHECK_DIR="${WORK_DIR}/merged-check"
STOCK_ARSC="${WORK_DIR}/stock-resources.arsc"
PRUNED_ARSC="${WORK_DIR}/resources-pruned-en-zh.arsc"
PRUNE_REPORT="${WORK_DIR}/arsc-prune-report.json"
POLICY_CHECK="${WORK_DIR}/merged-policy-check.txt"
ARSC_POLICY_CHECK="${WORK_DIR}/arsc-policy-check.txt"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"

if [ -z "$OUTPUT_APK" ]; then
  OUTPUT_APK="${OUT_DIR}/framework-smartisanos-res-locale-prune-en-zh.apk"
else
  case "$OUTPUT_APK" in
    /*) ;;
    *) OUTPUT_APK="${ROOT_DIR}/${OUTPUT_APK}" ;;
  esac
  OUT_DIR="$(dirname "$OUTPUT_APK")"
fi

SIG_REPORT="${OUTPUT_APK%.apk}.signature.txt"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUTPUT_APK" "$SIG_REPORT"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding stock framework-smartisanos-res.apk for verification baseline..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$STOCK_DECODED_DIR" "$FW_SMARTISAN" >/dev/null

echo "Extracting stock resources.arsc..."
unzip -p "$FW_SMARTISAN" resources.arsc > "$STOCK_ARSC"

echo "Pruning non-English/non-Chinese resources.arsc config chunks..."
"$ARSC_PRUNER" "$STOCK_ARSC" "$PRUNED_ARSC" --keep-languages en,zh --report "$PRUNE_REPORT" >&2

echo "Merging pruned resources.arsc into stock APK shell..."
merge_resources_into_stock_shell

echo "Verifying decoded merged resources..."
verify_decoded_output

echo "Writing signature boundary report..."
"$SIGCHECK" "$OUTPUT_APK" > "$SIG_REPORT"
grep -q 'SHA-256 digest error for resources.arsc' "$SIG_REPORT" \
  || die "signature report does not show expected resources.arsc digest boundary"

{
  echo "stock_apk=${FW_SMARTISAN}"
  echo "built_apk=${OUTPUT_APK}"
  echo "stock_arsc=${STOCK_ARSC}"
  echo "pruned_arsc=${PRUNED_ARSC}"
  echo "prune_report=${PRUNE_REPORT}"
  echo "signature_report=${SIG_REPORT}"
  echo "policy_check=${POLICY_CHECK}"
  echo "arsc_policy_check=${ARSC_POLICY_CHECK}"
  echo "public_xml_diff=${WORK_DIR}/public-xml.diff"
  shasum -a 256 "$OUTPUT_APK" "$PRUNED_ARSC" "$STOCK_ARSC" "$FW_SMARTISAN"
  echo
  sed -n '1,80p' "$POLICY_CHECK"
  echo
  python3 - "$PRUNE_REPORT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print("removed_count=" + str(data["removed_count"]))
print("kept_locale_count=" + str(data["kept_locale_count"]))
for row in data["removed"]:
    print("removed={type_name}:{language}_{region}:offset={offset}:size={size}".format(**row))
PY
  echo
  sed -n '1,80p' "$SIG_REPORT"
} >&2

echo "$OUTPUT_APK"
