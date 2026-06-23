#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SERIAL="${SERIAL:-bb12d264}"

VARIANT="v0.41.1-textboom-ppocr-runtime-arm32-libs"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
EXPECTED_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024

TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"
TEXTBOOM_LIB_ARM64_DIR="/system/app/TextBoom/lib/arm64"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.41.1-textboom-ppocr-runtime-arm32-libs.sh --offline-image
  tools/r2-verify-v0.41.1-textboom-ppocr-runtime-arm32-libs.sh --read-only

Verifies the v0.41.1 TextBoom PP-OCR runtime ABI fix. --offline-image does not
touch a device. --read-only collects live state only and must be run escalated.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1" path="$2" key="$3" expected actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
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

verify_avb_fec() {
  local label="$1" image="$2" partition_size="$3" ext4_size="$4" info
  info="${WORK_DIR}/${label}-avb-info.txt"
  "$PYTHON_BIN" "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${partition_size} bytes" "$info" || die "${label} AVB image size mismatch"
  grep -q "Original image size:      ${ext4_size} bytes" "$info" || die "${label} AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "${label} lost FEC roots"
  echo "${label}_avb_fec=ok"
}

verify_image_file_hash() {
  local image="$1" path="$2" key="$3" label="$4" expected out actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  out="${WORK_DIR}/${label}"
  debugfs_path_exists "$image" "$path" || die "missing image path: ${path}"
  debugfs_dump "$image" "$path" "$out"
  actual="$(sha256_one "$out")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_offline_image() {
  local ts report
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-${ts}.txt"
  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  rm -rf "${WORK_DIR:?}"/*
  {
    echo "# ${VARIANT} offline verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=read-only offline verifier; no device access"
    echo
    echo "## hashes"
    check_manifest_hash "sparse_super" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "system_b" "$EXPECTED_SYSTEM_B_IMG" "system_b_sha256"
    check_manifest_hash "product_b" "$EXPECTED_PRODUCT_B_IMG" "product_b_sha256"
    echo
    echo "## image sizes and FEC"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b size mismatch"
    [ "$(size_bytes "$EXPECTED_PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] || die "product_b size mismatch"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec system_b "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE" "$SYSTEM_B_EXT4_SIZE"
    verify_avb_fec product_b "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE" "$PRODUCT_B_EXT4_SIZE"
    echo
    echo "## TextBoom APK and native libraries"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_PATH" "textboom_apk_sha256" "textboom.apk"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libc++_shared.so" "textboom_arm32_libcxx_sha256" "arm32-libcxx.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime.so" "textboom_arm32_libonnxruntime_sha256" "arm32-libonnxruntime.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime4j_jni.so" "textboom_arm32_libonnxruntime4j_jni_sha256" "arm32-libonnxruntime4j_jni.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM_DIR}/libopencv_java4.so" "textboom_arm32_libopencv_java4_sha256" "arm32-libopencv_java4.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libc++_shared.so" "textboom_arm64_libcxx_sha256" "arm64-libcxx.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime.so" "textboom_arm64_libonnxruntime_sha256" "arm64-libonnxruntime.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime4j_jni.so" "textboom_arm64_libonnxruntime4j_jni_sha256" "arm64-libonnxruntime4j_jni.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${TEXTBOOM_LIB_ARM64_DIR}/libopencv_java4.so" "textboom_arm64_libopencv_java4_sha256" "arm64-libopencv_java4.so"
    echo
    echo "result=PASS_OFFLINE_IMAGE_V0411_TEXTBOOM_PPOCR_RUNTIME_ARM32_LIBS"
  } > "$report"
  cat "$report"
  echo "Report: $report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_shell() {
  adb -s "$SERIAL" shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@" 2>&1 | tr -d '\r'
}

live_sha256() {
  local path="$1"
  root_cmd "sha256sum ${path} 2>/dev/null || toybox sha256sum ${path} 2>/dev/null" | awk '{print $1}' | sed -n '1p'
}

require_live_manifest_hash() {
  local label="$1" path="$2" key="$3" expected actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  actual="$(live_sha256 "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected} path=${path}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_read_only_device() {
  local ts report slot boot bootanim root_id pkg_state keyguard_line
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-${ts}.txt"
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  {
    echo "# ${VARIANT} live read-only verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=read-only live verifier; no flash, no reboot, no package mutation, no /data cleanup"
    echo
    adb devices -l | tr -d '\r'
    adb_available || die "adb device ${SERIAL} is not online"
    boot="$(adb_shell 'getprop sys.boot_completed' | tail -n 1)"
    slot="$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)"
    bootanim="$(adb_shell 'getprop init.svc.bootanim' | tail -n 1)"
    printf 'sys.boot_completed=%s\nro.boot.slot_suffix=%s\ninit.svc.bootanim=%s\n' "$boot" "$slot" "$bootanim"
    [ "$boot" = "1" ] || die "boot not completed"
    [ "$slot" = "_b" ] || die "unexpected slot: ${slot}"
    root_id="$(root_cmd 'id; getenforce; getprop ro.boot.slot_suffix' || true)"
    printf '%s\n' "$root_id"
    grep -q 'uid=0(root)' <<<"$root_id" || die "root uid=0 missing"
    echo
    echo "## TextBoom package ABI"
    pkg_state="$(adb_shell 'dumpsys package com.smartisanos.textboom 2>/dev/null | grep -E "codePath=|resourcePath=|primaryCpuAbi=|secondaryCpuAbi=|UPDATED_SYSTEM_APP" | sed -n "1,80p" || true')"
    printf '%s\n' "$pkg_state"
    grep -q 'codePath=/system/app/TextBoom' <<<"$pkg_state" || die "TextBoom not served from system"
    grep -q 'primaryCpuAbi=armeabi-v7a' <<<"$pkg_state" || die "TextBoom primaryCpuAbi is not armeabi-v7a"
    if grep -q 'UPDATED_SYSTEM_APP' <<<"$pkg_state"; then
      die "TextBoom still has UPDATED_SYSTEM_APP shadow"
    fi
    echo
    echo "## live hashes"
    require_live_manifest_hash "textboom" "$TEXTBOOM_PATH" "textboom_apk_sha256"
    require_live_manifest_hash "arm32-libcxx" "${TEXTBOOM_LIB_ARM_DIR}/libc++_shared.so" "textboom_arm32_libcxx_sha256"
    require_live_manifest_hash "arm32-libonnxruntime" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime.so" "textboom_arm32_libonnxruntime_sha256"
    require_live_manifest_hash "arm32-libonnxruntime4j_jni" "${TEXTBOOM_LIB_ARM_DIR}/libonnxruntime4j_jni.so" "textboom_arm32_libonnxruntime4j_jni_sha256"
    require_live_manifest_hash "arm32-libopencv_java4" "${TEXTBOOM_LIB_ARM_DIR}/libopencv_java4.so" "textboom_arm32_libopencv_java4_sha256"
    require_live_manifest_hash "arm64-libopencv_java4" "${TEXTBOOM_LIB_ARM64_DIR}/libopencv_java4.so" "textboom_arm64_libopencv_java4_sha256"
    echo
    adb_shell 'ls -lZ /system/app/TextBoom/lib/arm /system/app/TextBoom/lib/arm64 2>/dev/null || true'
    keyguard_line="$(adb_shell 'dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen" | sed -n "1,80p" || true')"
    printf '%s\n' "$keyguard_line"
    if grep -Eq 'isKeyguardShowing=true|mShowingLockscreen=true' <<<"$keyguard_line"; then
      die "keyguard still showing"
    fi
    echo
    echo "result=PASS_READ_ONLY_V0411_TEXTBOOM_PPOCR_RUNTIME_ARM32_LIBS"
  } > "$report"
  cat "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) mode="offline" ;;
  --read-only) mode="read-only" ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_file "$AVBTOOL"
need_file "$MANIFEST"
if [ "$mode" = "read-only" ]; then
  verify_read_only_device
else
  need_executable "$DEBUGFS"
  need_executable "$E2FSCK"
  verify_offline_image
fi
