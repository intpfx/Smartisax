#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
AAPT="${AAPT:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
SKIP_LPDUMP="${SKIP_LPDUMP:-1}"

VARIANT="${VARIANT:-v0.37b-textboom-live-system-libs-deodex}"
SOURCE_VARIANT="v0.37a-textboom-live-system-base"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.37a-textboom-live-system-base.sparse.img}"
SOURCE_SPARSE_SHA256="537774d5c54358c893c51d2d8c68e6ab93a6340ddf6b8faba9aba0630cb65bfa"
SOURCE_SYSTEM_B_IMG="${SOURCE_SYSTEM_B_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.37a-textboom-live-system-base.img}"
SOURCE_SYSTEM_B_SHA256="133bf997e3c9b0ae8753262a3e752fcef3de1e84bbc12c3fc2b78d03c2f1ac28"
SOURCE_PRODUCT_B_IMG="${SOURCE_PRODUCT_B_IMG:-${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img}"
SOURCE_PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"
TEXTBOOM_APK="${TEXTBOOM_APK:-${ROOT_DIR}/apks/textboom-live/TextBoom-live-v3.2.2-base.apk}"
TEXTBOOM_APK_SHA256="52df3deb5315baf41b9f5476a122ce9782fa58f74076d1d4a9c060c9c506873c"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
SOURCE_EXTRACT_DIR="${SOURCE_EXTRACT_DIR:-${ROOT_DIR}/hard-rom/work/v0.37a-textboom-live-system-base/source-v0361-retained-slot1}"
FALLBACK_EXTRACT_DIR="${WORK_DIR}/source-v037a-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v037a-super.raw.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
OUT_RAW_FOR_LPDUMP="${WORK_DIR}/candidate-${VARIANT}-super.raw-for-lpdump.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SUPER_SIZE=10737418240
METADATA_SIZE=65536
METADATA_SLOTS=3
GROUP_A_MAX=5364514816
GROUP_B_MAX=5364514816

SYSTEM_A_SIZE=3052314624
PRODUCT_A_SIZE=255815680
VENDOR_A_SIZE=941768704
ODM_A_SIZE=917504
SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_PARTITION_SIZE=171110400
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"
SYSTEM_SELABEL="u:object_r:system_file:s0"

PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a3695d8}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-20 21:30:00 +0800; invalidates package_cache after TextBoom system lib/deodex repair}"

TEXTBOOM_PACKAGE="com.smartisanos.textboom"
TEXTBOOM_DIR="/system/app/TextBoom"
TEXTBOOM_APK_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_LIB_ROOT="/system/app/TextBoom/lib"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"
TEXTBOOM_OAT_DIR="/system/app/TextBoom/oat"
TEXTBOOM_OAT_ARM64_DIR="/system/app/TextBoom/oat/arm64"
TEXTBOOM_ODEX="/system/app/TextBoom/oat/arm64/TextBoom.odex"
TEXTBOOM_VDEX="/system/app/TextBoom/oat/arm64/TextBoom.vdex"
TEXTBOOM_EXPECTED_LIB_COUNT=13
TEXTBOOM_EXTRACTED_LIB_DIR="${WORK_DIR}/textboom-apk-libs/lib/armeabi-v7a"
SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
LAUNCHER_APK="/system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk"
SMARTISAX_APK_PATH="/system/app/SmartisaxShell/SmartisaxShell.apk"

DONOR_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
STOCK_LAUNCHER_SHA256="f3d5af9cf17c56b93462a7d596ed1c7b246a93b32ebc129dbfe14296eaf7ddb6"
SMARTISAX_APK_SHA256="7b1f70ca713260201e49ee3e3cc8ebec35ac3d59e199179a1e048860bb896753"

PURPOSE="TextBoom system-runtime repair on top of live-proven v0.37a: keeps the live v3.2.2 TextBoom APK byte-for-byte in /system/app/TextBoom, adds its extracted 32-bit native libraries under /system/app/TextBoom/lib/arm, removes stale stock TextBoom oat/vdex, and rebuilds system_b FEC so a later separately confirmed PackageManager shadow repair can safely fall back to the system package."

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

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

