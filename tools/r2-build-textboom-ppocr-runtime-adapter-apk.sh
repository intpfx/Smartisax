#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

JAVA_BIN="${JAVA_BIN:-${JAVA_HOME}/bin/java}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
DEXDUMP="${DEXDUMP:-${ANDROID_SDK_ROOT}/build-tools/35.0.1/dexdump}"

RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
SOURCE_APK="${SOURCE_APK:-${ROOT_DIR}/apks/textboom-live/TextBoom-live-v3.2.2-base.apk}"
SOURCE_APK_SHA256="52df3deb5315baf41b9f5476a122ce9782fa58f74076d1d4a9c060c9c506873c"

APP_DIR="${ROOT_DIR}/apps/TextBoomPpOcrRuntimeBridge"
OFFICIAL_DIR="${ROOT_DIR}/third_party/_downloads/paddleocr-ppocr-android/PaddleOCR/deploy/ppocr-android"
ONNX_ROOT="${PPOCRV6_ONNX_ROOT:-${ROOT_DIR}/hard-rom/build/ppocr-runtime/onnx}"

VARIANT="${VARIANT:-v0.41-textboom-ppocr-runtime-adapter}"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
WORK_DIR="${ROOT_DIR}/hard-rom/work/textboom-ppocr-runtime-adapter-apk"
FRAMEWORK_DIR="${WORK_DIR}/frameworks"
DECODED_DIR="${WORK_DIR}/decoded"
RUNTIME_PROJECT_DIR="${WORK_DIR}/runtime-gradle-project"
RUNTIME_CARRIER_APK="${WORK_DIR}/TextBoomPpOcrRuntimeCarrier.apk"
REBUILT_UNSIGNED="${WORK_DIR}/TextBoom-ppocr-runtime-adapter-rebuilt-unsigned.apk"
OUT_APK="${OUT_APK:-${OUT_DIR}/TextBoom-ppocr-runtime-adapter.apk}"
SIG_REPORT="${OUT_APK%.apk}.signature.txt"
ZIP_REPORT="${OUT_APK%.apk}.zip-boundary.txt"
DEX_REPORT="${OUT_APK%.apk}.dex-boundary.txt"
MANIFEST="${OUT_DIR}/textboom-ppocr-runtime-adapter-apk-manifest.tsv"

PACKAGE="com.smartisax.textboom.ppocr.carrier"
ABI="arm64-v8a"
ORT_ANDROID_VERSION="1.21.1"
OPENCV_COORDINATE="${OPENCV_COORDINATE:-org.opencv:opencv:4.9.0}"
OPENCV_VERSION_LABEL="${OPENCV_VERSION_LABEL:-4.9.0-official-aar}"
AGP_VERSION="8.7.3"
KOTLIN_VERSION="2.1.0"
KOTLIN_STDLIB_VERSION="${KOTLIN_STDLIB_VERSION:-1.5.20}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-textboom-ppocr-runtime-adapter-apk.sh

Builds an APK-only TextBoom candidate for the real local PP-OCR runtime gate.
It starts from the live TextBoom v3.2.2 APK, keeps the stock shell, changes the
two IOcrApi instantiation sites to LocalPpOcrApi, and adds:

  - official ppocr-sdk runtime dex, excluding the suspend PaddleOCR wrapper
  - PP-OCRv6 small det/rec ONNX assets
  - onnxruntime-android/OpenCV arm64 native libraries

