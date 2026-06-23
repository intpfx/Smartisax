#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
AAPT="${AAPT:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="${VARIANT:-v0.37a-textboom-live-system-base}"
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

TEXTBOOM_PACKAGE="com.smartisanos.textboom"
TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_DIR="/system/app/TextBoom"
TEXTBOOM_HELD_PATH="/system/app/TextBoom/.TextBoom.apk.smartisax-v037a-stock-held"
SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
LAUNCHER_APK="/system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk"
SMARTISAX_APK="/system/app/SmartisaxShell/SmartisaxShell.apk"

EXPECTED_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
EXPECTED_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
EXPECTED_LAUNCHER_SHA256="f3d5af9cf17c56b93462a7d596ed1c7b246a93b32ebc129dbfe14296eaf7ddb6"
EXPECTED_SMARTISAX_SHA256="7b1f70ca713260201e49ee3e3cc8ebec35ac3d59e199179a1e048860bb896753"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.37a-textboom-live-system-base.sh --offline-image
  tools/r2-verify-v0.37a-textboom-live-system-base.sh --read-only-pre-clean
  tools/r2-verify-v0.37a-textboom-live-system-base.sh --read-only-post-clean

--offline-image verifies the v0.37a candidate without touching a device.
--read-only-pre-clean expects the device may still use the /data/app TextBoom
updated-system shadow after flash.
--read-only-post-clean expects TextBoom to resolve from /system/app/TextBoom
after a separately confirmed PackageManager cleanup.
USAGE
}

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

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1"
  local path="$2"
  local key="$3"
  local expected
  local actual
  need_file "$MANIFEST"
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
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

verify_avb_fec() {
  local label="$1"
  local image="$2"
  local partition_size="$3"
  local ext4_size="$4"
  local info="${WORK_DIR}/${label}-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${partition_size} bytes" "$info" \
    || die "${label} AVB image size mismatch"
  grep -q "Original image size:      ${ext4_size} bytes" "$info" \
    || die "${label} AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "${label} lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "${label} missing FEC offset"
  echo "${label}_avb_fec=ok"
}

verify_apk_hash() {
  local image="$1"
  local path="$2"
  local expected="$3"
  local label="$4"
  local out="${WORK_DIR}/${label}.apk"
  debugfs_dump "$image" "$path" "$out"
  [ "$(sha256_one "$out")" = "$expected" ] || die "${label} hash mismatch"
  unzip -t "$out" >/dev/null || die "${label} zip integrity failed"
  printf '%s\tsha256=%s\t%s\n' "$label" "$expected" "$path"
}

verify_textboom_apk_contract() {
  local apk="$1"
  local badging="${WORK_DIR}/textboom-aapt-badging.txt"
  local sig="${WORK_DIR}/textboom-signature-boundary.txt"
  "$AAPT" dump badging "$apk" > "$badging"
  grep -q "package: name='${TEXTBOOM_PACKAGE}' versionCode='104' versionName='3.2.2'" "$badging" \
    || die "TextBoom package/version contract mismatch"
  grep -q "native-code: 'armeabi-v7a'" "$badging" || die "TextBoom native-code contract mismatch"
  unzip -Z -1 "$apk" | grep -x 'assets/tt_general_ocr_v1.0.model' >/dev/null \
    || die "TextBoom missing local OCR model asset"
  if unzip -Z -1 "$apk" | grep 'libsmash_ocr_lib\.so' >/dev/null; then
    die "TextBoom unexpectedly contains libsmash_ocr_lib.so; revisit SmashOcr route"
  fi
  "$SIGCHECK" "$apk" > "$sig"
  grep -q '^apk_sig_block_magic=absent$' "$sig" || die "TextBoom v2/v3 signing block state changed"
  grep -q '^keytool_status=0$' "$sig" || die "TextBoom keytool certificate read failed"
  grep -q '^jarsigner_status=0$' "$sig" || die "TextBoom JAR signature verify failed"
  echo "textboom_apk_contract=ok versionCode=104 versionName=3.2.2 manifest_edit=no signature=v1_jar_verified"
}

write_report_header() {
  local report="$1"
  {
    echo "# ${VARIANT} verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "serial=${SERIAL}"
    echo "report=${report#${ROOT_DIR}/}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no package-cache clear, no /data cleanup"
    echo
  } > "$report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$1" 2>&1 | tr -d '\r'
}

sq() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

