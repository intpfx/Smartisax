#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SERIAL="${SERIAL:-bb12d264}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
TEXTBOOM_SOURCE_APK="${ROOT_DIR}/apks/textboom-live/TextBoom-live-v3.2.2-base.apk"

VARIANT="${VARIANT:-v0.41-textboom-ppocr-runtime-adapter}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
EXPECTED_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"

APK_MANIFEST="${ROOT_DIR}/hard-rom/build/apk/textboom-ppocr-runtime-adapter-apk-manifest.tsv"
APK_SIGNATURE_REPORT="${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-runtime-adapter.signature.txt"
APK_ZIP_BOUNDARY_REPORT="${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-runtime-adapter.zip-boundary.txt"
APK_DEX_BOUNDARY_REPORT="${ROOT_DIR}/hard-rom/build/apk/TextBoom-ppocr-runtime-adapter.dex-boundary.txt"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024

SIDEBAR_PATH="/system/priv-app/Sidebar/Sidebar.apk"
TEXTBOOM_PATH="/system/app/TextBoom/TextBoom.apk"
TEXTBOOM_LIB_ARM_DIR="/system/app/TextBoom/lib/arm"
TEXTBOOM_LIB_ARM64_DIR="/system/app/TextBoom/lib/arm64"
SYSTEM_WEBVIEW_PATH="/system/app/webview/webview.apk"
SMARTISAX_PATH="/system/app/SmartisaxShell/SmartisaxShell.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.41-textboom-ppocr-runtime-adapter.sh --offline-image
  tools/r2-verify-v0.41-textboom-ppocr-runtime-adapter.sh --read-only

Verifies the v0.41 TextBoom LocalPpOcrApi PP-OCRv6 runtime adapter candidate.
--offline-image does not touch a device. --read-only collects live state only:
it does not flash, reboot, write settings, clear package cache, install,
uninstall, erase partitions, or modify /data.
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
  "$PYTHON_BIN" "$AVBTOOL" info_image --image "$image" > "$info"
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

verify_textboom_runtime_apk_reports() {
  need_file "$APK_MANIFEST"
  need_file "$APK_SIGNATURE_REPORT"
  need_file "$APK_ZIP_BOUNDARY_REPORT"
  need_file "$APK_DEX_BOUNDARY_REPORT"
  grep -q '^model=PP-OCRv6_small$' "$APK_MANIFEST" || die "runtime APK manifest model mismatch"
  grep -q '^ort_android_version=1.21.1$' "$APK_MANIFEST" || die "runtime APK manifest ORT version mismatch"
  grep -q '^opencv_dependency=org.opencv:opencv:4.9.0$' "$APK_MANIFEST" || die "runtime APK manifest OpenCV dependency mismatch"
  grep -q '^runtime_dex_policy=no_stock_duplicate_classes_no_kotlin_or_textboom_ocr_classes$' "$APK_MANIFEST" || die "runtime APK manifest dex policy missing"
  grep -q '^apk_sig_block_magic=absent$' "$APK_SIGNATURE_REPORT" || die "TextBoom v2/v3 signing block state changed"
  grep -q '^keytool_status=1$' "$APK_SIGNATURE_REPORT" || die "TextBoom keytool digest-boundary status changed"
  grep -q 'SHA1 digest error for classes2.dex' "$APK_SIGNATURE_REPORT" || die "TextBoom signature boundary did not point at classes2.dex"
  grep -q '^jarsigner_status=0$' "$APK_SIGNATURE_REPORT" || die "TextBoom jarsigner status changed"
  grep -q '^changed_entries=classes2.dex$' "$APK_ZIP_BOUNDARY_REPORT" || die "runtime APK changed-entry boundary mismatch"
  grep -q '^added_runtime_dex=classes4.dex$' "$APK_ZIP_BOUNDARY_REPORT" || die "runtime APK classes4 boundary missing"
  grep -q '^runtime_dex_entries=classes4.dex$' "$APK_DEX_BOUNDARY_REPORT" || die "runtime dex entry mismatch"
  grep -q '^duplicate_class_count=0$' "$APK_DEX_BOUNDARY_REPORT" || die "runtime dex duplicate classes found"
  grep -q '^forbidden_runtime_descriptor_count=0$' "$APK_DEX_BOUNDARY_REPORT" || die "runtime dex forbidden classes found"
  grep -q '^required_runtime_descriptors=present$' "$APK_DEX_BOUNDARY_REPORT" || die "runtime dex required descriptors missing"
  echo "textboom_runtime_apk_reports=ok"
}

