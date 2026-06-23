#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SAMESIZE_TOOL="${SAMESIZE_TOOL:-${ROOT_DIR}/tools/r2-apk-same-size-pad.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
APK_BUILDER="${APK_BUILDER:-${ROOT_DIR}/tools/r2-build-native-darkmode-tile-apks.sh}"
APK_VERIFIER="${APK_VERIFIER:-${ROOT_DIR}/tools/r2-verify-v0.11-native-darkmode-tile-apks.sh}"

SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img}"
SOURCE_SHA256="d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.11-native-darkmode}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.11-native-darkmode"

SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.11-native-darkmode.img"
SYSTEM_EXT_IMG="${OUT_DIR}/system_ext-otatrust-v0.11-native-darkmode.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.11-native-darkmode-exact-current.SHA256SUMS.txt"

STOCK_SETTINGS_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
STOCK_SYSTEMUI_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
SETTINGS_APK="${APK_OUT_DIR}/SettingsSmartisan-darkmode-ui-widget.apk"
SYSTEMUI_APK="${APK_OUT_DIR}/SmartisanSystemUI-darkmode-tile.apk"
SYSTEMUI_SAMESIZE_APK="${APK_OUT_DIR}/SmartisanSystemUI-darkmode-tile-samesize.apk"
SYSTEMUI_SAMESIZE_REPORT="${INSPECT_DIR}/systemui-darkmode-samesize-report.json"
SYSTEMUI_SAMESIZE_SIG_REPORT="${APK_OUT_DIR}/SmartisanSystemUI-darkmode-tile-samesize.signature.txt"

SETTINGS_IMAGE_PATH="/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
SYSTEMUI_IMAGE_PATH="/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
SYSTEM_SELABEL="u:object_r:system_file:s0"

SYSTEM_B_SIZE=3049058304
SYSTEM_EXT_B_SIZE=296116224
SYSTEM_B_START_SECTOR=10487744
SYSTEM_B_SIZE_SECTORS=5955192
SYSTEM_EXT_B_START_SECTOR=16443328
SYSTEM_EXT_B_SIZE_SECTORS=578352

REBUILD_APKS="${REBUILD_APKS:-1}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.11-native-darkmode.sh

Build the first combined native dark-mode behavior ROM image on the
live-verified v0.24 line. The candidate:

  - replaces SettingsSmartisan.apk in system_b with the v0.11 dark-mode UI and
    quick-widget editor patch using the shared_blocks-safe held-stock-inode path
  - replaces SmartisanSystemUI.apk in system_ext_b with a same-size v0.11
    native toggleDarkMode tile APK using an owner-audited same-path rm/write
    path on the system_ext image

This script does not flash, reboot, erase misc, or change /data. Flashing the
generated sparse image still requires explicit user confirmation.

Environment:
  SOURCE_SPARSE=<path>  source sparse super; defaults to live-verified v0.24
  REBUILD_APKS=0        reuse existing v0.11 APK outputs
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

replace_file_in_image() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped.apk"
  local dir
  local base
  local temp_path
  local held_path
  local src_hash
  local dumped_hash

  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  temp_path="${dir}/.${base}.smartisax-v011-tmp"
  held_path="${dir}/.${base}.smartisax-v011-stock-held"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination directory: ${dst}"
  debugfs_path_exists "$image" "$dst" || die "missing stock destination file: ${dst}"
  if debugfs_path_exists "$image" "$temp_path" || debugfs_path_exists "$image" "$held_path"; then
    die "temporary or held path already exists for ${dst}; refusing ambiguous replacement"
  fi

  {
    echo "ln ${dst} ${held_path}"
    echo "write ${src} ${temp_path}"
    echo "set_inode_field ${temp_path} mode 0100644"
    echo "set_inode_field ${temp_path} uid 0"
    echo "set_inode_field ${temp_path} gid 0"
    echo "ea_set ${temp_path} security.selinux ${SYSTEM_SELABEL}"
    echo "unlink ${dst}"
    echo "ln ${temp_path} ${dst}"
    echo "unlink ${temp_path}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$dst" || die "missing replaced file: ${dst}"
  debugfs_path_exists "$image" "$held_path" || die "missing held stock file: ${held_path}"
  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1

  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "dumped APK zip test failed before fsck for ${dst}"

  echo "${dst}|${src}|${src_hash}|${dumped}|${held_path}"
}

