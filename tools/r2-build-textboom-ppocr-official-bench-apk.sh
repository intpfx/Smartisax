#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tools/r2-android-sdk-env.sh
. "${ROOT_DIR}/tools/r2-android-sdk-env.sh"

APP_DIR="${ROOT_DIR}/apps/TextBoomPpOcrOfficialBench"
OFFICIAL_DIR="${ROOT_DIR}/third_party/_downloads/paddleocr-ppocr-android/PaddleOCR/deploy/ppocr-android"
ONNX_ROOT="${PPOCRV6_ONNX_ROOT:-${ROOT_DIR}/hard-rom/build/ppocr-runtime/onnx}"
BUILD_DIR="${ROOT_DIR}/hard-rom/build/textboom-ppocr-official-bench"
PROJECT_DIR="${BUILD_DIR}/gradle-project"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/TextBoomPpOcrOfficialBench.apk"
MANIFEST="${OUT_DIR}/TextBoomPpOcrOfficialBench.SHA256SUMS.txt"
VERIFY_REPORT="${OUT_DIR}/TextBoomPpOcrOfficialBench.apksigner.txt"
BADGING_REPORT="${OUT_DIR}/TextBoomPpOcrOfficialBench.badging.txt"
ZIP_REPORT="${OUT_DIR}/TextBoomPpOcrOfficialBench.zip-layout.txt"
KEYSTORE="${ROOT_DIR}/hard-rom/keys/smartisax_apk.jks"
KEY_ALIAS="smartisax-apk"
KEY_PASS="SmartisaxApk2026"
PACKAGE="com.smartisax.ocrbench.officialbench"
VERSION_NAME="0.2.0"
VERSION_CODE="3"
ABI="arm64-v8a"
ORT_ANDROID_VERSION="1.21.1"
OPENCV_COORDINATE="${OPENCV_COORDINATE:-org.opencv:opencv:4.9.0}"
OPENCV_VERSION_LABEL="${OPENCV_VERSION_LABEL:-4.9.0-official-aar}"
TEXTBOOM_MANIFEST="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/jadx/system__system__app__TextBoom__TextBoom.apk/resources/AndroidManifest.xml"
CAMSCANNER_APP_KEY="${CAMSCANNER_APP_KEY:-}"
AGP_VERSION="8.7.3"
KOTLIN_VERSION="2.1.0"
COROUTINES_VERSION="1.9.0"
ANDROIDX_CORE_VERSION="1.15.0"

AAPT="${ANDROID_SDK_ROOT}/build-tools/35.0.1/aapt"
APKSIGNER="${ANDROID_SDK_ROOT}/build-tools/35.0.1/apksigner"
ZIPALIGN="${ANDROID_SDK_ROOT}/build-tools/35.0.1/zipalign"
KEYTOOL="${JAVA_HOME}/bin/keytool"

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

need_file "${APP_DIR}/AndroidManifest.xml"
need_dir "${APP_DIR}/res"
need_dir "${APP_DIR}/src/main/java"
need_file "$TEXTBOOM_MANIFEST"
need_dir "$OFFICIAL_DIR"
need_file "${OFFICIAL_DIR}/gradlew"
need_dir "${OFFICIAL_DIR}/gradle"
need_dir "${OFFICIAL_DIR}/ppocr-sdk/src/main/java"
need_file "${OFFICIAL_DIR}/ppocr-sdk/proguard-rules.pro"
need_file "${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx"
need_file "${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx"
need_file "${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml"
need_executable "$AAPT"
need_executable "$APKSIGNER"
need_executable "$ZIPALIGN"
need_executable "$KEYTOOL"

if [ -z "$CAMSCANNER_APP_KEY" ]; then
  CAMSCANNER_APP_KEY="$(
    python3 - "$TEXTBOOM_MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
android = "{http://schemas.android.com/apk/res/android}"
root = ET.parse(path).getroot()
for node in root.iter("meta-data"):
    if node.attrib.get(android + "name") == "ocr_key":
        print(node.attrib.get(android + "value", ""))
        break
PY
  )"
fi
[ -n "$CAMSCANNER_APP_KEY" ] || die "failed to resolve TextBoom ocr_key from $TEXTBOOM_MANIFEST"

