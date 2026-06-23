#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.28-wallet-handshaker-debloat"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-v0.28-wallet-handshaker-debloat"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.28-wallet-handshaker-debloat.img"
SOURCE_V027="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.SHA256SUMS.txt"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"

target_packages=(
  "com.smartisanos.wallet"
  "com.smartisanos.smartfolder.aoa"
)

removed_paths=(
  "/system/priv-app/WalletSmartisan"
  "/system/app/HandShaker"
)

retained_paths=(
  "/system/priv-app/MtpService"
  "/system/priv-app/MtpService/MtpService.apk"
  "/system/apex/com.android.mediaprovider"
  "/system/apex/com.android.mediaprovider/priv-app/MediaProvider/MediaProvider.apk"
  "/system/priv-app/MediaProviderLegacy"
  "/system/priv-app/MediaProviderLegacy/MediaProviderLegacy.apk"
)

core_packages=(
  "com.android.settings"
  "com.smartisanos.launcher"
  "com.android.systemui"
  "com.smartisanos.keyguard"
  "com.android.mtp"
  "com.android.providers.media.module"
  "com.android.providers.media"
  "com.android.phone"
)

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.28-wallet-handshaker-debloat.sh --offline-image
  tools/r2-verify-v0.28-wallet-handshaker-debloat.sh --read-only-pre-clean
  tools/r2-verify-v0.28-wallet-handshaker-debloat.sh --read-only

--offline-image verifies the generated v0.28 sparse super:
  - system_b in sparse matches the generated v0.28 system image
  - Wallet and HandShaker package directories are absent from system_b
  - hiddenapi-package-whitelist.xml no longer references their packages
  - MtpService, MediaProvider, and MediaProviderLegacy paths are retained
  - system_ext_b and product_b remain byte-identical to the v0.27 source sparse

--read-only-pre-clean verifies a flashed device without changing /data, while
allowing com.smartisanos.wallet to remain as an updated-system /data/app residue
until the user approves cleanup.

--read-only verifies the final post-cleanup state and expects both target
packages to be absent.

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

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1"
  local path="$2"
  local key="$3"
  local expected
  local actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

latest_report_path() {
  local suffix="$1"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$INSPECT_DIR"
  printf '%s/%s-%s-%s.txt\n' "$INSPECT_DIR" "$REPORT_PREFIX" "$suffix" "$ts"
}

