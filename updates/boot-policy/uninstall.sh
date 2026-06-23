#!/system/bin/sh
set -eu

: "${SMARTISAX_ROOT:?missing SMARTISAX_ROOT}"
: "${SMARTISAX_PACKAGE_ID:?missing SMARTISAX_PACKAGE_ID}"

apm_id="smartisax_boot_policy"
apm_dir="/data/adb/modules/$apm_id"
module_dir="$SMARTISAX_ROOT/modules/$SMARTISAX_PACKAGE_ID"
runtime_marker="$SMARTISAX_STATE_DIR/runtime-installed-by-boot-policy.txt"
runtime_installed="$(cat "$runtime_marker" 2>/dev/null || echo 0)"

rm -rf "$apm_dir"
rm -f "$SMARTISAX_ROOT/bin/boot-policy-runner.sh"
rm -f "$SMARTISAX_ROOT/policy.d/20-modern-browser-default.sh"
rm -rf "$module_dir"

if [ "$runtime_installed" = "1" ]; then
  rm -f /data/adb/apd
  rm -rf /data/adb/ap
fi

echo "boot-policy uninstalled"
