#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
LOCALE_POLICY="${LOCALE_POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
INVENTORY="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv"
EXTRACTED_TARGETS="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/manifest/extracted-targets.tsv"
APK_ONLY_MANIFEST="${APK_ONLY_MANIFEST:-${ROOT_DIR}/hard-rom/build/apk/locale-prune-apk-only-manifest.tsv}"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

package_name=""
stock_apk=""
output_apk=""
label=""
apk_only_variant=""
apk_only_note=""

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-apk-locale-prune.sh --package <package.name> [--out <apk>] [--apk-only-variant <name>]
  tools/r2-build-apk-locale-prune.sh --apk <path/to/app.apk> --label <name> [--out <apk>]

Build an offline APK resource-prune candidate that removes compiled locale
resources outside English and Chinese:

  keep:
    res/values
    res/*-en*
    res/*-zh*
    non-locale resource qualifiers such as values-night, values-v31,
    drawable-nodpi, or layout-land

  remove:
    locale resource dirs for all other languages, such as values-ja, raw-ko,
    drawable-fr, values-pt-rBR, values-mcc001-ja, etc.

The output changes only resources.arsc in the stock APK shell. If present,
classes.dex and AndroidManifest.xml must remain byte-identical to stock.

This is an offline toolchain probe. Output APKs are not flash-authorized by
themselves and are intended for original-cert-preserving system-partition ROM
experiments only.

Use --apk-only-variant only for candidates that are not yet included in a ROM
image. It records the output in hard-rom/build/apk/locale-prune-apk-only-manifest.tsv
so coverage and APK-only verification can discover it.
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

safe_name() {
  printf "%s" "$1" | tr '/ :' '___' | tr -c 'A-Za-z0-9._+-' '_'
}

entry_exists() {
  local apk="$1"
  local entry="$2"
  unzip -Z1 "$apk" | awk -v entry="$entry" '$0 == entry { found = 1 } END { exit found ? 0 : 1 }'
}

resolve_package_apk() {
  local pkg="$1"
  local decoded
  decoded="$(awk -F '\t' -v pkg="$pkg" 'NR > 1 && $2 == pkg { print $1; exit }' "$INVENTORY")"
  [ -n "$decoded" ] || die "package not found in locale inventory: ${pkg}"

  stock_apk="$(awk -F '\t' -v decoded="$decoded" '$1 == decoded { print $5; exit }' "$EXTRACTED_TARGETS")"
  [ -n "$stock_apk" ] || die "raw APK path not found for ${pkg} (${decoded})"
  label="$pkg"
}

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
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

  "$PYTHON_BIN" - "$DECODED_DIR/res" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

res = Path(sys.argv[1])

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
for child in sorted(res.iterdir()):
    if not child.is_dir():
        continue
    lang = locale_from_res_dir(child.name)
    if lang and lang not in {"en", "zh"}:
        bad.append(child.name)
if bad:
    raise SystemExit("non-target locale resource dirs remained: " + ", ".join(bad))
PY
}

merge_resources_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-apk-locale-prune-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$OUT_DIR"
  cp "$stock_apk" "${output_apk}.tmp"
  unzip -p "$REBUILT_UNSIGNED" resources.arsc > "${tmp}/resources.arsc"
  touch -t 200901010000 "${tmp}/resources.arsc"
  (
    cd "$tmp"
    zip -X -q -0 "${output_apk}.tmp" resources.arsc
  )
  mv "${output_apk}.tmp" "$output_apk"

  rebuilt_res_hash="$(unzip -p "$REBUILT_UNSIGNED" resources.arsc | shasum -a 256 | awk '{print $1}')"
  out_res_hash="$(unzip -p "$output_apk" resources.arsc | shasum -a 256 | awk '{print $1}')"
  [ "$rebuilt_res_hash" = "$out_res_hash" ] || die "merged resources.arsc hash mismatch"

  for entry in classes.dex AndroidManifest.xml; do
    if entry_exists "$stock_apk" "$entry"; then
      entry_exists "$output_apk" "$entry" || die "${entry} missing from output"
      stock_hash="$(unzip -p "$stock_apk" "$entry" | shasum -a 256 | awk '{print $1}')"
      out_hash="$(unzip -p "$output_apk" "$entry" | shasum -a 256 | awk '{print $1}')"
      [ "$stock_hash" = "$out_hash" ] || die "${entry} changed unexpectedly"
    fi
  done
}

verify_merged_resources() {
  rm -rf "$CHECK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$CHECK_DIR" "$output_apk" >/dev/null

  "$PYTHON_BIN" - "$CHECK_DIR/res" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

res = Path(sys.argv[1])

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
    else:
        bad.append(child.name)
if bad:
    raise SystemExit("merged APK still decodes non-target locale resource dirs: " + ", ".join(bad))
print("kept_locale_dirs=" + ",".join(kept))
PY
}

record_apk_only_candidate() {
  [ -n "$apk_only_variant" ] || return 0
  [ -n "$package_name" ] || die "--apk-only-variant requires --package so coverage can join package metadata"

  local out_sha out_rel note
  out_sha="$(shasum -a 256 "$output_apk" | awk '{print $1}')"
  case "$output_apk" in
    "${ROOT_DIR}"/*) out_rel="${output_apk#${ROOT_DIR}/}" ;;
    *) out_rel="$output_apk" ;;
  esac
  note="$apk_only_note"
  if [ -z "$note" ]; then
    note="APK-only resources.arsc prune built offline; not in a ROM image and not live-tested"
  fi

  "$PYTHON_BIN" - "$APK_ONLY_MANIFEST" "$package_name" "$apk_only_variant" "$out_rel" "$out_sha" "$note" <<'PY'
from __future__ import annotations

import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
record = {
    "package": sys.argv[2],
    "variant": sys.argv[3],
    "apk": sys.argv[4],
    "sha256": sys.argv[5],
    "note": sys.argv[6],
}
fields = ["package", "variant", "apk", "sha256", "note"]
rows: dict[str, dict[str, str]] = {}
if path.exists():
    with path.open(encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            package = row.get("package", "")
            if package:
                rows[package] = {field: row.get(field, "") for field in fields}
rows[record["package"]] = record
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("w", encoding="utf-8", newline="") as fh:
    writer = csv.DictWriter(fh, fields, delimiter="\t")
    writer.writeheader()
    for package in sorted(rows):
        writer.writerow(rows[package])
PY

  echo "apk_only_manifest=${APK_ONLY_MANIFEST}" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      [ "$#" -ge 2 ] || die "--package requires a value"
      package_name="$2"
      shift 2
      ;;
    --apk)
      [ "$#" -ge 2 ] || die "--apk requires a value"
      stock_apk="$2"
      shift 2
      ;;
    --label)
      [ "$#" -ge 2 ] || die "--label requires a value"
      label="$2"
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || die "--out requires a value"
      output_apk="$2"
      shift 2
      ;;
    --apk-only-variant)
      [ "$#" -ge 2 ] || die "--apk-only-variant requires a value"
      apk_only_variant="$2"
      shift 2
      ;;
    --apk-only-note)
      [ "$#" -ge 2 ] || die "--apk-only-note requires a value"
      apk_only_note="$2"
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

if [ -n "$package_name" ]; then
  [ -z "$stock_apk" ] || die "use either --package or --apk, not both"
  resolve_package_apk "$package_name"
else
  [ -n "$stock_apk" ] || die "missing --package or --apk"
  [ -n "$label" ] || die "--label is required with --apk"
fi

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$stock_apk"
need_file "$LOCALE_POLICY"
need_executable "$JAVA_BIN"
need_command "$PYTHON_BIN"
need_executable "$SIGCHECK"
need_executable "$LOCALE_POLICY"

safe="$(safe_name "$label")"
WORK_DIR="${ROOT_DIR}/hard-rom/work/apk-locale-prune/${safe}"
FRAMEWORK_DIR="${WORK_DIR}/framework"
DECODED_DIR="${WORK_DIR}/decoded"
CHECK_DIR="${WORK_DIR}/merged-check"
REBUILT_UNSIGNED="${WORK_DIR}/${safe}-locale-prune-rebuilt-unsigned.apk"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"

if [ -z "$output_apk" ]; then
  output_apk="${OUT_DIR}/${safe}-locale-prune-en-zh.apk"
else
  case "$output_apk" in
    /*) ;;
    *) output_apk="${ROOT_DIR}/${output_apk}" ;;
  esac
  OUT_DIR="$(dirname "$output_apk")"
fi

SIG_REPORT="${output_apk%.apk}.signature.txt"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$output_apk" "$SIG_REPORT"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding APK: ${stock_apk}"
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$stock_apk" >/dev/null

echo "Pruning non-English/non-Chinese locale resources..."
prune_decoded_locales

echo "Rebuilding resource-prune intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging pruned resources.arsc into stock APK shell..."
merge_resources_into_stock_shell

echo "Verifying merged resource table..."
verify_merged_resources > "${WORK_DIR}/merged-locale-check.txt"
"$LOCALE_POLICY" --keep-languages en,zh "$output_apk" > "${WORK_DIR}/arsc-policy-check.txt"

echo "Writing signature boundary report..."
"$SIGCHECK" "$output_apk" > "$SIG_REPORT"
grep -q '^keytool_status=1$' "$SIG_REPORT" \
  || die "unexpected keytool boundary; review ${SIG_REPORT}"
grep -q 'SHA-256 digest error for resources.arsc' "$SIG_REPORT" \
  || die "signature report does not show the expected resources.arsc digest boundary"

record_apk_only_candidate

{
  echo "label=${label}"
  [ -n "$package_name" ] && echo "package=${package_name}"
  echo "stock_apk=${stock_apk}"
  echo "built_apk=${output_apk}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "signature_report=${SIG_REPORT}"
  echo "removed_locale_dirs=${WORK_DIR}/remove-dirs.txt"
  echo "kept_locale_dirs=${WORK_DIR}/keep-locale-dirs.txt"
  echo "merged_locale_check=${WORK_DIR}/merged-locale-check.txt"
  echo "arsc_policy_check=${WORK_DIR}/arsc-policy-check.txt"
  shasum -a 256 "$output_apk" "$REBUILT_UNSIGNED" "$stock_apk"
  echo
  sed -n '1,60p' "$SIG_REPORT"
} >&2

echo "$output_apk"
