#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SINGLE_RUNNER="${ROOT_DIR}/tools/r2-textboom-ppocr-official-bench-live-smoke.sh"

SERIAL="${SERIAL:-bb12d264}"
PACKAGE="com.smartisax.ocrbench.officialbench"
DEVICE_ROOT="/sdcard/Android/data/${PACKAGE}/files"
OUT_ROOT="${OUT_ROOT:-${ROOT_DIR}/hard-rom/inspect/textboom-ppocr-official-corpus-live}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${OUT_ROOT}/${RUN_ID}"
RUNS_ROOT="${OUT_DIR}/runs"
SKIP_INSTALL="${SKIP_INSTALL:-1}"
INSTALL_MODE="${INSTALL_MODE:-pm}"

DEFAULT_SAMPLES=(
  "${ROOT_DIR}/hard-rom/inspect/textboom-ppocr-live-capture/20260620-230945-unlocked-boom-image/device-files/imageboom.jpg"
  "${ROOT_DIR}/hard-rom/inspect/v0.39-sidebar-font-ocr-deleted/smartisax-shell-test-v0.39-20260620-221921.png"
  "${ROOT_DIR}/hard-rom/inspect/v0.39-sidebar-font-ocr-deleted/browserchrome-example-test-v0.39-recheck-20260620-221921.png"
  "${ROOT_DIR}/hard-rom/inspect/v0.39-sidebar-font-ocr-deleted/bigbang-boomtext-test-v0.39-20260620-221921.png"
  "${ROOT_DIR}/hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/thirdparty-wps-html-test-v0.35.2-webview-m150-clean-product-residue-20260620-141053.png"
  "${ROOT_DIR}/hard-rom/inspect/v0.29-sidebar-topbar-hide/screenshot-v0.29-sidebar-topbar-hide-20260618-224507.png"
)

