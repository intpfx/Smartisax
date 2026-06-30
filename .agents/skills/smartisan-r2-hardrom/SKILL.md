---
name: smartisan-r2-hardrom
description: Project workflow for Smartisan R2 Smartisan OS 8.5.3 hard-ROM customization, including APatch root state, exact-current super builds, fastboot flashing, rollback, debloat candidates, overlay strategy, and known failure modes.
---

# Smartisan R2 Hard-ROM Workflow

Use this skill for work in the Smartisax repository involving Smartisan R2 ROM modification, root, fastboot, `super.img`, system app debloat, overlays, framework resources, Browser/WebView, TextBoom/OCR, Smartisax system apps, or SmartisanUpdater research.

## First Rule

Separate offline work from live-device work. Local ROM/image/reverse-engineering/script/documentation tasks can run in the workspace sandbox. Anything that touches the physical R2 over USB, ADB, fastboot, screenshots, package queries, or log capture must be run escalated/non-sandboxed and only after the user has confirmed the device operation when it can mutate state.

Never flash, reboot to bootloader, erase partitions, clear `/data`, uninstall packages, or run cleanup scripts with side effects without explicit confirmation for that exact step.

## Current Device Facts

```text
serial: bb12d264
device: Smartisan R2, aries/darwin, Snapdragon 865/kona
OS: Smartisan OS 8.5.3, Android 11
active working slot: B
bootloader: unlocked
root: APatch/kp available on successful hard-ROM builds
fastboot boot: unsupported, returns unknown command
fastbootd: fastboot reboot fastboot enters stock recovery, not userspace fastboot
stock recovery: no adb sideload, only retry/factory reset style UI
```

Always verify live state instead of assuming it:

```bash
adb -s bb12d264 shell 'getprop ro.boot.slot_suffix; getprop sys.boot_completed'
tools/r2-root.sh status
fastboot -s bb12d264 getvar current-slot
fastboot -s bb12d264 getvar is-userspace
```

## Current Baselines

