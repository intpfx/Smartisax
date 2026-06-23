#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5h-webrtc-bitrate-quality"
export SOURCE_VARIANT="v0.portal5g-webrtc-touch-quality"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5g-webrtc-touch-quality.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-cbe9d5ff93fcf1ab492dbf0a86ee3524daad72ec320f60c30a8588cb1db00cb0}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5g-webrtc-touch-quality.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-b3cdb42a8d964fd35fa6302bc76e0b041464dacbb291692d06d659bfccb37213}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a40b000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 03:13:04 +0800; invalidates Smartisax package scan/cache after WebRTC-only portal UI and explicit H264 sender bitrate tuning}"
export PURPOSE="${PURPOSE:-Make native WebRTC the default Portal UI path, remove visible legacy transport choices, and set explicit H264 RtpSender bitrate parameters for sharper direct-LAN mirroring.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5H_WEBRTC_BITRATE_QUALITY}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
