# Smartisan R2 (DT2002C) Bootloader Diagnosis

## Source
`docs/research/device-info.txt` — getprop dump from the device running SmartisanOS 8.5.3 (Android 11)

## Bootloader Lock State

| Property                        | Value      | Meaning                                       |
|--------------------------------|------------|-----------------------------------------------|
| ro.boot.flash.locked           | 0          | UNLOCKED (0=unlocked, 1=locked)               |
| ro.boot.vbmeta.device_state    | unlocked   | UNLOCKED                                      |
| ro.boot.verifiedbootstate      | orange     | ORANGE = bootloader UNLOCKED                  |
| ro.oem_unlock_supported        | 1          | Device supports OEM unlocking                 |
| sys.oem_unlock_allowed         | 0          | Toggle OFF in Developer Options (normal)      |
| ro.build.keys / ro.build.tags  | dev-keys   | Development build (common after unlock)       |

**Verdict: Bootloader IS unlocked.** All three independent indicators agree.

## Fastboot Availability on Nut R2

- Platform: Snapdragon 865 (kona) — standard Qualcomm fastboot
- A/B slots: yes (current slot `_b`)
- Access: `adb reboot bootloader` or Volume Down + Power
- Since BL is already unlocked: `fastboot flash`, `fastboot boot`, `fastboot reboot` should work
- Note: AVB 1.1 enforces verified boot — may need `--disable-verity --disable-verification` when flashing modified partitions

## Notes

- `sys.oem_unlock_allowed=0` is NOT a re-lock signal; it's the user's Developer Options toggle preference
- `ro.boot.veritymode=enforcing` — dm-verity is active
- Device uses file-based encryption with metadata encryption
