#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
POLICY="${POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.24-cleaner-apk-only-locale-prune.img"
SOURCE_V022="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img"
V022_REPORT="${ROOT_DIR}/hard-rom/inspect/v0.22-all-apk-only-locale-prune/verify-v0.22-all-offline-image-20260618-141813.txt"

BASIC_DREAMS_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.dreams.basic-locale-prune-en-zh.apk"
HTML_VIEWER_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.htmlviewer-locale-prune-en-zh.apk"
LIVE_WALLPAPER_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.wallpaper.livepicker-locale-prune-en-zh.apk"
PRINT_SPOOLER_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.printspooler-locale-prune-en-zh.apk"
SIM_APP_DIALOG_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.simappdialog-locale-prune-en-zh.apk"
COMPANION_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.companiondevicemanager-locale-prune-en-zh.apk"
SHARE_BROWSER_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.share.browser-locale-prune-en-zh.apk"
TRACKER_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.tracker-locale-prune-en-zh.apk"
CLEANER_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.cleaner-locale-prune-en-zh.apk"
PHOTO_TABLE_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.dreams.phototable-locale-prune-en-zh.apk"
CONFDIALER_SAMESIZE_APK="${ROOT_DIR}/hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh-samesize.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh --offline-image
  tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh --offline-system-image
  tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh --read-only

--offline-image verifies the generated v0.24 sparse super:
  - all nine system_b promoted APKs match their APK-only candidates
  - product_b and system_ext_b are retained from the verified v0.22 sparse
  - PhotoTable and ConferenceDialer still match their v0.17 candidates
  - ZIP integrity and English/Chinese locale policy pass for all eleven APKs
  - held-stock paths exist for the shared_blocks replacements
  - sparse system_b/product_b/system_ext_b logical slices match expected images

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

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
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
  local apk
  for apk in \
    "$BASIC_DREAMS_APK" \
    "$HTML_VIEWER_APK" \
    "$LIVE_WALLPAPER_APK" \
    "$PRINT_SPOOLER_APK" \
    "$SIM_APP_DIALOG_APK" \
    "$COMPANION_APK" \
    "$SHARE_BROWSER_APK" \
    "$TRACKER_APK" \
    "$CLEANER_APK" \
    "$PHOTO_TABLE_APK" \
    "$CONFDIALER_SAMESIZE_APK"; do
    need_file "$apk"
    unzip -t "$apk" >/dev/null
  done
  need_file "$POLICY"
  need_executable "$POLICY"
}

dump_one() {
  local image="$1"
  local src_path="$2"
  local out="$3"
  "$DEBUGFS" -R "dump ${src_path} ${out}" "$image" >/dev/null 2>&1
  need_file "$out"
}

verify_held_path() {
  local image="$1"
  local path="$2"
  debugfs_path_exists "$image" "$path" || die "missing held-stock path: ${path}"
  echo "held_stock_path=${path}"
}

