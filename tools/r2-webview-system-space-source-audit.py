#!/usr/bin/env python3
"""Audit system_b space-source options for a full-ABI WebView layout.

This is an offline/read-only planning gate. It does not build images, touch a
device, flash, reboot, erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEBUGFS = Path("/opt/homebrew/opt/e2fsprogs/sbin/debugfs")
SYSTEM_IMAGE = ROOT / "hard-rom" / "build" / "system-otatrust-v0.32-browserchrome-stock-near-noop.img"
CAPACITY_JSON = (
    ROOT
    / "hard-rom"
    / "inspect"
    / "browser-webview-route-a-image-capacity"
    / "webview-route-a-image-capacity-audit.json"
)
PACKAGES_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "indexes" / "packages.tsv"
COMPONENTS_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "indexes" / "components.tsv"
PERMISSIONS_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "indexes" / "uses-permissions.tsv"

OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-system-space-source"
OUT_JSON = OUT_DIR / "webview-system-space-source-audit.json"
OUT_MD = ROOT / "docs" / "research" / "webview-system-space-source-audit.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-system-space-source-audit.tsv"

RESERVE_BYTES = 8 * 1024 * 1024
RECOMMENDED_SOURCE_ID = "user_selected_no_projection_print_preserving"
PREFERRED_EXTRA_SOURCE_ID = "smartisan_wallpapers_resource_pack"

USER_SELECTED_PRINT_PRESERVING_PATHS = [
    "/system/app/SMTBugreport",
    "/system/app/CrashReport",
    "/system/app/SlardarOsClient",
    "/system/app/SMPushService",
    "/system/app/UnionPushProxy",
    "/system/app/TrackerSmartisan",
    "/system/priv-app/TeaTracker",
    "/system/app/BasicDreams",
    "/system/app/HTMLViewer",
    "/system/app/LiveWallpapersPicker",
    "/system/app/WallpaperBackup",
    "/system/app/Exchange2",
    "/system/app/Traceur",
    "/system/app/EasterEgg",
    "/system/app/Protips",
    "/system/app/CtsShimPrebuilt",
    "/system/priv-app/CtsShimPrivPrebuilt",
    "/system/priv-app/SmartisanShareManual",
]


@dataclass(frozen=True)
class FsStats:
    block_size: int
    free_blocks: int
    free_bytes: int


@dataclass(frozen=True)
class PathMeasure:
    path: str
    present: bool
    logical_bytes: int
    allocated_bytes: int
    files: int
    dirs: int
    package_names: str


@dataclass(frozen=True)
class SpaceSource:
    source_id: str
    status: str
    risk: str
    logical_bytes: int
    allocated_bytes: int
    margin_to_shortfall: int
    margin_to_reserved_target: int
    path_count: int
    package_names: str
    feature_tradeoff: str
    rationale: str
    next_gate: str


@dataclass(frozen=True)
class Gate:
    gate: str
    status: str
    evidence: str
    next_step: str


SPACE_SOURCES = [
    {
        "source_id": "projection_cast_stack",
        "risk": "RED_USER_PROTECTED_CORE_TNT",
        "paths": [
            "/system/app/BostonScreenMirror",
            "/system/priv-app/BostonCastHalService",
            "/system/app/SmartisanWirelessCast",
        ],
        "feature_tradeoff": "removes Smartisan/Boston wireless projection and cast surfaces",
        "rationale": "offline evidence links Boston/WirelessCast surfaces to TNT/wireless projection settings and components; the user marked this as a core feature",
        "next_gate": "Do not use this as a WebView space source unless the user explicitly reopens the TNT/projection feature boundary.",
    },
    {
        "source_id": "projection_plus_low_value_debug_reserve",
        "risk": "RED_USER_PROTECTED_CORE_TNT",
        "paths": [
            "/system/app/BostonScreenMirror",
            "/system/priv-app/BostonCastHalService",
            "/system/app/SmartisanWirelessCast",
            "/system/app/SMTBugreport",
            "/system/app/Traceur",
            "/system/app/EasterEgg",
            "/system/app/Protips",
            "/system/app/CtsShimPrebuilt",
            "/system/priv-app/CtsShimPrivPrebuilt",
        ],
        "feature_tradeoff": "removes projection/cast plus OEM bugreport, on-device tracing UI, Easter egg, tips, and CTS shim apps",
        "rationale": "covers the space target but contains user-protected TNT/projection packages, so it is rejected despite the capacity margin",
        "next_gate": "Do not use this bundle. Recompute without BostonScreenMirror, BostonCastHalService, and SmartisanWirelessCast.",
    },
    {
        "source_id": "no_projection_low_value_service_reserve",
        "risk": "YELLOW_ORANGE",
        "paths": [
            "/system/app/SMTBugreport",
            "/system/app/CrashReport",
            "/system/app/SlardarOsClient",
            "/system/app/SMPushService",
            "/system/app/UnionPushProxy",
            "/system/app/TrackerSmartisan",
            "/system/priv-app/TeaTracker",
            "/system/app/BuiltInPrintService",
            "/system/app/PrintSpooler",
            "/system/app/PrintRecommendationService",
            "/system/app/BasicDreams",
            "/system/app/HTMLViewer",
            "/system/app/LiveWallpapersPicker",
            "/system/app/WallpaperBackup",
            "/system/app/Exchange2",
            "/system/app/Traceur",
            "/system/app/EasterEgg",
            "/system/app/Protips",
            "/system/app/CtsShimPrebuilt",
            "/system/priv-app/CtsShimPrivPrebuilt",
            "/system/priv-app/SmartisanShareManual",
        ],
        "feature_tradeoff": "removes telemetry/push/debug plus print, dream, live wallpaper, HTML viewer, Exchange remnants, CTS shims, and SmartisanShareManual",
        "rationale": "smallest reviewed no-projection bundle that covers the WebView full-ABI shortfall plus reserve while preserving TNT/projection, BrowserChrome, speech, assistant/text, setup, Launcher, Keyguard, Settings, SystemUI, and phone",
        "next_gate": "Rejected by user selection because the user explicitly preserved the Android print stack: BuiltInPrintService, PrintSpooler, and PrintRecommendationService.",
    },
    {
        "source_id": "user_selected_no_projection_print_preserving",
        "risk": "YELLOW_ORANGE_LOW_RESERVE",
        "paths": USER_SELECTED_PRINT_PRESERVING_PATHS,
        "feature_tradeoff": "removes telemetry/push/debug plus dream, live wallpaper, HTML viewer, Exchange remnants, CTS shims, and SmartisanShareManual while preserving Android printing",
        "rationale": "user-selected no-projection bundle from the low-value review set; it preserves BuiltInPrintService, PrintSpooler, and PrintRecommendationService, and still avoids TNT/projection, BrowserChrome, speech, assistant/text, setup, Launcher, Keyguard, Settings, SystemUI, and phone",
        "next_gate": "Run package-specific delete preflights for this selected set. It covers the bare full-ABI WebView shortfall, but does not cover the 8 MiB reserve; choose an extra space source, a smaller WebView build, or explicitly accept the low-reserve layout before image build.",
    },
    {
        "source_id": "smartisan_wallpapers_resource_pack",
        "risk": "GREEN_USER_VISIBLE_WALLPAPER_ASSETS",
        "paths": ["/system/app/SmartisanWallpapers"],
        "feature_tradeoff": "removes the bundled Smartisan wallpaper resource APK; existing /data wallpaper image should survive, but the stock wallpaper picker may lose built-in choices",
        "rationale": "delete preflight is GREEN, the APK has no components, no requested permissions, and no sysconfig references; static search found no hard-coded package references in the generated ROM knowledge base; the archive is almost entirely drawable assets",
        "next_gate": "Best extra-space candidate found so far. Before image build, run a focused WallpaperProvider/resource lookup review and live-check current wallpaper plus wallpaper picker behavior on a small isolated variant.",
    },
    {
        "source_id": "user_selected_plus_smartisan_wallpapers_reserve",
        "risk": "YELLOW_ORANGE_PLUS_GREEN_WALLPAPER_ASSETS",
        "paths": USER_SELECTED_PRINT_PRESERVING_PATHS + ["/system/app/SmartisanWallpapers"],
        "feature_tradeoff": "uses the user-selected no-projection/print-preserving deletion set and also removes the bundled Smartisan wallpaper resource APK",
        "rationale": "covers the bare WebView full-ABI shortfall, restores a comfortable reserve, keeps Android printing and TNT/projection, and avoids BrowserChrome, speech/assistant/text, setup, Launcher, Keyguard, Settings, SystemUI, and phone",
        "next_gate": "Run delete preflights for the user-selected set plus a focused wallpaper asset review; this remains a candidate, not deletion authorization.",
    },
    {
        "source_id": "user_selected_plus_weather_pair_reserve",
        "risk": "YELLOW_ORANGE_USER_FEATURE",
        "paths": USER_SELECTED_PRINT_PRESERVING_PATHS + ["/system/app/WeatherSmartisan", "/system/app/WeatherProvider"],
        "feature_tradeoff": "uses the user-selected no-projection/print-preserving deletion set and also removes the stock weather app/provider base",
        "rationale": "weather is a larger optional feature pair; WeatherSmartisan delete preflight is YELLOW and WeatherProvider is ORANGE because of provider/sysconfig hiddenapi references, so this is viable but less clean than the pure wallpaper resource pack",
        "next_gate": "Use only if the user prefers deleting Weather over deleting bundled wallpapers; pair ROM deletion with post-boot updated-system/data-state validation if live /data weather shadows exist.",
    },
    {
        "source_id": "telemetry_push_print_debug_bundle",
        "risk": "YELLOW_ORANGE",
        "paths": [
            "/system/app/SMTBugreport",
            "/system/app/CrashReport",
            "/system/app/SlardarOsClient",
            "/system/app/SMPushService",
            "/system/app/UnionPushProxy",
            "/system/app/TrackerSmartisan",
            "/system/priv-app/TeaTracker",
            "/system/app/BuiltInPrintService",
            "/system/app/PrintSpooler",
            "/system/app/PrintRecommendationService",
            "/system/app/BasicDreams",
            "/system/app/HTMLViewer",
            "/system/app/LiveWallpapersPicker",
            "/system/app/WallpaperBackup",
            "/system/app/Exchange2",
            "/system/app/Traceur",
            "/system/app/EasterEgg",
            "/system/app/Protips",
            "/system/app/CtsShimPrebuilt",
            "/system/priv-app/CtsShimPrivPrebuilt",
        ],
        "feature_tradeoff": "removes telemetry/push/debug plus print, dream, live wallpaper, HTML viewer, and Exchange remnants",
        "rationale": "does not touch browser or core boot UI, but it removes many independent surfaces and may affect OEM push/diagnostics",
        "next_gate": "Use only after deciding that OEM push/tracking and print/dream/viewer features are not needed.",
    },
    {
        "source_id": "speech_suite_only",
        "risk": "ORANGE_RED",
        "paths": ["/system/app/SpeechSuite"],
        "feature_tradeoff": "removes Iflytek speech suite; likely affects voice input, speech recognition, and assistant features",
        "rationale": "large enough alone, but conflicts with the prior goal of keeping Smartisan assistant-style features working",
        "next_gate": "Defer unless the user explicitly accepts speech/voice feature loss.",
    },
    {
        "source_id": "weather_pair",
        "risk": "YELLOW",
        "paths": ["/system/app/WeatherSmartisan", "/system/app/WeatherProvider"],
        "feature_tradeoff": "removes stock weather app and weather provider base",
        "rationale": "optional feature pair, but too small to solve the WebView space problem by itself",
        "next_gate": "Can be combined with another bundle only if the user wants deeper debloat.",
    },
    {
        "source_id": "setupwizard_pair",
        "risk": "RED_FACTORY_RESET",
        "paths": ["/system/app/SetupWizard", "/system/app/TableSetupWizard"],
        "feature_tradeoff": "removes first-boot/factory-reset setup surfaces",
        "rationale": "large enough, but factory reset and provisioning workflows become risky",
        "next_gate": "Defer until a separate factory-reset/provisioning rollback plan exists.",
    },
    {
        "source_id": "browserchrome",
        "risk": "RED_REJECTED_FOR_SPACE_SOURCE",
        "paths": ["/system/app/BrowserChrome"],
        "feature_tradeoff": "removes the stock default browser track",
        "rationale": "very large, but BrowserChrome is a RED separate modernization track and should not be used as a casual space source for WebView",
        "next_gate": "Do not use BrowserChrome as the v0.33 space source.",
    },
    {
        "source_id": "smartisan_ai_text_stack",
        "risk": "RED_USER_FEATURE_CONFLICT",
        "paths": [
            "/system/priv-app/VoiceAssistant",
            "/system/app/VoiceAssistantService",
            "/system/app/SpeechSuite",
            "/system/priv-app/SmartisanBrain",
            "/system/priv-app/IdeaPills",
            "/system/app/TextBoom",
            "/system/app/TextParticiple",
            "/system/app/IntelligenWords",
            "/system/app/QuickSearchBoxSmartisan",
        ],
        "feature_tradeoff": "removes or damages Sara, Big Bang/text intelligence, voice assistant, and search-related features",
        "rationale": "huge space source, but it collides with previously preserved Smartisan features and should not be a WebView prerequisite",
        "next_gate": "Defer unless the user explicitly chooses to abandon these Smartisan feature surfaces.",
    },
]


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def sh(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)


def die(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def parse_stats() -> FsStats:
    if not DEBUGFS.is_file():
        die(f"missing debugfs: {DEBUGFS}")
    if not SYSTEM_IMAGE.is_file():
        die(f"missing system image: {SYSTEM_IMAGE}")
    result = sh([str(DEBUGFS), "-R", "stats", str(SYSTEM_IMAGE)])
    if result.returncode != 0:
        die(result.stderr or result.stdout)
    values: dict[str, int] = {}
    for line in result.stdout.splitlines():
        match = re.match(r"(Block size|Free blocks):\s+(\d+)", line)
        if match:
            values[match.group(1)] = int(match.group(2))
    if "Block size" not in values or "Free blocks" not in values:
        die("debugfs stats did not expose Block size and Free blocks")
    return FsStats(
        block_size=values["Block size"],
        free_blocks=values["Free blocks"],
        free_bytes=values["Block size"] * values["Free blocks"],
    )


def stat_path(path: str) -> tuple[bool, str, int, int, int]:
    result = sh([str(DEBUGFS), "-R", f"stat {path}", str(SYSTEM_IMAGE)])
    text = result.stdout + result.stderr
    if "File not found" in text or result.returncode != 0:
        return False, "", 0, 0, 0
    type_match = re.search(r"Type:\s+(\w+)", text)
    inode_match = re.search(r"Inode:\s+(\d+)", text)
    size_match = re.search(r"Size:\s+(\d+)", text)
    block_match = re.search(r"Blockcount:\s+(\d+)", text)
    return (
        True,
        type_match.group(1) if type_match else "unknown",
        int(inode_match.group(1)) if inode_match else 0,
        int(size_match.group(1)) if size_match else 0,
        int(block_match.group(1)) * 512 if block_match else 0,
    )


def ls_path(path: str) -> list[tuple[int, str, str, int]]:
    result = sh([str(DEBUGFS), "-R", f"ls -p {path}", str(SYSTEM_IMAGE)])
    if result.returncode != 0:
        return []
    rows: list[tuple[int, str, str, int]] = []
    for line in result.stdout.splitlines():
        if not line.startswith("/"):
            continue
        parts = line.strip().split("/")
        if len(parts) < 7:
            continue
        inode = int(parts[1])
        mode = parts[2]
        name = parts[5]
        size = int(parts[6] or 0)
        if name in {".", ".."}:
            continue
        rows.append((inode, mode, name, size))
    return rows


def measure_one(path: str, seen: set[int]) -> tuple[bool, int, int, int, int]:
    present, type_name, inode, size, allocated = stat_path(path)
    if not present:
        return False, 0, 0, 0, 0
    if inode in seen:
        return True, 0, 0, 0, 0
    seen.add(inode)
    logical = size
    files = 1 if type_name == "regular" else 0
    dirs = 1 if type_name == "directory" else 0
    if type_name == "directory":
        for _child_inode, mode, name, _child_size in ls_path(path):
            child_path = path.rstrip("/") + "/" + name
            child_present, child_logical, child_allocated, child_files, child_dirs = measure_one(child_path, seen)
            if child_present:
                logical += child_logical
                allocated += child_allocated
                files += child_files
                dirs += child_dirs
    return True, logical, allocated, files, dirs


def load_package_facts() -> tuple[dict[str, list[str]], dict[str, dict[str, int]]]:
    path_to_packages: dict[str, list[str]] = {}
    package_stats: dict[str, dict[str, int]] = {}
    if PACKAGES_TSV.exists():
        with PACKAGES_TSV.open(encoding="utf-8") as fh:
            for row in csv.DictReader(fh, delimiter="\t"):
                if row.get("partition") != "system":
                    continue
                package = row.get("package") or ""
                rel_path = row.get("rel_path") or ""
                if not package or not rel_path:
                    continue
                normalized_rel_path = rel_path
                if normalized_rel_path.startswith("system/"):
                    normalized_rel_path = normalized_rel_path[len("system/") :]
                image_path = "/system/" + normalized_rel_path
                parts = image_path.split("/")
                if len(parts) >= 5 and parts[2] in {"app", "priv-app"}:
                    package_dir = "/".join(parts[:4])
                    path_to_packages.setdefault(package_dir, []).append(package)
                    package_stats.setdefault(
                        package,
                        {
                            "components": 0,
                            "exported_components": 0,
                            "permissions": 0,
                            "priv_app": 1 if row.get("priv_app") == "yes" else 0,
                            "shared_uid": 1 if row.get("sharedUserId") else 0,
                        },
                    )
    if COMPONENTS_TSV.exists():
        with COMPONENTS_TSV.open(encoding="utf-8") as fh:
            for row in csv.DictReader(fh, delimiter="\t"):
                package = row.get("package") or ""
                if package not in package_stats:
                    continue
                package_stats[package]["components"] += 1
                if str(row.get("exported", "")).lower() == "true":
                    package_stats[package]["exported_components"] += 1
    if PERMISSIONS_TSV.exists():
        with PERMISSIONS_TSV.open(encoding="utf-8") as fh:
            for row in csv.DictReader(fh, delimiter="\t"):
                package = row.get("package") or ""
                if package in package_stats:
                    package_stats[package]["permissions"] += 1
    return path_to_packages, package_stats


def package_names_for(path: str, path_to_packages: dict[str, list[str]]) -> list[str]:
    names: list[str] = []
    for package_path, packages in path_to_packages.items():
        if path == package_path or path.startswith(package_path.rstrip("/") + "/"):
            names.extend(packages)
    return sorted(set(names))


def measure_source(source: dict, shortfall: int, reserved_target: int, path_to_packages: dict[str, list[str]]) -> tuple[SpaceSource, list[PathMeasure]]:
    seen: set[int] = set()
    path_rows: list[PathMeasure] = []
    total_logical = 0
    total_allocated = 0
    total_packages: set[str] = set()
    for path in source["paths"]:
        present, logical, allocated, files, dirs = measure_one(path, seen)
        packages = package_names_for(path, path_to_packages)
        total_packages.update(packages)
        total_logical += logical
        total_allocated += allocated
        path_rows.append(
            PathMeasure(
                path=path,
                present=present,
                logical_bytes=logical,
                allocated_bytes=allocated,
                files=files,
                dirs=dirs,
                package_names=", ".join(packages) if packages else "",
            )
        )
    allocated_margin = total_allocated - shortfall
    reserve_margin = total_allocated - reserved_target
    if source["source_id"] == "browserchrome":
        status = "REJECTED_RED_BROWSER_TRACK"
    elif source["source_id"] in {"projection_cast_stack", "projection_plus_low_value_debug_reserve"}:
        status = "REJECTED_USER_PROTECTED_TNT_PROJECTION"
    elif source["source_id"] in {"setupwizard_pair", "smartisan_ai_text_stack"}:
        status = "DEFERRED_FEATURE_OR_FACTORY_RISK"
    elif source["source_id"] == RECOMMENDED_SOURCE_ID and reserve_margin >= 0:
        status = "USER_SELECTED_COVERS_RESERVE"
    elif source["source_id"] == RECOMMENDED_SOURCE_ID and allocated_margin >= 0:
        status = "USER_SELECTED_COVERS_SHORTFALL_LOW_RESERVE"
    elif source["source_id"] == RECOMMENDED_SOURCE_ID:
        status = "USER_SELECTED_NOT_ENOUGH_ALONE"
    elif reserve_margin >= 0:
        status = "COVERS_SHORTFALL_WITH_RESERVE"
    elif allocated_margin >= 0:
        status = "COVERS_SHORTFALL_LOW_RESERVE"
    else:
        status = "NOT_ENOUGH_ALONE"
    return (
        SpaceSource(
            source_id=source["source_id"],
            status=status,
            risk=source["risk"],
            logical_bytes=total_logical,
            allocated_bytes=total_allocated,
            margin_to_shortfall=allocated_margin,
            margin_to_reserved_target=reserve_margin,
            path_count=len(source["paths"]),
            package_names=", ".join(sorted(total_packages)),
            feature_tradeoff=source["feature_tradeoff"],
            rationale=source["rationale"],
            next_gate=source["next_gate"],
        ),
        path_rows,
    )


def capacity_numbers() -> tuple[int, int, int, int, int]:
    data = read_json(CAPACITY_JSON)
    system = data.get("system") or {}
    candidate = data.get("candidate") or {}
    system_free = int(system.get("free_bytes") or 0)
    without_libs = int(candidate.get("without_libs") or 0)
    lib_arm64 = int(candidate.get("lib_arm64") or 0)
    lib_arm32 = int(candidate.get("lib_arm32") or 0)
    full_external_need = without_libs + lib_arm64 + lib_arm32
    shortfall = max(0, full_external_need - system_free)
    return system_free, without_libs, lib_arm64, lib_arm32, shortfall


def build_gates(stats: FsStats, shortfall: int, reserved_target: int, sources: list[SpaceSource]) -> list[Gate]:
    selected = next((s for s in sources if s.source_id == RECOMMENDED_SOURCE_ID), None)
    browser = next((s for s in sources if s.source_id == "browserchrome"), None)
    selected_status = "MISSING"
    selected_next_step = "Regenerate the space-source audit before image design."
    if selected:
        if selected.margin_to_reserved_target >= 0:
            selected_status = "SELECTED_WITH_RESERVE"
            selected_next_step = "Run package-specific delete preflights before any image build."
        elif selected.margin_to_shortfall >= 0:
            selected_status = "SELECTED_LOW_RESERVE"
            selected_next_step = "Find extra reserve, reduce WebView footprint, or explicitly accept a low-reserve image layout before build."
        else:
            selected_status = "SELECTED_NOT_ENOUGH"
            selected_next_step = "Choose more space sources or a smaller WebView build before image work."
    return [
        Gate(
            "SPACE-GATE-01-system-shortfall-recorded",
            "PASS",
            f"system_free={stats.free_bytes}; shortfall={shortfall}; reserve={RESERVE_BYTES}; reserved_target={reserved_target}",
            "Use the reserved target, not just the bare shortfall, when choosing a space source.",
        ),
        Gate(
            "SPACE-GATE-02-browserchrome-not-space-source",
            "REJECTED",
            f"browserchrome_allocated={browser.allocated_bytes if browser else 'unknown'}",
            "Keep BrowserChrome on its separate RED modernization track; do not delete it just to fund WebView.",
        ),
        Gate(
            "SPACE-GATE-03-user-selected-source-recorded",
            selected_status,
            f"source={selected.source_id if selected else 'none'}; allocated={selected.allocated_bytes if selected else 'unknown'}; margin_to_shortfall={selected.margin_to_shortfall if selected else 'unknown'}; margin_to_reserved_target={selected.margin_to_reserved_target if selected else 'unknown'}",
            selected_next_step,
        ),
        Gate(
            "SPACE-GATE-04-no-build-authorization",
            "BLOCKED_IMAGE_DESIGN",
            "this audit is read-only and does not delete packages or build images",
            "After preflights and reserve/layout decision, build a separate candidate image with explicit user confirmation.",
        ),
    ]


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|") for cell in row) + " |")
    return lines


def audit_verdict(sources: list[SpaceSource]) -> str:
    selected = next((source for source in sources if source.source_id == RECOMMENDED_SOURCE_ID), None)
    if selected and selected.margin_to_reserved_target >= 0:
        return "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_COVERS_RESERVE"
    if selected and selected.margin_to_shortfall >= 0:
        return "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_LOW_RESERVE"
    if selected:
        return "SYSTEM_B_SPACE_SOURCE_USER_SELECTED_NOT_ENOUGH"
    return "SYSTEM_B_SPACE_SOURCE_SELECTION_MISSING"


def write_outputs(stats: FsStats, need: dict, sources: list[SpaceSource], path_rows: dict[str, list[PathMeasure]], gates: list[Gate]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "section",
                "source_id",
                "status",
                "risk",
                "path",
                "present",
                "logical_bytes",
                "allocated_bytes",
                "margin_to_shortfall",
                "margin_to_reserved_target",
                "package_names",
                "feature_tradeoff",
                "next_gate",
            ]
        )
        for gate in gates:
            writer.writerow(["gate", gate.gate, gate.status, "", "", "", "", "", "", "", "", gate.evidence, gate.next_step])
        for source in sources:
            writer.writerow(
                [
                    "source",
                    source.source_id,
                    source.status,
                    source.risk,
                    "",
                    "",
                    source.logical_bytes,
                    source.allocated_bytes,
                    source.margin_to_shortfall,
                    source.margin_to_reserved_target,
                    source.package_names,
                    source.feature_tradeoff,
                    source.next_gate,
                ]
            )
            for path_row in path_rows[source.source_id]:
                writer.writerow(
                    [
                        "path",
                        source.source_id,
                        source.status,
                        source.risk,
                        path_row.path,
                        str(path_row.present).lower(),
                        path_row.logical_bytes,
                        path_row.allocated_bytes,
                        "",
                        "",
                        path_row.package_names,
                        "",
                        "",
                    ]
                )

    lines: list[str] = []
    lines.append("# WebView System Space Source Audit")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is an offline/read-only audit. It does not build images, touch a")
    lines.append("device, flash, reboot, erase partitions, write settings, delete files,")
    lines.append("or modify `/data`.")
    lines.append("")
    lines.append("## Result")
    lines.append("")
    lines.append(
        "The user-selected non-BrowserChrome and non-TNT/projection `system_b` "
        f"space source is `{RECOMMENDED_SOURCE_ID}`. It preserves the Android "
        "print stack (`BuiltInPrintService`, `PrintSpooler`, and "
        "`PrintRecommendationService`) while avoiding BrowserChrome, "
        "TNT/projection packages, speech/assistant/text features, and core "
        "boot/UI packages. It covers the current bare WebView full-ABI "
        "shortfall, but it does not cover the 8 MiB planning reserve."
    )
    lines.append("")
    lines.append(
        f"The safest newly recorded extra source is `{PREFERRED_EXTRA_SOURCE_ID}`: "
        "a GREEN preflight, no-component, no-permission Smartisan wallpaper "
        "resource APK. It appears to be a user-visible asset loss rather than "
        "a boot/service dependency, and it can also stand alone as a reserve-"
        "covering space source if the user prefers not to delete the larger "
        "telemetry/push/debug bundle."
    )
    lines.append("")
    lines.append("This does not authorize deletion or image construction. It records the")
    lines.append("selected deletion set and the remaining reserve/layout decision.")
    lines.append("")
    lines.append("## Capacity Target")
    lines.append("")
    lines.extend(
        md_table(
            ["Item", "Bytes"],
            [
                ["system_b free bytes", stats.free_bytes],
                ["candidate APK without WebView libs", need["without_libs"]],
                ["M150 arm64 lib bytes", need["lib_arm64"]],
                ["M150 armeabi-v7a lib bytes", need["lib_arm32"]],
                ["full-ABI external layout need", need["full_external_need"]],
                ["bare shortfall", need["shortfall"]],
                ["planning reserve", RESERVE_BYTES],
                ["reserved target", need["reserved_target"]],
            ],
        )
    )
    lines.append("")
    lines.append("## Gates")
    lines.append("")
    lines.extend(md_table(["Gate", "Status", "Evidence", "Next step"], [[g.gate, g.status, g.evidence, g.next_step] for g in gates]))
    lines.append("")
    lines.append("## Space Source Candidates")
    lines.append("")
    lines.extend(
        md_table(
            [
                "Source",
                "Status",
                "Risk",
                "Allocated bytes",
                "Margin to shortfall",
                "Margin to reserved target",
                "Tradeoff",
            ],
            [
                [
                    source.source_id,
                    source.status,
                    source.risk,
                    source.allocated_bytes,
                    source.margin_to_shortfall,
                    source.margin_to_reserved_target,
                    source.feature_tradeoff,
                ]
                for source in sources
            ],
        )
    )
    lines.append("")
    for source in sources:
        lines.append(f"## {source.source_id}")
        lines.append("")
        lines.extend(
            md_table(
                ["Field", "Value"],
                [
                    ["status", source.status],
                    ["risk", source.risk],
                    ["logical bytes", source.logical_bytes],
                    ["allocated bytes", source.allocated_bytes],
                    ["margin to bare shortfall", source.margin_to_shortfall],
                    ["margin to reserved target", source.margin_to_reserved_target],
                    ["packages", source.package_names or "not mapped"],
                    ["feature tradeoff", source.feature_tradeoff],
                    ["rationale", source.rationale],
                    ["next gate", source.next_gate],
                ],
            )
        )
        lines.append("")
        lines.extend(
            md_table(
                ["Path", "Present", "Logical bytes", "Allocated bytes", "Files", "Dirs", "Packages"],
                [
                    [
                        row.path,
                        row.present,
                        row.logical_bytes,
                        row.allocated_bytes,
                        row.files,
                        row.dirs,
                        row.package_names,
                    ]
                    for row in path_rows[source.source_id]
                ],
            )
        )
        lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("- Do not use BostonScreenMirror, BostonCastHalService, or SmartisanWirelessCast as WebView space sources; they are treated as user-protected TNT/wireless projection dependencies.")
    lines.append("- Do not use BrowserChrome as a space source for WebView; it is the separate RED browser modernization track.")
    lines.append("- Do not use SpeechSuite or the broader Smartisan AI/text stack unless the user explicitly accepts assistant, speech, Big Bang, and search feature loss.")
    lines.append("- Do not use SetupWizard/TableSetupWizard without a factory-reset/provisioning rollback plan.")
    lines.append("- Preserve BuiltInPrintService, PrintSpooler, and PrintRecommendationService unless the user explicitly reopens the Android print feature boundary.")
    lines.append("- The selected source covers the bare WebView full-ABI shortfall but not the 8 MiB reserve; choose extra space, a smaller WebView build, or explicit low-reserve acceptance before image work.")
    lines.append("- After the selected source is preflighted, build a dedicated image; this report is not a flash gate.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    OUT_MD.write_text("\n".join(lines), encoding="utf-8")

    verdict = audit_verdict(sources)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().isoformat(timespec="seconds"),
                "verdict": verdict,
                "donor_backed_image_allowed": False,
                "preferred_extra_source_id": PREFERRED_EXTRA_SOURCE_ID,
                "system_image": rel(SYSTEM_IMAGE),
                "capacity_audit": rel(CAPACITY_JSON),
                "stats": asdict(stats),
                "need": need,
                "gates": [asdict(gate) for gate in gates],
                "sources": [asdict(source) for source in sources],
                "paths": {source_id: [asdict(row) for row in rows] for source_id, rows in path_rows.items()},
                "recommended_source_id": RECOMMENDED_SOURCE_ID,
            },
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    stats = parse_stats()
    system_free, without_libs, lib_arm64, lib_arm32, shortfall = capacity_numbers()
    if not system_free:
        system_free = stats.free_bytes
    full_external_need = without_libs + lib_arm64 + lib_arm32
    reserved_target = shortfall + RESERVE_BYTES
    path_to_packages, _package_stats = load_package_facts()
    sources: list[SpaceSource] = []
    path_rows: dict[str, list[PathMeasure]] = {}
    for definition in SPACE_SOURCES:
        source, rows = measure_source(definition, shortfall, reserved_target, path_to_packages)
        sources.append(source)
        path_rows[source.source_id] = rows
    gates = build_gates(stats, shortfall, reserved_target, sources)
    need = {
        "system_free": system_free,
        "without_libs": without_libs,
        "lib_arm64": lib_arm64,
        "lib_arm32": lib_arm32,
        "full_external_need": full_external_need,
        "shortfall": shortfall,
        "reserve": RESERVE_BYTES,
        "reserved_target": reserved_target,
    }
    write_outputs(stats, need, sources, path_rows, gates)
    print(f"verdict={audit_verdict(sources)}")
    print("donor_backed_image_allowed=false")
    print(f"recommended_source_id={RECOMMENDED_SOURCE_ID}")
    print(f"report={rel(OUT_MD)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
