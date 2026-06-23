#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.wadb2-smartisax-wireless-adb-current-wifi}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
DEXDUMP="${DEXDUMP:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/dexdump}"
BASE_SERVICES="${BASE_SERVICES:-${ROOT_DIR}/hard-rom/build/framework/services-kg1-smartisax-skip-keyguard.jar}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}/services}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/build/framework}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}}"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_JAR="${WORK_DIR}/services-apktool-wadb2.jar"
MERGED_JAR="${WORK_DIR}/services-wadb2-stock-shell-dex.jar"
OUT_JAR="${OUT_JAR:-${OUT_DIR}/services-wadb2-current-wifi-adb.jar}"
REPORT="${INSPECT_DIR}/services-wadb2-current-wifi-adb-report.txt"

BASE_SERVICES_SHA256="0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6"
SENTINEL="__smartisax_current_wifi__"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-services-wadb2-current-wifi-jar.sh

Builds a services.jar candidate for v0.wadb2. It starts from the live-proven
v0.kg1 services.jar and changes only AdbDebuggingManager's wireless-debugging
allow path: when the caller passes the Smartisax sentinel BSSID, system_server
resolves the current Wi-Fi BSSID and stores that real BSSID in the ADB trusted
network list. It does not build an image, flash, reboot, or touch a live device.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_file "$BASE_SERVICES"
need_file "$APKTOOL"
need_executable "$JAVA_BIN"
need_executable "$ZIPALIGN"
need_executable "$DEXDUMP"

[ "$(sha256_one "$BASE_SERVICES")" = "$BASE_SERVICES_SHA256" ] \
  || die "base services.jar hash mismatch; expected live-proven v0.kg1 jar"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$OUT_JAR" "$REPORT"

echo "Decoding base services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$DECODED_DIR" "$BASE_SERVICES" >/dev/null

echo "Patching AdbDebuggingManager current-Wi-Fi sentinel..."
python3 - "$DECODED_DIR" "$SENTINEL" <<'PY'
from pathlib import Path
import sys

decoded = Path(sys.argv[1])
sentinel = sys.argv[2]
handler = decoded / "smali" / "com" / "android" / "server" / "adb" / "AdbDebuggingManager$AdbDebuggingHandler.smali"

old = """    .line 1054
    .local v1, "alwaysAllow":Z
    if-eqz v1, :cond_5

    .line 1055
    iget-object v2, p0, Lcom/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler;->mAdbKeyStore:Lcom/android/server/adb/AdbDebuggingManager$AdbKeyStore;

    invoke-virtual {v2, v0}, Lcom/android/server/adb/AdbDebuggingManager$AdbKeyStore;->addTrustedNetwork(Ljava/lang/String;)V

    .line 1060
    :cond_5
    invoke-direct {p0}, Lcom/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler;->getCurrentWifiApInfo()Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;

    move-result-object v2

    .line 1061
    .local v2, "newInfo":Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;
    if-eqz v2, :cond_20

    invoke-virtual {v2}, Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;->getBSSID()Ljava/lang/String;

    move-result-object v3

    invoke-virtual {v0, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
"""

new = f"""    .line 1054
    .local v1, "alwaysAllow":Z
    invoke-direct {{p0}}, Lcom/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler;->getCurrentWifiApInfo()Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;

    move-result-object v2

    .line 1061
    .local v2, "newInfo":Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;
    if-eqz v2, :cond_20

    const-string v3, "{sentinel}"

    invoke-virtual {{v3, v0}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v3

    if-eqz v3, :smartisax_adb_bssid_resolved

    invoke-virtual {{v2}}, Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;->getBSSID()Ljava/lang/String;

    move-result-object v0

    const-string v3, "SmartisaxADB"

    const-string v6, "Resolved current Wi-Fi BSSID for Smartisax wireless ADB"

    invoke-static {{v3, v6}}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I

    :smartisax_adb_bssid_resolved
    if-eqz v1, :cond_5

    .line 1055
    iget-object v3, p0, Lcom/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler;->mAdbKeyStore:Lcom/android/server/adb/AdbDebuggingManager$AdbKeyStore;

    invoke-virtual {{v3, v0}}, Lcom/android/server/adb/AdbDebuggingManager$AdbKeyStore;->addTrustedNetwork(Ljava/lang/String;)V

    .line 1060
    :cond_5
    invoke-virtual {{v2}}, Lcom/android/server/adb/AdbDebuggingManager$AdbConnectionInfo;->getBSSID()Ljava/lang/String;

    move-result-object v3

    invoke-virtual {{v0, v3}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
"""

text = handler.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit("AdbDebuggingHandler allowWirelessDebugging branch did not match expected v0.kg1 base")
handler.write_text(text.replace(old, new), encoding="utf-8")
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
            data = zf.read(info.filename)
            result[info.filename] = {
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
                "compress_type": info.compress_type,
            }
        return result

def find_one(root: Path, rel_tail: str) -> Path:
    matches = [path for path in root.rglob(Path(rel_tail).name) if str(path).endswith(rel_tail)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {rel_tail} under {root}, found {len(matches)}")
    return matches[0]

base_entries = entry_map(base)
out_entries = entry_map(out)
if list(base_entries) != list(out_entries):
    raise SystemExit("entry list/order mismatch")
changed = [name for name in base_entries if base_entries[name]["sha256"] != out_entries[name]["sha256"]]
allowed_changed = {"classes.dex", "classes2.dex"}
if not changed or any(name not in allowed_changed for name in changed):
    raise SystemExit(f"unexpected changed entries: {changed}")
for name, meta in out_entries.items():
    if meta["compress_type"] != 0:
        raise SystemExit(f"entry is not STORED: {name}")

handler = find_one(decoded, "com/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler.smali")
pm_policy = find_one(decoded, "com/android/server/pm/SmartisaxPackagePolicy.smali")
kg_policy = find_one(decoded, "com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali")

handler_text = handler.read_text(encoding="utf-8")
checks = [
    (handler, sentinel),
    (handler, "Resolved current Wi-Fi BSSID for Smartisax wireless ADB"),
    (handler, "AdbDebuggingManager$AdbConnectionInfo;->getBSSID()Ljava/lang/String;"),
    (handler, "AdbKeyStore;->addTrustedNetwork(Ljava/lang/String;)V"),
    (pm_policy, "shouldBypassPackageCache"),
    (kg_policy, "persist.smartisax.skip_keyguard"),
]
for path, needle in checks:
    if needle not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"{path} missing {needle}")
if handler_text.find(sentinel) > handler_text.find("addTrustedNetwork"):
    raise SystemExit("sentinel resolution appears after addTrustedNetwork")

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
    f.write(f"sentinel={sentinel}\n")
    f.write("smartisax_current_wifi_sentinel_policy=ok\n")
    f.write("pm1_policy_retained=ok\n")
    f.write("kg1_policy_retained=ok\n")
    f.write("result=PASS_BUILD_SERVICES_WADB2_CURRENT_WIFI_ADB\n")
PY

cat "$REPORT"
echo "Built: $OUT_JAR"
echo "Report: $REPORT"
