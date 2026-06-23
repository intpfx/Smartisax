# ROM Archive

This file records large ROM images that were moved out of the Mac working tree.
Keep small manifests, hashes, and lpdump text files in the project; keep cold
large images on SSDUSB.

## Current Local Images

```text
current local direct flash targets:

v0.4 cold rollback:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  sha256=313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5
  purpose=fast local rollback

v0.39 previous live-verified stable target:
  hard-rom/build/super-otatrust-v0.39-sidebar-font-ocr-deleted.sparse.img
  sha256=a3672c3d32e7acedaf83051b289df86c729e91eb3e24f4e958b3fa4b42560f79
  purpose=live-verified v0.37b plus Sidebar/One Step font OCR code deletion; One Step manual corner-swipe panel, Big Bang/TextBoom, M150 WebView live-state, BrowserChrome rendering, and Smartisax verified

v0.40 previous live-verified TextBoom no-op adapter:
  hard-rom/build/super-otatrust-v0.40-textboom-ppocr-noop-adapter.sparse.img
  sha256=e1dd20fb38d7e8e49b7e111d8a92c59e1142a1bd6fe992cb1fb752a51e54ab7b
  purpose=v0.39 plus TextBoom LocalPpOcrApi no-op adapter gate; flashed and live-verified

v0.41 previous flashed TextBoom runtime ABI-failure candidate:
  hard-rom/build/super-otatrust-v0.41-textboom-ppocr-runtime-adapter.sparse.img
  sha256=f65fd372c8ac4642d8ed0ead7abe8535f904f740a6020b19019590ef3eacbce4
  purpose=v0.40 line with PP-OCR runtime adapter; boot/package and BOOM_TEXT pass, but image OCR needs v0.41.1 arm32 runtime libs

v0.41.1 current live-verified TextBoom PP-OCR runtime target:
  hard-rom/build/super-otatrust-v0.41.1-textboom-ppocr-runtime-arm32-libs.sparse.img
  sha256=1517f5acc76554b8537938daf99938ad6d17916088c4e8e73c787fc1007eee58
  purpose=v0.41 ABI fix that keeps the TextBoom APK stable, adds 32-bit ORT/OpenCV runtime libs for app_process32, and passes first live BOOM_IMAGE PP-OCR result smoke

current retained partition-image inputs:
  hard-rom/build/system-otatrust-v0.41.1-textboom-ppocr-runtime-arm32-libs.img
  hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img

superseded Mac-local sparse images removed during the v0.37a cleanup:
  v0.34-system-b-ext4-grow-fec
  v0.35-webview-m150-system-provider
  v0.35.1-webview-m150-browserchrome-deodex
  earlier v0.29, v0.31, v0.32, and v0.33 targets

superseded Mac-local images removed during the v0.40 cleanup:
  hard-rom/build/super-otatrust-v0.38-sidebar-font-ocr-disabled.sparse.img
  hard-rom/build/system-otatrust-v0.38-sidebar-font-ocr-disabled.img

superseded Mac-local images and work dirs removed during the v0.41.1 prep cleanup:
  hard-rom/work/v0.41-textboom-ppocr-runtime-adapter
  hard-rom/work/textboom-ppocr-runtime-adapter-apk
  hard-rom/work/v0.37a-textboom-live-system-base
  hard-rom/build/system-otatrust-v0.40-textboom-ppocr-noop-adapter.img
  hard-rom/build/system-otatrust-v0.39-sidebar-font-ocr-deleted.img
  hard-rom/build/super-otatrust-v0.37b-textboom-live-system-libs-deodex.sparse.img
  hard-rom/build/system-otatrust-v0.37b-textboom-live-system-libs-deodex.img
free-space result:
  about 15 GiB -> about 32 GiB available on /System/Volumes/Data

superseded Mac-local images and work dirs removed after v0.41.1 build/preflight:
  hard-rom/work/v0.41.1-textboom-ppocr-runtime-arm32-libs
  hard-rom/build/system-otatrust-v0.41-textboom-ppocr-runtime-adapter.img
free-space result:
  about 18 GiB -> about 23 GiB available on /System/Volumes/Data

retired local verifier partition intermediates:
  hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img
  hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
  hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
purpose:
  Removed from the Mac working tree after v0.17-all was built and verified.
  The v0.17-all sparse plus verifier reports remain local; rebuild these
  partition images only if slice equality must be reverified.
```

## SSDUSB Cold Archive

Archive root:

```text
/Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/
```

Archived large images:

