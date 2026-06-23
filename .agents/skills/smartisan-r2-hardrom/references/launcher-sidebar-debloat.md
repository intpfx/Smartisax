# Launcher, Sidebar, And Debloat Gates

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Launcher Entry Hiding Strategy

For requests to keep a feature installed and working while removing only its
desktop app entry, treat the change as manifest launcher-surface surgery, not
as debloat:

```text
tools/r2-launcher-entry-hide-audit.py
docs/research/launcher-entry-hide-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/launcher-entry-hide-audit.tsv
```

Current target set:

```text
闪念胶囊: com.smartisanos.sara / VoiceAssistant.apk
视频播放器: com.smartisanos.videoplayerproject / VideoPlayer.apk
屏幕录制: com.smartisanos.screenrecorder / ScreenRecorderSmartisan.apk
搜索: com.smartisanos.quicksearch / QuickSearchBoxSmartisan.apk
一步: com.smartisanos.sidebar / Sidebar.apk
```

Do not use package deletion or `pm disable` for this goal. The intended ROM
route is to remove only `android.intent.category.LAUNCHER` from the identified
`MAIN` intent-filter while keeping the activity enabled and preserving
non-launcher intent filters, services, providers, receivers, permissions, and
explicit settings routes.

Current staging:

```text
v0.26c live-proven baseline: VideoPlayer + ScreenRecorder + QuickSearch + Sara / VoiceAssistant + Sidebar / One Step
v0.26b previous live-proven baseline: VideoPlayer + ScreenRecorder + QuickSearch + Sara / VoiceAssistant
v0.26a.2 previous live-proven baseline: VideoPlayer + ScreenRecorder + QuickSearch
```

Current v0.26a status:

```text
tools/r2-build-launcher-entry-hide-apks.sh
tools/r2-hardrom-build-v0.26a-launcher-entry-hide.sh
tools/r2-verify-v0.26a-launcher-entry-hide.sh
tools/r2-apk-preserve-v2-signing-block.py
tools/r2-verify-v0.26a.1-launcher-entry-hide-v2cert.sh
tools/r2-verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump.sh
tools/r2-hardrom-build-v0.26b-sara-launcher-entry-hide.sh
tools/r2-verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.sh
tools/r2-hardrom-build-v0.26c-sidebar-launcher-entry-hide.sh
tools/r2-verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.sh

v0.26a live result:
  flashed to B slot and booted, but PackageManager failed collecting
  certificates for the three manifest-edited APKs because the v2 signing block
  had been stripped and the JAR/v1 path hits the AndroidManifest.xml digest
  boundary. The launcher entries disappeared, but the packages were removed
  from the live package set. v0.26a is rejected.

v0.26a.1 live partial failure:
  flashed to B slot and booted. PackageManager accepted the three v2cert APKs
  from /system and their device APK manifests truly lacked LAUNCHER, but after
  user unlock the launcher entries reappeared. Source and live evidence show
  PackageManager reused stale /data/system/package_cache ParsedPackage data.
  PackageCacher keys cluster packages as packageFile.getName() + '-' + flags
  and validates cache freshness using packageFile mtime. For these packages,
  packageFile is the package directory, not the APK file; the ROM directories
  still had 2009-01-01 mtimes while stale cache files from 2026-06-17 were
  newer, so PackageCacher treated old resolver data as fresh.

live-proven fix:
  v0.26a.2-launcher-entry-hide-v2cert-cachebump

base sparse:
  hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img
  sha256=2f1a4d8b8579551bf04246d00099f15c5c5a42146336cd6a00d129bbcffb8fa0
super sparse:
  hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=a96006fcd6c53b82aa3638411e01a36ce0bb92b02737aa5351fdd8827578e792
retired local system image:
  hard-rom/build/system-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump.img
  sha256=5282661df53643800601e816882b31113b96991340d701c1598feefa89285ae7
patched APKs:
  VideoPlayer launcher-hidden
    sha256=482d05dbe82611e7dedd6eed0964e85cf6882ea22709981cec101311489d2734
  ScreenRecorderSmartisan launcher-hidden
    sha256=36782cff3384242e1560b3f9748ce86ef426ab9e904967c1b35011db989a4e4d
  QuickSearchBoxSmartisan launcher-hidden
    sha256=deb179992f9886dbf34ba44814a7456eb26515d9bf8bc8ab33b205519477c604
package directory mtime bump:
  /system/priv-app/VideoPlayer
  /system/priv-app/ScreenRecorderSmartisan
  /system/app/QuickSearchBoxSmartisan
  mtime=0x6a33ddc0 (2026-06-18 20:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.26a.2-launcher-entry-hide-v2cert-cachebump/verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-184855.txt
  PASS; verifies the image contains the three audited manifest-only APKs,
  only AndroidManifest.xml changes as expected, MAIN remains while LAUNCHER is
  removed, APK Sig Block 42 is present, expected AndroidManifest.xml digest
  boundaries are present, held-stock hidden paths exist, package directory
  mtimes are bumped, sparse system_b matches the generated system image, and
  system_ext_b is byte-identical to v0.11.1.
preflight:
  tools/r2-live-flash-preflight.sh v0.26a.2-launcher-entry-hide-v2cert-cachebump
  PASS; required confirmation phrase:
  确认刷入 v0.26a.2-launcher-entry-hide-v2cert-cachebump B 槽
status:
  flashed to B slot and live-verified after user 0 was RUNNING_UNLOCKED.
  VideoPlayer, ScreenRecorderSmartisan, and QuickSearch remain installed from
  /system with expected hashes and no /data/app shadows, and their desktop
  launcher entries are absent. The failed v0.26a.1 sparse/system large images
  were removed locally after this PASS because free space dropped below 20 GiB;
  logs and offline/live evidence remain under hard-rom/inspect.
```