This script does not build a super image, touch a device, flash, reboot, erase
partitions, install packages, or modify /data.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_dir() {
  [ -d "$1" ] || die "missing directory: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

require_hash() {
  local path="$1" expected="$2" actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  [ "$actual" = "$expected" ] || die "hash mismatch for ${path}: actual=${actual} expected=${expected}"
}

install_frameworks() {
  mkdir -p "$FRAMEWORK_DIR"
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

build_runtime_carrier() {
  rm -rf "$RUNTIME_PROJECT_DIR"
  mkdir -p \
    "${RUNTIME_PROJECT_DIR}/app/src/main/java" \
    "${RUNTIME_PROJECT_DIR}/app/src/main/assets/models/det" \
    "${RUNTIME_PROJECT_DIR}/app/src/main/assets/models/rec" \
    "${RUNTIME_PROJECT_DIR}/ppocr-sdk/src/main"

  cp "${OFFICIAL_DIR}/gradlew" "${RUNTIME_PROJECT_DIR}/gradlew"
  chmod +x "${RUNTIME_PROJECT_DIR}/gradlew"
  cp -R "${OFFICIAL_DIR}/gradle" "${RUNTIME_PROJECT_DIR}/gradle"
  cp -R "${OFFICIAL_DIR}/ppocr-sdk/src/main/java" "${RUNTIME_PROJECT_DIR}/ppocr-sdk/src/main/java"
  rm -f "${RUNTIME_PROJECT_DIR}/ppocr-sdk/src/main/java/com/paddle/ocr/PaddleOCR.kt"
  cp -R "${APP_DIR}/src/main/java" "${RUNTIME_PROJECT_DIR}/app/src/main/java"
  cp "${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx" "${RUNTIME_PROJECT_DIR}/app/src/main/assets/models/det/inference.onnx"
  cp "${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx" "${RUNTIME_PROJECT_DIR}/app/src/main/assets/models/rec/inference.onnx"
  cp "${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml" "${RUNTIME_PROJECT_DIR}/app/src/main/assets/models/rec/inference.yml"

  cat > "${RUNTIME_PROJECT_DIR}/settings.gradle.kts" <<EOF
pluginManagement {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

rootProject.name = "TextBoomPpOcrRuntimeCarrierGenerated"
include(":app")
include(":ppocr-sdk")
EOF

  cat > "${RUNTIME_PROJECT_DIR}/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "${AGP_VERSION}" apply false
    id("com.android.library") version "${AGP_VERSION}" apply false
    id("org.jetbrains.kotlin.android") version "${KOTLIN_VERSION}" apply false
}
EOF

  cat > "${RUNTIME_PROJECT_DIR}/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx4096m -Dfile.encoding=UTF-8
android.useAndroidX=false
kotlin.code.style=official
kotlin.stdlib.default.dependency=false
android.nonTransitiveRClass=true
android.builder.sdkDownload=false
EOF

  cat > "${RUNTIME_PROJECT_DIR}/ppocr-sdk/build.gradle.kts" <<EOF
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.paddle.ocr"
    compileSdk = 35
    buildToolsVersion = "35.0.1"

    defaultConfig {
        minSdk = 26
        ndk {
            abiFilters += "${ABI}"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:${ORT_ANDROID_VERSION}")
    implementation("${OPENCV_COORDINATE}") {
        exclude(group = "org.jetbrains.kotlin")
    }
    compileOnly("org.jetbrains.kotlin:kotlin-stdlib:${KOTLIN_STDLIB_VERSION}")
}
EOF

  cat > "${RUNTIME_PROJECT_DIR}/app/build.gradle.kts" <<EOF
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "${PACKAGE}"
    compileSdk = 35
    buildToolsVersion = "35.0.1"

    defaultConfig {
        applicationId = "${PACKAGE}"
        minSdk = 26
        targetSdk = 30
        versionCode = 1
        versionName = "0.1.0"
        ndk {
            abiFilters += "${ABI}"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
            )
        }
    }

    lint {
        disable += "ExpiredTargetSdkVersion"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":ppocr-sdk"))
    compileOnly("org.jetbrains.kotlin:kotlin-stdlib:${KOTLIN_STDLIB_VERSION}")
}
EOF

  cat > "${RUNTIME_PROJECT_DIR}/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:extractNativeLibs="true" android:hasCode="true" />
</manifest>
EOF

  (
    cd "$RUNTIME_PROJECT_DIR"
    ./gradlew --no-daemon --console=plain :app:assembleRelease
  )

  local built_apk
  built_apk="$(
    find "${RUNTIME_PROJECT_DIR}/app/build/outputs/apk/release" -maxdepth 1 -type f -name '*.apk' | sort | sed -n '1p'
  )"
  [ -n "$built_apk" ] || die "runtime carrier APK was not built"
  cp "$built_apk" "$RUNTIME_CARRIER_APK"
}

