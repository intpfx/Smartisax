#!/usr/bin/env python3
"""
Build a static ROM source knowledge base for Smartisan OS 8.5.3.

Inputs are OTA-extracted partition images under hard-rom/extracted. The script
does not read /data/app or the live device.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "reverse" / "smartisan-8.5.3-rom-static"
PARTITIONS = {
    "system": ROOT / "hard-rom" / "extracted" / "system.img",
    "system_ext": ROOT / "hard-rom" / "extracted" / "system_ext.img",
    "product": ROOT / "hard-rom" / "extracted" / "product.img",
    "vendor": ROOT / "hard-rom" / "extracted" / "vendor.img",
    "odm": ROOT / "hard-rom" / "extracted" / "odm.img",
}
TARGET_EXTS = {".apk", ".jar", ".apex"}
JADX_EXTS = {".apk", ".jar"}
CONFIG_EXTS = {".prop", ".rc", ".xml", ".cil"}
CONFIG_PATH_MARKERS = (
    "/etc/init/",
    "/etc/permissions/",
    "/etc/sysconfig/",
    "/etc/selinux/",
    "/etc/vintf/",
    "/etc/default-permissions/",
    "/etc/preferred-apps/",
    "/etc/compatconfig/",
)
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


@dataclass(frozen=True)
class ListedFile:
    partition: str
    image: Path
    rel_path: str
    size: int
    packed_size: int
    attr: str

    @property
    def ext(self) -> str:
        return Path(self.rel_path).suffix.lower()

    @property
    def kind(self) -> str:
        if self.ext == ".apk":
            return "apk"
        if self.ext == ".jar":
            return "jar"
        if self.ext == ".apex":
            return "apex"
        if is_config_path(self.rel_path):
            return "config"
        return "other"


def run(cmd: list[str], *, stdout=None, stderr=None, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, stdout=stdout, stderr=stderr, text=True, check=check)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise SystemExit(f"missing required tool: {name}")
    return path


def ensure_dirs(out: Path) -> dict[str, Path]:
    paths = {
        "manifest": out / "manifest",
        "raw": out / "raw",
        "apex": out / "apex",
        "jadx": out / "jadx",
        "logs": out / "logs",
        "indexes": out / "indexes",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    return paths


def parse_7z_ba_line(partition: str, image: Path, line: str) -> ListedFile | None:
    line = line.rstrip("\n")
    if not line:
        return None
    parts = line.split(maxsplit=5)
    if len(parts) < 4:
        return None
    attr = parts[2]
    if attr.startswith("D"):
        return None
    if len(parts) >= 6 and parts[3].isdigit():
        size = int(parts[3])
        packed = int(parts[4]) if parts[4].isdigit() else 0
        rel_path = parts[5]
    else:
        size = 0
        packed = 0
        rel_path = parts[3]
    if not rel_path or rel_path.endswith("/"):
        return None
    return ListedFile(partition, image, rel_path, size, packed, attr)


def list_partition(partition: str, image: Path) -> list[ListedFile]:
    if not image.is_file():
        raise SystemExit(f"missing image for {partition}: {image}")
    proc = subprocess.run(
        ["7z", "l", "-ba", str(image)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    rows: list[ListedFile] = []
    for line in proc.stdout.splitlines():
        item = parse_7z_ba_line(partition, image, line)
        if item is not None:
            rows.append(item)
    return rows


def is_config_path(rel_path: str) -> bool:
    lower = "/" + rel_path.lower()
    name = Path(rel_path).name.lower()
    if name == "build.prop":
        return True
    if Path(rel_path).suffix.lower() in CONFIG_EXTS and any(marker in lower for marker in CONFIG_PATH_MARKERS):
        return True
    if name.endswith(("_file_contexts", "_property_contexts", "_service_contexts", "_seapp_contexts")):
        return True
    if name in {"file_contexts", "property_contexts", "service_contexts", "seapp_contexts"}:
        return True
    return False


def sanitize_name(partition: str, rel_path: str) -> str:
    base = f"{partition}__{rel_path}"
    base = re.sub(r"[^A-Za-z0-9._+-]+", "__", base)
    base = base.strip("._")
    if len(base) > 180:
        digest = hashlib.sha256(base.encode()).hexdigest()[:12]
        base = base[:160] + "__" + digest
    return base


def write_tsv(path: Path, header: list[str], rows: list[list[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def read_tsv_dicts(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def inventory(out: Path) -> None:
    require_tool("7z")
    paths = ensure_dirs(out)
    all_rows: list[ListedFile] = []
    for partition, image in PARTITIONS.items():
        print(f"inventory: {partition}")
        all_rows.extend(list_partition(partition, image))

    partition_rows: list[list[object]] = []
    targets: list[ListedFile] = []
    configs: list[ListedFile] = []
    for item in all_rows:
        partition_rows.append([
            item.partition,
            item.rel_path,
            item.size,
            item.packed_size,
            item.kind,
            item.image,
        ])
        if item.ext in TARGET_EXTS:
            targets.append(item)
        elif is_config_path(item.rel_path):
            configs.append(item)

    write_tsv(
        paths["manifest"] / "partition-files.tsv",
        ["partition", "rel_path", "size", "packed_size", "kind", "image"],
        partition_rows,
    )
    write_tsv(
        paths["manifest"] / "decompile-targets.tsv",
        ["name", "partition", "rel_path", "kind", "size", "image"],
        [[sanitize_name(i.partition, i.rel_path), i.partition, i.rel_path, i.kind, i.size, i.image] for i in targets],
    )
    write_tsv(
        paths["manifest"] / "config-targets.tsv",
        ["name", "partition", "rel_path", "kind", "size", "image"],
        [[sanitize_name(i.partition, i.rel_path), i.partition, i.rel_path, i.kind, i.size, i.image] for i in configs],
    )
    write_readme(out, len(all_rows), len(targets), len(configs))
    print(f"files: {len(all_rows)}")
    print(f"decompile targets: {len(targets)}")
    print(f"config targets: {len(configs)}")


def extract_paths(image: Path, out_dir: Path, rel_paths: list[str], log: Path) -> None:
    if not rel_paths:
        return
    out_dir.mkdir(parents=True, exist_ok=True)
    cmd = ["7z", "x", "-y", str(image), f"-o{out_dir}", *rel_paths]
    with log.open("a", encoding="utf-8") as fh:
        fh.write("$ " + " ".join(cmd) + "\n")
        proc = subprocess.run(cmd, text=True, stdout=fh, stderr=subprocess.STDOUT)
        if proc.returncode != 0:
            raise SystemExit(f"7z extract failed for {image}; see {log}")


def chunked(items: list[str], size: int) -> list[list[str]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def extract(out: Path, *, extract_apex_payloads: bool) -> None:
    require_tool("7z")
    paths = ensure_dirs(out)
    target_path = paths["manifest"] / "decompile-targets.tsv"
    config_path = paths["manifest"] / "config-targets.tsv"
    if not target_path.is_file() or not config_path.is_file():
        inventory(out)

    target_rows = read_tsv_dicts(target_path)
    config_rows = read_tsv_dicts(config_path)
    rows = target_rows + config_rows
    by_partition: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_partition.setdefault(row["partition"], []).append(row)

    extracted_rows: list[list[object]] = []
    for partition, part_rows in sorted(by_partition.items()):
        image = PARTITIONS[partition]
        rel_paths = sorted({r["rel_path"] for r in part_rows})
        print(f"extract: {partition} targets={len(rel_paths)}")
        for idx, batch in enumerate(chunked(rel_paths, 80), start=1):
            extract_paths(image, paths["raw"] / partition, batch, paths["logs"] / f"extract-{partition}.log")
            print(f"extract: {partition} batch {idx}/{(len(rel_paths) + 79) // 80}")
        for row in part_rows:
            raw_path = paths["raw"] / row["partition"] / row["rel_path"]
            if raw_path.is_file():
                extracted_rows.append([
                    row["name"],
                    row["partition"],
                    row["rel_path"],
                    row["kind"],
                    raw_path,
                    sha256_file(raw_path),
                ])

    write_tsv(
        paths["manifest"] / "extracted-targets.tsv",
        ["name", "partition", "rel_path", "kind", "raw_path", "sha256"],
        extracted_rows,
    )
    if extract_apex_payloads:
        extract_apex(out)


def extract_apex(out: Path) -> None:
    paths = ensure_dirs(out)
    extracted = read_tsv_dicts(paths["manifest"] / "extracted-targets.tsv")
    apex_rows = [r for r in extracted if r["kind"] == "apex"]
    nested_rows: list[list[object]] = []
    for row in apex_rows:
        apex_path = Path(row["raw_path"])
        apex_name = sanitize_name(row["partition"], row["rel_path"])
        apex_out = paths["apex"] / apex_name
        if not (apex_out / ".extracted").exists():
            print(f"apex: extract {apex_name}")
            run(["7z", "x", "-y", str(apex_path), f"-o{apex_out}"], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
            (apex_out / ".extracted").write_text("ok\n", encoding="utf-8")
        payload = apex_out / "apex_payload.img"
        if not payload.is_file():
            continue
        proc = subprocess.run(["7z", "l", "-ba", str(payload)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            continue
        nested: list[ListedFile] = []
        for line in proc.stdout.splitlines():
            item = parse_7z_ba_line(row["partition"], payload, line)
            if item and item.ext in JADX_EXTS:
                nested.append(item)
        if not nested:
            continue
        payload_out = apex_out / "payload"
        for batch in chunked([n.rel_path for n in nested], 80):
            extract_paths(payload, payload_out, batch, paths["logs"] / f"extract-apex-{apex_name}.log")
        for item in nested:
            raw_path = payload_out / item.rel_path
            if raw_path.is_file():
                nested_name = sanitize_name(f"apex_{apex_name}", item.rel_path)
                nested_rows.append([
                    nested_name,
                    row["partition"],
                    row["rel_path"],
                    item.rel_path,
                    item.kind,
                    raw_path,
                    sha256_file(raw_path),
                ])
    write_tsv(
        paths["manifest"] / "apex-payload-targets.tsv",
        ["name", "source_partition", "source_apex", "rel_path", "kind", "raw_path", "sha256"],
        nested_rows,
    )


def jadx_decompile(out: Path, limit: int | None) -> None:
    require_tool("jadx")
    paths = ensure_dirs(out)
    extracted_path = paths["manifest"] / "extracted-targets.tsv"
    if not extracted_path.is_file():
        extract(out, extract_apex_payloads=True)
    rows = [r for r in read_tsv_dicts(extracted_path) if Path(r["raw_path"]).suffix.lower() in JADX_EXTS]
    apex_targets = paths["manifest"] / "apex-payload-targets.tsv"
    if apex_targets.is_file():
        rows.extend(read_tsv_dicts(apex_targets))
    if limit is not None:
        rows = rows[:limit]

    status_rows: list[list[object]] = []
    for index, row in enumerate(rows, start=1):
        name = row["name"]
        raw_path = Path(row["raw_path"])
        out_dir = paths["jadx"] / name
        log = paths["logs"] / f"jadx-{name}.log"
        if out_dir.is_dir():
            status = "exists"
            code = 0
        else:
            print(f"jadx: {index}/{len(rows)} {name}")
            cmd = ["jadx", "--show-bad-code", "-d", str(out_dir), str(raw_path)]
            with log.open("w", encoding="utf-8") as fh:
                proc = subprocess.run(cmd, text=True, stdout=fh, stderr=subprocess.STDOUT)
            code = proc.returncode
            if code in (0, 3):
                status = "ok" if code == 0 else "recoverable-errors"
            else:
                status = "failed"
                print(f"jadx failed: {name}; see {log}", file=sys.stderr)
        java_count, xml_count, file_count = count_decompiled_files(out_dir)
        status_rows.append([
            name,
            raw_path,
            status,
            code,
            out_dir,
            java_count,
            xml_count,
            file_count,
        ])
    write_tsv(
        paths["manifest"] / "jadx-status.tsv",
        ["name", "raw_path", "status", "exit_code", "jadx_dir", "java_files", "xml_files", "total_files"],
        status_rows,
    )


def count_decompiled_files(path: Path) -> tuple[int, int, int]:
    if not path.is_dir():
        return (0, 0, 0)
    java_count = 0
    xml_count = 0
    file_count = 0
    for file_path in path.rglob("*"):
        if not file_path.is_file():
            continue
        file_count += 1
        suffix = file_path.suffix.lower()
        if suffix == ".java":
            java_count += 1
        elif suffix == ".xml":
            xml_count += 1
    return java_count, xml_count, file_count


def get_android_attr(elem: ET.Element, name: str) -> str:
    return elem.attrib.get(ANDROID_NS + name, elem.attrib.get(name, ""))


def parse_manifest(manifest: Path) -> dict[str, object]:
    result: dict[str, object] = {
        "package": "",
        "sharedUserId": "",
        "versionCode": "",
        "versionName": "",
        "minSdkVersion": "",
        "targetSdkVersion": "",
        "overlayTarget": "",
        "overlayIsStatic": "",
        "overlayPriority": "",
        "overlayCategory": "",
        "uses_permissions": [],
        "components": [],
        "intent_filters": [],
    }
    try:
        root = ET.parse(manifest).getroot()
    except Exception:
        return result
    result["package"] = root.attrib.get("package", "")
    result["sharedUserId"] = root.attrib.get(ANDROID_NS + "sharedUserId", "")
    result["versionCode"] = root.attrib.get(ANDROID_NS + "versionCode", root.attrib.get("versionCode", ""))
    result["versionName"] = root.attrib.get(ANDROID_NS + "versionName", root.attrib.get("versionName", ""))
    permissions: list[str] = []
    components: list[tuple[str, str, str]] = []
    intent_filters: list[tuple[str, str, str, str, str, str]] = []
    for child in root:
        tag = child.tag.split("}", 1)[-1]
        if tag == "uses-sdk":
            result["minSdkVersion"] = get_android_attr(child, "minSdkVersion")
            result["targetSdkVersion"] = get_android_attr(child, "targetSdkVersion")
        if tag == "overlay":
            result["overlayTarget"] = get_android_attr(child, "targetPackage")
            result["overlayIsStatic"] = get_android_attr(child, "isStatic")
            result["overlayPriority"] = get_android_attr(child, "priority")
            result["overlayCategory"] = get_android_attr(child, "category")
        if tag == "uses-permission":
            name = get_android_attr(child, "name")
            if name:
                permissions.append(name)
        if tag != "application":
            continue
        for comp in child:
            comp_tag = comp.tag.split("}", 1)[-1]
            if comp_tag not in {"activity", "activity-alias", "service", "receiver", "provider"}:
                continue
            name = get_android_attr(comp, "name")
            exported = get_android_attr(comp, "exported")
            components.append((comp_tag, name, exported))
            filter_index = 0
            for intent_filter in comp:
                if intent_filter.tag.split("}", 1)[-1] != "intent-filter":
                    continue
                filter_index += 1
                for item in intent_filter:
                    item_tag = item.tag.split("}", 1)[-1]
                    if item_tag == "action":
                        intent_filters.append((comp_tag, name, str(filter_index), "action", get_android_attr(item, "name"), ""))
                    elif item_tag == "category":
                        intent_filters.append((comp_tag, name, str(filter_index), "category", get_android_attr(item, "name"), ""))
                    elif item_tag == "data":
                        value = "|".join(
                            part
                            for part in [
                                f"scheme={get_android_attr(item, 'scheme')}" if get_android_attr(item, "scheme") else "",
                                f"host={get_android_attr(item, 'host')}" if get_android_attr(item, "host") else "",
                                f"path={get_android_attr(item, 'path')}" if get_android_attr(item, "path") else "",
                                f"mimeType={get_android_attr(item, 'mimeType')}" if get_android_attr(item, "mimeType") else "",
                            ]
                            if part
                        )
                        intent_filters.append((comp_tag, name, str(filter_index), "data", value, ""))
    result["uses_permissions"] = permissions
    result["components"] = components
    result["intent_filters"] = intent_filters
    return result


def parse_xml_file(path: Path) -> ET.Element | None:
    try:
        return ET.parse(path).getroot()
    except Exception:
        return None


def build_extracted_lookup(out: Path) -> dict[str, dict[str, str]]:
    path = out / "manifest" / "extracted-targets.tsv"
    if not path.is_file():
        return {}
    return {row["name"]: row for row in read_tsv_dicts(path)}


def infer_partition_rel_from_raw(raw_path: str) -> tuple[str, str]:
    marker = "/raw/"
    if marker not in raw_path:
        return ("", "")
    rest = raw_path.split(marker, 1)[1]
    parts = rest.split("/", 1)
    if len(parts) == 1:
        return (parts[0], "")
    return (parts[0], parts[1])


def is_priv_path(rel_path: str) -> str:
    return "yes" if "/priv-app/" in f"/{rel_path}" or rel_path.startswith("priv-app/") else "no"


def keytool_path() -> str | None:
    preferred = Path("/opt/homebrew/opt/openjdk/bin/keytool")
    if preferred.exists():
        return str(preferred)
    return shutil.which("keytool")


def cert_digest(raw_path: Path, keytool: str | None) -> tuple[str, str, str, str, str]:
    if raw_path.suffix.lower() != ".apk":
        return ("not-apk", "", "", "", "")
    if keytool is None:
        return ("missing-keytool", "", "", "", "")
    proc = subprocess.run(
        [keytool, "-printcert", "-jarfile", str(raw_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if proc.returncode != 0:
        return ("keytool-failed", "", "", "", "")
    owner = ""
    issuer = ""
    sha256 = ""
    algorithm = ""
    for line in proc.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("Owner:"):
            owner = stripped.removeprefix("Owner:").strip()
        elif stripped.startswith("Issuer:"):
            issuer = stripped.removeprefix("Issuer:").strip()
        elif stripped.startswith("SHA256:"):
            sha256 = stripped.removeprefix("SHA256:").strip().replace(":", "")
        elif stripped.startswith("Signature algorithm name:"):
            algorithm = stripped.removeprefix("Signature algorithm name:").strip()
    status = "ok" if sha256 else "no-cert-sha256"
    return (status, sha256, owner, issuer, algorithm)


def collect_config_indexes(out: Path) -> tuple[list[list[object]], list[list[object]], list[list[object]]]:
    raw = out / "raw"
    privapp_rows: list[list[object]] = []
    sysconfig_rows: list[list[object]] = []
    permission_config_rows: list[list[object]] = []
    for path in raw.rglob("*.xml"):
        root = parse_xml_file(path)
        if root is None:
            continue
        source = str(path.relative_to(out))
        for elem in root.iter():
            tag = elem.tag.split("}", 1)[-1]
            if tag == "privapp-permissions":
                package = elem.attrib.get("package", "")
                for child in elem:
                    child_tag = child.tag.split("}", 1)[-1]
                    if child_tag in {"permission", "deny-permission"}:
                        privapp_rows.append([source, package, child_tag, child.attrib.get("name", "")])
            package = elem.attrib.get("package", "")
            if package:
                sysconfig_rows.append([source, tag, package, attrs_to_string(elem.attrib)])
            if tag in {"library", "feature", "permission", "assign-permission"}:
                permission_config_rows.append([source, tag, elem.attrib.get("name", ""), elem.attrib.get("file", ""), elem.attrib.get("uid", ""), attrs_to_string(elem.attrib)])
    return privapp_rows, sysconfig_rows, permission_config_rows


def attrs_to_string(attrs: dict[str, str]) -> str:
    return ";".join(f"{k}={v}" for k, v in sorted(attrs.items()))


def collect_classes(status_rows: list[dict[str, str]]) -> list[list[object]]:
    rows: list[list[object]] = []
    for status in status_rows:
        sources = Path(status["jadx_dir"]) / "sources"
        if not sources.is_dir():
            continue
        for java in sources.rglob("*.java"):
            rel = java.relative_to(sources)
            class_name = ".".join(rel.with_suffix("").parts)
            rows.append([status["name"], class_name, java])
    return rows


def collect_resources(status_rows: list[dict[str, str]]) -> tuple[list[list[object]], list[list[object]]]:
    resource_rows: list[list[object]] = []
    overlayable_rows: list[list[object]] = []
    for status in status_rows:
        jadx_dir = Path(status["jadx_dir"])
        manifest = jadx_dir / "resources" / "AndroidManifest.xml"
        parsed = parse_manifest(manifest) if manifest.is_file() else {"package": ""}
        package_name = str(parsed.get("package", ""))
        public_xml = jadx_dir / "resources" / "res" / "values" / "public.xml"
        root = parse_xml_file(public_xml)
        if root is not None:
            for elem in root.iter():
                tag = elem.tag.split("}", 1)[-1]
                if tag == "public":
                    resource_rows.append([
                        status["name"],
                        package_name,
                        elem.attrib.get("type", ""),
                        elem.attrib.get("name", ""),
                        elem.attrib.get("id", ""),
                        public_xml,
                    ])
        for overlayable_xml in (jadx_dir / "resources" / "res").rglob("overlayable*.xml") if (jadx_dir / "resources" / "res").is_dir() else []:
            root = parse_xml_file(overlayable_xml)
            if root is None:
                continue
            for overlayable in root.iter():
                if overlayable.tag.split("}", 1)[-1] != "overlayable":
                    continue
                overlayable_name = overlayable.attrib.get("name", "")
                for policy in overlayable:
                    if policy.tag.split("}", 1)[-1] != "policy":
                        continue
                    policy_type = policy.attrib.get("type", "")
                    for item in policy:
                        item_tag = item.tag.split("}", 1)[-1]
                        overlayable_rows.append([
                            status["name"],
                            package_name,
                            overlayable_name,
                            policy_type,
                            item_tag,
                            item.attrib.get("type", ""),
                            item.attrib.get("name", ""),
                            overlayable_xml,
                        ])
    return resource_rows, overlayable_rows


def build_indexes(out: Path) -> None:
    paths = ensure_dirs(out)
    status_path = paths["manifest"] / "jadx-status.tsv"
    if not status_path.is_file():
        raise SystemExit(f"missing {status_path}; run decompile first")
    status_rows = read_tsv_dicts(status_path)
    extracted_lookup = build_extracted_lookup(out)
    keytool = keytool_path()
    package_rows: list[list[object]] = []
    component_rows: list[list[object]] = []
    permission_rows: list[list[object]] = []
    overlay_rows: list[list[object]] = []
    intent_rows: list[list[object]] = []
    signature_rows: list[list[object]] = []
    for row in status_rows:
        jadx_dir = Path(row["jadx_dir"])
        manifest = jadx_dir / "resources" / "AndroidManifest.xml"
        extracted = extracted_lookup.get(row["name"], {})
        partition = extracted.get("partition", "")
        rel_path = extracted.get("rel_path", "")
        kind = extracted.get("kind", Path(row["raw_path"]).suffix.lower().lstrip("."))
        try:
            fallback_size = str(Path(row["raw_path"]).stat().st_size)
        except OSError:
            fallback_size = ""
        size = extracted.get("size", "") or fallback_size
        sha256 = extracted.get("sha256", "")
        if not rel_path:
            partition, rel_path = infer_partition_rel_from_raw(row["raw_path"])
        raw_path = Path(row["raw_path"])
        artifact_type = raw_path.suffix.lower().lstrip(".")
        sig_status, sig_sha256, sig_owner, sig_issuer, sig_algorithm = cert_digest(raw_path, keytool)
        signature_rows.append([
            row["name"],
            partition,
            rel_path,
            artifact_type,
            sig_status,
            sig_sha256,
            sig_owner,
            sig_issuer,
            sig_algorithm,
        ])
        if not manifest.is_file():
            continue
        parsed = parse_manifest(manifest)
        package_name = str(parsed["package"])
        package_rows.append([
            row["name"],
            partition,
            rel_path,
            kind,
            size,
            sha256,
            is_priv_path(rel_path),
            package_name,
            parsed["versionCode"],
            parsed["versionName"],
            parsed["minSdkVersion"],
            parsed["targetSdkVersion"],
            parsed["sharedUserId"],
            parsed["overlayTarget"],
            row["raw_path"],
            row["status"],
            row["java_files"],
            row["xml_files"],
            row["total_files"],
        ])
        if parsed["overlayTarget"]:
            overlay_rows.append([
                package_name,
                parsed["overlayTarget"],
                parsed["overlayIsStatic"],
                parsed["overlayPriority"],
                parsed["overlayCategory"],
                partition,
                rel_path,
                row["name"],
            ])
        for perm in parsed["uses_permissions"]:
            permission_rows.append([package_name, perm, row["name"]])
        for comp_type, comp_name, exported in parsed["components"]:
            component_rows.append([package_name, comp_type, comp_name, exported, row["name"]])
        for comp_type, comp_name, filter_index, entry_type, value, extra in parsed["intent_filters"]:
            intent_rows.append([package_name, comp_type, comp_name, filter_index, entry_type, value, extra, row["name"]])

    write_tsv(
        paths["indexes"] / "packages.tsv",
        [
            "name",
            "partition",
            "rel_path",
            "kind",
            "size",
            "sha256",
            "priv_app",
            "package",
            "versionCode",
            "versionName",
            "minSdkVersion",
            "targetSdkVersion",
            "sharedUserId",
            "overlayTarget",
            "raw_path",
            "status",
            "java_files",
            "xml_files",
            "total_files",
        ],
        package_rows,
    )
    write_tsv(
        paths["indexes"] / "components.tsv",
        ["package", "type", "name", "exported", "source_name"],
        component_rows,
    )
    write_tsv(
        paths["indexes"] / "uses-permissions.tsv",
        ["package", "permission", "source_name"],
        permission_rows,
    )
    write_tsv(
        paths["indexes"] / "overlays.tsv",
        ["package", "targetPackage", "isStatic", "priority", "category", "partition", "rel_path", "source_name"],
        overlay_rows,
    )
    write_tsv(
        paths["indexes"] / "intent-filters.tsv",
        ["package", "component_type", "component_name", "filter_index", "entry_type", "value", "extra", "source_name"],
        intent_rows,
    )
    write_tsv(
        paths["indexes"] / "signatures.tsv",
        ["source_name", "partition", "rel_path", "artifact_type", "signature_status", "cert_sha256", "owner", "issuer", "algorithm"],
        signature_rows,
    )
    privapp_rows, sysconfig_rows, permission_config_rows = collect_config_indexes(out)
    write_tsv(
        paths["indexes"] / "privapp-permissions.tsv",
        ["source_file", "package", "entry_type", "permission"],
        privapp_rows,
    )
    write_tsv(
        paths["indexes"] / "sysconfig-packages.tsv",
        ["source_file", "tag", "package", "attrs"],
        sysconfig_rows,
    )
    write_tsv(
        paths["indexes"] / "permission-config.tsv",
        ["source_file", "tag", "name", "file", "uid", "attrs"],
        permission_config_rows,
    )
    class_rows = collect_classes(status_rows)
    write_tsv(
        paths["indexes"] / "classes.tsv",
        ["source_name", "class", "java_path"],
        class_rows,
    )
    resource_rows, overlayable_rows = collect_resources(status_rows)
    write_tsv(
        paths["indexes"] / "resources-public.tsv",
        ["source_name", "package", "type", "name", "id", "source_file"],
        resource_rows,
    )
    write_tsv(
        paths["indexes"] / "resources-overlayable.tsv",
        ["source_name", "package", "overlayable", "policy", "item_tag", "type", "name", "source_file"],
        overlayable_rows,
    )
    write_summary(
        out,
        status_rows,
        package_rows,
        component_rows,
        permission_rows,
        overlay_rows,
        intent_rows,
        privapp_rows,
        sysconfig_rows,
        permission_config_rows,
        signature_rows,
        class_rows,
        resource_rows,
        overlayable_rows,
    )


def write_readme(out: Path, file_count: int, target_count: int, config_count: int) -> None:
    rel = out.relative_to(ROOT)
    content = f"""# Smartisan OS 8.5.3 ROM Static Knowledge Base

