#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
AAPT="${AAPT:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="${VARIANT:-v0.36-smartisax-shell-debloat}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
REPORT_PREFIX="verify-${VARIANT}"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
EXPECTED_PRODUCT_B_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img"
SMARTISAX_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell.apk"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
PRODUCT_B_PARTITION_SIZE=171110400
PRODUCT_B_EXT4_SIZE=168321024
EXPECTED_WEBVIEW_VERSION="150.0.7871.28"

SMARTISAX_PACKAGE="com.smartisax.browser"
SMARTISAX_PATH="/system/app/SmartisaxShell/SmartisaxShell.apk"
SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSERCHROME_OAT_DIR="/system/app/BrowserChrome/oat"
LAUNCHER_APK="/system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk"

REMOVED_PATHS=(
  "/system/app/SMTBugreport"
  "/system/app/CrashReport"
  "/system/app/SlardarOsClient"
  "/system/app/SMPushService"
  "/system/app/UnionPushProxy"
  "/system/app/TrackerSmartisan"
  "/system/priv-app/TeaTracker"
  "/system/app/BasicDreams"
  "/system/app/HTMLViewer"
  "/system/app/LiveWallpapersPicker"
  "/system/app/WallpaperBackup"
  "/system/app/Exchange2"
  "/system/app/Traceur"
  "/system/app/EasterEgg"
  "/system/app/Protips"
  "/system/app/CtsShimPrebuilt"
  "/system/priv-app/CtsShimPrivPrebuilt"
  "/system/priv-app/SmartisanShareManual"
  "/system/app/SmartisanWallpapers"
)

REMOVED_PACKAGES=(
  "com.smartisanos.bug2go"
  "com.smartisan.crashreport"
  "com.bytedance.os.slardar"
  "com.smartisan.smpush"
  "com.smartisan.unionpush.proxy"
  "com.smartisanos.tracker"
  "com.smartisanos.teatracker"
  "com.android.dreams.basic"
  "com.android.htmlviewer"
  "com.android.wallpaper.livepicker"
  "com.android.wallpaperbackup"
  "com.android.exchange"
  "com.android.traceur"
  "com.android.egg"
  "com.android.protips"
  "com.android.cts.ctsshim"
  "com.android.cts.priv.ctsshim"
  "com.smartisanos.manual"
  "com.smartisanos.wallpapers"
)

KEEP_PATHS=(
  "/system/app/BuiltInPrintService"
  "/system/app/PrintSpooler"
  "/system/app/PrintRecommendationService"
  "/system/app/BostonScreenMirror"
  "/system/priv-app/BostonCastHalService"
  "/system/app/SmartisanWirelessCast"
  "$SYSTEM_WEBVIEW_APK"
  "$BROWSERCHROME_APK"
  "$LAUNCHER_APK"
)

CONFIG_FILTERS=(
  "/system/etc/sysconfig/hiddenapi-package-whitelist.xml"
  "/system/etc/sysconfig/qti_whitelist.xml"
  "/system/etc/sysconfig/preinstalled-packages-platform.xml"
  "/system/etc/sysconfig/preinstalled-packages-platform-full-base.xml"
  "/system/etc/permissions/platform.xml"
)

FORBIDDEN_PACKAGE_REGEX='com\.smartisanos\.bug2go|com\.smartisan\.crashreport|com\.bytedance\.os\.slardar|com\.smartisan\.smpush|com\.smartisan\.unionpush\.proxy|com\.smartisanos\.tracker|com\.smartisanos\.teatracker|com\.android\.dreams\.basic|com\.android\.htmlviewer|com\.android\.wallpaper\.livepicker|com\.android\.wallpaperbackup|com\.android\.exchange|com\.android\.traceur|com\.android\.egg|com\.android\.protips|com\.android\.cts\.ctsshim|com\.android\.cts\.priv\.ctsshim|com\.smartisanos\.manual|com\.smartisanos\.wallpapers'

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.36-smartisax-shell-debloat.sh --offline-image
  tools/r2-verify-v0.36-smartisax-shell-debloat.sh --read-only

--offline-image verifies the v0.36 candidate without touching a device:
  - sparse/system/product/APK hashes match the manifest
  - system_b has SmartisaxShell.apk and M150 WebView
  - stock BrowserChrome and stock Launcher remain byte-identical
  - selected debloat paths, including SmartisanWallpapers, are absent
  - print and TNT/projection paths are still present
  - active sysconfig/permissions files no longer reference removed packages
  - system_b and retained product_b AVB footers keep FEC roots=2

--read-only verifies a flashed device without changing /data.
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

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
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
  need_file "$MANIFEST"
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
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

verify_avb_fec() {
  local label="$1"
  local image="$2"
  local partition_size="$3"
  local ext4_size="$4"
  local info="${WORK_DIR}/${label}-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${partition_size} bytes" "$info" \
    || die "${label} AVB image size mismatch"
  grep -q "Original image size:      ${ext4_size} bytes" "$info" \
    || die "${label} AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "${label} lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "${label} missing FEC offset"
  echo "${label}_avb_fec=ok"
}

