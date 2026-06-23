#!/usr/bin/env python3
"""Copy an APK v2 signing block from a stock APK into an edited APK.

This is for system-partition experiments where PackageManager scans packages
with skipVerify=true but still needs to collect original signing certificates.
The copied block is not made cryptographically valid for the edited payload; it
only preserves the original certificate carrier for the platform's unsafe cert
collection path.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


EOCD_MAGIC = b"PK\x05\x06"
APK_SIG_MAGIC = b"APK Sig Block 42"


def find_eocd(data: bytes) -> int:
    start = max(0, len(data) - 0xFFFF - 22)
    for offset in range(len(data) - 22, start - 1, -1):
        if data[offset : offset + 4] != EOCD_MAGIC:
            continue
        comment_len = struct.unpack_from("<H", data, offset + 20)[0]
        if offset + 22 + comment_len == len(data):
            return offset
    raise SystemExit("EOCD not found")


def central_dir_offset(data: bytes, eocd_offset: int) -> int:
    return struct.unpack_from("<I", data, eocd_offset + 16)[0]


def extract_v2_block(data: bytes) -> bytes:
    eocd_offset = find_eocd(data)
    cd_offset = central_dir_offset(data, eocd_offset)
    if cd_offset < 32:
        raise SystemExit("central directory offset is too small for an APK signing block")
    magic_offset = cd_offset - len(APK_SIG_MAGIC)
    if data[magic_offset:cd_offset] != APK_SIG_MAGIC:
        raise SystemExit("stock APK has no APK Sig Block 42 before central directory")
    size2_offset = magic_offset - 8
    size2 = struct.unpack_from("<Q", data, size2_offset)[0]
    block_start = cd_offset - size2 - 8
    if block_start < 0:
        raise SystemExit("invalid APK signing block size")
    size1 = struct.unpack_from("<Q", data, block_start)[0]
    if size1 != size2:
        raise SystemExit(f"APK signing block size mismatch: head={size1} tail={size2}")
    return data[block_start:cd_offset]


def has_v2_block(data: bytes) -> bool:
    eocd_offset = find_eocd(data)
    cd_offset = central_dir_offset(data, eocd_offset)
    return cd_offset >= 24 and data[cd_offset - len(APK_SIG_MAGIC) : cd_offset] == APK_SIG_MAGIC


def insert_v2_block(edited: bytes, block: bytes) -> bytes:
    if has_v2_block(edited):
        raise SystemExit("edited APK already has an APK signing block; refusing to insert another")
    eocd_offset = find_eocd(edited)
    cd_offset = central_dir_offset(edited, eocd_offset)
    out = bytearray()
    out += edited[:cd_offset]
    out += block
    out += edited[cd_offset:]
    new_eocd_offset = eocd_offset + len(block)
    struct.pack_into("<I", out, new_eocd_offset + 16, cd_offset + len(block))
    return bytes(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stock", required=True, type=Path)
    parser.add_argument("--edited", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    stock = args.stock.read_bytes()
    edited = args.edited.read_bytes()
    block = extract_v2_block(stock)
    out = insert_v2_block(edited, block)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(out)
    print(f"copied_v2_block_bytes={len(block)}")
    print(f"out={args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
