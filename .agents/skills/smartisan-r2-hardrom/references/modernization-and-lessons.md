# Modernization Tracks And Proven Lessons

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Proven Lessons

Magisk boot patching failed on this device with both v30.7 and v26.4. The
device reports a non-standard boot VBMETA footer warning:

```text
unexpected ASN.1 DER tag: expected SEQUENCE, got APPLICATION [1] (primitive)
```

Do not resume Magisk boot-image experiments unless the user explicitly returns
to root research. APatch root is the working root path.

`fastboot flash system` fails because system is inside dynamic `super`.
Bootloader fastboot reports `is-userspace: no`, and this device does not enter a
useful fastbootd via `fastboot reboot fastboot`.

`fastboot erase misc` is mandatory after failed boots and after hard-ROM flashes
in this project. It clears stale forced-recovery/boot-fail state.

Browser replacement attempts v0.3/v0.3.1 booted into a broken state and should
not be reused as a normal package-replacement template. Same-package system app
replacement is higher risk than hard deletion.

The Quark Browser magic-mod route is retired. On 2026-06-19 the user chose to
stop pursuing Quark-derived launcher/browser work and return focus to the stock
Smartisan browser/WebView modernization path. Local Quark APK, decode, graph,
build, report, and Quark-specific script artifacts were removed from the
workspace. Do not recreate or resume this branch unless the user explicitly
reopens it.

Current Browser/WebView modernization backport entry point:

```text
tools/r2-browser-webview-modernization-audit.py
tools/r2-browser-webview-version-gap-audit.py
tools/r2-webview-framework-contract-audit.py
tools/r2-webview-donor-audit.py
tools/r2-webview-trichrome-bundle-audit.py
tools/r2-webview-donor-source-plan.py
tools/r2-webview-donor-target-matrix.py
tools/r2-webview-route-a-provider-spec.py
tools/r2-webview-route-a-candidate-audit.py
tools/r2-webview-source-build-readiness-plan.py
tools/r2-webview-signing-transition-plan.py
tools/r2-apk-v2-carrier-adapt.py
tools/r2-webview-linux-builder-kit.py
tools/r2-webview-sourcebuilt-intake.py
tools/r2-webview-integration-plan.py
tools/r2-webview-rom-design-plan.py
tools/r2-webview-system-space-source-audit.py
tools/r2-webview-super-capacity-audit.py
.github/workflows/webview-source-build.yml
tools/r2-browser-webview-live-state-audit.sh
tools/r2-hardrom-build-v0.31-webview-stock-near-noop.sh
tools/r2-verify-v0.31-webview-stock-near-noop.sh
tools/r2-hardrom-build-v0.32-browserchrome-stock-near-noop.sh
tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh
tools/r2-hardrom-build-v0.33-system-b-grow-noop.sh
tools/r2-verify-v0.33-system-b-grow-noop.sh
tools/r2-hardrom-build-v0.34-system-b-ext4-grow-nofec.sh
tools/r2-hardrom-build-v0.34-system-b-ext4-grow-fec.sh
tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh
tools/r2-hardrom-build-v0.35-webview-m150-system-provider.sh
tools/r2-verify-v0.35-webview-m150-system-provider.sh
docs/research/browser-webview-modernization-audit.md
docs/research/browser-webview-version-gap-audit.md
docs/research/webview-framework-contract-audit.md
docs/research/webview-donor-source-plan.md
docs/research/webview-donor-target-matrix.md
docs/research/webview-route-a-provider-spec.md
docs/research/webview-route-a-candidate-audit.md
docs/research/webview-source-build-readiness-plan.md
docs/research/webview-signing-transition-plan.md
docs/research/webview-linux-builder-kit.md
docs/research/webview-github-builder-workflow.md
docs/research/webview-integration-plan.md
docs/research/webview-rom-design-plan.md
docs/research/webview-system-space-source-audit.md
docs/research/webview-super-capacity-audit.md
docs/research/webview-v0.35-system-provider-image-design.md
reverse/smartisan-8.5.3-rom-static/manifest/browser-webview-modernization-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/browser-webview-version-gap-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-framework-contract-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-source-plan.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-target-matrix.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-provider-spec.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-candidate-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-source-build-readiness-plan.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-signing-transition-plan.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-linux-builder-kit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-integration-plan.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-rom-design-plan.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-system-space-source-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/webview-super-capacity-audit.tsv
```

The v0.30 audit is offline-only and separates the two tracks:

```text
BrowserChrome / com.android.browser:
  RED same-package replacement path. Preserve provider authorities,
  default browser intent filters, SmartisanApplication, zygotePreloadName,
  native/dex/assets shape, package directory mtime, package cache behavior,
  /data/system/icon redirection state, and BrowserChrome oat/vdex handling.
  Do not build a behavior candidate before a BrowserChrome no-op gate boots
  through keyguard and launcher.

System WebView / com.android.webview:
  product app WebView provider. framework-res config_webview_packages lists
  only com.android.webview, so a downloaded com.google.android.webview donor is
  not valid until the framework whitelist is patched or the donor is adapted to
  the com.android.webview contract. WebViewUpdater checks targetSdk >= 30,
  minimum version-code cohort, signature/system-app status, and
  WebViewLibrary metadata. SettingsSmartisan warns non-built-in WebView may
  break Big Bang WebView-based features.
```

Current donor analyzer:

