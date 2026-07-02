package com.smartisax.browser;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.ComponentName;
import android.content.Context;
import android.graphics.Rect;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.security.MessageDigest;
import java.util.List;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class SmartisaxAccessibilityService extends AccessibilityService {
    private static final int MAX_NODES = 120;
    private static final int MAX_DEPTH = 8;
    private static volatile SmartisaxAccessibilityService activeService;

    @Override
    protected void onServiceConnected() {
        activeService = this;
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                | AccessibilityEvent.TYPE_WINDOWS_CHANGED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                | AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
        info.notificationTimeout = 80L;
        setServiceInfo(info);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public boolean onUnbind(android.content.Intent intent) {
        if (activeService == this) {
            activeService = null;
        }
        return super.onUnbind(intent);
    }

    static JSONObject treeJson(Context context) {
        ensureEnabled(context);
        SmartisaxAccessibilityService service = activeService;
        JSONObject json = baseStatus(context, service);
        if (service == null) {
            return json;
        }
        JSONArray nodes = new JSONArray();
        JSONArray windows = new JSONArray();
        int[] count = new int[] {0};
        int rootCount = 0;
        AccessibilityNodeInfo root = service.getRootInActiveWindow();
        if (root != null) {
            try {
                collectNode(root, "0", 0, "active", nodes, count);
                rootCount++;
                put(json, "hasActiveRoot", true);
            } finally {
                root.recycle();
            }
        } else {
            put(json, "hasActiveRoot", false);
        }
        rootCount += collectWindowRoots(service, windows, nodes, count);
        put(json, "hasRoot", rootCount > 0);
        put(json, "rootCount", rootCount);
        put(json, "windowCount", windows.length());
        put(json, "windows", windows);
        put(json, "nodeCount", nodes.length());
        put(json, "truncated", count[0] >= MAX_NODES);
        put(json, "source", "android_accessibility_active_plus_windows");
        put(json, "nodes", nodes);
        return json;
    }

    private static int collectWindowRoots(
            SmartisaxAccessibilityService service,
            JSONArray windows,
            JSONArray nodes,
            int[] count) {
        List<AccessibilityWindowInfo> allWindows;
        try {
            allWindows = service.getWindows();
        } catch (Exception ignored) {
            return 0;
        }
        if (allWindows == null) {
            return 0;
        }
        int roots = 0;
        for (int i = 0; i < allWindows.size(); i++) {
            AccessibilityWindowInfo window = allWindows.get(i);
            if (window == null) {
                continue;
            }
            JSONObject windowJson = windowJson(window);
            AccessibilityNodeInfo windowRoot = null;
            try {
                windowRoot = window.getRoot();
                put(windowJson, "hasRoot", windowRoot != null);
                if (windowRoot != null) {
                    String windowKey = "w" + window.getId();
                    put(windowJson, "rootPath", windowKey + ":0");
                    collectNode(windowRoot, windowKey + ":0", 0, windowKey, nodes, count);
                    roots++;
                }
            } catch (Exception e) {
                put(windowJson, "rootError", shortReason(e));
            } finally {
                if (windowRoot != null) {
                    windowRoot.recycle();
                }
            }
            windows.put(windowJson);
        }
        return roots;
    }

    static JSONObject summaryJson(Context context) {
        JSONObject tree = treeJson(context);
        JSONObject summary = new JSONObject();
        put(summary, "enabledSetting", tree.optBoolean("enabledSetting", false));
        put(summary, "connected", tree.optBoolean("connected", false));
        put(summary, "hasRoot", tree.optBoolean("hasRoot", false));
        put(summary, "rootCount", tree.optInt("rootCount", 0));
        put(summary, "windowCount", tree.optInt("windowCount", 0));
        put(summary, "nodeCount", tree.optInt("nodeCount", 0));
        put(summary, "truncated", tree.optBoolean("truncated", false));
        return summary;
    }

    static JSONObject targetSummaryJson(Context context) {
        JSONObject tree = treeJson(context);
        JSONObject summary = new JSONObject();
        put(summary, "enabledSetting", tree.optBoolean("enabledSetting", false));
        put(summary, "connected", tree.optBoolean("connected", false));
        put(summary, "rootCount", tree.optInt("rootCount", 0));
        put(summary, "windowCount", tree.optInt("windowCount", 0));
        put(summary, "nodeCount", tree.optInt("nodeCount", 0));
        put(summary, "truncated", tree.optBoolean("truncated", false));
        JSONArray nodes = tree.optJSONArray("nodes");
        JSONArray samples = new JSONArray();
        int oneStepAppNodes = 0;
        int settingsNodes = 0;
        if (nodes != null) {
            for (int i = 0; i < nodes.length(); i++) {
                JSONObject node = nodes.optJSONObject(i);
                if (node == null) {
                    continue;
                }
                boolean oneStepApp = isOneStepAppNode(node);
                boolean settings = isSettingsNode(node);
                if (oneStepApp) {
                    oneStepAppNodes++;
                }
                if (settings) {
                    settingsNodes++;
                }
                if ((oneStepApp || settings) && samples.length() < 5) {
                    JSONObject sample = new JSONObject();
                    put(sample, "nodeId", node.optString("nodeId", ""));
                    put(sample, "description", trim(node.optString("description", ""), 120));
                    put(sample, "text", trim(node.optString("text", ""), 80));
                    put(sample, "package", trim(node.optString("package", ""), 80));
                    put(sample, "clickable", node.optBoolean("clickable", false));
                    put(sample, "enabled", node.optBoolean("enabled", false));
                    JSONObject bounds = node.optJSONObject("bounds");
                    if (bounds != null) {
                        put(sample, "bounds", bounds);
                    }
                    samples.put(sample);
                }
            }
        }
        put(summary, "oneStepAppNodeCount", oneStepAppNodes);
        put(summary, "settingsNodeCount", settingsNodes);
        put(summary, "sample", samples);
        return summary;
    }

    static JSONObject clickNode(Context context, String nodeId) {
        ensureEnabled(context);
        JSONObject result = new JSONObject();
        put(result, "nodeId", nodeId);
        SmartisaxAccessibilityService service = activeService;
        if (service == null) {
            put(result, "ok", false);
            put(result, "reason", "accessibility_service_not_connected");
            return result;
        }
        AccessibilityNodeInfo target = null;
        AccessibilityNodeInfo root = service.getRootInActiveWindow();
        try {
            if (root != null) {
                target = findNode(root, "0", nodeId);
                if (target != null) {
                    put(result, "source", "active");
                }
            }
            if (target == null) {
                target = findNodeInWindows(service, nodeId, result);
            }
            if (target == null) {
                put(result, "ok", false);
                put(result, "reason", "accessibility_node_not_found");
                return result;
            }
            put(result, "node", nodeJson(target, "target", 0, result.optString("source", "")));
            AccessibilityNodeInfo clickable = target;
            while (clickable != null && !clickable.isClickable()) {
                AccessibilityNodeInfo parent = clickable.getParent();
                if (clickable != target) {
                    clickable.recycle();
                }
                clickable = parent;
            }
            if (clickable == null) {
                put(result, "ok", false);
                put(result, "reason", "accessibility_node_not_clickable");
                return result;
            }
            boolean performed = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            put(result, "ok", performed);
            put(result, "performed", performed);
            put(result, "clickedAncestor", clickable != target);
            if (!performed) {
                put(result, "reason", "accessibility_click_rejected");
            }
            if (clickable != target) {
                clickable.recycle();
            }
            return result;
        } finally {
            if (target != null) {
                target.recycle();
            }
            if (root != null) {
                root.recycle();
            }
        }
    }

    private static void ensureEnabled(Context context) {
        if (context == null) {
            return;
        }
        try {
            ComponentName component = new ComponentName(
                    context.getPackageName(), SmartisaxAccessibilityService.class.getName());
            String flattened = component.flattenToString();
            String enabled = Settings.Secure.getString(
                    context.getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            if (enabled == null || !containsService(enabled, flattened)) {
                String next = TextUtils.isEmpty(enabled) ? flattened : enabled + ":" + flattened;
                Settings.Secure.putString(
                        context.getContentResolver(),
                        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                        next);
            }
            Settings.Secure.putInt(
                    context.getContentResolver(), Settings.Secure.ACCESSIBILITY_ENABLED, 1);
        } catch (Exception ignored) {
        }
    }

    private static boolean containsService(String enabled, String service) {
        if (enabled == null || service == null) {
            return false;
        }
        String[] parts = enabled.split(":");
        for (String part : parts) {
            if (service.equals(part)) {
                return true;
            }
        }
        return false;
    }

    private static JSONObject baseStatus(Context context, SmartisaxAccessibilityService service) {
        JSONObject json = new JSONObject();
        put(json, "enabledSetting", isEnabledSetting(context));
        put(json, "connected", service != null);
        put(json, "source", "android_accessibility");
        return json;
    }

    private static boolean isEnabledSetting(Context context) {
        if (context == null) {
            return false;
        }
        try {
            ComponentName component = new ComponentName(
                    context.getPackageName(), SmartisaxAccessibilityService.class.getName());
            String enabled = Settings.Secure.getString(
                    context.getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            return containsService(enabled, component.flattenToString());
        } catch (Exception ignored) {
            return false;
        }
    }

    private static void collectNode(
            AccessibilityNodeInfo node,
            String path,
            int depth,
            String source,
            JSONArray nodes,
            int[] count) {
        if (node == null || depth > MAX_DEPTH || count[0] >= MAX_NODES) {
            return;
        }
        if (isUseful(node)) {
            nodes.put(nodeJson(node, path, depth, source));
            count[0]++;
        }
        int children = node.getChildCount();
        for (int i = 0; i < children && count[0] < MAX_NODES; i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) {
                continue;
            }
            try {
                collectNode(child, path + "." + i, depth + 1, source, nodes, count);
            } finally {
                child.recycle();
            }
        }
    }

    private static AccessibilityNodeInfo findNode(
            AccessibilityNodeInfo node,
            String path,
            String wantedId) {
        if (node == null) {
            return null;
        }
        if (nodeId(node, path).equals(wantedId)) {
            return AccessibilityNodeInfo.obtain(node);
        }
        int children = node.getChildCount();
        for (int i = 0; i < children; i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) {
                continue;
            }
            try {
                AccessibilityNodeInfo found = findNode(child, path + "." + i, wantedId);
                if (found != null) {
                    return found;
                }
            } finally {
                child.recycle();
            }
        }
        return null;
    }

    private static AccessibilityNodeInfo findNodeInWindows(
            SmartisaxAccessibilityService service,
            String wantedId,
            JSONObject result) {
        List<AccessibilityWindowInfo> allWindows;
        try {
            allWindows = service.getWindows();
        } catch (Exception e) {
            put(result, "windowSearchError", shortReason(e));
            return null;
        }
        if (allWindows == null) {
            put(result, "windowSearch", "unavailable");
            return null;
        }
        for (int i = 0; i < allWindows.size(); i++) {
            AccessibilityWindowInfo window = allWindows.get(i);
            if (window == null) {
                continue;
            }
            AccessibilityNodeInfo root = null;
            try {
                root = window.getRoot();
                if (root == null) {
                    continue;
                }
                String windowKey = "w" + window.getId();
                AccessibilityNodeInfo found = findNode(root, windowKey + ":0", wantedId);
                if (found != null) {
                    put(result, "source", windowKey);
                    put(result, "windowId", window.getId());
                    put(result, "windowType", windowTypeName(window.getType()));
                    return found;
                }
            } catch (Exception e) {
                put(result, "windowSearchError", shortReason(e));
            } finally {
                if (root != null) {
                    root.recycle();
                }
            }
        }
        return null;
    }

    private static boolean isUseful(AccessibilityNodeInfo node) {
        return node.isClickable()
                || node.isLongClickable()
                || node.isScrollable()
                || node.isEditable()
                || hasText(node)
                || safeString(node.getViewIdResourceName()).length() > 0;
    }

    private static boolean hasText(AccessibilityNodeInfo node) {
        return safeString(node.getText()).length() > 0
                || safeString(node.getContentDescription()).length() > 0;
    }

    private static boolean isOneStepAppNode(JSONObject node) {
        return node.optString("description", "").startsWith("smartisax:onestep:app|");
    }

    private static boolean isSettingsNode(JSONObject node) {
        String value = (node.optString("package", "") + "|"
                + node.optString("text", "") + "|"
                + node.optString("description", "") + "|"
                + node.optString("viewId", "")).toLowerCase(Locale.US);
        return value.contains("com.android.settings")
                || value.contains("package=com.android.settings")
                || value.contains("settings")
                || value.contains("设置");
    }

    private static JSONObject nodeJson(
            AccessibilityNodeInfo node,
            String path,
            int depth,
            String source) {
        JSONObject json = new JSONObject();
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        put(json, "nodeId", nodeId(node, path));
        put(json, "path", path);
        put(json, "depth", depth);
        if (source != null && source.length() > 0) {
            put(json, "source", source);
        }
        put(json, "package", safeString(node.getPackageName()));
        put(json, "class", shortClassName(safeString(node.getClassName())));
        put(json, "text", trim(safeString(node.getText()), 80));
        put(json, "description", trim(safeString(node.getContentDescription()), 80));
        put(json, "viewId", trim(safeString(node.getViewIdResourceName()), 120));
        JSONObject boundsJson = new JSONObject();
        put(boundsJson, "left", bounds.left);
        put(boundsJson, "top", bounds.top);
        put(boundsJson, "right", bounds.right);
        put(boundsJson, "bottom", bounds.bottom);
        put(json, "bounds", boundsJson);
        put(json, "clickable", node.isClickable());
        put(json, "enabled", node.isEnabled());
        put(json, "focusable", node.isFocusable());
        put(json, "scrollable", node.isScrollable());
        put(json, "editable", node.isEditable());
        return json;
    }

    private static JSONObject windowJson(AccessibilityWindowInfo window) {
        JSONObject json = new JSONObject();
        Rect bounds = new Rect();
        try {
            window.getBoundsInScreen(bounds);
        } catch (Exception ignored) {
        }
        put(json, "id", window.getId());
        put(json, "type", windowTypeName(window.getType()));
        put(json, "active", window.isActive());
        put(json, "focused", window.isFocused());
        put(json, "layer", window.getLayer());
        put(json, "title", trim(safeString(window.getTitle()), 80));
        JSONObject boundsJson = new JSONObject();
        put(boundsJson, "left", bounds.left);
        put(boundsJson, "top", bounds.top);
        put(boundsJson, "right", bounds.right);
        put(boundsJson, "bottom", bounds.bottom);
        put(json, "bounds", boundsJson);
        return json;
    }

    private static String windowTypeName(int type) {
        switch (type) {
            case AccessibilityWindowInfo.TYPE_APPLICATION:
                return "APPLICATION";
            case AccessibilityWindowInfo.TYPE_INPUT_METHOD:
                return "INPUT_METHOD";
            case AccessibilityWindowInfo.TYPE_SYSTEM:
                return "SYSTEM";
            case AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY:
                return "ACCESSIBILITY_OVERLAY";
            case AccessibilityWindowInfo.TYPE_SPLIT_SCREEN_DIVIDER:
                return "SPLIT_SCREEN_DIVIDER";
            default:
                return "UNKNOWN_" + type;
        }
    }

    private static String shortReason(Exception e) {
        if (e == null) {
            return "";
        }
        String name = e.getClass().getSimpleName();
        String message = e.getMessage();
        if (message == null || message.length() == 0) {
            return name;
        }
        return trim(name + ":" + message, 120);
    }

    private static String nodeId(AccessibilityNodeInfo node, String path) {
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        String raw = safeString(node.getPackageName()) + "|"
                + safeString(node.getClassName()) + "|"
                + safeString(node.getViewIdResourceName()) + "|"
                + safeString(node.getText()) + "|"
                + safeString(node.getContentDescription()) + "|"
                + bounds.flattenToString() + "|"
                + path;
        return "n" + sha1(raw).substring(0, 10);
    }

    private static String sha1(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-1");
            byte[] bytes = digest.digest(value.getBytes("UTF-8"));
            StringBuilder builder = new StringBuilder();
            for (byte b : bytes) {
                builder.append(String.format(Locale.US, "%02x", b & 0xff));
            }
            return builder.toString();
        } catch (Exception e) {
            return Integer.toHexString(value.hashCode()) + "0000000000";
        }
    }

    private static String shortClassName(String value) {
        int dot = value.lastIndexOf('.');
        return dot >= 0 && dot + 1 < value.length() ? value.substring(dot + 1) : value;
    }

    private static String trim(String value, int max) {
        if (value == null) {
            return "";
        }
        String clean = value.replace('\n', ' ').replace('\r', ' ').trim();
        return clean.length() <= max ? clean : clean.substring(0, max);
    }

    private static String safeString(CharSequence value) {
        return value == null ? "" : value.toString();
    }

    private static void put(JSONObject json, String key, Object value) {
        try {
            json.put(key, value);
        } catch (JSONException ignored) {
        }
    }
}
