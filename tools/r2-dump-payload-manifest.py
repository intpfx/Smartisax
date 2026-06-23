#!/usr/bin/env python3
"""Dump the parts of an Android A/B payload manifest we care about."""

from __future__ import annotations

import argparse
import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path


HEADER_SIZE = 24
MAGIC = b"CrAU"


INSTALL_OPERATION_TYPES = {
    0: "REPLACE",
    1: "REPLACE_BZ",
    2: "MOVE",
    3: "BSDIFF",
    4: "SOURCE_COPY",
    5: "SOURCE_BSDIFF",
    6: "ZERO",
    7: "DISCARD",
    8: "REPLACE_XZ",
    9: "PUFFDIFF",
    10: "BROTLI_BSDIFF",
}


@dataclass
class Field:
    number: int
    wire_type: int
    value: int | bytes


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    shift = 0
    value = 0
    while True:
        b = data[offset]
        offset += 1
        value |= (b & 0x7F) << shift
        if not b & 0x80:
            return value, offset
        shift += 7


def parse_fields(data: bytes) -> list[Field]:
    fields: list[Field] = []
    offset = 0
    while offset < len(data):
        key, offset = read_varint(data, offset)
        number = key >> 3
        wire_type = key & 0x7
        if wire_type == 0:
            value, offset = read_varint(data, offset)
        elif wire_type == 1:
            value = data[offset : offset + 8]
            offset += 8
        elif wire_type == 2:
            length, offset = read_varint(data, offset)
            value = data[offset : offset + length]
            offset += length
        elif wire_type == 5:
            value = data[offset : offset + 4]
            offset += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wire_type}")
        fields.append(Field(number, wire_type, value))
    return fields


def first_varint(fields: list[Field], number: int, default: int | None = None) -> int | None:
    for field in fields:
        if field.number == number and field.wire_type == 0:
            return int(field.value)
    return default


def first_bytes(fields: list[Field], number: int) -> bytes | None:
    for field in fields:
        if field.number == number and field.wire_type == 2:
            return bytes(field.value)
    return None


def all_bytes(fields: list[Field], number: int) -> list[bytes]:
    return [bytes(field.value) for field in fields if field.number == number and field.wire_type == 2]


def text(value: bytes | None) -> str:
    if value is None:
        return ""
    return value.decode("utf-8", errors="replace")


def partition_info_summary(raw: bytes | None) -> str:
    if raw is None:
        return "(missing)"
    fields = parse_fields(raw)
    size = first_varint(fields, 1, 0)
    digest = first_bytes(fields, 2)
    digest_text = digest.hex() if digest else ""
    return f"size={size} sha256={digest_text}"


def dump_partition_update(raw: bytes) -> None:
    fields = parse_fields(raw)
    name = text(first_bytes(fields, 1))
    run_postinstall = first_varint(fields, 2)
    new_info = partition_info_summary(first_bytes(fields, 7))
    operations = all_bytes(fields, 8)
    op_counts: dict[str, int] = {}
    total_data = 0
    for op_raw in operations:
        op_fields = parse_fields(op_raw)
        op_type = first_varint(op_fields, 1, 0)
        op_name = INSTALL_OPERATION_TYPES.get(op_type or 0, f"UNKNOWN_{op_type}")
        op_counts[op_name] = op_counts.get(op_name, 0) + 1
        total_data += first_varint(op_fields, 3, 0) or 0
    print(f"partition {name}: {new_info}")
    print(f"  run_postinstall={run_postinstall} operations={len(operations)} data_bytes={total_data}")
    print(f"  operation_types={op_counts}")


def dump_dynamic_metadata(raw: bytes | None) -> None:
    if raw is None:
        print("dynamic_partition_metadata: (missing)")
        return
    fields = parse_fields(raw)
    snapshot_enabled = first_varint(fields, 2)
    print(f"dynamic_partition_metadata: snapshot_enabled={snapshot_enabled}")
    for group_raw in all_bytes(fields, 1):
        group_fields = parse_fields(group_raw)
        name = text(first_bytes(group_fields, 1))
        size = first_varint(group_fields, 2, 0)
        partitions = [text(v) for v in all_bytes(group_fields, 3)]
        print(f"  group {name}: size={size} partitions={partitions}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    args = parser.parse_args()

    data = args.payload.read_bytes()
    if data[:4] != MAGIC:
        raise SystemExit("payload magic is not CrAU")
    version = struct.unpack(">Q", data[4:12])[0]
    manifest_size = struct.unpack(">Q", data[12:20])[0]
    metadata_signature_size = struct.unpack(">I", data[20:24])[0]
    manifest = data[HEADER_SIZE : HEADER_SIZE + manifest_size]
    metadata = data[: HEADER_SIZE + manifest_size]
    fields = parse_fields(manifest)
    print(f"payload={args.payload}")
    print(f"version={version}")
    print(f"manifest_size={manifest_size}")
    print(f"metadata_signature_size={metadata_signature_size}")
    print(f"metadata_size={len(metadata)}")
    print(f"metadata_sha256={hashlib.sha256(metadata).hexdigest()}")
    print(f"block_size={first_varint(fields, 3, 4096)}")
    print(f"signatures_offset={first_varint(fields, 4)}")
    print(f"signatures_size={first_varint(fields, 5)}")
    print(f"minor_version={first_varint(fields, 12, 0)}")
    print(f"max_timestamp={first_varint(fields, 14)}")
    dump_dynamic_metadata(first_bytes(fields, 15))
    for partition_raw in all_bytes(fields, 13):
        dump_partition_update(partition_raw)


if __name__ == "__main__":
    main()
