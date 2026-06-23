#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
LPMake="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDump="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUnpack="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
RESIZE2FS="${RESIZE2FS:-/opt/homebrew/opt/e2fsprogs/sbin/resize2fs}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"

VARIANT="v0.34-system-b-ext4-grow-nofec"
SOURCE_VARIANT="v0.33-system-b-grow-noop"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.33-system-b-grow-noop.sparse.img}"
SOURCE_SHA256="${SOURCE_SHA256:-39e39965290b68a8980df8eaa090c2440000967f2f80648dc6a7316753165767}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
EXTRACT_DIR="${WORK_DIR}/source-v033-slot1"
SOURCE_RAW="${WORK_DIR}/source-v033-super.raw.img"
CANDIDATE_RAW="${WORK_DIR}/candidate-v034-super.raw.img"
CANDIDATE_EXTRACT_DIR="${WORK_DIR}/candidate-v034-slot1"
OUT_RAW_FOR_LPDUMP="${WORK_DIR}/candidate-v034-super.raw-for-lpdump.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"

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
SYSTEM_B_SOURCE_EXT4_SIZE=3000860672
SYSTEM_B_NOFEC_EXT4_SIZE=3158134784
SYSTEM_B_NOFEC_BLOCKS=771029
SYSTEM_B_NOFEC_OVERHEAD_BYTES=$((SYSTEM_B_PARTITION_SIZE - SYSTEM_B_NOFEC_EXT4_SIZE))
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"

SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_SIZE=171110400
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768

PURPOSE="Offline ext4 capacity gate on top of live-verified v0.33. It keeps partition layout at the v0.33 grown system_b size, expands the system_b ext4 filesystem to the maximum no-FEC AVB hashtree data size, rebuilds system_b hashtree footer without FEC because Android fec is not available locally, and preserves all package/file payloads."

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.34-system-b-ext4-grow-nofec.sh

Build the v0.34 offline ext4 capacity candidate on top of live-verified v0.33.
This is intentionally an offline-only no-FEC gate unless explicitly promoted.
It does not flash, reboot, erase misc, write settings, clear package cache, or
mutate /data.
USAGE
}

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

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

copy_clone_or_plain() {
  local src="$1"
  local dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
}

fsck_rw() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

check_size() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
}

compare_system_files() {
  python3 - "$DEBUGFS" "${EXTRACT_DIR}/system_b.img" "${CANDIDATE_EXTRACT_DIR}/system_b.img" "$ROOT_DIR" "${WORK_DIR}/file-compare" <<'PY'
from __future__ import annotations

import csv
import hashlib
import subprocess
import sys
from pathlib import Path

debugfs = Path(sys.argv[1])
source_img = Path(sys.argv[2])
candidate_img = Path(sys.argv[3])
root = Path(sys.argv[4])
out_dir = Path(sys.argv[5])
out_dir.mkdir(parents=True, exist_ok=True)

packages_tsv = root / "reverse/smartisan-8.5.3-rom-static/indexes/packages.tsv"
paths: set[str] = set()
with packages_tsv.open(encoding="utf-8") as fh:
    for row in csv.DictReader(fh, delimiter="\t"):
        if row.get("partition") != "system":
            continue
        rel_path = row.get("rel_path") or ""
        if not rel_path.endswith(".apk"):
            continue
        if rel_path.startswith("system/"):
            rel_path = rel_path[len("system/") :]
        paths.add("/system/" + rel_path)

paths.update(
    {
        "/system/framework/framework-res.apk",
        "/system/framework/framework.jar",
        "/system/framework/services.jar",
        "/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk",
        "/system/etc/security/otacerts.zip",
        "/system/etc/permissions/privapp-permissions-platform.xml",
        "/system/etc/sysconfig/hiddenapi-package-whitelist.xml",
    }
)

def exists(image: Path, path: str) -> bool:
    result = subprocess.run([str(debugfs), "-R", f"stat {path}", str(image)], text=True, capture_output=True)
    text = result.stdout + result.stderr
    return result.returncode == 0 and "File not found" not in text

def dump_hash(image: Path, path: str, label: str) -> str:
    safe = path.strip("/").replace("/", "__")
    dest = out_dir / f"{label}-{safe}"
    if dest.exists():
        dest.unlink()
    result = subprocess.run([str(debugfs), "-R", f"dump {path} {dest}", str(image)], text=True, capture_output=True)
    if result.returncode != 0 or not dest.exists():
        raise SystemExit(f"dump failed for {path} from {label}: {result.stdout}{result.stderr}")
    return hashlib.sha256(dest.read_bytes()).hexdigest()

checked = 0
for path in sorted(paths):
    source_present = exists(source_img, path)
    candidate_present = exists(candidate_img, path)
    if source_present != candidate_present:
        raise SystemExit(f"presence changed for {path}: source={source_present} candidate={candidate_present}")
    if not source_present:
        continue
    source_hash = dump_hash(source_img, path, "source")
    candidate_hash = dump_hash(candidate_img, path, "candidate")
    if source_hash != candidate_hash:
        raise SystemExit(f"content changed for {path}: source={source_hash} candidate={candidate_hash}")
    checked += 1

print(f"system_file_compare=PASS checked={checked}")
PY
}

