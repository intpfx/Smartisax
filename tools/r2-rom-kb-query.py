#!/usr/bin/env python3
"""Query the Smartisan OS 8.5.3 ROM static knowledge base indexes."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def print_rows(rows: list[dict[str, str]], columns: list[str], limit: int) -> None:
    shown = rows[:limit]
    if not shown:
        print("no matches")
        return
    print("\t".join(columns))
    for row in shown:
        print("\t".join(row.get(col, "") for col in columns))
    if len(rows) > limit:
        print(f"... {len(rows) - limit} more")


def contains(row: dict[str, str], needle: str) -> bool:
    n = needle.lower()
    return any(n in value.lower() for value in row.values())


def matches(row: dict[str, str], needle: str, columns: list[str], exact: bool) -> bool:
    if exact:
        return any(row.get(col, "") == needle for col in columns)
    return contains(row, needle)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "kind",
        choices=[
            "package",
            "class",
            "component",
            "intent",
            "permission",
            "privapp",
            "sysconfig",
            "config",
            "overlay",
            "signature",
            "resource",
            "overlayable",
        ],
    )
    parser.add_argument("query")
    parser.add_argument("--kb", type=Path, default=DEFAULT_KB)
    parser.add_argument("--exact", action="store_true")
    parser.add_argument("--limit", type=int, default=40)
    args = parser.parse_args()

    indexes = args.kb / "indexes"
    if args.kind == "package":
        rows = [r for r in read_rows(indexes / "packages.tsv") if matches(r, args.query, ["package", "name"], args.exact)]
        print_rows(
            rows,
            [
                "package",
                "partition",
                "rel_path",
                "priv_app",
                "versionCode",
                "versionName",
                "sharedUserId",
                "overlayTarget",
                "status",
                "java_files",
                "xml_files",
                "sha256",
            ],
            args.limit,
        )
    elif args.kind == "class":
        rows = [r for r in read_rows(indexes / "classes.tsv") if matches(r, args.query, ["class"], args.exact)]
        print_rows(rows, ["source_name", "class", "java_path"], args.limit)
    elif args.kind == "component":
        rows = [r for r in read_rows(indexes / "components.tsv") if matches(r, args.query, ["package", "name"], args.exact)]
        print_rows(rows, ["package", "type", "name", "exported", "source_name"], args.limit)
    elif args.kind == "intent":
        rows = [r for r in read_rows(indexes / "intent-filters.tsv") if matches(r, args.query, ["package", "component_name", "value"], args.exact)]
        print_rows(rows, ["package", "component_type", "component_name", "filter_index", "entry_type", "value", "source_name"], args.limit)
    elif args.kind == "permission":
        rows = [r for r in read_rows(indexes / "uses-permissions.tsv") if matches(r, args.query, ["package", "permission"], args.exact)]
        print_rows(rows, ["package", "permission", "source_name"], args.limit)
    elif args.kind == "privapp":
        rows = [r for r in read_rows(indexes / "privapp-permissions.tsv") if matches(r, args.query, ["package", "permission"], args.exact)]
        print_rows(rows, ["source_file", "package", "entry_type", "permission"], args.limit)
    elif args.kind == "sysconfig":
        rows = [r for r in read_rows(indexes / "sysconfig-packages.tsv") if matches(r, args.query, ["package", "tag"], args.exact)]
        print_rows(rows, ["source_file", "tag", "package", "attrs"], args.limit)
    elif args.kind == "config":
        rows = [r for r in read_rows(indexes / "permission-config.tsv") if matches(r, args.query, ["name", "file", "uid", "tag"], args.exact)]
        print_rows(rows, ["source_file", "tag", "name", "file", "uid", "attrs"], args.limit)
    elif args.kind == "overlay":
        rows = [r for r in read_rows(indexes / "overlays.tsv") if matches(r, args.query, ["package", "targetPackage"], args.exact)]
        print_rows(rows, ["package", "targetPackage", "isStatic", "priority", "partition", "rel_path"], args.limit)
    elif args.kind == "signature":
        rows = [r for r in read_rows(indexes / "signatures.tsv") if matches(r, args.query, ["source_name", "rel_path", "artifact_type", "signature_status", "cert_sha256"], args.exact)]
        print_rows(rows, ["source_name", "partition", "rel_path", "artifact_type", "signature_status", "cert_sha256", "owner", "algorithm"], args.limit)
    elif args.kind == "resource":
        rows = [r for r in read_rows(indexes / "resources-public.tsv") if matches(r, args.query, ["package", "type", "name", "id"], args.exact)]
        print_rows(rows, ["source_name", "package", "type", "name", "id", "source_file"], args.limit)
    elif args.kind == "overlayable":
        rows = [r for r in read_rows(indexes / "resources-overlayable.tsv") if matches(r, args.query, ["package", "overlayable", "type", "name"], args.exact)]
        print_rows(rows, ["source_name", "package", "overlayable", "policy", "item_tag", "type", "name", "source_file"], args.limit)


if __name__ == "__main__":
    main()
