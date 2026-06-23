#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"

VARIANT="v0.29-sidebar-topbar-hide"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
REPORT_PREFIX="verify-v0.29-sidebar-topbar-hide"
EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
SOURCE_V028="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img"
MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}-exact-current.SHA256SUMS.txt"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"

BASE_RAW_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.sidebar-launcher-hidden.apk"
SIDEBAR_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.sidebar-topbar-hidden-v2cert.apk"
SIDEBAR_RAW_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.sidebar-topbar-hidden.apk"
SIDEBAR_APK_MANIFEST="${ROOT_DIR}/hard-rom/build/apk/sidebar-topbar-hide-apk-manifest.tsv"
LAYOUT_MEMBER="res/layout/top_area_title_view.xml"
SIDEBAR_DIR_MTIME="0x6a3407f0"

removed_paths=(
  "/system/priv-app/CloudServiceSmartisan"
  "/system/priv-app/CloudServiceShare"
  "/system/priv-app/CloudSyncAgent"
  "/system/priv-app/WalletSmartisan"
  "/system/app/HandShaker"
)

target_absent_packages=(
  "com.smartisanos.cloudsync"
  "com.smartisanos.cloudsyncshare"
  "com.smartisanos.cloudagent"
  "com.smartisanos.wallet"
  "com.smartisanos.smartfolder.aoa"
)

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.29-sidebar-topbar-hide.sh --offline-image
  tools/r2-verify-v0.29-sidebar-topbar-hide.sh --read-only

--offline-image verifies the generated v0.29 sparse super:
  - only system_b is changed relative to v0.28
  - Sidebar.apk inside system_b matches the topbar-hidden APK
  - Sidebar's launcher-hidden manifest remains intact
  - only classes.dex and res/layout/top_area_title_view.xml changed from the
    v0.26c Sidebar launcher-hidden shell
  - the topbar layout root stays reserved for future features, but the stock
    controls and One Step text are deleted
  - TopAreaContentView no longer binds or touches the removed stock topbar IDs
  - the APK Sig Block 42 certificate carrier is present
  - Sidebar package directory mtime is bumped for PackageCacher

--read-only verifies a flashed device without changing /data. Visual removal
of the One Step top bar still needs a live screenshot/user check after opening
One Step.
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
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

install_frameworks() {
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

verify_package_dir_mtime() {
  local image="$1"
  local path="$2"
  local expected="$3"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1)"
  grep -q "Type: directory" <<<"$output" || die "expected package directory: ${path}"
  grep -q "mtime: ${expected}:" <<<"$output" \
    || die "package directory mtime mismatch for ${path}; expected ${expected}"
  echo "package_dir_mtime=ok path=${path} mtime=${expected}"
}

verify_sig_boundary() {
  local apk="$1"
  local report="$2"
  "$SIGCHECK" "$apk" > "$report"
  grep -q '^apk_sig_block_magic=present$' "$report" \
    || die "expected APK signing block state present for ${apk}"
  grep -q '^keytool_status=1$' "$report" \
    || die "expected keytool digest-boundary status for ${apk}"
  sed -n '1,22p' "$report"
}

verify_zip_scope() {
  local base_apk="$1"
  local out_apk="$2"
  python3 - "$base_apk" "$out_apk" "$LAYOUT_MEMBER" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile

base, out, expected = sys.argv[1:]

def members(path: str) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as zf:
        return {info.filename: zf.read(info.filename) for info in zf.infolist() if not info.is_dir()}

base_members = members(base)
out_members = members(out)
if set(base_members) != set(out_members):
    missing = sorted(set(base_members) - set(out_members))
    extra = sorted(set(out_members) - set(base_members))
    raise SystemExit(f"member set changed missing={missing[:10]} extra={extra[:10]}")
changed = sorted(
    name for name in base_members
    if hashlib.sha256(base_members[name]).digest() != hashlib.sha256(out_members[name]).digest()
)
expected_changed = {expected, "classes.dex"}
if set(changed) != expected_changed:
    raise SystemExit(f"unexpected changed APK members: {changed}")
print(f"apk_changed_members={','.join(changed)}")
print(f"base_member_sha256={hashlib.sha256(base_members[expected]).hexdigest()}")
print(f"out_member_sha256={hashlib.sha256(out_members[expected]).hexdigest()}")
print(f"base_classes_sha256={hashlib.sha256(base_members['classes.dex']).hexdigest()}")
print(f"out_classes_sha256={hashlib.sha256(out_members['classes.dex']).hexdigest()}")
PY
}

verify_decoded_sidebar_apk() {
  local apk="$1"
  local check_dir="$2"
  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/decoded" "$apk" >/dev/null
  python3 - "${check_dir}/decoded/AndroidManifest.xml" "${check_dir}/decoded/${LAYOUT_MEMBER}" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

manifest_path = Path(sys.argv[1])
layout_path = Path(sys.argv[2])
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
ATTR = lambda name: f"{{{ANDROID_NS}}}{name}"

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]