verify_apk_manifest_contract() {
  local apk="$1"
  local dump="${WORK_DIR}/smartisax-aapt-xmltree.txt"
  "$AAPT" dump badging "$apk" > "${WORK_DIR}/smartisax-aapt-badging.txt"
  grep -q "package: name='${SMARTISAX_PACKAGE}'" "${WORK_DIR}/smartisax-aapt-badging.txt" \
    || die "Smartisax APK package name mismatch"
  "$AAPT" dump xmltree "$apk" AndroidManifest.xml > "$dump"
  grep -q "android.intent.category.HOME" "$dump" || die "Smartisax APK missing HOME category"
  grep -q "android.intent.category.LAUNCHER" "$dump" || die "Smartisax APK missing LAUNCHER category"
  grep -q "android.intent.category.BROWSABLE" "$dump" || die "Smartisax APK missing BROWSABLE category"
  grep -q "android.intent.action.VIEW" "$dump" || die "Smartisax APK missing VIEW action"
  echo "smartisax_manifest_contract=ok"
}

verify_apk_r_plus_layout() {
  local apk="$1"
  python3 - "$apk" <<'PY'
import sys
import struct
import zipfile

apk = sys.argv[1]
with open(apk, "rb") as fp, zipfile.ZipFile(apk) as zf:
    info = zf.getinfo("resources.arsc")
    fp.seek(info.header_offset)
    header = fp.read(30)
    if len(header) != 30:
        raise SystemExit("truncated ZIP local header for resources.arsc")
    sig, _ver, _flag, method, *_rest, name_len, extra_len = struct.unpack("<IHHHHHIIIHH", header)
    if sig != 0x04034B50:
        raise SystemExit("bad ZIP local header signature for resources.arsc")
    data_offset = info.header_offset + 30 + name_len + extra_len
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit("resources.arsc is not STORED")
    if method != zipfile.ZIP_STORED:
        raise SystemExit("resources.arsc local header is not STORED")
    if data_offset % 4 != 0:
        raise SystemExit(f"resources.arsc data offset is not 4-byte aligned: {data_offset}")
    print(f"smartisax_resources_arsc_layout=ok stored=true data_offset={data_offset}")
PY
}

write_report_header() {
  local report="$1"
  {
    echo "# ${VARIANT} verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "serial=${SERIAL}"
    echo "report=${report#${ROOT_DIR}/}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no package-cache clear, no /data cleanup"
    echo
  } > "$report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@"
}

