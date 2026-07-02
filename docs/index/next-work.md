# Next Work

This file was split out of the root `README.md` so active task notes can grow without bloating the project entrypoint. Verify against current device/image state before acting.

## Agent Core Direction

Smartisax should grow from the live Portal line into a device-agent runtime.
The live Agent line is now `v0.agent0.10-finish-target-verify`, a B-slot
flashed/read-only PASS SmartisaxShell line on top of v0.agent0.9's worker/a11y
target repair. The Agent path keeps
the runtime on the R2,
sends manually started screenshot observations to MiMo V2.5 as the vision-first
planner, keeps DeepSeek as the text/status fallback, and restricts execution to
click_node, tap, swipe, BACK/HOME key, wait, finish, ask_user, and the narrow
Smartisan `one_step enter|exit` semantic action. v0.agent0.5 moved
stale-coordinate recovery from prompt-only guidance into Runtime: each
observation carries a 12x12 visual
signature; if the screen changes materially between planning and execution, the
runtime skips the stale action and reobserves/replans. If the previous action
caused a material screen change and the next action hits the edge-coordinate
guard, the runtime also reobserves before pausing. v0.agent0.6 adds a compact
Accessibility tree observation and a narrow `click_node` action backed by
`AccessibilityNodeInfo.performAction(ACTION_CLICK)`. v0.agent0.7 extends that
tree from active-root-only to active root plus `getWindows()` interactive
window roots, extends `click_node` lookup across those roots, and makes
provider planning/network/timeout failures visible in the transcript. The
v0.agent0.8 line adds One Step enter visible-state recovery and patches
Sidebar's dynamic top app strip so each bound AppItem exposes an
Agent-friendly clickable Accessibility node. v0.agent0.9 reconciles dead worker
status to `error/agent_worker_not_alive` and exposes `accessibilityTargets`
(`oneStepAppNodeCount`, `settingsNodeCount`, compact samples) in Shell/Portal
status. Its live Settings task proved the dynamic Settings AppItem is
Agent-visible and actionable: `A11y Targets` reported
`14 One Step apps / 1 Settings`, and MiMo executed `click_node(...)` to open
Settings. v0.agent0.10 implements the finish-gate repair:
foreground `com.android.settings`, a Settings Accessibility window, or an
actual Accessibility node whose package is `com.android.settings` can satisfy a
Settings-open goal instead of pausing at
`finish_requires_verified_screen_change`. It has passed live flash/read-only
verification and, after the R2 network was restored, passed the Settings-open
acceptance rerun. The first network-restored attempt reached MiMo but paused at
`one_step_enter_not_visible` because Sidebar rejected One Step entry while
keyguard was still considered showing. After waking/dismissing keyguard,
returning HOME, forcing One Step exit, and relaunching Shell, the same goal
completed: One Step became visible, Settings was foreground by 10s,
`A11y Targets` showed `13 One Step apps / 1 Settings`,
`click_node(...)` opened the Settings AppItem, and `finish 100%` ended
`complete`. The
design background is in `docs/research/smartisax-agent-core-v0.md`.

Implemented local-only/paired diagnostics:

```text
Smartisax Shell Agent panel
GET /api/agent/status
mimo_v25_vision / deepseek_text / mock providers
shared JPEG/Base64 screen observation helper
compact Accessibility tree helper
```

The runtime keeps flash, reboot, erase, cleanup, uninstall, raw root shell, ADB,
and fastboot outside the agent tool surface. Those remain explicit operator
workflows under `AGENTS.md`, the project skill, and the hard-ROM evidence loop.

Current Agent evidence:
`hard-rom/inspect/v0.agent0-vision-loop/build-v0.agent0-vision-loop-20260630-161953.txt`
and
`hard-rom/inspect/v0.agent0-vision-loop/verify-v0.agent0-vision-loop-offline-image-20260630-163620.txt`;
preflight evidence is
`hard-rom/inspect/v0.agent0-vision-loop/preflight-v0.agent0-vision-loop-20260630-163820.txt`;
flash/read-only evidence is
`hard-rom/inspect/v0.agent0-vision-loop/flash-v0.agent0-vision-loop-20260630-164247.txt`
and
`hard-rom/inspect/v0.agent0-vision-loop/verify-v0.agent0-vision-loop-device-read-only-20260630-164929.txt`.
The current guard-build live evidence is
`hard-rom/inspect/v0.agent0.1-vision-guard/flash-v0.agent0.1-vision-guard-20260630-185030.txt`,
`hard-rom/inspect/v0.agent0.1-vision-guard/boot-wait-v0.agent0.1-vision-guard-20260630-185030.txt`,
and
`hard-rom/inspect/v0.agent0.1-vision-guard/verify-v0.agent0.1-vision-guard-device-read-only-20260630-185541.txt`.
The v0.agent0.2 live One Step evidence is
`hard-rom/inspect/v0.agent0.2-one-step/build-v0.agent0.2-one-step-20260630-192040.txt`
and
`hard-rom/inspect/v0.agent0.2-one-step/verify-v0.agent0.2-one-step-offline-image-20260630-192343.txt`;
flash/read-only evidence is
`hard-rom/inspect/v0.agent0.2-one-step/flash-v0.agent0.2-one-step-20260630-193243.txt`
and
`hard-rom/inspect/v0.agent0.2-one-step/verify-v0.agent0.2-one-step-device-read-only-20260630-193754.txt`.
The v0.agent0.3 live One Step evidence is
`hard-rom/inspect/v0.agent0.3-one-step-bind-wait/build-v0.agent0.3-one-step-bind-wait-20260630-195448.txt`
and
`hard-rom/inspect/v0.agent0.3-one-step-bind-wait/verify-v0.agent0.3-one-step-bind-wait-offline-image-20260630-195752.txt`;
flash/read-only evidence is
`hard-rom/inspect/v0.agent0.3-one-step-bind-wait/flash-v0.agent0.3-one-step-bind-wait-20260630-200648.txt`
and
`hard-rom/inspect/v0.agent0.3-one-step-bind-wait/verify-v0.agent0.3-one-step-bind-wait-device-read-only-20260630-201158.txt`;
One Step smoke evidence is
`hard-rom/inspect/v0.agent0.3-one-step-bind-wait/one-step-smoke-20260630-201232/`.
The v0.agent0.4 repair candidate evidence is
`hard-rom/inspect/v0.agent0.4-home-onestep-settings-guard/build-v0.agent0.4-home-onestep-settings-guard-20260630-210029.txt`
and
`hard-rom/inspect/v0.agent0.4-home-onestep-settings-guard/verify-v0.agent0.4-home-onestep-settings-guard-offline-image-20260630-210333.txt`.
Flash/read-only evidence is
`hard-rom/inspect/v0.agent0.4-home-onestep-settings-guard/flash-v0.agent0.4-home-onestep-settings-guard-20260630-211650.txt`
and
`hard-rom/inspect/v0.agent0.4-home-onestep-settings-guard/verify-v0.agent0.4-home-onestep-settings-guard-device-read-only-20260630-212201.txt`;
Settings diagnostic evidence is
`hard-rom/inspect/v0.agent0.4-home-onestep-settings-guard/settings-app-task-20260630-212239/`.
The v0.agent0.5 reobserve candidate evidence is
`hard-rom/inspect/v0.agent0.5-reobserve-on-screen-change/build-v0.agent0.5-reobserve-on-screen-change-20260630-214854.txt`
and
`hard-rom/inspect/v0.agent0.5-reobserve-on-screen-change/verify-v0.agent0.5-reobserve-on-screen-change-offline-image-20260630-215157.txt`.
Flash/read-only evidence is
`hard-rom/inspect/v0.agent0.5-reobserve-on-screen-change/flash-v0.agent0.5-reobserve-on-screen-change-20260630-220422.txt`
and
`hard-rom/inspect/v0.agent0.5-reobserve-on-screen-change/verify-v0.agent0.5-reobserve-on-screen-change-device-read-only-20260630-220932.txt`;
focus/keyguard evidence is
`hard-rom/inspect/v0.agent0.5-reobserve-on-screen-change/post-flash-focus-v0.agent0.5-reobserve-on-screen-change-20260630-221006.txt`.
Settings diagnostic evidence is
`hard-rom/inspect/v0.agent0.5-reobserve-on-screen-change/settings-app-task-20260630-221422/`.
The v0.agent0.6 accessibility-tree live evidence is
`hard-rom/inspect/v0.agent0.6-accessibility-tree/build-v0.agent0.6-accessibility-tree-20260701-000041.txt`
and
`hard-rom/inspect/v0.agent0.6-accessibility-tree/verify-v0.agent0.6-accessibility-tree-offline-image-20260701-000415.txt`;
flash/read-only evidence is
`hard-rom/inspect/v0.agent0.6-accessibility-tree/flash-v0.agent0.6-accessibility-tree-20260701-154742.txt`
and
`hard-rom/inspect/v0.agent0.6-accessibility-tree/verify-v0.agent0.6-accessibility-tree-device-read-only-20260701-155253.txt`;
Accessibility binding evidence is
`hard-rom/inspect/v0.agent0.6-accessibility-tree/post-flash-accessibility-v0.agent0.6-accessibility-tree-20260701-155309.txt`.
Settings task diagnostic evidence is
`hard-rom/inspect/v0.agent0.6-accessibility-tree/settings-task-20260701-160601/report.md`.
The v0.agent0.7 window/preflight repair candidate evidence is
`hard-rom/inspect/v0.agent0.7-window-preflight/build-v0.agent0.7-window-preflight-20260701-162941.txt`,
`hard-rom/inspect/v0.agent0.7-window-preflight/verify-v0.agent0.7-window-preflight-offline-image-20260701-163244.txt`,
and
`hard-rom/inspect/v0.agent0.7-window-preflight/preflight-v0.agent0.7-window-preflight-20260701-163520.txt`.
The confirmed but blocked flash-attempt evidence is
`hard-rom/inspect/v0.agent0.7-window-preflight/flash-v0.agent0.7-window-preflight-20260701-163916.txt`.
The successful retry flash/read-only evidence is
`hard-rom/inspect/v0.agent0.7-window-preflight/flash-v0.agent0.7-window-preflight-20260701-165128.txt`,
`hard-rom/inspect/v0.agent0.7-window-preflight/boot-wait-v0.agent0.7-window-preflight-20260701-165128.txt`,
`hard-rom/inspect/v0.agent0.7-window-preflight/verify-v0.agent0.7-window-preflight-device-read-only-20260701-165639.txt`,
and
`hard-rom/inspect/v0.agent0.7-window-preflight/post-flash-focus-accessibility-v0.agent0.7-window-preflight-20260701-165715.txt`.
The v0.agent0.8 One Step accessibility-node candidate evidence is
`hard-rom/inspect/v0.agent0.8-onestep-a11y-nodes/build-v0.agent0.8-onestep-a11y-nodes-20260701-185031.txt`
and
`hard-rom/inspect/v0.agent0.8-onestep-a11y-nodes/verify-v0.agent0.8-onestep-a11y-nodes-offline-image-20260701-190024.txt`.
The live v0.agent0.8 flash/read-only/smoke evidence is
`hard-rom/inspect/v0.agent0.8-onestep-a11y-nodes/flash-v0.agent0.8-onestep-a11y-nodes-20260701-191116.txt`,
`hard-rom/inspect/v0.agent0.8-onestep-a11y-nodes/boot-wait-v0.agent0.8-onestep-a11y-nodes-20260701-191116.txt`,
`hard-rom/inspect/v0.agent0.8-onestep-a11y-nodes/verify-v0.agent0.8-onestep-a11y-nodes-device-read-only-20260701-191628.txt`,
and
`hard-rom/inspect/v0.agent0.8-onestep-a11y-nodes/one-step-smoke-20260701-191739/report.txt`.
The live v0.agent0.9 worker/a11y-target evidence is
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/build-v0.agent0.9-worker-a11y-targets-20260701-193038.txt`,
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/verify-v0.agent0.9-worker-a11y-targets-offline-image-20260701-193733.txt`,
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/preflight-v0.agent0.9-worker-a11y-targets-20260701-194145.txt`,
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/flash-v0.agent0.9-worker-a11y-targets-20260701-194953.txt`,
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/verify-v0.agent0.9-worker-a11y-targets-device-read-only-20260701-195505.txt`,
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/one-step-smoke-normalized-20260701-195625/report.txt`,
and
`hard-rom/inspect/v0.agent0.9-worker-a11y-targets/settings-task-20260701-195648/report.md`.
The live v0.agent0.10 finish-target evidence is
`hard-rom/inspect/v0.agent0.10-finish-target-verify/build-v0.agent0.10-finish-target-verify-20260701-203435.txt`,
`hard-rom/inspect/v0.agent0.10-finish-target-verify/verify-v0.agent0.10-finish-target-verify-offline-image-20260701-204145.txt`,
and
`hard-rom/inspect/v0.agent0.10-finish-target-verify/preflight-v0.agent0.10-finish-target-verify-20260701-204456.txt`;
flash/read-only evidence is
`hard-rom/inspect/v0.agent0.10-finish-target-verify/flash-v0.agent0.10-finish-target-verify-20260702-140853.txt`,
`hard-rom/inspect/v0.agent0.10-finish-target-verify/boot-wait-v0.agent0.10-finish-target-verify-20260702-140853.txt`,
and
`hard-rom/inspect/v0.agent0.10-finish-target-verify/verify-v0.agent0.10-finish-target-verify-device-read-only-20260702-141359.txt`;
initial blocked Settings diagnostic evidence is
`hard-rom/inspect/v0.agent0.10-finish-target-verify/settings-task-20260702-141444/report.md`;
accepted Settings rerun evidence is
`hard-rom/inspect/v0.agent0.10-finish-target-verify/settings-task-rerun-20260702-142354/report.md`.

