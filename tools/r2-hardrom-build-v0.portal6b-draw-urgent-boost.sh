#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

SOURCE_SYSTEM_B_DEFAULT="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal6a-marker-draw-sync.img"
SOURCE_SYSTEM_B_WORK="${ROOT_DIR}/hard-rom/work/v0.portal6b-draw-urgent-boost/source/system-otatrust-v0.portal6a-marker-draw-sync.img"
SOURCE_SYSTEM_B_EXPECTED_SHA256="a35a82f194eb06a7f6199562ff87ea9db4f5875ccf536275993d864fc917f5a0"
SOURCE_SPARSE_PATH="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal6a-marker-draw-sync.sparse.img"

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

export VARIANT="v0.portal6b-draw-urgent-boost"
export SOURCE_VARIANT="v0.portal6a-marker-draw-sync"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${SOURCE_SPARSE_PATH}}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-b8d2bbe12c3d889fa83963ea8d8e31e2a47b2a460c075d11b29ba4d1676fcc2a}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${SOURCE_SYSTEM_B_DEFAULT}}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-${SOURCE_SYSTEM_B_EXPECTED_SHA256}}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a45c000}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-07-02 12:00:00 +0800; invalidates Smartisax package scan/cache after Portal draw-urgent boost repair}"
export PURPOSE="${PURPOSE:-Reduce marker-visible touch-to-photon tail latency on top of live/read-only v0.portal6a by letting draw-synced marker boosts bypass the normal half-frame input boost spacing while preserving 60/90Hz transport pacing and 6a marker draw telemetry.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL6B_DRAW_URGENT_BOOST}"

"${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
