#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"
STOCK_SYSTEMUI_APK="${RAW}/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
STOCK_SETTINGS_APK="${RAW}/system/system/priv-app/SettingsSmartisan/SettingsSmartisan.apk"

WORK_DIR="${ROOT_DIR}/hard-rom/work/v0.11-native-darkmode-tile-apktool"
FRAMEWORK_DIR="${WORK_DIR}/framework"
SYSTEMUI_DIR="${WORK_DIR}/SmartisanSystemUI"
SETTINGS_DIR="${WORK_DIR}/SettingsSmartisan"
SYSTEMUI_REBUILT="${WORK_DIR}/SmartisanSystemUI-darkmode-tile-rebuilt-unsigned.apk"
SETTINGS_REBUILT="${WORK_DIR}/SettingsSmartisan-darkmode-ui-widget-rebuilt-unsigned.apk"

OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_SYSTEMUI="${OUT_DIR}/SmartisanSystemUI-darkmode-tile.apk"
OUT_SETTINGS="${OUT_DIR}/SettingsSmartisan-darkmode-ui-widget.apk"
SYSTEMUI_SIG="${OUT_DIR}/SmartisanSystemUI-darkmode-tile.signature.txt"
SETTINGS_SIG="${OUT_DIR}/SettingsSmartisan-darkmode-ui-widget.signature.txt"
MANIFEST="${OUT_DIR}/native-darkmode-integration-apks.SHA256SUMS.txt"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-native-darkmode-tile-apks.sh

Build offline APK candidates for a native Smartisan quick-setting dark-mode
tile without generating a ROM image or touching the device.

Outputs:
  hard-rom/build/apk/SmartisanSystemUI-darkmode-tile.apk
    Adds com.android.systemui.qs.tiles.DarkModeTile and maps tile spec
    toggleDarkMode in QSTileHost.createTile().

  hard-rom/build/apk/SettingsSmartisan-darkmode-ui-widget.apk
    Exposes a native dark-mode row in BrightnessSettingsFragment and teaches
    the Smartisan quick-widget customization page to render and offer
    toggleDarkMode instead of returning null or hiding it from the additional
    candidate list.

The candidates are original-shell dex replacements. They are not standalone-
installable APKs and are not flash-authorized until the matching no-op core-APK
gates pass live validation.
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

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

install_frameworks() {
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$FRAMEWORK_DIR" "$FW_SMARTISAN" >/dev/null
}

fixup_settings_tree() {
  perl -0pi -e 's/\s+androidprv:quickContactWindowSize="true"//g' \
    "${SETTINGS_DIR}/AndroidManifest.xml"
}

patch_settings_darkmode_ui() {
  local smali="${SETTINGS_DIR}/smali/com/android/settings/BrightnessSettingsFragment.smali"
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
    || die "Settings dark-mode UI patch missing setNightModeActivated"
  grep -q 'Landroid/app/UiModeManager;->getNightMode()I' "$smali" \
    || die "Settings dark-mode UI patch missing getNightMode"
  grep -q 'const v0, 0x7f120d5a' "$smali" \
    || die "Settings dark-mode UI patch missing night_mode_yes title resource"
  ! grep -q 'const-string/jumbo v0, "reduce_screen_strobe"' "$smali" \
    || die "old reduce_screen_strobe handler remained"
}

