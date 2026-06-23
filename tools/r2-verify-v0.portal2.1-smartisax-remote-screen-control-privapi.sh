#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
APKTOOL_JAR="${APKTOOL_JAR:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
AAPT="${AAPT:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="v0.portal2.1-smartisax-remote-screen-control-privapi"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
SUPER_MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
OLD_SMARTISAX_DIR="/system/app/SmartisaxShell"
NEW_SMARTISAX_APK_PATH="/system/priv-app/SmartisaxShell/SmartisaxShell.apk"
PRIVAPP_XML_PATH="/system/etc/permissions/privapp-permissions-com.smartisax.browser.xml"
SERVICES_JAR_PATH="/system/framework/services.jar"
BASE_SERVICES="${ROOT_DIR}/hard-rom/build/framework/services-wadb2-current-wifi-adb.jar"
BASE_SERVICES_JAR_SHA256="59e1174901e914684a15e1bb22f82bc5683e23c91ec9a74123f7367826ab8ce2"
SERVICES_JAR_CANDIDATE_SHA256="366bf1c3d0d25d195a51a265064d4a648b3656f4d703e507e86652072262e864"
SENTINEL="__smartisax_current_wifi__"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.portal2.1-smartisax-remote-screen-control-privapi.sh --offline-image
  tools/r2-verify-v0.portal2.1-smartisax-remote-screen-control-privapi.sh --read-only

--offline-image verifies the candidate without touching a device:
  - sparse/system_b hashes match manifests
  - system_b has AVB/FEC roots=2 and passes e2fsck
  - /system/app/SmartisaxShell is absent
  - /system/priv-app/SmartisaxShell/SmartisaxShell.apk is present and matches
  - Smartisax requests MANAGE_DEBUGGING/WRITE_SECURE_SETTINGS and sends the
    current-Wi-Fi BSSID sentinel
  - Smartisax declares DevicePortalService and contains the token-gated
    LAN portal /api/pair, /api/status, /api/screen.png, and /api/input paths
  - Smartisax contains the privileged SurfaceControl PNG screenshot and
    InputManager tap/swipe injection paths for the browser-control MVP
  - privapp-permissions-com.smartisax.browser.xml is present and matches
  - /system/framework/services.jar is present and contains the current-Wi-Fi
    sentinel policy while retaining PM1 and KG1 behavior
  - sparse system_b slice equals the generated system_b image

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

verify_avb_fec() {
  local image="$1" info="${WORK_DIR}/system-b-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "$info" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "$info" || die "system_b AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "system_b lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "system_b missing FEC offset"
  echo "system_b_avb_fec=ok"
}

