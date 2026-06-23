# TextBoom CsOcr / Intsig Deletion

Date: 2026-06-21

## Status

`v0.43e-textboom-codepath-arm64-runtime-repair` is the current accepted
live-verified candidate. `v0.43b-textboom-csocr-intsig-delete-manifest-retained`
remains the previous accepted reference. `v0.43c-textboom-force-arm32-abi` was flashed
as the follow-up ABI-control candidate and rejected: PackageManager still
selects `arm64-v8a` while arm64 native libs are absent, so BOOM_IMAGE fails the
PP-OCR OpenCV load path. `v0.43d-textboom-codepath-arm32-abi` was then flashed
as a codePath ABI-control candidate and also rejected: PackageManager accepts
the fresh `/system/app/TextBoomArm32` codePath but still selects `arm64-v8a`.
`v0.43e` accepts arm64-v8a and restores target arm64 ORT/OpenCV libraries under
`/system/app/TextBoomArm32/lib/arm64`; live BOOM_TEXT and three BOOM_IMAGE
regression cases pass with no native-link failure.

The earlier `v0.43a-textboom-csocr-intsig-delete` candidate was
offline-verified and flashed, but failed the live PackageManager gate after it
removed the manifest `ocr_key`. The file existed in `/system/app/TextBoom`, but
`pm path com.smartisanos.textboom` returned no package and BOOM intents did not
resolve. The accepted repair keeps the original `AndroidManifest.xml` and
`ocr_key`, and deletes only the legacy code reachable from `classes2.dex`.

## Deletion Scope

The accepted v0.43b candidate removes the real CamScanner executable code
surface from TextBoom while preserving the live-proven PP-OCR path:

```text
removed:
  com.smartisanos.textboom.ocr.CsOcr
  com.smartisanos.textboom.ocr.CsOcr$1
  com.smartisanos.textboom.ocr.-$$Lambda$CsOcr*
  TextBoom-local com.intsig.csopen smali package

retained:
  AndroidManifest.xml meta-data android:name="ocr_key" (v0.43b only)
  LocalPpOcrApi
  LocalPpOcrRuntime
  PP-OCRv6 small det/rec ONNX models
  Android/media preview save path
  arm32/arm64 ONNX Runtime and OpenCV libraries
  BOOM_TEXT and BOOM_IMAGE entry contracts
```

`BoomOcrActivity` also changes the remaining error log prefix from `CSOCR` to
`PPOCR`, so the code path no longer advertises the old backend when reporting
adapter errors.

The manifest `ocr_key` is now treated as a package-parse/signature-boundary
carrier, not as proof that the old OCR backend is still callable.

## Resource Boundary

v0.43b does not modify `resources.arsc`. The old CamScanner wording remains in
string resources as inert text because removing or renaming resource IDs is a
separate resource-table gate with a different risk profile.

The next cleanup after v0.43b live PASS should be a resource-string sweep that
either removes unreachable CamScanner strings or rewrites them to backend-neutral
OCR wording after a reference scan proves no live code still loads those IDs.

## Artifacts

```text
v0.43b APK:
  hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-manifest-retained.apk
v0.43b APK sha256:
  44d4f4393e061faf77ace20073d460dc8102797dd0847351a84e18fec886b192
v0.43b changed APK entries:
  classes2.dex

v0.43b super sparse:
  hard-rom/build/super-otatrust-v0.43b-textboom-csocr-intsig-delete-manifest-retained.sparse.img
v0.43b sparse sha256:
  e88559e276cb9c4fec68f63687af90bee937dde04e05ec6a7320b6d0645e226c
v0.43b system_b sha256:
  404922eb1a96e0616d781872cc5bdd2150ad26952e880026fae8b87ce1f0d15d

v0.43a rejected APK sha256:
  dbde0433b9a4bbec84ebb226a28b86188ece2c90a15f69c5099ddee6a6d6cd0e

v0.43c APK:
  hard-rom/build/apk/TextBoom-ppocr-csocr-intsig-delete-force-arm32.apk
v0.43c APK sha256:
  0627630d5f6e06a41b9f21c7a5cacc82be571eec4984d90ef715f681be6644d7
v0.43c removed APK entries:
  lib/arm64-v8a/*
v0.43c sparse sha256:
  0b42d185cfdc187b1065be15a3b0cf897be85dd05dceac9569e03341dda9ace2

v0.43e sparse sha256:
  d646db5c6462a80735327a3ba8bda2acc60b540df18f150c2d2cf70320f40863
v0.43e system_b sha256:
  858e9922e126444c66c04e94515bc3fd16e8991c45d557cfac926e2d2d9fa01f
v0.43e runtime repair:
  /system/app/TextBoomArm32/lib/arm64 restored
  APK-internal lib/arm64-v8a/* still absent
```

