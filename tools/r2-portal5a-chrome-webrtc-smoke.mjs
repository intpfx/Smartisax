#!/usr/bin/env node
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const key = process.argv[index];
  if (!key.startsWith("--")) {
    continue;
  }
  const value = process.argv[index + 1] && !process.argv[index + 1].startsWith("--")
    ? process.argv[++index]
    : "1";
  args.set(key, value);
}

const portalUrl = (args.get("--url") || "").replace(/\/$/, "");
const token = args.get("--token") || "";
const variant = args.get("--variant") || process.env.VARIANT || "v0.portal5a-native-webrtc-runtime";
const variantSlug = variant.replace(/[^A-Za-z0-9_.-]/g, "_");
const outDir = args.get("--out-dir") || `hard-rom/inspect/${variant}/portal-smoke-live`;
const timeoutMs = Number(args.get("--timeout-ms") || "45000");
const observeMs = Number(args.get("--observe-ms") || "0");
const preferCodecs = (args.get("--prefer-codecs") || args.get("--prefer-codec") || "")
  .split(/[,\s]+/)
  .map((item) => item.trim())
  .filter(Boolean);
const inputGestureTest = args.has("--input-gesture-test");
const inputLatencyTest = args.has("--input-latency-test");
const touchPhotonTest = args.has("--touch-photon-test");
const moveStreamTest = args.has("--move-stream-test") || touchPhotonTest;
const inputPingCountArg = args.get("--input-ping-count");
const inputChannelTest = args.has("--input-channel-test")
  || inputGestureTest
  || inputLatencyTest
  || touchPhotonTest
  || moveStreamTest
  || inputPingCountArg !== undefined;
const inputPingCount = Number(inputPingCountArg || (inputLatencyTest ? "30" : (inputChannelTest ? "1" : "0")));
const inputPingIntervalMs = Number(args.get("--input-ping-interval-ms") || "80");
const statsIntervalMs = Number(args.get("--stats-interval-ms") || "1000");
const moveStreamMoves = Number(args.get("--move-stream-moves") || "24");
const moveStreamIntervalMs = Number(args.get("--move-stream-interval-ms") || "16");
const moveStreamBatchSize = Number(args.get("--move-stream-batch-size") || "5");
const touchPhotonPredict = args.get("--touch-photon-predict") !== "0";
const quietPresentation = args.has("--quiet-presentation") || process.env.QUIET_PRESENTATION === "1";
const presenterModeRaw = (args.get("--presenter-mode") || process.env.PRESENTER_MODE || "video").trim().toLowerCase();
const presenterMode = ["video", "canvas", "dual", "probe"].includes(presenterModeRaw) ? presenterModeRaw : "video";
const canvasPresenterEnabled = presenterMode === "canvas" || presenterMode === "dual";
const touchPhotonDetectRaf = args.has("--touch-photon-detect-raf")
  || process.env.TOUCH_PHOTON_DETECT_RAF === "1"
  || presenterMode === "probe";
const touchPhotonRoiProbe = args.get("--touch-photon-roi-probe") !== "0"
  && process.env.TOUCH_PHOTON_ROI_PROBE !== "0";
const rvfcCadenceLite = args.get("--rvfc-cadence-lite") !== "0"
  && process.env.RVFC_CADENCE_LITE !== "0";
const tapX = Number(args.get("--tap-x") || "540");
const tapY = Number(args.get("--tap-y") || "1170");
const swipeX1 = Number(args.get("--swipe-x1") || "540");
const swipeY1 = Number(args.get("--swipe-y1") || "1300");
const swipeX2 = Number(args.get("--swipe-x2") || "540");
const swipeY2 = Number(args.get("--swipe-y2") || "900");
const chromePath = args.get("--chrome")
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const chromeAntiThrottle = args.get("--chrome-anti-throttle") !== "0"
  && process.env.CHROME_ANTI_THROTTLE !== "0";
const chromeWindowSize = args.get("--chrome-window-size")
  || process.env.CHROME_WINDOW_SIZE
  || "540,1170";
const chromeForceDeviceScaleFactor = args.get("--chrome-force-device-scale-factor")
  || process.env.CHROME_FORCE_DEVICE_SCALE_FACTOR
  || "1";
const chromeForeground = args.get("--chrome-foreground") !== "0"
  && process.env.CHROME_FOREGROUND !== "0";

if (!portalUrl || !token) {
  console.error("Usage: tools/r2-portal5a-chrome-webrtc-smoke.mjs --url http://<r2-ip>:37601 --token <token> [--variant v0.portal5b-native-webrtc-system-libs] [--prefer-codecs H264,AV1,VP9,H265] [--presenter-mode video|canvas|dual|probe] [--input-latency-test] [--touch-photon-test] [--move-stream-test]");
  process.exit(2);
}

await mkdir(outDir, { recursive: true });
const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "").replace("T", "-");
const reportPath = join(outDir, `chrome-webrtc-smoke-${variantSlug}-${stamp}.json`);
const htmlPath = join(outDir, `chrome-webrtc-smoke-${variantSlug}-${stamp}.html`);

let resultResolve;
let resultReject;
const resultPromise = new Promise((resolve, reject) => {
  resultResolve = resolve;
  resultReject = reject;
});

