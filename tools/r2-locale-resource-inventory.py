#!/usr/bin/env python3
"""Inventory locale resource qualifiers in decoded Smartisan ROM APKs."""

from __future__ import annotations

import argparse
import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
LOCALE_RE = re.compile(r"^(?P<lang>[a-z]{2})(?:-r(?P<region>[A-Z]{2}))?$")

KEEP_LOCALES = {"en", "en_US", "zh_CN", "zh_TW"}
DROP_LANGS = {"ja", "ko"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--jadx-root",
        default="reverse/smartisan-8.5.3-rom-static/jadx",
        help="Decoded ROM root containing <partition>__...apk directories.",
    )
    parser.add_argument(
        "--tsv",
        default="reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv",
        help="TSV output path.",
    )
    parser.add_argument(
        "--markdown",
        default="docs/research/locale-pruning-map.md",
        help="Markdown summary output path.",
    )
    return parser.parse_args()


def manifest_attr(root: ElementTree.Element, local_name: str) -> str:
    return root.attrib.get(local_name) or root.attrib.get(ANDROID_NS + local_name, "")


def parse_manifest(path: Path) -> dict[str, str]:
    manifest = path / "resources" / "AndroidManifest.xml"
    if not manifest.exists():
        return {}
    try:
        root = ElementTree.fromstring(manifest.read_text(encoding="utf-8"))
    except Exception:
        return {}

    overlay = root.find("overlay")
    return {
        "package": manifest_attr(root, "package"),
        "sharedUserId": manifest_attr(root, "sharedUserId"),
        "coreApp": manifest_attr(root, "coreApp"),
        "targetPackage": manifest_attr(overlay, "targetPackage") if overlay is not None else "",
        "isStaticOverlay": manifest_attr(overlay, "isStatic") if overlay is not None else "",
    }


def locale_from_values_dir(name: str) -> str | None:
    if name == "values":
        return None
    parts = name.removeprefix("values-").split("-")
    for i, part in enumerate(parts):
        if not re.fullmatch(r"[a-z]{2}", part):
            continue
        candidate = part
        if i + 1 < len(parts) and re.fullmatch(r"r[A-Z]{2}", parts[i + 1]):
            candidate = f"{part}_{parts[i + 1][1:]}"
        if LOCALE_RE.match(candidate.replace("_", "-r")):
            return candidate
    return None


def classify_risk(decoded_dir: Path, meta: dict[str, str]) -> str:
    name = decoded_dir.name
    package = meta.get("package", "")
    shared_uid = meta.get("sharedUserId", "")
    target = meta.get("targetPackage", "")
    core_app = meta.get("coreApp", "")

    if "framework__framework-res.apk" in name or package == "android":
        return "RED_FRAMEWORK_SYSTEM_ASSET"
    if "framework-smartisanos-res" in name:
        return "RED_SMARTISAN_FRAMEWORK_ASSET"
    if target == "android":
        return "AMBER_ANDROID_STATIC_OVERLAY"
    if core_app == "true":
        return "RED_CORE_APP"
    if shared_uid in {"android.uid.system", "android.uid.systemui", "android.uid.phone"}:
        return "RED_SHARED_UID"
    if shared_uid:
        return "AMBER_SHARED_UID"
    if "/priv-app/" in name or "__priv-app__" in name:
        return "AMBER_PRIV_APP"
    return "GREEN_OR_YELLOW_APP"


def decoded_apk_dirs(jadx_root: Path) -> list[Path]:
    return sorted(p for p in jadx_root.iterdir() if p.is_dir() and p.name.endswith(".apk"))


def collect_row(path: Path) -> dict[str, str | int]:
    res = path / "resources" / "res"
    value_dirs = sorted(p.name for p in res.glob("values*") if p.is_dir()) if res.exists() else []
    locales = sorted({loc for name in value_dirs if (loc := locale_from_values_dir(name))})
    drop_dirs = [name for name in value_dirs if (loc := locale_from_values_dir(name)) and loc.split("_", 1)[0] in DROP_LANGS]
    keep_dirs = [name for name in value_dirs if (loc := locale_from_values_dir(name)) and loc in KEEP_LOCALES]
    other_locale_dirs = [
        name
        for name in value_dirs
        if (loc := locale_from_values_dir(name)) and loc not in KEEP_LOCALES and loc.split("_", 1)[0] not in DROP_LANGS
    ]
    meta = parse_manifest(path)
    row: dict[str, str | int] = {
        "decoded_dir": path.name,
        "package": meta.get("package", ""),
        "sharedUserId": meta.get("sharedUserId", ""),
        "coreApp": meta.get("coreApp", ""),
        "targetPackage": meta.get("targetPackage", ""),
        "isStaticOverlay": meta.get("isStaticOverlay", ""),
        "risk": classify_risk(path, meta),
        "values_dirs": len(value_dirs),
        "locale_dirs": len([name for name in value_dirs if locale_from_values_dir(name)]),
        "keep_dirs": len(keep_dirs),
        "ja_ko_dirs": len(drop_dirs),
        "other_locale_dirs": len(other_locale_dirs),
        "locales": ",".join(locales),
        "ja_ko_values_dirs": ",".join(drop_dirs[:80]),
    }
    return row


