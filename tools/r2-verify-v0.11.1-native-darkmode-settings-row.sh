#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
APK_VERIFIER="${APK_VERIFIER:-${ROOT_DIR}/tools/r2-verify-v0.11-native-darkmode-tile-apks.sh}"

INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.11.1-native-darkmode-settings-row"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.11.1-native-darkmode-settings-row.img"
EXPECTED_SYSTEM_EXT_IMG="${ROOT_DIR}/hard-rom/build/system_ext-otatrust-v0.11.1-native-darkmode-settings-row.img"
SOURCE_V024="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img"
V024_LIVE_REPORT="${ROOT_DIR}/hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-device-20260618-151156.txt"
SETTINGS_NOOP_LIVE_REPORT="${ROOT_DIR}/hard-rom/inspect/v0.25-settings-noop-on-v0.24/verify-v0.25-settings-noop-on-v0.24-20260618-155616.txt"
SYSTEMUI_NOOP_LIVE_REPORT="${ROOT_DIR}/hard-rom/inspect/systemui-certprobe-noop-on-v0.24/verify-systemui-certprobe-noop-on-v0.24-device-20260618-160919.txt"

STOCK_SETTINGS_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
STOCK_SYSTEMUI_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
SETTINGS_APK="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk"
SYSTEMUI_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk"
SYSTEMUI_SAMESIZE_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-darkmode-tile-samesize.apk"

SETTINGS_IMAGE_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
SYSTEMUI_IMAGE_PATH="/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
SETTINGS_DEVICE_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
SYSTEMUI_DEVICE_PATH="/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh --offline-image
  tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh --read-only

--offline-image verifies the generated v0.11.1 sparse super:
  - v0.11.1 APK semantic verifier still passes, including the reachable Darwin
    Settings brightness-row check
  - SettingsSmartisan in system_b matches the behavior APK
  - SmartisanSystemUI in system_ext_b matches the same-size behavior APK
  - SystemUI same-size APK is byte-sized like stock and member-equivalent to
    the behavior APK
  - signature-boundary reports fail only at changed dex members
  - sparse system_b and system_ext_b logical slices match generated images

--read-only verifies a flashed device without changing /data.

The script never flashes, reboots, erases misc, or changes /data.
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

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

dump_one() {
  local image="$1"
  local src_path="$2"
  local out="$3"
  "$DEBUGFS" -R "dump ${src_path} ${out}" "$image" >/dev/null 2>&1
  need_file "$out"
}

verify_held_path() {
  local image="$1"
  local path="$2"
  debugfs_path_exists "$image" "$path" || die "missing held-stock path: ${path}"
  echo "held_stock_path=${path}"
}

verify_sig_boundary() {
  local apk="$1"
  local report="$2"
  local expected_digest="$3"
  "$SIGCHECK" "$apk" > "$report"
  grep -q '^keytool_status=1$' "$report" \
    || die "expected keytool_status=1 for ${apk}"
  grep -q "$expected_digest" "$report" \
    || die "signature report missing expected digest boundary for ${apk}: ${expected_digest}"
  sed -n '1,24p' "$report"
}

