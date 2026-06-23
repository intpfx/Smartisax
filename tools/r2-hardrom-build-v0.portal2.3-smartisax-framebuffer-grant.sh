#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="${VARIANT:-v0.portal2.3-smartisax-framebuffer-grant}"
SOURCE_VARIANT="v0.portal2.2-smartisax-remote-screen-control-bufferfix"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal2.2-smartisax-remote-screen-control-bufferfix.sparse.img}"
SOURCE_SPARSE_SHA256="ae537afb619ff50b89885a06c9bfd623900f6e518ecfa1a6ad869b7ab19b8a2f"
SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal2.2-smartisax-remote-screen-control-bufferfix.img}"
SOURCE_SYSTEM_B_SHA256="5f5df249307e2ccdb9e7079c073cbe21ff07722798dea3dec4577e2389c9cda6"

SERVICES_JAR_CANDIDATE="${SERVICES_JAR_CANDIDATE:-${ROOT_DIR}/hard-rom/build/framework/services-portal2.3-smartisax-framebuffer-grant.jar}"
BASE_SERVICES_JAR_SHA256="366bf1c3d0d25d195a51a265064d4a648b3656f4d703e507e86652072262e864"
SERVICES_JAR_CANDIDATE_SHA256_EXPECTED="0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a"
SERVICES_JAR_PATH="/system/framework/services.jar"
SERVICES_PREOPT_DIR="/system/framework/oat/arm64"
SERVICES_ART_PATH="${SERVICES_PREOPT_DIR}/services.art"
SERVICES_ODEX_PATH="${SERVICES_PREOPT_DIR}/services.odex"
SERVICES_VDEX_PATH="${SERVICES_PREOPT_DIR}/services.vdex"

WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
OUT_SPARSE="${OUT_DIR}/super-otatrust-${VARIANT}.sparse.img"
MANIFEST="${OUT_DIR}/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_MANIFEST="${OUT_DIR}/system-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"
SYSTEM_SELABEL="u:object_r:system_file:s0"
SERVICES_FILE_MTIME_HEX="${SERVICES_FILE_MTIME_HEX:-0x6a3a30f0}"
SERVICES_FILE_MTIME_NOTE="${SERVICES_FILE_MTIME_NOTE:-2026-06-22 23:45:00 +0800; marks services.jar Smartisax READ_FRAME_BUFFER signature grant policy}"

PURPOSE="Grant only android.permission.READ_FRAME_BUFFER to com.smartisax.browser through a narrow PackageManager signature-permission policy, on top of v0.portal2.2."
RESULT_NAME="PASS_BUILD_V0PORTAL23_SMARTISAX_FRAMEBUFFER_GRANT"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.portal2.3-smartisax-framebuffer-grant.sh

Builds a system_b-only candidate on top of v0.portal2.2. It replaces only
/system/framework/services.jar with the v0.portal2.3 candidate, keeps Smartisax
APK and privapp XML unchanged, rebuilds system_b AVB/FEC roots=2, and patches
that system_b image into the v0.portal2.2 sparse super. It does not touch a
live device.
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

check_size() {
  local label="$1" path="$2" expected="$3" actual
  need_file "$path"
  actual="$(size_bytes "$path")"
  [ "$actual" -eq "$expected" ] || die "${label} size mismatch: actual=${actual} expected=${expected}"
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
  local image="$1" status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
}

set_inode_common() {
  local path="$1" mode="$2"
  cat <<EOF
set_inode_field ${path} mode ${mode}
set_inode_field ${path} uid 0
set_inode_field ${path} gid 0
ea_set ${path} security.selinux ${SYSTEM_SELABEL}
set_inode_field ${path} ctime ${SERVICES_FILE_MTIME_HEX}
set_inode_field ${path} atime ${SERVICES_FILE_MTIME_HEX}
set_inode_field ${path} mtime ${SERVICES_FILE_MTIME_HEX}
set_inode_field ${path} crtime ${SERVICES_FILE_MTIME_HEX}
EOF
}

