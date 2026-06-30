#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
VARIANT="v0.portal6d-display-wake-guard"
RESULT_NAME="PASS_FLASH_V0PORTAL6D_DISPLAY_WAKE_GUARD"
IMAGE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal6d-display-wake-guard.sparse.img"
EXPECTED_IMAGE_SHA256_FILE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal6d-display-wake-guard.SHA256SUMS.txt"
CONFIRM_PHRASE="确认刷入 v0.portal6d-display-wake-guard B 槽"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
VERIFY_SCRIPT="${ROOT_DIR}/tools/r2-verify-v0.portal6d-display-wake-guard.sh"
PREFLIGHT_SCRIPT="${ROOT_DIR}/tools/r2-live-flash-preflight.sh"

usage() {
  cat <<USAGE
Usage:
  tools/r2-live-flash-v0.portal6d-display-wake-guard.sh --confirm "${CONFIRM_PHRASE}"

This is a mutating live-device helper. It refuses to run unless --confirm
matches the exact phrase above. When confirmed, it runs read-only preflight,
checks the built sparse hash from its manifest, reboots the R2 to bootloader,
flashes super, erases misc, reboots, waits for boot completion, and runs the
read-only v0.portal6d verifier.
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

expected_image_sha256() {
  [ -f "$EXPECTED_IMAGE_SHA256_FILE" ] || die "missing manifest: $EXPECTED_IMAGE_SHA256_FILE"
  awk -F= '
    $1 == "super_sparse_sha256" { print $2; found=1 }
    END { exit found ? 0 : 1 }
  ' "$EXPECTED_IMAGE_SHA256_FILE"
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

expected_sha="$(expected_image_sha256)"
[ -n "$expected_sha" ] || die "could not resolve expected sparse hash from ${EXPECTED_IMAGE_SHA256_FILE}"
actual_sha="$(sha256_one "$IMAGE")"
[ "$actual_sha" = "$expected_sha" ] || die "sparse hash mismatch: actual=${actual_sha} expected=${expected_sha}"

{
  echo "# ${VARIANT} live flash"
  echo "variant=${VARIANT}"
  echo "serial=${SERIAL}"
  echo "image=${IMAGE}"
  echo "image_sha256=${actual_sha}"
  echo "confirm=${confirm_arg}"
  echo
  "$PREFLIGHT_SCRIPT" "$VARIANT"
  echo
  echo "adb_reboot_bootloader=start"
  adb -s "$SERIAL" reboot bootloader
  wait_for_fastboot
  echo "fastboot_flash_super=start"
  fastboot -s "$SERIAL" flash super "$IMAGE"
  echo "fastboot_erase_misc=start"
  fastboot -s "$SERIAL" erase misc
  echo "fastboot_reboot=start"
  fastboot -s "$SERIAL" reboot
} | tee "$report"

wait_for_adb_device
wait_for_boot_completed | tee "$boot_report"

adb -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
  | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' \
  | tee "$focus_report" || true

"$VERIFY_SCRIPT" --read-only

echo "$RESULT_NAME"
