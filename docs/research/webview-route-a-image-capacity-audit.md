# WebView Route A Image Capacity Audit

Generated: 2026-06-20 00:43:18

This is an offline/read-only audit. It does not build images, touch a device,
flash, reboot, erase partitions, write settings, or modify `/data`.

## Result

The current full M150 `SystemWebView-stock-carrier.apk` must not be promoted as
a product_b-only image. The APK is physically larger than the product_b
replacement budget, and the only size experiment that fits product_b relies on
deflating native libraries, which is not accepted for the first WebView image
because bundled system apps do not follow the normal extracted-native-libs
install path.

## Size Evidence

| Item | Bytes |
| --- | ---: |
| product_b free bytes | 28672 |
| stock WebView APK bytes | 141674094 |
| stock WebView oat/vdex bytes | 280554 |
| product_b replacement budget | 141983320 |
| M150 stock-carrier APK bytes | 262686911 |
| M150 arm64 lib bytes | 166464072 |
| M150 armeabi-v7a lib bytes | 80635596 |
| M150 APK without WebView libs bytes | 15531662 |
| deflate-all APK estimate bytes | 130034070 |
| stored no-32-bit estimate bytes | 181834451 |
| system_b free bytes | 218636288 |

Manifest flags from the candidate:

```text
multiArch=true
use32bitAbi=true
extractNativeLibs=absent
```

## Gates

| Gate | Status | Observed | Impact | Next step |
| --- | --- | --- | --- | --- |
| CAP-GATE-01-product-full-stored | BLOCKED_CAPACITY | product_replace_budget=141983320; candidate_apk=262686911; product_free=28672; stock_webview=141674094; stale_oat_vdex=280554 | A full stored-lib M150 stock-carrier APK cannot replace stock WebView inside product_b. | Do not build a product_b-only stored-lib image from the current candidate. |
| CAP-GATE-02-product-deflated-native | REJECTED_FOR_FIRST_IMAGE | deflate_all_estimate=130034070; manifest_extractNativeLibs=absent; system-app scan extractLibs=false | Deflating libwebviewchromium.so makes the APK small enough, but system bundled apps are not a normal extracted-native-libs install path; WebView native loading/relro expects loadable native libs. | Treat compressed-native APKs as a separate research item, not the first flash candidate. |
| CAP-GATE-03-product-64bit-only | BLOCKED_CAPACITY_AND_RISK | stored_no32_estimate=181834451; product_replace_budget=141983320; use32bitAbi=true | Dropping armeabi-v7a alone still does not fit product_b, and the manifest asks for 32-bit ABI support. | Do not use 64-bit-only product_b replacement as the next image. |
| CAP-GATE-04-system-full-external | BLOCKED_NEEDS_SPACE_REVIEW | system_free=218636288; full_external_need=262631330; shortfall=43995042 | A safer full-ABI layout needs external native libs on a real filesystem path, but current system_b free space is still short. | Pick an explicit system_b space source or rebuild a smaller WebView before image construction. |
| CAP-GATE-05-system-64bit-external | FITS_WITH_32BIT_REGRESSION_RISK | system_free=218636288; only64_external_need=181995734; spare=36640554 | A 64-bit-only external-lib layout can fit system_b, but 32-bit WebView users and the 32-bit relro path become a known regression risk. | Only build this if the user explicitly accepts a 64-bit-only WebView probe. |

## Recommended Next Step

Do not build the original product_b-only Route A1 image. The next safe offline
step is a design decision:

1. Rebuild a smaller WebView from source that keeps loadable native libraries
   and fits product_b, or
2. Design a full-ABI external-native-library layout outside product_b and
   explicitly choose what system_b space to free, or
3. Build a 64-bit-only external-native-library probe only if the 32-bit WebView
   regression risk is explicitly accepted.

## Outputs

- JSON snapshot: `hard-rom/inspect/browser-webview-route-a-image-capacity/webview-route-a-image-capacity-audit.json`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-image-capacity-audit.tsv`
- Markdown report: `docs/research/webview-route-a-image-capacity-audit.md`