verify_systemui_samesize_equivalence() {
  python3 - "$STOCK_SYSTEMUI_APK" "$SYSTEMUI_APK" "$SYSTEMUI_SAMESIZE_APK" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

stock, patched, samesize = [Path(item) for item in sys.argv[1:]]
if stock.stat().st_size != samesize.stat().st_size:
    raise SystemExit("same-size APK byte size does not match stock")
with zipfile.ZipFile(patched) as zp, zipfile.ZipFile(samesize) as zs:
    patched_names = [i.filename for i in zp.infolist()]
    samesize_names = [i.filename for i in zs.infolist()]
    if patched_names != samesize_names:
        raise SystemExit("same-size APK entry order differs from behavior APK")
    for name in patched_names:
        hp = hashlib.sha256(zp.read(name)).hexdigest()
        hs = hashlib.sha256(zs.read(name)).hexdigest()
        if hp != hs:
            raise SystemExit(f"same-size APK member mismatch: {name}")
    info = zs.getinfo("classes10.dex")
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit("same-size APK classes10.dex is not STORED")
    print(f"systemui_samesize_comment_len={len(zs.comment)}")
    print("systemui_samesize_member_equivalence=ok")
PY
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

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_executable "$SIGCHECK"
  need_executable "$APK_VERIFIER"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$EXPECTED_SYSTEM_EXT_IMG"
  need_file "$SOURCE_V024"
  need_file "$V024_LIVE_REPORT"
  need_file "$SETTINGS_NOOP_LIVE_REPORT"
  need_file "$SYSTEMUI_NOOP_LIVE_REPORT"
  need_file "$SETTINGS_APK"
  need_file "$SYSTEMUI_APK"
  need_file "$SYSTEMUI_SAMESIZE_APK"
  need_file "$STOCK_SETTINGS_APK"
  need_file "$STOCK_SYSTEMUI_APK"
  grep -Fq "PASS: v0.24 device read-only verification" "$V024_LIVE_REPORT" \
    || die "v0.24 live source report is not PASS"
  grep -Eq "PASS: v0\\.25-settings-noop-on-v0\\.24 .*read-only" "$SETTINGS_NOOP_LIVE_REPORT" \
    || die "Settings no-op live report is not PASS"
  grep -Fq "PASS: systemui-certprobe-noop-on-v0.24 device read-only verification" "$SYSTEMUI_NOOP_LIVE_REPORT" \
    || die "SystemUI no-op live report is not PASS"
  mkdir -p "$INSPECT_DIR"

  local timestamp
  local report
  local dump_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  report="${INSPECT_DIR}/verify-v0.11.1-native-darkmode-settings-row-offline-image-${timestamp}.txt"
  dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  mkdir -p "$dump_dir"

  "$APK_VERIFIER" >/dev/null

  {
    echo "# v0.11.1 native dark-mode ROM offline verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo "expected_system_ext_img=${EXPECTED_SYSTEM_EXT_IMG}"
    echo "source_v0.24=${SOURCE_V024}"
    echo "v0.24_live_report=${V024_LIVE_REPORT}"
    echo "settings_noop_live_report=${SETTINGS_NOOP_LIVE_REPORT}"
    echo "systemui_noop_live_report=${SYSTEMUI_NOOP_LIVE_REPORT}"
    echo

    echo "## APK semantics"
    echo "apk_semantic_verifier=PASS"
    verify_systemui_samesize_equivalence
    unzip -t "$SETTINGS_APK" >/dev/null
    unzip -t "$SYSTEMUI_SAMESIZE_APK" >/dev/null
    echo "zip_integrity=ok"
    echo

    echo "## signature boundaries"
    verify_sig_boundary "$SETTINGS_APK" "${dump_dir}/SettingsSmartisan.signature.txt" \
      'SHA-256 digest error for classes.dex'
    echo
    verify_sig_boundary "$SYSTEMUI_SAMESIZE_APK" "${dump_dir}/SmartisanSystemUI-samesize.signature.txt" \
      'SHA-256 digest error for classes10.dex'
    echo

    echo "## system_b"
    dump_one "$EXPECTED_SYSTEM_IMG" "$SETTINGS_IMAGE_PATH" "${dump_dir}/SettingsSmartisan.apk"
    compare_file_hash "${dump_dir}/SettingsSmartisan.apk" "$SETTINGS_APK" "system/SettingsSmartisan.apk"
    unzip -t "${dump_dir}/SettingsSmartisan.apk" >/dev/null
    verify_held_path "$EXPECTED_SYSTEM_IMG" "/system/priv-app/SettingsSmartisan/.SettingsSmartisan.apk.smartisax-v0111-stock-held"
    echo

    echo "## system_ext_b"
    dump_one "$EXPECTED_SYSTEM_EXT_IMG" "$SYSTEMUI_IMAGE_PATH" "${dump_dir}/SmartisanSystemUI.apk"
    compare_file_hash "${dump_dir}/SmartisanSystemUI.apk" "$SYSTEMUI_SAMESIZE_APK" "system_ext/SmartisanSystemUI.apk"
    unzip -t "${dump_dir}/SmartisanSystemUI.apk" >/dev/null
    echo

    echo "## sparse slices"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_ext_b=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" "$EXPECTED_SYSTEM_EXT_IMG" "$SOURCE_V024" \
      "$SETTINGS_APK" "$SYSTEMUI_APK" "$SYSTEMUI_SAMESIZE_APK" "$STOCK_SETTINGS_APK" "$STOCK_SYSTEMUI_APK"
    echo
    echo "PASS: v0.11.1 native dark-mode settings-row offline image verification"
  } | tee "$report"

  echo "Report: ${report}"
}

