#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LPMAKE="${LPMAKE:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpmake}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"

VARIANT="${VARIANT:-v0.36-smartisax-shell-debloat}"
SOURCE_VARIANT="v0.35.2-webview-m150-clean-product-residue"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img}"
SOURCE_SPARSE_SHA256="977f753dee7b84adc7218f5f0f4a8fd7b4403e8e39b24c77da013c8c6b7ec2f5"
SOURCE_SYSTEM_B_IMG="${SOURCE_SYSTEM_B_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.35.1-webview-m150-browserchrome-deodex.img}"
SOURCE_SYSTEM_B_SHA256="fd906f64df8859d6da6ec3752849cb1813802a880a801a9c6f764400679ca795"
SOURCE_PRODUCT_B_IMG="${SOURCE_PRODUCT_B_IMG:-${ROOT_DIR}/hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img}"
SOURCE_PRODUCT_B_SHA256="21757366972626221c8a1cb2c4492a4edc812f037814c94bebe5e127abc23b57"
SOURCE_EXTRACT_DIR="${SOURCE_EXTRACT_DIR:-${ROOT_DIR}/hard-rom/work/v0.35.2-webview-m150-clean-product-residue/source-v0351-retained-slot1}"

SMARTISAX_APK="${SMARTISAX_APK:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell.apk}"
SMARTISAX_APK_PACKAGE="com.smartisax.browser"
SMARTISAX_DIR="/system/app/SmartisaxShell"
SMARTISAX_APK_PATH="/system/app/SmartisaxShell/SmartisaxShell.apk"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
FALLBACK_EXTRACT_DIR="${WORK_DIR}/source-v0352-retained-slot1"
SOURCE_RAW="${WORK_DIR}/source-v0352-super.raw.img"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
OUT_RAW_FOR_LPDUMP="${WORK_DIR}/candidate-${VARIANT}-super.raw-for-lpdump.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SUPER_SIZE=10737418240
METADATA_SIZE=65536
METADATA_SLOTS=3
GROUP_A_MAX=5364514816
GROUP_B_MAX=5364514816

SYSTEM_A_SIZE=3052314624
PRODUCT_A_SIZE=255815680
VENDOR_A_SIZE=941768704
ODM_A_SIZE=917504
SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SYSTEM_EXT_B_SIZE=296116224
PRODUCT_B_PARTITION_SIZE=171110400
VENDOR_B_SIZE=868663296
ODM_B_SIZE=1056768
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"
SYSTEM_SELABEL="u:object_r:system_file:s0"
PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a366ba8}"
PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-20 18:30:00 +0800; invalidates package_cache after Smartisax install and system_b package deletions}"

SYSTEM_WEBVIEW_APK="/system/app/webview/webview.apk"
BROWSERCHROME_APK="/system/app/BrowserChrome/BrowserChrome.apk"
BROWSERCHROME_OAT_DIR="/system/app/BrowserChrome/oat"
LAUNCHER_APK="/system/priv-app/LauncherSmartisanNew/LauncherSmartisanNew.apk"
PRINT_KEEP_PATHS=(
  "/system/app/BuiltInPrintService"
  "/system/app/PrintSpooler"
  "/system/app/PrintRecommendationService"
)
PROJECTION_KEEP_PATHS=(
  "/system/app/BostonScreenMirror"
  "/system/priv-app/BostonCastHalService"
  "/system/app/SmartisanWirelessCast"
)
DONOR_WEBVIEW_SHA256="2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"
STOCK_LAUNCHER_SHA256="f3d5af9cf17c56b93462a7d596ed1c7b246a93b32ebc129dbfe14296eaf7ddb6"

REMOVED_PATHS=(
  "/system/app/SMTBugreport"
  "/system/app/CrashReport"
  "/system/app/SlardarOsClient"
  "/system/app/SMPushService"
  "/system/app/UnionPushProxy"
  "/system/app/TrackerSmartisan"
  "/system/priv-app/TeaTracker"
  "/system/app/BasicDreams"
  "/system/app/HTMLViewer"
  "/system/app/LiveWallpapersPicker"
  "/system/app/WallpaperBackup"
  "/system/app/Exchange2"
  "/system/app/Traceur"
  "/system/app/EasterEgg"
  "/system/app/Protips"
  "/system/app/CtsShimPrebuilt"
  "/system/priv-app/CtsShimPrivPrebuilt"
  "/system/priv-app/SmartisanShareManual"
  "/system/app/SmartisanWallpapers"
)

