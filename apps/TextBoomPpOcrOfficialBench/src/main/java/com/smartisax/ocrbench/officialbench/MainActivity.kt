package com.smartisax.ocrbench.officialbench

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.model.OCRBox
import com.paddle.ocr.model.OCRRunResult
import com.paddle.ocr.util.OpenCVUtils
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : Activity() {
    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var statusView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(createContentView())
        statusView.text = "Preparing official PP-OCR benchmark..."

        activityScope.launch {
            val message = try {
                withContext(Dispatchers.IO) {
                    runBenchmark()
                }
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                Log.e(TAG, "benchmark failed", error)
                "result=ERROR\n${error.javaClass.simpleName}: ${error.message}"
            }
            statusView.text = message
        }
    }

    override fun onDestroy() {
        activityScope.cancel()
        super.onDestroy()
    }

    private fun createContentView(): ScrollView {
        val scrollView = ScrollView(this)
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        layout.gravity = Gravity.START
        val padding = dp(20)
        layout.setPadding(padding, padding, padding, padding)

        val title = TextView(this)
        title.text = "Smartisax OCR Official Bench"
        title.textSize = 22f
        title.gravity = Gravity.START
        layout.addView(title)

        statusView = TextView(this)
        statusView.textSize = 14f
        statusView.setPadding(0, dp(14), 0, 0)
        statusView.setTextIsSelectable(true)
        layout.addView(statusView)

        scrollView.addView(layout)
        return scrollView
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private suspend fun runBenchmark(): String {
        val appRoot = getExternalFilesDir(null) ?: filesDir
        val image = resolvePath(
            intent.getStringExtra(EXTRA_IMAGE_PATH),
            File(File(appRoot, "input"), DEFAULT_IMAGE_NAME),
        )
        val result = resolvePath(
            intent.getStringExtra(EXTRA_RESULT_PATH),
            File(File(appRoot, "results"), "last-result.json"),
        )

        val payload = buildPredictionPayload(image)
        writeJson(result, payload)

        val message = "result=${payload.optString("result")}\n" +
            "image=${image.absolutePath}\n" +
            "output=${result.absolutePath}"
        Log.i(TAG, message)
        return message
    }

    private fun resolvePath(path: String?, fallback: File): File {
        if (path.isNullOrBlank()) return fallback
        val file = File(path.trim())
        if (file.isAbsolute) return file
        val appRoot = getExternalFilesDir(null) ?: filesDir
        return File(appRoot, path.trim())
    }

    private suspend fun buildPredictionPayload(image: File): JSONObject {
        val started = SystemClock.elapsedRealtime()
        val probe = probeImage(image)
        var status = probe.status
        var runResult: OCRRunResult? = null
        var runError: String? = null
        var coldLoadMs = 0L

        if (status == "IMAGE_READY") {
            var ocr: PaddleOCR? = null
            try {
                if (!OpenCVUtils.init(this)) {
                    throw IllegalStateException("Failed to initialize OpenCV native library")
                }
                ocr = PaddleOCR.create(
                    context = this,
                    config = OCR_CONFIG,
                    engineConfig = EngineConfig(numThreads = CPU_THREAD_NUM),
                    detModelAssetPath = DET_MODEL_ASSET,
                    recModelAssetPath = REC_MODEL_ASSET,
                    recConfigAssetPath = REC_CONFIG_ASSET,
                )
                coldLoadMs = ocr.coldLoadTimeMs
                runResult = ocr.recognize(image.readBytes())
                status = "OK"
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                status = "OCR_ERROR"
                runError = "${error.javaClass.simpleName}: ${error.message}"
                Log.e(TAG, "official OCR runtime failed", error)
            } finally {
                ocr?.release()
            }
        }

        val elapsedMs = SystemClock.elapsedRealtime() - started
        val sample = JSONObject()
            .put("id", imageId(image))
            .put("source_image", image.absolutePath)
            .put("status", status)
            .put("image_sha256", probe.sha256 ?: JSONObject.NULL)
            .put("image_size", imageSizeArray(probe.width, probe.height))
            .put("latency_ms", runResult?.totalTimeMs ?: elapsedMs)
            .put("wall_elapsed_ms", elapsedMs)
            .put("cold_load_ms", coldLoadMs)
            .put("peak_pss_kb", currentPssKb())
            .put("ppocr", ppocrLines(runResult))
            .put("native_metrics", nativeMetrics(runResult, coldLoadMs))

        probe.error?.let { sample.put("error", it) }
        runError?.let { sample.put("runtime_error", it) }

        val samples = JSONArray().put(sample)

        return JSONObject()
            .put("generated_at", utcNow())
            .put("kind", "textboom-ppocr-official-runtime-prediction")
            .put("boundary", "standalone official ppocr-sdk benchmark APK; no TextBoom, ROM, or data mutation")
            .put("engine", engineJson())
            .put("model", modelJson())
            .put("device", deviceJson())
            .put("samples", samples)
            .put("result", status)
    }

    private fun nativeMetrics(runResult: OCRRunResult?, coldLoadMs: Long): JSONObject {
        if (runResult == null) {
            return JSONObject()
                .put("cold_load_ms", coldLoadMs)
                .put("line_count", 0)
        }
        return JSONObject()
            .put("cold_load_ms", coldLoadMs)
            .put("det_ms", runResult.detectionTimeMs)
            .put("det_preprocess_ms", runResult.detPreprocessMs)
            .put("det_inference_ms", runResult.detInferenceMs)
            .put("det_postprocess_ms", runResult.detPostprocessMs)
            .put("rec_ms", runResult.recognitionTimeMs)
            .put("rec_preprocess_ms", runResult.recPreprocessMs)
            .put("rec_inference_ms", runResult.recInferenceMs)
            .put("rec_postprocess_ms", runResult.recPostprocessMs)
            .put("pipeline_overhead_ms", runResult.pipelineOverheadMs)
            .put("total_ms", runResult.totalTimeMs)
            .put("line_count", runResult.lineCount)
            .put("det_input_shape", intArrayJson(runResult.detInputShape))
            .put("rec_input_shapes", intArrayListJson(runResult.recInputShapes))
            .put("per_line_rec_ms", longArrayJson(runResult.perLineRecMs))
    }

    private fun ppocrLines(runResult: OCRRunResult?): JSONArray {
        val lines = JSONArray()
        runResult?.results?.forEachIndexed { index, result ->
            lines.put(
                JSONObject()
                    .put("index", index)
                    .put("text", result.text)
                    .put("confidence", result.confidence.toDouble())
                    .put("box", boxJson(result.box)),
            )
        }
        return lines
    }

    private fun boxJson(box: OCRBox): JSONObject {
        val points = JSONArray()
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY
        box.points.forEach { point ->
            points.put(JSONArray().put(point.x.toDouble()).put(point.y.toDouble()))
            minX = minOf(minX, point.x)
            minY = minOf(minY, point.y)
            maxX = maxOf(maxX, point.x)
            maxY = maxOf(maxY, point.y)
        }
        return JSONObject()
            .put("points", points)
            .put("rect", JSONArray().put(minX.toDouble()).put(minY.toDouble()).put(maxX.toDouble()).put(maxY.toDouble()))
    }

    private fun engineJson(): JSONObject = JSONObject()
        .put("id", "official-paddleocr-ppocr-android")
        .put("version", "0.1.1")
        .put("runtime", "onnxruntime-android")
        .put("onnxruntime_android_version", ORT_ANDROID_VERSION)
        .put("opencv_version", OPENCV_VERSION)
        .put("cpu_threads", CPU_THREAD_NUM)
        .put("rec_batch_size", OCR_CONFIG.recBatchSize)

    private fun modelJson(): JSONObject = JSONObject()
        .put("id", MODEL_ID)
        .put("family", "PP-OCRv6 small")
        .put("det", DET_MODEL_ASSET)
        .put("rec", REC_MODEL_ASSET)
        .put("rec_config", REC_CONFIG_ASSET)
        .put("det_limit_side_len", OCR_CONFIG.detLimitSideLen)
        .put("det_limit_type", OCR_CONFIG.detLimitType)
        .put("det_thresh", OCR_CONFIG.detThresh.toDouble())
        .put("det_box_thresh", OCR_CONFIG.detBoxThresh.toDouble())
        .put("det_unclip_ratio", OCR_CONFIG.detUnclipRatio.toDouble())
        .put("rec_score_thresh", OCR_CONFIG.recScoreThresh.toDouble())

    private fun deviceJson(): JSONObject = JSONObject()
        .put("manufacturer", Build.MANUFACTURER)
        .put("brand", Build.BRAND)
        .put("model", Build.MODEL)
        .put("device", Build.DEVICE)
        .put("sdk_int", Build.VERSION.SDK_INT)
        .put("android_release", Build.VERSION.RELEASE)

    private fun probeImage(image: File): ImageProbe {
        if (!image.isFile) {
            return ImageProbe.error("IMAGE_MISSING", 0, 0, null, "missing file")
        }
        return try {
            val options = BitmapFactory.Options()
            options.inJustDecodeBounds = true
            BitmapFactory.decodeFile(image.absolutePath, options)
            if (options.outWidth <= 0 || options.outHeight <= 0) {
                ImageProbe.error("IMAGE_DECODE_FAILED", 0, 0, sha256(image), "BitmapFactory returned empty bounds")
            } else {
                ImageProbe("IMAGE_READY", options.outWidth, options.outHeight, sha256(image), null)
            }
        } catch (error: Throwable) {
            ImageProbe.error("IMAGE_PROBE_ERROR", 0, 0, null, "${error.javaClass.simpleName}: ${error.message}")
        }
    }

    private fun currentPssKb(): Int {
        val memoryInfo = Debug.MemoryInfo()
        Debug.getMemoryInfo(memoryInfo)
        return memoryInfo.totalPss
    }

    private fun imageSizeArray(width: Int, height: Int): JSONArray = JSONArray().put(width).put(height)

    private fun imageId(image: File): String {
        val name = image.name
        val dot = name.lastIndexOf('.')
        return when {
            dot > 0 -> name.substring(0, dot)
            name.isNotEmpty() -> name
            else -> "sample"
        }
    }

    private fun writeJson(result: File, payload: JSONObject) {
        val parent = result.parentFile
        if (parent != null && !parent.isDirectory && !parent.mkdirs()) {
            throw IllegalStateException("failed to create $parent")
        }
        result.writeText(payload.toString(2) + "\n", Charsets.UTF_8)
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(Locale.US, it.toInt() and 0xff) }
    }

    private fun utcNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private fun intArrayJson(values: List<Int>): JSONArray {
        val array = JSONArray()
        values.forEach { array.put(it) }
        return array
    }

    private fun longArrayJson(values: List<Long>): JSONArray {
        val array = JSONArray()
        values.forEach { array.put(it) }
        return array
    }

    private fun intArrayListJson(values: List<List<Int>>): JSONArray {
        val array = JSONArray()
        values.forEach { array.put(intArrayJson(it)) }
        return array
    }

    private data class ImageProbe(
        val status: String,
        val width: Int,
        val height: Int,
        val sha256: String?,
        val error: String?,
    ) {
        companion object {
            fun error(status: String, width: Int, height: Int, sha256: String?, error: String): ImageProbe {
                return ImageProbe(status, width, height, sha256, error)
            }
        }
    }

    companion object {
        private const val TAG = "SmartisaxOcrOfficialBench"
        private const val EXTRA_IMAGE_PATH = "image_path"
        private const val EXTRA_RESULT_PATH = "result_path"
        private const val DEFAULT_IMAGE_NAME = "imageboom.jpg"
        private const val MODEL_ID = "PP-OCRv6_small"
        private const val DET_MODEL_ASSET = "models/det/inference.onnx"
        private const val REC_MODEL_ASSET = "models/rec/inference.onnx"
        private const val REC_CONFIG_ASSET = "models/rec/inference.yml"
        private const val ORT_ANDROID_VERSION = "1.21.1"
        private const val OPENCV_VERSION = "4.9.0-official-aar"
        private const val CPU_THREAD_NUM = 4

        private val OCR_CONFIG = PaddleOCRConfig(
            recScoreThresh = 0.0f,
            recBatchSize = 1,
        )
    }
}