dump_and_verify_system_image() {
  local image="$1"
  local dump_dir="$2"

  dump_one "$image" "/system/app/BasicDreams/BasicDreams.apk" "${dump_dir}/BasicDreams.apk"
  dump_one "$image" "/system/app/HTMLViewer/HTMLViewer.apk" "${dump_dir}/HTMLViewer.apk"
  dump_one "$image" "/system/app/LiveWallpapersPicker/LiveWallpapersPicker.apk" "${dump_dir}/LiveWallpapersPicker.apk"
  dump_one "$image" "/system/app/PrintSpooler/PrintSpooler.apk" "${dump_dir}/PrintSpooler.apk"
  dump_one "$image" "/system/app/SimAppDialog/SimAppDialog.apk" "${dump_dir}/SimAppDialog.apk"
  dump_one "$image" "/system/app/CompanionDeviceManager/CompanionDeviceManager.apk" "${dump_dir}/CompanionDeviceManager.apk"
  dump_one "$image" "/system/app/SmartisanShareBrowser/SmartisanShareBrowser.apk" "${dump_dir}/SmartisanShareBrowser.apk"
  dump_one "$image" "/system/app/TrackerSmartisan/TrackerSmartisan.apk" "${dump_dir}/TrackerSmartisan.apk"
  dump_one "$image" "/system/app/CleanerSmartisan/CleanerSmartisan.apk" "${dump_dir}/CleanerSmartisan.apk"

  compare_file_hash "${dump_dir}/BasicDreams.apk" "$BASIC_DREAMS_APK" "system/BasicDreams.apk"
  compare_file_hash "${dump_dir}/HTMLViewer.apk" "$HTML_VIEWER_APK" "system/HTMLViewer.apk"
  compare_file_hash "${dump_dir}/LiveWallpapersPicker.apk" "$LIVE_WALLPAPER_APK" "system/LiveWallpapersPicker.apk"
  compare_file_hash "${dump_dir}/PrintSpooler.apk" "$PRINT_SPOOLER_APK" "system/PrintSpooler.apk"
  compare_file_hash "${dump_dir}/SimAppDialog.apk" "$SIM_APP_DIALOG_APK" "system/SimAppDialog.apk"
  compare_file_hash "${dump_dir}/CompanionDeviceManager.apk" "$COMPANION_APK" "system/CompanionDeviceManager.apk"
  compare_file_hash "${dump_dir}/SmartisanShareBrowser.apk" "$SHARE_BROWSER_APK" "system/SmartisanShareBrowser.apk"
  compare_file_hash "${dump_dir}/TrackerSmartisan.apk" "$TRACKER_APK" "system/TrackerSmartisan.apk"
  compare_file_hash "${dump_dir}/CleanerSmartisan.apk" "$CLEANER_APK" "system/CleanerSmartisan.apk"

  unzip -t "${dump_dir}/BasicDreams.apk" >/dev/null
  unzip -t "${dump_dir}/HTMLViewer.apk" >/dev/null
  unzip -t "${dump_dir}/LiveWallpapersPicker.apk" >/dev/null
  unzip -t "${dump_dir}/PrintSpooler.apk" >/dev/null
  unzip -t "${dump_dir}/SimAppDialog.apk" >/dev/null
  unzip -t "${dump_dir}/CompanionDeviceManager.apk" >/dev/null
  unzip -t "${dump_dir}/SmartisanShareBrowser.apk" >/dev/null
  unzip -t "${dump_dir}/TrackerSmartisan.apk" >/dev/null
  unzip -t "${dump_dir}/CleanerSmartisan.apk" >/dev/null

  verify_locale_policy "${dump_dir}/BasicDreams.apk" "system_basicdreams"
  verify_locale_policy "${dump_dir}/HTMLViewer.apk" "system_htmlviewer"
  verify_locale_policy "${dump_dir}/LiveWallpapersPicker.apk" "system_livewallpaperpicker"
  verify_locale_policy "${dump_dir}/PrintSpooler.apk" "system_printspooler"
  verify_locale_policy "${dump_dir}/SimAppDialog.apk" "system_simappdialog"
  verify_locale_policy "${dump_dir}/CompanionDeviceManager.apk" "system_companiondevicemanager"
  verify_locale_policy "${dump_dir}/SmartisanShareBrowser.apk" "system_smartisan_share_browser"
  verify_locale_policy "${dump_dir}/TrackerSmartisan.apk" "system_tracker"
  verify_locale_policy "${dump_dir}/CleanerSmartisan.apk" "system_cleanersmartisan"

  verify_held_path "$image" "/system/app/BasicDreams/.BasicDreams.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/HTMLViewer/.HTMLViewer.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/LiveWallpapersPicker/.LiveWallpapersPicker.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/PrintSpooler/.PrintSpooler.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/SimAppDialog/.SimAppDialog.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/CompanionDeviceManager/.CompanionDeviceManager.apk.smartisax-v022-stock-held"
  verify_held_path "$image" "/system/app/SmartisanShareBrowser/.SmartisanShareBrowser.apk.smartisax-v022-stock-held"
  verify_held_path "$image" "/system/app/TrackerSmartisan/.TrackerSmartisan.apk.smartisax-v022-stock-held"
  verify_held_path "$image" "/system/app/CleanerSmartisan/.CleanerSmartisan.apk.smartisax-v024-stock-held"
}

