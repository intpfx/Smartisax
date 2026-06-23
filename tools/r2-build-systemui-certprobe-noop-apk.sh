#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

STOCK_SYSTEMUI_APK="${RAW}/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
OUT_DIR="${ROOT_DIR}/hard-rom/build/apk"
OUT_APK="${OUT_DIR}/SmartisanSystemUI-certprobe-noop.apk"
SIG_REPORT="${OUT_DIR}/SmartisanSystemUI-certprobe-noop.signature.txt"
MANIFEST="${OUT_DIR}/SmartisanSystemUI-certprobe-noop.SHA256SUMS.txt"
MAGIC="APK Sig Block 42"
SMARTISAN_CERT_SHA256="99:CB:9A:0E:CE:39:C4:30:1E:22:15:0E:5D:72:38:EE:9B:40:73:04:20:54:C6:0B:AA:FD:68:F3:A7:C5:75:74"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-build-systemui-certprobe-noop-apk.sh

Build an offline SmartisanSystemUI.apk no-op certificate probe for a zero-free-
block system_ext image. The output keeps the exact stock APK size and changes
one byte in the APK Signature Scheme v2 block magic:

  APK Sig Block 42 -> XPK Sig Block 42

That disables the v2 block while leaving all ZIP/JAR entries byte-identical.
keytool and jarsigner still read the original Smartisan Android v1 certificate,
and runtime APK contents are unchanged.

This does not authorize flashing; a matching exact-current ROM image and
explicit user confirmation are still required before any live test.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1"
}

find_magic_offset() {
  perl -0777 -ne '
    my $magic = $ENV{MAGIC};
    my $i = index($_, $magic);
    die "magic not found\n" if $i < 0;
    my $j = index($_, $magic, $i + 1);
    die "magic appears more than once\n" if $j >= 0;
    print $i;
  ' "$1"
}

case "${1:-}" in
  "")
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

need_file "$STOCK_SYSTEMUI_APK"
need_executable "$SIGCHECK"

mkdir -p "$OUT_DIR"
rm -f "$OUT_APK" "$SIG_REPORT" "$MANIFEST"

offset="$(MAGIC="$MAGIC" find_magic_offset "$STOCK_SYSTEMUI_APK")"
cp "$STOCK_SYSTEMUI_APK" "$OUT_APK"
printf 'X' | dd of="$OUT_APK" bs=1 seek="$offset" conv=notrunc status=none

[ "$(size_bytes "$OUT_APK")" = "$(size_bytes "$STOCK_SYSTEMUI_APK")" ] \
  || die "probe APK size differs from stock"

diff_output="$(cmp -l "$STOCK_SYSTEMUI_APK" "$OUT_APK" || true)"
diff_count="$(printf '%s\n' "$diff_output" | sed '/^$/d' | wc -l | tr -d ' ')"
[ "$diff_count" = "1" ] || die "expected exactly one changed byte, got ${diff_count}"
diff_offset_1based="$(printf '%s\n' "$diff_output" | awk 'NR == 1 {print $1}')"
[ "$diff_offset_1based" = "$((offset + 1))" ] \
  || die "unexpected changed byte offset: ${diff_offset_1based}"

unzip -t "$OUT_APK" >/dev/null
"$SIGCHECK" "$OUT_APK" > "$SIG_REPORT"

grep -q "$SMARTISAN_CERT_SHA256" "$SIG_REPORT" \
  || die "probe APK does not expose the expected Smartisan Android certificate"
grep -q '^keytool_status=0$' "$SIG_REPORT" \
  || die "probe APK did not pass keytool cert read"
grep -q '^jarsigner_status=0$' "$SIG_REPORT" \
  || die "probe APK did not pass compact jarsigner status check"
grep -q '^apk_sig_block_magic=absent$' "$SIG_REPORT" \
  || die "probe APK still reports APK Sig Block magic as present"

{
  echo "variant=SmartisanSystemUI-certprobe-noop-apk"
  echo "purpose=SmartisanSystemUI same-size original-cert-readable no-op probe"
  echo "stock_apk=${STOCK_SYSTEMUI_APK}"
  echo "probe_apk=${OUT_APK}"
  echo "signature_report=${SIG_REPORT}"
  echo "mutation=apk_sig_block_magic_first_byte"
  echo "mutation_offset=${offset}"
  echo "mutation_from=A"
  echo "mutation_to=X"
  echo "changed_bytes=${diff_count}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  shasum -a 256 "$OUT_APK" "$STOCK_SYSTEMUI_APK"
} > "$MANIFEST"

echo "Built: ${OUT_APK}"
echo "Signature report: ${SIG_REPORT}"
echo "Manifest: ${MANIFEST}"
