package com.smartisax.browser;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxAgentConfig {
    static final String PROVIDER_AUTO = "auto";
    static final String PROVIDER_MIMO = "mimo_v25_vision";
    static final String PROVIDER_DEEPSEEK = "deepseek_text";
    static final String PROVIDER_MOCK = "mock";
    static final String DEFAULT_MIMO_MODEL = "mimo-v2.5";
    static final String DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-flash";
    static final String DEFAULT_MIMO_CHAT_URL = "https://api.xiaomimimo.com/v1/chat/completions";
    static final String DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com";
    private static final String PREFS = "smartisax_agent";
    private static final String KEY_PROVIDER = "provider";
    private static final String KEY_MIMO_API_KEY = "mimo_api_key";
    private static final String KEY_DEEPSEEK_API_KEY = "deepseek_api_key";

    final String providerPreference;
    final String mimoApiKey;
    final String deepSeekApiKey;
    final String mimoChatUrl;
    final String deepSeekBaseUrl;
    final String mimoModel;
    final String deepSeekModel;

    private SmartisaxAgentConfig(
            String providerPreference,
            String mimoApiKey,
            String deepSeekApiKey,
            String mimoChatUrl,
            String deepSeekBaseUrl,
            String mimoModel,
            String deepSeekModel) {
        this.providerPreference = providerPreference;
        this.mimoApiKey = mimoApiKey;
        this.deepSeekApiKey = deepSeekApiKey;
        this.mimoChatUrl = mimoChatUrl;
        this.deepSeekBaseUrl = deepSeekBaseUrl;
        this.mimoModel = mimoModel;
        this.deepSeekModel = deepSeekModel;
    }

    static SmartisaxAgentConfig load(Context context) {
        SharedPreferences prefs = context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        return new SmartisaxAgentConfig(
                normalizeProvider(prefs.getString(KEY_PROVIDER, PROVIDER_AUTO)),
                prefs.getString(KEY_MIMO_API_KEY, ""),
                prefs.getString(KEY_DEEPSEEK_API_KEY, ""),
                DEFAULT_MIMO_CHAT_URL,
                DEFAULT_DEEPSEEK_BASE_URL,
                DEFAULT_MIMO_MODEL,
                DEFAULT_DEEPSEEK_MODEL);
    }

    static void save(Context context, JSONObject json) {
        SharedPreferences prefs = context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();
        editor.putString(KEY_PROVIDER, normalizeProvider(json.optString("provider", PROVIDER_AUTO)));
        updateSecret(editor, KEY_MIMO_API_KEY, json.optString("mimoApiKey", null));
        updateSecret(editor, KEY_DEEPSEEK_API_KEY, json.optString("deepSeekApiKey", null));
        editor.apply();
    }

    String selectedProviderId() {
        if (PROVIDER_AUTO.equals(providerPreference)) {
            if (hasMimoKey()) {
                return PROVIDER_MIMO;
            }
            if (hasDeepSeekKey()) {
                return PROVIDER_DEEPSEEK;
            }
            return "";
        }
        return providerPreference;
    }

    boolean hasMimoKey() {
        return mimoApiKey != null && mimoApiKey.trim().length() > 0;
    }

    boolean hasDeepSeekKey() {
        return deepSeekApiKey != null && deepSeekApiKey.trim().length() > 0;
    }

    String deepSeekChatUrl() {
        String base = trimTrailingSlash(deepSeekBaseUrl);
        if (base.endsWith("/chat/completions")) {
            return base;
        }
        return base + "/chat/completions";
    }

    JSONObject redactedJson() throws JSONException {
        JSONObject json = new JSONObject();
        json.put("provider", providerPreference);
        json.put("selectedProvider", selectedProviderId());
        json.put("mimoKeySet", hasMimoKey());
        json.put("deepSeekKeySet", hasDeepSeekKey());
        json.put("mimoModel", mimoModel);
        json.put("deepSeekModel", deepSeekModel);
        json.put("mimoChatUrl", mimoChatUrl);
        json.put("deepSeekBaseUrl", deepSeekBaseUrl);
        return json;
    }

    String redact(String value) {
        String result = value == null ? "" : value;
        if (hasMimoKey()) {
            result = result.replace(mimoApiKey, "[mimo-api-key]");
        }
        if (hasDeepSeekKey()) {
            result = result.replace(deepSeekApiKey, "[deepseek-api-key]");
        }
        return result;
    }

    private static void updateSecret(SharedPreferences.Editor editor, String key, String value) {
        if (value == null) {
            return;
        }
        String trimmed = value.trim();
        if ("__clear__".equals(trimmed)) {
            editor.remove(key);
            return;
        }
        if (trimmed.length() > 0) {
            editor.putString(key, trimmed);
        }
    }

    private static String normalizeProvider(String provider) {
        String value = provider == null ? PROVIDER_AUTO : provider.trim();
        if (PROVIDER_MIMO.equals(value)
                || PROVIDER_DEEPSEEK.equals(value)
                || PROVIDER_MOCK.equals(value)
                || PROVIDER_AUTO.equals(value)) {
            return value;
        }
        return PROVIDER_AUTO;
    }

    private static String trimTrailingSlash(String value) {
        String result = value == null ? "" : value.trim();
        while (result.endsWith("/") && result.length() > 1) {
            result = result.substring(0, result.length() - 1);
        }
        return result.length() == 0 ? DEFAULT_DEEPSEEK_BASE_URL : result;
    }
}
