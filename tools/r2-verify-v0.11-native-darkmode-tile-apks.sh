#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

STOCK_SYSTEMUI_APK="${RAW}/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
STOCK_SETTINGS_APK="${RAW}/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"
OUT_SYSTEMUI="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk"
OUT_SETTINGS="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk"
SYSTEMUI_SIG="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.signature.txt"
SETTINGS_SIG="${ROOT_DIR}/hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.signature.txt"

INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/v0.11-native-darkmode-tile"

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

sha256_zip_member() {
  local apk="$1"
  local member="$2"
  unzip -p "$apk" "$member" | shasum -a 256 | awk '{print $1}'
}

assert_changed_dexes() {
  local label="$1"
  local stock="$2"
  local out="$3"
  shift 3
  local expected=("$@")

  local changed=()
  local dex
  while IFS= read -r dex; do
    local stock_hash
    local out_hash
    stock_hash="$(sha256_zip_member "$stock" "$dex")"
    out_hash="$(sha256_zip_member "$out" "$dex")"
    if [ "$stock_hash" != "$out_hash" ]; then
      changed+=("$dex")
    fi
  done < <(zipinfo -1 "$stock" 'classes*.dex' | sort)

  local changed_joined
  local expected_joined
  changed_joined="$(printf '%s\n' "${changed[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
  expected_joined="$(printf '%s\n' "${expected[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$changed_joined" = "$expected_joined" ] \
    || die "${label}: expected changed dexes [${expected_joined}], got [${changed_joined:-none}]"
}

assert_strings() {
  local apk="$1"
  local dex="$2"
  shift 2

  local tmp
  tmp="$(mktemp "/tmp/r2-v0.11-strings.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  unzip -p "$apk" "$dex" | strings > "$tmp"

  local needle
  for needle in "$@"; do
    grep -q "$needle" "$tmp" || die "${apk}:${dex} missing string ${needle}"
  done
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || die "${file} missing: ${needle}"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    die "${file} unexpectedly contains: ${needle}"
  fi
}

assert_brightness_darkmode_row_reachable() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")
title_at = text.find("    const v0, 0x7f120d5a")
label_at = text.rfind("    :cond_5\n", 0, title_at)
if label_at < 0 or title_at < 0:
    raise SystemExit("night_mode_yes title is not reachable from the Darwin :cond_5 path")
if title_at < label_at:
    raise SystemExit("night_mode_yes title appears before the Darwin :cond_5 path")
if title_at - label_at > 700:
    raise SystemExit("night_mode_yes title is too far from the Darwin :cond_5 path")
row_at = text.find(
    "Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitch:Lsmartisanos/widget/SettingItemSwitch;",
    label_at,
    title_at,
)
if row_at < 0:
    raise SystemExit("dark-mode switch row is not initialized immediately after the Darwin :cond_5 path")
print("brightness_darkmode_row_reachability=ok")
PY
}

decode_and_collect_smali() {
  local evidence_dir="$1"
  local tmp_dir="$2"
  local systemui_dir="${tmp_dir}/SystemUI"
  local settings_dir="${tmp_dir}/Settings"

  "$JAVA_BIN" -jar "$APKTOOL" d -r --no-assets -f \
    -o "$systemui_dir" "$OUT_SYSTEMUI" > "${evidence_dir}/decode-systemui.log" 2>&1
  "$JAVA_BIN" -jar "$APKTOOL" d -r --no-assets -f \
    -o "$settings_dir" "$OUT_SETTINGS" > "${evidence_dir}/decode-settings.log" 2>&1

  cp "${systemui_dir}/smali_classes10/com/android/systemui/qs/tiles/DarkModeTile.smali" \
    "${evidence_dir}/SystemUI-DarkModeTile.smali"
  cp "${systemui_dir}/smali_classes10/com/android/systemui/statusbar/phone/QSTileHost.smali" \
    "${evidence_dir}/SystemUI-QSTileHost.smali"
  cp "${settings_dir}/smali/com/android/settings/BrightnessSettingsFragment.smali" \
    "${evidence_dir}/Settings-BrightnessSettingsFragment.smali"
  cp "${settings_dir}/smali/com/android/settings/notificationcustom/QuickWidgetFactory.smali" \
    "${evidence_dir}/Settings-QuickWidgetFactory.smali"
  cp "${settings_dir}/smali_classes2/com/android/settings/widget/NotificationCustomView.smali" \
    "${evidence_dir}/Settings-NotificationCustomView.smali"
}

assert_smali_semantics() {
  local evidence_dir="$1"
  local dark_tile="${evidence_dir}/SystemUI-DarkModeTile.smali"
  local tile_host="${evidence_dir}/SystemUI-QSTileHost.smali"
  local brightness="${evidence_dir}/Settings-BrightnessSettingsFragment.smali"
  local widget="${evidence_dir}/Settings-QuickWidgetFactory.smali"
  local custom_view="${evidence_dir}/Settings-NotificationCustomView.smali"

  assert_contains "$dark_tile" '.class public Lcom/android/systemui/qs/tiles/DarkModeTile;'
  assert_contains "$dark_tile" 'Landroid/app/UiModeManager;->setNightModeActivated(Z)Z'
  assert_contains "$dark_tile" 'Landroid/app/UiModeManager;->setNightMode(I)V'
  assert_contains "$dark_tile" 'Landroid/app/UiModeManager;->getNightMode()I'
  assert_contains "$dark_tile" 'quick_settings_night_display_label'
  assert_contains "$dark_tile" 'com.android.settings.BrightnessSettingsActivity'
  assert_contains "$dark_tile" 'Landroid/widget/Switch;'

  assert_contains "$tile_host" 'const-string v0, "toggleDarkMode"'
  assert_contains "$tile_host" 'new-instance v0, Lcom/android/systemui/qs/tiles/DarkModeTile;'
  assert_contains "$tile_host" 'invoke-direct {v0, p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;-><init>(Lcom/android/systemui/qs/QSTile$Host;)V'

  assert_contains "$brightness" '.method private getUiModeManager()Landroid/app/UiModeManager;'
  assert_contains "$brightness" '.method private onDarkModeChanged()V'
  assert_contains "$brightness" '.method private setDarkModeActivated(Z)V'
  assert_contains "$brightness" 'const-string/jumbo v0, "uimode"'
  assert_contains "$brightness" 'Landroid/app/UiModeManager;->setNightModeActivated(Z)Z'
  assert_contains "$brightness" 'Landroid/app/UiModeManager;->getNightMode()I'
  assert_contains "$brightness" 'invoke-direct {p0, p2}, Lcom/android/settings/BrightnessSettingsFragment;->setDarkModeActivated(Z)V'
  assert_contains "$brightness" 'const v0, 0x7f120d5a'
  assert_brightness_darkmode_row_reachable "$brightness"
  assert_not_contains "$brightness" 'const-string/jumbo v0, "reduce_screen_strobe"'
  assert_not_contains "$brightness" 'Lcom/android/settings/Calibration;->setReduceScreenStrobeEnable(Z)V'

  assert_contains "$widget" 'const-string/jumbo v1, "toggleDarkMode"'
  assert_contains "$widget" 'const v0, 0x7f120d5a'
  assert_contains "$widget" 'new-instance v1, Lcom/android/settings/notificationcustom/QuickWidget;'
  assert_contains "$widget" 'Lcom/android/settings/notificationcustom/QuickWidget;-><init>(Ljava/lang/String;Ljava/lang/String;I)V'

  assert_contains "$custom_view" '.method private static containsWidget(Ljava/lang/String;Ljava/lang/String;)Z'
  assert_contains "$custom_view" '.method private static appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
  assert_contains "$custom_view" 'const-string v0, "toggleDarkMode"'
  assert_contains "$custom_view" 'invoke-static {p0}, Lcom/android/settings/widget/NotificationCustomView;->getCurrentQuickWidgetSettings(Landroid/content/Context;)Ljava/lang/String;'
  assert_contains "$custom_view" 'invoke-static {v1, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
  assert_contains "$custom_view" 'invoke-static {v0}, Lsmartisanos/util/SettingsUtil;->getDefaultNotificationWidgets(Landroid/content/Context;)Ljava/lang/String;'
  assert_contains "$custom_view" 'invoke-static {v0, v1}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
  assert_contains "$custom_view" 'invoke-static {v3, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
  assert_contains "$custom_view" 'invoke-static {p1, p2}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
}

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-v0.11-native-darkmode-tile-apks.sh

Read-only offline verifier for v0.11 native dark-mode integration APK
candidates. It does not build images, modify ROM files, or touch the device.
It decodes the candidate APKs to temporary smali, copies only four evidence
files plus NotificationCustomView evidence into hard-rom/inspect, and verifies
concrete method/class call sites.
USAGE
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

need_file "$STOCK_SYSTEMUI_APK"
need_file "$STOCK_SETTINGS_APK"
need_file "$OUT_SYSTEMUI"
need_file "$OUT_SETTINGS"
need_file "$SYSTEMUI_SIG"
need_file "$SETTINGS_SIG"
need_file "$APKTOOL"
need_executable "$JAVA_BIN"

mkdir -p "$INSPECT_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
report="${INSPECT_DIR}/verify-v0.11-native-darkmode-tile-apks-${timestamp}.txt"
evidence_dir="${INSPECT_DIR}/smali-evidence-${timestamp}"
decode_tmp="$(mktemp -d "/tmp/r2-v0.11-smali.XXXXXX")"
trap 'rm -rf "$decode_tmp"' EXIT
mkdir -p "$evidence_dir"

{
  echo "# v0.11 native dark-mode tile APK offline verification"
  echo "timestamp=${timestamp}"
  echo

  echo "## sha256"
  shasum -a 256 "$OUT_SYSTEMUI" "$OUT_SETTINGS" "$STOCK_SYSTEMUI_APK" "$STOCK_SETTINGS_APK"
  echo

  echo "## zip integrity"
  unzip -t "$OUT_SYSTEMUI" | tail -n 3
  unzip -t "$OUT_SETTINGS" | tail -n 3
  echo

  echo "## dex changes"
  assert_changed_dexes SmartisanSystemUI "$STOCK_SYSTEMUI_APK" "$OUT_SYSTEMUI" classes10.dex
  echo "SmartisanSystemUI: only classes10.dex changed"
  assert_changed_dexes SettingsSmartisan "$STOCK_SETTINGS_APK" "$OUT_SETTINGS" classes.dex classes2.dex
  echo "SettingsSmartisan: only classes.dex and classes2.dex changed"
  echo

  echo "## patched strings"
  assert_strings "$OUT_SYSTEMUI" classes10.dex \
    toggleDarkMode DarkModeTile setNightModeActivated quick_settings_night_display_label \
    com.android.settings.BrightnessSettingsActivity
  echo "SmartisanSystemUI: patched strings present"
  assert_strings "$OUT_SETTINGS" classes.dex \
    toggleDarkMode night_mode_yes setNightModeActivated getNightMode uimode \
    BrightnessSettingsFragment QuickWidgetFactory
  assert_strings "$OUT_SETTINGS" classes2.dex \
    toggleDarkMode appendDarkModeCandidate containsWidget expanded_widget_buttons_additional \
    NotificationCustomView
  echo "SettingsSmartisan: patched settings UI, widget renderer, and candidate-injection strings present"
  echo

  echo "## smali semantics"
  decode_and_collect_smali "$evidence_dir" "$decode_tmp"
  assert_smali_semantics "$evidence_dir"
  echo "smali_evidence=${evidence_dir}"
  echo "SystemUI: DarkModeTile and QSTileHost toggleDarkMode branch verified"
  echo "SettingsSmartisan: BrightnessSettingsFragment, QuickWidgetFactory, and NotificationCustomView dark-mode call sites verified"
  echo

  echo "## signature boundary"
  grep -q 'SHA-256 digest error for classes10.dex' "$SYSTEMUI_SIG" \
    || die "SystemUI signature report missing classes10.dex digest boundary"
  grep -q 'SHA-256 digest error for classes.dex' "$SETTINGS_SIG" \
    || die "Settings signature report missing classes.dex digest boundary"
  sed -n '1,28p' "$SYSTEMUI_SIG"
  echo
  sed -n '1,28p' "$SETTINGS_SIG"
  echo

  echo "PASS"
} | tee "$report"

echo "Report: ${report}"
