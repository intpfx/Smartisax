#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
POLICY="${POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.13-tier1a-locale-prune"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.13-tier1a-locale-prune-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img"
PROTIPS_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.protips-locale-prune-en-zh.apk"
PRINT_RECOMMENDATION_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.printservice.recommendation-locale-prune-en-zh.apk"
OSU_LOGIN_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.hotspot2.osulogin-locale-prune-en-zh.apk"

mode="read-only"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.13-tier1a-locale-prune.sh --offline-image
  tools/r2-verify-v0.13-tier1a-locale-prune.sh --offline-system-image
  tools/r2-verify-v0.13-tier1a-locale-prune.sh [--read-only]

--offline-image verifies the generated system image and flashable sparse super:
  - Protips.apk, PrintRecommendationService.apk, and OsuLogin.apk inside
    system_b match the expected Tier1a locale-prune APKs
  - dumped APK ZIP integrity passes
  - dumped APK resources.arsc locale policy contains only English/Chinese chunks
  - the sparse super system_b logical slice matches the generated system image

--offline-system-image verifies only the generated system image on the Mac.

--read-only verifies after a v0.13 flash on the live device:
  - boot/slot/root/window/logcat/package evidence is captured
  - pulled system APKs match the expected Tier1a locale-prune APKs
  - pulled APK resources.arsc locale policy still passes

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

