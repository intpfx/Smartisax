#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/v0.11-native-darkmode-functional}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/v0.11-darkmode-functional-${TS}.txt}"
LOGCAT_OUT="${OUT_DIR}/v0.11-darkmode-functional-logcat-${TS}.txt"

EXPECTED_SETTINGS_HASH="8a4472dbfe90c16dc3cdf01eb2a41bdcb951b5c0da1b07d57dba19373812a7f0"
EXPECTED_SYSTEMUI_HASH="42996f1c39b5a7bf3775c7da59982b385ced43a74dcb431b1973e64ffd19fe1f"
SETTINGS_DEVICE_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
SYSTEMUI_DEVICE_PATH="/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
WIDGET_ACTION="com.smartisanos.action.WIDGET_BUTTONS_CHANGED"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-darkmode-functional-test.sh --write-approved

This is a reversible live functional test for flashed v0.11-native-darkmode.
It writes /data settings only after --write-approved:
  - toggles UiModeManager night mode yes/no
  - temporarily replaces one existing system.expanded_widget_buttons entry with
    toggleDarkMode so SystemUI must instantiate the native tile
  - restores the original night mode and quick-setting values before exit

The script does not flash, reboot, erase misc, install packages, delete package
data, or run cleanup.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
  usage
  exit 0
fi

if [ "${1:-}" != "--write-approved" ]; then
  usage >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
: > "$REPORT"

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

section() {
  log ""
  log "## $*"
}

die() {
  log "error: $*"
  exit 1
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$1" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

sq() {
  local value="${1//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

get_setting() {
  local ns="$1"
  local key="$2"
  adb_shell "settings get $(sq "$ns") $(sq "$key") 2>/dev/null || true" | tail -n 1
}

put_or_delete_setting() {
  local ns="$1"
  local key="$2"
  local value="$3"
  if [ "$value" = "null" ]; then
    adb_shell "settings delete $(sq "$ns") $(sq "$key") >/dev/null 2>&1 || true" >/dev/null
  else
    adb_shell "settings put $(sq "$ns") $(sq "$key") $(sq "$value")" >/dev/null
  fi
}

broadcast_widget_change() {
  adb_shell "am broadcast --user 0 -a $(sq "$WIDGET_ACTION") -p com.android.systemui" >/dev/null
}

count_widgets() {
  local value="$1"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf '0'
    return
  fi
  awk -F'|' '{print NF}' <<<"$value"
}

has_widget() {
  local value="$1"
  local key="$2"
  case "|$value|" in
    *"|$key|"*) return 0 ;;
    *) return 1 ;;
  esac
}

join_by_pipe() {
  local out=""
  local item
  for item in "$@"; do
    if [ -z "$out" ]; then
      out="$item"
    else
      out="${out}|${item}"
    fi
  done
  printf '%s' "$out"
}

TEST_MAIN=""
REPLACED_TILE=""
choose_test_main() {
  local original="$1"
  local -a tiles=()
  local i prefer idx
  if [ -z "$original" ] || [ "$original" = "null" ]; then
    return 1
  fi
  IFS='|' read -r -a tiles <<< "$original"
  if [ "${#tiles[@]}" -eq 0 ]; then
    return 1
  fi
  for i in "${!tiles[@]}"; do
    if [ "${tiles[$i]}" = "toggleDarkMode" ]; then
      TEST_MAIN="$original"
      REPLACED_TILE="already-present"
      return 0
    fi
  done
  idx="-1"
  for prefer in toggleLockScreen toggleFakeCall toggleRealtimeSubtitle toggleWirelessTNT toggleReadingMode toggleProtectEyes toggleDisableButtons; do
    for i in "${!tiles[@]}"; do
      if [ "${tiles[$i]}" = "$prefer" ]; then
        idx="$i"
        break 2
      fi
    done
  done
  if [ "$idx" = "-1" ]; then
    idx="$((${#tiles[@]} - 1))"
  fi
  REPLACED_TILE="${tiles[$idx]}"
  tiles[$idx]="toggleDarkMode"
  TEST_MAIN="$(join_by_pipe "${tiles[@]}")"
}

wait_for_night_mode() {
  local expected="$1"
  local current=""
  local i
  for i in $(seq 1 20); do
    current="$(adb_shell 'cmd uimode night 2>/dev/null || true' | tail -n 1)"
    if grep -Fq "Night mode: ${expected}" <<<"$current"; then
      log "observed=${current}"
      return 0
    fi
    sleep 0.5
  done
  log "last_observed=${current}"
  return 1
}

ORIG_NIGHT_LINE=""
ORIG_SECURE_UI_NIGHT=""
ORIG_SYSTEM_UI_NIGHT=""
ORIG_GLOBAL_UI_NIGHT=""
ORIG_MAIN=""
ORIG_ADDITIONAL=""
RESTORE_NEEDED=0