```text
Current version-gap audit:
  command:
    tools/r2-browser-webview-version-gap-audit.py
  current result:
    BrowserChrome package com.android.browser is app version 9.0.6.4 with
    Chromium payload signals 90.0.4430.82 and 90.0.4430.210. Stock WebView is
    com.android.webview 75.0.3770.156/M75. BrowserChrome has much larger
    Smartisan shell/API surface, while WebView is the cleaner system provider
    modernization target.
  route decision:
    First real modernization should prioritize WebView Route A: adapt or
    source-build a standalone com.android.webview-compatible provider in place
    under /product/app/webview after v0.31 live proof. BrowserChrome
    behavior/engine replacement stays behind v0.32 live proof and a candidate
    diff audit.
  outputs:
    docs/research/browser-webview-version-gap-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/browser-webview-version-gap-audit.tsv
    hard-rom/inspect/browser-webview-version-gap-audit/browser-webview-version-gap-audit.json

Current framework contract audit:
  command:
    tools/r2-webview-framework-contract-audit.py
  current result:
    PASS. R2 framework-res config_webview_packages.xml whitelists only
    com.android.webview; SystemImpl boot invariants are satisfied; WebViewUpdater
    requires targetSdk >= 30, versionCode cohort >= stock floor, system-app or
    configured signature, and WebViewLibrary metadata; WebViewFactory requires
    com.android.webview.chromium.WebViewChromiumFactoryProviderForR; stock
    native ABI libraries and sandbox service declarations are internally
    consistent.
  route decision:
    Keep the first real modernization on Route A when possible: adapted or
    source-built com.android.webview under /product/app/webview after v0.31 live
    proof. Direct com.google.android.webview remains Route B and needs a
    separate framework-provider-add gate.
  outputs:
    docs/research/webview-framework-contract-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-framework-contract-audit.tsv
    hard-rom/inspect/browser-webview-framework-contract/webview-framework-contract-audit.json

tools/r2-webview-donor-audit.py [apk|apkm|apks|xapk|zip|directory]
tools/r2-webview-trichrome-bundle-audit.py [apk|apkm|apks|xapk|zip|directory]
tools/r2-webview-donor-inbox-audit.py [optional local files/dirs]
tools/r2-webview-donor-source-plan.py
tools/r2-webview-route-a-candidate-audit.py [apk|apkm|apks|xapk|zip|directory]
tools/r2-webview-integration-plan.py
tools/r2-webview-rom-design-plan.py
tools/r2-webview-system-space-source-audit.py

default self-test:
  tools/r2-webview-donor-audit.py --label stock-webview-selftest
  result: PASS against stock product/app/webview/webview.apk. The current
          auditor verifies Android 11 WebViewChromiumFactoryProviderForR,
          no Trichrome/static-library dependency, and recommends the
          adapt-in-place /product/app/webview route with package directory
          mtime, stale oat/vdex, relro, webviewupdate, Settings selector, and
          Big Bang/WebView regression checks.

negative self-test:
  tools/r2-webview-donor-audit.py \
    reverse/smartisan-8.5.3-rom-static/raw/system/system/app/BrowserChrome/BrowserChrome.apk \
  --label stock-browser-as-webview-negative
  result: FAIL because BrowserChrome is not whitelisted as a WebView provider,
          targetSdkVersion is 28, version-code cohort is too low, and
          WebViewLibrary/native WebView/factory-provider requirements are
          missing.

outputs:
  hard-rom/inspect/browser-webview-donor/<label>/webview-donor-audit.md
  hard-rom/inspect/browser-webview-donor/<label>/webview-donor-audit.tsv
  hard-rom/inspect/browser-webview-donor/<label>/webview-donor-audit.json

Trichrome/static-library bundle analyzer:
  command:
    tools/r2-webview-trichrome-bundle-audit.py --label stock-webview-standalone
  result:
    PASS_STANDALONE against stock product/app/webview/webview.apk. The bundle
    gate classifies stock WebView as standalone, verifies exactly one provider
    candidate, one base APK for the package, WebViewLibrary/native lib,
    Android 11 WebViewChromiumFactoryProviderForR, arm64/arm32 libs, and no
    static-library dependency. Local apksigner certificate extraction currently
    needs a Java runtime; this is not required for standalone/no-static-library
    stock evidence, but future Trichrome donors with certDigest refs should
    treat missing signer evidence as a warning that must be resolved or
    explicitly accepted before image design.
  negative self-test:
    tools/r2-webview-trichrome-bundle-audit.py \
      reverse/smartisan-8.5.3-rom-static/raw/system/system/app/BrowserChrome/BrowserChrome.apk \
      --label stock-browser-negative
    result: FAIL because BrowserChrome is not a WebView provider bundle.
  outputs:
    hard-rom/inspect/browser-webview-trichrome-bundle/<label>/trichrome-bundle-audit.md
    hard-rom/inspect/browser-webview-trichrome-bundle/<label>/trichrome-bundle-audit.tsv
    hard-rom/inspect/browser-webview-trichrome-bundle/<label>/trichrome-bundle-audit.json

inbox scanner:
  default local inbox path:
    apks/webview-donor-inbox/
  command:
    tools/r2-webview-donor-inbox-audit.py --include-downloads
  current result:
    candidate_count=0, meaning no external modern WebView donor package is
    currently present in the project inboxes or ~/Downloads.
  self-test:
    running the inbox scanner on the stock WebView APK discovers one candidate
    and forwards it to tools/r2-webview-donor-audit.py plus
    tools/r2-webview-trichrome-bundle-audit.py, producing PASS and
    PASS_STANDALONE respectively.
  outputs:
    hard-rom/inspect/browser-webview-donor-inbox/webview-donor-inbox-audit.md
    hard-rom/inspect/browser-webview-donor-inbox/webview-donor-inbox-audit.tsv
    hard-rom/inspect/browser-webview-donor-inbox/webview-donor-inbox-audit.json

source/route plan:
  command:
    tools/r2-webview-donor-source-plan.py
  current result:
    routes=5, rules=13. Route A is a stable/source-built com.android.webview
    adapt-in-place donor after v0.31 live proof; route B is
    com.google.android.webview via framework-provider-add; route C is
    Trichrome/static-library multi-package; route D is source-built Chromium;
    route E rejects Chrome/Browser APKs as WebView donors.
    The current source plan now points route C at
    tools/r2-webview-trichrome-bundle-audit.py before any image design.
  outputs:
    docs/research/webview-donor-source-plan.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-source-plan.tsv

donor target matrix:
  command:
    tools/r2-webview-donor-target-matrix.py
  current result:
    routes=6, ready_routes=0, route_a_provider_spec=RECORDED,
    route_a_candidate_audit=PASS_SHAPE,
    route_a_image_capacity=PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY, and
    system_b_space_source_audit=SELECTED_LOW_RESERVE. The
    preferred first real modernization target remains:
    ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW: source-build or adapt
    a standalone com.android.webview-compatible provider in /product/app/webview.
    The v0.31 stock provider live proof has passed. ROUTE_A2 accepts a prebuilt standalone
    com.android.webview donor only if one exists and passes donor plus bundle
    audits. ROUTE_B is direct com.google.android.webview via a separate
    framework-provider-add gate. ROUTE_C is Trichrome/static-library
    multi-package. ROUTE_D keeps BrowserChrome as a separate browser track, not
    a WebView provider route. ROUTE_E rejects native-library-only swaps.
  next offline step:
    Do not build the original product_b-only stock-carrier image. Run delete
    preflights for `user_selected_no_projection_print_preserving`, then choose
    extra reserve, a smaller WebView source build, or explicitly accept the
    low-reserve full-ABI layout before image build.
  current blockers:
    Live-state capture, v0.31 stock provider live proof, M150 source-built
    material, Route A candidate audit, ROM design review inputs, and offline
    A-SIG PackageManager evidence are present. donor_backed_image_allowed
    remains false because the current full M150 product_b-only image path is
    physically blocked by partition/native-library capacity. The selected
    full-ABI external-native-library layout preserves Android printing and
    covers the bare shortfall, but reserve/layout acceptance and delete
    preflights still block image construction.
  outputs:
    docs/research/webview-donor-target-matrix.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-target-matrix.tsv
    hard-rom/inspect/browser-webview-donor-target-matrix/webview-donor-target-matrix.json

Route A provider spec:
  command:
    tools/r2-webview-route-a-provider-spec.py
  current result:
    READY_FOR_DONOR_OR_SOURCE_BUILD_INTAKE. It defines 17 requirements and 6
    gates for the future source-built/adapted standalone com.android.webview
    provider. Required areas include package identity, standalone bundle shape,
    target/min SDK, version-code cohort, WebViewLibrary metadata,
    WebViewChromiumFactoryProviderForR, sandbox service counts, arm64/arm32
    native libraries, product_b-only scope after v0.31 live proof, shared-block
    safe replacement, package directory mtime, stale oat/vdex handling,
    same-package PackageManager signing/certificate-carrier transition, live
    webviewupdate/relro/Settings/Big Bang verification, and rejection of
    BrowserChrome/Chrome/Quark/lib-only shortcuts. Live-state and v0.31 stock
    provider gates are RECORDED_BASELINE/PASS, not current blockers.
  current blockers:
    This is a spec only. Do not build donor-backed images until an actual
    donor/source-build output passes the spec through donor and bundle audits
    and the same-package signing transition is proven.
  outputs:
    docs/research/webview-route-a-provider-spec.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-provider-spec.tsv
    hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json

Source-build readiness plan:
  command:
    tools/r2-webview-source-build-readiness-plan.py
  current result:
    source_build_route=system_webview_apk, package_target=com.android.webview,
    donor_backed_image_allowed=false. The plan fetches only Chromium Dash
    release metadata, not Chromium source. Current Android Stable is
    150.0.7871.28/M150 and refs/tags/150.0.7871.28 resolves to
    48db307645dcbaa0bb5ccee0cd096cf22971bb84. It records the isolated
    x86-64 Linux builder commands, release GN args, SystemWebView.apk intake
    path, and the required same-package signing/certificate-carrier transition
    proof before ROM image design.
  current blockers:
    Source-built SystemWebView.apk has returned from the Alibaba ECS builder,
    and A-SIG PackageManager acceptance is now recorded offline. Do not build
    or flash donor-backed images from the source-build plan alone; require
    explicit candidate image design, offline verification, and live proof.
  outputs:
    docs/research/webview-source-build-readiness-plan.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-source-build-readiness-plan.tsv
    hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json
    hard-rom/inspect/browser-webview-source-build-readiness/chromiumdash-android-stable-latest.json

WebView signing transition plan:
  command:
    tools/r2-webview-signing-transition-plan.py [--candidate SystemWebView.apk]
  current result:
    verdict=A_SIG_01_OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_IMAGE_LIVE,
    donor_backed_image_allowed=false. Stock
    /product/app/webview/webview.apk is hash-verified and has APK Sig Block 42
    present at offset 141623280 with 4096 block bytes. keytool/jarsigner read
    the Smartisan Android certificate. Source-built SystemWebView.apk is now
    recorded, and the stock-carrier adapted APK exists as
    SystemWebView-stock-carrier.apk. SIG-GATE-04 is
    OFFLINE_PM_ACCEPTANCE_RECORDED_PENDING_LIVE: Android-style v3 cert-only
    parsing reads the stock Smartisan WebView cert from the stock-carrier APK,
    while apksigner full verification fails as expected.
  current blockers:
    A-SIG proof collection is no longer the blocker. Do not accept or flash a
    donor-backed WebView image until the candidate image is explicitly reviewed
    and the live PackageManager/WebViewUpdateService regression gate passes.
  outputs:
    docs/research/webview-signing-transition-plan.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-signing-transition-plan.tsv
    hard-rom/inspect/browser-webview-signing-transition/webview-signing-transition-plan.json
    hard-rom/inspect/browser-webview-signing-transition/stock-webview-signature-boundary.txt

WebView A-SIG PackageManager audit:
  command:
    tools/r2-webview-a-sig-package-manager-audit.py
  current result:
    verdict=OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE,
    a_sig_01_status=OFFLINE_PM_ACCEPTANCE_RECORDED,
    donor_backed_image_allowed=false. The audit proves from local R2 sources
    that /product/app/webview is scanned as a system partition, parseFlags
    include PARSE_IS_SYSTEM_DIR, and the skipVerify path calls
    ApkSignatureVerifier.unsafeGetCertsWithoutVerification(). It compares stock
    WebView, source-built M150 WebView, and SystemWebView-stock-carrier.apk
    with apksigner full verification plus Android-style v2/v3 signer parsing.
  current blockers:
    The stock-carrier APK is not a valid user-installable APK and is not
    cryptographically re-signed; it is only acceptable as a system-partition
    certificate carrier pending live PackageManager/WebViewUpdateService proof.
  outputs:
    docs/research/webview-a-sig-package-manager-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-a-sig-package-manager-audit.tsv
    hard-rom/inspect/browser-webview-a-sig-package-manager/webview-a-sig-package-manager-audit.json

WebView Linux builder kit:
  command:
    tools/r2-webview-linux-builder-kit.py
  current result:
    The kit was executed on an Alibaba ECS x86-64 Linux builder and produced
    Chromium 150.0.7871.28 SystemWebView.apk plus provenance metadata. The kit
    still converts the source-build readiness plan into exact GN args, an
    isolated Linux preflight script, build script, artifact collection script,
    and Mac local-intake script for reproducible rebuilds. The preflight checks Linux/x86-64, required base
    commands, disk, RAM, no-space build path, and build-root writability before
    any Chromium fetch/build; if a configured path such as /mnt/webview-build is
    not creatable by the runner user, it tries a narrow sudo mkdir/chown
    fallback and then verifies writability. The collection script writes
    artifact-manifest.json, SHA256SUMS.txt, args.gn, chromium-revision.txt, and
    gn-args-expanded.txt. The local script delegates to
    tools/r2-webview-sourcebuilt-intake.py.
  GitHub/self-hosted wrapper:
    .github/workflows/webview-source-build.yml
    docs/research/webview-github-builder-workflow.md
    Manual workflow_dispatch wrapper around the same kit. It first regenerates
    the ignored hard-rom/inspect kit on the runner, so the workflow does not
    rely on local evidence artifacts being tracked in Git. Default mode is
    preflight-only. Full build mode should run only on a large self-hosted
    Linux x86-64 runner or GitHub larger Ubuntu runner; do not use the default
    standard ubuntu-latest runner for the full Chromium build.
  current blockers:
    Missing APK material and offline A-SIG proof are no longer blockers. The
    remaining blocker is candidate image acceptance plus live PackageManager/
    WebViewUpdateService behavior proof.
  outputs:
    docs/research/webview-linux-builder-kit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-linux-builder-kit.tsv
    hard-rom/inspect/browser-webview-linux-builder-kit/webview-linux-builder-kit.json
    hard-rom/inspect/browser-webview-linux-builder-kit/kit/

WebView source-built local intake:
  command:
    tools/r2-webview-sourcebuilt-intake.py [--dry-run|--validate-only] [--label label] [SystemWebView.apk-or-dist]
  current result:
    verdict=INTAKE_RAN_REVIEW_OUTPUTS, donor_backed_image_allowed=false for
    sourcebuilt-system-webview-150-0-7871-28. The real intake validated dist
    provenance, copied SystemWebView.apk, produced SystemWebView-stock-carrier.apk,
    recorded signing-shape/signature-boundary evidence, reran original/adapted
    Route A candidate audits, and refreshed the integration plan, ROM design
    plan, and target matrix.
  current blockers:
    Do not build donor-backed WebView images from the intake result alone.
    The generated stock-carrier candidate and offline A-SIG PackageManager
    audit may feed candidate image design, but a lone APK input remains only a
    warned manual-audit fallback because it cannot prove builder
    manifest/SHA/GN/revision provenance.
  outputs:
    hard-rom/inspect/browser-webview-sourcebuilt-intake/sourcebuilt-system-webview-150-0-7871-28/sourcebuilt-intake.md
    hard-rom/inspect/browser-webview-sourcebuilt-intake/sourcebuilt-system-webview-150-0-7871-28/sourcebuilt-intake.tsv
    hard-rom/inspect/browser-webview-sourcebuilt-intake/sourcebuilt-system-webview-150-0-7871-28/sourcebuilt-intake.json

Route A candidate audit:
  command:
    tools/r2-webview-route-a-candidate-audit.py [apk|apkm|apks|xapk|zip|directory]
  current result:
    CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE against the source-built M150
    SystemWebView-stock-carrier.apk. It maps to package com.android.webview,
    version 150.0.7871.28/787102801, standalone-webview bundle shape, and
    passes the modernity gate against stock M75. Donor audit is PASS after the
    WebView application-class analysis accepted Chromium's official
    nonembedded WebViewApkApplication shape.
  current blockers:
    The image, cache, ROM-layout, and post-donor live gates remain
    blocked/deferred until an explicit candidate image is designed and
    accepted. The actual modern Route A output exists, same-package signing
    transition is recorded offline, and Browser/WebView live-state plus v0.31
    stock provider proof are already PASS, but the current full M150
    product_b-only layout is blocked by capacity.
  outputs:
    docs/research/webview-route-a-candidate-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-candidate-audit.tsv
    hard-rom/inspect/browser-webview-route-a-candidate-audit/webview-route-a-candidate-audit.json

Route A image capacity audit:
  command:
    tools/r2-webview-route-a-image-capacity-audit.py
  current result:
    verdict=PRODUCT_B_ONLY_IMAGE_BLOCKED_BY_CAPACITY,
    donor_backed_image_allowed=false. product_b replacement budget is
    about 141.98 MB, while the current M150 stock-carrier APK is about
    262.69 MB. Deflating native libraries would fit product_b but is rejected
    for the first image because system bundled apps do not follow the normal
    extracted-native-libs install path. A full-ABI external-native-library
    system_b layout is short by about 44 MB; a 64-bit-only external layout fits
    but carries known 32-bit WebView/relro regression risk.
  current blockers:
    Do not build or flash the current product_b-only Route A1 image. The next
    decision must choose a smaller source build, full-ABI system_b space source,
    or explicitly accepted 64-bit-only probe.
  outputs:
    docs/research/webview-route-a-image-capacity-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-image-capacity-audit.tsv
    hard-rom/inspect/browser-webview-route-a-image-capacity/webview-route-a-image-capacity-audit.json

system_b space source audit:
  command:
    tools/r2-webview-system-space-source-audit.py
  current result:
    verdict=SYSTEM_B_SPACE_SOURCE_USER_SELECTED_LOW_RESERVE,
    donor_backed_image_allowed=false. The audit measures true ext4 allocation
    in the current system_b image. BostonScreenMirror, BostonCastHalService,
    and SmartisanWirelessCast are user-protected TNT/wireless projection
    dependencies, and the user selected a no-projection source that preserves
    Android printing:
      /system/app/BuiltInPrintService
      /system/app/PrintSpooler
      /system/app/PrintRecommendationService
    The selected source is `user_selected_no_projection_print_preserving`. It
    frees 45,912,064 allocated bytes, leaving 1,917,022 bytes over the bare
    WebView full-ABI shortfall but 6,471,586 bytes short of the 8 MiB reserve.
    The safest newly recorded extra-space candidate is
    `smartisan_wallpapers_resource_pack` at /system/app/SmartisanWallpapers:
    GREEN delete preflight, no components, no requested permissions, no
    sysconfig references, and 86,925,312 allocated bytes. It can cover the
    full reserve by itself at the cost of bundled wallpaper assets, but it is
    still only a candidate until the user selects it and a focused wallpaper
    picker/resource review is done.
  user-selected no-projection print-preserving source:
    /system/app/SMTBugreport
    /system/app/CrashReport
    /system/app/SlardarOsClient
    /system/app/SMPushService
    /system/app/UnionPushProxy
    /system/app/TrackerSmartisan
    /system/priv-app/TeaTracker
    /system/app/BasicDreams
    /system/app/HTMLViewer
    /system/app/LiveWallpapersPicker
    /system/app/WallpaperBackup
    /system/app/Exchange2
    /system/app/Traceur
    /system/app/EasterEgg
    /system/app/Protips
    /system/app/CtsShimPrebuilt
    /system/priv-app/CtsShimPrivPrebuilt
    /system/priv-app/SmartisanShareManual
  current blockers:
    Do not delete these packages or build a donor-backed image until
    package-specific delete preflights pass and the user chooses one of:
    add more reserve, reduce the WebView footprint, or explicitly accept the
    low-reserve layout. Keep rollback/live verification gates intact.
  outputs:
    docs/research/webview-system-space-source-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-system-space-source-audit.tsv
    hard-rom/inspect/browser-webview-system-space-source/webview-system-space-source-audit.json

system_b dynamic growth capacity audit:
  command:
    tools/r2-webview-super-capacity-audit.py
  current result:
    verdict=SYSTEM_B_DYNAMIC_GROWTH_FEASIBLE_REQUIRES_NOOP_GATE.
    The current slot-1 lpdump shows qti_dynamic_partitions_b has 978,509,824
    free bytes and the physical B-slot super tail hole has 980,967,424 bytes.
    The practical system_b growth ceiling is therefore 978,509,824 bytes.
    The recommended first experiment is a no-content +128 MiB system_b growth
    gate that changes only dynamic partition metadata and ext4 size, then
    verifies lpdump, fsck, sparse flashing, boot, and rollback before any
    WebView content is combined with the resize path.
  boundary:
    Existing exact-current builders deliberately do not modify dynamic
    partition metadata. Growing system_b needs a separate no-op gate and is
    not the same safety class as replacing an existing logical slice.
  outputs:
    docs/research/webview-super-capacity-audit.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-super-capacity-audit.tsv
    hard-rom/inspect/browser-webview-super-capacity/webview-super-capacity-audit.json

integration plan:
  command:
    tools/r2-webview-integration-plan.py
  current result:
    candidates=3, build_ready=2. The plan includes stock baseline plus the
    original and stock-carrier source-built M150 candidates. The v0.31 offline
    provider gate, Browser/WebView live-state capture, v0.31 live provider
    verification, modern donor inbox, and A-SIG PackageManager gate are PASS or
    recorded. The source-built candidates are READY_FOR_OFFLINE_IMAGE_DESIGN
    at the material/layout-requirement level, but remain non-authorizing; the
    actual product_b-only image path is blocked by capacity.
  outputs:
    docs/research/webview-integration-plan.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-integration-plan.tsv
    hard-rom/inspect/browser-webview-integration-plan/webview-integration-plan.json

ROM design plan:
  command:
    tools/r2-webview-rom-design-plan.py
  current result:
    designs=3, ready_for_design_review=0. The source-built original and
    stock-carrier M150 candidates are BLOCKED_CAPACITY under Route A for the
    original product_b-only layout. They still record product_b scope,
    filesystem actions, package-cache/oat-vdex actions, and verification gates,
    and now consume the system_b space-source audit, but donor-backed image
    work must first choose a smaller build or an explicitly selected
    native-library/filesystem layout.
  latest live-state note:
    hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260619-125547.txt
    result=PASS_READ_ONLY after v0.31 live verification.
  outputs:
    docs/research/webview-rom-design-plan.md
    reverse/smartisan-8.5.3-rom-static/manifest/webview-rom-design-plan.tsv
    hard-rom/inspect/browser-webview-rom-design-plan/webview-rom-design-plan.json

Modern donor route rule:
  If a donor is not com.android.webview, stock framework-res will not expose it
  until config_webview_packages.xml is patched or the package is adapted in
  place. If a donor uses com.google.android.trichromelibrary or other
  uses-static-library entries, treat it as a multi-package Trichrome/static
  shared-library ROM design, not as a single APK replacement. After donor and
  bundle audits, run tools/r2-webview-integration-plan.py to translate the
  audit result into Route A/B/C blockers before image design.
```

