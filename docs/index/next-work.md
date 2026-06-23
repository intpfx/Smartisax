# Next Work

This file was split out of the root `README.md` so active task notes can grow without bloating the project entrypoint. Verify against current device/image state before acting.

## Active Work Pointers

The active live ROM line is now
`v0.portal5j.2-projection-binder-transact`. It is flashed to B slot after
exact confirmation, boots cleanly, and read-only verifies. It retains `v0.usb2`
USB/CD-ROM cleanup,
`v0.kg1-smartisax-skip-keyguard` PackageManager/framework behavior,
`v0.wadb2.2-smartisax-wireless-adb-binder-transact` Smartisax wireless ADB
control, the v0.portal5j MediaProjection texture probe path, the
v0.portal4c Portal session hardening, v0.portal5d's Bitmap.copy WebRTC frame
pump, v0.portal5e's H.264/session cleanup behavior, v0.portal5g's touch overlay
mapping, v0.portal5h's WebRTC-only UI/default startup/bitrate parameter path,
v0.portal5i's runtime tuning controls, and Smartisax as
`/system/priv-app/SmartisaxShell`. Its services.jar policy grants
`READ_FRAME_BUFFER`, `CAPTURE_VIDEO_OUTPUT`, and `MANAGE_MEDIA_PROJECTION` to
`com.smartisax.browser`; live read-only verification proves all three are
`granted=true`. `INJECT_EVENTS` remains ungranted by this policy. The
Smartisax APK is now v0.6.9/versionCode 26 and uses raw Binder transact calls
instead of hidden `IMediaProjectionManager$Stub.asInterface(...)` reflection
for MediaProjection token creation.

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

The current live v0.portal5i line is built, offline-verified, live-preflighted,
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

The currently flashed v0.portal5j line updates Smartisax to
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

The current live candidate `v0.portal5j.1-projection-permission-grant` keeps the
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

Next, inspect and patch the
MediaProjection/VirtualDisplay/SurfaceTextureHelper -> WebRTC encoder surface
path so `projection-texture` keeps producing frames after startup. Prioritize
listener/thread ownership, VirtualDisplay lifecycle, requested fps versus
Smartisan/TNT virtual-display behavior, and the hardware encoder metadata-mode
fallback. Keep HTTP `/api/input` removed; use ADB for emergency debug/control.
After the repair, rerun 1080/30 first, then 1080/60, then `projection-auto`
fallback/regression.

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
Next Portal step is to repair projection-texture frame continuity. Treat
v0.portal5i Stable as the rollback runtime config until the new route can
sustain at least 1080/30, with 1080/60 as the desired default profile.
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
