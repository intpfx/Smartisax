#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.8-darkmode-ui"

PACKAGE="com.android.settings"
APK_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
EXPECTED_APK="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-darkmode-ui.apk"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img"

mode="read-only"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.8-darkmode-ui.sh [--read-only]
  tools/r2-verify-v0.8-darkmode-ui.sh --launch-display-settings
  tools/r2-verify-v0.8-darkmode-ui.sh --exercise-uimode-shell

Default mode is read-only. It verifies after a v0.8-darkmode-ui flash:
  - adb boot/slot state
  - APatch root availability
  - com.android.settings package path
  - pulled SettingsSmartisan APK hash equals the v0.8 dark-mode APK
  - pulled APK has the expected classes.dex digest-error signature boundary
  - pulled classes.dex contains UiModeManager/getNightMode/setNightModeActivated
  - current UiModeManager and Settings.Secure ui_night_mode state
  - compact package-manager, window, and logcat evidence

--launch-display-settings additionally starts android.settings.DISPLAY_SETTINGS.
Use that only after read-only verification passes, then inspect the phone screen
for the dark-mode row in the display/brightness settings page.

--exercise-uimode-shell changes night mode to yes, then no, then restores the
original shell-reported mode. Use it only after explicit confirmation because it
modifies system settings under /data.
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

night_mode_string() {
  adb_device shell cmd uimode night 2>/dev/null | tr -d '\r' | awk -F': ' '/Night mode:/ {print $2; exit}'
}

set_night_mode() {
  local target="$1"
  adb_device shell cmd uimode night "$target" >/dev/null
}

expect_night_mode() {
  local expected="$1"
  local actual
  actual="$(night_mode_string)"
  [ "$actual" = "$expected" ] || die "night mode expected ${expected}, got ${actual:-<empty>}"
}

restore_night_mode() {
  local original="$1"
  case "$original" in
    auto|no|yes|custom)
      set_night_mode "$original"
      ;;
    *)
      echo "warning: unknown original night mode '${original}', not restoring" >&2
      ;;
  esac
}

case "${1:---read-only}" in
  --read-only|"")
    mode="read-only"
    ;;
  --launch-display-settings)
    mode="launch-display-settings"
    ;;
  --exercise-uimode-shell)
    mode="exercise-uimode-shell"
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
report="${INSPECT_DIR}/verify-v0.8-darkmode-ui-${timestamp}.txt"
package_dump="${INSPECT_DIR}/package-${PACKAGE}-${timestamp}.txt"
pulled_apk="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.apk"
pulled_sig="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.signature.txt"
pulled_strings="${INSPECT_DIR}/SettingsSmartisan-device-${timestamp}.classes.strings.txt"
window_dump="${INSPECT_DIR}/window-${timestamp}.txt"
logcat_dump="${INSPECT_DIR}/logcat-${timestamp}.txt"
uimode_dump="${INSPECT_DIR}/uimode-${timestamp}.txt"

{
  echo "# v0.8-darkmode-ui verification"
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

  echo "## uimode"
  adb_device shell cmd uimode night | tr -d '\r'
  adb_device shell settings get secure ui_night_mode | tr -d '\r' | sed 's/^/secure.ui_night_mode=/'
  adb_device shell dumpsys uimode > "$uimode_dump"
  rg -n "mNightMode=|mNightModeLocked=|mCurUiMode=|mComputedNightMode=|mCarModeEnabled=" "$uimode_dump" || true
  echo

  echo "## window excerpt"
  adb_device shell "dumpsys window" > "$window_dump" || true
  rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing" "$window_dump" || true
  echo

  echo "## logcat excerpt"
  adb_device logcat -d -t 500 > "$logcat_dump" || true
  rg -n "PackageManager|PackageParser|SettingsSmartisan|com.android.settings|BrightnessSettingsFragment|UiModeManager|uimode|dex2oat|dexopt|FATAL EXCEPTION" "$logcat_dump" || true
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

unzip -p "$pulled_apk" classes.dex | strings > "$pulled_strings"
grep -q 'Landroid/app/UiModeManager;' "$pulled_strings" || die "missing UiModeManager class string"
grep -q 'getNightMode' "$pulled_strings" || die "missing getNightMode string"
grep -q 'setNightModeActivated' "$pulled_strings" || die "missing setNightModeActivated string"
grep -q 'uimode' "$pulled_strings" || die "missing uimode service string"

original_mode="$(night_mode_string)"
[ -n "$original_mode" ] || die "could not read current night mode"

if [ "$mode" = "launch-display-settings" ]; then
  adb_device shell am start -W -a android.settings.DISPLAY_SETTINGS | tr -d '\r' | tee -a "$report"
fi

if [ "$mode" = "exercise-uimode-shell" ]; then
  echo "Exercising UiModeManager night mode through shell backend..."
  trap 'restore_night_mode "$original_mode" >/dev/null 2>&1 || true' EXIT
  set_night_mode yes
  sleep 2
  expect_night_mode yes
  set_night_mode no
  sleep 2
  expect_night_mode no
  restore_night_mode "$original_mode"
  trap - EXIT
  echo "Restored night mode: $(night_mode_string)"
fi

{
  echo
  echo "## pulled APK verification"
  echo "pulled_apk=${pulled_apk}"
  echo "pulled_sha256=${pulled_hash}"
  echo "expected_sha256=${expected_hash}"
  echo "signature_report=${pulled_sig}"
  echo "classes_strings=${pulled_strings}"
  echo "original_night_mode=${original_mode}"
} | tee -a "$report"

echo
echo "PASS: v0.8-darkmode-ui verification (${mode})"
echo "Report: ${report}"
echo "Package dump: ${package_dump}"
echo "Pulled APK: ${pulled_apk}"
echo "Signature report: ${pulled_sig}"
echo "Classes strings: ${pulled_strings}"
echo "Window dump: ${window_dump}"
echo "Logcat dump: ${logcat_dump}"
echo "UiMode dump: ${uimode_dump}"
