# Launcher Entry Hide Audit

Generated: 2026-06-18 19:06:38

This read-only audit covers the user's next requested target: keep the
features working, but remove their desktop launcher entries for 闪念胶囊,
视频播放器, 屏幕录制, 搜索, and 一步.

This is not a hard delete and not a runtime `pm disable` plan. The safer ROM
route is manifest-only launcher-surface surgery: remove only
`android.intent.category.LAUNCHER` from the identified `MAIN` launcher
intent-filter while keeping the activity enabled and preserving non-launcher
intent filters, services, providers, receivers, permissions, and explicit
settings routes.

## Summary

| feature | package | static_replace_level | launcher_component | filter_index | stage |
| --- | --- | --- | --- | --- | --- |
| 视频播放器 | com.smartisanos.videoplayerproject | ORANGE | com.smartisanos.videoplayerproject.MainActivity | 1 | v0.26a first manifest-only candidate |
| 屏幕录制 | com.smartisanos.screenrecorder | ORANGE | com.smartisanos.screenrecorder.EmptyActivity | 1 | v0.26a first manifest-only candidate |
| 搜索 | com.smartisanos.quicksearch | ORANGE | com.android.quicksearchbox.SearchActivity | 2 | v0.26a first manifest-only candidate |
| 闪念胶囊 | com.smartisanos.sara | ORANGE | com.smartisanos.sara.bubble.SettingActivity | 1 | v0.26b after first batch passes live |
| 一步 | com.smartisanos.sidebar | RED | com.smartisanos.sidebar.setting.SettingActivity | 1 | v0.26c live-proven after dedicated RED source gate |

## Proposed Staging

First live candidate:

```text
v0.26a: 视频播放器 + 屏幕录制 + 搜索
```

Reason: these three are the smallest set with clear launcher-only surfaces and
without `android.uid.system`. They still need package-specific manifest-only
APK build and offline verification before any flash authorization.

Follow-up candidates:

```text
v0.26b: 闪念胶囊 / com.smartisanos.sara
v0.26c: 一步 / com.smartisanos.sidebar
```

Reason: Sara is a large VoiceAssistant priv-app with speech/provider/shortcut
coupling. Sidebar/One Step is a core priv-app using
`sharedUserId=android.uid.system`, so it was not batched with lower-risk
targets. It now has a dedicated source audit and live-proven v0.26c image.

## Candidate Details

### 视频播放器 / `com.smartisanos.videoplayerproject`

```text
source: system:system/priv-app/VideoPlayer/VideoPlayer.apk
source_name: system__system__priv-app__VideoPlayer__VideoPlayer.apk
launcher_component: com.smartisanos.videoplayerproject.MainActivity
launcher_filter_index: 1
launcher_filter: actions=android.intent.action.MAIN; categories=android.intent.category.LAUNCHER,android.intent.category.MONKEY
preserve: preserve VIEW/BROWSABLE video and playlist handlers plus VideoProvider
preserved_non_launcher_filters: filter 2: actions=android.intent.action.VIEW; categories=android.intent.category.BROWSABLE,android.intent.category.DEFAULT; data=scheme=rtsp | filter 3: actions=android.intent.action.VIEW; categories=android.intent.category.BROWSABLE,android.intent.category.DEFAULT; data=mimeType=application/sdp,mimeType=video/3gp,mimeType=video/3gpp,mimeType=video/3gpp2,mimeType=video/avi,mimeType=video/divx,mimeType=video/m4v,mimeType=video/mp2ts... | filter 4: actions=android.intent.action.VIEW; categories=android.intent.category.BROWSABLE,android.intent.category.DEFAULT; data=mimeType=application/vnd.apple.mpegurl,mimeType=application/x-mpegurl,mimeType=audio/mpegurl,mimeType=audio/x-mpegurl,scheme=http,scheme=https
component_counts: components=2 providers=1 exported=1
static_replace_level: ORANGE
risk_note: priv-app but no sensitive sharedUserId; same activity keeps VIEW video/http/content/file filters
recommendation: remove only android.intent.category.LAUNCHER from MainActivity filter 1; keep MainActivity enabled
preflight_flags: ORANGE: package is a priv-app; YELLOW: package declares 1 content providers; YELLOW: package exposes 1 exported components; YELLOW: package participates in core intent resolution: android.intent.action.MAIN, android.intent.action.VIEW, android.intent.category.BROWSABLE, android.intent.category.LAUNCHER; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior
```

### 屏幕录制 / `com.smartisanos.screenrecorder`

```text
source: system:system/priv-app/ScreenRecorderSmartisan/ScreenRecorderSmartisan.apk
source_name: system__system__priv-app__ScreenRecorderSmartisan__ScreenRecorderSmartisan.apk
launcher_component: com.smartisanos.screenrecorder.EmptyActivity
launcher_filter_index: 1
launcher_filter: actions=android.intent.action.MAIN; categories=android.intent.category.LAUNCHER
preserve: preserve ScreenRecorderService, ScreenshotToolService, settings/options/countdown/permission activities, and provider
preserved_non_launcher_filters: no non-launcher filters on com.smartisanos.screenrecorder.EmptyActivity; preserve other package components
component_counts: components=10 providers=1 exported=3
static_replace_level: ORANGE
risk_note: priv-app launcher trampoline; recording services/settings activities must remain resolvable
recommendation: remove only android.intent.category.LAUNCHER from EmptyActivity launcher filter; keep services and settings components
preflight_flags: ORANGE: package is a priv-app; YELLOW: package declares 1 content providers; YELLOW: package exposes 3 exported components; YELLOW: package participates in core intent resolution: android.intent.action.MAIN, android.intent.category.LAUNCHER; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior
```

