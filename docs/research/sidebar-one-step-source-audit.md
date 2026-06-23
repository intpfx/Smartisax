# Sidebar / One Step Source Audit

Generated: 2026-06-18

This is the focused RED-gate audit for `com.smartisanos.sidebar` / 一步. The
immediate ROM change is small: hide only the desktop launcher entry for
`SettingActivity`. The long-term value is the coupling map for reusing Sidebar
as a future Smartisax feature surface.

## Package Facts

```text
package: com.smartisanos.sidebar
system path: /system/priv-app/Sidebar/Sidebar.apk
stock sha256: b25634e3d101756b8d913308c9b0961f85f52c925f27307966fb56c8b6c914b5
versionCode: 30
versionName: 9.1.0
sharedUserId: android.uid.system
coreApp: true
directBootAware: true
defaultToDeviceProtectedStorage: true
static risk: RED
```

Preflight classifies this as RED because it is a priv-app, uses
`android.uid.system`, exports sensitive surfaces, declares providers, receives
boot, and participates in `MAIN` / `LAUNCHER` resolution. Therefore it must
stay a single-package gate and must not be batched with lower-risk app-entry
hiding.

## Launcher Target

Only this launcher category is removed in v0.26c:

```text
activity: com.smartisanos.sidebar.setting.SettingActivity
filter: 1
before: MAIN + DEFAULT + LAUNCHER
after: MAIN + DEFAULT
preserve:
  activity enabled
  android.app.shortcuts metadata
  revone_entry metadata -> com.smartisanos.sidebar.setting.RevOneSettingActivity
```

Source:

```text
reverse/smartisan-8.5.3-rom-static/jadx/system__system__priv-app__Sidebar__Sidebar.apk/resources/AndroidManifest.xml
  lines 243-261: SettingActivity launcher filter and metadata
```

## Preserved Manifest Surfaces

Do not remove or disable these as part of launcher hiding:

```text
service:
  com.smartisanos.sidebar.SidebarService exported=true

receivers:
  BootCompleteReceiver for BOOT_COMPLETED and QUICKBOOT_POWERON
  ShortcutReceiver, SyncDataReceiver, PickedContactReceiver, KeyguardReceiver,
  DictionaryReceiver, and other top-area receivers

providers:
  com.smartisanos.sidebar.call
  com.smartisanos.sidebar.sync
  com.smartisanos.sidebar.idea_pills_sync
  com.smartisanos.sidebar.forcetouch

feature intents:
  smartisanos.intent.action.BOOM_FONT
  com.smartisanos.sidebar.sticky.activity with recent_file, recent_photo,
  clipboard, and quick_snippet mime types
```

Source:

```text
AndroidManifest.xml lines 162-236: service, boot receiver, providers
AndroidManifest.xml lines 283-294: BoomFontActivity action
AndroidManifest.xml lines 333-371: sticky activities
```

## Runtime Model

`SettingActivity` is only the visible settings entry. It is not the runtime
service itself. The settings switch writes `Settings.Global side_bar_mode`:

```text
SettingActivity lines 75-100:
  switch listener calls Utils.switchSidebar(context, z)

Utils lines 650-655:
  isSidebarEnable reads side_bar_mode, default 1
  switchSidebar writes side_bar_mode to 1 or 0
```

`SidebarService` is the real app-side runtime. On create it resets
`side_bar_zoom_type` to `-1`, waits for user unlock if needed, and then calls
`initIfNeeded()`:

```text
SidebarService lines 43-55:
  reset side_bar_zoom_type, check UserManager.isUserUnlocked

SidebarService lines 77-95:
  initialize SidebarSyncProvider SQLite helper
  start PackagesMonitor
  OneStepScreen.onCreate
  SidebarController.init
  ZoomScreenController.init
  register keyguard and dictionary receivers
  bind intelligent words service
```

`SidebarController.init()` registers the app with the framework `sidebar`
service and attaches the side/top/content windows only if `side_bar_mode` is
enabled:

```text
SidebarController lines 158-164:
  ServiceManager.getService("sidebar")
  ISidebarService.registerSidebar(...)

SidebarController lines 193-240:
  create side/top/content/TNT areas
  attach windows if isPhoneSidebarEnable()

SidebarController lines 731-735:
  isPhoneSidebarEnable delegates to Utils.isSidebarEnable()
```

