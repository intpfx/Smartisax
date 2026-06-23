#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="${VARIANT:-v0.wadb1-smartisax-priv-wireless-adb}"
SOURCE_VARIANT="v0.usb2-physical-cdrom-iso-delete"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.usb2-physical-cdrom-iso-delete.sparse.img}"
SOURCE_SPARSE_SHA256="239b95b7ebbb467858c40b8e40a268cb1d83be145f5e9cddd8e2dc66a78153d0"
SOURCE_SYSTEM_B_SHA256="fd88c39e3716dcd7f6d018b651ec69c3e2457995afb78a6bc6c5ae5a95c513b2"

SMARTISAX_APK="${SMARTISAX_APK:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell.apk}"
PRIVAPP_XML="${PRIVAPP_XML:-${ROOT_DIR}/apps/SmartisaxShell/privapp-permissions-com.smartisax.browser.xml}"
OLD_SMARTISAX_DIR="/system/app/SmartisaxShell"
NEW_SMARTISAX_DIR="/system/priv-app/SmartisaxShell"
NEW_SMARTISAX_APK_PATH="${NEW_SMARTISAX_DIR}/SmartisaxShell.apk"
PRIVAPP_XML_PATH="/system/etc/permissions/privapp-permissions-com.smartisax.browser.xml"

WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_MANIFEST="${OUT_DIR}/system-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"
SYSTEM_SELABEL="u:object_r:system_file:s0"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a390098}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-22 17:30:00 +0800; invalidates package scan/cache after Smartisax moves from system app to priv-app}"

PURPOSE="Move Smartisax from /system/app to /system/priv-app and install a privapp permission whitelist so the Smartisax Shell can expose the wireless ADB control entry."
RESULT_NAME="PASS_BUILD_V0WADB1_SMARTISAX_PRIV_WIRELESS_ADB"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.wadb1-smartisax-priv-wireless-adb.sh

Builds a system_b-only candidate on top of live-proven v0.usb2. It removes the
old /system/app/SmartisaxShell package path, installs the rebuilt Smartisax APK
under /system/priv-app/SmartisaxShell, adds its privapp permissions XML, rebuilds
system_b AVB/FEC roots=2, and patches that system_b image into the v0.usb2
sparse super. It does not touch a live device.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

check_size() {
  local label="$1" path="$2" expected="$3" actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
}

