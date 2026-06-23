#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

SERIAL="${SERIAL:-bb12d264}"
PACKAGE="com.smartisax.ocrbench.officialbench"
ACTIVITY="${PACKAGE}/.MainActivity"
APK="${APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoomPpOcrOfficialBench.apk}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
INSTALL_MODE="${INSTALL_MODE:-adb}"
SAMPLE="${SAMPLE:-${ROOT_DIR}/hard-rom/inspect/textboom-ppocr-live-capture/20260620-230945-unlocked-boom-image/device-files/imageboom.jpg}"
if [ "$#" -gt 0 ]; then
  SAMPLE="$1"
fi
DEVICE_ROOT="/sdcard/Android/data/${PACKAGE}/files"
DEVICE_INPUT="${DEVICE_INPUT:-${DEVICE_ROOT}/input/imageboom.jpg}"
DEVICE_RESULT="${DEVICE_RESULT:-${DEVICE_ROOT}/results/last-result.json}"
OUT_ROOT="${OUT_ROOT:-${ROOT_DIR}/hard-rom/inspect/textboom-ppocr-official-bench-live}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${OUT_ROOT}/${RUN_ID}"
if [ "$SKIP_INSTALL" = "1" ]; then
  BOUNDARY="modifies live device by writing app-specific external files and launching an already-installed APK; no install/flash/reboot/erase/data-cleanup"
elif [ "$INSTALL_MODE" = "pm" ]; then
  BOUNDARY="modifies live device by pushing APK to /data/local/tmp, installing benchmark APK with pm, and writing app-specific external files; no flash/reboot/erase/data-cleanup"
else
  BOUNDARY="modifies live device by installing APK and writing app-specific external files; no flash/reboot/erase/data-cleanup"
fi

die() {
  echo "error: $*" >&2
  exit 1
}

adb_cmd() {
  adb -s "$SERIAL" "$@"
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
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

json_get_optional() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

path, dotted = sys.argv[1], sys.argv[2]
value = json.load(open(path, encoding="utf-8"))
for part in dotted.split("."):
    try:
        if part.isdigit():
            value = value[int(part)]
        else:
            value = value[part]
    except (KeyError, IndexError, TypeError):
        print("")
        raise SystemExit(0)
print(value)
PY
}

need_executable "${ANDROID_SDK_ROOT}/platform-tools/adb"
need_file "$APK"
need_file "$SAMPLE"
mkdir -p "$OUT_DIR"

{
  echo "run_id=${RUN_ID}"
  echo "serial=${SERIAL}"
  echo "apk=${APK}"
  echo "skip_install=${SKIP_INSTALL}"
  echo "install_mode=${INSTALL_MODE}"
  echo "sample=${SAMPLE}"
  echo "device_input=${DEVICE_INPUT}"
  echo "device_result=${DEVICE_RESULT}"
  echo "out_dir=${OUT_DIR}"
  echo "boundary=${BOUNDARY}"
} > "${OUT_DIR}/run.txt"

echo "Waiting for device ${SERIAL}..."
adb_cmd wait-for-device
adb_cmd shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; id' > "${OUT_DIR}/device-state-before.txt"

if [ "$SKIP_INSTALL" = "1" ]; then
  echo "Skipping install; verifying ${PACKAGE} is already present..."
  adb_cmd shell "pm path '${PACKAGE}'" | tee "${OUT_DIR}/adb-install.txt"
  grep -q '^package:' "${OUT_DIR}/adb-install.txt" || die "${PACKAGE} is not installed; rerun without SKIP_INSTALL=1"
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

echo "Preparing app-specific sample path..."
adb_cmd shell "mkdir -p '${DEVICE_ROOT}/input' '${DEVICE_ROOT}/results'"
adb_cmd push "$SAMPLE" "$DEVICE_INPUT" | tee "${OUT_DIR}/adb-push.txt"
adb_cmd shell "rm -f '${DEVICE_RESULT}'"