Current v0.26b status:

```text
variant:
  v0.26b-sara-launcher-entry-hide-v2cert-cachebump
purpose:
  hide only the Sara/VoiceAssistant desktop launcher entry while keeping the
  package, providers, services, explicit shortcuts, and the v0.26a.2 lower-risk
  launcher-entry-hide changes.
base sparse:
  hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=a96006fcd6c53b82aa3638411e01a36ce0bb92b02737aa5351fdd8827578e792
super sparse:
  hard-rom/build/super-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=599578445026fbf8d35edffc014b71e7507eba9ce2921a82d0d298465e020ff1
retired local system image:
  hard-rom/build/system-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.img
  sha256=59dfbf3e5c15f95ee15b32624dd6fd03efd38a0f35325611c63b66da473e5fca
patched APK:
  hard-rom/build/apk/com.smartisanos.sara-launcher-hidden-v2cert.apk
  sha256=f87e00479cdeb4dcfcd4215235349d8b18ac42096279f656bdeb8ce7a62a7637
package directory mtime bump:
  /system/priv-app/VoiceAssistant
  mtime=0x6a33ebd0 (2026-06-18 21:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-191608.txt
  PASS; verifies the prior v0.26a.2 APKs are retained, Sara changes only
  AndroidManifest.xml, MAIN remains while LAUNCHER is removed, APK Sig Block
  42 is present, expected AndroidManifest.xml digest boundaries are present,
  held-stock paths exist, package directory mtimes are correct, system_b
  sparse matches the generated system image, and system_ext_b is retained from
  v0.26a.2.
preflight:
  tools/r2-live-flash-preflight.sh v0.26b-sara-launcher-entry-hide-v2cert-cachebump
  PASS; required confirmation phrase:
  确认刷入 v0.26b-sara-launcher-entry-hide-v2cert-cachebump B 槽
live flash:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/flash-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-20260618-192548.txt
  PASS; fastboot gates current-slot=b, unlocked=yes, is-userspace=no; flashed
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/boot-wait-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-20260618-193145.txt
  PASS; boot=1, slot=_b, bootanim=stopped on attempt 4.
live verifier:
  hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump/verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-device-20260618-193214.txt
  PASS; all four edited packages match expected /system hashes with no
  /data/app shadows, user 0 is RUNNING_UNLOCKED, keyguard is not showing,
  smt_launcher has focus, the four desktop launcher entries are absent, and
  Sara provider/shortcut feature surfaces remain present.
status:
  accepted as the current live-proven launcher-entry-hide baseline.
```

