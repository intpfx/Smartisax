#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
LAUNCHER_HIDE_BUILDER="${LAUNCHER_HIDE_BUILDER:-${ROOT_DIR}/tools/r2-build-launcher-entry-hide-apks.sh}"
V2_PRESERVER="${V2_PRESERVER:-${ROOT_DIR}/tools/r2-apk-preserve-v2-signing-block.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
SIDEBAR_STOCK_APK="${RAW}/system/system/priv-app/Sidebar/Sidebar.apk"

OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/sidebar-topbar-hide-apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"

BASE_RAW_APK="${BASE_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-launcher-hidden.apk}"
BASE_V2_APK="${BASE_V2_APK:-${OUT_DIR}/com.smartisanos.sidebar-launcher-hidden-v2cert.apk}"
OUT_RAW_APK="${OUT_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-topbar-hidden.apk}"
OUT_V2_APK="${OUT_V2_APK:-${OUT_DIR}/com.smartisanos.sidebar-topbar-hidden-v2cert.apk}"
MANIFEST="${MANIFEST:-${OUT_DIR}/sidebar-topbar-hide-apk-manifest.tsv}"
SIG_REPORT="${SIG_REPORT:-${OUT_DIR}/com.smartisanos.sidebar-topbar-hidden.signature.txt}"

LAYOUT_MEMBER="res/layout/top_area_title_view.xml"
PACKAGE_NAME="com.smartisanos.sidebar"
SETTING_ACTIVITY="com.smartisanos.sidebar.setting.SettingActivity"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-sidebar-topbar-hide-apk.sh

Build a Sidebar APK candidate that keeps com.smartisanos.sidebar installed and
functional while deleting the stock One Step top title/control bar widgets.
The candidate is built on top of the v0.26c launcher-hidden Sidebar APK and
keeps the topbar container reserved as a blank future feature slot. It changes:

  res/layout/top_area_title_view.xml
  classes.dex

and then copies the stock APK signing block back as the certificate carrier.
This script does not flash, reboot, erase misc, or change /data.
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

install_frameworks() {
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
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

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]

if local(root.tag) != "LinearLayout":
    raise SystemExit(f"unexpected root tag: {root.tag}")

required_ids = {
    "sidebar_top_view_left_one",
    "sidebar_top_view_left_two",
    "sidebar_top_view_right_one",
    "sidebar_top_view_right_two",
}
seen_ids: set[str] = set()
text_nodes = 0

for child in list(root):
    child_id = child.attrib.get(ATTR("id"))
    if child_id:
        seen_ids.add(child_id.rsplit("/", 1)[-1])
    if child.attrib.get(ATTR("text")) == "One Step":
        text_nodes += 1
    root.remove(child)

missing = sorted(required_ids - seen_ids)
if missing:
    raise SystemExit(f"missing expected topbar ids: {missing}")
if text_nodes != 1:
    raise SystemExit(f"expected exactly one One Step text node, changed={text_nodes}")

tree.write(path, encoding="utf-8", xml_declaration=True)
print("patched_layout=top_area_title_view container_preserved children_deleted")
PY
}

patch_smali_topbar_references() {
  local decoded_dir="$1"
  "$PYTHON_BIN" - "$decoded_dir" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
top = root / "smali/com/smartisanos/sidebar/toparea/view/TopAreaContentView.smali"
holder = root / "smali/com/smartisanos/sidebar/toparea/view/TopAreaContentViewHolder.smali"


def replace_method(text: str, signature: str, body: str) -> str:
    pattern = re.compile(
        rf"^\.method {re.escape(signature)}\n.*?^\.end method",
        re.MULTILINE | re.DOTALL,
    )
    out, count = pattern.subn(body.rstrip(), text, count=1)
    if count != 1:
        raise SystemExit(f"failed to replace method: {signature}")
    return out


text = top.read_text()
text = replace_method(
    text,
    "private updateTopUIBySidebarMode()V",
    """
.method private updateTopUIBySidebarMode()V
    .locals 0

    return-void
.end method
""",
)
text = replace_method(
    text,
    "private onSettingButtonClick()V",
    """
.method private onSettingButtonClick()V
    .locals 0

    return-void
.end method
""",
)
start_marker = "    .line 290\n    :cond_0\n    new-instance v0, Lcom/smartisanos/sidebar/toparea/view/TopAreaContentViewHolder;"
end_marker = "    .line 297\n    iget-object v0, p0, Lcom/smartisanos/sidebar/toparea/view/TopAreaContentView;->mScrollViewDragged"
start = text.find(start_marker)
if start < 0:
    raise SystemExit("failed to find onFinishInflate topbar binding start")
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("failed to find onFinishInflate topbar binding end")
replacement = (
    "    .line 290\n"
    "    :cond_0\n"
    "    # Smartisax: stock One Step topbar controls were deleted from the\n"
    "    # reserved topbar slot, so no title/button view binding happens here.\n"
    "\n"
)
text = text[:start] + replacement + text[end:]
top.write_text(text)

holder_text = holder.read_text()
holder_text = replace_method(
    holder_text,
    "public constructor <init>(Lcom/smartisanos/sidebar/toparea/view/TopAreaContentView;)V",
    """
.method public constructor <init>(Lcom/smartisanos/sidebar/toparea/view/TopAreaContentView;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method
""",
)
holder_text = replace_method(
    holder_text,
    "public getHolderBySidebarMode(I)Lcom/smartisanos/sidebar/toparea/view/TopAreaContentViewHolder$Holder;",
    """
.method public getHolderBySidebarMode(I)Lcom/smartisanos/sidebar/toparea/view/TopAreaContentViewHolder$Holder;
    .locals 1

    const/4 v0, 0x0

    return-object v0
.end method
""",
)
holder.write_text(holder_text)

print("patched_smali=stock topbar bindings removed")
PY
}

