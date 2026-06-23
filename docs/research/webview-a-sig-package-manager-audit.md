# WebView A-SIG PackageManager Audit

Generated: 2026-06-20 00:31:41

This is a read-only offline audit for the Route A WebView
same-package signing transition. It does not touch a device, flash,
reboot, erase partitions, build images, write settings, or modify `/data`.

## Decision

A-SIG now has offline PackageManager evidence for the stock-carrier
route: `/product/app/webview` is scanned as a system partition, the
system path uses `unsafeGetCertsWithoutVerification()`, and the
current `SystemWebView-stock-carrier.apk` exposes the stock Smartisan
WebView certificate through an Android-style v3 cert-only parse.

This does **not** mean the APK is cryptographically re-signed or safe to
install as a user APK. `apksigner` full verification correctly fails on
the stock-carrier candidate because the stock v3 content digest no longer
matches the modern payload.

Practical status: A-SIG is good enough for offline ROM design review, but
a donor-backed image still needs explicit image acceptance and a live
PackageManager/WebViewUpdateService regression test before it can be
called accepted.

## Source Findings

| Finding | Status | Source | Evidence | Impact |
| --- | --- | --- | --- | --- |
| PM-SRC-01 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/content/pm/PackagePartitions.java:30 | /product is included in PackagePartitions.SYSTEM_PARTITIONS with partition type PRODUCT. | /product/app/webview participates in the system-partition scan list. |
| PM-SRC-02 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:2327 | PackageManagerService adds PackagePartitions.SYSTEM_PARTITIONS to mDirsToScanAsSystem. | The boot scan treats product/system_ext/vendor/system roots as system partitions. |
| PM-SRC-03 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:2443 | The system scan parse flags include PARSE_IS_SYSTEM_DIR (16). | Packages below /product/app are parsed with parseFlags & 16 set. |
| PM-SRC-04 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:9341 | addForInitLI derives scanSystemPartition from parseFlags & 16. | Certificate collection can enter the system-partition skipVerify path. |
| PM-SRC-05 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:9406 | scanSystemPartition causes skipVerify=true for certificate collection. | System scan can collect signer certs without full APK payload digest verification. |
| PM-SRC-06 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/content/pm/parsing/ParsingPackageUtils.java:2525 | ParsingPackageUtils calls unsafeGetCertsWithoutVerification when skipVerify is true. | A readable v2/v3 signing block can supply signingDetails for system packages. |
| PM-SRC-07 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/util/apk/ApkSignatureVerifier.java:106 | ApkSignatureVerifier uses unsafe v3 cert collection when verifyFull=false. | If a v3 block is present and internally valid, it is preferred before v2. |
| PM-SRC-08 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__framework.jar/sources/android/util/apk/ApkSignatureSchemeV3Verifier.java:113 | ApkSignatureSchemeV3Verifier verifies APK content digests only when doVerifyIntegrity is true. | The stock-carrier full digest mismatch is skipped by the system cert-only path. |
| PM-SRC-09 | PASS | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerService.java:11382 | The minimum signature-scheme enforcement is skipped for parseFlags & 16 system scans. | A targetSdk 30+ system package can rely on the system scan signingDetails route. |
| PM-SRC-10 | CAUTION | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/PackageManagerServiceUtils.java:461 | PackageManagerServiceUtils still compares parsed signingDetails with existing package/shared-user state. | The carrier must expose the stock WebView cert; different signer material remains unsafe for same-package replacement. |
| PM-SRC-11 | CAUTION | reverse/smartisan-8.5.3-rom-static/jadx/system__system__framework__services.jar/sources/com/android/server/pm/parsing/PackageCacher.java:31 | PackageCacher keys cache entries by packageFile name and flags. | The WebView package directory mtime must be bumped so stale package_cache does not hide the new APK parse. |

## APK Evidence

| APK | Status | SHA256 | apksigner | v2 cert | v3 cert | unsafe preferred | PM prediction |
| --- | --- | --- | --- | --- | --- | --- | --- |
| stock_webview | PASS_PM_CERT_CARRIER | 11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97 | PASS_FULL_VERIFY | 4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1 | 4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1 | v3:4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1 | ACCEPTS_STOCK_CERT_ON_SYSTEM_SCAN_OFFLINE |
| sourcebuilt_webview | RECORDED_DIFFERENT_CERT | 582e602b3ac554b4f8d1920bd2e51a61d506f933fd296b93930540cc8a6a2fd7 | PASS_FULL_VERIFY | 32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0 |  | v2:32a2fc74d731105859e5a85df16d95f102d85b22099b8064c5d8915c61dad1e0 | PARSES_DIFFERENT_CERT_ON_SYSTEM_SCAN |
| stock_carrier_webview | PASS_SYSTEM_SCAN_ONLY_FULL_VERIFY_FAILS | 2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95 | FAIL_FULL_VERIFY_EXIT_1 | 4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1 | 4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1 | v3:4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1 | ACCEPTS_STOCK_CERT_ON_SYSTEM_SCAN_OFFLINE |

## Full Verification Logs

- `stock_webview`: `hard-rom/inspect/browser-webview-a-sig-package-manager/stock_webview.apksigner.txt`
- `sourcebuilt_webview`: `hard-rom/inspect/browser-webview-a-sig-package-manager/sourcebuilt_webview.apksigner.txt`
- `stock_carrier_webview`: `hard-rom/inspect/browser-webview-a-sig-package-manager/stock_carrier_webview.apksigner.txt`

## Boundary

- The stock-carrier APK is a system-partition certificate carrier, not a valid user-install APK.
- The first donor-backed ROM image must bump `/product/app/webview` directory mtime and remove stale oat/vdex artifacts.
- The live gate must verify boot, PackageManager path/hash/signatures, WebViewUpdateService provider status, relro, Settings selector, keyguard, launcher, and PackageManager/WebView logs.

## Outputs

- Markdown report: `docs/research/webview-a-sig-package-manager-audit.md`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-a-sig-package-manager-audit.tsv`
- JSON snapshot: `hard-rom/inspect/browser-webview-a-sig-package-manager/webview-a-sig-package-manager-audit.json`
- Related signing transition plan: `docs/research/webview-signing-transition-plan.md`
- Related system signature boundary: `docs/research/system-apk-signature-boundary.md`
