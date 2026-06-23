#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"

VARIANT="v0.35.1-webview-m150-browserchrome-deodex"
SOURCE_VARIANT="v0.35-webview-m150-system-provider"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.35-webview-m150-system-provider.sparse.img}"
SOURCE_SPARSE_SHA256="e3e122faec2c01e1c710e9ad4661bbfd2c072573aa0e398eeb7afb5fa57c06ed"
SOURCE_SYSTEM_B_IMG="${SOURCE_SYSTEM_B_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.35-webview-m150-system-provider.img}"
SOURCE_PRODUCT_B_IMG="${SOURCE_PRODUCT_B_IMG:-${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35-webview-m150-system-provider.img}"
SOURCE_EXTRACT_DIR="${SOURCE_EXTRACT_DIR:-${ROOT_DIR}/hard-rom/work/v0.34-system-b-ext4-grow-fec/candidate-v034-fec-slot1}"
SOURCE_SYSTEM_B_SHA256="37a1d97782b0edbe31d0f4fc572ef22ac6a74c7548bc693c0eae853900279560"
SOURCE_PRODUCT_B_SHA256="1122ee932f1aca8305cdc258fa3e6ab1638fcc9640de7b29dfb4e7f04e212e83"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
DONOR_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_PRODUCT_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
FALLBACK_EXTRACT_DIR="${WORK_DIR}/source-v035-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v035-super.raw.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
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
SYSTEM_B_EXT4_SIZE=3132964864
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"

BROWSERCHROME_DIR="/system/app/BrowserChrome"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSERCHROME_OAT_DIR="/system/app/BrowserChrome/oat"
BROWSERCHROME_ARM64_DIR="/system/app/BrowserChrome/oat/arm64"
BROWSERCHROME_ODEX="/system/app/BrowserChrome/oat/arm64/BrowserChrome.odex"
BROWSERCHROME_VDEX="/system/app/BrowserChrome/oat/arm64/BrowserChrome.vdex"
SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
PRODUCT_WEBVIEW_HELD="/app/webview/.webview.apk.smartisax-v035-stock-held"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a363d18}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-20 15:11:20 +0800; invalidates BrowserChrome package/oat state after deleting prebuilt odex/vdex}"

PURPOSE="v0.35 follow-up that keeps the M150 com.android.webview system provider unchanged and removes BrowserChrome prebuilt oat/vdex so ART must fall back to APK dex for the stock system browser renderer."

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

check_size() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
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

set_dir_time() {
  local image="$1"
  local dir="$2"
  local tag="$3"
  local cmd_file="${WORK_DIR}/mtime-${tag}.debugfs"
  debugfs_path_exists "$image" "$dir" || die "missing directory: ${dir}"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE}"
}

