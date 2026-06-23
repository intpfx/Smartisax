#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
TOPBAR_BUILDER="${TOPBAR_BUILDER:-${ROOT_DIR}/tools/r2-build-sidebar-topbar-hide-apk.sh}"
V2_PRESERVER="${V2_PRESERVER:-${ROOT_DIR}/tools/r2-apk-preserve-v2-signing-block.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
SIDEBAR_STOCK_APK="${RAW}/system/system/priv-app/Sidebar/Sidebar.apk"

OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/sidebar-font-ocr-disabled-apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"

BASE_RAW_APK="${BASE_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-topbar-hidden.apk}"
BASE_V2_APK="${BASE_V2_APK:-${OUT_DIR}/com.smartisanos.sidebar-topbar-hidden-v2cert.apk}"
OUT_RAW_APK="${OUT_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-disabled.apk}"
OUT_V2_APK="${OUT_V2_APK:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-disabled-v2cert.apk}"
MANIFEST="${MANIFEST:-${OUT_DIR}/sidebar-font-ocr-disabled-apk-manifest.tsv}"
SIG_REPORT="${SIG_REPORT:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-disabled.signature.txt}"

FONT_BUTTON_LAYOUT="res/layout/tool_button_item_identify_font.xml"
PACKAGE_NAME="com.smartisanos.sidebar"
BOOM_FONT_ACTIVITY="com.smartisanos.sidebar.open.font.BoomFontActivity"
BOOM_FONT_ACTION="smartisanos.intent.action.BOOM_FONT"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-sidebar-font-ocr-disabled-apk.sh

Build a Sidebar APK candidate that retires the One Step font OCR feature while
keeping Sidebar identity and the existing launcher-entry/topbar patches. It:

  - hides res/layout/tool_button_item_identify_font.xml root
  - makes IdentifyFontView.onClick return immediately
  - makes FontUtils.startOcrActivity no-op
  - makes FontUtils.toggleFont cleanup-only
  - disables BoomFontActivity and removes ACTION_BOOM_FONT intent exposure

This script only builds and verifies an APK artifact. It does not build a super
image, touch a device, flash, reboot, erase partitions, or modify /data.
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

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

