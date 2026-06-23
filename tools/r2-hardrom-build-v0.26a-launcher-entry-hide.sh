#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
APK_BUILDER="${APK_BUILDER:-${ROOT_DIR}/tools/r2-build-launcher-entry-hide-apks.sh}"

SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img}"
SOURCE_SHA256="2f1a4d8b8579551bf04246d00099f15c5c5a42146336cd6a00d129bbcffb8fa0"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.26a-launcher-entry-hide}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
SYSTEM_IMG="${SYSTEM_IMG:-${OUT_DIR}/system-otatrust-v0.26a-launcher-entry-hide.img}"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-v0.26a-launcher-entry-hide-exact-current.sparse.img}"
MANIFEST="${MANIFEST:-${OUT_DIR}/super-otatrust-v0.26a-launcher-entry-hide-exact-current.SHA256SUMS.txt}"

VIDEO_APK="${VIDEO_APK:-${APK_OUT_DIR}/com.smartisanos.videoplayerproject-launcher-hidden.apk}"
SCREENREC_APK="${SCREENREC_APK:-${APK_OUT_DIR}/com.smartisanos.screenrecorder-launcher-hidden.apk}"
QUICKSEARCH_APK="${QUICKSEARCH_APK:-${APK_OUT_DIR}/com.smartisanos.quicksearch-launcher-hidden.apk}"
APK_MANIFEST="${APK_OUT_DIR}/launcher-entry-hide-apk-manifest.tsv"

SYSTEM_SELABEL="u:object_r:system_file:s0"
SYSTEM_B_SIZE=3049058304
SYSTEM_B_START_SECTOR=10487744
SYSTEM_B_SIZE_SECTORS=5955192

REBUILD_APKS="${REBUILD_APKS:-1}"
IMAGE_TAG="${IMAGE_TAG:-v026a}"
SPARSE_VARIANT="${SPARSE_VARIANT:-otatrust-v0.26a-launcher-entry-hide-exact-current}"
PURPOSE="${PURPOSE:-Manifest-only launcher entry hide for VideoPlayer, ScreenRecorderSmartisan, and QuickSearchBoxSmartisan on top of live-verified v0.11.1}"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.26a-launcher-entry-hide.sh

Build the v0.26a launcher-entry-hide ROM candidate on top of the live-verified
v0.11.1 sparse image. This removes only desktop LAUNCHER categories from:

  - VideoPlayer / com.smartisanos.videoplayerproject
  - ScreenRecorderSmartisan / com.smartisanos.screenrecorder
  - QuickSearchBoxSmartisan / com.smartisanos.quicksearch

It patches only system_b and does not flash, reboot, erase misc, or change
/data. Flashing the generated sparse image still requires explicit user
confirmation.

Environment:
  REBUILD_APKS=0        reuse existing launcher-hidden APK outputs
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

replace_file_in_image() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped.apk"
  local dir
  local base
  local temp_path
  local held_path
  local src_hash
  local dumped_hash

  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  temp_path="${dir}/.${base}.smartisax-v026a-tmp"
  held_path="${dir}/.${base}.smartisax-${IMAGE_TAG}-stock-held"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination directory: ${dst}"
  debugfs_path_exists "$image" "$dst" || die "missing stock destination file: ${dst}"
  if debugfs_path_exists "$image" "$temp_path" || debugfs_path_exists "$image" "$held_path"; then
    die "temporary or held path already exists for ${dst}; refusing ambiguous replacement"
  fi

  {
    echo "ln ${dst} ${held_path}"
    echo "write ${src} ${temp_path}"
    echo "set_inode_field ${temp_path} mode 0100644"
    echo "set_inode_field ${temp_path} uid 0"
    echo "set_inode_field ${temp_path} gid 0"
    echo "ea_set ${temp_path} security.selinux ${SYSTEM_SELABEL}"
    echo "unlink ${dst}"
    echo "ln ${temp_path} ${dst}"
    echo "unlink ${temp_path}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$dst" || die "missing replaced file: ${dst}"
  debugfs_path_exists "$image" "$held_path" || die "missing held stock file: ${held_path}"
  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1

  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "dumped APK zip test failed before fsck for ${dst}"

  echo "${dst}|${src}|${src_hash}|${dumped}|${held_path}"
}

bump_package_dir_time() {
  local image="$1"
  local dir="$2"
  local tag="$3"
  local cmd_file="${WORK_DIR}/bump-dir-time-${tag}.debugfs"

  [ -n "$PACKAGE_DIR_MTIME_HEX" ] || return 0
  debugfs_path_exists "$image" "$dir" || die "missing package directory for mtime bump: ${dir}"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE:-package-cache invalidation}"
}