Current live-state capture script:

```text
tools/r2-browser-webview-live-state-audit.sh

scope:
  read-only live capture for webviewupdate, WebView settings, package paths,
  product/system package directory mtimes, BrowserChrome oat/vdex paths,
  default browser resolver state, package_cache/icon redirection evidence,
  keyguard/launcher state, and recent Browser/WebView logs.

status:
  bash syntax/help checks pass. The latest v0.31-line run produced
  result=PASS_READ_ONLY after the v0.31 flash and read-only device verifier.
  Re-run it after any future donor-backed WebView image flash.
```

Current v0.31 WebView stock near-noop gate:

```text
variant:
  v0.31-webview-stock-near-noop
purpose:
  first WebView provider image gate on top of live-verified v0.29. It keeps
  /product/app/webview/webview.apk byte-identical to stock and bumps only the
  /app/webview package directory mtime inside product_b to validate
  PackageCacher/WebViewUpdateService freshness before donor integration.
base sparse:
  hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img
  sha256=a8207ee148946057fc2d9c00780b2939c8307f7b0b88ae2b4bc304cfb39892d9
super sparse:
  hard-rom/build/super-otatrust-v0.31-webview-stock-near-noop-exact-current.sparse.img
  sha256=c187b050ced604d3ba52cee0dd36b4a8a17f9a0d1c8b4ae78b0fde0ea44384ae
product image:
  hard-rom/build/product-otatrust-v0.31-webview-stock-near-noop.img
  sha256=cc1302eb5d9c8f4b6856f2b9e5c67c19bdf4ce454fa70a3126d325a86fac9652
stock WebView APK:
  sha256=11e69a224da36b552f3d52d4b86ed0821c67945112df3b0579fcd0b39e0bed97
package directory mtime:
  /app/webview
  mtime=0x6a344030 (2026-06-19 03:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-offline-image-20260619-124124.txt
  PASS; verifies patched_partitions=product_b, e2fsck, product directory
  mtime, byte-identical dumped WebView APK, sparse product_b slice equality,
  retained system_b/system_ext_b/vendor_b/odm_b logical slices, WebView
  donor/provider static gate PASS, Trichrome/static-library bundle gate
  PASS_STANDALONE, and the then-current integration plan recorded no modern
  donor-backed build-ready candidate yet.
preflight:
  tools/r2-live-flash-preflight.sh v0.31-webview-stock-near-noop
  PASS for local gates, rollback sparse, latest offline PASS evidence, and
  live adb/root/B-slot state before the confirmed flash.
status:
  flashed to B slot after explicit confirmation and live-verified. The device
  verifier report is:
    hard-rom/inspect/v0.31-webview-stock-near-noop/verify-v0.31-webview-stock-near-noop-device-read-only-20260619-125530.txt
  PASS_READ_ONLY: boot_completed=1, slot=_b, root available, keyguard not
  showing, launcher focused, /product/app/webview/webview.apk hash remains the
  stock M75 hash, /product/app/webview mtime is 2026-06-19 03:00 +0800,
  WebViewUpdateService reports com.android.webview as valid/current, and relro
  counts are clean. This is still a stock provider gate, not a modern WebView
  integration.
```

