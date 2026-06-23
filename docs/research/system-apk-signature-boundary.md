# System APK Signature Boundary

Date: 2026-06-18.

This note records the current boundary for modifying core system APKs such as
`SettingsSmartisan.apk`, `SettingsProvider.apk`, `SmartisanSystemUI.apk`,
`framework-res.apk`, and `framework-smartisanos-res.apk`.

It does not authorize flashing a modified core package. It narrows the signing
question enough to define the next safe gate.

## Source Chain

System partition package scanning can collect certificates without full APK
content verification:

```text
PackageManagerService.scanPackageNewLI()
  scanSystemPartition -> skipVerify=true

PackageManagerService.collectCertificatesLI()
  -> ParsingPackageUtils.getSigningDetails(parsedPackage, skipVerify)

ParsingPackageUtils.getSigningDetails(..., skipVerify=true)
  -> ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)
```

The certs-only path still feeds normal package identity checks. It does not
mean signatures are ignored:

```text
PackageManagerServiceUtils.verifySignatures()
  compares parsed package signing details with the previous package setting.
  for sharedUserId packages, also compares against shared user signing details.

Settings.insertPackageSettingLPw()
  seeds package and shared-user signing details from the parsed package.
```

SELinux policy matching is also certificate-aware:

```text
Policy.getMatchedSeInfo(AndroidPackage pkg)
  rejects a policy entry when the package certificate does not match.
```

## Consequences

Re-signing a shared-UID core package with our own key is not a safe path. The
package manager will see a different certificate, and the package can fail
previous-version, shared-user, signature-permission, or SELinux policy checks.

An unsigned apktool rebuild is also not a replacement artifact. It may rebuild
resources and smali successfully, but it has no readable Smartisan Android
certificate.

There is a narrower route worth testing:

```text
original-cert-preserving system-partition patch
```

For system partition scans, Android may accept an APK whose original certificate
is still readable through the certs-only path. This still needs a live boot
probe before it can become a ROM patch strategy.

## Offline Experiment

Experiment directory for reproducibility notes. Large temporary APK copies were
removed after recording the evidence:

```text
hard-rom/inspect/signature-experiments/
```

Original SettingsSmartisan APK temporary copy:

```text
sha256:
  52eca09083d0101865e3b245b61c205fc20354415e5044c93646f88059a4d424
APK signing block:
  present
cert SHA256:
  99:CB:9A:0E:CE:39:C4:30:1E:22:15:0E:5D:72:38:EE:9B:40:73:04:20:54:C6:0B:AA:FD:68:F3:A7:C5:75:74
cert owner:
  EMAILADDRESS=smartisancm@smartisan.com, CN=Android, OU=Software,
  O=Smartisan, L=Wangjiang, ST=BeiJing, C=CN
jarsigner:
  jar verified
```

Temporary copy modified with a normal `zip` update adding an inert probe file:

```text
sha256:
  1d93dd5bbf3bdd4572da9adc6d478a5e5ba1dedc74782f23f1f335863541bb68
APK signing block:
  absent
cert SHA256 read by keytool:
  99:CB:9A:0E:CE:39:C4:30:1E:22:15:0E:5D:72:38:EE:9B:40:73:04:20:54:C6:0B:AA:FD:68:F3:A7:C5:75:74
jarsigner:
  jar verified
  warning: unsigned entries exist
```

Unsigned apktool rebuild of SettingsSmartisan:

```text
sha256:
  c675d8191f711d5f7f81d3ad01aab65b106365754a304094be4fcb06300e5115
APK signing block:
  absent
cert read by keytool:
  none
jarsigner summary:
  no manifest
```

The normal `zip` update is not a final patching method because it removes the
APK signing block and can introduce unsigned entries. It only proves that the
old v1 certificate remains readable in this experiment. A real patcher should
prefer preserving original metadata where possible and must be validated by
booting a no-op replacement first.

## New Gate

Before a real Settings/SystemUI/framework modification:

```text
1. Build a no-op core-APK replacement variant from the current stable ROM.
2. Keep package name, manifest, dex/resources behavior, file context, mode,
   owner, path, and version unchanged.
3. Ensure the Smartisan Android certificate remains readable with
   tools/r2-apk-signature-boundary-check.sh.
4. Flash only after explicit user confirmation.
5. Verify boot_completed, root, keyguard, launcher, package path, shared UID,
   package signature state, SELinux policy behavior, Settings launch, and
   logcat/package-manager errors.
6. Only if the no-op replacement boots, build a one-behavior patch.
```

Recommended first no-op candidate:

```text
SettingsSmartisan.apk cert-boundary probe
  functional change: none
  reason: it is the natural target for language-list filtering and display
          settings integration, but it is less early-boot than framework-res.
```

For SystemUI work, use a separate no-op gate. Passing SettingsSmartisan does not
prove that `android.uid.systemui` and the `system_ext` package path accept the
same replacement boundary.

## v0.6 Settings No-Op Candidate

Built offline from stable v0.4. Not flashed or live-verified yet.

```text
build script:
  tools/r2-hardrom-build-v0.6-settings-noop.sh

verify script for after flashing:
  tools/r2-verify-v0.6-settings-noop.sh

source baseline:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  sha256=313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5

probe APK:
  hard-rom/build/apk/SettingsSmartisan-certprobe-noop.apk
  sha256=037fa05464a026a5e599c134d3120a42f6300cb7dddc847f9cb2b1d5a7743c3d

signature boundary:
  APK signing block absent
  keytool still reads the Smartisan Android cert
  jarsigner status 0 with unsigned-entry warning

system image:
  hard-rom/build/system-otatrust-v0.6-settings-noop.img
  sha256=9748e6d4b4f04d01461540135de57d8f3c0187b90134fe75793553cb24131bfb

super sparse:
  hard-rom/build/super-otatrust-v0.6-settings-noop-exact-current.sparse.img
  sha256=a06c2e81862c837bef53a4dc2f67c5dea7f0acf78dc7fbbecb6ae4ece26483db

inserted path:
  /system/priv-app/SettingsSmartisan/SettingsSmartisan.apk

offline verification:
  shared_blocks-safe held-stock-inode replacement was used.
  dumped APK hash from system image matched probe APK hash.
  ZIP integrity passed.
  e2fsck -fy and e2fsck -fn passed.
  final sparse super's system_b slice matched the system image hash.
  report=hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-061432.txt
```

If this boots, the next real behavior patch should be the narrow language
filter in `LocalePickerFragment.constructAdapter()`.

## SmartisanSystemUI No-Op Gate

Built and verified offline only. Not flashed or live-verified yet.

```text
APK build script:
  tools/r2-build-systemui-certprobe-noop-apk.sh

APK verify script:
  tools/r2-verify-systemui-certprobe-noop-apk.sh

ROM build script:
  tools/r2-hardrom-build-systemui-certprobe-noop.sh

ROM offline verify script:
  tools/r2-verify-systemui-certprobe-noop.sh --offline-image

stock APK:
  reverse/smartisan-8.5.3-rom-static/raw/system_ext/priv-app/SmartisanSystemUI/SmartisanSystemUI.apk
  sha256=3920c9ecce431f45633ac7b732550e4e9adc61cc05bcd54083e0b0437fa4f128

probe APK:
  hard-rom/build/apk/SmartisanSystemUI-certprobe-noop.apk
  sha256=654ff82819cf6a7bf42a3463cb9559196f871234800ad74ee0030963ce487d69

functional change:
  none; all 6137 ZIP/JAR entries are byte-identical to stock.
  The only file-level byte change is APK v2 signing block magic offset 56852464:
    APK Sig Block 42 -> XPK Sig Block 42

APK offline verification:
  report=hard-rom/inspect/systemui-certprobe-noop/verify-systemui-certprobe-noop-apk-20260618-055408.txt
  result=PASS
  changed_bytes=1
  stock_entries_verified=6137

ROM candidate:
  hard-rom/build/super-otatrust-systemui-certprobe-noop-exact-current.sparse.img
  sha256=836e8e7d2377580dc6237b617471084710d6b90c649f764b5f09681fd459cc60
  hard-rom/build/system_ext-otatrust-systemui-certprobe-noop.img
  sha256=9ffd495aa4d6d26df3107b66fcbfc01a3f5e8487aece6d9c9a85af2bd60f851d

ROM offline verification:
  report=hard-rom/inspect/systemui-certprobe-noop/verify-systemui-certprobe-noop-offline-20260618-055615.txt
  result=PASS
  final sparse system_ext_b slice matches the system_ext image
  SmartisanSystemUI.apk inside the image matches the probe APK

signature boundary:
  APK signing block magic absent after one-byte magic patch
  keytool still reads the Smartisan Android cert
  jarsigner status 0
```

