#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYTOOL="${KEYTOOL:-/opt/homebrew/opt/openjdk/bin/keytool}"
JARSIGNER="${JARSIGNER:-/opt/homebrew/opt/openjdk/bin/jarsigner}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-apk-signature-boundary-check.sh <apk>

Print a compact, read-only signature boundary summary for a ROM APK.

This does not prove that a modified APK is safe to flash. It answers narrower
questions that matter for Smartisan OS system-partition experiments:

  - what certificate Java/JAR tooling can still read
  - whether an APK Signature Scheme v2/v3 signing block magic is still present
  - whether jarsigner sees obvious v1/JAR verification warnings

For system-partition packages, Android's boot scan may use certs-only parsing;
do not extrapolate this output to user-installed APK behavior.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

apk="${1:-}"
if [ -z "$apk" ] || [ "$apk" = "-h" ] || [ "$apk" = "--help" ]; then
  usage
  exit 0
fi

[ -f "$apk" ] || die "missing apk: $apk"
[ -x "$KEYTOOL" ] || die "missing keytool: $KEYTOOL"
[ -x "$JARSIGNER" ] || die "missing jarsigner: $JARSIGNER"

abs_apk="$(cd "$(dirname "$apk")" && pwd)/$(basename "$apk")"

printf 'apk=%s\n' "$abs_apk"
printf 'sha256=%s\n' "$(shasum -a 256 "$abs_apk" | awk '{print $1}')"
printf 'size_bytes=%s\n' "$(wc -c < "$abs_apk" | tr -d ' ')"

python3 - "$abs_apk" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
magic = b"APK Sig Block 42"
offset = data.find(magic)
print(f"apk_sig_block_magic={'present' if offset >= 0 else 'absent'}")
print(f"apk_sig_block_magic_offset={offset}")
PY

printf 'cert_from_keytool:\n'
keytool_tmp="$(mktemp "/tmp/r2-keytool-summary.XXXXXX")"
trap 'rm -f "$keytool_tmp"' EXIT
set +e
"$KEYTOOL" -printcert -jarfile "$abs_apk" >"$keytool_tmp" 2>&1
keytool_status=$?
set -e
printf 'keytool_status=%s\n' "$keytool_status"
awk '
  /^Owner:/ || /^Issuer:/ || /SHA256:/ || /^Signature algorithm name:/ {
    print "  " $0
    printed = 1
  }
  END {
    if (!printed) {
      print "  (no certificate lines matched)"
    }
  }
' "$keytool_tmp"

printf 'keytool_summary:\n'
awk '
  BEGIN { printed = 0 }
  /^keytool error:/ || /java.lang.SecurityException/ || /invalid/ || /digest/ || /signature/ {
    if (printed < 8) {
      print "  " $0
      printed++
    }
  }
  END {
    if (printed == 0) {
      print "  (no compact warning lines matched)"
    }
  }
' "$keytool_tmp"

printf 'jarsigner_status='
tmp="$(mktemp "/tmp/r2-jarsigner-summary.XXXXXX")"
trap 'rm -f "$keytool_tmp" "$tmp"' EXIT
set +e
"$JARSIGNER" -verify "$abs_apk" >"$tmp" 2>&1
status=$?
set -e

printf '%s\n' "$status"
printf 'jarsigner_summary:\n'
awk '
  BEGIN { printed = 0 }
  /^jar verified\./ || /^jarsigner:/ || /unsigned entries/ || /Invalid signature/ || /no manifest/ || /Entry .* has unsigned/ || /digest/ {
    if (printed < 12) {
      print "  " $0
      printed++
    }
  }
  END {
    if (printed == 0) {
      print "  (no compact warning lines matched)"
    }
  }
' "$tmp"