run_offline_image() {
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/*.xml "${WORK_DIR}"/*-avb-info.txt "${WORK_DIR}"/*aapt*.txt
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## local files"
    check_manifest_hash "candidate_sparse" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "system_b_image" "$EXPECTED_SYSTEM_B_IMG" "system_b_sha256"
    check_manifest_hash "product_b_image" "$EXPECTED_PRODUCT_B_IMG" "product_b_sha256"
    check_manifest_hash "smartisax_apk" "$SMARTISAX_APK" "smartisax_apk_sha256"
    [ "$(manifest_value debloat_source_id)" = "user_selected_plus_smartisan_wallpapers_reserve" ] \
      || die "manifest debloat source mismatch"
    [ "$(manifest_value debloat_preserves_print_stack)" = "yes" ] || die "manifest print preservation missing"
    [ "$(manifest_value debloat_preserves_tnt_projection)" = "yes" ] || die "manifest projection preservation missing"
    [ "$(manifest_value debloat_includes_smartisan_wallpapers)" = "yes" ] || die "manifest wallpaper deletion missing"
    echo

    echo "## sparse layout evidence"
    need_file "${EXPECTED_SPARSE}.lpdump-slot1.txt"
    grep -q "Name: system_b" "${EXPECTED_SPARSE}.lpdump-slot1.txt" || die "lpdump missing system_b"
    grep -q "Name: product_b" "${EXPECTED_SPARSE}.lpdump-slot1.txt" || die "lpdump missing product_b"
    grep -q "system_b (6217336 sectors)" "${EXPECTED_SPARSE}.lpdump-slot1.txt" || die "lpdump system_b extent size mismatch"
    grep -q "product_b (334200 sectors)" "${EXPECTED_SPARSE}.lpdump-slot1.txt" || die "lpdump product_b extent size mismatch"
    echo "lpdump_slot1=ok"
    echo

    echo "## avb and fs"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    "$E2FSCK" -fn "$EXPECTED_PRODUCT_B_IMG" >/dev/null
    verify_avb_fec "system_b" "$EXPECTED_SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE" "$SYSTEM_B_EXT4_SIZE"
    verify_avb_fec "product_b" "$EXPECTED_PRODUCT_B_IMG" "$PRODUCT_B_PARTITION_SIZE" "$PRODUCT_B_EXT4_SIZE"
    echo

    echo "## smartisax and retained packages"
    smartisax_dump="${WORK_DIR}/smartisax-dumped.apk"
    debugfs_dump "$EXPECTED_SYSTEM_B_IMG" "$SMARTISAX_PATH" "$smartisax_dump"
    [ "$(sha256_one "$smartisax_dump")" = "$(manifest_value smartisax_apk_sha256)" ] \
      || die "Smartisax dumped APK hash mismatch"
    unzip -t "$smartisax_dump" >/dev/null
    verify_apk_manifest_contract "$smartisax_dump"
    verify_apk_r_plus_layout "$smartisax_dump"
    for keep_path in "${KEEP_PATHS[@]}"; do
      debugfs_path_exists "$EXPECTED_SYSTEM_B_IMG" "$keep_path" || die "protected path missing: ${keep_path}"
    done
    ! debugfs_path_exists "$EXPECTED_SYSTEM_B_IMG" "$BROWSERCHROME_OAT_DIR" \
      || die "BrowserChrome oat dir reappeared"
    echo "protected_paths=ok"
    echo

    echo "## removed paths"
    for removed_path in "${REMOVED_PATHS[@]}"; do
      ! debugfs_path_exists "$EXPECTED_SYSTEM_B_IMG" "$removed_path" || die "removed path still exists: ${removed_path}"
    done
    echo "removed_paths=ok count=${#REMOVED_PATHS[@]}"
    echo

    echo "## config references"
    for config_path in "${CONFIG_FILTERS[@]}"; do
      dump="${WORK_DIR}/$(basename "$config_path").active.xml"
      debugfs_dump "$EXPECTED_SYSTEM_B_IMG" "$config_path" "$dump"
      if grep -Eq "$FORBIDDEN_PACKAGE_REGEX" "$dump"; then
        die "active config still references a removed package: ${config_path}"
      fi
      echo "${config_path}=clean"
    done
    echo

    echo "smartisax_package=ok"
    echo "result=PASS_OFFLINE_IMAGE_V036_SMARTISAX_SHELL_DEBLOAT"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

run_read_only() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## adb"
    adb devices -l
    adb_available || die "adb device ${SERIAL} is not online"
    echo

    echo "## boot state"
    adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root"
    "$ROOT_HELPER" status
    echo

    echo "## package paths"
    smartisax_path="$(adb_shell 'cmd package path com.smartisax.browser || true' | tail -n 1)"
    echo "smartisax_path=${smartisax_path}"
    grep -q '/system/app/SmartisaxShell/SmartisaxShell.apk' <<<"$smartisax_path" \
      || die "com.smartisax.browser is not served from /system/app/SmartisaxShell"
    webview_path="$(adb_shell 'cmd package path com.android.webview || true' | tail -n 1)"
    echo "webview_path=${webview_path}"
    grep -q '/system/app/webview/webview.apk' <<<"$webview_path" \
      || die "com.android.webview is not served from /system/app/webview"
    echo "browser_path=$(adb_shell 'cmd package path com.android.browser || true' | tail -n 1)"
    echo "launcher_path=$(adb_shell 'cmd package path com.smartisanos.launcher || true' | tail -n 1)"
    echo

    echo "## removed packages"
    for package_name in "${REMOVED_PACKAGES[@]}"; do
      path="$(adb_shell "cmd package path ${package_name} || true" | tail -n 1)"
      if [ -n "$path" ]; then
        die "removed package still resolves: ${package_name} ${path}"
      fi
      echo "${package_name}=absent"
    done
    echo

    echo "## resolver surfaces"
    adb_shell 'cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.HOME | grep -E "com.smartisax.browser|com.smartisanos.launcher" || true'
    adb_shell 'cmd package query-activities -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d https://www.example.com | grep -E "com.smartisax.browser|com.android.browser" || true'
    adb_shell 'cmd webviewupdate | sed -n "1,60p"'
    adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing" | tail -n 12'
    echo

    echo "## root path probes"
    for removed_path in "${REMOVED_PATHS[@]}"; do
      state="$(root_cmd "test -e ${removed_path} && echo present || echo absent" | tail -n 1)"
      [ "$state" = "absent" ] || die "removed ROM path still exists on device: ${removed_path}"
      echo "${removed_path}=absent"
    done
    for keep_path in "${KEEP_PATHS[@]}" "$SMARTISAX_PATH"; do
      state="$(root_cmd "test -e ${keep_path} && echo present || echo absent" | tail -n 1)"
      [ "$state" = "present" ] || die "expected ROM path missing on device: ${keep_path}"
      echo "${keep_path}=present"
    done
    echo

    echo "result=PASS_READ_ONLY_V036_SMARTISAX_SHELL_DEBLOAT"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$DEBUGFS"
    need_executable "$E2FSCK"
    need_executable "$AAPT"
    need_file "$AVBTOOL"
    run_offline_image
    ;;
  --read-only)
    run_read_only
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