Framework-side helpers also depend on the same package and service:

```text
framework.jar smartisanos.util.SidebarHelper lines 380-400:
  binds com.smartisanos.sidebar/.SidebarService as UserHandle.OWNER

services.jar com.android.server.sidebar.AppServiceConnection lines 120-134:
  framework binds configured Sidebar app service and retries
```

This means future feature reuse can target either:

```text
1. Settings.Global policy knobs such as side_bar_mode / side_bar_zoom_type
2. framework sidebar service APIs guarded by android.permission.SIDEBAR_SERVICE
3. app-side providers, sticky activities, and window surfaces
```

but the package identity, UID, service name, provider authorities, and
framework bind path are structural contracts.

## Live Baseline Before v0.26c

Captured from live v0.26b:

```text
report:
  hard-rom/inspect/v0.26c-sidebar-source-audit/sidebar-live-readonly-baseline-20260618-194049.txt

device:
  boot_completed=1
  slot=_b
  bootanim=stopped
  verifiedbootstate=orange
  root uid=0 available
  SELinux Enforcing

package:
  pm path -> /system/priv-app/Sidebar/Sidebar.apk
  live sha256 -> b25634e3d101756b8d913308c9b0961f85f52c925f27307966fb56c8b6c914b5
  no /data/app shadow

runtime:
  com.smartisanos.sidebar process is running as uid 1000
  SidebarService is bound from the system process
  windows exist: sidebar_content_area, sidebar_top_area,
  sidebar_side_area_suck_view, sidebar_side_area_layout

settings:
  side_bar_mode=1
  sidebar_switch_status=0
  side_bar_zoom_type=-1
  squeeze_side_buttons=side_bar
```

The v0.26c live verifier must preserve these surfaces while removing only the
launcher listing.

## v0.26c Live-Proven ROM

```text
variant: v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
base: live-verified v0.26b sparse
base sha256: 599578445026fbf8d35edffc014b71e7507eba9ce2921a82d0d298465e020ff1

super sparse:
  hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1

retired local system image:
  hard-rom/build/system-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.img
  sha256=c0aaf672f208cf11d8849d1459b5eef571a1710e21d8672e62c45725c012f945

patched APK:
  hard-rom/build/apk/com.smartisanos.sidebar-launcher-hidden-v2cert.apk
  sha256=0c238bfb79a786ee28a325ca6983c5f4bc5d8877a19756a912968da9ecae93f2

package directory mtime:
  /system/priv-app/Sidebar
  mtime=0x6a33f9e0 (2026-06-18 22:00:00 +0800)
```

Offline verifier:

```text
hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-194804.txt

PASS:
  all five launcher-hidden APKs are present
  Sidebar changes only AndroidManifest.xml
  MAIN remains while LAUNCHER is removed from SettingActivity filter 1
  non-manifest ZIP members are byte-identical
  native library offsets remain stable
  APK Sig Block 42 is present
  expected AndroidManifest.xml digest boundary is present
  held-stock hidden path exists
  package directory mtimes are correct
  system_b sparse slice matches generated system image
  system_ext_b is retained from v0.26b
```

Preflight:

```text
tools/r2-live-flash-preflight.sh v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
PASS

required confirmation:
  确认刷入 v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump B 槽
```

Live flash and verifier:

```text
flash:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/flash-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-20260618-200032.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no, flashed
  super 9/9, erased misc, and rebooted.

boot wait:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/boot-wait-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-20260618-200633.txt
  PASS; boot=1, slot=_b, bootanim=stopped, verified=orange.

live verifier:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-device-20260618-200821.txt
  PASS; all five edited packages match expected /system hashes with shadow=no,
  user 0 is RUNNING_UNLOCKED, keyguard is not showing, all five launcher
  entries are absent, Sidebar shared UID is intact, SidebarService is live and
  system-bound, all four providers are present, explicit SettingActivity
  resolves, and sidebar_content_area/sidebar_top_area/sidebar_side_area windows
  are present.
```

