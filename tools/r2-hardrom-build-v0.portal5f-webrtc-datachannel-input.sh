#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5f-webrtc-datachannel-input"
export SOURCE_VARIANT="v0.portal5e-webrtc-h264-session-control"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5e-webrtc-h264-session-control.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-d495f67bd1a342ae9ff063e8ffaa5730f5f041cb0dae45e5e9166ccf1cfe8666}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5e-webrtc-h264-session-control.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-624ab39d6a0a15d915853fffe0ed49c78f5e9a80a62b76f26afdd561ba67e7a9}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a409800}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 02:32:00 +0800; invalidates Smartisax package scan/cache after removing HTTP input and adding WebRTC DataChannel input}"
export PURPOSE="${PURPOSE:-Remove token-gated HTTP /api/input, move Portal remote control input into the WebRTC smartisax-input RTCDataChannel, and keep v0.portal5e default H264/session cleanup behavior.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
