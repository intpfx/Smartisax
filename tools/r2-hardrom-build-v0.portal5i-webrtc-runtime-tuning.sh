#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5i-webrtc-runtime-tuning"
export SOURCE_VARIANT="v0.portal5h-webrtc-bitrate-quality"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5h-webrtc-bitrate-quality.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-9d193755098feb70e283b445aa741412ce35017e28b12931be42015d045a17bd}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5h-webrtc-bitrate-quality.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-1180edf2b4bd401819e4dc3a860b3193d849fc79208b9ef33f5cc768cb0ffa22}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a40c000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 04:00:00 +0800; invalidates Smartisax package scan/cache after WebRTC runtime tuning API and 1080p/30fps Portal controls}"
export PURPOSE="${PURPOSE:-Add token-gated native WebRTC runtime tuning to the Smartisax LAN Portal, keeping stable v0.portal5h defaults while allowing browser-side width/fps/bitrate changes up to 1080p and 30fps for new sessions.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5I_WEBRTC_RUNTIME_TUNING}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
