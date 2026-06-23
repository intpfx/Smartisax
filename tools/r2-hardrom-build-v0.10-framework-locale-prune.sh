#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
IMG2SIMG="${IMG2SIMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/img2simg}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"

FRAMEWORK_RES_BUILDER="${FRAMEWORK_RES_BUILDER:-${ROOT_DIR}/tools/r2-build-framework-res-locale-probe.sh}"
SMARTISAN_RES_BUILDER="${SMARTISAN_RES_BUILDER:-${ROOT_DIR}/tools/r2-build-smartisanos-framework-res-locale-probe.sh}"
APK_LOCALE_PRUNER="${APK_LOCALE_PRUNER:-${ROOT_DIR}/tools/r2-build-apk-locale-prune.sh}"

BASE_SPARSE="${BASE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img}"
RAW_ROM="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.10-framework-locale-prune"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
APK_OUT_DIR="${OUT_DIR}/apk"
RAW_SUPER="${WORK_DIR}/super-otatrust-v0.10-framework-locale-prune-exact-current.img"
SYSTEM_IMG="${OUT_DIR}/system-otatrust-v0.10-framework-locale-prune.img"
PRODUCT_IMG="${OUT_DIR}/product-otatrust-v0.10-framework-locale-prune.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-v0.10-framework-locale-prune-exact-current.SHA256SUMS.txt"

FW_RES_APK="${APK_OUT_DIR}/framework-res-locale-prune-en-zh.apk"
FW_RES_SIG="${APK_OUT_DIR}/framework-res-locale-prune-en-zh.signature.txt"
FW_SMARTISAN_APK="${APK_OUT_DIR}/framework-smartisanos-res-locale-prune-en-zh.apk"
FW_SMARTISAN_SIG="${APK_OUT_DIR}/framework-smartisanos-res-locale-prune-en-zh.signature.txt"

STOCK_FW_RES="${RAW_ROM}/system/system/framework/framework-res.apk"
STOCK_FW_SMARTISAN="${RAW_ROM}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

KEEP_RAW="${KEEP_RAW:-0}"
REBUILD_APKS="${REBUILD_APKS:-1}"

# Current v0.4 super slot 1 maps these B-slot partitions.
SYSTEM_B_SKIP_4096=1310968
SYSTEM_B_COUNT_4096=744399
SYSTEM_B_SIZE=3049058304
PRODUCT_B_SKIP_4096=2127736
PRODUCT_B_COUNT_4096=41775
PRODUCT_B_SIZE=171110400

SYSTEM_SELABEL="u:object_r:system_file:s0"
PRODUCT_OVERLAY_SELABEL="u:object_r:vendor_overlay_file:s0"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.10-framework-locale-prune.sh

Build an offline v0.10 exact-current super candidate from the stable v0.4
baseline. This candidate hard-prunes framework-level Japanese/Korean locale
resources by replacing:

  system_b:
    /system/framework/framework-res.apk
    /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk

  product_b:
    /overlay/DisplayCutoutEmulation*/DisplayCutoutEmulation*Overlay.apk

The candidate changes resources.arsc only in those APK shells. It is not
flash-authorized by this script. framework-res and static overlays are early
boot resources, so flashing requires explicit user confirmation and rollback
readiness.

Environment:
  REBUILD_APKS=0  reuse existing pruned APKs instead of rebuilding them first
  KEEP_RAW=1      keep the expanded raw super image in hard-rom/work
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

debugfs_rm_file_if_exists() {
  local image="$1"
  local path="$2"
  if debugfs_path_exists "$image" "$path"; then
    "$DEBUGFS" -w -R "rm ${path}" "$image" >/dev/null 2>&1 || true
  fi
}

verify_resource_sig_boundary() {
  local report="$1"
  need_file "$report"
  grep -q '^keytool_status=1$' "$report" \
    || die "unexpected keytool boundary; review ${report}"
  grep -q 'SHA-256 digest error for resources.arsc' "$report" \
    || die "signature report does not show expected resources.arsc digest boundary: ${report}"
}

