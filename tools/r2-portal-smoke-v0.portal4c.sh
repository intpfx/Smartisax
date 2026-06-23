#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VARIANT="${VARIANT:-v0.portal4c-session-hardening}"
URL="${URL:-}"
PAIRING_CODE="${PAIRING_CODE:-}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-smoke-live}"
TIMEOUT="${TIMEOUT:-8}"
TAP_X="${TAP_X:-1000}"
TAP_Y="${TAP_Y:-2250}"
SWIPE_X1="${SWIPE_X1:-540}"
SWIPE_Y1="${SWIPE_Y1:-1650}"
SWIPE_X2="${SWIPE_X2:-540}"
SWIPE_Y2="${SWIPE_Y2:-900}"
SWIPE_DURATION="${SWIPE_DURATION:-320}"
SKIP_INPUT="${SKIP_INPUT:-0}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-portal-smoke-v0.portal4c.sh --url http://<r2-ip>:37601 --code <pairing-code>

Environment/flags:
  VARIANT=v0.portal4c-session-hardening
  OUT_DIR=hard-rom/inspect/<variant>/portal-smoke-live
  TIMEOUT=8
  SKIP_INPUT=1
  TAP_X=1000 TAP_Y=2250
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
session = data.get("session", {})
if session.get("accessControl") != "bearer-token-pair-code-rotation":
    raise SystemExit("unexpected accessControl in pair session")
if session.get("pairingCodeUse") != "rotates-after-success":
    raise SystemExit("pairing code rotation marker missing")
print(f"token_len={len(token)}")
print("pair_session_access_control=bearer-token-pair-code-rotation")
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
    "portalVersion": "0.5.5",
    "webrtc": "signaling-rtp-probe-mp4-live-session-hardening",
    "webrtcCodec": "H264",
    "browserPlayback": "mp4-live-loop-fallback",
    "mediaCapabilities": "/api/media/capabilities",
    "videoStream": "/api/video/h264",
    "videoClip": "/api/video/mp4",
    "rtpProbe": "/api/rtp/h264",
    "webrtcOffer": "/api/webrtc/offer",
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
session = data.get("session", {})
if session.get("accessControl") != "bearer-token-pair-code-rotation":
    raise SystemExit("status session accessControl mismatch")
if session.get("pairingCodeUse") != "rotates-after-success":
    raise SystemExit("status pairingCodeUse mismatch")
if not isinstance(session.get("successfulPairs"), int) or session.get("successfulPairs") < 1:
    raise SystemExit("status successfulPairs did not record pair")
print("status_portal_version=0.5.5")
print("status_webrtc=signaling-rtp-probe-mp4-live-session-hardening")
print("status_screen_backend=privileged-surfacecontrol-png")
print("status_input_backend=privileged-inputmanager")
print("status_session_access_control=bearer-token-pair-code-rotation")
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
if data.get("portalVersion") != "0.5.5":
    raise SystemExit("capabilities portalVersion mismatch")
if data.get("variant") != "v0.portal4c-session-hardening":
    raise SystemExit("capabilities variant mismatch")
preferred = data.get("preferred", {})
if preferred.get("mime") != "video/avc":
    raise SystemExit("preferred mime is not video/avc")
if preferred.get("browserPlayback") != "mp4-live-loop-fallback":
    raise SystemExit("preferred browserPlayback mismatch")
if preferred.get("clip") != "/api/video/mp4":
    raise SystemExit("preferred MP4 clip path mismatch")
if preferred.get("rtpProbe") != "/api/rtp/h264":
    raise SystemExit("preferred RTP probe path mismatch")
if preferred.get("webrtcOffer") != "/api/webrtc/offer":
    raise SystemExit("preferred WebRTC offer path mismatch")
if preferred.get("accessControl") != "bearer-token-pair-code-rotation":
    raise SystemExit("preferred accessControl mismatch")
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