verify_offline_image() {
  local ts
  local report
  local textboom_hash
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-${ts}.txt"
  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.txt
  write_report_header "$report"

  {
    echo "## manifest hashes"
    check_manifest_hash "sparse_super" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "system_b" "$EXPECTED_SYSTEM_B_IMG" "system_b_sha256"
    check_manifest_hash "product_b" "$EXPECTED_PRODUCT_B_IMG" "product_b_sha256"
    check_manifest_hash "textboom_apk" "$(manifest_value textboom_apk)" "textboom_apk_sha256"
    echo

    echo "## image sizes and FEC"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b partition size mismatch"
    [ "$(size_bytes "$EXPECTED_PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] || die "product_b partition size mismatch"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec system_b "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE" "$SYSTEM_B_EXT4_SIZE"
    verify_avb_fec product_b "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE" "$PRODUCT_B_EXT4_SIZE"
    echo

    echo "## system_b APK contracts"
    textboom_hash="$(manifest_value textboom_apk_sha256)"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_PATH" "$textboom_hash" "textboom-system"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$EXPECTED_WEBVIEW_SHA256" "system-webview"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$EXPECTED_BROWSERCHROME_SHA256" "browserchrome"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$LAUNCHER_APK" "$EXPECTED_LAUNCHER_SHA256" "launcher"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$SMARTISAX_APK" "$EXPECTED_SMARTISAX_SHA256" "smartisax"
    debugfs_path_exists "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_HELD_PATH" || die "held stock TextBoom APK missing"
    verify_textboom_apk_contract "${WORK_DIR}/textboom-system.apk"
    echo "textboom_held_stock_path=present ${TEXTBOOM_HELD_PATH}"
    echo

    echo "## package-cache invalidation"
    grep -q '^package_dir_mtime_hex=0x6a3687c8$' "$MANIFEST" || die "manifest package dir mtime mismatch"
    grep -q '^textboom_manifest_edit=no$' "$MANIFEST" || die "manifest edit boundary mismatch"
    grep -q '^textboom_data_shadow_expected=yes_until_explicit_cleanup$' "$MANIFEST" || die "data shadow gate mismatch"
    echo "package_dir_mtime=ok 0x6a3687c8"
    echo "data_cleanup_gate=explicit_required"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V037A_TEXTBOOM_LIVE_SYSTEM_BASE"
  } 2>&1 | tee -a "$report"
  echo "PASS: ${VARIANT} offline image verification"
  echo "report=${report}"
}

verify_device_readonly() {
  local mode="$1"
  local ts
  local report
  local pkg
  local quoted
  local pm_path
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-${mode}-${ts}.txt"
  pkg="$TEXTBOOM_PACKAGE"
  quoted="$(sq "$pkg")"
  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  write_report_header "$report"

  {
    echo "## adb state"
    if ! adb_available; then
      adb devices -l || true
      die "adb device ${SERIAL} is not online"
    fi
    adb_shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop sys.usb.state'
    echo
    "$ROOT_HELPER" status
    echo

    echo "## package state"
    pm_path="$(adb_shell "pm path ${quoted} 2>/dev/null || true")"
    printf '%s\n' "$pm_path"
    adb_shell "cmd package list packages -u -f | grep -F ${quoted} || true"
    adb_shell "dumpsys package ${quoted} | grep -E 'Package \\[|codePath=|resourcePath=|legacyNativeLibraryDir=|versionCode=|versionName=|pkgFlags=|privateFlags=|User 0:' | sed -n '1,120p'"
    echo

    echo "## system file state"
    root_cmd "sha256sum ${TEXTBOOM_PATH} 2>/dev/null || true"
    root_cmd "ls -lZ ${TEXTBOOM_DIR} ${TEXTBOOM_PATH} 2>/dev/null || true"
    echo

    if [ "$mode" = "read-only-post-clean" ]; then
      grep -q "^package:${TEXTBOOM_PATH}$" <<<"$pm_path" \
        || die "post-clean TextBoom is not served from ${TEXTBOOM_PATH}"
      if adb_shell "dumpsys package ${quoted} | grep -q UPDATED_SYSTEM_APP && echo shadow || true" | grep -q shadow; then
        die "post-clean TextBoom still has UPDATED_SYSTEM_APP flag"
      fi
      echo "textboom_active_path=system"
      echo "textboom_updated_system_shadow=absent"
      echo "result=PASS_DEVICE_READ_ONLY_V037A_TEXTBOOM_POST_CLEAN"
    else
      if grep -q '^package:/data/app/' <<<"$pm_path"; then
        echo "textboom_active_path=data_shadow"
        echo "textboom_data_cleanup_next=explicit_confirmation_required"
      elif grep -q "^package:${TEXTBOOM_PATH}$" <<<"$pm_path"; then
        echo "textboom_active_path=system_unexpected_auto_takeover"
      else
        die "unexpected TextBoom pm path: ${pm_path}"
      fi
      echo "result=PASS_DEVICE_READ_ONLY_V037A_TEXTBOOM_PRE_CLEAN"
    fi
  } 2>&1 | tee -a "$report"

  echo "PASS: ${VARIANT} ${mode} device read-only verification"
  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$DEBUGFS"
    need_executable "$E2FSCK"
    need_executable "$AAPT"
    need_executable "$SIGCHECK"
    need_file "$AVBTOOL"
    verify_offline_image
    ;;
  --read-only-pre-clean)
    verify_device_readonly "read-only-pre-clean"
    ;;
  --read-only-post-clean)
    verify_device_readonly "read-only-post-clean"
    ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