verify_apk_semantics() {
  local apk="$1" decode_dir="${WORK_DIR}/smartisax-apk-decoded"
  rm -rf "$decode_dir"
  "$AAPT" dump badging "$apk" > "${WORK_DIR}/smartisax-aapt-badging.txt"
  grep -q "package: name='com.smartisax.browser' versionCode='8' versionName='0.4.1'" "${WORK_DIR}/smartisax-aapt-badging.txt" \
    || die "Smartisax aapt identity mismatch"
  PATH="$(dirname "$JAVA"):${PATH}" "$JAVA" -jar "$APKTOOL_JAR" d -f "$apk" -o "$decode_dir" >/dev/null
  grep -Eq 'android:name="(\.DevicePortalService|com\.smartisax\.browser\.DevicePortalService)"' "${decode_dir}/AndroidManifest.xml" \
    || die "Smartisax manifest missing DevicePortalService"
  grep -q 'android.permission.MANAGE_DEBUGGING' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing MANAGE_DEBUGGING"
  grep -q 'android.permission.WRITE_SECURE_SETTINGS' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing WRITE_SECURE_SETTINGS"
  grep -q 'android.permission.ACCESS_WIFI_STATE' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing ACCESS_WIFI_STATE"
  grep -q 'android.permission.READ_FRAME_BUFFER' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing READ_FRAME_BUFFER"
  grep -q 'android.permission.CAPTURE_VIDEO_OUTPUT' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing CAPTURE_VIDEO_OUTPUT"
  grep -q 'android.permission.INJECT_EVENTS' "${decode_dir}/AndroidManifest.xml" || die "Smartisax manifest missing INJECT_EVENTS"
  grep -R -q 'SmartisaxNative' "${decode_dir}/smali" || die "SmartisaxNative bridge missing from dex"
  grep -R -q 'removeJavascriptInterface' "${decode_dir}/smali" || die "bridge removal guard missing from dex"
  grep -R -q 'allowWirelessDebugging' "${decode_dir}/smali" || die "wireless adb privileged call missing from dex"
  grep -R -q "${SENTINEL}" "${decode_dir}/smali" || die "Smartisax current-Wi-Fi sentinel missing from dex"
  grep -R -q 'getAdbWirelessPort' "${decode_dir}/smali" || die "wireless adb port readback missing from dex"
  grep -R -F -q 'privileged[' "${decode_dir}/smali" || die "combined privileged/root diagnostics missing from dex"
  grep -R -q 'IBinder;->transact' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "Binder transact path missing from dex"
  grep -R -q 'writeInterfaceToken' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "Binder interface token path missing from dex"
  ! grep -R -q 'IAdbManager\\$Stub' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "hidden IAdbManager Stub reflection still present"
  ! grep -R -q 'asInterface' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "hidden asInterface reflection still present"
  grep -R -q 'adb_wifi_enabled' "${decode_dir}/smali" || die "wireless adb setting path missing from dex"
  grep -R -q 'DevicePortalService' "${decode_dir}/smali" || die "DevicePortalService missing from dex"
  grep -R -q '/api/status' "${decode_dir}/smali" || die "portal /api/status path missing from dex"
  grep -R -q '/api/pair' "${decode_dir}/smali" || die "portal /api/pair path missing from dex"
  grep -R -q '/api/screen.png' "${decode_dir}/smali" || die "portal /api/screen.png path missing from dex"
  grep -R -q '/api/input' "${decode_dir}/smali" || die "portal /api/input path missing from dex"
  grep -R -q 'SmartisaxDevicePortal' "${decode_dir}/smali" || die "portal server thread marker missing from dex"
  grep -R -q 'SmartisaxDevicePortalClient' "${decode_dir}/smali" || die "portal client worker thread marker missing from dex"
  grep -R -q 'pairingCode' "${decode_dir}/smali" || die "portal pairing code path missing from dex"
  grep -R -q 'enablePortal' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "ShellBridge enablePortal missing"
  grep -R -q 'disablePortal' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "ShellBridge disablePortal missing"
  grep -R -q 'getPortalStatus' "${decode_dir}/smali/com/smartisax/browser/ShellBridge.smali" || die "ShellBridge getPortalStatus missing"
  grep -R -q 'wlan0' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService.smali" || die "portal Wi-Fi interface binding missing"
  grep -R -q 'authorization' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "portal Authorization header path missing"
  grep -R -q 'Bearer ' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "portal bearer-token path missing"
  grep -R -q 'privileged-surfacecontrol-png' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "portal privileged screen backend marker missing"
  grep -R -q 'privileged-inputmanager' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "portal privileged input backend marker missing"
  grep -R -q 'android.view.SurfaceControl' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "SurfaceControl reflection path missing"
  grep -R -q 'injectInputEvent' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "InputManager injectInputEvent path missing"
  ! grep -R -q '/system/bin/kp' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali || die "app-internal kp path still present"
  echo "smartisax_apk_semantics=ok"
}

verify_privapp_xml() {
  local xml="$1"
  grep -q '<privapp-permissions package="com.smartisax.browser">' "$xml" || die "privapp XML missing package block"
  grep -q 'android.permission.MANAGE_DEBUGGING' "$xml" || die "privapp XML missing MANAGE_DEBUGGING"
  grep -q 'android.permission.WRITE_SECURE_SETTINGS' "$xml" || die "privapp XML missing WRITE_SECURE_SETTINGS"
  grep -q 'android.permission.READ_FRAME_BUFFER' "$xml" || die "privapp XML missing READ_FRAME_BUFFER"
  grep -q 'android.permission.CAPTURE_VIDEO_OUTPUT' "$xml" || die "privapp XML missing CAPTURE_VIDEO_OUTPUT"
  grep -q 'android.permission.INJECT_EVENTS' "$xml" || die "privapp XML missing INJECT_EVENTS"
  echo "smartisax_privapp_xml=ok"
}