assert_rtp_dump() {
  local dump="$1"
  python3 - "$dump" <<'PY'
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
offset = 0
packets = []
while offset + 2 <= len(data):
    length = int.from_bytes(data[offset:offset + 2], "big")
    offset += 2
    if length < 12 or offset + length > len(data):
        raise SystemExit(f"bad RTP packet length {length} at {offset - 2}")
    packet = data[offset:offset + length]
    offset += length
    payload = packet[12:]
    packets.append({
        "marker": bool(packet[1] & 0x80),
        "payload_type": packet[1] & 0x7f,
        "sequence": int.from_bytes(packet[2:4], "big"),
        "timestamp": int.from_bytes(packet[4:8], "big"),
        "ssrc": int.from_bytes(packet[8:12], "big"),
        "nal_type": payload[0] & 0x1f if payload else -1,
        "fu_type": payload[1] & 0x1f if len(payload) > 1 and (payload[0] & 0x1f) == 28 else -1,
        "bytes": len(packet),
    })
if offset != len(data):
    raise SystemExit("RTP dump had trailing bytes")
if len(packets) < 4:
    raise SystemExit(f"too few RTP packets: {len(packets)}")
payload_types = {p["payload_type"] for p in packets}
if payload_types != {96}:
    raise SystemExit(f"unexpected RTP payload types: {payload_types}")
if not any(p["marker"] for p in packets):
    raise SystemExit("RTP dump has no marker packets")
if not any(p["nal_type"] in (1, 5, 7, 8, 28) for p in packets):
    raise SystemExit("RTP dump has no H.264-like payloads")
print(f"rtp_dump_bytes={len(data)}")
print(f"rtp_packet_count={len(packets)}")
print(f"rtp_marker_packets={sum(1 for p in packets if p['marker'])}")
print(f"rtp_sequence_first={packets[0]['sequence']}")
print(f"rtp_sequence_last={packets[-1]['sequence']}")
print("rtp_payload_types=" + ",".join(str(v) for v in sorted(payload_types)))
print("rtp_nal_types=" + ",".join(str(p["nal_type"] if p["nal_type"] != 28 else f"FU-A:{p['fu_type']}") for p in packets[:20]))
PY
}

validate_webrtc_offer_probe() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if data.get("ok") is not True:
    raise SystemExit("WebRTC offer probe ok is not true")
if data.get("mode") != "webrtc-signaling-probe":
    raise SystemExit("WebRTC offer mode mismatch")
if data.get("portalVersion") != "0.5.5":
    raise SystemExit("WebRTC offer portalVersion mismatch")
if data.get("variant") != "v0.portal4c-session-hardening":
    raise SystemExit("WebRTC offer variant mismatch")
if data.get("nativeWebRtcRuntime") is not False:
    raise SystemExit("nativeWebRtcRuntime should be false for v0.portal4c")
if data.get("dtlsSrtp") is not False:
    raise SystemExit("dtlsSrtp should be false for v0.portal4c")
if data.get("rtpProbe") != "/api/rtp/h264":
    raise SystemExit("WebRTC offer RTP probe path mismatch")
if data.get("fallback") != "/api/video/mp4":
    raise SystemExit("WebRTC offer fallback path mismatch")
print("webrtc_offer_probe=ok")
print(f"webrtc_offer_sdp_bytes={data.get('sdpBytes')}")
print(f"webrtc_offer_has_h264={data.get('hasH264')}")
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
  grep -q "MP4 playback" "$index_body" || die "index missing MP4 playback text"
  grep -q "Start Live" "$index_body" || die "index missing Live playback button"
  grep -q "liveMetrics" "$index_body" || die "index missing Live metrics path"
  grep -q "sessionState" "$index_body" || die "index missing session status"
  grep -q "Forget Session" "$index_body" || die "index missing local-session clear control"
  grep -q "Start MP4" "$index_body" || die "index missing MP4 playback button"
  grep -q "/api/video/mp4" "$index_body" || die "index missing MP4 endpoint"
  grep -q "WebRTC Offer" "$index_body" || die "index missing WebRTC offer button"
  grep -q "Probe RTP" "$index_body" || die "index missing RTP probe button"
  grep -q "/api/webrtc/offer" "$index_body" || die "index missing WebRTC offer endpoint"
  grep -q "/api/rtp/h264" "$index_body" || die "index missing RTP endpoint"
  grep -q "RTCPeerConnection" "$index_body" || die "index missing WebRTC browser path"
  grep -q "parseRtpDump" "$index_body" || die "index missing RTP dump parser"
  grep -q "EncodedVideoChunk" "$index_body" || die "index missing WebCodecs chunk path"
  grep -q "splitAnnexB" "$index_body" || die "index missing Annex-B parser"
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

  echo "## POST /api/pair replay with consumed code"
  pair_replay_headers="${OUT_DIR}/pair-replay.headers"
  pair_replay_json="${OUT_DIR}/pair-replay.json"
  pair_replay_code="$(curl_request POST "/api/pair" "$pair_replay_json" "$pair_replay_headers" "$(cat "$pair_body")")"
  assert_http "$pair_replay_code" "403" "POST /api/pair replay with consumed code"
  grep -q "bad_pairing_code" "$pair_replay_json" || die "pair replay did not fail with bad_pairing_code"
  cat "$pair_replay_json"
  echo
  echo "pairing_code_replay_rejected=true"
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

  echo "## POST /api/webrtc/offer authorized"
  webrtc_body="${OUT_DIR}/webrtc-offer-body.json"
  webrtc_headers="${OUT_DIR}/webrtc-offer.headers"
  webrtc_json="${OUT_DIR}/webrtc-offer.json"
  python3 - "$webrtc_body" <<'PY'
