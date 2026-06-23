#!/usr/bin/env python3
"""Strip or graft APK Sig Block 42 as a certificate carrier.

This is for Smartisax system-partition experiments where Android may scan a
preinstalled package through a certs-only path. The output is not a valid
cryptographic re-signing of a modified APK payload. It only makes the original
APK v2 signing block readable as a certificate carrier for a later, explicitly
verified boot experiment.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path


EOCD_MAGIC = b"PK\x05\x06"
APK_SIG_MAGIC = b"APK Sig Block 42"


@dataclass(frozen=True)
class SigBlock:
    start: int
    end: int
    size_head: int
    size_tail: int

    @property
    def bytes_len(self) -> int:
        return self.end - self.start


def die(message: str) -> None:
    raise SystemExit(f"error: {message}")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def find_eocd(data: bytes) -> int:
    start = max(0, len(data) - 0xFFFF - 22)
    for offset in range(len(data) - 22, start - 1, -1):
        if data[offset : offset + 4] != EOCD_MAGIC:
            continue
        comment_len = struct.unpack_from("<H", data, offset + 20)[0]
        if offset + 22 + comment_len == len(data):
            return offset
    die("EOCD not found")


def central_dir_offset(data: bytes, eocd_offset: int) -> int:
    return struct.unpack_from("<I", data, eocd_offset + 16)[0]


def locate_v2_block(data: bytes) -> SigBlock | None:
    eocd_offset = find_eocd(data)
    cd_offset = central_dir_offset(data, eocd_offset)
    if cd_offset < len(APK_SIG_MAGIC) + 8:
        return None
    magic_offset = cd_offset - len(APK_SIG_MAGIC)
    if data[magic_offset:cd_offset] != APK_SIG_MAGIC:
        return None
    size2_offset = magic_offset - 8
    size2 = struct.unpack_from("<Q", data, size2_offset)[0]
    block_start = cd_offset - size2 - 8
    if block_start < 0:
        die("invalid APK signing block size")
    size1 = struct.unpack_from("<Q", data, block_start)[0]
    if size1 != size2:
        die(f"APK signing block size mismatch: head={size1} tail={size2}")
    return SigBlock(start=block_start, end=cd_offset, size_head=size1, size_tail=size2)


def extract_v2_block(data: bytes) -> bytes:
    block = locate_v2_block(data)
    if block is None:
        die("input APK has no APK Sig Block 42 before the central directory")
    return data[block.start : block.end]


def strip_v2_block(data: bytes) -> tuple[bytes, SigBlock]:
    block = locate_v2_block(data)
    if block is None:
        die("input APK has no APK Sig Block 42 to strip")
    eocd_offset = find_eocd(data)
    old_cd_offset = central_dir_offset(data, eocd_offset)
    block_len = block.bytes_len
    if old_cd_offset != block.end:
        die("unexpected signing block layout")
    out = bytearray()
    out += data[: block.start]
    out += data[block.end :]
    new_eocd_offset = eocd_offset - block_len
    struct.pack_into("<I", out, new_eocd_offset + 16, old_cd_offset - block_len)
    return bytes(out), block


def insert_v2_block(data: bytes, block: bytes) -> bytes:
    existing = locate_v2_block(data)
    if existing is not None:
        die("candidate APK already has APK Sig Block 42; strip it first or pass --strip-existing-candidate")
    eocd_offset = find_eocd(data)
    cd_offset = central_dir_offset(data, eocd_offset)
    out = bytearray()
    out += data[:cd_offset]
    out += block
    out += data[cd_offset:]
    new_eocd_offset = eocd_offset + len(block)
    struct.pack_into("<I", out, new_eocd_offset + 16, cd_offset + len(block))
    return bytes(out)


def write_output(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def run_self_test(path: Path) -> int:
    original = path.read_bytes()
    block = extract_v2_block(original)
    stripped, stripped_block = strip_v2_block(original)
    regrafted = insert_v2_block(stripped, block)
    if regrafted != original:
        die("self-test failed: strip + graft did not reproduce original bytes")
    print("self_test=PASS")
    print(f"apk={path}")
    print(f"sha256={sha256_bytes(original)}")
    print(f"block_start={stripped_block.start}")
    print(f"block_end={stripped_block.end}")
    print(f"block_bytes={stripped_block.bytes_len}")
    print(f"stripped_sha256={sha256_bytes(stripped)}")
    print("regraft_reproduces_original=true")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stock", type=Path, help="Stock APK to copy APK Sig Block 42 from.")
    parser.add_argument("--candidate", type=Path, help="Candidate APK to strip or graft.")
    parser.add_argument("--out", type=Path, help="Output APK path.")
    parser.add_argument("--strip-existing-candidate", action="store_true", help="Strip candidate's existing APK Sig Block 42 before grafting stock block.")
    parser.add_argument("--strip-only", action="store_true", help="Only strip the candidate APK Sig Block 42.")
    parser.add_argument("--self-test", type=Path, help="Run in-memory strip + graft self-test on one APK.")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test(args.self_test)

    if not args.candidate or not args.out:
        die("--candidate and --out are required unless --self-test is used")

    candidate = args.candidate.read_bytes()
    candidate_had_block = locate_v2_block(candidate) is not None
    stripped = False

    if args.strip_only:
        out, block = strip_v2_block(candidate)
        write_output(args.out, out)
        print("mode=strip-only")
        print(f"candidate={args.candidate}")
        print(f"candidate_had_block={str(candidate_had_block).lower()}")
        print(f"stripped_block_bytes={block.bytes_len}")
        print(f"out={args.out}")
        print(f"out_sha256={sha256_bytes(out)}")
        return 0

    if not args.stock:
        die("--stock is required unless --strip-only or --self-test is used")

    if candidate_had_block:
        if not args.strip_existing_candidate:
            die("candidate has APK Sig Block 42; pass --strip-existing-candidate to strip before graft")
        candidate, removed = strip_v2_block(candidate)
        stripped = True
        removed_bytes = removed.bytes_len
    else:
        removed_bytes = 0

    stock = args.stock.read_bytes()
    stock_block = extract_v2_block(stock)
    out = insert_v2_block(candidate, stock_block)
    write_output(args.out, out)
    print("mode=graft-stock-carrier")
    print(f"stock={args.stock}")
    print(f"candidate={args.candidate}")
    print(f"candidate_had_block={str(candidate_had_block).lower()}")
    print(f"candidate_block_stripped={str(stripped).lower()}")
    print(f"candidate_stripped_block_bytes={removed_bytes}")
    print(f"stock_block_bytes={len(stock_block)}")
    print(f"out={args.out}")
    print(f"out_sha256={sha256_bytes(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
