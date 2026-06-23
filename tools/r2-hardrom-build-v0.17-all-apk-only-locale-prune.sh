#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.17a-system-apk-only-locale-prune.img"
PRODUCT_IMG="${OUT_DIR}/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
SYSTEM_EXT_IMG="${OUT_DIR}/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.SHA256SUMS.txt"

BASE_SHA256="313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5"
SYSTEM_SHA256="d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5"
PRODUCT_SHA256="7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8"
SYSTEM_EXT_SHA256="742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.17-all-apk-only-locale-prune.sh

Build an offline v0.17-all exact-current sparse candidate from stable v0.4.
It combines already verified v0.17a system_b and v0.17b product_b/system_ext_b
partition images into one flashable sparse super. It does not rebuild APKs,
modify ext4 filesystems, flash, reboot, erase misc, or change /data.

Flashing still requires explicit user confirmation for this exact variant.
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

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
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

need_file "$BASE_SPARSE"
need_file "$SYSTEM_IMG"
need_file "$PRODUCT_IMG"
need_file "$SYSTEM_EXT_IMG"
need_executable "$SPARSE_TOOL"

require_hash "$BASE_SPARSE" "$BASE_SHA256"
require_hash "$SYSTEM_IMG" "$SYSTEM_SHA256"
require_hash "$PRODUCT_IMG" "$PRODUCT_SHA256"
require_hash "$SYSTEM_EXT_IMG" "$SYSTEM_EXT_SHA256"

mkdir -p "$OUT_DIR"
rm -f "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Combining v0.17a system_b with v0.17b product_b/system_ext_b..."
"$SPARSE_TOOL" \
  --source-sparse "$BASE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "system_b=${SYSTEM_IMG}" \
  --image "product_b=${PRODUCT_IMG}" \
  --image "system_ext_b=${SYSTEM_EXT_IMG}" \
  --variant "otatrust-v0.17-all-apk-only-locale-prune-exact-current"

super_hash="$(sha256_one "$OUT_SPARSE")"

{
  echo "variant=otatrust-v0.17-all-apk-only-locale-prune-exact-current"
  echo "purpose=Combine v0.17a system_b and v0.17b product_b/system_ext_b APK-only English/Chinese resources.arsc hard-prune images into one flashable sparse super"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partitions=system_b,product_b,system_ext_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "product_image=${PRODUCT_IMG}"
  echo "system_ext_image=${SYSTEM_EXT_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "system_b_sha256=${SYSTEM_SHA256}"
  echo "product_b_sha256=${PRODUCT_SHA256}"
  echo "system_ext_b_sha256=${SYSTEM_EXT_SHA256}"
  echo "sparse_super_sha256=${super_hash}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_SPARSE" "$BASE_SPARSE" "$SYSTEM_IMG" "$PRODUCT_IMG" "$SYSTEM_EXT_IMG"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
