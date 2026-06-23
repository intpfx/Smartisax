# HandShaker Replacement And R2 Mirroring Plan

This note tracks the replacement path for the deleted Smartisan HandShaker
desktop-assistant feature. It covers Mac-side screen mirroring/control, a future
browser-access portal, and a separate TNT/Desktop-mode research line.

## Current Boundary

HandShaker itself is removed from the ROM by the accepted
`v0.28-wallet-handshaker-debloat` line. The later `v0.usb2` vendor cleanup also
physically removes `/vendor/etc/cdrom_install.iso`, so macOS no longer receives
the old Smartisan transfer-tool virtual CD-ROM.

The TNT/projection stack was deliberately preserved during earlier WebView space
work:

```text
/system/app/BostonScreenMirror
/system/priv-app/BostonCastHalService
/system/app/SmartisanWirelessCast
/system/priv-app/Desktop
/system/priv-app/DesktopRecentsPsp
/system/priv-app/SmartisanDesktopSystemUI
```

The current live ROM line is
`v0.wadb2.2-smartisax-wireless-adb-binder-transact`, which proves Smartisax can
enable wireless ADB and expose `192.168.31.103:42701` as an online ADB
transport.

## v0.mirror0 Live Proof

`scrcpy` 4.0 was installed on the Mac through Homebrew. This does not change the
ROM; scrcpy temporarily pushes its server through ADB during a session.

Evidence directory:

```text
hard-rom/inspect/v0.mirror0-scrcpy-live-proof/
```

USB video smoke:

```text
command:
  scrcpy -s bb12d264 --no-window --no-audio --time-limit=8 \
    --record=hard-rom/inspect/v0.mirror0-scrcpy-live-proof/scrcpy-usb-smoke.mp4

result:
  scrcpy server pushed
  device identified as SMARTISAN / Android 11
  recording completed
  mp4: h264 1080x2340
```

USB video plus control smoke:

```text
command:
  scrcpy -s bb12d264 --no-window --no-audio --time-limit=12 \
    --record=hard-rom/inspect/v0.mirror0-scrcpy-live-proof/scrcpy-usb-control-smoke.mp4
  adb -s bb12d264 shell input keyevent 3
  adb -s bb12d264 shell input swipe 900 1800 900 900 300

result:
  recording completed
  mp4: h264 1080x2340, duration 12.035078 seconds
  ADB input reached the live device
```

Wireless ADB video smoke:

```text
command:
  scrcpy -s 192.168.31.103:42701 --no-window --no-audio --time-limit=8 \
    --record=hard-rom/inspect/v0.mirror0-scrcpy-live-proof/scrcpy-wireless-smoke.mp4

result:
  recording completed over tcpip transport
  mp4: h264 1080x2340, duration 7.320833 seconds
```

Interactive window smoke:

```text
command:
  tools/r2-mirror.sh usb --no-audio --time-limit=8

result:
  scrcpy renderer: metal
  texture: 1080x2340
  time-limited interactive mirror window exited cleanly
```

Verdict: USB and wireless scrcpy mirroring are live-proven enough to serve as
the first HandShaker replacement layer for screen viewing and control.

## v0.mirror1 Mac Wrapper

`tools/r2-mirror.sh` is the first Mac-side wrapper:

```text
tools/r2-mirror.sh [auto|usb|wireless] [scrcpy-args...]
tools/r2-mirror.sh record <output.mp4> [seconds] [auto|usb|wireless]
tools/r2-mirror.sh connect-wireless [host:port]
tools/r2-mirror.sh portal-url [auto|usb|wireless] [port]
tools/r2-mirror.sh devices
```

Default behavior:

```text
auto mode prefers USB serial bb12d264
if USB is unavailable, it falls back to wireless ADB
WIRELESS_SERIAL defaults to 192.168.31.103:42701
wireless mode tries adb connect when the preferred tcpip transport is not
already listed as online
```

The first script self-test passed:

```text
tools/r2-mirror.sh record \
  hard-rom/inspect/v0.mirror0-scrcpy-live-proof/r2-mirror-script-usb-smoke.mp4 \
  5 usb
```

Wireless reconnect self-test:

```text
tools/r2-mirror.sh connect-wireless
Wireless adb target online: 192.168.31.103:42701
```

LAN portal URL self-test:

```text
tools/r2-mirror.sh portal-url
http://192.168.31.103:37601
```

## Next Routes

1. `v0.mirror1-mac-wrapper`
   Polish the wrapper into a user-facing Mac entrypoint: device discovery,
   optional wireless reconnect, recording switches, bitrate/size presets, and a
   small launcher script or app bundle.

2. `v0.portal0-smartisax-device-portal-design`
   Design a browser portal for `http://<r2_wifi_ip>:37601` over the same LAN.
   First scope should be portal status plus a constrained file browser. The
   service must be explicitly enabled from Smartisax and require a pairing
   token before any API access.

3. `v0.tnt0-desktop-mode-audit`
   Reverse and live-test the retained TNT/Desktop/projection stack. The most
   promising probe is whether scrcpy virtual-display support or another Android
   display route can trigger Smartisan Desktop/TNT mode without requiring a real
   Miracast receiver on macOS.

## Safety Notes

- Do not expose root filesystem browsing over LAN by default.
- The product route is direct LAN access from Mac browser to R2 Wi-Fi IP.
  `adb forward` may remain only as a developer rescue path.
- Treat TNT/Desktop work as a high-uncertainty research line. Keep it separate
  from the proven scrcpy replacement path.
