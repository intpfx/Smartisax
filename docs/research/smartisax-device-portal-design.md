# Smartisax Device Portal Design

This is the first design for replacing the deleted HandShaker desktop assistant
with a browser-accessible Smartisax device portal. It intentionally builds on
the live-proven scrcpy mirror path instead of trying to recreate full screen
streaming inside a WebView on the first pass.

## Scope

Version:

```text
v0.portal0-smartisax-device-portal-design
```

Goal:

```text
Let the Mac browser access R2 device-management functions directly over the
same LAN by visiting the phone's Wi-Fi IP and a Smartisax portal port, while
keeping screen mirroring/control on the already-proven scrcpy path for now.
```

Non-goals for v0.portal0:

```text
No always-on unauthenticated LAN service.
No root filesystem browsing by default.
No WebRTC or MediaProjection screen stream yet.
No TNT/Desktop-mode replacement yet.
```

## Current Smartisax Fit

Current Smartisax shell facts:

```text
package:
  com.smartisax.browser

system role:
  /system/priv-app/SmartisaxShell

current privileged permissions:
  android.permission.MANAGE_DEBUGGING
  android.permission.WRITE_SECURE_SETTINGS

current bridge boundary:
  ShellActivity attaches SmartisaxNative only for
  file:///android_asset/shell/*
  and removes it before loading external web pages.
```

This bridge boundary is good for the on-device Smartisax control surface. The
Mac browser portal should be separate: a Wi-Fi HTTP service explicitly started
from Smartisax and protected with a pairing token.

## Recommended Architecture

```text
Mac
  tools/r2-mirror.sh
    - start scrcpy USB/wireless mirror
    - connect wireless ADB when Smartisax has enabled it
    - later open the LAN portal URL

  browser
    http://<r2_wifi_ip>:<portal_port>

R2 / Smartisax
  DevicePortalService
    - binds to the current wlan0 IPv4 address, not every interface
    - starts only after explicit Smartisax UI enable
    - requires pairing token for privileged endpoints
    - exposes small HTTP/JSON endpoints
    - serves a static portal UI

  ShellBridge
    - remains only for on-device Smartisax asset pages
    - can start/stop the portal and show its LAN URL plus pairing code
```

First port candidate:

```text
portal_port=37601
example_url=http://192.168.31.103:37601
```

## Endpoint Plan

Read-only first endpoints:

```text
GET /api/status
  returns device model, slot, boot state, WebView version, wireless ADB status

GET /api/files?path=/sdcard
  lists entries under allowed roots only

GET /api/file?path=/sdcard/...
  downloads a file from an allowed root
```

Controlled mutating endpoints:

```text
POST /api/wadb/enable
  calls the already-proven Smartisax privileged wireless ADB path

POST /api/wadb/disable
  disables wireless ADB

POST /api/files/upload
  uploads only into allowed roots such as /sdcard/Download/Smartisax
```

Deferred endpoints:

```text
POST /api/input
  possible later bridge to input tap/swipe/keyevent
  keep disabled while scrcpy handles control

GET /api/screen
  deferred until a MediaProjection/WebRTC/root screenrecord route is selected
```

## Security Model

v0.portal0 must be LAN-capable but not naked:

```text
listen_host=current wlan0 IPv4 address, for example 192.168.31.103
listen_port=37601
start condition=explicit Smartisax UI enable
stop condition=Smartisax UI disable, Wi-Fi disconnect, or service timeout
do not bind 0.0.0.0 unless a later audit proves it is needed
```

Token model:

```text
Smartisax generates a random session token when the portal starts.
The on-device Smartisax page shows:
  URL: http://<r2_wifi_ip>:37601
  pairing code: short human code
  session token / QR link: optional convenience

Browser flow:
  GET / returns the static pairing UI without sensitive data.
  User enters the pairing code or scans the QR link.
  API requests carry the session token in an Authorization header.

All /api/* endpoints require the token.
```

