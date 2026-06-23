# WebView Signing Transition Plan

Generated: 2026-06-20 00:31:42

This is a read-only offline plan for the Route A WebView
same-package signing blocker. It does not download donors, build images,
touch a device, flash, reboot, erase partitions, write settings, or
modify `/data`.

## Decision

A modern `com.android.webview` source-built provider is recorded,
and A-SIG now has offline PackageManager evidence for the
stock-cert carrier route. The current blocker has moved from
`A-SIG-01` proof collection to explicit ROM-image acceptance and
live PackageManager/WebViewUpdateService regression proof.

ROM design review may proceed from this state, but no WebView
donor/source-built image is accepted or flashable without the next
explicit image and live-verification gates.

## Why This Exists

Route A keeps the package name `com.android.webview` and replaces
`/product/app/webview` in place. That avoids an early framework provider
XML change, but it means PackageManager must reconcile the new APK with the
existing same-package system identity. The v0.26 launcher-entry-hide series
proved this is not automatic: package cache and certificate-carrier behavior
both mattered.

## Source Evidence

| Source | Status | Evidence | Impact |
| --- | --- | --- | --- |
| route_a_spec_a_sig_01 | RECORDED | hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json | Route A already blocks source-built same-package promotion until signing transition proof exists. |
| source_build_material | RECORDED | apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView.apk | A source-built SystemWebView.apk is recorded; signing transition proof is now the active blocker before image design. |
| source_build_signing_gate | PENDING_A_SIG_REVIEW | hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json | PackageManager signing transition remains the active blocker for ROM image design. |
| route_a_candidate_audit | CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE | hard-rom/inspect/browser-webview-route-a-candidate-audit/webview-route-a-candidate-audit.json | The current Route A candidate audit records the modern source-built candidate shape, but does not authorize image work. |
| stock_webview_donor_selftest | PASS | hard-rom/inspect/browser-webview-donor/stock-webview-selftest/webview-donor-audit.json | Stock WebView is a valid standalone com.android.webview reference shape. |
| stock_webview_bundle_selftest | PASS_STANDALONE | hard-rom/inspect/browser-webview-trichrome-bundle/stock-webview-standalone/trichrome-bundle-audit.json | Stock WebView bundle classification is standalone-webview. |
| system_apk_signature_boundary | RECORDED | docs/research/system-apk-signature-boundary.md | System partition scans may collect certs without full APK content verification, but signature identity still matters. |
| a_sig_package_manager_audit | OFFLINE_PM_ACCEPTANCE_RECORDED | hard-rom/inspect/browser-webview-a-sig-package-manager/webview-a-sig-package-manager-audit.json | The stock-carrier candidate has Android-style cert-only PackageManager evidence for /product system scans. |
| v0.26a_without_v2_carrier | FAIL_RECORDED | hard-rom/inspect/v0.26a-launcher-entry-hide/verify-v0.26a-launcher-entry-hide-device-20260618-182037.txt | The no-v2-carrier launcher-entry-hide image booted but PackageManager lost the target package paths. |
| v0.26a.1_with_v2_carrier | PASS_RECORDED | hard-rom/inspect/v0.26a.1-launcher-entry-hide-v2cert/verify-v0.26a.1-launcher-entry-hide-v2cert-device-20260618-183927.txt | Preserving the v2 cert carrier allowed PackageManager to keep same-package replacements. |
| v0.26a.2_with_cache_bump | PASS_RECORDED | hard-rom/inspect/v0.26a.2-launcher-entry-hide-v2cert-cachebump/verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump-device-20260618-190207.txt | Adding package directory mtime/cache invalidation stabilized the launcher/package state. |
| v2_preserver_tool | READY_LIMITED | tools/r2-apk-preserve-v2-signing-block.py | The current tool can copy stock APK Sig Block 42 into an edited APK only if the edited APK has no existing APK signing block. |
| v2_strip_graft_tool | READY_SELFTESTABLE | tools/r2-apk-v2-carrier-adapt.py | The strip/graft tool can remove an existing candidate APK Sig Block 42 before inserting the stock WebView carrier; its stock self-test verifies strip plus graft can reproduce the original bytes. |

## APK Signature Shapes

| APK | Status | Path | SHA256 | Size | APK Sig Block 42 | Block bytes | Keytool | Jarsigner | Cert SHA256 | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| stock_webview | HASH_OK+PASS+EXIT_0 | reverse/smartisan-8.5.3-rom-static/raw/product/app/webview/webview.apk | 11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97 | 141674094 | present@141623280 | 4096 | 0 | 0 | SHA256: 4E:95:C9:16:46:52:E2:D1:3A:52:29:4D:2B:65:60:3B:C3:17:BB:95:FD:3F:0B:81:D4:D7:6C:8D:C8:E5:FD:B1 | APK Sig Block 42 is immediately before the central directory |
| candidate_webview | RECORDED+PASS | apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView.apk | 582e602b3ac554b4f8d1920bd2e51a61d506f933fd296b93930540cc8a6a2fd7 | 262686911 | present@262602736 | 4096 |  |  |  | APK Sig Block 42 is immediately before the central directory |

## Transition Routes

