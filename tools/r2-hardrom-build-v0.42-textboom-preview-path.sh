#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
APK_BUILDER="${APK_BUILDER:-${ROOT_DIR}/tools/r2-build-textboom-ppocr-preview-path-apk.sh}"

VARIANT="${VARIANT:-v0.42-textboom-ppocr-preview-path}"
SOURCE_VARIANT="v0.41.1-textboom-ppocr-runtime-arm32-libs"
SOURCE_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.41.1-textboom-ppocr-runtime-arm32-libs.sparse.img"
SOURCE_SPARSE_SHA256="1517f5acc76554b8537938daf99938ad6d17916088c4e8e73c787fc1007eee58"
SOURCE_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.41.1-textboom-ppocr-runtime-arm32-libs.img"
SOURCE_SYSTEM_B_SHA256="00908fe7a218300211d1e42084faf85e9e934412180da5fdd038a5ebe79c7f8f"
SOURCE_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"
SOURCE_PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"

TEXTBOOM_PREVIEW_APK="${TEXTBOOM_PREVIEW_APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-preview-path.apk}"
TEXTBOOM_PREVIEW_APK_SHA256="${TEXTBOOM_PREVIEW_APK_SHA256:-a38f27541dbb5d9ef9b5f7d4bb806c474941bc1c21f146d8be5125ffd70645a8}"
TEXTBOOM_SOURCE_APK_SHA256="6f0d3964234f57c059f70446ba330e9dcb8a3741ae9ce97dfdc8d6fe7ce880a6"
TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_DIR="/system/app/TextBoom"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"
TEXTBOOM_LIB_ARM64_DIR="/system/app/TextBoom/lib/arm64"
TEXTBOOM_CODEPATH_MOVE="${TEXTBOOM_CODEPATH_MOVE:-0}"
TEXTBOOM_TARGET_DIR="${TEXTBOOM_TARGET_DIR:-$TEXTBOOM_DIR}"
TEXTBOOM_TARGET_APK_NAME="${TEXTBOOM_TARGET_APK_NAME:-TextBoom.apk}"
TEXTBOOM_TARGET_PATH="${TEXTBOOM_TARGET_DIR}/${TEXTBOOM_TARGET_APK_NAME}"
TEXTBOOM_TARGET_LIB_ROOT="${TEXTBOOM_TARGET_DIR}/lib"
TEXTBOOM_TARGET_LIB_ARM_DIR="${TEXTBOOM_TARGET_LIB_ROOT}/arm"
TEXTBOOM_TARGET_LIB_ARM64_DIR="${TEXTBOOM_TARGET_LIB_ROOT}/arm64"
TEXTBOOM_OLD_PUBLIC_HELD_PATH="${TEXTBOOM_OLD_PUBLIC_HELD_PATH:-${TEXTBOOM_DIR}/.TextBoom.apk.smartisax-${VARIANT}-old-codepath-held}"
NEW_OCR_DIR="${NEW_OCR_DIR:-/Android/data/com.smartisanos.textboom/files/.boom}"
NEW_OCR_PATH="${NEW_OCR_PATH:-/sdcard/Android/data/com.smartisanos.textboom/files/.boom/imageboom.jpg}"
OLD_OCR_DIR="${OLD_OCR_DIR:-/.boom}"
EXPECT_LEGACY_CSOCR_REMOVED="${EXPECT_LEGACY_CSOCR_REMOVED:-0}"
EXPECT_OCR_KEY_REMOVED="${EXPECT_OCR_KEY_REMOVED:-0}"
REMOVE_TEXTBOOM_ARM64_LIBS="${REMOVE_TEXTBOOM_ARM64_LIBS:-0}"
TEXTBOOM_ARM64_LIBS_EXPECTED="${TEXTBOOM_ARM64_LIBS_EXPECTED:-1}"
TEXTBOOM_CHANGED_PAYLOADS="${TEXTBOOM_CHANGED_PAYLOADS:-classes2.dex_only_from_v0411_textboom_apk}"
if [ "$REMOVE_TEXTBOOM_ARM64_LIBS" = "1" ]; then
  TEXTBOOM_ARM64_LIBS_EXPECTED=0
