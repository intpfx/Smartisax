#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.26a.2-launcher-entry-hide-v2cert-cachebump"
export EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img"
export EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump.img"
export VERIFY_LABEL="v0.26a.2 launcher-entry-hide v2cert cachebump"
export REPORT_PREFIX="verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump"
export HELD_TAG="v026a2"
export EXPECTED_APK_SIG_BLOCK="present"
export EXPECTED_PACKAGE_DIR_MTIME_HEX="0x6a33ddc0"
export REQUIRE_UNLOCKED_LAUNCHER="1"
export VIDEO_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.videoplayerproject-launcher-hidden-v2cert.apk"
export SCREENREC_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.screenrecorder-launcher-hidden-v2cert.apk"
export QUICKSEARCH_APK="${ROOT_DIR}/hard-rom/build/apk/com.smartisanos.quicksearch-launcher-hidden-v2cert.apk"

exec "${ROOT_DIR}/tools/r2-verify-v0.26a-launcher-entry-hide.sh" "$@"