const html = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Smartisax ${variant} Chrome WebRTC Smoke</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 24px; }
      body.quiet { margin: 0; overflow: hidden; background: #000; }
      video,
      canvas { width: 360px; max-width: 100%; background: #111; }
      #presenterCanvas { display: none; }
      body.quiet h1,
      body.quiet pre { display: none; }
      body.quiet video,
      body.quiet #presenterCanvas {
        position: fixed;
        inset: 0;
        width: 100vw;
        height: 100vh;
        max-width: none;
        object-fit: contain;
        contain: strict;
        will-change: transform;
        transform: translateZ(0);
        background: #000;
      }
      body.presenter-canvas video {
        opacity: 0.001;
        pointer-events: none;
      }
      body.presenter-canvas #presenterCanvas,
      body.presenter-dual #presenterCanvas {
        display: block;
      }
      body.presenter-dual #presenterCanvas {
        opacity: 0.35;
        mix-blend-mode: difference;
        pointer-events: none;
      }
      pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    </style>
  </head>
  <body class="${[quietPresentation ? "quiet" : "", `presenter-${presenterMode}`].filter(Boolean).join(" ")}">
    <h1>Smartisax ${variant} Chrome WebRTC Smoke</h1>
    <video id="video" autoplay playsinline muted></video>
    <canvas id="presenterCanvas"></canvas>
    <pre id="log">starting</pre>
    <script>
      const logNode = document.querySelector("#log");
      const video = document.querySelector("#video");
      const presenterCanvas = document.querySelector("#presenterCanvas");
      const presenterCtx = presenterCanvas.getContext("2d", { alpha: false });
      const events = [];
      const receiverPresentationHints = [];
      const quietPresentation = ${JSON.stringify(quietPresentation)};
      const presenterMode = ${JSON.stringify(presenterMode)};
      const canvasPresenterEnabled = ${JSON.stringify(canvasPresenterEnabled)};
      const touchPhotonDetectRaf = ${JSON.stringify(touchPhotonDetectRaf)};
      const touchPhotonRoiProbe = ${JSON.stringify(touchPhotonRoiProbe)};
      const rvfcCadenceLite = ${JSON.stringify(rvfcCadenceLite)};
      const startedAt = Date.now();
      let logRenderTimer = 0;
      try {
        video.disableRemotePlayback = true;
      } catch (error) {
      }
      function renderLog() {
        logRenderTimer = 0;
        if (quietPresentation) {
          return;
        }
        logNode.textContent = events.slice(-120).map((entry) => entry.t + "ms " + (typeof entry.value === "string" ? entry.value : JSON.stringify(entry.value))).join("\\n");
      }
      function log(value) {
        events.push({ t: Date.now() - startedAt, value });
        if (quietPresentation) {
          return;
        }
        if (!logRenderTimer) {
          logRenderTimer = setTimeout(renderLog, 250);
        }
      }
      function wait(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
      }
      function elapsedMs() {
        return Date.now() - startedAt;
      }
      function roundNumber(value) {
        return Number.isFinite(value) ? Math.round(value * 100) / 100 : null;
      }
      const pageLifecycleEvents = [];
      function currentPageState() {
        let focus = null;
        try {
          focus = document.hasFocus();
        } catch (error) {
        }
        return {
          hidden: document.hidden,
          visibilityState: document.visibilityState,
          hasFocus: focus,
        };
      }
      function recordPageLifecycle(type) {
        const entry = Object.assign({ t: elapsedMs(), type }, currentPageState());
        pageLifecycleEvents.push(entry);
        log({ pageLifecycle: entry });
      }
      recordPageLifecycle("init");
      document.addEventListener("visibilitychange", () => recordPageLifecycle("visibilitychange"));
      window.addEventListener("focus", () => recordPageLifecycle("focus"));
      window.addEventListener("blur", () => recordPageLifecycle("blur"));
      window.addEventListener("pagehide", () => recordPageLifecycle("pagehide"));
      window.addEventListener("pageshow", () => recordPageLifecycle("pageshow"));
      window.addEventListener("freeze", () => recordPageLifecycle("freeze"));
      window.addEventListener("resume", () => recordPageLifecycle("resume"));
      function countFieldOver(samples, field, threshold) {
        return samples.filter((sample) => Number.isFinite(sample[field]) && sample[field] > threshold).length;
      }
      function maxField(samples, field) {
        let max = null;
        for (const sample of samples) {
          const value = sample[field];
          if (Number.isFinite(value) && (max === null || value > max)) {
            max = value;
          }
        }
        return roundNumber(max);
      }
      function percentile(sortedValues, p) {
        if (!sortedValues.length) return null;
        const index = (sortedValues.length - 1) * p;
        const lower = Math.floor(index);
        const upper = Math.ceil(index);
        if (lower === upper) return sortedValues[lower];
        return sortedValues[lower] + (sortedValues[upper] - sortedValues[lower]) * (index - lower);
      }
      function summarizeNumbers(values) {
        const clean = values.filter((value) => Number.isFinite(value)).slice().sort((a, b) => a - b);
        if (!clean.length) {
          return { count: 0 };
        }
        const sum = clean.reduce((total, value) => total + value, 0);
        return {
          count: clean.length,
          min: roundNumber(clean[0]),
          p50: roundNumber(percentile(clean, 0.5)),
          p95: roundNumber(percentile(clean, 0.95)),
          p99: roundNumber(percentile(clean, 0.99)),
          max: roundNumber(clean[clean.length - 1]),
          avg: roundNumber(sum / clean.length),
        };
      }
      function summarizeGapClusters(values, threshold) {
        let clusterCount = 0;
        let current = 0;
        let maxCluster = 0;
        for (const value of values) {
          if (Number.isFinite(value) && value > threshold) {
            current += 1;
            if (current === 1) {
              clusterCount += 1;
            }
            maxCluster = Math.max(maxCluster, current);
          } else {
            current = 0;
          }
        }
        return {
          thresholdMs: threshold,
          clusterCount,
          maxCluster,
        };
      }
      function summarizeVideoFrames(samples, supported) {
        const callbackIntervals = samples.map((sample) => sample.callbackDeltaMs).filter((value) => Number.isFinite(value));
        const mediaIntervals = samples.map((sample) => sample.mediaDeltaMs).filter((value) => Number.isFinite(value));
        const presentedFrameDeltas = samples.map((sample) => sample.presentedFrameDelta).filter((value) => Number.isFinite(value));
        const durationMs = samples.length > 1 ? samples[samples.length - 1].t - samples[0].t : 0;
        return {
          supported,
          cadenceLite: rvfcCadenceLite,
          presentationCadence: rvfcCadenceLite
            ? "rvfc-presentation-cadence-lite+marker-visible-tail-presentation-cadence"
            : "rvfc-full-sample",
          sampleCount: samples.length,
          firstFrameAtMs: samples.length ? samples[0].t : null,
          callbackFps: durationMs > 0 ? roundNumber((Math.max(0, samples.length - 1) * 1000) / durationMs) : null,
          callbackIntervalMs: summarizeNumbers(callbackIntervals),
          mediaIntervalMs: summarizeNumbers(mediaIntervals),
          presentedFrameDelta: summarizeNumbers(presentedFrameDeltas),
          longGaps: {
            over25ms: callbackIntervals.filter((value) => value > 25).length,
            over34ms: callbackIntervals.filter((value) => value > 34).length,
            over50ms: callbackIntervals.filter((value) => value > 50).length,
            over100ms: callbackIntervals.filter((value) => value > 100).length,
          },
          gapClusters: {
            over34ms: summarizeGapClusters(callbackIntervals, 34),
            over50ms: summarizeGapClusters(callbackIntervals, 50),
          },
        };
      }
      function summarizeAnimationFrames(samples, supported) {
        const intervals = samples.map((sample) => sample.deltaMs).filter((value) => Number.isFinite(value));
        const durationMs = samples.length > 1 ? samples[samples.length - 1].t - samples[0].t : 0;
        return {
          supported,
          sampleCount: samples.length,
          callbackFps: durationMs > 0 ? roundNumber((Math.max(0, samples.length - 1) * 1000) / durationMs) : null,
          intervalMs: summarizeNumbers(intervals),
          longGaps: {
            over25ms: intervals.filter((value) => value > 25).length,
            over34ms: intervals.filter((value) => value > 34).length,
            over50ms: intervals.filter((value) => value > 50).length,
            over100ms: intervals.filter((value) => value > 100).length,
          },
          samples,
        };
      }
      function summarizeCanvasPresenter(samples, supported, mode) {
        const intervals = samples.map((sample) => sample.deltaMs).filter((value) => Number.isFinite(value));
        const drawDurations = samples.map((sample) => sample.drawDurationMs).filter((value) => Number.isFinite(value));
        const mediaIntervals = samples.map((sample) => sample.mediaDeltaMs).filter((value) => Number.isFinite(value) && value > 0);
        const mediaChanges = samples.filter((sample) => sample.mediaChanged === true);
        const durationMs = samples.length > 1 ? samples[samples.length - 1].t - samples[0].t : 0;
        const mediaDurationMs = mediaChanges.length > 1 ? mediaChanges[mediaChanges.length - 1].t - mediaChanges[0].t : 0;
        return {
          supported,
          mode,
          enabled: canvasPresenterEnabled,
          sampleCount: samples.length,
          drawFps: durationMs > 0 ? roundNumber((Math.max(0, samples.length - 1) * 1000) / durationMs) : null,
          mediaChangeCount: mediaChanges.length,
          mediaChangeFps: mediaDurationMs > 0 ? roundNumber((Math.max(0, mediaChanges.length - 1) * 1000) / mediaDurationMs) : null,
          intervalMs: summarizeNumbers(intervals),
          drawDurationMs: summarizeNumbers(drawDurations),
          mediaIntervalMs: summarizeNumbers(mediaIntervals),
          longGaps: {
            over25ms: intervals.filter((value) => value > 25).length,
            over34ms: intervals.filter((value) => value > 34).length,
            over50ms: intervals.filter((value) => value > 50).length,
            over100ms: intervals.filter((value) => value > 100).length,
          },
          samples,
        };
      }
      function summarizeInputLatency(samples) {
        const byType = {};
        for (const sample of samples) {
          const type = sample.type || "unknown";
          if (!byType[type]) byType[type] = [];
          byType[type].push(sample.latencyMs);
        }
        const grouped = {};
        for (const [type, values] of Object.entries(byType)) {
          grouped[type] = summarizeNumbers(values);
        }
        return {
          sampleCount: samples.length,
          all: summarizeNumbers(samples.map((sample) => sample.latencyMs)),
          byType: grouped,
          samples,
        };
      }
      function summarizeTouchPhoton(samples) {
        return {
          sampleCount: samples.length,
          detectedCount: samples.filter((sample) => sample.detected).length,
          latencyMs: summarizeNumbers(samples.filter((sample) => sample.detected).map((sample) => sample.latencyMs)),
          samples,
        };
      }
      function markerNumber(value) {
        const number = Number(value);
        return Number.isFinite(number) ? roundNumber(number) : null;
      }
      function markerDrawStatus(marker) {
        if (!marker) {
          return null;
        }
        const mode = String(marker.mode || "");
        const generation = markerNumber(marker.generation);
        const lastDrawGeneration = markerNumber(marker.lastDrawGeneration);
        const lastDrawnElapsedMs = markerNumber(marker.lastDrawnElapsedMs);
        const lastDrawLatencyMs = markerNumber(marker.lastDrawLatencyMs);
        const drawBoostRequests = markerNumber(marker.drawBoostRequests);
        const drawBoostBurstFrames = markerNumber(marker.drawBoostBurstFrames);
        const drawSync = mode.toLowerCase().indexOf("draw") >= 0
          || lastDrawGeneration !== null
          || lastDrawLatencyMs !== null
          || drawBoostRequests !== null;
        return {
          mode,
          supported: marker.supported !== false,
          drawSync,
          drawUrgentBoost: marker.drawUrgentBoost || "",
          visible: marker.visible === true,
          generation,
          lastDrawGeneration,
          lastDrawnElapsedMs,
          lastDrawLatencyMs,
          drawBoostRequests,
          drawBoostBurstFrames,
        };
      }
      function markerDrawStatusKey(status) {
        if (!status) {
          return "";
        }
        return [
          status.mode,
          status.supported,
          status.drawSync,
          status.drawUrgentBoost,
          status.visible,
          status.generation,
          status.lastDrawGeneration,
          status.lastDrawnElapsedMs,
          status.lastDrawLatencyMs,
          status.drawBoostRequests,
          status.drawBoostBurstFrames,
        ].join("|");
      }
      function summarizeMarkerDrawSync(samples, finalMarker) {
        const clean = Array.isArray(samples) ? samples.slice() : [];
        const finalStatus = markerDrawStatus(finalMarker);
        if (finalStatus) {
          const finalSample = Object.assign({ t: elapsedMs(), label: "final" }, finalStatus);
          const last = clean.length ? clean[clean.length - 1] : null;
          if (!last || markerDrawStatusKey(last) !== markerDrawStatusKey(finalSample)) {
            clean.push(finalSample);
          }
        }
        const latest = clean.length ? clean[clean.length - 1] : finalStatus;
        const drawLatencies = clean.map((sample) => sample.lastDrawLatencyMs).filter((value) => Number.isFinite(value));
        return {
          supported: latest ? latest.supported !== false : false,
          drawSync: clean.some((sample) => sample.drawSync === true),
          sampleCount: clean.length,
          mode: latest && latest.mode ? latest.mode : "",
          latest,
          drawLatencyMs: summarizeNumbers(drawLatencies),
          drawBoostRequests: latest ? latest.drawBoostRequests : null,
          drawBoostBurstFrames: latest ? latest.drawBoostBurstFrames : null,
          samples: clean,
        };
      }
      function markerTargetColor(marker) {
        const color = marker && marker.color;
        if (!color) return null;
        return {
          r: Number(color.r),
          g: Number(color.g),
          b: Number(color.b),
        };
      }
      function markerRegion(marker) {
        const region = marker && marker.region;
        if (!region) return null;
        const left = Number(region.left);
        const top = Number(region.top);
        const width = Number(region.width);
        const height = Number(region.height);
        if (![left, top, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
          return null;
        }
        return { left, top, width, height };
      }
      function colorDistance(left, right) {
        if (!left || !right) return Infinity;
        const dr = left.r - right.r;
        const dg = left.g - right.g;
        const db = left.b - right.b;
        return Math.sqrt(dr * dr + dg * dg + db * db);
      }
      const observeMs = ${JSON.stringify(observeMs)};
      const inputChannelTest = ${JSON.stringify(inputChannelTest)};
      const inputGestureTest = ${JSON.stringify(inputGestureTest)};
      const inputLatencyTest = ${JSON.stringify(inputLatencyTest)};
      const touchPhotonTest = ${JSON.stringify(touchPhotonTest)};
      const moveStreamTest = ${JSON.stringify(moveStreamTest)};
      const inputPingCount = ${JSON.stringify(inputPingCount)};
      const inputPingIntervalMs = ${JSON.stringify(inputPingIntervalMs)};
      const statsIntervalMs = ${JSON.stringify(statsIntervalMs)};
      const preferCodecs = ${JSON.stringify(preferCodecs)};
      const moveStreamMoves = ${JSON.stringify(moveStreamMoves)};
      const moveStreamIntervalMs = ${JSON.stringify(moveStreamIntervalMs)};
      const moveStreamBatchSize = ${JSON.stringify(moveStreamBatchSize)};
      const touchPhotonPredict = ${JSON.stringify(touchPhotonPredict)};
      const markerPalette = [
        { r: 255, g: 0, b: 255, argb: "#FFFF00FF" },
        { r: 0, g: 229, b: 255, argb: "#FF00E5FF" },
        { r: 255, g: 224, b: 0, argb: "#FFFFE000" },
        { r: 0, g: 255, b: 128, argb: "#FF00FF80" },
      ];
      const gesturePayloads = ${JSON.stringify({
        tap: { x: tapX, y: tapY },
        swipe: { x1: swipeX1, y1: swipeY1, x2: swipeX2, y2: swipeY2, duration: 180 },
      })};
      const maxFrameCallbacks = observeMs > 0 ? 10000 : 3;
      const maxAnimationFrameCallbacks = observeMs > 0 ? 12000 : 240;
      const maxPresenterDrawCallbacks = observeMs > 0 ? 12000 : 240;
      function codecSummary(sdp) {
        const lines = String(sdp || "").split(/\\r?\\n/);
        const videoMLine = lines.find((line) => line.startsWith("m=video ")) || "";
        const payloads = videoMLine.split(/\\s+/).slice(3);
        const rtpmap = new Map();
        for (const line of lines) {
          const match = /^a=rtpmap:(\\d+)\\s+([^\\s/]+)\\//i.exec(line);
          if (match) {
            rtpmap.set(match[1], match[2]);
          }
        }
        return {
          mLine: videoMLine,
          payloads,
          codecs: payloads.map((payload) => ({
            payload,
            codec: rtpmap.get(payload) || "",
          })),
          selectedCodec: payloads.length ? (rtpmap.get(payloads[0]) || "") : "",
        };
      }
      function codecKey(codec) {
        return JSON.stringify({
          mimeType: codec && codec.mimeType,
          clockRate: codec && codec.clockRate,
          sdpFmtpLine: (codec && codec.sdpFmtpLine) || "",
        });
      }
      function codecAliases(codecName) {
        const name = String(codecName || "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
        if (!name) {
          return [];
        }
        if (name === "HEVC" || name === "H265") {
          return ["video/h265", "video/hevc"];
        }
        if (name === "H264" || name === "AVC") {
          return ["video/h264", "video/avc"];
        }
        return ["video/" + name.toLowerCase()];
      }
      function preferVideoCodecs(transceiver, codecNames) {
        const requested = Array.isArray(codecNames) ? codecNames.filter(Boolean) : [];
        const result = { requested, applied: false, codecs: [], missing: [] };
        try {
          if (!requested.length || !window.RTCRtpReceiver || !RTCRtpReceiver.getCapabilities || !transceiver.setCodecPreferences) {
            return result;
          }
          const capabilities = RTCRtpReceiver.getCapabilities("video");
          const codecs = capabilities && capabilities.codecs ? capabilities.codecs : [];
          const selected = [];
          const selectedKeys = new Set();
          for (const codecName of requested) {
            const aliases = new Set(codecAliases(codecName));
            const matches = codecs.filter((codec) => aliases.has(String(codec.mimeType || "").toLowerCase()));
            if (!matches.length) {
              result.missing.push(codecName);
              continue;
            }
            for (const codec of matches) {
              const key = codecKey(codec);
              if (!selectedKeys.has(key)) {
                selectedKeys.add(key);
                selected.push(codec);
                result.codecs.push({
                  requested: codecName,
                  mimeType: codec.mimeType,
                  clockRate: codec.clockRate,
                  sdpFmtpLine: codec.sdpFmtpLine || "",
                });
              }
            }
          }
          if (!selected.length) {
            return result;
          }
          const rest = codecs.filter((codec) => !selectedKeys.has(codecKey(codec)));
          transceiver.setCodecPreferences([...selected, ...rest]);
          result.applied = true;
        } catch (error) {
          result.error = String(error);
        }
        return result;
      }
      function applyReceiverPresentationHint(receiver, source) {
        const entry = {
          source,
          receiverPlayoutDelayHint: "unsupported",
          receiverJitterBufferTarget: "unsupported",
          trackContentHint: "unsupported",
          playoutDelayHintApplied: false,
          jitterBufferTargetApplied: false,
          contentHintApplied: false,
        };
        if (!receiver) {
          receiverPresentationHints.push(entry);
          return entry;
        }
        try {
          if ("playoutDelayHint" in receiver) {
            receiver.playoutDelayHint = 0;
            entry.receiverPlayoutDelayHint = receiver.playoutDelayHint;
            entry.playoutDelayHintApplied = receiver.playoutDelayHint === 0;
          }
        } catch (error) {
          entry.playoutDelayHintError = String(error);
        }
        try {
          if ("jitterBufferTarget" in receiver) {
            receiver.jitterBufferTarget = 0;
            entry.receiverJitterBufferTarget = receiver.jitterBufferTarget;
            entry.jitterBufferTargetApplied = receiver.jitterBufferTarget === 0;
          }
        } catch (error) {
          entry.jitterBufferTargetError = String(error);
        }
        try {
          const track = receiver.track;
          if (track && "contentHint" in track) {
            track.contentHint = "motion";
            entry.trackContentHint = track.contentHint;
            entry.contentHintApplied = track.contentHint === "motion";
          }
        } catch (error) {
          entry.contentHintError = String(error);
        }
        receiverPresentationHints.push(entry);
        log({ receiverPresentationHint: entry });
        return entry;
      }
      function applyReceiverPresentationHints(pc, source) {
        const hints = [];
        const seen = new Set();
        const visit = (receiver, itemSource) => {
          if (!receiver || seen.has(receiver)) {
            return;
          }
          seen.add(receiver);
          hints.push(applyReceiverPresentationHint(receiver, itemSource));
        };
        try {
          if (pc.getReceivers) {
            pc.getReceivers().forEach((receiver) => visit(receiver, source + ":receiver"));
          }
        } catch (error) {
          log({ receiverPresentationHintError: String(error), source });
        }
        try {
          if (pc.getTransceivers) {
            pc.getTransceivers().forEach((transceiver) => visit(transceiver.receiver, source + ":transceiver"));
          }
        } catch (error) {
          log({ receiverTransceiverHintError: String(error), source });
        }
        return hints;
      }
      function waitIceComplete(pc, timeoutMs) {
        if (pc.iceGatheringState === "complete") {
          return Promise.resolve();
        }
        return new Promise((resolve) => {
          let done = false;
          const finish = () => {
            if (done) return;
            done = true;
            pc.removeEventListener("icegatheringstatechange", onChange);
            resolve();
          };
          const onChange = () => {
            log("iceGatheringState=" + pc.iceGatheringState);
            if (pc.iceGatheringState === "complete") finish();
          };
          pc.addEventListener("icegatheringstatechange", onChange);
          setTimeout(finish, timeoutMs);
        });
      }
      async function collectStats(pc) {
        const output = {
          inboundRtp: [],
          candidatePairs: [],
          selectedCandidatePairId: "",
        };
        const stats = await pc.getStats();
        stats.forEach((item) => {
          if (item.type === "inbound-rtp" && item.kind === "video") {
            output.inboundRtp.push({
              id: item.id,
              framesDecoded: item.framesDecoded || 0,
              framesReceived: item.framesReceived || 0,
              framesDropped: item.framesDropped || 0,
              framesPerSecond: item.framesPerSecond || 0,
              bytesReceived: item.bytesReceived || 0,
              packetsReceived: item.packetsReceived || 0,
              packetsLost: item.packetsLost || 0,
              jitter: item.jitter || 0,
              jitterBufferDelay: item.jitterBufferDelay || 0,
              jitterBufferEmittedCount: item.jitterBufferEmittedCount || 0,
              jitterBufferTargetDelay: item.jitterBufferTargetDelay || 0,
              totalDecodeTime: item.totalDecodeTime || 0,
              totalProcessingDelay: item.totalProcessingDelay || 0,
              totalInterFrameDelay: item.totalInterFrameDelay || 0,
              totalSquaredInterFrameDelay: item.totalSquaredInterFrameDelay || 0,
              freezeCount: item.freezeCount || 0,
              totalFreezesDuration: item.totalFreezesDuration || 0,
              pauseCount: item.pauseCount || 0,
              totalPausesDuration: item.totalPausesDuration || 0,
              pliCount: item.pliCount || 0,
              nackCount: item.nackCount || 0,
              qpSum: item.qpSum || 0,
              decoderImplementation: item.decoderImplementation || "",
            });
          }
          if (item.type === "transport" && item.selectedCandidatePairId) {
            output.selectedCandidatePairId = item.selectedCandidatePairId;
          }
          if (item.type === "candidate-pair") {
            output.candidatePairs.push({
              id: item.id,
              state: item.state,
              nominated: !!item.nominated,
              selected: !!item.selected,
              bytesReceived: item.bytesReceived || 0,
              bytesSent: item.bytesSent || 0,
            });
          }
        });
        return output;
      }
      async function postResult(result) {
        await fetch("/result", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(result),
        });
      }
      (async () => {
        const timings = {};
        const pc = new RTCPeerConnection({
          iceServers: [],
          bundlePolicy: "max-bundle",
          rtcpMuxPolicy: "require",
        });
        let remoteTrack = false;
        let firstFrame = false;
        let frameCallbacks = 0;
        let inputChannelState = "disabled";
        let moveChannelState = "disabled";
        let inputChannelAck = null;
        const inputChannelAcks = [];
        const inputAckLatencies = [];
        const inputSends = new Map();
        const videoFrameSamples = [];
        const animationFrameSamples = [];
        const presenterDrawSamples = [];
        const touchPhotonSamples = [];
        const pendingTouchPhoton = new Map();
        const markerDrawStatusSamples = [];
        const probeCanvas = document.createElement("canvas");
        const probeCtx = probeCanvas.getContext("2d", { willReadFrequently: true });
        let deviceStatus = null;
        let markerTemplate = null;
        let predictedMarkerGeneration = null;
        let lastMarkerDrawStatusKey = "";
        let nextInputSeq = 1;
        let lastFrameCallbackNowMs = null;
        let lastAnimationFrameNowMs = null;
        let lastPresenterDrawNowMs = null;
        let lastMediaTime = null;
        let lastPresentedFrames = null;
        let lastPresenterMediaTime = null;
        let currentMoveStreamOk = () => !moveStreamTest;
        let currentTouchPhotonOk = () => !touchPhotonTest;
      function startAnimationFrameProbe() {
          if (!("requestAnimationFrame" in window)) {
            return;
          }
          const onAnimationFrame = (now) => {
            const deltaMs = lastAnimationFrameNowMs === null ? null : roundNumber(now - lastAnimationFrameNowMs);
            animationFrameSamples.push({
              t: elapsedMs(),
              nowMs: roundNumber(now),
              deltaMs,
            });
            lastAnimationFrameNowMs = now;
            if (touchPhotonDetectRaf && !canvasPresenterEnabled) {
              detectTouchPhoton(now, "raf");
            }
            if (animationFrameSamples.length < maxAnimationFrameCallbacks) {
              requestAnimationFrame(onAnimationFrame);
            }
          };
          requestAnimationFrame(onAnimationFrame);
        }
        function startCanvasPresenterProbe() {
          if (!canvasPresenterEnabled || !presenterCtx || !("requestAnimationFrame" in window)) {
            return;
          }
          const onPresenterFrame = (now) => {
            if (!video.videoWidth || !video.videoHeight) {
              if (presenterDrawSamples.length < maxPresenterDrawCallbacks) {
                requestAnimationFrame(onPresenterFrame);
              }
              return;
            }
            if (presenterCanvas.width !== video.videoWidth || presenterCanvas.height !== video.videoHeight) {
              presenterCanvas.width = video.videoWidth;
              presenterCanvas.height = video.videoHeight;
            }
            const beforeDraw = performance.now();
            try {
              presenterCtx.drawImage(video, 0, 0, presenterCanvas.width, presenterCanvas.height);
            } catch (error) {
              if (presenterDrawSamples.length < maxPresenterDrawCallbacks) {
                requestAnimationFrame(onPresenterFrame);
              }
              return;
            }
            const afterDraw = performance.now();
            const mediaTime = Number.isFinite(video.currentTime) ? video.currentTime : null;
            const mediaChanged = mediaTime !== null && lastPresenterMediaTime !== null && mediaTime !== lastPresenterMediaTime;
            presenterDrawSamples.push({
              t: elapsedMs(),
              nowMs: roundNumber(now),
              deltaMs: lastPresenterDrawNowMs === null ? null : roundNumber(now - lastPresenterDrawNowMs),
              drawDurationMs: roundNumber(afterDraw - beforeDraw),
              mediaTime,
              mediaDeltaMs: mediaTime === null || lastPresenterMediaTime === null ? null : roundNumber((mediaTime - lastPresenterMediaTime) * 1000),
              mediaChanged,
              videoWidth: video.videoWidth,
              videoHeight: video.videoHeight,
            });
            lastPresenterDrawNowMs = now;
            if (mediaTime !== null) {
              lastPresenterMediaTime = mediaTime;
            }
            if (touchPhotonDetectRaf) {
              detectTouchPhoton(now, "canvas-presenter-raf");
            }
            if (presenterDrawSamples.length < maxPresenterDrawCallbacks) {
              requestAnimationFrame(onPresenterFrame);
            }
          };
          requestAnimationFrame(onPresenterFrame);
        }
        function rememberMarkerStatus(status) {
          const marker = status && status.touchPhotonMarker;
          if (!marker || !marker.region) {
            return;
          }
          markerTemplate = marker;
          const generation = Number(marker.generation);
          if (Number.isFinite(generation)) {
            predictedMarkerGeneration = generation;
          }
        }
        function rememberMarkerDrawStatus(label) {
          const marker = deviceStatus && deviceStatus.touchPhotonMarker;
          const compact = markerDrawStatus(marker);
          if (!compact) {
            return null;
          }
          const sample = Object.assign({ t: elapsedMs(), label: label || "" }, compact);
          const key = markerDrawStatusKey(sample);
          if (label === "initial" || label === "final" || key !== lastMarkerDrawStatusKey) {
            markerDrawStatusSamples.push(sample);
            lastMarkerDrawStatusKey = key;
          }
          return compact;
        }
        async function fetchDeviceStatus(label) {
          try {
            const statusResponse = await fetch("/status", { cache: "no-store" });
            if (!statusResponse.ok) {
              log({ deviceStatusError: "HTTP " + statusResponse.status, label });
              return null;
            }
            deviceStatus = await statusResponse.json();
            rememberMarkerStatus(deviceStatus);
            const markerDrawSync = rememberMarkerDrawStatus(label);
            if (label === "initial" || label === "final") {
              log({
                deviceStatus: {
                  portalVersion: deviceStatus.portalVersion,
                  webrtcLatencyRepair: deviceStatus.webrtcLatencyRepair,
                  markerGeneration: deviceStatus.touchPhotonMarker && deviceStatus.touchPhotonMarker.generation,
                  markerDrawSync,
                },
              });
            }
            return deviceStatus;
          } catch (error) {
            log({ deviceStatusError: String(error), label });
            return null;
          }
        }
        function predictMarker(envelope, label) {
          if (!touchPhotonPredict || !markerTemplate || predictedMarkerGeneration === null) {
            return null;
          }
          predictedMarkerGeneration += 1;
          const color = markerPalette[((predictedMarkerGeneration % markerPalette.length) + markerPalette.length) % markerPalette.length];
          return {
            mode: markerTemplate.mode || "touch-photon-marker",
            supported: markerTemplate.supported !== false,
            predicted: true,
            generation: predictedMarkerGeneration,
            visible: true,
            type: label || envelope.type || "",
            inputX: Number(envelope.x),
            inputY: Number(envelope.y),
            displayWidth: Number(markerTemplate.displayWidth) || 1080,
            displayHeight: Number(markerTemplate.displayHeight) || 2340,
            region: markerTemplate.region,
            color,
          };
        }
        function moveAckInjectedEvents(acks) {
          return (acks || []).filter((ack) => ack && ack.ok === true && (ack.type === "touchMove" || ack.type === "touchMoveBatch"))
            .reduce((total, ack) => {
              const result = ack.result || {};
              const injected = Number(result.injectedEvents);
              return total + Math.max(1, Number.isFinite(injected) ? injected : 1);
            }, 0);
        }
        function moveAckCount(acks) {
          return (acks || []).filter((ack) => ack && ack.ok === true && (ack.type === "touchMove" || ack.type === "touchMoveBatch")).length;
        }
        function trackTouchPhoton(envelope, label) {
          if (!touchPhotonTest || !envelope || envelope.seq === undefined) {
            return;
          }
          const sample = {
            seq: envelope.seq,
            type: label || envelope.type || "",
            sentAtMs: elapsedMs(),
            sentPerfAtMs: performance.now(),
            detected: false,
          };
          const marker = predictMarker(envelope, sample.type);
          if (marker) {
            sample.marker = marker;
            sample.markerPredictedAtMs = elapsedMs();
          }
          touchPhotonSamples.push(sample);
          pendingTouchPhoton.set(String(envelope.seq), sample);
        }
        function attachMarkerFromAck(ack) {
          if (!ack || ack.seq === undefined) return;
          const sample = pendingTouchPhoton.get(String(ack.seq));
          const marker = ack.result && ack.result.marker;
          if (!sample || !marker) return;
          const wasPredicted = sample.marker && sample.marker.predicted === true;
          sample.marker = marker;
          sample.markerAckCorrected = wasPredicted;
          sample.markerAckAtMs = elapsedMs();
        }
        function detectTouchPhoton(now, trigger) {
          const source = canvasPresenterEnabled && presenterCanvas.width > 0 && presenterCanvas.height > 0
            ? presenterCanvas
            : video;
          const sourceWidth = source === presenterCanvas ? presenterCanvas.width : video.videoWidth;
          const sourceHeight = source === presenterCanvas ? presenterCanvas.height : video.videoHeight;
          if (!pendingTouchPhoton.size || !probeCtx || !sourceWidth || !sourceHeight) {
            return;
          }
          for (const [key, sample] of Array.from(pendingTouchPhoton.entries())) {
            if (!sample.marker) continue;
            const region = markerRegion(sample.marker);
            const target = markerTargetColor(sample.marker);
            if (!region || !target) continue;
            const displayWidth = Number(sample.marker.displayWidth) || 1080;
            const displayHeight = Number(sample.marker.displayHeight) || 2340;
            const scaleX = sourceWidth / displayWidth;
            const scaleY = sourceHeight / displayHeight;
            const sx = Math.max(0, Math.min(sourceWidth - 1, Math.round((region.left + region.width * 0.25) * scaleX)));
            const sy = Math.max(0, Math.min(sourceHeight - 1, Math.round((region.top + region.height * 0.25) * scaleY)));
            const sw = Math.max(1, Math.min(sourceWidth - sx, Math.round(region.width * 0.5 * scaleX)));
            const sh = Math.max(1, Math.min(sourceHeight - sy, Math.round(region.height * 0.5 * scaleY)));
            const probeWidth = touchPhotonRoiProbe ? Math.max(2, Math.min(48, sw)) : sourceWidth;
            const probeHeight = touchPhotonRoiProbe ? Math.max(2, Math.min(48, sh)) : sourceHeight;
            let data;
            try {
              if (probeCanvas.width !== probeWidth || probeCanvas.height !== probeHeight) {
                probeCanvas.width = probeWidth;
                probeCanvas.height = probeHeight;
              }
              if (touchPhotonRoiProbe) {
                probeCtx.drawImage(source, sx, sy, sw, sh, 0, 0, probeWidth, probeHeight);
                data = probeCtx.getImageData(0, 0, probeWidth, probeHeight).data;
              } else {
                probeCtx.drawImage(source, 0, 0, probeCanvas.width, probeCanvas.height);
                data = probeCtx.getImageData(sx, sy, sw, sh).data;
              }
            } catch (error) {
              continue;
            }
            let r = 0;
            let g = 0;
            let b = 0;
            let count = 0;
            for (let index = 0; index < data.length; index += 16) {
              r += data[index];
              g += data[index + 1];
              b += data[index + 2];
              count += 1;
            }
            if (!count) continue;
            const avg = { r: r / count, g: g / count, b: b / count };
            const distance = colorDistance(avg, target);
            if (distance <= 120) {
              sample.detected = true;
              sample.detectedAtMs = elapsedMs();
              sample.detectedFrameCallback = frameCallbacks;
              sample.detectedPresenterFrame = presenterDrawSamples.length;
              sample.detectedSource = source === presenterCanvas ? "canvas-presenter" : "video";
              sample.detectedTrigger = trigger || "rvfc";
              sample.probeMode = touchPhotonRoiProbe ? "roi" : "full-frame";
              sample.latencyMs = roundNumber(performance.now() - sample.sentPerfAtMs);
              sample.colorDistance = roundNumber(distance);
              sample.sampledColor = {
                r: roundNumber(avg.r),
                g: roundNumber(avg.g),
                b: roundNumber(avg.b),
              };
              pendingTouchPhoton.delete(key);
              log({ touchPhotonDetected: sample });
            }
          }
        }
        if ("requestVideoFrameCallback" in HTMLVideoElement.prototype) {
          const onFrame = (now, metadata) => {
            firstFrame = true;
            frameCallbacks += 1;
            if (timings.firstFrameAtMs === undefined) {
              timings.firstFrameAtMs = elapsedMs();
            }
            const mediaTime = metadata && Number.isFinite(metadata.mediaTime) ? metadata.mediaTime : null;
            const presentedFrames = metadata && Number.isFinite(metadata.presentedFrames) ? metadata.presentedFrames : null;
            const sample = {
              t: elapsedMs(),
              callbackNowMs: roundNumber(now),
              callbackDeltaMs: lastFrameCallbackNowMs === null ? null : roundNumber(now - lastFrameCallbackNowMs),
              mediaTime,
              mediaDeltaMs: mediaTime === null || lastMediaTime === null ? null : roundNumber((mediaTime - lastMediaTime) * 1000),
              presentedFrames,
              presentedFrameDelta: presentedFrames === null || lastPresentedFrames === null ? null : presentedFrames - lastPresentedFrames,
            };
            if (metadata && Number.isFinite(metadata.expectedDisplayTime)) {
              sample.expectedDisplayTimeMs = roundNumber(metadata.expectedDisplayTime);
            }
            if (metadata && Number.isFinite(metadata.presentationTime)) {
              sample.presentationTimeMs = roundNumber(metadata.presentationTime);
            }
            videoFrameSamples.push(sample);
            lastFrameCallbackNowMs = now;
            if (mediaTime !== null) lastMediaTime = mediaTime;
            if (presentedFrames !== null) lastPresentedFrames = presentedFrames;
            if (!touchPhotonDetectRaf) {
              detectTouchPhoton(now, "rvfc");
            }
            if (frameCallbacks < maxFrameCallbacks) {
              video.requestVideoFrameCallback(onFrame);
            }
          };
          video.requestVideoFrameCallback(onFrame);
        }
        startAnimationFrameProbe();
        startCanvasPresenterProbe();
        await fetchDeviceStatus("initial");
        pc.ontrack = (event) => {
          remoteTrack = true;
          if (timings.firstTrackAtMs === undefined) {
            timings.firstTrackAtMs = elapsedMs();
          }
          applyReceiverPresentationHint(event.receiver, "ontrack");
          const stream = event.streams && event.streams[0] ? event.streams[0] : new MediaStream([event.track]);
          video.srcObject = stream;
          video.play().catch(() => {});
          log({ ontrack: event.track.kind, id: event.track.id });
        };
        pc.onconnectionstatechange = () => {
          if (pc.connectionState === "connected" && timings.connectedAtMs === undefined) {
            timings.connectedAtMs = elapsedMs();
          }
          log("connectionState=" + pc.connectionState);
        };
        pc.oniceconnectionstatechange = () => log("iceConnectionState=" + pc.iceConnectionState);
        pc.onsignalingstatechange = () => log("signalingState=" + pc.signalingState);
        if (inputChannelTest) {
          const inputChannel = pc.createDataChannel("smartisax-input", { ordered: true });
          const moveChannel = pc.createDataChannel("smartisax-input-move", {
            ordered: false,
            maxRetransmits: 1,
          });
          function isMoveInput(payload) {
            return payload && (payload.type === "touchMove" || payload.type === "touchMoveBatch");
          }
          function payloadPointCount(payload) {
            if (!payload) {
              return 0;
            }
            if (payload.type === "touchMoveBatch") {
              return Array.isArray(payload.points) ? payload.points.length : 0;
            }
            return payload.type === "touchMove" ? 1 : 0;
          }
          function payloadLastPoint(payload) {
            if (!payload) {
              return null;
            }
            if (payload.type === "touchMoveBatch" && Array.isArray(payload.points) && payload.points.length) {
              return payload.points[payload.points.length - 1];
            }
            return payload.type === "touchMove" ? payload : null;
          }
          function sendInput(payload) {
            const movePayload = isMoveInput(payload);
            let channel = movePayload && moveChannel.readyState === "open" ? moveChannel : inputChannel;
            if (channel.readyState !== "open") {
              log({
                inputChannel: inputChannel.readyState,
                moveChannel: moveChannel.readyState,
                droppedInput: payload.type || "",
              });
              return null;
            }
            let sendPayload = payload;
            const movePoints = payloadPointCount(sendPayload);
            if (movePayload && channel.bufferedAmount > 8192) {
              const lastPoint = payloadLastPoint(sendPayload);
              if (!lastPoint) {
                log({
                  inputChannel: inputChannel.readyState,
                  moveChannel: moveChannel.readyState,
                  droppedInput: payload.type || "",
                  bufferedAmount: channel.bufferedAmount,
                });
                return null;
              }
              sendPayload = {
                type: "touchMoveBatch",
                points: [{
                  x: lastPoint.x,
                  y: lastPoint.y,
                  t: lastPoint.t || Date.now(),
                }],
                marker: false,
              };
            }
            const seq = payload.seq === undefined ? nextInputSeq++ : payload.seq;
            const sent = {
              seq,
              type: sendPayload.type || "",
              perfAtMs: performance.now(),
              elapsedMs: elapsedMs(),
            };
            const envelope = Object.assign({}, sendPayload, {
              seq,
              ts: Date.now(),
              clientElapsedMs: roundNumber(sent.elapsedMs),
            });
            inputSends.set(String(seq), sent);
            channel.send(JSON.stringify(envelope));
            log({
              inputChannel: inputChannel.readyState,
              moveChannel: moveChannel.readyState,
              sent: envelope.type,
              seq,
              movePoints,
            });
            return envelope;
          }
          function inputAckOk(type) {
            return inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === type);
          }
          function inputAckOkCount(type) {
            return inputChannelAcks.filter((ack) => ack && ack.ok === true && ack.type === type).length;
          }
          currentMoveStreamOk = () => {
            return !moveStreamTest || (
              inputAckOk("touchStart")
              && inputAckOk("touchEnd")
              && moveAckInjectedEvents(inputChannelAcks) >= Math.max(0, moveStreamMoves)
            );
          };
          currentTouchPhotonOk = () => {
            return !touchPhotonTest || touchPhotonSamples.some((sample) => sample.detected === true);
          };
          function scheduleMoveStream(baseDelayMs) {
            const moves = Math.max(0, moveStreamMoves);
            const interval = Math.max(1, moveStreamIntervalMs);
            const batchSize = Math.max(1, moveStreamBatchSize);
            const start = {
              x: gesturePayloads.tap.x,
              y: gesturePayloads.tap.y,
            };
            const end = {
              x: gesturePayloads.swipe.x2,
              y: gesturePayloads.swipe.y2,
            };
            let sentMoves = 0;
            let streamStartedAt = 0;
            let endScheduled = false;
            function pointFor(index) {
              const fraction = moves <= 0 ? 1 : index / moves;
              return {
                x: Math.round(start.x + (end.x - start.x) * fraction),
                y: Math.round(start.y + (end.y - start.y) * fraction),
                t: Date.now(),
              };
            }
            function scheduleFrame(callback) {
              if (typeof requestAnimationFrame === "function") {
                requestAnimationFrame(callback);
              } else {
                setTimeout(callback, 16);
              }
            }
            function pumpMoves() {
              if (sentMoves >= moves) {
                scheduleEnd();
                return;
              }
              const elapsed = performance.now() - streamStartedAt;
              const targetMoves = Math.min(moves, Math.max(sentMoves + 1, Math.floor(elapsed / interval)));
              const points = [];
              while (sentMoves < targetMoves && points.length < batchSize) {
                sentMoves += 1;
                points.push(pointFor(sentMoves));
              }
              if (points.length) {
                sendInput({
                  type: "touchMoveBatch",
                  points,
                  marker: false,
                });
              }
              if (sentMoves < moves) {
                scheduleFrame(pumpMoves);
              } else {
                scheduleEnd();
              }
            }
            function scheduleEnd() {
              if (endScheduled) {
                return;
              }
              endScheduled = true;
              setTimeout(() => {
                const envelope = sendInput({
                  type: "touchEnd",
                  x: end.x,
                  y: end.y,
                  marker: touchPhotonTest,
                });
                if (touchPhotonTest) {
                  trackTouchPhoton(envelope, "touchEnd");
                }
              }, interval);
            }
            setTimeout(() => {
              streamStartedAt = performance.now();
              const envelope = sendInput({
                type: "touchStart",
                x: start.x,
                y: start.y,
                marker: true,
              });
              trackTouchPhoton(envelope, "touchStart");
              scheduleFrame(pumpMoves);
            }, baseDelayMs);
            return (moves + 1) * interval;
          }
          inputChannelState = inputChannel.readyState;
          moveChannelState = moveChannel.readyState;
          inputChannel.onopen = () => {
            inputChannelState = inputChannel.readyState;
            if (timings.inputChannelOpenAtMs === undefined) {
              timings.inputChannelOpenAtMs = elapsedMs();
            }
            for (let index = 0; index < Math.max(0, inputPingCount); index += 1) {
              setTimeout(() => {
                if (inputChannel.readyState === "open") {
                  sendInput({ type: "ping" });
                }
              }, index * inputPingIntervalMs);
            }
            let gestureDelayMs = Math.max(120, Math.max(0, inputPingCount) * inputPingIntervalMs + 120);
            if (moveStreamTest) {
              const moveDurationMs = scheduleMoveStream(gestureDelayMs);
              gestureDelayMs += moveDurationMs + 180;
            }
            if (inputGestureTest) {
              setTimeout(() => {
                sendInput({
                  type: "tap",
                  x: gesturePayloads.tap.x,
                  y: gesturePayloads.tap.y,
                });
                log({ inputChannel: inputChannelState, sent: "tap", point: gesturePayloads.tap });
              }, gestureDelayMs);
              setTimeout(() => {
                sendInput({
                  type: "swipe",
                  x1: gesturePayloads.swipe.x1,
                  y1: gesturePayloads.swipe.y1,
                  x2: gesturePayloads.swipe.x2,
                  y2: gesturePayloads.swipe.y2,
                  duration: gesturePayloads.swipe.duration,
                });
                log({ inputChannel: inputChannelState, sent: "swipe", path: gesturePayloads.swipe });
              }, gestureDelayMs + 140);
            }
          };
          inputChannel.onclose = () => {
            inputChannelState = inputChannel.readyState;
            log({ inputChannel: inputChannelState });
          };
          inputChannel.onerror = () => {
            inputChannelState = inputChannel.readyState;
            log({ inputChannel: inputChannelState, error: true });
          };
          moveChannel.onopen = () => {
            moveChannelState = moveChannel.readyState;
            log({ moveChannel: moveChannelState });
          };
          moveChannel.onclose = () => {
            moveChannelState = moveChannel.readyState;
            log({ moveChannel: moveChannelState });
          };
          moveChannel.onerror = () => {
            moveChannelState = moveChannel.readyState;
            log({ moveChannel: moveChannelState, error: true });
          };
          function handleInputAck(event) {
            const receivedPerfAtMs = performance.now();
            const receivedElapsedMs = elapsedMs();
            try {
              inputChannelAck = JSON.parse(event.data);
            } catch (error) {
              inputChannelAck = { ok: false, raw: String(event.data), error: String(error) };
            }
            const sent = inputChannelAck && inputChannelAck.seq !== undefined
              ? inputSends.get(String(inputChannelAck.seq))
              : null;
            if (sent) {
              const latencySample = {
                seq: inputChannelAck.seq,
                type: inputChannelAck.type || sent.type,
                ok: inputChannelAck.ok === true,
                sentAtMs: roundNumber(sent.elapsedMs),
                receivedAtMs: roundNumber(receivedElapsedMs),
                latencyMs: roundNumber(receivedPerfAtMs - sent.perfAtMs),
              };
              inputAckLatencies.push(latencySample);
              inputChannelAck.clientAckLatencyMs = latencySample.latencyMs;
              inputChannelAck.clientSentAtMs = latencySample.sentAtMs;
              inputChannelAck.clientReceivedAtMs = latencySample.receivedAtMs;
            }
            inputChannelAcks.push(inputChannelAck);
            attachMarkerFromAck(inputChannelAck);
            if (inputChannelAck && (inputChannelAck.type === "touchMove" || inputChannelAck.type === "touchMoveBatch") && inputChannelAck.ok === true) {
              log({ inputChannelAck: {
                type: inputChannelAck.type,
                seq: inputChannelAck.seq,
                ok: true,
                injectedEvents: inputChannelAck.result && inputChannelAck.result.injectedEvents,
              } });
            } else {
              log({ inputChannelAck });
            }
          }
          inputChannel.onmessage = handleInputAck;
          moveChannel.onmessage = handleInputAck;
        }
        const transceiver = pc.addTransceiver("video", { direction: "recvonly" });
        applyReceiverPresentationHint(transceiver.receiver, "recvonly-transceiver");
        const codecPreference = preferVideoCodecs(transceiver, preferCodecs);
        log({ codecPreference });
        const offer = await pc.createOffer();
        timings.offerCreatedAtMs = elapsedMs();
        await pc.setLocalDescription(offer);
        timings.localDescriptionSetAtMs = elapsedMs();
        await waitIceComplete(pc, 5000);
        timings.iceGatheringCompleteAtMs = elapsedMs();
        const local = pc.localDescription || offer;
        const localVideoSdp = codecSummary(local.sdp);
        log({ localType: local.type, localSdpBytes: local.sdp.length, hasCandidate: /a=candidate:/i.test(local.sdp), localVideoSdp });
        timings.offerPostStartedAtMs = elapsedMs();
        const offerResponse = await fetch("/offer", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ type: local.type, sdp: local.sdp, browser: { userAgent: navigator.userAgent } }),
        });
        const answer = await offerResponse.json();
        timings.answerReceivedAtMs = elapsedMs();
        const answerVideoSdp = answer.answer && answer.answer.sdp ? codecSummary(answer.answer.sdp) : {};
        log({ answerOk: answer.ok, mode: answer.mode, answerSdpBytes: answer.answer && answer.answer.sdp ? answer.answer.sdp.length : 0, answerVideoSdp, error: answer.error || "" });
        if (!answer.ok || !answer.answer || !answer.answer.sdp) {
          throw new Error("device did not return WebRTC answer: " + JSON.stringify(answer));
        }
        await pc.setRemoteDescription(answer.answer);
        timings.remoteDescriptionSetAtMs = elapsedMs();
        applyReceiverPresentationHints(pc, "remote-description");
        const deadline = Date.now() + 16000;
        while (Date.now() < deadline) {
          const stats = await collectStats(pc);
          const decoded = stats.inboundRtp.reduce((sum, item) => sum + (item.framesDecoded || 0), 0);
          const gestureOk = !inputGestureTest || (
            inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "tap")
            && inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "swipe")
          );
          const inputOk = !inputChannelTest || ((inputChannelAck && inputChannelAck.ok === true) && gestureOk);
          const moveStreamOk = !inputChannelTest || currentMoveStreamOk();
          const touchPhotonOk = !inputChannelTest || currentTouchPhotonOk();
          if (pc.connectionState === "connected" && (remoteTrack || decoded > 0 || firstFrame) && inputOk && moveStreamOk && touchPhotonOk) {
            break;
          }
          await wait(500);
        }
        const statsTimeline = [];
        if (observeMs > 0) {
          const observeUntil = Date.now() + observeMs;
          while (Date.now() < observeUntil) {
            await fetchDeviceStatus("timeline");
            const sample = await collectStats(pc);
            statsTimeline.push({
              t: Date.now() - startedAt,
              connectionState: pc.connectionState,
              iceConnectionState: pc.iceConnectionState,
              videoWidth: video.videoWidth,
              videoHeight: video.videoHeight,
              frameCallbacks,
              animationFrameCallbacks: animationFrameSamples.length,
              presenterDrawCallbacks: presenterDrawSamples.length,
              presenterCanvasWidth: presenterCanvas.width || 0,
              presenterCanvasHeight: presenterCanvas.height || 0,
              pageState: currentPageState(),
              rvfcLastGapMs: videoFrameSamples.length ? videoFrameSamples[videoFrameSamples.length - 1].callbackDeltaMs : null,
              rafLastGapMs: animationFrameSamples.length ? animationFrameSamples[animationFrameSamples.length - 1].deltaMs : null,
              rvfcGapsOver34ms: countFieldOver(videoFrameSamples, "callbackDeltaMs", 34),
              rafGapsOver34ms: countFieldOver(animationFrameSamples, "deltaMs", 34),
              rvfcMaxGapMs: maxField(videoFrameSamples, "callbackDeltaMs"),
              rafMaxGapMs: maxField(animationFrameSamples, "deltaMs"),
              markerDrawSync: markerDrawStatus(deviceStatus && deviceStatus.touchPhotonMarker),
              framesDecoded: sample.inboundRtp.reduce((sum, item) => sum + (item.framesDecoded || 0), 0),
              bytesReceived: sample.inboundRtp.reduce((sum, item) => sum + (item.bytesReceived || 0), 0),
              packetsReceived: sample.inboundRtp.reduce((sum, item) => sum + (item.packetsReceived || 0), 0),
              packetsLost: sample.inboundRtp.reduce((sum, item) => sum + (item.packetsLost || 0), 0),
              framesDropped: sample.inboundRtp.reduce((sum, item) => sum + (item.framesDropped || 0), 0),
              jitterBufferDelay: roundNumber(sample.inboundRtp.reduce((sum, item) => sum + (item.jitterBufferDelay || 0), 0)),
              jitterBufferTargetDelay: roundNumber(sample.inboundRtp.reduce((sum, item) => sum + (item.jitterBufferTargetDelay || 0), 0)),
              jitterBufferEmittedCount: sample.inboundRtp.reduce((sum, item) => sum + (item.jitterBufferEmittedCount || 0), 0),
              freezeCount: sample.inboundRtp.reduce((sum, item) => sum + (item.freezeCount || 0), 0),
            });
            await wait(Math.max(100, statsIntervalMs));
          }
        }
        await fetchDeviceStatus("final");
        const stats = await collectStats(pc);
        const decoded = stats.inboundRtp.reduce((sum, item) => sum + (item.framesDecoded || 0), 0);
        const bytesReceived = stats.inboundRtp.reduce((sum, item) => sum + (item.bytesReceived || 0), 0);
        const mediaOk = pc.connectionState === "connected" && (remoteTrack || decoded > 0 || firstFrame);
        const inputGestureOk = !inputGestureTest || (
          inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "tap")
          && inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "swipe")
        );
        const moveStreamOk = currentMoveStreamOk();
        const touchPhotonOk = currentTouchPhotonOk();
        const inputOk = !inputChannelTest || ((inputChannelAck && inputChannelAck.ok === true) && inputGestureOk && moveStreamOk && touchPhotonOk);
        const touchPhotonSummary = summarizeTouchPhoton(touchPhotonSamples);
        const markerDrawSyncSummary = summarizeMarkerDrawSync(markerDrawStatusSamples, deviceStatus && deviceStatus.touchPhotonMarker);
        const latencyMetrics = {
          timings,
          videoFrame: summarizeVideoFrames(videoFrameSamples, "requestVideoFrameCallback" in HTMLVideoElement.prototype),
          animationFrame: summarizeAnimationFrames(animationFrameSamples, "requestAnimationFrame" in window),
          canvasPresenter: summarizeCanvasPresenter(presenterDrawSamples, !!presenterCtx, presenterMode),
          input: summarizeInputLatency(inputAckLatencies),
          touchPhoton: touchPhotonSummary,
          markerDrawSync: markerDrawSyncSummary,
        };
        const result = {
          ok: mediaOk && inputOk,
          connectionState: pc.connectionState,
          iceConnectionState: pc.iceConnectionState,
          iceGatheringState: pc.iceGatheringState,
          signalingState: pc.signalingState,
          remoteTrack,
          firstFrame,
          quietPresentation,
          presenterMode,
          canvasPresenterEnabled,
          touchPhotonDetectRaf,
          touchPhotonRoiProbe,
          rvfcPresentationCadence: "rvfc-presentation-cadence-lite+marker-visible-tail-presentation-cadence",
          rvfcCadenceLite,
          frameCallbacks,
          animationFrameCallbacks: animationFrameSamples.length,
          presenterDrawCallbacks: presenterDrawSamples.length,
          presenterCanvasWidth: presenterCanvas.width || 0,
          presenterCanvasHeight: presenterCanvas.height || 0,
          videoWidth: video.videoWidth,
          videoHeight: video.videoHeight,
          framesDecoded: decoded,
          bytesReceived,
          inputChannelTest,
          inputGestureTest,
          inputLatencyTest,
          touchPhotonTest,
          moveStreamTest,
          moveStreamMoves,
          moveStreamIntervalMs,
          moveStreamBatchSize,
          moveStreamInjectedEvents: moveAckInjectedEvents(inputChannelAcks),
          moveStreamAckCount: moveAckCount(inputChannelAcks),
          inputPingCount,
          inputPingIntervalMs,
          inputChannelState,
          moveChannelState,
          inputChannelAck,
          inputChannelAcks,
          inputAckLatencies,
          inputGestureOk,
          moveStreamOk,
          touchPhotonOk,
          touchPhotonSamples,
          touchPhotonSummary,
          markerDrawSyncSummary,
          latencyMetrics,
          pageState: currentPageState(),
          pageLifecycleEvents,
          codecPreference,
          localVideoSdp,
          answerVideoSdp,
          selectedCodec: answerVideoSdp.selectedCodec || "",
          receiverPresentationHints,
          stats,
          statsTimeline,
          deviceAnswer: {
            ok: answer.ok,
            mode: answer.mode,
            nativeWebRtcRuntime: answer.nativeWebRtcRuntime,
            dtlsSrtp: answer.dtlsSrtp,
            srtp: answer.srtp,
            ice: answer.ice,
            localCandidateCount: answer.localCandidateCount,
            elapsedMs: answer.elapsedMs,
            framePump: answer.framePump,
            answerSdpBytes: answer.answer.sdp.length,
            answerHasCandidate: /a=candidate:/i.test(answer.answer.sdp),
            answerHasFingerprint: /a=fingerprint:/i.test(answer.answer.sdp),
            answerHasSetup: /a=setup:/i.test(answer.answer.sdp),
          },
          deviceStatus: deviceStatus ? {
            portalVersion: deviceStatus.portalVersion,
            variant: deviceStatus.variant,
            webrtcCodec: deviceStatus.webrtcCodec,
            webrtcCodecPolicy: deviceStatus.webrtcCodecPolicy,
            webrtcCodecFallback: deviceStatus.webrtcCodecFallback,
            webrtcLatencyRepair: deviceStatus.webrtcLatencyRepair,
            webrtcAckJitterRepair: deviceStatus.webrtcAckJitterRepair,
            chromePresentationGapRepair: deviceStatus.chromePresentationGapRepair,
            touchPhotonMarker: deviceStatus.touchPhotonMarker,
          } : null,
          events,
          elapsedMs: Date.now() - startedAt,
          userAgent: navigator.userAgent,
        };
        await postResult(result);
      })().catch(async (error) => {
        await postResult({
          ok: false,
          error: String(error && error.stack ? error.stack : error),
          events,
          elapsedMs: Date.now() - startedAt,
          userAgent: navigator.userAgent,
        });
      });
    </script>
  </body>
