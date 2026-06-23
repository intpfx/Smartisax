#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

VARIANT="${VARIANT:-v0.usb1-no-smartisan-cdrom}"
SOURCE_VARIANT="v0.kg1-smartisax-skip-keyguard"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.kg1-smartisax-skip-keyguard.sparse.img}"
SOURCE_SPARSE_SHA256="450c5e1e34b20a7fd66422c96e359bf949e3968a62c3f6f73db81a229706518c"
SOURCE_VENDOR_B_SHA256="d6e09ff25c612cc7f01c05f455646926019e17b1fe73b98f6ab7c0d5b69489f6"
VENDOR_B_EXTENT="${VENDOR_B_EXTENT:-vendor_b=15439872:1696608}"

OUT_DIR="${ROOT_DIR}/hard-rom/build"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
VENDOR_B_IMG="${OUT_DIR}/vendor-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
SPARSE_TOOL_MANIFEST="${OUT_SPARSE}.SHA256SUMS.txt"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

VENDOR_B_PARTITION_SIZE=868663296
VENDOR_B_EXT4_SIZE=854872064
VENDOR_B_SALT="36de52c1e8bca3930d488db687661fb86892908e11ea50200c51223a92054783"
VENDOR_CONFIG_SELABEL="u:object_r:vendor_configs_file:s0"
CDROM_ISO_PATH="/etc/cdrom_install.iso"
CDROM_ISO_SHA256="f4a5f3f482c9b091557a9b4366c8b808fa1cfd4d8c5f7afdbc11af12b0af25a0"

PURPOSE="Disable the Smartisan transfer-tool virtual CD-ROM by removing mass_storage symlinks from vendor USB compositions while preserving ADB and MTP."
RESULT_NAME="PASS_BUILD_V0USB1_NO_SMARTISAN_CDROM"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.usb1-no-smartisan-cdrom.sh

Builds a vendor_b-only candidate on top of live-proven v0.kg1. It leaves
/vendor/etc/cdrom_install.iso intact, but prevents vendor init from wiring the
mass_storage function into the active USB gadget configs. The candidate keeps
ADB/MTP routes and does not touch /data or a live device.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }
size_bytes() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

copy_clone_or_plain() {
  local src="$1" dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    :
  else
    cp "$src" "$dst"
  fi
}