fsck_image() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
  "$E2FSCK" -fn "$image" >/dev/null
}

dump_and_compare() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local dumped="${WORK_DIR}/${tag}-postfsck-dumped.apk"
  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1
  need_file "$dumped"
  [ "$(sha256_one "$src")" = "$(sha256_one "$dumped")" ] \
    || die "post-fsck dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null
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
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
need_executable "$APK_BUILDER"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR"
rm -f "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv

if [ "$REBUILD_APKS" = "1" ]; then
  echo "Building v0.26a launcher-entry-hide APK candidates..."
  "$APK_BUILDER" --variant v0.26a >/dev/null
fi

need_file "$VIDEO_APK"
need_file "$SCREENREC_APK"
need_file "$QUICKSEARCH_APK"
need_file "$APK_MANIFEST"

echo "Extracting system_b from v0.11.1 sparse super..."
"$SPARSE_TOOL" --source-sparse "$SOURCE_SPARSE" --extract-image "system_b=${SYSTEM_IMG}" >/dev/null
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

echo "Replacing v0.26a launcher-entry-hide APKs in system_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$VIDEO_APK" \
  "/system/priv-app/VideoPlayer/VideoPlayer.apk" \
  "system-videoplayer-launcher-hidden" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$SCREENREC_APK" \
  "/system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk" \
  "system-screenrecorder-launcher-hidden" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$QUICKSEARCH_APK" \
  "/system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk" \
  "system-quicksearch-launcher-hidden" >> "${WORK_DIR}/replacements.tsv"

if [ -n "$PACKAGE_DIR_MTIME_HEX" ]; then
  echo "Bumping package directory mtimes for PackageCacher invalidation..."
  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_IMG" "/system/priv-app/VideoPlayer" \
    "system-videoplayer-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_IMG" "/system/priv-app/ScreenRecorderSmartisan" \
    "system-screenrecorder-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_IMG" "/system/app/QuickSearchBoxSmartisan" \
    "system-quicksearch-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
fi

echo "Checking modified system_b..."
fsck_image "$SYSTEM_IMG"

echo "Verifying replaced APKs after fsck..."
dump_and_compare "$SYSTEM_IMG" "$VIDEO_APK" \
  "/system/priv-app/VideoPlayer/VideoPlayer.apk" "system-videoplayer-launcher-hidden"
dump_and_compare "$SYSTEM_IMG" "$SCREENREC_APK" \
  "/system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk" "system-screenrecorder-launcher-hidden"
dump_and_compare "$SYSTEM_IMG" "$QUICKSEARCH_APK" \
  "/system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk" "system-quicksearch-launcher-hidden"

echo "Patching system_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$SOURCE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "system_b=${SYSTEM_IMG}" \
  --variant "$SPARSE_VARIANT"

system_hash="$(sha256_one "$SYSTEM_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"
video_hash="$(sha256_one "$VIDEO_APK")"
screenrec_hash="$(sha256_one "$SCREENREC_APK")"
quicksearch_hash="$(sha256_one "$QUICKSEARCH_APK")"

{
  echo "variant=${SPARSE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${SOURCE_SPARSE}"
  echo "source_sparse_super_sha256=${SOURCE_SHA256}"
  echo "patched_partitions=system_b"
  echo "retained_partitions_from_source=system_ext_b,product_b,vendor_b,odm_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "apk_manifest=${APK_MANIFEST}"
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "system_b_start_sector=${SYSTEM_B_START_SECTOR}"
  echo "system_b_size_sectors=${SYSTEM_B_SIZE_SECTORS}"
  echo "system_b_sha256=${system_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "video_launcher_hidden_apk=${VIDEO_APK}"
  echo "video_launcher_hidden_sha256=${video_hash}"
  echo "screenrecorder_launcher_hidden_apk=${SCREENREC_APK}"
  echo "screenrecorder_launcher_hidden_sha256=${screenrec_hash}"
  echo "quicksearch_launcher_hidden_apk=${QUICKSEARCH_APK}"
  echo "quicksearch_launcher_hidden_sha256=${quicksearch_hash}"
  echo "rebuilt_apks=${REBUILD_APKS}"
  echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX:-not-set}"
  echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE:-not-set}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  if [ -f "${WORK_DIR}/package-dir-mtime-bumps.tsv" ]; then
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  fi
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$SOURCE_SPARSE" \
    "$VIDEO_APK" "$SCREENREC_APK" "$QUICKSEARCH_APK"
} > "$MANIFEST"

cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
