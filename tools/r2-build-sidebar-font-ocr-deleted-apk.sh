#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
V2_PRESERVER="${V2_PRESERVER:-${ROOT_DIR}/tools/r2-apk-preserve-v2-signing-block.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
SIDEBAR_STOCK_APK="${RAW}/system/system/priv-app/Sidebar/Sidebar.apk"

OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/sidebar-font-ocr-deleted-apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"

BASE_RAW_APK="${BASE_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-disabled.apk}"
OUT_RAW_APK="${OUT_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-deleted.apk}"
OUT_V2_APK="${OUT_V2_APK:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-deleted-v2cert.apk}"
MANIFEST="${MANIFEST:-${OUT_DIR}/sidebar-font-ocr-deleted-apk-manifest.tsv}"
SIG_REPORT="${SIG_REPORT:-${OUT_DIR}/com.smartisanos.sidebar-font-ocr-deleted.signature.txt}"

PACKAGE_NAME="com.smartisanos.sidebar"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-sidebar-font-ocr-deleted-apk.sh

Build a Sidebar APK-only candidate that fully removes the retired One Step font
OCR code path on top of the live-verified v0.38 behavioral stop. It:

  - removes BoomFontActivity and FontResultActivity manifest declarations
  - removes Sidebar's com.smartisanos.sidebar.open.font class cluster
  - removes Sidebar's local com.intsig.csopen SDK copy
  - removes IdentifyFontView classes
  - removes METHOD_FONT_REQUEST -> FontUtils reachability
  - prevents stale tool-button type=1 rows from being read or inflated

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

