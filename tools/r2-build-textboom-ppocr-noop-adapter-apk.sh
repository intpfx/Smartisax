#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
SOURCE_APK="${SOURCE_APK:-${ROOT_DIR}/apks/textboom-live/TextBoom-live-v3.2.2-base.apk}"
SOURCE_APK_SHA256="52df3deb5315baf41b9f5476a122ce9782fa58f74076d1d4a9c060c9c506873c"

VARIANT="${VARIANT:-v0.40-textboom-ppocr-noop-adapter}"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/textboom-ppocr-noop-adapter-apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
DECODED_DIR="${WORK_DIR}/decoded"
REBUILT_UNSIGNED="${WORK_DIR}/TextBoom-ppocr-noop-adapter-rebuilt-unsigned.apk"
OUT_APK="${OUT_APK:-${OUT_DIR}/TextBoom-ppocr-noop-adapter.apk}"
SIG_REPORT="${OUT_APK%.apk}.signature.txt"
MANIFEST="${OUT_DIR}/textboom-ppocr-noop-adapter-apk-manifest.tsv"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-textboom-ppocr-noop-adapter-apk.sh

Builds an APK-only TextBoom candidate for the PP-OCR migration gate. It keeps
the stock TextBoom APK shell and all legacy CsOcr/CamScanner code present, but
changes the two concrete IOcrApi instantiation sites to LocalPpOcrApi:

  - BoomOcrActivity.initView()
  - BoomAccessOcrActivity.initOcr()

LocalPpOcrApi is a no-op shell that implements IOcrApi and returns an empty OCR
result list. This script does not build a super image, touch a device, flash,
reboot, erase partitions, install packages, or modify /data.
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
  "$PYTHON_BIN" - "$DECODED_DIR" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
ocr_dir = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr"
boom = ocr_dir / "BoomOcrActivity.smali"
access = ocr_dir / "BoomAccessOcrActivity.smali"
adapter = ocr_dir / "LocalPpOcrApi.smali"

for path in (boom, access):
    if not path.exists():
        raise SystemExit(f"missing smali: {path}")

def replace_exact(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

replace_exact(
    boom,
    """    .line 110
    new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;

    iget-object v1, p0, Lcom/smartisanos/textboom/ocr/BoomOcrActivity;->mContext:Landroid/content/Context;

    invoke-direct {v0, v1}, Lcom/smartisanos/textboom/ocr/CsOcr;-><init>(Landroid/content/Context;)V
""",
    """    .line 110
    new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;

    iget-object v1, p0, Lcom/smartisanos/textboom/ocr/BoomOcrActivity;->mContext:Landroid/content/Context;

    invoke-direct {v0, v1}, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;-><init>(Landroid/content/Context;)V
""",
    "BoomOcrActivity.initView CsOcr constructor",
)

replace_exact(
    access,
    """    .line 131
    new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;

    invoke-direct {v0, p0}, Lcom/smartisanos/textboom/ocr/CsOcr;-><init>(Landroid/content/Context;)V
""",
    """    .line 131
    new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;

    invoke-direct {v0, p0}, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;-><init>(Landroid/content/Context;)V
""",
    "BoomAccessOcrActivity.initOcr CsOcr constructor",
)

adapter.write_text(
    """.class public Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;
.super Ljava/lang/Object;
.source "LocalPpOcrApi.java"
.implements Lcom/smartisanos/textboom/ocr/IOcrApi;


# direct methods
.method public constructor <init>(Landroid/content/Context;)V
    .locals 0
    .param p1, "context"    # Landroid/content/Context;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public handleOcrResult(IILandroid/content/Intent;Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;)V
    .locals 0
    .param p1, "requestCode"    # I
    .param p2, "resultCode"    # I
    .param p3, "data"    # Landroid/content/Intent;
    .param p4, "listener"    # Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;

    return-void
.end method

.method public startOcr(Landroid/app/Activity;Landroid/graphics/Bitmap;ILcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;Z)V
    .locals 1
    .param p1, "activity"    # Landroid/app/Activity;
    .param p2, "bitmap"    # Landroid/graphics/Bitmap;
    .param p3, "language"    # I
    .param p4, "listener"    # Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;
    .param p5, "fromFloat"    # Z

    if-eqz p4, :cond_0

    new-instance v0, Ljava/util/ArrayList;

    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V

    invoke-interface {p4, v0}, Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;->onResultSuccess(Ljava/util/List;)V

    :cond_0
    return-void
.end method
""",
    encoding="utf-8",
)

for path, label in ((boom, "BoomOcrActivity"), (access, "BoomAccessOcrActivity")):
    text = path.read_text(encoding="utf-8")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;" in text:
        raise SystemExit(f"{label} still instantiates CsOcr")
    if "Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in text:
        raise SystemExit(f"{label} missing LocalPpOcrApi")

if not (ocr_dir / "CsOcr.smali").exists():
    raise SystemExit("CsOcr was unexpectedly removed")
if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
    raise SystemExit("TextBoom local com.intsig.csopen SDK was unexpectedly removed")

print("patched_textboom_instantiation=ok")
PY
}

