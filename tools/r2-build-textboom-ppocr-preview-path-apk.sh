#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

JAVA_BIN="${JAVA_BIN:-${JAVA_HOME}/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

VARIANT="${VARIANT:-v0.42-textboom-ppocr-preview-path}"
SOURCE_APK="${SOURCE_APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-runtime-adapter.apk}"
SOURCE_APK_SHA256="6f0d3964234f57c059f70446ba330e9dcb8a3741ae9ce97dfdc8d6fe7ce880a6"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}-apk}"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_UNSIGNED="${REBUILT_UNSIGNED:-${WORK_DIR}/TextBoom-ppocr-preview-path-rebuilt-unsigned.apk}"
OUT_APK="${OUT_APK:-${OUT_DIR}/TextBoom-ppocr-preview-path.apk}"
case "$OUT_APK" in
  /*) ;;
  *) OUT_APK="${ROOT_DIR}/${OUT_APK}" ;;
esac
SIG_REPORT="${OUT_APK%.apk}.signature.txt"
ZIP_REPORT="${OUT_APK%.apk}.zip-boundary.txt"
MANIFEST="${MANIFEST:-${OUT_DIR}/textboom-ppocr-preview-path-apk-manifest.tsv}"
case "$MANIFEST" in
  /*) ;;
  *) MANIFEST="${ROOT_DIR}/${MANIFEST}" ;;
esac

OLD_OCR_DIR="${OLD_OCR_DIR:-/.boom}"
NEW_OCR_DIR="${NEW_OCR_DIR:-/Android/data/com.smartisanos.textboom/files/.boom}"
EXPECTED_NEW_OCR_PATH="${EXPECTED_NEW_OCR_PATH:-/sdcard/Android/data/com.smartisanos.textboom/files/.boom/imageboom.jpg}"
PATCH_DEAL_SAVE_BITMAP_RESULT="${PATCH_DEAL_SAVE_BITMAP_RESULT:-0}"
DELETE_LEGACY_CSOCR="${DELETE_LEGACY_CSOCR:-0}"
REMOVE_OCR_KEY="${REMOVE_OCR_KEY:-0}"
REMOVE_ARM64_LIBS="${REMOVE_ARM64_LIBS:-0}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-textboom-ppocr-preview-path-apk.sh

Builds an APK-only TextBoom candidate on top of the v0.41 PP-OCR runtime APK.
It keeps the stock-shell merge boundary and changes only classes2.dex by moving
FileUtils.OCR_IMAGE_DIR from the public /sdcard/.boom path to TextBoom's
external app-specific directory:

  /sdcard/Android/data/com.smartisanos.textboom/files/.boom

This is intended to fix stale result-page image previews caused by an old
root-owned /sdcard/.boom/imageboom.jpg while preserving the existing
OCR_IMAGE_PATH call sites, PP-OCR runtime dex/assets/libs, legacy CsOcr code,
and the v1/JAR stock-shell signature boundary.

Set DELETE_LEGACY_CSOCR=1 and REMOVE_OCR_KEY=1 for the follow-up deletion
candidate that removes TextBoom's old CsOcr/Intsig dependency and manifest key
after PP-OCR and preview saving have passed live.

Set REMOVE_ARM64_LIBS=1 for the ABI-control gate that removes APK-internal
lib/arm64-v8a entries while keeping the arm32 runtime path.

This script does not build a super image, touch a device, flash, reboot, erase
partitions, install packages, or modify /data.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
need_command() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

zip_has_prefix() {
  local apk="$1" prefix="$2"
  zipinfo -1 "$apk" | awk -v p="$prefix" 'index($0, p) == 1 {found = 1} END {exit !found}'
}

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

patch_textboom_smali() {
  "$PYTHON_BIN" - "$DECODED_DIR" "$OLD_OCR_DIR" "$NEW_OCR_DIR" "$PATCH_DEAL_SAVE_BITMAP_RESULT" "$DELETE_LEGACY_CSOCR" "$REMOVE_OCR_KEY" <<'PY'
from __future__ import annotations

import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
old_dir = sys.argv[2]
new_dir = sys.argv[3]
patch_deal_save = sys.argv[4] == "1"
delete_legacy_csocr = sys.argv[5] == "1"
remove_ocr_key = sys.argv[6] == "1"
file_utils = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "util" / "FileUtils.smali"
boom = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr" / "BoomOcrActivity.smali"
local_api = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr" / "LocalPpOcrApi.smali"
chip = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "words" / "BoomChipPage.smali"
manifest = root / "AndroidManifest.xml"

for path in (file_utils, boom, local_api, chip):
    if not path.exists():
        raise SystemExit(f"missing smali: {path}")
if not manifest.exists():
    raise SystemExit(f"missing manifest: {manifest}")

text = file_utils.read_text(encoding="utf-8")
old = f'    const-string v1, "{old_dir}"\n'
new = f'    const-string v1, "{new_dir}"\n'
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected one OCR_IMAGE_DIR literal match in FileUtils, found {count}")
file_utils.write_text(text.replace(old, new, 1), encoding="utf-8")

patched = file_utils.read_text(encoding="utf-8")
if old in patched:
    raise SystemExit("old OCR_IMAGE_DIR literal still present in FileUtils")
if new_dir not in patched:
    raise SystemExit("new OCR_IMAGE_DIR literal missing from FileUtils")

if patch_deal_save:
    boom_text = boom.read_text(encoding="utf-8")
    marker = (
        "    .line 616\n"
        "    iget-object v4, p0, Lcom/smartisanos/textboom/ocr/BoomOcrActivity;->mOcrApi:Lcom/smartisanos/textboom/ocr/IOcrApi;\n"
    )
    replacement = (
        "    const-string v0, \"imageboom.jpg\"\n\n"
        "    invoke-static {p1, v0}, Lcom/smartisanos/textboom/util/FileUtils;->saveBMtoLocal(Landroid/graphics/Bitmap;Ljava/lang/String;)Z\n\n"
        "    move-result v0\n\n"
        + marker
    )
    count = boom_text.count(marker)
    if count != 1:
        raise SystemExit(f"expected one dealSaveBitmapResult startOcr marker, found {count}")
    boom.write_text(boom_text.replace(marker, replacement, 1), encoding="utf-8")

if delete_legacy_csocr:
    boom_text = boom.read_text(encoding="utf-8")
    old_log = '    const-string v1, "CSOCR onError errorCode:"\n'
    new_log = '    const-string v1, "PPOCR onError errorCode:"\n'
    count = boom_text.count(old_log)
    if count != 1:
        raise SystemExit(f"expected one legacy CSOCR error log string, found {count}")
    boom.write_text(boom_text.replace(old_log, new_log, 1), encoding="utf-8")

    ocr_dir = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr"
    for name in (
        "CsOcr.smali",
        "CsOcr$1.smali",
        "-$$Lambda$CsOcr$TNVrMImp7_yy1JQ3YG2P6VfiUkI.smali",
        "-$$Lambda$CsOcr$n4Zm4iUpoJBOBke-cKEZPZcbTW4.smali",
    ):
        target = ocr_dir / name
        if not target.exists():
            raise SystemExit(f"missing legacy CsOcr file before delete: {target}")
        target.unlink()

    intsig_dir = root / "smali_classes2" / "com" / "intsig"
    if not intsig_dir.exists():
        raise SystemExit(f"missing legacy Intsig dir before delete: {intsig_dir}")
    shutil.rmtree(intsig_dir)

if remove_ocr_key:
    manifest_text = manifest.read_text(encoding="utf-8")
    lines = manifest_text.splitlines(keepends=True)
    kept = [line for line in lines if 'android:name="ocr_key"' not in line]
    if len(kept) != len(lines) - 1:
        raise SystemExit("expected exactly one manifest ocr_key metadata line to remove")
    manifest.write_text("".join(kept), encoding="utf-8")

boom_text = boom.read_text(encoding="utf-8", errors="replace")
local_api_text = local_api.read_text(encoding="utf-8", errors="replace")
chip_text = chip.read_text(encoding="utf-8", errors="replace")
for token in (
    "Lcom/smartisanos/textboom/util/FileUtils;->saveBMtoLocal",
    "Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;",
):
    if token not in boom_text:
        raise SystemExit(f"BoomOcrActivity missing expected runtime token: {token}")
if "Lcom/smartisax/textboom/ppocr/LocalPpOcrRuntime;->start" not in local_api_text:
    raise SystemExit("LocalPpOcrApi missing runtime start bridge")
if patch_deal_save:
    method_start = boom_text.index(".method private dealSaveBitmapResult")
    method_end = boom_text.index(".end method", method_start)
    method_body = boom_text[method_start:method_end]
    save_pos = method_body.find("FileUtils;->saveBMtoLocal")
    start_pos = method_body.find("IOcrApi;->startOcr")
    if save_pos < 0 or start_pos < 0 or save_pos > start_pos:
        raise SystemExit("dealSaveBitmapResult does not save preview before startOcr")
if not list(root.glob("smali_classes*/com/smartisax/textboom/ppocr/LocalPpOcrRuntime.smali")):
    raise SystemExit("LocalPpOcrRuntime smali missing")
