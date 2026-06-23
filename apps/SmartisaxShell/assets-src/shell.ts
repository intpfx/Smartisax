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

renderCapabilities();
refreshWirelessAdb();
refreshPortal();

export {};
