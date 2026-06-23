# TextBoom PP-OCR Adapter Design

Date: 2026-06-21

## Verdict

Design status: `V043B_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED_LIVE_PASSED`.

TextBoom image OCR now runs through a local `LocalPpOcrApi implements IOcrApi`
adapter backed by the official PaddleOCR `ppocr-sdk`, PP-OCRv6 small ONNX
models, and ONNX Runtime Android CPU inference. The live line has passed the
no-op adapter gate, the real runtime gate, the arm32 ABI fix, broader live OCR
regression, and the v0.42.2 preview-save fix.

Raw CsOcr/CamScanner quality parity is currently blocked outside TextBoom:
the standalone OpenAPI probe is rejected with response code `4003` and returns
empty `RESPONSE_DATA`. This is likely caller/package/signature/key-bound. Do
not treat the standalone probe as a successful legacy quality baseline.

The first TextBoom adapter gate now exists as `v0.40-textboom-ppocr-noop-adapter`.
It has been flashed to the B slot and live-verified. It is deliberately a
package/cache/signature boundary test only: `LocalPpOcrApi` implements
`IOcrApi` and returns an empty success list, while legacy
`CsOcr`/`com.intsig.csopen`/`ocr_key` remain present.

The current live point is
`v0.43b-textboom-csocr-intsig-delete-manifest-retained`. It removes `CsOcr` and
TextBoom-local `com.intsig.csopen` while retaining the original
`AndroidManifest.xml`/`ocr_key` package-parse boundary. The rejected v0.43a
attempt proved that removing `ocr_key` from the manifest makes PackageManager
ignore the TextBoom package even though the file exists on `/system`.

## Evidence Inputs

| Evidence | Result | Path |
| --- | --- | --- |
| Official PP-OCRv6 small corpus live run | `PASS_PPOCR_OFFICIAL_CORPUS_LIVE`; 6/6 samples OK; max latency 2090 ms; max PSS 75708 KB | `hard-rom/inspect/textboom-ppocr-official-corpus-live/20260621-ppocr-official-small-corpus-v1/` |
| Standalone CamScanner corpus probe | `FAIL_CSOCR_BASELINE_LIVE`; 6/6 rejected; `CSOCR_RESULT_CODE_1`, response code `4003`, raw size 0 | `hard-rom/inspect/textboom-csocr-baseline-live/20260621-csocr-corpus-standalone-v1/` |
| TextBoom no-op adapter image | `PASS_READ_ONLY_V040_TEXTBOOM_PPOCR_NOOP_ADAPTER`; sparse `e1dd20fb...`; BOOM_TEXT and image OCR no-op live smoke pass | `hard-rom/inspect/v0.40-textboom-ppocr-noop-adapter/` |
| TextBoom real runtime adapter candidate | `PASS_OFFLINE_IMAGE_V041_TEXTBOOM_PPOCR_RUNTIME_ADAPTER`; sparse `f65fd372...`; APK hash `6f0d396...`; preflight PASS, not flashed | `hard-rom/inspect/v0.41-textboom-ppocr-runtime-adapter/` |
| TextBoom preview-save live gate | `PASS_READ_ONLY_V0422_TEXTBOOM_PPOCR_PREVIEW_SAVE_BEFORE_OCR`; BOOM_IMAGE preview hash changes per selected region | `hard-rom/inspect/v0.42.2-textboom-ppocr-preview-save-before-ocr/`, `hard-rom/inspect/textboom-live-ocr-regression/20260621-v0422-preview-save-before-ocr-live/` |
| TextBoom legacy OCR deletion repair | `PASS_READ_ONLY_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED`; removes CsOcr/Intsig code, keeps manifest ocr_key, BOOM_TEXT and BOOM_IMAGE live pass | `hard-rom/inspect/v0.43b-textboom-csocr-intsig-delete-manifest-retained/`, `hard-rom/inspect/textboom-live-ocr-regression/20260621-v043b-csocr-delete-manifest-retained-live/` |
| Saved comparison report | `TEXTBOOM_OCR_BASELINE_COMPARE_PARTIAL` | `docs/research/textboom-ocr-baseline-comparison.md` |
| Pure PP-OCR mapping helper | maps line quads into TextBoom-style rects and `OcrInfo` JSON | `tools/r2-textboom-ppocr-mapping.py` |