Next Agent gate:
the first MiMo vision smoke has passed with a one-step `finish` action and no
UI manipulation. The first constrained Settings tap task on v0.agent0 was a
diagnostic FAIL: MiMo identified the gray gear Settings icon, but returned y
coordinates that were too high, the runtime injected valid-but-wrong taps, and
then accepted `finish` even though the foreground app stayed Smartisax Shell.
The live guard build is now `v0.agent0.1-vision-guard`: Smartisax
0.7.1/versionCode 52 with post-action observations, screenshot fingerprints,
coordinate edge guard, repeated no-change tap pause, finish gating after UI
actions, and richer visible transcript output. Build/offline/live verification
passed with sparse hash
`4456d0b9e3d2b05a05bebfca08424a4ee4dd5f61d3240a83a93b2a7dfb9b6458`.
The post-flash Settings task did not open Settings, but it did prove the guard:
the run ended `paused`, `5/5`, `max_steps_reached`, with ShellActivity still
focused and per-step post-check transcript visible instead of a false
`complete`. `v0.agent0.2-one-step` then proved the model uses `one_step`, but
the safe "enter One Step then exit it" smoke exposed an execution-layer wait
bug. `v0.agent0.3-one-step-bind-wait` repaired that path and the clean rerun now
passes: `one_step(enter)`, `one_step(exit)`, then `finish`, final state
`complete`. The broader Settings-open task on v0.agent0.3 still did not open
Settings; it paused at `5/5` with `max_steps_reached` after repeated HOME
actions, because SmartisaxShell can remain the HOME target.
`v0.agent0.4-home-onestep-settings-guard` has now been flashed and read-only
verified: Smartisax 0.7.4/versionCode 55, APK hash
`d200a807710af02604038050a2d6f460051e19a34e18a5b334f7b65ec4cabd6a`,
system_b hash `bf4c989ecd162fbcdca4d4122fc376d0444031f0def4ce658b35cad8022d8873`,
sparse hash `c3aa40da9294a3db7e28aa81e91bfd244b717d11a0c96fd71b1b1b28d2107fc5`,
flash result `PASS_FLASH_V0AGENT04_HOME_ONESTEP_SETTINGS_GUARD`, and read-only
result `PASS_READ_ONLY_V0AGENT04_HOME_ONESTEP_SETTINGS_GUARD`. The Settings
clean rerun opens One Step, then pauses at `coordinate_edge_guard` on
`tap(9275,250)`.

`v0.agent0.5-reobserve-on-screen-change` has now been flashed and read-only
verified:
Smartisax 0.7.5/versionCode 56, APK hash
`6e1aba0b426957bc88b561dfc4cc40677a8f42c5fde1b908f9896a5a1879e45f`,
system_b hash `90622eefcf994ebbf5f58aeca9cb4f7bd67b67e9782b7a24d983f8f5de16e8e1`,
sparse hash `09c157326d12dd95b5b0aaaa7783daebb0292e46cd1fb064923cd33654f17f47`,
flash result `PASS_FLASH_V0AGENT05_REOBSERVE_ON_SCREEN_CHANGE`, and read-only
result `PASS_READ_ONLY_V0AGENT05_REOBSERVE_ON_SCREEN_CHANGE`. Post-flash focus
is Smartisax Shell and `isKeyguardShowing=false`.

The live v0.agent0.5 Settings-open smoke is still diagnostic FAIL, but it
narrows the failure. MiMo now emits non-edge top-strip taps such as
`tap(9100,1700)` and `tap(9250,1700)` against the visible One Step Settings
gear, and the runtime correctly pauses with
`repeated_tap_no_screen_change` instead of false-completing. A manual
`input tap 982 398` probe on the apparent gear area also left focus on
`com.smartisax.browser/.ShellActivity`.

`v0.agent0.6-accessibility-tree` has now been built, offline verified,
live-preflighted, flashed to B slot, read-only verified, and Accessibility
probed:
Smartisax 0.7.6/versionCode 57, APK hash
`a0109ab1ceaea4c6039eb43227c5c601edb5464bda52f2a7e889c39964387389`,
system_b hash `143cc0674a8d451d76d63b4c9d61a8bda857310d5d26a6eb84f0ce19ff1269b9`,
sparse hash `8f9c050815555ca38c0c7aa35fb3ed88497f4680e57ad8e15a3d75072c298fa7`,
build result `PASS_BUILD_V0AGENT06_ACCESSIBILITY_TREE`, offline result
`PASS_OFFLINE_IMAGE_V0AGENT06_ACCESSIBILITY_TREE`, and extra checks
`PASS_AGENT0_OFFLINE_TESTS` / `agent06_extra_offline_checks=ok`. Flash result
is `PASS_FLASH_V0AGENT06_ACCESSIBILITY_TREE`, and read-only result is
`PASS_READ_ONLY_V0AGENT06_ACCESSIBILITY_TREE`. Post-flash proof includes
`sys.boot_completed=1`, slot `_b`, bootanim `stopped`, verified boot `orange`,
root available, SELinux Enforcing, device APK hash match,
`accessibility_enabled=1`, enabled service
`com.smartisax.browser/com.smartisax.browser.SmartisaxAccessibilityService`,
and `dumpsys accessibility` showing the Smartisax service bound with the
Smartisax window active/focused. The current flashed Shell header screenshot
still says `SMARTISAX 0.7.5` despite PackageManager reporting 0.7.6; source
metadata is corrected to 0.7.6 and will show on-device only after the next
rebuild/flash.

Latest v0.agent0.6 Settings task diagnostic:
the MiMo task did not reach a model action because the device had no usable
Internet/DNS path (`unknown host api.xiaomimimo.com`, `Network is
unreachable`) and stayed at `running step=0/5`. Manual One Step entry proved
the top strip is visually present and includes the gear-shaped Settings icon,
but the current Agent-accessible tree does not expose a Settings `click_node`.
`uiautomator`/active-root search only found the Agent goal input, while
`dumpsys accessibility` saw separate unknown overlay windows and
`dumpsys window` confirmed visible `com.smartisanos.sidebar` top/right
surfaces.

Previous live v0.agent0.7 line:
`v0.agent0.7-window-preflight` is built, offline verified, preflighted, flashed,
and read-only verified. A confirmed flash attempt was first blocked before
mutation because the R2 was not visible over ADB or fastboot; after USB
reconnect, the confirmed retry flashed successfully. It updates Smartisax to
v0.7.7/versionCode 58, collects
Accessibility active root plus `getWindows()` interactive-window roots, extends
`click_node` lookup across those roots, writes a visible `planning` transcript
entry before provider calls, and pauses with normalized provider network/DNS/
timeout reasons instead of silently remaining at `running step=0/5`. APK hash
is `68b9cc0da7fd8e8d03ac4606fb9dd46329993af05b92896890d787db5317a74b`,
system_b hash is
`4c1cee130f776f3fe83340dbef7592cc56ea4e37446aefa548f5cf3f378bc892`, and sparse
hash is `d16518056abea641cf51e8d944eb517a00dfdbd3d4ba7ef44a5cbad30400c7cc`.
ADB was still offline during preflight, so live state was skipped and no device
mutation happened. After exact confirmation, the flash helper then failed at
`adb reboot bootloader` with `device 'bb12d264' not found`, before any
`fastboot flash`, `fastboot erase misc`, or reboot-from-fastboot step. The
successful retry flashed sparse `super` chunks 1/9 through 9/9, erased `misc`,
rebooted, reached `sys.boot_completed=1` on slot `_b`, and passed
`PASS_READ_ONLY_V0AGENT07_WINDOW_PREFLIGHT`. Post-flash focus is Smartisax
Shell, `isKeyguardShowing=false`, and the Smartisax Accessibility service is
enabled.

Latest live v0.agent0.7 Settings/getWindows diagnostic:
after the USB reconnect, a clean Settings task reached MiMo and produced
`one_step(enter) 95%`, but paused at `one_step_enter_not_visible`. During that
task, WindowManager listed Sidebar windows, while One Step globals stayed
`side_bar_zoom_type=-1` and `sidebar_switch_status=0`, so Accessibility only
showed StatusBar plus Smartisax. A direct manual enter also did not change the
globals until the UI state was normalized by collapsing statusbar, dismissing
keyguard, going HOME, restarting ShellActivity, then issuing exit+enter
WindowManager transacts. In that normalized visible state, `dumpsys
accessibility` exposed two One Step `UNKNOWN_-1` overlay windows, and the
Smartisax Agent panel reported `One Step=visible right` plus
`A11y=91 nodes / 4 roots / 3 windows`. This proves v0.agent0.7 `getWindows()`
can see visible One Step overlay roots, but those roots still do not expose a
usable `Settings`/`设置`/`com.android.settings` node for `click_node`.

Next gate: repair the operator experience around the accepted path. The Shell
Agent panel should auto-refresh running transcript/status so a live task does
not look stuck until manual Refresh/Stop, and One Step entry should preflight or
normalize keyguard/readiness before invoking `one_step enter`. Keep Portal
WebRTC DataChannel regression as a separate follow-up gate after explicitly
enabling/pairing Portal again.

## Active Work Pointers

