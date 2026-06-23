#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
LOCALE_POLICY="${LOCALE_POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.10-framework-locale-prune"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.10-framework-locale-prune.img"
EXPECTED_PRODUCT_IMG="${ROOT_DIR}/hard-rom/build/product-otatrust-v0.10-framework-locale-prune.img"

APK_OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
EXPECTED_FW_RES="${APK_OUT_DIR}/framework-res-locale-prune-en-zh.apk"
EXPECTED_FW_SMARTISAN="${APK_OUT_DIR}/framework-smartisanos-res-locale-prune-en-zh.apk"

mode="read-only"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.10-framework-locale-prune.sh --offline-image
  tools/r2-verify-v0.10-framework-locale-prune.sh [--read-only]

--offline-image verifies the generated system/product images on the Mac:
  - framework-res and framework-smartisanos-res inside system_b match expected
  - five DisplayCutout static overlay APKs inside product_b match expected
  - the sparse super system_b/product_b logical slices match those images
  - each expected APK has the known resources.arsc digest-error boundary

--read-only verifies after a v0.10 flash on the live device:
  - boot/slot/root state evidence
  - pulled framework/product overlay APKs match the expected v0.10 APKs
  - current locale/resource/overlay/logcat evidence is captured

The script never flashes, reboots, erases misc, or changes /data.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    adb devices >&2
    die "device ${SERIAL} is not available over adb"
  fi
}

verify_resource_sig_boundary() {
  local apk="$1"
  local report="$2"
  "$SIGCHECK" "$apk" > "$report"
  grep -q '^keytool_status=1$' "$report" \
    || die "unexpected keytool boundary for ${apk}"
  grep -q 'SHA-256 digest error for resources.arsc' "$report" \
    || die "expected resources.arsc digest boundary missing for ${apk}"
}

compare_file_hash() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local actual_hash
  local expected_hash
  actual_hash="$(sha256_one "$actual")"
  expected_hash="$(sha256_one "$expected")"
  [ "$actual_hash" = "$expected_hash" ] || die "${label} hash mismatch: actual=${actual_hash} expected=${expected_hash}"
  printf '%s\t%s\t%s\n' "$label" "$actual_hash" "$actual"
}

expected_overlay_apk() {
  local name="$1"
  printf '%s/DisplayCutoutEmulation%sOverlay-locale-prune-en-zh.apk' "$APK_OUT_DIR" "$name"
}

offline_dump_and_compare() {
  local image="$1"
  local image_path="$2"
  local expected="$3"
  local label="$4"
  local out="$5"
  "$DEBUGFS" -R "dump ${image_path} ${out}" "$image" >/dev/null 2>&1
  compare_file_hash "$out" "$expected" "$label"
}

verify_expected_inputs() {
  need_file "$EXPECTED_FW_RES"
  need_file "$EXPECTED_FW_SMARTISAN"
  for name in Corner Double Hole Tall Waterfall; do
    need_file "$(expected_overlay_apk "$name")"
  done
  need_file "$SIGCHECK"
  need_file "$LOCALE_POLICY"
  need_executable "$SIGCHECK"
  need_executable "$LOCALE_POLICY"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  need_file "$EXPECTED_PRODUCT_IMG"
  verify_expected_inputs
  need_executable "$SPARSE_TOOL"
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.10-offline-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.10-framework-locale-prune offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo "expected_product_img=${EXPECTED_PRODUCT_IMG}"
    echo

    echo "## signature boundaries"
    verify_resource_sig_boundary "$EXPECTED_FW_RES" "${dump_dir}/framework-res.signature.txt"
    verify_resource_sig_boundary "$EXPECTED_FW_SMARTISAN" "${dump_dir}/framework-smartisanos-res.signature.txt"
    for name in Corner Double Hole Tall Waterfall; do
      verify_resource_sig_boundary "$(expected_overlay_apk "$name")" "${dump_dir}/DisplayCutoutEmulation${name}Overlay.signature.txt"
    done
    echo "signature_boundary=ok"
    echo

    echo "## system_b inserted APKs"
    offline_dump_and_compare "$EXPECTED_SYSTEM_IMG" \
      "/system/framework/framework-res.apk" \
      "$EXPECTED_FW_RES" \
      "system/framework-res.apk" \
      "${dump_dir}/framework-res.apk"
    offline_dump_and_compare "$EXPECTED_SYSTEM_IMG" \
      "/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk" \
      "$EXPECTED_FW_SMARTISAN" \
      "system/framework-smartisanos-res.apk" \
      "${dump_dir}/framework-smartisanos-res.apk"
    echo

    echo "## product_b inserted APKs"
    for name in Corner Double Hole Tall Waterfall; do
      offline_dump_and_compare "$EXPECTED_PRODUCT_IMG" \
        "/overlay/DisplayCutoutEmulation${name}/DisplayCutoutEmulation${name}Overlay.apk" \
        "$(expected_overlay_apk "$name")" \
        "product/DisplayCutoutEmulation${name}Overlay.apk" \
        "${dump_dir}/DisplayCutoutEmulation${name}Overlay.apk"
    done
    echo

    echo "## locale resource policy"
    "$LOCALE_POLICY" --keep-languages en,zh --report "${dump_dir}/locale-policy.json" \
      "${dump_dir}/framework-res.apk" \
      "${dump_dir}/framework-smartisanos-res.apk" \
      "${dump_dir}/DisplayCutoutEmulationCornerOverlay.apk" \
      "${dump_dir}/DisplayCutoutEmulationDoubleOverlay.apk" \
      "${dump_dir}/DisplayCutoutEmulationHoleOverlay.apk" \
      "${dump_dir}/DisplayCutoutEmulationTallOverlay.apk" \
      "${dump_dir}/DisplayCutoutEmulationWaterfallOverlay.apk"
    echo "locale_policy=${dump_dir}/locale-policy.json"
    echo

    echo "## sparse partition slices"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" \
      --verify-image "system_b=${EXPECTED_SYSTEM_IMG}" \
      --verify-image "product_b=${EXPECTED_PRODUCT_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" "$EXPECTED_PRODUCT_IMG" \
      "$EXPECTED_FW_RES" "$EXPECTED_FW_SMARTISAN" \
      "$(expected_overlay_apk Corner)" "$(expected_overlay_apk Double)" \
      "$(expected_overlay_apk Hole)" "$(expected_overlay_apk Tall)" \
      "$(expected_overlay_apk Waterfall)"
  } | tee "$report"

  echo
  echo "PASS: v0.10 offline image verification"
  echo "Report: ${report}"
}

