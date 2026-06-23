#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/v0.37b-textboom-live-system-libs-deodex}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/textboom-shadow-repair-${TS}.txt}"
REMOTE_SCRIPT="/data/local/tmp/r2-repair-v0.37b-textboom-shadow-${TS}.sh"
LOCAL_REMOTE_SCRIPT="${OUT_DIR}/textboom-shadow-repair-${TS}.remote.sh"
PKG="com.smartisanos.textboom"
SYSTEM_APK="/system/app/TextBoom/TextBoom.apk"
SYSTEM_DIR="/system/app/TextBoom"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-repair-v0.37b-textboom-shadow.sh --dry-run
  tools/r2-repair-v0.37b-textboom-shadow.sh --apply

--dry-run snapshots the current TextBoom PackageManager state and prints the
remote repair plan without changing /data.

--apply performs the explicitly approved v0.37b TextBoom updated-system shadow
repair:
  - backs up packages.xml, package restrictions, packages.list, and the
    /data/app TextBoom shadow into /data/system/smartisax-textboom-shadow-repair
  - rewrites only the com.smartisanos.textboom PackageManager entry to point at
    /system/app/TextBoom while preserving the existing userId/signature/perms
  - removes the disabled updated-package entry for com.smartisanos.textboom
  - removes TextBoom-specific package_cache files
  - moves the /data/app shadow out of the PackageManager scan path
  - stops Android framework before committing the package-state rewrite, then
    syncs and reboots

Use --apply only after explicit user confirmation for this /data repair.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

section() {
  log ""
  log "## $*"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

remote_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

root_cmd() {
  adb_device shell "$KP -c $(remote_quote "$*")" 2>&1 | tr -d '\r'
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    adb devices -l >&2 || true
    die "adb device ${SERIAL} is not online"
  fi
}

snapshot_state() {
  section "device state"
  adb_shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop sys.usb.state' | tee -a "$REPORT"
  section "root state"
  root_cmd 'id; getenforce; getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate' | tee -a "$REPORT"
  section "TextBoom package state"
  adb_shell "pm path ${PKG} 2>/dev/null || true" | tee -a "$REPORT"
  adb_shell "cmd package list packages -u -f | grep -F '=${PKG}' || true" | tee -a "$REPORT"
  adb_shell "dumpsys package ${PKG} | grep -E 'Package \\[|codePath=|resourcePath=|legacyNativeLibraryDir=|versionCode=|versionName=|pkgFlags=|privateFlags=|User 0:' | sed -n '1,180p'" | tee -a "$REPORT"
  section "TextBoom data/package-cache state"
  root_cmd "ls -ld /data/app/${PKG}-* 2>/dev/null || true; find /data/system/package_cache -maxdepth 2 \\( -iname '*TextBoom*' -o -iname '*textboom*' \\) -print 2>/dev/null || true" | tee -a "$REPORT"
}

write_remote_script() {
  mkdir -p "$OUT_DIR"
  cat > "$LOCAL_REMOTE_SCRIPT" <<'REMOTE'
#!/system/bin/sh
set -eu

mode="${1:-dry-run}"
ts="${2:-unknown-ts}"
pkg="com.smartisanos.textboom"
system_dir="/system/app/TextBoom"
system_apk="/system/app/TextBoom/TextBoom.apk"
system_lib_dir="/system/app/TextBoom/lib"
packages="/data/system/packages.xml"
backup_root="/data/system/smartisax-textboom-shadow-repair"
backup="${backup_root}/${ts}"

fail() {
  echo "error: $*" >&2
  exit 1
}

pm_path="$(pm path "$pkg" 2>/dev/null | sed -n '1p' || true)"
data_app_apk="$(printf '%s\n' "$pm_path" | sed -n 's#^package:\(/data/app/[^/]*/base.apk\)$#\1#p' | sed -n '1p')"
data_app_dir="${data_app_apk%/base.apk}"

echo "remote_mode=${mode}"
echo "pkg=${pkg}"
echo "pm_path_before=${pm_path}"
echo "data_app_dir=${data_app_dir}"
echo "system_apk=${system_apk}"
echo "backup_dir=${backup}"

[ -f "$system_apk" ] || fail "missing system TextBoom APK: $system_apk"
[ -d "$system_dir" ] || fail "missing system TextBoom dir: $system_dir"
[ -d "${system_dir}/lib/arm" ] || fail "missing system TextBoom arm libs"
[ -f "$packages" ] || fail "missing packages.xml"
case "$data_app_dir" in
  /data/app/com.smartisanos.textboom-*) ;;
  *) fail "TextBoom is not an expected /data/app shadow path: ${pm_path}" ;;
