#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERIAL="${SERIAL:-bb12d264}"
VARIANT="${VARIANT:-v0.portal5j.2-projection-binder-transact}"
URL="${URL:-}"
PAIRING_CODE="${PAIRING_CODE:-}"
TOKEN="${TOKEN:-}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-projection-texture-smoke-live}"
OBSERVE_MS="${OBSERVE_MS:-20000}"
TIMEOUT_MS="${TIMEOUT_MS:-100000}"
PROFILES="${PROFILES:-1080p30-texture 1080p60-texture}"
TIMEOUT="${TIMEOUT:-10}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-portal5j2-projection-texture-smoke.sh --url http://<r2-ip>:37601 --code <pairing-code>
  tools/r2-portal5j2-projection-texture-smoke.sh --url http://<r2-ip>:37601 --token <bearer-token>

Runs the v0.portal5j.2 projection-texture WebRTC smoke:
  - pairs with the LAN Portal using redacted pair evidence
  - verifies /api/webrtc/capture/probe is still createProjection=ok
  - applies 1080/30 and 1080/60 projection-texture runtime configs
  - runs Chrome native WebRTC H.264 playback plus smartisax-input gestures
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
{"config":{"frameWidthPortrait":1080,"frameWidthLandscape":1080,"fps":60,"minBitrateBps":8000000,"targetBitrateBps":12000000,"maxBitrateBps":12000000,"captureBackend":"projection-texture"}}
JSON
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
import sys
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probe = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
limits = config.get("limits", {})
if limits.get("maxFrameWidth") != 1080:
    raise SystemExit(f"maxFrameWidth={limits.get('maxFrameWidth')!r}, expected 1080")
if limits.get("maxFps") != 60:
    raise SystemExit(f"maxFps={limits.get('maxFps')!r}, expected 60")
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
  set +e
  node "${ROOT_DIR}/tools/r2-portal5a-chrome-webrtc-smoke.mjs" \
    --url "$URL" \
    --token "$TOKEN" \
    --variant "$chrome_variant" \
    --out-dir "$profile_dir" \
    --prefer-codec H264 \
    --input-gesture-test \
    --observe-ms "$OBSERVE_MS" \
    --timeout-ms "$TIMEOUT_MS" \
    > "$chrome_output"
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
input_acks = chrome.get("inputChannelAcks") or []
tap_ack = next((ack for ack in input_acks if isinstance(ack, dict) and ack.get("type") == "tap"), None)
swipe_ack = next((ack for ack in input_acks if isinstance(ack, dict) and ack.get("type") == "swipe"), None)
inbound = chrome.get("stats", {}).get("inboundRtp") or []
summary = {
    "profile": profile,
    "label": label,
    "chromeExit": int(chrome_exit),
    "ok": bool(chrome.get("ok")),
    "connectionState": chrome.get("connectionState"),
    "iceConnectionState": chrome.get("iceConnectionState"),
    "selectedCodec": chrome.get("selectedCodec"),
    "video": {
        "width": chrome.get("videoWidth"),
        "height": chrome.get("videoHeight"),
        "framesDecoded": chrome.get("framesDecoded"),
        "frameCallbacks": chrome.get("frameCallbacks"),
        "bytesReceived": chrome.get("bytesReceived"),
        "fpsEstimated": fps_est,
        "bitrateEstimatedBps": bitrate_est,
        "packetLossTotal": sum((item.get("packetsLost") or 0) for item in inbound),
        "packetLossDelta": loss_delta,
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
        "inputGestureOk": chrome.get("inputGestureOk"),
        "tapAck": tap_ack,
        "swipeAck": swipe_ack,
        "ackCount": len(input_acks),
    },
    "latency": {
        "answerElapsedMs": device_answer.get("elapsedMs"),
        "firstFrame": bool(chrome.get("firstFrame")),
        "elapsedMs": chrome.get("elapsedMs"),
        "note": "direct-lan browser-side one-way latency not measured in this smoke",
    },
    "quality": {
        "requested": label,
        "displayedResolution": f"{chrome.get('videoWidth')}x{chrome.get('videoHeight')}",
        "framePumpResolution": f"{frame_pump.get('width')}x{frame_pump.get('height')}",
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
python3 - "$summary_jsonl" "$summary_json" "$summary_md" <<'PY'
import json
import sys
from pathlib import Path

jsonl, summary_json, summary_md = map(Path, sys.argv[1:4])
rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line.strip()]
summary_json.write_text(json.dumps({"profiles": rows}, ensure_ascii=False, indent=2), encoding="utf-8")

lines = ["# v0.portal5j.2 Projection Texture WebRTC Smoke", ""]
lines.append("| Profile | OK | Capture | Frame Pump | Captured | Browser Video | Decoded | Est FPS | Est Bitrate | Loss Delta | PSS After | Input | Answer |")
lines.append("| --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |")
for row in rows:
    video = row.get("video", {})
    answer = row.get("deviceAnswer", {})
    fp = answer.get("framePump", {}) or {}
    sfp = row.get("sessionFramePump", {}) or {}
    mem = row.get("memoryKb", {})
    data = row.get("dataChannel", {})
    lines.append(
        "| {label} | {ok} | {capture} | {fpw}x{fph}@{fps} | {captured} | {vw}x{vh} | {decoded} | {efps} | {br} | {loss} | {pss} | {input_ok} | {ans} |".format(
            label=row.get("label"),
            ok="PASS" if row.get("ok") else "FAIL",
            capture=answer.get("captureBackend") or fp.get("backend"),
            fpw=fp.get("width"),
            fph=fp.get("height"),
            fps=fp.get("fps"),
            captured=sfp.get("capturedFrames") or fp.get("capturedFrames"),
            vw=video.get("width"),
            vh=video.get("height"),
            decoded=video.get("framesDecoded"),
            efps=video.get("fpsEstimated"),
            br=video.get("bitrateEstimatedBps"),
            loss=video.get("packetLossDelta"),
            pss=mem.get("afterTotalPss"),
            input_ok="PASS" if data.get("inputGestureOk") else "FAIL",
            ans=answer.get("elapsedMs"),
        )
    )
lines.append("")
lines.append("HTTP `/api/input` is intentionally absent; control is tested through the `smartisax-input` RTCDataChannel.")
summary_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "Summary JSON: $summary_json"
echo "Summary Markdown: $summary_md"
