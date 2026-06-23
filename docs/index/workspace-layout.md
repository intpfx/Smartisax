# Workspace Layout

This file was split out of the root `README.md` so the project entrypoint stays short.

## Directory Map

```text
docs/
  README.md                   Documentation index
  hard-rom-ota-trust.md        Main project log and evidence trail
  v0.5-debloat-candidates.md   Next debloat candidate list
  research/                    Bootloader, updater, OTA, and exploit notes
  legacy/systemless/           Older root/systemless route notes

tools/
  r2-root.sh                   Root command wrapper for bb12d264
  r2-hardrom-build-super.sh    Exact-current super image builder
  r2-hardrom-build-v0.4-debloat.sh
  r2-hardrom-build-v0.6-settings-noop.sh
  r2-hardrom-build-v0.7-locale-filter.sh
  r2-hardrom-build-v0.8-darkmode-ui.sh
  r2-verify-settingssmartisan-offline-images.sh
  r2-build-settingssmartisan-locale-filter-apk.sh
  r2-build-settingssmartisan-darkmode-ui-apk.sh
  r2-verify-v0.8-darkmode-ui.sh
  r2-build-protips-locale-prune-apk.sh
  r2-build-apk-locale-prune.sh
  r2-verify-tier1a-locale-prune-apks.sh
  r2-locale-prune-coverage-audit.py
  r2-language-source-coupling-audit.py
  r2-language-live-state-audit.sh
  r2-build-framework-res-locale-probe.sh
  r2-arsc-prune-locales.py
  r2-build-smartisanos-framework-res-locale-probe.sh
  r2-hardrom-build-v0.9-protips-locale-prune.sh
  r2-hardrom-build-v0.10-framework-locale-prune.sh
  r2-verify-v0.10-framework-locale-prune.sh
  r2-hardrom-build-v0.12-framework-res-noop.sh
  r2-verify-v0.12-framework-res-noop.sh
  r2-hardrom-build-v0.13-tier1a-locale-prune.sh
  r2-verify-v0.13-tier1a-locale-prune.sh
  r2-sparse-partition-patch.py
  r2-darkmode-source-coupling-audit.py
  r2-darkmode-persistence-audit.py
  r2-build-systemui-certprobe-noop-apk.sh
  r2-verify-systemui-certprobe-noop-apk.sh
  r2-hardrom-build-systemui-certprobe-noop.sh
  r2-verify-systemui-certprobe-noop.sh
  r2-build-native-darkmode-tile-apks.sh
  r2-verify-v0.11-native-darkmode-tile-apks.sh
  r2-hardrom-build-v0.11-native-darkmode.sh
  r2-verify-v0.11-native-darkmode.sh
  r2-clean-v0.4-launcher-shortcuts.sh

apps/
  SmartisaxControls/        Minimal ROM-bundled control app source for
                                dark-mode/QS/permission validation.

hard-rom/
  build/                       Generated system/super images and manifests
  inspect/                     Live-device inspection artifacts
  extracted/                   OTA-extracted partition images
  live-ota-logs/                SmartisanUpdater/OTA trust experiment logs;
                                old noop-ota outputs were cleaned and can be
                                rebuilt with tools/r2-build-noop-ota.sh

reverse/
  smartisan-8.5.3-rom-static/  Static ROM source KB, indexes, and
                                modification-confidence map
  smartisan-8.5.3-core/        Retired early partial reverse cache; cleaned
                                after the full rom-static KB became the source
                                for current graph/source analysis
  SmartisanUpdater-source-legacy/
                                Early flat SmartisanUpdater decompilation output

backups/
  2026-06-17-*                 Recovery-critical root/super metadata; large
                                raw super backup is cold-archived on SSDUSB

stock-ota/
  3901655064_Qrwo2/            Original OTA package/extraction workspace

apks/
  SmartisanUpdater.apk         Local APK artifact moved out of the root

third_party/apatch/
  kpimg-android, kptools-mac   Local APatch artifacts

dist/, updates/, fake-ota-server/
                                Legacy systemless update runtime/artifacts;
                                still referenced by old tools and docs

.agents/skills/
  smartisan-r2-hardrom/        Project-level agent operating guide
```
