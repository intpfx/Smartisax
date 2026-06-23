(function () {
  "use strict";

  const startedAt = performance.now();

  function report(payload) {
    payload.kind = "textboom-ppocrv6-onnx-smoke";
    payload.mode = "web";
    payload.boundary = "standalone benchmark APK; no TextBoom, ROM, or data mutation";
    payload.created_at = new Date().toISOString();
    SmartisaxOnnx.report(JSON.stringify(payload, null, 2));
  }

  function product(shape) {
    return shape.reduce((total, value) => total * value, 1);
  }

  async function runModel(provider, model) {
    const createStarted = performance.now();
    const session = await ort.InferenceSession.create(model.path, {
      executionProviders: [provider],
      graphOptimizationLevel: "all"
    });
    const createMs = performance.now() - createStarted;
    const inputName = session.inputNames[0];
    const data = new Float32Array(product(model.shape));
    const tensor = new ort.Tensor("float32", data, model.shape);
    const runStarted = performance.now();
    const outputs = await session.run({ [inputName]: tensor });
    const runMs = performance.now() - runStarted;
    const outputName = session.outputNames[0];
    const output = outputs[outputName];
    return {
      id: model.id,
      path: model.path,
      provider,
      input_name: inputName,
      input_shape: model.shape,
      output_name: outputName,
      first_output_shape: output.dims,
      first_output_type: output.type,
      session_create_ms: Math.round(createMs),
      run_ms: Math.round(runMs)
    };
  }

  async function runProvider(provider) {
    ort.env.wasm.numThreads = 1;
    ort.env.wasm.wasmPaths = new URL("ort/", location.href).href;
    const models = [
      { id: "PP-OCRv6_tiny_det", path: "models/PP-OCRv6_tiny_det.onnx", shape: [1, 3, 32, 32] },
      { id: "PP-OCRv6_tiny_rec", path: "models/PP-OCRv6_tiny_rec.onnx", shape: [1, 3, 48, 160] }
    ];
    const results = [];
    for (const model of models) {
      results.push(await runModel(provider, model));
    }
    return results;
  }

  async function main() {
    const candidates = ["wasm"];

    const attempts = [];
    for (const provider of candidates) {
      try {
        const models = await runProvider(provider);
        report({
          result: "WEB_ONNX_READY",
          engine: {
            id: "onnxruntime-web",
            version: ort.version || "unknown",
            provider,
            navigator_gpu: Boolean(navigator.gpu),
            user_agent: navigator.userAgent
          },
          attempts,
          models,
          latency_ms: Math.round(performance.now() - startedAt)
        });
        return;
      } catch (error) {
        attempts.push({
          provider,
          error: String(error && error.stack ? error.stack : error)
        });
      }
    }

    report({
      result: "WEB_ONNX_ERROR",
      engine: {
        id: "onnxruntime-web",
        version: ort && ort.version ? ort.version : "unknown",
        navigator_gpu: Boolean(navigator.gpu),
        user_agent: navigator.userAgent
      },
      attempts,
      latency_ms: Math.round(performance.now() - startedAt)
    });
  }

  main().catch((error) => {
    report({
      result: "WEB_ONNX_ERROR",
      error: String(error && error.stack ? error.stack : error),
      latency_ms: Math.round(performance.now() - startedAt)
    });
  });
})();
