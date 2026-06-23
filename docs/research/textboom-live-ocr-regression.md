# TextBoom Live OCR Regression

Last updated: 2026-06-21

## Current Evidence

The current live target is
`v0.42.2-textboom-ppocr-preview-save-before-ocr` on slot B. A read-only verifier
passed after the flash:

```text
hard-rom/inspect/v0.42.2-textboom-ppocr-preview-save-before-ocr/
  verify-v0.42.2-textboom-ppocr-preview-save-before-ocr-device-read-only-20260621-203435.txt
```

The fixed image corpus was rerun on the live device through the installed
official PP-OCR benchmark APK:

```text
hard-rom/inspect/textboom-ppocr-official-corpus-live/
  20260621-v0411-fixed-ocr-regression/
```

Result:

```text
samples=6
ok=6
p50_latency_ms=1418.5
max_latency_ms=2127
peak_pss_kb_max=72447
```

The earlier v0.41.1 live TextBoom/Big Bang BOOM_IMAGE path was run over three
deterministic screen states:

```text
hard-rom/inspect/textboom-live-ocr-regression/
  20260621-v0411-live-textboom-ocr-regression-v2/
```

All three cases cold-started `com.smartisanos.textboom/.ocr.BoomOcrActivity`,
reached `com.smartisanos.textboom/.BoomActivity`, produced visible OCR result
chips, and showed no TextBoom fatal marker or native-library load failure.

```text
case                  count text   wall ms   TextBoom total PSS KB
smartisax_home         共 226 字     10002    192014
settings_main          共 33 字       9974    243787
textboom_app_details   共 40 字      10009    246357
```

After v0.42.2, the same three BOOM_IMAGE cases were rerun with the live preview
path set to:

```text
/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg
```

All three cases wrote a fresh preview file before OCR and produced matching
OCR chips. The first case created the file from missing state, and the next two
cases changed the existing file hash:

```text
case                  before sha  after sha   dims       wall ms  PSS KB  count
smartisax_home        missing     85c8d407    1080x773   10201    202786  共 226 字
settings_main         85c8d407    18970a68    1080x773   10247    252633  共 33 字
textboom_app_details  18970a68    5907f5ad    1080x773   10015    248437  共 40 字
```

Aggregate verdict:

```text
fatal_marker_count=0
unsatisfied_link_marker_count=0
unchanged_image_file_cases=[]
```

Evidence:

```text
hard-rom/inspect/textboom-live-ocr-regression/
  20260621-v0422-preview-save-before-ocr-live/
```

## Preview Image Bug History

The user-visible issue was confirmed before v0.42.2: the OCR result changed
correctly with the selected screen region, but the image preview in the
TextBoom result page kept showing the same old image.

Evidence:

```text
/sdcard/.boom/imageboom.jpg
sha256=85c8d407caa2df8a0f644182f3bc2fb9c0caebcaaecb4c531de344bcde645f6a
mtime=2026-06-20 23:10:41 +0800
size=154521
dims=1080x773
owner=root:everybody
mode=0660
```

The file hash and modification time stayed unchanged before and after all three
new BOOM_IMAGE runs. For example, `settings_main` displayed recognized tokens
such as `蓝牙`, `双卡`, `无线`, `网络`, and `一步`, while the result page preview
and pulled `/sdcard/.boom/imageboom.jpg` still showed the old
Runtime/WebView/WebGPU image.

The only repeated `Permission denied` stack in the captured window is from
`com.android.settings.HandleEventService`, not directly from TextBoom
`FileUtils`. Treat it as related log noise unless a later trace proves otherwise.
The direct TextBoom evidence is the unchanged fixed image path plus the static
code map:

```text
BoomOcrActivity.startOcrCropped(...)
  saves imageboom.jpg through FileUtils.saveBMtoLocal(...)

BoomChipPage.loadOcrImageView()
  loads FileUtils.OCR_IMAGE_PATH

FileUtils.OCR_IMAGE_PATH
  /sdcard/.boom/imageboom.jpg
```

## Implication

The PP-OCR adapter is not feeding the wrong bitmap. `BoomOcrActivity` logs
`startOcr bitmap width = 1080 bitmap height = 773`, and the user-visible OCR
chips match the active screen. The stale preview comes from the legacy result
page image path, not from model input.

The first preview-path fix was built as
`v0.42-textboom-ppocr-preview-path`. It kept the v0.41.1 PP-OCR runtime and
changed only TextBoom `classes2.dex`, moving `FileUtils.OCR_IMAGE_DIR` from the
single public fixed path to TextBoom-owned external app-specific storage:

```text
/sdcard/Android/data/com.smartisanos.textboom/files/.boom/imageboom.jpg
```

Offline candidate evidence:

```text
APK:
  hard-rom/build/apk/TextBoom-ppocr-preview-path.apk
  sha256=a38f27541dbb5d9ef9b5f7d4bb806c474941bc1c21f146d8be5125ffd70645a8
ROM:
  hard-rom/build/super-otatrust-v0.42-textboom-ppocr-preview-path.sparse.img
  sha256=8a1b8ade7eec8873f650c2257224493679f679cf3103c1bc0fadb458c7bb1722
Verifier:
  PASS_OFFLINE_IMAGE_V042_TEXTBOOM_PPOCR_PREVIEW_PATH
```

Live verdict for v0.42:

```text
Flash/read-only verifier:
  PASS_READ_ONLY_V042_TEXTBOOM_PPOCR_PREVIEW_PATH
OCR regression:
  3/3 BOOM_IMAGE cases launched BoomOcrActivity and produced matching OCR chips
Preview file:
  missing at /sdcard/Android/data/com.smartisanos.textboom/files/.boom/imageboom.jpg
Log evidence:
  BitmapFactory FileNotFoundException ENOENT on the Android/data preview path
```

The v0.42.1 follow-up keeps the same runtime and changes only the preview
directory to an Android/media app-owned path that is more compatible with direct
file APIs on Android 11:

```text
/sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg

APK:
  hard-rom/build/apk/TextBoom-ppocr-preview-media-path.apk
  sha256=2746ec8547ce6f5e9e76879d324a9a312e61a496910ef8d0f8df68edaaac1ac9
ROM:
  hard-rom/build/super-otatrust-v0.42.1-textboom-ppocr-preview-media-path.sparse.img
  sha256=27767d12828eaf0628290a49ca7391007f7fad6d631db97f3f345c8ed40260e1
Verifier:
  PASS_OFFLINE_IMAGE_V0421_TEXTBOOM_PPOCR_PREVIEW_MEDIA_PATH
```

Live verdict for v0.42.1:

```text
Flash/read-only verifier:
  PASS_READ_ONLY_V0421_TEXTBOOM_PPOCR_PREVIEW_MEDIA_PATH
OCR regression:
  3/3 BOOM_IMAGE cases launched BoomOcrActivity and produced matching OCR chips
Preview file:
  missing at /sdcard/Android/media/com.smartisanos.textboom/.boom/imageboom.jpg
Log/static root cause:
  startOcrCropped(1) calls dealSaveBitmapResult(bitmap), which starts
  LocalPpOcrApi without entering the old TaskHandler saveBMtoLocal branch.
```

The v0.42.2 follow-up keeps the Android/media path and patches
`BoomOcrActivity.dealSaveBitmapResult(bitmap)` so it saves the bitmap before
calling `IOcrApi.startOcr(...)`:

```text
APK:
  hard-rom/build/apk/TextBoom-ppocr-preview-save-before-ocr.apk
  sha256=b783bb1face44039a8065991ef0274ae717bad3ef889618df995409baf4ebc98
ROM:
  hard-rom/build/super-otatrust-v0.42.2-textboom-ppocr-preview-save-before-ocr.sparse.img
  sha256=e74e76960e15eb9a608742cafdf1bbfda597b9277f922ed019c6b525f328cb40
Verifier:
  PASS_OFFLINE_IMAGE_V0422_TEXTBOOM_PPOCR_PREVIEW_SAVE_BEFORE_OCR
```

The larger per-run path/Intent-extra design remains the better long-term
shape, but v0.42 deliberately starts with the smallest fix that preserves all
existing `OCR_IMAGE_PATH` call sites:

```text
1. Keep OCR input in-memory for the PP-OCR runtime.
2. Save the preview bitmap into a TextBoom-owned app-specific file path.
3. Keep BoomChipPage.loadOcrImageView() and getOcrImageSize() on
   FileUtils.OCR_IMAGE_PATH for the first candidate.
4. Live-verify that the new file hash/mtime follows each selected screen
   region and the result-page preview updates.
5. If any stale-cache behavior remains, move to a per-run path or explicit
   Intent extra and then remove reliance on a fixed file name.
```

## Boundary

The BOOM_IMAGE regression script itself does not flash, reboot, erase, install,
uninstall, clear app data, or modify ROM images. It does force-stop the
TextBoom process between live cases to avoid reusing an existing result
activity.

The v0.42.2 build has now been flashed and live-verified. The fixed filename
preview route is acceptable for the next deletion gate. A per-run path or
explicit Intent-extra design can still be revisited later if stale-cache
behavior reappears, but it is no longer the active blocker.
