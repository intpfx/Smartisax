# Wallet And HandShaker Debloat Audit

Date: 2026-06-18

Baseline: live-verified `v0.27-cloud-service-debloat` on B slot.

This is a read-only pre-delete audit for:

```text
Wallet:
  package: com.smartisanos.wallet
  stock ROM path: /system/priv-app/WalletSmartisan/WalletSmartisan.apk
  live path: /data/app/.../com.smartisanos.wallet.../base.apk
  live state: SYSTEM + UPDATED_SYSTEM_APP + PRIVILEGED

HandShaker:
  package: com.smartisanos.smartfolder.aoa
  stock/live ROM path: /system/app/HandShaker/HandShaker.apk
```

No ROM image was built and no `/data` mutation was performed for this audit.

## Live Device State

The current device is booted and connected over USB:

```text
slot: _b
sys.boot_completed: 1
root: uid=0(root), SELinux Enforcing
sys.usb.config: mtp,diag,diag_mdm,mass_storage,adb
sys.usb.state: mtp,diag,diag_mdm,mass_storage,adb
```

Current live package paths:

```text
com.smartisanos.wallet:
  /data/app/.../com.smartisanos.wallet.../base.apk
  hidden stock system package:
    /system/priv-app/WalletSmartisan
    versionCode=35, versionName=8.0.2
  active updated-system package:
    versionCode=37, versionName=8.0.4

com.smartisanos.smartfolder.aoa:
  /system/app/HandShaker/HandShaker.apk
  versionCode=201, versionName=1.2.0
```

The old `com.smartisanos.handinhand` package is a different package from
HandShaker and was already removed by the earlier hard-debloat line.

## Static Preflight Result

`tools/r2-rom-mod-preflight.py` reports both package deletes as ORANGE:

```text
com.smartisanos.wallet:
  ORANGE because it is a priv-app and is referenced by hiddenapi sysconfig.
  YELLOW because it declares providers, exported components, and launcher/view
  intent filters.

com.smartisanos.smartfolder.aoa:
  ORANGE because it is referenced by hiddenapi sysconfig.
  YELLOW because it declares one provider, one exported service, and launcher
  intent filters.
```

Both packages are listed in:

```text
/system/etc/sysconfig/hiddenapi-package-whitelist.xml
```

If hard-deleted from ROM, their hiddenapi whitelist entries should be removed in
the same image, matching the v0.27 cloud-service cleanup pattern.

## HandShaker Connection Boundary

HandShaker is not the owner of basic phone-to-computer USB connectivity.

Evidence:

```text
com.android.mtp:
  /system/priv-app/MtpService/MtpService.apk
  sharedUser: android.media
  requested permissions include ACCESS_MTP and MANAGE_USB
  owns:
    com.android.mtp.MtpService
    com.android.mtp.MtpDocumentsProvider
    com.android.mtp.MtpReceiver
    com.android.mtp.UsbIntentReceiver
    com.android.mtp.ReceiverActivity
```

Live `dumpsys usb` shows the current basic USB state is managed by the system
USB manager:

```text
current_functions: ADB, MTP, 0x100, 0x200, 0x2000
current_functions_applied: true
connected: true
configured: true
kernel_state: CONFIGURED
```

HandShaker instead registers a Smartisan-specific Android Open Accessory
surface:

```xml
<uses-feature android:name="android.hardware.usb.accessory" android:required="true"/>

<activity android:name="com.smartisanos.smartfolder.aoa.MainActivity">
  <intent-filter>
    <action android:name="android.hardware.usb.action.USB_ACCESSORY_ATTACHED"/>
  </intent-filter>
  <meta-data
    android:name="android.hardware.usb.action.USB_ACCESSORY_ATTACHED"
    android:resource="@xml/accessory_filter"/>
</activity>
```

The accessory filter is:

```xml
<usb-accessory manufacturer="Smartisan" model="HandShaker" version="1"/>
```

`ConnectionManagerService` opens a private HandShaker connection only after
`MainActivity` receives either a USB accessory parcelable or an `ADB_PORT`
extra. The service is not currently running in the normal booted/connected
state.

System references to HandShaker are limited and feature-scoped:

