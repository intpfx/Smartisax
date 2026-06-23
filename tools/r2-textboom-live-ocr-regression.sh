#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_ROOT="${OUT_ROOT:-${ROOT_DIR}/hard-rom/inspect/textboom-live-ocr-regression}"
OUT_DIR="${OUT_ROOT}/${RUN_ID}"
REPORT="${OUT_DIR}/regression.md"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
REMOTE_UI_ROOT="/sdcard/Download/textboom-live-ocr-regression-${RUN_ID}"
OCR_IMAGE_PATH="${OCR_IMAGE_PATH:-/sdcard/.boom/imageboom.jpg}"

mkdir -p "$OUT_DIR"

adb_cmd() {
  adb -s "$SERIAL" "$@"
}

root_cmd() {
  "$ROOT_HELPER" cmd "$@" 2>&1 | tr -d '\r'
}

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

section() {
  log ""
  log "## $*"
}

run_shell_file() {
  local out="$1"
  shift
  adb_cmd shell "$@" > "$out" 2>&1 || true
}

capture_focus() {
  local out="$1"
  run_shell_file "$out" 'dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,80p"'
}

capture_screen() {
  local out="$1"
  adb_cmd exec-out screencap -p > "$out"
}

capture_ui() {
  local name="$1"
  local remote="${REMOTE_UI_ROOT}-${name}.xml"
  local local_path="${OUT_DIR}/${name}.xml"
  adb_cmd shell "uiautomator dump '${remote}' >/dev/null 2>&1 && cat '${remote}'" > "$local_path" 2>/dev/null || true
  printf '%s\n' "$local_path"
}

capture_logcat() {
  local name="$1"
  local raw="${OUT_DIR}/${name}.logcat.txt"
  local filtered="${OUT_DIR}/${name}.ocr-filtered.logcat.txt"
  adb_cmd logcat -d -t 3500 > "$raw" 2>/dev/null || true
  LC_ALL=C grep -Ei 'TextBoom|BoomOcrActivity|BoomChipPage|FileUtils|TB_FileUtil|OcrFloatViewService|CsOcr|CSOpenApi|CSOcr|CamScanner|camscanner|ACTION_OCR|RESPONSE_DATA|OCR|PpOcr|onnxruntime|OpenCV|AndroidRuntime|FATAL EXCEPTION|Permission denied|imageboom|Glide' "$raw" > "$filtered" || true
  printf '%s\n' "$filtered"
}

capture_meminfo() {
  local out="$1"
  adb_cmd shell 'dumpsys meminfo com.smartisanos.textboom 2>/dev/null' > "$out" 2>&1 || true
}

remote_image_info() {
  local out="$1"
  {
    echo "path=${OCR_IMAGE_PATH}"
    root_cmd "if [ -e '${OCR_IMAGE_PATH}' ]; then ls -l '${OCR_IMAGE_PATH}'; sha256sum '${OCR_IMAGE_PATH}' 2>/dev/null || toybox sha256sum '${OCR_IMAGE_PATH}'; stat '${OCR_IMAGE_PATH}' 2>/dev/null || toybox stat '${OCR_IMAGE_PATH}' 2>/dev/null; else echo missing; fi"
  } > "$out" 2>&1 || true
}

pull_ocr_image() {
  local out="$1"
  if adb_cmd shell "test -f '${OCR_IMAGE_PATH}'" >/dev/null 2>&1; then
    adb_cmd pull "$OCR_IMAGE_PATH" "$out" >/dev/null 2>&1 || true
  fi
}

sha_file() {
  if [ -f "$1" ]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'missing'
  fi
}

image_dims() {
  if [ ! -f "$1" ]; then
    printf 'missing'
    return
  fi
  python3 - "$1" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
    print(f"{struct.unpack('>I', data[16:20])[0]}x{struct.unpack('>I', data[20:24])[0]}")
    raise SystemExit
if data[:2] == b"\xff\xd8":
    i = 2
    while i + 9 < len(data):
        while i < len(data) and data[i] == 0xff:
            i += 1
        if i >= len(data):
            break
        marker = data[i]
        i += 1
        if marker in (0xd8, 0xd9):
            continue
        if i + 2 > len(data):
            break
        size = struct.unpack(">H", data[i:i + 2])[0]
        if marker in {0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf} and i + 7 < len(data):
            h = struct.unpack(">H", data[i + 3:i + 5])[0]
            w = struct.unpack(">H", data[i + 5:i + 7])[0]
            print(f"{w}x{h}")
            raise SystemExit
        i += size
print("unknown")
PY
}

