#!/usr/bin/env python3
"""Audit whether B-slot dynamic partitions have room to grow system_b.

This is a read-only planning helper. It parses local lpdump evidence and writes
reports. It does not rebuild super, resize filesystems, touch a device, flash,
reboot, erase partitions, write settings, or modify /data.
"""

from __future__ import annotations

import csv
import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LPDUMP_SLOT1 = ROOT / "hard-rom" / "preflight" / "lpdump-slot1-current.txt"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-super-capacity"
OUT_JSON = OUT_DIR / "webview-super-capacity-audit.json"
OUT_MD = ROOT / "docs" / "research" / "webview-super-capacity-audit.md"
OUT_TSV = ROOT / "reverse" / "smartisan-8.5.3-rom-static" / "manifest" / "webview-super-capacity-audit.tsv"

SECTOR_SIZE = 512
DEFAULT_GROWTH_BYTES = 128 * 1024 * 1024


@dataclass(frozen=True)
class Partition:
    name: str
    group: str
    start_sector: int
    sectors: int

    @property
    def end_sector(self) -> int:
        return self.start_sector + self.sectors

    @property
    def bytes(self) -> int:
        return self.sectors * SECTOR_SIZE


@dataclass(frozen=True)
class GroupSummary:
    group: str
    maximum_bytes: int
    allocated_bytes: int
    free_bytes: int
    free_mib: float


@dataclass(frozen=True)
class Hole:
    start_sector: int
    end_sector: int
    sectors: int
    bytes: int
    mib: float