### 搜索 / `com.smartisanos.quicksearch`

```text
source: system:system/app/QuickSearchBoxSmartisan/QuickSearchBoxSmartisan.apk
source_name: system__system__app__QuickSearchBoxSmartisan__QuickSearchBoxSmartisan.apk
launcher_component: com.android.quicksearchbox.SearchActivity
launcher_filter_index: 2
launcher_filter: actions=android.intent.action.MAIN; categories=android.intent.category.LAUNCHER
preserve: preserve GLOBAL_SEARCH, SEARCH, launchSpeech, TNTSearchActivity, providers, and boot receiver
preserved_non_launcher_filters: filter 1: actions=android.intent.action.launchSpeech; categories=android.intent.category.DEFAULT | filter 3: actions=android.search.action.GLOBAL_SEARCH; categories=android.intent.category.DEFAULT | filter 4: actions=android.search.action.GLOBAL_SEARCH; categories=android.intent.category.DEFAULT; data=scheme=qsb.corpus | filter 5: actions=android.intent.action.SEARCH; categories=android.intent.category.DEFAULT
component_counts: components=14 providers=5 exported=6
static_replace_level: ORANGE
risk_note: system app with boot receiver and providers; launcher filter is separate from GLOBAL_SEARCH/SEARCH filters
recommendation: remove only android.intent.category.LAUNCHER from SearchActivity MAIN launcher filter; keep search intent filters
preflight_flags: YELLOW: package declares 5 content providers; YELLOW: package exposes 6 exported components; YELLOW: package participates in core intent resolution: android.intent.action.BOOT_COMPLETED, android.intent.action.MAIN, android.intent.category.LAUNCHER; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior
```

### 闪念胶囊 / `com.smartisanos.sara`

```text
source: system:system/priv-app/VoiceAssistant/VoiceAssistant.apk
source_name: system__system__priv-app__VoiceAssistant__VoiceAssistant.apk
launcher_component: com.smartisanos.sara.bubble.SettingActivity
launcher_filter_index: 1
launcher_filter: actions=android.intent.action.MAIN; categories=android.intent.category.LAUNCHER
preserve: preserve bubble/shell/voice command activities, providers, receivers, services, and idea-pill settings routes
preserved_non_launcher_filters: no non-launcher filters on com.smartisanos.sara.bubble.SettingActivity; preserve other package components
component_counts: components=47 providers=6 exported=9
static_replace_level: ORANGE
risk_note: large priv-app VoiceAssistant package with speech, provider, locale, accessibility, and Smartisan shortcut coupling
recommendation: after source review, remove only android.intent.category.LAUNCHER from SettingActivity launcher filter
preflight_flags: ORANGE: package is a priv-app; YELLOW: package declares 6 content providers; YELLOW: package exposes 9 exported components; YELLOW: package participates in core intent resolution: android.intent.action.LOCALE_CHANGED, android.intent.action.MAIN, android.intent.category.LAUNCHER; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior
```

### 一步 / `com.smartisanos.sidebar`

```text
source: system:system/priv-app/Sidebar/Sidebar.apk
source_name: system__system__priv-app__Sidebar__Sidebar.apk
launcher_component: com.smartisanos.sidebar.setting.SettingActivity
launcher_filter_index: 1
launcher_filter: actions=android.intent.action.MAIN; categories=android.intent.category.DEFAULT,android.intent.category.LAUNCHER
preserve: preserve SidebarService, boot/keyguard/top-area receivers, providers, sticky activities, and explicit settings routes
preserved_non_launcher_filters: no non-launcher filters on com.smartisanos.sidebar.setting.SettingActivity; preserve other package components
component_counts: components=33 providers=4 exported=8
static_replace_level: RED
risk_note: priv-app coreApp with sharedUserId android.uid.system; do not batch with lower-risk targets
recommendation: after focused source/graph review and a dedicated gate, remove only LAUNCHER from SettingActivity; keep DEFAULT/explicit access
preflight_flags: ORANGE: package is a priv-app; RED: package uses sensitive sharedUserId android.uid.system; YELLOW: package declares 4 content providers; YELLOW: package exposes 8 exported components; YELLOW: package participates in core intent resolution: android.intent.action.BOOT_COMPLETED, android.intent.action.MAIN, android.intent.category.LAUNCHER; ORANGE: same-package replacement must preserve manifest, authorities, ABI, resources, signatures, and package cache behavior
current_gate: v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump is flashed and live-verified on B slot
source_audit: docs/research/sidebar-one-step-source-audit.md
```

## Build Gate

For a manifest-only candidate, the APK-level verifier must prove:

```text
AndroidManifest.xml changed only as expected
classes*.dex byte-identical
resources.arsc byte-identical
native libraries/assets byte-identical
package name/version/sharedUserId/permissions/providers/services/receivers unchanged
the original signing material remains readable by the system-partition parser
the edited manifest no longer resolves MAIN+LAUNCHER for selected components
all preserved feature intents still resolve
```

This is a new gate. The v0.24 live result proves resources-only APK replacement
on the current line, but it does not by itself prove manifest component changes.

## Live Verification After Any Future Flash

Run read-only checks after boot:

```bash
adb -s bb12d264 shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim'
tools/r2-root.sh status
adb -s bb12d264 shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head"
adb -s bb12d264 shell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER'
```

Expected launcher result for the selected package subset: the removed desktop
components are absent from `MAIN + LAUNCHER` resolution, while package paths
remain under `/system` and feature-specific intent filters still resolve.

## Generated Files

```text
docs/research/launcher-entry-hide-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/launcher-entry-hide-audit.tsv
```
