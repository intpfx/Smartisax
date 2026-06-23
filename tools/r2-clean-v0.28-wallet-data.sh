#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/v0.28-wallet-handshaker-debloat}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/wallet-data-clean-${TS}.txt}"
WALLET_PKG="com.smartisanos.wallet"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-clean-v0.28-wallet-data.sh [--dry-run]
  tools/r2-clean-v0.28-wallet-data.sh --apply

This handles the live /data side after v0.28 boots:
  - default dry-run prints current Wallet package paths and resolver surfaces
  - --apply asks PackageManager to remove the Wallet updated-system package
    and uninstall Wallet for user 0

It never flashes, reboots, erases misc, or deletes /data/app files directly.
Use --apply only after explicit user approval for this Wallet /data cleanup.
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

require_device() {
  if ! adb_available; then
    adb devices -l >&2 || true
    die "adb device ${SERIAL} is not online"
  fi
}

snapshot_wallet() {
  local pkg="$WALLET_PKG"
  section "package ${pkg}"
  run_pm "pm path $(sq "$pkg")"
  run_pm "cmd package list packages -u -f | awk -v pkg=$(sq "$pkg") 'BEGIN { suffix = \"=\" pkg } substr(\$0, length(\$0) - length(suffix) + 1) == suffix { print }'"
  run_pm "dumpsys package $(sq "$pkg") | grep -E 'Package \\[|codePath=|resourcePath=|legacyNativeLibraryDir=|pkgFlags=|privateFlags=|User 0:' | sed -n '1,80p'"
}

snapshot_surfaces() {
  section "wallet resolver surfaces"
  run_pm "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER | grep -iE 'smartisanos.wallet|WalletSmartisan|Wallet'"
  run_pm "cmd package query-activities --brief -a com.smartisanos.wallet.action.lockscreen_home | grep -iE 'smartisanos.wallet|WalletSmartisan|Wallet'"
  run_pm "cmd package query-services --brief -a android.nfc.cardemulation.action.HOST_APDU_SERVICE | grep -iE 'smartisanos.wallet|WalletSmartisan|Wallet'"
  run_pm "dumpsys package providers | grep -i -A3 -B3 'smartisanos.wallet'"
}

snapshot_all() {
  section "device state"
  run_pm "getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop sys.usb.state"
  section "window state"
  run_pm "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | sed -n '1,12p'"
  snapshot_wallet
  snapshot_surfaces
}

apply_cleanup() {
  local quoted
  quoted="$(sq "$WALLET_PKG")"

  section "apply cleanup"
  run_pm "am force-stop ${quoted}"
  run_pm "cmd package uninstall-system-updates ${quoted}"
  run_pm "pm uninstall --user 0 ${quoted}"

  if adb_shell "pm path ${quoted} 2>/dev/null || true" | grep -q '^package:'; then
    run_pm "pm uninstall ${quoted}"
  fi

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

log "# v0.28 Wallet live /data cleanup"
log "mode=${mode}"
log "serial=${SERIAL}"
log "report=${REPORT}"

snapshot_all

if [ "$mode" = "dry-run" ]; then
  section "result"
  log "Dry run only. Re-run with --apply only after explicit approval."
  exit 0
fi

apply_cleanup
snapshot_all

section "result"
log "Applied PackageManager cleanup for v0.28 Wallet updated-system /data residue."
