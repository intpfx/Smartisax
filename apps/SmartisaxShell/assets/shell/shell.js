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
  renderCapabilities();
  refreshWirelessAdb();
  refreshPortal();
})();
