#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.portal2.3-smartisax-framebuffer-grant}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
BASE_SERVICES="${BASE_SERVICES:-${ROOT_DIR}/hard-rom/build/framework/services-wadb2-privapp-cache-adb.jar}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}/services}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/build/framework}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}}"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_JAR="${WORK_DIR}/services-apktool-portal2.3-framebuffer-grant.jar"
MERGED_JAR="${WORK_DIR}/services-portal2.3-framebuffer-grant-stock-shell-dex.jar"
OUT_JAR="${OUT_JAR:-${OUT_DIR}/services-portal2.3-smartisax-framebuffer-grant.jar}"
REPORT="${INSPECT_DIR}/services-portal2.3-framebuffer-grant-report.txt"

BASE_SERVICES_SHA256="366bf1c3d0d25d195a51a265064d4a648b3656f4d703e507e86652072262e864"
SMARTISAX_PACKAGE="com.smartisax.browser"
SMARTISAX_PERMISSION="android.permission.READ_FRAME_BUFFER"

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

case "${1:-}" in
  "") ;;
  -h|--help|help)
    cat <<'USAGE'
Usage:
  tools/r2-build-services-portal2.3-framebuffer-grant-jar.sh

Builds a services.jar candidate on top of the live v0.portal2.2 services.jar.
It adds a narrow PackageManager signature-permission policy:

  com.smartisax.browser + android.permission.READ_FRAME_BUFFER => grant

All other signature permissions and packages keep the stock Smartisan/Android
grantSignaturePermission path. This is an offline build only.
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
  || die "base services.jar hash mismatch; expected live v0.portal2.2 services.jar"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$OUT_JAR" "$REPORT"

echo "Decoding base v0.portal2.2 services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$DECODED_DIR" "$BASE_SERVICES" >/dev/null

echo "Patching SmartisaxPackagePolicy and PermissionManagerService..."
python3 - "$DECODED_DIR" "$SMARTISAX_PACKAGE" "$SMARTISAX_PERMISSION" <<'PY'
from pathlib import Path
import sys

decoded = Path(sys.argv[1])
smartisax_package = sys.argv[2]
smartisax_permission = sys.argv[3]
policy = decoded / "smali" / "com" / "android" / "server" / "pm" / "SmartisaxPackagePolicy.smali"
pms = decoded / "smali" / "com" / "android" / "server" / "pm" / "permission" / "PermissionManagerService.smali"

policy_text = policy.read_text(encoding="utf-8")
if "shouldGrantSignaturePermission" in policy_text:
    raise SystemExit("SmartisaxPackagePolicy already contains shouldGrantSignaturePermission")

method = f"""
.method public static shouldGrantSignaturePermission(Ljava/lang/String;Ljava/lang/String;)Z
    .locals 2
    .param p0, "perm"    # Ljava/lang/String;
    .param p1, "packageName"    # Ljava/lang/String;

    if-eqz p0, :cond_0

    if-eqz p1, :cond_0

    const-string v0, "{smartisax_package}"

    invoke-virtual {{v0, p1}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_0

    const-string v1, "{smartisax_permission}"

    invoke-virtual {{v1, p0}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :cond_0

    const/4 v0, 0x1

    return v0

    :cond_0
    const/4 v0, 0x0

    return v0
.end method
"""

anchor = "# direct methods\n.method private constructor <init>()V"
if anchor not in policy_text:
    raise SystemExit("SmartisaxPackagePolicy constructor anchor not found")
policy_text = policy_text.replace(anchor, "# direct methods\n" + method + "\n.method private constructor <init>()V", 1)
policy.write_text(policy_text, encoding="utf-8")

pms_text = pms.read_text(encoding="utf-8")
if "shouldGrantSignaturePermission(Ljava/lang/String;Ljava/lang/String;)Z" in pms_text:
    raise SystemExit("PermissionManagerService already calls Smartisax signature policy")

old = """    move-object/from16 v1, p1

    invoke-virtual/range {p4 .. p4}, Lcom/android/server/pm/permission/BasePermission;->isOEM()Z
"""
new = """    move-object/from16 v1, p1

    invoke-interface/range {p2 .. p2}, Lcom/android/server/pm/parsing/pkg/AndroidPackage;->getPackageName()Ljava/lang/String;

    move-result-object v2

    invoke-static {v1, v2}, Lcom/android/server/pm/SmartisaxPackagePolicy;->shouldGrantSignaturePermission(Ljava/lang/String;Ljava/lang/String;)Z

    move-result v2

    if-eqz v2, :smartisax_sigperm_continue

    const/4 v2, 0x1

    return v2

    :smartisax_sigperm_continue
    invoke-virtual/range {p4 .. p4}, Lcom/android/server/pm/permission/BasePermission;->isOEM()Z
"""
if old not in pms_text:
    raise SystemExit("PermissionManagerService grantSignaturePermission anchor not found")
pms_text = pms_text.replace(old, new, 1)
pms.write_text(pms_text, encoding="utf-8")
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

python3 - "$BASE_SERVICES" "$OUT_JAR" "$VERIFY_DECODED_DIR" "$REPORT" "$VARIANT" "$SMARTISAX_PACKAGE" "$SMARTISAX_PERMISSION" <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

base = Path(sys.argv[1])
out = Path(sys.argv[2])
decoded = Path(sys.argv[3])
report = Path(sys.argv[4])
variant = sys.argv[5]
smartisax_package = sys.argv[6]
smartisax_permission = sys.argv[7]

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

policy = find_one("com/android/server/pm/SmartisaxPackagePolicy.smali")
pms = find_one("com/android/server/pm/permission/PermissionManagerService.smali")
handler = find_one("com/android/server/adb/AdbDebuggingManager$AdbDebuggingHandler.smali")
kg_policy = find_one("com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali")

checks = [
    (policy, "shouldBypassPackageCache"),
    (policy, "/system/priv-app/SmartisaxShell"),
    (policy, "/system/app/TextBoomArm32"),
    (policy, "shouldGrantSignaturePermission"),
    (policy, smartisax_package),
    (policy, smartisax_permission),
    (pms, "Lcom/android/server/pm/SmartisaxPackagePolicy;->shouldGrantSignaturePermission(Ljava/lang/String;Ljava/lang/String;)Z"),
    (pms, "move-result v2"),
    (pms, "return v2"),
    (handler, "__smartisax_current_wifi__"),
    (handler, "Resolved current Wi-Fi BSSID for Smartisax wireless ADB"),
    (kg_policy, "persist.smartisax.skip_keyguard"),
]
for path, needle in checks:
    if needle not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"{path} missing {needle}")

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
    f.write("smartisax_pm1_policy_retained=ok\n")
    f.write("smartisax_current_wifi_policy_retained=ok\n")
    f.write("smartisax_kg1_policy_retained=ok\n")
    f.write(f"smartisax_signature_grant_package={smartisax_package}\n")
    f.write(f"smartisax_signature_grant_permission={smartisax_permission}\n")
    f.write("result=PASS_BUILD_SERVICES_PORTAL23_FRAMEBUFFER_GRANT\n")
PY

cat "$REPORT"
echo "Built: $OUT_JAR"
echo "Report: $REPORT"
