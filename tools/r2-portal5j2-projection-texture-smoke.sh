#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERIAL="${SERIAL:-bb12d264}"
VARIANT="${VARIANT:-v0.portal5j.2-projection-binder-transact}"
URL="${URL:-}"
PAIRING_CODE="${PAIRING_CODE:-}"
TOKEN="${TOKEN:-}"
CHROME="${CHROME:-${CHROME_PATH:-}}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-projection-texture-smoke-live}"
SUMMARY_TITLE="${SUMMARY_TITLE:-${VARIANT} Projection Texture WebRTC Smoke}"
OBSERVE_MS="${OBSERVE_MS:-20000}"
TIMEOUT_MS="${TIMEOUT_MS:-100000}"
PROFILES="${PROFILES:-1080p30-texture 1080p60-texture}"
EXPECTED_RUNTIME_MAX_FPS="${EXPECTED_RUNTIME_MAX_FPS:-60}"
TIMEOUT="${TIMEOUT:-10}"
INPUT_LATENCY_TEST="${INPUT_LATENCY_TEST:-}"
INPUT_PING_COUNT="${INPUT_PING_COUNT:-}"
INPUT_PING_INTERVAL_MS="${INPUT_PING_INTERVAL_MS:-80}"
STATS_INTERVAL_MS="${STATS_INTERVAL_MS:-1000}"
QUIET_PRESENTATION="${QUIET_PRESENTATION:-0}"
PRESENTER_MODE="${PRESENTER_MODE:-video}"
TOUCH_PHOTON_TEST="${TOUCH_PHOTON_TEST:-}"
MOVE_STREAM_TEST="${MOVE_STREAM_TEST:-}"
MOVE_STREAM_MOVES="${MOVE_STREAM_MOVES:-24}"
MOVE_STREAM_INTERVAL_MS="${MOVE_STREAM_INTERVAL_MS:-16}"
MOVE_STREAM_BATCH_SIZE="${MOVE_STREAM_BATCH_SIZE:-5}"
PREFER_CODECS="${PREFER_CODECS:-${PREFER_CODEC:-H264}}"
RVFC_CADENCE_LITE="${RVFC_CADENCE_LITE:-0}"
EXPECT_MOVE_CHANNEL="${EXPECT_MOVE_CHANNEL:-0}"
EXPECT_INPUT_FRAME_BOOST="${EXPECT_INPUT_FRAME_BOOST:-0}"
EXPECT_INPUT_URGENT_BOOST="${EXPECT_INPUT_URGENT_BOOST:-0}"
FAIL_ON_SMOKE_FAILURE="${FAIL_ON_SMOKE_FAILURE:-0}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-portal5j2-projection-texture-smoke.sh --url http://<r2-ip>:37601 --code <pairing-code>
  tools/r2-portal5j2-projection-texture-smoke.sh --url http://<r2-ip>:37601 --token <bearer-token>
  tools/r2-portal5j2-projection-texture-smoke.sh --url http://<r2-ip>:37601 --code <pairing-code> --chrome /path/to/browser-or-wrapper

Runs the v0.portal5j.2 projection-texture WebRTC smoke:
  - pairs with the LAN Portal using redacted pair evidence
  - verifies /api/webrtc/capture/probe is still createProjection=ok
  - applies projection-texture runtime configs such as 1080/30, 1080/60, and 1080/90
  - runs desktop-browser WebRTC H.264 playback plus smartisax-input gestures
  - optionally captures browser-side frame interval and DataChannel ack latency
  - optionally captures touch-to-photon marker latency and move-stream acks
  - optionally batches move-stream points to reduce DataChannel ack jitter
  - optionally requires input-frame-boost runtime counters when EXPECT_INPUT_FRAME_BOOST=1
  - optionally applies quality gates from EXPECT_* environment thresholds
  - optionally enables quiet-presentation mode with QUIET_PRESENTATION=1
  - optionally switches the receiver presenter with PRESENTER_MODE=video|canvas|dual|probe
  - prefers codecs from PREFER_CODECS, default H264 for legacy comparability
  - captures meminfo, cpuinfo, sessions, config, status, and focused logcat
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
    --chrome)
      [ "$#" -ge 2 ] || die "--chrome requires a value"
      CHROME="$2"
      shift 2
      ;;
    --out-dir)
      [ "$#" -ge 2 ] || die "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --profiles)
      [ "$#" -ge 2 ] || die "--profiles requires a value"
      PROFILES="$2"
      shift 2
      ;;
    --observe-ms)
      [ "$#" -ge 2 ] || die "--observe-ms requires a value"
      OBSERVE_MS="$2"
      shift 2
      ;;
    --timeout-ms)
      [ "$#" -ge 2 ] || die "--timeout-ms requires a value"
      TIMEOUT_MS="$2"
      shift 2
      ;;
    --input-latency-test)
      INPUT_LATENCY_TEST="1"
      shift
      ;;
    --input-ping-count)
      [ "$#" -ge 2 ] || die "--input-ping-count requires a value"
      INPUT_PING_COUNT="$2"
      shift 2
      ;;
    --input-ping-interval-ms)
      [ "$#" -ge 2 ] || die "--input-ping-interval-ms requires a value"
      INPUT_PING_INTERVAL_MS="$2"
      shift 2
      ;;
    --stats-interval-ms)
      [ "$#" -ge 2 ] || die "--stats-interval-ms requires a value"
      STATS_INTERVAL_MS="$2"
      shift 2
      ;;
    --presenter-mode)
      [ "$#" -ge 2 ] || die "--presenter-mode requires a value"
      PRESENTER_MODE="$2"
      shift 2
      ;;
    --touch-photon-test)
      TOUCH_PHOTON_TEST="1"
      shift
      ;;
    --move-stream-test)
      MOVE_STREAM_TEST="1"
      shift
      ;;
    --move-stream-moves)
      [ "$#" -ge 2 ] || die "--move-stream-moves requires a value"
      MOVE_STREAM_MOVES="$2"
      shift 2
      ;;
    --move-stream-interval-ms)
      [ "$#" -ge 2 ] || die "--move-stream-interval-ms requires a value"
      MOVE_STREAM_INTERVAL_MS="$2"
      shift 2
      ;;
    --move-stream-batch-size)
      [ "$#" -ge 2 ] || die "--move-stream-batch-size requires a value"
      MOVE_STREAM_BATCH_SIZE="$2"
      shift 2
      ;;
    --prefer-codec)
      [ "$#" -ge 2 ] || die "--prefer-codec requires a value"
      PREFER_CODECS="$2"
      shift 2
      ;;
    --prefer-codecs)
      [ "$#" -ge 2 ] || die "--prefer-codecs requires a value"
      PREFER_CODECS="$2"
      shift 2
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