xml_summary() {
  local xml="$1"
  python3 - "$xml" <<'PY'
from pathlib import Path
import html
import re
import sys

xml = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore") if Path(sys.argv[1]).exists() else ""
values = []
for attr in ("text", "content-desc"):
    values.extend(html.unescape(v) for v in re.findall(attr + r'="([^"]*)"', xml))
values = [v.strip() for v in values if v.strip()]
tokens = [v for v in values if v not in {"大爆炸", "返回", "关闭", "取消"}]
count_text = next((v for v in values if re.search(r"共\s*\d+\s*字", v)), "")
joined = " ".join(tokens)
print("count_text=" + count_text)
print("token_count=" + str(len(tokens)))
print("preview=" + joined[:600].replace("\n", " "))
PY
}

wait_for_result() {
  local case_id="$1"
  local waited=0
  while [ "$waited" -lt 60 ]; do
    local focus="${OUT_DIR}/${case_id}-wait-${waited}s-focus.txt"
    capture_focus "$focus"
    if grep -q 'com.smartisanos.textboom/.BoomActivity' "$focus"; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

setup_home() {
  adb_cmd shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb_cmd shell input keyevent HOME >/dev/null 2>&1 || true
  sleep 2
}

setup_settings() {
  adb_cmd shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb_cmd shell am start -W -a android.settings.SETTINGS >/dev/null 2>&1 || true
  sleep 2
}

setup_textboom_details() {
  adb_cmd shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb_cmd shell am start -W -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.smartisanos.textboom >/dev/null 2>&1 || true
  sleep 2
}

run_case() {
  local case_id="$1"
  local setup_fn="$2"
  local start_x="$3"
  local start_y="$4"
  section "case ${case_id}"
  adb_cmd shell am force-stop com.smartisanos.textboom >/dev/null 2>&1 || true
  sleep 1
  "$setup_fn"

  capture_focus "${OUT_DIR}/${case_id}-00-focus-before.txt"
  capture_screen "${OUT_DIR}/${case_id}-00-before.png"
  capture_ui "${case_id}-00-before" >/dev/null
  remote_image_info "${OUT_DIR}/${case_id}-00-imageboom-before.txt"
  pull_ocr_image "${OUT_DIR}/${case_id}-00-imageboom-before.jpg"
  local before_sha before_dims
  before_sha="$(sha_file "${OUT_DIR}/${case_id}-00-imageboom-before.jpg")"
  before_dims="$(image_dims "${OUT_DIR}/${case_id}-00-imageboom-before.jpg")"

  adb_cmd logcat -c >/dev/null 2>&1 || true
  local start_epoch end_epoch
  start_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"
  adb_cmd shell am start -W \
    -a smartisanos.intent.action.BOOM_IMAGE \
    --ei boom_startx "$start_x" \
    --ei boom_starty "$start_y" \
    --ei boom_offsetx 0 \
    --ei boom_offsety 0 \
    --ez boom_fullscreen false \
    --ez boom_from_float false \
    --es caller_pkg com.smartisax.browser \
    > "${OUT_DIR}/${case_id}-01-am-start.txt" 2>&1 || true
  local launch_activity launch_state launch_warning
  launch_activity="$(awk -F': ' '/^Activity:/ {print $2; exit}' "${OUT_DIR}/${case_id}-01-am-start.txt")"
  launch_state="$(awk -F': ' '/^LaunchState:/ {print $2; exit}' "${OUT_DIR}/${case_id}-01-am-start.txt")"
  launch_warning="$(awk '/^Warning:/ {print; exit}' "${OUT_DIR}/${case_id}-01-am-start.txt")"

  sleep 3
  capture_focus "${OUT_DIR}/${case_id}-02-focus-crop.txt"
  capture_screen "${OUT_DIR}/${case_id}-02-crop.png"
  capture_ui "${case_id}-02-crop" >/dev/null

  # TextBoom's crop confirm button is stable on the R2 1080x2340 layout.
  adb_cmd shell input tap 936 2280 >/dev/null 2>&1 || true
  wait_for_result "$case_id" || true
  sleep 2
  end_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

  capture_focus "${OUT_DIR}/${case_id}-03-focus-result.txt"
  capture_screen "${OUT_DIR}/${case_id}-03-result.png"
  local result_xml
  result_xml="$(capture_ui "${case_id}-03-result")"
  capture_meminfo "${OUT_DIR}/${case_id}-03-textboom-meminfo.txt"
  local logcat_file
  logcat_file="$(capture_logcat "${case_id}-03-result")"
  remote_image_info "${OUT_DIR}/${case_id}-03-imageboom-after.txt"
  pull_ocr_image "${OUT_DIR}/${case_id}-03-imageboom-after.jpg"

  local after_sha after_dims result_elapsed_ms mem_total_pss mem_native_heap mem_graphics fatal_count unsatisfied_count denied_count imageboom_mentions
  after_sha="$(sha_file "${OUT_DIR}/${case_id}-03-imageboom-after.jpg")"
  after_dims="$(image_dims "${OUT_DIR}/${case_id}-03-imageboom-after.jpg")"
  result_elapsed_ms="$(python3 - "$start_epoch" "$end_epoch" <<'PY'
import sys
print(round((float(sys.argv[2]) - float(sys.argv[1])) * 1000))
PY
)"
  mem_total_pss="$(awk '/TOTAL PSS:/ {print $3; exit}' "${OUT_DIR}/${case_id}-03-textboom-meminfo.txt")"
  mem_native_heap="$(awk '/Native Heap/ {print $3; exit}' "${OUT_DIR}/${case_id}-03-textboom-meminfo.txt")"
  mem_graphics="$(awk '/Graphics/ {print $2; exit}' "${OUT_DIR}/${case_id}-03-textboom-meminfo.txt")"
  fatal_count="$(grep -Eic 'FATAL EXCEPTION|AndroidRuntime.*FATAL|UnsatisfiedLinkError' "$logcat_file" || true)"
  unsatisfied_count="$(grep -Eic 'UnsatisfiedLink|libopencv_java4.so not found|dlopen failed' "$logcat_file" || true)"
  denied_count="$(grep -Eic 'Permission denied' "$logcat_file" || true)"
  imageboom_mentions="$(grep -Eic 'imageboom|/sdcard/.boom|TB_FileUtil|FileUtils' "$logcat_file" || true)"

  {
    echo "case_id=${case_id}"
    echo "start_x=${start_x}"
    echo "start_y=${start_y}"
    echo "launch_activity=${launch_activity:-}"
    echo "launch_state=${launch_state:-}"
    echo "launch_warning=${launch_warning:-}"
    echo "wall_elapsed_ms=${result_elapsed_ms}"
    echo "before_image_sha256=${before_sha}"
    echo "before_image_dims=${before_dims}"
    echo "after_image_sha256=${after_sha}"
    echo "after_image_dims=${after_dims}"
    echo "image_file_changed=$([ "$before_sha" != "$after_sha" ] && echo yes || echo no)"
    echo "mem_total_pss_kb=${mem_total_pss:-}"
    echo "mem_native_heap_pss_kb=${mem_native_heap:-}"
    echo "mem_graphics_pss_kb=${mem_graphics:-}"
    echo "fatal_marker_count=${fatal_count}"
    echo "unsatisfied_link_marker_count=${unsatisfied_count}"
    echo "permission_denied_marker_count=${denied_count}"
    echo "imageboom_log_mentions=${imageboom_mentions}"
    xml_summary "$result_xml"
  } > "${OUT_DIR}/${case_id}-summary.txt"

  cat "${OUT_DIR}/${case_id}-summary.txt" | tee -a "$REPORT"
  adb_cmd shell input keyevent BACK >/dev/null 2>&1 || true
  sleep 1
}

