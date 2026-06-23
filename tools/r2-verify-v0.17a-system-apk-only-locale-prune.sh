#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
SPARSE_TOOL="${SPARSE_TOOL:-${ROOT_DIR}/tools/r2-sparse-partition-patch.py}"
POLICY="${POLICY:-${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py}"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.17a-system-apk-only-locale-prune"

EXPECTED_SUPER="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img"
EXPECTED_SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img"

BASIC_DREAMS_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.dreams.basic-locale-prune-en-zh.apk"
HTML_VIEWER_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.htmlviewer-locale-prune-en-zh.apk"
LIVE_WALLPAPER_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.wallpaper.livepicker-locale-prune-en-zh.apk"
PRINT_SPOOLER_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.printspooler-locale-prune-en-zh.apk"
SIM_APP_DIALOG_APK="${ROOT_DIR}/hard-rom/build/apk/com.android.simappdialog-locale-prune-en-zh.apk"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh --offline-image
  tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh --offline-system-image

--offline-image verifies the generated system_b image and flashable sparse super:
  - all five promoted system APKs match the expected APK-only candidates
  - dumped APK ZIP integrity passes
  - dumped APK resources.arsc locale policy contains only English/Chinese chunks
  - held-stock hidden paths exist for shared_blocks safety
  - the sparse super system_b logical slice matches the generated system image

--offline-system-image verifies only the generated system image on the Mac.

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