restore_night_mode() {
  case "$ORIG_NIGHT_LINE" in
    *"Night mode: yes"*) adb_shell "cmd uimode night yes" >/dev/null || true ;;
    *"Night mode: no"*) adb_shell "cmd uimode night no" >/dev/null || true ;;
    *"Night mode: auto"*) adb_shell "cmd uimode night auto" >/dev/null || true ;;
    *)
      case "$ORIG_SECURE_UI_NIGHT" in
        2) adb_shell "cmd uimode night yes" >/dev/null || true ;;
        0|1) adb_shell "cmd uimode night no" >/dev/null || true ;;
      esac
      ;;
  esac
}

restore_all() {
  section "restore original state"
  put_or_delete_setting system expanded_widget_buttons "$ORIG_MAIN"
  put_or_delete_setting system expanded_widget_buttons_additional "$ORIG_ADDITIONAL"
  broadcast_widget_change || true
  restore_night_mode
  sleep 1
  log "restored.cmd_uimode=$(adb_shell 'cmd uimode night 2>/dev/null || true' | tail -n 1)"
  log "restored.secure.ui_night_mode=$(get_setting secure ui_night_mode)"
  log "restored.system.ui_night_mode=$(get_setting system ui_night_mode)"
  log "restored.global.ui_night_mode=$(get_setting global ui_night_mode)"
  log "restored.system.expanded_widget_buttons=$(get_setting system expanded_widget_buttons)"
  log "restored.system.expanded_widget_buttons_additional=$(get_setting system expanded_widget_buttons_additional)"
}

