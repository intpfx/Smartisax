#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_ROOT="${ROOT_DIR}/hard-rom/work/launcher-entry-hide-apks"
MANIFEST="${MANIFEST:-}"

ANDROID_LAUNCHER="android.intent.category.LAUNCHER"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-launcher-entry-hide-apks.sh [--variant v0.26a|v0.26b|v0.26c]

Build manifest-only APK candidates that keep selected Smartisan features
installed but remove only their desktop launcher category. v0.26a covers:

  - com.smartisanos.videoplayerproject / VideoPlayer.apk
  - com.smartisanos.screenrecorder / ScreenRecorderSmartisan.apk
  - com.smartisanos.quicksearch / QuickSearchBoxSmartisan.apk

v0.26b covers:

  - com.smartisanos.sara / VoiceAssistant.apk

v0.26c covers:

  - com.smartisanos.sidebar / Sidebar.apk

The output changes only AndroidManifest.xml in the stock APK shell. It strips
the stock v2 signing block as a consequence of zip update, keeps META-INF v1
material, and expects the ordinary JAR verifier to report an
AndroidManifest.xml digest boundary. This is an offline candidate only.
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

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

safe_name() {
  printf "%s" "$1" | tr '/ :' '___' | tr -c 'A-Za-z0-9._+-' '_'
}

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

patch_decoded_manifest() {
  local manifest_xml="$1"
  local package_name="$2"
  local component="$3"
  local filter_index="$4"

  "$PYTHON_BIN" - "$manifest_xml" "$package_name" "$component" "$filter_index" <<'PY'
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
package_name = sys.argv[2]
component = sys.argv[3]
filter_index = int(sys.argv[4])

ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
ET.register_namespace("android", ANDROID_NS)


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


tree = ET.parse(path)
root = tree.getroot()
if root.attrib.get("package") != package_name:
    raise SystemExit(f"package mismatch: {root.attrib.get('package')} != {package_name}")

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

target = filters[filter_index - 1]
actions = values(target, "action")
categories = values(target, "category")
if "android.intent.action.MAIN" not in actions:
    raise SystemExit(f"target filter {filter_index} is not MAIN for {component}")
if "android.intent.category.LAUNCHER" not in categories:
    raise SystemExit(f"target filter {filter_index} does not contain LAUNCHER for {component}")

removed = 0
for child in list(target):
    if local(child.tag) == "category" and child.attrib.get(NAME) == "android.intent.category.LAUNCHER":
        target.remove(child)
        removed += 1
if removed != 1:
    raise SystemExit(f"expected to remove one LAUNCHER category, removed {removed}")

if "android.intent.category.LAUNCHER" in values(target, "category"):
    raise SystemExit("LAUNCHER category still present in target filter")

tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"removed_launcher_category={component}#{filter_index}")
PY
}

merge_manifest_into_stock_shell() {
  local stock_apk="$1"
  local rebuilt_apk="$2"
  local output_apk="$3"
  local tmp
  tmp="$(mktemp -d "/tmp/r2-launcher-hide-manifest.XXXXXX")"

  cp "$stock_apk" "${output_apk}.tmp"
  unzip -p "$rebuilt_apk" AndroidManifest.xml > "${tmp}/AndroidManifest.xml"
  touch -t 200901010000 "${tmp}/AndroidManifest.xml"
  (
    cd "$tmp"
    zip -X -q "${output_apk}.tmp" AndroidManifest.xml
  )
  mv "${output_apk}.tmp" "$output_apk"
  rm -rf "$tmp"
}

verify_output_apk() {
  local stock_apk="$1"
  local output_apk="$2"
  local package_name="$3"
  local component="$4"
  local filter_index="$5"
  local check_dir="$6"
  local sig_report="$7"

  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  unzip -t "$output_apk" >/dev/null

  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/stock" "$stock_apk" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/out" "$output_apk" >/dev/null

  "$PYTHON_BIN" - "$stock_apk" "$output_apk" "$package_name" "$component" "$filter_index" \
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


def remove_expected_launcher(root: ET.Element) -> None:
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
    target = filters[filter_index - 1]
    for child in list(target):
        if local(child.tag) == "category" and child.attrib.get(NAME) == "android.intent.category.LAUNCHER":
            target.remove(child)
            return
    raise SystemExit("expected LAUNCHER category was not present in stock XML")


def strip_blank_text(node: ET.Element) -> None:
    if node.text is not None and not node.text.strip():
        node.text = None
    if node.tail is not None and not node.tail.strip():
        node.tail = None
    for child in list(node):
        strip_blank_text(child)


def canonical_xml(path: str) -> bytes:
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
actual = canonical_xml(out_xml)
if expected != actual:
    Path("/tmp/r2-launcher-hide-expected.xml").write_bytes(expected)
    Path("/tmp/r2-launcher-hide-actual.xml").write_bytes(actual)
    raise SystemExit("decoded manifest differs from expected launcher-only change")

root = ET.parse(out_xml).getroot()
if root.attrib.get("package") != package_name:
    raise SystemExit("package mismatch in output decoded manifest")
application = next((child for child in root if local(child.tag) == "application"), None)
matches = [
    child
    for child in application
    if local(child.tag) in {"activity", "activity-alias"}
    and full_component(child.attrib.get(NAME, "")) == component
]
filters = [child for child in matches[0] if local(child.tag) == "intent-filter"]
target = filters[filter_index - 1]
if "android.intent.action.MAIN" not in values(target, "action"):
    raise SystemExit("target filter lost MAIN")
if "android.intent.category.LAUNCHER" in values(target, "category"):
    raise SystemExit("target filter still resolves as LAUNCHER")

print("manifest_only_change=ok")
print("zip_member_content_scope=AndroidManifest.xml_only")
print("native_lib_offsets=ok")
print("main_launcher_removed=ok")
PY

  "$SIGCHECK" "$output_apk" > "$sig_report"
  grep -q '^apk_sig_block_magic=absent$' "$sig_report" \
    || die "expected APK signing block to be absent after manifest merge: ${sig_report}"
  grep -q '^keytool_status=1$' "$sig_report" \
    || die "expected keytool digest-boundary status for manifest-only candidate: ${sig_report}"
  grep -q 'SHA-256 digest error for AndroidManifest.xml' "$sig_report" \
    || die "signature report missing AndroidManifest.xml digest boundary: ${sig_report}"
}

