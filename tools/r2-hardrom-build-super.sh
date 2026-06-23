#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMake="${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake"
LPDump="${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump"
OUT_DIR="${ROOT_DIR}/hard-rom/build"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

check_max_size() {
  local label="$1"
  local file="$2"
  local max_size="$3"
  local actual
  actual="$(size_bytes "$file")"
  [ "$actual" -le "$max_size" ] || die "${label} image too large: ${actual} > ${max_size}"
}

dump_sparse_prefix() {
  local image="$1"
  local output="$2"
  python3 - "$image" "$output" <<'PY'
import struct
import sys
from pathlib import Path

src = Path(sys.argv[1])
out = Path(sys.argv[2])
limit = 8 * 1024 * 1024

with src.open("rb") as f, out.open("wb") as g:
    header = f.read(28)
    magic, major, minor, file_hdr_sz, chunk_hdr_sz, block_size, total_blocks, total_chunks, checksum = struct.unpack(
        "<IHHHHIIII", header
    )
    if magic != 0xED26FF3A:
        raise SystemExit("not an Android sparse image")
    if file_hdr_sz > 28:
        f.read(file_hdr_sz - 28)

    written = 0
    for _ in range(total_chunks):
        chunk_header = f.read(12)
        if len(chunk_header) != 12:
            raise SystemExit("truncated sparse chunk header")
        chunk_type, reserved, chunk_blocks, total_size = struct.unpack("<HHII", chunk_header)
        data_size = total_size - chunk_hdr_sz
        want = min(chunk_blocks * block_size, max(0, limit - written))

        if chunk_type == 0xCAC1:
            data = f.read(data_size)
            if want:
                g.write(data[:want])
        elif chunk_type == 0xCAC2:
            fill = f.read(4)
            if data_size > 4:
                f.read(data_size - 4)
            if want:
                g.write((fill * ((want + 3) // 4))[:want])
        elif chunk_type == 0xCAC3:
            if data_size:
                f.read(data_size)
            if want:
                g.write(b"\0" * want)
        elif chunk_type == 0xCAC4:
            if data_size:
                f.read(data_size)
        else:
            raise SystemExit(f"unknown sparse chunk type: {chunk_type:#x}")

        written += chunk_blocks * block_size
        if written >= limit:
            break
PY
}

variant="${1:-otatrust-v0.1-exact-current}"
include_a_placeholders=0
exact_current=0

case "$variant" in
  otatrust-v0.1-exact-current)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.1-exact-current.img"
    exact_current=1
    ;;
  otatrust-v0.2-no-appstore-exact-current)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.2-no-appstore.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.2-no-appstore-exact-current.img"
    exact_current=1
    ;;
  otatrust-v0.3-browser-samepkg-exact-current)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.3-browser-samepkg.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.3-browser-samepkg-exact-current.img"
    exact_current=1
    ;;
  otatrust-v0.3.1-browser-official-update-exact-current)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.3.1-browser-official-update.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.3.1-browser-official-update-exact-current.img"
    exact_current=1
    ;;
  otatrust-v0.4-debloat-exact-current)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.4-debloat.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.4-debloat-exact-current.img"
    exact_current=1
    ;;
  otatrust-v0.1-bonly)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.1-bonly.img"
    ;;
  otatrust-v0.1-current-layout)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.img"
    OUT_IMG="${OUT_DIR}/super-otatrust-v0.1-current-layout.img"
    include_a_placeholders=1
    ;;
  stock-bonly)
    SYSTEM_IMG="${ROOT_DIR}/hard-rom/extracted/system.img"
    OUT_IMG="${OUT_DIR}/super-stock-bonly.img"
    ;;
  *)
    die "usage: $0 [otatrust-v0.1-exact-current|otatrust-v0.2-no-appstore-exact-current|otatrust-v0.3-browser-samepkg-exact-current|otatrust-v0.3.1-browser-official-update-exact-current|otatrust-v0.4-debloat-exact-current|otatrust-v0.1-current-layout|otatrust-v0.1-bonly|stock-bonly]"
    ;;
esac

PRODUCT_IMG="${ROOT_DIR}/hard-rom/extracted/product.img"
SYSTEM_EXT_IMG="${ROOT_DIR}/hard-rom/extracted/system_ext.img"
VENDOR_IMG="${ROOT_DIR}/hard-rom/extracted/vendor.img"
ODM_IMG="${ROOT_DIR}/hard-rom/extracted/odm.img"

need_file "$LPMake"
need_file "$LPDump"
need_file "$SYSTEM_IMG"

mkdir -p "$OUT_DIR"

# These values come from backups/2026-06-17-apatch-root-critical/lpdump.txt,
# metadata slot 1, current active slot b.
SUPER_SIZE=10737418240
METADATA_SIZE=65536
METADATA_SLOTS=3
GROUP_B_MAX=5364514816
GROUP_A_MAX=5364514816

SYSTEM_A_SIZE=3052314624
PRODUCT_A_SIZE=255815680
VENDOR_A_SIZE=941768704
ODM_A_SIZE=917504

SYSTEM_B_SIZE=3049058304
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_SIZE=171110400
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768

check_max_size system_b "$SYSTEM_IMG" "$SYSTEM_B_SIZE"
check_max_size system_ext_b "$SYSTEM_EXT_IMG" "$SYSTEM_EXT_B_SIZE"
check_max_size product_b "$PRODUCT_IMG" "$PRODUCT_B_SIZE"
check_max_size vendor_b "$VENDOR_IMG" "$VENDOR_B_SIZE"
check_max_size odm_b "$ODM_IMG" "$ODM_B_SIZE"

