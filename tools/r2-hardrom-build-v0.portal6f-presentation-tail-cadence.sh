#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"

SOURCE_SYSTEM_B_DEFAULT="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal6e-encoder-transport-burst.img"
SOURCE_SYSTEM_B_WORK="${ROOT_DIR}/hard-rom/work/v0.portal6f-presentation-tail-cadence/source/system-otatrust-v0.portal6e-encoder-transport-burst.img"
SOURCE_SYSTEM_B_EXPECTED_SHA256="04cfe9746848f5daee752a13efb18ba3cb938d8c7969d5b48333c965f319a6b7"
SOURCE_SPARSE_PATH="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal6e-encoder-transport-burst.sparse.img"

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

export VARIANT="v0.portal6f-presentation-tail-cadence"
export SOURCE_VARIANT="v0.portal6e-encoder-transport-burst"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${SOURCE_SPARSE_PATH}}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${SOURCE_SYSTEM_B_DEFAULT}}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-${SOURCE_SYSTEM_B_EXPECTED_SHA256}}"
export WEBRTC_ARM64_SO="${WEBRTC_ARM64_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/arm64-v8a/libjingle_peerconnection_so.so}"
export WEBRTC_ARM_SO="${WEBRTC_ARM_SO:-${ROOT_DIR}/hard-rom/build/apk/SmartisaxShell-java/webrtc-aar/jni/armeabi-v7a/libjingle_peerconnection_so.so}"
export EXPECTED_SERVICES_JAR_SHA256="${EXPECTED_SERVICES_JAR_SHA256:-3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a475700}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-07-03 14:48:00 +0800; invalidates Smartisax package scan/cache after Portal RVFC presentation-tail cadence repair}"
export PURPOSE="${PURPOSE:-Repair RVFC/presentation cadence and 1080/60 marker-visible touch-to-photon tail by pacing marker tail boosts at full video-frame cadence, extending marker visibility, and adding browser receiver jitter-buffer cadence diagnostics while preserving v0.portal6e encoder/transport burst behavior.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL6F_PRESENTATION_TAIL_CADENCE}"

"${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
