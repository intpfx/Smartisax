#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.kg1-smartisax-skip-keyguard}"
JAVA_BIN="${JAVA_BIN:-${ROOT_DIR}/third_party/_downloads/jdk/temurin-17/Contents/Home/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
ZIPALIGN="${ZIPALIGN:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/zipalign}"
DEXDUMP="${DEXDUMP:-${ROOT_DIR}/third_party/android-sdk/build-tools/35.0.1/dexdump}"
BASE_SERVICES="${BASE_SERVICES:-${ROOT_DIR}/hard-rom/build/framework/services-pm1-cache-allowlist.jar}"

WORK_DIR="${WORK_DIR:-${ROOT_DIR}/hard-rom/work/${VARIANT}/services}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/build/framework}"
INSPECT_DIR="${INSPECT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}}"
DECODED_DIR="${WORK_DIR}/decoded"
VERIFY_DECODED_DIR="${WORK_DIR}/verify-decoded"
REBUILT_JAR="${WORK_DIR}/services-apktool-kg1.jar"
MERGED_JAR="${WORK_DIR}/services-kg1-stock-shell-dex.jar"
OUT_JAR="${OUT_JAR:-${OUT_DIR}/services-kg1-smartisax-skip-keyguard.jar}"
REPORT="${INSPECT_DIR}/services-kg1-smartisax-skip-keyguard-report.txt"

BASE_SERVICES_SHA256="84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-services-kg1-skip-keyguard-jar.sh

Builds a services.jar candidate for v0.kg1-smartisax-skip-keyguard. It starts
from the live-proven v0.pm1 services.jar and adds only:

  - com.android.server.policy.keyguard.SmartisaxKeyguardPolicy
  - a KeyguardServiceDelegate$1.onServiceConnected policy hook that sets the
    delegate state to disabled, then lets the stock wrapper call
    setKeyguardEnabled(false).

The stock Smartisan Keyguard still refuses disabling when a secure keyguard or
SIM PIN is active. This script does not build an image, flash, reboot, or touch
a live device.
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
  || die "base services.jar hash mismatch; expected live-proven v0.pm1 jar"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR" "$INSPECT_DIR"
rm -f "$OUT_JAR" "$REPORT"

echo "Decoding base services.jar..."
"$JAVA_BIN" -jar "$APKTOOL" d -f -o "$DECODED_DIR" "$BASE_SERVICES" >/dev/null

echo "Applying Smartisax Keyguard skip policy..."
python3 - "$DECODED_DIR" <<'PY'
from pathlib import Path
import sys

decoded = Path(sys.argv[1])
keyguard_dir = decoded / "smali_classes2" / "com" / "android" / "server" / "policy" / "keyguard"
delegate_connection = keyguard_dir / "KeyguardServiceDelegate$1.smali"
policy = keyguard_dir / "SmartisaxKeyguardPolicy.smali"

old = """    .line 227
    :cond_9
    iget-object v0, p0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$1;->this$0:Lcom/android/server/policy/keyguard/KeyguardServiceDelegate;

    iget-object v0, v0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate;->mKeyguardState:Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$KeyguardState;
"""

new = """    .line 227
    :cond_9
    invoke-static {}, Lcom/android/server/policy/keyguard/SmartisaxKeyguardPolicy;->shouldDisableKeyguardAfterBoot()Z

    move-result v0

    if-eqz v0, :smartisax_skip_keyguard_done

    iget-object v0, p0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$1;->this$0:Lcom/android/server/policy/keyguard/KeyguardServiceDelegate;

    iget-object v0, v0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate;->mKeyguardState:Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$KeyguardState;

    const/4 v1, 0x0

    iput-boolean v1, v0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$KeyguardState;->enabled:Z

    const-string v0, "SmartisaxKeyguard"

    const-string v1, "Disable keyguard through stock setKeyguardEnabled path"

    invoke-static {v0, v1}, Landroid/util/Slog;->i(Ljava/lang/String;Ljava/lang/String;)I

    :smartisax_skip_keyguard_done
    iget-object v0, p0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$1;->this$0:Lcom/android/server/policy/keyguard/KeyguardServiceDelegate;

    iget-object v0, v0, Lcom/android/server/policy/keyguard/KeyguardServiceDelegate;->mKeyguardState:Lcom/android/server/policy/keyguard/KeyguardServiceDelegate$KeyguardState;
"""

text = delegate_connection.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit("KeyguardServiceDelegate$1 onServiceConnected hook point did not match expected v0.pm1 base")
delegate_connection.write_text(text.replace(old, new), encoding="utf-8")

policy.write_text(""".class public final Lcom/android/server/policy/keyguard/SmartisaxKeyguardPolicy;
.super Ljava/lang/Object;
.source "SmartisaxKeyguardPolicy.java"


# direct methods
.method private constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static shouldDisableKeyguardAfterBoot()Z
    .locals 2

    const-string v0, "persist.smartisax.skip_keyguard"

    const/4 v1, 0x1

    invoke-static {v0, v1}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

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

pm_policy = find_one(decoded, "com/android/server/pm/SmartisaxPackagePolicy.smali")
pm_parser = find_one(decoded, "com/android/server/pm/ParallelPackageParser.smali")
kg_policy = find_one(decoded, "com/android/server/policy/keyguard/SmartisaxKeyguardPolicy.smali")
kg_connection = find_one(decoded, "com/android/server/policy/keyguard/KeyguardServiceDelegate$1.smali")

checks = [
    (pm_policy, "shouldBypassPackageCache"),
    (pm_parser, "SmartisaxPackagePolicy;->shouldBypassPackageCache"),
    (kg_policy, "persist.smartisax.skip_keyguard"),
    (kg_policy, "shouldDisableKeyguardAfterBoot"),
    (kg_connection, "SmartisaxKeyguardPolicy;->shouldDisableKeyguardAfterBoot"),
    (kg_connection, "Disable keyguard through stock setKeyguardEnabled path"),
    (kg_connection, "KeyguardServiceWrapper;->setKeyguardEnabled"),
]
for path, needle in checks:
    if needle not in path.read_text(encoding="utf-8"):
        raise SystemExit(f"{path} missing {needle}")

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
    f.write("pm1_policy_retained=true\n")
    f.write("helper_class=com.android.server.policy.keyguard.SmartisaxKeyguardPolicy\n")
    f.write("patched_call=com.android.server.policy.keyguard.KeyguardServiceDelegate$1.onServiceConnected\n")
    f.write("runtime_switch=persist.smartisax.skip_keyguard default true\n")
    f.write("stock_security_guard=KeyguardViewMediator.setKeyguardEnabled refuses disable when secure\n")
    for name in ["classes.dex", "classes2.dex"]:
        f.write(f"{name}.base_sha256={base_entries[name]['sha256']}\n")
        f.write(f"{name}.output_sha256={out_entries[name]['sha256']}\n")
        f.write(f"{name}.base_size={base_entries[name]['size']}\n")
        f.write(f"{name}.output_size={out_entries[name]['size']}\n")
PY

{
  echo "services_kg1_skip_keyguard_jar=ok"
  echo "variant=${VARIANT}"
  echo "base=${BASE_SERVICES}"
  echo "output=${OUT_JAR}"
  echo "sha256=$(sha256_one "$OUT_JAR")"
  echo "report=${REPORT}"
} | tee -a "$REPORT"
