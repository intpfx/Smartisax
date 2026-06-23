#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5d-webrtc-bitmap-copy-frames"
export EXPECTED_VERSION_CODE="19"
export EXPECTED_VERSION_NAME="0.6.2"
export EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS="1"
export EXPECTED_PORTAL_VARIANT_MARKER="v0.portal5d-webrtc-bitmap-copy-frames"
export EXPECTED_SOFTWARE_BITMAP_FRAME_PUMP="0"
export EXPECTED_BITMAP_COPY_FRAME_PUMP="1"
export OFFLINE_RESULT_NAME="PASS_OFFLINE_IMAGE_V0PORTAL5D_WEBRTC_BITMAP_COPY_FRAMES"
export READ_ONLY_RESULT_NAME="PASS_READ_ONLY_V0PORTAL5D_WEBRTC_BITMAP_COPY_FRAMES"

exec "${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh" "$@"