</html>`;

await writeFile(htmlPath, html, "utf8");

const server = createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/") {
      response.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
      response.end(html);
      return;
    }
    if (request.method === "POST" && request.url === "/offer") {
      const body = await readBody(request);
      const upstream = await fetch(`${portalUrl}/api/webrtc/offer`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
        },
        body,
      });
      const text = await upstream.text();
      response.writeHead(upstream.status, { "content-type": upstream.headers.get("content-type") || "application/json" });
      response.end(text);
      return;
    }
    if (request.method === "GET" && request.url === "/status") {
      const upstream = await fetch(`${portalUrl}/api/status`, {
        method: "GET",
        headers: {
          authorization: `Bearer ${token}`,
        },
      });
      const text = await upstream.text();
      response.writeHead(upstream.status, { "content-type": upstream.headers.get("content-type") || "application/json" });
      response.end(text);
      return;
    }
    if (request.method === "POST" && request.url === "/result") {
      const body = await readBody(request);
      const parsed = JSON.parse(body);
      resultResolve(parsed);
      response.writeHead(204);
      response.end();
      return;
    }
    response.writeHead(404);
    response.end("not found");
  } catch (error) {
    resultReject(error);
    response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    response.end(String(error && error.stack ? error.stack : error));
  }
});

function readBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => resolve(body));
    request.on("error", reject);
  });
}

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const { port } = server.address();
const userDataDir = join(tmpdir(), `smartisax-chrome-v0portal5a-${Date.now()}`);
const chromeArgs = [
  `--user-data-dir=${userDataDir}`,
  "--no-first-run",
  "--no-default-browser-check",
  "--disable-webrtc-hide-local-ips-with-mdns",
  "--autoplay-policy=no-user-gesture-required",
  "--enable-logging=stderr",
  "--v=0",
];
if (chromeAntiThrottle) {
  chromeArgs.push(
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-features=CalculateNativeWinOcclusion,IntensiveWakeUpThrottling,BackForwardCache",
  );
}
if (chromeWindowSize) {
  chromeArgs.push(`--window-size=${chromeWindowSize}`);
}
if (chromeForceDeviceScaleFactor) {
  chromeArgs.push(`--force-device-scale-factor=${chromeForceDeviceScaleFactor}`);
}
chromeArgs.push("--new-window");
chromeArgs.push(`http://127.0.0.1:${port}/`);

