#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

SERIAL="${SERIAL:-bb12d264}"
PACKAGE="com.smartisax.ocrbench.onnx"
ACTIVITY="${PACKAGE}/.MainActivity"
APK="${APK:-${ROOT_DIR}/hard-rom/build/apk/TextBoomOnnxSmokeBench.apk}"
MODE="${MODE:-both}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
INSTALL_MODE="${INSTALL_MODE:-adb}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_ROOT="${OUT_ROOT:-${ROOT_DIR}/hard-rom/inspect/textboom-onnx-smoke-live}"
OUT_DIR="${OUT_ROOT}/${RUN_ID}"
DEVICE_ROOT="/sdcard/Android/data/${PACKAGE}/files"
DEVICE_RESULT="${DEVICE_ROOT}/results/last-result.json"

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

adb_cmd() {
  "${ANDROID_SDK_ROOT}/platform-tools/adb" -s "$SERIAL" "$@"
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

run_one_mode() {
  local mode="$1"
  local expected="$2"
  local mode_dir="${OUT_DIR}/${mode}"
  mkdir -p "$mode_dir"
  echo "Running ${mode} smoke..."
  adb_cmd shell "mkdir -p '${DEVICE_ROOT}/results'"
  adb_cmd shell "rm -f '${DEVICE_RESULT}'"
  adb_cmd shell "am force-stop '${PACKAGE}'" || true
  adb_cmd shell am start \
    -n "$ACTIVITY" \
    --es mode "$mode" \
    --es result_path "$DEVICE_RESULT" | tee "${mode_dir}/am-start.txt"

  for _attempt in $(seq 1 90); do
    if adb_cmd shell "test -f '${DEVICE_RESULT}'"; then
      break
    fi
    sleep 1
  done
  adb_cmd shell "test -f '${DEVICE_RESULT}'" || die "${mode} result did not appear"
  adb_cmd pull "$DEVICE_RESULT" "${mode_dir}/last-result.json" >/dev/null

  local result
  local latency
  local engine
  local provider
  result="$(json_get_optional "${mode_dir}/last-result.json" "result")"
  latency="$(json_get_optional "${mode_dir}/last-result.json" "latency_ms")"
  engine="$(json_get_optional "${mode_dir}/last-result.json" "engine.id")"
  provider="$(json_get_optional "${mode_dir}/last-result.json" "engine.provider")"
  {
    echo "mode=${mode}"
    echo "result=${result}"
    echo "expected=${expected}"
    echo "engine=${engine}"
    echo "provider=${provider}"
    echo "latency_ms=${latency}"
  } > "${mode_dir}/summary.txt"
  [ "$result" = "$expected" ] || die "${mode} unexpected result=${result}; see ${mode_dir}/last-result.json"
}

need_executable "${ANDROID_SDK_ROOT}/platform-tools/adb"
need_file "$APK"
mkdir -p "$OUT_DIR"

{
  echo "kind=textboom-onnx-smoke-live"
  echo "boundary=modifies live device by installing a standalone benchmark APK and writing app-specific external files; no flash/reboot/erase/data-cleanup/TextBoom mutation/ROM mutation"
  echo "serial=${SERIAL}"
  echo "apk=${APK}"
  echo "mode=${MODE}"
  echo "skip_install=${SKIP_INSTALL}"
  echo "install_mode=${INSTALL_MODE}"
  echo "device_result=${DEVICE_RESULT}"
  echo "run_id=${RUN_ID}"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${OUT_DIR}/run.txt"

adb_cmd wait-for-device
adb_cmd devices -l | tee "${OUT_DIR}/adb-devices.txt"

if [ "$SKIP_INSTALL" = "1" ]; then
  adb_cmd shell "pm path '${PACKAGE}'" | tee "${OUT_DIR}/adb-install.txt"
elif [ "$INSTALL_MODE" = "pm" ]; then
  remote_apk="/data/local/tmp/${PACKAGE}.apk"
  adb_cmd push "$APK" "$remote_apk" | tee "${OUT_DIR}/adb-install.txt"
  adb_cmd shell "pm install -r '${remote_apk}'; rm -f '${remote_apk}'" | tee -a "${OUT_DIR}/adb-install.txt"
else
  adb_cmd install -r "$APK" | tee "${OUT_DIR}/adb-install.txt"
fi

case "$MODE" in
  native)
    run_one_mode native NATIVE_ONNX_READY
    ;;
  web)
    run_one_mode web WEB_ONNX_READY
    ;;
  both)
    run_one_mode native NATIVE_ONNX_READY
    run_one_mode web WEB_ONNX_READY
    ;;
  *)
    die "unsupported MODE=${MODE}; expected native, web, or both"
    ;;
esac

echo "PASS_TEXTBOOM_ONNX_SMOKE_LIVE"
echo "Output: ${OUT_DIR}"
