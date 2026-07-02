#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
V2_PRESERVER="${V2_PRESERVER:-${ROOT_DIR}/tools/r2-apk-preserve-v2-signing-block.py}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.agent0.7-window-preflight.img}"
SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-4c1cee130f776f3fe83340dbef7592cc56ea4e37446aefa548f5cf3f378bc892}"
SIDEBAR_IMAGE_PATH="/system/priv-app/Sidebar/Sidebar.apk"

OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/sidebar-onestep-a11y-apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
BASE_APK="${WORK_DIR}/base-current-sidebar.apk"
OUT_RAW_APK="${OUT_RAW_APK:-${OUT_DIR}/com.smartisanos.sidebar-onestep-a11y.apk}"
OUT_V2_APK="${OUT_V2_APK:-${OUT_DIR}/com.smartisanos.sidebar-onestep-a11y-v2cert.apk}"
MANIFEST="${MANIFEST:-${OUT_DIR}/sidebar-onestep-a11y-apk-manifest.tsv}"
SIG_REPORT="${SIG_REPORT:-${OUT_DIR}/com.smartisanos.sidebar-onestep-a11y.signature.txt}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-sidebar-onestep-a11y-apk.sh

Build a Sidebar APK candidate from the current v0.agent0.7 system_b image that
adds Agent-friendly Accessibility semantics to the dynamic One Step app strip.
Each bound AppItem view gets a contentDescription carrying label/package/
component/user/id metadata and a real View.OnClickListener that opens that same
AppItem. Only classes.dex changes; the script does not flash, reboot, or touch
a live device.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