This directory is generated from OTA-extracted partition images only. It is the
ROM static layer and intentionally excludes `/data/app` live updated-system
packages.

Generated path:

```text
{rel}
```

Initial inventory:

```text
partition files: {file_count}
APK/JAR/APEX targets: {target_count}
config targets: {config_count}
```

Main files:

```text
manifest/partition-files.tsv      all files listed from static partition images
manifest/decompile-targets.tsv    APK/JAR/APEX targets from ROM partitions
manifest/config-targets.tsv       build/init/permission/SELinux config targets
manifest/extracted-targets.tsv    extracted raw artifacts with SHA256
manifest/jadx-status.tsv          decompile status and source file counts
indexes/packages.tsv              package-level manifest index
indexes/components.tsv            activity/service/receiver/provider index
indexes/uses-permissions.tsv      package permission index
indexes/intent-filters.tsv        manifest intent-filter index
indexes/overlays.tsv              static/resource overlay target index
indexes/privapp-permissions.tsv   priv-app permission config index
indexes/sysconfig-packages.tsv    sysconfig package allowlist/reference index
indexes/signatures.tsv            APK signer certificate digest index
indexes/classes.tsv               Java class lookup index
indexes/resources-public.tsv      public resource ID lookup index
indexes/resources-overlayable.tsv overlayable resource declaration lookup
indexes/summary.md                generated source knowledge summary
indexes/knowledge-map.md          system construction map
indexes/build-modification-map.md image modification and build map
```
"""
    (out / "README.md").write_text(content, encoding="utf-8")


def write_summary(
    out: Path,
    status_rows: list[dict[str, str]],
    package_rows: list[list[object]],
    component_rows: list[list[object]],
    permission_rows: list[list[object]],
    overlay_rows: list[list[object]],
    intent_rows: list[list[object]],
    privapp_rows: list[list[object]],
    sysconfig_rows: list[list[object]],
    permission_config_rows: list[list[object]],
    signature_rows: list[list[object]],
    class_rows: list[list[object]],
    resource_rows: list[list[object]],
    overlayable_rows: list[list[object]],
) -> None:
    paths = ensure_dirs(out)
    status_counts: dict[str, int] = {}
    java_total = 0
    xml_total = 0
    file_total = 0
    for row in status_rows:
        status_counts[row["status"]] = status_counts.get(row["status"], 0) + 1
        java_total += int(row.get("java_files") or 0)
        xml_total += int(row.get("xml_files") or 0)
        file_total += int(row.get("total_files") or 0)

    def count_components(kind: str) -> int:
        return sum(1 for row in component_rows if row[1] == kind)

    def count_signatures(status: str, artifact_type: str | None = None) -> int:
        total = 0
        for row in signature_rows:
            if row[4] != status:
                continue
            if artifact_type is not None and row[3] != artifact_type:
                continue
            total += 1
        return total

    lines = [
        "# ROM Static Source Summary",
        "",
        "Scope: OTA-extracted ROM partition images only; `/data/app` is excluded.",
        "",
        "## Decompiled Corpus",
        "",
        "```text",
        f"decompile targets indexed: {len(status_rows)}",
        f"packages with decoded manifest: {len(package_rows)}",
        f"class index rows: {len(class_rows)}",
        f"java files: {java_total}",
        f"xml files: {xml_total}",
        f"total decompiled files: {file_total}",
        "status counts:",
    ]
    for key in sorted(status_counts):
        lines.append(f"  {key}: {status_counts[key]}")
    lines.extend([
        "```",
        "",
        "## Manifest Components",
        "",
        "```text",
        f"activities: {count_components('activity')}",
        f"activity-aliases: {count_components('activity-alias')}",
        f"services: {count_components('service')}",
        f"receivers: {count_components('receiver')}",
        f"providers: {count_components('provider')}",
        f"uses-permission rows: {len(permission_rows)}",
        f"intent-filter rows: {len(intent_rows)}",
        f"overlay rows: {len(overlay_rows)}",
        f"privapp permission rows: {len(privapp_rows)}",
        f"sysconfig package rows: {len(sysconfig_rows)}",
        f"permission config rows: {len(permission_config_rows)}",
        f"public resource rows: {len(resource_rows)}",
        f"overlayable rows: {len(overlayable_rows)}",
        f"APK signature ok rows: {count_signatures('ok', 'apk')}",
        f"APK signature issue rows: {len([row for row in signature_rows if row[3] == 'apk' and row[4] != 'ok'])}",
        f"non-APK signature rows: {count_signatures('not-apk')}",
        "```",
        "",
        "## Modification Surface Notes",
        "",
        "- Dynamic partition edits should start from exact-current super patching, not `fastboot flash system`.",
        "- System, product, system_ext, vendor, and odm APK/JAR/APEX artifacts are tracked separately by partition.",
        "- For package removal, inspect package manifest rows, privapp permissions, sysconfig allowlists, overlays, and launcher/package-cache state before rebuilding.",
        "- Framework/resource edits need extra caution around `framework-res.apk`, `framework-smartisanos-res.apk`, `ResourcesManagerSmtEx`, `AssetManagerSmtEx`, and Smartisan icon redirection.",
        "- Same-package replacement remains higher risk than deletion; previous BrowserChrome replacement failures should be treated as a package/resources state hazard.",
        "",
    ])
    (paths["indexes"] / "summary.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["inventory", "extract", "decompile", "index", "all"])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--no-apex-payloads", action="store_true")
    parser.add_argument("--limit", type=int, default=None, help="decompile only the first N targets")
    args = parser.parse_args()

    out = args.out
    if args.command == "inventory":
        inventory(out)
    elif args.command == "extract":
        extract(out, extract_apex_payloads=not args.no_apex_payloads)
    elif args.command == "decompile":
        jadx_decompile(out, args.limit)
    elif args.command == "index":
        build_indexes(out)
    elif args.command == "all":
        inventory(out)
        extract(out, extract_apex_payloads=not args.no_apex_payloads)
        jadx_decompile(out, args.limit)
        build_indexes(out)


if __name__ == "__main__":
    main()
