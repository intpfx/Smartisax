#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5c-webrtc-software-bitmap-frames"
export SOURCE_VARIANT="v0.portal5b-native-webrtc-system-libs"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5b-native-webrtc-system-libs.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-39b7d30bb628671f82a1bd358c44d71e2b675f5cac843ba690141f1ffd567544}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5b-native-webrtc-system-libs.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-5495b80bc8ef8b1d6a14e75d12615944026834743cb35bd3688916c0f2a5d87f}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a3ef800}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-27 00:00:00 +0800; invalidates Smartisax package scan/cache after WebRTC frame pump software-bitmap fix}"
export PURPOSE="${PURPOSE:-Repair v0.portal5b WebRTC video frames by converting SurfaceControl HARDWARE screenshots to readable ARGB_8888 software bitmaps before I420 conversion.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5C_WEBRTC_SOFTWARE_BITMAP_FRAMES}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
