#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.pm1-pms-cache-allowlist}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
DEXDUMP="${DEXDUMP:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/dexdump}"
BASE_SERVICES="${BASE_SERVICES:-${ROOT_DIR}/hard-rom/build/framework/services-pm-noop-roundtrip.jar}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}/services}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/build/framework}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}}"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_JAR="${WORK_DIR}/services-apktool-pm1.jar"
MERGED_JAR="${WORK_DIR}/services-pm1-stock-shell-dex.jar"
OUT_JAR="${OUT_JAR:-${OUT_DIR}/services-pm1-cache-allowlist.jar}"
REPORT="${INSPECT_DIR}/services-pm1-cache-allowlist-report.txt"

BASE_SERVICES_SHA256="30ff020c9dead1afba480dfc075b50454723296376feae0b20a1a58e82f763bc"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-services-pm1-cache-allowlist-jar.sh

Builds a services.jar candidate for v0.pm1-pms-cache-allowlist. It starts from
the live-proven v0.pm0 no-op services.jar, adds only:

  - com.android.server.pm.SmartisaxPackagePolicy
  - a narrow ParallelPackageParser.parsePackage useCaches decision

The candidate keeps the base jar shell and replaces only rebuilt dex entries.
It does not build a system image, flash, reboot, or touch a live device.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

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

need_file "$BASE_SERVICES"
need_file "$APKTOOL"
need_executable "$JAVA_BIN"
need_executable "$ZIPALIGN"
need_executable "$DEXDUMP"

[ "$(sha256_one "$BASE_SERVICES")" = "$BASE_SERVICES_SHA256" ] \
  || die "base services.jar hash mismatch; expected live-proven v0.pm0 no-op jar"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$OUT_JAR" "$REPORT"

echo "Decoding base services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$DECODED_DIR" "$BASE_SERVICES" >/dev/null

echo "Applying SmartisaxPackagePolicy and ParallelPackageParser patch..."
python3 - "$DECODED_DIR" <<'PY'
from pathlib import Path
import sys

decoded = Path(sys.argv[1])
pm_dir = decoded / "smali" / "com" / "android" / "server" / "pm"
parser = pm_dir / "ParallelPackageParser.smali"
policy = pm_dir / "SmartisaxPackagePolicy.smali"

old = """.method protected parsePackage(Ljava/io/File;I)Lcom/android/server/pm/parsing/pkg/ParsedPackage;
    .locals 2
    .param p1, "scanFile"    # Ljava/io/File;
    .param p2, "parseFlags"    # I
    .annotation system Ldalvik/annotation/Throws;
        value = {
            Landroid/content/pm/PackageParser$PackageParserException;
        }
    .end annotation

    .line 129
    iget-object v0, p0, Lcom/android/server/pm/ParallelPackageParser;->mPackageParser:Lcom/android/server/pm/parsing/PackageParser2;

    const/4 v1, 0x1

    invoke-virtual {v0, p1, p2, v1}, Lcom/android/server/pm/parsing/PackageParser2;->parsePackage(Ljava/io/File;IZ)Lcom/android/server/pm/parsing/pkg/ParsedPackage;

    move-result-object v0

    return-object v0
.end method
"""

new = """.method protected parsePackage(Ljava/io/File;I)Lcom/android/server/pm/parsing/pkg/ParsedPackage;
    .locals 5
    .param p1, "scanFile"    # Ljava/io/File;
    .param p2, "parseFlags"    # I
    .annotation system Ldalvik/annotation/Throws;
        value = {
            Landroid/content/pm/PackageParser$PackageParserException;
        }
    .end annotation

    .line 129
    iget-object v0, p0, Lcom/android/server/pm/ParallelPackageParser;->mPackageParser:Lcom/android/server/pm/parsing/PackageParser2;

    invoke-static {p1}, Lcom/android/server/pm/SmartisaxPackagePolicy;->shouldBypassPackageCache(Ljava/io/File;)Z

    move-result v1

    if-eqz v1, :use_cache

    const/4 v1, 0x0

    const-string v2, "SmartisaxPMS"

    new-instance v3, Ljava/lang/StringBuilder;

    invoke-direct {v3}, Ljava/lang/StringBuilder;-><init>()V

    const-string v4, "Bypass package parser cache for "

    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    move-result-object v3

    invoke-virtual {v3, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    move-result-object v3

    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v3

    invoke-static {v2, v3}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :invoke_parse

    :use_cache
    const/4 v1, 0x1

    :invoke_parse
    invoke-virtual {v0, p1, p2, v1}, Lcom/android/server/pm/parsing/PackageParser2;->parsePackage(Ljava/io/File;IZ)Lcom/android/server/pm/parsing/pkg/ParsedPackage;

    move-result-object v0

    return-object v0
.end method
"""

text = parser.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit("ParallelPackageParser parsePackage method did not match expected v0.pm0 base")
parser.write_text(text.replace(old, new), encoding="utf-8")

policy.write_text(""".class public final Lcom/android/server/pm/SmartisaxPackagePolicy;
.super Ljava/lang/Object;
.source "SmartisaxPackagePolicy.java"


# direct methods
.method private constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static shouldBypassPackageCache(Ljava/io/File;)Z
    .locals 2
    .param p0, "scanFile"    # Ljava/io/File;

    if-eqz p0, :ret_false

    invoke-virtual {p0}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :ret_false

    const-string v1, "/system/app/SmartisaxShell"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :ret_true

    const-string v1, "/system/app/TextBoomArm32"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :ret_true

    const-string v1, "/system/app/TextBoom"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :ret_true

    const-string v1, "/system/priv-app/Sidebar"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :ret_true

    :ret_false
    const/4 v0, 0x0

    return v0

    :ret_true
    const/4 v0, 0x1

    return v0
.end method
""", encoding="utf-8")
PY

