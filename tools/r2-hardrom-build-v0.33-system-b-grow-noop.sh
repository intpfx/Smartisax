#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
LPMake="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDump="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUnpack="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"

VARIANT="v0.33-system-b-grow-noop"
SOURCE_VARIANT="v0.31-webview-stock-near-noop"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.31-webview-stock-near-noop-exact-current.sparse.img}"
SOURCE_SHA256="${SOURCE_SHA256:-c187b050ced604d3ba52cee0dd36b4a8a17f9a0d1c8b4ae78b0fde0ea44384ae}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
EXTRACT_DIR="${WORK_DIR}/source-v031-slot1"
SOURCE_RAW="${WORK_DIR}/source-v031-super.raw.img"
OUT_RAW_FOR_LPDUMP="${WORK_DIR}/candidate-v033-super.raw-for-lpdump.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"

SUPER_SIZE=10737418240
METADATA_SIZE=65536
METADATA_SLOTS=3
GROUP_A_MAX=5364514816
GROUP_B_MAX=5364514816

SYSTEM_A_SIZE=3052314624
PRODUCT_A_SIZE=255815680
VENDOR_A_SIZE=941768704
ODM_A_SIZE=917504

SYSTEM_B_OLD_SIZE=3049058304
SYSTEM_B_GROWTH_BYTES="${SYSTEM_B_GROWTH_BYTES:-134217728}"
SYSTEM_B_NEW_SIZE=$((SYSTEM_B_OLD_SIZE + SYSTEM_B_GROWTH_BYTES))
SYSTEM_B_OLD_SECTORS=5955192
SYSTEM_B_GROWTH_SECTORS=$((SYSTEM_B_GROWTH_BYTES / 512))
SYSTEM_B_NEW_SECTORS=$((SYSTEM_B_OLD_SECTORS + SYSTEM_B_GROWTH_SECTORS))
SYSTEM_B_AVB_ORIGINAL_IMAGE_SIZE=3000860672
SYSTEM_B_AVB_VBMETA_OFFSET=3048407040
SYSTEM_B_AVB_VBMETA_SIZE=896

SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_SIZE=171110400
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768

PURPOSE="No-content system_b dynamic partition growth gate on top of live-verified v0.31. It preserves all extracted partition contents and ext4 filesystem bytes, grows only the system_b logical partition image by 128 MiB, moves the AVB footer with avbtool resize_image, rebuilds full super metadata with lpmake, and does not touch any APK, package directory, device, or /data state."

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.33-system-b-grow-noop.sh

Build the v0.33 system_b growth no-op candidate on top of live-verified v0.31.
The candidate intentionally changes dynamic partition metadata and AVB footer
placement, so it is not an exact-current slice patch. It preserves A-slot and
all existing B-slot filesystem contents, while growing system_b by 128 MiB.

This is a partition/footer gate, not the final filesystem-capacity gate:
/system files and the ext4 block count remain byte-identical to v0.31. A later
gate can resize ext4 and rebuild hashtree/FEC once the dynamic-partition growth
path has booted on real hardware.

This script does not flash, reboot, erase misc, write settings, clear package
cache, or mutate /data. Live testing requires explicit user confirmation after
offline verification and preflight.
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

fsck_rw() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
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

