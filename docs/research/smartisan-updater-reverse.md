# SmartisanUpdater Reverse Notes

Device context: Nut R2 / `darwin`, Smartisan OS 8.5.3, Android 11, A/B update path.

Target APK:

- Package: `com.smartisanos.updater`
- Device path: `/system/priv-app/SmartisanUpdater/SmartisanUpdater.apk`
- Decompiled source: `reverse/SmartisanUpdater-jadx`
- Device APK SHA-256 matched local `apks/SmartisanUpdater.apk`: `abe3d802e79b29b2e69337cfe92a706f54eb7bdc5b4d2997fde1031e00084c24`

## Executive Conclusion

SmartisanUpdater can be made to talk to our own OTA server for update checks and download metadata, but it is not a practical channel for our custom systemless update packages.

The hard barrier is not the JSON protocol or MD5 check. The hard barrier is the final installer:

- On this Android 11 A/B device, downloaded zips are handed to `update_engine.applyPayload(...)`.
- `FactoryUpdate` from USB also calls `update_engine.applyPayload(...)`.
- The protected `smartisan_update2` broadcast path calls `RecoverySystem.installPackage(...)`, which is the recovery package path.

So a self-made package can pass SmartisanUpdater's network protocol and MD5 layer, but it still has to satisfy Android/Smartisan payload or recovery signature verification at install time. For our "custom system update" goal, the APatch/root systemless framework remains the right primary route.

## Exported Surface

Manifest highlights:

- `UpdatesCheck`
  - Main update UI.
  - Has intent filter for `android.intent.action.MAIN` and `com.android.settings.SHORTCUT`.
  - Accepts a `url` intent extra and stores it in static `Z.f111a`.
- `FactoryUpdate`
  - Explicitly exported.
  - Scans USB storage for `/update/payload.bin`, `/update/payload_properties.txt`, and `/update/META-INF`.
  - Calls `UpdateEngine.applyPayload(...)`.
- `UpdateProxyService`
  - Exported, but protected by `com.smartisanos.updater.RECEIVE`.
- `StartUpdateReceiver`
  - Action: `smartisan_update`.
  - Only opens `NotifyGMS` when `PACKAGE_PATH` contains `smartisan`.
- `StartUpdateReceiverEx`
  - Action: `smartisan_update2`.
  - Protected by `com.smartisanos.updater.RECEIVE`.
  - Calls `RecoverySystem.installPackage(...)` through `c0`/`b0`.

Code references:

- `reverse/SmartisanUpdater-jadx/resources/AndroidManifest.xml:13`
- `reverse/SmartisanUpdater-jadx/resources/AndroidManifest.xml:71`
- `reverse/SmartisanUpdater-jadx/resources/AndroidManifest.xml:96`
- `reverse/SmartisanUpdater-jadx/resources/AndroidManifest.xml:142`
- `reverse/SmartisanUpdater-jadx/resources/AndroidManifest.xml:148`
- `reverse/SmartisanUpdater-jadx/resources/AndroidManifest.xml:183`

## OTA Server Protocol

Default server:

```text
https://ota2.smartisan.com/update.php
```

The URL can be overridden by starting `UpdatesCheck` with a `url` extra:

```bash
adb shell am force-stop com.smartisanos.updater
adb shell am start -n com.smartisanos.updater/.UpdatesCheck \
  --es url http://127.0.0.1:18080/update.php \
  --ez check_for_update true
```

`UpdatesCheck.onCreate()` resets `Z.f111a`, then sets it from `getIntent().getStringExtra("url")`. `UpdateCheckService` uses `Z.f111a` instead of the resource URL when it is non-empty.

`UpdateCheckService` chooses HTTPS only when the URL string contains `https`; plain `http://` uses `HttpURLConnection`, which makes local mock testing easy.

Request body:

```json
{
  "method": "get_all_builds",
  "params": {
    "device": "darwin_user_sek",
    "version": "8.5.3-202207181710-user-drw",
    "buildtime": "1658135499",
    "deviceid": "<IMEI redacted>",
    "flag": "0",
    "language": "zh_CN"
  }
}
```

Response shape:

```json
{
  "result": [
    {
      "filename": "SmartisanOS_X.X.X_darwin_update.zip",
      "timestamp": "1718534400",
      "url": "http://host/package.zip",
      "md5sum": "hex_md5",
      "type": "stable",
      "size": "123456789",
      "changes": "changelog",
      "changesEx": "",
      "changelogUrl": "",
      "newfunction": "",
      "other": "3"
    }
  ]
}
```

`flag` is set to `1` when the updater thinks the device is rooted, an update has started, or `need_full_ota_package` is set. Otherwise it is `0`.

Code references:

