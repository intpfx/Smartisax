#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

SERIAL="${SERIAL:-bb12d264}"
PACKAGE="com.smartisax.ocrbench.officialbench"
ACTIVITY="${PACKAGE}/.CamScannerBaselineActivity"
APK="${APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoomPpOcrOfficialBench.apk}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
INSTALL_MODE="${INSTALL_MODE:-pm}"
DEVICE_ROOT="/sdcard/Android/data/${PACKAGE}/files"
OUT_ROOT="${OUT_ROOT:-${ROOT_DIR}/hard-rom/inspect/textboom-csocr-baseline-live}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${OUT_ROOT}/${RUN_ID}"
DEFAULT_SAMPLE="${ROOT_DIR}/hard-rom/inspect/textboom-ppocr-live-capture/20260620-230945-unlocked-boom-image/device-files/imageboom.jpg"

usage() {
  cat <<USAGE
Usage:
  tools/r2-textboom-csocr-baseline-live.sh [sample-image ...]

Environment:
  SERIAL=bb12d264
  APK=${APK}
  SKIP_INSTALL=0|1
  INSTALL_MODE=pm|adb
  RUN_ID=<stable-run-id>

Boundary:
  Installs or reuses the standalone benchmark APK, pushes sample images into
  the app-specific external files directory, invokes CamScanner ACTION_OCR via
  the benchmark APK, pulls raw RESPONSE_DATA JSON, and captures meminfo/logcat.
  It does not modify TextBoom, ROM images, system packages, boot state, or
  package data outside this benchmark APK's app-specific files.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

adb_cmd() {
  adb -s "$SERIAL" "$@"
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

sample_id_for_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys
stem = Path(sys.argv[1]).stem
print(re.sub(r"[^A-Za-z0-9_.-]+", "-", stem).strip("-") or "sample")
PY
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, dotted = sys.argv[1], sys.argv[2]
value = json.load(open(path, encoding="utf-8"))
for part in dotted.split("."):
    if part.isdigit():
        value = value[int(part)]
    else:
        value = value[part]
print(value)
PY
}

need_file "$APK"
if [ "$#" -eq 0 ]; then
  samples=("$DEFAULT_SAMPLE")
else
  samples=("$@")
fi
for sample in "${samples[@]}"; do
  need_file "$sample"
done

mkdir -p "$OUT_DIR"

{
  echo "run_id=${RUN_ID}"
  echo "serial=${SERIAL}"
  echo "package=${PACKAGE}"
  echo "activity=${ACTIVITY}"
  echo "apk=${APK}"
  echo "skip_install=${SKIP_INSTALL}"
  echo "install_mode=${INSTALL_MODE}"
  echo "device_root=${DEVICE_ROOT}"
  echo "out_dir=${OUT_DIR}"
  echo "boundary=standalone CamScanner baseline; no TextBoom/ROM/flash/reboot/erase/data-cleanup mutation"
  printf 'sample=%s\n' "${samples[@]}"
} > "${OUT_DIR}/run.txt"

echo "Waiting for device ${SERIAL}..."
adb_cmd wait-for-device
adb_cmd shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; id' > "${OUT_DIR}/device-state-before.txt"

if [ "$SKIP_INSTALL" = "1" ]; then
  echo "Skipping install; verifying ${PACKAGE} is already present..."
  adb_cmd shell "pm path '${PACKAGE}'" | tee "${OUT_DIR}/adb-install.txt"
  grep -q '^package:' "${OUT_DIR}/adb-install.txt" || die "${PACKAGE} is not installed"
else
  echo "Installing ${APK}..."
  if [ "$INSTALL_MODE" = "pm" ]; then
    remote_apk="/data/local/tmp/${PACKAGE}.apk"
    adb_cmd push "$APK" "$remote_apk" | tee "${OUT_DIR}/adb-install.txt"
    adb_cmd shell "pm install -r '${remote_apk}'; rm -f '${remote_apk}'" | tee -a "${OUT_DIR}/adb-install.txt"
  else
    adb_cmd install -r "$APK" | tee "${OUT_DIR}/adb-install.txt"
  fi
fi

adb_cmd shell "mkdir -p '${DEVICE_ROOT}/input' '${DEVICE_ROOT}/results'"
result_paths=()

for sample in "${samples[@]}"; do
  sample_id="$(sample_id_for_path "$sample")"
  suffix="${sample##*.}"
  device_input="${DEVICE_ROOT}/input/${sample_id}.${suffix}"
  device_result="${DEVICE_ROOT}/results/${sample_id}.csocr.json"
  sample_dir="${OUT_DIR}/${sample_id}"
  mkdir -p "$sample_dir"

  {
    echo "sample_id=${sample_id}"
    echo "sample=${sample}"
    echo "device_input=${device_input}"
    echo "device_result=${device_result}"
  } > "${sample_dir}/run.txt"

  echo "Running CamScanner baseline for ${sample_id}..."
  adb_cmd push "$sample" "$device_input" | tee "${sample_dir}/adb-push.txt"
  adb_cmd shell "rm -f '${device_result}'"
  adb_cmd shell logcat -c || true
  adb_cmd shell "am force-stop '${PACKAGE}'" || true
  adb_cmd shell am start -W \
    -n "$ACTIVITY" \
    --es sample_id "$sample_id" \
    --es image_path "$device_input" \
    --es result_path "$device_result" | tee "${sample_dir}/am-start.txt"

  for _attempt in $(seq 1 180); do
    if adb_cmd shell "test -f '${device_result}'"; then
      break
    fi
    sleep 1
  done

  adb_cmd shell "ls -l '${device_result}'" > "${sample_dir}/device-result-ls.txt"
  adb_cmd pull "$device_result" "${sample_dir}/result.json" | tee "${sample_dir}/adb-pull.txt"
  adb_cmd shell "dumpsys meminfo '${PACKAGE}'" > "${sample_dir}/meminfo-${PACKAGE}.txt" || true
  adb_cmd shell "dumpsys meminfo com.intsig.camscanner" > "${sample_dir}/meminfo-com.intsig.camscanner.txt" || true
  adb_cmd shell logcat -d -t 1000 > "${sample_dir}/logcat-tail.txt" || true
  adb_cmd shell "logcat -d -t 1000 | grep -Ei 'SmartisaxCsOcrBaseline|CamScanner|CSOpenApi|ACTION_OCR|RESPONSE_DATA|OcrJson|AndroidRuntime|FATAL EXCEPTION'" > "${sample_dir}/logcat-csocr.txt" || true

  result_status="$(json_get "${sample_dir}/result.json" "result")"
  line_count="$(json_get "${sample_dir}/result.json" "samples.0.csocr.line_count")"
  latency_ms="$(json_get "${sample_dir}/result.json" "samples.0.latency_ms")"
  echo "${sample_id} result=${result_status} line_count=${line_count} latency_ms=${latency_ms}" | tee "${sample_dir}/summary.txt"
  result_paths+=("${sample_dir}/result.json")
done

python3 - "$OUT_DIR" "${result_paths[@]}" <<'PY'
import json
import re
import statistics
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
paths = [Path(path) for path in sys.argv[2:]]

def meminfo_total_pss(path: Path):
    if not path.exists():
        return None
    for line in path.read_text(errors="ignore").splitlines():
        stripped = line.strip()
        match = re.match(r"TOTAL\s+(\d+)\s+", stripped)
        if match:
            return int(match.group(1))
        match = re.search(r"TOTAL PSS:\s*(\d+)", stripped)
        if match:
            return int(match.group(1))
    return None

samples = []
for path in paths:
    payload = json.loads(path.read_text(encoding="utf-8"))
    sample = payload["samples"][0]
    sample_dir = path.parent
    sample["local_result"] = str(path)
    sample["app_meminfo_total_pss_kb"] = meminfo_total_pss(sample_dir / "meminfo-com.smartisax.ocrbench.officialbench.txt")
    sample["camscanner_meminfo_total_pss_kb"] = meminfo_total_pss(sample_dir / "meminfo-com.intsig.camscanner.txt")
    samples.append(sample)

latencies = [int(sample.get("latency_ms", 0)) for sample in samples if isinstance(sample.get("latency_ms"), int)]
ok = [sample for sample in samples if sample.get("status") == "OK"]
summary = {
    "sample_count": len(samples),
    "ok_count": len(ok),
    "failed_count": len(samples) - len(ok),
    "line_count_total": sum(int(sample.get("csocr", {}).get("line_count", 0)) for sample in samples),
    "p50_latency_ms": statistics.median(latencies) if latencies else None,
    "max_latency_ms": max(latencies) if latencies else None,
    "max_app_peak_pss_kb": max((sample.get("peak_pss_kb") or 0) for sample in samples) if samples else None,
    "max_camscanner_total_pss_kb": max((sample.get("camscanner_meminfo_total_pss_kb") or 0) for sample in samples) if samples else None,
}
aggregate = {
    "kind": "textboom-csocr-camscanner-baseline-aggregate",
    "boundary": "aggregates saved standalone CamScanner baseline results; no live mutation",
    "summary": summary,
    "samples": samples,
    "result": "PASS_CSOCR_BASELINE_LIVE" if summary["failed_count"] == 0 else "FAIL_CSOCR_BASELINE_LIVE",
}
(out_dir / "csocr-baseline-results.json").write_text(json.dumps(aggregate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
with (out_dir / "summary.tsv").open("w", encoding="utf-8") as fh:
    fh.write("id\tstatus\tline_count\tlatency_ms\tpeak_pss_kb\tcamscanner_total_pss_kb\n")
    for sample in samples:
        fh.write(
            f"{sample.get('id')}\t{sample.get('status')}\t{sample.get('csocr', {}).get('line_count', 0)}\t"
            f"{sample.get('latency_ms')}\t{sample.get('peak_pss_kb')}\t{sample.get('camscanner_meminfo_total_pss_kb')}\n"
        )
print(f"aggregate={out_dir / 'csocr-baseline-results.json'}")
print(f"result={aggregate['result']}")
PY

cat "${OUT_DIR}/summary.tsv"
echo "Output: ${OUT_DIR}"
