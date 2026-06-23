# WebView ROM Design Plan

Generated: 2026-06-20 01:40:22

This is a read-only offline planning report. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Evidence State

| Gate | Status | Evidence | Impact |
| --- | --- | --- | --- |
| framework_contract_audit | PASS | docs/research/webview-framework-contract-audit.md | unblocks the corresponding design precondition |
| v0.31_offline_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt | unblocks the corresponding design precondition |
| browser_webview_live_state_capture | PASS | hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt | unblocks the corresponding design precondition |
| v0.31_live_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt | unblocks the corresponding design precondition |
| modern_donor_inbox | PASS | candidate_count=2; report=hard-rom/inspect/browser-webview-donor-inbox/webview-donor-inbox-audit.json | modern source-built/donor material is present; candidate-specific signing and live gates still control design promotion |
| a_sig_package_manager_gate | OFFLINE_PM_ACCEPTANCE_RECORDED | verdict=OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE; report=docs/research/webview-a-sig-package-manager-audit.md | stock-carrier system-scan PackageManager acceptance is recorded offline; live proof is still required |
| latest_v0.31_offline_report | RECORDED | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt | stock provider near-noop image remains offline-only until live flash/verification |
| route_a_image_capacity | PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY | candidate_apk=262686911; product_free=28672; report=docs/research/webview-route-a-image-capacity-audit.md | blocks the current product_b-only Route A image even though donor shape and A-SIG evidence are ready |
| system_b_space_source_audit | SYSTEM_B_SPACE_SOURCE_USER_SELECTED_LOW_RESERVE | recommended=user_selected_no_projection_print_preserving; allocated=45912064; margin_to_reserved_target=-6471586; preferred_extra=smartisan_wallpapers_resource_pack; extra_allocated=86925312; extra_margin_to_reserved_target=34541662; report=docs/research/webview-system-space-source-audit.md | records the selected system_b space source plus the current preferred extra source for a full-ABI layout; user selection and reserve/layout acceptance still gate image work |

## Candidate ROM Designs

| Candidate | Route | Status | Partition scope | ROM actions | Blockers |
| --- | --- | --- | --- | --- | --- |
| stock-webview-baseline | ROUTE_A_ADAPT_IN_PLACE | DESIGN_ONLY | product_b only for the first donor-backed image if no framework/provider config changes are needed | replace /product/app/webview as package com.android.webview; keep public base path /product/app/webview/webview.apk for the first gate; preserve all version-matched splits/native libs/resources | stock baseline is only a shape/reference candidate, not a modern donor; current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit |
| inbox-SystemWebView-stock-carrier-2e2b2c3c05ba | ROUTE_A_ADAPT_IN_PLACE | BLOCKED_CAPACITY | product_b only for the first donor-backed image if no framework/provider config changes are needed | replace /product/app/webview as package com.android.webview; keep public base path /product/app/webview/webview.apk for the first gate; preserve all version-matched splits/native libs/resources | current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit |
| inbox-SystemWebView-582e602b3ac5 | ROUTE_A_ADAPT_IN_PLACE | BLOCKED_CAPACITY | product_b only for the first donor-backed image if no framework/provider config changes are needed | replace /product/app/webview as package com.android.webview; keep public base path /product/app/webview/webview.apk for the first gate; preserve all version-matched splits/native libs/resources | current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit |

### stock-webview-baseline

- Route: `ROUTE_A_ADAPT_IN_PLACE`
- Status: `DESIGN_ONLY`
- Partition scope: product_b only for the first donor-backed image if no framework/provider config changes are needed
- Filesystem actions: write package cluster under image path /app/webview; restore uid/gid/mode/SELinux; e2fsck -fy then -fn; dump every installed APK and verify sha256/unzip
- Package/cache actions: bump /product/app/webview directory mtime beyond live package_cache; remove/regenerate stale oat/vdex inside the provider package directory if present; do not clear /data package_cache without explicit approval
- Verification gates: offline donor audit PASS; offline bundle audit PASS/PASS_STANDALONE; v0.31 live-state capture PASS; v0.31 live provider gate PASS; post-boot cmd webviewupdate and dumpsys webviewupdate; Settings WebView selector; Big Bang/WebView surfaces; browser resolver; keyguard and launcher
- Blockers: stock baseline is only a shape/reference candidate, not a modern donor; current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit

### inbox-SystemWebView-stock-carrier-2e2b2c3c05ba

- Route: `ROUTE_A_ADAPT_IN_PLACE`
- Status: `BLOCKED_CAPACITY`
- Partition scope: product_b only for the first donor-backed image if no framework/provider config changes are needed
- Filesystem actions: write package cluster under image path /app/webview; restore uid/gid/mode/SELinux; e2fsck -fy then -fn; dump every installed APK and verify sha256/unzip
- Package/cache actions: bump /product/app/webview directory mtime beyond live package_cache; remove/regenerate stale oat/vdex inside the provider package directory if present; do not clear /data package_cache without explicit approval
- Verification gates: offline donor audit PASS; offline bundle audit PASS/PASS_STANDALONE; v0.31 live-state capture PASS; v0.31 live provider gate PASS; post-boot cmd webviewupdate and dumpsys webviewupdate; Settings WebView selector; Big Bang/WebView surfaces; browser resolver; keyguard and launcher
- Blockers: current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit

### inbox-SystemWebView-582e602b3ac5

- Route: `ROUTE_A_ADAPT_IN_PLACE`
- Status: `BLOCKED_CAPACITY`
- Partition scope: product_b only for the first donor-backed image if no framework/provider config changes are needed
- Filesystem actions: write package cluster under image path /app/webview; restore uid/gid/mode/SELinux; e2fsck -fy then -fn; dump every installed APK and verify sha256/unzip
- Package/cache actions: bump /product/app/webview directory mtime beyond live package_cache; remove/regenerate stale oat/vdex inside the provider package directory if present; do not clear /data package_cache without explicit approval
- Verification gates: offline donor audit PASS; offline bundle audit PASS/PASS_STANDALONE; v0.31 live-state capture PASS; v0.31 live provider gate PASS; post-boot cmd webviewupdate and dumpsys webviewupdate; Settings WebView selector; Big Bang/WebView surfaces; browser resolver; keyguard and launcher
- Blockers: current M150 stock-carrier candidate cannot be promoted as product_b-only image; see WebView Route A image capacity audit

## Boundary

- This report is not build authorization. It translates audited donor shapes into ROM design requirements.
- Stock WebView remains a shape/reference candidate, not a modern donor.
- The current full M150 stock-carrier candidate is blocked as a product_b-only image by partition/native-library capacity; choose a smaller build, a reviewed external-native-library layout, or an explicitly accepted 64-bit-only probe before image construction.
- The system_b space-source audit now records user_selected_no_projection_print_preserving: TNT/projection and Android printing are preserved, the bare WebView full-ABI shortfall is covered, and the remaining blocker is reserve/layout acceptance plus package delete preflights. The audit also records SmartisanWallpapers as the current preferred extra-space candidate.
- Live-state, v0.31 stock provider proof, modern source-built material, and offline A-SIG PackageManager evidence are present; donor-backed image work still needs explicit ROM-image acceptance and live proof.
- Trichrome/static-library donors are multi-package ROM designs, never single APK replacements.

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-rom-design-plan.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-rom-design-plan/webview-rom-design-plan.json`
- Markdown report: `docs/research/webview-rom-design-plan.md`