verify_textboom_payload_delta() {
  local apk="$1"
  need_file "$TEXTBOOM_SOURCE_APK"
  "$PYTHON_BIN" - "$TEXTBOOM_SOURCE_APK" "$apk" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
candidate = Path(sys.argv[2])
expected_added = {
    "classes4.dex",
    "assets/models/det/inference.onnx",
    "assets/models/rec/inference.onnx",
    "assets/models/rec/inference.yml",
    "lib/arm64-v8a/libc++_shared.so",
    "lib/arm64-v8a/libonnxruntime.so",
    "lib/arm64-v8a/libonnxruntime4j_jni.so",
    "lib/arm64-v8a/libopencv_java4.so",
}
expected_hashes = {
    "assets/models/det/inference.onnx": "b1a4f07289eda88d29239890b94ea2f9e29f5635a33ff6e165bb1b27dcea25fc",
    "assets/models/rec/inference.onnx": "7a10319171913a664e03b9f84bb159dbc1c7c397a2ff7a79d89287df64c64d4b",
    "assets/models/rec/inference.yml": "ab078671bb49f06228eadccd34f1bb501e157f7a047095ffb943ba81512c77d1",
    "lib/arm64-v8a/libc++_shared.so": "28e7a3a306d7fc222c62abe08741cfcba38c3f336216c4563726bf985ae3cfd6",
    "lib/arm64-v8a/libonnxruntime.so": "11ef853b751532dc827bd7799f557f9495e2ee7523b9b355753fc0344576bd5e",
    "lib/arm64-v8a/libonnxruntime4j_jni.so": "f657216254a2f88fcbd89c5e73a2f7ae5a8145d092f8700951aedba8e4a60ef2",
    "lib/arm64-v8a/libopencv_java4.so": "41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7",
}
with zipfile.ZipFile(stock) as a, zipfile.ZipFile(candidate) as b:
    names_a = set(a.namelist())
    names_b = set(b.namelist())
    removed = sorted(names_a - names_b)
    added = set(names_b - names_a)
    if removed:
        raise SystemExit(f"zip entries removed unexpectedly: {removed}")
    if added != expected_added:
        raise SystemExit(f"added payload set mismatch: added={sorted(added)} expected={sorted(expected_added)}")
    changed = [name for name in sorted(names_a) if a.read(name) != b.read(name)]
    if changed != ["classes2.dex"]:
        raise SystemExit(f"unexpected changed payloads: {changed}")
    for name, expected in expected_hashes.items():
        actual = hashlib.sha256(b.read(name)).hexdigest()
        if actual != expected:
            raise SystemExit(f"{name} hash mismatch: actual={actual} expected={expected}")
print("textboom_changed_payloads=classes2.dex_plus_classes4_assets_models_arm64_libs")
print("textboom_runtime_assets_and_libs=ok")
PY
}