build_one() {
  local feature="$1"
  local package_name="$2"
  local stock_apk="$3"
  local component="$4"
  local filter_index="$5"
  local out_name="$6"
  local safe
  safe="$(safe_name "$package_name")"

  local work_dir="${WORK_ROOT}/${safe}"
  local framework="${WORK_ROOT}/framework"
  local decoded="${work_dir}/decoded"
  local rebuilt="${work_dir}/${safe}-launcher-hidden-rebuilt-unsigned.apk"
  local output="${OUT_DIR}/${out_name}"
  local sig_report="${output%.apk}.signature.txt"
  local check_dir="${work_dir}/check"

  FRAMEWORK_DIR="$framework"
  mkdir -p "$FRAMEWORK_DIR" "$OUT_DIR"
  rm -rf "$work_dir"
  mkdir -p "$work_dir"
  rm -f "$output" "$sig_report"

  need_file "$stock_apk"
  echo "Decoding ${package_name}..."
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$decoded" "$stock_apk" >/dev/null

  echo "Removing launcher category for ${component}..."
  patch_decoded_manifest "${decoded}/AndroidManifest.xml" "$package_name" "$component" "$filter_index" \
    > "${work_dir}/patch-report.txt"

  echo "Rebuilding manifest carrier for ${package_name}..."
  "$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$rebuilt" "$decoded" >/dev/null

  echo "Merging AndroidManifest.xml into stock APK shell for ${package_name}..."
  merge_manifest_into_stock_shell "$stock_apk" "$rebuilt" "$output"

  echo "Verifying manifest-only scope for ${package_name}..."
  verify_output_apk "$stock_apk" "$output" "$package_name" "$component" "$filter_index" \
    "$check_dir" "$sig_report" > "${work_dir}/verify-report.txt"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$feature" "$package_name" "$component" "$filter_index" "$stock_apk" "$output" \
    "$(sha256_one "$stock_apk")" "$(sha256_one "$output")" "$sig_report" >> "$MANIFEST"

  echo "$output"
}

variant="v0.26a"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --variant)
      [ "$#" -ge 2 ] || die "--variant requires a value"
      variant="$2"
      shift 2
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
done

if [ -z "$MANIFEST" ]; then
  case "$variant" in
    v0.26a) MANIFEST="${OUT_DIR}/launcher-entry-hide-apk-manifest.tsv" ;;
    v0.26b) MANIFEST="${OUT_DIR}/launcher-entry-hide-apk-manifest-v0.26b.tsv" ;;
    v0.26c) MANIFEST="${OUT_DIR}/launcher-entry-hide-apk-manifest-v0.26c.tsv" ;;
    *) MANIFEST="${OUT_DIR}/launcher-entry-hide-apk-manifest-${variant}.tsv" ;;
  esac
fi

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_executable "$JAVA_BIN"
need_command "$PYTHON_BIN"
need_command zip
need_executable "$SIGCHECK"

rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT" "$OUT_DIR"
FRAMEWORK_DIR="${WORK_ROOT}/framework"
install_frameworks

{
  printf 'feature\tpackage\tcomponent\tfilter_index\tstock_apk\tbuilt_apk\tstock_sha256\tbuilt_sha256\tsignature_report\n'
} > "$MANIFEST"

case "$variant" in
  v0.26a)
    build_one "视频播放器" "com.smartisanos.videoplayerproject" \
      "${RAW}/system/system/priv-app/VideoPlayer/VideoPlayer.apk" \
      "com.smartisanos.videoplayerproject.MainActivity" "1" \
      "com.smartisanos.videoplayerproject-launcher-hidden.apk" >/dev/null

    build_one "屏幕录制" "com.smartisanos.screenrecorder" \
      "${RAW}/system/system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk" \
      "com.smartisanos.screenrecorder.EmptyActivity" "1" \
      "com.smartisanos.screenrecorder-launcher-hidden.apk" >/dev/null

    build_one "搜索" "com.smartisanos.quicksearch" \
      "${RAW}/system/system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk" \
      "com.android.quicksearchbox.SearchActivity" "2" \
      "com.smartisanos.quicksearch-launcher-hidden.apk" >/dev/null
    ;;
  v0.26b)
    build_one "闪念胶囊" "com.smartisanos.sara" \
      "${RAW}/system/system/priv-app/VoiceAssistant/VoiceAssistant.apk" \
      "com.smartisanos.sara.bubble.SettingActivity" "1" \
      "com.smartisanos.sara-launcher-hidden.apk" >/dev/null
    ;;
  v0.26c)
    build_one "一步" "com.smartisanos.sidebar" \
      "${RAW}/system/system/priv-app/Sidebar/Sidebar.apk" \
      "com.smartisanos.sidebar.setting.SettingActivity" "1" \
      "com.smartisanos.sidebar-launcher-hidden.apk" >/dev/null
    ;;
  *)
    die "unsupported variant: ${variant}"
    ;;
esac

echo "Built launcher-entry-hide APK candidates."
echo "Manifest: ${MANIFEST}"
cat "$MANIFEST"