mkdir -p "$OUT_DIR" "${ROOT_DIR}/hard-rom/keys"
rm -rf "$BUILD_DIR"
mkdir -p "$PROJECT_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$MANIFEST" "$VERIFY_REPORT" "$BADGING_REPORT" "$ZIP_REPORT"

if [ ! -f "$KEYSTORE" ]; then
  "$KEYTOOL" -genkeypair \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" \
    -keypass "$KEY_PASS" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 7300 \
    -dname 'CN=Smartisax APK, OU=ROM, O=Smartisax, L=Beijing, ST=Beijing, C=CN'
  chmod 600 "$KEYSTORE"
fi

cp "${OFFICIAL_DIR}/gradlew" "$PROJECT_DIR/gradlew"
chmod +x "$PROJECT_DIR/gradlew"
cp -R "${OFFICIAL_DIR}/gradle" "$PROJECT_DIR/gradle"

mkdir -p "${PROJECT_DIR}/app/src/main" "${PROJECT_DIR}/ppocr-sdk/src/main" "${PROJECT_DIR}/app/src/main/assets/models/det" "${PROJECT_DIR}/app/src/main/assets/models/rec"
cp "${APP_DIR}/AndroidManifest.xml" "${PROJECT_DIR}/app/src/main/AndroidManifest.xml"
cp -R "${APP_DIR}/res" "${PROJECT_DIR}/app/src/main/res"
cp -R "${APP_DIR}/src/main/java" "${PROJECT_DIR}/app/src/main/java"
cp -R "${OFFICIAL_DIR}/ppocr-sdk/src/main/java" "${PROJECT_DIR}/ppocr-sdk/src/main/java"
cp "${OFFICIAL_DIR}/ppocr-sdk/proguard-rules.pro" "${PROJECT_DIR}/ppocr-sdk/proguard-rules.pro"
cp "${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx" "${PROJECT_DIR}/app/src/main/assets/models/det/inference.onnx"
cp "${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx" "${PROJECT_DIR}/app/src/main/assets/models/rec/inference.onnx"
cp "${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml" "${PROJECT_DIR}/app/src/main/assets/models/rec/inference.yml"

cat > "${PROJECT_DIR}/settings.gradle.kts" <<EOF
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

rootProject.name = "TextBoomPpOcrOfficialBenchGenerated"
include(":app")
include(":ppocr-sdk")
EOF

cat > "${PROJECT_DIR}/build.gradle.kts" <<EOF
plugins {
    id("com.android.application") version "${AGP_VERSION}" apply false
    id("com.android.library") version "${AGP_VERSION}" apply false
    id("org.jetbrains.kotlin.android") version "${KOTLIN_VERSION}" apply false
}
EOF

cat > "${PROJECT_DIR}/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx4096m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
android.builder.sdkDownload=false
EOF

cat > "${PROJECT_DIR}/ppocr-sdk/build.gradle.kts" <<EOF
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
        consumerProguardFiles("proguard-rules.pro")
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
    implementation("${OPENCV_COORDINATE}")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:${COROUTINES_VERSION}")
    implementation("androidx.core:core-ktx:${ANDROIDX_CORE_VERSION}")
}
EOF

cat > "${PROJECT_DIR}/app/build.gradle.kts" <<EOF
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
        versionCode = ${VERSION_CODE}
        versionName = "${VERSION_NAME}"
        buildConfigField("String", "CAMSCANNER_APP_KEY", "\"${CAMSCANNER_APP_KEY}\"")
        ndk {
            abiFilters += "${ABI}"
        }
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("SMARTISAX_APK_KEYSTORE"))
            storePassword = System.getenv("SMARTISAX_APK_KEY_PASS")
            keyAlias = System.getenv("SMARTISAX_APK_KEY_ALIAS")
            keyPassword = System.getenv("SMARTISAX_APK_KEY_PASS")
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:${COROUTINES_VERSION}")
    implementation("androidx.core:core-ktx:${ANDROIDX_CORE_VERSION}")
}
EOF

(
  cd "$PROJECT_DIR"
  SMARTISAX_APK_KEYSTORE="$KEYSTORE" \
  SMARTISAX_APK_KEY_ALIAS="$KEY_ALIAS" \
  SMARTISAX_APK_KEY_PASS="$KEY_PASS" \
    ./gradlew --no-daemon --console=plain :app:assembleRelease
)

