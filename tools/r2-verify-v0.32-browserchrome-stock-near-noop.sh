#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.32-browserchrome-stock-near-noop"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-v0.32-browserchrome-stock-near-noop"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
SOURCE_V029="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}-exact-current.SHA256SUMS.txt"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
STOCK_BROWSER_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/app/BrowserChrome/BrowserChrome.apk"
BROWSER_DIR="/system/app/BrowserChrome"
BROWSER_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSER_DEVICE_DIR="/system/app/BrowserChrome"
BROWSER_DEVICE_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSER_DIR_MTIME="0x6a34dae0"
BROWSER_DIR_MTIME_DEC="1781848800"
STOCK_BROWSER_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh --offline-image
  tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh --read-only

--offline-image verifies the generated v0.32 sparse super:
  - only system_b is the intended patched partition
  - system_b slice in sparse matches the generated system image
  - source-retained partitions match v0.29 by logical sparse hash
  - /system/app/BrowserChrome directory mtime is bumped for PackageCacher freshness
  - /system/app/BrowserChrome/BrowserChrome.apk remains byte-identical to stock

--read-only verifies a flashed device without changing /data. It checks boot
state, BrowserChrome package path/hash, package directory mtime, default web
resolver, and keyguard/launcher state.
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

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1"
  local path="$2"
  local key="$3"
  local expected
  local actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

verify_package_dir_mtime() {
  local image="$1"
  local path="$2"
  local expected="$3"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1)"
  grep -q "Type: directory" <<<"$output" || die "expected package directory: ${path}"
  grep -q "mtime: ${expected}:" <<<"$output" \
    || die "package directory mtime mismatch for ${path}; expected ${expected}"
  echo "package_dir_mtime=ok path=${path} mtime=${expected}"
}

verify_retained_sparse_extents() {
  python3 - "$SPARSE_TOOL" "$SOURCE_V029" "$EXPECTED_SUPER" <<'PY'
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

tool, source, out = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("r2_sparse_partition_patch", tool)
if spec is None or spec.loader is None:
    raise SystemExit(f"cannot load {tool}")
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

source_header, source_chunks = mod.parse_sparse(source)
out_header, out_chunks = mod.parse_sparse(out)
for part in ["product_b", "system_ext_b", "vendor_b", "odm_b"]:
    source_hash = mod.hash_sparse_logical_extent(source, source_header, source_chunks, mod.EXTENTS[part])
    out_hash = mod.hash_sparse_logical_extent(out, out_header, out_chunks, mod.EXTENTS[part])
    if source_hash != out_hash:
        raise SystemExit(f"{part} changed unexpectedly: source={source_hash} out={out_hash}")
    print(f"{part}\tretained={source_hash}")
PY
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
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
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## local files"
    need_file "$MANIFEST"
    check_manifest_hash "candidate_sparse" "$EXPECTED_SUPER" "sparse_super_sha256"
    check_manifest_hash "system_image" "$EXPECTED_SYSTEM_IMG" "system_b_sha256"
    check_manifest_hash "source_sparse" "$SOURCE_V029" "source_sparse_super_sha256"
    need_file "$STOCK_BROWSER_APK"
    [ "$(sha256_one "$STOCK_BROWSER_APK")" = "$STOCK_BROWSER_SHA256" ] \
      || die "stock BrowserChrome APK hash mismatch"
    echo "stock_browser_sha256=${STOCK_BROWSER_SHA256}"
    echo

    echo "## manifest gates"
    [ "$(manifest_value patched_partitions)" = "system_b" ] \
      || die "manifest patched_partitions is not system_b"
    [ "$(manifest_value browser_dir)" = "$BROWSER_DIR" ] \
      || die "manifest browser_dir mismatch"
    [ "$(manifest_value browser_apk)" = "$BROWSER_APK" ] \
      || die "manifest browser_apk mismatch"
    [ "$(manifest_value stock_browser_sha256)" = "$STOCK_BROWSER_SHA256" ] \
      || die "manifest stock_browser_sha256 mismatch"
    [ "$(manifest_value package_dir_mtime_hex)" = "$BROWSER_DIR_MTIME" ] \
      || die "manifest package_dir_mtime_hex mismatch"
    source_system="$(manifest_value source_system_b_sha256)"
    system="$(manifest_value system_b_sha256)"
    [ -n "$source_system" ] || die "manifest missing source_system_b_sha256"
    [ "$source_system" != "$system" ] \
      || die "system image hash did not change; expected mtime-only near-noop delta"
    echo "patched_partitions=system_b"
    echo "source_system_b_sha256=${source_system}"
    echo "system_b_sha256=${system}"
    echo

    echo "## system image gates"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_IMG" >/dev/null
    verify_package_dir_mtime "$EXPECTED_SYSTEM_IMG" "$BROWSER_DIR" "$BROWSER_DIR_MTIME"
    dumped="${WORK_DIR}/offline-BrowserChrome.apk"
    debugfs_dump "$EXPECTED_SYSTEM_IMG" "$BROWSER_APK" "$dumped"
    dumped_hash="$(sha256_one "$dumped")"
    [ "$dumped_hash" = "$STOCK_BROWSER_SHA256" ] \
      || die "dumped BrowserChrome APK hash mismatch: ${dumped_hash}"
    unzip -t "$dumped" >/dev/null
    echo "browser_apk_bytes=stock"
    echo "dumped_browser=${dumped}"
    echo "dumped_browser_sha256=${dumped_hash}"
    echo

    echo "## sparse slice gates"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" \
      --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## retained partition gates"
    verify_retained_sparse_extents
    echo

    echo "result=PASS_OFFLINE_IMAGE"
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
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] \
      || die "device has not completed boot"
    echo

    echo "## root status"
    if [ -x "$ROOT_HELPER" ]; then
      "$ROOT_HELPER" status || true
    else
      echo "missing_root_helper=${ROOT_HELPER}"
    fi
    echo

    echo "## BrowserChrome package path and hash"
    paths="$(adb_shell 'pm path com.android.browser 2>/dev/null | tr "\n" " " || true' | tail -n 1)"
    echo "pm_path=${paths}"
    grep -q "package:${BROWSER_DEVICE_APK}" <<<"$paths" \
      || die "com.android.browser is not loaded from ${BROWSER_DEVICE_APK}"
    live_hash="$(adb_shell "sha256sum ${BROWSER_DEVICE_APK} 2>/dev/null | awk '{print \\$1}'" | tail -n 1)"
    [ "$live_hash" = "$STOCK_BROWSER_SHA256" ] \
      || die "live BrowserChrome APK hash mismatch: ${live_hash}"
    echo "live_browser_sha256=${live_hash}"
    live_mtime="$(adb_shell "stat -c %Y ${BROWSER_DEVICE_DIR} 2>/dev/null || true" | tail -n 1)"
    echo "live_browser_dir_mtime_epoch=${live_mtime}"
    [ "$live_mtime" = "$BROWSER_DIR_MTIME_DEC" ] \
      || die "live BrowserChrome directory mtime mismatch: ${live_mtime} != ${BROWSER_DIR_MTIME_DEC}"
    echo

    echo "## default browser resolver"
    adb_shell 'cmd package resolve-activity --brief \
  -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d https://example.com 2>&1 | sed -n "1,80p" || true;
cmd package query-activities --brief \
  -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER \
  com.android.browser 2>&1 | sed -n "1,80p" || true'
    echo

    echo "## current window and keyguard"
    adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,100p"' || true
    echo

    echo "result=PASS_READ_ONLY"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$DEBUGFS"
    need_executable "$E2FSCK"
    need_executable "$SPARSE_TOOL"
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
