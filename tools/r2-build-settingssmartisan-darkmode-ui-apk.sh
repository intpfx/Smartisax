#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
STOCK_SETTINGS_APK="${RAW}/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.8-darkmode-ui-apktool"
FRAMEWORK_DIR="${WORK_DIR}/framework"
DECODED_DIR="${WORK_DIR}/SettingsSmartisan"
REBUILT_UNSIGNED="${WORK_DIR}/SettingsSmartisan-darkmode-ui-rebuilt-unsigned.apk"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/SettingsSmartisan-darkmode-ui.apk"
SIG_REPORT="${OUT_DIR}/SettingsSmartisan-darkmode-ui.signature.txt"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-settingssmartisan-darkmode-ui-apk.sh

Build an offline SettingsSmartisan.apk behavior-patch candidate that exposes a
native dark-mode switch in BrightnessSettingsFragment.

This v0.8 candidate intentionally avoids resources.arsc changes. It reuses the
existing hidden switch_dc row on R2/darwin, retitles it with the existing
night_mode_yes string resource, and routes switch changes through:

  UiModeManager.setNightModeActivated(boolean)

The output APK is not a standalone installable app and is not flash-authorized.
It replaces classes.dex while keeping the stock APK shell. That intentionally
breaks ordinary JAR digest verification for classes.dex; it is only useful for
the Android system-partition certs-only experiment path and must not be flashed
until the v0.6 SettingsSmartisan no-op probe has passed live validation.
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

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

fixup_decoded_tree() {
  # apktool decodes this private enum attr as boolean. aapt2 rejects it when
  # rebuilding; the original activity still inherits a normal framework theme.
  perl -0pi -e 's/\s+androidprv:quickContactWindowSize="true"//g' \
    "${DECODED_DIR}/AndroidManifest.xml"
}

