#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.17-all-apk-only-locale-prune"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img"
EXPECTED_PRODUCT_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
EXPECTED_SYSTEM_EXT_IMG="${ROOT_DIR}/hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
V017A_REPORT="${ROOT_DIR}/hard-rom/inspect/v0.17a-system-apk-only-locale-prune/verify-v0.17a-offline-image-20260618-124311.txt"
V017B_REPORT="${ROOT_DIR}/hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune/verify-v0.17b-offline-image-20260618-130101.txt"

SYSTEM_SHA256="d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5"
PRODUCT_SHA256="7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8"
SYSTEM_EXT_SHA256="742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.17-all-apk-only-locale-prune.sh --offline-image

Verifies the generated v0.17-all sparse super:
  - v0.17a and v0.17b source image reports are present and passed
  - source partition images match their known hashes
  - sparse system_b, product_b, and system_ext_b logical slices match those images

The script never flashes, reboots, erases misc, or changes /data.
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

require_marker() {
  local path="$1"
  local marker="$2"
  grep -Fq "$marker" "$path" || die "missing marker in ${path}: ${marker}"
}

run_offline_image() {
  need_executable "$SPARSE_TOOL"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$EXPECTED_PRODUCT_IMG"
  need_file "$EXPECTED_SYSTEM_EXT_IMG"
  need_file "$V017A_REPORT"
  need_file "$V017B_REPORT"

  require_hash "$EXPECTED_SYSTEM_IMG" "$SYSTEM_SHA256"
  require_hash "$EXPECTED_PRODUCT_IMG" "$PRODUCT_SHA256"
  require_hash "$EXPECTED_SYSTEM_EXT_IMG" "$SYSTEM_EXT_SHA256"
  require_marker "$V017A_REPORT" "PASS: v0.17a offline image verification"
  require_marker "$V017B_REPORT" "PASS: v0.17b offline image verification"

  mkdir -p "$INSPECT_DIR"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.17-all-offline-image-${timestamp}.txt"

  {
    echo "# v0.17-all-apk-only-locale-prune offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo "expected_product_img=${EXPECTED_PRODUCT_IMG}"
    echo "expected_system_ext_img=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## source reports"
    echo "v0.17a_report=${V017A_REPORT}"
    echo "v0.17a_report_pass=ok"
    echo "v0.17b_report=${V017B_REPORT}"
    echo "v0.17b_report_pass=ok"
    echo

    echo "## sparse slices"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "product_b=${EXPECTED_PRODUCT_IMG}"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_ext_b=${EXPECTED_SYSTEM_EXT_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" "$EXPECTED_PRODUCT_IMG" "$EXPECTED_SYSTEM_EXT_IMG"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.17-all offline image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

case "${1:---offline-image}" in
  --offline-image)
    run_offline_image
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
