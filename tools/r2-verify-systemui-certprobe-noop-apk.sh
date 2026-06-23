#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"

STOCK_APK="${RAW}/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk"
PROBE_APK="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk"
SIG_REPORT="${ROOT_DIR}/hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.signature.txt"
INSPECT_DIR="${ROOT_DIR}/hard-rom/inspect/systemui-certprobe-noop"
MAGIC="APK Sig Block 42"
SMARTISAN_CERT_SHA256="99:CB:9A:0E:CE:39:C4:30:1E:22:15:0E:5D:72:38:EE:9B:40:73:04:20:54:C6:0B:AA:FD:68:F3:A7:C5:75:74"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-verify-systemui-certprobe-noop-apk.sh

Read-only offline verifier for SmartisanSystemUI-certprobe-noop.apk. It checks
that all ZIP/JAR entries remain byte-identical to stock, the APK size is
unchanged, and the only file-level byte change is the first byte of the APK v2
signing block magic.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
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

need_file "$STOCK_APK"
need_file "$PROBE_APK"
need_file "$SIG_REPORT"

mkdir -p "$INSPECT_DIR"
tmp="$(mktemp -d "/tmp/r2-systemui-noop-verify.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

stock_list="${tmp}/stock.list"
probe_list="${tmp}/probe.list"
stock_dir="${tmp}/stock"
probe_dir="${tmp}/probe"

[ "$(size_bytes "$STOCK_APK")" = "$(size_bytes "$PROBE_APK")" ] \
  || die "probe APK size differs from stock"

stock_magic_offset="$(MAGIC="$MAGIC" find_magic_offset "$STOCK_APK")"
if MAGIC="$MAGIC" find_magic_offset "$PROBE_APK" >/dev/null 2>&1; then
  die "probe APK still contains intact APK Sig Block magic"
fi

diff_output="$(cmp -l "$STOCK_APK" "$PROBE_APK" || true)"
diff_count="$(printf '%s\n' "$diff_output" | sed '/^$/d' | wc -l | tr -d ' ')"
[ "$diff_count" = "1" ] || die "expected exactly one changed byte, got ${diff_count}"
diff_line="$(printf '%s\n' "$diff_output" | awk 'NR == 1 {print $1, $2, $3}')"
diff_offset_1based="$(awk '{print $1}' <<<"$diff_line")"
diff_from_octal="$(awk '{print $2}' <<<"$diff_line")"
diff_to_octal="$(awk '{print $3}' <<<"$diff_line")"
[ "$diff_offset_1based" = "$((stock_magic_offset + 1))" ] \
  || die "unexpected changed byte offset: ${diff_offset_1based}"
[ "$diff_from_octal" = "101" ] || die "unexpected source byte octal: ${diff_from_octal}"
[ "$diff_to_octal" = "130" ] || die "unexpected probe byte octal: ${diff_to_octal}"

mkdir -p "$stock_dir" "$probe_dir"
unzip -q "$STOCK_APK" -d "$stock_dir"
unzip -q "$PROBE_APK" -d "$probe_dir"

(
  cd "$stock_dir"
  find . -type f -print | sed 's#^\./##' | LC_ALL=C sort
) > "$stock_list"
(
  cd "$probe_dir"
  find . -type f -print | sed 's#^\./##' | LC_ALL=C sort
) > "$probe_list"
cmp -s "$stock_list" "$probe_list" || die "ZIP entry list differs from stock"

while IFS= read -r member; do
  cmp -s "${stock_dir}/${member}" "${probe_dir}/${member}" \
    || die "ZIP member changed: ${member}"
done < "$stock_list"

grep -q "$SMARTISAN_CERT_SHA256" "$SIG_REPORT" \
  || die "signature report missing Smartisan Android certificate"
grep -q '^keytool_status=0$' "$SIG_REPORT" \
  || die "signature report does not show keytool_status=0"
grep -q '^jarsigner_status=0$' "$SIG_REPORT" \
  || die "signature report does not show jarsigner_status=0"
grep -q '^apk_sig_block_magic=absent$' "$SIG_REPORT" \
  || die "signature report does not show absent APK Sig Block magic"

timestamp="$(date +%Y%m%d-%H%M%S)"
report="${INSPECT_DIR}/verify-systemui-certprobe-noop-apk-${timestamp}.txt"

{
  echo "# SmartisanSystemUI cert-probe no-op APK offline verification"
  echo "timestamp=${timestamp}"
  echo
  echo "## sha256"
  shasum -a 256 "$PROBE_APK" "$STOCK_APK"
  echo
  echo "## byte scope"
  echo "same_size=1"
  echo "changed_bytes=${diff_count}"
  echo "changed_offset=${stock_magic_offset}"
  echo "changed_from=A"
  echo "changed_to=X"
  echo
  echo "## zip-entry scope"
  echo "entry_list_identical=1"
  echo "entries_verified=$(wc -l < "$stock_list" | tr -d ' ')"
  echo
  echo "## signature boundary"
  sed -n '1,28p' "$SIG_REPORT"
  echo
  echo "PASS"
} | tee "$report"

echo "Report: ${report}"
