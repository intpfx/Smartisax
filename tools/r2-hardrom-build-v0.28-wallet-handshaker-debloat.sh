#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img}"
SOURCE_SHA256="${SOURCE_SHA256:-11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.28-wallet-handshaker-debloat}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
SYSTEM_IMG="${SYSTEM_IMG:-${OUT_DIR}/system-otatrust-v0.28-wallet-handshaker-debloat.img}"
OUT_SPARSE="${OUT_SPARSE:-${OUT_DIR}/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img}"
MANIFEST="${MANIFEST:-${OUT_DIR}/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.SHA256SUMS.txt}"

SYSTEM_SELABEL="u:object_r:system_file:s0"
SYSTEM_B_SIZE=3049058304
SYSTEM_B_START_SECTOR=10487744
SYSTEM_B_SIZE_SECTORS=5955192
SPARSE_VARIANT="otatrust-v0.28-wallet-handshaker-debloat-exact-current"

remove_entries=(
  "com.smartisanos.wallet|/system/priv-app/WalletSmartisan|17116000|Smartisan Wallet, NFC/payment/card/lockscreen wallet surfaces"
  "com.smartisanos.smartfolder.aoa|/system/app/HandShaker|7108011|Smartisan HandShaker AOA desktop assistant and PC-mode display helper"
)

hiddenapi_packages=(
  "com.smartisanos.wallet"
  "com.smartisanos.smartfolder.aoa"
)

retained_paths=(
  "/system/priv-app/MtpService"
  "/system/priv-app/MtpService/MtpService.apk"
  "/system/apex/com.android.mediaprovider"
  "/system/apex/com.android.mediaprovider/priv-app/MediaProvider/MediaProvider.apk"
  "/system/priv-app/MediaProviderLegacy"
  "/system/priv-app/MediaProviderLegacy/MediaProviderLegacy.apk"
)

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.28-wallet-handshaker-debloat.sh

Build v0.28 on top of the live-verified v0.27 sparse image. The candidate
hard-removes Wallet and HandShaker ROM packages from system_b:

  /system/priv-app/WalletSmartisan
  /system/app/HandShaker

It also removes their entries from hiddenapi-package-whitelist.xml and verifies
that core MTP/MediaProvider ROM paths are retained. The script does not flash,
reboot, erase misc, or change /data. The live device currently has an
updated-system /data/app copy of com.smartisanos.wallet, so final Wallet package
absence requires a separate user-confirmed /data cleanup after flashing v0.28.
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

debugfs_rm_tree() {
  local image="$1"
  local path="$2"

  if ! debugfs_path_exists "$image" "$path"; then
    return 1
  fi

  while IFS=$'\t' read -r mode name; do
    [ -n "${name:-}" ] || continue
    local child="${path}/${name}"
    if [[ "$mode" == 04* ]]; then
      debugfs_rm_tree "$image" "$child" || true
    else
      "$DEBUGFS" -w -R "rm ${child}" "$image" >/dev/null 2>&1 || true
    fi
  done < <("$DEBUGFS" -R "ls -p ${path}" "$image" 2>/dev/null | \
    awk -F/ '$0 ~ /^\// && $6 != "." && $6 != ".." { print $3 "\t" $6 }')

  "$DEBUGFS" -w -R "rmdir ${path}" "$image" >/dev/null 2>&1 || true
  return 0
}

replace_file_in_image() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped"
  local dir
  local base
  local temp_path
  local held_path
  local src_hash
  local dumped_hash

  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  temp_path="${dir}/.${base}.smartisax-v028-tmp"
  held_path="${dir}/.${base}.smartisax-v028-stock-held"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination directory: ${dir}"
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
  echo "${dst}|${src}|${src_hash}|${dumped}|${held_path}"
}

filter_hiddenapi_whitelist() {
  local image="$1"
  local src_path="/system/etc/sysconfig/hiddenapi-package-whitelist.xml"
  local stock="${WORK_DIR}/hiddenapi-package-whitelist.stock.xml"
  local filtered="${WORK_DIR}/hiddenapi-package-whitelist.v0.28.xml"
  local pattern

  "$DEBUGFS" -R "dump ${src_path} ${stock}" "$image" >/dev/null 2>&1
  need_file "$stock"
  cp "$stock" "$filtered"
  for package_name in "${hiddenapi_packages[@]}"; do
    grep -v "package=\"${package_name}\"" "$filtered" > "${filtered}.tmp"
    mv "${filtered}.tmp" "$filtered"
  done
  pattern="$(IFS='|'; echo "${hiddenapi_packages[*]}")"
  if grep -Eq "$pattern" "$filtered"; then
    die "filtered hiddenapi whitelist still contains a removed package"
  fi
  replace_file_in_image "$image" "$filtered" "$src_path" "system-hiddenapi-whitelist"
}

