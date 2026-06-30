#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="${VARIANT:-v0.portal5k-frame-pump-continuity}"
export OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-frame-pump-continuity-smoke-live}"
export PROFILES="${PROFILES:-1080p30-texture 1080p60-texture}"
export SUMMARY_TITLE="${SUMMARY_TITLE:-v0.portal5k Frame Pump Continuity WebRTC Smoke}"

exec "${ROOT_DIR}/tools/r2-portal5j2-projection-texture-smoke.sh" "$@"
