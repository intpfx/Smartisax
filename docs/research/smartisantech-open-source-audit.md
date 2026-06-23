# SmartisanTech Open Source Audit

Date: 2026-06-19

Scope: read-only review of the public SmartisanTech GitHub organization for
relevance to Smartisax hard-ROM work on Smartisan R2 / Smartisan OS 8.5.3 /
Android 11.

## Verdict

The public SmartisanTech repositories are useful as historical source
intelligence, especially for One Step / Sidebar architecture, Smartisan
framework APIs, old framework service wiring, and SELinux service registration.
They are not a directly buildable R2 / Android 11 / Smartisan OS 8.5.3 source
tree, and they do not provide a ready BrowserChrome, modern WebView, R2 ROM
builder, or SmartisanUpdater source route.

The strongest practical use is to compare old One Step contracts against the
current R2 `Sidebar.apk` and framework behavior before deeper Sidebar feature
work.

## High-Value Repositories

| Repository | Relevance | Use For This Project |
| --- | --- | --- |
| https://github.com/SmartisanTech/packages_apps_OneStep | High | Historical One Step UI app, package `com.smartisanos.sidebar`, service/activity naming, drag/status surfaces, top/sidebar UI classes. |
| https://github.com/SmartisanTech/android_frameworks_base | High | Historical `android.view.onestep`, `OneStepManagerService`, WindowManager/SystemUI/Keyguard integration clues. |
| https://github.com/SmartisanTech/android_frameworks_smartisanos-base | Medium | Smartisan framework helper/API/resource layer clues such as Sidebar utilities and Smartisan UI contracts. |
| https://github.com/SmartisanTech/SmartisanOS-SDK | Medium | Third-party One Step API surface, `OneStepHelper`, metadata conventions, sample-level integration hints. |
| https://github.com/SmartisanTech/android_external_sepolicy | Medium | Historical `onestep_service` service manager context and SELinux type reference. |
| https://github.com/SmartisanTech/android_frameworks_native | Medium | Historical native input/window changes for One Step window transitions. |
| https://github.com/SmartisanTech/android_build | Medium | Historical build integration of Smartisan framework and One Step/Big Bang packages. |
| https://github.com/SmartisanTech/android | Medium | Repo manifest and README tying the One Step / Big Bang source set together. |

## Useful Source Clues

The `android` manifest README says the release is One Step / Big Bang source
for Android 6.0.1 on Nexus 6, and explicitly lists the affected projects:
`frameworks_base`, `frameworks_native`, `packages_apps_OneStep`, `build`,
`external_sepolicy`, `frameworks_smartisanos-base`, and `SmartisanSDK`.

The same README is important for WebView expectations: it says the opened Big
Bang code did not support WebView and would need browser-engine changes for
that. That confirms these public repos are not a shortcut for the current R2
WebView modernization route.

The One Step app should be used as a historical comparison point for:

- `AndroidManifest.xml`: package identity, `android.uid.system`,
  `coreApp`, `persistent`, and launcher/settings activity shape.
- `SidebarService.java`: service initialization and resume behavior.
- Sidebar view/controller classes such as `TopView`, `TopItemView`,
  `SidebarRootView`, and `ContentView`.

The framework source should be used as a protocol reference for:

- `android.view.onestep` AIDL/API shape.
- `OneStepManagerService` methods such as `bindOneStepUI`,
  `requestEnterOneStepMode`, `requestExitOneStepMode`, `resetWindow`, and
  state observer callbacks.
- permissions such as `android.permission.ONE_STEP` and
  `android.permission.ONE_STEP_SERVICE`.

The SELinux repository records a historical `onestep` service context mapped to
`u:object_r:onestep_service:s0`. Treat this as a naming and registration clue
only; Android 11 policy on R2 must be analyzed from the actual ROM.

## Low Or No Direct Value

These repositories are not useful for the current R2 hard-ROM/WebView/Sidebar
work except as broad historical or GPL-compliance context:

- `SmartisanOS_Kernel_Source`, `T1Kernel`, `T2Kernel`, `U1Kernel`, `M1Kernel`:
  old device kernel sources, not R2/kona.
- `SmartisanOS_ffmpeg`: multimedia library source, unrelated to current
  WebView/Sidebar/Updater work.
- `Wrench`, `Wrench-releases`: Android desktop-control tool, not ROM source.
- `SmartisanOS_Build_Release`, `android_device_moto_shamu`: Nexus 6
  experience build/device tree, not R2.
- `T1Bash`, `T1Tar`, `T1Busybox`, `libraw`, `email-ext-plugin`: unrelated to
  current system modification goals.

## Project Guidance

1. For Sidebar/One Step feature work, pull and compare the historical
   `packages_apps_OneStep` and `android_frameworks_base` source against the
   current R2 reverse output. Use it to name methods, states, permissions, and
   service contracts, not to directly transplant code.
2. For v0.29+ Sidebar topbar and future blank-slot feature work, prioritize
   `TopView`, `TopItemView`, `SidebarRootView`, `ContentView`,
   `SidebarService`, and framework `OneStepManagerService` comparisons.
3. For WebView modernization, continue the current source-built
   `SystemWebView.apk` Route A path. The public SmartisanTech repos do not
   provide a modern WebView donor or R2 WebView integration shortcut.
4. For SmartisanUpdater, do not spend time in these repos unless a new repo or
   branch appears; no obvious updater source was found in the public
   organization.
5. For SELinux/service changes, use the old `onestep_service` entries only as
   historical labels. Any R2 experiment still needs local Android 11 policy
   extraction, no-op gates, and live verification.