install_frameworks() {
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

dump_current_sidebar() {
  rm -f "$BASE_APK"
  "$DEBUGFS" -R "dump ${SIDEBAR_IMAGE_PATH} ${BASE_APK}" "$SOURCE_SYSTEM_B" >/dev/null 2>&1
  need_file "$BASE_APK"
  unzip -t "$BASE_APK" >/dev/null
}

patch_smali_agent_nodes() {
  local decoded_dir="$1"
  "$PYTHON_BIN" - "$decoded_dir" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
matches = [
    p for p in root.rglob("AppListAdapter.smali")
    if p.as_posix().endswith("/com/smartisanos/sidebar/toparea/view/AppListAdapter.smali")
]
if len(matches) != 1:
    raise SystemExit(f"expected one AppListAdapter.smali, found {len(matches)}")
adapter = matches[0]
listener = adapter.with_name("AppListAdapter$AgentAppClickListener.smali")

text = adapter.read_text(encoding="utf-8")
if "bindSmartisaxAgentAccessibility" in text or listener.exists():
    raise SystemExit("Smartisax Agent Accessibility patch already present")

needle = (
    "    invoke-direct {p0, p1, p2}, "
    "Lcom/smartisanos/sidebar/toparea/view/AppListAdapter;->setIconImage"
    "(Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$ViewHolder;"
    "Lcom/smartisanos/sidebar/util/AppItem;)V\n"
)
insert = (
    needle
    + "\n"
    + "    iget-object v0, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter;->mContext:Landroid/content/Context;\n"
    + "\n"
    + "    invoke-static {p1, p2, v0}, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter;->bindSmartisaxAgentAccessibility(Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$ViewHolder;Lcom/smartisanos/sidebar/util/AppItem;Landroid/content/Context;)V\n"
)
if text.count(needle) != 1:
    raise SystemExit("failed to find unique setIconImage call in onBindViewHolder")
text = text.replace(needle, insert, 1)

helper = r'''
.method private static bindSmartisaxAgentAccessibility(Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$ViewHolder;Lcom/smartisanos/sidebar/util/AppItem;Landroid/content/Context;)V
    .locals 4

    iget-object v0, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$ViewHolder;->itemView:Landroid/view/View;

    if-eqz v0, :cond_0

    const-string v1, "smartisax:onestep:app|label="

    new-instance v2, Ljava/lang/StringBuilder;

    invoke-direct {v2, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {p1}, Lcom/smartisanos/sidebar/util/SidebarItem;->getDisplayName()Ljava/lang/CharSequence;

    move-result-object v1

    invoke-static {v1}, Ljava/lang/String;->valueOf(Ljava/lang/Object;)Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v1, "|package="

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {p1}, Lcom/smartisanos/sidebar/util/AppItem;->getPackageName()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v1, "|component="

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {p1}, Lcom/smartisanos/sidebar/util/AppItem;->getComponentName()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v1, "|user="

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {p1}, Lcom/smartisanos/sidebar/util/AppItem;->getUserId()I

    move-result v1

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v1, "|id="

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {p1}, Lcom/smartisanos/sidebar/util/AppItem;->getSimpleId()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v0, v1}, Landroid/view/View;->setContentDescription(Ljava/lang/CharSequence;)V

    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Landroid/view/View;->setImportantForAccessibility(I)V

    invoke-virtual {v0, v1}, Landroid/view/View;->setClickable(Z)V

    new-instance v1, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;

    invoke-direct {v1, p2, p1}, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;-><init>(Landroid/content/Context;Lcom/smartisanos/sidebar/util/AppItem;)V

    invoke-virtual {v0, v1}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V

    :cond_0
    return-void
.end method
'''
marker = "\n\n# virtual methods\n"
if marker not in text:
    raise SystemExit("failed to find virtual-method marker")
text = text.replace(marker, "\n" + helper + marker, 1)
adapter.write_text(text, encoding="utf-8")

listener.write_text(r'''.class public Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;
.super Ljava/lang/Object;
.source "AppListAdapter.java"

# interfaces
.implements Landroid/view/View$OnClickListener;


# annotations
.annotation system Ldalvik/annotation/EnclosingClass;
    value = Lcom/smartisanos/sidebar/toparea/view/AppListAdapter;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x9
    name = "AgentAppClickListener"
.end annotation


# instance fields
.field private final mContext:Landroid/content/Context;

.field private final mItem:Lcom/smartisanos/sidebar/util/AppItem;


# direct methods
.method public constructor <init>(Landroid/content/Context;Lcom/smartisanos/sidebar/util/AppItem;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;->mContext:Landroid/content/Context;

    iput-object p2, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;->mItem:Lcom/smartisanos/sidebar/util/AppItem;

    return-void
.end method


# virtual methods
.method public onClick(Landroid/view/View;)V
    .locals 4

    iget-object v0, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;->mContext:Landroid/content/Context;

    invoke-static {v0}, Lcom/smartisanos/sidebar/util/Utils;->dismissAllDialog(Landroid/content/Context;)V

    iget-object v0, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;->mItem:Lcom/smartisanos/sidebar/util/AppItem;

    iget-object v1, p0, Lcom/smartisanos/sidebar/toparea/view/AppListAdapter$AgentAppClickListener;->mContext:Landroid/content/Context;

    invoke-virtual {v0, v1}, Lcom/smartisanos/sidebar/util/AppItem;->openUI(Landroid/content/Context;)Z

    const/4 v1, 0x2

    new-array v1, v1, [Ljava/lang/Object;

    const/4 v2, 0x0

    const-string v3, "package"

    aput-object v3, v1, v2

    const/4 v2, 0x1

    invoke-virtual {v0}, Lcom/smartisanos/sidebar/util/AppItem;->getPackageName()Ljava/lang/String;

    move-result-object v0

    aput-object v0, v1, v2

    const-string v0, "0009"

    invoke-static {v0, v1}, Lcom/smartisanos/sidebar/util/Tracker;->onEvent(Ljava/lang/String;[Ljava/lang/Object;)V

    return-void
.end method
''', encoding="utf-8")

print(f"patched_adapter={adapter}")
print(f"added_listener={listener}")
PY
}

merge_classes_into_shell() {
  local base_apk="$1"
  local rebuilt_apk="$2"
  local out_apk="$3"
  local tmp
  tmp="$(mktemp -d "/tmp/r2-sidebar-onestep-a11y.XXXXXX")"
  unzip -p "$rebuilt_apk" classes.dex > "${tmp}/classes.dex"
  touch -t 200901010000 "${tmp}/classes.dex"
  cp "$base_apk" "${out_apk}.tmp"
  (
    cd "$tmp"
    zip -X -q "${out_apk}.tmp" classes.dex
  )
  mv "${out_apk}.tmp" "$out_apk"
  rm -rf "$tmp"
}

verify_zip_scope() {
  local base_apk="$1"
  local out_apk="$2"
  "$PYTHON_BIN" - "$base_apk" "$out_apk" <<'PY'
from __future__ import annotations

import hashlib
import sys
import zipfile

base, out = sys.argv[1:]

def members(path: str) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as zf:
        return {info.filename: zf.read(info.filename) for info in zf.infolist() if not info.is_dir()}

base_members = members(base)
out_members = members(out)
if set(base_members) != set(out_members):
    missing = sorted(set(base_members) - set(out_members))
    extra = sorted(set(out_members) - set(base_members))
    raise SystemExit(f"member set changed missing={missing[:10]} extra={extra[:10]}")

changed = sorted(
    name for name in base_members
    if hashlib.sha256(base_members[name]).digest() != hashlib.sha256(out_members[name]).digest()
)
if changed != ["classes.dex"]:
    raise SystemExit(f"unexpected changed members: {changed}")

print("changed_members=classes.dex")
print(f"base_classes_sha256={hashlib.sha256(base_members['classes.dex']).hexdigest()}")
print(f"out_classes_sha256={hashlib.sha256(out_members['classes.dex']).hexdigest()}")
PY
}

verify_decoded_output() {
  local apk="$1"
  local check_dir="$2"
  rm -rf "$check_dir"
  mkdir -p "$check_dir"
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${check_dir}/decoded" "$apk" >/dev/null

  grep -q 'package="com.smartisanos.sidebar"' "${check_dir}/decoded/AndroidManifest.xml" \
    || die "Sidebar package identity changed"
  grep -R -q 'smartisax:onestep:app' "${check_dir}/decoded/smali" \
    || die "Agent app strip contentDescription marker missing"
  grep -R -q 'bindSmartisaxAgentAccessibility' "${check_dir}/decoded/smali" \
    || die "Agent accessibility bind helper missing"
  grep -R -q 'setContentDescription' "${check_dir}/decoded/smali" \
    || die "contentDescription setter missing"
  grep -R -q 'setImportantForAccessibility' "${check_dir}/decoded/smali" \
    || die "importantForAccessibility setter missing"
  grep -R -q 'setOnClickListener' "${check_dir}/decoded/smali" \
    || die "OnClickListener binding missing"
  grep -R -q 'AppListAdapter\$AgentAppClickListener' "${check_dir}/decoded/smali" \
    || die "Agent app click listener class missing"
  grep -R -q 'openUI(Landroid/content/Context;)Z' "${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/AppListAdapter\$AgentAppClickListener.smali" \
    || die "Agent click listener does not call AppItem.openUI"
  grep -R -q 'dismissAllDialog' "${check_dir}/decoded/smali/com/smartisanos/sidebar/toparea/view/AppListAdapter\$AgentAppClickListener.smali" \
    || die "Agent click listener does not dismiss One Step dialogs"

  echo "agent_onestep_app_nodes=ok"
  echo "agent_onestep_app_click_listener=ok"
}

case "${1:-}" in
  "") ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