```text
v0.2 no-appstore cold rollback:
  /Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/hard-rom/build/super-otatrust-v0.2-no-appstore-exact-current.sparse.img
sha256:
  63bbc29f53d06adc5450cab2628430b67bd8feaf5ab8a578d1180fa60c2fb485

pre-hard-ROM raw super backup:
  /Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img
sha256:
  f0e7d91c422e5467b0c628fea9a3824c8187b6079967cfa5171c17b9c92ca03a
```

## Restore Commands

Restore the v0.2 cold rollback image to its original project path:

```bash
rsync -rt --modify-window=2 \
  /Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/hard-rom/build/super-otatrust-v0.2-no-appstore-exact-current.sparse.img \
  hard-rom/build/

shasum -a 256 hard-rom/build/super-otatrust-v0.2-no-appstore-exact-current.sparse.img
```

Restore the pre-hard-ROM raw super backup:

```bash
rsync -rt --modify-window=2 \
  /Volumes/SSDUSB/Smartisax/archive/2026-06-18-rom-cold-backups/backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img \
  backups/2026-06-17-before-hardrom-super/

shasum -a 256 backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img
```

## Cleanup Record

On 2026-06-18, these Mac-local large files were removed after SSDUSB copy and
SHA256 verification:

```text
hard-rom/build/super-otatrust-v0.2-no-appstore-exact-current.sparse.img
backups/2026-06-17-before-hardrom-super/super-current-before-hardrom.img
```

Earlier on the same cleanup pass, raw/intermediate images were removed:

```text
hard-rom/build/super-otatrust-v0.4-debloat-exact-current.img
hard-rom/build/system-otatrust-v0.2-no-appstore.img
hard-rom/build/system-otatrust-v0.4-debloat.img
```

On 2026-06-18 after the v0.17-all build, Mac-local disk pressure was reduced
again. The v0.4 rollback sparse and v0.17-all next-test sparse were kept local.
These older unflashed sparse candidates were removed from the Mac working tree
and can be rebuilt from scripts/reports if needed:

```text
hard-rom/build/super-otatrust-systemui-certprobe-noop-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.5-control-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.6-settings-noop-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.7-locale-filter-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.8-darkmode-ui-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.17a-system-apk-only-locale-prune-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.17b-product-system_ext-apk-only-locale-prune-exact-current.sparse.img
```

On 2026-06-18, a follow-up local cleanup retired the v0.17a/v0.17b verifier
partition intermediates and the small APK-locale-prune work directory. The
v0.4 rollback sparse and v0.17-all next-test sparse remain local.

```text
hard-rom/build/system-otatrust-v0.17a-system-apk-only-locale-prune.img
hard-rom/build/product-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
hard-rom/build/system_ext-otatrust-v0.17b-product-system_ext-apk-only-locale-prune.img
hard-rom/work/apk-locale-prune/
```

Later on 2026-06-18, another Mac-local cleanup removed reproducible temporary
analysis/output directories while keeping the v0.4 rollback sparse, v0.17-all
next-test sparse, stock OTA package, OTA-extracted partition images, verifier
text reports, APK evidence, and the current `rom-static` source KB local.

```text
hard-rom/inspect/*/offline-*
hard-rom/inspect/*/offline-image-*
hard-rom/inspect/*/offline-system-image-*
hard-rom/inspect/*/smali-evidence-*
hard-rom/inspect/recovery-unpack/
hard-rom/noop-ota/
reverse/apkextractor/
reverse/smartisan-8.5.3-core/
third_party/lpunpack_and_lpmake_cmake/build/
apps/SmartisaxControls/build/
```

Later on 2026-06-18, after the v0.20a APK-only probe, another safe local
cleanup removed regenerated work/cache data while preserving the two direct
flash targets, the OTA zip, OTA-extracted partition images, APK evidence,
verifier reports, decoded source KB, and the retained graph JSON files.
SSDUSB was not mounted, so no large archive migration was attempted.

```text
hard-rom/work/apk-locale-prune/
reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graph-input/
reverse/smartisan-8.5.3-rom-static/graph-corpus/feature-control/graph-input/
reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/graphify-out/cache/
reverse/smartisan-8.5.3-rom-static/graph-corpus/feature-control/graphify-out/cache/
*.tmp
*.pyc
.DS_Store
__pycache__/
```

Post-cleanup verification kept both local direct flash images intact:

```text
313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
942da9469ccf9a24ff390912f26d76673415d2a500482d060a89c11847faf819  hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img
```

