#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.portal5a-native-webrtc-runtime}"
EXPECTED_VARIANT="${EXPECTED_VARIANT:-${VARIANT}}"
EXPECTED_RUNTIME_VARIANT="${EXPECTED_RUNTIME_VARIANT:-${EXPECTED_VARIANT}}"
EXPECTED_PORTAL_VERSION="${EXPECTED_PORTAL_VERSION:-0.6.0}"
EXPECTED_WEBRTC_CODEC="${EXPECTED_WEBRTC_CODEC:-H264}"
EXPECTED_INPUT="${EXPECTED_INPUT:-privileged-inputmanager}"
EXPECTED_HTTP_INPUT_REMOVED="${EXPECTED_HTTP_INPUT_REMOVED:-0}"
EXPECTED_BROWSER_PLAYBACK="${EXPECTED_BROWSER_PLAYBACK:-mp4-live-loop-fallback}"
EXPECTED_WEBRTC_DEFAULT_UI="${EXPECTED_WEBRTC_DEFAULT_UI:-0}"
EXPECTED_WEBRTC_BITRATE_BPS="${EXPECTED_WEBRTC_BITRATE_BPS:-0}"
RESULT_NAME="${RESULT_NAME:-PORTAL_SMOKE_V0PORTAL5A_CURL_COMPLETED}"
URL="${URL:-}"
PAIRING_CODE="${PAIRING_CODE:-}"
TOKEN="${TOKEN:-}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-smoke-live}"
TIMEOUT="${TIMEOUT:-8}"
TAP_X="${TAP_X:-1000}"
TAP_Y="${TAP_Y:-2250}"
SKIP_INPUT="${SKIP_INPUT:-0}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-portal-smoke-v0.portal5a.sh --url http://<r2-ip>:37601 --code <pairing-code>
  tools/r2-portal-smoke-v0.portal5a.sh --url http://<r2-ip>:37601 --token <bearer-token>

This curl-level live smoke validates pairing, status, capabilities, PNG, MP4,
and optional input. It also checks that the selected variant reports the native
libwebrtc DTLS/SRTP runtime fields. Browser-side RTCPeerConnection playback is
validated separately in Chrome because curl cannot create a real browser SDP.
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
    --token)
      [ "$#" -ge 2 ] || die "--token requires a value"
      TOKEN="$2"
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
if [ -z "$PAIRING_CODE" ] && [ -z "$TOKEN" ]; then
  die "missing --code <pairing-code> or --token <bearer-token>"
fi
URL="${URL%/}"

need_executable curl
need_executable python3
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

validate_index() {
  local body="$1" headers="$2"
  if [ "$EXPECTED_WEBRTC_DEFAULT_UI" = "1" ]; then
    grep -q 'data-portal-mode="webrtc-default"' "$body" || die "index missing default WebRTC mode marker"
    grep -q 'id="reconnectWebRtc"' "$body" || die "index missing WebRTC reconnect control"
    grep -q 'ensureWebRtc().catch' "$body" || die "index missing default WebRTC startup path"
    if grep -E -q 'id="(startLive|startMp4|stopMp4|startH264|stopH264|startPng|stopPng|startWebRtc|caps|probeH264|probeRtp)"' "$body"; then
      die "index still exposes legacy transport mode buttons"
    fi
    if grep -E -q '<video id="mp4Video"[^>]*controls' "$body"; then
      die "index still exposes browser video controls"
    fi
  else
    grep -q "Native WebRTC" "$body" || die "index missing Native WebRTC button"
  fi
  grep -q "/api/webrtc/offer" "$body" || die "index missing WebRTC offer endpoint"
  grep -q "setRemoteDescription" "$body" || die "index missing browser answer apply path"
  grep -q "srcObject" "$body" || die "index missing MediaStream video path"
  grep -qi "Content-Security-Policy:" "$headers" || die "index missing CSP header"
  grep -qi "X-Content-Type-Options:" "$headers" || die "index missing X-Content-Type-Options header"
  echo "index_native_webrtc_ui=ok"
  [ "$EXPECTED_WEBRTC_DEFAULT_UI" != "1" ] || echo "index_default_webrtc_ui=ok"
}

