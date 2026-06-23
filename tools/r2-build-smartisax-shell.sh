#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
JAVAC="${JAVAC:-/opt/homebrew/opt/openjdk/bin/javac}"
JAR="${JAR:-/opt/homebrew/opt/openjdk/bin/jar}"
KEYTOOL="${KEYTOOL:-/opt/homebrew/opt/openjdk/bin/keytool}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
BUN="${BUN:-/opt/homebrew/bin/bun}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/zipalign}"
APKSIGNER="${APKSIGNER:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/apksigner}"
D8="${D8:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/d8}"
ANDROID_JAR="${ANDROID_JAR:-${ROOT_DIR}/third_party/android-sdk/platforms/android-30/android.jar}"
WEBRTC_AAR="${WEBRTC_AAR:-${ROOT_DIR}/third_party/webrtc-sdk/android/125.6422.07/webrtc-sdk-android-125.6422.07.aar}"

SRC_DIR="${ROOT_DIR}/apps/SmartisaxShell"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
UNSIGNED_APK="${OUT_DIR}/SmartisaxShell-unsigned.apk"
ALIGNED_UNSIGNED_APK="${OUT_DIR}/SmartisaxShell-unsigned-aligned.apk"
OUT_APK="${OUT_DIR}/SmartisaxShell.apk"
MANIFEST="${OUT_DIR}/SmartisaxShell.SHA256SUMS.txt"
KEYSTORE="${ROOT_DIR}/hard-rom/keys/smartisax_apk.jks"
KEY_ALIAS="smartisax-apk"
KEY_PASS="SmartisaxApk2026"
TS_ENTRY="${SRC_DIR}/assets-src/shell.ts"
JS_OUT="${SRC_DIR}/assets/shell/shell.js"
JAVA_SRC_DIR="${SRC_DIR}/src"
JAVA_BUILD_DIR="${OUT_DIR}/SmartisaxShell-java"
CLASSES_DIR="${JAVA_BUILD_DIR}/classes"
DEX_DIR="${JAVA_BUILD_DIR}/dex"
CLASSES_JAR="${JAVA_BUILD_DIR}/classes.jar"
WEBRTC_AAR_DIR="${JAVA_BUILD_DIR}/webrtc-aar"
WEBRTC_CLASSES_JAR="${WEBRTC_AAR_DIR}/classes.jar"
WEBRTC_JNI_DIR="${WEBRTC_AAR_DIR}/jni"

need_file() {
  [ -f "$1" ] || {
    echo "missing file: $1" >&2
    exit 1
  }
}

need_executable() {
  [ -x "$1" ] || {
    echo "missing executable: $1" >&2
    exit 1
  }
}

need_executable "$JAVA"
need_executable "$JAVAC"
need_executable "$JAR"
need_executable "$KEYTOOL"
need_file "$APKTOOL"
need_executable "$BUN"
need_executable "$ZIPALIGN"
need_executable "$APKSIGNER"
need_executable "$D8"
need_file "$ANDROID_JAR"
need_file "$WEBRTC_AAR"
need_file "${SRC_DIR}/AndroidManifest.xml"
need_file "$TS_ENTRY"

mkdir -p "$OUT_DIR" "${ROOT_DIR}/hard-rom/keys" "$(dirname "$JS_OUT")"
rm -f "$UNSIGNED_APK" "$ALIGNED_UNSIGNED_APK" "$OUT_APK" "$MANIFEST" "$JS_OUT"

"$BUN" build "$TS_ENTRY" --outfile "$JS_OUT" --format iife --target browser >/dev/null
need_file "$JS_OUT"

"$JAVA" -jar "$APKTOOL" b "$SRC_DIR" -o "$UNSIGNED_APK" >/dev/null

if [ -d "$JAVA_SRC_DIR" ] && find "$JAVA_SRC_DIR" -name '*.java' -print -quit | grep -q .; then
  rm -rf "$JAVA_BUILD_DIR"
  mkdir -p "$CLASSES_DIR" "$DEX_DIR"
  mkdir -p "$WEBRTC_AAR_DIR"
  unzip -q "$WEBRTC_AAR" -d "$WEBRTC_AAR_DIR"
  need_file "$WEBRTC_CLASSES_JAR"
  need_file "${WEBRTC_JNI_DIR}/arm64-v8a/libjingle_peerconnection_so.so"
  need_file "${WEBRTC_JNI_DIR}/armeabi-v7a/libjingle_peerconnection_so.so"
  find "$JAVA_SRC_DIR" -name '*.java' | sort > "${JAVA_BUILD_DIR}/sources.list"
  "$JAVAC" \
    -encoding UTF-8 \
    -source 8 \
    -target 8 \
    -bootclasspath "$ANDROID_JAR" \
    -classpath "$WEBRTC_CLASSES_JAR" \
    -d "$CLASSES_DIR" \
    @"${JAVA_BUILD_DIR}/sources.list"
  "$JAR" --create --file "$CLASSES_JAR" -C "$CLASSES_DIR" .
  PATH="$(dirname "$JAVA"):${PATH}" "$D8" --min-api 30 --lib "$ANDROID_JAR" --output "$DEX_DIR" "$CLASSES_JAR" "$WEBRTC_CLASSES_JAR" >/dev/null
  need_file "${DEX_DIR}/classes.dex"
  python3 - "$UNSIGNED_APK" "${DEX_DIR}/classes.dex" "$WEBRTC_JNI_DIR" <<'PY'