esac
[ -f "${data_app_dir}/base.apk" ] || fail "missing active data shadow base.apk: ${data_app_dir}/base.apk"

echo "system_hash=$(sha256sum "$system_apk" | awk '{print $1}')"
echo "data_hash=$(sha256sum "${data_app_dir}/base.apk" | awk '{print $1}')"
echo "system_lib_count=$(find "${system_dir}/lib/arm" -maxdepth 1 -type f -name '*.so' | wc -l | tr -d ' ')"
echo "packages_xml_entries_before:"
grep -n -A4 -B2 "$pkg" "$packages" || true
echo "package_cache_before:"
find /data/system/package_cache -maxdepth 2 \( -iname '*TextBoom*' -o -iname '*textboom*' \) -print 2>/dev/null || true

if [ "$mode" = "dry-run" ]; then
  echo "result=DRY_RUN_ONLY"
  exit 0
fi

[ "$mode" = "apply" ] || fail "unsupported mode: $mode"

mkdir -p "$backup"
cp -p "$packages" "${backup}/packages.xml.before"
[ -f /data/system/packages.list ] && cp -p /data/system/packages.list "${backup}/packages.list.before" || true
if [ -f /data/system/users/0/package-restrictions.xml ]; then
  mkdir -p "${backup}/users/0"
  cp -p /data/system/users/0/package-restrictions.xml "${backup}/users/0/package-restrictions.xml.before"
fi
cp -pR "$data_app_dir" "${backup}/data-app-shadow"

tmp="${packages}.smartisax-${ts}.tmp"
awk -v pkg="$pkg" '
  BEGIN { skip = 0 }
  $0 ~ "<updated-package name=\"" pkg "\"" { skip = 1; next }
  skip == 1 {
    if ($0 ~ "</updated-package>") { skip = 0 }
    next
  }
  $0 ~ "<package name=\"" pkg "\"" {
    gsub(/codePath="[^"]+"/, "codePath=\"/system/app/TextBoom\"")
    gsub(/nativeLibraryPath="[^"]+"/, "nativeLibraryPath=\"/system/app/TextBoom/lib\"")
    gsub(/ publicFlags="940064453"/, " publicFlags=\"940064325\"")
    gsub(/ isOrphaned="true"/, "")
  }
  { print }
' "$packages" > "$tmp"

grep -q "<package name=\"${pkg}\" codePath=\"/system/app/TextBoom\"" "$tmp" \
  || fail "rewritten packages.xml is missing system TextBoom package entry"
if grep -q "<updated-package name=\"${pkg}\"" "$tmp"; then
  fail "rewritten packages.xml still contains TextBoom updated-package entry"
fi

echo "stopping_android_framework=begin"
am force-stop "$pkg" >/dev/null 2>&1 || true
stop
sleep 3
echo "stopping_android_framework=done"

mv "$tmp" "$packages"
chown system:system "$packages"
chmod 660 "$packages"
restorecon "$packages" >/dev/null 2>&1 || true

echo "removing_textboom_package_cache=begin"
find /data/system/package_cache -maxdepth 2 \( -iname '*TextBoom*' -o -iname '*textboom*' \) -print -exec rm -f {} \; 2>/dev/null || true
echo "removing_textboom_package_cache=done"