BUILT_APK="${PROJECT_DIR}/app/build/outputs/apk/release/app-release.apk"
need_file "$BUILT_APK"
cp "$BUILT_APK" "$OUT_APK"

"$APKSIGNER" verify --verbose --print-certs "$OUT_APK" > "$VERIFY_REPORT"
"$ZIPALIGN" -c -p 4 "$OUT_APK" >/dev/null
unzip -t "$OUT_APK" >/dev/null
"$AAPT" dump badging "$OUT_APK" > "$BADGING_REPORT"

python3 - "$OUT_APK" "$ZIP_REPORT" <<'PY'
import struct
import sys
import zipfile

apk = sys.argv[1]
report = sys.argv[2]
lines = []
with open(apk, "rb") as fp, zipfile.ZipFile(apk) as zf:
    for name in ("AndroidManifest.xml", "resources.arsc", "classes.dex"):
        info = zf.getinfo(name)
        fp.seek(info.header_offset)
        header = fp.read(30)
        if len(header) != 30:
            raise SystemExit(f"truncated ZIP local header for {name}")
        sig, _ver, _flag, method, *_rest, name_len, extra_len = struct.unpack("<IHHHHHIIIHH", header)
        if sig != 0x04034B50:
            raise SystemExit(f"bad ZIP local header signature for {name}")
        data_offset = info.header_offset + 30 + name_len + extra_len
        lines.append(
            f"{name}\tmethod={info.compress_type}\tlocal_method={method}\t"
            f"data_offset={data_offset}\taligned4={data_offset % 4 == 0}\tsize={info.file_size}"
        )
        if name == "resources.arsc":
            if info.compress_type != zipfile.ZIP_STORED or method != zipfile.ZIP_STORED:
                raise SystemExit("resources.arsc is not STORED")
            if data_offset % 4 != 0:
                raise SystemExit(f"resources.arsc data offset is not 4-byte aligned: {data_offset}")
open(report, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY

{
  echo "apk=${OUT_APK}"
  echo "source=${APP_DIR}"
  echo "official_ppocr_android=${OFFICIAL_DIR}"
  echo "official_ppocr_android_commit=$(git -C "${OFFICIAL_DIR}" rev-parse HEAD 2>/dev/null || true)"
  echo "package=${PACKAGE}"
  echo "versionName=${VERSION_NAME}"
  echo "versionCode=${VERSION_CODE}"
  echo "abi=${ABI}"
  echo "model=PP-OCRv6_small"
  echo "det_model=${ONNX_ROOT}/PP-OCRv6_small_det/model.onnx"
  echo "rec_model=${ONNX_ROOT}/PP-OCRv6_small_rec/model.onnx"
  echo "rec_config=${ONNX_ROOT}/PP-OCRv6_small_rec/inference.yml"
  echo "ort_android_version=${ORT_ANDROID_VERSION}"
  echo "opencv_dependency=${OPENCV_COORDINATE}"
  echo "opencv_version=${OPENCV_VERSION_LABEL}"
  echo "camscanner_app_key_source=${TEXTBOOM_MANIFEST}"
  echo "agp_version=${AGP_VERSION}"
  echo "kotlin_version=${KOTLIN_VERSION}"
  echo "signed_by=${KEYSTORE}"
  echo "verify_report=${VERIFY_REPORT}"
  echo "badging_report=${BADGING_REPORT}"
  echo "zip_layout_report=${ZIP_REPORT}"
  echo "default_device_input=/sdcard/Android/data/${PACKAGE}/files/input/imageboom.jpg"
  echo "default_device_result=/sdcard/Android/data/${PACKAGE}/files/results/last-result.json"
  echo "start=adb shell am start -n ${PACKAGE}/.MainActivity"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 \
    "$OUT_APK" \
    "$VERIFY_REPORT" \
    "$BADGING_REPORT" \
    "$ZIP_REPORT" \
    "${PROJECT_DIR}/app/src/main/assets/models/det/inference.onnx" \
    "${PROJECT_DIR}/app/src/main/assets/models/rec/inference.onnx" \
    "${PROJECT_DIR}/app/src/main/assets/models/rec/inference.yml"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Manifest: ${MANIFEST}"
