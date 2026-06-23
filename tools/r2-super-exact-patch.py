#!/usr/bin/env python3
"""Patch one or more B-slot dynamic partitions inside an exact-current super.

This is a generic helper for future hard-ROM variants. It does not rebuild the
dynamic partition layout; it copies an existing raw super image and overwrites
known partition extents in place.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCAL_SOURCE_SUPER = ROOT / "backups" / "2026-06-17-before-hardrom-super" / "super-current-before-hardrom.img"
SSD_SOURCE_SUPER = (
    Path("/Volumes/SSDUSB")
    / "Smartisax"
    / "archive"
    / "2026-06-18-rom-cold-backups"
    / "backups"
    / "2026-06-17-before-hardrom-super"
    / "super-current-before-hardrom.img"
)
LPDUMP = ROOT / "third_party" / "lpunpack_and_lpmake_cmake" / "bin" / "lpdump"


@dataclass(frozen=True)
class Extent:
    start_sector: int
    sectors: int
    max_bytes: int

    @property
    def seek_4096(self) -> int:
        return self.start_sector // 8

    @property
    def count_4096(self) -> int:
        return self.sectors // 8


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


def sha256_slice(path: Path, extent: Extent) -> str:
    h = hashlib.sha256()
    remaining = extent.count_4096
    with path.open("rb") as fh:
        fh.seek(extent.seek_4096 * 4096)
        while remaining:
            blocks = min(remaining, 1024)
            data = fh.read(blocks * 4096)
            if len(data) != blocks * 4096:
                raise SystemExit(f"truncated super while reading slice: {path}")
            h.update(data)
            remaining -= blocks
    return h.hexdigest()


def resolve_source_super(arg: str | None) -> Path:
    if arg:
        path = Path(arg)
        if not path.is_file():
            raise SystemExit(f"missing source super: {path}")
        return path
    if LOCAL_SOURCE_SUPER.is_file():
        return LOCAL_SOURCE_SUPER
    if SSD_SOURCE_SUPER.is_file():
        return SSD_SOURCE_SUPER
    raise SystemExit(
        "missing source super. Restore the cold backup or pass --source-super. "
        f"Tried {LOCAL_SOURCE_SUPER} and {SSD_SOURCE_SUPER}"
    )


def parse_image_arg(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected PARTITION=IMAGE")
    part, image = value.split("=", 1)
    if part not in EXTENTS:
        raise argparse.ArgumentTypeError(f"unknown partition {part}; expected one of {', '.join(EXTENTS)}")
    path = Path(image)
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"missing image: {path}")
    return part, path


def copy_source(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["cp", "-c", str(src), str(dst)], check=True)
    except Exception:
        shutil.copyfile(src, dst)


def patch_partition(super_img: Path, part: str, image: Path) -> tuple[str, str]:
    extent = EXTENTS[part]
    size = image.stat().st_size
    if size > extent.max_bytes:
        raise SystemExit(f"{part} image too large: {size} > {extent.max_bytes}")
    source_hash = sha256_file(image)
    with image.open("rb") as src, super_img.open("r+b") as dst:
        dst.seek(extent.seek_4096 * 4096)
        shutil.copyfileobj(src, dst, length=1024 * 1024)
    slice_hash = sha256_slice(super_img, extent)
    if slice_hash != source_hash:
        raise SystemExit(f"{part} hash mismatch: slice={slice_hash} source={source_hash}")
    return source_hash, slice_hash


def write_lpdump(out: Path) -> None:
    if not LPDUMP.is_file():
        return
    for slot in ("0", "1"):
        with (out.with_suffix(out.suffix + f".lpdump-slot{slot}.txt")).open("w", encoding="utf-8") as fh:
            subprocess.run([str(LPDUMP), "-s", slot, str(out)], text=True, stdout=fh, stderr=subprocess.STDOUT)
    combined = out.with_suffix(out.suffix + ".lpdump.txt")
    with combined.open("w", encoding="utf-8") as target:
        for slot in ("0", "1"):
            target.write((out.with_suffix(out.suffix + f".lpdump-slot{slot}.txt")).read_text(encoding="utf-8"))


def print_layout() -> None:
    print("partition\tstart_sector\tsectors\tseek_4096\tcount_4096\tmax_bytes")
    for part, extent in EXTENTS.items():
        print(f"{part}\t{extent.start_sector}\t{extent.sectors}\t{extent.seek_4096}\t{extent.count_4096}\t{extent.max_bytes}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-super", default=None)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--image", action="append", type=parse_image_arg, default=[], help="PARTITION=IMAGE")
    parser.add_argument("--variant", default="custom-exact-current")
    parser.add_argument("--print-layout", action="store_true")
    args = parser.parse_args()

    if args.print_layout:
        print_layout()
        return
    if not args.out:
        raise SystemExit("--out is required")
    if not args.image:
        raise SystemExit("at least one --image PARTITION=IMAGE is required")

    source_super = resolve_source_super(args.source_super)
    copy_source(source_super, args.out)

    manifest_lines = [
        f"super_image={args.out}",
        f"source_super_image={source_super}",
        f"variant={args.variant}",
    ]
    for part, image in args.image:
        source_hash, slice_hash = patch_partition(args.out, part, image)
        manifest_lines.extend(
            [
                f"{part}_image={image}",
                f"{part}_sha256={source_hash}",
                f"{part}_slice_sha256={slice_hash}",
                f"{part}_start_sector={EXTENTS[part].start_sector}",
                f"{part}_sectors={EXTENTS[part].sectors}",
            ]
        )

    write_lpdump(args.out)
    manifest_lines.append("")
    manifest_lines.append(f"{sha256_file(args.out)}  {args.out}")
    manifest_lines.append(f"{sha256_file(source_super)}  {source_super}")
    args.out.with_suffix(args.out.suffix + ".SHA256SUMS.txt").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    print(f"built: {args.out}")
    print(f"manifest: {args.out}.SHA256SUMS.txt")


if __name__ == "__main__":
    main()
