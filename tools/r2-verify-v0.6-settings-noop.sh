#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
SETTINGS_NOOP_VARIANT="${SETTINGS_NOOP_VARIANT:-v0.6-settings-noop}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${SETTINGS_NOOP_VARIANT}}"

PACKAGE="com.android.settings"
APK_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
EXPECTED_APK="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-certprobe-noop.apk"
EXPECTED_SUPER="${EXPECTED_SUPER:-${ROOT_DIR}/hard-rom/build/super-otatrust-${SETTINGS_NOOP_VARIANT}-exact-current.sparse.img}"

mode="read-only"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.6-settings-noop.sh [--read-only]
  tools/r2-verify-v0.6-settings-noop.sh --launch-settings

Default mode is read-only. It verifies after a SettingsSmartisan no-op flash:
  - adb boot/slot state
  - APatch root availability
  - com.android.settings package path
  - pulled SettingsSmartisan APK hash equals the v0.6 probe APK
  - pulled APK still exposes the Smartisan Android certificate
  - compact package-manager and window state evidence

--launch-settings additionally starts the Settings activity with am start -W.
Use that only after the read-only verification passes.

Environment:
  SETTINGS_NOOP_VARIANT=<name>  report/output variant; defaults to v0.6-settings-noop
  EXPECTED_SUPER=<path>         sparse super expected to have been flashed
  INSPECT_DIR=<path>            report directory
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
  --launch-settings)
    mode="launch-settings"
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
report="${INSPECT_DIR}/verify-${SETTINGS_NOOP_VARIANT}-${timestamp}.txt"
package_dump="${INSPECT_DIR}/package-${PACKAGE}-${timestamp}.txt"
pulled_apk="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.apk"
pulled_sig="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.signature.txt"
window_dump="${INSPECT_DIR}/window-${timestamp}.txt"

{
  echo "# ${SETTINGS_NOOP_VARIANT} verification"
  echo "timestamp=${timestamp}"
  echo "serial=${SERIAL}"
  echo "mode=${mode}"
  echo "settings_noop_variant=${SETTINGS_NOOP_VARIANT}"
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
} | tee "$report"

pm_path="$(adb_device shell "pm path ${PACKAGE}" | tr -d '\r' | sed 's/^package://')"
[ "$pm_path" = "$APK_PATH" ] || die "unexpected package path for ${PACKAGE}: ${pm_path:-<empty>}"

adb_device pull "$APK_PATH" "$pulled_apk" >/dev/null
"$SIGCHECK" "$pulled_apk" > "$pulled_sig"

expected_hash="$(shasum -a 256 "$EXPECTED_APK" | awk '{print $1}')"
pulled_hash="$(shasum -a 256 "$pulled_apk" | awk '{print $1}')"
[ "$pulled_hash" = "$expected_hash" ] || die "pulled SettingsSmartisan hash mismatch"

grep -q "99:CB:9A:0E:CE:39:C4:30:1E:22:15:0E:5D:72:38:EE:9B:40:73:04:20:54:C6:0B:AA:FD:68:F3:A7:C5:75:74" "$pulled_sig" \
  || die "pulled SettingsSmartisan does not expose the Smartisan Android cert"

if [ "$mode" = "launch-settings" ]; then
  adb_device shell am start -W -a android.settings.SETTINGS | tr -d '\r' | tee -a "$report"
fi

{
  echo
  echo "## pulled APK verification"
  echo "pulled_apk=${pulled_apk}"
  echo "pulled_sha256=${pulled_hash}"
  echo "expected_sha256=${expected_hash}"
  echo "signature_report=${pulled_sig}"
} | tee -a "$report"

{
  echo
  echo "PASS: ${SETTINGS_NOOP_VARIANT} verification (${mode})"
  echo "Report: ${report}"
  echo "Package dump: ${package_dump}"
  echo "Pulled APK: ${pulled_apk}"
  echo "Signature report: ${pulled_sig}"
  echo "Window dump: ${window_dump}"
} | tee -a "$report"
