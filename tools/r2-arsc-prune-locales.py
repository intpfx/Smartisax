#!/usr/bin/env python3
"""Remove non-target locale config chunks from an Android resources.arsc file.

This is intentionally narrow: it preserves package/type/key string pools,
type-spec chunks, entry IDs, and entry payload bytes. It only removes
RES_TABLE_TYPE_TYPE chunks whose ResTable_config language is outside the keep
set. That makes it useful for framework packages that apktool/aapt2 cannot
rebuild without changing private resource type identity.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path

RES_STRING_POOL_TYPE = 0x0001
RES_TABLE_TYPE = 0x0002
RES_TABLE_PACKAGE_TYPE = 0x0200
RES_TABLE_TYPE_TYPE = 0x0201
RES_TABLE_TYPE_SPEC_TYPE = 0x0202


@dataclass(frozen=True)
class Chunk:
    type: int
    header_size: int
    size: int


def u16(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def write_u32(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", data, offset, value)


def read_chunk(data: bytes | bytearray, offset: int) -> Chunk:
    if offset + 8 > len(data):
        raise ValueError(f"chunk header beyond EOF at {offset}")
    chunk = Chunk(u16(data, offset), u16(data, offset + 2), u32(data, offset + 4))
    if chunk.size < chunk.header_size or chunk.header_size < 8:
        raise ValueError(f"invalid chunk at {offset}: {chunk}")
    if offset + chunk.size > len(data):
        raise ValueError(f"chunk beyond EOF at {offset}: {chunk}")
    return chunk


def read_utf16_name(data: bytes | bytearray, offset: int, chars: int) -> str:
    raw = bytes(data[offset : offset + chars * 2])
    return raw.decode("utf-16le", "ignore").split("\x00", 1)[0]


def parse_string_pool_size(data: bytes | bytearray, offset: int) -> int:
    chunk = read_chunk(data, offset)
    if chunk.type != RES_STRING_POOL_TYPE:
        raise ValueError(f"expected string pool at {offset}, got 0x{chunk.type:04x}")
    return chunk.size


def decode_packed_locale(two: bytes) -> str:
    if len(two) != 2 or two == b"\x00\x00":
        return ""
    first, second = two
    if first & 0x80:
        # ResTable_config packs three lowercase letters into two bytes.
        first &= 0x7F
        chars = [
            chr(((first >> 2) & 0x1F) + ord("a")),
            chr((((first & 0x03) << 3) | ((second >> 5) & 0x07)) + ord("a")),
            chr((second & 0x1F) + ord("a")),
        ]
        return "".join(chars)
    return two.decode("ascii", "ignore").rstrip("\x00")


def chunk_locale(data: bytes | bytearray, offset: int) -> tuple[str, str, str]:
    # ResTable_type starts with an 8-byte chunk header, then:
    # id/res0/res1/entryCount/entriesStart, followed by ResTable_config.
    config_offset = offset + 20
    config_size = u32(data, config_offset)
    if config_size < 12:
        raise ValueError(f"unexpected ResTable_config size {config_size} at {offset}")
    raw_lang = bytes(data[config_offset + 8 : config_offset + 10])
    raw_region = bytes(data[config_offset + 10 : config_offset + 12])
    language = decode_packed_locale(raw_lang)
    region = decode_packed_locale(raw_region)
    return language, region, (raw_lang + raw_region).hex()


def type_names(data: bytes | bytearray, package_offset: int, package_chunk: Chunk) -> list[str]:
    type_strings_offset = u32(data, package_offset + 268)
    string_pool_offset = package_offset + type_strings_offset
    chunk = read_chunk(data, string_pool_offset)
    if chunk.type != RES_STRING_POOL_TYPE:
        return []

    string_count = u32(data, string_pool_offset + 8)
    flags = u32(data, string_pool_offset + 16)
    strings_start = u32(data, string_pool_offset + 20)
    utf8 = bool(flags & 0x100)
    offsets_base = string_pool_offset + chunk.header_size
    strings_base = string_pool_offset + strings_start

    names: list[str] = []
    for index in range(string_count):
        relative = u32(data, offsets_base + index * 4)
        cursor = strings_base + relative
        if utf8:
            _utf16_len, cursor = read_len8(data, cursor)
            byte_len, cursor = read_len8(data, cursor)
            names.append(bytes(data[cursor : cursor + byte_len]).decode("utf-8", "replace"))
        else:
            char_len, cursor = read_len16(data, cursor)
            names.append(bytes(data[cursor : cursor + char_len * 2]).decode("utf-16le", "replace"))
    return names


def read_len8(data: bytes | bytearray, offset: int) -> tuple[int, int]:
    first = data[offset]
    if first & 0x80:
        return ((first & 0x7F) << 8) | data[offset + 1], offset + 2
    return first, offset + 1


def read_len16(data: bytes | bytearray, offset: int) -> tuple[int, int]:
    first = u16(data, offset)
    if first & 0x8000:
        return ((first & 0x7FFF) << 16) | u16(data, offset + 2), offset + 4
    return first, offset + 2


def package_subchunk_start(data: bytes | bytearray, package_offset: int) -> int:
    key_strings_offset = u32(data, package_offset + 276)
    key_pool_offset = package_offset + key_strings_offset
    return key_pool_offset + parse_string_pool_size(data, key_pool_offset)


def should_remove_locale(language: str, keep_languages: set[str]) -> bool:
    return bool(language) and language not in keep_languages


def prune(data: bytes, keep_languages: set[str]) -> tuple[bytes, dict[str, object]]:
    table = read_chunk(data, 0)
    if table.type != RES_TABLE_TYPE:
        raise ValueError(f"not a RES_TABLE_TYPE file: 0x{table.type:04x}")

    cursor = table.header_size
    output = bytearray(data[: table.header_size])
    removed: list[dict[str, object]] = []
    kept_locale: list[dict[str, object]] = []

    while cursor < len(data):
        chunk = read_chunk(data, cursor)
        if chunk.type != RES_TABLE_PACKAGE_TYPE:
            output.extend(data[cursor : cursor + chunk.size])
            cursor += chunk.size
            continue

        package_name = read_utf16_name(data, cursor + 12, 128)
        names = type_names(data, cursor, chunk)
        sub_start = package_subchunk_start(data, cursor)
        package_out = bytearray(data[cursor:sub_start])

        sub_cursor = sub_start
        while sub_cursor < cursor + chunk.size:
            sub = read_chunk(data, sub_cursor)
            if sub.type == RES_TABLE_TYPE_TYPE:
                type_id = data[sub_cursor + 8]
                language, region, raw_locale = chunk_locale(data, sub_cursor)
                type_name = names[type_id - 1] if 0 < type_id <= len(names) else f"type_{type_id}"
                record = {
                    "package": package_name,
                    "type_id": type_id,
                    "type_name": type_name,
                    "language": language,
                    "region": region,
                    "raw_locale": raw_locale,
                    "offset": sub_cursor,
                    "size": sub.size,
                }
                if should_remove_locale(language, keep_languages):
                    removed.append(record)
                    sub_cursor += sub.size
                    continue
                if language:
                    kept_locale.append(record)
            package_out.extend(data[sub_cursor : sub_cursor + sub.size])
            sub_cursor += sub.size

        write_u32(package_out, 4, len(package_out))
        output.extend(package_out)
        cursor += chunk.size

    write_u32(output, 4, len(output))
    report: dict[str, object] = {
        "input_size": len(data),
        "output_size": len(output),
        "removed_count": len(removed),
        "kept_locale_count": len(kept_locale),
        "removed": removed,
        "kept_locale": kept_locale,
        "keep_languages": sorted(keep_languages),
    }
    return bytes(output), report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="Input resources.arsc")
    parser.add_argument("output", help="Output resources.arsc")
    parser.add_argument("--keep-languages", default="en,zh", help="Comma-separated language codes to keep")
    parser.add_argument("--report", help="JSON report path")
    args = parser.parse_args()

    keep_languages = {item.strip() for item in args.keep_languages.split(",") if item.strip()}
    source = Path(args.input).read_bytes()
    result, report = prune(source, keep_languages)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_bytes(result)
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"input_size={report['input_size']}")
    print(f"output_size={report['output_size']}")
    print(f"removed_count={report['removed_count']}")
    print(f"kept_locale_count={report['kept_locale_count']}")


if __name__ == "__main__":
    main()
