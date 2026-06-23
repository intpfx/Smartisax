#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
KEYTOOL="${KEYTOOL:-/opt/homebrew/opt/openjdk/bin/keytool}"
JARSIGNER="${JARSIGNER:-/opt/homebrew/opt/openjdk/bin/jarsigner}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"

SRC_DIR="${ROOT_DIR}/apps/SmartisaxControls"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
UNSIGNED_APK="${OUT_DIR}/SmartisaxControls-unsigned.apk"
OUT_APK="${OUT_DIR}/SmartisaxControls.apk"
MANIFEST="${OUT_DIR}/SmartisaxControls.SHA256SUMS.txt"
KEYSTORE="${ROOT_DIR}/hard-rom/keys/smartisax_apk.jks"
KEY_ALIAS="smartisax-apk"
KEY_PASS="SmartisaxApk2026"

need_file() {
  [ -f "$1" ] || {
    echo "missing file: $1" >&2
    exit 1
  }
}

need_file "$JAVA"
need_file "$KEYTOOL"
need_file "$JARSIGNER"
need_file "$APKTOOL"
need_file "${SRC_DIR}/AndroidManifest.xml"

mkdir -p "$OUT_DIR" "${ROOT_DIR}/hard-rom/keys"
rm -f "$UNSIGNED_APK" "$OUT_APK" "$MANIFEST"

"$JAVA" -jar "$APKTOOL" b "$SRC_DIR" -o "$UNSIGNED_APK" >/dev/null

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

cp "$UNSIGNED_APK" "$OUT_APK"
"$JARSIGNER" \
  -keystore "$KEYSTORE" \
  -storepass "$KEY_PASS" \
  -keypass "$KEY_PASS" \
  -sigalg SHA256withRSA \
  -digestalg SHA-256 \
  "$OUT_APK" "$KEY_ALIAS" >/dev/null

"$JARSIGNER" -verify "$OUT_APK" >/dev/null

{
  echo "apk=${OUT_APK}"
  echo "unsigned_apk=${UNSIGNED_APK}"
  echo "source=${SRC_DIR}"
  echo "package=com.smartisax.controls"
  echo "versionName=0.1.0"
  echo "versionCode=1"
  echo "signed_by=${KEYSTORE}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_APK" "$UNSIGNED_APK" "$APKTOOL"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Manifest: ${MANIFEST}"