@dataclass(frozen=True)
class Gate:
    gate: str
    status: str
    evidence: str
    next_step: str


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def die(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def parse_lpdump(path: Path) -> tuple[int, dict[str, int], dict[str, Partition]]:
    if not path.is_file():
        die(f"missing lpdump: {path}")
    text = path.read_text(encoding="utf-8")
    super_size = 0
    groups: dict[str, int] = {}
    partitions: dict[str, Partition] = {}

    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "Partition name: super":
            for subline in lines[index + 1 : index + 8]:
                match = re.match(r"\s+Size:\s+(\d+) bytes", subline)
                if match:
                    super_size = int(match.group(1))
                    break
        group_match = re.match(r"\s+Name:\s+(qti_dynamic_partitions_[ab]|default)$", line)
        if group_match:
            group = group_match.group(1)
            for subline in lines[index + 1 : index + 6]:
                size_match = re.match(r"\s+Maximum size:\s+(\d+) bytes", subline)
                if size_match:
                    groups[group] = int(size_match.group(1))
                    break

    current_name = ""
    current_group = ""
    for line in lines:
        name_match = re.match(r"\s+Name:\s+(\S+)$", line)
        if name_match:
            current_name = name_match.group(1)
            current_group = ""
            continue
        group_match = re.match(r"\s+Group:\s+(\S+)$", line)
        if group_match and current_name:
            current_group = group_match.group(1)
            continue
        extent_match = re.match(r"\s+0 \.\. (\d+) linear super (\d+)$", line)
        if extent_match and current_name and current_group:
            last_partition_sector = int(extent_match.group(1))
            start_sector = int(extent_match.group(2))
            partitions[current_name] = Partition(
                name=current_name,
                group=current_group,
                start_sector=start_sector,
                sectors=last_partition_sector + 1,
            )

    if not super_size:
        die(f"could not parse super size from {path}")
    return super_size, groups, partitions


def group_summaries(groups: dict[str, int], partitions: dict[str, Partition]) -> list[GroupSummary]:
    rows: list[GroupSummary] = []
    for group, maximum in sorted(groups.items()):
        if group == "default":
            continue
        allocated = sum(partition.bytes for partition in partitions.values() if partition.group == group)
        rows.append(
            GroupSummary(
                group=group,
                maximum_bytes=maximum,
                allocated_bytes=allocated,
                free_bytes=maximum - allocated,
                free_mib=(maximum - allocated) / 1024 / 1024,
            )
        )
    return rows


def physical_holes(super_size: int, partitions: dict[str, Partition]) -> list[Hole]:
    super_sectors = super_size // SECTOR_SIZE
    extents = sorted((partition.start_sector, partition.end_sector) for partition in partitions.values())
    holes: list[Hole] = []
    last = 2048
    for start, end in extents:
        if start > last:
            sectors = start - last
            holes.append(Hole(last, start, sectors, sectors * SECTOR_SIZE, sectors * SECTOR_SIZE / 1024 / 1024))
        last = max(last, end)
    if last < super_sectors:
        sectors = super_sectors - last
        holes.append(Hole(last, super_sectors, sectors, sectors * SECTOR_SIZE, sectors * SECTOR_SIZE / 1024 / 1024))
    return holes


def find_group(rows: list[GroupSummary], group: str) -> GroupSummary:
    for row in rows:
        if row.group == group:
            return row
    die(f"missing group summary: {group}")


def build_gates(
    super_size: int,
    groups: list[GroupSummary],
    partitions: dict[str, Partition],
    holes: list[Hole],
) -> list[Gate]:
    group_b = find_group(groups, "qti_dynamic_partitions_b")
    system_b = partitions.get("system_b")
    if not system_b:
        die("missing system_b partition in lpdump")
    tail_hole = max((hole for hole in holes if hole.start_sector >= system_b.end_sector), key=lambda h: h.bytes, default=None)
    physical_growth = tail_hole.bytes if tail_hole else 0
    growth_ceiling = min(group_b.free_bytes, physical_growth)
    proposed_growth = min(DEFAULT_GROWTH_BYTES, growth_ceiling)
    return [
        Gate(
            "SUPER-CAP-01-group-b-free-space",
            "PASS" if group_b.free_bytes > 0 else "BLOCKED",
            f"group_b_free={group_b.free_bytes}; group_b_free_mib={group_b.free_mib:.2f}",
            "Use group free space as the hard logical capacity ceiling for growing B-slot partitions.",
        ),
        Gate(
            "SUPER-CAP-02-physical-tail-hole",
            "PASS" if physical_growth > 0 else "BLOCKED",
            f"tail_hole_bytes={physical_growth}; super_size={super_size}; system_b_end_sector={system_b.end_sector}",
            "A full super rebuild can allocate a new system_b extent in the tail hole; exact-current slice patching cannot.",
        ),
        Gate(
            "SUPER-CAP-03-system-b-growth-ceiling",
            "FEASIBLE" if growth_ceiling >= DEFAULT_GROWTH_BYTES else "TIGHT_OR_BLOCKED",
            f"growth_ceiling={growth_ceiling}; proposed_growth={proposed_growth}; current_system_b={system_b.bytes}; proposed_system_b={system_b.bytes + proposed_growth}",
            "Prototype a no-content-change system_b growth image before combining it with WebView or debloat changes.",
        ),
        Gate(
            "SUPER-CAP-04-builder-risk-boundary",
            "REQUIRES_NEW_NOOP_GATE",
            "current exact-current builders overwrite existing logical slices and do not modify dynamic partition metadata",
            "Create a separate lpmake/lpadd-style metadata-resize builder and verify lpdump, ext4 resize, fsck, sparse flash, boot, rollback.",
        ),
    ]


def md_table(headers: list[str], rows: list[list[object]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|") for cell in row) + " |")
    return lines


def write_outputs(
    super_size: int,
    groups: list[GroupSummary],
    partitions: dict[str, Partition],
    holes: list[Hole],
    gates: list[Gate],
) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    system_b = partitions["system_b"]
    group_b = find_group(groups, "qti_dynamic_partitions_b")
    tail_hole = max((hole for hole in holes if hole.start_sector >= system_b.end_sector), key=lambda h: h.bytes, default=None)
    physical_growth = tail_hole.bytes if tail_hole else 0
    growth_ceiling = min(group_b.free_bytes, physical_growth)
    proposed_growth = min(DEFAULT_GROWTH_BYTES, growth_ceiling)
    verdict = "SYSTEM_B_DYNAMIC_GROWTH_FEASIBLE_REQUIRES_NOOP_GATE" if proposed_growth else "SYSTEM_B_DYNAMIC_GROWTH_BLOCKED"

    with OUT_TSV.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "name", "status", "bytes", "mib", "detail", "next_step"])
        for gate in gates:
            writer.writerow(["gate", gate.gate, gate.status, "", "", gate.evidence, gate.next_step])
        for group in groups:
            writer.writerow(["group", group.group, "", group.free_bytes, f"{group.free_mib:.2f}", f"allocated={group.allocated_bytes}; maximum={group.maximum_bytes}", ""])
        for partition in sorted(partitions.values(), key=lambda item: item.start_sector):
            writer.writerow(["partition", partition.name, partition.group, partition.bytes, f"{partition.bytes / 1024 / 1024:.2f}", f"start_sector={partition.start_sector}; sectors={partition.sectors}", ""])
        for hole in holes:
            writer.writerow(["hole", f"{hole.start_sector}..{hole.end_sector}", "", hole.bytes, f"{hole.mib:.2f}", f"sectors={hole.sectors}", ""])

    lines: list[str] = []
    lines.append("# WebView Super Capacity Audit")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline planning report. It does not rebuild `super`,")
    lines.append("resize filesystems, touch a device, flash, reboot, erase partitions, write")
    lines.append("settings, or modify `/data`.")
    lines.append("")
    lines.append("## Result")
    lines.append("")
    lines.append(
        "`system_b` can technically be grown inside the current dynamic `super` "
        "layout. Slot B's dynamic group still has unused capacity, and the "
        "physical super tail has a matching large hole. The current blocker is "
        "not raw NAND space; it is that our safest builders intentionally avoid "
        "changing logical partition metadata."
    )
    lines.append("")
    lines.append("## Capacity Summary")
    lines.append("")
    lines.extend(
        md_table(
            ["Item", "Bytes", "MiB"],
            [
                ["super size", super_size, f"{super_size / 1024 / 1024:.2f}"],
                ["system_b current size", system_b.bytes, f"{system_b.bytes / 1024 / 1024:.2f}"],
                ["qti_dynamic_partitions_b free", group_b.free_bytes, f"{group_b.free_mib:.2f}"],
                ["largest usable B-slot tail hole", physical_growth, f"{physical_growth / 1024 / 1024:.2f}"],
                ["system_b growth ceiling", growth_ceiling, f"{growth_ceiling / 1024 / 1024:.2f}"],
                ["suggested first no-op growth", proposed_growth, f"{proposed_growth / 1024 / 1024:.2f}"],
                ["suggested no-op system_b size", system_b.bytes + proposed_growth, f"{(system_b.bytes + proposed_growth) / 1024 / 1024:.2f}"],
            ],
        )
    )
    lines.append("")
    lines.append("## Gates")
    lines.append("")
    lines.extend(md_table(["Gate", "Status", "Evidence", "Next step"], [[g.gate, g.status, g.evidence, g.next_step] for g in gates]))
    lines.append("")
    lines.append("## Dynamic Groups")
    lines.append("")
    lines.extend(md_table(["Group", "Maximum bytes", "Allocated bytes", "Free bytes", "Free MiB"], [[g.group, g.maximum_bytes, g.allocated_bytes, g.free_bytes, f"{g.free_mib:.2f}"] for g in groups]))
    lines.append("")
    lines.append("## Slot 1 Partitions")
    lines.append("")
    lines.extend(
        md_table(
            ["Partition", "Group", "Start sector", "Sectors", "Bytes", "MiB"],
            [[p.name, p.group, p.start_sector, p.sectors, p.bytes, f"{p.bytes / 1024 / 1024:.2f}"] for p in sorted(partitions.values(), key=lambda item: item.start_sector)],
        )
    )
    lines.append("")
    lines.append("## Physical Holes")
    lines.append("")
    lines.extend(md_table(["Start sector", "End sector", "Sectors", "Bytes", "MiB"], [[h.start_sector, h.end_sector, h.sectors, h.bytes, f"{h.mib:.2f}"] for h in holes]))
    lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("- Exact-current sparse patching remains the safest path for same-size partition images because it leaves dynamic partition metadata unchanged.")
    lines.append("- Growing `system_b` requires a new no-op gate: rebuild or edit dynamic partition metadata, grow the ext4 filesystem, run fsck, verify lpdump, flash full `super`, boot, and keep rollback ready.")
    lines.append("- The first growth probe should change only `system_b` size and filesystem size, not WebView contents, package directories, APKs, or `/data` state.")
    lines.append("- If the no-op growth gate passes live, later WebView images can stop depending on aggressive package deletion for capacity.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append("")
    OUT_MD.write_text("\n".join(lines), encoding="utf-8")

    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().isoformat(timespec="seconds"),
                "verdict": verdict,
                "lpdump_slot1": rel(LPDUMP_SLOT1),
                "super_size": super_size,
                "system_b_current_bytes": system_b.bytes,
                "group_b_free_bytes": group_b.free_bytes,
                "physical_tail_hole_bytes": physical_growth,
                "system_b_growth_ceiling_bytes": growth_ceiling,
                "suggested_noop_growth_bytes": proposed_growth,
                "suggested_noop_system_b_bytes": system_b.bytes + proposed_growth,
                "gates": [asdict(gate) for gate in gates],
                "groups": [asdict(group) for group in groups],
                "partitions": {name: asdict(partition) for name, partition in sorted(partitions.items())},
                "holes": [asdict(hole) for hole in holes],
            },
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"verdict={verdict}")
    print(f"group_b_free_bytes={group_b.free_bytes}")
    print(f"system_b_growth_ceiling_bytes={growth_ceiling}")
    print(f"suggested_noop_growth_bytes={proposed_growth}")
    print(f"report={rel(OUT_MD)}")


def main() -> int:
    super_size, groups, partitions = parse_lpdump(LPDUMP_SLOT1)
    group_rows = group_summaries(groups, partitions)
    holes = physical_holes(super_size, partitions)
    gates = build_gates(super_size, group_rows, partitions, holes)
    write_outputs(super_size, group_rows, partitions, holes, gates)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
