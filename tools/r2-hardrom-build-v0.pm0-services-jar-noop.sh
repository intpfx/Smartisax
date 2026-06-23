#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
FEC="${FEC:-${ROOT_DIR}/third_party/aosp-system-extras-fec/bin/fec}"

VARIANT="${VARIANT:-v0.pm0-services-jar-noop}"
SOURCE_VARIANT="v0.43e-textboom-codepath-arm64-runtime-repair"
SOURCE_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.43e-textboom-codepath-arm64-runtime-repair.img"
SOURCE_SYSTEM_B_SHA256="858e9922e126444c66c04e94515bc3fd16e8991c45d557cfac926e2d2d9fa01f"
SERVICES_JAR_CANDIDATE="${SERVICES_JAR_CANDIDATE:-${ROOT_DIR}/hard-rom/build/framework/services-pm-noop-roundtrip.jar}"
SERVICES_JAR_CANDIDATE_SHA256="30ff020c9dead1afba480dfc075b50454723296376feae0b20a1a58e82f763bc"
STOCK_SERVICES_JAR_SHA256="45945c1d1f9f25be8b1db31df5d417504634305d4033e9421f7d3cd416057da6"

WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}"
OUT_DIR="${ROOT_DIR}/hard-rom/build"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
SYSTEM_B_IMG="${OUT_DIR}/system-otatrust-${VARIANT}.img"
MANIFEST="${OUT_DIR}/system-otatrust-${VARIANT}.SHA256SUMS.txt"
REPORT="${INSPECT_DIR}/build-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SYSTEM_B_SALT="fd64da91753a58a5c95717d8e67e8147f314f9635769d2b6983c01adb98797a6"
SYSTEM_SELABEL="u:object_r:system_file:s0"

SERVICES_JAR_PATH="/system/framework/services.jar"
SERVICES_PREOPT_DIR="/system/framework/oat/arm64"
SERVICES_ART_PATH="${SERVICES_PREOPT_DIR}/services.art"
SERVICES_ODEX_PATH="${SERVICES_PREOPT_DIR}/services.odex"
SERVICES_VDEX_PATH="${SERVICES_PREOPT_DIR}/services.vdex"
SERVICES_ART_SHA256="f650b73c2f062aada6b0fdd465e288f5392fdc05d06b68a1c2a6cf2989108c25"
SERVICES_ODEX_SHA256="f7339d7813955f6bdc2334f99e312795414b30c041c1804b91bb68d3a710f70b"
SERVICES_VDEX_SHA256="5f1493119d2c2339f0265ea774065fecaf37f30bc65ee2c730fca5d05a4b0a93"

PURPOSE="Install the v0.pm0 PackageManager services.jar no-op roundtrip into system_b while removing uniquely owned stale services preopt artifacts."
RESULT_NAME="PASS_BUILD_V0PM0_SERVICES_JAR_NOOP_SYSTEM_IMAGE"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-hardrom-build-v0.pm0-services-jar-noop.sh

Builds only a system_b image candidate for the PackageManager framework no-op
gate. This script does not build super, flash, reboot, or touch a live device.

The image-level gate:
  - starts from live-proven v0.43e system_b
  - replaces /system/framework/services.jar with the no-op roundtrip jar
  - audits stock services.jar block ownership, then replaces its public path
  - audits stale arm64 services.art/odex/vdex block ownership, then removes
    their public paths to free enough ext4 space and force loading new dex
  - rebuilds the system_b AVB hashtree footer with FEC roots=2
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
  local image="$1" status=0
  "$E2FSCK" -fy "$image" >/dev/null || status=$?
  [ "$status" -le 1 ] || die "e2fsck repair failed for ${image} with exit code ${status}"
}

