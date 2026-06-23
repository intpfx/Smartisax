#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${ROOT_DIR}/bin"
TAG="android-11.0.0_r48"
EXTRAS_DIR="${ROOT_DIR}/${TAG}"
SRC_DIR="${ROOT_DIR}/external-fec-android-11.0.0_r48"
CC_BIN="${CC:-cc}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

fetch_extras_sources() {
  if [ -d "${EXTRAS_DIR}/.git" ]; then
    return
  fi

  rm -rf "$EXTRAS_DIR"
  git clone \
    --filter=blob:none \
    --no-checkout \
    --depth 1 \
    --branch "$TAG" \
    https://android.googlesource.com/platform/system/extras \
    "$EXTRAS_DIR"
  git -C "$EXTRAS_DIR" sparse-checkout init --cone
  git -C "$EXTRAS_DIR" sparse-checkout set verity/fec libfec
  git -C "$EXTRAS_DIR" checkout
}

fetch_external_fec_sources() {
  if [ -d "${SRC_DIR}/.git" ]; then
    return
  fi

  rm -rf "$SRC_DIR"
  git clone \
    --depth 1 \
    --branch "$TAG" \
    https://android.googlesource.com/platform/external/fec \
    "$SRC_DIR"
}

need_cmd git
need_cmd "$CC_BIN"
fetch_extras_sources
fetch_external_fec_sources

mkdir -p "$OUT_DIR"

"$CC_BIN" \
  -std=c11 \
  -Wall \
  -Wextra \
  -O3 \
  -I"$SRC_DIR" \
  "$ROOT_DIR/fec-minimal.c" \
  "$SRC_DIR/init_rs_char.c" \
  "$SRC_DIR/encode_rs_char.c" \
  -o "$OUT_DIR/fec"

"$OUT_DIR/fec" --print-fec-size 4096 --roots 2 >/dev/null
echo "built $OUT_DIR/fec"
