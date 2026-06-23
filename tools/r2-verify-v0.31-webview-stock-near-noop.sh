#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
DONOR_AUDIT="${DONOR_AUDIT:-${ROOT_DIR}/tools/r2-webview-donor-audit.py}"
BUNDLE_AUDIT="${BUNDLE_AUDIT:-${ROOT_DIR}/tools/r2-webview-trichrome-bundle-audit.py}"
INTEGRATION_PLAN="${INTEGRATION_PLAN:-${ROOT_DIR}/tools/r2-webview-integration-plan.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.31-webview-stock-near-noop"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-v0.31-webview-stock-near-noop"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}-exact-current.sparse.img"
EXPECTED_PRODUCT_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-${VARIANT}.img"
SOURCE_V029="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}-exact-current.SHA256SUMS.txt"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
STOCK_WEBVIEW_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/product/app/webview/webview.apk"
WEBVIEW_DIR="/app/webview"
WEBVIEW_APK="/app/webview/webview.apk"
WEBVIEW_DEVICE_DIR="/product/app/webview"
WEBVIEW_DEVICE_APK="/product/app/webview/webview.apk"
WEBVIEW_DIR_MTIME="0x6a344030"
WEBVIEW_DIR_MTIME_DEC="1781809200"
STOCK_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.31-webview-stock-near-noop.sh --offline-image
  tools/r2-verify-v0.31-webview-stock-near-noop.sh --read-only

--offline-image verifies the generated v0.31 sparse super:
  - only product_b is the intended patched partition
  - product_b slice in sparse matches the generated product image
  - source-retained partitions match v0.29 by logical sparse hash
  - /app/webview directory mtime is bumped for PackageCacher freshness
  - /app/webview/webview.apk remains byte-identical to stock
  - dumped WebView APK passes the WebView donor/provider static audit
  - dumped WebView APK passes the Trichrome/static-library bundle audit
  - WebView integration plan still reports zero build-ready donor candidates

--read-only verifies a flashed device without changing /data. It checks boot
state, WebView package path/hash, WebViewUpdateService state, package directory
mtime, and keyguard/launcher state.
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

verify_product_dir_mtime() {
  local image="$1"
  local path="$2"
  local expected="$3"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1)"
  grep -q "Type: directory" <<<"$output" || die "expected package directory: ${path}"
  grep -q "mtime: ${expected}:" <<<"$output" \
    || die "package directory mtime mismatch for ${path}; expected ${expected}"
  echo "product_dir_mtime=ok path=${path} mtime=${expected}"
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
for part in ["system_b", "system_ext_b", "vendor_b", "odm_b"]:
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
    check_manifest_hash "product_image" "$EXPECTED_PRODUCT_IMG" "product_b_sha256"
    check_manifest_hash "source_sparse" "$SOURCE_V029" "source_sparse_super_sha256"
    need_file "$STOCK_WEBVIEW_APK"
    [ "$(sha256_one "$STOCK_WEBVIEW_APK")" = "$STOCK_WEBVIEW_SHA256" ] \
      || die "stock WebView APK hash mismatch"
    echo "stock_webview_sha256=${STOCK_WEBVIEW_SHA256}"
    echo

    echo "## manifest gates"
    [ "$(manifest_value patched_partitions)" = "product_b" ] \
      || die "manifest patched_partitions is not product_b"
    [ "$(manifest_value webview_dir)" = "$WEBVIEW_DIR" ] \
      || die "manifest webview_dir mismatch"
    [ "$(manifest_value webview_apk)" = "$WEBVIEW_APK" ] \
      || die "manifest webview_apk mismatch"
    [ "$(manifest_value stock_webview_sha256)" = "$STOCK_WEBVIEW_SHA256" ] \
      || die "manifest stock_webview_sha256 mismatch"
    [ "$(manifest_value package_dir_mtime_hex)" = "$WEBVIEW_DIR_MTIME" ] \
      || die "manifest package_dir_mtime_hex mismatch"
    source_product="$(manifest_value source_product_b_sha256)"
    product="$(manifest_value product_b_sha256)"
    [ -n "$source_product" ] || die "manifest missing source_product_b_sha256"
    [ "$source_product" != "$product" ] \
      || die "product image hash did not change; expected mtime-only near-noop delta"
    echo "patched_partitions=product_b"
    echo "source_product_b_sha256=${source_product}"
    echo "product_b_sha256=${product}"
    echo

    echo "## product image gates"
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_IMG" >/dev/null
    verify_product_dir_mtime "$EXPECTED_PRODUCT_IMG" "$WEBVIEW_DIR" "$WEBVIEW_DIR_MTIME"
    dumped="${WORK_DIR}/offline-product-webview.apk"
    debugfs_dump "$EXPECTED_PRODUCT_IMG" "$WEBVIEW_APK" "$dumped"
    dumped_hash="$(sha256_one "$dumped")"
    [ "$dumped_hash" = "$STOCK_WEBVIEW_SHA256" ] \
      || die "dumped WebView APK hash mismatch: ${dumped_hash}"
    unzip -t "$dumped" >/dev/null
    echo "webview_apk_bytes=stock"
    echo "dumped_webview=${dumped}"
    echo "dumped_webview_sha256=${dumped_hash}"
    echo

    echo "## sparse slice gates"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" \
      --verify-image "product_b=${EXPECTED_PRODUCT_IMG}"
    echo

    echo "## retained partition gates"
    verify_retained_sparse_extents
    echo

	    echo "## WebView donor/provider static gate on dumped APK"
	    "$DONOR_AUDIT" "$dumped" --label "${VARIANT}-dumped-webview" >/tmp/r2-v031-donor-audit.out
	    cat /tmp/r2-v031-donor-audit.out
    donor_json="${ROOT_DIR}/hard-rom/inspect/browser-webview-donor/${VARIANT}-dumped-webview/webview-donor-audit.json"
    need_file "$donor_json"
    verdict="$(python3 - "$donor_json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["verdict"])
