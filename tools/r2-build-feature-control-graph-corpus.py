#!/usr/bin/env python3
"""Build a focused graphify corpus for user-facing system controls.

This corpus is for modifications such as:

- exposing real system light/dark mode
- restricting system language choices
- wiring Settings/SystemUI entries to existing framework services

It intentionally avoids the full ROM reverse tree. The output is small enough
to query repeatedly while still including the framework, Settings, SystemUI,
overlay, permission, and resource files that decide these features.
"""

from __future__ import annotations

import csv
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
JADX = STATIC / "jadx"
RAW = STATIC / "raw"
OUT = STATIC / "graph-corpus" / "feature-control"
GRAPH_INPUT = OUT / "graph-input"


FRAMEWORK = JADX / "system__system__framework__framework.jar" / "sources"
SERVICES = JADX / "system__system__framework__services.jar" / "sources"
FRAMEWORK_RES = JADX / "system__system__framework__framework-res.apk"
SETTINGS = JADX / "system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk"
SETTINGS_PROVIDER = JADX / "system__system__priv-app__SettingsProvider__SettingsProvider.apk"
SYSTEMUI = JADX / "system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk"

ANDROID_OVERLAYS = {
    "FrameworksResCommon": JADX / "product__overlay__FrameworksResCommon.apk",
    "FrameworksResCommonQva": JADX / "product__overlay__FrameworksResCommonQva.apk",
    "FrameworksResTarget": JADX / "vendor__overlay__FrameworksResTarget.apk",
}

SYSTEMUI_OVERLAYS = {
    "SystemUIResCommon": JADX / "product__overlay__SystemUIResCommon.apk",
}


FRAMEWORK_FILES = [
    "android/app/ActivityManager.java",
    "android/app/ActivityTaskManager.java",
    "android/app/ActivityThread.java",
    "android/app/IActivityManager.java",
    "android/app/ITntResourcesManager.java",
    "android/app/IUiModeManager.java",
    "android/app/ResourcesManager.java",
    "android/app/ResourcesManagerSmtEx.java",
    "android/app/UiModeManager.java",
    "android/content/Context.java",
    "android/content/res/ApkAssets.java",
    "android/content/res/AssetManager.java",
    "android/content/res/AssetManagerSmtEx.java",
    "android/content/res/Configuration.java",
    "android/content/res/Resources.java",
    "android/content/res/ResourcesImpl.java",
    "android/content/res/ResourcesImplSmtEx.java",
    "android/os/LocaleList.java",
    "android/provider/Settings.java",
    "com/android/internal/app/LocaleHelper.java",
    "com/android/internal/app/LocalePicker.java",
    "com/android/internal/app/LocalePickerWithRegion.java",
    "com/android/internal/app/LocaleStore.java",
    "com/android/internal/app/SuggestedLocaleAdapter.java",
]

SERVICES_FILES = [
    "com/android/server/SystemServer.java",
    "com/android/server/UiModeManagerInternal.java",
    "com/android/server/UiModeManagerService.java",
    "com/android/server/display/color/ColorDisplayService.java",
    "com/android/server/twilight/TwilightListener.java",
    "com/android/server/twilight/TwilightManager.java",
    "com/android/server/twilight/TwilightService.java",
    "com/android/server/twilight/TwilightState.java",
    "com/android/server/wm/ActivityTaskManagerService.java",
    "com/android/server/wm/RootWindowContainer.java",
]

FRAMEWORK_RESOURCE_FILES = [
    "resources/AndroidManifest.xml",
    "resources/res/layout/locale_picker_item.xml",
    "resources/res/values/arrays.xml",
    "resources/res/values/bools.xml",
    "resources/res/values/integers.xml",
    "resources/res/values/public.xml",
    "resources/res/values/strings.xml",
    "resources/res/values/styles.xml",
]

SETTINGS_RESOURCE_FILES = [
    "resources/AndroidManifest.xml",
    "resources/res/layout/display.xml",
    "resources/res/layout/inputmethod_language_settings_layout.xml",
    "resources/res/layout/locale_drag_cell.xml",
    "resources/res/layout/locale_order_list.xml",
    "resources/res/layout/locale_picker_layout.xml",
    "resources/res/menu/language_selection_list.xml",
    "resources/res/values/arrays.xml",
    "resources/res/values/bools.xml",
    "resources/res/values/colors.xml",
    "resources/res/values/public.xml",
    "resources/res/values/strings.xml",
    "resources/res/values/styles.xml",
    "resources/res/values-night/styles.xml",
    "resources/res/xml/language_settings.xml",
    "resources/res/xml/searchable.xml",
]

