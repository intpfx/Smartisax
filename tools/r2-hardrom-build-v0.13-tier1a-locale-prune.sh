#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
APK_BUILDER="${APK_BUILDER:-${ROOT_DIR}/tools/r2-build-apk-locale-prune.sh}"
APK_VERIFIER="${APK_VERIFIER:-${ROOT_DIR}/tools/r2-verify-tier1a-locale-prune-apks.sh}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.13-tier1a-locale-prune}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.13-tier1a-locale-prune.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.13-tier1a-locale-prune-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.13-tier1a-locale-prune-exact-current.SHA256SUMS.txt"

PROTIPS_APK="${APK_OUT_DIR}/com.android.protips-locale-prune-en-zh.apk"
PRINT_RECOMMENDATION_APK="${APK_OUT_DIR}/com.android.printservice.recommendation-locale-prune-en-zh.apk"
OSU_LOGIN_APK="${APK_OUT_DIR}/com.android.hotspot2.osulogin-locale-prune-en-zh.apk"

REBUILD_APKS="${REBUILD_APKS:-0}"
BUILD_SUPER="${BUILD_SUPER:-0}"
SYSTEM_SELABEL="u:object_r:system_file:s0"

SYSTEM_B_SIZE=3049058304
SYSTEM_B_START_SECTOR=10487744
SYSTEM_B_SIZE_SECTORS=5955192

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh

Build an offline v0.13 exact-current candidate from the stable v0.4 baseline.
This is a low-exposure ROM-level language hard-prune batch. It replaces only:

  system_b:
    /system/app/Protips/Protips.apk
    /system/app/PrintRecommendationService/PrintRecommendationService.apk
    /system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk

with already verified English/Chinese-only resources.arsc variants.

Environment:
  REBUILD_APKS=1  rebuild the three Tier1a APKs before image construction
  BUILD_SUPER=1   also produce a flashable sparse super by direct sparse rewrite
                  (default 0 because this can consume several GiB on APFS)
  WORK_DIR=<dir>  put debugfs artifacts elsewhere

The script never flashes, reboots, erases misc, or changes /data. Flashing any
generated sparse super still requires explicit user confirmation.
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

ensure_tier1a_apks() {
  if [ "$REBUILD_APKS" = "1" ]; then
    echo "Rebuilding Tier1a locale-prune APKs..."
    "$APK_BUILDER" --package com.android.protips --out "$PROTIPS_APK" >/dev/null
    "$APK_BUILDER" --package com.android.printservice.recommendation --out "$PRINT_RECOMMENDATION_APK" >/dev/null
    "$APK_BUILDER" --package com.android.hotspot2.osulogin --out "$OSU_LOGIN_APK" >/dev/null
  elif [ "$REBUILD_APKS" != "0" ]; then
    die "REBUILD_APKS must be 0 or 1"
  fi

  need_file "$PROTIPS_APK"
  need_file "$PRINT_RECOMMENDATION_APK"
  need_file "$OSU_LOGIN_APK"

  echo "Verifying Tier1a APK candidates..."
  "$APK_VERIFIER" >/dev/null
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
  temp_path="${dir}/.${base}.smartisax-v013-tmp"
  held_path="${dir}/.${base}.smartisax-v013-stock-held"

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
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
need_executable "$APK_BUILDER"
need_executable "$APK_VERIFIER"
if [ "$BUILD_SUPER" != "0" ] && [ "$BUILD_SUPER" != "1" ]; then
  die "BUILD_SUPER must be 0 or 1"
fi

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR"
rm -f "$SYSTEM_IMG" "$MANIFEST"
if [ "$BUILD_SUPER" = "1" ]; then
  rm -f "$OUT_SPARSE" "${OUT_SPARSE}.SHA256SUMS.txt"
elif [ -e "$OUT_SPARSE" ]; then
  die "refusing BUILD_SUPER=0 while ${OUT_SPARSE} already exists; remove or archive it before system-only rebuild"
fi
rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/replace-*.debugfs "${WORK_DIR}/replacements.tsv"

ensure_tier1a_apks

echo "Extracting system_b from v0.4 sparse super..."
"$SPARSE_TOOL" --source-sparse "$BASE_SPARSE" --extract-image "system_b=${SYSTEM_IMG}" >/dev/null
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

echo "Replacing Tier1a APKs in system_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$PROTIPS_APK" \
  "/system/app/Protips/Protips.apk" "$SYSTEM_SELABEL" \
  "system-protips" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$PRINT_RECOMMENDATION_APK" \
  "/system/app/PrintRecommendationService/PrintRecommendationService.apk" "$SYSTEM_SELABEL" \
  "system-print-recommendation" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$OSU_LOGIN_APK" \
  "/system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk" "$SYSTEM_SELABEL" \
  "system-osu-login" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified ext4 image..."
fsck_image "$SYSTEM_IMG"

echo "Verifying replaced APKs after fsck..."
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$PROTIPS_APK" \
  "/system/app/Protips/Protips.apk" "system-protips"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$PRINT_RECOMMENDATION_APK" \
  "/system/app/PrintRecommendationService/PrintRecommendationService.apk" "system-print-recommendation"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$OSU_LOGIN_APK" \
  "/system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk" "system-osu-login"

system_b_hash="$(sha256_one "$SYSTEM_IMG")"

if [ "$BUILD_SUPER" = "1" ]; then
  echo "Patching system_b back into sparse super..."
  "$SPARSE_TOOL" \
    --source-sparse "$BASE_SPARSE" \
    --out "$OUT_SPARSE" \
    --image "system_b=${SYSTEM_IMG}" \
    --variant "otatrust-v0.13-tier1a-locale-prune-exact-current"
fi

{
  echo "variant=otatrust-v0.13-tier1a-locale-prune-exact-current"
  echo "purpose=Tier1a minimal-exposure ROM-level English/Chinese-only resources.arsc hard-prune"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partitions=system_b"
  echo "system_image=${SYSTEM_IMG}"
  if [ "$BUILD_SUPER" = "1" ]; then
    echo "sparse_super=${OUT_SPARSE}"
  else
    echo "sparse_super=not-built"
  fi
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "system_b_start_sector=${SYSTEM_B_START_SECTOR}"
  echo "system_b_size_sectors=${SYSTEM_B_SIZE_SECTORS}"
  echo "system_b_sha256=${system_b_hash}"
  echo "rebuild_apks=${REBUILD_APKS}"
  echo "built_super=${BUILD_SUPER}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  if [ "$BUILD_SUPER" = "1" ]; then
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$BASE_SPARSE" \
      "$PROTIPS_APK" "$PRINT_RECOMMENDATION_APK" "$OSU_LOGIN_APK"
  else
    shasum -a 256 "$SYSTEM_IMG" "$BASE_SPARSE" \
      "$PROTIPS_APK" "$PRINT_RECOMMENDATION_APK" "$OSU_LOGIN_APK"
  fi
} > "$MANIFEST"

if [ "$BUILD_SUPER" = "1" ]; then
  echo "Built: ${OUT_SPARSE}"
else
  echo "Built system image only: ${SYSTEM_IMG}"
fi
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
