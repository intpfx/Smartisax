#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="${VARIANT:-v0.portal5k.1-frame-timestamp-retain}"
export OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-frame-timestamp-retain-smoke-live}"
export PROFILES="${PROFILES:-1080p30-texture 1080p60-texture}"
export SUMMARY_TITLE="${SUMMARY_TITLE:-v0.portal5k.1 Frame Timestamp Retain WebRTC Smoke}"

exec "${ROOT_DIR}/tools/r2-portal5j2-projection-texture-smoke.sh" "$@"
