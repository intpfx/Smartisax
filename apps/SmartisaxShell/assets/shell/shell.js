(() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  function __accessProp(key) {
    return this[key];
  }
  var __toCommonJS = (from) => {
    var entry = (__moduleCache ??= new WeakMap).get(from), desc;
    if (entry)
      return entry;
    entry = __defProp({}, "__esModule", { value: true });
    if (from && typeof from === "object" || typeof from === "function") {
      for (var key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(entry, key))
          __defProp(entry, key, {
            get: __accessProp.bind(from, key),
            enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable
          });
    }
    __moduleCache.set(from, entry);
    return entry;
  };
  var __moduleCache;

  // apps/SmartisaxShell/assets-src/shell.ts
  var exports_shell = {};
  var form = document.querySelector("#openForm");
  var input = document.querySelector("#addressInput");
  var statusList = document.querySelector("#statusList");
  var reloadStatus = document.querySelector("#reloadStatus");
  var wirelessAdbStatus = document.querySelector("#wirelessAdbStatus");
  var wirelessAdbLog = document.querySelector("#wirelessAdbLog");
  var portalStatus = document.querySelector("#portalStatus");
  var portalLog = document.querySelector("#portalLog");
  var agentProvider = document.querySelector("#agentProvider");
  var mimoKeyInput = document.querySelector("#mimoKeyInput");
  var deepSeekKeyInput = document.querySelector("#deepSeekKeyInput");
  var agentGoalInput = document.querySelector("#agentGoalInput");
  var agentStatus = document.querySelector("#agentStatus");
  var agentTranscript = document.querySelector("#agentTranscript");
  var agentLog = document.querySelector("#agentLog");
  function normalizeAddress(value) {
    const trimmed = value.trim();
    if (!trimmed) {
      return "https://www.example.com";
    }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed)) {
      return trimmed;
    }
    if (trimmed.includes(".") && !trimmed.includes(" ")) {
      return `https://${trimmed}`;
    }
    return `https://www.google.com/search?q=${encodeURIComponent(trimmed)}`;
  }
  function detectWebgl2() {
    const canvas = document.createElement("canvas");
    const gl = canvas.getContext("webgl2");
    return Boolean(gl);
  }
  function renderCapabilities() {
    if (!statusList) {
      return;
    }
    const caps = [
      {
        label: "WebView",
        value: navigator.userAgent
      },
      {
        label: "WebGPU",
        value: "gpu" in navigator ? "available" : "not exposed",
        tone: "gpu" in navigator ? "ok" : "warn"
      },
      {
        label: "WebGL2",
        value: detectWebgl2() ? "available" : "not available",
        tone: detectWebgl2() ? "ok" : "warn"
      },
      {
        label: "Storage",
        value: typeof localStorage === "object" ? "localStorage ready" : "unavailable",
        tone: typeof localStorage === "object" ? "ok" : "warn"
      }
    ];
    statusList.replaceChildren(...caps.flatMap((cap) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = cap.label;
      dd.textContent = cap.value;
      if (cap.tone) {
        dd.className = cap.tone;
      }
      return [dt, dd];
    }));
  }
  function parseWirelessStatus(raw) {
    try {
      return JSON.parse(raw);
    } catch (error) {
      return {
        ok: false,
        backend: "web",
        log: error instanceof Error ? error.message : String(error)
      };
    }
  }
  function parsePortalStatus(raw) {
    try {
      return JSON.parse(raw);
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  function parseAgentStatus(raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && "status" in parsed) {
        return parsed.status ?? parsed;
      }
      return parsed;
    } catch (error) {
      return {
        ok: false,
        state: "error",
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }
  function renderWirelessAdb(status) {
    if (!wirelessAdbStatus) {
      return;
    }
    const rows = [
      {
        label: "State",
        value: status.active ? "active" : status.enabled ? "starting" : "off",
        tone: status.active ? "ok" : status.enabled ? "warn" : undefined
      },
      {
        label: "Connect",
        value: status.connect || "not available",
        tone: status.connect ? "ok" : "warn"
      },
      {
        label: "Backend",
        value: status.backend || "unavailable",
        tone: status.ok ? "ok" : "warn"
      },
      {
        label: "BSSID",
        value: status.bssid || "not available"
      }
    ];
    wirelessAdbStatus.replaceChildren(...rows.flatMap((row) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = row.label;
      dd.textContent = row.value;
      if (row.tone) {
        dd.className = row.tone;
      }
      return [dt, dd];
    }));
    if (wirelessAdbLog) {
      const action = status.action ? ` ${status.action}` : "";
      wirelessAdbLog.textContent = `${status.actionBackend || status.backend || "web"}${action}`;
    }
  }
  function refreshWirelessAdb() {
    const native = window.SmartisaxNative;
    if (!native) {
      renderWirelessAdb({ ok: false, backend: "web", log: "native bridge unavailable" });
      return;
    }
    renderWirelessAdb(parseWirelessStatus(native.getWirelessAdbStatus()));
  }
  function renderPortal(status) {
    if (!portalStatus) {
      return;
    }
    const rows = [
      {
        label: "State",
        value: status.running ? status.autoStartEnabled ? "running auto" : "running" : "off",
        tone: status.running ? "ok" : undefined
      },
      {
        label: "URL",
        value: status.url || "not available",
        tone: status.url ? "ok" : "warn"
      },
      {
        label: "Code",
        value: status.pairingCode || "not available",
        tone: status.pairingCode ? "ok" : "warn"
      },
      {
        label: "Pairs",
        value: String(status.successfulPairs ?? 0),
        tone: status.successfulPairs ? "ok" : undefined
      },
      {
        label: "Auto-start",
        value: status.autoStartEnabled ? "on" : "off",
        tone: status.autoStartEnabled ? "ok" : undefined
      },
      {
        label: "Start reason",
        value: status.startReason || "not available"
      },
      {
        label: "Port",
        value: status.port ? String(status.port) : "not available"
      }
    ];
    portalStatus.replaceChildren(...rows.flatMap((row) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = row.label;
      dd.textContent = row.value;
      if (row.tone) {
        dd.className = row.tone;
      }
      return [dt, dd];
    }));
    if (portalLog) {
      const action = status.action ? `${status.action} ` : "";
      portalLog.textContent = `${action}${status.error || ""}`.trim();
    }
  }
  function refreshPortal() {
    const native = window.SmartisaxNative;
    if (!native) {
      renderPortal({ ok: false, error: "native bridge unavailable" });
      return;
    }
    renderPortal(parsePortalStatus(native.getPortalStatus()));
  }
  function formatAction(action) {
    if (!action?.type) {
      return "action pending";
    }
    const confidence = typeof action.confidence === "number" ? ` ${(action.confidence * 100).toFixed(0)}%` : "";
    if (action.type === "tap") {
      return `tap(${action.x ?? "-"}, ${action.y ?? "-"})${confidence}`;
    }
    if (action.type === "swipe") {
      return `swipe(${action.x1 ?? "-"}, ${action.y1 ?? "-"} -> ${action.x2 ?? "-"}, ${action.y2 ?? "-"})${confidence}`;
    }
    if (action.type === "key") {
      return `key(${action.key || "-"})${confidence}`;
    }
    if (action.type === "wait") {
      return `wait(${action.durationMs ?? "-"}ms)${confidence}`;
    }
    if (action.type === "one_step") {
      return `one_step(${action.operation || "-"})${confidence}`;
    }
    if (action.type === "click_node") {
      return `click_node(${action.nodeId || "-"})${confidence}`;
    }
    if (action.type === "finish" || action.type === "ask_user") {
      return `${action.type}${confidence}`;
    }
    return `${action.type}${confidence}`;
  }
  function formatResult(result) {
    if (result.type === "provider_planning") {
      const a11y = result.accessibility;
      if (a11y) {
        return `planning: ${a11y.nodeCount ?? 0} nodes / ${a11y.rootCount ?? 0} roots / ${a11y.windowCount ?? 0} windows`;
      }
      return "planning";
    }
    if (result.guard) {
      return `${result.guard}: ${result.reason || result.message || "paused"}`;
    }
    if (result.finishGate && result.finishGate.accepted === false) {
      return `finish gate: ${result.finishGate.reason || "not accepted"}`;
    }
    if (result.actionFailure) {
      return `${result.actionFailure.guard || "action guard"}: ${result.actionFailure.reason || "not satisfied"}`;
    }
    if (result.oneStep) {
      const after = result.oneStep.after;
      const visible = after?.visible === true ? "visible" : after?.visible === false ? "hidden" : "unknown";
      const side = after?.side ? ` ${after.side}` : "";
      const failure = result.oneStep.failureReason ? ` ${result.oneStep.failureReason}` : "";
      return `one-step: ${result.oneStep.operation || "-"} ${visible}${side}${failure}`;
    }
    if (result.accessibility && typeof result.accessibility.ok === "boolean") {
      const ok = result.accessibility.ok ? "ok" : "failed";
      const ancestor = result.accessibility.clickedAncestor ? " ancestor" : "";
      const reason = result.accessibility.reason ? ` ${result.accessibility.reason}` : "";
      return `accessibility: ${ok}${ancestor}${reason}`;
    }
    if (result.postActionCheck) {
      const check = result.postActionCheck;
      const changed = check.screenChanged === true ? "changed" : check.screenChanged === false ? "no change" : "unknown";
      const fp = check.beforeFingerprint && check.afterFingerprint ? ` ${check.beforeFingerprint}->${check.afterFingerprint}` : "";
      return `post-check: ${changed}${fp}${check.reason ? ` ${check.reason}` : ""}`;
    }
    if (result.input) {
      const elapsed = typeof result.input.injectionElapsedMs === "number" ? ` ${result.input.injectionElapsedMs}ms` : "";
      return `input: ${result.input.type || result.type || "ok"} ${result.input.backend || ""}${elapsed}`.trim();
    }
    if (result.message) {
      return result.message;
    }
    return result.type || "result";
  }
  function renderAgent(status) {
    if (agentProvider && status.config?.provider) {
      agentProvider.value = status.config.provider;
    }
    if (!agentStatus) {
      return;
    }
    const rows = [
      {
        label: "State",
        value: status.state || "idle",
        tone: status.running || status.state === "complete" ? "ok" : status.state === "error" || status.state === "paused" ? "warn" : undefined
      },
      {
        label: "Provider",
        value: status.config?.selectedProvider || status.provider || "not selected",
        tone: status.config?.selectedProvider ? "ok" : "warn"
      },
      {
        label: "MiMo",
        value: status.config?.mimoKeySet ? `${status.config.mimoModel || "mimo-v2.5"} key saved` : "key not saved",
        tone: status.config?.mimoKeySet ? "ok" : "warn"
      },
      {
        label: "DeepSeek",
        value: status.config?.deepSeekKeySet ? `${status.config.deepSeekModel || "deepseek-v4-flash"} key saved` : "key not saved",
        tone: status.config?.deepSeekKeySet ? "ok" : undefined
      },
      {
        label: "Step",
        value: `${status.step ?? 0}/${status.maxSteps ?? 5}`
      },
      {
        label: "One Step",
        value: status.systemState?.oneStep?.visible ? `visible ${status.systemState.oneStep.side || ""}`.trim() : "hidden",
        tone: status.systemState?.oneStep?.visible ? "ok" : undefined
      },
      {
        label: "A11y",
        value: status.accessibility?.connected ? `${status.accessibility.nodeCount ?? 0} nodes / ${status.accessibility.rootCount ?? 0} roots / ${status.accessibility.windowCount ?? 0} windows` : status.accessibility?.enabledSetting ? "enabled, waiting" : "not connected",
        tone: status.accessibility?.connected ? "ok" : "warn"
      },
      {
        label: "A11y Targets",
        value: `${status.accessibilityTargets?.oneStepAppNodeCount ?? 0} One Step apps / ${status.accessibilityTargets?.settingsNodeCount ?? 0} Settings`,
        tone: (status.accessibilityTargets?.oneStepAppNodeCount ?? 0) > 0 || (status.accessibilityTargets?.settingsNodeCount ?? 0) > 0 ? "ok" : undefined
      },
      {
        label: "Last",
        value: status.lastMessage || status.error || "not available",
        tone: status.lastMessage || status.error ? "warn" : undefined
      }
    ];
    agentStatus.replaceChildren(...rows.flatMap((row) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = row.label;
      dd.textContent = row.value;
      if (row.tone) {
        dd.className = row.tone;
      }
      return [dt, dd];
    }));
    if (agentTranscript) {
      const items = (status.transcript ?? []).slice(-5).map((entry) => {
        const li = document.createElement("li");
        li.className = entry.status?.startsWith("paused") ? "transcriptItem transcriptWarn" : "transcriptItem";
        const action = entry.action;
        const summary = action?.summary || action?.message || "";
        const header = document.createElement("div");
        header.className = "transcriptHeader";
        header.textContent = `#${entry.step ?? "-"} ${entry.provider || ""} ${entry.status || ""} ${entry.planMs ?? "-"}ms`.trim();
        const actionLine = document.createElement("div");
        actionLine.textContent = formatAction(action);
        li.append(header, actionLine);
        if (summary) {
          const summaryLine = document.createElement("div");
          summaryLine.className = "transcriptSummary";
          summaryLine.textContent = summary;
          li.append(summaryLine);
        }
        if (entry.result) {
          const resultLine = document.createElement("div");
          resultLine.className = "transcriptResult";
          resultLine.textContent = formatResult(entry.result);
          li.append(resultLine);
        }
        return li;
      });
      agentTranscript.replaceChildren(...items);
    }
    if (agentLog) {
      agentLog.textContent = status.lastMessage || status.error || "";
    }
  }
  function refreshAgent() {
    const native = window.SmartisaxNative;
    if (!native) {
      renderAgent({ ok: false, state: "error", error: "native bridge unavailable" });
      return;
    }
    renderAgent(parseAgentStatus(native.getAgentStatus()));
  }
  function runWirelessAdbAction(action) {
    const native = window.SmartisaxNative;
    if (!native) {
      renderWirelessAdb({ ok: false, backend: "web", log: "native bridge unavailable" });
      return;
    }
    if (action === "enable") {
      renderWirelessAdb(parseWirelessStatus(native.enableWirelessAdb()));
      return;
    }
    if (action === "disable") {
      renderWirelessAdb(parseWirelessStatus(native.disableWirelessAdb()));
      return;
    }
    renderWirelessAdb(parseWirelessStatus(native.getWirelessAdbStatus()));
  }
  function runPortalAction(action) {
    const native = window.SmartisaxNative;
    if (!native) {
      renderPortal({ ok: false, error: "native bridge unavailable" });
      return;
    }
    if (action === "enable") {
      renderPortal(parsePortalStatus(native.enablePortal()));
      return;
    }
    if (action === "disable") {
      renderPortal(parsePortalStatus(native.disablePortal()));
      return;
    }
    if (action === "auto-on") {
      renderPortal(parsePortalStatus(native.enablePortalAutoStart()));
      return;
    }
    if (action === "auto-off") {
      renderPortal(parsePortalStatus(native.disablePortalAutoStart()));
      return;
    }
    renderPortal(parsePortalStatus(native.getPortalStatus()));
  }
  function runAgentAction(action) {
    const native = window.SmartisaxNative;
    if (!native) {
      renderAgent({ ok: false, state: "error", error: "native bridge unavailable" });
      return;
    }
    if (action === "save") {
      renderAgent(parseAgentStatus(native.saveAgentConfig(JSON.stringify({
        provider: agentProvider?.value ?? "auto",
        mimoApiKey: mimoKeyInput?.value ?? "",
        deepSeekApiKey: deepSeekKeyInput?.value ?? ""
      }))));
      if (mimoKeyInput) {
        mimoKeyInput.value = "";
      }
      if (deepSeekKeyInput) {
        deepSeekKeyInput.value = "";
      }
      return;
    }
    if (action === "start") {
      native.saveAgentConfig(JSON.stringify({
        provider: agentProvider?.value ?? "auto",
        mimoApiKey: mimoKeyInput?.value ?? "",
        deepSeekApiKey: deepSeekKeyInput?.value ?? ""
      }));
      if (mimoKeyInput) {
        mimoKeyInput.value = "";
      }
      if (deepSeekKeyInput) {
        deepSeekKeyInput.value = "";
      }
      renderAgent(parseAgentStatus(native.startAgent(agentGoalInput?.value ?? "")));
      return;
    }
    if (action === "stop") {
      renderAgent(parseAgentStatus(native.stopAgent()));
      return;
    }
    renderAgent(parseAgentStatus(native.getAgentStatus()));
  }
  function openUrl(raw) {
    window.location.href = normalizeAddress(raw);
  }
  form?.addEventListener("submit", (event) => {
    event.preventDefault();
    openUrl(input?.value ?? "");
  });
  document.querySelectorAll("[data-url]").forEach((button) => {
    button.addEventListener("click", () => openUrl(button.dataset.url ?? ""));
  });
  reloadStatus?.addEventListener("click", renderCapabilities);
  document.querySelectorAll("[data-adb-action]").forEach((button) => {
    button.addEventListener("click", () => runWirelessAdbAction(button.dataset.adbAction ?? "refresh"));
  });
  document.querySelectorAll("[data-portal-action]").forEach((button) => {
    button.addEventListener("click", () => runPortalAction(button.dataset.portalAction ?? "refresh"));
  });
  document.querySelectorAll("[data-agent-action]").forEach((button) => {
    button.addEventListener("click", () => runAgentAction(button.dataset.agentAction ?? "refresh"));
  });
  renderCapabilities();
  refreshWirelessAdb();
  refreshPortal();
  refreshAgent();
})();
