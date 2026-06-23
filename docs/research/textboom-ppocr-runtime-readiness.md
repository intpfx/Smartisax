# TextBoom PP-OCR Runtime Readiness

Date: 2026-06-20

## Current Verdict

The project-local Android SDK/NDK route was selected and installed on
2026-06-20. We now have enough local Android build tooling to build and run
standalone OCR benchmark APKs. The first real native-runtime gate passed on R2
on 2026-06-21: `com.smartisax.ocrbench` packages Paddle Lite, OpenCV, JNI glue,
and PP-OCR mobile v2 slim `.nb` models, runs on `imageboom.jpg`, and writes
structured OCR JSON with latency and memory fields.

The user explicitly rejected using old PP-OCR v2 as a final candidate, so the
current route has shifted to PP-OCRv6 ONNX. A later official-docs correction
changed the main implementation route again: PaddleOCR now ships
`deploy/ppocr-android`, a PP-OCRv6 Android SDK/demo using ONNX Runtime. The
formal TextBoom replacement target is now official `ppocr-sdk` +
`PP-OCRv6_small_det.onnx` + `PP-OCRv6_small_rec.onnx` + native ONNX Runtime
Android CPU inference.

Our already-built `com.smartisax.ocrbench.onnx` tiny-model smoke remains useful
only as runtime compatibility proof: PP-OCRv6 tiny/small Paddle 3/PIR models
convert locally to ONNX opset 17, native ORT Android runs tiny det/rec on R2,
and WebView/WASM also works. Tiny is now a speed/power fallback, not the primary
candidate. WebView/ORT Web is a Smartisax Shell experiment, not the TextBoom
replacement dependency.

The current safe gate is:

```text
Do not patch TextBoom or delete TextBoom's CsOcr/com.intsig code yet.
The official `deploy/ppocr-android/ppocr-sdk` no-ROM benchmark APK has passed
live R2 corpus testing with PP-OCRv6 small. The standalone CamScanner OpenAPI
probe is blocked with response code 4003 and empty RESPONSE_DATA, so raw CsOcr
quality parity now requires TextBoom-internal instrumentation if we still need
that legacy payload. The next safe TextBoom step is a LocalPpOcrApi no-op
adapter gate, followed by a real local PP-OCR adapter gate.
```

## Ready Inputs

