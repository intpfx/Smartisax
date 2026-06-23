#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
IMG2SIMG="${IMG2SIMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/img2simg}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"

FRAMEWORK_RES_BUILDER="${FRAMEWORK_RES_BUILDER:-${ROOT_DIR}/tools/r2-build-framework-res-locale-probe.sh}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
RAW_ROM="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.12-framework-res-noop}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
RAW_SUPER="${WORK_DIR}/super-otatrust-v0.12-framework-res-noop-exact-current.img"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.12-framework-res-noop.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.12-framework-res-noop-exact-current.SHA256SUMS.txt"

FW_RES_NOOP_APK="${APK_OUT_DIR}/framework-res-rebuild-noop.apk"
FW_RES_NOOP_SIG="${APK_OUT_DIR}/framework-res-rebuild-noop.signature.txt"
STOCK_FW_RES="${RAW_ROM}/system/system/framework/framework-res.apk"

KEEP_RAW="${KEEP_RAW:-0}"
REBUILD_APK="${REBUILD_APK:-1}"
BUILD_SUPER="${BUILD_SUPER:-1}"

SYSTEM_B_SKIP_4096=1310968
SYSTEM_B_COUNT_4096=744399
SYSTEM_B_SIZE=3049058304
SYSTEM_SELABEL="u:object_r:system_file:s0"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.12-framework-res-noop.sh

Build an offline v0.12 exact-current super candidate from the stable v0.4
baseline. This is a framework-res resource-table no-op gate: it replaces only

  system_b:
    /system/framework/framework-res.apk

with framework-res-rebuild-noop.apk, which keeps the stock APK shell and changes
only resources.arsc from an apktool decode/rebuild without source edits.

The candidate is not flash-authorized by this script. It exists to prove the
framework-res resource-table replacement boundary before the v0.10 language
hard-prune ROM is flashed.

Environment:
  REBUILD_APK=0   reuse hard-rom/build/apk/framework-res-rebuild-noop.apk
  BUILD_SUPER=0   build and verify only the modified system image; do not
                  produce a flashable sparse super
  KEEP_RAW=1      keep the expanded raw super image in the work dir
  WORK_DIR=<dir>  put temporary raw super and debugfs artifacts elsewhere
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

verify_resource_sig_boundary() {
  local report="$1"
  need_file "$report"
  grep -q '^keytool_status=1$' "$report" \
    || die "unexpected keytool boundary; review ${report}"
  grep -q 'SHA-256 digest error for resources.arsc' "$report" \
    || die "signature report does not show expected resources.arsc digest boundary: ${report}"
}

ensure_noop_apk() {
  if [ "$REBUILD_APK" = "1" ]; then
    echo "Building framework-res no-op APK..."
    "$FRAMEWORK_RES_BUILDER" --mode noop --out "$FW_RES_NOOP_APK" >/dev/null
  fi

  need_file "$FW_RES_NOOP_APK"
  verify_resource_sig_boundary "$FW_RES_NOOP_SIG"
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
  temp_path="${dir}/.${base}.smartisax-v012-tmp"
  held_path="${dir}/.${base}.smartisax-v012-stock-held"

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
need_file "$STOCK_FW_RES"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SIMG2IMG"
if [ "$BUILD_SUPER" = "1" ]; then
  need_executable "$IMG2SIMG"
  need_executable "$LPDUMP"
elif [ "$BUILD_SUPER" != "0" ]; then
  die "BUILD_SUPER must be 0 or 1"
fi
need_executable "$FRAMEWORK_RES_BUILDER"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR"
rm -f "$RAW_SUPER" "$SYSTEM_IMG" "$MANIFEST"
if [ "$BUILD_SUPER" = "1" ]; then
  rm -f "$OUT_SPARSE" \
    "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"
elif [ -e "$OUT_SPARSE" ]; then
  die "refusing BUILD_SUPER=0 while ${OUT_SPARSE} already exists; remove or archive it before system-only rebuild"
fi
rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/replace-*.debugfs "${WORK_DIR}/replacements.tsv"

ensure_noop_apk

echo "Expanding v0.4 sparse super to raw..."
"$SIMG2IMG" "$BASE_SPARSE" "$RAW_SUPER"

echo "Extracting system_b..."
dd if="$RAW_SUPER" of="$SYSTEM_IMG" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" status=none
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

echo "Replacing framework-res.apk in system_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$FW_RES_NOOP_APK" \
  "/system/framework/framework-res.apk" "$SYSTEM_SELABEL" \
  "system-framework-res" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified ext4 image..."
fsck_image "$SYSTEM_IMG"

echo "Verifying replaced APK after fsck..."
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$FW_RES_NOOP_APK" \
  "/system/framework/framework-res.apk" \
  "system-framework-res"

expected_system_hash="$(sha256_one "$SYSTEM_IMG")"
system_b_hash="$expected_system_hash"

if [ "$BUILD_SUPER" = "1" ]; then
  echo "Patching system_b back into raw super..."
  dd if="$SYSTEM_IMG" of="$RAW_SUPER" bs=4096 seek="$SYSTEM_B_SKIP_4096" conv=notrunc status=none

  system_b_hash="$(dd if="$RAW_SUPER" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  [ "$system_b_hash" = "$expected_system_hash" ] || die "patched system_b hash mismatch"

  "$LPDUMP" -s 0 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot0.txt"
  "$LPDUMP" -s 1 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot1.txt"
  cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"

  echo "Converting patched raw super to sparse..."
  "$IMG2SIMG" "$RAW_SUPER" "$OUT_SPARSE"
fi

if [ "$KEEP_RAW" != "1" ]; then
  rm -f "$RAW_SUPER"
fi

{
  echo "variant=otatrust-v0.12-framework-res-noop-exact-current"
  echo "purpose=framework-res resource-table no-op replacement gate before language hard-prune"
  echo "flash_gate=not authorized; RED early-boot framework resource gate; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partitions=system_b"
  echo "system_image=${SYSTEM_IMG}"
  if [ "$BUILD_SUPER" = "1" ]; then
    echo "sparse_super=${OUT_SPARSE}"
  else
    echo "sparse_super=not-built"
  fi
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "system_b_start_sector=10487744"
  echo "system_b_size_sectors=5955192"
  echo "system_b_sha256=${system_b_hash}"
  echo "keep_raw=${KEEP_RAW}"
  echo "rebuilt_apk=${REBUILD_APK}"
  echo "built_super=${BUILD_SUPER}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  if [ "$BUILD_SUPER" = "1" ]; then
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$BASE_SPARSE" \
      "$FW_RES_NOOP_APK" "$STOCK_FW_RES"
  else
    shasum -a 256 "$SYSTEM_IMG" "$BASE_SPARSE" "$FW_RES_NOOP_APK" "$STOCK_FW_RES"
  fi
} > "$MANIFEST"

if [ "$BUILD_SUPER" = "1" ]; then
  echo "Built: ${OUT_SPARSE}"
else
  echo "Built system image only: ${SYSTEM_IMG}"
fi
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
if [ "$BUILD_SUPER" = "1" ]; then
  echo "Metadata dump: ${OUT_SPARSE}.lpdump.txt"
fi
echo "Flash gate: explicit user confirmation required; this is a RED framework resource no-op gate."
