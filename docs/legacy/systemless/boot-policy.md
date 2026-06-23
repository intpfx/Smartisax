# Boot Policy

`updates/boot-policy` installs a minimal APatch module named
`smartisax_boot_policy`.

The module does not mount or replace any system files. It creates `skip_mount`
and only uses `boot-completed.sh`, so policy checks run after Android reports
boot completion.

Runtime files:

```text
/data/adb/apd
/data/adb/ap/bin/busybox
/data/adb/ap/bin/magiskpolicy
/data/adb/ap/bin/resetprop
/data/adb/modules/smartisax_boot_policy
/data/adb/smartisax/bin/boot-policy-runner.sh
/data/adb/smartisax/policy.d
/data/adb/smartisax/logs/boot-policy.log
```

On this R2, KernelPatch root was working but `/data/adb/apd` was not present,
so APatch module scripts did not run after reboot until the APatch userland
runtime was deployed.

The runner executes executable scripts in:

```text
/data/adb/smartisax/policy.d/*.sh
```

Current policy scripts:

- `20-modern-browser-default.sh`: if `modern-browser` is installed, keep
  `org.cromite.cromite` as the default browser after reboot.

Commands:

```sh
tools/r2-update.sh validate updates/boot-policy
tools/r2-update.sh pack updates/boot-policy
tools/r2-update.sh install updates/boot-policy
tools/r2-update.sh uninstall boot-policy
```

Packaged update artifact:

```text
dist/boot-policy-1.0.0.zip
sha256: b37f0ddf23456555ab00941b2bc9788e43e99b8c4996c4242ea2652fd79f3394
```

Manual run:

```sh
tools/r2-root.sh cmd '/data/adb/smartisax/bin/boot-policy-runner.sh manual'
tools/r2-root.sh cmd '/data/adb/apd boot-completed'
```

`apd boot-completed` starts APatch's foreground listener. For ad-hoc checks,
prefer the runner command unless you deliberately want to test APatch's full
boot-completed entrypoint.

## Verified Behavior

Verified on 2026-06-17:

- APatch `boot-completed.sh` is invoked automatically after reboot once
  `/data/adb/apd` is deployed.
- Before user unlock, Android reports user 0 as `RUNNING_LOCKED`, and browser
  resolution may return `No activity found`; the runner waits instead of
  changing policy.
- After unlock, user 0 becomes `RUNNING_UNLOCKED`; the runner sees
  `org.cromite.cromite` and completes successfully.

Observed log shape:

```text
[boot-completed] browser resolver ready ...
[boot-completed] run policy: /data/adb/smartisax/policy.d/20-modern-browser-default.sh
modern-browser default ok: org.cromite.cromite
[boot-completed] done
```

Diagnostics:

```sh
tools/r2-root.sh cmd 'cat /data/adb/smartisax/modules/boot-policy/status.txt'
tools/r2-root.sh cmd 'tail -120 /data/adb/smartisax/logs/boot-policy.log'
```

Recovery note: APatch safe mode can disable modules if a module causes boot
trouble. Hold/press Volume Down during early boot according to APatch's rescue
documentation.