Current v0.32 BrowserChrome stock near-noop gate:

```text
variant:
  v0.32-browserchrome-stock-near-noop
purpose:
  first BrowserChrome image gate on top of live-verified v0.29. It keeps
  /system/app/BrowserChrome/BrowserChrome.apk byte-identical to stock and
  bumps only the /system/app/BrowserChrome package directory mtime inside
  system_b to validate PackageCacher/default-browser freshness before any
  BrowserChrome behavior or engine replacement.
base sparse:
  hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img
  sha256=a8207ee148946057fc2d9c00780b2939c8307f7b0b88ae2b4bc304cfb39892d9
super sparse:
  hard-rom/build/super-otatrust-v0.32-browserchrome-stock-near-noop-exact-current.sparse.img
  sha256=7b2ce1ccdab66a303fffd54d2dff8f940851672a8a97936c51874a5c28cc9795
system image:
  hard-rom/build/system-otatrust-v0.32-browserchrome-stock-near-noop.img
  sha256=994e41051505b4409eb2219d87f1f87f515042708a80bcfe2fb19ed6f0f75d4d
stock BrowserChrome APK:
  sha256=0304ebb69d7c29b15f7a348b62770d55d8009f9bfbea02d45741937456ab6d7c
package directory mtime:
  /system/app/BrowserChrome
  mtime=0x6a34dae0 (2026-06-19 14:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.32-browserchrome-stock-near-noop/verify-v0.32-browserchrome-stock-near-noop-offline-image-20260619-115109.txt
  PASS; verifies patched_partitions=system_b, e2fsck, BrowserChrome package
  directory mtime, byte-identical dumped BrowserChrome APK, sparse system_b
  slice equality, and retained product_b/system_ext_b/vendor_b/odm_b logical
  slices.
status:
  built and verified offline only. It has not been flashed or live-verified.
  This is not a modern browser integration and not a behavior replacement.
  Run the Browser/WebView live-state capture and get explicit confirmation
  before flashing/live verification.
```

