#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.35.2-webview-m150-clean-product-residue"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-${VARIANT}.img"
SOURCE_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.35.1-webview-m150-browserchrome-deodex.img"

PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024
SUPER_SIZE=10737418240
DONOR_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
SOURCE_SYSTEM_B_SHA256="fd906f64df8859d6da6ec3752849cb1813802a880a801a9c6f764400679ca795"
EXPECTED_WEBVIEW_VERSION="150.0.7871.28"

SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSERCHROME_OAT_DIR="/system/app/BrowserChrome/oat"
PRODUCT_WEBVIEW_DIR="/app/webview"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh --offline-image
  tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh --read-only

--offline-image verifies the v0.35.2 candidate without touching a device:
  - sparse and product_b hashes match the manifest
  - product_b no longer contains /app/webview, hidden stock WebView backup, or
    stale oat/vdex files
  - product_b AVB footer has FEC roots=2
  - product_b sparse slice matches the generated image
  - retained v0.35.1 system_b still contains M150 WebView and no BrowserChrome oat

--read-only verifies a flashed device without changing /data:
  - boot completed on B slot, root available
  - com.android.webview is served from /system/app/webview/webview.apk
  - /product/app/webview and BrowserChrome oat paths are absent
  - WebViewUpdateService selects M150 and relro state is clean
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
  local expected
  local actual
  need_file "$MANIFEST"
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

verify_avb_fec() {
  local image="$1"
  local info="${WORK_DIR}/product-b-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${PRODUCT_B_PARTITION_SIZE} bytes" "$info" \
    || die "product_b AVB image size mismatch"
  grep -q "Original image size:      ${PRODUCT_B_EXT4_SIZE} bytes" "$info" \
    || die "product_b AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "product_b lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "product_b missing FEC offset"
  echo "product_b_avb_fec=ok"
}