PY
)"
	    [ "$verdict" = "PASS" ] || die "dumped WebView donor audit did not PASS: ${verdict}"
	    echo "dumped_webview_donor_audit=PASS"
	    echo

	    echo "## WebView Trichrome/static-library bundle gate on dumped APK"
	    "$BUNDLE_AUDIT" "$dumped" --label "${VARIANT}-dumped-webview" >/tmp/r2-v031-bundle-audit.out
	    cat /tmp/r2-v031-bundle-audit.out
	    bundle_json="${ROOT_DIR}/hard-rom/inspect/browser-webview-trichrome-bundle/${VARIANT}-dumped-webview/trichrome-bundle-audit.json"
	    need_file "$bundle_json"
	    bundle_verdict="$(python3 - "$bundle_json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["verdict"])
PY
)"
	    [ "$bundle_verdict" = "PASS_STANDALONE" ] \
	      || die "dumped WebView bundle audit did not PASS_STANDALONE: ${bundle_verdict}"
	    echo "dumped_webview_bundle_audit=PASS_STANDALONE"
	    echo

	    echo "## WebView integration plan gate"
	    "$INTEGRATION_PLAN" >/tmp/r2-v031-integration-plan.out
	    cat /tmp/r2-v031-integration-plan.out
	    integration_json="${ROOT_DIR}/hard-rom/inspect/browser-webview-integration-plan/webview-integration-plan.json"
	    need_file "$integration_json"
	    build_ready="$(python3 - "$integration_json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
print(sum(1 for candidate in data.get("candidates", []) if candidate.get("build_readiness") == "READY_FOR_OFFLINE_IMAGE_DESIGN"))
PY
)"
	    [ "$build_ready" = "0" ] \
	      || die "integration plan unexpectedly reports build-ready candidates: ${build_ready}"
	    echo "webview_integration_plan_build_ready=0"
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

    echo "## WebView package path and hash"
    paths="$(adb_shell 'pm path com.android.webview 2>/dev/null | tr "\n" " " || true' | tail -n 1)"
    echo "pm_path=${paths}"
    grep -q "package:${WEBVIEW_DEVICE_APK}" <<<"$paths" \
      || die "com.android.webview is not loaded from ${WEBVIEW_DEVICE_APK}"
    live_hash="$(adb_shell "sha256sum ${WEBVIEW_DEVICE_APK} 2>/dev/null | cut -d ' ' -f 1" | tail -n 1)"
    [ "$live_hash" = "$STOCK_WEBVIEW_SHA256" ] \
      || die "live WebView APK hash mismatch: ${live_hash}"
    echo "live_webview_sha256=${live_hash}"
    live_mtime="$(adb_shell "stat -c %Y ${WEBVIEW_DEVICE_DIR} 2>/dev/null || true" | tail -n 1)"
    echo "live_webview_dir_mtime_epoch=${live_mtime}"
    [ "$live_mtime" = "$WEBVIEW_DIR_MTIME_DEC" ] \
      || die "live WebView directory mtime mismatch: ${live_mtime} != ${WEBVIEW_DIR_MTIME_DEC}"
    echo

    echo "## WebViewUpdateService"
    adb_shell 'cmd webviewupdate getCurrentWebViewPackage 2>/dev/null || true;
dumpsys webviewupdate 2>/dev/null | sed -n "1,220p" || true'
    adb_shell 'dumpsys webviewupdate 2>/dev/null' | grep -q "com.android.webview" \
      || die "dumpsys webviewupdate does not mention com.android.webview"
    echo

    echo "## Settings selector and browser resolver"
    adb_shell 'settings get global webview_provider 2>/dev/null || true;
cmd package resolve-activity --brief \
  -a android.settings.WEBVIEW_SETTINGS 2>&1 | sed -n "1,80p" || true;
cmd package resolve-activity --brief \
  -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d https://example.com 2>&1 | sed -n "1,80p" || true'
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
	    need_executable "$DONOR_AUDIT"
	    need_executable "$BUNDLE_AUDIT"
	    need_executable "$INTEGRATION_PLAN"
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
