#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/v0.37a-textboom-live-system-base}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/textboom-data-clean-${TS}.txt}"
TEXTBOOM_PKG="com.smartisanos.textboom"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-clean-v0.37a-textboom-data.sh [--dry-run]
  tools/r2-clean-v0.37a-textboom-data.sh --apply

This handles the live /data side after v0.37a boots:
  - default dry-run prints current TextBoom package paths and Big Bang surfaces
  - --apply asks PackageManager to remove only the TextBoom updated-system
    package so the ROM /system/app/TextBoom base can become active

It never flashes, reboots, erases misc, or deletes /data/app files directly.
Use --apply only after explicit user approval for this TextBoom /data cleanup.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_shell() {
  adb -s "$SERIAL" shell "$1" 2>&1 | tr -d '\r'
}

sq() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

section() {
  log ""
  log "## $*"
}

run_pm() {
  local cmd="$1"
  log "\$ ${cmd}"
  adb_shell "${cmd} 2>&1 || true" | tee -a "$REPORT"
}

pm_path_for() {
  adb_shell "pm path $(sq "$1") 2>/dev/null | sed -n '1p'"
}

require_device() {
  if ! adb_available; then
    adb devices -l >&2 || true
    die "adb device ${SERIAL} is not online"
  fi
}

snapshot_textboom() {
  local pkg="$TEXTBOOM_PKG"
  section "package ${pkg}"
  run_pm "pm path $(sq "$pkg")"
  run_pm "cmd package list packages -u -f | awk -v pkg=$(sq "$pkg") 'BEGIN { suffix = \"=\" pkg } substr(\$0, length(\$0) - length(suffix) + 1) == suffix { print }'"
  run_pm "dumpsys package $(sq "$pkg") | grep -E 'Package \\[|codePath=|resourcePath=|legacyNativeLibraryDir=|versionCode=|versionName=|pkgFlags=|privateFlags=|User 0:' | sed -n '1,100p'"
}

snapshot_surfaces() {
  section "TextBoom/Big Bang resolver surfaces"
  run_pm "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER | grep -iE 'smartisanos.textboom|TextBoom|Boom'"
  run_pm "cmd package query-activities --brief -a com.smartisanos.textboom.action.BOOM_TEXT | grep -iE 'smartisanos.textboom|TextBoom|Boom'"
  run_pm "dumpsys package providers | grep -i -A3 -B3 'smartisanos.textboom'"
}

snapshot_all() {
  section "device state"
  run_pm "getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop sys.usb.state"
  section "window state"
  run_pm "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | sed -n '1,12p'"
  snapshot_textboom
  snapshot_surfaces
}

apply_cleanup() {
  local quoted
  quoted="$(sq "$TEXTBOOM_PKG")"

  section "apply cleanup"
  run_pm "am force-stop ${quoted}"
  run_pm "cmd package uninstall-system-updates ${quoted}"
  run_pm "pm path ${quoted}"
}

mode="dry-run"
case "${1:-}" in
  ""|--dry-run)
    mode="dry-run"
    ;;
  --apply)
    mode="apply"
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
mkdir -p "$OUT_DIR"
: > "$REPORT"

log "# v0.37a TextBoom live /data cleanup"
log "mode=${mode}"
log "serial=${SERIAL}"
log "report=${REPORT}"
log "boundary=no flash, no reboot, no direct /data/app deletion"

snapshot_all

if [ "$mode" = "dry-run" ]; then
  section "result"
  log "Dry run only. Re-run with --apply only after explicit approval."
  exit 0
fi

apply_cleanup
snapshot_all

section "result"
after_path="$(pm_path_for "$TEXTBOOM_PKG")"
case "$after_path" in
  package:/system/app/TextBoom/TextBoom.apk)
    log "Applied PackageManager cleanup for v0.37a TextBoom updated-system /data residue."
    ;;
  *)
    log "FAILED: PackageManager cleanup did not switch TextBoom to /system/app/TextBoom."
    log "active_path=${after_path:-missing}"
    log "No direct /data/app deletion was attempted by this script."
    exit 1
    ;;
esac
