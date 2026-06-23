package com.smartisax.textboom.ppocr

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.engine.OCREngine
import com.paddle.ocr.model.OCRResult
import com.paddle.ocr.util.OpenCVUtils
import java.util.ArrayList
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

object LocalPpOcrRuntime {
    private const val TAG = "TextBoomLocalPpOcr"
    private const val ERROR_INIT = -101
    private const val ERROR_BITMAP = -102
    private const val ERROR_RUNTIME = -103
    private const val DET_MODEL_ASSET = "models/det/inference.onnx"
    private const val REC_MODEL_ASSET = "models/rec/inference.onnx"
    private const val REC_CONFIG_ASSET = "models/rec/inference.yml"
    private const val CPU_THREAD_NUM = 4

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "TextBoomPpOcr").apply { isDaemon = true }
    }
    private val engineLock = Object()
    private var engine: OCREngine? = null

    private val config = PaddleOCRConfig(
        recScoreThresh = 0.0f,
        recBatchSize = 1,
    )

    @JvmStatic
    fun start(
        activity: Activity?,
        bitmap: Bitmap?,
        language: Int,
        listener: Any?,
        fromFloat: Boolean,
    ) {
        if (listener == null) return
        if (activity == null || bitmap == null || bitmap.isRecycled || bitmap.width <= 0 || bitmap.height <= 0) {
            postError(listener, ERROR_BITMAP)
            return
        }

        val appContext = activity.applicationContext
        val width = bitmap.width
        val height = bitmap.height
        val safeBitmap = try {
            bitmap.copy(Bitmap.Config.ARGB_8888, false)
        } catch (error: Throwable) {
            Log.e(TAG, "failed to copy bitmap", error)
            postError(listener, ERROR_BITMAP)
            return
        }

        executor.execute {
            try {
                val localEngine = getOrCreateEngine(appContext)
                val runResult = localEngine.run(safeBitmap)
                val mapped = mapResults(runResult.results, width, height)
                postSuccess(listener, mapped)
            } catch (error: Throwable) {
                Log.e(TAG, "local PP-OCR failed", error)
                postError(listener, if (isInitError(error)) ERROR_INIT else ERROR_RUNTIME)
            } finally {
                safeBitmap.recycle()
            }
        }
    }

    private fun getOrCreateEngine(context: Context): OCREngine {
        synchronized(engineLock) {
            engine?.let { return it }
            if (!OpenCVUtils.init(context)) {
                throw IllegalStateException("OpenCV init failed")
            }
            return OCREngine(
                context = context,
                config = config,
                engineConfig = EngineConfig(numThreads = CPU_THREAD_NUM),
                detModelAsset = DET_MODEL_ASSET,
                recModelAsset = REC_MODEL_ASSET,
                recConfigAsset = REC_CONFIG_ASSET,
            ).also { engine = it }
        }
    }

    private fun isInitError(error: Throwable): Boolean {
        val text = error.javaClass.name + ":" + (error.message ?: "")
        return text.contains("Model", ignoreCase = true) ||
            text.contains("OpenCV", ignoreCase = true) ||
            text.contains("UnsatisfiedLinkError", ignoreCase = true)
    }

    private fun mapResults(results: List<OCRResult>, width: Int, height: Int): ArrayList<Any> {
        val lines = results
            .mapNotNull { result -> toLine(result, width, height) }
            .sortedWith(compareBy({ it.rect.top }, { it.rect.left }, { it.rect.right }))

        val output = ArrayList<Any>(lines.size)
        for (line in lines) {
            output.add(createTextBoomOcrInfo(line.text, line.rect))
        }
        return output
    }

    private fun toLine(result: OCRResult, width: Int, height: Int): Line? {
        val text = normalizeText(result.text)
        if (text.isEmpty()) return null
        val points = result.box.points
        if (points.isEmpty()) return null

        var left = Float.POSITIVE_INFINITY
        var top = Float.POSITIVE_INFINITY
        var right = Float.NEGATIVE_INFINITY
        var bottom = Float.NEGATIVE_INFINITY
        for (point in points) {
            left = min(left, point.x)
            top = min(top, point.y)
            right = max(right, point.x)
            bottom = max(bottom, point.y)
        }

        val rect = RectF(
            clamp(min(left, right), 0f, width.toFloat()),
            clamp(min(top, bottom), 0f, height.toFloat()),
            clamp(max(left, right), 0f, width.toFloat()),
            clamp(max(top, bottom), 0f, height.toFloat()),
        )
        if (rect.width() <= 0f || rect.height() <= 0f) return null
        return Line(text, rect)
    }

    private fun normalizeText(value: String?): String {
        if (value == null) return ""
        return value.replace("\r", "").trim()
    }

    private fun clamp(value: Float, minValue: Float, maxValue: Float): Float {
        return max(minValue, min(maxValue, value))
    }

    private fun createTextBoomOcrInfo(text: String, rect: RectF): Any {
        val klass = Class.forName("com.smartisanos.textboom.ocr.OcrInfo")
        val item = klass.getDeclaredConstructor().newInstance()
        klass.getField("mText").set(item, text)
        val targetRect = klass.getField("mRect").get(item) as RectF
        targetRect.set(rect)
        return item
    }

    private fun postSuccess(listener: Any, data: ArrayList<Any>) {
        postToMain {
            try {
                val iface = Class.forName("com.smartisanos.textboom.ocr.IOcrApi\$OcrListener")
                val method = iface.getMethod("onResultSuccess", java.util.List::class.java)
                method.invoke(listener, data)
            } catch (error: Throwable) {
                Log.e(TAG, "failed to deliver OCR success", error)
            }
        }
    }

    private fun postError(listener: Any, code: Int) {
        postToMain {
            try {
                val iface = Class.forName("com.smartisanos.textboom.ocr.IOcrApi\$OcrListener")
                val method = iface.getMethod("onResultError", Integer.TYPE)
                method.invoke(listener, code)
            } catch (error: Throwable) {
                Log.e(TAG, "failed to deliver OCR error", error)
            }
        }
    }

    private fun postToMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    private data class Line(
        val text: String,
        val rect: RectF,
    )
}
