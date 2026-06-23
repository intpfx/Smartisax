#!/usr/bin/env python3
"""Scan local WebView donor inboxes and run the donor static audit.

This helper is read-only with respect to inputs. It does not download donors,
build images, touch a device, flash, reboot, erase partitions, write settings,
or modify /data. It only writes audit reports under hard-rom/inspect.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDITOR = ROOT / "tools" / "r2-webview-donor-audit.py"
BUNDLE_AUDITOR = ROOT / "tools" / "r2-webview-trichrome-bundle-audit.py"
OUT_ROOT = ROOT / "hard-rom" / "inspect" / "browser-webview-donor-inbox"

DEFAULT_SCAN_ROOTS = [
    ROOT / "apks" / "webview-donor-inbox",
    ROOT / "apks" / "webview",
    ROOT / "apks",
    ROOT / "donors" / "webview",
    ROOT / "hard-rom" / "donors" / "webview",
]

DOWNLOADS_ROOT = Path.home() / "Downloads"

PACKAGE_SUFFIXES = {".apk", ".apkm", ".apks", ".xapk", ".zip"}
NAME_TOKENS = {
    "webview",
    "trichrome",
    "monochrome",
    "chrome",
    "chromium",
    "androidsystemwebview",
    "systemwebview",
}
INBOX_NAME_TOKENS = {"webview", "donor", "trichrome", "chrome"}
EXCLUDE_PARTS = {
    ".git",
    "hard-rom/build",
    "hard-rom/work",
    "hard-rom/inspect",
    "reverse",
    "stock-ota",
    "backups",
}


@dataclass(frozen=True)
class Candidate:
    path: str
    source_root: str
    size: int
    mtime: str
    sha256: str
    filename_match: bool
    inbox_context: bool


@dataclass(frozen=True)
class AuditSummary:
    path: str
    label: str
    sha256: str
    size: int
    source_root: str
    filename_match: bool
    inbox_context: bool
    auditor_returncode: int
    verdict: str
    base_package: str
    base_version_code: str
    base_version_name: str
    adaptation_route: str
    report_md: str
    report_json: str
    error: str
    bundle_auditor_returncode: int
    bundle_verdict: str
    bundle_classification: str
    bundle_report_md: str
    bundle_report_json: str
    bundle_error: str


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def sh(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def normalized_name(path: Path) -> str:
    return re.sub(r"[^a-z0-9]+", "", path.name.lower())


def has_name_match(path: Path) -> bool:
    name = normalized_name(path)
    return any(token in name for token in NAME_TOKENS)


def has_inbox_context(path: Path) -> bool:
    lowered_parts = [part.lower() for part in path.parts]
    return any(any(token in part for token in INBOX_NAME_TOKENS) for part in lowered_parts)


def should_exclude(path: Path) -> bool:
    rel_path = rel(path)
    return any(rel_path == part or rel_path.startswith(part + os.sep) for part in EXCLUDE_PARTS)


def sanitize_label(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    return cleaned or "webview-donor"


def iter_package_files(root: Path, *, max_depth: int | None) -> list[Path]:
    root = root.expanduser()
    if not root.exists():
        return []
    if root.is_file():
        return [root] if root.suffix.lower() in PACKAGE_SUFFIXES else []

    base_depth = len(root.resolve().parts)
    found: list[Path] = []
    for current, dirs, files in os.walk(root):
        current_path = Path(current)
        if should_exclude(current_path):
            dirs[:] = []
            continue
        if max_depth is not None:
            depth = len(current_path.resolve().parts) - base_depth
            if depth >= max_depth:
                dirs[:] = []
        for name in files:
            path = current_path / name
            if path.suffix.lower() in PACKAGE_SUFFIXES:
                found.append(path)
    return sorted(found)


def discover(paths: list[Path], *, include_downloads: bool, max_depth: int, all_apks: bool) -> list[Candidate]:
    scan_roots = [path.expanduser() for path in (paths or DEFAULT_SCAN_ROOTS)]
    if include_downloads:
        scan_roots.append(DOWNLOADS_ROOT)

    candidates: dict[Path, Candidate] = {}
    for root in scan_roots:
        files = iter_package_files(root, max_depth=max_depth)
        for path in files:
            suffix = path.suffix.lower()
            filename_match = has_name_match(path)
            inbox_context = has_inbox_context(path)
            if suffix == ".apk" and not all_apks and not filename_match and not inbox_context:
                continue
            if suffix in {".zip"} and not filename_match and not inbox_context:
                continue
            stat = path.stat()
            digest = sha256(path)
            candidates[path.resolve()] = Candidate(
                path=rel(path),
                source_root=rel(root) if root.exists() else str(root),
                size=stat.st_size,
                mtime=datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                sha256=digest,
                filename_match=filename_match,
                inbox_context=inbox_context,
            )
    return sorted(candidates.values(), key=lambda item: (item.path.lower(), item.sha256))


def read_audit_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def base_apk_fields(data: dict) -> tuple[str, str, str]:
    base_name = data.get("base_apk", "")
    for apk in data.get("apks", []):
        if apk.get("name") == base_name:
            return (
                str(apk.get("package", "")),
                str(apk.get("version_code", "")),
                str(apk.get("version_name", "")),
            )
    return "", "", ""


def run_auditor(candidate: Candidate, *, allow_framework_config_patch: bool) -> AuditSummary:
    path = Path(candidate.path)
    if not path.is_absolute():
        path = ROOT / path
    label = sanitize_label(f"inbox-{path.stem}-{candidate.sha256[:12]}")
    cmd = [str(AUDITOR), str(path), "--label", label]
    if allow_framework_config_patch:
        cmd.append("--allow-framework-config-patch")
    result = sh(cmd)

    report_dir = ROOT / "hard-rom" / "inspect" / "browser-webview-donor" / label
    report_json = report_dir / "webview-donor-audit.json"
    report_md = report_dir / "webview-donor-audit.md"
    data = read_audit_json(report_json)
    package, version_code, version_name = base_apk_fields(data)
    error = ""
    if result.returncode != 0:
        error = (result.stderr or result.stdout).strip().splitlines()[0] if (result.stderr or result.stdout).strip() else "auditor failed"
    bundle_cmd = [str(BUNDLE_AUDITOR), str(path), "--label", label]
    if allow_framework_config_patch:
        bundle_cmd.append("--allow-framework-config-patch")
    bundle_result = sh(bundle_cmd)
    bundle_report_dir = ROOT / "hard-rom" / "inspect" / "browser-webview-trichrome-bundle" / label
    bundle_report_json = bundle_report_dir / "trichrome-bundle-audit.json"
    bundle_report_md = bundle_report_dir / "trichrome-bundle-audit.md"
    bundle_data = read_audit_json(bundle_report_json)
    bundle_error = ""
    if bundle_result.returncode != 0:
        bundle_error = (
            (bundle_result.stderr or bundle_result.stdout).strip().splitlines()[0]
            if (bundle_result.stderr or bundle_result.stdout).strip()
            else "bundle auditor failed"
        )
    return AuditSummary(
        path=candidate.path,
        label=label,
        sha256=candidate.sha256,
        size=candidate.size,
        source_root=candidate.source_root,
        filename_match=candidate.filename_match,
        inbox_context=candidate.inbox_context,
        auditor_returncode=result.returncode,
        verdict=str(data.get("verdict", "AUDITOR_ERROR" if result.returncode else "UNKNOWN")),
        base_package=package,
        base_version_code=version_code,
        base_version_name=version_name,
        adaptation_route=str(data.get("adaptation_route", "")),
        report_md=rel(report_md) if report_md.exists() else "",
        report_json=rel(report_json) if report_json.exists() else "",
        error=error,
        bundle_auditor_returncode=bundle_result.returncode,
        bundle_verdict=str(bundle_data.get("verdict", "BUNDLE_AUDITOR_ERROR" if bundle_result.returncode else "UNKNOWN")),
        bundle_classification=str(bundle_data.get("classification", "")),
        bundle_report_md=rel(bundle_report_md) if bundle_report_md.exists() else "",
        bundle_report_json=rel(bundle_report_json) if bundle_report_json.exists() else "",
        bundle_error=bundle_error,
    )


def write_tsv(path: Path, rows: list[AuditSummary]) -> None:
    fields = [
        "path",
        "label",
        "sha256",
        "size",
        "source_root",
        "filename_match",
        "inbox_context",
        "auditor_returncode",
        "verdict",
        "base_package",
        "base_version_code",
        "base_version_name",
        "adaptation_route",
        "report_md",
        "report_json",
        "error",
        "bundle_auditor_returncode",
        "bundle_verdict",
        "bundle_classification",
        "bundle_report_md",
        "bundle_report_json",
        "bundle_error",
    ]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, delimiter="\t", fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def write_markdown(
    path: Path,
    candidates: list[Candidate],
    rows: list[AuditSummary],
    scan_roots: list[Path],
    include_downloads: bool,
    all_apks: bool,
) -> None:
    lines: list[str] = []
    lines.append("# WebView Donor Inbox Audit")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only local donor inbox audit. It does not download donors,")
    lines.append("build images, touch a device, flash, reboot, erase partitions, write")
    lines.append("settings, or modify `/data`.")
    lines.append("")
    lines.append("## Scan Scope")
    lines.append("")
    lines.append(f"- include Downloads: `{str(include_downloads).lower()}`")
    lines.append(f"- all APKs: `{str(all_apks).lower()}`")
    for root in scan_roots:
        lines.append(f"- root: `{rel(root) if root.exists() else str(root)}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- candidate files: `{len(candidates)}`")
    verdict_counts: dict[str, int] = {}
    for row in rows:
        verdict_counts[row.verdict] = verdict_counts.get(row.verdict, 0) + 1
    if verdict_counts:
        for verdict, count in sorted(verdict_counts.items()):
            lines.append(f"- {verdict}: `{count}`")
    else:
        lines.append("- no local modern donor candidates found")
    lines.append("")

    if rows:
        lines.append("## Candidate Audits")
        lines.append("")
        lines.append("| Verdict | Bundle | Package | Version | File | Route | Reports |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for row in rows:
            version = row.base_version_name or row.base_version_code
            donor_report = f"`{row.report_md}`" if row.report_md else row.error or "missing donor report"
            bundle_report = (
                f"`{row.bundle_report_md}`"
                if row.bundle_report_md
                else row.bundle_error or "missing bundle report"
            )
            bundle_summary = f"{row.bundle_verdict} / {row.bundle_classification or 'unknown'}"
            lines.append(
                "| "
                + " | ".join(
                    cell.replace("|", "\\|").replace("\n", " ")
                    for cell in [
                        row.verdict,
                        bundle_summary,
                        row.base_package or "unknown",
                        version or "unknown",
                        f"`{row.path}`",
                        row.adaptation_route or "unknown",
                        f"donor: {donor_report}; bundle: {bundle_report}",
                    ]
                )
                + " |"
            )
        lines.append("")

    lines.append("## Candidate Files")
    lines.append("")
    if candidates:
        lines.append("| File | Size | SHA-256 | Source | Name match | Inbox context |")
        lines.append("| --- | ---: | --- | --- | --- | --- |")
        for candidate in candidates:
            lines.append(
                f"| `{candidate.path}` | {candidate.size} | `{candidate.sha256}` | `{candidate.source_root}` | {candidate.filename_match} | {candidate.inbox_context} |"
            )
    else:
        lines.append("No package files matched the local WebView donor candidate filters.")
    lines.append("")
    lines.append("## Source Plan")
    lines.append("")
    lines.append("Use `docs/research/webview-donor-source-plan.md` before choosing a")
    lines.append("download/extraction route. The first preferred donor class is a stable")
    lines.append("`com.android.webview` provider or source-built equivalent;")
    lines.append("`com.google.android.webview` and Trichrome/static-library bundles require")
    lines.append("separate framework/provider or multi-package ROM gates. This scanner now")
    lines.append("runs both the single-provider donor audit and the Trichrome bundle audit")
    lines.append("for each local candidate.")
    lines.append("")
    lines.append("## Next Gate")
    lines.append("")
    lines.append("A PASS/WARN donor here is still not flash-ready. Use the per-candidate")
    lines.append("`webview-donor-audit.md` and `trichrome-bundle-audit.md` reports to choose")
    lines.append("between adapt-in-place, framework-provider-add, or a Trichrome/static-")
    lines.append("library bundle design, then build a separate ROM candidate only after")
    lines.append("v0.31 stock provider live proof.")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="Optional local files or directories to scan.")
    parser.add_argument("--include-downloads", action="store_true", help="Also scan ~/Downloads.")
    parser.add_argument("--all-apks", action="store_true", help="Audit every APK under scan roots, not only WebView/Chrome-looking names.")
    parser.add_argument("--max-depth", type=int, default=3, help="Maximum directory depth per scan root. Default: 3.")
    parser.add_argument(
        "--allow-framework-config-patch",
        action="store_true",
        help="Pass through to r2-webview-donor-audit.py for explicit framework-provider exploration.",
    )
    args = parser.parse_args()

    if not AUDITOR.exists():
        raise SystemExit(f"ERROR: missing donor auditor at {AUDITOR}")
    if not BUNDLE_AUDITOR.exists():
        raise SystemExit(f"ERROR: missing bundle auditor at {BUNDLE_AUDITOR}")

    scan_roots = [path.expanduser() for path in (args.paths or DEFAULT_SCAN_ROOTS)]
    if args.include_downloads:
        scan_roots.append(DOWNLOADS_ROOT)

    candidates = discover(args.paths, include_downloads=args.include_downloads, max_depth=args.max_depth, all_apks=args.all_apks)
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    rows = [run_auditor(candidate, allow_framework_config_patch=args.allow_framework_config_patch) for candidate in candidates]

    tsv_path = OUT_ROOT / "webview-donor-inbox-audit.tsv"
    md_path = OUT_ROOT / "webview-donor-inbox-audit.md"
    json_path = OUT_ROOT / "webview-donor-inbox-audit.json"
    write_tsv(tsv_path, rows)
    write_markdown(md_path, candidates, rows, scan_roots, args.include_downloads, args.all_apks)
    json_path.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "scan_roots": [rel(root) if root.exists() else str(root) for root in scan_roots],
                "include_downloads": args.include_downloads,
                "all_apks": args.all_apks,
                "candidates": [asdict(candidate) for candidate in candidates],
                "audits": [asdict(row) for row in rows],
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"candidate_count={len(candidates)}")
    print(f"markdown={rel(md_path)}")
    print(f"tsv={rel(tsv_path)}")
    print(f"json={rel(json_path)}")
    for row in rows:
        bundle = f"{row.bundle_verdict}/{row.bundle_classification or 'unknown'}"
        print(f"{row.verdict}\t{bundle}\t{row.base_package or 'unknown'}\t{row.path}\t{row.report_md or row.error}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
