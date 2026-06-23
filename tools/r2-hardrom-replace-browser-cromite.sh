#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"

BASE_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.2-no-appstore.img"
OUT_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.3-cromite-browser.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.3-cromite-browser.SHA256SUMS.txt"
CROMITE_APK="${ROOT_DIR}/updates/modern-browser/payload/cromite.apk"
VERIFY_DIR="${ROOT_DIR}/hard-rom/verify"

OLD_BROWSER_DIR="/system/app/BrowserChrome"
OLD_BROWSER_APK="${OLD_BROWSER_DIR}/BrowserChrome.apk"
NEW_BROWSER_DIR="/system/app/Cromite"
NEW_BROWSER_APK="${NEW_BROWSER_DIR}/Cromite.apk"
EXPECTED_CROMITE_SHA256="77af7db8f0a02e8d8cd2099d1f9b5c8266d6ae4cba06924bda5c73f980dc6894"

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

set_system_file_metadata() {
  local image="$1"
  local path="$2"
  "$DEBUGFS" -w -R "ea_set ${path} security.selinux u:object_r:system_file:s0" "$image" >/dev/null
  "$DEBUGFS" -w -R "set_inode_field ${path} ctime 0x495c0780" "$image" >/dev/null
  "$DEBUGFS" -w -R "set_inode_field ${path} atime 0x495c0780" "$image" >/dev/null
  "$DEBUGFS" -w -R "set_inode_field ${path} mtime 0x495c0780" "$image" >/dev/null
  "$DEBUGFS" -w -R "set_inode_field ${path} crtime 0x495c0780" "$image" >/dev/null
}

need_file "$DEBUGFS"
need_file "$E2FSCK"
need_file "$BASE_IMG"
need_file "$CROMITE_APK"

actual_cromite_sha256="$(shasum -a 256 "$CROMITE_APK" | awk '{print $1}')"
[ "$actual_cromite_sha256" = "$EXPECTED_CROMITE_SHA256" ] || \
  die "cromite apk sha256 mismatch: ${actual_cromite_sha256}"

mkdir -p "$VERIFY_DIR"

if cp -c "$BASE_IMG" "$OUT_IMG" 2>/dev/null; then
  :
else
  cp "$BASE_IMG" "$OUT_IMG"
fi

"$DEBUGFS" -w -R "rm ${OLD_BROWSER_DIR}/oat/arm64/BrowserChrome.odex" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rm ${OLD_BROWSER_DIR}/oat/arm64/BrowserChrome.vdex" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rmdir ${OLD_BROWSER_DIR}/oat/arm64" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rmdir ${OLD_BROWSER_DIR}/oat" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rm ${OLD_BROWSER_APK}" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rmdir ${OLD_BROWSER_DIR}" "$OUT_IMG" >/dev/null 2>&1 || true

if debugfs_path_exists "$OUT_IMG" "$OLD_BROWSER_DIR"; then
  die "old browser directory still exists after removal: ${OLD_BROWSER_DIR}"
fi

"$DEBUGFS" -w -R "mkdir ${NEW_BROWSER_DIR}" "$OUT_IMG" >/dev/null
"$DEBUGFS" -w -R "write ${CROMITE_APK} ${NEW_BROWSER_APK}" "$OUT_IMG" >/dev/null
set_system_file_metadata "$OUT_IMG" "$NEW_BROWSER_DIR"
set_system_file_metadata "$OUT_IMG" "$NEW_BROWSER_APK"

if ! debugfs_path_exists "$OUT_IMG" "$NEW_BROWSER_APK"; then
  die "cromite apk missing after write: ${NEW_BROWSER_APK}"
fi

fsck_status=0
"$E2FSCK" -fy "$OUT_IMG" >/dev/null || fsck_status=$?
[ "$fsck_status" -le 1 ] || die "e2fsck repair failed with exit code ${fsck_status}"
"$E2FSCK" -fn "$OUT_IMG" >/dev/null

dumped_apk="${VERIFY_DIR}/system-otatrust-v0.3-cromite-browser.apk"
"$DEBUGFS" -R "dump ${NEW_BROWSER_APK} ${dumped_apk}" "$OUT_IMG" >/dev/null
dumped_sha256="$(shasum -a 256 "$dumped_apk" | awk '{print $1}')"
[ "$dumped_sha256" = "$EXPECTED_CROMITE_SHA256" ] || \
  die "dumped cromite apk sha256 mismatch: ${dumped_sha256}"

{
  echo "system_image=${OUT_IMG}"
  echo "base_system_image=${BASE_IMG}"
  echo "removed=${OLD_BROWSER_DIR}"
  echo "added=${NEW_BROWSER_APK}"
  echo "removed_package=com.android.browser"
  echo "added_package=org.cromite.cromite"
  echo "cromite_apk_sha256=${EXPECTED_CROMITE_SHA256}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_IMG" "$BASE_IMG" "$CROMITE_APK"
} > "$MANIFEST"

echo "Built: ${OUT_IMG}"
echo "Manifest: ${MANIFEST}"
