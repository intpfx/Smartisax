# WebView Route A Candidate Audit

Generated: 2026-06-20 12:40:55

This is a read-only offline candidate intake audit. It does not
download donors, build images, touch a device, flash, reboot, erase
partitions, write settings, or modify `/data`.

Verdict: **CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE**

The input passes the offline Route A shape gate, but donor-backed
image work is still blocked by live-state and v0.31 live proof.

## Input

| Field | Value |
| --- | --- |
| input | apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView-stock-carrier.apk |
| label | v0.35-m150-stock-carrier-system-provider |
| base package | com.android.webview |
| base APK | SystemWebView-stock-carrier.apk |
| version | 150.0.7871.28 / 787102801 |
| base sha256 | 2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95 |
| donor verdict | PASS |
| bundle verdict | PASS_STANDALONE |
| bundle classification | standalone-webview |

## Requirement Mapping

| ID | Level | Status | Observed | Evidence |
| --- | --- | --- | --- | --- |
| A-ID-01 | MUST | PASS | package_identity=PASS; framework_provider_route=PASS | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json; hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json |
| A-ID-02 | MUST | PASS | verdict=PASS_STANDALONE; classification=standalone-webview; static_library_resolution=PASS | hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json |
| A-SDK-01 | MUST | PASS | min_sdk_device_compat=PASS; target_sdk_webviewupdater=PASS | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json |
| A-VER-01 | MUST | PASS | 787102801 cohort=7871 | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json |
| A-MAN-01 | MUST | PASS | donor metadata=PASS; donor native=PASS; bundle library=PASS | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json; hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json |
| A-MAN-02 | MUST | PASS | android11_factory_provider_class=PASS; android11_factory_provider_class=PASS | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json; hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json |
| A-MAN-03 | MUST | PASS | metadata=40; declarations=41 | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json |
| A-ABI-01 | MUST | PASS | arm64_runtime=PASS; arm64_runtime_libs=PASS | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json; hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json |
| A-ABI-02 | SHOULD | PASS | donor=PASS; bundle=PASS | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json; hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json |
| A-MOD-01 | PROJECT_MUST | PASS | version=150.0.7871.28/787102801 > stock 75.0.3770.156/377015630 | hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json |
| A-CACHE-01 | MUST | DEFERRED_IMAGE_GATE | package directory mtime is checked by the future ROM image verifier | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-CACHE-02 | MUST | DEFERRED_IMAGE_GATE | oat/vdex policy is checked by the future ROM image verifier | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-SIG-01 | MUST | DEFERRED_ADAPTATION_GATE | source-built same-package signing/certificate-carrier transition is checked before image design | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-ROM-01 | MUST | RECORDED_BASELINE | Browser/WebView live-state capture and v0.31 live proof exist; future donor image still needs candidate-specific image gates | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-ROM-02 | MUST | DEFERRED_IMAGE_GATE | shared-block-safe product_b replacement is checked by the future image verifier | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-LIVE-01 | MUST | RECORDED_BASELINE | current Browser/WebView live-state and v0.31 live verifier are recorded; rerun after any donor-backed flash | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-LIVE-02 | MUST | FUTURE_LIVE_GATE | post-boot donor verification cannot run in this offline candidate audit | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |
| A-REJ-01 | MUST_NOT | PASS | candidate audit explicitly requires donor/bundle Route A gates and rejects non-WebView/lib-only shortcuts | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json |

## Gate Mapping

| Gate | Status | Observed | Blocks |
| --- | --- | --- | --- |
| A-GATE-01 | PASS | donor_verdict=PASS; bundle_verdict=PASS_STANDALONE | candidate intake |
| A-GATE-02 | PASS | must_failures=none; baseline_only=False | ROM image design |
| A-GATE-03 | BLOCKED_PENDING_INTEGRATION_PLAN | run integration/ROM design plans after a real modern candidate audit | ROM builder implementation |
| A-GATE-04 | RECORDED_BASELINE | Browser/WebView live-state capture and v0.31 live provider proof are recorded; rerun after a future donor-backed image | future donor-backed image live acceptance |

## Source Reports

- Route A provider spec: `docs/research/webview-route-a-provider-spec.md`
- Target matrix: `docs/research/webview-donor-target-matrix.md`
- Donor audit JSON: `hard-rom/inspect/browser-webview-donor/route-a-candidate-v0.35-m150-stock-carrier-system-provider-donor/webview-donor-audit.json`
- Bundle audit JSON: `hard-rom/inspect/browser-webview-trichrome-bundle/route-a-candidate-v0.35-m150-stock-carrier-system-provider-bundle/trichrome-bundle-audit.json`

## Outputs

- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-candidate-audit.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-route-a-candidate-audit/webview-route-a-candidate-audit.json`
- Markdown report: `docs/research/webview-route-a-candidate-audit.md`