```text
current ROM baseline:
  v0.39-sidebar-font-ocr-deleted on slot B
working legacy route:
  TextBoom -> CsOcr -> CamScanner OpenAPI -> TextBoom result page
real OCR input:
  hard-rom/inspect/textboom-ppocr-live-capture/20260620-230945-unlocked-boom-image/device-files/imageboom.jpg
  dimensions=1080x773
  size=154521 bytes
UI baseline:
  hard-rom/inspect/textboom-ppocr-live-capture/20260620-230945-unlocked-boom-image/textboom-ui-result-baseline.json
corpus template:
  hard-rom/inspect/textboom-ppocr-corpus/v0.39-live-imageboom-corpus-template.json
offline scoring:
  tools/r2-textboom-ppocr-mapping.py
  tools/r2-textboom-ppocr-benchmark.py
  tools/r2-textboom-ppocr-corpus-template.py
  tools/r2-textboom-ui-result-baseline.py
  tools/r2-textboom-ocr-compare-report.py
standalone APK skeleton:
  apps/TextBoomPpOcrBench/
  tools/r2-build-textboom-ppocr-bench-apk.sh
  tools/r2-textboom-ppocr-bench-live-smoke.sh
  hard-rom/build/apk/TextBoomPpOcrBench.apk
  package=com.smartisax.ocrbench
  versionName=0.1.0
  current_apk_sha256=f9765fe7cd305d2d67916fd4f1bbd0189fa590d646e967710f9e58ea3b0c9d4f
live stub smoke:
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-0020-skip-install-boundary/
  result=PASS_STUB_BENCH_LIVE_SMOKE
  sample_status=STUB_READY
  image_size=1080x773
  sample_sha256=85c8d407caa2df8a0f644182f3bc2fb9c0caebcaaecb4c531de344bcde645f6a
live native PP-OCR smoke:
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-ppocr-v210-heap-det-script-pass2/
  result=PASS_PPOCR_BENCH_LIVE_SMOKE
  sample_status=PP_OCR_READY
  image_size=1080x773
  line_count=14
  latency_ms=1464
  peak_pss_kb=91570
PP-OCRv6 ONNX smoke APK:
  apps/TextBoomOnnxSmokeBench/
  tools/r2-ppocrv6-onnx-env.sh
  tools/r2-convert-ppocrv6-onnx.sh
  tools/r2-fetch-onnxruntime-runtimes.sh
  tools/r2-build-textboom-onnx-smoke-apk.sh
  tools/r2-textboom-onnx-smoke-live.sh
  hard-rom/build/apk/TextBoomOnnxSmokeBench.apk
  package=com.smartisax.ocrbench.onnx
  version=0.1.1 / 2
  current_apk_sha256=365438ee0d1db0bff886874739de60f0d9324b3cf699b29e699867cbe1d34c47
  live_status=PASS_TEXTBOOM_ONNX_SMOKE_LIVE
  live_evidence=hard-rom/inspect/textboom-onnx-smoke-live/20260621-onnx-smoke-v011-both-pass/
official ppocr-android intake:
  tools/r2-fetch-official-ppocr-android.sh
  source=third_party/_downloads/paddleocr-ppocr-android/PaddleOCR/deploy/ppocr-android/
  commit=ef346e0b402934477489001a4d253a20dbeb72a5
  sdk=ppocr-sdk
  main_model=PP-OCRv6_small
  model_layout=models/det/inference.onnx + models/rec/inference.onnx + models/rec/inference.yml
  runtime=onnxruntime-android 1.21.1 per official demo; current 1.26.0 remains an upgrade test
official ppocr-sdk benchmark APK:
  apps/TextBoomPpOcrOfficialBench/
  tools/r2-build-textboom-ppocr-official-bench-apk.sh
  tools/r2-textboom-ppocr-official-bench-live-smoke.sh
  tools/r2-textboom-ppocr-official-corpus-live.sh
  tools/r2-textboom-csocr-baseline-live.sh
  hard-rom/build/apk/TextBoomPpOcrOfficialBench.apk
  package=com.smartisax.ocrbench.officialbench
  version=0.2.0 / 3
  apk_sha256=daa4fcf63f35d23ba0274a635c8361999d0fb5164a606eaf73de10fea7a4c8ba
  size=42M
  status=live corpus passed for official PP-OCRv6 small; standalone CamScanner raw probe blocked
official PP-OCR corpus:
  hard-rom/inspect/textboom-ppocr-official-corpus-live/20260621-ppocr-official-small-corpus-v1/
  result=PASS_PPOCR_OFFICIAL_CORPUS_LIVE
  samples=6
  max_latency_ms=2090
  max_peak_pss_kb=75708
standalone CsOcr/CamScanner corpus:
  hard-rom/inspect/textboom-csocr-baseline-live/20260621-csocr-corpus-standalone-v1/
  result=FAIL_CSOCR_BASELINE_LIVE
  samples=6
  status=CSOCR_RESULT_CODE_1
  response_code=4003
  raw_response_size=0
comparison:
  docs/research/textboom-ocr-baseline-comparison.md
  result=TEXTBOOM_OCR_BASELINE_COMPARE_PARTIAL
adapter design:
  docs/research/textboom-ppocr-adapter-design.md
  status=READY_FOR_TEXTBOOM_ADAPTER_PROTOTYPE
```

## Local Tooling Check

Available before local-sdk install:

```text
OpenJDK:
  /opt/homebrew/opt/openjdk/bin/java
  version=26.0.1
Android build-tools:
  third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt
  third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/aapt2
  third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/d8
  third_party/android-build-tools/build-tools_r35.0.1_macosx/android-15/zipalign
apktool:
  third_party/apktool/apktool_3.0.2.jar
```

Installed by the local-sdk route:

```text
install script:
  tools/r2-android-sdk-install.sh
environment script:
  tools/r2-android-sdk-env.sh
SDK root:
  third_party/android-sdk
download cache:
  third_party/_downloads/android-sdk
disk impact after install:
  third_party/android-sdk ~= 3.1G
  third_party/_downloads ~= 144M
installed packages:
  commandline-tools latest
  platform-tools
  platforms;android-30
  platforms;android-35
  build-tools;35.0.1
  cmake;3.22.1
  ndk;27.2.12479018
verification:
  sdkmanager --version -> 19.0
  adb version -> 37.0.0-14910828
  aapt2 version -> 2.19-12874835
  d8 version -> 8.6.2-dev
  cmake version -> 3.22.1-g37088a8
  ndk-build -> GNU Make 4.3
  aarch64-linux-android30-clang -> Android clang 18.0.3
  android-30/android.jar present
  android-35/android.jar present
```

Project-local Gradle JDK:

```text
script:
  tools/r2-fetch-local-jdk17.sh
installed root:
  third_party/_downloads/jdk/temurin-17/Contents/Home
version:
  Temurin 17.0.19+10
reason:
  Homebrew OpenJDK 26.0.1 is too new for the current Gradle/Kotlin Android
  stack; Kotlin's Gradle script compiler rejects Java version string 26.0.1.
network note:
  Gradle dependency resolution prefers Aliyun Google/Central mirrors before
  google()/mavenCentral() because Java TLS through the current proxy path hits
  `SSLv2Hello is not enabled` against dl.google.com.
```

Current runtime boundary:

```text
Paddle Lite Android runtime:
  packaged and live-proven through the standalone bench APK
PP-OCR v2 mobile slim model assets:
  packaged and live-proven on imageboom.jpg
PP-OCRv6 tiny/small model assets:
  converted to ONNX and locally validated through ONNX Runtime CPU
PP-OCRv6 ONNX Android/Web runtime:
  tiny standalone APK live-proven on R2 in native and WebView/WASM modes;
  compatibility proof only, not final OCR candidate
live benchmark:
  real native PP-OCR live smoke passed on R2
live smoke helper:
  supports SKIP_INSTALL=1 after the APK has already been installed once;
  iterative bench updates currently use either the Smartisan install consent UI
  or an app-specific root replacement of the installed bench APK code path
```

## Standalone Benchmark APK Skeleton

```text
app:
  apps/TextBoomPpOcrBench/
builder:
  tools/r2-build-textboom-ppocr-bench-apk.sh
live smoke helper:
  tools/r2-textboom-ppocr-bench-live-smoke.sh
output:
  hard-rom/build/apk/TextBoomPpOcrBench.apk
package:
  com.smartisax.ocrbench
version:
  0.1.0 / 1
default device input:
  /sdcard/Android/data/com.smartisax.ocrbench/files/input/imageboom.jpg
default device result:
  /sdcard/Android/data/com.smartisax.ocrbench/files/results/last-result.json
```

The initial stub APK only read/probed the configured image and emitted
`ppocr: []`. The current APK now loads `c++_shared`,
`paddle_light_api_shared`, and `smartisax_ppocr_bench`, copies PP-OCR assets
from APK assets into app-private storage, runs the native Paddle Lite pipeline,
and writes a `textboom-ppocr-runtime-prediction` JSON result.

Live stub smoke result:

```text
date:
  2026-06-21
command:
  SKIP_INSTALL=1 RUN_ID=20260621-0020-skip-install-boundary tools/r2-textboom-ppocr-bench-live-smoke.sh
output:
  PASS_STUB_BENCH_LIVE_SMOKE
evidence:
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-0020-skip-install-boundary/run.txt
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-0020-skip-install-boundary/summary.txt
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-0020-skip-install-boundary/last-result.json
result:
  sample_status=STUB_READY
  image_size=1080x773
  sha256 matches imageboom.jpg
boundary:
  no install, flash, reboot, erase, uninstall, or data cleanup in the final
  skip-install smoke run
  no TextBoom, ROM, or system package mutation
```

Local packaging validation:

```text
apksigner verify:
  Verifies
  v3 scheme=true
aapt badging:
  package=com.smartisax.ocrbench
  sdkVersion=30
  targetSdkVersion=30
resources.arsc:
  method=STORED
  data_offset=1020
  aligned4=true
```