The active live ROM line is
`v0.agent0.10-finish-target-verify`; the previous live Agent line is
`v0.agent0.9-worker-a11y-targets`, and the previous live Portal
performance line is
`v0.portal6g-rvfc-media-tail`, which was flashed to B slot after exact
confirmation, boots cleanly, and read-only verifies. The 6g live line retains
`v0.usb2` USB/CD-ROM cleanup,
`v0.kg1-smartisax-skip-keyguard` PackageManager/framework behavior,
`v0.wadb2.2-smartisax-wireless-adb-binder-transact` Smartisax wireless ADB
control, the v0.portal4c Portal session hardening, the v0.portal5j.2 raw Binder
MediaProjection token repair, v0.portal5k.1's fresh timestamp
projection-texture baseline, v0.portal5l's visible touch-to-photon marker and
down/move/up stream injection, v0.portal5m's predictive marker status plus
compact `touchMoveBatch` acks, v0.portal5n's latest-frame-only queue collapse
plus dual move DataChannel, v0.portal5o/v0.portal5p input-frame boosts,
v0.portal5r/v0.portal5s 60/90Hz event-time input-priority capture,
v0.portal5u's marker-burst reschedule-until-accepted repair, v0.portal5v's
receiver presentation cadence, v0.portal5w's quiet presentation surface,
v0.portal5x's canvas presenter surface, v0.portal5y's presentation/transport
pacing split, v0.portal5z's video-primary ROI probe, and v0.portal6a marker
draw-sync boost, plus v0.portal6b's draw-urgent input-frame boost and
v0.portal6c's real Portal screenBox repair and v0.portal6d's display wake
guard, v0.portal6e's 1080/60 encoder/transport burst repair, and
v0.portal6f's presentation-tail cadence repair. It now adds the exact 1080/60
RVFC/media callback tail branch:
`1080p60-rvfc-media-callback-tail-dephase+sender-59fps+7mbps-window+full-frame-forceFrame-spacing`.
The 1080/60 smoke profile explicitly preserves `inputRefreshHz=90`, the
sender is capped to 59fps, the 1080p60 target/max bitrate window is narrowed
to 7000000bps, and continuity/marker tail forceFrame cadence is spaced at a
full media-frame interval. It exposes `mediaCallbackTailRepair`,
`mediaCallbackTailFrameSpacingMs`, and `senderMaxFramerate` diagnostics.
Its services.jar policy grants
`READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and `MANAGE_MEDIA_PROJECTION` to
`com.smartisax.browser`; live read-only verification proves all three are
`granted=true`. `WAKE_LOCK` is also granted. `INJECT_EVENTS` remains ungranted
by this policy.

Smartisax live is v0.6.33/versionCode 50 from
`/system/priv-app/SmartisaxShell`. Hashes: APK
`442276dfaf1e70ecf0209818ed61b207bae72194fc490f8c601471b6a43f9f6a`,
system_b `941c660259f32270eaf4e3a8a5778b8518d4035e0f5efb73a8b704fd7d4b4241`,
sparse `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`.
Build result is `PASS_BUILD_V0PORTAL6G_RVFC_MEDIA_TAIL`; offline result is
`PASS_OFFLINE_IMAGE_V0PORTAL6G_RVFC_MEDIA_TAIL`; live read-only result is
`PASS_READ_ONLY_V0PORTAL6G_RVFC_MEDIA_TAIL`; flash result is
`PASS_FLASH_V0PORTAL6G_RVFC_MEDIA_TAIL`.
Post-boot checks prove slot `_b`, boot_completed=1, bootanim stopped, verified
boot orange, root with SELinux Enforcing, Smartisax Shell resumed,
isKeyguardShowing=false, and the device APK/libwebrtc hashes match the
candidate. A post-flash display/window probe proves `mWakefulness=Awake`,
`mDisplayReady=true`, display power `state=ON`, and the ShellActivity window is
on-screen/visible. Flash/boot/read-only evidence:
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/flash-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/boot-wait-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
and
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-device-read-only-20260629-204302.txt`.
Focus/keyguard and display evidence:
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/post-flash-focus-v0.portal6g-rvfc-media-tail-20260629-203737.txt`
and
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/display-window-state-after-flash-20260629-204340.txt`.

Fresh-code 6f strict smoke with pairing code `176725` was run through a
Safari fallback browser wrapper because Google Chrome is not installed at
`/Applications/Google Chrome.app`. It passed both strict profiles as a real
Safari visibility/playback/control/T2P gate: 1080/60 selected H264, displayed
1080x2340, decoded 3855 frames at 59.77fps, packetLossDelta 0, RVFC 55.65fps,
RVFC gaps over 34ms 18, move-stream PASS, and T2P p50/p95/max
115.5/116.85/117ms. 1080/90 selected H264, displayed 1080x2340, decoded 3855
frames at 59.93fps, packetLossDelta 0, RVFC 56.16fps, RVFC gaps over 34ms 10,
move-stream PASS, and T2P p50/p95/max 128/140.6/142ms. Summary evidence:
`hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-safari-176725/projection-texture-summary.md`.
This does not close the Chrome-specific presentation-gap comparison; Safari
reports playoutDelayHint/jitterBufferTarget unsupported, so use a fresh pairing
code with a supported Chrome/Chromium runner if the next question is Chrome
RVFC/presentation cadence.

Fresh-code 6f Chrome-side cadence smoke with pairing code `998599` was then run
through the Codex in-app browser at a temporary 540x1170 viewport. It is
diagnostic FAIL overall because 1080/60 still misses the RVFC gap gate, but it
proves the device/input path is no longer the main blocker. 1080/60 selected
H264, displayed 1080x2340, decoded 3878 frames at 59.76fps, packetLossDelta 0,
RVFC 51.2fps, RAF 60fps, T2P p50/p95/max 102.95/124.42/126.8ms, and
move-stream PASS; the single failing gate is RVFC gaps over 34ms = 123 against
the <=60 requirement. 1080/90 selected H264, displayed 1080x2340, decoded 3874
frames at 59.93fps, packetLossDelta 0, RVFC 53.79fps, RVFC gaps over 34ms 63,
T2P p50/p95/max 113.55/129.26/131ms, and PASS. Summary evidence:
`hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-iab-998599/projection-texture-summary.md`.
Unlike Safari, the in-app browser run applied receiver playoutDelayHint and
jitterBufferTarget. The next optimization should target RVFC/media callback
tail clustering and receiver presentation cadence, especially 1080/60
`frameGapsOver34ms`, rather than adding more input boost.

Fresh-code 6e strict smoke with pairing code `666132` has run and is
diagnostic FAIL, not accepted. The run proves the 1080/60 packet-loss and
encoder/transport burst repair direction: 1080/60 packetLossDelta is now 0,
down from v0.portal6b's 560. The remaining strict blockers are video
presentation/RVFC cadence and marker-visible T2P tail. Summary evidence:
`hard-rom/inspect/v0.portal6e-encoder-transport-burst/portal-encoder-transport-burst-smoke-live/projection-texture-summary.md`.

6f build/offline/preflight evidence:
`hard-rom/inspect/v0.portal6f-presentation-tail-cadence/build-v0.portal6f-presentation-tail-cadence-20260625-190344.txt`,
`hard-rom/inspect/v0.portal6f-presentation-tail-cadence/verify-v0.portal6f-presentation-tail-cadence-offline-image-20260625-190751.txt`,
and
`hard-rom/inspect/v0.portal6f-presentation-tail-cadence/preflight-v0.portal6f-presentation-tail-cadence-20260625-191141.txt`.

6g build/offline/preflight/flash/read-only evidence:
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/build-v0.portal6g-rvfc-media-tail-20260629-202323.txt`,
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-offline-image-20260629-202657.txt`,
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/preflight-v0.portal6g-rvfc-media-tail-20260629-202908.txt`,
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/flash-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/boot-wait-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-device-read-only-20260629-204302.txt`,
and
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/display-window-state-after-flash-20260629-204340.txt`.
It updates Smartisax to v0.6.33/versionCode 50, APK hash
`442276dfaf1e70ecf0209818ed61b207bae72194fc490f8c601471b6a43f9f6a`,
system_b hash
`941c660259f32270eaf4e3a8a5778b8518d4035e0f5efb73a8b704fd7d4b4241`,
and sparse hash
`d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`.
It specifically targets Chrome-side/in-app-browser RVFC media callback tail
cadence by making the 1080/60 smoke profile explicitly preserve
`inputRefreshHz=90`, de-phasing the exact 1080p60 sender to 59fps, narrowing
that sender window to 7Mbps, and spacing continuity forceFrame cadence at a
full media-frame interval. Flash was performed only after the exact
confirmation phrase `确认刷入 v0.portal6g-rvfc-media-tail B 槽`.

After the confirmed flash and read-only verification, the next gate is the
strict in-app browser or supported Chrome/Chromium smoke with a fresh pairing
code:
`tools/r2-portal6g-rvfc-media-tail-smoke.sh --url http://192.168.31.103:37601 --code <new-code> --chrome <chrome-or-browser-wrapper>`.
The target remains reducing 1080/60 `frameGapsOver34ms` from 123 to <=60 while
preserving packetLossDelta 0, T2P p95 around 125ms, and DataChannel ack p95
around 13ms.

Pairing codes `829543` and `808364` were consumed on 2026-06-30 by attempted
in-app-browser 6g strict smoke runs. `829543` could not create/attach a receiver
tab. `808364` used manual-open fallback after the user opened the in-app
browser, but 1080/60 (`http://127.0.0.1:60826/`) and 1080/90
(`http://127.0.0.1:60958/`) both timed out after `180000ms` without WebRTC
answers. Pair/config/probe and runtime config passed, but no decoded frames,
RVFC, DataChannel ack, or T2P sample was produced. Treat both as
`CONTROL_FAIL`, not as 6g performance results. Evidence:
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-iab-829543/`
and
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-iab-808364/`.

The same already paired Portal tab was then measured directly at
`http://192.168.31.103:37601/`. That direct-in-Portal diagnostic is valid for
connectivity, packet loss, RVFC/RAF, and DataChannel input: both profiles
connected with H264 1080x2340 and packetLossDelta 0; 1080/60 decoded 55.66fps
with RVFC gaps over 34ms = 61, while 1080/90 decoded 57.36fps with gaps = 83.
Move acks and touchEnd acks were 8/8 on both profiles, and RAF had 0 gaps over
34ms. Pixel T2P was disabled because the first marker-pixel probe stalled under
the in-app-browser automation path, so keep this as diagnostic evidence and
next build a durable direct-in-Portal harness with non-blocking marker sampling.
Evidence:
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-direct-in-app-browser-20260630-808364-session/`.

Fresh-code Safari strict smoke with pairing code `223229` consumed the code and
is diagnostic FAIL overall only because 1080/90 was visibility-contaminated.
1080/60 is strict Safari PASS: H264 1080x2340, decoded 57.94fps,
packetLossDelta 0, RVFC 56.18fps, RVFC gaps over 34ms = 6, RAF 60.01fps,
T2P p50/p95/max 133/149.2/151ms, ping ack p50/p95 9/14ms, move-stream PASS,
marker draw-sync PASS, inputFrameBoost PASS, urgent PASS, and no hidden/blur
events. 1080/90 kept packetLossDelta 0, decoded 59.72fps, T2P p95 135.8ms,
move-stream PASS, and marker/input boost PASS, but the receiver page entered
hidden/unfocused state around 33s (`blur` about 33315ms and
`visibilitychange hidden` about 33642ms), after which RVFC fell to 38.93fps and
gaps rose to 163. Treat 1080/90 as `VISIBILITY_CONTAMINATED`, not as a clean
6g media-cadence failure. Evidence:
`hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-safari-223229/projection-texture-summary.md`.

Next Portal work should keep 1080/60 as accepted Safari strict evidence, then
rerun 1080/90 only with receiver foreground pinning or an explicit visibility
guard that aborts contaminated samples. In parallel, convert the direct
`http://192.168.31.103:37601/` Portal path into a strict schema harness so
paired real-Portal sessions can be measured without the localhost receiver-tab
attach failure.

6d build/offline evidence:
`hard-rom/inspect/v0.portal6d-display-wake-guard/build-v0.portal6d-display-wake-guard-20260625-155951.txt`
and
`hard-rom/inspect/v0.portal6d-display-wake-guard/verify-v0.portal6d-display-wake-guard-offline-image-20260625-160303.txt`.

The real Portal Chrome visual smoke on the previous v0.portal6c did connect
and decode H264
at 1080x2340 with both WebRTC input channels open, and the real screenBox was
visible and non-collapsed. It still failed because the video pixels were flat
black. Read-only ADB evidence showed the R2 was asleep
(`mWakefulness=Asleep`, `mGlobalDisplayState=OFF`) and ADB `screencap` itself
was black; an ADB wake probe changed the display state to ON and normal Shell UI
returned. Evidence is in
`hard-rom/inspect/v0.portal6c-visible-screenbox/portal-real-ui-visual-smoke-live/`.

The fresh-code real Portal visual smoke on live 6d now passes. Evidence:
`hard-rom/inspect/v0.portal6d-display-wake-guard/portal-real-ui-visual-smoke-live/real-portal-visual-smoke-v0.portal6d-display-wake-guard-20260625-083527.json`
and
`hard-rom/inspect/v0.portal6d-display-wake-guard/portal-real-ui-visual-smoke-live/real-portal-visual-smoke-v0.portal6d-display-wake-guard-20260625-083527.png`.
It proves pairState `paired`, H264 answer applied, video `1080x2340`,
readyState `4`, screenBox `1170px contain=layout paint aspect=1080 / 2340`,
pixelRange `233.33`, pixelBuckets `89`, and both input DataChannels open.
Post-smoke display evidence is
`hard-rom/inspect/v0.portal6d-display-wake-guard/display-wake-state-after-real-portal-smoke-20260625-083527.txt`;
it proves `mWakefulness=Awake`, `mGlobalDisplayState=ON`, built-in display
`state ON`, and `SmartisaxWebRtcProjection` virtual display `state ON`.

