package com.smartisax.browser;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxAgentProviders {
    private SmartisaxAgentProviders() {
    }

    static SmartisaxAgentProvider create(String id) throws IOException {
        if (SmartisaxAgentConfig.PROVIDER_MIMO.equals(id)) {
            return new MimoVisionProvider();
        }
        if (SmartisaxAgentConfig.PROVIDER_DEEPSEEK.equals(id)) {
            return new DeepSeekTextProvider();
        }
        if (SmartisaxAgentConfig.PROVIDER_MOCK.equals(id)) {
            return new MockProvider();
        }
        throw new IOException("unknown_agent_provider_" + id);
    }

    private static final class MimoVisionProvider implements SmartisaxAgentProvider {
        @Override
        public String id() {
            return SmartisaxAgentConfig.PROVIDER_MIMO;
        }

        @Override
        public boolean needsVision() {
            return true;
        }

        @Override
        public SmartisaxAgentAction plan(SmartisaxAgentRuntime.StepRequest request) throws Exception {
            if (!request.config.hasMimoKey()) {
                throw new IOException("missing_mimo_api_key");
            }
            networkPreflight(request.config.mimoChatUrl);
            JSONObject body = chatEnvelope(request.config.mimoModel);
            JSONArray messages = new JSONArray();
            messages.put(systemMessage(true));
            JSONArray content = new JSONArray();
            content.put(new JSONObject()
                    .put("type", "text")
                    .put("text", stepPrompt(request, true)));
            content.put(new JSONObject()
                    .put("type", "image_url")
                    .put("image_url", new JSONObject()
                            .put("url", request.observation.jpegDataUrl())));
            messages.put(new JSONObject()
                    .put("role", "user")
                    .put("content", content));
            body.put("messages", messages);
            return actionFromChatResponse(postJson(
                    request.config.mimoChatUrl,
                    request.config.mimoApiKey,
                    body));
        }
    }

    private static final class DeepSeekTextProvider implements SmartisaxAgentProvider {
        @Override
        public String id() {
            return SmartisaxAgentConfig.PROVIDER_DEEPSEEK;
        }

        @Override
        public boolean needsVision() {
            return false;
        }

        @Override
        public SmartisaxAgentAction plan(SmartisaxAgentRuntime.StepRequest request) throws Exception {
            if (!request.config.hasDeepSeekKey()) {
                throw new IOException("missing_deepseek_api_key");
            }
            networkPreflight(request.config.deepSeekChatUrl());
            JSONObject body = chatEnvelope(request.config.deepSeekModel);
            JSONArray messages = new JSONArray();
            messages.put(systemMessage(false));
            messages.put(new JSONObject()
                    .put("role", "user")
                    .put("content", stepPrompt(request, false)));
            body.put("messages", messages);
            return actionFromChatResponse(postJson(
                    request.config.deepSeekChatUrl(),
                    request.config.deepSeekApiKey,
                    body));
        }
    }

    private static final class MockProvider implements SmartisaxAgentProvider {
        @Override
        public String id() {
            return SmartisaxAgentConfig.PROVIDER_MOCK;
        }

        @Override
        public boolean needsVision() {
            return false;
        }

        @Override
        public SmartisaxAgentAction plan(SmartisaxAgentRuntime.StepRequest request) throws Exception {
            JSONObject json = new JSONObject();
            if (request.stepIndex <= 1 && !request.goal.toLowerCase().contains("finish")) {
                json.put("type", "wait");
                json.put("durationMs", 500);
                json.put("confidence", 0.8d);
                json.put("summary", "mock first step");
            } else {
                json.put("type", "finish");
                json.put("confidence", 0.9d);
                json.put("message", "Mock provider completed the task.");
                json.put("summary", "mock finish");
            }
            return SmartisaxAgentAction.fromJson(json);
        }
    }

    private static JSONObject chatEnvelope(String model) throws JSONException {
        JSONObject body = new JSONObject();
        body.put("model", model);
        body.put("temperature", 0.1d);
        body.put("max_tokens", 600);
        body.put("response_format", new JSONObject().put("type", "json_object"));
        return body;
    }

    private static JSONObject systemMessage(boolean hasVision) throws JSONException {
        String vision = hasVision
                ? "You can inspect the attached phone screenshot directly."
                : "You cannot see the screen image. If the next action requires visual context, return ask_user.";
        return new JSONObject()
                .put("role", "system")
                .put("content",
                        "You are Smartisax Agent running on a Smartisan R2 phone. "
                                + vision + " Return exactly one strict JSON object and no markdown. "
                                + "Allowed action schema: " + SmartisaxAgentAction.schemaText() + ". "
                                + "If accessibilityTree has a suitable enabled clickable node, prefer click_node with that nodeId over tap. "
                                + "Only use tap when no reliable accessibility node exists for the target. "
                                + "Coordinates are normalized integers from 0 to 10000 over the whole phone screen. "
                                + "When tapping a visible icon or control, choose the visual center of that target. "
                                + "Avoid tap y coordinates in the top or bottom 10 percent unless the goal explicitly targets a system edge. "
                                + "Use one_step with operation enter to open Smartisan One Step/right sidebar; "
                                + "use one_step with operation exit to close it. Prefer this semantic action over guessing edge swipes. "
                                + "If systemState.oneStep.visible is true and the goal does not need One Step, exit it before normal app taps. "
                                + "Smartisax Shell may be the phone HOME app; if foreground.isSmartisaxShell is true, pressing HOME can keep the same Shell screen. "
                                + "If foreground.isSettings is true for a Settings goal, the target app is already visible and finish is allowed. "
                                + "For goals that open the Settings app from Smartisax Shell, use a Settings accessibility node if present; otherwise use one_step enter and then tap the gear-shaped Settings icon in the One Step top app strip. "
                                + "After any tap, swipe, key, one_step, or click_node action, wait for the next screenshot observation before returning finish, unless the latest foreground/accessibility state already confirms the target app is visible. "
                                + "Never request shell, root, adb, fastboot, file deletion, data clearing, or privileged commands.");
    }

    private static String stepPrompt(SmartisaxAgentRuntime.StepRequest request, boolean hasVision)
            throws JSONException {
        JSONObject json = new JSONObject();
        json.put("goal", request.goal);
        json.put("step", request.stepIndex);
        json.put("maxSteps", SmartisaxAgentRuntime.MAX_STEPS);
        json.put("provider", request.providerId);
        json.put("vision", hasVision ? "screenshot_attached" : "not_available");
        json.put("display", request.displayJson);
        json.put("systemState", request.systemState);
        json.put("accessibilityTree", request.accessibilityTree);
        json.put("lastResult", request.lastResult);
        json.put("history", request.history);
        json.put("actionSchema", SmartisaxAgentAction.schemaText());
        json.put("instruction",
                "Choose exactly one safe next action. Prefer finish when the goal is already satisfied. "
                        + "Prefer click_node for enabled clickable accessibilityTree.nodes that match the intended target. "
                        + "Use tap only when the target has no reliable accessibility node. "
                        + "Use one_step enter/exit for Smartisan One Step mode instead of inventing screen-edge coordinates. "
                        + "If systemState.oneStep.visible=true and the goal is unrelated to One Step, use one_step exit first. "
                        + "If the goal is to open Settings and foreground.isSmartisaxShell=true, do not press HOME repeatedly; "
                        + "if foreground.isSettings=true, return finish. "
                        + "use a Settings accessibility node if present, otherwise enter One Step and tap the gear-shaped Settings icon in the top app strip. "
                        + "If history shows key(HOME) with postActionCheck.screenChanged=false, never return HOME again. "
                        + "If history shows a tap/swipe/key/one_step/click_node action without postActionCheck.screenChanged=true, do not finish; "
                        + "try a better grounded action or ask_user, unless systemState.foreground or accessibilityTree confirms the target app is already visible. "
                        + "Use ask_user when the safe next step is ambiguous.");
        return json.toString();
    }

    private static SmartisaxAgentAction actionFromChatResponse(String response)
            throws IOException, JSONException {
        JSONObject root = new JSONObject(response);
        JSONArray choices = root.optJSONArray("choices");
        if (choices == null || choices.length() == 0) {
            throw new IOException("provider_response_missing_choices");
        }
        JSONObject choice = choices.optJSONObject(0);
        JSONObject message = choice == null ? null : choice.optJSONObject("message");
        if (message == null) {
            throw new IOException("provider_response_missing_message");
        }
        String content = message.optString("content", "");
        if (content.length() == 0) {
            JSONArray toolCalls = message.optJSONArray("tool_calls");
            if (toolCalls != null && toolCalls.length() > 0) {
                JSONObject function = toolCalls.optJSONObject(0).optJSONObject("function");
                content = function == null ? "" : function.optString("arguments", "");
            }
        }
        return SmartisaxAgentAction.parseModelText(content);
    }

    private static String postJson(String url, String apiKey, JSONObject body) throws IOException {
        HttpURLConnection connection = null;
        String host = hostOf(url);
        try {
            connection = (HttpURLConnection) new URL(url).openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(6000);
            connection.setReadTimeout(20000);
            connection.setDoOutput(true);
            connection.setRequestProperty("Authorization", "Bearer " + apiKey);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            byte[] data = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setFixedLengthStreamingMode(data.length);
            OutputStream out = connection.getOutputStream();
            try {
                out.write(data);
            } finally {
                out.close();
            }
            int code = connection.getResponseCode();
            String response = readBody(code >= 200 && code < 300
                    ? connection.getInputStream()
                    : connection.getErrorStream());
            if (code < 200 || code >= 300) {
                throw new IOException("provider_http_" + code + " " + limit(response, 280));
            }
            return response;
        } catch (UnknownHostException e) {
            throw new IOException("provider_network_dns_unavailable host=" + host, e);
        } catch (SocketTimeoutException e) {
            throw new IOException("provider_request_timeout host=" + host, e);
        } catch (SocketException e) {
            throw new IOException("provider_network_unavailable host=" + host
                    + " error=" + limit(e.getMessage(), 120), e);
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private static void networkPreflight(String url) throws IOException {
        String host = hostOf(url);
        if (host.length() == 0) {
            throw new IOException("provider_network_invalid_host");
        }
        try {
            InetAddress.getByName(host);
        } catch (UnknownHostException e) {
            throw new IOException("provider_network_dns_unavailable host=" + host, e);
        }
    }

    private static String hostOf(String url) throws IOException {
        try {
            return new URL(url).getHost();
        } catch (Exception e) {
            throw new IOException("provider_network_invalid_url", e);
        }
    }

    private static String readBody(InputStream stream) throws IOException {
        if (stream == null) {
            return "";
        }
        BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8));
        StringBuilder builder = new StringBuilder();
        try {
            String line;
            while ((line = reader.readLine()) != null) {
                if (builder.length() + line.length() > 128 * 1024) {
                    throw new IOException("provider_response_too_large");
                }
                builder.append(line);
            }
        } finally {
            reader.close();
        }
        return builder.toString();
    }

    private static String limit(String value, int max) {
        if (value == null) {
            return "";
        }
        return value.length() <= max ? value : value.substring(0, max);
    }
}