fi
TEXTBOOM_APK_ARM64_LIBS_EXPECTED="${TEXTBOOM_APK_ARM64_LIBS_EXPECTED:-$TEXTBOOM_ARM64_LIBS_EXPECTED}"

WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
SOURCE_EXTRACT_DIR="${WORK_DIR}/source-v0411-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v0411-super.raw.img"
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

TEXTBOOM_ARM32_LIBCXX_SHA256="c93fd24d94d79dd7c02ecf7e24f59692ad9743f8f681200393ff1f5a6d004b6a"
TEXTBOOM_ARM32_LIBONNXRUNTIME_SHA256="2e55ddb9df17bba226a2b3eb4ccd7029010c7631cee93a69a00f928c0e955972"
TEXTBOOM_ARM32_LIBONNXRUNTIME4J_SHA256="8b53e40fc127190b18e69a524371cd4ce9b52e059354d8fe8f228a345bb8355d"
TEXTBOOM_ARM32_LIBOPENCV_SHA256="d1671d9718927d7247840c49c7c1c3334f5eb335a9fafa495b73dac4e8ddea6a"
TEXTBOOM_ARM64_LIBCXX_SHA256="28e7a3a306d7fc222c62abe08741cfcba38c3f336216c4563726bf985ae3cfd6"
TEXTBOOM_ARM64_LIBONNXRUNTIME_SHA256="11ef853b751532dc827bd7799f557f9495e2ee7523b9b355753fc0344576bd5e"
TEXTBOOM_ARM64_LIBONNXRUNTIME4J_SHA256="f657216254a2f88fcbd89c5e73a2f7ae5a8145d092f8700951aedba8e4a60ef2"
TEXTBOOM_ARM64_LIBOPENCV_SHA256="41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7"

PURPOSE="${PURPOSE:-Move TextBoom result-page preview image from public /sdcard/.boom to TextBoom external app-specific storage while retaining the v0.41.1 PP-OCR runtime and ABI libraries.}"
RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V042_TEXTBOOM_PPOCR_PREVIEW_PATH}"

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
need_command() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

zip_has_prefix() {
  local apk="$1" prefix="$2"
  zipinfo -1 "$apk" | awk -v p="$prefix" 'index($0, p) == 1 {found = 1} END {exit !found}'
}

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

debugfs_link_count() {
  local image="$1" path="$2"
  "$DEBUGFS" -R "stat ${path}" "$image" 2>/dev/null \
    | awk '/Links:/ {for (i = 1; i <= NF; i++) if ($i == "Links:") {print $(i + 1); exit}}'
}

