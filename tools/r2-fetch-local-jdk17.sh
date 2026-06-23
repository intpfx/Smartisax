#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ROOT="${ROOT_DIR}/third_party/_downloads/jdk"
INSTALL_ROOT="${OUT_ROOT}/temurin-17"

case "$(uname -m)" in
  arm64|aarch64)
    ADOPTIUM_ARCH="aarch64"
    ;;
  x86_64|amd64)
    ADOPTIUM_ARCH="x64"
    ;;
  *)
    echo "error: unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

JAVA_BIN="${INSTALL_ROOT}/Contents/Home/bin/java"
if [ -x "$JAVA_BIN" ]; then
  "$JAVA_BIN" -version
  echo "JDK already available: ${INSTALL_ROOT}/Contents/Home"
  exit 0
fi

mkdir -p "$OUT_ROOT"
TARBALL="${OUT_ROOT}/temurin-17-mac-${ADOPTIUM_ARCH}.tar.gz"
TMP_DIR="$(mktemp -d "${OUT_ROOT}/temurin-17.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

URL="https://api.adoptium.net/v3/binary/latest/17/ga/mac/${ADOPTIUM_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
curl --fail --location --retry 3 --output "$TARBALL" "$URL"
tar -xzf "$TARBALL" -C "$TMP_DIR"

JAVA_BIN_IN_TMP="$(find "$TMP_DIR" -path '*/Contents/Home/bin/java' -type f | sort | head -n 1)"
if [ -z "$JAVA_BIN_IN_TMP" ]; then
  echo "error: downloaded JDK archive did not contain Contents/Home/bin/java" >&2
  exit 1
fi

JDK_BUNDLE="$(cd "$(dirname "$JAVA_BIN_IN_TMP")/../../.." && pwd)"
rm -rf "$INSTALL_ROOT"
mv "$JDK_BUNDLE" "$INSTALL_ROOT"
"$JAVA_BIN" -version
echo "Installed JDK: ${INSTALL_ROOT}/Contents/Home"