remove_browserchrome_oat() {
  local image="$1"
  local cmd_file="${WORK_DIR}/remove-browserchrome-oat.debugfs"
  debugfs_path_exists "$image" "$BROWSERCHROME_APK" || die "missing BrowserChrome APK"
  debugfs_path_exists "$image" "$BROWSERCHROME_ODEX" || die "missing BrowserChrome odex"
  debugfs_path_exists "$image" "$BROWSERCHROME_VDEX" || die "missing BrowserChrome vdex"
  {
    echo "rm ${BROWSERCHROME_ODEX}"
    echo "rm ${BROWSERCHROME_VDEX}"
    echo "rmdir ${BROWSERCHROME_ARM64_DIR}"
    echo "rmdir ${BROWSERCHROME_OAT_DIR}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  ! debugfs_path_exists "$image" "$BROWSERCHROME_ODEX" || die "BrowserChrome odex still exists"
  ! debugfs_path_exists "$image" "$BROWSERCHROME_VDEX" || die "BrowserChrome vdex still exists"
  ! debugfs_path_exists "$image" "$BROWSERCHROME_OAT_DIR" || die "BrowserChrome oat dir still exists"
  set_dir_time "$image" "$BROWSERCHROME_DIR" "browserchrome-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
}

rebuild_system_footer() {
  local image="$1"
  PATH="$(dirname "$FEC"):${PATH}" python3 "$AVBTOOL" add_hashtree_footer \
    --image "$image" \
    --partition_size "$SYSTEM_B_PARTITION_SIZE" \
    --partition_name system \
    --hash_algorithm sha1 \
    --salt "$SYSTEM_B_SALT" \
    --block_size 4096 \
    --fec_num_roots 2 \
    --prop com.android.build.system.fingerprint:qti/aries/aries:11/RKQ1.201217.002/1658135499:user/dev-keys \
    --prop com.android.build.system.os_version:11 \
    --prop com.android.build.system.security_patch:2022-06-10 \
    --prop com.android.build.system.security_patch:2022-06-10
}

prepare_inputs() {
  local part
  local extract_dir="$SOURCE_EXTRACT_DIR"
  require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
  if [ ! -f "${extract_dir}/system_a.img" ] || [ ! -f "${extract_dir}/system_ext_b.img" ]; then
    extract_dir="$FALLBACK_EXTRACT_DIR"
    echo "Source retained partitions are missing; extracting selected slot-1 partitions from v0.35 sparse super..."
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    rm -f "$SOURCE_RAW"
    "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
    check_size "source raw super" "$SOURCE_RAW" "$SUPER_SIZE"
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
  fi
  SOURCE_EXTRACT_DIR="$extract_dir"
  for part in system_a product_a vendor_a odm_a system_ext_b vendor_b odm_b; do
    need_file "${SOURCE_EXTRACT_DIR}/${part}.img"
  done
  check_size system_a "${SOURCE_EXTRACT_DIR}/system_a.img" "$SYSTEM_A_SIZE"
  check_size product_a "${SOURCE_EXTRACT_DIR}/product_a.img" "$PRODUCT_A_SIZE"
  check_size vendor_a "${SOURCE_EXTRACT_DIR}/vendor_a.img" "$VENDOR_A_SIZE"
  check_size odm_a "${SOURCE_EXTRACT_DIR}/odm_a.img" "$ODM_A_SIZE"
  check_size system_ext_b "${SOURCE_EXTRACT_DIR}/system_ext_b.img" "$SYSTEM_EXT_B_SIZE"
  check_size vendor_b "${SOURCE_EXTRACT_DIR}/vendor_b.img" "$VENDOR_B_SIZE"
  check_size odm_b "${SOURCE_EXTRACT_DIR}/odm_b.img" "$ODM_B_SIZE"
  check_size source_system_b "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  check_size source_product_b "$SOURCE_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE"
}

dump_lpdump() {
  rm -f "$OUT_RAW_FOR_LPDUMP"
  "$SIMG2IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP"
  check_size "candidate raw super for lpdump" "$OUT_RAW_FOR_LPDUMP" "$SUPER_SIZE"
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
    sed -n '1,80p' "$0"
    exit 0
    ;;
  *)
    echo "Usage: $0" >&2
    exit 2
    ;;
esac

need_executable "$LPMAKE"
need_executable "$LPDUMP"
need_executable "$LPUNPACK"
need_executable "$SIMG2IMG"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_file "$AVBTOOL"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$PRODUCT_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$OUT_RAW_FOR_LPDUMP" \
  "${OUT_SPARSE}.lpdump"* "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*-avb-info.txt

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
  prepare_inputs
  echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size "system_b pure ext4" "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  verify_dumped_apk "$SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$STOCK_BROWSERCHROME_SHA256" "${WORK_DIR}/browserchrome-before.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_WEBVIEW_SHA256" "${WORK_DIR}/system-webview.apk"
  remove_browserchrome_oat "$SYSTEM_B_IMG"
  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_dumped_apk "$SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$STOCK_BROWSERCHROME_SHA256" "${WORK_DIR}/browserchrome-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_WEBVIEW_SHA256" "${WORK_DIR}/system-webview-after.apk"
  browserchrome_oat_removed="yes"
  system_free_blocks="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "browserchrome_oat_removed=${browserchrome_oat_removed}"
  echo "system_b_free_blocks_after_deodex=${system_free_blocks}"
  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size "system_b FEC image" "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-v0351-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-v0351-avb-info.txt" || die "system_b lost FEC roots"
  echo

  echo "## clone product_b"
  copy_clone_or_plain "$SOURCE_PRODUCT_B_IMG" "$PRODUCT_B_IMG"
  check_size "product_b FEC image" "$PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE"
  verify_dumped_apk "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_HELD" "$STOCK_PRODUCT_WEBVIEW_SHA256" "${WORK_DIR}/product-webview-stock-held.apk"
  echo "product_b_clone_sha256=$(sha256_one "$PRODUCT_B_IMG")"
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
    --image="system_b=${SYSTEM_B_IMG}" \
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

  system_hash="$(sha256_one "$SYSTEM_B_IMG")"
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
    echo "patched_partitions=system_b"
    echo "retained_partitions_from_source=system_a,product_a,vendor_a,odm_a,system_ext_b,product_b,vendor_b,odm_b"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "product_b_image=${PRODUCT_B_IMG}"
    echo "product_b_sha256=${product_hash}"
    echo "browserchrome_apk=${BROWSERCHROME_APK}"
    echo "browserchrome_apk_sha256=${STOCK_BROWSERCHROME_SHA256}"
    echo "browserchrome_removed_paths=${BROWSERCHROME_ODEX},${BROWSERCHROME_VDEX}"
    echo "browserchrome_oat_removed=${browserchrome_oat_removed}"
    echo "system_webview_apk=${SYSTEM_WEBVIEW_APK}"
    echo "system_webview_apk_sha256=${DONOR_WEBVIEW_SHA256}"
    echo "product_webview_held_sha256=${STOCK_PRODUCT_WEBVIEW_SHA256}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "system_b_free_blocks_after_deodex=${system_free_blocks}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "product_b_ext4_size=${PRODUCT_B_EXT4_SIZE}"
    echo "fec_status=system_b_generated_roots_2_product_b_retained_from_v035"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$PRODUCT_B_IMG"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V0351_BROWSERCHROME_DEODEX"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Product image: ${PRODUCT_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
