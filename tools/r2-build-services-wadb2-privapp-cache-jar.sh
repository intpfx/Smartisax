#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
BASE_SERVICES="${BASE_SERVICES:-${ROOT_DIR}/hard-rom/build/framework/services-wadb2-current-wifi-adb.jar}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}/services}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/build/framework}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}}"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_JAR="${WORK_DIR}/services-apktool-wadb2-privapp-cache.jar"
MERGED_JAR="${WORK_DIR}/services-wadb2-privapp-cache-stock-shell-dex.jar"
OUT_JAR="${OUT_JAR:-${OUT_DIR}/services-wadb2-privapp-cache-adb.jar}"
REPORT="${INSPECT_DIR}/services-wadb2-privapp-cache-adb-report.txt"

BASE_SERVICES_SHA256="59e1174901e914684a15e1bb22f82bc5683e23c91ec9a74123f7367826ab8ce2"
SENTINEL="__smartisax_current_wifi__"

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

case "${1:-}" in
  "") ;;
  -h|--help|help)
    cat <<'USAGE'
Usage:
  tools/r2-build-services-wadb2-privapp-cache-jar.sh

Builds a services.jar candidate on top of v0.wadb2. It only extends
SmartisaxPackagePolicy so PackageManager bypasses package-cache reads for
/system/priv-app/SmartisaxShell as well as the old /system/app path. It keeps
the v0.wadb2 current-Wi-Fi wireless ADB sentinel policy.
USAGE
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
esac

need_file "$BASE_SERVICES"
need_file "$APKTOOL"
need_executable "$JAVA_BIN"
need_executable "$ZIPALIGN"

[ "$(sha256_one "$BASE_SERVICES")" = "$BASE_SERVICES_SHA256" ] \
  || die "base services.jar hash mismatch; expected v0.wadb2 jar"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$OUT_JAR" "$REPORT"

echo "Decoding base v0.wadb2 services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$DECODED_DIR" "$BASE_SERVICES" >/dev/null

echo "Patching SmartisaxPackagePolicy priv-app cache bypass..."
python3 - "$DECODED_DIR" <<'PY'
from pathlib import Path
import sys

decoded = Path(sys.argv[1])
policy = decoded / "smali" / "com" / "android" / "server" / "pm" / "SmartisaxPackagePolicy.smali"
old = """    const-string v1, "/system/app/SmartisaxShell"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :cond_1

    const-string v1, "/system/app/TextBoomArm32"
"""
new = """    const-string v1, "/system/app/SmartisaxShell"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :cond_1

    const-string v1, "/system/priv-app/SmartisaxShell"

    invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :cond_1

    const-string v1, "/system/app/TextBoomArm32"
"""
text = policy.read_text(encoding="utf-8")
if "/system/priv-app/SmartisaxShell" in text:
    raise SystemExit("priv-app Smartisax path is already present")
if old not in text:
    raise SystemExit("SmartisaxPackagePolicy base block did not match expected v0.wadb2 policy")
policy.write_text(text.replace(old, new), encoding="utf-8")
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

"$ZIPALIGN" -f -p 4 "$MERGED_JAR" "$OUT_JAR" >/dev/null
unzip -t "$OUT_JAR" >/dev/null
"$ZIPALIGN" -c -p 4 "$OUT_JAR" >/dev/null

echo "Decoding final services.jar for semantic evidence..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$VERIFY_DECODED_DIR" "$OUT_JAR" >/dev/null

python3 - "$BASE_SERVICES" "$OUT_JAR" "$VERIFY_DECODED_DIR" "$REPORT" "$VARIANT" "$SENTINEL" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
out = Path(sys.argv[2])
decoded = Path(sys.argv[3])
report = Path(sys.argv[4])
variant = sys.argv[5]
sentinel = sys.argv[6]

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
            result[info.filename] = {
                "sha256": hashlib.sha256(zf.read(info.filename)).hexdigest(),
                "compress_type": info.compress_type,
            }
        return result

def find_one(rel_tail: str) -> Path:
    matches = [path for path in decoded.rglob(Path(rel_tail).name) if str(path).endswith(rel_tail)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {rel_tail}, found {len(matches)}")
    return matches[0]

base_entries = entry_map(base)
out_entries = entry_map(out)
if list(base_entries) != list(out_entries):
    raise SystemExit("entry list/order mismatch")
changed = [name for name in base_entries if base_entries[name]["sha256"] != out_entries[name]["sha256"]]
if not changed or any(name not in {"classes.dex", "classes2.dex"} for name in changed):
    raise SystemExit(f"unexpected changed entries: {changed}")
for name, meta in out_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"entry is not STORED: {name}")

handler = find_one("com/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler.smali")
policy = find_one("com/android/server/pm/SmartisaxPackagePolicy.smali")
kg_policy = find_one("com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali")
policy_text = policy.read_text(encoding="utf-8")
required = [
    (handler, sentinel),
    (handler, "Resolved current Wi-Fi BSSID for Smartisax wireless ADB"),
    (policy, "/system/app/SmartisaxShell"),
    (policy, "/system/priv-app/SmartisaxShell"),
    (policy, "/system/app/TextBoomArm32"),
    (kg_policy, "persist.smartisax.skip_keyguard"),
]
for path, needle in required:
    if needle not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"{path} missing {needle}")
if policy_text.find("/system/priv-app/SmartisaxShell") > policy_text.find("/system/app/TextBoomArm32"):
    raise SystemExit("priv-app Smartisax path appears after TextBoom block; expected early Smartisax bypass")

report.parent.mkdir(parents=True, exist_ok=True)
with report.open("w", encoding="utf-8") as f:
    f.write(f"variant={variant}\n")
    f.write(f"base_services={base}\n")
    f.write(f"base_services_sha256={file_sha(base)}\n")
    f.write(f"out_services={out}\n")
    f.write(f"out_services_sha256={file_sha(out)}\n")
    f.write("changed_entries=" + ",".join(changed) + "\n")
    f.write("all_entries_stored=true\n")
    f.write("manifest_retained=true\n")
    f.write("smartisax_current_wifi_sentinel_policy=ok\n")
    f.write("smartisax_privapp_cache_bypass=ok\n")
    f.write("kg1_policy_retained=ok\n")
    f.write("result=PASS_BUILD_SERVICES_WADB2_PRIVAPP_CACHE_ADB\n")
PY

cat "$REPORT"
echo "Built: $OUT_JAR"
echo "Report: $REPORT"