validate_pair() {
  local json_file="$1"
  python3 - "$json_file" "$EXPECTED_INPUT" "$EXPECTED_HTTP_INPUT_REMOVED" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_input = sys.argv[2]
expected_http_input_removed = sys.argv[3] == "1"
token = data.get("token", "")
if len(token) < 16:
    raise SystemExit("pair token missing or too short")
status = data.get("status", {})
if status.get("screen") != "privileged-surfacecontrol-png":
    raise SystemExit("unexpected screen backend")
if status.get("input") != expected_input:
    raise SystemExit("unexpected input backend")
if expected_http_input_removed:
    if status.get("httpInput") is not False:
        raise SystemExit("pair status still exposes HTTP input")
    if status.get("inputTransport") != "RTCDataChannel":
        raise SystemExit("pair status inputTransport mismatch")
    if status.get("inputChannel") != "smartisax-input":
        raise SystemExit("pair status inputChannel mismatch")
session = data.get("session", {})
if session.get("accessControl") != "bearer-token-pair-code-rotation":
    raise SystemExit("unexpected accessControl")
print(f"token_len={len(token)}")
PY
}

validate_status() {
  local json_file="$1"
  local expected_webrtc_codec="$2"
  python3 - "$json_file" "$EXPECTED_PORTAL_VERSION" "$expected_webrtc_codec" "$EXPECTED_INPUT" "$EXPECTED_HTTP_INPUT_REMOVED" "$EXPECTED_BROWSER_PLAYBACK" "$EXPECTED_WEBRTC_DEFAULT_UI" "$EXPECTED_WEBRTC_BITRATE_BPS" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_portal_version = sys.argv[2]
expected_webrtc_codec = sys.argv[3]
expected_input = sys.argv[4]
expected_http_input_removed = sys.argv[5] == "1"
expected_browser_playback = sys.argv[6]
expected_webrtc_default_ui = sys.argv[7] == "1"
expected_webrtc_bitrate_bps = int(sys.argv[8])
checks = {
    "portalVersion": expected_portal_version,
    "webrtc": "native-libwebrtc-dtls-srtp-screen",
    "webrtcCodec": expected_webrtc_codec,
    "browserPlayback": expected_browser_playback,
    "screen": "privileged-surfacecontrol-png",
    "input": expected_input,
}
for key, expected in checks.items():
    if data.get(key) != expected:
        raise SystemExit(f"status {key}={data.get(key)!r}, expected {expected!r}")
if expected_http_input_removed:
    if data.get("httpInput") is not False:
        raise SystemExit("status still exposes HTTP input")
    if data.get("inputTransport") != "RTCDataChannel":
        raise SystemExit("status inputTransport mismatch")
    if data.get("inputChannel") != "smartisax-input":
        raise SystemExit("status inputChannel mismatch")
native = data.get("nativeWebRtc", {})
if native.get("backend") != "io.github.webrtc-sdk:android":
    raise SystemExit("native WebRTC backend mismatch")
if native.get("artifactVersion") != "125.6422.07":
    raise SystemExit("native WebRTC artifact version mismatch")
if native.get("nativeLibrary") != "jingle_peerconnection_so":
    raise SystemExit("native WebRTC library mismatch")
if native.get("dtlsSrtp") is not True:
    raise SystemExit("native WebRTC dtlsSrtp marker is not true")
if expected_webrtc_default_ui:
    if data.get("webrtcDefault") is not True:
        raise SystemExit("status webrtcDefault is not true")
    if data.get("webrtcBitratePolicy") != "explicit-h264-bitrate":
        raise SystemExit("status bitrate policy mismatch")
    if expected_webrtc_bitrate_bps and data.get("webrtcTargetBitrateBps") != expected_webrtc_bitrate_bps:
        raise SystemExit("status target bitrate mismatch")
    frame_defaults = native.get("framePumpDefaults", {})
    if frame_defaults.get("bitratePolicy") != "explicit-h264-bitrate":
        raise SystemExit("native framePumpDefaults bitrate policy mismatch")
    if expected_webrtc_bitrate_bps and frame_defaults.get("targetVideoBitrateBps") != expected_webrtc_bitrate_bps:
        raise SystemExit("native framePumpDefaults target bitrate mismatch")
if expected_http_input_removed:
    if native.get("httpInput") is not False:
        raise SystemExit("native WebRTC status still exposes HTTP input")
    if native.get("inputChannel") != "smartisax-input":
        raise SystemExit("native WebRTC inputChannel mismatch")
session = data.get("session", {})
if session.get("accessControl") != "bearer-token-pair-code-rotation":
    raise SystemExit("session accessControl mismatch")
if expected_webrtc_codec == "H264-preferred-browser":
    if data.get("webrtcSessions") != "/api/webrtc/sessions":
        raise SystemExit("status webrtcSessions endpoint mismatch")
    if data.get("webrtcClose") != "/api/webrtc/close":
        raise SystemExit("status webrtcClose endpoint mismatch")
print(f"status_portal_version={expected_portal_version}")
print("status_webrtc=native-libwebrtc-dtls-srtp-screen")
print("status_native_webrtc_backend=io.github.webrtc-sdk:android")
if expected_webrtc_default_ui:
    print(f"status_webrtc_target_bitrate={expected_webrtc_bitrate_bps}")
PY
}

