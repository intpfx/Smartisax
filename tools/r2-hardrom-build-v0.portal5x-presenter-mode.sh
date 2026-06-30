#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

SOURCE_SYSTEM_B_DEFAULT="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal5w-quiet-presentation.img"
SOURCE_SYSTEM_B_WORK="${ROOT_DIR}/hard-rom/work/v0.portal5x-presenter-mode/source/system-otatrust-v0.portal5w-quiet-presentation.img"
SOURCE_SYSTEM_B_EXPECTED_SHA256="0c54440dcfde80c389dce5b40f854a94eae8e5c10f6c7634861063fbf35e823b"
SOURCE_SPARSE_PATH="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5w-quiet-presentation.sparse.img"

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

export VARIANT="v0.portal5x-presenter-mode"
export SOURCE_VARIANT="v0.portal5w-quiet-presentation"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${SOURCE_SPARSE_PATH}}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-bf7145e79050d65cba96b1c0451c8b5c246957f8ef2fb9c513cc2966db77b593}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${SOURCE_SYSTEM_B_DEFAULT}}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-${SOURCE_SYSTEM_B_EXPECTED_SHA256}}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a448000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-07-01 08:16:00 +0800; invalidates Smartisax package scan/cache after Portal presenter-mode repair}"
export PURPOSE="${PURPOSE:-Separate Chrome video presentation bottlenecks by adding video/canvas/dual receiver presenter modes and RVFC/RAF/canvas cadence diagnostics on top of v0.portal5w.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5X_PRESENTER_MODE}"

"${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
