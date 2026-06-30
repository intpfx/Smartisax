#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:net";

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

const portalUrl = (args.get("--url") || "http://192.168.31.103:37601").replace(/\/$/, "");
const code = args.get("--code") || "";
const variant = args.get("--variant") || "v0.portal6c-visible-screenbox";
const variantSlug = variant.replace(/[^A-Za-z0-9_.-]/g, "_");
const outDir = args.get("--out-dir") || `hard-rom/inspect/${variant}/portal-real-ui-visual-smoke-live`;
const timeoutMs = Number(args.get("--timeout-ms") || "45000");
const observeMs = Number(args.get("--observe-ms") || "5000");
const pollMs = Number(args.get("--poll-ms") || "750");
const chromePath = args.get("--chrome")
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const keepProfile = args.has("--keep-profile");
const chromeWindowSize = args.get("--chrome-window-size") || "720,1480";
const deviceScaleFactor = args.get("--chrome-force-device-scale-factor") || "1";
const presenterMode = args.get("--presenter") || "video";

if (!code) {
  console.error("Usage: tools/r2-portal6c-real-portal-visual-smoke.mjs --code <pairing-code> [--url http://<r2-ip>:37601]");
  process.exit(2);
}

function stamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "").replace("T", "-");
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getFreePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : 0;
      server.close(() => resolve(port));
    });
  });
}

async function fetchJson(url, timeout = 1000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`);
    }
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function pollDevTools(port, deadline) {
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const pages = await fetchJson(`http://127.0.0.1:${port}/json/list`, 1000);
      const page = pages.find((item) => item.type === "page" && item.webSocketDebuggerUrl)
        || pages.find((item) => item.webSocketDebuggerUrl);
      if (page) {
        return page;
      }
    } catch (error) {
      lastError = error;
    }
    await wait(250);
  }
  throw new Error(`Chrome DevTools endpoint did not become ready: ${lastError || "timeout"}`);
}

function connectCdp(wsUrl) {
  const socket = new WebSocket(wsUrl);
  let nextId = 1;
  const pending = new Map();
  const events = [];

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        reject(new Error(`${message.error.message || "CDP error"} ${message.error.data || ""}`.trim()));
      } else {
        resolve(message.result || {});
      }
      return;
    }
    if (message.method) {
      events.push({
        t: Date.now(),
        method: message.method,
        params: message.params || {},
      });
    }
  });

  const opened = new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  function send(method, params = {}) {
    if (socket.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error(`CDP socket not open, state=${socket.readyState}`));
    }
    const id = nextId++;
    socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`CDP command timed out: ${method}`));
        }
      }, 10000);
    });
  }

  return {
    opened,
    send,
    events,
    close: () => socket.close(),
  };
}

async function evaluate(cdp, expression, awaitPromise = true) {
  const result = await cdp.send("Runtime.evaluate", {
    expression,
    awaitPromise,
    returnByValue: true,
    userGesture: true,
  });
  if (result.exceptionDetails) {
    const detail = result.exceptionDetails.exception?.description
      || result.exceptionDetails.text
      || JSON.stringify(result.exceptionDetails);
    throw new Error(`Runtime.evaluate failed: ${detail}`);
  }
  return result.result?.value;
}