need_executable adb
need_executable curl
need_executable node
need_executable python3

mkdir -p "$OUT_DIR"

curl_request() {
  local method="$1" path="$2" output="$3" body="${4:-}" token="${5:-}"
  local headers="${output}.headers"
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

profile_config() {
  case "$1" in
    1080p30-texture|1080-30-texture)
      cat <<'JSON'
{"config":{"frameWidthPortrait":1080,"frameWidthLandscape":1080,"fps":30,"minBitrateBps":8000000,"targetBitrateBps":12000000,"maxBitrateBps":12000000,"captureBackend":"projection-texture"}}
JSON
      ;;
  1080p60-texture|1080-60-texture)
    cat <<'JSON'
{"config":{"frameWidthPortrait":1080,"frameWidthLandscape":1080,"fps":60,"presentationFps":60,"transportFps":60,"inputRefreshHz":90,"minBitrateBps":8000000,"targetBitrateBps":12000000,"maxBitrateBps":12000000,"captureBackend":"projection-texture"}}
JSON
    ;;
    1080p90-texture|1080-90-texture)
      if [ "${PRESENTATION_TRANSPORT_PACING:-0}" = "1" ]; then
        cat <<'JSON'
{"config":{"frameWidthPortrait":1080,"frameWidthLandscape":1080,"fps":90,"presentationFps":60,"transportFps":60,"inputRefreshHz":90,"minBitrateBps":6000000,"targetBitrateBps":9000000,"maxBitrateBps":10000000,"captureBackend":"projection-texture"}}
JSON
      else
        cat <<'JSON'
{"config":{"frameWidthPortrait":1080,"frameWidthLandscape":1080,"fps":90,"minBitrateBps":12000000,"targetBitrateBps":16000000,"maxBitrateBps":18000000,"captureBackend":"projection-texture"}}
JSON
      fi
      ;;
    *)
      die "unknown profile: $1"
      ;;
  esac
}

profile_label() {
  case "$1" in
    1080p30-texture|1080-30-texture) printf '1080/30 projection-texture' ;;
    1080p60-texture|1080-60-texture) printf '1080/60 projection-texture' ;;
    1080p90-texture|1080-90-texture) printf '1080/90 projection-texture' ;;
    *) printf '%s' "$1" ;;
  esac
}

capture_meminfo() {
  local output="$1"
  adb -s "$SERIAL" shell dumpsys meminfo com.smartisax.browser > "$output" || true
}

capture_cpuinfo() {
  local output="$1"
  adb -s "$SERIAL" shell "dumpsys cpuinfo | grep -E 'TOTAL|com.smartisax.browser|system_server|surfaceflinger|webview|mediaserver|media.codec' | head -n 80" > "$output" || true
}

capture_logcat() {
  local output="$1"
  adb -s "$SERIAL" logcat -d -v time \
    | grep -E 'Smartisax|DevicePortal|Projection|MediaProjection|WebRtc|webrtc|libjingle|Video|OMX|c2.qti|qcom.video.encoder|AndroidRuntime|FATAL|SIGSEGV|Exception|InputManager|DataChannel|SurfaceTextureHelper' \
    > "$output" || true
}

if [ -z "$TOKEN" ]; then
  pair_body="${OUT_DIR}/pair-body.json"
  pair_json="${OUT_DIR}/pair-redacted.json"
  token_tmp="${OUT_DIR}/.token.tmp"
  python3 - "$pair_body" "$PAIRING_CODE" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"code": sys.argv[2]}), encoding="utf-8")
PY
  raw_pair="$(mktemp)"
  pair_code="$(curl_request POST "/api/pair" "$raw_pair" "$(cat "$pair_body")")"
  assert_http "$pair_code" "200" "POST /api/pair"
  python3 - "$raw_pair" "$pair_json" "$token_tmp" "$pair_code" <<'PY'
import json
import sys
from pathlib import Path
raw_path, redacted_path, token_path, code = sys.argv[1:5]
body = json.loads(Path(raw_path).read_text(encoding="utf-8"))
token = body.get("token", "")
if not token:
    raise SystemExit("pair response missing token")
