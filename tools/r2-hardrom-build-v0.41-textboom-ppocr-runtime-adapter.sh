#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
TEXTBOOM_APK_BUILDER="${TEXTBOOM_APK_BUILDER:-${ROOT_DIR}/tools/r2-build-textboom-ppocr-runtime-adapter-apk.sh}"
SKIP_LPDUMP="${SKIP_LPDUMP:-1}"

VARIANT="${VARIANT:-v0.41-textboom-ppocr-runtime-adapter}"
SOURCE_VARIANT="v0.39-sidebar-font-ocr-deleted"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.39-sidebar-font-ocr-deleted.sparse.img}"
SOURCE_SPARSE_SHA256="a3672c3d32e7acedaf83051b289df86c729e91eb3e24f4e958b3fa4b42560f79"
SOURCE_SYSTEM_B_IMG="${SOURCE_SYSTEM_B_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.39-sidebar-font-ocr-deleted.img}"
SOURCE_SYSTEM_B_SHA256="f5d921a76ca3f91c883074077d1e6a1720321eaa9bdcac9f444156935b4ec898"
SOURCE_PRODUCT_B_IMG="${SOURCE_PRODUCT_B_IMG:-${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img}"
SOURCE_PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"
SOURCE_EXTRACT_DIR="${SOURCE_EXTRACT_DIR:-${ROOT_DIR}/hard-rom/work/v0.37a-textboom-live-system-base/source-v0361-retained-slot1}"

TEXTBOOM_ADAPTER_APK="${TEXTBOOM_ADAPTER_APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-runtime-adapter.apk}"
TEXTBOOM_ADAPTER_APK_SHA256="6f0d3964234f57c059f70446ba330e9dcb8a3741ae9ce97dfdc8d6fe7ce880a6"
TEXTBOOM_SYSTEM_BEFORE_SHA256="52df3deb5315baf41b9f5476a122ce9782fa58f74076d1d4a9c060c9c506873c"
TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_DIR="/system/app/TextBoom"
TEXTBOOM_LIB_ROOT="/system/app/TextBoom/lib"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"
TEXTBOOM_LIB_ARM64_DIR="/system/app/TextBoom/lib/arm64"
TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR="${TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}/textboom-runtime-apk-libs/lib/arm64-v8a}"
TEXTBOOM_RUNTIME_EXPECTED_LIB_COUNT=4

SIDEBAR_PATH="/system/priv-app/Sidebar/Sidebar.apk"
SIDEBAR_APK_SHA256="9a249c3398fa92017294f2b9ff1885d98992404e9cf4a52b848cfce5741ca503"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
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
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-$(printf '0x%x' "$(date +%s)")}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-generated at build time to invalidate PackageCacher for TextBoom}"

SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
SYSTEM_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
SMARTISAX_APK="/system/app/SmartisaxShell/SmartisaxShell.apk"
SMARTISAX_SHA256="7b1f70ca713260201e49ee3e3cc8ebec35ac3d59e199179a1e048860bb896753"

PURPOSE="Switch TextBoom image OCR entrypoints to a LocalPpOcrApi backed by local PP-OCRv6 small ONNX Runtime/OpenCV runtime on top of live-stable v0.39, preserving Sidebar font-OCR deletion, M150 WebView, Smartisax shell, legacy CsOcr fallback code, TextBoom lib/arm, and system_b AVB/FEC."

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

