#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.12-framework-res-noop"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.12-framework-res-noop.img"
EXPECTED_FW_RES="${ROOT_DIR}/hard-rom/build/apk/framework-res-rebuild-noop.apk"

mode="read-only"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.12-framework-res-noop.sh --offline-image
  tools/r2-verify-v0.12-framework-res-noop.sh --offline-system-image
  tools/r2-verify-v0.12-framework-res-noop.sh [--read-only]

--offline-image verifies the generated system image on the Mac:
  - framework-res.apk inside system_b matches framework-res-rebuild-noop.apk
  - the flashable sparse super exists
  - the sparse super system_b logical slice matches the generated system image
  - the expected APK has the known resources.arsc digest-error boundary
  - dumped APK ZIP integrity passes

--offline-system-image verifies only the generated system image on the Mac:
  - framework-res.apk inside system_b matches framework-res-rebuild-noop.apk
  - the expected APK has the known resources.arsc digest-error boundary
  - dumped APK ZIP integrity passes

--read-only verifies after a v0.12 flash on the live device:
  - boot/slot/root/window/logcat evidence is captured
  - pulled /system/framework/framework-res.apk matches the expected no-op APK

The script never flashes, reboots, erases misc, or changes /data.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    adb devices >&2
    die "device ${SERIAL} is not available over adb"
  fi
}

verify_resource_sig_boundary() {
  local apk="$1"
  local report="$2"
  "$SIGCHECK" "$apk" > "$report"
  grep -q '^keytool_status=1$' "$report" \
    || die "unexpected keytool boundary for ${apk}"
  grep -q 'SHA-256 digest error for resources.arsc' "$report" \
    || die "expected resources.arsc digest boundary missing for ${apk}"
}

compare_file_hash() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local actual_hash
  local expected_hash
  actual_hash="$(sha256_one "$actual")"
  expected_hash="$(sha256_one "$expected")"
  [ "$actual_hash" = "$expected_hash" ] || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$actual"
}

verify_expected_inputs() {
  need_file "$EXPECTED_FW_RES"
  need_file "$SIGCHECK"
  need_executable "$SIGCHECK"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  verify_expected_inputs
  need_executable "$SPARSE_TOOL"
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.12-offline-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.12-framework-res-noop offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## signature boundary"
    verify_resource_sig_boundary "$EXPECTED_FW_RES" "${dump_dir}/framework-res.signature.txt"
    echo "signature_boundary=ok"
    echo

    echo "## system_b inserted APK"
    "$DEBUGFS" -R "dump /system/framework/framework-res.apk ${dump_dir}/framework-res.apk" "$EXPECTED_SYSTEM_IMG" >/dev/null 2>&1
    compare_file_hash "${dump_dir}/framework-res.apk" "$EXPECTED_FW_RES" "system/framework-res.apk"
    unzip -t "${dump_dir}/framework-res.apk" >/dev/null
    echo "zip_integrity=ok"
    echo

    echo "## sparse system_b slice"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" "$EXPECTED_FW_RES"
  } | tee "$report"

  echo
  echo "PASS: v0.12 offline image verification"
  echo "Report: ${report}"
}

run_offline_system_image() {
  need_executable "$DEBUGFS"
  need_file "$EXPECTED_SYSTEM_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.12-offline-system-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-system-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.12-framework-res-noop offline system image verification"
    echo "timestamp=${timestamp}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## signature boundary"
    verify_resource_sig_boundary "$EXPECTED_FW_RES" "${dump_dir}/framework-res.signature.txt"
    echo "signature_boundary=ok"
    echo

    echo "## system_b inserted APK"
    "$DEBUGFS" -R "dump /system/framework/framework-res.apk ${dump_dir}/framework-res.apk" "$EXPECTED_SYSTEM_IMG" >/dev/null 2>&1
    compare_file_hash "${dump_dir}/framework-res.apk" "$EXPECTED_FW_RES" "system/framework-res.apk"
    unzip -t "${dump_dir}/framework-res.apk" >/dev/null
    echo "zip_integrity=ok"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SYSTEM_IMG" "$EXPECTED_FW_RES"
  } | tee "$report"

  echo
  echo "PASS: v0.12 offline system image verification"
  echo "Report: ${report}"
}

run_read_only_device() {
  need_file "$EXPECTED_SUPER"
  verify_expected_inputs
  require_device
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.12-device-${timestamp}.txt"
  local pull_dir="${INSPECT_DIR}/device-${timestamp}"
  mkdir -p "$pull_dir"

  {
    echo "# v0.12-framework-res-noop device verification"
    echo "timestamp=${timestamp}"
    echo "serial=${SERIAL}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo

    echo "## adb"
    adb devices -l
    echo

    echo "## boot state"
    adb_device shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint; getprop persist.sys.locale; settings get system system_locales' | tr -d '\r'
    echo

    echo "## root"
    "$ROOT_HELPER" status || true
    echo

    echo "## path label"
    adb_device shell 'ls -lZ /system/framework/framework-res.apk 2>/dev/null' | tr -d '\r'
    echo

    echo "## window excerpt"
    adb_device shell "dumpsys window" > "${pull_dir}/window.txt" || true
    rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing" "${pull_dir}/window.txt" || true
    echo

    echo "## logcat excerpt"
    adb_device logcat -d -t 800 > "${pull_dir}/logcat.txt" || true
    rg -n "ResourcesManager|ResourcesImpl|AssetManager|OverlayManager|idmap|PackageManager|framework-res|FATAL EXCEPTION" "${pull_dir}/logcat.txt" || true
    echo
  } | tee "$report"

  adb_device pull /system/framework/framework-res.apk "${pull_dir}/framework-res.apk" >/dev/null
  compare_file_hash "${pull_dir}/framework-res.apk" "$EXPECTED_FW_RES" "device/framework-res.apk" | tee -a "$report"
  unzip -t "${pull_dir}/framework-res.apk" >/dev/null

  echo
  echo "PASS: v0.12 device read-only verification"
  echo "Report: ${report}"
}

case "${1:---read-only}" in
  --offline-image)
    mode="offline-image"
    ;;
  --offline-system-image)
    mode="offline-system-image"
    ;;
  --read-only|"")
    mode="read-only"
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

case "$mode" in
  offline-image)
    run_offline_image
    ;;
  offline-system-image)
    run_offline_system_image
    ;;
  read-only)
    run_read_only_device
    ;;
esac
