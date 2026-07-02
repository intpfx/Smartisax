# Smartisax Agent Core v0

Smartisax should become a device-agent system, but the first stable layer
should be a small Smartisax-owned runtime rather than a full general-purpose
agent framework. The current Portal line already proves the hard parts that a
phone agent needs: device observation, screen transport, interactive input,
session control, privilege boundaries, and evidence capture. Agent Core v0
turns those pieces into a stable tool contract.

## Position

Smartisax Agent Core is the phone-side runtime and protocol.

```text
External planner or LLM
  Codex, OpenAI Agents SDK, Pi, MCP, local model, or another coordinator

Smartisax Agent Protocol
  stable JSON tool schema, risk labels, evidence envelope, errors

Smartisax Device Agent Runtime
  tool registry, policy checks, state snapshot, action dispatcher

Existing Smartisax surfaces
  DevicePortalService, SmartisaxWebRtcRuntime, SmartisaxInputController,
  ShellBridge, MediaProjection, InputManager, system APIs
```

The planner is replaceable. The runtime is product-specific and must stay close
to the hard-ROM, Android permission, Portal, WebRTC, and live-device evidence
model.

## 2026-06-30 Implementation Update

`v0.agent0-vision-loop` is the first implemented MVP candidate. It moves beyond
the earlier read-only protocol sketch while keeping the same safety boundary:
the loop is manually started from the local Smartisax Shell UI, not remotely
invoked over LAN.

Implemented in SmartisaxShell v0.7.0/versionCode 51:

```text
SmartisaxAgentRuntime
  observe -> plan -> execute -> observe, max 5 steps

SmartisaxScreenCapture
  SurfaceControl screenshot reused as JPEG/Base64 observation for vision models

providers
  mimo_v25_vision: MiMo V2.5, vision-first screenshot planner
  deepseek_text: DeepSeek v4 flash, text/status fallback only
  mock: offline fixture provider

allowed actions
  tap, swipe, key(BACK|HOME), wait, finish, ask_user

diagnostics
  local Shell Agent panel
  token-gated read-only GET /api/agent/status
```

Still excluded:

```text
root.shell
adb.command
fastboot.command
rom.flash_super
rom.erase_misc
package.uninstall
data.clear
cleanup.run
remote HTTP start/control of the Agent
```

Offline evidence:

```text
PASS_BUILD_V0AGENT0_VISION_LOOP
PASS_OFFLINE_IMAGE_V0AGENT0_VISION_LOOP
PASS_AGENT0_OFFLINE_TESTS
agent0_extra_offline_checks=ok
```

The candidate has not been flashed or live-verified yet. Treat the older
read-only endpoint sequence below as historical protocol background; the
current MVP exposes only `/api/agent/status` remotely and keeps Agent start/stop
local to Shell.

## Why Not Start With An Agent Framework

Generic agent frameworks are useful above Smartisax, but they do not define the
phone safety contract. Smartisax first needs to decide:

```text
what the agent can observe
what the agent can do
which calls are read-only, interactive, privileged, or destructive
which calls require explicit human confirmation
how every call returns evidence
which capabilities are permanently excluded from automatic execution
```

After that contract exists, an outside framework can drive it as a planner. It
should not own the device privilege model.

## v0 Goals

```text
1. Name the device-agent tools that already exist behind Portal.
2. Put every tool behind a risk class and confirmation rule.
3. Return structured evidence from every invocation.
4. Keep destructive phone and ROM operations outside the default runtime.
5. Make future LLM/planner integration a protocol adapter, not the core.
```

## Non-Goals

```text
No on-phone autonomous LLM loop in v0.
No flash, reboot, erase, uninstall, data cleanup, or fastboot tool in v0.
No raw root shell over the LAN protocol.
No root filesystem browser by default.
No unauthenticated or always-on agent service.
No replacement for the existing hard-ROM build and preflight loop.
```

## Risk Classes

```text
read_only
  Reads state, capabilities, sessions, screen metadata, or diagnostics.
  Allowed after normal Portal pairing.

observe_sensitive
  Reads screen pixels, screenshots, active UI state, or user-visible content.
  Allowed after pairing, but surfaced separately because it can expose private
  information.

interactive
  Injects touch or gesture input into the live device UI. Requires an active
  session and should be auditable in the action log.

privileged_control
  Starts or stops privileged services, changes WebRTC runtime config, closes
  sessions, or toggles non-destructive system-facing state.

dangerous_manual
  Flashes, reboots, erases, clears data, uninstalls packages, runs cleanup
  scripts, or mutates ROM/device state outside app interaction. Excluded from
  Agent Core v0. These remain explicit operator workflows.
```

## Initial Tool Registry

v0 should describe tools before it broadens behavior. The first implementation
can expose only `read_only` and `observe_sensitive` tools, then add
`interactive` tools once the schema and evidence log are stable.

