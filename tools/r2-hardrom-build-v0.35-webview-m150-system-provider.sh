#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"

VARIANT="v0.35-webview-m150-system-provider"
SOURCE_VARIANT="v0.34-system-b-ext4-grow-fec"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.34-system-b-ext4-grow-fec.sparse.img}"
SOURCE_SPARSE_SHA256="bd795e1a91e4e3d6108bb989cd03cc1511fa2487cde1bd28bb0e857148b99232"
SOURCE_EXTRACT_DIR="${SOURCE_EXTRACT_DIR:-${ROOT_DIR}/hard-rom/work/v0.34-system-b-ext4-grow-fec/candidate-v034-fec-slot1}"
SOURCE_SYSTEM_B_SHA256="62fe11bc7424e35370eb37d85dc6cf412b50367e2d2e1efce6d1cef5db9a9a44"
SOURCE_PRODUCT_B_SHA256="cc1302eb5d9c8f4b6856f2b9e5c67c19bdf4ce454fa70a3126d325a86fac9652"

DONOR_APK="${DONOR_APK:-${ROOT_DIR}/apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView-stock-carrier.apk}"
DONOR_APK_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_PRODUCT_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
FALLBACK_EXTRACT_DIR="${WORK_DIR}/source-v034-slot1"
SOURCE_RAW="${WORK_DIR}/source-v034-super.raw.img"
OUT_RAW_FOR_LPDUMP="${WORK_DIR}/candidate-v035-super.raw-for-lpdump.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
PRODUCT_B_IMG="${OUT_DIR}/product-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
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
PRODUCT_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"

SYSTEM_WEBVIEW_DIR="/system/app/webview"
SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
PRODUCT_WEBVIEW_DIR="/app/webview"
PRODUCT_WEBVIEW_APK="/app/webview/webview.apk"
PRODUCT_WEBVIEW_HELD="/app/webview/.webview.apk.smartisax-v035-stock-held"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a363a70}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-20 15:00:00 +0800; invalidates package_cache for old product WebView absence and new system WebView provider}"
SYSTEM_SELABEL="u:object_r:system_file:s0"

PURPOSE="First donor-backed WebView modernization image design on top of live-verified v0.34. It installs the source-built Chromium M150 stock-carrier com.android.webview APK as /system/app/webview/webview.apk, hides the old product WebView APK from PackageManager scanning, bumps both package directories, rebuilds system_b and product_b FEC hashtree footers, and keeps BrowserChrome/framework/provider whitelist unchanged."

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.35-webview-m150-system-provider.sh

Build the v0.35 WebView modernization offline candidate on top of the
live-verified v0.34 FEC ext4-capacity baseline.

Layout:
  - add modern com.android.webview M150 stock-carrier APK to /system/app/webview
  - hide the old /product/app/webview/webview.apk behind a non-.apk held path
  - leave BrowserChrome and framework config_webview_packages.xml unchanged
  - rebuild system_b and product_b AVB hashtree footers with FEC roots=2

This script does not flash, reboot, erase misc, write settings, clear
package_cache, or mutate /data. Live testing requires explicit user
confirmation after offline verification and preflight wiring.
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

check_size() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
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

set_package_dir_time() {
  local image="$1"
  local dir="$2"
  local tag="$3"
  local cmd_file="${WORK_DIR}/mtime-${tag}.debugfs"
  debugfs_path_exists "$image" "$dir" || die "missing package directory: ${dir}"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE}"
}

