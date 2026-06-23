#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
APKTOOL_JAR="${APKTOOL_JAR:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="v0.wadb1-smartisax-priv-wireless-adb"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
SUPER_MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
OLD_SMARTISAX_DIR="/system/app/SmartisaxShell"
NEW_SMARTISAX_APK_PATH="/system/priv-app/SmartisaxShell/SmartisaxShell.apk"
PRIVAPP_XML_PATH="/system/etc/permissions/privapp-permissions-com.smartisax.browser.xml"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.wadb1-smartisax-priv-wireless-adb.sh --offline-image
  tools/r2-verify-v0.wadb1-smartisax-priv-wireless-adb.sh --read-only

--offline-image verifies the candidate without touching a device:
  - sparse/system_b hashes match manifests
  - system_b has AVB/FEC roots=2 and passes e2fsck
  - /system/app/SmartisaxShell is absent
  - /system/priv-app/SmartisaxShell/SmartisaxShell.apk is present and matches
  - Smartisax requests MANAGE_DEBUGGING and WRITE_SECURE_SETTINGS
  - privapp-permissions-com.smartisax.browser.xml is present and matches
  - sparse system_b slice equals the generated system_b image

--read-only verifies a flashed device without changing /data.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

manifest_value() {
  local manifest="$1" key="$2"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2); exit}' "$manifest"
}

check_manifest_hash() {
  local manifest="$1" label="$2" path="$3" key="$4" expected actual
  need_file "$manifest"
  expected="$(manifest_value "$manifest" "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}: ${manifest}"
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
  local image="$1" info="${WORK_DIR}/system-b-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "$info" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "$info" || die "system_b AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "system_b lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "system_b missing FEC offset"
  echo "system_b_avb_fec=ok"
}

verify_apk_semantics() {
  local apk="$1" decode_dir="${WORK_DIR}/smartisax-apk-decoded"
  rm -rf "$decode_dir"
  PATH="$(dirname "$JAVA"):${PATH}" "$JAVA" -jar "$APKTOOL_JAR" d -f "$apk" -o "$decode_dir" >/dev/null
  grep -q 'android.permission.MANAGE_DEBUGGING' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing MANAGE_DEBUGGING"
  grep -q 'android.permission.WRITE_SECURE_SETTINGS' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing WRITE_SECURE_SETTINGS"
  grep -R -q 'SmartisaxNative' "${decode_dir}/smali" || die "SmartisaxNative bridge missing from dex"
  grep -R -q 'removeJavascriptInterface' "${decode_dir}/smali" || die "bridge removal guard missing from dex"
  grep -R -q 'allowWirelessDebugging' "${decode_dir}/smali" || die "wireless adb privileged call missing from dex"
  grep -R -q 'adb_wifi_enabled' "${decode_dir}/smali" || die "wireless adb setting path missing from dex"
  echo "smartisax_apk_semantics=ok"
}

verify_privapp_xml() {
  local xml="$1"
  grep -q '<privapp-permissions package="com.smartisax.browser">' "$xml" || die "privapp XML missing package block"
  grep -q 'android.permission.MANAGE_DEBUGGING' "$xml" || die "privapp XML missing MANAGE_DEBUGGING"
  grep -q 'android.permission.WRITE_SECURE_SETTINGS' "$xml" || die "privapp XML missing WRITE_SECURE_SETTINGS"
  echo "smartisax_privapp_xml=ok"
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

run_offline_image() {
  need_executable "$E2FSCK"
  need_executable "$DEBUGFS"
  need_executable "$JAVA"
  need_file "$AVBTOOL"
  need_file "$SPARSE_TOOL"
  need_file "$APKTOOL_JAR"

  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} offline image verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo "boundary=offline verifier only; no adb, no fastboot, no flash, no reboot, no /data mutation"
    echo

    echo "## local files"
    check_manifest_hash "$SUPER_MANIFEST" "candidate_sparse" "$SUPER_SPARSE" "super_sparse_sha256"
    check_manifest_hash "$SUPER_MANIFEST" "system_b_image" "$SYSTEM_B_IMG" "system_b_sha256"
    smartisax_expected="$(manifest_value "$SUPER_MANIFEST" smartisax_apk_sha256)"
    privapp_expected="$(manifest_value "$SUPER_MANIFEST" privapp_xml_sha256)"
    [ -n "$smartisax_expected" ] || die "manifest missing smartisax_apk_sha256"
    [ -n "$privapp_expected" ] || die "manifest missing privapp_xml_sha256"
    echo

    echo "## system_b"
    "$E2FSCK" -fn "$SYSTEM_B_IMG" >/dev/null
    echo "system_b_fsck=ok"
    verify_avb_fec "$SYSTEM_B_IMG"
    ! debugfs_path_exists "$SYSTEM_B_IMG" "$OLD_SMARTISAX_DIR" || die "old Smartisax system app path still exists"
    debugfs_dump "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "${WORK_DIR}/smartisax-priv-app.apk"
    debugfs_dump "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml"
    [ "$(sha256_one "${WORK_DIR}/smartisax-priv-app.apk")" = "$smartisax_expected" ] || die "Smartisax APK hash mismatch"
    [ "$(sha256_one "${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml")" = "$privapp_expected" ] || die "Smartisax privapp XML hash mismatch"
    unzip -t "${WORK_DIR}/smartisax-priv-app.apk" >/dev/null
    verify_apk_semantics "${WORK_DIR}/smartisax-priv-app.apk"
    verify_privapp_xml "${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml"
    "$SPARSE_TOOL" \
      --source-sparse "$SUPER_SPARSE" \
      --extent "$SYSTEM_B_EXTENT" \
      --verify-image "system_b=${SYSTEM_B_IMG}"
    echo "sparse_system_b_slice=ok"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0WADB1_SMARTISAX_PRIV_WIRELESS_ADB"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

run_read_only() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} device read-only verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo "serial=${SERIAL}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no /data cleanup"
    echo

    echo "## adb"
    adb devices -l
    adb_available || die "adb device ${SERIAL} is not online"
    echo

    echo "## boot state"
    adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root"
    "$ROOT_HELPER" status || warn "root status failed"
    echo

    echo "## Smartisax package"
    pm_path="$(adb_shell 'pm path com.smartisax.browser | head -n1')"
    echo "$pm_path"
    [[ "$pm_path" == "package:${NEW_SMARTISAX_APK_PATH}" ]] || die "Smartisax is not served from priv-app"
    adb_shell 'dumpsys package com.smartisax.browser | grep -E "codePath=|resourcePath=|versionCode=|pkgFlags=|privateFlags=|android.permission.(MANAGE_DEBUGGING|WRITE_SECURE_SETTINGS|ACCESS_WIFI_STATE):" || true'
    root_cmd "[ ! -e ${OLD_SMARTISAX_DIR} ] && echo old_smartisax_system_app=absent || { echo old_smartisax_system_app=present; ls -ld ${OLD_SMARTISAX_DIR}; }"
    root_cmd "[ -f ${PRIVAPP_XML_PATH} ] && echo smartisax_privapp_xml=present || echo smartisax_privapp_xml=absent"
    echo

    echo "## wireless adb state"
    adb_shell 'settings get global adb_wifi_enabled; service call adb 10 2>/dev/null || true'
    echo

    echo "result=PASS_READ_ONLY_V0WADB1_SMARTISAX_PRIV_WIRELESS_ADB"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) run_offline_image ;;
  --read-only) run_read_only ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
