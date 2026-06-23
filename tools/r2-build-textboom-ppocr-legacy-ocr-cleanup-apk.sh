#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

JAVA_BIN="${JAVA_BIN:-${JAVA_HOME}/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

VARIANT="${VARIANT:-v0.44-textboom-ppocr-legacy-ocr-cleanup}"
SOURCE_APK="${SOURCE_APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-force-arm32.apk}"
SOURCE_APK_SHA256="0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}-apk}"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_UNSIGNED="${WORK_DIR}/TextBoom-ppocr-legacy-ocr-cleanup-rebuilt-unsigned.apk"
MERGED_APK="${WORK_DIR}/TextBoom-ppocr-legacy-ocr-cleanup-merged.apk"
OUT_APK="${OUT_APK:-${OUT_DIR}/TextBoom-ppocr-legacy-ocr-cleanup.apk}"
case "$OUT_APK" in
  /*) ;;
  *) OUT_APK="${ROOT_DIR}/${OUT_APK}" ;;
esac
SIG_REPORT="${OUT_APK%.apk}.signature.txt"
ZIP_REPORT="${OUT_APK%.apk}.zip-boundary.txt"
LAYOUT_REPORT="${OUT_APK%.apk}.zip-layout.txt"
AUDIT_REPORT="${OUT_APK%.apk}.legacy-ocr-audit.txt"
MANIFEST="${MANIFEST:-${OUT_DIR}/textboom-ppocr-legacy-ocr-cleanup-apk-manifest.tsv}"
case "$MANIFEST" in
  /*) ;;
  *) MANIFEST="${ROOT_DIR}/${MANIFEST}" ;;
esac

OLD_INTSIG_HOST="imgs-sandbox.intsig.net"
OLD_INTSIG_USER="smartisan"
NEW_INTSIG_URL=""

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-textboom-ppocr-legacy-ocr-cleanup-apk.sh

Builds an APK-only TextBoom follow-up on top of the live-proven v0.43e APK.
It keeps the original AndroidManifest.xml and manifest ocr_key carrier, but:

  - forces BoomAccessOcrActivity's accessibility OCR path to use LocalPpOcrApi
    instead of the old network OCR branch when the device has connectivity;
  - removes the hardcoded Intsig/CamScanner online OCR URL from classes2.dex;
  - removes CamScanner wording from OCR error strings in resources.arsc;
  - renames the inert ocr_camscanner_* resource symbols to storage-neutral
    names while preserving the same resource IDs.

This script changes only classes2.dex and resources.arsc in the APK shell.
It does not build a super image, touch a device, flash, reboot, erase
partitions, install packages, or modify /data.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
need_command() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

install_frameworks() {
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

patch_decoded_apk() {
  "$PYTHON_BIN" - "$DECODED_DIR" "$OLD_INTSIG_HOST" "$OLD_INTSIG_USER" "$NEW_INTSIG_URL" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
legacy_host = sys.argv[2]
legacy_user = sys.argv[3]
new_url = sys.argv[4]

access_activity = root / "smali_classes2/com/smartisanos/textboom/ocr/BoomAccessOcrActivity.smali"
r_string = root / "smali_classes2/com/smartisanos/textboom/R$string.smali"
manifest = root / "AndroidManifest.xml"

for path in (access_activity, r_string, manifest):
    if not path.exists():
        raise SystemExit(f"missing expected file: {path}")

text = access_activity.read_text(encoding="utf-8")
legacy_url_prefix = (
    f"http://{legacy_host}/icr/recognize_document?user={legacy_user}&"
    + "pass"
    + "word="
)
old_field = re.compile(
    r'(\.field private static url:Ljava/lang/String; = ")'
    + re.escape(legacy_url_prefix)
    + r'[^"]*(")'
)
text, count = old_field.subn(rf"\1{new_url}\2", text, count=1)
if count != 1:
    raise SystemExit("expected exactly one legacy Intsig URL field")

old_branch = (
    "    .line 137\n"
    "    invoke-virtual {p0}, Lcom/smartisanos/textboom/ocr/BoomAccessOcrActivity;->isConnected()Z\n\n"
    "    move-result v0\n"
)
new_branch = (
    "    .line 137\n"
    "    const/4 v0, 0x0\n"
)
if text.count(old_branch) != 1:
    raise SystemExit("expected exactly one BoomAccessOcrActivity connectivity gate")
text = text.replace(old_branch, new_branch, 1)
access_activity.write_text(text, encoding="utf-8")

symbol_renames = {
    "ocr_camscanner_no_permission": "ocr_storage_no_permission",
    "ocr_camscanner_permission_denied": "ocr_storage_permission_denied",
}

for xml in sorted((root / "res").glob("values*/strings.xml")):
    data = xml.read_text(encoding="utf-8")
    had_permission_strings = any(
        f'name="{old}"' in data for old in symbol_renames
    )
    for old, new in symbol_renames.items():
        data = data.replace(f'name="{old}"', f'name="{new}"')
    locale = xml.parent.name
    if locale == "values-zh-rCN":
        replacements = {
            "ocr_storage_no_permission": "图像识别需要存储权限，请授予相关权限后重试",
            "ocr_storage_permission_denied": "图像识别无法读取图片，请授予存储权限后重试",
            "ocr_recognize_not_available": "本地识别服务暂不可用，请稍后重试",
            "ocr_recognize_uninstall": "本地识别服务暂不可用，请稍后重试",
        }
    elif locale in {"values-zh-rTW", "values-zh-rHK"}:
        replacements = {
            "ocr_storage_no_permission": "圖像識別需要儲存權限，請授予相關權限後重試",
            "ocr_storage_permission_denied": "圖像識別無法讀取圖片，請授予儲存權限後重試",
            "ocr_recognize_not_available": "本地識別服務暫不可用，請稍後重試",
            "ocr_recognize_uninstall": "本地識別服務暫不可用，請稍後重試",
        }
    else:
        replacements = {
            "ocr_storage_no_permission": "Image recognition needs storage permission. Please grant permission and try again.",
            "ocr_storage_permission_denied": "Image recognition cannot read the image. Please grant storage permission and try again.",
            "ocr_recognize_not_available": "Local recognition service is temporarily unavailable. Please try again.",
            "ocr_recognize_uninstall": "Local recognition service is temporarily unavailable. Please try again.",
        }
    for name, value in replacements.items():
        pattern = re.compile(
            rf'(<string name="{re.escape(name)}">)(.*?)(</string>)',
            re.DOTALL,
        )
        data, count = pattern.subn(rf"\1{value}\3", data, count=1)
        if count == 0 and had_permission_strings and name in {
            "ocr_storage_no_permission",
            "ocr_storage_permission_denied",
        }:
            raise SystemExit(f"{xml} missing required string {name}")
    xml.write_text(data, encoding="utf-8")

