#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5g-webrtc-touch-quality"
export SOURCE_VARIANT="v0.portal5f-webrtc-datachannel-input"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5f-webrtc-datachannel-input.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-b3b633b97f218a713dd09980b85a8d566914c4ac604121214e1961e2b40a93a0}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5f-webrtc-datachannel-input.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-dbbdb34b39a27420043c0a0b22147bb8709e0d395acdf0359e98b8552f70b9d2}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a40a000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 03:06:40 +0800; invalidates Smartisax package scan/cache after touch overlay display-coordinate input and WebRTC frame-pump quality tuning}"
export PURPOSE="${PURPOSE:-Map Portal browser touch overlay events to real display coordinates over the smartisax-input WebRTC DataChannel, and raise native WebRTC frame-pump defaults for better quality and latency.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5G_WEBRTC_TOUCH_QUALITY}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