v0.portal6e-encoder-transport-burst is the previous live flashed/read-only line
for the first returned performance gate. It starts from live/read-only 6d,
updates Smartisax to v0.6.31/versionCode 48, clamps the 1080p60/90 WebRTC
sender bitrate window, sets sender degradation preference to maintain
framerate, and late-starts the projection frame pump after local SDP. Build,
offline-image verifier, read-only live preflight, flash, and read-only device
verifier all pass. Evidence:
`hard-rom/inspect/v0.portal6e-encoder-transport-burst/build-v0.portal6e-encoder-transport-burst-20260625-165309.txt`,
`hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-offline-image-20260625-170017.txt`,
`hard-rom/inspect/v0.portal6e-encoder-transport-burst/preflight-v0.portal6e-encoder-transport-burst-20260625-170235.txt`,
`hard-rom/inspect/v0.portal6e-encoder-transport-burst/flash-v0.portal6e-encoder-transport-burst-20260625-171510.txt`,
and
`hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-device-read-only-20260625-172037.txt`.
Hashes: APK
`90421ef5613f5dafa5491735848ebe6588e2fe5d95ffb79929bfe00329a921ef`,
system_b `04cfe9746848f5daee752a13efb18ba3cb938d8c7969d5b48333c965f319a6b7`,
sparse `5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83`.
Strict smoke result with code `666132`: diagnostic FAIL. 1080/60 used H264
1080x2340, frame pump 1080x2340@60, packetLossDelta 0 PASS, but decoded at
54.54fps, RVFC 41.92fps, had 158 RVFC gaps over 34ms, and T2P p50/p95
347.5/471.07ms. 1080/90 used H264 1080x2340, requested 90Hz input with 60fps
video transport, decoded at 59.14fps PASS, T2P p50/p95 138.55/163.98ms PASS,
but packetLossDelta was 2 and RVFC stayed at 47.7fps with 126 gaps over 34ms.
It led directly to the current live 6f RVFC/presentation-cadence and 1080/60
marker-visible T2P-tail candidate; the next proof is the 6f strict smoke with
a fresh pairing code.

Previous v0.portal6a evidence remains:
`hard-rom/inspect/v0.portal6a-marker-draw-sync/flash-v0.portal6a-marker-draw-sync-20260625-013740.txt`,
`hard-rom/inspect/v0.portal6a-marker-draw-sync/boot-wait-v0.portal6a-marker-draw-sync-20260625-013740.txt`,
`hard-rom/inspect/v0.portal6a-marker-draw-sync/verify-v0.portal6a-marker-draw-sync-device-read-only-20260625-014307.txt`,
`hard-rom/inspect/v0.portal6a-marker-draw-sync/build-v0.portal6a-marker-draw-sync-20260625-011529.txt`,
and
`hard-rom/inspect/v0.portal6a-marker-draw-sync/verify-v0.portal6a-marker-draw-sync-offline-image-20260625-012011.txt`.

v0.portal6b strict smoke remains the performance diagnostic boundary and is not
accepted:
`hard-rom/inspect/v0.portal6b-draw-urgent-boost/portal-draw-urgent-boost-smoke-live/projection-texture-summary.md`.
Both profiles connected with H264, projection-texture 1080x2340, input PASS,
move-stream PASS, marker draw-sync PASS, and draw-urgent counters PASS.
1080/60 decoded 3602 frames at 55.03fps but failed RVFC 43.78fps,
packet-loss delta 560, 127 RVFC gaps over 34ms, and T2P p50/p95
189.8/197.99ms. 1080/90 decoded 3872 frames at 59.64fps with packet-loss delta
0 and RVFC 50.39fps, but failed 102 RVFC gaps over 34ms and T2P p50/p95
183.75/186.86ms. The draw-urgent mechanism is proven by counters:
1080/60 had urgent requests/frames 4/4 and 1080/90 had 4/4. Next proof should
repair 1080/60 packet loss and encoder/transport burst first, then reduce RVFC
gap cadence and marker-visible T2P tail rather than adding more input boosts.

v0.portal5z strict smoke comparison evidence is in
`hard-rom/inspect/v0.portal5z-video-primary-roi-probe/portal-video-primary-roi-probe-smoke-live/projection-texture-summary.md`.

v0.portal5z strict smoke is diagnostic FAIL, not accepted. Both profiles
connected with H264, projection-texture 1080x2340, input PASS, move-stream PASS,
and input-frame-boost PASS. The original 5z smoke showed 1080/60 decoding
59.3fps but RVFC at 31.41fps, packet-loss delta 4, 95 RVFC gaps over 34ms, and
T2P p50/p95 153.9/192.96ms; 1080/90 decoded 59.38fps with packet-loss delta 0
and RAF 59.99fps, but RVFC was 49.09fps, RVFC gaps over 34ms were 111, and T2P
p50/p95 was 357.7/401.98ms. After adding Chrome anti-throttle launch flags,
fixed window sizing, compact summary output, and page lifecycle/RVFC/RAF
timeline fields, a no-flash rerun against current 5z kept packet-loss delta 0
on both profiles and RAF near 60fps. It moved 1080/60 to decoded 59.76fps,
RVFC 49.79fps, 79 RVFC gaps over 34ms, ping p50/p95 16.6/95.31ms, and T2P
p50/p95 409.25/591.54ms; 1080/90 reached decoded 60.03fps, RVFC 48.38fps,
146 RVFC gaps over 34ms, ping p50/p95 14.95/95.55ms, and T2P p50/p95
189.1/214.03ms. `document.hidden` stayed false and RAF stayed clean, so treat
the original 22s-class presentation gap as host-window/background noise, but
continue treating video RVFC cadence and marker-visible tail latency as the real
remaining blocker. The smoke harness now also tries to foreground Chrome after
launch; that foreground path still needs a fresh pairing code or explicit Portal
restart before it can be validated.

v0.portal5y strict smoke is the previous diagnostic FAIL boundary, not accepted,
but it moved the
transport boundary. Both 1080/60 and 1080/90 connected with H264,
projection-texture 1080x2340, input PASS, move-stream PASS,
input-frame-boost PASS, and packet-loss delta 0. 1080/60 decoded 60.04fps with
RVFC 43.5fps, 21 RVFC gaps over 34ms, RAF 60fps, canvas draw 59.95fps, ping
ack p50/p95 15.8/101.39ms, and T2P p50/p95 205.35/253.82ms. 1080/90 decoded
55.14fps with RVFC 31.45fps, 91 RVFC gaps over 34ms, max frame delta
14016.7ms, 133 dropped frames, 15 freezes, 7080ms freeze time, ping ack
p50/p95 16.65/97.78ms, and T2P p50/p95 175.15/176.99ms. Treat this as proof
that 90Hz input plus 60fps transport removes packet loss, while the remaining
repair path is the 5z video-primary ROI probe: reduce Chrome/smoke-page
observation overhead first, then measure whether real presentation/main-thread
freeze, RVFC/media-change cadence, and T2P tail latency move.

v0.portal5o strict-smoke follow-up was diagnostic rather than fully accepted.
The full 1080/30 plus 1080/60 run failed: the 1080/30 profile had no
touch-to-photon detections and no move events in that sequence, while 1080/60
then saw RVFC below gate and packet-loss delta 4. Clean single-profile reruns
show the important split. 1080/60 passes and is the best measured latency point
so far: H264 1080x2340, decoded fps 60.2, RVFC 54.2fps, packet-loss delta 0,
gaps over 34ms 56, move-stream 30/30, `inputFrameBoostRequests=14`,
`inputFrameBoostFrames=14`, and touch-to-photon p50/p95 133.25/138.51ms. The
1080/30 single-profile rerun keeps decoded fps 29.84, RVFC 27.76fps,
packet-loss delta 0, move-stream 30/30, and input boost proof, but fails the
strict gates with 911 gaps over 34ms and touch-to-photon p50/p95
181.85/205.66ms. Treat this as proof that the 5o boost helps, especially at
60Hz cadence, but that 30fps still loses about one frame of input-to-capture
budget.

The strict v0.portal5n latency-budget smoke passes both profiles with
`smartisax-input-move` open. 1080/30 projection-texture H264 decodes 1989
frames at 29.85fps with packet-loss delta 0, RVFC 23.99fps, 273 gaps over 34ms,
move events 30/30, ping ack p50/p95 18.05/144.41ms, and touch-to-photon
p50/p95 221.7/221.7ms from 1/2 detections. 1080/60 decodes 3875 frames at
59.33fps with packet-loss delta 2, RVFC 45.23fps, 46 gaps over 34ms, 34 gaps
over 50ms, move events 30/30, ping ack p50/p95 16.05/91.73ms, and
touch-to-photon p50/p95 205.85/208.6ms. Compared with v0.portal5m, 1080/60 gap
count and ping p95 improved, but T2P regressed from 154.45/158.1ms and RVFC got
worse, so queue collapse alone is not accepted as the final latency repair.

v0.portal5s strict smoke is diagnostic, not accepted. The full 1080/60 plus
1080/90 run connected both profiles with H264, packet-loss delta 0,
move-stream PASS, and input-frame-boost PASS. 1080/60 decoded 3944 frames at
60.01fps with 19 input boost frames and T2P p50/p95 160.1/165.86ms, but failed
RVFC 44.46fps, 117 gaps over 34ms, and the strict 165ms T2P p95 gate. 1080/90
decoded 5568 frames at 85.14fps with 18 input boost frames and only 33 gaps
over 34ms, but failed RVFC 31.62fps and T2P p50/p95 213.6/298.92ms. A clean
single-profile 1080/60 rerun still failed: decoded 3947 frames at 60.13fps,
packet-loss delta 0, 34 gaps over 34ms, move-stream PASS, and 21 input boost
frames, but RVFC was 47.98fps and touch-to-photon p50/p95 regressed to
266.85/370.85ms. Treat 5s as a live/read-only proven experiment that exposes
the next bottleneck rather than the new latency winner.

v0.portal5w-quiet-presentation is the previous live Portal gate. Its strict
smoke was diagnostic FAIL, not accepted, but it usefully isolated the video
presentation/RVFC path: both 1080/60 and 1080/90 connected with H264,
packet-loss delta 0, move-stream PASS, input-frame-boost PASS, and RAF near
59.9fps, while RVFC/media cadence and marker latency still missed gates.

v0.portal5x-presenter-mode is the previous live Portal gate, flashed to B slot,
read-only verified, strict-smoked after exact confirmation, and then
superseded by v0.portal5y. Strict smoke is
diagnostic FAIL, not accepted, but it moved the latency boundary. Both 1080/60
and 1080/90 connected with H264, move-stream PASS, input-frame-boost PASS, and
RAF/canvas draw near 60fps. 1080/60 decoded 59.8fps with packet-loss delta 0,
RVFC 42.26fps, 167 RVFC gaps over 34ms, canvas gaps over 34ms = 1, and T2P
p50/p95 144.1/173.08ms. 1080/90 decoded 86.64fps but had packet-loss delta
176, RVFC 35.05fps, 310 RVFC gaps over 34ms, canvas gaps over 34ms = 0, and
T2P p50/p95 140.45/143.65ms. Treat this as proof that the visible
canvas-presenter feedback path is much healthier, while the remaining repair
then needed video RVFC/media-change cadence, encoder/transport pacing, and the
fact that the 90fps encoder path still sits on a VirtualDisplay supported mode
reported as `fps=60.0`. v0.portal5y now proves the transport pacing half can
remove packet loss, leaving Chrome presentation/RVFC freeze as the sharper
boundary. For interactive testing, keep H264 as the measured low-latency
default; AV1 remains an explicit experiment, VP9 is too slow, and H265 should
not be preferred until the browser decode path produces frames.
v0.portal5o's clean 1080/60 result remains the latency target to beat: 60.2fps
decoded, RVFC 54.2fps, packet-loss delta 0, gaps over 34ms 56, and T2P
p50/p95 133.25/138.51ms. v0.portal5z has now tested the video-primary ROI probe
against that target and did not beat it; continue with video presentation/RVFC
cadence and marker-visible tail repair.

