#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
VARIANT="v0.portal6a-marker-draw-sync"
RESULT_NAME="PASS_FLASH_V0PORTAL6A_MARKER_DRAW_SYNC"
IMAGE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal6a-marker-draw-sync.sparse.img"
EXPECTED_IMAGE_SHA256="b8d2bbe12c3d889fa83963ea8d8e31e2a47b2a460c075d11b29ba4d1676fcc2a"
CONFIRM_PHRASE="确认刷入 v0.portal6a-marker-draw-sync B 槽"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
VERIFY_SCRIPT="${ROOT_DIR}/tools/r2-verify-v0.portal6a-marker-draw-sync.sh"
PREFLIGHT_SCRIPT="${ROOT_DIR}/tools/r2-live-flash-preflight.sh"

usage() {
  cat <<USAGE
Usage:
  tools/r2-live-flash-v0.portal6a-marker-draw-sync.sh --confirm "${CONFIRM_PHRASE}"

This is a mutating live-device helper. It refuses to run unless --confirm
matches the exact phrase above. When confirmed, it runs read-only preflight,
checks the pinned sparse hash, reboots the R2 to bootloader, flashes super,
erases misc, reboots, waits for boot completion, and runs the read-only
v0.portal6a verifier.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_executable() {
  command -v "$1" >/dev/null 2>&1 || die "missing executable: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

wait_for_fastboot() {
  local deadline=$((SECONDS + 90))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if fastboot devices | awk '{print $1}' | grep -q "^${SERIAL}$"; then
      return 0
    fi
    sleep 1
  done
  fastboot devices -l || true
  die "device ${SERIAL} did not enter fastboot"
}

wait_for_adb_device() {
  local deadline=$((SECONDS + 180))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
      return 0
    fi
    sleep 2
  done
  adb devices -l || true
  die "device ${SERIAL} did not return to adb"
}

wait_for_boot_completed() {
  local deadline=$((SECONDS + 240))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local boot_completed slot bootanim verified
    boot_completed="$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    slot="$(adb -s "$SERIAL" shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r' || true)"
    bootanim="$(adb -s "$SERIAL" shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r' || true)"
    verified="$(adb -s "$SERIAL" shell getprop ro.boot.verifiedbootstate 2>/dev/null | tr -d '\r' || true)"
    printf 'boot_poll boot_completed=%s slot=%s bootanim=%s verified=%s\n' \
      "$boot_completed" "$slot" "$bootanim" "$verified"
    if [ "$boot_completed" = "1" ]; then
      return 0
    fi
    sleep 3
  done
  die "device ${SERIAL} did not reach sys.boot_completed=1"
}

confirm_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --confirm)
      [ "$#" -ge 2 ] || die "--confirm requires a value"
      confirm_arg="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ "$confirm_arg" = "$CONFIRM_PHRASE" ] || {
  usage >&2
  die "exact confirmation phrase is required"
}

need_executable adb
need_executable fastboot
need_executable shasum
need_executable awk
need_executable grep

[ -x "$PREFLIGHT_SCRIPT" ] || die "missing executable: $PREFLIGHT_SCRIPT"
[ -x "$VERIFY_SCRIPT" ] || die "missing executable: $VERIFY_SCRIPT"
[ -f "$IMAGE" ] || die "missing image: $IMAGE"

mkdir -p "$INSPECT_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
report="${INSPECT_DIR}/flash-${VARIANT}-${stamp}.txt"
boot_report="${INSPECT_DIR}/boot-wait-${VARIANT}-${stamp}.txt"
focus_report="${INSPECT_DIR}/post-flash-focus-${VARIANT}-${stamp}.txt"

exec > >(tee "$report") 2>&1

echo "# ${VARIANT} live flash"
echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
echo "serial=${SERIAL}"
echo "image=${IMAGE}"
echo "expected_image_sha256=${EXPECTED_IMAGE_SHA256}"
echo "confirmation=${confirm_arg}"
echo "boundary=mutating live flash was explicitly confirmed by the exact phrase"

echo
echo "## preflight"
"$PREFLIGHT_SCRIPT" "$VARIANT"

echo
echo "## pinned image hash"
actual_hash="$(sha256_one "$IMAGE")"
echo "actual_image_sha256=${actual_hash}"
[ "$actual_hash" = "$EXPECTED_IMAGE_SHA256" ] \
  || die "candidate image hash mismatch: actual=${actual_hash} expected=${EXPECTED_IMAGE_SHA256}"

echo
echo "## adb reboot bootloader"
adb -s "$SERIAL" reboot bootloader
wait_for_fastboot

echo
echo "## fastboot read-only state"
fastboot -s "$SERIAL" getvar current-slot 2>&1 || true
fastboot -s "$SERIAL" getvar unlocked 2>&1 || true
fastboot -s "$SERIAL" getvar is-userspace 2>&1 || true

echo
echo "## fastboot flash super"
fastboot -s "$SERIAL" flash super "$IMAGE"

echo
echo "## fastboot erase misc"
fastboot -s "$SERIAL" erase misc

echo
echo "## fastboot reboot"
fastboot -s "$SERIAL" reboot

echo
echo "## boot wait"
{
  wait_for_adb_device
  wait_for_boot_completed
} | tee "$boot_report"

echo
echo "## read-only verifier"
"$VERIFY_SCRIPT" --read-only

echo
echo "## focus/keyguard snapshot"
{
  adb -s "$SERIAL" shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate' | tr -d '\r'
  adb -s "$SERIAL" shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head -n 20" | tr -d '\r' || true
} | tee "$focus_report"

echo
echo "result=${RESULT_NAME}"
echo "report=${report}"
echo "boot_report=${boot_report}"
echo "focus_report=${focus_report}"
