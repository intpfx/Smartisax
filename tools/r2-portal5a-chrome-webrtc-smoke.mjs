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
const preferCodec = args.get("--prefer-codec") || "";
const inputGestureTest = args.has("--input-gesture-test");
const inputChannelTest = args.has("--input-channel-test") || inputGestureTest;
const tapX = Number(args.get("--tap-x") || "540");
const tapY = Number(args.get("--tap-y") || "1170");
const swipeX1 = Number(args.get("--swipe-x1") || "540");
const swipeY1 = Number(args.get("--swipe-y1") || "1300");
const swipeX2 = Number(args.get("--swipe-x2") || "540");
const swipeY2 = Number(args.get("--swipe-y2") || "900");
const chromePath = args.get("--chrome")
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

if (!portalUrl || !token) {
  console.error("Usage: tools/r2-portal5a-chrome-webrtc-smoke.mjs --url http://<r2-ip>:37601 --token <token> [--variant v0.portal5b-native-webrtc-system-libs]");
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
      video { width: 360px; max-width: 100%; background: #111; }
      pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    </style>
  </head>
  <body>
    <h1>Smartisax ${variant} Chrome WebRTC Smoke</h1>
    <video id="video" autoplay playsinline muted></video>
    <pre id="log">starting</pre>
    <script>
      const logNode = document.querySelector("#log");
      const video = document.querySelector("#video");
      const events = [];
      const startedAt = Date.now();
      function log(value) {
        const line = typeof value === "string" ? value : JSON.stringify(value);
        events.push({ t: Date.now() - startedAt, value });
        logNode.textContent = events.map((entry) => entry.t + "ms " + (typeof entry.value === "string" ? entry.value : JSON.stringify(entry.value))).join("\\n");
      }
      function wait(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
      }
      const observeMs = ${JSON.stringify(observeMs)};
      const preferCodec = ${JSON.stringify(preferCodec)};
      const inputChannelTest = ${JSON.stringify(inputChannelTest)};
      const inputGestureTest = ${JSON.stringify(inputGestureTest)};
      const gesturePayloads = ${JSON.stringify({
        tap: { x: tapX, y: tapY },
        swipe: { x1: swipeX1, y1: swipeY1, x2: swipeX2, y2: swipeY2, duration: 180 },
      })};
      const maxFrameCallbacks = observeMs > 0 ? 10000 : 3;
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
              bytesReceived: item.bytesReceived || 0,
              packetsReceived: item.packetsReceived || 0,
              packetsLost: item.packetsLost || 0,
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
        const pc = new RTCPeerConnection({
          iceServers: [],
          bundlePolicy: "max-bundle",
          rtcpMuxPolicy: "require",
        });
        let remoteTrack = false;
        let firstFrame = false;
        let frameCallbacks = 0;
        let inputChannelState = "disabled";
        let inputChannelAck = null;
        const inputChannelAcks = [];
        if ("requestVideoFrameCallback" in HTMLVideoElement.prototype) {
          const onFrame = () => {
            firstFrame = true;
            frameCallbacks += 1;
            if (frameCallbacks < maxFrameCallbacks) {
              video.requestVideoFrameCallback(onFrame);
            }
          };
          video.requestVideoFrameCallback(onFrame);
        }
        pc.ontrack = (event) => {
          remoteTrack = true;
          const stream = event.streams && event.streams[0] ? event.streams[0] : new MediaStream([event.track]);
          video.srcObject = stream;
          video.play().catch(() => {});
          log({ ontrack: event.track.kind, id: event.track.id });
        };
        pc.onconnectionstatechange = () => log("connectionState=" + pc.connectionState);
        pc.oniceconnectionstatechange = () => log("iceConnectionState=" + pc.iceConnectionState);
        pc.onsignalingstatechange = () => log("signalingState=" + pc.signalingState);
        if (inputChannelTest) {
          const inputChannel = pc.createDataChannel("smartisax-input", { ordered: true });
          inputChannelState = inputChannel.readyState;
          inputChannel.onopen = () => {
            inputChannelState = inputChannel.readyState;
            inputChannel.send(JSON.stringify({ type: "ping", seq: 1, ts: Date.now() }));
            log({ inputChannel: inputChannelState, sent: "ping" });
            if (inputGestureTest) {
              setTimeout(() => {
                inputChannel.send(JSON.stringify({
                  type: "tap",
                  seq: 2,
                  ts: Date.now(),
                  x: gesturePayloads.tap.x,
                  y: gesturePayloads.tap.y,
                }));
                log({ inputChannel: inputChannelState, sent: "tap", point: gesturePayloads.tap });
              }, 120);
              setTimeout(() => {
                inputChannel.send(JSON.stringify({
                  type: "swipe",
                  seq: 3,
                  ts: Date.now(),
                  x1: gesturePayloads.swipe.x1,
                  y1: gesturePayloads.swipe.y1,
                  x2: gesturePayloads.swipe.x2,
                  y2: gesturePayloads.swipe.y2,
                  duration: gesturePayloads.swipe.duration,
                }));
                log({ inputChannel: inputChannelState, sent: "swipe", path: gesturePayloads.swipe });
              }, 260);
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
          inputChannel.onmessage = (event) => {
            try {
              inputChannelAck = JSON.parse(event.data);
            } catch (error) {
              inputChannelAck = { ok: false, raw: String(event.data), error: String(error) };
            }
            inputChannelAcks.push(inputChannelAck);
            log({ inputChannelAck });
          };
        }
        const transceiver = pc.addTransceiver("video", { direction: "recvonly" });
        let codecPreference = { requested: preferCodec, applied: false, codecs: [] };
        if (preferCodec && window.RTCRtpReceiver && RTCRtpReceiver.getCapabilities && transceiver.setCodecPreferences) {
          const capabilities = RTCRtpReceiver.getCapabilities("video");
          const codecs = capabilities && capabilities.codecs ? capabilities.codecs : [];
          const wanted = codecs.filter((codec) => {
            const mime = String(codec.mimeType || "").toLowerCase();
            return mime === ("video/" + preferCodec).toLowerCase();
          });
          if (wanted.length) {
            const wantedKeys = new Set(wanted.map((codec) => JSON.stringify({
              mimeType: codec.mimeType,
              clockRate: codec.clockRate,
              sdpFmtpLine: codec.sdpFmtpLine || "",
            })));
            const rest = codecs.filter((codec) => !wantedKeys.has(JSON.stringify({
              mimeType: codec.mimeType,
              clockRate: codec.clockRate,
              sdpFmtpLine: codec.sdpFmtpLine || "",
            })));
            transceiver.setCodecPreferences([...wanted, ...rest]);
            codecPreference = {
              requested: preferCodec,
              applied: true,
              codecs: wanted.map((codec) => ({
                mimeType: codec.mimeType,
                clockRate: codec.clockRate,
                sdpFmtpLine: codec.sdpFmtpLine || "",
              })),
            };
          }
        }
        log({ codecPreference });
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await waitIceComplete(pc, 5000);
        const local = pc.localDescription || offer;
        const localVideoSdp = codecSummary(local.sdp);
        log({ localType: local.type, localSdpBytes: local.sdp.length, hasCandidate: /a=candidate:/i.test(local.sdp), localVideoSdp });
        const offerResponse = await fetch("/offer", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ type: local.type, sdp: local.sdp, browser: { userAgent: navigator.userAgent } }),
        });
        const answer = await offerResponse.json();
        const answerVideoSdp = answer.answer && answer.answer.sdp ? codecSummary(answer.answer.sdp) : {};
        log({ answerOk: answer.ok, mode: answer.mode, answerSdpBytes: answer.answer && answer.answer.sdp ? answer.answer.sdp.length : 0, answerVideoSdp, error: answer.error || "" });
        if (!answer.ok || !answer.answer || !answer.answer.sdp) {
          throw new Error("device did not return WebRTC answer: " + JSON.stringify(answer));
        }
        await pc.setRemoteDescription(answer.answer);
        const deadline = Date.now() + 16000;
        while (Date.now() < deadline) {
          const stats = await collectStats(pc);
          const decoded = stats.inboundRtp.reduce((sum, item) => sum + (item.framesDecoded || 0), 0);
          const gestureOk = !inputGestureTest || (
            inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "tap")
            && inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "swipe")
          );
          const inputOk = !inputChannelTest || ((inputChannelAck && inputChannelAck.ok === true) && gestureOk);
          if (pc.connectionState === "connected" && (remoteTrack || decoded > 0 || firstFrame) && inputOk) {
            break;
          }
          await wait(500);
        }
        const statsTimeline = [];
        if (observeMs > 0) {
          const observeUntil = Date.now() + observeMs;
          while (Date.now() < observeUntil) {
            const sample = await collectStats(pc);
            statsTimeline.push({
              t: Date.now() - startedAt,
              connectionState: pc.connectionState,
              iceConnectionState: pc.iceConnectionState,
              videoWidth: video.videoWidth,
              videoHeight: video.videoHeight,
              frameCallbacks,
              framesDecoded: sample.inboundRtp.reduce((sum, item) => sum + (item.framesDecoded || 0), 0),
              bytesReceived: sample.inboundRtp.reduce((sum, item) => sum + (item.bytesReceived || 0), 0),
              packetsReceived: sample.inboundRtp.reduce((sum, item) => sum + (item.packetsReceived || 0), 0),
              packetsLost: sample.inboundRtp.reduce((sum, item) => sum + (item.packetsLost || 0), 0),
            });
            await wait(1000);
          }
        }
        const stats = await collectStats(pc);
        const decoded = stats.inboundRtp.reduce((sum, item) => sum + (item.framesDecoded || 0), 0);
        const bytesReceived = stats.inboundRtp.reduce((sum, item) => sum + (item.bytesReceived || 0), 0);
        const mediaOk = pc.connectionState === "connected" && (remoteTrack || decoded > 0 || firstFrame);
        const inputGestureOk = !inputGestureTest || (
          inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "tap")
          && inputChannelAcks.some((ack) => ack && ack.ok === true && ack.type === "swipe")
        );
        const inputOk = !inputChannelTest || ((inputChannelAck && inputChannelAck.ok === true) && inputGestureOk);
        const result = {
          ok: mediaOk && inputOk,
          connectionState: pc.connectionState,
          iceConnectionState: pc.iceConnectionState,
          iceGatheringState: pc.iceGatheringState,
          signalingState: pc.signalingState,
          remoteTrack,
          firstFrame,
          frameCallbacks,
          videoWidth: video.videoWidth,
          videoHeight: video.videoHeight,
          framesDecoded: decoded,
          bytesReceived,
          inputChannelTest,
          inputGestureTest,
          inputChannelState,
          inputChannelAck,
          inputChannelAcks,
          inputGestureOk,
          codecPreference,
          localVideoSdp,
          answerVideoSdp,
          selectedCodec: answerVideoSdp.selectedCodec || "",
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
  `http://127.0.0.1:${port}/`,
];

const chrome = spawn(chromePath, chromeArgs, { stdio: "ignore" });
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
    inputChannelState: result.inputChannelState,
    inputChannelAck: result.inputChannelAck,
    inputGestureOk: result.inputGestureOk,
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
