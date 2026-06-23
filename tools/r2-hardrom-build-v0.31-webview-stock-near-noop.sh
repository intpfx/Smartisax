#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

VARIANT="v0.31-webview-stock-near-noop"
SOURCE_VARIANT="v0.29-sidebar-topbar-hide"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img}"
SOURCE_SHA256="${SOURCE_SHA256:-a8207ee148946057fc2d9c00780b2939c8307f7b0b88ae2b4bc304cfb39892d9}"
STOCK_WEBVIEW_APK="${STOCK_WEBVIEW_APK:-${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/product/app/webview/webview.apk}"
STOCK_WEBVIEW_SHA256="${STOCK_WEBVIEW_SHA256:-11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
PRODUCT_IMG="${PRODUCT_IMG:-${OUT_DIR}/product-otatrust-${VARIANT}.img}"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-${VARIANT}-exact-current.sparse.img}"
MANIFEST="${MANIFEST:-${OUT_DIR}/super-otatrust-${VARIANT}-exact-current.SHA256SUMS.txt}"

PRODUCT_B_SIZE=171110400
PRODUCT_B_START_SECTOR=17021888
PRODUCT_B_SIZE_SECTORS=334200
WEBVIEW_DIR="/app/webview"
WEBVIEW_APK="/app/webview/webview.apk"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a344030}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-19 03:00:00 +0800; forces PackageCacher to reparse stock WebView product package directory without changing the APK bytes}"
SPARSE_VARIANT="otatrust-${VARIANT}-exact-current"
PURPOSE="Stock WebView provider near-no-op gate on top of live-verified v0.29: keep product WebView APK byte-identical and bump only /product app directory mtime for PackageCacher/WebViewUpdateService no-op validation"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.31-webview-stock-near-noop.sh

Build the v0.31 WebView stock near-no-op ROM candidate on top of the
live-verified v0.29 sparse image. It patches only product_b by changing the
mtime/ctime/atime/crtime of:

  /app/webview

The stock WebView APK remains byte-identical:

  /app/webview/webview.apk

This script never flashes, reboots, erases misc, writes settings, changes
packages, clears package_cache, or mutates /data. Flashing still requires
explicit user confirmation after offline verification and live-state capture.

Environment:
  PACKAGE_DIR_MTIME_HEX=0x...  override WebView package directory timestamp
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

verify_product_dir_mtime() {
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

verify_webview_apk_bytes() {
  local image="$1"
  local tag="$2"
  local dumped="${WORK_DIR}/${tag}-webview.apk"
  local dumped_hash

  debugfs_dump "$image" "$WEBVIEW_APK" "$dumped"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$dumped_hash" = "$STOCK_WEBVIEW_SHA256" ] \
    || die "WebView APK hash mismatch: ${dumped_hash} != ${STOCK_WEBVIEW_SHA256}"
  unzip -t "$dumped" >/dev/null || die "dumped WebView APK zip test failed"
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
need_file "$STOCK_WEBVIEW_APK"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"
require_hash "$STOCK_WEBVIEW_APK" "$STOCK_WEBVIEW_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$PRODUCT_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv

echo "Extracting product_b from ${SOURCE_VARIANT} sparse super..."
"$SPARSE_TOOL" --source-sparse "$SOURCE_SPARSE" \
  --extract-image "product_b=${PRODUCT_IMG}" >/dev/null
[ "$(size_bytes "$PRODUCT_IMG")" -eq "$PRODUCT_B_SIZE" ] || die "unexpected product_b size"

source_product_hash="$(sha256_one "$PRODUCT_IMG")"
source_webview_dump="$(verify_webview_apk_bytes "$PRODUCT_IMG" "source")"

echo "Bumping stock WebView package directory mtime for PackageCacher/WebView no-op gate..."
: > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
bump_package_dir_time "$PRODUCT_IMG" "$WEBVIEW_DIR" "product-webview-dir" \
  >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
verify_product_dir_mtime "$PRODUCT_IMG" "$WEBVIEW_DIR" "$PACKAGE_DIR_MTIME_HEX"

echo "Checking modified product_b image..."
fsck_image "$PRODUCT_IMG"
verify_product_dir_mtime "$PRODUCT_IMG" "$WEBVIEW_DIR" "$PACKAGE_DIR_MTIME_HEX"
postfsck_webview_dump="$(verify_webview_apk_bytes "$PRODUCT_IMG" "postfsck")"

echo "Patching product_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$SOURCE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "product_b=${PRODUCT_IMG}" \
  --variant "$SPARSE_VARIANT"

product_hash="$(sha256_one "$PRODUCT_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"

{
  echo "variant=${SPARSE_VARIANT}"
  echo "display_variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse_super=${SOURCE_SPARSE}"
  echo "source_sparse_super_sha256=${SOURCE_SHA256}"
  echo "patched_partitions=product_b"
  echo "retained_partitions_from_source=system_b,system_ext_b,vendor_b,odm_b"
  echo "product_image=${PRODUCT_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "product_b_start_sector=${PRODUCT_B_START_SECTOR}"
  echo "product_b_size_sectors=${PRODUCT_B_SIZE_SECTORS}"
  echo "source_product_b_sha256=${source_product_hash}"
  echo "product_b_sha256=${product_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "stock_webview_apk=${STOCK_WEBVIEW_APK}"
  echo "stock_webview_sha256=${STOCK_WEBVIEW_SHA256}"
  echo "source_webview_dump=${source_webview_dump}"
  echo "postfsck_webview_dump=${postfsck_webview_dump}"
  echo "webview_dir=${WEBVIEW_DIR}"
  echo "webview_apk=${WEBVIEW_APK}"
  echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
  echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# package_dir_mtime_bumps"
  cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$PRODUCT_IMG" "$SOURCE_SPARSE" "$STOCK_WEBVIEW_APK" "$postfsck_webview_dump"
} > "$MANIFEST"

cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Built: ${OUT_SPARSE}"
echo "Product image: ${PRODUCT_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
