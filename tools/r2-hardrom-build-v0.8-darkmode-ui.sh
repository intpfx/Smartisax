#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
IMG2SIMG="${IMG2SIMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/img2simg}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
APK_BUILDER="${APK_BUILDER:-${ROOT_DIR}/tools/r2-build-settingssmartisan-darkmode-ui-apk.sh}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
STOCK_SETTINGS_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.8-darkmode-ui"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
RAW_SUPER="${WORK_DIR}/super-otatrust-v0.8-darkmode-ui-exact-current.img"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.8-darkmode-ui.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.8-darkmode-ui-exact-current.SHA256SUMS.txt"
DARKMODE_APK="${APK_OUT_DIR}/SettingsSmartisan-darkmode-ui.apk"
DARKMODE_SIG_REPORT="${APK_OUT_DIR}/SettingsSmartisan-darkmode-ui.signature.txt"
DUMPED_DARKMODE_APK="${WORK_DIR}/SettingsSmartisan-darkmode-ui-dumped-from-system.img.apk"

KEEP_RAW="${KEEP_RAW:-0}"

# Current super slot 1 maps system_b to sector 10487744, size 5955192 sectors.
SYSTEM_B_SKIP_4096=1310968
SYSTEM_B_COUNT_4096=744399
SYSTEM_B_SIZE=3049058304

SETTINGS_APK_DST="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
SETTINGS_DIR="/system/priv-app/SettingsSmartisan"
SELABEL="u:object_r:system_file:s0"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.8-darkmode-ui.sh

Build an offline v0.8 exact-current super candidate from the stable v0.4
baseline. The ROM change is replacing SettingsSmartisan.apk with a behavior
patch that exposes a native dark-mode switch in BrightnessSettingsFragment.

This image is not flash-authorized yet. The patched APK replaces classes.dex,
so ordinary JAR/keytool verification reports a classes.dex digest error. It is
only a candidate for the system-partition certs-only path documented in:

  docs/research/system-apk-signature-boundary.md

Do not flash this variant until the v0.6 SettingsSmartisan no-op replacement
has passed live validation and the user explicitly confirms flashing v0.8.
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
  local selabel="$4"
  local tag="$5"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped.apk"
  local dir
  local base
  local temp_path
  local held_path

  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  temp_path="${dir}/.${base}.smartisax-v08-tmp"
  held_path="${dir}/.${base}.smartisax-v08-stock-held"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination directory: ${dst}"
  debugfs_path_exists "$image" "$dst" || die "missing stock destination file: ${dst}"
  if debugfs_path_exists "$image" "$temp_path" || debugfs_path_exists "$image" "$held_path"; then
    die "temporary or held path already exists for ${dst}; refusing ambiguous replacement"
  fi

  {
    # Keep the stock inode linked so debugfs never frees shared ext4 blocks.
    echo "ln ${dst} ${held_path}"
    echo "write ${src} ${temp_path}"
    echo "set_inode_field ${temp_path} mode 0100644"
    echo "set_inode_field ${temp_path} uid 0"
    echo "set_inode_field ${temp_path} gid 0"
    echo "ea_set ${temp_path} security.selinux ${selabel}"
    echo "unlink ${dst}"
    echo "ln ${temp_path} ${dst}"
    echo "unlink ${temp_path}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$dst" || die "missing replaced file: ${dst}"
  debugfs_path_exists "$image" "$held_path" || die "missing held stock file: ${held_path}"
  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1

  local src_hash
  local dumped_hash
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
  "" )
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
need_file "$STOCK_SETTINGS_APK"
need_executable "$APK_BUILDER"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SIMG2IMG"
need_executable "$IMG2SIMG"
need_executable "$LPDUMP"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR"
rm -f "$RAW_SUPER" "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" \
  "$DUMPED_DARKMODE_APK" \
  "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"
rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/replace-*.debugfs "${WORK_DIR}/replacements.tsv"

