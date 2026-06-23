#!/usr/bin/env python3
"""Build a focused graphify corpus for high-confidence Smartisan ROM edits.

The corpus is intentionally smaller than the full ROM static JADX tree. It
collects files that decide whether a hard-ROM modification is likely to boot:
package parsing/state, resources/assets, overlays, permissions, install flows,
keyguard policy, and high-risk app manifests/resources.
"""

from __future__ import annotations

import csv
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
JADX = STATIC / "jadx"
RAW = STATIC / "raw"
OUT = STATIC / "graph-corpus" / "modification-critical"
GRAPH_INPUT = OUT / "graph-input"


FRAMEWORK = JADX / "system__system__framework__framework.jar" / "sources"
SERVICES = JADX / "system__system__framework__services.jar" / "sources"


FRAMEWORK_FILES = [
    "android/app/ActivityThread.java",
    "android/app/ApplicationPackageManager.java",
    "android/app/LoadedApk.java",
    "android/app/ResourcesManager.java",
    "android/app/ResourcesManagerSmtEx.java",
    "android/content/Context.java",
    "android/app/ContextImpl.java",
    "android/content/pm/ApplicationInfo.java",
    "android/content/pm/ApplicationInfoSmtEx.java",
    "android/content/pm/IPackageManager.java",
    "android/content/pm/IPackageManagerSmtEx.java",
    "android/content/pm/PackageInfo.java",
    "android/content/pm/PackageInfoLite.java",
    "android/content/pm/PackageInstaller.java",
    "android/content/pm/PackageItemInfo.java",
    "android/content/pm/PackageManager.java",
    "android/content/pm/PackageManagerSmtEx.java",
    "android/content/pm/PackageParser.java",
    "android/content/pm/PackageParserSmtBase.java",
    "android/content/pm/PackageParserSmtEx.java",
    "android/content/pm/PackagePartitions.java",
    "android/content/pm/PackageUserState.java",
    "android/content/pm/PackageUserStateSmtEx.java",
    "android/content/pm/Signature.java",
    "android/content/pm/parsing/ParsingPackage.java",
    "android/content/pm/parsing/ParsingPackageImpl.java",
    "android/content/pm/parsing/ParsingPackageUtils.java",
    "android/content/pm/split/DefaultSplitAssetLoader.java",
    "android/content/pm/split/SplitAssetDependencyLoader.java",
    "android/content/pm/split/SplitAssetLoader.java",
    "android/content/res/ApkAssets.java",
    "android/content/res/AssetManager.java",
    "android/content/res/AssetManagerSmtEx.java",
    "android/content/res/IIconManager.java",
    "android/content/res/IconManager.java",
    "android/content/res/Resources.java",
    "android/content/res/ResourcesImpl.java",
    "android/content/res/ResourcesImplSmtEx.java",
    "android/content/res/ResourcesKey.java",
    "android/content/res/ResourcesSmtEx.java",
    "android/content/res/ResourcesSmto.java",
    "android/webkit/UserPackage.java",
    "android/webkit/WebViewFactory.java",
    "android/webkit/WebViewProviderInfo.java",
    "android/os/ISystemConfig.java",
    "android/os/SystemConfigManager.java",
    "com/android/server/SystemConfig.java",
]

FRAMEWORK_DIRS = [
    "android/content/om",
    "android/content/pm/permission",
    "android/permission",
    "android/content/res/loader",
]

SERVICES_DIRS = [
    "com/android/server/om",
    "com/android/server/pm/permission",
    "com/android/server/policy/keyguard",
    "com/android/server/pm",
    "com/android/server/webkit",
]

