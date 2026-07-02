#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SMARTISAX_BUILDER="${SMARTISAX_BUILDER:-${ROOT_DIR}/tools/r2-build-smartisax-shell.sh}"
SIDEBAR_APK_BUILDER="${SIDEBAR_APK_BUILDER:-${ROOT_DIR}/tools/r2-build-sidebar-onestep-a11y-apk.sh}"
SMARTISAX_ROM_BUILDER="${SMARTISAX_ROM_BUILDER:-${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh}"

VARIANT="v0.agent0.10-finish-target-verify"
SOURCE_VARIANT="v0.agent0.9-worker-a11y-targets"
SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.agent0.9-worker-a11y-targets.img}"
SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-65867365776dbf8d4c73c1ab26a16f8e9d8bf5e47758909b811b698586cf589f}"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.agent0.9-worker-a11y-targets.sparse.img}"
SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-648320622194a61fa0f4c4b9d30f5d395c6f20928e5c53bd98896c4a705a6cfc}"
WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"

SMARTISAX_APK="${SMARTISAX_APK:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell.apk}"
PRIVAPP_XML="${PRIVAPP_XML:-${ROOT_DIR}/apps/SmartisaxShell/privapp-permissions-com.smartisax.browser.xml}"
SIDEBAR_APK="${SIDEBAR_APK:-${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.sidebar-onestep-a11y-v2cert.apk}"
SIDEBAR_APK_MANIFEST="${SIDEBAR_APK_MANIFEST:-${ROOT_DIR}/hard-rom/build/apk/sidebar-onestep-a11y-apk-manifest.tsv}"

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
SYSTEM_B_EXTENT="system_b=8306688:6217336"
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"
SYSTEM_SELABEL="u:object_r:system_file:s0"
SIDEBAR_IMAGE_PATH="/system/priv-app/Sidebar/Sidebar.apk"
NEW_SMARTISAX_APK_PATH="/system/priv-app/SmartisaxShell/SmartisaxShell.apk"
PRIVAPP_XML_PATH="/system/etc/permissions/privapp-permissions-com.smartisax.browser.xml"
SERVICES_JAR_PATH="/system/framework/services.jar"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a4ae1f0}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-07-06 07:00:00 +0800; invalidates Smartisax package scan cache after Agent 0.7.10 finish target-aware verification update}"

PURPOSE="Agent v0.10 repair on top of live v0.agent0.9: make finish verification target-aware for Settings-open goals while reusing the v0.8 Sidebar app-node patch."
RESULT_NAME="PASS_BUILD_V0AGENT010_FINISH_TARGET_VERIFY"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.agent0.10-finish-target-verify.sh

Build the v0.agent0.10 Agent diagnostic repair on top of live-proven
v0.agent0.9-worker-a11y-targets. This updates SmartisaxShell and preserves the
already-built v0.agent0.8 Sidebar classes.dex-only patch at:

  /system/priv-app/Sidebar/Sidebar.apk

so dynamic top app strip items stay exposed as clickable Accessibility nodes.
The script rebuilds system_b AVB/FEC and patches it into the v0.agent0.9 sparse super. It
does not flash, reboot, erase misc, or touch /data.
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