write_darkmode_tile_smali() {
  local out="${SYSTEMUI_DIR}/smali_classes10/com/android/systemui/qs/tiles/DarkModeTile.smali"
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<'SMALI'
.class public Lcom/android/systemui/qs/tiles/DarkModeTile;
.super Lcom/android/systemui/qs/QSTile;
.source "DarkModeTile.java"


# annotations
.annotation system Ldalvik/annotation/Signature;
    value = {
        "Lcom/android/systemui/qs/QSTile<",
        "Lcom/android/systemui/qs/QSTile$BooleanState;",
        ">;"
    }
.end annotation


# instance fields
.field private final mDisable:Lcom/android/systemui/qs/QSTile$Icon;

.field private final mEnable:Lcom/android/systemui/qs/QSTile$Icon;

.field private mListening:Z


# direct methods
.method public constructor <init>(Lcom/android/systemui/qs/QSTile$Host;)V
    .locals 1
    .param p1, "host"    # Lcom/android/systemui/qs/QSTile$Host;

    invoke-direct {p0, p1}, Lcom/android/systemui/qs/QSTile;-><init>(Lcom/android/systemui/qs/QSTile$Host;)V

    sget v0, Lcom/android/systemui/R$drawable;->smartisan_qs_night_shift_on:I

    invoke-static {v0}, Lcom/android/systemui/qs/QSTile$ResourceIcon;->get(I)Lcom/android/systemui/qs/QSTile$Icon;

    move-result-object v0

    iput-object v0, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mEnable:Lcom/android/systemui/qs/QSTile$Icon;

    sget v0, Lcom/android/systemui/R$drawable;->smartisan_qs_night_shift_off:I

    invoke-static {v0}, Lcom/android/systemui/qs/QSTile$ResourceIcon;->get(I)Lcom/android/systemui/qs/QSTile$Icon;

    move-result-object v0

    iput-object v0, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mDisable:Lcom/android/systemui/qs/QSTile$Icon;

    return-void
.end method

.method private getUiModeManager()Landroid/app/UiModeManager;
    .locals 2

    iget-object v0, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mContext:Landroid/content/Context;

    const-string v1, "uimode"

    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/UiModeManager;

    return-object v0
.end method

.method private isDarkMode()Z
    .locals 2

    invoke-direct {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->getUiModeManager()Landroid/app/UiModeManager;

    move-result-object v0

    if-eqz v0, :cond_0

    invoke-virtual {v0}, Landroid/app/UiModeManager;->getNightMode()I

    move-result v0

    const/4 v1, 0x2

    if-ne v0, v1, :cond_0

    const/4 v0, 0x1

    return v0

    :cond_0
    const/4 v0, 0x0

    return v0
.end method

.method private setDarkModeActivated(Z)V
    .locals 2
    .param p1, "enabled"    # Z

    invoke-direct {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->getUiModeManager()Landroid/app/UiModeManager;

    move-result-object v0

    if-eqz v0, :cond_2

    invoke-virtual {v0, p1}, Landroid/app/UiModeManager;->setNightModeActivated(Z)Z

    move-result v1

    if-nez v1, :cond_2

    if-eqz p1, :cond_0

    const/4 v1, 0x2

    goto :goto_0

    :cond_0
    const/4 v1, 0x1

    :goto_0
    invoke-virtual {v0, v1}, Landroid/app/UiModeManager;->setNightMode(I)V

    :cond_2
    return-void
.end method


# virtual methods
.method protected composeChangeAnnouncement()Ljava/lang/String;
    .locals 2

    invoke-direct {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->isDarkMode()Z

    move-result v0

    iget-object v1, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mContext:Landroid/content/Context;

    if-eqz v0, :cond_0

    sget v0, Lcom/android/systemui/R$string;->quick_settings_night_display_summary_on:I

    goto :goto_0

    :cond_0
    sget v0, Lcom/android/systemui/R$string;->quick_settings_night_display_summary_off:I

    :goto_0
    invoke-virtual {v1, v0}, Landroid/content/Context;->getString(I)Ljava/lang/String;

    move-result-object v0

    return-object v0
.end method

.method public getLongClickIntent()Landroid/content/Intent;
    .locals 3

    new-instance v0, Landroid/content/Intent;

    invoke-direct {v0}, Landroid/content/Intent;-><init>()V

    const-string v1, "com.android.settings"

    const-string v2, "com.android.settings.BrightnessSettingsActivity"

    invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const-string v1, "android.intent.category.DEFAULT"

    invoke-virtual {v0, v1}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;

    const/high16 v1, 0x10000000

    invoke-virtual {v0, v1}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;

    return-object v0
.end method

.method public getMetricsCategory()I
    .locals 1

    const/16 v0, 0x70

    return v0
.end method

.method public getTileLabel()Ljava/lang/CharSequence;
    .locals 2

    iget-object v0, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mContext:Landroid/content/Context;

    sget v1, Lcom/android/systemui/R$string;->quick_settings_night_display_label:I

    invoke-virtual {v0, v1}, Landroid/content/Context;->getString(I)Ljava/lang/String;

    move-result-object v0

    return-object v0
.end method

.method public handleClick()V
    .locals 1

    invoke-direct {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->isDarkMode()Z

    move-result v0

    if-nez v0, :cond_0

    const/4 v0, 0x1

    goto :goto_0

    :cond_0
    const/4 v0, 0x0

    :goto_0
    invoke-direct {p0, v0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->setDarkModeActivated(Z)V

    invoke-virtual {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->refreshState()V

    return-void
.end method

.method protected handleUpdateState(Lcom/android/systemui/qs/QSTile$BooleanState;Ljava/lang/Object;)V
    .locals 3
    .param p1, "state"    # Lcom/android/systemui/qs/QSTile$BooleanState;
    .param p2, "arg"    # Ljava/lang/Object;

    invoke-direct {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->isDarkMode()Z

    move-result v0

    iput-boolean v0, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->value:Z

    invoke-virtual {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->getTileLabel()Ljava/lang/CharSequence;

    move-result-object v1

    iput-object v1, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->label:Ljava/lang/CharSequence;

    if-eqz v0, :cond_0

    iget-object v1, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mEnable:Lcom/android/systemui/qs/QSTile$Icon;

    goto :goto_0

    :cond_0
    iget-object v1, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mDisable:Lcom/android/systemui/qs/QSTile$Icon;

    :goto_0
    iput-object v1, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->icon:Lcom/android/systemui/qs/QSTile$Icon;

    iget-object v1, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->label:Ljava/lang/CharSequence;

    iput-object v1, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->contentDescription:Ljava/lang/CharSequence;

    const-class v2, Landroid/widget/Switch;

    invoke-virtual {v2}, Ljava/lang/Class;->getName()Ljava/lang/String;

    move-result-object v2

    iput-object v2, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->expandedAccessibilityClassName:Ljava/lang/String;

    iput-object v2, p1, Lcom/android/systemui/qs/QSTile$BooleanState;->minimalAccessibilityClassName:Ljava/lang/String;

    return-void
.end method

.method protected bridge synthetic handleUpdateState(Lcom/android/systemui/qs/QSTile$State;Ljava/lang/Object;)V
    .locals 0

    check-cast p1, Lcom/android/systemui/qs/QSTile$BooleanState;

    invoke-virtual {p0, p1, p2}, Lcom/android/systemui/qs/tiles/DarkModeTile;->handleUpdateState(Lcom/android/systemui/qs/QSTile$BooleanState;Ljava/lang/Object;)V

    return-void
.end method

.method public newTileState()Lcom/android/systemui/qs/QSTile$BooleanState;
    .locals 1

    new-instance v0, Lcom/android/systemui/qs/QSTile$BooleanState;

    invoke-direct {v0}, Lcom/android/systemui/qs/QSTile$BooleanState;-><init>()V

    return-object v0
.end method

.method public bridge synthetic newTileState()Lcom/android/systemui/qs/QSTile$State;
    .locals 1

    invoke-virtual {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->newTileState()Lcom/android/systemui/qs/QSTile$BooleanState;

    move-result-object v0

    return-object v0
.end method

.method public setListening(Z)V
    .locals 1
    .param p1, "listening"    # Z

    iget-boolean v0, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mListening:Z

    if-ne v0, p1, :cond_0

    return-void

    :cond_0
    iput-boolean p1, p0, Lcom/android/systemui/qs/tiles/DarkModeTile;->mListening:Z

    if-eqz p1, :cond_1

    invoke-virtual {p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;->refreshState()V

    :cond_1
    return-void
.end method
SMALI
}

patch_systemui() {
  local host="${SYSTEMUI_DIR}/smali_classes10/com/android/systemui/statusbar/phone/QSTileHost.smali"
  need_file "$host"

  write_darkmode_tile_smali

  perl -0pi -e '
    my $needle = "    .line 504\n    :cond_17\n    const-string v0, \"intent(\"\n";
    my $patch = "    .line 503\n    :cond_17\n    const-string v0, \"toggleDarkMode\"\n\n    invoke-virtual {p1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n    move-result v0\n\n    if-eqz v0, :cond_darkmode_continue\n\n    new-instance v0, Lcom/android/systemui/qs/tiles/DarkModeTile;\n\n    invoke-direct {v0, p0}, Lcom/android/systemui/qs/tiles/DarkModeTile;-><init>(Lcom/android/systemui/qs/QSTile\$Host;)V\n\n    return-object v0\n\n    .line 504\n    :cond_darkmode_continue\n    const-string v0, \"intent(\"\n";
    s/\Q$needle\E/$patch/ or die "failed to insert toggleDarkMode branch in QSTileHost\n";
  ' "$host"

  grep -q 'Lcom/android/systemui/qs/tiles/DarkModeTile;' "$host" \
    || die "QSTileHost patch did not reference DarkModeTile"
  grep -q 'setNightModeActivated' \
    "${SYSTEMUI_DIR}/smali_classes10/com/android/systemui/qs/tiles/DarkModeTile.smali" \
    || die "DarkModeTile missing setNightModeActivated"
}

patch_settings_widget() {
  local widget="${SETTINGS_DIR}/smali/com/android/settings/notificationcustom/QuickWidgetFactory.smali"
  need_file "$widget"

  perl -0pi -e '
    my $needle = "    :cond_27\n    const-string/jumbo v0, \"toggleRelay\"\n\n    .line 114\n";
    my $patch = "    :cond_27\n    const-string/jumbo v1, \"toggleDarkMode\"\n\n    invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n    move-result v1\n\n    if-eqz v1, :cond_darkmode_widget_continue\n\n    new-instance v1, Lcom/android/settings/notificationcustom/QuickWidget;\n\n    const v0, 0x7f120d5a\n\n    invoke-virtual {p0, v0}, Landroid/content/Context;->getString(I)Ljava/lang/String;\n\n    move-result-object p0\n\n    const v0, 0x7f0801fe\n\n    invoke-direct {v1, p1, p0, v0}, Lcom/android/settings/notificationcustom/QuickWidget;-><init>(Ljava/lang/String;Ljava/lang/String;I)V\n\n    goto :goto_10\n\n    :cond_darkmode_widget_continue\n    const-string/jumbo v0, \"toggleRelay\"\n\n    .line 114\n";
    s/\Q$needle\E/$patch/ or die "failed to insert toggleDarkMode branch in QuickWidgetFactory\n";
  ' "$widget"

  grep -q 'toggleDarkMode' "$widget" \
    || die "QuickWidgetFactory patch did not reference toggleDarkMode"
  grep -q '0x7f120d5a' "$widget" \
    || die "QuickWidgetFactory patch missing night_mode_yes title"
}

patch_settings_candidate_injection() {
  local view="${SETTINGS_DIR}/smali_classes2/com/android/settings/widget/NotificationCustomView.smali"
  need_file "$view"

  perl -0pi -e '
    my $needle = ".method private static isAdditionalOrderSupport()Z\n";
    my $patch = ".method private static containsWidget(Ljava/lang/String;Ljava/lang/String;)Z\n    .locals 3\n\n    invoke-static {p0}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z\n\n    move-result v0\n\n    if-nez v0, :cond_false\n\n    invoke-static {p1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z\n\n    move-result v0\n\n    if-nez v0, :cond_false\n\n    new-instance v0, Ljava/lang/StringBuilder;\n\n    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\n\n    const-string v1, \"|\"\n\n    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\n\n    move-result-object p0\n\n    new-instance v0, Ljava/lang/StringBuilder;\n\n    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\n\n    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\n\n    move-result-object p1\n\n    invoke-virtual {p0, p1}, Ljava/lang/String;->indexOf(Ljava/lang/String;)I\n\n    move-result p0\n\n    if-gez p0, :cond_true\n\n    :cond_false\n    const/4 p0, 0x0\n\n    return p0\n\n    :cond_true\n    const/4 p0, 0x1\n\n    return p0\n.end method\n\n.method private static appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\n    .locals 3\n\n    const-string v0, \"toggleDarkMode\"\n\n    invoke-static {p0, v0}, Lcom/android/settings/widget/NotificationCustomView;->containsWidget(Ljava/lang/String;Ljava/lang/String;)Z\n\n    move-result v1\n\n    if-nez v1, :cond_return\n\n    invoke-static {p1, v0}, Lcom/android/settings/widget/NotificationCustomView;->containsWidget(Ljava/lang/String;Ljava/lang/String;)Z\n\n    move-result v1\n\n    if-nez v1, :cond_return\n\n    invoke-static {p1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z\n\n    move-result v1\n\n    if-eqz v1, :cond_append\n\n    return-object v0\n\n    :cond_append\n    new-instance v1, Ljava/lang/StringBuilder;\n\n    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V\n\n    invoke-virtual {v1, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    const-string v2, \"|\"\n\n    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n\n    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\n\n    move-result-object p1\n\n    :cond_return\n    return-object p1\n.end method\n\n" . $needle;
    s/\Q$needle\E/$patch/ or die "failed to insert NotificationCustomView dark-mode candidate helpers\n";
  ' "$view"

  perl -0pi -e '
    my $old = "    :cond_1\n    return-object v0\n.end method\n\n.method public static getCurrentBostonQuickWidgetSettings(Landroid/content/Context;)Ljava/lang/String;";
    my $new = "    :cond_1\n    invoke-static {p0}, Lcom/android/settings/widget/NotificationCustomView;->getCurrentQuickWidgetSettings(Landroid/content/Context;)Ljava/lang/String;\n\n    move-result-object v1\n\n    invoke-static {v1, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\n\n    move-result-object v0\n\n    return-object v0\n.end method\n\n.method public static getCurrentBostonQuickWidgetSettings(Landroid/content/Context;)Ljava/lang/String;";
    s/\Q$old\E/$new/ or die "failed to patch current additional dark-mode fallback\n";
  ' "$view"

  perl -0pi -e '
    my $old = ".method private getDefaultAdditionalOrderSettings()Ljava/lang/String;\n    .locals 1";
    my $new = ".method private getDefaultAdditionalOrderSettings()Ljava/lang/String;\n    .locals 2";
    s/\Q$old\E/$new/ or die "failed to enlarge getDefaultAdditionalOrderSettings locals\n";
  ' "$view"

  perl -0pi -e '
    my $old = "    .line 280\n    :cond_1\n    iget-object p0, p0, Lcom/android/settings/widget/NotificationCustomView;->mDefaultAdditionalWidgets:Ljava/lang/String;";
    my $new = "    .line 280\n    :cond_1\n    sget-boolean v0, Lcom/android/settings/widget/NotificationCustomView;->isPCMode:Z\n\n    if-nez v0, :cond_darkmode_default_additional_done\n\n    iget-object v0, p0, Lcom/android/settings/widget/NotificationCustomView;->mContext:Landroid/content/Context;\n\n    invoke-static {v0}, Lsmartisanos/util/SettingsUtil;->getDefaultNotificationWidgets(Landroid/content/Context;)Ljava/lang/String;\n\n    move-result-object v0\n\n    iget-object v1, p0, Lcom/android/settings/widget/NotificationCustomView;->mDefaultAdditionalWidgets:Ljava/lang/String;\n\n    invoke-static {v0, v1}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\n\n    move-result-object v1\n\n    iput-object v1, p0, Lcom/android/settings/widget/NotificationCustomView;->mDefaultAdditionalWidgets:Ljava/lang/String;\n\n    :cond_darkmode_default_additional_done\n    iget-object p0, p0, Lcom/android/settings/widget/NotificationCustomView;->mDefaultAdditionalWidgets:Ljava/lang/String;";
    s/\Q$old\E/$new/ or die "failed to patch default additional dark-mode helper\n";
  ' "$view"

  perl -0pi -e '
    my $old = "    invoke-static {v0, v3}, Lsmartisanos/util/SettingsUtil;->getAdditionalNotificationWidgets(Landroid/content/Context;Ljava/lang/String;)Ljava/lang/String;\n\n    move-result-object v0\n\n    .line 404\n    :goto_2";
    my $new = "    invoke-static {v0, v3}, Lsmartisanos/util/SettingsUtil;->getAdditionalNotificationWidgets(Landroid/content/Context;Ljava/lang/String;)Ljava/lang/String;\n\n    move-result-object v0\n\n    invoke-static {v3, v0}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\n\n    move-result-object v0\n\n    .line 404\n    :goto_2";
    s/\Q$old\E/$new/ or die "failed to patch checkValidity dark-mode reset path\n";
  ' "$view"

  perl -0pi -e '
    my $old = "    :cond_1\n    const-string p0, \"expanded_widget_buttons\"\n\n    .line 373";
    my $new = "    :cond_1\n    invoke-static {p1, p2}, Lcom/android/settings/widget/NotificationCustomView;->appendDarkModeCandidate(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\n\n    move-result-object p2\n\n    const-string p0, \"expanded_widget_buttons\"\n\n    .line 373";
    s/\Q$old\E/$new/ or die "failed to patch saveWidgetButtonsAndNotify dark-mode additional path\n";
  ' "$view"

  grep -q 'appendDarkModeCandidate' "$view" \
    || die "NotificationCustomView patch missing appendDarkModeCandidate"
  grep -q 'containsWidget' "$view" \
    || die "NotificationCustomView patch missing containsWidget"
  grep -q 'toggleDarkMode' "$view" \
    || die "NotificationCustomView patch missing toggleDarkMode"
}

merge_dexes_into_stock_shell() {
  local stock="$1"
  local rebuilt="$2"
  local out="$3"
  shift 3

  local tmp
  tmp="$(mktemp -d "/tmp/r2-native-darkmode-merge.XXXXXX")"
  trap 'rm -rf "$tmp"' RETURN

  cp "$stock" "${out}.tmp"
  local dex_name
  for dex_name in "$@"; do
    unzip -p "$rebuilt" "$dex_name" > "${tmp}/${dex_name}"
    (
      cd "$tmp"
      zip -q "${out}.tmp" "$dex_name"
    )

    local rebuilt_hash
    local out_hash
    rebuilt_hash="$(unzip -p "$rebuilt" "$dex_name" | shasum -a 256 | awk '{print $1}')"
    out_hash="$(unzip -p "${out}.tmp" "$dex_name" | shasum -a 256 | awk '{print $1}')"
    [ "$rebuilt_hash" = "$out_hash" ] || die "merged ${dex_name} hash mismatch for ${out}"
  done
  mv "${out}.tmp" "$out"
}

verify_outputs() {
  unzip -p "$OUT_SYSTEMUI" classes10.dex | strings > "${WORK_DIR}/SmartisanSystemUI.classes10.strings"
  grep -q 'toggleDarkMode' "${WORK_DIR}/SmartisanSystemUI.classes10.strings" \
    || die "patched SystemUI dex missing toggleDarkMode"
  grep -q 'setNightModeActivated' "${WORK_DIR}/SmartisanSystemUI.classes10.strings" \
    || die "patched SystemUI dex missing setNightModeActivated"
  grep -q 'DarkModeTile' "${WORK_DIR}/SmartisanSystemUI.classes10.strings" \
    || die "patched SystemUI dex missing DarkModeTile"

  unzip -p "$OUT_SETTINGS" classes.dex | strings > "${WORK_DIR}/SettingsSmartisan.classes.strings"
  grep -q 'toggleDarkMode' "${WORK_DIR}/SettingsSmartisan.classes.strings" \
    || die "patched SettingsSmartisan dex missing toggleDarkMode"
  grep -q 'setNightModeActivated' "${WORK_DIR}/SettingsSmartisan.classes.strings" \
    || die "patched SettingsSmartisan dex missing setNightModeActivated"
  grep -q 'getNightMode' "${WORK_DIR}/SettingsSmartisan.classes.strings" \
    || die "patched SettingsSmartisan dex missing getNightMode"
  grep -q 'uimode' "${WORK_DIR}/SettingsSmartisan.classes.strings" \
    || die "patched SettingsSmartisan dex missing uimode service constant"

  unzip -p "$OUT_SETTINGS" classes2.dex | strings > "${WORK_DIR}/SettingsSmartisan.classes2.strings"
  grep -q 'toggleDarkMode' "${WORK_DIR}/SettingsSmartisan.classes2.strings" \
    || die "patched SettingsSmartisan classes2.dex missing toggleDarkMode"
  grep -q 'appendDarkModeCandidate' "${WORK_DIR}/SettingsSmartisan.classes2.strings" \
    || die "patched SettingsSmartisan classes2.dex missing appendDarkModeCandidate"
  grep -q 'expanded_widget_buttons_additional' "${WORK_DIR}/SettingsSmartisan.classes2.strings" \
    || die "patched SettingsSmartisan classes2.dex missing additional-widget setting"
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
need_file "$STOCK_SYSTEMUI_APK"
need_file "$STOCK_SETTINGS_APK"
need_executable "$JAVA_BIN"
need_executable "$SIGCHECK"
need_command zip
need_command unzip

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FRAMEWORK_DIR" "$OUT_DIR"
rm -f "$OUT_SYSTEMUI" "$OUT_SETTINGS" "$SYSTEMUI_SIG" "$SETTINGS_SIG" "$MANIFEST"

echo "Installing framework resources for apktool..."
install_frameworks

echo "Decoding SmartisanSystemUI..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$SYSTEMUI_DIR" "$STOCK_SYSTEMUI_APK" >/dev/null

echo "Patching SmartisanSystemUI native dark-mode tile..."
patch_systemui

echo "Rebuilding patched SmartisanSystemUI as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$SYSTEMUI_REBUILT" "$SYSTEMUI_DIR" >/dev/null

echo "Merging patched classes10.dex into stock SmartisanSystemUI shell..."
merge_dexes_into_stock_shell "$STOCK_SYSTEMUI_APK" "$SYSTEMUI_REBUILT" "$OUT_SYSTEMUI" classes10.dex

echo "Decoding SettingsSmartisan..."
"$JAVA_BIN" -jar "$APKTOOL" d -p "$FRAMEWORK_DIR" -f -o "$SETTINGS_DIR" "$STOCK_SETTINGS_APK" >/dev/null

echo "Applying SettingsSmartisan rebuild fixups..."
fixup_settings_tree

echo "Patching SettingsSmartisan dark-mode settings UI..."
patch_settings_darkmode_ui

echo "Patching SettingsSmartisan quick-widget renderer..."
patch_settings_widget

echo "Patching SettingsSmartisan quick-widget candidate injection..."
patch_settings_candidate_injection

echo "Rebuilding patched SettingsSmartisan as unsigned intermediate..."
"$JAVA_BIN" -jar "$APKTOOL" b -p "$FRAMEWORK_DIR" -o "$SETTINGS_REBUILT" "$SETTINGS_DIR" >/dev/null

echo "Merging patched classes.dex and classes2.dex into stock SettingsSmartisan shell..."
merge_dexes_into_stock_shell "$STOCK_SETTINGS_APK" "$SETTINGS_REBUILT" "$OUT_SETTINGS" classes.dex classes2.dex

echo "Verifying patched dex payloads..."
verify_outputs

echo "Writing signature boundary reports..."
"$SIGCHECK" "$OUT_SYSTEMUI" > "$SYSTEMUI_SIG"
"$SIGCHECK" "$OUT_SETTINGS" > "$SETTINGS_SIG"

{
  echo "variant=v0.11-native-darkmode-integration-apks"
  echo "systemui_apk=${OUT_SYSTEMUI}"
  echo "settings_apk=${OUT_SETTINGS}"
  echo "systemui_rebuilt_unsigned=${SYSTEMUI_REBUILT}"
  echo "settings_rebuilt_unsigned=${SETTINGS_REBUILT}"
  echo "systemui_signature_report=${SYSTEMUI_SIG}"
  echo "settings_signature_report=${SETTINGS_SIG}"
  echo "systemui_patch=QSTileHost toggleDarkMode + DarkModeTile"
  echo "settings_patch=BrightnessSettingsFragment dark-mode UI + QuickWidgetFactory renders toggleDarkMode + NotificationCustomView injects toggleDarkMode candidate"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_SYSTEMUI" "$OUT_SETTINGS" "$SYSTEMUI_REBUILT" "$SETTINGS_REBUILT" \
    "$STOCK_SYSTEMUI_APK" "$STOCK_SETTINGS_APK"
} > "$MANIFEST"

echo "Built: ${OUT_SYSTEMUI}"
echo "Built: ${OUT_SETTINGS}"
echo "Manifest: ${MANIFEST}"
