#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SERIAL="${SERIAL:-bb12d264}"

VARIANT="${VARIANT:-v0.42-textboom-ppocr-preview-path}"
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
AUTO_DISMISS_KEYGUARD="${AUTO_DISMISS_KEYGUARD:-0}"
NEW_OCR_DIR="${NEW_OCR_DIR:-/Android/data/com.smartisanos.textboom/files/.boom}"
OLD_OCR_DIR="${OLD_OCR_DIR:-/.boom}"
EXPECT_LEGACY_CSOCR_REMOVED="${EXPECT_LEGACY_CSOCR_REMOVED:-0}"
EXPECT_OCR_KEY_REMOVED="${EXPECT_OCR_KEY_REMOVED:-0}"
TEXTBOOM_PRIMARY_CPU_ABI="${TEXTBOOM_PRIMARY_CPU_ABI:-armeabi-v7a}"
TEXTBOOM_ARM64_LIBS_EXPECTED="${TEXTBOOM_ARM64_LIBS_EXPECTED:-}"
TEXTBOOM_APK_ARM64_LIBS_EXPECTED="${TEXTBOOM_APK_ARM64_LIBS_EXPECTED:-}"
RESULT_OFFLINE="${RESULT_OFFLINE:-PASS_OFFLINE_IMAGE_V042_TEXTBOOM_PPOCR_PREVIEW_PATH}"
RESULT_READ_ONLY="${RESULT_READ_ONLY:-PASS_READ_ONLY_V042_TEXTBOOM_PPOCR_PREVIEW_PATH}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.42-textboom-preview-path.sh --offline-image
  tools/r2-verify-v0.42-textboom-preview-path.sh --read-only

Verifies the v0.42 TextBoom preview-path candidate. Environment overrides may
select a follow-up VARIANT/NEW_OCR_DIR. --offline-image does not touch a
device. --read-only collects live state only and must be run escalated.
USAGE
}

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

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

manifest_value_or_default() {
  local key="$1" fallback="$2" value
  value="$(manifest_value "$key")"
  if [ -n "$value" ]; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

textboom_apk_path() {
  manifest_value_or_default textboom_target_system_path "$TEXTBOOM_PATH"
}

textboom_code_path_expected() {
  local fallback
  fallback="$(dirname "$(textboom_apk_path)")"
  manifest_value_or_default textboom_code_path_expected "$fallback"
}

textboom_lib_arm_dir() {
  manifest_value_or_default textboom_lib_arm_dir "$TEXTBOOM_LIB_ARM_DIR"
}

textboom_lib_arm64_dir() {
  manifest_value_or_default textboom_lib_arm64_dir "$TEXTBOOM_LIB_ARM64_DIR"
}

textboom_arm64_libs_expected() {
  local retained
  if [ -n "$TEXTBOOM_ARM64_LIBS_EXPECTED" ]; then
    echo "$TEXTBOOM_ARM64_LIBS_EXPECTED"
    return
  fi
  retained="$(manifest_value textboom_arm64_libs_retained)"
  case "$retained" in
    false|0) echo 0 ;;
    *) echo 1 ;;
  esac
}

textboom_apk_arm64_libs_expected() {
  local retained
  if [ -n "$TEXTBOOM_APK_ARM64_LIBS_EXPECTED" ]; then
    echo "$TEXTBOOM_APK_ARM64_LIBS_EXPECTED"
    return
  fi
  retained="$(manifest_value textboom_apk_arm64_libs_retained)"
  case "$retained" in
    false|0) echo 0 ;;
    true|1) echo 1 ;;
    *) textboom_arm64_libs_expected ;;
  esac
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

verify_image_path_absent() {
  local image="$1" path="$2" label="$3"
  if debugfs_path_exists "$image" "$path"; then
    die "${label} unexpectedly exists: ${path}"
  fi
  printf '%s\tabsent\t%s\n' "$label" "$path"
}