REMOVED_PACKAGES=(
  "com.smartisanos.bug2go"
  "com.smartisan.crashreport"
  "com.bytedance.os.slardar"
  "com.smartisan.smpush"
  "com.smartisan.unionpush.proxy"
  "com.smartisanos.tracker"
  "com.smartisanos.teatracker"
  "com.android.dreams.basic"
  "com.android.htmlviewer"
  "com.android.wallpaper.livepicker"
  "com.android.wallpaperbackup"
  "com.android.exchange"
  "com.android.traceur"
  "com.android.egg"
  "com.android.protips"
  "com.android.cts.ctsshim"
  "com.android.cts.priv.ctsshim"
  "com.smartisanos.manual"
  "com.smartisanos.wallpapers"
)

CONFIG_FILTERS=(
  "/system/etc/sysconfig/hiddenapi-package-whitelist.xml"
  "/system/etc/sysconfig/qti_whitelist.xml"
  "/system/etc/sysconfig/preinstalled-packages-platform.xml"
  "/system/etc/sysconfig/preinstalled-packages-platform-full-base.xml"
  "/system/etc/permissions/platform.xml"
)

PURPOSE="First Smartisax system-app shell image on top of live-proven v0.35.2: installs com.smartisax.browser as a WebView-backed browser/Home candidate without replacing stock Launcher or com.android.browser, removes the user-selected no-projection print-preserving debloat set, and also removes SmartisanWallpapers as user-confirmed extra reserve."

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

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

check_size() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
}

copy_clone_or_plain() {
  local src="$1"
  local dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1"
  local src="$2"
  local dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
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
  temp_path="${dir}/.${base}.smartisax-v036-tmp"
  held_path="${dir}/.${base}.smartisax-v036-stock-held"

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
  echo "${dst}|${src}|${src_hash}|${held_path}"
}

