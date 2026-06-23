#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
POLICY="${POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img"
EXPECTED_PRODUCT_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
EXPECTED_SYSTEM_EXT_IMG="${ROOT_DIR}/hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"

PHOTO_TABLE_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.dreams.phototable-locale-prune-en-zh.apk"
CONFDIALER_REGULAR_APK="${ROOT_DIR}/hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh.apk"
CONFDIALER_SAMESIZE_APK="${ROOT_DIR}/hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh-samesize.apk"
STOCK_CONFDIALER_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system_ext/app/ConferenceDialer/ConferenceDialer.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh --offline-image
  tools/r2-verify-v0.17b-product-system_ext-apk-only-locale-prune.sh --offline-partition-images

--offline-image verifies the generated product_b/system_ext_b images and
flashable sparse super:
  - PhotoTable matches the expected APK-only candidate and has a held-stock path
  - ConferenceDialer matches the same-size candidate used for system_ext
  - dumped APK ZIP integrity passes
  - dumped APK resources.arsc locale policy contains only English/Chinese chunks
  - sparse product_b and system_ext_b logical slices match generated images

The script never flashes, reboots, erases misc, or changes /data.
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

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

zip_entry_hash() {
  local apk="$1"
  local entry="$2"
  unzip -p "$apk" "$entry" | shasum -a 256 | awk '{print $1}'
}

compare_file_hash() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local actual_hash
  local expected_hash
  actual_hash="$(sha256_one "$actual")"
  expected_hash="$(sha256_one "$expected")"
  [ "$actual_hash" = "$expected_hash" ] || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$actual"
}

verify_locale_policy() {
  local apk="$1"
  local label="$2"
  local policy_out
  policy_out="$("$POLICY" --keep-languages en,zh "$apk")"
  grep -q "bad_locale_chunk_count=0" <<<"$policy_out" || {
    echo "$policy_out" >&2
    die "${label} locale policy failed"
  }
  echo "${label}_locale_policy=ok"
  echo "$policy_out"
}

verify_same_size_confdialer_scope() {
  [ "$(size_bytes "$STOCK_CONFDIALER_APK")" -eq "$(size_bytes "$CONFDIALER_SAMESIZE_APK")" ] \
    || die "ConferenceDialer same-size APK does not match stock size"
  [ "$(zip_entry_hash "$STOCK_CONFDIALER_APK" "AndroidManifest.xml")" = "$(zip_entry_hash "$CONFDIALER_SAMESIZE_APK" "AndroidManifest.xml")" ] \
    || die "ConferenceDialer same-size AndroidManifest.xml changed"
  [ "$(zip_entry_hash "$STOCK_CONFDIALER_APK" "classes.dex")" = "$(zip_entry_hash "$CONFDIALER_SAMESIZE_APK" "classes.dex")" ] \
    || die "ConferenceDialer same-size classes.dex changed"
  echo "confdialer_same_size_scope=ok"
}

verify_expected_inputs() {
  need_file "$PHOTO_TABLE_APK"
  need_file "$CONFDIALER_REGULAR_APK"
  need_file "$CONFDIALER_SAMESIZE_APK"
  need_file "$STOCK_CONFDIALER_APK"
  need_file "$POLICY"
  need_executable "$POLICY"
  unzip -t "$PHOTO_TABLE_APK" >/dev/null
  unzip -t "$CONFDIALER_REGULAR_APK" >/dev/null
  unzip -t "$CONFDIALER_SAMESIZE_APK" >/dev/null
  verify_same_size_confdialer_scope
}

dump_one() {
  local image="$1"
  local src_path="$2"
  local out="$3"
  "$DEBUGFS" -R "dump ${src_path} ${out}" "$image" >/dev/null 2>&1
  need_file "$out"
}

verify_held_path() {
  local image="$1"
  local path="$2"
  debugfs_path_exists "$image" "$path" || die "missing held-stock path: ${path}"
  echo "held_stock_path=${path}"
}

dump_and_verify_partition_images() {
  local dump_dir="$1"

  dump_one "$EXPECTED_PRODUCT_IMG" "/app/PhotoTable/PhotoTable.apk" "${dump_dir}/PhotoTable.apk"
  dump_one "$EXPECTED_SYSTEM_EXT_IMG" "/app/ConferenceDialer/ConferenceDialer.apk" "${dump_dir}/ConferenceDialer.apk"

  compare_file_hash "${dump_dir}/PhotoTable.apk" "$PHOTO_TABLE_APK" "product/PhotoTable.apk"
  compare_file_hash "${dump_dir}/ConferenceDialer.apk" "$CONFDIALER_SAMESIZE_APK" "system_ext/ConferenceDialer.apk"

  unzip -t "${dump_dir}/PhotoTable.apk" >/dev/null
  unzip -t "${dump_dir}/ConferenceDialer.apk" >/dev/null
  echo "zip_integrity=ok"

  verify_locale_policy "${dump_dir}/PhotoTable.apk" "product_phototable"
  verify_locale_policy "${dump_dir}/ConferenceDialer.apk" "system_ext_confdialer"

  verify_held_path "$EXPECTED_PRODUCT_IMG" "/app/PhotoTable/.PhotoTable.apk.smartisax-v017b-stock-held"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_PRODUCT_IMG"
  need_file "$EXPECTED_SYSTEM_EXT_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.17b-offline-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.17b-product-system_ext-apk-only-locale-prune offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_product_img=${EXPECTED_PRODUCT_IMG}"
    echo "expected_system_ext_img=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## same-size scope"
    verify_same_size_confdialer_scope
    echo

    echo "## inserted APKs"
    dump_and_verify_partition_images "$dump_dir"
    echo

    echo "## sparse slices"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "product_b=${EXPECTED_PRODUCT_IMG}"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_ext_b=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_PRODUCT_IMG" "$EXPECTED_SYSTEM_EXT_IMG" \
      "$PHOTO_TABLE_APK" \
      "$CONFDIALER_REGULAR_APK" \
      "$CONFDIALER_SAMESIZE_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.17b offline image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

run_offline_partition_images() {
  need_executable "$DEBUGFS"
  need_file "$EXPECTED_PRODUCT_IMG"
  need_file "$EXPECTED_SYSTEM_EXT_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.17b-offline-partition-images-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-partition-images-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.17b-product-system_ext-apk-only-locale-prune offline partition-image verification"
    echo "timestamp=${timestamp}"
    echo "expected_product_img=${EXPECTED_PRODUCT_IMG}"
    echo "expected_system_ext_img=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## same-size scope"
    verify_same_size_confdialer_scope
    echo

    echo "## inserted APKs"
    dump_and_verify_partition_images "$dump_dir"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_PRODUCT_IMG" "$EXPECTED_SYSTEM_EXT_IMG" \
      "$PHOTO_TABLE_APK" \
      "$CONFDIALER_REGULAR_APK" \
      "$CONFDIALER_SAMESIZE_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.17b offline partition-image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

case "${1:---offline-image}" in
  --offline-image)
    run_offline_image
    ;;
  --offline-partition-images)
    run_offline_partition_images
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
