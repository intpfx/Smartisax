#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
KEYTOOL="${KEYTOOL:-/opt/homebrew/opt/openjdk/bin/keytool}"
JARSIGNER="${JARSIGNER:-/opt/homebrew/opt/openjdk/bin/jarsigner}"
PYTHON="${PYTHON:-/Users/siaovon/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"

SOURCE_APK="${ROOT_DIR}/updates/modern-browser/payload/cromite.apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/apk-repack-cromite-browser"
DECODED_DIR="${WORK_DIR}/cromite-decoded"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
UNSIGNED_APK="${OUT_DIR}/cromite-as-com.android.browser-unsigned.apk"
OUT_APK="${OUT_DIR}/cromite-as-com.android.browser.apk"
MANIFEST="${OUT_DIR}/cromite-as-com.android.browser.SHA256SUMS.txt"
KEYSTORE="${ROOT_DIR}/hard-rom/keys/smartisax_apk.jks"
KEY_ALIAS="smartisax-apk"
KEY_PASS="SmartisaxApk2026"
EXPECTED_SOURCE_SHA256="77af7db8f0a02e8d8cd2099d1f9b5c8266d6ae4cba06924bda5c73f980dc6894"
EXPECTED_APKTOOL_SHA256="eee4669a704a14e0623407e6701b0b91887e61e1e4049cb7a82833e14ae8b5fd"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_file "$JAVA"
need_file "$KEYTOOL"
need_file "$JARSIGNER"
need_file "$PYTHON"
need_file "$APKTOOL"
need_file "$SOURCE_APK"

source_sha256="$(shasum -a 256 "$SOURCE_APK" | awk '{print $1}')"
[ "$source_sha256" = "$EXPECTED_SOURCE_SHA256" ] || die "source Cromite sha256 mismatch: ${source_sha256}"

apktool_sha256="$(shasum -a 256 "$APKTOOL" | awk '{print $1}')"
[ "$apktool_sha256" = "$EXPECTED_APKTOOL_SHA256" ] || die "apktool sha256 mismatch: ${apktool_sha256}"

mkdir -p "$WORK_DIR" "$OUT_DIR" "${ROOT_DIR}/hard-rom/keys"
rm -rf "$DECODED_DIR" "$UNSIGNED_APK" "$OUT_APK"

"$JAVA" -jar "$APKTOOL" d -f -s -o "$DECODED_DIR" "$SOURCE_APK"

"$PYTHON" - "$DECODED_DIR" <<'PY'
from pathlib import Path
import hashlib
import sys
import zlib

root = Path(sys.argv[1])
old = b"org.cromite.cromite"
new = b"com.android.browser"
old16 = "org.cromite.cromite".encode("utf-16le")
new16 = "com.android.browser".encode("utf-16le")

changed = []
for path in root.rglob("*"):
    if not path.is_file():
        continue
    data = path.read_bytes()
    out = data.replace(old, new).replace(old16, new16)
    if out == data:
        continue
    if path.suffix == ".dex":
        out = bytearray(out)
        out[12:32] = hashlib.sha1(out[32:]).digest()
        out[8:12] = zlib.adler32(out[12:]).to_bytes(4, "little")
        out = bytes(out)
    path.write_bytes(out)
    changed.append(str(path.relative_to(root)))

required = {
    "AndroidManifest.xml",
    "original/AndroidManifest.xml",
    "classes.dex",
    "res/xml/searchable.xml",
    "res/xml/launchershortcuts.xml",
}
missing = required.difference(changed)
if missing:
    raise SystemExit(f"required files were not patched: {sorted(missing)}")
print("\n".join(changed))
PY

# These future Android attributes are present in upstream Cromite's manifest,
# but apktool's current framework cannot relink them. Android 11 on R2 does not
# depend on them for our browser replacement test.
perl -0pi -e 's/\s+n0:zygotePreloadNativeLib="[^"]+"//g; s/\s+n0:nativeService="[^"]+"//g' \
  "${DECODED_DIR}/AndroidManifest.xml"

# Preserve the original practical compression profile. In particular,
# libchrome.so is compressed in the upstream APK; storing every .so makes the
# repacked APK too large for the R2 system partition.
perl -0pi -e 's/^\- so\n//m' "${DECODED_DIR}/apktool.yml"

"$JAVA" -jar "$APKTOOL" b "$DECODED_DIR" -o "$UNSIGNED_APK"

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
  "$OUT_APK" "$KEY_ALIAS"

"$JARSIGNER" -verify "$OUT_APK" >/dev/null

{
  echo "apk=${OUT_APK}"
  echo "source_apk=${SOURCE_APK}"
  echo "source_package=org.cromite.cromite"
  echo "target_package=com.android.browser"
  echo "versionName=148.0.7778.168"
  echo "versionCode=777816802"
  echo "signed_by=${KEYSTORE}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_APK" "$UNSIGNED_APK" "$SOURCE_APK" "$APKTOOL"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Manifest: ${MANIFEST}"