echo "Building SettingsSmartisan dark-mode UI APK..."
"$APK_BUILDER" >/dev/null
need_file "$DARKMODE_APK"
need_file "$DARKMODE_SIG_REPORT"
grep -q '^keytool_status=1$' "$DARKMODE_SIG_REPORT" \
  || die "unexpected dark-mode APK keytool boundary; review ${DARKMODE_SIG_REPORT}"
grep -q 'SHA-256 digest error for classes.dex' "$DARKMODE_SIG_REPORT" \
  || die "dark-mode APK signature report does not show the expected classes.dex digest boundary"

echo "Expanding v0.4 sparse super to raw..."
"$SIMG2IMG" "$BASE_SPARSE" "$RAW_SUPER"

echo "Extracting system_b..."
dd if="$RAW_SUPER" of="$SYSTEM_IMG" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" status=none
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

debugfs_path_exists "$SYSTEM_IMG" "$SETTINGS_DIR" || die "missing SettingsSmartisan directory in system image"
debugfs_path_exists "$SYSTEM_IMG" "$SETTINGS_APK_DST" || die "missing stock SettingsSmartisan APK in system image"

echo "Replacing SettingsSmartisan APK in system image..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$DARKMODE_APK" \
  "$SETTINGS_APK_DST" "$SELABEL" \
  "settingssmartisan-darkmode-ui" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified system image..."
fsck_image "$SYSTEM_IMG"

echo "Verifying replaced APK after fsck..."
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$DARKMODE_APK" \
  "$SETTINGS_APK_DST" \
  "settingssmartisan-darkmode-ui"

darkmode_hash="$(sha256_one "$DARKMODE_APK")"
dumped_hash="$(sha256_one "${WORK_DIR}/settingssmartisan-darkmode-ui-postfsck-dumped.apk")"

echo "Patching system_b back into raw super..."
dd if="$SYSTEM_IMG" of="$RAW_SUPER" bs=4096 seek="$SYSTEM_B_SKIP_4096" conv=notrunc status=none

system_b_hash="$(dd if="$RAW_SUPER" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
expected_system_hash="$(sha256_one "$SYSTEM_IMG")"
[ "$system_b_hash" = "$expected_system_hash" ] || die "patched system_b hash mismatch"

"$LPDUMP" -s 0 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot0.txt"
"$LPDUMP" -s 1 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot1.txt"
cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"

echo "Converting patched raw super to sparse..."
"$IMG2SIMG" "$RAW_SUPER" "$OUT_SPARSE"

if [ "$KEEP_RAW" != "1" ]; then
  rm -f "$RAW_SUPER"
fi

{
  echo "variant=otatrust-v0.8-darkmode-ui-exact-current"
  echo "purpose=SettingsSmartisan native dark-mode switch in BrightnessSettingsFragment"
  echo "flash_gate=not authorized until v0.6 SettingsSmartisan no-op passes live validation"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partition=system_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "settings_stock_apk=${STOCK_SETTINGS_APK}"
  echo "settings_darkmode_apk=${DARKMODE_APK}"
  echo "settings_darkmode_signature_report=${DARKMODE_SIG_REPORT}"
  echo "settings_darkmode_inserted_path=${SETTINGS_APK_DST}"
  echo "settings_darkmode_sha256=${darkmode_hash}"
  echo "settings_dumped_sha256=${dumped_hash}"
  echo "system_b_start_sector=10487744"
  echo "system_b_size_sectors=5955192"
  echo "system_b_sha256=${system_b_hash}"
  echo "keep_raw=${KEEP_RAW}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$BASE_SPARSE" "$DARKMODE_APK" "$STOCK_SETTINGS_APK"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Dark-mode APK: ${DARKMODE_APK}"
echo "Signature report: ${DARKMODE_SIG_REPORT}"
echo "Manifest: ${MANIFEST}"
echo "Metadata dump: ${OUT_SPARSE}.lpdump.txt"
echo "Flash gate: v0.6 no-op live validation must pass before considering this image."
