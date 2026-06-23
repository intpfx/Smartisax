package com.smartisax.ocrbench.onnx;

import ai.onnxruntime.NodeInfo;
import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OnnxValue;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;
import ai.onnxruntime.TensorInfo;
import ai.onnxruntime.ValueInfo;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Debug;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.FloatBuffer;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class MainActivity extends Activity {
    private static final String TAG = "SmartisaxOnnxSmoke";
    private static final String EXTRA_MODE = "mode";
    private static final String EXTRA_RESULT_PATH = "result_path";
    private static final String MODE_NATIVE = "native";
    private static final String MODE_WEB = "web";
    private static final String ASSET_ORIGIN = "https://smartisax.local/assets/web/";
    private static final String DET_ASSET = "onnx/models/PP-OCRv6_tiny_det.onnx";
    private static final String REC_ASSET = "onnx/models/PP-OCRv6_tiny_rec.onnx";

    private TextView statusView;
    private File resultFile;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        statusView = new TextView(this);
        statusView.setGravity(Gravity.CENTER);
        statusView.setTextSize(14);
        statusView.setText("Smartisax ONNX smoke starting");
        setContentView(statusView);

        resultFile = resolveResultFile();
        String mode = getIntent().getStringExtra(EXTRA_MODE);
        if (MODE_WEB.equals(mode)) {
            runWebSmoke();
        } else {
            runNativeSmoke();
        }
    }

    private File resolveResultFile() {
        String extra = getIntent().getStringExtra(EXTRA_RESULT_PATH);
        if (extra != null && extra.trim().length() > 0) {
            return new File(extra.trim());
        }
        File root = getExternalFilesDir(null);
        if (root == null) {
            root = getFilesDir();
        }
        return new File(new File(root, "results"), "last-result.json");
    }

    private void runNativeSmoke() {
        statusView.setText("Native ONNX smoke running");
        new Thread(new Runnable() {
            @Override
            public void run() {
                JSONObject payload;
                try {
                    payload = buildNativePayload();
                } catch (Throwable error) {
                    payload = errorPayload("native", "NATIVE_ONNX_ERROR", error);
                }
                writeResultAndShow(payload);
            }
        }, "native-onnx-smoke").start();
    }

    private JSONObject buildNativePayload() throws Exception {
        long started = SystemClock.elapsedRealtime();
        JSONArray models = new JSONArray();
        OrtEnvironment environment = OrtEnvironment.getEnvironment();
        models.put(runNativeModel(environment, "PP-OCRv6_tiny_det", DET_ASSET, new long[]{1, 3, 32, 32}));
        models.put(runNativeModel(environment, "PP-OCRv6_tiny_rec", REC_ASSET, new long[]{1, 3, 48, 160}));

        JSONObject engine = new JSONObject();
        engine.put("id", "onnxruntime-android");
        engine.put("version", environment.getVersion());
        engine.put("providers", OrtEnvironment.getAvailableProviders().toString());

        JSONObject payload = basePayload("native");
        payload.put("result", "NATIVE_ONNX_READY");
        payload.put("engine", engine);
        payload.put("models", models);
        payload.put("latency_ms", SystemClock.elapsedRealtime() - started);
        payload.put("peak_pss_kb", currentPssKb());
        return payload;
    }

    private JSONObject runNativeModel(
            OrtEnvironment environment,
            String id,
            String assetPath,
            long[] inputShape
    ) throws Exception {
        File modelFile = ensureAssetFile(assetPath, new File(new File(getFilesDir(), "onnx"), id + ".onnx"));
        long createStarted = SystemClock.elapsedRealtime();
        OrtSession.SessionOptions options = new OrtSession.SessionOptions();
        try {
            OrtSession session = environment.createSession(modelFile.getAbsolutePath(), options);
            try {
                long createMs = SystemClock.elapsedRealtime() - createStarted;
                String inputName = firstName(session.getInputNames());
                long runStarted = SystemClock.elapsedRealtime();
                OnnxTensor input = OnnxTensor.createTensor(
                        environment,
                        FloatBuffer.wrap(new float[elementCount(inputShape)]),
                        inputShape
                );
                try {
                    Map<String, OnnxTensor> feeds = new HashMap<>();
                    feeds.put(inputName, input);
                    OrtSession.Result result = session.run(feeds);
                    try {
                        long runMs = SystemClock.elapsedRealtime() - runStarted;
                        OnnxValue output = result.get(0);
                        TensorInfo outputInfo = tensorInfo(output.getInfo());
                        JSONObject model = new JSONObject();
                        model.put("id", id);
                        model.put("asset", assetPath);
                        model.put("file_bytes", modelFile.length());
                        model.put("input_name", inputName);
                        model.put("input_shape", shapeJson(inputShape));
                        model.put("input_info", nodeInfoJson(session.getInputInfo()));
                        model.put("output_info", nodeInfoJson(session.getOutputInfo()));
                        model.put("first_output_shape", shapeJson(outputInfo.getShape()));
                        model.put("first_output_type", outputInfo.type.toString());
                        model.put("session_create_ms", createMs);
                        model.put("run_ms", runMs);
                        return model;
                    } finally {
                        result.close();
                    }
                } finally {
                    input.close();
                }
            } finally {
                session.close();
                options.close();
            }
        } catch (OrtException error) {
            options.close();
            throw error;
        }
    }

    private String firstName(Set<String> names) {
        Iterator<String> iterator = names.iterator();
        if (!iterator.hasNext()) {
            throw new IllegalStateException("model has no input names");
        }
        return iterator.next();
    }

    private int elementCount(long[] shape) {
        long total = 1;
        for (long value : shape) {
            total *= value;
        }
        if (total > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("shape too large");
        }
        return (int) total;
    }

    private TensorInfo tensorInfo(ValueInfo info) {
        if (!(info instanceof TensorInfo)) {
            throw new IllegalStateException("expected tensor output, got " + info);
        }
        return (TensorInfo) info;
    }

    private JSONObject nodeInfoJson(Map<String, NodeInfo> items) throws JSONException {
        JSONObject result = new JSONObject();
        for (Map.Entry<String, NodeInfo> entry : items.entrySet()) {
            ValueInfo info = entry.getValue().getInfo();
            if (info instanceof TensorInfo) {
                TensorInfo tensor = (TensorInfo) info;
                JSONObject item = new JSONObject();
                item.put("type", tensor.type.toString());
                item.put("shape", shapeJson(tensor.getShape()));
                result.put(entry.getKey(), item);
            } else {
                result.put(entry.getKey(), String.valueOf(info));
            }
        }
        return result;
    }

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    private void runWebSmoke() {
        statusView.setText("WebView ONNX smoke running");
        WebView webView = new WebView(this);
        setContentView(webView);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccess(false);
        if (Build.VERSION.SDK_INT >= 26) {
            settings.setSafeBrowsingEnabled(false);
        }
        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new AssetClient());
        webView.addJavascriptInterface(new Bridge(), "SmartisaxOnnx");
        try {
            String html = readAssetText("web/index.html");
            webView.loadDataWithBaseURL(ASSET_ORIGIN, html, "text/html", "UTF-8", null);
        } catch (Throwable error) {
            writeResultAndShow(errorPayload("web", "WEB_ONNX_ERROR", error));
        }
    }

    private final class Bridge {
        @JavascriptInterface
        public void report(String json) {
            try {
                JSONObject payload = new JSONObject(json);
                writeResultAndShow(payload);
            } catch (Throwable error) {
                writeResultAndShow(errorPayload("web", "WEB_ONNX_REPORT_ERROR", error));
            }
        }
    }

    private final class AssetClient extends WebViewClient {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            return intercept(request.getUrl());
        }

        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
            return intercept(Uri.parse(url));
        }

        private WebResourceResponse intercept(Uri uri) {
            String url = uri.toString();
            if (!url.startsWith(ASSET_ORIGIN)) {
                return null;
            }
            String assetPath = "web/" + url.substring(ASSET_ORIGIN.length());
            try {
                return new WebResourceResponse(mimeType(assetPath), "UTF-8", getAssets().open(assetPath));
            } catch (IOException error) {
                Log.e(TAG, "asset intercept failed: " + assetPath, error);
                return null;
            }
        }
    }

    private String mimeType(String path) {
        if (path.endsWith(".html")) {
            return "text/html";
        }
        if (path.endsWith(".js") || path.endsWith(".mjs")) {
            return "application/javascript";
        }
        if (path.endsWith(".wasm")) {
            return "application/wasm";
        }
        if (path.endsWith(".onnx")) {
            return "application/octet-stream";
        }
        if (path.endsWith(".json")) {
            return "application/json";
        }
        return "text/plain";
    }

    private JSONObject basePayload(String mode) throws JSONException {
        JSONObject device = new JSONObject();
        device.put("manufacturer", Build.MANUFACTURER);
        device.put("model", Build.MODEL);
        device.put("sdk", Build.VERSION.SDK_INT);
        device.put("release", Build.VERSION.RELEASE);

        JSONObject payload = new JSONObject();
        payload.put("kind", "textboom-ppocrv6-onnx-smoke");
        payload.put("mode", mode);
        payload.put("boundary", "standalone benchmark APK; no TextBoom, ROM, or data mutation");
        payload.put("created_at", now());
        payload.put("device", device);
        return payload;
    }

    private JSONObject errorPayload(String mode, String status, Throwable error) {
        try {
            JSONObject payload = basePayload(mode);
            payload.put("result", status);
            payload.put("error", error.getClass().getSimpleName() + ": " + error.getMessage());
            payload.put("peak_pss_kb", currentPssKb());
            return payload;
        } catch (JSONException jsonError) {
            throw new IllegalStateException(jsonError);
        }
    }

    private File ensureAssetFile(String assetPath, File target) throws IOException {
        if (target.isFile() && target.length() > 0) {
            return target;
        }
        File parent = target.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("failed to create " + parent);
        }
        InputStream input = getAssets().open(assetPath);
        try {
            OutputStream output = new FileOutputStream(target, false);
            try {
                byte[] buffer = new byte[1024 * 1024];
                while (true) {
                    int read = input.read(buffer);
                    if (read < 0) {
                        break;
                    }
                    output.write(buffer, 0, read);
                }
            } finally {
                output.close();
            }
        } finally {
            input.close();
        }
        return target;
    }

    private String readAssetText(String assetPath) throws IOException {
        AssetManager assets = getAssets();
        InputStream input = assets.open(assetPath);
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            while (true) {
                int read = input.read(buffer);
                if (read < 0) {
                    break;
                }
                output.write(buffer, 0, read);
            }
            return output.toString("UTF-8");
        } finally {
            input.close();
        }
    }

    private JSONArray shapeJson(long[] shape) {
        JSONArray result = new JSONArray();
        for (long value : shape) {
            result.put(value);
        }
        return result;
    }

    private long currentPssKb() {
        Debug.MemoryInfo info = new Debug.MemoryInfo();
        Debug.getMemoryInfo(info);
        return info.getTotalPss();
    }

    private void writeResultAndShow(final JSONObject payload) {
        try {
            File parent = resultFile.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                throw new IOException("failed to create " + parent);
            }
            FileWriter writer = new FileWriter(resultFile, false);
            try {
                writer.write(payload.toString(2));
                writer.write("\n");
            } finally {
                writer.close();
            }
        } catch (Throwable error) {
            Log.e(TAG, "failed to write result", error);
        }
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                statusView.setText(payload.optString("result", "DONE") + "\n" + resultFile.getAbsolutePath());
            }
        });
    }

    private String now() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US);
        return format.format(new Date());
    }
}
