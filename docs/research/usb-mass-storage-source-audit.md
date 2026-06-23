# USB Mass Storage Source Audit

Date: 2026-06-22

Scope: explain why a Mac still sees a Smartisan transfer-tool virtual disk after
the ROM-level HandShaker APK removal.

## Conclusion

The mounted "Smartisan transfer tool" disk is not produced by the Android
`HandShaker.apk` package. It is a vendor USB gadget mass-storage function backed
by a read-only ISO image:

```text
/vendor/etc/cdrom_install.iso
sha256=f4a5f3f482c9b091557a9b4366c8b808fa1cfd4d8c5f7afdbc11af12b0af25a0
ISO label=Smartisan 文件传输工具
```

Deleting the ROM HandShaker APK removes Smartisan's Android-side assistant
package, but it does not remove MTP, ADB, or the vendor mass-storage CD-ROM
function. Removing the mounted disk is a separate vendor-image task.

## Static Sources

`vendor/etc/init/hw/init.qcom.usb.rc` creates and wires the configfs mass-storage
function:

```text
/config/usb_gadget/g1/functions/mass_storage.0
sys.usb.config=mass_storage
sys.usb.config=mass_storage,adb
sys.usb.config=mtp,diag,diag_mdm,mass_storage,adb
```

The Smartisan default USB composition includes mass storage:

```text
persist.sys.usb.config=mtp,diag,diag_mdm,mass_storage,adb
```

`vendor/etc/init/hw/init.qcom.rc` also sets charger mode to mass storage:

```text
on charger
  setprop persist.sys.usb.config mass_storage
```

`vendor/build.prop` keeps the CD-ROM feature enabled:

```text
persist.service.cdrom.enable=1
vendor.usb.diag.func.name=diag
vendor.usb.use_ffs_mtp=0
```

## Live State

Read-only live audit report:

```text
hard-rom/inspect/usb-mass-storage-source-audit/live-usb-state-20260622-141450.txt
```

Key live values:

```text
persist.service.cdrom.enable=1
persist.sys.usb.config=mtp,diag,diag_mdm,mass_storage,adb
sys.usb.config=mtp,diag,diag_mdm,mass_storage,adb
sys.usb.state=mtp,diag,diag_mdm,mass_storage,adb
```

Configfs shows the active CD-ROM LUN:

```text
/config/usb_gadget/g1/functions/mass_storage.0/lun.0/cdrom=1
/config/usb_gadget/g1/functions/mass_storage.0/lun.0/file=/vendor/etc/cdrom_install.iso
/config/usb_gadget/g1/functions/mass_storage.0/lun.0/ro=1
/config/usb_gadget/g1/configs/b.1/f4 -> functions/mass_storage.0
```

## ISO Evidence

The stock vendor image contains the ISO at `/etc/cdrom_install.iso` inside
`vendor.img`. It was dumped to:

```text
hard-rom/inspect/usb-mass-storage-source-audit/cdrom_install.iso
size=41353216
sha256=f4a5f3f482c9b091557a9b4366c8b808fa1cfd4d8c5f7afdbc11af12b0af25a0
```

String evidence inside the ISO:

```text
Guide_to_Transferring_Files_Between_Your_Phone_and_a_Mac.pdf
HandShaker.dmg
HandShaker_Win7_Web_Setup.exe
HandShaker_Win8&Later_Web_Setup.exe
```

## Future Removal Boundary

If we decide to remove the mounted disk, do it as a dedicated vendor-image
candidate. Possible options:

```text
1. Remove or replace /vendor/etc/cdrom_install.iso.
2. Disable the mass_storage function from the default USB composition.
3. Keep MTP and ADB untouched.
4. Verify macOS no longer mounts the ISO while adb devices and MTP still work.
```

Do not combine this with PackageManager/service.jar work.

## v0.usb1 Candidate

`v0.usb1-no-smartisan-cdrom` is the first implementation candidate. It is built
from live-proven `v0.kg1-smartisax-skip-keyguard` and patches only `vendor_b`.

The chosen first cut is option 2, not option 1:

```text
keep /vendor/etc/cdrom_install.iso retained as inert payload
remove mass_storage.0 symlinks from the active vendor USB compositions
preserve ADB and MTP symlink routes
change charger fallback from mass_storage to charging
```

