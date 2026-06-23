#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
LOCALE_POLICY="${LOCALE_POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

MODE="locale-prune"
OUTPUT_APK=""

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-framework-res-locale-probe.sh [--mode locale-prune|noop] [--out <apk>]

Build an offline framework-res.apk resource-table probe.

Modes:
  locale-prune
    Remove non-English/non-Chinese locale resource dirs from framework-res.apk
    and narrow android.R.array.supported_locales to:
      en-US
      zh-Hans-CN
      zh-Hant-TW

    Also remove ar_EG from special_locale_codes/special_locale_names.

  noop
    Rebuild framework-res.apk without source edits, then merge the rebuilt
    resources.arsc into the stock APK shell. This is a toolchain control, not a
    behavior change.

The output changes only resources.arsc in the stock APK shell. AndroidManifest.xml
must remain byte-identical to stock. Public resource IDs must remain unchanged
after decoding the merged APK.

This is a high-risk framework resource probe. It does not build a system image,
does not build a super image, and is not flash-authorized by itself.
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

entry_exists() {
  local apk="$1"
  local entry="$2"
  unzip -Z1 "$apk" | awk -v entry="$entry" '$0 == entry { found = 1 } END { exit found ? 0 : 1 }'
}

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

rewrite_array_body() {
  "$PYTHON_BIN" - "$DECODED_DIR/res/values/arrays.xml" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

replacements = {
    "supported_locales": ["en-US", "zh-Hans-CN", "zh-Hant-TW"],
    "special_locale_codes": ["zh_CN", "zh_TW"],
    "special_locale_names": ["中文 (简体)", "中文 (繁體)"],
}

def replace_array(source: str, name: str, values: list[str]) -> str:
    pattern = re.compile(
        rf'(?P<head>^[ \t]*<(?P<tag>[A-Za-z0-9_-]+) name="{re.escape(name)}">\n)'
        r'(?P<body>.*?)'
        r'(?P<tail>^[ \t]*</(?P=tag)>)',
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(source)
    if not match:
        raise SystemExit(f"array not found: {name}")
    indent = " " * 8
    body = "".join(f"{indent}<item>{value}</item>\n" for value in values)
    return source[: match.start()] + match.group("head") + body + match.group("tail") + source[match.end() :]

for array_name, values in replacements.items():
    text = replace_array(text, array_name, values)

path.write_text(text, encoding="utf-8")
PY
}

compute_prune_sets() {
  "$PYTHON_BIN" - "$DECODED_DIR/res" "$WORK_DIR/remove-dirs.txt" "$WORK_DIR/keep-locale-dirs.txt" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

res = Path(sys.argv[1])
remove_out = Path(sys.argv[2])
keep_out = Path(sys.argv[3])

def locale_from_res_dir(name: str) -> tuple[str, str | None] | None:
    if "-" not in name:
        return None
    parts = name.split("-")[1:]
    for index, part in enumerate(parts):
        if part.startswith("b+"):
            tags = part.split("+")
            if len(tags) > 1 and re.fullmatch(r"[a-z]{2,3}", tags[1]):
                return tags[1], None
        if not re.fullmatch(r"[a-z]{2}", part):
            continue
        region = None
        if index + 1 < len(parts) and re.fullmatch(r"r[A-Z]{2}", parts[index + 1]):
            region = parts[index + 1][1:]
        return part, region
    return None

remove: list[Path] = []
keep_locale: list[Path] = []
for child in sorted(res.iterdir()):
    if not child.is_dir():
        continue
    parsed = locale_from_res_dir(child.name)
    if parsed is None:
        continue
    lang, _region = parsed
    if lang in {"en", "zh"}:
        keep_locale.append(child)
    else:
        remove.append(child)

remove_out.write_text("\n".join(str(path) for path in remove) + ("\n" if remove else ""), encoding="utf-8")
keep_out.write_text("\n".join(str(path) for path in keep_locale) + ("\n" if keep_locale else ""), encoding="utf-8")
print(f"remove={len(remove)} keep_locale={len(keep_locale)}")
PY
}

prune_decoded_locales() {
  need_file "${DECODED_DIR}/apktool.yml"
  compute_prune_sets

  [ -s "${WORK_DIR}/remove-dirs.txt" ] || die "no non-English/non-Chinese locale resource dirs found to prune"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    rm -rf "$path"
  done < "${WORK_DIR}/remove-dirs.txt"

  rewrite_array_body
  verify_decoded_policy "$DECODED_DIR" > "${WORK_DIR}/decoded-policy-check.txt"
}

merge_resources_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-framework-res-locale-probe-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$OUT_DIR"
  cp "$FW_ANDROID" "${OUTPUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" resources.arsc > "${tmp}/resources.arsc"
  touch -t 200901010000 "${tmp}/resources.arsc"
  (
    cd "$tmp"
    zip -X -q -0 "${OUTPUT_APK}.tmp" resources.arsc
  )
  mv "${OUTPUT_APK}.tmp" "$OUTPUT_APK"

  local rebuilt_res_hash
  local out_res_hash
  rebuilt_res_hash="$(unzip -p "$REBUILT_UNSIGNED" resources.arsc | shasum -a 256 | awk '{print $1}')"
  out_res_hash="$(unzip -p "$OUTPUT_APK" resources.arsc | shasum -a 256 | awk '{print $1}')"
  [ "$rebuilt_res_hash" = "$out_res_hash" ] || die "merged resources.arsc hash mismatch"

  entry_exists "$OUTPUT_APK" AndroidManifest.xml || die "AndroidManifest.xml missing from output"
  stock_manifest_hash="$(unzip -p "$FW_ANDROID" AndroidManifest.xml | shasum -a 256 | awk '{print $1}')"
  out_manifest_hash="$(unzip -p "$OUTPUT_APK" AndroidManifest.xml | shasum -a 256 | awk '{print $1}')"
  [ "$stock_manifest_hash" = "$out_manifest_hash" ] || die "AndroidManifest.xml changed unexpectedly"
}

