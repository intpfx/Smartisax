#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="v0.portal5a-native-webrtc-runtime"
export SOURCE_VARIANT="v0.portal4c-session-hardening"
export SOURCE_SPARSE="${SOURCE_SPARSE:-${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal4c-session-hardening.sparse.img}"
export SOURCE_SPARSE_SHA256="${SOURCE_SPARSE_SHA256:-66693df65d84e4ef775ff5a2e8b364aa87a4bd6cb203934fa81226bf2146f672}"
export SOURCE_SYSTEM_B="${SOURCE_SYSTEM_B:-${ROOT_DIR}/hard-rom/build/system-otatrust-v0.portal4c-session-hardening.img}"
export SOURCE_SYSTEM_B_SHA256="${SOURCE_SYSTEM_B_SHA256:-7234bc2dbf266715e8cff1d507352694a133d820338bac96821d058943e88a5a}"
export PACKAGE_DIR_MTIME_HEX="${PACKAGE_DIR_MTIME_HEX:-0x6a3c1800}"
export PACKAGE_DIR_MTIME_NOTE="${PACKAGE_DIR_MTIME_NOTE:-2026-06-25 00:00:00 +0800; invalidates Smartisax package scan/cache after native libwebrtc runtime APK update}"
export PURPOSE="${PURPOSE:-Add the first native Android libwebrtc DTLS/SRTP runtime gate to Smartisax Portal on top of live-proven v0.portal4c, while retaining MP4/PNG/input fallbacks.}"
export RESULT_NAME="${RESULT_NAME:-PASS_BUILD_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME}"

exec "${ROOT_DIR}/tools/r2-hardrom-build-v0.portal4c-session-hardening.sh" "$@"