check_size() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
}

copy_clone_or_plain() {
  local src="$1"
  local dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
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
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE}"
}

fsck_rw() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

verify_dumped_apk() {
  local image="$1"
  local src="$2"
  local expected="$3"
  local dst="$4"
  debugfs_dump "$image" "$src" "$dst"
  [ "$(sha256_one "$dst")" = "$expected" ] || die "dumped APK hash mismatch for ${src}"
  unzip -t "$dst" >/dev/null || die "dumped APK zip test failed for ${src}"
}

verify_textboom_source_apk() {
  local badging="${WORK_DIR}/textboom-source-aapt-badging.txt"
  require_hash "$TEXTBOOM_APK" "$TEXTBOOM_APK_SHA256"
  unzip -t "$TEXTBOOM_APK" >/dev/null
  "$AAPT" dump badging "$TEXTBOOM_APK" > "$badging"
  grep -q "package: name='${TEXTBOOM_PACKAGE}' versionCode='104' versionName='3.2.2'" "$badging" \
    || die "TextBoom source APK package/version contract mismatch"
  grep -q "native-code: 'armeabi-v7a'" "$badging" || die "TextBoom source APK native-code mismatch"
  unzip -Z -1 "$TEXTBOOM_APK" | grep -x 'assets/tt_general_ocr_v1.0.model' >/dev/null \
    || die "TextBoom source APK missing tt_general_ocr_v1.0.model"
  "$SIGCHECK" "$TEXTBOOM_APK" > "${WORK_DIR}/textboom-source-signature-boundary.txt"
  grep -q '^apk_sig_block_magic=absent$' "${WORK_DIR}/textboom-source-signature-boundary.txt" \
    || die "TextBoom source unexpectedly has an APK signing block"
  grep -q '^keytool_status=0$' "${WORK_DIR}/textboom-source-signature-boundary.txt" \
    || die "TextBoom source keytool certificate read failed"
  grep -q '^jarsigner_status=0$' "${WORK_DIR}/textboom-source-signature-boundary.txt" \
    || die "TextBoom source JAR signature verification failed"
}

extract_textboom_libs() {
  local lib_count
  local lib_manifest="${WORK_DIR}/textboom-apk-libs.tsv"

  rm -rf "${WORK_DIR}/textboom-apk-libs"
  mkdir -p "${WORK_DIR}/textboom-apk-libs"
  unzip -q "$TEXTBOOM_APK" 'lib/armeabi-v7a/*.so' -d "${WORK_DIR}/textboom-apk-libs"
  [ -d "$TEXTBOOM_EXTRACTED_LIB_DIR" ] || die "TextBoom APK lib/armeabi-v7a extraction failed"

  lib_count="$(find "$TEXTBOOM_EXTRACTED_LIB_DIR" -maxdepth 1 -type f -name '*.so' | wc -l | tr -d ' ')"
  [ "$lib_count" -eq "$TEXTBOOM_EXPECTED_LIB_COUNT" ] \
    || die "TextBoom native lib count mismatch: actual=${lib_count} expected=${TEXTBOOM_EXPECTED_LIB_COUNT}"

  : > "$lib_manifest"
  find "$TEXTBOOM_EXTRACTED_LIB_DIR" -maxdepth 1 -type f -name '*.so' | sort | while IFS= read -r lib; do
    printf '%s\t%s\t%s\n' "$(basename "$lib")" "$(sha256_one "$lib")" "$lib" >> "$lib_manifest"
  done
}

