#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORT_ANDROID_VERSION="${ORT_ANDROID_VERSION:-1.26.0}"
ORT_WEB_VERSION="${ORT_WEB_VERSION:-1.27.0}"
DOWNLOAD_ROOT="${ONNXRUNTIME_DOWNLOAD_ROOT:-${ROOT_DIR}/third_party/_downloads/onnxruntime}"
ANDROID_DIR="${DOWNLOAD_ROOT}/android"
WEB_DIR="${DOWNLOAD_ROOT}/web"
MANIFEST="${DOWNLOAD_ROOT}/runtime-manifest.txt"

die() {
  echo "error: $*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_command curl
need_command npm

mkdir -p "$ANDROID_DIR" "$WEB_DIR"

ANDROID_AAR="${ANDROID_DIR}/onnxruntime-android-${ORT_ANDROID_VERSION}.aar"
ANDROID_URL="https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ORT_ANDROID_VERSION}/onnxruntime-android-${ORT_ANDROID_VERSION}.aar"
if [ ! -f "$ANDROID_AAR" ]; then
  curl -fL "$ANDROID_URL" -o "$ANDROID_AAR"
fi

npm install --prefix "$WEB_DIR" --no-audit --no-fund "onnxruntime-web@${ORT_WEB_VERSION}"

{
  echo "kind=onnxruntime-runtime-downloads"
  echo "android_version=${ORT_ANDROID_VERSION}"
  echo "android_aar=${ANDROID_AAR}"
  echo "android_url=${ANDROID_URL}"
  echo "web_version=${ORT_WEB_VERSION}"
  echo "web_prefix=${WEB_DIR}"
  echo "downloaded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$ANDROID_AAR"
  find "${WEB_DIR}/node_modules/onnxruntime-web/dist" -maxdepth 1 -type f -print0 \
    | sort -z \
    | xargs -0 shasum -a 256
} > "$MANIFEST"

echo "PASS_ONNXRUNTIME_RUNTIME_FETCH"
echo "Manifest: ${MANIFEST}"