verify_image_file_hash() {
  local image="$1" path="$2" expected="$3" label="$4" out actual
  out="${WORK_DIR}/${label}"
  debugfs_path_exists "$image" "$path" || die "missing image path: ${path}"
  debugfs_dump "$image" "$path" "$out"
  actual="$(sha256_one "$out")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_image_path_absent() {
  local image="$1" path="$2" label="$3"
  if debugfs_path_exists "$image" "$path"; then
    die "${label} unexpectedly exists: ${path}"
  fi
  printf '%s\tabsent\t%s\n' "$label" "$path"
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
    return subprocess.check_output([debugfs, "-R", command, image], text=True, stderr=subprocess.STDOUT)

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

replace_services_jar() {
  local image="$1" cmd_file dumped
  cmd_file="${WORK_DIR}/replace-services-jar.debugfs"
  dumped="${WORK_DIR}/services-jar-public-after.jar"

  debugfs_path_exists "$image" "$SERVICES_JAR_PATH" || die "missing public services.jar"
  debugfs_dump "$image" "$SERVICES_JAR_PATH" "${WORK_DIR}/services-jar-base-before-replace.jar"
  [ "$(sha256_one "${WORK_DIR}/services-jar-base-before-replace.jar")" = "$BASE_SERVICES_JAR_SHA256" ] || die "base services.jar hash mismatch before replace"
  assert_unique_blocks_for_delete "$image" "$SERVICES_JAR_PATH" "services-jar-portal23"

  {
    echo "rm ${SERVICES_JAR_PATH}"
    echo "write ${SERVICES_JAR_CANDIDATE} ${SERVICES_JAR_PATH}"
    set_inode_common "$SERVICES_JAR_PATH" "0100644"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$SERVICES_JAR_PATH" || die "missing public services.jar after replacement"
  debugfs_dump "$image" "$SERVICES_JAR_PATH" "$dumped"
  [ "$(sha256_one "$dumped")" = "$SERVICES_JAR_CANDIDATE_SHA256_EXPECTED" ] || die "public services.jar hash mismatch after replacement"
  unzip -t "$dumped" >/dev/null || die "public services.jar zip test failed"
}

verify_services_jar_delta() {
  local base="$1" candidate="$2" report="$3"
  python3 - "$base" "$candidate" "$report" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
candidate = Path(sys.argv[2])
report = Path(sys.argv[3])

def entry_map(path: Path):
    with zipfile.ZipFile(path, "r") as zf:
        return {
            info.filename: {
                "sha256": hashlib.sha256(zf.read(info.filename)).hexdigest(),
                "compress_type": info.compress_type,
            }
            for info in zf.infolist()
        }

base_entries = entry_map(base)
candidate_entries = entry_map(candidate)
if list(base_entries) != list(candidate_entries):
    raise SystemExit("services.jar entry list/order mismatch")
changed = [name for name in base_entries if base_entries[name]["sha256"] != candidate_entries[name]["sha256"]]
if changed != ["classes.dex"]:
    raise SystemExit(f"unexpected changed services.jar entries: {changed}")
for name, meta in candidate_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"candidate services.jar entry is not STORED: {name}")
if "META-INF/MANIFEST.MF" not in candidate_entries:
    raise SystemExit("candidate services.jar lost META-INF/MANIFEST.MF")

with report.open("w", encoding="utf-8") as f:
    f.write("changed_entries=" + ",".join(changed) + "\n")
    f.write("all_entries_stored=true\n")
    f.write("manifest_retained=true\n")
PY
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

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_executable "$E2FSCK"
need_executable "$DEBUGFS"
need_executable "$FEC"
need_file "$AVBTOOL"
need_file "$SPARSE_TOOL"
require_hash "$SOURCE_SPARSE" "$SOURCE_SPARSE_SHA256"
require_hash "$SOURCE_SYSTEM_B" "$SOURCE_SYSTEM_B_SHA256"
require_hash "$SERVICES_JAR_CANDIDATE" "$SERVICES_JAR_CANDIDATE_SHA256_EXPECTED"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$OUT_SPARSE" "$MANIFEST" "$SYSTEM_MANIFEST" "${OUT_SPARSE}.SHA256SUMS.txt"
rm -f "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*.jar "${WORK_DIR}"/*.txt

{
  echo "# ${VARIANT} offline build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "boundary=offline build only; no adb, no fastboot, no flash, no reboot, no /data mutation"
  echo

  echo "## inputs"
  echo "source_sparse=${SOURCE_SPARSE}"
  echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
  echo "source_system_b=${SOURCE_SYSTEM_B}"
  echo "source_system_b_extent=${SYSTEM_B_EXTENT}"
  echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
  echo "services_jar_candidate=${SERVICES_JAR_CANDIDATE}"
  echo "services_jar_candidate_sha256=${SERVICES_JAR_CANDIDATE_SHA256_EXPECTED}"
  echo "base_services_jar_sha256=${BASE_SERVICES_JAR_SHA256}"
  echo

  echo "## clone system_b"
  if cp -c "$SOURCE_SYSTEM_B" "$SYSTEM_B_IMG" 2>/dev/null; then
    echo "source_system_b_clone=apfs_clone"
  else
    cp "$SOURCE_SYSTEM_B" "$SYSTEM_B_IMG"
    echo "source_system_b_clone=full_copy"
  fi
  [ "$(sha256_one "$SYSTEM_B_IMG")" = "$SOURCE_SYSTEM_B_SHA256" ] || die "source system_b clone hash mismatch"
  check_size system_b_source_partition "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  echo "source_system_b_prepare=ok"
  echo

  echo "## patch system_b"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$BASE_SERVICES_JAR_SHA256" "services-jar-before.jar"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "services-art-public-before"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "services-odex-public-before"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "services-vdex-public-before"

  replace_services_jar "$SYSTEM_B_IMG"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$SERVICES_JAR_CANDIDATE_SHA256_EXPECTED" "services-jar-after.jar"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "services-art-public-final"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "services-odex-public-final"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "services-vdex-public-final"
  verify_services_jar_delta \
    "${WORK_DIR}/services-jar-base-before-replace.jar" \
    "${WORK_DIR}/services-jar-after.jar" \
    "${WORK_DIR}/services-jar-delta.txt"
  cat "${WORK_DIR}/services-jar-delta.txt"
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "services_file_mtime_hex=${SERVICES_FILE_MTIME_HEX}"
  echo "services_file_mtime_note=${SERVICES_FILE_MTIME_NOTE}"
  echo "system_free_blocks_before=${system_free_blocks_before}"
  echo "system_free_blocks_after=${system_free_blocks_after}"
  echo

  rebuild_system_footer "$SYSTEM_B_IMG"
  check_size system_b_fec_image "$SYSTEM_B_IMG" "$SYSTEM_B_PARTITION_SIZE"
  python3 "$AVBTOOL" info_image --image "$SYSTEM_B_IMG" > "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b AVB original size mismatch"
  grep -q "FEC num roots:         2" "${WORK_DIR}/system-b-${VARIANT}-avb-info.txt" || die "system_b lost FEC roots"
  echo "system_b_fec=ok"
  echo

  system_hash="$(sha256_one "$SYSTEM_B_IMG")"
  changed_entries="$(awk -F= '$1 == "changed_entries" {print $2}' "${WORK_DIR}/services-jar-delta.txt")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "boundary=offline system_b build only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse=${SOURCE_SPARSE}"
    echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
    echo "source_system_b=${SOURCE_SYSTEM_B}"
    echo "source_system_b_extent=${SYSTEM_B_EXTENT}"
    echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "patched_partitions=system_b"
    echo "services_jar_path=${SERVICES_JAR_PATH}"
    echo "services_jar_candidate=${SERVICES_JAR_CANDIDATE}"
    echo "services_jar_candidate_sha256=${SERVICES_JAR_CANDIDATE_SHA256_EXPECTED}"
    echo "base_services_jar_sha256=${BASE_SERVICES_JAR_SHA256}"
    echo "services_jar_delete_boundary=unique_block_owner_audited"
    echo "services_jar_changed_entries=${changed_entries}"
    echo "services_jar_manifest_retained=true"
    echo "services_preopt_public_absent=true"
    echo "services_file_mtime_hex=${SERVICES_FILE_MTIME_HEX}"
    echo "services_file_mtime_note=${SERVICES_FILE_MTIME_NOTE}"
    echo "fec_status=system_b_generated_roots_2"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$SYSTEM_B_IMG" "$SERVICES_JAR_CANDIDATE" "$SOURCE_SPARSE"
  } > "$SYSTEM_MANIFEST"

  echo "system_b_image=${SYSTEM_B_IMG}"
  echo "system_b_sha256=${system_hash}"
  echo

  echo "## sparse patch"
  "$SPARSE_TOOL" \
    --source-sparse "$SOURCE_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --out "$OUT_SPARSE" \
    --image "system_b=${SYSTEM_B_IMG}" \
    --variant "$VARIANT"
  "$SPARSE_TOOL" \
    --source-sparse "$OUT_SPARSE" \
    --extent "$SYSTEM_B_EXTENT" \
    --verify-image "system_b=${SYSTEM_B_IMG}"

  sparse_hash="$(sha256_one "$OUT_SPARSE")"
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "boundary=offline sparse build only; explicit user confirmation required before live flash"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_sparse=${SOURCE_SPARSE}"
    echo "source_sparse_sha256=${SOURCE_SPARSE_SHA256}"
    echo "system_b_extent=${SYSTEM_B_EXTENT}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "super_sparse_image=${OUT_SPARSE}"
    echo "super_sparse_sha256=${sparse_hash}"
    echo "sparse_tool_manifest=${OUT_SPARSE}.SHA256SUMS.txt"
    echo "services_jar_path=${SERVICES_JAR_PATH}"
    echo "services_jar_candidate_sha256=${SERVICES_JAR_CANDIDATE_SHA256_EXPECTED}"
    echo "base_services_jar_sha256=${BASE_SERVICES_JAR_SHA256}"
    echo "services_jar_changed_entries=${changed_entries}"
    echo "patched_partitions=system_b"
    echo "system_manifest=${SYSTEM_MANIFEST}"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$OUT_SPARSE" "$SYSTEM_B_IMG" "$SERVICES_JAR_CANDIDATE" "$SOURCE_SPARSE"
  } > "$MANIFEST"

  echo "super_sparse_image=${OUT_SPARSE}"
  echo "super_sparse_sha256=${sparse_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} 2>&1 | tee "$REPORT"

echo "Sparse super: $OUT_SPARSE"
echo "System image: $SYSTEM_B_IMG"
echo "Manifest: $MANIFEST"
echo "System manifest: $SYSTEM_MANIFEST"
echo "Report: $REPORT"
echo "Flash gate: explicit user confirmation required."
