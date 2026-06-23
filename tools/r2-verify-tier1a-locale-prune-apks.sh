#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${ROOT_DIR}/tools/r2-verify-apk-locale-policy.py"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/tier1a-locale-prune-apks"

need_file() {
  [ -f "$1" ] || {
    echo "error: missing file: $1" >&2
    exit 1
  }
}

entry_exists() {
  local apk="$1"
  local entry="$2"
  unzip -Z1 "$apk" | awk -v entry="$entry" '$0 == entry { found = 1 } END { exit found ? 0 : 1 }'
}

entry_hash() {
  local apk="$1"
  local entry="$2"
  unzip -p "$apk" "$entry" | shasum -a 256 | awk '{print $1}'
}

file_hash() {
  shasum -a 256 "$1" | awk '{print $1}'
}

assert_resources_arsc_stored() {
  local package="$1"
  local stock="$2"
  local out="$3"
  python3 - "$package" "$stock" "$out" <<'PY'
from __future__ import annotations

import sys
import zipfile

package, stock, out = sys.argv[1:4]
for label, path in [("stock", stock), ("output", out)]:
    with zipfile.ZipFile(path) as zf:
        try:
            info = zf.getinfo("resources.arsc")
        except KeyError:
            raise SystemExit(f"error: {package} {label} missing resources.arsc")
        if info.compress_type != zipfile.ZIP_STORED:
            raise SystemExit(
                f"error: {package} {label} resources.arsc is not STORED: "
                f"compress_type={info.compress_type}"
            )
PY
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [ "$actual" = "$expected" ] || {
    echo "error: ${label}: expected ${expected}, got ${actual}" >&2
    exit 1
  }
}

verify_apk() {
  local package="$1"
  local stock_rel="$2"
  local out_rel="$3"
  local expected_sha="$4"
  local signature_rel="$5"
  local stock="${ROOT_DIR}/${stock_rel}"
  local out="${ROOT_DIR}/${out_rel}"
  local signature="${ROOT_DIR}/${signature_rel}"
  local out_sha stock_entry out_entry policy_out

  need_file "$stock"
  need_file "$out"
  need_file "$signature"

  out_sha="$(file_hash "$out")"
  assert_eq "$out_sha" "$expected_sha" "${package} APK sha256"

  unzip -t "$out" >/dev/null

  for entry in classes.dex AndroidManifest.xml; do
    if entry_exists "$stock" "$entry"; then
      entry_exists "$out" "$entry" || {
        echo "error: ${package} output is missing ${entry}" >&2
        exit 1
      }
      stock_entry="$(entry_hash "$stock" "$entry")"
      out_entry="$(entry_hash "$out" "$entry")"
      assert_eq "$out_entry" "$stock_entry" "${package} ${entry}"
    fi
  done

  if entry_exists "$stock" resources.arsc && entry_exists "$out" resources.arsc; then
    stock_entry="$(entry_hash "$stock" resources.arsc)"
    out_entry="$(entry_hash "$out" resources.arsc)"
    [ "$stock_entry" != "$out_entry" ] || {
      echo "error: ${package} resources.arsc did not change" >&2
      exit 1
    }
    assert_resources_arsc_stored "$package" "$stock" "$out"
  else
    echo "error: ${package} resources.arsc missing in stock or output" >&2
    exit 1
  fi

  policy_out="$("${POLICY}" --keep-languages en,zh "$out")"
  grep -q "bad_locale_chunk_count=0" <<<"$policy_out" || {
    echo "error: ${package} locale policy failed" >&2
    echo "$policy_out" >&2
    exit 1
  }

  grep -q "SHA-256 digest error for resources.arsc" "$signature" || {
    echo "error: ${package} signature boundary did not show resources.arsc digest error" >&2
    exit 1
  }

  {
    echo "package=${package}"
    echo "stock=${stock_rel}"
    echo "output=${out_rel}"
    echo "sha256=${out_sha}"
    echo "zip_integrity=ok"
    echo "classes_and_manifest=unchanged"
    echo "resources_arsc=changed"
    echo "resources_arsc_zip_method=stored"
    echo "signature_boundary=resources.arsc_digest_error"
    echo "$policy_out"
    echo
  } >> "$REPORT"
}

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-tier1a-locale-prune-apks.sh

Read-only verifier for the first minimal-exposure APK-level language
hard-prune candidates. It checks that each output APK hash is expected, ZIP
integrity is valid, classes.dex and AndroidManifest.xml are unchanged,
resources.arsc changed and remains STORED, and binary locale-policy contains
only English/Chinese language chunks.
USAGE
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

need_file "$POLICY"
mkdir -p "$INSPECT_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
REPORT="${INSPECT_DIR}/verify-tier1a-locale-prune-apks-${timestamp}.txt"

{
  echo "# Tier1a locale-prune APK verification"
  echo "timestamp=${timestamp}"
  echo
} > "$REPORT"

verify_apk \
  "com.android.protips" \
  "reverse/smartisan-8.5.3-rom-static/raw/system/system/app/Protips/Protips.apk" \
  "hard-rom/build/apk/com.android.protips-locale-prune-en-zh.apk" \
  "71ed25c64babd01e07cec4263aa1ea88ddb0a1bf74c1a03e3dc45c67ae5850d5" \
  "hard-rom/build/apk/com.android.protips-locale-prune-en-zh.signature.txt"

verify_apk \
  "com.android.printservice.recommendation" \
  "reverse/smartisan-8.5.3-rom-static/raw/system/system/app/PrintRecommendationService/PrintRecommendationService.apk" \
  "hard-rom/build/apk/com.android.printservice.recommendation-locale-prune-en-zh.apk" \
  "06628867eba1a7451a0afdb866eeb18b8d1bc36b6521a894331a4b2194b5c383" \
  "hard-rom/build/apk/com.android.printservice.recommendation-locale-prune-en-zh.signature.txt"

verify_apk \
  "com.android.hotspot2.osulogin" \
  "reverse/smartisan-8.5.3-rom-static/raw/system/system/apex/com.android.wifi/app/OsuLogin/OsuLogin.apk" \
  "hard-rom/build/apk/com.android.hotspot2.osulogin-locale-prune-en-zh.apk" \
  "fa09b52598733e680abc21cd77dde6e953fdaf676f2fb835b99f5361c9476e6e" \
  "hard-rom/build/apk/com.android.hotspot2.osulogin-locale-prune-en-zh.signature.txt"

echo "result=PASS" >> "$REPORT"
echo "PASS: tier1a locale-prune APK verification"
echo "report=${REPORT}"
