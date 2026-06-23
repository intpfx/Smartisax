#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"

INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/v0.26a-launcher-entry-hide}"
EXPECTED_SUPER="${EXPECTED_SUPER:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26a-launcher-entry-hide-exact-current.sparse.img}"
EXPECTED_SYSTEM_IMG="${EXPECTED_SYSTEM_IMG:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.26a-launcher-entry-hide.img}"
SOURCE_V0111="${SOURCE_V0111:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img}"
V0111_REPORT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.11.1-native-darkmode-settings-row"
VERIFY_LABEL="${VERIFY_LABEL:-v0.26a launcher-entry-hide}"
REPORT_PREFIX="${REPORT_PREFIX:-verify-v0.26a-launcher-entry-hide}"
HELD_TAG="${HELD_TAG:-v026a}"
EXPECTED_APK_SIG_BLOCK="${EXPECTED_APK_SIG_BLOCK:-absent}"
EXPECTED_PACKAGE_DIR_MTIME_HEX="${EXPECTED_PACKAGE_DIR_MTIME_HEX:-}"
REQUIRE_UNLOCKED_LAUNCHER="${REQUIRE_UNLOCKED_LAUNCHER:-0}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

VIDEO_STOCK_APK="${RAW}/system/system/priv-app/VideoPlayer/VideoPlayer.apk"
SCREENREC_STOCK_APK="${RAW}/system/system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk"
QUICKSEARCH_STOCK_APK="${RAW}/system/system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk"

VIDEO_APK="${VIDEO_APK:-${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.videoplayerproject-launcher-hidden.apk}"
SCREENREC_APK="${SCREENREC_APK:-${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.screenrecorder-launcher-hidden.apk}"
QUICKSEARCH_APK="${QUICKSEARCH_APK:-${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.quicksearch-launcher-hidden.apk}"
APK_MANIFEST="${ROOT_DIR}/hard-rom/build/apk/launcher-entry-hide-apk-manifest.tsv"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.26a-launcher-entry-hide.sh --offline-image
  tools/r2-verify-v0.26a-launcher-entry-hide.sh --read-only

--offline-image verifies the generated v0.26a sparse super:
  - the image contains the three launcher-hidden APKs
  - each APK changes only AndroidManifest.xml as the audited launcher-only diff
  - signature reports stop at the expected AndroidManifest.xml digest boundary
  - held-stock hidden paths exist for shared_blocks safety
  - sparse system_b matches the generated system image
  - system_ext_b remains byte-identical to the live-verified v0.11.1 source

--read-only verifies a flashed device without changing /data.

The script never flashes, reboots, erases misc, or changes /data.
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

latest_report() {
  local dir="$1"
  local pattern="$2"
  find "$dir" -maxdepth 1 -type f -name "$pattern" -exec stat -f '%m %N' {} \; 2>/dev/null \
    | sort -rn \
    | sed -n '1s/^[0-9][0-9]* //p'
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

dump_one() {
  local image="$1"
  local src_path="$2"
  local out="$3"
  "$DEBUGFS" -R "dump ${src_path} ${out}" "$image" >/dev/null 2>&1
  need_file "$out"
}

compare_file_hash() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local actual_hash
  local expected_hash
  actual_hash="$(sha256_one "$actual")"
  expected_hash="$(sha256_one "$expected")"
  [ "$actual_hash" = "$expected_hash" ] \
    || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$actual"
}

verify_held_path() {
  local image="$1"
  local path="$2"
  debugfs_path_exists "$image" "$path" || die "missing held-stock path: ${path}"
  echo "held_stock_path=${path}"
}

verify_package_dir_mtime() {
  local image="$1"
  local path="$2"
  local output
  [ -n "$EXPECTED_PACKAGE_DIR_MTIME_HEX" ] || return 0
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1)"
  grep -q "Type: directory" <<<"$output" || die "expected package directory: ${path}"
  grep -q "mtime: ${EXPECTED_PACKAGE_DIR_MTIME_HEX}:" <<<"$output" \
    || die "package directory mtime mismatch for ${path}; expected ${EXPECTED_PACKAGE_DIR_MTIME_HEX}"
  echo "package_dir_mtime=ok path=${path} mtime=${EXPECTED_PACKAGE_DIR_MTIME_HEX}"
}

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

