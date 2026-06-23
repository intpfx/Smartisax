#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.portal3b-h264-http-stream-prototype}"
URL="${URL:-}"
PAIRING_CODE="${PAIRING_CODE:-}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-smoke-live}"
TIMEOUT="${TIMEOUT:-8}"
TAP_X="${TAP_X:-540}"
TAP_Y="${TAP_Y:-1170}"
SWIPE_X1="${SWIPE_X1:-540}"
SWIPE_Y1="${SWIPE_Y1:-1650}"
SWIPE_X2="${SWIPE_X2:-540}"
SWIPE_Y2="${SWIPE_Y2:-900}"
SWIPE_DURATION="${SWIPE_DURATION:-320}"
SKIP_INPUT="${SKIP_INPUT:-0}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-portal-smoke-v0.portal3b.sh --url http://<r2-ip>:37601 --code <pairing-code>

Environment/flags:
  VARIANT=v0.portal3b-h264-http-stream-prototype
  OUT_DIR=hard-rom/inspect/<variant>/portal-smoke-live
  TIMEOUT=8
  SKIP_INPUT=1
  TAP_X=540 TAP_Y=1170
  SWIPE_X1=540 SWIPE_Y1=1650 SWIPE_X2=540 SWIPE_Y2=900 SWIPE_DURATION=320

This script performs a live LAN Portal smoke against the phone. It does not use
ADB and does not start the Portal service; enable Device Portal on the phone and
read the pairing code from Smartisax first. It sends real input events unless
SKIP_INPUT=1 is set.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
need_executable() { command -v "$1" >/dev/null 2>&1 || die "missing executable: $1"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      [ "$#" -ge 2 ] || die "--url requires a value"
      URL="$2"
      shift 2
      ;;
    --code|--pairing-code)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      PAIRING_CODE="$2"
      shift 2
      ;;
    --out-dir)
      [ "$#" -ge 2 ] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --skip-input)
      SKIP_INPUT=1
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -n "$URL" ] || die "missing --url http://<r2-ip>:37601"
[ -n "$PAIRING_CODE" ] || die "missing --code <pairing-code>"
URL="${URL%/}"

need_executable curl
need_executable python3
need_executable file
need_executable wc

mkdir -p "$OUT_DIR"
REPORT="${OUT_DIR}/portal-smoke-${VARIANT}-$(date '+%Y%m%d-%H%M%S').txt"

curl_request() {
  local method="$1" path="$2" output="$3" headers="$4" body="${5:-}" token="${6:-}"
  local http_code
  local args=(
    --silent --show-error --location
    --max-time "$TIMEOUT"
    --request "$method"
    --dump-header "$headers"
    --output "$output"
    --write-out "%{http_code}"
  )
  if [ -n "$token" ]; then
    args+=(--header "Authorization: Bearer ${token}")
  fi
  if [ -n "$body" ]; then
    args+=(--header "Content-Type: application/json" --data "$body")
  fi
  http_code="$(curl "${args[@]}" "${URL}${path}")"
  printf '%s' "$http_code"
}

assert_http() {
  local actual="$1" expected="$2" label="$3"
  [ "$actual" = "$expected" ] || die "${label} HTTP ${actual}, expected ${expected}"
}

assert_png() {
  local png="$1" label="$2"
  python3 - "$png" "$label" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
label = sys.argv[2]
data = path.read_bytes()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit(f"{label} is not PNG: {path}")
print(f"{label}_png_signature=True")
print(f"{label}_bytes={len(data)}")
PY
}

json_field() {
  local json_file="$1" expr="$2"
  python3 - "$json_file" "$expr" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = data
for part in sys.argv[2].split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

validate_pair() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
token = data.get("token", "")
if len(token) < 16:
    raise SystemExit("pair token missing or too short")
status = data.get("status", {})
if status.get("screen") != "privileged-surfacecontrol-png":
    raise SystemExit("unexpected screen backend")
if status.get("input") != "privileged-inputmanager":
    raise SystemExit("unexpected input backend")
print(f"token_len={len(token)}")
PY
}

validate_status() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
checks = {
    "portalVersion": "0.5.1",
    "webrtc": "h264-http-prototype",
    "webrtcCodec": "H264",
    "mediaCapabilities": "/api/media/capabilities",
    "videoStream": "/api/video/h264",
    "screen": "privileged-surfacecontrol-png",
    "input": "privileged-inputmanager",
}
for key, expected in checks.items():
    if data.get(key) != expected:
        raise SystemExit(f"status {key}={data.get(key)!r}, expected {expected!r}")
if data.get("bootCompleted") != "1":
    raise SystemExit("bootCompleted is not 1")
if data.get("slot") != "_b":
    raise SystemExit("device is not on _b")
