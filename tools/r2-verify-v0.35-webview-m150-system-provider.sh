#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
AAPT="${AAPT:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt}"
DONOR_AUDIT="${DONOR_AUDIT:-${ROOT_DIR}/tools/r2-webview-donor-audit.py}"
BUNDLE_AUDIT="${BUNDLE_AUDIT:-${ROOT_DIR}/tools/r2-webview-trichrome-bundle-audit.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.35-webview-m150-system-provider"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
EXPECTED_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-${VARIANT}.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024
DONOR_APK_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_PRODUCT_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
PRODUCT_WEBVIEW_APK="/app/webview/webview.apk"
PRODUCT_WEBVIEW_HELD="/app/webview/.webview.apk.smartisax-v035-stock-held"
PACKAGE_DIR_MTIME_HEX="0x6a363a70"
EXPECTED_WEBVIEW_VERSION="150.0.7871.28"
EXPECTED_WEBVIEW_VERSION_CODE="787102801"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.35-webview-m150-system-provider.sh --offline-image
  tools/r2-verify-v0.35-webview-m150-system-provider.sh --read-only

--offline-image verifies the v0.35 candidate images without touching a device:
  - local sparse/system/product hashes match the manifest
  - system_b contains exactly the M150 stock-carrier WebView APK under /system
  - product_b no longer exposes /app/webview/webview.apk and keeps a held stock
    non-.apk copy for shared-block safety
  - system/product AVB footers retain FEC roots=2
  - the dumped system WebView passes Route A donor and standalone bundle audits

--read-only verifies a flashed device without changing /data:
  - boot completed on B slot, root available
  - PackageManager path for com.android.webview is /system/app/webview/webview.apk
  - product WebView APK is absent, BrowserChrome hash remains stock
  - WebViewUpdateService sees the M150 provider and relro state is clean
  - keyguard hidden and launcher focused
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

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

verify_dir_mtime() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1)"
  grep -q "Type: directory" <<<"$output" || die "expected directory: ${path}"
  grep -q "mtime: ${PACKAGE_DIR_MTIME_HEX}:" <<<"$output" \
    || die "directory mtime mismatch for ${path}"
  echo "dir_mtime=ok path=${path} mtime=${PACKAGE_DIR_MTIME_HEX}"
}

verify_avb_fec() {
  local label="$1"
  local image="$2"
  local partition_size="$3"
  local original_size="$4"
  local info="${WORK_DIR}/${label}-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${partition_size} bytes" "$info" \
    || die "${label} AVB image size mismatch"
  grep -q "Original image size:      ${original_size} bytes" "$info" \
    || die "${label} AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "${label} lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "${label} missing FEC offset"
  echo "${label}_avb_fec=ok"
}

verify_aapt_identity() {
  local apk="$1"
  local badging
  badging="$("$AAPT" dump badging "$apk")"
  grep -q "package: name='com.android.webview'" <<<"$badging" || die "WebView package name mismatch"
  grep -q "versionName='${EXPECTED_WEBVIEW_VERSION}'" <<<"$badging" || die "WebView versionName mismatch"
  grep -q "versionCode='${EXPECTED_WEBVIEW_VERSION_CODE}'" <<<"$badging" || die "WebView versionCode mismatch"
  grep -q "sdkVersion:'" <<<"$badging" || die "missing sdkVersion"
  echo "aapt_identity=ok package=com.android.webview version=${EXPECTED_WEBVIEW_VERSION} versionCode=${EXPECTED_WEBVIEW_VERSION_CODE}"
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
    check_manifest_hash "system_b_image" "$EXPECTED_SYSTEM_B_IMG" "system_b_sha256"
    check_manifest_hash "product_b_image" "$EXPECTED_PRODUCT_B_IMG" "product_b_sha256"
    [ "$(manifest_value patched_partitions)" = "system_b,product_b" ] \
      || die "patched_partitions mismatch"
    [ "$(manifest_value donor_apk_sha256)" = "$DONOR_APK_SHA256" ] \
      || die "donor_apk_sha256 mismatch"
    echo

    echo "## system_b gates"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] \
      || die "system_b size mismatch"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    verify_avb_fec system_b "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE" "$SYSTEM_B_EXT4_SIZE"
    verify_dir_mtime "$EXPECTED_SYSTEM_B_IMG" "/system/app/webview"
    system_dump="${WORK_DIR}/system-webview-dumped.apk"
    debugfs_dump "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$system_dump"
    [ "$(sha256_one "$system_dump")" = "$DONOR_APK_SHA256" ] \
      || die "system WebView APK hash mismatch"
    unzip -t "$system_dump" >/dev/null
    verify_aapt_identity "$system_dump"
    free_blocks="$(debugfs_stat_value "$EXPECTED_SYSTEM_B_IMG" "Free blocks")"
    echo "system_b_free_blocks_after_webview=${free_blocks}"
    echo

    echo "## product_b gates"
    [ "$(size_bytes "$EXPECTED_PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] \
      || die "product_b size mismatch"
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec product_b "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE" "$PRODUCT_B_EXT4_SIZE"
    verify_dir_mtime "$EXPECTED_PRODUCT_B_IMG" "/app/webview"
    ! debugfs_path_exists "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_APK" \
      || die "product WebView public APK is still scan-visible"
    debugfs_path_exists "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_HELD" \
      || die "product WebView held path is missing"
    product_dump="${WORK_DIR}/product-webview-held-dumped.apk"
    debugfs_dump "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_WEBVIEW_HELD" "$product_dump"
    [ "$(sha256_one "$product_dump")" = "$STOCK_PRODUCT_WEBVIEW_SHA256" ] \
      || die "held product WebView hash mismatch"
    unzip -t "$product_dump" >/dev/null
    echo "product_public_webview=absent"
    echo "product_stock_webview_held=ok"
    echo

    echo "## donor/provider static audits"
    "$DONOR_AUDIT" "$system_dump" --label "${VARIANT}-dumped-system-webview" >/tmp/r2-v035-donor-audit.out
    cat /tmp/r2-v035-donor-audit.out
    donor_json="$(awk -F= '$1 == "json" {print $2}' /tmp/r2-v035-donor-audit.out | tail -n 1)"
    donor_json="${ROOT_DIR}/${donor_json}"
    need_file "$donor_json"
    donor_verdict="$(python3 - "$donor_json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["verdict"])
