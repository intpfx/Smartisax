#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
SQLITE3="${SQLITE3:-sqlite3}"

DB_REMOTE="/data/user/0/com.smartisanos.launcher/databases/launcher.db"
DB_JOURNAL_REMOTE="/data/user/0/com.smartisanos.launcher/databases/launcher.db-journal"
DB_WAL_REMOTE="/data/user/0/com.smartisanos.launcher/databases/launcher.db-wal"
DB_SHM_REMOTE="/data/user/0/com.smartisanos.launcher/databases/launcher.db-shm"
TMP_REMOTE="/data/local/tmp/launcher-v0.4-shortcut-clean.db"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/live-launcher"

target_packages=(
  com.smartisanos.gamestore
  com.smartisanos.compass
  com.sohu.inputmethod.sogou.chuizi
  com.iflytek.inputmethod.smartisan
  com.android.email
  com.smartisanos.handinhand
  com.smartisanos.writer
  com.smartisanos.notes
  com.smartisanos.calculator
  com.smartisanos.recharge
  com.smartisanos.cloudgallery
  com.smartisanos.recorder
  com.smartisanos.launcher.themes
  com.smartisanos.launcher.theme.aero
  com.smartisanos.launcher.theme.lightblue
  com.smartisanos.launcher.theme.trans
  com.smartisanos.launcher.theme.bamboo
  com.smartisanos.launcher.theme.glime
  com.smartisanos.launcher.theme.leaf
  com.smartisanos.launcher.theme.raven
)

usage() {
  cat <<'EOF'
Usage:
  tools/r2-clean-v0.4-launcher-shortcuts.sh [--dry-run]
  tools/r2-clean-v0.4-launcher-shortcuts.sh --apply

This edits only Smartisan Launcher user data after v0.4 has booted:
  - table_iteminfos rows whose packageName is one of the v0.4 removed packages
  - table_icons rows owned by those launcher items

Default mode is --dry-run. It pulls a backup DB and prints the rows that would
be removed. Use --apply only after the v0.4 ROM boots successfully.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

remote_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

root_cmd() {
  adb -s "$SERIAL" shell "$KP -c $(remote_quote "$*")"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    echo "Device $SERIAL is not available over adb." >&2
    adb devices >&2
    exit 1
  fi
}

sql_in_list() {
  local package_name
  local first=1
  for package_name in "${target_packages[@]}"; do
    if [ "$first" -eq 0 ]; then
      printf ","
    fi
    first=0
    printf "'%s'" "$(printf "%s" "$package_name" | sed "s/'/''/g")"
  done
}

pull_launcher_db() {
  local out_db="$1"
  root_cmd "cp $(remote_quote "$DB_REMOTE") $(remote_quote "$TMP_REMOTE") && chmod 0644 $(remote_quote "$TMP_REMOTE")"
  adb -s "$SERIAL" pull "$TMP_REMOTE" "$out_db" >/dev/null
  root_cmd "rm -f $(remote_quote "$TMP_REMOTE")"
}

show_targets() {
  local db="$1"
  local in_list="$2"
  "$SQLITE3" -header -column "$db" "
    SELECT _id,title,itemType,pageIndex,cellIndex,folderIndex,packageName,componentName
    FROM table_iteminfos
    WHERE packageName IN (${in_list})
    ORDER BY _id;
  "
  "$SQLITE3" -header -column "$db" "
    SELECT COUNT(*) AS target_items
    FROM table_iteminfos
    WHERE packageName IN (${in_list});
    SELECT COUNT(*) AS target_icons
    FROM table_icons
    WHERE owner IN (
      SELECT _id FROM table_iteminfos WHERE packageName IN (${in_list})
    );
  "
}

apply_local_cleanup() {
  local db="$1"
  local in_list="$2"
  "$SQLITE3" "$db" "
    PRAGMA foreign_keys=OFF;
    PRAGMA integrity_check;
    BEGIN IMMEDIATE;
    DELETE FROM table_icons
      WHERE owner IN (
        SELECT _id FROM table_iteminfos WHERE packageName IN (${in_list})
      );
    DELETE FROM table_iteminfos
      WHERE packageName IN (${in_list});
    COMMIT;
    PRAGMA integrity_check;
  " | tee "${db}.integrity.txt"
  if grep -v '^ok$' "${db}.integrity.txt" >/dev/null; then
    die "SQLite integrity check did not return ok"
  fi
}

push_launcher_db() {
  local clean_db="$1"
  adb -s "$SERIAL" push "$clean_db" "$TMP_REMOTE" >/dev/null
  root_cmd "
    set -e
    owner=\$(stat -c '%u:%g' $(remote_quote "$DB_REMOTE"))
    context=\$(stat -c '%C' $(remote_quote "$DB_REMOTE"))
    am force-stop com.smartisanos.launcher || true
    cp $(remote_quote "$DB_REMOTE") $(remote_quote "${DB_REMOTE}.before-v0.4-shortcut-clean")
    cp $(remote_quote "$TMP_REMOTE") $(remote_quote "$DB_REMOTE")
    chown \"\$owner\" $(remote_quote "$DB_REMOTE")
    chmod 660 $(remote_quote "$DB_REMOTE")
    rm -f $(remote_quote "$DB_JOURNAL_REMOTE") $(remote_quote "$DB_WAL_REMOTE") $(remote_quote "$DB_SHM_REMOTE")
    if command -v restorecon >/dev/null 2>&1; then
      restorecon $(remote_quote "$DB_REMOTE") || true
    else
      chcon \"\$context\" $(remote_quote "$DB_REMOTE") || true
    fi
    rm -f $(remote_quote "$TMP_REMOTE")
    am force-stop com.smartisanos.launcher || true
  "
}

mode="dry-run"
case "${1:-}" in
  ""|--dry-run)
    mode="dry-run"
    ;;
  --apply)
    mode="apply"
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

need_cmd adb
need_cmd "$SQLITE3"
require_device
mkdir -p "$INSPECT_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_db="${INSPECT_DIR}/launcher-before-v0.4-shortcut-clean-${timestamp}.db"
clean_db="${INSPECT_DIR}/launcher-after-v0.4-shortcut-clean-${timestamp}.db"
in_list="$(sql_in_list)"

pull_launcher_db "$backup_db"

echo "Backup DB: ${backup_db}"
echo
echo "Launcher rows selected for v0.4 shortcut cleanup:"
show_targets "$backup_db" "$in_list"

if [ "$mode" = "dry-run" ]; then
  echo
  echo "Dry run only. Re-run with --apply after v0.4 boots successfully."
  exit 0
fi

cp "$backup_db" "$clean_db"
apply_local_cleanup "$clean_db" "$in_list"
push_launcher_db "$clean_db"

echo
echo "Applied launcher shortcut cleanup."
echo "Clean DB copy: ${clean_db}"
