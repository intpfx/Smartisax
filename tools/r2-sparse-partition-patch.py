#!/usr/bin/env python3
"""Patch known B-slot partition extents directly inside an Android sparse image.

This avoids expanding a full raw super image when the target partition range is
already stored as RAW sparse chunks. It is intended for exact-current R2 hard-ROM
variants where the dynamic partition layout is fixed and already documented.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import shutil
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path


SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4


@dataclass(frozen=True)
class Extent:
    start_sector: int
    sectors: int
    max_bytes: int

    @property
    def byte_offset(self) -> int:
        return self.start_sector * 512

    @property
    def byte_size(self) -> int:
        return self.sectors * 512


@dataclass(frozen=True)
class SparseHeader:
    file_hdr_sz: int
    chunk_hdr_sz: int
    blk_sz: int
    total_blks: int
    total_chunks: int
    image_checksum: int


@dataclass(frozen=True)
class Chunk:
    index: int
    chunk_type: int
    logical_start_block: int
    block_count: int
    header_offset: int
    data_offset: int
    total_size: int

    @property
    def logical_end_block(self) -> int:
        return self.logical_start_block + self.block_count


EXTENTS = {
    "system_b": Extent(10487744, 5955192, 3049058304),
    "system_ext_b": Extent(16443328, 578352, 296116224),
    "product_b": Extent(17021888, 334200, 171110400),
    "vendor_b": Extent(17356736, 1696608, 868663296),
    "odm_b": Extent(19053504, 2064, 1056768),
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_image_arg(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected PARTITION=IMAGE")
    part, raw_path = value.split("=", 1)
    if part not in EXTENTS:
        raise argparse.ArgumentTypeError(f"unknown partition {part}; expected one of {', '.join(EXTENTS)}")
    path = Path(raw_path)
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"missing image: {path}")
    return part, path


def parse_extract_arg(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected PARTITION=OUT_IMAGE")
    part, raw_path = value.split("=", 1)
    if part not in EXTENTS:
        raise argparse.ArgumentTypeError(f"unknown partition {part}; expected one of {', '.join(EXTENTS)}")
    return part, Path(raw_path)


def parse_extent_arg(value: str) -> tuple[str, Extent]:
    if "=" not in value or ":" not in value:
        raise argparse.ArgumentTypeError("expected PARTITION=START_SECTOR:SECTOR_COUNT")
    part, raw_extent = value.split("=", 1)
    if part not in EXTENTS:
        raise argparse.ArgumentTypeError(f"unknown partition {part}; expected one of {', '.join(EXTENTS)}")
    start_raw, sectors_raw = raw_extent.split(":", 1)
    try:
        start_sector = int(start_raw, 0)
        sectors = int(sectors_raw, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("extent start and sector count must be integers") from exc
    if start_sector < 0 or sectors <= 0:
        raise argparse.ArgumentTypeError("extent start must be non-negative and sector count must be positive")
    return part, Extent(start_sector, sectors, sectors * 512)


def parse_sparse(path: Path) -> tuple[SparseHeader, list[Chunk]]:
    chunks: list[Chunk] = []
    with path.open("rb") as fh:
        header_bytes = fh.read(28)
        if len(header_bytes) != 28:
            raise SystemExit(f"truncated sparse header: {path}")
        (
            magic,
            major_version,
            _minor_version,
            file_hdr_sz,
            chunk_hdr_sz,
            blk_sz,
            total_blks,
            total_chunks,
            image_checksum,
        ) = struct.unpack("<IHHHHIIII", header_bytes)
        if magic != SPARSE_MAGIC:
            raise SystemExit(f"not an Android sparse image: {path}")
        if major_version != 1:
            raise SystemExit(f"unsupported sparse major version: {major_version}")
        if file_hdr_sz < 28 or chunk_hdr_sz < 12:
            raise SystemExit(f"unsupported sparse header sizes: file={file_hdr_sz} chunk={chunk_hdr_sz}")
        fh.seek(file_hdr_sz)
        logical = 0
        for index in range(total_chunks):
            header_offset = fh.tell()
            chunk_header = fh.read(chunk_hdr_sz)
            if len(chunk_header) != chunk_hdr_sz:
                raise SystemExit(f"truncated sparse chunk header {index}: {path}")
            chunk_type, _reserved, chunk_sz, total_sz = struct.unpack("<HHII", chunk_header[:12])
            data_offset = header_offset + chunk_hdr_sz
            expected_total = chunk_hdr_sz
            if chunk_type == CHUNK_RAW:
                expected_total += chunk_sz * blk_sz
            elif chunk_type == CHUNK_FILL:
                expected_total += 4
            elif chunk_type == CHUNK_DONT_CARE:
                expected_total += 0
            elif chunk_type == CHUNK_CRC32:
                expected_total += 4
                if chunk_sz != 0:
                    raise SystemExit(f"CRC32 chunk {index} has non-zero block count: {chunk_sz}")
            else:
                raise SystemExit(f"unsupported sparse chunk type 0x{chunk_type:04x} at chunk {index}")
            if total_sz != expected_total:
                raise SystemExit(
                    f"chunk {index} total size mismatch: got {total_sz}, expected {expected_total}"
                )
            chunks.append(
                Chunk(
                    index=index,
                    chunk_type=chunk_type,
                    logical_start_block=logical,
                    block_count=chunk_sz,
                    header_offset=header_offset,
                    data_offset=data_offset,
                    total_size=total_sz,
                )
            )
            if chunk_type != CHUNK_CRC32:
                logical += chunk_sz
            fh.seek(header_offset + total_sz)
        if logical != total_blks:
            raise SystemExit(f"sparse logical block mismatch: got {logical}, header says {total_blks}")
    return (
        SparseHeader(
            file_hdr_sz=file_hdr_sz,
            chunk_hdr_sz=chunk_hdr_sz,
            blk_sz=blk_sz,
            total_blks=total_blks,
            total_chunks=total_chunks,
            image_checksum=image_checksum,
        ),
        chunks,
    )


def chunk_name(chunk_type: int) -> str:
    return {
        CHUNK_RAW: "RAW",
        CHUNK_FILL: "FILL",
        CHUNK_DONT_CARE: "DONT_CARE",
        CHUNK_CRC32: "CRC32",
    }.get(chunk_type, f"0x{chunk_type:04x}")


def raw_plan(header: SparseHeader, chunks: list[Chunk], extent: Extent) -> list[tuple[Chunk, int, int, int]]:
    if extent.byte_offset % header.blk_sz != 0 or extent.byte_size % header.blk_sz != 0:
        raise SystemExit("partition extent is not sparse-block aligned")
    start_block = extent.byte_offset // header.blk_sz
    end_block = start_block + extent.byte_size // header.blk_sz
    plan: list[tuple[Chunk, int, int, int]] = []
    cursor = start_block
    for chunk in chunks:
        if chunk.chunk_type == CHUNK_CRC32:
            continue
        if chunk.logical_end_block <= cursor:
            continue
        if chunk.logical_start_block >= end_block:
            break
        overlap_start = max(cursor, chunk.logical_start_block)
        overlap_end = min(end_block, chunk.logical_end_block)
        if overlap_start >= overlap_end:
            continue
        if chunk.chunk_type != CHUNK_RAW:
            raise SystemExit(
                f"partition range crosses non-RAW sparse chunk {chunk.index} "
                f"({chunk_name(chunk.chunk_type)}) at logical block {overlap_start}"
            )
        file_offset = chunk.data_offset + (overlap_start - chunk.logical_start_block) * header.blk_sz
        image_offset = (overlap_start - start_block) * header.blk_sz
        byte_count = (overlap_end - overlap_start) * header.blk_sz
        plan.append((chunk, file_offset, image_offset, byte_count))
        cursor = overlap_end
    if cursor != end_block:
        raise SystemExit(f"partition range not fully covered by sparse chunks: stopped at block {cursor}")
    return plan


def clone_sparse(src: Path, dst: Path) -> None:
    if dst.exists():
        raise SystemExit(f"output already exists: {dst}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["cp", "-c", str(src), str(dst)], check=True, stderr=subprocess.PIPE)
    except Exception as exc:
        raise SystemExit(
            f"APFS clone failed for {src} -> {dst}. Refusing full copy by default: {exc}"
        ) from exc


def read_exact(fh, size: int, what: str) -> bytes:
    data = fh.read(size)
    if len(data) != size:
        raise SystemExit(f"truncated data while reading {what}")
    return data


def write_chunk_header(out_fh, header: SparseHeader, chunk_type: int, block_count: int, data_size: int) -> None:
    total_size = header.chunk_hdr_sz + data_size
    out_fh.write(struct.pack("<HHII", chunk_type, 0, block_count, total_size))
    if header.chunk_hdr_sz > 12:
        out_fh.write(b"\x00" * (header.chunk_hdr_sz - 12))


def copy_bytes(src_fh, out_fh, size: int) -> None:
    remaining = size
    while remaining:
        data = src_fh.read(min(1024 * 1024, remaining))
        if not data:
            raise SystemExit("truncated source while copying sparse chunk data")
        out_fh.write(data)
        remaining -= len(data)


def copy_raw_range(src_fh, out_fh, header: SparseHeader, chunk: Chunk, start_block: int, end_block: int) -> None:
    blocks = end_block - start_block
    source_offset = chunk.data_offset + (start_block - chunk.logical_start_block) * header.blk_sz
    write_chunk_header(out_fh, header, CHUNK_RAW, blocks, blocks * header.blk_sz)
    src_fh.seek(source_offset)
    copy_bytes(src_fh, out_fh, blocks * header.blk_sz)


def write_raw_range_from_image(image_fh, out_fh, header: SparseHeader, image_offset: int, blocks: int) -> None:
    byte_count = blocks * header.blk_sz
    write_chunk_header(out_fh, header, CHUNK_RAW, blocks, byte_count)
    image_fh.seek(image_offset)
    copy_bytes(image_fh, out_fh, byte_count)


def write_fill_range(src_fh, out_fh, header: SparseHeader, chunk: Chunk, blocks: int) -> None:
    src_fh.seek(chunk.data_offset)
    fill_value = read_exact(src_fh, 4, f"fill value for chunk {chunk.index}")
    write_chunk_header(out_fh, header, CHUNK_FILL, blocks, 4)
    out_fh.write(fill_value)


def write_dont_care_range(out_fh, header: SparseHeader, blocks: int) -> None:
    write_chunk_header(out_fh, header, CHUNK_DONT_CARE, blocks, 0)


def write_original_range(src_fh, out_fh, header: SparseHeader, chunk: Chunk, start_block: int, end_block: int) -> None:
    blocks = end_block - start_block
    if blocks <= 0:
        return
    if chunk.chunk_type == CHUNK_RAW:
        copy_raw_range(src_fh, out_fh, header, chunk, start_block, end_block)
    elif chunk.chunk_type == CHUNK_FILL:
        write_fill_range(src_fh, out_fh, header, chunk, blocks)
    elif chunk.chunk_type == CHUNK_DONT_CARE:
        write_dont_care_range(out_fh, header, blocks)
    else:
        raise SystemExit(f"cannot copy logical range from chunk type {chunk_name(chunk.chunk_type)}")


def rewrite_sparse_with_images(source_sparse: Path, out_sparse: Path, images: list[tuple[str, Path]]) -> list[str]:
    if out_sparse.exists():
        raise SystemExit(f"output already exists: {out_sparse}")
    out_sparse.parent.mkdir(parents=True, exist_ok=True)

    header, chunks = parse_sparse(source_sparse)
    targets = []
    image_hashes: dict[str, str] = {}
    for part, image in images:
        extent = EXTENTS[part]
        if image.stat().st_size != extent.byte_size:
            raise SystemExit(f"{part} image size mismatch: {image.stat().st_size} != {extent.byte_size}")
        if extent.byte_offset % header.blk_sz != 0 or extent.byte_size % header.blk_sz != 0:
            raise SystemExit(f"{part} extent is not sparse-block aligned")
        targets.append(
            {
                "part": part,
                "image": image,
                "start": extent.byte_offset // header.blk_sz,
                "end": (extent.byte_offset + extent.byte_size) // header.blk_sz,
                "fh": None,
            }
        )
        image_hashes[part] = sha256_file(image)
    targets.sort(key=lambda item: item["start"])
    for left, right in zip(targets, targets[1:]):
        if left["end"] > right["start"]:
            raise SystemExit(f"overlapping patch targets: {left['part']} and {right['part']}")

    with source_sparse.open("rb") as header_fh:
        source_header = read_exact(header_fh, header.file_hdr_sz, "sparse file header")
    header_bytes = bytearray(source_header)
    struct.pack_into("<I", header_bytes, 20, 0)
    struct.pack_into("<I", header_bytes, 24, 0)

    chunk_count = 0
    with source_sparse.open("rb") as src_fh, out_sparse.open("wb") as out_fh:
        target_fhs = []
        try:
            for target in targets:
                fh = target["image"].open("rb")
                target["fh"] = fh
                target_fhs.append(fh)

            out_fh.write(header_bytes)
            for chunk in chunks:
                if chunk.chunk_type == CHUNK_CRC32:
                    continue
                pos = chunk.logical_start_block
                end = chunk.logical_end_block
                while pos < end:
                    active = next((target for target in targets if target["start"] <= pos < target["end"]), None)
                    if active is not None:
                        sub_end = min(end, active["end"])
                        image_offset = (pos - active["start"]) * header.blk_sz
                        write_raw_range_from_image(active["fh"], out_fh, header, image_offset, sub_end - pos)
                        chunk_count += 1
                        pos = sub_end
                        continue
                    next_target_start = min(
                        [target["start"] for target in targets if target["start"] > pos] + [end]
                    )
                    sub_end = min(end, next_target_start)
                    write_original_range(src_fh, out_fh, header, chunk, pos, sub_end)
                    chunk_count += 1
                    pos = sub_end
        finally:
            for fh in target_fhs:
                fh.close()

    # The R2 sparse supers currently use checksum=0 and no CRC chunk. If this
    # ever changes, append/update a CRC chunk in a focused follow-up instead of
    # guessing what the bootloader accepts.
    if header.image_checksum != 0 or any(chunk.chunk_type == CHUNK_CRC32 for chunk in chunks):
        raise SystemExit("sparse CRC chunks/checksums are not supported by rewrite mode yet")

    with out_sparse.open("r+b") as out_fh:
        out_fh.seek(20)
        out_fh.write(struct.pack("<I", chunk_count))

    manifest = [
        "patch_mode=rewrite-sparse",
        f"rewrite_chunk_count={chunk_count}",
    ]
    for part, image in images:
        slice_hash = hash_sparse_extent(out_sparse, *parse_sparse(out_sparse), EXTENTS[part])
        if slice_hash != image_hashes[part]:
            raise SystemExit(f"{part} sparse slice hash mismatch: {slice_hash} != {image_hashes[part]}")
        manifest.extend(
            [
                f"{part}_image={image}",
                f"{part}_sha256={image_hashes[part]}",
                f"{part}_slice_sha256={slice_hash}",
            ]
        )
    return manifest


def patch_image(out_sparse: Path, header: SparseHeader, chunks: list[Chunk], part: str, image: Path) -> str:
    extent = EXTENTS[part]
    size = image.stat().st_size
    if size != extent.byte_size:
        raise SystemExit(f"{part} image size mismatch: {size} != expected {extent.byte_size}")
    plan = raw_plan(header, chunks, extent)
    with image.open("rb") as src, out_sparse.open("r+b") as dst:
        for _chunk, file_offset, image_offset, byte_count in plan:
            src.seek(image_offset)
            dst.seek(file_offset)
            remaining = byte_count
            while remaining:
                data = src.read(min(1024 * 1024, remaining))
                if not data:
                    raise SystemExit(f"truncated image while patching {image}")
                dst.write(data)
                remaining -= len(data)
    return sha256_file(image)


def hash_sparse_extent(path: Path, header: SparseHeader, chunks: list[Chunk], extent: Extent) -> str:
    plan = raw_plan(header, chunks, extent)
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for _chunk, file_offset, _image_offset, byte_count in plan:
            fh.seek(file_offset)
            remaining = byte_count
            while remaining:
                data = fh.read(min(1024 * 1024, remaining))
                if len(data) == 0:
                    raise SystemExit(f"truncated sparse image while hashing {path}")
                h.update(data)
                remaining -= len(data)
    return h.hexdigest()


def hash_sparse_logical_extent(path: Path, header: SparseHeader, chunks: list[Chunk], extent: Extent) -> str:
    if extent.byte_offset % header.blk_sz != 0 or extent.byte_size % header.blk_sz != 0:
        raise SystemExit("partition extent is not sparse-block aligned")
    start_block = extent.byte_offset // header.blk_sz
    end_block = start_block + extent.byte_size // header.blk_sz
    cursor = start_block
    h = hashlib.sha256()
    zero_block = b"\x00" * header.blk_sz
    with path.open("rb") as fh:
        for chunk in chunks:
            if chunk.chunk_type == CHUNK_CRC32:
                continue
            if chunk.logical_end_block <= cursor:
                continue
            if chunk.logical_start_block >= end_block:
                break
            overlap_start = max(cursor, chunk.logical_start_block)
            overlap_end = min(end_block, chunk.logical_end_block)
            if overlap_start >= overlap_end:
                continue
            blocks = overlap_end - overlap_start
            if chunk.chunk_type == CHUNK_RAW:
                file_offset = chunk.data_offset + (overlap_start - chunk.logical_start_block) * header.blk_sz
                fh.seek(file_offset)
                remaining = blocks * header.blk_sz
                while remaining:
                    data = fh.read(min(1024 * 1024, remaining))
                    if not data:
                        raise SystemExit(f"truncated sparse image while hashing {path}")
                    h.update(data)
                    remaining -= len(data)
            elif chunk.chunk_type == CHUNK_FILL:
                fh.seek(chunk.data_offset)
                fill = read_exact(fh, 4, f"fill value for chunk {chunk.index}")
                block = fill * (header.blk_sz // 4)
                for _ in range(blocks):
                    h.update(block)
            elif chunk.chunk_type == CHUNK_DONT_CARE:
                for _ in range(blocks):
                    h.update(zero_block)
            else:
                raise SystemExit(f"cannot hash sparse chunk type {chunk_name(chunk.chunk_type)}")
            cursor = overlap_end
    if cursor != end_block:
        raise SystemExit(f"partition range not fully covered by sparse chunks: stopped at block {cursor}")
    return h.hexdigest()


def extract_sparse_logical_extent(path: Path, part: str, out_image: Path) -> str:
    if out_image.exists():
        raise SystemExit(f"output already exists: {out_image}")
    out_image.parent.mkdir(parents=True, exist_ok=True)

    header, chunks = parse_sparse(path)
    extent = EXTENTS[part]
    if extent.byte_offset % header.blk_sz != 0 or extent.byte_size % header.blk_sz != 0:
        raise SystemExit("partition extent is not sparse-block aligned")
    start_block = extent.byte_offset // header.blk_sz
    end_block = start_block + extent.byte_size // header.blk_sz
    cursor = start_block
    zero_block = b"\x00" * header.blk_sz

    with path.open("rb") as src_fh, out_image.open("wb") as out_fh:
        for chunk in chunks:
            if chunk.chunk_type == CHUNK_CRC32:
                continue
            if chunk.logical_end_block <= cursor:
                continue
            if chunk.logical_start_block >= end_block:
                break
            overlap_start = max(cursor, chunk.logical_start_block)
            overlap_end = min(end_block, chunk.logical_end_block)
            if overlap_start >= overlap_end:
                continue
            if overlap_start != cursor:
                raise SystemExit(f"partition range has a logical gap before block {overlap_start}")
            blocks = overlap_end - overlap_start
            if chunk.chunk_type == CHUNK_RAW:
                file_offset = chunk.data_offset + (overlap_start - chunk.logical_start_block) * header.blk_sz
                src_fh.seek(file_offset)
                copy_bytes(src_fh, out_fh, blocks * header.blk_sz)
            elif chunk.chunk_type == CHUNK_FILL:
                src_fh.seek(chunk.data_offset)
                fill = read_exact(src_fh, 4, f"fill value for chunk {chunk.index}")
                block = fill * (header.blk_sz // 4)
                for _ in range(blocks):
                    out_fh.write(block)
            elif chunk.chunk_type == CHUNK_DONT_CARE:
                for _ in range(blocks):
                    out_fh.write(zero_block)
            else:
                raise SystemExit(f"cannot extract sparse chunk type {chunk_name(chunk.chunk_type)}")
            cursor = overlap_end

    if cursor != end_block:
        out_image.unlink(missing_ok=True)
        raise SystemExit(f"partition range not fully covered by sparse chunks: stopped at block {cursor}")
    if out_image.stat().st_size != extent.byte_size:
        out_image.unlink(missing_ok=True)
        raise SystemExit(f"{part} extracted size mismatch: {out_image.stat().st_size} != {extent.byte_size}")
    return sha256_file(out_image)


def compute_logical_crc32(path: Path, header: SparseHeader, chunks: list[Chunk]) -> int:
    crc = 0
    zero_block = b"\x00" * header.blk_sz
    with path.open("rb") as fh:
        for chunk in chunks:
            if chunk.chunk_type == CHUNK_CRC32:
                continue
            if chunk.chunk_type == CHUNK_RAW:
                fh.seek(chunk.data_offset)
                remaining = chunk.block_count * header.blk_sz
                while remaining:
                    data = fh.read(min(1024 * 1024, remaining))
                    if not data:
                        raise SystemExit(f"truncated RAW chunk while computing CRC: {path}")
                    crc = binascii.crc32(data, crc)
                    remaining -= len(data)
            elif chunk.chunk_type == CHUNK_FILL:
                fh.seek(chunk.data_offset)
                fill = fh.read(4)
                if len(fill) != 4:
                    raise SystemExit(f"truncated FILL chunk while computing CRC: {path}")
                block = fill * (header.blk_sz // 4)
                for _ in range(chunk.block_count):
                    crc = binascii.crc32(block, crc)
            elif chunk.chunk_type == CHUNK_DONT_CARE:
                for _ in range(chunk.block_count):
                    crc = binascii.crc32(zero_block, crc)
    return crc & 0xFFFFFFFF


def update_checksums_if_needed(path: Path, header: SparseHeader, chunks: list[Chunk]) -> int | None:
    has_crc_chunk = any(chunk.chunk_type == CHUNK_CRC32 for chunk in chunks)
    if header.image_checksum == 0 and not has_crc_chunk:
        return None
    crc = compute_logical_crc32(path, header, chunks)
    with path.open("r+b") as fh:
        fh.seek(24)
        fh.write(struct.pack("<I", crc))
        for chunk in chunks:
            if chunk.chunk_type == CHUNK_CRC32:
                fh.seek(chunk.data_offset)
                fh.write(struct.pack("<I", crc))
    return crc


def print_summary(path: Path, part: str | None) -> None:
    header, chunks = parse_sparse(path)
    print(f"sparse={path}")
    print(f"block_size={header.blk_sz}")
    print(f"total_blocks={header.total_blks}")
    print(f"total_chunks={header.total_chunks}")
    print(f"image_checksum=0x{header.image_checksum:08x}")
    counts: dict[str, int] = {}
    for chunk in chunks:
        counts[chunk_name(chunk.chunk_type)] = counts.get(chunk_name(chunk.chunk_type), 0) + 1
    print("chunk_counts=" + ",".join(f"{key}:{value}" for key, value in sorted(counts.items())))
    if part:
        extent = EXTENTS[part]
        plan = raw_plan(header, chunks, extent)
        print(f"partition={part}")
        print(f"byte_offset={extent.byte_offset}")
        print(f"byte_size={extent.byte_size}")
        print(f"raw_segments={len(plan)}")
        for chunk, file_offset, image_offset, byte_count in plan:
            print(
                f"segment chunk={chunk.index} file_offset={file_offset} "
                f"image_offset={image_offset} bytes={byte_count}"
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-sparse", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--image", action="append", type=parse_image_arg, default=[], help="PARTITION=IMAGE")
    parser.add_argument("--verify-image", action="append", type=parse_image_arg, default=[], help="PARTITION=IMAGE")
    parser.add_argument("--extract-image", action="append", type=parse_extract_arg, default=[], help="PARTITION=OUT_IMAGE")
    parser.add_argument(
        "--extent",
        action="append",
        type=parse_extent_arg,
        default=[],
        help="override a built-in extent as PARTITION=START_SECTOR:SECTOR_COUNT",
    )
    parser.add_argument("--print-map", action="store_true")
    parser.add_argument("--partition", choices=sorted(EXTENTS))
    parser.add_argument("--variant", default="sparse-partition-patch")
    args = parser.parse_args()

    for part, extent in args.extent:
        EXTENTS[part] = extent

    if not args.source_sparse.is_file():
        raise SystemExit(f"missing source sparse image: {args.source_sparse}")

    if args.print_map:
        print_summary(args.source_sparse, args.partition)
        return

    if args.image and not args.out:
        raise SystemExit("--out is required when patching")
    if args.out and not args.image:
        raise SystemExit("--image PARTITION=IMAGE is required when --out is used")

    if args.extract_image:
        for part, out_image in args.extract_image:
            image_hash = extract_sparse_logical_extent(args.source_sparse, part, out_image)
            print(f"{part}\textracted={image_hash}\t{out_image}")

    if args.image:
        header, chunks = parse_sparse(args.source_sparse)
        manifest: list[str] = [
            f"variant={args.variant}",
            f"source_sparse={args.source_sparse}",
            f"out_sparse={args.out}",
            f"block_size={header.blk_sz}",
            f"total_blocks={header.total_blks}",
        ]
        patched_parts = [part for part, _image in args.image]
        try:
            for part, _image in args.image:
                raw_plan(header, chunks, EXTENTS[part])
            clone_sparse(args.source_sparse, args.out)
            manifest.append("patch_mode=clone-raw")
            for part, image in args.image:
                image_hash = patch_image(args.out, header, chunks, part, image)
                slice_hash = hash_sparse_extent(args.out, header, chunks, EXTENTS[part])
                if slice_hash != image_hash:
                    raise SystemExit(f"{part} sparse slice hash mismatch: {slice_hash} != {image_hash}")
                plan = raw_plan(header, chunks, EXTENTS[part])
                manifest.extend(
                    [
                        f"{part}_image={image}",
                        f"{part}_sha256={image_hash}",
                        f"{part}_slice_sha256={slice_hash}",
                        f"{part}_raw_segments={len(plan)}",
                    ]
                )
            crc = update_checksums_if_needed(args.out, header, chunks)
            if crc is not None:
                manifest.append(f"updated_sparse_crc32=0x{crc:08x}")
        except SystemExit as exc:
            if args.out.exists():
                args.out.unlink()
            reason = str(exc)
            manifest.append(f"clone_raw_unavailable={reason}")
            manifest.extend(rewrite_sparse_with_images(args.source_sparse, args.out, args.image))
        manifest.extend(
            [
                f"patched_partitions={','.join(patched_parts)}",
                f"out_sparse_sha256={sha256_file(args.out)}",
                f"source_sparse_sha256={sha256_file(args.source_sparse)}",
                "",
            ]
        )
        args.out.with_suffix(args.out.suffix + ".SHA256SUMS.txt").write_text(
            "\n".join(manifest), encoding="utf-8"
        )
        print(f"built: {args.out}")
        print(f"manifest: {args.out}.SHA256SUMS.txt")

    if args.verify_image:
        header, chunks = parse_sparse(args.source_sparse)
        for part, image in args.verify_image:
            image_hash = sha256_file(image)
            slice_hash = hash_sparse_logical_extent(args.source_sparse, header, chunks, EXTENTS[part])
            print(f"{part}\timage={image_hash}\tsparse_slice={slice_hash}\t{image}")
            if image_hash != slice_hash:
                raise SystemExit(f"{part} sparse slice hash mismatch")


if __name__ == "__main__":
    main()
