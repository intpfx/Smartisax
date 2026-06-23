#!/system/bin/sh
set -eu

: "${SMARTISAX_ROOT:?missing SMARTISAX_ROOT}"
: "${SMARTISAX_PACKAGE_ID:?missing SMARTISAX_PACKAGE_ID}"

module_dir="$SMARTISAX_ROOT/modules/$SMARTISAX_PACKAGE_ID"
rm -rf "$module_dir"
echo "hello-marker removed from $module_dir"