dump_lpdump() {
  rm -f "$OUT_RAW_FOR_LPDUMP"
  "$SIMG2IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP"
  check_size "candidate raw super for lpdump" "$OUT_RAW_FOR_LPDUMP" "$SUPER_SIZE"
  for slot in 0 1; do
    "$LPDump" -s "$slot" "$OUT_RAW_FOR_LPDUMP" > "${OUT_SPARSE}.lpdump-slot${slot}.txt"
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
need_executable "$LPMake"
need_executable "$LPDump"
need_executable "$LPUnpack"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_file "$AVBTOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"

[ $((SYSTEM_B_GROWTH_BYTES % 4096)) -eq 0 ] || die "SYSTEM_B_GROWTH_BYTES must be 4096-byte aligned"
[ "$SYSTEM_B_NEW_SIZE" -le "$GROUP_B_MAX" ] || die "new system_b size exceeds group max"

mkdir -p "$WORK_DIR" "$EXTRACT_DIR" "$OUT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$OUT_RAW_FOR_LPDUMP" "${OUT_SPARSE}.lpdump"* "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Converting ${SOURCE_VARIANT} sparse super to raw for lpunpack..."
rm -f "$SOURCE_RAW"
"$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
check_size "source raw super" "$SOURCE_RAW" "$SUPER_SIZE"

echo "Extracting slot-1 logical partitions from source super..."
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
"$LPUnpack" --slot=1 "$SOURCE_RAW" "$EXTRACT_DIR" >/dev/null

check_size system_a "${EXTRACT_DIR}/system_a.img" "$SYSTEM_A_SIZE"
check_size product_a "${EXTRACT_DIR}/product_a.img" "$PRODUCT_A_SIZE"
check_size vendor_a "${EXTRACT_DIR}/vendor_a.img" "$VENDOR_A_SIZE"
check_size odm_a "${EXTRACT_DIR}/odm_a.img" "$ODM_A_SIZE"
check_size system_b_source "${EXTRACT_DIR}/system_b.img" "$SYSTEM_B_OLD_SIZE"
check_size system_ext_b "${EXTRACT_DIR}/system_ext_b.img" "$SYSTEM_EXT_B_SIZE"
check_size product_b "${EXTRACT_DIR}/product_b.img" "$PRODUCT_B_SIZE"
check_size vendor_b "${EXTRACT_DIR}/vendor_b.img" "$VENDOR_B_SIZE"
check_size odm_b "${EXTRACT_DIR}/odm_b.img" "$ODM_B_SIZE"

source_system_b_hash="$(sha256_one "${EXTRACT_DIR}/system_b.img")"
source_system_b_blocks="$(debugfs_stat_value "${EXTRACT_DIR}/system_b.img" "Block count")"
source_system_b_free_blocks="$(debugfs_stat_value "${EXTRACT_DIR}/system_b.img" "Free blocks")"

echo "Growing system_b partition image by ${SYSTEM_B_GROWTH_BYTES} bytes while preserving ext4 bytes..."
copy_clone_or_plain "${EXTRACT_DIR}/system_b.img" "$SYSTEM_B_IMG"
python3 "$AVBTOOL" resize_image --image "$SYSTEM_B_IMG" --partition_size "$SYSTEM_B_NEW_SIZE"
fsck_ro "$SYSTEM_B_IMG"
check_size system_b_grown "$SYSTEM_B_IMG" "$SYSTEM_B_NEW_SIZE"

grown_system_b_hash="$(sha256_one "$SYSTEM_B_IMG")"
grown_system_b_blocks="$(debugfs_stat_value "$SYSTEM_B_IMG" "Block count")"
grown_system_b_free_blocks="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
[ "$grown_system_b_blocks" = "$source_system_b_blocks" ] \
  || die "grown system_b block count changed unexpectedly: actual=${grown_system_b_blocks} expected=${source_system_b_blocks}"
python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-grown-avb-info.txt"
grep -q "Image size:               ${SYSTEM_B_NEW_SIZE} bytes" "${WORK_DIR}/system-b-grown-avb-info.txt" \
  || die "grown system_b AVB image size mismatch"
grep -q "Original image size:      ${SYSTEM_B_AVB_ORIGINAL_IMAGE_SIZE} bytes" "${WORK_DIR}/system-b-grown-avb-info.txt" \
  || die "grown system_b AVB original image size changed unexpectedly"
grep -q "VBMeta offset:            ${SYSTEM_B_AVB_VBMETA_OFFSET}" "${WORK_DIR}/system-b-grown-avb-info.txt" \
  || die "grown system_b AVB vbmeta offset changed unexpectedly"
grep -q "VBMeta size:              ${SYSTEM_B_AVB_VBMETA_SIZE} bytes" "${WORK_DIR}/system-b-grown-avb-info.txt" \
  || die "grown system_b AVB vbmeta size changed unexpectedly"

echo "Rebuilding full sparse super with grown system_b metadata..."
rm -f "$OUT_SPARSE"
"$LPMake" \
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
  --partition="system_b:readonly:${SYSTEM_B_NEW_SIZE}:qti_dynamic_partitions_b" \
  --partition="system_ext_b:readonly:${SYSTEM_EXT_B_SIZE}:qti_dynamic_partitions_b" \
  --partition="product_b:readonly:${PRODUCT_B_SIZE}:qti_dynamic_partitions_b" \
  --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b" \
  --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b" \
  --image="system_a=${EXTRACT_DIR}/system_a.img" \
  --image="product_a=${EXTRACT_DIR}/product_a.img" \
  --image="vendor_a=${EXTRACT_DIR}/vendor_a.img" \
  --image="odm_a=${EXTRACT_DIR}/odm_a.img" \
  --image="system_b=${SYSTEM_B_IMG}" \
  --image="system_ext_b=${EXTRACT_DIR}/system_ext_b.img" \
  --image="product_b=${EXTRACT_DIR}/product_b.img" \
  --image="vendor_b=${EXTRACT_DIR}/vendor_b.img" \
  --image="odm_b=${EXTRACT_DIR}/odm_b.img" \
  --block-size=4096 \
  --sparse \
  --output="$OUT_SPARSE"

dump_lpdump
super_hash="$(sha256_one "$OUT_SPARSE")"

{
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse_super=${SOURCE_SPARSE}"
  echo "source_sparse_super_sha256=${SOURCE_SHA256}"
  echo "source_raw_super=${SOURCE_RAW}"
  echo "extracted_partition_dir=${EXTRACT_DIR}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=${super_hash}"
  echo "system_b_image=${SYSTEM_B_IMG}"
  echo "system_b_source_image=${EXTRACT_DIR}/system_b.img"
  echo "system_b_source_sha256=${source_system_b_hash}"
  echo "system_b_grown_sha256=${grown_system_b_hash}"
  echo "system_b_old_size=${SYSTEM_B_OLD_SIZE}"
  echo "system_b_new_size=${SYSTEM_B_NEW_SIZE}"
  echo "system_b_growth_bytes=${SYSTEM_B_GROWTH_BYTES}"
  echo "system_b_old_sectors=${SYSTEM_B_OLD_SECTORS}"
  echo "system_b_new_sectors=${SYSTEM_B_NEW_SECTORS}"
  echo "system_b_growth_sectors=${SYSTEM_B_GROWTH_SECTORS}"
  echo "system_b_avb_original_image_size=${SYSTEM_B_AVB_ORIGINAL_IMAGE_SIZE}"
  echo "system_b_avb_vbmeta_offset=${SYSTEM_B_AVB_VBMETA_OFFSET}"
  echo "system_b_avb_vbmeta_size=${SYSTEM_B_AVB_VBMETA_SIZE}"
  echo "system_b_source_blocks_4k=${source_system_b_blocks}"
  echo "system_b_grown_blocks_4k=${grown_system_b_blocks}"
  echo "system_b_source_free_blocks=${source_system_b_free_blocks}"
  echo "system_b_grown_free_blocks=${grown_system_b_free_blocks}"
  echo "system_b_grown_avb_info=${WORK_DIR}/system-b-grown-avb-info.txt"
  echo "super_size=${SUPER_SIZE}"
  echo "metadata_size=${METADATA_SIZE}"
  echo "metadata_slots=${METADATA_SLOTS}"
  echo "group_a_max=${GROUP_A_MAX}"
  echo "group_b_max=${GROUP_B_MAX}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 \
    "$OUT_SPARSE" \
    "$SOURCE_SPARSE" \
    "$SOURCE_RAW" \
    "$SYSTEM_B_IMG" \
    "${EXTRACT_DIR}/system_a.img" \
    "${EXTRACT_DIR}/product_a.img" \
    "${EXTRACT_DIR}/vendor_a.img" \
    "${EXTRACT_DIR}/odm_a.img" \
    "${EXTRACT_DIR}/system_b.img" \
    "${EXTRACT_DIR}/system_ext_b.img" \
    "${EXTRACT_DIR}/product_b.img" \
    "${EXTRACT_DIR}/vendor_b.img" \
    "${EXTRACT_DIR}/odm_b.img"
} > "$MANIFEST"

cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Built: ${OUT_SPARSE}"
echo "Grown system_b: ${SYSTEM_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
