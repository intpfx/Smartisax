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

VARIANT="v0.41.1-textboom-ppocr-runtime-arm32-libs"
SOURCE_VARIANT="v0.41-textboom-ppocr-runtime-adapter"
SOURCE_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.41-textboom-ppocr-runtime-adapter.sparse.img"
SOURCE_SPARSE_SHA256="f65fd372c8ac4642d8ed0ead7abe8535f904f740a6020b19019590ef3eacbce4"
SOURCE_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.41-textboom-ppocr-runtime-adapter.img"
SOURCE_SYSTEM_B_SHA256="02f356d36afdc6cc9f9c9d6975bdb1b0b9c51a530a605a758a5ea8638a93d348"
SOURCE_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"
SOURCE_PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"

WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
SOURCE_EXTRACT_DIR="${WORK_DIR}/source-v041-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v041-super.raw.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

ARM32_RUNTIME_DIR="${ROOT_DIR}/hard-rom/build/textboom-ppocr-official-bench/gradle-project/app/build/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib/armeabi-v7a"
TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_DIR="/system/app/TextBoom"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"
TEXTBOOM_LIB_ARM64_DIR="/system/app/TextBoom/lib/arm64"
SYSTEM_SELABEL="u:object_r:system_file:s0"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-$(printf '0x%x' "$(date +%s)")}"

TEXTBOOM_APK_SHA256="6f0d3964234f57c059f70446ba330e9dcb8a3741ae9ce97dfdc8d6fe7ce880a6"
TEXTBOOM_OLD_ARM_LIBCXX_SHA256="c93fd24d94d79dd7c02ecf7e24f59692ad9743f8f681200393ff1f5a6d004b6a"
ARM32_LIBONNXRUNTIME_SHA256="2e55ddb9df17bba226a2b3eb4ccd7029010c7631cee93a69a00f928c0e955972"
ARM32_LIBONNXRUNTIME4J_SHA256="8b53e40fc127190b18e69a524371cd4ce9b52e059354d8fe8f228a345bb8355d"
ARM32_LIBOPENCV_SHA256="d1671d9718927d7247840c49c7c1c3334f5eb335a9fafa495b73dac4e8ddea6a"

ARM64_LIBCXX_SHA256="28e7a3a306d7fc222c62abe08741cfcba38c3f336216c4563726bf985ae3cfd6"
ARM64_LIBONNXRUNTIME_SHA256="11ef853b751532dc827bd7799f557f9495e2ee7523b9b355753fc0344576bd5e"
ARM64_LIBONNXRUNTIME4J_SHA256="f657216254a2f88fcbd89c5e73a2f7ae5a8145d092f8700951aedba8e4a60ef2"
ARM64_LIBOPENCV_SHA256="41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7"

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
  debugfs_dump "$image" "$path" "$out"
  actual="$(sha256_one "$out")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

write_arm32_runtime_libs() {
  local image="$1" cmd_file="${WORK_DIR}/write-arm32-runtime-libs.debugfs"
  local base src

  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM_DIR" || die "missing TextBoom lib/arm dir"
  for base in libonnxruntime.so libonnxruntime4j_jni.so libopencv_java4.so; do
    src="${ARM32_RUNTIME_DIR}/${base}"
    need_file "$src"
    if debugfs_path_exists "$image" "${TEXTBOOM_LIB_ARM_DIR}/${base}"; then
      die "target arm32 runtime lib already exists: ${base}"
    fi
  done

  {
    for base in libonnxruntime.so libonnxruntime4j_jni.so libopencv_java4.so; do
      src="${ARM32_RUNTIME_DIR}/${base}"
      echo "write ${src} ${TEXTBOOM_LIB_ARM_DIR}/${base}"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR}/${base} mode 0100644"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR}/${base} uid 0"
      echo "set_inode_field ${TEXTBOOM_LIB_ARM_DIR}/${base} gid 0"
      echo "ea_set ${TEXTBOOM_LIB_ARM_DIR}/${base} security.selinux ${SYSTEM_SELABEL}"
    done
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
}

