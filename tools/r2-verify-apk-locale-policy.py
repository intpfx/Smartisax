#!/usr/bin/env python3
"""Verify locale config chunks inside APK resources.arsc files.

This is a read-only verifier for Smartisax locale-prune candidates. It
parses the binary Android resource table directly and fails if any localized
RES_TABLE_TYPE_TYPE chunk uses a language outside the allowed set.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

RES_STRING_POOL_TYPE = 0x0001
RES_TABLE_TYPE = 0x0002
RES_TABLE_PACKAGE_TYPE = 0x0200
RES_TABLE_TYPE_TYPE = 0x0201


@dataclass(frozen=True)
class Chunk:
    type: int
    header_size: int
    size: int


def u16(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes | bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


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
        first &= 0x7F
        chars = [
            chr(((first >> 2) & 0x1F) + ord("a")),
            chr((((first & 0x03) << 3) | ((second >> 5) & 0x07)) + ord("a")),
            chr((second & 0x1F) + ord("a")),
        ]
        return "".join(chars)
    return two.decode("ascii", "ignore").rstrip("\x00")


def chunk_locale(data: bytes | bytearray, offset: int) -> tuple[str, str, str]:
    config_offset = offset + 20
    config_size = u32(data, config_offset)
    if config_size < 12:
        raise ValueError(f"unexpected ResTable_config size {config_size} at {offset}")
    raw_lang = bytes(data[config_offset + 8 : config_offset + 10])
    raw_region = bytes(data[config_offset + 10 : config_offset + 12])
    language = decode_packed_locale(raw_lang)
    region = decode_packed_locale(raw_region)
    return language, region, (raw_lang + raw_region).hex()


def type_names(data: bytes | bytearray, package_offset: int) -> list[str]:
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


def package_subchunk_start(data: bytes | bytearray, package_offset: int) -> int:
    key_strings_offset = u32(data, package_offset + 276)
    key_pool_offset = package_offset + key_strings_offset
    return key_pool_offset + parse_string_pool_size(data, key_pool_offset)


def read_resources_arsc(apk: Path) -> bytes | None:
    with zipfile.ZipFile(apk) as zf:
        try:
            return zf.read("resources.arsc")
        except KeyError:
            return None


def scan_arsc(data: bytes) -> list[dict[str, Any]]:
    table = read_chunk(data, 0)
    if table.type != RES_TABLE_TYPE:
        raise ValueError(f"not a RES_TABLE_TYPE file: 0x{table.type:04x}")

    records: list[dict[str, Any]] = []
    cursor = table.header_size
    while cursor < len(data):
        chunk = read_chunk(data, cursor)
        if chunk.type != RES_TABLE_PACKAGE_TYPE:
            cursor += chunk.size
            continue

        package_name = read_utf16_name(data, cursor + 12, 128)
        names = type_names(data, cursor)
        sub_cursor = package_subchunk_start(data, cursor)
        while sub_cursor < cursor + chunk.size:
            sub = read_chunk(data, sub_cursor)
            if sub.type == RES_TABLE_TYPE_TYPE:
                type_id = data[sub_cursor + 8]
                language, region, raw_locale = chunk_locale(data, sub_cursor)
                type_name = names[type_id - 1] if 0 < type_id <= len(names) else f"type_{type_id}"
                if language:
                    records.append(
                        {
                            "package": package_name,
                            "type_id": type_id,
                            "type_name": type_name,
                            "language": language,
                            "region": region,
                            "raw_locale": raw_locale,
                            "offset": sub_cursor,
                            "size": sub.size,
                        }
                    )
            sub_cursor += sub.size
        cursor += chunk.size
    return records


def summarize(apk: Path, keep_languages: set[str], allow_no_resources: bool) -> dict[str, Any]:
    arsc = read_resources_arsc(apk)
    if arsc is None:
        if allow_no_resources:
            return {
                "apk": str(apk),
                "has_resources_arsc": False,
                "locale_chunk_count": 0,
                "bad_locale_chunk_count": 0,
                "languages": [],
                "bad": [],
            }
        raise ValueError(f"{apk}: missing resources.arsc")

    records = scan_arsc(arsc)
    bad = [row for row in records if row["language"] not in keep_languages]
    languages = sorted({row["language"] for row in records})
    kept_languages = sorted({row["language"] for row in records if row["language"] in keep_languages})
    return {
        "apk": str(apk),
        "has_resources_arsc": True,
        "resources_arsc_size": len(arsc),
        "keep_languages": sorted(keep_languages),
        "locale_chunk_count": len(records),
        "bad_locale_chunk_count": len(bad),
        "languages": languages,
        "kept_languages": kept_languages,
        "bad": bad,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", nargs="+", help="APK(s) to verify")
    parser.add_argument("--keep-languages", default="en,zh", help="Comma-separated language codes to keep")
    parser.add_argument("--allow-no-resources", action="store_true", help="Do not fail for APKs without resources.arsc")
    parser.add_argument("--report", help="Optional JSON report path")
    args = parser.parse_args()

    keep_languages = {item.strip() for item in args.keep_languages.split(",") if item.strip()}
    reports: list[dict[str, Any]] = []
    failed = False

    for raw_apk in args.apk:
        apk = Path(raw_apk)
        if not apk.is_file():
            print(f"error: missing APK: {apk}", file=sys.stderr)
            failed = True
            continue
        try:
            report = summarize(apk, keep_languages, args.allow_no_resources)
        except Exception as exc:
            print(f"error: {exc}", file=sys.stderr)
            failed = True
            continue
        reports.append(report)
        print(f"apk={apk}")
        print(f"has_resources_arsc={str(report['has_resources_arsc']).lower()}")
        print(f"locale_chunk_count={report['locale_chunk_count']}")
        print(f"languages={','.join(report['languages'])}")
        print(f"bad_locale_chunk_count={report['bad_locale_chunk_count']}")
        if report["bad"]:
            failed = True
            for row in report["bad"][:40]:
                print(
                    "bad={type_name}:{language}_{region}:offset={offset}:size={size}".format(**row),
                    file=sys.stderr,
                )
        print()

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(reports, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
