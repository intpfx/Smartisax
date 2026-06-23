#!/usr/bin/env python3
"""Audit WebView A-SIG PackageManager acceptance evidence.

This helper is read-only with respect to the ROM and device. It compares the
stock WebView, the source-built M150 WebView, and the stock-carrier adapted
candidate against the Android 11 PackageManager/system-scan signing path.

It intentionally records two different facts:

* apksigner full verification, which should fail for a stock-carrier APK whose
  payload no longer matches the stock signing block.
* Android-style cert-only v2/v3 signer parsing, which mirrors the part of
  ApkSignatureVerifier.unsafeGetCertsWithoutVerification() that still verifies
  the signer block and certificate/public-key relationship while skipping APK
  content digest verification.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import struct
import subprocess
import warnings
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import dsa, ec, padding, rsa


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "reverse" / "smartisan-8.5.3-rom-static"

STOCK_WEBVIEW_APK = KB / "raw" / "product" / "app" / "webview" / "webview.apk"
SOURCEBUILT_DIR = ROOT / "apks" / "webview-donor-inbox" / "sourcebuilt-system-webview-150-0-7871-28"
SOURCEBUILT_APK = SOURCEBUILT_DIR / "SystemWebView.apk"
STOCK_CARRIER_APK = SOURCEBUILT_DIR / "SystemWebView-stock-carrier.apk"

STOCK_CERT_SHA256 = "4e95c9164652e2d13a52294d2b65603bc317bb95fd3f0b81d4d76c8dc8e5fdb1"
R2_ANDROID_SDK = 30

APKSIGNER = ROOT / "third_party" / "android-build-tools" / "build-tools_r35.0.1_macosx" / "android-15" / "apksigner"
JAVA_HOME = Path("/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home")
OPENJDK_BIN = Path("/opt/homebrew/opt/openjdk/bin")

OUT_MD = ROOT / "docs" / "research" / "webview-a-sig-package-manager-audit.md"
OUT_TSV = KB / "manifest" / "webview-a-sig-package-manager-audit.tsv"
OUT_DIR = ROOT / "hard-rom" / "inspect" / "browser-webview-a-sig-package-manager"
OUT_JSON = OUT_DIR / "webview-a-sig-package-manager-audit.json"

DOCS_INDEX = ROOT / "docs" / "README.md"
SIGNING_PLAN_MD = ROOT / "docs" / "research" / "webview-signing-transition-plan.md"
SYSTEM_SIGNATURE_MD = ROOT / "docs" / "research" / "system-apk-signature-boundary.md"

PACKAGE_PARTITIONS = KB / "jadx" / "system__system__framework__framework.jar" / "sources" / "android" / "content" / "pm" / "PackagePartitions.java"
PMS = KB / "jadx" / "system__system__framework__services.jar" / "sources" / "com" / "android" / "server" / "pm" / "PackageManagerService.java"
PARSING_UTILS = KB / "jadx" / "system__system__framework__framework.jar" / "sources" / "android" / "content" / "pm" / "parsing" / "ParsingPackageUtils.java"
APK_VERIFIER = KB / "jadx" / "system__system__framework__framework.jar" / "sources" / "android" / "util" / "apk" / "ApkSignatureVerifier.java"
APK_V2 = KB / "jadx" / "system__system__framework__framework.jar" / "sources" / "android" / "util" / "apk" / "ApkSignatureSchemeV2Verifier.java"
APK_V3 = KB / "jadx" / "system__system__framework__framework.jar" / "sources" / "android" / "util" / "apk" / "ApkSignatureSchemeV3Verifier.java"
PMS_UTILS = KB / "jadx" / "system__system__framework__services.jar" / "sources" / "com" / "android" / "server" / "pm" / "PackageManagerServiceUtils.java"
PACKAGE_CACHER = KB / "jadx" / "system__system__framework__services.jar" / "sources" / "com" / "android" / "server" / "pm" / "parsing" / "PackageCacher.java"

EOCD_MAGIC = b"PK\x05\x06"
APK_SIG_MAGIC = b"APK Sig Block 42"
V2_ID = 0x7109871A
V3_ID = 0xF05368C0


@dataclass(frozen=True)
class SourceFinding:
    finding_id: str
    status: str
    source: str
    line: int
    evidence: str
    impact: str


@dataclass(frozen=True)
class SchemeSigner:
    scheme: str
    status: str
    signer_count: int
    selected_algorithm: str
    min_sdk: int | None
    max_sdk: int | None
    platform_supported: bool | None
    certificate_sha256: str
    certificate_subject: str
    public_key_sha256: str
    signer_signature_verified: bool
    certificate_public_key_matches: bool
    notes: str


@dataclass(frozen=True)
class ApkAudit:
    apk_id: str
    path: str
    status: str
    sha256: str
    size_bytes: int
    signing_block_ids: str
    apksigner_status: str
    apksigner_log: str
    apksigner_summary: str
    v2_status: str
    v2_cert_sha256: str
    v3_status: str
    v3_cert_sha256: str
    unsafe_preferred_scheme: str
    unsafe_cert_sha256: str
    unsafe_signer_signature_verified: bool
    unsafe_cert_matches_stock: bool
    package_manager_system_scan_prediction: str
    notes: str


class ParseError(ValueError):
    pass


class Cursor:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def remaining(self) -> int:
        return len(self.data) - self.pos

    def read_u32(self) -> int:
        if self.remaining() < 4:
            raise ParseError("underflow while reading uint32")
        value = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return value

    def read_i32(self) -> int:
        if self.remaining() < 4:
            raise ParseError("underflow while reading int32")
        value = struct.unpack_from("<i", self.data, self.pos)[0]
        self.pos += 4
        return value

    def read_bytes(self, length: int) -> bytes:
        if length < 0 or length > self.remaining():
            raise ParseError(f"underflow while reading {length} bytes")
        value = self.data[self.pos : self.pos + length]
        self.pos += length
        return value

    def read_lp_bytes(self) -> bytes:
        return self.read_bytes(self.read_u32())

    def read_lp_cursor(self) -> "Cursor":
        return Cursor(self.read_lp_bytes())


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def find_line(path: Path, pattern: str) -> int:
    if not path.exists():
        return 0
    for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        if pattern in line:
            return lineno
    return 0


def source_ref(path: Path, line: int) -> str:
    return f"{rel(path)}:{line}" if line else rel(path)


def find_eocd(data: bytes) -> int:
    start = max(0, len(data) - 0xFFFF - 22)
    for offset in range(len(data) - 22, start - 1, -1):
        if data[offset : offset + 4] != EOCD_MAGIC:
            continue
        comment_len = struct.unpack_from("<H", data, offset + 20)[0]
        if offset + 22 + comment_len == len(data):
            return offset
    raise ParseError("EOCD not found")


def central_dir_offset(data: bytes, eocd_offset: int) -> int:
    return struct.unpack_from("<I", data, eocd_offset + 16)[0]


def signing_block_pairs(data: bytes) -> tuple[dict[int, bytes], list[int]]:
    eocd = find_eocd(data)
    cd_offset = central_dir_offset(data, eocd)
    if cd_offset < len(APK_SIG_MAGIC) + 8 or data[cd_offset - len(APK_SIG_MAGIC) : cd_offset] != APK_SIG_MAGIC:
        return {}, []
    size2 = struct.unpack_from("<Q", data, cd_offset - len(APK_SIG_MAGIC) - 8)[0]
    block_start = cd_offset - size2 - 8
    if block_start < 0:
        raise ParseError("invalid APK signing block start")
    size1 = struct.unpack_from("<Q", data, block_start)[0]
    if size1 != size2:
        raise ParseError(f"APK signing block size mismatch head={size1} tail={size2}")
    pairs_blob = data[block_start + 8 : cd_offset - 24]
    pairs: dict[int, bytes] = {}
    ids: list[int] = []
    cursor = Cursor(pairs_blob)
    while cursor.remaining() > 0:
        if cursor.remaining() < 8:
            raise ParseError("trailing bytes before APK signing block footer")
        pair_len = struct.unpack_from("<Q", cursor.data, cursor.pos)[0]
        cursor.pos += 8
        if pair_len < 4 or pair_len - 4 > cursor.remaining():
            raise ParseError(f"invalid APK signing block pair length: {pair_len}")
        pair_id = cursor.read_u32()
        value = cursor.read_bytes(pair_len - 4)
        pairs[pair_id] = value
        ids.append(pair_id)
    return pairs, ids


def digest_rank(sig_algorithm: int) -> int:
    digest_algorithm = signature_content_digest_algorithm(sig_algorithm)
    if digest_algorithm == 2:
        return 3
    if digest_algorithm == 3:
        return 2
    if digest_algorithm == 1:
        return 1
    return 0


def signature_content_digest_algorithm(sig_algorithm: int) -> int:
    if sig_algorithm in {0x0201, 0x0301, 0x0101, 0x0103}:
        return 1
    if sig_algorithm in {0x0202, 0x0102, 0x0104}:
        return 2
    if sig_algorithm in {0x0421, 0x0423, 0x0425}:
        return 3
    raise ParseError(f"unsupported signature algorithm 0x{sig_algorithm:08x}")


def signature_algorithm_name(sig_algorithm: int) -> str:
    return {
        0x0101: "SHA256withRSA/PSS",
        0x0102: "SHA512withRSA/PSS",
        0x0103: "SHA256withRSA",
        0x0104: "SHA512withRSA",
        0x0201: "SHA256withECDSA",
        0x0202: "SHA512withECDSA",
        0x0301: "SHA256withDSA",
        0x0421: "SHA256withRSA-verity",
        0x0423: "SHA256withECDSA-verity",
        0x0425: "SHA256withDSA-verity",
    }.get(sig_algorithm, f"unknown-0x{sig_algorithm:08x}")


def verify_signed_data(public_key_bytes: bytes, sig_algorithm: int, signature: bytes, signed_data: bytes) -> bool:
    public_key = serialization.load_der_public_key(public_key_bytes)
    hash_alg = hashes.SHA512() if sig_algorithm in {0x0102, 0x0104, 0x0202} else hashes.SHA256()
    try:
        if isinstance(public_key, rsa.RSAPublicKey):
            if sig_algorithm in {0x0101, 0x0102}:
                salt_len = 64 if sig_algorithm == 0x0102 else 32
                public_key.verify(signature, signed_data, padding.PSS(mgf=padding.MGF1(hash_alg), salt_length=salt_len), hash_alg)
            else:
                public_key.verify(signature, signed_data, padding.PKCS1v15(), hash_alg)
        elif isinstance(public_key, ec.EllipticCurvePublicKey):
            public_key.verify(signature, signed_data, ec.ECDSA(hash_alg))
        elif isinstance(public_key, dsa.DSAPublicKey):
            public_key.verify(signature, signed_data, hash_alg)
        else:
            raise ParseError(f"unsupported public key type: {type(public_key).__name__}")
    except InvalidSignature:
        return False
    return True


def parse_signature_records(cursor: Cursor) -> tuple[int, bytes, list[int]]:
    best_algorithm = -1
    best_signature = b""
    algorithms: list[int] = []
    while cursor.remaining() > 0:
        record = cursor.read_lp_cursor()
        if record.remaining() < 8:
            raise ParseError("signature record too short")
        algorithm = record.read_u32()
        algorithms.append(algorithm)
        signature = record.read_lp_bytes()
        if best_algorithm == -1 or digest_rank(algorithm) > digest_rank(best_algorithm):
            best_algorithm = algorithm
            best_signature = signature
    if best_algorithm == -1:
        raise ParseError("no supported signatures found")
    return best_algorithm, best_signature, algorithms


def parse_digests(cursor: Cursor) -> list[int]:
    algorithms: list[int] = []
    while cursor.remaining() > 0:
        record = cursor.read_lp_cursor()
        if record.remaining() < 8:
            raise ParseError("digest record too short")
        algorithm = record.read_u32()
        record.read_lp_bytes()
        algorithms.append(algorithm)
    return algorithms


def parse_certs(cursor: Cursor) -> list[bytes]:
    certs: list[bytes] = []
    while cursor.remaining() > 0:
        certs.append(cursor.read_lp_bytes())
    if not certs:
        raise ParseError("no certificates listed")
    return certs


def cert_subject(cert_der: bytes) -> str:
    cert = x509.load_der_x509_certificate(cert_der)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return cert.subject.rfc4514_string()


def cert_public_key_sha256(cert_der: bytes) -> str:
    cert = x509.load_der_x509_certificate(cert_der)
    public_key = cert.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return sha256_bytes(public_key)


def cert_public_key_matches(cert_der: bytes, public_key_bytes: bytes) -> bool:
    cert = x509.load_der_x509_certificate(cert_der)
    cert_public_key = cert.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return cert_public_key == public_key_bytes


def parse_v2(value: bytes) -> SchemeSigner:
    signers = Cursor(value).read_lp_cursor()
    selected: SchemeSigner | None = None
    signer_count = 0
    while signers.remaining() > 0:
        signer_count += 1
        signer = signers.read_lp_cursor()
        signed_data = signer.read_lp_bytes()
        signatures = signer.read_lp_cursor()
        public_key_bytes = signer.read_lp_bytes()
        best_algorithm, best_signature, signature_algorithms = parse_signature_records(signatures)
        signer_signature_verified = verify_signed_data(public_key_bytes, best_algorithm, best_signature, signed_data)
        signed = Cursor(signed_data)
        digest_algorithms = parse_digests(signed.read_lp_cursor())
        certs = parse_certs(signed.read_lp_cursor())
        cert_der = certs[0]
        key_matches = cert_public_key_matches(cert_der, public_key_bytes)
        selected = SchemeSigner(
            scheme="v2",
            status="PASS" if signer_signature_verified and key_matches else "FAIL",
            signer_count=signer_count,
            selected_algorithm=signature_algorithm_name(best_algorithm),
            min_sdk=None,
            max_sdk=None,
            platform_supported=None,
            certificate_sha256=sha256_bytes(cert_der),
            certificate_subject=cert_subject(cert_der),
            public_key_sha256=sha256_bytes(public_key_bytes),
            signer_signature_verified=signer_signature_verified,
            certificate_public_key_matches=key_matches,
            notes=(
                f"signature_algorithms={','.join(signature_algorithm_name(item) for item in signature_algorithms)}; "
                f"digest_algorithms={','.join(hex(item) for item in digest_algorithms)}; content_digest_not_verified=true"
            ),
        )
    if selected is None:
        raise ParseError("no v2 signers found")
    return selected


def parse_v3(value: bytes) -> SchemeSigner:
    signers = Cursor(value).read_lp_cursor()
    selected: SchemeSigner | None = None
    signer_count = 0
    skipped = 0
    while signers.remaining() > 0:
        signer = signers.read_lp_cursor()
        signed_data = signer.read_lp_bytes()
        min_sdk = signer.read_i32()
        max_sdk = signer.read_i32()
        platform_supported = min_sdk <= R2_ANDROID_SDK <= max_sdk
        if not platform_supported:
            skipped += 1
            continue
        signer_count += 1
        signatures = signer.read_lp_cursor()
        public_key_bytes = signer.read_lp_bytes()
        best_algorithm, best_signature, signature_algorithms = parse_signature_records(signatures)
        signer_signature_verified = verify_signed_data(public_key_bytes, best_algorithm, best_signature, signed_data)
        signed = Cursor(signed_data)
        digest_algorithms = parse_digests(signed.read_lp_cursor())
        certs = parse_certs(signed.read_lp_cursor())
        cert_der = certs[0]
        signed_min_sdk = signed.read_i32()
        signed_max_sdk = signed.read_i32()
        sdk_values_match = signed_min_sdk == min_sdk and signed_max_sdk == max_sdk
        key_matches = cert_public_key_matches(cert_der, public_key_bytes)
        selected = SchemeSigner(
            scheme="v3",
            status="PASS" if signer_signature_verified and key_matches and sdk_values_match else "FAIL",
            signer_count=signer_count,
            selected_algorithm=signature_algorithm_name(best_algorithm),
            min_sdk=min_sdk,
            max_sdk=max_sdk,
            platform_supported=platform_supported,
            certificate_sha256=sha256_bytes(cert_der),
            certificate_subject=cert_subject(cert_der),
            public_key_sha256=sha256_bytes(public_key_bytes),
            signer_signature_verified=signer_signature_verified,
            certificate_public_key_matches=key_matches,
            notes=(
                f"signature_algorithms={','.join(signature_algorithm_name(item) for item in signature_algorithms)}; "
                f"digest_algorithms={','.join(hex(item) for item in digest_algorithms)}; "
                f"signed_sdk_values_match={str(sdk_values_match).lower()}; skipped_unsupported={skipped}; "
                "content_digest_not_verified=true"
            ),
        )
    if selected is None:
        raise ParseError("no v3 signers supported on Android SDK 30")
    return selected


def parse_scheme(value_by_id: dict[int, bytes], scheme: str) -> SchemeSigner:
    if scheme == "v3":
        if V3_ID not in value_by_id:
            raise ParseError("v3 block missing")
        return parse_v3(value_by_id[V3_ID])
    if scheme == "v2":
        if V2_ID not in value_by_id:
            raise ParseError("v2 block missing")
        return parse_v2(value_by_id[V2_ID])
    raise ValueError(scheme)


def run_apksigner(label: str, path: Path) -> tuple[str, str, str]:
    if not APKSIGNER.exists():
        return "MISSING", "", f"missing {rel(APKSIGNER)}"
    env = os.environ.copy()
    env["PATH"] = f"{OPENJDK_BIN}:{env.get('PATH', '')}"
    env["JAVA_HOME"] = str(JAVA_HOME)
    result = subprocess.run(
        [str(APKSIGNER), "verify", "--verbose", "--print-certs", str(path)],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=180,
        check=False,
    )
    body = result.stdout
    if result.stderr:
        body = body + ("\n" if body else "") + "# stderr\n" + result.stderr
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    log_path = OUT_DIR / f"{label}.apksigner.txt"
    log_path.write_text(body, encoding="utf-8")
    compact = []
    for line in body.splitlines():
        stripped = line.strip()
        if (
            stripped in {"Verifies", "DOES NOT VERIFY"}
            or stripped.startswith("ERROR:")
            or stripped.startswith("Verified using")
            or stripped.startswith("Signer #1 certificate")
            or stripped.startswith("Number of signers:")
        ):
            compact.append(stripped)
    status = "PASS_FULL_VERIFY" if result.returncode == 0 else f"FAIL_FULL_VERIFY_EXIT_{result.returncode}"
    return status, rel(log_path), "; ".join(compact[:12])


def audit_apk(apk_id: str, path: Path) -> ApkAudit:
    if not path.exists():
        return ApkAudit(
            apk_id=apk_id,
            path=rel(path),
            status="MISSING",
            sha256="",
            size_bytes=0,
            signing_block_ids="",
            apksigner_status="MISSING",
            apksigner_log="",
            apksigner_summary="apk missing",
            v2_status="MISSING",
            v2_cert_sha256="",
            v3_status="MISSING",
            v3_cert_sha256="",
            unsafe_preferred_scheme="",
            unsafe_cert_sha256="",
            unsafe_signer_signature_verified=False,
            unsafe_cert_matches_stock=False,
            package_manager_system_scan_prediction="MISSING",
            notes="apk missing",
        )

    data = path.read_bytes()
    pairs, ids = signing_block_pairs(data)
    signer_by_scheme: dict[str, SchemeSigner] = {}
    scheme_errors: dict[str, str] = {}
    for scheme in ("v3", "v2"):
        try:
            signer_by_scheme[scheme] = parse_scheme(pairs, scheme)
        except Exception as exc:  # noqa: BLE001 - report parser errors as evidence.
            scheme_errors[scheme] = str(exc)

    preferred = signer_by_scheme.get("v3") or signer_by_scheme.get("v2")
    apksigner_status, apksigner_log, apksigner_summary = run_apksigner(apk_id, path)
    unsafe_cert = preferred.certificate_sha256 if preferred else ""
    unsafe_verified = bool(preferred and preferred.signer_signature_verified and preferred.certificate_public_key_matches and preferred.status == "PASS")
    matches_stock = unsafe_cert == STOCK_CERT_SHA256
    if preferred and unsafe_verified and matches_stock:
        prediction = "ACCEPTS_STOCK_CERT_ON_SYSTEM_SCAN_OFFLINE"
    elif preferred and unsafe_verified:
        prediction = "PARSES_DIFFERENT_CERT_ON_SYSTEM_SCAN"
    elif preferred:
        prediction = "UNSAFE_SIGNER_PARSE_FAILED"
    else:
        prediction = "NO_ANDROID_V2_V3_SIGNER"
    status = "PASS_PM_CERT_CARRIER" if prediction == "ACCEPTS_STOCK_CERT_ON_SYSTEM_SCAN_OFFLINE" else "RECORDED"
    if apk_id == "sourcebuilt_webview" and prediction == "PARSES_DIFFERENT_CERT_ON_SYSTEM_SCAN":
        status = "RECORDED_DIFFERENT_CERT"
    if apk_id == "stock_carrier_webview" and apksigner_status.startswith("FAIL") and prediction == "ACCEPTS_STOCK_CERT_ON_SYSTEM_SCAN_OFFLINE":
        status = "PASS_SYSTEM_SCAN_ONLY_FULL_VERIFY_FAILS"

    v2 = signer_by_scheme.get("v2")
    v3 = signer_by_scheme.get("v3")
    return ApkAudit(
        apk_id=apk_id,
        path=rel(path),
        status=status,
        sha256=sha256_file(path),
        size_bytes=path.stat().st_size,
        signing_block_ids=",".join(f"0x{item:08x}" for item in ids),
        apksigner_status=apksigner_status,
        apksigner_log=apksigner_log,
        apksigner_summary=apksigner_summary,
        v2_status=v2.status if v2 else f"MISSING_OR_FAIL: {scheme_errors.get('v2', '')}",
        v2_cert_sha256=v2.certificate_sha256 if v2 else "",
        v3_status=v3.status if v3 else f"MISSING_OR_FAIL: {scheme_errors.get('v3', '')}",
        v3_cert_sha256=v3.certificate_sha256 if v3 else "",
        unsafe_preferred_scheme=preferred.scheme if preferred else "",
        unsafe_cert_sha256=unsafe_cert,
        unsafe_signer_signature_verified=unsafe_verified,
        unsafe_cert_matches_stock=matches_stock,
        package_manager_system_scan_prediction=prediction,
        notes=preferred.notes if preferred else "; ".join(f"{k}: {v}" for k, v in scheme_errors.items()),
    )


def collect_source_findings() -> list[SourceFinding]:
    rows: list[SourceFinding] = []

    line = find_line(PACKAGE_PARTITIONS, "Environment.getProductDirectory()")
    rows.append(
        SourceFinding(
            "PM-SRC-01",
            "PASS",
            source_ref(PACKAGE_PARTITIONS, line),
            line,
            "/product is included in PackagePartitions.SYSTEM_PARTITIONS with partition type PRODUCT.",
            "/product/app/webview participates in the system-partition scan list.",
        )
    )

    line = find_line(PMS, "arrayList3.addAll(SYSTEM_PARTITIONS)")
    rows.append(
        SourceFinding(
            "PM-SRC-02",
            "PASS",
            source_ref(PMS, line),
            line,
            "PackageManagerService adds PackagePartitions.SYSTEM_PARTITIONS to mDirsToScanAsSystem.",
            "The boot scan treats product/system_ext/vendor/system roots as system partitions.",
        )
    )

    line = find_line(PMS, "int i17 = this.mDefParseFlags | 16")
    rows.append(
        SourceFinding(
            "PM-SRC-03",
            "PASS",
            source_ref(PMS, line),
            line,
            "The system scan parse flags include PARSE_IS_SYSTEM_DIR (16).",
            "Packages below /product/app are parsed with parseFlags & 16 set.",
        )
    )

    line = find_line(PMS, "boolean scanSystemPartition = (parseFlags & 16) != 0")
    rows.append(
        SourceFinding(
            "PM-SRC-04",
            "PASS",
            source_ref(PMS, line),
            line,
            "addForInitLI derives scanSystemPartition from parseFlags & 16.",
            "Certificate collection can enter the system-partition skipVerify path.",
        )
    )

    line = find_line(PMS, "collectCertificatesLI(pkgSetting, parsedPackage, forceCollect, skipVerify)")
    rows.append(
        SourceFinding(
            "PM-SRC-05",
            "PASS",
            source_ref(PMS, line),
            line,
            "scanSystemPartition causes skipVerify=true for certificate collection.",
            "System scan can collect signer certs without full APK payload digest verification.",
        )
    )

    line = find_line(PARSING_UTILS, "verified = ApkSignatureVerifier.unsafeGetCertsWithoutVerification(baseCodePath, 1)")
    rows.append(
        SourceFinding(
            "PM-SRC-06",
            "PASS",
            source_ref(PARSING_UTILS, line),
            line,
            "ParsingPackageUtils calls unsafeGetCertsWithoutVerification when skipVerify is true.",
            "A readable v2/v3 signing block can supply signingDetails for system packages.",
        )
    )

    line = find_line(APK_VERIFIER, "ApkSignatureSchemeV3Verifier.unsafeGetCertsWithoutVerification(apkPath)")
    rows.append(
        SourceFinding(
            "PM-SRC-07",
            "PASS",
            source_ref(APK_VERIFIER, line),
            line,
            "ApkSignatureVerifier uses unsafe v3 cert collection when verifyFull=false.",
            "If a v3 block is present and internally valid, it is preferred before v2.",
        )
    )

    line = find_line(APK_V3, "if (doVerifyIntegrity)")
    rows.append(
        SourceFinding(
            "PM-SRC-08",
            "PASS",
            source_ref(APK_V3, line),
            line,
            "ApkSignatureSchemeV3Verifier verifies APK content digests only when doVerifyIntegrity is true.",
            "The stock-carrier full digest mismatch is skipped by the system cert-only path.",
        )
    )

    line = find_line(PMS, "if ((parseFlags & 16) == 0 && pkg.getSigningDetails().signatureSchemeVersion")
    rows.append(
        SourceFinding(
            "PM-SRC-09",
            "PASS",
            source_ref(PMS, line),
            line,
            "The minimum signature-scheme enforcement is skipped for parseFlags & 16 system scans.",
            "A targetSdk 30+ system package can rely on the system scan signingDetails route.",
        )
    )

    line = find_line(PMS_UTILS, "public static boolean verifySignatures")
    rows.append(
        SourceFinding(
            "PM-SRC-10",
            "CAUTION",
            source_ref(PMS_UTILS, line),
            line,
            "PackageManagerServiceUtils still compares parsed signingDetails with existing package/shared-user state.",
            "The carrier must expose the stock WebView cert; different signer material remains unsafe for same-package replacement.",
        )
    )

    line = find_line(PACKAGE_CACHER, "return packageFile.getName() + '-' + flags")
    rows.append(
        SourceFinding(
            "PM-SRC-11",
            "CAUTION",
            source_ref(PACKAGE_CACHER, line),
            line,
            "PackageCacher keys cache entries by packageFile name and flags.",
            "The WebView package directory mtime must be bumped so stale package_cache does not hide the new APK parse.",
        )
    )

    return rows


def md_table(headers: list[str], rows: Iterable[Iterable[object]]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|").replace("\n", " ") for cell in row) + " |")
    return lines


def final_verdict(apks: list[ApkAudit], sources: list[SourceFinding]) -> str:
    source_ok = all(row.status in {"PASS", "CAUTION"} for row in sources)
    stock = next((row for row in apks if row.apk_id == "stock_webview"), None)
    carrier = next((row for row in apks if row.apk_id == "stock_carrier_webview"), None)
    if (
        source_ok
        and stock
        and carrier
        and stock.unsafe_cert_matches_stock
        and carrier.unsafe_cert_matches_stock
        and carrier.unsafe_signer_signature_verified
        and carrier.apksigner_status.startswith("FAIL_FULL_VERIFY")
    ):
        return "OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE"
    return "BLOCKED_A_SIG_01"


def write_tsv(path: Path, sources: list[SourceFinding], apks: list[ApkAudit], verdict: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, delimiter="\t", lineterminator="\n")
        writer.writerow(["section", "id", "status", "evidence", "impact_or_prediction", "notes"])
        writer.writerow(["decision", "verdict", verdict, rel(OUT_JSON), "donor-backed image still needs explicit image/live gates", ""])
        for row in sources:
            writer.writerow(["source", row.finding_id, row.status, row.source, row.impact, row.evidence])
        for row in apks:
            writer.writerow(
                [
                    "apk",
                    row.apk_id,
                    row.status,
                    f"{row.path}; sha256={row.sha256}; apksigner={row.apksigner_status}; log={row.apksigner_log}",
                    row.package_manager_system_scan_prediction,
                    f"unsafe={row.unsafe_preferred_scheme}:{row.unsafe_cert_sha256}; full={row.apksigner_summary}",
                ]
            )


def write_markdown(path: Path, sources: list[SourceFinding], apks: list[ApkAudit], verdict: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    lines.append("# WebView A-SIG PackageManager Audit")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This is a read-only offline audit for the Route A WebView")
    lines.append("same-package signing transition. It does not touch a device, flash,")
    lines.append("reboot, erase partitions, build images, write settings, or modify `/data`.")
    lines.append("")
    lines.append("## Decision")
    lines.append("")
    if verdict == "OFFLINE_SYSTEM_SCAN_CERT_ACCEPTS_STOCK_CARRIER_PENDING_LIVE":
        lines.append("A-SIG now has offline PackageManager evidence for the stock-carrier")
        lines.append("route: `/product/app/webview` is scanned as a system partition, the")
        lines.append("system path uses `unsafeGetCertsWithoutVerification()`, and the")
        lines.append("current `SystemWebView-stock-carrier.apk` exposes the stock Smartisan")
        lines.append("WebView certificate through an Android-style v3 cert-only parse.")
        lines.append("")
        lines.append("This does **not** mean the APK is cryptographically re-signed or safe to")
        lines.append("install as a user APK. `apksigner` full verification correctly fails on")
        lines.append("the stock-carrier candidate because the stock v3 content digest no longer")
        lines.append("matches the modern payload.")
        lines.append("")
        lines.append("Practical status: A-SIG is good enough for offline ROM design review, but")
        lines.append("a donor-backed image still needs explicit image acceptance and a live")
        lines.append("PackageManager/WebViewUpdateService regression test before it can be")
        lines.append("called accepted.")
    else:
        lines.append("A-SIG remains blocked. See the source and APK rows below for the failing")
        lines.append("piece before any donor-backed image work.")
    lines.append("")
    lines.append("## Source Findings")
    lines.append("")
    lines.extend(
        md_table(
            ["Finding", "Status", "Source", "Evidence", "Impact"],
            [[row.finding_id, row.status, row.source, row.evidence, row.impact] for row in sources],
        )
    )
    lines.append("")
    lines.append("## APK Evidence")
    lines.append("")
    lines.extend(
        md_table(
            [
                "APK",
                "Status",
                "SHA256",
                "apksigner",
                "v2 cert",
                "v3 cert",
                "unsafe preferred",
                "PM prediction",
            ],
            [
                [
                    row.apk_id,
                    row.status,
                    row.sha256,
                    row.apksigner_status,
                    row.v2_cert_sha256,
                    row.v3_cert_sha256,
                    f"{row.unsafe_preferred_scheme}:{row.unsafe_cert_sha256}",
                    row.package_manager_system_scan_prediction,
                ]
                for row in apks
            ],
        )
    )
    lines.append("")
    lines.append("## Full Verification Logs")
    lines.append("")
    for row in apks:
        lines.append(f"- `{row.apk_id}`: `{row.apksigner_log}`")
    lines.append("")
    lines.append("## Boundary")
    lines.append("")
    lines.append("- The stock-carrier APK is a system-partition certificate carrier, not a valid user-install APK.")
    lines.append("- The first donor-backed ROM image must bump `/product/app/webview` directory mtime and remove stale oat/vdex artifacts.")
    lines.append("- The live gate must verify boot, PackageManager path/hash/signatures, WebViewUpdateService provider status, relro, Settings selector, keyguard, launcher, and PackageManager/WebView logs.")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append(f"- Markdown report: `{rel(OUT_MD)}`")
    lines.append(f"- TSV manifest: `{rel(OUT_TSV)}`")
    lines.append(f"- JSON snapshot: `{rel(OUT_JSON)}`")
    lines.append(f"- Related signing transition plan: `{rel(SIGNING_PLAN_MD)}`")
    lines.append(f"- Related system signature boundary: `{rel(SYSTEM_SIGNATURE_MD)}`")
    lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sources = collect_source_findings()
    apks = [
        audit_apk("stock_webview", STOCK_WEBVIEW_APK),
        audit_apk("sourcebuilt_webview", SOURCEBUILT_APK),
        audit_apk("stock_carrier_webview", STOCK_CARRIER_APK),
    ]
    verdict = final_verdict(apks, sources)
    write_tsv(OUT_TSV, sources, apks, verdict)
    write_markdown(OUT_MD, sources, apks, verdict)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "verdict": verdict,
                "a_sig_01_status": "OFFLINE_PM_ACCEPTANCE_RECORDED" if verdict.startswith("OFFLINE_SYSTEM_SCAN") else "BLOCKED",
                "donor_backed_image_allowed": False,
                "rom_design_review_allowed": verdict.startswith("OFFLINE_SYSTEM_SCAN"),
                "live_proof_required": True,
                "stock_cert_sha256": STOCK_CERT_SHA256,
                "sources": [asdict(row) for row in sources],
                "apks": [asdict(row) for row in apks],
                "outputs": {
                    "markdown": rel(OUT_MD),
                    "tsv": rel(OUT_TSV),
                    "json": rel(OUT_JSON),
                    "apksigner_logs": {row.apk_id: row.apksigner_log for row in apks},
                },
            },
            ensure_ascii=True,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"verdict={verdict}")
    print(f"a_sig_01_status={'OFFLINE_PM_ACCEPTANCE_RECORDED' if verdict.startswith('OFFLINE_SYSTEM_SCAN') else 'BLOCKED'}")
    print("donor_backed_image_allowed=false")
    print(f"markdown={rel(OUT_MD)}")
    print(f"tsv={rel(OUT_TSV)}")
    print(f"json={rel(OUT_JSON)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
