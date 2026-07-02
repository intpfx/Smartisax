package com.smartisax.browser;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.SystemClock;
import android.provider.Settings;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.List;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxOneStepController {
    private static final int SIDEBAR_MODE_RIGHT = 2;
    private static final int SIDEBAR_MODE_EXIT = -1;
    private static final int SIDEBAR_REASON_AGENT = 0;
    private static final int IWINDOW_MANAGER_REQUEST_ZOOM = 2001;
    private static final long PROGRAMMATIC_WAIT_MS = 2800L;
    private static final long PROGRAMMATIC_RETRY_WAIT_MS = 1800L;
    private static final long RECOVERY_HOME_SETTLE_MS = 650L;
    private static final long RECOVERY_EXIT_WAIT_MS = 1000L;
    private static final long RECOVERY_ENTER_WAIT_MS = 3000L;
    private static final long FALLBACK_WAIT_MS = 1400L;
    private static final long STATE_POLL_MS = 120L;

    private SmartisaxOneStepController() {
    }

    static JSONObject handle(Context context, String operation, JSONObject display)
            throws JSONException, IOException {
        JSONObject result = new JSONObject();
        result.put("operation", operation);
        result.put("before", stateJson(context));
        JSONObject programmatic = requestProgrammatic(operation);
        result.put("programmatic", programmatic);
        JSONObject afterProgrammatic = waitForOperation(context, operation, PROGRAMMATIC_WAIT_MS);
        result.put("afterProgrammatic", afterProgrammatic);
        if (!operationSatisfied(operation, afterProgrammatic)) {
            JSONObject retry = requestProgrammatic(operation);
            result.put("programmaticRetry", retry);
            JSONObject afterRetry = waitForOperation(context, operation, PROGRAMMATIC_RETRY_WAIT_MS);
            result.put("afterRetry", afterRetry);
        }
        JSONObject afterRetry = result.optJSONObject("afterRetry");
        JSONObject latest = afterRetry == null ? afterProgrammatic : afterRetry;
        if (!operationSatisfied(operation, latest) && "enter".equals(operation)) {
            JSONObject recovery = recoverEnterVisibility(context);
            result.put("visibilityRecovery", recovery);
            JSONObject afterRecovery = recovery.optJSONObject("afterEnter");
            if (afterRecovery != null) {
                latest = afterRecovery;
            }
        }
        if (!operationSatisfied(operation, latest)) {
            JSONObject fallback = fallbackGesture(operation, display);
            result.put("fallback", fallback);
            result.put("afterFallback", waitForOperation(context, operation, FALLBACK_WAIT_MS));
        }
        JSONObject after = stateJson(context);
        result.put("after", after);
        boolean satisfied = operationSatisfied(operation, after);
        result.put("satisfied", satisfied);
        if (!satisfied) {
            result.put("failureReason", failureReason(operation, after));
        }
        result.put("backend", "smartisan-one-step-window-manager");
        return result;
    }

    private static JSONObject recoverEnterVisibility(Context context) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("strategy", "one_step_visibility_recovery_home_exit_enter");
        JSONObject home = new JSONObject();
        home.put("type", "key");
        home.put("key", "HOME");
        home.put("marker", false);
        json.put("home", safeInput(home));
        sleepQuietly(RECOVERY_HOME_SETTLE_MS);
        json.put("afterHome", stateJson(context));
        json.put("exit", requestProgrammatic("exit"));
        json.put("afterExit", waitForOperation(context, "exit", RECOVERY_EXIT_WAIT_MS));
        json.put("enter", requestProgrammatic("enter"));
        json.put("afterEnter", waitForOperation(context, "enter", RECOVERY_ENTER_WAIT_MS));
        return json;
    }

    private static JSONObject safeInput(JSONObject body) throws JSONException {
        try {
            return SmartisaxInputController.handle(body);
        } catch (Exception e) {
            JSONObject error = new JSONObject();
            error.put("ok", false);
            error.put("error", e.getClass().getSimpleName() + ":" + limit(e.getMessage(), 120));
            return error;
        }
    }

    static JSONObject systemStateJson(Context context) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("oneStep", stateJson(context));
        JSONObject foreground = foregroundJson(context);
        if (foreground.length() > 0) {
            json.put("foreground", foreground);
        }
        return json;
    }

    static JSONObject stateJson(Context context) throws JSONException {
        JSONObject json = new JSONObject();
        int enabled = globalInt(context, "side_bar_mode", -1);
        int zoomType = globalInt(context, "side_bar_zoom_type", -1);
        int switchStatus = globalInt(context, "sidebar_switch_status", -1);
        boolean visible = zoomType == 1 || zoomType == SIDEBAR_MODE_RIGHT || switchStatus == 1;
        json.put("enabled", enabled == 1);
        json.put("sideBarMode", enabled);
        json.put("sideBarZoomType", zoomType);
        json.put("sidebarSwitchStatus", switchStatus);
        json.put("visible", visible);
        json.put("side", zoomType == 1 ? "left" : zoomType == SIDEBAR_MODE_RIGHT ? "right" : "none");
        return json;
    }

    private static JSONObject requestProgrammatic(String operation) throws JSONException {
        JSONObject json = new JSONObject();
        int mode = "exit".equals(operation) ? SIDEBAR_MODE_EXIT : SIDEBAR_MODE_RIGHT;
        json.put("mode", mode);
        json.put("reason", SIDEBAR_REASON_AGENT);
        json.put("transactCode", IWINDOW_MANAGER_REQUEST_ZOOM);
        try {
            Class<?> globalClass = Class.forName("android.view.WindowManagerGlobal");
            Method serviceMethod = globalClass.getDeclaredMethod("getWindowManagerService");
            Object service = serviceMethod.invoke(null);
            if (!(service instanceof IInterface)) {
                throw new IOException("window_manager_service_not_iinterface");
            }
            IBinder binder = ((IInterface) service).asBinder();
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInterfaceToken("android.view.IWindowManager");
                data.writeInt(mode);
                data.writeInt(SIDEBAR_REASON_AGENT);
                boolean ok = binder.transact(IWINDOW_MANAGER_REQUEST_ZOOM, data, reply, 0);
                reply.readException();
                json.put("ok", ok);
                json.put("method", "IWindowManager.transact(2001)");
            } finally {
                reply.recycle();
                data.recycle();
            }
        } catch (Exception e) {
            json.put("ok", false);
            json.put("error", e.getClass().getSimpleName() + ":" + limit(e.getMessage(), 120));
        }
        return json;
    }

    private static JSONObject fallbackGesture(String operation, JSONObject display)
            throws IOException, JSONException {
        if ("exit".equals(operation)) {
            JSONObject key = new JSONObject();
            key.put("type", "key");
            key.put("key", "BACK");
            key.put("marker", false);
            JSONObject result = SmartisaxInputController.handle(key);
            result.put("fallback", "back_key");
            return result;
        }
        int width = Math.max(1, display.optInt("width", 1080));
        int height = Math.max(1, display.optInt("height", 2340));
        int y = Math.max(0, Math.min(height - 1, Math.round(height * 0.72f)));
        JSONObject swipe = new JSONObject();
        swipe.put("type", "swipe");
        swipe.put("x1", Math.max(0, width - 2));
        swipe.put("y1", y);
        swipe.put("x2", Math.max(0, Math.round(width * 0.42f)));
        swipe.put("y2", y);
        swipe.put("duration", 360);
        swipe.put("marker", false);
        JSONObject result = SmartisaxInputController.handle(swipe);
        result.put("fallback", "right_edge_swipe");
        return result;
    }

    private static boolean operationSatisfied(String operation, JSONObject state) {
        boolean visible = state.optBoolean("visible", false);
        return "exit".equals(operation) ? !visible : visible;
    }

    private static JSONObject waitForOperation(Context context, String operation, long timeoutMs)
            throws JSONException {
        long start = SystemClock.elapsedRealtime();
        JSONObject state = stateJson(context);
        int polls = 0;
        while (!operationSatisfied(operation, state)
                && SystemClock.elapsedRealtime() - start < timeoutMs) {
            sleepQuietly(STATE_POLL_MS);
            polls++;
            state = stateJson(context);
        }
        long waited = Math.max(0L, SystemClock.elapsedRealtime() - start);
        state.put("waitedMs", waited);
        state.put("polls", polls);
        state.put("satisfied", operationSatisfied(operation, state));
        return state;
    }

    private static String failureReason(String operation, JSONObject state) {
        if ("exit".equals(operation)) {
            return state.optBoolean("visible", false)
                    ? "one_step_exit_still_visible" : "one_step_exit_not_confirmed";
        }
        return state.optBoolean("visible", false)
                ? "one_step_enter_not_confirmed" : "one_step_enter_not_visible";
    }

    private static int globalInt(Context context, String key, int fallback) {
        try {
            return Settings.Global.getInt(context.getContentResolver(), key, fallback);
        } catch (RuntimeException ignored) {
            return fallback;
        }
    }

    private static JSONObject foregroundJson(Context context) throws JSONException {
        JSONObject json = new JSONObject();
        try {
            ActivityManager activityManager =
                    (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
            List<ActivityManager.RunningTaskInfo> tasks = activityManager == null
                    ? null : activityManager.getRunningTasks(1);
            if (tasks == null || tasks.isEmpty() || tasks.get(0).topActivity == null) {
                return json;
            }
            ComponentName top = tasks.get(0).topActivity;
            json.put("package", top.getPackageName());
            json.put("class", top.getClassName());
            json.put("isSmartisaxShell", "com.smartisax.browser".equals(top.getPackageName()));
            json.put("isSettings", "com.android.settings".equals(top.getPackageName()));
        } catch (RuntimeException ignored) {
        }
        return json;
    }

    private static void sleepQuietly(long ms) {
        try {
            Thread.sleep(Math.max(0L, ms));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static String limit(String value, int max) {
        if (value == null) {
            return "";
        }
        return value.length() <= max ? value : value.substring(0, max);
    }
}
