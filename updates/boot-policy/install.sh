#!/system/bin/sh
set -eu

: "${SMARTISAX_ROOT:?missing SMARTISAX_ROOT}"
: "${SMARTISAX_PACKAGE_ID:?missing SMARTISAX_PACKAGE_ID}"
: "${SMARTISAX_PACKAGE_VERSION:?missing SMARTISAX_PACKAGE_VERSION}"
: "${SMARTISAX_STATE_DIR:?missing SMARTISAX_STATE_DIR}"

apm_id="smartisax_boot_policy"
apm_dir="/data/adb/modules/$apm_id"
module_dir="$SMARTISAX_ROOT/modules/$SMARTISAX_PACKAGE_ID"
payload_dir="$SMARTISAX_PACKAGE_DIR/payload"
bin_dir="$SMARTISAX_ROOT/bin"
policy_dir="$SMARTISAX_ROOT/policy.d"
log_dir="$SMARTISAX_ROOT/logs"
runner="$bin_dir/boot-policy-runner.sh"
ap_dir="/data/adb/ap"
ap_bin_dir="$ap_dir/bin"
apd="/data/adb/apd"
runtime_marker="$SMARTISAX_STATE_DIR/runtime-installed-by-boot-policy.txt"

[ -f "$payload_dir/apd" ] || { echo "Missing payload: apd" >&2; exit 1; }
[ -f "$payload_dir/busybox" ] || { echo "Missing payload: busybox" >&2; exit 1; }
[ -f "$payload_dir/magiskpolicy" ] || { echo "Missing payload: magiskpolicy" >&2; exit 1; }
[ -f "$payload_dir/resetprop" ] || { echo "Missing payload: resetprop" >&2; exit 1; }

if [ ! -e "$apd" ] && [ ! -d "$ap_dir" ]; then
  echo 1 > "$runtime_marker"
else
  echo 0 > "$runtime_marker"
fi

mkdir -p /data/adb/modules "$apm_dir" "$module_dir" "$bin_dir" "$policy_dir" "$log_dir" "$ap_bin_dir" "$ap_dir/log"
chmod 0700 "$SMARTISAX_ROOT" "$SMARTISAX_ROOT/modules" "$module_dir" "$bin_dir" "$policy_dir" "$log_dir"
chmod 0755 /data/adb/modules "$apm_dir"
chmod 0700 "$ap_dir" "$ap_dir/log"

cp "$payload_dir/apd" "$apd"
cp "$payload_dir/busybox" "$ap_bin_dir/busybox"
cp "$payload_dir/magiskpolicy" "$ap_bin_dir/magiskpolicy"
cp "$payload_dir/resetprop" "$ap_bin_dir/resetprop"
chmod 0755 "$apd" "$ap_bin_dir/busybox" "$ap_bin_dir/magiskpolicy" "$ap_bin_dir/resetprop"

rm -f "$apm_dir/remove" "$apm_dir/disable"

cat > "$apm_dir/module.prop" <<EOF
id=$apm_id
name=Smartisax Boot Policy
version=$SMARTISAX_PACKAGE_VERSION
versionCode=1
author=Smartisax
description=Runs Smartisax systemless policy checks after Android boot completes.
EOF

touch "$apm_dir/skip_mount"

