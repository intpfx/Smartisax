#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
VARIANT="v0.agent0.4-home-onestep-settings-guard"
RESULT_NAME="PASS_FLASH_V0AGENT04_HOME_ONESTEP_SETTINGS_GUARD"
IMAGE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.agent0.4-home-onestep-settings-guard.sparse.img"
EXPECTED_IMAGE_SHA256_FILE="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.agent0.4-home-onestep-settings-guard.SHA256SUMS.txt"
CONFIRM_PHRASE="确认刷入 v0.agent0.4-home-onestep-settings-guard B 槽"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
VERIFY_SCRIPT="${ROOT_DIR}/tools/r2-verify-v0.agent0.4-home-onestep-settings-guard.sh"
PREFLIGHT_SCRIPT="${ROOT_DIR}/tools/r2-live-flash-preflight.sh"

usage() {
  cat <<USAGE
Usage:
  tools/r2-live-flash-v0.agent0.4-home-onestep-settings-guard.sh --confirm "${CONFIRM_PHRASE}"

This is a mutating live-device helper. It refuses to run unless --confirm
matches the exact phrase above. When confirmed, it runs read-only preflight,
checks the built sparse hash from its manifest, reboots the R2 to bootloader,
flashes super, erases misc, reboots, waits for boot completion, and runs the
	read-only v0.agent0.4 verifier.
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
    echo "boot_poll boot_completed=${boot_completed:-?} slot=${slot:-?} bootanim=${bootanim:-?} verified=${verified:-?}"
    if [ "$boot_completed" = "1" ]; then
      return 0
    fi
    sleep 5
  done
  die "device ${SERIAL} did not boot"
}

confirm=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --confirm)
      shift
      [ "$#" -gt 0 ] || die "--confirm requires a value"
      confirm="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[ "$confirm" = "$CONFIRM_PHRASE" ] || {
  usage >&2
  die "missing exact confirmation phrase"
}

need_executable adb
need_executable fastboot
need_executable shasum

[ -f "$IMAGE" ] || die "missing sparse image: $IMAGE"
expected_sha="$(expected_image_sha256)"
actual_sha="$(sha256_one "$IMAGE")"
[ "$actual_sha" = "$expected_sha" ] || die "sparse sha mismatch: actual=${actual_sha} expected=${expected_sha}"

mkdir -p "$INSPECT_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
flash_report="${INSPECT_DIR}/flash-${VARIANT}-${stamp}.txt"
boot_report="${INSPECT_DIR}/boot-wait-${VARIANT}-${stamp}.txt"

{
  echo "# ${VARIANT} live flash"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "serial=${SERIAL}"
  echo "image=${IMAGE}"
  echo "image_sha256=${actual_sha}"
  echo "confirmation=${confirm}"
  echo
  echo "## preflight"
  "$PREFLIGHT_SCRIPT" "$VARIANT"
  echo
  echo "## reboot bootloader"
  adb -s "$SERIAL" reboot bootloader
  wait_for_fastboot
  fastboot -s "$SERIAL" getvar current-slot 2>&1 || true
  fastboot -s "$SERIAL" getvar unlocked 2>&1 || true
  fastboot -s "$SERIAL" getvar is-userspace 2>&1 || true
  echo
  echo "## flash super"
  fastboot -s "$SERIAL" flash super "$IMAGE"
  echo
  echo "## erase misc"
  fastboot -s "$SERIAL" erase misc
  echo
  echo "## reboot"
  fastboot -s "$SERIAL" reboot
  echo "result=${RESULT_NAME}"
} 2>&1 | tee "$flash_report"

{
  echo "# ${VARIANT} boot wait"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  wait_for_adb_device
  wait_for_boot_completed
  echo
  echo "## read-only verify"
  "$VERIFY_SCRIPT" --read-only
} 2>&1 | tee "$boot_report"

echo "Flash report: $flash_report"
echo "Boot report: $boot_report"