fsck_image_repair() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
  "$E2FSCK" -fn "$image" >/dev/null
}

fsck_image_read_only() {
  local image="$1"
  local status=0
  "$E2FSCK" -fn "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "read-only e2fsck failed for ${image} with exit code ${status}"
}

audit_file_blocks_unique_owner() {
  local image="$1"
  local image_path="$2"
  local report="$3"

  python3 - "$DEBUGFS" "$image" "$image_path" "$report" <<'PY'
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

debugfs, image, image_path, report = sys.argv[1:]

def run(command: str) -> str:
    return subprocess.check_output(
        [debugfs, "-R", command, image],
        stderr=subprocess.STDOUT,
        text=True,
    )

stat = run(f"stat {image_path}")
inode_match = re.search(r"^Inode:\s+(\d+)", stat, re.M)
size_match = re.search(r"^\s*User:.*\s+Size:\s+(\d+)$", stat, re.M)
if not inode_match or not size_match:
    raise SystemExit("failed to parse inode or size")
inode = int(inode_match.group(1))
inode_size = int(size_match.group(1))

logical_to_physical = []
for match in re.finditer(r"\((\d+)(?:-(\d+))?\):(\d+)(?:-(\d+))?", stat):
    logical_start = int(match.group(1))
    logical_end = int(match.group(2) or match.group(1))
    physical_start = int(match.group(3))
    physical_end = int(match.group(4) or match.group(3))
    if logical_end - logical_start != physical_end - physical_start:
        raise SystemExit(f"extent length mismatch: {match.group(0)}")
    logical_to_physical.extend(zip(range(logical_start, logical_end + 1), range(physical_start, physical_end + 1)))

if not logical_to_physical:
    raise SystemExit("no extents found")

physical_blocks = sorted({physical for _logical, physical in logical_to_physical})
physical_to_logical: dict[int, list[int]] = defaultdict(list)
for logical, physical in logical_to_physical:
    physical_to_logical[physical].append(logical)

missing = []
unexpected = []
for start in range(0, len(physical_blocks), 100):
    chunk = physical_blocks[start : start + 100]
    output = run("icheck " + " ".join(str(item) for item in chunk))
    seen = {}
    for line in output.splitlines():
        parsed = re.match(r"^(\d+)\s+(.+)$", line.strip())
        if not parsed or parsed.group(1) == "Block":
            continue
        seen[int(parsed.group(1))] = [int(item) for item in re.findall(r"\d+", parsed.group(2))]
    for block in chunk:
        owners = seen.get(block)
        if owners is None:
            missing.append(block)
        elif owners != [inode]:
            unexpected.append({"block": block, "owners": owners})

aliases = {
    str(physical): logicals
    for physical, logicals in sorted(physical_to_logical.items())
    if len(logicals) > 1
}
result = {
    "image": image,
    "path": image_path,
    "inode": inode,
    "inode_size": inode_size,
    "logical_block_refs": len(logical_to_physical),
    "unique_physical_blocks": len(physical_blocks),
    "aliased_physical_blocks": len(aliases),
    "aliased_physical_block_logicals": aliases,
    "missing_owner_rows": missing,
    "unexpected_owner_rows": unexpected,
    "all_unique_physical_blocks_owned_only_by_inode": not missing and not unexpected,
}
Path(report).parent.mkdir(parents=True, exist_ok=True)
Path(report).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
if missing or unexpected:
    raise SystemExit("target blocks are not owned only by the target inode")
print(json.dumps(result, indent=2, ensure_ascii=False))
PY
}

dump_and_compare() {
  local image="$1"
  local image_path="$2"
  local expected="$3"
  local out="$4"
  "$DEBUGFS" -R "dump ${image_path} ${out}" "$image" >/dev/null 2>&1
  need_file "$out"
  [ "$(sha256_one "$out")" = "$(sha256_one "$expected")" ] \
    || die "dumped hash mismatch for ${image_path}"
  unzip -t "$out" >/dev/null
}

