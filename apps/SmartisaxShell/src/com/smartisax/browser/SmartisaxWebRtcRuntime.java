package com.smartisax.browser;

import android.content.Context;
import android.hardware.display.VirtualDisplay;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjection.Callback;
import android.os.Handler;
import android.os.PowerManager;
import android.os.SystemClock;
import android.view.Surface;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.webrtc.CapturerObserver;
import org.webrtc.DataChannel;
import org.webrtc.DefaultVideoDecoderFactory;
import org.webrtc.DefaultVideoEncoderFactory;
import org.webrtc.EglBase;
import org.webrtc.IceCandidate;
import org.webrtc.JavaI420Buffer;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.RtpReceiver;
import org.webrtc.RtpParameters;
import org.webrtc.RtpSender;
import org.webrtc.RtpTransceiver;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;
import org.webrtc.SurfaceTextureHelper;
import org.webrtc.VideoFrame;
import org.webrtc.VideoSink;
import org.webrtc.VideoSource;
import org.webrtc.VideoTrack;

final class SmartisaxWebRtcRuntime {
    interface FrameProvider {
        Bitmap capture() throws IOException;

        Point displaySize();
    }

    interface InputHandler {
        JSONObject handle(JSONObject payload) throws IOException, JSONException;
    }

    private static final Object LOCK = new Object();
    private static final int MAX_SESSIONS = 2;
    private static final long SESSION_TTL_MS = 10 * 60 * 1000L;
    private static final int MIN_FRAME_WIDTH = 240;
    private static final int MAX_FRAME_WIDTH = 1080;
    private static final int MIN_FRAME_FPS = 1;
    private static final int MAX_FRAME_FPS = 90;
    private static final int DEFAULT_FRAME_WIDTH_PORTRAIT = 1080;
    private static final int DEFAULT_FRAME_HEIGHT_PORTRAIT = 1170;
    private static final int DEFAULT_FRAME_WIDTH_LANDSCAPE = 1080;
    private static final int DEFAULT_FRAME_FPS = 60;
    private static final int PRESENTATION_TRANSPORT_MAX_FPS = 60;
    private static final int BITRATE_MIN_BPS = 250000;
    private static final int BITRATE_MAX_BPS = 18000000;
    private static final int ENCODER_BURST_MIN_VIDEO_BITRATE_BPS = 4000000;
    private static final int ENCODER_BURST_TARGET_VIDEO_BITRATE_BPS = 8000000;
    private static final int ENCODER_BURST_MAX_VIDEO_BITRATE_BPS = 9000000;
    private static final int RVFC_TAIL_60HZ_TARGET_VIDEO_BITRATE_BPS = 7000000;
    private static final int RVFC_TAIL_60HZ_MAX_VIDEO_BITRATE_BPS = 7000000;
    private static final int RVFC_TAIL_60HZ_SENDER_MAX_FRAMERATE = 59;
    private static final int PACED_90_MIN_VIDEO_BITRATE_BPS = ENCODER_BURST_MIN_VIDEO_BITRATE_BPS;
    private static final int PACED_90_TARGET_VIDEO_BITRATE_BPS = ENCODER_BURST_TARGET_VIDEO_BITRATE_BPS;
    private static final int PACED_90_MAX_VIDEO_BITRATE_BPS = ENCODER_BURST_MAX_VIDEO_BITRATE_BPS;
    private static final int DEFAULT_MIN_VIDEO_BITRATE_BPS = ENCODER_BURST_MIN_VIDEO_BITRATE_BPS;
    private static final int DEFAULT_TARGET_VIDEO_BITRATE_BPS = ENCODER_BURST_TARGET_VIDEO_BITRATE_BPS;
    private static final int DEFAULT_MAX_VIDEO_BITRATE_BPS = ENCODER_BURST_MAX_VIDEO_BITRATE_BPS;
    private static final String BITRATE_POLICY = "runtime-tuning+presentation-transport-pacing+encoder-transport-burst-clamp+rvfc-media-tail-60hz-window";
    private static final String TRANSPORT_PACING_POLICY = "virtualdisplay-60fps-presentation-paced-90hz-input";
    private static final String ENCODER_TRANSPORT_BURST_POLICY = "1080p60-target-window-bitrate+late-start-frame-pump+maintain-framerate-sender";
    private static final String MEDIA_CALLBACK_TAIL_POLICY = "1080p60-rvfc-media-callback-tail-dephase+sender-59fps+7mbps-window+full-frame-forceFrame-spacing";
    private static final String CAPTURE_BACKEND_AUTO = "projection-auto";
    private static final String CAPTURE_BACKEND_PROJECTION = "projection-texture";
    private static final String CAPTURE_BACKEND_BITMAP = "bitmap-i420";
    private static final String DISPLAY_WAKE_POLICY = "webrtc-session-screen-wake-lock+activity-keep-screen-on";
    private static final int PROJECTION_MAX_PENDING_CONTINUITY_FRAMES = 1;
    private static final long PROJECTION_FORCE_FRAME_EARLY_MARGIN_MS = 1L;
    private static final long PROJECTION_INPUT_BOOST_MIN_INTERVAL_DIVISOR = 2L;
    private static final int PROJECTION_INPUT_BOOST_BURST_MAX_FRAMES = 4;
    private static final String PRESENTATION_TAIL_CADENCE_POLICY = "marker-visible-tail-presentation-cadence+full-frame-spacing-after-draw-urgent+rvfc-media-callback-tail-dephase";
    private static final String LATENCY_MODE = "latest-frame-only-queue-collapse+dual-phase-input-frame-boost+marker-visible-burst-boost+marker-burst-reschedule-until-accepted+boost-token-retain+60-90hz+event-time-input-priority+receiver-playout-delay-zero+quiet-presentation-surface+canvas-presenter-mode+presentation-transport-pacing+video-primary-roi-probe+raf-touch-photon-detect+marker-draw-synced-capture-boost+draw-urgent-input-frame-boost+encoder-transport-burst-clamp+marker-visible-tail-presentation-cadence+rvfc-media-callback-tail-dephase";
    private static final String FRAME_QUEUE_POLICY = "skip-forceFrame-when-captured-frame-is-fresh+coalesce-pending-forceFrame-after-input-marker+retain-boost-token-until-captured-frame+input-boost-half-interval-capture+marker-burst-input-priority+marker-burst-reschedule-until-accepted+marker-draw-synced-capture-boost+draw-urgent-bypass-half-interval+marker-tail-full-frame-spacing+virtualdisplay-60fps-presentation-paced-90hz-input+rvfc-tail-full-frame-forceFrame-spacing";
    private static final Map<String, RuntimeSession> SESSIONS = new LinkedHashMap<>();
    private static RuntimeConfig currentConfig = RuntimeConfig.defaults();
    private static boolean initialized;
    private static EglBase eglBase;
    private static PeerConnectionFactory factory;

    private SmartisaxWebRtcRuntime() {
    }

    static JSONObject statusJson() throws JSONException {
        RuntimeConfig config = configSnapshot();
        JSONObject json = new JSONObject();
        json.put("available", true);
        json.put("backend", "io.github.webrtc-sdk:android");
        json.put("artifactVersion", "125.6422.07");
        json.put("nativeLibrary", "jingle_peerconnection_so");
        json.put("mode", "native-libwebrtc");
        json.put("dtlsSrtp", true);
        json.put("codecPolicy", "latency-first-modern-fallback");
        json.put("codecPreference", "H264,AV1,VP9,H265");
        json.put("codecFallback", "H264");
        json.put("input", "webrtc-datachannel-input");
        json.put("inputChannel", "smartisax-input");
        json.put("inputMoveChannel", "smartisax-input-move");
        json.put("inputMoveStream", "touchStart-touchMoveBatch-touchEnd-low-retransmit+event-time-preserving-move-stream");
        json.put("touchPhotonMarker", "touch-photon-marker+predictive-status+dual-phase-input-frame-boost+marker-visible-burst-boost+marker-burst-reschedule-until-accepted+marker-draw-synced-capture-boost+draw-urgent-input-frame-boost+boost-token-retain+60-90hz+input-priority-frame+marker-visible-tail-presentation-cadence");
        json.put("ackJitterRepair", "dual-datachannel+compact-move-acks+batched-move-stream");
        json.put("chromePresentationGapRepair", "rvfc-marker-prediction+throttled-smoke-logging+dual-phase-input-frame-boost+marker-visible-burst-boost+marker-burst-reschedule-until-accepted+marker-draw-synced-capture-boost+draw-urgent-input-frame-boost+boost-token-retain+60-90hz+receiver-playout-delay-zero+motion-content-hint+rtc-playout-stats+quiet-presentation-surface+raf-mainthread-drift+canvas-presenter-mode+rvfc-vs-raf-vs-canvas+presentation-transport-pacing+video-primary-roi-probe+raf-touch-photon-detect+marker-visible-tail-presentation-cadence+rvfc-media-callback-tail-dephase");
        json.put("displayWakeGuard", DISPLAY_WAKE_POLICY);
        json.put("presentationProbe", "video-primary-roi-probe+raf-touch-photon-detect");
        json.put("refreshRateProfiles", "1080p60+1080p90");
        json.put("transportPacing", TRANSPORT_PACING_POLICY);
        json.put("encoderTransportBurstRepair", ENCODER_TRANSPORT_BURST_POLICY);
        json.put("mediaCallbackTailRepair", MEDIA_CALLBACK_TAIL_POLICY);
        json.put("httpInput", false);
        JSONObject framePump = new JSONObject();
        framePump.put("widthPortrait", config.frameWidthPortrait);
        framePump.put("heightPortrait", DEFAULT_FRAME_HEIGHT_PORTRAIT);
        framePump.put("widthLandscape", config.frameWidthLandscape);
        framePump.put("fps", config.presentationFps);
        framePump.put("requestedFps", config.fps);
        framePump.put("presentationFps", config.presentationFps);
        framePump.put("transportFps", config.presentationFps);
        framePump.put("inputRefreshHz", config.inputRefreshHz);
        framePump.put("minVideoBitrateBps", config.minBitrateBps);
        framePump.put("targetVideoBitrateBps", config.targetBitrateBps);
        framePump.put("maxVideoBitrateBps", config.maxBitrateBps);
        framePump.put("bitratePolicy", config.bitratePolicy);
        framePump.put("captureBackend", config.captureBackend);
        framePump.put("latency", "low-latency-screencast");
        framePump.put("copyPath", "projection-texture avoids Java Bitmap/I420 conversion when available");
        framePump.put("latencyMode", LATENCY_MODE);
        framePump.put("queuePolicy", FRAME_QUEUE_POLICY);
        framePump.put("transportPacing", TRANSPORT_PACING_POLICY);
        framePump.put("encoderTransportBurstRepair", ENCODER_TRANSPORT_BURST_POLICY);
        framePump.put("mediaCallbackTailRepair", MEDIA_CALLBACK_TAIL_POLICY);
        framePump.put("presentationTailCadence", PRESENTATION_TAIL_CADENCE_POLICY);
        framePump.put("senderMinVideoBitrateBps", config.senderMinBitrateBps());
        framePump.put("senderTargetVideoBitrateBps", config.senderTargetBitrateBps());
        framePump.put("senderMaxVideoBitrateBps", config.senderMaxBitrateBps());
        framePump.put("senderMaxFramerate", config.senderMaxFramerate());
        framePump.put("senderDegradationPreference", "MAINTAIN_FRAMERATE");
        framePump.put("framePumpStartPolicy", "late-start-after-local-sdp");
        framePump.put("maxPendingContinuityFrames", PROJECTION_MAX_PENDING_CONTINUITY_FRAMES);
        json.put("framePumpDefaults", framePump);
        json.put("runtimeTuning", true);
        json.put("targetMinimum", "1080p60");
        json.put("targetDefault", "1080p90-input-60fps-presentation");
        json.put("runtimeConfig", config.toJson());
        json.put("runtimeConfigLimits", RuntimeConfig.limitsJson());
        synchronized (LOCK) {
            cleanupSessionsLocked(false);
            json.put("initialized", initialized);
            json.put("activeSessions", SESSIONS.size());
            json.put("sessions", sessionsJsonLocked());
        }
        return json;
    }

