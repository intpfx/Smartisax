#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
INPLACE_WRITER="${INPLACE_WRITER:-${ROOT_DIR}/tools/r2-ext4-inplace-file-write.py}"
APK_BATCH_VERIFIER="${APK_BATCH_VERIFIER:-${ROOT_DIR}/tools/r2-verify-apk-only-locale-prune-candidates.sh}"
POLICY="${POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/v0.17b-product-system_ext-apk-only-locale-prune}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
PRODUCT_IMG="${OUT_DIR}/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
SYSTEM_EXT_IMG="${OUT_DIR}/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.SHA256SUMS.txt"

SELABEL="u:object_r:system_file:s0"
PRODUCT_B_SIZE=171110400
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_START_SECTOR=17021888
PRODUCT_B_SIZE_SECTORS=334200
SYSTEM_EXT_B_START_SECTOR=16443328
SYSTEM_EXT_B_SIZE_SECTORS=578352

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.17b-product-system_ext-apk-only-locale-prune.sh

Build an offline v0.17b exact-current candidate from the stable v0.4 baseline.
It promotes the remaining APK-only English/Chinese resource-prune candidates:

  product_b:    /app/PhotoTable/PhotoTable.apk
  system_ext_b: /app/ConferenceDialer/ConferenceDialer.apk

PhotoTable uses the shared_blocks-safe held-stock-inode replacement pattern.
ConferenceDialer uses the exact-size in-place strategy because system_ext_b is
tight and the same-size APK has already been proven on the current reference
inode. The script never flashes, reboots, erases misc, or changes /data.
Flashing still requires explicit user confirmation.
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

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

zip_entry_hash() {
  local apk="$1"
  local entry="$2"
  unzip -p "$apk" "$entry" | shasum -a 256 | awk '{print $1}'
}