cleanup() {
  local status=$?
  set +e
  if [ "$RESTORE_NEEDED" = "1" ]; then
    restore_all
  fi
  if [ "$status" -ne 0 ]; then
    log "result=FAIL_WRITE_APPROVED_FUNCTIONAL"
    log "report=${REPORT}"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

log "# v0.11 native dark-mode functional write test"
log "timestamp=${TS}"
log "serial=${SERIAL}"
log "report=${REPORT#${ROOT_DIR}/}"
log "boundary=write-approved; writes only UiModeManager and system quick-setting keys; restores originals; no flash/reboot/erase/package/data cleanup"

section "adb"
adb devices -l | tee -a "$REPORT"
adb_available || die "device ${SERIAL} is not available over adb"

section "preflight"
BOOT_COMPLETED="$(adb_shell 'getprop sys.boot_completed' | tail -n 1)"
SLOT_SUFFIX="$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)"
BOOTANIM="$(adb_shell 'getprop init.svc.bootanim' | tail -n 1)"
VBSTATE="$(adb_shell 'getprop ro.boot.verifiedbootstate' | tail -n 1)"
SETTINGS_HASH="$(adb_shell "sha256sum $(sq "$SETTINGS_DEVICE_PATH") 2>/dev/null || true" | awk 'NR == 1 {print $1}')"
SYSTEMUI_HASH="$(adb_shell "sha256sum $(sq "$SYSTEMUI_DEVICE_PATH") 2>/dev/null || true" | awk 'NR == 1 {print $1}')"
log "sys.boot_completed=${BOOT_COMPLETED}"
log "ro.boot.slot_suffix=${SLOT_SUFFIX}"
log "init.svc.bootanim=${BOOTANIM}"
log "ro.boot.verifiedbootstate=${VBSTATE}"
log "device.SettingsSmartisan.sha256=${SETTINGS_HASH}"
log "device.SmartisanSystemUI.sha256=${SYSTEMUI_HASH}"
[ "$BOOT_COMPLETED" = "1" ] || die "device is not boot-completed"
[ "$SLOT_SUFFIX" = "_b" ] || die "device is not on B slot"
[ "$SETTINGS_HASH" = "$EXPECTED_SETTINGS_HASH" ] || die "SettingsSmartisan hash is not v0.11"
[ "$SYSTEMUI_HASH" = "$EXPECTED_SYSTEMUI_HASH" ] || die "SmartisanSystemUI hash is not v0.11"

section "save original /data settings"
ORIG_NIGHT_LINE="$(adb_shell 'cmd uimode night 2>/dev/null || true' | tail -n 1)"
ORIG_SECURE_UI_NIGHT="$(get_setting secure ui_night_mode)"
ORIG_SYSTEM_UI_NIGHT="$(get_setting system ui_night_mode)"
ORIG_GLOBAL_UI_NIGHT="$(get_setting global ui_night_mode)"
ORIG_MAIN="$(get_setting system expanded_widget_buttons)"
ORIG_ADDITIONAL="$(get_setting system expanded_widget_buttons_additional)"
log "original.cmd_uimode=${ORIG_NIGHT_LINE}"
log "original.secure.ui_night_mode=${ORIG_SECURE_UI_NIGHT}"
log "original.system.ui_night_mode=${ORIG_SYSTEM_UI_NIGHT}"
log "original.global.ui_night_mode=${ORIG_GLOBAL_UI_NIGHT}"
log "original.system.expanded_widget_buttons=${ORIG_MAIN}"
log "original.system.expanded_widget_buttons_additional=${ORIG_ADDITIONAL}"
log "original.system.expanded_widget_buttons.count=$(count_widgets "$ORIG_MAIN")"
log "original.system.expanded_widget_buttons.has_toggleDarkMode=$(if has_widget "$ORIG_MAIN" toggleDarkMode; then printf yes; else printf no; fi)"
RESTORE_NEEDED=1

section "UiModeManager write test"
log "$ adb shell cmd uimode night yes"
adb_shell 'cmd uimode night yes' | tee -a "$REPORT" || true
wait_for_night_mode yes || die "night mode did not become yes"
log "after_yes.secure.ui_night_mode=$(get_setting secure ui_night_mode)"

log "$ adb shell cmd uimode night no"
adb_shell 'cmd uimode night no' | tee -a "$REPORT" || true
wait_for_night_mode no || die "night mode did not become no"
log "after_no.secure.ui_night_mode=$(get_setting secure ui_night_mode)"

section "SystemUI toggleDarkMode tile instantiation test"
choose_test_main "$ORIG_MAIN" || die "cannot build safe test quick-setting list from original expanded_widget_buttons"
log "replacement_tile=${REPLACED_TILE}"
log "test.system.expanded_widget_buttons=${TEST_MAIN}"
log "test.system.expanded_widget_buttons.count=$(count_widgets "$TEST_MAIN")"
has_widget "$TEST_MAIN" toggleDarkMode || die "test quick-setting list does not contain toggleDarkMode"

MARKER="SmartisaxDarkModeTest-${TS}"
adb_shell "log -t SmartisaxDarkModeTest $(sq "start ${MARKER}")" >/dev/null || true
put_or_delete_setting system expanded_widget_buttons "$TEST_MAIN"
broadcast_widget_change
sleep 3
log "live.system.expanded_widget_buttons=$(get_setting system expanded_widget_buttons)"
adb_shell "log -t SmartisaxDarkModeTest $(sq "after-tile-broadcast ${MARKER}")" >/dev/null || true

adb_device logcat -d -v time -t 1600 > "$LOGCAT_OUT" || true
{
  echo "logcat=${LOGCAT_OUT#${ROOT_DIR}/}"
  echo
  echo "### marker/QSTileHost/DarkMode excerpt"
  rg -n "SmartisaxDarkModeTest|QSTileHost|toggleDarkMode|DarkModeTile|UiMode|Night mode|FATAL EXCEPTION|AndroidRuntime" "$LOGCAT_OUT" || true
} | tee -a "$REPORT"

if ! rg -q "Creating tile: toggleDarkMode" "$LOGCAT_OUT"; then
  die "SystemUI log did not show Creating tile: toggleDarkMode"
fi
if rg -q "Error creating tile for spec: toggleDarkMode|Bad tile spec: toggleDarkMode|FATAL EXCEPTION|AndroidRuntime" "$LOGCAT_OUT"; then
  die "SystemUI log contains a toggleDarkMode creation error or crash"
fi
log "tile_creation_log=observed"

restore_all
RESTORE_NEEDED=0

section "final verification"
FINAL_NIGHT="$(adb_shell 'cmd uimode night 2>/dev/null || true' | tail -n 1)"
FINAL_MAIN="$(get_setting system expanded_widget_buttons)"
FINAL_ADDITIONAL="$(get_setting system expanded_widget_buttons_additional)"
log "final.cmd_uimode=${FINAL_NIGHT}"
log "final.system.expanded_widget_buttons=${FINAL_MAIN}"
log "final.system.expanded_widget_buttons_additional=${FINAL_ADDITIONAL}"
[ "$FINAL_MAIN" = "$ORIG_MAIN" ] || die "expanded_widget_buttons did not restore exactly"
[ "$FINAL_ADDITIONAL" = "$ORIG_ADDITIONAL" ] || die "expanded_widget_buttons_additional did not restore exactly"

section "summary"
log "ui_mode_yes=PASS"
log "ui_mode_no=PASS"
log "systemui_toggleDarkMode_tile_creation=PASS"
log "restore_original_quick_settings=PASS"
log "result=PASS_WRITE_APPROVED_FUNCTIONAL"
log "report=${REPORT}"