set_dir_time() {
  local image="$1"
  local dir="$2"
  local tag="$3"
  local cmd_file="${WORK_DIR}/mtime-${tag}.debugfs"
  debugfs_path_exists "$image" "$dir" || die "missing directory: ${dir}"
  {
    echo "set_inode_field ${dir} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${dir} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  echo "${dir}|mtime_hex=${PACKAGE_DIR_MTIME_HEX}|${PACKAGE_DIR_MTIME_NOTE}"
}

install_smartisax_apk() {
  local image="$1"
  local cmd_file="${WORK_DIR}/install-smartisax.debugfs"
  debugfs_path_exists "$image" "/system/app" || die "missing /system/app"
  if debugfs_path_exists "$image" "$SMARTISAX_DIR"; then
    die "Smartisax destination already exists: ${SMARTISAX_DIR}"
  fi
  {
    echo "mkdir ${SMARTISAX_DIR}"
    echo "set_inode_field ${SMARTISAX_DIR} mode 040755"
    echo "set_inode_field ${SMARTISAX_DIR} uid 0"
    echo "set_inode_field ${SMARTISAX_DIR} gid 0"
    echo "ea_set ${SMARTISAX_DIR} security.selinux ${SYSTEM_SELABEL}"
    echo "write ${SMARTISAX_APK} ${SMARTISAX_APK_PATH}"
    echo "set_inode_field ${SMARTISAX_APK_PATH} mode 0100644"
    echo "set_inode_field ${SMARTISAX_APK_PATH} uid 0"
    echo "set_inode_field ${SMARTISAX_APK_PATH} gid 0"
    echo "ea_set ${SMARTISAX_APK_PATH} security.selinux ${SYSTEM_SELABEL}"
    echo "set_inode_field ${SMARTISAX_APK_PATH} ctime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${SMARTISAX_APK_PATH} atime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${SMARTISAX_APK_PATH} mtime ${PACKAGE_DIR_MTIME_HEX}"
    echo "set_inode_field ${SMARTISAX_APK_PATH} crtime ${PACKAGE_DIR_MTIME_HEX}"
  } > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  set_dir_time "$image" "$SMARTISAX_DIR" "smartisax-dir" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  debugfs_path_exists "$image" "$SMARTISAX_APK_PATH" || die "missing installed Smartisax APK"
}

filter_config_file() {
  local image="$1"
  local src_path="$2"
  local tag="$3"
  local stock="${WORK_DIR}/${tag}.stock.xml"
  local filtered="${WORK_DIR}/${tag}.v0.36.xml"
  local package_name

  "$DEBUGFS" -R "dump ${src_path} ${stock}" "$image" >/dev/null 2>&1
  need_file "$stock"
  cp "$stock" "$filtered"

  for package_name in "${REMOVED_PACKAGES[@]}"; do
    PACKAGE_NAME="$package_name" perl -0pi -e 'my $p=$ENV{PACKAGE_NAME}; s/\n[ \t]*<install-in-user-type package="\Q$p\E">.*?<\/install-in-user-type>//sg;' "$filtered"
    grep -v "package=\"${package_name}\"" "$filtered" > "${filtered}.tmp"
    mv "${filtered}.tmp" "$filtered"
  done

  if grep -E 'com\.smartisanos\.bug2go|com\.smartisan\.crashreport|com\.bytedance\.os\.slardar|com\.smartisan\.smpush|com\.smartisan\.unionpush\.proxy|com\.smartisanos\.tracker|com\.smartisanos\.teatracker|com\.android\.dreams\.basic|com\.android\.htmlviewer|com\.android\.wallpaper\.livepicker|com\.android\.wallpaperbackup|com\.android\.exchange|com\.android\.traceur|com\.android\.egg|com\.android\.protips|com\.android\.cts\.ctsshim|com\.android\.cts\.priv\.ctsshim|com\.smartisanos\.manual|com\.smartisanos\.wallpapers' "$filtered" >/dev/null; then
    die "filtered config still contains a removed package: ${src_path}"
  fi

  if cmp -s "$stock" "$filtered"; then
    echo "${src_path}|unchanged" >> "${WORK_DIR}/config-filtered.tsv"
  else
    replace_file_in_image "$image" "$filtered" "$src_path" "config-${tag}" >> "${WORK_DIR}/config-filtered.tsv"
  fi
}

fsck_rw() {
  local image="$1"
  local status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

verify_dumped_apk() {
  local image="$1"
  local src="$2"
  local expected="$3"
  local dst="$4"
  debugfs_dump "$image" "$src" "$dst"
  [ "$(sha256_one "$dst")" = "$expected" ] || die "dumped APK hash mismatch for ${src}"
  unzip -t "$dst" >/dev/null || die "dumped APK zip test failed for ${src}"
}

rebuild_system_footer() {
  local image="$1"
  PATH="$(dirname "$FEC"):${PATH}" python3 "$AVBTOOL" add_hashtree_footer \
    --image "$image" \
    --partition_size "$SYSTEM_B_PARTITION_SIZE" \
    --partition_name system \
    --hash_algorithm sha1 \
    --salt "$SYSTEM_B_SALT" \
    --block_size 4096 \
    --fec_num_roots 2 \
    --prop com.android.build.system.fingerprint:qti/aries/aries:11/RKQ1.201217.002/1658135499:user/dev-keys \
    --prop com.android.build.system.os_version:11 \
    --prop com.android.build.system.security_patch:2022-06-10 \
    --prop com.android.build.system.security_patch:2022-06-10
}

prepare_inputs() {
  local part
  local extract_dir="$SOURCE_EXTRACT_DIR"
  require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
  require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
  require_hash "$SOURCE_PRODUCT_B_IMG" "$SOURCE_PRODUCT_B_SHA256"
  if [ ! -f "${extract_dir}/system_a.img" ] || [ ! -f "${extract_dir}/system_ext_b.img" ]; then
    extract_dir="$FALLBACK_EXTRACT_DIR"
    echo "Retained partitions are missing; extracting selected slot-1 partitions from v0.35.2 sparse super..."
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    rm -f "$SOURCE_RAW"
    "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW"
    check_size "source raw super" "$SOURCE_RAW" "$SUPER_SIZE"
    "$LPUNPACK" --slot=1 \
      --partition=system_a \
      --partition=product_a \
      --partition=vendor_a \
      --partition=odm_a \
      --partition=system_ext_b \
      --partition=vendor_b \
      --partition=odm_b \
      "$SOURCE_RAW" "$extract_dir" >/dev/null
    rm -f "$SOURCE_RAW"
  fi
  SOURCE_EXTRACT_DIR="$extract_dir"
  for part in system_a product_a vendor_a odm_a system_ext_b vendor_b odm_b; do
    need_file "${SOURCE_EXTRACT_DIR}/${part}.img"
  done
  check_size system_a "${SOURCE_EXTRACT_DIR}/system_a.img" "$SYSTEM_A_SIZE"
  check_size product_a "${SOURCE_EXTRACT_DIR}/product_a.img" "$PRODUCT_A_SIZE"
  check_size vendor_a "${SOURCE_EXTRACT_DIR}/vendor_a.img" "$VENDOR_A_SIZE"
  check_size odm_a "${SOURCE_EXTRACT_DIR}/odm_a.img" "$ODM_A_SIZE"
  check_size system_ext_b "${SOURCE_EXTRACT_DIR}/system_ext_b.img" "$SYSTEM_EXT_B_SIZE"
  check_size vendor_b "${SOURCE_EXTRACT_DIR}/vendor_b.img" "$VENDOR_B_SIZE"
  check_size odm_b "${SOURCE_EXTRACT_DIR}/odm_b.img" "$ODM_B_SIZE"
}

dump_lpdump() {
  rm -f "$OUT_RAW_FOR_LPDUMP"
  "$SIMG2IMG" "$OUT_SPARSE" "$OUT_RAW_FOR_LPDUMP"
  check_size "candidate raw super for lpdump" "$OUT_RAW_FOR_LPDUMP" "$SUPER_SIZE"
  for slot in 0 1; do
    "$LPDUMP" -s "$slot" "$OUT_RAW_FOR_LPDUMP" > "${OUT_SPARSE}.lpdump-slot${slot}.txt"
  done
  cat "${OUT_SPARSE}.lpdump-slot0.txt" "${OUT_SPARSE}.lpdump-slot1.txt" > "${OUT_SPARSE}.lpdump.txt"
  rm -f "$OUT_RAW_FOR_LPDUMP"
}

case "${1:-}" in
  "")
    ;;
  -h|--help|help)
    sed -n '1,90p' "$0"
    exit 0
    ;;
  *)
    echo "Usage: $0" >&2
    exit 2
    ;;
