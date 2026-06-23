#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_IMG="${ROOT_DIR}/hard-rom/extracted/system.img"
DEBUGFS="/opt/homebrew/opt/e2fsprogs/sbin/debugfs"
E2FSCK="/opt/homebrew/opt/e2fsprogs/sbin/e2fsck"
OPENSSL="/opt/homebrew/bin/openssl"

KEY_DIR="${ROOT_DIR}/hard-rom/keys"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/system-security"
TRUST_DIR="${ROOT_DIR}/hard-rom/build/trust-anchor"
VERIFY_DIR="${ROOT_DIR}/hard-rom/verify"
OUT_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.img"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_file "$SYSTEM_IMG"
need_cmd zip
need_cmd unzip
need_file "$DEBUGFS"
need_file "$E2FSCK"
need_file "$OPENSSL"

mkdir -p "$KEY_DIR" "$INSPECT_DIR" "$TRUST_DIR" "$VERIFY_DIR"

if [ ! -f "${INSPECT_DIR}/otacerts.zip" ]; then
  "$DEBUGFS" -R "dump -p /system/etc/security/otacerts.zip ${INSPECT_DIR}/otacerts.zip" "$SYSTEM_IMG" >/dev/null
fi

rm -rf "${INSPECT_DIR}/otacerts-unzipped"
mkdir -p "${INSPECT_DIR}/otacerts-unzipped"
unzip -o "${INSPECT_DIR}/otacerts.zip" -d "${INSPECT_DIR}/otacerts-unzipped" >/dev/null
need_file "${INSPECT_DIR}/otacerts-unzipped/releasekey.x509.pem"

if [ ! -f "${KEY_DIR}/smartisax_ota.key.pem" ]; then
  "$OPENSSL" genrsa -out "${KEY_DIR}/smartisax_ota.key.pem" 4096
  chmod 600 "${KEY_DIR}/smartisax_ota.key.pem"
fi

if [ ! -f "${KEY_DIR}/smartisax_ota.x509.pem" ]; then
  "$OPENSSL" req -new -x509 -sha256 \
    -key "${KEY_DIR}/smartisax_ota.key.pem" \
    -out "${KEY_DIR}/smartisax_ota.x509.pem" \
    -days 7300 \
    -subj '/C=CN/ST=BeiJing/L=Beijing/O=Smartisax/OU=ROM/CN=Smartisax OTA/emailAddress=smartisax.local@example.invalid'
fi

if [ ! -f "${KEY_DIR}/smartisax_ota.pk8" ]; then
  "$OPENSSL" pkcs8 -topk8 -inform PEM -outform DER \
    -in "${KEY_DIR}/smartisax_ota.key.pem" \
    -out "${KEY_DIR}/smartisax_ota.pk8" \
    -nocrypt
  chmod 600 "${KEY_DIR}/smartisax_ota.pk8"
fi

rm -rf "${TRUST_DIR}/otacerts-contents"
mkdir -p "${TRUST_DIR}/otacerts-contents"
cp "${INSPECT_DIR}/otacerts-unzipped/releasekey.x509.pem" \
  "${TRUST_DIR}/otacerts-contents/smartisan-releasekey.x509.pem"
cp "${KEY_DIR}/smartisax_ota.x509.pem" \
  "${TRUST_DIR}/otacerts-contents/smartisax-releasekey.x509.pem"
touch -t 200901010000 "${TRUST_DIR}/otacerts-contents/"*.x509.pem

(
  cd "${TRUST_DIR}/otacerts-contents"
  zip -q -X -9 "${TRUST_DIR}/otacerts-smartisan-plus-smartisax.zip" \
    smartisan-releasekey.x509.pem \
    smartisax-releasekey.x509.pem
)

cp "$SYSTEM_IMG" "$OUT_IMG"
"$DEBUGFS" -w -R 'rm /system/etc/security/otacerts.zip' "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R "write ${TRUST_DIR}/otacerts-smartisan-plus-smartisax.zip /system/etc/security/otacerts.zip" "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R 'ea_set /system/etc/security/otacerts.zip security.selinux u:object_r:system_file:s0' "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R 'set_inode_field /system/etc/security/otacerts.zip ctime 0x495c0780' "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R 'set_inode_field /system/etc/security/otacerts.zip atime 0x495c0780' "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R 'set_inode_field /system/etc/security/otacerts.zip mtime 0x495c0780' "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R 'set_inode_field /system/etc/security/otacerts.zip crtime 0x495c0780' "$OUT_IMG" >/dev/null

"$E2FSCK" -fn "$OUT_IMG" >/dev/null

"$DEBUGFS" -R "dump -p /system/etc/security/otacerts.zip ${VERIFY_DIR}/system-otatrust-v0.1-otacerts.zip" "$OUT_IMG" >/dev/null
cmp "${VERIFY_DIR}/system-otatrust-v0.1-otacerts.zip" \
  "${TRUST_DIR}/otacerts-smartisan-plus-smartisax.zip"

{
  echo "system_image=${OUT_IMG}"
  echo "source_system_image=${SYSTEM_IMG}"
  echo "otacerts_zip=${TRUST_DIR}/otacerts-smartisan-plus-smartisax.zip"
  echo "smartisax_cert=${KEY_DIR}/smartisax_ota.x509.pem"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$SYSTEM_IMG" "$OUT_IMG" \
    "${TRUST_DIR}/otacerts-smartisan-plus-smartisax.zip" \
    "${KEY_DIR}/smartisax_ota.x509.pem" \
    "${KEY_DIR}/smartisax_ota.pk8"
} > "${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.SHA256SUMS.txt"

echo "Built: ${OUT_IMG}"
echo "Manifest: ${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.SHA256SUMS.txt"
