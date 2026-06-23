#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

APP_DIR="${ROOT_DIR}/apps/TextBoomOnnxSmokeBench"
BUILD_DIR="${ROOT_DIR}/hard-rom/build/textboom-onnx-smoke-bench"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/TextBoomOnnxSmokeBench.apk"
MANIFEST="${OUT_DIR}/TextBoomOnnxSmokeBench.SHA256SUMS.txt"
KEYSTORE="${ROOT_DIR}/hard-rom/keys/smartisax_apk.jks"
KEY_ALIAS="smartisax-apk"
KEY_PASS="SmartisaxApk2026"
PACKAGE="com.smartisax.ocrbench.onnx"
VERSION_NAME="0.1.1"
VERSION_CODE="2"
ABI="arm64-v8a"

ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-30/android.jar"
AAPT="${ANDROID_SDK_ROOT}/build-tools/35.0.1/aapt"
AAPT2="${ANDROID_SDK_ROOT}/build-tools/35.0.1/aapt2"
APKSIGNER="${ANDROID_SDK_ROOT}/build-tools/35.0.1/apksigner"
D8="${ANDROID_SDK_ROOT}/build-tools/35.0.1/d8"
ZIPALIGN="${ANDROID_SDK_ROOT}/build-tools/35.0.1/zipalign"
JAVAC="${JAVA_HOME}/bin/javac"
KEYTOOL="${JAVA_HOME}/bin/keytool"

ORT_ANDROID_VERSION="${ORT_ANDROID_VERSION:-1.26.0}"
ORT_WEB_VERSION="${ORT_WEB_VERSION:-1.27.0}"
ORT_AAR="${ORT_AAR:-${ROOT_DIR}/third_party/_downloads/onnxruntime/android/onnxruntime-android-${ORT_ANDROID_VERSION}.aar}"
ORT_WEB_DIST="${ORT_WEB_DIST:-${ROOT_DIR}/third_party/_downloads/onnxruntime/web/node_modules/onnxruntime-web/dist}"
ONNX_ROOT="${PPOCRV6_ONNX_ROOT:-${ROOT_DIR}/hard-rom/build/ppocr-runtime/onnx}"

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

need_file "${APP_DIR}/AndroidManifest.xml"
need_file "$ANDROID_JAR"
need_file "$ORT_AAR"
need_file "${ORT_WEB_DIST}/ort.webgpu.min.js"
need_file "${ONNX_ROOT}/PP-OCRv6_tiny_det/model.onnx"
need_file "${ONNX_ROOT}/PP-OCRv6_tiny_rec/model.onnx"
need_executable "$AAPT"
need_executable "$AAPT2"
need_executable "$APKSIGNER"
need_executable "$D8"
need_executable "$ZIPALIGN"
need_executable "$JAVAC"
need_executable "$KEYTOOL"

RES_ZIP="${BUILD_DIR}/resources.zip"
GEN_DIR="${BUILD_DIR}/generated"
CLASSES_DIR="${BUILD_DIR}/classes"
DEX_DIR="${BUILD_DIR}/dex"
AAR_DIR="${BUILD_DIR}/ort-aar"
NATIVE_PACKAGE_DIR="${BUILD_DIR}/native-package"
ASSET_PACKAGE_DIR="${BUILD_DIR}/asset-package"
RES_APK="${BUILD_DIR}/TextBoomOnnxSmokeBench-res.apk"
UNSIGNED_APK="${BUILD_DIR}/TextBoomOnnxSmokeBench-unsigned.apk"
ALIGNED_UNSIGNED_APK="${BUILD_DIR}/TextBoomOnnxSmokeBench-unsigned-aligned.apk"
VERIFY_REPORT="${OUT_DIR}/TextBoomOnnxSmokeBench.apksigner.txt"
BADGING_REPORT="${OUT_DIR}/TextBoomOnnxSmokeBench.badging.txt"
ARS_REPORT="${OUT_DIR}/TextBoomOnnxSmokeBench.zip-layout.txt"

mkdir -p "$OUT_DIR" "${ROOT_DIR}/hard-rom/keys"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$GEN_DIR" "$CLASSES_DIR" "$DEX_DIR" "$AAR_DIR" "$NATIVE_PACKAGE_DIR" "$ASSET_PACKAGE_DIR"
rm -f "$OUT_APK" "$MANIFEST" "$VERIFY_REPORT" "$BADGING_REPORT" "$ARS_REPORT"