import json
import sys
from pathlib import Path

sdp = "\r\n".join([
    "v=0",
    "o=- 46117327 2 IN IP4 127.0.0.1",
    "s=Smartisax Portal Smoke",
    "t=0 0",
    "a=group:BUNDLE 0",
    "a=ice-ufrag:smkx",
    "a=fingerprint:sha-256 00:11:22:33:44:55",
    "m=video 9 UDP/TLS/RTP/SAVPF 96",
    "c=IN IP4 0.0.0.0",
    "a=mid:0",
    "a=recvonly",
    "a=rtpmap:96 H264/90000",
    "a=fmtp:96 packetization-mode=1;profile-level-id=42e01f",
    "",
])
Path(sys.argv[1]).write_text(json.dumps({"type": "offer", "sdp": sdp}), encoding="utf-8")
PY
  webrtc_code="$(curl_request POST "/api/webrtc/offer" "$webrtc_json" "$webrtc_headers" "$(cat "$webrtc_body")" "$token")"
  assert_http "$webrtc_code" "200" "POST /api/webrtc/offer"
  cat "$webrtc_json"
  echo
  validate_webrtc_offer_probe "$webrtc_json"
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

  echo "## GET /api/video/mp4 authorized"
  mp4_headers="${OUT_DIR}/video-mp4.headers"
  mp4_file="${OUT_DIR}/video-mp4.mp4"
  mp4_code="$(curl_request GET "/api/video/mp4?frames=8&fps=4&width=720" "$mp4_file" "$mp4_headers" "" "$token")"
  assert_http "$mp4_code" "200" "GET /api/video/mp4"
  grep -qi "Content-Type: video/mp4" "$mp4_headers" || die "MP4 response is not video/mp4"
  wc -c "$mp4_file"
  python3 - "$mp4_file" <<'PY'
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
if len(data) < 1024:
    raise SystemExit(f"MP4 clip too small: {len(data)}")
for box in (b"ftyp", b"moov", b"mdat", b"avc1"):
    if box not in data:
        raise SystemExit(f"MP4 missing box marker {box!r}")
print(f"mp4_bytes={len(data)}")
print("mp4_box_markers=ftyp,moov,mdat,avc1")
PY
  echo

  echo "## GET /api/rtp/h264 authorized"
  rtp_headers="${OUT_DIR}/rtp-h264.headers"
  rtp_dump="${OUT_DIR}/rtp-h264.dump"
  rtp_code="$(curl_request GET "/api/rtp/h264?frames=6&fps=6&width=720&payload=1200" "$rtp_dump" "$rtp_headers" "" "$token")"
  assert_http "$rtp_code" "200" "GET /api/rtp/h264"
  grep -qi "Content-Type: application/x-smartisax-rtp-dump" "$rtp_headers" || die "RTP response is not application/x-smartisax-rtp-dump"
  wc -c "$rtp_dump"
  assert_rtp_dump "$rtp_dump"
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

  echo "result=PORTAL_SMOKE_V0PORTAL4C_COMPLETED"
} 2>&1 | tee "$REPORT"

echo "Report: $REPORT"
