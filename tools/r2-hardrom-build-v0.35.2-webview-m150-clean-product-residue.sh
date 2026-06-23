#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"

VARIANT="v0.35.2-webview-m150-clean-product-residue"
SOURCE_VARIANT="v0.35.1-webview-m150-browserchrome-deodex"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.35.1-webview-m150-browserchrome-deodex.sparse.img}"
SOURCE_SPARSE_SHA256="c86a1f734ebb243d279291023a2427c2c0d0cf183d99aec8e8bf6af8573e9559"
SOURCE_SYSTEM_B_IMG="${SOURCE_SYSTEM_B_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.35.1-webview-m150-browserchrome-deodex.img}"
SOURCE_PRODUCT_B_IMG="${SOURCE_PRODUCT_B_IMG:-${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.1-webview-m150-browserchrome-deodex.img}"
SOURCE_SYSTEM_B_SHA256="fd906f64df8859d6da6ec3752849cb1813802a880a801a9c6f764400679ca795"
SOURCE_PRODUCT_B_SHA256="1122ee932f1aca8305cdc258fa3e6ab1638fcc9640de7b29dfb4e7f04e212e83"

OUT_DIR="${ROOT_DIR}/hard-rom/build"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
FALLBACK_EXTRACT_DIR="${WORK_DIR}/source-v0351-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v0351-super.raw.img"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
PRODUCT_B_IMG="${OUT_DIR}/product-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
OUT_RAW_FOR_LPDUMP="${WORK_DIR}/candidate-${VARIANT}-super.raw-for-lpdump.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SUPER_SIZE=10737418240
METADATA_SIZE=65536
METADATA_SLOTS=3
GROUP_A_MAX=5364514816
GROUP_B_MAX=5364514816

SYSTEM_A_SIZE=3052314624
PRODUCT_A_SIZE=255815680
VENDOR_A_SIZE=941768704
ODM_A_SIZE=917504
SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768
PRODUCT_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"

SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSERCHROME_OAT_DIR="/system/app/BrowserChrome/oat"
PRODUCT_WEBVIEW_DIR="/app/webview"
PRODUCT_WEBVIEW_APK="/app/webview/webview.apk"
PRODUCT_WEBVIEW_HELD="/app/webview/.webview.apk.smartisax-v035-stock-held"
DONOR_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
STOCK_PRODUCT_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"

PURPOSE="v0.35.1 follow-up that leaves the M150 /system WebView provider and BrowserChrome deodex fix unchanged, but fully removes the old /product/app/webview hidden stock backup and stale oat/vdex tree from product_b."

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.35.2-webview-m150-clean-product-residue.sh

Build v0.35.2 on top of the live-proven v0.35.1 sparse image.

Scope:
  - retain v0.35.1 system_b byte-for-byte in the sparse source
  - clone v0.35.1 product_b
  - remove /product/app/webview entirely, including the hidden stock-held
    WebView backup and stale arm/arm64 oat/vdex files
  - rebuild product_b AVB hashtree footer with FEC roots=2
  - rebuild the sparse super with v0.35.1 retained partitions and cleaned
    product_b

This script does not flash, reboot, erase misc, write settings, clear
package_cache, install apps, or mutate /data. Live testing requires explicit
user confirmation after offline verification and preflight.
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

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

