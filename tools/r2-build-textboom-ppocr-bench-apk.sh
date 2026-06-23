#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

APP_DIR="${ROOT_DIR}/apps/TextBoomPpOcrBench"
BUILD_DIR="${ROOT_DIR}/hard-rom/build/textboom-ppocr-bench"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/TextBoomPpOcrBench.apk"
MANIFEST="${OUT_DIR}/TextBoomPpOcrBench.SHA256SUMS.txt"
KEYSTORE="${ROOT_DIR}/hard-rom/keys/smartisax_apk.jks"
KEY_ALIAS="smartisax-apk"
KEY_PASS="SmartisaxApk2026"
PACKAGE="com.smartisax.ocrbench"
VERSION_NAME="0.1.0"
VERSION_CODE="1"

ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-30/android.jar"
AAPT="${ANDROID_SDK_ROOT}/build-tools/35.0.1/aapt"
AAPT2="${ANDROID_SDK_ROOT}/build-tools/35.0.1/aapt2"
APKSIGNER="${ANDROID_SDK_ROOT}/build-tools/35.0.1/apksigner"
D8="${ANDROID_SDK_ROOT}/build-tools/35.0.1/d8"
ZIPALIGN="${ANDROID_SDK_ROOT}/build-tools/35.0.1/zipalign"
JAVAC="${JAVA_HOME}/bin/javac"
KEYTOOL="${JAVA_HOME}/bin/keytool"
CMAKE="${ANDROID_SDK_ROOT}/cmake/3.22.1/bin/cmake"
NINJA="${ANDROID_SDK_ROOT}/cmake/3.22.1/bin/ninja"
ABI="arm64-v8a"
NATIVE_SRC_DIR="${APP_DIR}/native/src/main/cpp"
PPOCR_ASSETS_DIR="${PPOCR_ASSETS_DIR:-${ROOT_DIR}/third_party/_downloads/ppocr-runtime/paddle-lite-demo-assets}"
PADDLE_LITE_ROOT="${PADDLE_LITE_ROOT:-${ROOT_DIR}/third_party/_downloads/ppocr-runtime/paddle-lite-demo-v2.10/extracted}"
OPENCV_EXTRACTED_ROOT="${ROOT_DIR}/third_party/_downloads/ppocr-runtime/opencv/extracted"
OPENCV_COMPAT_ROOT="${OPENCV_EXTRACTED_ROOT}/opencv/opencv4.1.0"
OPENCV_ROOT="${OPENCV_ROOT:-${OPENCV_COMPAT_ROOT}}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

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
need_executable "$AAPT"
need_executable "$AAPT2"
need_executable "$APKSIGNER"
need_executable "$D8"
need_executable "$ZIPALIGN"
need_executable "$JAVAC"
need_executable "$KEYTOOL"
need_executable "$CMAKE"
need_executable "$NINJA"
[ -n "$ANDROID_NDK_HOME" ] || die "ANDROID_NDK_HOME is not set; source tools/r2-android-sdk-env.sh with an installed NDK"
if [ ! -e "$OPENCV_COMPAT_ROOT" ] && [ -d "${OPENCV_EXTRACTED_ROOT}/opencv4.1.0" ]; then
  mkdir -p "$(dirname "$OPENCV_COMPAT_ROOT")"
  ln -s ../opencv4.1.0 "$OPENCV_COMPAT_ROOT"
fi
need_file "${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
need_file "${NATIVE_SRC_DIR}/CMakeLists.txt"
need_file "${PADDLE_LITE_ROOT}/cxx/include/paddle_api.h"
PADDLE_LITE_SHARED="${PADDLE_LITE_ROOT}/cxx/libs/${ABI}/libpaddle_light_api_shared.so"
PADDLE_LITE_STATIC="${PADDLE_LITE_ROOT}/cxx/lib/libpaddle_api_light_bundled.a"
if [ -f "$PADDLE_LITE_SHARED" ]; then
  PADDLE_LITE_MODE="shared"
  PADDLE_LITE_RUNTIME="$PADDLE_LITE_SHARED"
elif [ -f "$PADDLE_LITE_STATIC" ]; then
  PADDLE_LITE_MODE="static"
  PADDLE_LITE_RUNTIME="$PADDLE_LITE_STATIC"
