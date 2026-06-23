#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/Cellar/e2fsprogs/1.47.4/sbin/debugfs}"

BASE_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.1.img"
OUT_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.2-no-appstore.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.2-no-appstore.SHA256SUMS.txt"
REMOVED_DIR="/system/app/AppStoreSmartisan"
REMOVED_APK="${REMOVED_DIR}/AppStoreSmartisan.apk"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_file "$DEBUGFS"
need_file "$BASE_IMG"

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

if cp -c "$BASE_IMG" "$OUT_IMG" 2>/dev/null; then
  :
else
  cp "$BASE_IMG" "$OUT_IMG"
fi

"$DEBUGFS" -w -R "rm ${REMOVED_APK}" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rmdir ${REMOVED_DIR}" "$OUT_IMG" >/dev/null 2>&1 || true

if debugfs_path_exists "$OUT_IMG" "$REMOVED_APK"; then
  die "APK still exists after removal: ${REMOVED_APK}"
fi

if debugfs_path_exists "$OUT_IMG" "$REMOVED_DIR"; then
  die "directory still exists after removal: ${REMOVED_DIR}"
fi

{
  echo "system_image=${OUT_IMG}"
  echo "base_system_image=${BASE_IMG}"
  echo "removed=${REMOVED_DIR}"
  echo "package=com.smartisanos.appstore"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_IMG" "$BASE_IMG"
} > "$MANIFEST"

echo "Built: ${OUT_IMG}"
echo "Manifest: ${MANIFEST}"
