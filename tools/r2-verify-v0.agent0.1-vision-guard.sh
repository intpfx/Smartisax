#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.agent0.1-vision-guard"
export EXPECTED_VERSION_CODE="52"
export EXPECTED_VERSION_NAME="0.7.1"
export EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS="1"
export EXPECTED_PORTAL_VARIANT_MARKER="v0.agent0.1-vision-guard"
export EXPECTED_SOFTWARE_BITMAP_FRAME_PUMP="0"
export EXPECTED_BITMAP_COPY_FRAME_PUMP="1"
export EXPECTED_WEBRTC_SESSION_CONTROL="1"
export EXPECTED_WEBRTC_INPUT_CHANNEL="1"
export EXPECTED_WEBRTC_TOUCH_OVERLAY="1"
export EXPECTED_WEBRTC_QUALITY_TUNE="1"
export EXPECTED_WEBRTC_QUALITY_REASON_MARKER="portal6g_rvfc_media_tail"
export EXPECTED_WEBRTC_BITRATE_TUNE="1"
export EXPECTED_WEBRTC_DEFAULT_UI="1"
export EXPECTED_WEBRTC_RUNTIME_TUNING="1"
export EXPECTED_WEBRTC_RUNTIME_REASON_MARKER="portal6g_rvfc_media_tail"
export EXPECTED_WEBRTC_RUNTIME_MAX_FPS="90"
export EXPECTED_WEBRTC_CAPTURE_PROBE="1"
export EXPECTED_MANAGE_MEDIA_PROJECTION="1"
export EXPECTED_PROJECTION_PERMISSION_POLICY="1"
export EXPECTED_PROJECTION_BINDER_TRANSACT="1"
export EXPECTED_WEBRTC_FRAME_CONTINUITY_REPAIR="1"
export EXPECTED_WEBRTC_FRAME_TIMESTAMP_RETAIN="1"
export EXPECTED_WEBRTC_TOUCH_PHOTON_MARKER="1"
export EXPECTED_WEBRTC_MOVE_STREAM_INPUT="1"
export EXPECTED_WEBRTC_LATENCY_FOLLOW_RATE="1"
export EXPECTED_WEBRTC_DUAL_MOVE_CHANNEL="1"
export EXPECTED_WEBRTC_LATEST_FRAME_QUEUE="1"
export EXPECTED_WEBRTC_INPUT_FRAME_BOOST="1"
export EXPECTED_WEBRTC_DUAL_PHASE_INPUT_BOOST="1"
export EXPECTED_WEBRTC_MARKER_BURST_BOOST="1"
export EXPECTED_WEBRTC_MARKER_BURST_RESCHEDULE="1"
export EXPECTED_WEBRTC_PRESENTATION_CADENCE="1"
export EXPECTED_WEBRTC_QUIET_PRESENTATION="1"
export EXPECTED_WEBRTC_PRESENTER_MODE="1"
export EXPECTED_WEBRTC_PRESENTATION_TRANSPORT_PACING="1"
export EXPECTED_WEBRTC_VIDEO_PRIMARY_ROI_PROBE="1"
export EXPECTED_WEBRTC_MARKER_DRAW_SYNC="1"
export EXPECTED_WEBRTC_DRAW_URGENT_BOOST="1"
export EXPECTED_WEBRTC_BOOST_TOKEN_RETAIN="1"
export EXPECTED_WEBRTC_EVENT_TIME_INPUT="1"
export EXPECTED_WEBRTC_INPUT_PRIORITY_FRAME="1"
export EXPECTED_WEBRTC_VISIBLE_SCREENBOX="1"
export EXPECTED_WEBRTC_DISPLAY_WAKE_GUARD="1"
export EXPECTED_WEBRTC_ENCODER_TRANSPORT_BURST="1"
export EXPECTED_WEBRTC_ENCODER_TRANSPORT_REASON_MARKER="portal6g_rvfc_media_tail"
export EXPECTED_WEBRTC_PRESENTATION_TAIL_CADENCE="1"
export EXPECTED_WEBRTC_MEDIA_CALLBACK_TAIL_REPAIR="1"
export EXPECTED_SERVICES_JAR_SHA256="3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909"
export OFFLINE_RESULT_NAME="PASS_OFFLINE_IMAGE_V0AGENT01_VISION_GUARD"
export READ_ONLY_RESULT_NAME="PASS_READ_ONLY_V0AGENT01_VISION_GUARD"

