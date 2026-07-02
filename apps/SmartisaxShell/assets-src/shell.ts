type Capability = {
  label: string;
  value: string;
  tone?: "ok" | "warn";
};

type WirelessAdbStatus = {
  ok?: boolean;
  backend?: string;
  enabled?: boolean;
  active?: boolean;
  ip?: string;
  bssid?: string;
  port?: number;
  connect?: string;
  actionExit?: number | null;
  actionBackend?: string;
  action?: string;
  log?: string;
};

type PortalStatus = {
  ok?: boolean;
  action?: string;
  running?: boolean;
  ip?: string;
  port?: number;
  url?: string;
  pairingCode?: string;
  successfulPairs?: number;
  startedAtMs?: number;
  lastPairAtMs?: number;
  startReason?: string;
  autoStartEnabled?: boolean;
  error?: string;
};

type AgentStatus = {
  ok?: boolean;
  state?: string;
  running?: boolean;
  goal?: string;
  provider?: string;
  step?: number;
  maxSteps?: number;
  lastMessage?: string;
  config?: {
    provider?: string;
    selectedProvider?: string;
    mimoKeySet?: boolean;
    deepSeekKeySet?: boolean;
    mimoModel?: string;
    deepSeekModel?: string;
  };
  transcript?: Array<{
    step?: number;
    provider?: string;
    status?: string;
    planMs?: number;
    action?: {
      type?: string;
      x?: number;
      y?: number;
      x1?: number;
      y1?: number;
      x2?: number;
      y2?: number;
      summary?: string;
      confidence?: number;
      key?: string;
      durationMs?: number;
      message?: string;
      operation?: string;
      nodeId?: string;
    };
    result?: {
      type?: string;
      guard?: string;
      reason?: string;
      message?: string;
      input?: {
        ok?: boolean;
        type?: string;
        backend?: string;
        injectedEvents?: number;
        injectionElapsedMs?: number;
      };
      postActionCheck?: {
        comparable?: boolean;
        screenChanged?: boolean | null;
        reason?: string;
        beforeFingerprint?: string;
        afterFingerprint?: string;
      };
      finishGate?: {
        accepted?: boolean;
        reason?: string;
        lastUiActionVerifiedScreenChange?: boolean;
      };
      oneStep?: {
        operation?: string;
        backend?: string;
        after?: {
          visible?: boolean;
          side?: string;
          sideBarZoomType?: number;
          sidebarSwitchStatus?: number;
        };
      };
      accessibility?: {
        ok?: boolean;
        nodeId?: string;
        reason?: string;
        performed?: boolean;
        clickedAncestor?: boolean;
        rootCount?: number;
        windowCount?: number;
      };
    };
  }>;
  systemState?: {
    oneStep?: {
      visible?: boolean;
      side?: string;
      sideBarZoomType?: number;
      sidebarSwitchStatus?: number;
    };
  };
  accessibility?: {
    enabledSetting?: boolean;
    connected?: boolean;
    hasRoot?: boolean;
    rootCount?: number;
    windowCount?: number;
    nodeCount?: number;
    truncated?: boolean;
  };
  accessibilityTargets?: {
    oneStepAppNodeCount?: number;
    settingsNodeCount?: number;
    sample?: Array<{
      nodeId?: string;
      description?: string;
      text?: string;
      package?: string;
      clickable?: boolean;
      enabled?: boolean;
    }>;
  };
  error?: string;
};

declare global {
  interface Window {
    SmartisaxNative?: {
      getWirelessAdbStatus(): string;
      enableWirelessAdb(): string;
      disableWirelessAdb(): string;
      getPortalStatus(): string;
      enablePortal(): string;
      disablePortal(): string;
      enablePortalAutoStart(): string;
      disablePortalAutoStart(): string;
      getAgentStatus(): string;
      saveAgentConfig(rawConfig: string): string;
      startAgent(goal: string): string;
      stopAgent(): string;
    };
  }
}

