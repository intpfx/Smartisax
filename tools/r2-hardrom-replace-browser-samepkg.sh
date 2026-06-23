#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"

BASE_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.2-no-appstore.img"
OUT_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.3-browser-samepkg.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.3-browser-samepkg.SHA256SUMS.txt"
REPLACEMENT_APK="${ROOT_DIR}/hard-rom/build/apk/cromite-as-com.android.browser.apk"
REPLACEMENT_MANIFEST="${ROOT_DIR}/hard-rom/build/apk/cromite-as-com.android.browser.SHA256SUMS.txt"
VERIFY_DIR="${ROOT_DIR}/hard-rom/verify"

BROWSER_DIR="/system/app/BrowserChrome"
BROWSER_APK="${BROWSER_DIR}/BrowserChrome.apk"

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
need_file "$REPLACEMENT_APK"
need_file "$REPLACEMENT_MANIFEST"

EXPECTED_REPLACEMENT_SHA256="$(awk -v apk="$REPLACEMENT_APK" '$2 == apk {print $1}' "$REPLACEMENT_MANIFEST")"
[ -n "$EXPECTED_REPLACEMENT_SHA256" ] || die "missing replacement apk hash in: ${REPLACEMENT_MANIFEST}"
actual_replacement_sha256="$(shasum -a 256 "$REPLACEMENT_APK" | awk '{print $1}')"
[ "$actual_replacement_sha256" = "$EXPECTED_REPLACEMENT_SHA256" ] || \
  die "replacement apk sha256 mismatch: ${actual_replacement_sha256}"

mkdir -p "$VERIFY_DIR"

if cp -c "$BASE_IMG" "$OUT_IMG" 2>/dev/null; then
  :
else
  cp "$BASE_IMG" "$OUT_IMG"
fi

"$DEBUGFS" -w -R "rm ${BROWSER_DIR}/oat/arm64/BrowserChrome.odex" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rm ${BROWSER_DIR}/oat/arm64/BrowserChrome.vdex" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rmdir ${BROWSER_DIR}/oat/arm64" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rmdir ${BROWSER_DIR}/oat" "$OUT_IMG" >/dev/null 2>&1 || true
"$DEBUGFS" -w -R "rm ${BROWSER_APK}" "$OUT_IMG" >/dev/null 2>&1 || true

if ! debugfs_path_exists "$OUT_IMG" "$BROWSER_DIR"; then
  "$DEBUGFS" -w -R "mkdir ${BROWSER_DIR}" "$OUT_IMG" >/dev/null
  set_system_file_metadata "$OUT_IMG" "$BROWSER_DIR"
fi

"$DEBUGFS" -w -R "write ${REPLACEMENT_APK} ${BROWSER_APK}" "$OUT_IMG" >/dev/null
set_system_file_metadata "$OUT_IMG" "$BROWSER_APK"

if ! debugfs_path_exists "$OUT_IMG" "$BROWSER_APK"; then
  die "replacement browser apk missing after write: ${BROWSER_APK}"
fi

fsck_status=0
"$E2FSCK" -fy "$OUT_IMG" >/dev/null || fsck_status=$?
[ "$fsck_status" -le 1 ] || die "e2fsck repair failed with exit code ${fsck_status}"
"$E2FSCK" -fn "$OUT_IMG" >/dev/null

dumped_apk="${VERIFY_DIR}/system-otatrust-v0.3-browser-samepkg.apk"
"$DEBUGFS" -R "dump ${BROWSER_APK} ${dumped_apk}" "$OUT_IMG" >/dev/null
dumped_sha256="$(shasum -a 256 "$dumped_apk" | awk '{print $1}')"
[ "$dumped_sha256" = "$EXPECTED_REPLACEMENT_SHA256" ] || \
  die "dumped browser apk sha256 mismatch: ${dumped_sha256}"

{
  echo "system_image=${OUT_IMG}"
  echo "base_system_image=${BASE_IMG}"
  echo "replaced_path=${BROWSER_APK}"
  echo "package=com.android.browser"
  echo "replacement_source=${REPLACEMENT_APK}"
  echo "replacement_apk_sha256=${EXPECTED_REPLACEMENT_SHA256}"
  echo "browser_engine=Cromite 148.0.7778.168 repackaged as com.android.browser"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_IMG" "$BASE_IMG" "$REPLACEMENT_APK"
} > "$MANIFEST"

echo "Built: ${OUT_IMG}"
echo "Manifest: ${MANIFEST}"