validate_capabilities() {
  local json_file="$1"
  python3 - "$json_file" "$EXPECTED_RUNTIME_VARIANT" "$EXPECTED_PORTAL_VERSION" "$EXPECTED_HTTP_INPUT_REMOVED" "$EXPECTED_WEBRTC_DEFAULT_UI" "$EXPECTED_WEBRTC_BITRATE_BPS" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_variant = sys.argv[2]
expected_portal_version = sys.argv[3]
expected_http_input_removed = sys.argv[4] == "1"
expected_webrtc_default_ui = sys.argv[5] == "1"
expected_webrtc_bitrate_bps = int(sys.argv[6])
if not data.get("ok"):
    raise SystemExit("capabilities ok is not true")
if data.get("portalVersion") != expected_portal_version:
    raise SystemExit("capabilities portalVersion mismatch")
if data.get("variant") != expected_variant:
    raise SystemExit("capabilities variant mismatch")
preferred = data.get("preferred", {})
if preferred.get("webRtc") != "native-libwebrtc-dtls-srtp":
    raise SystemExit("preferred native WebRTC marker mismatch")
if preferred.get("mime") != "video/avc":
    raise SystemExit("preferred mime mismatch")
if expected_variant in ("v0.portal5e-webrtc-h264-session-control", "v0.portal5f-webrtc-datachannel-input"):
    if preferred.get("webrtcSessions") != "/api/webrtc/sessions":
        raise SystemExit("preferred webrtcSessions endpoint mismatch")
    if preferred.get("webrtcClose") != "/api/webrtc/close":
        raise SystemExit("preferred webrtcClose endpoint mismatch")
if expected_http_input_removed:
    if preferred.get("input") != "webrtc-datachannel-input":
        raise SystemExit("preferred input marker mismatch")
    if preferred.get("inputChannel") != "smartisax-input":
        raise SystemExit("preferred inputChannel mismatch")
    if preferred.get("httpInput") is not False:
        raise SystemExit("preferred still exposes HTTP input")
if expected_webrtc_default_ui:
    if preferred.get("defaultTransport") != "WebRTC":
        raise SystemExit("preferred defaultTransport mismatch")
    if preferred.get("bitratePolicy") != "explicit-h264-bitrate":
        raise SystemExit("preferred bitrate policy mismatch")
    if expected_webrtc_bitrate_bps and preferred.get("bitrateBps") != expected_webrtc_bitrate_bps:
        raise SystemExit("preferred bitrate mismatch")
screen = data.get("screen", {})
print(f"capabilities_screen={screen.get('width')}x{screen.get('height')}")
print("capabilities_preferred_webrtc=native-libwebrtc-dtls-srtp")
if expected_webrtc_default_ui:
    print(f"capabilities_preferred_bitrate={expected_webrtc_bitrate_bps}")
PY
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
    raise SystemExit(f"{label} is not PNG")
print(f"{label}_bytes={len(data)}")
PY
}

assert_mp4() {
  local mp4="$1"
  python3 - "$mp4" <<'PY'
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
for marker in (b"ftyp", b"moov", b"mdat", b"avc1"):
    if marker not in data:
        raise SystemExit(f"MP4 missing {marker!r}")
print(f"mp4_bytes={len(data)}")
PY
}