```text
android.app.SmtPCUtils.HANDSHAKER_DISPLAY_PKG = com.smartisanos.smartfolder.aoa
SmtPCUtils includes it in PC-mode/display package checks.
SystemUI recents keeps it in a not-kill whitelist.
Settings lists it among openable system apps and battery-optimization special
cases.
USB accessory resolver reads its accessory activity like any other
USB_ACCESSORY_ATTACHED handler.
```

Conclusion: deleting HandShaker should not remove ADB, MTP, fastboot, normal
charging, or Android USB gadget enumeration. It will remove Smartisan's
HandShaker/SmartFolder AOA desktop-assistant experience and any PC-mode display
special handling tied to package `com.smartisanos.smartfolder.aoa`.

## Wallet Boundary

Wallet is a larger optional feature package, not a boot-critical service.

Wallet declares and exposes:

```text
launcher activity:
  com.smartisanos.wallet.WalletMainActivity

payment/lockscreen activity:
  com.smartisanos.wallet.card.CardPayActivity
  alias: com.smartisanos.wallet.WalletPayActivity

providers:
  com.smartisanos.wallet.db
  com.smartisanos.wallet.centerprovider
  com.smartisanos.wallet.apm

NFC/off-host service:
  com.smartisanos.wallet.service.PaymentServiceWallet

declared signature/privileged permissions:
  com.smartisanos.permission.WALLETCENTER
  com.smartisanos.permission.WALLET_WRITE_CARDS
```

Framework/Settings/Keyguard references are feature-scoped:

```text
PhoneWindowManagerSMT:
  launches com.smartisanos.wallet.action.lockscreen_home for the wallet
  shortcut, inside try/catch.
  tracks com.smartisanos.wallet.ACTION_WALLET_IN_FRONT for home-key handling
  while WalletPayActivity is open.

KeyguardSmartisan:
  has wallet-specific occluded-app and fingerprint-wallet logic.

SettingsSmartisan:
  SettingsFeature.isWalletFeatureEnabled(context) checks whether
  com.smartisanos.wallet is installed.
  Wallet-related settings rows and reset messages are gated by that package
  presence where checked.
```

The current live settings values are benign:

```text
global lockscreen_home_trigger_type: null
global use_fingerprint_in_wallet: 0
```

Conclusion: deleting Wallet should not break normal boot, launcher, telephony,
ADB, or MTP. It will remove Smartisan Wallet, NFC/bank/transit/access-card
flows, wallet lockscreen/home shortcut behavior, and wallet-related fingerprint
payment options. Because it is an updated-system privileged app, ROM deletion
must be paired with a separate post-boot cleanup plan for the active
`/data/app` update, subject to explicit user approval.

## Recommended v0.28 Route

Build a small isolated hard-debloat variant on top of `v0.27-cloud-service-debloat`:

```text
variant:
  v0.28-wallet-handshaker-debloat

remove ROM paths:
  /system/priv-app/WalletSmartisan
  /system/app/HandShaker

remove sysconfig rows:
  hidden-api-whitelisted-app package="com.smartisanos.wallet"
  hidden-api-whitelisted-app package="com.smartisanos.smartfolder.aoa"

retain:
  /system/priv-app/MtpService
  /system/apex/com.android.mediaprovider
  /system/priv-app/MediaProviderLegacy
  USB init/vendor HAL files
  framework/services USB code
```

After flash and boot, request separate approval before cleaning `/data`:

```text
com.smartisanos.wallet updated-system app:
  uninstall user/update residue after ROM base is absent

com.smartisanos.smartfolder.aoa:
  check for package data/cache residue; clean only after approval if needed
```

Read-only post-boot verification should check:

```text
boot_completed=1, slot=_b, root available
keyguard not showing, launcher focused
com.smartisanos.wallet absent
com.smartisanos.smartfolder.aoa absent
com.android.mtp present
USB state still includes adb and mtp
dumpsys usb configured=true
adb device still visible
core packages present:
  com.android.settings
  com.smartisanos.launcher
  com.android.systemui
  com.smartisanos.keyguard
  com.android.mtp
  com.android.providers.media.module / com.android.providers.media
  com.android.phone
```

Risk rating:

```text
Wallet: ORANGE functional-loss risk; low boot risk.
HandShaker: ORANGE feature-loss risk for Smartisan desktop-assistant/AOA/PC-mode
            display surfaces; low risk for ordinary ADB/MTP/charging.
Combined v0.28: acceptable as a small isolated hard-ROM experiment after
                ordinary rollback/preflight gates and explicit flash approval.
```
