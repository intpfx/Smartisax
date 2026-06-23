package com.smartisax.browser;

import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import java.io.IOException;
import java.lang.reflect.Method;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxInputController {
    private SmartisaxInputController() {
    }

    static JSONObject handle(JSONObject body) throws IOException, JSONException {
        String type = body.optString("type", "");
        boolean ok;
        if ("tap".equals(type)) {
            int x = coordinate(body, "x");
            int y = coordinate(body, "y");
            ok = injectTap(x, y);
        } else if ("swipe".equals(type)) {
            int x1 = coordinate(body, "x1");
            int y1 = coordinate(body, "y1");
            int x2 = coordinate(body, "x2");
            int y2 = coordinate(body, "y2");
            int duration = clamp(body.optInt("duration", 240), 50, 1500);
            ok = injectSwipe(x1, y1, x2, y2, duration);
        } else {
            throw new IOException("unsupported_input_type");
        }
        if (!ok) {
            throw new IOException("input_injection_failed");
        }
        JSONObject json = new JSONObject();
        json.put("ok", true);
        json.put("type", type);
        json.put("backend", "privileged-inputmanager");
        json.put("transport", "webrtc-datachannel-input");
        if (body.has("seq")) {
            json.put("seq", body.optLong("seq"));
        }
        return json;
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

    private static boolean injectSwipe(int x1, int y1, int x2, int y2, int duration) throws IOException {
        long downTime = SystemClock.uptimeMillis();
        boolean ok = injectMotion(MotionEvent.ACTION_DOWN, downTime, downTime, x1, y1);
        int steps = Math.max(2, Math.min(12, duration / 50));
        for (int i = 1; i < steps; i++) {
            float fraction = i / (float) steps;
            int x = Math.round(x1 + (x2 - x1) * fraction);
            int y = Math.round(y1 + (y2 - y1) * fraction);
            ok &= injectMotion(MotionEvent.ACTION_MOVE, downTime, downTime + (duration * i / steps), x, y);
        }
        ok &= injectMotion(MotionEvent.ACTION_UP, downTime, downTime + duration, x2, y2);
        return ok;
    }

    private static boolean injectMotion(int action, long downTime, long eventTime, int x, int y)
            throws IOException {
        MotionEvent event = MotionEvent.obtain(downTime, eventTime, action, x, y, 0);
        event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try {
            Class<?> inputManager = Class.forName("android.hardware.input.InputManager");
            Method getInstance = inputManager.getDeclaredMethod("getInstance");
            Object manager = getInstance.invoke(null);
            Method inject = inputManager.getDeclaredMethod("injectInputEvent", InputEvent.class, int.class);
            Object result = inject.invoke(manager, event, 0);
            return Boolean.TRUE.equals(result);
        } catch (ReflectiveOperationException e) {
            throw new IOException("inputmanager_reflection_failed", e);
        } catch (RuntimeException e) {
            throw new IOException("inputmanager_runtime_failed", e);
        } finally {
            event.recycle();
        }
    }
}
