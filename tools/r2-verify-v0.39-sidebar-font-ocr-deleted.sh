#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

VARIANT="${VARIANT:-v0.39-sidebar-font-ocr-deleted}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
EXPECTED_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024

SIDEBAR_PATH="/system/priv-app/Sidebar/Sidebar.apk"
TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.39-sidebar-font-ocr-deleted.sh --offline-image
  tools/r2-verify-v0.39-sidebar-font-ocr-deleted.sh --read-only

Verifies the v0.39 Sidebar font OCR code-deleted candidate. --offline-image
does not touch a device. --read-only collects live state only: it does not
flash, reboot, write settings, clear package cache, or modify /data.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1" path="$2" key="$3" expected actual
  need_file "$MANIFEST"
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_path_exists() {
  local image="$1" path="$2" output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1" src="$2" dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

verify_avb_fec() {
  local label="$1" image="$2" partition_size="$3" ext4_size="$4" info
  info="${WORK_DIR}/${label}-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${partition_size} bytes" "$info" || die "${label} AVB image size mismatch"
  grep -q "Original image size:      ${ext4_size} bytes" "$info" || die "${label} AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "${label} lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "${label} missing FEC offset"
  echo "${label}_avb_fec=ok"
}

verify_apk_hash() {
  local image="$1" path="$2" key="$3" label="$4" expected out
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  out="${WORK_DIR}/${label}.apk"
  debugfs_dump "$image" "$path" "$out"
  [ "$(sha256_one "$out")" = "$expected" ] || die "${label} hash mismatch"
  unzip -t "$out" >/dev/null || die "${label} zip integrity failed"
  printf '%s\tsha256=%s\t%s\n' "$label" "$expected" "$path"
}

verify_sidebar_semantics() {
  local apk="$1" decoded="${WORK_DIR}/sidebar-decoded" sig="${WORK_DIR}/sidebar-signature.txt"
  rm -rf "$decoded"
  "$SIGCHECK" "$apk" > "$sig"
  grep -q '^apk_sig_block_magic=present$' "$sig" || die "Sidebar copied v2/v3 signing block missing"
  grep -q '^keytool_status=1$' "$sig" || die "Sidebar expected digest-boundary keytool status changed"
  grep -q 'SHA-256 digest error for classes.dex' "$sig" || die "Sidebar signature boundary did not point at classes.dex"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$decoded" "$apk" >/dev/null
  python3 - "$decoded" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
manifest_path = root / "AndroidManifest.xml"
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]

def full_component(package_name: str, raw: str) -> str:
    if raw.startswith("."):
        return package_name + raw
    if "." not in raw:
        return package_name + "." + raw
    return raw

manifest = ET.parse(manifest_path).getroot()
package_name = manifest.attrib.get("package")
if package_name != "com.smartisanos.sidebar":
    raise SystemExit("package mismatch")
application = next((child for child in manifest if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("manifest has no application")
components = [
    full_component(package_name, child.attrib.get(NAME, ""))
    for child in application
    if local(child.tag) in {"activity", "service", "provider", "receiver"}
]
for component in (
    "com.smartisanos.sidebar.open.font.BoomFontActivity",
    "com.smartisanos.sidebar.open.font.FontResultActivity",
):
    if component in components:
        raise SystemExit(f"{component} still declared")

manifest_text = manifest_path.read_text(encoding="utf-8", errors="replace")
for token in ("BoomFontActivity", "FontResultActivity", "ocr_key", "smartisanos.intent.action.BOOM_FONT"):
    if token in manifest_text:
        raise SystemExit(f"manifest still contains {token}")

for path in (
    root / "smali/com/smartisanos/sidebar/open/font",
    root / "smali/com/intsig/csopen",
    root / "smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView.smali",
):
    if path.exists():
        raise SystemExit(f"deleted path still present: {path.relative_to(root)}")

for path in (root / "smali/com/smartisanos/sidebar").rglob("*.smali"):
    text = path.read_text(encoding="utf-8", errors="replace")
    for token in (
        "Lcom/smartisanos/sidebar/open/font/",
        "Lcom/intsig/csopen/",
        "IdentifyFontView",
        "smartisanos.intent.action.BOOM_FONT",
        "qiuziti.com",
        "OCRhelper",
        "CSOpenAPI",
    ):
        if token in text:
            raise SystemExit(f"{path.relative_to(root)} still contains {token}")

adapter_layouts = root / "smali/com/smartisanos/sidebar/toparea/view/ToolButtonAdapter$6.smali"
if "0x7f090065" in adapter_layouts.read_text(encoding="utf-8", errors="replace"):
    raise SystemExit("ToolButtonAdapter still maps type=1 to tool_button_item_identify_font")

print("sidebar_font_ocr_code_deleted=ok")
PY
}

verify_offline_image() {
  local ts report sidebar_dump
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-${ts}.txt"
  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  rm -rf "${WORK_DIR:?}"/*
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
  {
    echo "# ${VARIANT} offline verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=read-only offline verifier; no device access"
    echo
    echo "## hashes"
    check_manifest_hash "sparse_super" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "system_b" "$EXPECTED_SYSTEM_B_IMG" "system_b_sha256"
    check_manifest_hash "product_b" "$EXPECTED_PRODUCT_B_IMG" "product_b_sha256"
    check_manifest_hash "sidebar_apk" "$(manifest_value sidebar_apk)" "sidebar_apk_sha256"
    echo
    echo "## image sizes and FEC"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b size mismatch"
    [ "$(size_bytes "$EXPECTED_PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] || die "product_b size mismatch"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec system_b "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE" "$SYSTEM_B_EXT4_SIZE"
    verify_avb_fec product_b "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE" "$PRODUCT_B_EXT4_SIZE"
    echo
    echo "## APK retention and Sidebar semantics"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$SIDEBAR_PATH" "sidebar_apk_sha256" "sidebar"
    sidebar_dump="${WORK_DIR}/sidebar.apk"
    verify_sidebar_semantics "$sidebar_dump"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_PATH" "textboom_apk_sha256" "textboom"
    debugfs_path_exists "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_LIB_ARM_DIR" || die "TextBoom lib/arm missing"
    echo "textboom_lib_arm_retained=ok"
    echo
    echo "result=PASS_OFFLINE_IMAGE_V039_SIDEBAR_FONT_OCR_DELETED"
  } > "$report"
  cat "$report"
  echo "Report: $report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL:-bb12d264} device$"
}

adb_shell() {
  adb -s "${SERIAL:-bb12d264}" shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}" cmd "$@" 2>&1 | tr -d '\r'
}

live_sha256() {
  local path="$1"
  root_cmd "sha256sum ${path} 2>/dev/null || toybox sha256sum ${path} 2>/dev/null" | awk '{print $1}' | sed -n '1p'
}

require_live_hash() {
  local label="$1" path="$2" key="$3" expected actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  actual="$(live_sha256 "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected} path=${path}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_read_only_device() {
  local ts report slot boot bootanim keyguard_line sidebar_action sidebar_launcher sidebar_windows sidebar_services sidebar_provider_count textboom_path webview_path browser_path smartisax_path root_id
  ts="$(date '+%Y%m%d-%H%M%S')"
  report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-${ts}.txt"
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  {
    echo "# ${VARIANT} live read-only verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=read-only live verifier; no flash, no reboot, no settings write, no package mutation, no /data cleanup"
    echo
    echo "## adb"
    adb devices -l | tr -d '\r'
    adb_available || die "adb device ${SERIAL:-bb12d264} is not online"
    echo
    echo "## boot and root"
    boot="$(adb_shell 'getprop sys.boot_completed' | tail -n 1)"
    slot="$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)"
    bootanim="$(adb_shell 'getprop init.svc.bootanim' | tail -n 1)"
    printf 'sys.boot_completed=%s\n' "$boot"
    printf 'ro.boot.slot_suffix=%s\n' "$slot"
    printf 'init.svc.bootanim=%s\n' "$bootanim"
    [ "$boot" = "1" ] || die "boot not completed"
    [ "$slot" = "_b" ] || die "unexpected slot: ${slot}"
    root_id="$(root_cmd 'id; getenforce; getprop ro.boot.slot_suffix' || true)"
    printf '%s\n' "$root_id"
    grep -q 'uid=0(root)' <<<"$root_id" || die "root uid=0 missing"
    echo
    echo "## package paths"
    adb_shell 'for pkg in com.smartisanos.sidebar com.smartisanos.textboom com.android.webview com.android.browser com.smartisax.browser; do
      echo "### ${pkg}"
      pm path "$pkg" 2>/dev/null || true
      dumpsys package "$pkg" 2>/dev/null | grep -E "Package \\[|versionCode=|versionName=|codePath=|resourcePath=|pkgFlags=|privateFlags=|sharedUserId=|enabled=|stopped=|hidden=|suspended=|firstInstallTime=|lastUpdateTime=|UPDATED_SYSTEM_APP" | sed -n "1,80p"
    done'
    sidebar_provider_count="$(adb_shell 'dumpsys package com.smartisanos.sidebar 2>/dev/null | grep -c "Provider{" || true' | tail -n 1)"
    printf 'sidebar_provider_count=%s\n' "$sidebar_provider_count"
    [ "${sidebar_provider_count:-0}" -ge 1 ] || die "Sidebar providers missing"
    textboom_path="$(adb_shell 'pm path com.smartisanos.textboom 2>/dev/null | tr "\n" " "' | tail -n 1)"
    webview_path="$(adb_shell 'pm path com.android.webview 2>/dev/null | tr "\n" " "' | tail -n 1)"
    browser_path="$(adb_shell 'pm path com.android.browser 2>/dev/null | tr "\n" " "' | tail -n 1)"
    smartisax_path="$(adb_shell 'pm path com.smartisax.browser 2>/dev/null | tr "\n" " "' | tail -n 1)"
    [[ "$textboom_path" == *"/system/app/TextBoom/TextBoom.apk"* ]] || die "TextBoom not served from system"
    [[ "$webview_path" == *"/system/app/webview/webview.apk"* ]] || die "WebView not served from system"
    [[ "$browser_path" == *"/system/app/BrowserChrome/BrowserChrome.apk"* ]] || die "BrowserChrome path missing"
    [[ "$smartisax_path" == *"/system/app/SmartisaxShell/SmartisaxShell.apk"* ]] || die "Smartisax path missing"
    echo
    echo "## live hashes"
    require_live_hash "sidebar" "/system/priv-app/Sidebar/Sidebar.apk" "sidebar_apk_sha256"
    require_live_hash "textboom" "$TEXTBOOM_PATH" "textboom_apk_sha256"
    echo
    echo "## Sidebar font OCR absence"
    sidebar_action="$(adb_shell 'cmd package resolve-activity --brief -a smartisanos.intent.action.BOOM_FONT 2>&1 || true')"
    printf '%s\n' "$sidebar_action"
    if ! grep -Eq 'No activity found|No activities found|unable to resolve|^$' <<<"$sidebar_action"; then
      die "BOOM_FONT still resolves"
    fi
    sidebar_launcher="$(adb_shell 'cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.smartisanos.sidebar 2>&1 || true')"
    printf '%s\n' "$sidebar_launcher" | sed -n '1,80p'
    if ! grep -Eq 'No activities found|No activity found|^$' <<<"$sidebar_launcher"; then
      die "Sidebar launcher entry unexpectedly present"
    fi
    echo
    echo "## Sidebar runtime"
    sidebar_services="$(adb_shell 'dumpsys activity services com.smartisanos.sidebar 2>/dev/null | grep -E "ServiceRecord|com.smartisanos.sidebar" | sed -n "1,80p" || true')"
    printf '%s\n' "$sidebar_services"
    grep -q 'com.smartisanos.sidebar' <<<"$sidebar_services" || die "Sidebar service state missing"
    sidebar_windows="$(adb_shell 'dumpsys window windows 2>/dev/null | grep -Ei "sidebar|smartisanos.sidebar|one.?step|side_bar" | sed -n "1,120p" || true')"
    printf '%s\n' "$sidebar_windows"
    if [ -z "$sidebar_windows" ]; then
      echo "WARN: Sidebar windows not currently visible; manual corner-swipe check may still be needed"
    fi
    keyguard_line="$(adb_shell 'dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen" | sed -n "1,80p" || true')"
    printf '%s\n' "$keyguard_line"
    if grep -Eq 'isKeyguardShowing=true|mShowingLockscreen=true' <<<"$keyguard_line"; then
      die "keyguard still showing"
    fi
    echo
    echo "## retained TextBoom/WebView contracts"
    adb_shell 'ls -ldZ /system/app/TextBoom/lib/arm /system/app/webview /system/app/BrowserChrome /system/app/SmartisaxShell 2>/dev/null || true'
    adb_shell 'cmd webviewupdate getCurrentWebViewPackage 2>/dev/null || true; dumpsys webviewupdate 2>/dev/null | grep -E "Current WebView package|versionName|versionCode|relro|dirty|valid|com.android.webview" | sed -n "1,120p" || true'
    echo
    echo "result=PASS_READ_ONLY_V039_SIDEBAR_FONT_OCR_DELETED"
  } > "$report"
  cat "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) ;;
  --read-only) mode="read-only" ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_file "$AVBTOOL"
if [ "${mode:-offline}" = "read-only" ]; then
  need_file "$MANIFEST"
  verify_read_only_device
else
  need_executable "$DEBUGFS"
  need_executable "$E2FSCK"
  need_executable "$JAVA_BIN"
  need_file "$APKTOOL"
  need_file "$FW_ANDROID"
  need_file "$FW_SMARTISAN"
  need_executable "$SIGCHECK"
  verify_offline_image
fi
