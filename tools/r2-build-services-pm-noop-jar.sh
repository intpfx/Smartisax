#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.pm0-services-jar-noop}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
DEXDUMP="${DEXDUMP:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/dexdump}"
STOCK_SERVICES="${STOCK_SERVICES:-${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw/system/system/framework/services.jar}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/build/framework}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}}"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
ROUNDTRIP_JAR="${WORK_DIR}/services-apktool-roundtrip.jar"
MERGED_JAR="${WORK_DIR}/services-stock-shell-roundtrip-dex.jar"
OUT_JAR="${OUT_JAR:-${OUT_DIR}/services-pm-noop-roundtrip.jar}"
REPORT="${INSPECT_DIR}/services-pm-noop-roundtrip-report.txt"
SMALI_EVIDENCE_DIR="${INSPECT_DIR}/smali-evidence"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-services-pm-noop-jar.sh

Build a services.jar no-op/roundtrip candidate for the PackageManager policy
line. The script:

  1. decodes stock /system/framework/services.jar with apktool
  2. rebuilds it without smali edits
  3. merges only rebuilt classes.dex/classes2.dex back into the stock jar shell
  4. zipaligns and validates the result
  5. records PackageManager smali evidence for later policy work

It does not build a system image, build a super image, flash, reboot, or touch a
live device.

Environment:
  VARIANT=<name>
  WORK_DIR=<dir>
  OUT_JAR=<path>
  JAVA_BIN=<path>
  APKTOOL=<path>
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

entry_sha256() {
  local archive="$1"
  local entry="$2"
  unzip -p "$archive" "$entry" | shasum -a 256 | awk '{print $1}'
}

case "${1:-}" in
  "" )
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

need_file "$STOCK_SERVICES"
need_file "$APKTOOL"
need_executable "$JAVA_BIN"
need_executable "$ZIPALIGN"
need_executable "$DEXDUMP"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR" "$SMALI_EVIDENCE_DIR"
rm -f "$OUT_JAR" "$REPORT"

echo "Decoding stock services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$DECODED_DIR" "$STOCK_SERVICES" >/dev/null

echo "Rebuilding services.jar without smali edits..."
"$JAVA_BIN" -jar "$APKTOOL" b -f -o "$ROUNDTRIP_JAR" "$DECODED_DIR" >/dev/null

echo "Merging rebuilt dex files into stock jar shell..."
python3 - "$STOCK_SERVICES" "$ROUNDTRIP_JAR" "$MERGED_JAR" <<'PY'
import shutil
import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
roundtrip = Path(sys.argv[2])
out = Path(sys.argv[3])
dex_entries = {"classes.dex", "classes2.dex"}

with zipfile.ZipFile(stock, "r") as stock_zip, zipfile.ZipFile(roundtrip, "r") as rt_zip:
    stock_names = [info.filename for info in stock_zip.infolist()]
    rt_names = set(rt_zip.namelist())
    missing = sorted(name for name in dex_entries if name not in rt_names)
    if missing:
        raise SystemExit(f"roundtrip jar missing dex entries: {missing}")
    with zipfile.ZipFile(out, "w") as out_zip:
        for info in stock_zip.infolist():
            data = rt_zip.read(info.filename) if info.filename in dex_entries else stock_zip.read(info.filename)
            new_info = zipfile.ZipInfo(info.filename, info.date_time)
            new_info.comment = info.comment
            new_info.extra = info.extra
            new_info.internal_attr = info.internal_attr
            new_info.external_attr = info.external_attr
            new_info.create_system = info.create_system
            new_info.compress_type = zipfile.ZIP_STORED
            out_zip.writestr(new_info, data)

with zipfile.ZipFile(out, "r") as merged_zip:
    merged_names = [info.filename for info in merged_zip.infolist()]
if merged_names != stock_names:
    raise SystemExit("merged jar entry order does not match stock shell")
PY

echo "Zipaligning services.jar..."
"$ZIPALIGN" -f -p 4 "$MERGED_JAR" "$OUT_JAR" >/dev/null

