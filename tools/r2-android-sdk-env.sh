#!/usr/bin/env bash
# Source this file before local Android/PP-OCR benchmark builds:
#   source tools/r2-android-sdk-env.sh

if [ -n "${BASH_VERSION:-}" ]; then
  R2_ANDROID_ENV_SCRIPT="${BASH_SOURCE[0]}"
  if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "source this file instead of executing it:" >&2
    echo "  source tools/r2-android-sdk-env.sh" >&2
    exit 2
  fi
elif [ -n "${ZSH_VERSION:-}" ]; then
  R2_ANDROID_ENV_SCRIPT="${(%):-%x}"
  if [[ "${ZSH_EVAL_CONTEXT:-}" != *:file* ]]; then
    echo "source this file instead of executing it:" >&2
    echo "  source tools/r2-android-sdk-env.sh" >&2
    return 2 2>/dev/null || exit 2
  fi
else
  R2_ANDROID_ENV_SCRIPT="$0"
fi

R2_ANDROID_ENV_ROOT="$(cd "$(dirname "${R2_ANDROID_ENV_SCRIPT}")/.." && pwd)"

if [ -z "${JAVA_HOME:-}" ]; then
  R2_ANDROID_JAVA_CANDIDATES=(
    "${R2_ANDROID_ENV_ROOT}/third_party/_downloads/jdk/temurin-17/Contents/Home"
    "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
  )
  for R2_ANDROID_JAVA_HOME in "${R2_ANDROID_JAVA_CANDIDATES[@]}"; do
    if [ -x "${R2_ANDROID_JAVA_HOME}/bin/java" ]; then
      export JAVA_HOME="${R2_ANDROID_JAVA_HOME}"
      break
    fi
  done
  export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}"
fi
export ANDROID_HOME="${ANDROID_HOME:-${R2_ANDROID_ENV_ROOT}/third_party/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME}}"

if [ -d "${ANDROID_SDK_ROOT}/ndk" ]; then
  R2_ANDROID_NDK_DIR="$(find "${ANDROID_SDK_ROOT}/ndk" -mindepth 1 -maxdepth 1 -type d | sort -r | head -n 1)"
  if [ -n "${R2_ANDROID_NDK_DIR}" ]; then
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${R2_ANDROID_NDK_DIR}}"
    export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME}}"
  fi
fi

R2_ANDROID_PATHS=(
  "${JAVA_HOME}/bin"
  "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin"
  "${ANDROID_SDK_ROOT}/platform-tools"
  "${ANDROID_SDK_ROOT}/build-tools/35.0.1"
  "${ANDROID_SDK_ROOT}/cmake/3.22.1/bin"
)

if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  R2_ANDROID_PATHS+=("${ANDROID_NDK_HOME}")
  R2_ANDROID_PATHS+=("${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/darwin-x86_64/bin")
  R2_ANDROID_PATHS+=("${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/darwin-arm64/bin")
fi

for R2_ANDROID_PATH in "${R2_ANDROID_PATHS[@]}"; do
  if [ -d "${R2_ANDROID_PATH}" ]; then
    case ":${PATH}:" in
      *":${R2_ANDROID_PATH}:"*) ;;
      *) export PATH="${R2_ANDROID_PATH}:${PATH}" ;;
    esac
  fi
done

unset R2_ANDROID_ENV_ROOT R2_ANDROID_ENV_SCRIPT R2_ANDROID_JAVA_CANDIDATES R2_ANDROID_JAVA_HOME R2_ANDROID_NDK_DIR R2_ANDROID_PATH R2_ANDROID_PATHS
