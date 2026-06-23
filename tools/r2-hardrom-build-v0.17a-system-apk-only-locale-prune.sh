#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
APK_BATCH_VERIFIER="${APK_BATCH_VERIFIER:-${ROOT_DIR}/tools/r2-verify-apk-only-locale-prune-candidates.sh}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.17a-system-apk-only-locale-prune}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.17a-system-apk-only-locale-prune.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.SHA256SUMS.txt"

SYSTEM_SELABEL="u:object_r:system_file:s0"
SYSTEM_B_SIZE=3049058304
SYSTEM_B_START_SECTOR=10487744
SYSTEM_B_SIZE_SECTORS=5955192

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.17a-system-apk-only-locale-prune.sh

Build an offline v0.17a exact-current candidate from the stable v0.4 baseline.
It promotes the system_b APK-only English/Chinese resource-prune candidates:

  /system/app/BasicDreams/BasicDreams.apk
  /system/app/HTMLViewer/HTMLViewer.apk
  /system/app/LiveWallpapersPicker/LiveWallpapersPicker.apk
  /system/app/PrintSpooler/PrintSpooler.apk
  /system/app/SimAppDialog/SimAppDialog.apk

The script uses the shared_blocks-safe held-stock-inode replacement pattern and
then rewrites system_b into a sparse super. It never flashes, reboots, erases
misc, or changes /data. Flashing still requires explicit user confirmation.
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
  temp_path="${dir}/.${base}.smartisax-v017a-tmp"
  held_path="${dir}/.${base}.smartisax-v017a-stock-held"

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

fsck_image() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
  "$E2FSCK" -fn "$image" >/dev/null
}

verify_file_in_image_after_fsck() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local dumped="${WORK_DIR}/${tag}-postfsck-dumped.apk"
  local src_hash
  local dumped_hash

  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1
  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "post-fsck dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "post-fsck APK zip test failed for ${dst}"
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

need_file "$BASE_SPARSE"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
need_executable "$APK_BATCH_VERIFIER"

BASIC_DREAMS_APK="${APK_OUT_DIR}/com.android.dreams.basic-locale-prune-en-zh.apk"
HTML_VIEWER_APK="${APK_OUT_DIR}/com.android.htmlviewer-locale-prune-en-zh.apk"
LIVE_WALLPAPER_APK="${APK_OUT_DIR}/com.android.wallpaper.livepicker-locale-prune-en-zh.apk"
PRINT_SPOOLER_APK="${APK_OUT_DIR}/com.android.printspooler-locale-prune-en-zh.apk"
SIM_APP_DIALOG_APK="${APK_OUT_DIR}/com.android.simappdialog-locale-prune-en-zh.apk"

for apk in \
  "$BASIC_DREAMS_APK" \
  "$HTML_VIEWER_APK" \
  "$LIVE_WALLPAPER_APK" \
  "$PRINT_SPOOLER_APK" \
  "$SIM_APP_DIALOG_APK"; do
  need_file "$apk"
done

echo "Verifying APK-only candidate batch before ROM promotion..."
"$APK_BATCH_VERIFIER" >/dev/null

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/replace-*.debugfs "${WORK_DIR}/replacements.tsv"

echo "Extracting system_b from v0.4 sparse super..."
"$SPARSE_TOOL" --source-sparse "$BASE_SPARSE" --extract-image "system_b=${SYSTEM_IMG}" >/dev/null
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

echo "Replacing system APK-only candidates in system_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$BASIC_DREAMS_APK" \
  "/system/app/BasicDreams/BasicDreams.apk" \
  "system-basicdreams" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$HTML_VIEWER_APK" \
  "/system/app/HTMLViewer/HTMLViewer.apk" \
  "system-htmlviewer" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$LIVE_WALLPAPER_APK" \
  "/system/app/LiveWallpapersPicker/LiveWallpapersPicker.apk" \
  "system-livewallpaperpicker" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$PRINT_SPOOLER_APK" \
  "/system/app/PrintSpooler/PrintSpooler.apk" \
  "system-printspooler" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$SIM_APP_DIALOG_APK" \
  "/system/app/SimAppDialog/SimAppDialog.apk" \
  "system-simappdialog" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified ext4 image..."
fsck_image "$SYSTEM_IMG"

echo "Verifying replaced APKs after fsck..."
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$BASIC_DREAMS_APK" \
  "/system/app/BasicDreams/BasicDreams.apk" "system-basicdreams"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$HTML_VIEWER_APK" \
  "/system/app/HTMLViewer/HTMLViewer.apk" "system-htmlviewer"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$LIVE_WALLPAPER_APK" \
  "/system/app/LiveWallpapersPicker/LiveWallpapersPicker.apk" "system-livewallpaperpicker"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$PRINT_SPOOLER_APK" \
  "/system/app/PrintSpooler/PrintSpooler.apk" "system-printspooler"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$SIM_APP_DIALOG_APK" \
  "/system/app/SimAppDialog/SimAppDialog.apk" "system-simappdialog"

echo "Patching system_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$BASE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "system_b=${SYSTEM_IMG}" \
  --variant "otatrust-v0.17a-system-apk-only-locale-prune-exact-current"

system_b_hash="$(sha256_one "$SYSTEM_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"

{
  echo "variant=otatrust-v0.17a-system-apk-only-locale-prune-exact-current"
  echo "purpose=Promote system_b APK-only English/Chinese resources.arsc hard-prune candidates into a flashable sparse super"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partitions=system_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "system_b_start_sector=${SYSTEM_B_START_SECTOR}"
  echo "system_b_size_sectors=${SYSTEM_B_SIZE_SECTORS}"
  echo "system_b_sha256=${system_b_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$BASE_SPARSE" \
    "$BASIC_DREAMS_APK" \
    "$HTML_VIEWER_APK" \
    "$LIVE_WALLPAPER_APK" \
    "$PRINT_SPOOLER_APK" \
    "$SIM_APP_DIALOG_APK"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