rm -f "$OUT_IMG" "${OUT_IMG}.lpdump.txt" "${OUT_IMG}.SHA256SUMS.txt"

if [ "$exact_current" -eq 1 ]; then
  CURRENT_SUPER="${ROOT_DIR}/backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img"
  need_file "$CURRENT_SUPER"
  check_max_size system_b "$SYSTEM_IMG" "$SYSTEM_B_SIZE"

  # Current super slot 1 maps system_b to sector 10487744, size 5955192 sectors.
  # The sector size is 512 bytes, so the 4096-byte block seek is 10487744 / 8.
  SYSTEM_B_SKIP_4096=1310968
  SYSTEM_B_COUNT_4096=744399

  if cp -c "$CURRENT_SUPER" "$OUT_IMG" 2>/dev/null; then
    :
  else
    cp "$CURRENT_SUPER" "$OUT_IMG"
  fi

  dd if="$SYSTEM_IMG" of="$OUT_IMG" bs=4096 seek="$SYSTEM_B_SKIP_4096" conv=notrunc >/dev/null 2>&1

  "$LPDump" -s 0 "$OUT_IMG" > "${OUT_IMG}.lpdump-slot0.txt"
  "$LPDump" -s 1 "$OUT_IMG" > "${OUT_IMG}.lpdump-slot1.txt"
  cat "${OUT_IMG}.lpdump-slot0.txt" "${OUT_IMG}.lpdump-slot1.txt" > "${OUT_IMG}.lpdump.txt"

  system_b_hash="$(dd if="$OUT_IMG" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  expected_system_hash="$(shasum -a 256 "$SYSTEM_IMG" | awk '{print $1}')"
  [ "$system_b_hash" = "$expected_system_hash" ] || die "patched system_b hash mismatch"

  {
    echo "super_image=${OUT_IMG}"
    echo "source_super_image=${CURRENT_SUPER}"
    echo "variant=${variant}"
    echo "patched_partition=system_b"
    echo "system_b_start_sector=10487744"
    echo "system_b_size_sectors=5955192"
    echo "system_b_sha256=${system_b_hash}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$OUT_IMG" "$CURRENT_SUPER" "$SYSTEM_IMG"
  } > "${OUT_IMG}.SHA256SUMS.txt"

  echo "Built: ${OUT_IMG}"
  echo "Metadata dump: ${OUT_IMG}.lpdump.txt"
  echo "Manifest: ${OUT_IMG}.SHA256SUMS.txt"
  exit 0
fi

need_file "$PRODUCT_IMG"
need_file "$SYSTEM_EXT_IMG"
need_file "$VENDOR_IMG"
need_file "$ODM_IMG"

lpmake_args=(
  --metadata-size="$METADATA_SIZE"
  --metadata-slots="$METADATA_SLOTS"
  --super-name=super
  --device="super:${SUPER_SIZE}"
)

if [ "$include_a_placeholders" -eq 1 ]; then
  lpmake_args+=(
    --group="qti_dynamic_partitions_a:${GROUP_A_MAX}"
    --partition="system_a:readonly:${SYSTEM_A_SIZE}:qti_dynamic_partitions_a"
    --partition="product_a:readonly:${PRODUCT_A_SIZE}:qti_dynamic_partitions_a"
    --partition="vendor_a:readonly:${VENDOR_A_SIZE}:qti_dynamic_partitions_a"
    --partition="odm_a:readonly:${ODM_A_SIZE}:qti_dynamic_partitions_a"
  )
fi

lpmake_args+=(
  --group="qti_dynamic_partitions_b:${GROUP_B_MAX}"
  --partition="system_b:readonly:${SYSTEM_B_SIZE}:qti_dynamic_partitions_b"
  --partition="system_ext_b:readonly:${SYSTEM_EXT_B_SIZE}:qti_dynamic_partitions_b"
  --partition="product_b:readonly:${PRODUCT_B_SIZE}:qti_dynamic_partitions_b"
  --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b"
  --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b"
  --image="system_b=${SYSTEM_IMG}"
  --image="system_ext_b=${SYSTEM_EXT_IMG}"
  --image="product_b=${PRODUCT_IMG}"
  --image="vendor_b=${VENDOR_IMG}"
  --image="odm_b=${ODM_IMG}"
  --block-size=4096
  --sparse
  --output="$OUT_IMG"
)

"$LPMake" "${lpmake_args[@]}"

if ! "$LPDump" "$OUT_IMG" > "${OUT_IMG}.lpdump.txt" 2>/dev/null; then
  prefix_raw="${OUT_IMG}.prefix.raw"
  dump_sparse_prefix "$OUT_IMG" "$prefix_raw"
  "$LPDump" "$prefix_raw" > "${OUT_IMG}.lpdump.txt"
  rm -f "$prefix_raw"
fi

{
  echo "super_image=${OUT_IMG}"
  echo "variant=${variant}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_IMG" "$SYSTEM_IMG" "$SYSTEM_EXT_IMG" "$PRODUCT_IMG" "$VENDOR_IMG" "$ODM_IMG"
} > "${OUT_IMG}.SHA256SUMS.txt"

echo "Built: ${OUT_IMG}"
echo "Metadata dump: ${OUT_IMG}.lpdump.txt"
echo "Manifest: ${OUT_IMG}.SHA256SUMS.txt"