Reasoning:

```text
The ISO has repeated physical block aliases, so deleting it is a separate,
higher-risk filesystem operation. The live-visible disk should disappear once
mass_storage.0 is no longer attached to /config/usb_gadget/g1/configs/b.1.
```

Implementation note:

```text
Do not use debugfs hard-link held-stock replacement for these vendor init files.
A trial showed debugfs ln can create inode-0 directory entries in this vendor
image. The accepted offline route audits unique physical block ownership first,
then uses direct rm + write for the two init files.
```

Current status:

```text
offline build: PASS_BUILD_V0USB1_NO_SMARTISAN_CDROM
offline verifier: PASS_OFFLINE_IMAGE_V0USB1_NO_SMARTISAN_CDROM
live preflight: PASS
live flash: PASS
live verifier: PASS_READ_ONLY_V0USB1_NO_SMARTISAN_CDROM
macOS volume check: NO_SMARTISAN_TRANSFER_TOOL_VOLUME_OBSERVED
candidate sparse:
  hard-rom/build/super-otatrust-v0.usb1-no-smartisan-cdrom.sparse.img
  sha256=1608da03f036a4e9d4972d7c892fd018903e603a299040e5464a1512547829bc
live proof:
  active /config/usb_gadget/g1/configs/b.1 links mtp.gs0, diag.diag,
  diag.diag_mdm, and ffs.adb, but not mass_storage.0
```

## v0.usb2 Physical ISO Removal Candidate

`v0.usb2-physical-cdrom-iso-delete` is the physical cleanup follow-up on top of
live-proven `v0.usb1-no-smartisan-cdrom`. It still patches only `vendor_b`.

The candidate removes the ISO path:

```text
/vendor/etc/cdrom_install.iso
```

and keeps the v0.usb1 USB behavior:

```text
mass_storage.0 is still not linked into active USB configfs compositions
charger fallback remains charging
ADB and MTP symlink routes are preserved
```

Important shared-block finding:

```text
ISO inode=536
ISO size=41353216
logical block entries=9462
unique physical blocks=9392
internal duplicate block entries=70
```

After `debugfs rm` and `e2fsck`, 9391 of the old ISO physical blocks became
free and were zeroed. One block was reassigned to an existing vendor file and
was deliberately preserved:

```text
block 28776 -> inode 2994 -> /media/icon/cn.kuwo.player/logo
```

This means `debugfs icheck` before deletion does not fully describe Android
`shared_blocks` aliasing for this vendor image. The safe rule for future
physical cleanup is:

```text
remove the target path first, run e2fsck, classify old blocks again, zero only
old blocks that are still free, and preserve any blocks reassigned to existing
files.
```

Current status:

```text
offline build: PASS_BUILD_V0USB2_PHYSICAL_CDROM_ISO_DELETE
offline verifier: PASS_OFFLINE_IMAGE_V0USB2_PHYSICAL_CDROM_ISO_DELETE
live preflight: PASS
live flash: PASS
live verifier: PASS_READ_ONLY_V0USB2_PHYSICAL_CDROM_ISO_DELETE
macOS volume check: NO_SMARTISAN_TRANSFER_TOOL_VOLUME_OBSERVED
candidate sparse:
  hard-rom/build/super-otatrust-v0.usb2-physical-cdrom-iso-delete.sparse.img
  sha256=239b95b7ebbb467858c40b8e40a268cb1d83be145f5e9cddd8e2dc66a78153d0
vendor_b image:
  hard-rom/build/vendor-otatrust-v0.usb2-physical-cdrom-iso-delete.img
  sha256=f97230d6c810f08008180b9e1a56ec95d51bf7cc63df78ceffec9e2a37dca44f
offline proof:
  cdrom_iso_absent=ok
  cdrom_payload_strings=absent
  vendor_b_avb_fec=ok
  sparse_vendor_b_slice=ok
live proof:
  /vendor/etc/cdrom_install.iso absent
  mass_storage LUN file is empty
  active configfs has MTP, diag, diag_mdm, and ADB, but not mass_storage.0
  Smartisax focused and isKeyguardShowing=false
```