verify_sig_boundary() {
  local apk="$1"
  local report="$2"
  "$SIGCHECK" "$apk" > "$report"
  grep -q "^apk_sig_block_magic=${EXPECTED_APK_SIG_BLOCK}$" "$report" \
    || die "expected APK signing block state ${EXPECTED_APK_SIG_BLOCK} for ${apk}"
  grep -q '^keytool_status=1$' "$report" \
    || die "expected keytool digest-boundary status for ${apk}"
  grep -q 'SHA-256 digest error for AndroidManifest.xml' "$report" \
    || die "signature report missing AndroidManifest.xml digest boundary for ${apk}"
  sed -n '1,18p' "$report"
}

verify_apk_manifest_scope() {
  local stock_apk="$1"
  local output_apk="$2"
  local package_name="$3"
  local component="$4"
  local filter_index="$5"
  local check_dir="$6"

  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  unzip -t "$output_apk" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/stock" "$stock_apk" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/out" "$output_apk" >/dev/null

  python3 - "$stock_apk" "$output_apk" "$package_name" "$component" "$filter_index" \
    "${check_dir}/stock/AndroidManifest.xml" "${check_dir}/out/AndroidManifest.xml" <<'PY'
from __future__ import annotations

import copy
import hashlib
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

stock_apk, output_apk, package_name, component, filter_index_s, stock_xml, out_xml = sys.argv[1:]
filter_index = int(filter_index_s)
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def full_component(raw: str) -> str:
    if raw.startswith("."):
        return package_name + raw
    if "." not in raw:
        return package_name + "." + raw
    return raw


def values(parent: ET.Element, tag_name: str) -> set[str]:
    return {
        child.attrib.get(NAME, "")
        for child in parent
        if local(child.tag) == tag_name and child.attrib.get(NAME)
    }


def strip_blank_text(node: ET.Element) -> None:
    if node.text is not None and not node.text.strip():
        node.text = None
    if node.tail is not None and not node.tail.strip():
        node.tail = None
    for child in list(node):
        strip_blank_text(child)


def target_filter(root: ET.Element) -> ET.Element:
    application = next((child for child in root if local(child.tag) == "application"), None)
    if application is None:
        raise SystemExit("manifest has no application")
    matches = [
        child
        for child in application
        if local(child.tag) in {"activity", "activity-alias"}
        and full_component(child.attrib.get(NAME, "")) == component
    ]
    if len(matches) != 1:
        raise SystemExit(f"expected one component {component}, found {len(matches)}")
    filters = [child for child in matches[0] if local(child.tag) == "intent-filter"]
    if filter_index < 1 or filter_index > len(filters):
        raise SystemExit(f"filter index {filter_index} out of range for {component}")
    return filters[filter_index - 1]


def remove_expected_launcher(root: ET.Element) -> None:
    target = target_filter(root)
    actions = values(target, "action")
    categories = values(target, "category")
    if "android.intent.action.MAIN" not in actions:
        raise SystemExit("stock target filter is not MAIN")
    if "android.intent.category.LAUNCHER" not in categories:
        raise SystemExit("stock target filter lacks LAUNCHER")
    removed = 0
    for child in list(target):
        if local(child.tag) == "category" and child.attrib.get(NAME) == "android.intent.category.LAUNCHER":
            target.remove(child)
            removed += 1
    if removed != 1:
        raise SystemExit(f"expected to remove one LAUNCHER category, removed {removed}")


def canonical_root(path: str) -> bytes:
    root = ET.parse(path).getroot()
    strip_blank_text(root)
    return ET.canonicalize(ET.tostring(root, encoding="unicode")).encode()


def canonical_expected(path: str) -> bytes:
    root = ET.parse(path).getroot()
    if root.attrib.get("package") != package_name:
        raise SystemExit("package mismatch in stock decoded manifest")
    expected = copy.deepcopy(root)
    remove_expected_launcher(expected)
    strip_blank_text(expected)
    return ET.canonicalize(ET.tostring(expected, encoding="unicode")).encode()


with zipfile.ZipFile(stock_apk) as zs, zipfile.ZipFile(output_apk) as zo:
    stock_infos = zs.infolist()
    out_infos = zo.infolist()
    stock_names = [info.filename for info in stock_infos]
    out_names = [info.filename for info in out_infos]
    if stock_names != out_names:
        raise SystemExit("zip entry order/names changed")
    for name in stock_names:
        sdata = zs.read(name)
        odata = zo.read(name)
        if name == "AndroidManifest.xml":
            if sha256(sdata) == sha256(odata):
                raise SystemExit("AndroidManifest.xml did not change")
            continue
        if sha256(sdata) != sha256(odata):
            raise SystemExit(f"unexpected zip member content change: {name}")
    stock_by_name = {info.filename: info for info in stock_infos}
    out_by_name = {info.filename: info for info in out_infos}
    for name in stock_names:
        sinfo = stock_by_name[name]
        oinfo = out_by_name[name]
        if sinfo.compress_type != oinfo.compress_type:
            raise SystemExit(f"compression method changed: {name}")
        if name.endswith(".so"):
            if sinfo.header_offset != oinfo.header_offset:
                raise SystemExit(f"native library local-header offset changed: {name}")
            if sinfo.extra != oinfo.extra:
                raise SystemExit(f"native library extra field changed: {name}")

expected = canonical_expected(stock_xml)
actual = canonical_root(out_xml)
if expected != actual:
    Path("/tmp/r2-v026a-expected.xml").write_bytes(expected)
    Path("/tmp/r2-v026a-actual.xml").write_bytes(actual)
    raise SystemExit("decoded manifest differs from expected launcher-only change")

out_root = ET.parse(out_xml).getroot()
if out_root.attrib.get("package") != package_name:
    raise SystemExit("package mismatch in output decoded manifest")
target = target_filter(out_root)
if "android.intent.action.MAIN" not in values(target, "action"):
    raise SystemExit("target filter lost MAIN")
if "android.intent.category.LAUNCHER" in values(target, "category"):
    raise SystemExit("target filter still resolves as LAUNCHER")

print(f"manifest_only_change=ok package={package_name} component={component} filter={filter_index}")
print("zip_member_content_scope=AndroidManifest.xml_only")
print("native_lib_offsets=ok")
print("main_launcher_removed=ok")
PY
}