```text
rollback local: v0.4 hard debloat
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  sha256: 313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5

current live flashed state: v0.portal6g-rvfc-media-tail
  flashed to B slot after exact confirmation, booted cleanly, and read-only
  verified. It starts from live/read-only v0.portal6f and preserves H264/default
  codec policy, raw Binder MediaProjection token repair, fresh
  projection-texture timestamps, marker/move-stream input, latest-frame-only
  queue collapse, 60/90Hz input with 60fps video transport pacing, marker
  draw-sync, draw-urgent input boosts, the real Portal `.screenBox` visibility
  repair, the display wake guard, the 6e encoder/transport burst repair, and
  the 6f presentation-tail cadence repair. It targets the in-app browser
  1080/60 RVFC/media callback tail cluster by de-phasing the exact 1080p60
  sender to 59fps, narrowing the 1080p60 target/max bitrate window to 7Mbps,
  preserving `inputRefreshHz=90`, and spacing continuity/marker tail forceFrame
  cadence at a full media-frame interval.
  Smartisax is v0.6.33/versionCode 50 from /system/priv-app/SmartisaxShell.
  Hashes: APK
  `442276dfaf1e70ecf0209818ed61b207bae72194fc490f8c601471b6a43f9f6a`,
  system_b `941c660259f32270eaf4e3a8a5778b8518d4035e0f5efb73a8b704fd7d4b4241`,
  sparse `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`.
  Build result is `PASS_BUILD_V0PORTAL6G_RVFC_MEDIA_TAIL`; offline result is
  `PASS_OFFLINE_IMAGE_V0PORTAL6G_RVFC_MEDIA_TAIL`; live result is
  `PASS_READ_ONLY_V0PORTAL6G_RVFC_MEDIA_TAIL`; flash result is
  `PASS_FLASH_V0PORTAL6G_RVFC_MEDIA_TAIL`.
  Live proof: boot_completed=1, slot `_b`, bootanim stopped, verified boot
  orange, root available, SELinux Enforcing, Smartisax Shell resumed,
  isKeyguardShowing=false, READ_FRAME_BUFFER/CAPTURE_VIDEO_OUTPUT/
  MANAGE_MEDIA_PROJECTION and WAKE_LOCK all granted=true, and device
  APK/libwebrtc hashes match. A post-flash display/window probe proves
  `mWakefulness=Awake`, `mHalInteractiveModeEnabled=true`,
  `mDisplayReady=true`, display power `state=ON`, and the ShellActivity window
  is on-screen/visible. Evidence:
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/flash-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/boot-wait-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-device-read-only-20260629-204302.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/post-flash-focus-v0.portal6g-rvfc-media-tail-20260629-203737.txt`, and
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/display-window-state-after-flash-20260629-204340.txt`.
  Previous 6e fresh-code strict smoke with pairing code `666132` is diagnostic
  FAIL, not accepted. It proves the 1080/60 packet-loss repair direction:
  1080/60
  packetLossDelta is now 0, down from v0.portal6b's 560. Remaining strict
  blockers are RVFC/presentation cadence and marker-visible T2P tail, with
  1080/60 T2P p95 471.07ms and RVFC 41.92fps; 1080/90 T2P p95 is 163.98ms
  but packetLossDelta is 2 and RVFC is 47.7fps. Summary:
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/portal-encoder-transport-burst-smoke-live/projection-texture-summary.md`.
  Fresh-code 6f strict smoke with pairing code `176725` passed through a
  Safari fallback browser wrapper because Google Chrome is not installed on
  this Mac. 1080/60 selected H264, displayed 1080x2340, decoded 3855 frames at
  59.77fps, packetLossDelta 0, RVFC 55.65fps, 18 RVFC gaps over 34ms,
  move-stream PASS, and T2P p50/p95/max 115.5/116.85/117ms. 1080/90 selected
  H264, displayed 1080x2340, decoded 3855 frames at 59.93fps,
  packetLossDelta 0, RVFC 56.16fps, 10 RVFC gaps over 34ms, move-stream PASS,
  and T2P p50/p95/max 128/140.6/142ms. Summary:
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-safari-176725/projection-texture-summary.md`.
  Treat this as Safari visibility/playback/control/T2P PASS, not as
  Chrome-specific presentation-gap acceptance. Fresh-code 6f Chrome-side
  cadence smoke with pairing code `998599` was then run through the Codex
  in-app browser at a temporary 540x1170 viewport. It is diagnostic FAIL
  overall because 1080/60 still misses the RVFC gap gate: H264 1080x2340,
  decoded 3878 frames at 59.76fps, packetLossDelta 0, RVFC 51.2fps, RAF 60fps,
  move-stream PASS, T2P p95 124.42ms, but RVFC gaps over 34ms = 123 against
  <=60. 1080/90 passes: H264 1080x2340, decoded 3874 frames at 59.93fps,
  packetLossDelta 0, RVFC 53.79fps, RVFC gaps over 34ms = 63, and T2P p95
  129.26ms. Summary:
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-iab-998599/projection-texture-summary.md`.
  Next target: run a fresh-code 6g strict smoke and reduce 1080/60 RVFC/media
  callback tail clustering while preserving packetLossDelta 0, low input ack,
  and low T2P. Build/offline/preflight evidence:
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/build-v0.portal6g-rvfc-media-tail-20260629-202323.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-offline-image-20260629-202657.txt`,
  and
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/preflight-v0.portal6g-rvfc-media-tail-20260629-202908.txt`.
  Pairing codes `829543` and `808364` were consumed by 2026-06-30
  in-app-browser smoke attempts, but both are `CONTROL_FAIL` only. `829543`
  could not create/attach the generated local receiver tab. `808364` used
  manual-open fallback, generated 1080/60 `http://127.0.0.1:60826/` and
  1080/90 `http://127.0.0.1:60958/`, but both profiles timed out after
  `180000ms` without WebRTC answers. Pair/config/probe and runtime config
  passed; no decoded frames, RVFC, DataChannel ack, or T2P sample was produced.
  Evidence:
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-iab-829543/`
  and
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-iab-808364/`.
  A same-session direct-in-Portal diagnostic then reused the already paired
  Codex in-app browser tab at `http://192.168.31.103:37601/` successfully.
  Both profiles connected with H264 1080x2340, packetLossDelta 0, open
  input/move DataChannels, and 8/8 move plus touchEnd acks. 1080/60 decoded
  55.66fps with RVFC 44.43fps and 61 gaps over 34ms; 1080/90 decoded 57.36fps
  with RVFC 43.48fps and 83 gaps over 34ms. RAF stayed near 59.7fps with 0
  gaps. Pixel T2P was disabled after marker-pixel sampling stalled under the
  automation path, so treat this as diagnostic evidence, not strict acceptance.
  Evidence:
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-direct-in-app-browser-20260630-808364-session/`.
  Safari fresh-code strict smoke with pairing code `223229` proves 1080/60 as
  a strict Safari PASS on live 6g: H264 1080x2340, decoded 57.94fps,
  packetLossDelta 0, RVFC 56.18fps, RVFC gaps over 34ms = 6, T2P p95
  149.2ms, move-stream PASS, marker draw-sync PASS, inputFrameBoost PASS, and
  urgent PASS. The same run is diagnostic FAIL overall only because 1080/90 was
  visibility-contaminated: packetLossDelta 0, decoded 59.72fps, T2P p95
  135.8ms, and input PASS, but Safari reported blur at about 33315ms and
  visibilitychange hidden at about 33642ms, ending with `document.hidden=true`
  and `hasFocus=false`; RVFC then fell to 38.93fps with 163 gaps over 34ms.
  Treat that 1080/90 sample as foreground/visibility contamination, not a clean
  6g media failure. Evidence:
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/portal-rvfc-media-tail-smoke-safari-223229/projection-texture-summary.md`.
  Next smoke work should pin/guard receiver foreground visibility before
  judging 1080/90, and should keep the direct real-Portal
  `http://192.168.31.103:37601/` path as the preferred harness target.
  v0.portal6b is the previous performance diagnostic boundary: both 1080/60 and
  1080/90 connected with H264, input PASS, move-stream PASS, marker draw-sync
  PASS, and draw-urgent counters PASS, but 1080/60 failed packet loss/RVFC/T2P
  and 1080/90 still failed RVFC gaps and T2P. A real-Portal Chrome visual smoke
  against the previous 6c connected, selected H264, exposed 1080x2340 video,
  and opened both input DataChannels, but failed because decoded pixels were
  flat black. ADB evidence showed `mWakefulness=Asleep`,
  `mGlobalDisplayState=OFF`, and ADB `screencap` itself was black; waking the
  device restored normal Shell UI. 6d is the live display wake repair for that
  source-display sleep boundary.
  The previous v0.portal5z strict and
  no-flash anti-throttle smoke remains the comparison boundary:
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/portal-video-primary-roi-probe-smoke-live/projection-texture-summary.md`.
  The original 5z smoke had 1080/60 at decoded 59.3fps, RVFC 31.41fps,
  packet-loss delta 4, 95 gaps over 34ms, and T2P p50/p95 153.9/192.96ms;
  1080/90 decoded 59.38fps with packet-loss delta 0 and RAF 59.99fps, but
  RVFC was 49.09fps, gaps over 34ms were 111, and T2P p50/p95 was
  357.7/401.98ms. A no-flash anti-throttle rerun on current 5z then kept both
  profiles at packet-loss delta 0 and RAF near 60fps. 1080/60 improved to
  decoded 59.76fps, RVFC 49.79fps, 79 gaps over 34ms, but T2P p50/p95 regressed
  to 409.25/591.54ms. 1080/90 reached decoded 60.03fps, RVFC 48.38fps,
  146 gaps over 34ms, and T2P p50/p95 189.1/214.03ms. The smoke harness now
  records page lifecycle plus RVFC/RAF timeline state, compacts summary output,
  uses Chrome anti-throttle flags by default, and has an unvalidated Chrome
  foreground activation path for the next fresh-code run.

next Portal step:
  The live v0.portal6d-display-wake-guard real Portal visual smoke has passed:
  pairState `paired`, H264 answer applied, video `1080x2340`, readyState `4`,
  pixelRange `233.33`, pixelBuckets `89`, and both input DataChannels open.
  Post-smoke device evidence keeps `mWakefulness=Awake`,
  `mGlobalDisplayState=ON`, and both the built-in display and
  `SmartisaxWebRtcProjection` virtual display `state ON`.
  v0.portal6e-encoder-transport-burst is previous flashed/read-only PASS. It starts
  from live/read-only 6d, updates Smartisax to v0.6.31/versionCode 48, clamps
  the 1080p60/90 sender bitrate window, sets WebRTC sender degradation
  preference to `MAINTAIN_FRAMERATE`, and late-starts the projection frame pump
  after local SDP. Hashes: APK
  `90421ef5613f5dafa5491735848ebe6588e2fe5d95ffb79929bfe00329a921ef`,
  system_b `04cfe9746848f5daee752a13efb18ba3cb938d8c7969d5b48333c965f319a6b7`,
  sparse `5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83`.
  Build/offline/preflight/flash/read-only evidence:
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/build-v0.portal6e-encoder-transport-burst-20260625-165309.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-offline-image-20260625-170017.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/preflight-v0.portal6e-encoder-transport-burst-20260625-170235.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/flash-v0.portal6e-encoder-transport-burst-20260625-171510.txt`,
  and
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-device-read-only-20260625-172037.txt`.
  Fresh-code 6e strict smoke with code `666132` proved the 1080/60 packet-loss
  repair direction but is diagnostic FAIL, not accepted: 1080/60 packetLossDelta
  is 0, while RVFC 41.92fps, 158 RVFC gaps over 34ms, and T2P p95 471.07ms miss
  strict gates; 1080/90 T2P p95 is 163.98ms PASS, but packetLossDelta 2 and
  RVFC 47.7fps still miss. v0.portal6f-presentation-tail-cadence is the
  previous flashed/read-only PASS candidate for RVFC/presentation cadence and
  the 1080/60 marker-visible T2P tail; v0.portal6g is the current live
  media-callback-tail repair candidate. Next, run the 1080/60 + 1080/90 strict
  smoke with a fresh pairing code. The draw-urgent path is proven by counters,
  so avoid adding more ordinary input boost until video/RVFC evidence moves.
  Treat
  the original 22s-class
  1080/60 presentation gap as
  host-window/background noise after the anti-throttle rerun, but do not treat
  5z as accepted: RVFC and T2P still miss gates. The comparison boundary
  includes v0.portal5z diagnostic/anti-throttle smoke and v0.portal5y strict
  smoke:
  both profiles connected with H264, projection-texture 1080x2340, input PASS,
  move-stream PASS, input-frame-boost PASS, and packet-loss delta 0, but
  1080/60 T2P p50/p95 was 205.35/253.82ms and 1080/90 had a 14016.7ms
  presentation gap with 7080ms reported freeze time.
  Historical codec cascade probe with
  `PREFER_CODECS=AV1,H265,VP9,H264` proves AV1 negotiation and decode on both
  1080/30 and 1080/60; 1080/30 AV1 passes at 29.98fps with T2P p95 158.9ms,
  while 1080/60 AV1 passes at 57.34fps, packet-loss delta 0, RVFC 45.65fps,
  242 gaps over 34ms, and T2P p95 172.67ms. Forced H265 negotiates but produces
  browser video 0x0 with decoded frames 0 on both profiles. Forced VP9 displays
  1080x2340 but decodes only about 5fps and has 1080/60 T2P p95 251.68ms. For
  interactive 1080/60, keep H264 as the measured low-latency default; retain
  AV1 as an explicit experiment path, and do not prefer H265/VP9 until H265
  produces browser frames and VP9 reaches usable decode cadence. Continue
  projection-auto fallback/regression, longer-duration 1080/60 stability,
  default profile/autostart policy, file APIs, and broader UI polish. HTTP
  /api/input remains removed; control belongs to smartisax-input RTCDataChannel.

previous accepted TextBoom/OCR base: v0.43b-textboom-csocr-intsig-delete-manifest-retained
  keeps the v0.42.2 Android/media preview-save fix and the PP-OCR runtime,
  deletes TextBoom's legacy CsOcr and TextBoom-local Intsig/CamScanner code,
  retains the original AndroidManifest.xml/ocr_key package-parse boundary, and
  passes BOOM_TEXT plus three BOOM_IMAGE regression cases on B slot.

current WebView baseline: v0.35.2-webview-m150-clean-product-residue
  M150 `com.android.webview` is served from `/system/app/webview`; old product WebView residue is removed.

current Smartisax live branch: v0.portal6g-rvfc-media-tail
  `com.smartisax.browser` registers as a privileged WebView-backed browser/Home
  candidate from `/system/priv-app/SmartisaxShell` and has a guarded local
  Smartisax Shell wireless ADB control entry that works through raw Binder
  transact calls. It also has a Wi-Fi-bound DevicePortalService, enabled from
  the Smartisax UI, serving GET /, POST /api/pair, token-gated
  GET /api/status, GET /api/screen.png,
  GET /api/media/capabilities, GET /api/video/h264, GET /api/video/mp4,
  POST /api/webrtc/offer, GET/POST /api/webrtc/config,
  GET /api/webrtc/capture/probe,
  GET /api/webrtc/sessions, POST /api/webrtc/close, and GET /api/rtp/h264.
  HTTP POST /api/input is intentionally absent; remote
  control input now belongs to the WebRTC smartisax-input RTCDataChannel. The
  live-flashed v0.portal6g browser UI is the current read-only verified
  RVFC/media callback tail repair line on top of the 6f presentation-tail
  cadence line, 6e encoder/transport burst repair, 6d display wake guard, 6c
  visible-screenBox repair, and 6b draw-urgent marker boost lines. The previous
  6c real-Portal Chrome smoke
  proved the browser/WebRTC connection but failed on black pixels because the
  device display was asleep; 6d is flashed, read-only verified, and display
  probed with the source display awake/ON.
  It prefers the latency-aware
  `H264,AV1,VP9,H265` codec cascade for native WebRTC while keeping newer
  codecs available through explicit smoke/UI experiments. The live/source
  Portal line includes 60/90Hz runtime WebRTC tuning controls up to 90Hz input,
  event-time move-stream injection, input-priority projection frames,
  marker-burst reschedule, retained MP4/PNG diagnostics, explicit native WebRTC
  session close, canvas-presenter diagnostics, 60fps video transport pacing for
  the 1080/90 input profile, video-primary marker ROI probe diagnostics, and
  marker draw-pass synchronized capture boost/burst, draw-urgent marker boost
  that bypasses ordinary half-frame input boost spacing after marker OnDraw, a
  real Portal `.screenBox` CSS repair that avoids parent size containment
  clipping the video surface in Chrome/Safari, and a WebRTC session display
  wake guard.
  MediaProjection permissions are live-proven and the raw-Binder token repair
  is live-proven with
  createProjection=ok. The
  v0.portal6d display wake guard was live-flashed and read-only verified. Its
  real-Portal visual smoke in Chrome now passes with visible non-black H264
  video pixels and both input DataChannels open. The previous
  v0.portal6e-encoder-transport-burst candidate is flashed/read-only PASS.
  Its fresh-code strict smoke with `666132` is diagnostic FAIL, but it proves
  1080/60 packetLossDelta 0. The previous
  v0.portal6f-presentation-tail-cadence candidate is flashed/read-only PASS.
  Safari fallback strict smoke passes, and in-app browser Chrome-side smoke
  with code `998599` shows the remaining accepted blocker is 1080/60 RVFC gaps
  over 34ms = 123 against <=60; 1080/90 passes. The current live 6g candidate
  is flashed/read-only PASS and is the media callback tail repair to validate
  with the next fresh-code strict smoke.
  v0.portal6b strict smoke remains diagnostic FAIL: draw-urgent counters pass,
  but 1080/60 packet loss, RVFC gaps, and T2P tail still miss gates; 1080/90
  removes packet loss but still misses RVFC gap and T2P gates. v0.portal6b is
  the previous live/read-only performance boundary, v0.portal6a marker draw-sync
  is the previous draw-sync boundary, and v0.portal5z video-primary ROI probe is
  the previous
  diagnostic FAIL comparison boundary. The previous v0.portal5y strict smoke was not
  accepted because Chrome presentation/RVFC cadence and T2P tail latency still
  missed gates even though packet loss became zero on both profiles. The 5z
  smoke kept 1080/90 packet-loss delta at zero and RAF near 60fps, but RVFC
  cadence, gaps, and T2P tail still missed gates.
  v0.portal5o still proves the clean 1080/60 T2P target to beat, but 1080/30
  still misses the strict latency/presentation gate.
  v0.portal5n remains the smoke-tested queue-collapse comparison line, and
  v0.portal5m remains the earlier smoke-proven
  latency/follow-rate comparison baseline, v0.portal5l remains the marker and
  move-stream comparison baseline, and v0.portal5k.1 remains the pre-marker
  comparison baseline for 1080/30 and 1080/60 decode continuity.

current retained Smartisax sparse images:
  Rollback v0.4 sparse:
  `hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img`
  sha256 `313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5`.
  Previous live v0.portal5y sparse:
  `hard-rom/build/super-otatrust-v0.portal5y-presentation-transport-pacing.sparse.img`
  sha256 `c20ad88972c3395b848f5941b5bf12f8b5674d00da3cf9ccd6fca673ca28e4dc`.
  Previous live v0.portal5z sparse:
  `hard-rom/build/super-otatrust-v0.portal5z-video-primary-roi-probe.sparse.img`
  sha256 `3a622e32a540c077075d0e9259a6245338e38a24b65342a09c212a6032fda0df`.
  Previous live v0.portal6a sparse:
  `hard-rom/build/super-otatrust-v0.portal6a-marker-draw-sync.sparse.img`
  sha256 `b8d2bbe12c3d889fa83963ea8d8e31e2a47b2a460c075d11b29ba4d1676fcc2a`.
  Previous live v0.portal6b sparse:
  `hard-rom/build/super-otatrust-v0.portal6b-draw-urgent-boost.sparse.img`
  sha256 `057930f125ce07e5fc3c2940af4ac348102df7e8acbfe83d6a25467e4c3ee235`.
  Previous live v0.portal6c sparse:
  `hard-rom/build/super-otatrust-v0.portal6c-visible-screenbox.sparse.img`
  sha256 `df7912827b4201bcff601edcc300fe79654ffdc571dda860272eb6485a247a9a`.
  Previous live v0.portal6d sparse:
  `hard-rom/build/super-otatrust-v0.portal6d-display-wake-guard.sparse.img`
  sha256 `48f3329f3da1496e9c27ce3de7ff2f08fdd4d589f37ee5feaab74b8782bba0e4`.
  Previous live v0.portal6e sparse:
  `hard-rom/build/super-otatrust-v0.portal6e-encoder-transport-burst.sparse.img`
  sha256 `5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83`.
  Previous live v0.portal6f sparse:
  `hard-rom/build/super-otatrust-v0.portal6f-presentation-tail-cadence.sparse.img`
  sha256 `d0bd5eb4653d8e019fdfea6fbe7815895c9ab57b87bc441b38ed7b8112465d9a`.
  Current live v0.portal6g sparse:
  `hard-rom/build/super-otatrust-v0.portal6g-rvfc-media-tail.sparse.img`
  sha256 `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`.
  To recover local free space to 50 GiB, superseded portal sparse images
  including v0.portal5w and later v0.portal5x, old raw system_b intermediates,
  regenerated 5z raw/work files, `hard-rom/work/*`, and `hard-rom/extracted`
  were removed locally. Their scripts, manifests, docs, checksum files, and
  inspect reports remain; regenerate raw system images from retained sparse
  images/build scripts if an offline reverify needs them.

next Smartisax/HandShaker replacement step:
  Run a fresh-code in-app-browser or supported Chromium strict smoke through
  `tools/r2-portal6g-rvfc-media-tail-smoke.sh`. The acceptance target is still
  1080/60 RVFC gaps over 34ms <=60 while preserving packetLossDelta 0, low input
  ack, and T2P p95 near the 6f 125ms level. v0.portal6e proved the 1080/60
  packet-loss repair direction; v0.portal6f proved Safari PASS and the
  Chrome-side failure isolation; live v0.portal6g is the current media callback
  tail repair candidate.
  HTTP /api/input remains removed; debug/control fallbacks should use ADB rather
  than a separate LAN input route.

current accepted TextBoom/OCR base: v0.43e-textboom-codepath-arm64-runtime-repair
  TextBoom v3.2.2 is served from `/system/app/TextBoomArm32` with no
  `/data/app` shadow. The live line uses LocalPpOcrApi plus PP-OCRv6 small ONNX
  models, removes executable CsOcr/Intsig code, keeps manifest ocr_key after
  v0.43a proved manifest removal PackageManager-unsafe, resolves as
  primaryCpuAbi=arm64-v8a, and uses restored target arm64 runtime libs.

next TextBoom/OCR step:
  Continue from v0.43e. The next low-risk branch is CamScanner resource-string
  cleanup plus broader PP-OCR quality/memory regression. True arm32 forcing is
  now a separate PackageManager settings/cache/version or manifest ABI policy
  investigation. Do not remove manifest ocr_key again without a
  package-signature/manifest carrier plan.

next PackageManager/framework step:
  Continue from live-proven v0.portal2.3 services.jar behavior.
  PackageInstallerSmartisan remains parked for a later focused task.
  TextBoom-only ABI rederive/override remains pm2, and selected updated-system
  shadow repair remains pm3. Do not globally bypass signature checks,
  sharedUserId checks, or /data/app precedence.

USB cleanup status:
  v0.usb2-physical-cdrom-iso-delete is live-proven on B slot.
  /vendor/etc/cdrom_install.iso is absent, active USB configfs keeps MTP and
  ADB without mass_storage.0, and macOS shows no Smartisan transfer-tool volume.

cold archive: v0.2 no-appstore on SSDUSB; see docs/rom-archive.md before referencing old paths.
```

Do not make disk cleanup routine. Continue the ROM/reverse-engineering goal unless free space drops below 20 GiB or the user explicitly asks for cleanup.

## Task Routing

Read the matching reference before acting:

| Task | Required reference | Primary docs |
| --- | --- | --- |
| Rollback, retained images, storage policy | `references/device-baselines.md` | `docs/rom-archive.md` |
| Build, exact-current super patching, ext4/shared_blocks, FEC, flash protocol | `references/build-flash-protocol.md` | `docs/hard-rom-ota-trust.md` |
| Browser/WebView modernization, Smartisax, TextBoom/PP-OCR | `references/modernization-and-lessons.md` | `docs/research/webview-v0.35-system-provider-image-design.md`, `docs/research/textboom-ppocr-adapter-design.md` |
| Debloat, package delete/replace, core APK patching, signature boundaries | `references/system-modification-gates.md` | `docs/research/system-modification-playbook.md`, `docs/research/system-apk-signature-boundary.md` |
| Language pruning or native dark mode | `references/language-darkmode.md` | `docs/research/language-prune-integration-map.md`, `docs/research/darkmode-integration-map.md` |
| Launcher entry hiding, Sidebar/One Step, cloud/wallet/HandShaker debloat | `references/launcher-sidebar-debloat.md` | `docs/research/launcher-entry-hide-audit.md`, `docs/research/sidebar-one-step-source-audit.md` |
| Documentation/evidence updates | `references/documentation-rules.md` | `docs/README.md`, `docs/index/` |

Use graphify and the static ROM knowledge base as navigation aids, not final proof. Confirm findings with decoded manifests/resources, source paths, partition extents, generated manifests, and post-boot device checks.

## Safe Build And Flash Loop

```text
1. Inspect static ROM evidence and current live/device state when needed.
2. Build the smallest candidate from the latest suitable live-proven baseline.
3. Verify image hashes, partition extents, fsck, dumped APK hashes, ZIP integrity, and FEC/AVB metadata offline.
4. Run `tools/r2-live-flash-preflight.sh <variant>` for the exact candidate.
5. Ask for the exact confirmation phrase before any flash or mutating live action.
6. Flash `super`, erase `misc`, reboot, and wait for boot completion.
7. Verify slot, `sys.boot_completed`, root, SELinux, keyguard/launcher focus, package paths/hashes, and feature-specific behavior.
8. Record the result in `docs/hard-rom-ota-trust.md` or the active split log/index before proceeding.
```

Rollback command for the local stable image:

```bash
fastboot -s bb12d264 flash super hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
fastboot -s bb12d264 erase misc
fastboot -s bb12d264 reboot
```

## Hard Rules

- Prefer hard-ROM changes: edit partition images, rebuild `super`, flash, boot, verify.
- Prefer Android-native mechanisms such as static RRO overlays before directly repacking framework resources.
- Do not treat bootloader unlock or root as proof that a modification is safe; PackageManager, resources, SELinux, overlays, cache freshness, and boot-order contracts still apply.
- Do not replace core shared-UID APKs with unsigned or self-signed rebuilds. Use original-cert-preserving system-partition probes and no-op gates.
- For shared-block ext4 images, do not replace files with naive `debugfs rm + write`; use the proven held-stock-inode pattern unless a target-specific owner/alias audit proves a narrower exception.
- Same-package BrowserChrome/system app replacement is high risk; v0.3/v0.3.1 failed around boot/keyguard/resource state and must not be used as a template.
- For updated-system packages active from `/data/app`, ROM removal alone is insufficient; plan explicit post-boot PackageManager/data-shadow repair and verification.
- Keep at least one working keyboard. Do not remove Smartisan IME and LatinIME in the same test.

## Current OCR Boundary

TextBoom PP-OCR replacement is past standalone runtime proof and the first
TextBoom no-op adapter gate is live-proven:

```text
official ppocr-sdk + PP-OCRv6 small + onnxruntime-android 1.21.1 + OpenCV 4.9.0: corpus PASS on R2
standalone CamScanner/CsOcr raw baseline: blocked with CSOCR_RESULT_CODE_1, response_code=4003
v0.40 LocalPpOcrApi no-op adapter gate: flashed to B slot and live-verified;
  BOOM_TEXT, image OCR empty/no-result behavior, BrowserChrome, Smartisax, and
  WebView M150 smoke checks passed
v0.41 LocalPpOcrApi runtime adapter gate: built, offline-verified, and
  flashed to B slot. Read-only verification and BOOM_TEXT pass after the user
  manually swiped past keyguard; image OCR fails with OpenCV not found because
  TextBoom's primaryCpuAbi is armeabi-v7a/app_process32 and v0.41 only added
  arm64 runtime libs.
v0.41.1 LocalPpOcrApi runtime arm32 ABI fix: flashed to B slot and
  live-verified. TextBoom primaryCpuAbi is armeabi-v7a, the expected arm32
  ORT/OpenCV libraries are present, BOOM_TEXT starts/segments text, and
  BOOM_IMAGE reaches a TextBoom result page with PP-OCR text from a Smartisax
  screenshot. Residual non-TextBoom log noise exists, so the next gate is a
  broader corpus and memory/latency/regression pass before deleting legacy OCR.
v0.42.2 TextBoom preview-save fix: flashed and live-verified. It keeps the
  v0.41.1 PP-OCR runtime/libs, writes the selected bitmap to
  `/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg` before
  local OCR starts, and passes the three-case preview hash regression.
v0.43a TextBoom CsOcr/Intsig deletion attempt: flashed and booted, but the live
  PackageManager ignored TextBoom after AndroidManifest.xml/ocr_key removal
  even though `/system/app/TextBoom/TextBoom.apk` existed and matched hash.
v0.43b TextBoom CsOcr/Intsig deletion repair: flashed and live-verified. It
  retains AndroidManifest.xml/ocr_key, changes only classes2.dex, removes
  CsOcr and TextBoom-local com.intsig.csopen smali, passes BOOM_TEXT plus
  three BOOM_IMAGE regression cases, and currently runs as arm64-v8a.
v0.43c TextBoom force-arm32 ABI candidate: flashed and rejected as a failed
  ABI-control gate. It keeps v0.43b's manifest/ocr_key and CsOcr/Intsig code
  deletion, removes APK-internal lib/arm64-v8a entries plus
  /system/app/TextBoom/lib/arm64, but PackageManager still records
  primaryCpuAbi=arm64-v8a. BOOM_TEXT passes; BOOM_IMAGE fails PP-OCR with
  `libopencv_java4.so not found` and returns to the source app.
v0.43d TextBoom codePath arm32 ABI candidate: flashed and rejected as a failed
  ABI-control gate. It keeps the v0.43b manifest/ocr_key boundary and v0.43c
  force-arm32 APK, moves the package scan path to
  /system/app/TextBoomArm32/TextBoomArm32.apk, removes the old public TextBoom
  APK path, and retains the old stock APK only as a non-.apk hidden held inode.
  PackageManager updates codePath but still records primaryCpuAbi=arm64-v8a;
  TextBoom runs as /system/bin/app_process64 and BOOM_IMAGE fails PP-OCR with
  `libopencv_java4.so not found`.
v0.43e TextBoom codePath arm64 runtime repair candidate: built,
  offline-verified, live-preflighted, flashed, and live-verified. It keeps the
  v0.43d codePath boundary and force-arm32 APK hash, keeps APK-internal arm64
  libs absent, but restores the system target arm64 runtime libraries under
  /system/app/TextBoomArm32/lib/arm64. Live PackageManager reports
  primaryCpuAbi=arm64-v8a; BOOM_TEXT and three BOOM_IMAGE regression cases pass
  with no OpenCV/UnsatisfiedLink failure.
```

Read `docs/research/textboom-ocr-baseline-comparison.md` and `docs/research/textboom-ppocr-adapter-design.md` before TextBoom OCR work. Do not remove manifest `ocr_key` again without a package-signature/manifest carrier plan.

## Documentation Rules

Keep entrypoints short:

```text
README.md       human + agent project overview
AGENTS.md       short agent operating rules
SKILL.md        short operational router
references/     long skill reference material
docs/README.md  documentation index
docs/index/     topic indexes and navigation aids
```

Update `docs/hard-rom-ota-trust.md` after every meaningful experiment. Include the variant name, source baseline, exact commands, image paths and hashes, fastboot output summary, post-boot verification, and rollback path.