copy_clone_or_plain() {
  local src="$1" dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
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

replace_file_in_image() {
  local image="$1" src="$2" dst="$3" tag="$4"
  local dir base temp_path held_path cmd_file dumped src_hash dumped_hash
  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  temp_path="${dir}/.${base}.smartisax-${VARIANT}-tmp"
  held_path="${dir}/.${base}.smartisax-${VARIANT}-held"
  cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  dumped="${WORK_DIR}/${tag}-dumped.apk"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination dir: $dir"
  debugfs_path_exists "$image" "$dst" || die "missing destination file: $dst"
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
  debugfs_path_exists "$image" "$dst" || die "missing replaced file: $dst"
  debugfs_path_exists "$image" "$held_path" || die "missing held file: $held_path"

  debugfs_dump "$image" "$dst" "$dumped"
  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "dumped APK zip test failed for ${dst}"
  echo "${dst}|${src}|${src_hash}|${dumped}|${held_path}"
}

bump_package_dir_time() {
  local image="$1" dir="$2" tag="$3" cmd_file
  cmd_file="${WORK_DIR}/bump-dir-time-${tag}.debugfs"
  debugfs_path_exists "$image" "$dir" || die "missing package dir: $dir"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE}"
}

verify_apk_hash() {
  local image="$1" path="$2" expected="$3" label="$4" out
  out="${WORK_DIR}/${label}.apk"
  debugfs_dump "$image" "$path" "$out"
  [ "$(sha256_one "$out")" = "$expected" ] || die "${label} hash mismatch"
  unzip -t "$out" >/dev/null || die "${label} zip test failed"
  printf '%s\tsha256=%s\t%s\n' "$label" "$expected" "$path"
}

extract_textboom_runtime_libs() {
  local lib_count lib_manifest
  lib_manifest="${WORK_DIR}/textboom-runtime-apk-libs.tsv"
  rm -rf "${WORK_DIR}/textboom-runtime-apk-libs"
  mkdir -p "${WORK_DIR}/textboom-runtime-apk-libs"
  unzip -q "$TEXTBOOM_ADAPTER_APK" 'lib/arm64-v8a/*.so' -d "${WORK_DIR}/textboom-runtime-apk-libs"
  [ -d "$TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR" ] || die "TextBoom runtime APK lib/arm64-v8a extraction failed"

  lib_count="$(find "$TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR" -maxdepth 1 -type f -name '*.so' | wc -l | tr -d ' ')"
  [ "$lib_count" -eq "$TEXTBOOM_RUNTIME_EXPECTED_LIB_COUNT" ] \
    || die "TextBoom runtime native lib count mismatch: actual=${lib_count} expected=${TEXTBOOM_RUNTIME_EXPECTED_LIB_COUNT}"

  : > "$lib_manifest"
  find "$TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR" -maxdepth 1 -type f -name '*.so' | sort | while IFS= read -r lib; do
    printf '%s\t%s\t%s\n' "$(basename "$lib")" "$(sha256_one "$lib")" "$lib" >> "$lib_manifest"
  done
}

verify_textboom_runtime_libs_in_image() {
  local image="$1"
  local lib base dumped expected_hash dumped_hash verified

  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ROOT" || die "missing TextBoom lib root in image"
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM64_DIR" || die "missing TextBoom arm64 lib dir in image"
  : > "${WORK_DIR}/textboom-runtime-image-libs.tsv"
  find "$TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR" -maxdepth 1 -type f -name '*.so' | sort | while IFS= read -r lib; do
    base="$(basename "$lib")"
    dumped="${WORK_DIR}/textboom-runtime-dumped-${base}"
    debugfs_path_exists "$image" "${TEXTBOOM_LIB_ARM64_DIR}/${base}" || die "missing TextBoom runtime lib in image: ${base}"
    debugfs_dump "$image" "${TEXTBOOM_LIB_ARM64_DIR}/${base}" "$dumped"
    expected_hash="$(sha256_one "$lib")"
    dumped_hash="$(sha256_one "$dumped")"
    [ "$dumped_hash" = "$expected_hash" ] || die "TextBoom runtime dumped lib hash mismatch for ${base}"
    printf '%s\t%s\t%s\n' "$base" "$dumped_hash" "${TEXTBOOM_LIB_ARM64_DIR}/${base}" >> "${WORK_DIR}/textboom-runtime-image-libs.tsv"
  done

  verified="$(wc -l < "${WORK_DIR}/textboom-runtime-image-libs.tsv" | tr -d ' ')"
  [ "$verified" -eq "$TEXTBOOM_RUNTIME_EXPECTED_LIB_COUNT" ] \
    || die "verified TextBoom runtime image lib count mismatch: actual=${verified} expected=${TEXTBOOM_RUNTIME_EXPECTED_LIB_COUNT}"
}

