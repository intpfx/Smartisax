#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

SOURCE_SYSTEM_B_DEFAULT="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal6c-visible-screenbox.img"
SOURCE_SYSTEM_B_WORK="${ROOT_DIR}/hard-rom/work/v0.portal6d-display-wake-guard/source/system-otatrust-v0.portal6c-visible-screenbox.img"
SOURCE_SYSTEM_B_EXPECTED_SHA256="0854bd2deb455759baee791b4860f8be2cf1686675d32e662126c913a1c76c7c"
SOURCE_SPARSE_PATH="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal6c-visible-screenbox.sparse.img"

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

export VARIANT="v0.portal6d-display-wake-guard"
export SOURCE_VARIANT="v0.portal6c-visible-screenbox"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${SOURCE_SPARSE_PATH}}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-df7912827b4201bcff601edcc300fe79654ffdc571dda860272eb6485a247a9a}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${SOURCE_SYSTEM_B_DEFAULT}}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-${SOURCE_SYSTEM_B_EXPECTED_SHA256}}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a473960}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-07-03 12:24:00 +0800; invalidates Smartisax package scan/cache after Portal display wake guard}"
export PURPOSE="${PURPOSE:-Keep the R2 display awake during real Portal WebRTC sessions so MediaProjection does not stream black frames after the phone sleeps, while preserving v0.portal6c visible screenBox and all 6b latency/input paths.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL6D_DISPLAY_WAKE_GUARD}"

"${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