: > "$REPORT"
log "# TextBoom live OCR regression ${RUN_ID}"
log ""
log "Boundary: force-stops the TextBoom process between cases, launches existing system TextBoom BOOM_IMAGE, and reads logs, screenshots, meminfo, and ${OCR_IMAGE_PATH}. No flash, reboot, erase, install, uninstall, package data cleanup, or ROM mutation."

section "device"
adb_cmd wait-for-device
adb_cmd devices -l | tee -a "$REPORT"
adb_cmd shell 'echo slot=$(getprop ro.boot.slot_suffix); echo boot=$(getprop sys.boot_completed); echo build=$(getprop ro.smartisan.version); echo android=$(getprop ro.build.version.release)' | tee -a "$REPORT"
capture_focus "${OUT_DIR}/device-focus-before.txt"
cat "${OUT_DIR}/device-focus-before.txt" | tee -a "$REPORT"
if grep -Eq 'isKeyguardShowing=true|mShowingLockscreen=true' "${OUT_DIR}/device-focus-before.txt"; then
  log "result=BLOCKED_KEYGUARD"
  exit 3
fi

run_case "smartisax_home" setup_home 540 1170
run_case "settings_main" setup_settings 540 1170
run_case "textboom_app_details" setup_textboom_details 540 1170

python3 - "$OUT_DIR" <<'PY'
from pathlib import Path
import json
import re
import sys

