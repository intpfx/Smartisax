#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import onnx
import onnxruntime as ort


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def shape_to_json(shape: list[Any]) -> list[Any]:
    return [str(item) if item is not None else None for item in shape]


def inspect_model(path: Path) -> dict[str, Any]:
    model = onnx.load(str(path))
    onnx.checker.check_model(model)

    options = ort.SessionOptions()
    options.log_severity_level = 3
    session = ort.InferenceSession(
        str(path),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )

    return {
        "path": str(path),
        "sha256": sha256(path),
        "size_bytes": path.stat().st_size,
        "opsets": [
            {"domain": opset.domain, "version": opset.version}
            for opset in model.opset_import
        ],
        "node_count": len(model.graph.node),
        "inputs": [
            {"name": item.name, "type": item.type, "shape": shape_to_json(item.shape)}
            for item in session.get_inputs()
        ],
        "outputs": [
            {"name": item.name, "type": item.type, "shape": shape_to_json(item.shape)}
            for item in session.get_outputs()
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("models", nargs="+")
    args = parser.parse_args()

    models = [inspect_model(Path(model)) for model in args.models]
    payload = {
        "kind": "ppocrv6-onnx-inspect",
        "onnxruntime_providers": ort.get_available_providers(),
        "models": models,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for model in models:
        print(
            "MODEL",
            model["path"],
            "size",
            model["size_bytes"],
            "nodes",
            model["node_count"],
        )
        for item in model["inputs"]:
            print("  input", item["name"], item["type"], item["shape"])
        for item in model["outputs"]:
            print("  output", item["name"], item["type"], item["shape"])
    print("PASS_PPOCRV6_ONNX_INSPECT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
