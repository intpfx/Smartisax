#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
LOCALE_POLICY="${LOCALE_POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
ARSC_PRUNER="${ROOT_DIR}/tools/r2-arsc-prune-locales.py"
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
  tools/r2-build-apk-locale-prune-binary-arsc.sh --package <package.name> [--out <apk>] [--apk-only-variant <name>]
  tools/r2-build-apk-locale-prune-binary-arsc.sh --apk <path/to/app.apk> --label <name> [--out <apk>]

Build an offline APK locale-prune candidate without rebuilding resources
through apktool/aapt2. This is for Smartisan packages that decode correctly
but cannot be rebuilt because of private framework attrs or package-id quirks.

The tool edits only resources.arsc by removing localized RES_TABLE_TYPE_TYPE
chunks whose language is not English or Chinese. It then merges the pruned
resources.arsc into the stock APK shell, preserving AndroidManifest.xml,
classes*.dex, and all other entries.

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

assert_stock_resources_stored() {
  "$PYTHON_BIN" - "$stock_apk" <<'PY'
from __future__ import annotations

import sys
import zipfile

apk = sys.argv[1]
with zipfile.ZipFile(apk) as zf:
    info = zf.getinfo("resources.arsc")
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit(
            f"stock resources.arsc is not STORED: compress_type={info.compress_type}"
        )
PY
}

merge_pruned_resources_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-apk-binary-arsc-merge.XXXXXX")"

  mkdir -p "$OUT_DIR"
  cp "$stock_apk" "${output_apk}.tmp"
  cp "$PRUNED_ARSC" "${tmp}/resources.arsc"
  touch -t 200901010000 "${tmp}/resources.arsc"
  (
    cd "$tmp"
    zip -X -q -0 "${output_apk}.tmp" resources.arsc
  )
  rm -rf "$tmp"
  mv "${output_apk}.tmp" "$output_apk"

  local pruned_hash out_hash
  pruned_hash="$(shasum -a 256 "$PRUNED_ARSC" | awk '{print $1}')"
  out_hash="$(unzip -p "$output_apk" resources.arsc | shasum -a 256 | awk '{print $1}')"
  [ "$pruned_hash" = "$out_hash" ] || die "merged resources.arsc hash mismatch"
}

verify_selected_entries_unchanged() {
  "$PYTHON_BIN" - "$stock_apk" "$output_apk" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile

stock, output = sys.argv[1:3]

with zipfile.ZipFile(stock) as stock_zip, zipfile.ZipFile(output) as out_zip:
    stock_names = set(stock_zip.namelist())
    out_names = set(out_zip.namelist())
    entries = ["AndroidManifest.xml"] + sorted(
        name for name in stock_names if name == "classes.dex" or (name.startswith("classes") and name.endswith(".dex"))
    )
    for entry in entries:
        if entry not in stock_names:
            continue
        if entry not in out_names:
            raise SystemExit(f"{entry} missing from output")
        stock_hash = hashlib.sha256(stock_zip.read(entry)).hexdigest()
        out_hash = hashlib.sha256(out_zip.read(entry)).hexdigest()
        if stock_hash != out_hash:
            raise SystemExit(f"{entry} changed unexpectedly")
PY
}

verify_decoded_output() {
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

bad: list[str] = []
kept: list[str] = []
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
    note="APK-only binary resources.arsc prune built offline; not in a ROM image and not live-tested"
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
need_file "$ARSC_PRUNER"
need_file "$LOCALE_POLICY"
need_executable "$JAVA_BIN"
need_command "$PYTHON_BIN"
need_command zip
need_command unzip
need_command shasum
need_executable "$SIGCHECK"
need_executable "$LOCALE_POLICY"

safe="$(safe_name "$label")"
WORK_DIR="${ROOT_DIR}/hard-rom/work/apk-locale-prune-binary-arsc/${safe}"
FRAMEWORK_DIR="${WORK_DIR}/framework"
CHECK_DIR="${WORK_DIR}/merged-check"
STOCK_ARSC="${WORK_DIR}/stock-resources.arsc"
PRUNED_ARSC="${WORK_DIR}/resources-pruned-en-zh.arsc"
PRUNE_REPORT="${WORK_DIR}/arsc-prune-report.json"
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

echo "Checking stock APK resource-table storage..."
assert_stock_resources_stored

echo "Extracting stock resources.arsc: ${stock_apk}"
unzip -p "$stock_apk" resources.arsc > "$STOCK_ARSC"

echo "Pruning non-English/non-Chinese resources.arsc config chunks..."
"$ARSC_PRUNER" "$STOCK_ARSC" "$PRUNED_ARSC" --keep-languages en,zh --report "$PRUNE_REPORT" >&2
"$PYTHON_BIN" - "$PRUNE_REPORT" <<'PY'
from __future__ import annotations

import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
if report["removed_count"] <= 0:
    raise SystemExit("binary arsc prune removed no locale config chunks")
PY

echo "Merging pruned resources.arsc into stock APK shell..."
merge_pruned_resources_into_stock_shell

echo "Verifying selected entries stayed unchanged..."
verify_selected_entries_unchanged
unzip -t "$output_apk" >/dev/null

echo "Verifying decoded merged resource dirs..."
verify_decoded_output > "${WORK_DIR}/merged-locale-check.txt"

echo "Verifying binary locale policy..."
"$LOCALE_POLICY" --keep-languages en,zh "$output_apk" > "${WORK_DIR}/arsc-policy-check.txt"
grep -q "bad_locale_chunk_count=0" "${WORK_DIR}/arsc-policy-check.txt" \
  || die "locale policy failed; review ${WORK_DIR}/arsc-policy-check.txt"

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
  echo "mode=binary_resources_arsc_prune"
  echo "stock_apk=${stock_apk}"
  echo "built_apk=${output_apk}"
  echo "stock_arsc=${STOCK_ARSC}"
  echo "pruned_arsc=${PRUNED_ARSC}"
  echo "prune_report=${PRUNE_REPORT}"
  echo "signature_report=${SIG_REPORT}"
  echo "merged_locale_check=${WORK_DIR}/merged-locale-check.txt"
  echo "arsc_policy_check=${WORK_DIR}/arsc-policy-check.txt"
  shasum -a 256 "$output_apk" "$PRUNED_ARSC" "$STOCK_ARSC" "$stock_apk"
  echo
  sed -n '1,80p' "${WORK_DIR}/merged-locale-check.txt"
  echo
  "$PYTHON_BIN" - "$PRUNE_REPORT" <<'PY'
from __future__ import annotations

import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print("removed_count=" + str(data["removed_count"]))
print("kept_locale_count=" + str(data["kept_locale_count"]))
for row in data["removed"][:80]:
    print("removed={type_name}:{language}_{region}:offset={offset}:size={size}".format(**row))
PY
  echo
  sed -n '1,80p' "$SIG_REPORT"
} >&2

echo "$output_apk"