- `reverse/SmartisanUpdater-jadx/resources/res/values/strings.xml:28`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/UpdatesCheck.java:87`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateCheckService.java:252`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateCheckService.java:256`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateCheckService.java:261`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateCheckService.java:465`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateCheckService.java:501`

## Download And MD5 Layer

Download behavior:

- Uses Android `DownloadManager`.
- Downloads to `/sdcard/smartisan/update/<filename>.partial`.
- Renames to `/sdcard/smartisan/update/<filename>` after download completes.
- Stores expected MD5 in `SharedPreferences` key `download_md5`.
- Computes MD5 over the final file and compares it case-insensitively.

This layer is easy to satisfy with a mock OTA server because the MD5 is fully controlled by the JSON response.

Code references:

- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/v0/f.java:46`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/v0/f.java:61`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/v0/f.java:87`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/MD5CheckService.java:150`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/MD5CheckService.java:190`

## A/B Install Path

This R2 is Android 11, so `l.x()` returns true for the A/B update path. After MD5 succeeds, `MD5CheckService` starts `UpdateProgressService` with the downloaded filename.

`UpdateProgressService` then:

- Verifies the zip exists in `/sdcard/smartisan/update`.
- Reads `payload_properties.txt` from the zip.
- Locates `payload.bin` inside the zip.
- Calls `UpdateEngine.applyPayload(...)` with an `AssetFileDescriptor`.

That means the payload must be a valid Android A/B OTA payload accepted by `update_engine`, including its metadata/signature requirements. A random zip, or our systemless package zip, will not become an installable system OTA through this path.

Failure behavior:

- On update failure, it sets `need_full_ota_package=true`.
- It sets `ab_update_status=1`.
- The UI asks the user to redownload.

Code references:

- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/v0/l.java:380`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/MD5CheckService.java:45`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateProgressService.java:188`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/UpdateProgressService.java:228`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/f.java:34`
- `reverse/SmartisanUpdater-jadx/sources/b/a/a/a/a/a.java:11`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/service/i.java:38`

## FactoryUpdate Path

`FactoryUpdate` is an exported activity intended for factory/USB updates.

It searches mounted USB storage for:

```text
/update/payload.bin
/update/payload_properties.txt
/update/META-INF
```

When all required files exist, it calls:

```java
UpdateEngine.applyPayload(file:///.../update/payload.bin, 0L, 0L, properties)
```

So this path is not a shortcut around payload verification. It is the same update_engine trust boundary, only with payload files unpacked on USB instead of inside a zip.

Code references:

- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/FactoryUpdate.java:28`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/FactoryUpdate.java:48`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/FactoryUpdate.java:78`
- `reverse/SmartisanUpdater-jadx/sources/com/smartisanos/updater/FactoryUpdate.java:105`

## Dynamic Verification

Safe mock server was updated to default to `no-update`:

```bash
python3 fake-ota-server/server.py --host 127.0.0.1 --port 18080 --mode no-update
adb reverse tcp:18080 tcp:18080
adb shell am force-stop com.smartisanos.updater
adb shell am start -n com.smartisanos.updater/.UpdatesCheck \
  --es url http://127.0.0.1:18080/update.php \
  --ez check_for_update true
adb reverse --remove tcp:18080
```

Observed result:

- Device sent `POST /update.php`.
- Request method was `get_all_builds`.
- Request device was `darwin_user_sek`.
- Request version was `8.5.3-202207181710-user-drw`.
- Mock response was `{"result": []}`.
- Logcat reported a successful check with `0 updates`.
- No package download or install attempt was triggered.

## Practical Decision

Do not route our real custom updates through SmartisanUpdater.

Use SmartisanUpdater only for:

- Understanding Smartisan's official OTA protocol.
- Testing a mirror of an official signed OTA package.
- UI/protocol experiments with safe `no-update` responses.

Keep our actual custom update path on the APatch/root systemless framework:

- It already installs and lists packages through `/data/adb/smartisax`.
- It already has boot-completed policy repair through APatch modules.
- It avoids Android OTA payload signing and recovery signing entirely.

If we ever want a user-facing update UI, the better route is to build our own small updater app or CLI that calls our root framework, not to coerce SmartisanUpdater into installing non-Smartisan payloads.

## Safe Mock Server Modes

Safe no-update mode:

```bash
python3 fake-ota-server/server.py --host 127.0.0.1 --port 18080 --mode no-update
```

Fake-update mode:

```bash
python3 fake-ota-server/server.py --host 127.0.0.1 --port 18080 --mode fake-update
```

`fake-update` is only for UI/download behavior research. It may cause SmartisanUpdater to try the A/B install flow and mark `need_full_ota_package=true` after failure. Do not use it casually on the daily device.
