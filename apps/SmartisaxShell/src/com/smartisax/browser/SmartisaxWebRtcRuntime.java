package com.smartisax.browser;

import android.content.Context;
import android.hardware.display.VirtualDisplay;
import android.graphics.Bitmap;
import android.graphics.Point;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjection.Callback;
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
    private static final int MAX_FRAME_FPS = 60;
    private static final int DEFAULT_FRAME_WIDTH_PORTRAIT = 540;
    private static final int DEFAULT_FRAME_HEIGHT_PORTRAIT = 1170;
    private static final int DEFAULT_FRAME_WIDTH_LANDSCAPE = 720;
    private static final int DEFAULT_FRAME_FPS = 8;
    private static final int BITRATE_MIN_BPS = 250000;
    private static final int BITRATE_MAX_BPS = 12000000;
    private static final int DEFAULT_MIN_VIDEO_BITRATE_BPS = 600000;
    private static final int DEFAULT_TARGET_VIDEO_BITRATE_BPS = 1200000;
    private static final int DEFAULT_MAX_VIDEO_BITRATE_BPS = 1200000;
    private static final String BITRATE_POLICY = "runtime-tuning";
    private static final String CAPTURE_BACKEND_AUTO = "projection-auto";
    private static final String CAPTURE_BACKEND_PROJECTION = "projection-texture";
    private static final String CAPTURE_BACKEND_BITMAP = "bitmap-i420";
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
        json.put("input", "webrtc-datachannel-input");
        json.put("inputChannel", "smartisax-input");
        json.put("httpInput", false);
        JSONObject framePump = new JSONObject();
        framePump.put("widthPortrait", config.frameWidthPortrait);
        framePump.put("heightPortrait", DEFAULT_FRAME_HEIGHT_PORTRAIT);
        framePump.put("widthLandscape", config.frameWidthLandscape);
        framePump.put("fps", config.fps);
        framePump.put("minVideoBitrateBps", config.minBitrateBps);
        framePump.put("targetVideoBitrateBps", config.targetBitrateBps);
        framePump.put("maxVideoBitrateBps", config.maxBitrateBps);
        framePump.put("bitratePolicy", config.bitratePolicy);
        framePump.put("captureBackend", config.captureBackend);
        framePump.put("latency", "low-latency-screencast");
        framePump.put("copyPath", "projection-texture avoids Java Bitmap/I420 conversion when available");
        json.put("framePumpDefaults", framePump);
        json.put("runtimeTuning", true);
        json.put("targetMinimum", "1080p30");
        json.put("targetDefault", "1080p60");
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
        String videoBitratePolicy = BITRATE_POLICY;
        String videoBitrateStage = "";
        String videoBitrateError = "";
        int videoBitrateEncodingCount;
        boolean videoBitrateApplied;

        RuntimeSession(Context context, FrameProvider frameProvider, InputHandler inputHandler, RuntimeConfig config) {
            this.context = context;
            this.frameProvider = frameProvider;
            this.inputHandler = inputHandler;
            this.config = config;
            this.videoBitratePolicy = config.bitratePolicy;
        }

        NativeAnswer answer(String remoteSdp) throws JSONException, IOException {
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
            videoSource.adaptOutputFormat(config.targetWidth(display), config.targetHeight(display), config.fps);
            videoTrack = factory.createVideoTrack("smartisax-r2-screen", videoSource);
            videoTrack.setEnabled(true);
            videoSender = peerConnection.addTrack(videoTrack, Collections.singletonList("smartisax-screen"));
            applyVideoSenderParameters("after-addTrack");

            startFramePump(videoSource.getCapturerObserver());

            awaitSetRemote(new SessionDescription(SessionDescription.Type.OFFER, remoteSdp));
            SessionDescription answer = awaitCreateAnswer();
            awaitSetLocal(answer);
            applyVideoSenderParameters("after-setLocal");
            peerObserver.awaitIceComplete(2200);
            SessionDescription local = peerConnection.getLocalDescription();
            String sdp = local == null ? answer.description : local.description;
            return new NativeAnswer(sdp, peerObserver.iceGatheringState(), candidatesJson(candidates));
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
            json.put("capturedFrames", framePump.capturedFrames());
            json.put("lastError", framePump.lastError());
            json.put("startedElapsedMs", framePump.startedElapsedMs());
            json.put("lastFrameElapsedMs", framePump.lastFrameElapsedMs());
            json.put("fallbackError", framePump.fallbackError());
            json.put("bitratePolicy", videoBitratePolicy);
            json.put("minBitrateBps", config.minBitrateBps);
            json.put("targetBitrateBps", config.targetBitrateBps);
            json.put("maxBitrateBps", config.maxBitrateBps);
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
            json.put("maxFramerate", config.fps);
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
                videoBitrateError = "video_sender_unavailable";
                return;
            }
            try {
                RtpParameters parameters = videoSender.getParameters();
                if (parameters == null || parameters.encodings == null || parameters.encodings.isEmpty()) {
                    videoBitrateApplied = false;
                    videoBitrateEncodingCount = 0;
                    videoBitrateError = "sender_parameters_no_encodings";
                    return;
                }
                videoBitrateEncodingCount = parameters.encodings.size();
                for (RtpParameters.Encoding encoding : parameters.encodings) {
                    if (encoding == null) {
                        continue;
                    }
                    encoding.active = true;
                    encoding.minBitrateBps = Integer.valueOf(config.minBitrateBps);
                    encoding.maxBitrateBps = Integer.valueOf(config.maxBitrateBps);
                    encoding.maxFramerate = Integer.valueOf(config.fps);
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
        private volatile String inputChannelLabel = "";
        private volatile String inputChannelState = "";
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
            json.put("last", lastInputJson.length() == 0 ? JSONObject.NULL : new JSONObject(lastInputJson));
            return json;
        }

        void closeDataChannel() {
            DataChannel channel = inputChannel;
            inputChannel = null;
            inputChannelState = "CLOSED";
            if (channel != null) {
                try {
                    channel.close();
                } catch (RuntimeException ignored) {
                }
                try {
                    channel.unregisterObserver();
                } catch (RuntimeException ignored) {
                }
            }
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
            inputChannel = dataChannel;
            inputChannelLabel = safeLabel(dataChannel);
            inputChannelState = String.valueOf(dataChannel.state());
            dataChannel.registerObserver(new DataChannel.Observer() {
                @Override
                public void onBufferedAmountChange(long previousAmount) {
                }

                @Override
                public void onStateChange() {
                    inputChannelState = String.valueOf(dataChannel.state());
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
                if (payload.has("seq")) {
                    ack.put("seq", payload.optLong("seq"));
                }
                ack.put("type", result.optString("type", type));
                ack.put("result", result);
            } catch (Throwable t) {
                try {
                    ack.put("ok", false);
                    ack.put("mode", "webrtc-datachannel-input");
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
            this.fps = config.fps;
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
        private final int width;
        private final int height;
        private volatile boolean running;
        private volatile long capturedFrames;
        private volatile long startedElapsedMs;
        private volatile long lastFrameElapsedMs;
        private volatile String lastError = "";
        private MediaProjection mediaProjection;
        private VirtualDisplay virtualDisplay;
        private SurfaceTextureHelper surfaceTextureHelper;
        private Surface surface;

        ProjectionTextureFramePump(Context context, FrameProvider frameProvider, CapturerObserver observer,
                RuntimeConfig config) {
            this.context = context;
            this.frameProvider = frameProvider;
            this.observer = observer;
            this.config = config;
            this.fps = config.fps;
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
            capturedFrames += 1;
            lastFrameElapsedMs = SystemClock.elapsedRealtime();
            observer.onFrameCaptured(frame);
        }

        @Override
        public void stop() {
            running = false;
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
            observer.onCapturerStopped();
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
            return "MediaProjection VirtualDisplay -> SurfaceTextureHelper texture frames -> WebRTC encoder";
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
            return "";
        }
    }

    private static final class RuntimeConfig {
        final int frameWidthPortrait;
        final int frameWidthLandscape;
        final int fps;
        final int minBitrateBps;
        final int targetBitrateBps;
        final int maxBitrateBps;
        final String bitratePolicy;
        final String captureBackend;

        RuntimeConfig(int frameWidthPortrait, int frameWidthLandscape, int fps,
                int minBitrateBps, int targetBitrateBps, int maxBitrateBps, String captureBackend) {
            this.frameWidthPortrait = even(clampValue(frameWidthPortrait, MIN_FRAME_WIDTH, MAX_FRAME_WIDTH));
            this.frameWidthLandscape = even(clampValue(frameWidthLandscape, MIN_FRAME_WIDTH, MAX_FRAME_WIDTH));
            this.fps = clampValue(fps, MIN_FRAME_FPS, MAX_FRAME_FPS);
            this.targetBitrateBps = clampValue(targetBitrateBps, BITRATE_MIN_BPS, BITRATE_MAX_BPS);
            int min = clampValue(minBitrateBps, BITRATE_MIN_BPS, BITRATE_MAX_BPS);
            int max = clampValue(maxBitrateBps, BITRATE_MIN_BPS, BITRATE_MAX_BPS);
            if (min > this.targetBitrateBps) {
                min = this.targetBitrateBps;
            }
            if (max < this.targetBitrateBps) {
                max = this.targetBitrateBps;
            }
            this.minBitrateBps = min;
            this.maxBitrateBps = max;
            this.bitratePolicy = BITRATE_POLICY;
            this.captureBackend = normalizeCaptureBackend(captureBackend);
        }

        static RuntimeConfig defaults() {
            return new RuntimeConfig(
                    DEFAULT_FRAME_WIDTH_PORTRAIT,
                    DEFAULT_FRAME_WIDTH_LANDSCAPE,
                    DEFAULT_FRAME_FPS,
                    DEFAULT_MIN_VIDEO_BITRATE_BPS,
                    DEFAULT_TARGET_VIDEO_BITRATE_BPS,
                    DEFAULT_MAX_VIDEO_BITRATE_BPS,
                    CAPTURE_BACKEND_AUTO);
        }

        static RuntimeConfig fromJson(JSONObject json, RuntimeConfig fallback) {
            RuntimeConfig base = fallback == null ? defaults() : fallback;
            int target = optIntAny(json, base.targetBitrateBps,
                    "targetBitrateBps", "targetVideoBitrateBps", "bitrateBps", "bitrate");
            return new RuntimeConfig(
                    optIntAny(json, base.frameWidthPortrait, "frameWidthPortrait", "widthPortrait", "width"),
                    optIntAny(json, base.frameWidthLandscape, "frameWidthLandscape", "widthLandscape"),
                    optIntAny(json, base.fps, "fps", "frameFps"),
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
            json.put("minBitrateBps", BITRATE_MIN_BPS);
            json.put("maxBitrateBps", BITRATE_MAX_BPS);
            json.put("maxResolutionLabel", "1080p");
            json.put("defaultTarget", "1080p60");
            json.put("minimumTarget", "1080p30");
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
            json.put("minBitrateBps", minBitrateBps);
            json.put("targetBitrateBps", targetBitrateBps);
            json.put("maxBitrateBps", maxBitrateBps);
            json.put("minVideoBitrateBps", minBitrateBps);
            json.put("targetVideoBitrateBps", targetBitrateBps);
            json.put("maxVideoBitrateBps", maxBitrateBps);
            json.put("bitratePolicy", bitratePolicy);
            json.put("captureBackend", captureBackend);
            json.put("runtimeTuning", true);
            json.put("maxFrameWidth", MAX_FRAME_WIDTH);
            json.put("maxFps", MAX_FRAME_FPS);
            return json;
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
                    && minBitrateBps == other.minBitrateBps
                    && targetBitrateBps == other.targetBitrateBps
                    && maxBitrateBps == other.maxBitrateBps
                    && captureBackend.equals(other.captureBackend);
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
