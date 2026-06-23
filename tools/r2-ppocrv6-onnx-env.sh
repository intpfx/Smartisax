#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UV="${UV:-uv}"
PYTHON_BIN="${PYTHON_BIN:-/opt/homebrew/bin/python3.12}"
VENV_DIR="${PPOCR_ONNX_VENV:-${ROOT_DIR}/third_party/_venvs/ppocr-onnx}"

die() {
  echo "error: $*" >&2
  exit 1
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

need_executable "$UV"
need_executable "$PYTHON_BIN"

"$UV" venv --python "$PYTHON_BIN" "$VENV_DIR"

"$UV" pip install --python "${VENV_DIR}/bin/python" \
  paddlepaddle==3.3.1 \
  paddle2onnx==2.1.0 \
  onnx==1.17.0 \
  onnxruntime==1.27.0 \
  PyYAML==6.0.3

"${VENV_DIR}/bin/python" - <<'PY'
import importlib.metadata as metadata

for package in ("paddlepaddle", "paddle2onnx", "onnx", "onnxruntime", "PyYAML"):
    print(f"{package}=={metadata.version(package)}")
PY

echo "PPOCR_ONNX_VENV=${VENV_DIR}"