print("status_portal_version=0.5.1")
print("status_webrtc=h264-http-prototype")
print("status_screen_backend=privileged-surfacecontrol-png")
print("status_input_backend=privileged-inputmanager")
PY
}

validate_capabilities() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if not data.get("ok"):
    raise SystemExit("capabilities ok is not true")
if data.get("portalVersion") != "0.5.1":
    raise SystemExit("capabilities portalVersion mismatch")
if data.get("variant") != "v0.portal3b-h264-http-stream-prototype":
    raise SystemExit("capabilities variant mismatch")
preferred = data.get("preferred", {})
if preferred.get("mime") != "video/avc":
    raise SystemExit("preferred mime is not video/avc")
screen = data.get("screen", {})
if not isinstance(screen.get("width"), int) or not isinstance(screen.get("height"), int):
    raise SystemExit("screen dimensions missing")
encoders = data.get("encoders", [])
if not isinstance(encoders, list):
    raise SystemExit("encoders is not a list")
avc = [item for item in encoders if item.get("mime") == "video/avc"]
hevc = [item for item in encoders if item.get("mime") == "video/hevc"]
if not avc:
    raise SystemExit("no video/avc encoder reported")
hardware_avc = [item for item in avc if item.get("hardwareAccelerated") is True]
print(f"capabilities_screen={screen.get('width')}x{screen.get('height')} rotation={screen.get('rotation')}")
print(f"capabilities_avc_encoder_count={len(avc)}")
print(f"capabilities_hevc_encoder_count={len(hevc)}")
print(f"capabilities_hardware_avc_encoder_count={len(hardware_avc)}")
print("capabilities_preferred=video/avc")
PY
}

assert_h264() {
  local stream="$1"
  python3 - "$stream" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 128:
    raise SystemExit(f"H.264 stream too small: {len(data)} bytes")

def find_start_codes(buf: bytes):
    offsets = []
    i = 0
    while i < len(buf) - 3:
        if buf[i:i + 3] == b"\x00\x00\x01":
            offsets.append(i)
            i += 3
            continue
        if buf[i:i + 4] == b"\x00\x00\x00\x01":
            offsets.append(i)
            i += 4
            continue
        i += 1
    return offsets

starts = find_start_codes(data)
if not starts:
    raise SystemExit("H.264 stream has no Annex-B start code")
nal_types = []
for offset in starts:
    nal = offset + (4 if data[offset:offset + 4] == b"\x00\x00\x00\x01" else 3)
    if nal < len(data):
        nal_types.append(data[nal] & 0x1f)
if not any(t in (5, 7, 8) for t in nal_types):
    raise SystemExit(f"H.264 stream lacks IDR/SPS/PPS-like NALs: {nal_types[:20]}")
print(f"h264_bytes={len(data)}")
print(f"h264_annexb_start_codes={len(starts)}")
print("h264_nal_types=" + ",".join(str(t) for t in nal_types[:20]))
PY
}

validate_input() {
  local json_file="$1" expected_type="$2"
  python3 - "$json_file" "$expected_type" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = sys.argv[2]
if data.get("ok") is not True:
    raise SystemExit(f"{expected} input ok is not true")
if data.get("type") != expected:
    raise SystemExit(f"input type {data.get('type')!r}, expected {expected!r}")
if data.get("backend") != "privileged-inputmanager":
    raise SystemExit("input backend mismatch")
print(f"input_{expected}=ok")
PY
}

{
  echo "# ${VARIANT} portal smoke"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "url=${URL}"
  echo "code=${PAIRING_CODE}"
  echo "boundary=live LAN Portal smoke; no adb, no fastboot, no flash, no reboot, no /data cleanup"
  if [ "$SKIP_INPUT" = "1" ]; then
    echo "input=skipped"
  else
    echo "input=enabled"
  fi
  echo

  echo "## GET /"
  index_headers="${OUT_DIR}/index.headers"
  index_body="${OUT_DIR}/index.html"
  index_code="$(curl_request GET "/" "$index_body" "$index_headers")"
  assert_http "$index_code" "200" "GET /"
  grep -q "Smartisax Portal" "$index_body" || die "index missing Smartisax Portal title"
  grep -q "Capabilities" "$index_body" || die "index missing Capabilities button"
  echo "index_http=${index_code}"
  wc -c "$index_body"
  echo

  echo "## GET /api/status without token"
  no_token_headers="${OUT_DIR}/status-no-token.headers"
  no_token_body="${OUT_DIR}/status-no-token.json"
  no_token_code="$(curl_request GET "/api/status" "$no_token_body" "$no_token_headers")"
  assert_http "$no_token_code" "401" "GET /api/status without token"
  cat "$no_token_body"
  echo

  echo "## POST /api/pair"
  pair_body="${OUT_DIR}/pair-body.json"
  pair_headers="${OUT_DIR}/pair.headers"
  pair_json="${OUT_DIR}/pair.json"
  python3 - "$PAIRING_CODE" "$pair_body" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[2]).write_text(json.dumps({"code": sys.argv[1]}), encoding="utf-8")