patch_textboom_smali() {
  "$PYTHON_BIN" - "$DECODED_DIR" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
ocr_dir = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr"
boom = ocr_dir / "BoomOcrActivity.smali"
access = ocr_dir / "BoomAccessOcrActivity.smali"
adapter = ocr_dir / "LocalPpOcrApi.smali"

for path in (boom, access):
    if not path.exists():
        raise SystemExit(f"missing smali: {path}")

def replace_exact(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

replace_exact(
    boom,
    """    .line 110
    new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;

    iget-object v1, p0, Lcom/smartisanos/textboom/ocr/BoomOcrActivity;->mContext:Landroid/content/Context;

    invoke-direct {v0, v1}, Lcom/smartisanos/textboom/ocr/CsOcr;-><init>(Landroid/content/Context;)V
""",
    """    .line 110
    new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;

    iget-object v1, p0, Lcom/smartisanos/textboom/ocr/BoomOcrActivity;->mContext:Landroid/content/Context;

    invoke-direct {v0, v1}, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;-><init>(Landroid/content/Context;)V
""",
    "BoomOcrActivity.initView CsOcr constructor",
)

replace_exact(
    access,
    """    .line 131
    new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;

    invoke-direct {v0, p0}, Lcom/smartisanos/textboom/ocr/CsOcr;-><init>(Landroid/content/Context;)V
""",
    """    .line 131
    new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;

    invoke-direct {v0, p0}, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;-><init>(Landroid/content/Context;)V
""",
    "BoomAccessOcrActivity.initOcr CsOcr constructor",
)

adapter.write_text(
    """.class public Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;
.super Ljava/lang/Object;
.source "LocalPpOcrApi.java"
.implements Lcom/smartisanos/textboom/ocr/IOcrApi;


# direct methods
.method public constructor <init>(Landroid/content/Context;)V
    .locals 0
    .param p1, "context"    # Landroid/content/Context;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public handleOcrResult(IILandroid/content/Intent;Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;)V
    .locals 0
    .param p1, "requestCode"    # I
    .param p2, "resultCode"    # I
    .param p3, "data"    # Landroid/content/Intent;
    .param p4, "listener"    # Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;

    return-void
.end method

.method public startOcr(Landroid/app/Activity;Landroid/graphics/Bitmap;ILcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;Z)V
    .locals 0
    .param p1, "activity"    # Landroid/app/Activity;
    .param p2, "bitmap"    # Landroid/graphics/Bitmap;
    .param p3, "language"    # I
    .param p4, "listener"    # Lcom/smartisanos/textboom/ocr/IOcrApi$OcrListener;
    .param p5, "fromFloat"    # Z

    if-eqz p4, :cond_0

    invoke-static {p1, p2, p3, p4, p5}, Lcom/smartisax/textboom/ppocr/LocalPpOcrRuntime;->start(Landroid/app/Activity;Landroid/graphics/Bitmap;ILjava/lang/Object;Z)V

    :cond_0
    return-void
.end method
""",
    encoding="utf-8",
)

for path, label in ((boom, "BoomOcrActivity"), (access, "BoomAccessOcrActivity")):
    text = path.read_text(encoding="utf-8")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;" in text:
        raise SystemExit(f"{label} still instantiates CsOcr")
    if "Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in text:
        raise SystemExit(f"{label} missing LocalPpOcrApi")

if not (ocr_dir / "CsOcr.smali").exists():
    raise SystemExit("CsOcr was unexpectedly removed")
if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
    raise SystemExit("TextBoom local com.intsig.csopen SDK was unexpectedly removed")

print("patched_textboom_runtime_instantiation=ok")
PY
}

next_classes_index() {
  "$PYTHON_BIN" - "$SOURCE_APK" <<'PY'
from __future__ import annotations

import re
import sys
import zipfile

def dex_index(name: str) -> int | None:
    if name == "classes.dex":
        return 1
    match = re.fullmatch(r"classes(\d+)\.dex", name)
    return int(match.group(1)) if match else None

with zipfile.ZipFile(sys.argv[1]) as zf:
    indexes = [idx for name in zf.namelist() for idx in [dex_index(name)] if idx is not None]
print(max(indexes) + 1)
PY
}

runtime_dex_names() {
  "$PYTHON_BIN" - "$RUNTIME_CARRIER_APK" <<'PY'
from __future__ import annotations

import re
import sys
import zipfile

def key(name: str) -> int:
    if name == "classes.dex":
        return 1
    match = re.fullmatch(r"classes(\d+)\.dex", name)
    return int(match.group(1)) if match else 9999

with zipfile.ZipFile(sys.argv[1]) as zf:
    names = sorted(
        [name for name in zf.namelist() if re.fullmatch(r"classes(\d*)\.dex", name)],
        key=key,
    )
print("\n".join(names))
PY
}

merge_runtime_into_stock_shell() {
  local tmp next_index runtime_name out_name path
  tmp="$(mktemp -d "/tmp/r2-textboom-ppocr-runtime-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  cp "$SOURCE_APK" "${OUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" classes2.dex > "${tmp}/classes2.dex"
  (
    cd "$tmp"
    zip -q "${OUT_APK}.tmp" classes2.dex
  )

  next_index="$(next_classes_index)"
  while IFS= read -r runtime_name; do
    [ -n "$runtime_name" ] || continue
    out_name="classes${next_index}.dex"
    unzip -p "$RUNTIME_CARRIER_APK" "$runtime_name" > "${tmp}/${out_name}"
    (
      cd "$tmp"
      zip -q "${OUT_APK}.tmp" "$out_name"
    )
    next_index=$((next_index + 1))
  done < <(runtime_dex_names)

  for path in \
    assets/models/det/inference.onnx \
    assets/models/rec/inference.onnx \
    assets/models/rec/inference.yml \
    lib/arm64-v8a/libc++_shared.so \
    lib/arm64-v8a/libonnxruntime.so \
    lib/arm64-v8a/libonnxruntime4j_jni.so \
    lib/arm64-v8a/libopencv_java4.so
  do
    mkdir -p "${tmp}/$(dirname "$path")"
    unzip -p "$RUNTIME_CARRIER_APK" "$path" > "${tmp}/${path}"
    (
      cd "$tmp"
      zip -q "${OUT_APK}.tmp" "$path"
    )
  done

  mv "${OUT_APK}.tmp" "$OUT_APK"
}

verify_zip_boundary() {
  "$PYTHON_BIN" - "$SOURCE_APK" "$OUT_APK" "$ZIP_REPORT" <<'PY'
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

stock = Path(sys.argv[1])
out = Path(sys.argv[2])
report = Path(sys.argv[3])
allowed_changed = {"classes2.dex"}
required_added_prefixes = {
    "assets/models/det/inference.onnx",
    "assets/models/rec/inference.onnx",
    "assets/models/rec/inference.yml",
    "lib/arm64-v8a/libc++_shared.so",
    "lib/arm64-v8a/libonnxruntime.so",
    "lib/arm64-v8a/libonnxruntime4j_jni.so",
    "lib/arm64-v8a/libopencv_java4.so",
}

with zipfile.ZipFile(stock) as a, zipfile.ZipFile(out) as b:
    names_a = set(a.namelist())
    names_b = set(b.namelist())
    removed = sorted(names_a - names_b)
    added = sorted(names_b - names_a)
    changed = sorted(name for name in names_a & names_b if a.read(name) != b.read(name))
    runtime_dex_added = [name for name in added if re.fullmatch(r"classes\d+\.dex", name)]
    required_missing = sorted(path for path in required_added_prefixes if path not in names_b)

    if removed:
        raise SystemExit(f"removed zip entries: {removed}")
    if set(changed) != allowed_changed:
        raise SystemExit(f"unexpected changed entries: {changed}")
    if not runtime_dex_added:
        raise SystemExit("no runtime classesN.dex entry was added")
    if required_missing:
        raise SystemExit(f"missing required runtime entries: {required_missing}")

    allowed_added = set(runtime_dex_added) | required_added_prefixes
    unexpected_added = sorted(name for name in added if name not in allowed_added)
    if unexpected_added:
        raise SystemExit(f"unexpected added entries: {unexpected_added}")

    lines = [
        "changed_entries=" + ",".join(changed),
        "added_runtime_dex=" + ",".join(runtime_dex_added),
        "added_assets_and_libs=" + ",".join(sorted(required_added_prefixes)),
    ]
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("zip_boundary=ok")
PY
}

verify_dex_boundary() {
  "$PYTHON_BIN" - "$DEXDUMP" "$SOURCE_APK" "$OUT_APK" "$DEX_REPORT" <<'PY'
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

dexdump = Path(sys.argv[1])
stock_apk = Path(sys.argv[2])
out_apk = Path(sys.argv[3])
report = Path(sys.argv[4])

def dex_index(name: str) -> int | None:
    if name == "classes.dex":
        return 1
    match = re.fullmatch(r"classes(\d+)\.dex", name)
    return int(match.group(1)) if match else None

def descriptors(path: Path) -> set[str]:
    proc = subprocess.run(
        [str(dexdump), "-f", str(path)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    found: set[str] = set()
    for line in proc.stdout.decode("utf-8", errors="replace").splitlines():
        marker = "Class descriptor  : '"
        if marker in line:
            found.add(line.split(marker, 1)[1].split("'", 1)[0])
    return found

with tempfile.TemporaryDirectory(prefix="r2-ppocr-dex-") as tmp_raw:
    tmp = Path(tmp_raw)
    stock_dir = tmp / "stock"
    out_dir = tmp / "out"
    stock_dir.mkdir()
    out_dir.mkdir()
    with zipfile.ZipFile(stock_apk) as zf:
        stock_dex_names = sorted(
            [name for name in zf.namelist() if dex_index(name) is not None],
            key=lambda item: dex_index(item) or 0,
        )
        for name in stock_dex_names:
            (stock_dir / name).write_bytes(zf.read(name))
    with zipfile.ZipFile(out_apk) as zf:
        out_dex_names = sorted(
            [name for name in zf.namelist() if dex_index(name) is not None],
            key=lambda item: dex_index(item) or 0,
        )
        for name in out_dex_names:
            (out_dir / name).write_bytes(zf.read(name))

    stock_max = max(dex_index(name) or 0 for name in stock_dex_names)
    runtime_names = [name for name in out_dex_names if (dex_index(name) or 0) > stock_max]
    if not runtime_names:
        raise SystemExit("no runtime dex entries found")

    stock_classes: set[str] = set()
    for name in stock_dex_names:
        stock_classes.update(descriptors(stock_dir / name))

    runtime_classes: set[str] = set()
    for name in runtime_names:
        runtime_classes.update(descriptors(out_dir / name))

duplicates = sorted(stock_classes & runtime_classes)
forbidden_prefixes = ("Lkotlin/", "Lkotlinx/", "Lcom/smartisanos/textboom/ocr/")
forbidden = sorted(
    desc for desc in runtime_classes
    if desc.startswith(forbidden_prefixes)
)
required = {
    "Lcom/smartisax/textboom/ppocr/LocalPpOcrRuntime;",
    "Lcom/paddle/ocr/engine/OCREngine;",
    "Lai/onnxruntime/OrtEnvironment;",
    "Lorg/opencv/android/Utils;",
}
missing = sorted(required - runtime_classes)

if duplicates:
    raise SystemExit("duplicate classes between stock TextBoom dex and runtime dex:\n" + "\n".join(duplicates[:200]))
if forbidden:
    raise SystemExit("forbidden runtime descriptors:\n" + "\n".join(forbidden[:200]))
if missing:
    raise SystemExit("missing required runtime descriptors:\n" + "\n".join(missing))

report.write_text(
    "\n".join(
        [
            "stock_dex_count=" + str(len(stock_dex_names)),
            "runtime_dex_entries=" + ",".join(runtime_names),
            "runtime_class_count=" + str(len(runtime_classes)),
            "duplicate_class_count=0",
            "forbidden_runtime_descriptor_count=0",
            "required_runtime_descriptors=present",
        ]
    )
    + "\n",
    encoding="utf-8",
)
print("dex_boundary=ok")
PY
}

verify_rebuilt_semantics() {
  local verify_decode="${WORK_DIR}/verify-decoded" strings_file="${WORK_DIR}/classes2.strings"
  rm -rf "$verify_decode"
  unzip -t "$OUT_APK" >/dev/null
  unzip -p "$OUT_APK" classes2.dex | strings > "$strings_file"
  grep -q 'LocalPpOcrApi' "$strings_file" \
    || die "merged classes2.dex missing LocalPpOcrApi"
  grep -q 'LocalPpOcrRuntime' "$strings_file" \
    || die "merged classes2.dex missing LocalPpOcrRuntime bridge call"

  "$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$verify_decode" "$OUT_APK" >/dev/null
  "$PYTHON_BIN" - "$verify_decode" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

root = Path(sys.argv[1])
ocr_dir = root / "smali_classes2" / "com" / "smartisanos" / "textboom" / "ocr"
for name, label in {
    "BoomOcrActivity.smali": "BoomOcrActivity",
    "BoomAccessOcrActivity.smali": "BoomAccessOcrActivity",
}.items():
    text = (ocr_dir / name).read_text(encoding="utf-8", errors="replace")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/CsOcr;" in text:
        raise SystemExit(f"{label} still instantiates CsOcr")
    if "new-instance v0, Lcom/smartisanos/textboom/ocr/LocalPpOcrApi;" not in text:
        raise SystemExit(f"{label} missing LocalPpOcrApi instantiation")

adapter = ocr_dir / "LocalPpOcrApi.smali"
text = adapter.read_text(encoding="utf-8", errors="replace")
for token in (
    ".implements Lcom/smartisanos/textboom/ocr/IOcrApi;",
    "Lcom/smartisax/textboom/ppocr/LocalPpOcrRuntime;->start",
):
    if token not in text:
        raise SystemExit(f"LocalPpOcrApi missing {token}")
if "onResultSuccess(Ljava/util/List;)V" in text:
    raise SystemExit("LocalPpOcrApi still contains the v0.40 no-op success callback")
if not (ocr_dir / "CsOcr.smali").exists():
    raise SystemExit("legacy CsOcr unexpectedly removed before runtime live gate")
if not (root / "smali_classes2" / "com" / "intsig" / "csopen").exists():
    raise SystemExit("legacy com.intsig.csopen unexpectedly removed before runtime live gate")
print("textboom_ppocr_runtime_adapter_semantics=ok")
PY
}

write_signature_report() {
  "$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"
  grep -q '^apk_sig_block_magic=absent$' "$SIG_REPORT" \
    || die "TextBoom v2/v3 signing-block boundary changed"
  grep -q 'digest error for classes2.dex' "$SIG_REPORT" \
    || die "TextBoom signature boundary did not point at classes2.dex"
}

case "${1:-}" in
  "")
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

need_file "$APKTOOL"
need_file "$FW_ANDROID"
need_file "$FW_SMARTISAN"
need_file "$SOURCE_APK"
need_file "${APP_DIR}/src/main/java/com/smartisax/textboom/ppocr/LocalPpOcrRuntime.kt"
need_dir "$OFFICIAL_DIR"
need_file "${OFFICIAL_DIR}/gradlew"
need_dir "${OFFICIAL_DIR}/gradle"
need_dir "${OFFICIAL_DIR}/ppocr-sdk/src/main/java"
need_file "${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx"
need_file "${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx"
need_file "${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"
need_executable "$DEXDUMP"
need_command zip
need_command unzip
need_command strings
require_hash "$SOURCE_APK" "$SOURCE_APK_SHA256"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT" "$ZIP_REPORT" "$DEX_REPORT" "$MANIFEST" "$REBUILT_UNSIGNED" "$RUNTIME_CARRIER_APK"

echo "Building PP-OCR runtime carrier..."
build_runtime_carrier

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding TextBoom..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$SOURCE_APK" >/dev/null

echo "Patching TextBoom IOcrApi instantiation to LocalPpOcrApi runtime bridge..."
patch_textboom_smali

echo "Rebuilding patched TextBoom as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging runtime dex/assets/native libs into stock TextBoom shell..."
merge_runtime_into_stock_shell

echo "Verifying ZIP, dex, and adapter boundaries..."
verify_zip_boundary
verify_dex_boundary
verify_rebuilt_semantics

echo "Writing signature boundary report..."
write_signature_report

{
  echo "variant=${VARIANT}"
  echo "source_apk=${SOURCE_APK}"
  echo "source_apk_sha256=${SOURCE_APK_SHA256}"
  echo "runtime_source=${APP_DIR}"
  echo "official_ppocr_android=${OFFICIAL_DIR}"
  echo "official_ppocr_android_commit=$(git -C "${OFFICIAL_DIR}" rev-parse HEAD 2>/dev/null || true)"
  echo "runtime_carrier_apk=${RUNTIME_CARRIER_APK}"
  echo "runtime_carrier_apk_sha256=$(sha256_one "$RUNTIME_CARRIER_APK")"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "out_apk=${OUT_APK}"
  echo "out_apk_sha256=$(sha256_one "$OUT_APK")"
  echo "signature_report=${SIG_REPORT}"
  echo "zip_boundary_report=${ZIP_REPORT}"
  echo "dex_boundary_report=${DEX_REPORT}"
  echo "model=PP-OCRv6_small"
  echo "det_model=${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx"
  echo "rec_model=${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx"
  echo "rec_config=${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml"
  echo "ort_android_version=${ORT_ANDROID_VERSION}"
  echo "opencv_dependency=${OPENCV_COORDINATE}"
  echo "opencv_version=${OPENCV_VERSION_LABEL}"
  echo "abi=${ABI}"
  echo "adapter=LocalPpOcrApi"
  echo "adapter_behavior=local_ppocr_runtime_async_line_results"
  echo "patched_entrypoints=BoomOcrActivity.initView,BoomAccessOcrActivity.initOcr"
  echo "legacy_csocr_retained=true"
  echo "legacy_intsig_csopen_retained=true"
  echo "legacy_ocr_key_retained=true"
  echo "runtime_dex_policy=no_stock_duplicate_classes_no_kotlin_or_textboom_ocr_classes"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 \
    "$SOURCE_APK" \
    "$RUNTIME_CARRIER_APK" \
    "$REBUILT_UNSIGNED" \
    "$OUT_APK" \
    "$SIG_REPORT" \
    "$ZIP_REPORT" \
    "$DEX_REPORT" \
    "${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx" \
    "${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx" \
    "${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Runtime carrier: ${RUNTIME_CARRIER_APK}"
echo "Signature report: ${SIG_REPORT}"
echo "ZIP report: ${ZIP_REPORT}"
echo "DEX report: ${DEX_REPORT}"
echo "Manifest: ${MANIFEST}"
echo "Flash gate: APK-only artifact; no live flash authorization."