def full_component(package_name: str, raw: str) -> str:
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

manifest = ET.parse(manifest_path).getroot()
package_name = manifest.attrib.get("package")
if package_name != "com.smartisanos.sidebar":
    raise SystemExit(f"package mismatch: {package_name}")
application = next((child for child in manifest if local(child.tag) == "application"), None)
if application is None:
    raise SystemExit("manifest has no application")
matches = [
    child for child in application
    if local(child.tag) in {"activity", "activity-alias"}
    and full_component(package_name, child.attrib.get(NAME, "")) == "com.smartisanos.sidebar.setting.SettingActivity"
]
if len(matches) != 1:
    raise SystemExit(f"SettingActivity match count={len(matches)}")
main_filters = [
    child for child in matches[0]
    if local(child.tag) == "intent-filter" and "android.intent.action.MAIN" in values(child, "action")
]
if not main_filters:
    raise SystemExit("SettingActivity MAIN filter missing")
if any("android.intent.category.LAUNCHER" in values(f, "category") for f in main_filters):
    raise SystemExit("SettingActivity still has LAUNCHER category")

layout = ET.parse(layout_path).getroot()
if layout.attrib.get(ATTR("layout_height")) != "match_parent":
    raise SystemExit("topbar reserved slot height is not preserved as match_parent")
if layout.attrib.get(ATTR("background")) != "@drawable/sidebar_topview_top_bg":
    raise SystemExit("topbar reserved slot background is not preserved")
children = list(layout)
if children:
    raise SystemExit(f"topbar layout still has child controls: {len(children)}")

print("manifest_launcher_hidden=ok")
print("topbar_slot_preserved=ok")
print("topbar_children_deleted=ok")
PY

  local top_smali="${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/TopAreaContentView.smali"
  local holder_smali="${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/TopAreaContentViewHolder.smali"
  [ -f "$top_smali" ] || die "decoded TopAreaContentView.smali missing"
  [ -f "$holder_smali" ] || die "decoded TopAreaContentViewHolder.smali missing"
  if grep -Eq 'new-instance .*TopAreaContentViewHolder|getHolderBySidebarMode|0x7f070092|0x7f07010f|0x7f070110|0x7f070112|0x7f070113' "$top_smali"; then
    die "TopAreaContentView.smali still references removed stock topbar views"
  fi
  if grep -Eq 'findViewById|UIHandler;->post|0x7f07010f|0x7f070110|0x7f070112|0x7f070113' "$holder_smali"; then
    die "TopAreaContentViewHolder.smali still binds removed stock topbar views"
  fi
  echo "topbar_smali_references_removed=ok"
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

latest_report_path() {
  local suffix="$1"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$INSPECT_DIR"
  printf '%s/%s-%s-%s.txt\n' "$INSPECT_DIR" "$REPORT_PREFIX" "$suffix" "$ts"
}

