#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
SIMG2IMG="${SIMG2IMG:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/simg2img}"
LPDUMP="${LPDUMP:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpdump}"
LPUNPACK="${LPUNPACK:-${ROOT_DIR}/third_party/lpunpack_and_lpmake_cmake/bin/lpunpack}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

VARIANT="v0.33-system-b-grow-noop"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
REPORT_PREFIX="verify-v0.33-system-b-grow-noop"

EXPECTED_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
EXPECTED_SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.31-webview-stock-near-noop-exact-current.sparse.img}"
SOURCE_SHA256="${SOURCE_SHA256:-c187b050ced604d3ba52cee0dd36b4a8a17f9a0d1c8b4ae78b0fde0ea44384ae}"
SOURCE_EXTRACT_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/source-v031-slot1"
CANDIDATE_RAW="${WORK_DIR}/candidate-v033-super.raw.img"
CANDIDATE_EXTRACT_DIR="${WORK_DIR}/candidate-v033-slot1"
SOURCE_RAW_FOR_VERIFY="${WORK_DIR}/source-v031-super.raw.img"

SUPER_SIZE=10737418240
SYSTEM_B_NEW_SIZE=3183276032
SYSTEM_B_NEW_SECTORS=6217336
SYSTEM_B_SOURCE_BLOCKS_4K=732632
SYSTEM_B_AVB_ORIGINAL_IMAGE_SIZE=3000860672
SYSTEM_B_AVB_VBMETA_OFFSET=3048407040
SYSTEM_B_AVB_VBMETA_SIZE=896
STOCK_WEBVIEW_SHA256="11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97"
STOCK_BROWSERCHROME_SHA256="0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.33-system-b-grow-noop.sh --offline-image
  tools/r2-verify-v0.33-system-b-grow-noop.sh --read-only

--offline-image verifies the generated v0.33 sparse super:
  - lpdump metadata exposes a grown system_b in slot 1
  - candidate sparse unpacks to the expected grown system_b image
  - all other extracted partition images match the live-verified v0.31 source
  - grown system_b fsck passes and keeps the original ext4 block count
  - AVB footer was moved to the new image tail while vbmeta/hashtree metadata
    still describes the original ext4 data range
  - package APKs and critical system files are byte-identical between source
    system_b and grown system_b

--read-only verifies a flashed device without changing /data. It checks boot,
slot, root, system_b mapper size, /system filesystem size, WebView/BrowserChrome
hashes, WebViewUpdateService, keyguard, and launcher focus.
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

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

manifest_value() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2)}' "$MANIFEST" | sed -n '1p'
}

