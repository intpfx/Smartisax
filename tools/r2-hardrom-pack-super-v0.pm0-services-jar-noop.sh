#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"

VARIANT="${VARIANT:-v0.pm0-services-jar-noop}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/super"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
RETAINED_DIR="${RETAINED_DIR:-${ROOT_DIR}/hard-rom/work/v0.43e-textboom-codepath-arm64-runtime-repair/source-v043d-retained-slot1}"

SYSTEM_B_IMG="${SYSTEM_B_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.pm0-services-jar-noop.img}"
PRODUCT_B_IMG="${PRODUCT_B_IMG:-${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img}"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img}"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/pack-super-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SUPER_SIZE=10737418240
METADATA_SIZE=65536
METADATA_SLOTS=3
GROUP_A_MAX=5364514816
GROUP_B_MAX=5364514816

SYSTEM_A_SIZE=3052314624
PRODUCT_A_SIZE=255815680
VENDOR_A_SIZE=941768704
ODM_A_SIZE=917504
SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_PARTITION_SIZE=171110400
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768

SYSTEM_B_SHA256="e6341016f5f453f5734916c88fa3efaa51c937f9533f58b9e36cf36a3a43440e"
PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"
SYSTEM_A_SHA256="ed8dc9ba6a704f5cd9eb9fa812dbcfce860a219fe2d6c47404f06cd575a32108"
PRODUCT_A_SHA256="582138953c49dd7600e62c892ea238821aa9a81e96909c64746efee424a93a00"
VENDOR_A_SHA256="bd9be6dc075740e3e5ec214a617fddb54763d330a4ece3f3987c73e2097e344d"
ODM_A_SHA256="20103d3dde8c2085fc3d85b35f933bf0699371ae60a4e288b3e6c8ae51a559dd"
SYSTEM_EXT_B_SHA256="3f994cb1a7f2e82af007969ce7035e0ded83da90a0bef20f6142ac7e303c4f6a"
VENDOR_B_SHA256="d6e09ff25c612cc7f01c05f455646926019e17b1fe73b98f6ab7c0d5b69489f6"
ODM_B_SHA256="8ffd2ccb8585e8cfb6ea7bcd108057025e33d47da4a5992fdd3ad71eb515474b"

PURPOSE="Pack the offline-verified v0.pm0 system_b image into a flashable sparse super without generating a raw 10 GiB super."
RESULT_NAME="PASS_PACK_SUPER_V0PM0_SERVICES_JAR_NOOP"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-pack-super-v0.pm0-services-jar-noop.sh

Packs the offline-verified v0.pm0 system_b image into a sparse super image.
This script does not touch a live device.

It avoids a full raw super by:
  - using lpmake --sparse directly
  - dumping only the sparse logical prefix for lpdump metadata
  - streaming sparse logical ranges to verify partition SHA256 slices
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

check_size() {
  local label="$1" path="$2" expected="$3" actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
}

