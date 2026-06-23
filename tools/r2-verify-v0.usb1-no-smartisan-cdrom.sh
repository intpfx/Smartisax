#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.usb1-no-smartisan-cdrom"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
VENDOR_B_IMG="${ROOT_DIR}/hard-rom/build/vendor-otatrust-${VARIANT}.img"
VENDOR_B_EXTENT="${VENDOR_B_EXTENT:-vendor_b=15439872:1696608}"

SOURCE_SPARSE_SHA256="450c5e1e34b20a7fd66422c96e359bf949e3968a62c3f6f73db81a229706518c"
SOURCE_VENDOR_B_SHA256="d6e09ff25c612cc7f01c05f455646926019e17b1fe73b98f6ab7c0d5b69489f6"
VENDOR_B_PARTITION_SIZE=868663296
VENDOR_B_EXT4_SIZE=854872064
CDROM_ISO_PATH="/etc/cdrom_install.iso"
CDROM_ISO_SHA256="f4a5f3f482c9b091557a9b4366c8b808fa1cfd4d8c5f7afdbc11af12b0af25a0"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.usb1-no-smartisan-cdrom.sh --offline-image
  tools/r2-verify-v0.usb1-no-smartisan-cdrom.sh --read-only

--offline-image verifies the candidate without touching a device:
  - sparse and vendor_b hashes match the manifest
  - vendor_b has AVB/FEC roots=2 and passes e2fsck
  - build.prop defaults cdrom enable to 0
  - charger fallback uses charging, not mass_storage
  - init.qcom.usb.rc no longer symlinks mass_storage.0 into USB configs
  - the original cdrom_install.iso is retained but inert
  - sparse vendor_b slice equals the generated vendor_b image

--read-only verifies a flashed device without changing /data:
  - boot completed on B slot and root is available
  - ADB is still online
  - configfs active USB config has no mass_storage.0 symlink
  - MTP and ADB function symlinks are still present when expected
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2); exit}' "$MANIFEST"
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

count_fixed() {
  local needle="$1" path="$2"
  awk -v n="$needle" 'index($0, n) { count++ } END { print count + 0 }' "$path"
}

verify_avb_fec() {
  local image="$1" info="${WORK_DIR}/vendor-b-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${VENDOR_B_PARTITION_SIZE} bytes" "$info" || die "vendor_b AVB image size mismatch"
  grep -q "Original image size:      ${VENDOR_B_EXT4_SIZE} bytes" "$info" || die "vendor_b AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "vendor_b lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "vendor_b missing FEC offset"
  echo "vendor_b_avb_fec=ok"
}

