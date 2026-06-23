#!/system/bin/sh

MODDIR="${0%/*}"
. "$MODDIR/common.sh"

restore_adb_usb boot-completed
