#!/usr/bin/env python3
"""Build a same-size APK candidate without adding ZIP entries.

This is for Smartisax hard-ROM experiments where an ext4 partition is too
tight for held-inode replacement, but the patched APK is smaller than the stock
file. The script can store selected ZIP members, usually resources.arsc, and
then pads the archive to the stock byte size using only the EOCD comment.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def entry_hash(apk: Path, entry: str) -> str | None:
    with zipfile.ZipFile(apk) as zf:
        try:
            data = zf.read(entry)
        except KeyError:
            return None
    return hashlib.sha256(data).hexdigest()


def copy_info(source: zipfile.ZipInfo, *, force_stored: bool) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(source.filename, source.date_time)
    info.comment = source.comment
    info.extra = source.extra
    info.internal_attr = source.internal_attr
    info.external_attr = source.external_attr
    info.create_system = source.create_system
    info.create_version = source.create_version
    info.extract_version = source.extract_version
    info.flag_bits = source.flag_bits
    info.volume = source.volume
    info.compress_type = zipfile.ZIP_STORED if force_stored else source.compress_type
    return info


def comment_bytes(length: int) -> bytes:
    if length < 0 or length > 65535:
        raise ValueError(f"ZIP EOCD comment length out of range: {length}")
    seed = b"SMARTISAX-SAME-SIZE-PAD\n"
    if length <= len(seed):
        return seed[:length]
    repeats, remain = divmod(length - len(seed), 8)
    return seed + (b"R2PAD000" * repeats) + b"R2PAD000"[:remain]


def build_candidate(stock: Path, patched: Path, out: Path, store_entries: set[str]) -> dict[str, Any]:
    stock_size = stock.stat().st_size
    patched_size = patched.stat().st_size

    out.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="r2-apk-same-size-") as tmp_raw:
        tmp = Path(tmp_raw) / "candidate.apk"
        with zipfile.ZipFile(patched, "r") as zin, zipfile.ZipFile(tmp, "w") as zout:
            zout.comment = b""
            for src_info in zin.infolist():
                data = zin.read(src_info.filename)
                info = copy_info(src_info, force_stored=src_info.filename in store_entries)
                zout.writestr(info, data)

        no_comment_size = tmp.stat().st_size
        pad_needed = stock_size - no_comment_size
        if pad_needed < 0:
            raise SystemExit(
                f"candidate after store_entries is already larger than stock: "
                f"stock={stock_size} no_comment={no_comment_size}"
            )
        if pad_needed > 65535:
            raise SystemExit(
                f"candidate needs ZIP comment {pad_needed}, exceeds 65535; "
                "use a different same-size strategy"
            )

        if pad_needed:
            with zipfile.ZipFile(tmp, "a") as zout:
                zout.comment = comment_bytes(pad_needed)

        final_size = tmp.stat().st_size
        if final_size != stock_size:
            raise SystemExit(f"final size mismatch: stock={stock_size} candidate={final_size}")

        os.replace(tmp, out)

    with zipfile.ZipFile(stock) as zs, zipfile.ZipFile(patched) as zp, zipfile.ZipFile(out) as zo:
        stock_names = [i.filename for i in zs.infolist()]
        patched_names = [i.filename for i in zp.infolist()]
        out_names = [i.filename for i in zo.infolist()]
        entries: dict[str, Any] = {}
        for name in sorted(store_entries):
            sinfo = zs.getinfo(name) if name in stock_names else None
            pinfo = zp.getinfo(name) if name in patched_names else None
            oinfo = zo.getinfo(name) if name in out_names else None
            entries[name] = {
                "stock_compress_type": sinfo.compress_type if sinfo else None,
                "patched_compress_type": pinfo.compress_type if pinfo else None,
                "out_compress_type": oinfo.compress_type if oinfo else None,
                "stock_file_size": sinfo.file_size if sinfo else None,
                "patched_file_size": pinfo.file_size if pinfo else None,
                "out_file_size": oinfo.file_size if oinfo else None,
                "stock_compress_size": sinfo.compress_size if sinfo else None,
                "patched_compress_size": pinfo.compress_size if pinfo else None,
                "out_compress_size": oinfo.compress_size if oinfo else None,
            }

        report = {
            "stock": str(stock),
            "patched": str(patched),
            "out": str(out),
            "stock_size": stock_size,
            "patched_size": patched_size,
            "out_size": out.stat().st_size,
            "stock_sha256": sha256(stock),
            "patched_sha256": sha256(patched),
            "out_sha256": sha256(out),
            "store_entries": sorted(store_entries),
            "zip_entry_order_matches_patched": out_names == patched_names,
            "zip_entry_order_matches_stock": out_names == stock_names,
            "zip_comment_len": len(zo.comment),
            "entries": entries,
            "member_hashes": {
                name: {
                    "stock": entry_hash(stock, name),
                    "patched": entry_hash(patched, name),
                    "out": entry_hash(out, name),
                    "out_matches_stock": entry_hash(stock, name) == entry_hash(out, name),
                    "out_matches_patched": entry_hash(patched, name) == entry_hash(out, name),
                }
                for name in ["AndroidManifest.xml", "classes.dex", "resources.arsc"]
            },
        }
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stock", required=True, type=Path)
    parser.add_argument("--patched", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument(
        "--store-entry",
        action="append",
        default=[],
        help="ZIP member to force to method STORED; repeatable",
    )
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    for path in [args.stock, args.patched]:
        if not path.is_file():
            print(f"error: missing file: {path}", file=sys.stderr)
            return 1

    report = build_candidate(args.stock, args.patched, args.out, set(args.store_entry))
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
