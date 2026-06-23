# WebView Super Capacity Audit

Generated: 2026-06-20 01:40:29

This is a read-only offline planning report. It does not rebuild `super`,
resize filesystems, touch a device, flash, reboot, erase partitions, write
settings, or modify `/data`.

## Result

`system_b` can technically be grown inside the current dynamic `super` layout. Slot B's dynamic group still has unused capacity, and the physical super tail has a matching large hole. The current blocker is not raw NAND space; it is that our safest builders intentionally avoid changing logical partition metadata.

## Capacity Summary

| Item | Bytes | MiB |
| --- | --- | --- |
| super size | 10737418240 | 10240.00 |
| system_b current size | 3049058304 | 2907.81 |
| qti_dynamic_partitions_b free | 978509824 | 933.18 |
| largest usable B-slot tail hole | 980967424 | 935.52 |
| system_b growth ceiling | 978509824 | 933.18 |
| suggested first no-op growth | 134217728 | 128.00 |
| suggested no-op system_b size | 3183276032 | 3035.81 |

## Gates

| Gate | Status | Evidence | Next step |
| --- | --- | --- | --- |
| SUPER-CAP-01-group-b-free-space | PASS | group_b_free=978509824; group_b_free_mib=933.18 | Use group free space as the hard logical capacity ceiling for growing B-slot partitions. |
| SUPER-CAP-02-physical-tail-hole | PASS | tail_hole_bytes=980967424; super_size=10737418240; system_b_end_sector=16442936 | A full super rebuild can allocate a new system_b extent in the tail hole; exact-current slice patching cannot. |
| SUPER-CAP-03-system-b-growth-ceiling | FEASIBLE | growth_ceiling=978509824; proposed_growth=134217728; current_system_b=3049058304; proposed_system_b=3183276032 | Prototype a no-content-change system_b growth image before combining it with WebView or debloat changes. |
| SUPER-CAP-04-builder-risk-boundary | REQUIRES_NEW_NOOP_GATE | current exact-current builders overwrite existing logical slices and do not modify dynamic partition metadata | Create a separate lpmake/lpadd-style metadata-resize builder and verify lpdump, ext4 resize, fsck, sparse flash, boot, rollback. |

## Dynamic Groups

| Group | Maximum bytes | Allocated bytes | Free bytes | Free MiB |
| --- | --- | --- | --- | --- |
| qti_dynamic_partitions_a | 5364514816 | 4250816512 | 1113698304 | 1062.11 |
| qti_dynamic_partitions_b | 5364514816 | 4386004992 | 978509824 | 933.18 |

## Slot 1 Partitions

| Partition | Group | Start sector | Sectors | Bytes | MiB |
| --- | --- | --- | --- | --- | --- |
| system_a | qti_dynamic_partitions_a | 2048 | 5961552 | 3052314624 | 2910.91 |
| product_a | qti_dynamic_partitions_a | 5963776 | 499640 | 255815680 | 243.96 |
| vendor_a | qti_dynamic_partitions_a | 6463488 | 1839392 | 941768704 | 898.14 |
| odm_a | qti_dynamic_partitions_a | 8304640 | 1792 | 917504 | 0.88 |
| system_b | qti_dynamic_partitions_b | 10487744 | 5955192 | 3049058304 | 2907.81 |
| system_ext_b | qti_dynamic_partitions_b | 16443328 | 578352 | 296116224 | 282.40 |
| product_b | qti_dynamic_partitions_b | 17021888 | 334200 | 171110400 | 163.18 |
| vendor_b | qti_dynamic_partitions_b | 17356736 | 1696608 | 868663296 | 828.42 |
| odm_b | qti_dynamic_partitions_b | 19053504 | 2064 | 1056768 | 1.01 |

## Physical Holes

| Start sector | End sector | Sectors | Bytes | MiB |
| --- | --- | --- | --- | --- |
| 5963600 | 5963776 | 176 | 90112 | 0.09 |
| 6463416 | 6463488 | 72 | 36864 | 0.04 |
| 8302880 | 8304640 | 1760 | 901120 | 0.86 |
| 8306432 | 10487744 | 2181312 | 1116831744 | 1065.09 |
| 16442936 | 16443328 | 392 | 200704 | 0.19 |
| 17021680 | 17021888 | 208 | 106496 | 0.10 |
| 17356088 | 17356736 | 648 | 331776 | 0.32 |
| 19053344 | 19053504 | 160 | 81920 | 0.08 |
| 19055568 | 20971520 | 1915952 | 980967424 | 935.52 |

## Boundary

- Exact-current sparse patching remains the safest path for same-size partition images because it leaves dynamic partition metadata unchanged.
- Growing `system_b` requires a new no-op gate: rebuild or edit dynamic partition metadata, grow the ext4 filesystem, run fsck, verify lpdump, flash full `super`, boot, and keep rollback ready.
- The first growth probe should change only `system_b` size and filesystem size, not WebView contents, package directories, APKs, or `/data` state.
- If the no-op growth gate passes live, later WebView images can stop depending on aggressive package deletion for capacity.

## Outputs

- JSON snapshot: `hard-rom/inspect/browser-webview-super-capacity/webview-super-capacity-audit.json`
- TSV manifest: `reverse/smartisan-8.5.3-rom-static/manifest/webview-super-capacity-audit.tsv`
- Markdown report: `docs/research/webview-super-capacity-audit.md`
