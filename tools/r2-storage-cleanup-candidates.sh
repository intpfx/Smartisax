#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

size_of() {
  du -sh "$@" 2>/dev/null | sort -hr || true
}

find_glob() {
  local dir="$1"
  local pattern="$2"
  find "$dir" -type f -name "$pattern" -print 2>/dev/null | sort || true
}

echo "# R2 storage cleanup candidates"
echo
echo "This report is read-only. It does not delete, move, or modify files."
echo

echo "## filesystem"
df -h "$ROOT_DIR"
echo

echo "## largest project directories"
size_of \
  "$ROOT_DIR/hard-rom/build" \
  "$ROOT_DIR/hard-rom/inspect" \
  "$ROOT_DIR/hard-rom/work" \
  "$ROOT_DIR/reverse/smartisan-8.5.3-rom-static" \
  "$ROOT_DIR/stock-ota" \
  "$ROOT_DIR/backups"
echo

echo "## safe cleanup candidate: obsolete raw super slices"
old_slices="$(find_glob "$ROOT_DIR/hard-rom/inspect/settingssmartisan-offline" '*-system_b-from-super.img')"
if [ -n "$old_slices" ]; then
  printf '%s\n' "$old_slices" | xargs du -sh | sort -hr
  cat <<'EOF'

Reason:
  These were created by the old SettingsSmartisan offline verifier. The current
  verifier uses tools/r2-sparse-partition-patch.py logical-slice hashing and no
  longer needs multi-gigabyte raw system_b slice dumps.

Suggested action after explicit confirmation:
  rm hard-rom/inspect/settingssmartisan-offline/offline-*/v0.*-system_b-from-super.img
EOF
else
  echo "none found"
fi
echo

echo "## large sparse images kept for current gates"
size_of "$ROOT_DIR"/hard-rom/build/super-otatrust-*.sparse.img
cat <<'EOF'

Policy:
  Keep v0.4 locally as fast rollback.
  Keep the next live gate candidate locally before a flash.
  Archive or delete older unflashed sparse candidates only after deciding they
  are rebuildable and no longer part of the active gate sequence.
EOF
echo

echo "## generated partition images used by offline verifiers"
size_of \
  "$ROOT_DIR"/hard-rom/build/system-otatrust-v0.*.img \
  "$ROOT_DIR"/hard-rom/build/product-otatrust-v0.*.img \
  "$ROOT_DIR"/hard-rom/build/system_ext-otatrust-*.img
cat <<'EOF'

Policy:
  These are not directly flashed, but current offline verifiers compare sparse
  logical partition slices against them. Delete only after the corresponding
  sparse candidate is retired or after updating the verifier to reconstruct the
  expected image another way.
EOF
