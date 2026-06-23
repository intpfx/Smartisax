#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"

BASE_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.2-no-appstore.img"
OUT_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.4-debloat.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.4-debloat.SHA256SUMS.txt"
VERIFY_DIR="${ROOT_DIR}/hard-rom/verify"

remove_entries=(
  "com.smartisanos.gamestore|/system/app/GameStoreSmartisan|16837893"
  "com.smartisanos.compass|/system/app/CompassSmartisan|1686103"
  "com.sohu.inputmethod.sogou.chuizi|/system/app/SmartisanSogouIME|25259434"
  "com.iflytek.inputmethod.smartisan|/system/app/SmartisanIFlyIME|52730812"
  "com.android.email|/system/app/EmailSmartisan|12466076"
  "com.smartisanos.handinhand|/system/app/HandInHand|39083662"
  "com.smartisanos.writer|/system/app/Write|17929709"
  "com.smartisanos.notes|/system/app/NotesSmartisan|15988596"
  "com.smartisanos.calculator|/system/app/CalculatorSmartisan|2403957"
  "com.smartisanos.recharge|/system/priv-app/RechargeSmartisan|3369364"
  "com.smartisanos.cloudgallery|/system/app/CloudGallerySmartisan|8800014"
  "com.smartisanos.recorder|/system/priv-app/SoundRecorderSmartisan|5874680"
  "com.smartisanos.launcher.themes|/system/app/LauncherSmartisanTheme|12702"
  "com.smartisanos.launcher.theme.aero|/system/app/LauncherSmartisanThemeAero|16967864"
  "com.smartisanos.launcher.theme.lightblue|/system/app/LauncherSmartisanThemeLightBlue|15587074"
  "com.smartisanos.launcher.theme.trans|/system/app/LauncherSmartisanThemeTrans|14895279"
  "com.smartisanos.launcher.theme.bamboo|/system/app/LauncherSmartisanThemeBamboo|22800666"
  "com.smartisanos.launcher.theme.glime|/system/app/LauncherSmartisanThemeGlime|14251449"
  "com.smartisanos.launcher.theme.leaf|/system/app/LauncherSmartisanThemeLeaf|17352464"
  "com.smartisanos.launcher.theme.raven|/system/app/LauncherSmartisanThemeRaven|22071224"
)

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_rm_tree() {
  local image="$1"
  local path="$2"

  if ! debugfs_path_exists "$image" "$path"; then
    return 0
  fi

  while IFS=$'\t' read -r mode name; do
    [ -n "${name:-}" ] || continue
    local child="${path}/${name}"
    if [[ "$mode" == 04* ]]; then
      debugfs_rm_tree "$image" "$child"
    else
      "$DEBUGFS" -w -R "rm ${child}" "$image" >/dev/null 2>&1 || true
    fi
  done < <("$DEBUGFS" -R "ls -p ${path}" "$image" 2>/dev/null | \
    awk -F/ '$0 ~ /^\// && $6 != "." && $6 != ".." { print $3 "\t" $6 }')

  "$DEBUGFS" -w -R "rmdir ${path}" "$image" >/dev/null 2>&1 || true
}

need_file "$DEBUGFS"
need_file "$E2FSCK"
need_file "$BASE_IMG"

mkdir -p "$VERIFY_DIR"

if cp -c "$BASE_IMG" "$OUT_IMG" 2>/dev/null; then
  :
else
  cp "$BASE_IMG" "$OUT_IMG"
fi

removed_count=0
already_absent_count=0
selected_apk_bytes=0

for entry in "${remove_entries[@]}"; do
  IFS='|' read -r package_name remove_path apk_bytes <<<"$entry"
  selected_apk_bytes=$((selected_apk_bytes + apk_bytes))
  if debugfs_path_exists "$OUT_IMG" "$remove_path"; then
    debugfs_rm_tree "$OUT_IMG" "$remove_path"
    removed_count=$((removed_count + 1))
  else
    already_absent_count=$((already_absent_count + 1))
  fi

  if debugfs_path_exists "$OUT_IMG" "$remove_path"; then
    die "path still exists after removal: ${remove_path}"
  fi
done

fsck_status=0
"$E2FSCK" -fy "$OUT_IMG" >/dev/null || fsck_status=$?
[ "$fsck_status" -le 1 ] || die "e2fsck repair failed with exit code ${fsck_status}"
"$E2FSCK" -fn "$OUT_IMG" >/dev/null

{
  echo "system_image=${OUT_IMG}"
  echo "base_system_image=${BASE_IMG}"
  echo "variant=otatrust-v0.4-debloat"
  echo "removed_count=${removed_count}"
  echo "already_absent_count=${already_absent_count}"
  echo "selected_apk_bytes=${selected_apk_bytes}"
  echo "launcher_cleanup_script=tools/r2-clean-v0.4-launcher-shortcuts.sh"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "removed_packages:"
  for entry in "${remove_entries[@]}"; do
    IFS='|' read -r package_name remove_path apk_bytes <<<"$entry"
    echo "  ${package_name} ${remove_path} apk_bytes=${apk_bytes}"
  done
  echo
  shasum -a 256 "$OUT_IMG" "$BASE_IMG"
} > "$MANIFEST"

echo "Built: ${OUT_IMG}"
echo "Manifest: ${MANIFEST}"