verify_apk_manifest_tsv() {
  need_file "$APK_MANIFEST"
  grep -Fq $'视频播放器\tcom.smartisanos.videoplayerproject\tcom.smartisanos.videoplayerproject.MainActivity\t1' "$APK_MANIFEST" \
    || die "APK manifest is missing VideoPlayer v0.26a row"
  grep -Fq $'屏幕录制\tcom.smartisanos.screenrecorder\tcom.smartisanos.screenrecorder.EmptyActivity\t1' "$APK_MANIFEST" \
    || die "APK manifest is missing ScreenRecorder v0.26a row"
  grep -Fq $'搜索\tcom.smartisanos.quicksearch\tcom.android.quicksearchbox.SearchActivity\t2' "$APK_MANIFEST" \
    || die "APK manifest is missing QuickSearch v0.26a row"
  echo "apk_manifest_rows=ok"
}

dump_and_verify_system_image() {
  local image="$1"
  local dump_dir="$2"

  dump_one "$image" "/system/priv-app/VideoPlayer/VideoPlayer.apk" "${dump_dir}/VideoPlayer.apk"
  dump_one "$image" "/system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk" "${dump_dir}/ScreenRecorderSmartisan.apk"
  dump_one "$image" "/system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk" "${dump_dir}/QuickSearchBoxSmartisan.apk"

  compare_file_hash "${dump_dir}/VideoPlayer.apk" "$VIDEO_APK" "system/VideoPlayer.apk"
  compare_file_hash "${dump_dir}/ScreenRecorderSmartisan.apk" "$SCREENREC_APK" "system/ScreenRecorderSmartisan.apk"
  compare_file_hash "${dump_dir}/QuickSearchBoxSmartisan.apk" "$QUICKSEARCH_APK" "system/QuickSearchBoxSmartisan.apk"
  echo "zip_integrity=ok"
  echo

  echo "## manifest-only APK scopes from system_b"
  verify_apk_manifest_scope "$VIDEO_STOCK_APK" "${dump_dir}/VideoPlayer.apk" \
    "com.smartisanos.videoplayerproject" "com.smartisanos.videoplayerproject.MainActivity" "1" \
    "${dump_dir}/check-VideoPlayer"
  verify_apk_manifest_scope "$SCREENREC_STOCK_APK" "${dump_dir}/ScreenRecorderSmartisan.apk" \
    "com.smartisanos.screenrecorder" "com.smartisanos.screenrecorder.EmptyActivity" "1" \
    "${dump_dir}/check-ScreenRecorderSmartisan"
  verify_apk_manifest_scope "$QUICKSEARCH_STOCK_APK" "${dump_dir}/QuickSearchBoxSmartisan.apk" \
    "com.smartisanos.quicksearch" "com.android.quicksearchbox.SearchActivity" "2" \
    "${dump_dir}/check-QuickSearchBoxSmartisan"
  echo

  echo "## signature boundaries from system_b"
  verify_sig_boundary "${dump_dir}/VideoPlayer.apk" "${dump_dir}/VideoPlayer.signature.txt"
  echo
  verify_sig_boundary "${dump_dir}/ScreenRecorderSmartisan.apk" "${dump_dir}/ScreenRecorderSmartisan.signature.txt"
  echo
  verify_sig_boundary "${dump_dir}/QuickSearchBoxSmartisan.apk" "${dump_dir}/QuickSearchBoxSmartisan.signature.txt"
  echo

  echo "## held-stock paths"
  verify_held_path "$image" "/system/priv-app/VideoPlayer/.VideoPlayer.apk.smartisax-${HELD_TAG}-stock-held"
  verify_held_path "$image" "/system/priv-app/ScreenRecorderSmartisan/.ScreenRecorderSmartisan.apk.smartisax-${HELD_TAG}-stock-held"
  verify_held_path "$image" "/system/app/QuickSearchBoxSmartisan/.QuickSearchBoxSmartisan.apk.smartisax-${HELD_TAG}-stock-held"

  if [ -n "$EXPECTED_PACKAGE_DIR_MTIME_HEX" ]; then
    echo
    echo "## package directory mtimes"
    verify_package_dir_mtime "$image" "/system/priv-app/VideoPlayer"
    verify_package_dir_mtime "$image" "/system/priv-app/ScreenRecorderSmartisan"
    verify_package_dir_mtime "$image" "/system/app/QuickSearchBoxSmartisan"
  fi
}

