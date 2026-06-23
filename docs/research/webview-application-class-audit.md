# WebView Application Class Audit

Generated: 2026-06-19 23:55:00

## Question

The source-built M150 `SystemWebView.apk` declares:

```text
android:name="org.chromium.android_webview.nonembedded.WebViewApkApplication"
```

Stock Smartisan OS 8.5.3 WebView declares:

```text
android:name="com.android.webview.chromium.WebViewApplication"
```

This audit checks whether the M150 class is a real incompatibility for R2
Android 11, or just a modern Chromium standalone WebView shape difference.

## Evidence

Stock M75 WebView:

- `reverse/smartisan-8.5.3-rom-static/raw/product/app/webview/webview.apk`
- application class: `com.android.webview.chromium.WebViewApplication`
- `reverse/smartisan-8.5.3-rom-static/jadx/product__app__webview__webview.apk/sources/com/android/webview/chromium/WebViewApplication.java`
- The stock class only runs a narrow Android 8.x font workaround after
  `super.onCreate()`. On R2 Android 11, the guarded branch does not run.

R2 Android 11 framework:

- `android.webkit.WebViewFactory` loads
  `com.android.webview.chromium.WebViewChromiumFactoryProviderForR` from the
  provider classloader.
- `WebViewFactory.getWebViewContextAndSetProvider()` validates package,
  version, signature, and `com.android.webview.WebViewLibrary`, then creates an
  application context and classloader for the provider.
- `WebViewLibraryLoader.RelroFileCreator` and `WebViewZygoteInit` use the
  provider package classloader and native library metadata; they do not hardcode
  or instantiate the old stock Application class.

Source-built M150 WebView:

- `apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView.apk`
- adapted carrier:
  `apks/webview-donor-inbox/sourcebuilt-system-webview-150-0-7871-28/SystemWebView-stock-carrier.apk`
- application class:
  `org.chromium.android_webview.nonembedded.WebViewApkApplication`
- dex contains both the declared Application class and
  `com.android.webview.chromium.WebViewChromiumFactoryProviderForR`.

ECS Chromium source check:

- instance: `i-t4n3boze247s8f5wzuwc`
- read-only Cloud Assistant invocations:
  `t-sgp6ofko007qygw`, `t-sgp6ofkp2o95og0`
- build args include `system_webview_package_name = "com.android.webview"`.
- `android_webview/nonembedded/java/AndroidManifest.xml` defaults the
  Application class to
  `org.chromium.android_webview.nonembedded.WebViewApkApplication`.
- Chromium source comments identify it as the Application subclass for
  SystemWebView and Trichrome. It runs under the WebView APK package for
  renderer/service/provider processes, not inside ordinary apps that embed
  WebView.
- `android_webview/glue/java/src/com/android/webview/chromium/WebViewChromiumFactoryProviderForR.java`
  explicitly exists for Android R framework loading.

## Conclusion

`org.chromium.android_webview.nonembedded.WebViewApkApplication` is a normal
Chromium M150 standalone SystemWebView Application class, not a blocker by
itself.

The real Android 11 provider loading contract remains:

- package is `com.android.webview`
- targetSdk is at least 30
- versionCode cohort is at least stock M75
- `com.android.webview.WebViewLibrary=libwebviewchromium.so`
- `libwebviewchromium.so` exists for R2 ABIs
- `WebViewChromiumFactoryProviderForR` exists in dex
- sandbox service metadata/declarations are coherent
- PackageManager signing/certificate-carrier transition is handled

The donor audit now treats both known compatible Application shapes as PASS:

- legacy stock `com.android.webview.chromium.WebViewApplication`
- Chromium standalone
  `org.chromium.android_webview.nonembedded.WebViewApkApplication`

It also verifies that the declared Application class is actually present in
dex, so a bad manifest-only declaration remains blocked.

## Current State After Re-Audit

- M150 original donor audit: PASS
- M150 stock-carrier donor audit: PASS
- Route A candidate verdict: `CANDIDATE_SHAPE_PASS_BLOCKED_BY_LIVE`
- Integration plan: `build_ready=2`
- ROM design plan: `ready_for_design_review=2`
- Target matrix: preferred route remains
  `ROUTE_A1_SOURCE_BUILT_STANDALONE_COM_ANDROID_WEBVIEW`
- `donor_backed_image_allowed=false`

Remaining blockers are not `application_class`; they are A-SIG signing
transition acceptance, explicit ROM-image design acceptance, image build
verification, and live-device WebView regression testing.
