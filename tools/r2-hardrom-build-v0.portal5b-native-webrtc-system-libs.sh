#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5b-native-webrtc-system-libs"
export SOURCE_VARIANT="v0.portal5a-native-webrtc-runtime"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5a-native-webrtc-runtime.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-c6b7f1d5605ff7e69a4d785bab91a10baa1af65d48b54d9c11bd9bb43061b814}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5a-native-webrtc-runtime.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-df7d2e4aac9b392224e91bfd798d3fb940e4ae1806db0a6ebd9cfca7ec237604}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a3d9000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-26 00:00:00 +0800; invalidates Smartisax package scan/cache after adding external system native libwebrtc libraries}"
export PURPOSE="${PURPOSE:-Repair v0.portal5a native library loading by installing libjingle_peerconnection_so.so as external Smartisax system app libraries under /system/priv-app/SmartisaxShell/lib/arm64 and lib/arm.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
