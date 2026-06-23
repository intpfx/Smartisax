#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.pm0-services-jar-noop"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SERVICES_JAR_CANDIDATE_SHA256="30ff020c9dead1afba480dfc075b50454723296376feae0b20a1a58e82f763bc"
STOCK_SERVICES_JAR_SHA256="45945c1d1f9f25be8b1db31df5d417504634305d4033e9421f7d3cd416057da6"
STOCK_SERVICES_JAR="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/framework/services.jar"
SERVICES_ART_SHA256="f650b73c2f062aada6b0fdd465e288f5392fdc05d06b68a1c2a6cf2989108c25"
SERVICES_ODEX_SHA256="f7339d7813955f6bdc2334f99e312795414b30c041c1804b91bb68d3a710f70b"
SERVICES_VDEX_SHA256="5f1493119d2c2339f0265ea774065fecaf37f30bc65ee2c730fca5d05a4b0a93"

SERVICES_JAR_PATH="/system/framework/services.jar"
SERVICES_PREOPT_DIR="/system/framework/oat/arm64"
SERVICES_ART_PATH="${SERVICES_PREOPT_DIR}/services.art"
SERVICES_ODEX_PATH="${SERVICES_PREOPT_DIR}/services.odex"
SERVICES_VDEX_PATH="${SERVICES_PREOPT_DIR}/services.vdex"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.pm0-services-jar-noop.sh --offline-image
  tools/r2-verify-v0.pm0-services-jar-noop.sh --read-only

Offline verifier only. It does not touch a live device.

Checks:
  - system_b image hash and AVB/FEC footer
  - ext4 fsck after removing footer on a temporary clone
  - public services.jar is the no-op candidate
  - stock services.jar was replaced after the build-time unique block ownership
    audit; local stock ROM material is used for the no-op delta check
  - public services.art/odex/vdex are absent after the build-time unique block
    ownership audit freed space for the no-op services.jar replacement
  - services.jar changed entries are exactly classes.dex and classes2.dex

--read-only verifies a flashed device without changing /data:
  - boot completed on B slot and root is available
  - public services.jar hash matches the no-op candidate
  - public arm64 services.art/odex/vdex are absent
  - key PackageManager-managed packages still resolve
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1" path="$2" key="$3" expected actual
  need_file "$MANIFEST"
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
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

verify_services_jar_delta() {
  local stock="$1" candidate="$2"
  python3 - "$stock" "$candidate" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
candidate = Path(sys.argv[2])

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

stock_entries = entry_map(stock)
candidate_entries = entry_map(candidate)
if list(stock_entries) != list(candidate_entries):
    raise SystemExit("services.jar entry list/order mismatch")

changed = [
    name for name in stock_entries
    if stock_entries[name]["sha256"] != candidate_entries[name]["sha256"]
]
if changed != ["classes.dex", "classes2.dex"]:
    raise SystemExit(f"unexpected changed services.jar entries: {changed}")
for name, meta in candidate_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"candidate services.jar entry is not STORED: {name}")
if "META-INF/MANIFEST.MF" not in candidate_entries:
    raise SystemExit("candidate services.jar lost META-INF/MANIFEST.MF")
print("services_jar_changed_entries=classes.dex,classes2.dex")
print("services_jar_all_entries_stored=true")
print("services_jar_manifest_retained=true")
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
  rm -f "${WORK_DIR}"/*
  local report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"

  {
    echo "# ${VARIANT} offline image verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=offline image only; no adb, no fastboot, no flash, no reboot, no /data mutation"
    echo

    echo "## local files"
    check_manifest_hash "system_b_image" "$SYSTEM_B_IMG" "system_b_sha256"
    [ "$(manifest_value image_mode)" = "system_b_only_no_super" ] || die "manifest image_mode mismatch"
    [ "$(size_bytes "$SYSTEM_B_IMG")" -eq "$SYSTEM_B_PARTITION_SIZE" ] || die "system_b image size mismatch"
    verify_avb_fec "$SYSTEM_B_IMG"
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
    [ "$(manifest_value services_jar_delete_boundary)" = "unique_block_owner_audited" ] || die "manifest does not record services.jar audit boundary"
    need_file "$STOCK_SERVICES_JAR"
    [ "$(sha256_one "$STOCK_SERVICES_JAR")" = "$STOCK_SERVICES_JAR_SHA256" ] || die "local stock services.jar hash mismatch"
    verify_image_file_hash "$pure" "$SERVICES_JAR_PATH" "$SERVICES_JAR_CANDIDATE_SHA256" "services-jar-public.jar"
    unzip -t "${WORK_DIR}/services-jar-public.jar" >/dev/null
    verify_services_jar_delta "$STOCK_SERVICES_JAR" "${WORK_DIR}/services-jar-public.jar"
    echo

    echo "## services preopt"
    [ "$(manifest_value services_preopt_delete_boundary)" = "unique_block_owner_audited" ] || die "manifest does not record services preopt audit boundary"
    verify_image_path_absent "$pure" "$SERVICES_ART_PATH" "services-art-public"
    verify_image_path_absent "$pure" "$SERVICES_ODEX_PATH" "services-odex-public"
    verify_image_path_absent "$pure" "$SERVICES_VDEX_PATH" "services-vdex-public"
    echo "services_preopt_delete_boundary=unique_block_owner_audited"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0PM0_SERVICES_JAR_NOOP"
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
    textboom_path="$(adb_shell 'cmd package path com.smartisanos.textboom || true' | tail -n 1)"
    grep -q '/system/app/TextBoomArm32/TextBoomArm32.apk' <<<"$textboom_path" \
      || die "TextBoom is not served from /system/app/TextBoomArm32"
    webview_path="$(adb_shell 'cmd package path com.android.webview || true' | tail -n 1)"
    grep -q '/system/app/webview/webview.apk' <<<"$webview_path" \
      || die "WebView is not served from /system/app/webview"
    echo

    echo "result=PASS_READ_ONLY_V0PM0_SERVICES_JAR_NOOP"
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
    run_offline_image
    ;;
  --read-only)
    need_file "$ROOT_HELPER"
    run_read_only
    ;;
esac