| Tool | Risk | Backing surface | v0 status |
| --- | --- | --- | --- |
| `device.status` | `read_only` | `/api/status` and build props | first |
| `portal.status` | `read_only` | `DevicePortalService.snapshot()` | first |
| `portal.capabilities` | `read_only` | `/api/media/capabilities` | first |
| `webrtc.sessions` | `read_only` | `SmartisaxWebRtcRuntime.statusJson()` | first |
| `webrtc.config.get` | `read_only` | `SmartisaxWebRtcRuntime.configJson()` | first |
| `display.state` | `read_only` | Portal display JSON | first |
| `screen.snapshot` | `observe_sensitive` | `/api/screen.png` or capture probe | second |
| `input.tap` | `interactive` | `SmartisaxInputController.handle()` | second |
| `input.swipe` | `interactive` | `SmartisaxInputController.handle()` | second |
| `input.touch_stream` | `interactive` | WebRTC `smartisax-input` channels | second |
| `webrtc.config.set` | `privileged_control` | `/api/webrtc/config` | second |
| `webrtc.session.close` | `privileged_control` | `/api/webrtc/close` | second |
| `portal.start` | `privileged_control` | `ShellBridge` or service start | local UI first |
| `portal.stop` | `privileged_control` | `ShellBridge` or service stop | local UI first |

Excluded v0 tools:

```text
root.shell
adb.command
fastboot.command
rom.flash_super
rom.erase_misc
package.uninstall
data.clear
cleanup.run
```

Those names are reserved only so future documentation can explicitly say why
they are not part of the default agent surface.

## Protocol Endpoints

The first API can live inside `DevicePortalService` beside the existing Portal
routes.

```text
GET /api/agent/capabilities
  Returns the registered tools, risk classes, input schemas, output summaries,
  confirmation policy, and whether each tool is enabled.

GET /api/agent/state
  Returns a compact state snapshot suitable for a planner.

POST /api/agent/invoke
  Invokes a single enabled tool through the common evidence envelope.
```

All endpoints reuse the current Portal pairing and Bearer token model. v0 does
not add a second authentication path.

## Invocation Request

```json
{
  "tool": "device.status",
  "arguments": {},
  "client": {
    "name": "smartisax-mac-harness",
    "sessionId": "optional-client-session"
  },
  "dryRun": false
}
```

For `interactive` and `privileged_control` tools, the runtime should reject
calls unless the tool is enabled and its policy allows remote invocation.

## Invocation Response

```json
{
  "ok": true,
  "invocationId": "agent-20260630-000001",
  "tool": "device.status",
  "risk": "read_only",
  "startedElapsedMs": 123456,
  "finishedElapsedMs": 123463,
  "durationMs": 7,
  "result": {
    "slot": "_b",
    "bootCompleted": "1",
    "portalVersion": "0.6.33"
  },
  "evidence": {
    "source": "DevicePortalService.statusJson",
    "variant": "v0.portal6g-rvfc-media-tail",
    "portalVersion": "0.6.33"
  }
}
```

Error responses should keep the same envelope:

```json
{
  "ok": false,
  "invocationId": "agent-20260630-000002",
  "tool": "input.tap",
  "risk": "interactive",
  "error": {
    "code": "tool_not_enabled",
    "message": "interactive tools are disabled for this session"
  },
  "evidence": {
    "source": "SmartisaxAgentRuntime.policy"
  }
}
```

## State Snapshot

`/api/agent/state` should be optimized for planner context and avoid large
payloads:

```json
{
  "ok": true,
  "device": {
    "model": "Smartisan R2",
    "slot": "_b",
    "bootCompleted": "1"
  },
  "portal": {
    "variant": "v0.portal6g-rvfc-media-tail",
    "url": "http://192.168.31.103:37601",
    "paired": true
  },
  "display": {
    "width": 1080,
    "height": 2340,
    "wakePolicy": "webrtc-session-screen-wake-lock+activity-keep-screen-on"
  },
  "runtime": {
    "webrtcAvailable": true,
    "inputTransport": "RTCDataChannel",
    "httpInput": false
  },
  "enabledRiskClasses": [
    "read_only",
    "observe_sensitive"
  ]
}
```

## Implementation Sequence

1. Add a small `SmartisaxAgentRuntime` class that owns the tool registry,
   risk labels, and common response envelope.
2. Wire `GET /api/agent/capabilities` and `GET /api/agent/state` in
   `DevicePortalService`.
3. Implement `POST /api/agent/invoke` for read-only tools only.
4. Add offline verifier checks for route strings, tool ids, risk labels, and
   the absence of excluded dangerous tools.
5. Add a Mac-side smoke helper that pairs with Portal and validates the Agent
   Core read-only contract.
6. Only after that gate passes, add `interactive` input tools through the same
   envelope.

## Verification Gates

Offline:

```text
APK builds.
Agent endpoint strings exist in decoded Smartisax APK.
Tool registry contains expected read-only tools.
Excluded dangerous tool ids are not invokable.
Existing Portal routes still exist.
Existing HTTP /api/input absence remains true.
```

Live read-only:

```text
Portal starts through the existing explicit flow.
Pairing still rotates code/token after success.
GET /api/agent/capabilities rejects missing token.
Authorized capabilities returns tool ids and risk labels.
GET /api/agent/state returns compact planner state.
POST /api/agent/invoke device.status returns an evidence envelope.
No input injection or system mutation occurs in the read-only gate.
```

Interactive later:

```text
input.tap and input.swipe return structured acks through the agent envelope.
Touch marker and WebRTC input evidence remain visible.
The smoke harness proves that Agent Core input is no worse than the current
direct `smartisax-input` path.
```

## Documentation Boundary

This document defines the product/runtime direction. It does not replace the
hard-ROM safety workflow. Any build, flash, reboot, fastboot, cleanup, or live
device mutation still follows `AGENTS.md`,
`.agents/skills/smartisan-r2-hardrom/SKILL.md`, and
`docs/hard-rom-ota-trust.md`.