debugfs_path_exists() {
  local image="$1"
  local path="$2"
  local output
  output="$("$DEBUGFS" -R "stat ${path}" "$image" 2>&1 || true)"
  ! grep -q "File not found" <<<"$output"
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

verify_locale_policy() {
  local apk="$1"
  local label="$2"
  local policy_out
  policy_out="$("$POLICY" --keep-languages en,zh "$apk")"
  grep -q "bad_locale_chunk_count=0" <<<"$policy_out" || {
    echo "$policy_out" >&2
    die "${label} locale policy failed"
  }
  echo "${label}_locale_policy=ok"
  echo "$policy_out"
}

verify_expected_inputs() {
  need_file "$BASIC_DREAMS_APK"
  need_file "$HTML_VIEWER_APK"
  need_file "$LIVE_WALLPAPER_APK"
  need_file "$PRINT_SPOOLER_APK"
  need_file "$SIM_APP_DIALOG_APK"
  need_file "$POLICY"
  need_executable "$POLICY"
  unzip -t "$BASIC_DREAMS_APK" >/dev/null
  unzip -t "$HTML_VIEWER_APK" >/dev/null
  unzip -t "$LIVE_WALLPAPER_APK" >/dev/null
  unzip -t "$PRINT_SPOOLER_APK" >/dev/null
  unzip -t "$SIM_APP_DIALOG_APK" >/dev/null
}

dump_one() {
  local image="$1"
  local src_path="$2"
  local out="$3"
  "$DEBUGFS" -R "dump ${src_path} ${out}" "$image" >/dev/null 2>&1
  need_file "$out"
}

verify_held_path() {
  local image="$1"
  local path="$2"
  debugfs_path_exists "$image" "$path" || die "missing held-stock path: ${path}"
  echo "held_stock_path=${path}"
}

dump_and_verify_from_system_image() {
  local image="$1"
  local dump_dir="$2"

  dump_one "$image" "/system/app/BasicDreams/BasicDreams.apk" "${dump_dir}/BasicDreams.apk"
  dump_one "$image" "/system/app/HTMLViewer/HTMLViewer.apk" "${dump_dir}/HTMLViewer.apk"
  dump_one "$image" "/system/app/LiveWallpapersPicker/LiveWallpapersPicker.apk" "${dump_dir}/LiveWallpapersPicker.apk"
  dump_one "$image" "/system/app/PrintSpooler/PrintSpooler.apk" "${dump_dir}/PrintSpooler.apk"
  dump_one "$image" "/system/app/SimAppDialog/SimAppDialog.apk" "${dump_dir}/SimAppDialog.apk"

  compare_file_hash "${dump_dir}/BasicDreams.apk" "$BASIC_DREAMS_APK" "system/BasicDreams.apk"
  compare_file_hash "${dump_dir}/HTMLViewer.apk" "$HTML_VIEWER_APK" "system/HTMLViewer.apk"
  compare_file_hash "${dump_dir}/LiveWallpapersPicker.apk" "$LIVE_WALLPAPER_APK" "system/LiveWallpapersPicker.apk"
  compare_file_hash "${dump_dir}/PrintSpooler.apk" "$PRINT_SPOOLER_APK" "system/PrintSpooler.apk"
  compare_file_hash "${dump_dir}/SimAppDialog.apk" "$SIM_APP_DIALOG_APK" "system/SimAppDialog.apk"

  unzip -t "${dump_dir}/BasicDreams.apk" >/dev/null
  unzip -t "${dump_dir}/HTMLViewer.apk" >/dev/null
  unzip -t "${dump_dir}/LiveWallpapersPicker.apk" >/dev/null
  unzip -t "${dump_dir}/PrintSpooler.apk" >/dev/null
  unzip -t "${dump_dir}/SimAppDialog.apk" >/dev/null
  echo "zip_integrity=ok"

  verify_locale_policy "${dump_dir}/BasicDreams.apk" "system_basicdreams"
  verify_locale_policy "${dump_dir}/HTMLViewer.apk" "system_htmlviewer"
  verify_locale_policy "${dump_dir}/LiveWallpapersPicker.apk" "system_livewallpaperpicker"
  verify_locale_policy "${dump_dir}/PrintSpooler.apk" "system_printspooler"
  verify_locale_policy "${dump_dir}/SimAppDialog.apk" "system_simappdialog"

  verify_held_path "$image" "/system/app/BasicDreams/.BasicDreams.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/HTMLViewer/.HTMLViewer.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/LiveWallpapersPicker/.LiveWallpapersPicker.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/PrintSpooler/.PrintSpooler.apk.smartisax-v017a-stock-held"
  verify_held_path "$image" "/system/app/SimAppDialog/.SimAppDialog.apk.smartisax-v017a-stock-held"
}

run_offline_image() {
  need_executable "$DEBUGFS"
  need_executable "$SPARSE_TOOL"
  need_file "$EXPECTED_SUPER"
  need_file "$EXPECTED_SYSTEM_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.17a-offline-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.17a-system-apk-only-locale-prune offline image verification"
    echo "timestamp=${timestamp}"
    echo "expected_super=${EXPECTED_SUPER}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_from_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo

    echo "## sparse system_b slice"
    "$SPARSE_TOOL" --source-sparse "$EXPECTED_SUPER" --verify-image "system_b=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SUPER" "$EXPECTED_SYSTEM_IMG" \
      "$BASIC_DREAMS_APK" \
      "$HTML_VIEWER_APK" \
      "$LIVE_WALLPAPER_APK" \
      "$PRINT_SPOOLER_APK" \
      "$SIM_APP_DIALOG_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.17a offline image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

run_offline_system_image() {
  need_executable "$DEBUGFS"
  need_file "$EXPECTED_SYSTEM_IMG"
  verify_expected_inputs
  mkdir -p "$INSPECT_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local report="${INSPECT_DIR}/verify-v0.17a-offline-system-image-${timestamp}.txt"
  local dump_dir="${INSPECT_DIR}/offline-system-image-${timestamp}"
  mkdir -p "$dump_dir"

  {
    echo "# v0.17a-system-apk-only-locale-prune offline system image verification"
    echo "timestamp=${timestamp}"
    echo "expected_system_img=${EXPECTED_SYSTEM_IMG}"
    echo

    echo "## system_b inserted APKs"
    dump_and_verify_from_system_image "$EXPECTED_SYSTEM_IMG" "$dump_dir"
    echo

    echo "## hashes"
    shasum -a 256 "$EXPECTED_SYSTEM_IMG" \
      "$BASIC_DREAMS_APK" \
      "$HTML_VIEWER_APK" \
      "$LIVE_WALLPAPER_APK" \
      "$PRINT_SPOOLER_APK" \
      "$SIM_APP_DIALOG_APK"
  } | tee "$report"

  {
    echo
    echo "result=PASS"
    echo "PASS: v0.17a offline system image verification"
  } | tee -a "$report"
  echo "Report: ${report}"
}

case "${1:---offline-image}" in
  --offline-image)
    run_offline_image
    ;;
  --offline-system-image)
    run_offline_system_image
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
