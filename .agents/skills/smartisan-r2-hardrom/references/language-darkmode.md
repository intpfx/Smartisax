# Language And Dark Mode Strategy

This file was split from `../SKILL.md` so the skill entrypoint stays short.
Treat historical evidence here as a pointer to current docs and verifier reports; re-check live state before device work.

## Overlay And Language Strategy

For AOSP locale-list customization, one source is the framework resource array:

```text
framework-res.apk res/values/arrays.xml array supported_locales
```

However Smartisan's visible language picker also uses:

```text
SettingsSmartisan LocalePickerFragment.constructAdapter()
  -> Resources.getSystem().getAssets().getLocales()
  -> filters locale strings by length == 5
```

`Resources.getSystem()` is built from `framework-res.apk`,
`framework-smartisanos-res.apk`, and immutable static overlays targeting
`android`. A ROM-bundled static RRO can override arrays such as
`supported_locales`, but it cannot hide locale configurations already compiled
into the framework resource APKs. Use:

```text
tools/r2-locale-resource-inventory.py
tools/r2-locale-prune-coverage-audit.py
tools/r2-language-full-prune-coverage-audit.py
tools/r2-language-source-coupling-audit.py
tools/r2-language-live-state-audit.sh
docs/research/locale-pruning-map.md
docs/research/language-prune-integration-map.md
docs/research/locale-prune-coverage-audit.md
docs/research/language-full-prune-coverage-audit.md
docs/research/language-source-coupling-audit.md
reverse/smartisan-8.5.3-rom-static/manifest/locale-resource-inventory.tsv
reverse/smartisan-8.5.3-rom-static/manifest/locale-prune-coverage-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/language-full-prune-coverage-audit.tsv
reverse/smartisan-8.5.3-rom-static/manifest/language-source-coupling-audit.tsv
```

before planning locale pruning. The integration map defines the target visible
set as `en-US`, `zh-Hans-CN`, and `zh-Hant-TW`, while first-stage resource
retention keeps all `en*` and `zh*` configs and removes non-English/
non-Chinese configs. The coverage audit is the current source for
distinguishing stock ja/ko resources already removed by v0.2/v0.4, resources
covered by the v0.10/v0.13/v0.17a/v0.17b/v0.22/v0.24 candidates, the v0.7 visible-filter-only
Settings change, and remaining hard-prune packages. After v0.24, it leaves 10
P1 small APK-only candidates behind package-specific review, with the prior APK-only
promotion queue empty and larger P2 rows separated. The full-prune coverage audit is the stricter source for the user's
actual English/Chinese-only goal: it counts all non-`en*`/`zh*` resource dirs,
not only the ja/ko subset. The latest full-prune audit reports 179 packages and
5650 non-target dirs in stock static ROM evidence, with 138 packages and 4674
non-target dirs still outside current ROM coverage.

v0.17a moves five system APK-only probes into a verified system_b image and
flashable sparse super. v0.17b moves PhotoTable and Confdialer into verified
product_b/system_ext_b images and a separate flashable sparse super. These
two sparse images are separate v0.4-based candidates, not a single combined
test target.

Use `tools/r2-language-next-batch-plan.py` after the full-prune audit to decide
the next staged work. Current plan:

```text
P0a_rebuild_v013_tier1a_stored: 3 packages / 6 dirs
P1_build_small_apk_only: 10 packages / 20 dirs
P2_build_green_full_language_apk_only: 22 packages / 1555 dirs
P3_deferred_green_coupled: 5 packages / 161 dirs
P4_amber_package_gate: 56 packages / 1840 dirs
P5_red_core_gate: 45 packages / 1098 dirs
```

Do not treat this plan as build authorization. It is a queue for review,
APK-only candidate work, image promotion, and live gates.

Run `tools/r2-language-p1-source-review-audit.py` before building from the P1
small APK-only queue. After v0.19a CompanionDeviceManager, v0.20a
SmartisanShareBrowser, v0.21a TrackerSmartisan, and v0.23a/v0.24
CleanerSmartisan, the current review leaves 10 P1 rows:

```text
P1c_defer_focused_package_review: 10 packages
```

This does not authorize a build by itself. It narrows the next APK-only
mini-batch and records which rows need package-specific source/graph review
before resource pruning.

The source-coupling audit confirms the mechanism split:

```text
SettingsSmartisan LocalePickerFragment
  -> Resources.getSystem().getAssets().getLocales()
framework AssetManager
  -> framework-res.apk, framework-smartisanos-res.apk, android static overlays
ResourcesManager / ResourcesImpl
  -> per-package resDir/splits/overlays and best-locale fallback
telephony/SIM helpers
  -> context.getAssets().getLocales()
```