def write_tsv(rows: list[dict[str, str | int]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "decoded_dir",
        "package",
        "sharedUserId",
        "coreApp",
        "targetPackage",
        "isStaticOverlay",
        "risk",
        "values_dirs",
        "locale_dirs",
        "keep_dirs",
        "ja_ko_dirs",
        "other_locale_dirs",
        "locales",
        "ja_ko_values_dirs",
    ]
    lines = ["\t".join(headers)]
    for row in rows:
        lines.append("\t".join(str(row.get(header, "")).replace("\t", " ") for header in headers))
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_markdown(rows: list[dict[str, str | int]], output: Path, tsv: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with_locale = [r for r in rows if int(r["locale_dirs"]) > 0]
    with_ja_ko = [r for r in rows if int(r["ja_ko_dirs"]) > 0]
    risk_counts = Counter(str(r["risk"]) for r in with_ja_ko)
    top = sorted(with_ja_ko, key=lambda r: (str(r["risk"]), -int(r["ja_ko_dirs"]), str(r["decoded_dir"])))[:40]

    lines = [
        "# Locale Pruning Map",
        "",
        "Date: 2026-06-18.",
        "",
        "This note is generated from decoded static ROM resources. It maps locale",
        "resource qualifiers for ROM-level language pruning research. It does not",
        "modify any image or device state.",
        "",
        "## Summary",
        "",
        f"- decoded APK/resource packages scanned: {len(rows)}",
        f"- packages with locale-qualified values dirs: {len(with_locale)}",
        f"- packages with Japanese/Korean resource dirs: {len(with_ja_ko)}",
        f"- TSV inventory: `{tsv}`",
        "",
        "Japanese/Korean hits by risk tier:",
        "",
    ]
    for risk, count in sorted(risk_counts.items()):
        lines.append(f"- {risk}: {count}")

    lines.extend(
        [
            "",
            "## Core Findings",
            "",
            "- Smartisan's main language picker uses",
            "  `Resources.getSystem().getAssets().getLocales()`, not only",
            "  `android.R.array.supported_locales`.",
            "- The system AssetManager is built from `framework-res.apk`,",
            "  `framework-smartisanos-res.apk`, and immutable static overlays",
            "  targeting `android`.",
            "- A product/vendor RRO can override arrays such as `supported_locales`,",
            "  but it cannot hide locale configurations already compiled into",
            "  framework resource APKs.",
            "- A true hard prune of visible Smartisan system locales therefore needs",
            "  either framework resource repacking, a framework/Settings code patch,",
            "  or an equivalent hook that filters `AssetManager.getLocales()`.",
            "",
            "## First High-Risk Targets",
            "",
            "| risk | ja/ko dirs | package | decoded dir |",
            "| --- | ---: | --- | --- |",
        ]
    )
    for row in top:
        lines.append(
            f"| {row['risk']} | {row['ja_ko_dirs']} | {row['package']} | `{row['decoded_dir']}` |"
        )

    lines.extend(
        [
            "",
            "## Practical Boundary",
            "",
            "Restricting the selectable language list is easier than physically removing",
            "all non-target translations from the ROM. Full ROM language slimming needs",
            "package-by-package signing and boot-risk handling, especially for core",
            "shared-UID packages.",
            "",
        ]
    )
    output.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    args = parse_args()
    jadx_root = Path(args.jadx_root)
    rows = [collect_row(path) for path in decoded_apk_dirs(jadx_root)]
    tsv = Path(args.tsv)
    write_tsv(rows, tsv)
    write_markdown(rows, Path(args.markdown), tsv)
    print(f"scanned={len(rows)}")
    print(f"tsv={tsv}")
    print(f"markdown={args.markdown}")


if __name__ == "__main__":
    main()