write_textboom_libs_to_image() {
  local image="$1"
  local cmd_file="${WORK_DIR}/write-textboom-libs.debugfs"
  local lib
  local base

  debugfs_path_exists "$image" "$TEXTBOOM_DIR" || die "missing TextBoom directory"
  ! debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM_DIR" || die "TextBoom arm lib dir already exists; refusing ambiguous lib repair"
  {
    if ! debugfs_path_exists "$image" "$TEXTBOOM_LIB_ROOT"; then
      echo "mkdir ${TEXTBOOM_LIB_ROOT}"
    fi
    echo "set_inode_field ${TEXTBOOM_LIB_ROOT} mode 040755"
    echo "set_inode_field ${TEXTBOOM_LIB_ROOT} uid 0"
    echo "set_inode_field ${TEXTBOOM_LIB_ROOT} gid 0"
    echo "ea_set ${TEXTBOOM_LIB_ROOT} security.selinux ${SYSTEM_SELABEL}"
    echo "mkdir ${TEXTBOOM_LIB_ARM_DIR}"
    echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR} mode 040755"
    echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR} uid 0"
    echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR} gid 0"
    echo "ea_set ${TEXTBOOM_LIB_ARM_DIR} security.selinux ${SYSTEM_SELABEL}"
    find "$TEXTBOOM_EXTRACTED_LIB_DIR" -maxdepth 1 -type f -name '*.so' | sort | while IFS= read -r lib; do
      base="$(basename "$lib")"
      echo "write ${lib} ${TEXTBOOM_LIB_ARM_DIR}/${base}"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR}/${base} mode 0100644"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR}/${base} uid 0"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR}/${base} gid 0"
      echo "ea_set ${TEXTBOOM_LIB_ARM_DIR}/${base} security.selinux ${SYSTEM_SELABEL}"
    done
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  verify_textboom_libs_in_image "$image"
  set_dir_time "$image" "$TEXTBOOM_DIR" "textboom-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
}

verify_textboom_libs_in_image() {
  local image="$1"
  local lib
  local base
  local dumped
  local expected_hash
  local dumped_hash
  local verified=0

  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ROOT" || die "missing TextBoom lib root in image"
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM_DIR" || die "missing TextBoom arm lib dir in image"
  : > "${WORK_DIR}/textboom-image-libs.tsv"
  find "$TEXTBOOM_EXTRACTED_LIB_DIR" -maxdepth 1 -type f -name '*.so' | sort | while IFS= read -r lib; do
    base="$(basename "$lib")"
    dumped="${WORK_DIR}/textboom-dumped-${base}"
    debugfs_path_exists "$image" "${TEXTBOOM_LIB_ARM_DIR}/${base}" || die "missing TextBoom lib in image: ${base}"
    debugfs_dump "$image" "${TEXTBOOM_LIB_ARM_DIR}/${base}" "$dumped"
    expected_hash="$(sha256_one "$lib")"
    dumped_hash="$(sha256_one "$dumped")"
    [ "$dumped_hash" = "$expected_hash" ] || die "TextBoom dumped lib hash mismatch for ${base}"
    printf '%s\t%s\t%s\n' "$base" "$dumped_hash" "${TEXTBOOM_LIB_ARM_DIR}/${base}" >> "${WORK_DIR}/textboom-image-libs.tsv"
    verified=$((verified + 1))
  done

  verified="$(wc -l < "${WORK_DIR}/textboom-image-libs.tsv" | tr -d ' ')"
  [ "$verified" -eq "$TEXTBOOM_EXPECTED_LIB_COUNT" ] \
    || die "verified TextBoom image lib count mismatch: actual=${verified} expected=${TEXTBOOM_EXPECTED_LIB_COUNT}"
}

