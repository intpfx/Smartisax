package com.smartisax.browser;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.graphics.Rect;
import android.util.Base64;
import android.view.Display;
import android.view.WindowManager;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.lang.reflect.Method;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxScreenCapture {
    static final int AGENT_MAX_IMAGE_WIDTH = 720;
    static final int AGENT_JPEG_QUALITY = 72;
    private static final int VISUAL_SIGNATURE_COLUMNS = 12;
    private static final int VISUAL_SIGNATURE_ROWS = 12;

    private SmartisaxScreenCapture() {
    }

    static AgentObservation captureForAgent(Context context) throws IOException {
        Bitmap raw = captureBitmap(context);
        if (raw == null) {
            throw new IOException("surfacecontrol_screenshot_returned_null");
        }
        Bitmap readable = readableBitmap(raw);
        int originalWidth = Math.max(1, readable.getWidth());
        int originalHeight = Math.max(1, readable.getHeight());
        int scaledWidth = originalWidth;
        int scaledHeight = originalHeight;
        Bitmap scaled = readable;
        if (originalWidth > AGENT_MAX_IMAGE_WIDTH) {
            scaledWidth = AGENT_MAX_IMAGE_WIDTH;
            scaledHeight = Math.max(1, Math.round(originalHeight * (AGENT_MAX_IMAGE_WIDTH / (float) originalWidth)));
            scaled = Bitmap.createScaledBitmap(readable, scaledWidth, scaledHeight, true);
        }
        byte[] visualSignature = visualSignature(scaled);
        ByteArrayOutputStream out = new ByteArrayOutputStream(256 * 1024);
        if (!scaled.compress(Bitmap.CompressFormat.JPEG, AGENT_JPEG_QUALITY, out)) {
            throw new IOException("bitmap_jpeg_compress_failed");
        }
        byte[] bytes = out.toByteArray();
        if (bytes.length < 4 || bytes[0] != (byte) 0xff || bytes[1] != (byte) 0xd8) {
            throw new IOException("agent_screenshot_not_jpeg size=" + bytes.length);
        }
        return new AgentObservation(
                originalWidth,
                originalHeight,
                scaledWidth,
                scaledHeight,
                displayRotation(context),
                bytes,
                visualSignature);
    }

    static byte[] capturePng(Context context) throws IOException {
        Bitmap bitmap = captureBitmap(context);
        if (bitmap == null) {
            throw new IOException("surfacecontrol_screenshot_returned_null");
        }
        Bitmap pngBitmap = readableBitmap(bitmap);
        ByteArrayOutputStream out = new ByteArrayOutputStream(1024 * 1024);
        if (!pngBitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
            throw new IOException("bitmap_png_compress_failed");
        }
        byte[] bytes = out.toByteArray();
        if (!isPng(bytes)) {
            throw new IOException("surfacecontrol_screenshot_not_png size=" + bytes.length);
        }
        return bytes;
    }

    static Bitmap captureBitmap(Context context) throws IOException {
        try {
            Point size = realDisplaySize(context);
            int rotation = displayRotation(context);
            Class<?> surfaceControl = Class.forName("android.view.SurfaceControl");
            try {
                Method screenshot = surfaceControl.getDeclaredMethod(
                        "screenshot", Rect.class, int.class, int.class, boolean.class, int.class);
                return bitmapFromSurfaceResult(
                        screenshot.invoke(null, new Rect(), size.x, size.y, false, rotation));
            } catch (NoSuchMethodException ignored) {
                Method screenshot = surfaceControl.getDeclaredMethod(
                        "screenshot", Rect.class, int.class, int.class, int.class);
                return bitmapFromSurfaceResult(
                        screenshot.invoke(null, new Rect(), size.x, size.y, rotation));
            }
        } catch (ReflectiveOperationException e) {
            throw new IOException("surfacecontrol_screenshot_reflection_failed", e);
        } catch (RuntimeException e) {
            throw new IOException("surfacecontrol_screenshot_runtime_failed", e);
        }
    }

    static JSONObject displayJson(Context context) throws JSONException {
        Point size = realDisplaySize(context);
        JSONObject json = new JSONObject();
        json.put("width", size.x);
        json.put("height", size.y);
        json.put("rotation", displayRotation(context));
        return json;
    }

    static Point realDisplaySize(Context context) {
        Point size = new Point();
        try {
            WindowManager windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
            Display display = windowManager == null ? null : windowManager.getDefaultDisplay();
            if (display != null) {
                display.getRealSize(size);
            }
        } catch (RuntimeException ignored) {
        }
        if (size.x <= 0 || size.y <= 0) {
            size.x = 1080;
            size.y = 2340;
        }
        return size;
    }

    static int displayRotation(Context context) {
        try {
            WindowManager windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
            Display display = windowManager == null ? null : windowManager.getDefaultDisplay();
            return display == null ? 0 : display.getRotation();
        } catch (RuntimeException ignored) {
            return 0;
        }
    }

    private static Bitmap readableBitmap(Bitmap bitmap) {
        if (bitmap.getConfig() == Bitmap.Config.HARDWARE) {
            return bitmap.copy(Bitmap.Config.ARGB_8888, false);
        }
        return bitmap;
    }

    private static Bitmap bitmapFromSurfaceResult(Object result) throws IOException {
        if (result == null) {
            return null;
        }
        if (result instanceof Bitmap) {
            return (Bitmap) result;
        }
        try {
            Class<?> resultClass = result.getClass();
            Method getGraphicBuffer = resultClass.getDeclaredMethod("getGraphicBuffer");
            Method getColorSpace = resultClass.getDeclaredMethod("getColorSpace");
            Object graphicBuffer = getGraphicBuffer.invoke(result);
            Object colorSpace = getColorSpace.invoke(result);
            if (graphicBuffer == null) {
                return null;
            }
            Class<?> graphicBufferClass = Class.forName("android.graphics.GraphicBuffer");
            Class<?> colorSpaceClass = Class.forName("android.graphics.ColorSpace");
            try {
                Method wrap = Bitmap.class.getDeclaredMethod(
                        "wrapHardwareBuffer", graphicBufferClass, colorSpaceClass);
                Object bitmap = wrap.invoke(null, graphicBuffer, colorSpace);
                if (bitmap instanceof Bitmap) {
                    return (Bitmap) bitmap;
                }
            } catch (NoSuchMethodException ignored) {
                Class<?> hardwareBufferClass = Class.forName("android.hardware.HardwareBuffer");
                Method create = hardwareBufferClass.getDeclaredMethod(
                        "createFromGraphicBuffer", graphicBufferClass);
                Object hardwareBuffer = create.invoke(null, graphicBuffer);
                Method wrap = Bitmap.class.getDeclaredMethod(
                        "wrapHardwareBuffer", hardwareBufferClass, colorSpaceClass);
                Object bitmap = wrap.invoke(null, hardwareBuffer, colorSpace);
                if (bitmap instanceof Bitmap) {
                    return (Bitmap) bitmap;
                }
            }
            throw new IOException("surfacecontrol_screenshot_unsupported_bitmap_result");
        } catch (ReflectiveOperationException e) {
            throw new IOException(
                    "surfacecontrol_screenshot_buffer_convert_failed class="
                            + result.getClass().getName(), e);
        }
    }

    private static boolean isPng(byte[] bytes) {
        return bytes.length >= 8
                && bytes[0] == (byte) 0x89
                && bytes[1] == 0x50
                && bytes[2] == 0x4e
                && bytes[3] == 0x47
                && bytes[4] == 0x0d
                && bytes[5] == 0x0a
                && bytes[6] == 0x1a
                && bytes[7] == 0x0a;
    }

    private static byte[] visualSignature(Bitmap bitmap) {
        byte[] signature = new byte[VISUAL_SIGNATURE_COLUMNS * VISUAL_SIGNATURE_ROWS];
        int width = Math.max(1, bitmap.getWidth());
        int height = Math.max(1, bitmap.getHeight());
        int index = 0;
        for (int row = 0; row < VISUAL_SIGNATURE_ROWS; row++) {
            int y = Math.min(height - 1, Math.max(0,
                    Math.round(((row + 0.5f) / VISUAL_SIGNATURE_ROWS) * (height - 1))));
            for (int column = 0; column < VISUAL_SIGNATURE_COLUMNS; column++) {
                int x = Math.min(width - 1, Math.max(0,
                        Math.round(((column + 0.5f) / VISUAL_SIGNATURE_COLUMNS) * (width - 1))));
                int pixel = bitmap.getPixel(x, y);
                int red = (pixel >> 16) & 0xff;
                int green = (pixel >> 8) & 0xff;
                int blue = pixel & 0xff;
                signature[index++] = (byte) ((red * 30 + green * 59 + blue * 11) / 100);
            }
        }
        return signature;
    }

    static final class AgentObservation {
        private static final char[] HEX = "0123456789abcdef".toCharArray();
        private static final double MATERIAL_VISUAL_DISTANCE = 14.0d;
        private static final int MATERIAL_VISUAL_CELL_DELTA = 28;
        private static final int MATERIAL_VISUAL_CHANGED_CELLS = 18;
        final int originalWidth;
        final int originalHeight;
        final int scaledWidth;
        final int scaledHeight;
        final int rotation;
        private final byte[] jpegBytes;
        private final byte[] visualSignature;
        private final String fingerprint;

        AgentObservation(
                int originalWidth,
                int originalHeight,
                int scaledWidth,
                int scaledHeight,
                int rotation,
                byte[] jpegBytes,
                byte[] visualSignature) {
            this.originalWidth = originalWidth;
            this.originalHeight = originalHeight;
            this.scaledWidth = scaledWidth;
            this.scaledHeight = scaledHeight;
            this.rotation = rotation;
            this.jpegBytes = jpegBytes;
            this.visualSignature = visualSignature == null ? new byte[0] : visualSignature.clone();
            this.fingerprint = sha256(jpegBytes);
        }

        String jpegDataUrl() {
            return "data:image/jpeg;base64," + Base64.encodeToString(jpegBytes, Base64.NO_WRAP);
        }

        String fingerprint() {
            return fingerprint;
        }

        boolean canCompareVisual(AgentObservation other) {
            return other != null
                    && visualSignature.length > 0
                    && visualSignature.length == other.visualSignature.length;
        }

        double visualDistance(AgentObservation other) {
            if (!canCompareVisual(other)) {
                return -1.0d;
            }
            int total = 0;
            for (int i = 0; i < visualSignature.length; i++) {
                total += Math.abs((visualSignature[i] & 0xff) - (other.visualSignature[i] & 0xff));
            }
            return total / (double) visualSignature.length;
        }

        int visualChangedCells(AgentObservation other) {
            if (!canCompareVisual(other)) {
                return 0;
            }
            int changed = 0;
            for (int i = 0; i < visualSignature.length; i++) {
                int delta = Math.abs((visualSignature[i] & 0xff) - (other.visualSignature[i] & 0xff));
                if (delta >= MATERIAL_VISUAL_CELL_DELTA) {
                    changed++;
                }
            }
            return changed;
        }

        int visualCellCount() {
            return visualSignature.length;
        }

        boolean materiallyDifferent(AgentObservation other) {
            return canCompareVisual(other)
                    && (visualDistance(other) >= MATERIAL_VISUAL_DISTANCE
                    || visualChangedCells(other) >= MATERIAL_VISUAL_CHANGED_CELLS);
        }

        JSONObject summaryJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("originalWidth", originalWidth);
            json.put("originalHeight", originalHeight);
            json.put("scaledWidth", scaledWidth);
            json.put("scaledHeight", scaledHeight);
            json.put("rotation", rotation);
            json.put("mime", "image/jpeg");
            json.put("jpegBytes", jpegBytes.length);
            json.put("visualSignature", VISUAL_SIGNATURE_COLUMNS + "x" + VISUAL_SIGNATURE_ROWS);
            if (fingerprint.length() > 0) {
                json.put("fingerprint", shortFingerprint(fingerprint));
            }
            json.put("stored", false);
            return json;
        }

        private static String sha256(byte[] bytes) {
            try {
                byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
                StringBuilder builder = new StringBuilder(digest.length * 2);
                for (byte value : digest) {
                    builder.append(HEX[(value >> 4) & 0x0f]);
                    builder.append(HEX[value & 0x0f]);
                }
                return builder.toString();
            } catch (NoSuchAlgorithmException ignored) {
                return "";
            }
        }

        private static String shortFingerprint(String value) {
            return value.length() <= 16 ? value : value.substring(0, 16);
        }
    }
}