Current v0.33 system_b dynamic partition/footer growth gate:

```text
variant:
  v0.33-system-b-grow-noop
purpose:
  first no-content dynamic-partition growth gate on top of live-verified
  v0.31. It grows only the system_b logical partition image by 128 MiB,
  moves the existing AVB footer with avbtool resize_image, rebuilds full super
  metadata with lpmake, and keeps the ext4 block count, APKs, and critical
  system files byte-identical.
base sparse:
  hard-rom/build/super-otatrust-v0.31-webview-stock-near-noop-exact-current.sparse.img
  sha256=c187b050ced604d3ba52cee0dd36b4a8a17f9a0d1c8b4ae78b0fde0ea44384ae
super sparse:
  hard-rom/build/super-otatrust-v0.33-system-b-grow-noop.sparse.img
  sha256=39e39965290b68a8980df8eaa090c2440000967f2f80648dc6a7316753165767
system_b image:
  hard-rom/build/system-otatrust-v0.33-system-b-grow-noop.img
  sha256=7b778bb262e6047d8074491b1c5da54fd79c1192163dc5f6308dc616deca2c9f
offline verifier:
  hard-rom/inspect/v0.33-system-b-grow-noop/verify-v0.33-system-b-grow-noop-offline-image-20260620-020849.txt
  PASS; verifies lpdump system_b sectors=6217336, AVB image size=3183276032,
  AVB original image size=3000860672, ext4 block count remains 732632, retained
  non-system_b partition hashes, grown system_b hash, and byte-identical
  system APK/critical-file contents.
status:
  flashed to B slot after explicit confirmation and live-verified. Device
  verifier report:
    hard-rom/inspect/v0.33-system-b-grow-noop/verify-v0.33-system-b-grow-noop-device-read-only-20260620-114213.txt
  PASS_READ_ONLY: boot_completed=1, slot=_b, root available, system_b mapper
  size=3183276032, WebView and BrowserChrome hashes remain stock, WebViewUpdateService
  keeps com.android.webview valid/current, and relro counts are clean. A
  post-unlock live-state report:
    hard-rom/inspect/v0.33-system-b-grow-noop/verify-v0.33-system-b-grow-noop-post-unlock-20260620-114245.txt
  proves launcher focus returned and isKeyguardShowing=false. This gate proves
  bootloader/fastboot/lpmake/AVB-footer acceptance of a larger dynamic system_b
  partition. It intentionally does not grow ext4, so /system df remains at the
  original size until a later filesystem-capacity gate.
```

