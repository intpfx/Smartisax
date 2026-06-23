#!/usr/bin/env python3
"""Plan v0.17/v0.22/v0.24 APK-only locale-prune promotion into ROM images.

This audit is read-only. It turns the current APK-only language-prune manifest
into an exact-current ROM-promotion build plan, including partition ownership,
space requirements, and the smallest safe batch choices.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]

DEFAULT_COVERAGE = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv"
DEFAULT_OUT_TSV = ROOT / "reverse/smartisan-8.5.3-rom-static/manifest/v0.17-apk-only-promotion-audit.tsv"
DEFAULT_OUT_MD = ROOT / "docs/research/v0.17-apk-only-promotion-audit.md"
DEFAULT_BASE_SPARSE = ROOT / "hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img"
DUMPE2FS = Path("/opt/homebrew/opt/e2fsprogs/sbin/dumpe2fs")

CONFDIALER_SAME_SIZE = {
    "package": "com.qualcomm.qti.confdialer",
    "same_size_apk": "hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh-samesize.apk",
    "same_size_report": "hard-rom/inspect/v0.17-apk-only-promotion/confdialer-samesize-apk-report.json",
    "inplace_dry_report": "hard-rom/inspect/v0.17-apk-only-promotion/confdialer-system_ext-inplace-dry-run.json",
    "inplace_write_report": "hard-rom/inspect/v0.17-apk-only-promotion/confdialer-system_ext-inplace-write-test.json",
    "inplace_e2fsck": "hard-rom/inspect/v0.17-apk-only-promotion/confdialer-system_ext-inplace-e2fsck-fn.txt",
    "dumped_apk": "hard-rom/inspect/v0.17-apk-only-promotion/dumped/ConferenceDialer-samesize-from-system_ext.apk",
}

PARTITION_INFO = {
    "system": {
        "dynamic_partition": "system_b",
        "image_bytes": 3049058304,
        "selabel": "u:object_r:system_file:s0",
        "build_class": "shared_blocks_held_inode_replace",
        "reference_image": "hard-rom/build/system-otatrust-v0.13-tier1a-locale-prune.img",
    },
    "product": {
        "dynamic_partition": "product_b",
        "image_bytes": 171110400,
        "selabel": "u:object_r:system_file:s0",
        "build_class": "shared_blocks_held_inode_replace",
        "reference_image": "hard-rom/build/product-otatrust-v0.10-framework-locale-prune.img",
    },
    "system_ext": {
        "dynamic_partition": "system_ext_b",
        "image_bytes": 296116224,
        "selabel": "u:object_r:system_file:s0",
        "build_class": "system_ext_special_strategy_required",
        "reference_image": "hard-rom/build/system_ext-otatrust-systemui-certprobe-noop.img",
    },
}

V017_BATCHES = {
    "v0.17a-system-apk-only-locale-prune": {"system"},
    "v0.17b-product-system_ext-apk-only-locale-prune": {"product", "system_ext"},
    "v0.17-all-apk-only-locale-prune": {"system", "product", "system_ext"},
}

V017_PROMOTED_PACKAGES = {
    "com.android.dreams.basic",
    "com.android.dreams.phototable",
    "com.android.htmlviewer",
    "com.android.printspooler",
    "com.android.simappdialog",
    "com.android.wallpaper.livepicker",
    "com.qualcomm.qti.confdialer",
}

V022_PROMOTED_PACKAGES = {
    "com.android.companiondevicemanager",
    "com.smartisanos.share.browser",
    "com.smartisanos.tracker",
}

V024_PROMOTED_PACKAGES = {
    "com.smartisanos.cleaner",
}

V017A_EVIDENCE = {
    "super_sparse": "hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img",
    "super_sha256": "2ebe837f314c35b02d5bab3bdd21d8661cf85b8cba8816e99d8d9744d2f5100a",
    "system_image": "hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img",
    "system_sha256": "d5724b330be72eee2b25f00b239089bdf16990eab8b4ae0dbee15e43fb3b91e5",
    "verify_report": "hard-rom/inspect/v0.17a-system-apk-only-locale-prune/verify-v0.17a-offline-image-20260618-124311.txt",
}

V017B_EVIDENCE = {
    "super_sparse": "hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img",
    "super_sha256": "f7e1c18b1023714731c714557ee5ed6763426882901026f3e914d79469c20e45",
    "product_image": "hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img",
    "product_sha256": "7fb45200e148bea21bb5cbccab3fb83fae274f6bed04cf30b13037a68fac8bc8",
    "system_ext_image": "hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img",
    "system_ext_sha256": "742588430998ee9cbaabaf6091b4f0fea80b98ddfb3da878230f8b48028d91cb",
    "verify_report": "hard-rom/inspect/v0.17b-product-system_ext-apk-only-locale-prune/verify-v0.17b-offline-image-20260618-130101.txt",
}

V017ALL_EVIDENCE = {
    "super_sparse": "hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img",
    "super_sha256": "942da9469ccf9a24ff390912f26d76673415d2a500482d060a89c11847faf819",
    "verify_report": "hard-rom/inspect/v0.17-all-apk-only-locale-prune/verify-v0.17-all-offline-image-20260618-131151.txt",
}

V022_EVIDENCE = {
    "super_sparse": "hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img",
    "super_sha256": "bd1670d117b124aa70220068a031b2a608b2373fab149da5020b1a71bc312e86",
    "system_image": "hard-rom/build/system-otatrust-v0.22-all-apk-only-locale-prune.img",
    "system_sha256": "ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316",
    "verify_report": "hard-rom/inspect/v0.22-all-apk-only-locale-prune/verify-v0.22-all-offline-image-20260618-141813.txt",
}

V024_EVIDENCE = {
    "super_sparse": "hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img",
    "super_sha256": "d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e",
    "system_image": "hard-rom/build/system-otatrust-v0.24-cleaner-apk-only-locale-prune.img",
    "system_sha256": "4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6",
    "verify_report": "hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune/verify-v0.24-offline-image-20260618-144855.txt",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coverage", type=Path, default=DEFAULT_COVERAGE)
    parser.add_argument("--base-sparse", type=Path, default=DEFAULT_BASE_SPARSE)
    parser.add_argument("--out-tsv", type=Path, default=DEFAULT_OUT_TSV)
    parser.add_argument("--markdown", type=Path, default=DEFAULT_OUT_MD)
    return parser.parse_args()


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def int_field(row: dict[str, str], key: str) -> int:
    try:
        return int(row.get(key, "") or 0)
    except ValueError:
        return 0


def file_size(path: Path) -> int:
    return path.stat().st_size if path.exists() else 0


def file_sha256(path: Path) -> str:
    if not path.exists():
        return ""
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def mib(value: int) -> str:
    return f"{value / 1024 / 1024:.1f} MiB"


def gib(value: int) -> str:
    return f"{value / 1024 / 1024 / 1024:.2f} GiB"


def disk_free(path: Path) -> int:
    return shutil.disk_usage(path).free


def ceil_blocks(size: int, block_size: int = 4096) -> int:
    return int(math.ceil(size / block_size)) if size > 0 else 0


def ext4_header(path: Path) -> dict[str, int | str]:
    if not path.exists() or not DUMPE2FS.exists():
        return {}
    proc = subprocess.run(
        [str(DUMPE2FS), "-h", str(path)],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if proc.returncode != 0:
        return {}
    out: dict[str, int | str] = {}
    key_map = {
        "Block size": "reference_block_size",
        "Free blocks": "reference_free_blocks",
        "Free inodes": "reference_free_inodes",
        "Block count": "reference_block_count",
        "Inode count": "reference_inode_count",
    }
    for line in proc.stdout.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        mapped = key_map.get(key.strip())
        if not mapped:
            continue
        text = value.strip()
        try:
            out[mapped] = int(text)
        except ValueError:
            out[mapped] = text
    return out


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def v017a_evidence_status() -> dict[str, str]:
    super_sparse = ROOT / V017A_EVIDENCE["super_sparse"]
    system_image = ROOT / V017A_EVIDENCE["system_image"]
    combined_sparse = ROOT / V017ALL_EVIDENCE["super_sparse"]
    verify_report = ROOT / V017A_EVIDENCE["verify_report"]
    report_text = verify_report.read_text(encoding="utf-8", errors="replace") if verify_report.exists() else ""
    super_ok = file_sha256(super_sparse) == V017A_EVIDENCE["super_sha256"]
    system_ok = file_sha256(system_image) == V017A_EVIDENCE["system_sha256"]
    report_ok = (
        "result=PASS" in report_text
        and "PASS: v0.17a offline image verification" in report_text
        and "bad_locale_chunk_count=0" in report_text
        and f"sparse_slice={V017A_EVIDENCE['system_sha256']}" in report_text
    )
    partition_verified = system_ok and report_ok
    partition_status = "yes" if partition_verified else "no"
    if not system_image.exists() and report_ok and combined_sparse.exists():
        partition_status = "retired_local"
    standalone_sparse_verified = super_ok and report_ok
    standalone_sparse_status = "yes" if standalone_sparse_verified else "no"
    if not super_sparse.exists() and report_ok and combined_sparse.exists():
        standalone_sparse_status = "retired_local"
    return {
        "partition_verified": partition_status,
        "standalone_sparse_verified": standalone_sparse_status,
        "super_sparse": V017A_EVIDENCE["super_sparse"] if super_sparse.exists() else "",
        "system_image": V017A_EVIDENCE["system_image"] if system_image.exists() else "",
        "verify_report": V017A_EVIDENCE["verify_report"] if verify_report.exists() else "",
    }


def v017b_evidence_status() -> dict[str, str]:
    super_sparse = ROOT / V017B_EVIDENCE["super_sparse"]
    product_image = ROOT / V017B_EVIDENCE["product_image"]
    system_ext_image = ROOT / V017B_EVIDENCE["system_ext_image"]
    combined_sparse = ROOT / V017ALL_EVIDENCE["super_sparse"]
    verify_report = ROOT / V017B_EVIDENCE["verify_report"]
    report_text = verify_report.read_text(encoding="utf-8", errors="replace") if verify_report.exists() else ""
    super_ok = file_sha256(super_sparse) == V017B_EVIDENCE["super_sha256"]
    product_ok = file_sha256(product_image) == V017B_EVIDENCE["product_sha256"]
    system_ext_ok = file_sha256(system_ext_image) == V017B_EVIDENCE["system_ext_sha256"]
    report_ok = (
        "result=PASS" in report_text
        and "PASS: v0.17b offline image verification" in report_text
        and "confdialer_same_size_scope=ok" in report_text
        and f"sparse_slice={V017B_EVIDENCE['product_sha256']}" in report_text
        and f"sparse_slice={V017B_EVIDENCE['system_ext_sha256']}" in report_text
    )
    partition_verified = product_ok and system_ext_ok and report_ok
    partition_status = "yes" if partition_verified else "no"
    if (not product_image.exists() or not system_ext_image.exists()) and report_ok and combined_sparse.exists():
        partition_status = "retired_local"
    standalone_sparse_verified = super_ok and report_ok
    standalone_sparse_status = "yes" if standalone_sparse_verified else "no"
    if not super_sparse.exists() and report_ok and combined_sparse.exists():
        standalone_sparse_status = "retired_local"
    return {
        "partition_verified": partition_status,
        "standalone_sparse_verified": standalone_sparse_status,
        "super_sparse": V017B_EVIDENCE["super_sparse"] if super_sparse.exists() else "",
        "product_image": V017B_EVIDENCE["product_image"] if product_image.exists() else "",
        "system_ext_image": V017B_EVIDENCE["system_ext_image"] if system_ext_image.exists() else "",
        "verify_report": V017B_EVIDENCE["verify_report"] if verify_report.exists() else "",
    }


def v017all_evidence_status() -> dict[str, str]:
    super_sparse = ROOT / V017ALL_EVIDENCE["super_sparse"]
    verify_report = ROOT / V017ALL_EVIDENCE["verify_report"]
    report_text = verify_report.read_text(encoding="utf-8", errors="replace") if verify_report.exists() else ""
    super_ok = file_sha256(super_sparse) == V017ALL_EVIDENCE["super_sha256"]
    report_ok = (
        "result=PASS" in report_text
        and "PASS: v0.17-all offline image verification" in report_text
        and "v0.17a_report_pass=ok" in report_text
        and "v0.17b_report_pass=ok" in report_text
        and f"sparse_slice={V017A_EVIDENCE['system_sha256']}" in report_text
        and f"sparse_slice={V017B_EVIDENCE['product_sha256']}" in report_text
        and f"sparse_slice={V017B_EVIDENCE['system_ext_sha256']}" in report_text
    )
    verified = super_ok and report_ok
    return {
        "verified": "yes" if verified else "no",
        "super_sparse": V017ALL_EVIDENCE["super_sparse"] if super_sparse.exists() else "",
        "verify_report": V017ALL_EVIDENCE["verify_report"] if verify_report.exists() else "",
    }


def v022_evidence_status() -> dict[str, str]:
    super_sparse = ROOT / V022_EVIDENCE["super_sparse"]
    system_image = ROOT / V022_EVIDENCE["system_image"]
    verify_report = ROOT / V022_EVIDENCE["verify_report"]
    report_text = verify_report.read_text(encoding="utf-8", errors="replace") if verify_report.exists() else ""
    super_ok = file_sha256(super_sparse) == V022_EVIDENCE["super_sha256"]
    system_ok = file_sha256(system_image) == V022_EVIDENCE["system_sha256"]
    report_ok = (
        "result=PASS" in report_text
        and "PASS: v0.22-all offline image verification" in report_text
        and "bad_locale_chunk_count=0" in report_text
        and f"sparse_slice={V022_EVIDENCE['system_sha256']}" in report_text
    )
    verified = super_ok and system_ok and report_ok
    return {
        "verified": "yes" if verified else "no",
        "super_sparse": V022_EVIDENCE["super_sparse"] if super_sparse.exists() else "",
        "system_image": V022_EVIDENCE["system_image"] if system_image.exists() else "",
        "verify_report": V022_EVIDENCE["verify_report"] if verify_report.exists() else "",
    }


def v024_evidence_status() -> dict[str, str]:
    super_sparse = ROOT / V024_EVIDENCE["super_sparse"]
    system_image = ROOT / V024_EVIDENCE["system_image"]
    verify_report = ROOT / V024_EVIDENCE["verify_report"]
    report_text = verify_report.read_text(encoding="utf-8", errors="replace") if verify_report.exists() else ""
    super_ok = file_sha256(super_sparse) == V024_EVIDENCE["super_sha256"]
    system_ok = file_sha256(system_image) == V024_EVIDENCE["system_sha256"]
    report_ok = (
        "result=PASS" in report_text
        and "PASS: v0.24 offline image verification" in report_text
        and "system/CleanerSmartisan.apk\td0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc" in report_text
        and f"sparse_slice={V024_EVIDENCE['system_sha256']}" in report_text
    )
    verified = super_ok and system_ok and report_ok
    return {
        "verified": "yes" if verified else "no",
        "super_sparse": V024_EVIDENCE["super_sparse"] if super_sparse.exists() else "",
        "system_image": V024_EVIDENCE["system_image"] if system_image.exists() else "",
        "verify_report": V024_EVIDENCE["verify_report"] if verify_report.exists() else "",
    }


def promotion_scope(row: dict[str, str]) -> str:
    package = row.get("package", "")
    status = row.get("coverage_status", "")
    if package in V017_PROMOTED_PACKAGES or status in {
        "pruned_in_v0.17a_system_image",
        "pruned_in_v0.17b_product_system_ext_image",
    }:
        return "v0.17_promoted"
    if package in V022_PROMOTED_PACKAGES or status == "pruned_in_v0.22_all_system_image":
        return "v0.22_promoted"
    if package in V024_PROMOTED_PACKAGES or status == "pruned_in_v0.24_system_image":
        return "v0.24_promoted"
    return "future_apk_only_pending"


def same_size_evidence(package: str, stock_bytes: int) -> dict[str, str]:
    if package != CONFDIALER_SAME_SIZE["package"]:
        return {
            "same_size_apk": "",
            "same_size_apk_bytes": "",
            "same_size_apk_sha256": "",
            "same_size_inplace_proven_offline": "",
            "same_size_evidence": "",
        }

    paths = {key: ROOT / value for key, value in CONFDIALER_SAME_SIZE.items() if key != "package"}
    same_size_apk = paths["same_size_apk"]
    same_size_report = read_json(paths["same_size_report"])
    dry_report = read_json(paths["inplace_dry_report"])
    write_report = read_json(paths["inplace_write_report"])
    dumped_apk = paths["dumped_apk"]
    same_hash = file_sha256(same_size_apk)
    dumped_hash = file_sha256(dumped_apk)
    e2fsck_text = paths["inplace_e2fsck"].read_text(encoding="utf-8", errors="replace") if paths["inplace_e2fsck"].exists() else ""

    proven = (
        same_size_apk.exists()
        and file_size(same_size_apk) == stock_bytes
        and same_size_report.get("out_size") == stock_bytes
        and same_size_report.get("entries", {}).get("resources.arsc", {}).get("out_compress_type") == 0
        and dry_report.get("owner_audit", {}).get("all_blocks_owned_only_by_inode") is True
        and write_report.get("write") is True
        and write_report.get("owner_audit", {}).get("all_blocks_owned_only_by_inode") is True
        and write_report.get("payload_sha256") == same_hash
        and dumped_apk.exists()
        and dumped_hash == same_hash
        and "Pass 5: Checking group summary information" in e2fsck_text
    )
    evidence_paths = [
        path.relative_to(ROOT).as_posix()
        for path in paths.values()
        if path.exists()
    ]
    return {
        "same_size_apk": same_size_apk.relative_to(ROOT).as_posix() if same_size_apk.exists() else "",
        "same_size_apk_bytes": str(file_size(same_size_apk)) if same_size_apk.exists() else "",
        "same_size_apk_sha256": same_hash,
        "same_size_inplace_proven_offline": "yes" if proven else "no",
        "same_size_evidence": ";".join(evidence_paths),
    }


def promotion_rows(coverage_rows: Iterable[dict[str, str]], base_sparse: Path) -> list[dict[str, str]]:
    base_sparse_bytes = file_size(base_sparse)
    rows: list[dict[str, str]] = []
    for row in coverage_rows:
        if not row.get("apk_only_variant"):
            continue
        partition = row.get("partition", "")
        info = PARTITION_INFO.get(partition, {})
        dynamic_partition = info.get("dynamic_partition", "")
        image_bytes = int(info.get("image_bytes", 0) or 0)
        stock_rel = f"reverse/smartisan-8.5.3-rom-static/raw/{partition}/{row.get('rel_path', '')}"
        stock_abs = ROOT / stock_rel
        patched_abs = ROOT / row.get("apk_only_apk", "")
        stock_bytes = file_size(stock_abs)
        patched_bytes = file_size(patched_abs)
        reference_image = ROOT / str(info.get("reference_image", ""))
        header = ext4_header(reference_image)
        block_size = int(header.get("reference_block_size", 4096) or 4096)
        required_blocks = ceil_blocks(patched_bytes, block_size)
        free_blocks = int(header.get("reference_free_blocks", 0) or 0)
        free_inodes = int(header.get("reference_free_inodes", 0) or 0)
        held_inode_feasible = free_blocks >= required_blocks and free_inodes >= 1
        system_ext_strategy = ""
        if partition == "system_ext" and not held_inode_feasible:
            system_ext_strategy = "needs_same_size_or_in_place_strategy_before_rom_promotion"
        same_size = same_size_evidence(row.get("package", ""), stock_bytes)
        if same_size.get("same_size_inplace_proven_offline") == "yes":
            system_ext_strategy = "same_size_in_place_offline_proven_for_reference_inode"
        out = {
            "package": row.get("package", ""),
            "promotion_scope": promotion_scope(row),
            "coverage_status": row.get("coverage_status", ""),
            "variant": row.get("apk_only_variant", ""),
            "partition": partition,
            "dynamic_partition": dynamic_partition,
            "rel_path": row.get("rel_path", ""),
            "stock_apk": stock_rel,
            "patched_apk": row.get("apk_only_apk", ""),
            "patched_sha256": row.get("apk_only_sha256", ""),
            "stock_apk_bytes": str(stock_bytes),
            "patched_apk_bytes": str(patched_bytes),
            "held_inode_new_blocks_required": str(required_blocks),
            "reference_image": str(reference_image.relative_to(ROOT)) if reference_image.exists() else "",
            "reference_free_blocks": str(free_blocks) if header else "",
            "reference_free_inodes": str(free_inodes) if header else "",
            "held_inode_feasible_on_reference_image": "yes" if held_inode_feasible else "no",
            "special_strategy": system_ext_strategy,
            **same_size,
            "risk": row.get("risk", ""),
            "exposure_gate": row.get("exposure_gate", ""),
            "exposure_score": row.get("exposure_score", ""),
            "non_target_dirs": row.get("non_target_dirs", ""),
            "ja_ko_dirs": row.get("ja_ko_dirs", ""),
            "other_locale_dirs": row.get("other_locale_dirs", ""),
            "keep_dirs": row.get("keep_dirs", ""),
            "non_target_values_dirs": row.get("non_target_values_dirs", ""),
            "selabel": info.get("selabel", ""),
            "build_class": info.get("build_class", ""),
            "partition_image_bytes": str(image_bytes),
            "base_sparse_bytes": str(base_sparse_bytes),
            "needs_partition_image": "yes",
            "needs_sparse_rewrite_for_flashable_super": "yes",
            "rom_coverage_after_promotion": "yes_after_matching_image_verified_not_live",
            "live_gate": "flash only after explicit confirmation and v0.4 rollback readiness",
        }
        rows.append(out)
    return sorted(rows, key=lambda item: (item["partition"], item["package"]))


def batch_rows(candidate_rows: list[dict[str, str]], base_sparse: Path, free_bytes: int) -> list[dict[str, str]]:
    base_sparse_bytes = file_size(base_sparse)
    rows: list[dict[str, str]] = []
    for batch, partitions in V017_BATCHES.items():
        candidates = [
            row
            for row in candidate_rows
            if row["partition"] in partitions and row.get("promotion_scope") == "v0.17_promoted"
        ]
        image_bytes = sum(int(PARTITION_INFO[part]["image_bytes"]) for part in sorted(partitions))
        image_only_required = image_bytes
        flashable_required = image_bytes + base_sparse_bytes
        rows.append(
            {
                "batch": batch,
                "partitions": ",".join(sorted(partitions)),
                "candidate_count": str(len(candidates)),
                "packages": ",".join(row["package"] for row in candidates),
                "partition_image_required_bytes": str(image_only_required),
                "flashable_sparse_required_bytes": str(flashable_required),
                "current_free_bytes": str(free_bytes),
                "image_only_feasible_now": "yes" if free_bytes > image_only_required else "no",
                "flashable_super_feasible_now": "yes" if free_bytes > flashable_required else "no",
                "required_free_for_flashable_with_margin_bytes": str(flashable_required + 1024 * 1024 * 1024),
            }
        )
    return rows


def write_tsv(rows: list[dict[str, str]], path: Path) -> None:
    fields = [
        "package",
        "promotion_scope",
        "coverage_status",
        "variant",
        "partition",
        "dynamic_partition",
        "rel_path",
        "stock_apk",
        "patched_apk",
        "patched_sha256",
        "stock_apk_bytes",
        "patched_apk_bytes",
        "held_inode_new_blocks_required",
        "reference_image",
        "reference_free_blocks",
        "reference_free_inodes",
        "held_inode_feasible_on_reference_image",
        "special_strategy",
        "same_size_apk",
        "same_size_apk_bytes",
        "same_size_apk_sha256",
        "same_size_inplace_proven_offline",
        "same_size_evidence",
        "risk",
        "exposure_gate",
        "exposure_score",
        "non_target_dirs",
        "ja_ko_dirs",
        "other_locale_dirs",
        "keep_dirs",
        "non_target_values_dirs",
        "selabel",
        "build_class",
        "partition_image_bytes",
        "base_sparse_bytes",
        "needs_partition_image",
        "needs_sparse_rewrite_for_flashable_super",
        "rom_coverage_after_promotion",
        "live_gate",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fields, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def md_table(rows: list[dict[str, str]], columns: list[str]) -> list[str]:
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    for row in rows:
        values = []
        for col in columns:
            value = row.get(col, "")
            if col.endswith("_bytes") and value:
                value = gib(int(value)) if int(value) >= 1024 * 1024 * 1024 else mib(int(value))
            value = value.replace("|", "\\|").replace("\n", " ")
            if col in {"rel_path", "patched_apk", "stock_apk"} and value:
                value = f"`{value}`"
            values.append(value)
        lines.append("| " + " | ".join(values) + " |")
    return lines


def write_markdown(
    candidates: list[dict[str, str]],
    batches: list[dict[str, str]],
    out_tsv: Path,
    path: Path,
    base_sparse: Path,
    free_bytes: int,
) -> None:
    by_partition: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in candidates:
        by_partition[row["partition"]].append(row)

    flashable_batches = [row for row in batches if row["flashable_super_feasible_now"] == "yes"]
    v017_promoted_count = sum(1 for row in candidates if row.get("promotion_scope") == "v0.17_promoted")
    v022_promoted_count = sum(1 for row in candidates if row.get("promotion_scope") == "v0.22_promoted")
    v024_promoted_count = sum(1 for row in candidates if row.get("promotion_scope") == "v0.24_promoted")
    future_pending_count = sum(1 for row in candidates if row.get("promotion_scope") == "future_apk_only_pending")
    all_flashable = len(flashable_batches) == len(batches)
    any_flashable = bool(flashable_batches)
    v017a_status = v017a_evidence_status()
    v017b_status = v017b_evidence_status()
    v017all_status = v017all_evidence_status()
    v022_status = v022_evidence_status()
    v024_status = v024_evidence_status()
    max_required_with_margin = max(
        int(row["required_free_for_flashable_with_margin_bytes"]) for row in batches
    )
    if all_flashable:
        constraint_text = [
            "Current free space is enough for every planned v0.17 flashable",
            f"batch with the 1 GiB margin; the largest requirement is {gib(max_required_with_margin)}.",
            "This is build feasibility only, not flash authorization.",
        ]
        first_recommendation = [
            "1. Build only one explicit v0.17 variant at a time even though",
            "   local space is now sufficient; verify the generated partition",
            "   images and sparse super offline before any flash request.",
        ]
    elif any_flashable:
        feasible_names = ", ".join(row["batch"] for row in flashable_batches)
        constraint_text = [
            "Current free space is enough for some v0.17 flashable batches,",
            f"but not all of them. Feasible now: {feasible_names}.",
            "This is build feasibility only, not flash authorization.",
        ]
        first_recommendation = [
            "1. Prefer one currently feasible v0.17 variant and keep at least",
            "   the flashable requirement plus 1 GiB margin shown above; verify",
            "   the generated partition images and sparse super offline before",
            "   any flash request.",
        ]
    else:
        constraint_text = [
            "Because the flashable route needs a rewritten sparse super in addition",
            "to extracted partition images, current free space is not enough for a",
            "safe v0.17 flashable build.",
        ]
        first_recommendation = [
            "1. Free enough local space before building a flashable v0.17 sparse",
            "   super. For the all-candidate batch, keep at least the flashable",
            "   requirement plus 1 GiB margin shown above.",
        ]

    if v024_status["verified"] == "yes":
        promotion_state = [
            "v0.24 is built and verified offline as the latest combined",
            "flashable sparse super containing all eleven APK-only resource-prune",
            "promotions: the seven v0.17-all candidates, the three v0.22",
            "system_b candidates, and CleanerSmartisan. It is not live proof",
            "until explicitly flashed and boot-verified.",
        ]
        route_recommendation = [
            "1. Do not rebuild `v0.24-cleaner-apk-only-locale-prune` unless the",
            "   base sparse super or source APK candidates change; the current",
            "   sparse/system hashes already match the offline verifier.",
            "2. Use `v0.24-cleaner-apk-only-locale-prune` as the single live-test",
            "   target if the goal is to test all eleven APK-only promotions at once.",
            "3. Use `v0.22-all-apk-only-locale-prune` only if a deliberate",
            "   ten-package subset test is preferred over the fuller v0.24 image.",
            "4. Every replacement must use the shared_blocks-safe held-inode pattern,",
            "   unless this audit marks the target as requiring a special same-size",
            "   or in-place strategy. Follow with e2fsck, post-fsck dumped APK hash",
            "   checks, ZIP integrity, binary locale-policy checks, and sparse",
            "   logical-slice verification.",
            "5. No v0.24 image is flash-authorized until an offline verifier report",
            "   exists and the user explicitly confirms the exact variant.",
        ]
    elif v022_status["verified"] == "yes":
        promotion_state = [
            "v0.22-all is built and verified offline as the current combined",
            "flashable sparse super containing all ten APK-only resource-prune",
            "promotions: the seven v0.17-all candidates plus the three newer",
            "system_b candidates. It is not live proof until explicitly flashed",
            "and boot-verified.",
        ]
        route_recommendation = [
            "1. Do not rebuild `v0.22-all-apk-only-locale-prune` unless the",
            "   base sparse super or source APK candidates change; the current",
            "   sparse/system hashes already match the offline verifier.",
            "2. Use `v0.22-all-apk-only-locale-prune` as the single live-test",
            "   target if the goal is to test all ten APK-only promotions at once.",
            "3. Use `v0.17-all-apk-only-locale-prune` only if a deliberate",
            "   seven-package subset test is preferred over the fuller v0.22 image.",
            "4. Every replacement must use the shared_blocks-safe held-inode pattern,",
            "   unless this audit marks the target as requiring a special same-size",
            "   or in-place strategy. Follow with e2fsck, post-fsck dumped APK hash",
            "   checks, ZIP integrity, binary locale-policy checks, and sparse",
            "   logical-slice verification.",
            "5. No v0.22 image is flash-authorized until an offline verifier report",
            "   exists and the user explicitly confirms the exact variant.",
        ]
    elif v017all_status["verified"] == "yes":
        promotion_state = [
            "v0.17-all is built and verified offline as the single combined",
            "flashable sparse super containing the v0.17a system_b and v0.17b",
            f"product_b/system_ext_b images for {v017_promoted_count} APK-only",
            "promotions. It is not live proof until explicitly flashed and",
            "boot-verified.",
        ]
        if future_pending_count:
            promotion_state.extend(
                [
                    f"{future_pending_count} APK-only candidate(s) still exist outside",
                    "the current promoted-image set and must be promoted by a later",
                    "image before they count as ROM coverage.",
                ]
            )
        route_recommendation = [
            "1. Do not rebuild `v0.17-all` unless the base sparse super or source",
            "   partition images change; the current sparse hash already matches",
            "   the offline verifier.",
            "2. Use `v0.17-all-apk-only-locale-prune` as the single live-test",
            "   target if the goal is to test all seven APK-only promotions at once.",
            "3. Rebuild v0.17a or v0.17b standalone sparse only if a smaller",
            "   partition-scoped live test is deliberately selected. Request",
            "   explicit user authorization for the exact variant before flashing.",
            "4. Every replacement must use the shared_blocks-safe held-inode pattern,",
            "   unless this audit marks the target as requiring a special same-size",
            "   or in-place strategy. Follow with e2fsck, post-fsck dumped APK hash",
            "   checks, ZIP integrity, binary locale-policy checks, and sparse",
            "   logical-slice verification.",
            "5. No v0.17 image is flash-authorized until an offline verifier report",
            "   exists and the user explicitly confirms the exact variant.",
        ]
    elif v017a_status["standalone_sparse_verified"] == "yes" and v017b_status["standalone_sparse_verified"] == "yes":
        promotion_state = [
            "v0.17a and v0.17b are already built and verified offline as",
            "separate v0.4-based flashable sparse supers. They are not one",
            "combined ROM image, and neither is live proof until explicitly",
            "flashed and boot-verified.",
        ]
        route_recommendation = [
            "1. Do not rebuild `v0.17a` or `v0.17b` unless the base sparse",
            "   super or source APK candidates change; their sparse/partition",
            "   hashes already match offline verifiers.",
            "2. Build `v0.17-all-apk-only-locale-prune` only if we want a single",
            "   flashable test target containing all seven APK-only promotions.",
            "3. Otherwise, keep v0.17a and v0.17b as separate live-test choices",
            "   and request explicit user authorization for the exact variant.",
            "4. Every replacement must use the shared_blocks-safe held-inode pattern,",
            "   unless this audit marks the target as requiring a special same-size",
            "   or in-place strategy. Follow with e2fsck, post-fsck dumped APK hash",
            "   checks, ZIP integrity, binary locale-policy checks, and sparse",
            "   logical-slice verification.",
            "5. No v0.17 image is flash-authorized until an offline verifier report",
            "   exists and the user explicitly confirms the exact variant.",
        ]
    elif v017a_status["standalone_sparse_verified"] == "yes":
        promotion_state = [
            "v0.17a is already built and verified offline as a flashable sparse",
            "super. It is still not live proof until the user explicitly authorizes",
            "a flash and the device boots through the standard verification gate.",
        ]
        route_recommendation = [
            "1. Do not rebuild `v0.17a-system-apk-only-locale-prune` unless the",
            "   base sparse super or source APK candidates change; the current",
            "   v0.17a sparse/system hashes already match the offline verifier.",
            "2. The next unpromoted APK-only lane is",
            "   `v0.17b-product-system_ext-apk-only-locale-prune`, or we can ask",
            "   for explicit authorization to flash v0.17a and collect live proof.",
            "3. Keep `product` and `system_ext` candidates grouped separately unless",
            "   we intentionally want a three-partition sparse rewrite.",
            "4. Every replacement must use the shared_blocks-safe held-inode pattern,",
            "   unless this audit marks the target as requiring a special same-size",
            "   or in-place strategy. Follow with e2fsck, post-fsck dumped APK hash",
            "   checks, ZIP integrity, binary locale-policy checks, and sparse",
            "   logical-slice verification.",
            "5. No v0.17 image is flash-authorized until an offline verifier report",
            "   exists and the user explicitly confirms the exact variant.",
        ]
    else:
        promotion_state = [
            "No v0.17a flashable sparse super has been fully verified in the",
            "current local evidence set.",
        ]
        route_recommendation = [
            *first_recommendation,
            "2. Build `v0.17a-system-apk-only-locale-prune` first if we want the",
            "   smallest live-test blast radius that still exercises multiple",
            "   resources.arsc-only replacements in `/system`.",
            "3. Keep `product` and `system_ext` candidates grouped separately unless",
            "   we intentionally want a three-partition sparse rewrite.",
            "4. Every replacement must use the shared_blocks-safe held-inode pattern,",
            "   unless this audit marks the target as requiring a special same-size",
            "   or in-place strategy. Follow with e2fsck, post-fsck dumped APK hash",
            "   checks, ZIP integrity, binary locale-policy checks, and sparse",
            "   logical-slice verification.",
            "5. No v0.17 image is flash-authorized until an offline verifier report",
            "   exists and the user explicitly confirms the exact variant.",
        ]

    lines = [
        "# v0.17/v0.22/v0.24 APK-Only Locale-Prune Promotion Audit",
        "",
        "Date: 2026-06-18.",
        "",
        "This read-only audit plans how the current APK-only language-prune",
        "candidates can be promoted into exact-current ROM partition images.",
        "It does not build APKs, partition images, sparse super images, flash,",
        "reboot, erase misc, or modify `/data`.",
        "",
        "## Current Constraint",
        "",
        f"- current free space: {gib(free_bytes)}",
        f"- base v0.4 sparse super: `{base_sparse.relative_to(ROOT)}`",
        f"- base sparse size: {gib(file_size(base_sparse))}",
        f"- TSV output: `{out_tsv.relative_to(ROOT)}`",
        f"- v0.17a partition-image status: {v017a_status['partition_verified']}",
        f"- v0.17a standalone sparse super status: {v017a_status['standalone_sparse_verified']}",
        f"- v0.17a sparse super: `{v017a_status['super_sparse'] or 'retired locally; rebuild only for separate live test'}`",
        f"- v0.17a verifier: `{v017a_status['verify_report'] or 'missing'}`",
        f"- v0.17b partition-image status: {v017b_status['partition_verified']}",
        f"- v0.17b standalone sparse super status: {v017b_status['standalone_sparse_verified']}",
        f"- v0.17b sparse super: `{v017b_status['super_sparse'] or 'retired locally; rebuild only for separate live test'}`",
        f"- v0.17b verifier: `{v017b_status['verify_report'] or 'missing'}`",
        f"- v0.17-all combined image status: {v017all_status['verified']}",
        f"- v0.17-all sparse super: `{v017all_status['super_sparse'] or 'missing'}`",
        f"- v0.17-all verifier: `{v017all_status['verify_report'] or 'missing'}`",
        f"- v0.22-all combined image status: {v022_status['verified']}",
        f"- v0.22-all sparse super: `{v022_status['super_sparse'] or 'missing'}`",
        f"- v0.22-all system image: `{v022_status['system_image'] or 'missing'}`",
        f"- v0.22-all verifier: `{v022_status['verify_report'] or 'missing'}`",
        f"- v0.24 cleaner image status: {v024_status['verified']}",
        f"- v0.24 sparse super: `{v024_status['super_sparse'] or 'missing'}`",
        f"- v0.24 system image: `{v024_status['system_image'] or 'missing'}`",
        f"- v0.24 verifier: `{v024_status['verify_report'] or 'missing'}`",
        f"- v0.17 promoted APK-only candidates in this audit: {v017_promoted_count}",
        f"- v0.22 promoted APK-only candidates in this audit: {v022_promoted_count}",
        f"- v0.24 promoted APK-only candidates in this audit: {v024_promoted_count}",
        f"- future APK-only candidates outside promoted images: {future_pending_count}",
        "",
        *constraint_text,
        "",
        *promotion_state,
        "",
        "## Batch Feasibility",
        "",
        *md_table(
            batches,
            [
                "batch",
                "partitions",
                "candidate_count",
                "partition_image_required_bytes",
                "flashable_sparse_required_bytes",
                "current_free_bytes",
                "image_only_feasible_now",
                "flashable_super_feasible_now",
                "required_free_for_flashable_with_margin_bytes",
            ],
        ),
        "",
        "## Candidate Partition Map",
        "",
        *md_table(
            candidates,
            [
                "package",
                "promotion_scope",
                "coverage_status",
                "partition",
                "dynamic_partition",
                "exposure_gate",
                "exposure_score",
                "non_target_dirs",
                "held_inode_feasible_on_reference_image",
                "held_inode_new_blocks_required",
                "reference_free_blocks",
                "special_strategy",
                "same_size_inplace_proven_offline",
                "rel_path",
                "patched_apk",
            ],
        ),
        "",
        "## Recommended Promotion Route",
        "",
        *route_recommendation,
        "",
        "## Build Notes",
        "",
        "- `r2-sparse-partition-patch.py` knows `system_b`, `product_b`, and",
        "  `system_ext_b` extents, but these extents cross FILL chunks in the",
        "  v0.4 sparse base, so the flashable path must use rewrite-sparse mode.",
        "- `system_ext_b` has limited free blocks. The ordinary held-inode",
        "  path is still not feasible for Confdialer on the reference image,",
        "  but the same-size/in-place strategy is now offline-proven for the",
        "  current reference inode: the candidate APK matches the stock byte",
        "  size, `resources.arsc` is stored, all target blocks are owned only",
        "  by inode 20, a cloned image write passed `e2fsck -fn`, and the",
        "  dumped APK hash matches the same-size candidate.",
        "- The same-size/in-place strategy remains a special gate, not a blanket",
        "  replacement method. It must re-run size, extent, owner, fsck, dump,",
        "  ZIP, signature-boundary, and locale-policy checks for each target.",
        "- Rows with `promotion_scope=v0.17_promoted` are contained in the",
        "  verified v0.17-all combined sparse. Rows with",
        "  `promotion_scope=v0.22_promoted` are contained in the newer verified",
        "  v0.22-all combined sparse. Rows with",
        "  `promotion_scope=v0.24_promoted` are contained in the latest verified",
        "  v0.24 CleanerSmartisan combined sparse. Rows with",
        "  `promotion_scope=future_apk_only_pending` are built APK-only evidence",
        "  but remain outside ROM coverage until a later partition image and",
        "  sparse super are built and verified. None of these states are live",
        "  proof until flashed and boot-tested.",
    ]
    for partition, rows in sorted(by_partition.items()):
        info = PARTITION_INFO[partition]
        lines.extend(
            [
                "",
                f"### {partition}",
                "",
                f"- dynamic partition: `{info['dynamic_partition']}`",
                f"- partition image size: {mib(int(info['image_bytes']))}",
                f"- build class: `{info['build_class']}`",
                f"- reference image: `{info['reference_image']}`",
                f"- candidates: {len(rows)}",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    rows = promotion_rows(read_tsv(args.coverage), args.base_sparse)
    free_bytes = disk_free(ROOT)
    batches = batch_rows(rows, args.base_sparse, free_bytes)
    write_tsv(rows, args.out_tsv)
    write_markdown(rows, batches, args.out_tsv, args.markdown, args.base_sparse, free_bytes)

    print(f"apk_only_candidates={len(rows)}")
    print(f"v017_promoted_candidates={sum(1 for row in rows if row.get('promotion_scope') == 'v0.17_promoted')}")
    print(f"v022_promoted_candidates={sum(1 for row in rows if row.get('promotion_scope') == 'v0.22_promoted')}")
    print(f"v024_promoted_candidates={sum(1 for row in rows if row.get('promotion_scope') == 'v0.24_promoted')}")
    print(f"future_apk_only_pending_candidates={sum(1 for row in rows if row.get('promotion_scope') == 'future_apk_only_pending')}")
    print(f"partitions={','.join(sorted({row['partition'] for row in rows}))}")
    print(f"current_free_bytes={free_bytes}")
    for row in batches:
        print(
            "batch="
            f"{row['batch']} candidates={row['candidate_count']} "
            f"image_only_feasible_now={row['image_only_feasible_now']} "
            f"flashable_super_feasible_now={row['flashable_super_feasible_now']}"
        )
    print(f"tsv={args.out_tsv.relative_to(ROOT)}")
    print(f"markdown={args.markdown.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