On 2026-06-19, after the v0.29 live PASS and Quark no-op APK offline work,
Mac-local free space was below the project cleanup threshold. SSDUSB was not
mounted, so no archive migration was attempted. These superseded sparse images
were removed from the Mac working tree:

```text
hard-rom/build/super-otatrust-systemui-certprobe-noop-on-v0.24-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.17-all-apk-only-locale-prune-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.25-settings-noop-on-v0.24-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img
```

Post-cleanup verification kept only the current live image and the fast rollback
image local:

```text
313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
```

On 2026-06-20, after the v0.35 WebView M150 candidate was built and verified
offline, free space dropped below the 20 GiB cleanup threshold. The
regenerable v0.34 extraction work directory was removed, while v0.34 stable
sparse, v0.35 candidate images, manifests, and verifier evidence stayed local.

```text
removed:
  hard-rom/work/v0.34-system-b-ext4-grow-fec/
kept:
  hard-rom/build/super-otatrust-v0.34-system-b-ext4-grow-fec.sparse.img
  hard-rom/build/super-otatrust-v0.35-webview-m150-system-provider.sparse.img
  hard-rom/build/system-otatrust-v0.35-webview-m150-system-provider.img
  hard-rom/build/product-otatrust-v0.35-webview-m150-system-provider.img
free-space result:
  about 15 GiB -> about 28 GiB available on /System/Volumes/Data
```

On 2026-06-20, after v0.35.1 was built and manually verified offline, temporary
retained partition extracts and APK dump copies were removed. Superseded local
sparse images v0.29, v0.31, v0.32, and v0.33 were also removed because free
space again dropped below the 20 GiB threshold.

```text
removed:
  hard-rom/work/v0.35.1-webview-m150-browserchrome-deodex/source-v035-retained-slot1
  hard-rom/work/v0.35.1-webview-m150-browserchrome-deodex/manual-verify
  hard-rom/work/v0.35.1-webview-m150-browserchrome-deodex/*.apk
  hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img
  hard-rom/build/super-otatrust-v0.31-webview-stock-near-noop-exact-current.sparse.img
  hard-rom/build/super-otatrust-v0.32-browserchrome-stock-near-noop-exact-current.sparse.img
  hard-rom/build/super-otatrust-v0.33-system-b-grow-noop.sparse.img
kept:
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  hard-rom/build/super-otatrust-v0.34-system-b-ext4-grow-fec.sparse.img
  hard-rom/build/super-otatrust-v0.35-webview-m150-system-provider.sparse.img
  hard-rom/build/super-otatrust-v0.35.1-webview-m150-browserchrome-deodex.sparse.img
free-space result:
  about 14 GiB -> about 39 GiB available on /System/Volumes/Data
```

On 2026-06-20, after the v0.38 Sidebar font OCR disabled candidate was built
and verified offline, free space again dropped below the 20 GiB threshold. The
latest v0.38 candidate, current stable v0.37b rollback, and v0.4 cold rollback
were kept. Superseded sparse/system/product intermediates were removed.

```text
removed:
  hard-rom/build/super-otatrust-v0.37a-textboom-live-system-base.sparse.img
  hard-rom/build/super-otatrust-v0.36.1-smartisax-shell-debloat-arsc-align.sparse.img
  hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img
  hard-rom/build/system-otatrust-v0.37a-textboom-live-system-base.img
  hard-rom/build/system-otatrust-v0.36.1-smartisax-shell-debloat-arsc-align.img
  hard-rom/build/system-otatrust-v0.33-system-b-grow-noop.img
  hard-rom/build/system-otatrust-v0.32-browserchrome-stock-near-noop.img
  hard-rom/build/product-otatrust-v0.35.1-webview-m150-browserchrome-deodex.img
  hard-rom/build/product-otatrust-v0.35-webview-m150-system-provider.img
  hard-rom/build/product-otatrust-v0.31-webview-stock-near-noop.img
kept:
  hard-rom/build/super-otatrust-v0.38-sidebar-font-ocr-disabled.sparse.img
  hard-rom/build/super-otatrust-v0.37b-textboom-live-system-libs-deodex.sparse.img
  hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
  hard-rom/build/system-otatrust-v0.38-sidebar-font-ocr-disabled.img
  hard-rom/build/system-otatrust-v0.37b-textboom-live-system-libs-deodex.img
  hard-rom/build/product-otatrust-v0.35.2-webview-m150-clean-product-residue.img
free-space result:
  about 18 GiB -> about 48 GiB available on /System/Volumes/Data
```