## Existing TextBoom Contract

`IOcrApi` is the adapter boundary:

```java
void startOcr(Activity activity, Bitmap bitmap, int language, OcrListener listener, boolean fromFloat);
void handleOcrResult(int requestCode, int resultCode, Intent data, OcrListener listener);
```

`OcrInfo` is intentionally small:

```java
public RectF mRect = new RectF();
public String mText = "";
```

Current entry points:

| Entry point | Current behavior | Adapter implication |
| --- | --- | --- |
| `BoomOcrActivity.initView()` | hard-codes `new CsOcr(context)` | replace with `new LocalPpOcrApi(context)` behind the no-op gate |
| `BoomOcrActivity.startOcrCropped()` | passes a cropped bitmap into `startOcr` | return rects in cropped-bitmap coordinates |
| `BoomOcrActivity.ExtendOcrListener` | rescales returned rects from cropped bitmap into extended-screen mask coordinates | do not pre-apply screen or crop offsets inside the adapter |
| `BoomOcrActivity.onActivityResult()` | delegates to `mOcrApi.handleOcrResult` | local adapter can make this a no-op unless async cancellation/error plumbing needs it |
| `BoomAccessOcrActivity.initOcr()` | hard-codes `new CsOcr(this)` | later replace after deciding whether to delete its online OCR branch too |

On the current v0.42.2/v0.43b line, the TextBoom image OCR instantiation sites
have already been switched to `LocalPpOcrApi`. The table above records the
stock contract that guided the patch, not the current patched bytecode.

## Adapter Shape

```text
LocalPpOcrApi
  implements IOcrApi
  owns LocalPpOcrEngine singleton/lazy holder
  startOcr(activity, bitmap, language, listener, fromFloat)
    -> copy or encode bitmap off the UI thread
    -> run official PaddleOCR ppocr-sdk recognize()
    -> map OCRResult rows to List<OcrInfo>
    -> post listener callback on UIHandler/main thread
  handleOcrResult(...)
    -> no-op for local engine
```

Keep the impure Android side thin:

- model asset copying and engine lifecycle
- bitmap byte conversion
- worker-thread dispatch
- main-thread callback
- error code mapping

Keep the mapping side pure and testable:

- trim text and remove carriage returns
- convert quadrilateral boxes into axis-aligned `RectF`
- clamp boxes to the bitmap size
- sort rows in reading order
- output `OcrInfo` objects with `mText` and `mRect`

Current pure helper:

```text
tools/r2-textboom-ppocr-mapping.py
  map_ppocr_to_textboom_json(...)
  map_ppocr_to_ocrinfo_json(...)
```

## Coordinate Policy

PP-OCR output coordinates are in the bitmap passed to the engine. For the first
adapter:

1. Return `OcrInfo.mRect` in the cropped bitmap's coordinate space.
2. Clamp `left/top/right/bottom` to `[0,width] x [0,height]`.
3. Preserve line-level rectangles first.
4. Defer character-level click boxes until the line-level adapter is live
   stable.

This matches the current extended-screen listener, which rescales adapter
rectangles back into the selected mask rect by using the cropped bitmap width
and height.

## Error Mapping

First candidate error codes:

| Condition | Proposed code | User-facing behavior |
| --- | ---: | --- |
| model/runtime init failure | `-101` | existing generic OCR error path |
| bitmap encode/decode failure | `-102` | existing generic OCR error path |
| no recognized text | success with empty list | preserves current no-words behavior |
| worker crash/exception | `-103` | existing generic OCR error path |

Do not reuse CamScanner-specific codes such as `4003`, `4008`, or `4009` for
local PP-OCR failures.

## Deletion Scope

Delete CamScanner code only in the same candidate that switches TextBoom to the
local adapter:

- `com.smartisanos.textboom.ocr.CsOcr`
- TextBoom-local `com.intsig.csopen` classes
- keep manifest `ocr_key` metadata until a separate manifest/signature carrier
  plan proves it can be edited without PackageManager rejection
- CamScanner availability/install/error strings only after reference scans show
  no remaining TextBoom branch needs them

Do not delete `BoomAccessOcrActivity` online OCR code in the first adapter
candidate unless we explicitly decide that accessibility OCR must become
local-only too.

Current execution:

```text
v0.43b deletes:
  CsOcr smali
  CsOcr lambda smali
  TextBoom-local com.intsig.csopen smali

v0.43b retains:
  manifest ocr_key

v0.43b defers:
  CamScanner string resources in resources.arsc
  SmashOcr/tt_general_ocr_v1.0.model cleanup
  character-level PP-OCR boxes
```

## Gates

1. `LocalPpOcrApi` no-op shell APK/image gate:
   - instantiate the local adapter
   - keep old CsOcr code present
   - return a controlled error or empty result
   - verify TextBoom launch, BOOM_TEXT, image OCR UI, boot/keyguard, WebView,
     Smartisax, and Sidebar are not destabilized
   - current status: live PASS in v0.40; TextBoom package/hash, BOOM_TEXT,
     image OCR no-op behavior, BrowserChrome, Smartisax, and M150 WebView
     smoke checks are recorded
2. Real local PP-OCR APK gate:
   - package official ppocr-sdk runtime and models inside TextBoom
   - run imageboom and screenshot corpus
   - verify line text, latency, memory, and no ANR/crash
   - current status: live PASS across v0.41.1, v0.42.2, and v0.43b; broader
     corpus, preview-save, BOOM_TEXT, and BOOM_IMAGE checks are recorded
3. CamScanner deletion gate:
   - remove CsOcr and Intsig SDK
   - keep ocr_key until a separate manifest/package-signature design proves a
     safe carrier route
   - verify reference scan, APK package/cache state, and live image OCR
   - current status: v0.43b live PASS; PackageManager registers TextBoom,
     BOOM_TEXT passes, and three BOOM_IMAGE regression cases pass
4. Optional raw legacy instrumentation gate:
   - only if we still need exact CamScanner raw parity
   - patch TextBoom itself to log/write `RESPONSE_DATA` before replacing CsOcr

## Current Blockers

- Raw CsOcr response is not available from a standalone package.
- The official PP-OCR result is line-level; TextBoom may eventually need
  character-level boxes for finer click targets.
- v0.43c tested the lower-memory ABI policy and failed the acceptance gate.
  Deleting APK/system arm64 native libs does not force PackageManager to choose
  `armeabi-v7a`; live TextBoom still runs under `app_process64`, local PP-OCR
  cannot load OpenCV, and BOOM_IMAGE returns to the source app.
- v0.43d tested a PackageManager scan/codePath ABI policy and failed the
  acceptance gate. It keeps the v0.43b manifest/`ocr_key` boundary, reuses the
  v0.43c force-arm32 APK, and changes the system package scan/codePath to
  `/system/app/TextBoomArm32/TextBoomArm32.apk` while hiding the old public APK
  behind a non-`.apk` held path. Live PackageManager accepts the new codePath
  but still records `primaryCpuAbi=arm64-v8a`, so TextBoom runs under
  `app_process64` and cannot load OpenCV with arm64 libs absent.
- v0.43e is the current live-verified repair. It keeps the v0.43d codePath
  boundary, accepts `primaryCpuAbi=arm64-v8a`, and restores target arm64
  ORT/OpenCV libraries under `/system/app/TextBoomArm32/lib/arm64`. BOOM_TEXT
  and three BOOM_IMAGE regression cases pass with no native-link failure. This
  does not solve the lower-memory arm32 question; it establishes the accepted
  forward line for PP-OCR validation.

## Next Step

Continue CamScanner resource-string cleanup and broader PP-OCR regression from
the live-verified v0.43e arm64-accepted line. Treat true arm32 forcing as a
separate PackageManager settings/cache/version or manifest ABI policy
investigation, not as the main repair path.