verify_textboom_adapter_semantics() {
  local apk="$1" decoded="${WORK_DIR}/textboom-decoded" sig="${WORK_DIR}/textboom-signature.txt"
  rm -rf "$decoded"
  "$SIGCHECK" "$apk" > "$sig"
  grep -q '^apk_sig_block_magic=absent$' "$sig" || die "TextBoom v2/v3 signing block state changed"
  grep -q '^keytool_status=1$' "$sig" || die "TextBoom keytool digest-boundary status changed"
  grep -q 'SHA1 digest error for classes2.dex' "$sig" || die "TextBoom signature boundary did not point at classes2.dex"
  grep -q '^jarsigner_status=0$' "$sig" || die "TextBoom jarsigner status changed"

  verify_textboom_payload_delta "$apk"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$decoded" "$apk" >/dev/null
  "$PYTHON_BIN" - "$decoded" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
manifest = ET.parse(root / "AndroidManifest.xml").getroot()
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
if manifest.attrib.get("package") != "com.smartisanos.textboom":
    raise SystemExit("TextBoom package mismatch")

manifest_text = (root / "AndroidManifest.xml").read_text(encoding="utf-8", errors="replace")
if "ocr_key" not in manifest_text:
    raise SystemExit("legacy ocr_key unexpectedly removed before runtime gate")

ocr_dir = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr"
for name, label in {
    "BoomOcrActivity.smali": "BoomOcrActivity",
    "BoomAccessOcrActivity.smali": "BoomAccessOcrActivity",
}.items():
    text = (ocr_dir / name).read_text(encoding="utf-8", errors="replace")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;" in text:
        raise SystemExit(f"{label} still instantiates CsOcr")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in text:
        raise SystemExit(f"{label} missing LocalPpOcrApi instantiation")

adapter = ocr_dir / "LocalPpOcrApi.smali"
text = adapter.read_text(encoding="utf-8", errors="replace")
for token in (
    ".implements Lcom/smartisanos/textboom/ocr/IOcrApi;",
    "handleOcrResult(IILandroid/content/Intent;Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;)V",
    "startOcr(Landroid/app/Activity;Landroid/graphics/Bitmap;ILcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;Z)V",
    "Lcom/smartisax/textboom/ppocr/LocalPpOcrRuntime;->start(Landroid/app/Activity;Landroid/graphics/Bitmap;ILjava/lang/Object;Z)V",
):
    if token not in text:
        raise SystemExit(f"LocalPpOcrApi missing {token}")
if "onResultSuccess(Ljava/util/List;)V" in text:
    raise SystemExit("LocalPpOcrApi still looks like the v0.40 no-op adapter")

if not (ocr_dir / "CsOcr.smali").exists():
    raise SystemExit("legacy CsOcr unexpectedly removed before live runtime gate")
if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
    raise SystemExit("legacy com.intsig.csopen unexpectedly removed before live runtime gate")

required_runtime = [
    root / "smali_classes4" / "com" / "smartisax" / "textboom" / "ppocr" / "LocalPpOcrRuntime.smali",
    root / "smali_classes4" / "com" / "paddle" / "ocr" / "engine" / "OCREngine.smali",
    root / "smali_classes4" / "ai" / "onnxruntime" / "OrtEnvironment.smali",
    root / "smali_classes4" / "org" / "opencv" / "android" / "Utils.smali",
]
for path in required_runtime:
    if not path.exists():
        raise SystemExit(f"missing runtime class {path.relative_to(root)}")
for forbidden in (
    root / "smali_classes4" / "kotlin",
    root / "smali_classes4" / "kotlinx",
    root / "smali_classes4" / "com" / "smartisanos" / "textboom" / "ocr",
):
    if forbidden.exists():
        raise SystemExit(f"runtime dex contains forbidden package {forbidden.relative_to(root)}")

runtime = required_runtime[0].read_text(encoding="utf-8", errors="replace")
for token in (
    'DET_MODEL_ASSET:Ljava/lang/String; = "models/det/inference.onnx"',
    'REC_MODEL_ASSET:Ljava/lang/String; = "models/rec/inference.onnx"',
    'REC_CONFIG_ASSET:Ljava/lang/String; = "models/rec/inference.yml"',
    "CPU_THREAD_NUM:I = 0x4",
    "ERROR_INIT:I = -0x65",
    "ERROR_BITMAP:I = -0x66",
    "ERROR_RUNTIME:I = -0x67",
    "Lcom/paddle/ocr/engine/OCREngine;",
    "Lcom/paddle/ocr/util/OpenCVUtils;->init",
):
    if token not in runtime:
        raise SystemExit(f"LocalPpOcrRuntime missing {token}")

print("textboom_ppocr_runtime_adapter_semantics=ok")
PY
}