build_product_overlay_apk() {
  local name="$1"
  local stock="${RAW_ROM}/product/overlay/DisplayCutoutEmulation${name}/DisplayCutoutEmulation${name}Overlay.apk"
  local out="${APK_OUT_DIR}/DisplayCutoutEmulation${name}Overlay-locale-prune-en-zh.apk"
  need_file "$stock"
  "$APK_LOCALE_PRUNER" \
    --apk "$stock" \
    --label "product-DisplayCutoutEmulation${name}" \
    --out "$out" >/dev/null
}

ensure_pruned_apks() {
  if [ "$REBUILD_APKS" = "1" ]; then
    echo "Building framework-res locale-prune APK..."
    "$FRAMEWORK_RES_BUILDER" --mode locale-prune --out "$FW_RES_APK" >/dev/null

    echo "Building framework-smartisanos-res locale-prune APK..."
    "$SMARTISAN_RES_BUILDER" --out "$FW_SMARTISAN_APK" >/dev/null

    echo "Building product DisplayCutout overlay locale-prune APKs..."
    for name in Corner Double Hole Tall Waterfall; do
      build_product_overlay_apk "$name"
    done
  fi

  need_file "$FW_RES_APK"
  need_file "$FW_SMARTISAN_APK"
  verify_resource_sig_boundary "$FW_RES_SIG"
  verify_resource_sig_boundary "$FW_SMARTISAN_SIG"

  for name in Corner Double Hole Tall Waterfall; do
    local apk="${APK_OUT_DIR}/DisplayCutoutEmulation${name}Overlay-locale-prune-en-zh.apk"
    local sig="${apk%.apk}.signature.txt"
    need_file "$apk"
    verify_resource_sig_boundary "$sig"
  done
}

replace_file_in_image() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local selabel="$4"
  local tag="$5"
  local cmd_file="${WORK_DIR}/replace-${tag}.debugfs"
  local dumped="${WORK_DIR}/${tag}-dumped.apk"
  local dir
  local base
  local temp_path
  local held_path

  dir="$(dirname "$dst")"
  base="$(basename "$dst")"
  temp_path="${dir}/.${base}.smartisax-v010-tmp"
  held_path="${dir}/.${base}.smartisax-v010-stock-held"

  need_file "$src"
  debugfs_path_exists "$image" "$dir" || die "missing destination directory: ${dst}"
  debugfs_path_exists "$image" "$dst" || die "missing stock destination file: ${dst}"
  if debugfs_path_exists "$image" "$temp_path" || debugfs_path_exists "$image" "$held_path"; then
    die "temporary or held path already exists for ${dst}; refusing ambiguous replacement"
  fi

  {
    # Keep the stock inode linked so debugfs never frees shared ext4 blocks.
    echo "ln ${dst} ${held_path}"
    echo "write ${src} ${temp_path}"
    echo "set_inode_field ${temp_path} mode 0100644"
    echo "set_inode_field ${temp_path} uid 0"
    echo "set_inode_field ${temp_path} gid 0"
    echo "ea_set ${temp_path} security.selinux ${selabel}"
    echo "unlink ${dst}"
    echo "ln ${temp_path} ${dst}"
    echo "unlink ${temp_path}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$dst" || die "missing replaced file: ${dst}"
  debugfs_path_exists "$image" "$held_path" || die "missing held stock file: ${held_path}"
  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1

  local src_hash
  local dumped_hash
  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "dumped APK zip test failed before fsck for ${dst}"

  echo "${dst}|${src}|${src_hash}|${dumped}|${held_path}"
}

fsck_image() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
  "$E2FSCK" -fn "$image" >/dev/null
}