    static void requestInputFrameBoost(String reason) {
        synchronized (LOCK) {
            cleanupSessionsLocked(false);
            for (RuntimeSession session : SESSIONS.values()) {
                session.requestInputFrameBoost(reason);
            }
        }
    }

    static void requestUrgentInputFrameBoost(String reason) {
        synchronized (LOCK) {
            cleanupSessionsLocked(false);
            for (RuntimeSession session : SESSIONS.values()) {
                session.requestUrgentInputFrameBoost(reason);
            }
        }
    }

    static void requestInputFrameBoostBurst(String reason, int frameCount) {
        synchronized (LOCK) {
            cleanupSessionsLocked(false);
            for (RuntimeSession session : SESSIONS.values()) {
                session.requestInputFrameBoostBurst(reason, frameCount);
            }
        }
    }

    static JSONObject configJson() throws JSONException {
        JSONObject json = new JSONObject();
        synchronized (LOCK) {
            cleanupSessionsLocked(false);
            json.put("ok", true);
            json.put("mode", "native-libwebrtc-config");
            json.put("config", currentConfig.toJson());
            json.put("limits", RuntimeConfig.limitsJson());
            json.put("activeSessions", SESSIONS.size());
            json.put("appliesTo", "new-webrtc-sessions");
            json.put("volatile", true);
            return json;
        }
    }

    static JSONObject captureProbeJson(Context context, Point display) throws JSONException {
        JSONObject json = SmartisaxProjectionCapture.probe(context.getApplicationContext(), display);
        json.put("activeRuntimeConfig", configSnapshot().toJson());
        json.put("bitmapFallback", CAPTURE_BACKEND_BITMAP);
        json.put("preferredBackend", CAPTURE_BACKEND_PROJECTION);
        json.put("autoBackend", CAPTURE_BACKEND_AUTO);
        return json;
    }

    static JSONObject updateConfig(JSONObject body) throws JSONException {
        JSONObject source = body == null ? new JSONObject() : body.optJSONObject("config");
        if (source == null) {
            source = body == null ? new JSONObject() : body;
        }
        JSONObject json = new JSONObject();
        synchronized (LOCK) {
            cleanupSessionsLocked(false);
            RuntimeConfig before = currentConfig;
            RuntimeConfig after = RuntimeConfig.fromJson(source, before);
            currentConfig = after;
            json.put("ok", true);
            json.put("mode", "native-libwebrtc-config");
            json.put("before", before.toJson());
            json.put("config", after.toJson());
            json.put("limits", RuntimeConfig.limitsJson());
            json.put("changed", !before.equalsConfig(after));
            json.put("activeSessions", SESSIONS.size());
            json.put("appliesTo", "new-webrtc-sessions");
            json.put("volatile", true);
            return json;
        }
    }

    static JSONObject closeSessions(JSONObject body) throws JSONException {
        String requestedId = body == null ? "" : body.optString("sessionId", "");
        int before;
        int closed = 0;
        synchronized (LOCK) {
            before = SESSIONS.size();
            if (requestedId.length() == 0 || "all".equals(requestedId)) {
                Iterator<Map.Entry<String, RuntimeSession>> iterator = SESSIONS.entrySet().iterator();
                while (iterator.hasNext()) {
                    Map.Entry<String, RuntimeSession> entry = iterator.next();
                    entry.getValue().close();
                    iterator.remove();
                    closed += 1;
                }
            } else {
                RuntimeSession session = SESSIONS.remove(requestedId);
                if (session != null) {
                    session.close();
                    closed = 1;
                }
            }
            JSONObject json = new JSONObject();
            json.put("ok", true);
            json.put("mode", "native-libwebrtc-close");
            json.put("requestedSessionId", requestedId);
            json.put("before", before);
            json.put("closed", closed);
            json.put("activeSessions", SESSIONS.size());
            json.put("sessions", sessionsJsonLocked());
            return json;
        }
    }

    static JSONObject answer(Context context, FrameProvider frameProvider, InputHandler inputHandler, JSONObject body)
            throws JSONException, IOException {
        String type = body.optString("type", "");
        String sdp = body.optString("sdp", "");
        if (!"offer".equalsIgnoreCase(type) || sdp.length() == 0) {
            JSONObject error = new JSONObject();
            error.put("ok", false);
            error.put("mode", "native-libwebrtc-answer");
            error.put("error", "missing_offer_sdp");
            return error;
        }

        long started = SystemClock.elapsedRealtime();
        ensureInitialized(context);
        cleanupSessions(false);

        RuntimeConfig config = configSnapshot();
        RuntimeSession session = new RuntimeSession(context.getApplicationContext(), frameProvider, inputHandler, config);
        NativeAnswer answer = session.answer(sdp);
        synchronized (LOCK) {
            SESSIONS.put(session.id, session);
            cleanupSessionsLocked(false);
        }

        JSONObject json = new JSONObject();
        json.put("ok", true);
        json.put("mode", "native-libwebrtc-answer");
        json.put("nativeWebRtcRuntime", true);
        json.put("dtlsSrtp", true);
        json.put("srtp", true);
        json.put("ice", "host-candidates-no-stun-direct-lan");
        json.put("sessionId", session.id);
        json.put("elapsedMs", SystemClock.elapsedRealtime() - started);
        json.put("offerType", type);
        json.put("offerSdpBytes", sdp.length());
        json.put("answerSdpBytes", answer.sdp.length());
        json.put("selectedCodec", selectedVideoCodec(answer.sdp));
        json.put("iceGatheringState", answer.iceGatheringState);
        json.put("iceCandidates", answer.candidates);
        json.put("localCandidateCount", answer.candidates.length());
        json.put("framePump", session.framePumpJson());
        json.put("bitrate", session.bitrateJson());
        json.put("runtimeConfig", config.toJson());
        json.put("input", "webrtc-datachannel-input");
        json.put("inputChannel", "smartisax-input");
        json.put("httpInput", false);
        JSONObject answerJson = new JSONObject();
        answerJson.put("type", "answer");
        answerJson.put("sdp", answer.sdp);
        json.put("answer", answerJson);
        return json;
    }

    private static RuntimeConfig configSnapshot() {
        synchronized (LOCK) {
            return currentConfig;
        }
    }

    private static void ensureInitialized(Context context) {
        synchronized (LOCK) {
            if (initialized) {
                return;
            }
            PeerConnectionFactory.InitializationOptions options =
                    PeerConnectionFactory.InitializationOptions.builder(context.getApplicationContext())
                            .setEnableInternalTracer(false)
                            .setFieldTrials("WebRTC-H264HighProfile/Enabled/")
                            .setNativeLibraryName("jingle_peerconnection_so")
                            .createInitializationOptions();
            PeerConnectionFactory.initialize(options);
            eglBase = EglBase.create();
            PeerConnectionFactory.Options factoryOptions = new PeerConnectionFactory.Options();
            factoryOptions.disableEncryption = false;
            factoryOptions.disableNetworkMonitor = false;
            factory = PeerConnectionFactory.builder()
                    .setOptions(factoryOptions)
                    .setVideoEncoderFactory(new DefaultVideoEncoderFactory(
                            eglBase.getEglBaseContext(), true, true))
                    .setVideoDecoderFactory(new DefaultVideoDecoderFactory(eglBase.getEglBaseContext()))
                    .createPeerConnectionFactory();
            initialized = true;
        }
    }

    private static void cleanupSessions(boolean force) {
        synchronized (LOCK) {
            cleanupSessionsLocked(force);
        }
    }

