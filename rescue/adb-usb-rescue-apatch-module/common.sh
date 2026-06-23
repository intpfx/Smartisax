#!/system/bin/sh

MODDIR="${0%/*}"
LOG_DIR="/data/adb/smartisax/logs"
LOG_FILE="$LOG_DIR/adb-usb-rescue.log"

log_line() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

restore_adb_usb() {
  log_line "start mode=${1:-manual}"
  setprop persist.sys.usb.config mtp,adb 2>/dev/null || true
  setprop persist.vendor.usb.config mtp,adb 2>/dev/null || true
  setprop sys.usb.config none 2>/dev/null || true
  sleep 1
  setprop sys.usb.config mtp,adb 2>/dev/null || true
  svc usb setFunctions mtp,adb >/dev/null 2>&1 || true
  setprop ctl.restart adbd 2>/dev/null || true
  sleep 2
  log_line "sys.usb.config=$(getprop sys.usb.config 2>/dev/null) sys.usb.state=$(getprop sys.usb.state 2>/dev/null) adbd=$(getprop init.svc.adbd 2>/dev/null)"
}