The first post-boot verifier run failed because the phone was still
`RUNNING_LOCKED` with Keyguard showing. A second run after unlock exposed a
verifier-only check that searched `dumpsys package` for `SidebarService`; on
this build the authoritative service evidence is `dumpsys activity services`.
The verifier was corrected to check the live `ServiceRecord` and then passed.

## Live Acceptance Gate

For regression checks, the read-only verifier must continue to pass:

```bash
tools/r2-verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.sh --read-only
```

Acceptance requires:

```text
boot_completed=1, slot=_b, bootanim=stopped
root uid=0 available, SELinux Enforcing
all five edited packages match expected /system hashes
no /data/app shadows for the five packages
VideoPlayer, ScreenRecorderSmartisan, QuickSearch, VoiceAssistant, and Sidebar
  launcher entries absent
explicit Sidebar SettingActivity still resolves
SidebarService exists and is bound from system
four Sidebar providers remain present
sidebar_content_area/top/side windows remain present
side_bar_mode and related settings remain readable and sane
```

If any service/window/provider gate fails in a future run, treat v0.26c as
regressed even if the
desktop icon is gone.

## v0.29 Topbar Cleanup Candidate

User-selected UI target:

```text
Delete the stock One Step topbar controls and text:
  left/right task arrows
  One Step label
  settings gear
  exit/expand button

Keep the topbar area itself as a blank future feature slot.
Keep the One Step drag/status switching path working.
```

Source mapping:

```text
layout:
  res/layout/top_area_title_view.xml
  contains the four ImageViewImprove controls plus hard-coded "One Step" text.

binding code:
  TopAreaContentView.onFinishInflate()
  TopAreaContentView.updateTopUIBySidebarMode()
  TopAreaContentViewHolder

preserved behavior path:
  TopAreaRootView.show/requestStatus/updateDragWindow
  TopAreaContentView.requestStatus/requestShowShareList/requestShowNormalList
  TopAreaContentView.dispatchDragEvent
```

Implementation:

```text
tools/r2-build-sidebar-topbar-hide-apk.sh
tools/r2-hardrom-build-v0.29-sidebar-topbar-hide.sh
tools/r2-verify-v0.29-sidebar-topbar-hide.sh

APK:
  hard-rom/build/apk/com.smartisanos.sidebar-topbar-hidden-v2cert.apk
  sha256=d69e0c7d5960f623795b4c95d1d306f7a2c19b21b22bd6533296943fd4e6772b

changed APK members from the v0.26c launcher-hidden Sidebar shell:
  classes.dex
  res/layout/top_area_title_view.xml
```

Offline verifier:

```text
hard-rom/inspect/v0.29-sidebar-topbar-hide/verify-v0.29-sidebar-topbar-hide-offline-image-20260618-222711.txt

PASS:
  topbar_slot_preserved=ok
  topbar_children_deleted=ok
  topbar_smali_references_removed=ok
  launcher-hidden manifest remains intact
  system_b sparse slice matches generated v0.29 system image
  system_ext_b/product_b are retained from v0.28
```

Preflight:

```text
tools/r2-live-flash-preflight.sh v0.29-sidebar-topbar-hide
PASS

required confirmation:
  确认刷入 v0.29-sidebar-topbar-hide B 槽
```

Live result:

```text
flash report:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/flash-v0.29-sidebar-topbar-hide-20260618-223822.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed
  sparse super 9/9, erased misc, and rebooted.

boot wait:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/boot-wait-v0.29-sidebar-topbar-hide-20260618-224404.txt
  PASS; boot_completed=1, slot=_b, bootanim=stopped, verified=orange.

device verifier:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/verify-v0.29-sidebar-topbar-hide-device-20260618-224500.txt
  PASS; root works, keyguard is not showing, launcher is focused, Sidebar
  window markers remain present, live Sidebar APK hash matches the v0.29 APK,
  Sidebar launcher query reports No activities found, and v0.27/v0.28 package
  removals remain absent.

visual screenshot:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/screenshot-v0.29-sidebar-topbar-hide-20260618-224507.png
  The old topbar controls/text are absent and the topbar area remains blank for
  future use.

Status: LIVE_PASS.
```
