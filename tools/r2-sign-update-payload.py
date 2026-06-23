#!/usr/bin/env python3
"""Sign an Android A/B update payload with a local RSA key.

This implements the metadata and payload signature layout used by update_engine
major version 2 payloads:

  CrAU | version | manifest_size | metadata_signature_size | manifest |
  metadata Signatures protobuf | payload data | payload Signatures protobuf

It intentionally only handles RSA keys and the simple one-signature case we use
for Smartisax OTA experiments.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import struct
import subprocess
import tempfile
from collections.abc import Iterable
from pathlib import Path


HEADER_SIZE = 24
MAGIC = b"CrAU"


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        to_write = value & 0x7F
        value >>= 7
        if value:
            out.append(to_write | 0x80)
        else:
            out.append(to_write)
            return bytes(out)


def protobuf_field_varint(field_number: int, value: int) -> bytes:
    return varint((field_number << 3) | 0) + varint(value)


def protobuf_field_bytes(field_number: int, value: bytes) -> bytes:
    return varint((field_number << 3) | 2) + varint(len(value)) + value


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


def filter_protobuf_fields(data: bytes, excluded_numbers: set[int]) -> bytes:
    out = bytearray()
    offset = 0
    while offset < len(data):
        start = offset
        key, offset = read_varint(data, offset)
        number = key >> 3
        wire_type = key & 0x7
        if wire_type == 0:
            _, offset = read_varint(data, offset)
        elif wire_type == 1:
            offset += 8
        elif wire_type == 2:
            length, offset = read_varint(data, offset)
            offset += length
        elif wire_type == 5:
            offset += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wire_type}")
        if number not in excluded_numbers:
            out += data[start:offset]
    return bytes(out)


def signatures_proto(signature: bytes) -> bytes:
    # update_metadata.proto:
    # message Signatures {
    #   message Signature { optional bytes data = 2; }
    #   repeated Signature signatures = 1;
    # }
    inner = b"\x12" + varint(len(signature)) + signature
    return b"\x0a" + varint(len(inner)) + inner


def dynamic_partition_metadata(group_spec: str, snapshot_enabled: bool) -> bytes:
    try:
        name, size_text, partitions_text = group_spec.split(":", 2)
        size = int(size_text, 0)
    except ValueError as exc:
        raise ValueError(
            "--dynamic-group must be formatted as name:size:partition,partition"
        ) from exc
    partitions = [item for item in partitions_text.split(",") if item]
    if not name or size < 0 or not partitions:
        raise ValueError("--dynamic-group requires a name, non-negative size, and partitions")

    group = bytearray()
    group += protobuf_field_bytes(1, name.encode("utf-8"))
    group += protobuf_field_varint(2, size)
    for partition in partitions:
        group += protobuf_field_bytes(3, partition.encode("utf-8"))

    metadata = bytearray()
    metadata += protobuf_field_bytes(1, bytes(group))
    metadata += protobuf_field_varint(2, 1 if snapshot_enabled else 0)
    return bytes(metadata)


def openssl_sign(key: Path, data: bytes) -> bytes:
    with tempfile.NamedTemporaryFile() as data_file, tempfile.NamedTemporaryFile() as sig_file:
        data_file.write(data)
        data_file.flush()
        subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-sign",
                str(key),
                "-out",
                sig_file.name,
                data_file.name,
            ],
            check=True,
        )
        sig_file.seek(0)
        return sig_file.read()


def openssl_sign_chunks(key: Path, chunks: Iterable[bytes | memoryview]) -> bytes:
    proc = subprocess.Popen(
        [
            "openssl",
            "dgst",
            "-sha256",
            "-sign",
            str(key),
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert proc.stdin is not None
    for chunk in chunks:
        proc.stdin.write(chunk)
    stdout, stderr = proc.communicate()
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(
            proc.returncode,
            proc.args,
            output=stdout,
            stderr=stderr,
        )
    return stdout


def b64_sha256(data: bytes) -> str:
    return base64.b64encode(hashlib.sha256(data).digest()).decode("ascii")


def b64_sha256_chunks(chunks: Iterable[bytes | memoryview]) -> str:
    digest = hashlib.sha256()
    for chunk in chunks:
        digest.update(chunk)
    return base64.b64encode(digest.digest()).decode("ascii")


def write_chunks(path: Path, chunks: Iterable[bytes | memoryview]) -> None:
    with path.open("wb") as out:
        for chunk in chunks:
            out.write(chunk)


def sign_payload(
    payload_in: Path,
    key: Path,
    max_timestamp: int | None,
    dynamic_group: str | None,
    snapshot_enabled: bool,
    include_payload_signature: bool,
) -> tuple[list[bytes | memoryview], str]:
    payload = payload_in.read_bytes()
    if len(payload) < HEADER_SIZE:
        raise ValueError("payload is too small")
    if payload[:4] != MAGIC:
        raise ValueError("payload magic is not CrAU")

    version = struct.unpack(">Q", payload[4:12])[0]
    if version != 2:
        raise ValueError(f"unsupported payload major version: {version}")

    manifest_size = struct.unpack(">Q", payload[12:20])[0]
    old_sig_size = struct.unpack(">I", payload[20:24])[0]
    metadata_size = HEADER_SIZE + manifest_size
    old_data_offset = metadata_size + old_sig_size
    if len(payload) < old_data_offset:
        raise ValueError("payload metadata/signature size exceeds file size")

    manifest = payload[HEADER_SIZE:metadata_size]
    excluded_fields: set[int] = set()
    if max_timestamp is not None:
        if max_timestamp < 0:
            raise ValueError("max_timestamp must be non-negative")
        excluded_fields.add(14)
    if dynamic_group is not None:
        excluded_fields.add(15)
    if excluded_fields:
        manifest = filter_protobuf_fields(manifest, excluded_fields)
    if max_timestamp is not None:
        # DeltaArchiveManifest.max_timestamp is field 14, optional int64.
        manifest += protobuf_field_varint(14, max_timestamp)
    if dynamic_group is not None:
        # DeltaArchiveManifest.dynamic_partition_metadata is field 15.
        manifest += protobuf_field_bytes(
            15, dynamic_partition_metadata(dynamic_group, snapshot_enabled)
        )
    data_blobs = memoryview(payload)[old_data_offset:]

    # Determine the RSA signature size without depending on the final metadata
    # bytes. RSA signatures have a fixed size equal to the key modulus length.
    dummy_signature = openssl_sign(key, b"")
    dummy_proto = signatures_proto(dummy_signature)
    if include_payload_signature:
        # DeltaArchiveManifest.signatures_offset/signatures_size point into the
        # payload data blob stream, where update_engine expects the serialized
        # Signatures message after all install operation data.
        manifest = filter_protobuf_fields(manifest, {4, 5})
        manifest += protobuf_field_varint(4, len(data_blobs))
        manifest += protobuf_field_varint(5, len(dummy_proto))

    header = (
        MAGIC
        + struct.pack(">Q", version)
        + struct.pack(">Q", len(manifest))
        + struct.pack(">I", len(dummy_proto))
    )
    signed_metadata = header + manifest
    signature = openssl_sign(key, signed_metadata)
    signature_proto = signatures_proto(signature)
    if len(signature_proto) != len(dummy_proto):
        raise ValueError("signature protobuf size changed unexpectedly")

    payload_signature_proto = b""
    if include_payload_signature:
        payload_signature = openssl_sign_chunks(key, [signed_metadata, data_blobs])
        payload_signature_proto = signatures_proto(payload_signature)
        if len(payload_signature_proto) != len(dummy_proto):
            raise ValueError("payload signature protobuf size changed unexpectedly")

    signed_payload_chunks = [
        signed_metadata,
        signature_proto,
        data_blobs,
        payload_signature_proto,
    ]
    signed_payload_size = sum(len(chunk) for chunk in signed_payload_chunks)
    properties = "\n".join(
        [
            f"FILE_HASH={b64_sha256_chunks(signed_payload_chunks)}",
            f"FILE_SIZE={signed_payload_size}",
            f"METADATA_HASH={b64_sha256(signed_metadata)}",
            f"METADATA_SIZE={len(signed_metadata)}",
        ]
    )
    return signed_payload_chunks, properties + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload-in", required=True, type=Path)
    parser.add_argument("--payload-out", required=True, type=Path)
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--properties-out", required=True, type=Path)
    parser.add_argument("--max-timestamp", type=int)
    parser.add_argument(
        "--dynamic-group",
        help="Replace manifest dynamic metadata, formatted as name:size:partition,partition",
    )
    parser.add_argument("--snapshot-enabled", action="store_true")
    parser.add_argument(
        "--no-payload-signature",
        action="store_true",
        help="Only sign metadata; for live OTA installs the payload signature is required",
    )
    args = parser.parse_args()

    signed_payload_chunks, properties = sign_payload(
        args.payload_in,
        args.key,
        args.max_timestamp,
        args.dynamic_group,
        args.snapshot_enabled,
        not args.no_payload_signature,
    )
    args.payload_out.parent.mkdir(parents=True, exist_ok=True)
    args.properties_out.parent.mkdir(parents=True, exist_ok=True)
    write_chunks(args.payload_out, signed_payload_chunks)
    args.properties_out.write_text(properties, encoding="ascii")
    os.chmod(args.payload_out, 0o644)
    os.chmod(args.properties_out, 0o644)


if __name__ == "__main__":
    main()