{
  echo "# ${VARIANT} Portal curl smoke"
  echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "url=${URL}"
  echo "boundary=LAN HTTP smoke; browser RTCPeerConnection playback is separate"
  echo

  index_body="${OUT_DIR}/index.html"
  index_headers="${OUT_DIR}/index.headers"
  index_code="$(curl_request GET "/" "$index_body" "$index_headers")"
  assert_http "$index_code" "200" "GET /"
  validate_index "$index_body" "$index_headers"
  echo

  no_token_json="${OUT_DIR}/status-no-token.json"
  no_token_headers="${OUT_DIR}/status-no-token.headers"
  no_token_code="$(curl_request GET "/api/status" "$no_token_json" "$no_token_headers")"
  assert_http "$no_token_code" "401" "GET /api/status without token"
  echo "status_without_token=401"
  echo

  if [ -z "$TOKEN" ]; then
    pair_body="${OUT_DIR}/pair-body.json"
    pair_json="${OUT_DIR}/pair.json"
    pair_headers="${OUT_DIR}/pair.headers"
    python3 - "$pair_body" "$PAIRING_CODE" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"code": sys.argv[2]}), encoding="utf-8")
PY
    pair_code="$(curl_request POST "/api/pair" "$pair_json" "$pair_headers" "$(cat "$pair_body")")"
    assert_http "$pair_code" "200" "POST /api/pair"
    validate_pair "$pair_json"
    TOKEN="$(python3 - "$pair_json" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["token"])
PY
)"
    echo

    replay_json="${OUT_DIR}/pair-replay.json"
    replay_headers="${OUT_DIR}/pair-replay.headers"
    replay_code="$(curl_request POST "/api/pair" "$replay_json" "$replay_headers" "$(cat "$pair_body")")"
    assert_http "$replay_code" "403" "POST /api/pair replay"
    echo "pair_replay_rejected=403"
    echo
  else
    echo "token_supplied_len=${#TOKEN}"
    echo
  fi

  status_json="${OUT_DIR}/status-authorized.json"
  status_headers="${OUT_DIR}/status-authorized.headers"
  status_code="$(curl_request GET "/api/status" "$status_json" "$status_headers" "" "$TOKEN")"
  assert_http "$status_code" "200" "GET /api/status"
  validate_status "$status_json" "$EXPECTED_WEBRTC_CODEC"
  echo

  caps_json="${OUT_DIR}/media-capabilities.json"
  caps_headers="${OUT_DIR}/media-capabilities.headers"
  caps_code="$(curl_request GET "/api/media/capabilities" "$caps_json" "$caps_headers" "" "$TOKEN")"
  assert_http "$caps_code" "200" "GET /api/media/capabilities"
  validate_capabilities "$caps_json"
  echo

  png="${OUT_DIR}/screen.png"
  png_headers="${OUT_DIR}/screen.headers"
  png_code="$(curl_request GET "/api/screen.png?ts=$(date +%s)" "$png" "$png_headers" "" "$TOKEN")"
  assert_http "$png_code" "200" "GET /api/screen.png"
  assert_png "$png" "screen"
  echo

  mp4="${OUT_DIR}/video-mp4.mp4"
  mp4_headers="${OUT_DIR}/video-mp4.headers"
  mp4_code="$(curl_request GET "/api/video/mp4?frames=8&fps=6&width=720" "$mp4" "$mp4_headers" "" "$TOKEN")"
  assert_http "$mp4_code" "200" "GET /api/video/mp4"
  assert_mp4 "$mp4"
  echo

  if [ "$EXPECTED_HTTP_INPUT_REMOVED" = "1" ]; then
    input_json="${OUT_DIR}/input-removed.json"
    input_headers="${OUT_DIR}/input-removed.headers"
    input_body='{"type":"tap","x":'"${TAP_X}"',"y":'"${TAP_Y}"'}'
    input_code="$(curl_request POST "/api/input" "$input_json" "$input_headers" "$input_body" "$TOKEN")"
    assert_http "$input_code" "404" "POST /api/input removed"
    echo "http_input_removed=404"
    echo
  elif [ "$SKIP_INPUT" != "1" ]; then
    input_json="${OUT_DIR}/input-tap.json"
    input_headers="${OUT_DIR}/input-tap.headers"
    input_body='{"type":"tap","x":'"${TAP_X}"',"y":'"${TAP_Y}"'}'
    input_code="$(curl_request POST "/api/input" "$input_json" "$input_headers" "$input_body" "$TOKEN")"
    assert_http "$input_code" "200" "POST /api/input tap"
    grep -q 'privileged-inputmanager' "$input_json" || die "input backend mismatch"
    echo "input_tap=privileged-inputmanager"
    echo
  else
    echo "input_tap=skipped"
    echo
  fi

  echo "browser_webrtc_required=Chrome RTCPeerConnection must apply /api/webrtc/offer answer separately"
  echo "result=${RESULT_NAME}"
} 2>&1 | tee "$REPORT"

echo "Report: $REPORT"
