#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

VARIANT="${VARIANT:-v0.usb2-physical-cdrom-iso-delete}"
SOURCE_VARIANT="v0.usb1-no-smartisan-cdrom"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.usb1-no-smartisan-cdrom.sparse.img}"
SOURCE_SPARSE_SHA256="1608da03f036a4e9d4972d7c892fd018903e603a299040e5464a1512547829bc"
SOURCE_VENDOR_B_SHA256="92cc0620019295f7e2ceeb982c011441ba81d65a46376c07eab032827d668afd"
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
CDROM_ISO_PATH="/etc/cdrom_install.iso"
CDROM_ISO_SHA256="f4a5f3f482c9b091557a9b4366c8b808fa1cfd4d8c5f7afdbc11af12b0af25a0"

PURPOSE="Physically remove the inert Smartisan transfer-tool ISO from vendor_b after v0.usb1 disabled active mass_storage, then zero old ISO blocks that remain free after deletion while preserving blocks reassigned to existing files."
RESULT_NAME="PASS_BUILD_V0USB2_PHYSICAL_CDROM_ISO_DELETE"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.usb2-physical-cdrom-iso-delete.sh

Builds a vendor_b-only candidate on top of live-proven v0.usb1. It removes
/vendor/etc/cdrom_install.iso from the vendor filesystem, then zeroes old ISO
blocks that are still free after deletion. If e2fsck reassigns a formerly
deduped/shared block to an existing file, that block is recorded and preserved.
The script does not touch a live device, /data, ADB, fastboot, or the current
USB init text changes from v0.usb1.
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

audit_iso_blocks() {
  local image="$1" path="$2" tag="$3"
  local json_report="${WORK_DIR}/${tag}-block-owner-audit.json"
  local blocks_file="${WORK_DIR}/${tag}-unique-blocks.txt"
  local env_file="${WORK_DIR}/${tag}-block-owner-audit.env"
  python3 - "$DEBUGFS" "$image" "$path" "$tag" "$json_report" "$blocks_file" "$env_file" <<'PY'
import collections
import json
import re
import subprocess
import sys
from pathlib import Path

debugfs, image, public_path, tag, json_report, blocks_file, env_file = sys.argv[1:8]

def run_debugfs(command: str) -> str:
    return subprocess.check_output(
        [debugfs, "-R", command, image],
        text=True,
        stderr=subprocess.STDOUT,
    )

stats_output = run_debugfs("stats")
block_size_match = re.search(r"^Block size:\s+(\d+)$", stats_output, flags=re.MULTILINE)
if not block_size_match:
    raise SystemExit("could not parse ext4 block size")
block_size = int(block_size_match.group(1))

stat_output = run_debugfs(f"stat {public_path}")
inode_match = re.search(r"Inode:\s+(\d+)", stat_output)
size_match = re.search(r"User:.*?Size:\s+(\d+)", stat_output)
if not inode_match or not size_match:
    raise SystemExit(f"could not read inode/size for {public_path}")
expected_inode = int(inode_match.group(1))
file_size = int(size_match.group(1))

blocks_output = run_debugfs(f"blocks {public_path}")
block_text = "\n".join(line for line in blocks_output.splitlines() if not line.startswith("debugfs "))
blocks = [int(value) for value in re.findall(r"\b\d+\b", block_text)]
if not blocks:
    raise SystemExit(f"no blocks found for {public_path}")

unique_blocks = sorted(set(blocks))
counts = collections.Counter(blocks)
bad = []
missing = []
for index in range(0, len(unique_blocks), 200):
    batch = unique_blocks[index:index + 200]
    icheck_output = run_debugfs("icheck " + " ".join(str(block) for block in batch))
    seen = {}
    for line in icheck_output.splitlines():
        match = re.match(r"^(\d+)\s+(.+)$", line.strip())
        if not match or match.group(1) == "Block":
            continue
        block = int(match.group(1))
        owner_text = match.group(2).strip()
        owners = [int(value) for value in re.findall(r"\d+", owner_text)]
        seen[block] = (owner_text, owners)
    for block in batch:
        if block not in seen:
            missing.append(block)
            continue
        owner_text, owners = seen[block]
        if owners != [expected_inode]:
            bad.append(
                {
                    "block": block,
                    "owner_text": owner_text,
                    "owners": owners,
                    "within_iso_count": counts[block],
                }
            )

report = {
    "tag": tag,
    "image": image,
    "path": public_path,
    "inode": expected_inode,
    "size": file_size,
    "block_size": block_size,
    "logical_block_entries": len(blocks),
    "unique_physical_blocks": len(unique_blocks),
    "internal_duplicate_block_entries": len(blocks) - len(unique_blocks),
    "top_internal_duplicates": [
        {"block": block, "count": count}
        for block, count in counts.most_common(20)
        if count > 1
    ],
    "missing_owner_rows_count": len(missing),
    "unexpected_owner_rows_count": len(bad),
    "all_unique_physical_blocks_owned_only_by_inode": not missing and not bad,
    "unexpected_owner_rows_sample": bad[:50],
    "missing_owner_rows_sample": missing[:50],
}

Path(json_report).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
Path(blocks_file).write_text("\n".join(str(block) for block in unique_blocks) + "\n", encoding="utf-8")
Path(env_file).write_text(
    "\n".join(
        [
            f"iso_inode={expected_inode}",
            f"iso_size={file_size}",
            f"iso_block_size={block_size}",
            f"iso_logical_block_entries={len(blocks)}",
            f"iso_unique_physical_blocks={len(unique_blocks)}",
            f"iso_internal_duplicate_block_entries={len(blocks) - len(unique_blocks)}",
        ]
    )
    + "\n",
    encoding="utf-8",
)

if missing or bad:
    raise SystemExit(f"{public_path} has non-unique or missing block owners; see {json_report}")

print(
    f"{tag}_unique_blocks=ok inode={expected_inode} "
    f"logical_blocks={len(blocks)} unique_blocks={len(unique_blocks)}"
)
PY
}