## Upstream Runtime Facts

- PaddleOCR's PP-OCRv6 Android Deployment docs now describe
  `deploy/ppocr-android` as the current Android route: an ONNX Runtime based
  PP-OCRv6 SDK/demo with separate `ppocr-sdk` and demo app modules.
- Official `ppocr-sdk` dependencies are minSdk 26, ONNX Runtime Android 1.21.1,
  OpenCV 4.5.3, Kotlin 2.1.0, AGP 8.7.3, and JDK 17.
- Official model layout is `models/det/inference.onnx`,
  `models/rec/inference.onnx`, and `models/rec/inference.yml`.
- Official API returns line-level text, confidence, and box points plus
  detection/recognition timing breakdowns. TextBoom still needs our own
  character-level coordinate approximation, Chinese segmentation, URL/phone/
  address recognition, and click-block mapping.
- The old `deploy/android_demo` remains a PaddleLite v2.10 historical reference
  only. Do not use it as the main PP-OCRv6 Android route.

## Native Paddle Lite PP-OCR Live Gate

Date:

```text
2026-06-21
```

Build:

```text
builder:
  tools/r2-build-textboom-ppocr-bench-apk.sh
apk:
  hard-rom/build/apk/TextBoomPpOcrBench.apk
sha256:
  f9765fe7cd305d2d67916fd4f1bbd0189fa590d646e967710f9e58ea3b0c9d4f
native library:
  hard-rom/build/textboom-ppocr-bench/native/libsmartisax_ppocr_bench.so
Paddle Lite runtime:
  third_party/_downloads/ppocr-runtime/paddle-lite-demo-v2.10/extracted/cxx/libs/arm64-v8a/libpaddle_light_api_shared.so
model:
  PP-OCR mobile v2 slim det/cls/rec .nb files
assets:
  assets/ppocr-v2/models/
  assets/ppocr-v2/labels/ppocr_keys_v1.txt
  assets/ppocr-v2/config.txt
```

Implementation notes:

```text
NativeBench.cc:
  JNI wrapper returning structured JSON.
pipeline.cc:
  adds RunImage(imagePath), cv::imread input, reading-order sorting, clamped
  crop bounds, and det/rec/total timing fields.
det_process.cc:
  clears ratio_hw_ for each run, guards output rank, and replaces stack-sized
  prediction buffers with heap vectors. The heap-vector fix removed a live
  SIGSEGV on the 1080x773 sample.
MainActivity.java:
  reports native load errors explicitly, copies model assets to app storage,
  records peak PSS, and emits PP_OCR_READY only after native success.
AndroidManifest.xml:
  sets extractNativeLibs=true for the packaged native libraries.
```

Live run:

```text
command:
  SKIP_INSTALL=1 RUN_ID=20260621-ppocr-v210-heap-det-script-pass2 tools/r2-textboom-ppocr-bench-live-smoke.sh
output:
  PASS_PPOCR_BENCH_LIVE_SMOKE
evidence:
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-ppocr-v210-heap-det-script-pass2/last-result.json
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-ppocr-v210-heap-det-script-pass2/summary.txt
  hard-rom/inspect/textboom-ppocr-bench-live/20260621-ppocr-v210-heap-det-script-pass2/csocr-ppocr-comparison.md
boundary:
  writes app-specific external files and launches an already-installed bench
  APK only. No flash, reboot, erase, uninstall, data cleanup, TextBoom
  mutation, ROM mutation, or system package mutation.
```

Live result:

```text
sample_status:
  PP_OCR_READY
image_size:
  1080x773
sample_sha256:
  85c8d407caa2df8a0f644182f3bc2fb9c0caebcaaecb4c531de344bcde645f6a
line_count:
  14
latency_ms:
  1464
peak_pss_kb:
  91570
native_det_ms:
  646.757
native_rec_ms:
  774.145
native_total_ms:
  1464.252
```

Recognized text:

```text
Runtime
Webview
Mozilla/5.0 (Linux:Android 11:
Build/RKQ1.201217.002:WV)
AppleWebKit/537.36(KHTML.like
Gecko)Version/4.0
Chrome/150.0.7871.28 Mobile
Safari/537.36
WebGPU
available
WebGL2
available
Storage
localStorage ready
```