Current v0.26c status:

```text
variant:
  v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
purpose:
  hide only the Sidebar/One Step desktop launcher entry while keeping the
  shared-UID package, SidebarService, providers, explicit settings route, and
  framework-bound window surfaces functional.
source audit:
  docs/research/sidebar-one-step-source-audit.md
base sparse:
  hard-rom/build/super-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=599578445026fbf8d35edffc014b71e7507eba9ce2921a82d0d298465e020ff1
super sparse:
  hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1
retired local system image:
  hard-rom/build/system-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.img
  sha256=c0aaf672f208cf11d8849d1459b5eef571a1710e21d8672e62c45725c012f945
patched APK:
  hard-rom/build/apk/com.smartisanos.sidebar-launcher-hidden-v2cert.apk
  sha256=0c238bfb79a786ee28a325ca6983c5f4bc5d8877a19756a912968da9ecae93f2
package directory mtime bump:
  /system/priv-app/Sidebar
  mtime=0x6a33f9e0 (2026-06-18 22:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-offline-image-20260618-194804.txt
  PASS; verifies the prior four launcher-hidden APKs are retained, Sidebar
  changes only AndroidManifest.xml, MAIN remains while LAUNCHER is removed
  from SettingActivity, APK Sig Block 42 is present, held-stock paths exist,
  package directory mtimes are correct, system_b sparse matches the generated
  system image, and system_ext_b is retained from v0.26b.
preflight:
  tools/r2-live-flash-preflight.sh v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump
  PASS; required confirmation phrase:
  确认刷入 v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump B 槽
status:
  flashed to B slot after explicit confirmation and live-verified. The first
  post-boot verifier run failed because user 0 was still RUNNING_LOCKED with
  keyguard showing. A second run after unlock exposed a verifier-only
  SidebarService check that was too narrow; the verifier now checks the live
  ServiceRecord from dumpsys activity services.
live flash:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/flash-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-20260618-200032.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no, flashed
  sparse super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/boot-wait-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-20260618-200633.txt
  PASS; boot=1, slot=_b, bootanim=stopped, verified=orange.
live verifier:
  hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump/verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-device-20260618-200821.txt
  PASS; all five edited packages match expected /system hashes with no
  /data/app shadows, user 0 is RUNNING_UNLOCKED, keyguard is not showing, all
  five desktop launcher entries are absent, Sidebar shared UID is intact,
  SidebarService is live and system-bound, all four providers are present,
  explicit SettingActivity resolves, and sidebar windows are present.
```

This is a new gate. v0.24 proved resources-only APK replacement on the current
line; it does not by itself prove AndroidManifest component changes. v0.26a
proved that stripping the v2 signing block is not acceptable for manifest edits
because PackageManager certificate collection falls back to the JAR path and
hits the AndroidManifest.xml digest boundary. v0.26a.1 preserves a copied stock
v2 signing block as the certificate carrier, but also proved package directory
mtime matters for Android 11 PackageCacher. For cluster package system-app
manifest changes, bump the package directory mtime or clear package_cache after
explicit /data-write approval. v0.26a.2 proved the lower-risk batch, and
v0.26b is now the live-proven baseline that adds Sara after its separate
source/shortcut/provider review and image gate. v0.26c is now the separate
Sidebar shared-UID RED live-proven baseline after service/provider/window
verification.

Current v0.27 status:

```text
variant:
  v0.27-cloud-service-debloat
purpose:
  hard-remove Smartisan cloud service ROM packages on top of live-verified
  v0.26c.
source audit:
  docs/research/cloud-service-debloat-audit.md
base sparse:
  hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
  sha256=fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1
super sparse:
  hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img
  sha256=11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1
retired local system image:
  hard-rom/build/system-otatrust-v0.27-cloud-service-debloat.img
  sha256=e81e02caa9009b74138860f5c8c51ef66401ad863c119572d5cb97a574038bad
removed ROM paths:
  /system/priv-app/CloudServiceSmartisan
  /system/priv-app/CloudServiceShare
  /system/priv-app/CloudSyncAgent
offline verifier:
  hard-rom/inspect/v0.27-cloud-service-debloat/verify-v0.27-cloud-service-debloat-offline-image-20260618-202805.txt
  PASS; verifies absent cloud directories, hiddenapi whitelist cleanup,
  system_b sparse slice equality, and system_ext_b retention from v0.26c.
preflight:
  hard-rom/inspect/v0.27-cloud-service-debloat/preflight-v0.27-cloud-service-debloat-20260618-203558.txt
  PASS; required confirmation phrase:
  确认刷入 v0.27-cloud-service-debloat B 槽
live flash:
  hard-rom/inspect/v0.27-cloud-service-debloat/flash-v0.27-cloud-service-debloat-20260618-203648.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed sparse
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.27-cloud-service-debloat/boot-wait-v0.27-cloud-service-debloat-20260618-204255.txt
  PASS; boot_completed=1, slot=_b, bootanim=stopped, verified=orange.
approved data cleanup:
  hard-rom/inspect/v0.27-cloud-service-debloat/cloud-service-data-clean-20260618-204428.txt
  PackageManager cleanup removed the updated-system com.smartisanos.cloudsync
  /data app for user 0. Smartisan's uninstall-system-updates shell path throws
  a NullPointerException after the system base is gone, but pm uninstall
  --user 0 succeeded and post-cleanup package/resolver surfaces were empty.
live verifier:
  hard-rom/inspect/v0.27-cloud-service-debloat/verify-v0.27-cloud-service-debloat-device-20260618-204534.txt
  PASS; boot_completed=1, slot=_b, root available, keyguard not showing,
  cloudsync/cloudsyncshare/cloudagent absent, cloud launcher/sync adapter/
  account authenticator/account-center provider surfaces absent, and core
  Settings, Contacts, providers, MMS, Phone, Launcher, and SystemUI present.
status:
  accepted as the current live-proven cloud-service hard-debloat state.
```

Current v0.28 status:

```text
variant:
  v0.28-wallet-handshaker-debloat
purpose:
  hard-remove Smartisan Wallet and HandShaker ROM packages on top of
  live-verified v0.27.
source audit:
  docs/research/wallet-handshaker-debloat-audit.md
base sparse:
  hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img
  sha256=11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1
super sparse:
  hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img
  sha256=705c42c5b639ed9f08e8555749e6b7abaf9d281a2f7f2324e2ef29ceec561728
retired local system image:
  hard-rom/build/system-otatrust-v0.28-wallet-handshaker-debloat.img
  sha256=334f7e32491c2a43f524d3112807c19cf6f104a20fae2d2eb9f749aee9b73daf
removed ROM paths:
  /system/priv-app/WalletSmartisan
  /system/app/HandShaker
offline verifier:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/verify-v0.28-wallet-handshaker-debloat-offline-image-20260618-214643.txt
  PASS; verifies WalletSmartisan and HandShaker are absent, hiddenapi whitelist
  rows are removed, MtpService/MediaProvider/MediaProviderLegacy paths are
  retained, system_b sparse slice matches the generated image, and
  system_ext_b/product_b are byte-identical to v0.27.
preflight:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/preflight-v0.28-wallet-handshaker-debloat-20260618-214903.txt
  PASS; required confirmation phrase:
  确认刷入 v0.28-wallet-handshaker-debloat B 槽
status:
  flashed to B slot after explicit confirmation and live-verified at the
  read-only pre-clean gate; after separate explicit approval, the Wallet
  updated-system /data residue was cleaned and the final verifier passed.
live flash:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/flash-v0.28-wallet-handshaker-debloat-20260618-215337.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed sparse
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/boot-wait-v0.28-wallet-handshaker-debloat-20260618-215908.txt
  PASS; boot_completed=1, slot=_b, bootanim=stopped, verified=orange.
live pre-clean verifier:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/verify-v0.28-wallet-handshaker-debloat-device-pre-clean-20260618-215940.txt
  PASS; boot_completed=1, root available, keyguard not showing, launcher
  focused, sys.usb.state includes mtp and adb, MtpService/MediaProvider/
  MediaProviderLegacy are present, HandShaker is absent, and Wallet remains
  only as expected updated-system /data residue.
approved data cleanup:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/wallet-data-clean-20260618-220153.txt
  PackageManager cleanup removed the updated-system com.smartisanos.wallet
  /data app for user 0. Smartisan's uninstall-system-updates shell path throws
  the same NullPointerException seen in v0.27 after the system base is gone,
  but pm uninstall --user 0 succeeded and post-cleanup Wallet paths/resolver
  surfaces were empty.
live final verifier:
  hard-rom/inspect/v0.28-wallet-handshaker-debloat/verify-v0.28-wallet-handshaker-debloat-device-20260618-220158.txt
  PASS; boot_completed=1, root available, keyguard not showing, sys.usb.state
  includes mtp and adb, MtpService/MediaProvider/MediaProviderLegacy are
  present, and both com.smartisanos.wallet and com.smartisanos.smartfolder.aoa
  are absent.
```