for token in (
    "Lcom/smartisanos/textboom/util/FileUtils;->OCR_IMAGE_PATH",
    "Lcom/bumptech/glide/signature/StringSignature;",
):
    if token not in chip_text:
        raise SystemExit(f"BoomChipPage missing expected preview token: {token}")

if delete_legacy_csocr:
    if any(root.glob("smali_classes*/com/smartisanos/textboom/ocr/*CsOcr*.smali")):
        raise SystemExit("legacy CsOcr smali still present")
    if any(root.glob("smali_classes*/com/intsig/**")):
        raise SystemExit("legacy com.intsig smali still present")
    code_hits = []
    for smali_dir in root.glob("smali*"):
        if not smali_dir.is_dir():
            continue
        for path in smali_dir.rglob("*.smali"):
            rel = path.relative_to(root).as_posix()
            if rel.endswith("/R$string.smali"):
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for token in ("Lcom/intsig", "com/intsig", "CsOcr", "CSOCR"):
                if token in text:
                    code_hits.append(f"{rel}:{token}")
    if code_hits:
        raise SystemExit("legacy OCR code references remain: " + ", ".join(code_hits[:20]))
else:
    if not (root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr" / "CsOcr.smali").exists():
        raise SystemExit("legacy CsOcr unexpectedly removed")
    if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
        raise SystemExit("legacy com.intsig.csopen unexpectedly removed")

if remove_ocr_key:
    if 'android:name="ocr_key"' in manifest.read_text(encoding="utf-8", errors="replace"):
        raise SystemExit("manifest ocr_key metadata still present")
else:
    if 'android:name="ocr_key"' not in manifest.read_text(encoding="utf-8", errors="replace"):
        raise SystemExit("manifest ocr_key unexpectedly removed")

print("patched_textboom_preview_path=ok")
PY
}

