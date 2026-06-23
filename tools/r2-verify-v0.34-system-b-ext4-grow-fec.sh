#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.34-system-b-ext4-grow-fec"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-v0.34-system-b-ext4-grow-fec"

EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_FEC_EXT4_SIZE=3132964864
SYSTEM_B_FEC_BLOCKS=764884
SYSTEM_B_MIN_DF_1K=3000000
STOCK_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh --offline-image
  tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh --read-only

--offline-image verifies the generated v0.34 FEC-preserving sparse super:
  - local sparse and system_b hashes match the manifest
  - system_b ext4 has grown to the FEC-preserving block count
  - AVB hashtree footer keeps FEC num roots=2 and a nonzero FEC offset

--read-only verifies a flashed device without changing /data. It checks boot,
slot, root, system_b mapper size, /system df growth, stock WebView and
BrowserChrome hashes, WebViewUpdateService, keyguard, and launcher focus.
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

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1"
  local path="$2"
  local key="$3"
  local expected actual
  need_file "$MANIFEST"
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@"
}

write_report_header() {
  local report="$1"
  {
    echo "# ${VARIANT} verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "serial=${SERIAL}"
    echo "report=${report#${ROOT_DIR}/}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no package-cache clear, no /data cleanup"
    echo
  } > "$report"
}

run_offline_image() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-offline-preflight-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## local files"
    check_manifest_hash "candidate_sparse" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "grown_fec_system_b" "$EXPECTED_SYSTEM_B_IMG" "system_b_sha256"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] \
      || die "system_b image size mismatch"
    echo

    echo "## grown system_b filesystem"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    block_count="$(debugfs_stat_value "$EXPECTED_SYSTEM_B_IMG" "Block count")"
    free_blocks="$(debugfs_stat_value "$EXPECTED_SYSTEM_B_IMG" "Free blocks")"
    [ "$block_count" = "$SYSTEM_B_FEC_BLOCKS" ] \
      || die "grown system_b block count mismatch: ${block_count} != ${SYSTEM_B_FEC_BLOCKS}"
    echo "system_b_block_count=${block_count}"
    echo "system_b_free_blocks=${free_blocks}"
    echo

    echo "## AVB/FEC footer"
    python3 "$AVBTOOL" info_image --image "$EXPECTED_SYSTEM_B_IMG"
    python3 "$AVBTOOL" info_image --image "$EXPECTED_SYSTEM_B_IMG" > "${INSPECT_DIR}/candidate-system-b-avb-info-preflight.txt"
    grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "${INSPECT_DIR}/candidate-system-b-avb-info-preflight.txt" \
      || die "candidate system_b AVB image size mismatch"
    grep -q "Original image size:      ${SYSTEM_B_FEC_EXT4_SIZE} bytes" "${INSPECT_DIR}/candidate-system-b-avb-info-preflight.txt" \
      || die "candidate system_b AVB original image size mismatch"
    grep -q "FEC num roots:         2" "${INSPECT_DIR}/candidate-system-b-avb-info-preflight.txt" \
      || die "candidate system_b lost FEC roots"
    grep -q "FEC offset:            [1-9]" "${INSPECT_DIR}/candidate-system-b-avb-info-preflight.txt" \
      || die "candidate system_b FEC offset is missing"
    grep -q "FEC size:              [1-9]" "${INSPECT_DIR}/candidate-system-b-avb-info-preflight.txt" \
      || die "candidate system_b FEC size is missing"
    echo

    echo "result=PASS_OFFLINE_IMAGE_FEC"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

run_read_only() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## adb"
    adb devices -l
    adb_available || die "adb device ${SERIAL} is not online"
    echo

    echo "## boot state"
    adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root status"
    "$ROOT_HELPER" status
    echo

    echo "## system_b size and df gates"
    mapper_size="$(root_cmd 'blockdev --getsize64 /dev/block/mapper/system_b 2>/dev/null || true' | tr -d '\r' | tail -n 1)"
    [ "$mapper_size" = "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b mapper size mismatch: ${mapper_size} != ${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_mapper_size=${mapper_size}"
    df_line="$(adb_shell 'df -k /system | tail -n 1')"
    echo "$df_line"
    df_blocks="$(awk '{print $2}' <<<"$df_line")"
    [[ "$df_blocks" =~ ^[0-9]+$ ]] || die "could not parse /system df 1K-block count: ${df_line}"
    [ "$df_blocks" -ge "$SYSTEM_B_MIN_DF_1K" ] \
      || die "/system df did not grow enough for v0.34: blocks_1k=${df_blocks} min=${SYSTEM_B_MIN_DF_1K}"
    echo "system_df_blocks_1k=${df_blocks}"
    echo

    echo "## package/content read-only hashes"
    hash_output="$(adb_shell 'sha256sum /product/app/webview/webview.apk /system/app/BrowserChrome/BrowserChrome.apk /system/etc/security/otacerts.zip /system/framework/framework-res.apk 2>/dev/null')"
    echo "$hash_output"
    grep -q "^${STOCK_WEBVIEW_SHA256}  /product/app/webview/webview.apk" <<<"$hash_output" \
      || die "live WebView hash mismatch"
    grep -q "^${STOCK_BROWSERCHROME_SHA256}  /system/app/BrowserChrome/BrowserChrome.apk" <<<"$hash_output" \
      || die "live BrowserChrome hash mismatch"
    echo

    echo "## WebViewUpdateService"
    adb_shell 'cmd webviewupdate get-current-webview-package || true'
    adb_shell 'dumpsys webviewupdate | sed -n "1,80p"'
    echo

    echo "## window state"
    window_output="$(adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head -n 20")"
    echo "$window_output"
    grep -q 'isKeyguardShowing=false' <<<"$window_output" \
      || die "keyguard is still showing"
    grep -Eq 'smt_launcher|com\.smartisanos\.launcher/\.Launcher' <<<"$window_output" \
      || die "launcher is not focused"
    echo

    echo "result=PASS_READ_ONLY"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$E2FSCK"
    need_executable "$DEBUGFS"
    need_file "$AVBTOOL"
    run_offline_image
    ;;
  --read-only)
    run_read_only
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