function stateExpression() {
  return `(() => {
    const byId = (id) => document.querySelector("#" + id);
    const text = (id) => byId(id) ? byId(id).textContent.trim() : "";
    const rect = (node) => {
      if (!node) return null;
      const value = node.getBoundingClientRect();
      return {
        x: Math.round(value.x * 100) / 100,
        y: Math.round(value.y * 100) / 100,
        width: Math.round(value.width * 100) / 100,
        height: Math.round(value.height * 100) / 100,
        top: Math.round(value.top * 100) / 100,
        left: Math.round(value.left * 100) / 100,
        bottom: Math.round(value.bottom * 100) / 100,
        right: Math.round(value.right * 100) / 100,
      };
    };
    const style = (node) => {
      if (!node) return null;
      const value = getComputedStyle(node);
      return {
        display: value.display,
        visibility: value.visibility,
        opacity: value.opacity,
        width: value.width,
        height: value.height,
        minHeight: value.minHeight,
        aspectRatio: value.aspectRatio,
        contain: value.contain,
        objectFit: value.objectFit,
      };
    };
    const video = byId("mp4Video");
    const screenBox = video ? video.closest(".screenBox") : null;
    let pixelSample = null;
    if (video && video.videoWidth > 0 && video.videoHeight > 0 && video.readyState >= 2) {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = 96;
        canvas.height = 96;
        const ctx = canvas.getContext("2d", { willReadFrequently: true, alpha: false });
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        let min = 255;
        let max = 0;
        let sum = 0;
        let sumSq = 0;
        let nonDark = 0;
        let nonFlat = 0;
        const buckets = new Set();
        const count = data.length / 4;
        for (let index = 0; index < data.length; index += 4) {
          const r = data[index];
          const g = data[index + 1];
          const b = data[index + 2];
          const y = (r + g + b) / 3;
          min = Math.min(min, y);
          max = Math.max(max, y);
          sum += y;
          sumSq += y * y;
          if (y > 8) nonDark += 1;
          if (Math.abs(r - g) + Math.abs(g - b) + Math.abs(r - b) > 6) nonFlat += 1;
          buckets.add(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4));
        }
        const mean = sum / count;
        const variance = Math.max(0, sumSq / count - mean * mean);
        pixelSample = {
          ok: true,
          width: canvas.width,
          height: canvas.height,
          mean: Math.round(mean * 100) / 100,
          stddev: Math.round(Math.sqrt(variance) * 100) / 100,
          min: Math.round(min * 100) / 100,
          max: Math.round(max * 100) / 100,
          range: Math.round((max - min) * 100) / 100,
          nonDarkRatio: Math.round((nonDark / count) * 10000) / 10000,
          nonFlatRatio: Math.round((nonFlat / count) * 10000) / 10000,
          colorBuckets: buckets.size,
        };
      } catch (error) {
        pixelSample = { ok: false, error: String(error) };
      }
    }
    let pc = null;
    try {
      pc = typeof webRtcPc !== "undefined" && webRtcPc ? {
        connectionState: webRtcPc.connectionState || "",
        iceConnectionState: webRtcPc.iceConnectionState || "",
        signalingState: webRtcPc.signalingState || "",
      } : null;
    } catch (error) {
      pc = { error: String(error) };
    }
    let inputChannel = null;
    try {
      inputChannel = typeof webRtcInputChannel !== "undefined" && webRtcInputChannel ? {
        readyState: webRtcInputChannel.readyState || "",
        label: webRtcInputChannel.label || "",
      } : null;
    } catch (error) {
      inputChannel = { error: String(error) };
    }
    let moveChannel = null;
    try {
      moveChannel = typeof webRtcMoveChannel !== "undefined" && webRtcMoveChannel ? {
        readyState: webRtcMoveChannel.readyState || "",
        label: webRtcMoveChannel.label || "",
      } : null;
    } catch (error) {
      moveChannel = { error: String(error) };
    }
    let sessionId = "";
    try {
      sessionId = typeof webRtcSessionId !== "undefined" ? webRtcSessionId : "";
    } catch (error) {
    }
    let runtimeConfig = null;
    try {
      runtimeConfig = typeof webRtcRuntimeConfig !== "undefined" ? webRtcRuntimeConfig : null;
    } catch (error) {
    }
    return {
      href: location.href,
      title: document.title,
      visibilityState: document.visibilityState,
      hasFocus: document.hasFocus(),
      bodyClass: document.body.className,
      bodyMode: document.body.dataset.portalMode || "",
      pairState: text("pairState"),
      remoteState: text("remoteState"),
      liveMetrics: text("liveMetrics"),
      tuningState: text("tuningState"),
      sessionState: text("sessionState"),
      logText: byId("out") ? byId("out").textContent.slice(0, 1200) : "",
      screenBox: {
        rect: rect(screenBox),
        style: style(screenBox),
      },
      video: video ? {
        rect: rect(video),
        style: style(video),
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight,
        readyState: video.readyState,
        networkState: video.networkState,
        currentTime: Math.round(video.currentTime * 1000) / 1000,
        paused: video.paused,
        ended: video.ended,
        srcObject: !!video.srcObject,
      } : null,
      pixelSample,
      pc,
      inputChannel,
      moveChannel,
      sessionId,
      runtimeConfig,
    };
  })()`;
}

