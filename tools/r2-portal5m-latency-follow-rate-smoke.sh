#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="${VARIANT:-v0.portal5m-latency-follow-rate}"
export OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-latency-follow-rate-smoke-live}"
export PROFILES="${PROFILES:-1080p30-texture 1080p60-texture}"
export SUMMARY_TITLE="${SUMMARY_TITLE:-v0.portal5m Latency Follow-rate WebRTC Smoke}"
export OBSERVE_MS="${OBSERVE_MS:-60000}"
export TIMEOUT_MS="${TIMEOUT_MS:-180000}"
export INPUT_LATENCY_TEST="${INPUT_LATENCY_TEST:-1}"
export INPUT_PING_COUNT="${INPUT_PING_COUNT:-40}"
export INPUT_PING_INTERVAL_MS="${INPUT_PING_INTERVAL_MS:-100}"
export STATS_INTERVAL_MS="${STATS_INTERVAL_MS:-500}"
export TOUCH_PHOTON_TEST="${TOUCH_PHOTON_TEST:-1}"
export MOVE_STREAM_TEST="${MOVE_STREAM_TEST:-1}"
export MOVE_STREAM_MOVES="${MOVE_STREAM_MOVES:-30}"
export MOVE_STREAM_INTERVAL_MS="${MOVE_STREAM_INTERVAL_MS:-16}"
export MOVE_STREAM_BATCH_SIZE="${MOVE_STREAM_BATCH_SIZE:-5}"
export PREFER_CODECS="${PREFER_CODECS:-H264,AV1,VP9,H265}"

exec "${ROOT_DIR}/tools/r2-portal5j2-projection-texture-smoke.sh" "$@"