debugfs_regular_names() {
  local image="$1" path="$2"
  "$DEBUGFS" -R "ls -p ${path}" "$image" 2>/dev/null \
    | awk -F/ '$0 ~ /^\// && $3 !~ /^04/ && $6 != "." && $6 != ".." {print $6}'
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

verify_preview_apk_payload() {
  local apk="$1" tag="$2" strings_file manifest_strings_file
  strings_file="${WORK_DIR}/${tag}.classes2.strings"
  manifest_strings_file="${WORK_DIR}/${tag}.manifest.strings"
  unzip -t "$apk" >/dev/null || die "${tag} zip test failed"
  if [ "$TEXTBOOM_APK_ARM64_LIBS_EXPECTED" = "1" ]; then
    zip_has_prefix "$apk" 'lib/arm64-v8a/' || die "${tag} missing APK-internal arm64 libs"
  else
    if zip_has_prefix "$apk" 'lib/arm64-v8a/'; then
      die "${tag} still contains APK-internal arm64 libs"
    fi
  fi
  unzip -p "$apk" classes2.dex | strings > "$strings_file"
  unzip -p "$apk" AndroidManifest.xml | strings > "$manifest_strings_file"
  grep -q "$NEW_OCR_DIR" "$strings_file" || die "${tag} missing new OCR preview dir"
  if grep -Fxq "$OLD_OCR_DIR" "$strings_file"; then
    die "${tag} still contains standalone old OCR preview dir"
  fi
  grep -q "LocalPpOcrRuntime" "$strings_file" || die "${tag} lost LocalPpOcrRuntime bridge"
  grep -q "LocalPpOcrApi" "$strings_file" || die "${tag} lost LocalPpOcrApi bridge"
  if [ "$EXPECT_LEGACY_CSOCR_REMOVED" = "1" ]; then
    if grep -Eq 'CsOcr|Lcom/intsig|com/intsig|CSOCR' "$strings_file"; then
      die "${tag} still contains legacy CsOcr/Intsig code strings"
    fi
  fi
  if [ "$EXPECT_OCR_KEY_REMOVED" = "1" ]; then
    if grep -q 'ocr_key' "$manifest_strings_file"; then
      die "${tag} still contains manifest ocr_key"
    fi
  fi
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

verify_image_path_absent() {
  local image="$1" path="$2" label="$3"
  if debugfs_path_exists "$image" "$path"; then
    die "${label} unexpectedly exists: ${path}"
  fi
  printf '%s\tabsent\t%s\n' "$label" "$path"
}

replace_file_in_image() {
  local image="$1" src="$2" dst="$3" tag="$4"
  local dir base unlink_cmd write_cmd dumped src_hash dumped_hash link_count
  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  unlink_cmd="${WORK_DIR}/replace-${tag}-unlink.debugfs"
  write_cmd="${WORK_DIR}/replace-${tag}-write.debugfs"
  dumped="${WORK_DIR}/${tag}-dumped.apk"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination dir: $dir"
  debugfs_path_exists "$image" "$dst" || die "missing destination file: $dst"
  link_count="$(debugfs_link_count "$image" "$dst")"
  [ "$link_count" = "1" ] || die "${dst} link count is ${link_count}; refusing unlink-first replacement"

  {
    # v0.41.1 leaves only about 50 MiB free in system_b; freeing the old
    # single-link TextBoom APK before writing avoids a false ENOSPC.
    echo "rm ${dst}"
  } > "$unlink_cmd"
  "$DEBUGFS" -w -f "$unlink_cmd" "$image" >/dev/null
  if debugfs_path_exists "$image" "$dst"; then
    die "rm did not remove ${dst}"
  fi
  fsck_rw "$image"

  {
    echo "write ${src} ${dst}"
    echo "set_inode_field ${dst} mode 0100644"
    echo "set_inode_field ${dst} uid 0"
    echo "set_inode_field ${dst} gid 0"
    echo "ea_set ${dst} security.selinux ${SYSTEM_SELABEL}"
  } > "$write_cmd"
  "$DEBUGFS" -w -f "$write_cmd" "$image" >/dev/null
  debugfs_dump "$image" "$dst" "$dumped"
  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${dst}"
  verify_preview_apk_payload "$dumped" "${tag}-dumped"
  echo "${dst}|${src}|${src_hash}|${dumped}|rm_first_single_link=true"
}

install_textboom_at_new_codepath() {
  local image="$1" src="$2" tag="$3"
  local cmd_file dumped src_hash dumped_hash arm_lib_count arm64_lib_count
  cmd_file="${WORK_DIR}/install-${tag}-new-codepath.debugfs"
  dumped="${WORK_DIR}/${tag}-new-codepath-dumped.apk"

  [ "$TEXTBOOM_TARGET_DIR" != "$TEXTBOOM_DIR" ] \
    || die "TEXTBOOM_CODEPATH_MOVE=1 requires TEXTBOOM_TARGET_DIR to differ from ${TEXTBOOM_DIR}"
  need_file "$src"
  debugfs_path_exists "$image" "/system/app" || die "missing /system/app"
  debugfs_path_exists "$image" "$TEXTBOOM_DIR" || die "missing old TextBoom directory"
  debugfs_path_exists "$image" "$TEXTBOOM_PATH" || die "missing old TextBoom public APK"
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM_DIR" || die "missing old TextBoom arm lib dir"
  ! debugfs_path_exists "$image" "$TEXTBOOM_TARGET_DIR" \
    || die "target TextBoom codePath already exists: ${TEXTBOOM_TARGET_DIR}"
  ! debugfs_path_exists "$image" "$TEXTBOOM_OLD_PUBLIC_HELD_PATH" \
    || die "old TextBoom held path already exists: ${TEXTBOOM_OLD_PUBLIC_HELD_PATH}"

  arm_lib_count="$(debugfs_regular_names "$image" "$TEXTBOOM_LIB_ARM_DIR" | wc -l | tr -d ' ')"
  [ "$arm_lib_count" -gt 0 ] || die "old TextBoom arm lib dir is empty"
  arm64_lib_count=0
  if [ "$TEXTBOOM_ARM64_LIBS_EXPECTED" = "1" ]; then
    debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM64_DIR" || die "missing old TextBoom arm64 lib dir"
    arm64_lib_count="$(debugfs_regular_names "$image" "$TEXTBOOM_LIB_ARM64_DIR" | wc -l | tr -d ' ')"
    [ "$arm64_lib_count" -gt 0 ] || die "old TextBoom arm64 lib dir is empty"
  fi

  {
    echo "mkdir ${TEXTBOOM_TARGET_DIR}"
    echo "set_inode_field ${TEXTBOOM_TARGET_DIR} mode 040755"
    echo "set_inode_field ${TEXTBOOM_TARGET_DIR} uid 0"
    echo "set_inode_field ${TEXTBOOM_TARGET_DIR} gid 0"
    echo "ea_set ${TEXTBOOM_TARGET_DIR} security.selinux ${SYSTEM_SELABEL}"
    echo "write ${src} ${TEXTBOOM_TARGET_PATH}"
    echo "set_inode_field ${TEXTBOOM_TARGET_PATH} mode 0100644"
    echo "set_inode_field ${TEXTBOOM_TARGET_PATH} uid 0"
    echo "set_inode_field ${TEXTBOOM_TARGET_PATH} gid 0"
    echo "ea_set ${TEXTBOOM_TARGET_PATH} security.selinux ${SYSTEM_SELABEL}"
    echo "mkdir ${TEXTBOOM_TARGET_LIB_ROOT}"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ROOT} mode 040755"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ROOT} uid 0"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ROOT} gid 0"
    echo "ea_set ${TEXTBOOM_TARGET_LIB_ROOT} security.selinux ${SYSTEM_SELABEL}"
    echo "mkdir ${TEXTBOOM_TARGET_LIB_ARM_DIR}"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM_DIR} mode 040755"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM_DIR} uid 0"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM_DIR} gid 0"
    echo "ea_set ${TEXTBOOM_TARGET_LIB_ARM_DIR} security.selinux ${SYSTEM_SELABEL}"
    while IFS= read -r lib_name; do
      [ -n "$lib_name" ] || continue
      echo "ln ${TEXTBOOM_LIB_ARM_DIR}/${lib_name} ${TEXTBOOM_TARGET_LIB_ARM_DIR}/${lib_name}"
    done < <(debugfs_regular_names "$image" "$TEXTBOOM_LIB_ARM_DIR")
    if [ "$TEXTBOOM_ARM64_LIBS_EXPECTED" = "1" ]; then
      echo "mkdir ${TEXTBOOM_TARGET_LIB_ARM64_DIR}"
      echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR} mode 040755"
      echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR} uid 0"
      echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR} gid 0"
      echo "ea_set ${TEXTBOOM_TARGET_LIB_ARM64_DIR} security.selinux ${SYSTEM_SELABEL}"
      while IFS= read -r lib_name; do
        [ -n "$lib_name" ] || continue
        echo "ln ${TEXTBOOM_LIB_ARM64_DIR}/${lib_name} ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/${lib_name}"
      done < <(debugfs_regular_names "$image" "$TEXTBOOM_LIB_ARM64_DIR")
    fi
    echo "ln ${TEXTBOOM_PATH} ${TEXTBOOM_OLD_PUBLIC_HELD_PATH}"
    echo "unlink ${TEXTBOOM_PATH}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$TEXTBOOM_TARGET_DIR" || die "missing new TextBoom target dir"
  debugfs_path_exists "$image" "$TEXTBOOM_TARGET_PATH" || die "missing new TextBoom target APK"
  debugfs_path_exists "$image" "$TEXTBOOM_TARGET_LIB_ARM_DIR" || die "missing new TextBoom arm lib dir"
  if [ "$TEXTBOOM_ARM64_LIBS_EXPECTED" = "1" ]; then
    debugfs_path_exists "$image" "$TEXTBOOM_TARGET_LIB_ARM64_DIR" || die "missing new TextBoom arm64 lib dir"
  fi
  debugfs_path_exists "$image" "$TEXTBOOM_OLD_PUBLIC_HELD_PATH" || die "missing held old TextBoom APK"
  ! debugfs_path_exists "$image" "$TEXTBOOM_PATH" || die "old TextBoom public APK still exists"

  debugfs_dump "$image" "$TEXTBOOM_TARGET_PATH" "$dumped"
  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${TEXTBOOM_TARGET_PATH}"
  verify_preview_apk_payload "$dumped" "${tag}-new-codepath-dumped"
  echo "${TEXTBOOM_TARGET_PATH}|${src}|${src_hash}|${dumped}|codepath_move=true|old_public_held=${TEXTBOOM_OLD_PUBLIC_HELD_PATH}|linked_arm_libs=${arm_lib_count}|linked_arm64_libs=${arm64_lib_count}"
}