The previous fully Portal-smoke-proven v0.portal5h hashes are: APK
`d434f4d7ca4a1c3625d27c8788781018b6e349458f4f7eab81a5869b0c999308`,
system_b `1180edf2b4bd401819e4dc3a860b3193d849fc79208b9ef33f5cc768cb0ffa22`,
sparse `9d193755098feb70e283b445aa741412ce35017e28b12931be42015d045a17bd`.
Build result is `PASS_BUILD_V0PORTAL5H_WEBRTC_BITRATE_QUALITY`; offline result
is `PASS_OFFLINE_IMAGE_V0PORTAL5H_WEBRTC_BITRATE_QUALITY`; live read-only
result is `PASS_READ_ONLY_V0PORTAL5H_WEBRTC_BITRATE_QUALITY`; curl smoke result
is `PASS_PORTAL_SMOKE_V0PORTAL5H_CURL`; Chrome smoke proves H.264
ICE/DTLS/SRTP playback, 127 decoded frames in 15s, first frame, DataChannel
ping/tap/swipe acks, and `bitrateApplied=true`. Logcat proves the encoder
accepted explicit bitrate configuration but chose the min value:
`bitrate=600000`.

The previous live v0.portal5i line is built, offline-verified, live-preflighted,
flashed, booted, and read-only verified. It updates Smartisax to
v0.6.7/versionCode 24, keeps the v0.portal5h stable defaults, adds the
token-gated `/api/webrtc/config` runtime config endpoint, and exposes browser
controls for frame width, fps, and min/target/max bitrate. Limits are
maxFrameWidth=1080, maxFps=30, and maxBitrateBps=12000000. Hashes: APK
`8b6c4b7a2bf5e3fb49ff2ceba01427d8d0e1277a80c81d421f29cd73d174f751`,
system_b `f93449427c47e87fb566b30a7c87ee869496b7ec5e01b19b9b1b832b825ade1d`,
sparse `7461215ef7403d005be3fe3c13ec711e9129998d28f11736fd3e1474e304aaf7`.
Build result is `PASS_BUILD_V0PORTAL5I_WEBRTC_RUNTIME_TUNING`; offline result
is `PASS_OFFLINE_IMAGE_V0PORTAL5I_WEBRTC_RUNTIME_TUNING`; live read-only result
is `PASS_READ_ONLY_V0PORTAL5I_WEBRTC_RUNTIME_TUNING`. Post-flash checks prove
boot_completed=1, slot `_b`, Smartisax Shell focused, Keyguard not showing,
READ_FRAME_BUFFER granted, and libwebrtc arm64/arm system libraries intact.
Portal runtime smoke is now complete: `/api/webrtc/config` reports the expected
limits, Stable 540x1170@8 passes with about 8fps decoded and zero packet loss,
Sharp 720x1560@15 passes with about 14fps decoded and three lost packets, and
1080/30 1080x2340@30 passes connection/control but decodes around 11fps. All
three profiles use H.264 WebRTC and pass `smartisax-input` DataChannel
ping/tap/swipe acks. The device was restored to Stable config and
activeSessions=0 afterward.

The previous v0.portal5j line updates Smartisax to
v0.6.8/versionCode 25, adds a MediaProjection + VirtualDisplay + WebRTC
SurfaceTextureHelper capture backend, raises runtime tuning maxFps to 60, adds
token-gated `/api/webrtc/capture/probe`, and adds
`MANAGE_MEDIA_PROJECTION` to the Smartisax privapp permission XML. It keeps the
old Bitmap/I420 path as `projection-auto` fallback. Hashes: APK
`5f23dd62ff25829a02f4bbefdb994d67c13df3a31e02ee733054140e3f621e4e`,
system_b `7d75d7cdcaba49a7cda17daf0fa350f34fa6590cff80984732ca3779bac641a2`,
sparse `d51213324cebd9eca4b7dec58a509618949ebc598dcefa9aff6481f2e2921f28`.
Build result is `PASS_BUILD_V0PORTAL5J_PROJECTION_TEXTURE_PROBE`; offline
result is `PASS_OFFLINE_IMAGE_V0PORTAL5J_PROJECTION_TEXTURE_PROBE`; live
read-only result is a focused failure because the framework does not grant
`MANAGE_MEDIA_PROJECTION`/`CAPTURE_VIDEO_OUTPUT` to Smartisax without a
services.jar signature-permission policy.

The previous live candidate `v0.portal5j.1-projection-permission-grant` keeps the
Smartisax v0.6.8 APK unchanged and replaces only services.jar with a narrow
`SmartisaxPackagePolicy.shouldGrantSignaturePermission(...)` policy for
`com.smartisax.browser`: `READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and
`MANAGE_MEDIA_PROJECTION`. It explicitly does not grant `INJECT_EVENTS`.
Hashes: services.jar
`3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909`,
system_b `b803a6ac467e855ed3b3abb0cd021d0409d6f50c207ebac79ee8d8522b62f136`,
sparse `3a89aca9fb029cc8cddfeba78d163ad533a6578ae13b8c229e54f11daafa39bc`.
Build result is `PASS_BUILD_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT`; offline
result is `PASS_OFFLINE_IMAGE_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT`; live
read-only result is `PASS_READ_ONLY_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT`.
The flash wrote all 9 sparse chunks, erased misc, and rebooted successfully.

The current live v0.portal5g hashes are: APK
`24122dceb927dd6bbc7cdba2da60bccadd90e733bdfd44e192a7eeff74023715`,
system_b `b3cdb42a8d964fd35fa6302bc76e0b041464dacbb291692d06d659bfccb37213`,
sparse `cbe9d5ff93fcf1ab492dbf0a86ee3524daad72ec320f60c30a8588cb1db00cb0`.
Build result is `PASS_BUILD_V0PORTAL5G_WEBRTC_TOUCH_QUALITY`; offline result
is `PASS_OFFLINE_IMAGE_V0PORTAL5G_WEBRTC_TOUCH_QUALITY`; live read-only result
is `PASS_READ_ONLY_V0PORTAL5G_WEBRTC_TOUCH_QUALITY`; curl smoke result is
`PASS_PORTAL_SMOKE_V0PORTAL5G_CURL`; Chrome smoke proves H.264 ICE/DTLS/SRTP
playback, 125 decoded frames in 15s, zero packet loss, 540x1170@8fps frame pump,
and `smartisax-input` DataChannel ping/tap/swipe acks.

The previous live v0.portal5f hashes are: APK
`27a6672dc6abbf8789607d4f92ffb37909095dcefd20d82d11b44cf1c7ef3be3`,
system_b `dbbdb34b39a27420043c0a0b22147bb8709e0d395acdf0359e98b8552f70b9d2`,
sparse `b3b633b97f218a713dd09980b85a8d566914c4ac604121214e1961e2b40a93a0`.
Build result is `PASS_BUILD_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT`; offline
result is `PASS_OFFLINE_IMAGE_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT`; live
read-only result is `PASS_READ_ONLY_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT`;
curl smoke proves pairing/status/capabilities/PNG/MP4 and HTTP `/api/input`
removal; Chrome WebRTC smoke proves H.264 ICE/DTLS/SRTP playback plus
`smartisax-input` RTCDataChannel ping/ack.

The previous live v0.portal5c line proved that Canvas is not a valid conversion
route for `Config#HARDWARE` screenshot bitmaps. v0.portal5d fixes that by using
`Bitmap.copy(ARGB_8888,false)`, the same conversion path already proven by
PNG/MP4, before I420 conversion.