public_xml = root / "res/values/public.xml"
data = public_xml.read_text(encoding="utf-8")
for old, new in symbol_renames.items():
    data = data.replace(f'name="{old}"', f'name="{new}"')
public_xml.write_text(data, encoding="utf-8")

data = r_string.read_text(encoding="utf-8")
for old, new in symbol_renames.items():
    data = data.replace(f" {old}:I", f" {new}:I")
r_string.write_text(data, encoding="utf-8")

manifest_text = manifest.read_text(encoding="utf-8", errors="replace")
if 'android:name="ocr_key"' not in manifest_text:
    raise SystemExit("manifest ocr_key was unexpectedly removed")

access_text = access_activity.read_text(encoding="utf-8", errors="replace")
if old_url in access_text:
    raise SystemExit("legacy Intsig URL still present after patch")
if "Lcom/smartisanos/textboom/ocr/BoomAccessOcrActivity;->isConnected()Z" in access_text:
    raise SystemExit("BoomAccessOcrActivity still branches on connectivity for OCR")
if "new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in access_text:
    raise SystemExit("BoomAccessOcrActivity lost LocalPpOcrApi init")

print("patched_textboom_legacy_ocr_cleanup=ok")
PY
}

merge_changed_entries() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-textboom-legacy-ocr-cleanup-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  cp "$SOURCE_APK" "$MERGED_APK"
  unzip -p "$REBUILT_UNSIGNED" classes2.dex > "${tmp}/classes2.dex"
  unzip -p "$REBUILT_UNSIGNED" resources.arsc > "${tmp}/resources.arsc"
  touch -t 200901010000 "${tmp}/classes2.dex" "${tmp}/resources.arsc"
  (
    cd "$tmp"
    zip -X -q "$MERGED_APK" classes2.dex
    zip -X -q -0 "$MERGED_APK" resources.arsc
  )
  "$ZIPALIGN" -p -f 4 "$MERGED_APK" "$OUT_APK"
}

