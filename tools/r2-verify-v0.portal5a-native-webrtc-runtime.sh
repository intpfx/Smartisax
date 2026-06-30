#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
E2FSCK="${E2FSCK:-/opt/homebrew/opt/e2fsprogs/sbin/e2fsck}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
AVBTOOL="${AVBTOOL:-${ROOT_DIR}/hard-rom/tools/avbtool.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
APKTOOL_JAR="${APKTOOL_JAR:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
JAVA="${JAVA:-/opt/homebrew/opt/openjdk/bin/java}"
AAPT="${AAPT:-${ROOT_DIR}/third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
SYSTEM_B_EXTENT="${SYSTEM_B_EXTENT:-system_b=8306688:6217336}"

VARIANT="${VARIANT:-v0.portal5a-native-webrtc-runtime}"
EXPECTED_VERSION_CODE="${EXPECTED_VERSION_CODE:-17}"
EXPECTED_VERSION_NAME="${EXPECTED_VERSION_NAME:-0.6.0}"
EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS="${EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS:-0}"
EXPECTED_PORTAL_VARIANT_MARKER="${EXPECTED_PORTAL_VARIANT_MARKER:-}"
EXPECTED_SOFTWARE_BITMAP_FRAME_PUMP="${EXPECTED_SOFTWARE_BITMAP_FRAME_PUMP:-0}"
EXPECTED_BITMAP_COPY_FRAME_PUMP="${EXPECTED_BITMAP_COPY_FRAME_PUMP:-0}"
EXPECTED_WEBRTC_SESSION_CONTROL="${EXPECTED_WEBRTC_SESSION_CONTROL:-0}"
EXPECTED_WEBRTC_INPUT_CHANNEL="${EXPECTED_WEBRTC_INPUT_CHANNEL:-0}"
EXPECTED_WEBRTC_TOUCH_OVERLAY="${EXPECTED_WEBRTC_TOUCH_OVERLAY:-0}"
EXPECTED_WEBRTC_QUALITY_TUNE="${EXPECTED_WEBRTC_QUALITY_TUNE:-0}"
EXPECTED_WEBRTC_QUALITY_REASON_MARKER="${EXPECTED_WEBRTC_QUALITY_REASON_MARKER:-portal5g_maps_touch_overlay_to_display_coordinates}"
EXPECTED_WEBRTC_BITRATE_TUNE="${EXPECTED_WEBRTC_BITRATE_TUNE:-0}"
EXPECTED_WEBRTC_DEFAULT_UI="${EXPECTED_WEBRTC_DEFAULT_UI:-0}"
EXPECTED_WEBRTC_RUNTIME_TUNING="${EXPECTED_WEBRTC_RUNTIME_TUNING:-0}"
EXPECTED_WEBRTC_RUNTIME_REASON_MARKER="${EXPECTED_WEBRTC_RUNTIME_REASON_MARKER:-portal5i_webrtc_runtime_tuning_1080p_30fps}"
EXPECTED_WEBRTC_RUNTIME_MAX_FPS="${EXPECTED_WEBRTC_RUNTIME_MAX_FPS:-30}"
EXPECTED_WEBRTC_CAPTURE_PROBE="${EXPECTED_WEBRTC_CAPTURE_PROBE:-0}"
EXPECTED_MANAGE_MEDIA_PROJECTION="${EXPECTED_MANAGE_MEDIA_PROJECTION:-0}"
EXPECTED_PROJECTION_PERMISSION_POLICY="${EXPECTED_PROJECTION_PERMISSION_POLICY:-0}"
EXPECTED_PROJECTION_BINDER_TRANSACT="${EXPECTED_PROJECTION_BINDER_TRANSACT:-0}"
EXPECTED_WEBRTC_FRAME_CONTINUITY_REPAIR="${EXPECTED_WEBRTC_FRAME_CONTINUITY_REPAIR:-0}"
EXPECTED_WEBRTC_FRAME_TIMESTAMP_RETAIN="${EXPECTED_WEBRTC_FRAME_TIMESTAMP_RETAIN:-0}"
EXPECTED_WEBRTC_TOUCH_PHOTON_MARKER="${EXPECTED_WEBRTC_TOUCH_PHOTON_MARKER:-0}"
EXPECTED_WEBRTC_MOVE_STREAM_INPUT="${EXPECTED_WEBRTC_MOVE_STREAM_INPUT:-0}"
EXPECTED_WEBRTC_LATENCY_FOLLOW_RATE="${EXPECTED_WEBRTC_LATENCY_FOLLOW_RATE:-0}"
EXPECTED_WEBRTC_DUAL_MOVE_CHANNEL="${EXPECTED_WEBRTC_DUAL_MOVE_CHANNEL:-0}"
EXPECTED_WEBRTC_LATEST_FRAME_QUEUE="${EXPECTED_WEBRTC_LATEST_FRAME_QUEUE:-0}"
EXPECTED_WEBRTC_INPUT_FRAME_BOOST="${EXPECTED_WEBRTC_INPUT_FRAME_BOOST:-0}"
EXPECTED_WEBRTC_DUAL_PHASE_INPUT_BOOST="${EXPECTED_WEBRTC_DUAL_PHASE_INPUT_BOOST:-0}"
EXPECTED_WEBRTC_BOOST_TOKEN_RETAIN="${EXPECTED_WEBRTC_BOOST_TOKEN_RETAIN:-0}"
EXPECTED_WEBRTC_EVENT_TIME_INPUT="${EXPECTED_WEBRTC_EVENT_TIME_INPUT:-0}"
EXPECTED_WEBRTC_INPUT_PRIORITY_FRAME="${EXPECTED_WEBRTC_INPUT_PRIORITY_FRAME:-0}"
EXPECTED_WEBRTC_MARKER_BURST_BOOST="${EXPECTED_WEBRTC_MARKER_BURST_BOOST:-0}"
EXPECTED_WEBRTC_MARKER_BURST_RESCHEDULE="${EXPECTED_WEBRTC_MARKER_BURST_RESCHEDULE:-0}"
EXPECTED_WEBRTC_PRESENTATION_CADENCE="${EXPECTED_WEBRTC_PRESENTATION_CADENCE:-0}"
EXPECTED_WEBRTC_QUIET_PRESENTATION="${EXPECTED_WEBRTC_QUIET_PRESENTATION:-0}"
EXPECTED_WEBRTC_PRESENTER_MODE="${EXPECTED_WEBRTC_PRESENTER_MODE:-0}"
EXPECTED_WEBRTC_PRESENTATION_TRANSPORT_PACING="${EXPECTED_WEBRTC_PRESENTATION_TRANSPORT_PACING:-0}"
EXPECTED_WEBRTC_VIDEO_PRIMARY_ROI_PROBE="${EXPECTED_WEBRTC_VIDEO_PRIMARY_ROI_PROBE:-0}"
EXPECTED_WEBRTC_MARKER_DRAW_SYNC="${EXPECTED_WEBRTC_MARKER_DRAW_SYNC:-0}"
EXPECTED_WEBRTC_VISIBLE_SCREENBOX="${EXPECTED_WEBRTC_VISIBLE_SCREENBOX:-0}"
EXPECTED_WEBRTC_DISPLAY_WAKE_GUARD="${EXPECTED_WEBRTC_DISPLAY_WAKE_GUARD:-0}"
EXPECTED_WEBRTC_ENCODER_TRANSPORT_BURST="${EXPECTED_WEBRTC_ENCODER_TRANSPORT_BURST:-0}"
EXPECTED_WEBRTC_ENCODER_TRANSPORT_REASON_MARKER="${EXPECTED_WEBRTC_ENCODER_TRANSPORT_REASON_MARKER:-portal6e_encoder_transport_burst}"
EXPECTED_WEBRTC_PRESENTATION_TAIL_CADENCE="${EXPECTED_WEBRTC_PRESENTATION_TAIL_CADENCE:-0}"
EXPECTED_WEBRTC_MEDIA_CALLBACK_TAIL_REPAIR="${EXPECTED_WEBRTC_MEDIA_CALLBACK_TAIL_REPAIR:-0}"
EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a}"
OFFLINE_RESULT_NAME="${OFFLINE_RESULT_NAME:-PASS_OFFLINE_IMAGE_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME}"
READ_ONLY_RESULT_NAME="${READ_ONLY_RESULT_NAME:-PASS_READ_ONLY_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/${VARIANT}"
WORK_DIR="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify"
SUPER_MANIFEST="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.SHA256SUMS.txt"
SYSTEM_MANIFEST="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.SHA256SUMS.txt"
SUPER_SPARSE="${ROOT_DIR}/hard-rom/build/super-otatrust-${VARIANT}.sparse.img"
SYSTEM_B_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"

