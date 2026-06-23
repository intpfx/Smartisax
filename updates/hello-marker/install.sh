#!/system/bin/sh
set -eu

: "${SMARTISAX_ROOT:?missing SMARTISAX_ROOT}"
: "${SMARTISAX_PACKAGE_ID:?missing SMARTISAX_PACKAGE_ID}"
: "${SMARTISAX_PACKAGE_VERSION:?missing SMARTISAX_PACKAGE_VERSION}"
: "${SMARTISAX_PACKAGE_DIR:?missing SMARTISAX_PACKAGE_DIR}"

module_dir="$SMARTISAX_ROOT/modules/$SMARTISAX_PACKAGE_ID"
mkdir -p "$SMARTISAX_ROOT" "$SMARTISAX_ROOT/modules" "$module_dir"
chmod 0700 "$SMARTISAX_ROOT" "$SMARTISAX_ROOT/modules" "$module_dir"

cat > "$module_dir/marker.txt" <<EOF
id=$SMARTISAX_PACKAGE_ID
version=$SMARTISAX_PACKAGE_VERSION
installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
device=$(getprop ro.product.manufacturer) $(getprop ro.product.model)
slot=$(getprop ro.boot.slot_suffix)
root=$(id)
EOF

if [ -f "$SMARTISAX_PACKAGE_DIR/payload/message.txt" ]; then
  cp "$SMARTISAX_PACKAGE_DIR/payload/message.txt" "$module_dir/message.txt"
fi

chmod 0644 "$module_dir"/*.txt
echo "hello-marker installed at $module_dir"