SETTINGS_SOURCE_PATTERNS = [
    "sources/com/android/settings/DisplaySettings.java",
    "sources/com/android/settings/FingerprintHelper.java",
    "sources/com/android/settings/LandscapeSettings.java",
    "sources/com/android/settings/MainSettingsFragment.java",
    "sources/com/android/settings/NavbarModeFragment.java",
    "sources/com/android/settings/Settings.java",
    "sources/com/android/settings/SettingsActivity.java",
    "sources/com/android/settings/StepBackUtils.java",
    "sources/com/android/settings/display/**/*.java",
    "sources/com/android/settings/eyesprotection/**/*.java",
    "sources/com/android/settings/inputmethod/InputMethodAndLanguageSettings*.java",
    "sources/com/android/settings/inputmethod/LocalePickerFragment.java",
    "sources/com/android/settings/localepicker/**/*.java",
    "sources/com/android/settings/search/**/*.java",
    "sources/com/android/settings/settingitemsprovider/**/*.java",
]

SETTINGS_PROVIDER_RESOURCE_FILES = [
    "resources/AndroidManifest.xml",
    "resources/res/values/bools.xml",
    "resources/res/values/integers.xml",
    "resources/res/values/public.xml",
    "resources/res/values/strings.xml",
]

SETTINGS_PROVIDER_SOURCE_PATTERNS = [
    "sources/com/android/providers/settings/DatabaseHelper.java",
    "sources/com/android/providers/settings/SettingsProvider.java",
]

SYSTEMUI_RESOURCE_FILES = [
    "resources/AndroidManifest.xml",
    "resources/res/values/arrays.xml",
    "resources/res/values/bools.xml",
    "resources/res/values/colors.xml",
    "resources/res/values/public.xml",
    "resources/res/values/strings.xml",
    "resources/res/values/styles.xml",
]

SYSTEMUI_SOURCE_PATTERNS = [
    "sources/com/android/systemui/Dependency.java",
    "sources/com/android/systemui/SystemUIFactory.java",
    "sources/com/android/systemui/dagger/DependencyProvider*.java",
    "sources/com/android/systemui/qs/*.java",
    "sources/com/android/systemui/qs/customize/**/*.java",
    "sources/com/android/systemui/qs/external/**/*.java",
    "sources/com/android/systemui/qs/tiles/*.java",
    "sources/com/android/systemui/statusbar/phone/AutoTileManager.java",
    "sources/com/android/systemui/statusbar/phone/PhoneStatusBar.java",
    "sources/com/android/systemui/statusbar/phone/QSTileHost.java",
    "sources/com/android/systemui/statusbar/phone/QuickStatusBarHeader.java",
    "sources/com/android/systemui/statusbar/policy/**/*.java",
    "sources/com/android/systemui/util/SettingsUtil.java",
    "sources/com/android/systemui/util/SmartisanApi.java",
]

RAW_CONFIG_DIRS = [
    RAW / "system" / "system" / "etc" / "permissions",
    RAW / "system" / "system" / "etc" / "sysconfig",
    RAW / "system_ext" / "etc" / "permissions",
    RAW / "system_ext" / "etc" / "sysconfig",
    RAW / "product" / "etc" / "permissions",
    RAW / "product" / "etc" / "sysconfig",
    RAW / "vendor" / "etc" / "permissions",
    RAW / "vendor" / "etc" / "sysconfig",
]

INDEX_FILES = [
    "indexes/summary.md",
    "indexes/knowledge-map.md",
    "indexes/classes.tsv",
    "indexes/packages.tsv",
    "indexes/components.tsv",
    "indexes/intent-filters.tsv",
    "indexes/uses-permissions.tsv",
    "indexes/privapp-permissions.tsv",
    "indexes/sysconfig-packages.tsv",
    "indexes/permission-config.tsv",
    "indexes/overlays.tsv",
    "indexes/resources-overlayable.tsv",
    "indexes/resources-public.tsv",
    "indexes/signatures.tsv",
    "modification-confidence-map.md",
]


def copy_file(src: Path, dst: Path, rows: list[list[str]], group: str) -> None:
    if not src.is_file():
        rows.append([group, "missing", str(src), ""])
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    rows.append([group, "file", str(src), str(dst.relative_to(OUT))])


def copy_optional_file(src: Path, dst: Path, rows: list[list[str]], group: str) -> None:
    if src.is_file():
        copy_file(src, dst, rows, group)


def copy_tree(src: Path, dst: Path, rows: list[list[str]], group: str) -> None:
    if not src.is_dir():
        rows.append([group, "missing", str(src), ""])
        return
    for path in sorted(src.rglob("*")):
        if path.is_file():
            copy_file(path, dst / path.relative_to(src), rows, group)


def copy_globs(base: Path, patterns: list[str], dst_base: Path, rows: list[list[str]], group: str) -> None:
    seen: set[Path] = set()
    for pattern in patterns:
        for path in sorted(base.glob(pattern)):
            if not path.is_file() or path in seen:
                continue
            seen.add(path)
            copy_file(path, dst_base / path.relative_to(base), rows, group)


