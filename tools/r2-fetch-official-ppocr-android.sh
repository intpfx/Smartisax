#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ROOT="${PPOCR_ANDROID_OUT:-${ROOT_DIR}/third_party/_downloads/paddleocr-ppocr-android}"
REPO_DIR="${OUT_ROOT}/PaddleOCR"
MANIFEST="${OUT_ROOT}/ppocr-android-manifest.txt"
REMOTE="${PPOCR_ANDROID_REMOTE:-https://github.com/PaddlePaddle/PaddleOCR.git}"
REF="${PPOCR_ANDROID_REF:-main}"

die() {
  echo "error: $*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_command git
need_command shasum

mkdir -p "$OUT_ROOT"

if [ ! -d "${REPO_DIR}/.git" ]; then
  git clone --depth 1 --filter=blob:none --sparse --branch "$REF" "$REMOTE" "$REPO_DIR"
fi

git -C "$REPO_DIR" sparse-checkout set deploy/ppocr-android
git -C "$REPO_DIR" fetch --depth 1 origin "$REF"
git -C "$REPO_DIR" checkout FETCH_HEAD

SDK_DIR="${REPO_DIR}/deploy/ppocr-android/ppocr-sdk"
[ -d "$SDK_DIR" ] || die "missing official ppocr-sdk: $SDK_DIR"

{
  echo "kind=official-paddleocr-ppocr-android-intake"
  echo "remote=${REMOTE}"
  echo "ref=${REF}"
  echo "commit=$(git -C "$REPO_DIR" rev-parse HEAD)"
  echo "source_dir=${REPO_DIR}/deploy/ppocr-android"
  echo "sdk_dir=${SDK_DIR}"
  echo "fetched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "[versions]"
  grep -E 'onnxruntime|opencv|minSdk|kotlin|agp' \
    "${REPO_DIR}/deploy/ppocr-android/gradle/libs.versions.toml" \
    "${SDK_DIR}/build.gradle.kts" || true
  echo
  echo "[key_files]"
  find "$SDK_DIR/src/main/java" -type f | sort
  echo
  echo "[sha256]"
  shasum -a 256 \
    "${REPO_DIR}/deploy/ppocr-android/README_en.md" \
    "${REPO_DIR}/deploy/ppocr-android/gradle/libs.versions.toml" \
    "${SDK_DIR}/build.gradle.kts" \
    "${SDK_DIR}/src/main/java/com/paddle/ocr/PaddleOCR.kt" \
    "${SDK_DIR}/src/main/java/com/paddle/ocr/engine/OCREngine.kt" \
    "${SDK_DIR}/src/main/java/com/paddle/ocr/postprocess/DBPostProcessor.kt" \
    "${SDK_DIR}/src/main/java/com/paddle/ocr/postprocess/CTCDecoder.kt" \
    "${SDK_DIR}/src/main/java/com/paddle/ocr/postprocess/QuadTextCrop.kt"
} > "$MANIFEST"

echo "PASS_OFFICIAL_PPOCR_ANDROID_INTAKE"
echo "Manifest: ${MANIFEST}"