unzip -t "$OUT_JAR" >/dev/null
"$ZIPALIGN" -c -p 4 "$OUT_JAR" >/dev/null

mkdir -p "${WORK_DIR}/dex"
unzip -p "$OUT_JAR" classes.dex > "${WORK_DIR}/dex/classes.dex"
unzip -p "$OUT_JAR" classes2.dex > "${WORK_DIR}/dex/classes2.dex"
"$DEXDUMP" -f "${WORK_DIR}/dex/classes.dex" > "${WORK_DIR}/dex/classes.dexdump.txt"
"$DEXDUMP" -f "${WORK_DIR}/dex/classes2.dex" > "${WORK_DIR}/dex/classes2.dexdump.txt"

echo "Decoding final services.jar for evidence..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$VERIFY_DECODED_DIR" "$OUT_JAR" >/dev/null

for rel in \
  "smali/com/android/server/pm/PackageManagerService.smali" \
  "smali/com/android/server/pm/PackageAbiHelperImpl.smali" \
  "smali/com/android/server/pm/parsing/PackageCacher.smali" \
  "smali/com/android/server/pm/PackageManagerServiceUtils.smali" \
  "smali/com/android/server/pm/Settings.smali"
do
  need_file "${VERIFY_DECODED_DIR}/${rel}"
  cp "${VERIFY_DECODED_DIR}/${rel}" "${SMALI_EVIDENCE_DIR}/$(basename "$rel")"
done

python3 - "$STOCK_SERVICES" "$OUT_JAR" "$REPORT" "$VARIANT" "$SMALI_EVIDENCE_DIR" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
out = Path(sys.argv[2])
report = Path(sys.argv[3])
variant = sys.argv[4]
smali_dir = Path(sys.argv[5])

def file_sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def entry_map(path: Path):
    with zipfile.ZipFile(path, "r") as zf:
        result = {}
        for info in zf.infolist():
            data = zf.read(info.filename)
            result[info.filename] = {
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
                "compress_type": info.compress_type,
                "date_time": "%04d-%02d-%02d %02d:%02d:%02d" % info.date_time,
            }
        return result

stock_entries = entry_map(stock)
out_entries = entry_map(out)
if list(stock_entries) != list(out_entries):
    raise SystemExit("entry list/order mismatch")

changed = [
    name
    for name in stock_entries
    if stock_entries[name]["sha256"] != out_entries[name]["sha256"]
]
allowed = ["classes.dex", "classes2.dex"]
if changed != allowed:
    raise SystemExit(f"unexpected changed entries: {changed}")
for name, meta in out_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"entry is not STORED: {name}")

report.parent.mkdir(parents=True, exist_ok=True)
with report.open("w", encoding="utf-8") as f:
    f.write(f"variant={variant}\n")
    f.write(f"stock_services={stock}\n")
    f.write(f"stock_sha256={file_sha(stock)}\n")
    f.write(f"output_services={out}\n")
    f.write(f"output_sha256={file_sha(out)}\n")
    f.write("changed_entries=" + ",".join(changed) + "\n")
    f.write("all_entries_stored=true\n")
    f.write("stock_shell_non_dex_entries_preserved=true\n")
    f.write(f"smali_evidence_dir={smali_dir}\n")
    for name in allowed:
        f.write(f"{name}.stock_sha256={stock_entries[name]['sha256']}\n")
        f.write(f"{name}.output_sha256={out_entries[name]['sha256']}\n")
        f.write(f"{name}.stock_size={stock_entries[name]['size']}\n")
        f.write(f"{name}.output_size={out_entries[name]['size']}\n")
    for path in sorted(smali_dir.glob("*.smali")):
        f.write(f"smali_evidence={path}\n")
PY

{
  echo "services_pm_noop_jar=ok"
  echo "variant=${VARIANT}"
  echo "output=${OUT_JAR}"
  echo "sha256=$(sha256_one "$OUT_JAR")"
  echo "report=${REPORT}"
  echo "smali_evidence=${SMALI_EVIDENCE_DIR}"
} | tee -a "$REPORT"