Comparison with the current CsOcr baseline:

```text
CsOcr baseline:
  TextBoom UI extraction only, not raw CsOcr RESPONSE_DATA.
  Visible user-agent text is cleaner for punctuation and case.
PP-OCR v2 mobile slim:
  real local/native result with latency and memory telemetry.
  captures lower sample lines that are not present in the current UI-extracted
  baseline JSON, but punctuation and technical casing are weaker.
next comparison gate:
  capture raw CsOcr response/timing/memory before ranking replacement quality.
```

## PP-OCRv6 ONNX Conversion and Smoke APK

Date:

```text
2026-06-21
```

Conversion route:

```text
environment:
  tools/r2-ppocrv6-onnx-env.sh
  python=3.12
  paddlepaddle==3.3.1
  paddle2onnx==2.1.0
  onnx==1.17.0
  onnxruntime==1.27.0
conversion:
  tools/r2-convert-ppocrv6-onnx.sh
  opset=17
  output=hard-rom/build/ppocr-runtime/onnx/
validation:
  tools/r2-ppocrv6-onnx-inspect.py
  result=PASS_PPOCRV6_ONNX_INSPECT
```

Converted models:

```text
PP-OCRv6_tiny_det:
  size=1793140 bytes
  nodes=928
  input=x [dynamic,3,dynamic,dynamic]
  output=fetch_name_0 [dynamic,1,dynamic,dynamic]
PP-OCRv6_tiny_rec:
  size=4456893 bytes
  nodes=464
  input=x [dynamic,3,48,dynamic]
  output=fetch_name_0 [dynamic,dynamic,6906]
PP-OCRv6_small_det:
  size=9893093 bytes
  nodes=928
  input=x [dynamic,3,dynamic,dynamic]
  output=fetch_name_0 [dynamic,1,dynamic,dynamic]
PP-OCRv6_small_rec:
  size=21143574 bytes
  nodes=876
  input=x [dynamic,3,48,dynamic]
  output=fetch_name_0 [dynamic,dynamic,18710]
```

Runtime packages:

```text
Android native:
  onnxruntime-android 1.26.0
  source=Maven Central latest release metadata as of 2026-06-21
WebView:
  onnxruntime-web 1.27.0
  source=npm latest as of 2026-06-21
```

Offline smoke APK:

```text
app:
  apps/TextBoomOnnxSmokeBench/
package:
  com.smartisax.ocrbench.onnx
version:
  0.1.1 / 2
builder:
  tools/r2-build-textboom-onnx-smoke-apk.sh
apk:
  hard-rom/build/apk/TextBoomOnnxSmokeBench.apk
sha256:
  365438ee0d1db0bff886874739de60f0d9324b3cf699b29e699867cbe1d34c47
size:
  39M
contents:
  arm64-v8a libonnxruntime.so and libonnxruntime4j_jni.so
  PP-OCRv6 tiny det/rec ONNX for native Java smoke
  PP-OCRv6 tiny det/rec ONNX plus ORT Web JS/WASM for WebView smoke
current limitation:
  zero-tensor runtime smoke only; real imageboom.jpg preprocessing, DB
  postprocess, crop, CTC decode, and score comparison are the next gate.
```

Live smoke:

```text
command:
  SKIP_INSTALL=1 MODE=both RUN_ID=20260621-onnx-smoke-v011-both-pass tools/r2-textboom-onnx-smoke-live.sh
output:
  PASS_TEXTBOOM_ONNX_SMOKE_LIVE
evidence:
  hard-rom/inspect/textboom-onnx-smoke-live/20260621-onnx-smoke-v011-both-pass/native/last-result.json
  hard-rom/inspect/textboom-onnx-smoke-live/20260621-onnx-smoke-v011-both-pass/web/last-result.json
device package:
  versionCode=2
  versionName=0.1.1
native:
  result=NATIVE_ONNX_READY
  runtime=onnxruntime-android 1.26.0
  providers=[CPU, NNAPI, XNNPACK, WEBGPU]
  latency_ms=160
  peak_pss_kb=52444
  tiny_det session_create_ms=81 run_ms=4 output=[1,1,32,32]
  tiny_rec session_create_ms=36 run_ms=4 output=[1,20,6906]
web:
  result=WEB_ONNX_READY
  runtime=onnxruntime-web 1.27.0 package, runtime reports version unknown
  provider=wasm
  navigator_gpu=true
  latency_ms=2435
  tiny_det session_create_ms=1896 run_ms=85 output=[1,1,32,32]
  tiny_rec session_create_ms=400 run_ms=53 output=[1,20,6906]
note:
  WebGPU is available in WebView, but this smoke intentionally uses WASM first.
  WebGPU should be a separate performance experiment so a WebGPU init failure
  cannot poison the baseline WASM path.
```

