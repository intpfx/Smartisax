#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5d-webrtc-bitmap-copy-frames"
export SOURCE_VARIANT="v0.portal5c-webrtc-software-bitmap-frames"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5c-webrtc-software-bitmap-frames.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-429816c1ebf2d8e0ea3e152d6b7a7d1d19dcddc9c12049ad990eff07c19652c9}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5c-webrtc-software-bitmap-frames.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-e82258355f4544797bbbea401c09e864207c7467bd51c74529af9b9956eb6e80}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a407000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 00:00:00 +0800; invalidates Smartisax package scan/cache after WebRTC frame pump Bitmap.copy fix}"
export PURPOSE="${PURPOSE:-Repair v0.portal5c WebRTC video frames by using Bitmap.copy(ARGB_8888,false), the same hardware-bitmap conversion path already proven by PNG/MP4 routes, before I420 conversion.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5D_WEBRTC_BITMAP_COPY_FRAMES}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
