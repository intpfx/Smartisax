#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

SOURCE_SYSTEM_B_DEFAULT="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5p-dual-phase-input-boost.img"
SOURCE_SYSTEM_B_WORK="${ROOT_DIR}/hard-rom/work/v0.portal5s-event-time-input-priority/source/system-otatrust-v0.portal5p-dual-phase-input-boost.img"
SOURCE_SYSTEM_B_EXPECTED_SHA256="354246abbac4ee418b78580ef75682cc9bc089be067c57066a397e602821e58a"
SOURCE_SPARSE_PATH="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5p-dual-phase-input-boost.sparse.img"

if [ ! -f "$SOURCE_SYSTEM_B_DEFAULT" ]; then
  mkdir -p "$(dirname "$SOURCE_SYSTEM_B_WORK")"
  if [ ! -f "$SOURCE_SYSTEM_B_WORK" ]; then
    "$SPARSE_TOOL" \
      --source-sparse "$SOURCE_SPARSE_PATH" \
      --extent "system_b=8306688:6217336" \
      --extract-image "system_b=${SOURCE_SYSTEM_B_WORK}" >/dev/null
  fi
  SOURCE_SYSTEM_B_DEFAULT="$SOURCE_SYSTEM_B_WORK"
fi

export VARIANT="v0.portal5s-event-time-input-priority"
export SOURCE_VARIANT="v0.portal5p-dual-phase-input-boost"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${SOURCE_SPARSE_PATH}}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-4c7d83fbb34a5f9aa76edd65cc5088f9decb190d341f1b14f302f46f86d1c1ef}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${SOURCE_SYSTEM_B_DEFAULT}}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-${SOURCE_SYSTEM_B_EXPECTED_SHA256}}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a442800}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-07-01 02:32:00 +0800; invalidates Smartisax package scan/cache after Portal event-time input priority repair}"
export PURPOSE="${PURPOSE:-Keep the 60/90Hz local-feel target while preserving browser pointer event timing through move-stream injection and allowing input-triggered projection frames to use half-interval priority capture.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY}"

"${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