PY
  pair_code="$(curl_request POST "/api/pair" "$pair_json" "$pair_headers" "$(cat "$pair_body")")"
  assert_http "$pair_code" "200" "POST /api/pair"
  cat "$pair_json"
  echo
  validate_pair "$pair_json"
  token="$(json_field "$pair_json" token)"
  [ -n "$token" ] || die "missing token after pair"
  echo

  echo "## GET /api/status authorized"
  status_headers="${OUT_DIR}/status-authorized.headers"
  status_json="${OUT_DIR}/status-authorized.json"
  status_code="$(curl_request GET "/api/status" "$status_json" "$status_headers" "" "$token")"
  assert_http "$status_code" "200" "GET /api/status authorized"
  cat "$status_json"
  echo
  validate_status "$status_json"
  echo

  echo "## GET /api/media/capabilities authorized"
  caps_headers="${OUT_DIR}/media-capabilities.headers"
  caps_json="${OUT_DIR}/media-capabilities.json"
  caps_code="$(curl_request GET "/api/media/capabilities" "$caps_json" "$caps_headers" "" "$token")"
  assert_http "$caps_code" "200" "GET /api/media/capabilities"
  cat "$caps_json"
  echo
  validate_capabilities "$caps_json"
  echo

  echo "## GET /api/video/h264 authorized"
  h264_headers="${OUT_DIR}/video-h264.headers"
  h264_stream="${OUT_DIR}/video-h264.264"
  h264_code="$(curl_request GET "/api/video/h264?frames=8&fps=4&width=720" "$h264_stream" "$h264_headers" "" "$token")"
  assert_http "$h264_code" "200" "GET /api/video/h264"
  grep -qi "Content-Type: video/avc" "$h264_headers" || die "H.264 response is not video/avc"
  wc -c "$h264_stream"
  assert_h264 "$h264_stream"
  echo

  echo "## GET /api/screen.png authorized"
  screen_headers="${OUT_DIR}/screen.headers"
  screen_png="${OUT_DIR}/screen.png"
  screen_code="$(curl_request GET "/api/screen.png?ts=$(date +%s)" "$screen_png" "$screen_headers" "" "$token")"
  assert_http "$screen_code" "200" "GET /api/screen.png"
  grep -qi "Content-Type: image/png" "$screen_headers" || die "screen response is not image/png"
  file "$screen_png"
  wc -c "$screen_png"
  assert_png "$screen_png" "screen"
  echo

  if [ "$SKIP_INPUT" != "1" ]; then
    echo "## POST /api/input tap authorized"
    tap_headers="${OUT_DIR}/input-tap.headers"
    tap_json="${OUT_DIR}/input-tap.json"
    tap_body="{\"type\":\"tap\",\"x\":${TAP_X},\"y\":${TAP_Y}}"
    tap_code="$(curl_request POST "/api/input" "$tap_json" "$tap_headers" "$tap_body" "$token")"
    assert_http "$tap_code" "200" "POST /api/input tap"
    cat "$tap_json"
    echo
    validate_input "$tap_json" "tap"
    echo

    echo "## POST /api/input swipe authorized"
    swipe_headers="${OUT_DIR}/input-swipe.headers"
    swipe_json="${OUT_DIR}/input-swipe.json"
    swipe_body="{\"type\":\"swipe\",\"x1\":${SWIPE_X1},\"y1\":${SWIPE_Y1},\"x2\":${SWIPE_X2},\"y2\":${SWIPE_Y2},\"duration\":${SWIPE_DURATION}}"
    swipe_code="$(curl_request POST "/api/input" "$swipe_json" "$swipe_headers" "$swipe_body" "$token")"
    assert_http "$swipe_code" "200" "POST /api/input swipe"
    cat "$swipe_json"
    echo
    validate_input "$swipe_json" "swipe"
    echo

    echo "## GET /api/screen.png after input"
    screen_after_headers="${OUT_DIR}/screen-after-input.headers"
    screen_after_png="${OUT_DIR}/screen-after-input.png"
    screen_after_code="$(curl_request GET "/api/screen.png?ts=$(date +%s)" "$screen_after_png" "$screen_after_headers" "" "$token")"
    assert_http "$screen_after_code" "200" "GET /api/screen.png after input"
    grep -qi "Content-Type: image/png" "$screen_after_headers" || die "screen-after-input response is not image/png"
    file "$screen_after_png"
    wc -c "$screen_after_png"
    assert_png "$screen_after_png" "screen_after_input"
    echo
  fi

  echo "result=PORTAL_SMOKE_V0PORTAL3B_COMPLETED"
} 2>&1 | tee "$REPORT"

echo "Report: $REPORT"