verify_sidebar_semantics() {
  local apk="$1" decoded="${WORK_DIR}/sidebar-decoded" sig="${WORK_DIR}/sidebar-signature.txt"
  rm -rf "$decoded"
  "$SIGCHECK" "$apk" > "$sig"
  grep -q '^apk_sig_block_magic=present$' "$sig" || die "retained Sidebar v2/v3 signing block missing"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$decoded" "$apk" >/dev/null
  "$PYTHON_BIN" - "$decoded" <<'PY'
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
    raise SystemExit("Sidebar package mismatch")
application = next((child for child in manifest if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("Sidebar manifest has no application")
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
        raise SystemExit(f"Sidebar manifest still contains {token}")

for path in (
    root / "smali/com/smartisanos/sidebar/open/font",
    root / "smali/com/intsig/csopen",
    root / "smali/com/smartisanos/sidebar/toparea/view/IdentifyFontView.smali",
):
    if path.exists():
        raise SystemExit(f"deleted Sidebar font-OCR path still present: {path.relative_to(root)}")

print("sidebar_font_ocr_code_deleted_retained=ok")
PY
}

verify_textboom_runtime_libs_in_image() {
  local image="$1" base expected dumped actual count=0
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM_DIR" || die "TextBoom lib/arm missing"
  debugfs_path_exists "$image" "$TEXTBOOM_LIB_ARM64_DIR" || die "TextBoom lib/arm64 missing"
  while read -r base expected; do
    [ -n "$base" ] || continue
    dumped="${WORK_DIR}/textboom-runtime-image-${base}"
    debugfs_path_exists "$image" "${TEXTBOOM_LIB_ARM64_DIR}/${base}" || die "missing TextBoom runtime image lib: ${base}"
    debugfs_dump "$image" "${TEXTBOOM_LIB_ARM64_DIR}/${base}" "$dumped"
    actual="$(sha256_one "$dumped")"
    [ "$actual" = "$expected" ] || die "TextBoom runtime lib hash mismatch: ${base} actual=${actual} expected=${expected}"
    printf 'textboom_runtime_lib\t%s\tsha256=%s\t%s/%s\n' "$base" "$actual" "$TEXTBOOM_LIB_ARM64_DIR" "$base"
    count=$((count + 1))
  done <<'EOF'
libc++_shared.so 28e7a3a306d7fc222c62abe08741cfcba38c3f336216c4563726bf985ae3cfd6
libonnxruntime.so 11ef853b751532dc827bd7799f557f9495e2ee7523b9b355753fc0344576bd5e
libonnxruntime4j_jni.so f657216254a2f88fcbd89c5e73a2f7ae5a8145d092f8700951aedba8e4a60ef2
libopencv_java4.so 41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7
EOF
  [ "$count" -eq 4 ] || die "TextBoom runtime lib count mismatch: ${count}"
  echo "textboom_runtime_libs_in_image=ok count=${count}"
}

verify_offline_image() {
  local ts report sidebar_dump textboom_dump
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
    check_manifest_hash "textboom_runtime_adapter_apk" "$(manifest_value textboom_adapter_apk)" "textboom_adapter_apk_sha256"
    echo
    echo "## image sizes and FEC"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b size mismatch"
    [ "$(size_bytes "$EXPECTED_PRODUCT_B_IMG")" -eq "$PRODUCT_B_PARTITION_SIZE" ] || die "product_b size mismatch"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec system_b "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE" "$SYSTEM_B_EXT4_SIZE"
    verify_avb_fec product_b "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE" "$PRODUCT_B_EXT4_SIZE"
    echo
    echo "## APK builder evidence and TextBoom runtime semantics"
    verify_textboom_runtime_apk_reports
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_PATH" "textboom_apk_sha256" "textboom"
    textboom_dump="${WORK_DIR}/textboom.apk"
    verify_textboom_adapter_semantics "$textboom_dump"
    verify_textboom_runtime_libs_in_image "$EXPECTED_SYSTEM_B_IMG"
    echo
    echo "## retained system components"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$SIDEBAR_PATH" "sidebar_apk_sha256" "sidebar"
    sidebar_dump="${WORK_DIR}/sidebar.apk"
    verify_sidebar_semantics "$sidebar_dump"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_PATH" "system_webview_apk_sha256" "system-webview"
    verify_apk_hash "$EXPECTED_SYSTEM_B_IMG" "$SMARTISAX_PATH" "smartisax_apk_sha256" "smartisax"
    debugfs_path_exists "$EXPECTED_SYSTEM_B_IMG" "$TEXTBOOM_LIB_ARM_DIR" || die "TextBoom lib/arm missing"
    echo "textboom_lib_arm_retained=ok"
    echo
    echo "result=PASS_OFFLINE_IMAGE_V041_TEXTBOOM_PPOCR_RUNTIME_ADAPTER"
  } > "$report"
  cat "$report"
  echo "Report: $report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_shell() {
  adb -s "$SERIAL" shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@" 2>&1 | tr -d '\r'
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

require_live_literal_hash() {
  local label="$1" path="$2" expected="$3" actual
  actual="$(live_sha256 "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected} path=${path}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_read_only_device() {
  local ts report slot boot bootanim keyguard_line textboom_path webview_path smartisax_path root_id pkg_flags
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
    adb_available || die "adb device ${SERIAL} is not online"
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
    echo "## package paths and flags"
    adb_shell 'for pkg in com.smartisanos.textboom com.smartisanos.sidebar com.android.webview com.android.browser com.smartisax.browser; do
      echo "### ${pkg}"
      pm path "$pkg" 2>/dev/null || true
      dumpsys package "$pkg" 2>/dev/null | grep -E "Package \\[|versionCode=|versionName=|codePath=|resourcePath=|pkgFlags=|privateFlags=|enabled=|stopped=|hidden=|suspended=|UPDATED_SYSTEM_APP" | sed -n "1,80p"
    done'
    textboom_path="$(adb_shell 'pm path com.smartisanos.textboom 2>/dev/null | tr "\n" " "' | tail -n 1)"
    webview_path="$(adb_shell 'pm path com.android.webview 2>/dev/null | tr "\n" " "' | tail -n 1)"
    smartisax_path="$(adb_shell 'pm path com.smartisax.browser 2>/dev/null | tr "\n" " "' | tail -n 1)"
    [[ "$textboom_path" == *"/system/app/TextBoom/TextBoom.apk"* ]] || die "TextBoom not served from system"
    [[ "$webview_path" == *"/system/app/webview/webview.apk"* ]] || die "WebView not served from system"
    [[ "$smartisax_path" == *"/system/app/SmartisaxShell/SmartisaxShell.apk"* ]] || die "Smartisax not served from system"
    pkg_flags="$(adb_shell 'dumpsys package com.smartisanos.textboom 2>/dev/null | grep -E "UPDATED_SYSTEM_APP|codePath=|resourcePath=" | sed -n "1,40p" || true')"
    printf '%s\n' "$pkg_flags"
    if grep -q 'UPDATED_SYSTEM_APP' <<<"$pkg_flags"; then
      die "TextBoom still has UPDATED_SYSTEM_APP shadow"
    fi
    echo
    echo "## live hashes"
    require_live_hash "textboom" "$TEXTBOOM_PATH" "textboom_apk_sha256"
    require_live_hash "sidebar" "$SIDEBAR_PATH" "sidebar_apk_sha256"
    require_live_hash "system-webview" "$SYSTEM_WEBVIEW_PATH" "system_webview_apk_sha256"
    require_live_hash "smartisax" "$SMARTISAX_PATH" "smartisax_apk_sha256"
    require_live_literal_hash "textboom-lib-libc++_shared.so" "${TEXTBOOM_LIB_ARM64_DIR}/libc++_shared.so" "28e7a3a306d7fc222c62abe08741cfcba38c3f336216c4563726bf985ae3cfd6"
    require_live_literal_hash "textboom-lib-libonnxruntime.so" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime.so" "11ef853b751532dc827bd7799f557f9495e2ee7523b9b355753fc0344576bd5e"
    require_live_literal_hash "textboom-lib-libonnxruntime4j_jni.so" "${TEXTBOOM_LIB_ARM64_DIR}/libonnxruntime4j_jni.so" "f657216254a2f88fcbd89c5e73a2f7ae5a8145d092f8700951aedba8e4a60ef2"
    require_live_literal_hash "textboom-lib-libopencv_java4.so" "${TEXTBOOM_LIB_ARM64_DIR}/libopencv_java4.so" "41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7"
    echo
    echo "## retained runtime surface"
    adb_shell 'ls -ldZ /system/app/TextBoom/lib/arm /system/app/TextBoom/lib/arm64 /system/priv-app/Sidebar /system/app/webview /system/app/SmartisaxShell 2>/dev/null || true'
    adb_shell 'ls -lZ /system/app/TextBoom/lib/arm64 2>/dev/null || true'
    adb_shell 'cmd package resolve-activity --brief -a smartisanos.intent.action.BOOM_FONT 2>&1 || true'
    keyguard_line="$(adb_shell 'dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen" | sed -n "1,80p" || true')"
    printf '%s\n' "$keyguard_line"
    if grep -Eq 'isKeyguardShowing=true|mShowingLockscreen=true' <<<"$keyguard_line"; then
      die "keyguard still showing"
    fi
    echo
    echo "result=PASS_READ_ONLY_V041_TEXTBOOM_PPOCR_RUNTIME_ADAPTER"
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
  need_file "$TEXTBOOM_SOURCE_APK"
  need_executable "$SIGCHECK"
  verify_offline_image
fi
