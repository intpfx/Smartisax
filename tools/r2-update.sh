#!/usr/bin/env bash
set -euo pipefail

SERIAL="${SERIAL:-bb12d264}"
KP="${KP:-/system/bin/kp}"
ROOT_DIR="${ROOT_DIR:-/data/adb/smartisax}"
STAGE_BASE="${STAGE_BASE:-/data/local/tmp/smartisax-updates}"

usage() {
  cat <<'EOF'
Usage:
  tools/r2-update.sh validate <package-dir>
  tools/r2-update.sh pack <package-dir> [out.zip]
  tools/r2-update.sh install <package-dir>
  tools/r2-update.sh uninstall <package-id>
  tools/r2-update.sh list
  tools/r2-update.sh status

Package contract:
  manifest.json       JSON with id, version, name
  install.sh          POSIX shell, runs as root on device
  uninstall.sh        POSIX shell, runs as root on device
  payload/            Optional package files

Install-time environment:
  SMARTISAX_ROOT
  SMARTISAX_PACKAGE_ID
  SMARTISAX_PACKAGE_VERSION
  SMARTISAX_PACKAGE_DIR
  SMARTISAX_STATE_DIR
EOF
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

require_device() {
  if ! adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"; then
    echo "Device $SERIAL is not available over adb." >&2
    adb devices >&2
    exit 1
  fi
}

json_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
value = data
for part in field.split("."):
    value = value[part]
if not isinstance(value, str):
    raise SystemExit(f"{field} must be a string")
print(value)
PY
}

validate_package() {
  local pkg="$1"
  [ -d "$pkg" ] || { echo "Package dir not found: $pkg" >&2; exit 1; }
  [ -f "$pkg/manifest.json" ] || { echo "Missing manifest.json" >&2; exit 1; }
  [ -f "$pkg/install.sh" ] || { echo "Missing install.sh" >&2; exit 1; }
  [ -f "$pkg/uninstall.sh" ] || { echo "Missing uninstall.sh" >&2; exit 1; }
  python3 -m json.tool "$pkg/manifest.json" >/dev/null
  local id version name
  id="$(json_field "$pkg/manifest.json" id)"
  version="$(json_field "$pkg/manifest.json" version)"
  name="$(json_field "$pkg/manifest.json" name)"
  case "$id" in
    *[!a-z0-9._-]*|"") echo "Invalid package id: $id" >&2; exit 1 ;;
  esac
  case "$version" in
    *[!A-Za-z0-9._+-]*|"") echo "Invalid package version: $version" >&2; exit 1 ;;
  esac
  echo "ok id=$id version=$version name=$name"
}

pack_package() {
  local pkg="$1"
  local out="${2:-}"
  validate_package "$pkg" >/dev/null
  local id version
  id="$(json_field "$pkg/manifest.json" id)"
  version="$(json_field "$pkg/manifest.json" version)"
  if [ -z "$out" ]; then
    mkdir -p dist
    out="dist/${id}-${version}.zip"
  fi
  (cd "$pkg" && zip -qr "$OLDPWD/$out" manifest.json install.sh uninstall.sh payload)
  shasum -a 256 "$out"
}

remote_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

root_cmd() {
  adb_device shell "$KP -c $(remote_quote "$*")"
}

run_root_script() {
  local script="$1"
  local local_tmp remote_tmp
  local_tmp="$(mktemp "${TMPDIR:-/tmp}/r2-update.XXXXXX")"
  remote_tmp="${STAGE_BASE}/runner-$$-$(date +%s).sh"
  printf '%s\n' "$script" > "$local_tmp"
  adb_device shell "mkdir -p $(remote_quote "$STAGE_BASE")"
  adb_device push "$local_tmp" "$remote_tmp" >/dev/null 2>&1
  rm -f "$local_tmp"
  adb_device shell "chmod 755 $(remote_quote "$remote_tmp")"
  root_cmd "sh $remote_tmp"
  adb_device shell "rm -f $(remote_quote "$remote_tmp")" >/dev/null || true
}