verify_file_in_image_after_fsck() {
  local image="$1"
  local src="$2"
  local dst="$3"
  local tag="$4"
  local dumped="${WORK_DIR}/${tag}-postfsck-dumped.apk"
  local src_hash
  local dumped_hash

  "$DEBUGFS" -R "dump ${dst} ${dumped}" "$image" >/dev/null 2>&1
  src_hash="$(sha256_one "$src")"
  dumped_hash="$(sha256_one "$dumped")"
  [ "$src_hash" = "$dumped_hash" ] || die "post-fsck dumped hash mismatch for ${dst}"
  unzip -t "$dumped" >/dev/null || die "post-fsck APK zip test failed for ${dst}"
}

case "${1:-}" in
  "" )
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
need_file "$STOCK_FW_RES"
need_file "$STOCK_FW_SMARTISAN"
need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$SIMG2IMG"
need_executable "$IMG2SIMG"
need_executable "$LPDUMP"
need_executable "$FRAMEWORK_RES_BUILDER"
need_executable "$SMARTISAN_RES_BUILDER"
need_executable "$APK_LOCALE_PRUNER"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$APK_OUT_DIR"
rm -f "$RAW_SUPER" "$SYSTEM_IMG" "$PRODUCT_IMG" "$OUT_SPARSE" "$MANIFEST" \
  "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" "${OUT_SPARSE}.lpdump.txt"