else
  die "missing Paddle Lite runtime under ${PADDLE_LITE_ROOT}"
fi
need_file "$PADDLE_LITE_RUNTIME"
if [ "$PADDLE_LITE_MODE" = "shared" ]; then
  python3 - "$PADDLE_LITE_RUNTIME" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
    raise SystemExit(f"unsupported ELF format: {path}")

e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
e_shentsize = struct.unpack_from("<H", data, 0x3A)[0]
e_shnum = struct.unpack_from("<H", data, 0x3C)[0]
e_shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
if e_shoff == 0 or e_shnum == 0:
    raise SystemExit(f"ELF has no section headers: {path}")

def shdr(index):
    off = e_shoff + index * e_shentsize
    return struct.unpack_from("<IIQQQQIIQQ", data, off), off

headers = [shdr(index) for index in range(e_shnum)]
shstr_header, _ = headers[e_shstrndx]
shstr_off = shstr_header[4]
shstr_size = shstr_header[5]
shstr = data[shstr_off:shstr_off + shstr_size]

def section_name(name_offset):
    end = shstr.find(b"\0", name_offset)
    if end < 0:
        return ""
    return shstr[name_offset:end].decode("utf-8", "replace")

for header, header_off in headers:
    name = section_name(header[0])
    if name != ".dynsym":
        continue
    dynsym_off = header[4]
    dynsym_size = header[5]
    dynsym_entsize = header[9]
    old_info = header[7]
    if dynsym_entsize <= 0:
        raise SystemExit(".dynsym has invalid entry size")
    local_count = 0
    for offset in range(dynsym_off, dynsym_off + dynsym_size, dynsym_entsize):
        st_info = data[offset + 4]
        bind = st_info >> 4
        if bind != 0:
            break
        local_count += 1
    if old_info != local_count:
        struct.pack_into("<I", data, header_off + 44, local_count)
        path.write_bytes(data)
        print(f"patched {path}: .dynsym sh_info {old_info} -> {local_count}")
    else:
        print(f"checked {path}: .dynsym sh_info={old_info}")
    break
else:
    raise SystemExit(".dynsym not found")
PY
fi
need_file "${OPENCV_ROOT}/${ABI}/cmake/OpenCVConfig.cmake"
need_file "${PPOCR_ASSETS_DIR}/models/ch_ppocr_mobile_v2.0_det_slim_opt.nb"
need_file "${PPOCR_ASSETS_DIR}/models/ch_ppocr_mobile_v2.0_cls_slim_opt.nb"
need_file "${PPOCR_ASSETS_DIR}/models/ch_ppocr_mobile_v2.0_rec_slim_opt.nb"
need_file "${PPOCR_ASSETS_DIR}/labels/ppocr_keys_v1.txt"
need_file "${PPOCR_ASSETS_DIR}/config.txt"