Current v0.34 live-verified FEC-preserving ext4-capacity gate:

```text
variant:
  v0.34-system-b-ext4-grow-fec
purpose:
  live-verified capacity gate on top of live-verified v0.33. It keeps the
  v0.33 system_b logical partition size, erases the old system_b AVB footer,
  expands ext4 from 3000860672 to 3132964864 bytes, and rebuilds the hashtree
  footer with Android FEC roots=2.
super sparse:
  hard-rom/build/super-otatrust-v0.34-system-b-ext4-grow-fec.sparse.img
  sha256=bd795e1a91e4e3d6108bb989cd03cc1511fa2487cde1bd28bb0e857148b99232
system_b image:
  hard-rom/build/system-otatrust-v0.34-system-b-ext4-grow-fec.img
  sha256=62fe11bc7424e35370eb37d85dc6cf412b50367e2d2e1efce6d1cef5db9a9a44
offline report:
  hard-rom/inspect/v0.34-system-b-ext4-grow-fec/verify-v0.34-system-b-ext4-grow-fec-offline-image-20260620-121005.txt
  PASS_OFFLINE_IMAGE_FEC; verifies ext4 block count 764884, free blocks
  85614, retained non-system_b partition hashes, matching candidate system_b
  extraction, byte-identical system APK/critical-file contents checked=157,
  and AVB hashtree metadata with FEC num roots=2 and nonzero FEC offset.
fec tool:
  third_party/aosp-system-extras-fec/bin/fec
preflight:
  tools/r2-live-flash-preflight.sh v0.34-system-b-ext4-grow-fec
  PASS; validates candidate sparse hash, v0.4 rollback sparse hash, verifier
  availability, latest offline FEC report with FEC num roots=2 evidence, and
  current read-only adb/root/B-slot state. Required confirmation phrase:
  确认刷入 v0.34-system-b-ext4-grow-fec B 槽
flash:
  hard-rom/inspect/v0.34-system-b-ext4-grow-fec/flash-v0.34-system-b-ext4-grow-fec-20260620-122827.txt
  PASS; sparse super 1/9 through 9/9 OK, erase misc OK, reboot OK.
boot wait:
  hard-rom/inspect/v0.34-system-b-ext4-grow-fec/boot-wait-v0.34-system-b-ext4-grow-fec-20260620-123240.txt
  BOOT_COMPLETED on attempt 2 with boot_completed=1, slot=_b, bootanim=stopped.
post-flash verifier:
  tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh --read-only
  hard-rom/inspect/v0.34-system-b-ext4-grow-fec/verify-v0.34-system-b-ext4-grow-fec-device-read-only-20260620-123354.txt
  PASS_READ_ONLY: boot_completed=1, slot=_b, root uid=0, SELinux enforcing,
  system_b mapper size=3183276032, /system df blocks_1k=3057952, stock
  WebView/BrowserChrome hashes, WebViewUpdateService current
  com.android.webview 75.0.3770.156 with relro 2/2 and dirty=false, keyguard
  hidden, launcher focused.
browser/webview live-state:
  hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260620-123338.txt
  PASS_READ_ONLY; confirms stock WebView path/hash, stock BrowserChrome
  path/hash, no browser icon cache subtree, and existing redirection policy.
boundary:
  Live vbmeta_b and vbmeta_system_b were manually probed with flags=3 before
  the earlier no-FEC gate. v0.34 FEC is now the preferred live-proven
  system_b capacity baseline; it is still only a capacity gate, not a donor
  WebView image.
```

Current v0.35 live-verified read-only WebView M150 system-provider candidate:

```text
variant:
  v0.35-webview-m150-system-provider
purpose:
  first donor-backed WebView modernization candidate on top of live-verified
  v0.34. It avoids the product_b-only capacity blocker by installing the
  source-built Chromium M150 stock-carrier `com.android.webview` APK at
  /system/app/webview/webview.apk and removing the old product public WebView
  APK from PackageManager's scan path while retaining a non-.apk held stock
  inode for shared-block safety and evidence.
super sparse:
  hard-rom/build/super-otatrust-v0.35-webview-m150-system-provider.sparse.img
  sha256=e3e122faec2c01e1c710e9ad4661bbfd2c072573aa0e398eeb7afb5fa57c06ed
system_b image:
  hard-rom/build/system-otatrust-v0.35-webview-m150-system-provider.img
  sha256=37a1d97782b0edbe31d0f4fc572ef22ac6a74c7548bc693c0eae853900279560
product_b image:
  hard-rom/build/product-otatrust-v0.35-webview-m150-system-provider.img
  sha256=1122ee932f1aca8305cdc258fa3e6ab1638fcc9640de7b29dfb4e7f04e212e83
provider APK:
  apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView-stock-carrier.apk
  sha256=2e2b2c3c05ba7ef40ba7fc5cc71cdde2cc09d4afd4a09ff385be04b7959d8e95
provider identity:
  package=com.android.webview
  versionName=150.0.7871.28
  versionCode=787102801
package directory mtimes:
  /system/app/webview and /app/webview
  mtime=0x6a363a70 (2026-06-20 15:00:00 +0800)
offline verifier:
  tools/r2-verify-v0.35-webview-m150-system-provider.sh --offline-image
  hard-rom/inspect/v0.35-webview-m150-system-provider/verify-v0.35-webview-m150-system-provider-offline-image-20260620-125012.txt
  PASS_OFFLINE_IMAGE_V035_WEBVIEW_SYSTEM_PROVIDER; verifies system_b/product_b
  FEC metadata, package mtimes, aapt identity, product public WebView absence,
  product held stock WebView presence, and dumped provider donor/bundle audits.
preflight:
  tools/r2-live-flash-preflight.sh v0.35-webview-m150-system-provider
  PASS; validates candidate sparse hash, v0.4 rollback hash, offline evidence,
  verifier availability, and current read-only adb/root/B-slot state.
  Required confirmation phrase:
  确认刷入 v0.35-webview-m150-system-provider B 槽
flash:
  hard-rom/inspect/v0.35-webview-m150-system-provider/flash-v0.35-webview-m150-system-provider-20260620-130108.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no, sparse super
  1/9 through 9/9 OK, erase misc OK, reboot OK.
boot wait:
  hard-rom/inspect/v0.35-webview-m150-system-provider/boot-wait-v0.35-webview-m150-system-provider-20260620-130541.txt
  BOOT_COMPLETED on attempt 3 with slot=_b, bootanim=stopped, verified=orange.
post-flash verifier:
  tools/r2-verify-v0.35-webview-m150-system-provider.sh --read-only
  hard-rom/inspect/v0.35-webview-m150-system-provider/verify-v0.35-webview-m150-system-provider-device-read-only-20260620-130601.txt
  PASS_READ_ONLY_V035_WEBVIEW_SYSTEM_PROVIDER; PackageManager path is
  /system/app/webview/webview.apk, product public WebView is absent, provider
  hash matches M150 stock-carrier, BrowserChrome hash remains stock,
  WebViewUpdateService selects com.android.webview 150.0.7871.28 with relro
  2/2 and dirty=false, keyguard is hidden, and launcher is focused.
browser/webview live-state:
  hard-rom/inspect/browser-webview-live-state/browser-webview-live-state-20260620-130615.txt
  PASS_READ_ONLY; confirms provider path/version, BrowserChrome path, WebView
  settings, resolver state, package_cache/icon/redirection evidence, keyguard,
  and recent Browser/WebView logs.
boundary:
  The read-only live gate passed, but user-facing BrowserChrome regression
  testing then reproduced a white-loading page. Logs show the stock browser
  sandbox renderer aborting at
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex. Big Bang remained
  normal, so the M150 provider path is not globally dead.
design doc:
  docs/research/webview-v0.35-system-provider-image-design.md
```

Current v0.35.1 live-proven BrowserChrome deodex fix:

```text
variant:
  v0.35.1-webview-m150-browserchrome-deodex
purpose:
  v0.35 follow-up that keeps the M150 system WebView provider and stock
  BrowserChrome APK unchanged, removes BrowserChrome prebuilt odex/vdex plus
  empty oat directories, bumps the BrowserChrome package directory mtime, and
  rebuilds system_b FEC.
super sparse:
  hard-rom/build/super-otatrust-v0.35.1-webview-m150-browserchrome-deodex.sparse.img
  sha256=c86a1f734ebb243d279291023a2427c2c0d0cf183d99aec8e8bf6af8573e9559
builder:
  tools/r2-hardrom-build-v0.35.1-webview-m150-browserchrome-deodex.sh
offline proof:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/verify-v0.35.1-webview-m150-browserchrome-deodex-offline-manual-20260620-132329.txt
  PASS_MANUAL_OFFLINE_V0351_BROWSERCHROME_DEODEX; BrowserChrome APK hash
  remains stock, BrowserChrome oat paths are absent, WebView M150 remains
  present, product public WebView remains absent, product held stock WebView
  remains present, and system_b/product_b FEC roots=2.
preflight:
  tools/r2-live-flash-preflight.sh v0.35.1-webview-m150-browserchrome-deodex
  PASS
flash:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/flash-v0.35.1-webview-m150-browserchrome-deodex-20260620-133057.txt
  PASS; sparse super 1/9 through 9/9 OK, erase misc OK, reboot OK.
boot:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/boot-wait-v0.35.1-webview-m150-browserchrome-deodex-20260620-133526.txt
  BOOT_COMPLETED on attempt 7 with slot=_b, bootanim=stopped, verified=orange.
post-flash:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/verify-v0.35.1-webview-m150-browserchrome-deodex-device-oat-read-only-20260620-133607.txt
  PASS_READ_ONLY_V0351_OAT_ABSENT.
  hard-rom/inspect/v0.35-webview-m150-system-provider/verify-v0.35-webview-m150-system-provider-device-read-only-20260620-133623.txt
  PASS_READ_ONLY_V035_WEBVIEW_SYSTEM_PROVIDER.
browser regression:
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/browserchrome-repro-v0.35.1-webview-m150-browserchrome-deodex-20260620-133640.png
  BrowserChrome renders Example Domain.
  hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex/browserchrome-repro-v0.35.1-webview-m150-browserchrome-deodex-browser-only-crash-check-20260620-133757.txt
  PASS_BROWSERCHROME_RENDERED_NO_BROWSER_CRASH, browser_only_crash_marker_count=0.
```

Current v0.35.2 live-proven product WebView residue cleanup image:

```text
variant:
  v0.35.2-webview-m150-clean-product-residue
purpose:
  v0.35.1 follow-up that keeps the M150 system WebView provider and
  BrowserChrome deodex fix, but removes the old /product/app/webview hidden
  stock backup plus stale oat/vdex tree from product_b.
super sparse:
  hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img
  sha256=977f753dee7b84adc7218f5f0f4a8fd7b4403e8e39b24c77da013c8c6b7ec2f5
builder:
  tools/r2-hardrom-build-v0.35.2-webview-m150-clean-product-residue.sh
verifier:
  tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh
offline proof:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/verify-v0.35.2-webview-m150-clean-product-residue-offline-image-20260620-135658.txt
  PASS_OFFLINE_IMAGE_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN; retained system_b
  has M150 WebView and no BrowserChrome oat, product_b has FEC roots=2,
  product_b sparse slice matches, and /app/webview is absent.
preflight:
  tools/r2-live-flash-preflight.sh v0.35.2-webview-m150-clean-product-residue
  PASS
status:
  flashed to B slot and live-verified after explicit confirmation.
live proof:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/flash-v0.35.2-webview-m150-clean-product-residue-20260620-140256.txt
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/boot-wait-v0.35.2-webview-m150-clean-product-residue-20260620-140724.txt
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/verify-v0.35.2-webview-m150-clean-product-residue-device-read-only-20260620-140800.txt
  PASS_READ_ONLY_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN; WebView path is
  /system/app/webview/webview.apk, version is 150.0.7871.28, /product/app/webview
  is absent, BrowserChrome oat is absent, relro is 2/2 with dirty=false,
  keyguard is hidden, and Launcher is focused.
functional proof:
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/browserchrome-repro-v0.35.2-webview-m150-clean-product-residue-20260620-140817.png
  stock BrowserChrome renders example.com.
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/htmlviewer-webview-test-mediastore-v0.35.2-webview-m150-clean-product-residue-20260620-140945.png
  system HtmlViewer loads M150 WebView and renders a local test page.
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/bigbang-boomtext-test-v0.35.2-webview-m150-clean-product-residue-20260620-141025.png
  Big Bang BOOM_TEXT starts and segments text.
  hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue/thirdparty-wps-html-test-v0.35.2-webview-m150-clean-product-residue-20260620-141053.png
  WPS loads M150 WebView as a third-party host.
```

Next safe offline gates:

```text
v0.35.2 is now the live WebView cleanup baseline. For the next WebView round,
extend user-facing WebView provider, Settings selector, stock BrowserChrome,
Big Bang, and third-party embedded WebView checks rather than repeating the
old product-residue cleanup gate.
v0.36-smartisax-shell-debloat flashed and booted on B slot, but PackageManager
rejected Smartisax because the targetSdk 30 APK did not satisfy Android 11's
resources.arsc stored/aligned rule. Its hard-debloat scope and M150 WebView
baseline passed read-only live checks. The failed v0.36 sparse/system images
were removed locally after v0.36.1 superseded them.
v0.36.1-smartisax-shell-debloat-arsc-align is the current live Smartisax branch
candidate: it keeps the v0.36 debloat scope, installs
com.smartisax.browser under /system/app/SmartisaxShell as a WebView-backed
browser/Home candidate, preserves stock Launcher/com.android.browser/M150
WebView/print/TNT-projection, and fixes Smartisax resources.arsc by storing and
4-byte aligning it. It has PASS offline verifier, live preflight, B-slot flash,
device read-only verifier, browser/WebView live-state audit, and Smartisax
functional UX testing. The functional pass proves default Home resolver/focus,
WebView shell rendering with Chrome/150 UA, WebGPU/WebGL2/localStorage probes,
ACTION_VIEW example.com rendering, Back-to-shell behavior, and Settings-to-Home
return.
v0.37a-textboom-live-system-base is the current flashed TextBoom/OCR groundwork
candidate: it promotes the live v3.2.2 com.smartisanos.textboom APK
byte-for-byte into /system/app/TextBoom without manifest/code/resource edits,
preserving the v1/JAR signature boundary. Pre-clean live verification passes:
the system APK hash matches v3.2.2, while the active package still resolves
from the same-version /data/app updated-system shadow. The first explicitly
confirmed PackageManager cleanup attempt failed: uninstall-system-updates and
pm uninstall -k leave TextBoom active from /data/app. Do not claim post-clean
TextBoom proof until a safer PM-state repair plan is approved and verified.
v0.37b-textboom-live-system-libs-deodex is now the live TextBoom/OCR test
image. It starts from v0.37a, keeps the TextBoom v3.2.2 APK byte-identical,
adds the 13 32-bit native libraries under /system/app/TextBoom/lib/arm,
removes stale /system/app/TextBoom/oat, rebuilds system_b FEC roots=2, and has
PASS offline image verification, live B-slot flash, read-only pre-repair
verification, explicitly approved /data shadow repair, read-only post-repair
verification, and Big Bang BOOM_TEXT functional proof. TextBoom now resolves
from /system/app/TextBoom/TextBoom.apk with no UPDATED_SYSTEM_APP flag; the old
/data/app shadow is moved under /data/system/smartisax-textboom-shadow-repair
as a rollback backup.
TextBoom PP-OCR replacement is now past the standalone runtime proof stage:
official ppocr-sdk + PP-OCRv6 small + onnxruntime-android 1.21.1 + OpenCV 4.9.0
official AAR passed a six-sample R2 corpus run at
hard-rom/inspect/textboom-ppocr-official-corpus-live/20260621-ppocr-official-small-corpus-v1/.
The standalone CamScanner/CsOcr raw baseline probe is blocked for all six
samples with CSOCR_RESULT_CODE_1, response_code=4003, and empty RESPONSE_DATA:
hard-rom/inspect/textboom-csocr-baseline-live/20260621-csocr-corpus-standalone-v1/.
Read docs/research/textboom-ocr-baseline-comparison.md and
docs/research/textboom-ppocr-adapter-design.md before TextBoom OCR work. The
next TextBoom step is a LocalPpOcrApi no-op adapter gate; do not delete CsOcr,
TextBoom-local com.intsig.csopen, or ocr_key until the candidate that switches
TextBoom to local PP-OCR passes.
keep v0.4 rollback, v0.35.2 WebView baseline, and v0.36.1 live Smartisax
branch paths ready during functional testing
rollback remains v0.4 fast local sparse; v0.34/v0.35/v0.35.1 sparse images
were removed locally during v0.37a cleanup after being superseded
v0.32 BrowserChrome stock near-noop gate remains separate
v0.33 partition/footer growth live proof is complete
v0.34 FEC-preserving ext4-capacity growth is live-proven and is the v0.35 base
```

For launcher/user-data cleanup, prefer a dry-run first. v0.4 proved that
Launcher may clean invalid shortcuts itself after the corresponding packages are
removed from ROM.
