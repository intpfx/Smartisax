#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/language-live-state}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/language-live-state-${TS}.txt}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-language-live-state-audit.sh

Environment:
  SERIAL       Android serial, default bb12d264
  OUT_DIR      Report directory, default hard-rom/inspect/language-live-state
  REPORT       Report path override
  ROOT_HELPER  Root wrapper, default tools/r2-root.sh

This script is read-only. It does not reboot, flash, erase misc, write settings,
change packages, delete data, or mutate /data. It only collects current live
locale/package state needed to design and verify English/Chinese-only ROM
language pruning.
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

log "# R2 Language Live State Audit"
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
printf "ro.build.fingerprint=%s\n" "$(getprop ro.build.fingerprint)";
printf "persist.sys.locale=%s\n" "$(getprop persist.sys.locale)";
printf "persist.sys.language=%s\n" "$(getprop persist.sys.language)";
printf "persist.sys.country=%s\n" "$(getprop persist.sys.country)";
printf "ro.product.locale=%s\n" "$(getprop ro.product.locale)";
printf "ro.product.locale.language=%s\n" "$(getprop ro.product.locale.language)";
printf "ro.product.locale.region=%s\n" "$(getprop ro.product.locale.region)"' | tee -a "$REPORT"

section "root status"
if [ -x "$ROOT_HELPER" ]; then
  run_cmd "$ROOT_HELPER" cmd 'id; getenforce; getprop ro.boot.slot_suffix'
else
  log "missing_root_helper=${ROOT_HELPER}"
fi

section "activity locale configuration"
adb_shell 'am get-config 2>/dev/null | sed -n "1,120p"' | tee -a "$REPORT" || true
adb_shell 'cmd activity get-config 2>/dev/null | sed -n "1,120p"' | tee -a "$REPORT" || true
adb_shell 'dumpsys activity settings 2>/dev/null | grep -Ei "locale|mConfiguration|Configuration|system_locales" | sed -n "1,120p"' | tee -a "$REPORT" || true

section "settings locale keys"
adb_shell 'for ns in system secure global; do
  for key in \
    system_locales \
    locale \
    user_set_locale \
    selected_input_method_subtype \
    default_input_method \
    user_setup_complete \
    device_provisioned; do
      value="$(settings get "$ns" "$key" 2>/dev/null || true)"
      printf "%s.%s=%s\n" "$ns" "$key" "$value"
  done
done' | tee -a "$REPORT"

section "package paths for language-sensitive targets"
adb_shell 'for pkg in \
  android \
  com.android.settings \
  com.android.providers.settings \
  com.android.protips \
  com.android.printservice.recommendation \
  com.android.hotspot2.osulogin \
  com.android.dreams.basic \
  com.android.dreams.phototable \
  com.android.htmlviewer \
  com.android.printspooler \
  com.android.wallpaper.livepicker \
  com.android.contacts; do
    echo "### package ${pkg}"
    pm path "$pkg" 2>/dev/null | sed -n "1,20p"
    dumpsys package "$pkg" 2>/dev/null | grep -E "Package \\[|versionCode=|codePath=|resourcePath=|dataDir=|pkgFlags=|privateFlags=|sharedUserId=|enabled=|stopped=|hidden=|suspended=" | sed -n "1,80p"
done' | tee -a "$REPORT"

section "updated-system shadow check"
adb_shell 'for pkg in \
  com.android.settings \
  com.android.providers.settings \
  com.android.protips \
  com.android.printservice.recommendation \
  com.android.hotspot2.osulogin \
  com.android.dreams.basic \
  com.android.dreams.phototable \
  com.android.htmlviewer \
  com.android.printspooler \
  com.android.wallpaper.livepicker \
  com.android.contacts; do
    paths="$(pm path "$pkg" 2>/dev/null | tr "\n" " ")"
    case "$paths" in
      *"/data/app/"*) shadow="yes" ;;
      *) shadow="no" ;;
    esac
    printf "%s.path=%s\n" "$pkg" "$paths"
    printf "%s.updated_system_shadow=%s\n" "$pkg" "$shadow"
done' | tee -a "$REPORT"

section "current window and keyguard"
adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,80p"' | tee -a "$REPORT" || true

section "recent logs matching language and resources"
adb_shell 'logcat -d -t 400 2>/dev/null | grep -Ei "LocalePicker|AssetManager|ResourcesImpl|ResourcesManager|MccTable|IccRecords|RuimRecords|SettingsProvider|PackageManager|locale" | tail -n 160' | tee -a "$REPORT" || true

section "summary"
persist_locale="$(adb_shell 'getprop persist.sys.locale 2>/dev/null || true' | tail -n 1)"
ro_locale="$(adb_shell 'getprop ro.product.locale 2>/dev/null || true' | tail -n 1)"
system_locales="$(adb_shell 'settings get system system_locales 2>/dev/null || true' | tail -n 1)"
secure_locales="$(adb_shell 'settings get secure system_locales 2>/dev/null || true' | tail -n 1)"
global_locales="$(adb_shell 'settings get global system_locales 2>/dev/null || true' | tail -n 1)"
input_method="$(adb_shell 'settings get secure default_input_method 2>/dev/null || true' | tail -n 1)"
input_subtype="$(adb_shell 'settings get secure selected_input_method_subtype 2>/dev/null || true' | tail -n 1)"

log "persist.sys.locale=${persist_locale}"
log "ro.product.locale=${ro_locale}"
log "system.system_locales=${system_locales}"
log "secure.system_locales=${secure_locales}"
log "global.system_locales=${global_locales}"
log "secure.default_input_method=${input_method}"
log "secure.selected_input_method_subtype=${input_subtype}"
log "result=PASS_READ_ONLY"
log "report=${REPORT}"