merge_classes2_into_source_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-textboom-preview-path-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  cp "$SOURCE_APK" "${OUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" classes2.dex > "${tmp}/classes2.dex"
  if [ "$REMOVE_OCR_KEY" = "1" ]; then
    unzip -p "$REBUILT_UNSIGNED" AndroidManifest.xml > "${tmp}/AndroidManifest.xml"
  fi
  (
    cd "$tmp"
    if [ "$REMOVE_OCR_KEY" = "1" ]; then
      zip -q "${OUT_APK}.tmp" classes2.dex AndroidManifest.xml
    else
      zip -q "${OUT_APK}.tmp" classes2.dex
    fi
  )
  if [ "$REMOVE_ARM64_LIBS" = "1" ]; then
    zip_has_prefix "${OUT_APK}.tmp" 'lib/arm64-v8a/' \
      || die "source shell has no APK-internal arm64 libs to remove"
    zip -q -d "${OUT_APK}.tmp" 'lib/arm64-v8a/*' >/dev/null
    if zip_has_prefix "${OUT_APK}.tmp" 'lib/arm64-v8a/'; then
      die "APK-internal arm64 libs still present after removal"
    fi
  fi
  mv "${OUT_APK}.tmp" "$OUT_APK"
}

verify_zip_boundary() {
  "$PYTHON_BIN" - "$SOURCE_APK" "$OUT_APK" "$ZIP_REPORT" "$REMOVE_OCR_KEY" "$REMOVE_ARM64_LIBS" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1])
out = Path(sys.argv[2])
report = Path(sys.argv[3])
remove_ocr_key = sys.argv[4] == "1"
remove_arm64 = sys.argv[5] == "1"
allowed_changed = {"classes2.dex"}
if remove_ocr_key:
    allowed_changed.add("AndroidManifest.xml")

with zipfile.ZipFile(source) as a, zipfile.ZipFile(out) as b:
    names_a = set(a.namelist())
    names_b = set(b.namelist())
    removed = sorted(names_a - names_b)
    added = sorted(names_b - names_a)
    changed = sorted(name for name in names_a & names_b if a.read(name) != b.read(name))
    allowed_removed = []
    if remove_arm64:
        allowed_removed = sorted(name for name in names_a if name.startswith("lib/arm64-v8a/"))
        if not allowed_removed:
            raise SystemExit("source APK has no lib/arm64-v8a entries")
    if removed != allowed_removed:
        raise SystemExit(f"removed zip entries: {removed}")
    if added:
        raise SystemExit(f"unexpected added zip entries: {added}")
    if set(changed) != allowed_changed:
        raise SystemExit(f"unexpected changed entries: {changed}")
    report.write_text(
        "changed_entries=" + ",".join(changed) + "\n"
        + "removed_entries=" + ",".join(removed) + "\n",
        encoding="utf-8",
    )