remove_textboom_oat() {
  local image="$1"
  local cmd_file="${WORK_DIR}/remove-textboom-oat.debugfs"

  debugfs_path_exists "$image" "$TEXTBOOM_APK_PATH" || die "missing TextBoom APK"
  debugfs_path_exists "$image" "$TEXTBOOM_ODEX" || die "missing TextBoom odex"
  debugfs_path_exists "$image" "$TEXTBOOM_VDEX" || die "missing TextBoom vdex"
  {
    echo "rm ${TEXTBOOM_ODEX}"
    echo "rm ${TEXTBOOM_VDEX}"
    echo "rmdir ${TEXTBOOM_OAT_ARM64_DIR}"
    echo "rmdir ${TEXTBOOM_OAT_DIR}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  ! debugfs_path_exists "$image" "$TEXTBOOM_ODEX" || die "TextBoom odex still exists"
  ! debugfs_path_exists "$image" "$TEXTBOOM_VDEX" || die "TextBoom vdex still exists"
  ! debugfs_path_exists "$image" "$TEXTBOOM_OAT_DIR" || die "TextBoom oat dir still exists"
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

prepare_inputs() {
  local part
  local extract_dir="$SOURCE_EXTRACT_DIR"
  require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
  require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  verify_textboom_source_apk
  extract_textboom_libs

  if [ ! -f "${extract_dir}/system_a.img" ] || [ ! -f "${extract_dir}/system_ext_b.img" ]; then
    extract_dir="$FALLBACK_EXTRACT_DIR"
    echo "Retained partitions are missing; extracting selected slot-1 partitions from v0.37a sparse super..."
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    rm -f "$SOURCE_RAW"
    "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
    check_size "source raw super" "$SOURCE_RAW" "$SUPER_SIZE"
    "$LPUNPACK" --slot=1 \
      --partition=system_a \
      --partition=product_a \
      --partition=vendor_a \
      --partition=odm_a \
      --partition=system_ext_b \
      --partition=vendor_b \
      --partition=odm_b \
      "$SOURCE_RAW" "$extract_dir" >/dev/null
    rm -f "$SOURCE_RAW"
  fi
  SOURCE_EXTRACT_DIR="$extract_dir"

  for part in system_a product_a vendor_a odm_a system_ext_b vendor_b odm_b; do
    need_file "${SOURCE_EXTRACT_DIR}/${part}.img"
  done
  check_size system_a "${SOURCE_EXTRACT_DIR}/system_a.img" "$SYSTEM_A_SIZE"
  check_size product_a "${SOURCE_EXTRACT_DIR}/product_a.img" "$PRODUCT_A_SIZE"
  check_size vendor_a "${SOURCE_EXTRACT_DIR}/vendor_a.img" "$VENDOR_A_SIZE"
  check_size odm_a "${SOURCE_EXTRACT_DIR}/odm_a.img" "$ODM_A_SIZE"
  check_size system_ext_b "${SOURCE_EXTRACT_DIR}/system_ext_b.img" "$SYSTEM_EXT_B_SIZE"
  check_size vendor_b "${SOURCE_EXTRACT_DIR}/vendor_b.img" "$VENDOR_B_SIZE"
  check_size odm_b "${SOURCE_EXTRACT_DIR}/odm_b.img" "$ODM_B_SIZE"
  check_size source_system_b "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  check_size source_product_b "$SOURCE_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE"
}

dump_lpdump() {
  if [ "$SKIP_LPDUMP" = "1" ]; then
    echo "lpdump_status=skipped_to_save_disk_space"
    return 0
  fi
  rm -f "$OUT_RAW_FOR_LPDUMP"
  "$SIMG2IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP"
  check_size "candidate raw super for lpdump" "$OUT_RAW_FOR_LPDUMP" "$SUPER_SIZE"
  for slot in 0 1; do
    "$LPDUMP" -s "$slot" "$OUT_RAW_FOR_LPDUMP" > "${OUT_SPARSE}.lpdump-slot${slot}.txt"
  done
  cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"
  rm -f "$OUT_RAW_FOR_LPDUMP"
}

case "${1:-}" in
  "")
    ;;
  -h|--help|help)
    sed -n '1,120p' "$0"
    exit 0
    ;;
  *)
    echo "Usage: $0" >&2
    exit 2
    ;;
esac