fsck_ro() {
  "$E2FSCK" -fn "$1" >/dev/null
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

replace_services_jar() {
  local image="$1" cmd_file dumped
  cmd_file="${WORK_DIR}/replace-services-jar.debugfs"
  dumped="${WORK_DIR}/services-jar-public-after.jar"

  debugfs_path_exists "$image" "$SERVICES_JAR_PATH" || die "missing public services.jar"
  debugfs_dump "$image" "$SERVICES_JAR_PATH" "${WORK_DIR}/services-jar-stock-before-replace.jar"
  [ "$(sha256_one "${WORK_DIR}/services-jar-stock-before-replace.jar")" = "$STOCK_SERVICES_JAR_SHA256" ] || die "stock services.jar hash mismatch before replace"
  assert_unique_blocks_for_delete "$image" "$SERVICES_JAR_PATH" "services-jar"

  {
    echo "rm ${SERVICES_JAR_PATH}"
    echo "write ${SERVICES_JAR_CANDIDATE} ${SERVICES_JAR_PATH}"
    echo "set_inode_field ${SERVICES_JAR_PATH} mode 0100644"
    echo "set_inode_field ${SERVICES_JAR_PATH} uid 0"
    echo "set_inode_field ${SERVICES_JAR_PATH} gid 0"
    echo "ea_set ${SERVICES_JAR_PATH} security.selinux ${SYSTEM_SELABEL}"
  } > "$cmd_file"

  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  debugfs_path_exists "$image" "$SERVICES_JAR_PATH" || die "missing public services.jar after replacement"

  debugfs_dump "$image" "$SERVICES_JAR_PATH" "$dumped"
  [ "$(sha256_one "$dumped")" = "$SERVICES_JAR_CANDIDATE_SHA256" ] || die "public services.jar hash mismatch after replacement"
  unzip -t "$dumped" >/dev/null || die "public services.jar zip test failed"
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
block_text = "\n".join(
    line for line in blocks_output.splitlines()
    if not line.startswith("debugfs ")
)
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

remove_unique_public_path() {
  local image="$1" public_path="$2" expected_sha="$3" tag="$4"
  local cmd_file dumped
  cmd_file="${WORK_DIR}/remove-${tag}.debugfs"
  dumped="${WORK_DIR}/${tag}-before-remove"

  debugfs_path_exists "$image" "$public_path" || die "missing public ${tag}: ${public_path}"
  debugfs_dump "$image" "$public_path" "$dumped"
  [ "$(sha256_one "$dumped")" = "$expected_sha" ] || die "${tag} hash mismatch before remove"
  assert_unique_blocks_for_delete "$image" "$public_path" "$tag"

  echo "rm ${public_path}" > "$cmd_file"
  "$DEBUGFS" -w -f "$cmd_file" "$image" >/dev/null
  verify_image_path_absent "$image" "$public_path" "${tag}-public-after"
}

verify_services_jar_delta() {
  local stock="$1" candidate="$2" report="$3"
  python3 - "$stock" "$candidate" "$report" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
candidate = Path(sys.argv[2])
report = Path(sys.argv[3])

def entry_map(path: Path):
    with zipfile.ZipFile(path, "r") as zf:
        result = {}
        for info in zf.infolist():
            data = zf.read(info.filename)
            result[info.filename] = {
                "sha256": hashlib.sha256(data).hexdigest(),
                "compress_type": info.compress_type,
            }
        return result

stock_entries = entry_map(stock)
candidate_entries = entry_map(candidate)
if list(stock_entries) != list(candidate_entries):
    raise SystemExit("services.jar entry list/order mismatch")

changed = [
    name for name in stock_entries
    if stock_entries[name]["sha256"] != candidate_entries[name]["sha256"]
]
if changed != ["classes.dex", "classes2.dex"]:
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
require_hash "$SOURCE_SYSTEM_B_IMG" "$SOURCE_SYSTEM_B_SHA256"
require_hash "$SERVICES_JAR_CANDIDATE" "$SERVICES_JAR_CANDIDATE_SHA256"

mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$SYSTEM_B_IMG" "$MANIFEST"
rm -f "${WORK_DIR}"/*.debugfs "${WORK_DIR}"/*-after.jar "${WORK_DIR}"/*-before-remove "${WORK_DIR}"/*-unique-block-audit.txt "${WORK_DIR}"/*-avb-info.txt "${WORK_DIR}/services-jar-delta.txt" "${WORK_DIR}/services-jar-stock-before-replace.jar"

{
  echo "# ${VARIANT} offline system_b build"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "variant=${VARIANT}"
  echo "source_variant=${SOURCE_VARIANT}"
  echo "purpose=${PURPOSE}"
  echo "flash_gate=system_b image only; no super built; explicit user confirmation required before any live flash"
  echo

  echo "## inputs"
  echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
  echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
  echo "services_jar_candidate=${SERVICES_JAR_CANDIDATE}"
  echo "services_jar_candidate_sha256=${SERVICES_JAR_CANDIDATE_SHA256}"
  echo

  echo "## patch system_b"
  copy_clone_or_plain "$SOURCE_SYSTEM_B_IMG" "$SYSTEM_B_IMG"
  python3 "$AVBTOOL" erase_footer --image "$SYSTEM_B_IMG"
  check_size system_b_pure_ext4 "$SYSTEM_B_IMG" "$SYSTEM_B_EXT4_SIZE"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_before="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"

  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$STOCK_SERVICES_JAR_SHA256" "services-jar-before.jar"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "$SERVICES_ART_SHA256" "services-art-before"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "$SERVICES_ODEX_SHA256" "services-odex-before"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "$SERVICES_VDEX_SHA256" "services-vdex-before"

  remove_unique_public_path "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "$SERVICES_ART_SHA256" "services-art"
  remove_unique_public_path "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "$SERVICES_ODEX_SHA256" "services-odex"
  remove_unique_public_path "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "$SERVICES_VDEX_SHA256" "services-vdex"
  fsck_rw "$SYSTEM_B_IMG"
  system_free_blocks_after_preopt_remove="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
  echo "system_free_blocks_after_preopt_remove=${system_free_blocks_after_preopt_remove}"

  replace_services_jar "$SYSTEM_B_IMG"

  fsck_rw "$SYSTEM_B_IMG"
  fsck_ro "$SYSTEM_B_IMG"
  verify_image_file_hash "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$SERVICES_JAR_CANDIDATE_SHA256" "services-jar-after.jar"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ART_PATH" "services-art-public-final"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_ODEX_PATH" "services-odex-public-final"
  verify_image_path_absent "$SYSTEM_B_IMG" "$SERVICES_VDEX_PATH" "services-vdex-public-final"
  verify_services_jar_delta \
    "${WORK_DIR}/services-jar-stock-before-replace.jar" \
    "${WORK_DIR}/services-jar-after.jar" \
    "${WORK_DIR}/services-jar-delta.txt"
  cat "${WORK_DIR}/services-jar-delta.txt"
  system_free_blocks_after="$(debugfs_stat_value "$SYSTEM_B_IMG" "Free blocks")"
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
  {
    echo "variant=${VARIANT}"
    echo "purpose=${PURPOSE}"
    echo "flash_gate=system_b image only; no super built; explicit user confirmation required before any live flash"
    echo "image_mode=system_b_only_no_super"
    echo "source_variant=${SOURCE_VARIANT}"
    echo "source_system_b=${SOURCE_SYSTEM_B_IMG}"
    echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
    echo "system_b_image=${SYSTEM_B_IMG}"
    echo "system_b_sha256=${system_hash}"
    echo "system_b_partition_size=${SYSTEM_B_PARTITION_SIZE}"
    echo "system_b_ext4_size=${SYSTEM_B_EXT4_SIZE}"
    echo "patched_partitions=system_b"
    echo "services_jar_path=${SERVICES_JAR_PATH}"
    echo "services_jar_candidate=${SERVICES_JAR_CANDIDATE}"
    echo "services_jar_candidate_sha256=${SERVICES_JAR_CANDIDATE_SHA256}"
    echo "services_jar_stock_sha256=${STOCK_SERVICES_JAR_SHA256}"
    echo "services_jar_delete_boundary=unique_block_owner_audited"
    echo "services_jar_changed_entries=classes.dex,classes2.dex"
    echo "services_jar_manifest_retained=true"
    echo "services_preopt_public_absent=true"
    echo "services_preopt_delete_boundary=unique_block_owner_audited"
    echo "services_art_sha256=${SERVICES_ART_SHA256}"
    echo "services_odex_sha256=${SERVICES_ODEX_SHA256}"
    echo "services_vdex_sha256=${SERVICES_VDEX_SHA256}"
    echo "system_free_blocks_before=${system_free_blocks_before}"
    echo "system_free_blocks_after_preopt_remove=${system_free_blocks_after_preopt_remove}"
    echo "system_free_blocks_after=${system_free_blocks_after}"
    echo "fec_status=system_b_generated_roots_2"
    echo "build_report=${REPORT}"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    shasum -a 256 "$SYSTEM_B_IMG" "$SERVICES_JAR_CANDIDATE"
  } > "$MANIFEST"

  echo "system_b_image=${SYSTEM_B_IMG}"
  echo "system_b_sha256=${system_hash}"
  echo "manifest=${MANIFEST}"
  echo "result=${RESULT_NAME}"
} | tee "$REPORT"

echo "System image: $SYSTEM_B_IMG"
echo "Manifest: $MANIFEST"
echo "Report: $REPORT"
echo "Next gate: run tools/r2-verify-v0.pm0-services-jar-noop.sh --offline-image"
