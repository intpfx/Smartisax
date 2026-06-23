#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="${VARIANT:-v0.kg1-smartisax-skip-keyguard}"
SOURCE_VARIANT="v0.pm1-pms-cache-allowlist"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.pm1-pms-cache-allowlist.sparse.img}"
SOURCE_SPARSE_SHA256="dd64f8a741dc434763bf6d9518bd0ee74c33cbcf3471121056883f591fc34f52"

OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${SYSTEM_B_IMG:-${OUT_DIR}/system-otatrust-${VARIANT}.img}"
SYSTEM_B_MANIFEST="${OUT_DIR}/system-otatrust-${VARIANT}.SHA256SUMS.txt"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img}"
SPARSE_TOOL_MANIFEST="${OUT_SPARSE}.SHA256SUMS.txt"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/pack-super-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

PURPOSE="Patch the v0.kg1 Smartisax skip-keyguard system_b image into the live-proven v0.pm1 sparse super."
RESULT_NAME="PASS_PACK_SUPER_V0KG1_SMARTISAX_SKIP_KEYGUARD"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-pack-super-v0.kg1-smartisax-skip-keyguard.sh

Packs the offline-built v0.kg1 system_b image into a flashable sparse super by
rewriting only the system_b logical partition range inside the live-proven
v0.pm1 sparse super. This script does not touch a live device.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2); exit}' "$SYSTEM_B_MANIFEST"
}

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_file "$SPARSE_TOOL"
need_file "$SYSTEM_B_MANIFEST"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"

system_b_sha="$(manifest_value system_b_sha256)"
[ -n "$system_b_sha" ] || die "system_b manifest missing system_b_sha256"
require_hash "$SYSTEM_B_IMG" "$system_b_sha"

mkdir -p "$OUT_DIR" "$INSPECT_DIR"
rm -f "$OUT_SPARSE" "$SPARSE_TOOL_MANIFEST" "$MANIFEST"

{
  echo "# ${VARIANT} sparse super pack"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "boundary=offline pack only; no adb, no fastboot, no flash, no reboot, no /data mutation"
  echo

  echo "## inputs"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
  echo "system_b_extent=${SYSTEM_B_EXTENT}"
  echo "system_b_image=${SYSTEM_B_IMG}"
  echo "system_b_sha256=${system_b_sha}"
  echo

  echo "## sparse patch"
  "$SPARSE_TOOL" \
    --source-sparse "$SOURCE_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --out "$OUT_SPARSE" \
    --image "system_b=${SYSTEM_B_IMG}" \
    --variant "$VARIANT"
  echo

  need_file "$SPARSE_TOOL_MANIFEST"
  out_sparse_sha="$(sha256_one "$OUT_SPARSE")"
  tool_out_sparse_sha="$(awk -F= '$1 == "out_sparse_sha256" {print $2; exit}' "$SPARSE_TOOL_MANIFEST")"
  tool_source_sparse_sha="$(awk -F= '$1 == "source_sparse_sha256" {print $2; exit}' "$SPARSE_TOOL_MANIFEST")"
  tool_system_b_sha="$(awk -F= '$1 == "system_b_sha256" {print $2; exit}' "$SPARSE_TOOL_MANIFEST")"
  tool_system_b_slice_sha="$(awk -F= '$1 == "system_b_slice_sha256" {print $2; exit}' "$SPARSE_TOOL_MANIFEST")"

  [ "$tool_out_sparse_sha" = "$out_sparse_sha" ] || die "sparse manifest output hash mismatch"
  [ "$tool_source_sparse_sha" = "$SOURCE_SPARSE_SHA256" ] || die "sparse manifest source hash mismatch"
  [ "$tool_system_b_sha" = "$system_b_sha" ] || die "sparse manifest system_b hash mismatch"
  [ "$tool_system_b_slice_sha" = "$system_b_sha" ] || die "sparse system_b slice hash mismatch"
  echo "out_sparse_sha256=${out_sparse_sha}"
  echo "sparse_tool_manifest=${SPARSE_TOOL_MANIFEST}"
  echo

  echo "## sparse range verify"
  "$SPARSE_TOOL" \
    --source-sparse "$OUT_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --verify-image "system_b=${SYSTEM_B_IMG}"
  echo

  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "boundary=offline pack only; explicit user confirmation required before any live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse=${SOURCE_SPARSE}"
    echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
    echo "system_b_extent=${SYSTEM_B_EXTENT}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_b_sha}"
    echo "super_sparse_image=${OUT_SPARSE}"
    echo "super_sparse_sha256=${out_sparse_sha}"
    echo "sparse_tool_manifest=${SPARSE_TOOL_MANIFEST}"
    echo "patched_partitions=system_b"
    echo "pack_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_SPARSE"
  } > "$MANIFEST"

  echo "super_sparse_image=${OUT_SPARSE}"
  echo "super_sparse_sha256=${out_sparse_sha}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} | tee "$REPORT"

echo "Sparse super: $OUT_SPARSE"
echo "Manifest: $MANIFEST"
echo "Report: $REPORT"
