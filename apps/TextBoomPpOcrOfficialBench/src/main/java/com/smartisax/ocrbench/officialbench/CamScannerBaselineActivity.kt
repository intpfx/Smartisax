package com.smartisax.ocrbench.officialbench

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class CamScannerBaselineActivity : Activity() {
    private lateinit var statusView: TextView
    private var startedAtMs: Long = 0L
    private lateinit var imageFile: File
    private lateinit var resultFile: File
    private lateinit var sampleId: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(createContentView())
        statusView.text = "Preparing CamScanner baseline..."
        startBaseline()
    }

    private fun createContentView(): ScrollView {
        val scrollView = ScrollView(this)
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        layout.gravity = Gravity.START
        val padding = dp(20)
        layout.setPadding(padding, padding, padding, padding)

        val title = TextView(this)
        title.text = "Smartisax CsOcr Baseline"
        title.textSize = 22f
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

    private fun startBaseline() {
        try {
            val appRoot = getExternalFilesDir(null) ?: filesDir
            imageFile = resolvePath(
                intent.getStringExtra(EXTRA_IMAGE_PATH),
                File(File(appRoot, "input"), DEFAULT_IMAGE_NAME),
            )
            resultFile = resolvePath(
                intent.getStringExtra(EXTRA_RESULT_PATH),
                File(File(appRoot, "results"), "last-csocr-result.json"),
            )
            sampleId = intent.getStringExtra(EXTRA_SAMPLE_ID)?.trim().orEmpty().ifBlank {
                imageId(imageFile)
            }
            if (!imageFile.isFile) {
                writeAndShow(errorPayload("IMAGE_MISSING", "missing file: ${imageFile.absolutePath}", 0L))
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", imageFile)
            grantCamScannerUri(uri)
            val targetPackage = camScannerPackage()
            if (targetPackage == null) {
                writeAndShow(errorPayload("CAMSCANNER_MISSING", "CamScanner package is not installed", 0L))
                return
            }

            val ocrIntent = Intent(ACTION_OCR)
                .setPackage(targetPackage)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(EXTRA_APP_KEY, BuildConfig.CAMSCANNER_APP_KEY)
                .putExtra(EXTRA_OCR_LANGUAGE, intent.getIntExtra(EXTRA_OCR_LANGUAGE, DEFAULT_OCR_LANGUAGE))
                .putExtra(EXTRA_OCR_SHOW_PROGRESS, intent.getBooleanExtra(EXTRA_OCR_SHOW_PROGRESS, false))
                .putExtra(EXTRA_OCR_SHOW_STATUSBAR, intent.getBooleanExtra(EXTRA_OCR_SHOW_STATUSBAR, true))

            startedAtMs = SystemClock.elapsedRealtime()
            statusView.text = "Starting CamScanner OCR for $sampleId..."
            startActivityForResult(ocrIntent, REQ_OCR)
        } catch (error: ActivityNotFoundException) {
            writeAndShow(errorPayload("CAMSCANNER_ACTIVITY_MISSING", "${error.javaClass.simpleName}: ${error.message}", elapsedMs()))
        } catch (error: Throwable) {
            Log.e(TAG, "failed to start baseline", error)
            writeAndShow(errorPayload("START_ERROR", "${error.javaClass.simpleName}: ${error.message}", elapsedMs()))
        }
    }

    @Deprecated("Deprecated in Android framework; kept to match the legacy OpenAPI contract.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_OCR) return
        val elapsed = elapsedMs()
        val payload = try {
            buildResultPayload(resultCode, data, elapsed)
        } catch (error: Throwable) {
            Log.e(TAG, "failed to parse CamScanner result", error)
            errorPayload("PARSE_ERROR", "${error.javaClass.simpleName}: ${error.message}", elapsed)
        }
        writeAndShow(payload)
    }

    private fun buildResultPayload(resultCode: Int, data: Intent?, elapsedMs: Long): JSONObject {
        val responseData = data?.getStringExtra(EXTRA_RESPONSE_DATA)
        val responseCode = data?.getIntExtra(EXTRA_RESPONSE_CODE, DEFAULT_RESPONSE_CODE) ?: DEFAULT_RESPONSE_CODE
        val probe = probeImage(imageFile)
        val parsed = parseCsOcrResponse(responseData)
        val status = when {
            resultCode != RESULT_OK -> "CSOCR_RESULT_CODE_${resultCode}"
            responseData.isNullOrBlank() -> "CSOCR_EMPTY_RESPONSE"
            parsed.optBoolean("parse_ok") -> "OK"
            else -> "CSOCR_PARSE_ERROR"
        }
        val sample = JSONObject()
            .put("id", sampleId)
            .put("source_image", imageFile.absolutePath)
            .put("status", status)
            .put("activity_result_code", resultCode)
            .put("response_code", responseCode)
            .put("image_sha256", probe.sha256 ?: JSONObject.NULL)
            .put("image_size", JSONArray().put(probe.width).put(probe.height))
            .put("latency_ms", elapsedMs)
            .put("wall_elapsed_ms", elapsedMs)
            .put("peak_pss_kb", currentPssKb())
            .put("raw_response_size", responseData?.length ?: 0)
            .put("raw_response_data", responseData ?: JSONObject.NULL)
            .put("csocr", parsed)
            .put("textboom_ocrinfo", parsed.optJSONArray("textboom_ocrinfo") ?: JSONArray())

        probe.error?.let { sample.put("image_error", it) }

        return JSONObject()
            .put("generated_at", utcNow())
            .put("kind", "textboom-csocr-camscanner-baseline")
            .put("boundary", "standalone CamScanner OpenAPI baseline Activity; no TextBoom APK, ROM, flash, reboot, erase, or data cleanup mutation")
            .put("engine", engineJson())
            .put("device", deviceJson())
            .put("samples", JSONArray().put(sample))
            .put("result", status)
    }

    private fun parseCsOcrResponse(responseData: String?): JSONObject {
        if (responseData.isNullOrBlank()) {
            return JSONObject()
                .put("parse_ok", false)
                .put("error", "empty RESPONSE_DATA")
                .put("line_count", 0)
                .put("lines", JSONArray())
                .put("textboom_ocrinfo", JSONArray())
        }
        return try {
            val raw = JSONObject(responseData)
            val pageWidth = raw.optInt("pageWidth", 0)
            val pageHeight = raw.optInt("pageHeight", 0)
            val lineCount = raw.optInt("lineNum", 0)
            val lineTexts = raw.optJSONArray("linesText") ?: JSONArray()
            val linePos = raw.optJSONArray("eachLinePos") ?: JSONArray()
            val charPos = raw.optJSONArray("charPos") ?: JSONArray()
            val lines = JSONArray()
            val textboom = JSONArray()
            for (index in 0 until lineCount) {
                val text = lineTexts.optString(index, "").replace("\r", "").trim()
                val rawRect = parsePosition(linePos.optString(index, ""))
                val rect = transformCamScannerRect(rawRect, pageHeight)
                val chars = parseChars(text, charPos.optJSONArray(index), pageHeight)
                lines.put(
                    JSONObject()
                        .put("index", index)
                        .put("text", text)
                        .put("raw_line_pos", intArrayJson(rawRect))
                        .put("rect", rectJson(rect))
                        .put("char_count", text.length)
                        .put("chars", chars),
                )
                textboom.put(
                    JSONObject()
                        .put("text", text)
                        .put("rect", rectJson(rect))
                        .put("score", JSONObject.NULL),
                )
            }
            JSONObject()
                .put("parse_ok", true)
                .put("page_width", pageWidth)
                .put("page_height", pageHeight)
                .put("language", raw.optInt("language", 0))
                .put("line_count", lineCount)
                .put("full_text", concatLineText(lines))
                .put("lines", lines)
                .put("textboom_ocrinfo", textboom)
        } catch (error: JSONException) {
            JSONObject()
                .put("parse_ok", false)
                .put("error", "${error.javaClass.simpleName}: ${error.message}")
                .put("line_count", 0)
                .put("lines", JSONArray())
                .put("textboom_ocrinfo", JSONArray())
        }
    }

    private fun parseChars(text: String, rawCharPos: JSONArray?, pageHeight: Int): JSONArray {
        val chars = JSONArray()
        if (rawCharPos == null) return chars
        for (index in 0 until rawCharPos.length()) {
            val rawRect = parsePosition(rawCharPos.optString(index, ""))
            val rect = transformCamScannerRect(rawRect, pageHeight)
            chars.put(
                JSONObject()
                    .put("index", index)
                    .put("text", text.getOrNull(index)?.toString() ?: "")
                    .put("raw_pos", intArrayJson(rawRect))
                    .put("rect", rectJson(rect)),
            )
        }
        return chars
    }

    private fun transformCamScannerRect(raw: IntArray, pageHeight: Int): IntArray {
        if (raw.size != 4) return intArrayOf(0, 0, 0, 0)
        val left = raw[0]
        val top = pageHeight - raw[1] - raw[3]
        return intArrayOf(left, top, left + raw[2], top + raw[3])
    }

    private fun parsePosition(value: String): IntArray {
        val trimmed = value.trim()
        if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
            return intArrayOf(0, 0, 0, 0)
        }
        val parts = trimmed.substring(1, trimmed.length - 1).split(",")
        if (parts.size != 4) return intArrayOf(0, 0, 0, 0)
        return IntArray(4) { index -> parts[index].trim().toIntOrNull() ?: 0 }
    }

    private fun concatLineText(lines: JSONArray): String {
        val builder = StringBuilder()
        for (index in 0 until lines.length()) {
            builder.append(lines.optJSONObject(index)?.optString("text", "") ?: "")
        }
        return builder.toString()
    }

    private fun writeAndShow(payload: JSONObject) {
        writeJson(resultFile, payload)
        val message = "result=${payload.optString("result")}\n" +
            "sample=${sampleId}\n" +
            "image=${imageFile.absolutePath}\n" +
            "output=${resultFile.absolutePath}"
        Log.i(TAG, message)
        statusView.text = message
    }

    private fun errorPayload(status: String, message: String, elapsedMs: Long): JSONObject {
        val sample = JSONObject()
            .put("id", if (::sampleId.isInitialized) sampleId else "sample")
            .put("status", status)
            .put("error", message)
            .put("latency_ms", elapsedMs)
            .put("peak_pss_kb", currentPssKb())
            .put("csocr", JSONObject().put("parse_ok", false).put("line_count", 0).put("lines", JSONArray()))
        return JSONObject()
            .put("generated_at", utcNow())
            .put("kind", "textboom-csocr-camscanner-baseline")
            .put("boundary", "standalone CamScanner OpenAPI baseline Activity; no TextBoom APK, ROM, flash, reboot, erase, or data cleanup mutation")
            .put("engine", engineJson())
            .put("device", deviceJson())
            .put("samples", JSONArray().put(sample))
            .put("result", status)
    }

    private fun resolvePath(path: String?, fallback: File): File {
        if (path.isNullOrBlank()) return fallback
        val file = File(path.trim())
        if (file.isAbsolute) return file
        val appRoot = getExternalFilesDir(null) ?: filesDir
        return File(appRoot, path.trim())
    }

    private fun camScannerPackage(): String? {
        val candidates = listOf("com.intsig.camscanner", "com.intsig.camscanner_cn")
        return candidates.firstOrNull { packageName ->
            try {
                packageManager.getPackageInfo(packageName, 0)
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    private fun grantCamScannerUri(uri: Uri) {
        for (packageName in listOf("com.intsig.camscanner", "com.intsig.camscanner_cn")) {
            grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
    }

    private fun probeImage(image: File): ImageProbe {
        if (!image.isFile) {
            return ImageProbe(0, 0, null, "missing file")
        }
        return try {
            val options = BitmapFactory.Options()
            options.inJustDecodeBounds = true
            BitmapFactory.decodeFile(image.absolutePath, options)
            ImageProbe(options.outWidth, options.outHeight, sha256(image), null)
        } catch (error: Throwable) {
            ImageProbe(0, 0, null, "${error.javaClass.simpleName}: ${error.message}")
        }
    }

    private fun currentPssKb(): Int {
        val memoryInfo = Debug.MemoryInfo()
        Debug.getMemoryInfo(memoryInfo)
        return memoryInfo.totalPss
    }

    private fun elapsedMs(): Long = if (startedAtMs == 0L) 0L else SystemClock.elapsedRealtime() - startedAtMs

    private fun imageId(image: File): String {
        val dot = image.name.lastIndexOf('.')
        return if (dot > 0) image.name.substring(0, dot) else image.name.ifBlank { "sample" }
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

    private fun intArrayJson(values: IntArray): JSONArray {
        val array = JSONArray()
        values.forEach { array.put(it) }
        return array
    }

    private fun rectJson(values: IntArray): JSONObject = JSONObject()
        .put("left", values.getOrElse(0) { 0 })
        .put("top", values.getOrElse(1) { 0 })
        .put("right", values.getOrElse(2) { 0 })
        .put("bottom", values.getOrElse(3) { 0 })

    private fun engineJson(): JSONObject = JSONObject()
        .put("id", "textboom-csocr-camscanner-openapi")
        .put("version", "0.1.0")
        .put("runtime", "CamScanner ACTION_OCR")
        .put("activity", "$packageName/.CamScannerBaselineActivity")

    private fun deviceJson(): JSONObject = JSONObject()
        .put("manufacturer", android.os.Build.MANUFACTURER)
        .put("brand", android.os.Build.BRAND)
        .put("model", android.os.Build.MODEL)
        .put("device", android.os.Build.DEVICE)
        .put("sdk_int", android.os.Build.VERSION.SDK_INT)
        .put("android_release", android.os.Build.VERSION.RELEASE)

    private data class ImageProbe(
        val width: Int,
        val height: Int,
        val sha256: String?,
        val error: String?,
    )

    companion object {
        private const val TAG = "SmartisaxCsOcrBaseline"
        private const val ACTION_OCR = "com.intsig.camscanner.ACTION_OCR"
        private const val REQ_OCR = 4401
        private const val DEFAULT_IMAGE_NAME = "imageboom.jpg"
        private const val DEFAULT_OCR_LANGUAGE = 3
        private const val DEFAULT_RESPONSE_CODE = 3000
        private const val EXTRA_IMAGE_PATH = "image_path"
        private const val EXTRA_RESULT_PATH = "result_path"
        private const val EXTRA_SAMPLE_ID = "sample_id"
        private const val EXTRA_APP_KEY = "app_key"
        private const val EXTRA_RESPONSE_DATA = "RESPONSE_DATA"
        private const val EXTRA_RESPONSE_CODE = "RESPONSE_CODE"
        private const val EXTRA_OCR_LANGUAGE = "ocr_language"
        private const val EXTRA_OCR_SHOW_PROGRESS = "ocr_show_progress"
        private const val EXTRA_OCR_SHOW_STATUSBAR = "ocr_show_statusbar"
    }
}
