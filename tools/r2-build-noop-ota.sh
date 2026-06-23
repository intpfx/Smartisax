#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD_PACKER="$ROOT/third_party/payload_packer-v0.1.1/bin/payload_packer"
SIGN_PAYLOAD="$ROOT/tools/r2-sign-update-payload.py"
KEY="$ROOT/hard-rom/keys/smartisax_ota.key.pem"
CERT="$ROOT/hard-rom/keys/smartisax_ota.x509.pem"

NAME="${1:-full-dynamic-v0.1}"
OUT="$ROOT/hard-rom/noop-ota/$NAME"
TARGET="$OUT/target-images"
RAW="$OUT/raw"
SIGNED="$OUT/signed"
PKG="$OUT/package"
OTA_VERSION="${OTA_VERSION:-1.0.4}"
ZIP="$OUT/Smartisax_${OTA_VERSION}_full_dynamic_noop_update.zip"
SWITCH_SLOT_ON_REBOOT="${SWITCH_SLOT_ON_REBOOT:-0}"
RUN_POST_INSTALL="${RUN_POST_INSTALL:-0}"

DYNAMIC_GROUP="qti_dynamic_partitions:5364514816:system,system_ext,product,vendor,odm"
MAX_TIMESTAMP="${MAX_TIMESTAMP:-2000000000}"

rm -rf "$TARGET" "$RAW" "$SIGNED" "$PKG" "$ZIP"
mkdir -p "$TARGET" "$RAW" "$SIGNED" "$PKG/META-INF/com/android"

ln -s "$ROOT/hard-rom/build/system-otatrust-v0.1.img" "$TARGET/system.img"
ln -s "$ROOT/hard-rom/extracted/system_ext.img" "$TARGET/system_ext.img"
ln -s "$ROOT/hard-rom/extracted/product.img" "$TARGET/product.img"
ln -s "$ROOT/hard-rom/extracted/vendor.img" "$TARGET/vendor.img"
ln -s "$ROOT/hard-rom/extracted/odm.img" "$TARGET/odm.img"

"$PAYLOAD_PACKER" \
  --target-dir "$TARGET" \
  --partitions system,system_ext,product,vendor,odm \
  --method bz2 \
  --level 1 \
  --output "$RAW/payload.bin"

"$SIGN_PAYLOAD" \
  --payload-in "$RAW/payload.bin" \
  --payload-out "$SIGNED/payload.bin" \
  --properties-out "$SIGNED/payload_properties.base.txt" \
  --key "$KEY" \
  --max-timestamp "$MAX_TIMESTAMP" \
  --dynamic-group "$DYNAMIC_GROUP"

cp "$SIGNED/payload_properties.base.txt" "$SIGNED/payload_properties.txt"
{
  echo "SWITCH_SLOT_ON_REBOOT=$SWITCH_SLOT_ON_REBOOT"
  echo "RUN_POST_INSTALL=$RUN_POST_INSTALL"
} >> "$SIGNED/payload_properties.txt"

cp "$SIGNED/payload.bin" "$PKG/payload.bin"
cp "$SIGNED/payload_properties.txt" "$PKG/payload_properties.txt"
cp "$CERT" "$PKG/META-INF/com/android/otacert"
cat > "$PKG/META-INF/com/android/metadata" <<'EOF'
ota-type=AB
post-build=SMARTISAN/aries/aries:11/RKQ1.201217.002/1658136626:user/dev-keys
post-build-incremental=1658136626
post-sdk-level=30
post-security-patch-level=2022-07-01
post-timestamp=1658136626
pre-device=darwin
EOF

(
  cd "$PKG"
  zip -0 -X -q "$ZIP" \
    META-INF/com/android/metadata \
    payload.bin \
    payload_properties.txt \
    META-INF/com/android/otacert
)

{
  shasum -a 256 "$TARGET"/*.img
  shasum -a 256 "$RAW/payload.bin" "$SIGNED/payload.bin" "$ZIP"
  md5 -r "$ZIP"
} > "$OUT/SHA256SUMS-and-MD5.txt"

echo "$ZIP"