function isConnected(state) {
  return state
    && state.pairState === "paired"
    && state.video
    && state.video.srcObject
    && state.video.videoWidth >= 720
    && state.video.videoHeight >= 1280
    && state.video.readyState >= 2
    && state.screenBox?.rect?.height >= 300
    && state.video?.rect?.height >= 300
    && state.screenBox?.style?.contain === "layout paint"
    && state.screenBox?.style?.aspectRatio === "1080 / 2340"
    && state.pixelSample?.ok
    && state.pixelSample.range > 2
    && state.pixelSample.colorBuckets > 2;
}

await mkdir(outDir, { recursive: true });
const runStamp = stamp();
const reportPath = join(outDir, `real-portal-visual-smoke-${variantSlug}-${runStamp}.json`);
const screenshotPath = join(outDir, `real-portal-visual-smoke-${variantSlug}-${runStamp}.png`);
const profileDir = join(tmpdir(), `smartisax-real-portal-${process.pid}-${runStamp}`);
const port = await getFreePort();
const targetUrl = `${portalUrl}/?code=${encodeURIComponent(code)}&presenter=${encodeURIComponent(presenterMode)}`;
let chrome = null;
let cdp = null;
let exitCode = 1;
const timeline = [];

try {
  chrome = spawn(chromePath, [
    `--user-data-dir=${profileDir}`,
    `--remote-debugging-port=${port}`,
    "--remote-allow-origins=*",
    "--no-first-run",
    "--no-default-browser-check",
    "--autoplay-policy=no-user-gesture-required",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-features=CalculateNativeWinOcclusion,IntensiveWakeUpThrottling",
    `--window-size=${chromeWindowSize}`,
    `--force-device-scale-factor=${deviceScaleFactor}`,
    targetUrl,
  ], {
    stdio: ["ignore", "ignore", "pipe"],
  });
  let chromeStderr = "";
  chrome.stderr.on("data", (chunk) => {
    chromeStderr += chunk.toString();
    chromeStderr = chromeStderr.slice(-8000);
  });

  const deadline = Date.now() + timeoutMs;
  const page = await pollDevTools(port, deadline);
  cdp = connectCdp(page.webSocketDebuggerUrl);
  await cdp.opened;
  await cdp.send("Page.enable");
  await cdp.send("Runtime.enable");
  await cdp.send("Emulation.setFocusEmulationEnabled", { enabled: true }).catch(() => {});
  await evaluate(cdp, "document.querySelector('.screenBox')?.scrollIntoView({ block: 'center', inline: 'center' }); true");

  let finalState = null;
  while (Date.now() < deadline) {
    const state = await evaluate(cdp, stateExpression());
    timeline.push({
      t: Date.now(),
      pairState: state.pairState,
      remoteState: state.remoteState,
      liveMetrics: state.liveMetrics,
      videoWidth: state.video?.videoWidth || 0,
      videoHeight: state.video?.videoHeight || 0,
      readyState: state.video?.readyState || 0,
      currentTime: state.video?.currentTime || 0,
      srcObject: !!state.video?.srcObject,
      pc: state.pc,
      inputChannel: state.inputChannel,
      moveChannel: state.moveChannel,
      pixelSample: state.pixelSample,
      screenBoxRect: state.screenBox?.rect || null,
      videoRect: state.video?.rect || null,
    });
    finalState = state;
    if (isConnected(state)) {
      await wait(observeMs);
      finalState = await evaluate(cdp, stateExpression());
      timeline.push({
        t: Date.now(),
        pairState: finalState.pairState,
        remoteState: finalState.remoteState,
        liveMetrics: finalState.liveMetrics,
        videoWidth: finalState.video?.videoWidth || 0,
        videoHeight: finalState.video?.videoHeight || 0,
        readyState: finalState.video?.readyState || 0,
        currentTime: finalState.video?.currentTime || 0,
        srcObject: !!finalState.video?.srcObject,
        pc: finalState.pc,
        inputChannel: finalState.inputChannel,
        moveChannel: finalState.moveChannel,
        pixelSample: finalState.pixelSample,
        screenBoxRect: finalState.screenBox?.rect || null,
        videoRect: finalState.video?.rect || null,
      });
      break;
    }
    await wait(pollMs);
  }

  await evaluate(cdp, "document.querySelector('.screenBox')?.scrollIntoView({ block: 'center', inline: 'center' }); true").catch(() => {});
  const screenshot = await cdp.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false,
  });
  await writeFile(screenshotPath, Buffer.from(screenshot.data || "", "base64"));

  const pass = isConnected(finalState);
  const report = {
    result: pass ? "PASS_REAL_PORTAL_VISUAL_SMOKE" : "FAIL_REAL_PORTAL_VISUAL_SMOKE",
    variant,
    portalUrl,
    targetUrl: targetUrl.replace(code, "******"),
    codeUsed: true,
    chrome: {
      path: chromePath,
      windowSize: chromeWindowSize,
      deviceScaleFactor,
      devtoolsPort: port,
      stderrTail: chromeStderr,
    },
    paths: {
      reportPath,
      screenshotPath,
      profileDir: keepProfile ? profileDir : null,
    },
    finalState,
    timeline,
    cdpEventsTail: (cdp?.events || []).slice(-80),
    checks: {
      paired: finalState?.pairState === "paired",
      videoSrcObject: !!finalState?.video?.srcObject,
      videoSize: `${finalState?.video?.videoWidth || 0}x${finalState?.video?.videoHeight || 0}`,
      videoReadyState: finalState?.video?.readyState || 0,
      screenBoxHeight: finalState?.screenBox?.rect?.height || 0,
      videoHeightCss: finalState?.video?.rect?.height || 0,
      screenBoxContain: finalState?.screenBox?.style?.contain || "",
      screenBoxAspectRatio: finalState?.screenBox?.style?.aspectRatio || "",
      pixelRange: finalState?.pixelSample?.range || 0,
      pixelBuckets: finalState?.pixelSample?.colorBuckets || 0,
    },
  };
  await writeFile(reportPath, JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({
    result: report.result,
    reportPath,
    screenshotPath,
    pairState: finalState?.pairState || "",
    remoteState: finalState?.remoteState || "",
    liveMetrics: finalState?.liveMetrics || "",
    video: report.checks.videoSize,
    readyState: report.checks.videoReadyState,
    currentTime: finalState?.video?.currentTime || 0,
    screenBox: `${report.checks.screenBoxHeight}px contain=${report.checks.screenBoxContain} aspect=${report.checks.screenBoxAspectRatio}`,
    pixelRange: report.checks.pixelRange,
    pixelBuckets: report.checks.pixelBuckets,
    pc: finalState?.pc || null,
    inputChannel: finalState?.inputChannel || null,
    moveChannel: finalState?.moveChannel || null,
  }, null, 2));
  exitCode = pass ? 0 : 1;
} catch (error) {
  const failure = {
    result: "FAIL_REAL_PORTAL_VISUAL_SMOKE",
    variant,
    portalUrl,
    targetUrl: targetUrl.replace(code, "******"),
    error: String(error && error.stack ? error.stack : error),
    timeline,
  };
  await writeFile(reportPath, JSON.stringify(failure, null, 2) + "\n").catch(() => {});
  console.error(failure.error);
  exitCode = 1;
} finally {
  if (cdp) {
    cdp.close();
  }
  if (chrome && !chrome.killed) {
    chrome.kill("SIGTERM");
    await wait(500);
    if (!chrome.killed) {
      chrome.kill("SIGKILL");
    }
  }
  if (!keepProfile) {
    await rm(profileDir, { recursive: true, force: true }).catch(() => {});
  }
}

process.exit(exitCode);