SYSTEM_B_PARTITION_SIZE=3183276032
SYSTEM_B_EXT4_SIZE=3132964864
SERVICES_JAR_PATH="/system/framework/services.jar"
NEW_SMARTISAX_APK_PATH="/system/priv-app/SmartisaxShell/SmartisaxShell.apk"
PRIVAPP_XML_PATH="/system/etc/permissions/privapp-permissions-com.smartisax.browser.xml"
WEBRTC_ARM64_SO_PATH="/system/priv-app/SmartisaxShell/lib/arm64/libjingle_peerconnection_so.so"
WEBRTC_ARM_SO_PATH="/system/priv-app/SmartisaxShell/lib/arm/libjingle_peerconnection_so.so"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh --offline-image
  tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh --read-only

--offline-image verifies the built sparse/system_b without touching a device.
--read-only verifies a flashed device without changing /data or starting Portal.
USAGE
}

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
need_file() { [ -f "$1" ] || die "missing file: $1"; }
need_executable() { [ -x "$1" ] || die "missing executable: $1"; }
sha256_one() { shasum -a 256 "$1" | awk '{print $1}'; }

manifest_value() {
  local manifest="$1" key="$2"
  awk -F= -v k="$key" '$1 == k {print substr($0, length(k) + 2); exit}' "$manifest"
}

manifest_value_available() {
  local key="$1" value=""
  if [ -f "$SYSTEM_MANIFEST" ]; then
    value="$(manifest_value "$SYSTEM_MANIFEST" "$key")"
  fi
  if [ -z "$value" ] && [ -f "$SUPER_MANIFEST" ]; then
    value="$(manifest_value "$SUPER_MANIFEST" "$key")"
  fi
  printf '%s\n' "$value"
}