mv "$data_app_dir" "${backup}/data-app-shadow-moved-from-scan-path"
sync

echo "packages_xml_entries_after:"
grep -n -A4 -B2 "$pkg" "$packages" || true
echo "result=APPLIED_REBOOTING"
reboot
REMOTE
  chmod +x "$LOCAL_REMOTE_SCRIPT"
}

push_remote_script() {
  adb_device push "$LOCAL_REMOTE_SCRIPT" "$REMOTE_SCRIPT" | tee -a "$REPORT"
  root_cmd "chmod 755 ${REMOTE_SCRIPT}" | tee -a "$REPORT"
}

run_remote_script() {
  local mode="$1"
  section "remote ${mode}"
  set +e
  adb_device shell "$KP" -c "$REMOTE_SCRIPT $mode $TS" 2>&1 | tr -d '\r' | tee -a "$REPORT"
  local status=${PIPESTATUS[0]}
  set -e
  if [ "$mode" = "apply" ]; then
    log "remote_apply_exit=${status}"
    return 0
  fi
  [ "$status" -eq 0 ] || die "remote ${mode} failed with status ${status}"
}

wait_for_boot() {
  section "wait for boot"
  local i
  for i in $(seq 1 90); do
    local state
    local boot
    local slot
    local bootanim
    state="$(adb devices | awk -v s="$SERIAL" '$1 == s {print $2}' | sed -n '1p')"
    if [ "$state" = "device" ]; then
      boot="$(adb_shell 'getprop sys.boot_completed' | tail -n 1)"
      slot="$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)"
      bootanim="$(adb_shell 'getprop init.svc.bootanim' | tail -n 1)"
      log "boot_wait attempt=${i} state=${state} boot=${boot} slot=${slot} bootanim=${bootanim}"
      if [ "$boot" = "1" ] && [ "$slot" = "_b" ] && [ "$bootanim" = "stopped" ]; then
        return 0
      fi
    else
      log "boot_wait attempt=${i} state=${state:-missing}"
    fi
    sleep 3
  done
  die "device did not reach boot_completed on B slot"
}

mode=""
case "${1:-}" in
  --dry-run)
    mode="dry-run"
    ;;
  --apply)
    mode="apply"
    ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_device
mkdir -p "$OUT_DIR"
: > "$REPORT"

log "# v0.37b TextBoom /data shadow repair"
log "timestamp=${TS}"
log "mode=${mode}"
log "serial=${SERIAL}"
log "report=${REPORT}"
log "boundary=mutates /data only in --apply; no flash, no fastboot, no partition writes"

snapshot_state
write_remote_script
push_remote_script
run_remote_script "$mode"

if [ "$mode" = "apply" ]; then
  wait_for_boot
  section "post-reboot package state"
  post_path="$(adb_shell "pm path ${PKG} 2>/dev/null | sed -n '1p' || true")"
  printf '%s\n' "$post_path" | tee -a "$REPORT"
  adb_shell "dumpsys package ${PKG} | grep -E 'Package \\[|codePath=|resourcePath=|legacyNativeLibraryDir=|versionCode=|versionName=|pkgFlags=|privateFlags=|User 0:' | sed -n '1,180p'" | tee -a "$REPORT"
  [ "$post_path" = "package:${SYSTEM_APK}" ] || die "post-repair TextBoom path is not ${SYSTEM_APK}: ${post_path}"
  if adb_shell "dumpsys package ${PKG} | grep -q UPDATED_SYSTEM_APP && echo updated || true" | grep -q updated; then
    die "post-repair TextBoom still has UPDATED_SYSTEM_APP"
  fi
fi

section "result"
log "report=${REPORT}"
if [ "$mode" = "dry-run" ]; then
  log "result=DRY_RUN_ONLY"
else
  log "result=APPLY_FINISHED_VERIFY_WITH_POST_REPAIR_SCRIPT"
fi
