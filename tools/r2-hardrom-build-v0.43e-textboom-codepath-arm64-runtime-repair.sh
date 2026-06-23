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

VARIANT="${VARIANT:-v0.43e-textboom-codepath-arm64-runtime-repair}"
SOURCE_VARIANT="v0.43d-textboom-codepath-arm32-abi"
SOURCE_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.43d-textboom-codepath-arm32-abi.sparse.img"
SOURCE_SPARSE_SHA256="c9c2d6013a933f5fcf1374bcb0c1df6940c4110d3ae138192236cf5865801bc2"
SOURCE_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.43d-textboom-codepath-arm32-abi.img"
SOURCE_SYSTEM_B_SHA256="d34e00f433497405af81438d8c7bb1763b75d623820123c7e7c1fb57e42ecda7"
SOURCE_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"
SOURCE_PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"

WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
SOURCE_EXTRACT_DIR="${WORK_DIR}/source-v043d-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v043d-super.raw.img"
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

TEXTBOOM_TARGET_DIR="/system/app/TextBoomArm32"
TEXTBOOM_TARGET_PATH="${TEXTBOOM_TARGET_DIR}/TextBoomArm32.apk"
TEXTBOOM_OLD_PUBLIC_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_OLD_PUBLIC_HELD_PATH="/system/app/TextBoom/.TextBoom.apk.smartisax-v0.43d-textboom-codepath-arm32-abi-old-codepath-held"
TEXTBOOM_TARGET_LIB_ROOT="${TEXTBOOM_TARGET_DIR}/lib"
TEXTBOOM_TARGET_LIB_ARM_DIR="${TEXTBOOM_TARGET_LIB_ROOT}/arm"
TEXTBOOM_TARGET_LIB_ARM64_DIR="${TEXTBOOM_TARGET_LIB_ROOT}/arm64"
TEXTBOOM_APK_SHA256="0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7"
TEXTBOOM_SOURCE_APK_SHA256="6f0d3964234f57c059f70446ba330e9dcb8a3741ae9ce97dfdc8d6fe7ce880a6"
TEXTBOOM_ARM32_LIBCXX_SHA256="c93fd24d94d79dd7c02ecf7e24f59692ad9743f8f681200393ff1f5a6d004b6a"
TEXTBOOM_ARM32_LIBONNXRUNTIME_SHA256="2e55ddb9df17bba226a2b3eb4ccd7029010c7631cee93a69a00f928c0e955972"
TEXTBOOM_ARM32_LIBONNXRUNTIME4J_SHA256="8b53e40fc127190b18e69a524371cd4ce9b52e059354d8fe8f228a345bb8355d"
TEXTBOOM_ARM32_LIBOPENCV_SHA256="d1671d9718927d7247840c49c7c1c3334f5eb335a9fafa495b73dac4e8ddea6a"
TEXTBOOM_ARM64_LIBCXX_SHA256="28e7a3a306d7fc222c62abe08741cfcba38c3f336216c4563726bf985ae3cfd6"
TEXTBOOM_ARM64_LIBONNXRUNTIME_SHA256="11ef853b751532dc827bd7799f557f9495e2ee7523b9b355753fc0344576bd5e"
TEXTBOOM_ARM64_LIBONNXRUNTIME4J_SHA256="f657216254a2f88fcbd89c5e73a2f7ae5a8145d092f8700951aedba8e4a60ef2"
TEXTBOOM_ARM64_LIBOPENCV_SHA256="41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7"

ARM64_LIB_SRC_DIR="${ARM64_LIB_SRC_DIR:-${ROOT_DIR}/hard-rom/build/textboom-arm64-runtime-libs-v0411}"
ARM64_LIBCXX="${ARM64_LIBCXX:-${ARM64_LIB_SRC_DIR}/libc++_shared.so}"
ARM64_LIBONNXRUNTIME="${ARM64_LIBONNXRUNTIME:-${ARM64_LIB_SRC_DIR}/libonnxruntime.so}"
ARM64_LIBONNXRUNTIME4J="${ARM64_LIBONNXRUNTIME4J:-${ARM64_LIB_SRC_DIR}/libonnxruntime4j_jni.so}"
ARM64_LIBOPENCV="${ARM64_LIBOPENCV:-${ARM64_LIB_SRC_DIR}/libopencv_java4.so}"