## Official PP-OCRv6 Android SDK Intake

Date:

```text
2026-06-21
```

Source:

```text
official docs:
  https://www.paddleocr.ai/main/en/version3.x/inference_deployment/cross_platform/android_deployment.html
official source:
  https://github.com/PaddlePaddle/PaddleOCR/tree/main/deploy/ppocr-android
local intake script:
  tools/r2-fetch-official-ppocr-android.sh
local source:
  third_party/_downloads/paddleocr-ppocr-android/PaddleOCR/deploy/ppocr-android/
commit:
  ef346e0b402934477489001a4d253a20dbeb72a5
manifest:
  third_party/_downloads/paddleocr-ppocr-android/ppocr-android-manifest.txt
```

Key official SDK files:

```text
ppocr-sdk/src/main/java/com/paddle/ocr/PaddleOCR.kt
ppocr-sdk/src/main/java/com/paddle/ocr/PaddleOCRConfig.kt
ppocr-sdk/src/main/java/com/paddle/ocr/EngineConfig.kt
ppocr-sdk/src/main/java/com/paddle/ocr/engine/OCREngine.kt
ppocr-sdk/src/main/java/com/paddle/ocr/engine/DetectionEngine.kt
ppocr-sdk/src/main/java/com/paddle/ocr/engine/RecognitionEngine.kt
ppocr-sdk/src/main/java/com/paddle/ocr/engine/ORTSessionManager.kt
ppocr-sdk/src/main/java/com/paddle/ocr/postprocess/DBPostProcessor.kt
ppocr-sdk/src/main/java/com/paddle/ocr/postprocess/CTCDecoder.kt
ppocr-sdk/src/main/java/com/paddle/ocr/postprocess/QuadTextCrop.kt
ppocr-sdk/src/main/java/com/paddle/ocr/model/OCRRunResult.kt
ppocr-sdk/src/main/java/com/paddle/ocr/model/OCRResult.kt
```

Route correction:

```text
main TextBoom route:
  official ppocr-sdk + PP-OCRv6_small_det.onnx + PP-OCRv6_small_rec.onnx
  + ONNX Runtime Android native CPU inference
dependency alignment:
  first integration aligns to official onnxruntime-android 1.21.1.
  The current APK uses the official OpenCV Android AAR 4.9.0 instead of the
  older documented 4.5.3 because that is the packaged dependency shape now
  working in the local Gradle build.
upgrade probe:
  current onnxruntime-android 1.26.0 is already live smoke-proven on tiny
  det/rec and can be tested after the official-aligned path works
fallback:
  PP-OCRv6 tiny only if small is too slow/heavy on R2
out of main path:
  WebView/ORT Web remains a Smartisax Shell experiment
official comparison anchor:
  GM1900 Android 9 sample benchmark total ~=420ms, detection ~=349ms,
  recognition ~=66ms; use only as a rough external comparison, not as R2 proof
```

## Official SDK Benchmark APK

Date:

```text
2026-06-21
```

Build:

```text
app:
  apps/TextBoomPpOcrOfficialBench/
builder:
  tools/r2-build-textboom-ppocr-official-bench-apk.sh
live smoke helper:
  tools/r2-textboom-ppocr-official-bench-live-smoke.sh
corpus helper:
  tools/r2-textboom-ppocr-official-corpus-live.sh
standalone CamScanner baseline helper:
  tools/r2-textboom-csocr-baseline-live.sh
output:
  hard-rom/build/apk/TextBoomPpOcrOfficialBench.apk
package:
  com.smartisax.ocrbench.officialbench
version:
  0.2.0 / 3
official source commit:
  ef346e0b402934477489001a4d253a20dbeb72a5
runtime:
  onnxruntime-android 1.21.1
  OpenCV 4.9.0 official AAR
  arm64-v8a
model:
  PP-OCRv6_small
  models/det/inference.onnx
  models/rec/inference.onnx
  models/rec/inference.yml
apk size:
  42M
apk sha256:
  daa4fcf63f35d23ba0274a635c8361999d0fb5164a606eaf73de10fea7a4c8ba
```

Packaging validation:

```text
apksigner:
  v2 verified=true
  signer=CN=Smartisax APK, OU=ROM, O=Smartisax, L=Beijing, ST=Beijing, C=CN
aapt badging:
  sdkVersion=26
  targetSdkVersion=30
  native-code=arm64-v8a
resources.arsc:
  method=STORED
  aligned4=true
default device input:
  /sdcard/Android/data/com.smartisax.ocrbench.officialbench/files/input/imageboom.jpg
default device result:
  /sdcard/Android/data/com.smartisax.ocrbench.officialbench/files/results/last-result.json
boundary:
  no TextBoom, ROM, system package, flash, reboot, erase, or data-cleanup
  mutation during the offline build or corpus runs
live status:
  PP-OCRv6 small corpus PASS on R2:
    hard-rom/inspect/textboom-ppocr-official-corpus-live/20260621-ppocr-official-small-corpus-v1/
    samples=6, ok=6, max_latency_ms=2090, max_peak_pss_kb=75708
  standalone CamScanner raw baseline blocked:
    hard-rom/inspect/textboom-csocr-baseline-live/20260621-csocr-corpus-standalone-v1/
    samples=6, ok=0, status=CSOCR_RESULT_CODE_1, response_code=4003,
    raw_response_size=0
  comparison:
    docs/research/textboom-ocr-baseline-comparison.md
    result=TEXTBOOM_OCR_BASELINE_COMPARE_PARTIAL
```

## Candidate Route

Preferred next implementation route:

```text
1. DONE: Build a new official-SDK benchmark harness from
   `deploy/ppocr-android/ppocr-sdk` instead of extending the hand-rolled tiny
   smoke into a full OCR pipeline.
2. DONE: Package PP-OCRv6 small using the official asset layout:
   `models/det/inference.onnx`, `models/rec/inference.onnx`, and
   `models/rec/inference.yml`.
3. DONE: First align dependencies to official ONNX Runtime Android 1.21.1 and
   OpenCV 4.5.3, then test 1.26.0 as an upgrade only after the aligned path
   passes.
4. DONE: Run PP-OCRv6 small on `imageboom.jpg` and the R2 screenshot corpus;
   record line text, confidence, boxes, latency, memory, and model footprint.
5. DONE/BLOCKED: Try standalone raw CsOcr/CamScanner response capture for the
   same input. It is blocked with response code 4003 and empty RESPONSE_DATA.
6. DONE: Add pure mapping tests for TextBoom `OcrInfo` line-level output.
7. NEXT TEXTBOOM GATE: Build a LocalPpOcrApi no-op adapter candidate before
   packaging the full PP-OCR runtime into TextBoom.
8. Only after TextBoom adapter PASS, delete CsOcr/com.intsig/ocr_key in the
   same candidate that switches to local PP-OCR.
```

Why standalone first:

```text
It avoids risking TextBoom, Sidebar, Keyguard, or system boot while we are still
proving model runtime, memory, latency, and OCR coordinates on the R2.
```

## Confirmation Needed

Resolved on 2026-06-20:

```text
local-sdk:
  Selected by Codex after the user delegated the environment choice.
  Android SDK/NDK build tooling is installed under third_party/android-sdk.

remote-builder:
  Not selected for the first PP-OCR benchmark because final latency/memory proof
  must run on the physical R2 anyway.
```

Do not spend additional large disk/network budget silently. Paddle Lite runtime
and PP-OCRv6 model downloads are the next budgeted assets and should be recorded
before vendoring.