verify_preview_apk_payload() {
  local apk="$1" label="$2" strings_file manifest_strings_file apk_arm64_expected
  apk_arm64_expected="$(textboom_apk_arm64_libs_expected)"
  strings_file="${WORK_DIR}/${label}.classes2.strings"
  manifest_strings_file="${WORK_DIR}/${label}.manifest.strings"
  unzip -t "$apk" >/dev/null || die "${label} zip test failed"
  if [ "$apk_arm64_expected" = "1" ]; then
    zip_has_prefix "$apk" 'lib/arm64-v8a/' || die "${label} missing APK-internal arm64 libs"
  else
    if zip_has_prefix "$apk" 'lib/arm64-v8a/'; then
      die "${label} still contains APK-internal arm64 libs"
    fi
  fi
  unzip -p "$apk" classes2.dex | strings > "$strings_file"
  unzip -p "$apk" AndroidManifest.xml | strings > "$manifest_strings_file"
  grep -q "$NEW_OCR_DIR" "$strings_file" || die "${label} missing new OCR preview dir"
  if grep -Fxq "$OLD_OCR_DIR" "$strings_file"; then
    die "${label} still contains standalone old OCR preview dir"
  fi
  grep -q "LocalPpOcrApi" "$strings_file" || die "${label} lost LocalPpOcrApi"
  grep -q "LocalPpOcrRuntime" "$strings_file" || die "${label} lost LocalPpOcrRuntime"
  if [ "$EXPECT_LEGACY_CSOCR_REMOVED" = "1" ]; then
    if grep -Eq 'CsOcr|Lcom/intsig|com/intsig|CSOCR' "$strings_file"; then
      die "${label} still contains legacy CsOcr/Intsig code strings"
    fi
  fi
  if [ "$EXPECT_OCR_KEY_REMOVED" = "1" ]; then
    if grep -q 'ocr_key' "$manifest_strings_file"; then
      die "${label} still contains manifest ocr_key"
    fi
  fi
  echo "${label}_preview_path=ok"
}

verify_offline_image() {
  local ts report textboom_dump arm64_expected textboom_path arm_dir arm64_dir old_public_absent old_public_path held_path
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-${ts}.txt"
  arm64_expected="$(textboom_arm64_libs_expected)"
  textboom_path="$(textboom_apk_path)"
  arm_dir="$(textboom_lib_arm_dir)"
  arm64_dir="$(textboom_lib_arm64_dir)"
  old_public_absent="$(manifest_value textboom_old_public_apk_absent)"
  old_public_path="$(manifest_value_or_default textboom_old_public_apk_path "$TEXTBOOM_PATH")"
  held_path="$(manifest_value textboom_old_public_held_path)"
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
    echo "## TextBoom APK, preview path, and runtime libraries"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "$textboom_path" "textboom_apk_sha256" "textboom.apk"
    textboom_dump="${WORK_DIR}/textboom.apk"
    verify_preview_apk_payload "$textboom_dump" "textboom.apk"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm_dir}/libc++_shared.so" "textboom_arm32_libcxx_sha256" "arm32-libcxx.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm_dir}/libonnxruntime.so" "textboom_arm32_libonnxruntime_sha256" "arm32-libonnxruntime.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm_dir}/libonnxruntime4j_jni.so" "textboom_arm32_libonnxruntime4j_jni_sha256" "arm32-libonnxruntime4j_jni.so"
    verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm_dir}/libopencv_java4.so" "textboom_arm32_libopencv_java4_sha256" "arm32-libopencv_java4.so"
    if [ "$arm64_expected" = "1" ]; then
      verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm64_dir}/libc++_shared.so" "textboom_arm64_libcxx_sha256" "arm64-libcxx.so"
      verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm64_dir}/libonnxruntime.so" "textboom_arm64_libonnxruntime_sha256" "arm64-libonnxruntime.so"
      verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm64_dir}/libonnxruntime4j_jni.so" "textboom_arm64_libonnxruntime4j_jni_sha256" "arm64-libonnxruntime4j_jni.so"
      verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "${arm64_dir}/libopencv_java4.so" "textboom_arm64_libopencv_java4_sha256" "arm64-libopencv_java4.so"
    else
      verify_image_path_absent "$EXPECTED_SYSTEM_B_IMG" "$arm64_dir" "arm64-lib-dir"
    fi
    if [ "$old_public_absent" = "true" ]; then
      verify_image_path_absent "$EXPECTED_SYSTEM_B_IMG" "$old_public_path" "textboom-old-public-apk"
      if [ -n "$held_path" ]; then
        verify_image_file_hash "$EXPECTED_SYSTEM_B_IMG" "$held_path" "textboom_source_apk_sha256" "textboom-old-held.apk"
      fi
    fi
    echo "expected_preview_path=$(manifest_value textboom_preview_expected_path)"
    echo
    echo "result=${RESULT_OFFLINE}"
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