fsck_image() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
  "$E2FSCK" -fn "$image" >/dev/null
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
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$SYSTEM_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.txt "${WORK_DIR}"/*.xml "${WORK_DIR}"/*.tmp

echo "Extracting system_b from v0.27 sparse super..."
"$SPARSE_TOOL" --source-sparse "$SOURCE_SPARSE" --extract-image "system_b=${SYSTEM_IMG}" >/dev/null
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

echo "Checking retained connectivity/media paths before removal..."
for retained_path in "${retained_paths[@]}"; do
  debugfs_path_exists "$SYSTEM_IMG" "$retained_path" || die "missing retained path before removal: ${retained_path}"
done

: > "${WORK_DIR}/removed-paths.tsv"
removed_count=0
already_absent_count=0
selected_apk_bytes=0

echo "Removing Wallet and HandShaker package directories..."
for entry in "${remove_entries[@]}"; do
  IFS='|' read -r package_name remove_path apk_bytes note <<<"$entry"
  selected_apk_bytes=$((selected_apk_bytes + apk_bytes))
  if debugfs_rm_tree "$SYSTEM_IMG" "$remove_path"; then
    removed_count=$((removed_count + 1))
    printf '%s\t%s\tremoved\tapk_bytes=%s\t%s\n' "$package_name" "$remove_path" "$apk_bytes" "$note" >> "${WORK_DIR}/removed-paths.tsv"
  else
    already_absent_count=$((already_absent_count + 1))
    printf '%s\t%s\talready_absent\tapk_bytes=%s\t%s\n' "$package_name" "$remove_path" "$apk_bytes" "$note" >> "${WORK_DIR}/removed-paths.tsv"
  fi

  if debugfs_path_exists "$SYSTEM_IMG" "$remove_path"; then
    die "path still exists after removal: ${remove_path}"
  fi
done

echo "Removing Wallet and HandShaker entries from hiddenapi whitelist..."
: > "${WORK_DIR}/replacements.tsv"
filter_hiddenapi_whitelist "$SYSTEM_IMG" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified system_b..."
fsck_image "$SYSTEM_IMG"

for entry in "${remove_entries[@]}"; do
  IFS='|' read -r _package_name remove_path _apk_bytes _note <<<"$entry"
  if debugfs_path_exists "$SYSTEM_IMG" "$remove_path"; then
    die "path reappeared after fsck: ${remove_path}"
  fi
done

for retained_path in "${retained_paths[@]}"; do
  debugfs_path_exists "$SYSTEM_IMG" "$retained_path" || die "retained path missing after fsck: ${retained_path}"
done

hiddenapi_dump="${WORK_DIR}/hiddenapi-package-whitelist.postfsck.xml"
"$DEBUGFS" -R "dump /system/etc/sysconfig/hiddenapi-package-whitelist.xml ${hiddenapi_dump}" "$SYSTEM_IMG" >/dev/null 2>&1
for package_name in "${hiddenapi_packages[@]}"; do
  if grep -Fq "$package_name" "$hiddenapi_dump"; then
    die "post-fsck hiddenapi whitelist still contains ${package_name}"
  fi
done

echo "Patching system_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$SOURCE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "system_b=${SYSTEM_IMG}" \
  --variant "$SPARSE_VARIANT"

system_hash="$(sha256_one "$SYSTEM_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"
hiddenapi_hash="$(sha256_one "$hiddenapi_dump")"

{
  echo "variant=${SPARSE_VARIANT}"
  echo "purpose=Hard-remove Smartisan Wallet and HandShaker ROM packages on top of live-verified v0.27"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "data_cleanup_gate=updated-system /data/app com.smartisanos.wallet cleanup requires separate explicit user confirmation"
  echo "source_sparse_super=${SOURCE_SPARSE}"
  echo "source_sparse_super_sha256=${SOURCE_SHA256}"
  echo "patched_partitions=system_b"
  echo "retained_partitions_from_source=system_ext_b,product_b,vendor_b,odm_b"
  echo "retained_system_paths=${retained_paths[*]}"
  echo "system_image=${SYSTEM_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "removed_paths=${WORK_DIR}/removed-paths.tsv"
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "system_b_start_sector=${SYSTEM_B_START_SECTOR}"
  echo "system_b_size_sectors=${SYSTEM_B_SIZE_SECTORS}"
  echo "removed_count=${removed_count}"
  echo "already_absent_count=${already_absent_count}"
  echo "selected_apk_bytes=${selected_apk_bytes}"
  echo "system_b_sha256=${system_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "hiddenapi_postfsck_sha256=${hiddenapi_hash}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# removed_paths"
  cat "${WORK_DIR}/removed-paths.tsv"
  echo
  echo "# replacements"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$SOURCE_SPARSE" "$hiddenapi_dump"
} > "$MANIFEST"

cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
