#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.26a.1-launcher-entry-hide-v2cert"
export EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26a.1-launcher-entry-hide-v2cert-exact-current.sparse.img"
export EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.26a.1-launcher-entry-hide-v2cert.img"
export VERIFY_LABEL="v0.26a.1 launcher-entry-hide v2cert"
export REPORT_PREFIX="verify-v0.26a.1-launcher-entry-hide-v2cert"
export HELD_TAG="v026a1"
export EXPECTED_APK_SIG_BLOCK="present"
export VIDEO_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.videoplayerproject-launcher-hidden-v2cert.apk"
export SCREENREC_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.screenrecorder-launcher-hidden-v2cert.apk"
export QUICKSEARCH_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.quicksearch-launcher-hidden-v2cert.apk"

exec "${ROOT_DIR}/tools/r2-verify-v0.26a-launcher-entry-hide.sh" "$@"
