# Build And Flash Protocol

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Flashing Protocol

Do not flash without explicit user confirmation for the exact variant.

Before flashing:

```bash
tools/r2-live-flash-preflight.sh <variant>
shasum -a 256 hard-rom/build/<variant>.sparse.img
adb -s bb12d264 shell 'getprop ro.boot.slot_suffix; getprop sys.boot_completed'
```

Enter bootloader:

```bash
adb -s bb12d264 reboot bootloader
fastboot -s bb12d264 getvar current-slot
fastboot -s bb12d264 getvar unlocked
fastboot -s bb12d264 getvar is-userspace
```

Flash:

```bash
fastboot -s bb12d264 flash super hard-rom/build/<variant>.sparse.img
fastboot -s bb12d264 erase misc
fastboot -s bb12d264 reboot
```

Post-boot checks:

```bash
adb -s bb12d264 shell 'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim'
tools/r2-root.sh status
adb -s bb12d264 shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp|isKeyguardShowing' | head"
```

If a new build fails, return to fastboot and flash the latest local stable
sparse image, then `fastboot erase misc`. If a lower-change fallback is needed,
restore the v0.2 cold archive from SSDUSB first; see `docs/rom-archive.md`.

## Build Rules

Prefer exact-current super patching over rebuilding the full dynamic layout from
scratch. The known B-slot `system_b` mapping in the current super layout is:

```text
system_b_start_sector: 10487744
system_b_size_sectors: 5955192
4096-byte seek: 1310968
4096-byte count: 744399
```

The known B-slot `product_b` mapping in the current super layout is:

```text
product_b_start_sector: 17021888
product_b_size_sectors: 334200
4096-byte seek: 2127736
4096-byte count: 41775
```

`tools/r2-hardrom-build-super.sh` supports exact-current system_b replacement
variants. v0.10 extends the exact-current pattern to patch `product_b` too; do
not pretend a system-only image changes product contents.

Generated images need:

```text
system image manifest
super raw manifest
sparse image sha256
lpdump slot0/slot1
hash check that the partition slice in raw super equals the source image
```

Important ext4 shared-block rule:

```text
system/product ext4 images use shared_blocks.
Do not replace files with debugfs rm + write on these images.
That can free blocks still referenced by other inodes, and e2fsck can then
repair the conflict by corrupting the replacement APK.

For replacement on shared_blocks images, use the v0.10 pattern:
  1. ln old public path to a hidden non-.apk stock-held path
  2. write new APK to a hidden temporary path
  3. set mode/uid/gid/SELinux xattr on the temporary inode
  4. unlink the old public path
  5. ln temporary inode to the public path
  6. unlink the temporary path
  7. e2fsck -fy, then e2fsck -fn
  8. dump the public path again and verify full APK sha256 plus unzip -t

This intentionally leaves a hidden stock-held inode to keep shared blocks
referenced. Hidden held files must not end in .apk so package/overlay scanners
do not parse them.
```

Narrow exception, proven for the v0.11 SmartisanSystemUI target only:

```text
system_ext_b SmartisanSystemUI.apk has repeated physical block aliases inside
the same inode, so full in-place overwrite is unsafe unless the new same-size
APK preserves every alias group byte-for-byte. The v0.11 same-size SystemUI APK
does not preserve those alias groups.

For v0.11, ordinary held-stock replacement could not be used on system_ext_b.
The accepted path was:
  1. build a same-size SmartisanSystemUI APK
  2. audit every unique physical block with debugfs/icheck
  3. prove all unique blocks are owned only by the SmartisanSystemUI inode
  4. debugfs rm the public path and write the same path back
  5. restore mode/uid/gid/SELinux xattr
  6. e2fsck -fy, then e2fsck -fn
  7. dump the APK from the final image and verify sha256 plus unzip -t

Evidence:
  hard-rom/work/v0.11-native-darkmode/systemui-block-owner-audit.json
  hard-rom/inspect/v0.11-native-darkmode/verify-v0.11-native-darkmode-offline-image-20260618-163441.txt

Do not reuse this as a blanket system_ext rule. Re-run the owner audit, alias
check, fsck, dumped-APK hash, ZIP integrity, signature-boundary, and sparse
slice checks for each target.
```
