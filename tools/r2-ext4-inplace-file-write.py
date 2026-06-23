#!/usr/bin/env python3
"""Overwrite an existing ext4 file's allocated blocks without reallocating.

This is a narrow Smartisax hard-ROM helper for tight, shared_blocks Android
partition images. It refuses to write unless the input payload size exactly
matches the existing inode size and, by default, every target block is owned
only by that inode according to debugfs icheck.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_DEBUGFS = "/opt/homebrew/opt/e2fsprogs/sbin/debugfs"


@dataclass(frozen=True)
class Extent:
    logical_start: int
    logical_end: int
    physical_start: int
    physical_end: int

    @property
    def block_count(self) -> int:
        return self.logical_end - self.logical_start + 1


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run_debugfs(debugfs: str, image: Path, command: str) -> str:
    proc = subprocess.run(
        [debugfs, "-R", command, str(image)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"debugfs command failed ({command}):\n{proc.stdout}")
    return proc.stdout


def parse_block_size(stats: str) -> int:
    match = re.search(r"^Block size:\s+(\d+)$", stats, flags=re.MULTILINE)
    if not match:
        raise ValueError("failed to parse block size from debugfs stats")
    return int(match.group(1))


def parse_inode_stat(stat: str) -> tuple[int, int, list[Extent]]:
    inode_match = re.search(r"^Inode:\s+(\d+)", stat, flags=re.MULTILINE)
    size_match = re.search(r"^\s*User:.*\s+Size:\s+(\d+)$", stat, flags=re.MULTILINE)
    if not inode_match or not size_match:
        raise ValueError("failed to parse inode or size from debugfs stat")

    extents: list[Extent] = []
    for match in re.finditer(r"\((\d+)(?:-(\d+))?\):(\d+)(?:-(\d+))?", stat):
        logical_start = int(match.group(1))
        logical_end = int(match.group(2) or match.group(1))
        physical_start = int(match.group(3))
        physical_end = int(match.group(4) or match.group(3))
        if logical_end - logical_start != physical_end - physical_start:
            raise ValueError(f"extent length mismatch: {match.group(0)}")
        extents.append(Extent(logical_start, logical_end, physical_start, physical_end))

    if not extents:
        raise ValueError("no extents found in debugfs stat output")
    extents.sort(key=lambda item: item.logical_start)
    expected = 0
    for extent in extents:
        if extent.logical_start != expected:
            raise ValueError(f"non-contiguous logical extent at {extent}")
        expected = extent.logical_end + 1

    return int(inode_match.group(1)), int(size_match.group(1)), extents


def audit_block_owners(debugfs: str, image: Path, extents: list[Extent], inode: int) -> dict[str, Any]:
    blocks: list[int] = []
    for extent in extents:
        blocks.extend(range(extent.physical_start, extent.physical_end + 1))

    unexpected: list[dict[str, Any]] = []
    missing: list[int] = []
    chunk_size = 100
    for start in range(0, len(blocks), chunk_size):
        chunk = blocks[start : start + chunk_size]
        output = run_debugfs(debugfs, image, "icheck " + " ".join(str(item) for item in chunk))
        seen: dict[int, str] = {}
        for line in output.splitlines():
            match = re.match(r"^(\d+)\s+(.+)$", line.strip())
            if not match or match.group(1) == "Block":
                continue
            seen[int(match.group(1))] = match.group(2).strip()
        for block in chunk:
            owner = seen.get(block)
            if owner is None:
                missing.append(block)
                continue
            owners = [int(item) for item in re.findall(r"\d+", owner)]
            if owners != [inode]:
                unexpected.append({"block": block, "owner_text": owner, "owners": owners})

    return {
        "checked_blocks": len(blocks),
        "missing_owner_rows": missing,
        "unexpected_owner_rows": unexpected,
        "all_blocks_owned_only_by_inode": not missing and not unexpected,
    }


def write_payload(image: Path, payload: Path, block_size: int, extents: list[Extent], inode_size: int) -> None:
    with payload.open("rb") as src, image.open("r+b") as dst:
        logical_block = 0
        remaining = inode_size
        for extent in extents:
            for physical_block in range(extent.physical_start, extent.physical_end + 1):
                if logical_block < extent.logical_start:
                    logical_block += 1
                    continue
                if remaining <= 0:
                    return
                count = min(block_size, remaining)
                data = src.read(count)
                if len(data) != count:
                    raise IOError(f"payload ended early at logical block {logical_block}")
                dst.seek(physical_block * block_size)
                dst.write(data)
                remaining -= count
                logical_block += 1
        if remaining != 0:
            raise IOError(f"payload not fully written, remaining={remaining}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--path", required=True, help="absolute path inside the ext4 image")
    parser.add_argument("--payload", required=True, type=Path)
    parser.add_argument("--debugfs", default=DEFAULT_DEBUGFS)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--write", action="store_true", help="actually mutate --image; default is dry-run")
    parser.add_argument(
        "--allow-shared-block-owners",
        action="store_true",
        help="skip the default icheck owner gate",
    )
    args = parser.parse_args()

    for path in [args.image, args.payload]:
        if not path.is_file():
            print(f"error: missing file: {path}", file=sys.stderr)
            return 1

    stats = run_debugfs(args.debugfs, args.image, "stats")
    block_size = parse_block_size(stats)
    inode, inode_size, extents = parse_inode_stat(run_debugfs(args.debugfs, args.image, f"stat {args.path}"))
    payload_size = args.payload.stat().st_size
    if payload_size != inode_size:
        print(f"error: payload size {payload_size} does not match inode size {inode_size}", file=sys.stderr)
        return 1

    allocated_blocks = sum(extent.block_count for extent in extents)
    required_blocks = math.ceil(inode_size / block_size)
    if allocated_blocks < required_blocks:
        print(
            f"error: extents allocate {allocated_blocks} blocks but file needs {required_blocks}",
            file=sys.stderr,
        )
        return 1

    owner_audit = audit_block_owners(args.debugfs, args.image, extents, inode)
    if not args.allow_shared_block_owners and not owner_audit["all_blocks_owned_only_by_inode"]:
        print("error: target file has missing or shared block owners; refusing in-place write", file=sys.stderr)
        return 1

    before_hash = sha256(args.image) if args.write else None
    if args.write:
        write_payload(args.image, args.payload, block_size, extents, inode_size)
    after_hash = sha256(args.image) if args.write else None

    report = {
        "image": str(args.image),
        "path": args.path,
        "payload": str(args.payload),
        "write": args.write,
        "inode": inode,
        "inode_size": inode_size,
        "payload_size": payload_size,
        "block_size": block_size,
        "allocated_blocks": allocated_blocks,
        "required_blocks": required_blocks,
        "extents": [extent.__dict__ for extent in extents],
        "owner_audit": owner_audit,
        "payload_sha256": sha256(args.payload),
        "image_sha256_before": before_hash,
        "image_sha256_after": after_hash,
    }

    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