verify_retained_system_ext() {
  local dump_dir="$1"
  local source_system_ext="${dump_dir}/system_ext_b-from-v0.11.1.img"
  local output_system_ext="${dump_dir}/system_ext_b-from-output.img"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V0111" \
    --extract-image "system_ext_b=${source_system_ext}" >/dev/null
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" \
    --extract-image "system_ext_b=${output_system_ext}" >/dev/null

  local source_hash
  local output_hash
  source_hash="$(sha256_one "$source_system_ext")"
  output_hash="$(sha256_one "$output_system_ext")"
  [ "$source_hash" = "$output_hash" ] \
    || die "system_ext_b retention mismatch: source=${source_hash} output=${output_hash}"
  printf 'system_ext_b\tsource=%s\toutput=%s\n' "$source_hash" "$output_hash"
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_ext_b=${output_system_ext}"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_executable "$SIGCHECK"
  need_executable "$JAVA_BIN"
  need_file "$APKTOOL"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$SOURCE_V0111"
  need_file "$FW_ANDROID"
  need_file "$FW_SMARTISAN"
  need_file "$VIDEO_STOCK_APK"
  need_file "$SCREENREC_STOCK_APK"
  need_file "$QUICKSEARCH_STOCK_APK"
  need_file "$VIDEO_APK"
  need_file "$SCREENREC_APK"
  need_file "$QUICKSEARCH_APK"
  mkdir -p "$INSPECT_DIR"

  local v0111_report
  v0111_report="$(latest_report "$V0111_REPORT_DIR" "verify-v0.11.1-native-darkmode-settings-row-device-*.txt")"
  [ -n "$v0111_report" ] || die "missing v0.11.1 device PASS report"
  grep -Fq "PASS: v0.11.1 native dark-mode settings-row device read-only verification" "$v0111_report" \
    || die "latest v0.11.1 device report is not PASS: ${v0111_report}"

  local timestamp
  local report
  local dump_dir
  timestamp="$(date +%Y%m%d-%H%M%S)"
  report="${INSPECT_DIR}/${REPORT_PREFIX}-offline-image-${timestamp}.txt"
  dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  FRAMEWORK_DIR="${dump_dir}/apktool-framework"
  mkdir -p "$dump_dir" "$FRAMEWORK_DIR"
  install_frameworks

  {
    echo "# ${VERIFY_LABEL} ROM offline verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo "source_v0.11.1=${SOURCE_V0111}"
    echo "source_v0.11.1_device_report=${v0111_report}"
    echo

    echo "## APK manifest"
    verify_apk_manifest_tsv
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo

    echo "## retained system_ext_b"
    verify_retained_system_ext "$dump_dir"
    echo

    echo "## sparse slices"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" "$SOURCE_V0111" \
      "$VIDEO_APK" "$SCREENREC_APK" "$QUICKSEARCH_APK" \
      "$VIDEO_STOCK_APK" "$SCREENREC_STOCK_APK" "$QUICKSEARCH_STOCK_APK"
    echo
    echo "result=PASS"
    echo "PASS: ${VERIFY_LABEL} offline image verification"
  } | tee "$report"

  echo "Report: ${report}"
}