prepare_source_images() {
  local extract_dir="$SOURCE_EXTRACT_DIR"
  local part
  if [ ! -f "${extract_dir}/system_b.img" ] || [ "$(sha256_one "${extract_dir}/system_b.img" 2>/dev/null || true)" != "$SOURCE_SYSTEM_B_SHA256" ]; then
    extract_dir="$FALLBACK_EXTRACT_DIR"
    echo "Source v0.34 extracted images are missing or stale; extracting from sparse super..."
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    rm -f "$SOURCE_RAW"
    "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
    check_size "source raw super" "$SOURCE_RAW" "$SUPER_SIZE"
    "$LPUNPACK" --slot=1 "$SOURCE_RAW" "$extract_dir" >/dev/null
    rm -f "$SOURCE_RAW"
  else
    echo "Using existing v0.34 extracted slot-1 images: ${extract_dir}"
  fi
  SOURCE_EXTRACT_DIR="$extract_dir"
  for part in system_a product_a vendor_a odm_a system_b system_ext_b product_b vendor_b odm_b; do
    need_file "${SOURCE_EXTRACT_DIR}/${part}.img"
  done
  check_size system_a "${SOURCE_EXTRACT_DIR}/system_a.img" "$SYSTEM_A_SIZE"
  check_size product_a "${SOURCE_EXTRACT_DIR}/product_a.img" "$PRODUCT_A_SIZE"
  check_size vendor_a "${SOURCE_EXTRACT_DIR}/vendor_a.img" "$VENDOR_A_SIZE"
  check_size odm_a "${SOURCE_EXTRACT_DIR}/odm_a.img" "$ODM_A_SIZE"
  check_size source_system_b "${SOURCE_EXTRACT_DIR}/system_b.img" "$SYSTEM_B_PARTITION_SIZE"
  check_size system_ext_b "${SOURCE_EXTRACT_DIR}/system_ext_b.img" "$SYSTEM_EXT_B_SIZE"
  check_size source_product_b "${SOURCE_EXTRACT_DIR}/product_b.img" "$PRODUCT_B_PARTITION_SIZE"
  check_size vendor_b "${SOURCE_EXTRACT_DIR}/vendor_b.img" "$VENDOR_B_SIZE"
  check_size odm_b "${SOURCE_EXTRACT_DIR}/odm_b.img" "$ODM_B_SIZE"
  require_hash "${SOURCE_EXTRACT_DIR}/system_b.img" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "${SOURCE_EXTRACT_DIR}/product_b.img" "$SOURCE_PRODUCT_B_SHA256"
}

install_system_webview() {
  local image="$1"
  local cmd_file="${WORK_DIR}/install-system-webview.debugfs"
  debugfs_path_exists "$image" "/system/app" || die "missing /system/app"
  if debugfs_path_exists "$image" "$SYSTEM_WEBVIEW_DIR"; then
    die "system WebView directory already exists: ${SYSTEM_WEBVIEW_DIR}"
  fi
  {
    echo "mkdir ${SYSTEM_WEBVIEW_DIR}"
    echo "set_inode_field ${SYSTEM_WEBVIEW_DIR} mode 040755"
    echo "set_inode_field ${SYSTEM_WEBVIEW_DIR} uid 0"
    echo "set_inode_field ${SYSTEM_WEBVIEW_DIR} gid 0"
    echo "ea_set ${SYSTEM_WEBVIEW_DIR} security.selinux ${SYSTEM_SELABEL}"
    echo "write ${DONOR_APK} ${SYSTEM_WEBVIEW_APK}"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} mode 0100644"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} uid 0"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} gid 0"
    echo "ea_set ${SYSTEM_WEBVIEW_APK} security.selinux ${SYSTEM_SELABEL}"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${SYSTEM_WEBVIEW_APK} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  set_package_dir_time "$image" "$SYSTEM_WEBVIEW_DIR" "system-webview-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  debugfs_path_exists "$image" "$SYSTEM_WEBVIEW_APK" || die "missing installed system WebView APK"
}