verify_decoded_policy() {
  local decoded="$1"
  "$PYTHON_BIN" - "$decoded/res" "$MODE" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

res = Path(sys.argv[1])
mode = sys.argv[2]

def locale_from_res_dir(name: str) -> str | None:
    if "-" not in name:
        return None
    parts = name.split("-")[1:]
    for part in parts:
        if part.startswith("b+"):
            tags = part.split("+")
            if len(tags) > 1 and re.fullmatch(r"[a-z]{2,3}", tags[1]):
                return tags[1]
        if re.fullmatch(r"[a-z]{2}", part):
            return part
    return None

bad = []
kept = []
for child in sorted(res.iterdir()):
    if not child.is_dir():
        continue
    lang = locale_from_res_dir(child.name)
    if not lang:
        continue
    if lang in {"en", "zh"}:
        kept.append(child.name)
    elif mode == "locale-prune":
        bad.append(child.name)

if bad:
    raise SystemExit("non-target locale resource dirs remained: " + ", ".join(bad[:80]))

arrays = res / "values" / "arrays.xml"
if arrays.exists():
    root = ET.parse(arrays).getroot()
    def array_values(name: str) -> list[str]:
        node = None
        for candidate in root:
            if candidate.attrib.get("name") == name:
                node = candidate
                break
        if node is None:
            raise SystemExit(f"array not found after decode: {name}")
        return [(item.text or "").strip() for item in node.findall("item")]

    supported = array_values("supported_locales")
    special_codes = array_values("special_locale_codes")
    special_names = array_values("special_locale_names")
    if mode == "locale-prune":
        expected_supported = ["en-US", "zh-Hans-CN", "zh-Hant-TW"]
        expected_codes = ["zh_CN", "zh_TW"]
        expected_names = ["中文 (简体)", "中文 (繁體)"]
        if supported != expected_supported:
            raise SystemExit("supported_locales mismatch: " + repr(supported))
        if special_codes != expected_codes:
            raise SystemExit("special_locale_codes mismatch: " + repr(special_codes))
        if special_names != expected_names:
            raise SystemExit("special_locale_names mismatch: " + repr(special_names))
    print("supported_locales=" + ",".join(supported))
    print("special_locale_codes=" + ",".join(special_codes))
    print("kept_locale_dirs=" + ",".join(kept))
PY
}

