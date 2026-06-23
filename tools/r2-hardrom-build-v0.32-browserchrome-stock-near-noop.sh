#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

VARIANT="v0.32-browserchrome-stock-near-noop"
SOURCE_VARIANT="v0.29-sidebar-topbar-hide"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img}"
SOURCE_SHA256="${SOURCE_SHA256:-a8207ee148946057fc2d9c00780b2939c8307f7b0b88ae2b4bc304cfb39892d9}"
STOCK_BROWSER_APK="${STOCK_BROWSER_APK:-${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/app/BrowserChrome/BrowserChrome.apk}"
STOCK_BROWSER_SHA256="${STOCK_BROWSER_SHA256:-0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
SYSTEM_IMG="${SYSTEM_IMG:-${OUT_DIR}/system-otatrust-${VARIANT}.img}"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-${VARIANT}-exact-current.sparse.img}"
MANIFEST="${MANIFEST:-${OUT_DIR}/super-otatrust-${VARIANT}-exact-current.SHA256SUMS.txt}"

SYSTEM_B_SIZE=3049058304
SYSTEM_B_START_SECTOR=10487744
SYSTEM_B_SIZE_SECTORS=5955192
BROWSER_DIR="/system/app/BrowserChrome"
BROWSER_APK="/system/app/BrowserChrome/BrowserChrome.apk"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a34dae0}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-19 14:00:00 +0800; forces PackageCacher to reparse stock BrowserChrome package directory without changing APK bytes}"
SPARSE_VARIANT="otatrust-${VARIANT}-exact-current"
PURPOSE="Stock BrowserChrome near-no-op gate on top of live-verified v0.29: keep BrowserChrome.apk byte-identical and bump only the BrowserChrome package directory mtime for PackageCacher/default-browser no-op validation"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.32-browserchrome-stock-near-noop.sh

Build the v0.32 BrowserChrome stock near-no-op ROM candidate on top of the
live-verified v0.29 sparse image. It patches only system_b by changing the
mtime/ctime/atime/crtime of:

  /system/app/BrowserChrome

The stock BrowserChrome APK remains byte-identical:

  /system/app/BrowserChrome/BrowserChrome.apk

This script never flashes, reboots, erases misc, writes settings, changes
packages, clears package_cache, or mutates /data. Flashing still requires
explicit user confirmation after offline verification and live-state capture.

Environment:
  PACKAGE_DIR_MTIME_HEX=0x...  override BrowserChrome package directory timestamp
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

bump_package_dir_time() {
  local image="$1"
  local dir="$2"
  local tag="$3"
  local cmd_file="${WORK_DIR}/bump-dir-time-${tag}.debugfs"

  debugfs_path_exists "$image" "$dir" || die "missing package directory for mtime bump: ${dir}"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE}"
}

verify_package_dir_mtime() {
  local image="$1"
  local dir="$2"
  local expected="$3"
  local output
  output="$("$DEBUGFS" -R "stat ${dir}" "$image" 2>&1)"
  grep -q "Type: directory" <<<"$output" || die "expected directory: ${dir}"
  grep -q "mtime: ${expected}:" <<<"$output" \
    || die "package directory mtime mismatch for ${dir}; expected ${expected}"
}

fsck_image() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
  "$E2FSCK" -fn "$image" >/dev/null
}

verify_browser_apk_bytes() {
  local image="$1"
  local tag="$2"
  local dumped="${WORK_DIR}/${tag}-BrowserChrome.apk"
  local dumped_hash

  debugfs_dump "$image" "$BROWSER_APK" "$dumped"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$dumped_hash" = "$STOCK_BROWSER_SHA256" ] \
    || die "BrowserChrome APK hash mismatch: ${dumped_hash} != ${STOCK_BROWSER_SHA256}"
  unzip -t "$dumped" >/dev/null || die "dumped BrowserChrome APK zip test failed"
  echo "$dumped"
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

need_file "$SOURCE_SPARSE"
need_file "$STOCK_BROWSER_APK"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"
require_hash "$STOCK_BROWSER_APK" "$STOCK_BROWSER_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv

echo "Extracting system_b from ${SOURCE_VARIANT} sparse super..."
"$SPARSE_TOOL" --source-sparse "$SOURCE_SPARSE" \
  --extract-image "system_b=${SYSTEM_IMG}" >/dev/null
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

source_system_hash="$(sha256_one "$SYSTEM_IMG")"
source_browser_dump="$(verify_browser_apk_bytes "$SYSTEM_IMG" "source")"

echo "Bumping stock BrowserChrome package directory mtime for PackageCacher no-op gate..."
: > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
bump_package_dir_time "$SYSTEM_IMG" "$BROWSER_DIR" "system-browserchrome-dir" \
  >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
verify_package_dir_mtime "$SYSTEM_IMG" "$BROWSER_DIR" "$PACKAGE_DIR_MTIME_HEX"

echo "Checking modified system_b image..."
fsck_image "$SYSTEM_IMG"
verify_package_dir_mtime "$SYSTEM_IMG" "$BROWSER_DIR" "$PACKAGE_DIR_MTIME_HEX"
postfsck_browser_dump="$(verify_browser_apk_bytes "$SYSTEM_IMG" "postfsck")"

echo "Patching system_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$SOURCE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "system_b=${SYSTEM_IMG}" \
  --variant "$SPARSE_VARIANT"

system_hash="$(sha256_one "$SYSTEM_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"

{
  echo "variant=${SPARSE_VARIANT}"
  echo "display_variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse_super=${SOURCE_SPARSE}"
  echo "source_sparse_super_sha256=${SOURCE_SHA256}"
  echo "patched_partitions=system_b"
  echo "retained_partitions_from_source=product_b,system_ext_b,vendor_b,odm_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "system_b_start_sector=${SYSTEM_B_START_SECTOR}"
  echo "system_b_size_sectors=${SYSTEM_B_SIZE_SECTORS}"
  echo "source_system_b_sha256=${source_system_hash}"
  echo "system_b_sha256=${system_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "stock_browser_apk=${STOCK_BROWSER_APK}"
  echo "stock_browser_sha256=${STOCK_BROWSER_SHA256}"
  echo "source_browser_dump=${source_browser_dump}"
  echo "postfsck_browser_dump=${postfsck_browser_dump}"
  echo "browser_dir=${BROWSER_DIR}"
  echo "browser_apk=${BROWSER_APK}"
  echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
  echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# package_dir_mtime_bumps"
  cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$SOURCE_SPARSE" "$STOCK_BROWSER_APK" "$postfsck_browser_dump"
} > "$MANIFEST"

cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