verify_zip_boundary() {
  "$PYTHON_BIN" - "$SOURCE_APK" "$OUT_APK" "$ZIP_REPORT" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1])
out = Path(sys.argv[2])
report = Path(sys.argv[3])
allowed_changed = {"classes2.dex", "resources.arsc"}

with zipfile.ZipFile(source) as a, zipfile.ZipFile(out) as b:
    names_a = set(a.namelist())
    names_b = set(b.namelist())
    removed = sorted(names_a - names_b)
    added = sorted(names_b - names_a)
    changed = sorted(name for name in names_a & names_b if a.read(name) != b.read(name))
    if removed:
        raise SystemExit(f"unexpected removed zip entries: {removed}")
    if added:
        raise SystemExit(f"unexpected added zip entries: {added}")
    if set(changed) != allowed_changed:
        raise SystemExit(f"unexpected changed entries: {changed}")
    report.write_text(
        "changed_entries=" + ",".join(changed) + "\n"
        + "removed_entries=\n"
        + "added_entries=\n",
        encoding="utf-8",
    )
print("zip_boundary=ok")
PY
}

verify_resources_layout() {
  "$PYTHON_BIN" - "$OUT_APK" "$LAYOUT_REPORT" <<'PY'
from __future__ import annotations

import struct
import sys
import zipfile
from pathlib import Path

apk = Path(sys.argv[1])
report = Path(sys.argv[2])
with zipfile.ZipFile(apk) as zf, apk.open("rb") as fp:
    info = zf.getinfo("resources.arsc")
    fp.seek(info.header_offset)
    header = fp.read(30)
    if len(header) != 30 or header[:4] != b"PK\x03\x04":
        raise SystemExit("invalid local zip header for resources.arsc")
    name_len, extra_len = struct.unpack_from("<HH", header, 26)
    data_offset = info.header_offset + 30 + name_len + extra_len
    lines = [
        f"resources.arsc_method={info.compress_type}",
        f"resources.arsc_data_offset={data_offset}",
        f"resources.arsc_data_offset_mod4={data_offset % 4}",
        f"resources.arsc_size={info.file_size}",
    ]
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit("resources.arsc is not STORED")
    if data_offset % 4 != 0:
        raise SystemExit(f"resources.arsc data offset is not 4-byte aligned: {data_offset}")
print("resources_arsc_layout=ok")
PY
}

verify_rebuilt_semantics() {
  local strings_file="${WORK_DIR}/classes2.strings"
  local arsc_strings_file="${WORK_DIR}/resources.arsc.strings"
  rm -rf "$VERIFY_DECODED_DIR"
  unzip -t "$OUT_APK" >/dev/null
  unzip -p "$OUT_APK" classes2.dex | strings > "$strings_file"
  unzip -p "$OUT_APK" resources.arsc | strings > "$arsc_strings_file"

  if grep -qF "$OLD_INTSIG_HOST" "$strings_file"; then
    die "classes2.dex still contains legacy Intsig URL"
  fi
  if grep -qiE 'CamScanner|Camscanner|扫描全能王|com/intsig|Lcom/intsig|CsOcr|CSOCR|CSOpenApi' "$strings_file"; then
    die "classes2.dex still contains executable legacy OCR strings"
  fi
  if grep -qiE 'CamScanner|Camscanner|扫描全能王|全能王|合合' "$arsc_strings_file"; then
    die "resources.arsc still contains CamScanner wording"
  fi
  grep -q 'ocr_storage_no_permission' "$arsc_strings_file" \
    || die "resources.arsc missing renamed storage permission symbol"
  grep -q 'LocalPpOcrApi' "$strings_file" || die "classes2.dex lost LocalPpOcrApi"
  grep -q 'LocalPpOcrRuntime' "$strings_file" || die "classes2.dex lost LocalPpOcrRuntime"

  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$VERIFY_DECODED_DIR" "$OUT_APK" >/dev/null
  "$PYTHON_BIN" - "$VERIFY_DECODED_DIR" "$OLD_INTSIG_HOST" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
legacy_host = sys.argv[2]
access_activity = root / "smali_classes2/com/smartisanos/textboom/ocr/BoomAccessOcrActivity.smali"
manifest = root / "AndroidManifest.xml"
strings_cn = root / "res/values-zh-rCN/strings.xml"
public_xml = root / "res/values/public.xml"
r_string = root / "smali_classes2/com/smartisanos/textboom/R$string.smali"

for path in (access_activity, manifest, strings_cn, public_xml, r_string):
    if not path.exists():
        raise SystemExit(f"missing verification file: {path}")

access = access_activity.read_text(encoding="utf-8", errors="replace")
if legacy_host in access:
    raise SystemExit("verified smali still contains legacy URL")
if "Lcom/smartisanos/textboom/ocr/BoomAccessOcrActivity;->isConnected()Z" in access:
    raise SystemExit("verified accessibility OCR still checks connectivity")
if "new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in access:
    raise SystemExit("verified accessibility OCR lost LocalPpOcrApi init")
if 'android:name="ocr_key"' not in manifest.read_text(encoding="utf-8", errors="replace"):
    raise SystemExit("verified manifest ocr_key unexpectedly removed")
for path in (strings_cn, public_xml, r_string):
    text = path.read_text(encoding="utf-8", errors="replace")
    if "ocr_camscanner" in text or "扫描全能王" in text or "CamScanner" in text or "Camscanner" in text:
        raise SystemExit(f"verified legacy wording/symbol remains in {path}")
if "ocr_storage_no_permission" not in public_xml.read_text(encoding="utf-8", errors="replace"):
    raise SystemExit("verified public.xml missing renamed storage symbol")
print("textboom_legacy_ocr_cleanup_semantics=ok")
PY

  {
    echo "classes2_legacy_url_absent=true"
    echo "classes2_connectivity_gate_removed=true"
    echo "classes2_local_ppocr_retained=true"
    echo "resources_camscanner_wording_absent=true"
    echo "resources_storage_symbols_present=true"
    echo "manifest_ocr_key_retained=true"
  } > "$AUDIT_REPORT"
}