replace_file_by_rm_write_in_image() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped.apk"
  local dumped_postfsck="${WORK_DIR}/${tag}-postfsck-dumped.apk"

  need_file "$src"
  debugfs_path_exists "$image" "$(dirname "$dst")" || die "missing destination directory: ${dst}"
  debugfs_path_exists "$image" "$dst" || die "missing destination file: ${dst}"

  {
    echo "rm ${dst}"
    echo "write ${src} ${dst}"
    echo "set_inode_field ${dst} mode 0100644"
    echo "set_inode_field ${dst} uid 0"
    echo "set_inode_field ${dst} gid 0"
    echo "ea_set ${dst} security.selinux ${SYSTEM_SELABEL}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$dst" || die "missing rewritten file: ${dst}"
  dump_and_compare "$image" "$dst" "$src" "$dumped"
  fsck_image_repair "$image"
  dump_and_compare "$image" "$dst" "$src" "$dumped_postfsck"

  echo "${dst}|${src}|$(sha256_one "$src")|${dumped_postfsck}|rm-write-owner-audited"
}

verify_systemui_samesize_apk() {
  need_file "$SYSTEMUI_APK"
  need_file "$SYSTEMUI_SAMESIZE_APK"
  [ "$(size_bytes "$SYSTEMUI_SAMESIZE_APK")" -eq "$(size_bytes "$STOCK_SYSTEMUI_APK")" ] \
    || die "same-size SystemUI APK does not match stock byte size"
  unzip -t "$SYSTEMUI_SAMESIZE_APK" >/dev/null

  python3 - "$SYSTEMUI_APK" "$SYSTEMUI_SAMESIZE_APK" <<'PY'
import hashlib
import sys
import zipfile

patched, samesize = sys.argv[1:]
with zipfile.ZipFile(patched) as zp, zipfile.ZipFile(samesize) as zs:
    patched_names = [i.filename for i in zp.infolist()]
    samesize_names = [i.filename for i in zs.infolist()]
    if patched_names != samesize_names:
        raise SystemExit("zip entry order differs from patched APK")
    for name in patched_names:
        hp = hashlib.sha256(zp.read(name)).hexdigest()
        hs = hashlib.sha256(zs.read(name)).hexdigest()
        if hp != hs:
            raise SystemExit(f"zip member content mismatch: {name}")
    info = zs.getinfo("classes10.dex")
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit("classes10.dex is not STORED in same-size APK")
    if len(zs.comment) > 65535:
        raise SystemExit("ZIP comment exceeds EOCD limit")
print("systemui_samesize_member_equivalence=ok")
PY

  "$SIGCHECK" "$SYSTEMUI_SAMESIZE_APK" > "$SYSTEMUI_SAMESIZE_SIG_REPORT"
  grep -q '^keytool_status=1$' "$SYSTEMUI_SAMESIZE_SIG_REPORT" \
    || die "same-size SystemUI signature report has unexpected keytool status"
  grep -q 'SHA-256 digest error for classes10.dex' "$SYSTEMUI_SAMESIZE_SIG_REPORT" \
    || die "same-size SystemUI signature report missing classes10.dex digest boundary"
}

case "${1:-}" in
  "")
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

need_file "$SOURCE_SPARSE"
need_file "$STOCK_SETTINGS_APK"
need_file "$STOCK_SYSTEMUI_APK"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
need_executable "$SAMESIZE_TOOL"
need_executable "$SIGCHECK"
need_executable "$APK_BUILDER"
need_executable "$APK_VERIFIER"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_IMG" "$SYSTEM_EXT_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.json "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*.debugfs

if [ "$REBUILD_APKS" = "1" ]; then
  echo "Building v0.11 native dark-mode APK candidates..."
  "$APK_BUILDER" >/dev/null
fi

need_file "$SETTINGS_APK"
need_file "$SYSTEMUI_APK"

echo "Verifying v0.11 APK semantics..."
"$APK_VERIFIER" >/dev/null

echo "Building same-size SystemUI behavior APK..."
"$SAMESIZE_TOOL" \
  --stock "$STOCK_SYSTEMUI_APK" \
  --patched "$SYSTEMUI_APK" \
  --out "$SYSTEMUI_SAMESIZE_APK" \
  --store-entry classes10.dex \
  --report "$SYSTEMUI_SAMESIZE_REPORT" >/dev/null
verify_systemui_samesize_apk