import os
import sys
import zipfile
from pathlib import Path

apk = Path(sys.argv[1])
dex = Path(sys.argv[2])
webrtc_jni = Path(sys.argv[3])
tmp = apk.with_suffix(apk.suffix + ".tmp")
native_libs = {
    "lib/arm64-v8a/libjingle_peerconnection_so.so": webrtc_jni / "arm64-v8a" / "libjingle_peerconnection_so.so",
    "lib/armeabi-v7a/libjingle_peerconnection_so.so": webrtc_jni / "armeabi-v7a" / "libjingle_peerconnection_so.so",
}
fixed_time = (2026, 1, 1, 0, 0, 0)

with zipfile.ZipFile(apk, "r") as src, zipfile.ZipFile(tmp, "w") as dst:
    for info in src.infolist():
        if info.filename == "classes.dex" or info.filename in native_libs:
            continue
        dst.writestr(info, src.read(info.filename))
    dst.write(dex, "classes.dex", compress_type=zipfile.ZIP_DEFLATED)
    for name, path in native_libs.items():
        out = zipfile.ZipInfo(name, fixed_time)
        out.compress_type = zipfile.ZIP_STORED
        out.external_attr = 0o100644 << 16
        dst.writestr(out, path.read_bytes())

os.replace(tmp, apk)
PY
fi

python3 - "$UNSIGNED_APK" <<'PY'
import os
import sys
import zipfile
from pathlib import Path

apk = Path(sys.argv[1])
tmp = apk.with_suffix(apk.suffix + ".normalized")
fixed_time = (2026, 1, 1, 0, 0, 0)

with zipfile.ZipFile(apk, "r") as src, zipfile.ZipFile(tmp, "w") as dst:
    for info in src.infolist():
        data = src.read(info.filename)
        out = zipfile.ZipInfo(info.filename, fixed_time)
        out.compress_type = info.compress_type
        out.comment = info.comment
        out.extra = b""
        out.internal_attr = info.internal_attr
        out.external_attr = info.external_attr
        out.create_system = info.create_system
        dst.writestr(out, data)

os.replace(tmp, apk)
PY

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

"$ZIPALIGN" -f -p 4 "$UNSIGNED_APK" "$ALIGNED_UNSIGNED_APK"
cp "$ALIGNED_UNSIGNED_APK" "$OUT_APK"
JAVA_HOME="${JAVA_HOME:-$(cd "$(dirname "$JAVA")/.." && pwd)}" "$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:${KEY_PASS}" \
  --key-pass "pass:${KEY_PASS}" \
  --min-sdk-version 30 \
  "$OUT_APK" >/dev/null
JAVA_HOME="${JAVA_HOME:-$(cd "$(dirname "$JAVA")/.." && pwd)}" "$APKSIGNER" verify --min-sdk-version 30 "$OUT_APK" >/dev/null
"$ZIPALIGN" -c -p 4 "$OUT_APK" >/dev/null
unzip -t "$OUT_APK" >/dev/null

python3 - "$OUT_APK" <<'PY'
import sys
import struct
import zipfile

apk = sys.argv[1]
with open(apk, "rb") as fp, zipfile.ZipFile(apk) as zf:
    info = zf.getinfo("resources.arsc")
    fp.seek(info.header_offset)
    header = fp.read(30)
    if len(header) != 30:
        raise SystemExit("truncated ZIP local header for resources.arsc")
    sig, _ver, _flag, method, *_rest, name_len, extra_len = struct.unpack("<IHHHHHIIIHH", header)
    if sig != 0x04034B50:
        raise SystemExit("bad ZIP local header signature for resources.arsc")
    data_offset = info.header_offset + 30 + name_len + extra_len
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit("resources.arsc is not STORED")
    if method != zipfile.ZIP_STORED:
        raise SystemExit("resources.arsc local header is not STORED")
    if data_offset % 4 != 0:
        raise SystemExit(f"resources.arsc data offset is not 4-byte aligned: {data_offset}")
PY

{
  echo "apk=${OUT_APK}"
  echo "unsigned_apk=${UNSIGNED_APK}"
  echo "aligned_unsigned_apk=${ALIGNED_UNSIGNED_APK}"
  echo "source=${SRC_DIR}"
  echo "package=com.smartisax.browser"
  echo "versionName=0.6.9"
  echo "versionCode=26"
  echo "webrtc_aar=${WEBRTC_AAR}"
  echo "signed_by=${KEYSTORE}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  if [ -f "${DEX_DIR}/classes.dex" ]; then
    shasum -a 256 "$OUT_APK" "$ALIGNED_UNSIGNED_APK" "$UNSIGNED_APK" "$JS_OUT" "${DEX_DIR}/classes.dex" "$WEBRTC_AAR" "$WEBRTC_CLASSES_JAR" "${WEBRTC_JNI_DIR}/arm64-v8a/libjingle_peerconnection_so.so" "${WEBRTC_JNI_DIR}/armeabi-v7a/libjingle_peerconnection_so.so" "$APKTOOL" "$ZIPALIGN" "$APKSIGNER" "$ANDROID_JAR"
  else
    shasum -a 256 "$OUT_APK" "$ALIGNED_UNSIGNED_APK" "$UNSIGNED_APK" "$JS_OUT" "$APKTOOL" "$ZIPALIGN" "$APKSIGNER" "$ANDROID_JAR"
  fi
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Manifest: ${MANIFEST}"