print("zip_boundary=ok")
PY
}

verify_rebuilt_semantics() {
  local strings_file="${WORK_DIR}/classes2.strings"
  rm -rf "$VERIFY_DECODED_DIR"
  unzip -t "$OUT_APK" >/dev/null
  if [ "$REMOVE_ARM64_LIBS" = "1" ]; then
    if zip_has_prefix "$OUT_APK" 'lib/arm64-v8a/'; then
      die "OUT_APK still contains APK-internal arm64 libs"
    fi
  else
    zip_has_prefix "$OUT_APK" 'lib/arm64-v8a/' \
      || die "OUT_APK unexpectedly lacks APK-internal arm64 libs"
  fi
  unzip -p "$OUT_APK" classes2.dex | strings > "$strings_file"
  grep -q "$NEW_OCR_DIR" "$strings_file" || die "classes2.dex missing new OCR directory"
  if grep -Fxq "$OLD_OCR_DIR" "$strings_file"; then
    die "classes2.dex still contains old OCR directory"
  fi

  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$VERIFY_DECODED_DIR" "$OUT_APK" >/dev/null
  "$PYTHON_BIN" - "$VERIFY_DECODED_DIR" "$NEW_OCR_DIR" "$EXPECTED_NEW_OCR_PATH" "$PATCH_DEAL_SAVE_BITMAP_RESULT" "$DELETE_LEGACY_CSOCR" "$REMOVE_OCR_KEY" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
new_dir = sys.argv[2]
expected_path = sys.argv[3]
patch_deal_save = sys.argv[4] == "1"
delete_legacy_csocr = sys.argv[5] == "1"
remove_ocr_key = sys.argv[6] == "1"
file_utils = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "util" / "FileUtils.smali"
boom = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr" / "BoomOcrActivity.smali"
local_api = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr" / "LocalPpOcrApi.smali"
chip = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "words" / "BoomChipPage.smali"
manifest = root / "AndroidManifest.xml"
text = file_utils.read_text(encoding="utf-8", errors="replace")
if new_dir not in text:
    raise SystemExit("verified FileUtils missing new OCR dir")
if expected_path.split("/imageboom.jpg", 1)[0].split("/sdcard", 1)[-1] not in text:
    raise SystemExit("verified FileUtils cannot form expected app-specific OCR path")
boom_text = boom.read_text(encoding="utf-8", errors="replace")
local_api_text = local_api.read_text(encoding="utf-8", errors="replace")
chip_text = chip.read_text(encoding="utf-8", errors="replace")
if "LocalPpOcrApi" not in boom_text:
    raise SystemExit("verified BoomOcrActivity lost LocalPpOcrApi instantiation")
if "LocalPpOcrRuntime;->start" not in local_api_text:
    raise SystemExit("verified BoomOcrActivity lost PP-OCR runtime bridge")
if patch_deal_save:
    method_start = boom_text.index(".method private dealSaveBitmapResult")
    method_end = boom_text.index(".end method", method_start)
    method_body = boom_text[method_start:method_end]
    save_pos = method_body.find("FileUtils;->saveBMtoLocal")
    start_pos = method_body.find("IOcrApi;->startOcr")
    if save_pos < 0 or start_pos < 0 or save_pos > start_pos:
        raise SystemExit("verified dealSaveBitmapResult does not save preview before startOcr")
if not list(root.glob("smali_classes*/com/smartisax/textboom/ppocr/LocalPpOcrRuntime.smali")):
    raise SystemExit("verified LocalPpOcrRuntime smali missing")
if "FileUtils;->OCR_IMAGE_PATH" not in chip_text:
    raise SystemExit("verified BoomChipPage lost OCR_IMAGE_PATH preview loading")
if "StringSignature" not in chip_text:
    raise SystemExit("verified BoomChipPage lost Glide cache-busting signature")
if delete_legacy_csocr:
    if any(root.glob("smali_classes*/com/smartisanos/textboom/ocr/*CsOcr*.smali")):
        raise SystemExit("verified legacy CsOcr smali still present")
    if any(root.glob("smali_classes*/com/intsig/**")):
        raise SystemExit("verified legacy com.intsig smali still present")
    code_hits = []
    for smali_dir in root.glob("smali*"):
        if not smali_dir.is_dir():
            continue
        for path in smali_dir.rglob("*.smali"):
            rel = path.relative_to(root).as_posix()
            if rel.endswith("/R$string.smali"):
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for token in ("Lcom/intsig", "com/intsig", "CsOcr", "CSOCR"):
                if token in text:
                    code_hits.append(f"{rel}:{token}")
    if code_hits:
        raise SystemExit("verified legacy OCR code references remain: " + ", ".join(code_hits[:20]))
else:
    if not (root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr" / "CsOcr.smali").exists():
        raise SystemExit("verified legacy CsOcr unexpectedly removed")
    if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
        raise SystemExit("verified legacy com.intsig.csopen unexpectedly removed")

manifest_text = manifest.read_text(encoding="utf-8", errors="replace")
if remove_ocr_key:
    if 'android:name="ocr_key"' in manifest_text:
        raise SystemExit("verified manifest ocr_key metadata still present")
else:
    if 'android:name="ocr_key"' not in manifest_text:
        raise SystemExit("verified manifest ocr_key unexpectedly removed")
print("textboom_preview_path_semantics=ok")
PY
}

write_signature_report() {
  "$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"
  grep -q '^apk_sig_block_magic=absent$' "$SIG_REPORT" \
    || die "TextBoom v2/v3 signing-block boundary changed"
  grep -Eq 'digest error for (classes2.dex|AndroidManifest.xml)' "$SIG_REPORT" \
    || die "TextBoom signature boundary did not point at a changed stock-shell entry"
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
need_executable "$SIGCHECK"
need_command zip
need_command zipinfo
need_command unzip
need_command strings
require_hash "$SOURCE_APK" "$SOURCE_APK_SHA256"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT" "$ZIP_REPORT" "$MANIFEST" "$REBUILT_UNSIGNED"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding TextBoom PP-OCR runtime APK..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$SOURCE_APK" >/dev/null

echo "Patching TextBoom preview image path..."
patch_textboom_smali

echo "Rebuilding patched TextBoom as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging patched classes2.dex into source stock shell..."
merge_classes2_into_source_shell

echo "Verifying ZIP and preview-path semantics..."
verify_zip_boundary
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
  echo "old_ocr_image_dir=${OLD_OCR_DIR}"
  echo "new_ocr_image_dir=${NEW_OCR_DIR}"
  echo "expected_new_ocr_image_path=${EXPECTED_NEW_OCR_PATH}"
  echo "patch_deal_save_bitmap_result=${PATCH_DEAL_SAVE_BITMAP_RESULT}"
  if [ "$PATCH_DEAL_SAVE_BITMAP_RESULT" = "1" ]; then
    echo "patched_classes=FileUtils,BoomOcrActivity"
  else
    echo "patched_classes=FileUtils"
  fi
  if [ "$REMOVE_OCR_KEY" = "1" ]; then
    echo "changed_zip_entries=AndroidManifest.xml,classes2.dex"
  else
    echo "changed_zip_entries=classes2.dex"
  fi
  if [ "$REMOVE_ARM64_LIBS" = "1" ]; then
    echo "removed_zip_entries=lib/arm64-v8a/*"
  else
    echo "removed_zip_entries="
  fi
  echo "ppocr_runtime_bridge_retained=true"
  if [ "$DELETE_LEGACY_CSOCR" = "1" ]; then
    echo "legacy_csocr_retained=false"
    echo "legacy_intsig_csopen_retained=false"
  else
    echo "legacy_csocr_retained=true"
    echo "legacy_intsig_csopen_retained=true"
  fi
  if [ "$REMOVE_OCR_KEY" = "1" ]; then
    echo "legacy_ocr_key_retained=false"
  else
    echo "legacy_ocr_key_retained=true"
  fi
  echo "delete_legacy_csocr=${DELETE_LEGACY_CSOCR}"
  echo "remove_ocr_key=${REMOVE_OCR_KEY}"
  echo "remove_arm64_libs=${REMOVE_ARM64_LIBS}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$SOURCE_APK" "$REBUILT_UNSIGNED" "$OUT_APK" "$SIG_REPORT" "$ZIP_REPORT"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Signature report: ${SIG_REPORT}"
echo "ZIP report: ${ZIP_REPORT}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: APK-only artifact; no live flash authorization."