echo "Extracting system_b and system_ext_b from v0.24 sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$SOURCE_SPARSE" \
  --extract-image "system_b=${SYSTEM_IMG}" \
  --extract-image "system_ext_b=${SYSTEM_EXT_IMG}" >/dev/null
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"
[ "$(size_bytes "$SYSTEM_EXT_IMG")" -eq "$SYSTEM_EXT_B_SIZE" ] || die "unexpected system_ext_b size"

echo "Replacing SettingsSmartisan in system_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$SETTINGS_APK" "$SETTINGS_IMAGE_PATH" \
  "settingssmartisan-darkmode-widget" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified system_b..."
fsck_image_repair "$SYSTEM_IMG"
dump_and_compare "$SYSTEM_IMG" "$SETTINGS_IMAGE_PATH" "$SETTINGS_APK" \
  "${WORK_DIR}/SettingsSmartisan-postfsck.apk"

echo "Auditing SmartisanSystemUI block ownership before rm/write replacement..."
audit_file_blocks_unique_owner "$SYSTEM_EXT_IMG" "$SYSTEMUI_IMAGE_PATH" \
  "${WORK_DIR}/systemui-block-owner-audit.json" >/dev/null

echo "Replacing SmartisanSystemUI in system_ext_b by owner-audited rm/write..."
replace_file_by_rm_write_in_image "$SYSTEM_EXT_IMG" "$SYSTEMUI_SAMESIZE_APK" \
  "$SYSTEMUI_IMAGE_PATH" "systemui-darkmode-samesize" >> "${WORK_DIR}/replacements.tsv"

echo "Patching system_b and system_ext_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$SOURCE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "system_b=${SYSTEM_IMG}" \
  --image "system_ext_b=${SYSTEM_EXT_IMG}" \
  --variant "otatrust-v0.11-native-darkmode-exact-current"

system_hash="$(sha256_one "$SYSTEM_IMG")"
system_ext_hash="$(sha256_one "$SYSTEM_EXT_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"
settings_hash="$(sha256_one "$SETTINGS_APK")"
systemui_hash="$(sha256_one "$SYSTEMUI_APK")"
systemui_samesize_hash="$(sha256_one "$SYSTEMUI_SAMESIZE_APK")"

{
  echo "variant=otatrust-v0.11-native-darkmode-exact-current"
  echo "purpose=Combined native dark-mode SettingsSmartisan UI/editor patch and SmartisanSystemUI toggleDarkMode tile patch"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${SOURCE_SPARSE}"
  echo "source_sparse_super_sha256=${SOURCE_SHA256}"
  echo "patched_partitions=system_b,system_ext_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "system_ext_image=${SYSTEM_EXT_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "systemui_block_owner_audit=${WORK_DIR}/systemui-block-owner-audit.json"
  echo "systemui_samesize_report=${SYSTEMUI_SAMESIZE_REPORT}"
  echo "systemui_samesize_signature_report=${SYSTEMUI_SAMESIZE_SIG_REPORT}"
  echo "system_b_start_sector=${SYSTEM_B_START_SECTOR}"
  echo "system_b_size_sectors=${SYSTEM_B_SIZE_SECTORS}"
  echo "system_ext_b_start_sector=${SYSTEM_EXT_B_START_SECTOR}"
  echo "system_ext_b_size_sectors=${SYSTEM_EXT_B_SIZE_SECTORS}"
  echo "system_b_sha256=${system_hash}"
  echo "system_ext_b_sha256=${system_ext_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "settings_darkmode_apk=${SETTINGS_APK}"
  echo "settings_darkmode_sha256=${settings_hash}"
  echo "systemui_darkmode_apk=${SYSTEMUI_APK}"
  echo "systemui_darkmode_sha256=${systemui_hash}"
  echo "systemui_darkmode_samesize_apk=${SYSTEMUI_SAMESIZE_APK}"
  echo "systemui_darkmode_samesize_sha256=${systemui_samesize_hash}"
  echo "rebuilt_apks=${REBUILD_APKS}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$SYSTEM_EXT_IMG" "$SOURCE_SPARSE" \
    "$SETTINGS_APK" "$SYSTEMUI_APK" "$SYSTEMUI_SAMESIZE_APK"
} > "$MANIFEST"

cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "System_ext image: ${SYSTEM_EXT_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