dump_lpdump() {
  rm -f "$OUT_RAW_FOR_LPDUMP"
  "$SIMG2IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP"
  check_size "candidate raw super for lpdump" "$OUT_RAW_FOR_LPDUMP" "$SUPER_SIZE"
  for slot in 0 1; do
    "$LPDump" -s "$slot" "$OUT_RAW_FOR_LPDUMP" > "${OUT_SPARSE}.lpdump-slot${slot}.txt"
  done
  cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"
  rm -f "$OUT_RAW_FOR_LPDUMP"
}

verify_candidate_extract() {
  rm -f "$CANDIDATE_RAW"
  rm -rf "$CANDIDATE_EXTRACT_DIR"
  mkdir -p "$CANDIDATE_EXTRACT_DIR"
  "$SIMG2IMG" "$OUT_SPARSE" "$CANDIDATE_RAW"
  check_size "candidate raw super" "$CANDIDATE_RAW" "$SUPER_SIZE"
  "$LPUnpack" --slot=1 "$CANDIDATE_RAW" "$CANDIDATE_EXTRACT_DIR" >/dev/null
  rm -f "$CANDIDATE_RAW"

  local part source_hash candidate_hash
  for part in system_a product_a vendor_a odm_a system_ext_b product_b vendor_b odm_b; do
    source_hash="$(sha256_one "${EXTRACT_DIR}/${part}.img")"
    candidate_hash="$(sha256_one "${CANDIDATE_EXTRACT_DIR}/${part}.img")"
    [ "$source_hash" = "$candidate_hash" ] || die "${part} changed unexpectedly"
    printf '%s\tretained_sha256=%s\n' "$part" "$candidate_hash"
  done

  source_hash="$(sha256_one "$SYSTEM_B_IMG")"
  candidate_hash="$(sha256_one "${CANDIDATE_EXTRACT_DIR}/system_b.img")"
  [ "$source_hash" = "$candidate_hash" ] || die "candidate system_b does not match built image"
  printf 'system_b\tgrown_nofec_sha256=%s\n' "$candidate_hash"
}

case "${1:-}" in
  "")
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

need_executable "$SIMG2IMG"
need_executable "$LPMake"
need_executable "$LPDump"
need_executable "$LPUnpack"
need_executable "$E2FSCK"
need_executable "$RESIZE2FS"
need_executable "$DEBUGFS"
need_file "$AVBTOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"