write_textboom_runtime_libs_to_image() {
  local image="$1" cmd_file lib base mkdir_arm64 arm64_listing
  cmd_file="${WORK_DIR}/write-textboom-runtime-libs.debugfs"

  debugfs_path_exists "$image" "$TEXTBOOM_DIR" || die "missing TextBoom directory"
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ROOT" || die "missing TextBoom lib root"
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM_DIR" || die "missing TextBoom arm lib dir"
  mkdir_arm64=1
  if debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM64_DIR"; then
    arm64_listing="$("$DEBUGFS" -R "ls -l ${TEXTBOOM_LIB_ARM64_DIR}" "$image" 2>&1 || true)"
    if grep -q '\.so' <<<"$arm64_listing"; then
      die "TextBoom arm64 lib dir already contains .so files; refusing ambiguous runtime lib write"
    fi
    mkdir_arm64=0
  fi

  {
    if [ "$mkdir_arm64" -eq 1 ]; then
      echo "mkdir ${TEXTBOOM_LIB_ARM64_DIR}"
    fi
    echo "set_inode_field ${TEXTBOOM_LIB_ARM64_DIR} mode 040755"
    echo "set_inode_field ${TEXTBOOM_LIB_ARM64_DIR} uid 0"
    echo "set_inode_field ${TEXTBOOM_LIB_ARM64_DIR} gid 0"
    echo "ea_set ${TEXTBOOM_LIB_ARM64_DIR} security.selinux ${SYSTEM_SELABEL}"
    find "$TEXTBOOM_RUNTIME_LIB_EXTRACTED_DIR" -maxdepth 1 -type f -name '*.so' | sort | while IFS= read -r lib; do
      base="$(basename "$lib")"
      echo "write ${lib} ${TEXTBOOM_LIB_ARM64_DIR}/${base}"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM64_DIR}/${base} mode 0100644"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM64_DIR}/${base} uid 0"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM64_DIR}/${base} gid 0"
      echo "ea_set ${TEXTBOOM_LIB_ARM64_DIR}/${base} security.selinux ${SYSTEM_SELABEL}"
    done
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  verify_textboom_runtime_libs_in_image "$image"
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

verify_inputs() {
  local part
  require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
  require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  if [ ! -f "$TEXTBOOM_ADAPTER_APK" ]; then
    "$TEXTBOOM_APK_BUILDER" >/dev/null
  fi
  require_hash "$TEXTBOOM_ADAPTER_APK" "$TEXTBOOM_ADAPTER_APK_SHA256"
  extract_textboom_runtime_libs
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

case "${1:-}" in
  "") ;;
  -h|--help|help) sed -n '1,120p' "$0"; exit 0 ;;
  *) echo "Usage: $0" >&2; exit 2 ;;
esac