merge_layout_into_shell() {
  local base_apk="$1"
  local rebuilt_apk="$2"
  local out_apk="$3"
  local tmp
  tmp="$(mktemp -d "/tmp/r2-sidebar-topbar-layout.XXXXXX")"
  mkdir -p "${tmp}/res/layout"
  unzip -p "$rebuilt_apk" "$LAYOUT_MEMBER" > "${tmp}/${LAYOUT_MEMBER}"
  unzip -p "$rebuilt_apk" classes.dex > "${tmp}/classes.dex"
  touch -t 200901010000 "${tmp}/${LAYOUT_MEMBER}"
  touch -t 200901010000 "${tmp}/classes.dex"
  cp "$base_apk" "${out_apk}.tmp"
  (
    cd "$tmp"
    zip -X -q "${out_apk}.tmp" "$LAYOUT_MEMBER" classes.dex
  )
  mv "${out_apk}.tmp" "$out_apk"
  rm -rf "$tmp"
}

verify_zip_scope() {
  local base_apk="$1"
  local out_apk="$2"
  "$PYTHON_BIN" - "$base_apk" "$out_apk" "$LAYOUT_MEMBER" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile

base, out, expected = sys.argv[1:]

def members(path: str) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as zf:
        return {info.filename: zf.read(info.filename) for info in zf.infolist() if not info.is_dir()}

base_members = members(base)
out_members = members(out)
if set(base_members) != set(out_members):
    missing = sorted(set(base_members) - set(out_members))
    extra = sorted(set(out_members) - set(base_members))
    raise SystemExit(f"member set changed missing={missing[:10]} extra={extra[:10]}")

changed = sorted(
    name for name in base_members
    if hashlib.sha256(base_members[name]).digest() != hashlib.sha256(out_members[name]).digest()
)
expected_changed = {expected, "classes.dex"}
if set(changed) != expected_changed:
    raise SystemExit(f"unexpected changed members: {changed}")

print(f"changed_members={','.join(changed)}")
print(f"base_member_sha256={hashlib.sha256(base_members[expected]).hexdigest()}")
print(f"out_member_sha256={hashlib.sha256(out_members[expected]).hexdigest()}")
print(f"base_classes_sha256={hashlib.sha256(base_members['classes.dex']).hexdigest()}")
print(f"out_classes_sha256={hashlib.sha256(out_members['classes.dex']).hexdigest()}")
PY
}

verify_decoded_output() {
  local apk="$1"
  local check_dir="$2"
  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/decoded" "$apk" >/dev/null
  "$PYTHON_BIN" - "${check_dir}/decoded/AndroidManifest.xml" "${check_dir}/decoded/${LAYOUT_MEMBER}" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

manifest_path = Path(sys.argv[1])
layout_path = Path(sys.argv[2])
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
ATTR = lambda name: f"{{{ANDROID_NS}}}{name}"

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]

def full_component(package_name: str, raw: str) -> str:
    if raw.startswith("."):
        return package_name + raw
    if "." not in raw:
        return package_name + "." + raw
    return raw

def values(parent: ET.Element, tag_name: str) -> set[str]:
    return {
        child.attrib.get(NAME, "")
        for child in parent
        if local(child.tag) == tag_name and child.attrib.get(NAME)
    }

manifest = ET.parse(manifest_path).getroot()
package_name = manifest.attrib.get("package")
if package_name != "com.smartisanos.sidebar":
    raise SystemExit(f"package mismatch: {package_name}")