verify_services_semantics() {
  local base="$1" candidate="$2" decode_dir="$3"
  [ "$(sha256_one "$base")" = "$BASE_SERVICES_JAR_SHA256" ] || die "base services.jar hash mismatch"
  [ "$(sha256_one "$candidate")" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "candidate services.jar hash mismatch"
  rm -rf "$decode_dir"
  PATH="$(dirname "$JAVA"):${PATH}" "$JAVA" -jar "$APKTOOL_JAR" d -f "$candidate" -o "$decode_dir" >/dev/null
  python3 - "$base" "$candidate" "$decode_dir" "$SENTINEL" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
candidate = Path(sys.argv[2])
decoded = Path(sys.argv[3])
sentinel = sys.argv[4]

def entry_map(path: Path):
    with zipfile.ZipFile(path, "r") as zf:
        result = {}
        for info in zf.infolist():
            data = zf.read(info.filename)
            result[info.filename] = {
                "sha256": hashlib.sha256(data).hexdigest(),
                "compress_type": info.compress_type,
            }
        return result

def find_one(rel_tail: str) -> Path:
    matches = [path for path in decoded.rglob(Path(rel_tail).name) if str(path).endswith(rel_tail)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {rel_tail}, found {len(matches)}")
    return matches[0]

base_entries = entry_map(base)
candidate_entries = entry_map(candidate)
if list(base_entries) != list(candidate_entries):
    raise SystemExit("services.jar entry list/order mismatch")
changed = [name for name in base_entries if base_entries[name]["sha256"] != candidate_entries[name]["sha256"]]
allowed = {"classes.dex", "classes2.dex"}
if not changed or any(name not in allowed for name in changed):
    raise SystemExit(f"unexpected changed services.jar entries: {changed}")
for name, meta in candidate_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"candidate services.jar entry is not STORED: {name}")
if "META-INF/MANIFEST.MF" not in candidate_entries:
    raise SystemExit("candidate services.jar lost META-INF/MANIFEST.MF")

handler = find_one("com/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler.smali")
pm_policy = find_one("com/android/server/pm/SmartisaxPackagePolicy.smali")
kg_policy = find_one("com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali")

handler_text = handler.read_text(encoding="utf-8")
checks = [
    (handler, sentinel),
    (handler, "Resolved current Wi-Fi BSSID for Smartisax wireless ADB"),
    (handler, "getCurrentWifiApInfo"),
    (handler, "AdbDebuggingManager$AdbConnectionInfo;->getBSSID()Ljava/lang/String;"),
    (handler, "AdbKeyStore;->addTrustedNetwork(Ljava/lang/String;)V"),
    (pm_policy, "shouldBypassPackageCache"),
    (pm_policy, "/system/priv-app/SmartisaxShell"),
    (kg_policy, "persist.smartisax.skip_keyguard"),
]
for path, needle in checks:
    if needle not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"{path} missing {needle}")
sentinel_index = handler_text.find(sentinel)
trusted_index = handler_text.find("addTrustedNetwork", sentinel_index)
if sentinel_index < 0 or trusted_index < sentinel_index:
    raise SystemExit("sentinel resolution does not appear before addTrustedNetwork in the patched block")

print("services_jar_changed_entries=" + ",".join(changed))
print("services_jar_all_entries_stored=true")
print("services_jar_manifest_retained=true")
print("smartisax_services_current_wifi_policy=ok")
print("smartisax_privapp_cache_bypass=ok")
print("smartisax_pm1_policy_retained=ok")
print("smartisax_kg1_policy_retained=ok")
PY
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_shell() {
  adb -s "$SERIAL" shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@" 2>&1 | tr -d '\r'
}

run_offline_image() {
  need_executable "$E2FSCK"
  need_executable "$DEBUGFS"
  need_executable "$JAVA"
  need_executable "$AAPT"
  need_file "$AVBTOOL"
  need_file "$SPARSE_TOOL"
  need_file "$APKTOOL_JAR"

  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} offline image verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo "boundary=offline verifier only; no adb, no fastboot, no flash, no reboot, no /data mutation"
    echo

    echo "## local files"
    check_manifest_hash "$SUPER_MANIFEST" "candidate_sparse" "$SUPER_SPARSE" "super_sparse_sha256"
    check_manifest_hash "$SUPER_MANIFEST" "system_b_image" "$SYSTEM_B_IMG" "system_b_sha256"
    smartisax_expected="$(manifest_value "$SUPER_MANIFEST" smartisax_apk_sha256)"
    privapp_expected="$(manifest_value "$SUPER_MANIFEST" privapp_xml_sha256)"
    services_expected="$(manifest_value "$SUPER_MANIFEST" services_jar_retained_sha256)"
    [ -n "$smartisax_expected" ] || die "manifest missing smartisax_apk_sha256"
    [ -n "$privapp_expected" ] || die "manifest missing privapp_xml_sha256"
    [ -n "$services_expected" ] || die "manifest missing services_jar_retained_sha256"
    [ "$services_expected" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "services.jar expected hash drift: manifest=${services_expected} verifier=${SERVICES_JAR_CANDIDATE_SHA256}"
    echo

    echo "## system_b"
    "$E2FSCK" -fn "$SYSTEM_B_IMG" >/dev/null
    echo "system_b_fsck=ok"
    verify_avb_fec "$SYSTEM_B_IMG"
    ! debugfs_path_exists "$SYSTEM_B_IMG" "$OLD_SMARTISAX_DIR" || die "old Smartisax system app path still exists"
    debugfs_dump "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "${WORK_DIR}/smartisax-priv-app.apk"
    debugfs_dump "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml"
    debugfs_dump "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "${WORK_DIR}/services-jar-public.jar"
    [ "$(sha256_one "${WORK_DIR}/smartisax-priv-app.apk")" = "$smartisax_expected" ] || die "Smartisax APK hash mismatch"
    [ "$(sha256_one "${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml")" = "$privapp_expected" ] || die "Smartisax privapp XML hash mismatch"
    [ "$(sha256_one "${WORK_DIR}/services-jar-public.jar")" = "$services_expected" ] || die "services.jar hash mismatch"
    unzip -t "${WORK_DIR}/smartisax-priv-app.apk" >/dev/null
    unzip -t "${WORK_DIR}/services-jar-public.jar" >/dev/null
    verify_apk_semantics "${WORK_DIR}/smartisax-priv-app.apk"
    verify_privapp_xml "${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml"
    verify_services_semantics "$BASE_SERVICES" "${WORK_DIR}/services-jar-public.jar" "${WORK_DIR}/services-decoded"
    "$SPARSE_TOOL" \
      --source-sparse "$SUPER_SPARSE" \
      --extent "$SYSTEM_B_EXTENT" \
      --verify-image "system_b=${SYSTEM_B_IMG}"
    echo "sparse_system_b_slice=ok"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0PORTAL21_SMARTISAX_REMOTE_SCREEN_CONTROL_PRIVAPI"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

run_read_only() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} device read-only verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo "serial=${SERIAL}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no /data cleanup"
    echo

    echo "## adb"
    adb devices -l
    adb_available || die "adb device ${SERIAL} is not online"
    echo

    echo "## boot state"
    adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root"
    "$ROOT_HELPER" status || warn "root status failed"
    echo

    echo "## Smartisax package"
    pm_path="$(adb_shell 'pm path com.smartisax.browser | head -n1')"
    echo "$pm_path"
    [[ "$pm_path" == "package:${NEW_SMARTISAX_APK_PATH}" ]] || die "Smartisax is not served from priv-app"
    package_dump="$(adb_shell 'dumpsys package com.smartisax.browser')"
    grep -E "codePath=|resourcePath=|versionCode=|pkgFlags=|privateFlags=|android.permission.(MANAGE_DEBUGGING|WRITE_SECURE_SETTINGS|ACCESS_WIFI_STATE|READ_FRAME_BUFFER|CAPTURE_VIDEO_OUTPUT|INJECT_EVENTS):" <<<"$package_dump" || true
    grep -q 'versionCode=8 ' <<<"$package_dump" || die "Smartisax PackageManager did not parse versionCode=8"
    grep -q 'android.permission.READ_FRAME_BUFFER: granted=true' <<<"$package_dump" || die "READ_FRAME_BUFFER not granted"
    grep -q 'android.permission.INJECT_EVENTS: granted=true' <<<"$package_dump" || die "INJECT_EVENTS not granted"
    root_cmd "[ ! -e ${OLD_SMARTISAX_DIR} ] && echo old_smartisax_system_app=absent || { echo old_smartisax_system_app=present; ls -ld ${OLD_SMARTISAX_DIR}; }"
    root_cmd "[ -f ${PRIVAPP_XML_PATH} ] && echo smartisax_privapp_xml=present || echo smartisax_privapp_xml=absent"
    echo

    echo "## services.jar"
    services_hash="$(root_cmd 'sha256sum /system/framework/services.jar' | awk '/services.jar/ {print $1; exit}')"
    echo "services_jar_sha256=${services_hash}"
    [ "$services_hash" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "services.jar hash mismatch: ${services_hash}"
    root_cmd 'ls -l /system/framework/oat/arm64/services.* 2>/dev/null || echo services_preopt_public_absent'
    echo

    echo "## wireless adb state"
    adb_shell 'settings get global adb_wifi_enabled; service call adb 10 2>/dev/null || true'
    echo

    echo "result=PASS_READ_ONLY_V0PORTAL21_SMARTISAX_REMOTE_SCREEN_CONTROL_PRIVAPI"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) run_offline_image ;;
  --read-only) run_read_only ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
