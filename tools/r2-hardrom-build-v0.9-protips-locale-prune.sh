#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
IMG2SIMG="${IMG2SIMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/img2simg}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
APK_BUILDER="${APK_BUILDER:-${ROOT_DIR}/tools/r2-build-protips-locale-prune-apk.sh}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
STOCK_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/app/Protips/Protips.apk"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.9-protips-locale-prune"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
RAW_SUPER="${WORK_DIR}/super-otatrust-v0.9-protips-locale-prune-exact-current.img"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.9-protips-locale-prune.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.9-protips-locale-prune-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.9-protips-locale-prune-exact-current.SHA256SUMS.txt"
PRUNED_APK="${APK_OUT_DIR}/Protips-locale-prune-ja-ko.apk"
PRUNED_SIG_REPORT="${APK_OUT_DIR}/Protips-locale-prune-ja-ko.signature.txt"
DUMPED_APK="${WORK_DIR}/Protips-locale-prune-dumped-from-system.img.apk"

KEEP_RAW="${KEEP_RAW:-0}"

# Current super slot 1 maps system_b to sector 10487744, size 5955192 sectors.
SYSTEM_B_SKIP_4096=1310968
SYSTEM_B_COUNT_4096=744399
SYSTEM_B_SIZE=3049058304

APK_DST="/system/app/Protips/Protips.apk"
APK_DIR="/system/app/Protips"
SELABEL="u:object_r:system_file:s0"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.9-protips-locale-prune.sh

Build an offline v0.9 exact-current super candidate from the stable v0.4
baseline. The ROM change is replacing Protips.apk with a resource-table patch
that removes Japanese and Korean values resources while keeping English,
Simplified Chinese, and Traditional Chinese.

This image is not flash-authorized. The patched APK changes resources.arsc, so
ordinary JAR/keytool verification reports a resources.arsc digest error. It is
only a low-risk L2 language-prune toolchain probe for the original-cert-
preserving system-partition path.
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

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_rm_file_if_exists() {
  local image="$1"
  local path="$2"
  if debugfs_path_exists "$image" "$path"; then
    "$DEBUGFS" -w -R "rm ${path}" "$image" >/dev/null 2>&1 || true
  fi
}

make_debugfs_cmds() {
  local cmd_file="$1"
  : > "$cmd_file"
  {
    echo "write ${PRUNED_APK} ${APK_DST}"
    echo "set_inode_field ${APK_DST} mode 0100644"
    echo "set_inode_field ${APK_DST} uid 0"
    echo "set_inode_field ${APK_DST} gid 0"
    echo "ea_set ${APK_DST} security.selinux ${SELABEL}"
  } >> "$cmd_file"
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
need_file "$STOCK_APK"
need_executable "$APK_BUILDER"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SIMG2IMG"
need_executable "$IMG2SIMG"
need_executable "$LPDUMP"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR"
rm -f "$RAW_SUPER" "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" \
  "$DUMPED_APK" \
  "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"

echo "Building Protips locale-prune APK..."
"$APK_BUILDER" >/dev/null
need_file "$PRUNED_APK"
need_file "$PRUNED_SIG_REPORT"
grep -q '^keytool_status=1$' "$PRUNED_SIG_REPORT" \
  || die "unexpected Protips APK keytool boundary; review ${PRUNED_SIG_REPORT}"
grep -q 'SHA-256 digest error for resources.arsc' "$PRUNED_SIG_REPORT" \
  || die "Protips APK signature report does not show the expected resources.arsc digest boundary"

echo "Expanding v0.4 sparse super to raw..."
"$SIMG2IMG" "$BASE_SPARSE" "$RAW_SUPER"

echo "Extracting system_b..."
dd if="$RAW_SUPER" of="$SYSTEM_IMG" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" status=none
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

debugfs_path_exists "$SYSTEM_IMG" "$APK_DIR" || die "missing Protips directory in system image"
debugfs_path_exists "$SYSTEM_IMG" "$APK_DST" || die "missing stock Protips APK in system image"
debugfs_rm_file_if_exists "$SYSTEM_IMG" "$APK_DST"

cmd_file="${WORK_DIR}/replace-protips-locale-prune.debugfs"
make_debugfs_cmds "$cmd_file"

echo "Replacing Protips APK in system image..."
"$DEBUGFS" -w -f "$cmd_file" "$SYSTEM_IMG" >/dev/null
debugfs_path_exists "$SYSTEM_IMG" "$APK_DST" || die "missing replaced Protips APK"

echo "Dumping replaced APK for hash verification..."
"$DEBUGFS" -R "dump ${APK_DST} ${DUMPED_APK}" "$SYSTEM_IMG" >/dev/null 2>&1
dumped_hash="$(shasum -a 256 "$DUMPED_APK" | awk '{print $1}')"
pruned_hash="$(shasum -a 256 "$PRUNED_APK" | awk '{print $1}')"
[ "$dumped_hash" = "$pruned_hash" ] || die "dumped Protips hash mismatch"

fsck_status=0
"$E2FSCK" -fy "$SYSTEM_IMG" >/dev/null || fsck_status=$?
[ "$fsck_status" -le 1 ] || die "e2fsck repair failed with exit code ${fsck_status}"
"$E2FSCK" -fn "$SYSTEM_IMG" >/dev/null

echo "Patching system_b back into raw super..."
dd if="$SYSTEM_IMG" of="$RAW_SUPER" bs=4096 seek="$SYSTEM_B_SKIP_4096" conv=notrunc status=none

system_b_hash="$(dd if="$RAW_SUPER" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
expected_system_hash="$(shasum -a 256 "$SYSTEM_IMG" | awk '{print $1}')"
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
  echo "variant=otatrust-v0.9-protips-locale-prune-exact-current"
  echo "purpose=Protips ja/ko compiled values resource prune"
  echo "flash_gate=not authorized; low-risk L2 language-prune probe"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partition=system_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "stock_apk=${STOCK_APK}"
  echo "pruned_apk=${PRUNED_APK}"
  echo "pruned_signature_report=${PRUNED_SIG_REPORT}"
  echo "inserted_path=${APK_DST}"
  echo "pruned_sha256=${pruned_hash}"
  echo "dumped_sha256=${dumped_hash}"
  echo "system_b_start_sector=10487744"
  echo "system_b_size_sectors=5955192"
  echo "system_b_sha256=${system_b_hash}"
  echo "keep_raw=${KEEP_RAW}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$BASE_SPARSE" "$PRUNED_APK" "$STOCK_APK"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Pruned APK: ${PRUNED_APK}"
echo "Signature report: ${PRUNED_SIG_REPORT}"
echo "Manifest: ${MANIFEST}"
echo "Metadata dump: ${OUT_SPARSE}.lpdump.txt"
echo "Flash gate: explicit user confirmation required."
