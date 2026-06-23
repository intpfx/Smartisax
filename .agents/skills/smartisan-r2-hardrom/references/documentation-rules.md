# Documentation Rules

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Documentation Rules

Update `docs/hard-rom-ota-trust.md` after every meaningful experiment. Include:

```text
variant name
source baseline
exact commands
image paths and hashes
fastboot output summary
post-boot adb/root/slot/UI/package verification
rollback path
```

Keep `README.md` human-oriented and `AGENTS.md` short. Put recurring operational
knowledge here, not in the root agent entrypoint.

Current documentation organization:

```text
docs/hard-rom-ota-trust.md          primary evidence log
docs/v0.5-debloat-candidates.md     current debloat candidate list
docs/research/                      bootloader/updater/OTA/exploit notes
docs/legacy/systemless/             older root/systemless route notes
apks/                               small APK artifacts
third_party/apatch/                 local APatch binaries
reverse/SmartisanUpdater-source-legacy/
                                    early flat SmartisanUpdater source dump
```