remove_textboom_arm64_libs() {
  local image="$1"
  debugfs_rm_tree "$image" "$TEXTBOOM_LIB_ARM64_DIR" \
    || die "missing TextBoom arm64 lib dir before removal"
  if debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM64_DIR"; then
    die "TextBoom arm64 lib dir still exists after removal"
  fi
  echo "${TEXTBOOM_LIB_ARM64_DIR}|removed=true" >> "${WORK_DIR}/removed-paths.tsv"
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
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
}

prepare_retained_partitions() {
  local part
  if [ ! -f "${SOURCE_EXTRACT_DIR}/system_a.img" ] || [ ! -f "${SOURCE_EXTRACT_DIR}/system_ext_b.img" ]; then
    echo "retained_partition_extract=from_${SOURCE_VARIANT}"
    rm -rf "$SOURCE_EXTRACT_DIR"
    mkdir -p "$SOURCE_EXTRACT_DIR"
    rm -f "$SOURCE_RAW"
    "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
    check_size source_raw_super "$SOURCE_RAW" "$SUPER_SIZE"
    "$LPUNPACK" --slot=1 \
      --partition=system_a \
      --partition=product_a \
      --partition=vendor_a \
      --partition=odm_a \
      --partition=system_ext_b \
      --partition=vendor_b \
      --partition=odm_b \
      "$SOURCE_RAW" "$SOURCE_EXTRACT_DIR" >/dev/null
    rm -f "$SOURCE_RAW"
  else
    echo "retained_partition_extract=reused"
  fi

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
  -h|--help|help) sed -n '1,140p' "$0"; exit 0 ;;
  *) echo "Usage: $0" >&2; exit 2 ;;