const form = document.querySelector<HTMLFormElement>("#openForm");
const input = document.querySelector<HTMLInputElement>("#addressInput");
const statusList = document.querySelector<HTMLDListElement>("#statusList");
const reloadStatus = document.querySelector<HTMLButtonElement>("#reloadStatus");
const wirelessAdbStatus = document.querySelector<HTMLDListElement>("#wirelessAdbStatus");
const wirelessAdbLog = document.querySelector<HTMLParagraphElement>("#wirelessAdbLog");
const portalStatus = document.querySelector<HTMLDListElement>("#portalStatus");
const portalLog = document.querySelector<HTMLParagraphElement>("#portalLog");
const agentProvider = document.querySelector<HTMLSelectElement>("#agentProvider");
const mimoKeyInput = document.querySelector<HTMLInputElement>("#mimoKeyInput");
const deepSeekKeyInput = document.querySelector<HTMLInputElement>("#deepSeekKeyInput");
const agentGoalInput = document.querySelector<HTMLTextAreaElement>("#agentGoalInput");
const agentStatus = document.querySelector<HTMLDListElement>("#agentStatus");
const agentTranscript = document.querySelector<HTMLOListElement>("#agentTranscript");
const agentLog = document.querySelector<HTMLParagraphElement>("#agentLog");

function normalizeAddress(value: string): string {
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

function detectWebgl2(): boolean {
  const canvas = document.createElement("canvas");
  const gl = canvas.getContext("webgl2");
  return Boolean(gl);
}

function renderCapabilities(): void {
  if (!statusList) {
    return;
  }
  const caps: Capability[] = [
    {
      label: "WebView",
      value: navigator.userAgent,
    },
    {
      label: "WebGPU",
      value: "gpu" in navigator ? "available" : "not exposed",
      tone: "gpu" in navigator ? "ok" : "warn",
    },
    {
      label: "WebGL2",
      value: detectWebgl2() ? "available" : "not available",
      tone: detectWebgl2() ? "ok" : "warn",
    },
    {
      label: "Storage",
      value: typeof localStorage === "object" ? "localStorage ready" : "unavailable",
      tone: typeof localStorage === "object" ? "ok" : "warn",
    },
  ];
  statusList.replaceChildren(
    ...caps.flatMap((cap) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = cap.label;
      dd.textContent = cap.value;
      if (cap.tone) {
        dd.className = cap.tone;
      }
      return [dt, dd];
    }),
  );
}

function parseWirelessStatus(raw: string): WirelessAdbStatus {
  try {
    return JSON.parse(raw) as WirelessAdbStatus;
  } catch (error) {
    return {
      ok: false,
      backend: "web",
      log: error instanceof Error ? error.message : String(error),
    };
  }
}

