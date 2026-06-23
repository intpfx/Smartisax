#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
APK_GATE_VERIFIER="${APK_GATE_VERIFIER:-${ROOT_DIR}/tools/r2-verify-systemui-certprobe-noop-apk.sh}"

SYSTEMUI_NOOP_VARIANT="${SYSTEMUI_NOOP_VARIANT:-systemui-certprobe-noop}"
EXPECTED_SUPER="${EXPECTED_SUPER:-${ROOT_DIR}/hard-rom/build/super-otatrust-${SYSTEMUI_NOOP_VARIANT}-exact-current.sparse.img}"
EXPECTED_SYSTEM_EXT_IMG="${EXPECTED_SYSTEM_EXT_IMG:-${ROOT_DIR}/hard-rom/build/system_ext-otatrust-${SYSTEMUI_NOOP_VARIANT}.img}"
EXPECTED_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk"
STOCK_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${SYSTEMUI_NOOP_VARIANT}}"

SYSTEMUI_IMAGE_PATH="/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
SYSTEMUI_DEVICE_PATH="/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-systemui-certprobe-noop.sh --offline-image
  tools/r2-verify-systemui-certprobe-noop.sh --read-only

--offline-image verifies the generated SystemUI no-op ROM candidate on the Mac:
  - APK no-op scope verifier passes
  - SmartisanSystemUI inside system_ext image matches the same-size no-op APK
  - final sparse super's system_ext_b logical slice matches the system_ext image

--read-only verifies after a future flash on the live device:
  - boot/slot/root/window/package/logcat evidence is captured
  - pulled SmartisanSystemUI APK matches the expected no-op APK

This script never flashes, reboots, erases misc, or changes /data.

Environment:
  SYSTEMUI_NOOP_VARIANT=<name>  report/output variant; defaults to systemui-certprobe-noop
  EXPECTED_SUPER=<path>         sparse super expected to have been flashed
  EXPECTED_SYSTEM_EXT_IMG=<path> offline system_ext image to verify
  INSPECT_DIR=<path>            report directory
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

compare_file_hash() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local actual_hash
  local expected_hash
  actual_hash="$(sha256_one "$actual")"
  expected_hash="$(sha256_one "$expected")"
  [ "$actual_hash" = "$expected_hash" ] || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$actual"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    adb devices >&2
    die "device ${SERIAL} is not available over adb"
  fi
}

verify_sig_boundary_noop() {
  local apk="$1"
  local report="$2"
  "$SIGCHECK" "$apk" > "$report"
  grep -q '^keytool_status=0$' "$report" \
    || die "expected keytool_status=0 for ${apk}"
  grep -q '^jarsigner_status=0$' "$report" \
    || die "expected jarsigner_status=0 for ${apk}"
  grep -q '99:CB:9A:0E:CE:39:C4:30:1E:22:15:0E:5D:72:38:EE:9B:40:73:04:20:54:C6:0B:AA:FD:68:F3:A7:C5:75:74' "$report" \
    || die "expected Smartisan Android cert missing for ${apk}"
  grep -q '^apk_sig_block_magic=absent$' "$report" \
    || die "expected absent APK Sig Block magic for ${apk}"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_executable "$SIGCHECK"
  need_executable "$APK_GATE_VERIFIER"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_EXT_IMG"
  need_file "$EXPECTED_APK"
  need_file "$STOCK_APK"
  mkdir -p "$INSPECT_DIR"

  local timestamp
  local report
  local dump_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  report="${INSPECT_DIR}/verify-${SYSTEMUI_NOOP_VARIANT}-offline-${timestamp}.txt"
  dump_dir="${INSPECT_DIR}/offline-${timestamp}"
  mkdir -p "$dump_dir"

  "$APK_GATE_VERIFIER" >/dev/null

  {
    echo "# SmartisanSystemUI cert-probe no-op ROM offline verification"
    echo "timestamp=${timestamp}"
    echo "systemui_noop_variant=${SYSTEMUI_NOOP_VARIANT}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_ext_img=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## APK gate"
    echo "apk_gate_verifier=PASS"
    echo

    echo "## signature boundary"
    verify_sig_boundary_noop "$EXPECTED_APK" "${dump_dir}/SmartisanSystemUI-certprobe-noop.signature.txt"
    echo "signature_boundary=ok"
    echo

    echo "## system_ext image"
    "$DEBUGFS" -R "dump ${SYSTEMUI_IMAGE_PATH} ${dump_dir}/SmartisanSystemUI.apk" "$EXPECTED_SYSTEM_EXT_IMG" >/dev/null 2>&1
    compare_file_hash "${dump_dir}/SmartisanSystemUI.apk" "$EXPECTED_APK" "system_ext/SmartisanSystemUI.apk"
    unzip -t "${dump_dir}/SmartisanSystemUI.apk" >/dev/null
    echo "zip_integrity=ok"
    echo

    echo "## super slice"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_ext_b=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## lpdump excerpt"
    rg -n "system_ext_b|16443328|17021680|578352" "${EXPECTED_SUPER}.lpdump"* || true
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_EXT_IMG" "$EXPECTED_APK" "$STOCK_APK"
    echo
    echo "PASS"
  } | tee "$report"

  echo "Report: ${report}"
}

