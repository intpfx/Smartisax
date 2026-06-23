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
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="v0.portal2.3-smartisax-framebuffer-grant"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
SUPER_MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
BASE_SERVICES="${ROOT_DIR}/hard-rom/build/framework/services-wadb2-privapp-cache-adb.jar"
BASE_SERVICES_JAR_SHA256="366bf1c3d0d25d195a51a265064d4a648b3656f4d703e507e86652072262e864"
SERVICES_JAR_CANDIDATE_SHA256="0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a"
SERVICES_JAR_PATH="/system/framework/services.jar"
SERVICES_PREOPT_DIR="/system/framework/oat/arm64"
SERVICES_ART_PATH="${SERVICES_PREOPT_DIR}/services.art"
SERVICES_ODEX_PATH="${SERVICES_PREOPT_DIR}/services.odex"
SERVICES_VDEX_PATH="${SERVICES_PREOPT_DIR}/services.vdex"
NEW_SMARTISAX_APK_PATH="/system/priv-app/SmartisaxShell/SmartisaxShell.apk"
SMARTISAX_PACKAGE="com.smartisax.browser"
SMARTISAX_PERMISSION="android.permission.READ_FRAME_BUFFER"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.portal2.3-smartisax-framebuffer-grant.sh --offline-image
  tools/r2-verify-v0.portal2.3-smartisax-framebuffer-grant.sh --read-only

--offline-image verifies the built sparse/system_b without touching a device.
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
  local base="$1" candidate="$2" decode_dir="$3"
  [ "$(sha256_one "$base")" = "$BASE_SERVICES_JAR_SHA256" ] || die "base services.jar hash mismatch"
  [ "$(sha256_one "$candidate")" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "candidate services.jar hash mismatch"
  rm -rf "$decode_dir"
  PATH="$(dirname "$JAVA"):${PATH}" "$JAVA" -jar "$APKTOOL_JAR" d -f "$candidate" -o "$decode_dir" >/dev/null
  python3 - "$base" "$candidate" "$decode_dir" "$SMARTISAX_PACKAGE" "$SMARTISAX_PERMISSION" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
candidate = Path(sys.argv[2])
decoded = Path(sys.argv[3])
smartisax_package = sys.argv[4]
smartisax_permission = sys.argv[5]

def entry_map(path: Path):
    with zipfile.ZipFile(path, "r") as zf:
        return {
            info.filename: {
                "sha256": hashlib.sha256(zf.read(info.filename)).hexdigest(),
                "compress_type": info.compress_type,
            }
            for info in zf.infolist()
        }

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
if changed != ["classes.dex"]:
    raise SystemExit(f"unexpected changed services.jar entries: {changed}")
for name, meta in candidate_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"candidate services.jar entry is not STORED: {name}")
if "META-INF/MANIFEST.MF" not in candidate_entries:
    raise SystemExit("candidate services.jar lost META-INF/MANIFEST.MF")

policy = find_one("com/android/server/pm/SmartisaxPackagePolicy.smali")
pms = find_one("com/android/server/pm/permission/PermissionManagerService.smali")
handler = find_one("com/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler.smali")
kg_policy = find_one("com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali")

policy_text = policy.read_text(encoding="utf-8")
pms_text = pms.read_text(encoding="utf-8")
checks = [
    (policy, "shouldBypassPackageCache"),
    (policy, "/system/priv-app/SmartisaxShell"),
    (policy, "/system/app/TextBoomArm32"),
    (policy, "shouldGrantSignaturePermission"),
    (policy, smartisax_package),
    (policy, smartisax_permission),
    (pms, "Lcom/android/server/pm/SmartisaxPackagePolicy;->shouldGrantSignaturePermission(Ljava/lang/String;Ljava/lang/String;)Z"),
    (pms, "return v2"),
    (handler, "__smartisax_current_wifi__"),
    (handler, "Resolved current Wi-Fi BSSID for Smartisax wireless ADB"),
    (kg_policy, "persist.smartisax.skip_keyguard"),
]
for path, needle in checks:
    if needle not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"{path} missing {needle}")
if "android.permission.CAPTURE_VIDEO_OUTPUT" in policy_text or "android.permission.INJECT_EVENTS" in policy_text:
    raise SystemExit("Smartisax signature policy grants more than READ_FRAME_BUFFER")