Therefore visible filtering, framework AssetManager hard-pruning, app-level
resource pruning, and live framework/package gates remain separate work streams.

Direct `framework-res.apk` repacking is a later, higher-risk step because
framework resource IDs, package IDs, and early boot resource loading are fragile.
`framework-res.apk` currently rebuilds offline with apktool, but
`framework-smartisanos-res.apk` must not be rebuilt by normalizing
`^attr-private` to ordinary attrs for a ROM candidate. The current safe offline
strategy is binary `resources.arsc` locale-config chunk pruning.

The first visible-language behavior candidate is already reproducible offline:

```bash
tools/r2-build-settingssmartisan-locale-filter-apk.sh
tools/r2-verify-settingssmartisan-locale-filter-apk.sh
tools/r2-hardrom-build-v0.7-locale-filter.sh
tools/r2-verify-v0.7-locale-filter.sh --read-only
tools/r2-build-settingssmartisan-darkmode-ui-apk.sh
tools/r2-hardrom-build-v0.8-darkmode-ui.sh
tools/r2-verify-v0.8-darkmode-ui.sh --read-only
tools/r2-build-protips-locale-prune-apk.sh
tools/r2-build-apk-locale-prune.sh --package <package.name>
tools/r2-build-apk-locale-prune-binary-arsc.sh --package <package.name>
tools/r2-verify-tier1a-locale-prune-apks.sh
tools/r2-verify-apk-only-locale-prune-candidates.sh
tools/r2-locale-prune-coverage-audit.py
tools/r2-language-full-prune-coverage-audit.py
tools/r2-build-framework-res-locale-probe.sh --mode locale-prune
tools/r2-build-smartisanos-framework-res-locale-probe.sh
tools/r2-v017-apk-only-promotion-audit.py
tools/r2-hardrom-build-v0.9-protips-locale-prune.sh
tools/r2-hardrom-build-v0.10-framework-locale-prune.sh
tools/r2-verify-v0.10-framework-locale-prune.sh --offline-image
tools/r2-hardrom-build-v0.12-framework-res-noop.sh
tools/r2-verify-v0.12-framework-res-noop.sh --offline-image
tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh
tools/r2-verify-v0.13-tier1a-locale-prune.sh --offline-system-image
```

The first resource-table hard-prune probe is Protips:

```text
package: com.android.protips
path: /system/app/Protips/Protips.apk
preflight: delete GREEN, replace ORANGE only because same-package replacement
resource change: resources.arsc only
signature boundary: SHA-256 digest error for resources.arsc
status: APK built; super image intentionally not generated yet to save space
```

The reusable APK-level locale prune tool is now:

```text
tools/r2-build-apk-locale-prune.sh
tools/r2-build-apk-locale-prune-binary-arsc.sh
  --package <package.name>
  --apk <path/to/app.apk> --label <name>
  --apk-only-variant <variant> --apk-only-note <note>

Use the binary-arsc fallback when apktool/aapt2 can decode a package but cannot
rebuild it because of Smartisan private attrs or package-id quirks. It removes
only binary resources.arsc locale config chunks and merges the result into the
stock APK shell.

verified offline samples:
  com.android.protips
    removes values-ja and values-ko
    output sha256=71ed25c64babd01e07cec4263aa1ea88ddb0a1bf74c1a03e3dc45c67ae5850d5
  com.android.printservice.recommendation
    removes values-ja and values-ko
    output sha256=06628867eba1a7451a0afdb866eeb18b8d1bc36b6521a894331a4b2194b5c383
  com.android.hotspot2.osulogin
    removes values-ja and values-ko
    output sha256=fa09b52598733e680abc21cd77dde6e953fdaf676f2fb835b99f5361c9476e6e
  com.android.printspooler
    removes 77 non-English/non-Chinese locale dirs
    output sha256=3f7ee66118b7e5acab0a8aad71e8efcc086535887250da4af0e723c1b11c9d38
  com.android.wallpaper.livepicker
    removes values-ja and values-ko
    output sha256=acf2131fe283817b61e1f99ebaceddc2973caaaaddae0e86cd070d20dbb10130
  com.android.htmlviewer
    removes values-ja and values-ko
    output sha256=fcfdd58b5fb92bfc05b6eba8cfc13759e3175d0e3db3cca7c129fec528282e35
  com.android.dreams.basic
    removes values-ja and values-ko
    output sha256=2512094b9ac6ab042e97f37b74eb305b44e354a7fb341bcb5ceb4860dd7d0129
  com.android.dreams.phototable
    removes values-ja and values-ko
    output sha256=c48ca2f6c3c95b1e0a7cbad3de2df3a7db5a78742a8cf77b3f847aa33f32a27f
  com.qualcomm.qti.confdialer
    removes values-ja and values-ko, keeps values-zh, values-zh-rCN, values-zh-rTW
    output sha256=ee1bb729fe3bf2577ba898c91fbb088b0942a0ecf5c60183bf0fb6046d5914db
  com.smartisanos.tracker
    removes values-ja and values-ko app_name resources
    output sha256=9040314bd46e953e43827ab8d9102fe306a06c62516f0a19ec779ff078a1626c
  com.smartisanos.cleaner
    binary resources.arsc prune; removes ja/ko config chunks after apktool rebuild failure
    output sha256=d0a12dbc5bab63dbb7bba43cc01c56c91e4503fda1eaf6852b80bb50cc5639fc

Tier1a verifier:
  tools/r2-verify-tier1a-locale-prune-apks.sh
  hard-rom/inspect/tier1a-locale-prune-apks/verify-tier1a-locale-prune-apks-20260618-115520.txt
  result=PASS; confirms classes.dex and AndroidManifest.xml unchanged,
  resources.arsc changed and remains STORED, ZIP integrity OK, signature
  boundary at resources.arsc, and binary locale policy bad_locale_chunk_count=0.

APK-only batch verifier:
  tools/r2-verify-apk-only-locale-prune-candidates.sh
  hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-124601.txt
  result=PASS_OFFLINE_APK_ONLY_BATCH; confirms the seven v0.17 APK-only
  candidates keep classes.dex and AndroidManifest.xml unchanged,
  change resources.arsc, keep resources.arsc STORED, and pass binary locale
  policy.
  Latest APK-only verifier:
    hard-rom/inspect/apk-only-locale-prune-candidates/verify-apk-only-locale-prune-candidates-20260618-144236.txt
    result=PASS_OFFLINE_APK_ONLY_BATCH; confirms all eleven APK-only candidates
    including v0.19a CompanionDeviceManager, v0.20a SmartisanShareBrowser, and
    v0.21a TrackerSmartisan, plus v0.23a CleanerSmartisan.

v0.17 promotion audit:
  tools/r2-v017-apk-only-promotion-audit.py
  tools/r2-apk-same-size-pad.py
  tools/r2-ext4-inplace-file-write.py
  docs/research/v0.17-apk-only-promotion-audit.md
  reverse/smartisan-8.5.3-rom-static/manifest/v0.17-apk-only-promotion-audit.tsv
  current result: eleven promoted APK-only candidates map to system_b/product_b/system_ext_b.
  Seven have promotion_scope=v0.17_promoted and are included in v0.17-all.
  v0.19a CompanionDeviceManager, v0.20a SmartisanShareBrowser, and v0.21a
  TrackerSmartisan have promotion_scope=v0.22_promoted and are included in the
  newer v0.22-all image. v0.23a CleanerSmartisan has
  promotion_scope=v0.24_promoted and is included in the latest v0.24 image.
  Ordinary held-inode replacement is not feasible for Confdialer on system_ext
  because the reference image has fewer free blocks than the patched APK write
  would need. The special same-size/in-place strategy is now offline-proven for
  the current reference inode:
    hard-rom/build/apk/com.qualcomm.qti.confdialer-locale-prune-en-zh-samesize.apk
      sha256=e91d53b1cf1124896a3e8a0bfd577c8b1a9ef222435061bcfdafa93d3e3765c5
    evidence:
      hard-rom/inspect/v0.17-apk-only-promotion/confdialer-samesize-apk-report.json
      hard-rom/inspect/v0.17-apk-only-promotion/confdialer-system_ext-inplace-dry-run.json
      hard-rom/inspect/v0.17-apk-only-promotion/confdialer-system_ext-inplace-write-test.json
      hard-rom/inspect/v0.17-apk-only-promotion/confdialer-system_ext-inplace-e2fsck-fn.txt
      hard-rom/inspect/v0.17-apk-only-promotion/dumped/ConferenceDialer-samesize-from-system_ext.apk
  This is not a blanket system_ext rule. Re-run exact size, resources.arsc
  stored mode, extent, icheck owner, fsck, dumped-APK hash, ZIP integrity,
  signature-boundary, and locale-policy gates for each new target.

guardrails:
  use r2-rom-mod-preflight.py before choosing a package
  treat the APK as an offline candidate only until a matching ROM image and
  flash step are explicitly authorized
  verify classes.dex and AndroidManifest.xml remain byte-identical when present
  future resources.arsc rebuilds should keep the ZIP member STORED like stock
  system APKs; scripts now use zip -0 for resource-table merges. Rebuild and
  re-verify any older deflated APK-only candidates before promoting them into a
  new ROM image.
```