LIVE_FAILURES=0

note_live_failure() {
  echo "FAIL: $*"
  LIVE_FAILURES=$((LIVE_FAILURES + 1))
}

verify_live_apk() {
  local label="$1"
  local package="$2"
  local expected_apk="$3"
  local expected_hash
  local pm_paths
  local device_path
  local actual_hash
  local shadow

  expected_hash="$(sha256_one "$expected_apk")"
  pm_paths="$(adb_shell "pm path ${package} 2>/dev/null || true")"
  device_path="$(printf '%s\n' "$pm_paths" | sed -n '1s/^package://p')"
  shadow="no"

  if [ -z "$device_path" ]; then
    note_live_failure "${label}: package path missing for ${package}"
    printf '%s\tpackage=%s\tpath=MISSING\texpected=%s\tactual=MISSING\tshadow=unknown\n' \
      "$label" "$package" "$expected_hash"
    return
  fi

  case "$pm_paths" in
    *"/data/app/"*) shadow="yes" ;;
  esac
  if [ "$shadow" = "yes" ]; then
    note_live_failure "${label}: updated-system /data/app shadow present"
  fi

  actual_hash="$(adb_shell "sha256sum '${device_path}' 2>/dev/null || true" | awk 'NR == 1 {print $1}')"
  if [ -z "$actual_hash" ]; then
    note_live_failure "${label}: could not hash ${device_path}"
    actual_hash="MISSING"
  elif [ "$actual_hash" != "$expected_hash" ]; then
    note_live_failure "${label}: hash mismatch actual=${actual_hash} expected=${expected_hash}"
  fi

  printf '%s\tpackage=%s\tpath=%s\texpected=%s\tactual=%s\tshadow=%s\n' \
    "$label" "$package" "$device_path" "$expected_hash" "$actual_hash" "$shadow"
}

check_launcher_absent() {
  local label="$1"
  local package="$2"
  local activity="$3"
  local launcher_query="$4"
  if printf '%s\n' "$launcher_query" | grep -F "$package" | grep -Fq "$activity"; then
    note_live_failure "${label}: launcher entry still resolves for ${package}/${activity}"
  else
    printf '%s\tlauncher_absent=ok\tcomponent=%s/%s\n' "$label" "$package" "$activity"
  fi
}

run_read_only() {
  need_file "$VIDEO_APK"
  need_file "$SCREENREC_APK"
  need_file "$QUICKSEARCH_APK"
  need_executable "$ROOT_HELPER"
  adb_available || {
    adb devices -l >&2 || true
    die "adb device ${SERIAL} is not online"
  }
  mkdir -p "$INSPECT_DIR"

  local timestamp
  local report
  local launcher_query
  timestamp="$(date +%Y%m%d-%H%M%S)"
  report="${INSPECT_DIR}/${REPORT_PREFIX}-device-${timestamp}.txt"
  exec > >(tee "$report") 2>&1

  echo "# ${VERIFY_LABEL} device read-only verification"
  echo "timestamp=${timestamp}"
  echo "serial=${SERIAL}"
  echo "boundary=read-only; no reboot, no flash, no settings write, no package mutation, no /data cleanup"
  echo

  echo "## device state"
  adb devices -l
  adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)";
