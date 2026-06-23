#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${PPOCR_ONNX_VENV:-${ROOT_DIR}/third_party/_venvs/ppocr-onnx}"
PADDLE2ONNX="${PADDLE2ONNX:-${VENV_DIR}/bin/paddle2onnx}"
PYTHON_BIN="${PYTHON_BIN:-${VENV_DIR}/bin/python}"
MODEL_ROOT="${PPOCRV6_MODEL_ROOT:-${ROOT_DIR}/third_party/_downloads/ppocr-runtime/models/extracted}"
TAR_ROOT="${PPOCRV6_TAR_ROOT:-${ROOT_DIR}/third_party/_downloads/ppocr-runtime/models/tars}"
OUT_ROOT="${PPOCRV6_ONNX_OUT:-${ROOT_DIR}/hard-rom/build/ppocr-runtime/onnx}"
OPSET_VERSION="${PPOCRV6_ONNX_OPSET:-17}"

MODELS=(
  "PP-OCRv6_tiny_det_infer:PP-OCRv6_tiny_det"
  "PP-OCRv6_tiny_rec_infer:PP-OCRv6_tiny_rec"
  "PP-OCRv6_small_det_infer:PP-OCRv6_small_det"
  "PP-OCRv6_small_rec_infer:PP-OCRv6_small_rec"
)

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

need_executable "$PADDLE2ONNX"
need_executable "$PYTHON_BIN"

mkdir -p "$OUT_ROOT"

MODEL_PATHS=()
{
  echo "kind=ppocrv6-onnx-conversion"
  echo "opset_version=${OPSET_VERSION}"
  echo "model_root=${MODEL_ROOT}"
  echo "out_root=${OUT_ROOT}"
  echo "converted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "[tool_versions]"
  "$PYTHON_BIN" - <<'PY'
import importlib.metadata as metadata

for package in ("paddlepaddle", "paddle2onnx", "onnx", "onnxruntime", "PyYAML"):
    print(f"{package}=={metadata.version(package)}")
PY
  echo
  echo "[input_tars]"
  find "$TAR_ROOT" -maxdepth 1 -type f -name 'PP-OCRv6_*_infer.tar' -print0 \
    | sort -z \
    | xargs -0 shasum -a 256
} > "${OUT_ROOT}/conversion-manifest.txt"

for entry in "${MODELS[@]}"; do
  IFS=: read -r archive_name model_name <<< "$entry"
  src_dir="${MODEL_ROOT}/${archive_name}/${archive_name}"
  out_dir="${OUT_ROOT}/${model_name}"
  out_model="${out_dir}/model.onnx"
  need_file "${src_dir}/inference.json"
  need_file "${src_dir}/inference.pdiparams"
  need_file "${src_dir}/inference.yml"
  mkdir -p "$out_dir"
  cp "${src_dir}/inference.yml" "${out_dir}/inference.yml"
  echo "Converting ${archive_name} -> ${out_model}"
  "$PADDLE2ONNX" \
    --model_dir "$src_dir" \
    --model_filename inference.json \
    --params_filename inference.pdiparams \
    --save_file "$out_model" \
    --opset_version "$OPSET_VERSION" \
    --enable_onnx_checker True \
    --optimize_tool None 2>&1 | tee "${out_dir}/convert.log"
  MODEL_PATHS+=("$out_model")
done

"$PYTHON_BIN" "${ROOT_DIR}/tools/r2-ppocrv6-onnx-inspect.py" \
  --output "${OUT_ROOT}/inspect.json" \
  "${MODEL_PATHS[@]}"

{
  echo
  echo "[outputs]"
  find "$OUT_ROOT" -type f \
    \( -name '*.onnx' -o -name '*.yml' -o -name '*.log' -o -name '*.json' \) \
    -print0 | sort -z | xargs -0 shasum -a 256
} >> "${OUT_ROOT}/conversion-manifest.txt"

echo "PASS_PPOCRV6_ONNX_CONVERSION"
echo "Output: ${OUT_ROOT}"
