#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.7-locale-filter"

PACKAGE="com.android.settings"
APK_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
EXPECTED_APK="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-locale-filter-ja-ko.apk"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img"

mode="read-only"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.7-locale-filter.sh [--read-only]
  tools/r2-verify-v0.7-locale-filter.sh --launch-locale-settings

Default mode is read-only. It verifies after a v0.7-locale-filter flash:
  - adb boot/slot state
  - APatch root availability
  - com.android.settings package path
  - pulled SettingsSmartisan APK hash equals the v0.7 locale-filter APK
  - pulled APK has the expected classes.dex digest-error signature boundary
  - compact package-manager, window, and logcat evidence

--launch-locale-settings additionally starts android.settings.LOCALE_SETTINGS.
Use that only after read-only verification passes, then inspect the phone screen
for the visible language list.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

remote_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

root_cmd() {
  adb_device shell "$KP -c $(remote_quote "$*")"
}

require_file() {
  [ -f "$1" ] || die "missing file: $1"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    adb devices >&2
    die "device ${SERIAL} is not available over adb"
  fi
}

case "${1:---read-only}" in
  --read-only|"")
    mode="read-only"
    ;;
  --launch-locale-settings)
    mode="launch-locale-settings"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_file "$SIGCHECK"
require_file "$EXPECTED_APK"
require_file "$EXPECTED_SUPER"
require_device
mkdir -p "$INSPECT_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
report="${INSPECT_DIR}/verify-v0.7-locale-filter-${timestamp}.txt"
package_dump="${INSPECT_DIR}/package-${PACKAGE}-${timestamp}.txt"
pulled_apk="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.apk"
pulled_sig="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.signature.txt"
window_dump="${INSPECT_DIR}/window-${timestamp}.txt"
logcat_dump="${INSPECT_DIR}/logcat-${timestamp}.txt"

{
  echo "# v0.7-locale-filter verification"
  echo "timestamp=${timestamp}"
  echo "serial=${SERIAL}"
  echo "mode=${mode}"
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
  root_cmd 'id; getenforce; getprop ro.boot.slot_suffix' | tr -d '\r'
  echo

  echo "## package path"
  adb_device shell "pm path ${PACKAGE}" | tr -d '\r'
  echo

  echo "## package excerpt"
  adb_device shell "dumpsys package ${PACKAGE}" > "$package_dump"
  rg -n "Package \\[${PACKAGE}\\]|codePath=|resourcePath=|userId=|sharedUser=|pkg=Package|versionCode=|targetSdk=|signatures|granted=true" "$package_dump" || true
  echo

  echo "## window excerpt"
  adb_device shell "dumpsys window" > "$window_dump" || true
  rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing" "$window_dump" || true
  echo

  echo "## logcat excerpt"
  adb_device logcat -d -t 500 > "$logcat_dump" || true
  rg -n "PackageManager|PackageParser|SettingsSmartisan|com.android.settings|LocalePicker|dex2oat|dexopt|FATAL EXCEPTION" "$logcat_dump" || true
  echo
} | tee "$report"

pm_path="$(adb_device shell "pm path ${PACKAGE}" | tr -d '\r' | sed 's/^package://')"
[ "$pm_path" = "$APK_PATH" ] || die "unexpected package path for ${PACKAGE}: ${pm_path:-<empty>}"

adb_device pull "$APK_PATH" "$pulled_apk" >/dev/null
"$SIGCHECK" "$pulled_apk" > "$pulled_sig"

expected_hash="$(shasum -a 256 "$EXPECTED_APK" | awk '{print $1}')"
pulled_hash="$(shasum -a 256 "$pulled_apk" | awk '{print $1}')"
[ "$pulled_hash" = "$expected_hash" ] || die "pulled SettingsSmartisan hash mismatch"

grep -q '^keytool_status=1$' "$pulled_sig" \
  || die "pulled SettingsSmartisan did not show the expected keytool boundary"
grep -q 'SHA-256 digest error for classes.dex' "$pulled_sig" \
  || die "pulled SettingsSmartisan did not show the expected classes.dex digest boundary"

if [ "$mode" = "launch-locale-settings" ]; then
  adb_device shell am start -W -a android.settings.LOCALE_SETTINGS | tr -d '\r' | tee -a "$report"
fi

{
  echo
  echo "## pulled APK verification"
  echo "pulled_apk=${pulled_apk}"
  echo "pulled_sha256=${pulled_hash}"
  echo "expected_sha256=${expected_hash}"
  echo "signature_report=${pulled_sig}"
} | tee -a "$report"

echo
echo "PASS: v0.7-locale-filter verification (${mode})"
echo "Report: ${report}"
echo "Package dump: ${package_dump}"
echo "Pulled APK: ${pulled_apk}"
echo "Signature report: ${pulled_sig}"
echo "Window dump: ${window_dump}"
echo "Logcat dump: ${logcat_dump}"