patch_brightness_dark_mode() {
  local smali="${DECODED_DIR}/smali/com/android/settings/BrightnessSettingsFragment.smali"
  need_file "$smali"

  perl -0pi -e '
    my $old = "    .line 522\n    invoke-virtual {p0}, Lcom/android/settings/BrightnessSettingsFragment;->getContentResolver()Landroid/content/ContentResolver;\n\n    move-result-object p1\n\n    const-string/jumbo v0, \"reduce_screen_strobe\"\n\n    invoke-static {p1, v0, p2}, Landroid/provider/Settings\$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z\n\n    .line 524\n    invoke-static {}, Lcom/android/settings/SettingsFeature;->isDarwin()Z\n\n    move-result p1\n\n    if-eqz p1, :cond_2\n\n    if-eqz p2, :cond_2\n\n    iget-object p0, p0, Lcom/android/settings/BrightnessSettingsFragment;->mContext:Landroid/content/Context;\n\n    invoke-static {p0}, Lcom/android/settings/utils/SettingsProviderUtils;->getSystemScreenBrightness(Landroid/content/Context;)F\n\n    move-result p0\n\n    const p1, 0x3e8ccccd    # 0.275f\n\n    cmpg-float p0, p0, p1\n\n    if-gtz p0, :cond_2\n\n    return-void\n\n    .line 528\n    :cond_2\n    invoke-static {p2}, Lcom/android/settings/Calibration;->setReduceScreenStrobeEnable(Z)V\n\n    goto :goto_0";
    my $new = "    .line 522\n    invoke-direct {p0, p2}, Lcom/android/settings/BrightnessSettingsFragment;->setDarkModeActivated(Z)V\n\n    goto :goto_0";
    s/\Q$old\E/$new/ or die "failed to replace reduce_screen_strobe handler\n";
  ' "$smali"

  perl -0pi -e '
    my $old = ".method private onReadModeChanged()V\n    .locals 3\n\n    .line 425\n    invoke-virtual {p0}, Lcom/android/settings/BrightnessSettingsFragment;->getContentResolver()Landroid/content/ContentResolver;\n\n    move-result-object v0\n\n    const/4 v1, 0x0\n\n    const-string/jumbo v2, \"read_mode_enable\"\n\n    invoke-static {v0, v2, v1}, Landroid/provider/Settings\$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I\n\n    move-result v0\n\n    const/4 v2, 0x1\n\n    if-ne v0, v2, :cond_0\n\n    move v1, v2\n\n    .line 426\n    :cond_0\n    iget-object p0, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReadModeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    invoke-virtual {p0, v1}, Lsmartisanos/widget/SettingItemSwitch;->setChecked(Z)V\n\n    return-void\n.end method\n\n.method private setBrightness(IZ)V";
    my $new = ".method private onReadModeChanged()V\n    .locals 3\n\n    .line 425\n    invoke-virtual {p0}, Lcom/android/settings/BrightnessSettingsFragment;->getContentResolver()Landroid/content/ContentResolver;\n\n    move-result-object v0\n\n    const/4 v1, 0x0\n\n    const-string/jumbo v2, \"read_mode_enable\"\n\n    invoke-static {v0, v2, v1}, Landroid/provider/Settings\$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I\n\n    move-result v0\n\n    const/4 v2, 0x1\n\n    if-ne v0, v2, :cond_0\n\n    move v1, v2\n\n    .line 426\n    :cond_0\n    iget-object p0, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReadModeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    invoke-virtual {p0, v1}, Lsmartisanos/widget/SettingItemSwitch;->setChecked(Z)V\n\n    return-void\n.end method\n\n.method private getUiModeManager()Landroid/app/UiModeManager;\n    .locals 1\n\n    const-string/jumbo v0, \"uimode\"\n\n    invoke-virtual {p0, v0}, Lcom/android/settings/BrightnessSettingsFragment;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;\n\n    move-result-object p0\n\n    check-cast p0, Landroid/app/UiModeManager;\n\n    return-object p0\n.end method\n\n.method private onDarkModeChanged()V\n    .locals 4\n\n    iget-object v0, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    if-eqz v0, :cond_1\n\n    invoke-direct {p0}, Lcom/android/settings/BrightnessSettingsFragment;->getUiModeManager()Landroid/app/UiModeManager;\n\n    move-result-object v1\n\n    if-eqz v1, :cond_1\n\n    invoke-virtual {v1}, Landroid/app/UiModeManager;->getNightMode()I\n\n    move-result v1\n\n    const/4 v2, 0x2\n\n    const/4 v3, 0x0\n\n    if-ne v1, v2, :cond_0\n\n    const/4 v3, 0x1\n\n    :cond_0\n    invoke-virtual {v0, v3}, Lsmartisanos/widget/SettingItemSwitch;->setChecked(Z)V\n\n    :cond_1\n    return-void\n.end method\n\n.method private setDarkModeActivated(Z)V\n    .locals 1\n\n    invoke-direct {p0}, Lcom/android/settings/BrightnessSettingsFragment;->getUiModeManager()Landroid/app/UiModeManager;\n\n    move-result-object p0\n\n    if-eqz p0, :cond_0\n\n    invoke-virtual {p0, p1}, Landroid/app/UiModeManager;->setNightModeActivated(Z)Z\n\n    :cond_0\n    return-void\n.end method\n\n.method private setBrightness(IZ)V";
    s/\Q$old\E/$new/ or die "failed to insert dark-mode helper methods\n";
  ' "$smali"

  perl -0pi -e '
    my $old = "    .line 223\n    :cond_5\n    invoke-static {}, Lcom/android/settings/SettingsFeature;->isSupportReadMode()Z";
    my $new = "    .line 223\n    :cond_5\n\n    .line 222\n    iget-object p1, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    const v0, 0x7f120d5a\n\n    invoke-virtual {p1, v0}, Lsmartisanos/widget/SettingItemSwitch;->setTitle(I)V\n\n    iget-object p1, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    invoke-virtual {p1, p3}, Lsmartisanos/widget/SettingItemSwitch;->setVisibility(I)V\n\n    iget-object p1, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitchTips:Lsmartisanos/widget/TipsView;\n\n    invoke-virtual {p1, v1}, Lsmartisanos/widget/TipsView;->setVisibility(I)V\n\n    iget-object p1, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    invoke-virtual {p1, p0}, Lsmartisanos/widget/SettingItemSwitch;->setOnCheckedChangeListener(Landroid/widget/CompoundButton\$OnCheckedChangeListener;)V\n\n    invoke-static {}, Lcom/android/settings/SettingsFeature;->isSupportReadMode()Z";
    s/\Q$old\E/$new/ or die "failed to expose dark-mode switch row\n";
  ' "$smali"

  perl -0pi -e '
    my $old = "    .line 285\n    invoke-static {}, Lcom/android/settings/SettingsFeature;->isSupportDC()Z\n\n    move-result v0\n\n    if-eqz v0, :cond_4\n\n    .line 286\n    iget-object v0, p0, Lcom/android/settings/BrightnessSettingsFragment;->mReduceStrobeSwitch:Lsmartisanos/widget/SettingItemSwitch;\n\n    invoke-virtual {p0}, Lcom/android/settings/BrightnessSettingsFragment;->getContentResolver()Landroid/content/ContentResolver;\n\n    move-result-object v1\n\n    const-string/jumbo v4, \"reduce_screen_strobe\"\n\n    invoke-static {v1, v4, v3}, Landroid/provider/Settings\$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I\n\n    move-result v1\n\n    if-eqz v1, :cond_3\n\n    const/4 v1, 0x1\n\n    goto :goto_1\n\n    :cond_3\n    move v1, v3\n\n    :goto_1\n    invoke-virtual {v0, v1}, Lsmartisanos/widget/SettingItemSwitch;->setChecked(Z)V\n\n    .line 289\n    :cond_4";
    my $new = "    .line 285\n    invoke-direct {p0}, Lcom/android/settings/BrightnessSettingsFragment;->onDarkModeChanged()V\n\n    .line 289\n    :cond_4";
    s/\Q$old\E/$new/ or die "failed to replace support-visible DC refresh\n";
  ' "$smali"

  grep -q 'Landroid/app/UiModeManager;->setNightModeActivated(Z)Z' "$smali" \
    || die "missing setNightModeActivated call"
  grep -q 'Landroid/app/UiModeManager;->getNightMode()I' "$smali" \
    || die "missing getNightMode call"
  grep -q 'const v0, 0x7f120d5a' "$smali" \
    || die "missing night_mode_yes title resource reference"
  ! grep -q 'const-string/jumbo v0, "reduce_screen_strobe"' "$smali" \
    || die "old reduce_screen_strobe handler remained"
}