adb_device() {
  adb -s "$SERIAL" "$@"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    adb devices >&2
    die "device ${SERIAL} is not available over adb"
  fi
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

assert_file_hash() {
  local path="$1"
  local expected_hash="$2"
  local label="$3"
  local actual_hash
  actual_hash="$(sha256_one "$path")"
  [ "$actual_hash" = "$expected_hash" ] || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$path"
}

verify_locale_policy() {
  local apk="$1"
  local label="$2"
  local policy_out
  policy_out="$("$POLICY" --keep-languages en,zh "$apk")"
  grep -q "bad_locale_chunk_count=0" <<<"$policy_out" || {
    echo "$policy_out" >&2
    die "${label} locale policy failed"
  }
  echo "${label}_locale_policy=ok"
  echo "$policy_out"
}

verify_expected_inputs() {
  need_file "$PROTIPS_APK"
  need_file "$PRINT_RECOMMENDATION_APK"
  need_file "$OSU_LOGIN_APK"
  need_file "$POLICY"
  need_executable "$POLICY"

  assert_file_hash "$PROTIPS_APK" "12e0fc8cc46e9bfe2eacd1b142a945e678661d0062c4d108d3358a27e8827f7d" \
    "expected/com.android.protips.apk" >/dev/null
  assert_file_hash "$PRINT_RECOMMENDATION_APK" "3d92952e74308a3402e0debb5a0ca0a1c909b5cc1990968ccfcbe73377ceb806" \
    "expected/com.android.printservice.recommendation.apk" >/dev/null
  assert_file_hash "$OSU_LOGIN_APK" "4e3059205ea37596aa9957f6b96a26517eeb09b2b7055d15344edf70e4dfb65c" \
    "expected/com.android.hotspot2.osulogin.apk" >/dev/null
  unzip -t "$PROTIPS_APK" >/dev/null
  unzip -t "$PRINT_RECOMMENDATION_APK" >/dev/null
  unzip -t "$OSU_LOGIN_APK" >/dev/null
}

dump_and_verify_from_system_image() {
  local image="$1"
  local dump_dir="$2"

  "$DEBUGFS" -R "dump /system/app/Protips/Protips.apk ${dump_dir}/Protips.apk" "$image" >/dev/null 2>&1
  "$DEBUGFS" -R "dump /system/app/PrintRecommendationService/PrintRecommendationService.apk ${dump_dir}/PrintRecommendationService.apk" "$image" >/dev/null 2>&1
  "$DEBUGFS" -R "dump /system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk ${dump_dir}/OsuLogin.apk" "$image" >/dev/null 2>&1

  compare_file_hash "${dump_dir}/Protips.apk" "$PROTIPS_APK" "system/Protips.apk"
  compare_file_hash "${dump_dir}/PrintRecommendationService.apk" "$PRINT_RECOMMENDATION_APK" "system/PrintRecommendationService.apk"
  compare_file_hash "${dump_dir}/OsuLogin.apk" "$OSU_LOGIN_APK" "system/OsuLogin.apk"
  unzip -t "${dump_dir}/Protips.apk" >/dev/null
  unzip -t "${dump_dir}/PrintRecommendationService.apk" >/dev/null
  unzip -t "${dump_dir}/OsuLogin.apk" >/dev/null
  echo "zip_integrity=ok"

  verify_locale_policy "${dump_dir}/Protips.apk" "system_protips"
  verify_locale_policy "${dump_dir}/PrintRecommendationService.apk" "system_print_recommendation"
  verify_locale_policy "${dump_dir}/OsuLogin.apk" "system_osu_login"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.13-offline-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.13-tier1a-locale-prune offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_from_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo

    echo "## sparse system_b slice"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" \
      "$PROTIPS_APK" "$PRINT_RECOMMENDATION_APK" "$OSU_LOGIN_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.13 offline image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

run_offline_system_image() {
  need_executable "$DEBUGFS"
  need_file "$EXPECTED_SYSTEM_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.13-offline-system-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-system-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.13-tier1a-locale-prune offline system image verification"
    echo "timestamp=${timestamp}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_from_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SYSTEM_IMG" \
      "$PROTIPS_APK" "$PRINT_RECOMMENDATION_APK" "$OSU_LOGIN_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.13 offline system image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

run_read_only_device() {
  verify_expected_inputs
  require_device
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.13-device-${timestamp}.txt"
  local pull_dir="${INSPECT_DIR}/device-${timestamp}"
  mkdir -p "$pull_dir"

  {
    echo "# v0.13-tier1a-locale-prune device verification"
    echo "timestamp=${timestamp}"
    echo "serial=${SERIAL}"
    echo

    echo "## adb"
    adb devices -l
    echo

    echo "## boot state"
    adb_device shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint; getprop persist.sys.locale; settings get system system_locales' | tr -d '\r'
    echo

    echo "## root"
    "$ROOT_HELPER" status || true
    echo

    echo "## package paths"
    adb_device shell 'cmd package path com.android.protips; cmd package path com.android.printservice.recommendation; cmd package path com.android.hotspot2.osulogin' | tr -d '\r' || true
    echo

    echo "## path labels"
    adb_device shell 'ls -lZ /system/app/Protips/Protips.apk /system/app/PrintRecommendationService/PrintRecommendationService.apk /system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk 2>/dev/null' | tr -d '\r'
    echo

    echo "## window excerpt"
    adb_device shell "dumpsys window" > "${pull_dir}/window.txt" || true
    rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing" "${pull_dir}/window.txt" || true
    echo

    echo "## logcat excerpt"
    adb_device logcat -d -t 1000 > "${pull_dir}/logcat.txt" || true
    rg -n "PackageManager|ResourcesManager|ResourcesImpl|AssetManager|OverlayManager|idmap|Protips|PrintRecommendation|OsuLogin|FATAL EXCEPTION" "${pull_dir}/logcat.txt" || true
    echo
  } | tee "$report"

  adb_device pull /system/app/Protips/Protips.apk "${pull_dir}/Protips.apk" >/dev/null
  adb_device pull /system/app/PrintRecommendationService/PrintRecommendationService.apk "${pull_dir}/PrintRecommendationService.apk" >/dev/null
  adb_device pull /system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk "${pull_dir}/OsuLogin.apk" >/dev/null

  {
    compare_file_hash "${pull_dir}/Protips.apk" "$PROTIPS_APK" "device/Protips.apk"
    compare_file_hash "${pull_dir}/PrintRecommendationService.apk" "$PRINT_RECOMMENDATION_APK" "device/PrintRecommendationService.apk"
    compare_file_hash "${pull_dir}/OsuLogin.apk" "$OSU_LOGIN_APK" "device/OsuLogin.apk"
    unzip -t "${pull_dir}/Protips.apk" >/dev/null
    unzip -t "${pull_dir}/PrintRecommendationService.apk" >/dev/null
    unzip -t "${pull_dir}/OsuLogin.apk" >/dev/null
    echo "zip_integrity=ok"
    verify_locale_policy "${pull_dir}/Protips.apk" "device_protips"
    verify_locale_policy "${pull_dir}/PrintRecommendationService.apk" "device_print_recommendation"
    verify_locale_policy "${pull_dir}/OsuLogin.apk" "device_osu_login"
  } | tee -a "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.13 device read-only verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

case "${1:---read-only}" in
  --offline-image)
    mode="offline-image"
    ;;
  --offline-system-image)
    mode="offline-system-image"
    ;;
  --read-only|"")
    mode="read-only"
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

case "$mode" in
  offline-image)
    run_offline_image
    ;;
  offline-system-image)
    run_offline_system_image
    ;;
  read-only)
    run_read_only_device
    ;;
esac