const chrome = spawn(chromePath, chromeArgs, { stdio: "ignore" });
if (chromeForeground && process.platform === "darwin") {
  setTimeout(() => {
    try {
      const focus = spawn("/usr/bin/osascript", ["-e", 'tell application "Google Chrome" to activate'], {
        stdio: "ignore",
      });
      focus.unref();
    } catch {
    }
  }, 750).unref();
}
let timeout;
try {
  const timed = Promise.race([
    resultPromise,
    new Promise((_, reject) => {
      timeout = setTimeout(() => reject(new Error(`Chrome WebRTC smoke timed out after ${timeoutMs}ms`)), timeoutMs);
    }),
  ]);
  const result = await timed;
  clearTimeout(timeout);
  result.report = reportPath;
  result.html = htmlPath;
  result.portalUrl = portalUrl;
  result.tokenRedacted = true;
  result.chromeLaunch = {
    antiThrottle: chromeAntiThrottle,
    foreground: chromeForeground,
    windowSize: chromeWindowSize,
    forceDeviceScaleFactor: chromeForceDeviceScaleFactor,
    flags: chromeArgs.filter((item) => item.startsWith("--")),
  };
  await writeFile(reportPath, JSON.stringify(result, null, 2), "utf8");
  console.log(JSON.stringify({
    ok: result.ok,
    connectionState: result.connectionState,
    iceConnectionState: result.iceConnectionState,
    remoteTrack: result.remoteTrack,
    firstFrame: result.firstFrame,
    framesDecoded: result.framesDecoded,
    bytesReceived: result.bytesReceived,
    inputChannelTest: result.inputChannelTest,
    inputGestureTest: result.inputGestureTest,
    inputLatencyTest: result.inputLatencyTest,
    touchPhotonTest: result.touchPhotonTest,
    touchPhotonDetectRaf: result.touchPhotonDetectRaf,
    touchPhotonRoiProbe: result.touchPhotonRoiProbe,
    moveStreamTest: result.moveStreamTest,
    moveStreamBatchSize: result.moveStreamBatchSize,
    moveStreamInjectedEvents: result.moveStreamInjectedEvents,
    moveStreamAckCount: result.moveStreamAckCount,
    inputChannelState: result.inputChannelState,
    moveChannelState: result.moveChannelState,
    inputChannelAck: result.inputChannelAck,
    inputGestureOk: result.inputGestureOk,
    moveStreamOk: result.moveStreamOk,
    touchPhotonOk: result.touchPhotonOk,
    latencyMetrics: {
      timings: result.latencyMetrics && result.latencyMetrics.timings,
      videoFrame: result.latencyMetrics && result.latencyMetrics.videoFrame,
      input: result.latencyMetrics && result.latencyMetrics.input ? {
        sampleCount: result.latencyMetrics.input.sampleCount,
        all: result.latencyMetrics.input.all,
        byType: result.latencyMetrics.input.byType,
      } : undefined,
      touchPhoton: result.latencyMetrics && result.latencyMetrics.touchPhoton ? {
        sampleCount: result.latencyMetrics.touchPhoton.sampleCount,
        detectedCount: result.latencyMetrics.touchPhoton.detectedCount,
        latencyMs: result.latencyMetrics.touchPhoton.latencyMs,
      } : undefined,
      markerDrawSync: result.latencyMetrics && result.latencyMetrics.markerDrawSync ? {
        supported: result.latencyMetrics.markerDrawSync.supported,
        drawSync: result.latencyMetrics.markerDrawSync.drawSync,
        sampleCount: result.latencyMetrics.markerDrawSync.sampleCount,
        mode: result.latencyMetrics.markerDrawSync.mode,
        latest: result.latencyMetrics.markerDrawSync.latest,
        drawLatencyMs: result.latencyMetrics.markerDrawSync.drawLatencyMs,
      } : undefined,
    },
    deviceAnswer: result.deviceAnswer,
    report: reportPath,
  }, null, 2));
  process.exitCode = result.ok ? 0 : 1;
} catch (error) {
  clearTimeout(timeout);
  const result = {
    ok: false,
    error: String(error && error.stack ? error.stack : error),
    report: reportPath,
    html: htmlPath,
    portalUrl,
    tokenRedacted: true,
    chromeLaunch: {
      antiThrottle: chromeAntiThrottle,
      foreground: chromeForeground,
      windowSize: chromeWindowSize,
      forceDeviceScaleFactor: chromeForceDeviceScaleFactor,
      flags: chromeArgs.filter((item) => item.startsWith("--")),
    },
  };
  await writeFile(reportPath, JSON.stringify(result, null, 2), "utf8");
  console.error(JSON.stringify(result, null, 2));
  process.exitCode = 1;
} finally {
  server.close();
  try {
    chrome.kill("SIGTERM");
  } catch {
  }
  setTimeout(() => {
    try {
      chrome.kill("SIGKILL");
    } catch {
    }
  }, 1000).unref();
  await rm(userDataDir, { recursive: true, force: true }).catch(() => {});
}