Important system_ext constraint:

```text
system_ext_b features: shared_blocks
system_ext_b free blocks: 0
```

The earlier asset-add APK probe is superseded for ROM use. It proved a
certificate-readable v1/JAR boundary, but it cannot be inserted safely into
system_ext_b because inode replacement needs free blocks. The valid SystemUI
ROM no-op gate is the same-size one-byte in-place patch above.

This is the correct precursor to any live SmartisanSystemUI behavior patch such
as a native `toggleDarkMode` tile. The next step is live verification of this
no-op ROM after explicit user confirmation.

## v0.7 Settings Locale-Filter Candidate

Built offline from stable v0.4. Not flashed or live-verified yet.

```text
build scripts:
  tools/r2-build-settingssmartisan-locale-filter-apk.sh
  tools/r2-hardrom-build-v0.7-locale-filter.sh

verify script for after flashing:
  tools/r2-verify-v0.7-locale-filter.sh

source baseline:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  sha256=313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5

patched APK:
  hard-rom/build/apk/SettingsSmartisan-locale-filter-ja-ko.apk
  sha256=352794d2413d269799afac88dc3bead17cb587fefd2513378d99618461b10d9e

behavior patch:
  SettingsSmartisan LocalePickerFragment.constructAdapter()
  skip ja_JP and ko_KR before LocaleInfo row creation

signature boundary:
  APK signing block absent
  keytool_status=1
  jarsigner_status=1
  error: SHA-256 digest error for classes.dex

system image:
  hard-rom/build/system-otatrust-v0.7-locale-filter.img
  sha256=558062c9de8fd20fb887b725f842aa8eabad5e7db84e6098c74d3e1f09d3673f

super sparse:
  hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img
  sha256=d3dfef95d52dd1a26b399b2ef8a375c2645edfb08de46e4431e68cb5f823f9e4

inserted path:
  /system/priv-app/SettingsSmartisan/SettingsSmartisan.apk

offline verification:
  shared_blocks-safe held-stock-inode replacement was used.
  dumped APK hash from system image matched patched APK hash.
  ZIP integrity passed.
  e2fsck -fy and e2fsck -fn passed.
  final sparse super's system_b slice matched the system image hash.
  report=hard-rom/inspect/settingssmartisan-offline/verify-settingssmartisan-offline-20260618-061432.txt
```

This is the first real SettingsSmartisan behavior candidate, but it is a higher
risk artifact than v0.6. The v0.6 no-op can still be read by ordinary keytool
and jarsigner; v0.7 cannot because it replaces an already-signed `classes.dex`
entry. The only reason v0.7 remains worth testing later is the source-confirmed
system-partition path:

```text
skipVerify=true
  -> ApkSignatureVerifier.unsafeGetCertsWithoutVerification(...)
  -> verifyFull=false
  -> verifyV1Signature() reads AndroidManifest.xml certificates and skips
     per-entry verification.
```

Therefore v0.7 is not flash-authorized until v0.6 boots and verifies cleanly.

## Impact On Language Work

For the user's current language-pruning goal, the lowest practical hard-ROM
path is no longer direct framework resource repacking. It is:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  filter out ja_JP and ko_KR before creating LocaleInfo rows
```

This changes the visible Smartisan language picker while avoiding a first
framework-res replacement. Full removal of Japanese/Korean resources from the
whole ROM remains a later broad-prune project touching many APKs and resource
packages.