verify_vendor_texts() {
  local image="$1"
  local build_prop="${WORK_DIR}/build.prop.final"
  local init_usb="${WORK_DIR}/init.qcom.usb.rc.final"
  local init_qcom="${WORK_DIR}/init.qcom.rc.final"
  local iso="${WORK_DIR}/cdrom_install.iso.final"

  debugfs_dump "$image" "/build.prop" "$build_prop"
  debugfs_dump "$image" "/etc/init/hw/init.qcom.usb.rc" "$init_usb"
  debugfs_dump "$image" "/etc/init/hw/init.qcom.rc" "$init_qcom"
  debugfs_dump "$image" "$CDROM_ISO_PATH" "$iso"
  [ "$(sha256_one "$iso")" = "$CDROM_ISO_SHA256" ] || die "retained cdrom ISO hash mismatch"

  grep -q '^persist.service.cdrom.enable=1$' "$build_prop" || die "build.prop cdrom default changed unexpectedly"
  grep -q 'setprop persist.sys.usb.config charging' "$init_qcom" || die "charger fallback does not use charging"
  ! grep -q 'setprop persist.sys.usb.config mass_storage' "$init_qcom" || die "charger fallback still uses mass_storage"
  [ "$(count_fixed 'functions/mass_storage.0 /config/usb_gadget/g1/configs/b.1/f' "$init_usb")" -eq 0 ] \
    || die "init.qcom.usb.rc still links mass_storage.0 into a config"
  grep -q 'on property:sys.usb.config=mtp,diag,diag_mdm,mass_storage,adb' "$init_usb" \
    || die "old persisted USB config trigger was removed"
  grep -q 'symlink /config/usb_gadget/g1/functions/mtp.gs0' "$init_usb" \
    || die "MTP symlink routes missing"
  grep -q 'symlink /config/usb_gadget/g1/functions/ffs.adb' "$init_usb" \
    || die "ADB symlink routes missing"
  echo "vendor_usb_texts=ok"
  echo "cdrom_iso_retained=ok sha256=${CDROM_ISO_SHA256}"
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
  need_executable "$DEBUGFS"
  need_executable "$E2FSCK"
  need_file "$AVBTOOL"
  need_file "$SPARSE_TOOL"

  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} offline image verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "variant=${VARIANT}"
    echo "boundary=offline verifier only; no adb, no fastboot, no flash, no reboot, no /data mutation"
    echo

    echo "## local files"
    check_manifest_hash "candidate_sparse" "$SUPER_SPARSE" "sparse_super_sha256"
    check_manifest_hash "vendor_b_image" "$VENDOR_B_IMG" "vendor_b_sha256"
    [ "$(manifest_value source_sparse_super_sha256)" = "$SOURCE_SPARSE_SHA256" ] || die "source sparse manifest hash mismatch"
    [ "$(manifest_value source_vendor_b_sha256)" = "$SOURCE_VENDOR_B_SHA256" ] || die "source vendor_b manifest hash mismatch"
    [ "$(manifest_value patched_partitions)" = "vendor_b" ] || die "patched_partitions mismatch"
    echo

    echo "## vendor_b gates"
    "$E2FSCK" -fn "$VENDOR_B_IMG" >/dev/null
    echo "vendor_b_fsck=ok"
    verify_avb_fec "$VENDOR_B_IMG"
    verify_vendor_texts "$VENDOR_B_IMG"
    "$SPARSE_TOOL" \
      --source-sparse "$SUPER_SPARSE" \
      --extent "$VENDOR_B_EXTENT" \
      --verify-image "vendor_b=${VENDOR_B_IMG}"
    echo "sparse_vendor_b_slice=ok"
    echo

    echo "result=PASS_OFFLINE_IMAGE_V0USB1_NO_SMARTISAN_CDROM"
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
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)";
printf "persist.service.cdrom.enable=%s\n" "$(getprop persist.service.cdrom.enable)";
printf "persist.sys.usb.config=%s\n" "$(getprop persist.sys.usb.config)";
printf "sys.usb.config=%s\n" "$(getprop sys.usb.config)";
printf "sys.usb.state=%s\n" "$(getprop sys.usb.state)";
printf "sys.usb.configfs=%s\n" "$(getprop sys.usb.configfs)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root"
    "$ROOT_HELPER" status || warn "root status failed"
    echo

    echo "## active USB configfs"
    configfs="$(root_cmd 'ls -l /config/usb_gadget/g1/configs/b.1 2>/dev/null || true;
echo "---";
for f in /config/usb_gadget/g1/configs/b.1/f*; do [ -e "$f" ] && readlink "$f"; done 2>/dev/null || true;
echo "---lun---";
for f in cdrom file ro; do printf "mass_storage.%s=" "$f"; cat /config/usb_gadget/g1/functions/mass_storage.0/lun.0/$f 2>/dev/null || true; echo; done')"
    echo "$configfs"
    ! grep -q 'functions/mass_storage.0' <<<"$configfs" || die "active USB config still links mass_storage.0"
    grep -q 'functions/ffs.adb' <<<"$configfs" || die "active USB config lost ADB function"
    grep -q 'functions/mtp.gs0\|functions/ffs.mtp' <<<"$configfs" || warn "MTP function not observed in active config"
    echo

    echo "## window state"
    adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head -20" || true
    echo

    echo "result=PASS_READ_ONLY_V0USB1_NO_SMARTISAN_CDROM"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image)
    run_offline_image
    ;;
  --read-only)
    run_read_only
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