bump_package_dir_time() {
  local image="$1" dir="$2" tag="$3" cmd_file
  cmd_file="${WORK_DIR}/bump-${tag}.debugfs"
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
  "" ) ;;
  -h|--help|help) sed -n '1,120p' "$0"; exit 0 ;;
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
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*-dumped.so "${WORK_DIR}"/*-avb-info.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=Add 32-bit ORT/OpenCV runtime libraries for TextBoom app_process32 while keeping the v0.41 TextBoom APK unchanged."
  echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
  echo

  echo "## inputs"
  require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
  require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  require_hash "${ARM32_RUNTIME_DIR}/libonnxruntime.so" "$ARM32_LIBONNXRUNTIME_SHA256"
  require_hash "${ARM32_RUNTIME_DIR}/libonnxruntime4j_jni.so" "$ARM32_LIBONNXRUNTIME4J_SHA256"
  require_hash "${ARM32_RUNTIME_DIR}/libopencv_java4.so" "$ARM32_LIBOPENCV_SHA256"
  prepare_retained_partitions
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  echo "arm32_runtime_dir=${ARM32_RUNTIME_DIR}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"

  verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$TEXTBOOM_APK_SHA256" "textboom-before.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libc++_shared.so" "$TEXTBOOM_OLD_ARM_LIBCXX_SHA256" "textboom-arm32-libcxx-retained-dumped.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libc++_shared.so" "$ARM64_LIBCXX_SHA256" "textboom-arm64-libcxx-retained-dumped.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime.so" "$ARM64_LIBONNXRUNTIME_SHA256" "textboom-arm64-libonnxruntime-retained-dumped.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime4j_jni.so" "$ARM64_LIBONNXRUNTIME4J_SHA256" "textboom-arm64-libonnxruntime4j-retained-dumped.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libopencv_java4.so" "$ARM64_LIBOPENCV_SHA256" "textboom-arm64-libopencv-retained-dumped.so"

  write_arm32_runtime_libs "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime.so" "$ARM32_LIBONNXRUNTIME_SHA256" "textboom-arm32-libonnxruntime-dumped.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime4j_jni.so" "$ARM32_LIBONNXRUNTIME4J_SHA256" "textboom-arm32-libonnxruntime4j-dumped.so"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libopencv_java4.so" "$ARM32_LIBOPENCV_SHA256" "textboom-arm32-libopencv-dumped.so"

  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_B_IMG" "$TEXTBOOM_DIR" "textboom-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  bump_package_dir_time "$SYSTEM_B_IMG" "/system/app" "system-app" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$TEXTBOOM_APK_SHA256" "textboom-after.apk"
  verify_image_file_hash "$SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libc++_shared.so" "$TEXTBOOM_OLD_ARM_LIBCXX_SHA256" "textboom-arm32-libcxx-after-dumped.so"
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size system_b_fec_image "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-v0411-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-v0411-avb-info.txt" || die "system_b lost FEC roots"
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
    echo "purpose=Add 32-bit ORT/OpenCV runtime libraries for TextBoom app_process32 while keeping the v0.41 TextBoom APK unchanged."
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
    echo "textboom_apk_sha256=${TEXTBOOM_APK_SHA256}"
    echo "textboom_primary_cpu_abi_expected=armeabi-v7a"
    echo "textboom_runtime_arm32_lib_dir=${TEXTBOOM_LIB_ARM_DIR}"
    echo "textboom_runtime_arm64_lib_dir=${TEXTBOOM_LIB_ARM64_DIR}"
    echo "textboom_arm32_libcxx_policy=retain_existing_textboom_libcxx"
    echo "textboom_arm32_libcxx_sha256=${TEXTBOOM_OLD_ARM_LIBCXX_SHA256}"
    echo "textboom_arm32_libonnxruntime_sha256=${ARM32_LIBONNXRUNTIME_SHA256}"
    echo "textboom_arm32_libonnxruntime4j_jni_sha256=${ARM32_LIBONNXRUNTIME4J_SHA256}"
    echo "textboom_arm32_libopencv_java4_sha256=${ARM32_LIBOPENCV_SHA256}"
    echo "textboom_arm64_libcxx_sha256=${ARM64_LIBCXX_SHA256}"
    echo "textboom_arm64_libonnxruntime_sha256=${ARM64_LIBONNXRUNTIME_SHA256}"
    echo "textboom_arm64_libonnxruntime4j_jni_sha256=${ARM64_LIBONNXRUNTIME4J_SHA256}"
    echo "textboom_arm64_libopencv_java4_sha256=${ARM64_LIBOPENCV_SHA256}"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "fec_status=system_b_generated_roots_2_product_b_retained_from_v0352_roots_2"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_PRODUCT_B_IMG"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=${sparse_hash}"
  echo "system_b_sha256=${system_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V0411_TEXTBOOM_PPOCR_RUNTIME_ARM32_LIBS"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
