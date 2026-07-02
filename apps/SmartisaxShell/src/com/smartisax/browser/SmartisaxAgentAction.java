package com.smartisax.browser;

import java.io.IOException;
import java.util.Locale;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxAgentAction {
    static final double LOW_CONFIDENCE_THRESHOLD = 0.35d;

    final String type;
    final int x;
    final int y;
    final int x1;
    final int y1;
    final int x2;
    final int y2;
    final int durationMs;
    final String key;
    final String operation;
    final String nodeId;
    final String message;
    final String summary;
    final double confidence;

    private SmartisaxAgentAction(
            String type,
            int x,
            int y,
            int x1,
            int y1,
            int x2,
            int y2,
            int durationMs,
            String key,
            String operation,
            String nodeId,
            String message,
            String summary,
            double confidence) {
        this.type = type;
        this.x = x;
        this.y = y;
        this.x1 = x1;
        this.y1 = y1;
        this.x2 = x2;
        this.y2 = y2;
        this.durationMs = durationMs;
        this.key = key;
        this.operation = operation;
        this.nodeId = nodeId;
        this.message = message;
        this.summary = summary;
        this.confidence = confidence;
    }

    static SmartisaxAgentAction parseModelText(String text) throws IOException, JSONException {
        JSONObject root = new JSONObject(extractJsonObject(text));
        Object actionValue = root.opt("action");
        JSONObject actionJson = actionValue instanceof JSONObject ? (JSONObject) actionValue : root;
        if (actionValue instanceof String && !actionJson.has("type")) {
            actionJson.put("type", (String) actionValue);
        }
        return fromJson(actionJson);
    }

    static SmartisaxAgentAction fromJson(JSONObject json) throws IOException {
        String rawType = json.optString("type", json.optString("action", "")).trim();
        String type = rawType.toLowerCase(Locale.US).replace('-', '_');
        if ("press_key".equals(type)) {
            type = "key";
        }
        if ("onestep".equals(type) || "one_step_mode".equals(type) || "sidebar".equals(type)) {
            type = "one_step";
        }
        if ("done".equals(type) || "complete".equals(type)) {
            type = "finish";
        }
        double confidence = json.has("confidence") ? json.optDouble("confidence", 0.0d) : 0.5d;
        String summary = trim(json.optString("summary", json.optString("reason", "")), 160);
        if ("tap".equals(type)) {
            return new SmartisaxAgentAction(
                    type,
                    normalized(json, "x"),
                    normalized(json, "y"),
                    -1,
                    -1,
                    -1,
                    -1,
                    0,
                    "",
                    "",
                    "",
                    "",
                    summary,
                    confidence);
        }
        if ("swipe".equals(type)) {
            return new SmartisaxAgentAction(
                    type,
                    -1,
                    -1,
                    normalized(json, "x1"),
                    normalized(json, "y1"),
                    normalized(json, "x2"),
                    normalized(json, "y2"),
                    clamp(json.optInt("durationMs", json.optInt("duration", 240)), 50, 1500),
                    "",
                    "",
                    "",
                    "",
                    summary,
                    confidence);
        }
        if ("key".equals(type)) {
            String key = json.optString("key", "").trim().toUpperCase(Locale.US);
            if (!"BACK".equals(key) && !"HOME".equals(key)) {
                throw new IOException("unsupported_key_" + key);
            }
            return new SmartisaxAgentAction(
                    type, -1, -1, -1, -1, -1, -1, 0, key, "", "", "", summary, confidence);
        }
        if ("wait".equals(type)) {
            return new SmartisaxAgentAction(
                    type,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    clamp(json.optInt("durationMs", json.optInt("duration", 750)), 250, 5000),
                    "",
                    "",
                    "",
                    "",
                    summary,
                    confidence);
        }
        if ("one_step".equals(type)) {
            return new SmartisaxAgentAction(
                    type,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    0,
                    "",
                    normalizedOperation(json),
                    "",
                    "",
                    summary,
                    confidence);
        }
        if ("click_node".equals(type) || "node_click".equals(type) || "accessibility_click".equals(type)) {
            return new SmartisaxAgentAction(
                    "click_node",
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    0,
                    "",
                    "",
                    normalizedNodeId(json),
                    "",
                    summary,
                    confidence);
        }
        if ("finish".equals(type)) {
            return new SmartisaxAgentAction(
                    type,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    -1,
                    0,
                    "",
                    "",
                    "",
                    trim(json.optString("message", summary), 220),
                    summary,
                    Math.max(confidence, 0.5d));
        }
        if ("ask_user".equals(type)) {
            String message = trim(json.optString("message", "Need user input before continuing."), 220);
            return new SmartisaxAgentAction(
                    type, -1, -1, -1, -1, -1, -1, 0, "", "", "", message, summary, confidence);
        }
        throw new IOException("unsupported_agent_action_" + rawType);
    }

    boolean isLowConfidence() {
        return confidence < LOW_CONFIDENCE_THRESHOLD;
    }

    JSONObject toJson() throws JSONException {
        JSONObject json = new JSONObject();
        json.put("type", type);
        json.put("confidence", confidence);
        if (summary.length() > 0) {
            json.put("summary", summary);
        }
        if ("tap".equals(type)) {
            json.put("x", x);
            json.put("y", y);
        } else if ("swipe".equals(type)) {
            json.put("x1", x1);
            json.put("y1", y1);
            json.put("x2", x2);
            json.put("y2", y2);
            json.put("durationMs", durationMs);
        } else if ("key".equals(type)) {
            json.put("key", key);
        } else if ("wait".equals(type)) {
            json.put("durationMs", durationMs);
        } else if ("one_step".equals(type)) {
            json.put("operation", operation);
        } else if ("click_node".equals(type)) {
            json.put("nodeId", nodeId);
        } else if ("ask_user".equals(type) || "finish".equals(type)) {
            json.put("message", message);
        }
        return json;
    }

    static String schemaText() {
        return "{"
                + "\"type\":\"click_node|tap|swipe|key|wait|one_step|finish|ask_user\","
                + "\"confidence\":0.0-1.0,"
                + "\"summary\":\"short reason\","
                + "\"nodeId\":\"nodeId from accessibilityTree.nodes, for click_node\","
                + "\"x\":0-10000,\"y\":0-10000,"
                + "\"x1\":0-10000,\"y1\":0-10000,\"x2\":0-10000,\"y2\":0-10000,"
                + "\"durationMs\":250-5000,"
                + "\"key\":\"BACK|HOME\","
                + "\"operation\":\"enter|exit\","
                + "\"message\":\"only for finish or ask_user\""
                + "}";
    }

    private static String normalizedNodeId(JSONObject json) throws IOException {
        String value = json.optString("nodeId", json.optString("node_id", "")).trim();
        if (!value.matches("n[0-9a-fA-F]{10}")) {
            throw new IOException("invalid_accessibility_node_id");
        }
        return value;
    }

    private static String normalizedOperation(JSONObject json) throws IOException {
        String raw = json.optString("operation",
                json.optString("mode", json.optString("state", ""))).trim();
        String operation = raw.toLowerCase(Locale.US).replace('-', '_');
        if ("open".equals(operation) || "show".equals(operation) || "right".equals(operation)
                || "enter_right".equals(operation) || "enter".equals(operation)
                || "start".equals(operation)) {
            return "enter";
        }
        if ("close".equals(operation) || "hide".equals(operation) || "leave".equals(operation)
                || "reset".equals(operation) || "off".equals(operation) || "exit".equals(operation)
                || "stop".equals(operation)) {
            return "exit";
        }
        throw new IOException("unsupported_one_step_operation_" + raw);
    }

    private static int normalized(JSONObject json, String key) throws IOException {
        if (!json.has(key)) {
            throw new IOException("missing_coordinate_" + key);
        }
        int value = json.optInt(key, -1);
        if (value < 0 || value > 10000) {
            throw new IOException("coordinate_out_of_range_" + key);
        }
        return value;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static String trim(String value, int max) {
        if (value == null) {
            return "";
        }
        String trimmed = value.trim();
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
    }

    private static String extractJsonObject(String text) throws IOException {
        if (text == null) {
            throw new IOException("empty_model_response");
        }
        int start = text.indexOf('{');
        if (start < 0) {
            throw new IOException("model_response_missing_json_object");
        }
        boolean inString = false;
        boolean escaped = false;
        int depth = 0;
        for (int i = start; i < text.length(); i++) {
            char c = text.charAt(i);
            if (escaped) {
                escaped = false;
                continue;
            }
            if (c == '\\') {
                escaped = inString;
                continue;
            }
            if (c == '"') {
                inString = !inString;
                continue;
            }
            if (inString) {
                continue;
            }
            if (c == '{') {
                depth += 1;
            } else if (c == '}') {
                depth -= 1;
                if (depth == 0) {
                    return text.substring(start, i + 1);
                }
            }
        }
        throw new IOException("model_response_unclosed_json_object");
    }
}