PY
)"
    [ "$donor_verdict" = "PASS" ] || die "donor audit did not PASS: ${donor_verdict}"
    "$BUNDLE_AUDIT" "$system_dump" --label "${VARIANT}-dumped-system-webview" >/tmp/r2-v035-bundle-audit.out
    cat /tmp/r2-v035-bundle-audit.out
    bundle_json="$(awk -F= '$1 == "json" {print $2}' /tmp/r2-v035-bundle-audit.out | tail -n 1)"
    bundle_json="${ROOT_DIR}/${bundle_json}"
    need_file "$bundle_json"
    bundle_verdict="$(python3 - "$bundle_json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["verdict"])
PY
)"
    [ "$bundle_verdict" = "PASS_STANDALONE" ] \
      || die "bundle audit did not PASS_STANDALONE: ${bundle_verdict}"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V035_WEBVIEW_SYSTEM_PROVIDER"
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
    product_public="$(root_cmd 'test -e /product/app/webview/webview.apk && echo present || echo absent' | tail -n 1)"
    [ "$product_public" = "absent" ] || die "product WebView public APK is still present"
    echo "product_public_webview=${product_public}"
    echo

    echo "## hashes"
    hash_output="$(adb_shell 'sha256sum /system/app/webview/webview.apk /system/app/BrowserChrome/BrowserChrome.apk 2>/dev/null')"
    echo "$hash_output"
    grep -q "^${DONOR_APK_SHA256}  /system/app/webview/webview.apk" <<<"$hash_output" \
      || die "live system WebView hash mismatch"
    grep -q "^${STOCK_BROWSERCHROME_SHA256}  /system/app/BrowserChrome/BrowserChrome.apk" <<<"$hash_output" \
      || die "live BrowserChrome hash mismatch"
    echo

    echo "## package dump"
    adb_shell 'dumpsys package com.android.webview | sed -n "1,140p"'
    adb_shell 'dumpsys package com.android.webview | grep -E "versionCode|versionName|codePath|resourcePath|nativeLibraryDir|primaryCpuAbi|secondaryCpuAbi" | head -n 40'
    echo

    echo "## WebViewUpdateService"
    adb_shell 'cmd webviewupdate get-current-webview-package || true'
    adb_shell 'dumpsys webviewupdate | sed -n "1,120p"'
    adb_shell 'dumpsys webviewupdate' | grep -q "com.android.webview" \
      || die "WebViewUpdateService does not list com.android.webview"
    adb_shell 'dumpsys webviewupdate' | grep -Eq "150\\.0\\.7871\\.28|787102801" \
      || die "WebViewUpdateService does not expose the M150 provider"
    echo

    echo "## window state"
    window_output="$(adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head -n 20")"
    echo "$window_output"
    grep -q 'isKeyguardShowing=false' <<<"$window_output" \
      || die "keyguard is still showing"
    grep -Eq 'smt_launcher|com\.smartisanos\.launcher/\.Launcher' <<<"$window_output" \
      || die "launcher is not focused"
    echo

    echo "result=PASS_READ_ONLY_V035_WEBVIEW_SYSTEM_PROVIDER"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$DEBUGFS"
    need_executable "$E2FSCK"
    need_file "$AVBTOOL"
    need_executable "$AAPT"
    need_executable "$DONOR_AUDIT"
    need_executable "$BUNDLE_AUDIT"
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
