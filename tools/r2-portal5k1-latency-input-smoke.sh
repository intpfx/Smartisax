#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export VARIANT="${VARIANT:-v0.portal5k.1-frame-timestamp-retain}"
export OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/${VARIANT}/portal-latency-input-smoke-live}"
export PROFILES="${PROFILES:-1080p60-texture}"
export SUMMARY_TITLE="${SUMMARY_TITLE:-v0.portal5k.1 1080/60 Latency And Input Metrics Smoke}"
export OBSERVE_MS="${OBSERVE_MS:-60000}"
export TIMEOUT_MS="${TIMEOUT_MS:-160000}"
export INPUT_LATENCY_TEST="${INPUT_LATENCY_TEST:-1}"
export INPUT_PING_COUNT="${INPUT_PING_COUNT:-40}"
export INPUT_PING_INTERVAL_MS="${INPUT_PING_INTERVAL_MS:-100}"
export STATS_INTERVAL_MS="${STATS_INTERVAL_MS:-500}"

exec "${ROOT_DIR}/tools/r2-portal5j2-projection-texture-smoke.sh" "$@"