redacted = dict(body)
redacted["token"] = "<redacted>"
Path(redacted_path).write_text(json.dumps({"httpStatus": int(code), "body": redacted}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
Path(token_path).write_text(token, encoding="utf-8")
PY
  TOKEN="$(cat "$token_tmp")"
  rm -f "$raw_pair" "$token_tmp"
fi

status_json="${OUT_DIR}/status-before-profiles.json"
status_code="$(curl_request GET "/api/status" "$status_json" "" "$TOKEN")"
assert_http "$status_code" "200" "GET /api/status"

initial_config="${OUT_DIR}/webrtc-config-initial.json"
initial_code="$(curl_request GET "/api/webrtc/config" "$initial_config" "" "$TOKEN")"
assert_http "$initial_code" "200" "GET /api/webrtc/config"

probe_json="${OUT_DIR}/capture-probe-before-profiles.json"
probe_code="$(curl_request GET "/api/webrtc/capture/probe?ts=$(date +%s)" "$probe_json" "" "$TOKEN")"
assert_http "$probe_code" "200" "GET /api/webrtc/capture/probe"
python3 - "$initial_config" "$probe_json" <<'PY'
import json
import os
import sys
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probe = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
limits = config.get("limits", {})
if limits.get("maxFrameWidth") != 1080:
    raise SystemExit(f"maxFrameWidth={limits.get('maxFrameWidth')!r}, expected 1080")
expected_max_fps = int(os.environ.get("EXPECTED_RUNTIME_MAX_FPS", "60"))
if limits.get("maxFps") != expected_max_fps:
    raise SystemExit(f"maxFps={limits.get('maxFps')!r}, expected {expected_max_fps}")
if "projection-texture" not in limits.get("captureBackends", []):
    raise SystemExit("projection-texture not listed in captureBackends")
if probe.get("createProjection") != "ok":
    raise SystemExit(f"createProjection={probe.get('createProjection')!r}, expected ok")
print("preflight_config_and_probe=ok")
PY

summary_jsonl="${OUT_DIR}/projection-texture-summary.jsonl"
: > "$summary_jsonl"

for profile in $PROFILES; do
  label="$(profile_label "$profile")"
  slug="$(printf '%s' "$profile" | tr '/' '-' | tr -cd 'A-Za-z0-9_.-')"
  profile_dir="${OUT_DIR}/${slug}"
  mkdir -p "$profile_dir"
  config_body="${profile_dir}/request-config.json"
  profile_config "$profile" > "$config_body"

  echo "== ${label} (${profile}) =="
  adb -s "$SERIAL" logcat -c || true
  capture_meminfo "${profile_dir}/meminfo-before.txt"
  capture_cpuinfo "${profile_dir}/cpuinfo-before.txt"

  close_before="${profile_dir}/close-before.json"
  close_before_code="$(curl_request POST "/api/webrtc/close" "$close_before" '{"sessionId":"all"}' "$TOKEN")"
  assert_http "$close_before_code" "200" "POST /api/webrtc/close before ${profile}"

  config_apply="${profile_dir}/config-apply.json"
  config_code="$(curl_request POST "/api/webrtc/config" "$config_apply" "$(cat "$config_body")" "$TOKEN")"
  assert_http "$config_code" "200" "POST /api/webrtc/config ${profile}"

  config_after="${profile_dir}/config-after.json"
  config_after_code="$(curl_request GET "/api/webrtc/config" "$config_after" "" "$TOKEN")"
  assert_http "$config_after_code" "200" "GET /api/webrtc/config ${profile}"

  chrome_variant="${VARIANT}-${slug}"
  chrome_output="${profile_dir}/chrome-webrtc.stdout.json"
  chrome_args=(
    "${ROOT_DIR}/tools/r2-portal5a-chrome-webrtc-smoke.mjs"
    --url "$URL"
    --token "$TOKEN"
    --variant "$chrome_variant"
    --out-dir "$profile_dir"
    --prefer-codecs "$PREFER_CODECS"
    --input-gesture-test
    --observe-ms "$OBSERVE_MS"
    --timeout-ms "$TIMEOUT_MS"
    --stats-interval-ms "$STATS_INTERVAL_MS"
    --presenter-mode "$PRESENTER_MODE"
  )
  if [ -n "$CHROME" ]; then
    chrome_args+=(--chrome "$CHROME")
  fi
  if [ -n "$INPUT_LATENCY_TEST" ]; then
    chrome_args+=(--input-latency-test)
  fi
  if [ -n "$INPUT_PING_COUNT" ]; then
    chrome_args+=(--input-ping-count "$INPUT_PING_COUNT")
  fi
  if [ -n "$INPUT_PING_INTERVAL_MS" ]; then
    chrome_args+=(--input-ping-interval-ms "$INPUT_PING_INTERVAL_MS")
  fi
  if [ -n "$TOUCH_PHOTON_TEST" ]; then
    chrome_args+=(--touch-photon-test)
  fi
  if [ "$QUIET_PRESENTATION" = "1" ]; then
    chrome_args+=(--quiet-presentation)
  fi
  if [ "$RVFC_CADENCE_LITE" = "1" ]; then
    chrome_args+=(--rvfc-cadence-lite)
  fi
  if [ -n "$MOVE_STREAM_TEST" ]; then
    chrome_args+=(--move-stream-test)
  fi
  if [ -n "$TOUCH_PHOTON_TEST" ] || [ -n "$MOVE_STREAM_TEST" ]; then
    chrome_args+=(--move-stream-moves "$MOVE_STREAM_MOVES")
    chrome_args+=(--move-stream-interval-ms "$MOVE_STREAM_INTERVAL_MS")
    chrome_args+=(--move-stream-batch-size "$MOVE_STREAM_BATCH_SIZE")
  fi
  set +e
  node "${chrome_args[@]}" > "$chrome_output"
  chrome_exit=$?
  set -e

  sessions_after="${profile_dir}/sessions-after.json"
  sessions_code="$(curl_request GET "/api/webrtc/sessions" "$sessions_after" "" "$TOKEN")"
  assert_http "$sessions_code" "200" "GET /api/webrtc/sessions ${profile}"

  status_after="${profile_dir}/status-after.json"
  status_after_code="$(curl_request GET "/api/status" "$status_after" "" "$TOKEN")"
  assert_http "$status_after_code" "200" "GET /api/status ${profile}"

  capture_meminfo "${profile_dir}/meminfo-after.txt"
  capture_cpuinfo "${profile_dir}/cpuinfo-after.txt"
  capture_logcat "${profile_dir}/logcat-focused.txt"

  close_after="${profile_dir}/close-after.json"
  close_after_code="$(curl_request POST "/api/webrtc/close" "$close_after" '{"sessionId":"all"}' "$TOKEN")"
  assert_http "$close_after_code" "200" "POST /api/webrtc/close after ${profile}"

  python3 - "$profile" "$label" "$chrome_exit" "$profile_dir" "$summary_jsonl" <<'PY'
import glob
import json
import os
import re
import sys
from pathlib import Path

profile, label, chrome_exit, profile_dir, summary_jsonl = sys.argv[1:6]
profile_path = Path(profile_dir)

def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        return {"_error": str(exc), "_path": str(path)}

def total_pss(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace") if Path(path).exists() else ""
    match = re.search(r"TOTAL\s+([0-9,]+)", text)
    return int(match.group(1).replace(",", "")) if match else None

def interesting_cpu(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace") if Path(path).exists() else ""
    return [line.strip() for line in text.splitlines() if line.strip()][:20]

def env_float(name):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return None
    return float(raw)

def env_int(name):
    value = env_float(name)
    return None if value is None else int(value)

def fps_suffix():
    text = f"{profile} {label}".lower()
    if "90" in text:
        return "90"
    if "60" in text:
        return "60"
    if "30" in text:
        return "30"
    return ""

def profile_env_float(base):
    suffix = fps_suffix()
    if suffix:
        value = env_float(f"{base}_{suffix}")
        if value is not None:
            return value
    return env_float(base)

def profile_env_int(base):
    value = profile_env_float(base)
    return None if value is None else int(value)

def gate_at_least(name, value, threshold, unit=""):
    if threshold is None:
        return None
    ok = value is not None and value >= threshold
    return {"name": name, "op": ">=", "value": value, "threshold": threshold, "unit": unit, "ok": ok}

def gate_at_most(name, value, threshold, unit=""):
    if threshold is None:
        return None
    ok = value is not None and value <= threshold
    return {"name": name, "op": "<=", "value": value, "threshold": threshold, "unit": unit, "ok": ok}

reports = sorted(glob.glob(str(profile_path / "chrome-webrtc-smoke-*.json")))
chrome = load_json(reports[-1]) if reports else {"ok": False, "_error": "missing chrome report"}
config = load_json(profile_path / "config-after.json")
sessions = load_json(profile_path / "sessions-after.json")
status = load_json(profile_path / "status-after.json")
logcat = (profile_path / "logcat-focused.txt").read_text(encoding="utf-8", errors="replace") if (profile_path / "logcat-focused.txt").exists() else ""
timeline = chrome.get("statsTimeline") or []
fps_est = None
bitrate_est = None
loss_delta = None
if len(timeline) >= 2:
    first = timeline[0]
    last = timeline[-1]
    dt = max(1, (last.get("t", 0) - first.get("t", 0)) / 1000.0)
    frame_delta = max(0, (last.get("framesDecoded") or 0) - (first.get("framesDecoded") or 0))
    byte_delta = max(0, (last.get("bytesReceived") or 0) - (first.get("bytesReceived") or 0))
    loss_delta = max(0, (last.get("packetsLost") or 0) - (first.get("packetsLost") or 0))
    fps_est = round(frame_delta / dt, 2)
    bitrate_est = round(byte_delta * 8 / dt)
device_answer = chrome.get("deviceAnswer") or {}
frame_pump = device_answer.get("framePump") or {}
session_frame_pump = None
current_session = sessions.get("currentSession")
if isinstance(current_session, dict):
    session_frame_pump = current_session.get("framePump")
if session_frame_pump is None:
    session_list = sessions.get("sessions") or []
    if session_list and isinstance(session_list[0], dict):
        session_frame_pump = session_list[0].get("framePump")
if not isinstance(session_frame_pump, dict):
    session_frame_pump = None
effective_frame_pump = session_frame_pump or frame_pump
input_acks = chrome.get("inputChannelAcks") or []
expect_move_channel = os.environ.get("EXPECT_MOVE_CHANNEL") == "1"
move_channel_state = chrome.get("moveChannelState")
move_channel_ok = (not expect_move_channel) or move_channel_state == "open"
expect_input_frame_boost = os.environ.get("EXPECT_INPUT_FRAME_BOOST") == "1"
input_boost_requests = int(effective_frame_pump.get("inputFrameBoostRequests") or 0)
input_boost_skips = int(effective_frame_pump.get("inputFrameBoostSkips") or 0)
input_boost_frames = int(effective_frame_pump.get("inputFrameBoostFrames") or 0)
input_boost_urgent_requests = int(effective_frame_pump.get("inputFrameBoostUrgentRequests") or 0)
input_boost_urgent_skips = int(effective_frame_pump.get("inputFrameBoostUrgentSkips") or 0)
input_boost_urgent_frames = int(effective_frame_pump.get("inputFrameBoostUrgentFrames") or 0)
input_boost_ok = (not expect_input_frame_boost) or (input_boost_requests > 0 and input_boost_frames > 0)
expect_input_urgent_boost = os.environ.get("EXPECT_INPUT_URGENT_BOOST") == "1"
input_boost_urgent_ok = (not expect_input_urgent_boost) or (input_boost_urgent_requests > 0 and input_boost_urgent_frames > 0)
tap_ack = next((ack for ack in input_acks if isinstance(ack, dict) and ack.get("type") == "tap"), None)
swipe_ack = next((ack for ack in input_acks if isinstance(ack, dict) and ack.get("type") == "swipe"), None)
touch_start_ack = next((ack for ack in input_acks if isinstance(ack, dict) and ack.get("type") == "touchStart"), None)
touch_end_ack = next((ack for ack in input_acks if isinstance(ack, dict) and ack.get("type") == "touchEnd"), None)
touch_move_ack_count = sum(1 for ack in input_acks if isinstance(ack, dict) and ack.get("ok") is True and ack.get("type") in ("touchMove", "touchMoveBatch"))
touch_move_injected_events = sum(
    max(1, int(((ack.get("result") or {}).get("injectedEvents") or 1)))
    for ack in input_acks
    if isinstance(ack, dict) and ack.get("ok") is True and ack.get("type") in ("touchMove", "touchMoveBatch")
)
latency_metrics = chrome.get("latencyMetrics") or {}
video_frame_metrics = latency_metrics.get("videoFrame") or {}
animation_frame_metrics = latency_metrics.get("animationFrame") or {}
canvas_presenter_metrics = latency_metrics.get("canvasPresenter") or {}
input_latency_metrics = latency_metrics.get("input") or {}
input_latency_by_type = input_latency_metrics.get("byType") or {}
touch_photon_metrics = chrome.get("touchPhotonSummary") or latency_metrics.get("touchPhoton") or {}
marker_draw_metrics = chrome.get("markerDrawSyncSummary") or latency_metrics.get("markerDrawSync") or {}
timings = latency_metrics.get("timings") or {}
inbound = chrome.get("stats", {}).get("inboundRtp") or []

def sum_stat(rows, field):
    total = 0.0
    seen = False
    for item in rows:
        if not isinstance(item, dict):
            continue
        value = item.get(field)
        if isinstance(value, (int, float)):
            total += float(value)
            seen = True
    return total if seen else None

def round_metric(value, digits=2):
    return None if value is None else round(value, digits)

def avg_delay_ms(delay_s, count):
    if delay_s is None or not count:
        return None
    return round(delay_s * 1000.0 / max(1, int(count)), 2)

def without_samples(value):
    if not isinstance(value, dict):
        return value
    copy = dict(value)
    copy.pop("samples", None)
    return copy

receiver_hints = chrome.get("receiverPresentationHints") or []
page_lifecycle = chrome.get("pageLifecycleEvents") or []
page_state = chrome.get("pageState") or {}
chrome_launch = chrome.get("chromeLaunch") or {}
hidden_timeline_samples = sum(
    1 for item in timeline
    if isinstance(item, dict) and isinstance(item.get("pageState"), dict) and item["pageState"].get("hidden") is True
)
focus_false_timeline_samples = sum(
    1 for item in timeline
    if isinstance(item, dict) and isinstance(item.get("pageState"), dict) and item["pageState"].get("hasFocus") is False
)
hidden_lifecycle_events = sum(1 for item in page_lifecycle if isinstance(item, dict) and item.get("hidden") is True)
blur_lifecycle_events = sum(1 for item in page_lifecycle if isinstance(item, dict) and item.get("type") == "blur")
rvfc_timeline_max_gap_ms = max(
    [item.get("rvfcMaxGapMs") for item in timeline if isinstance(item, dict) and isinstance(item.get("rvfcMaxGapMs"), (int, float))],
    default=None,
)
raf_timeline_max_gap_ms = max(
    [item.get("rafMaxGapMs") for item in timeline if isinstance(item, dict) and isinstance(item.get("rafMaxGapMs"), (int, float))],
    default=None,
)
playout_delay_s = sum_stat(inbound, "jitterBufferDelay")
playout_target_s = sum_stat(inbound, "jitterBufferTargetDelay")
playout_emitted = sum_stat(inbound, "jitterBufferEmittedCount")
frames_dropped_total = sum_stat(inbound, "framesDropped")
freeze_count_total = sum_stat(inbound, "freezeCount")
freeze_duration_s = sum_stat(inbound, "totalFreezesDuration")
decoder_impl = next((item.get("decoderImplementation") for item in inbound if isinstance(item, dict) and item.get("decoderImplementation")), "")
frame_callback_gaps = video_frame_metrics.get("longGaps") or {}
touch_photon_latency = touch_photon_metrics.get("latencyMs") or {}
ping_latency = input_latency_by_type.get("ping") or {}
quality_gates = [
    gate_at_least("estimatedFps", fps_est, profile_env_float("EXPECT_MIN_EST_FPS"), "fps"),
    gate_at_least("rvfcFps", video_frame_metrics.get("callbackFps"), profile_env_float("EXPECT_MIN_RVFC_FPS"), "fps"),
    gate_at_most("packetLossDelta", loss_delta, env_int("EXPECT_PACKET_LOSS_DELTA_MAX"), "packets"),
    gate_at_most("frameGapsOver34ms", frame_callback_gaps.get("over34ms"), profile_env_int("EXPECT_GAPS34_MAX"), "gaps"),
    gate_at_most("touchPhotonP95", touch_photon_latency.get("p95"), env_float("EXPECT_T2P_P95_MAX_MS"), "ms"),
    gate_at_most("pingAckP95", ping_latency.get("p95"), env_float("EXPECT_PING_P95_MAX_MS"), "ms"),
]
quality_gates = [gate for gate in quality_gates if gate is not None]
quality_gates_ok = all(gate.get("ok") for gate in quality_gates)
summary = {
    "profile": profile,
    "label": label,
    "chromeExit": int(chrome_exit),
    "ok": bool(chrome.get("ok")) and move_channel_ok and input_boost_ok and input_boost_urgent_ok and quality_gates_ok,
    "connectionState": chrome.get("connectionState"),
    "iceConnectionState": chrome.get("iceConnectionState"),
    "selectedCodec": chrome.get("selectedCodec"),
    "codecPreference": chrome.get("codecPreference"),
    "video": {
        "width": chrome.get("videoWidth"),
        "height": chrome.get("videoHeight"),
        "framesDecoded": chrome.get("framesDecoded"),
        "frameCallbacks": chrome.get("frameCallbacks"),
        "animationFrameCallbacks": chrome.get("animationFrameCallbacks"),
        "presenterDrawCallbacks": chrome.get("presenterDrawCallbacks"),
        "presenterCanvasWidth": chrome.get("presenterCanvasWidth"),
        "presenterCanvasHeight": chrome.get("presenterCanvasHeight"),
        "bytesReceived": chrome.get("bytesReceived"),
        "fpsEstimated": fps_est,
        "bitrateEstimatedBps": bitrate_est,
        "packetLossTotal": sum((item.get("packetsLost") or 0) for item in inbound),
        "packetLossDelta": loss_delta,
    },
    "presentation": {
        "quietPresentation": bool(chrome.get("quietPresentation")),
        "presenterMode": chrome.get("presenterMode", "video"),
        "canvasPresenterEnabled": bool(chrome.get("canvasPresenterEnabled")),
        "receiverHints": receiver_hints,
        "playoutDelayHintApplied": any(item.get("playoutDelayHintApplied") for item in receiver_hints if isinstance(item, dict)),
        "contentHintApplied": any(item.get("contentHintApplied") for item in receiver_hints if isinstance(item, dict)),
        "animationFrame": without_samples(animation_frame_metrics),
        "canvasPresenter": without_samples(canvas_presenter_metrics),
        "avgJitterBufferDelayMs": avg_delay_ms(playout_delay_s, playout_emitted),
        "avgJitterBufferTargetDelayMs": avg_delay_ms(playout_target_s, playout_emitted),
        "jitterBufferDelayS": round_metric(playout_delay_s),
        "jitterBufferTargetDelayS": round_metric(playout_target_s),
        "jitterBufferEmittedCount": int(playout_emitted or 0),
        "framesDropped": int(frames_dropped_total or 0),
        "freezeCount": int(freeze_count_total or 0),
        "totalFreezesDurationMs": round_metric((freeze_duration_s or 0) * 1000.0),
        "decoderImplementation": decoder_impl,
        "pageState": page_state,
        "pageLifecycleEvents": page_lifecycle,
        "pageLifecycleSummary": {
            "eventCount": len(page_lifecycle),
            "hiddenEvents": hidden_lifecycle_events,
            "blurEvents": blur_lifecycle_events,
            "hiddenTimelineSamples": hidden_timeline_samples,
            "focusFalseTimelineSamples": focus_false_timeline_samples,
            "rvfcTimelineMaxGapMs": round_metric(rvfc_timeline_max_gap_ms),
            "rafTimelineMaxGapMs": round_metric(raf_timeline_max_gap_ms),
        },
        "chromeLaunch": chrome_launch,
    },
    "deviceAnswer": {
        "elapsedMs": device_answer.get("elapsedMs"),
        "framePump": frame_pump,
        "bitrateApplied": frame_pump.get("bitrateApplied"),
        "bitrateStage": frame_pump.get("bitrateStage"),
        "captureBackend": frame_pump.get("captureBackend") or frame_pump.get("backend"),
    },
    "config": config.get("config"),
    "statusRuntimeConfig": status.get("webrtcRuntimeConfig"),
    "sessionFramePump": session_frame_pump,
    "memoryKb": {
        "beforeTotalPss": total_pss(profile_path / "meminfo-before.txt"),
        "afterTotalPss": total_pss(profile_path / "meminfo-after.txt"),
    },
    "cpu": {
        "before": interesting_cpu(profile_path / "cpuinfo-before.txt"),
        "after": interesting_cpu(profile_path / "cpuinfo-after.txt"),
    },
    "dataChannel": {
        "state": chrome.get("inputChannelState"),
        "moveState": move_channel_state,
        "moveReady": move_channel_state == "open",
        "moveRequired": expect_move_channel,
        "inputGestureOk": chrome.get("inputGestureOk"),
        "tapAck": tap_ack,
        "swipeAck": swipe_ack,
        "ackCount": len(input_acks),
    },
    "moveStream": {
        "test": chrome.get("moveStreamTest"),
        "ok": chrome.get("moveStreamOk"),
        "configuredMoves": chrome.get("moveStreamMoves"),
        "intervalMs": chrome.get("moveStreamIntervalMs"),
        "batchSize": chrome.get("moveStreamBatchSize"),
        "touchMoveAckCount": chrome.get("moveStreamAckCount", touch_move_ack_count),
        "injectedMoveEvents": chrome.get("moveStreamInjectedEvents", touch_move_injected_events),
        "touchStartAck": touch_start_ack,
        "touchEndAck": touch_end_ack,
    },
    "inputFrameBoost": {
        "required": expect_input_frame_boost,
        "ok": input_boost_ok,
        "requests": input_boost_requests,
        "skips": input_boost_skips,
        "frames": input_boost_frames,
        "urgentRequired": expect_input_urgent_boost,
        "urgentOk": input_boost_urgent_ok,
        "urgentRequests": input_boost_urgent_requests,
        "urgentSkips": input_boost_urgent_skips,
        "urgentFrames": input_boost_urgent_frames,
        "lastRequestElapsedMs": effective_frame_pump.get("lastInputFrameBoostRequestElapsedMs"),
        "lastSkipElapsedMs": effective_frame_pump.get("lastInputFrameBoostSkipElapsedMs"),
        "lastFrameElapsedMs": effective_frame_pump.get("lastInputFrameBoostElapsedMs"),
        "lastUrgentRequestElapsedMs": effective_frame_pump.get("lastInputFrameBoostUrgentRequestElapsedMs"),
        "lastUrgentSkipElapsedMs": effective_frame_pump.get("lastInputFrameBoostUrgentSkipElapsedMs"),
        "lastUrgentFrameElapsedMs": effective_frame_pump.get("lastInputFrameBoostUrgentFrameElapsedMs"),
    },
    "touchPhoton": {
        "test": chrome.get("touchPhotonTest"),
        "ok": chrome.get("touchPhotonOk"),
        "summary": touch_photon_metrics,
        "markerDrawSync": without_samples(marker_draw_metrics),
    },
    "markerDrawSync": without_samples(marker_draw_metrics),
    "latency": {
        "answerElapsedMs": device_answer.get("elapsedMs"),
        "connectedAtMs": timings.get("connectedAtMs"),
        "firstTrackAtMs": timings.get("firstTrackAtMs"),
        "firstFrameAtMs": timings.get("firstFrameAtMs") or video_frame_metrics.get("firstFrameAtMs"),
        "inputChannelOpenAtMs": timings.get("inputChannelOpenAtMs"),
        "frameCallbackFps": video_frame_metrics.get("callbackFps"),
        "frameCallbackIntervalMs": video_frame_metrics.get("callbackIntervalMs"),
        "frameCallbackLongGaps": video_frame_metrics.get("longGaps"),
        "frameCallbackGapClusters": video_frame_metrics.get("gapClusters"),
        "animationFrameFps": animation_frame_metrics.get("callbackFps"),
        "animationFrameIntervalMs": animation_frame_metrics.get("intervalMs"),
        "animationFrameLongGaps": animation_frame_metrics.get("longGaps"),
        "canvasPresenterDrawFps": canvas_presenter_metrics.get("drawFps"),
        "canvasPresenterMediaChangeFps": canvas_presenter_metrics.get("mediaChangeFps"),
        "canvasPresenterIntervalMs": canvas_presenter_metrics.get("intervalMs"),
        "canvasPresenterMediaIntervalMs": canvas_presenter_metrics.get("mediaIntervalMs"),
        "canvasPresenterLongGaps": canvas_presenter_metrics.get("longGaps"),
        "canvasPresenterDrawDurationMs": canvas_presenter_metrics.get("drawDurationMs"),
        "inputAckLatencyMs": input_latency_metrics.get("all"),
        "pingAckLatencyMs": input_latency_by_type.get("ping"),
        "tapAckLatencyMs": (tap_ack or {}).get("clientAckLatencyMs"),
        "swipeAckLatencyMs": (swipe_ack or {}).get("clientAckLatencyMs"),
        "touchPhotonLatencyMs": touch_photon_metrics.get("latencyMs"),
        "markerDrawLatencyMs": marker_draw_metrics.get("drawLatencyMs"),
        "firstFrame": bool(chrome.get("firstFrame")),
        "elapsedMs": chrome.get("elapsedMs"),
        "note": "browser-side frame cadence, DataChannel ack latency, and optional marker pixel-detected touch-to-photon latency",
    },
    "quality": {
        "requested": label,
        "displayedResolution": f"{chrome.get('videoWidth')}x{chrome.get('videoHeight')}",
        "framePumpResolution": f"{frame_pump.get('width')}x{frame_pump.get('height')}",
        "gates": quality_gates,
        "logcatEncoderLines": [line for line in logcat.splitlines() if "encoder" in line.lower() or "bitrate" in line.lower() or "projection" in line.lower()][:24],
    },
    "report": reports[-1] if reports else "",
}
with open(summary_jsonl, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(summary, ensure_ascii=False) + "\n")
print(json.dumps(summary, ensure_ascii=False, indent=2))
PY

  if [ "$chrome_exit" -ne 0 ]; then
    echo "chrome_webrtc_${profile}=failed_exit_${chrome_exit}"
  else
    echo "chrome_webrtc_${profile}=ok"
  fi
done

summary_json="${OUT_DIR}/projection-texture-summary.json"
summary_md="${OUT_DIR}/projection-texture-summary.md"
python3 - "$summary_jsonl" "$summary_json" "$summary_md" "$SUMMARY_TITLE" <<'PY'
import json
import os
import sys
from pathlib import Path

jsonl, summary_json, summary_md = map(Path, sys.argv[1:4])
rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line.strip()]
summary_json.write_text(json.dumps({"profiles": rows}, ensure_ascii=False, indent=2), encoding="utf-8")

title = sys.argv[4] if len(sys.argv) > 4 else "Projection Texture WebRTC Smoke"
lines = [f"# {title}", ""]
lines.append("| Profile | OK | Codec | Capture | Frame Pump | Source | Continuity | Dropped | Captured | Browser Video | Decoded | Est FPS | Est Bitrate | Loss Delta | PSS After | Input | Move Ch | Answer |")
lines.append("| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: |")
for row in rows:
    video = row.get("video", {})
    answer = row.get("deviceAnswer", {})
    fp = answer.get("framePump", {}) or {}
    sfp = row.get("sessionFramePump", {}) or {}
    mem = row.get("memoryKb", {})
    data = row.get("dataChannel", {})
    move_required = data.get("moveRequired")
    move_ready = data.get("moveReady")
    move_state = data.get("moveState")
    lines.append(
        "| {label} | {ok} | {codec} | {capture} | {fpw}x{fph}@{fps} | {source} | {continuity} | {dropped} | {captured} | {vw}x{vh} | {decoded} | {efps} | {br} | {loss} | {pss} | {input_ok} | {move_ch} | {ans} |".format(
            label=row.get("label"),
            ok="PASS" if row.get("ok") else "FAIL",
            codec=row.get("selectedCodec"),
            capture=answer.get("captureBackend") or fp.get("backend"),
            fpw=fp.get("width"),
            fph=fp.get("height"),
            fps=fp.get("fps"),
            source=sfp.get("sourceFrames", fp.get("sourceFrames")),
            continuity=sfp.get("continuityFrames", fp.get("continuityFrames")),
            dropped=sfp.get("droppedFrames", fp.get("droppedFrames")),
            captured=sfp.get("capturedFrames", fp.get("capturedFrames")),
            vw=video.get("width"),
            vh=video.get("height"),
            decoded=video.get("framesDecoded"),
            efps=video.get("fpsEstimated"),
            br=video.get("bitrateEstimatedBps"),
            loss=video.get("packetLossDelta"),
            pss=mem.get("afterTotalPss"),
            input_ok="PASS" if data.get("inputGestureOk") else "FAIL",
            move_ch=("PASS" if move_ready else ("SKIP" if not move_required else f"FAIL:{move_state}")),
            ans=answer.get("elapsedMs"),
        )
    )
lines.append("")
lines.append("## Latency Metrics")
lines.append("")
lines.append("| Profile | Connected | First Frame | RVFC FPS | RAF FPS | Canvas Draw FPS | Canvas Media FPS | Frame Δ p50 | Frame Δ p95 | Frame Δ max | RVFC >34ms | RAF >34ms | Canvas >34ms | Ping Ack p50 | Ping Ack p95 | Tap Ack | Swipe Ack |")
lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

def ms(value):
    return "" if value is None else str(value)

for row in rows:
    latency = row.get("latency", {}) or {}
    frame_interval = latency.get("frameCallbackIntervalMs") or {}
    long_gaps = latency.get("frameCallbackLongGaps") or {}
    raf_gaps = latency.get("animationFrameLongGaps") or {}
    canvas_gaps = latency.get("canvasPresenterLongGaps") or {}
    ping = latency.get("pingAckLatencyMs") or {}
    lines.append(
        "| {label} | {connected} | {first_frame} | {rvfc_fps} | {raf_fps} | {canvas_draw_fps} | {canvas_media_fps} | {frame_p50} | {frame_p95} | {frame_max} | {gaps34} | {raf_gaps34} | {canvas_gaps34} | {ping_p50} | {ping_p95} | {tap} | {swipe} |".format(
            label=row.get("label"),
            connected=ms(latency.get("connectedAtMs")),
            first_frame=ms(latency.get("firstFrameAtMs")),
            rvfc_fps=ms(latency.get("frameCallbackFps")),
            raf_fps=ms(latency.get("animationFrameFps")),
            canvas_draw_fps=ms(latency.get("canvasPresenterDrawFps")),
            canvas_media_fps=ms(latency.get("canvasPresenterMediaChangeFps")),
            frame_p50=ms(frame_interval.get("p50")),
            frame_p95=ms(frame_interval.get("p95")),
            frame_max=ms(frame_interval.get("max")),
            gaps34=ms(long_gaps.get("over34ms")),
            raf_gaps34=ms(raf_gaps.get("over34ms")),
            canvas_gaps34=ms(canvas_gaps.get("over34ms")),
            ping_p50=ms(ping.get("p50")),
            ping_p95=ms(ping.get("p95")),
            tap=ms(latency.get("tapAckLatencyMs")),
            swipe=ms(latency.get("swipeAckLatencyMs")),
        )
    )
lines.append("")
lines.append("## Presentation / Playout")
lines.append("")
lines.append("| Profile | Quiet | Presenter | Canvas | Canvas Draw p95 | Canvas Media p95 | Playout Hint | Motion Hint | Jitter Avg | Target Avg | Dropped | Freezes | Freeze ms | Decoder |")
lines.append("| --- | --- | --- | --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |")
for row in rows:
    presentation = row.get("presentation", {}) or {}
    canvas_presenter = presentation.get("canvasPresenter") or {}
    canvas_draw = canvas_presenter.get("drawDurationMs") or {}
    canvas_media = canvas_presenter.get("mediaIntervalMs") or {}
    lines.append(
        "| {label} | {quiet} | {presenter} | {canvas_enabled} | {canvas_draw_p95} | {canvas_media_p95} | {playout} | {motion} | {jitter} | {target} | {dropped} | {freezes} | {freeze_ms} | {decoder} |".format(
            label=row.get("label"),
            quiet="yes" if presentation.get("quietPresentation") else "no",
            presenter=presentation.get("presenterMode") or "video",
            canvas_enabled="yes" if presentation.get("canvasPresenterEnabled") else "no",
            canvas_draw_p95=ms(canvas_draw.get("p95")),
            canvas_media_p95=ms(canvas_media.get("p95")),
            playout="PASS" if presentation.get("playoutDelayHintApplied") else "UNSUPPORTED",
            motion="PASS" if presentation.get("contentHintApplied") else "UNSUPPORTED",
            jitter=ms(presentation.get("avgJitterBufferDelayMs")),
            target=ms(presentation.get("avgJitterBufferTargetDelayMs")),
            dropped=ms(presentation.get("framesDropped")),
            freezes=ms(presentation.get("freezeCount")),
            freeze_ms=ms(presentation.get("totalFreezesDurationMs")),
            decoder=presentation.get("decoderImplementation") or "",
        )
    )
lines.append("")
lines.append("## Receiver Page / Chrome")
lines.append("")
lines.append("| Profile | Anti-throttle | Window | Hidden End | Focus End | Hidden Events | Blur Events | Hidden Samples | Focus-false Samples | RVFC Max Gap | RAF Max Gap |")
lines.append("| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for row in rows:
    presentation = row.get("presentation", {}) or {}
    lifecycle = presentation.get("pageLifecycleSummary") or {}
    page_state = presentation.get("pageState") or {}
    launch = presentation.get("chromeLaunch") or {}
    lines.append(
        "| {label} | {anti} | {window} | {hidden_end} | {focus_end} | {hidden_events} | {blur_events} | {hidden_samples} | {focus_false_samples} | {rvfc_max} | {raf_max} |".format(
            label=row.get("label"),
            anti="yes" if launch.get("antiThrottle") else "no",
            window=launch.get("windowSize") or "",
            hidden_end=ms(page_state.get("hidden")),
            focus_end=ms(page_state.get("hasFocus")),
            hidden_events=ms(lifecycle.get("hiddenEvents")),
            blur_events=ms(lifecycle.get("blurEvents")),
            hidden_samples=ms(lifecycle.get("hiddenTimelineSamples")),
            focus_false_samples=ms(lifecycle.get("focusFalseTimelineSamples")),
            rvfc_max=ms(lifecycle.get("rvfcTimelineMaxGapMs")),
            raf_max=ms(lifecycle.get("rafTimelineMaxGapMs")),
        )
    )
lines.append("")
lines.append("## Input Frame Boost")
lines.append("")
lines.append("| Profile | Required | OK | Requests | Skips | Frames | Urgent | Urgent Req | Urgent Frames | Urgent Skips | Last Request | Last Frame | Last Urgent Frame |")
lines.append("| --- | --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for row in rows:
    boost = row.get("inputFrameBoost", {}) or {}
    urgent_status = "PASS" if boost.get("urgentOk") else ("SKIP" if not boost.get("urgentRequired") else "FAIL")
    lines.append(
        "| {label} | {required} | {ok} | {requests} | {skips} | {frames} | {urgent} | {urgent_requests} | {urgent_frames} | {urgent_skips} | {last_request} | {last_frame} | {last_urgent_frame} |".format(
            label=row.get("label"),
            required="yes" if boost.get("required") else "no",
            ok="PASS" if boost.get("ok") else ("SKIP" if not boost.get("required") else "FAIL"),
            requests=ms(boost.get("requests")),
            skips=ms(boost.get("skips")),
            frames=ms(boost.get("frames")),
            urgent=urgent_status,
            urgent_requests=ms(boost.get("urgentRequests")),
            urgent_frames=ms(boost.get("urgentFrames")),
            urgent_skips=ms(boost.get("urgentSkips")),
            last_request=ms(boost.get("lastRequestElapsedMs")),
            last_frame=ms(boost.get("lastFrameElapsedMs")),
            last_urgent_frame=ms(boost.get("lastUrgentFrameElapsedMs")),
        )
    )
lines.append("")
lines.append("## Touch-To-Photon / Move Stream")
lines.append("")
lines.append("| Profile | Move Stream | Batch | Move Events | Move Acks | Down Ack | Up Ack | Touch Photon | Samples | Detected | T2P p50 | T2P p95 | T2P max |")
lines.append("| --- | --- | ---: | ---: | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |")
for row in rows:
    move = row.get("moveStream", {}) or {}
    photon = row.get("touchPhoton", {}) or {}
    photon_summary = photon.get("summary", {}) or {}
    photon_latency = photon_summary.get("latencyMs") or {}
    lines.append(
        "| {label} | {move_ok} | {batch} | {move_events}/{move_target} | {move_acks} | {down} | {up} | {photon_ok} | {samples} | {detected} | {p50} | {p95} | {maxv} |".format(
            label=row.get("label"),
            move_ok="PASS" if move.get("ok") else ("SKIP" if not move.get("test") else "FAIL"),
            batch=ms(move.get("batchSize")),
            move_events=ms(move.get("injectedMoveEvents")),
            move_acks=ms(move.get("touchMoveAckCount")),
            move_target=ms(move.get("configuredMoves")),
            down="PASS" if (move.get("touchStartAck") or {}).get("ok") else ("SKIP" if not move.get("test") else "FAIL"),
            up="PASS" if (move.get("touchEndAck") or {}).get("ok") else ("SKIP" if not move.get("test") else "FAIL"),
            photon_ok="PASS" if photon.get("ok") else ("SKIP" if not photon.get("test") else "FAIL"),
            samples=ms(photon_summary.get("sampleCount")),
            detected=ms(photon_summary.get("detectedCount")),
            p50=ms(photon_latency.get("p50")),
            p95=ms(photon_latency.get("p95")),
            maxv=ms(photon_latency.get("max")),
        )
    )
lines.append("")
lines.append("## Marker Draw Sync")
lines.append("")
lines.append("| Profile | Draw Sync | Mode | Urgent | Samples | Latest Gen | Draw Gen | Draw p50 | Draw p95 | Draw max | Boost Req | Burst Frames |")
lines.append("| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for row in rows:
    marker = row.get("markerDrawSync", {}) or ((row.get("touchPhoton", {}) or {}).get("markerDrawSync") or {})
    latest = marker.get("latest") or {}
    draw_latency = marker.get("drawLatencyMs") or {}
    sample_count = marker.get("sampleCount") or 0
    draw_sync = "yes" if marker.get("drawSync") else ("none" if not sample_count else "no")
    lines.append(
        "| {label} | {draw_sync} | {mode} | {urgent} | {samples} | {generation} | {draw_generation} | {p50} | {p95} | {maxv} | {boost_requests} | {burst_frames} |".format(
            label=row.get("label"),
            draw_sync=draw_sync,
            mode=marker.get("mode") or latest.get("mode") or "",
            urgent=latest.get("drawUrgentBoost") or "",
            samples=ms(sample_count),
            generation=ms(latest.get("generation")),
            draw_generation=ms(latest.get("lastDrawGeneration")),
            p50=ms(draw_latency.get("p50")),
            p95=ms(draw_latency.get("p95")),
            maxv=ms(draw_latency.get("max")),
            boost_requests=ms(marker.get("drawBoostRequests", latest.get("drawBoostRequests"))),
            burst_frames=ms(marker.get("drawBoostBurstFrames", latest.get("drawBoostBurstFrames"))),
        )
    )
lines.append("")
lines.append("## Quality Gates")
lines.append("")
lines.append("| Profile | Gate | Value | Requirement | Result |")
lines.append("| --- | --- | ---: | --- | --- |")
for row in rows:
    gates = ((row.get("quality") or {}).get("gates") or [])
    if not gates:
        lines.append(f"| {row.get('label')} | none |  |  | SKIP |")
        continue
    for gate in gates:
        unit = gate.get("unit") or ""
        value = gate.get("value")
        threshold = gate.get("threshold")
        requirement = f"{gate.get('op')} {threshold}{unit}"
        lines.append(
            "| {label} | {name} | {value} | {requirement} | {result} |".format(
                label=row.get("label"),
                name=gate.get("name"),
                value=ms(value),
                requirement=requirement,
                result="PASS" if gate.get("ok") else "FAIL",
            )
        )
lines.append("")
lines.append("Latency values are browser-side milliseconds. DataChannel ack latency measures command round trip; touch-to-photon measures input send to marker pixels appearing in decoded video frames when enabled.")
lines.append("")
lines.append("HTTP `/api/input` is intentionally absent; control is tested through the `smartisax-input` RTCDataChannel.")
summary_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
if os.environ.get("FAIL_ON_SMOKE_FAILURE") == "1" and any(not row.get("ok") for row in rows):
    raise SystemExit(1)
PY

echo "Summary JSON: $summary_json"
echo "Summary Markdown: $summary_md"