printf "ro.build.fingerprint=%s\n" "$(getprop ro.build.fingerprint)"'
  "$ROOT_HELPER" cmd 'id; getenforce; getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate'
  echo

  echo "## boot gates"
  [ "$(adb_shell 'getprop sys.boot_completed' | tail -n 1)" = "1" ] \
    || note_live_failure "sys.boot_completed is not 1"
  [ "$(adb_shell 'getprop ro.boot.slot_suffix' | tail -n 1)" = "_b" ] \
    || note_live_failure "slot is not _b"
  [ "$(adb_shell 'getprop init.svc.bootanim' | tail -n 1)" = "stopped" ] \
    || note_live_failure "bootanim is not stopped"
  echo

  echo "## package hashes"
  verify_live_apk "system/VideoPlayer.apk" "com.smartisanos.videoplayerproject" "$VIDEO_APK"
  verify_live_apk "system/ScreenRecorderSmartisan.apk" "com.smartisanos.screenrecorder" "$SCREENREC_APK"
  verify_live_apk "system/QuickSearchBoxSmartisan.apk" "com.smartisanos.quicksearch" "$QUICKSEARCH_APK"
  echo

  echo "## launcher query"
  if [ "$REQUIRE_UNLOCKED_LAUNCHER" = "1" ]; then
    local user_state
    local window_state
    user_state="$(adb_shell 'dumpsys user | grep -m1 "State:" || true')"
    window_state="$(adb_shell 'dumpsys window | grep -E "isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,8p" || true')"
    printf '%s\n%s\n' "$user_state" "$window_state"
    grep -q 'RUNNING_UNLOCKED' <<<"$user_state" \
      || note_live_failure "user 0 is not RUNNING_UNLOCKED; unlock device and rerun verifier"
    grep -q 'isKeyguardShowing=false' <<<"$window_state" \
      || note_live_failure "keyguard is still showing; unlock device and rerun verifier"
  fi
  launcher_query="$(adb_shell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null || true')"
  printf '%s\n' "$launcher_query" | sed -n '1,120p'
  check_launcher_absent "VideoPlayer" "com.smartisanos.videoplayerproject" \
    "com.smartisanos.videoplayerproject.MainActivity" "$launcher_query"
  check_launcher_absent "ScreenRecorderSmartisan" "com.smartisanos.screenrecorder" \
    "com.smartisanos.screenrecorder.EmptyActivity" "$launcher_query"
  check_launcher_absent "QuickSearchBoxSmartisan" "com.smartisanos.quicksearch" \
    "com.android.quicksearchbox.SearchActivity" "$launcher_query"
  echo

  echo "## package feature surface spot checks"
  adb_shell 'dumpsys package com.smartisanos.videoplayerproject | grep -E "MainActivity|VideoProvider|android.intent.action.VIEW" | sed -n "1,80p"' || true
  adb_shell 'dumpsys package com.smartisanos.screenrecorder | grep -E "ScreenRecorderService|ScreenshotToolService|EmptyActivity" | sed -n "1,80p"' || true
  adb_shell 'dumpsys package com.smartisanos.quicksearch | grep -E "GLOBAL_SEARCH|android.intent.action.SEARCH|SearchActivity|SuggestionProvider" | sed -n "1,80p"' || true
  echo

  echo "## window state"
  adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,40p"' || true
  echo

  if [ "$LIVE_FAILURES" -eq 0 ]; then
    echo "result=PASS"
    echo "PASS: ${VERIFY_LABEL} device read-only verification"
  else
    echo "result=FAIL"
    echo "failure_count=${LIVE_FAILURES}"
    echo "Report: ${report}"
    exit 1
  fi
  echo "Report: ${report}"
}

case "${1:---offline-image}" in
  --offline-image)
    run_offline_image
    ;;
  --read-only)
    run_read_only
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