run_read_only_device() {
  need_file "$EXPECTED_APK"
  need_executable "$SIGCHECK"
  require_device
  mkdir -p "$INSPECT_DIR"

  local timestamp
  local report
  local pull_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  report="${INSPECT_DIR}/verify-${SYSTEMUI_NOOP_VARIANT}-device-${timestamp}.txt"
  pull_dir="${INSPECT_DIR}/device-${timestamp}"
  mkdir -p "$pull_dir"

  {
    echo "# SmartisanSystemUI cert-probe no-op device verification"
    echo "timestamp=${timestamp}"
    echo "serial=${SERIAL}"
    echo "systemui_noop_variant=${SYSTEMUI_NOOP_VARIANT}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_apk=${EXPECTED_APK}"
    echo

    echo "## adb"
    adb devices -l
    echo

    echo "## boot state"
    adb_device shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint' | tr -d '\r'
    echo

    echo "## root"
    "$ROOT_HELPER" status || true
    echo

    echo "## package"
    adb_device shell 'pm path com.android.systemui; dumpsys package com.android.systemui | grep -E "userId=|sharedUser|pkg=|codePath=|versionCode=|signatures|SigningInfo" | head -n 80' | tr -d '\r' || true
    echo

    echo "## path label"
    adb_device shell "ls -lZ ${SYSTEMUI_DEVICE_PATH} 2>/dev/null" | tr -d '\r' || true
    echo

    echo "## window excerpt"
    adb_device shell 'dumpsys window' > "${pull_dir}/window.txt" || true
    rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing|StatusBar" "${pull_dir}/window.txt" || true
    echo

    echo "## logcat excerpt"
    adb_device logcat -d -t 1000 > "${pull_dir}/logcat.txt" || true
    rg -n "SystemUI|QSTile|StatusBar|PackageManager|PackageParser|dex2oat|dexopt|FATAL EXCEPTION|AndroidRuntime" "${pull_dir}/logcat.txt" || true
    echo
  } | tee "$report"

  adb_device pull "$SYSTEMUI_DEVICE_PATH" "${pull_dir}/SmartisanSystemUI.apk" >/dev/null
  compare_file_hash "${pull_dir}/SmartisanSystemUI.apk" "$EXPECTED_APK" "device/SmartisanSystemUI.apk" | tee -a "$report"
  verify_sig_boundary_noop "${pull_dir}/SmartisanSystemUI.apk" "${pull_dir}/SmartisanSystemUI.signature.txt"
  echo "signature_boundary=ok" | tee -a "$report"

  {
    echo
    echo "PASS: ${SYSTEMUI_NOOP_VARIANT} device read-only verification"
    echo "Report: ${report}"
  } | tee -a "$report"
}

case "${1:---offline-image}" in
  --offline-image)
    run_offline_image
    ;;
  --read-only)
    run_read_only_device
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