latest_offline_report() {
  find "${ROOT_DIR}/hard-rom/inspect/${VARIANT}" -maxdepth 1 -type f -name "verify-${VARIANT}-offline-image-*.txt" -exec stat -f '%m %N' {} \; 2>/dev/null \
    | sort -rn \
    | sed -n '1s/^[0-9][0-9]* //p'
}

if [ "${1:-}" != "--offline-image" ]; then
  "${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh" "$@"
  exit $?
fi

"${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh" "$@"

report="$(latest_offline_report)"
[ -n "$report" ] || {
  echo "error: missing ${VARIANT} offline report after base verifier" >&2
  exit 1
}

{
  echo
  echo "## agent0.1 extra offline checks"
  decode_dir="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify/smartisax-apk-decoded"
  [ -d "$decode_dir" ] || {
    echo "error: missing decoded Smartisax APK: ${decode_dir}" >&2
    exit 1
  }
  grep -R -q 'SmartisaxAgentRuntime' "$decode_dir" || { echo "error: Agent runtime missing from dex" >&2; exit 1; }
  grep -R -q 'SmartisaxAgentProviders' "$decode_dir" || { echo "error: Agent providers missing from dex" >&2; exit 1; }
  grep -R -q 'SmartisaxScreenCapture' "$decode_dir" || { echo "error: shared screen capture helper missing from dex" >&2; exit 1; }
  grep -R -q 'mimo-v2.5' "$decode_dir" || { echo "error: MiMo model marker missing" >&2; exit 1; }
  grep -R -q 'deepseek-v4-flash' "$decode_dir" || { echo "error: DeepSeek model marker missing" >&2; exit 1; }
  grep -R -q 'https://api.xiaomimimo.com/v1/chat/completions' "$decode_dir" || { echo "error: MiMo API marker missing" >&2; exit 1; }
  grep -R -q 'https://api.deepseek.com' "$decode_dir" || { echo "error: DeepSeek API marker missing" >&2; exit 1; }
  grep -R -q '/api/agent/status' "$decode_dir" || { echo "error: read-only agent status route missing" >&2; exit 1; }
  grep -R -q 'v0.agent0.1-vision-guard' "$decode_dir" || { echo "error: agent0.1 variant marker missing" >&2; exit 1; }
  grep -R -q 'postActionCheck' "$decode_dir" || { echo "error: post-action check marker missing" >&2; exit 1; }
  grep -R -q 'coordinate_edge_guard' "$decode_dir" || { echo "error: coordinate guard marker missing" >&2; exit 1; }
  grep -R -q 'finish_requires_verified_screen_change' "$decode_dir" || { echo "error: finish gate marker missing" >&2; exit 1; }
  grep -R -q 'repeated_tap_no_screen_change' "$decode_dir" || { echo "error: repeated tap guard marker missing" >&2; exit 1; }
  grep -q 'data-agent-action="start"' "${decode_dir}/assets/shell/index.html" || { echo "error: Shell Agent start UI missing" >&2; exit 1; }
  grep -q 'id="agentProvider"' "${decode_dir}/assets/shell/index.html" || { echo "error: Shell Agent provider UI missing" >&2; exit 1; }
  grep -q 'post-check:' "${decode_dir}/assets/shell/shell.js" || { echo "error: Shell Agent post-check transcript missing" >&2; exit 1; }
  if grep -R -q '/api/input' "$decode_dir"; then
    echo "error: forbidden HTTP input route regressed" >&2
    exit 1
  fi
  "${ROOT_DIR}/tools/r2-agent0-offline-tests.py"
  echo "agent01_extra_offline_checks=ok"
} 2>&1 | tee -a "$report"
