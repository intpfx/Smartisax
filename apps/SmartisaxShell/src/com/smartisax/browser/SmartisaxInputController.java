package com.smartisax.browser;

import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.MotionEvent;
import java.io.IOException;
import java.lang.reflect.Method;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxInputController {
    private static final Object TOUCH_LOCK = new Object();
    private static final Object INJECT_LOCK = new Object();
    private static Object inputManagerInstance;
    private static Method injectInputEventMethod;
    private static boolean streamActive;
    private static long streamDownTime;
    private static long streamPointerId;
    private static int streamLastX;
    private static int streamLastY;
    private static double streamClientBaseElapsedMs;
    private static long streamDeviceBaseUptimeMs;
    private static long streamLastEventTimeUptimeMs;
    private static boolean streamClientTimingActive;
    private static volatile long lastInjectedMotionEventTimeUptimeMs;

    private SmartisaxInputController() {
    }

    static JSONObject handle(JSONObject body) throws IOException, JSONException {
        long receivedElapsedMs = SystemClock.elapsedRealtime();
        String type = body.optString("type", "");
        String normalizedType = type;
        boolean ok = false;
        int markerX = -1;
        int markerY = -1;
        int injectedEvents = 0;
        if ("tap".equals(type)) {
            int x = coordinate(body, "x");
            int y = coordinate(body, "y");
            ok = injectTap(x, y);
            injectedEvents = 2;
            markerX = x;
            markerY = y;
        } else if ("swipe".equals(type)) {
            int x1 = coordinate(body, "x1");
            int y1 = coordinate(body, "y1");
            int x2 = coordinate(body, "x2");
            int y2 = coordinate(body, "y2");
            int duration = clamp(body.optInt("duration", 240), 50, 1500);
            injectedEvents = injectSwipe(x1, y1, x2, y2, duration);
            ok = injectedEvents > 0;
            markerX = x2;
            markerY = y2;
        } else if ("key".equals(type)) {
            normalizedType = "key";
            ok = injectKey(keyCode(body.optString("key", "")));
            injectedEvents = 2;
        } else if (isTouchStart(type)) {
            normalizedType = "touchStart";
            int x = coordinate(body, "x");
            int y = coordinate(body, "y");
            ok = injectTouchStart(body.optLong("pointerId", 1L), x, y, clientEventElapsedMs(body));
            injectedEvents = 1;
            markerX = x;
            markerY = y;
        } else if (isTouchMove(type)) {
            normalizedType = isTouchMoveBatch(type) ? "touchMoveBatch" : "touchMove";
            MoveResult result = injectTouchMove(body);
            ok = result.injectedEvents > 0;
            injectedEvents = result.injectedEvents;
            markerX = result.lastX;
            markerY = result.lastY;
        } else if (isTouchEnd(type)) {
            normalizedType = "touchEnd";
            int x = coordinate(body, "x");
            int y = coordinate(body, "y");
            ok = injectTouchEnd(body.optLong("pointerId", 1L), x, y, false, body);
            injectedEvents = 1;
            markerX = x;
            markerY = y;
        } else if (isTouchCancel(type)) {
            normalizedType = "touchCancel";
            int x = body.has("x") ? coordinate(body, "x") : currentX();
            int y = body.has("y") ? coordinate(body, "y") : currentY();
            ok = injectTouchEnd(body.optLong("pointerId", 1L), x, y, true, body);
            injectedEvents = 1;
            markerX = x;
            markerY = y;
        } else {
            throw new IOException("unsupported_input_type");
        }
        long injectionDoneElapsedMs = SystemClock.elapsedRealtime();
        if (!ok) {
            throw new IOException("input_injection_failed");
        }
        JSONObject json = new JSONObject();
        json.put("ok", true);
        json.put("type", normalizedType);
        json.put("requestType", type);
        json.put("backend", "privileged-inputmanager");
        json.put("transport", "webrtc-datachannel-input");
        json.put("stream", isStreamType(normalizedType) ? "down-move-up" : "legacy-gesture");
        json.put("eventTimeMode", "client-event-elapsed-relative-uptime");
        json.put("injectedEvents", injectedEvents);
        json.put("lastMotionEventTimeUptimeMs", lastInjectedMotionEventTimeUptimeMs);
        if (isTouchMoveBatch(normalizedType) || isTouchMoveBatch(type)) {
            json.put("pointCount", pointCount(body));
        }
        json.put("inputReceiveElapsedMs", receivedElapsedMs);
        json.put("injectionDoneElapsedMs", injectionDoneElapsedMs);
        json.put("injectionElapsedMs", Math.max(0L, injectionDoneElapsedMs - receivedElapsedMs));
        if (body.has("seq")) {
            json.put("seq", body.optLong("seq"));
        }
        if (body.has("clientElapsedMs")) {
            json.put("clientElapsedMs", body.optDouble("clientElapsedMs"));
        }
        boolean flashMarker = shouldFlashMarker(body, normalizedType);
        if (flashMarker) {
            json.put("marker", SmartisaxTouchMarker.flash(
                    normalizedType,
                    body.has("seq") ? body.optLong("seq") : -1L,
                    markerX,
                    markerY));
            SmartisaxWebRtcRuntime.requestInputFrameBoost("touch-marker-injected");
        } else {
            SmartisaxWebRtcRuntime.requestInputFrameBoost("input-" + normalizedType);
        }
        if (!flashMarker && body.optBoolean("markerStatus", false)) {
            json.put("marker", SmartisaxTouchMarker.statusJson());
        }
        return json;
    }

    private static boolean isTouchStart(String type) {
        return "touchStart".equals(type) || "pointerDown".equals(type) || "down".equals(type);
    }

    private static boolean isTouchMove(String type) {
        return "touchMove".equals(type) || "pointerMove".equals(type) || "move".equals(type)
                || "touchMoveBatch".equals(type) || "moveBatch".equals(type);
    }

    private static boolean isTouchMoveBatch(String type) {
        return "touchMoveBatch".equals(type) || "moveBatch".equals(type);
    }

    private static boolean isTouchEnd(String type) {
        return "touchEnd".equals(type) || "pointerUp".equals(type) || "up".equals(type);
    }

    private static boolean isTouchCancel(String type) {
        return "touchCancel".equals(type) || "pointerCancel".equals(type) || "cancel".equals(type);
    }

    private static boolean isStreamType(String type) {
        return "touchStart".equals(type) || "touchMove".equals(type) || "touchMoveBatch".equals(type)
                || "touchEnd".equals(type) || "touchCancel".equals(type);
    }

    private static boolean shouldFlashMarker(JSONObject body, String normalizedType) {
        if ("key".equals(normalizedType)) {
            return false;
        }
        boolean defaultValue = !"touchMove".equals(normalizedType) && !"touchMoveBatch".equals(normalizedType);
        return body.optBoolean("marker", defaultValue);
    }

    private static int keyCode(String key) throws IOException {
        if ("BACK".equalsIgnoreCase(key)) {
            return KeyEvent.KEYCODE_BACK;
        }
        if ("HOME".equalsIgnoreCase(key)) {
            return KeyEvent.KEYCODE_HOME;
        }
        throw new IOException("unsupported_key_" + key);
    }

    private static int pointCount(JSONObject body) {
        JSONArray points = body.optJSONArray("points");
        return points == null ? 0 : points.length();
    }

    private static int coordinate(JSONObject body, String key) throws IOException {
        if (!body.has(key)) {
            throw new IOException("missing_coordinate_" + key);
        }
        return clamp(body.optInt(key, -1), 0, 10000);
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static boolean injectTap(int x, int y) throws IOException {
        long now = SystemClock.uptimeMillis();
        return injectMotion(MotionEvent.ACTION_DOWN, now, now, x, y)
                && injectMotion(MotionEvent.ACTION_UP, now, now + 40, x, y);
    }

    private static boolean injectKey(int keyCode) throws IOException {
        long downTime = SystemClock.uptimeMillis();
        return injectInputEvent(new KeyEvent(
                downTime,
                downTime,
                KeyEvent.ACTION_DOWN,
                keyCode,
                0,
                0,
                KeyCharacterMap.VIRTUAL_KEYBOARD,
                0,
                KeyEvent.FLAG_FROM_SYSTEM,
                InputDevice.SOURCE_KEYBOARD))
                && injectInputEvent(new KeyEvent(
                downTime,
                downTime + 40,
                KeyEvent.ACTION_UP,
                keyCode,
                0,
                0,
                KeyCharacterMap.VIRTUAL_KEYBOARD,
                0,
                KeyEvent.FLAG_FROM_SYSTEM,
                InputDevice.SOURCE_KEYBOARD));
    }

    private static int injectSwipe(int x1, int y1, int x2, int y2, int duration) throws IOException {
        long downTime = SystemClock.uptimeMillis();
        boolean ok = injectMotion(MotionEvent.ACTION_DOWN, downTime, downTime, x1, y1);
        int injected = ok ? 1 : 0;
        int steps = Math.max(2, Math.min(12, duration / 50));
        for (int i = 1; i < steps; i++) {
            float fraction = i / (float) steps;
            int x = Math.round(x1 + (x2 - x1) * fraction);
            int y = Math.round(y1 + (y2 - y1) * fraction);
            if (injectMotion(MotionEvent.ACTION_MOVE, downTime, downTime + (duration * i / steps), x, y)) {
                injected += 1;
            } else {
                ok = false;
            }
        }
        if (injectMotion(MotionEvent.ACTION_UP, downTime, downTime + duration, x2, y2)) {
            injected += 1;
        } else {
            ok = false;
        }
        return ok ? injected : 0;
    }

    private static boolean injectTouchStart(long pointerId, int x, int y, double clientEventElapsedMs)
            throws IOException {
        synchronized (TOUCH_LOCK) {
            if (streamActive) {
                injectMotion(MotionEvent.ACTION_CANCEL, streamDownTime, SystemClock.uptimeMillis(), streamLastX, streamLastY);
                streamActive = false;
            }
            streamDownTime = SystemClock.uptimeMillis();
            streamPointerId = pointerId;
            streamLastX = x;
            streamLastY = y;
            streamClientBaseElapsedMs = clientEventElapsedMs;
            streamDeviceBaseUptimeMs = streamDownTime;
            streamLastEventTimeUptimeMs = streamDownTime;
            streamClientTimingActive = isFinite(clientEventElapsedMs);
            streamActive = injectMotion(MotionEvent.ACTION_DOWN, streamDownTime, streamDownTime, x, y);
            return streamActive;
        }
    }

    private static MoveResult injectTouchMove(JSONObject body) throws IOException, JSONException {
        synchronized (TOUCH_LOCK) {
            if (!streamActive) {
                throw new IOException("touch_stream_not_active");
            }
            long pointerId = body.optLong("pointerId", streamPointerId);
            if (pointerId != streamPointerId) {
                throw new IOException("touch_stream_pointer_mismatch");
            }
            JSONArray points = body.optJSONArray("points");
            if (points != null && points.length() > 0) {
                int injected = 0;
                int lastX = streamLastX;
                int lastY = streamLastY;
                for (int i = 0; i < points.length(); i++) {
                    JSONObject point = points.optJSONObject(i);
                    if (point == null) {
                        continue;
                    }
                    int x = coordinate(point, "x");
                    int y = coordinate(point, "y");
                    long eventTime = streamEventTime(point);
                    if (injectMotion(MotionEvent.ACTION_MOVE, streamDownTime, eventTime, x, y)) {
                        injected += 1;
                        lastX = x;
                        lastY = y;
                    }
                }
                streamLastX = lastX;
                streamLastY = lastY;
                return new MoveResult(injected, lastX, lastY);
            }
            int x = coordinate(body, "x");
            int y = coordinate(body, "y");
            boolean ok = injectMotion(MotionEvent.ACTION_MOVE, streamDownTime, streamEventTime(body), x, y);
            if (ok) {
                streamLastX = x;
                streamLastY = y;
            }
            return new MoveResult(ok ? 1 : 0, streamLastX, streamLastY);
        }
    }

    private static boolean injectTouchEnd(long pointerId, int x, int y, boolean cancel, JSONObject body)
            throws IOException {
        synchronized (TOUCH_LOCK) {
            if (!streamActive) {
                throw new IOException("touch_stream_not_active");
            }
            if (pointerId != streamPointerId) {
                throw new IOException("touch_stream_pointer_mismatch");
            }
            long eventTime = streamEventTime(body);
            boolean ok = injectMotion(cancel ? MotionEvent.ACTION_CANCEL : MotionEvent.ACTION_UP,
                    streamDownTime, eventTime, x, y);
            streamLastX = x;
            streamLastY = y;
            streamActive = false;
            streamPointerId = 0L;
            streamDownTime = 0L;
            streamClientTimingActive = false;
            streamClientBaseElapsedMs = 0.0d;
            streamDeviceBaseUptimeMs = 0L;
            streamLastEventTimeUptimeMs = 0L;
            return ok;
        }
    }

    private static long streamEventTime(JSONObject body) {
        long now = SystemClock.uptimeMillis();
        long eventTime = now;
        double clientEventElapsedMs = clientEventElapsedMs(body);
        if (streamClientTimingActive && isFinite(clientEventElapsedMs)) {
            long deltaMs = Math.round(clientEventElapsedMs - streamClientBaseElapsedMs);
            deltaMs = clampLong(deltaMs, 0L, 60000L);
            eventTime = streamDeviceBaseUptimeMs + deltaMs;
        }
        eventTime = clampLong(eventTime, streamDownTime, now);
        if (eventTime < streamLastEventTimeUptimeMs) {
            eventTime = streamLastEventTimeUptimeMs;
        }
        streamLastEventTimeUptimeMs = eventTime;
        return eventTime;
    }

    private static double clientEventElapsedMs(JSONObject body) {
        if (body == null) {
            return Double.NaN;
        }
        if (body.has("clientEventElapsedMs")) {
            return body.optDouble("clientEventElapsedMs", Double.NaN);
        }
        if (body.has("eventElapsedMs")) {
            return body.optDouble("eventElapsedMs", Double.NaN);
        }
        if (body.has("e")) {
            return body.optDouble("e", Double.NaN);
        }
        return Double.NaN;
    }

    private static boolean isFinite(double value) {
        return !Double.isNaN(value) && !Double.isInfinite(value);
    }

    private static long clampLong(long value, long min, long max) {
        return Math.max(min, Math.min(max, value));
    }

    private static int currentX() {
        synchronized (TOUCH_LOCK) {
            return streamLastX;
        }
    }

    private static int currentY() {
        synchronized (TOUCH_LOCK) {
            return streamLastY;
        }
    }

    private static boolean injectMotion(int action, long downTime, long eventTime, int x, int y)
            throws IOException {
        MotionEvent event = MotionEvent.obtain(downTime, eventTime, action, x, y, 0);
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try {
            boolean ok = injectInputEvent(event);
            if (ok) {
                lastInjectedMotionEventTimeUptimeMs = eventTime;
            }
            return ok;
        } finally {
            event.recycle();
        }
    }

    private static boolean injectInputEvent(InputEvent event) throws IOException {
        try {
            Object manager;
            Method inject;
            synchronized (INJECT_LOCK) {
                if (inputManagerInstance == null || injectInputEventMethod == null) {
                    Class<?> inputManager = Class.forName("android.hardware.input.InputManager");
                    Method getInstance = inputManager.getDeclaredMethod("getInstance");
                    inputManagerInstance = getInstance.invoke(null);
                    injectInputEventMethod = inputManager.getDeclaredMethod("injectInputEvent", InputEvent.class, int.class);
                }
                manager = inputManagerInstance;
                inject = injectInputEventMethod;
            }
            Object result = inject.invoke(manager, event, 0);
            return Boolean.TRUE.equals(result);
        } catch (ReflectiveOperationException e) {
            throw new IOException("inputmanager_reflection_failed", e);
        } catch (RuntimeException e) {
            throw new IOException("inputmanager_runtime_failed", e);
        }
    }

    private static final class MoveResult {
        final int injectedEvents;
        final int lastX;
        final int lastY;

        MoveResult(int injectedEvents, int lastX, int lastY) {
            this.injectedEvents = injectedEvents;
            this.lastX = lastX;
            this.lastY = lastY;
        }
    }
}