out_dir = Path(sys.argv[1])
cases = []
for path in sorted(out_dir.glob("*-summary.txt")):
    data = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key] = value
    cases.append(data)

def as_int(value):
    try:
        return int(value)
    except Exception:
        return None

latencies = [as_int(c.get("wall_elapsed_ms")) for c in cases]
latencies = [v for v in latencies if v is not None]
pss = [as_int(c.get("mem_total_pss_kb")) for c in cases]
pss = [v for v in pss if v is not None]
aggregate = {
    "kind": "textboom-live-ocr-regression",
    "case_count": len(cases),
    "cases": cases,
    "summary": {
        "max_wall_elapsed_ms": max(latencies) if latencies else None,
        "max_textboom_total_pss_kb": max(pss) if pss else None,
        "fatal_marker_count": sum(as_int(c.get("fatal_marker_count")) or 0 for c in cases),
        "unsatisfied_link_marker_count": sum(as_int(c.get("unsatisfied_link_marker_count")) or 0 for c in cases),
        "permission_denied_marker_count": sum(as_int(c.get("permission_denied_marker_count")) or 0 for c in cases),
        "unchanged_image_file_cases": [c.get("case_id") for c in cases if c.get("image_file_changed") == "no"],
    },
}
(out_dir / "regression-summary.json").write_text(json.dumps(aggregate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
with (out_dir / "summary.tsv").open("w", encoding="utf-8") as fh:
    fh.write("case_id\tlaunch_activity\tlaunch_state\tlaunch_warning\twall_elapsed_ms\timage_file_changed\tbefore_sha\tafter_sha\tafter_dims\tmem_total_pss_kb\tpermission_denied\tfatal\tunsatisfied\ttoken_count\tcount_text\n")
    for c in cases:
        fh.write("\t".join([
            c.get("case_id", ""),
            c.get("launch_activity", ""),
            c.get("launch_state", ""),
            c.get("launch_warning", ""),
            c.get("wall_elapsed_ms", ""),
            c.get("image_file_changed", ""),
            c.get("before_image_sha256", ""),
            c.get("after_image_sha256", ""),
            c.get("after_image_dims", ""),
            c.get("mem_total_pss_kb", ""),
            c.get("permission_denied_marker_count", ""),
            c.get("fatal_marker_count", ""),
            c.get("unsatisfied_link_marker_count", ""),
            c.get("token_count", ""),
            c.get("count_text", ""),
        ]) + "\n")
print(out_dir / "regression-summary.json")
PY

section "aggregate"
cat "${OUT_DIR}/summary.tsv" | tee -a "$REPORT"
log "result=CAPTURED_TEXTBOOM_LIVE_OCR_REGRESSION"
log "out_dir=${OUT_DIR}"