Network boundary:

```text
Allow:
  same-LAN Mac browser -> R2 Wi-Fi IP:37601

Do not require:
  adb forward
  USB cable
  Mac-side daemon

Fallback only:
  adb forward may remain as a developer rescue path, but it is not the product
  route.
```

File boundary:

```text
default allowed roots:
  /sdcard
  /sdcard/Download
  /sdcard/Pictures
  /sdcard/DCIM

root-only paths:
  disabled by default
  require a separate explicit UI toggle and a future live risk review
```

## Why Not Browser Screen Streaming First

scrcpy is already live-proven over USB and wireless ADB, including control.
Rebuilding that inside Smartisax would require a harder choice among:

```text
MediaProjection
  needs user consent unless a privileged/signature route is proven safe

MediaCodec + Surface capture
  deeper framework/system permission work

root screenrecord pipe
  simpler prototype but poorer latency and lifecycle behavior

WebRTC
  useful later, but adds signaling, encoding, and browser compatibility work
```

Therefore v0.portal0 should complement scrcpy rather than replace it.

## First Implementation Candidate

```text
v0.portal1-smartisax-lan-portal-noop
```

Candidate shape:

```text
Smartisax manifest:
  add DevicePortalService

Java:
  add tiny Wi-Fi-bound HTTP server
  add token generation
  add pairing code generation
  add /api/status only

Assets:
  add portal HTML/CSS/TS served by DevicePortalService

Mac:
  extend tools/r2-mirror.sh with:
    portal-url
    portal-open
```

Current wrapper seed:

```text
tools/r2-mirror.sh portal-url
  prints http://<r2_wifi_ip>:37601

live self-test on 2026-06-22:
  http://192.168.31.103:37601
```

Verification:

```text
offline:
  APK builds with stored/aligned resources.arsc
  no external-page JavaScript bridge exposure regression

live:
  Smartisax boots as current HOME
  wireless ADB control still works
  Smartisax UI enables the portal explicitly
  R2 displays http://<r2_wifi_ip>:37601 and a pairing code
  Mac browser opens http://<r2_wifi_ip>:37601 directly over LAN
  /api/status rejects missing/wrong token
  /api/status returns JSON with the correct token
  service binds only to the Wi-Fi IP and not to every interface
  service stops after Smartisax UI disable
```

Candidate status on 2026-06-22:

```text
variant:
  v0.portal1-smartisax-lan-portal-noop
Smartisax:
  v0.3.0/versionCode 6
APK sha256:
  6211e4ebc733daac45e66b05f9ea0b7075982e488e55378b3b72c052c23a4b13
super sparse:
  hard-rom/build/super-otatrust-v0.portal1-smartisax-lan-portal-noop.sparse.img
sparse sha256:
  8af6630b1911e9c697b02b4cca458f0d6609f8900046063c4372494d4a1ddd76
offline verifier:
  PASS_OFFLINE_IMAGE_V0PORTAL1_SMARTISAX_LAN_PORTAL_NOOP
live preflight:
  passed against the live v0.wadb2.2 B-slot device state
flash status:
  flashed to B slot and live-proven
live verifier:
  PASS_READ_ONLY_V0PORTAL1_SMARTISAX_LAN_PORTAL_NOOP
live smoke:
  Smartisax focused with Keyguard hidden
  Smartisax UI starts the portal explicitly
  R2 displays http://192.168.31.103:37601 and a pairing code
  Mac curl opens GET / directly over LAN without adb forward
  GET /api/status without token returns 401
  POST /api/pair with phone-displayed code returns token and status JSON
  authorized GET /api/status returns device status
  ss shows bind address [::ffff:192.168.31.103]:37601
known polish:
  in-page label still says SMARTISAX 0.2 even though PackageManager reports
  versionName 0.3.0/versionCode 6
```

Implemented in v0.portal1:

```text
DevicePortalService:
  binds to wlan0 IPv4 on port 37601
  serves GET /
  serves POST /api/pair
  serves token-gated GET /api/status

Not implemented yet:
  file listing/download/upload
  screen streaming
  input control
  root filesystem access
```

## v0.portal2 Remote Screen And Control Candidate

Version:

```text
v0.portal2-smartisax-remote-screen-control
```

Status on 2026-06-22:

```text
built: yes
offline verified: yes
live preflight: yes
flashed: no
```

Technology choice:

```text
Use token-gated PNG polling plus root input commands for the first live gate.
Defer WebRTC/H.264 until after the product loop is proven.
```

Reasoning:

```text
PNG polling:
  works with the existing tiny HTTP portal
  can use APatch/kp root through screencap immediately
  avoids MediaProjection consent and framework capture permissions
  avoids bundling libwebrtc or building a signaling stack before the feature
  shape is proven

WebRTC/H.264:
  likely better for latency and bandwidth later
  requires a deeper media pipeline decision: MediaProjection, Surface capture,
  screenrecord/MediaCodec, scrcpy-server reuse, or native encoder service
  should be treated as a video-layer upgrade after v0.portal2 proves browser
  access, pairing, frame delivery, and input control.
```

Implemented portal additions:

```text
GET /api/screen.png
  requires Authorization: Bearer <token>
  executes kp -c "screencap -p"
  returns image/png after validating PNG magic bytes

POST /api/input
  requires Authorization: Bearer <token>
  accepts:
    {"type":"tap","x":...,"y":...}
    {"type":"swipe","x1":...,"y1":...,"x2":...,"y2":...,"duration":...}
  clamps coordinates and duration
  executes kp -c "input tap ..." or kp -c "input swipe ..."

GET /api/status
  reports:
    screen=root-screencap-png
    input=root-input-command
```

Portal UI behavior:

```text
After pairing, the Mac browser can start/stop the screen stream.
Frames are fetched as blobs from /api/screen.png on a short interval.
Clicking the image sends a tap mapped through natural image dimensions.
Dragging the image sends a swipe mapped through natural image dimensions.
```

Candidate artifacts:

```text
Smartisax APK:
  hard-rom/build/apk/SmartisaxShell.apk
  sha256=6cdf114bd4e97173800d5057a24b7d29693df17b9bb2b1ff26668141ab8cf07c

system_b:
  hard-rom/build/system-otatrust-v0.portal2-smartisax-remote-screen-control.img
  sha256=8b6add09cf63da59cfe93cda433180fff0622a7be87ec14a145594e7abab3317

sparse super:
  hard-rom/build/super-otatrust-v0.portal2-smartisax-remote-screen-control.sparse.img
  sha256=24a2955b962595509e6799d79da299b068480815e81ddffa2a221b77a71a2cbc

offline result:
  PASS_OFFLINE_IMAGE_V0PORTAL2_SMARTISAX_REMOTE_SCREEN_CONTROL
```

Flash boundary:

```text
Required phrase:
  确认刷入 v0.portal2-smartisax-remote-screen-control B 槽

After flash:
  run tools/r2-verify-v0.portal2-smartisax-remote-screen-control.sh --read-only
  enable Device Portal from Smartisax
  pair from the Mac browser without adb forward
  confirm /api/screen.png returns screen PNG frames
  confirm browser tap/drag controls the phone
  check Smartisax logs for Java crash/ANR markers
```

## TNT/Desktop Follow-up

TNT remains a separate research line:

```text
v0.tnt0-desktop-mode-audit
```

Relevant retained packages:

```text
BostonScreenMirror
BostonCastHalService
SmartisanWirelessCast
Desktop
DesktopRecentsPsp
SmartisanDesktopSystemUI
```

The first TNT probe should check whether a virtual display route can trigger
Smartisan Desktop mode on the phone. It should not block the scrcpy/portal
replacement path.