install_frameworks() {
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

patch_decoded_manifest() {
  local manifest_xml="$1"
  "$PYTHON_BIN" - "$manifest_xml" "$PACKAGE_NAME" "$BOOM_FONT_ACTIVITY" "$BOOM_FONT_ACTION" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
package_name, component, action_name = sys.argv[2:5]
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
ENABLED = f"{{{ANDROID_NS}}}enabled"
ET.register_namespace("android", ANDROID_NS)


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def full_component(raw: str) -> str:
    if raw.startswith("."):
        return package_name + raw
    if "." not in raw:
        return package_name + "." + raw
    return raw


def has_action(filter_node: ET.Element) -> bool:
    return any(
        local(child.tag) == "action" and child.attrib.get(NAME) == action_name
        for child in filter_node
    )


tree = ET.parse(path)
root = tree.getroot()
if root.attrib.get("package") != package_name:
    raise SystemExit(f"package mismatch: {root.attrib.get('package')} != {package_name}")
application = next((child for child in root if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("manifest has no application")
matches = [
    child
    for child in application
    if local(child.tag) == "activity" and full_component(child.attrib.get(NAME, "")) == component
]
if len(matches) != 1:
    raise SystemExit(f"expected one {component}, found {len(matches)}")
activity = matches[0]
activity.attrib[ENABLED] = "false"
removed = 0
for child in list(activity):
    if local(child.tag) == "intent-filter" and has_action(child):
        activity.remove(child)
        removed += 1
if removed != 1:
    raise SystemExit(f"expected to remove one {action_name} intent-filter, removed {removed}")
tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"disabled_activity={component}")
print(f"removed_action={action_name}")
PY
}

patch_layout_xml() {
  local xml="$1"
  "$PYTHON_BIN" - "$xml" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)
ATTR = lambda name: f"{{{ANDROID_NS}}}{name}"

tree = ET.parse(path)
root = tree.getroot()
if root.tag.rsplit("}", 1)[-1] != "FrameLayout":
    raise SystemExit(f"unexpected root tag: {root.tag}")
if not any(child.tag.rsplit("}", 1)[-1] == "RelativeLayout" for child in root):
    raise SystemExit("expected child RelativeLayout missing")
if "IdentifyFontView" not in path.read_text(encoding="utf-8", errors="replace"):
    raise SystemExit("IdentifyFontView missing before patch")
root.attrib[ATTR("visibility")] = "gone"
root.attrib[ATTR("layout_width")] = "0dp"
root.attrib[ATTR("layout_height")] = "0dp"
tree.write(path, encoding="utf-8", xml_declaration=True)
print("patched_font_button_layout=root_gone_width0_height0_tool_button_preserved")
PY
}

patch_smali() {
  local decoded_dir="$1"
  "$PYTHON_BIN" - "$decoded_dir" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
font_utils = root / "smali/com/smartisanos/sidebar/open/font/FontUtils.smali"
identify = root / "smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView.smali"


def replace_method(path: Path, signature: str, body: str) -> None:
    text = path.read_text()
    pattern = re.compile(
        rf"^\.method {re.escape(signature)}\n.*?^\.end method",
        re.MULTILINE | re.DOTALL,
    )
    out, count = pattern.subn(body.strip() + "\n", text, count=1)
    if count != 1:
        raise SystemExit(f"failed to replace {signature} in {path}")
    path.write_text(out)


replace_method(
    font_utils,
    "public static startOcrActivity(Landroid/content/Context;Z)V",
    """
.method public static startOcrActivity(Landroid/content/Context;Z)V
    .locals 0

    return-void
.end method
""",
)

replace_method(
    font_utils,
    "public static toggleFont(Landroid/content/Context;)V",
    """
.method public static toggleFont(Landroid/content/Context;)V
    .locals 1

    invoke-static {p0}, Lcom/smartisanos/sidebar/open/font/FontUtils;->isShowing(Landroid/content/Context;)Z

    move-result v0

    if-eqz v0, :cond_0

    invoke-static {p0}, Lcom/smartisanos/sidebar/open/font/FontUtils;->exitOcrActivity(Landroid/content/Context;)V

    :cond_0
    return-void
.end method
""",
)

replace_method(
    identify,
    "public onClick(Landroid/view/View;)V",
    """
.method public onClick(Landroid/view/View;)V
    .locals 0

    return-void
.end method
""",
)

for path in (font_utils, identify):
    text = path.read_text()
    if path == font_utils and "->startActivity(Landroid/content/Intent;Landroid/os/Bundle;)V" in text:
        raise SystemExit("FontUtils still starts an activity")
    if path == identify and "FontUtils;->startOcrActivity" in text:
        raise SystemExit("IdentifyFontView.onClick still reaches FontUtils.startOcrActivity")

print("patched_smali=font_ocr_launch_paths_inert")
PY
}

merge_members_into_shell() {
  local base_apk="$1"
  local rebuilt_apk="$2"
  local out_apk="$3"
  local tmp
  tmp="$(mktemp -d "/tmp/r2-sidebar-font-ocr.XXXXXX")"
  mkdir -p "${tmp}/res/layout"
  unzip -p "$rebuilt_apk" AndroidManifest.xml > "${tmp}/AndroidManifest.xml"
  unzip -p "$rebuilt_apk" classes.dex > "${tmp}/classes.dex"
  unzip -p "$rebuilt_apk" "$FONT_BUTTON_LAYOUT" > "${tmp}/${FONT_BUTTON_LAYOUT}"
  touch -t 200901010000 "${tmp}/AndroidManifest.xml"
  touch -t 200901010000 "${tmp}/classes.dex"
  touch -t 200901010000 "${tmp}/${FONT_BUTTON_LAYOUT}"
  cp "$base_apk" "${out_apk}.tmp"
  (
    cd "$tmp"
    zip -X -q "${out_apk}.tmp" AndroidManifest.xml classes.dex "$FONT_BUTTON_LAYOUT"
  )
  mv "${out_apk}.tmp" "$out_apk"
  rm -rf "$tmp"
}

verify_zip_scope() {
  local base_apk="$1"
  local out_apk="$2"
  "$PYTHON_BIN" - "$base_apk" "$out_apk" "$FONT_BUTTON_LAYOUT" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile

base, out, layout = sys.argv[1:]


def members(path: str) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as zf:
        return {info.filename: zf.read(info.filename) for info in zf.infolist() if not info.is_dir()}


base_members = members(base)
out_members = members(out)
if set(base_members) != set(out_members):
    raise SystemExit("zip member set changed")
changed = sorted(
    name
    for name in base_members
    if hashlib.sha256(base_members[name]).digest() != hashlib.sha256(out_members[name]).digest()
)
expected = {"AndroidManifest.xml", "classes.dex", layout}
if set(changed) != expected:
    raise SystemExit(f"unexpected changed members: {changed}")
print(f"changed_members={','.join(changed)}")
for name in changed:
    print(f"{name}_sha256={hashlib.sha256(out_members[name]).hexdigest()}")
PY
}

verify_decoded_output() {
  local apk="$1"
  local check_dir="$2"
  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/decoded" "$apk" >/dev/null
  "$PYTHON_BIN" - "${check_dir}/decoded/AndroidManifest.xml" "${check_dir}/decoded/${FONT_BUTTON_LAYOUT}" \
    "${check_dir}/decoded/smali/com/smartisanos/sidebar/open/font/FontUtils.smali" \
    "${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView.smali" <<'PY'
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
    raise SystemExit(f"package mismatch: {package_name}")
application = next((child for child in manifest if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("manifest has no application")
matches = [
    child
    for child in application
    if local(child.tag) == "activity"
    and full_component(package_name, child.attrib.get(NAME, "")) == "com.smartisanos.sidebar.open.font.BoomFontActivity"
]
if len(matches) != 1:
    raise SystemExit(f"BoomFontActivity count={len(matches)}")
activity = matches[0]
if activity.attrib.get(ENABLED) != "false":
    raise SystemExit("BoomFontActivity is not disabled")
for child in activity:
    if local(child.tag) != "intent-filter":
        continue
    for sub in child:
        if local(sub.tag) == "action" and sub.attrib.get(NAME) == "smartisanos.intent.action.BOOM_FONT":
            raise SystemExit("ACTION_BOOM_FONT still exposed")

layout = ET.parse(layout_path).getroot()
if layout.attrib.get(ATTR("visibility")) != "gone":
    raise SystemExit("font button layout root is not gone")
zero_dims = {"0dp", "0.0dp", "0dip", "0.0dip", "0px", "0.0px"}
if layout.attrib.get(ATTR("layout_width")) not in zero_dims or layout.attrib.get(ATTR("layout_height")) not in zero_dims:
    raise SystemExit("font button layout root dimensions are not 0dp")
layout_text = layout_path.read_text()
if "tool_button" not in layout_text or "IdentifyFontView" not in layout_text:
    raise SystemExit("tool_button IdentifyFontView was not preserved")

font_utils = font_utils_path.read_text()
identify = identify_path.read_text()
if "->startActivity(Landroid/content/Intent;Landroid/os/Bundle;)V" in font_utils:
    raise SystemExit("FontUtils still starts activity")
if "FontUtils;->startOcrActivity" in identify:
    raise SystemExit("IdentifyFontView still calls startOcrActivity")
if "public static toggleFont(Landroid/content/Context;)V" not in font_utils:
    raise SystemExit("toggleFont missing")
if "FontUtils;->exitOcrActivity" not in font_utils:
    raise SystemExit("toggleFont cleanup path missing")

print("boom_font_activity_disabled=ok")
print("action_boom_font_removed=ok")
print("font_button_layout_hidden=ok")
print("font_launch_smali_inert=ok")
PY
}

case "${1:-}" in
  "")
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

need_file "$JAVA_BIN"
need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$SIDEBAR_STOCK_APK"
need_executable "$TOPBAR_BUILDER"
need_executable "$V2_PRESERVER"
need_executable "$SIGCHECK"
need_command "$PYTHON_BIN"
need_command zip
need_command unzip

mkdir -p "$OUT_DIR" "$WORK_DIR"

if [ ! -f "$BASE_RAW_APK" ] || [ ! -f "$BASE_V2_APK" ]; then
  echo "Building Sidebar topbar-hidden base APKs first..."
  "$TOPBAR_BUILDER" >/dev/null
fi

need_file "$BASE_RAW_APK"
need_file "$BASE_V2_APK"

rm -rf "${WORK_DIR}/decoded" "${WORK_DIR}/check" "${WORK_DIR}/rebuilt.apk"
rm -f "$OUT_RAW_APK" "$OUT_V2_APK" "$MANIFEST" "$SIG_REPORT"

install_frameworks

echo "Decoding Sidebar topbar-hidden base APK..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${WORK_DIR}/decoded" "$BASE_RAW_APK" >/dev/null

echo "Patching BoomFontActivity manifest contract..."
patch_decoded_manifest "${WORK_DIR}/decoded/AndroidManifest.xml" > "${WORK_DIR}/manifest-patch-report.txt"

echo "Hiding One Step font OCR tool-button layout..."
patch_layout_xml "${WORK_DIR}/decoded/${FONT_BUTTON_LAYOUT}" > "${WORK_DIR}/layout-patch-report.txt"

echo "Patching font OCR smali launch paths..."
patch_smali "${WORK_DIR}/decoded" > "${WORK_DIR}/smali-patch-report.txt"

echo "Rebuilding patched Sidebar APK carrier..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "${WORK_DIR}/rebuilt.apk" "${WORK_DIR}/decoded" >/dev/null

echo "Merging patched manifest/classes/layout into topbar-hidden APK shell..."
merge_members_into_shell "$BASE_RAW_APK" "${WORK_DIR}/rebuilt.apk" "$OUT_RAW_APK"
verify_zip_scope "$BASE_RAW_APK" "$OUT_RAW_APK"

echo "Copying stock v2/v3 signing block into patched Sidebar APK..."
"$V2_PRESERVER" --stock "$SIDEBAR_STOCK_APK" --edited "$OUT_RAW_APK" --out "$OUT_V2_APK" >/dev/null

echo "Verifying decoded output semantics..."
verify_decoded_output "$OUT_V2_APK" "${WORK_DIR}/check"

echo "Recording signature boundary..."
"$SIGCHECK" "$OUT_V2_APK" > "$SIG_REPORT"
grep -q '^apk_sig_block_magic=present$' "$SIG_REPORT" \
  || die "expected copied APK Sig Block 42 in ${OUT_V2_APK}"
grep -q '^keytool_status=1$' "$SIG_REPORT" \
  || die "expected keytool digest-boundary status for modified Sidebar APK"

base_raw_hash="$(sha256_one "$BASE_RAW_APK")"
base_v2_hash="$(sha256_one "$BASE_V2_APK")"
out_raw_hash="$(sha256_one "$OUT_RAW_APK")"
out_v2_hash="$(sha256_one "$OUT_V2_APK")"
stock_hash="$(sha256_one "$SIDEBAR_STOCK_APK")"

{
  echo "variant=sidebar-font-ocr-disabled-apk"
  echo "purpose=Retire One Step font OCR while preserving Sidebar package identity and existing launcher/topbar patches"
  echo "base_raw_apk=${BASE_RAW_APK}"
  echo "base_raw_sha256=${base_raw_hash}"
  echo "base_v2_apk=${BASE_V2_APK}"
  echo "base_v2_sha256=${base_v2_hash}"
  echo "stock_apk=${SIDEBAR_STOCK_APK}"
  echo "stock_sha256=${stock_hash}"
  echo "out_raw_apk=${OUT_RAW_APK}"
  echo "out_raw_sha256=${out_raw_hash}"
  echo "out_v2_apk=${OUT_V2_APK}"
  echo "out_v2_sha256=${out_v2_hash}"
  echo "changed_members=AndroidManifest.xml,classes.dex,${FONT_BUTTON_LAYOUT}"
  echo "signature_report=${SIG_REPORT}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_V2_APK" "$OUT_RAW_APK" "$BASE_RAW_APK" "$BASE_V2_APK" "$SIDEBAR_STOCK_APK"
} > "$MANIFEST"

echo "Built: ${OUT_V2_APK}"
echo "Manifest: ${MANIFEST}"
echo "Signature report: ${SIG_REPORT}"
echo "Flash gate: APK-only artifact; ROM build and explicit flash confirmation are still required."