copy_clone_or_plain() {
  local src="$1"
  local dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

debugfs_rm_tree() {
  local image="$1"
  local path="$2"

  if ! debugfs_path_exists "$image" "$path"; then
    return 1
  fi

  while IFS=$'\t' read -r mode name; do
    [ -n "${name:-}" ] || continue
    local child="${path}/${name}"
    if [[ "$mode" == 04* ]]; then
      debugfs_rm_tree "$image" "$child" || true
    else
      "$DEBUGFS" -w -R "rm ${child}" "$image" >/dev/null 2>&1 || true
    fi
  done < <("$DEBUGFS" -R "ls -p ${path}" "$image" 2>/dev/null | \
    awk -F/ '$0 ~ /^\// && $6 != "." && $6 != ".." { print $3 "\t" $6 }')

  "$DEBUGFS" -w -R "rmdir ${path}" "$image" >/dev/null 2>&1 || true
  return 0
}

fsck_rw() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

verify_dumped_apk() {
  local image="$1"
  local src="$2"
  local expected="$3"
  local dst="$4"
  debugfs_dump "$image" "$src" "$dst"
  [ "$(sha256_one "$dst")" = "$expected" ] || die "dumped APK hash mismatch for ${src}"
  unzip -t "$dst" >/dev/null || die "dumped APK zip test failed for ${src}"
}

rebuild_product_footer() {
  local image="$1"
  PATH="$(dirname "$FEC"):${PATH}" python3 "$AVBTOOL" add_hashtree_footer \
    --image "$image" \
    --partition_size "$PRODUCT_B_PARTITION_SIZE" \
    --partition_name product \
    --hash_algorithm sha1 \
    --salt "$PRODUCT_B_SALT" \
    --block_size 4096 \
    --fec_num_roots 2 \
    --prop com.android.build.product.fingerprint:qti/aries/aries:11/RKQ1.201217.002/1658135499:user/dev-keys \
    --prop com.android.build.product.os_version:11 \
    --prop com.android.build.product.security_patch:2022-06-10 \
    --prop com.android.build.product.security_patch:2022-06-10
}

prepare_inputs() {
  local part
  local extract_dir="$FALLBACK_EXTRACT_DIR"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  if [ ! -f "${extract_dir}/system_a.img" ] || [ ! -f "${extract_dir}/system_ext_b.img" ]; then
    echo "Retained source partitions are missing; extracting selected slot-1 partitions from v0.35.1 sparse super..."
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    rm -f "$SOURCE_RAW"
    "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
    [ "$(size_bytes "$SOURCE_RAW")" -eq "$SUPER_SIZE" ] || die "source raw super size mismatch"
    "$LPUNPACK" --slot=1 \
      --partition=system_a \
      --partition=product_a \
      --partition=vendor_a \
      --partition=odm_a \
      --partition=system_ext_b \
      --partition=vendor_b \
      --partition=odm_b \
      "$SOURCE_RAW" "$extract_dir" >/dev/null
    rm -f "$SOURCE_RAW"
  else
    echo "Using existing retained source partitions: ${extract_dir}"
  fi
  for part in system_a product_a vendor_a odm_a system_ext_b vendor_b odm_b; do
    need_file "${extract_dir}/${part}.img"
  done
  [ "$(size_bytes "${extract_dir}/system_a.img")" -eq "$SYSTEM_A_SIZE" ] || die "system_a size mismatch"
  [ "$(size_bytes "${extract_dir}/product_a.img")" -eq "$PRODUCT_A_SIZE" ] || die "product_a size mismatch"
  [ "$(size_bytes "${extract_dir}/vendor_a.img")" -eq "$VENDOR_A_SIZE" ] || die "vendor_a size mismatch"
  [ "$(size_bytes "${extract_dir}/odm_a.img")" -eq "$ODM_A_SIZE" ] || die "odm_a size mismatch"
  [ "$(size_bytes "${extract_dir}/system_ext_b.img")" -eq "$SYSTEM_EXT_B_SIZE" ] || die "system_ext_b size mismatch"
  [ "$(size_bytes "${extract_dir}/vendor_b.img")" -eq "$VENDOR_B_SIZE" ] || die "vendor_b size mismatch"
  [ "$(size_bytes "${extract_dir}/odm_b.img")" -eq "$ODM_B_SIZE" ] || die "odm_b size mismatch"
  SOURCE_EXTRACT_DIR="$extract_dir"
}

dump_lpdump() {
  rm -f "$OUT_RAW_FOR_LPDUMP"
  "$SIMG2IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP"
  [ "$(size_bytes "$OUT_RAW_FOR_LPDUMP")" -eq "$SUPER_SIZE" ] || die "candidate raw super size mismatch"
  for slot in 0 1; do
    "$LPDUMP" -s "$slot" "$OUT_RAW_FOR_LPDUMP" > "${OUT_SPARSE}.lpdump-slot${slot}.txt"
  done
  cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"
  rm -f "$OUT_RAW_FOR_LPDUMP"
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

need_executable "$LPMAKE"
need_executable "$LPDUMP"
need_executable "$LPUNPACK"
need_executable "$SIMG2IMG"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$FEC"
need_file "$AVBTOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$PRODUCT_B_IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP" "$SOURCE_RAW" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt" \
  "${OUT_SPARSE}.lpdump"*
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.txt "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*-avb-info.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
  echo

  echo "## source"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
  echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
  echo "source_product_b_sha256=${SOURCE_PRODUCT_B_SHA256}"
  prepare_inputs
  echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
  verify_dumped_apk "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_WEBVIEW_SHA256" "${WORK_DIR}/source-system-webview.apk"
  verify_dumped_apk "$SOURCE_SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$STOCK_BROWSERCHROME_SHA256" "${WORK_DIR}/source-browserchrome.apk"
  ! debugfs_path_exists "$SOURCE_SYSTEM_B_IMG" "$BROWSERCHROME_OAT_DIR" \
    || die "source BrowserChrome oat dir unexpectedly exists"
  echo "source_system_webview=ok"
  echo "source_browserchrome_oat_absent=ok"
  echo

  echo "## clone product_b"
  copy_clone_or_plain "$SOURCE_PRODUCT_B_IMG" "$PRODUCT_B_IMG"
  [ "$(size_bytes "$PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] \
    || die "cloned product_b size mismatch"
  require_hash "$PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  echo

  echo "## product_b cleanup"
  verify_dumped_apk "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_HELD" "$STOCK_PRODUCT_WEBVIEW_SHA256" "${WORK_DIR}/product-webview-stock-held-before.apk"
  ! debugfs_path_exists "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_APK" \
    || die "source product public WebView APK unexpectedly exists"
  python3 "$AVBTOOL" erase_footer --image "$PRODUCT_B_IMG"
  [ "$(size_bytes "$PRODUCT_B_IMG")" -eq "$PRODUCT_B_EXT4_SIZE" ] \
    || die "product_b pure ext4 size mismatch after footer erase"
  fsck_rw "$PRODUCT_B_IMG"
  product_free_blocks_before="$(debugfs_stat_value "$PRODUCT_B_IMG" "Free blocks")"
  : > "${WORK_DIR}/removed-product-webview-paths.tsv"
  if debugfs_rm_tree "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_DIR"; then
    printf '%s\tremoved\told product WebView backup and oat/vdex tree\n' "$PRODUCT_WEBVIEW_DIR" \
      >> "${WORK_DIR}/removed-product-webview-paths.tsv"
  else
    die "expected product WebView directory was already absent before v0.35.2 cleanup"
  fi
  ! debugfs_path_exists "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_DIR" \
    || die "product WebView directory still exists after removal"
  fsck_rw "$PRODUCT_B_IMG"
  fsck_ro "$PRODUCT_B_IMG"
  ! debugfs_path_exists "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_DIR" \
    || die "product WebView directory reappeared after fsck"
  product_free_blocks_after="$(debugfs_stat_value "$PRODUCT_B_IMG" "Free blocks")"
  rebuild_product_footer "$PRODUCT_B_IMG"
  [ "$(size_bytes "$PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] \
    || die "product_b FEC size mismatch"
  python3 "$AVBTOOL" info_image --image "$PRODUCT_B_IMG" > "${WORK_DIR}/product-b-v0352-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/product-b-v0352-avb-info.txt" \
    || die "product_b lost FEC roots"
  echo "product_webview_dir_removed=yes"
  echo "product_free_blocks_before=${product_free_blocks_before}"
  echo "product_free_blocks_after=${product_free_blocks_after}"
  echo

  echo "## rebuild sparse super"
  "$LPMAKE" \
    --metadata-size="$METADATA_SIZE" \
    --metadata-slots="$METADATA_SLOTS" \
    --super-name=super \
    --device="super:${SUPER_SIZE}" \
    --group="qti_dynamic_partitions_a:${GROUP_A_MAX}" \
    --group="qti_dynamic_partitions_b:${GROUP_B_MAX}" \
    --partition="system_a:readonly:${SYSTEM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="product_a:readonly:${PRODUCT_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="vendor_a:readonly:${VENDOR_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="odm_a:readonly:${ODM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="system_b:readonly:${SYSTEM_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="system_ext_b:readonly:${SYSTEM_EXT_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="product_b:readonly:${PRODUCT_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b" \
    --image="system_a=${SOURCE_EXTRACT_DIR}/system_a.img" \
    --image="product_a=${SOURCE_EXTRACT_DIR}/product_a.img" \
    --image="vendor_a=${SOURCE_EXTRACT_DIR}/vendor_a.img" \
    --image="odm_a=${SOURCE_EXTRACT_DIR}/odm_a.img" \
    --image="system_b=${SOURCE_SYSTEM_B_IMG}" \
    --image="system_ext_b=${SOURCE_EXTRACT_DIR}/system_ext_b.img" \
    --image="product_b=${PRODUCT_B_IMG}" \
    --image="vendor_b=${SOURCE_EXTRACT_DIR}/vendor_b.img" \
    --image="odm_b=${SOURCE_EXTRACT_DIR}/odm_b.img" \
    --block-size=4096 \
    --sparse \
    --output="$OUT_SPARSE"
  dump_lpdump
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=$(sha256_one "$OUT_SPARSE")"
  echo

  product_hash="$(sha256_one "$PRODUCT_B_IMG")"
  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse_super=${SOURCE_SPARSE}"
    echo "source_sparse_super_sha256=${SOURCE_SPARSE_SHA256}"
    echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
    echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
    echo "source_product_b_sha256=${SOURCE_PRODUCT_B_SHA256}"
    echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
    echo "patched_partitions=product_b"
    echo "retained_partitions_from_source=system_a,product_a,vendor_a,odm_a,system_b,system_ext_b,vendor_b,odm_b"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "product_b_image=${PRODUCT_B_IMG}"
    echo "product_b_sha256=${product_hash}"
    echo "system_webview_apk=${SYSTEM_WEBVIEW_APK}"
    echo "system_webview_apk_sha256=${DONOR_WEBVIEW_SHA256}"
    echo "browserchrome_apk=${BROWSERCHROME_APK}"
    echo "browserchrome_apk_sha256=${STOCK_BROWSERCHROME_SHA256}"
    echo "browserchrome_oat_absent_in_source_system=yes"
    echo "removed_product_webview_dir=${PRODUCT_WEBVIEW_DIR}"
    echo "removed_product_webview_held_path=${PRODUCT_WEBVIEW_HELD}"
    echo "removed_product_webview_oat_tree=${PRODUCT_WEBVIEW_DIR}/oat"
    echo "product_webview_dir_absent_after_fsck=yes"
    echo "stock_product_webview_sha256=${STOCK_PRODUCT_WEBVIEW_SHA256}"
    echo "product_free_blocks_before=${product_free_blocks_before}"
    echo "product_free_blocks_after=${product_free_blocks_after}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "product_b_ext4_size=${PRODUCT_B_EXT4_SIZE}"
    echo "fec_status=product_b_generated_roots_2_system_b_retained_from_v0351"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# removed_product_webview_paths"
    cat "${WORK_DIR}/removed-product-webview-paths.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$PRODUCT_B_IMG" "$SOURCE_SPARSE" "$SOURCE_SYSTEM_B_IMG"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "Product image: ${PRODUCT_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
