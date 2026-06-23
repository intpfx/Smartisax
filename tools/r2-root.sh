#!/usr/bin/env bash
set -euo pipefail

SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"

usage() {
  cat <<'EOF'
Usage:
  tools/r2-root.sh status
  tools/r2-root.sh cmd <root-command>
  tools/r2-root.sh sh
  tools/r2-root.sh reboot
  tools/r2-root.sh bootloader
  tools/r2-root.sh recovery-help

Environment:
  SERIAL  Android serial, default bb12d264
  KP      APatch su path, default /system/bin/kp
EOF
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

remote_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

root_cmd() {
  adb_device shell "$KP -c $(remote_quote "$*")"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    echo "Device $SERIAL is not available over adb." >&2
    adb devices >&2
    exit 1
  fi
}

case "${1:-}" in
  status)
    require_device
    echo "adb:"
    adb devices -l | sed -n '1,3p'
    echo
    echo "root:"
    root_cmd 'id; getenforce; getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint'
    ;;
  cmd)
    shift
    if [ "$#" -eq 0 ]; then
      echo "Missing root command." >&2
      usage >&2
      exit 2
    fi
    require_device
    root_cmd "$*"
    ;;
  sh)
    require_device
    adb_device shell "$KP" -c /system/bin/sh
    ;;
  reboot)
    require_device
    adb_device reboot
    ;;
  bootloader)
    require_device
    adb_device reboot bootloader
    ;;
  recovery-help)
    cat <<'EOF'
Known-good slot B recovery:

  fastboot -s bb12d264 flash boot_b extracted/boot.img
  fastboot -s bb12d264 erase misc
  fastboot -s bb12d264 reboot

If fastboot does not see the device on macOS, reconnect USB while the phone is
on the fastboot screen.
EOF
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