need_file "$JAVA_BIN"
need_file "$APKTOOL"
need_executable "$DEBUGFS"
need_executable "$V2_PRESERVER"
need_executable "$SIGCHECK"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
require_hash "$SOURCE_SYSTEM_B" "$SOURCE_SYSTEM_B_SHA256"

mkdir -p "$OUT_DIR" "$WORK_DIR"
rm -rf "${WORK_DIR}/decoded" "${WORK_DIR}/check" "${WORK_DIR}/rebuilt.apk"
rm -f "$BASE_APK" "$OUT_RAW_APK" "$OUT_V2_APK" "$MANIFEST" "$SIG_REPORT"

install_frameworks
echo "Dumping current Sidebar APK from ${SOURCE_SYSTEM_B}..."
dump_current_sidebar

echo "Decoding current Sidebar APK..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "${WORK_DIR}/decoded" "$BASE_APK" >/dev/null

echo "Patching dynamic One Step app strip Accessibility semantics..."
patch_smali_agent_nodes "${WORK_DIR}/decoded"

echo "Rebuilding patched Sidebar classes..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "${WORK_DIR}/rebuilt.apk" "${WORK_DIR}/decoded" >/dev/null

echo "Merging patched classes.dex into current Sidebar APK shell..."
merge_classes_into_shell "$BASE_APK" "${WORK_DIR}/rebuilt.apk" "$OUT_RAW_APK"
verify_zip_scope "$BASE_APK" "$OUT_RAW_APK"

echo "Copying current APK v2/v3 signing block into patched Sidebar APK..."
"$V2_PRESERVER" --stock "$BASE_APK" --edited "$OUT_RAW_APK" --out "$OUT_V2_APK" >/dev/null

echo "Verifying decoded output semantics..."
verify_decoded_output "$OUT_V2_APK" "${WORK_DIR}/check"

echo "Recording signature boundary..."
"$SIGCHECK" "$OUT_V2_APK" > "$SIG_REPORT"
grep -q '^apk_sig_block_magic=present$' "$SIG_REPORT" \
  || die "expected copied APK Sig Block 42 in ${OUT_V2_APK}"
grep -q '^keytool_status=1$' "$SIG_REPORT" \
  || die "expected keytool digest-boundary status for modified Sidebar APK"

base_hash="$(sha256_one "$BASE_APK")"
out_raw_hash="$(sha256_one "$OUT_RAW_APK")"
out_v2_hash="$(sha256_one "$OUT_V2_APK")"

{
  echo "variant=v0.agent0.8-onestep-a11y-nodes-apk"
  echo "purpose=Bind One Step top app strip Accessibility semantics to dynamic AppItem metadata and route ACTION_CLICK to AppItem.openUI"
  echo "source_system_b=${SOURCE_SYSTEM_B}"
  echo "source_system_b_sha256=${SOURCE_SYSTEM_B_SHA256}"
  echo "source_apk_path=${SIDEBAR_IMAGE_PATH}"
  echo "base_apk=${BASE_APK}"
  echo "base_apk_sha256=${base_hash}"
  echo "out_raw_apk=${OUT_RAW_APK}"
  echo "out_raw_sha256=${out_raw_hash}"
  echo "out_v2_apk=${OUT_V2_APK}"
  echo "out_v2_sha256=${out_v2_hash}"
  echo "changed_members=classes.dex"
  echo "signature_report=${SIG_REPORT}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_V2_APK" "$OUT_RAW_APK" "$BASE_APK" "$SOURCE_SYSTEM_B"
} > "$MANIFEST"

echo "Built: ${OUT_V2_APK}"
echo "Manifest: ${MANIFEST}"
echo "Signature report: ${SIG_REPORT}"
echo "Flash gate: APK-only artifact; ROM build and explicit flash confirmation are still required."