check_manifest_hash() {
  local manifest="$1" label="$2" path="$3" key="$4" expected actual
  need_file "$manifest"
  expected="$(manifest_value "$manifest" "$key")"
  [ -n "$expected" ] || die "manifest missing ${key}: ${manifest}"
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

debugfs_path_exists() {
  local image="$1" path="$2" output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
}

debugfs_dump() {
  local image="$1" src="$2" dst="$3"
  rm -f "$dst"
  "$DEBUGFS" -R "dump ${src} ${dst}" "$image" >/dev/null 2>&1
  need_file "$dst"
}

verify_avb_fec() {
  local image="$1" info="${WORK_DIR}/system-b-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$image" > "$info"
  grep -q "Image size:               ${SYSTEM_B_PARTITION_SIZE} bytes" "$info" || die "system_b AVB image size mismatch"
  grep -q "Original image size:      ${SYSTEM_B_EXT4_SIZE} bytes" "$info" || die "system_b AVB original image size mismatch"
  grep -q "FEC num roots:         2" "$info" || die "system_b lost FEC roots"
  grep -q "FEC offset:            [1-9]" "$info" || die "system_b missing FEC offset"
  echo "system_b_avb_fec=ok"
}

verify_apk_semantics() {
  local apk="$1" decode_dir="${WORK_DIR}/smartisax-apk-decoded"
  rm -rf "$decode_dir"
  "$AAPT" dump badging "$apk" > "${WORK_DIR}/smartisax-aapt-badging.txt"
  grep -q "package: name='com.smartisax.browser' versionCode='${EXPECTED_VERSION_CODE}' versionName='${EXPECTED_VERSION_NAME}'" "${WORK_DIR}/smartisax-aapt-badging.txt" \
    || die "Smartisax aapt identity mismatch"
  grep -q "native-code: 'arm64-v8a' 'armeabi-v7a'" "${WORK_DIR}/smartisax-aapt-badging.txt" \
    || die "Smartisax native-code ABI mismatch"
  unzip -t "$apk" >/dev/null
  unzip -l "$apk" > "${WORK_DIR}/smartisax-zip-list.txt"
  grep -q 'lib/arm64-v8a/libjingle_peerconnection_so.so' "${WORK_DIR}/smartisax-zip-list.txt" \
    || die "missing arm64 libjingle_peerconnection_so.so"
  grep -q 'lib/armeabi-v7a/libjingle_peerconnection_so.so' "${WORK_DIR}/smartisax-zip-list.txt" \
    || die "missing armeabi-v7a libjingle_peerconnection_so.so"
  PATH="$(dirname "$JAVA"):${PATH}" "$JAVA" -jar "$APKTOOL_JAR" d -f "$apk" -o "$decode_dir" >/dev/null
  grep -q 'android:extractNativeLibs="true"' "${decode_dir}/AndroidManifest.xml" \
    || die "Smartisax manifest missing extractNativeLibs=true"
  grep -R -q 'SmartisaxWebRtcRuntime' "${decode_dir}/smali" || die "SmartisaxWebRtcRuntime missing from dex"
  grep -R -q 'PeerConnectionFactory' "${decode_dir}/smali" || die "PeerConnectionFactory missing from dex"
  grep -R -q 'DefaultVideoEncoderFactory' "${decode_dir}/smali" || die "DefaultVideoEncoderFactory missing from dex"
  grep -R -q 'jingle_peerconnection_so' "${decode_dir}/smali" || die "libwebrtc native library marker missing"
  grep -R -q 'native-libwebrtc-dtls-srtp-screen' "${decode_dir}/smali" || die "native WebRTC status marker missing"
  grep -R -q 'native-libwebrtc-answer' "${decode_dir}/smali" || die "native WebRTC answer marker missing"
  grep -R -q 'host-candidates-no-stun-direct-lan' "${decode_dir}/smali" || die "native ICE route marker missing"
  if [ -n "$EXPECTED_PORTAL_VARIANT_MARKER" ]; then
    grep -R -q "$EXPECTED_PORTAL_VARIANT_MARKER" "${decode_dir}/smali" || die "expected portal variant marker missing"
  fi
  if [ "$EXPECTED_SOFTWARE_BITMAP_FRAME_PUMP" = "1" ]; then
    grep -R -q 'readableArgb8888' "${decode_dir}/smali" || die "software bitmap conversion helper missing"
    grep -R -q 'Landroid/graphics/Canvas;' "${decode_dir}/smali" || die "software bitmap Canvas conversion missing"
  fi
  if [ "$EXPECTED_BITMAP_COPY_FRAME_PUMP" = "1" ]; then
    local runtime_smali="${decode_dir}/smali/com/smartisax/browser/SmartisaxWebRtcRuntime.smali"
    grep -F -q 'copy(Landroid/graphics/Bitmap$Config;Z)Landroid/graphics/Bitmap;' "$runtime_smali" \
      || die "Bitmap.copy ARGB_8888 frame conversion missing"
    if grep -F -q 'Landroid/graphics/Canvas;' "$runtime_smali"; then
      die "SmartisaxWebRtcRuntime still references Canvas"
    fi
  fi
  grep -R -q 'JavaI420Buffer' "${decode_dir}/smali" || die "I420 frame pump missing"
  grep -R -q 'onFrameCaptured' "${decode_dir}/smali" || die "capturer observer frame feed missing"
  grep -R -q '/api/webrtc/offer' "${decode_dir}/smali" || die "portal /api/webrtc/offer path missing"
  grep -R -q 'Content-Security-Policy' "${decode_dir}/smali" || die "portal CSP header missing"
  grep -R -q 'privileged-surfacecontrol-png' "${decode_dir}/smali" || die "screen backend marker missing"
  grep -R -q 'privileged-inputmanager' "${decode_dir}/smali" || die "input backend marker missing"
  if [ "$EXPECTED_WEBRTC_DEFAULT_UI" = "1" ]; then
    grep -q 'data-portal-mode="webrtc-default"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing default WebRTC mode marker"
    grep -q 'ensureWebRtc().catch' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset does not auto-start native WebRTC after status"
    grep -q 'id="reconnectWebRtc"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing WebRTC reconnect control"
    if grep -E -q 'id="(startLive|startMp4|stopMp4|startH264|stopH264|startPng|stopPng|startWebRtc|caps|probeH264|probeRtp)"' "${decode_dir}/assets/portal/index.html"; then
      die "Portal asset still exposes legacy transport mode buttons"
    fi
    if grep -E -q '<video id="mp4Video"[^>]*controls' "${decode_dir}/assets/portal/index.html"; then
      die "Portal video element still exposes browser controls"
    fi
  else
    grep -q 'Native WebRTC' "${decode_dir}/assets/portal/index.html" || die "Portal asset missing Native WebRTC button"
  fi
  grep -q 'setRemoteDescription' "${decode_dir}/assets/portal/index.html" || die "Portal asset missing setRemoteDescription path"
  grep -q 'srcObject' "${decode_dir}/assets/portal/index.html" || die "Portal asset missing MediaStream video path"
  grep -q 'waitIceComplete' "${decode_dir}/assets/portal/index.html" || die "Portal asset missing ICE completion wait"
  if [ "$EXPECTED_WEBRTC_SESSION_CONTROL" = "1" ]; then
    grep -R -q '/api/webrtc/sessions' "${decode_dir}/smali" || die "WebRTC sessions API route missing"
    grep -R -q '/api/webrtc/close' "${decode_dir}/smali" || die "WebRTC close API route missing"
    grep -R -q 'native-libwebrtc-close' "${decode_dir}/smali" || die "WebRTC close response marker missing"
    grep -R -q 'activeSessions' "${decode_dir}/smali" || die "WebRTC activeSessions status marker missing"
    grep -R -q 'requestedSessionId' "${decode_dir}/smali" || die "WebRTC requestedSessionId close marker missing"
    grep -R -q 'webrtcSessions' "${decode_dir}/smali" || die "Portal status missing webrtcSessions endpoint marker"
    grep -R -q 'webrtcClose' "${decode_dir}/smali" || die "Portal status missing webrtcClose endpoint marker"
    grep -R -E -q 'H264-preferred-browser|H264,AV1,VP9,H265' "${decode_dir}/smali" \
      || die "H264 preferred status marker missing"
    grep -R -q 'selectedCodec' "${decode_dir}/smali" || die "selectedCodec answer marker missing"
    grep -E -q 'preferVideoCodec\(transceiver, "H264"\)|preferVideoCodecs\(transceiver, modernCodecPreference\)' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing default H264 codec preference"
    grep -q 'webRtcSessionId = json.sessionId || "";' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset does not retain native WebRTC sessionId"
    grep -q '/api/webrtc/close' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing WebRTC close call"
    grep -q 'body: JSON.stringify({ sessionId })' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing sessionId close request body"
  fi
  if [ "$EXPECTED_WEBRTC_INPUT_CHANNEL" = "1" ]; then
    grep -R -q 'SmartisaxInputController' "$decode_dir" || die "SmartisaxInputController missing from APK"
    grep -R -q 'webrtc-datachannel-input' "$decode_dir" || die "DataChannel input marker missing"
    grep -R -q 'smartisax-input' "$decode_dir" || die "smartisax-input channel label missing"
    grep -R -q 'RTCDataChannel' "$decode_dir" || die "RTCDataChannel status marker missing"
    grep -R -q 'DataChannel' "${decode_dir}/smali" || die "WebRTC DataChannel binding missing"
    grep -q 'createDataChannel("smartisax-input"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing smartisax-input DataChannel creation"
    grep -E -q '(webRtcInputChannel|channel)\.send' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset does not send input over DataChannel"
    if grep -R -q '/api/input' "$decode_dir"; then
      die "HTTP /api/input residue remains in Smartisax APK"
    fi
  fi
  if [ "$EXPECTED_WEBRTC_TOUCH_OVERLAY" = "1" ]; then
    grep -q 'id="touchOverlay"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing transparent touch overlay"
    grep -q 'deviceDisplay.width' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing display-coordinate width mapping"
    grep -q 'deviceDisplay.height' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing display-coordinate height mapping"
    grep -q 'displayWidth' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing displayWidth in DataChannel payload"
    grep -q 'displayHeight' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing displayHeight in DataChannel payload"
  fi
  if [ "$EXPECTED_WEBRTC_QUALITY_TUNE" = "1" ]; then
    grep -R -q 'framePumpDefaults' "${decode_dir}/smali" || die "framePumpDefaults marker missing"
    grep -R -q 'low-latency-screencast' "${decode_dir}/smali" || die "low-latency frame pump marker missing"
    grep -R -q 'display' "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali \
      || die "Portal status display mapping marker missing"
    grep -q "$EXPECTED_WEBRTC_QUALITY_REASON_MARKER" "${decode_dir}/smali/com/smartisax/browser/DevicePortalService"*.smali \
      || die "expected quality/touch reason marker missing"
  fi
  if [ "$EXPECTED_WEBRTC_BITRATE_TUNE" = "1" ]; then
    local runtime_smali="${decode_dir}/smali/com/smartisax/browser/SmartisaxWebRtcRuntime"*.smali
    grep -R -E -q 'explicit-h264-bitrate|runtime-tuning' "${decode_dir}/smali" || die "H264 bitrate policy marker missing"
    grep -R -q 'targetVideoBitrateBps' "${decode_dir}/smali" || die "targetVideoBitrateBps status marker missing"
    grep -R -q 'minVideoBitrateBps' "${decode_dir}/smali" || die "minVideoBitrateBps status marker missing"
    grep -F -q 'setParameters(Lorg/webrtc/RtpParameters;)Z' $runtime_smali \
      || die "RtpSender.setParameters bitrate call missing"
    grep -F -q 'getParameters()Lorg/webrtc/RtpParameters;' $runtime_smali \
      || die "RtpSender.getParameters bitrate call missing"
  fi
  if [ "$EXPECTED_WEBRTC_RUNTIME_TUNING" = "1" ]; then
    grep -R -q '/api/webrtc/config' "${decode_dir}/smali" || die "WebRTC runtime config API route missing"
    grep -R -q 'native-libwebrtc-config' "${decode_dir}/smali" || die "native WebRTC config response marker missing"
    grep -R -q 'runtime-tuning' "${decode_dir}/smali" || die "runtime tuning bitrate policy marker missing"
    grep -R -q 'runtimeConfigLimits' "${decode_dir}/smali" || die "runtimeConfigLimits status marker missing"
    grep -R -q 'maxFrameWidth' "${decode_dir}/smali" || die "maxFrameWidth runtime limit marker missing"
    grep -R -q 'maxFps' "${decode_dir}/smali" || die "maxFps runtime limit marker missing"
    grep -R -q "$EXPECTED_WEBRTC_RUNTIME_REASON_MARKER" "${decode_dir}/smali" \
      || die "expected runtime tuning reason marker missing"
    grep -q 'id="tuneWidth"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing runtime width control"
    grep -q 'id="tuneFps"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing runtime fps control"
    grep -q "max=\"${EXPECTED_WEBRTC_RUNTIME_MAX_FPS}\"" "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing ${EXPECTED_WEBRTC_RUNTIME_MAX_FPS}fps runtime slider cap"
    grep -q 'id="maxTuning"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing 1080/30 preset control"
    grep -q '/api/webrtc/config' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing runtime config fetch/update path"
    grep -q 'maxTuningConfig' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing max tuning preset"
    grep -q 'frameWidthPortrait: 1080' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset max preset does not expose 1080 width"
    grep -q "fps: ${EXPECTED_WEBRTC_RUNTIME_MAX_FPS}" "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset max preset does not expose ${EXPECTED_WEBRTC_RUNTIME_MAX_FPS}fps"
  fi
  if [ "$EXPECTED_WEBRTC_CAPTURE_PROBE" = "1" ]; then
    grep -R -q '/api/webrtc/capture/probe' "${decode_dir}/smali" \
      || die "WebRTC capture probe API route missing"
    grep -R -q 'SmartisaxProjectionCapture' "${decode_dir}/smali" \
      || die "SmartisaxProjectionCapture missing from APK"
    grep -R -q 'MediaProjection VirtualDisplay' "${decode_dir}/smali" \
      || die "MediaProjection texture capture marker missing"
    grep -R -q 'SurfaceTextureHelper' "${decode_dir}/smali" \
      || die "SurfaceTextureHelper texture capture marker missing"
    grep -R -q 'projection-texture' "${decode_dir}/smali" \
      || die "projection-texture backend marker missing"
    grep -R -q 'projection-auto' "${decode_dir}/smali" \
      || die "projection-auto backend marker missing"
    grep -q '/api/webrtc/capture/probe' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing capture probe endpoint"
    grep -q 'captureBackend' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing captureBackend runtime config"
    grep -q "max=\"${EXPECTED_WEBRTC_RUNTIME_MAX_FPS}\"" "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset fps controls do not expose ${EXPECTED_WEBRTC_RUNTIME_MAX_FPS}fps"
    if [ "$EXPECTED_PROJECTION_BINDER_TRANSACT" = "1" ]; then
      local projection_smali="${decode_dir}/smali/com/smartisax/browser/SmartisaxProjectionCapture.smali"
      grep -q 'raw-binder-transact-media-projection' "$projection_smali" \
        || die "raw Binder MediaProjection route marker missing"
      grep -q 'android.media.projection.IMediaProjectionManager' "$projection_smali" \
        || die "MediaProjection manager descriptor missing"
      grep -F -q 'transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z' "$projection_smali" \
        || die "IBinder.transact call missing from projection capture"
      grep -q 'media_projection_transact_' "$projection_smali" \
        || die "raw Binder transact error marker missing"
      if grep -q 'IMediaProjectionManager$Stub' "$projection_smali"; then
        die "old IMediaProjectionManager Stub reflection residue remains"
      fi
      if grep -q 'media_projection_manager_asInterface_returned_null' "$projection_smali"; then
        die "old asInterface error marker remains"
      fi
    fi
  fi
  if [ "$EXPECTED_WEBRTC_FRAME_CONTINUITY_REPAIR" = "1" ]; then
    local runtime_smali="${decode_dir}/smali/com/smartisax/browser/SmartisaxWebRtcRuntime"*.smali
    grep -R -E -q 'surface-texture-helper-(force-frame-cadence|latest-frame-only)' "${decode_dir}/smali" \
      || die "frame continuity repair marker missing"
    grep -F -q 'forceFrame()V' $runtime_smali \
      || die "SurfaceTextureHelper.forceFrame cadence call missing"
    grep -R -q 'continuityFrameRequests' "${decode_dir}/smali" \
      || die "continuityFrameRequests diagnostic marker missing"
    grep -R -q 'continuityFrames' "${decode_dir}/smali" \
      || die "continuityFrames diagnostic marker missing"
    grep -R -q 'droppedFrames' "${decode_dir}/smali" \
      || die "droppedFrames diagnostic marker missing"
  fi
  if [ "$EXPECTED_WEBRTC_FRAME_TIMESTAMP_RETAIN" = "1" ]; then
    local runtime_smali="${decode_dir}/smali/com/smartisax/browser/SmartisaxWebRtcRuntime"*.smali
    grep -R -q 'fresh-texture-timestamps' "${decode_dir}/smali" \
      || die "fresh texture timestamp marker missing"
    grep -R -q 'timestampRewriteFrames' "${decode_dir}/smali" \
      || die "timestampRewriteFrames diagnostic marker missing"
    grep -R -q 'lastTimestampRewriteElapsedMs' "${decode_dir}/smali" \
      || die "lastTimestampRewriteElapsedMs diagnostic marker missing"
    grep -F -q 'retain()V' $runtime_smali \
      || die "texture buffer retain call missing"
    grep -F -q 'System;->nanoTime()J' $runtime_smali \
      || die "fresh System.nanoTime frame timestamp missing"
  fi
  if [ "$EXPECTED_WEBRTC_TOUCH_PHOTON_MARKER" = "1" ]; then
    grep -R -q 'SmartisaxTouchMarker' "${decode_dir}/smali" \
      || die "SmartisaxTouchMarker missing from APK"
    grep -R -q 'touch-photon-marker' "${decode_dir}/smali" \
      || die "touch-photon marker mode missing from smali"
    grep -R -q 'touchPhotonMarker' "${decode_dir}/smali" \
      || die "Portal status touchPhotonMarker field missing"
    grep -R -q 'displayWidth' "${decode_dir}/smali/com/smartisax/browser/SmartisaxTouchMarker"*.smali \
      || die "touch marker displayWidth metadata missing"
    grep -R -q 'marker' "${decode_dir}/smali/com/smartisax/browser/SmartisaxInputController"*.smali \
      || die "input marker ack field missing"
  fi
  if [ "$EXPECTED_WEBRTC_MOVE_STREAM_INPUT" = "1" ]; then
    grep -R -q 'inputMoveStream' "${decode_dir}/smali" \
      || die "Portal inputMoveStream status field missing"
    grep -R -q 'touchStart' "$decode_dir" || die "touchStart move-stream marker missing"
    grep -R -q 'touchMove' "$decode_dir" || die "touchMove move-stream marker missing"
    grep -R -q 'touchEnd' "$decode_dir" || die "touchEnd move-stream marker missing"
    grep -R -q 'down-move-up' "${decode_dir}/smali" \
      || die "down-move-up stream ack marker missing"
    grep -q 'getCoalescedEvents' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing coalesced pointer events"
    grep -Eq '(webRtcInputChannel|webRtcMoveChannel|channel)\.bufferedAmount' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing move-stream bufferedAmount backpressure"
  fi
  if [ "$EXPECTED_WEBRTC_LATENCY_FOLLOW_RATE" = "1" ]; then
    grep -R -q 'compact-move-acks+batched-move-stream' "${decode_dir}/smali" \
      || die "DataChannel ack jitter repair marker missing"
    grep -R -q 'touchStart-touchMoveBatch-touchEnd' "${decode_dir}/smali" \
      || die "batched move-stream status marker missing"
    grep -R -q 'pointCount' "${decode_dir}/smali/com/smartisax/browser/SmartisaxInputController"*.smali \
      || die "touchMoveBatch pointCount ack marker missing"
    grep -q 'touchMoveBatch' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing touchMoveBatch sender"
    grep -q 'maxMoveBatchPoints' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing move batch queue cap"
    grep -q 'requestAnimationFrame' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing frame-aligned move flush"
  fi
  if [ "$EXPECTED_WEBRTC_EVENT_TIME_INPUT" = "1" ]; then
    grep -R -q 'event-time-preserving-move-stream' "${decode_dir}/smali" \
      || die "event-time preserving move-stream status marker missing"
    grep -R -q 'client-event-elapsed-relative-uptime' "${decode_dir}/smali" \
      || die "client event-time relative uptime ack marker missing"
    grep -R -q 'lastMotionEventTimeUptimeMs' "${decode_dir}/smali" \
      || die "last MotionEvent eventTime diagnostic marker missing"
    grep -R -q 'clientEventElapsedMs' "${decode_dir}/smali/com/smartisax/browser/SmartisaxInputController"*.smali \
      || die "SmartisaxInputController missing clientEventElapsedMs parser"
    grep -q 'normalizedEventElapsedMs' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing pointer event-time normalization"
    grep -q 'event.timeStamp' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing browser pointer event timestamp sampling"
    grep -q 'clientEventElapsedMs' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing top-level clientEventElapsedMs payload"
    grep -q 'e: item.e' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing move-batch event elapsed payload"
    echo "smartisax_event_time_input=ok"
  fi
  if [ "$EXPECTED_WEBRTC_DUAL_MOVE_CHANNEL" = "1" ]; then
    grep -R -q 'smartisax-input-move' "$decode_dir" \
      || die "dual move DataChannel label missing"
    grep -R -q 'dual-datachannel' "${decode_dir}/smali" \
      || die "dual DataChannel ack jitter repair marker missing"
    grep -q 'maxRetransmits' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing low-retransmit move DataChannel"
    grep -q 'moveChannelBufferedLimit' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing move channel buffer budget"
    echo "smartisax_dual_move_channel=ok"
  fi
  if [ "$EXPECTED_WEBRTC_LATEST_FRAME_QUEUE" = "1" ]; then
    grep -R -q 'latest-frame-only' "${decode_dir}/smali" \
      || die "latest-frame-only frame queue marker missing"
    grep -R -q 'continuityFrameSkips' "${decode_dir}/smali" \
      || die "continuityFrameSkips diagnostic marker missing"
    grep -R -q 'maxPendingContinuityFrames' "${decode_dir}/smali" \
      || die "maxPendingContinuityFrames diagnostic marker missing"
    grep -R -q 'skip-forceFrame-when-captured-frame-is-fresh' "${decode_dir}/smali" \
      || die "fresh-frame forceFrame skip policy marker missing"
    echo "smartisax_latest_frame_queue=ok"
  fi
  if [ "$EXPECTED_WEBRTC_INPUT_FRAME_BOOST" = "1" ]; then
    grep -R -q 'input-frame-boost' "${decode_dir}/smali" \
      || die "input frame boost mode marker missing"
    grep -R -q 'inputFrameBoostRequests' "${decode_dir}/smali" \
      || die "inputFrameBoostRequests diagnostic marker missing"
    grep -R -q 'inputFrameBoostFrames' "${decode_dir}/smali" \
      || die "inputFrameBoostFrames diagnostic marker missing"
    grep -R -q 'requestInputFrameBoost' "${decode_dir}/smali" \
      || die "requestInputFrameBoost route missing"
    if ! grep -R -q 'touch-marker-drawn' "${decode_dir}/smali" \
        && ! grep -R -q 'touch-marker-visible-burst' "${decode_dir}/smali"; then
      die "touch marker drawn or visible burst boost trigger missing"
    fi
    if ! grep -R -q 'boost-after-input-marker' "${decode_dir}/smali" \
        && ! grep -R -q 'coalesce-pending-forceFrame-after-input-marker' "${decode_dir}/smali"; then
      die "input-marker boost queue policy missing"
    fi
    echo "smartisax_input_frame_boost=ok"
  fi
  if [ "$EXPECTED_WEBRTC_DUAL_PHASE_INPUT_BOOST" = "1" ]; then
    grep -R -q 'dual-phase-input-frame-boost' "${decode_dir}/smali" \
      || die "dual-phase input frame boost mode marker missing"
    grep -R -q 'touch-marker-injected' "${decode_dir}/smali" \
      || die "touch marker injected boost trigger missing"
    grep -R -q 'coalesce-pending-forceFrame-after-input-marker' "${decode_dir}/smali" \
      || die "dual-phase coalesced pending forceFrame marker missing"
    echo "smartisax_dual_phase_input_boost=ok"
  fi
  if [ "$EXPECTED_WEBRTC_MARKER_BURST_BOOST" = "1" ]; then
    grep -R -q 'marker-visible-burst-boost' "${decode_dir}/smali" \
      || die "marker visible burst boost mode marker missing"
    grep -R -q 'marker-burst-input-priority' "${decode_dir}/smali" \
      || die "marker burst input-priority queue policy missing"
    if ! grep -R -q 'touch-marker-visible-burst' "${decode_dir}/smali" \
        && ! grep -R -q 'touch-marker-drawn-burst' "${decode_dir}/smali"; then
      die "touch marker visible or draw-synced burst trigger missing"
    fi
    grep -R -q 'requestInputFrameBoostBurst' "${decode_dir}/smali" \
      || die "requestInputFrameBoostBurst route missing"
    grep -R -q 'inputFrameBoostBurstRequests' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstRequests diagnostic marker missing"
    grep -R -q 'inputFrameBoostBurstFrames' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstFrames diagnostic marker missing"
    grep -R -q 'inputFrameBoostBurstMaxFrames' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstMaxFrames diagnostic marker missing"
    echo "smartisax_marker_burst_boost=ok"
  fi
  if [ "$EXPECTED_WEBRTC_MARKER_BURST_RESCHEDULE" = "1" ]; then
    grep -R -q 'marker-burst-reschedule-until-accepted' "${decode_dir}/smali" \
      || die "marker burst reschedule-until-accepted mode marker missing"
    grep -R -q 'inputFrameBoostBurstRetries' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstRetries diagnostic marker missing"
    grep -R -q 'inputFrameBoostBurstPendingFrames' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstPendingFrames diagnostic marker missing"
    grep -R -q 'inputFrameBoostBurstActiveFrames' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstActiveFrames diagnostic marker missing"
    grep -R -q 'lastInputFrameBoostBurstRetryElapsedMs' "${decode_dir}/smali" \
      || die "lastInputFrameBoostBurstRetryElapsedMs diagnostic marker missing"
    echo "smartisax_marker_burst_reschedule=ok"
  fi
  if [ "$EXPECTED_WEBRTC_PRESENTATION_CADENCE" = "1" ]; then
    grep -R -q 'receiver-playout-delay-zero' "${decode_dir}/smali" \
      || die "receiver playout-delay-zero status marker missing"
    grep -q 'playoutDelayHint' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing RTCRtpReceiver playoutDelayHint path"
    grep -q 'receiverPlayoutDelayHint' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing receiverPlayoutDelayHint diagnostic marker"
    grep -q 'contentHint = "motion"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing motion contentHint path"
    grep -q 'receiverPresentationHints' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing receiverPresentationHints diagnostics"
    grep -q 'disableRemotePlayback' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing remote playback disable hint"
    echo "smartisax_presentation_cadence=ok"
  fi
  if [ "$EXPECTED_WEBRTC_QUIET_PRESENTATION" = "1" ]; then
    grep -R -q 'quiet-presentation-surface' "${decode_dir}/smali" \
      || die "quiet presentation surface status marker missing"
    grep -R -q 'raf-mainthread-drift' "${decode_dir}/smali" \
      || die "RAF main-thread drift status marker missing"
    grep -q 'quietPresentation' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing quietPresentation class/mode"
    grep -q 'setQuietPresentation' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing setQuietPresentation route"
    grep -q 'contain: strict' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing strict video containment"
    grep -q 'translateZ(0)' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing compositor promotion hint"
    grep -q 'requestAnimationFrame' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing animation-frame presentation diagnostics"
    echo "smartisax_quiet_presentation=ok"
  fi
  if [ "$EXPECTED_WEBRTC_VISIBLE_SCREENBOX" = "1" ]; then
    grep -R -q 'portalFrameBox' "${decode_dir}/smali" \
      || die "visible screenbox status marker missing"
    grep -q 'aspect-ratio: 1080 / 2340' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing stable phone screenBox aspect ratio"
    grep -q 'contain: layout paint;' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing visible screenBox containment"
    ! grep -q 'contain: layout paint size;' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset still has size-contained screenBox"
    grep -q 'height: 100%;' "${decode_dir}/assets/portal/index.html" \
      || die "Portal media elements no longer fill the visible screenBox"
    echo "smartisax_visible_screenbox=ok"
  fi
  if [ "$EXPECTED_WEBRTC_DISPLAY_WAKE_GUARD" = "1" ]; then
    grep -q 'android.permission.WAKE_LOCK' "${decode_dir}/AndroidManifest.xml" \
      || die "Smartisax manifest missing WAKE_LOCK permission"
    grep -R -q 'displayWakeGuard' "${decode_dir}/smali" \
      || die "display wake guard status marker missing"
    grep -R -q 'webrtc-session-screen-wake-lock+activity-keep-screen-on' "${decode_dir}/smali" \
      || die "display wake guard policy marker missing"
    grep -R -q 'Smartisax:PortalWebRtc' "${decode_dir}/smali" \
      || die "display wake guard WakeLock tag missing"
    grep -R -q 'newWakeLock' "${decode_dir}/smali" \
      || die "display wake guard missing PowerManager.newWakeLock call"
    grep -R -q 'setTurnScreenOn' "${decode_dir}/smali" \
      || die "ShellActivity missing setTurnScreenOn call"
    grep -R -q 'portal6d_display_wake_guard' "${decode_dir}/smali" \
      || die "Portal 6d display wake guard reason marker missing"
    echo "smartisax_display_wake_guard=ok"
  fi
  if [ "$EXPECTED_WEBRTC_ENCODER_TRANSPORT_BURST" = "1" ]; then
    grep -R -q 'encoder-transport-burst-clamp' "${decode_dir}/smali" \
      || die "encoder transport burst clamp policy missing"
    grep -R -q '1080p60-target-window-bitrate+late-start-frame-pump+maintain-framerate-sender' "${decode_dir}/smali" \
      || die "encoder transport burst repair marker missing"
    grep -R -q "$EXPECTED_WEBRTC_ENCODER_TRANSPORT_REASON_MARKER" "${decode_dir}/smali" \
      || die "encoder transport reason marker missing: ${EXPECTED_WEBRTC_ENCODER_TRANSPORT_REASON_MARKER}"
    grep -R -q 'senderMaxBitrateBps' "${decode_dir}/smali" \
      || die "senderMaxBitrateBps diagnostic missing"
    grep -R -q 'senderDegradationPreference' "${decode_dir}/smali" \
      || die "senderDegradationPreference diagnostic missing"
    grep -R -q 'MAINTAIN_FRAMERATE' "${decode_dir}/smali" \
      || die "sender maintain-framerate preference missing"
    grep -R -q 'late-start-after-local-sdp' "${decode_dir}/smali" \
      || die "late-start frame pump policy marker missing"
    grep -q 'encoderTransportBurstRepair' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing encoder transport burst repair marker"
    echo "smartisax_encoder_transport_burst=ok"
  fi
  if [ "$EXPECTED_WEBRTC_PRESENTATION_TAIL_CADENCE" = "1" ]; then
    grep -R -q 'marker-visible-tail-presentation-cadence' "${decode_dir}/smali" \
      || die "presentation tail cadence status marker missing"
    grep -R -q 'marker-tail-full-frame-spacing' "${decode_dir}/smali" \
      || die "marker tail full-frame spacing policy marker missing"
    grep -R -q 'inputFrameBoostBurstCadenceMs' "${decode_dir}/smali" \
      || die "inputFrameBoostBurstCadenceMs diagnostic missing"
    grep -R -q 'touch-marker-drawn-burst-presentation-tail' "${decode_dir}/smali" \
      || die "touch marker drawn presentation-tail burst reason missing"
    grep -q 'rvfc-presentation-cadence-lite' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing RVFC presentation cadence lite marker"
    grep -q 'jitterBufferTarget' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing receiver jitterBufferTarget hint"
    echo "smartisax_presentation_tail_cadence=ok"
  fi
  if [ "$EXPECTED_WEBRTC_MEDIA_CALLBACK_TAIL_REPAIR" = "1" ]; then
    grep -R -q 'rvfc-media-callback-tail-dephase' "${decode_dir}/smali" \
      || die "RVFC media callback tail dephase marker missing"
    grep -R -q 'sender-59fps' "${decode_dir}/smali" \
      || die "RVFC media callback tail sender dephase marker missing"
    grep -R -q 'mediaCallbackTailRepair' "${decode_dir}/smali" \
      || die "mediaCallbackTailRepair diagnostic missing"
    grep -R -q 'mediaCallbackTailFrameSpacingMs' "${decode_dir}/smali" \
      || die "mediaCallbackTailFrameSpacingMs diagnostic missing"
    grep -R -q 'senderMaxFramerate' "${decode_dir}/smali" \
      || die "senderMaxFramerate diagnostic missing"
    echo "smartisax_media_callback_tail_repair=ok"
  fi
  if [ "$EXPECTED_WEBRTC_PRESENTER_MODE" = "1" ]; then
    grep -R -q 'canvas-presenter-mode' "${decode_dir}/smali" \
      || die "canvas presenter mode status marker missing"
    grep -R -q 'rvfc-vs-raf-vs-canvas' "${decode_dir}/smali" \
      || die "RVFC/RAF/canvas presentation diagnostic marker missing"
    grep -q 'webRtcPresenterMode' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing WebRTC presenter mode state"
    grep -q 'desiredWebRtcPresenterMode' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing presenter query/localStorage mode route"
    grep -q 'webRtcCanvasPresenterSamples' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing canvas presenter samples"
    grep -q 'ctx.drawImage(video' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing canvas presenter drawImage(video) path"
    grep -q 'webRtcPresenterCanvas' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing canvas presenter CSS mode"
    echo "smartisax_presenter_mode=ok"
  fi
  if [ "$EXPECTED_WEBRTC_PRESENTATION_TRANSPORT_PACING" = "1" ]; then
    grep -R -q 'presentation-transport-pacing' "${decode_dir}/smali" \
      || die "presentation transport pacing status marker missing"
    grep -R -q 'virtualdisplay-60fps-presentation-paced-90hz-input' "${decode_dir}/smali" \
      || die "VirtualDisplay 60fps paced 90Hz input policy marker missing"
    grep -R -q 'presentationFps' "${decode_dir}/smali" \
      || die "presentationFps runtime marker missing"
    grep -R -q 'inputRefreshHz' "${decode_dir}/smali" \
      || die "inputRefreshHz runtime marker missing"
    grep -R -q 'maxPresentationFps' "${decode_dir}/smali" \
      || die "maxPresentationFps limit marker missing"
    grep -q 'transportPacedTuningConfig' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing transport-paced tuning preset marker"
    grep -q 'presentationFps' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing presentationFps config"
    grep -q 'inputRefreshHz' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing inputRefreshHz config"
    grep -q 'transportPacing: "presentation-transport-pacing"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing transportPacing diagnostic marker"
    echo "smartisax_presentation_transport_pacing=ok"
  fi
  if [ "$EXPECTED_WEBRTC_VIDEO_PRIMARY_ROI_PROBE" = "1" ]; then
    grep -R -q 'video-primary-roi-probe' "${decode_dir}/smali" \
      || die "video-primary ROI probe status marker missing"
    grep -R -q 'raf-touch-photon-detect' "${decode_dir}/smali" \
      || die "RAF touch-photon detection status marker missing"
    grep -q 'video-primary-roi-probe+raf-touch-photon-detect' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing video-primary ROI probe marker"
    grep -q 'webRtcPresenterProbe' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing probe presenter CSS mode"
    grep -q '\"probe\"' "${decode_dir}/assets/portal/index.html" \
      || die "Portal asset missing probe presenter option"
    echo "smartisax_video_primary_roi_probe=ok"
  fi
  if [ "$EXPECTED_WEBRTC_MARKER_DRAW_SYNC" = "1" ]; then
    grep -R -q 'marker-draw-synced-capture-boost' "${decode_dir}/smali" \
      || die "marker draw-sync boost status marker missing"
    grep -R -q 'lastDrawnElapsedMs' "${decode_dir}/smali/com/smartisax/browser/SmartisaxTouchMarker"*.smali \
      || die "touch marker lastDrawnElapsedMs diagnostic missing"
    grep -R -q 'lastDrawLatencyMs' "${decode_dir}/smali/com/smartisax/browser/SmartisaxTouchMarker"*.smali \
      || die "touch marker draw latency diagnostic missing"
    grep -R -q 'drawBoostRequests' "${decode_dir}/smali/com/smartisax/browser/SmartisaxTouchMarker"*.smali \
      || die "touch marker drawBoostRequests diagnostic missing"
    grep -R -q 'addOnDrawListener' "${decode_dir}/smali/com/smartisax/browser/SmartisaxTouchMarker"*.smali \
      || die "touch marker draw-sync OnDraw listener missing"
    grep -R -q 'removeOnDrawListener' "${decode_dir}/smali/com/smartisax/browser/SmartisaxTouchMarker"*.smali \
      || die "touch marker draw-sync listener cleanup missing"
    grep -R -q 'touch-marker-drawn-burst' "${decode_dir}/smali" \
      || die "touch marker drawn burst reason missing"
    echo "smartisax_marker_draw_sync=ok"
  fi
  if [ "${EXPECTED_WEBRTC_DRAW_URGENT_BOOST:-0}" = "1" ]; then
    grep -R -q 'draw-urgent-input-frame-boost' "${decode_dir}/smali" \
      || die "draw urgent input frame boost marker missing"
    grep -R -q 'draw-urgent-bypass-half-interval' "${decode_dir}/smali" \
      || die "draw urgent queue policy marker missing"
    grep -R -q 'requestUrgentInputFrameBoost' "${decode_dir}/smali" \
      || die "requestUrgentInputFrameBoost route missing"
    grep -R -q 'touch-marker-drawn-urgent' "${decode_dir}/smali" \
      || die "touch marker drawn urgent reason missing"
    grep -R -q 'inputFrameBoostUrgentRequests' "${decode_dir}/smali" \
      || die "inputFrameBoostUrgentRequests diagnostic missing"
    grep -R -q 'inputFrameBoostUrgentFrames' "${decode_dir}/smali" \
      || die "inputFrameBoostUrgentFrames diagnostic missing"
    grep -R -q 'lastInputFrameBoostUrgentFrameElapsedMs' "${decode_dir}/smali" \
      || die "lastInputFrameBoostUrgentFrameElapsedMs diagnostic missing"
    echo "smartisax_draw_urgent_boost=ok"
  fi
  if [ "$EXPECTED_WEBRTC_BOOST_TOKEN_RETAIN" = "1" ]; then
    grep -R -q 'boost-token-retain' "${decode_dir}/smali" \
      || die "boost token retain mode marker missing"
    grep -R -q 'retain-boost-token-until-captured-frame' "${decode_dir}/smali" \
      || die "boost token captured-frame retain policy marker missing"
    echo "smartisax_boost_token_retain=ok"
  fi
  if [ "$EXPECTED_WEBRTC_INPUT_PRIORITY_FRAME" = "1" ]; then
    grep -R -q 'input-priority-frame' "${decode_dir}/smali" \
      || die "input priority frame mode marker missing"
    grep -R -q 'input-boost-half-interval-capture' "${decode_dir}/smali" \
      || die "input boost half-interval queue policy missing"
    grep -R -q 'inputFrameBoostMinIntervalMs' "${decode_dir}/smali" \
      || die "input boost min-interval diagnostic marker missing"
    echo "smartisax_input_priority_frame=ok"
  fi
  echo "smartisax_apk_semantics=ok"
}

verify_privapp_xml() {
  local xml="$1"
  grep -q '<privapp-permissions package="com.smartisax.browser">' "$xml" || die "privapp XML missing package block"
  grep -q 'android.permission.MANAGE_DEBUGGING' "$xml" || die "privapp XML missing MANAGE_DEBUGGING"
  grep -q 'android.permission.WRITE_SECURE_SETTINGS' "$xml" || die "privapp XML missing WRITE_SECURE_SETTINGS"
  grep -q 'android.permission.READ_FRAME_BUFFER' "$xml" || die "privapp XML missing READ_FRAME_BUFFER"
  grep -q 'android.permission.CAPTURE_VIDEO_OUTPUT' "$xml" || die "privapp XML missing CAPTURE_VIDEO_OUTPUT"
  grep -q 'android.permission.INJECT_EVENTS' "$xml" || die "privapp XML missing INJECT_EVENTS"
  if [ "$EXPECTED_MANAGE_MEDIA_PROJECTION" = "1" ]; then
    grep -q 'android.permission.MANAGE_MEDIA_PROJECTION' "$xml" || die "privapp XML missing MANAGE_MEDIA_PROJECTION"
  fi
  echo "smartisax_privapp_xml=ok"
}

verify_services_policy() {
  local jar="$1" decode_dir="${WORK_DIR}/services-decoded"
  rm -rf "$decode_dir"
  PATH="$(dirname "$JAVA"):${PATH}" "$JAVA" -jar "$APKTOOL_JAR" d -f "$jar" -o "$decode_dir" >/dev/null
  if [ "$EXPECTED_PROJECTION_PERMISSION_POLICY" = "1" ]; then
    python3 - "$decode_dir" <<'PY'
import sys
from pathlib import Path

decoded = Path(sys.argv[1])

def find_one(rel_tail: str) -> Path:
    matches = [path for path in decoded.rglob(Path(rel_tail).name) if str(path).endswith(rel_tail)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {rel_tail}, found {len(matches)}")
    return matches[0]

policy = find_one("com/android/server/pm/SmartisaxPackagePolicy.smali").read_text(encoding="utf-8")
pms = find_one("com/android/server/pm/permission/PermissionManagerService.smali").read_text(encoding="utf-8")
required = [
    "com.smartisax.browser",
    "android.permission.READ_FRAME_BUFFER",
    "android.permission.CAPTURE_VIDEO_OUTPUT",
    "android.permission.MANAGE_MEDIA_PROJECTION",
    "shouldGrantSignaturePermission",
]
for needle in required:
    if needle not in policy:
        raise SystemExit(f"SmartisaxPackagePolicy missing {needle}")
if "android.permission.INJECT_EVENTS" in policy:
    raise SystemExit("SmartisaxPackagePolicy unexpectedly grants INJECT_EVENTS")
if "SmartisaxPackagePolicy;->shouldGrantSignaturePermission" not in pms:
    raise SystemExit("PermissionManagerService Smartisax signature hook missing")
print("smartisax_projection_permission_policy=ok")
PY
  fi
}

verify_system_webrtc_libs_offline() {
  local image="$1"
  [ "$EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS" = "1" ] || return 0
  local expected_arm64 expected_arm arm64_dump arm_dump
  expected_arm64="$(manifest_value "$SYSTEM_MANIFEST" "webrtc_arm64_so_sha256")"
  expected_arm="$(manifest_value "$SYSTEM_MANIFEST" "webrtc_arm_so_sha256")"
  [ -n "$expected_arm64" ] || die "system manifest missing webrtc_arm64_so_sha256"
  [ -n "$expected_arm" ] || die "system manifest missing webrtc_arm_so_sha256"
  arm64_dump="${WORK_DIR}/system-libjingle-peerconnection-arm64.so"
  arm_dump="${WORK_DIR}/system-libjingle-peerconnection-arm.so"
  debugfs_path_exists "$image" "$WEBRTC_ARM64_SO_PATH" || die "missing system arm64 libwebrtc path"
  debugfs_path_exists "$image" "$WEBRTC_ARM_SO_PATH" || die "missing system arm libwebrtc path"
  debugfs_dump "$image" "$WEBRTC_ARM64_SO_PATH" "$arm64_dump"
  debugfs_dump "$image" "$WEBRTC_ARM_SO_PATH" "$arm_dump"
  [ "$(sha256_one "$arm64_dump")" = "$expected_arm64" ] || die "system arm64 libwebrtc hash mismatch"
  [ "$(sha256_one "$arm_dump")" = "$expected_arm" ] || die "system arm libwebrtc hash mismatch"
  echo "system_webrtc_arm64=${expected_arm64}"
  echo "system_webrtc_arm=${expected_arm}"
  echo "smartisax_system_webrtc_libs=ok"
}

verify_device_file_hash() {
  local path="$1" expected="$2" label="$3" actual
  actual="$(adb -s "$SERIAL" shell "sha256sum '${path}' 2>/dev/null" | tr -d '\r' | awk '{print $1; exit}')"
  [ -n "$actual" ] || die "could not hash device ${label}: ${path}"
  [ "$actual" = "$expected" ] || die "device ${label} hash mismatch: actual=${actual} expected=${expected}"
  printf '%s\tsha256=%s\t%s\n' "$label" "$actual" "$path"
}

verify_system_webrtc_libs_device() {
  [ "$EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS" = "1" ] || return 0
  local expected_arm64 expected_arm
  expected_arm64="$(manifest_value_available "webrtc_arm64_so_sha256")"
  expected_arm="$(manifest_value_available "webrtc_arm_so_sha256")"
  [ -n "$expected_arm64" ] || die "manifest missing webrtc_arm64_so_sha256"
  [ -n "$expected_arm" ] || die "manifest missing webrtc_arm_so_sha256"
  adb -s "$SERIAL" shell "test -f '${WEBRTC_ARM64_SO_PATH}'" || die "device missing system arm64 libwebrtc path"
  adb -s "$SERIAL" shell "test -f '${WEBRTC_ARM_SO_PATH}'" || die "device missing system arm libwebrtc path"
  verify_device_file_hash "$WEBRTC_ARM64_SO_PATH" "$expected_arm64" "device-system-libjingle-arm64"
  verify_device_file_hash "$WEBRTC_ARM_SO_PATH" "$expected_arm" "device-system-libjingle-arm"
  echo "smartisax_system_webrtc_libs=ok"
}

offline_image() {
  mkdir -p "$WORK_DIR" "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-offline-image-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} offline verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=offline only; no adb, no fastboot, no flash, no reboot"
    echo
    check_manifest_hash "$SUPER_MANIFEST" "super-sparse" "$SUPER_SPARSE" "super_sparse_sha256"
    check_manifest_hash "$SYSTEM_MANIFEST" "system-b" "$SYSTEM_B_IMG" "system_b_sha256"
    "$SPARSE_TOOL" --source-sparse "$SUPER_SPARSE" --extent "$SYSTEM_B_EXTENT" --verify-image "system_b=${SYSTEM_B_IMG}"
    verify_avb_fec "$SYSTEM_B_IMG"
    "$E2FSCK" -fn "$SYSTEM_B_IMG" >/dev/null
    echo "system_b_e2fsck_readonly=ok"

    local smartisax_dump="${WORK_DIR}/smartisax-priv-app.apk"
    local privapp_xml_dump="${WORK_DIR}/privapp-permissions-com.smartisax.browser.xml"
    local services_dump="${WORK_DIR}/services.jar"
    debugfs_path_exists "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" || die "missing Smartisax APK in system_b"
    debugfs_path_exists "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" || die "missing Smartisax privapp XML in system_b"
    debugfs_path_exists "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" || die "missing services.jar in system_b"
    debugfs_dump "$SYSTEM_B_IMG" "$NEW_SMARTISAX_APK_PATH" "$smartisax_dump"
    debugfs_dump "$SYSTEM_B_IMG" "$PRIVAPP_XML_PATH" "$privapp_xml_dump"
    debugfs_dump "$SYSTEM_B_IMG" "$SERVICES_JAR_PATH" "$services_dump"
    local expected_apk expected_xml
    expected_apk="$(manifest_value "$SYSTEM_MANIFEST" "smartisax_apk_sha256")"
    expected_xml="$(manifest_value "$SYSTEM_MANIFEST" "privapp_xml_sha256")"
    [ "$(sha256_one "$smartisax_dump")" = "$expected_apk" ] || die "dumped Smartisax APK hash mismatch"
    [ "$(sha256_one "$privapp_xml_dump")" = "$expected_xml" ] || die "dumped privapp XML hash mismatch"
    [ "$(sha256_one "$services_dump")" = "$EXPECTED_SERVICES_JAR_SHA256" ] || die "services.jar hash changed"
    verify_services_policy "$services_dump"
    verify_apk_semantics "$smartisax_dump"
    verify_privapp_xml "$privapp_xml_dump"
    verify_system_webrtc_libs_offline "$SYSTEM_B_IMG"
    echo "services_jar_sha256=${EXPECTED_SERVICES_JAR_SHA256}"
    echo "system_b image=$(sha256_one "$SYSTEM_B_IMG") sparse_slice=$(sha256_one "$SYSTEM_B_IMG")"
    echo "result=${OFFLINE_RESULT_NAME}"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

read_only_device() {
  mkdir -p "$INSPECT_DIR"
  local report="${INSPECT_DIR}/verify-${VARIANT}-device-read-only-$(date '+%Y%m%d-%H%M%S').txt"
  {
    echo "# ${VARIANT} device read-only verification"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "boundary=read-only adb; no flash, no reboot, no /data mutation, no service start"
    adb_available || die "adb device ${SERIAL} is not online"
    echo
    echo "## properties"
    adb -s "$SERIAL" shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate' | tr -d '\r'
    echo
    "$ROOT_HELPER" status || warn "root status command failed"
    echo
    echo "## package"
    adb -s "$SERIAL" shell 'pm path com.smartisax.browser; dumpsys package com.smartisax.browser | grep -E "versionCode=|versionName=|codePath=|resourcePath=|nativeLibraryDir=|primaryCpuAbi=|READ_FRAME_BUFFER|CAPTURE_VIDEO_OUTPUT|INJECT_EVENTS|MANAGE_DEBUGGING|WRITE_SECURE_SETTINGS|MANAGE_MEDIA_PROJECTION|WAKE_LOCK" | head -n 100' | tr -d '\r'
    adb -s "$SERIAL" shell 'pm path com.smartisax.browser' | tr -d '\r' | grep -q '/system/priv-app/SmartisaxShell/SmartisaxShell.apk' \
      || die "Smartisax is not served from system priv-app"
    adb -s "$SERIAL" shell 'dumpsys package com.smartisax.browser' | tr -d '\r' > "${INSPECT_DIR}/device-package-${VARIANT}.txt"
    grep -q "versionCode=${EXPECTED_VERSION_CODE}" "${INSPECT_DIR}/device-package-${VARIANT}.txt" || die "device Smartisax versionCode is not ${EXPECTED_VERSION_CODE}"
    grep -q "versionName=${EXPECTED_VERSION_NAME}" "${INSPECT_DIR}/device-package-${VARIANT}.txt" || die "device Smartisax versionName is not ${EXPECTED_VERSION_NAME}"
    grep -q 'primaryCpuAbi=arm64-v8a' "${INSPECT_DIR}/device-package-${VARIANT}.txt" || warn "primaryCpuAbi arm64-v8a not visible in dumpsys"
    grep -q 'android.permission.READ_FRAME_BUFFER: granted=true' "${INSPECT_DIR}/device-package-${VARIANT}.txt" \
      || die "READ_FRAME_BUFFER is not granted"
    if [ "$EXPECTED_MANAGE_MEDIA_PROJECTION" = "1" ]; then
      grep -q 'android.permission.MANAGE_MEDIA_PROJECTION: granted=true' "${INSPECT_DIR}/device-package-${VARIANT}.txt" \
        || die "MANAGE_MEDIA_PROJECTION is not granted"
    fi
    if [ "$EXPECTED_WEBRTC_DISPLAY_WAKE_GUARD" = "1" ]; then
      grep -q 'android.permission.WAKE_LOCK: granted=true' "${INSPECT_DIR}/device-package-${VARIANT}.txt" \
        || die "WAKE_LOCK is not granted"
    fi
    local expected_apk
    expected_apk="$(manifest_value_available "smartisax_apk_sha256")"
    [ -n "$expected_apk" ] || die "manifest missing smartisax_apk_sha256"
    verify_device_file_hash "$NEW_SMARTISAX_APK_PATH" "$expected_apk" "device-smartisax-apk"
    verify_system_webrtc_libs_device
    echo "result=${READ_ONLY_RESULT_NAME}"
  } 2>&1 | tee "$report"
  echo "Report: $report"
}

case "${1:-}" in
  --offline-image) offline_image ;;
  --read-only) read_only_device ;;
  -h|--help|help|"") usage; [ "${1:-}" = "" ] && exit 2 || exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
