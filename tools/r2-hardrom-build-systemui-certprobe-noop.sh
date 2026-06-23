#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
IMG2SIMG="${IMG2SIMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/img2simg}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"

SYSTEMUI_NOOP_BUILDER="${SYSTEMUI_NOOP_BUILDER:-${ROOT_DIR}/tools/r2-build-systemui-certprobe-noop-apk.sh}"
SYSTEMUI_NOOP_VERIFIER="${SYSTEMUI_NOOP_VERIFIER:-${ROOT_DIR}/tools/r2-verify-systemui-certprobe-noop-apk.sh}"

SYSTEMUI_NOOP_VARIANT="${SYSTEMUI_NOOP_VARIANT:-systemui-certprobe-noop}"
BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
STOCK_SYSTEMUI_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
PROBE_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${SYSTEMUI_NOOP_VARIANT}}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
RAW_SUPER="${RAW_SUPER:-${WORK_DIR}/super-otatrust-${SYSTEMUI_NOOP_VARIANT}-exact-current.img}"
SYSTEM_EXT_IMG="${SYSTEM_EXT_IMG:-${OUT_DIR}/system_ext-otatrust-${SYSTEMUI_NOOP_VARIANT}.img}"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-${SYSTEMUI_NOOP_VARIANT}-exact-current.sparse.img}"
MANIFEST="${MANIFEST:-${OUT_DIR}/super-otatrust-${SYSTEMUI_NOOP_VARIANT}-exact-current.SHA256SUMS.txt}"

KEEP_RAW="${KEEP_RAW:-0}"
REBUILD_APK="${REBUILD_APK:-1}"
MAGIC="APK Sig Block 42"

# Current v0.4 super slot 1 maps system_ext_b to sector 16443328, size 578352 sectors.
SYSTEM_EXT_B_SKIP_4096=2055416
SYSTEM_EXT_B_COUNT_4096=72294
SYSTEM_EXT_B_SIZE=296116224

SYSTEMUI_APK_DST="/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-systemui-certprobe-noop.sh

Build an offline exact-current super candidate from a source sparse super.
The only ROM change is a one-byte in-place patch inside system_ext_b
SmartisanSystemUI.apk:

  APK Sig Block 42 -> XPK Sig Block 42

This keeps the APK size and every ZIP/JAR entry byte-identical, avoids inode
replacement on the zero-free-block shared_blocks system_ext image, and tests
the original-certificate-readable v1/JAR boundary for SystemUI.

This script does not touch the device. Flashing the generated sparse image
still requires explicit user confirmation.

Environment:
  BASE_SPARSE=<path>                 source sparse super; defaults to v0.4
  SYSTEMUI_NOOP_VARIANT=<name>       output variant name; defaults to systemui-certprobe-noop
  REBUILD_APK=0  reuse the existing SmartisanSystemUI-certprobe-noop.apk
  KEEP_RAW=1    keep the expanded raw super image in hard-rom/work
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

find_magic_offset() {
  perl -0777 -ne '
    my $magic = $ENV{MAGIC};
    my $i = index($_, $magic);
    die "magic not found\n" if $i < 0;
    my $j = index($_, $magic, $i + 1);
    die "magic appears more than once\n" if $j >= 0;
    print $i;
  ' "$1"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_bmap() {
  local image="$1"
  local path="$2"
  local logical_block="$3"
  "$DEBUGFS" -R "bmap ${path} ${logical_block}" "$image" 2>/dev/null | awk '/^[0-9]+$/ {print; exit}'
}

require_single_inode_for_block() {
  local image="$1"
  local block="$2"
  local out="$3"
  "$DEBUGFS" -R "icheck ${block}" "$image" > "$out" 2>&1
  awk '/^[0-9]+[[:space:]]+[0-9]+/ {count++} END {exit count == 1 ? 0 : 1}' "$out" \
    || die "physical block ${block} is not uniquely mapped; see ${out}"
}

fsck_image_read_only() {
  local image="$1"
  local status=0
  "$E2FSCK" -fn "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "read-only e2fsck failed for ${image} with exit code ${status}"
}

