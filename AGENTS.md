# AGENTS.md

## Mission

Smartisax customizes Smartisan R2 Smartisan OS 8.5.3 through verified hard-ROM
image builds, fastboot flashing, and live-device validation.

## First Reads

1. Read `README.md` for project status and layout.
2. Load `.agents/skills/smartisan-r2-hardrom/SKILL.md` before ROM, root,
   fastboot, system-app, overlay, or framework work.
3. Use `docs/README.md` as the documentation index.
4. Use `docs/index/` for split topic indexes and long-document navigation.
5. Use `docs/hard-rom-ota-trust.md` as the chronological evidence log.
6. Use `docs/v0.5-debloat-candidates.md` when choosing the next debloat set.

## Operating Rules

- Treat the live device and generated manifests as source of truth.
- Do not flash, reboot to bootloader, erase partitions, or run cleanup scripts
  that modify `/data` without explicit user confirmation for that step.
- Keep the latest successful sparse image local for fast rollback. The v0.2
  no-appstore image is the cold rollback baseline and may need restoring from
  SSDUSB; check `docs/rom-archive.md` before referencing old paths.
- After every flash, verify slot, `sys.boot_completed`, root, keyguard/launcher
  state, and package results before proceeding.
- Record successful and failed experiments in `docs/hard-rom-ota-trust.md`.
- Keep project docs and project skills updated when the workflow changes.

## Safety Model

This project treats "can flash" and "can boot" as different things. The safe
loop is:

1. Inspect static ROM evidence and current live/device state when needed.
2. Build the smallest candidate from the latest suitable live-proven baseline.
3. Verify image hashes, partition extents, fsck, dumped APK hashes, ZIP
   integrity, and FEC/AVB metadata offline.
4. Run `tools/r2-live-flash-preflight.sh` for the exact candidate.
5. Flash only after explicit confirmation.
6. Erase `misc` after flashing.
7. Boot and verify slot, root, keyguard/launcher, package state, and feature
   behavior.
8. Record evidence before the next experiment.

Local rollback command when the device is already in bootloader fastboot:

```bash
fastboot -s bb12d264 flash super hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
fastboot -s bb12d264 erase misc
fastboot -s bb12d264 reboot
```

Anything that touches the physical phone over USB/ADB/fastboot must use
non-sandboxed execution. Do not flash, reboot, erase, uninstall, clear `/data`,
or run cleanup scripts with side effects without explicit confirmation for that
exact step.

## Technical Boundaries

- Prefer hard-ROM changes for this project: edit partition images, rebuild
  `super`, flash, boot, verify.
- Prefer Android-native mechanisms such as static RRO overlays before directly
  repacking `framework-res.apk`.
- Do not treat bootloader unlock or root as proof that a system modification is
  safe. Android package, resource, SELinux, overlay, and boot-order contracts
  still apply.
- Avoid touching framework, services, SystemUI, Launcher, Keyguard, Settings,
  telephony, package installer, permission controller, and providers unless the
  user explicitly selects that higher-risk tier.

## Useful Commands

```bash
tools/r2-root.sh status
tools/r2-root.sh cmd 'id; getenforce; getprop ro.boot.slot_suffix'

fastboot -s bb12d264 getvar current-slot
fastboot -s bb12d264 getvar unlocked
fastboot -s bb12d264 getvar is-userspace
```
