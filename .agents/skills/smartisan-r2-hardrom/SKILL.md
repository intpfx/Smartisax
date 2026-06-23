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

current live flashed state: v0.portal5j.2-projection-binder-transact
  flashed to B slot after exact confirmation, booted cleanly, and read-only
  verified. It keeps the
  v0.usb2 physical CD-ROM ISO removal, v0.kg1 Keyguard behavior, the v0.43e
  TextBoom/OCR/WebView baseline, the v0.portal4c session hardening, and the
  v0.portal5j MediaProjection/VirtualDisplay/SurfaceTextureHelper capture probe.
  It keeps the v0.portal5j.1 narrow SmartisaxPackagePolicy signature-permission
  policy for com.smartisax.browser: READ_FRAME_BUFFER, CAPTURE_VIDEO_OUTPUT,
  and MANAGE_MEDIA_PROJECTION. Smartisax is v0.6.9/versionCode 26 from
  /system/priv-app/SmartisaxShell and
  keeps libjingle_peerconnection_so.so as external system app libraries under
  /system/priv-app/SmartisaxShell/lib/arm64 and lib/arm. Live proof: boot
  completes on B slot, Smartisax Shell is installed from /system/priv-app,
  READ_FRAME_BUFFER, CAPTURE_VIDEO_OUTPUT, and MANAGE_MEDIA_PROJECTION are all
  granted=true, libwebrtc arm64/arm hashes match, Smartisax Shell is focused,
  and isKeyguardShowing=false. INJECT_EVENTS remains requested by the APK but
  is not granted by this policy. v0.portal5j.2 replaces the blocked hidden
  IMediaProjectionManager$Stub.asInterface reflection path with raw Binder
  transact calls. Live Portal `/api/webrtc/capture/probe` reports
  hasProjectionPermission=true, binderCreateProjection=available,
  tokenRoute=raw-binder-transact-media-projection, and createProjection=ok.
  Formal 1080/30 and 1080/60 projection-texture WebRTC smoke tests now prove
  the path connects, selects H.264, displays 1080x2340, and passes
  smartisax-input DataChannel tap/swipe, but the frame stream stalls after the
  first burst and does not yet satisfy the 1080p30/60 performance target.

next Portal step:
  Optimize the MediaProjection/VirtualDisplay/SurfaceTextureHelper texture
  frame pump so 1080p30 is sustained before treating 1080p60 as the default.
  Keep projection-auto fallback/regression behind that repair.

previous accepted TextBoom/OCR base: v0.43b-textboom-csocr-intsig-delete-manifest-retained
  keeps the v0.42.2 Android/media preview-save fix and the PP-OCR runtime,
  deletes TextBoom's legacy CsOcr and TextBoom-local Intsig/CamScanner code,
  retains the original AndroidManifest.xml/ocr_key package-parse boundary, and
  passes BOOM_TEXT plus three BOOM_IMAGE regression cases on B slot.

current WebView baseline: v0.35.2-webview-m150-clean-product-residue
  M150 `com.android.webview` is served from `/system/app/webview`; old product WebView residue is removed.

current Smartisax live branch: v0.portal5j.2-projection-binder-transact
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
  browser UI prefers H264 for native WebRTC, includes runtime WebRTC tuning
  controls up to 60fps, retains MP4/PNG diagnostics, and closes native WebRTC
  sessions explicitly. The MediaProjection permissions are live-proven and the
  raw-Binder token repair is live-proven with createProjection=ok. 1080/30 and
  1080/60 projection-texture smokes are live-run and connect/control, but
  actual decoded fps stalls far below target.

current retained Smartisax sparse images:
  `hard-rom/build/super-otatrust-v0.portal5i-webrtc-runtime-tuning.sparse.img`
  sha256 `7461215ef7403d005be3fe3c13ec711e9129998d28f11736fd3e1474e304aaf7`.
  Current live v0.portal5j.1 sparse:
  `hard-rom/build/super-otatrust-v0.portal5j.1-projection-permission-grant.sparse.img`
  sha256 `3a89aca9fb029cc8cddfeba78d163ad533a6578ae13b8c229e54f11daafa39bc`.
  Current live v0.portal5j.2 sparse:
  `hard-rom/build/super-otatrust-v0.portal5j.2-projection-binder-transact.sparse.img`
  sha256 `789bb849e7bc849271958b3b6dd6e01a7c707d06373f6d4d72e88564acd83b66`.
  Previous live v0.portal5h sparse:
  `hard-rom/build/super-otatrust-v0.portal5h-webrtc-bitrate-quality.sparse.img`
  sha256 `9d193755098feb70e283b445aa741412ce35017e28b12931be42015d045a17bd`.
  v0.portal5d/v0.portal5e/v0.portal5f/v0.portal5g sparse images and old raw
  system_b verifier intermediates were removed locally after free space dropped
  below 20 GiB. The superseded v0.portal5j sparse image and v0.portal5j.2 raw
  system_b/source extraction were also removed after v0.portal5j.2 offline
  verification when free space remained below the threshold. Their scripts,
  manifests, docs, and inspect reports remain.

next Smartisax/HandShaker replacement step:
  Repair the projection-texture frame-pump continuity path, then rerun 1080/30,
  1080/60, and projection-auto fallback/regression. HTTP /api/input remains
  removed; debug/control fallbacks should use ADB rather than a separate LAN
  input route.

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