SERVICES_FILES = [
    "com/android/server/SystemServer.java",
    "com/android/server/policy/PhoneWindowManager.java",
    "com/android/server/policy/PhoneWindowManagerSmtEx.java",
    "com/android/server/wm/ActivityRecord.java",
    "com/android/server/wm/ActivityRecordSmtEx.java",
    "com/android/server/wm/ActivityStack.java",
    "com/android/server/wm/ActivityStackSmtEx.java",
    "com/android/server/wm/ActivityStartController.java",
    "com/android/server/wm/ActivityStarter.java",
    "com/android/server/wm/ActivityStarterSmtEx.java",
    "com/android/server/wm/ActivityTaskManagerService.java",
    "com/android/server/wm/ActivityTaskManagerServiceSmtEx.java",
    "com/android/server/wm/DisplayPolicy.java",
    "com/android/server/wm/DisplayPolicySmtEx.java",
    "com/android/server/wm/WindowManagerService.java",
    "com/android/server/wm/WindowManagerServiceSmtEx.java",
]

APP_DIRS = {
    "BrowserChrome": JADX / "system__system__app__BrowserChrome__BrowserChrome.apk",
    "KeyguardSmartisan": JADX / "system__system__priv-app__KeyguardSmartisan__KeyguardSmartisan.apk",
    "LauncherSmartisanNew": JADX / "system__system__priv-app__LauncherSmartisanNew__LauncherSmartisanNew.apk",
    "PackageInstallerSmartisan": JADX / "system__system__priv-app__PackageInstallerSmartisan__PackageInstallerSmartisan.apk",
    "PermissionController": JADX / "system__system__apex__com.android.permission__priv-app__PermissionController__PermissionController.apk",
    "PermissionControllerSmartisan": JADX / "system__system__priv-app__PermissionControllerSmartisan__PermissionControllerSmartisan.apk",
    "SettingsSmartisan": JADX / "system__system__priv-app__SettingsSmartisan__SettingsSmartisan.apk",
    "SmartisanSystemUI": JADX / "system_ext__priv-app__SmartisanSystemUI__SmartisanSystemUI.apk",
}

APP_RESOURCE_FILES = [
    "resources/AndroidManifest.xml",
    "resources/res/values/public.xml",
    "resources/res/values/arrays.xml",
    "resources/res/values/bools.xml",
    "resources/res/values/config.xml",
    "resources/res/values/strings.xml",
    "resources/res/xml/default_apps.xml",
    "resources/res/xml/launchershortcuts.xml",
    "resources/res/xml/searchable.xml",
]

APP_SOURCE_PATTERNS = {
    "KeyguardSmartisan": [
        "sources/com/smartisanos/keyguard/**/*.java",
        "sources/com/smartisanos/keyguard/*.java",
    ],
    "LauncherSmartisanNew": [
        "sources/com/smartisanos/launcher/provider/**/*.java",
        "sources/com/smartisanos/launcher/model/**/*.java",
        "sources/com/smartisanos/launcher/*.java",
    ],
    "PackageInstallerSmartisan": [
        "sources/com/android/packageinstaller/**/*.java",
    ],
    "PermissionController": [
        "sources/com/android/permissioncontroller/**/*.java",
    ],
    "PermissionControllerSmartisan": [
        "sources/com/android/permissioncontroller/**/*.java",
    ],
    "SettingsSmartisan": [
        "sources/com/android/settings/applications/**/*.java",
        "sources/com/android/settings/development/**/*.java",
        "sources/com/android/settings/localepicker/**/*.java",
        "sources/com/android/settings/notification/**/*.java",
        "sources/com/android/settings/Settings.java",
        "sources/com/android/settings/SettingsActivity.java",
    ],
    "SmartisanSystemUI": [
        "sources/com/android/systemui/statusbar/**/*.java",
        "sources/com/android/systemui/shared/**/*.java",
        "sources/com/android/systemui/util/**/*.java",
    ],
    "BrowserChrome": [
        "sources/org/chromium/chrome/browser/ChromeTabbedActivity.java",
        "sources/org/chromium/chrome/browser/document/ChromeLauncherActivity.java",
        "sources/org/chromium/chrome/browser/customtabs/**/*.java",
        "sources/org/chromium/chrome/browser/smartisan/**/*.java",
    ],
}

