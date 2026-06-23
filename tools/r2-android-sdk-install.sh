#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${SDK_ROOT:-${ROOT_DIR}/third_party/android-sdk}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${ROOT_DIR}/third_party/_downloads/android-sdk}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}"
JAVA="${JAVA:-${JAVA_HOME}/bin/java}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip}"
CMDLINE_TOOLS_ZIP="${DOWNLOAD_DIR}/$(basename "${CMDLINE_TOOLS_URL}")"
SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"

PACKAGES=(
  "platform-tools"
  "platforms;android-30"
  "platforms;android-35"
  "build-tools;35.0.1"
  "cmake;3.22.1"
  "ndk;27.2.12479018"
)

if [ "$#" -gt 0 ]; then
  PACKAGES=("$@")
fi

need_executable() {
  [ -x "$1" ] || {
    echo "missing executable: $1" >&2
    exit 1
  }
}

need_executable "$JAVA"
mkdir -p "$SDK_ROOT" "$DOWNLOAD_DIR"

if [ ! -x "$SDKMANAGER" ]; then
  echo "Downloading Android commandline-tools..."
  curl -fL --retry 3 --connect-timeout 30 -o "$CMDLINE_TOOLS_ZIP" "$CMDLINE_TOOLS_URL"
  unzip -t "$CMDLINE_TOOLS_ZIP" >/dev/null

  tmp_dir="${SDK_ROOT}/.cmdline-tools-tmp"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir" "${SDK_ROOT}/cmdline-tools"
  unzip -q "$CMDLINE_TOOLS_ZIP" -d "$tmp_dir"
  rm -rf "${SDK_ROOT}/cmdline-tools/latest"
  mv "${tmp_dir}/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"
  rm -rf "$tmp_dir"
fi

need_executable "$SDKMANAGER"

export JAVA_HOME
echo "Accepting Android SDK licenses..."
set +o pipefail
yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null
license_rc="${PIPESTATUS[1]}"
set -o pipefail
if [ "$license_rc" -ne 0 ]; then
  echo "sdkmanager license acceptance failed: ${license_rc}" >&2
  exit "$license_rc"
fi

echo "Installing Android SDK packages:"
printf '  %s\n' "${PACKAGES[@]}"
"$SDKMANAGER" --sdk_root="$SDK_ROOT" "${PACKAGES[@]}"

cat > "${SDK_ROOT}/smartisax-sdk.env" <<EOF
export JAVA_HOME="${JAVA_HOME}"
export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export PATH="${SDK_ROOT}/cmdline-tools/latest/bin:${SDK_ROOT}/platform-tools:${SDK_ROOT}/build-tools/35.0.1:${JAVA_HOME}/bin:\$PATH"
EOF

echo "sdk_root=${SDK_ROOT}"
echo "env_script=${ROOT_DIR}/tools/r2-android-sdk-env.sh"
echo "sdk_env=${SDK_ROOT}/smartisax-sdk.env"
shasum -a 256 "$CMDLINE_TOOLS_ZIP" > "${DOWNLOAD_DIR}/SHA256SUMS.txt"