esac

need_executable "$LPMAKE"
need_executable "$LPDUMP"
need_executable "$LPUNPACK"
need_executable "$SIMG2IMG"
need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_file "$AVBTOOL"
need_file "$SMARTISAX_APK"
unzip -t "$SMARTISAX_APK" >/dev/null

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$OUT_RAW_FOR_LPDUMP" \
  "${OUT_SPARSE}.lpdump"* "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*.xml "${WORK_DIR}"/*-avb-info.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
  echo

  echo "## source"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
  prepare_inputs
  echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size "system_b pure ext4" "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  : > "${WORK_DIR}/removed-system-paths.tsv"
  : > "${WORK_DIR}/config-filtered.tsv"
  : > "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_WEBVIEW_SHA256" "${WORK_DIR}/system-webview-before.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$STOCK_BROWSERCHROME_SHA256" "${WORK_DIR}/browserchrome-before.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$LAUNCHER_APK" "$STOCK_LAUNCHER_SHA256" "${WORK_DIR}/launcher-before.apk"
  ! debugfs_path_exists "$SYSTEM_B_IMG" "$BROWSERCHROME_OAT_DIR" || die "BrowserChrome oat dir unexpectedly present in source"

  for removed_path in "${REMOVED_PATHS[@]}"; do
    debugfs_path_exists "$SYSTEM_B_IMG" "$removed_path" || die "expected removal source missing: ${removed_path}"
    if debugfs_rm_tree "$SYSTEM_B_IMG" "$removed_path"; then
      printf '%s\tremoved\n' "$removed_path" >> "${WORK_DIR}/removed-system-paths.tsv"
    else
      die "failed to remove ${removed_path}"
    fi
  done

  for config_path in "${CONFIG_FILTERS[@]}"; do
    tag="$(basename "$config_path" | tr -cd 'A-Za-z0-9_.-' | tr '.' '-')"
    filter_config_file "$SYSTEM_B_IMG" "$config_path" "$tag"
  done

  install_smartisax_apk "$SYSTEM_B_IMG"
  set_dir_time "$SYSTEM_B_IMG" "/system/app" "system-app-parent" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"
  set_dir_time "$SYSTEM_B_IMG" "/system/priv-app" "system-priv-app-parent" >> "${WORK_DIR}/package-dir-mtime-bumps.tsv"

  for removed_path in "${REMOVED_PATHS[@]}"; do
    ! debugfs_path_exists "$SYSTEM_B_IMG" "$removed_path" || die "removed path still exists before fsck: ${removed_path}"
  done
  for keep_path in "${PRINT_KEEP_PATHS[@]}" "${PROJECTION_KEEP_PATHS[@]}"; do
    debugfs_path_exists "$SYSTEM_B_IMG" "$keep_path" || die "protected keep path missing: ${keep_path}"
  done
  verify_dumped_apk "$SYSTEM_B_IMG" "$SYSTEM_WEBVIEW_APK" "$DONOR_WEBVIEW_SHA256" "${WORK_DIR}/system-webview-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$BROWSERCHROME_APK" "$STOCK_BROWSERCHROME_SHA256" "${WORK_DIR}/browserchrome-after.apk"
  verify_dumped_apk "$SYSTEM_B_IMG" "$LAUNCHER_APK" "$STOCK_LAUNCHER_SHA256" "${WORK_DIR}/launcher-after.apk"
  debugfs_dump "$SYSTEM_B_IMG" "$SMARTISAX_APK_PATH" "${WORK_DIR}/smartisax-installed.apk"
  [ "$(sha256_one "${WORK_DIR}/smartisax-installed.apk")" = "$(sha256_one "$SMARTISAX_APK")" ] || die "installed Smartisax APK hash mismatch"
  unzip -t "${WORK_DIR}/smartisax-installed.apk" >/dev/null

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  for removed_path in "${REMOVED_PATHS[@]}"; do
    ! debugfs_path_exists "$SYSTEM_B_IMG" "$removed_path" || die "removed path reappeared after fsck: ${removed_path}"
  done
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  smartisax_apk_sha256="$(sha256_one "$SMARTISAX_APK")"
  smartisax_apk_bytes="$(size_bytes "$SMARTISAX_APK")"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo "smartisax_apk_sha256=${smartisax_apk_sha256}"
  echo "smartisax_apk_bytes=${smartisax_apk_bytes}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size "system_b FEC image" "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-v036-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-v036-avb-info.txt" || die "system_b lost FEC roots"
  echo "system_b_fec=ok"
  echo

  echo "## rebuild sparse super"
  "$LPMAKE" \
    --metadata-size="$METADATA_SIZE" \
    --metadata-slots="$METADATA_SLOTS" \
    --super-name=super \
    --device="super:${SUPER_SIZE}" \
    --group="qti_dynamic_partitions_a:${GROUP_A_MAX}" \
    --group="qti_dynamic_partitions_b:${GROUP_B_MAX}" \
    --partition="system_a:readonly:${SYSTEM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="product_a:readonly:${PRODUCT_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="vendor_a:readonly:${VENDOR_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="odm_a:readonly:${ODM_A_SIZE}:qti_dynamic_partitions_a" \
    --partition="system_b:readonly:${SYSTEM_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="system_ext_b:readonly:${SYSTEM_EXT_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="product_b:readonly:${PRODUCT_B_PARTITION_SIZE}:qti_dynamic_partitions_b" \
    --partition="vendor_b:readonly:${VENDOR_B_SIZE}:qti_dynamic_partitions_b" \
    --partition="odm_b:readonly:${ODM_B_SIZE}:qti_dynamic_partitions_b" \
    --image="system_a=${SOURCE_EXTRACT_DIR}/system_a.img" \
    --image="product_a=${SOURCE_EXTRACT_DIR}/product_a.img" \
    --image="vendor_a=${SOURCE_EXTRACT_DIR}/vendor_a.img" \
    --image="odm_a=${SOURCE_EXTRACT_DIR}/odm_a.img" \
    --image="system_b=${SYSTEM_B_IMG}" \
    --image="system_ext_b=${SOURCE_EXTRACT_DIR}/system_ext_b.img" \
    --image="product_b=${SOURCE_PRODUCT_B_IMG}" \
    --image="vendor_b=${SOURCE_EXTRACT_DIR}/vendor_b.img" \
    --image="odm_b=${SOURCE_EXTRACT_DIR}/odm_b.img" \
    --block-size=4096 \
    --sparse \
    --output="$OUT_SPARSE"
  dump_lpdump
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=$(sha256_one "$OUT_SPARSE")"
  echo

  system_hash="$(sha256_one "$SYSTEM_B_IMG")"
  product_hash="$(sha256_one "$SOURCE_PRODUCT_B_IMG")"
  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse_super=${SOURCE_SPARSE}"
    echo "source_sparse_super_sha256=${SOURCE_SPARSE_SHA256}"
    echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
    echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo "source_product_b=${SOURCE_PRODUCT_B_IMG}"
    echo "source_product_b_sha256=${SOURCE_PRODUCT_B_SHA256}"
    echo "source_extract_dir=${SOURCE_EXTRACT_DIR}"
    echo "patched_partitions=system_b"
    echo "retained_partitions_from_source=system_a,product_a,vendor_a,odm_a,system_ext_b,product_b,vendor_b,odm_b"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "product_b_image=${SOURCE_PRODUCT_B_IMG}"
    echo "product_b_sha256=${product_hash}"
    echo "smartisax_apk=${SMARTISAX_APK}"
    echo "smartisax_apk_sha256=${smartisax_apk_sha256}"
    echo "smartisax_apk_bytes=${smartisax_apk_bytes}"
    echo "smartisax_package=${SMARTISAX_APK_PACKAGE}"
    echo "smartisax_system_path=${SMARTISAX_APK_PATH}"
    echo "debloat_source_id=user_selected_plus_smartisan_wallpapers_reserve"
    echo "debloat_preserves_print_stack=yes"
    echo "debloat_preserves_tnt_projection=yes"
    echo "debloat_preserves_stock_launcher=yes"
    echo "debloat_preserves_stock_browserchrome=yes"
    echo "debloat_preserves_m150_webview=yes"
    echo "debloat_includes_smartisan_wallpapers=yes"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "package_dir_mtime_hex=${PACKAGE_DIR_MTIME_HEX}"
    echo "package_dir_mtime_note=${PACKAGE_DIR_MTIME_NOTE}"
    echo "system_webview_apk_sha256=${DONOR_WEBVIEW_SHA256}"
    echo "browserchrome_apk_sha256=${STOCK_BROWSERCHROME_SHA256}"
    echo "launcher_apk_sha256=${STOCK_LAUNCHER_SHA256}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "product_b_partition_size=${PRODUCT_B_PARTITION_SIZE}"
    echo "fec_status=system_b_generated_roots_2_product_b_retained_from_v0352_roots_2"
    echo "risk_note=SlardarOsClient and WallpaperBackup delete preflights are RED because they use android.uid.system; included by explicit user-selected debloat set with rollback/preflight gates"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# removed_system_paths"
    cat "${WORK_DIR}/removed-system-paths.tsv"
    echo
    echo "# config_filtered"
    cat "${WORK_DIR}/config-filtered.tsv"
    echo
    echo "# package_dir_mtime_bumps"
    cat "${WORK_DIR}/package-dir-mtime-bumps.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SOURCE_PRODUCT_B_IMG" "$SMARTISAX_APK"
  } > "$MANIFEST"
  cp "$MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
  echo "manifest=${MANIFEST}"
  echo "result=PASS_BUILD_V036_SMARTISAX_SHELL_DEBLOAT"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "System image: ${SYSTEM_B_IMG}"
echo "Product image retained: ${SOURCE_PRODUCT_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