The framework-res language-resource probe is now reproducible offline:

```text
tools/r2-build-framework-res-locale-probe.sh
  --mode noop
  --mode locale-prune

verified offline outputs:
  framework-res-rebuild-noop.apk
    sha256=319cd91f8a29c88e8c1058a15bdcd2fbd159a82107add92daf87cbd40fd4240a
  framework-res-locale-prune-en-zh.apk
    sha256=10fc36befd0acdb1a1530c6e676cc154170de1bebac5d7eb84b73c24f164aedd

locale-prune result:
  removes 61 non-English/non-Chinese framework-res resource dirs, including
  raw-ja and raw-ko
  keeps 63 English/Chinese framework-res locale resource dirs
  narrows supported_locales to en-US, zh-Hans-CN, zh-Hant-TW
  removes ar_EG from special_locale_codes/special_locale_names
  binary resources.arsc policy check reports only en/zh locale chunks
  keeps public.xml byte-identical after decode/rebuild
  keeps AndroidManifest.xml byte-identical in the stock APK shell

guardrails:
  this is not a flash-authorized ROM image
  framework-res remains a RED early-boot system asset
```

The Smartisan framework resource probe is now reproducible offline without
aapt2 rebuild:

```text
tools/r2-arsc-prune-locales.py
tools/r2-build-smartisanos-framework-res-locale-probe.sh

raw apktool/aapt2 rebuild failure:
  public.xml declares smartisanos:^attr-private/backgroundShadow and peers
  at IDs 0x020b0000..0x020b0004, but aapt2 cannot link that synthetic type.

binary arsc-prune output:
  framework-smartisanos-res-locale-prune-en-zh.apk
    sha256=eefab348089210bba963c69f5966052a65b11fdd1bf198084c60cc005a45b228

locale-prune result:
  removes 6 non-English/non-Chinese RES_TABLE_TYPE_TYPE chunks:
    string ja, string ko, dimen ja, array ja, array ko, integer ja
  keeps zh-rCN and zh-rTW resources
  decoded output has no values-ja or values-ko dirs
  keeps AndroidManifest.xml byte-identical
  keeps public.xml diff at 0 bytes after decode
  keeps ^attr-private public IDs at 0x020b0000..0x020b0004

guardrails:
  this is not a flash-authorized ROM image
  framework-smartisanos-res remains a RED early-boot system asset
  use the binary arsc route for locale config pruning; do not use the old smoke
  script's attr normalization as a ROM patching method
```

The combined framework/product language-resource candidate is now reproducible
offline:

```text
tools/r2-hardrom-build-v0.10-framework-locale-prune.sh
tools/r2-verify-v0.10-framework-locale-prune.sh --offline-image

super sparse:
  hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img
  sha256=62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae
system image:
  sha256=1a9c2725a25ce48ec7b708ff5cb69e98f6ceae69827ee04e571d7bb15c146351
product image:
  sha256=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2

patched files:
  /system/framework/framework-res.apk
  /system/framework/framework-smartisanos-res/framework-smartisanos-res.apk
  /overlay/DisplayCutoutEmulation{Corner,Double,Hole,Tall,Waterfall}/...

verification:
  build enforces post-fsck dump hash and unzip -t for all seven APKs
  offline verifier passed against final system/product images
  offline verifier also checks sparse system_b/product_b logical slices match
  the generated system/product images

guardrails:
  not flashed or live-verified
  RED early-boot framework resource candidate
  explicit user confirmation required before flash
```

The smaller framework-res replacement gate is prepared but not built:

```text
tools/r2-hardrom-build-v0.12-framework-res-noop.sh
tools/r2-verify-v0.12-framework-res-noop.sh --offline-system-image
tools/r2-verify-v0.12-framework-res-noop.sh --offline-image
tools/r2-sparse-partition-patch.py

purpose:
  replace only /system/framework/framework-res.apk with the already verified
  framework-res-rebuild-noop.apk before attempting v0.10 language hard-prune.

current boundary:
  system image generated with BUILD_SUPER=0 and verified offline, then removed
  during cleanup to save disk space.
  sparse super generated by direct Android sparse rewrite, because system_b
  crosses FILL chunks and cannot be patched as raw-only clone.
  sparse sha256=d5c63890f27f6609b09667cc0bee0dd4b55c5c335abeb530650c16fbce9d94d9
  system image sha256=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0
  offline verifier checks framework-res.apk hash/ZIP/signature boundary and
  sparse system_b logical slice hash.
```