usage() {
  cat <<USAGE
Usage:
  tools/r2-textboom-ppocr-official-corpus-live.sh [sample-image ...]

Environment:
  SERIAL=${SERIAL}
  SKIP_INSTALL=1|0      default: 1, because the bench APK is normally already installed
  INSTALL_MODE=pm|adb   default: pm, used only when SKIP_INSTALL=0
  RUN_ID=<stable-run-id>

Boundary:
  Runs the standalone official PP-OCRv6 small benchmark APK over a local image
  corpus by writing app-specific external files and launching the benchmark
  activity. It does not modify TextBoom, ROM images, system packages, boot
  state, or package data outside this benchmark APK's app-specific files.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

die() {
  echo "error: $*" >&2
  exit 1
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

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_file "$SINGLE_RUNNER"

if [ "$#" -eq 0 ]; then
  samples=("${DEFAULT_SAMPLES[@]}")
else
  samples=("$@")
fi
for sample in "${samples[@]}"; do
  need_file "$sample"
done

mkdir -p "$RUNS_ROOT"

{
  echo "run_id=${RUN_ID}"
  echo "serial=${SERIAL}"
  echo "package=${PACKAGE}"
  echo "skip_install=${SKIP_INSTALL}"
  echo "install_mode=${INSTALL_MODE}"
  echo "out_dir=${OUT_DIR}"
  echo "boundary=standalone official PP-OCR corpus run; no TextBoom/ROM/flash/reboot/erase/data-cleanup mutation"
  printf 'sample=%s\n' "${samples[@]}"
} > "${OUT_DIR}/run.txt"

result_paths=()
run_status_paths=()
first=1
for sample in "${samples[@]}"; do
  sample_id="$(sample_id_for_path "$sample")"
  suffix="${sample##*.}"
  if [ "$suffix" = "$sample" ]; then
    suffix="img"
  fi
  sample_run_id="${RUN_ID}-${sample_id}"
  sample_device_input="${DEVICE_ROOT}/input/${sample_id}.${suffix}"
  sample_device_result="${DEVICE_ROOT}/results/${sample_id}.ppocr.json"
  run_skip_install="1"
  if [ "$first" -eq 1 ]; then
    run_skip_install="$SKIP_INSTALL"
    first=0
  fi

  status_path="${RUNS_ROOT}/${sample_run_id}.status"
  echo "Running official PP-OCR on ${sample_id}..."
  if SERIAL="$SERIAL" \
    SKIP_INSTALL="$run_skip_install" \
    INSTALL_MODE="$INSTALL_MODE" \
    RUN_ID="$sample_run_id" \
    OUT_ROOT="$RUNS_ROOT" \
    SAMPLE="$sample" \
    DEVICE_INPUT="$sample_device_input" \
    DEVICE_RESULT="$sample_device_result" \
    "$SINGLE_RUNNER" "$sample"; then
    echo "exit_status=0" > "$status_path"
  else
    exit_status=$?
    echo "exit_status=${exit_status}" > "$status_path"
  fi

  result_path="${RUNS_ROOT}/${sample_run_id}/last-result.json"
  if [ -f "$result_path" ]; then
    result_paths+=("$result_path")
  fi
  run_status_paths+=("$status_path")
done

python3 - "$OUT_DIR" "${result_paths[@]}" <<'PY'
import json
import statistics
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
paths = [Path(value) for value in sys.argv[2:]]
samples = []
for path in paths:
    payload = json.loads(path.read_text(encoding="utf-8"))
    sample = payload["samples"][0]
    sample["local_result"] = str(path)
    sample["engine"] = payload.get("engine", {})
    sample["model"] = payload.get("model", {})
    samples.append(sample)

latencies = [sample.get("latency_ms") for sample in samples if isinstance(sample.get("latency_ms"), (int, float))]
pss = [sample.get("peak_pss_kb") for sample in samples if isinstance(sample.get("peak_pss_kb"), (int, float))]
line_counts = [sample.get("native_metrics", {}).get("line_count") for sample in samples]
line_counts = [value for value in line_counts if isinstance(value, int)]
ok = [sample for sample in samples if sample.get("status") == "OK"]
summary = {
    "sample_count": len(samples),
    "ok_count": len(ok),
    "failed_count": len(samples) - len(ok),
    "line_count_total": sum(line_counts),
    "p50_latency_ms": statistics.median(latencies) if latencies else None,
    "max_latency_ms": max(latencies) if latencies else None,
    "max_peak_pss_kb": max(pss) if pss else None,
}
aggregate = {
    "kind": "textboom-ppocr-official-corpus-live-aggregate",
    "boundary": "aggregates saved official PP-OCRv6 small standalone results; no live mutation",
    "summary": summary,
    "samples": samples,
    "result": "PASS_PPOCR_OFFICIAL_CORPUS_LIVE" if summary["failed_count"] == 0 and summary["sample_count"] else "FAIL_PPOCR_OFFICIAL_CORPUS_LIVE",
}
(out_dir / "ppocr-official-corpus-results.json").write_text(json.dumps(aggregate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
with (out_dir / "summary.tsv").open("w", encoding="utf-8") as fh:
    fh.write("id\tstatus\timage_size\tline_count\tlatency_ms\tdet_ms\trec_ms\tpeak_pss_kb\tlocal_result\n")
    for sample in samples:
        size = sample.get("image_size") or []
        metrics = sample.get("native_metrics") or {}
        fh.write(
            f"{sample.get('id')}\t{sample.get('status')}\t"
            f"{'x'.join(str(part) for part in size)}\t"
            f"{metrics.get('line_count')}\t{sample.get('latency_ms')}\t"
            f"{metrics.get('det_ms')}\t{metrics.get('rec_ms')}\t"
            f"{sample.get('peak_pss_kb')}\t{sample.get('local_result')}\n"
        )
print(f"aggregate={out_dir / 'ppocr-official-corpus-results.json'}")
print(f"result={aggregate['result']}")
PY

cat "${OUT_DIR}/summary.tsv"
echo "Output: ${OUT_DIR}"
