package com.smartisax.browser;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.graphics.Rect;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.os.Build;
import android.os.IBinder;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Range;
import android.view.Display;
import android.view.WindowManager;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.lang.reflect.Method;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class DevicePortalService extends Service {
    public static final String ACTION_START = "com.smartisax.browser.portal.START";
    public static final String ACTION_STOP = "com.smartisax.browser.portal.STOP";
    public static final String EXTRA_START_REASON = "com.smartisax.browser.portal.START_REASON";
    public static final int PORT = 37601;
    private static final String PORTAL_VERSION = "0.7.10";
    private static final String PORTAL_VARIANT = "v0.agent0.10-finish-target-verify";
    private static final String PORTAL_WEBRTC = "native-libwebrtc-dtls-srtp-screen";
    private static final String PORTAL_PLAYBACK = "native-webrtc-default";
    private static final String PREFS = "smartisax_portal";
    private static final String PREF_AUTO_START = "auto_start";
    private static final int MAX_BAD_PAIR_ATTEMPTS = 8;
    private static final long BAD_PAIR_LOCKOUT_MS = 30000L;
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Object LOCK = new Object();
    private static PortalServer server;
    private static PortalSnapshot lastSnapshot = PortalSnapshot.stopped("");

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopPortal();
            stopSelf();
            return START_NOT_STICKY;
        }
        startPortal(intent == null ? "service_start" : intent.getStringExtra(EXTRA_START_REASON));
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        stopPortal();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    public static PortalSnapshot snapshot() {
        synchronized (LOCK) {
            return lastSnapshot;
        }
    }

    public static boolean isAutoStartEnabled(Context context) {
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(PREF_AUTO_START, false);
    }

    public static void setAutoStartEnabled(Context context, boolean enabled) {
        SharedPreferences prefs = context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        prefs.edit().putBoolean(PREF_AUTO_START, enabled).apply();
    }

    public static void requestStart(Context context, String reason) {
        Intent intent = new Intent(context, DevicePortalService.class);
        intent.setAction(ACTION_START);
        intent.putExtra(EXTRA_START_REASON, reason == null || reason.length() == 0 ? "external_start" : reason);
        context.startService(intent);
    }

    private void startPortal(String reason) {
        synchronized (LOCK) {
            if (server != null && server.isRunning()) {
                lastSnapshot = server.snapshot();
                return;
            }
            String ip = wlanIpv4();
            if (ip.length() == 0) {
                lastSnapshot = PortalSnapshot.stopped("no_wlan_ipv4");
                return;
            }
            PortalServer next = new PortalServer(this, ip, PORT, randomToken(), randomPairingCode(),
                    reason == null || reason.length() == 0 ? "service_start" : reason);
            if (!next.start()) {
                lastSnapshot = PortalSnapshot.stopped(next.lastError());
                return;
            }
            server = next;
            lastSnapshot = next.snapshot();
        }
    }

    private static void stopPortal() {
        synchronized (LOCK) {
            if (server != null) {
                server.stop();
                server = null;
            }
            lastSnapshot = PortalSnapshot.stopped("stopped");
        }
    }

    private static String randomToken() {
        byte[] bytes = new byte[24];
        RANDOM.nextBytes(bytes);
        return android.util.Base64.encodeToString(
                bytes, android.util.Base64.URL_SAFE | android.util.Base64.NO_WRAP | android.util.Base64.NO_PADDING);
    }

    private static String randomPairingCode() {
        return String.format(Locale.US, "%06d", RANDOM.nextInt(1000000));
    }

    private static String wlanIpv4() {
        try {
            for (NetworkInterface iface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!"wlan0".equals(iface.getName()) || !iface.isUp()) {
                    continue;
                }
                for (InetAddress address : Collections.list(iface.getInetAddresses())) {
                    if (address instanceof Inet4Address && !address.isLoopbackAddress()) {
                        return address.getHostAddress();
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return "";
    }

    public static final class PortalSnapshot {
        public final boolean running;
        public final String ip;
        public final int port;
        public final String url;
        public final String pairingCode;
        public final String error;
        public final int successfulPairs;
        public final long startedAtMs;
        public final long lastPairAtMs;
        public final String startReason;

        private PortalSnapshot(
                boolean running,
                String ip,
                int port,
                String pairingCode,
                String error,
                int successfulPairs,
                long startedAtMs,
                long lastPairAtMs,
                String startReason) {
            this.running = running;
            this.ip = ip == null ? "" : ip;
            this.port = port;
            this.url = running ? "http://" + this.ip + ":" + port : "";
            this.pairingCode = pairingCode == null ? "" : pairingCode;
            this.error = error == null ? "" : error;
            this.successfulPairs = successfulPairs;
            this.startedAtMs = startedAtMs;
            this.lastPairAtMs = lastPairAtMs;
            this.startReason = startReason == null ? "" : startReason;
        }

        static PortalSnapshot running(
                String ip,
                int port,
                String pairingCode,
                int successfulPairs,
                long startedAtMs,
                long lastPairAtMs,
                String startReason) {
            return new PortalSnapshot(true, ip, port, pairingCode, "", successfulPairs, startedAtMs, lastPairAtMs,
                    startReason);
        }

        static PortalSnapshot stopped(String error) {
            return new PortalSnapshot(false, "", 0, "", error, 0, 0L, 0L, "");
        }

        JSONObject toJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("running", running);
            json.put("ip", ip);
            json.put("port", port);
            json.put("url", url);
            json.put("pairingCode", pairingCode);
            json.put("error", error);
            json.put("successfulPairs", successfulPairs);
            json.put("startedAtMs", startedAtMs);
            json.put("lastPairAtMs", lastPairAtMs);
            json.put("startReason", startReason);
            return json;
        }
    }

    private static final class PortalServer implements Runnable {
        private final Service service;
        private final String ip;
        private final int port;
        private final String token;
        private volatile String pairingCode;
        private final long startedAtMs;
        private final long startedElapsedMs;
        private final long tokenIssuedAtMs;
        private final String startReason;
        private volatile int successfulPairs;
        private volatile int badPairAttempts;
        private volatile long badPairBlockedUntilElapsedMs;
        private volatile long lastPairAtMs;
        private volatile boolean running;
        private volatile String error = "";
        private ServerSocket serverSocket;
        private Thread thread;

        PortalServer(Service service, String ip, int port, String token, String pairingCode, String startReason) {
            this.service = service;
            this.ip = ip;
            this.port = port;
            this.token = token;
            this.pairingCode = pairingCode;
            this.startedAtMs = System.currentTimeMillis();
            this.startedElapsedMs = SystemClock.elapsedRealtime();
            this.tokenIssuedAtMs = this.startedAtMs;
            this.startReason = startReason;
        }

        boolean start() {
            try {
                serverSocket = new ServerSocket();
                serverSocket.setReuseAddress(true);
                serverSocket.bind(new InetSocketAddress(InetAddress.getByName(ip), port), 8);
                running = true;
                thread = new Thread(this, "SmartisaxDevicePortal");
                thread.start();
                return true;
            } catch (Exception e) {
                error = e.toString();
                closeQuietly(serverSocket);
                serverSocket = null;
                running = false;
                return false;
            }
        }

        boolean isRunning() {
            return running;
        }

        String lastError() {
            return error;
        }

        PortalSnapshot snapshot() {
            return running
                    ? PortalSnapshot.running(ip, port, pairingCode, successfulPairs, startedAtMs, lastPairAtMs,
                            startReason)
                    : PortalSnapshot.stopped(error);
        }

        void stop() {
            running = false;
            closeQuietly(serverSocket);
        }

        @Override
        public void run() {
            while (running) {
                try {
                    final Socket socket = serverSocket.accept();
                    Thread client = new Thread(new Runnable() {
                        @Override
                        public void run() {
                            handle(socket);
                        }
                    }, "SmartisaxDevicePortalClient");
                    client.start();
                } catch (IOException e) {
                    if (running) {
                        error = e.toString();
                    }
                }
            }
        }

        private void handle(Socket socket) {
            try {
                socket.setSoTimeout(5000);
                HttpRequest request = HttpRequest.read(socket.getInputStream());
                if (request == null) {
                    return;
                }
                if ("OPTIONS".equals(request.method)) {
                    writeText(socket, 204, "No Content", "text/plain; charset=utf-8", "");
                    return;
                }
                if ("GET".equals(request.method) && "/".equals(request.path)) {
                    writeText(socket, 200, "OK", "text/html; charset=utf-8", indexHtml());
                    return;
                }
                if ("POST".equals(request.method) && "/api/pair".equals(request.path)) {
                    handlePair(socket, request);
                    return;
                }
                if ("GET".equals(request.method) && "/api/status".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", statusJson());
                    return;
                }
                if ("GET".equals(request.method) && "/api/agent/status".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", SmartisaxAgentRuntime.get(service).statusJson());
                    return;
                }
                if ("GET".equals(request.method) && "/api/media/capabilities".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", mediaCapabilitiesJson());
                    return;
                }
                if ("GET".equals(request.method) && "/api/screen.png".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeBytes(socket, 200, "OK", "image/png", screenshotPng());
                    return;
                }
                if ("GET".equals(request.method) && "/api/video/h264".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeBytes(socket, 200, "OK", "video/avc", h264Video(request));
                    return;
                }
                if ("GET".equals(request.method) && "/api/video/mp4".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeBytes(socket, 200, "OK", "video/mp4", mp4Video(request));
                    return;
                }
                if ("GET".equals(request.method) && "/api/rtp/h264".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeBytes(socket, 200, "OK", "application/x-smartisax-rtp-dump", rtpH264(request));
                    return;
                }
                if ("POST".equals(request.method) && "/api/webrtc/offer".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", webrtcOfferProbe(request));
                    return;
                }
                if ("GET".equals(request.method) && "/api/webrtc/config".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", webrtcConfigJson());
                    return;
                }
                if ("GET".equals(request.method) && "/api/webrtc/capture/probe".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", webrtcCaptureProbeJson());
                    return;
                }
                if ("POST".equals(request.method) && "/api/webrtc/config".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", webrtcConfigUpdate(request));
                    return;
                }
                if ("GET".equals(request.method) && "/api/webrtc/sessions".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", webrtcSessionsJson());
                    return;
                }
                if ("POST".equals(request.method) && "/api/webrtc/close".equals(request.path)) {
                    if (!authorized(request)) {
                        writeJson(socket, 401, "Unauthorized", errorJson("unauthorized"));
                        return;
                    }
                    writeJson(socket, 200, "OK", webrtcClose(request));
                    return;
                }
                writeJson(socket, 404, "Not Found", errorJson("not_found"));
            } catch (Exception e) {
                try {
                    writeJson(socket, 500, "Internal Server Error", errorJson(e.toString()));
                } catch (Exception ignored) {
                }
            } finally {
                closeQuietly(socket);
            }
        }

        private void handlePair(Socket socket, HttpRequest request) throws IOException, JSONException {
            String code = "";
            try {
                JSONObject json = new JSONObject(request.body);
                code = json.optString("code", "");
            } catch (JSONException ignored) {
                code = formValue(request.body, "code");
            }
            JSONObject session;
            synchronized (this) {
                long now = SystemClock.elapsedRealtime();
                if (now < badPairBlockedUntilElapsedMs) {
                    JSONObject errorJson = errorJson("pairing_temporarily_locked");
                    errorJson.put("retryAfterMs", badPairBlockedUntilElapsedMs - now);
                    writeJson(socket, 429, "Too Many Requests", errorJson);
                    return;
                }
                if (!pairingCode.equals(code)) {
                    badPairAttempts += 1;
                    if (badPairAttempts >= MAX_BAD_PAIR_ATTEMPTS) {
                        badPairBlockedUntilElapsedMs = now + BAD_PAIR_LOCKOUT_MS;
                        badPairAttempts = 0;
                    }
                    JSONObject errorJson = errorJson("bad_pairing_code");
                    errorJson.put("badPairAttempts", badPairAttempts);
                    if (badPairBlockedUntilElapsedMs > now) {
                        errorJson.put("retryAfterMs", badPairBlockedUntilElapsedMs - now);
                    }
                    writeJson(socket, 403, "Forbidden", errorJson);
                    return;
                }
                badPairAttempts = 0;
                badPairBlockedUntilElapsedMs = 0L;
                successfulPairs += 1;
                lastPairAtMs = System.currentTimeMillis();
                rotatePairingCodeLocked();
                session = sessionJsonLocked();
                publishSnapshot();
            }
            JSONObject json = new JSONObject();
            json.put("token", token);
            json.put("session", session);
            json.put("status", statusJson());
            writeJson(socket, 200, "OK", json);
        }

        private void rotatePairingCodeLocked() {
            String next = randomPairingCode();
            while (next.equals(pairingCode)) {
                next = randomPairingCode();
            }
            pairingCode = next;
        }

        private void publishSnapshot() {
            synchronized (LOCK) {
                if (server == this) {
                    lastSnapshot = snapshot();
                }
            }
        }

        private boolean authorized(HttpRequest request) {
            String auth = request.headers.get("authorization");
            return constantTimeEquals("Bearer " + token, auth);
        }

        private JSONObject statusJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("device", Build.DEVICE);
            json.put("model", Build.MODEL);
            json.put("manufacturer", Build.MANUFACTURER);
            json.put("android", Build.VERSION.RELEASE);
            json.put("sdk", Build.VERSION.SDK_INT);
            json.put("slot", getprop("ro.boot.slot_suffix"));
            json.put("bootCompleted", getprop("sys.boot_completed"));
            json.put("portalUrl", "http://" + ip + ":" + port);
            json.put("portalIp", ip);
            json.put("portalPort", port);
            json.put("autoStartEnabled", isAutoStartEnabled(service));
            json.put("bootPolicy", "explicit-autostart-opt-in");
            json.put("wirelessAdbEnabled", Settings.Global.getInt(
                    service.getContentResolver(), "adb_wifi_enabled", 0) == 1);
            json.put("screen", "privileged-surfacecontrol-png");
            json.put("display", displayJson());
            json.put("agent", SmartisaxAgentRuntime.get(service).statusJson());
            json.put("agentStatus", "/api/agent/status");
            json.put("input", "webrtc-datachannel-input");
            json.put("inputTransport", "RTCDataChannel");
            json.put("inputChannel", "smartisax-input");
            json.put("inputMoveChannel", "smartisax-input-move");
            json.put("inputMoveStream", "touchStart-touchMoveBatch-touchEnd-low-retransmit+event-time-preserving-move-stream");
            json.put("touchPhotonMarker", SmartisaxTouchMarker.statusJson());
            json.put("webrtcAckJitterRepair", "dual-datachannel+compact-move-acks+batched-move-stream");
            json.put("chromePresentationGapRepair", "rvfc-marker-prediction+throttled-smoke-logging+dual-phase-input-frame-boost+marker-visible-burst-boost+marker-burst-reschedule-until-accepted+boost-token-retain+60-90hz+input-priority-frame+receiver-playout-delay-zero+motion-content-hint+rtc-playout-stats+quiet-presentation-surface+raf-mainthread-drift+canvas-presenter-mode+rvfc-vs-raf-vs-canvas+marker-draw-synced-capture-boost+draw-urgent-input-frame-boost+marker-visible-tail-presentation-cadence+rvfc-media-callback-tail-dephase");
            json.put("httpInput", false);
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            json.put("webrtc", PORTAL_WEBRTC);
            json.put("webrtcCodec", "H264-AV1-VP9-H265-latency-aware-browser-cascade");
            json.put("webrtcCodecPolicy", "latency-first-modern-fallback");
            json.put("webrtcCodecFallback", "H264");
            json.put("portalFrameBox", "visible-screenbox-stable-phone-aspect");
            json.put("portalDisplayWakeGuard", "webrtc-session-screen-wake-lock+activity-keep-screen-on");
            json.put("webrtcDefault", true);
            json.put("webrtcRuntimeTuning", true);
            json.put("webrtcBitratePolicy", "runtime-tuning");
            json.put("webrtcMaxFrameWidth", 1080);
            json.put("webrtcMaxFps", 90);
            json.put("webrtcCaptureBackend", "projection-auto");
            json.put("webrtcCaptureProbe", "/api/webrtc/capture/probe");
            json.put("webrtcMinimumTarget", "1080p60");
            json.put("webrtcDefaultTarget", "1080p90");
            json.put("webrtcFrameContinuityRepair", "surface-texture-helper-latest-frame-only+fresh-texture-timestamps");
            json.put("webrtcLatencyRepair", "latest-frame-only-queue-collapse+dual-move-datachannel+dual-phase-input-frame-boost+marker-visible-burst-boost+marker-burst-reschedule-until-accepted+boost-token-retain+60-90hz+event-time-input-priority+receiver-playout-delay-zero+quiet-presentation-surface+canvas-presenter-mode+marker-draw-synced-capture-boost+draw-urgent-input-frame-boost+display-wake-guard+marker-visible-tail-presentation-cadence+rvfc-media-callback-tail-dephase");
            json.put("webrtcRefreshRateProfiles", "1080p60+1080p90");
            try {
                JSONObject runtimeStatus = SmartisaxWebRtcRuntime.statusJson();
                JSONObject runtimeConfigEnvelope = SmartisaxWebRtcRuntime.configJson();
                JSONObject runtimeConfig = runtimeConfigEnvelope.optJSONObject("config");
                JSONObject runtimeLimits = runtimeConfigEnvelope.optJSONObject("limits");
                json.put("nativeWebRtc", runtimeStatus);
                if (runtimeConfig != null) {
                    json.put("webrtcRuntimeConfig", runtimeConfig);
                    json.put("webrtcTargetBitrateBps", runtimeConfig.optInt("targetBitrateBps", 1200000));
                }
                if (runtimeLimits != null) {
                    json.put("webrtcRuntimeLimits", runtimeLimits);
                }
            } catch (JSONException ignored) {
            }
            json.put("browserPlayback", PORTAL_PLAYBACK);
            json.put("mediaCapabilities", "/api/media/capabilities");
            json.put("videoStream", "/api/video/h264");
            json.put("videoClip", "/api/video/mp4");
            json.put("rtpProbe", "/api/rtp/h264");
            json.put("webrtcOffer", "/api/webrtc/offer");
            json.put("webrtcConfig", "/api/webrtc/config");
            json.put("webrtcCaptureProbe", "/api/webrtc/capture/probe");
            json.put("webrtcSessions", "/api/webrtc/sessions");
            json.put("webrtcClose", "/api/webrtc/close");
            synchronized (this) {
                json.put("session", sessionJsonLocked());
            }
            return json;
        }

        private JSONObject sessionJsonLocked() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("accessControl", "bearer-token-pair-code-rotation");
            json.put("pairingCodeUse", "rotates-after-success");
            json.put("badPairLimit", MAX_BAD_PAIR_ATTEMPTS);
            json.put("badPairLockoutMs", BAD_PAIR_LOCKOUT_MS);
            json.put("badPairAttempts", badPairAttempts);
            json.put("successfulPairs", successfulPairs);
            json.put("lastPairAtMs", lastPairAtMs);
            json.put("tokenIssuedAtMs", tokenIssuedAtMs);
            json.put("startedAtMs", startedAtMs);
            json.put("uptimeMs", Math.max(0L, SystemClock.elapsedRealtime() - startedElapsedMs));
            long retryMs = Math.max(0L, badPairBlockedUntilElapsedMs - SystemClock.elapsedRealtime());
            json.put("pairingLocked", retryMs > 0L);
            json.put("pairingRetryAfterMs", retryMs);
            json.put("startReason", startReason);
            return json;
        }

        private JSONObject mediaCapabilitiesJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("ok", true);
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            json.put("backend", "android-mediacodec-list");
            json.put("screen", displayJson());
            JSONObject runtimeConfigEnvelope = SmartisaxWebRtcRuntime.configJson();
            JSONObject runtimeConfig = runtimeConfigEnvelope.optJSONObject("config");
            JSONObject runtimeLimits = runtimeConfigEnvelope.optJSONObject("limits");
            if (runtimeConfig == null) {
                runtimeConfig = new JSONObject();
            }
            if (runtimeLimits == null) {
                runtimeLimits = new JSONObject();
            }
            JSONObject preferred = new JSONObject();
            preferred.put("codec", "H264,AV1,VP9,H265");
            preferred.put("codecPolicy", "latency-first-modern-fallback");
            preferred.put("codecFallback", "H264");
            preferred.put("portalFrameBox", "visible-screenbox-stable-phone-aspect");
            preferred.put("mime", "webrtc-negotiated");
            preferred.put("fallbackMime", "video/avc");
            int preferredWidth = runtimeConfig.optInt("frameWidthPortrait", 540);
            preferred.put("width", preferredWidth);
            preferred.put("height", preferredVideoHeight(preferredWidth));
            preferred.put("fps", runtimeConfig.optInt("fps", 8));
            preferred.put("bitrateBps", runtimeConfig.optInt("targetBitrateBps", 1200000));
            preferred.put("minBitrateBps", runtimeConfig.optInt("minBitrateBps", 600000));
            preferred.put("targetBitrateBps", runtimeConfig.optInt("targetBitrateBps", 1200000));
            preferred.put("maxBitrateBps", runtimeConfig.optInt("maxBitrateBps", 1200000));
            preferred.put("bitratePolicy", runtimeConfig.optString("bitratePolicy", "runtime-tuning+presentation-transport-pacing+encoder-transport-burst-clamp"));
            preferred.put("runtimeTuning", true);
            preferred.put("maxFrameWidth", runtimeLimits.optInt("maxFrameWidth", 1080));
            preferred.put("maxFps", runtimeLimits.optInt("maxFps", 90));
            preferred.put("captureBackend", runtimeConfig.optString("captureBackend", "projection-auto"));
            preferred.put("captureProbe", "/api/webrtc/capture/probe");
            preferred.put("minimumTarget", "1080p60");
            preferred.put("defaultTarget", "1080p90-input-60fps-presentation");
            preferred.put("frameContinuityRepair", "surface-texture-helper-latest-frame-only+fresh-texture-timestamps");
            preferred.put("stream", "/api/video/h264");
            preferred.put("clip", "/api/video/mp4");
            preferred.put("rtpProbe", "/api/rtp/h264");
            preferred.put("webrtcOffer", "/api/webrtc/offer");
            preferred.put("webrtcConfig", "/api/webrtc/config");
            preferred.put("webrtcSessions", "/api/webrtc/sessions");
            preferred.put("webrtcClose", "/api/webrtc/close");
            preferred.put("input", "webrtc-datachannel-input");
            preferred.put("inputTransport", "RTCDataChannel");
            preferred.put("inputChannel", "smartisax-input");
            preferred.put("inputMoveChannel", "smartisax-input-move");
            preferred.put("inputMoveStream", "touchStart-touchMoveBatch-touchEnd-low-retransmit+event-time-preserving-move-stream");
            preferred.put("touchPhotonMarker", SmartisaxTouchMarker.MODE);
            preferred.put("ackJitterRepair", "dual-datachannel+compact-move-acks+batched-move-stream");
            preferred.put("chromePresentationGapRepair", "rvfc-marker-prediction+throttled-smoke-logging+dual-phase-input-frame-boost+marker-visible-burst-boost+marker-burst-reschedule-until-accepted+boost-token-retain+60-90hz+input-priority-frame+receiver-playout-delay-zero+motion-content-hint+rtc-playout-stats+quiet-presentation-surface+raf-mainthread-drift+canvas-presenter-mode+rvfc-vs-raf-vs-canvas+presentation-transport-pacing+video-primary-roi-probe+raf-touch-photon-detect+marker-draw-synced-capture-boost+draw-urgent-input-frame-boost+marker-visible-tail-presentation-cadence+rvfc-media-callback-tail-dephase");
            preferred.put("browserReceiverPresentation", "receiver-playout-delay-zero+motion-content-hint+disable-remote-playback+quiet-presentation-surface+raf-mainthread-drift+video-primary-roi-probe+presentation-transport-pacing+rvfc-presentation-cadence-lite+rvfc-media-callback-tail-dephase");
            preferred.put("presentationProbe", "video-primary-roi-probe+raf-touch-photon-detect");
            preferred.put("transportPacing", "virtualdisplay-60fps-presentation-paced-90hz-input");
            preferred.put("encoderTransportBurstRepair", "1080p60-target-window-bitrate+late-start-frame-pump+maintain-framerate-sender");
            preferred.put("mediaCallbackTailRepair", "1080p60-rvfc-media-callback-tail-dephase+sender-59fps+7mbps-window+full-frame-forceFrame-spacing");
            preferred.put("inputFrameBoost", "touch-marker-injected-plus-draw-synced-visible-burst+retain-until-captured-frame+draw-urgent-bypass-half-interval+marker-visible-tail-full-frame-spacing");
            preferred.put("refreshRateProfiles", "1080p60+1080p90");
            preferred.put("httpInput", false);
            preferred.put("browserPlayback", PORTAL_PLAYBACK);
            preferred.put("webRtc", "native-libwebrtc-dtls-srtp");
            preferred.put("defaultTransport", "WebRTC");
            preferred.put("webCodecs", "optional-secure-context-diagnostic");
            preferred.put("reason", "portal6g_rvfc_media_tail");
            preferred.put("displayWakeGuard", "webrtc-session-screen-wake-lock+activity-keep-screen-on");
            preferred.put("displayWakeGuardReason", "portal6d_display_wake_guard");
            preferred.put("accessControl", "bearer-token-pair-code-rotation");
            json.put("preferred", preferred);
            json.put("webrtcRuntimeConfig", runtimeConfigEnvelope);
            try {
                json.put("encoders", encoderCapabilitiesJson());
            } catch (Exception e) {
                json.put("encoders", new JSONArray());
                json.put("mediaCodecError", e.toString());
            }
            return json;
        }

        private int preferredVideoHeight(int width) {
            Point size = realDisplaySize();
            if (size.x <= 0 || size.y <= 0) {
                return 1280;
            }
            int height = Math.round(width * (size.y / (float) size.x));
            return align(height, 16);
        }

        private JSONObject displayJson() throws JSONException {
            return SmartisaxScreenCapture.displayJson(service);
        }

        private Point realDisplaySize() {
            return SmartisaxScreenCapture.realDisplaySize(service);
        }

        private int displayRotation() {
            return SmartisaxScreenCapture.displayRotation(service);
        }

        private JSONArray encoderCapabilitiesJson() throws JSONException {
            JSONArray encoders = new JSONArray();
            String[] targetMimes = {"video/avc", "video/hevc"};
            MediaCodecInfo[] codecInfos = new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos();
            for (MediaCodecInfo info : codecInfos) {
                if (!info.isEncoder()) {
                    continue;
                }
                for (String mime : targetMimes) {
                    if (!supportsMime(info, mime)) {
                        continue;
                    }
                    JSONObject item = new JSONObject();
                    item.put("name", info.getName());
                    item.put("mime", mime);
                    item.put("encoder", true);
                    if (Build.VERSION.SDK_INT >= 29) {
                        item.put("hardwareAccelerated", info.isHardwareAccelerated());
                        item.put("softwareOnly", info.isSoftwareOnly());
                        item.put("vendor", info.isVendor());
                    }
                    try {
                        MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(mime);
                        item.put("colorFormats", intArray(caps.colorFormats));
                        item.put("profileLevels", profileLevels(caps.profileLevels));
                        try {
                            item.put("videoCapabilities", videoCapabilities(caps.getVideoCapabilities()));
                        } catch (RuntimeException e) {
                            item.put("videoCapabilitiesError", e.toString());
                        }
                    } catch (RuntimeException e) {
                        item.put("capabilitiesError", e.toString());
                    }
                    encoders.put(item);
                }
            }
            return encoders;
        }

        private static boolean supportsMime(MediaCodecInfo info, String mime) {
            for (String type : info.getSupportedTypes()) {
                if (mime.equalsIgnoreCase(type)) {
                    return true;
                }
            }
            return false;
        }

        private static JSONArray intArray(int[] values) {
            JSONArray json = new JSONArray();
            if (values != null) {
                for (int value : values) {
                    json.put(value);
                }
            }
            return json;
        }

        private static JSONArray profileLevels(MediaCodecInfo.CodecProfileLevel[] values) throws JSONException {
            JSONArray json = new JSONArray();
            if (values != null) {
                for (MediaCodecInfo.CodecProfileLevel value : values) {
                    JSONObject entry = new JSONObject();
                    entry.put("profile", value.profile);
                    entry.put("level", value.level);
                    json.put(entry);
                }
            }
            return json;
        }

        private static JSONObject videoCapabilities(MediaCodecInfo.VideoCapabilities caps) throws JSONException {
            JSONObject json = new JSONObject();
            if (caps == null) {
                return json;
            }
            json.put("widthAlignment", caps.getWidthAlignment());
            json.put("heightAlignment", caps.getHeightAlignment());
            Range<Integer> widths = caps.getSupportedWidths();
            Range<Integer> heights = caps.getSupportedHeights();
            if (widths != null) {
                json.put("minWidth", widths.getLower());
                json.put("maxWidth", widths.getUpper());
            }
            if (heights != null) {
                json.put("minHeight", heights.getLower());
                json.put("maxHeight", heights.getUpper());
            }
            return json;
        }

        private static int clamp(int value, int min, int max) {
            return Math.max(min, Math.min(max, value));
        }

        private byte[] screenshotPng() throws IOException {
            return SmartisaxScreenCapture.capturePng(service);
        }

        private byte[] h264Video(HttpRequest request) throws IOException {
            int width = align(queryInt(request, "width", 720, 160, 720), 16);
            int height = align(queryInt(request, "height", preferredVideoHeight(width), 160, 1600), 16);
            int fps = queryInt(request, "fps", 5, 1, 15);
            int frames = queryInt(request, "frames", 12, 1, 60);
            int bitrate = queryInt(request, "bitrate", 1200000, 250000, 4000000);
            return encodeH264Frames(width, height, fps, frames, bitrate);
        }

        private byte[] mp4Video(HttpRequest request) throws IOException {
            int width = align(queryInt(request, "width", 720, 160, 720), 16);
            int height = align(queryInt(request, "height", preferredVideoHeight(width), 160, 1600), 16);
            int fps = queryInt(request, "fps", 6, 1, 15);
            int frames = queryInt(request, "frames", 12, 1, 60);
            int bitrate = queryInt(request, "bitrate", 1200000, 250000, 4000000);
            return encodeMp4Frames(width, height, fps, frames, bitrate);
        }

        private byte[] rtpH264(HttpRequest request) throws IOException {
            int width = align(queryInt(request, "width", 720, 160, 720), 16);
            int height = align(queryInt(request, "height", preferredVideoHeight(width), 160, 1600), 16);
            int fps = queryInt(request, "fps", 6, 1, 15);
            int frames = queryInt(request, "frames", 8, 1, 30);
            int bitrate = queryInt(request, "bitrate", 1200000, 250000, 4000000);
            int payloadMax = queryInt(request, "payload", 1200, 400, 1400);
            return rtpDumpFromAnnexB(encodeH264Frames(width, height, fps, frames, bitrate), fps, payloadMax);
        }

        private JSONObject webrtcOfferProbe(HttpRequest request) throws JSONException {
            JSONObject body;
            try {
                body = new JSONObject(request.body);
            } catch (JSONException e) {
                body = new JSONObject();
            }
            try {
                JSONObject json = SmartisaxWebRtcRuntime.answer(service, new SmartisaxWebRtcRuntime.FrameProvider() {
                    @Override
                    public Bitmap capture() throws IOException {
                        return screenshotBitmap();
                    }

                    @Override
                    public Point displaySize() {
                        return realDisplaySize();
                    }
                }, new SmartisaxWebRtcRuntime.InputHandler() {
                    @Override
                    public JSONObject handle(JSONObject payload) throws IOException, JSONException {
                        return SmartisaxInputController.handle(payload);
                    }
                }, body);
                json.put("portalVersion", PORTAL_VERSION);
                json.put("variant", PORTAL_VARIANT);
                json.put("display", displayJson());
                json.put("hasVideo", body.optString("sdp", "").contains("m=video"));
                json.put("hasH264", body.optString("sdp", "").toLowerCase(Locale.US).contains("h264"));
                json.put("hasIceUfrag", body.optString("sdp", "").contains("a=ice-ufrag:"));
                json.put("hasFingerprint", body.optString("sdp", "").contains("a=fingerprint:"));
                json.put("fallback", "/api/video/mp4");
                return json;
            } catch (Throwable t) {
                JSONObject json = new JSONObject();
                String sdp = body.optString("sdp", "");
                json.put("ok", false);
                json.put("mode", "native-libwebrtc-answer");
                json.put("portalVersion", PORTAL_VERSION);
                json.put("variant", PORTAL_VARIANT);
                json.put("offerType", body.optString("type", ""));
                json.put("sdpBytes", sdp.getBytes(StandardCharsets.UTF_8).length);
                json.put("hasVideo", sdp.contains("m=video"));
                json.put("hasH264", sdp.toLowerCase(Locale.US).contains("h264"));
                json.put("hasIceUfrag", sdp.contains("a=ice-ufrag:"));
                json.put("hasFingerprint", sdp.contains("a=fingerprint:"));
                json.put("nativeWebRtcRuntime", true);
                json.put("dtlsSrtp", false);
                json.put("error", t.toString());
                json.put("fallback", "/api/video/mp4");
                return json;
            }
        }

        private JSONObject webrtcSessionsJson() throws JSONException {
            JSONObject json = SmartisaxWebRtcRuntime.statusJson();
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            return json;
        }

        private JSONObject webrtcConfigJson() throws JSONException {
            JSONObject json = SmartisaxWebRtcRuntime.configJson();
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            return json;
        }

        private JSONObject webrtcConfigUpdate(HttpRequest request) throws JSONException {
            JSONObject body;
            try {
                body = request.body == null || request.body.length() == 0
                        ? new JSONObject()
                        : new JSONObject(request.body);
            } catch (JSONException e) {
                body = new JSONObject();
            }
            JSONObject json = SmartisaxWebRtcRuntime.updateConfig(body);
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            return json;
        }

        private JSONObject webrtcCaptureProbeJson() throws JSONException {
            JSONObject json = SmartisaxWebRtcRuntime.captureProbeJson(service, realDisplaySize());
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            return json;
        }

        private JSONObject webrtcClose(HttpRequest request) throws JSONException {
            JSONObject body;
            try {
                body = request.body == null || request.body.length() == 0
                        ? new JSONObject()
                        : new JSONObject(request.body);
            } catch (JSONException e) {
                body = new JSONObject();
            }
            JSONObject json = SmartisaxWebRtcRuntime.closeSessions(body);
            json.put("portalVersion", PORTAL_VERSION);
            json.put("variant", PORTAL_VARIANT);
            return json;
        }

        private static boolean constantTimeEquals(String expected, String actual) {
            if (expected == null || actual == null) {
                return false;
            }
            int diff = expected.length() ^ actual.length();
            int max = Math.max(expected.length(), actual.length());
            for (int i = 0; i < max; i++) {
                char left = i < expected.length() ? expected.charAt(i) : 0;
                char right = i < actual.length() ? actual.charAt(i) : 0;
                diff |= left ^ right;
            }
            return diff == 0;
        }

        private byte[] encodeH264Frames(int width, int height, int fps, int frames, int bitrate)
                throws IOException {
            H264EncoderChoice choice = chooseH264Encoder();
            MediaCodec codec = null;
            try {
                MediaFormat format = MediaFormat.createVideoFormat("video/avc", width, height);
                format.setInteger(MediaFormat.KEY_COLOR_FORMAT, choice.colorFormat);
                format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
                format.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
                format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);

                codec = MediaCodec.createByCodecName(choice.name);
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                codec.start();

                MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
                ByteArrayOutputStream out = new ByteArrayOutputStream(Math.max(256 * 1024, frames * 64 * 1024));
                long frameDurationUs = 1000000L / Math.max(1, fps);
                for (int frame = 0; frame < frames; frame++) {
                    queueH264Frame(codec, width, height, choice.colorFormat, frame * frameDurationUs);
                    drainH264(codec, info, out, false);
                    if (frame + 1 < frames) {
                        SystemClock.sleep(Math.max(1, 1000 / Math.max(1, fps)));
                    }
                }
                queueH264Eos(codec, frames * frameDurationUs);
                drainH264(codec, info, out, true);
                byte[] bytes = out.toByteArray();
                if (!containsStartCode(bytes)) {
                    throw new IOException("h264_stream_missing_annexb_start_code encoder=" + choice.name);
                }
                return bytes;
            } catch (IOException e) {
                throw e;
            } catch (Exception e) {
                throw new IOException("h264_encode_failed", e);
            } finally {
                if (codec != null) {
                    try {
                        codec.stop();
                    } catch (Exception ignored) {
                    }
                    try {
                        codec.release();
                    } catch (Exception ignored) {
                    }
                }
            }
        }

        private void queueH264Frame(MediaCodec codec, int width, int height, int colorFormat, long ptsUs)
                throws IOException {
            int inputIndex = codec.dequeueInputBuffer(1000000);
            if (inputIndex < 0) {
                throw new IOException("h264_input_buffer_timeout");
            }
            ByteBuffer input = codec.getInputBuffer(inputIndex);
            if (input == null) {
                throw new IOException("h264_input_buffer_null");
            }
            byte[] yuv = screenshotYuv420(width, height, colorFormat);
            if (input.capacity() < yuv.length) {
                throw new IOException("h264_input_buffer_too_small capacity=" + input.capacity() + " need=" + yuv.length);
            }
            input.clear();
            input.put(yuv);
            codec.queueInputBuffer(inputIndex, 0, yuv.length, ptsUs, 0);
        }

        private static void queueH264Eos(MediaCodec codec, long ptsUs) throws IOException {
            int inputIndex = codec.dequeueInputBuffer(1000000);
            if (inputIndex < 0) {
                throw new IOException("h264_eos_input_buffer_timeout");
            }
            codec.queueInputBuffer(inputIndex, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
        }

        private static void drainH264(
                MediaCodec codec,
                MediaCodec.BufferInfo info,
                ByteArrayOutputStream out,
                boolean waitForEos) throws IOException {
            while (true) {
                int outputIndex = codec.dequeueOutputBuffer(info, waitForEos ? 1000000 : 1000);
                if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (!waitForEos) {
                        return;
                    }
                    continue;
                }
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat format = codec.getOutputFormat();
                    appendCsd(out, format, "csd-0");
                    appendCsd(out, format, "csd-1");
                    continue;
                }
                if (outputIndex < 0) {
                    continue;
                }
                ByteBuffer output = codec.getOutputBuffer(outputIndex);
                if (output != null && info.size > 0) {
                    output.position(info.offset);
                    output.limit(info.offset + info.size);
                    appendAnnexB(out, output.slice());
                }
                boolean eos = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                codec.releaseOutputBuffer(outputIndex, false);
                if (eos || !waitForEos) {
                    return;
                }
            }
        }

        private static void appendCsd(ByteArrayOutputStream out, MediaFormat format, String key) {
            ByteBuffer csd = format.getByteBuffer(key);
            if (csd != null) {
                appendAnnexB(out, csd.slice());
            }
        }

        private byte[] screenshotYuv420(int width, int height, int colorFormat) throws IOException {
            Bitmap raw = screenshotBitmap();
            if (raw == null) {
                throw new IOException("surfacecontrol_screenshot_returned_null");
            }
            Bitmap readable = raw;
            if (raw.getConfig() == Bitmap.Config.HARDWARE) {
                readable = raw.copy(Bitmap.Config.ARGB_8888, false);
            }
            Bitmap scaled = Bitmap.createScaledBitmap(readable, width, height, true);
            try {
                return bitmapToYuv420(scaled, colorFormat);
            } finally {
                if (scaled != readable) {
                    scaled.recycle();
                }
                if (readable != raw) {
                    readable.recycle();
                }
            }
        }

        private static byte[] bitmapToYuv420(Bitmap bitmap, int colorFormat) {
            int width = bitmap.getWidth();
            int height = bitmap.getHeight();
            int frameSize = width * height;
            int[] pixels = new int[frameSize];
            byte[] yuv = new byte[frameSize * 3 / 2];
            boolean planar = colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar;
            int uIndex = frameSize;
            int vIndex = frameSize + frameSize / 4;
            int uvIndex = frameSize;
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    int argb = pixels[y * width + x];
                    int r = (argb >> 16) & 0xff;
                    int g = (argb >> 8) & 0xff;
                    int b = argb & 0xff;
                    int yy = clampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
                    int uu = clampByte(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
                    int vv = clampByte(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
                    yuv[y * width + x] = (byte) yy;
                    if ((y & 1) == 0 && (x & 1) == 0) {
                        if (planar) {
                            yuv[uIndex++] = (byte) uu;
                            yuv[vIndex++] = (byte) vv;
                        } else {
                            yuv[uvIndex++] = (byte) uu;
                            yuv[uvIndex++] = (byte) vv;
                        }
                    }
                }
            }
            return yuv;
        }

        private static H264EncoderChoice chooseH264Encoder() throws IOException {
            MediaCodecInfo[] codecInfos = new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos();
            H264EncoderChoice fallback = null;
            for (MediaCodecInfo info : codecInfos) {
                if (!info.isEncoder() || !supportsMime(info, "video/avc")) {
                    continue;
                }
                MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType("video/avc");
                for (int color : caps.colorFormats) {
                    if (isPreferredYuv420(color)) {
                        return new H264EncoderChoice(info.getName(), color);
                    }
                    if (fallback == null && color != MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface) {
                        fallback = new H264EncoderChoice(info.getName(), color);
                    }
                }
            }
            if (fallback != null) {
                return fallback;
            }
            throw new IOException("no_bytebuffer_h264_encoder");
        }

        private static boolean isPreferredYuv420(int colorFormat) {
            return colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
                    || colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
                    || colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible;
        }

        private static void appendAnnexB(ByteArrayOutputStream out, ByteBuffer buffer) {
            byte[] bytes = new byte[buffer.remaining()];
            buffer.get(bytes);
            if (startsWithStartCode(bytes)) {
                out.write(bytes, 0, bytes.length);
                return;
            }
            if (appendAvccAsAnnexB(out, bytes)) {
                return;
            }
            out.write(0);
            out.write(0);
            out.write(0);
            out.write(1);
            out.write(bytes, 0, bytes.length);
        }

        private static boolean appendAvccAsAnnexB(ByteArrayOutputStream out, byte[] bytes) {
            int offset = 0;
            boolean wrote = false;
            while (offset + 4 <= bytes.length) {
                int length = ((bytes[offset] & 0xff) << 24)
                        | ((bytes[offset + 1] & 0xff) << 16)
                        | ((bytes[offset + 2] & 0xff) << 8)
                        | (bytes[offset + 3] & 0xff);
                offset += 4;
                if (length <= 0 || offset + length > bytes.length) {
                    return false;
                }
                out.write(0);
                out.write(0);
                out.write(0);
                out.write(1);
                out.write(bytes, offset, length);
                offset += length;
                wrote = true;
            }
            return wrote && offset == bytes.length;
        }

        private static boolean containsStartCode(byte[] bytes) {
            for (int i = 0; i + 4 <= bytes.length; i++) {
                if (bytes[i] == 0 && bytes[i + 1] == 0
                        && (bytes[i + 2] == 1 || (i + 3 < bytes.length && bytes[i + 2] == 0 && bytes[i + 3] == 1))) {
                    return true;
                }
            }
            return false;
        }

        private static boolean startsWithStartCode(byte[] bytes) {
            return bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 0
                    && (bytes[2] == 1 || (bytes[2] == 0 && bytes[3] == 1));
        }

        private static byte[] rtpDumpFromAnnexB(byte[] annexb, int fps, int payloadMax) throws IOException {
            List<byte[]> nals = splitAnnexBNals(annexb);
            if (nals.isEmpty()) {
                throw new IOException("rtp_packetizer_no_nals");
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream(annexb.length + nals.size() * 16);
            int sequence = 1;
            long timestamp = 0x53584f53L;
            int ssrc = 0x53585232;
            int frameTicks = Math.max(1, 90000 / Math.max(1, fps));
            boolean sawVclForTimestamp = false;
            for (byte[] nal : nals) {
                if (nal.length == 0) {
                    continue;
                }
                int nalType = nal[0] & 0x1f;
                boolean vcl = nalType == 1 || nalType == 5;
                if (vcl && sawVclForTimestamp) {
                    timestamp = (timestamp + frameTicks) & 0xffffffffL;
                    sawVclForTimestamp = false;
                }
                sequence = writeRtpNal(out, nal, sequence, timestamp, ssrc, vcl, payloadMax);
                if (vcl) {
                    sawVclForTimestamp = true;
                }
            }
            return out.toByteArray();
        }

        private static List<byte[]> splitAnnexBNals(byte[] bytes) {
            ArrayList<Integer> starts = new ArrayList<>();
            int i = 0;
            while (i + 3 < bytes.length) {
                int length = startCodeLength(bytes, i);
                if (length > 0) {
                    starts.add(i);
                    i += length;
                    continue;
                }
                i++;
            }
            ArrayList<byte[]> nals = new ArrayList<>();
            for (int index = 0; index < starts.size(); index++) {
                int start = starts.get(index);
                int prefix = startCodeLength(bytes, start);
                int nalStart = start + prefix;
                int nalEnd = index + 1 < starts.size() ? starts.get(index + 1) : bytes.length;
                while (nalEnd > nalStart && bytes[nalEnd - 1] == 0) {
                    nalEnd--;
                }
                if (nalEnd > nalStart) {
                    byte[] nal = new byte[nalEnd - nalStart];
                    System.arraycopy(bytes, nalStart, nal, 0, nal.length);
                    nals.add(nal);
                }
            }
            return nals;
        }

        private static int startCodeLength(byte[] bytes, int offset) {
            if (offset + 3 <= bytes.length
                    && bytes[offset] == 0
                    && bytes[offset + 1] == 0
                    && bytes[offset + 2] == 1) {
                return 3;
            }
            if (offset + 4 <= bytes.length
                    && bytes[offset] == 0
                    && bytes[offset + 1] == 0
                    && bytes[offset + 2] == 0
                    && bytes[offset + 3] == 1) {
                return 4;
            }
            return 0;
        }

        private static int writeRtpNal(
                ByteArrayOutputStream out,
                byte[] nal,
                int sequence,
                long timestamp,
                int ssrc,
                boolean marker,
                int payloadMax) throws IOException {
            if (nal.length <= payloadMax) {
                writeRtpDumpPacket(out, nal, sequence, timestamp, ssrc, marker);
                return (sequence + 1) & 0xffff;
            }
            int nalHeader = nal[0] & 0xff;
            int fuIndicator = (nalHeader & 0xe0) | 28;
            int nalType = nalHeader & 0x1f;
            int offset = 1;
            int chunkMax = Math.max(2, payloadMax - 2);
            boolean start = true;
            while (offset < nal.length) {
                int chunk = Math.min(chunkMax, nal.length - offset);
                boolean end = offset + chunk >= nal.length;
                byte[] payload = new byte[chunk + 2];
                payload[0] = (byte) fuIndicator;
                payload[1] = (byte) ((start ? 0x80 : 0) | (end ? 0x40 : 0) | nalType);
                System.arraycopy(nal, offset, payload, 2, chunk);
                writeRtpDumpPacket(out, payload, sequence, timestamp, ssrc, marker && end);
                sequence = (sequence + 1) & 0xffff;
                offset += chunk;
                start = false;
            }
            return sequence;
        }

        private static void writeRtpDumpPacket(
                ByteArrayOutputStream out,
                byte[] payload,
                int sequence,
                long timestamp,
                int ssrc,
                boolean marker) throws IOException {
            int length = 12 + payload.length;
            if (length > 65535) {
                throw new IOException("rtp_packet_too_large");
            }
            out.write((length >> 8) & 0xff);
            out.write(length & 0xff);
            out.write(0x80);
            out.write((marker ? 0x80 : 0) | 96);
            out.write((sequence >> 8) & 0xff);
            out.write(sequence & 0xff);
            writeUint32(out, timestamp);
            writeUint32(out, ssrc & 0xffffffffL);
            out.write(payload, 0, payload.length);
        }

        private static void writeUint32(ByteArrayOutputStream out, long value) {
            out.write((int) ((value >> 24) & 0xff));
            out.write((int) ((value >> 16) & 0xff));
            out.write((int) ((value >> 8) & 0xff));
            out.write((int) (value & 0xff));
        }

        private byte[] encodeMp4Frames(int width, int height, int fps, int frames, int bitrate)
                throws IOException {
            H264EncoderChoice choice = chooseH264Encoder();
            File file = File.createTempFile("smartisax-portal-", ".mp4", service.getCacheDir());
            MediaCodec codec = null;
            Mp4MuxerState muxer = new Mp4MuxerState(file);
            try {
                MediaFormat format = MediaFormat.createVideoFormat("video/avc", width, height);
                format.setInteger(MediaFormat.KEY_COLOR_FORMAT, choice.colorFormat);
                format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
                format.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
                format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);

                codec = MediaCodec.createByCodecName(choice.name);
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                codec.start();

                MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
                long frameDurationUs = 1000000L / Math.max(1, fps);
                for (int frame = 0; frame < frames; frame++) {
                    queueH264Frame(codec, width, height, choice.colorFormat, frame * frameDurationUs);
                    drainMp4(codec, info, muxer, false);
                    if (frame + 1 < frames) {
                        SystemClock.sleep(Math.max(1, 1000 / Math.max(1, fps)));
                    }
                }
                queueH264Eos(codec, frames * frameDurationUs);
                drainMp4(codec, info, muxer, true);
                muxer.close();
                return readFileLimited(file, 16 * 1024 * 1024);
            } catch (IOException e) {
                throw e;
            } catch (Exception e) {
                throw new IOException("mp4_encode_failed", e);
            } finally {
                muxer.close();
                if (codec != null) {
                    try {
                        codec.stop();
                    } catch (Exception ignored) {
                    }
                    try {
                        codec.release();
                    } catch (Exception ignored) {
                    }
                }
                //noinspection ResultOfMethodCallIgnored
                file.delete();
            }
        }

        private static void drainMp4(
                MediaCodec codec,
                MediaCodec.BufferInfo info,
                Mp4MuxerState muxer,
                boolean waitForEos) throws IOException {
            while (true) {
                int outputIndex = codec.dequeueOutputBuffer(info, waitForEos ? 1000000 : 1000);
                if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (!waitForEos) {
                        return;
                    }
                    continue;
                }
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    muxer.start(codec.getOutputFormat());
                    continue;
                }
                if (outputIndex < 0) {
                    continue;
                }
                ByteBuffer output = codec.getOutputBuffer(outputIndex);
                if (output != null && info.size > 0
                        && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                    if (!muxer.started) {
                        throw new IOException("mp4_muxer_not_started_before_sample");
                    }
                    output.position(info.offset);
                    output.limit(info.offset + info.size);
                    muxer.muxer.writeSampleData(muxer.track, output, info);
                }
                boolean eos = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                codec.releaseOutputBuffer(outputIndex, false);
                if (eos || !waitForEos) {
                    return;
                }
            }
        }

        private static byte[] readFileLimited(File file, int maxBytes) throws IOException {
            if (file.length() > maxBytes) {
                throw new IOException("file_output_too_large");
            }
            FileInputStream input = null;
            try {
                input = new FileInputStream(file);
                return readLimited(input, maxBytes).toByteArray();
            } finally {
                if (input != null) {
                    input.close();
                }
            }
        }

        private static int queryInt(HttpRequest request, String key, int defaultValue, int min, int max) {
            String value = queryValue(request.query, key);
            if (value.length() == 0) {
                return defaultValue;
            }
            try {
                return clamp(Integer.parseInt(value), min, max);
            } catch (NumberFormatException ignored) {
                return defaultValue;
            }
        }

        private static String queryValue(String query, String key) {
            if (query == null || query.length() == 0) {
                return "";
            }
            try {
                for (String part : query.split("&")) {
                    int at = part.indexOf('=');
                    String name = at >= 0 ? part.substring(0, at) : part;
                    if (key.equals(URLDecoder.decode(name, "UTF-8"))) {
                        return URLDecoder.decode(at >= 0 ? part.substring(at + 1) : "", "UTF-8");
                    }
                }
            } catch (Exception ignored) {
            }
            return "";
        }

        private static int align(int value, int multiple) {
            return ((Math.max(1, value) + multiple - 1) / multiple) * multiple;
        }

        private static int clampByte(int value) {
            return Math.max(0, Math.min(255, value));
        }

        private Bitmap screenshotBitmap() throws IOException {
            return SmartisaxScreenCapture.captureBitmap(service);
        }

        private Bitmap bitmapFromSurfaceResult(Object result) throws IOException {
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
                                + result.getClass().getName(),
                        e);
            }
        }

        private static boolean isPng(byte[] bytes) {
            return bytes.length >= 8
                    && (bytes[0] & 0xff) == 0x89
                    && bytes[1] == 0x50
                    && bytes[2] == 0x4e
                    && bytes[3] == 0x47
                    && bytes[4] == 0x0d
                    && bytes[5] == 0x0a
                    && bytes[6] == 0x1a
                    && bytes[7] == 0x0a;
        }

        private static ByteArrayOutputStream readLimited(InputStream input, int maxBytes) throws IOException {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int total = 0;
            int read;
            while ((read = input.read(buffer)) >= 0) {
                total += read;
                if (total > maxBytes) {
                    throw new IOException("process_output_too_large");
                }
                out.write(buffer, 0, read);
            }
            return out;
        }

        private static JSONObject errorJson(String error) throws JSONException {
            JSONObject json = new JSONObject();
            json.put("ok", false);
            json.put("error", error);
            return json;
        }

        private static String formValue(String body, String key) {
            try {
                for (String part : body.split("&")) {
                    int at = part.indexOf('=');
                    if (at < 0) {
                        continue;
                    }
                    String name = URLDecoder.decode(part.substring(0, at), "UTF-8");
                    if (key.equals(name)) {
                        return URLDecoder.decode(part.substring(at + 1), "UTF-8");
                    }
                }
            } catch (Exception ignored) {
            }
            return "";
        }

        private static String getprop(String name) {
            Process process = null;
            try {
                process = new ProcessBuilder("/system/bin/getprop", name).redirectErrorStream(true).start();
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                InputStream input = process.getInputStream();
                byte[] buffer = new byte[256];
                int read;
                while ((read = input.read(buffer)) >= 0) {
                    out.write(buffer, 0, read);
                }
                return out.toString("UTF-8").trim();
            } catch (Exception ignored) {
                return "";
            } finally {
                if (process != null) {
                    process.destroy();
                }
            }
        }

        private String indexHtml() {
            InputStream input = null;
            try {
                input = service.getAssets().open("portal/index.html");
                return readLimited(input, 256 * 1024).toString("UTF-8");
            } catch (Exception e) {
                return "<!doctype html><html><head><meta charset=\"utf-8\">"
                        + "<title>Smartisax Portal</title></head><body>"
                        + "<h1>Smartisax Portal</h1><pre>portal_asset_load_failed: "
                        + e.toString()
                        + "</pre></body></html>";
            } finally {
                if (input != null) {
                    try {
                        input.close();
                    } catch (IOException ignored) {
                    }
                }
            }
        }

        private static void writeJson(Socket socket, int code, String reason, JSONObject json) throws IOException {
            writeText(socket, code, reason, "application/json; charset=utf-8", json.toString());
        }

        private static void writeSecurityHeaders(BufferedWriter writer) throws IOException {
            writer.write("Cache-Control: no-store\r\n");
            writer.write("Connection: close\r\n");
            writer.write("X-Content-Type-Options: nosniff\r\n");
            writer.write("Referrer-Policy: no-referrer\r\n");
            writer.write("Cross-Origin-Resource-Policy: same-origin\r\n");
            writer.write("X-Frame-Options: DENY\r\n");
            writer.write("Content-Security-Policy: default-src 'self'; connect-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'\r\n");
        }

        private static void writeBytes(Socket socket, int code, String reason, String contentType, byte[] body)
                throws IOException {
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8));
            writer.write("HTTP/1.1 " + code + " " + reason + "\r\n");
            writer.write("Content-Type: " + contentType + "\r\n");
            writer.write("Content-Length: " + body.length + "\r\n");
            writeSecurityHeaders(writer);
            writer.write("\r\n");
            writer.flush();
            socket.getOutputStream().write(body);
            socket.getOutputStream().flush();
        }

        private static void writeText(Socket socket, int code, String reason, String contentType, String body)
                throws IOException {
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8));
            writer.write("HTTP/1.1 " + code + " " + reason + "\r\n");
            writer.write("Content-Type: " + contentType + "\r\n");
            writer.write("Content-Length: " + bytes.length + "\r\n");
            writeSecurityHeaders(writer);
            writer.write("\r\n");
            writer.flush();
            socket.getOutputStream().write(bytes);
            socket.getOutputStream().flush();
        }
    }

    private static final class RootResult {
        final int exitCode;
        final byte[] bytes;
        final String output;

        RootResult(int exitCode, byte[] bytes, String output) {
            this.exitCode = exitCode;
            this.bytes = bytes;
            this.output = output == null ? "" : output;
        }
    }

    private static final class HttpRequest {
        final String method;
        final String path;
        final String query;
        final Map<String, String> headers;
        final String body;

        private HttpRequest(String method, String path, String query, Map<String, String> headers, String body) {
            this.method = method;
            this.path = path;
            this.query = query;
            this.headers = headers;
            this.body = body;
        }

        static HttpRequest read(InputStream input) throws IOException {
            BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8));
            String requestLine = reader.readLine();
            if (requestLine == null || requestLine.length() == 0) {
                return null;
            }
            String[] parts = requestLine.split(" ");
            if (parts.length < 2) {
                return null;
            }
            Map<String, String> headers = new HashMap<>();
            String line;
            while ((line = reader.readLine()) != null && line.length() > 0) {
                int colon = line.indexOf(':');
                if (colon <= 0) {
                    continue;
                }
                headers.put(
                        line.substring(0, colon).trim().toLowerCase(Locale.US),
                        line.substring(colon + 1).trim());
            }
            int length = 0;
            try {
                length = Integer.parseInt(headers.get("content-length"));
            } catch (Exception ignored) {
            }
            char[] chars = new char[Math.max(0, Math.min(length, 65536))];
            int offset = 0;
            while (offset < chars.length) {
                int read = reader.read(chars, offset, chars.length - offset);
                if (read < 0) {
                    break;
                }
                offset += read;
            }
            String rawPath = parts[1];
            int query = rawPath.indexOf('?');
            String path = query >= 0 ? rawPath.substring(0, query) : rawPath;
            String queryString = query >= 0 ? rawPath.substring(query + 1) : "";
            return new HttpRequest(
                    parts[0].toUpperCase(Locale.US),
                    path,
                    queryString,
                    headers,
                    new String(chars, 0, offset));
        }
    }

    private static final class H264EncoderChoice {
        final String name;
        final int colorFormat;

        H264EncoderChoice(String name, int colorFormat) {
            this.name = name;
            this.colorFormat = colorFormat;
        }
    }

    private static final class Mp4MuxerState {
        final File file;
        MediaMuxer muxer;
        int track = -1;
        boolean started;

        Mp4MuxerState(File file) {
            this.file = file;
        }

        void start(MediaFormat format) throws IOException {
            if (started) {
                return;
            }
            muxer = new MediaMuxer(file.getAbsolutePath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            track = muxer.addTrack(format);
            muxer.start();
            started = true;
        }

        void close() {
            if (muxer == null) {
                return;
            }
            try {
                if (started) {
                    muxer.stop();
                }
            } catch (Exception ignored) {
            }
            try {
                muxer.release();
            } catch (Exception ignored) {
            }
            muxer = null;
            started = false;
        }
    }

    private static void closeQuietly(Object closeable) {
        if (closeable == null) {
            return;
        }
        try {
            if (closeable instanceof ServerSocket) {
                ((ServerSocket) closeable).close();
            } else if (closeable instanceof Socket) {
                ((Socket) closeable).close();
            }
        } catch (IOException ignored) {
        }
    }
}