classify_blocks_after_delete() {
  local image="$1" blocks_file="$2" tag="$3"
  local free_file="${WORK_DIR}/${tag}-free-blocks-after-delete.txt"
  local owned_file="${WORK_DIR}/${tag}-reassigned-blocks-after-delete.tsv"
  local env_file="${WORK_DIR}/${tag}-after-delete-block-classification.env"
  python3 - "$DEBUGFS" "$image" "$blocks_file" "$tag" "$free_file" "$owned_file" "$env_file" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

debugfs, image, blocks_file, tag, free_file, owned_file, env_file = sys.argv[1:8]
blocks = [int(line.strip()) for line in Path(blocks_file).read_text(encoding="utf-8").splitlines() if line.strip()]
free = []
owned = []
for index in range(0, len(blocks), 200):
    batch = blocks[index:index + 200]
    output = subprocess.check_output(
        [debugfs, "-R", "icheck " + " ".join(str(block) for block in batch), image],
        text=True,
        stderr=subprocess.STDOUT,
    )
    seen = set()
    for line in output.splitlines():
        match = re.match(r"^(\d+)\s+(.+)$", line.strip())
        if not match or match.group(1) == "Block":
            continue
        block = int(match.group(1))
        seen.add(block)
        owner_text = match.group(2).strip()
        if "<block not found>" in owner_text:
            free.append(block)
        else:
            owned.append((block, owner_text))
    for block in batch:
        if block not in seen:
            free.append(block)
Path(free_file).write_text("\n".join(str(block) for block in free) + ("\n" if free else ""), encoding="utf-8")
Path(owned_file).write_text(
    "\n".join(f"{block}\t{owner}" for block, owner in owned) + ("\n" if owned else ""),
    encoding="utf-8",
)
Path(env_file).write_text(
    f"iso_free_blocks_after_delete={len(free)}\n"
    f"iso_reassigned_blocks_after_delete={len(owned)}\n",
    encoding="utf-8",
)
print(
    f"{tag}_blocks_after_delete=ok free_blocks={len(free)} "
    f"reassigned_blocks={len(owned)}"
)
PY
}

zero_blocks_from_list() {
  local image="$1" blocks_file="$2" block_size="$3" tag="$4"
  python3 - "$image" "$blocks_file" "$block_size" "$tag" <<'PY'
import sys
from pathlib import Path

image, blocks_file, block_size, tag = sys.argv[1:5]
block_size = int(block_size)
zero = b"\0" * block_size
blocks = [int(line.strip()) for line in Path(blocks_file).read_text(encoding="utf-8").splitlines() if line.strip()]
with open(image, "r+b") as f:
    for block in blocks:
        f.seek(block * block_size)
        f.write(zero)
print(f"{tag}_zeroed_blocks=ok blocks={len(blocks)} block_size={block_size}")
PY
}