verify_sparse_product_slice() {
  local raw="${WORK_DIR}/candidate-super.raw.img"
  local extract_dir="${WORK_DIR}/candidate-super-extract"
  local extracted="${extract_dir}/product_b.img"
  rm -f "$raw"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  "$SIMG2IMG" "$EXPECTED_SPARSE" "$raw"
  [ "$(size_bytes "$raw")" -eq "$SUPER_SIZE" ] || die "candidate raw super size mismatch"
  "$LPUNPACK" --slot=1 --partition=product_b "$raw" "$extract_dir" >/dev/null
  rm -f "$raw"
  need_file "$extracted"
  [ "$(size_bytes "$extracted")" -eq "$PRODUCT_B_PARTITION_SIZE" ] \
    || die "extracted product_b size mismatch"
  local image_hash
  local slice_hash
  image_hash="$(sha256_one "$EXPECTED_PRODUCT_B_IMG")"
  slice_hash="$(sha256_one "$extracted")"
  [ "$slice_hash" = "$image_hash" ] \
    || die "product_b sparse slice hash mismatch: ${slice_hash} != ${image_hash}"
  echo "product_b_sparse_slice=ok sha256=${slice_hash}"
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

run_offline_image() {
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## local files"
    check_manifest_hash "candidate_sparse" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "product_b_image" "$EXPECTED_PRODUCT_B_IMG" "product_b_sha256"
    need_file "$SOURCE_SYSTEM_B_IMG"
    [ "$(sha256_one "$SOURCE_SYSTEM_B_IMG")" = "$SOURCE_SYSTEM_B_SHA256" ] \
      || die "retained source system_b hash mismatch"
    [ "$(manifest_value patched_partitions)" = "product_b" ] \
      || die "patched_partitions mismatch"
    [ "$(manifest_value product_webview_dir_absent_after_fsck)" = "yes" ] \
      || die "manifest does not record product WebView absence"
    echo "source_system_b_retained=ok sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo

    echo "## retained system_b gates"
    system_webview_dump="${WORK_DIR}/system-webview-dumped.apk"
    debugfs_dump "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$system_webview_dump"
    [ "$(sha256_one "$system_webview_dump")" = "$DONOR_WEBVIEW_SHA256" ] \
      || die "retained system WebView hash mismatch"
    browser_dump="${WORK_DIR}/browserchrome-dumped.apk"
    debugfs_dump "$SOURCE_SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$browser_dump"
    [ "$(sha256_one "$browser_dump")" = "$STOCK_BROWSERCHROME_SHA256" ] \
      || die "retained BrowserChrome hash mismatch"
    ! debugfs_path_exists "$SOURCE_SYSTEM_B_IMG" "$BROWSERCHROME_OAT_DIR" \
      || die "retained BrowserChrome oat dir exists"
    echo "retained_system_webview=ok"
    echo "retained_browserchrome_oat_absent=ok"
    echo

    echo "## product_b cleanup gates"
    [ "$(size_bytes "$EXPECTED_PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] \
      || die "product_b size mismatch"
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec "$EXPECTED_PRODUCT_B_IMG"
    ! debugfs_path_exists "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_DIR" \
      || die "product WebView directory still exists in product_b"
    verify_sparse_product_slice
    echo "product_webview_dir=absent"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN"
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

    echo "## root"
    "$ROOT_HELPER" status
    echo

    echo "## package paths"
    adb_shell 'cmd package path com.android.webview || true'
    webview_path="$(adb_shell 'cmd package path com.android.webview || true' | tail -n 1)"
    grep -q '/system/app/webview/webview.apk' <<<"$webview_path" \
      || die "com.android.webview is not served from /system/app/webview"
    product_webview_dir="$(root_cmd 'test -e /product/app/webview && echo present || echo absent' | tail -n 1)"
    [ "$product_webview_dir" = "absent" ] || die "/product/app/webview still exists"
    browser_oat="$(root_cmd 'test -e /system/app/BrowserChrome/oat && echo present || echo absent' | tail -n 1)"
    [ "$browser_oat" = "absent" ] || die "BrowserChrome oat dir still exists"
    echo "product_webview_dir=${product_webview_dir}"
    echo "browserchrome_oat=${browser_oat}"
    echo

    echo "## hashes"
    hash_output="$(adb_shell 'sha256sum /system/app/webview/webview.apk /system/app/BrowserChrome/BrowserChrome.apk 2>/dev/null')"
    echo "$hash_output"
    grep -q "^${DONOR_WEBVIEW_SHA256}  /system/app/webview/webview.apk" <<<"$hash_output" \
      || die "live system WebView hash mismatch"
    grep -q "^${STOCK_BROWSERCHROME_SHA256}  /system/app/BrowserChrome/BrowserChrome.apk" <<<"$hash_output" \
      || die "live BrowserChrome hash mismatch"
    echo

    echo "## WebViewUpdateService"
    adb_shell 'dumpsys webviewupdate | sed -n "1,120p"'
    adb_shell 'dumpsys webviewupdate' | grep -q "com.android.webview" \
      || die "WebViewUpdateService does not list com.android.webview"
    adb_shell 'dumpsys webviewupdate' | grep -q "$EXPECTED_WEBVIEW_VERSION" \
      || die "WebViewUpdateService does not expose M150"
    adb_shell 'dumpsys webviewupdate' | grep -q "Number of relros finished: 2" \
      || die "WebView relro did not finish"
    adb_shell 'dumpsys webviewupdate' | grep -q "WebView package dirty: false" \
      || die "WebView package is dirty"
    echo

    echo "## window state"
    window_output="$(adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head -n 20")"
    echo "$window_output"
    grep -q 'isKeyguardShowing=false' <<<"$window_output" \
      || die "keyguard is still showing"
    echo

    echo "result=PASS_READ_ONLY_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$DEBUGFS"
    need_executable "$E2FSCK"
    need_file "$AVBTOOL"
    need_executable "$SIMG2IMG"
    need_executable "$LPUNPACK"
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
