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

VARIANT="${VARIANT:-v0.38-sidebar-font-ocr-disabled}"
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
  tools/r2-verify-v0.38-sidebar-font-ocr-disabled.sh --offline-image

Verifies the v0.38 Sidebar font OCR disabled candidate without touching a
device. It does not flash, reboot, write settings, clear package cache, or
modify /data.
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
  python3 - "$decoded/AndroidManifest.xml" "$decoded/res/layout/tool_button_item_identify_font.xml" \
    "$decoded/smali/com/smartisanos/sidebar/open/font/FontUtils.smali" \
    "$decoded/smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView.smali" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

manifest_path, layout_path, font_utils_path, identify_path = map(Path, sys.argv[1:5])
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
ENABLED = f"{{{ANDROID_NS}}}enabled"
ATTR = lambda name: f"{{{ANDROID_NS}}}{name}"

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
matches = [
    child for child in application
    if local(child.tag) == "activity"
    and full_component(package_name, child.attrib.get(NAME, "")) == "com.smartisanos.sidebar.open.font.BoomFontActivity"
]
if len(matches) != 1:
    raise SystemExit("BoomFontActivity count mismatch")
activity = matches[0]
if activity.attrib.get(ENABLED) != "false":
    raise SystemExit("BoomFontActivity not disabled")
for child in activity:
    if local(child.tag) == "intent-filter":
        for sub in child:
            if local(sub.tag) == "action" and sub.attrib.get(NAME) == "smartisanos.intent.action.BOOM_FONT":
                raise SystemExit("ACTION_BOOM_FONT still exposed")

layout = ET.parse(layout_path).getroot()
zero_dims = {"0dp", "0.0dp", "0dip", "0.0dip", "0px", "0.0px"}
if layout.attrib.get(ATTR("visibility")) != "gone":
    raise SystemExit("font button layout root is not gone")
if layout.attrib.get(ATTR("layout_width")) not in zero_dims or layout.attrib.get(ATTR("layout_height")) not in zero_dims:
    raise SystemExit("font button root dimensions are not zero")
layout_text = layout_path.read_text()
if "tool_button" not in layout_text or "IdentifyFontView" not in layout_text:
    raise SystemExit("tool_button IdentifyFontView not preserved")

font_utils = font_utils_path.read_text()
identify = identify_path.read_text()
if "->startActivity(Landroid/content/Intent;Landroid/os/Bundle;)V" in font_utils:
    raise SystemExit("FontUtils still starts activity")
if "FontUtils;->startOcrActivity" in identify:
    raise SystemExit("IdentifyFontView still calls startOcrActivity")
if "FontUtils;->exitOcrActivity" not in font_utils:
    raise SystemExit("toggleFont cleanup path missing")
print("sidebar_font_ocr_semantics=ok")
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
    echo "result=PASS_OFFLINE_IMAGE_V038_SIDEBAR_FONT_OCR_DISABLED"
  } > "$report"
  cat "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$JAVA_BIN"
need_file "$AVBTOOL"
need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_executable "$SIGCHECK"
verify_offline_image