run_read_only_device() {
  need_file "$EXPECTED_SUPER"
  verify_expected_inputs
  require_device
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.10-device-${timestamp}.txt"
  local pull_dir="${INSPECT_DIR}/device-${timestamp}"
  mkdir -p "$pull_dir"

  {
    echo "# v0.10-framework-locale-prune device verification"
    echo "timestamp=${timestamp}"
    echo "serial=${SERIAL}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo

    echo "## adb"
    adb devices -l
    echo

    echo "## boot state"
    adb_device shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint; getprop persist.sys.locale; settings get system system_locales' | tr -d '\r'
    echo

    echo "## root"
    "$ROOT_HELPER" status || true
    echo

    echo "## locale commands"
    adb_device shell 'cmd locale 2>/dev/null || true; cmd uimode night 2>/dev/null || true' | tr -d '\r'
    echo

    echo "## overlay excerpt"
    adb_device shell 'cmd overlay list --user 0 2>/dev/null | grep -E "DisplayCutout|android" || true' | tr -d '\r'
    echo

    echo "## path labels"
    adb_device shell 'ls -lZ /system/framework/framework-res.apk /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk /product/overlay/DisplayCutoutEmulation*/DisplayCutoutEmulation*Overlay.apk 2>/dev/null' | tr -d '\r'
    echo

    echo "## window excerpt"
    adb_device shell "dumpsys window" > "${pull_dir}/window.txt" || true
    rg -n "mCurrentFocus|mFocusedApp|isKeyguardShowing" "${pull_dir}/window.txt" || true
    echo

    echo "## logcat excerpt"
    adb_device logcat -d -t 800 > "${pull_dir}/logcat.txt" || true
    rg -n "ResourcesManager|ResourcesImpl|AssetManager|OverlayManager|idmap|PackageManager|framework-res|smartisanos-res|DisplayCutout|FATAL EXCEPTION" "${pull_dir}/logcat.txt" || true
    echo
  } | tee "$report"

  adb_device pull /system/framework/framework-res.apk "${pull_dir}/framework-res.apk" >/dev/null
  adb_device pull /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk "${pull_dir}/framework-smartisanos-res.apk" >/dev/null

  compare_file_hash "${pull_dir}/framework-res.apk" "$EXPECTED_FW_RES" "device/framework-res.apk" | tee -a "$report"
  compare_file_hash "${pull_dir}/framework-smartisanos-res.apk" "$EXPECTED_FW_SMARTISAN" "device/framework-smartisanos-res.apk" | tee -a "$report"

  for name in Corner Double Hole Tall Waterfall; do
    adb_device pull \
      "/product/overlay/DisplayCutoutEmulation${name}/DisplayCutoutEmulation${name}Overlay.apk" \
      "${pull_dir}/DisplayCutoutEmulation${name}Overlay.apk" >/dev/null
    compare_file_hash \
      "${pull_dir}/DisplayCutoutEmulation${name}Overlay.apk" \
      "$(expected_overlay_apk "$name")" \
      "device/DisplayCutoutEmulation${name}Overlay.apk" | tee -a "$report"
  done

  {
    echo
    echo "## locale resource policy"
    "$LOCALE_POLICY" --keep-languages en,zh --report "${pull_dir}/locale-policy.json" \
      "${pull_dir}/framework-res.apk" \
      "${pull_dir}/framework-smartisanos-res.apk" \
      "${pull_dir}/DisplayCutoutEmulationCornerOverlay.apk" \
      "${pull_dir}/DisplayCutoutEmulationDoubleOverlay.apk" \
      "${pull_dir}/DisplayCutoutEmulationHoleOverlay.apk" \
      "${pull_dir}/DisplayCutoutEmulationTallOverlay.apk" \
      "${pull_dir}/DisplayCutoutEmulationWaterfallOverlay.apk"
    echo "locale_policy=${pull_dir}/locale-policy.json"
  } | tee -a "$report"

  echo
  echo "PASS: v0.10 device read-only verification"
  echo "Report: ${report}"
}

case "${1:---read-only}" in
  --offline-image)
    mode="offline-image"
    ;;
  --read-only|"")
    mode="read-only"
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

case "$mode" in
  offline-image)
    run_offline_image
    ;;
  read-only)
    run_read_only_device
    ;;
esac
