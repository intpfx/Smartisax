#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.kg1-smartisax-skip-keyguard"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
SYSTEM_MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
BASE_SERVICES="${ROOT_DIR}/hard-rom/build/framework/services-pm1-cache-allowlist.jar"
KG1_SERVICES="${ROOT_DIR}/hard-rom/build/framework/services-kg1-smartisax-skip-keyguard.jar"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
BASE_SERVICES_JAR_SHA256="84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40"
KG1_SERVICES_JAR_SHA256="0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6"

SERVICES_JAR_PATH="/system/framework/services.jar"
SERVICES_PREOPT_DIR="/system/framework/oat/arm64"
SERVICES_ART_PATH="${SERVICES_PREOPT_DIR}/services.art"
SERVICES_ODEX_PATH="${SERVICES_PREOPT_DIR}/services.odex"
SERVICES_VDEX_PATH="${SERVICES_PREOPT_DIR}/services.vdex"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.kg1-smartisax-skip-keyguard.sh --offline-image
  tools/r2-verify-v0.kg1-smartisax-skip-keyguard.sh --read-only

Checks:
  - offline image hash, sparse hash, AVB/FEC footer, ext4 fsck
  - sparse system_b slice matches the image
  - public services.jar is the kg1 candidate
  - services preopt artifacts remain absent
  - pm1 PackageManager policy remains present
  - kg1 SmartisaxKeyguardPolicy and onServiceConnected hook are present

--read-only verifies a flashed device without changing /data.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

manifest_value() {
  local manifest="$1" key="$2"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2); exit}' "$manifest"
}

check_manifest_hash() {
  local manifest="$1" label="$2" path="$3" key="$4" expected actual
  need_file "$manifest"
  expected="$(manifest_value "$manifest" "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}: ${manifest}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_path_exists() {
  local image="$1" path="$2" output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1" src="$2" dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

verify_image_file_hash() {
  local image="$1" path="$2" expected="$3" label="$4" out actual
  out="${WORK_DIR}/${label}"
  debugfs_path_exists "$image" "$path" || die "missing image path: ${path}"
  debugfs_dump "$image" "$path" "$out"
  actual="$(sha256_one "$out")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_image_path_absent() {
  local image="$1" path="$2" label="$3"
  if debugfs_path_exists "$image" "$path"; then
    die "${label} unexpectedly exists: ${path}"
  fi
  printf '%s\tabsent\t%s\n' "$label" "$path"
}

verify_avb_fec() {
  local image="$1" info="${WORK_DIR}/system-b-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "$info" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "$info" || die "system_b AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "system_b lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "system_b missing FEC offset"
  echo "system_b_avb_fec=ok"
}

verify_services_semantics() {
  local services="$1" decoded="$2"
  rm -rf "$decoded"
  "$JAVA_BIN" -jar "$APKTOOL" d -f -o "$decoded" "$services" >/dev/null
  python3 - "$decoded" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])

def find_one(rel_tail: str) -> Path:
    matches = [path for path in root.rglob(Path(rel_tail).name) if str(path).endswith(rel_tail)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {rel_tail}, found {len(matches)}")
    return matches[0]

checks = [
    ("com/android/server/pm/SmartisaxPackagePolicy.smali", "shouldBypassPackageCache"),
    ("com/android/server/pm/ParallelPackageParser.smali", "SmartisaxPackagePolicy;->shouldBypassPackageCache"),
    ("com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali", "persist.smartisax.skip_keyguard"),
    ("com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali", "shouldDisableKeyguardAfterBoot"),
    ("com/android/server/policy/keyguard/KeyguardServiceDelegate$1.smali", "SmartisaxKeyguardPolicy;->shouldDisableKeyguardAfterBoot"),
    ("com/android/server/policy/keyguard/KeyguardServiceDelegate$1.smali", "Disable keyguard through stock setKeyguardEnabled path"),
    ("com/android/server/policy/keyguard/KeyguardServiceDelegate$1.smali", "KeyguardServiceWrapper;->setKeyguardEnabled"),
]
for rel, needle in checks:
    text = find_one(rel).read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"{rel} missing {needle}")
