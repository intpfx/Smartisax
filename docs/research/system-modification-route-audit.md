# System Modification Route Audit

Date: 2026-06-18.

Purpose:

```text
Translate user-facing system modification requests into concrete hard-ROM
routes, current confidence, required no-op/live gates, and the next safe
step. This report is generated read-only and does not authorize flashing.
```

Summary:

```text
routes=11
confidence_counts=apk_semantics_proven_offline_gated=1, framework_candidate_offline_gated=1, known_failed_red=1, live_functional_ux_pending=1, mapped_but_no_component_gate=1, proven_live=2, proven_live_pattern=1, red_requires_new_gates=2, toolchain_offline_proven_coverage_incomplete=1
```

Core conclusion:

```text
We now have enough source and graph structure to choose precise edit
surfaces. The remaining confidence boundary is live acceptance of each
replacement layer: SettingsSmartisan, SmartisanSystemUI, framework-res,
and later SettingsProvider/Keyguard/Launcher/Phone each need their own
gate. Do not transfer a pass from one layer to another.
```

How to use:

```bash
tools/r2-system-modification-route-audit.py
tools/r2-system-modification-route-audit.py --package-action com.android.phone:replace
tools/r2-rom-mod-preflight.py <package> --action delete
tools/r2-live-flash-preflight.sh <variant>
```

## Route Matrix

| route_id | target | action | static_level | confidence | required_gate | next_step |
| --- | --- | --- | --- | --- | --- | --- |
| delete_optional_app | optional stock/system app | delete | YELLOW | proven_live_pattern | Package-specific preflight plus local v0.4 rollback sparse image. | Use tools/r2-rom-mod-preflight.py <package> --action delete, then build a small isolated ROM variant. |
| same_package_browser_replace | BrowserChrome same package | replace | RED | known_failed_red | Fresh package-source graph review, no-op/minimal probe, and explicit rollback plan. | Prefer lower-risk modern browser routes unless the user explicitly wants another same-package browser experiment. |
| settings_core_apk_patch | SettingsSmartisan behavior patches | replace | RED | proven_live | v0.25 current-base SettingsSmartisan no-op has booted and verified live. | For native dark mode, v0.11 has boot/package/hash plus UiMode/SystemUI functional proof; next manually validate the Settings row and QS editor UX. |
| systemui_core_apk_patch | SmartisanSystemUI behavior patches | replace | RED | proven_live | current-base SmartisanSystemUI certprobe no-op has booted and verified live. | SystemUI tile creation is functionally proven on v0.11; next validate the Smartisan QS editor candidate path, then decide whether default-visible QS seeding or SettingsSmt regis... |
| native_dark_mode | native toggleDarkMode across SettingsSmartisan and SystemUI | multi-apk-code | N/A | live_functional_ux_pending | Dark-mode live-state, Settings no-op live gate, SystemUI no-op live gate, combined v0.11 live boot/package proof, reversible UiMode/SystemUI functional proof, then manual Settin... | Manually validate Settings dark-mode row visibility/click behavior and Smartisan QS editor candidate behavior; then choose default-visible seeding or leave editor-first. |
| settingsprovider_defaults | SettingsProvider widget/default settings | replace | RED | mapped_but_no_component_gate | Build and live-verify a SettingsProvider no-op gate before default seeding or migrations. | Keep default-visible dark-mode tile as a later decision after live QS state is captured. |
| language_visible_picker | Smartisan visible language picker | replace | RED | apk_semantics_proven_offline_gated | v0.25 current-base SettingsSmartisan no-op live gate plus language live-state capture. | After dark-mode priority work allows, rebuild/test the visible list before coupling it to framework resource pruning. |
| language_framework_assets | framework-res, framework-smartisanos-res, android static overlays | resource-prune | RED | framework_candidate_offline_gated | v0.12 framework-res no-op must boot live before v0.10 language hard-prune. | Flash only after explicit confirmation; verify Resources.getSystem().getAssets().getLocales() and boot UI. |
| language_app_resource_prune | package-local non-English/non-Chinese resources | resource-prune | N/A | toolchain_offline_proven_coverage_incomplete | Build sparse super for v0.13, then verify and live-test selected low-exposure package batch. | Continue from Tier1a/Tier1b candidates before core APEX, provider, keyboard, phone, or permission packages. |
| keyguard_launcher_boot_surface | Keyguard and Launcher | replace | N/A | red_requires_new_gates | Focused graph/source review plus per-component no-op gate and rollback strategy. | Do not edit until the user explicitly chooses this risk tier. |
| phone_telephony_surface | TeleService, Telecom, TelephonyProvider, InCallUI, MMS | replace | RED | red_requires_new_gates | Separate source graph, no-op gates, and live call/SIM validation before behavior changes. | Defer until lower-risk language/resource gates have passed. |

## Gate Order For Current Goals

```text
1. Capture dark-mode and language live-state read-only when the phone is visible to adb.
2. Keep the v0.25 current-base SettingsSmartisan live proof as the Settings behavior patch gate.
3. Keep the current-base SmartisanSystemUI live proof as the SystemUI behavior patch gate.
4. Treat v0.11 boot/package/hash plus UiMode/SystemUI functional proof as live; next manually prove Settings row and QS editor UX.
5. Flash/verify v0.12 framework-res no-op before v0.10 framework language pruning.
6. Promote low-exposure APK-only language prune candidates into ROM images in small batches.
7. Only then move toward SettingsProvider defaults, Keyguard/Launcher, or phone/telephony surfaces.
```

Generated TSV:

```text
reverse/smartisan-8.5.3-rom-static/manifest/system-modification-route-audit.tsv
```
