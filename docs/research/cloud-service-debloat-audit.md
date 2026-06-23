# Smartisan Cloud Service Debloat Audit

Date: 2026-06-18.

Purpose:

```text
Prepare the first cloud/account/sync hard-ROM debloat candidate after the
live-proven v0.26c launcher-entry-hide baseline.
```

Status:

```text
variant: v0.27-cloud-service-debloat
base: v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
state: flashed to B slot and live-verified
flash: completed after explicit confirmation
data cleanup: completed after separate explicit approval
```

## Target Packages

```text
com.smartisanos.cloudsync
  ROM path: /system/priv-app/CloudServiceSmartisan
  live path before v0.27: /data/app/.../com.smartisanos.cloudsync.../base.apk
  role: Smartisan account, sync adapters, find-phone, backup login, account
        center provider

com.smartisanos.cloudsyncshare
  ROM path: /system/priv-app/CloudServiceShare
  role: third-party login/share bridge for Smartisan cloud

com.smartisanos.cloudagent
  ROM path: /system/priv-app/CloudSyncAgent
  role: find-phone/cloud system provider agent
```

v0.4 already removed:

```text
com.smartisanos.cloudgallery
  ROM path: /system/app/CloudGallerySmartisan
```

## Static Coupling

Preflight level:

```text
tools/r2-rom-mod-preflight.py com.smartisanos.cloudsync --action delete
tools/r2-rom-mod-preflight.py com.smartisanos.cloudsyncshare --action delete
tools/r2-rom-mod-preflight.py com.smartisanos.cloudagent --action delete

result: ORANGE for the cloud service group
reason: priv-app packages, sysconfig references, exported components, providers
```

Important references outside the target packages:

```text
SettingsSmartisan:
  cloud/support Settings rows
  MasterClear binds CloudFindPhoneService and queries
  content://com.smartisanos.cloudsync.accountcenter
  lock/password and cloud login helpers

ContactsSmartisan:
  Smartisan account type and first-launch cloud sync helper

Backup:
  explicit cloudsync references and find-phone service stubs

WalletSmartisan:
  account-center provider query and cloud account activity launch

framework/services/telephony:
  lost-mode/find-phone helpers and cloud-related allowlist behavior
```

This is still acceptable as a staged debloat candidate because the target
behavior is to remove Smartisan cloud account/sync/find-phone integration, but
it means the post-flash verifier must check core package presence and package
manager residue instead of only checking deleted files.

## ROM Build

Builder:

```bash
tools/r2-hardrom-build-v0.27-cloud-service-debloat.sh
```

Output:

```text
sparse:
  hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img
  sha256=11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1

system_b image:
  hard-rom/build/system-otatrust-v0.27-cloud-service-debloat.img
  sha256=e81e02caa9009b74138860f5c8c51ef66401ad863c119572d5cb97a574038bad

source sparse:
  hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1
```

ROM changes:

```text
removed:
  /system/priv-app/CloudServiceSmartisan
  /system/priv-app/CloudServiceShare
  /system/priv-app/CloudSyncAgent

edited:
  /system/etc/sysconfig/hiddenapi-package-whitelist.xml
    removed com.smartisanos.cloudsync
    removed com.smartisanos.cloudsyncshare
    removed com.smartisanos.cloudagent
```

The build does not flash, reboot, erase misc, or change `/data`.

## Verification

Offline verifier:

```bash
tools/r2-verify-v0.27-cloud-service-debloat.sh --offline-image
```

Latest report:

```text
hard-rom/inspect/v0.27-cloud-service-debloat/verify-v0.27-cloud-service-debloat-offline-image-20260618-202805.txt
result: PASS
```

Verified:

```text
system_b sparse slice matches the generated v0.27 system image
system_ext_b remains byte-identical to v0.26c
e2fsck -fn passes
all three cloud package directories are absent
hiddenapi whitelist no longer references the three cloud packages
```

Live-flash preflight:

```bash
tools/r2-live-flash-preflight.sh v0.27-cloud-service-debloat
```

Report:

```text
hard-rom/inspect/v0.27-cloud-service-debloat/preflight-v0.27-cloud-service-debloat-20260618-202604.txt
result: PASS
```

Required flash confirmation:

```text
确认刷入 v0.27-cloud-service-debloat B 槽
```

## Live Data Boundary

Before v0.27, the live device reports:

```text
com.smartisanos.cloudsync:
  package path: /data/app/.../com.smartisanos.cloudsync.../base.apk
  flags: SYSTEM HAS_CODE UPDATED_SYSTEM_APP

com.smartisanos.cloudsyncshare:
  package path: /system/priv-app/CloudServiceShare/CloudServiceShare.apk

com.smartisanos.cloudagent:
  package path: /system/priv-app/CloudSyncAgent/CloudSyncAgent.apk
```

Dry-run capture:

```bash
tools/r2-clean-v0.27-cloud-service-data.sh --dry-run
```

Latest report:

```text
hard-rom/inspect/v0.27-cloud-service-debloat/cloud-service-data-clean-20260618-202901.txt
```

Original implication:

```text
ROM removal alone may not make com.smartisanos.cloudsync disappear because the
live device has an updated-system /data/app copy. If the post-flash read-only
verifier reports cloudsync still present from /data/app, run the cleanup script
only after a separate explicit /data package cleanup approval.
```

Cleanup command, after approval only:

```bash
tools/r2-clean-v0.27-cloud-service-data.sh --apply
```

The cleanup script uses PackageManager commands only. It does not manually
delete `/data/app` files.

Approved cleanup result:

```text
approval:
  确认清理 v0.27 云服务 /data 残留
report:
  hard-rom/inspect/v0.27-cloud-service-debloat/cloud-service-data-clean-20260618-204428.txt
result:
  pm uninstall --user 0 com.smartisanos.cloudsync returned Success
  post-cleanup package paths were empty for all three cloud packages
  cloud launcher, sync adapter, account authenticator, and account-center
  provider resolver surfaces were empty
note:
  cmd package uninstall-system-updates throws a NullPointerException on this
  build once the system base is already absent. It did not prevent the
  PackageManager user cleanup from succeeding.
```

## Post-Flash Acceptance

After an authorized flash and boot:

```bash
tools/r2-verify-v0.27-cloud-service-debloat.sh --read-only
```

Required acceptance:

```text
boot_completed=1
slot=_b
root available
keyguard not showing after unlock
com.smartisanos.cloudsync absent
com.smartisanos.cloudsyncshare absent
com.smartisanos.cloudagent absent
cloud launcher, sync adapter, authenticator, and account-center provider
  surfaces absent
core Settings, Contacts, providers, MMS, Phone, Launcher, and SystemUI packages
  still present
```

Final live verifier:

```text
report:
  hard-rom/inspect/v0.27-cloud-service-debloat/verify-v0.27-cloud-service-debloat-device-20260618-204534.txt
result:
  PASS
evidence:
  boot_completed=1
  slot=_b
  root available
  keyguard not showing
  com.smartisanos.cloudsync absent
  com.smartisanos.cloudsyncshare absent
  com.smartisanos.cloudagent absent
  cloud launcher, sync adapter, account authenticator, and account-center
  provider surfaces absent
  core Settings, Contacts, providers, MMS, Phone, Launcher, and SystemUI
  packages present
```