run_offline() {
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$SOURCE_V028"
  need_file "$MANIFEST"
  need_file "$BASE_RAW_APK"
  need_file "$SIDEBAR_APK"
  need_file "$SIDEBAR_RAW_APK"
  need_file "$SIDEBAR_APK_MANIFEST"
  need_executable "$DEBUGFS"
  need_executable "$E2FSCK"
  need_executable "$SPARSE_TOOL"
  need_executable "$SIGCHECK"
  need_file "$JAVA_BIN"
  need_file "$APKTOOL"

  mkdir -p "$WORK_DIR"
  rm -f "${WORK_DIR}"/*.img "${WORK_DIR}"/*.apk "${WORK_DIR}"/*.txt

  echo "# ${VARIANT} offline verification"
  date -u +"verified_at=%Y-%m-%dT%H:%M:%SZ"
  echo

  check_manifest_hash "sparse_super" "$EXPECTED_SUPER" "sparse_super_sha256"
  check_manifest_hash "system_b_image" "$EXPECTED_SYSTEM_IMG" "system_b_sha256"
  check_manifest_hash "sidebar_topbar_hidden_v2cert_apk" "$SIDEBAR_APK" "sidebar_topbar_hidden_v2cert_sha256"
  echo

  echo "## ext4 fsck"
  "$E2FSCK" -fn "$EXPECTED_SYSTEM_IMG" >/dev/null
  echo "system_b_fsck=ok"
  echo

  echo "## sparse system_b slice"
  local extracted_system="${WORK_DIR}/system_b-from-v0.29-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "system_b=${extracted_system}" >/dev/null
  local expected_system_hash
  local extracted_system_hash
  expected_system_hash="$(sha256_one "$EXPECTED_SYSTEM_IMG")"
  extracted_system_hash="$(sha256_one "$extracted_system")"
  [ "$expected_system_hash" = "$extracted_system_hash" ] \
    || die "system_b sparse slice mismatch: ${extracted_system_hash} != ${expected_system_hash}"
  printf 'system_b\timage=%s\tsparse_slice=%s\n' "$expected_system_hash" "$extracted_system_hash"
  echo

  echo "## retained system_ext_b slice"
  local source_system_ext="${WORK_DIR}/system_ext_b-from-v0.28-source.img"
  local out_system_ext="${WORK_DIR}/system_ext_b-from-v0.29-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V028" --extract-image "system_ext_b=${source_system_ext}" >/dev/null
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "system_ext_b=${out_system_ext}" >/dev/null
  local source_system_ext_hash
  local out_system_ext_hash
  source_system_ext_hash="$(sha256_one "$source_system_ext")"
  out_system_ext_hash="$(sha256_one "$out_system_ext")"
  [ "$source_system_ext_hash" = "$out_system_ext_hash" ] \
    || die "system_ext_b changed unexpectedly"
  printf 'system_ext_b\tsource=%s\tout=%s\n' "$source_system_ext_hash" "$out_system_ext_hash"
  echo

  echo "## retained product_b slice"
  local source_product="${WORK_DIR}/product_b-from-v0.28-source.img"
  local out_product="${WORK_DIR}/product_b-from-v0.29-sparse.img"
  "$SPARSE_TOOL" --source-sparse "$SOURCE_V028" --extract-image "product_b=${source_product}" >/dev/null
  "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --extract-image "product_b=${out_product}" >/dev/null
  local source_product_hash
  local out_product_hash
  source_product_hash="$(sha256_one "$source_product")"
  out_product_hash="$(sha256_one "$out_product")"
  [ "$source_product_hash" = "$out_product_hash" ] \
    || die "product_b changed unexpectedly"
  printf 'product_b\tsource=%s\tout=%s\n' "$source_product_hash" "$out_product_hash"
  echo

  echo "## Sidebar APK in system_b"
  local dumped_sidebar="${WORK_DIR}/Sidebar-from-system_b.apk"
  debugfs_dump "$EXPECTED_SYSTEM_IMG" "/system/priv-app/Sidebar/Sidebar.apk" "$dumped_sidebar"
  [ "$(sha256_one "$dumped_sidebar")" = "$(sha256_one "$SIDEBAR_APK")" ] \
    || die "dumped Sidebar APK hash mismatch"
  unzip -t "$dumped_sidebar" >/dev/null
  printf 'sidebar_apk\tsha256=%s\t%s\n' "$(sha256_one "$dumped_sidebar")" "$dumped_sidebar"
  echo

  echo "## APK member scope and decoded semantics"
  verify_zip_scope "$BASE_RAW_APK" "$SIDEBAR_RAW_APK"
  install_frameworks
  verify_decoded_sidebar_apk "$dumped_sidebar" "${WORK_DIR}/decoded-sidebar"
  echo

  echo "## signature boundary"
  verify_sig_boundary "$dumped_sidebar" "${WORK_DIR}/sidebar-signature-boundary.txt"
  echo

  echo "## package directory and held inode paths"
  debugfs_path_exists "$EXPECTED_SYSTEM_IMG" "/system/priv-app/Sidebar/.Sidebar.apk.smartisax-v029-stock-held" \
    || die "missing v0.29 held Sidebar APK path"
  echo "held_stock_path=/system/priv-app/Sidebar/.Sidebar.apk.smartisax-v029-stock-held"
  verify_package_dir_mtime "$EXPECTED_SYSTEM_IMG" "/system/priv-app/Sidebar" "$SIDEBAR_DIR_MTIME"
  echo

  echo "## retained debloat removals"
  local path
  for path in "${removed_paths[@]}"; do
    if debugfs_path_exists "$EXPECTED_SYSTEM_IMG" "$path"; then
      die "removed path unexpectedly exists in v0.29 system_b: ${path}"
    fi
    echo "absent=${path}"
  done
  echo

  echo "PASS: v0.29 Sidebar topbar-hide offline image verification"
}

live_failures=0

note_live_failure() {
  echo "FAIL: $*" >&2
  live_failures=$((live_failures + 1))
}

live_package_paths() {
  local pkg="$1"
  adb_shell "pm path ${pkg} 2>/dev/null || true"
}

check_live_package_absent() {
  local pkg="$1"
  local paths
  paths="$(live_package_paths "$pkg")"
  if [ -n "$paths" ]; then
    note_live_failure "${pkg} is still present: ${paths}"
    printf '%s\tpresent\t%s\n' "$pkg" "$paths"
  else
    printf '%s\tabsent=ok\n' "$pkg"
  fi
}

run_live() {
  need_file "$SIDEBAR_APK"
  need_executable "$ROOT_HELPER"
  adb_available || die "adb device ${SERIAL} is not online"

  echo "# ${VARIANT} device read-only verification"
  date -u +"verified_at=%Y-%m-%dT%H:%M:%SZ"
  echo

  echo "## boot state"
  local boot slot bootanim verified
  boot="$(adb_shell 'getprop sys.boot_completed')"
  slot="$(adb_shell 'getprop ro.boot.slot_suffix')"
  bootanim="$(adb_shell 'getprop init.svc.bootanim')"
  verified="$(adb_shell 'getprop ro.boot.verifiedbootstate')"
  printf 'boot_completed=%s\nslot=%s\nbootanim=%s\nverified=%s\n' "$boot" "$slot" "$bootanim" "$verified"
  [ "$boot" = "1" ] || note_live_failure "sys.boot_completed != 1"
  [ "$slot" = "_b" ] || note_live_failure "slot is not _b"
  [ "$bootanim" = "stopped" ] || note_live_failure "bootanim is not stopped"
  echo

  echo "## root"
  "$ROOT_HELPER" status || note_live_failure "root status failed"
  echo

  echo "## keyguard/window state"
  local window_state
  window_state="$(adb_shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing|sidebar_content_area|sidebar_top_area|sidebar_side_area' | head -120")"
  printf '%s\n' "$window_state"
  if printf '%s\n' "$window_state" | grep -q 'isKeyguardShowing=true'; then
    note_live_failure "keyguard is showing; unlock before final verification"
  fi
  for needle in sidebar_content_area sidebar_top_area sidebar_side_area; do
    if ! printf '%s\n' "$window_state" | grep -q "$needle"; then
      note_live_failure "missing sidebar window marker: ${needle}"
    fi
  done
  echo

  echo "## Sidebar package and APK hash"
  local sidebar_paths
  sidebar_paths="$(live_package_paths com.smartisanos.sidebar)"
  printf 'pm_path_com.smartisanos.sidebar=%s\n' "${sidebar_paths:-none}"
  if ! printf '%s\n' "$sidebar_paths" | grep -q '/system/priv-app/Sidebar/Sidebar.apk'; then
    note_live_failure "Sidebar package is not resolving from /system/priv-app/Sidebar"
  fi
  if printf '%s\n' "$sidebar_paths" | grep -q '/data/app/'; then
    note_live_failure "Sidebar has /data/app shadow"
  fi
  local expected_hash
  local live_hash
  expected_hash="$(sha256_one "$SIDEBAR_APK")"
  live_hash="$("$ROOT_HELPER" cmd "sha256sum /system/priv-app/Sidebar/Sidebar.apk" | awk '{print $1}' | tail -1)"
  printf 'sidebar_expected_sha256=%s\nsidebar_live_sha256=%s\n' "$expected_hash" "$live_hash"
  [ "$live_hash" = "$expected_hash" ] || note_live_failure "live Sidebar APK hash mismatch"
  echo

  echo "## Sidebar structural package state"
  local package_dump
  package_dump="$(adb_shell "dumpsys package com.smartisanos.sidebar | grep -E 'userId=1000|pkg=Package|sharedUser|SidebarService|SettingActivity|provider|android.uid.system' | head -120")"
  printf '%s\n' "$package_dump"
  if ! printf '%s\n' "$package_dump" | grep -Eq 'userId=1000|android.uid.system'; then
    note_live_failure "Sidebar shared/system UID marker missing"
  fi
  local launcher_query
  launcher_query="$(adb_shell "cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.smartisanos.sidebar 2>/dev/null || true")"
  printf 'sidebar_launcher_query=%s\n' "${launcher_query:-empty}"
  if [ -n "$launcher_query" ] \
    && ! printf '%s\n' "$launcher_query" | grep -Eq '^No activit(y|ies) found$'; then
    note_live_failure "Sidebar launcher entry is present"
  fi
  echo

  echo "## retained v0.27/v0.28 package removals"
  local pkg
  for pkg in "${target_absent_packages[@]}"; do
    check_live_package_absent "$pkg"
  done
  echo

  if [ "$live_failures" -ne 0 ]; then
    die "v0.29 live read-only verification failed with ${live_failures} issue(s)"
  fi
  echo "PASS: v0.29 Sidebar topbar-hide device read-only verification"
}

mode="${1:-}"
case "$mode" in
  --offline-image)
    report="$(latest_report_path offline-image)"
    run_offline | tee "$report"
    ;;
  --read-only)
    report="$(latest_report_path device)"
    run_live | tee "$report"
    ;;
  -h|--help|help|"")
    usage
    [ -n "$mode" ] || exit 2
    ;;
  *)
    usage >&2
    die "unknown mode: ${mode}"
    ;;
esac