write_signature_report() {
  "$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"
  grep -q '^apk_sig_block_magic=absent$' "$SIG_REPORT" \
    || die "TextBoom v2/v3 signing-block boundary changed"
  grep -Eq 'digest error for (classes2.dex|resources.arsc)' "$SIG_REPORT" \
    || die "TextBoom signature boundary did not point at changed stock-shell entries"
}

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$SOURCE_APK"
need_executable "$JAVA_BIN"
need_executable "$ZIPALIGN"
need_executable "$SIGCHECK"
need_command zip
need_command zipinfo
need_command unzip
need_command strings
require_hash "$SOURCE_APK" "$SOURCE_APK_SHA256"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT" "$ZIP_REPORT" "$LAYOUT_REPORT" "$AUDIT_REPORT" "$MANIFEST"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding TextBoom v0.43e APK..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$SOURCE_APK" >/dev/null

echo "Patching TextBoom legacy OCR branch and strings..."
patch_decoded_apk

echo "Rebuilding patched TextBoom as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging patched classes2.dex and resources.arsc into source shell..."
merge_changed_entries

echo "Verifying ZIP boundary, resources layout, and semantics..."
verify_zip_boundary
verify_resources_layout
verify_rebuilt_semantics

echo "Writing signature boundary report..."
write_signature_report

{
  echo "variant=${VARIANT}"
  echo "source_apk=${SOURCE_APK}"
  echo "source_apk_sha256=${SOURCE_APK_SHA256}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "out_apk=${OUT_APK}"
  echo "out_apk_sha256=$(sha256_one "$OUT_APK")"
  echo "signature_report=${SIG_REPORT}"
  echo "zip_boundary_report=${ZIP_REPORT}"
  echo "zip_layout_report=${LAYOUT_REPORT}"
  echo "legacy_ocr_audit_report=${AUDIT_REPORT}"
  echo "changed_zip_entries=classes2.dex,resources.arsc"
  echo "removed_zip_entries="
  echo "manifest_ocr_key_retained=true"
  echo "legacy_intsig_url_removed=true"
  echo "accessibility_ocr_forced_local_ppocr=true"
  echo "resources_camscanner_wording_removed=true"
  echo "resource_symbol_renames=ocr_camscanner_no_permission->ocr_storage_no_permission,ocr_camscanner_permission_denied->ocr_storage_permission_denied"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$SOURCE_APK" "$REBUILT_UNSIGNED" "$OUT_APK" "$SIG_REPORT" "$ZIP_REPORT" "$LAYOUT_REPORT" "$AUDIT_REPORT"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Signature report: ${SIG_REPORT}"
echo "ZIP report: ${ZIP_REPORT}"
echo "Layout report: ${LAYOUT_REPORT}"
echo "Audit report: ${AUDIT_REPORT}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: APK-only artifact; no live flash authorization."
