#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
IMG2SIMG="${IMG2SIMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/img2simg}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"

BASE_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img"
CONTROL_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisaxControls.apk"
CONTROL_PERMS="${ROOT_DIR}/apps/SmartisaxControls/privapp-permissions-com.smartisax.controls.xml"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.5-control"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
RAW_SUPER="${WORK_DIR}/super-otatrust-v0.5-control-exact-current.img"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.5-control.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.5-control-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.5-control-exact-current.SHA256SUMS.txt"

KEEP_RAW="${KEEP_RAW:-0}"

# Current super slot 1 maps system_b to sector 10487744, size 5955192 sectors.
SYSTEM_B_SKIP_4096=1310968
SYSTEM_B_COUNT_4096=744399
SYSTEM_B_SIZE=3049058304

CONTROL_DIR="/system/priv-app/SmartisaxControls"
CONTROL_APK_DST="${CONTROL_DIR}/SmartisaxControls.apk"
CONTROL_PERMS_DST="/system/etc/permissions/privapp-permissions-com.smartisax.controls.xml"
SELABEL="u:object_r:system_file:s0"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
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
  local mkdir_control="$2"

  : > "$cmd_file"
  if [ "$mkdir_control" = "1" ]; then
    {
      echo "mkdir ${CONTROL_DIR}"
      echo "set_inode_field ${CONTROL_DIR} mode 040755"
      echo "set_inode_field ${CONTROL_DIR} uid 0"
      echo "set_inode_field ${CONTROL_DIR} gid 0"
      echo "ea_set ${CONTROL_DIR} security.selinux ${SELABEL}"
    } >> "$cmd_file"
  fi

  {
    echo "write ${CONTROL_APK} ${CONTROL_APK_DST}"
    echo "write ${CONTROL_PERMS} ${CONTROL_PERMS_DST}"
    echo "set_inode_field ${CONTROL_APK_DST} mode 0100644"
    echo "set_inode_field ${CONTROL_APK_DST} uid 0"
    echo "set_inode_field ${CONTROL_APK_DST} gid 0"
    echo "ea_set ${CONTROL_APK_DST} security.selinux ${SELABEL}"
    echo "set_inode_field ${CONTROL_PERMS_DST} mode 0100644"
    echo "set_inode_field ${CONTROL_PERMS_DST} uid 0"
    echo "set_inode_field ${CONTROL_PERMS_DST} gid 0"
    echo "ea_set ${CONTROL_PERMS_DST} security.selinux ${SELABEL}"
  } >> "$cmd_file"
}

need_file "$DEBUGFS"
need_file "$E2FSCK"
need_file "$SIMG2IMG"
need_file "$IMG2SIMG"
need_file "$LPDUMP"
need_file "$BASE_SPARSE"
need_file "$CONTROL_APK"
need_file "$CONTROL_PERMS"

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$RAW_SUPER" "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" \
  "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"

echo "Expanding v0.4 sparse super to raw..."
"$SIMG2IMG" "$BASE_SPARSE" "$RAW_SUPER"

echo "Extracting system_b..."
dd if="$RAW_SUPER" of="$SYSTEM_IMG" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" status=none
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

debugfs_rm_file_if_exists "$SYSTEM_IMG" "$CONTROL_APK_DST"
debugfs_rm_file_if_exists "$SYSTEM_IMG" "$CONTROL_PERMS_DST"

mkdir_control=0
if ! debugfs_path_exists "$SYSTEM_IMG" "$CONTROL_DIR"; then
  mkdir_control=1
fi

cmd_file="${WORK_DIR}/insert-smartisax-controls.debugfs"
make_debugfs_cmds "$cmd_file" "$mkdir_control"

echo "Inserting SmartisaxControls into system image..."
"$DEBUGFS" -w -f "$cmd_file" "$SYSTEM_IMG" >/dev/null

for path in "$CONTROL_DIR" "$CONTROL_APK_DST" "$CONTROL_PERMS_DST"; do
  debugfs_path_exists "$SYSTEM_IMG" "$path" || die "missing inserted path: $path"
done

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
  echo "variant=otatrust-v0.5-control-exact-current"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "patched_partition=system_b"
  echo "system_b_start_sector=10487744"
  echo "system_b_size_sectors=5955192"
  echo "system_b_sha256=${system_b_hash}"
  echo "control_apk=${CONTROL_APK}"
  echo "control_permissions=${CONTROL_PERMS}"
  echo "control_package=com.smartisax.controls"
  echo "keep_raw=${KEEP_RAW}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$BASE_SPARSE" "$CONTROL_APK" "$CONTROL_PERMS"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Metadata dump: ${OUT_SPARSE}.lpdump.txt"
