#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.5-control"

PACKAGE="com.smartisax.controls"
APK_PATH="/system/priv-app/SmartisaxControls/SmartisaxControls.apk"
QS_ACTION="android.service.quicksettings.action.QS_TILE"

mode="read-only"

usage() {
  cat <<'EOF'
Usage:
  tools/r2-verify-v0.5-control.sh [--read-only]
  tools/r2-verify-v0.5-control.sh --exercise-uimode

Default mode is read-only. It verifies:
  - adb boot/slot state
  - APatch root availability
  - SmartisaxControls package path
  - MODIFY_DAY_NIGHT_MODE grant
  - QS TileService discovery
  - current UiModeManager night-mode state

--exercise-uimode changes the system night mode to yes, then no, then restores
the original mode. Use it only after a successful v0.5-control boot.
EOF
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
  --exercise-uimode)
    mode="exercise-uimode"
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

require_device
mkdir -p "$INSPECT_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
report="${INSPECT_DIR}/verify-v0.5-control-${timestamp}.txt"
package_dump="${INSPECT_DIR}/package-${PACKAGE}-${timestamp}.txt"
services_dump="${INSPECT_DIR}/qs-services-${timestamp}.txt"
uimode_dump="${INSPECT_DIR}/uimode-${timestamp}.txt"

{
  echo "# v0.5-control verification"
  echo "timestamp=${timestamp}"
  echo "serial=${SERIAL}"
  echo "mode=${mode}"
  echo

  echo "## adb"
  adb devices -l
  echo

  echo "## boot state"
  adb_device shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint'
  echo

  echo "## root"
  root_cmd 'id; getenforce; getprop ro.boot.slot_suffix'
  echo

  echo "## package path"
  adb_device shell "pm path ${PACKAGE}" | tr -d '\r'
  echo

  echo "## package permission excerpt"
  adb_device shell "dumpsys package ${PACKAGE}" > "$package_dump"
  rg -n "Package \\[${PACKAGE}\\]|codePath=|resourcePath=|android.permission.MODIFY_DAY_NIGHT_MODE|granted=true|DarkModeTileService|DarkModeActivity" "$package_dump" || true
  echo

  echo "## QS tile service query"
  adb_device shell "cmd package query-services --brief --components -a ${QS_ACTION}" > "$services_dump" || true
  tr -d '\r' < "$services_dump"
  echo

  echo "## uimode"
  adb_device shell cmd uimode night | tr -d '\r'
  adb_device shell settings get secure ui_night_mode | tr -d '\r' | sed 's/^/secure.ui_night_mode=/'
  adb_device shell dumpsys uimode > "$uimode_dump"
  rg -n "mNightMode=|mNightModeLocked=|mCurUiMode=|mComputedNightMode=|mCarModeEnabled=" "$uimode_dump" || true
  echo
} | tee "$report"

pm_path="$(adb_device shell "pm path ${PACKAGE}" | tr -d '\r' | sed 's/^package://')"
[ "$pm_path" = "$APK_PATH" ] || die "unexpected package path for ${PACKAGE}: ${pm_path:-<empty>}"

grep -q "android.permission.MODIFY_DAY_NIGHT_MODE: granted=true" "$package_dump" \
  || die "MODIFY_DAY_NIGHT_MODE is not granted to ${PACKAGE}"

grep -Eq "${PACKAGE}/\\.DarkModeTileService|${PACKAGE}/com\\.smartisax\\.controls\\.DarkModeTileService" "$services_dump" \
  || die "QS TileService was not discovered for ${PACKAGE}"

original_mode="$(night_mode_string)"
[ -n "$original_mode" ] || die "could not read current night mode"

if [ "$mode" = "exercise-uimode" ]; then
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

echo
echo "PASS: v0.5-control verification (${mode})"
echo "Report: ${report}"
echo "Package dump: ${package_dump}"
echo "QS services dump: ${services_dump}"
echo "UiMode dump: ${uimode_dump}"