| Route | Status | Description | Current evidence | Required next evidence | Risk | Blocks |
| --- | --- | --- | --- | --- | --- | --- |
| STOCK_CERT_CARRIER_ADAPTATION | OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE | Preferred first experiment: adapt the source-built standalone SystemWebView.apk in place under /product/app/webview while preserving the stock WebView APK Sig Block 42 as the certificate carrier. | stock WebView carrier, preserver tool, and strip/graft tool are recorded; candidate has its own APK Sig Block 42 and needs a strip/unsigned-output step before current preserver can insert stock carrier; A-SIG PackageManager audit records stock-carrier system-scan cert-only acceptance offline | A real SystemWebView.apk, a generated adapted APK from r2-apk-v2-carrier-adapt.py or an equivalent reproducible no-signing-block output, parsed certificate evidence from Android-compatible tooling, and a no-op/live PackageManager proof before ROM design. | This preserves a certificate carrier for Android's cert-only system scan path, but it is not a cryptographically valid re-signing of the modified payload. | Route A ROM image design. |
| SAME_CERT_SIGNED_BUILD | BLOCKED_KEYS_UNAVAILABLE | Build or sign the modern WebView with the original Smartisan/Android signing certificate. | No Smartisan private signing key is present in the project; OTA public certificates do not sign APKs. | Original private APK signing key or a vendor-signed modern WebView package with matching cert lineage. | Treat as unavailable unless the real private key appears; do not confuse public otacerts with APK signing keys. | Direct same-package replacement without carrier adaptation. |
| PACKAGE_SETTING_MIGRATION_GATE | DEFERRED_LIVE_DATA_RISK | Allow a different signing identity only with an explicit package-setting/cache migration experiment. | Current project rules require explicit user confirmation before any /data mutation; this plan is offline only. | A separately approved live-device experiment that snapshots relevant /data/system package state, clears or migrates package_cache/settings for com.android.webview, and verifies rollback. | High risk: a bad package-setting transition can break provider visibility before WebViewUpdateService runs. | Only considered if stock-cert carrier adaptation fails. |
| FRAMEWORK_SIGNATURE_CONFIG_ROUTE | RED_DEFERRED | Patch framework WebView provider config/signature policy to accept a new provider signature. | Route A intentionally avoids framework-res/provider-add risk for the first modern WebView candidate. | Framework-res config_webview_packages.xml signature semantics mapped, overlay/framework patch designed, and separate no-op framework gate passed. | Touches framework/provider selection and may affect every WebView user; this belongs after a source-built candidate exists. | Route B/C or future policy-based provider work. |
| DIRECT_RESIGN_WITH_OUR_KEY | REJECTED | Re-sign source-built com.android.webview with an arbitrary local key and place it over stock. | System APK signature boundary evidence says package identity, shared state, signature permissions, and SELinux policy remain certificate-aware. | None for the current route; this is a rejected shortcut. | Likely PackageManager rejection or stale-cache mismatch for the same package. | Not allowed for Route A. |

## Gate Order

| Gate | Phase | Status | Required evidence | Blocks |
| --- | --- | --- | --- | --- |
| SIG-GATE-01 | stock-carrier | RECORDED | Stock WebView APK hash, APK Sig Block 42 offset/size, and signature boundary report: hard-rom/inspect/browser-webview-signing-transition/stock-webview-signature-boundary.txt | candidate carrier proof |
| SIG-GATE-02 | tool-boundary | RECORDED | tools/r2-apk-preserve-v2-signing-block.py limitation recorded, and tools/r2-apk-v2-carrier-adapt.py provides the strip/graft path for candidates that already contain APK Sig Block 42. | source-built packaging instructions |
| SIG-GATE-03 | candidate-material | RECORDED | apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView.apk | stock-cert-carrier adaptation proof |
| SIG-GATE-04 | candidate-adaptation | OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_LIVE | apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView-stock-carrier.apk exists; hard-rom/inspect/browser-webview-a-sig-package-manager/webview-a-sig-package-manager-audit.json records Android-style v3 cert-only PackageManager evidence for /product system scans. apksigner full verification fails as expected for the stock-carrier payload, so live PackageManager/WebViewUpdateService proof is still required before acceptance. | Route A integration plan and ROM design plan. |
| SIG-GATE-05 | package-cache | READY_SPEC | Reuse v0.31/v0.26 package directory mtime/cache-bump rule for /product/app/webview and remove stale oat/vdex when code changes. | offline image verifier. |
| SIG-GATE-06 | live-noop | FUTURE_REQUIRED | After explicit user confirmation, flash only an offline-verified candidate and verify boot, PM path/hash/signatures, webviewupdate, relro, Settings selector, keyguard, launcher, and logs. | accepting a modern WebView provider. |
| SIG-GATE-07 | decision | BLOCKED_IMAGE_LIVE_GATE | A-SIG offline PackageManager acceptance is recorded; no donor/source-built ROM image is accepted until explicit image review and live regression proof. | ROM image design. |

## Required First Proof

The current `SystemWebView.apk` has already been recorded by this plan.
The next proof is the stock-carrier adapted APK plus Android-compatible
signer evidence and a PackageManager/live gate before any image design.

If the candidate has no APK Sig Block 42, the current preserver can be used
for a throwaway adaptation proof. If the candidate has its own signing
block, use `tools/r2-apk-v2-carrier-adapt.py --strip-existing-candidate`
or an equivalent reproducible no-signing-block output first. Either way,
the proof must record Android-compatible certificate parsing evidence, not
only `keytool` output.

## Source Reports

- Route A provider spec: `docs/research/webview-route-a-provider-spec.md`
- Source-build readiness: `docs/research/webview-source-build-readiness-plan.md`
- System APK signature boundary: `docs/research/system-apk-signature-boundary.md`
- A-SIG PackageManager audit: `docs/research/webview-a-sig-package-manager-audit.md`
- Stock signature boundary snapshot: `hard-rom/inspect/browser-webview-signing-transition/stock-webview-signature-boundary.txt`

## Outputs

- Markdown report: `docs/research/webview-signing-transition-plan.md`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-signing-transition-plan.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-signing-transition/webview-signing-transition-plan.json`