application = next((child for child in manifest if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("manifest has no application")
matches = [
    child for child in application
    if local(child.tag) in {"activity", "activity-alias"}
    and full_component(package_name, child.attrib.get(NAME, "")) == "com.smartisanos.sidebar.setting.SettingActivity"
]
if len(matches) != 1:
    raise SystemExit(f"SettingActivity match count={len(matches)}")
main_filters = [
    child for child in matches[0]
    if local(child.tag) == "intent-filter" and "android.intent.action.MAIN" in values(child, "action")
]
if not main_filters:
    raise SystemExit("SettingActivity MAIN filter missing")
if any("android.intent.category.LAUNCHER" in values(f, "category") for f in main_filters):
    raise SystemExit("SettingActivity still has LAUNCHER category")

layout = ET.parse(layout_path).getroot()
if layout.attrib.get(ATTR("layout_height")) != "match_parent":
    raise SystemExit("topbar reserved slot height is not preserved as match_parent")
if layout.attrib.get(ATTR("background")) != "@drawable/sidebar_topview_top_bg":
    raise SystemExit("topbar reserved slot background is not preserved")
if list(layout):
    raise SystemExit("topbar layout still has child controls")

print("manifest_launcher_hidden=ok")
print("topbar_slot_preserved=ok")
print("topbar_children_deleted=ok")
PY

  local top_smali="${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/TopAreaContentView.smali"
  local holder_smali="${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/TopAreaContentViewHolder.smali"
  [ -f "$top_smali" ] || die "decoded TopAreaContentView.smali missing"
  [ -f "$holder_smali" ] || die "decoded TopAreaContentViewHolder.smali missing"
  if grep -Eq 'new-instance .*TopAreaContentViewHolder|getHolderBySidebarMode|0x7f070092|0x7f07010f|0x7f070110|0x7f070112|0x7f070113' "$top_smali"; then
    die "TopAreaContentView.smali still references removed stock topbar views"
  fi
  if grep -Eq 'findViewById|UIHandler;->post|0x7f07010f|0x7f070110|0x7f070112|0x7f070113' "$holder_smali"; then
    die "TopAreaContentViewHolder.smali still binds removed stock topbar views"
  fi
  echo "topbar_smali_references_removed=ok"
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
need_executable "$LAUNCHER_HIDE_BUILDER"
need_executable "$V2_PRESERVER"
need_executable "$SIGCHECK"

mkdir -p "$OUT_DIR" "$WORK_DIR"

if [ ! -f "$BASE_RAW_APK" ] || [ ! -f "$BASE_V2_APK" ]; then
  echo "Building Sidebar launcher-hidden base APKs first..."
  "$LAUNCHER_HIDE_BUILDER" --variant v0.26c >/dev/null
fi

need_file "$BASE_RAW_APK"
need_file "$BASE_V2_APK"

rm -rf "${WORK_DIR}/decoded" "${WORK_DIR}/check" "${WORK_DIR}/rebuilt.apk"
rm -f "$OUT_RAW_APK" "$OUT_V2_APK" "$MANIFEST" "$SIG_REPORT"

install_frameworks

echo "Decoding Sidebar launcher-hidden base APK..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${WORK_DIR}/decoded" "$BASE_RAW_APK" >/dev/null

echo "Patching top_area_title_view.xml..."
patch_layout_xml "${WORK_DIR}/decoded/${LAYOUT_MEMBER}"
echo "Patching stock topbar smali references..."
patch_smali_topbar_references "${WORK_DIR}/decoded"

echo "Rebuilding patched Sidebar resources..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "${WORK_DIR}/rebuilt.apk" "${WORK_DIR}/decoded" >/dev/null

echo "Merging patched binary layout into launcher-hidden APK shell..."
merge_layout_into_shell "$BASE_RAW_APK" "${WORK_DIR}/rebuilt.apk" "$OUT_RAW_APK"
verify_zip_scope "$BASE_RAW_APK" "$OUT_RAW_APK" "$LAYOUT_MEMBER"

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
  echo "variant=v0.29-sidebar-topbar-hide-apk"
  echo "purpose=Delete stock One Step topbar controls while preserving a blank topbar slot for future features, Sidebar package identity, and v0.26c launcher-entry-hide manifest"
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
  echo "changed_members=classes.dex,${LAYOUT_MEMBER}"
  echo "signature_report=${SIG_REPORT}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_V2_APK" "$OUT_RAW_APK" "$BASE_RAW_APK" "$BASE_V2_APK" "$SIDEBAR_STOCK_APK"
} > "$MANIFEST"

echo "Built: ${OUT_V2_APK}"
echo "Manifest: ${MANIFEST}"
echo "Signature report: ${SIG_REPORT}"
echo "Flash gate: APK-only artifact; ROM build and explicit flash confirmation are still required."