echo "Rebuilding patched services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" b -f -o "$REBUILT_JAR" "$DECODED_DIR" >/dev/null

echo "Merging rebuilt dex files into base jar shell..."
python3 - "$BASE_SERVICES" "$REBUILT_JAR" "$MERGED_JAR" <<'PY'
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
rebuilt = Path(sys.argv[2])
out = Path(sys.argv[3])
dex_entries = {"classes.dex", "classes2.dex"}

with zipfile.ZipFile(base, "r") as base_zip, zipfile.ZipFile(rebuilt, "r") as rebuilt_zip:
    base_names = [info.filename for info in base_zip.infolist()]
    rebuilt_names = set(rebuilt_zip.namelist())
    missing = sorted(name for name in dex_entries if name not in rebuilt_names)
    if missing:
        raise SystemExit(f"rebuilt jar missing dex entries: {missing}")
    with zipfile.ZipFile(out, "w") as out_zip:
        for info in base_zip.infolist():
            data = rebuilt_zip.read(info.filename) if info.filename in dex_entries else base_zip.read(info.filename)
            new_info = zipfile.ZipInfo(info.filename, info.date_time)
            new_info.comment = info.comment
            new_info.extra = info.extra
            new_info.internal_attr = info.internal_attr
            new_info.external_attr = info.external_attr
            new_info.create_system = info.create_system
            new_info.compress_type = zipfile.ZIP_STORED
            out_zip.writestr(new_info, data)

with zipfile.ZipFile(out, "r") as out_zip:
    if [info.filename for info in out_zip.infolist()] != base_names:
        raise SystemExit("merged jar entry order does not match base shell")
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

echo "Decoding final services.jar for semantic evidence..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$VERIFY_DECODED_DIR" "$OUT_JAR" >/dev/null

python3 - "$BASE_SERVICES" "$OUT_JAR" "$VERIFY_DECODED_DIR" "$REPORT" "$VARIANT" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
out = Path(sys.argv[2])
decoded = Path(sys.argv[3])
report = Path(sys.argv[4])
variant = sys.argv[5]

def file_sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
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
            }
        return result

base_entries = entry_map(base)
out_entries = entry_map(out)
if list(base_entries) != list(out_entries):
    raise SystemExit("entry list/order mismatch")
changed = [name for name in base_entries if base_entries[name]["sha256"] != out_entries[name]["sha256"]]
allowed_changed = {"classes.dex", "classes2.dex"}
if not changed or any(name not in allowed_changed for name in changed) or "classes.dex" not in changed:
    raise SystemExit(f"unexpected changed entries: {changed}")
for name, meta in out_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"entry is not STORED: {name}")

policy = decoded / "smali" / "com" / "android" / "server" / "pm" / "SmartisaxPackagePolicy.smali"
parser = decoded / "smali" / "com" / "android" / "server" / "pm" / "ParallelPackageParser.smali"
policy_text = policy.read_text(encoding="utf-8")
parser_text = parser.read_text(encoding="utf-8")
required_policy = [
    "/system/app/SmartisaxShell",
    "/system/app/TextBoomArm32",
    "/system/app/TextBoom",
    "/system/priv-app/Sidebar",
    "shouldBypassPackageCache",
]
for needle in required_policy:
    if needle not in policy_text:
        raise SystemExit(f"policy missing {needle}")
required_parser = [
    "SmartisaxPackagePolicy;->shouldBypassPackageCache",
    "SmartisaxPMS",
    "Bypass package parser cache for ",
    "parsePackage(Ljava/io/File;IZ)",
]
for needle in required_parser:
    if needle not in parser_text:
        raise SystemExit(f"parser missing {needle}")

report.parent.mkdir(parents=True, exist_ok=True)
with report.open("w", encoding="utf-8") as f:
    f.write(f"variant={variant}\n")
    f.write(f"base_services={base}\n")
    f.write(f"base_sha256={file_sha(base)}\n")
    f.write(f"output_services={out}\n")
    f.write(f"output_sha256={file_sha(out)}\n")
    f.write("changed_entries=" + ",".join(changed) + "\n")
    f.write("all_entries_stored=true\n")
    f.write("base_shell_non_dex_entries_preserved=true\n")
    f.write("helper_class=com.android.server.pm.SmartisaxPackagePolicy\n")
    f.write("patched_call=com.android.server.pm.ParallelPackageParser.parsePackage\n")
    f.write("allowlist=/system/app/SmartisaxShell,/system/app/TextBoomArm32,/system/app/TextBoom,/system/priv-app/Sidebar\n")
    for name in ["classes.dex", "classes2.dex"]:
        f.write(f"{name}.base_sha256={base_entries[name]['sha256']}\n")
        f.write(f"{name}.output_sha256={out_entries[name]['sha256']}\n")
        f.write(f"{name}.base_size={base_entries[name]['size']}\n")
        f.write(f"{name}.output_size={out_entries[name]['size']}\n")
PY

{
  echo "services_pm1_cache_allowlist_jar=ok"
  echo "variant=${VARIANT}"
  echo "base=${BASE_SERVICES}"
  echo "output=${OUT_JAR}"
  echo "sha256=$(sha256_one "$OUT_JAR")"
  echo "report=${REPORT}"
} | tee -a "$REPORT"
