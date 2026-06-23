package com.smartisax.ocrbench;

import android.app.Activity;
import android.content.res.AssetManager;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.Bundle;
import android.os.Debug;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public final class MainActivity extends Activity {
    private static final String TAG = "SmartisaxOcrBench";
    private static final String EXTRA_IMAGE_PATH = "image_path";
    private static final String EXTRA_RESULT_PATH = "result_path";
    private static final String DEFAULT_IMAGE_NAME = "imageboom.jpg";
    private static final String MODEL_ASSET_ROOT = "ppocr-v2";
    private static final String MODEL_ID = "ch_ppocr_mobile_v2.0_slim_opt_for_cpu_v2_10_rc";
    private static final String DET_MODEL_ASSET = MODEL_ASSET_ROOT + "/models/ch_ppocr_mobile_v2.0_det_slim_opt.nb";
    private static final String CLS_MODEL_ASSET = MODEL_ASSET_ROOT + "/models/ch_ppocr_mobile_v2.0_cls_slim_opt.nb";
    private static final String REC_MODEL_ASSET = MODEL_ASSET_ROOT + "/models/ch_ppocr_mobile_v2.0_rec_slim_opt.nb";
    private static final String CONFIG_ASSET = MODEL_ASSET_ROOT + "/config.txt";
    private static final String LABEL_ASSET = MODEL_ASSET_ROOT + "/labels/ppocr_keys_v1.txt";
    private static final String CPU_POWER_MODE = "LITE_POWER_HIGH";
    private static final int CPU_THREAD_NUM = 4;
    private static final boolean NATIVE_READY;
    private static final String NATIVE_LOAD_ERROR;

    static {
        boolean ready = false;
        String error = null;
        try {
            System.loadLibrary("c++_shared");
            System.loadLibrary("paddle_light_api_shared");
            System.loadLibrary("smartisax_ppocr_bench");
            ready = true;
        } catch (Throwable throwable) {
            error = throwable.getClass().getSimpleName() + ": " + throwable.getMessage();
            Log.e(TAG, "native OCR runtime load failed", throwable);
        }
        NATIVE_READY = ready;
        NATIVE_LOAD_ERROR = error;
    }

    private static native String nativeRunPpOcr(
            String imagePath,
            String detModelPath,
            String clsModelPath,
            String recModelPath,
            String configPath,
            String labelPath,
            int cpuThreadNum,
            String cpuPowerMode
    );

    private TextView statusView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(createContentView());
        statusView.setText("Preparing OCR benchmark...");

        new Thread(new Runnable() {
            @Override
            public void run() {
                final String message = runBenchmark();
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        statusView.setText(message);
                    }
                });
            }
        }, "smartisax-ocrbench").start();
    }

    private ScrollView createContentView() {
        ScrollView scrollView = new ScrollView(this);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.START);
        int padding = dp(20);
        layout.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setText("Smartisax OCR Bench");
        title.setTextSize(22);
        title.setGravity(Gravity.START);
        layout.addView(title);

        statusView = new TextView(this);
        statusView.setTextSize(14);
        statusView.setPadding(0, dp(14), 0, 0);
        statusView.setTextIsSelectable(true);
        layout.addView(statusView);

        scrollView.addView(layout);
        return scrollView;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private String runBenchmark() {
        File appRoot = getExternalFilesDir(null);
        if (appRoot == null) {
            appRoot = getFilesDir();
        }

        File image = resolvePath(
                getIntent().getStringExtra(EXTRA_IMAGE_PATH),
                new File(new File(appRoot, "input"), DEFAULT_IMAGE_NAME)
        );
        File result = resolvePath(
                getIntent().getStringExtra(EXTRA_RESULT_PATH),
                new File(new File(appRoot, "results"), "last-result.json")
        );

        try {
            JSONObject payload = buildPredictionPayload(image);
            writeJson(result, payload);
            String message = "result=" + payload.optString("result") + "\n"
                    + "image=" + image.getAbsolutePath() + "\n"
                    + "output=" + result.getAbsolutePath();
            Log.i(TAG, message);
            return message;
        } catch (Exception error) {
            Log.e(TAG, "benchmark failed", error);
            return "result=ERROR\n" + error.getClass().getSimpleName() + ": " + error.getMessage();
        }
    }

    private File resolvePath(String path, File fallback) {
        if (path == null || path.trim().isEmpty()) {
            return fallback;
        }
        File file = new File(path.trim());
        if (file.isAbsolute()) {
            return file;
        }
        File appRoot = getExternalFilesDir(null);
        if (appRoot == null) {
            appRoot = getFilesDir();
        }
        return new File(appRoot, path.trim());
    }

    private JSONObject buildPredictionPayload(File image) throws JSONException, IOException {
        long started = SystemClock.elapsedRealtime();
        ImageProbe probe = probeImage(image);
        JSONObject nativeResult = runNativeIfReady(image, probe);
        long elapsedMs = SystemClock.elapsedRealtime() - started;
        JSONArray ppocr = nativeResult.optJSONArray("lines");
        if (ppocr == null) {
            ppocr = new JSONArray();
        }
        String status = nativeResult.optString("status", probe.status);
        double nativeTotalMs = nativeResult.optDouble("total_ms", elapsedMs);

        JSONObject sample = new JSONObject();
        sample.put("id", imageId(image));
        sample.put("source_image", image.getAbsolutePath());
        sample.put("status", status);
        sample.put("image_sha256", probe.sha256 == null ? JSONObject.NULL : probe.sha256);
        sample.put("image_size", imageSizeArray(
                nativeResult.optInt("image_width", probe.width),
                nativeResult.optInt("image_height", probe.height)
        ));
        sample.put("latency_ms", Math.round(nativeTotalMs));
        sample.put("peak_pss_kb", currentPssKb());
        sample.put("ppocr", ppocr);
        sample.put("native_metrics", nativeMetrics(nativeResult));
        if (probe.error != null) {
            sample.put("error", probe.error);
        }
        if (nativeResult.has("error")) {
            sample.put("native_error", nativeResult.optString("error"));
        }

        JSONObject engine = new JSONObject();
        engine.put("id", "smartisax-paddle-lite-ppocr-v2-mobile-slim");
        engine.put("version", "0.2.0");
        engine.put("runtime", "android-native-paddle-lite");
        engine.put("status", NATIVE_READY ? "native-ready" : "native-load-error");
        if (NATIVE_LOAD_ERROR != null) {
            engine.put("load_error", NATIVE_LOAD_ERROR);
        }

        JSONObject model = new JSONObject();
        model.put("id", MODEL_ID);
        model.put("family", "PP-OCR mobile v2 slim");
        model.put("det", DET_MODEL_ASSET);
        model.put("cls", CLS_MODEL_ASSET);
        model.put("rec", REC_MODEL_ASSET);
        model.put("labels", LABEL_ASSET);
        model.put("config", CONFIG_ASSET);
        model.put("cpu_threads", CPU_THREAD_NUM);
        model.put("cpu_power_mode", CPU_POWER_MODE);

        JSONObject device = new JSONObject();
        device.put("manufacturer", Build.MANUFACTURER);
        device.put("brand", Build.BRAND);
        device.put("model", Build.MODEL);
        device.put("device", Build.DEVICE);
        device.put("sdk_int", Build.VERSION.SDK_INT);

        JSONArray samples = new JSONArray();
        samples.put(sample);

        JSONObject payload = new JSONObject();
        payload.put("generated_at", utcNow());
        payload.put("kind", "textboom-ppocr-runtime-prediction");
        payload.put("boundary", "standalone benchmark APK; no TextBoom, ROM, or data mutation");
        payload.put("engine", engine);
        payload.put("model", model);
        payload.put("device", device);
        payload.put("samples", samples);
        payload.put("result", status);
        return payload;
    }

    private JSONObject runNativeIfReady(File image, ImageProbe probe) throws JSONException, IOException {
        if (!"IMAGE_READY".equals(probe.status)) {
            JSONObject result = new JSONObject();
            result.put("status", probe.status);
            if (probe.error != null) {
                result.put("error", probe.error);
            }
            return result;
        }
        if (!NATIVE_READY) {
            JSONObject result = new JSONObject();
            result.put("status", "NATIVE_LOAD_ERROR");
            result.put("error", NATIVE_LOAD_ERROR == null ? "unknown native load error" : NATIVE_LOAD_ERROR);
            return result;
        }

        ModelFiles model = ensureModelFiles();
        String raw = nativeRunPpOcr(
                image.getAbsolutePath(),
                model.det.getAbsolutePath(),
                model.cls.getAbsolutePath(),
                model.rec.getAbsolutePath(),
                model.config.getAbsolutePath(),
                model.labels.getAbsolutePath(),
                CPU_THREAD_NUM,
                CPU_POWER_MODE
        );
        return new JSONObject(raw);
    }

    private JSONObject nativeMetrics(JSONObject nativeResult) throws JSONException {
        JSONObject metrics = new JSONObject();
        metrics.put("det_ms", nativeResult.optDouble("det_ms", 0.0));
        metrics.put("rec_ms", nativeResult.optDouble("rec_ms", 0.0));
        metrics.put("total_ms", nativeResult.optDouble("total_ms", 0.0));
        metrics.put("line_count", nativeResult.optJSONArray("lines") == null ? 0 : nativeResult.optJSONArray("lines").length());
        return metrics;
    }

    private JSONArray imageSizeArray(int width, int height) {
        JSONArray imageSize = new JSONArray();
        imageSize.put(width);
        imageSize.put(height);
        return imageSize;
    }

    private ModelFiles ensureModelFiles() throws IOException {
        File root = new File(getFilesDir(), MODEL_ASSET_ROOT);
        File det = ensureAssetFile(DET_MODEL_ASSET, new File(root, "models/ch_ppocr_mobile_v2.0_det_slim_opt.nb"));
        File cls = ensureAssetFile(CLS_MODEL_ASSET, new File(root, "models/ch_ppocr_mobile_v2.0_cls_slim_opt.nb"));
        File rec = ensureAssetFile(REC_MODEL_ASSET, new File(root, "models/ch_ppocr_mobile_v2.0_rec_slim_opt.nb"));
        File config = ensureAssetFile(CONFIG_ASSET, new File(root, "config.txt"));
        File labels = ensureAssetFile(LABEL_ASSET, new File(root, "labels/ppocr_keys_v1.txt"));
        return new ModelFiles(det, cls, rec, config, labels);
    }

    private File ensureAssetFile(String assetPath, File target) throws IOException {
        if (target.isFile() && target.length() > 0) {
            return target;
        }
        File parent = target.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("failed to create " + parent);
        }
        AssetManager assets = getAssets();
        InputStream input = assets.open(assetPath);
        try {
            OutputStream output = new FileOutputStream(target, false);
            try {
                byte[] buffer = new byte[16384];
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

    private ImageProbe probeImage(File image) {
        if (!image.isFile()) {
            return ImageProbe.error("IMAGE_MISSING", 0, 0, null, "missing file");
        }
        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(image.getAbsolutePath(), options);
            if (options.outWidth <= 0 || options.outHeight <= 0) {
                return ImageProbe.error("IMAGE_DECODE_FAILED", 0, 0, sha256(image), "BitmapFactory returned empty bounds");
            }
            return new ImageProbe("IMAGE_READY", options.outWidth, options.outHeight, sha256(image), null);
        } catch (Exception error) {
            return ImageProbe.error("IMAGE_PROBE_ERROR", 0, 0, null, error.getClass().getSimpleName() + ": " + error.getMessage());
        }
    }

    private int currentPssKb() {
        Debug.MemoryInfo memoryInfo = new Debug.MemoryInfo();
        Debug.getMemoryInfo(memoryInfo);
        return memoryInfo.getTotalPss();
    }

    private String imageId(File image) {
        String name = image.getName();
        int dot = name.lastIndexOf('.');
        if (dot > 0) {
            return name.substring(0, dot);
        }
        return name.isEmpty() ? "sample" : name;
    }

    private void writeJson(File result, JSONObject payload) throws IOException {
        File parent = result.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("failed to create " + parent);
        }
        FileWriter writer = new FileWriter(result, false);
        try {
            writer.write(payload.toString(2));
            writer.write("\n");
        } catch (JSONException error) {
            throw new IOException("failed to serialize JSON", error);
        } finally {
            writer.close();
        }
    }

    private String sha256(File file) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        FileInputStream input = new FileInputStream(file);
        try {
            byte[] buffer = new byte[8192];
            while (true) {
                int read = input.read(buffer);
                if (read < 0) {
                    break;
                }
                digest.update(buffer, 0, read);
            }
        } finally {
            input.close();
        }
        byte[] bytes = digest.digest();
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            builder.append(String.format(Locale.US, "%02x", value & 0xff));
        }
        return builder.toString();
    }

    private String utcNow() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    private static final class ModelFiles {
        final File det;
        final File cls;
        final File rec;
        final File config;
        final File labels;

        ModelFiles(File det, File cls, File rec, File config, File labels) {
            this.det = det;
            this.cls = cls;
            this.rec = rec;
            this.config = config;
            this.labels = labels;
        }
    }

    private static final class ImageProbe {
        final String status;
        final int width;
        final int height;
        final String sha256;
        final String error;

        ImageProbe(String status, int width, int height, String sha256, String error) {
            this.status = status;
            this.width = width;
            this.height = height;
            this.sha256 = sha256;
            this.error = error;
        }

        static ImageProbe error(String status, int width, int height, String sha256, String error) {
            return new ImageProbe(status, width, height, sha256, error);
        }
    }
}