function parsePortalStatus(raw: string): PortalStatus {
  try {
    return JSON.parse(raw) as PortalStatus;
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

function parseAgentStatus(raw: string): AgentStatus {
  try {
    const parsed = JSON.parse(raw) as AgentStatus;
    if (parsed && typeof parsed === "object" && "status" in parsed) {
      return (parsed as { status?: AgentStatus }).status ?? parsed;
    }
    return parsed;
  } catch (error) {
    return {
      ok: false,
      state: "error",
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

function renderWirelessAdb(status: WirelessAdbStatus): void {
  if (!wirelessAdbStatus) {
    return;
  }
  const rows: Capability[] = [
    {
      label: "State",
      value: status.active ? "active" : status.enabled ? "starting" : "off",
      tone: status.active ? "ok" : status.enabled ? "warn" : undefined,
    },
    {
      label: "Connect",
      value: status.connect || "not available",
      tone: status.connect ? "ok" : "warn",
    },
    {
      label: "Backend",
      value: status.backend || "unavailable",
      tone: status.ok ? "ok" : "warn",
    },
    {
      label: "BSSID",
      value: status.bssid || "not available",
    },
  ];
  wirelessAdbStatus.replaceChildren(
    ...rows.flatMap((row) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = row.label;
      dd.textContent = row.value;
      if (row.tone) {
        dd.className = row.tone;
      }
      return [dt, dd];
    }),
  );
  if (wirelessAdbLog) {
    const action = status.action ? ` ${status.action}` : "";
    wirelessAdbLog.textContent = `${status.actionBackend || status.backend || "web"}${action}`;
  }
}

function refreshWirelessAdb(): void {
  const native = window.SmartisaxNative;
  if (!native) {
    renderWirelessAdb({ ok: false, backend: "web", log: "native bridge unavailable" });
    return;
  }
  renderWirelessAdb(parseWirelessStatus(native.getWirelessAdbStatus()));
}

function renderPortal(status: PortalStatus): void {
  if (!portalStatus) {
    return;
  }
  const rows: Capability[] = [
    {
      label: "State",
      value: status.running ? status.autoStartEnabled ? "running auto" : "running" : "off",
      tone: status.running ? "ok" : undefined,
    },
    {
      label: "URL",
      value: status.url || "not available",
      tone: status.url ? "ok" : "warn",
    },
    {
      label: "Code",
      value: status.pairingCode || "not available",
      tone: status.pairingCode ? "ok" : "warn",
    },
    {
      label: "Pairs",
      value: String(status.successfulPairs ?? 0),
      tone: status.successfulPairs ? "ok" : undefined,
    },
    {
      label: "Auto-start",
      value: status.autoStartEnabled ? "on" : "off",
      tone: status.autoStartEnabled ? "ok" : undefined,
    },
    {
      label: "Start reason",
      value: status.startReason || "not available",
    },
    {
      label: "Port",
      value: status.port ? String(status.port) : "not available",
    },
  ];
  portalStatus.replaceChildren(
    ...rows.flatMap((row) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = row.label;
      dd.textContent = row.value;
      if (row.tone) {
        dd.className = row.tone;
      }
      return [dt, dd];
    }),
  );
  if (portalLog) {
    const action = status.action ? `${status.action} ` : "";
    portalLog.textContent = `${action}${status.error || ""}`.trim();
  }
}

function refreshPortal(): void {
  const native = window.SmartisaxNative;
  if (!native) {
    renderPortal({ ok: false, error: "native bridge unavailable" });
    return;
  }
  renderPortal(parsePortalStatus(native.getPortalStatus()));
}

function formatAction(action: NonNullable<AgentStatus["transcript"]>[number]["action"]): string {
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

function formatResult(result: NonNullable<NonNullable<AgentStatus["transcript"]>[number]["result"]>): string {
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
    const fp = check.beforeFingerprint && check.afterFingerprint
      ? ` ${check.beforeFingerprint}->${check.afterFingerprint}`
      : "";
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

function renderAgent(status: AgentStatus): void {
  if (agentProvider && status.config?.provider) {
    agentProvider.value = status.config.provider;
  }
  if (!agentStatus) {
    return;
  }
  const rows: Capability[] = [
    {
      label: "State",
      value: status.state || "idle",
      tone: status.running || status.state === "complete" ? "ok" : status.state === "error" || status.state === "paused" ? "warn" : undefined,
    },
    {
      label: "Provider",
      value: status.config?.selectedProvider || status.provider || "not selected",
      tone: status.config?.selectedProvider ? "ok" : "warn",
    },
    {
      label: "MiMo",
      value: status.config?.mimoKeySet ? `${status.config.mimoModel || "mimo-v2.5"} key saved` : "key not saved",
      tone: status.config?.mimoKeySet ? "ok" : "warn",
    },
    {
      label: "DeepSeek",
      value: status.config?.deepSeekKeySet ? `${status.config.deepSeekModel || "deepseek-v4-flash"} key saved` : "key not saved",
      tone: status.config?.deepSeekKeySet ? "ok" : undefined,
    },
    {
      label: "Step",
      value: `${status.step ?? 0}/${status.maxSteps ?? 5}`,
    },
    {
      label: "One Step",
      value: status.systemState?.oneStep?.visible
        ? `visible ${status.systemState.oneStep.side || ""}`.trim()
        : "hidden",
      tone: status.systemState?.oneStep?.visible ? "ok" : undefined,
    },
    {
      label: "A11y",
      value: status.accessibility?.connected
        ? `${status.accessibility.nodeCount ?? 0} nodes / ${status.accessibility.rootCount ?? 0} roots / ${status.accessibility.windowCount ?? 0} windows`
        : status.accessibility?.enabledSetting ? "enabled, waiting" : "not connected",
      tone: status.accessibility?.connected ? "ok" : "warn",
    },
    {
      label: "A11y Targets",
      value: `${status.accessibilityTargets?.oneStepAppNodeCount ?? 0} One Step apps / ${status.accessibilityTargets?.settingsNodeCount ?? 0} Settings`,
      tone: (status.accessibilityTargets?.oneStepAppNodeCount ?? 0) > 0
        || (status.accessibilityTargets?.settingsNodeCount ?? 0) > 0 ? "ok" : undefined,
    },
    {
      label: "Last",
      value: status.lastMessage || status.error || "not available",
      tone: status.lastMessage || status.error ? "warn" : undefined,
    },
  ];
  agentStatus.replaceChildren(
    ...rows.flatMap((row) => {
      const dt = document.createElement("dt");
      const dd = document.createElement("dd");
      dt.textContent = row.label;
      dd.textContent = row.value;
      if (row.tone) {
        dd.className = row.tone;
      }
      return [dt, dd];
    }),
  );
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

function refreshAgent(): void {
  const native = window.SmartisaxNative;
  if (!native) {
    renderAgent({ ok: false, state: "error", error: "native bridge unavailable" });
    return;
  }
  renderAgent(parseAgentStatus(native.getAgentStatus()));
}

function runWirelessAdbAction(action: string): void {
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

function runPortalAction(action: string): void {
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

function runAgentAction(action: string): void {
  const native = window.SmartisaxNative;
  if (!native) {
    renderAgent({ ok: false, state: "error", error: "native bridge unavailable" });
    return;
  }
  if (action === "save") {
    renderAgent(parseAgentStatus(native.saveAgentConfig(JSON.stringify({
      provider: agentProvider?.value ?? "auto",
      mimoApiKey: mimoKeyInput?.value ?? "",
      deepSeekApiKey: deepSeekKeyInput?.value ?? "",
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
      deepSeekApiKey: deepSeekKeyInput?.value ?? "",
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

function openUrl(raw: string): void {
  window.location.href = normalizeAddress(raw);
}

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  openUrl(input?.value ?? "");
});

document.querySelectorAll<HTMLButtonElement>("[data-url]").forEach((button) => {
  button.addEventListener("click", () => openUrl(button.dataset.url ?? ""));
});

reloadStatus?.addEventListener("click", renderCapabilities);

document.querySelectorAll<HTMLButtonElement>("[data-adb-action]").forEach((button) => {
  button.addEventListener("click", () => runWirelessAdbAction(button.dataset.adbAction ?? "refresh"));
});

document.querySelectorAll<HTMLButtonElement>("[data-portal-action]").forEach((button) => {
  button.addEventListener("click", () => runPortalAction(button.dataset.portalAction ?? "refresh"));
});

document.querySelectorAll<HTMLButtonElement>("[data-agent-action]").forEach((button) => {
  button.addEventListener("click", () => runAgentAction(button.dataset.agentAction ?? "refresh"));
});

renderCapabilities();
refreshWirelessAdb();
refreshPortal();
refreshAgent();

export {};