LIBCXX_SHARED="$(find "${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt" \
  -path '*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so' \
  -type f | sort | head -n 1)"
[ -n "$LIBCXX_SHARED" ] || die "missing NDK libc++_shared.so for ${ABI}"
need_file "$LIBCXX_SHARED"

RES_ZIP="${BUILD_DIR}/resources.zip"
GEN_DIR="${BUILD_DIR}/generated"
CLASSES_DIR="${BUILD_DIR}/classes"
DEX_DIR="${BUILD_DIR}/dex"
NATIVE_BUILD_DIR="${BUILD_DIR}/native"
NATIVE_PACKAGE_DIR="${BUILD_DIR}/native-package"
ASSET_PACKAGE_DIR="${BUILD_DIR}/asset-package"
RES_APK="${BUILD_DIR}/TextBoomPpOcrBench-res.apk"
UNSIGNED_APK="${BUILD_DIR}/TextBoomPpOcrBench-unsigned.apk"
ALIGNED_UNSIGNED_APK="${BUILD_DIR}/TextBoomPpOcrBench-unsigned-aligned.apk"
VERIFY_REPORT="${OUT_DIR}/TextBoomPpOcrBench.apksigner.txt"
BADGING_REPORT="${OUT_DIR}/TextBoomPpOcrBench.badging.txt"
ARS_REPORT="${OUT_DIR}/TextBoomPpOcrBench.zip-layout.txt"

mkdir -p "$OUT_DIR" "${ROOT_DIR}/hard-rom/keys"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$GEN_DIR" "$CLASSES_DIR" "$DEX_DIR" "$NATIVE_PACKAGE_DIR" "$ASSET_PACKAGE_DIR"
rm -f "$OUT_APK" "$MANIFEST" "$VERIFY_REPORT" "$BADGING_REPORT" "$ARS_REPORT"

"$CMAKE" \
  -S "$NATIVE_SRC_DIR" \
  -B "$NATIVE_BUILD_DIR" \
  -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM=android-30 \
  -DANDROID_STL=c++_shared \
  -DPADDLE_LITE_ROOT="$PADDLE_LITE_ROOT" \
  -DOPENCV_ROOT="$OPENCV_ROOT"
"$CMAKE" --build "$NATIVE_BUILD_DIR"

mkdir -p "${NATIVE_PACKAGE_DIR}/lib/${ABI}"
cp "${NATIVE_BUILD_DIR}/libsmartisax_ppocr_bench.so" "${NATIVE_PACKAGE_DIR}/lib/${ABI}/"
if [ "$PADDLE_LITE_MODE" = "shared" ]; then
  cp "$PADDLE_LITE_RUNTIME" "${NATIVE_PACKAGE_DIR}/lib/${ABI}/"
fi
cp "$LIBCXX_SHARED" "${NATIVE_PACKAGE_DIR}/lib/${ABI}/"

mkdir -p "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models" "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/labels"
cp "${PPOCR_ASSETS_DIR}/models/ch_ppocr_mobile_v2.0_det_slim_opt.nb" "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models/"
cp "${PPOCR_ASSETS_DIR}/models/ch_ppocr_mobile_v2.0_cls_slim_opt.nb" "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models/"
cp "${PPOCR_ASSETS_DIR}/models/ch_ppocr_mobile_v2.0_rec_slim_opt.nb" "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models/"
cp "${PPOCR_ASSETS_DIR}/labels/ppocr_keys_v1.txt" "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/labels/"
cp "${PPOCR_ASSETS_DIR}/config.txt" "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/config.txt"

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
  -classpath "$ANDROID_JAR" \
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
  echo "paddle_lite_mode=${PADDLE_LITE_MODE}"
  echo "paddle_lite_root=${PADDLE_LITE_ROOT}"
  echo "paddle_lite_runtime=${PADDLE_LITE_RUNTIME}"
  echo "opencv_root=${OPENCV_ROOT}"
  echo "ppocr_assets_dir=${PPOCR_ASSETS_DIR}"
  echo "signed_by=${KEYSTORE}"
  echo "verify_report=${VERIFY_REPORT}"
  echo "badging_report=${BADGING_REPORT}"
  echo "zip_layout_report=${ARS_REPORT}"
  echo "default_device_input=/sdcard/Android/data/${PACKAGE}/files/input/imageboom.jpg"
  echo "default_device_result=/sdcard/Android/data/${PACKAGE}/files/results/last-result.json"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 \
    "$OUT_APK" \
    "$ALIGNED_UNSIGNED_APK" \
    "$UNSIGNED_APK" \
    "$RES_APK" \
    "$RES_ZIP" \
    "$NATIVE_BUILD_DIR/libsmartisax_ppocr_bench.so" \
    "$PADDLE_LITE_RUNTIME" \
    "${NATIVE_PACKAGE_DIR}/lib/${ABI}/libc++_shared.so" \
    "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models/ch_ppocr_mobile_v2.0_det_slim_opt.nb" \
    "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models/ch_ppocr_mobile_v2.0_cls_slim_opt.nb" \
    "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/models/ch_ppocr_mobile_v2.0_rec_slim_opt.nb" \
    "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/labels/ppocr_keys_v1.txt" \
    "${ASSET_PACKAGE_DIR}/assets/ppocr-v2/config.txt" \
    "$VERIFY_REPORT" \
    "$BADGING_REPORT" \
    "$ARS_REPORT"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Manifest: ${MANIFEST}"
