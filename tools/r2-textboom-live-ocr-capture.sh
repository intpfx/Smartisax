#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
TS="${TS:-$(date +%Y%m%d-%H%M%S)}"
LABEL="${LABEL:-textboom-live-ocr-capture-${TS}}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/textboom-ppocr-live-capture/${TS}}"
REPORT="${REPORT:-${OUT_DIR}/capture.txt}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-textboom-live-ocr-capture.sh [--probe-only]

Environment:
  SERIAL=bb12d264
  OUT_DIR=hard-rom/inspect/textboom-ppocr-live-capture/<timestamp>
  LABEL=textboom-live-ocr-capture-<timestamp>

Boundary:
  - captures live state, screenshots, UI hierarchy, and OCR-related logcat
  - launches TextBoom's smartisanos.intent.action.BOOM_IMAGE only when unlocked
  - does not flash, reboot, erase, uninstall, clear app data, or modify ROM images
  - writes only local reports plus a transient /sdcard/Download UI dump file
USAGE
}

PROBE_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-only)
      PROBE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUT_DIR"

adb_device() {
  adb -s "$SERIAL" "$@"
}

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

section() {
  log ""
  log "## $*"
}

capture_shell() {
  local name="$1"
  shift
  section "$name"
  adb_device shell "$@" 2>&1 | tee -a "$REPORT" || true
}

capture_screen() {
  local name="$1"
  local path="${OUT_DIR}/${name}.png"
  adb_device exec-out screencap -p > "$path"
  log "screenshot=${path}"
}

capture_focus() {
  capture_shell "$1" 'dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp|mShowingLockscreen|isKeyguardShowing|mDreamingLockscreen" | head -n 40'
}

capture_ui() {
  local name="$1"
  local remote="/sdcard/Download/${LABEL}-${name}.xml"
  local local_path="${OUT_DIR}/${name}.xml"
  section "ui ${name}"
  adb_device shell "uiautomator dump '${remote}' >/dev/null 2>&1 && cat '${remote}'" > "$local_path" || true
  log "ui=${local_path}"
}

capture_logcat() {
  local name="$1"
  local raw="${OUT_DIR}/${name}.logcat.txt"
  local filtered="${OUT_DIR}/${name}.ocr-filtered.logcat.txt"
  section "logcat ${name}"
  adb_device logcat -d -t 2500 > "$raw" || true
  LC_ALL=C grep -Ei 'TextBoom|BoomOcrActivity|OcrFloatViewService|CsOcr|CSOpenApi|CSOcr|CamScanner|camscanner|ACTION_OCR|RESPONSE_DATA|OCR|AndroidRuntime|FATAL EXCEPTION' "$raw" > "$filtered" || true
  log "logcat_raw=${raw}"
  log "logcat_filtered=${filtered}"
  tail -n 120 "$filtered" | tee -a "$REPORT" || true
}

is_keyguard_showing() {
  adb_device shell 'dumpsys window 2>/dev/null | grep -q "isKeyguardShowing=true"'
}

launch_textboom_image() {
  section "launch TextBoom BOOM_IMAGE"
  adb_device shell \
    am start -W \
      -a smartisanos.intent.action.BOOM_IMAGE \
      --ei boom_startx 540 \
      --ei boom_starty 1170 \
      --ei boom_offsetx 0 \
      --ei boom_offsety 0 \
      --ez boom_fullscreen false \
      --ez boom_from_float false \
      --es caller_pkg com.smartisax.browser \
    2>&1 | tee -a "$REPORT" || true
}

: > "$REPORT"
log "# ${LABEL}"
log "timestamp=${TS}"
log "serial=${SERIAL}"
log "out_dir=${OUT_DIR}"

section "adb"
adb_device devices | tee -a "$REPORT"

capture_shell "device" 'echo slot=$(getprop ro.boot.slot_suffix); echo boot=$(getprop sys.boot_completed); echo build=$(getprop ro.smartisan.version); echo android=$(getprop ro.build.version.release)'
capture_focus "focus-before"
capture_shell "packages" 'pm path com.smartisanos.textboom; pm path com.intsig.camscanner 2>/dev/null || true; dumpsys package com.smartisanos.textboom | grep -E "versionName|versionCode|codePath|dataDir|flags=|privateFlags=|signatures" | head -n 60'
capture_shell "resolvers" 'cmd package resolve-activity --brief -a smartisanos.intent.action.BOOM_IMAGE 2>/dev/null || true; cmd package query-activities --brief -a smartisanos.intent.action.BOOM_IMAGE 2>/dev/null || true'
capture_screen "00-before"
capture_ui "00-before"
capture_logcat "00-before"

if is_keyguard_showing; then
  section "result"
  log "result=BLOCKED_KEYGUARD"
  log "message=Unlock the phone to desktop and rerun this script."
  exit 3
fi

if [[ "$PROBE_ONLY" -eq 1 ]]; then
  section "result"
  log "result=PASS_PROBE_ONLY_UNLOCKED"
  exit 0
fi

launch_textboom_image
sleep 1
capture_focus "focus-after-start-1s"
capture_screen "01-after-start-1s"
capture_ui "01-after-start-1s"

sleep 2
capture_focus "focus-after-start-3s"
capture_screen "02-after-start-3s"
capture_ui "02-after-start-3s"
capture_logcat "02-after-start-3s"

section "result"
log "result=CAPTURE_COMPLETE"
log "note=If the UI shows the crop surface, use the saved screenshots/UI dump to decide the next exact tap/crop automation."
