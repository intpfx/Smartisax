#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/settingssmartisan-offline"
VERIFY_VARIANTS="${VERIFY_VARIANTS:-v0.6-settings-noop v0.7-locale-filter v0.8-darkmode-ui}"

SETTINGS_APK_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-settingssmartisan-offline-images.sh

Read-only offline verifier for SettingsSmartisan exact-current ROM candidates:
  - v0.6-settings-noop
  - v0.7-locale-filter
  - v0.8-darkmode-ui

It verifies each generated system image contains the expected SettingsSmartisan
APK, each APK has ZIP integrity, and each sparse super's system_b slice matches
the generated system image. It verifies the sparse logical slice directly
without expanding the full raw super.

Environment:
  VERIFY_VARIANTS="v0.25-settings-noop-on-v0.24"  verify a selected variant list
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

compare_file_hash() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local actual_hash
  local expected_hash
  actual_hash="$(sha256_one "$actual")"
  expected_hash="$(sha256_one "$expected")"
  [ "$actual_hash" = "$expected_hash" ] || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$actual"
}

variant_system_img() {
  case "$1" in
    v0.6-settings-noop) printf '%s\n' "${ROOT_DIR}/hard-rom/build/system-otatrust-v0.6-settings-noop.img" ;;
    v0.7-locale-filter) printf '%s\n' "${ROOT_DIR}/hard-rom/build/system-otatrust-v0.7-locale-filter.img" ;;
    v0.8-darkmode-ui) printf '%s\n' "${ROOT_DIR}/hard-rom/build/system-otatrust-v0.8-darkmode-ui.img" ;;
    v0.25-settings-noop-on-v0.24) printf '%s\n' "${ROOT_DIR}/hard-rom/build/system-otatrust-v0.25-settings-noop-on-v0.24.img" ;;
    *) die "unknown variant: $1" ;;
  esac
}

variant_super_img() {
  case "$1" in
    v0.6-settings-noop) printf '%s\n' "${ROOT_DIR}/hard-rom/build/super-otatrust-v0.6-settings-noop-exact-current.sparse.img" ;;
    v0.7-locale-filter) printf '%s\n' "${ROOT_DIR}/hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img" ;;
    v0.8-darkmode-ui) printf '%s\n' "${ROOT_DIR}/hard-rom/build/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img" ;;
    v0.25-settings-noop-on-v0.24) printf '%s\n' "${ROOT_DIR}/hard-rom/build/super-otatrust-v0.25-settings-noop-on-v0.24-exact-current.sparse.img" ;;
    *) die "unknown variant: $1" ;;
  esac
}

variant_expected_apk() {
  case "$1" in
    v0.6-settings-noop) printf '%s\n' "${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-certprobe-noop.apk" ;;
    v0.25-settings-noop-on-v0.24) printf '%s\n' "${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-certprobe-noop.apk" ;;
    v0.7-locale-filter) printf '%s\n' "${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-locale-filter-ja-ko.apk" ;;
    v0.8-darkmode-ui) printf '%s\n' "${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-darkmode-ui.apk" ;;
    *) die "unknown variant: $1" ;;
  esac
}

verify_variant() {
  local variant="$1"
  local dump_dir="$2"
  local system_img
  local super_img
  local expected_apk
  local dumped_apk

  system_img="$(variant_system_img "$variant")"
  super_img="$(variant_super_img "$variant")"
  expected_apk="$(variant_expected_apk "$variant")"
  dumped_apk="${dump_dir}/${variant}-SettingsSmartisan.apk"

  need_file "$system_img"
  need_file "$super_img"
  need_file "$expected_apk"

  echo "## ${variant}"
  "$DEBUGFS" -R "dump ${SETTINGS_APK_PATH} ${dumped_apk}" "$system_img" >/dev/null 2>&1
  compare_file_hash "$dumped_apk" "$expected_apk" "${variant}/SettingsSmartisan.apk"
  unzip -t "$dumped_apk" >/dev/null
  echo "zip_integrity=ok"

  "$SPARSE_TOOL" --source-sparse "$super_img" --verify-image "system_b=${system_img}"

  echo "hashes:"
  shasum -a 256 "$super_img" "$system_img" "$expected_apk"
  echo
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

need_executable "$DEBUGFS"
need_executable "$SPARSE_TOOL"
mkdir -p "$INSPECT_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
dump_dir="${INSPECT_DIR}/offline-${timestamp}"
report="${INSPECT_DIR}/verify-settingssmartisan-offline-${timestamp}.txt"
mkdir -p "$dump_dir"

{
  echo "# SettingsSmartisan offline image verification"
  echo "timestamp=${timestamp}"
  echo "verify_variants=${VERIFY_VARIANTS}"
  echo
  for variant in $VERIFY_VARIANTS; do
    verify_variant "$variant" "$dump_dir"
  done
  echo "PASS"
} | tee "$report"

echo "Report: ${report}"
