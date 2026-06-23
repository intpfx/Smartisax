#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5e-webrtc-h264-session-control"
export SOURCE_VARIANT="v0.portal5d-webrtc-bitmap-copy-frames"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5d-webrtc-bitmap-copy-frames.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-c6e1d7107bce64fa647786aa8838a3e13f5996ac105494ee14a7666be31a71be}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5d-webrtc-bitmap-copy-frames.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-bea2172046907c5d0457d15c8014bf765841d010ca901106ea49b455b34fc5d7}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a409000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 02:00:00 +0800; invalidates Smartisax package scan/cache after default H264 WebRTC and session cleanup controls}"
export PURPOSE="${PURPOSE:-Make Smartisax Portal native WebRTC default to browser-side H264 preference, expose WebRTC session status/cleanup APIs, and keep v0.portal5d Bitmap.copy frame pump and external libwebrtc system libraries.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5E_WEBRTC_H264_SESSION_CONTROL}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