## Verification

APK verification proves:

```text
zip boundary:
  changed_entries=classes2.dex
manifest:
  ocr_key retained
classes2:
  LocalPpOcrApi retained
  LocalPpOcrRuntime retained
  /Android/media/com.smartisanos.textboom/.boom retained
  CsOcr absent
  com/intsig absent
  CSOCR absent
```

Image verification result:

```text
PASS_OFFLINE_IMAGE_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED

report:
  hard-rom/inspect/v0.43b-textboom-csocr-intsig-delete-manifest-retained/
    verify-v0.43b-textboom-csocr-intsig-delete-manifest-retained-offline-image-20260621-212607.txt
```

## Live Gate

v0.43b live result:

```text
PASS_READ_ONLY_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED

TextBoom package:
  codePath=/system/app/TextBoom
  primaryCpuAbi=arm64-v8a
  APK sha256=44d4f439...
  no UPDATED_SYSTEM_APP shadow

BOOM_IMAGE regression:
  3/3 cold-start cases launched BoomOcrActivity
  3/3 preview image hashes changed
  fatal_marker_count=0
  unsatisfied_link_marker_count=0

BOOM_TEXT smoke:
  am start status=ok
  Activity=com.smartisanos.textboom/.BoomActivity
  UI count text=共 44 字
```

Because PackageManager selects `arm64-v8a`, v0.43b raised a product decision:
accept the live-proven arm64 state, or try an ABI gate that removes TextBoom
arm64 runtime libs to force the previous `armeabi-v7a` state.

v0.43c implements that ABI gate at image level but fails the live gate:

```text
live verifier:
  WARN_READ_ONLY_V043C_TEXTBOOM_ARM64_PM_WITH_ARM64_LIBS_ABSENT
PackageManager:
  primaryCpuAbi=arm64-v8a
filesystem:
  /system/app/TextBoom/lib/arm64 absent
APK:
  lib/arm64-v8a/* absent
BOOM_TEXT:
  starts com.smartisanos.textboom/.BoomActivity
BOOM_IMAGE:
  returns to source app
  TextBoomLocalPpOcr logs OpenCV dlopen failure for libopencv_java4.so
```

v0.43d changes that ABI experiment from a native-library-only gate to a
PackageManager scan/codePath gate, but the live result is still rejected:

```text
public APK:
  /system/app/TextBoomArm32/TextBoomArm32.apk
old public APK:
  /system/app/TextBoom/TextBoom.apk absent
hidden held stock APK:
  /system/app/TextBoom/.TextBoom.apk.smartisax-v0.43d-textboom-codepath-arm32-abi-old-codepath-held
target arm32 libs:
  /system/app/TextBoomArm32/lib/arm
target arm64 libs:
  /system/app/TextBoomArm32/lib/arm64 absent
offline verifier:
  PASS_OFFLINE_IMAGE_V043D_TEXTBOOM_CODEPATH_ARM32_ABI
live verifier:
  WARN_READ_ONLY_V043D_CODEPATH_CHANGED_ABI_STILL_ARM64
PackageManager:
  codePath=/system/app/TextBoomArm32
  primaryCpuAbi=arm64-v8a
process:
  /system/bin/app_process64
BOOM_IMAGE:
  returns to source app
  TextBoomLocalPpOcr logs OpenCV dlopen failure for libopencv_java4.so
```

Conclusion: deleting arm64 native-library surfaces is not sufficient to force
`armeabi-v7a`, and changing only the system app codePath is also insufficient.
v0.43e takes the accept-arm64 repair branch and has passed live verification.
The CsOcr/Intsig deletion line should continue from v0.43e while the
lower-memory arm32-forcing problem remains a separate PackageManager policy
investigation.