debugfs_path_exists() {
  local image="$1" path="$2" output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1" src="$2" dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

debugfs_stat_value() {
  local image="$1" key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

debugfs_rm_tree() {
  local image="$1" path="$2"

  if ! debugfs_path_exists "$image" "$path"; then
    return 1
  fi

  while IFS=$'\t' read -r mode name; do
    [ -n "${name:-}" ] || continue
    local child="${path}/${name}"
    if [[ "$mode" == 04* ]]; then
      debugfs_rm_tree "$image" "$child" || true
    else
      "$DEBUGFS" -w -R "rm ${child}" "$image" >/dev/null 2>&1 || true
    fi
  done < <("$DEBUGFS" -R "ls -p ${path}" "$image" 2>/dev/null | \
    awk -F/ '$0 ~ /^\// && $6 != "." && $6 != ".." { print $3 "\t" $6 }')

  "$DEBUGFS" -w -R "rmdir ${path}" "$image" >/dev/null 2>&1 || true
  return 0
}

fsck_rw() {
  local image="$1" status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

set_inode_common() {
  local path="$1" mode="$2"
  cat <<EOF
set_inode_field ${path} mode ${mode}
set_inode_field ${path} uid 0
set_inode_field ${path} gid 0
ea_set ${path} security.selinux ${SYSTEM_SELABEL}
set_inode_field ${path} ctime ${PACKAGE_DIR_MTIME_HEX}
set_inode_field ${path} atime ${PACKAGE_DIR_MTIME_HEX}
set_inode_field ${path} mtime ${PACKAGE_DIR_MTIME_HEX}
set_inode_field ${path} crtime ${PACKAGE_DIR_MTIME_HEX}
EOF
}

set_dir_time() {
  local image="$1"
  local dir="$2"
  local tag="$3"
  local cmd_file="${WORK_DIR}/mtime-${tag}.debugfs"
  debugfs_path_exists "$image" "$dir" || die "missing directory: ${dir}"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  printf '%s\tmtime_hex=%s\t%s\n' "$dir" "$PACKAGE_DIR_MTIME_HEX" "$PACKAGE_DIR_MTIME_NOTE"
}

install_smartisax_privapp() {
  local image="$1" cmd_file="${WORK_DIR}/install-smartisax-privapp.debugfs"

  debugfs_path_exists "$image" "/system/app" || die "missing /system/app"
  debugfs_path_exists "$image" "/system/priv-app" || die "missing /system/priv-app"
  debugfs_path_exists "$image" "/system/etc/permissions" || die "missing /system/etc/permissions"
  debugfs_path_exists "$image" "$OLD_SMARTISAX_DIR" || die "missing old Smartisax path: ${OLD_SMARTISAX_DIR}"
  if debugfs_path_exists "$image" "$NEW_SMARTISAX_DIR"; then
    die "new Smartisax priv-app path already exists: ${NEW_SMARTISAX_DIR}"
  fi
  if debugfs_path_exists "$image" "$PRIVAPP_XML_PATH"; then
    die "Smartisax privapp permission XML already exists: ${PRIVAPP_XML_PATH}"
  fi

  debugfs_dump "$image" "${OLD_SMARTISAX_DIR}/SmartisaxShell.apk" "${WORK_DIR}/smartisax-old-system-app.apk"
  debugfs_rm_tree "$image" "$OLD_SMARTISAX_DIR" || die "failed to remove old Smartisax system-app path"

  {
    echo "mkdir ${NEW_SMARTISAX_DIR}"
    set_inode_common "$NEW_SMARTISAX_DIR" "040755"
    echo "write ${SMARTISAX_APK} ${NEW_SMARTISAX_APK_PATH}"
    set_inode_common "$NEW_SMARTISAX_APK_PATH" "0100644"
    echo "write ${PRIVAPP_XML} ${PRIVAPP_XML_PATH}"
    set_inode_common "$PRIVAPP_XML_PATH" "0100644"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$NEW_SMARTISAX_APK_PATH" || die "missing new Smartisax APK"
  debugfs_path_exists "$image" "$PRIVAPP_XML_PATH" || die "missing Smartisax privapp XML"
  ! debugfs_path_exists "$image" "$OLD_SMARTISAX_DIR" || die "old Smartisax system-app path still exists"
}

verify_image_file_hash() {
  local image="$1" path="$2" expected="$3" label="$4" out actual
  out="${WORK_DIR}/${label}"
  debugfs_path_exists "$image" "$path" || die "missing image path: ${path}"
  debugfs_dump "$image" "$path" "$out"
  actual="$(sha256_one "$out")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

rebuild_system_footer() {
  local image="$1"
  PATH="$(dirname "$FEC"):${PATH}" python3 "$AVBTOOL" add_hashtree_footer \
    --image "$image" \
    --partition_size "$SYSTEM_B_PARTITION_SIZE" \
    --partition_name system \
    --hash_algorithm sha1 \
    --salt "$SYSTEM_B_SALT" \
    --block_size 4096 \
    --fec_num_roots 2 \
    --prop com.android.build.system.fingerprint:qti/aries/aries:11/RKQ1.201217.002/1658135499:user/dev-keys \
    --prop com.android.build.system.os_version:11 \
    --prop com.android.build.system.security_patch:2022-06-10 \
    --prop com.android.build.system.security_patch:2022-06-10
}

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_file "$AVBTOOL"
need_file "$SPARSE_TOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
need_file "$SMARTISAX_APK"
need_file "$PRIVAPP_XML"
unzip -t "$SMARTISAX_APK" >/dev/null

SMARTISAX_APK_SHA256="$(sha256_one "$SMARTISAX_APK")"
PRIVAPP_XML_SHA256="$(sha256_one "$PRIVAPP_XML")"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$SYSTEM_MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.xml "${WORK_DIR}"/*.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "boundary=offline build only; no adb, no fastboot, no flash, no reboot, no /data mutation"
  echo

  echo "## inputs"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
  echo "source_system_b_extent=${SYSTEM_B_EXTENT}"
  echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
  echo "smartisax_apk=${SMARTISAX_APK}"
  echo "smartisax_apk_sha256=${SMARTISAX_APK_SHA256}"
  echo "privapp_xml=${PRIVAPP_XML}"
  echo "privapp_xml_sha256=${PRIVAPP_XML_SHA256}"
  echo

  echo "## extract system_b"
  "$SPARSE_TOOL" \
    --source-sparse "$SOURCE_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --extract-image "system_b=${SYSTEM_B_IMG}" >/dev/null
  [ "$(sha256_one "$SYSTEM_B_IMG")" = "$SOURCE_SYSTEM_B_SHA256" ] || die "extracted source system_b hash mismatch"
  check_size system_b_source_partition "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  echo "source_system_b_extract=ok"
  echo

  echo "## patch system_b"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  old_smartisax_sha256="$(sha256_one "${WORK_DIR}/smartisax-old-system-app.apk" 2>/dev/null || true)"
  install_smartisax_privapp "$SYSTEM_B_IMG"
  old_smartisax_sha256="$(sha256_one "${WORK_DIR}/smartisax-old-system-app.apk")"
  {
    set_dir_time "$SYSTEM_B_IMG" "/system/app" "system-app-parent"
    set_dir_time "$SYSTEM_B_IMG" "/system/priv-app" "system-priv-app-parent"
    set_dir_time "$SYSTEM_B_IMG" "/system/etc/permissions" "system-permissions-parent"
  } > "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  verify_image_file_hash "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "$SMARTISAX_APK_SHA256" "smartisax-priv-app.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "$PRIVAPP_XML_SHA256" "privapp-permissions-com.smartisax.browser.xml"
  ! debugfs_path_exists "$SYSTEM_B_IMG" "$OLD_SMARTISAX_DIR" || die "old Smartisax system-app path still exists before fsck"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "$SMARTISAX_APK_SHA256" "smartisax-priv-app-after-fsck.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "$PRIVAPP_XML_SHA256" "privapp-permissions-com.smartisax.browser-after-fsck.xml"
  ! debugfs_path_exists "$SYSTEM_B_IMG" "$OLD_SMARTISAX_DIR" || die "old Smartisax system-app path reappeared after fsck"
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "old_smartisax_system_app_sha256=${old_smartisax_sha256}"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size system_b_fec_image "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b AVB original size mismatch"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b lost FEC roots"
  echo "system_b_fec=ok"
  echo

  system_hash="$(sha256_one "$SYSTEM_B_IMG")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "boundary=offline system_b build only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse=${SOURCE_SPARSE}"
    echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
    echo "source_system_b_extent=${SYSTEM_B_EXTENT}"
    echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "smartisax_old_path=${OLD_SMARTISAX_DIR}"
    echo "smartisax_new_path=${NEW_SMARTISAX_APK_PATH}"
    echo "smartisax_apk=${SMARTISAX_APK}"
    echo "smartisax_apk_sha256=${SMARTISAX_APK_SHA256}"
    echo "smartisax_old_system_app_sha256=${old_smartisax_sha256}"
    echo "privapp_xml_path=${PRIVAPP_XML_PATH}"
    echo "privapp_xml=${PRIVAPP_XML}"
    echo "privapp_xml_sha256=${PRIVAPP_XML_SHA256}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "patched_partitions=system_b"
    echo "fec_status=system_b_generated_roots_2"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$SYSTEM_B_IMG" "$SMARTISAX_APK" "$PRIVAPP_XML" "$SOURCE_SPARSE"
  } > "$SYSTEM_MANIFEST"

  echo "system_b_image=${SYSTEM_B_IMG}"
  echo "system_b_sha256=${system_hash}"
  echo

  echo "## sparse patch"
  "$SPARSE_TOOL" \
    --source-sparse "$SOURCE_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --out "$OUT_SPARSE" \
    --image "system_b=${SYSTEM_B_IMG}" \
    --variant "$VARIANT"
  "$SPARSE_TOOL" \
    --source-sparse "$OUT_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --verify-image "system_b=${SYSTEM_B_IMG}"

  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "boundary=offline sparse build only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse=${SOURCE_SPARSE}"
    echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
    echo "system_b_extent=${SYSTEM_B_EXTENT}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "super_sparse_image=${OUT_SPARSE}"
    echo "super_sparse_sha256=${sparse_hash}"
    echo "sparse_tool_manifest=${OUT_SPARSE}.SHA256SUMS.txt"
    echo "smartisax_new_path=${NEW_SMARTISAX_APK_PATH}"
    echo "smartisax_apk_sha256=${SMARTISAX_APK_SHA256}"
    echo "privapp_xml_path=${PRIVAPP_XML_PATH}"
    echo "privapp_xml_sha256=${PRIVAPP_XML_SHA256}"
    echo "patched_partitions=system_b"
    echo "system_manifest=${SYSTEM_MANIFEST}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SMARTISAX_APK" "$PRIVAPP_XML" "$SOURCE_SPARSE"
  } > "$MANIFEST"

  echo "super_sparse_image=${OUT_SPARSE}"
  echo "super_sparse_sha256=${sparse_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} 2>&1 | tee "$REPORT"

echo "Sparse super: $OUT_SPARSE"
echo "System image: $SYSTEM_B_IMG"
echo "Manifest: $MANIFEST"
echo "System manifest: $SYSTEM_MANIFEST"
echo "Report: $REPORT"
echo "Flash gate: explicit user confirmation required."