verify_same_size_confdialer_scope() {
  local stock="$1"
  local same_size="$2"
  [ "$(size_bytes "$stock")" -eq "$(size_bytes "$same_size")" ] \
    || die "ConferenceDialer same-size payload is not the stock APK size"
  unzip -t "$same_size" >/dev/null
  [ "$(zip_entry_hash "$stock" "AndroidManifest.xml")" = "$(zip_entry_hash "$same_size" "AndroidManifest.xml")" ] \
    || die "ConferenceDialer same-size AndroidManifest.xml changed"
  [ "$(zip_entry_hash "$stock" "classes.dex")" = "$(zip_entry_hash "$same_size" "classes.dex")" ] \
    || die "ConferenceDialer same-size classes.dex changed"
  "$POLICY" --keep-languages en,zh "$same_size" | grep -q "bad_locale_chunk_count=0" \
    || die "ConferenceDialer same-size locale policy failed"
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
  temp_path="${dir}/.${base}.smartisax-v017b-tmp"
  held_path="${dir}/.${base}.smartisax-v017b-stock-held"

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
    echo "ea_set ${temp_path} security.selinux ${SELABEL}"
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

  echo "${dst}|${src}|${src_hash}|${dumped}|${held_path}|held-inode"
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

dump_and_compare() {
  local image="$1"
  local path="$2"
  local expected="$3"
  local out="$4"
  "$DEBUGFS" -R "dump ${path} ${out}" "$image" >/dev/null 2>&1
  [ "$(sha256_one "$out")" = "$(sha256_one "$expected")" ] \
    || die "dumped hash mismatch for ${path}"
  unzip -t "$out" >/dev/null
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

need_file "$BASE_SPARSE"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SPARSE_TOOL"
need_executable "$INPLACE_WRITER"
need_executable "$APK_BATCH_VERIFIER"
need_executable "$POLICY"

PHOTO_TABLE_APK="${APK_OUT_DIR}/com.android.dreams.phototable-locale-prune-en-zh.apk"
CONFDIALER_APK="${APK_OUT_DIR}/com.qualcomm.qti.confdialer-locale-prune-en-zh.apk"
CONFDIALER_SAMESIZE_APK="${APK_OUT_DIR}/com.qualcomm.qti.confdialer-locale-prune-en-zh-samesize.apk"
STOCK_CONFDIALER_APK="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system_ext/app/ConferenceDialer/ConferenceDialer.apk"

need_file "$PHOTO_TABLE_APK"
need_file "$CONFDIALER_APK"
need_file "$CONFDIALER_SAMESIZE_APK"
need_file "$STOCK_CONFDIALER_APK"

echo "Verifying APK-only candidate batch before ROM promotion..."
"$APK_BATCH_VERIFIER" >/dev/null
verify_same_size_confdialer_scope "$STOCK_CONFDIALER_APK" "$CONFDIALER_SAMESIZE_APK"

mkdir -p "$WORK_DIR" "$OUT_DIR"
rm -f "$PRODUCT_IMG" "$SYSTEM_EXT_IMG" "$OUT_SPARSE" "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/*.json "${WORK_DIR}"/replace-*.debugfs "${WORK_DIR}/replacements.tsv"

echo "Extracting product_b and system_ext_b from v0.4 sparse super..."
"$SPARSE_TOOL" --source-sparse "$BASE_SPARSE" \
  --extract-image "product_b=${PRODUCT_IMG}" \
  --extract-image "system_ext_b=${SYSTEM_EXT_IMG}" >/dev/null
[ "$(size_bytes "$PRODUCT_IMG")" -eq "$PRODUCT_B_SIZE" ] || die "unexpected product_b size"
[ "$(size_bytes "$SYSTEM_EXT_IMG")" -eq "$SYSTEM_EXT_B_SIZE" ] || die "unexpected system_ext_b size"

echo "Replacing PhotoTable in product_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$PRODUCT_IMG" "$PHOTO_TABLE_APK" \
  "/app/PhotoTable/PhotoTable.apk" \
  "product-phototable" >> "${WORK_DIR}/replacements.tsv"

echo "Checking modified product_b image..."
fsck_image_repair "$PRODUCT_IMG"
dump_and_compare "$PRODUCT_IMG" "/app/PhotoTable/PhotoTable.apk" \
  "$PHOTO_TABLE_APK" "${WORK_DIR}/product-phototable-postfsck-dumped.apk"

echo "Writing same-size ConferenceDialer payload into system_ext_b..."
"$INPLACE_WRITER" \
  --image "$SYSTEM_EXT_IMG" \
  --path "/app/ConferenceDialer/ConferenceDialer.apk" \
  --payload "$CONFDIALER_SAMESIZE_APK" \
  --write \
  --report "${WORK_DIR}/system_ext-confdialer-inplace-write.json" >/dev/null
dump_and_compare "$SYSTEM_EXT_IMG" "/app/ConferenceDialer/ConferenceDialer.apk" \
  "$CONFDIALER_SAMESIZE_APK" "${WORK_DIR}/system_ext-confdialer-postwrite-dumped.apk"
fsck_image_read_only "$SYSTEM_EXT_IMG"
printf '%s|%s|%s|%s|%s|%s\n' \
  "/app/ConferenceDialer/ConferenceDialer.apk" \
  "$CONFDIALER_SAMESIZE_APK" \
  "$(sha256_one "$CONFDIALER_SAMESIZE_APK")" \
  "${WORK_DIR}/system_ext-confdialer-postwrite-dumped.apk" \
  "${WORK_DIR}/system_ext-confdialer-inplace-write.json" \
  "same-size-in-place" >> "${WORK_DIR}/replacements.tsv"

echo "Patching product_b and system_ext_b back into sparse super..."
"$SPARSE_TOOL" \
  --source-sparse "$BASE_SPARSE" \
  --out "$OUT_SPARSE" \
  --image "product_b=${PRODUCT_IMG}" \
  --image "system_ext_b=${SYSTEM_EXT_IMG}" \
  --variant "otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current"

product_b_hash="$(sha256_one "$PRODUCT_IMG")"
system_ext_b_hash="$(sha256_one "$SYSTEM_EXT_IMG")"
super_hash="$(sha256_one "$OUT_SPARSE")"

{
  echo "variant=otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current"
  echo "purpose=Promote product_b and system_ext_b APK-only English/Chinese resources.arsc hard-prune candidates into a flashable sparse super"
  echo "flash_gate=not authorized; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partitions=product_b,system_ext_b"
  echo "product_image=${PRODUCT_IMG}"
  echo "system_ext_image=${SYSTEM_EXT_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "product_b_start_sector=${PRODUCT_B_START_SECTOR}"
  echo "product_b_size_sectors=${PRODUCT_B_SIZE_SECTORS}"
  echo "system_ext_b_start_sector=${SYSTEM_EXT_B_START_SECTOR}"
  echo "system_ext_b_size_sectors=${SYSTEM_EXT_B_SIZE_SECTORS}"
  echo "product_b_sha256=${product_b_hash}"
  echo "system_ext_b_sha256=${system_ext_b_hash}"
  echo "sparse_super_sha256=${super_hash}"
  echo "confdialer_regular_apk=${CONFDIALER_APK}"
  echo "confdialer_regular_sha256=$(sha256_one "$CONFDIALER_APK")"
  echo "confdialer_samesize_apk=${CONFDIALER_SAMESIZE_APK}"
  echo "confdialer_samesize_sha256=$(sha256_one "$CONFDIALER_SAMESIZE_APK")"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$PRODUCT_IMG" "$SYSTEM_EXT_IMG" "$BASE_SPARSE" \
    "$PHOTO_TABLE_APK" \
    "$CONFDIALER_APK" \
    "$CONFDIALER_SAMESIZE_APK"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "Product image: ${PRODUCT_IMG}"
echo "System_ext image: ${SYSTEM_EXT_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: explicit user confirmation required."
