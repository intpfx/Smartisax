package com.smartisax.browser;

import android.content.Context;
import android.graphics.Point;
import android.os.SystemClock;
import java.io.IOException;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxAgentRuntime {
    static final int MAX_STEPS = 5;
    private static final int MIN_SAFE_TAP_Y = 1000;
    private static final int MAX_SAFE_TAP_Y = 9700;
    private static final int SAME_TAP_TOLERANCE = 250;
    private static final int MAX_REOBSERVE_SKIPS = 2;
    private static final long PRE_ACTION_OBSERVE_DELAY_MS = 120L;
    private static final long POST_ACTION_OBSERVE_DELAY_MS = 650L;
    private static final long REOBSERVE_SETTLE_DELAY_MS = 300L;
    private static final Object INSTANCE_LOCK = new Object();
    private static SmartisaxAgentRuntime instance;

    private final Context context;
    private final Object lock = new Object();
    private Thread worker;
    private boolean stopRequested;
    private String state = "idle";
    private String goal = "";
    private String providerId = "";
    private String lastError = "";
    private int step;
    private long startedAtMs;
    private long updatedAtMs;
    private final JSONArray transcript = new JSONArray();

    private SmartisaxAgentRuntime(Context context) {
        this.context = context.getApplicationContext();
    }

    static SmartisaxAgentRuntime get(Context context) {
        synchronized (INSTANCE_LOCK) {
            if (instance == null) {
                instance = new SmartisaxAgentRuntime(context);
            }
            return instance;
        }
    }

    JSONObject start(String requestedGoal) {
        String cleanGoal = requestedGoal == null ? "" : requestedGoal.trim();
        synchronized (lock) {
            if (worker != null && worker.isAlive()) {
                return statusWithErrorLocked("agent_already_running");
            }
            if (cleanGoal.length() == 0) {
                return statusWithErrorLocked("missing_goal");
            }
            if (cleanGoal.length() > 600) {
                cleanGoal = cleanGoal.substring(0, 600);
            }
            SmartisaxAgentConfig config = SmartisaxAgentConfig.load(context);
            String selected = config.selectedProviderId();
            if (selected.length() == 0) {
                return statusWithErrorLocked("missing_model_api_key");
            }
            if (SmartisaxAgentConfig.PROVIDER_MIMO.equals(selected) && !config.hasMimoKey()) {
                return statusWithErrorLocked("missing_mimo_api_key");
            }
            if (SmartisaxAgentConfig.PROVIDER_DEEPSEEK.equals(selected) && !config.hasDeepSeekKey()) {
                return statusWithErrorLocked("missing_deepseek_api_key");
            }
            stopRequested = false;
            state = "running";
            goal = cleanGoal;
            providerId = selected;
            lastError = "";
            step = 0;
            startedAtMs = System.currentTimeMillis();
            updatedAtMs = startedAtMs;
            clearTranscriptLocked();
            final String runGoal = cleanGoal;
            final SmartisaxAgentConfig runConfig = config;
            worker = new Thread(new Runnable() {
                @Override
                public void run() {
                    runLoop(runGoal, runConfig);
                }
            }, "SmartisaxAgentRuntime");
            worker.start();
            return statusJsonLocked();
        }
    }

    JSONObject stop() {
        synchronized (lock) {
            stopRequested = true;
            if ("running".equals(state)) {
                state = "stopping";
            }
            if (worker != null) {
                worker.interrupt();
            }
            updatedAtMs = System.currentTimeMillis();
            return statusJsonLocked();
        }
    }

    JSONObject statusJson() {
        synchronized (lock) {
            return statusJsonLocked();
        }
    }

    private void runLoop(String runGoal, SmartisaxAgentConfig config) {
        String previousResult = "";
        SmartisaxAgentAction previousTap = null;
        SmartisaxAgentAction previousKey = null;
        SmartisaxAgentAction previousNode = null;
        boolean previousTapHadVisualCheck = false;
        boolean previousTapChanged = true;
        boolean previousKeyHadVisualCheck = false;
        boolean previousKeyChanged = true;
        boolean previousNodeHadVisualCheck = false;
        boolean previousNodeChanged = true;
        boolean uiActionAttempted = false;
        boolean lastUiActionVerifiedChange = false;
        boolean previousObservedScreenChanged = false;
        int reobserveSkips = 0;
        try {
            SmartisaxAgentProvider provider = SmartisaxAgentProviders.create(config.selectedProviderId());
            for (int i = 1; i <= MAX_STEPS; i++) {
                if (isStopRequested()) {
                    finishState("stopped", "stop_requested");
                    return;
                }
                updateStep(i, provider.id());
                SmartisaxScreenCapture.AgentObservation observation = null;
                if (provider.needsVision()) {
                    observation = SmartisaxScreenCapture.captureForAgent(context);
                }
                JSONObject display = SmartisaxScreenCapture.displayJson(context);
                JSONObject systemState = SmartisaxOneStepController.systemStateJson(context);
                JSONObject accessibilityTree = SmartisaxAccessibilityService.treeJson(context);
                StepRequest request = new StepRequest(
                        runGoal,
                        i,
                        provider.id(),
                        config,
                        observation,
                        display,
                        systemState,
                        accessibilityTree,
                        transcriptSnapshot(),
                        previousResult);
                recordStep(i, provider.id(), observation, null, 0L, "planning", planningResult(
                        display, systemState, accessibilityTree));
                long planStart = SystemClock.elapsedRealtime();
                SmartisaxAgentAction action;
                long planMs;
                try {
                    action = provider.plan(request);
                    planMs = Math.max(0L, SystemClock.elapsedRealtime() - planStart);
                } catch (Exception e) {
                    planMs = Math.max(0L, SystemClock.elapsedRealtime() - planStart);
                    JSONObject failure = providerFailureResult(e, config, planMs);
                    previousResult = failure.toString();
                    recordStep(i, provider.id(), observation, null, planMs, "paused_provider_error", failure);
                    finishState("paused", failure.optString("reason", "provider_request_failed"));
                    return;
                }
                if (action.isLowConfidence()) {
                    recordStep(i, provider.id(), observation, action, planMs, "paused_low_confidence", null);
                    finishState("paused", "low_confidence");
                    return;
                }
                PreActionCheck freshnessCheck = preActionFreshnessGuard(provider, observation, action);
                if (freshnessCheck.shouldReobserve) {
                    previousResult = freshnessCheck.result.toString();
                    reobserveSkips++;
                    String status = reobserveSkips > MAX_REOBSERVE_SKIPS
                            ? "paused_screen_changed_before_action"
                            : "skipped_reobserve_screen_changed";
                    recordStep(i, provider.id(), observation, action, planMs, status, freshnessCheck.result);
                    if (reobserveSkips > MAX_REOBSERVE_SKIPS) {
                        finishState("paused", "screen_changed_before_action_reobserve_limit");
                        return;
                    }
                    sleepInterruptibly(REOBSERVE_SETTLE_DELAY_MS);
                    continue;
                }
                JSONObject guard = coordinateGuard(action, display);
                if (guard != null) {
                    if (shouldReobserveCoordinateGuard(provider, previousObservedScreenChanged, reobserveSkips)) {
                        JSONObject reobserveResult = coordinateReobserveResult(guard);
                        previousResult = reobserveResult.toString();
                        reobserveSkips++;
                        recordStep(i, provider.id(), observation, action, planMs,
                                "skipped_coordinate_guard_reobserve", reobserveResult);
                        sleepInterruptibly(REOBSERVE_SETTLE_DELAY_MS);
                        continue;
                    }
                    recordStep(i, provider.id(), observation, action, planMs, "paused_coordinate_guard", guard);
                    finishState("paused", guard.optString("reason", "coordinate_guard"));
                    return;
                }
                JSONObject result = executeAction(action, display);
                if ("finish".equals(action.type)) {
                    JSONObject finishGate = finishGate(
                            runGoal,
                            action,
                            uiActionAttempted,
                            lastUiActionVerifiedChange,
                            systemState,
                            accessibilityTree);
                    result.put("finishGate", finishGate);
                    if (!finishGate.optBoolean("accepted", false)) {
                        recordStep(i, provider.id(), observation, action, planMs, "paused_finish_unverified", result);
                        finishState("paused", finishGate.optString(
                                "reason", "finish_requires_verified_screen_change"));
                        return;
                    }
                    previousResult = result.toString();
                    recordStep(i, provider.id(), observation, action, planMs, "executed", result);
                    finishState("complete", action.message.length() > 0 ? action.message : "finished");
                    return;
                }
                if ("ask_user".equals(action.type)) {
                    previousResult = result.toString();
                    recordStep(i, provider.id(), observation, action, planMs, "executed", result);
                    finishState("paused", action.message);
                    return;
                }
                JSONObject actionFailure = actionFailure(action, result);
                if (actionFailure != null) {
                    previousResult = result.toString();
                    recordStep(i, provider.id(), observation, action, planMs,
                            "paused_action_not_satisfied", result);
                    finishState("paused", actionFailure.optString(
                            "reason", "action_not_satisfied"));
                    return;
                }
                PostActionCheck postActionCheck = observeAfterAction(provider, observation, action, result);
                if (postActionCheck.uiAction) {
                    uiActionAttempted = true;
                    lastUiActionVerifiedChange = postActionCheck.comparable && postActionCheck.screenChanged;
                }
                if (postActionCheck.comparable) {
                    previousObservedScreenChanged = postActionCheck.screenChanged;
                }
                boolean repeatedTapNoChange = "tap".equals(action.type)
                        && previousTap != null
                        && sameTap(action, previousTap)
                        && previousTapHadVisualCheck
                        && !previousTapChanged
                        && postActionCheck.comparable
                        && !postActionCheck.screenChanged;
                boolean repeatedKeyNoChange = "key".equals(action.type)
                        && previousKey != null
                        && sameKey(action, previousKey)
                        && previousKeyHadVisualCheck
                        && !previousKeyChanged
                        && postActionCheck.comparable
                        && !postActionCheck.screenChanged;
                boolean repeatedNodeNoChange = "click_node".equals(action.type)
                        && previousNode != null
                        && sameNode(action, previousNode)
                        && previousNodeHadVisualCheck
                        && !previousNodeChanged
                        && postActionCheck.comparable
                        && !postActionCheck.screenChanged;
                if ("tap".equals(action.type)) {
                    previousTap = action;
                    previousTapHadVisualCheck = postActionCheck.comparable;
                    previousTapChanged = postActionCheck.screenChanged;
                }
                if ("key".equals(action.type)) {
                    previousKey = action;
                    previousKeyHadVisualCheck = postActionCheck.comparable;
                    previousKeyChanged = postActionCheck.screenChanged;
                }
                if ("click_node".equals(action.type)) {
                    previousNode = action;
                    previousNodeHadVisualCheck = postActionCheck.comparable;
                    previousNodeChanged = postActionCheck.screenChanged;
                }
                reobserveSkips = 0;
                previousResult = result.toString();
                String status = repeatedTapNoChange
                        ? "paused_repeated_tap_no_screen_change"
                        : repeatedKeyNoChange
                                ? "paused_repeated_key_no_screen_change"
                                : repeatedNodeNoChange ? "paused_repeated_node_no_screen_change" : "executed";
                recordStep(i, provider.id(), observation, action, planMs, status, result);
                if (repeatedTapNoChange) {
                    finishState("paused", "repeated_tap_no_screen_change");
                    return;
                }
                if (repeatedKeyNoChange) {
                    finishState("paused", "repeated_key_no_screen_change");
                    return;
                }
                if (repeatedNodeNoChange) {
                    finishState("paused", "repeated_node_no_screen_change");
                    return;
                }
                sleepInterruptibly(250L);
            }
            finishState("paused", "max_steps_reached");
        } catch (InterruptedException e) {
            finishState("stopped", "interrupted");
        } catch (Exception e) {
            finishState("error", config.redact(e.toString()));
        } catch (Throwable t) {
            finishState("error", config.redact(t.toString()));
        }
    }

    private JSONObject planningResult(
            JSONObject display,
            JSONObject systemState,
            JSONObject accessibilityTree) throws JSONException {
        JSONObject result = new JSONObject();
        result.put("type", "provider_planning");
        result.put("message", "Provider request started.");
        result.put("display", display);
        result.put("oneStep", systemState.optJSONObject("oneStep"));
        JSONObject a11y = new JSONObject();
        a11y.put("hasRoot", accessibilityTree.optBoolean("hasRoot", false));
        a11y.put("rootCount", accessibilityTree.optInt("rootCount", 0));
        a11y.put("windowCount", accessibilityTree.optInt("windowCount", 0));
        a11y.put("nodeCount", accessibilityTree.optInt("nodeCount", 0));
        a11y.put("truncated", accessibilityTree.optBoolean("truncated", false));
        result.put("accessibility", a11y);
        return result;
    }

    private JSONObject providerFailureResult(Exception error, SmartisaxAgentConfig config, long planMs)
            throws JSONException {
        String redacted = config.redact(error == null ? "" : error.toString());
        String reason = providerFailureReason(redacted);
        JSONObject result = new JSONObject();
        result.put("type", "provider_error");
        result.put("guard", reason.startsWith("provider_network") || reason.endsWith("_timeout")
                ? "provider_network_guard"
                : "provider_error_guard");
        result.put("reason", reason);
        result.put("planMs", planMs);
        result.put("message", "Provider did not return a safe action; paused.");
        result.put("error", redacted);
        return result;
    }

    private String providerFailureReason(String error) {
        String value = error == null ? "" : error.toLowerCase();
        if (value.contains("provider_network_dns_unavailable")
                || value.contains("unknownhost")
                || value.contains("unknown host")
                || value.contains("no address associated")) {
            return "provider_network_dns_unavailable";
        }
        if (value.contains("provider_network_unavailable")
                || value.contains("network is unreachable")
                || value.contains("failed to connect")
                || value.contains("connectexception")) {
            return "provider_network_unavailable";
        }
        if (value.contains("provider_request_timeout")
                || value.contains("sockettimeoutexception")
                || value.contains("timed out")
                || value.contains("timeout")) {
            return "provider_request_timeout";
        }
        if (value.contains("missing_mimo_api_key") || value.contains("missing_deepseek_api_key")) {
            return "provider_missing_api_key";
        }
        return "provider_request_failed";
    }

    private PreActionCheck preActionFreshnessGuard(
            SmartisaxAgentProvider provider,
            SmartisaxScreenCapture.AgentObservation plannedObservation,
            SmartisaxAgentAction action) throws IOException, JSONException, InterruptedException {
        if (!provider.needsVision() || plannedObservation == null || !requiresFreshVision(action.type)) {
            return PreActionCheck.none();
        }
        sleepInterruptibly(PRE_ACTION_OBSERVE_DELAY_MS);
        SmartisaxScreenCapture.AgentObservation freshObservation =
                SmartisaxScreenCapture.captureForAgent(context);
        JSONObject check = screenDiffJson(plannedObservation, freshObservation);
        if (!check.optBoolean("screenChanged", false)) {
            return PreActionCheck.none();
        }
        JSONObject result = new JSONObject();
        result.put("type", "runtime_guard");
        result.put("guard", "screen_freshness_guard");
        result.put("reason", "screen_changed_before_action");
        result.put("actionSkipped", true);
        result.put("message", "Screen changed materially after planning; skipped stale action and will reobserve.");
        result.put("preActionCheck", check);
        result.put("freshObservation", freshObservation.summaryJson());
        return new PreActionCheck(true, result);
    }

    private boolean requiresFreshVision(String actionType) {
        return isUiAction(actionType) || "finish".equals(actionType);
    }

    private boolean shouldReobserveCoordinateGuard(
            SmartisaxAgentProvider provider,
            boolean previousObservedScreenChanged,
            int reobserveSkips) {
        return provider.needsVision()
                && previousObservedScreenChanged
                && reobserveSkips < MAX_REOBSERVE_SKIPS;
    }

    private JSONObject coordinateReobserveResult(JSONObject guard) throws JSONException {
        JSONObject result = new JSONObject();
        result.put("type", "runtime_guard");
        result.put("guard", "coordinate_edge_guard");
        result.put("reason", "coordinate_guard_after_screen_change_reobserve");
        result.put("actionSkipped", true);
        result.put("screenChangedAfterPreviousAction", true);
        result.put("coordinateGuard", guard);
        result.put("message", "Previous action materially changed the screen; reobserve before trusting this edge coordinate.");
        return result;
    }

    private JSONObject coordinateGuard(SmartisaxAgentAction action, JSONObject display) throws JSONException {
        if (!"tap".equals(action.type)) {
            return null;
        }
        if (action.y >= MIN_SAFE_TAP_Y && action.y <= MAX_SAFE_TAP_Y) {
            return null;
        }
        JSONObject guard = new JSONObject();
        guard.put("type", "runtime_guard");
        guard.put("guard", "coordinate_edge_guard");
        guard.put("reason", "tap_coordinate_in_screen_edge_band");
        guard.put("minSafeY", MIN_SAFE_TAP_Y);
        guard.put("maxSafeY", MAX_SAFE_TAP_Y);
        guard.put("normalizedX", action.x);
        guard.put("normalizedY", action.y);
        guard.put("mappedX", mapX(action.x, display));
        guard.put("mappedY", mapY(action.y, display));
        guard.put("message", "Tap coordinate is too close to the top or bottom edge; paused for a new plan.");
        return guard;
    }

    private JSONObject finishGate(
            String runGoal,
            SmartisaxAgentAction action,
            boolean uiActionAttempted,
            boolean lastUiActionVerifiedChange,
            JSONObject systemState,
            JSONObject accessibilityTree)
            throws JSONException {
        JSONObject gate = new JSONObject();
        gate.put("requiresPostActionObservation", uiActionAttempted);
        gate.put("lastUiActionVerifiedScreenChange", lastUiActionVerifiedChange);
        JSONObject target = finishTargetVerification(runGoal, action, systemState, accessibilityTree);
        gate.put("targetVerification", target);
        boolean targetVerified = target.optBoolean("accepted", false);
        boolean accepted = !uiActionAttempted || lastUiActionVerifiedChange || targetVerified;
        gate.put("accepted", accepted);
        if (!accepted) {
            gate.put("reason", "finish_requires_verified_screen_change");
        } else if (targetVerified) {
            gate.put("reason", "finish_target_verified");
        }
        return gate;
    }

    private JSONObject finishTargetVerification(
            String runGoal,
            SmartisaxAgentAction action,
            JSONObject systemState,
            JSONObject accessibilityTree) throws JSONException {
        JSONObject target = new JSONObject();
        String intentText = ((runGoal == null ? "" : runGoal) + " "
                + (action == null ? "" : action.message)).toLowerCase(Locale.US);
        if (!mentionsSettings(intentText)) {
            target.put("enabled", false);
            target.put("accepted", false);
            target.put("reason", "no_known_finish_target");
            return target;
        }
        target.put("enabled", true);
        target.put("target", "settings_app");
        JSONObject foreground = systemState == null ? null : systemState.optJSONObject("foreground");
        String foregroundPackage = foreground == null ? "" : foreground.optString("package", "");
        String foregroundClass = foreground == null ? "" : foreground.optString("class", "");
        boolean foregroundSettings = "com.android.settings".equals(foregroundPackage);
        boolean windowSettings = accessibilityHasSettingsWindow(accessibilityTree);
        boolean packageNodeSettings = accessibilityHasSettingsPackageNode(accessibilityTree);
        target.put("foregroundPackage", foregroundPackage);
        target.put("foregroundClass", foregroundClass);
        target.put("foregroundPackageMatched", foregroundSettings);
        target.put("accessibilityWindowMatched", windowSettings);
        target.put("accessibilityPackageNodeMatched", packageNodeSettings);
        boolean accepted = foregroundSettings || windowSettings || packageNodeSettings;
        target.put("accepted", accepted);
        target.put("reason", accepted ? "settings_target_visible" : "settings_target_not_visible");
        return target;
    }

    private boolean mentionsSettings(String value) {
        return value != null
                && (value.contains("settings")
                || value.contains("com.android.settings")
                || value.contains("设置"));
    }

    private boolean accessibilityHasSettingsWindow(JSONObject accessibilityTree) {
        JSONArray windows = accessibilityTree == null ? null : accessibilityTree.optJSONArray("windows");
        if (windows == null) {
            return false;
        }
        for (int i = 0; i < windows.length(); i++) {
            JSONObject window = windows.optJSONObject(i);
            if (window == null) {
                continue;
            }
            String title = window.optString("title", "").toLowerCase(Locale.US);
            String type = window.optString("type", "");
            if ("APPLICATION".equals(type) && mentionsSettings(title)) {
                return true;
            }
        }
        return false;
    }

    private boolean accessibilityHasSettingsPackageNode(JSONObject accessibilityTree) {
        JSONArray nodes = accessibilityTree == null ? null : accessibilityTree.optJSONArray("nodes");
        if (nodes == null) {
            return false;
        }
        for (int i = 0; i < nodes.length(); i++) {
            JSONObject node = nodes.optJSONObject(i);
            if (node == null) {
                continue;
            }
            if ("com.android.settings".equals(node.optString("package", ""))) {
                return true;
            }
        }
        return false;
    }

    private JSONObject actionFailure(SmartisaxAgentAction action, JSONObject result)
            throws JSONException {
        if (!"one_step".equals(action.type)) {
            if (!"click_node".equals(action.type)) {
                return null;
            }
            JSONObject accessibility = result.optJSONObject("accessibility");
            if (accessibility != null && accessibility.optBoolean("ok", false)) {
                return null;
            }
            JSONObject guard = new JSONObject();
            guard.put("type", "runtime_guard");
            guard.put("guard", "accessibility_action_guard");
            guard.put("reason", accessibility == null
                    ? "accessibility_missing_result"
                    : accessibility.optString("reason", "accessibility_click_failed"));
            guard.put("message", "Accessibility click did not complete; paused.");
            result.put("actionFailure", guard);
            return guard;
        }
        JSONObject oneStep = result.optJSONObject("oneStep");
        if (oneStep != null && oneStep.optBoolean("satisfied", false)) {
            return null;
        }
        JSONObject guard = new JSONObject();
        guard.put("type", "runtime_guard");
        guard.put("guard", "one_step_state_guard");
        guard.put("reason", oneStep == null
                ? "one_step_missing_result"
                : oneStep.optString("failureReason", "one_step_not_satisfied"));
        guard.put("message", "One Step action did not reach the requested visible state; paused.");
        result.put("actionFailure", guard);
        return guard;
    }

    private PostActionCheck observeAfterAction(
            SmartisaxAgentProvider provider,
            SmartisaxScreenCapture.AgentObservation before,
            SmartisaxAgentAction action,
            JSONObject result) throws IOException, JSONException, InterruptedException {
        if (!isObservedAction(action.type)) {
            return PostActionCheck.none();
        }
        boolean uiAction = isUiAction(action.type);
        sleepInterruptibly(POST_ACTION_OBSERVE_DELAY_MS);
        JSONObject check = new JSONObject();
        check.put("delayMs", POST_ACTION_OBSERVE_DELAY_MS);
        check.put("visionProvider", provider.needsVision());
        if (!provider.needsVision()) {
            check.put("comparable", false);
            check.put("screenChanged", JSONObject.NULL);
            check.put("reason", "post_action_vision_not_available");
            result.put("postActionCheck", check);
            return new PostActionCheck(uiAction, false, false);
        }
        SmartisaxScreenCapture.AgentObservation after = SmartisaxScreenCapture.captureForAgent(context);
        JSONObject diff = screenDiffJson(before, after);
        check.put("comparable", diff.optBoolean("comparable", false));
        if (diff.has("screenChanged")) {
            check.put("screenChanged", diff.opt("screenChanged"));
        }
        if (diff.has("visualDistance")) {
            check.put("visualDistance", diff.opt("visualDistance"));
        }
        if (diff.has("changedCells")) {
            check.put("changedCells", diff.opt("changedCells"));
        }
        if (diff.has("cellCount")) {
            check.put("cellCount", diff.opt("cellCount"));
        }
        if (diff.has("exactFingerprintChanged")) {
            check.put("exactFingerprintChanged", diff.opt("exactFingerprintChanged"));
        }
        if (diff.has("beforeFingerprint")) {
            check.put("beforeFingerprint", diff.opt("beforeFingerprint"));
        }
        if (diff.has("afterFingerprint")) {
            check.put("afterFingerprint", diff.opt("afterFingerprint"));
        }
        boolean comparable = check.optBoolean("comparable", false);
        boolean changed = check.optBoolean("screenChanged", false);
        result.put("postObservation", after.summaryJson());
        result.put("postActionCheck", check);
        return new PostActionCheck(uiAction, comparable, changed);
    }

    private JSONObject screenDiffJson(
            SmartisaxScreenCapture.AgentObservation before,
            SmartisaxScreenCapture.AgentObservation after) throws JSONException {
        JSONObject diff = new JSONObject();
        boolean comparable = before != null && after != null && before.canCompareVisual(after);
        diff.put("comparable", comparable);
        if (!comparable) {
            diff.put("screenChanged", JSONObject.NULL);
            diff.put("reason", "visual_signature_not_comparable");
            return diff;
        }
        double visualDistance = before.visualDistance(after);
        int changedCells = before.visualChangedCells(after);
        boolean screenChanged = before.materiallyDifferent(after);
        String beforeFingerprint = before.fingerprint();
        String afterFingerprint = after.fingerprint();
        diff.put("screenChanged", screenChanged);
        diff.put("visualDistance", roundToTenth(visualDistance));
        diff.put("changedCells", changedCells);
        diff.put("cellCount", before.visualCellCount());
        diff.put("exactFingerprintChanged",
                beforeFingerprint.length() > 0
                        && afterFingerprint.length() > 0
                        && !beforeFingerprint.equals(afterFingerprint));
        if (beforeFingerprint.length() > 0) {
            diff.put("beforeFingerprint", shortFingerprint(beforeFingerprint));
        }
        if (afterFingerprint.length() > 0) {
            diff.put("afterFingerprint", shortFingerprint(afterFingerprint));
        }
        return diff;
    }

    private double roundToTenth(double value) {
        return Math.round(value * 10.0d) / 10.0d;
    }

    private boolean sameTap(SmartisaxAgentAction current, SmartisaxAgentAction previous) {
        return Math.abs(current.x - previous.x) <= SAME_TAP_TOLERANCE
                && Math.abs(current.y - previous.y) <= SAME_TAP_TOLERANCE;
    }

    private boolean sameKey(SmartisaxAgentAction current, SmartisaxAgentAction previous) {
        return current.key.equals(previous.key);
    }

    private boolean sameNode(SmartisaxAgentAction current, SmartisaxAgentAction previous) {
        return current.nodeId.equals(previous.nodeId);
    }

    private boolean isUiAction(String type) {
        return "tap".equals(type)
                || "swipe".equals(type)
                || "key".equals(type)
                || "one_step".equals(type)
                || "click_node".equals(type);
    }

    private boolean isObservedAction(String type) {
        return isUiAction(type) || "wait".equals(type);
    }

    private String shortFingerprint(String value) {
        return value == null || value.length() <= 16 ? value : value.substring(0, 16);
    }

    private JSONObject executeAction(SmartisaxAgentAction action, JSONObject display)
            throws IOException, JSONException, InterruptedException {
        JSONObject result = new JSONObject();
        result.put("type", action.type);
        if ("tap".equals(action.type)) {
            JSONObject input = new JSONObject();
            input.put("type", "tap");
            input.put("x", mapX(action.x, display));
            input.put("y", mapY(action.y, display));
            input.put("marker", false);
            result.put("input", SmartisaxInputController.handle(input));
            return result;
        }
        if ("swipe".equals(action.type)) {
            JSONObject input = new JSONObject();
            input.put("type", "swipe");
            input.put("x1", mapX(action.x1, display));
            input.put("y1", mapY(action.y1, display));
            input.put("x2", mapX(action.x2, display));
            input.put("y2", mapY(action.y2, display));
            input.put("duration", action.durationMs);
            input.put("marker", false);
            result.put("input", SmartisaxInputController.handle(input));
            return result;
        }
        if ("key".equals(action.type)) {
            JSONObject input = new JSONObject();
            input.put("type", "key");
            input.put("key", action.key);
            input.put("marker", false);
            result.put("input", SmartisaxInputController.handle(input));
            return result;
        }
        if ("wait".equals(action.type)) {
            sleepInterruptibly(action.durationMs);
            result.put("waitedMs", action.durationMs);
            return result;
        }
        if ("one_step".equals(action.type)) {
            result.put("oneStep", SmartisaxOneStepController.handle(context, action.operation, display));
            return result;
        }
        if ("click_node".equals(action.type)) {
            result.put("accessibility", SmartisaxAccessibilityService.clickNode(context, action.nodeId));
            return result;
        }
        if ("finish".equals(action.type) || "ask_user".equals(action.type)) {
            result.put("message", action.message);
            return result;
        }
        throw new IOException("unsupported_runtime_action_" + action.type);
    }

    private int mapX(int normalized, JSONObject display) {
        return mapCoordinate(normalized, display.optInt("width", 1080));
    }

    private int mapY(int normalized, JSONObject display) {
        return mapCoordinate(normalized, display.optInt("height", 2340));
    }

    private int mapCoordinate(int normalized, int size) {
        int max = Math.max(0, size - 1);
        int mapped = Math.round((normalized / 10000.0f) * max);
        return Math.max(0, Math.min(max, mapped));
    }

    private void updateStep(int nextStep, String nextProviderId) {
        synchronized (lock) {
            step = nextStep;
            providerId = nextProviderId;
            state = "running";
            updatedAtMs = System.currentTimeMillis();
        }
    }

    private void recordStep(
            int index,
            String provider,
            SmartisaxScreenCapture.AgentObservation observation,
            SmartisaxAgentAction action,
            long planMs,
            String status,
            JSONObject result) throws JSONException {
        JSONObject entry = new JSONObject();
        entry.put("step", index);
        entry.put("provider", provider);
        entry.put("status", status);
        entry.put("planMs", planMs);
        if (action != null) {
            entry.put("action", action.toJson());
        }
        if (observation != null) {
            entry.put("observation", observation.summaryJson());
        } else {
            Point size = SmartisaxScreenCapture.realDisplaySize(context);
            entry.put("observation", new JSONObject()
                    .put("vision", "not_sent")
                    .put("displayWidth", size.x)
                    .put("displayHeight", size.y));
        }
        if (result != null) {
            entry.put("result", result);
        }
        entry.put("atMs", System.currentTimeMillis());
        synchronized (lock) {
            transcript.put(entry);
            updatedAtMs = System.currentTimeMillis();
        }
    }

    private JSONArray transcriptSnapshot() {
        synchronized (lock) {
            try {
                return new JSONArray(transcript.toString());
            } catch (JSONException ignored) {
                return new JSONArray();
            }
        }
    }

    private boolean isStopRequested() {
        synchronized (lock) {
            return stopRequested;
        }
    }

    private void finishState(String nextState, String message) {
        synchronized (lock) {
            state = nextState;
            lastError = message == null ? "" : message;
            stopRequested = false;
            updatedAtMs = System.currentTimeMillis();
        }
    }

    private void sleepInterruptibly(long ms) throws InterruptedException {
        long end = SystemClock.elapsedRealtime() + Math.max(0L, ms);
        while (SystemClock.elapsedRealtime() < end) {
            if (isStopRequested()) {
                throw new InterruptedException("stop_requested");
            }
            Thread.sleep(Math.min(100L, end - SystemClock.elapsedRealtime()));
        }
    }

    private JSONObject statusWithErrorLocked(String error) {
        lastError = error;
        updatedAtMs = System.currentTimeMillis();
        return statusJsonLocked();
    }

    private JSONObject statusJsonLocked() {
        reconcileWorkerStateLocked();
        JSONObject json = new JSONObject();
        try {
            json.put("ok", lastError.length() == 0 || !"error".equals(state));
            json.put("agentVersion", "v0.agent0.10-finish-target-verify");
            json.put("state", state);
            json.put("running", worker != null && worker.isAlive());
            json.put("stopRequested", stopRequested);
            json.put("goal", goal);
            json.put("provider", providerId);
            json.put("step", step);
            json.put("maxSteps", MAX_STEPS);
            json.put("lastMessage", lastError);
            json.put("startedAtMs", startedAtMs);
            json.put("updatedAtMs", updatedAtMs);
            json.put("systemState", SmartisaxOneStepController.systemStateJson(context));
            json.put("accessibility", SmartisaxAccessibilityService.summaryJson(context));
            json.put("accessibilityTargets", SmartisaxAccessibilityService.targetSummaryJson(context));
            json.put("policy", new JSONObject()
                    .put("runtime", "on-device-r2")
                    .put("visionFirst", true)
                    .put("uploadsScreenOnlyAfterManualStart", true)
                    .put("storesScreenshots", false)
                    .put("postActionObservation", true)
                    .put("screenChangeReobserve", new JSONObject()
                            .put("visualSignature", "12x12")
                            .put("preActionFreshnessDelayMs", PRE_ACTION_OBSERVE_DELAY_MS)
                            .put("settleDelayMs", REOBSERVE_SETTLE_DELAY_MS)
                            .put("maxSkips", MAX_REOBSERVE_SKIPS))
                    .put("finishRequiresVerifiedScreenChangeAfterUiAction", true)
                    .put("finishTargetVerification", "known app-open goals can complete when foreground/accessibility confirms the target app")
                    .put("oneStepAction", "programmatic IWindowManager transact with HOME/exit/enter visibility recovery and touch fallback")
                    .put("accessibilityTree", "compact active and interactive-window nodes sent only during manual Agent runs")
                    .put("providerRequestGuard", "planning transcript plus normalized network and timeout pauses")
                    .put("coordinateEdgeGuard", new JSONObject()
                            .put("tapMinY", MIN_SAFE_TAP_Y)
                            .put("tapMaxY", MAX_SAFE_TAP_Y))
                    .put("allowedActions", new JSONArray()
                            .put("tap")
                            .put("swipe")
                            .put("key")
                            .put("wait")
                            .put("one_step")
                            .put("click_node")
                            .put("finish")
                            .put("ask_user"))
                    .put("forbidden", "shell,root,adb,fastboot,erase,delete,clear-data"));
            json.put("config", SmartisaxAgentConfig.load(context).redactedJson());
            json.put("transcript", new JSONArray(transcript.toString()));
        } catch (JSONException ignored) {
        }
        return json;
    }

    private void reconcileWorkerStateLocked() {
        if (("running".equals(state) || "stopping".equals(state))
                && worker != null
                && !worker.isAlive()) {
            state = "error";
            lastError = "agent_worker_not_alive";
            stopRequested = false;
            updatedAtMs = System.currentTimeMillis();
        }
    }

    private void clearTranscriptLocked() {
        while (transcript.length() > 0) {
            transcript.remove(0);
        }
    }

    private static final class PreActionCheck {
        final boolean shouldReobserve;
        final JSONObject result;

        PreActionCheck(boolean shouldReobserve, JSONObject result) {
            this.shouldReobserve = shouldReobserve;
            this.result = result;
        }

        static PreActionCheck none() {
            return new PreActionCheck(false, null);
        }
    }

    private static final class PostActionCheck {
        final boolean uiAction;
        final boolean comparable;
        final boolean screenChanged;

        PostActionCheck(boolean uiAction, boolean comparable, boolean screenChanged) {
            this.uiAction = uiAction;
            this.comparable = comparable;
            this.screenChanged = screenChanged;
        }

        static PostActionCheck none() {
            return new PostActionCheck(false, false, false);
        }
    }

    static final class StepRequest {
        final String goal;
        final int stepIndex;
        final String providerId;
        final SmartisaxAgentConfig config;
        final SmartisaxScreenCapture.AgentObservation observation;
        final JSONObject displayJson;
        final JSONObject systemState;
        final JSONObject accessibilityTree;
        final JSONArray history;
        final String lastResult;

        StepRequest(
                String goal,
                int stepIndex,
                String providerId,
                SmartisaxAgentConfig config,
                SmartisaxScreenCapture.AgentObservation observation,
                JSONObject displayJson,
                JSONObject systemState,
                JSONObject accessibilityTree,
                JSONArray history,
                String lastResult) {
            this.goal = goal;
            this.stepIndex = stepIndex;
            this.providerId = providerId;
            this.config = config;
            this.observation = observation;
            this.displayJson = displayJson;
            this.systemState = systemState;
            this.accessibilityTree = accessibilityTree;
            this.history = history;
            this.lastResult = lastResult;
        }
    }
}