The first v0.portal5j.1 `/api/webrtc/capture/probe` was run and failed before
token creation. The failure is not the services.jar permission grant anymore:
the package has `READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and
`MANAGE_MEDIA_PROJECTION` granted. The current blocker is in
`SmartisaxProjectionCapture`: reflection on hidden
`IMediaProjectionManager$Stub.asInterface(IBinder)` is blocked by Android 11
hidden-API enforcement and throws `NoSuchMethodException`. Evidence lives under
`hard-rom/inspect/v0.portal5j.1-projection-permission-grant/portal-projection-live/`.

The v0.portal5j.2 repair is now built, offline-verified, live-preflighted,
flashed to B slot, booted, and read-only verified. It updates Smartisax to
v0.6.9/versionCode 26 and replaces
the hidden Stub reflection path with raw Binder transact calls for
`hasProjectionPermission` transaction 1 and `createProjection` transaction 2.
Hashes: APK `b1b9f3db5b26e64de5fb469c490b86b9cc2b1fcee35f0353a4376aac2c50998c`,
system_b `5bb2b36d15b6befdfbb0c990b816adbfe488b9e5eafa38463437058635fd6c3b`,
sparse `789bb849e7bc849271958b3b6dd6e01a7c707d06373f6d4d72e88564acd83b66`.
Build result is `PASS_BUILD_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT`; offline
result is `PASS_OFFLINE_IMAGE_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT`; live
result is `PASS_READ_ONLY_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT`.

Live v0.portal5j.2 `/api/webrtc/capture/probe` now passes: HTTP 200,
`ok=true`, `hasProjectionPermission=true`, `binderCreateProjection=available`,
`tokenRoute=raw-binder-transact-media-projection`, and `createProjection=ok`.
Evidence is in
`hard-rom/inspect/v0.portal5j.2-projection-binder-transact/portal-projection-live-rawbinder/`.

The formal 1080/30 and 1080/60 `projection-texture` WebRTC smokes have now run
on live v0.portal5j.2. Both profiles pass connection/control gates:
`/api/webrtc/capture/probe` still reports `createProjection=ok`, Chrome
RTCPeerConnection reaches `connected`, H.264 is selected, browser video reports
1080x2340, packet loss delta is zero, and the `smartisax-input` DataChannel
tap/swipe acks return through `privileged-inputmanager`. They do not pass the
performance target. 1080/30 decodes only 27 frames over the 20s observation
window, estimated about 1.1fps, while the device session reports 80 captured
frames. 1080/60 decodes only 18 frames, estimated about 0.89fps, while the
device session reports 27 captured frames. In both cases frame counters stop
after the initial burst, so the next step is not another profile run; it is a
frame-pump continuity repair.

The v0.portal5k frame-pump continuity repair is now live-flashed and read-only
verified. It starts from v0.portal5j.2, updates Smartisax to
v0.6.10/versionCode 27, keeps the raw Binder MediaProjection token route and
services.jar policy, and uses `SurfaceTextureHelper.forceFrame()` on the helper
handler to keep `projection-texture` feeding WebRTC after the initial
VirtualDisplay burst. Hashes: APK
`4181d040b473a83c12a2be25d07a706e29c5b0e0749487dfd1c9ef13c4c7f619`, system_b
`57302f32c4ccd0f9c1ee9a18791761261d775ef2ac542928871c35236b511958`, sparse
`cc9f9921c510ce471d46a24ac786684b03b7e5bb5cf2d801865bd4d3f8dfe14a`. Build
result is `PASS_BUILD_V0PORTAL5K_FRAME_PUMP_CONTINUITY`; offline result is
`PASS_OFFLINE_IMAGE_V0PORTAL5K_FRAME_PUMP_CONTINUITY`; live read-only result is
`PASS_READ_ONLY_V0PORTAL5K_FRAME_PUMP_CONTINUITY`. The 1080/30 smoke proves
H.264 connection, 1080x2340 browser video, zero packet-loss delta, and
DataChannel tap/swipe, but browser decode stalls at 26 frames while device-side
`capturedFrames=638`, `sourceFrames=718`, and `continuityFrames=633` continue.
1080/60 was intentionally not run after 1080/30 failed.

The previous live Portal performance baseline is
`v0.portal5k.1-frame-timestamp-retain`. It
updates Smartisax to v0.6.11/versionCode 28 and wraps each retained texture
frame with a fresh `System.nanoTime()` timestamp before handing it to WebRTC,
while preserving v0.portal5k's `forceFrame()` cadence. Hashes: APK
`d99026b525f57daa9b7a85ebdca8752e9d2312d11ca485055cec2ec258d0fc35`, system_b
`e1d3dddd36dceea72d2cacc0df2d58ed91669f8680f6738f7b8e4b957c481174`, sparse
`e60e756bc805190ea7e43244fac6c5701be2b4bf0891f3e90d20ac20b524d451`. Build
result is `PASS_BUILD_V0PORTAL5K1_FRAME_TIMESTAMP_RETAIN`; offline result is
`PASS_OFFLINE_IMAGE_V0PORTAL5K1_FRAME_TIMESTAMP_RETAIN`; live read-only result
is `PASS_READ_ONLY_V0PORTAL5K1_FRAME_TIMESTAMP_RETAIN`; smoke evidence proves
1080/30 and 1080/60 `projection-texture` with H.264, 1080x2340, zero
packet-loss delta, fresh timestamp rewrite counters, and `smartisax-input`
tap/swipe. A no-flash 1080/60 latency/input baseline has also passed with
decoded fps 59.99, packet-loss delta 0, DataChannel ping ack p50 15.25ms/p95
71.09ms, tap ack 80.8ms, and swipe ack 21.1ms. The bottleneck to investigate
next is presentation/control feel rather than source frame continuity: RVFC
callback fps was 39.67, frame interval p95 was 49.72ms, and the run recorded
135 gaps over 34ms. Next Portal work is true touch-to-photon marker evidence,
move-stream reverse-control refresh, Chrome presentation-gap investigation,
`projection-auto` fallback/regression, longer-duration stability, default
profile/autostart policy, file APIs, and UI polish. Keep HTTP `/api/input`
removed; use ADB for emergency debug/control.

The previous smoke-proven Portal line `v0.portal5l-touch-photon-move-stream` is built,
offline-verified, live-preflighted, flashed, booted, read-only verified, and
1080/60 touch-to-photon/move-stream smoke verified.
It starts from v0.portal5k.1, updates Smartisax to v0.6.12/versionCode 29, adds a
device-side visible touch-to-photon marker overlay, reports marker region/color
metadata through DataChannel acks/status, and upgrades reverse control from
legacy tap/swipe gestures to `touchStart`/`touchMove`/`touchEnd` down/move/up
stream injection. Hashes: APK
`c7f4487f4bfa2a1b06cc0be4ffeeb81b418b1b9a248200a20849c503b8f1301a`, system_b
`0f8398b5fa42409e104979b8ee37baefe2ba6316ad98283bc6ed763f1b849877`, sparse
`680a8c78299706996a4a96ada98e4c24606d76df94e4683fadeb9ec8780886c9`. Build
result is `PASS_BUILD_V0PORTAL5L_TOUCH_PHOTON_MOVE_STREAM`; offline result is
`PASS_OFFLINE_IMAGE_V0PORTAL5L_TOUCH_PHOTON_MOVE_STREAM`; live read-only result
is `PASS_READ_ONLY_V0PORTAL5L_TOUCH_PHOTON_MOVE_STREAM`; smoke result is PASS.
The flash wrote sparse super chunks 1/9 through 9/9, erased `misc`, rebooted,
and reached `sys.boot_completed=1` on `_b`. The smoke reports H.264 1080x2340,
3922 decoded frames, estimated 60.05fps, packet-loss delta 0, 4188 source
frames, 4075 continuity frames, 4085 captured frames, 103 dropped frames,
30/30 move acks, down/up PASS, and touch-to-photon marker detection 2/2 with
p50 202.85ms, p95 286.59ms, and max 295.9ms.

The previous smoke-proven Portal line `v0.portal5m-latency-follow-rate` is
latency/follow-rate smoke-proven. Build result:
`PASS_BUILD_V0PORTAL5M_LATENCY_FOLLOW_RATE`; offline result:
`PASS_OFFLINE_IMAGE_V0PORTAL5M_LATENCY_FOLLOW_RATE`; live read-only result:
`PASS_READ_ONLY_V0PORTAL5M_LATENCY_FOLLOW_RATE`; smoke result: PASS. It was
flashed to B slot after exact confirmation, wrote sparse super chunks 1/9
through 9/9, erased `misc`, rebooted, and verified boot/package/keyguard/focus
state. Its 1080/30 smoke holds 29.81fps with T2P p95 193.03ms; its 1080/60
smoke holds 59.94fps with T2P p95 158.1ms, ping ack p95 97.04ms, RVFC
52.28fps, and move events 30/30 through batched move acks.

The current live v0.portal4b hashes are: APK
`81470570b23022d30893cb2b4a9b592158c7b94f9fbd056aae806a74b30d84f9`,
system_b `2c06a8295b4fb629464ed28190b4546774e444ed5982b1b9e054be9feb2a0826`,
sparse `2a1b702184d351dc5b74b139f1b2961fb429702d7f857865a07680b3277d9fa6`.
Build result is `PASS_BUILD_V0PORTAL4B_MP4_CONTROL_POLISH`; offline result is
`PASS_OFFLINE_IMAGE_V0PORTAL4B_MP4_CONTROL_POLISH`; live read-only result is
`PASS_READ_ONLY_V0PORTAL4B_MP4_CONTROL_POLISH`; LAN smoke result is
`PORTAL_SMOKE_V0PORTAL4B_COMPLETED`.

The previous live v0.portal4a hashes are: APK
`8e5bc6e1ecea382e93023f3ca7e2db56d3fc40ae3ef7a3b288be7f6b8942c3aa`,
system_b `a9ae296781e159bd353ea77df6582155a1b08743eddcd8f997ccf06382c342da`,
sparse `a1c24a085f604966ddd500a7cb88a26aad81697efc524fbe83d287fbb4243ae3`.

Historical note: v0.portal3c established the accepted direct-LAN HTTP MP4 route
by serving `/api/video/mp4` through Android `MediaMuxer`, allowing desktop
browsers to play the R2 screen through a normal video element without HTTPS.
The raw `/api/video/h264` Annex-B endpoint remains useful for WebCodecs
diagnostics, but it is not the default direct-LAN route because browser
`VideoDecoder` requires a secure context and `http://<r2-ip>:37601` is not one.

The current HandShaker replacement line is `v0.mirror0-scrcpy-live-proof`.
It does not change ROM images. scrcpy 4.0 is installed on the Mac, USB and
wireless no-window recordings pass, ADB input reaches the phone during a
control smoke, and an interactive scrcpy window opens with Metal renderer and
1080x2340 texture. Use `tools/r2-mirror.sh` as the first Mac-side wrapper:
`tools/r2-mirror.sh`, `tools/r2-mirror.sh wireless`, or
`tools/r2-mirror.sh record <output.mp4> [seconds] [usb|wireless|auto]`.
The script also has `tools/r2-mirror.sh connect-wireless` to reconnect the
known Smartisax wireless ADB endpoint when it is already enabled on the phone.
Next Portal step is a v0.portal5s-based repair for Chrome presentation/RVFC
gaps and marker touchEnd tail latency. After building the next candidate, run
read-only verification plus 1080/60 and 1080/90 event-time/input-priority
smoke.
Treat v0.portal5o as the current measured 1080/60 latency comparison line, and
v0.portal5k.1 as the pre-marker continuity baseline.
Persistent Portal autostart, file APIs, broader UI polish, optional
`v0.mirror1-mac-wrapper`, and TNT/Desktop-mode audit remain separate lines.

`v0.portal2.3-smartisax-framebuffer-grant` is flashed and live-proven on B slot.
It keeps Smartisax v0.4.2/versionCode 9 unchanged and replaces only
`/system/framework/services.jar` with a narrow PackageManager policy granting
`android.permission.READ_FRAME_BUFFER` to `com.smartisax.browser`. Live smoke
proves direct LAN browser access without adb forward:
`GET /`, pairing, authorized `/api/status`, `GET /api/screen.png` returning
1080 x 2340 PNG frames, and `POST /api/input` tap/swipe via
`privileged-inputmanager`.

`v0.portal3a-webrtc-capability-probe` is flashed and live-proven on B slot. It
updates Smartisax to v0.5.0/versionCode 10, retains the v0.portal2.3
services.jar hash `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a`,
keeps `/api/screen.png` plus `/api/input`, and adds the token-gated
`/api/media/capabilities` endpoint. Live smoke proves `/api/status` reports
`portalVersion=0.5.0` and `webrtc=capability-probe`, `/api/media/capabilities`
reports screen 1080 x 2340 plus four AVC encoders, three HEVC encoders, and two
hardware AVC encoders, `/api/screen.png` returns PNG frames, and `/api/input`
tap/swipe still uses `privileged-inputmanager`.

`v0.portal3b-h264-http-stream-prototype` is flashed and live-proven on B slot.
It updates Smartisax to v0.5.1/versionCode 11, keeps the v0.portal2.3
services.jar hash `0b0811858d794f22a4e423f26f4ab27248c25fc4e4b1e6cd95362c0f90b9b97a`,
keeps `/api/screen.png`, `/api/input`, and `/api/media/capabilities`, and adds
the token-gated `/api/video/h264` endpoint. Live smoke proves `/api/status`
reports `portalVersion=0.5.1` and `webrtc=h264-http-prototype`,
`/api/media/capabilities` reports four AVC encoders, three HEVC encoders, and
two hardware AVC encoders, `/api/video/h264?frames=8&fps=4&width=720` returns
125086 bytes with Annex-B SPS/PPS/IDR/P-slice NALs, ffprobe parses it as H.264
High 720x1568 yuv420p level 3.2, `/api/screen.png` returns PNG frames, and
`/api/input` tap/swipe still uses `privileged-inputmanager`.

`v0.portal3c-h264-webcodecs-playback` is flashed and live-proven on B slot. It
updates Smartisax to v0.5.2/versionCode 12, keeps `/api/status`,
`/api/media/capabilities`, `/api/screen.png`, `/api/input`, and
`/api/video/h264`, and adds `/api/video/mp4` backed by Android `MediaMuxer` for
direct-LAN HTTP browser playback through a normal video element. LAN smoke and
Safari visual playback both passed.

`v0.portal4a-webrtc-rtp-probe` is flashed and live-proven on B slot. It starts
from live-proven v0.portal3c, updates Smartisax to
v0.5.3/versionCode 13, adds `/api/webrtc/offer` to inspect posted browser SDP
offers, and adds `/api/rtp/h264` as a length-prefixed RTP dump built from the
existing H.264 Annex-B encoder path. It is not full WebRTC yet: no ICE, DTLS,
SRTP, or native WebRTC runtime is enabled. MP4 clips and PNG polling stay as
fallbacks. Live smoke proves pairing/status, `/api/webrtc/offer`,
`/api/media/capabilities`, `/api/video/h264`, `/api/video/mp4`,
`/api/rtp/h264`, `/api/screen.png`, and `/api/input` all work; a clean
post-smoke logcat has no matching fatal/AndroidRuntime/SurfaceControl screenshot
errors. Product polish tracks remain smoother frame refresh, pointer coordinate
polish, access-control hardening, persistent/auto-start policy, file APIs, and
optional system_server screenshot bridge review.

`v0.portal4b-mp4-control-polish` is flashed and live-proven on B slot. It starts
from live-proven v0.portal4a, updates Smartisax to v0.5.4/versionCode 14, and
keeps `/api/status`, `/api/media/capabilities`, `/api/screen.png`, `/api/input`,
`/api/video/h264`, `/api/video/mp4`, `/api/webrtc/offer`, and `/api/rtp/h264`.
Its behavioral change is intentionally browser-side/product-side: the Portal
page adds `Start Live`, accepts `autoplay=live`, uses MP4 clips as the
direct-LAN default, records live loop metrics, and keeps WebCodecs/WebRTC/RTP as
diagnostics. Live smoke proves pairing/status, SDP-offer inspection, media
capabilities, H.264, MP4, RTP dump, PNG screen, and privileged input; a clean
post-smoke logcat has no matching fatal/AndroidRuntime/SurfaceControl screenshot
errors. Static route evidence proves the `autoplay=live` page contains Start
Live, live metrics, autoplay handling, and `/api/video/mp4`. Full browser-side
autoplay rendering remains a manual/tooling validation item because local Chrome
automation failed on macOS Crashpad permissions and the bundled Playwright
Chromium was not installed.

`v0.portal4c-session-hardening` is flashed and live-proven on B slot. It starts
from live-proven v0.portal4b, updates Smartisax to v0.5.5/versionCode 15, keeps
the v0.portal4b media/control endpoints, and adds the first
production-hardening pass for the same-LAN Portal: pairing-code rotation after
a successful pair, bad-pair lockout, session metadata in `/api/status`,
browser-side Forget Session, constant-time Bearer comparison, and
`Content-Security-Policy`/`Referrer-Policy`/same-origin headers. Live smoke
proves pairing-code replay rejection, session metadata, WebRTC offer probing,
media capabilities, H.264, MP4, RTP dump, PNG screen, tap/swipe input, and a
clean focused post-smoke logcat.

