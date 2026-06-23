#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5j-projection-texture-probe"
export SOURCE_VARIANT="v0.portal5i-webrtc-runtime-tuning"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5i-webrtc-runtime-tuning.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-7461215ef7403d005be3fe3c13ec711e9129998d28f11736fd3e1474e304aaf7}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5i-webrtc-runtime-tuning.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-f93449427c47e87fb566b30a7c87ee869496b7ec5e01b19b9b1b832b825ade1d}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a40d000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 05:00:00 +0800; invalidates Smartisax package scan/cache after MediaProjection texture capture probe and 1080p60 tuning target}"
export PURPOSE="${PURPOSE:-Add a MediaProjection/VirtualDisplay WebRTC texture capture probe and backend so Portal can move away from Java Bitmap/I420 frame pumping toward a zero-copy 1080p30 minimum and 1080p60 default target.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5J_PROJECTION_TEXTURE_PROBE}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