require_live_path_absent() {
  local path="$1" probe
  probe="$(root_cmd "[ ! -e '${path}' ] && echo absent || echo present" | tail -n 1)"
  [ "$probe" = "absent" ] || die "live path unexpectedly exists: ${path}"
  printf 'absent\t%s\n' "$path"
}

maybe_auto_dismiss_keyguard() {
  [ "$AUTO_DISMISS_KEYGUARD" = "1" ] || return 0
  echo
  echo "## auto keyguard dismiss attempt"
  adb_shell 'input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; cmd window dismiss-keyguard >/dev/null 2>&1 || true; wm dismiss-keyguard >/dev/null 2>&1 || true; input keyevent 82 >/dev/null 2>&1 || true; input keyevent HOME >/dev/null 2>&1 || true' >/dev/null || true
  sleep 2
  echo "auto_dismiss_keyguard=attempted"
}

verify_read_only_device() {
  local ts report slot boot bootanim root_id pkg_state keyguard_line arm64_expected textboom_path code_path arm_dir arm64_dir old_public_absent old_public_path held_path
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-${ts}.txt"
  arm64_expected="$(textboom_arm64_libs_expected)"
  textboom_path="$(textboom_apk_path)"
  code_path="$(textboom_code_path_expected)"
  arm_dir="$(textboom_lib_arm_dir)"
  arm64_dir="$(textboom_lib_arm64_dir)"
  old_public_absent="$(manifest_value textboom_old_public_apk_absent)"
  old_public_path="$(manifest_value_or_default textboom_old_public_apk_path "$TEXTBOOM_PATH")"
  held_path="$(manifest_value textboom_old_public_held_path)"
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  {
    echo "# ${VARIANT} live read-only verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=live verifier; no flash, no reboot, no package mutation, no /data cleanup; optional UI-only keyguard dismiss=${AUTO_DISMISS_KEYGUARD}"
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
    maybe_auto_dismiss_keyguard
    echo
    echo "## TextBoom package ABI"
    pkg_state="$(adb_shell 'dumpsys package com.smartisanos.textboom 2>/dev/null | grep -E "codePath=|resourcePath=|primaryCpuAbi=|secondaryCpuAbi=|UPDATED_SYSTEM_APP" | sed -n "1,80p" || true')"
    printf '%s\n' "$pkg_state"
    grep -q "codePath=${code_path}" <<<"$pkg_state" || die "TextBoom not served from expected codePath: ${code_path}"
    grep -q "primaryCpuAbi=${TEXTBOOM_PRIMARY_CPU_ABI}" <<<"$pkg_state" || die "TextBoom primaryCpuAbi is not ${TEXTBOOM_PRIMARY_CPU_ABI}"
    if grep -q 'UPDATED_SYSTEM_APP' <<<"$pkg_state"; then
      die "TextBoom still has UPDATED_SYSTEM_APP shadow"
    fi
    echo
    echo "## live hashes"
    require_live_manifest_hash "textboom" "$textboom_path" "textboom_apk_sha256"
    require_live_manifest_hash "arm32-libonnxruntime" "${arm_dir}/libonnxruntime.so" "textboom_arm32_libonnxruntime_sha256"
    require_live_manifest_hash "arm32-libopencv_java4" "${arm_dir}/libopencv_java4.so" "textboom_arm32_libopencv_java4_sha256"
    if [ "$arm64_expected" = "1" ]; then
      require_live_manifest_hash "arm64-libopencv_java4" "${arm64_dir}/libopencv_java4.so" "textboom_arm64_libopencv_java4_sha256"
    else
      require_live_path_absent "$arm64_dir"
    fi
    if [ "$old_public_absent" = "true" ]; then
      require_live_path_absent "$old_public_path"
      if [ -n "$held_path" ]; then
        require_live_manifest_hash "textboom-old-held" "$held_path" "textboom_source_apk_sha256"
      fi
    fi
    echo
    keyguard_line="$(adb_shell 'dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen" | sed -n "1,80p" || true')"
    printf '%s\n' "$keyguard_line"
    if grep -Eq 'isKeyguardShowing=true|mShowingLockscreen=true' <<<"$keyguard_line"; then
      die "keyguard still showing"
    fi
    echo
    echo "result=${RESULT_READ_ONLY}"
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
need_command unzip
need_command zipinfo
need_command strings
if [ "$mode" = "read-only" ]; then
  verify_read_only_device
else
  need_executable "$DEBUGFS"
  need_executable "$E2FSCK"
  verify_offline_image
fi