call_index = pms_text.find("SmartisaxPackagePolicy;->shouldGrantSignaturePermission")
stock_index = pms_text.find("BasePermission;->isOEM")
if call_index < 0 or stock_index < 0 or call_index > stock_index:
    raise SystemExit("Smartisax signature policy is not before stock signature checks")

print("services_jar_changed_entries=" + ",".join(changed))
print("services_jar_all_entries_stored=true")
print("services_jar_manifest_retained=true")
print("smartisax_signature_permission_policy=ok")
print("smartisax_signature_permission_package=" + smartisax_package)
print("smartisax_signature_permission_grant=" + smartisax_permission)
print("smartisax_signature_policy_scope=read_frame_buffer_only")
print("smartisax_pm1_policy_retained=ok")
print("smartisax_current_wifi_policy_retained=ok")
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
  need_file "$AVBTOOL"
  need_file "$SPARSE_TOOL"
  need_file "$APKTOOL_JAR"
  need_file "$BASE_SERVICES"

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
    services_expected="$(manifest_value "$SUPER_MANIFEST" services_jar_candidate_sha256)"
    [ -n "$services_expected" ] || die "manifest missing services_jar_candidate_sha256"
    [ "$services_expected" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "services.jar expected hash drift: manifest=${services_expected} verifier=${SERVICES_JAR_CANDIDATE_SHA256}"
    echo

    echo "## system_b"
    "$E2FSCK" -fn "$SYSTEM_B_IMG" >/dev/null
    echo "system_b_fsck=ok"
    verify_avb_fec "$SYSTEM_B_IMG"
    verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "services-art-public"
    verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "services-odex-public"
    verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "services-vdex-public"
    debugfs_dump "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "${WORK_DIR}/services-jar-public.jar"
    [ "$(sha256_one "${WORK_DIR}/services-jar-public.jar")" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "services.jar hash mismatch"
    unzip -t "${WORK_DIR}/services-jar-public.jar" >/dev/null
    verify_services_semantics "$BASE_SERVICES" "${WORK_DIR}/services-jar-public.jar" "${WORK_DIR}/services-decoded"
    "$SPARSE_TOOL" \
      --source-sparse "$SUPER_SPARSE" \
      --extent "$SYSTEM_B_EXTENT" \
      --verify-image "system_b=${SYSTEM_B_IMG}"
    echo "sparse_system_b_slice=ok"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0PORTAL23_SMARTISAX_FRAMEBUFFER_GRANT"
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

    echo "## services.jar"
    services_hash="$(root_cmd 'sha256sum /system/framework/services.jar' | awk '/services.jar/ {print $1; exit}')"
    echo "services_jar_sha256=${services_hash}"
    [ "$services_hash" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "services.jar hash mismatch: ${services_hash}"
    root_cmd 'ls -l /system/framework/oat/arm64/services.* 2>/dev/null || echo services_preopt_public_absent'
    echo

    echo "## Smartisax package and permissions"
    pm_path="$(adb_shell 'pm path com.smartisax.browser | head -n1')"
    echo "$pm_path"
    [[ "$pm_path" == "package:${NEW_SMARTISAX_APK_PATH}" ]] || die "Smartisax is not served from priv-app"
    package_dump="$(adb_shell 'dumpsys package com.smartisax.browser')"
    grep -E "codePath=|resourcePath=|versionCode=|pkgFlags=|privateFlags=|android.permission.(MANAGE_DEBUGGING|WRITE_SECURE_SETTINGS|ACCESS_WIFI_STATE|READ_FRAME_BUFFER|CAPTURE_VIDEO_OUTPUT|INJECT_EVENTS):" <<<"$package_dump" || true
    grep -q 'versionCode=9 ' <<<"$package_dump" || die "Smartisax PackageManager did not parse versionCode=9"
    grep -q 'android.permission.READ_FRAME_BUFFER: granted=true' <<<"$package_dump" || die "READ_FRAME_BUFFER was not granted to Smartisax"
    echo "smartisax_read_frame_buffer_granted=true"
    echo

    echo "result=PASS_READ_ONLY_V0PORTAL23_SMARTISAX_FRAMEBUFFER_GRANT"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) run_offline_image ;;
  --read-only) run_read_only ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