need_executable "$LPMAKE"
need_executable "$LPDUMP"
need_executable "$LPUNPACK"
need_executable "$SIMG2IMG"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_executable "$AAPT"
need_file "$AVBTOOL"
need_executable "$SIGCHECK"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$OUT_RAW_FOR_LPDUMP" \
  "${OUT_SPARSE}.lpdump"* "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*-avb-info.txt \
  "${WORK_DIR}"/*aapt*.txt "${WORK_DIR}"/*signature-boundary.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
  echo "data_cleanup_gate=TextBoom updated-system /data/app shadow repair requires separate explicit user confirmation after v0.37b boot verification"
  echo

  echo "## source"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  echo "textboom_source_apk=${TEXTBOOM_APK}"
  prepare_inputs
  echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size "system_b pure ext4" "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  : > "${WORK_DIR}/textboom-system-actions.tsv"

  verify_dumped_apk "$SYSTEM_B_IMG" "$TEXTBOOM_APK_PATH" "$TEXTBOOM_APK_SHA256" "${WORK_DIR}/textboom-before.apk"
  textboom_system_before_sha256="$(sha256_one "${WORK_DIR}/textboom-before.apk")"
  echo "${TEXTBOOM_APK_PATH}|retained_v037a_apk|${textboom_system_before_sha256}" >> "${WORK_DIR}/textboom-system-actions.tsv"
  remove_textboom_oat "$SYSTEM_B_IMG"
  echo "${TEXTBOOM_OAT_DIR}|removed_stale_stock_oat_vdex|ok" >> "${WORK_DIR}/textboom-system-actions.tsv"
  write_textboom_libs_to_image "$SYSTEM_B_IMG"
  echo "${TEXTBOOM_LIB_ARM_DIR}|written_from_textboom_apk|count=${TEXTBOOM_EXPECTED_LIB_COUNT}" >> "${WORK_DIR}/textboom-system-actions.tsv"
  set_dir_time "$SYSTEM_B_IMG" "/system/app" "system-app-parent" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  verify_dumped_apk "$SYSTEM_B_IMG" "$TEXTBOOM_APK_PATH" "$TEXTBOOM_APK_SHA256" "${WORK_DIR}/textboom-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_WEBVIEW_SHA256" "${WORK_DIR}/system-webview-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$STOCK_BROWSERCHROME_SHA256" "${WORK_DIR}/browserchrome-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$LAUNCHER_APK" "$STOCK_LAUNCHER_SHA256" "${WORK_DIR}/launcher-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$SMARTISAX_APK_PATH" "$SMARTISAX_APK_SHA256" "${WORK_DIR}/smartisax-after.apk"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_textboom_libs_in_image "$SYSTEM_B_IMG"
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo "textboom_system_before_sha256=${textboom_system_before_sha256}"
  echo "textboom_source_apk_sha256=${TEXTBOOM_APK_SHA256}"
  echo "textboom_system_lib_count=${TEXTBOOM_EXPECTED_LIB_COUNT}"
  echo "textboom_system_oat=absent"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size "system_b FEC image" "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-v037b-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-v037b-avb-info.txt" || die "system_b lost FEC roots"
  echo "system_b_fec=ok"
  echo

  echo "## rebuild sparse super"
  "$LPMAKE" \
    --metadata-size="$METADATA_SIZE" \
    --metadata-slots="$METADATA_SLOTS" \
    --super-name=super \
    --device="super:${SUPER_SIZE}" \
    --group="qti_dynamic_partitions_a:${GROUP_A_MAX}" \
    --group="qti_dynamic_partitions_b:${GROUP_B_MAX}" \
    --partition="system_a:readonly:${SYSTEM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="product_a:readonly:${PRODUCT_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="vendor_a:readonly:${VENDOR_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="odm_a:readonly:${ODM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="system_b:readonly:${SYSTEM_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="system_ext_b:readonly:${SYSTEM_EXT_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="product_b:readonly:${PRODUCT_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b" \
    --image="system_a=${SOURCE_EXTRACT_DIR}/system_a.img" \
    --image="product_a=${SOURCE_EXTRACT_DIR}/product_a.img" \
    --image="vendor_a=${SOURCE_EXTRACT_DIR}/vendor_a.img" \
    --image="odm_a=${SOURCE_EXTRACT_DIR}/odm_a.img" \
    --image="system_b=${SYSTEM_B_IMG}" \
    --image="system_ext_b=${SOURCE_EXTRACT_DIR}/system_ext_b.img" \
    --image="product_b=${SOURCE_PRODUCT_B_IMG}" \
    --image="vendor_b=${SOURCE_EXTRACT_DIR}/vendor_b.img" \
    --image="odm_b=${SOURCE_EXTRACT_DIR}/odm_b.img" \
    --block-size=4096 \
    --sparse \
    --output="$OUT_SPARSE"
  dump_lpdump
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=$(sha256_one "$OUT_SPARSE")"
  echo

  system_hash="$(sha256_one "$SYSTEM_B_IMG")"
  product_hash="$(sha256_one "$SOURCE_PRODUCT_B_IMG")"
  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
    echo "data_cleanup_gate=TextBoom updated-system /data/app shadow repair requires separate explicit user confirmation after v0.37b boot verification"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse_super=${SOURCE_SPARSE}"
    echo "source_sparse_super_sha256=${SOURCE_SPARSE_SHA256}"
    echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
    echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
    echo "source_product_b_sha256=${SOURCE_PRODUCT_B_SHA256}"
    echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
    echo "patched_partitions=system_b"
    echo "retained_partitions_from_source=system_a,product_a,vendor_a,odm_a,system_ext_b,product_b,vendor_b,odm_b"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "product_b_image=${SOURCE_PRODUCT_B_IMG}"
    echo "product_b_sha256=${product_hash}"
    echo "textboom_apk=${TEXTBOOM_APK}"
    echo "textboom_apk_sha256=${TEXTBOOM_APK_SHA256}"
    echo "textboom_package=${TEXTBOOM_PACKAGE}"
    echo "textboom_system_path=${TEXTBOOM_APK_PATH}"
    echo "textboom_manifest_edit=no"
    echo "textboom_version_code=104"
    echo "textboom_version_name=3.2.2"
    echo "textboom_system_before_sha256=${textboom_system_before_sha256}"
    echo "textboom_signature_boundary=v1_jar_original_verified_no_v2_block"
    echo "textboom_ocr_backend_change=no"
    echo "textboom_system_lib_dir=${TEXTBOOM_LIB_ARM_DIR}"
    echo "textboom_system_lib_count=${TEXTBOOM_EXPECTED_LIB_COUNT}"
    echo "textboom_system_oat=absent"
    echo "textboom_data_shadow_expected=yes_until_explicit_shadow_repair"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "system_webview_apk_sha256=${DONOR_WEBVIEW_SHA256}"
    echo "browserchrome_apk_sha256=${STOCK_BROWSERCHROME_SHA256}"
    echo "launcher_apk_sha256=${STOCK_LAUNCHER_SHA256}"
    echo "smartisax_apk_sha256=${SMARTISAX_APK_SHA256}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "lpdump_status=$([ "$SKIP_LPDUMP" = "1" ] && echo skipped_to_save_disk_space || echo generated)"
    echo "fec_status=system_b_generated_roots_2_product_b_retained_from_v0352_roots_2"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# textboom_system_actions"
    cat "${WORK_DIR}/textboom-system-actions.tsv"
    echo
    echo "# textboom_apk_libs"
    cat "${WORK_DIR}/textboom-apk-libs.tsv"
    echo
    echo "# textboom_image_libs"
    cat "${WORK_DIR}/textboom-image-libs.tsv"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_PRODUCT_B_IMG" "$TEXTBOOM_APK"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V037B_TEXTBOOM_LIVE_SYSTEM_LIBS_DEODEX"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Product image retained: ${SOURCE_PRODUCT_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