esac

need_executable "$LPMAKE"
need_executable "$LPUNPACK"
need_executable "$SIMG2IMG"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_executable "$APK_BUILDER"
need_file "$AVBTOOL"
need_command unzip
need_command zipinfo
need_command strings

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
trap 'rm -f "$SOURCE_RAW"' EXIT
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.strings "${WORK_DIR}"/*-avb-info.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
  echo

  echo "## inputs"
  require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
  require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  if [ ! -f "$TEXTBOOM_PREVIEW_APK" ]; then
    "$APK_BUILDER" >/dev/null
  fi
  require_hash "$TEXTBOOM_PREVIEW_APK" "$TEXTBOOM_PREVIEW_APK_SHA256"
  verify_preview_apk_payload "$TEXTBOOM_PREVIEW_APK" "textboom-preview-source"
  prepare_retained_partitions
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  echo "textboom_preview_apk=${TEXTBOOM_PREVIEW_APK}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"

  verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$TEXTBOOM_SOURCE_APK_SHA256" "textboom-before.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libc++_shared.so" "$TEXTBOOM_ARM32_LIBCXX_SHA256" "textboom-arm32-libcxx-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime.so" "$TEXTBOOM_ARM32_LIBONNXRUNTIME_SHA256" "textboom-arm32-libonnxruntime-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime4j_jni.so" "$TEXTBOOM_ARM32_LIBONNXRUNTIME4J_SHA256" "textboom-arm32-libonnxruntime4j-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libopencv_java4.so" "$TEXTBOOM_ARM32_LIBOPENCV_SHA256" "textboom-arm32-libopencv-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libc++_shared.so" "$TEXTBOOM_ARM64_LIBCXX_SHA256" "textboom-arm64-libcxx-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime.so" "$TEXTBOOM_ARM64_LIBONNXRUNTIME_SHA256" "textboom-arm64-libonnxruntime-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime4j_jni.so" "$TEXTBOOM_ARM64_LIBONNXRUNTIME4J_SHA256" "textboom-arm64-libonnxruntime4j-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libopencv_java4.so" "$TEXTBOOM_ARM64_LIBOPENCV_SHA256" "textboom-arm64-libopencv-before.so"

  : > "${WORK_DIR}/removed-paths.tsv"
  if [ "$REMOVE_TEXTBOOM_ARM64_LIBS" = "1" ] && [ "$TEXTBOOM_CODEPATH_MOVE" = "1" ]; then
    remove_textboom_arm64_libs "$SYSTEM_B_IMG"
    fsck_rw "$SYSTEM_B_IMG"
  fi

  : > "${WORK_DIR}/replacements.tsv"
  if [ "$TEXTBOOM_CODEPATH_MOVE" = "1" ]; then
    install_textboom_at_new_codepath "$SYSTEM_B_IMG" "$TEXTBOOM_PREVIEW_APK" \
      "textboom-ppocr-preview-path" >> "${WORK_DIR}/replacements.tsv"
  else
    replace_file_in_image "$SYSTEM_B_IMG" "$TEXTBOOM_PREVIEW_APK" "$TEXTBOOM_PATH" \
      "textboom-ppocr-preview-path" >> "${WORK_DIR}/replacements.tsv"
  fi

  if [ "$REMOVE_TEXTBOOM_ARM64_LIBS" = "1" ] && [ "$TEXTBOOM_CODEPATH_MOVE" != "1" ]; then
    remove_textboom_arm64_libs "$SYSTEM_B_IMG"
  fi

  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_B_IMG" "$TEXTBOOM_DIR" "textboom-old-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  if [ "$TEXTBOOM_CODEPATH_MOVE" = "1" ]; then
    bump_package_dir_time "$SYSTEM_B_IMG" "$TEXTBOOM_TARGET_DIR" "textboom-target-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  fi
  bump_package_dir_time "$SYSTEM_B_IMG" "/system/app" "system-app" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  if [ "$TEXTBOOM_CODEPATH_MOVE" = "1" ]; then
    verify_image_path_absent "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "textboom-old-public-apk-after"
    verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_TARGET_PATH" "$TEXTBOOM_PREVIEW_APK_SHA256" "textboom-after.apk"
  else
    verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$TEXTBOOM_PREVIEW_APK_SHA256" "textboom-after.apk"
  fi
  verify_preview_apk_payload "${WORK_DIR}/textboom-after.apk" "textboom-after"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM_DIR}/libonnxruntime.so" "$TEXTBOOM_ARM32_LIBONNXRUNTIME_SHA256" "textboom-arm32-libonnxruntime-after.so"
  if [ "$TEXTBOOM_ARM64_LIBS_EXPECTED" = "1" ]; then
    verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libopencv_java4.so" "$TEXTBOOM_ARM64_LIBOPENCV_SHA256" "textboom-arm64-libopencv-after.so"
  else
    verify_image_path_absent "$SYSTEM_B_IMG" "$TEXTBOOM_LIB_ARM64_DIR" "textboom-old-arm64-lib-dir-after"
    verify_image_path_absent "$SYSTEM_B_IMG" "$TEXTBOOM_TARGET_LIB_ARM64_DIR" "textboom-target-arm64-lib-dir-after"
  fi
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size system_b_fec_image "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b lost FEC roots"
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
    echo "textboom_system_path=${TEXTBOOM_PATH}"
    echo "textboom_target_system_path=${TEXTBOOM_TARGET_PATH}"
    echo "textboom_code_path_expected=${TEXTBOOM_TARGET_DIR}"
    echo "textboom_native_library_path_expected=${TEXTBOOM_TARGET_LIB_ROOT}"
    echo "textboom_lib_arm_dir=${TEXTBOOM_TARGET_LIB_ARM_DIR}"
    echo "textboom_lib_arm64_dir=${TEXTBOOM_TARGET_LIB_ARM64_DIR}"
    echo "textboom_codepath_move=${TEXTBOOM_CODEPATH_MOVE}"
    if [ "$TEXTBOOM_CODEPATH_MOVE" = "1" ]; then
      echo "textboom_old_public_apk_path=${TEXTBOOM_PATH}"
      echo "textboom_old_public_apk_absent=true"
      echo "textboom_old_public_held_path=${TEXTBOOM_OLD_PUBLIC_HELD_PATH}"
    else
      echo "textboom_old_public_apk_absent=false"
    fi
    echo "textboom_source_apk_sha256=${TEXTBOOM_SOURCE_APK_SHA256}"
    echo "textboom_apk_sha256=${TEXTBOOM_PREVIEW_APK_SHA256}"
    echo "textboom_preview_apk=${TEXTBOOM_PREVIEW_APK}"
    echo "textboom_preview_new_ocr_dir=${NEW_OCR_DIR}"
    echo "textboom_preview_expected_path=${NEW_OCR_PATH}"
    echo "textboom_preview_old_public_path=/sdcard/.boom/imageboom.jpg"
    echo "textboom_changed_payloads=${TEXTBOOM_CHANGED_PAYLOADS}"
    if [ "$EXPECT_LEGACY_CSOCR_REMOVED" = "1" ]; then
      echo "textboom_legacy_csocr_retained=false"
      echo "textboom_legacy_intsig_csopen_retained=false"
    else
      echo "textboom_legacy_csocr_retained=true"
      echo "textboom_legacy_intsig_csopen_retained=true"
    fi
    if [ "$EXPECT_OCR_KEY_REMOVED" = "1" ]; then
      echo "textboom_legacy_ocr_key_retained=false"
    else
      echo "textboom_legacy_ocr_key_retained=true"
    fi
    echo "expect_legacy_csocr_removed=${EXPECT_LEGACY_CSOCR_REMOVED}"
    echo "expect_ocr_key_removed=${EXPECT_OCR_KEY_REMOVED}"
    echo "textboom_adapter=LocalPpOcrApi"
    echo "textboom_runtime=LocalPpOcrRuntime_retained"
    echo "textboom_primary_cpu_abi_expected=armeabi-v7a"
    if [ "$TEXTBOOM_APK_ARM64_LIBS_EXPECTED" = "1" ]; then
      echo "textboom_apk_arm64_libs_retained=true"
    else
      echo "textboom_apk_arm64_libs_retained=false"
    fi
    if [ "$TEXTBOOM_ARM64_LIBS_EXPECTED" = "1" ]; then
      echo "textboom_arm64_libs_retained=true"
    else
      echo "textboom_arm64_libs_retained=false"
      echo "textboom_arm64_libs_removed_path=${TEXTBOOM_LIB_ARM64_DIR}"
    fi
    echo "textboom_arm32_libcxx_sha256=${TEXTBOOM_ARM32_LIBCXX_SHA256}"
    echo "textboom_arm32_libonnxruntime_sha256=${TEXTBOOM_ARM32_LIBONNXRUNTIME_SHA256}"
    echo "textboom_arm32_libonnxruntime4j_jni_sha256=${TEXTBOOM_ARM32_LIBONNXRUNTIME4J_SHA256}"
    echo "textboom_arm32_libopencv_java4_sha256=${TEXTBOOM_ARM32_LIBOPENCV_SHA256}"
    echo "textboom_arm64_libcxx_sha256=${TEXTBOOM_ARM64_LIBCXX_SHA256}"
    echo "textboom_arm64_libonnxruntime_sha256=${TEXTBOOM_ARM64_LIBONNXRUNTIME_SHA256}"
    echo "textboom_arm64_libonnxruntime4j_jni_sha256=${TEXTBOOM_ARM64_LIBONNXRUNTIME4J_SHA256}"
    echo "textboom_arm64_libopencv_java4_sha256=${TEXTBOOM_ARM64_LIBOPENCV_SHA256}"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "fec_status=system_b_generated_roots_2_product_b_retained_from_v0352_roots_2"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# replacements"
    cat "${WORK_DIR}/replacements.tsv"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    if [ -s "${WORK_DIR}/removed-paths.tsv" ]; then
      echo
      echo "# removed_paths"
      cat "${WORK_DIR}/removed-paths.tsv"
    fi
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_PRODUCT_B_IMG" "$TEXTBOOM_PREVIEW_APK"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=${sparse_hash}"
  echo "system_b_sha256=${system_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
