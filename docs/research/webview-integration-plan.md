# WebView Integration Plan

Generated: 2026-06-20 00:31:42

This is a read-only offline planning report. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Current Gate State

| Gate | Status | Evidence | Next step |
| --- | --- | --- | --- |
| framework_contract_audit | PASS | docs/research/webview-framework-contract-audit.md | Run tools/r2-webview-framework-contract-audit.py after framework/source changes and before donor-backed ROM design. |
| v0.31_offline_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt | Keep this as the stock WebView product_b mtime-only image gate. |
| browser_webview_live_state_capture | PASS | hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt | Keep this as the current pre-v0.31 Browser/WebView baseline and rerun it after v0.31 or donor-backed flashes. |
| v0.31_live_provider_gate | PASS | hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt | Keep this as the stock provider live proof before donor-backed images. |
| modern_donor_inbox | PASS | candidate_count=2; report=hard-rom/inspect/browser-webview-donor-inbox/webview-donor-inbox-audit.json | Modern source-built/donor material is present; review donor/bundle audit rows and signing evidence before ROM image design. |
| a_sig_package_manager_gate | OFFLINE_PM_ACCEPTANCE_RECORDED | verdict=OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE; report=docs/research/webview-a-sig-package-manager-audit.md | Use the stock-carrier candidate only as a system-partition cert carrier, then prove it on-device with PackageManager/WebViewUpdateService logs. |

## Candidate Plans

| Candidate | Source | Package | Version | Route | Readiness | Reports |
| --- | --- | --- | --- | --- | --- | --- |
| stock-webview-baseline | stock-baseline | com.android.webview | 75.0.3770.156 / 377015630 | ROUTE_A_ADAPT_IN_PLACE | NOT_BUILD_READY | donor: `hard-rom/inspect/browser-webview-donor/stock-webview-selftest/webview-donor-audit.md`; bundle: `hard-rom/inspect/browser-webview-trichrome-bundle/stock-webview-standalone/trichrome-bundle-audit.md` |
| inbox-SystemWebView-stock-carrier-2e2b2c3c05ba | inbox | com.android.webview | 150.0.7871.28 / 787102801 | ROUTE_A_ADAPT_IN_PLACE | READY_FOR_OFFLINE_IMAGE_DESIGN | donor: `hard-rom/inspect/browser-webview-donor/inbox-SystemWebView-stock-carrier-2e2b2c3c05ba/webview-donor-audit.md`; bundle: `hard-rom/inspect/browser-webview-trichrome-bundle/inbox-SystemWebView-stock-carrier-2e2b2c3c05ba/trichrome-bundle-audit.md` |
| inbox-SystemWebView-582e602b3ac5 | inbox | com.android.webview | 150.0.7871.28 / 787102801 | ROUTE_A_ADAPT_IN_PLACE | READY_FOR_OFFLINE_IMAGE_DESIGN | donor: `hard-rom/inspect/browser-webview-donor/inbox-SystemWebView-582e602b3ac5/webview-donor-audit.md`; bundle: `hard-rom/inspect/browser-webview-trichrome-bundle/inbox-SystemWebView-582e602b3ac5/trichrome-bundle-audit.md` |

### stock-webview-baseline

Required ROM design:
- satisfy the R2 framework contract audit before image design
- replace /product/app/webview as com.android.webview under product_b
- start from live-verified v0.31, not directly from stock v0.29
- preserve provider Java/native/resources/splits as one version-matched set
- bump every changed package directory mtime so PackageCacher reparses
- remove or regenerate stale oat/vdex for changed provider packages
- verify relro, cmd webviewupdate, Settings WebView selector, Big Bang/WebView surfaces, resolver, keyguard, and launcher after boot

Blockers:
- stock baseline is only a shape/reference candidate, not a modern donor

Next gates:
- keep the current Browser/WebView live-state PASS as the pre-v0.31 baseline
- keep the v0.31 stock WebView near-noop live proof as the product_b provider gate
- rerun donor and Trichrome bundle audits on the actual stable donor material
- generate a donor-specific image design only after all audit FAIL gates and the A-SIG PackageManager gate are resolved

### inbox-SystemWebView-stock-carrier-2e2b2c3c05ba

Required ROM design:
- satisfy the R2 framework contract audit before image design
- replace /product/app/webview as com.android.webview under product_b
- start from live-verified v0.31, not directly from stock v0.29
- preserve provider Java/native/resources/splits as one version-matched set
- bump every changed package directory mtime so PackageCacher reparses
- remove or regenerate stale oat/vdex for changed provider packages
- verify relro, cmd webviewupdate, Settings WebView selector, Big Bang/WebView surfaces, resolver, keyguard, and launcher after boot

Blockers:
- none

Next gates:
- keep the current Browser/WebView live-state PASS as the pre-v0.31 baseline
- keep the v0.31 stock WebView near-noop live proof as the product_b provider gate
- rerun donor and Trichrome bundle audits on the actual stable donor material
- generate a donor-specific image design only after all audit FAIL gates and the A-SIG PackageManager gate are resolved

### inbox-SystemWebView-582e602b3ac5

Required ROM design:
- satisfy the R2 framework contract audit before image design
- replace /product/app/webview as com.android.webview under product_b
- start from live-verified v0.31, not directly from stock v0.29
- preserve provider Java/native/resources/splits as one version-matched set
- bump every changed package directory mtime so PackageCacher reparses
- remove or regenerate stale oat/vdex for changed provider packages
- verify relro, cmd webviewupdate, Settings WebView selector, Big Bang/WebView surfaces, resolver, keyguard, and launcher after boot

Blockers:
- none

Next gates:
- keep the current Browser/WebView live-state PASS as the pre-v0.31 baseline
- keep the v0.31 stock WebView near-noop live proof as the product_b provider gate
- rerun donor and Trichrome bundle audits on the actual stable donor material
- generate a donor-specific image design only after all audit FAIL gates and the A-SIG PackageManager gate are resolved

## Route Boundary

- Route A is adapt-in-place for `com.android.webview` under `/product/app/webview` after v0.31 live proof.
- Route B is `com.google.android.webview` via framework-provider-add; it needs a separate framework config gate.
- Route C is Trichrome/static-library multi-package; it is never a single APK replacement.
- BrowserChrome remains a separate browser no-op gate and must not be treated as a WebView provider donor.

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-integration-plan.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-integration-plan/webview-integration-plan.json`
- Markdown report: `docs/research/webview-integration-plan.md`