run_offline() {
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$SOURCE_V027"
  need_file "$MANIFEST"
  need_executable "$DEBUGFS"
  need_executable "$E2FSCK"
  need_executable "$SPARSE_TOOL"

  mkdir -p "$WORK_DIR"
  rm -f "${WORK_DIR}"/*.img "${WORK_DIR}"/*.xml

  echo "# ${VARIANT} offline verification"
  date -u +"verified_at=%Y-%m-%dT%H:%M:%SZ"
  echo

  check_manifest_hash "sparse_super" "$EXPECTED_SUPER" "sparse_super_sha256"
  check_manifest_hash "system_b_image" "$EXPECTED_SYSTEM_IMG" "system_b_sha256"
  echo

  echo "## ext4 fsck"
  "$E2FSCK" -fn "$EXPECTED_SYSTEM_IMG" >/dev/null
  echo "system_b_fsck=ok"
  echo

  echo "## sparse system_b slice"
  local extracted_system="${WORK_DIR}/system_b-from-v0.28-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "system_b=${extracted_system}" >/dev/null
  local expected_system_hash
  local extracted_system_hash
  expected_system_hash="$(sha256_one "$EXPECTED_SYSTEM_IMG")"
  extracted_system_hash="$(sha256_one "$extracted_system")"
  [ "$expected_system_hash" = "$extracted_system_hash" ] \
    || die "system_b sparse slice mismatch: ${extracted_system_hash} != ${expected_system_hash}"
  printf 'system_b\timage=%s\tsparse_slice=%s\n' "$expected_system_hash" "$extracted_system_hash"
  echo

  echo "## retained system_ext_b slice"
  local source_system_ext="${WORK_DIR}/system_ext_b-from-v0.27-source.img"
  local out_system_ext="${WORK_DIR}/system_ext_b-from-v0.28-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V027" --extract-image "system_ext_b=${source_system_ext}" >/dev/null
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "system_ext_b=${out_system_ext}" >/dev/null
  local source_system_ext_hash
  local out_system_ext_hash
  source_system_ext_hash="$(sha256_one "$source_system_ext")"
  out_system_ext_hash="$(sha256_one "$out_system_ext")"
  [ "$source_system_ext_hash" = "$out_system_ext_hash" ] \
    || die "system_ext_b changed unexpectedly"
  printf 'system_ext_b\tsource=%s\tout=%s\n' "$source_system_ext_hash" "$out_system_ext_hash"
  echo

  echo "## retained product_b slice"
  local source_product="${WORK_DIR}/product_b-from-v0.27-source.img"
  local out_product="${WORK_DIR}/product_b-from-v0.28-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V027" --extract-image "product_b=${source_product}" >/dev/null
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "product_b=${out_product}" >/dev/null
  local source_product_hash
  local out_product_hash
  source_product_hash="$(sha256_one "$source_product")"
  out_product_hash="$(sha256_one "$out_product")"
  [ "$source_product_hash" = "$out_product_hash" ] \
    || die "product_b changed unexpectedly"
  printf 'product_b\tsource=%s\tout=%s\n' "$source_product_hash" "$out_product_hash"
  echo

  echo "## removed Wallet and HandShaker package directories"
  local path
  for path in "${removed_paths[@]}"; do
    if debugfs_path_exists "$EXPECTED_SYSTEM_IMG" "$path"; then
      die "removed path still exists in system_b: ${path}"
    fi
    echo "absent=${path}"
  done
  echo

  echo "## retained MTP/media paths"
  for path in "${retained_paths[@]}"; do
    if ! debugfs_path_exists "$EXPECTED_SYSTEM_IMG" "$path"; then
      die "retained path missing from system_b: ${path}"
    fi
    echo "retained=${path}"
  done
  echo

  echo "## hiddenapi whitelist"
  local whitelist="${WORK_DIR}/hiddenapi-package-whitelist.offline.xml"
  debugfs_dump "$EXPECTED_SYSTEM_IMG" "/system/etc/sysconfig/hiddenapi-package-whitelist.xml" "$whitelist"
  local pkg
  for pkg in "${target_packages[@]}"; do
    if grep -Fq "$pkg" "$whitelist"; then
      die "hiddenapi whitelist still references ${pkg}"
    fi
    echo "hiddenapi_absent=${pkg}"
  done
  echo

  echo "PASS: v0.28 Wallet and HandShaker debloat offline image verification"
}

live_failures=0

note_live_failure() {
  echo "FAIL: $*" >&2
  live_failures=$((live_failures + 1))
}

live_package_paths() {
  local pkg="$1"
  adb_shell "pm path ${pkg} 2>/dev/null || true"
}

check_live_package_absent() {
  local pkg="$1"
  local paths
  local listed
  paths="$(live_package_paths "$pkg")"
  listed="$(adb_shell "cmd package list packages -u -f | awk -v pkg='${pkg}' 'BEGIN { suffix = \"=\" pkg } substr(\$0, length(\$0) - length(suffix) + 1) == suffix { print }' 2>/dev/null || true")"
  if [ -n "$paths" ] || printf '%s\n' "$listed" | grep -Fq "=${pkg}"; then
    note_live_failure "${pkg} is still present; paths=${paths:-none}"
    printf '%s\tpresent\t%s\n' "$pkg" "${paths:-$listed}"
  else
    printf '%s\tabsent=ok\n' "$pkg"
  fi
}

check_wallet_preclean_state() {
  local paths
  paths="$(live_package_paths "com.smartisanos.wallet")"
  if [ -z "$paths" ]; then
    echo "com.smartisanos.wallet\tabsent=ok"
    return 0
  fi
  if printf '%s\n' "$paths" | grep -Fq '/system/'; then
    note_live_failure "Wallet still resolves from /system after ROM delete; paths=${paths}"
  elif printf '%s\n' "$paths" | grep -Fq '/data/app/'; then
    echo "com.smartisanos.wallet\tupdated_system_residue=present_until_user_approved_cleanup\t${paths}"
  else
    note_live_failure "Wallet resolves from unexpected path before cleanup; paths=${paths}"
  fi
}

check_live_package_present() {
  local label="$1"
  local pkg="$2"
  local paths
  paths="$(live_package_paths "$pkg")"
  if [ -z "$paths" ]; then
    note_live_failure "${label}: ${pkg} missing"
  fi
  printf '%s\tpackage=%s\tpaths=%s\n' "$label" "$pkg" "${paths:-MISSING}"
}

check_usb_state() {
  local sys_usb_state
  local sys_usb_config
  local usb_dump
  sys_usb_state="$(adb_shell 'getprop sys.usb.state')"
  sys_usb_config="$(adb_shell 'getprop sys.usb.config')"
  usb_dump="$(adb_shell "dumpsys usb | grep -E 'current_functions|current_functions_applied|connected:|configured:' | sed -n '1,40p' || true")"
  printf 'sys.usb.state=%s\n' "$sys_usb_state"
  printf 'sys.usb.config=%s\n' "$sys_usb_config"
  printf '%s\n' "$usb_dump"
  if ! printf '%s\n' "$sys_usb_state" | grep -Fq 'adb'; then
    note_live_failure "sys.usb.state does not include adb"
  fi
  if ! printf '%s\n' "$sys_usb_state" | grep -Fq 'mtp'; then
    note_live_failure "sys.usb.state does not include mtp"
  fi
  if ! printf '%s\n' "$usb_dump" | grep -Fq 'current_functions_applied=true'; then
    note_live_failure "dumpsys usb does not show current_functions_applied=true"
  fi
}

run_device_common() {
  local mode_label="$1"

  echo "# ${VARIANT} device ${mode_label} verification"
  date -u +"verified_at=%Y-%m-%dT%H:%M:%SZ"
  echo

  if ! adb_available; then
    adb devices -l || true
    die "adb device ${SERIAL} is not online"
  fi

  echo "## boot state"
  local boot_state
  boot_state="$(adb_shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint')"
  printf '%s\n' "$boot_state"
  local boot_completed
  local slot_suffix
  boot_completed="$(printf '%s\n' "$boot_state" | sed -n '1p')"
  slot_suffix="$(printf '%s\n' "$boot_state" | sed -n '2p')"
  [ "$boot_completed" = "1" ] || note_live_failure "sys.boot_completed=${boot_completed}"
  [ "$slot_suffix" = "_b" ] || note_live_failure "slot_suffix=${slot_suffix}"
  echo

  echo "## root state"
  "$ROOT_HELPER" status || note_live_failure "root status failed"
  echo

  echo "## window state"
  local window_state
  window_state="$(adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | sed -n '1,12p' || true")"
  printf '%s\n' "$window_state"
  if printf '%s\n' "$window_state" | grep -q 'isKeyguardShowing=true'; then
    note_live_failure "keyguard is showing"
  fi
  echo

  echo "## USB/MTP state"
  check_usb_state
  echo

  echo "## core package smoke"
  local pkg
  for pkg in "${core_packages[@]}"; do
    check_live_package_present "$pkg" "$pkg"
  done
  echo
}

run_read_only_pre_clean() {
  run_device_common "read-only-pre-clean"

  echo "## target package state before data cleanup"
  check_wallet_preclean_state
  check_live_package_absent "com.smartisanos.smartfolder.aoa"
  echo

  echo "## package manager target residue"
  adb_shell "cmd package list packages -u -f | grep -iE 'smartisanos.wallet|smartfolder.aoa|HandShaker|WalletSmartisan' || true"
  echo

  if [ "$live_failures" -ne 0 ]; then
    echo "FAIL: v0.28 Wallet and HandShaker pre-clean device read-only verification (${live_failures} failures)"
    exit 1
  fi
  echo "PASS: v0.28 Wallet and HandShaker pre-clean device read-only verification"
}

run_read_only() {
  run_device_common "read-only"

  echo "## target package absence"
  local pkg
  for pkg in "${target_packages[@]}"; do
    check_live_package_absent "$pkg"
  done
  echo

  echo "## package manager target residue"
  adb_shell "cmd package list packages -u -f | grep -iE 'smartisanos.wallet|smartfolder.aoa|HandShaker|WalletSmartisan' || true"
  echo

  if [ "$live_failures" -ne 0 ]; then
    echo "FAIL: v0.28 Wallet and HandShaker final device read-only verification (${live_failures} failures)"
    exit 1
  fi
  echo "PASS: v0.28 Wallet and HandShaker final device read-only verification"
}

mode="${1:-}"
case "$mode" in
  --offline-image)
    report="$(latest_report_path offline-image)"
    run_offline | tee "$report"
    echo "Report: $report"
    ;;
  --read-only-pre-clean)
    report="$(latest_report_path device-pre-clean)"
    run_read_only_pre_clean | tee "$report"
    echo "Report: $report"
    ;;
  --read-only)
    report="$(latest_report_path device)"
    run_read_only | tee "$report"
    echo "Report: $report"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