    private static void cleanupSessionsLocked(boolean force) {
        long now = SystemClock.elapsedRealtime();
        Iterator<Map.Entry<String, RuntimeSession>> iterator = SESSIONS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<String, RuntimeSession> entry = iterator.next();
            if (force || now - entry.getValue().createdElapsedMs > SESSION_TTL_MS) {
                entry.getValue().close();
                iterator.remove();
            }
        }
        while (SESSIONS.size() > MAX_SESSIONS) {
            Iterator<Map.Entry<String, RuntimeSession>> oldest = SESSIONS.entrySet().iterator();
            if (!oldest.hasNext()) {
                break;
            }
            Map.Entry<String, RuntimeSession> entry = oldest.next();
            entry.getValue().close();
            oldest.remove();
        }
    }

    @SuppressWarnings("deprecation")
    private static final class ProjectionDisplayGuard {
        private final String policy = DISPLAY_WAKE_POLICY;
        private final String reason;
        private final long acquiredElapsedMs;
        private long releasedElapsedMs;
        private PowerManager.WakeLock wakeLock;
        private boolean acquired;
        private String error = "";

        private ProjectionDisplayGuard(String reason) {
            this.reason = reason == null || reason.length() == 0 ? "webrtc-session" : reason;
            this.acquiredElapsedMs = SystemClock.elapsedRealtime();
        }

        static ProjectionDisplayGuard acquire(Context context, String reason) {
            ProjectionDisplayGuard guard = new ProjectionDisplayGuard(reason);
            try {
                PowerManager powerManager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
                if (powerManager == null) {
                    guard.error = "power_manager_unavailable";
                    return guard;
                }
                PowerManager.WakeLock lock = powerManager.newWakeLock(
                        PowerManager.SCREEN_BRIGHT_WAKE_LOCK
                                | PowerManager.ACQUIRE_CAUSES_WAKEUP
                                | PowerManager.ON_AFTER_RELEASE,
                        "Smartisax:PortalWebRtc");
                lock.setReferenceCounted(false);
                lock.acquire(SESSION_TTL_MS + 30000L);
                guard.wakeLock = lock;
                guard.acquired = lock.isHeld();
            } catch (RuntimeException e) {
                guard.error = e.toString();
            }
            return guard;
        }

        void release() {
            releasedElapsedMs = SystemClock.elapsedRealtime();
            if (wakeLock == null) {
                return;
            }
            try {
                if (wakeLock.isHeld()) {
                    wakeLock.release();
                }
            } catch (RuntimeException e) {
                error = e.toString();
            } finally {
                wakeLock = null;
            }
        }

        JSONObject toJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("policy", policy);
            json.put("reason", reason);
            json.put("acquired", acquired);
            json.put("held", wakeLock != null && wakeLock.isHeld());
            json.put("acquiredElapsedMs", acquiredElapsedMs);
            json.put("releasedElapsedMs", releasedElapsedMs);
            json.put("error", error);
            return json;
        }
    }

    private static final class NativeAnswer {
        final String sdp;
        final String iceGatheringState;
        final JSONArray candidates;

        NativeAnswer(String sdp, String iceGatheringState, JSONArray candidates) {
            this.sdp = sdp;
            this.iceGatheringState = iceGatheringState;
            this.candidates = candidates;
        }
    }

    private static final class RuntimeSession {
        final String id = UUID.randomUUID().toString();
        final long createdElapsedMs = SystemClock.elapsedRealtime();
        final Context context;
        final FrameProvider frameProvider;
        final InputHandler inputHandler;
        final RuntimeConfig config;
        final List<IceCandidate> candidates = Collections.synchronizedList(new ArrayList<IceCandidate>());
        PeerObserver peerObserver;
        PeerConnection peerConnection;
        VideoSource videoSource;
        VideoTrack videoTrack;
        RtpSender videoSender;
        CapturePump framePump;
        ProjectionDisplayGuard displayGuard;
        String videoBitratePolicy = BITRATE_POLICY;
        String videoBitrateStage = "";
        String videoBitrateError = "";
        int videoBitrateEncodingCount;
        int videoSenderMinBitrateBps;
        int videoSenderTargetBitrateBps;
        int videoSenderMaxBitrateBps;
        int videoSenderMaxFramerate;
        String videoSenderDegradationPreference = "";
        boolean videoBitrateApplied;

        RuntimeSession(Context context, FrameProvider frameProvider, InputHandler inputHandler, RuntimeConfig config) {
            this.context = context;
            this.frameProvider = frameProvider;
            this.inputHandler = inputHandler;
            this.config = config;
            this.videoBitratePolicy = config.bitratePolicy;
        }

        NativeAnswer answer(String remoteSdp) throws JSONException, IOException {
            try {
            PeerConnection.RTCConfiguration configuration =
                    new PeerConnection.RTCConfiguration(Collections.<PeerConnection.IceServer>emptyList());
            configuration.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN;
            configuration.bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE;
            configuration.rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE;
            configuration.tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED;
            configuration.continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_ONCE;
            configuration.iceTransportsType = PeerConnection.IceTransportsType.ALL;
            configuration.candidateNetworkPolicy = PeerConnection.CandidateNetworkPolicy.ALL;
            configuration.keyType = PeerConnection.KeyType.ECDSA;

            peerObserver = new PeerObserver(candidates, inputHandler);
            peerConnection = factory.createPeerConnection(configuration, peerObserver);
            if (peerConnection == null) {
                throw new IOException("create_peer_connection_failed");
            }

            videoSource = factory.createVideoSource(true);
            videoSource.setIsScreencast(true);
            Point display = frameProvider.displaySize();
            videoSource.adaptOutputFormat(config.targetWidth(display), config.targetHeight(display), config.videoFps());
            videoTrack = factory.createVideoTrack("smartisax-r2-screen", videoSource);
            videoTrack.setEnabled(true);
            videoSender = peerConnection.addTrack(videoTrack, Collections.singletonList("smartisax-screen"));
            applyVideoSenderParameters("after-addTrack");

            awaitSetRemote(new SessionDescription(SessionDescription.Type.OFFER, remoteSdp));
            SessionDescription answer = awaitCreateAnswer();
            awaitSetLocal(answer);
            applyVideoSenderParameters("after-setLocal");
            peerObserver.awaitIceComplete(2200);
            SessionDescription local = peerConnection.getLocalDescription();
            String sdp = local == null ? answer.description : local.description;
            displayGuard = ProjectionDisplayGuard.acquire(context, "webrtc-session");
            startFramePump(videoSource.getCapturerObserver());
            return new NativeAnswer(sdp, peerObserver.iceGatheringState(), candidatesJson(candidates));
            } catch (JSONException e) {
                close();
                throw e;
            } catch (IOException e) {
                close();
                throw e;
            } catch (RuntimeException e) {
                close();
                throw e;
            }
        }

        JSONObject framePumpJson() throws JSONException {
            JSONObject json = new JSONObject();
            if (framePump == null) {
                json.put("running", false);
                return json;
            }
            json.put("running", framePump.running());
            json.put("backend", framePump.backend());
            json.put("copyPath", framePump.copyPath());
            json.put("width", framePump.width());
            json.put("height", framePump.height());
            json.put("fps", framePump.fps());
            json.put("requestedFps", config.fps);
            json.put("presentationFps", config.presentationFps);
            json.put("transportFps", config.presentationFps);
            json.put("inputRefreshHz", config.inputRefreshHz);
            json.put("capturedFrames", framePump.capturedFrames());
            json.put("lastError", framePump.lastError());
            json.put("startedElapsedMs", framePump.startedElapsedMs());
            json.put("lastFrameElapsedMs", framePump.lastFrameElapsedMs());
            json.put("fallbackError", framePump.fallbackError());
            json.put("displayWakeGuard", displayGuard == null ? JSONObject.NULL : displayGuard.toJson());
            if (framePump instanceof ProjectionTextureFramePump) {
                ProjectionTextureFramePump projectionPump = (ProjectionTextureFramePump) framePump;
                json.put("continuityMode", projectionPump.continuityMode());
                json.put("latencyMode", projectionPump.latencyMode());
                json.put("queuePolicy", projectionPump.queuePolicy());
                json.put("maxPendingContinuityFrames", projectionPump.maxPendingContinuityFrames());
                json.put("sourceFrames", projectionPump.sourceFrames());
                json.put("droppedFrames", projectionPump.droppedFrames());
                json.put("continuityFrameRequests", projectionPump.continuityFrameRequests());
                json.put("continuityFrameSkips", projectionPump.continuityFrameSkips());
                json.put("continuityFrames", projectionPump.continuityFrames());
                json.put("inputFrameBoostRequests", projectionPump.inputFrameBoostRequests());
                json.put("inputFrameBoostSkips", projectionPump.inputFrameBoostSkips());
                json.put("inputFrameBoostFrames", projectionPump.inputFrameBoostFrames());
                json.put("inputFrameBoostUrgentRequests", projectionPump.inputFrameBoostUrgentRequests());
                json.put("inputFrameBoostUrgentSkips", projectionPump.inputFrameBoostUrgentSkips());
                json.put("inputFrameBoostUrgentFrames", projectionPump.inputFrameBoostUrgentFrames());
                json.put("inputFrameBoostBurstRequests", projectionPump.inputFrameBoostBurstRequests());
                json.put("inputFrameBoostBurstFrames", projectionPump.inputFrameBoostBurstFrames());
                json.put("inputFrameBoostBurstSkips", projectionPump.inputFrameBoostBurstSkips());
                json.put("inputFrameBoostBurstRetries", projectionPump.inputFrameBoostBurstRetries());
                json.put("inputFrameBoostBurstPendingFrames", projectionPump.inputFrameBoostBurstPendingFrames());
                json.put("inputFrameBoostBurstActiveFrames", projectionPump.inputFrameBoostBurstActiveFrames());
                json.put("inputFrameBoostBurstMaxFrames", projectionPump.inputFrameBoostBurstMaxFrames());
                json.put("inputFrameBoostBurstCadenceMs", projectionPump.inputFrameBoostBurstCadenceMs());
                json.put("mediaCallbackTailRepair", projectionPump.mediaCallbackTailRepair());
                json.put("mediaCallbackTailFrameSpacingMs", projectionPump.mediaCallbackTailFrameSpacingMs());
                json.put("presentationTailCadence", projectionPump.presentationTailCadence());
                json.put("inputFrameBoostMinIntervalMs", projectionPump.inputFrameBoostMinIntervalMs());
                json.put("timestampRewriteFrames", projectionPump.timestampRewriteFrames());
                json.put("lastSourceFrameElapsedMs", projectionPump.lastSourceFrameElapsedMs());
                json.put("lastContinuityFrameRequestElapsedMs", projectionPump.lastContinuityFrameRequestElapsedMs());
                json.put("lastContinuityFrameSkipElapsedMs", projectionPump.lastContinuityFrameSkipElapsedMs());
                json.put("lastContinuityFrameElapsedMs", projectionPump.lastContinuityFrameElapsedMs());
                json.put("lastInputFrameBoostRequestElapsedMs", projectionPump.lastInputFrameBoostRequestElapsedMs());
                json.put("lastInputFrameBoostSkipElapsedMs", projectionPump.lastInputFrameBoostSkipElapsedMs());
                json.put("lastInputFrameBoostElapsedMs", projectionPump.lastInputFrameBoostElapsedMs());
                json.put("lastInputFrameBoostUrgentRequestElapsedMs", projectionPump.lastInputFrameBoostUrgentRequestElapsedMs());
                json.put("lastInputFrameBoostUrgentSkipElapsedMs", projectionPump.lastInputFrameBoostUrgentSkipElapsedMs());
                json.put("lastInputFrameBoostUrgentFrameElapsedMs", projectionPump.lastInputFrameBoostUrgentFrameElapsedMs());
                json.put("lastInputFrameBoostBurstRequestElapsedMs", projectionPump.lastInputFrameBoostBurstRequestElapsedMs());
                json.put("lastInputFrameBoostBurstFrameElapsedMs", projectionPump.lastInputFrameBoostBurstFrameElapsedMs());
                json.put("lastInputFrameBoostBurstRetryElapsedMs", projectionPump.lastInputFrameBoostBurstRetryElapsedMs());
                json.put("lastTimestampRewriteElapsedMs", projectionPump.lastTimestampRewriteElapsedMs());
            }
            json.put("bitratePolicy", videoBitratePolicy);
            json.put("transportPacing", TRANSPORT_PACING_POLICY);
            json.put("encoderTransportBurstRepair", ENCODER_TRANSPORT_BURST_POLICY);
            json.put("mediaCallbackTailRepair", MEDIA_CALLBACK_TAIL_POLICY);
            json.put("presentationTailCadence", PRESENTATION_TAIL_CADENCE_POLICY);
            json.put("minBitrateBps", config.minBitrateBps);
            json.put("targetBitrateBps", config.targetBitrateBps);
            json.put("maxBitrateBps", config.maxBitrateBps);
            json.put("senderMinBitrateBps", videoSenderMinBitrateBps);
            json.put("senderTargetBitrateBps", videoSenderTargetBitrateBps);
            json.put("senderMaxBitrateBps", videoSenderMaxBitrateBps);
            json.put("senderMaxFramerate", videoSenderMaxFramerate);
            json.put("senderDegradationPreference", videoSenderDegradationPreference);
            json.put("framePumpStartPolicy", "late-start-after-local-sdp");
            json.put("bitrateApplied", videoBitrateApplied);
            json.put("bitrateStage", videoBitrateStage);
            json.put("bitrateError", videoBitrateError);
            json.put("bitrateEncodingCount", videoBitrateEncodingCount);
            json.put("runtimeConfig", config.toJson());
            return json;
        }

        JSONObject bitrateJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("policy", videoBitratePolicy);
            json.put("minBitrateBps", config.minBitrateBps);
            json.put("targetBitrateBps", config.targetBitrateBps);
            json.put("maxBitrateBps", config.maxBitrateBps);
            json.put("senderMinBitrateBps", videoSenderMinBitrateBps);
            json.put("senderTargetBitrateBps", videoSenderTargetBitrateBps);
            json.put("senderMaxBitrateBps", videoSenderMaxBitrateBps);
            json.put("senderMaxFramerate", videoSenderMaxFramerate);
            json.put("senderDegradationPreference", videoSenderDegradationPreference);
            json.put("encoderTransportBurstRepair", ENCODER_TRANSPORT_BURST_POLICY);
            json.put("mediaCallbackTailRepair", MEDIA_CALLBACK_TAIL_POLICY);
            json.put("framePumpStartPolicy", "late-start-after-local-sdp");
            json.put("maxFramerate", config.senderMaxFramerate());
            json.put("captureFramerate", config.videoFps());
            json.put("requestedFramerate", config.fps);
            json.put("presentationFps", config.presentationFps);
            json.put("inputRefreshHz", config.inputRefreshHz);
            json.put("applied", videoBitrateApplied);
            json.put("stage", videoBitrateStage);
            json.put("encodingCount", videoBitrateEncodingCount);
            json.put("error", videoBitrateError);
            json.put("runtimeConfig", config.toJson());
            return json;
        }

        JSONObject sessionJson(long now) throws JSONException {
            JSONObject json = new JSONObject();
            json.put("id", id);
            json.put("ageMs", Math.max(0L, now - createdElapsedMs));
            json.put("hasPeerConnection", peerConnection != null);
            json.put("framePump", framePumpJson());
            json.put("input", peerObserver == null ? null : peerObserver.inputJson());
            return json;
        }

        void close() {
            if (framePump != null) {
                framePump.stop();
                framePump = null;
            }
            if (displayGuard != null) {
                displayGuard.release();
                displayGuard = null;
            }
            if (peerObserver != null) {
                peerObserver.closeDataChannel();
            }
            if (peerConnection != null) {
                peerConnection.close();
                peerConnection.dispose();
                peerConnection = null;
            }
            if (videoTrack != null) {
                videoTrack.dispose();
                videoTrack = null;
            }
            if (videoSource != null) {
                videoSource.dispose();
                videoSource = null;
            }
        }

        void requestInputFrameBoost(String reason) {
            if (framePump instanceof ProjectionTextureFramePump) {
                ((ProjectionTextureFramePump) framePump).requestInputFrameBoost(reason);
            }
        }

        void requestUrgentInputFrameBoost(String reason) {
            if (framePump instanceof ProjectionTextureFramePump) {
                ((ProjectionTextureFramePump) framePump).requestUrgentInputFrameBoost(reason);
            }
        }

        void requestInputFrameBoostBurst(String reason, int frameCount) {
            if (framePump instanceof ProjectionTextureFramePump) {
                ((ProjectionTextureFramePump) framePump).requestInputFrameBoostBurst(reason, frameCount);
            }
        }

        private void startFramePump(CapturerObserver observer) throws IOException {
            if (CAPTURE_BACKEND_BITMAP.equals(config.captureBackend)) {
                framePump = new ScreenFramePump(frameProvider, observer, config, "", "");
                framePump.start();
                return;
            }
            try {
                framePump = new ProjectionTextureFramePump(context, frameProvider, observer, config);
                framePump.start();
            } catch (Throwable t) {
                if (CAPTURE_BACKEND_AUTO.equals(config.captureBackend)) {
                    framePump = new ScreenFramePump(frameProvider, observer, config, CAPTURE_BACKEND_PROJECTION, t.toString());
                    framePump.start();
                    return;
                }
                throw new IOException("projection_texture_frame_pump_unavailable", t);
            }
        }

        private void awaitSetRemote(SessionDescription description) throws IOException {
            AwaitSdpObserver observer = new AwaitSdpObserver();
            peerConnection.setRemoteDescription(observer, description);
            observer.await("set_remote_description");
        }

        private SessionDescription awaitCreateAnswer() throws IOException {
            AwaitSdpObserver observer = new AwaitSdpObserver();
            peerConnection.createAnswer(observer, new MediaConstraints());
            observer.await("create_answer");
            if (observer.description == null) {
                throw new IOException("create_answer_returned_null");
            }
            return observer.description;
        }

        private void awaitSetLocal(SessionDescription description) throws IOException {
            AwaitSdpObserver observer = new AwaitSdpObserver();
            peerConnection.setLocalDescription(observer, description);
            observer.await("set_local_description");
        }

        private void applyVideoSenderParameters(String stage) {
            videoBitrateStage = stage;
            videoBitratePolicy = config.bitratePolicy;
            videoBitrateError = "";
            if (videoSender == null) {
                videoBitrateApplied = false;
                videoBitrateEncodingCount = 0;
                videoSenderMinBitrateBps = 0;
                videoSenderTargetBitrateBps = 0;
                videoSenderMaxBitrateBps = 0;
                videoSenderMaxFramerate = 0;
                videoSenderDegradationPreference = "";
                videoBitrateError = "video_sender_unavailable";
                return;
            }
            try {
                RtpParameters parameters = videoSender.getParameters();
                if (parameters == null || parameters.encodings == null || parameters.encodings.isEmpty()) {
                    videoBitrateApplied = false;
                    videoBitrateEncodingCount = 0;
                    videoSenderMinBitrateBps = 0;
                    videoSenderTargetBitrateBps = 0;
                    videoSenderMaxBitrateBps = 0;
                    videoSenderMaxFramerate = 0;
                    videoSenderDegradationPreference = "";
                    videoBitrateError = "sender_parameters_no_encodings";
                    return;
                }
                parameters.degradationPreference = RtpParameters.DegradationPreference.MAINTAIN_FRAMERATE;
                videoSenderMinBitrateBps = config.senderMinBitrateBps();
                videoSenderTargetBitrateBps = config.senderTargetBitrateBps();
                videoSenderMaxBitrateBps = config.senderMaxBitrateBps();
                videoSenderMaxFramerate = config.senderMaxFramerate();
                videoSenderDegradationPreference = String.valueOf(parameters.degradationPreference);
                videoBitrateEncodingCount = parameters.encodings.size();
                for (RtpParameters.Encoding encoding : parameters.encodings) {
                    if (encoding == null) {
                        continue;
                    }
                    encoding.active = true;
                    encoding.minBitrateBps = Integer.valueOf(videoSenderMinBitrateBps);
                    encoding.maxBitrateBps = Integer.valueOf(videoSenderMaxBitrateBps);
                    encoding.maxFramerate = Integer.valueOf(videoSenderMaxFramerate);
                }
                videoBitrateApplied = videoSender.setParameters(parameters);
                if (!videoBitrateApplied) {
                    videoBitrateError = "set_parameters_returned_false";
                }
            } catch (Throwable t) {
                videoBitrateApplied = false;
                videoBitrateError = t.toString();
            }
        }
    }

    private static final class PeerObserver implements PeerConnection.Observer {
        private final List<IceCandidate> candidates;
        private final InputHandler inputHandler;
        private final CountDownLatch iceComplete = new CountDownLatch(1);
        private volatile String iceGatheringState = "";
        private volatile DataChannel inputChannel;
        private volatile DataChannel moveChannel;
        private volatile String inputChannelLabel = "";
        private volatile String inputChannelState = "";
        private volatile String moveChannelLabel = "";
        private volatile String moveChannelState = "";
        private volatile String lastInputJson = "";

        PeerObserver(List<IceCandidate> candidates, InputHandler inputHandler) {
            this.candidates = candidates;
            this.inputHandler = inputHandler;
        }

        void awaitIceComplete(long timeoutMs) {
            try {
                iceComplete.await(timeoutMs, TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        String iceGatheringState() {
            return iceGatheringState;
        }

        JSONObject inputJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("transport", "RTCDataChannel");
            json.put("label", inputChannelLabel);
            json.put("state", inputChannelState);
            json.put("ready", "OPEN".equals(inputChannelState));
            json.put("moveLabel", moveChannelLabel);
            json.put("moveState", moveChannelState);
            json.put("moveReady", "OPEN".equals(moveChannelState));
            json.put("last", lastInputJson.length() == 0 ? JSONObject.NULL : new JSONObject(lastInputJson));
            return json;
        }

        void closeDataChannel() {
            DataChannel channel = inputChannel;
            DataChannel move = moveChannel;
            inputChannel = null;
            moveChannel = null;
            inputChannelState = "CLOSED";
            moveChannelState = "CLOSED";
            closeChannel(channel);
            closeChannel(move);
        }

        @Override
        public void onSignalingChange(PeerConnection.SignalingState state) {
        }

        @Override
        public void onIceConnectionChange(PeerConnection.IceConnectionState state) {
        }

        @Override
        public void onIceConnectionReceivingChange(boolean receiving) {
        }

        @Override
        public void onIceGatheringChange(PeerConnection.IceGatheringState state) {
            iceGatheringState = String.valueOf(state);
            if (state == PeerConnection.IceGatheringState.COMPLETE) {
                iceComplete.countDown();
            }
        }

        @Override
        public void onIceCandidate(IceCandidate candidate) {
            if (candidate != null) {
                candidates.add(candidate);
            }
        }

        @Override
        public void onIceCandidatesRemoved(IceCandidate[] removed) {
        }

        @Override
        public void onAddStream(MediaStream stream) {
        }

        @Override
        public void onRemoveStream(MediaStream stream) {
        }

        @Override
        public void onDataChannel(DataChannel dataChannel) {
            if (dataChannel == null) {
                return;
            }
            String label = safeLabel(dataChannel);
            boolean isMoveChannel = label.toLowerCase().contains("move");
            if (isMoveChannel) {
                moveChannel = dataChannel;
                moveChannelLabel = label;
                moveChannelState = String.valueOf(dataChannel.state());
            } else {
                inputChannel = dataChannel;
                inputChannelLabel = label;
                inputChannelState = String.valueOf(dataChannel.state());
            }
            dataChannel.registerObserver(new DataChannel.Observer() {
                @Override
                public void onBufferedAmountChange(long previousAmount) {
                }

                @Override
                public void onStateChange() {
                    updateChannelState(dataChannel);
                }

                @Override
                public void onMessage(DataChannel.Buffer buffer) {
                    handleDataChannelMessage(dataChannel, buffer);
                }
            });
        }

        @Override
        public void onRenegotiationNeeded() {
        }

        @Override
        public void onAddTrack(RtpReceiver receiver, MediaStream[] streams) {
        }

        @Override
        public void onTrack(RtpTransceiver transceiver) {
        }

        private void handleDataChannelMessage(DataChannel dataChannel, DataChannel.Buffer buffer) {
            JSONObject ack = new JSONObject();
            long receivedElapsedMs = SystemClock.elapsedRealtime();
            try {
                if (buffer == null || buffer.binary) {
                    throw new IOException("input_message_must_be_text_json");
                }
                JSONObject payload = new JSONObject(bufferToString(buffer.data));
                String type = payload.optString("type", "");
                JSONObject result;
                if ("ping".equals(type)) {
                    result = new JSONObject();
                    result.put("ok", true);
                    result.put("type", "ping");
                    result.put("transport", "webrtc-datachannel-input");
                } else if (inputHandler != null) {
                    result = inputHandler.handle(payload);
                } else {
                    throw new IOException("input_handler_unavailable");
                }
                ack.put("ok", true);
                ack.put("mode", "webrtc-datachannel-input");
                ack.put("receivedElapsedMs", receivedElapsedMs);
                ack.put("ackElapsedMs", SystemClock.elapsedRealtime());
                if (payload.has("seq")) {
                    ack.put("seq", payload.optLong("seq"));
                }
                if (payload.has("clientElapsedMs")) {
                    ack.put("clientElapsedMs", payload.optDouble("clientElapsedMs"));
                }
                ack.put("type", result.optString("type", type));
                ack.put("result", result);
            } catch (Throwable t) {
                try {
                    ack.put("ok", false);
                    ack.put("mode", "webrtc-datachannel-input");
                    ack.put("receivedElapsedMs", receivedElapsedMs);
                    ack.put("ackElapsedMs", SystemClock.elapsedRealtime());
                    ack.put("error", t.toString());
                } catch (JSONException ignored) {
                }
            }
            sendAck(dataChannel, ack);
        }

        private void sendAck(DataChannel dataChannel, JSONObject ack) {
            lastInputJson = ack.toString();
            try {
                byte[] bytes = ack.toString().getBytes(StandardCharsets.UTF_8);
                dataChannel.send(new DataChannel.Buffer(ByteBuffer.wrap(bytes), false));
            } catch (RuntimeException ignored) {
            }
        }

        private void updateChannelState(DataChannel dataChannel) {
            String state = String.valueOf(dataChannel.state());
            if (dataChannel == moveChannel) {
                moveChannelState = state;
            } else if (dataChannel == inputChannel) {
                inputChannelState = state;
            }
        }

        private static void closeChannel(DataChannel channel) {
            if (channel == null) {
                return;
            }
            try {
                channel.close();
            } catch (RuntimeException ignored) {
            }
            try {
                channel.unregisterObserver();
            } catch (RuntimeException ignored) {
            }
        }

        private static String safeLabel(DataChannel dataChannel) {
            try {
                return dataChannel.label();
            } catch (RuntimeException e) {
                return "";
            }
        }

        private static String bufferToString(ByteBuffer source) {
            ByteBuffer data = source.asReadOnlyBuffer();
            byte[] bytes = new byte[data.remaining()];
            data.get(bytes);
            return new String(bytes, StandardCharsets.UTF_8);
        }
    }

    private static final class AwaitSdpObserver implements SdpObserver {
        final CountDownLatch latch = new CountDownLatch(1);
        volatile SessionDescription description;
        volatile String error = "";

        @Override
        public void onCreateSuccess(SessionDescription description) {
            this.description = description;
            latch.countDown();
        }

        @Override
        public void onSetSuccess() {
            latch.countDown();
        }

        @Override
        public void onCreateFailure(String error) {
            this.error = error == null ? "create_failure" : error;
            latch.countDown();
        }

        @Override
        public void onSetFailure(String error) {
            this.error = error == null ? "set_failure" : error;
            latch.countDown();
        }

        void await(String label) throws IOException {
            try {
                if (!latch.await(4500, TimeUnit.MILLISECONDS)) {
                    throw new IOException(label + "_timeout");
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IOException(label + "_interrupted");
            }
            if (error.length() != 0) {
                throw new IOException(label + "_" + error);
            }
        }
    }

    private interface CapturePump {
        void start() throws IOException;

        void stop();

        boolean running();

        String backend();

        String copyPath();

        int width();

        int height();

        int fps();

        long capturedFrames();

        long startedElapsedMs();

        long lastFrameElapsedMs();

        String lastError();

        String fallbackError();
    }

    private static final class ScreenFramePump implements CapturePump, Runnable {
        private final FrameProvider frameProvider;
        private final CapturerObserver observer;
        private final Thread thread;
        private final RuntimeConfig config;
        private final int fps;
        private final String fallbackFrom;
        private final String fallbackError;
        private volatile boolean running;
        private volatile int width = 360;
        private volatile int height = DEFAULT_FRAME_HEIGHT_PORTRAIT;
        private volatile long capturedFrames;
        private volatile long startedElapsedMs;
        private volatile long lastFrameElapsedMs;
        private volatile String lastError = "";

        ScreenFramePump(FrameProvider frameProvider, CapturerObserver observer, RuntimeConfig config,
                String fallbackFrom, String fallbackError) {
            this.frameProvider = frameProvider;
            this.observer = observer;
            this.config = config;
            this.fps = config.videoFps();
            this.fallbackFrom = fallbackFrom == null ? "" : fallbackFrom;
            this.fallbackError = fallbackError == null ? "" : fallbackError;
            this.thread = new Thread(this, "SmartisaxWebRtcScreenFrames");
        }

        @Override
        public void start() {
            running = true;
            startedElapsedMs = SystemClock.elapsedRealtime();
            observer.onCapturerStarted(true);
            thread.start();
        }

        @Override
        public void stop() {
            running = false;
            try {
                thread.join(800);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            observer.onCapturerStopped();
        }

        @Override
        public boolean running() {
            return running;
        }

        @Override
        public String backend() {
            return fallbackFrom.length() == 0 ? CAPTURE_BACKEND_BITMAP : CAPTURE_BACKEND_BITMAP + "-fallback";
        }

        @Override
        public String copyPath() {
            return "SurfaceControl Bitmap -> scale -> Bitmap.copy(ARG8888) -> Java ARGB to I420";
        }

        @Override
        public int width() {
            return width;
        }

        @Override
        public int height() {
            return height;
        }

        @Override
        public int fps() {
            return fps;
        }

        @Override
        public long capturedFrames() {
            return capturedFrames;
        }

        @Override
        public long startedElapsedMs() {
            return startedElapsedMs;
        }

        @Override
        public long lastFrameElapsedMs() {
            return lastFrameElapsedMs;
        }

        @Override
        public String lastError() {
            return lastError;
        }

        @Override
        public String fallbackError() {
            return fallbackError;
        }

        @Override
        public void run() {
            long intervalMs = 1000L / fps;
            while (running) {
                long started = SystemClock.elapsedRealtime();
                try {
                    Bitmap source = frameProvider.capture();
                    if (source != null) {
                        emit(source);
                    }
                } catch (Throwable t) {
                    lastError = t.toString();
                }
                long elapsed = SystemClock.elapsedRealtime() - started;
                long sleep = Math.max(10L, intervalMs - elapsed);
                try {
                    Thread.sleep(sleep);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
        }

        private void emit(Bitmap source) {
            Point display = frameProvider.displaySize();
            int targetWidth = config.targetWidth(display);
            int targetHeight = config.targetHeight(display);
            targetWidth = even(targetWidth);
            Bitmap scaled = Bitmap.createScaledBitmap(source, targetWidth, targetHeight, false);
            Bitmap readable = readableArgb8888(scaled);
            try {
                JavaI420Buffer buffer = bitmapToI420(readable);
                VideoFrame frame = new VideoFrame(buffer, 0, System.nanoTime());
                observer.onFrameCaptured(frame);
                frame.release();
            } finally {
                if (readable != scaled) {
                    readable.recycle();
                }
                if (scaled != source) {
                    scaled.recycle();
                }
            }
            width = targetWidth;
            height = targetHeight;
            capturedFrames += 1;
            lastFrameElapsedMs = SystemClock.elapsedRealtime();
            lastError = "";
        }
    }

    private static final class ProjectionTextureFramePump implements CapturePump, VideoSink {
        private final Context context;
        private final FrameProvider frameProvider;
        private final CapturerObserver observer;
        private final RuntimeConfig config;
        private final int fps;
        private final long frameIntervalMs;
        private final int width;
        private final int height;
        private volatile boolean running;
        private volatile boolean observerStarted;
        private volatile long capturedFrames;
        private volatile long sourceFrames;
        private volatile long droppedFrames;
        private volatile long continuityFrameRequests;
        private volatile long continuityFrameSkips;
        private volatile long continuityFrames;
        private volatile long inputFrameBoostRequests;
        private volatile long inputFrameBoostSkips;
        private volatile long inputFrameBoostFrames;
        private volatile long inputFrameBoostUrgentRequests;
        private volatile long inputFrameBoostUrgentSkips;
        private volatile long inputFrameBoostUrgentFrames;
        private volatile long inputFrameBoostBurstRequests;
        private volatile long inputFrameBoostBurstSkips;
        private volatile long inputFrameBoostBurstFrames;
        private volatile long inputFrameBoostBurstRetries;
        private volatile long timestampRewriteFrames;
        private volatile long startedElapsedMs;
        private volatile long lastFrameElapsedMs;
        private volatile long lastSourceFrameElapsedMs;
        private volatile long lastContinuityFrameRequestElapsedMs;
        private volatile long lastContinuityFrameSkipElapsedMs;
        private volatile long lastContinuityFrameElapsedMs;
        private volatile long lastInputFrameBoostRequestElapsedMs;
        private volatile long lastInputFrameBoostSkipElapsedMs;
        private volatile long lastInputFrameBoostElapsedMs;
        private volatile long lastInputFrameBoostUrgentRequestElapsedMs;
        private volatile long lastInputFrameBoostUrgentSkipElapsedMs;
        private volatile long lastInputFrameBoostUrgentFrameElapsedMs;
        private volatile long lastInputFrameBoostBurstRequestElapsedMs;
        private volatile long lastInputFrameBoostBurstFrameElapsedMs;
        private volatile long lastInputFrameBoostBurstRetryElapsedMs;
        private volatile long lastTimestampRewriteElapsedMs;
        private volatile String lastError = "";
        private MediaProjection mediaProjection;
        private VirtualDisplay virtualDisplay;
        private SurfaceTextureHelper surfaceTextureHelper;
        private Surface surface;
        private Runnable continuityTicker;
        private int pendingContinuityFrames;
        private int pendingInputFrameBoostFrames;
        private int pendingUrgentInputFrameBoostFrames;
        private int pendingInputFrameBoostBurstFrames;
        private int activeInputFrameBoostBurstFrames;
        private boolean inputFrameBoostScheduled;
        private boolean inputFrameBoostBurstRetryScheduled;
        private int inputFrameBoostScheduleToken;
        private String inputFrameBoostBurstReason = "";

        ProjectionTextureFramePump(Context context, FrameProvider frameProvider, CapturerObserver observer,
                RuntimeConfig config) {
            this.context = context;
            this.frameProvider = frameProvider;
            this.observer = observer;
            this.config = config;
            this.fps = config.videoFps();
            this.frameIntervalMs = Math.max(1L, 1000L / Math.max(1, config.videoFps()));
            Point display = frameProvider.displaySize();
            this.width = config.targetWidth(display);
            this.height = config.targetHeight(display);
        }

        @Override
        public void start() throws IOException {
            running = true;
            startedElapsedMs = SystemClock.elapsedRealtime();
            try {
                mediaProjection = SmartisaxProjectionCapture.createMediaProjection(context);
                surfaceTextureHelper = SurfaceTextureHelper.create(
                        "SmartisaxWebRtcProjection", eglBase.getEglBaseContext());
                if (surfaceTextureHelper == null) {
                    throw new IOException("surface_texture_helper_create_returned_null");
                }
                surfaceTextureHelper.setTextureSize(width, height);
                surfaceTextureHelper.startListening(this);
                surface = new Surface(surfaceTextureHelper.getSurfaceTexture());
                virtualDisplay = mediaProjection.createVirtualDisplay(
                        "SmartisaxWebRtcProjection",
                        width,
                        height,
                        400,
                        3,
                        surface,
                        null,
                        surfaceTextureHelper.getHandler());
                if (virtualDisplay == null) {
                    throw new IOException("projection_create_virtual_display_returned_null");
                }
                mediaProjection.registerCallback(new Callback() {
                    @Override
                    public void onStop() {
                        running = false;
                        lastError = "media_projection_stopped";
                    }
                }, surfaceTextureHelper.getHandler());
                observer.onCapturerStarted(true);
                observerStarted = true;
                startContinuityTicker();
            } catch (Throwable t) {
                lastError = t.toString();
                stop();
                if (t instanceof IOException) {
                    throw (IOException) t;
                }
                throw new IOException("projection_texture_start_failed", t);
            }
        }

        @Override
        public void onFrame(VideoFrame frame) {
            if (!running || frame == null) {
                return;
            }
            long now = SystemClock.elapsedRealtime();
            boolean continuity = pendingContinuityFrames > 0;
            boolean inputBoost = pendingInputFrameBoostFrames > 0;
            boolean urgentInputBoost = pendingUrgentInputFrameBoostFrames > 0;
            boolean burstInputBoost = activeInputFrameBoostBurstFrames > 0;
            sourceFrames += 1;
            lastSourceFrameElapsedMs = now;
            long minimumFrameSpacingMs = inputBoost
                    ? (urgentInputBoost ? 0L
                            : (burstInputBoost ? markerTailFrameSpacingMs() : inputBoostMinimumFrameSpacingMs()))
                    : continuityForceFrameMinimumSpacingMs();
            if (lastFrameElapsedMs != 0L && now - lastFrameElapsedMs < minimumFrameSpacingMs) {
                droppedFrames += 1;
                return;
            }
            if (continuity) {
                pendingContinuityFrames -= 1;
            }
            if (inputBoost) {
                pendingInputFrameBoostFrames -= 1;
                if (urgentInputBoost) {
                    pendingUrgentInputFrameBoostFrames -= 1;
                }
                if (activeInputFrameBoostBurstFrames > 0) {
                    activeInputFrameBoostBurstFrames -= 1;
                }
            }
            try {
                VideoFrame outboundFrame = wrapWithFreshTimestamp(frame);
                try {
                    observer.onFrameCaptured(outboundFrame);
                } finally {
                    outboundFrame.release();
                }
                capturedFrames += 1;
                lastFrameElapsedMs = now;
                if (inputBoost) {
                    inputFrameBoostFrames += 1;
                    lastInputFrameBoostElapsedMs = now;
                    if (urgentInputBoost) {
                        inputFrameBoostUrgentFrames += 1;
                        lastInputFrameBoostUrgentFrameElapsedMs = now;
                    }
                    if (burstInputBoost) {
                        inputFrameBoostBurstFrames += 1;
                        lastInputFrameBoostBurstFrameElapsedMs = now;
                        scheduleNextInputFrameBoostBurst();
                    }
                } else if (continuity) {
                    continuityFrames += 1;
                    lastContinuityFrameElapsedMs = now;
                }
                lastError = "";
            } catch (Throwable t) {
                lastError = t.toString();
            }
        }

        private VideoFrame wrapWithFreshTimestamp(VideoFrame frame) {
            frame.getBuffer().retain();
            timestampRewriteFrames += 1;
            lastTimestampRewriteElapsedMs = SystemClock.elapsedRealtime();
            return new VideoFrame(frame.getBuffer(), frame.getRotation(), System.nanoTime());
        }

        @Override
        public void stop() {
            running = false;
            Handler handler = surfaceTextureHelper == null ? null : surfaceTextureHelper.getHandler();
            if (handler != null && continuityTicker != null) {
                try {
                    handler.removeCallbacks(continuityTicker);
                } catch (RuntimeException ignored) {
                }
            }
            if (surfaceTextureHelper != null) {
                try {
                    surfaceTextureHelper.stopListening();
                } catch (RuntimeException ignored) {
                }
            }
            if (virtualDisplay != null) {
                try {
                    virtualDisplay.release();
                } catch (RuntimeException ignored) {
                }
                virtualDisplay = null;
            }
            if (surface != null) {
                try {
                    surface.release();
                } catch (RuntimeException ignored) {
                }
                surface = null;
            }
            if (mediaProjection != null) {
                try {
                    mediaProjection.stop();
                } catch (RuntimeException ignored) {
                }
                mediaProjection = null;
            }
            if (surfaceTextureHelper != null) {
                try {
                    surfaceTextureHelper.dispose();
                } catch (RuntimeException ignored) {
                }
                surfaceTextureHelper = null;
            }
            if (observerStarted) {
                observerStarted = false;
                observer.onCapturerStopped();
            }
        }

        private void startContinuityTicker() {
            continuityTicker = new Runnable() {
                @Override
                public void run() {
                    if (!running) {
                        return;
                    }
                    long now = SystemClock.elapsedRealtime();
                    long elapsedSinceFrame = lastFrameElapsedMs == 0L ? Long.MAX_VALUE : now - lastFrameElapsedMs;
                    long minimumForceInterval = continuityForceFrameMinimumSpacingMs();
                    long cadenceMs = mediaCallbackTailFrameSpacingMs();
                    if (pendingContinuityFrames > 0) {
                        long pendingAgeMs = lastContinuityFrameRequestElapsedMs == 0L
                                ? 0L
                                : now - lastContinuityFrameRequestElapsedMs;
                        if (pendingAgeMs < Math.max(cadenceMs * 2L, cadenceMs + 1L)) {
                            continuityFrameSkips += 1;
                            lastContinuityFrameSkipElapsedMs = now;
                            postContinuityTick(cadenceMs);
                            return;
                        }
                        pendingContinuityFrames = 0;
                    }
                    if (elapsedSinceFrame < minimumForceInterval) {
                        continuityFrameSkips += 1;
                        lastContinuityFrameSkipElapsedMs = now;
                        postContinuityTick(Math.max(1L, minimumForceInterval - elapsedSinceFrame));
                        return;
                    }
                    if (surfaceTextureHelper != null) {
                        try {
                            if (pendingContinuityFrames < PROJECTION_MAX_PENDING_CONTINUITY_FRAMES) {
                                pendingContinuityFrames += 1;
                            }
                            continuityFrameRequests += 1;
                            lastContinuityFrameRequestElapsedMs = now;
                            surfaceTextureHelper.forceFrame();
                        } catch (RuntimeException e) {
                            lastError = e.toString();
                            if (pendingContinuityFrames > 0) {
                                pendingContinuityFrames -= 1;
                            }
                        }
                    }
                    postContinuityTick(cadenceMs);
                }
            };
            postContinuityTick(mediaCallbackTailFrameSpacingMs());
        }

        void requestInputFrameBoost(final String reason) {
            Handler handler = surfaceTextureHelper == null ? null : surfaceTextureHelper.getHandler();
            if (handler == null) {
                return;
            }
            try {
                handler.post(new Runnable() {
                    @Override
                    public void run() {
                        scheduleInputFrameBoost(reason);
                    }
                });
            } catch (RuntimeException e) {
                lastError = e.toString();
            }
        }

        void requestUrgentInputFrameBoost(final String reason) {
            Handler handler = surfaceTextureHelper == null ? null : surfaceTextureHelper.getHandler();
            if (handler == null) {
                return;
            }
            try {
                handler.post(new Runnable() {
                    @Override
                    public void run() {
                        scheduleUrgentInputFrameBoost(reason);
                    }
                });
            } catch (RuntimeException e) {
                lastError = e.toString();
            }
        }

        void requestInputFrameBoostBurst(final String reason, final int frameCount) {
            Handler handler = surfaceTextureHelper == null ? null : surfaceTextureHelper.getHandler();
            if (handler == null) {
                return;
            }
            try {
                handler.post(new Runnable() {
                    @Override
                    public void run() {
                        scheduleInputFrameBoostBurst(reason, frameCount);
                    }
                });
            } catch (RuntimeException e) {
                lastError = e.toString();
            }
        }

        private boolean scheduleInputFrameBoost(final String reason) {
            return scheduleInputFrameBoost(reason, true);
        }

        private boolean scheduleInputFrameBoost(final String reason, boolean countSkip) {
            if (!running || surfaceTextureHelper == null) {
                return false;
            }
            long now = SystemClock.elapsedRealtime();
            if (pendingInputFrameBoostFrames > 0 || inputFrameBoostScheduled) {
                if (countSkip) {
                    inputFrameBoostSkips += 1;
                    lastInputFrameBoostSkipElapsedMs = now;
                }
                return false;
            }
            if (pendingContinuityFrames > 0) {
                pendingInputFrameBoostFrames += 1;
                inputFrameBoostRequests += 1;
                lastInputFrameBoostRequestElapsedMs = now;
                return true;
            }
            long elapsedSinceFrame = lastFrameElapsedMs == 0L ? Long.MAX_VALUE : now - lastFrameElapsedMs;
            long minimumForceInterval = inputBoostMinimumFrameSpacingMs();
            long delayMs = elapsedSinceFrame < minimumForceInterval
                    ? Math.max(1L, minimumForceInterval - elapsedSinceFrame)
                    : 1L;
            inputFrameBoostScheduled = true;
            Handler handler = surfaceTextureHelper.getHandler();
            try {
                final int scheduleToken = ++inputFrameBoostScheduleToken;
                handler.postDelayed(new Runnable() {
                    @Override
                    public void run() {
                        if (scheduleToken != inputFrameBoostScheduleToken) {
                            return;
                        }
                        inputFrameBoostScheduled = false;
                        requestInputFrameBoostNow(reason);
                    }
                }, delayMs);
                return true;
            } catch (RuntimeException e) {
                inputFrameBoostScheduled = false;
                lastError = e.toString();
                return false;
            }
        }

        private boolean scheduleUrgentInputFrameBoost(final String reason) {
            if (!running || surfaceTextureHelper == null) {
                return false;
            }
            long now = SystemClock.elapsedRealtime();
            if (pendingInputFrameBoostFrames > 0) {
                if (pendingUrgentInputFrameBoostFrames < pendingInputFrameBoostFrames) {
                    pendingUrgentInputFrameBoostFrames += 1;
                    inputFrameBoostUrgentRequests += 1;
                    lastInputFrameBoostUrgentRequestElapsedMs = now;
                    return true;
                }
                inputFrameBoostUrgentSkips += 1;
                lastInputFrameBoostUrgentSkipElapsedMs = now;
                return false;
            }
            if (inputFrameBoostScheduled) {
                inputFrameBoostScheduleToken += 1;
                inputFrameBoostScheduled = false;
            }
            return requestInputFrameBoostNow(reason, true);
        }

        private void scheduleInputFrameBoostBurst(String reason, int frameCount) {
            if (!running || surfaceTextureHelper == null) {
                return;
            }
            long now = SystemClock.elapsedRealtime();
            int requestedFrames = Math.max(1, Math.min(PROJECTION_INPUT_BOOST_BURST_MAX_FRAMES, frameCount));
            String burstReason = reason == null || reason.length() == 0 ? "touch-marker-burst" : reason;
            pendingInputFrameBoostBurstFrames = Math.max(
                    pendingInputFrameBoostBurstFrames,
                    requestedFrames);
            inputFrameBoostBurstReason = burstReason;
            inputFrameBoostBurstRequests += requestedFrames;
            lastInputFrameBoostBurstRequestElapsedMs = now;
            scheduleNextInputFrameBoostBurst(markerTailFrameSpacingMs());
        }

        private void scheduleNextInputFrameBoostBurst() {
            scheduleNextInputFrameBoostBurst(markerTailFrameSpacingMs());
        }

        private void scheduleNextInputFrameBoostBurst(long delayMs) {
            if (!running || surfaceTextureHelper == null || pendingInputFrameBoostBurstFrames <= 0) {
                return;
            }
            final Handler handler = surfaceTextureHelper.getHandler();
            if (handler == null) {
                return;
            }
            if (delayMs <= 0L) {
                requestNextInputFrameBoostBurst();
                return;
            }
            if (inputFrameBoostBurstRetryScheduled) {
                return;
            }
            inputFrameBoostBurstRetryScheduled = true;
            try {
                handler.postDelayed(new Runnable() {
                    @Override
                    public void run() {
                        inputFrameBoostBurstRetryScheduled = false;
                        if (!running) {
                            return;
                        }
                        requestNextInputFrameBoostBurst();
                    }
                }, Math.max(1L, delayMs));
            } catch (RuntimeException e) {
                inputFrameBoostBurstRetryScheduled = false;
                inputFrameBoostBurstSkips += 1;
                lastInputFrameBoostBurstRetryElapsedMs = SystemClock.elapsedRealtime();
                lastError = e.toString();
            }
        }

        private void requestNextInputFrameBoostBurst() {
            if (!running || surfaceTextureHelper == null || pendingInputFrameBoostBurstFrames <= 0) {
                return;
            }
            String baseReason = inputFrameBoostBurstReason == null || inputFrameBoostBurstReason.length() == 0
                    ? "touch-marker-burst"
                    : inputFrameBoostBurstReason;
            boolean accepted = scheduleInputFrameBoost(baseReason + "-accepted", false);
            if (accepted) {
                pendingInputFrameBoostBurstFrames -= 1;
                activeInputFrameBoostBurstFrames += 1;
                return;
            }
            inputFrameBoostBurstRetries += 1;
            inputFrameBoostBurstSkips += 1;
            lastInputFrameBoostBurstRetryElapsedMs = SystemClock.elapsedRealtime();
            scheduleNextInputFrameBoostBurst(markerTailFrameSpacingMs());
        }

        private boolean requestInputFrameBoostNow(String reason) {
            return requestInputFrameBoostNow(reason, false);
        }

        private boolean requestInputFrameBoostNow(String reason, boolean urgent) {
            if (!running || surfaceTextureHelper == null) {
                return false;
            }
            long now = SystemClock.elapsedRealtime();
            if (pendingContinuityFrames >= PROJECTION_MAX_PENDING_CONTINUITY_FRAMES) {
                if (pendingInputFrameBoostFrames == 0) {
                    pendingInputFrameBoostFrames += 1;
                    if (urgent) {
                        pendingUrgentInputFrameBoostFrames += 1;
                        inputFrameBoostUrgentRequests += 1;
                        lastInputFrameBoostUrgentRequestElapsedMs = now;
                    }
                    inputFrameBoostRequests += 1;
                    lastInputFrameBoostRequestElapsedMs = now;
                    return true;
                }
                inputFrameBoostSkips += 1;
                lastInputFrameBoostSkipElapsedMs = now;
                if (urgent) {
                    inputFrameBoostUrgentSkips += 1;
                    lastInputFrameBoostUrgentSkipElapsedMs = now;
                }
                return false;
            }
            try {
                pendingContinuityFrames += 1;
                pendingInputFrameBoostFrames += 1;
                if (urgent) {
                    pendingUrgentInputFrameBoostFrames += 1;
                    inputFrameBoostUrgentRequests += 1;
                    lastInputFrameBoostUrgentRequestElapsedMs = now;
                }
                inputFrameBoostRequests += 1;
                continuityFrameRequests += 1;
                lastInputFrameBoostRequestElapsedMs = now;
                lastContinuityFrameRequestElapsedMs = now;
                surfaceTextureHelper.forceFrame();
                return true;
            } catch (RuntimeException e) {
                lastError = e.toString();
                if (pendingContinuityFrames > 0) {
                    pendingContinuityFrames -= 1;
                }
                if (pendingInputFrameBoostFrames > 0) {
                    pendingInputFrameBoostFrames -= 1;
                }
                if (urgent && pendingUrgentInputFrameBoostFrames > 0) {
                    pendingUrgentInputFrameBoostFrames -= 1;
                }
                if (urgent) {
                    inputFrameBoostUrgentSkips += 1;
                    lastInputFrameBoostUrgentSkipElapsedMs = now;
                }
                return false;
            }
        }

        private void postContinuityTick(long delayMs) {
            Handler handler = surfaceTextureHelper == null ? null : surfaceTextureHelper.getHandler();
            if (handler == null || continuityTicker == null) {
                return;
            }
            try {
                handler.postDelayed(continuityTicker, Math.max(1L, delayMs));
            } catch (RuntimeException e) {
                lastError = e.toString();
            }
        }

        @Override
        public boolean running() {
            return running;
        }

        @Override
        public String backend() {
            return CAPTURE_BACKEND_PROJECTION;
        }

        @Override
        public String copyPath() {
            return "MediaProjection VirtualDisplay -> latest-frame-only SurfaceTextureHelper cadence -> fresh-timestamp retained texture frames -> WebRTC encoder";
        }

        String continuityMode() {
            return "surface-texture-helper-latest-frame-only+fresh-texture-timestamps";
        }

        String latencyMode() {
            return LATENCY_MODE;
        }

        String queuePolicy() {
            return FRAME_QUEUE_POLICY;
        }

        String presentationTailCadence() {
            return PRESENTATION_TAIL_CADENCE_POLICY;
        }

        int maxPendingContinuityFrames() {
            return PROJECTION_MAX_PENDING_CONTINUITY_FRAMES;
        }

        @Override
        public int width() {
            return width;
        }

        @Override
        public int height() {
            return height;
        }

        @Override
        public int fps() {
            return fps;
        }

        @Override
        public long capturedFrames() {
            return capturedFrames;
        }

        long sourceFrames() {
            return sourceFrames;
        }

        long droppedFrames() {
            return droppedFrames;
        }

        long continuityFrameRequests() {
            return continuityFrameRequests;
        }

        long continuityFrameSkips() {
            return continuityFrameSkips;
        }

        long continuityFrames() {
            return continuityFrames;
        }

        long inputFrameBoostRequests() {
            return inputFrameBoostRequests;
        }

        long inputFrameBoostSkips() {
            return inputFrameBoostSkips;
        }

        long inputFrameBoostFrames() {
            return inputFrameBoostFrames;
        }

        long inputFrameBoostUrgentRequests() {
            return inputFrameBoostUrgentRequests;
        }

        long inputFrameBoostUrgentSkips() {
            return inputFrameBoostUrgentSkips;
        }

        long inputFrameBoostUrgentFrames() {
            return inputFrameBoostUrgentFrames;
        }

        long inputFrameBoostBurstRequests() {
            return inputFrameBoostBurstRequests;
        }

        long inputFrameBoostBurstSkips() {
            return inputFrameBoostBurstSkips;
        }

        long inputFrameBoostBurstFrames() {
            return inputFrameBoostBurstFrames;
        }

        long inputFrameBoostBurstRetries() {
            return inputFrameBoostBurstRetries;
        }

        int inputFrameBoostBurstPendingFrames() {
            return pendingInputFrameBoostBurstFrames;
        }

        int inputFrameBoostBurstActiveFrames() {
            return activeInputFrameBoostBurstFrames;
        }

        int inputFrameBoostBurstMaxFrames() {
            return PROJECTION_INPUT_BOOST_BURST_MAX_FRAMES;
        }

        long inputFrameBoostBurstCadenceMs() {
            return markerTailFrameSpacingMs();
        }

        String mediaCallbackTailRepair() {
            return config.mediaCallbackTailRepair ? MEDIA_CALLBACK_TAIL_POLICY : "";
        }

        long mediaCallbackTailFrameSpacingMs() {
            if (!config.mediaCallbackTailRepair) {
                return Math.max(1L, frameIntervalMs);
            }
            return Math.max(1L, Math.round(1000.0d / Math.max(1, config.videoFps())));
        }

        long inputFrameBoostMinIntervalMs() {
            return inputBoostMinimumFrameSpacingMs();
        }

        long timestampRewriteFrames() {
            return timestampRewriteFrames;
        }

        @Override
        public long startedElapsedMs() {
            return startedElapsedMs;
        }

        @Override
        public long lastFrameElapsedMs() {
            return lastFrameElapsedMs;
        }

        long lastSourceFrameElapsedMs() {
            return lastSourceFrameElapsedMs;
        }

        long lastContinuityFrameRequestElapsedMs() {
            return lastContinuityFrameRequestElapsedMs;
        }

        long lastContinuityFrameSkipElapsedMs() {
            return lastContinuityFrameSkipElapsedMs;
        }

        long lastContinuityFrameElapsedMs() {
            return lastContinuityFrameElapsedMs;
        }

        long lastInputFrameBoostRequestElapsedMs() {
            return lastInputFrameBoostRequestElapsedMs;
        }

        long lastInputFrameBoostSkipElapsedMs() {
            return lastInputFrameBoostSkipElapsedMs;
        }

        long lastInputFrameBoostElapsedMs() {
            return lastInputFrameBoostElapsedMs;
        }

        long lastInputFrameBoostUrgentRequestElapsedMs() {
            return lastInputFrameBoostUrgentRequestElapsedMs;
        }

        long lastInputFrameBoostUrgentSkipElapsedMs() {
            return lastInputFrameBoostUrgentSkipElapsedMs;
        }

        long lastInputFrameBoostUrgentFrameElapsedMs() {
            return lastInputFrameBoostUrgentFrameElapsedMs;
        }

        long lastInputFrameBoostBurstRequestElapsedMs() {
            return lastInputFrameBoostBurstRequestElapsedMs;
        }

        long lastInputFrameBoostBurstFrameElapsedMs() {
            return lastInputFrameBoostBurstFrameElapsedMs;
        }

        long lastInputFrameBoostBurstRetryElapsedMs() {
            return lastInputFrameBoostBurstRetryElapsedMs;
        }

        long lastTimestampRewriteElapsedMs() {
            return lastTimestampRewriteElapsedMs;
        }

        @Override
        public String lastError() {
            return lastError;
        }

        @Override
        public String fallbackError() {
            return "";
        }

        private long inputBoostMinimumFrameSpacingMs() {
            return Math.max(1L, frameIntervalMs / PROJECTION_INPUT_BOOST_MIN_INTERVAL_DIVISOR);
        }

        private long continuityForceFrameMinimumSpacingMs() {
            long earlyMargin = config.mediaCallbackTailRepair ? 0L : PROJECTION_FORCE_FRAME_EARLY_MARGIN_MS;
            return Math.max(1L, frameIntervalMs - earlyMargin);
        }

        private long markerTailFrameSpacingMs() {
            return mediaCallbackTailFrameSpacingMs();
        }
    }

    private static final class RuntimeConfig {
        final int frameWidthPortrait;
        final int frameWidthLandscape;
        final int fps;
        final int presentationFps;
        final int inputRefreshHz;
        final int minBitrateBps;
        final int targetBitrateBps;
        final int maxBitrateBps;
        final boolean encoderTransportBurstClamped;
        final boolean mediaCallbackTailRepair;
        final String bitratePolicy;
        final String captureBackend;

        RuntimeConfig(int frameWidthPortrait, int frameWidthLandscape, int fps,
                int presentationFps, int inputRefreshHz,
                int minBitrateBps, int targetBitrateBps, int maxBitrateBps, String captureBackend) {
            this.frameWidthPortrait = even(clampValue(frameWidthPortrait, MIN_FRAME_WIDTH, MAX_FRAME_WIDTH));
            this.frameWidthLandscape = even(clampValue(frameWidthLandscape, MIN_FRAME_WIDTH, MAX_FRAME_WIDTH));
            this.fps = clampValue(fps, MIN_FRAME_FPS, MAX_FRAME_FPS);
            this.presentationFps = clampValue(
                    Math.min(presentationFps, PRESENTATION_TRANSPORT_MAX_FPS),
                    MIN_FRAME_FPS,
                    PRESENTATION_TRANSPORT_MAX_FPS);
            this.inputRefreshHz = clampValue(inputRefreshHz, MIN_FRAME_FPS, MAX_FRAME_FPS);
            boolean transportPaced = isTransportPaced(this.fps, this.presentationFps, this.inputRefreshHz);
            int target = clampValue(targetBitrateBps, BITRATE_MIN_BPS, BITRATE_MAX_BPS);
            int min = clampValue(minBitrateBps, BITRATE_MIN_BPS, BITRATE_MAX_BPS);
            int max = clampValue(maxBitrateBps, BITRATE_MIN_BPS, BITRATE_MAX_BPS);
            if (transportPaced) {
                target = Math.min(target, PACED_90_TARGET_VIDEO_BITRATE_BPS);
                min = Math.min(min, PACED_90_MIN_VIDEO_BITRATE_BPS);
                max = Math.min(max, PACED_90_MAX_VIDEO_BITRATE_BPS);
            }
            boolean burstClamped = isEncoderTransportBurstClamped(this.frameWidthPortrait, this.fps,
                    this.presentationFps);
            if (burstClamped) {
                target = Math.min(target, ENCODER_BURST_TARGET_VIDEO_BITRATE_BPS);
                min = Math.min(min, ENCODER_BURST_MIN_VIDEO_BITRATE_BPS);
                max = Math.min(max, ENCODER_BURST_MAX_VIDEO_BITRATE_BPS);
            }
            boolean mediaTailRepair = isMediaCallbackTailRepair(this.frameWidthPortrait, this.fps,
                    this.presentationFps);
            if (mediaTailRepair) {
                target = Math.min(target, RVFC_TAIL_60HZ_TARGET_VIDEO_BITRATE_BPS);
                max = Math.min(max, RVFC_TAIL_60HZ_MAX_VIDEO_BITRATE_BPS);
            }
            this.targetBitrateBps = target;
            if (min > this.targetBitrateBps) {
                min = this.targetBitrateBps;
            }
            if (max < this.targetBitrateBps) {
                max = this.targetBitrateBps;
            }
            this.minBitrateBps = min;
            this.maxBitrateBps = max;
            this.encoderTransportBurstClamped = burstClamped;
            this.mediaCallbackTailRepair = mediaTailRepair;
            this.bitratePolicy = BITRATE_POLICY;
            this.captureBackend = normalizeCaptureBackend(captureBackend);
        }

        static RuntimeConfig defaults() {
            return new RuntimeConfig(
                    DEFAULT_FRAME_WIDTH_PORTRAIT,
                    DEFAULT_FRAME_WIDTH_LANDSCAPE,
                    DEFAULT_FRAME_FPS,
                    DEFAULT_FRAME_FPS,
                    DEFAULT_FRAME_FPS,
                    DEFAULT_MIN_VIDEO_BITRATE_BPS,
                    DEFAULT_TARGET_VIDEO_BITRATE_BPS,
                    DEFAULT_MAX_VIDEO_BITRATE_BPS,
                    CAPTURE_BACKEND_AUTO);
        }

        static RuntimeConfig fromJson(JSONObject json, RuntimeConfig fallback) {
            RuntimeConfig base = fallback == null ? defaults() : fallback;
            int requestedFps = optIntAny(json, base.fps, "fps", "frameFps", "requestedFps");
            int inputRefreshHz = optIntAny(json,
                    Math.max(requestedFps, base.inputRefreshHz),
                    "inputRefreshHz", "refreshHz", "inputHz");
            int presentationFps = optIntAny(json,
                    defaultPresentationFps(requestedFps),
                    "presentationFps", "transportFps", "captureFps", "sendFps");
            int target = optIntAny(json, base.targetBitrateBps,
                    "targetBitrateBps", "targetVideoBitrateBps", "bitrateBps", "bitrate");
            return new RuntimeConfig(
                    optIntAny(json, base.frameWidthPortrait, "frameWidthPortrait", "widthPortrait", "width"),
                    optIntAny(json, base.frameWidthLandscape, "frameWidthLandscape", "widthLandscape"),
                    requestedFps,
                    presentationFps,
                    inputRefreshHz,
                    optIntAny(json, Math.min(base.minBitrateBps, target), "minBitrateBps", "minVideoBitrateBps"),
                    target,
                    optIntAny(json, Math.max(base.maxBitrateBps, target), "maxBitrateBps", "maxVideoBitrateBps"),
                    optStringAny(json, base.captureBackend, "captureBackend", "backend", "capture"));
        }

        static JSONObject limitsJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("minFrameWidth", MIN_FRAME_WIDTH);
            json.put("maxFrameWidth", MAX_FRAME_WIDTH);
            json.put("minFps", MIN_FRAME_FPS);
            json.put("maxFps", MAX_FRAME_FPS);
            json.put("maxPresentationFps", PRESENTATION_TRANSPORT_MAX_FPS);
            json.put("minBitrateBps", BITRATE_MIN_BPS);
            json.put("maxBitrateBps", BITRATE_MAX_BPS);
            json.put("encoderTransportBurstMinBitrateBps", ENCODER_BURST_MIN_VIDEO_BITRATE_BPS);
            json.put("encoderTransportBurstTargetBitrateBps", ENCODER_BURST_TARGET_VIDEO_BITRATE_BPS);
            json.put("encoderTransportBurstMaxBitrateBps", ENCODER_BURST_MAX_VIDEO_BITRATE_BPS);
            json.put("mediaCallbackTailTargetBitrateBps", RVFC_TAIL_60HZ_TARGET_VIDEO_BITRATE_BPS);
            json.put("mediaCallbackTailMaxBitrateBps", RVFC_TAIL_60HZ_MAX_VIDEO_BITRATE_BPS);
            json.put("mediaCallbackTailSenderMaxFramerate", RVFC_TAIL_60HZ_SENDER_MAX_FRAMERATE);
            json.put("maxResolutionLabel", "1080p");
            json.put("defaultTarget", "1080p90-input-60fps-presentation");
            json.put("minimumTarget", "1080p60");
            json.put("refreshRateProfiles", "1080p60+1080p90");
            json.put("transportPacing", TRANSPORT_PACING_POLICY);
            JSONArray captureBackends = new JSONArray();
            captureBackends.put(CAPTURE_BACKEND_AUTO);
            captureBackends.put(CAPTURE_BACKEND_PROJECTION);
            captureBackends.put(CAPTURE_BACKEND_BITMAP);
            json.put("captureBackends", captureBackends);
            return json;
        }

        JSONObject toJson() throws JSONException {
            JSONObject json = new JSONObject();
            json.put("frameWidthPortrait", frameWidthPortrait);
            json.put("frameWidthLandscape", frameWidthLandscape);
            json.put("widthPortrait", frameWidthPortrait);
            json.put("widthLandscape", frameWidthLandscape);
            json.put("fps", fps);
            json.put("requestedFps", fps);
            json.put("presentationFps", presentationFps);
            json.put("transportFps", presentationFps);
            json.put("inputRefreshHz", inputRefreshHz);
            json.put("minBitrateBps", minBitrateBps);
            json.put("targetBitrateBps", targetBitrateBps);
            json.put("maxBitrateBps", maxBitrateBps);
            json.put("minVideoBitrateBps", minBitrateBps);
            json.put("targetVideoBitrateBps", targetBitrateBps);
            json.put("maxVideoBitrateBps", maxBitrateBps);
            json.put("bitratePolicy", bitratePolicy);
            json.put("captureBackend", captureBackend);
            json.put("transportPacing", TRANSPORT_PACING_POLICY);
            json.put("encoderTransportBurstRepair", ENCODER_TRANSPORT_BURST_POLICY);
            json.put("encoderTransportBurstClamped", encoderTransportBurstClamped);
            json.put("mediaCallbackTailRepair", mediaCallbackTailRepair);
            json.put("mediaCallbackTailPolicy", MEDIA_CALLBACK_TAIL_POLICY);
            json.put("mediaCallbackTailFrameSpacingMs", mediaCallbackTailRepair
                    ? Math.max(1L, Math.round(1000.0d / Math.max(1, videoFps())))
                    : Math.max(1L, 1000L / Math.max(1, videoFps())));
            json.put("senderMinBitrateBps", senderMinBitrateBps());
            json.put("senderTargetBitrateBps", senderTargetBitrateBps());
            json.put("senderMaxBitrateBps", senderMaxBitrateBps());
            json.put("senderMaxFramerate", senderMaxFramerate());
            json.put("senderDegradationPreference", "MAINTAIN_FRAMERATE");
            json.put("framePumpStartPolicy", "late-start-after-local-sdp");
            json.put("presentationTransportPacing", isTransportPaced(fps, presentationFps, inputRefreshHz));
            json.put("runtimeTuning", true);
            json.put("maxFrameWidth", MAX_FRAME_WIDTH);
            json.put("maxFps", MAX_FRAME_FPS);
            json.put("maxPresentationFps", PRESENTATION_TRANSPORT_MAX_FPS);
            return json;
        }

        int videoFps() {
            return presentationFps;
        }

        int senderMinBitrateBps() {
            return minBitrateBps;
        }

        int senderTargetBitrateBps() {
            return targetBitrateBps;
        }

        int senderMaxBitrateBps() {
            return encoderTransportBurstClamped ? targetBitrateBps : maxBitrateBps;
        }

        int senderMaxFramerate() {
            return mediaCallbackTailRepair ? RVFC_TAIL_60HZ_SENDER_MAX_FRAMERATE : videoFps();
        }

        int targetWidth(Point display) {
            return display != null && display.x > 0 && display.y > 0 && display.x < display.y
                    ? frameWidthPortrait
                    : frameWidthLandscape;
        }

        int targetHeight(Point display) {
            int width = targetWidth(display);
            return display != null && display.x > 0 && display.y > 0
                    ? even(Math.round(width * (display.y / (float) display.x)))
                    : DEFAULT_FRAME_HEIGHT_PORTRAIT;
        }

        boolean equalsConfig(RuntimeConfig other) {
            return other != null
                    && frameWidthPortrait == other.frameWidthPortrait
                    && frameWidthLandscape == other.frameWidthLandscape
                    && fps == other.fps
                    && presentationFps == other.presentationFps
                    && inputRefreshHz == other.inputRefreshHz
                    && minBitrateBps == other.minBitrateBps
                    && targetBitrateBps == other.targetBitrateBps
                    && maxBitrateBps == other.maxBitrateBps
                    && encoderTransportBurstClamped == other.encoderTransportBurstClamped
                    && mediaCallbackTailRepair == other.mediaCallbackTailRepair
                    && captureBackend.equals(other.captureBackend);
        }

        private static int defaultPresentationFps(int requestedFps) {
            return Math.min(
                    clampValue(requestedFps, MIN_FRAME_FPS, MAX_FRAME_FPS),
                    PRESENTATION_TRANSPORT_MAX_FPS);
        }

        private static boolean isTransportPaced(int requestedFps, int presentationFps, int inputRefreshHz) {
            return requestedFps > presentationFps || inputRefreshHz > presentationFps;
        }

        private static boolean isEncoderTransportBurstClamped(int widthPortrait, int requestedFps,
                int presentationFps) {
            return widthPortrait >= 1080 && requestedFps >= 60 && presentationFps >= 60;
        }

        private static boolean isMediaCallbackTailRepair(int widthPortrait, int requestedFps,
                int presentationFps) {
            return widthPortrait >= 1080 && requestedFps == 60 && presentationFps == 60;
        }
    }

    private static int optIntAny(JSONObject json, int fallback, String... keys) {
        if (json == null) {
            return fallback;
        }
        for (String key : keys) {
            if (json.has(key)) {
                return json.optInt(key, fallback);
            }
        }
        return fallback;
    }

    private static String optStringAny(JSONObject json, String fallback, String... keys) {
        if (json == null) {
            return fallback;
        }
        for (String key : keys) {
            if (json.has(key)) {
                return json.optString(key, fallback);
            }
        }
        return fallback;
    }

    private static String normalizeCaptureBackend(String value) {
        if (CAPTURE_BACKEND_PROJECTION.equals(value)
                || CAPTURE_BACKEND_BITMAP.equals(value)
                || CAPTURE_BACKEND_AUTO.equals(value)) {
            return value;
        }
        return CAPTURE_BACKEND_AUTO;
    }

    private static int clampValue(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static Bitmap readableArgb8888(Bitmap source) {
        if (source.getConfig() == Bitmap.Config.ARGB_8888) {
            return source;
        }
        Bitmap copy = source.copy(Bitmap.Config.ARGB_8888, false);
        if (copy == null) {
            throw new IllegalStateException("bitmap_copy_argb8888_returned_null");
        }
        return copy;
    }

    private static JavaI420Buffer bitmapToI420(Bitmap bitmap) {
        int width = even(bitmap.getWidth());
        int height = even(bitmap.getHeight());
        int[] pixels = new int[width * height];
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
        JavaI420Buffer buffer = JavaI420Buffer.allocate(width, height);
        ByteBuffer yPlane = buffer.getDataY();
        ByteBuffer uPlane = buffer.getDataU();
        ByteBuffer vPlane = buffer.getDataV();
        int strideY = buffer.getStrideY();
        int strideU = buffer.getStrideU();
        int strideV = buffer.getStrideV();

        for (int y = 0; y < height; y++) {
            int row = y * width;
            for (int x = 0; x < width; x++) {
                int color = pixels[row + x];
                int r = (color >> 16) & 0xff;
                int g = (color >> 8) & 0xff;
                int b = color & 0xff;
                yPlane.put(y * strideY + x, (byte) clamp(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16));
            }
        }

        for (int y = 0; y < height; y += 2) {
            for (int x = 0; x < width; x += 2) {
                int rSum = 0;
                int gSum = 0;
                int bSum = 0;
                for (int dy = 0; dy < 2; dy++) {
                    for (int dx = 0; dx < 2; dx++) {
                        int color = pixels[(y + dy) * width + x + dx];
                        rSum += (color >> 16) & 0xff;
                        gSum += (color >> 8) & 0xff;
                        bSum += color & 0xff;
                    }
                }
                int r = rSum >> 2;
                int g = gSum >> 2;
                int b = bSum >> 2;
                int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                int uvX = x >> 1;
                int uvY = y >> 1;
                uPlane.put(uvY * strideU + uvX, (byte) clamp(u));
                vPlane.put(uvY * strideV + uvX, (byte) clamp(v));
            }
        }
        return buffer;
    }

    private static JSONArray candidatesJson(List<IceCandidate> candidates) throws JSONException {
        JSONArray array = new JSONArray();
        synchronized (candidates) {
            for (IceCandidate candidate : candidates) {
                JSONObject json = new JSONObject();
                json.put("sdpMid", candidate.sdpMid);
                json.put("sdpMLineIndex", candidate.sdpMLineIndex);
                json.put("candidate", candidate.sdp);
                array.put(json);
            }
        }
        return array;
    }

    private static JSONArray sessionsJsonLocked() throws JSONException {
        JSONArray array = new JSONArray();
        long now = SystemClock.elapsedRealtime();
        for (RuntimeSession session : SESSIONS.values()) {
            array.put(session.sessionJson(now));
        }
        return array;
    }

    private static String selectedVideoCodec(String sdp) {
        if (sdp == null) {
            return "";
        }
        String videoLine = "";
        Map<String, String> rtpmap = new LinkedHashMap<>();
        String[] lines = sdp.split("\\r?\\n");
        for (String line : lines) {
            if (line.startsWith("m=video ")) {
                videoLine = line;
            } else if (line.startsWith("a=rtpmap:")) {
                int space = line.indexOf(' ');
                if (space > 9) {
                    String payload = line.substring(9, space);
                    String codec = line.substring(space + 1);
                    int slash = codec.indexOf('/');
                    rtpmap.put(payload, slash >= 0 ? codec.substring(0, slash) : codec);
                }
            }
        }
        if (videoLine.length() == 0) {
            return "";
        }
        String[] parts = videoLine.split("\\s+");
        return parts.length > 3 ? rtpmap.getOrDefault(parts[3], "") : "";
    }

    private static int even(int value) {
        return Math.max(2, value & ~1);
    }

    private static int clamp(int value) {
        return Math.max(0, Math.min(255, value));
    }
}