merge_classes2_into_stock_shell() {
  local tmp rebuilt_hash out_hash
  tmp="$(mktemp -d "/tmp/r2-textboom-ppocr-noop-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  cp "$SOURCE_APK" "${OUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" classes2.dex > "${tmp}/classes2.dex"
  (
    cd "$tmp"
    zip -q "${OUT_APK}.tmp" classes2.dex
  )

  rebuilt_hash="$(unzip -p "$REBUILT_UNSIGNED" classes2.dex | shasum -a 256 | awk '{print $1}')"
  out_hash="$(unzip -p "${OUT_APK}.tmp" classes2.dex | shasum -a 256 | awk '{print $1}')"
  [ "$rebuilt_hash" = "$out_hash" ] || die "merged classes2.dex hash mismatch"

  mv "${OUT_APK}.tmp" "$OUT_APK"
}

verify_only_classes2_payload_changed() {
  "$PYTHON_BIN" - "$SOURCE_APK" "$OUT_APK" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
out = Path(sys.argv[2])
allowed = {"classes2.dex"}

with zipfile.ZipFile(stock) as a, zipfile.ZipFile(out) as b:
    names_a = set(a.namelist())
    names_b = set(b.namelist())
    if names_a != names_b:
        raise SystemExit(f"zip entry set changed: added={sorted(names_b-names_a)} removed={sorted(names_a-names_b)}")
    changed = []
    for name in sorted(names_a):
        if a.read(name) != b.read(name):
            changed.append(name)
    if set(changed) != allowed:
        raise SystemExit(f"unexpected changed payloads: {changed}")

print("changed_payloads=classes2.dex")
PY
}

verify_rebuilt_semantics() {
  local verify_decode="${WORK_DIR}/verify-decoded" strings_file="${WORK_DIR}/classes2.strings"
  rm -rf "$verify_decode"
  unzip -t "$OUT_APK" >/dev/null
  unzip -p "$OUT_APK" classes2.dex | strings > "$strings_file"
  grep -q 'LocalPpOcrApi' "$strings_file" \
    || die "merged classes2.dex missing LocalPpOcrApi"
  grep -q 'onResultSuccess' "$strings_file" \
    || die "merged classes2.dex missing IOcrApi success callback"

  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$verify_decode" "$OUT_APK" >/dev/null
  "$PYTHON_BIN" - "$verify_decode" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
ocr_dir = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr"
checks = {
    "BoomOcrActivity.smali": "BoomOcrActivity",
    "BoomAccessOcrActivity.smali": "BoomAccessOcrActivity",
}
for name, label in checks.items():
    text = (ocr_dir / name).read_text(encoding="utf-8")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;" in text:
        raise SystemExit(f"{label} still instantiates CsOcr")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in text:
        raise SystemExit(f"{label} missing LocalPpOcrApi instantiation")
adapter = ocr_dir / "LocalPpOcrApi.smali"
text = adapter.read_text(encoding="utf-8")
for token in (
    ".implements Lcom/smartisanos/textboom/ocr/IOcrApi;",
    "Ljava/util/ArrayList;",
    "onResultSuccess(Ljava/util/List;)V",
):
    if token not in text:
        raise SystemExit(f"LocalPpOcrApi missing {token}")
if not (ocr_dir / "CsOcr.smali").exists():
    raise SystemExit("CsOcr unexpectedly removed")
if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
    raise SystemExit("com.intsig.csopen unexpectedly removed")
print("textboom_ppocr_noop_semantics=ok")
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

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$SOURCE_APK"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"
need_command zip
need_command unzip
need_command strings
require_hash "$SOURCE_APK" "$SOURCE_APK_SHA256"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT" "$MANIFEST" "$REBUILT_UNSIGNED"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding TextBoom..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$SOURCE_APK" >/dev/null

echo "Patching TextBoom IOcrApi instantiation to LocalPpOcrApi no-op..."
patch_textboom_smali

echo "Rebuilding patched TextBoom as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging patched classes2.dex into stock TextBoom shell..."
merge_classes2_into_stock_shell

echo "Verifying changed payload boundary and no-op semantics..."
verify_only_classes2_payload_changed
verify_rebuilt_semantics

echo "Writing signature boundary report..."
"$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"
grep -q '^apk_sig_block_magic=absent$' "$SIG_REPORT" \
  || die "TextBoom v2/v3 signing-block boundary changed"
grep -q 'digest error for classes2.dex' "$SIG_REPORT" \
  || die "TextBoom signature boundary did not point at classes2.dex"

{
  echo "variant=${VARIANT}"
  echo "source_apk=${SOURCE_APK}"
  echo "source_apk_sha256=${SOURCE_APK_SHA256}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "out_apk=${OUT_APK}"
  echo "out_apk_sha256=$(sha256_one "$OUT_APK")"
  echo "signature_report=${SIG_REPORT}"
  echo "changed_payloads=classes2.dex"
  echo "adapter=LocalPpOcrApi"
  echo "adapter_behavior=noop_success_empty_list"
  echo "patched_entrypoints=BoomOcrActivity.initView,BoomAccessOcrActivity.initOcr"
  echo "legacy_csocr_retained=true"
  echo "legacy_intsig_csopen_retained=true"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$SOURCE_APK" "$REBUILT_UNSIGNED" "$OUT_APK" "$SIG_REPORT"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Signature report: ${SIG_REPORT}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: APK-only artifact; no live flash authorization."
