# Smartisax ADB USB Rescue Module

This is a local rescue module for the Smartisan R2 when USB enumerates as MTP
but ADB is not exposed.

It does not mount or replace system files. The scripts only request:

```sh
persist.sys.usb.config=mtp,adb
persist.vendor.usb.config=mtp,adb
sys.usb.config=mtp,adb
ctl.restart adbd
```

Install only if APatch exposes a local module ZIP installer. Reboot after
installing, or run the module action if APatch exposes an action button.

Log path on device:

```text
/data/adb/smartisax/logs/adb-usb-rescue.log
```