print("services_semantics=ok")
PY
}

offline_image() {
  need_executable "$E2FSCK"
  need_executable "$DEBUGFS"
  need_file "$AVBTOOL"
  need_file "$SPARSE_TOOL"
  need_file "$JAVA_BIN"
  need_file "$APKTOOL"
  need_file "$BASE_SERVICES"
  need_file "$KG1_SERVICES"
  [ "$(sha256_one "$BASE_SERVICES")" = "$BASE_SERVICES_JAR_SHA256" ] || die "base services hash mismatch"
  [ "$(sha256_one "$KG1_SERVICES")" = "$KG1_SERVICES_JAR_SHA256" ] || die "kg1 services hash mismatch"

  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} offline image verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo

    check_manifest_hash "$SYSTEM_MANIFEST" "system_b" "$SYSTEM_B_IMG" "system_b_sha256"
    check_manifest_hash "$SUPER_MANIFEST" "super_sparse" "$SUPER_SPARSE" "super_sparse_sha256"
    echo

    verify_avb_fec "$SYSTEM_B_IMG"
    "$E2FSCK" -fn "$SYSTEM_B_IMG" >/dev/null
    echo "system_b_fsck=ok"
    echo

    verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$KG1_SERVICES_JAR_SHA256" "services-jar-final.jar"
    verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "services-art-public-final"
    verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "services-odex-public-final"
    verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "services-vdex-public-final"
    verify_services_semantics "${WORK_DIR}/services-jar-final.jar" "${WORK_DIR}/decoded-services-final"
    echo

    "$SPARSE_TOOL" \
      --source-sparse "$SUPER_SPARSE" \
      --extent "$SYSTEM_B_EXTENT" \
      --verify-image "system_b=${SYSTEM_B_IMG}"
    echo "sparse_system_b_slice=ok"
    echo "result=PASS_VERIFY_V0KG1_SMARTISAX_SKIP_KEYGUARD_OFFLINE_IMAGE"
  } | tee "$report"
  echo "Report: $report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

read_only() {
  mkdir -p "$INSPECT_DIR"
  report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} device read-only verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo "serial=${SERIAL}"
    echo

    if ! adb_available; then
      adb devices -l || true
      die "adb device ${SERIAL} is not online"
    fi

    adb -s "$SERIAL" shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.build.fingerprint; settings get secure lockscreen.disabled; cmd lock_settings get-disabled 2>/dev/null; sha256sum /system/framework/services.jar; dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen" | head -20' | tr -d '\r'
    echo
    "$ROOT_HELPER" status || warn "root status command failed"
    echo
    adb -s "$SERIAL" logcat -d -t 800 | grep -E 'SmartisaxKeyguard|setKeyguardEnabled|current mode is SecurityMode' | tail -40 || true
    echo

    device_services_sha="$(adb -s "$SERIAL" shell 'sha256sum /system/framework/services.jar' | tr -d '\r' | awk '{print $1}')"
    [ "$device_services_sha" = "$KG1_SERVICES_JAR_SHA256" ] || die "device services.jar hash mismatch: ${device_services_sha}"

    window_state="$(adb -s "$SERIAL" shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing" | head -20' | tr -d '\r')"
    grep -q "isKeyguardShowing=false" <<<"$window_state" || die "keyguard is still showing"
    grep -q "com.smartisax.browser" <<<"$window_state" || warn "Smartisax focus not observed in window state"
    echo "result=PASS_READ_ONLY_V0KG1_SMARTISAX_SKIP_KEYGUARD"
  } | tee "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image)
    offline_image
    ;;
  --read-only)
    read_only
    ;;
  -h|--help|help|"")
    usage
    [ "${1:-}" = "" ] && exit 2 || exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
