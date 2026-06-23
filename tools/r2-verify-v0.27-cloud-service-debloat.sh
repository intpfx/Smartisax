#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.27-cloud-service-debloat"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-v0.27-cloud-service-debloat"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.27-cloud-service-debloat.img"
SOURCE_V026C="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.SHA256SUMS.txt"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"

cloud_packages=(
  "com.smartisanos.cloudsync"
  "com.smartisanos.cloudsyncshare"
  "com.smartisanos.cloudagent"
)

removed_paths=(
  "/system/priv-app/CloudServiceSmartisan"
  "/system/priv-app/CloudServiceShare"
  "/system/priv-app/CloudSyncAgent"
)

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.27-cloud-service-debloat.sh --offline-image
  tools/r2-verify-v0.27-cloud-service-debloat.sh --read-only

--offline-image verifies the generated v0.27 sparse super:
  - system_b in sparse matches the generated v0.27 system image
  - Smartisan cloud service package directories are absent from system_b
  - hiddenapi-package-whitelist.xml no longer references cloud packages
  - system_ext_b remains byte-identical to the v0.26c source sparse

--read-only verifies a flashed device without changing /data:
  - boot, slot, root, keyguard, and launcher state
  - cloud packages absent from PackageManager
  - cloud launcher, account authenticator, sync adapter, and provider surfaces absent
  - core Settings, Contacts, Calendar provider, MMS, and Phone packages still present

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
  need_file "$SOURCE_V026C"
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
  local extracted_system="${WORK_DIR}/system_b-from-v0.27-sparse.img"
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
  local source_system_ext="${WORK_DIR}/system_ext_b-from-v0.26c-source.img"
  local out_system_ext="${WORK_DIR}/system_ext_b-from-v0.27-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V026C" --extract-image "system_ext_b=${source_system_ext}" >/dev/null
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "system_ext_b=${out_system_ext}" >/dev/null
  local source_system_ext_hash
  local out_system_ext_hash
  source_system_ext_hash="$(sha256_one "$source_system_ext")"
  out_system_ext_hash="$(sha256_one "$out_system_ext")"
  [ "$source_system_ext_hash" = "$out_system_ext_hash" ] \
    || die "system_ext_b changed unexpectedly"
  printf 'system_ext_b\tsource=%s\tout=%s\n' "$source_system_ext_hash" "$out_system_ext_hash"
  echo

  echo "## removed cloud package directories"
  local path
  for path in "${removed_paths[@]}"; do
    if debugfs_path_exists "$EXPECTED_SYSTEM_IMG" "$path"; then
      die "removed path still exists in system_b: ${path}"
    fi
    echo "absent=${path}"
  done
  echo

  echo "## hiddenapi whitelist"
  local whitelist="${WORK_DIR}/hiddenapi-package-whitelist.offline.xml"
  debugfs_dump "$EXPECTED_SYSTEM_IMG" "/system/etc/sysconfig/hiddenapi-package-whitelist.xml" "$whitelist"
  local pkg
  for pkg in "${cloud_packages[@]}"; do
    if grep -Fq "$pkg" "$whitelist"; then
      die "hiddenapi whitelist still references ${pkg}"
    fi
    echo "hiddenapi_absent=${pkg}"
  done
  echo

  echo "PASS: v0.27 cloud service debloat offline image verification"
}

live_failures=0

note_live_failure() {
  echo "FAIL: $*" >&2
  live_failures=$((live_failures + 1))
}

check_live_package_absent() {
  local pkg="$1"
  local paths
  local listed
  paths="$(adb_shell "pm path ${pkg} 2>/dev/null || true")"
  listed="$(adb_shell "cmd package list packages -u -f | awk -v pkg='${pkg}' 'BEGIN { suffix = \"=\" pkg } substr(\$0, length(\$0) - length(suffix) + 1) == suffix { print }' 2>/dev/null || true")"
  if [ -n "$paths" ] || printf '%s\n' "$listed" | grep -Fq "=${pkg}"; then
    note_live_failure "${pkg} is still present; paths=${paths:-none}"
    printf '%s\tpresent\t%s\n' "$pkg" "${paths:-$listed}"
  else
    printf '%s\tabsent=ok\n' "$pkg"
  fi
}

check_live_package_present() {
  local label="$1"
  local pkg="$2"
  local paths
  paths="$(adb_shell "pm path ${pkg} 2>/dev/null || true")"
  if [ -z "$paths" ]; then
    note_live_failure "${label}: ${pkg} missing"
  fi
  printf '%s\tpackage=%s\tpaths=%s\n' "$label" "$pkg" "${paths:-MISSING}"
}

check_query_absent() {
  local label="$1"
  local needle="$2"
  local text="$3"
  if printf '%s\n' "$text" | grep -Fq "$needle"; then
    note_live_failure "${label}: still contains ${needle}"
  else
    printf '%s\tabsent=ok\tneedle=%s\n' "$label" "$needle"
  fi
}

run_read_only() {
  echo "# ${VARIANT} device read-only verification"
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

  echo "## cloud package absence"
  local pkg
  for pkg in "${cloud_packages[@]}"; do
    check_live_package_absent "$pkg"
  done
  echo

  echo "## cloud resolver surfaces"
  local launcher_query
  local sync_services
  local account_services
  local cloud_provider
  launcher_query="$(adb_shell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null || true')"
  sync_services="$(adb_shell 'cmd package query-services --brief -a android.content.SyncAdapter 2>/dev/null || true')"
  account_services="$(adb_shell 'cmd package query-services --brief -a android.accounts.AccountAuthenticator 2>/dev/null || true')"
  cloud_provider="$(adb_shell "dumpsys package providers | grep -i -A3 -B3 'com.smartisanos.cloudsync.accountcenter' 2>/dev/null || true")"
  check_query_absent "launcher_query" "com.smartisanos.cloudsync" "$launcher_query"
  check_query_absent "sync_adapter_query" "com.smartisanos.cloudsync" "$sync_services"
  check_query_absent "account_authenticator_query" "com.smartisanos.cloudsync" "$account_services"
  check_query_absent "accountcenter_provider_query" "com.smartisanos.cloudsync" "$cloud_provider"
  echo "provider_query_output=${cloud_provider:-none}"
  echo

  echo "## core package smoke"
  check_live_package_present "Settings" "com.android.settings"
  check_live_package_present "Contacts" "com.android.contacts"
  check_live_package_present "ContactsProvider" "com.android.providers.contacts"
  check_live_package_present "CalendarProvider" "com.android.providers.calendar"
  check_live_package_present "Mms" "com.android.mms"
  check_live_package_present "Phone" "com.android.phone"
  check_live_package_present "Launcher" "com.smartisanos.launcher"
  check_live_package_present "SystemUI" "com.android.systemui"
  echo

  echo "## package manager cloud residue"
  adb_shell "cmd package list packages -u -f | grep -iE 'cloudsync|cloudagent|CloudService' || true"
  echo

  if [ "$live_failures" -ne 0 ]; then
    echo "FAIL: v0.27 cloud service debloat device read-only verification (${live_failures} failures)"
    exit 1
  fi
  echo "PASS: v0.27 cloud service debloat device read-only verification"
}

mode="${1:-}"
case "$mode" in
  --offline-image)
    report="$(latest_report_path offline-image)"
    run_offline | tee "$report"
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