patch_manifest() {
  local manifest_xml="$1"
  "$PYTHON_BIN" - "$manifest_xml" "$PACKAGE_NAME" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
package_name = sys.argv[2]
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
ET.register_namespace("android", ANDROID_NS)


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def full_component(raw: str) -> str:
    if raw.startswith("."):
        return package_name + raw
    if "." not in raw:
        return package_name + "." + raw
    return raw


remove_components = {
    "com.smartisanos.sidebar.open.font.BoomFontActivity",
    "com.smartisanos.sidebar.open.font.FontResultActivity",
}

tree = ET.parse(path)
root = tree.getroot()
if root.attrib.get("package") != package_name:
    raise SystemExit(f"package mismatch: {root.attrib.get('package')} != {package_name}")
application = next((child for child in root if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("manifest has no application")

removed = []
for child in list(application):
    if local(child.tag) != "activity":
        continue
    component = full_component(child.attrib.get(NAME, ""))
    if component in remove_components:
        application.remove(child)
        removed.append(component)

if set(removed) != remove_components:
    raise SystemExit(f"removed {sorted(removed)}, expected {sorted(remove_components)}")

text = ET.tostring(root, encoding="unicode")
for token in ("BoomFontActivity", "FontResultActivity", "ocr_key", "smartisanos.intent.action.BOOM_FONT"):
    if token in text:
        raise SystemExit(f"manifest still contains {token}")

tree.write(path, encoding="utf-8", xml_declaration=True)
print("removed_manifest_components=" + ",".join(sorted(removed)))
PY
}

patch_reachability_smali() {
  local decoded_dir="$1"
  "$PYTHON_BIN" - "$decoded_dir" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
provider = root / "smali/com/smartisanos/sidebar/storage/SidebarCallProvider.smali"
manager = root / "smali/com/smartisanos/sidebar/util/ToolButtonManager.smali"
db = root / "smali/com/smartisanos/sidebar/util/ToolButtonManager$ToolButtonDatabaseHelper.smali"
adapter_layouts = root / "smali/com/smartisanos/sidebar/toparea/view/ToolButtonAdapter$6.smali"


def replace_exact(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"missing patch target {label} in {path}")
    path.write_text(text.replace(old, new, 1))


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


replace_exact(
    provider,
    "    invoke-static {p0}, Lcom/smartisanos/sidebar/open/font/FontUtils;->toggleFont(Landroid/content/Context;)V\n",
    "    # Smartisax: font OCR removed; METHOD_FONT_REQUEST is intentionally inert.\n",
    "SidebarCallProvider font request",
)

replace_method(
    manager,
    "private updateToolButtonItems()V",
    """
.method private updateToolButtonItems()V
    .locals 3

    iget-object v0, p0, Lcom/smartisanos/sidebar/util/ToolButtonManager;->mContext:Landroid/content/Context;

    invoke-static {v0}, Lcom/smartisanos/sidebar/util/ToolsHelper;->isWordLookupOn(Landroid/content/Context;)Z

    move-result v0

    const/4 v1, 0x0

    invoke-virtual {p0, v1, v0}, Lcom/smartisanos/sidebar/util/ToolButtonManager;->update(IZ)V

    const/4 v0, 0x1

    invoke-virtual {p0, v0, v1}, Lcom/smartisanos/sidebar/util/ToolButtonManager;->update(IZ)V

    iget-object v2, p0, Lcom/smartisanos/sidebar/util/ToolButtonManager;->mContext:Landroid/content/Context;

    invoke-static {v2}, Lcom/smartisanos/sidebar/util/ToolsHelper;->isBindAppOn(Landroid/content/Context;)Z

    move-result v2

    const/4 v0, 0x2

    invoke-virtual {p0, v0, v2}, Lcom/smartisanos/sidebar/util/ToolButtonManager;->update(IZ)V

    iget-object v2, p0, Lcom/smartisanos/sidebar/util/ToolButtonManager;->mContext:Landroid/content/Context;

    invoke-static {v2}, Lcom/smartisanos/sidebar/util/ToolsHelper;->isThreeInOneAppOn(Landroid/content/Context;)Z

    move-result v2

    const/4 v0, 0x3

    invoke-virtual {p0, v0, v2}, Lcom/smartisanos/sidebar/util/ToolButtonManager;->update(IZ)V

    return-void
.end method
""",
)

replace_exact(
    db,
    """    invoke-interface {v1, v2}, Landroid/database/Cursor;->getInt(I)I

    move-result v2

    const-string v3, "weight"
""",
    """    invoke-interface {v1, v2}, Landroid/database/Cursor;->getInt(I)I

    move-result v2

    const/4 v6, 0x1

    if-eq v2, v6, :goto_0

    const-string v3, "weight"
""",
    "ToolButtonDatabaseHelper stale type=1 filter",
)

replace_exact(
    db,
    """    iget-object v1, p0, Lcom/smartisanos/sidebar/util/ToolButtonManager$ToolButtonDatabaseHelper;->mContext:Landroid/content/Context;

    invoke-static {v1}, Lcom/smartisanos/sidebar/util/ToolsHelper;->isFontLookupOn(Landroid/content/Context;)Z

    move-result v1
""",
    """    const/4 v1, 0x0
""",
    "ToolButtonDatabaseHelper default type=1 seed guard",
)

replace_exact(
    adapter_layouts,
    """    const v0, 0x7f090065

    .line 295
    invoke-static {v0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    const/4 v1, 0x1

    invoke-virtual {p0, v1, v0}, Lcom/smartisanos/sidebar/toparea/view/ToolButtonAdapter$6;->append(ILjava/lang/Object;)V

""",
    "",
    "ToolButtonAdapter type=1 layout mapping",
)

for path, forbidden in (
    (provider, "Lcom/smartisanos/sidebar/open/font/"),
    (manager, "isFontLookupOn"),
    (db, "isFontLookupOn"),
    (adapter_layouts, "0x7f090065"),
):
    if forbidden in path.read_text():
        raise SystemExit(f"{path} still contains {forbidden}")

print("patched_sidebar_font_ocr_reachability=ok")
PY
}

delete_retired_code() {
  local decoded_dir="$1"
  rm -rf \
    "${decoded_dir}/smali/com/smartisanos/sidebar/open/font" \
    "${decoded_dir}/smali/com/intsig/csopen"
  rm -f "${decoded_dir}"/smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView*.smali
}

merge_members_into_shell() {
  local base_apk="$1"
  local rebuilt_apk="$2"
  local out_apk="$3"
  local tmp
  tmp="$(mktemp -d "/tmp/r2-sidebar-font-delete.XXXXXX")"
  unzip -p "$rebuilt_apk" AndroidManifest.xml > "${tmp}/AndroidManifest.xml"
  unzip -p "$rebuilt_apk" classes.dex > "${tmp}/classes.dex"
  touch -t 200901010000 "${tmp}/AndroidManifest.xml"
  touch -t 200901010000 "${tmp}/classes.dex"
  cp "$base_apk" "${out_apk}.tmp"
  (
    cd "$tmp"
    zip -X -q "${out_apk}.tmp" AndroidManifest.xml classes.dex
  )
  mv "${out_apk}.tmp" "$out_apk"
  rm -rf "$tmp"
}

verify_zip_scope() {
  local base_apk="$1"
  local out_apk="$2"
  "$PYTHON_BIN" - "$base_apk" "$out_apk" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile

base, out = sys.argv[1:3]


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
expected = {"AndroidManifest.xml", "classes.dex"}
if set(changed) != expected:
    raise SystemExit(f"unexpected changed members: {changed}")
print(f"changed_members={','.join(changed)}")
for name in changed:
    print(f"{name}_sha256={hashlib.sha256(out_members[name]).hexdigest()}")
PY
}

verify_deleted_output() {
  local apk="$1"
  local check_dir="$2"
  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/decoded" "$apk" >/dev/null
  "$PYTHON_BIN" - "${check_dir}/decoded" <<'PY'
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
    raise SystemExit(f"package mismatch: {package_name}")
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

absent_paths = [
    root / "smali/com/smartisanos/sidebar/open/font",
    root / "smali/com/intsig/csopen",
    root / "smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView.smali",
    root / "smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView$1.smali",
]
for path in absent_paths:
    if path.exists():
        raise SystemExit(f"deleted path still present: {path.relative_to(root)}")

scan_roots = [root / "smali/com/smartisanos/sidebar"]
for scan_root in scan_roots:
    for path in scan_root.rglob("*.smali"):
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

print("manifest_font_ocr_components_absent=ok")
print("sidebar_open_font_classes_absent=ok")
print("sidebar_intsig_sdk_absent=ok")
print("identify_font_view_absent=ok")
print("font_request_provider_reference_absent=ok")
print("tool_button_type1_layout_mapping_absent=ok")
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
need_file "$BASE_RAW_APK"
need_executable "$V2_PRESERVER"
need_executable "$SIGCHECK"
need_command "$PYTHON_BIN"
need_command zip
need_command unzip

mkdir -p "$OUT_DIR" "$WORK_DIR"
rm -rf "${WORK_DIR}/decoded" "${WORK_DIR}/check" "${WORK_DIR}/rebuilt.apk"
rm -f "$OUT_RAW_APK" "$OUT_V2_APK" "$MANIFEST" "$SIG_REPORT"

install_frameworks

echo "Decoding Sidebar v0.38 font-OCR-disabled base APK..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${WORK_DIR}/decoded" "$BASE_RAW_APK" >/dev/null

echo "Removing font OCR manifest declarations..."
patch_manifest "${WORK_DIR}/decoded/AndroidManifest.xml" > "${WORK_DIR}/manifest-patch-report.txt"

echo "Removing font OCR reachability from provider/manager/adapter..."
patch_reachability_smali "${WORK_DIR}/decoded" > "${WORK_DIR}/smali-reachability-patch-report.txt"

echo "Deleting retired font OCR and Sidebar Intsig classes..."
delete_retired_code "${WORK_DIR}/decoded"

echo "Rebuilding Sidebar font-OCR-deleted carrier..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "${WORK_DIR}/rebuilt.apk" "${WORK_DIR}/decoded" >/dev/null

echo "Merging patched manifest/classes into v0.38 APK shell..."
merge_members_into_shell "$BASE_RAW_APK" "${WORK_DIR}/rebuilt.apk" "$OUT_RAW_APK"
verify_zip_scope "$BASE_RAW_APK" "$OUT_RAW_APK"

echo "Copying stock v2/v3 signing block into patched Sidebar APK..."
"$V2_PRESERVER" --stock "$SIDEBAR_STOCK_APK" --edited "$OUT_RAW_APK" --out "$OUT_V2_APK" >/dev/null

echo "Verifying deleted output semantics..."
verify_deleted_output "$OUT_V2_APK" "${WORK_DIR}/check"

echo "Recording signature boundary..."
"$SIGCHECK" "$OUT_V2_APK" > "$SIG_REPORT"
grep -q '^apk_sig_block_magic=present$' "$SIG_REPORT" \
  || die "expected copied APK Sig Block 42 in ${OUT_V2_APK}"
grep -q '^keytool_status=1$' "$SIG_REPORT" \
  || die "expected keytool digest-boundary status for modified Sidebar APK"

base_raw_hash="$(sha256_one "$BASE_RAW_APK")"
out_raw_hash="$(sha256_one "$OUT_RAW_APK")"
out_v2_hash="$(sha256_one "$OUT_V2_APK")"
stock_hash="$(sha256_one "$SIDEBAR_STOCK_APK")"

{
  echo "variant=sidebar-font-ocr-deleted-apk"
  echo "purpose=Code-level deletion of retired One Step font OCR and Sidebar-local CamScanner SDK"
  echo "base_raw_apk=${BASE_RAW_APK}"
  echo "base_raw_sha256=${base_raw_hash}"
  echo "stock_apk=${SIDEBAR_STOCK_APK}"
  echo "stock_sha256=${stock_hash}"
  echo "out_raw_apk=${OUT_RAW_APK}"
  echo "out_raw_sha256=${out_raw_hash}"
  echo "out_v2_apk=${OUT_V2_APK}"
  echo "out_v2_sha256=${out_v2_hash}"
  echo "changed_members=AndroidManifest.xml,classes.dex"
  echo "signature_report=${SIG_REPORT}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_V2_APK" "$OUT_RAW_APK" "$BASE_RAW_APK" "$SIDEBAR_STOCK_APK"
} > "$MANIFEST"

echo "Built: ${OUT_V2_APK}"
echo "Manifest: ${MANIFEST}"
echo "Signature report: ${SIG_REPORT}"
echo "Flash gate: APK-only artifact; ROM build and explicit flash confirmation are still required."