NEW_OCR_DIR="/Android/media/com.smartisanos.textboom/.boom"
NEW_OCR_PATH="/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg"
PURPOSE="Repair v0.43d's codePath experiment by accepting PackageManager arm64-v8a and restoring arm64 ORT/OpenCV runtime libraries under /system/app/TextBoomArm32/lib/arm64."
RESULT_NAME="PASS_BUILD_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR"

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

install_target_arm64_libs() {
  local image="$1" cmd_file
  cmd_file="${WORK_DIR}/install-textboom-target-arm64.debugfs"
  debugfs_path_exists "$image" "$TEXTBOOM_TARGET_LIB_ROOT" || die "missing target lib root"
  ! debugfs_path_exists "$image" "$TEXTBOOM_TARGET_LIB_ARM64_DIR" || die "target arm64 lib dir already exists"

  {
    echo "mkdir ${TEXTBOOM_TARGET_LIB_ARM64_DIR}"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR} mode 040755"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR} uid 0"
    echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR} gid 0"
    echo "ea_set ${TEXTBOOM_TARGET_LIB_ARM64_DIR} security.selinux ${SYSTEM_SELABEL}"
    echo "write ${ARM64_LIBCXX} ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libc++_shared.so"
    echo "write ${ARM64_LIBONNXRUNTIME} ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libonnxruntime.so"
    echo "write ${ARM64_LIBONNXRUNTIME4J} ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libonnxruntime4j_jni.so"
    echo "write ${ARM64_LIBOPENCV} ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libopencv_java4.so"
    for lib in libc++_shared.so libonnxruntime.so libonnxruntime4j_jni.so libopencv_java4.so; do
      echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/${lib} mode 0100644"
      echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/${lib} uid 0"
      echo "set_inode_field ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/${lib} gid 0"
      echo "ea_set ${TEXTBOOM_TARGET_LIB_ARM64_DIR}/${lib} security.selinux ${SYSTEM_SELABEL}"
    done
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$TEXTBOOM_TARGET_LIB_ARM64_DIR" || die "missing target arm64 lib dir after install"
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
need_file "$AVBTOOL"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
trap 'rm -f "$SOURCE_RAW"' EXIT
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.so "${WORK_DIR}"/*-avb-info.txt

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
  require_hash "$ARM64_LIBCXX" "$TEXTBOOM_ARM64_LIBCXX_SHA256"
  require_hash "$ARM64_LIBONNXRUNTIME" "$TEXTBOOM_ARM64_LIBONNXRUNTIME_SHA256"
  require_hash "$ARM64_LIBONNXRUNTIME4J" "$TEXTBOOM_ARM64_LIBONNXRUNTIME4J_SHA256"
  require_hash "$ARM64_LIBOPENCV" "$TEXTBOOM_ARM64_LIBOPENCV_SHA256"
  prepare_retained_partitions
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  echo "arm64_lib_source_dir=${ARM64_LIB_SRC_DIR}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_TARGET_PATH" "$TEXTBOOM_APK_SHA256" "textboom-before.apk"
  verify_image_path_absent "$SYSTEM_B_IMG" "$TEXTBOOM_OLD_PUBLIC_PATH" "textboom-old-public-before"
  verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_OLD_PUBLIC_HELD_PATH" "$TEXTBOOM_SOURCE_APK_SHA256" "textboom-old-held-before.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM_DIR}/libc++_shared.so" "$TEXTBOOM_ARM32_LIBCXX_SHA256" "textboom-arm32-libcxx-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM_DIR}/libonnxruntime.so" "$TEXTBOOM_ARM32_LIBONNXRUNTIME_SHA256" "textboom-arm32-libonnxruntime-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM_DIR}/libonnxruntime4j_jni.so" "$TEXTBOOM_ARM32_LIBONNXRUNTIME4J_SHA256" "textboom-arm32-libonnxruntime4j-before.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM_DIR}/libopencv_java4.so" "$TEXTBOOM_ARM32_LIBOPENCV_SHA256" "textboom-arm32-libopencv-before.so"
  verify_image_path_absent "$SYSTEM_B_IMG" "$TEXTBOOM_TARGET_LIB_ARM64_DIR" "textboom-target-arm64-lib-dir-before"

  : > "${WORK_DIR}/added-paths.tsv"
  install_target_arm64_libs "$SYSTEM_B_IMG"
  echo "${TEXTBOOM_TARGET_LIB_ARM64_DIR}|restored=true" >> "${WORK_DIR}/added-paths.tsv"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libc++_shared.so" "$TEXTBOOM_ARM64_LIBCXX_SHA256" "textboom-arm64-libcxx-after.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libonnxruntime.so" "$TEXTBOOM_ARM64_LIBONNXRUNTIME_SHA256" "textboom-arm64-libonnxruntime-after.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libonnxruntime4j_jni.so" "$TEXTBOOM_ARM64_LIBONNXRUNTIME4J_SHA256" "textboom-arm64-libonnxruntime4j-after.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_TARGET_LIB_ARM64_DIR}/libopencv_java4.so" "$TEXTBOOM_ARM64_LIBOPENCV_SHA256" "textboom-arm64-libopencv-after.so"
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
    echo "textboom_system_path=/system/app/TextBoom/TextBoom.apk"
    echo "textboom_target_system_path=${TEXTBOOM_TARGET_PATH}"
    echo "textboom_code_path_expected=${TEXTBOOM_TARGET_DIR}"
    echo "textboom_native_library_path_expected=${TEXTBOOM_TARGET_LIB_ROOT}"
    echo "textboom_lib_arm_dir=${TEXTBOOM_TARGET_LIB_ARM_DIR}"
    echo "textboom_lib_arm64_dir=${TEXTBOOM_TARGET_LIB_ARM64_DIR}"
    echo "textboom_codepath_move=1"
    echo "textboom_old_public_apk_path=${TEXTBOOM_OLD_PUBLIC_PATH}"
    echo "textboom_old_public_apk_absent=true"
    echo "textboom_old_public_held_path=${TEXTBOOM_OLD_PUBLIC_HELD_PATH}"
    echo "textboom_source_apk_sha256=${TEXTBOOM_SOURCE_APK_SHA256}"
    echo "textboom_apk_sha256=${TEXTBOOM_APK_SHA256}"
    echo "textboom_preview_new_ocr_dir=${NEW_OCR_DIR}"
    echo "textboom_preview_expected_path=${NEW_OCR_PATH}"
    echo "textboom_preview_old_public_path=/sdcard/.boom/imageboom.jpg"
    echo "textboom_changed_payloads=v0.43d_system_b_plus_target_arm64_runtime_libs"
    echo "textboom_legacy_csocr_retained=false"
    echo "textboom_legacy_intsig_csopen_retained=false"
    echo "textboom_legacy_ocr_key_retained=true"
    echo "expect_legacy_csocr_removed=1"
    echo "expect_ocr_key_removed=0"
    echo "textboom_adapter=LocalPpOcrApi"
    echo "textboom_runtime=LocalPpOcrRuntime_retained"
    echo "textboom_primary_cpu_abi_expected=arm64-v8a"
    echo "textboom_apk_arm64_libs_retained=false"
    echo "textboom_arm64_libs_retained=true"
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
    echo "# added_paths"
    cat "${WORK_DIR}/added-paths.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_PRODUCT_B_IMG" "$ARM64_LIBCXX" "$ARM64_LIBONNXRUNTIME" "$ARM64_LIBONNXRUNTIME4J" "$ARM64_LIBOPENCV"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=${sparse_hash}"
  echo "system_b_sha256=${system_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} | tee "$REPORT"

echo "Built: $OUT_SPARSE"
echo "System image: $SYSTEM_B_IMG"
echo "Manifest: $MANIFEST"
echo "Report: $REPORT"
echo "Flash gate: explicit user confirmation required."