RAW_CONFIG_DIRS = [
    RAW / "system" / "system" / "etc" / "permissions",
    RAW / "system" / "system" / "etc" / "sysconfig",
    RAW / "product" / "etc" / "permissions",
    RAW / "product" / "etc" / "sysconfig",
    RAW / "vendor" / "etc" / "permissions",
    RAW / "vendor" / "etc" / "sysconfig",
]


def copy_file(src: Path, dst: Path, rows: list[list[str]], group: str) -> None:
    if not src.is_file():
        rows.append([group, "missing", str(src), ""])
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    rows.append([group, "file", str(src), str(dst.relative_to(OUT))])


def copy_optional_file(src: Path, dst: Path, rows: list[list[str]], group: str) -> None:
    if not src.is_file():
        return
    copy_file(src, dst, rows, group)


def copy_tree(src: Path, dst: Path, rows: list[list[str]], group: str) -> None:
    if not src.is_dir():
        rows.append([group, "missing", str(src), ""])
        return
    for path in sorted(src.rglob("*")):
        if path.is_file():
            rel = path.relative_to(src)
            copy_file(path, dst / rel, rows, group)


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
    content = f"""# Smartisan OS 8.5.3 Modification-Critical Graph Corpus

Generated from `reverse/smartisan-8.5.3-rom-static`.

Purpose: create a graphable, focused source set for hard-ROM modifications that
can affect boot, package scanning, resource loading, overlays, permissions,
install/uninstall flows, keyguard, launcher, SystemUI, Settings, and browser
default/app replacement behavior.

This is not a full ROM copy. It is a decision corpus for modification confidence.

```text
copied files: {copied}
missing expected files: {missing}
source boundary: static ROM JADX/raw config only
excluded: /data/app live updated-system APKs
```

Important groups:

```text
graph-input: code/config/index TSV files passed to graphify
framework: framework.jar package/resource/overlay/WebView client-side classes
services: services.jar PackageManager/OverlayManager/WebView/keyguard policy
apps: high-risk app manifests, resources, and selected source packages
configs: privapp/sysconfig/permissions XML used by package and permission policy
indexes: selected TSV indexes and build maps from the static knowledge base
notes: Markdown evidence kept out of graphify when no semantic LLM key exists
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
    for rel in FRAMEWORK_DIRS:
        copy_tree(FRAMEWORK / rel, GRAPH_INPUT / "java" / "framework.jar" / rel, rows, "framework")

    for rel in SERVICES_FILES:
        copy_file(SERVICES / rel, GRAPH_INPUT / "java" / "services.jar" / rel, rows, "services")
    for rel in SERVICES_DIRS:
        copy_tree(SERVICES / rel, GRAPH_INPUT / "java" / "services.jar" / rel, rows, "services")

    for app_name, app_dir in APP_DIRS.items():
        dst = GRAPH_INPUT / "apps" / app_name
        for rel in APP_RESOURCE_FILES:
            copy_optional_file(app_dir / rel, dst / rel, rows, f"app:{app_name}")
        copy_globs(app_dir, APP_SOURCE_PATTERNS.get(app_name, []), dst, rows, f"app:{app_name}")

    for src in RAW_CONFIG_DIRS:
        if src.is_dir():
            copy_tree(src, GRAPH_INPUT / "configs" / src.relative_to(RAW), rows, "configs")

    for rel in [
        "indexes/summary.md",
        "indexes/knowledge-map.md",
        "indexes/build-modification-map.md",
        "indexes/packages.tsv",
        "indexes/components.tsv",
        "indexes/intent-filters.tsv",
        "indexes/uses-permissions.tsv",
        "indexes/privapp-permissions.tsv",
        "indexes/sysconfig-packages.tsv",
        "indexes/permission-config.tsv",
        "indexes/overlays.tsv",
        "indexes/resources-public.tsv",
        "indexes/signatures.tsv",
        "review/qa-v1.1-answers.md",
        "review/qa-v1.1-hooke-score.md",
    ]:
        dst_root = OUT / "notes" if Path(rel).suffix == ".md" else GRAPH_INPUT / "knowledge-base"
        copy_file(STATIC / rel, dst_root / rel, rows, "indexes")

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
