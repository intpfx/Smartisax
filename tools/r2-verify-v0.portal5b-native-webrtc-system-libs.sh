#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5b-native-webrtc-system-libs"
export EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS="1"
export OFFLINE_RESULT_NAME="PASS_OFFLINE_IMAGE_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS"
export READ_ONLY_RESULT_NAME="PASS_READ_ONLY_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS"

exec "${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh" "$@"