unzip -q "$ORT_AAR" classes.jar "jni/${ABI}/libonnxruntime.so" "jni/${ABI}/libonnxruntime4j_jni.so" -d "$AAR_DIR"
ORT_CLASSES_JAR="${AAR_DIR}/classes.jar"
need_file "$ORT_CLASSES_JAR"

mkdir -p "${NATIVE_PACKAGE_DIR}/lib/${ABI}"
cp "${AAR_DIR}/jni/${ABI}/libonnxruntime.so" "${NATIVE_PACKAGE_DIR}/lib/${ABI}/"
cp "${AAR_DIR}/jni/${ABI}/libonnxruntime4j_jni.so" "${NATIVE_PACKAGE_DIR}/lib/${ABI}/"

mkdir -p "${ASSET_PACKAGE_DIR}/assets/onnx/models" "${ASSET_PACKAGE_DIR}/assets/web/ort" "${ASSET_PACKAGE_DIR}/assets/web/models"
cp "${ONNX_ROOT}/PP-OCRv6_tiny_det/model.onnx" "${ASSET_PACKAGE_DIR}/assets/onnx/models/PP-OCRv6_tiny_det.onnx"
cp "${ONNX_ROOT}/PP-OCRv6_tiny_rec/model.onnx" "${ASSET_PACKAGE_DIR}/assets/onnx/models/PP-OCRv6_tiny_rec.onnx"
cp "${ONNX_ROOT}/PP-OCRv6_tiny_det/model.onnx" "${ASSET_PACKAGE_DIR}/assets/web/models/PP-OCRv6_tiny_det.onnx"
cp "${ONNX_ROOT}/PP-OCRv6_tiny_rec/model.onnx" "${ASSET_PACKAGE_DIR}/assets/web/models/PP-OCRv6_tiny_rec.onnx"
cp "${APP_DIR}/assets-src/web/index.html" "${ASSET_PACKAGE_DIR}/assets/web/index.html"
cp "${APP_DIR}/assets-src/web/smoke.js" "${ASSET_PACKAGE_DIR}/assets/web/smoke.js"
cp "${ORT_WEB_DIST}/ort.webgpu.min.js" "${ASSET_PACKAGE_DIR}/assets/web/ort/"
find "$ORT_WEB_DIST" -maxdepth 1 -type f -name 'ort-wasm-simd-threaded.*' -exec cp {} "${ASSET_PACKAGE_DIR}/assets/web/ort/" \;

"$AAPT2" compile --dir "${APP_DIR}/res" -o "$RES_ZIP"
"$AAPT2" link \
  -o "$RES_APK" \
  --manifest "${APP_DIR}/AndroidManifest.xml" \
  -I "$ANDROID_JAR" \
  --java "$GEN_DIR" \
  --min-sdk-version 30 \
  --target-sdk-version 30 \
  --version-code "$VERSION_CODE" \
  --version-name "$VERSION_NAME" \
  -0 arsc \
  "$RES_ZIP"

find "${APP_DIR}/src" "$GEN_DIR" -name '*.java' | sort > "${BUILD_DIR}/java-sources.txt"
[ -s "${BUILD_DIR}/java-sources.txt" ] || die "no Java sources found"

"$JAVAC" \
  -source 8 \
  -target 8 \
  -encoding UTF-8 \
  -classpath "${ANDROID_JAR}:${ORT_CLASSES_JAR}" \
  -d "$CLASSES_DIR" \
  @"${BUILD_DIR}/java-sources.txt"

class_files=()
while IFS= read -r class_file; do
  class_files+=("$class_file")
done < <(find "$CLASSES_DIR" -name '*.class' | sort)
[ "${#class_files[@]}" -gt 0 ] || die "javac produced no class files"

"$D8" \
  --min-api 30 \
  --lib "$ANDROID_JAR" \
  --output "$DEX_DIR" \
  "$ORT_CLASSES_JAR" \
  "${class_files[@]}"

need_file "${DEX_DIR}/classes.dex"
cp "$RES_APK" "$UNSIGNED_APK"
(
  cd "$DEX_DIR"
  zip -q "$UNSIGNED_APK" classes.dex
)
(
  cd "$NATIVE_PACKAGE_DIR"
  zip -q -r "$UNSIGNED_APK" lib
)
(
  cd "$ASSET_PACKAGE_DIR"
  zip -q -r "$UNSIGNED_APK" assets
)