mkdir -p "$WORK_DIR" "$EXTRACT_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$SOURCE_RAW" "$CANDIDATE_RAW" \
  "$OUT_RAW_FOR_LPDUMP" "${OUT_SPARSE}.lpdump"* "${OUT_SPARSE}.SHA256SUMS.txt"

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline-only; no-FEC candidate requires explicit promotion before live flashing"
  echo

  echo "## source"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_sparse_sha256=${SOURCE_SHA256}"
  echo

  echo "## extract source super"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
  check_size "source raw super" "$SOURCE_RAW" "$SUPER_SIZE"
  "$LPUnpack" --slot=1 "$SOURCE_RAW" "$EXTRACT_DIR" >/dev/null
  rm -f "$SOURCE_RAW"

  check_size system_a "${EXTRACT_DIR}/system_a.img" "$SYSTEM_A_SIZE"
  check_size product_a "${EXTRACT_DIR}/product_a.img" "$PRODUCT_A_SIZE"
  check_size vendor_a "${EXTRACT_DIR}/vendor_a.img" "$VENDOR_A_SIZE"
  check_size odm_a "${EXTRACT_DIR}/odm_a.img" "$ODM_A_SIZE"
  check_size system_b_source "${EXTRACT_DIR}/system_b.img" "$SYSTEM_B_PARTITION_SIZE"
  check_size system_ext_b "${EXTRACT_DIR}/system_ext_b.img" "$SYSTEM_EXT_B_SIZE"
  check_size product_b "${EXTRACT_DIR}/product_b.img" "$PRODUCT_B_SIZE"
  check_size vendor_b "${EXTRACT_DIR}/vendor_b.img" "$VENDOR_B_SIZE"
  check_size odm_b "${EXTRACT_DIR}/odm_b.img" "$ODM_B_SIZE"
  echo "extract=PASS"
  echo

  echo "## grow system_b ext4"
  python3 "$AVBTOOL" info_image --image "${EXTRACT_DIR}/system_b.img" > "${WORK_DIR}/source-system-b-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/source-system-b-avb-info.txt" || die "source system_b is not the expected FEC footer form"
  source_blocks="$(debugfs_stat_value "${EXTRACT_DIR}/system_b.img" "Block count")"
  source_free_blocks="$(debugfs_stat_value "${EXTRACT_DIR}/system_b.img" "Free blocks")"
  echo "source_system_b_block_count=${source_blocks}"
  echo "source_system_b_free_blocks=${source_free_blocks}"

  copy_clone_or_plain "${EXTRACT_DIR}/system_b.img" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size "system_b pure ext4 after erase_footer" "$SYSTEM_B_IMG" "$SYSTEM_B_SOURCE_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  truncate -s "$SYSTEM_B_NOFEC_EXT4_SIZE" "$SYSTEM_B_IMG"
  "$RESIZE2FS" -f "$SYSTEM_B_IMG" "$SYSTEM_B_NOFEC_BLOCKS" >/dev/null
  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  grown_blocks="$(debugfs_stat_value "$SYSTEM_B_IMG" "Block count")"
  grown_free_blocks="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  [ "$grown_blocks" = "$SYSTEM_B_NOFEC_BLOCKS" ] || die "grown block count mismatch: ${grown_blocks} != ${SYSTEM_B_NOFEC_BLOCKS}"
  echo "grown_system_b_block_count=${grown_blocks}"
  echo "grown_system_b_free_blocks=${grown_free_blocks}"
  echo "system_b_ext4_growth_blocks=$((grown_blocks - source_blocks))"
  echo "system_b_ext4_growth_bytes=$((SYSTEM_B_NOFEC_EXT4_SIZE - SYSTEM_B_SOURCE_EXT4_SIZE))"
  echo "system_b_nofec_avb_overhead_bytes=${SYSTEM_B_NOFEC_OVERHEAD_BYTES}"

  python3 "$AVBTOOL" add_hashtree_footer \
    --image "$SYSTEM_B_IMG" \
    --partition_size "$SYSTEM_B_PARTITION_SIZE" \
    --partition_name system \
    --hash_algorithm sha1 \
    --salt "$SYSTEM_B_SALT" \
    --block_size 4096 \
    --do_not_generate_fec \
    --prop com.android.build.system.fingerprint:qti/aries/aries:11/RKQ1.201217.002/1658135499:user/dev-keys \
    --prop com.android.build.system.os_version:11 \
    --prop com.android.build.system.security_patch:2022-06-10 \
    --prop com.android.build.system.security_patch:2022-06-10
  check_size "system_b no-FEC image" "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/candidate-system-b-avb-info.txt"
  grep -q "Original image size:      ${SYSTEM_B_NOFEC_EXT4_SIZE} bytes" "${WORK_DIR}/candidate-system-b-avb-info.txt" || die "candidate original image size mismatch"
  grep -q "FEC num roots:         0" "${WORK_DIR}/candidate-system-b-avb-info.txt" || die "candidate still has FEC roots"
  cat "${WORK_DIR}/candidate-system-b-avb-info.txt"
  echo

  echo "## rebuild sparse super"
  "$LPMake" \
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
    --partition="product_b:readonly:${PRODUCT_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b" \
    --image="system_a=${EXTRACT_DIR}/system_a.img" \
    --image="product_a=${EXTRACT_DIR}/product_a.img" \
    --image="vendor_a=${EXTRACT_DIR}/vendor_a.img" \
    --image="odm_a=${EXTRACT_DIR}/odm_a.img" \
    --image="system_b=${SYSTEM_B_IMG}" \
    --image="system_ext_b=${EXTRACT_DIR}/system_ext_b.img" \
    --image="product_b=${EXTRACT_DIR}/product_b.img" \
    --image="vendor_b=${EXTRACT_DIR}/vendor_b.img" \
    --image="odm_b=${EXTRACT_DIR}/odm_b.img" \
    --block-size=4096 \
    --sparse \
    --output="$OUT_SPARSE"
  dump_lpdump
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=$(sha256_one "$OUT_SPARSE")"
  echo

  echo "## verify candidate extraction"
  verify_candidate_extract
  compare_system_files
  echo

  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline-only; no-FEC candidate requires explicit promotion before live flashing"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse_super=${SOURCE_SPARSE}"
    echo "source_sparse_super_sha256=${SOURCE_SHA256}"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=$(sha256_one "$OUT_SPARSE")"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=$(sha256_one "$SYSTEM_B_IMG")"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_source_ext4_size=${SYSTEM_B_SOURCE_EXT4_SIZE}"
    echo "system_b_nofec_ext4_size=${SYSTEM_B_NOFEC_EXT4_SIZE}"
    echo "system_b_ext4_growth_bytes=$((SYSTEM_B_NOFEC_EXT4_SIZE - SYSTEM_B_SOURCE_EXT4_SIZE))"
    echo "system_b_nofec_avb_overhead_bytes=${SYSTEM_B_NOFEC_OVERHEAD_BYTES}"
    echo "source_system_b_block_count=${source_blocks}"
    echo "source_system_b_free_blocks=${source_free_blocks}"
    echo "grown_system_b_block_count=${grown_blocks}"
    echo "grown_system_b_free_blocks=${grown_free_blocks}"
    echo "fec_status=not_generated"
    echo "vbmeta_prereq=live vbmeta_b and vbmeta_system_b flags were manually probed as 3 before this offline gate"
    echo "offline_report=${REPORT}"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

  echo "manifest=${MANIFEST}"
  echo "result=PASS_OFFLINE_IMAGE_NOFEC"
} 2>&1 | tee "$REPORT"

echo "report=${REPORT}"