delete_iso_file() {
  local image="$1"
  local cmd_file="${WORK_DIR}/cdrom-iso-delete.debugfs"

  debugfs_path_exists "$image" "$CDROM_ISO_PATH" || die "missing ${CDROM_ISO_PATH} before delete"
  audit_iso_blocks "$image" "$CDROM_ISO_PATH" "cdrom-iso"

  echo "rm ${CDROM_ISO_PATH}" > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  ! debugfs_path_exists "$image" "$CDROM_ISO_PATH" || die "${CDROM_ISO_PATH} still exists after debugfs rm"
  echo "cdrom_iso_path_removed=ok"
}

assert_no_cdrom_payload_strings() {
  local image="$1"
  if LC_ALL=C grep -a -q 'HandShaker.dmg' "$image"; then
    die "old HandShaker.dmg payload string remains in vendor_b image"
  fi
  if LC_ALL=C grep -a -q 'Guide_to_Transferring_Files_Between_Your_Phone_and_a_Mac.pdf' "$image"; then
    die "old transfer guide payload string remains in vendor_b image"
  fi
  if LC_ALL=C grep -a -q 'HandShaker_Win8&Later_Web_Setup.exe' "$image"; then
    die "old HandShaker Windows payload string remains in vendor_b image"
  fi
  echo "cdrom_payload_strings=absent"
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
  rm -f "${WORK_DIR}"/*.txt "${WORK_DIR}"/*.tsv "${WORK_DIR}"/*.prop "${WORK_DIR}"/*.rc \
  "${WORK_DIR}"/*.json "${WORK_DIR}"/*.env "${WORK_DIR}"/*.debugfs "${WORK_DIR}/vendor-b-source.img" \
  "${WORK_DIR}/cdrom_install.iso"

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
  debugfs_dump "$VENDOR_B_IMG" "/build.prop" "${WORK_DIR}/build.prop.source"
  debugfs_dump "$VENDOR_B_IMG" "/etc/init/hw/init.qcom.usb.rc" "${WORK_DIR}/init.qcom.usb.rc.source"
  debugfs_dump "$VENDOR_B_IMG" "/etc/init/hw/init.qcom.rc" "${WORK_DIR}/init.qcom.rc.source"
  debugfs_dump "$VENDOR_B_IMG" "$CDROM_ISO_PATH" "${WORK_DIR}/cdrom_install.iso"
  require_hash "${WORK_DIR}/cdrom_install.iso" "$CDROM_ISO_SHA256"
  grep -q '^persist.service.cdrom.enable=1$' "${WORK_DIR}/build.prop.source" \
    || die "source build.prop does not expose expected cdrom enable flag"
  grep -q 'setprop persist.sys.usb.config charging' "${WORK_DIR}/init.qcom.rc.source" \
    || die "source init.qcom.rc does not retain v0.usb1 charger fallback"
  ! grep -q 'setprop persist.sys.usb.config mass_storage' "${WORK_DIR}/init.qcom.rc.source" \
    || die "source init.qcom.rc still requests charger mass_storage"
  [ "$(count_fixed 'functions/mass_storage.0 /config/usb_gadget/g1/configs/b.1/f' "${WORK_DIR}/init.qcom.usb.rc.source")" -eq 0 ] \
    || die "source init.qcom.usb.rc still links mass_storage.0 into configs"
  grep -q 'symlink /config/usb_gadget/g1/functions/mtp.gs0' "${WORK_DIR}/init.qcom.usb.rc.source" \
    || die "source USB text lost MTP route"
  grep -q 'symlink /config/usb_gadget/g1/functions/ffs.adb' "${WORK_DIR}/init.qcom.usb.rc.source" \
    || die "source USB text lost ADB route"
  echo "source_usb1_mass_storage_config_symlinks=0"
  echo "source_cdrom_iso_sha256=${CDROM_ISO_SHA256}"
  echo

  echo "## rewrite vendor_b"
  python3 "$AVBTOOL" erase_footer --image "$VENDOR_B_IMG"
  [ "$(size_bytes "$VENDOR_B_IMG")" -eq "$VENDOR_B_EXT4_SIZE" ] || die "vendor_b ext4 size mismatch after footer erase"
  fsck_rw "$VENDOR_B_IMG"
  vendor_free_blocks_before="$(debugfs_stat_value "$VENDOR_B_IMG" "Free blocks")"
  delete_iso_file "$VENDOR_B_IMG"
  . "${WORK_DIR}/cdrom-iso-block-owner-audit.env"
  fsck_rw "$VENDOR_B_IMG"
  fsck_ro "$VENDOR_B_IMG"
  vendor_free_blocks_after_delete="$(debugfs_stat_value "$VENDOR_B_IMG" "Free blocks")"
  classify_blocks_after_delete "$VENDOR_B_IMG" "${WORK_DIR}/cdrom-iso-unique-blocks.txt" "cdrom-iso"
  . "${WORK_DIR}/cdrom-iso-after-delete-block-classification.env"
  zero_blocks_from_list "$VENDOR_B_IMG" "${WORK_DIR}/cdrom-iso-free-blocks-after-delete.txt" "$iso_block_size" "cdrom-iso-free"
  fsck_rw "$VENDOR_B_IMG"
  fsck_ro "$VENDOR_B_IMG"
  vendor_free_blocks_after_zero="$(debugfs_stat_value "$VENDOR_B_IMG" "Free blocks")"
  assert_no_cdrom_payload_strings "$VENDOR_B_IMG"
  rebuild_vendor_footer "$VENDOR_B_IMG"
  [ "$(size_bytes "$VENDOR_B_IMG")" -eq "$VENDOR_B_PARTITION_SIZE" ] || die "vendor_b FEC size mismatch"
  python3 "$AVBTOOL" info_image --image "$VENDOR_B_IMG" > "${WORK_DIR}/vendor-b-v0usb2-avb-info.txt"
  grep -q "FEC num roots:         2" "${WORK_DIR}/vendor-b-v0usb2-avb-info.txt" || die "vendor_b lost FEC roots"
  echo "vendor_b_fec=ok"
  echo "iso_inode=${iso_inode}"
  echo "iso_size=${iso_size}"
  echo "iso_logical_block_entries=${iso_logical_block_entries}"
  echo "iso_unique_physical_blocks=${iso_unique_physical_blocks}"
  echo "iso_internal_duplicate_block_entries=${iso_internal_duplicate_block_entries}"
  echo "iso_free_blocks_after_delete=${iso_free_blocks_after_delete}"
  echo "iso_reassigned_blocks_after_delete=${iso_reassigned_blocks_after_delete}"
  echo "vendor_free_blocks_before=${vendor_free_blocks_before}"
  echo "vendor_free_blocks_after_delete=${vendor_free_blocks_after_delete}"
  echo "vendor_free_blocks_after_zero=${vendor_free_blocks_after_zero}"
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
    echo "usb1_mass_storage_config_symlinks=retained_removed"
    echo "build_prop_cdrom_default=retained_1"
    echo "cdrom_iso_removed_path=${CDROM_ISO_PATH}"
    echo "cdrom_iso_removed_sha256=${CDROM_ISO_SHA256}"
    echo "cdrom_iso_block_owner_audit=${WORK_DIR}/cdrom-iso-block-owner-audit.json"
    echo "cdrom_iso_old_free_blocks_zeroed=true"
    echo "cdrom_iso_reassigned_blocks_preserved=${iso_reassigned_blocks_after_delete}"
    echo "iso_inode=${iso_inode}"
    echo "iso_size=${iso_size}"
    echo "iso_logical_block_entries=${iso_logical_block_entries}"
    echo "iso_unique_physical_blocks=${iso_unique_physical_blocks}"
    echo "iso_internal_duplicate_block_entries=${iso_internal_duplicate_block_entries}"
    echo "iso_free_blocks_after_delete=${iso_free_blocks_after_delete}"
    echo "iso_reassigned_blocks_after_delete=${iso_reassigned_blocks_after_delete}"
    echo "vendor_free_blocks_before=${vendor_free_blocks_before}"
    echo "vendor_free_blocks_after_delete=${vendor_free_blocks_after_delete}"
    echo "vendor_free_blocks_after_zero=${vendor_free_blocks_after_zero}"
    echo "sparse_tool_manifest=${SPARSE_TOOL_MANIFEST}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