"$ZIPALIGN" -f -p 4 "$UNSIGNED_APK" "$ALIGNED_UNSIGNED_APK"

if [ ! -f "$KEYSTORE" ]; then
  "$KEYTOOL" -genkeypair \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" \
    -keypass "$KEY_PASS" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 7300 \
    -dname 'CN=Smartisax APK, OU=ROM, O=Smartisax, L=Beijing, ST=Beijing, C=CN'
  chmod 600 "$KEYSTORE"
fi

"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:${KEY_PASS}" \
  --key-pass "pass:${KEY_PASS}" \
  --min-sdk-version 30 \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  --out "$OUT_APK" \
  "$ALIGNED_UNSIGNED_APK"

"$APKSIGNER" verify --verbose --print-certs "$OUT_APK" > "$VERIFY_REPORT"
"$ZIPALIGN" -c -p 4 "$OUT_APK" >/dev/null
unzip -t "$OUT_APK" >/dev/null
"$AAPT" dump badging "$OUT_APK" > "$BADGING_REPORT"

python3 - "$OUT_APK" "$ARS_REPORT" <<'PY'
import struct
import sys
import zipfile

apk = sys.argv[1]
report = sys.argv[2]
lines = []
with open(apk, "rb") as fp, zipfile.ZipFile(apk) as zf:
    for name in ("AndroidManifest.xml", "resources.arsc", "classes.dex"):
        info = zf.getinfo(name)
        fp.seek(info.header_offset)
        header = fp.read(30)
        if len(header) != 30:
            raise SystemExit(f"truncated ZIP local header for {name}")
        sig, _ver, _flag, method, *_rest, name_len, extra_len = struct.unpack("<IHHHHHIIIHH", header)
        if sig != 0x04034B50:
            raise SystemExit(f"bad ZIP local header signature for {name}")
        data_offset = info.header_offset + 30 + name_len + extra_len
        lines.append(
            f"{name}\tmethod={info.compress_type}\tlocal_method={method}\t"
            f"data_offset={data_offset}\taligned4={data_offset % 4 == 0}\tsize={info.file_size}"
        )
        if name == "resources.arsc":
            if info.compress_type != zipfile.ZIP_STORED or method != zipfile.ZIP_STORED:
                raise SystemExit("resources.arsc is not STORED")
            if data_offset % 4 != 0:
                raise SystemExit(f"resources.arsc data offset is not 4-byte aligned: {data_offset}")
open(report, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY

{
  echo "apk=${OUT_APK}"
  echo "source=${APP_DIR}"
  echo "package=${PACKAGE}"
  echo "versionName=${VERSION_NAME}"
  echo "versionCode=${VERSION_CODE}"
  echo "abi=${ABI}"
  echo "ort_android_version=${ORT_ANDROID_VERSION}"
  echo "ort_android_aar=${ORT_AAR}"
  echo "ort_web_version=${ORT_WEB_VERSION}"
  echo "ort_web_dist=${ORT_WEB_DIST}"
  echo "onnx_root=${ONNX_ROOT}"
  echo "signed_by=${KEYSTORE}"
  echo "verify_report=${VERIFY_REPORT}"
  echo "badging_report=${BADGING_REPORT}"
  echo "zip_layout_report=${ARS_REPORT}"
  echo "default_device_result=/sdcard/Android/data/${PACKAGE}/files/results/last-result.json"
  echo "native_start=adb shell am start -n ${PACKAGE}/.MainActivity --es mode native"
  echo "web_start=adb shell am start -n ${PACKAGE}/.MainActivity --es mode web"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 \
    "$OUT_APK" \
    "$ALIGNED_UNSIGNED_APK" \
    "$UNSIGNED_APK" \
    "$RES_APK" \
    "$RES_ZIP" \
    "$ORT_AAR" \
    "${ASSET_PACKAGE_DIR}/assets/onnx/models/PP-OCRv6_tiny_det.onnx" \
    "${ASSET_PACKAGE_DIR}/assets/onnx/models/PP-OCRv6_tiny_rec.onnx" \
    "${ASSET_PACKAGE_DIR}/assets/web/ort/ort.webgpu.min.js" \
    "$VERIFY_REPORT" \
    "$BADGING_REPORT" \
    "$ARS_REPORT"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Manifest: ${MANIFEST}"