cat > "$apm_dir/boot-completed.sh" <<'EOF'
#!/system/bin/sh
MODDIR=${0%/*}
ROOT_DIR=/data/adb/smartisax
RUNNER="$ROOT_DIR/bin/boot-policy-runner.sh"
LOG="$ROOT_DIR/logs/boot-policy.log"

mkdir -p "$ROOT_DIR/logs"
if [ -x "$RUNNER" ]; then
  "$RUNNER" boot-completed >> "$LOG" 2>&1 &
else
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') runner missing: $RUNNER" >> "$LOG"
fi
EOF

cat > "$apm_dir/action.sh" <<'EOF'
#!/system/bin/sh
ROOT_DIR=/data/adb/smartisax
RUNNER="$ROOT_DIR/bin/boot-policy-runner.sh"
LOG="$ROOT_DIR/logs/boot-policy.log"
if [ -x "$RUNNER" ]; then
  "$RUNNER" action >> "$LOG" 2>&1
  tail -80 "$LOG"
else
  echo "runner missing: $RUNNER"
  exit 1
fi
EOF

cat > "$runner" <<'EOF'
#!/system/bin/sh
set -u

ROOT_DIR="${SMARTISAX_ROOT:-/data/adb/smartisax}"
TRIGGER="${1:-manual}"
POLICY_DIR="$ROOT_DIR/policy.d"
LOG_DIR="$ROOT_DIR/logs"
RUN_LOG="$LOG_DIR/boot-policy.log"
STATE_DIR="$ROOT_DIR/modules/boot-policy"

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
  echo "$(timestamp) [$TRIGGER] $*"
}

ensure_dirs() {
  mkdir -p "$ROOT_DIR" "$ROOT_DIR/modules" "$POLICY_DIR" "$LOG_DIR" "$STATE_DIR"
  touch "$RUN_LOG"
  chmod 0700 "$ROOT_DIR" "$ROOT_DIR/modules" "$POLICY_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
  chmod 0600 "$RUN_LOG" 2>/dev/null || true
}

current_default_browser() {
  cmd package resolve-activity --brief -a android.intent.action.VIEW -d https://example.com 2>/dev/null \
    | awk -F/ 'NF > 1 {print $1; exit}'
}

wait_for_browser_resolver() {
  case "$TRIGGER" in
    boot-completed)
      i=0
      while [ "$i" -lt 120 ]; do
        current="$(current_default_browser)"
        if [ -n "$current" ]; then
          log "browser resolver ready after ${i} checks: $current"
          return 0
        fi
        sleep 5
        i=$((i + 1))
      done
      log "browser resolver unavailable after wait; user may still be locked"
      ;;
  esac
}

record_state() {
  {
    echo "last_run=$(timestamp)"
    echo "trigger=$TRIGGER"
    echo "uid=$(id 2>/dev/null || true)"
    echo "slot=$(getprop ro.boot.slot_suffix 2>/dev/null || true)"
    echo "boot_completed=$(getprop sys.boot_completed 2>/dev/null || true)"
    echo "verifiedbootstate=$(getprop ro.boot.verifiedbootstate 2>/dev/null || true)"
    echo "default_browser=$(current_default_browser)"
  } > "$STATE_DIR/status.txt"
  chmod 0600 "$STATE_DIR/status.txt" 2>/dev/null || true
}

run_policy_scripts() {
  [ -d "$POLICY_DIR" ] || return 0
  for script in "$POLICY_DIR"/*.sh; do
    [ -f "$script" ] || continue
    [ -x "$script" ] || {
      log "skip non-executable policy: $script"
      continue
    }
    log "run policy: $script"
    SMARTISAX_ROOT="$ROOT_DIR" SMARTISAX_TRIGGER="$TRIGGER" sh "$script"
    rc=$?
    log "policy exit $rc: $script"
  done
}

main() {
  ensure_dirs
  log "start uid=$(id 2>/dev/null || true) boot_completed=$(getprop sys.boot_completed 2>/dev/null || true)"
  wait_for_browser_resolver
  record_state
  run_policy_scripts
  record_state
  log "done"
}

main "$@" >> "$RUN_LOG" 2>&1
EOF

cat > "$policy_dir/20-modern-browser-default.sh" <<'EOF'
#!/system/bin/sh
set -u

ROOT_DIR="${SMARTISAX_ROOT:-/data/adb/smartisax}"
STATE_DIR="$ROOT_DIR/updates/modern-browser"
PKG="org.cromite.cromite"

[ -d "$STATE_DIR" ] || {
  echo "modern-browser not installed in Smartisax state; skip"
  exit 0
}

pm path "$PKG" >/dev/null 2>&1 || {
  echo "modern-browser package missing: $PKG"
  exit 0
}

current="$(cmd package resolve-activity --brief -a android.intent.action.VIEW -d https://example.com 2>/dev/null \
  | awk -F/ 'NF > 1 {print $1; exit}')"

if [ -z "$current" ]; then
  echo "modern-browser default resolver unavailable; skip"
  exit 0
fi

if [ "$current" = "$PKG" ]; then
  echo "modern-browser default ok: $PKG"
  exit 0
fi

echo "modern-browser default repair: $current -> $PKG"
cmd role add-role-holder --user 0 android.app.role.BROWSER "$PKG" 0 || true
after="$(cmd package resolve-activity --brief -a android.intent.action.VIEW -d https://example.com 2>/dev/null \
  | awk -F/ 'NF > 1 {print $1; exit}')"
echo "modern-browser default after repair: $after"
EOF

chmod 0644 "$apm_dir/module.prop" "$apm_dir/skip_mount"
chmod 0755 "$apm_dir/boot-completed.sh" "$apm_dir/action.sh" "$runner" "$policy_dir/20-modern-browser-default.sh"
chmod 0600 "$SMARTISAX_STATE_DIR/manifest.json" 2>/dev/null || true

cat > "$module_dir/status.txt" <<EOF
id=$SMARTISAX_PACKAGE_ID
version=$SMARTISAX_PACKAGE_VERSION
apatch_module=$apm_id
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
runner=$runner
policy_dir=$policy_dir
apd=$apd
runtime_installed_by_boot_policy=$(cat "$runtime_marker" 2>/dev/null || echo 0)
EOF
chmod 0600 "$module_dir/status.txt" "$runtime_marker"

"$runner" install
echo "boot-policy installed: $apm_id"