dump_and_compare() {
  local image="$1"
  local expected="$2"
  local out="$3"
  "$DEBUGFS" -R "dump ${SYSTEMUI_APK_DST} ${out}" "$image" >/dev/null 2>&1
  [ "$(sha256_one "$out")" = "$(sha256_one "$expected")" ] \
    || die "dumped SmartisanSystemUI hash mismatch: ${out}"
  unzip -t "$out" >/dev/null
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
need_file "$STOCK_SYSTEMUI_APK"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SIMG2IMG"
need_executable "$IMG2SIMG"
need_executable "$LPDUMP"
need_executable "$SYSTEMUI_NOOP_BUILDER"
need_executable "$SYSTEMUI_NOOP_VERIFIER"

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$RAW_SUPER" "$SYSTEM_EXT_IMG" "$OUT_SPARSE" "$MANIFEST" \
  "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.txt "${WORK_DIR}"/*.tsv "${WORK_DIR}"/replace-*.debugfs

if [ "$REBUILD_APK" = "1" ]; then
  echo "Building same-size SmartisanSystemUI cert-probe no-op APK..."
  "$SYSTEMUI_NOOP_BUILDER" >/dev/null
fi
need_file "$PROBE_APK"

echo "Verifying SmartisanSystemUI no-op APK scope..."
"$SYSTEMUI_NOOP_VERIFIER" >/dev/null

echo "Expanding source sparse super to raw: ${BASE_SPARSE}"
"$SIMG2IMG" "$BASE_SPARSE" "$RAW_SUPER"

echo "Extracting system_ext_b..."
dd if="$RAW_SUPER" of="$SYSTEM_EXT_IMG" bs=4096 skip="$SYSTEM_EXT_B_SKIP_4096" count="$SYSTEM_EXT_B_COUNT_4096" status=none
[ "$(size_bytes "$SYSTEM_EXT_IMG")" -eq "$SYSTEM_EXT_B_SIZE" ] || die "unexpected system_ext_b size"
debugfs_path_exists "$SYSTEM_EXT_IMG" "$SYSTEMUI_APK_DST" || die "missing stock SmartisanSystemUI path in system_ext image"

echo "Verifying stock SmartisanSystemUI before patch..."
dump_and_compare "$SYSTEM_EXT_IMG" "$STOCK_SYSTEMUI_APK" "${WORK_DIR}/SmartisanSystemUI-before.apk"

magic_offset="$(MAGIC="$MAGIC" find_magic_offset "$STOCK_SYSTEMUI_APK")"
logical_block="$((magic_offset / 4096))"
block_offset="$((magic_offset % 4096))"
physical_block="$(debugfs_bmap "$SYSTEM_EXT_IMG" "$SYSTEMUI_APK_DST" "$logical_block")"
[ -n "$physical_block" ] || die "could not map logical block ${logical_block} for ${SYSTEMUI_APK_DST}"
require_single_inode_for_block "$SYSTEM_EXT_IMG" "$physical_block" "${WORK_DIR}/systemui-patch-block-icheck.txt"
image_offset="$((physical_block * 4096 + block_offset))"

echo "Applying one-byte in-place SystemUI APK patch..."
printf 'X' | dd of="$SYSTEM_EXT_IMG" bs=1 seek="$image_offset" conv=notrunc status=none

echo "Verifying patched SmartisanSystemUI in system_ext_b..."
dump_and_compare "$SYSTEM_EXT_IMG" "$PROBE_APK" "${WORK_DIR}/SmartisanSystemUI-after.apk"
fsck_image_read_only "$SYSTEM_EXT_IMG"

{
  echo "apk_path=${SYSTEMUI_APK_DST}"
  echo "apk_magic_offset=${magic_offset}"
  echo "apk_logical_block=${logical_block}"
  echo "apk_block_offset=${block_offset}"
  echo "image_physical_block=${physical_block}"
  echo "image_patch_offset=${image_offset}"
  echo "patch_from=A"
  echo "patch_to=X"
} > "${WORK_DIR}/patch-systemui-byte.tsv"

echo "Patching system_ext_b back into raw super..."
dd if="$SYSTEM_EXT_IMG" of="$RAW_SUPER" bs=4096 seek="$SYSTEM_EXT_B_SKIP_4096" conv=notrunc status=none

system_ext_b_hash="$(dd if="$RAW_SUPER" bs=4096 skip="$SYSTEM_EXT_B_SKIP_4096" count="$SYSTEM_EXT_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
expected_system_ext_hash="$(sha256_one "$SYSTEM_EXT_IMG")"
[ "$system_ext_b_hash" = "$expected_system_ext_hash" ] || die "patched system_ext_b hash mismatch"

"$LPDUMP" -s 0 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot0.txt"
"$LPDUMP" -s 1 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot1.txt"
cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"

echo "Converting patched raw super to sparse..."
"$IMG2SIMG" "$RAW_SUPER" "$OUT_SPARSE"

if [ "$KEEP_RAW" != "1" ]; then
  rm -f "$RAW_SUPER"
fi

probe_hash="$(sha256_one "$PROBE_APK")"
stock_hash="$(sha256_one "$STOCK_SYSTEMUI_APK")"

{
  echo "variant=otatrust-${SYSTEMUI_NOOP_VARIANT}-exact-current"
  echo "purpose=SmartisanSystemUI same-size original-cert-readable no-op replacement gate"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "systemui_noop_variant=${SYSTEMUI_NOOP_VARIANT}"
  echo "patched_partition=system_ext_b"
  echo "system_ext_image=${SYSTEM_EXT_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "patch_record=${WORK_DIR}/patch-systemui-byte.tsv"
  echo "system_ext_b_start_sector=16443328"
  echo "system_ext_b_size_sectors=578352"
  echo "system_ext_b_sha256=${system_ext_b_hash}"
  echo "systemui_path=${SYSTEMUI_APK_DST}"
  echo "systemui_stock_apk=${STOCK_SYSTEMUI_APK}"
  echo "systemui_stock_sha256=${stock_hash}"
  echo "systemui_probe_apk=${PROBE_APK}"
  echo "systemui_probe_sha256=${probe_hash}"
  echo "keep_raw=${KEEP_RAW}"
  echo "rebuilt_apk=${REBUILD_APK}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# patch"
  cat "${WORK_DIR}/patch-systemui-byte.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_EXT_IMG" "$BASE_SPARSE" "$PROBE_APK" "$STOCK_SYSTEMUI_APK"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "System_ext image: ${SYSTEM_EXT_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Metadata dump: ${OUT_SPARSE}.lpdump.txt"
echo "Flash gate: explicit user confirmation required."