Current v0.29 status:

```text
variant:
  v0.29-sidebar-topbar-hide
purpose:
  delete the stock One Step topbar controls/text while preserving a blank
  topbar slot for future features and keeping Sidebar drag/status switching
  surfaces intact.
base sparse:
  hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img
  sha256=705c42c5b639ed9f08e8555749e6b7abaf9d281a2f7f2324e2ef29ceec561728
super sparse:
  hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img
  sha256=a8207ee148946057fc2d9c00780b2939c8307f7b0b88ae2b4bc304cfb39892d9
retired local system image:
  hard-rom/build/system-otatrust-v0.29-sidebar-topbar-hide.img
  sha256=99cef7a65c499f45da93c5cb4ee9f0dadf58623aa766f8d8698de64282f86660
patched APK:
  hard-rom/build/apk/com.smartisanos.sidebar-topbar-hidden-v2cert.apk
  sha256=d69e0c7d5960f623795b4c95d1d306f7a2c19b21b22bd6533296943fd4e6772b
changed APK members:
  classes.dex
  res/layout/top_area_title_view.xml
code/layout semantics:
  topbar_slot_preserved=ok
  topbar_children_deleted=ok
  topbar_smali_references_removed=ok
package directory mtime:
  /system/priv-app/Sidebar
  mtime=0x6a3407f0 (2026-06-18 23:00:00 +0800)
offline verifier:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/verify-v0.29-sidebar-topbar-hide-offline-image-20260618-222711.txt
  PASS; verifies exact changed APK members, launcher-hidden manifest retention,
  blank topbar slot preservation, removed stock topbar code bindings, system_b
  sparse slice equality, system_ext_b/product_b retention from v0.28, and
  v0.27/v0.28 debloat removals.
preflight:
  tools/r2-live-flash-preflight.sh v0.29-sidebar-topbar-hide
  PASS; required confirmation phrase:
  确认刷入 v0.29-sidebar-topbar-hide B 槽
live flash:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/flash-v0.29-sidebar-topbar-hide-20260618-223822.txt
  PASS; fastboot current-slot=b, unlocked=yes, is-userspace=no; flashed sparse
  super 9/9, erased misc, and rebooted.
boot wait:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/boot-wait-v0.29-sidebar-topbar-hide-20260618-224404.txt
  PASS; boot_completed=1, slot=_b, bootanim=stopped, verified=orange.
live verifier:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/verify-v0.29-sidebar-topbar-hide-device-20260618-224500.txt
  PASS; root available, keyguard not showing, launcher focused, Sidebar
  window markers present, live Sidebar APK hash matches v0.29, Sidebar
  launcher query reports No activities found, and v0.27/v0.28 removed packages
  remain absent. The first device verifier report was a verifier-only false
  failure because `cmd package query-activities` returns the text
  "No activities found" for absence; the script now treats that as absent.
visual screenshot:
  hard-rom/inspect/v0.29-sidebar-topbar-hide/screenshot-v0.29-sidebar-topbar-hide-20260618-224507.png
  The old left/right arrows, One Step title, settings gear, and exit/expand
  button are absent; the topbar area remains blank/reserved and Sidebar panels
  remain visible.
status:
  flashed to B slot and live-verified. v0.29 is the current live-proven Sidebar
  topbar-cleanup state on top of v0.28.
```