verify_image_file_hash() {
  local image="$1" path="$2" expected="$3" label="$4" out actual
  out="${WORK_DIR}/${label}"
  debugfs_path_exists "$image" "$path" || die "missing image path: ${path}"
  debugfs_dump "$image" "$path" "$out"
  actual="$(sha256_one "$out")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

replace_file_direct_with_stock_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped.apk"
  local stock_dump="${WORK_DIR}/${tag}-stock-before.apk"
  local dir src_hash dumped_hash

  dir="$(dirname "$dst")"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination directory: ${dst}"
  debugfs_path_exists "$image" "$dst" || die "missing stock destination file: ${dst}"
  debugfs_dump "$image" "$dst" "$stock_dump"
  unzip -t "$stock_dump" >/dev/null || die "stock APK zip test failed before replace for ${dst}"

  {
    echo "rm ${dst}"
    echo "write ${src} ${dst}"
    set_inode_common "$dst" "0100644"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$dst" || die "missing replaced file: ${dst}"
  debugfs_dump "$image" "$dst" "$dumped"

  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "dumped APK zip test failed before fsck for ${dst}"

  printf '%s\t%s\tsha256=%s\tstock_dump=%s\tstock_sha256=%s\n' "$dst" "$src" "$src_hash" "$stock_dump" "$(sha256_one "$stock_dump")"
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
need_executable "$SMARTISAX_BUILDER"
need_executable "$SIDEBAR_APK_BUILDER"
need_executable "$SMARTISAX_ROM_BUILDER"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
require_hash "$SOURCE_SYSTEM_B" "$SOURCE_SYSTEM_B_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "boundary=offline build only; no adb, no fastboot, no flash, no reboot, no /data mutation"
  echo

  echo "## build SmartisaxShell APK"
  "$SMARTISAX_BUILDER"
  need_file "$SMARTISAX_APK"
  smartisax_apk_sha256="$(sha256_one "$SMARTISAX_APK")"
  privapp_xml_sha256="$(sha256_one "$PRIVAPP_XML")"
  need_file "$WEBRTC_ARM64_SO"
  need_file "$WEBRTC_ARM_SO"
  webrtc_arm64_so_sha256="$(sha256_one "$WEBRTC_ARM64_SO")"
  webrtc_arm_so_sha256="$(sha256_one "$WEBRTC_ARM_SO")"
  echo "smartisax_apk=${SMARTISAX_APK}"
  echo "smartisax_apk_sha256=${smartisax_apk_sha256}"
  echo

  echo "## reuse Sidebar Agent-friendly One Step APK"
  need_file "$SIDEBAR_APK"
  need_file "$SIDEBAR_APK_MANIFEST"
  sidebar_apk_sha256="$(sha256_one "$SIDEBAR_APK")"
  echo "sidebar_apk=${SIDEBAR_APK}"
  echo "sidebar_apk_sha256=${sidebar_apk_sha256}"
  echo

  echo "## build Smartisax system_b stage"
  VARIANT="$VARIANT" \
  SOURCE_VARIANT="$SOURCE_VARIANT" \
  SOURCE_SPARSE="$SOURCE_SPARSE" \
  SOURCE_SPARSE_SHA256="$SOURCE_SPARSE_SHA256" \
  SOURCE_SYSTEM_B="$SOURCE_SYSTEM_B" \
  SOURCE_SYSTEM_B_SHA256="$SOURCE_SYSTEM_B_SHA256" \
  WEBRTC_ARM64_SO="$WEBRTC_ARM64_SO" \
  WEBRTC_ARM_SO="$WEBRTC_ARM_SO" \
  EXPECTED_SERVICES_JAR_SHA256="$EXPECTED_SERVICES_JAR_SHA256" \
  PACKAGE_DIR_MTIME_HEX="$PACKAGE_DIR_MTIME_HEX" \
  PACKAGE_DIR_MTIME_NOTE="$PACKAGE_DIR_MTIME_NOTE" \
  PURPOSE="$PURPOSE" \
  RESULT_NAME="${RESULT_NAME}_SMARTISAX_STAGE" \
    "$SMARTISAX_ROM_BUILDER"
  check_size system_b_stage_with_fec "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  system_hash_smartisax_stage="$(sha256_one "$SYSTEM_B_IMG")"
  echo "system_b_smartisax_stage_sha256=${system_hash_smartisax_stage}"
  echo

  echo "## patch Sidebar APK into staged system_b"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before_sidebar="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  verify_image_file_hash "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "$smartisax_apk_sha256" "smartisax-priv-app-before-sidebar.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "$privapp_xml_sha256" "privapp-permissions-before-sidebar.xml"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$EXPECTED_SERVICES_JAR_SHA256" "services-jar-before-sidebar.jar"

  : > "${WORK_DIR}/sidebar-replacements.tsv"
  replace_file_direct_with_stock_dump "$SYSTEM_B_IMG" "$SIDEBAR_APK" "$SIDEBAR_IMAGE_PATH" "sidebar-onestep-a11y" >> "${WORK_DIR}/sidebar-replacements.tsv"
  : > "${WORK_DIR}/sidebar-package-dir-mtime-bumps.tsv"
  set_dir_time "$SYSTEM_B_IMG" "/system/priv-app/Sidebar" "sidebar-package-dir" >> "${WORK_DIR}/sidebar-package-dir-mtime-bumps.tsv"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "$smartisax_apk_sha256" "smartisax-priv-app-after-sidebar.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "$privapp_xml_sha256" "privapp-permissions-after-sidebar.xml"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SIDEBAR_IMAGE_PATH" "$sidebar_apk_sha256" "sidebar-onestep-a11y-after-fsck.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$EXPECTED_SERVICES_JAR_SHA256" "services-jar-after-sidebar.jar"
  system_free_blocks_after_sidebar="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_free_blocks_before_sidebar=${system_free_blocks_before_sidebar}"
  echo "system_free_blocks_after_sidebar=${system_free_blocks_after_sidebar}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size system_b_fec_image "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b AVB original size mismatch"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b lost FEC roots"
  echo "system_b_fec=ok"
  echo

  final_system_hash="$(sha256_one "$SYSTEM_B_IMG")"
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
    echo "system_b_sha256=${final_system_hash}"
    echo "system_b_smartisax_stage_sha256=${system_hash_smartisax_stage}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "smartisax_apk=${SMARTISAX_APK}"
    echo "smartisax_apk_sha256=${smartisax_apk_sha256}"
    echo "privapp_xml=${PRIVAPP_XML}"
    echo "privapp_xml_sha256=${privapp_xml_sha256}"
    echo "webrtc_arm64_so=${WEBRTC_ARM64_SO}"
    echo "webrtc_arm64_so_path=/system/priv-app/SmartisaxShell/lib/arm64/libjingle_peerconnection_so.so"
    echo "webrtc_arm64_so_sha256=${webrtc_arm64_so_sha256}"
    echo "webrtc_arm_so=${WEBRTC_ARM_SO}"
    echo "webrtc_arm_so_path=/system/priv-app/SmartisaxShell/lib/arm/libjingle_peerconnection_so.so"
    echo "webrtc_arm_so_sha256=${webrtc_arm_so_sha256}"
    echo "sidebar_apk=${SIDEBAR_APK}"
    echo "sidebar_apk_sha256=${sidebar_apk_sha256}"
    echo "sidebar_apk_manifest=${SIDEBAR_APK_MANIFEST}"
    echo "sidebar_image_path=${SIDEBAR_IMAGE_PATH}"
    echo "services_jar_path=${SERVICES_JAR_PATH}"
    echo "services_jar_final_sha256=${EXPECTED_SERVICES_JAR_SHA256}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "fec_status=system_b_generated_roots_2"
    echo "system_free_blocks_before_sidebar=${system_free_blocks_before_sidebar}"
    echo "system_free_blocks_after_sidebar=${system_free_blocks_after_sidebar}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# sidebar_replacements"
    cat "${WORK_DIR}/sidebar-replacements.tsv"
    echo
    echo "# sidebar_package_dir_mtime_bumps"
    cat "${WORK_DIR}/sidebar-package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$SYSTEM_B_IMG" "$SMARTISAX_APK" "$PRIVAPP_XML" "$SIDEBAR_APK" "$SOURCE_SPARSE"
  } > "$SYSTEM_MANIFEST"

  echo "system_b_image=${SYSTEM_B_IMG}"
  echo "system_b_sha256=${final_system_hash}"
  echo

  echo "## sparse patch"
  rm -f "$OUT_SPARSE" "${OUT_SPARSE}.SHA256SUMS.txt"
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
    echo "system_b_sha256=${final_system_hash}"
    echo "super_sparse_image=${OUT_SPARSE}"
    echo "super_sparse_sha256=${sparse_hash}"
    echo "smartisax_apk_sha256=${smartisax_apk_sha256}"
    echo "webrtc_arm64_so_path=/system/priv-app/SmartisaxShell/lib/arm64/libjingle_peerconnection_so.so"
    echo "webrtc_arm64_so_sha256=${webrtc_arm64_so_sha256}"
    echo "webrtc_arm_so_path=/system/priv-app/SmartisaxShell/lib/arm/libjingle_peerconnection_so.so"
    echo "webrtc_arm_so_sha256=${webrtc_arm_so_sha256}"
    echo "sidebar_apk_sha256=${sidebar_apk_sha256}"
    echo "sidebar_image_path=${SIDEBAR_IMAGE_PATH}"
    echo "services_jar_final_sha256=${EXPECTED_SERVICES_JAR_SHA256}"
    echo "patched_partitions=system_b"
    echo "system_manifest=${SYSTEM_MANIFEST}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SMARTISAX_APK" "$SIDEBAR_APK" "$PRIVAPP_XML" "$SOURCE_SPARSE"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

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