check_manifest_hash() {
  local label="$1"
  local path="$2"
  local key="$3"
  local expected
  local actual
  expected="$(manifest_value "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

require_hash() {
  local path="$1"
  local expected="$2"
  local actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

debugfs_stat_value() {
  local image="$1"
  local key="$2"
  "$DEBUGFS" -R stats "$image" 2>/dev/null | awk -F: -v k="$key" '$1 == k {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

latest_report_path() {
  local pattern="$1"
  find "$INSPECT_DIR" -maxdepth 1 -type f -name "$pattern" -exec stat -f '%m %N' {} \; 2>/dev/null \
    | sort -rn \
    | sed -n '1s/^[0-9][0-9]* //p'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@"
}

write_report_header() {
  local report="$1"
  {
    echo "# ${VARIANT} verifier"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "serial=${SERIAL}"
    echo "report=${report#${ROOT_DIR}/}"
    echo "boundary=read-only verifier; no flash, no reboot, no settings write, no package mutation, no package-cache clear, no /data cleanup"
    echo
  } > "$report"
}

verify_lpdump_metadata() {
  python3 - "$CANDIDATE_RAW" "$LPDUMP" "$SYSTEM_B_NEW_SECTORS" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

image = Path(sys.argv[1])
lpdump = Path(sys.argv[2])
expected_sectors = int(sys.argv[3])

for slot in ("0", "1"):
    text = subprocess.check_output([str(lpdump), "-s", slot, str(image)], text=True)
    found = False
    current = None
    group = None
    for line in text.splitlines():
        name = re.match(r"\s+Name:\s+(\S+)$", line)
        if name:
            current = name.group(1)
            group = None
            continue
        group_match = re.match(r"\s+Group:\s+(\S+)$", line)
        if group_match:
            group = group_match.group(1)
            continue
        extent = re.match(r"\s+0 \.\. (\d+) linear super (\d+)$", line)
        if extent and current == "system_b":
            sectors = int(extent.group(1)) + 1
            if sectors != expected_sectors:
                raise SystemExit(f"slot{slot} system_b sectors mismatch: {sectors} != {expected_sectors}")
            if group != "qti_dynamic_partitions_b":
                raise SystemExit(f"slot{slot} system_b group mismatch: {group}")
            print(f"slot{slot}\tsystem_b_sectors={sectors}\tstart_sector={extent.group(2)}")
            found = True
            break
    if not found:
        raise SystemExit(f"slot{slot} missing grown system_b extent")
PY
}

prepare_source_extract_if_needed() {
  if [ -f "${SOURCE_EXTRACT_DIR}/system_a.img" ] \
    && [ -f "${SOURCE_EXTRACT_DIR}/system_b.img" ] \
    && [ -f "${SOURCE_EXTRACT_DIR}/product_b.img" ] \
    && [ -f "${SOURCE_EXTRACT_DIR}/vendor_b.img" ]; then
    echo "source_extract=${SOURCE_EXTRACT_DIR}"
    return
  fi

  require_hash "$SOURCE_SPARSE" "$SOURCE_SHA256"
  rm -f "$SOURCE_RAW_FOR_VERIFY"
  rm -rf "$SOURCE_EXTRACT_DIR"
  mkdir -p "$SOURCE_EXTRACT_DIR"
  "$SIMG2IMG" "$SOURCE_SPARSE" "$SOURCE_RAW_FOR_VERIFY"
  [ "$(size_bytes "$SOURCE_RAW_FOR_VERIFY")" -eq "$SUPER_SIZE" ] || die "source raw super size mismatch"
  "$LPUNPACK" --slot=1 "$SOURCE_RAW_FOR_VERIFY" "$SOURCE_EXTRACT_DIR" >/dev/null
  rm -f "$SOURCE_RAW_FOR_VERIFY"
  echo "source_extract=${SOURCE_EXTRACT_DIR}"
}

verify_partition_hashes() {
  local part
  for part in system_a product_a vendor_a odm_a system_ext_b product_b vendor_b odm_b; do
    need_file "${SOURCE_EXTRACT_DIR}/${part}.img"
    need_file "${CANDIDATE_EXTRACT_DIR}/${part}.img"
    source_hash="$(sha256_one "${SOURCE_EXTRACT_DIR}/${part}.img")"
    candidate_hash="$(sha256_one "${CANDIDATE_EXTRACT_DIR}/${part}.img")"
    [ "$source_hash" = "$candidate_hash" ] \
      || die "${part} changed unexpectedly: source=${source_hash} candidate=${candidate_hash}"
    printf '%s\tretained_sha256=%s\n' "$part" "$candidate_hash"
  done

  candidate_system_hash="$(sha256_one "${CANDIDATE_EXTRACT_DIR}/system_b.img")"
  grown_system_hash="$(sha256_one "$EXPECTED_SYSTEM_B_IMG")"
  [ "$candidate_system_hash" = "$grown_system_hash" ] \
    || die "candidate system_b does not match grown system image: ${candidate_system_hash} != ${grown_system_hash}"
  printf 'system_b\tgrown_sha256=%s\n' "$candidate_system_hash"
}

compare_system_files() {
  python3 - "$DEBUGFS" "${SOURCE_EXTRACT_DIR}/system_b.img" "${CANDIDATE_EXTRACT_DIR}/system_b.img" "$ROOT_DIR" "$WORK_DIR/file-compare" <<'PY'
from __future__ import annotations

import csv
import hashlib
import subprocess
import sys
from pathlib import Path

debugfs = Path(sys.argv[1])
source_img = Path(sys.argv[2])
candidate_img = Path(sys.argv[3])
root = Path(sys.argv[4])
out_dir = Path(sys.argv[5])
out_dir.mkdir(parents=True, exist_ok=True)

packages_tsv = root / "reverse/smartisan-8.5.3-rom-static/indexes/packages.tsv"
paths: set[str] = set()
with packages_tsv.open(encoding="utf-8") as fh:
    for row in csv.DictReader(fh, delimiter="\t"):
        if row.get("partition") != "system":
            continue
        rel_path = row.get("rel_path") or ""
        if not rel_path.endswith(".apk"):
            continue
        if rel_path.startswith("system/"):
            rel_path = rel_path[len("system/") :]
        paths.add("/system/" + rel_path)

required = {
    "/system/framework/framework-res.apk",
    "/system/framework/framework.jar",
    "/system/framework/services.jar",
    "/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk",
    "/system/etc/security/otacerts.zip",
}
optional = {
    "/system/bin/kp",
    "/system/etc/permissions/privapp-permissions-platform.xml",
    "/system/etc/sysconfig/hiddenapi-package-whitelist.xml",
}
paths.update(required)
paths.update(optional)

def stat_path(image: Path, path: str) -> bool:
    result = subprocess.run([str(debugfs), "-R", f"stat {path}", str(image)], text=True, capture_output=True)
    text = result.stdout + result.stderr
    return result.returncode == 0 and "File not found" not in text

def sha256_dump(image: Path, path: str, label: str) -> str:
    safe = path.strip("/").replace("/", "__")
    dest = out_dir / f"{label}-{safe}"
    if dest.exists():
        dest.unlink()
    result = subprocess.run([str(debugfs), "-R", f"dump {path} {dest}", str(image)], text=True, capture_output=True)
    if result.returncode != 0 or not dest.exists():
        raise SystemExit(f"dump failed for {path} from {label}: {result.stdout}{result.stderr}")
    return hashlib.sha256(dest.read_bytes()).hexdigest()

checked = 0
absent = 0
for path in sorted(paths):
    src_present = stat_path(source_img, path)
    dst_present = stat_path(candidate_img, path)
    if path in required and not (src_present and dst_present):
        raise SystemExit(f"required file missing after resize: {path} source={src_present} candidate={dst_present}")
    if src_present != dst_present:
        raise SystemExit(f"presence changed for {path}: source={src_present} candidate={dst_present}")
    if not src_present:
        absent += 1
        continue
    src_hash = sha256_dump(source_img, path, "source")
    dst_hash = sha256_dump(candidate_img, path, "candidate")
    if src_hash != dst_hash:
        raise SystemExit(f"content changed for {path}: source={src_hash} candidate={dst_hash}")
    checked += 1

print(f"system_file_compare=PASS checked={checked} absent_in_both={absent}")
PY
}

run_offline_image() {
  mkdir -p "$INSPECT_DIR" "$WORK_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## local files"
    need_file "$MANIFEST"
    check_manifest_hash "candidate_sparse" "$EXPECTED_SPARSE" "sparse_super_sha256"
    check_manifest_hash "grown_system_b" "$EXPECTED_SYSTEM_B_IMG" "system_b_grown_sha256"
    [ "$(size_bytes "$EXPECTED_SYSTEM_B_IMG")" -eq "$SYSTEM_B_NEW_SIZE" ] \
      || die "grown system_b image size mismatch"
    echo

    echo "## candidate raw preparation"
    rm -f "$CANDIDATE_RAW"
    "$SIMG2IMG" "$EXPECTED_SPARSE" "$CANDIDATE_RAW"
    [ "$(size_bytes "$CANDIDATE_RAW")" -eq "$SUPER_SIZE" ] || die "candidate raw super size mismatch"
    echo "candidate_raw=${CANDIDATE_RAW}"
    echo

    echo "## source extract preparation"
    prepare_source_extract_if_needed
    echo

    echo "## lpdump metadata gates"
    verify_lpdump_metadata
    echo

    echo "## grown system_b filesystem and AVB footer gates"
    "$E2FSCK" -fn "$EXPECTED_SYSTEM_B_IMG" >/dev/null
    block_count="$(debugfs_stat_value "$EXPECTED_SYSTEM_B_IMG" "Block count")"
    free_blocks="$(debugfs_stat_value "$EXPECTED_SYSTEM_B_IMG" "Free blocks")"
    [ "$block_count" = "$SYSTEM_B_SOURCE_BLOCKS_4K" ] \
      || die "grown system_b block count changed unexpectedly: ${block_count} != ${SYSTEM_B_SOURCE_BLOCKS_4K}"
    echo "system_b_block_count=${block_count}"
    echo "system_b_free_blocks=${free_blocks}"
    python3 "$AVBTOOL" info_image --image "$EXPECTED_SYSTEM_B_IMG"
    python3 "$AVBTOOL" info_image --image "$EXPECTED_SYSTEM_B_IMG" > "${WORK_DIR}/candidate-system-b-avb-info.txt"
    grep -q "Image size:               ${SYSTEM_B_NEW_SIZE} bytes" "${WORK_DIR}/candidate-system-b-avb-info.txt" \
      || die "candidate system_b AVB image size mismatch"
    grep -q "Original image size:      ${SYSTEM_B_AVB_ORIGINAL_IMAGE_SIZE} bytes" "${WORK_DIR}/candidate-system-b-avb-info.txt" \
      || die "candidate system_b AVB original image size changed unexpectedly"
    grep -q "VBMeta offset:            ${SYSTEM_B_AVB_VBMETA_OFFSET}" "${WORK_DIR}/candidate-system-b-avb-info.txt" \
      || die "candidate system_b AVB vbmeta offset changed unexpectedly"
    grep -q "VBMeta size:              ${SYSTEM_B_AVB_VBMETA_SIZE} bytes" "${WORK_DIR}/candidate-system-b-avb-info.txt" \
      || die "candidate system_b AVB vbmeta size changed unexpectedly"
    echo

    echo "## candidate unpack gates"
    rm -rf "$CANDIDATE_EXTRACT_DIR"
    mkdir -p "$CANDIDATE_EXTRACT_DIR"
    "$LPUNPACK" --slot=1 "$CANDIDATE_RAW" "$CANDIDATE_EXTRACT_DIR" >/dev/null
    verify_partition_hashes
    echo

    echo "## no-content system_b file comparison"
    compare_system_files
    echo

    echo "result=PASS_OFFLINE_IMAGE"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

run_read_only() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/${REPORT_PREFIX}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  write_report_header "$report"

  {
    echo "## adb"
    adb devices -l
    adb_available || die "adb device ${SERIAL} is not online"
    echo

    echo "## boot state"
    adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)"'
    [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] || die "device has not completed boot"
    [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] || die "device is not on B slot"
    echo

    echo "## root status"
    "$ROOT_HELPER" status
    echo

    echo "## system_b size gates"
    mapper_size="$(root_cmd 'blockdev --getsize64 /dev/block/mapper/system_b 2>/dev/null || true' | tr -d '\r' | tail -n 1)"
    [ "$mapper_size" = "$SYSTEM_B_NEW_SIZE" ] || die "system_b mapper size mismatch: ${mapper_size} != ${SYSTEM_B_NEW_SIZE}"
    echo "system_b_mapper_size=${mapper_size}"
    df_line="$(adb_shell 'df -k /system | tail -n 1')"
    echo "$df_line"
    echo "note=/system df is expected to remain at the original ext4 size in v0.33; this gate tests dynamic partition and AVB footer growth only"
    echo

    echo "## package/content read-only hashes"
    hash_output="$(adb_shell 'sha256sum /product/app/webview/webview.apk /system/app/BrowserChrome/BrowserChrome.apk /system/etc/security/otacerts.zip /system/framework/framework-res.apk 2>/dev/null')"
    echo "$hash_output"
    grep -q "^${STOCK_WEBVIEW_SHA256}  /product/app/webview/webview.apk" <<<"$hash_output" \
      || die "live WebView hash mismatch"
    grep -q "^${STOCK_BROWSERCHROME_SHA256}  /system/app/BrowserChrome/BrowserChrome.apk" <<<"$hash_output" \
      || die "live BrowserChrome hash mismatch"
    echo

    echo "## WebViewUpdateService"
    adb_shell 'cmd webviewupdate get-current-webview-package || true'
    adb_shell 'dumpsys webviewupdate | sed -n "1,80p"'
    echo

    echo "## window state"
    adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head -n 20"
    echo

    echo "result=PASS_READ_ONLY"
  } 2>&1 | tee -a "$report"

  echo "report=${report}"
}

case "${1:-}" in
  --offline-image)
    need_executable "$SIMG2IMG"
    need_executable "$LPDUMP"
    need_executable "$LPUNPACK"
    need_executable "$E2FSCK"
    need_executable "$DEBUGFS"
    need_file "$AVBTOOL"
    run_offline_image
    ;;
  --read-only)
    run_read_only
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