The accepted USB physical cleanup starts from live-proven `v0.usb1`, removes
`/vendor/etc/cdrom_install.iso`, zeroes 9391 old ISO blocks that became free
after deletion, preserves one reassigned shared block for
`/media/icon/cn.kuwo.player/logo`, and rebuilds vendor_b FEC. Candidate sparse:
`hard-rom/build/super-otatrust-v0.usb2-physical-cdrom-iso-delete.sparse.img`,
hash `239b95b7ebbb467858c40b8e40a268cb1d83be145f5e9cddd8e2dc66a78153d0`.

The underlying PackageManager/framework line is
`v0.kg1-smartisax-skip-keyguard`. It keeps the first real
PackageManager behavior policy from `v0.pm1-pms-cache-allowlist`, which adds
only `SmartisaxPackagePolicy` and one
`ParallelPackageParser.parsePackage(File,int)` call-site change so the
allowlisted Smartisax-managed boot-scan paths bypass PackageParser cache reads.
It then adds the kg1 Keyguard policy so no-password boots land directly in
Smartisax Home with `isKeyguardShowing=false`. Current sparse:
`hard-rom/build/super-otatrust-v0.usb2-physical-cdrom-iso-delete.sparse.img`,
hash `239b95b7ebbb467858c40b8e40a268cb1d83be145f5e9cddd8e2dc66a78153d0`.

The PackageManager policy route is documented in
`docs/research/package-manager-policy-map.md`. The first real behavior policy
is documented in `docs/research/package-manager-pm1-cache-policy-design.md`.
pm1 is the selected allowlisted boot-scan package parser cache read-bypass for
Smartisax-managed paths. TextBoom-only ABI rederive/override remains `pm2`;
selected updated-system shadow repair remains `pm3`. Do not globally bypass
signature checks, sharedUserId checks, or `/data/app` precedence.
`PackageInstallerSmartisan.apk` remains parked for a later focused task.

The accepted Keyguard behavior gate is `v0.kg1-smartisax-skip-keyguard`, built
on top of live-proven `v0.pm1`. It changes only `services.jar`: it keeps pm1's
`SmartisaxPackagePolicy`, adds
`com.android.server.policy.keyguard.SmartisaxKeyguardPolicy`, and hooks
`KeyguardServiceDelegate$1.onServiceConnected()` so the delegate sets
`KeyguardState.enabled=false` and lets the stock
`KeyguardServiceWrapper.setKeyguardEnabled(false)` path run. Stock
`KeyguardViewMediator.setKeyguardEnabled(false)` still refuses disabling when a
secure keyguard or SIM PIN is active. Offline image verification passes with
system_b hash `fd88c39e3716dcd7f6d018b651ec69c3e2457995afb78a6bc6c5ae5a95c513b2`
and sparse hash
`450c5e1e34b20a7fd66422c96e359bf949e3968a62c3f6f73db81a229706518c`. Live
verification proves `/system/framework/services.jar` hash
`0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6`,
`isKeyguardShowing=false`, and current focus
`com.smartisax.browser/.ShellActivity`.

The accepted USB/vendor gate is now `v0.usb2-physical-cdrom-iso-delete`. It is
built from live-proven `v0.usb1`, patches only `vendor_b`, removes
`/vendor/etc/cdrom_install.iso`, keeps the v0.usb1 `mass_storage.0` configfs
symlink removal, keeps ADB/MTP routes, and is live-verified. Active configfs now
has MTP, diag, diag_mdm, and ADB links, but no `mass_storage.0` link; the
mass_storage LUN `file` is empty, and macOS did not show a Smartisan transfer
tool volume after flashing.

The physical ISO removal follow-up is documented in
`docs/research/usb-mass-storage-source-audit.md`. Its key filesystem lesson is
that pre-delete `debugfs icheck` can miss shared-block aliasing in this vendor
image: block 28776 looked ISO-owned before deletion but was reassigned to
`/media/icon/cn.kuwo.player/logo` after `debugfs rm` and `e2fsck`. Future
physical cleanup must delete first, run fsck, classify old blocks again, and
zero only blocks that remain free.

The accepted TextBoom/OCR live milestone is
`v0.43e-textboom-codepath-arm64-runtime-repair`. It keeps the v0.42.2 PP-OCR
runtime and Android/media preview-save behavior, removes TextBoom's legacy
`CsOcr` and TextBoom-local `com.intsig` code, deliberately retains the original
`AndroidManifest.xml` plus `ocr_key` after the v0.43a manifest edit proved
package-parse unsafe, serves TextBoom from
`/system/app/TextBoomArm32/TextBoomArm32.apk`, accepts PackageManager
`primaryCpuAbi=arm64-v8a`, and restores target arm64 ORT/OpenCV runtime libs
under `/system/app/TextBoomArm32/lib/arm64`.

The previous accepted TextBoom/OCR base was
`v0.43b-textboom-csocr-intsig-delete-manifest-retained`. It remains useful as a
rollback/reference point, but v0.43e is the current live continuation base.

The rejected ABI-control experiments are `v0.43c` and `v0.43d`. v0.43c proved
that deleting APK/system arm64 libs does not force PackageManager to pick
`armeabi-v7a`. v0.43d proved that moving the package to a fresh
`/system/app/TextBoomArm32` codePath changes codePath but still does not force
the ABI away from `arm64-v8a`.

The v0.43d candidate was built offline, then flashed and rejected:
`v0.43d-textboom-codepath-arm32-abi`. It keeps the v0.43b
manifest/`ocr_key` boundary and the v0.43c force-arm32 APK, but changes the
PackageManager scan boundary: the public TextBoom APK moves to
`/system/app/TextBoomArm32/TextBoomArm32.apk`, the old public
`/system/app/TextBoom/TextBoom.apk` is absent, and the old stock APK is retained
only as a hidden non-`.apk` held inode. The live verifier is also wired with an
optional UI-only keyguard-dismiss attempt for the current no-password test
setup; the ROM itself does not bypass Keyguard.

The accepted repair candidate is
`v0.43e-textboom-codepath-arm64-runtime-repair`. It accepts the live
PackageManager result from v0.43d instead of trying again to force
`armeabi-v7a`: TextBoom still scans from
`/system/app/TextBoomArm32/TextBoomArm32.apk`, the APK still has no internal
`lib/arm64-v8a/*`, but the target system path now restores arm64 ORT/OpenCV
libraries under `/system/app/TextBoomArm32/lib/arm64`. It is built,
offline-verified, live-preflighted, flashed, and live-verified.

The broader TextBoom PP-OCR validation pass now has three evidence sets. The
fixed image corpus passed 6/6 through the live official PP-OCR benchmark on
2026-06-21 with p50 latency 1418.5 ms, max latency 2127 ms, and max peak PSS
72447 KB. The v0.41.1 live BOOM_IMAGE path proved PP-OCR result quality across
three deterministic screen states. The v0.42.2 live BOOM_IMAGE regression then
proved the preview file follows each selected region: the three cold-start
cases all launched `com.smartisanos.textboom/.ocr.BoomOcrActivity`, produced
matching OCR chips, wrote distinct
`/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg` hashes,
and reported no TextBoom fatal marker or native-library load failure. See
`docs/research/textboom-live-ocr-regression.md`.

The previous preview regression is closed for the fixed filename route. v0.42
proved the PP-OCR path stayed stable but Android/data was read as ENOENT.
v0.42.1 proved Android/media was a better read path but the live
`startOcrCropped(1) -> dealSaveBitmapResult(...)` branch never wrote the file.
v0.42.2 writes the bitmap in that branch before OCR, and the live regression
reports `unchanged_image_file_cases=[]`.

The first legacy cleanup attempt, `v0.43a-textboom-csocr-intsig-delete`,
removed `ocr_key` from `AndroidManifest.xml` and was rejected by the live
PackageManager: `/system/app/TextBoom/TextBoom.apk` existed and matched hash,
but `pm path com.smartisanos.textboom` returned no package and BOOM intents did
not resolve. Its large sparse/system images were removed after v0.43b superseded
it; reports remain under `hard-rom/inspect/v0.43a-textboom-csocr-intsig-delete/`.

The accepted repair is `v0.43b-textboom-csocr-intsig-delete-manifest-retained`.
It keeps the original manifest and `ocr_key`, changes only `classes2.dex`,
removes TextBoom's `CsOcr` implementation, removes TextBoom-local
`com.intsig.csopen` smali, and changes the remaining OCR error log prefix from
`CSOCR` to `PPOCR`. It deliberately does not touch `resources.arsc`, so inert
CamScanner wording remains as a later resource-string cleanup gate.

```text
variant:
  v0.43b-textboom-csocr-intsig-delete-manifest-retained
APK:
  hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-manifest-retained.apk
APK sha256:
  44d4f4393e061faf77ace20073d460dc8102797dd0847351a84e18fec886b192
super sparse:
  hard-rom/build/super-otatrust-v0.43b-textboom-csocr-intsig-delete-manifest-retained.sparse.img
sparse sha256:
  e88559e276cb9c4fec68f63687af90bee937dde04e05ec6a7320b6d0645e226c
offline verifier:
  PASS_OFFLINE_IMAGE_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED
live verifier:
  PASS_READ_ONLY_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED
boundary:
  live-proven; TextBoom currently resolves as arm64-v8a and passes BOOM_TEXT/BOOM_IMAGE
```

```text
variant:
  v0.43c-textboom-force-arm32-abi
APK:
  hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-force-arm32.apk
APK sha256:
  0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7
super sparse:
  hard-rom/build/super-otatrust-v0.43c-textboom-force-arm32-abi.sparse.img
sparse sha256:
  0b42d185cfdc187b1065be15a3b0cf897be85dd05dceac9569e03341dda9ace2
system_b sha256:
  2b57378c560de0f4dddaee3b49d40bb45b0b44610c56e41301bcf1a9ed621e01
offline verifier:
  PASS_OFFLINE_IMAGE_V043C_TEXTBOOM_FORCE_ARM32_ABI
preflight:
  hard-rom/inspect/v0.43c-textboom-force-arm32-abi/preflight-v0.43c-textboom-force-arm32-abi-20260621-223101.txt
live verifier:
  WARN_READ_ONLY_V043C_TEXTBOOM_ARM64_PM_WITH_ARM64_LIBS_ABSENT
  hard-rom/inspect/v0.43c-textboom-force-arm32-abi/verify-v0.43c-textboom-force-arm32-abi-device-read-only-20260621-231056.txt
BOOM_IMAGE regression:
  hard-rom/inspect/textboom-live-ocr-regression/20260621-v043c-force-arm32-abi-live/
boundary:
  flashed and rejected; boot/system/BOOM_TEXT OK, image OCR not OK
  large v0.43c sparse/system/work artifacts removed after v0.43d superseded it
```

```text
variant:
  v0.43d-textboom-codepath-arm32-abi
APK:
  hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-force-arm32.apk
APK sha256:
  0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7
super sparse:
  hard-rom/build/super-otatrust-v0.43d-textboom-codepath-arm32-abi.sparse.img
sparse sha256:
  c9c2d6013a933f5fcf1374bcb0c1df6940c4110d3ae138192236cf5865801bc2
system_b sha256:
  d34e00f433497405af81438d8c7bb1763b75d623820123c7e7c1fb57e42ecda7
offline verifier:
  PASS_OFFLINE_IMAGE_V043D_TEXTBOOM_CODEPATH_ARM32_ABI
  hard-rom/inspect/v0.43d-textboom-codepath-arm32-abi/verify-v0.43d-textboom-codepath-arm32-abi-offline-image-20260621-233720.txt
boundary:
  flashed and rejected; codePath changed, ABI remained arm64-v8a, image OCR not OK
live verifier:
  WARN_READ_ONLY_V043D_CODEPATH_CHANGED_ABI_STILL_ARM64
  hard-rom/inspect/v0.43d-textboom-codepath-arm32-abi/verify-v0.43d-textboom-codepath-arm32-abi-device-read-only-20260621-235413.txt
BOOM_IMAGE regression:
  hard-rom/inspect/textboom-live-ocr-regression/20260621-v043d-codepath-arm32-abi-live/
```