install_package() {
  local pkg="$1"
  validate_package "$pkg" >/dev/null
  require_device

  local id version stage state
  id="$(json_field "$pkg/manifest.json" id)"
  version="$(json_field "$pkg/manifest.json" version)"
  stage="${STAGE_BASE}/${id}-${version}-$$"
  state="${ROOT_DIR}/updates/${id}"

  echo "Staging $id $version to $SERIAL:$stage"
  adb_device shell "rm -rf $(remote_quote "$stage") && mkdir -p $(remote_quote "$stage")"
  adb_device push "$pkg/." "$stage/" >/dev/null 2>&1

  echo "Installing as root"
  local q_root q_stage q_state q_id q_version
  q_root="$(remote_quote "$ROOT_DIR")"
  q_stage="$(remote_quote "$stage")"
  q_state="$(remote_quote "$state")"
  q_id="$(remote_quote "$id")"
  q_version="$(remote_quote "$version")"

  run_root_script "set -eu
mkdir -p $q_root/updates $q_root/modules $q_state
chmod 0700 $q_root $q_root/updates $q_root/modules $q_state
rm -rf $q_state/package
mkdir -p $q_state/package
cp -R $q_stage/. $q_state/package/
chmod 0755 $q_state/package/install.sh $q_state/package/uninstall.sh
SMARTISAX_ROOT=$q_root \
SMARTISAX_PACKAGE_ID=$q_id \
SMARTISAX_PACKAGE_VERSION=$q_version \
SMARTISAX_PACKAGE_DIR=$q_state/package \
SMARTISAX_STATE_DIR=$q_state \
sh $q_state/package/install.sh
date '+%Y-%m-%dT%H:%M:%S%z' > $q_state/installed_at
cp $q_state/package/manifest.json $q_state/manifest.json
chmod -R go-rwx $q_state
chmod 0755 $q_state/package/install.sh $q_state/package/uninstall.sh
rm -rf $q_stage"
  echo "Installed $id $version"
}

uninstall_package() {
  local id="$1"
  case "$id" in
    *[!a-z0-9._-]*|"") echo "Invalid package id: $id" >&2; exit 1 ;;
  esac
  require_device
  local state q_state q_root q_id
  state="${ROOT_DIR}/updates/${id}"
  q_state="$(remote_quote "$state")"
  q_root="$(remote_quote "$ROOT_DIR")"
  q_id="$(remote_quote "$id")"

  run_root_script "set -eu
if [ ! -d $q_state/package ]; then
  echo 'Package is not installed: '$q_id >&2
  exit 1
fi
chmod 0755 $q_state/package/uninstall.sh
SMARTISAX_ROOT=$q_root \
SMARTISAX_PACKAGE_ID=$q_id \
SMARTISAX_PACKAGE_VERSION='' \
SMARTISAX_PACKAGE_DIR=$q_state/package \
SMARTISAX_STATE_DIR=$q_state \
sh $q_state/package/uninstall.sh
rm -rf $q_state"
  echo "Uninstalled $id"
}

list_packages() {
  require_device
  run_root_script "set -eu
mkdir -p '$ROOT_DIR/updates' '$ROOT_DIR/modules'
chmod 0700 '$ROOT_DIR' '$ROOT_DIR/updates' '$ROOT_DIR/modules'
for d in '$ROOT_DIR'/updates/*; do
  [ -d \"\$d\" ] || continue
  id=\$(basename \"\$d\")
  version=\$(awk -F'\"' '/\"version\"[[:space:]]*:/ {print \$4; exit}' \"\$d/manifest.json\" 2>/dev/null || true)
  installed_at=\$(cat \"\$d/installed_at\" 2>/dev/null || true)
  echo \"\$id \$version \$installed_at\"
done"
}

status_device() {
  require_device
  run_root_script "set -eu
echo 'root:'
id
echo 'slot:'
getprop ro.boot.slot_suffix
echo 'kernelpatch:'
dmesg | grep -i 'KernelPatch Version' | tail -1 || true
echo 'updates root:'
chmod 0700 '$ROOT_DIR' '$ROOT_DIR/updates' '$ROOT_DIR/modules' 2>/dev/null || true
ls -ld '$ROOT_DIR' '$ROOT_DIR/updates' '$ROOT_DIR/modules' 2>/dev/null || true"
}

case "${1:-}" in
  validate)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    validate_package "$2"
    ;;
  pack)
    [ "$#" -ge 2 ] || { usage >&2; exit 2; }
    pack_package "$2" "${3:-}"
    ;;
  install)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    install_package "$2"
    ;;
  uninstall)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    uninstall_package "$2"
    ;;
  list)
    list_packages
    ;;
  status)
    status_device
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