verify_merged_resources() {
  rm -rf "$CHECK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$CHECK_DIR" "$OUTPUT_APK" >/dev/null

  verify_decoded_policy "$CHECK_DIR" > "${WORK_DIR}/merged-policy-check.txt"
  if [ "$MODE" = "locale-prune" ]; then
    "$LOCALE_POLICY" --keep-languages en,zh "$OUTPUT_APK" > "${WORK_DIR}/arsc-policy-check.txt"
  fi

  if ! diff -u "${DECODED_DIR}/res/values/public.xml" "${CHECK_DIR}/res/values/public.xml" \
    > "${WORK_DIR}/public-xml.diff"; then
    die "public.xml changed after rebuild; review ${WORK_DIR}/public-xml.diff"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      [ "$#" -ge 2 ] || die "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || die "--out requires a value"
      OUTPUT_APK="$2"
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

case "$MODE" in
  locale-prune|noop) ;;
  *) die "unknown mode: $MODE" ;;
esac

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$LOCALE_POLICY"
need_executable "$JAVA_BIN"
need_command "$PYTHON_BIN"
need_executable "$SIGCHECK"
need_executable "$LOCALE_POLICY"

WORK_DIR="${ROOT_DIR}/hard-rom/work/framework-res-${MODE}"
FRAMEWORK_DIR="${WORK_DIR}/framework"
DECODED_DIR="${WORK_DIR}/decoded"
CHECK_DIR="${WORK_DIR}/merged-check"
REBUILT_UNSIGNED="${WORK_DIR}/framework-res-${MODE}-rebuilt-unsigned.apk"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"

if [ -z "$OUTPUT_APK" ]; then
  case "$MODE" in
    locale-prune)
      OUTPUT_APK="${OUT_DIR}/framework-res-locale-prune-en-zh.apk"
      ;;
    noop)
      OUTPUT_APK="${OUT_DIR}/framework-res-rebuild-noop.apk"
      ;;
  esac
else
  case "$OUTPUT_APK" in
    /*) ;;
    *) OUTPUT_APK="${ROOT_DIR}/${OUTPUT_APK}" ;;
  esac
  OUT_DIR="$(dirname "$OUTPUT_APK")"
fi

SIG_REPORT="${OUTPUT_APK%.apk}.signature.txt"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUTPUT_APK" "$SIG_REPORT"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding framework-res.apk..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$FW_ANDROID" >/dev/null

if [ "$MODE" = "locale-prune" ]; then
  echo "Pruning framework-res non-English/non-Chinese locale resources..."
  prune_decoded_locales
else
  echo "Running framework-res no-op rebuild probe..."
  verify_decoded_policy "$DECODED_DIR" > "${WORK_DIR}/decoded-policy-check.txt"
fi

echo "Rebuilding framework-res resource intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging rebuilt resources.arsc into stock framework-res shell..."
merge_resources_into_stock_shell

echo "Verifying merged framework resource table..."
verify_merged_resources

echo "Writing signature boundary report..."
"$SIGCHECK" "$OUTPUT_APK" > "$SIG_REPORT"
grep -q 'SHA-256 digest error for resources.arsc' "$SIG_REPORT" \
  || die "signature report does not show the expected resources.arsc digest boundary"

{
  echo "mode=${MODE}"
  echo "stock_apk=${FW_ANDROID}"
  echo "built_apk=${OUTPUT_APK}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "signature_report=${SIG_REPORT}"
  echo "decoded_policy_check=${WORK_DIR}/decoded-policy-check.txt"
  echo "merged_policy_check=${WORK_DIR}/merged-policy-check.txt"
  [ -f "${WORK_DIR}/arsc-policy-check.txt" ] && echo "arsc_policy_check=${WORK_DIR}/arsc-policy-check.txt"
  echo "public_xml_diff=${WORK_DIR}/public-xml.diff"
  [ -f "${WORK_DIR}/remove-dirs.txt" ] && echo "removed_locale_dirs=${WORK_DIR}/remove-dirs.txt"
  [ -f "${WORK_DIR}/keep-locale-dirs.txt" ] && echo "kept_locale_dirs=${WORK_DIR}/keep-locale-dirs.txt"
  shasum -a 256 "$OUTPUT_APK" "$REBUILT_UNSIGNED" "$FW_ANDROID"
  echo
  sed -n '1,80p' "${WORK_DIR}/merged-policy-check.txt"
  echo
  sed -n '1,80p' "$SIG_REPORT"
} >&2

echo "$OUTPUT_APK"