need_executable "$LPMAKE"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_executable "$TEXTBOOM_APK_BUILDER"
need_file "$AVBTOOL"
need_file "$SOURCE_EXTRACT_DIR/system_a.img"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*-avb-info.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
  echo

  echo "## source"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
  echo "textboom_adapter_apk=${TEXTBOOM_ADAPTER_APK}"
  verify_inputs
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size "system_b pure ext4" "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"

  verify_apk_hash "$SYSTEM_B_IMG" "$SIDEBAR_PATH" "$SIDEBAR_APK_SHA256" "sidebar-retained"
  verify_apk_hash "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$TEXTBOOM_SYSTEM_BEFORE_SHA256" "textboom-before"
  verify_apk_hash "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$SYSTEM_WEBVIEW_SHA256" "system-webview-retained"
  verify_apk_hash "$SYSTEM_B_IMG" "$SMARTISAX_APK" "$SMARTISAX_SHA256" "smartisax-retained"
  debugfs_path_exists "$SYSTEM_B_IMG" "$TEXTBOOM_LIB_ARM_DIR" || die "TextBoom lib/arm missing before patch"

  : > "${WORK_DIR}/replacements.tsv"
  replace_file_in_image "$SYSTEM_B_IMG" "$TEXTBOOM_ADAPTER_APK" "$TEXTBOOM_PATH" \
    "textboom-ppocr-runtime-adapter" >> "${WORK_DIR}/replacements.tsv"
  write_textboom_runtime_libs_to_image "$SYSTEM_B_IMG"

  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_B_IMG" "$TEXTBOOM_DIR" "textboom-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_B_IMG" "/system/app" "system-app" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_apk_hash "$SYSTEM_B_IMG" "$SIDEBAR_PATH" "$SIDEBAR_APK_SHA256" "sidebar-after"
  verify_apk_hash "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$TEXTBOOM_ADAPTER_APK_SHA256" "textboom-after"
  debugfs_path_exists "$SYSTEM_B_IMG" "$TEXTBOOM_LIB_ARM_DIR" || die "TextBoom lib/arm missing after patch"
  verify_textboom_runtime_libs_in_image "$SYSTEM_B_IMG"
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size "system_b FEC image" "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-v041-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-v041-avb-info.txt" || die "system_b lost FEC roots"
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
  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  system_hash="$(sha256_one "$SYSTEM_B_IMG")"
  product_hash="$(sha256_one "$SOURCE_PRODUCT_B_IMG")"
  textboom_adapter_hash="$(sha256_one "$TEXTBOOM_ADAPTER_APK")"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=${sparse_hash}"
  echo

  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
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
    echo "textboom_adapter_apk=${TEXTBOOM_ADAPTER_APK}"
    echo "textboom_adapter_apk_sha256=${textboom_adapter_hash}"
    echo "textboom_system_path=${TEXTBOOM_PATH}"
    echo "textboom_system_before_sha256=${TEXTBOOM_SYSTEM_BEFORE_SHA256}"
    echo "textboom_apk_sha256=${TEXTBOOM_ADAPTER_APK_SHA256}"
    echo "textboom_adapter=LocalPpOcrApi"
    echo "textboom_adapter_behavior=local_ppocr_runtime_async_line_results"
    echo "textboom_patched_entrypoints=BoomOcrActivity.initView,BoomAccessOcrActivity.initOcr"
    echo "textboom_changed_payloads=classes2.dex_plus_classes4_assets_models_arm64_libs"
    echo "textboom_legacy_csocr_retained=true"
    echo "textboom_legacy_intsig_csopen_retained=true"
    echo "textboom_legacy_ocr_key_retained=true"
    echo "textboom_runtime_lib_arm64_dir=${TEXTBOOM_LIB_ARM64_DIR}"
    echo "textboom_runtime_lib_count=${TEXTBOOM_RUNTIME_EXPECTED_LIB_COUNT}"
    echo "sidebar_apk_sha256=${SIDEBAR_APK_SHA256}"
    echo "sidebar_font_ocr=code_deleted_retained_from_v039"
    echo "textboom_system_lib_dir=${TEXTBOOM_LIB_ARM_DIR}"
    echo "system_webview_apk_sha256=${SYSTEM_WEBVIEW_SHA256}"
    echo "smartisax_apk_sha256=${SMARTISAX_SHA256}"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "lpdump_status=$([ "$SKIP_LPDUMP" = "1" ] && echo skipped_to_save_disk_space || echo generated)"
    echo "fec_status=system_b_generated_roots_2_product_b_retained_from_v0352_roots_2"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# replacements"
    cat "${WORK_DIR}/replacements.tsv"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    echo "# textboom_runtime_libs"
    cat "${WORK_DIR}/textboom-runtime-image-libs.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_PRODUCT_B_IMG" "$TEXTBOOM_ADAPTER_APK"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V041_TEXTBOOM_PPOCR_RUNTIME_ADAPTER"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