merge_classes_into_stock_shell() {
  local tmp
  tmp="$(mktemp -d "/tmp/r2-settings-darkmode-ui-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$OUT_DIR"
  cp "$STOCK_SETTINGS_APK" "${OUT_APK}.tmp"
  unzip -p "$REBUILT_UNSIGNED" classes.dex > "${tmp}/classes.dex"
  (
    cd "$tmp"
    zip -q "${OUT_APK}.tmp" classes.dex
  )
  mv "${OUT_APK}.tmp" "$OUT_APK"

  local rebuilt_class_hash
  local out_class_hash
  rebuilt_class_hash="$(unzip -p "$REBUILT_UNSIGNED" classes.dex | shasum -a 256 | awk '{print $1}')"
  out_class_hash="$(unzip -p "$OUT_APK" classes.dex | shasum -a 256 | awk '{print $1}')"
  [ "$rebuilt_class_hash" = "$out_class_hash" ] || die "merged classes.dex hash mismatch"

  unzip -p "$OUT_APK" classes.dex | strings > "${tmp}/classes.strings"
  grep -q 'setNightModeActivated' "${tmp}/classes.strings" || die "missing setNightModeActivated constant"
  grep -q 'getNightMode' "${tmp}/classes.strings" || die "missing getNightMode constant"
  grep -q 'uimode' "${tmp}/classes.strings" || die "missing uimode service constant"
}

case "${1:-}" in
  "" )
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
need_file "$STOCK_SETTINGS_APK"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding SettingsSmartisan..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$DECODED_DIR" "$STOCK_SETTINGS_APK" >/dev/null

echo "Applying SettingsSmartisan rebuild fixups..."
fixup_decoded_tree

echo "Patching BrightnessSettingsFragment dark-mode switch..."
patch_brightness_dark_mode

echo "Rebuilding patched SettingsSmartisan as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$REBUILT_UNSIGNED" "$DECODED_DIR" >/dev/null

echo "Merging patched classes.dex into stock SettingsSmartisan shell..."
merge_classes_into_stock_shell

echo "Writing signature boundary report..."
"$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"

{
  echo "built_apk=${OUT_APK}"
  echo "rebuilt_unsigned=${REBUILT_UNSIGNED}"
  echo "signature_report=${SIG_REPORT}"
  shasum -a 256 "$OUT_APK" "$REBUILT_UNSIGNED" "$STOCK_SETTINGS_APK"
  echo
  sed -n '1,60p' "$SIG_REPORT"
} >&2

echo "$OUT_APK"