hide_product_webview() {
  local image="$1"
  local cmd_file="${WORK_DIR}/hide-product-webview.debugfs"
  debugfs_path_exists "$image" "$PRODUCT_WEBVIEW_DIR" || die "missing product WebView directory"
  debugfs_path_exists "$image" "$PRODUCT_WEBVIEW_APK" || die "missing product WebView APK"
  if debugfs_path_exists "$image" "$PRODUCT_WEBVIEW_HELD"; then
    die "held product WebView path already exists: ${PRODUCT_WEBVIEW_HELD}"
  fi
  {
    echo "ln ${PRODUCT_WEBVIEW_APK} ${PRODUCT_WEBVIEW_HELD}"
    echo "unlink ${PRODUCT_WEBVIEW_APK}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  set_package_dir_time "$image" "$PRODUCT_WEBVIEW_DIR" "product-webview-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  ! debugfs_path_exists "$image" "$PRODUCT_WEBVIEW_APK" || die "product WebView APK is still public"
  debugfs_path_exists "$image" "$PRODUCT_WEBVIEW_HELD" || die "held product WebView path was not created"
}

verify_dumped_apk() {
  local image="$1"
  local src="$2"
  local expected="$3"
  local dst="$4"
  local actual
  debugfs_dump "$image" "$src" "$dst"
  actual="$(sha256_one "$dst")"
  [ "$actual" = "$expected" ] || die "dumped hash mismatch for ${src}: ${actual} != ${expected}"
  unzip -t "$dst" >/dev/null || die "dumped APK zip test failed for ${src}"
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
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

need_executable "$SIMG2IMG"
need_executable "$LPMAKE"
need_executable "$LPDUMP"
need_executable "$LPUNPACK"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_file "$AVBTOOL"
need_executable "$FEC"
need_file "$SOURCE_SPARSE"
need_file "$DONOR_APK"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
require_hash "$DONOR_APK" "$DONOR_APK_SHA256"

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
  echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
  prepare_source_images
  echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
  echo

  echo "## prepare system_b"
  copy_clone_or_plain "${SOURCE_EXTRACT_DIR}/system_b.img" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size "system_b pure ext4" "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  install_system_webview "$SYSTEM_B_IMG"
  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_APK_SHA256" "${WORK_DIR}/system-webview-pre-fsck.apk"
  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_APK_SHA256" "${WORK_DIR}/system-webview-post-fsck.apk"
  system_free_blocks="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_b_free_blocks_after_webview=${system_free_blocks}"
  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size "system_b FEC image" "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-v035-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-v035-avb-info.txt" || die "system_b lost FEC roots"
  echo

  echo "## prepare product_b"
  copy_clone_or_plain "${SOURCE_EXTRACT_DIR}/product_b.img" "$PRODUCT_B_IMG"
  verify_dumped_apk "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_APK" "$STOCK_PRODUCT_WEBVIEW_SHA256" "${WORK_DIR}/product-webview-stock-before-hide.apk"
  python3 "$AVBTOOL" erase_footer --image "$PRODUCT_B_IMG"
  check_size "product_b pure ext4" "$PRODUCT_B_IMG" "$PRODUCT_B_EXT4_SIZE"
  fsck_rw "$PRODUCT_B_IMG"
  hide_product_webview "$PRODUCT_B_IMG"
  verify_dumped_apk "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_HELD" "$STOCK_PRODUCT_WEBVIEW_SHA256" "${WORK_DIR}/product-webview-stock-held.apk"
  fsck_rw "$PRODUCT_B_IMG"
  fsck_ro "$PRODUCT_B_IMG"
  ! debugfs_path_exists "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_APK" || die "public product WebView APK returned after fsck"
  verify_dumped_apk "$PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_HELD" "$STOCK_PRODUCT_WEBVIEW_SHA256" "${WORK_DIR}/product-webview-stock-held-post-fsck.apk"
  rebuild_product_footer "$PRODUCT_B_IMG"
  check_size "product_b FEC image" "$PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$PRODUCT_B_IMG" > "${WORK_DIR}/product-b-v035-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/product-b-v035-avb-info.txt" || die "product_b lost FEC roots"
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
    echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
    echo "patched_partitions=system_b,product_b"
    echo "retained_partitions_from_source=system_a,product_a,vendor_a,odm_a,system_ext_b,vendor_b,odm_b"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "product_b_image=${PRODUCT_B_IMG}"
    echo "product_b_sha256=${product_hash}"
    echo "donor_apk=${DONOR_APK}"
    echo "donor_apk_sha256=${DONOR_APK_SHA256}"
    echo "stock_product_webview_sha256=${STOCK_PRODUCT_WEBVIEW_SHA256}"
    echo "system_webview_apk=${SYSTEM_WEBVIEW_APK}"
    echo "product_webview_public_apk=${PRODUCT_WEBVIEW_APK}"
    echo "product_webview_held_path=${PRODUCT_WEBVIEW_HELD}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "system_b_free_blocks_after_webview=${system_free_blocks}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "product_b_ext4_size=${PRODUCT_B_EXT4_SIZE}"
    echo "fec_status=system_b_and_product_b_generated_roots_2"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$PRODUCT_B_IMG" "$DONOR_APK"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V035_WEBVIEW_SYSTEM_PROVIDER"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Product image: ${PRODUCT_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