echo "Launching official PP-OCR benchmark..."
adb_cmd shell logcat -c || true
adb_cmd shell "am force-stop '${PACKAGE}'" || true
adb_cmd shell am start \
  -n "$ACTIVITY" \
  --es image_path "$DEVICE_INPUT" \
  --es result_path "$DEVICE_RESULT" | tee "${OUT_DIR}/am-start.txt"

for _attempt in $(seq 1 120); do
  if adb_cmd shell "test -f '${DEVICE_RESULT}'"; then
    break
  fi
  sleep 1
done

adb_cmd shell "ls -l '${DEVICE_RESULT}'" > "${OUT_DIR}/device-result-ls.txt"
adb_cmd pull "$DEVICE_RESULT" "${OUT_DIR}/last-result.json" | tee "${OUT_DIR}/adb-pull.txt"
adb_cmd shell logcat -d -t 500 > "${OUT_DIR}/logcat-tail.txt" || true
adb_cmd shell "logcat -d -t 500 | grep -E 'SmartisaxOcrOfficialBench|${PACKAGE}|OpenCVUtils|onnxruntime'" > "${OUT_DIR}/logcat-ocrbench.txt" || true

result_status="$(json_get "${OUT_DIR}/last-result.json" "result")"
sample_status="$(json_get "${OUT_DIR}/last-result.json" "samples.0.status")"
sample_width="$(json_get "${OUT_DIR}/last-result.json" "samples.0.image_size.0")"
sample_height="$(json_get "${OUT_DIR}/last-result.json" "samples.0.image_size.1")"
sample_sha="$(json_get "${OUT_DIR}/last-result.json" "samples.0.image_sha256")"
expected_sha="$(shasum -a 256 "$SAMPLE" | awk '{print $1}')"
line_count="$(json_get_optional "${OUT_DIR}/last-result.json" "samples.0.native_metrics.line_count")"
latency_ms="$(json_get_optional "${OUT_DIR}/last-result.json" "samples.0.latency_ms")"
det_ms="$(json_get_optional "${OUT_DIR}/last-result.json" "samples.0.native_metrics.det_ms")"
rec_ms="$(json_get_optional "${OUT_DIR}/last-result.json" "samples.0.native_metrics.rec_ms")"
peak_pss_kb="$(json_get_optional "${OUT_DIR}/last-result.json" "samples.0.peak_pss_kb")"

{
  echo "result=${result_status}"
  echo "sample_status=${sample_status}"
  echo "image_size=${sample_width}x${sample_height}"
  echo "sample_sha256=${sample_sha}"
  echo "expected_sha256=${expected_sha}"
  echo "line_count=${line_count}"
  echo "latency_ms=${latency_ms}"
  echo "det_ms=${det_ms}"
  echo "rec_ms=${rec_ms}"
  echo "peak_pss_kb=${peak_pss_kb}"
} > "${OUT_DIR}/summary.txt"

[ "$result_status" = "OK" ] || die "unexpected result=${result_status}; see ${OUT_DIR}/last-result.json"
[ "$sample_status" = "OK" ] || die "unexpected sample_status=${sample_status}; see ${OUT_DIR}/last-result.json"
case "$sample_width" in
  ''|*[!0-9]*) die "unexpected width=${sample_width}" ;;
  *) [ "$sample_width" -gt 0 ] || die "unexpected width=${sample_width}" ;;
esac
case "$sample_height" in
  ''|*[!0-9]*) die "unexpected height=${sample_height}" ;;
  *) [ "$sample_height" -gt 0 ] || die "unexpected height=${sample_height}" ;;
esac
[ "$sample_sha" = "$expected_sha" ] || die "image sha mismatch"
if [ -z "$line_count" ] || [ "$line_count" -le 0 ]; then
  die "expected at least one OCR line, got line_count=${line_count}"
fi

echo "PASS_PPOCR_OFFICIAL_BENCH_LIVE_SMOKE"
echo "Output: ${OUT_DIR}"