```text
variant:
  v0.43e-textboom-codepath-arm64-runtime-repair
APK:
  hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-force-arm32.apk
APK sha256:
  0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7
super sparse:
  hard-rom/build/super-otatrust-v0.43e-textboom-codepath-arm64-runtime-repair.sparse.img
sparse sha256:
  d646db5c6462a80735327a3ba8bda2acc60b540df18f150c2d2cf70320f40863
system_b sha256:
  858e9922e126444c66c04e94515bc3fd16e8991c45d557cfac926e2d2d9fa01f
offline verifier:
  PASS_OFFLINE_IMAGE_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR
  hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair/verify-v0.43e-textboom-codepath-arm64-runtime-repair-offline-image-20260622-001646.txt
live preflight:
  hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair/preflight-v0.43e-textboom-codepath-arm64-runtime-repair-20260622-003000.txt
flash-confirmed preflight:
  hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair/preflight-v0.43e-textboom-codepath-arm64-runtime-repair-20260622-flash-confirmed.txt
live verifier:
  PASS_READ_ONLY_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR
  hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair/verify-v0.43e-textboom-codepath-arm64-runtime-repair-device-read-only-20260622-004056.txt
BOOM_IMAGE regression:
  hard-rom/inspect/textboom-live-ocr-regression/20260622-v043e-codepath-arm64-runtime-repair-live/
functional smoke:
  hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair/verify-v0.43e-functional-smoke-20260622-004300.txt
  hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair/verify-v0.43e-webview-smoke-20260622-004400.txt
boundary:
  live PASS. It repairs v0.43d by restoring
  /system/app/TextBoomArm32/lib/arm64 for the observed arm64-v8a runtime.
  BOOM_TEXT passes, three BOOM_IMAGE regression cases pass with
  unsatisfied_link_marker_count=0, WebView M150 stays clean, Smartisax remains
  default Home, and SidebarService remains bound.
```

The v0.44 APK-only cleanup gate has passed offline:
`hard-rom/build/apk/TextBoom-ppocr-legacy-ocr-cleanup.apk` has SHA-256
`fe761609aac2be4eade7bc747bfdc429497f5e43627a4f19b4d76b5ce22faa26`, changes
only `classes2.dex` and `resources.arsc`, removes the old Intsig online OCR URL,
forces `BoomAccessOcrActivity` to use local PP-OCR even when the device has
network connectivity, removes CamScanner/扫描全能王 resource wording, and keeps
manifest `ocr_key` retained.

Next step: if enough disk space is available, promote v0.44 from APK-only to a
v0.44 ROM image based on the live-proven v0.43e system_b, run live preflight,
then ask for explicit flash confirmation. After live acceptance, run the broader
PP-OCR quality/memory regression. Treat true `armeabi-v7a` forcing as a
separate PackageManager policy investigation, not as the main repair line.

The current live-proven launcher-entry-hide baseline is
`v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump`: it keeps VideoPlayer,
ScreenRecorderSmartisan, QuickSearch, Sara/VoiceAssistant, and Sidebar/One Step
installed and functional while removing their desktop launcher entries.

The current live-proven hard-debloat result is
`v0.28-wallet-handshaker-debloat`: the Wallet and HandShaker ROM directories
are removed, the approved Wallet `/data/app` residue cleanup has passed, and
USB/MTP remains healthy.

The next dark-mode milestone remains polishing and functionally validating the
v0.11.1 Settings row. The earlier v0.11 image is live-proven for
boot/package/hash plus reversible UiMode/SystemUI toggleDarkMode `/data` write
behavior, and v0.11.1 now fixes the Darwin/R2 Settings row reachability issue
on the live device.

```text
1. Keep v0.4 rollback, v0.11 live functional evidence, and the v0.11.1 live
   verifier/UI-visibility evidence intact.
2. With explicit `/data` write approval, tap the v0.11.1 Settings row and
   verify UiMode yes/no restoration from the UI path.
3. Build a small native-label polish if the row should display Chinese text
   instead of the current "Dark" label.
4. Validate the Smartisan QS editor/toggleDarkMode path and decide whether a
   default-visible SettingsProvider seed, live migration, or SettingsSmt
   registry patch is needed.
5. Keep the language-facing v0.7 locale-filter behind the dark-mode line unless
   the user explicitly changes priority.
```

The v0.5-control dark-mode/QS app remains an offline candidate. Future debloat
work should still use `docs/v0.5-debloat-candidates.md`.

Language list customization is no longer treated as a simple overlay-only
change. A static overlay can affect AOSP `supported_locales`, but Smartisan's
main language picker enumerates `Resources.getSystem().getAssets().getLocales()`
from framework resource assets. Use `docs/research/locale-pruning-map.md` before
planning a ROM-level language prune.
Use `docs/research/language-prune-integration-map.md` as the end-to-end route:
visible choices are `en-US`, `zh-Hans-CN`, and `zh-Hant-TW`, while first-stage
resource retention keeps all `en*` and `zh*` configs and removes non-English/
non-Chinese configs. Run `tools/r2-language-live-state-audit.sh` on a booted
device before validating visible language behavior, `/data/app` updated-system
shadows, or live language migration.
Use `docs/research/locale-prune-coverage-audit.md` and
`tools/r2-locale-prune-coverage-audit.py` before selecting the next hard-prune
target; they distinguish packages already removed in v0.4, resources covered by
the v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 candidates, v0.7 visible-filter-only work, and true remaining
hard-prune packages. The current audit retains v0.13 Tier1a verifier evidence,
but the local v0.13 system_b image intermediate has been cleaned and must be
rebuilt before promotion. v0.17a promotes five system APK-only probes into a
verified system_b image, v0.17b promotes PhotoTable and Confdialer into
product_b/system_ext_b, and v0.17-all is the retained local combined sparse for
testing those seven promotions. v0.19a CompanionDeviceManager, v0.20a
SmartisanShareBrowser, and v0.21a TrackerSmartisan are newer APK-only evidence
promoted by the v0.22 combined sparse. v0.23a CleanerSmartisan is promoted by
the v0.24 combined sparse, which is the current fuller APK-only test target.
Use `docs/research/resource-loading-map.md` before framework resources, package
resources, icon-sensitive packages, or same-package replacements; Smartisan adds
icon redirection state to the normal Android ResourcesManager/AssetManager path.
Use `docs/research/system-modification-playbook.md` before deleting,
replacing, resource-pruning, or behavior-patching any new system package. It
separates ordinary delete/resource changes from core shared-UID APKs,
SettingsProvider defaults/migrations, framework resources, and boot UI surfaces.
For APK-level resource-table pruning, use `tools/r2-build-apk-locale-prune.sh`
and still gate every package with `tools/r2-rom-mod-preflight.py`; a built APK
is not by itself a flash authorization. If apktool/aapt2 can decode but cannot
rebuild because of Smartisan private attrs or package-id quirks, use
`tools/r2-build-apk-locale-prune-binary-arsc.sh` so only binary
`resources.arsc` config chunks are removed before merging back into the stock
APK shell.
Use `tools/r2-v017-apk-only-promotion-audit.py` before promoting APK-only
candidates into ROM images. The current v0.17/v0.22/v0.24 path maps eleven
promoted APK-only candidates across `system_b`, `product_b`, and `system_ext_b`;
seven are promoted in `v0.17-all`, v0.19a, v0.20a, and v0.21a are promoted by
`v0.22-all`, and v0.23a CleanerSmartisan is promoted by the newer `v0.24`
image. This is image proof only, not flash authorization. The audit also shows
that ordinary held-inode replacement is not feasible for `system_ext_b`
Confdialer, but the same-size/in-place strategy is now offline-proven on a
cloned reference image. Use `tools/r2-apk-same-size-pad.py` and
`tools/r2-ext4-inplace-file-write.py`; re-run the size, stored-resource, block
owner, fsck, dumped-APK hash, ZIP, signature-boundary, and locale-policy gates
for each target before treating the strategy as available.
For the completed Tier1a system-image batch, use
`tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh` and verify with
`tools/r2-verify-v0.13-tier1a-locale-prune.sh --offline-system-image`. The
flashable v0.13 sparse super has not been built yet; build it only when local
free space is sufficient, then run `--offline-image` before any flash request.
For framework language pruning research, use
`tools/r2-build-framework-res-locale-probe.sh`; this only proves offline
resource-table control and does not authorize a framework-res flash.
For `framework-smartisanos-res.apk`, do not normalize `^attr-private` to
ordinary attrs for a ROM candidate. Use
`tools/r2-build-smartisanos-framework-res-locale-probe.sh`, which performs a
binary `resources.arsc` locale-config prune and preserves the private type ID.
For a combined framework/product ROM candidate, use
`tools/r2-hardrom-build-v0.10-framework-locale-prune.sh` and verify with
`tools/r2-verify-v0.10-framework-locale-prune.sh --offline-image`. Because
system/product ext4 images use `shared_blocks`, do not replace files by
`debugfs rm` followed by `write`; keep the stock inode linked under a hidden
non-APK name before linking in the new inode.
Before flashing v0.10, prefer proving the smaller framework-res replacement
boundary with `tools/r2-hardrom-build-v0.12-framework-res-noop.sh` and
`tools/r2-verify-v0.12-framework-res-noop.sh --read-only`. The v0.12 sparse
super is now built and offline-verified; live testing still requires explicit
user confirmation and rollback readiness. Use
`tools/r2-live-flash-preflight.sh v0.12-framework-res-noop` immediately before
asking for that confirmation.

For the live-verified v0.24 APK-only language-prune target, use
`tools/r2-live-flash-preflight.sh v0.24-cleaner-apk-only-locale-prune` before any
future reflash. The preflight only checks local image hashes, rollback
readiness, verifier evidence, and current adb/fastboot visibility; it does not
flash, reboot, erase misc, or change `/data`. After an authorized flash and
boot, use `tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh --read-only`
to prove the live package hashes and `/data/app` shadow state.

Core Settings/SystemUI/framework APK edits also now have a clearer gate:
do not use unsigned or self-signed apktool rebuilds for shared-UID system
packages. Use `docs/research/system-apk-signature-boundary.md` and
`tools/r2-apk-signature-boundary-check.sh`; a no-op original-cert-preserving
replacement must boot cleanly for the exact core APK being changed before real
behavior patches. The current-line SettingsSmartisan gate is
`v0.25-settings-noop-on-v0.24`; the current-line SmartisanSystemUI gate is
`systemui-certprobe-noop-on-v0.24`. Both have passed live independently.

For native QS dark-mode integration, do not default-insert a
`custom(com.smartisax.controls/...)` tile into Smartisan's quick-widget
setting yet. SystemUI can parse `custom(...)`, but SettingsSmartisan's
quick-widget editor uses a Smartisan `toggle...` factory and may not render an
unknown custom spec safely. The v0.11 native candidate instead adds a native
`toggleDarkMode` key in SystemUI and SettingsSmartisan, and now patches
SettingsSmartisan's NotificationCustomView additional/default/reset paths so the
editor can offer `toggleDarkMode` without modifying smartisanos.jar first. The
combined v0.11 ROM image is now built, flashed, and live-verified at the
boot/package/hash level; reversible functional testing is next.
Use `docs/research/darkmode-integration-map.md` before changing dark-mode
Settings, SystemUI, SettingsProvider defaults, QS reset/restore behavior, or
live tile migration.

For the current top-level readiness boundary, run
`tools/r2-system-mod-readiness-audit.py` and read
`docs/research/system-modification-readiness-audit.md`. The latest audit reports
49 offline-proven items, 7 live-proven items, 5 retired local image artifacts,
5 missing gates, and 1 not-achieved full-ROM language-prune item across 67
checks. The full language audit currently reports
138 packages and 4674 non-English/non-Chinese resource dirs still outside ROM
coverage. This audit is the current guard against claiming the user-facing
dark-mode or language hard-prune goals are complete too early.

Before any new package, overlay, resource, or framework modification, use:

```text
reverse/smartisan-8.5.3-rom-static/modification-confidence-map.md
tools/r2-rom-mod-preflight.py
reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/
docs/research/system-modification-playbook.md
docs/research/system-modification-route-audit.md
tools/r2-system-modification-route-audit.py
```
