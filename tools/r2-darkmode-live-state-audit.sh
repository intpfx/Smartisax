#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/darkmode-live-state}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/darkmode-live-state-${TS}.txt}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-darkmode-live-state-audit.sh

Environment:
  SERIAL       Android serial, default bb12d264
  OUT_DIR      Report directory, default hard-rom/inspect/darkmode-live-state
  REPORT       Report path override
  ROOT_HELPER  Root wrapper, default tools/r2-root.sh

This script is read-only. It does not reboot, flash, erase misc, write settings,
change packages, or mutate /data. It only collects current live state needed to
design native dark-mode Settings/SystemUI integration.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
  usage
  exit 0
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

run_cmd() {
  log "\$ $*"
  "$@" 2>&1 | tr -d '\r' | tee -a "$REPORT" || true
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

log "# R2 Dark Mode Live State Audit"
log "timestamp=${TS}"
log "serial=${SERIAL}"
log "report=${REPORT#${ROOT_DIR}/}"
log "boundary=read-only; no reboot, no flash, no settings write, no package mutation, no /data cleanup"

section "adb"
run_cmd adb devices -l
if ! adb_available; then
  log "result=DEVICE_NOT_AVAILABLE"
  log "report=${REPORT}"
  exit 1
fi

section "device props"
adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)";
printf "ro.build.version.sdk=%s\n" "$(getprop ro.build.version.sdk)";
printf "ro.build.fingerprint=%s\n" "$(getprop ro.build.fingerprint)"' | tee -a "$REPORT"

section "root status"
if [ -x "$ROOT_HELPER" ]; then
  run_cmd "$ROOT_HELPER" cmd 'id; getenforce; getprop ro.boot.slot_suffix'
else
  log "missing_root_helper=${ROOT_HELPER}"
fi

section "UiModeManager"
adb_shell 'cmd uimode night' | tee -a "$REPORT" || true
adb_shell 'dumpsys uimode | sed -n "1,180p"' | tee -a "$REPORT" || true

section "settings keys"
adb_shell 'for ns in secure system global; do
  for key in \
    ui_night_mode \
    ui_night_mode_custom_type \
    ui_night_mode_last_computed \
    dark_mode_enable \
    sysui_qs_tiles \
    qs_tiles \
    notification_widget_buttons \
    def_notification_widget_buttons \
    expanded_widget_buttons \
    expanded_widget_buttons_additional \
    expanded_widget_buttons_old \
    notification_widget_order \
    quick_setting_tiles \
    smartisan_qs_tiles; do
      value="$(settings get "$ns" "$key" 2>/dev/null || true)"
      printf "%s.%s=%s\n" "$ns" "$key" "$value"
  done
done' | tee -a "$REPORT"

section "parsed Smartisan QS state"
adb_shell '
count_widgets() {
  value="$1"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf "0"
    return
  fi
  printf "%s" "$value" | awk -F"|" "{print NF}"
}

has_widget() {
  value="$1"
  key="$2"
  case "|$value|" in
    *"|$key|"*) printf "yes" ;;
    *) printf "no" ;;
  esac
}

dup_widgets() {
  value="$1"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    printf "none"
    return
  fi
  printf "%s" "$value" | tr "|" "\n" | awk "NF {count[\$0]++} END {first=1; for (k in count) if (count[k] > 1) { if (!first) printf \",\"; printf \"%s\", k; first=0 } if (first) printf \"none\" }"
}

for ns in system secure global; do
  main="$(settings get "$ns" expanded_widget_buttons 2>/dev/null || true)"
  additional="$(settings get "$ns" expanded_widget_buttons_additional 2>/dev/null || true)"
  tnt="$(settings get "$ns" tnt_expanded_widget_buttons 2>/dev/null || true)"
  boston="$(settings get "$ns" boston_expanded_widget_buttons 2>/dev/null || true)"
  for pair in \
    "expanded_widget_buttons:$main" \
    "expanded_widget_buttons_additional:$additional" \
    "tnt_expanded_widget_buttons:$tnt" \
    "boston_expanded_widget_buttons:$boston"; do
    name="${pair%%:*}"
    value="${pair#*:}"
    count="$(count_widgets "$value")"
    over20="no"
    if [ "$count" -gt 20 ] 2>/dev/null; then
      over20="yes"
    fi
    printf "%s.%s.count=%s\n" "$ns" "$name" "$count"
    printf "%s.%s.has_toggleDarkMode=%s\n" "$ns" "$name" "$(has_widget "$value" toggleDarkMode)"
    printf "%s.%s.over20=%s\n" "$ns" "$name" "$over20"
    printf "%s.%s.duplicates=%s\n" "$ns" "$name" "$(dup_widgets "$value")"
  done
done' | tee -a "$REPORT"

section "package state"
adb_shell 'for pkg in com.android.settings com.android.systemui com.smartisanos.systemui com.android.providers.settings; do
  echo "### package ${pkg}"
  dumpsys package "$pkg" 2>/dev/null | grep -E "Package \\[|versionCode=|pkgFlags=|privateFlags=|installerPackageName=|codePath=|resourcePath=|dataDir=|sharedUserId=|enabled=|stopped=|hidden=|suspended=" | sed -n "1,80p"
done' | tee -a "$REPORT"

section "current window and keyguard"
adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,80p"' | tee -a "$REPORT" || true

section "SystemUI service snippets"
adb_shell 'dumpsys activity service com.android.systemui/.SystemUIService 2>/dev/null | sed -n "1,140p"' | tee -a "$REPORT" || true

section "recent logs matching dark mode"
adb_shell 'logcat -d -t 300 2>/dev/null | grep -Ei "UiMode|NightMode|toggleDarkMode|QSTileHost|QuickWidget|BrightnessSettings|SettingsProvider" | tail -n 120' | tee -a "$REPORT" || true

section "summary"
secure_ui_night="$(adb_shell 'settings get secure ui_night_mode 2>/dev/null || true' | tail -n 1)"
system_ui_night="$(adb_shell 'settings get system ui_night_mode 2>/dev/null || true' | tail -n 1)"
global_ui_night="$(adb_shell 'settings get global ui_night_mode 2>/dev/null || true' | tail -n 1)"
system_expanded="$(adb_shell 'settings get system expanded_widget_buttons 2>/dev/null || true' | tail -n 1)"
system_additional="$(adb_shell 'settings get system expanded_widget_buttons_additional 2>/dev/null || true' | tail -n 1)"
secure_expanded="$(adb_shell 'settings get secure expanded_widget_buttons 2>/dev/null || true' | tail -n 1)"
secure_additional="$(adb_shell 'settings get secure expanded_widget_buttons_additional 2>/dev/null || true' | tail -n 1)"
sysui_tiles="$(adb_shell 'settings get secure sysui_qs_tiles 2>/dev/null || true' | tail -n 1)"

log "secure.ui_night_mode=${secure_ui_night}"
log "system.ui_night_mode=${system_ui_night}"
log "global.ui_night_mode=${global_ui_night}"
log "system.expanded_widget_buttons=${system_expanded}"
log "system.expanded_widget_buttons_additional=${system_additional}"
log "secure.expanded_widget_buttons=${secure_expanded}"
log "secure.expanded_widget_buttons_additional=${secure_additional}"
log "secure.sysui_qs_tiles=${sysui_tiles}"
log "result=PASS_READ_ONLY"
log "report=${REPORT}"
