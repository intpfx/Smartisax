#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"

VARIANT="v0.pm1-pms-cache-allowlist"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
SYSTEM_MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
BASE_SERVICES="${ROOT_DIR}/hard-rom/build/framework/services-pm-noop-roundtrip.jar"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SERVICES_JAR_CANDIDATE_SHA256="84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40"
BASE_SERVICES_JAR_SHA256="30ff020c9dead1afba480dfc075b50454723296376feae0b20a1a58e82f763bc"

SERVICES_JAR_PATH="/system/framework/services.jar"
SERVICES_PREOPT_DIR="/system/framework/oat/arm64"
SERVICES_ART_PATH="${SERVICES_PREOPT_DIR}/services.art"
SERVICES_ODEX_PATH="${SERVICES_PREOPT_DIR}/services.odex"
SERVICES_VDEX_PATH="${SERVICES_PREOPT_DIR}/services.vdex"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.pm1-pms-cache-allowlist.sh --offline-image
  tools/r2-verify-v0.pm1-pms-cache-allowlist.sh --read-only

Offline verifier only. It does not touch a live device.

Checks:
  - system_b image hash, sparse super hash, AVB/FEC footer, and ext4 fsck
  - sparse system_b slice matches the image
  - public services.jar is the pm1 candidate
  - public services.art/odex/vdex remain absent
  - services.jar changed entries are only allowed dex entries
  - SmartisaxPackagePolicy exists and ParallelPackageParser calls it
  - key PackageManager classes remain byte-identical to the v0.pm0 base

--read-only verifies a flashed device without changing /data.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

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