def write_readme(rows: list[list[str]]) -> None:
    copied = sum(1 for row in rows if row[1] == "file")
    missing = sum(1 for row in rows if row[1] == "missing")
    content = f"""# Smartisan OS 8.5.3 Feature-Control Graph Corpus

Generated from `reverse/smartisan-8.5.3-rom-static`.

Purpose: make system-control modifications queryable before building ROM
variants. This corpus focuses on the code and resources behind:

- Android day/night mode (`UiModeManagerService`, framework resources,
  Settings/SystemUI privileges and entry points)
- system language selection (`LocalePickerFragment`, `LocaleListEditor`,
  framework `LocalePicker`/`LocaleStore`, framework assets/locales)
- static overlays targeting `android`
- SystemUI quick setting defaults and SettingsProvider seeded system settings
- permissions and sysconfig grants used by Settings/SystemUI

```text
copied files: {copied}
missing expected files: {missing}
source boundary: static ROM JADX/raw config only
excluded: full APK binaries, live /data/app, generated super/system images
```

Important working notes:

```text
dark mode:
  The framework service exists and persists Settings.Secure.ui_night_mode.
  The main questions are entry point, permission, config_lockDayNightMode,
  and Smartisan QS tile wiring through SettingsProvider/SystemUI.

language trimming:
  AOSP LocaleListEditor uses framework supported_locales.
  Smartisan LocalePickerFragment also enumerates Resources.getSystem().getAssets().getLocales().
  A robust ROM change must account for both paths.
```

Generated manifest:

```text
corpus-manifest.tsv
```
"""
    (OUT / "README.md").write_text(content, encoding="utf-8")


def main() -> None:
    if not STATIC.is_dir():
        raise SystemExit(f"missing static knowledge base: {STATIC}")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    GRAPH_INPUT.mkdir(parents=True)

    rows: list[list[str]] = []

    for rel in FRAMEWORK_FILES:
        copy_file(FRAMEWORK / rel, GRAPH_INPUT / "java" / "framework.jar" / rel, rows, "framework")
    for rel in SERVICES_FILES:
        copy_file(SERVICES / rel, GRAPH_INPUT / "java" / "services.jar" / rel, rows, "services")

    for rel in FRAMEWORK_RESOURCE_FILES:
        copy_optional_file(FRAMEWORK_RES / rel, GRAPH_INPUT / "resources" / "framework-res.apk" / rel, rows, "framework-res")

    for overlay_name, overlay_dir in ANDROID_OVERLAYS.items():
        for rel in FRAMEWORK_RESOURCE_FILES:
            copy_optional_file(overlay_dir / rel, GRAPH_INPUT / "resources" / "overlays" / overlay_name / rel, rows, f"overlay:{overlay_name}")

    for rel in SETTINGS_RESOURCE_FILES:
        copy_optional_file(SETTINGS / rel, GRAPH_INPUT / "apps" / "SettingsSmartisan" / rel, rows, "app:SettingsSmartisan")
    copy_globs(SETTINGS, SETTINGS_SOURCE_PATTERNS, GRAPH_INPUT / "apps" / "SettingsSmartisan", rows, "app:SettingsSmartisan")

    for rel in SETTINGS_PROVIDER_RESOURCE_FILES:
        copy_optional_file(SETTINGS_PROVIDER / rel, GRAPH_INPUT / "apps" / "SettingsProvider" / rel, rows, "app:SettingsProvider")
    copy_globs(SETTINGS_PROVIDER, SETTINGS_PROVIDER_SOURCE_PATTERNS, GRAPH_INPUT / "apps" / "SettingsProvider", rows, "app:SettingsProvider")

    for rel in SYSTEMUI_RESOURCE_FILES:
        copy_optional_file(SYSTEMUI / rel, GRAPH_INPUT / "apps" / "SmartisanSystemUI" / rel, rows, "app:SmartisanSystemUI")
    copy_globs(SYSTEMUI, SYSTEMUI_SOURCE_PATTERNS, GRAPH_INPUT / "apps" / "SmartisanSystemUI", rows, "app:SmartisanSystemUI")

    for overlay_name, overlay_dir in SYSTEMUI_OVERLAYS.items():
        for rel in SYSTEMUI_RESOURCE_FILES:
            copy_optional_file(overlay_dir / rel, GRAPH_INPUT / "resources" / "overlays" / overlay_name / rel, rows, f"overlay:{overlay_name}")

    for src in RAW_CONFIG_DIRS:
        if src.is_dir():
            copy_tree(src, GRAPH_INPUT / "configs" / src.relative_to(RAW), rows, "configs")

    for rel in INDEX_FILES:
        src = STATIC / rel
        dst_root = OUT / "notes" if src.suffix == ".md" else GRAPH_INPUT / "knowledge-base"
        copy_optional_file(src, dst_root / rel, rows, "indexes")

    with (OUT / "corpus-manifest.tsv").open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow(["group", "status", "source", "corpus_path"])
        writer.writerows(rows)

    write_readme(rows)
    copied = sum(1 for row in rows if row[1] == "file")
    missing = sum(1 for row in rows if row[1] == "missing")
    print(f"corpus: {OUT}")
    print(f"copied files: {copied}")
    print(f"missing expected files: {missing}")


if __name__ == "__main__":
    main()
