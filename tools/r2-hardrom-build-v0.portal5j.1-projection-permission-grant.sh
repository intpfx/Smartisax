#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5j.1-projection-permission-grant"
export SOURCE_VARIANT="v0.portal5j-projection-texture-probe"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5j-projection-texture-probe.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-d51213324cebd9eca4b7dec58a509618949ebc598dcefa9aff6481f2e2921f28}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5j-projection-texture-probe.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-7d75d7cdcaba49a7cda17daf0fa350f34fa6590cff80984732ca3779bac641a2}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export SERVICES_JAR_CANDIDATE="${SERVICES_JAR_CANDIDATE:-${ROOT_DIR}/hard-rom/build/framework/services-portal5j-smartisax-projection-permissions.jar}"
export SERVICES_JAR_CANDIDATE_SHA256="${SERVICES_JAR_CANDIDATE_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a40e000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-28 05:15:00 +0800; invalidates Smartisax package scan/cache after projection permission services.jar grant}"
export PURPOSE="${PURPOSE:-Grant CAPTURE_VIDEO_OUTPUT and MANAGE_MEDIA_PROJECTION only to com.smartisax.browser through the existing SmartisaxPackagePolicy signature-permission hook, on top of v0.portal5j.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