dump_and_verify_retained_product_system_ext() {
  local product_img="$1"
  local system_ext_img="$2"
  local dump_dir="$3"

  dump_one "$product_img" "/app/PhotoTable/PhotoTable.apk" "${dump_dir}/PhotoTable.apk"
  dump_one "$system_ext_img" "/app/ConferenceDialer/ConferenceDialer.apk" "${dump_dir}/ConferenceDialer.apk"

  compare_file_hash "${dump_dir}/PhotoTable.apk" "$PHOTO_TABLE_APK" "product/PhotoTable.apk"
  compare_file_hash "${dump_dir}/ConferenceDialer.apk" "$CONFDIALER_SAMESIZE_APK" "system_ext/ConferenceDialer.apk"
  unzip -t "${dump_dir}/PhotoTable.apk" >/dev/null
  unzip -t "${dump_dir}/ConferenceDialer.apk" >/dev/null
  verify_locale_policy "${dump_dir}/PhotoTable.apk" "product_phototable"
  verify_locale_policy "${dump_dir}/ConferenceDialer.apk" "system_ext_confdialer"
  verify_held_path "$product_img" "/app/PhotoTable/.PhotoTable.apk.smartisax-v017b-stock-held"
}

extract_retained_images() {
  local product_img="$1"
  local system_ext_img="$2"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V022" \
    --extract-image "product_b=${product_img}" \
    --extract-image "system_ext_b=${system_ext_img}" >/dev/null
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$SOURCE_V022"
  need_file "$V022_REPORT"
  grep -Fq "PASS: v0.22-all offline image verification" "$V022_REPORT" \
    || die "v0.22 source report is not PASS"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.24-offline-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  local product_img="${dump_dir}/product_b-from-v0.22.img"
  local system_ext_img="${dump_dir}/system_ext_b-from-v0.22.img"
  mkdir -p "$dump_dir"
  extract_retained_images "$product_img" "$system_ext_img"

  {
    echo "# v0.24-cleaner-apk-only-locale-prune offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo "source_v0.22=${SOURCE_V022}"
    echo "source_v0.22_report=${V022_REPORT}"
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo "zip_integrity=ok"
    echo

    echo "## retained product_b and system_ext_b APKs"
    dump_and_verify_retained_product_system_ext "$product_img" "$system_ext_img" "$dump_dir"
    echo

    echo "## sparse slices"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "product_b=${product_img}"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_ext_b=${system_ext_img}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" "$SOURCE_V022" \
      "$BASIC_DREAMS_APK" \
      "$HTML_VIEWER_APK" \
      "$LIVE_WALLPAPER_APK" \
      "$PRINT_SPOOLER_APK" \
      "$SIM_APP_DIALOG_APK" \
      "$COMPANION_APK" \
      "$SHARE_BROWSER_APK" \
      "$TRACKER_APK" \
      "$CLEANER_APK" \
      "$PHOTO_TABLE_APK" \
      "$CONFDIALER_SAMESIZE_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.24 offline image verification"
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
  local report="${INSPECT_DIR}/verify-v0.24-offline-system-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-system-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.24-cleaner-apk-only-locale-prune offline system image verification"
    echo "timestamp=${timestamp}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo "zip_integrity=ok"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SYSTEM_IMG" \
      "$BASIC_DREAMS_APK" \
      "$HTML_VIEWER_APK" \
      "$LIVE_WALLPAPER_APK" \
      "$PRINT_SPOOLER_APK" \
      "$SIM_APP_DIALOG_APK" \
      "$COMPANION_APK" \
      "$SHARE_BROWSER_APK" \
      "$TRACKER_APK" \
      "$CLEANER_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.24 offline system image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

LIVE_FAILURES=0

note_live_failure() {
  echo "FAIL: $*"
  LIVE_FAILURES=$((LIVE_FAILURES + 1))
}

verify_live_apk() {
  local label="$1"
  local package="$2"
  local expected_apk="$3"
  local expected_hash
  local pm_paths
  local device_path
  local actual_hash
  local shadow

  expected_hash="$(sha256_one "$expected_apk")"
  pm_paths="$(adb_shell "pm path ${package} 2>/dev/null || true")"
  device_path="$(printf '%s\n' "$pm_paths" | sed -n '1s/^package://p')"
  shadow="no"

  if [ -z "$device_path" ]; then
    note_live_failure "${label}: package path missing for ${package}"
    printf '%s\tpackage=%s\tpath=MISSING\texpected=%s\tactual=MISSING\tshadow=unknown\n' \
      "$label" "$package" "$expected_hash"
    return
  fi

  case "$pm_paths" in
    *"/data/app/"*) shadow="yes" ;;
  esac
  if [ "$shadow" = "yes" ]; then
    note_live_failure "${label}: updated-system /data/app shadow present"
  fi

  actual_hash="$(adb_shell "sha256sum '${device_path}' 2>/dev/null || true" | awk 'NR == 1 {print $1}')"
  if [ -z "$actual_hash" ]; then
    note_live_failure "${label}: could not hash ${device_path}"
    actual_hash="MISSING"
  elif [ "$actual_hash" != "$expected_hash" ]; then
    note_live_failure "${label}: hash mismatch actual=${actual_hash} expected=${expected_hash}"
  fi

  printf '%s\tpackage=%s\tpath=%s\texpected=%s\tactual=%s\tshadow=%s\n' \
    "$label" "$package" "$device_path" "$expected_hash" "$actual_hash" "$shadow"
}

run_read_only() {
  verify_expected_inputs
  adb_available || {
    adb devices -l >&2 || true
    die "adb device ${SERIAL} is not online"
  }
  need_executable "$ROOT_HELPER"
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.24-device-${timestamp}.txt"
  exec > >(tee "$report") 2>&1

  echo "# v0.24-cleaner-apk-only-locale-prune device read-only verification"
  echo "timestamp=${timestamp}"
  echo "serial=${SERIAL}"
  echo "boundary=read-only; no reboot, no flash, no settings write, no package mutation, no /data cleanup"
  echo

  echo "## device state"
  adb devices -l
  adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)";
printf "ro.build.fingerprint=%s\n" "$(getprop ro.build.fingerprint)"'
  "$ROOT_HELPER" cmd 'id; getenforce; getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate'
  echo

  echo "## boot gates"
  [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] \
    || note_live_failure "sys.boot_completed is not 1"
  [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] \
    || note_live_failure "slot is not _b"
  [ "$(adb_shell 'getprop init.svc.bootanim' | tail -n 1)" = "stopped" ] \
    || note_live_failure "bootanim is not stopped"
  echo

  echo "## package hashes"
  verify_live_apk "system/BasicDreams.apk" "com.android.dreams.basic" "$BASIC_DREAMS_APK"
  verify_live_apk "system/HTMLViewer.apk" "com.android.htmlviewer" "$HTML_VIEWER_APK"
  verify_live_apk "system/LiveWallpapersPicker.apk" "com.android.wallpaper.livepicker" "$LIVE_WALLPAPER_APK"
  verify_live_apk "system/PrintSpooler.apk" "com.android.printspooler" "$PRINT_SPOOLER_APK"
  verify_live_apk "system/SimAppDialog.apk" "com.android.simappdialog" "$SIM_APP_DIALOG_APK"
  verify_live_apk "system/CompanionDeviceManager.apk" "com.android.companiondevicemanager" "$COMPANION_APK"
  verify_live_apk "system/SmartisanShareBrowser.apk" "com.smartisanos.share.browser" "$SHARE_BROWSER_APK"
  verify_live_apk "system/TrackerSmartisan.apk" "com.smartisanos.tracker" "$TRACKER_APK"
  verify_live_apk "system/CleanerSmartisan.apk" "com.smartisanos.cleaner" "$CLEANER_APK"
  verify_live_apk "product/PhotoTable.apk" "com.android.dreams.phototable" "$PHOTO_TABLE_APK"
  verify_live_apk "system_ext/ConferenceDialer.apk" "com.qualcomm.qti.confdialer" "$CONFDIALER_SAMESIZE_APK"
  echo

  echo "## window state"
  adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,40p"' || true
  echo

  if [ "$LIVE_FAILURES" -eq 0 ]; then
    echo "result=PASS"
    echo "PASS: v0.24 device read-only verification"
  else
    echo "result=FAIL"
    echo "failure_count=${LIVE_FAILURES}"
    echo "Report: ${report}"
    exit 1
  fi
  echo "Report: ${report}"
}

case "${1:---offline-image}" in
  --offline-image)
    run_offline_image
    ;;
  --offline-system-image)
    run_offline_system_image
    ;;
  --read-only)
    run_read_only
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