run_read_only_device() {
  need_file "$SETTINGS_APK"
  need_file "$SYSTEMUI_SAMESIZE_APK"
  need_executable "$SIGCHECK"
  require_device
  mkdir -p "$INSPECT_DIR"

  local timestamp
  local report
  local pull_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  report="${INSPECT_DIR}/verify-v0.11.1-native-darkmode-settings-row-device-${timestamp}.txt"
  pull_dir="${INSPECT_DIR}/device-${timestamp}"
  mkdir -p "$pull_dir"

  {
    echo "# v0.11.1 native dark-mode device verification"
    echo "timestamp=${timestamp}"
    echo "serial=${SERIAL}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "settings_expected_apk=${SETTINGS_APK}"
    echo "systemui_expected_apk=${SYSTEMUI_SAMESIZE_APK}"
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

    echo "## package excerpts"
    adb_device shell 'pm path com.android.settings; dumpsys package com.android.settings | grep -E "userId=|sharedUser|pkg=|codePath=|versionCode=|signatures|SigningInfo" | head -n 60' | tr -d '\r' || true
    echo
    adb_device shell 'pm path com.android.systemui; dumpsys package com.android.systemui | grep -E "userId=|sharedUser|pkg=|codePath=|versionCode=|signatures|SigningInfo" | head -n 60' | tr -d '\r' || true
    echo

    echo "## path labels"
    adb_device shell "ls -lZ ${SETTINGS_DEVICE_PATH} ${SYSTEMUI_DEVICE_PATH} 2>/dev/null" | tr -d '\r' || true
    echo

    echo "## ui mode and quick settings"
    adb_device shell 'cmd uimode night 2>/dev/null || true; settings get secure expanded_widget_buttons; settings get secure expanded_widget_buttons_additional' | tr -d '\r' || true
    echo

    echo "## window excerpt"
    adb_device shell 'dumpsys window' > "${pull_dir}/window.txt" || true
    rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing|StatusBar" "${pull_dir}/window.txt" || true
    echo

    echo "## logcat excerpt"
    adb_device logcat -d -t 1200 > "${pull_dir}/logcat.txt" || true
    rg -n "SystemUI|QSTile|toggleDarkMode|UiMode|Settings|PackageManager|PackageParser|dex2oat|dexopt|FATAL EXCEPTION|AndroidRuntime" "${pull_dir}/logcat.txt" || true
    echo
  } | tee "$report"

  adb_device pull "$SETTINGS_DEVICE_PATH" "${pull_dir}/SettingsSmartisan.apk" >/dev/null
  adb_device pull "$SYSTEMUI_DEVICE_PATH" "${pull_dir}/SmartisanSystemUI.apk" >/dev/null
  compare_file_hash "${pull_dir}/SettingsSmartisan.apk" "$SETTINGS_APK" "device/SettingsSmartisan.apk" | tee -a "$report"
  compare_file_hash "${pull_dir}/SmartisanSystemUI.apk" "$SYSTEMUI_SAMESIZE_APK" "device/SmartisanSystemUI.apk" | tee -a "$report"
  verify_sig_boundary "${pull_dir}/SettingsSmartisan.apk" "${pull_dir}/SettingsSmartisan.signature.txt" \
    'SHA-256 digest error for classes.dex' | tee -a "$report"
  verify_sig_boundary "${pull_dir}/SmartisanSystemUI.apk" "${pull_dir}/SmartisanSystemUI.signature.txt" \
    'SHA-256 digest error for classes10.dex' | tee -a "$report"

  {
    echo
    echo "PASS: v0.11.1 native dark-mode settings-row device read-only verification"
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