copy_clone_or_plain() {
  local src="$1" dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
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

verify_services_jar_delta_and_policy() {
  local base="$1" candidate="$2" base_decoded="$3" candidate_decoded="$4"
  python3 - "$base" "$candidate" "$base_decoded" "$candidate_decoded" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
candidate = Path(sys.argv[2])
base_decoded = Path(sys.argv[3])
candidate_decoded = Path(sys.argv[4])

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

base_entries = entry_map(base)
candidate_entries = entry_map(candidate)
if list(base_entries) != list(candidate_entries):
    raise SystemExit("services.jar entry list/order mismatch")

changed = [name for name in base_entries if base_entries[name]["sha256"] != candidate_entries[name]["sha256"]]
allowed = {"classes.dex", "classes2.dex"}
if not changed or any(name not in allowed for name in changed) or "classes.dex" not in changed:
    raise SystemExit(f"unexpected changed services.jar entries: {changed}")
for name, meta in candidate_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"candidate services.jar entry is not STORED: {name}")
if "META-INF/MANIFEST.MF" not in candidate_entries:
    raise SystemExit("candidate services.jar lost META-INF/MANIFEST.MF")

def find_one(root: Path, rel_tail: str) -> Path:
    matches = [path for path in root.rglob(Path(rel_tail).name) if str(path).endswith(rel_tail)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {rel_tail} under {root}, found {len(matches)}")
    return matches[0]

policy = find_one(candidate_decoded, "com/android/server/pm/SmartisaxPackagePolicy.smali")
parser = find_one(candidate_decoded, "com/android/server/pm/ParallelPackageParser.smali")
policy_text = policy.read_text(encoding="utf-8")
parser_text = parser.read_text(encoding="utf-8")
for needle in [
    "/system/app/SmartisaxShell",
    "/system/app/TextBoomArm32",
    "/system/app/TextBoom",
    "/system/priv-app/Sidebar",
    "shouldBypassPackageCache",
]:
    if needle not in policy_text:
        raise SystemExit(f"SmartisaxPackagePolicy missing {needle}")
for needle in [
    "SmartisaxPackagePolicy;->shouldBypassPackageCache",
    "SmartisaxPMS",
    "Bypass package parser cache for ",
    "parsePackage(Ljava/io/File;IZ)",
]:
    if needle not in parser_text:
        raise SystemExit(f"ParallelPackageParser missing {needle}")

same_classes = [
    "com/android/server/pm/parsing/PackageCacher.smali",
    "com/android/server/pm/parsing/PackageParser2.smali",
    "com/android/server/pm/PackageAbiHelperImpl.smali",
    "com/android/server/pm/PackageManagerServiceUtils.smali",
    "com/android/server/pm/Settings.smali",
]
for rel in same_classes:
    base_file = find_one(base_decoded, rel)
    candidate_file = find_one(candidate_decoded, rel)
    if base_file.read_bytes() != candidate_file.read_bytes():
        raise SystemExit(f"unexpected pm1 change outside ParallelPackageParser/policy: {rel}")

pms_base = find_one(base_decoded, "com/android/server/pm/PackageManagerService.smali")
pms_candidate = find_one(candidate_decoded, "com/android/server/pm/PackageManagerService.smali")
pms_base_text = pms_base.read_text(encoding="utf-8")
pms_candidate_text = pms_candidate.read_text(encoding="utf-8")
if pms_base_text != pms_candidate_text:
    normalized_base = pms_base_text.replace("const-string/jumbo", "const-string")
    normalized_candidate = pms_candidate_text.replace("const-string/jumbo", "const-string")
    if normalized_base != normalized_candidate:
        raise SystemExit("unexpected PackageManagerService change after const-string jumbo normalization")
    print("package_manager_service_const_string_jumbo_only=true")
else:
    print("package_manager_service_byte_identical=true")

print("services_jar_changed_entries=" + ",".join(changed))
print("services_jar_all_entries_stored=true")
print("services_jar_manifest_retained=true")
print("smartisax_policy_helper=ok")
print("parallel_package_parser_policy_call=ok")
print("pms_neighbor_classes_byte_identical_or_jumbo_equivalent=true")
PY
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
  rm -rf "${WORK_DIR:?}"/*
  local report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"

  {
    echo "# ${VARIANT} offline image verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=offline image only; no adb, no fastboot, no flash, no reboot, no /data mutation"
    echo

    echo "## local files"
    check_manifest_hash "$SYSTEM_MANIFEST" "system_b_image" "$SYSTEM_B_IMG" "system_b_sha256"
    [ "$(manifest_value "$SYSTEM_MANIFEST" image_mode)" = "system_b_from_v0pm0_sparse" ] || die "system manifest image_mode mismatch"
    [ "$(size_bytes "$SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b image size mismatch"
    check_manifest_hash "$SUPER_MANIFEST" "super_sparse_image" "$SUPER_SPARSE" "super_sparse_sha256"
    [ "$(manifest_value "$SUPER_MANIFEST" patched_partitions)" = "system_b" ] || die "super manifest patched_partitions mismatch"
    verify_avb_fec "$SYSTEM_B_IMG"
    echo

    echo "## sparse system_b slice"
    "$SPARSE_TOOL" \
      --source-sparse "$SUPER_SPARSE" \
      --extent "$SYSTEM_B_EXTENT" \
      --verify-image "system_b=${SYSTEM_B_IMG}"
    echo

    echo "## ext4 clone fsck"
    pure="${WORK_DIR}/system-b-pure-ext4.img"
    copy_clone_or_plain "$SYSTEM_B_IMG" "$pure"
    python3 "$AVBTOOL" erase_footer --image "$pure"
    [ "$(size_bytes "$pure")" -eq "$SYSTEM_B_EXT4_SIZE" ] || die "pure ext4 size mismatch"
    "$E2FSCK" -fn "$pure" >/dev/null
    echo "system_b_ext4_fsck=ok"
    echo

    echo "## services.jar"
    [ "$(sha256_one "$BASE_SERVICES")" = "$BASE_SERVICES_JAR_SHA256" ] || die "base v0.pm0 services.jar hash mismatch"
    [ "$(manifest_value "$SYSTEM_MANIFEST" services_jar_delete_boundary)" = "unique_block_owner_audited" ] || die "manifest does not record services.jar audit boundary"
    verify_image_file_hash "$pure" "$SERVICES_JAR_PATH" "$SERVICES_JAR_CANDIDATE_SHA256" "services-jar-public.jar"
    unzip -t "${WORK_DIR}/services-jar-public.jar" >/dev/null
    rm -rf "${WORK_DIR}/base-decoded" "${WORK_DIR}/candidate-decoded"
    "$JAVA_BIN" -jar "$APKTOOL" d -f -o "${WORK_DIR}/base-decoded" "$BASE_SERVICES" >/dev/null
    "$JAVA_BIN" -jar "$APKTOOL" d -f -o "${WORK_DIR}/candidate-decoded" "${WORK_DIR}/services-jar-public.jar" >/dev/null
    verify_services_jar_delta_and_policy \
      "$BASE_SERVICES" \
      "${WORK_DIR}/services-jar-public.jar" \
      "${WORK_DIR}/base-decoded" \
      "${WORK_DIR}/candidate-decoded"
    echo

    echo "## services preopt"
    [ "$(manifest_value "$SYSTEM_MANIFEST" services_preopt_public_absent)" = "true" ] || die "manifest does not record services preopt absence"
    verify_image_path_absent "$pure" "$SERVICES_ART_PATH" "services-art-public"
    verify_image_path_absent "$pure" "$SERVICES_ODEX_PATH" "services-odex-public"
    verify_image_path_absent "$pure" "$SERVICES_VDEX_PATH" "services-vdex-public"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0PM1_PMS_CACHE_ALLOWLIST"
  } 2>&1 | tee "$report"

  echo "report=${report}"
}

run_read_only() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"

  {
    echo "# ${VARIANT} live read-only verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "serial=${SERIAL}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no package-cache clear, no /data cleanup"
    echo

    echo "## adb"
    adb devices -l
    adb_available || die "adb device ${SERIAL} is not online"
    echo

    echo "## boot state"
    adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)";
printf "sys.system_server.start_count=%s\n" "$(getprop sys.system_server.start_count)";
printf "system_server_pid=%s\n" "$(pidof system_server)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root"
    "$ROOT_HELPER" status
    echo

    echo "## services.jar"
    services_hash="$(root_cmd 'sha256sum /system/framework/services.jar' | awk '/services.jar/ {print $1; exit}')"
    echo "services_jar_sha256=${services_hash}"
    [ "$services_hash" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "services.jar hash mismatch: ${services_hash}"
    for path in \
      /system/framework/oat/arm64/services.art \
      /system/framework/oat/arm64/services.odex \
      /system/framework/oat/arm64/services.vdex
    do
      state="$(root_cmd "test -e ${path} && echo present || echo absent" | tail -n 1)"
      echo "${path}=${state}"
      [ "$state" = "absent" ] || die "stale services preopt still present: ${path}"
    done
    echo

    echo "## package-manager smoke"
    adb_shell 'cmd package path com.android.webview || true;
cmd package path com.smartisanos.textboom || true;
cmd package path com.smartisax.browser || true;
cmd package path com.smartisanos.sidebar || true;
dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing" | head -n 8 || true'
    smartisax_path="$(adb_shell 'cmd package path com.smartisax.browser || true' | tail -n 1)"
    grep -q '/system/app/SmartisaxShell/SmartisaxShell.apk' <<<"$smartisax_path" \
      || die "Smartisax is not served from /system/app/SmartisaxShell"
    textboom_path="$(adb_shell 'cmd package path com.smartisanos.textboom || true' | tail -n 1)"
    grep -q '/system/app/TextBoomArm32/TextBoomArm32.apk' <<<"$textboom_path" \
      || die "TextBoom is not served from /system/app/TextBoomArm32"
    sidebar_path="$(adb_shell 'cmd package path com.smartisanos.sidebar || true' | tail -n 1)"
    grep -q '/system/priv-app/Sidebar/Sidebar.apk' <<<"$sidebar_path" \
      || die "Sidebar is not served from /system/priv-app/Sidebar"
    webview_path="$(adb_shell 'cmd package path com.android.webview || true' | tail -n 1)"
    grep -q '/system/app/webview/webview.apk' <<<"$webview_path" \
      || die "WebView is not served from /system/app/webview"
    echo

    echo "## webview smoke"
    adb_shell 'dumpsys webviewupdate | sed -n "1,80p"'
    adb_shell 'dumpsys webviewupdate | grep -E "Current WebView package|relro|dirty" || true'
    echo

    echo "## SmartisaxPMS log smoke"
    pms_log="$(adb_shell 'logcat -d -s SmartisaxPMS 2>/dev/null | tail -n 40 || true')"
    printf '%s\n' "$pms_log"
    if ! grep -q "Bypass package parser cache for" <<<"$pms_log"; then
      warn "SmartisaxPMS bypass lines were not found in current logcat buffer"
    fi
    fatal_scan="$(adb_shell 'logcat -d -b all -t 1500 2>/dev/null | grep -Ei "PackageManager.*(FATAL|PackageParserException|Failed to parse|scan.*failed)|SystemServer.*RuntimeException" | tail -n 30 || true')"
    if [ -n "$fatal_scan" ]; then
      printf '%s\n' "$fatal_scan"
      die "recent fatal package/system_server markers found"
    fi
    echo "fatal_package_scan_markers=absent"
    echo

    echo "result=PASS_READ_ONLY_V0PM1_PMS_CACHE_ALLOWLIST"
  } 2>&1 | tee "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image) ;;
  --read-only) ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

case "$1" in
  --offline-image)
    need_executable "$E2FSCK"
    need_executable "$DEBUGFS"
    need_file "$AVBTOOL"
    need_file "$SPARSE_TOOL"
    need_executable "$JAVA_BIN"
    need_file "$APKTOOL"
    run_offline_image
    ;;
  --read-only)
    need_file "$ROOT_HELPER"
    run_read_only
    ;;
esac
