#!/usr/bin/env bash
set -euo pipefail

SERIAL="${SERIAL:-bb12d264}"
DEFAULT_WIRELESS_SERIAL="${WIRELESS_SERIAL:-192.168.31.103:42701}"
PORTAL_PORT="${PORTAL_PORT:-37601}"

usage() {
  cat <<'EOF'
Usage:
  tools/r2-mirror.sh [auto|usb|wireless] [scrcpy-args...]
  tools/r2-mirror.sh record <output.mp4> [seconds] [auto|usb|wireless]
  tools/r2-mirror.sh connect-wireless [host:port]
  tools/r2-mirror.sh portal-url [auto|usb|wireless] [port]
  tools/r2-mirror.sh devices

Environment:
  SERIAL           USB adb serial, default bb12d264
  WIRELESS_SERIAL  Preferred wireless adb serial, default 192.168.31.103:42701
  PORTAL_PORT      Smartisax portal port, default 37601

Examples:
  tools/r2-mirror.sh
  tools/r2-mirror.sh wireless --max-size=1600
  tools/r2-mirror.sh portal-url
  tools/r2-mirror.sh record hard-rom/inspect/v0.mirror0-scrcpy-live-proof/check.mp4 8 usb
EOF
}

require_adb() {
  command -v adb >/dev/null || {
    echo "adb not found in PATH." >&2
    exit 1
  }
}

require_scrcpy() {
  command -v scrcpy >/dev/null || {
    echo "scrcpy not found in PATH. Install it first, for example: brew install scrcpy" >&2
    exit 1
  }
}

require_tools() {
  require_adb
  require_scrcpy
}

adb_state() {
  local serial="$1"
  adb devices | awk -v serial="$serial" '$1 == serial { print $2; found=1 } END { if (!found) exit 1 }'
}

is_online() {
  local serial="$1"
  [ "$(adb_state "$serial" 2>/dev/null || true)" = "device" ]
}

first_wireless_online() {
  if is_online "$DEFAULT_WIRELESS_SERIAL"; then
    printf '%s\n' "$DEFAULT_WIRELESS_SERIAL"
    return 0
  fi
  adb devices | awk 'NR > 1 && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ && $2 == "device" { print $1; exit }'
}

try_connect_wireless() {
  local serial="${1:-$DEFAULT_WIRELESS_SERIAL}"
  if [ -z "$serial" ]; then
    return 1
  fi
  if is_online "$serial"; then
    printf '%s\n' "$serial"
    return 0
  fi
  adb connect "$serial" >&2 || true
  if is_online "$serial"; then
    printf '%s\n' "$serial"
    return 0
  fi
  return 1
}

target_lan_host() {
  local target="$1"
  if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
    printf '%s\n' "${target%:*}"
    return 0
  fi
  adb -s "$target" shell "ip -o -4 addr show wlan0 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -n1" \
    | tr -d '\r' \
    | sed -n '1p'
}

select_target() {
  local mode="${1:-auto}"
  case "$mode" in
    auto)
      if is_online "$SERIAL"; then
        printf '%s\n' "$SERIAL"
        return 0
      fi
      first_wireless_online || try_connect_wireless "$DEFAULT_WIRELESS_SERIAL"
      ;;
    usb)
      if is_online "$SERIAL"; then
        printf '%s\n' "$SERIAL"
      fi
      ;;
    wireless)
      first_wireless_online || try_connect_wireless "$DEFAULT_WIRELESS_SERIAL"
      ;;
    *)
      echo "Unknown mirror mode: $mode" >&2
      return 2
      ;;
  esac
}

main() {
  local cmd="${1:-auto}"
  case "$cmd" in
    -h|--help|help)
      usage
      return 0
      ;;
    devices)
      require_adb
      adb devices -l
      return 0
      ;;
    connect-wireless)
      require_adb
      local wireless_serial="${2:-$DEFAULT_WIRELESS_SERIAL}"
      local target
      target="$(try_connect_wireless "$wireless_serial")"
      if [ -z "$target" ]; then
        echo "Unable to connect wireless adb target: $wireless_serial" >&2
        return 1
      fi
      echo "Wireless adb target online: $target"
      return 0
      ;;
    portal-url)
      require_adb
      local mode="${2:-auto}"
      local port="${3:-$PORTAL_PORT}"
      local target
      target="$(select_target "$mode")"
      if [ -z "$target" ]; then
        echo "No online R2 adb target for mode '$mode'." >&2
        adb devices -l >&2
        return 1
      fi
      local host
      host="$(target_lan_host "$target")"
      if [ -z "$host" ]; then
        echo "Unable to determine R2 Wi-Fi IP from $target." >&2
        return 1
      fi
      printf 'http://%s:%s\n' "$host" "$port"
      return 0
      ;;
    record)
      require_tools
      local output="${2:-}"
      local seconds="${3:-8}"
      local mode="${4:-auto}"
      if [ -z "$output" ]; then
        echo "Missing output mp4 path." >&2
        usage >&2
        return 2
      fi
      local target
      target="$(select_target "$mode")"
      if [ -z "$target" ]; then
        echo "No online R2 adb target for mode '$mode'." >&2
        adb devices -l >&2
        return 1
      fi
      mkdir -p "$(dirname "$output")"
      echo "Recording R2 mirror from $target for ${seconds}s -> $output" >&2
      exec scrcpy -s "$target" --no-window --no-audio --time-limit="$seconds" --record="$output"
      ;;
    auto|usb|wireless)
      require_tools
      shift || true
      local target
      target="$(select_target "$cmd")"
      if [ -z "$target" ]; then
        echo "No online R2 adb target for mode '$cmd'." >&2
        adb devices -l >&2
        return 1
      fi
      echo "Starting R2 mirror via $target" >&2
      exec scrcpy -s "$target" "$@"
      ;;
    *)
      require_tools
      local target
      target="$(select_target auto)"
      if [ -z "$target" ]; then
        echo "No online R2 adb target." >&2
        adb devices -l >&2
        return 1
      fi
      echo "Starting R2 mirror via $target" >&2
      exec scrcpy -s "$target" "$@"
      ;;
  esac
}

main "$@"