rm -f "${WORK_DIR}"/*-dumped.apk "${WORK_DIR}"/replace-*.debugfs "${WORK_DIR}/replacements.tsv"

ensure_pruned_apks

echo "Expanding v0.4 sparse super to raw..."
"$SIMG2IMG" "$BASE_SPARSE" "$RAW_SUPER"

echo "Extracting system_b..."
dd if="$RAW_SUPER" of="$SYSTEM_IMG" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" status=none
[ "$(size_bytes "$SYSTEM_IMG")" -eq "$SYSTEM_B_SIZE" ] || die "unexpected system_b size"

echo "Extracting product_b..."
dd if="$RAW_SUPER" of="$PRODUCT_IMG" bs=4096 skip="$PRODUCT_B_SKIP_4096" count="$PRODUCT_B_COUNT_4096" status=none
[ "$(size_bytes "$PRODUCT_IMG")" -eq "$PRODUCT_B_SIZE" ] || die "unexpected product_b size"

echo "Replacing framework resource APKs in system_b..."
: > "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$FW_RES_APK" \
  "/system/framework/framework-res.apk" "$SYSTEM_SELABEL" \
  "system-framework-res" >> "${WORK_DIR}/replacements.tsv"
replace_file_in_image "$SYSTEM_IMG" "$FW_SMARTISAN_APK" \
  "/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk" "$SYSTEM_SELABEL" \
  "system-framework-smartisanos-res" >> "${WORK_DIR}/replacements.tsv"

echo "Replacing DisplayCutout static overlays in product_b..."
for name in Corner Double Hole Tall Waterfall; do
  apk="${APK_OUT_DIR}/DisplayCutoutEmulation${name}Overlay-locale-prune-en-zh.apk"
  replace_file_in_image "$PRODUCT_IMG" "$apk" \
    "/overlay/DisplayCutoutEmulation${name}/DisplayCutoutEmulation${name}Overlay.apk" \
    "$PRODUCT_OVERLAY_SELABEL" \
    "product-displaycutout-${name}" >> "${WORK_DIR}/replacements.tsv"
done

echo "Checking modified ext4 images..."
fsck_image "$SYSTEM_IMG"
fsck_image "$PRODUCT_IMG"

echo "Verifying replaced APKs after fsck..."
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$FW_RES_APK" \
  "/system/framework/framework-res.apk" \
  "system-framework-res"
verify_file_in_image_after_fsck "$SYSTEM_IMG" "$FW_SMARTISAN_APK" \
  "/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk" \
  "system-framework-smartisanos-res"
for name in Corner Double Hole Tall Waterfall; do
  apk="${APK_OUT_DIR}/DisplayCutoutEmulation${name}Overlay-locale-prune-en-zh.apk"
  verify_file_in_image_after_fsck "$PRODUCT_IMG" "$apk" \
    "/overlay/DisplayCutoutEmulation${name}/DisplayCutoutEmulation${name}Overlay.apk" \
    "product-displaycutout-${name}"
done

echo "Patching system_b and product_b back into raw super..."
dd if="$SYSTEM_IMG" of="$RAW_SUPER" bs=4096 seek="$SYSTEM_B_SKIP_4096" conv=notrunc status=none
dd if="$PRODUCT_IMG" of="$RAW_SUPER" bs=4096 seek="$PRODUCT_B_SKIP_4096" conv=notrunc status=none

system_b_hash="$(dd if="$RAW_SUPER" bs=4096 skip="$SYSTEM_B_SKIP_4096" count="$SYSTEM_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
expected_system_hash="$(sha256_one "$SYSTEM_IMG")"
[ "$system_b_hash" = "$expected_system_hash" ] || die "patched system_b hash mismatch"

product_b_hash="$(dd if="$RAW_SUPER" bs=4096 skip="$PRODUCT_B_SKIP_4096" count="$PRODUCT_B_COUNT_4096" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
expected_product_hash="$(sha256_one "$PRODUCT_IMG")"
[ "$product_b_hash" = "$expected_product_hash" ] || die "patched product_b hash mismatch"

"$LPDUMP" -s 0 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot0.txt"
"$LPDUMP" -s 1 "$RAW_SUPER" > "${OUT_SPARSE}.lpdump-slot1.txt"
cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"

echo "Converting patched raw super to sparse..."
"$IMG2SIMG" "$RAW_SUPER" "$OUT_SPARSE"

if [ "$KEEP_RAW" != "1" ]; then
  rm -f "$RAW_SUPER"
fi

{
  echo "variant=otatrust-v0.10-framework-locale-prune-exact-current"
  echo "purpose=framework-level English/Chinese-only locale resource hard-prune candidate"
  echo "flash_gate=not authorized; RED early-boot framework resource candidate; explicit user confirmation required"
  echo "source_sparse_super=${BASE_SPARSE}"
  echo "patched_partitions=system_b,product_b"
  echo "system_image=${SYSTEM_IMG}"
  echo "product_image=${PRODUCT_IMG}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "replacements=${WORK_DIR}/replacements.tsv"
  echo "system_b_start_sector=10487744"
  echo "system_b_size_sectors=5955192"
  echo "system_b_sha256=${system_b_hash}"
  echo "product_b_start_sector=17021888"
  echo "product_b_size_sectors=334200"
  echo "product_b_sha256=${product_b_hash}"
  echo "keep_raw=${KEEP_RAW}"
  echo "rebuilt_apks=${REBUILD_APKS}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "# inserted_apks"
  cat "${WORK_DIR}/replacements.tsv"
  echo
  shasum -a 256 "$OUT_SPARSE" "$SYSTEM_IMG" "$PRODUCT_IMG" "$BASE_SPARSE" \
    "$FW_RES_APK" "$FW_SMARTISAN_APK" \
    "${APK_OUT_DIR}/DisplayCutoutEmulationCornerOverlay-locale-prune-en-zh.apk" \
    "${APK_OUT_DIR}/DisplayCutoutEmulationDoubleOverlay-locale-prune-en-zh.apk" \
    "${APK_OUT_DIR}/DisplayCutoutEmulationHoleOverlay-locale-prune-en-zh.apk" \
    "${APK_OUT_DIR}/DisplayCutoutEmulationTallOverlay-locale-prune-en-zh.apk" \
    "${APK_OUT_DIR}/DisplayCutoutEmulationWaterfallOverlay-locale-prune-en-zh.apk" \
    "$STOCK_FW_RES" "$STOCK_FW_SMARTISAN"
} > "$MANIFEST"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_IMG}"
echo "Product image: ${PRODUCT_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Metadata dump: ${OUT_SPARSE}.lpdump.txt"
echo "Flash gate: explicit user confirmation required; this is a RED framework resource candidate."