dump_sparse_prefix() {
  local image="$1" output="$2"
  python3 - "$image" "$output" <<'PY'
import struct
import sys
from pathlib import Path

src = Path(sys.argv[1])
out = Path(sys.argv[2])
limit = 16 * 1024 * 1024

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

verify_sparse_partition_hashes() {
  local sparse="$1" lpdump_slot1="$2" out_tsv="$3"
  python3 - "$sparse" "$lpdump_slot1" "$out_tsv" <<'PY'
import hashlib
import re
import struct
import sys
from pathlib import Path

sparse = Path(sys.argv[1])
lpdump = Path(sys.argv[2])
out_tsv = Path(sys.argv[3])

expected = {
    "system_a": ("ed8dc9ba6a704f5cd9eb9fa812dbcfce860a219fe2d6c47404f06cd575a32108", 3052314624),
    "product_a": ("582138953c49dd7600e62c892ea238821aa9a81e96909c64746efee424a93a00", 255815680),
    "vendor_a": ("bd9be6dc075740e3e5ec214a617fddb54763d330a4ece3f3987c73e2097e344d", 941768704),
    "odm_a": ("20103d3dde8c2085fc3d85b35f933bf0699371ae60a4e288b3e6c8ae51a559dd", 917504),
    "system_b": ("e6341016f5f453f5734916c88fa3efaa51c937f9533f58b9e36cf36a3a43440e", 3183276032),
    "system_ext_b": ("3f994cb1a7f2e82af007969ce7035e0ded83da90a0bef20f6142ac7e303c4f6a", 296116224),
    "product_b": ("21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57", 171110400),
    "vendor_b": ("d6e09ff25c612cc7f01c05f455646926019e17b1fe73b98f6ab7c0d5b69489f6", 868663296),
    "odm_b": ("8ffd2ccb8585e8cfb6ea7bcd108057025e33d47da4a5992fdd3ad71eb515474b", 1056768),
}

text = lpdump.read_text(encoding="utf-8")
extents = {}
current = None
for line in text.splitlines():
    name_match = re.match(r"\s*Name:\s+(\S+)\s*$", line)
    if name_match:
        current = name_match.group(1)
        continue
    extent_match = re.match(r"\s*0\s+\.\.\s+(\d+)\s+linear\s+super\s+(\d+)\s*$", line)
    if extent_match and current:
        end_sector = int(extent_match.group(1))
        start_sector = int(extent_match.group(2))
        extents[current] = (start_sector * 512, (end_sector + 1) * 512, start_sector, end_sector + 1)

missing = sorted(set(expected) - set(extents))
if missing:
    raise SystemExit(f"missing lpdump extents: {missing}")

def sparse_ranges(path: Path):
    with path.open("rb") as f:
        header = f.read(28)
        magic, major, minor, file_hdr_sz, chunk_hdr_sz, block_size, total_blocks, total_chunks, checksum = struct.unpack(
            "<IHHHHIIII", header
        )
        if magic != 0xED26FF3A:
            raise SystemExit("not an Android sparse image")
        if total_blocks * block_size != 10737418240:
            raise SystemExit(f"unexpected sparse logical size: {total_blocks * block_size}")
        if file_hdr_sz > 28:
            f.read(file_hdr_sz - 28)
        logical = 0
        for _ in range(total_chunks):
            chunk_header = f.read(12)
            if len(chunk_header) != 12:
                raise SystemExit("truncated sparse chunk header")
            chunk_type, reserved, chunk_blocks, total_size = struct.unpack("<HHII", chunk_header)
            data_size = total_size - chunk_hdr_sz
            logical_size = chunk_blocks * block_size
            data_offset = f.tell()
            if chunk_type == 0xCAC1:
                yield logical, logical_size, "raw", data_offset, None
                f.seek(data_size, 1)
            elif chunk_type == 0xCAC2:
                fill = f.read(4)
                if data_size > 4:
                    f.seek(data_size - 4, 1)
                yield logical, logical_size, "fill", None, fill
            elif chunk_type == 0xCAC3:
                if data_size:
                    f.seek(data_size, 1)
                yield logical, logical_size, "zero", None, None
            elif chunk_type == 0xCAC4:
                if data_size:
                    f.seek(data_size, 1)
            else:
                raise SystemExit(f"unknown sparse chunk type: {chunk_type:#x}")
            logical += logical_size

def update_zero(h, length):
    zero = b"\0" * (1024 * 1024)
    while length:
        take = min(length, len(zero))
        h.update(zero[:take])
        length -= take

def update_fill(h, fill, length):
    block = (fill * ((1024 * 1024 + len(fill) - 1) // len(fill)))[:1024 * 1024]
    while length:
        take = min(length, len(block))
        h.update(block[:take])
        length -= take

def hash_sparse_range(path: Path, start: int, length: int) -> str:
    h = hashlib.sha256()
    end = start + length
    with path.open("rb") as f:
        for logical, logical_size, kind, data_offset, fill in sparse_ranges(path):
            chunk_end = logical + logical_size
            if chunk_end <= start:
                continue
            if logical >= end:
                break
            take_start = max(start, logical)
            take_end = min(end, chunk_end)
            take_len = take_end - take_start
            if take_len <= 0:
                continue
            chunk_offset = take_start - logical
            if kind == "raw":
                f.seek(data_offset + chunk_offset)
                remaining = take_len
                while remaining:
                    data = f.read(min(1024 * 1024, remaining))
                    if not data:
                        raise SystemExit("truncated raw sparse chunk data")
                    h.update(data)
                    remaining -= len(data)
            elif kind == "fill":
                phase = chunk_offset % len(fill)
                if phase:
                    prefix = fill[phase:] + fill[:phase]
                    first = min(take_len, len(fill) - phase)
                    h.update(prefix[:first])
                    take_len -= first
                if take_len:
                    update_fill(h, fill, take_len)
            elif kind == "zero":
                update_zero(h, take_len)
    return h.hexdigest()

lines = ["partition\tstart_sector\tsector_count\tsize_bytes\tsha256\tstatus"]
for name in sorted(expected):
    expected_hash, expected_size = expected[name]
    start, length, start_sector, sector_count = extents[name]
    if length != expected_size:
        raise SystemExit(f"{name} size mismatch from lpdump: {length} != {expected_size}")
    digest = hash_sparse_range(sparse, start, length)
    if digest != expected_hash:
        raise SystemExit(f"{name} sparse slice hash mismatch: {digest} != {expected_hash}")
    lines.append(f"{name}\t{start_sector}\t{sector_count}\t{length}\t{digest}\tPASS")

out_tsv.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("sparse_partition_hashes=ok")
print(out_tsv)
PY
}

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_executable "$LPMAKE"
need_executable "$LPDUMP"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"

SYSTEM_A_IMG="${RETAINED_DIR}/system_a.img"
PRODUCT_A_IMG="${RETAINED_DIR}/product_a.img"
VENDOR_A_IMG="${RETAINED_DIR}/vendor_a.img"
ODM_A_IMG="${RETAINED_DIR}/odm_a.img"
SYSTEM_EXT_B_IMG="${RETAINED_DIR}/system_ext_b.img"
VENDOR_B_IMG="${RETAINED_DIR}/vendor_b.img"
ODM_B_IMG="${RETAINED_DIR}/odm_b.img"

rm -f "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"
rm -f "${WORK_DIR}/candidate-super-prefix.raw.img" "${WORK_DIR}/sparse-partition-hashes.tsv"

{
  echo "# ${VARIANT} sparse super pack"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline sparse super candidate only; explicit user confirmation required before live flash"
  echo

  echo "## inputs"
  check_size system_a "$SYSTEM_A_IMG" "$SYSTEM_A_SIZE"
  check_size product_a "$PRODUCT_A_IMG" "$PRODUCT_A_SIZE"
  check_size vendor_a "$VENDOR_A_IMG" "$VENDOR_A_SIZE"
  check_size odm_a "$ODM_A_IMG" "$ODM_A_SIZE"
  check_size system_b "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  check_size system_ext_b "$SYSTEM_EXT_B_IMG" "$SYSTEM_EXT_B_SIZE"
  check_size product_b "$PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE"
  check_size vendor_b "$VENDOR_B_IMG" "$VENDOR_B_SIZE"
  check_size odm_b "$ODM_B_IMG" "$ODM_B_SIZE"

  require_hash "$SYSTEM_A_IMG" "$SYSTEM_A_SHA256"
  require_hash "$PRODUCT_A_IMG" "$PRODUCT_A_SHA256"
  require_hash "$VENDOR_A_IMG" "$VENDOR_A_SHA256"
  require_hash "$ODM_A_IMG" "$ODM_A_SHA256"
  require_hash "$SYSTEM_B_IMG" "$SYSTEM_B_SHA256"
  require_hash "$SYSTEM_EXT_B_IMG" "$SYSTEM_EXT_B_SHA256"
  require_hash "$PRODUCT_B_IMG" "$PRODUCT_B_SHA256"
  require_hash "$VENDOR_B_IMG" "$VENDOR_B_SHA256"
  require_hash "$ODM_B_IMG" "$ODM_B_SHA256"
  echo "input_hashes=ok"
  echo

  echo "## lpmake"
  "$LPMAKE" \
    --metadata-size="$METADATA_SIZE" \
    --metadata-slots="$METADATA_SLOTS" \
    --super-name=super \
    --device="super:${SUPER_SIZE}" \
    --group="qti_dynamic_partitions_a:${GROUP_A_MAX}" \
    --group="qti_dynamic_partitions_b:${GROUP_B_MAX}" \
    --partition="system_a:readonly:${SYSTEM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="product_a:readonly:${PRODUCT_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="vendor_a:readonly:${VENDOR_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="odm_a:readonly:${ODM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="system_b:readonly:${SYSTEM_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="system_ext_b:readonly:${SYSTEM_EXT_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="product_b:readonly:${PRODUCT_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b" \
    --image="system_a=${SYSTEM_A_IMG}" \
    --image="product_a=${PRODUCT_A_IMG}" \
    --image="vendor_a=${VENDOR_A_IMG}" \
    --image="odm_a=${ODM_A_IMG}" \
    --image="system_b=${SYSTEM_B_IMG}" \
    --image="system_ext_b=${SYSTEM_EXT_B_IMG}" \
    --image="product_b=${PRODUCT_B_IMG}" \
    --image="vendor_b=${VENDOR_B_IMG}" \
    --image="odm_b=${ODM_B_IMG}" \
    --block-size=4096 \
    --sparse \
    --output="$OUT_SPARSE"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_size=$(size_bytes "$OUT_SPARSE")"
  echo

  echo "## lpdump prefix"
  dump_sparse_prefix "$OUT_SPARSE" "${WORK_DIR}/candidate-super-prefix.raw.img"
  "$LPDUMP" -s 0 "${WORK_DIR}/candidate-super-prefix.raw.img" > "${OUT_SPARSE}.lpdump-slot0.txt"
  "$LPDUMP" -s 1 "${WORK_DIR}/candidate-super-prefix.raw.img" > "${OUT_SPARSE}.lpdump-slot1.txt"
  cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"
  rm -f "${WORK_DIR}/candidate-super-prefix.raw.img"
  echo "lpdump=ok"
  echo

  echo "## sparse slice hashes"
  verify_sparse_partition_hashes "$OUT_SPARSE" "${OUT_SPARSE}.lpdump-slot1.txt" "${WORK_DIR}/sparse-partition-hashes.tsv"
  cat "${WORK_DIR}/sparse-partition-hashes.tsv"
  echo

  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline sparse super candidate only; explicit user confirmation required before live flash"
    echo "source_system_b=${SYSTEM_B_IMG}"
    echo "source_system_b_sha256=${SYSTEM_B_SHA256}"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${SYSTEM_B_SHA256}"
    echo "product_b_image=${PRODUCT_B_IMG}"
    echo "product_b_sha256=${PRODUCT_B_SHA256}"
    echo "retained_dir=${RETAINED_DIR}"
    echo "lpdump_slot0=${OUT_SPARSE}.lpdump-slot0.txt"
    echo "lpdump_slot1=${OUT_SPARSE}.lpdump-slot1.txt"
    echo "sparse_partition_hashes=${WORK_DIR}/sparse-partition-hashes.tsv"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$PRODUCT_B_IMG" \
      "$SYSTEM_A_IMG" "$PRODUCT_A_IMG" "$VENDOR_A_IMG" "$ODM_A_IMG" \
      "$SYSTEM_EXT_B_IMG" "$VENDOR_B_IMG" "$ODM_B_IMG"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

  echo "sparse_super_sha256=${sparse_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} | tee "$REPORT"

echo "Sparse super: $OUT_SPARSE"
echo "Manifest: $MANIFEST"
echo "Report: $REPORT"
echo "Flash gate: explicit user confirmation required."
