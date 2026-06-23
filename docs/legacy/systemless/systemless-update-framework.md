# Smartisax Systemless Update Framework

This workspace now has a small root-based update framework for the rooted
Smartisan R2.

## Root Wrapper

```sh
tools/r2-root.sh status
tools/r2-root.sh cmd 'id'
tools/r2-root.sh cmd 'ls -l /data/adb'
```

The wrapper uses APatch through `/system/bin/kp -c`.

Current verified device state:

- device serial: `bb12d264`
- active slot: `_b`
- boot state: `orange`
- SELinux: `Enforcing`
- root command: `/system/bin/kp -c id`

## Update Packages

Packages are directories with:

- `manifest.json`
- `install.sh`
- `uninstall.sh`
- optional `payload/`

Install scripts run as root and receive:

- `SMARTISAX_ROOT`
- `SMARTISAX_PACKAGE_ID`
- `SMARTISAX_PACKAGE_VERSION`
- `SMARTISAX_PACKAGE_DIR`
- `SMARTISAX_STATE_DIR`

Installed package state is kept under:

```text
/data/adb/smartisax/updates/<package-id>
```

Systemless module data should live under:

```text
/data/adb/smartisax/modules/<package-id>
```

The framework keeps `/data/adb/smartisax`, `updates`, and `modules`
root-only (`0700`). Package scripts are copied to the package state directory
and run as root through APatch.

## Commands

```sh
tools/r2-update.sh validate updates/hello-marker
tools/r2-update.sh pack updates/hello-marker
tools/r2-update.sh install updates/hello-marker
tools/r2-update.sh list
tools/r2-update.sh uninstall hello-marker
tools/r2-update.sh install updates/modern-browser
tools/r2-update.sh uninstall modern-browser
tools/r2-update.sh install updates/boot-policy
tools/r2-update.sh uninstall boot-policy
```

The `hello-marker` package is a harmless smoke test. It has been installed,
listed, inspected, and uninstalled on the real device. The device is currently
left clean with no installed test package.

Latest package artifact:

```text
dist/hello-marker-1.0.0.zip
sha256: 99b6b06b76fbee0b615b36947e837d11c90b285489fddac1c6b6d8ca32874972
```

## Safety Rules

- Do not write to `super`, `system`, `vendor`, `product`, or `oem` from update
  packages until the systemless framework has been validated.
- Keep `boot_a` stock and `boot_b` APatch-rooted unless deliberately changing
  slot strategy.
- Keep `.apatch-superkey` private.
- Keep the backup directory:
  `backups/2026-06-17-apatch-root-critical`.
- If a boot experiment fails, the proven recovery path is stock `boot_b` plus
  `fastboot erase misc`, using the backup README for exact commands.

## Next Package Pattern

For the first real customization package:

1. Copy `updates/hello-marker` to `updates/<new-id>`.
2. Change `manifest.json`.
3. Put files under `payload/`.
4. Implement idempotent `install.sh` and `uninstall.sh`.
5. Validate locally, install on device, then reboot-test.

`boot-policy` is now the persistent policy layer. Future packages should put
small executable policy scripts in `/data/adb/smartisax/policy.d` when they
need boot-completed self-check or repair behavior.