debugfs_path_exists() {
  local image="$1" path="$2" output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1" src="$2" dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

debugfs_stat_value() {
  local image="$1" key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

fsck_rw() {
  local image="$1" rc=0
  "$E2FSCK" -fy "$image" >/dev/null || rc=$?
  [ "$rc" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${rc}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

count_fixed() {
  local needle="$1" path="$2"
  awk -v n="$needle" 'index($0, n) { count++ } END { print count + 0 }' "$path"
}

replace_texts() {
  local init_usb_in="$1" init_qcom_in="$2"
  local init_usb_out="$3" init_qcom_out="$4"

  cp "$init_qcom_in" "$init_qcom_out"
  perl -0pi -e 's/setprop persist\.sys\.usb\.config mass_storage/setprop persist.sys.usb.config charging/g' "$init_qcom_out"
  grep -q 'setprop persist.sys.usb.config charging' "$init_qcom_out" || die "charger USB fallback patch failed"
  ! grep -q 'setprop persist.sys.usb.config mass_storage' "$init_qcom_out" || die "charger USB fallback still requests mass_storage"

  cp "$init_usb_in" "$init_usb_out"
  local before_links after_links
  before_links="$(count_fixed 'functions/mass_storage.0 /config/usb_gadget/g1/configs/b.1/f' "$init_usb_out")"
  [ "$before_links" -eq 4 ] || die "unexpected mass_storage config symlink count before patch: ${before_links}"
  perl -0pi -e '
    s/^\s*symlink \/config\/usb_gadget\/g1\/functions\/mass_storage\.0 \/config\/usb_gadget\/g1\/configs\/b\.1\/f[0-9]+\n//mg;
    s/"msc"/"no_cdrom"/g;
    s/"adb_msc"/"adb_no_cdrom"/g;
    s/"mtp_diag_mass_storage"/"mtp_diag_no_cdrom"/g;
    s/"mtp_diag_mass_storage_adb"/"mtp_diag_adb_no_cdrom"/g;
  ' "$init_usb_out"
  after_links="$(count_fixed 'functions/mass_storage.0 /config/usb_gadget/g1/configs/b.1/f' "$init_usb_out")"
  [ "$after_links" -eq 0 ] || die "mass_storage config symlinks remain after patch: ${after_links}"
  grep -q 'on property:sys.usb.config=mtp,diag,diag_mdm,mass_storage,adb' "$init_usb_out" \
    || die "old default USB composition trigger was removed"
  grep -q 'symlink /config/usb_gadget/g1/functions/ffs.adb' "$init_usb_out" \
    || die "ADB symlink routes missing after USB patch"
  grep -q 'symlink /config/usb_gadget/g1/functions/mtp.gs0' "$init_usb_out" \
    || die "MTP symlink routes missing after USB patch"
}

assert_unique_blocks_for_delete() {
  local image="$1" public_path="$2" tag="$3" audit_report
  audit_report="${WORK_DIR}/${tag}-unique-block-audit.txt"
  python3 - "$DEBUGFS" "$image" "$public_path" "$tag" "$audit_report" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

debugfs, image, public_path, tag, report = sys.argv[1:6]

def run_debugfs(command: str) -> str:
    return subprocess.check_output(
        [debugfs, "-R", command, image],
        text=True,
        stderr=subprocess.STDOUT,
    )

stat_output = run_debugfs(f"stat {public_path}")
inode_match = re.search(r"Inode:\s+(\d+)", stat_output)
if not inode_match:
    raise SystemExit(f"could not read inode for {public_path}")
expected_inode = inode_match.group(1)

blocks_output = run_debugfs(f"blocks {public_path}")
block_text = "\n".join(line for line in blocks_output.splitlines() if not line.startswith("debugfs "))
blocks = [int(value) for value in re.findall(r"\b\d+\b", block_text)]
if not blocks:
    raise SystemExit(f"no blocks found for {public_path}")

bad = []
for index in range(0, len(blocks), 256):
    batch = blocks[index:index + 256]
    icheck_output = run_debugfs("icheck " + " ".join(str(block) for block in batch))
    for line in icheck_output.splitlines():
        match = re.match(r"^(\d+)\s+(\d+)$", line.strip())
        if not match:
            continue
        block, inode = match.groups()
        if inode != expected_inode:
            bad.append((block, inode))

Path(report).write_text(
    f"tag={tag}\n"
    f"path={public_path}\n"
    f"inode={expected_inode}\n"
    f"block_count={len(blocks)}\n"
    f"bad_owner_count={len(bad)}\n"
    + "".join(f"bad_owner={block}:{inode}\n" for block, inode in bad[:20]),
    encoding="utf-8",
)
if bad:
    raise SystemExit(f"{public_path} has non-unique block owners; see {report}")
print(f"{tag}_unique_blocks=ok inode={expected_inode} blocks={len(blocks)}")
PY
}

replace_vendor_file_direct() {
  local image="$1" src="$2" dst="$3" mode="$4" selabel="$5" tag="$6"
  local dumped cmd_file src_hash dst_hash
  dumped="${WORK_DIR}/${tag}-after"
  cmd_file="${WORK_DIR}/${tag}-replace.debugfs"
  src_hash="$(sha256_one "$src")"

  debugfs_path_exists "$image" "$dst" || die "missing public vendor path: ${dst}"
  assert_unique_blocks_for_delete "$image" "$dst" "$tag"

  {
    echo "rm ${dst}"
    echo "write ${src} ${dst}"
    echo "set_inode_field ${dst} mode 010${mode}"
    echo "set_inode_field ${dst} uid 0"
    echo "set_inode_field ${dst} gid 0"
    echo "ea_set ${dst} security.selinux ${selabel}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_dump "$image" "$dst" "$dumped"
  dst_hash="$(sha256_one "$dumped")"
  [ "$dst_hash" = "$src_hash" ] || die "image file hash mismatch for ${dst}: ${dst_hash} != ${src_hash}"
  printf '%s\t%s\t%s\t%s\tdirect-unique-blocks\n' "$dst" "$src" "$src_hash" "$dumped" >> "${WORK_DIR}/replacements.tsv"
}

rebuild_vendor_footer() {
  local image="$1"
  PATH="$(dirname "$FEC"):${PATH}" python3 "$AVBTOOL" add_hashtree_footer \
    --image "$image" \
    --partition_size "$VENDOR_B_PARTITION_SIZE" \
    --partition_name vendor \
    --hash_algorithm sha1 \
    --salt "$VENDOR_B_SALT" \
    --block_size 4096 \
    --fec_num_roots 2 \
    --prop com.android.build.vendor.fingerprint:SMARTISAN/aries/aries:11/RKQ1.201217.002/1658135499:user/dev-keys \
    --prop com.android.build.vendor.os_version:11 \
    --prop com.android.build.vendor.security_patch:2022-06-10 \
    --prop com.android.build.vendor.security_patch:2022-06-10
}

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_executable "$DEBUGFS"
need_executable "$E2FSCK"
need_executable "$FEC"
need_file "$AVBTOOL"
need_file "$SPARSE_TOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$VENDOR_B_IMG" "$OUT_SPARSE" "$SPARSE_TOOL_MANIFEST" "$MANIFEST"
rm -f "${WORK_DIR}"/*.txt "${WORK_DIR}"/*.prop "${WORK_DIR}"/*.rc "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*-after \
  "${WORK_DIR}/replacements.tsv" "${WORK_DIR}/vendor-b-source.img" "${WORK_DIR}/cdrom_install.iso"

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "boundary=offline build only; no adb, no fastboot, no flash, no reboot, no /data mutation"
  echo

  echo "## extract vendor_b"
  "$SPARSE_TOOL" \
    --source-sparse "$SOURCE_SPARSE" \
    --extent "$VENDOR_B_EXTENT" \
    --extract-image "vendor_b=${WORK_DIR}/vendor-b-source.img"
  require_hash "${WORK_DIR}/vendor-b-source.img" "$SOURCE_VENDOR_B_SHA256"
  copy_clone_or_plain "${WORK_DIR}/vendor-b-source.img" "$VENDOR_B_IMG"
  check_size="$(size_bytes "$VENDOR_B_IMG")"
  [ "$check_size" -eq "$VENDOR_B_PARTITION_SIZE" ] || die "vendor_b size mismatch: ${check_size}"
  echo "source_vendor_b_sha256=${SOURCE_VENDOR_B_SHA256}"
  echo

  echo "## source evidence"
  debugfs_dump "$VENDOR_B_IMG" "/build.prop" "${WORK_DIR}/build.prop.stock"
  debugfs_dump "$VENDOR_B_IMG" "/etc/init/hw/init.qcom.usb.rc" "${WORK_DIR}/init.qcom.usb.rc.stock"
  debugfs_dump "$VENDOR_B_IMG" "/etc/init/hw/init.qcom.rc" "${WORK_DIR}/init.qcom.rc.stock"
  debugfs_dump "$VENDOR_B_IMG" "$CDROM_ISO_PATH" "${WORK_DIR}/cdrom_install.iso"
  require_hash "${WORK_DIR}/cdrom_install.iso" "$CDROM_ISO_SHA256"
  grep -q '^persist.service.cdrom.enable=1$' "${WORK_DIR}/build.prop.stock" \
    || die "stock build.prop does not expose expected cdrom enable flag"
  grep -q 'setprop persist.sys.usb.config mass_storage' "${WORK_DIR}/init.qcom.rc.stock" \
    || die "stock init.qcom.rc does not expose charger mass_storage fallback"
  [ "$(count_fixed 'functions/mass_storage.0 /config/usb_gadget/g1/configs/b.1/f' "${WORK_DIR}/init.qcom.usb.rc.stock")" -eq 4 ] \
    || die "stock init.qcom.usb.rc mass_storage symlink evidence changed"
  echo "stock_usb_mass_storage_symlinks=4"
  echo "cdrom_iso_retained_sha256=${CDROM_ISO_SHA256}"
  echo

  echo "## patch vendor text files"
  replace_texts \
    "${WORK_DIR}/init.qcom.usb.rc.stock" \
    "${WORK_DIR}/init.qcom.rc.stock" \
    "${WORK_DIR}/init.qcom.usb.rc.usb1" \
    "${WORK_DIR}/init.qcom.rc.usb1"
  echo "build_prop_cdrom_default=retained_1"
  echo "build_prop_note=runtime persist.service.cdrom.enable may remain /data-persisted; mass_storage is blocked at configfs composition instead"
  echo "charger_usb_config=charging"
  echo "mass_storage_config_symlinks_removed=4"
  echo

  echo "## rewrite vendor_b"
  python3 "$AVBTOOL" erase_footer --image "$VENDOR_B_IMG"
  [ "$(size_bytes "$VENDOR_B_IMG")" -eq "$VENDOR_B_EXT4_SIZE" ] || die "vendor_b ext4 size mismatch after footer erase"
  fsck_rw "$VENDOR_B_IMG"
  vendor_free_blocks_before="$(debugfs_stat_value "$VENDOR_B_IMG" "Free blocks")"
  : > "${WORK_DIR}/replacements.tsv"
  replace_vendor_file_direct "$VENDOR_B_IMG" "${WORK_DIR}/init.qcom.usb.rc.usb1" "/etc/init/hw/init.qcom.usb.rc" "0644" "$VENDOR_CONFIG_SELABEL" "init-qcom-usb-rc"
  replace_vendor_file_direct "$VENDOR_B_IMG" "${WORK_DIR}/init.qcom.rc.usb1" "/etc/init/hw/init.qcom.rc" "0644" "$VENDOR_CONFIG_SELABEL" "init-qcom-rc"
  fsck_rw "$VENDOR_B_IMG"
  fsck_ro "$VENDOR_B_IMG"
  vendor_free_blocks_after="$(debugfs_stat_value "$VENDOR_B_IMG" "Free blocks")"
  rebuild_vendor_footer "$VENDOR_B_IMG"
  [ "$(size_bytes "$VENDOR_B_IMG")" -eq "$VENDOR_B_PARTITION_SIZE" ] || die "vendor_b FEC size mismatch"
  python3 "$AVBTOOL" info_image --image "$VENDOR_B_IMG" > "${WORK_DIR}/vendor-b-v0usb1-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/vendor-b-v0usb1-avb-info.txt" || die "vendor_b lost FEC roots"
  echo "vendor_b_fec=ok"
  echo "vendor_free_blocks_before=${vendor_free_blocks_before}"
  echo "vendor_free_blocks_after=${vendor_free_blocks_after}"
  echo

  echo "## pack sparse super"
  "$SPARSE_TOOL" \
    --source-sparse "$SOURCE_SPARSE" \
    --extent "$VENDOR_B_EXTENT" \
    --out "$OUT_SPARSE" \
    --image "vendor_b=${VENDOR_B_IMG}" \
    --variant "$VARIANT"
  need_file "$SPARSE_TOOL_MANIFEST"
  "$SPARSE_TOOL" \
    --source-sparse "$OUT_SPARSE" \
    --extent "$VENDOR_B_EXTENT" \
    --verify-image "vendor_b=${VENDOR_B_IMG}"
  echo

  vendor_hash="$(sha256_one "$VENDOR_B_IMG")"
  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  tool_vendor_hash="$(awk -F= '$1 == "vendor_b_sha256" {print $2; exit}' "$SPARSE_TOOL_MANIFEST")"
  tool_vendor_slice_hash="$(awk -F= '$1 == "vendor_b_slice_sha256" {print $2; exit}' "$SPARSE_TOOL_MANIFEST")"
  [ "$tool_vendor_hash" = "$vendor_hash" ] || die "sparse manifest vendor_b hash mismatch"
  [ "$tool_vendor_slice_hash" = "$vendor_hash" ] || die "sparse vendor_b slice hash mismatch"

  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=offline candidate only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse_super=${SOURCE_SPARSE}"
    echo "source_sparse_super_sha256=${SOURCE_SPARSE_SHA256}"
    echo "source_vendor_b_sha256=${SOURCE_VENDOR_B_SHA256}"
    echo "vendor_b_extent=${VENDOR_B_EXTENT}"
    echo "patched_partitions=vendor_b"
    echo "retained_partitions_from_source=all_except_vendor_b"
    echo "sparse_super=${OUT_SPARSE}"
    echo "sparse_super_sha256=${sparse_hash}"
    echo "vendor_b_image=${VENDOR_B_IMG}"
    echo "vendor_b_sha256=${vendor_hash}"
    echo "vendor_b_partition_size=${VENDOR_B_PARTITION_SIZE}"
    echo "vendor_b_ext4_size=${VENDOR_B_EXT4_SIZE}"
    echo "fec_status=vendor_b_generated_roots_2"
    echo "build_prop_cdrom_default=retained_1"
    echo "build_prop_note=runtime persist.service.cdrom.enable may remain /data-persisted; mass_storage is blocked at configfs composition instead"
    echo "charger_usb_config=charging"
    echo "usb_mass_storage_config_symlinks=removed"
    echo "cdrom_iso_retained_path=${CDROM_ISO_PATH}"
    echo "cdrom_iso_retained_sha256=${CDROM_ISO_SHA256}"
    echo "vendor_free_blocks_before=${vendor_free_blocks_before}"
    echo "vendor_free_blocks_after=${vendor_free_blocks_after}"
    echo "sparse_tool_manifest=${SPARSE_TOOL_MANIFEST}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "# replacements"
    cat "${WORK_DIR}/replacements.tsv"
    echo
    shasum -a 256 "$OUT_SPARSE" "$VENDOR_B_IMG" "$SOURCE_SPARSE"
  } > "$MANIFEST"
  cp "$MANIFEST" "$SPARSE_TOOL_MANIFEST"

  echo "vendor_b_image=${VENDOR_B_IMG}"
  echo "vendor_b_sha256=${vendor_hash}"
  echo "sparse_super=${OUT_SPARSE}"
  echo "sparse_super_sha256=${sparse_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} 2>&1 | tee "$REPORT"

echo "Built: ${OUT_SPARSE}"
echo "Vendor image: ${VENDOR_B_IMG}"
echo "Manifest: ${MANIFEST}"
echo "Report: ${REPORT}"
echo "Flash gate: explicit user confirmation required."
