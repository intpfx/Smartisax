# Artifact And Tool Index

This file was split out of `docs/README.md`; it lists important artifact directories and helper tools.
Paths are repo-root-relative unless explicitly described otherwise.


## Artifact Directories And Tools

```text
hard-rom/build/
  Generated system/super images and manifests. Keep the latest successful local
  sparse image here; older/cold rollback images may live on SSDUSB if recorded
  in rom-archive.md.

tools/r2-rom-mod-preflight.py
  Read-only package modification preflight against the static ROM indexes.

tools/r2-locale-resource-inventory.py
  Read-only locale qualifier inventory for decoded ROM APK/resource packages.

tools/r2-build-settingssmartisan-locale-filter-apk.sh
  Reproducible offline APK patcher for the SettingsSmartisan ja_JP/ko_KR
  visible language-list filter.

tools/r2-verify-settingssmartisan-locale-filter-apk.sh
  Read-only APK-level semantic verifier for the v0.7 SettingsSmartisan
  visible-language filter. It confirms only classes.dex changed, decodes the
  APK to temporary smali, copies LocalePickerFragment.smali into
  hard-rom/inspect, and verifies constructAdapter() skips ja_JP and ko_KR while
  still enumerating AssetManager.getLocales().

tools/r2-build-settingssmartisan-darkmode-ui-apk.sh
  Reproducible offline APK patcher for the SettingsSmartisan native dark-mode
  switch candidate.

tools/r2-hardrom-build-v0.6-settings-noop.sh
tools/r2-hardrom-build-v0.7-locale-filter.sh
tools/r2-hardrom-build-v0.8-darkmode-ui.sh
  Offline exact-current system_b replacement builders for the SettingsSmartisan
  core-APK trust gate and behavior patch candidates. These now use the
  shared_blocks-safe held-stock-inode replacement pattern and enforce
  post-fsck APK hash plus ZIP verification.

tools/r2-verify-settingssmartisan-offline-images.sh
  Read-only verifier for the SettingsSmartisan v0.6/v0.7/v0.8 offline images.
  It dumps SettingsSmartisan.apk from each final system image, verifies ZIP
  integrity, and checks that each sparse super's system_b logical slice matches
  the generated system image without expanding a full raw super.

tools/r2-build-protips-locale-prune-apk.sh
  Reproducible APK-level resource-table probe that removes Protips ja/ko values
  resources while keeping English and Chinese resources.

tools/r2-build-apk-locale-prune.sh
  Generic APK-level resource-table tool that removes non-English/non-Chinese
  locale resource dirs from a selected package or APK while preserving the stock
  APK shell and verifying that only resources.arsc changed. Future rebuilds keep
  `resources.arsc` STORED like stock system APKs. When run with
  --apk-only-variant and --apk-only-note, it records the candidate in
  hard-rom/build/apk/locale-prune-apk-only-manifest.tsv for shared audit and
  verifier use.

tools/r2-verify-tier1a-locale-prune-apks.sh
  Read-only verifier for the first Tier1a minimal-exposure APK language
  hard-prune candidates: Protips, PrintRecommendationService, and OsuLogin. It
  checks expected APK hashes, ZIP integrity, unchanged classes.dex and
  AndroidManifest.xml, changed resources.arsc, resources.arsc digest-boundary,
  and binary locale policy.

tools/r2-verify-apk-only-locale-prune-candidates.sh
  Read-only verifier for all APK-only language hard-prune candidates listed in
  the APK-only locale-prune manifest and full-prune coverage TSV. It verifies
  expected hashes, ZIP integrity, unchanged classes.dex and AndroidManifest.xml,
  changed resources.arsc, the expected resources.arsc digest-boundary, and binary
  English/Chinese locale policy. It does not build ROM images or authorize
  flashing.

tools/r2-v017-apk-only-promotion-audit.py
  Read-only v0.17 planning audit for promoting APK-only language-prune
  candidates into ROM partition images. It writes
  `docs/research/v0.17-apk-only-promotion-audit.md` and
  `reverse/smartisan-8.5.3-rom-static/manifest/v0.17-apk-only-promotion-audit.tsv`.

tools/r2-apk-same-size-pad.py
  Builds a same-size APK candidate for tight partition replacement by forcing
  selected ZIP members such as `resources.arsc` to STORED and padding only with
  an EOCD comment. Used for the Confdialer system_ext in-place strategy.

tools/r2-ext4-inplace-file-write.py
  Dry-run/write helper for exact-size ext4 file replacement without reallocating
  blocks. It refuses size mismatches and, by default, refuses target blocks that
  are not owned only by the target inode according to `debugfs icheck`.

tools/r2-locale-prune-coverage-audit.py
  Read-only audit that writes the current locale hard-prune coverage TSV and
  markdown report. It separates v0.4-deleted packages, v0.10-covered resource
  targets, v0.7 visible-filter-only Settings work, and remaining GREEN/AMBER/RED
  hard-prune frontiers. It also scores small GREEN/YELLOW APK candidates by
  static package exposure using component, core-intent, provider, and permission
  indexes plus package-index status, and joins the APK-only manifest so offline
  APK candidates are visible but not counted as ROM coverage.

tools/r2-language-source-coupling-audit.py
  Read-only language source-coupling audit. It writes a TSV manifest and
  markdown report that map why visible language filtering, framework
  AssetManager resource pruning, app-level resource pruning, and live framework
  gates must remain separate work streams.

tools/r2-build-framework-res-locale-probe.sh
  High-risk framework-res-only offline probe. Builds a no-op resource-table
  control and an English/Chinese locale-prune candidate while verifying
  public.xml stability, AndroidManifest.xml identity, locale policy, and the
  resources.arsc signature boundary. Does not build a ROM image or authorize a
  flash.

tools/r2-arsc-prune-locales.py
  Binary resources.arsc locale-config chunk pruner. Preserves package/type/key
  string pools, type-spec chunks, entry IDs, and entry payload bytes while
  removing RES_TABLE_TYPE_TYPE chunks outside the kept language set.

tools/r2-verify-apk-locale-policy.py
  Read-only binary resources.arsc locale-policy verifier. It parses APK resource
  tables directly and fails if any localized resource-table chunk uses a
  language outside the kept set, such as en,zh for the R2 hard-prune route.

tools/r2-build-smartisanos-framework-res-locale-probe.sh
  framework-smartisanos-res-only offline probe. Avoids apktool/aapt2 rebuild so
  Smartisan's ^attr-private type ID remains intact; merges the pruned
  resources.arsc back into the stock APK shell and verifies decoded locale
  removal, public.xml stability, manifest identity, and signature boundary.

tools/r2-hardrom-build-v0.9-protips-locale-prune.sh
  Offline exact-current system_b builder for the Protips locale-prune probe.
  Prepared but not run as of the APK-level probe.

tools/r2-hardrom-build-v0.10-framework-locale-prune.sh
tools/r2-verify-v0.10-framework-locale-prune.sh
  High-risk exact-current framework/product language hard-prune ROM candidate.
  Patches system_b framework resource APKs plus product_b DisplayCutout static
  overlays. Uses hidden hard-link stock-inode holds to avoid freeing
  shared_blocks ext4 data during debugfs replacement, then verifies post-fsck
  APK hashes, ZIP integrity, and dumped-APK binary locale policy. Built and
  offline-verified only; not flashed.

tools/r2-hardrom-build-v0.12-framework-res-noop.sh
tools/r2-verify-v0.12-framework-res-noop.sh
  Smaller framework-res replacement gate before v0.10. Replaces only
  /system/framework/framework-res.apk with the no-op rebuilt resource-table APK
  so live testing can separate framework-res replacement boot risk from language
  hard-prune behavior. The system image and flashable sparse super are built
  and verified offline; live testing still requires explicit confirmation.

tools/r2-hardrom-build-v0.13-tier1a-locale-prune.sh
tools/r2-verify-v0.13-tier1a-locale-prune.sh
  Low-exposure Tier1a ROM-level language hard-prune batch. Replaces Protips,
  PrintRecommendationService, and OsuLogin in system_b with verified
  English/Chinese-only resources.arsc APK variants using the shared_blocks-safe
  held-inode replacement pattern. The system_b image is built and verified
  offline; the flashable sparse super is not built yet.

tools/r2-hardrom-build-v0.17a-system-apk-only-locale-prune.sh
tools/r2-verify-v0.17a-system-apk-only-locale-prune.sh
  System-only APK promotion batch for the English/Chinese language hard-prune
  route. Replaces BasicDreams, HTMLViewer, LiveWallpapersPicker, PrintSpooler,
  and SimAppDialog in system_b with verified APK-only candidates, keeps hidden
  held-stock inodes for shared_blocks safety, rewrites a flashable sparse super,
  and verifies dumped APK hashes, ZIP integrity, locale policy, held paths, and
  sparse system_b slice equality. It is not live proof or flash authorization.

tools/r2-sparse-partition-patch.py
  Low-space Android sparse-image partition patcher. It parses sparse chunks,
  extracts/verifies/patches known B-slot partition extents, and can rewrite
  sparse output directly when a partition range crosses FILL/DONT_CARE chunks,
  avoiding a full raw-super expansion.

tools/r2-live-flash-preflight.sh
  Read-only flash preflight for the current live gates. It verifies expected
  sparse-image hashes, v0.4 rollback readiness, latest offline evidence reports,
  verifier scripts, and current adb/fastboot state when available. It never
  flashes, reboots, erases misc, or changes /data.

tools/r2-mirror.sh
tools/r2-hardrom-build-v0.portal1-smartisax-lan-portal-noop.sh
tools/r2-verify-v0.portal1-smartisax-lan-portal-noop.sh
hard-rom/build/super-otatrust-v0.portal1-smartisax-lan-portal-noop.sparse.img
hard-rom/inspect/v0.portal1-smartisax-lan-portal-noop/
  Mac wrapper plus offline builder/verifier, flashable sparse image, and
  evidence for the first Smartisax LAN Device Portal candidate. v0.portal1
  starts from live-proven v0.wadb2.2, updates Smartisax to v0.3.0/versionCode 6,
  adds a Wi-Fi-bound `DevicePortalService` on port 37601, and exposes only
  pairing plus token-gated `/api/status`. It is built, offline-verified,
  live-preflighted, flashed to B slot, and live-proven for direct same-LAN
  browser access without adb forward.

tools/r2-hardrom-build-v0.portal2-smartisax-remote-screen-control.sh
tools/r2-verify-v0.portal2-smartisax-remote-screen-control.sh
hard-rom/build/super-otatrust-v0.portal2-smartisax-remote-screen-control.sparse.img
hard-rom/inspect/v0.portal2-smartisax-remote-screen-control/
  Offline builder/verifier, flashable sparse image, and evidence for the first
  Smartisax LAN Portal screen/control gate. v0.portal2 starts from live-proven
  v0.portal1, updates Smartisax to v0.4.0/versionCode 7, and adds token-gated
  `/api/screen.png` PNG polling plus `/api/input` tap/swipe control. It is
  built, offline-verified, and live-preflighted, but not flashed yet.

tools/r2-hardrom-build-v0.portal2.3-smartisax-framebuffer-grant.sh
tools/r2-verify-v0.portal2.3-smartisax-framebuffer-grant.sh
hard-rom/build/super-otatrust-v0.portal2.3-smartisax-framebuffer-grant.sparse.img
hard-rom/inspect/v0.portal2.3-smartisax-framebuffer-grant/
  Offline builder/verifier, flashable sparse image, and evidence for the
  accepted Smartisax LAN Portal framebuffer permission gate. v0.portal2.3 starts
  from v0.portal2.2, keeps Smartisax v0.4.2/versionCode 9 unchanged, replaces
  only `/system/framework/services.jar`, and adds a narrow PackageManager
  signature-permission policy granting only `android.permission.READ_FRAME_BUFFER`
  to `com.smartisax.browser`. It is live-proven on B slot: `/api/screen.png`
  returns 1080 x 2340 PNG frames and `/api/input` tap/swipe works through the
  privileged InputManager path.

tools/r2-hardrom-build-v0.portal3a-webrtc-capability-probe.sh
tools/r2-verify-v0.portal3a-webrtc-capability-probe.sh
tools/r2-portal-smoke-v0.portal3a.sh
hard-rom/build/super-otatrust-v0.portal3a-webrtc-capability-probe.sparse.img
hard-rom/inspect/v0.portal3a-webrtc-capability-probe/
  Offline builder/verifier, flashable sparse image, and evidence for the first
  Smartisax Portal WebRTC route probe. v0.portal3a starts from live-proven
  v0.portal2.3, updates Smartisax to v0.5.0/versionCode 10, keeps the framebuffer
  services.jar policy unchanged, preserves `/api/screen.png` and `/api/input`,
  and adds token-gated `/api/media/capabilities` plus browser-side
  WebRTC/WebCodecs probing. It is built, offline-verified, live-preflighted,
  flashed to B slot, read-only verified, and LAN-smoke verified. The smoke
  helper takes the live Portal URL plus pairing code and verifies status, media
  capabilities, PNG screen, tap/swipe input, and a post-input PNG frame.

tools/r2-hardrom-build-v0.portal3b-h264-http-stream-prototype.sh
tools/r2-verify-v0.portal3b-h264-http-stream-prototype.sh
tools/r2-portal-smoke-v0.portal3b.sh
hard-rom/build/super-otatrust-v0.portal3b-h264-http-stream-prototype.sparse.img
hard-rom/inspect/v0.portal3b-h264-http-stream-prototype/
  Offline builder/verifier, flashable sparse image, and live smoke helper for
  the first Smartisax Portal H.264 stream prototype. v0.portal3b starts from
  live-proven v0.portal3a, updates Smartisax to v0.5.1/versionCode 11, keeps
  the framebuffer services.jar policy unchanged, preserves `/api/screen.png`,
  `/api/input`, and `/api/media/capabilities`, and adds token-gated
  `/api/video/h264` H.264 Annex-B output. It is built, offline-verified,
  live-preflighted, flashed to B slot, read-only verified, and LAN-smoke
  verified. The smoke helper verifies status, media capabilities, H.264 Annex-B
  stream shape, PNG screen, tap/swipe input, and a post-input PNG frame.

tools/r2-hardrom-build-v0.portal3c-h264-webcodecs-playback.sh
tools/r2-verify-v0.portal3c-h264-webcodecs-playback.sh
tools/r2-portal-smoke-v0.portal3c.sh
hard-rom/build/super-otatrust-v0.portal3c-h264-webcodecs-playback.sparse.img
hard-rom/inspect/v0.portal3c-h264-webcodecs-playback/
  Offline builder/verifier, flashable sparse image, and live smoke helper for
  the Smartisax Portal browser playback candidate. v0.portal3c starts
  from live-proven v0.portal3b, updates Smartisax to v0.5.2/versionCode 12,
  moves the Portal page to `assets/portal/index.html`, adds token-gated
  `/api/video/mp4` MediaMuxer clips for direct-LAN HTTP video-element playback,
  and keeps raw `/api/video/h264` as WebCodecs diagnostic input plus PNG/input
  fallback. It is built, offline-verified, live-preflighted, flashed,
  read-only verified, LAN-smoke verified, and Safari playback verified on B
  slot.

tools/r2-hardrom-build-v0.portal4a-webrtc-rtp-probe.sh
tools/r2-verify-v0.portal4a-webrtc-rtp-probe.sh
tools/r2-portal-smoke-v0.portal4a.sh
hard-rom/build/super-otatrust-v0.portal4a-webrtc-rtp-probe.sparse.img
hard-rom/inspect/v0.portal4a-webrtc-rtp-probe/
  Offline builder/verifier, flashable sparse image, and live smoke helper for
  the Smartisax Portal WebRTC/RTP diagnostic candidate.
  v0.portal4a starts from live-proven v0.portal3c, updates Smartisax to
  v0.5.3/versionCode 13, adds `/api/webrtc/offer` SDP inspection and
  `/api/rtp/h264` length-prefixed RTP packet-dump probing, and keeps the
  v0.portal3c MP4, raw H.264, PNG, and input fallbacks. It is built,
  offline-verified, live-preflighted, flashed to B slot, read-only verified,
  LAN-smoke verified twice, and clean-logcat checked.

tools/r2-hardrom-build-v0.portal4b-mp4-control-polish.sh
tools/r2-verify-v0.portal4b-mp4-control-polish.sh
tools/r2-portal-smoke-v0.portal4b.sh
hard-rom/build/super-otatrust-v0.portal4b-mp4-control-polish.sparse.img
hard-rom/inspect/v0.portal4b-mp4-control-polish/
  Offline builder/verifier, flashable sparse image, and live smoke helper for
  the Smartisax Portal Start Live MP4/control polish target.
  v0.portal4b starts from live-proven v0.portal4a, updates Smartisax to
  v0.5.4/versionCode 14, keeps `/api/webrtc/offer` and `/api/rtp/h264`
  diagnostics, adds `Start Live`, `autoplay=live`, and live loop metrics, and
  keeps direct-LAN MP4 video-element playback as the default browser route.
  It is built, offline-verified, live-preflighted, flashed to B slot, read-only
  verified, LAN-smoke verified, static `autoplay=live` route checked, and
  clean-logcat checked.

tools/r2-hardrom-build-v0.portal4c-session-hardening.sh
tools/r2-verify-v0.portal4c-session-hardening.sh
tools/r2-portal-smoke-v0.portal4c.sh
hard-rom/build/super-otatrust-v0.portal4c-session-hardening.sparse.img
hard-rom/inspect/v0.portal4c-session-hardening/
  Offline builder/verifier, flashable sparse image, live preflight evidence,
  and live smoke helper for the Smartisax Portal session-hardening
  target. v0.portal4c starts from live-proven v0.portal4b, updates Smartisax to
  v0.5.5/versionCode 15, keeps the MP4/H.264/RTP/PNG/input and WebRTC-offer
  diagnostic endpoints, and adds pairing-code rotation, bad-pair lockout,
  session metadata, local-session clear UI, constant-time Bearer comparison,
  and browser security headers. It is built, offline-verified, live-preflighted,
  flashed, read-only verified, and LAN-smoke verified on B slot.

tools/r2-hardrom-build-v0.portal5a-native-webrtc-runtime.sh
tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh
tools/r2-hardrom-build-v0.portal5b-native-webrtc-system-libs.sh
tools/r2-verify-v0.portal5b-native-webrtc-system-libs.sh
tools/r2-hardrom-build-v0.portal5c-webrtc-software-bitmap-frames.sh
tools/r2-verify-v0.portal5c-webrtc-software-bitmap-frames.sh
tools/r2-hardrom-build-v0.portal5d-webrtc-bitmap-copy-frames.sh
tools/r2-verify-v0.portal5d-webrtc-bitmap-copy-frames.sh
tools/r2-hardrom-build-v0.portal5e-webrtc-h264-session-control.sh
tools/r2-verify-v0.portal5e-webrtc-h264-session-control.sh
tools/r2-hardrom-build-v0.portal5f-webrtc-datachannel-input.sh
tools/r2-verify-v0.portal5f-webrtc-datachannel-input.sh
tools/r2-hardrom-build-v0.portal5g-webrtc-touch-quality.sh
tools/r2-verify-v0.portal5g-webrtc-touch-quality.sh
tools/r2-hardrom-build-v0.portal5h-webrtc-bitrate-quality.sh
tools/r2-verify-v0.portal5h-webrtc-bitrate-quality.sh
tools/r2-hardrom-build-v0.portal5i-webrtc-runtime-tuning.sh
tools/r2-verify-v0.portal5i-webrtc-runtime-tuning.sh
tools/r2-hardrom-build-v0.portal5j-projection-texture-probe.sh
tools/r2-verify-v0.portal5j-projection-texture-probe.sh
tools/r2-build-services-portal5j-projection-permissions-jar.sh
tools/r2-hardrom-build-v0.portal5j.1-projection-permission-grant.sh
tools/r2-verify-v0.portal5j.1-projection-permission-grant.sh
tools/r2-hardrom-build-v0.portal5j.2-projection-binder-transact.sh
tools/r2-verify-v0.portal5j.2-projection-binder-transact.sh
tools/r2-hardrom-build-v0.portal5k-frame-pump-continuity.sh
tools/r2-verify-v0.portal5k-frame-pump-continuity.sh
tools/r2-hardrom-build-v0.portal5k.1-frame-timestamp-retain.sh
tools/r2-verify-v0.portal5k.1-frame-timestamp-retain.sh
tools/r2-hardrom-build-v0.portal5l-touch-photon-move-stream.sh
tools/r2-verify-v0.portal5l-touch-photon-move-stream.sh
tools/r2-portal-smoke-v0.portal5a.sh
tools/r2-portal5a-chrome-webrtc-smoke.mjs
tools/r2-portal5i-runtime-tuning-smoke.sh
tools/r2-portal5j2-projection-texture-smoke.sh
tools/r2-portal5k-frame-pump-continuity-smoke.sh
tools/r2-portal5k1-frame-timestamp-retain-smoke.sh
tools/r2-portal5k1-latency-input-smoke.sh
tools/r2-portal5l-touch-photon-move-stream-smoke.sh
tools/r2-hardrom-build-v0.portal5m-latency-follow-rate.sh
tools/r2-verify-v0.portal5m-latency-follow-rate.sh
tools/r2-portal5m-latency-follow-rate-smoke.sh
tools/r2-hardrom-build-v0.portal5n-latency-budget-queue-collapse.sh
tools/r2-verify-v0.portal5n-latency-budget-queue-collapse.sh
tools/r2-portal5n-latency-budget-queue-collapse-smoke.sh
tools/r2-hardrom-build-v0.portal5o-input-frame-boost.sh
tools/r2-verify-v0.portal5o-input-frame-boost.sh
tools/r2-portal5o-input-frame-boost-smoke.sh
tools/r2-hardrom-build-v0.portal5p-dual-phase-input-boost.sh
tools/r2-verify-v0.portal5p-dual-phase-input-boost.sh
tools/r2-portal5p-dual-phase-input-boost-smoke.sh
tools/r2-hardrom-build-v0.portal5r-refresh-rate-60-90hz.sh
tools/r2-verify-v0.portal5r-refresh-rate-60-90hz.sh
tools/r2-portal5r-refresh-rate-60-90hz-smoke.sh
tools/r2-hardrom-build-v0.portal5s-event-time-input-priority.sh
tools/r2-verify-v0.portal5s-event-time-input-priority.sh
tools/r2-portal5s-event-time-input-priority-smoke.sh
tools/r2-hardrom-build-v0.portal5t-marker-burst-presentation.sh
tools/r2-verify-v0.portal5t-marker-burst-presentation.sh
tools/r2-portal5t-marker-burst-presentation-smoke.sh
tools/r2-hardrom-build-v0.portal5u-burst-reschedule-presentation.sh
tools/r2-verify-v0.portal5u-burst-reschedule-presentation.sh
tools/r2-portal5u-burst-reschedule-presentation-smoke.sh
tools/r2-hardrom-build-v0.portal5v-presentation-cadence.sh
tools/r2-verify-v0.portal5v-presentation-cadence.sh
tools/r2-portal5v-presentation-cadence-smoke.sh
tools/r2-hardrom-build-v0.portal5w-quiet-presentation.sh
tools/r2-verify-v0.portal5w-quiet-presentation.sh
tools/r2-portal5w-quiet-presentation-smoke.sh
tools/r2-hardrom-build-v0.portal5x-presenter-mode.sh
tools/r2-verify-v0.portal5x-presenter-mode.sh
tools/r2-portal5x-presenter-mode-smoke.sh
tools/r2-hardrom-build-v0.portal5y-presentation-transport-pacing.sh
tools/r2-verify-v0.portal5y-presentation-transport-pacing.sh
tools/r2-portal5y-presentation-transport-pacing-smoke.sh
tools/r2-hardrom-build-v0.portal5z-video-primary-roi-probe.sh
tools/r2-verify-v0.portal5z-video-primary-roi-probe.sh
tools/r2-portal5z-video-primary-roi-probe-smoke.sh
tools/r2-live-flash-v0.portal5z-video-primary-roi-probe.sh
tools/r2-hardrom-build-v0.portal6a-marker-draw-sync.sh
tools/r2-verify-v0.portal6a-marker-draw-sync.sh
tools/r2-portal6a-marker-draw-sync-smoke.sh
tools/r2-live-flash-v0.portal6a-marker-draw-sync.sh
hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img
hard-rom/build/super-otatrust-v0.portal5y-presentation-transport-pacing.sparse.img
hard-rom/build/super-otatrust-v0.portal5z-video-primary-roi-probe.sparse.img
hard-rom/build/super-otatrust-v0.portal6a-marker-draw-sync.sparse.img
  Retained local flash/rollback images after the 2026-06-24 space recovery.
  Superseded portal5h through portal5x sparse images, old raw system_b
  intermediates, regenerated 5z raw/work files, `hard-rom/work/*`, and
  `hard-rom/extracted` were removed locally; their scripts, checksum manifests,
  docs, and inspect reports remain.
hard-rom/build/framework/services-portal5j-smartisax-projection-permissions.jar
hard-rom/inspect/v0.portal5f-webrtc-datachannel-input/
hard-rom/inspect/v0.portal5g-webrtc-touch-quality/
hard-rom/inspect/v0.portal5h-webrtc-bitrate-quality/
hard-rom/inspect/v0.portal5i-webrtc-runtime-tuning/
hard-rom/inspect/v0.portal5j-projection-texture-probe/
hard-rom/inspect/v0.portal5j.1-projection-permission-grant/
hard-rom/inspect/v0.portal5j.2-projection-binder-transact/
hard-rom/inspect/v0.portal5j.2-projection-binder-transact/portal-projection-live-rawbinder/
hard-rom/inspect/v0.portal5j.2-projection-binder-transact/portal-projection-texture-smoke-live/
hard-rom/inspect/v0.portal5k-frame-pump-continuity/
hard-rom/inspect/v0.portal5k-frame-pump-continuity/portal-frame-pump-continuity-smoke-live/
hard-rom/inspect/v0.portal5k.1-frame-timestamp-retain/
hard-rom/inspect/v0.portal5l-touch-photon-move-stream/
hard-rom/inspect/v0.portal5m-latency-follow-rate/
hard-rom/inspect/v0.portal5n-latency-budget-queue-collapse/
hard-rom/inspect/v0.portal5o-input-frame-boost/
hard-rom/inspect/v0.portal5p-dual-phase-input-boost/
hard-rom/inspect/v0.portal5r-refresh-rate-60-90hz/
hard-rom/inspect/v0.portal5s-event-time-input-priority/
hard-rom/inspect/v0.portal5t-marker-burst-presentation/
hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/
hard-rom/inspect/v0.portal5v-presentation-cadence/
hard-rom/inspect/v0.portal5w-quiet-presentation/
hard-rom/inspect/v0.portal5x-presenter-mode/
hard-rom/inspect/v0.portal5y-presentation-transport-pacing/
hard-rom/inspect/v0.portal5z-video-primary-roi-probe/
hard-rom/inspect/v0.portal6a-marker-draw-sync/
  Builder/verifier chain, shared curl smoke, Chrome RTCPeerConnection smoke,
  flash evidence, and live reports for the native WebRTC Portal line. v0.portal5a
  adds the first libwebrtc runtime and proves browser SDP reaches the device but
  exposes the missing native-library boundary; v0.portal5b installs external
  system libwebrtc libraries and proves ICE/DTLS/SRTP connection; v0.portal5c
  proves Canvas cannot consume HARDWARE screenshot bitmaps; v0.portal5d fixes
  that with Bitmap.copy and proves decoded browser frames; v0.portal5e makes
  H.264/session cleanup the default; v0.portal5f removes HTTP `/api/input` and
  proves the `smartisax-input` WebRTC DataChannel as the control transport.
  v0.portal5g is live-proven: it adds the transparent browser touch overlay,
  maps gestures to display coordinates for DataChannel tap/swipe payloads, and
  raises the default WebRTC frame pump to 540x1170@8fps. The Chrome smoke helper
  supports `--input-gesture-test` and proved ping/tap/swipe acknowledgements.
  v0.portal5h is live-proven: it removes the visible legacy transport choices
  from the Portal UI, defaults to native WebRTC, and writes explicit H.264
  RtpSender bitrate parameters. Chrome smoke proves bitrateApplied=true and
  127 decoded frames in 15s; logcat shows the encoder configured at 600kbps
  because it selected minBitrateBps. v0.portal5i is flashed and read-only
  verified; it adds `/api/webrtc/config` and Portal runtime controls for width,
  fps, and min/target/max bitrate with 1080px/30fps upper bounds. The v0.portal5i
  runtime-tuning smoke helper pairs the LAN Portal, checks `/api/webrtc/config`,
  applies Stable/Sharp/1080-30 configs, runs Chrome WebRTC H.264 with
  DataChannel tap/swipe, captures meminfo/logcat/sessions/config, and writes
  `runtime-tuning-summary.json` plus `runtime-tuning-summary.md`. Live smoke
  passes all three profiles; 1080/30 connects and controls but decodes around
  11fps, making it a stress profile rather than a default. v0.portal5j is the
  live-flashed MediaProjection/VirtualDisplay/SurfaceTextureHelper capture
  probe. It raises runtime tuning to 60fps, adds `/api/webrtc/capture/probe`,
  adds `MANAGE_MEDIA_PROJECTION` to Smartisax privapp permissions, and keeps the
  old Bitmap/I420 path as `projection-auto` fallback, but live verification
  proves privapp XML alone does not grant MANAGE_MEDIA_PROJECTION or
  CAPTURE_VIDEO_OUTPUT. v0.portal5j.1 is the live-verified services.jar repair:
  it grants READ_FRAME_BUFFER,
  CAPTURE_VIDEO_OUTPUT, and MANAGE_MEDIA_PROJECTION only to
  com.smartisax.browser and does not grant INJECT_EVENTS. Its read-only device
  verifier passes after B-slot flashing. v0.portal5j.2 is the current
  live-proven raw Binder token repair: it updates Smartisax to
  v0.6.9/versionCode 26, replaces the blocked hidden IMediaProjectionManager
  Stub reflection path with raw Binder transact calls, and its live
  `portal-projection-live-rawbinder/` evidence proves
  `/api/webrtc/capture/probe` returns hasProjectionPermission=true,
  binderCreateProjection=available, tokenRoute=raw-binder-transact-media-projection,
  and createProjection=ok. The dedicated v0.portal5j.2 projection-texture smoke
  helper pairs the LAN Portal, checks `/api/webrtc/capture/probe`, applies
  1080/30 and 1080/60 projection-texture configs, runs Chrome WebRTC H.264 with
  DataChannel tap/swipe, captures meminfo/logcat/sessions/config, and writes
  `projection-texture-summary.json` plus `projection-texture-summary.md`.
  Live smoke proves the path connects and controls at 1080x2340, but the
  stream stalls after the initial burst: 1080/30 decodes 27 frames at about
  1.1fps and 1080/60 decodes 18 frames at about 0.89fps over the 20s
  observation window, both with zero packet-loss delta. v0.portal5k is the
  previous live-flashed continuity repair: it updates Smartisax to
  v0.6.10/versionCode 27, keeps the raw Binder MediaProjection token route and
  Smartisax-only services.jar policy, and uses
  `SurfaceTextureHelper.forceFrame()` cadence on the helper handler. Its smoke
  wrapper reuses the projection-texture profile flow and records device-side
  `continuityFrameRequests`, `continuityFrames`, `droppedFrames`, source
  frames, browser fps, bitrate, packet loss, memory, CPU, logcat, and
  DataChannel tap/swipe evidence. Live 1080/30 smoke proves the device-side pump
  counters continue, but browser decode still stalls at 26 frames, about
  0.83fps, so 1080/30 remains unaccepted and 1080/60 was not run. v0.portal5k.1
  is the previous live-flashed fresh-timestamp performance baseline: it updates Smartisax to
  v0.6.11/versionCode 28, keeps the v0.portal5k forceFrame cadence, and wraps
  retained texture frames with fresh `System.nanoTime()` timestamps before
  WebRTC capture. Its combined smoke evidence proves 1080/30 at 29.7fps and
  1080/60 at 60.15fps, both with H.264, 1080x2340, zero packet-loss delta,
  timestamp rewrite counters, and `smartisax-input` tap/swipe PASS. The
  v0.portal5k.1 latency/input smoke wrapper captures 1080/60 browser RVFC frame
  cadence plus DataChannel ack latency and established the presentation-gap
  baseline. v0.portal5l is the previous live flashed/read-only/smoke verified line: it updates Smartisax to
  v0.6.12/versionCode 29, adds a device-side touch-to-photon marker with
  marker metadata in status/acks, upgrades reverse control to
  touchStart/touchMove/touchEnd move-stream injection, and extends the Chrome
  smoke helper plus projection-texture wrapper with marker pixel detection and
  move-stream ack summaries. It is built, offline-verified, live-preflighted,
  flashed to B slot, booted, read-only verified, and smoke-proven at 1080/60:
  decoded fps 60.05, packet-loss delta 0, move-stream 30/30 ack, marker
  detection 2/2, and touch-to-photon p50 202.85ms/p95 286.59ms/max 295.9ms.
  v0.portal5m is the previous live flashed/read-only/smoke-proven latency/follow-rate line: it updates
  Smartisax to v0.6.13/versionCode 30, adds predictive marker status for Chrome
  smoke, compact `touchMoveBatch` acks, frame-aligned Portal move batching,
  injected-event move summaries, and throttled smoke logging. It is
  built/offline-verified/live-preflighted/flashed/read-only verified with APK hash
  `04b46c757e0cd0a0a5a2c58b1525ded25fc34a7dd13ff4d159123911f6bfad72`,
  system_b hash
  `b37ff12f06e5cc304810b7a718fc4b9b8dc501d11326a23bd7475ff463d1f7f2`,
  and sparse hash
  `8ea6074817bd376ae0d2d17aeaf1ddd9432c3fb294d63f914d6bc02b06b564e8`.
  It is smoke-proven at 1080/30 plus 1080/60 under
  `hard-rom/inspect/v0.portal5m-latency-follow-rate/portal-latency-follow-rate-smoke-live/`.
  The summary artifacts are `projection-texture-summary.md` and
  `projection-texture-summary.json`. 1080/30 passes at 29.81fps with
  packet-loss delta 0, injected move events 30/30, and touch-to-photon p50/p95
  192.4/193.03ms. 1080/60 passes at 59.94fps with packet-loss delta 0,
  injected move events 30/30, ping ack p50/p95 15.25/97.04ms, RVFC 52.28fps,
  and touch-to-photon p50/p95 154.45/158.1ms.
  The no-flash modern codec cascade evidence lives under
  `hard-rom/inspect/v0.portal5m-latency-follow-rate/portal-modern-codec-cascade-smoke-live/`.
  Its summary artifacts prove `PREFER_CODECS=AV1,H265,VP9,H264` selects AV1
  for both 1080/30 and 1080/60: 1080/30 passes at 29.98fps with T2P p95
  158.9ms, while 1080/60 passes at 57.34fps with packet-loss delta 0, RVFC
  45.65fps, 242 gaps over 34ms, and T2P p95 172.67ms.
  Forced H265 and VP9 no-flash codec evidence lives under
  `hard-rom/inspect/v0.portal5m-latency-follow-rate/portal-h265-forced-smoke-live/`
  and
  `hard-rom/inspect/v0.portal5m-latency-follow-rate/portal-vp9-forced-smoke-live/`.
  H265 negotiates but leaves browser video at 0x0 with decoded frames 0 on both
  profiles. VP9 displays 1080x2340 but decodes only 4.87fps at 1080/30 and
  5.34fps at 1080/60, with 1080/60 T2P p95 251.68ms.
  v0.portal5n-latency-budget-queue-collapse is the previous live
  flashed/read-only and smoke-tested latency-budget line. It is built from
  v0.portal5m, updates Smartisax to v0.6.14/versionCode 31, adds
  latest-frame-only projection queue collapse, `smartisax-input-move`
  low-retransmit move input, newest-point backpressure collapse, and smoke
  dual-channel status reporting. Build result:
  `PASS_BUILD_V0PORTAL5N_LATENCY_BUDGET_QUEUE_COLLAPSE`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5N_LATENCY_BUDGET_QUEUE_COLLAPSE`; live read-only
  result: `PASS_READ_ONLY_V0PORTAL5N_LATENCY_BUDGET_QUEUE_COLLAPSE`. APK hash
  `fb35e386649a51ff83eda8914fd02a9ffee3ca42c924d54b237b579c5abd6d7f`,
  system_b hash
  `502e18835efe3d7a085f5cd9ac3b063f02bf129128a6c3f0ae05c982f9f2fc70`,
  sparse hash
  `639e7cfcb7ca8c4f7a4b55fba18335714c291a9fa828951adf1e9363c7b11339`.
  Device read-only evidence is in
  `hard-rom/inspect/v0.portal5n-latency-budget-queue-collapse/verify-v0.portal5n-latency-budget-queue-collapse-device-read-only-20260624-162811.txt`;
  smoke evidence is in
  `hard-rom/inspect/v0.portal5n-latency-budget-queue-collapse/portal-latency-budget-queue-collapse-smoke-live/`.
  1080/60 improves gap count versus v0.portal5m but regresses T2P to
  p50/p95 205.85/208.6ms.
  v0.portal5o-input-frame-boost is the previous live flashed/read-only
  candidate; strict smoke was diagnostic rather than accepted. It updates Smartisax to
  v0.6.15/versionCode 32 and adds input-triggered urgent projection forceFrame
  boosts. Build result: `PASS_BUILD_V0PORTAL5O_INPUT_FRAME_BOOST`; offline
  result: `PASS_OFFLINE_IMAGE_V0PORTAL5O_INPUT_FRAME_BOOST`; live read-only
  result: `PASS_READ_ONLY_V0PORTAL5O_INPUT_FRAME_BOOST`; sparse
  hash `1886be1676562e91e5860b14faeaf00d3cd4534b86b001596ff6a9638f60eec4`;
  APK hash `05c30d70bd4ed0401d4cc7885f63086b8a511e30ee73f6deb2f49fb36860df38`;
  system_b hash
  `b0df788c0d548cb853c5ab22512e34499728b05876ac1f2ff3805d634d0af69d`.
  Offline evidence is in
  `hard-rom/inspect/v0.portal5o-input-frame-boost/verify-v0.portal5o-input-frame-boost-offline-image-20260624-165637.txt`.
  Device read-only evidence is in
  `hard-rom/inspect/v0.portal5o-input-frame-boost/verify-v0.portal5o-input-frame-boost-device-read-only-20260624-172412.txt`.
  Smoke evidence is in
  `hard-rom/inspect/v0.portal5o-input-frame-boost/portal-input-frame-boost-smoke-live/`,
  `hard-rom/inspect/v0.portal5o-input-frame-boost/portal-input-frame-boost-smoke-rerun-60/`,
  and
  `hard-rom/inspect/v0.portal5o-input-frame-boost/portal-input-frame-boost-smoke-rerun-30/`.
  The clean 1080/60 rerun passes with T2P p50/p95 133.25/138.51ms; the clean
  1080/30 rerun fails the strict gate at T2P p95 205.66ms and 911 gaps over
  34ms.
  v0.portal5p-dual-phase-input-boost is a previous live flashed/read-only
  candidate. It updates Smartisax to v0.6.16/versionCode 33, adds
  `touch-marker-injected` first-phase boost while retaining marker-drawn boost,
  and coalesces pending forceFrame work. Build result:
  `PASS_BUILD_V0PORTAL5P_DUAL_PHASE_INPUT_BOOST`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5P_DUAL_PHASE_INPUT_BOOST`; sparse hash
  `4c7d83fbb34a5f9aa76edd65cc5088f9decb190d341f1b14f302f46f86d1c1ef`;
  APK hash
  `d2c23440cdef4181422643520bfe5009f30b33df4903d6c65186a35f8961ac8a`;
  system_b hash
  `354246abbac4ee418b78580ef75682cc9bc089be067c57066a397e602821e58a`.
  Build evidence is in
  `hard-rom/inspect/v0.portal5p-dual-phase-input-boost/build-v0.portal5p-dual-phase-input-boost-20260624-175036.txt`;
  offline evidence is in
  `hard-rom/inspect/v0.portal5p-dual-phase-input-boost/verify-v0.portal5p-dual-phase-input-boost-offline-image-20260624-175325.txt`;
  device read-only evidence is in
  `hard-rom/inspect/v0.portal5p-dual-phase-input-boost/verify-v0.portal5p-dual-phase-input-boost-device-read-only-20260624-181204.txt`;
  live read-only result:
  `PASS_READ_ONLY_V0PORTAL5P_DUAL_PHASE_INPUT_BOOST`. It has no dedicated
  Portal smoke result before being superseded by v0.portal5s.
  v0.portal5r-refresh-rate-60-90hz is a built/offline/preflight-ready comparison
  candidate. It updates Smartisax to v0.6.18/versionCode 35, changes the primary
  profiles to 1080/60 plus 1080/90, raises runtime maxFps to 90 and max bitrate
  to 18000000, defaults to 1080p90, and adds boost-token-retain semantics on top
  of dual-phase input boost. Build result:
  `PASS_BUILD_V0PORTAL5R_REFRESH_RATE_60_90HZ`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5R_REFRESH_RATE_60_90HZ`; live preflight result:
  PASS. Sparse hash
  `157c4ebb19b5331b13492a464a0d15a0074f22af3b9ac8ff0894b48afeb6bfd7`;
  system_b hash
  `28f2a293b578e2c61c1c1aa5d4c566590f6d8d07c6c5f985e1e00965831dba86`;
  APK hash
  `29fbc902ada4f8b309c6c5f93fa8f9eaf0780fa7e9ddb6ddd2fe0a8514ed2a02`.
  Build evidence is in
  `hard-rom/inspect/v0.portal5r-refresh-rate-60-90hz/build-v0.portal5r-refresh-rate-60-90hz-20260624-183329.txt`;
  offline evidence is in
  `hard-rom/inspect/v0.portal5r-refresh-rate-60-90hz/verify-v0.portal5r-refresh-rate-60-90hz-offline-image-20260624-183650.txt`;
  live preflight evidence is in
  `hard-rom/inspect/v0.portal5r-refresh-rate-60-90hz/preflight-v0.portal5r-refresh-rate-60-90hz-20260624-184000.txt`.
  v0.portal5s-event-time-input-priority is a previous live flashed/read-only
  candidate and a diagnostic smoke failure. It updates Smartisax to
  v0.6.19/versionCode 36, keeps the 1080/60 plus 1080/90 target and
  boost-token-retain behavior, adds event-time-preserving move-stream input, and
  allows input-triggered projection frames to capture at a half-frame interval.
  Build result: `PASS_BUILD_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY`; offline
  result: `PASS_OFFLINE_IMAGE_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY`; live
  preflight result: PASS; live read-only result:
  `PASS_READ_ONLY_V0PORTAL5S_EVENT_TIME_INPUT_PRIORITY`. Sparse hash
  `b947a9456c11284810b1f976691c689d2158798c5c3ed504865bfaecb851a5f2`;
  system_b hash
  `2ae129226d18c10e7e7331bc01842305b7ab32d794b20aad7d92f00ba6d23191`;
  APK hash
  `32727a16d70c15cbd7f4c20e0e953bf59555a57b91e96a22df03b7386992d6f0`.
  Build evidence is in
  `hard-rom/inspect/v0.portal5s-event-time-input-priority/build-v0.portal5s-event-time-input-priority-20260624-185418.txt`;
  offline evidence is in
  `hard-rom/inspect/v0.portal5s-event-time-input-priority/verify-v0.portal5s-event-time-input-priority-offline-image-20260624-185706.txt`;
  live preflight evidence is in
  `hard-rom/inspect/v0.portal5s-event-time-input-priority/preflight-v0.portal5s-event-time-input-priority-20260624-185843.txt`;
  device read-only evidence is in
  `hard-rom/inspect/v0.portal5s-event-time-input-priority/verify-v0.portal5s-event-time-input-priority-device-read-only-20260624-191453.txt`;
  strict smoke diagnostic evidence is in
  `hard-rom/inspect/v0.portal5s-event-time-input-priority/portal-event-time-input-priority-smoke-live/`;
  clean single-profile 1080/60 rerun evidence is in
  `hard-rom/inspect/v0.portal5s-event-time-input-priority/portal-event-time-input-priority-smoke-rerun-60/`.
  The full smoke connects both H264 profiles with packet-loss delta 0,
  move-stream PASS, and input-frame-boost PASS, but fails RVFC/T2P gates; the
  clean 1080/60 rerun still fails RVFC 47.98fps and T2P p95 370.85ms.
  v0.portal5t-marker-burst-presentation is the next prepared, unflashed
  candidate. It updates Smartisax to v0.6.20/versionCode 37 on top of v0.portal5s
  and adds marker-visible burst input-priority frames after marker draw. Build
  result: `PASS_BUILD_V0PORTAL5T_MARKER_BURST_PRESENTATION`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5T_MARKER_BURST_PRESENTATION` with
  `smartisax_marker_burst_boost=ok`; live preflight result: PASS. Sparse hash
  `7417c6abcabca10dacf77d50e6dbdb84bf54414b074e23f7737c3ec929843bdd`;
  system_b hash
  `2ab359e6b6c16e0f0e8335c045df6a422c879c5da6b5294c334f815bbf76a1d6`;
  APK hash
  `4d55ff08af4e656b8a1218645b1e7e44746c550f126084d4b3ec165685606c31`.
  Build evidence is in
  `hard-rom/inspect/v0.portal5t-marker-burst-presentation/build-v0.portal5t-marker-burst-presentation-20260624-194836.txt`;
  offline evidence is in
  `hard-rom/inspect/v0.portal5t-marker-burst-presentation/verify-v0.portal5t-marker-burst-presentation-offline-image-20260624-195141.txt`.
  Live preflight evidence is in
  `hard-rom/inspect/v0.portal5t-marker-burst-presentation/preflight-v0.portal5t-marker-burst-presentation-20260624-195807.txt`
  and confirmed the exact flash phrase:
  `确认刷入 v0.portal5t-marker-burst-presentation B 槽`.
  v0.portal5u-burst-reschedule-presentation is a previous live flashed and
  read-only verified Portal latency candidate. It updates Smartisax to
  v0.6.21/versionCode 38 on top of v0.portal5s, keeps marker-visible burst
  input-priority frames, and reschedules burst frames until the projection
  frame pump accepts each request. Build result:
  `PASS_BUILD_V0PORTAL5U_BURST_RESCHEDULE_PRESENTATION`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5U_BURST_RESCHEDULE_PRESENTATION` with
  `smartisax_marker_burst_reschedule=ok`; confirmed preflight result: PASS;
  live result: `PASS_READ_ONLY_V0PORTAL5U_BURST_RESCHEDULE_PRESENTATION`.
  Sparse hash
  `4515ab16ff5dc443c91cd455c6361aeac3016fd728bc8abd9dbe70d3d7ac3db8`;
  system_b hash
  `7a0542497e74e323354bdfacd6ba366e929531d5e2678e995592fc6af796a5d5`;
  APK hash
  `31f75eb17d5800cf325e21d0d5e543d58b6234e5cbfc25422c0391a58bd3b6ed`.
  Evidence is in
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/build-v0.portal5u-burst-reschedule-presentation-20260624-201127.txt`,
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/verify-v0.portal5u-burst-reschedule-presentation-offline-image-20260624-201420.txt`,
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/preflight-v0.portal5u-burst-reschedule-presentation-20260624-confirmed-flash.txt`,
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/flash-v0.portal5u-burst-reschedule-presentation-20260624-202724.txt`,
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/boot-wait-v0.portal5u-burst-reschedule-presentation-20260624-203204.txt`,
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/verify-v0.portal5u-burst-reschedule-presentation-device-read-only-20260624-203234.txt`,
  and
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/post-flash-focus-hash-v0.portal5u-burst-reschedule-presentation-20260624-203300.txt`.
  Strict 1080/60 plus 1080/90 smoke evidence is in
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/portal-burst-reschedule-presentation-smoke-live/projection-texture-summary.md`
  and
  `hard-rom/inspect/v0.portal5u-burst-reschedule-presentation/portal-burst-reschedule-presentation-smoke-live/projection-texture-summary.json`.
  The strict smoke result is diagnostic FAIL: 1080/60 decoded 59.23fps but
  failed RVFC/gap/T2P gates; 1080/90 decoded 85.4fps and passed T2P p95 at
  134.61ms, but still failed RVFC/gap gates.
  v0.portal5v-presentation-cadence is a previous prepared, unflashed Portal
  candidate. It updates Smartisax to v0.6.22/versionCode 39, keeps
  v0.portal5u's marker-burst-reschedule behavior, adds browser receiver
  `playoutDelayHint=0`, `contentHint="motion"`, `disableRemotePlayback`, and
  carries RTC playout/drop/freeze diagnostics into the smoke summary. Build
  result: `PASS_BUILD_V0PORTAL5V_PRESENTATION_CADENCE`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5V_PRESENTATION_CADENCE` with
  `smartisax_presentation_cadence=ok`; read-only preflight passed in the
  current terminal run but was not persisted to a report file after the
  tee/redirect escalation was rejected. Sparse hash
  `9fbef52aee9ecffd146f0d949047107be6bbbfb1ca6ebb4762a00c7387742fff`;
  system_b hash
  `bd6f4f2d6a4ae028d1096a065942bfe7fb543b445c5b4ae6522cccec936470c5`;
  APK hash
  `3da3b86d74a4c78a3b98d0095bb7718a951f06c0feee96974d383207334e2509`.
  Evidence is in
  `hard-rom/inspect/v0.portal5v-presentation-cadence/build-v0.portal5v-presentation-cadence-20260624-210440.txt`
  and
  `hard-rom/inspect/v0.portal5v-presentation-cadence/verify-v0.portal5v-presentation-cadence-offline-image-20260624-210730.txt`.
  It was superseded by the flashed v0.portal5w quiet-presentation line.
  v0.portal5w-quiet-presentation is the previous live flashed and read-only
  verified Portal candidate. It updates Smartisax to v0.6.23/versionCode 40, keeps
  v0.portal5u/v0.portal5v presentation repairs, suppresses WebRTC DOM/log
  churn in the Portal and strict smoke page, gives the video path
  compositor/containment hints, and records RAF main-thread drift beside RVFC
  cadence. Build result: `PASS_BUILD_V0PORTAL5W_QUIET_PRESENTATION`; offline
  result: `PASS_OFFLINE_IMAGE_V0PORTAL5W_QUIET_PRESENTATION` with
  `smartisax_quiet_presentation=ok`; live result:
  `PASS_READ_ONLY_V0PORTAL5W_QUIET_PRESENTATION`; strict smoke result:
  diagnostic FAIL. Sparse hash
  `bf7145e79050d65cba96b1c0451c8b5c246957f8ef2fb9c513cc2966db77b593`;
  system_b hash
  `0c54440dcfde80c389dce5b40f854a94eae8e5c10f6c7634861063fbf35e823b`;
  APK hash
  `04c3e0ad784278ce82e31aecb89f9e1fe73b0dc312f9a6ad3f285ec5a6e1672d`.
  Build/offline evidence is in
  `hard-rom/inspect/v0.portal5w-quiet-presentation/build-v0.portal5w-quiet-presentation-20260624-212357.txt`
  and
  `hard-rom/inspect/v0.portal5w-quiet-presentation/verify-v0.portal5w-quiet-presentation-offline-image-20260624-212655.txt`.
  Live/strict-smoke evidence is in
  `hard-rom/inspect/v0.portal5w-quiet-presentation/flash-v0.portal5w-quiet-presentation-20260624-213938.txt`,
  `hard-rom/inspect/v0.portal5w-quiet-presentation/verify-v0.portal5w-quiet-presentation-device-read-only-20260624-214443.txt`,
  and
  `hard-rom/inspect/v0.portal5w-quiet-presentation/portal-quiet-presentation-smoke-live/projection-texture-summary.md`.
  It was superseded by the flashed v0.portal5x presenter-mode line.
  v0.portal5x-presenter-mode is the previous live flashed and read-only verified
  Portal candidate. It updates Smartisax to v0.6.24/versionCode 41 and adds a
  canvas presenter mode for comparing video RVFC, RAF, canvas draw cadence,
  canvas media-change cadence, and marker pixel detection source. Build result:
  `PASS_BUILD_V0PORTAL5X_PRESENTER_MODE`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5X_PRESENTER_MODE` with
  `smartisax_presenter_mode=ok`; live result:
  `PASS_READ_ONLY_V0PORTAL5X_PRESENTER_MODE`; strict smoke result:
  diagnostic FAIL. Sparse hash
  `3d72fe25ae50542edca42edc0472f70f16deef320fc5dde0a8ecc6eebfad2f6d`;
  system_b hash
  `3dcdd89252b549184cb41bc044de7d64377987fc5e91b65347b685afcd97aa09`;
  APK hash
  `370090e6647d3e07e3defb7a459295413a5465bc729ee9c08452c902225ac450`.
  Build/offline/preflight evidence is in
  `hard-rom/inspect/v0.portal5x-presenter-mode/build-v0.portal5x-presenter-mode-20260624-215835.txt`,
  `hard-rom/inspect/v0.portal5x-presenter-mode/verify-v0.portal5x-presenter-mode-offline-image-20260624-220414.txt`,
  and
  `hard-rom/inspect/v0.portal5x-presenter-mode/preflight-v0.portal5x-presenter-mode-20260624-222753.txt`.
  Live/strict-smoke evidence is in
  `hard-rom/inspect/v0.portal5x-presenter-mode/flash-v0.portal5x-presenter-mode-20260624-222855.txt`,
  `hard-rom/inspect/v0.portal5x-presenter-mode/boot-wait-v0.portal5x-presenter-mode-20260624-223332.txt`,
  `hard-rom/inspect/v0.portal5x-presenter-mode/verify-v0.portal5x-presenter-mode-device-read-only-20260624-223345.txt`,
  `hard-rom/inspect/v0.portal5x-presenter-mode/post-flash-focus-hash-v0.portal5x-presenter-mode-20260624-223402.txt`,
  and
  `hard-rom/inspect/v0.portal5x-presenter-mode/portal-presenter-mode-smoke-live/projection-texture-summary.md`.
  v0.portal5y-presentation-transport-pacing is the previous live flashed Portal
  candidate. It updates Smartisax to v0.6.25/versionCode 42, keeps the 5x
  canvas presenter feedback path, and paces 90Hz input semantics through 60fps
  WebRTC video presentation/transport with lower 1080/90 bitrate. Build result:
  `PASS_BUILD_V0PORTAL5Y_PRESENTATION_TRANSPORT_PACING`; offline result:
  `PASS_OFFLINE_IMAGE_V0PORTAL5Y_PRESENTATION_TRANSPORT_PACING` with
  `smartisax_presentation_transport_pacing=ok`; live preflight result: PASS;
  live read-only result:
  `PASS_READ_ONLY_V0PORTAL5Y_PRESENTATION_TRANSPORT_PACING`; strict smoke:
  diagnostic FAIL, not accepted.
  Sparse hash
  `c20ad88972c3395b848f5941b5bf12f8b5674d00da3cf9ccd6fca673ca28e4dc`;
  system_b hash
  `05454c258274b9c1f3b69bf875b60bd5deea6957d6dc6ed1e2a6e1ab0d04cfcd`;
  APK hash
  `17221eab917d34b4327ce59385765211c91335e59d89d959bf9aefd672dabbe6`.
  Build/offline/preflight evidence is in
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/build-v0.portal5y-presentation-transport-pacing-20260624-225845.txt`,
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/verify-v0.portal5y-presentation-transport-pacing-offline-image-20260624-230155.txt`,
  and
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/preflight-v0.portal5y-presentation-transport-pacing-20260624-231831.txt`.
  Flash/live/smoke evidence is in
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/flash-v0.portal5y-presentation-transport-pacing-20260624-231941.txt`,
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/boot-wait-v0.portal5y-presentation-transport-pacing-20260624-232452.txt`,
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/verify-v0.portal5y-presentation-transport-pacing-device-read-only-20260624-232732.txt`,
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/post-flash-focus-hash-v0.portal5y-presentation-transport-pacing-20260624-232744.txt`,
  and
  `hard-rom/inspect/v0.portal5y-presentation-transport-pacing/portal-presentation-transport-pacing-smoke-live/projection-texture-summary.md`.
  v0.portal5z-video-primary-roi-probe is the previous live flashed/read-only
  Portal candidate and current comparison boundary. It updates Smartisax to
  v0.6.26/versionCode 43, preserves
  v0.portal5y transport pacing, keeps video as the primary visible presenter in
  `PRESENTER_MODE=probe`, samples only the marker ROI for touch-to-photon
  detection, and enables RAF-driven pending-marker detection in the smoke
  harness. Strict smoke is diagnostic FAIL, not accepted. Build result:
  `PASS_BUILD_V0PORTAL5Z_VIDEO_PRIMARY_ROI_PROBE`;
  offline result: `PASS_OFFLINE_IMAGE_V0PORTAL5Z_VIDEO_PRIMARY_ROI_PROBE` with
  `smartisax_video_primary_roi_probe=ok` and
  `smartisax_presentation_transport_pacing=ok`; live preflight result: PASS;
  live read-only result: `PASS_READ_ONLY_V0PORTAL5Z_VIDEO_PRIMARY_ROI_PROBE`.
  Sparse hash
  `3a622e32a540c077075d0e9259a6245338e38a24b65342a09c212a6032fda0df`;
  system_b hash
  `930e1b9aad2794527d4e34871073654393fca8cd5636e9e1902851cf3a14a6ed`;
  APK hash
  `9a6280585c996d9f54d0fb03cd1c43b5d49d4487b40b52dbf1780cde76d718ad`.
  Build/offline evidence is in
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/build-v0.portal5z-video-primary-roi-probe-20260624-235135.txt`
  and
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/verify-v0.portal5z-video-primary-roi-probe-offline-image-20260624-235505.txt`.
  Live preflight evidence is in
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/preflight-v0.portal5z-video-primary-roi-probe-20260625-000755.txt`.
  Flash/live evidence is in
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/flash-v0.portal5z-video-primary-roi-probe-20260625-002052.txt`,
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/boot-wait-v0.portal5z-video-primary-roi-probe-20260625-002052.txt`,
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/verify-v0.portal5z-video-primary-roi-probe-device-read-only-20260625-002635.txt`,
  and
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/post-flash-focus-v0.portal5z-video-primary-roi-probe-20260625-002052.txt`.
  Strict and no-flash anti-throttle smoke evidence is in
  `hard-rom/inspect/v0.portal5z-video-primary-roi-probe/portal-video-primary-roi-probe-smoke-live/projection-texture-summary.md`;
  the original 1080/60 run failed RVFC, packet loss, gaps, and T2P p95 gates,
  while 1080/90 kept packet-loss delta 0 and RAF near 60fps but still failed
  RVFC, gaps, and T2P p95 gates. The later anti-throttle rerun kept
  packet-loss delta 0 and RAF near 60fps on both profiles, classifying the
  original 22s-class gap as host-window/background noise, but still failed video
  RVFC cadence and marker-visible T2P tail gates.
  `tools/r2-live-flash-v0.portal5z-video-primary-roi-probe.sh` is the
  post-confirmation flash/verify harness used for the accepted B-slot run.
  The host-side Chrome smoke now avoids duplicate touch-to-photon pixel
  sampling from RVFC when RAF detection is enabled; 5z probe smoke samples the
  marker through the RAF ROI path and keeps RVFC for cadence/gap metrics. The
  harness also defaults to Chrome anti-throttle flags, fixed window sizing,
  page lifecycle/RVFC/RAF timeline fields, compact summary JSON, and an
  unvalidated Chrome foreground activation attempt for the next fresh pairing
  run.
  v0.portal6a-marker-draw-sync is the previous live flashed/read-only Portal
  candidate. It updates Smartisax to v0.6.27/versionCode 44 and triggers marker
  capture boost plus marker burst after the marker view reaches Android draw,
  preserving v0.portal5z video-primary ROI probe and 60/90Hz transport pacing.
  Build result is `PASS_BUILD_V0PORTAL6A_MARKER_DRAW_SYNC`; offline result is
  `PASS_OFFLINE_IMAGE_V0PORTAL6A_MARKER_DRAW_SYNC` with
  `smartisax_marker_draw_sync=ok`; live preflight and read-only verification
  pass. Sparse hash
  `b8d2bbe12c3d889fa83963ea8d8e31e2a47b2a460c075d11b29ba4d1676fcc2a`;
  system_b hash
  `a35a82f194eb06a7f6199562ff87ea9db4f5875ccf536275993d864fc917f5a0`;
  APK hash
  `25a4c9f05e61983911761668915cdfd9af6b0fe7e61cd68cd89bc8e7866ecd70`.
  Evidence is in
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/build-v0.portal6a-marker-draw-sync-20260625-011529.txt`,
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/verify-v0.portal6a-marker-draw-sync-offline-image-20260625-012011.txt`,
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/preflight-v0.portal6a-marker-draw-sync-20260625-012222.txt`,
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/flash-v0.portal6a-marker-draw-sync-20260625-013740.txt`,
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/boot-wait-v0.portal6a-marker-draw-sync-20260625-013740.txt`,
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/verify-v0.portal6a-marker-draw-sync-device-read-only-20260625-014307.txt`,
  and
  `hard-rom/inspect/v0.portal6a-marker-draw-sync/post-flash-focus-v0.portal6a-marker-draw-sync-20260625-013740.txt`.
  `tools/r2-live-flash-v0.portal6a-marker-draw-sync.sh` is the
  post-confirmation flash/verify harness used for the B-slot run. Strict
  1080/60 plus 1080/90 smoke is still pending.
  v0.portal6b-draw-urgent-boost is the current live flashed/read-only Portal
  candidate. It adds a draw-urgent input boost path on top of 6a so
  `touch-marker-drawn-urgent` can bypass the ordinary half-frame input boost
  spacing while preserving marker draw-sync diagnostics and burst retry limits.
  Build result is
  `PASS_BUILD_V0PORTAL6B_DRAW_URGENT_BOOST`; offline result is
  `PASS_OFFLINE_IMAGE_V0PORTAL6B_DRAW_URGENT_BOOST` with
  `smartisax_draw_urgent_boost=ok`; live result is
  `PASS_READ_ONLY_V0PORTAL6B_DRAW_URGENT_BOOST`. Sparse hash
  `057930f125ce07e5fc3c2940af4ac348102df7e8acbfe83d6a25467e4c3ee235`;
  system_b hash
  `3956bfcd006b5448008088af4fc839847cdd85ca4c12ada77bc436c29237161a`;
  APK hash
  `6484d7eb882f04e7a73ae7fb8539c070697abbd1235f1a598894b07230f9cc34`.
  Build/offline evidence is in
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/build-v0.portal6b-draw-urgent-boost-20260625-020852.txt`
  and
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/verify-v0.portal6b-draw-urgent-boost-offline-image-20260625-021233.txt`.
  Flash/boot/read-only evidence is in
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/flash-v0.portal6b-draw-urgent-boost-20260625-022145.txt`,
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/boot-wait-v0.portal6b-draw-urgent-boost-20260625-022145.txt`,
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/verify-v0.portal6b-draw-urgent-boost-device-read-only-20260625-022709.txt`,
  and
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/post-flash-focus-v0.portal6b-draw-urgent-boost-20260625-022145.txt`.
  `tools/r2-hardrom-build-v0.portal6b-draw-urgent-boost.sh`,
  `tools/r2-verify-v0.portal6b-draw-urgent-boost.sh`,
  `tools/r2-portal6b-draw-urgent-boost-smoke.sh`, and
  `tools/r2-live-flash-v0.portal6b-draw-urgent-boost.sh` are the 6b helper
  entrypoints. Strict 1080/60 plus 1080/90 smoke is diagnostic FAIL, not
  accepted, but proves marker draw-sync and draw-urgent counters. Summary:
  `hard-rom/inspect/v0.portal6b-draw-urgent-boost/portal-draw-urgent-boost-smoke-live/projection-texture-summary.md`.
  v0.portal6c-visible-screenbox is the previous live flashed/read-only Portal
  UI visibility repair on top of 6b. It keeps the draw-urgent/WebRTC/input path
  and repairs the real Portal `.screenBox` so Chrome/Safari do not clip the
  video surface after pairing. Sparse hash
  `df7912827b4201bcff601edcc300fe79654ffdc571dda860272eb6485a247a9a`;
  system_b hash
  `0854bd2deb455759baee791b4860f8be2cf1686675d32e662126c913a1c76c7c`;
  APK hash
  `d90161ce3a15a88b272ade654fdef131597114eb79a1f00ef32ca1d7cb12fe46`.
  Build/offline evidence:
  `hard-rom/inspect/v0.portal6c-visible-screenbox/build-v0.portal6c-visible-screenbox-20260625-134721.txt`
  and
  `hard-rom/inspect/v0.portal6c-visible-screenbox/verify-v0.portal6c-visible-screenbox-offline-image-20260625-135024.txt`.
  Flash/boot/read-only evidence:
  `hard-rom/inspect/v0.portal6c-visible-screenbox/flash-v0.portal6c-visible-screenbox-20260625-152802.txt`,
  `hard-rom/inspect/v0.portal6c-visible-screenbox/boot-wait-v0.portal6c-visible-screenbox-20260625-152802.txt`,
  `hard-rom/inspect/v0.portal6c-visible-screenbox/verify-v0.portal6c-visible-screenbox-device-read-only-20260625-153326.txt`,
  and
  `hard-rom/inspect/v0.portal6c-visible-screenbox/post-flash-focus-v0.portal6c-visible-screenbox-20260625-152802.txt`.
  `tools/r2-hardrom-build-v0.portal6c-visible-screenbox.sh`,
  `tools/r2-verify-v0.portal6c-visible-screenbox.sh`, and
  `tools/r2-live-flash-v0.portal6c-visible-screenbox.sh` are the 6c helper
  entrypoints. A real Portal Chrome visual smoke on 6c connected but returned
  flat black pixels because the R2 display was asleep/off.
  v0.portal6d-display-wake-guard is the current live flashed/read-only Portal
  display wake repair on top of 6c. It adds `WAKE_LOCK`, ShellActivity
  screen-on/turn-screen-on behavior, and a `Smartisax:PortalWebRtc` display
  wake lock for active WebRTC runtime sessions. Sparse hash
  `48f3329f3da1496e9c27ce3de7ff2f08fdd4d589f37ee5feaab74b8782bba0e4`;
  system_b hash
  `3c791ba52af85a8a6ed4bf7adc4ff7c194c1577f8782d98a945e063a6bb62718`;
  APK hash
  `30e7cab2c2900763a3b9e695c17ee37cd5601c4683f823aa570637bdc4d169b8`.
  Build/offline evidence:
  `hard-rom/inspect/v0.portal6d-display-wake-guard/build-v0.portal6d-display-wake-guard-20260625-155951.txt`
  and
  `hard-rom/inspect/v0.portal6d-display-wake-guard/verify-v0.portal6d-display-wake-guard-offline-image-20260625-160303.txt`.
  Flash/boot/read-only/display evidence:
  `hard-rom/inspect/v0.portal6d-display-wake-guard/flash-v0.portal6d-display-wake-guard-20260625-161338.txt`,
  `hard-rom/inspect/v0.portal6d-display-wake-guard/boot-wait-v0.portal6d-display-wake-guard-20260625-161338.txt`,
  `hard-rom/inspect/v0.portal6d-display-wake-guard/verify-v0.portal6d-display-wake-guard-device-read-only-20260625-161902.txt`,
  `hard-rom/inspect/v0.portal6d-display-wake-guard/post-flash-focus-v0.portal6d-display-wake-guard-20260625-161338.txt`,
  and
  `hard-rom/inspect/v0.portal6d-display-wake-guard/display-wake-state-after-flash-20260625-161938.txt`.
  `tools/r2-hardrom-build-v0.portal6d-display-wake-guard.sh`,
  `tools/r2-verify-v0.portal6d-display-wake-guard.sh`, and
  `tools/r2-live-flash-v0.portal6d-display-wake-guard.sh` are the 6d helper
  entrypoints. Real Portal visual smoke on 6d now passes. Evidence:
  `hard-rom/inspect/v0.portal6d-display-wake-guard/portal-real-ui-visual-smoke-live/real-portal-visual-smoke-v0.portal6d-display-wake-guard-20260625-083527.json`,
  `hard-rom/inspect/v0.portal6d-display-wake-guard/portal-real-ui-visual-smoke-live/real-portal-visual-smoke-v0.portal6d-display-wake-guard-20260625-083527.png`,
  and
  `hard-rom/inspect/v0.portal6d-display-wake-guard/display-wake-state-after-real-portal-smoke-20260625-083527.txt`.
  v0.portal6e-encoder-transport-burst is the previous live flashed/read-only
  Portal line. It is the first returned 1080/60 plus 1080/90 performance
  candidate after 6d real
  Portal visibility PASS, targeting 1080/60 packet loss and encoder/transport
  burst before RVFC/T2P work. It updates Smartisax to v0.6.31/versionCode 48,
  clamps the 1080p60/90 sender bitrate window, applies `MAINTAIN_FRAMERATE`,
  and late-starts the projection frame pump after local SDP while preserving
  the 6d display wake guard. Sparse hash
  `5c1a6d9885dcdff1f9ee0b7277419dc2280b4320cfe3551bd68e901eb4663f83`;
  system_b hash
  `04cfe9746848f5daee752a13efb18ba3cb938d8c7969d5b48333c965f319a6b7`;
  APK hash
  `90421ef5613f5dafa5491735848ebe6588e2fe5d95ffb79929bfe00329a921ef`.
  Build/offline/preflight/flash/read-only evidence:
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/build-v0.portal6e-encoder-transport-burst-20260625-165309.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-offline-image-20260625-170017.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/preflight-v0.portal6e-encoder-transport-burst-20260625-170235.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/flash-v0.portal6e-encoder-transport-burst-20260625-171510.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/boot-wait-v0.portal6e-encoder-transport-burst-20260625-171510.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/verify-v0.portal6e-encoder-transport-burst-device-read-only-20260625-172037.txt`,
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/post-flash-focus-v0.portal6e-encoder-transport-burst-20260625-171510.txt`,
  and
  `hard-rom/inspect/v0.portal6e-encoder-transport-burst/display-window-state-after-flash-20260625-172135.txt`.
  `tools/r2-hardrom-build-v0.portal6e-encoder-transport-burst.sh`,
  `tools/r2-verify-v0.portal6e-encoder-transport-burst.sh`,
  `tools/r2-live-flash-v0.portal6e-encoder-transport-burst.sh`, and
  `tools/r2-portal6e-encoder-transport-burst-smoke.sh` are the 6e helper
  entrypoints. Strict smoke with code `666132` is diagnostic FAIL but proves
  1080/60 packetLossDelta 0, leading to the current 6f presentation-tail line.
  v0.portal6f-presentation-tail-cadence is the current live flashed/read-only
  Portal line. It starts from 6e and targets RVFC/presentation cadence plus
  1080/60 marker-visible T2P tail with full-frame marker-tail cadence, 1200ms
  marker visibility, and receiver jitterBufferTarget/RVFC cadence-lite
  diagnostics. Sparse hash
  `d0bd5eb4653d8e019fdfea6fbe7815895c9ab57b87bc441b38ed7b8112465d9a`;
  system_b hash
  `0cd94324a512d5cb1fd9eed87f7aa82b49e586062033c08a81a96e7c0ab937b2`;
  APK hash
  `98b517b37cfcccce93f0724464b3d874c911efe9a6166e9775c345bceffb0db5`.
  Build/offline/preflight/flash/read-only evidence:
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/build-v0.portal6f-presentation-tail-cadence-20260625-190344.txt`,
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/verify-v0.portal6f-presentation-tail-cadence-offline-image-20260625-190751.txt`,
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/preflight-v0.portal6f-presentation-tail-cadence-20260625-191141.txt`,
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/flash-v0.portal6f-presentation-tail-cadence-20260625-202928.txt`,
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/boot-wait-v0.portal6f-presentation-tail-cadence-20260625-202928.txt`,
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/verify-v0.portal6f-presentation-tail-cadence-device-read-only-20260625-203453.txt`,
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/post-flash-focus-v0.portal6f-presentation-tail-cadence-20260625-202928.txt`,
  and
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/display-window-state-after-flash-20260625-203526.txt`.
  Safari fallback strict smoke evidence:
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-safari-176725/projection-texture-summary.md`
  and
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-safari-176725/projection-texture-summary.json`.
  In-app browser Chrome-side cadence smoke evidence:
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-iab-998599/projection-texture-summary.md`
  and
  `hard-rom/inspect/v0.portal6f-presentation-tail-cadence/portal-presentation-tail-cadence-smoke-iab-998599/projection-texture-summary.json`.
  `tools/r2-hardrom-build-v0.portal6f-presentation-tail-cadence.sh`,
  `tools/r2-verify-v0.portal6f-presentation-tail-cadence.sh`,
  `tools/r2-live-flash-v0.portal6f-presentation-tail-cadence.sh`, and
  `tools/r2-portal6f-presentation-tail-cadence-smoke.sh` are the 6f helper
  entrypoints. Safari fallback strict smoke with code `176725` passed both
  1080/60 and 1080/90 H264 1080x2340 visibility/control/T2P gates. In-app
  browser Chrome-side smoke with code `998599` passed 1080/90 and failed only
  the 1080/60 RVFC gap gate: `frameGapsOver34ms=123` against `<=60`.
  v0.portal6g-rvfc-media-tail is the current live flashed/read-only follow-up
  for that 1080/60 RVFC/media callback tail gate. It starts from 6f, updates
  Smartisax to v0.6.33/versionCode 50, makes the 1080/60 smoke profile
  explicitly preserve `inputRefreshHz=90`, de-phases the exact 1080p60 sender
  to 59fps, narrows the 60Hz sender window to 7Mbps, spaces continuity
  forceFrame cadence at the full media-frame interval, and adds
  `mediaCallbackTailRepair`/`mediaCallbackTailFrameSpacingMs` diagnostics.
  Sparse hash
  `d3a938546f197e54ea1f7c08bf300b8d61bf91b9c389bca92a9ddfa018a038fb`;
  system_b hash
  `941c660259f32270eaf4e3a8a5778b8518d4035e0f5efb73a8b704fd7d4b4241`;
  APK hash
  `442276dfaf1e70ecf0209818ed61b207bae72194fc490f8c601471b6a43f9f6a`.
  Valid build/offline/preflight/flash/read-only evidence:
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/build-v0.portal6g-rvfc-media-tail-20260629-202323.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-offline-image-20260629-202657.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/preflight-v0.portal6g-rvfc-media-tail-20260629-202908.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/flash-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/boot-wait-v0.portal6g-rvfc-media-tail-20260629-203737.txt`,
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/verify-v0.portal6g-rvfc-media-tail-device-read-only-20260629-204302.txt`,
  and
  `hard-rom/inspect/v0.portal6g-rvfc-media-tail/display-window-state-after-flash-20260629-204340.txt`.
  `tools/r2-hardrom-build-v0.portal6g-rvfc-media-tail.sh`,
  `tools/r2-verify-v0.portal6g-rvfc-media-tail.sh`,
  `tools/r2-live-flash-v0.portal6g-rvfc-media-tail.sh`, and
  `tools/r2-portal6g-rvfc-media-tail-smoke.sh` are the 6g helper entrypoints.
  Flash used the exact phrase `确认刷入 v0.portal6g-rvfc-media-tail B 槽`;
  next, use a fresh code with the 6g strict smoke to
  test whether 1080/60 `frameGapsOver34ms` is <=60.
  The superseded local v0.portal5j, v0.portal5j.1, and v0.portal5j.2 sparse
  images plus old v0.portal5k-through-v0.portal5o raw system_b intermediates
  were removed after their evidence was retained and free space was needed for
  the v0.portal5r build.

tools/r2-build-services-kg1-skip-keyguard-jar.sh
tools/r2-hardrom-build-v0.kg1-smartisax-skip-keyguard.sh
tools/r2-hardrom-pack-super-v0.kg1-smartisax-skip-keyguard.sh
tools/r2-verify-v0.kg1-smartisax-skip-keyguard.sh
  Offline builders and verifier for the v0.kg1 Smartisax skip-keyguard
  candidate. They start from live-proven v0.pm1, replace only
  `/system/framework/services.jar`, preserve pm1's PackageManager policy, add
  a KeyguardServiceDelegate hook that goes through the stock
  setKeyguardEnabled(false) path, rebuild system_b FEC, pack a sparse super,
  and verify the live device read-only after flashing.

tools/r2-hardrom-build-v0.usb1-no-smartisan-cdrom.sh
tools/r2-verify-v0.usb1-no-smartisan-cdrom.sh
hard-rom/build/super-otatrust-v0.usb1-no-smartisan-cdrom.sparse.img
hard-rom/inspect/v0.usb1-no-smartisan-cdrom/
  Offline builder, verifier, flashable sparse image, and evidence for the
  vendor_b-only Smartisan virtual CD-ROM removal candidate. It starts from
  live-proven v0.kg1, keeps `/vendor/etc/cdrom_install.iso` inert, removes
  `mass_storage.0` from vendor USB configfs symlink bodies, preserves ADB/MTP
  routes, rebuilds vendor_b FEC, and is live-verified on B slot. The macOS
  volume check shows no Smartisan transfer-tool volume after flashing.

tools/r2-hardrom-build-v0.usb2-physical-cdrom-iso-delete.sh
tools/r2-verify-v0.usb2-physical-cdrom-iso-delete.sh
hard-rom/build/super-otatrust-v0.usb2-physical-cdrom-iso-delete.sparse.img
hard-rom/inspect/v0.usb2-physical-cdrom-iso-delete/
  Offline builder, verifier, flashable sparse image, and evidence for the
  v0.usb2 physical Smartisan transfer-tool ISO cleanup candidate. It starts
  from live-proven v0.usb1, removes `/vendor/etc/cdrom_install.iso`, zeroes old
  ISO blocks that remain free after deletion, preserves any blocks reassigned
  to existing files, rebuilds vendor_b FEC, and is live-verified on B slot. The
  macOS volume check shows no Smartisan transfer-tool volume after flashing.

tools/r2-system-mod-readiness-audit.py
  Read-only top-level readiness audit for native dark-mode integration and
  English/Chinese-only ROM hard-pruning. It writes a TSV manifest and markdown
  report that explicitly separate offline proof from missing live gates and
  not-yet-achieved full-ROM language pruning.

tools/r2-system-modification-route-audit.py
  Read-only route audit that converts requested system modifications into
  current hard-ROM change classes, static risk levels, existing evidence,
  required live/no-op gates, and next safe steps. Canonical output goes to
  `docs/research/system-modification-route-audit.md`; ad hoc package queries
  are written under `hard-rom/inspect/system-modification-route-audit/`.

tools/r2-textboom-ocr-backend-map.py
  Read-only static backend mapper for TextBoom and Sidebar OCR modernization.
  It verifies focused JADX call points, checks the current live TextBoom APK for
  `tt_general_ocr_v1.0.model` and `libsmash_ocr_lib.so`, then writes
  `docs/research/textboom-ocr-backend-map.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/textboom-ocr-backend-map.tsv`,
  and `hard-rom/inspect/textboom-ocr-backend-map/textboom-ocr-backend-map.json`.

tools/r2-sidebar-font-ocr-removal-audit.py
  Read-only Sidebar font OCR removal mapper. It writes
  `docs/research/sidebar-font-ocr-removal-plan.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/sidebar-font-ocr-removal-plan.tsv`,
  and
  `hard-rom/inspect/sidebar-font-ocr-removal-plan/sidebar-font-ocr-removal-plan.json`.

tools/r2-ocr-ppocr-replacement-plan.py
  Read-only full-deletion and PP-OCR replacement planner. It scans the current
  v0.38 decoded Sidebar APK, the TextBoom live decode, and TextBoom JADX
  sources, then writes `docs/research/ocr-ppocr-replacement-plan.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/ocr-ppocr-replacement-plan.tsv`,
  and
  `hard-rom/inspect/ocr-ppocr-replacement-plan/ocr-ppocr-replacement-plan.json`.
  It is intentionally not a ROM builder or flash tool.

tools/r2-textboom-ppocr-mapping.py
  Pure PP-OCR to TextBoom OCR-result mapping helpers. It accepts common
  PaddleOCR result shapes, normalizes text, clamps quadrilateral boxes to an
  optional bitmap size, filters low-confidence/empty lines, sorts in reading
  order, and emits TextBoom-compatible `{text, rect, score}` rows plus
  `OcrInfo`-shaped `{mText, mRect, score}` rows. It has no Android, APK,
  native-library, filesystem, or device dependency and is the tested boundary
  for the future `LocalPpOcrApi` adapter.

tools/r2-textboom-ppocr-benchmark.py
  Offline benchmark harness for saved TextBoom OCR predictions. It consumes a
  labeled screenshot corpus plus PP-OCR/CsOcr prediction JSON, reuses the pure
  mapping helper, scores line recall, character error rate, matched-box IoU,
  latency, and PSS memory, then writes JSON/Markdown/TSV reports. It does not
  run an OCR model, patch TextBoom, build a ROM image, touch a device, or
  authorize deletion of TextBoom's CsOcr/CamScanner code by itself.

tools/r2-textboom-ppocr-corpus-template.py
  Offline corpus-template generator for the TextBoom PP-OCR benchmark. It reads
  local PNG/JPEG screenshots, records image ids and sizes, preserves existing
  manual `expected` labels when requested, and writes the JSON corpus skeleton
  consumed by `tools/r2-textboom-ppocr-benchmark.py`. It does not capture from
  a device or run OCR.

tools/r2-textboom-ui-result-baseline.py
  Offline TextBoom result-page baseline extractor. It parses a saved
  UIAutomator XML dump, extracts OCR result chips rendered by TextBoom, records
  title/total-size text, normalizes localized punctuation labels, and writes a
  JSON baseline for user-visible legacy CsOcr/CamScanner output. It is not raw
  CamScanner `RESPONSE_DATA` and does not touch a device, APK, or ROM image.

tools/r2-textboom-ocr-compare-report.py
  Offline comparison report generator for saved OCR evidence. It aggregates
  official PP-OCR result JSON, standalone CsOcr/CamScanner probe JSON, and
  TextBoom UI-result baseline JSON, then writes JSON/Markdown/TSV reports with
  quality, latency, and memory fields. It does not run OCR or touch a device.

tools/r2-android-sdk-install.sh
tools/r2-android-sdk-env.sh
  Project-local Android SDK/NDK bootstrap for the TextBoom PP-OCR benchmark
  route. The installer downloads commandline-tools and installs platform-tools,
  android-30/android-35 platform jars, build-tools 35.0.1, CMake 3.22.1, and
  NDK 27.2 under ignored `third_party/android-sdk`. Source the env script
  before local Android builds so Java, sdkmanager, adb, aapt2, d8, CMake, and
  NDK clang resolve from the same local toolchain. The env script now prefers
  project-local Temurin JDK 17 when present because Homebrew OpenJDK 26 is too
  new for the current Android Gradle/Kotlin toolchain.

tools/r2-fetch-local-jdk17.sh
  Downloads a project-local Temurin JDK 17 into ignored
  `third_party/_downloads/jdk/temurin-17/` for Gradle/Kotlin Android builds.
  This avoids changing global Homebrew Java state and lets
  `tools/r2-android-sdk-env.sh` pick a compatible JDK automatically.

tools/r2-build-services-pm-noop-jar.sh
hard-rom/build/framework/services-pm-noop-roundtrip.jar
hard-rom/inspect/v0.pm0-services-jar-noop/
  Offline PackageManager framework gate. The script decodes stock
  `/system/framework/services.jar`, rebuilds it without smali edits, merges only
  rebuilt `classes.dex` and `classes2.dex` into the stock jar shell, zipaligns
  the result, verifies DEX and ZIP structure, and copies key PMS smali evidence.
  It does not build a system image, build a super image, flash, reboot, or touch
  the live R2.

tools/r2-hardrom-build-v0.pm0-services-jar-noop.sh
tools/r2-verify-v0.pm0-services-jar-noop.sh
tools/r2-hardrom-pack-super-v0.pm0-services-jar-noop.sh
hard-rom/build/super-otatrust-v0.pm0-services-jar-noop.sparse.img
  Offline system_b image gate for the PackageManager framework no-op line. The
  builder starts from live-proven v0.43e, audits block ownership for stock
  `services.jar` and stale arm64 `services.art/odex/vdex`, removes those public
  paths as narrow shared-block exceptions, writes the no-op services.jar,
  rebuilds system_b AVB/FEC roots=2, and records
  `PASS_BUILD_V0PM0_SERVICES_JAR_NOOP_SYSTEM_IMAGE`. The verifier records
  `PASS_OFFLINE_IMAGE_V0PM0_SERVICES_JAR_NOOP`. The packer then builds the
  flashable sparse super without a raw 10 GiB super, records
  `PASS_PACK_SUPER_V0PM0_SERVICES_JAR_NOOP`, and verifies all sparse partition
  slice hashes. The B-slot flash and read-only verifier passed after exact user
  confirmation; the live report is
  `hard-rom/inspect/v0.pm0-services-jar-noop/verify-v0.pm0-services-jar-noop-device-read-only-20260622-134433.txt`.

tools/r2-build-services-pm1-cache-allowlist-jar.sh
tools/r2-hardrom-build-v0.pm1-pms-cache-allowlist.sh
tools/r2-hardrom-pack-super-v0.pm1-pms-cache-allowlist.sh
tools/r2-verify-v0.pm1-pms-cache-allowlist.sh
hard-rom/build/framework/services-pm1-cache-allowlist.jar
hard-rom/build/super-otatrust-v0.pm1-pms-cache-allowlist.sparse.img
hard-rom/inspect/v0.pm1-pms-cache-allowlist/
  First real PackageManager behavior-policy candidate after the live-proven
  v0.pm0 services.jar no-op. The JAR builder adds
  `com.android.server.pm.SmartisaxPackagePolicy` and changes only
  `ParallelPackageParser.parsePackage(File,int)` so allowlisted
  Smartisax-managed paths bypass PackageParser cache reads. The system image
  is built from the v0.pm0 sparse `system_b` slice at
  `system_b=8306688:6217336`, replaces only `/system/framework/services.jar`,
  keeps public services preopt absent, and rebuilds AVB/FEC roots=2. The sparse
  packer rewrites only `system_b` on top of v0.pm0 sparse. Current hashes:
  services.jar `84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40`,
  system_b `8b22c971bfb63d506104df3096031b6524aa738952294fb294aaac1fac98228c`,
  sparse super `dd64f8a741dc434763bf6d9518bd0ee74c33cbcf3471121056883f591fc34f52`.
  Offline verifier records `PASS_OFFLINE_IMAGE_V0PM1_PMS_CACHE_ALLOWLIST`; live
  preflight passed, the B-slot flash wrote 9/9 sparse chunks, and live read-only
  verifier records `PASS_READ_ONLY_V0PM1_PMS_CACHE_ALLOWLIST`. Flash and live
  reports are
  `hard-rom/inspect/v0.pm1-pms-cache-allowlist/flash-v0.pm1-pms-cache-allowlist-20260622-144550.txt`
  and
  `hard-rom/inspect/v0.pm1-pms-cache-allowlist/verify-v0.pm1-pms-cache-allowlist-device-read-only-20260622-145034.txt`.

tools/r2-build-textboom-ppocr-bench-apk.sh
apps/TextBoomPpOcrBench/
  Historical standalone Android benchmark APK for the TextBoom PP-OCR route.
  It builds `com.smartisax.ocrbench` with the local SDK through
  javac/d8/aapt2, signs it with the project APK key, verifies
  apksigner/zipalign/unzip/aapt badging, and enforces the Android 11
  `resources.arsc` STORED plus 4-byte alignment rule. It now packages a
  Paddle Lite + PP-OCR mobile v2 slim native pipeline and has live R2 evidence,
  but it is no longer the selected final route because the current candidate is
  official `ppocr-sdk` + PP-OCRv6 small + ONNX Runtime Android.

tools/r2-build-textboom-ppocr-official-bench-apk.sh
apps/TextBoomPpOcrOfficialBench/
  Current no-ROM benchmark APK for the formal TextBoom PP-OCR replacement
  route. The builder generates a temporary Gradle project under
  `hard-rom/build`, reuses official `deploy/ppocr-android/ppocr-sdk`, packages
  PP-OCRv6 small using the official asset layout, aligns to
  onnxruntime-android 1.21.1 and OpenCV 4.5.3, signs the APK with the project
  APK key, and verifies apksigner/zipalign/unzip/aapt badging plus
  `resources.arsc` STORED/4-byte alignment. The output package is
  `com.smartisax.ocrbench.officialbench`; it is a benchmark harness only and
  does not mutate TextBoom, ROM images, or system packages.

tools/r2-textboom-ppocr-bench-live-smoke.sh
  Explicit-confirmation live smoke helper for the standalone benchmark APK. It
  installs `TextBoomPpOcrBench.apk`, pushes the captured `imageboom.jpg` into
  the app-specific external files directory, starts
  `com.smartisax.ocrbench/.MainActivity`, pulls `last-result.json`, and checks
  `PP_OCR_READY`, 1080x773 dimensions, and SHA-256 equality. It modifies the
  live device by installing an APK and writing app-specific external files, so
  run it only after user approval and with escalated USB/ADB execution. After
  the APK has been installed and authorized once, set `SKIP_INSTALL=1` to
  verify the installed package and rerun the smoke without triggering another
  install.

tools/r2-textboom-ppocr-official-bench-live-smoke.sh
  Explicit-confirmation live smoke helper for the official PP-OCRv6 small
  benchmark APK. It installs or reuses `TextBoomPpOcrOfficialBench.apk`, pushes
  a local PNG/JPEG into the app-specific external files directory, starts
  `com.smartisax.ocrbench.officialbench/.MainActivity`, pulls
  `last-result.json`, and checks `result=OK`, positive image dimensions, image
  SHA, and nonzero OCR line count. It writes only app-specific files and
  installs a test APK when `SKIP_INSTALL=0`, so run it only after user approval
  and with escalated USB/ADB execution.

tools/r2-textboom-ppocr-official-corpus-live.sh
  Live-device corpus runner for the official PP-OCRv6 small benchmark APK. It
  reuses the single-image live smoke helper across `imageboom.jpg` plus selected
  R2 screenshots, aggregates per-sample results into
  `ppocr-official-corpus-results.json`, and records latency, detection time,
  recognition time, line count, and PSS memory. It touches only app-specific
  benchmark files and requires escalated USB/ADB execution.

tools/r2-textboom-csocr-baseline-live.sh
  Live-device standalone CamScanner OpenAPI probe. It invokes
  `com.intsig.camscanner.ACTION_OCR` from the benchmark package using the
  TextBoom-extracted OpenAPI key and records raw `RESPONSE_DATA` if returned,
  parsed CsOcr/TextBoom-shaped output, latency, and meminfo. Current evidence
  shows CamScanner rejects this standalone caller with response code 4003, so a
  raw legacy baseline requires TextBoom-internal instrumentation if still needed.

tools/r2-textboom-live-ocr-capture.sh
  Live-device TextBoom image-OCR capture helper. After explicit approval and
  with the phone unlocked, it records boot/package/resolver/focus state,
  captures screenshots and UI dumps, starts
  `smartisanos.intent.action.BOOM_IMAGE`, and saves OCR/TextBoom/CamScanner
  logcat excerpts under `hard-rom/inspect/textboom-ppocr-live-capture/`. It is
  a sampling tool only: no flash, reboot, erase, uninstall, data clear, or ROM
  image mutation.

tools/r2-build-sidebar-font-ocr-disabled-apk.sh
  APK-only Sidebar patch builder for retiring One Step font OCR. It starts from
  the v0.29 topbar-hidden Sidebar APK, hides the font tool-button layout root,
  no-ops the font OCR launch path, disables BoomFontActivity, removes the
  ACTION_BOOM_FONT manifest exposure, and preserves the stock v2/v3 signing
  block as the certificate carrier. It does not build or flash a ROM image.

tools/r2-build-sidebar-font-ocr-deleted-apk.sh
  APK-only v0.39 Sidebar code-deletion builder. It starts from the v0.38
  font-OCR-disabled APK, removes BoomFontActivity/FontResultActivity manifest
  declarations, deletes Sidebar's `open/font` class cluster, deletes the
  Sidebar-local `com.intsig.csopen` SDK copy, removes IdentifyFontView classes,
  makes METHOD_FONT_REQUEST inert without FontUtils, and removes stale
  tool-button type=1 reachability. It does not build or flash a ROM image.

tools/r2-hardrom-build-v0.38-sidebar-font-ocr-disabled.sh
  FEC-preserving hard-ROM builder for v0.38. It starts from live-verified
  v0.37b, replaces only `/system/priv-app/Sidebar/Sidebar.apk` with the
  font-OCR-disabled Sidebar APK, bumps Sidebar package mtimes, rebuilds
  system_b AVB/FEC, and emits a sparse super candidate. It does not flash or
  touch a device.

tools/r2-verify-v0.38-sidebar-font-ocr-disabled.sh
  Read-only offline verifier for the v0.38 candidate. It checks sparse/system/
  product hashes, system_b/product_b FEC, dumped Sidebar APK hash and decoded
  font-OCR-disabled semantics, and retained TextBoom plus TextBoom `lib/arm`.

tools/r2-hardrom-build-v0.39-sidebar-font-ocr-deleted.sh
  FEC-preserving hard-ROM builder for the offline v0.39 Sidebar font OCR
  code-deletion candidate. It replaces only `/system/priv-app/Sidebar/Sidebar.apk`
  with the v0.39 deleted APK, bumps Sidebar package mtimes, rebuilds system_b
  AVB/FEC, and emits a sparse super candidate. It does not flash or touch a
  device.

tools/r2-verify-v0.39-sidebar-font-ocr-deleted.sh
  Read-only offline and live-device verifier for the v0.39 Sidebar font OCR
  code-deletion target. It checks sparse/system/product hashes, system_b/
  product_b FEC, dumped or live Sidebar APK hash, code-deleted Sidebar font
  OCR semantics, retained TextBoom plus TextBoom `lib/arm`, and live boot/
  slot/root/keyguard/Sidebar/WebView package state.

tools/r2-build-textboom-ppocr-noop-adapter-apk.sh
  APK-only TextBoom PP-OCR integration gate builder. It starts from the live
  TextBoom v3.2.2 APK, adds `LocalPpOcrApi implements IOcrApi`, changes
  `BoomOcrActivity.initView()` and `BoomAccessOcrActivity.initOcr()` from
  `new CsOcr(...)` to `new LocalPpOcrApi(...)`, and merges only `classes2.dex`
  back into the stock TextBoom shell. The adapter returns
  `onResultSuccess(empty ArrayList)` and leaves legacy `CsOcr`,
  TextBoom-local `com.intsig.csopen`, and `ocr_key` present.

tools/r2-build-textboom-ppocr-legacy-ocr-cleanup-apk.sh
  APK-only TextBoom legacy OCR cleanup builder for the v0.44 gate. It starts
  from the live-proven v0.43e TextBoom APK, keeps the original
  AndroidManifest.xml and manifest `ocr_key`, forces `BoomAccessOcrActivity`
  accessibility OCR to use `LocalPpOcrApi` instead of the old connectivity
  online branch, removes the hardcoded Intsig/CamScanner URL from classes2.dex,
  removes CamScanner wording from OCR resource strings, renames the inert
  `ocr_camscanner_*` resource symbols to storage-neutral names with the same
  IDs, merges only `classes2.dex` and `resources.arsc` back into the source
  shell, and verifies `resources.arsc` is STORED plus 4-byte aligned. It does
  not build a ROM image or authorize flashing.

tools/r2-hardrom-build-v0.40-textboom-ppocr-noop-adapter.sh
  FEC-preserving hard-ROM builder for the v0.40 TextBoom no-op adapter gate.
  It starts from live-verified v0.39, replaces only
  `/system/app/TextBoom/TextBoom.apk`, bumps `/system/app/TextBoom` and
  `/system/app` mtimes for PackageCacher freshness, rebuilds system_b
  AVB/FEC roots=2, and emits the sparse super candidate. It does not flash or
  touch a device.

tools/r2-verify-v0.40-textboom-ppocr-noop-adapter.sh
  Read-only offline and live-device verifier for the v0.40 TextBoom no-op
  adapter candidate. Offline mode checks sparse/system/product hashes,
  system_b/product_b FEC, retained Sidebar/WebView/Smartisax hashes,
  TextBoom `lib/arm`, and decoded TextBoom `LocalPpOcrApi` semantics. Live mode
  checks boot/slot/root, package paths, live hashes, and absence of a TextBoom
  updated-system shadow.

tools/r2-browser-webview-modernization-audit.py
  Read-only v0.30 BrowserChrome/WebView modernization backport entry audit. It
  consumes stock APK manifests, static package indexes, framework WebView
  provider config, WebViewUpdateService source, SettingsSmartisan WebView UI,
  and APK zip structure, then writes the browser/WebView contract TSV and
  markdown report.

tools/r2-browser-webview-version-gap-audit.py
  Read-only BrowserChrome/WebView version-gap audit. It extracts stock
  BrowserChrome app and Chromium payload version signals, stock WebView provider
  version, APK payload shape, current gate state, and route priority, then writes
  `docs/research/browser-webview-version-gap-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/browser-webview-version-gap-audit.tsv`,
  and `hard-rom/inspect/browser-webview-version-gap-audit/browser-webview-version-gap-audit.json`.

tools/r2-webview-framework-contract-audit.py
  Read-only WebView framework contract audit. It inspects local decoded
  framework-res, services.jar, framework.jar, SettingsSmartisan, and stock
  WebView artifacts, then writes
  `docs/research/webview-framework-contract-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-framework-contract-audit.tsv`,
  and
  `hard-rom/inspect/browser-webview-framework-contract/webview-framework-contract-audit.json`.

tools/r2-webview-donor-audit.py
  Read-only WebView donor APK/APKM/APKS/XAPK analyzer. It checks provider
  whitelist/package identity, Android 11 min/target SDK gates, WebViewUpdater
  version-code cohort, WebViewLibrary metadata, native ABI/library presence,
  sandbox service declarations, split layout, Android 11
  WebViewChromiumFactoryProviderForR class presence, Trichrome/static
  shared-library dependencies, multi-package bundle shape, local aapt parser
  coverage, and the recommended ROM adaptation route before any donor-backed
  ROM image is built.

tools/r2-webview-trichrome-bundle-audit.py
  Read-only WebView package-group analyzer for modern Trichrome/static-library
  donor bundles. It expands APK/APKM/APKS/XAPK/ZIP/directory inputs, selects a
  single WebView provider candidate, classifies standalone versus
  Trichrome/static-library bundles, checks one-base-APK-per-package layout,
  resolves uses-static-library references, compares static-library versions
  and certDigest evidence when local signer tooling is available, and writes
  reports under `hard-rom/inspect/browser-webview-trichrome-bundle/`.

tools/r2-webview-donor-inbox-audit.py
  Read-only local inbox scanner for future WebView donor material. It scans
  `apks/webview-donor-inbox/`, related local donor directories, and optionally
  `~/Downloads`, computes hashes, runs both `tools/r2-webview-donor-audit.py`
  and `tools/r2-webview-trichrome-bundle-audit.py` for each local
  APK/APKM/APKS/XAPK/ZIP candidate, and writes the donor inbox manifest under
  `hard-rom/inspect/browser-webview-donor-inbox/`.

tools/r2-webview-donor-source-plan.py
  Read-only generator for `docs/research/webview-donor-source-plan.md` and
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-source-plan.tsv`.
  It converts the stock WebView audit plus current donor inbox state into
  route priorities and version/package/static-library rules, including the
  dedicated route C Trichrome bundle gate.

tools/r2-webview-donor-target-matrix.py
  Read-only generator for `docs/research/webview-donor-target-matrix.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-donor-target-matrix.tsv`,
  and `hard-rom/inspect/browser-webview-donor-target-matrix/webview-donor-target-matrix.json`.
  It turns the current WebView evidence into concrete source-build/prebuilt/
  framework-provider-add/Trichrome/BrowserChrome/rejected route targets and now
  consumes the image-capacity and system_b space-source gates so donor-backed
  image work stays blocked until the user selects a feasible layout.

tools/r2-webview-route-a-provider-spec.py
  Read-only generator for `docs/research/webview-route-a-provider-spec.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-provider-spec.tsv`,
  and `hard-rom/inspect/browser-webview-route-a-provider-spec/webview-route-a-provider-spec.json`.
  It defines the Route A donor/source-build acceptance contract and marks the
  current state ready for intake but not image build.

tools/r2-webview-route-a-candidate-audit.py
  Read-only Route A candidate intake auditor. It accepts an APK, split bundle,
  archive, or directory, runs `tools/r2-webview-donor-audit.py` and
  `tools/r2-webview-trichrome-bundle-audit.py`, then writes
  `docs/research/webview-route-a-candidate-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-candidate-audit.tsv`,
  and `hard-rom/inspect/browser-webview-route-a-candidate-audit/webview-route-a-candidate-audit.json`.

tools/r2-webview-source-build-readiness-plan.py
  Read-only source-build readiness generator for
  `docs/research/webview-source-build-readiness-plan.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-source-build-readiness-plan.tsv`,
  and `hard-rom/inspect/browser-webview-source-build-readiness/webview-source-build-readiness-plan.json`.
  It records the isolated Linux builder route, Chromium stable metadata,
  GN args, and the missing SystemWebView.apk/signing-transition gates.

tools/r2-webview-signing-transition-plan.py
  Read-only A-SIG-01 generator for
  `docs/research/webview-signing-transition-plan.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-signing-transition-plan.tsv`,
  and `hard-rom/inspect/browser-webview-signing-transition/webview-signing-transition-plan.json`.
  It records stock WebView APK Sig Block 42 and certificate-carrier evidence,
  accepted/rejected same-package transition routes, and now consumes the
  PackageManager audit to distinguish offline A-SIG proof from live acceptance.

tools/r2-webview-a-sig-package-manager-audit.py
  Read-only A-SIG PackageManager acceptance auditor for
  `docs/research/webview-a-sig-package-manager-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-a-sig-package-manager-audit.tsv`,
  and `hard-rom/inspect/browser-webview-a-sig-package-manager/webview-a-sig-package-manager-audit.json`.
  It runs apksigner full verification, parses APK Signing Block v2/v3 signer
  certificates in the same cert-only spirit as Android's system-scan path, and
  records whether the stock-carrier WebView exposes the stock Smartisan cert.

tools/r2-webview-route-a-image-capacity-audit.py
  Read-only Route A image capacity auditor for
  `docs/research/webview-route-a-image-capacity-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-route-a-image-capacity-audit.tsv`,
  and
  `hard-rom/inspect/browser-webview-route-a-image-capacity/webview-route-a-image-capacity-audit.json`.
  It blocks the current full M150 product_b-only candidate, records system_b
  full-ABI and 64-bit-only alternatives, and does not build images or touch the
  device.

tools/r2-webview-system-space-source-audit.py
  Read-only system_b space-source auditor for
  `docs/research/webview-system-space-source-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-system-space-source-audit.tsv`,
  and
  `hard-rom/inspect/browser-webview-system-space-source/webview-system-space-source-audit.json`.
  It measures candidate removable package bundles in the current system_b image
  and records a preferred review candidate without deleting packages, building
  images, touching the device, or mutating `/data`.

tools/r2-webview-super-capacity-audit.py
  Read-only dynamic-super capacity auditor for
  `docs/research/webview-super-capacity-audit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-super-capacity-audit.tsv`,
  and
  `hard-rom/inspect/browser-webview-super-capacity/webview-super-capacity-audit.json`.
  It parses local lpdump evidence and records whether `system_b` can grow
  inside the current B-slot dynamic partition group without touching the live
  device.

tools/r2-apk-v2-carrier-adapt.py
  Offline APK Sig Block 42 strip/graft helper for same-package system APK
  experiments. It can strip an existing candidate v2 signing block before
  grafting the stock certificate carrier, and its `--self-test` mode verifies
  strip plus graft can reproduce stock APK bytes. It does not create a valid
  cryptographic re-signature for modified payloads.

tools/r2-webview-linux-builder-kit.py
  Read-only/off-device generator for `docs/research/webview-linux-builder-kit.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-linux-builder-kit.tsv`,
  `hard-rom/inspect/browser-webview-linux-builder-kit/webview-linux-builder-kit.json`,
  and the small kit under `hard-rom/inspect/browser-webview-linux-builder-kit/kit/`.
  It writes exact GN args, isolated Linux preflight/build/collection scripts,
  provenance manifest/SHA256/revision metadata, and a local Mac intake script
  for a future returned `SystemWebView.apk`.

.github/workflows/webview-source-build.yml
  Manual workflow_dispatch entry for running the generated WebView Linux
  builder kit on a large self-hosted or GitHub larger Ubuntu runner. Default
  mode is preflight-only; it regenerates the ignored kit directory on the
  runner before validation, and full build mode uploads the returned dist/logs
  but still does not authorize a donor-backed ROM image.

tools/r2-webview-sourcebuilt-intake.py
  Offline Mac-side intake runner for a returned Linux-builder
  `SystemWebView.apk` or dist directory. It validates dist provenance
  metadata, copies the artifact into `apks/webview-donor-inbox/`, records
  A-SIG-01 signing shape, prepares the stock-cert-carrier adaptation path with
  `tools/r2-apk-v2-carrier-adapt.py`, runs the A-SIG PackageManager audit,
  runs original/adapted Route A candidate audits, refreshes
  integration/design/target-matrix gates, and supports `--dry-run` plus
  `--validate-only` before any real APK is admitted.

tools/r2-webview-integration-plan.py
  Read-only generator for `docs/research/webview-integration-plan.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-integration-plan.tsv`,
  and `hard-rom/inspect/browser-webview-integration-plan/webview-integration-plan.json`.
  It consumes donor audit, Trichrome bundle audit, inbox, live-state, and
  v0.31 evidence to classify Route A/B/C, list build-readiness blockers, and
  keep donor-backed image design behind the required live gates.

tools/r2-webview-rom-design-plan.py
  Read-only generator for `docs/research/webview-rom-design-plan.md`,
  `reverse/smartisan-8.5.3-rom-static/manifest/webview-rom-design-plan.tsv`,
  and `hard-rom/inspect/browser-webview-rom-design-plan/webview-rom-design-plan.json`.
  It consumes the integration plan plus donor/bundle/live-state/capacity and
  system_b space-source evidence, then emits donor-to-image design requirements
  without downloading donors, building images, touching a device, or mutating
  `/data`.

tools/r2-browser-webview-live-state-audit.sh
  Read-only live-device capture for BrowserChrome/WebView modernization. It
  records `webviewupdate`, WebView settings, BrowserChrome/WebView package
  paths and mtimes, default browser resolver state, package_cache/icon
  redirection evidence through the root helper, keyguard/launcher state, and
  recent Browser/WebView logs without writing settings or mutating `/data`.

tools/r2-hardrom-build-v0.31-webview-stock-near-noop.sh
tools/r2-verify-v0.31-webview-stock-near-noop.sh
  WebView provider near-noop ROM gate on top of live-verified v0.29. The
  builder patches only product_b, keeps `/product/app/webview/webview.apk`
  byte-identical to stock, bumps only the `/app/webview` package directory
  mtime in the product image, and rewrites the sparse super. The verifier
  checks the candidate sparse/product hashes, e2fsck, WebView directory mtime,
  byte-identical dumped WebView APK, sparse product_b slice equality, retained
  system_b/system_ext_b/vendor_b/odm_b slices, WebView donor/provider static
  gate, Trichrome/static-library bundle gate, and integration-plan
  build-readiness gate on the dumped APK.

tools/r2-hardrom-build-v0.32-browserchrome-stock-near-noop.sh
tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh
  BrowserChrome stock near-noop ROM gate on top of live-verified v0.29. The
  builder patches only system_b, keeps
  `/system/app/BrowserChrome/BrowserChrome.apk` byte-identical to stock, bumps
  only the `/system/app/BrowserChrome` package directory mtime in the system
  image, and rewrites the sparse super. The verifier checks the candidate
  sparse/system hashes, e2fsck, BrowserChrome directory mtime,
  byte-identical dumped BrowserChrome APK, sparse system_b slice equality, and
  retained product_b/system_ext_b/vendor_b/odm_b slices.

tools/r2-hardrom-build-v0.33-system-b-grow-noop.sh
tools/r2-verify-v0.33-system-b-grow-noop.sh
  Dynamic system_b partition/footer growth gate on top of live-verified v0.31.
  The builder reconstructs full super metadata with lpmake, grows only the
  system_b logical partition image by 128 MiB, and moves the existing AVB
  footer with avbtool resize_image while preserving the ext4 block count and
  all filesystem contents. The verifier checks lpdump sectors, AVB footer
  metadata, e2fsck, retained partition hashes, byte-identical APK/critical-file
  contents, and provides a read-only live verifier for the future flash. This
  is not yet an ext4 df-capacity growth gate.

tools/r2-hardrom-build-v0.34-system-b-ext4-grow-nofec.sh
  Historical offline-only ext4 capacity gate on top of live-verified v0.33. The builder
  keeps the v0.33 system_b logical partition size, erases the old footer,
  expands system_b ext4 to the no-FEC maximum data size, rebuilds a no-FEC
  hashtree footer, rebuilds full super metadata, and verifies retained
  partition hashes plus byte-identical system APK/critical-file contents. This
  was superseded by the FEC-preserving v0.34 build; do not use no-FEC as the
  default capacity candidate.

tools/r2-hardrom-build-v0.34-system-b-ext4-grow-fec.sh
tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh
  Current live-verified ext4 capacity gate on top of live-verified v0.33. The
  builder keeps the v0.33 system_b logical partition size, erases the old
  footer, expands system_b ext4 to the maximum FEC-preserving AVB data size,
  rebuilds a hashtree footer with Android FEC roots=2 through
  third_party/aosp-system-extras-fec/bin/fec, rebuilds full super metadata,
  and verifies retained partition hashes plus byte-identical system
  APK/critical-file contents. The verifier checks the local FEC footer and
  provides the post-flash read-only device gate for boot, B slot, root,
  system_b mapper size, /system df growth, stock WebView/BrowserChrome hashes,
  WebViewUpdateService, keyguard, and launcher focus. It was flashed to B slot
  after explicit confirmation and passed the strict post-unlock live verifier.

tools/r2-hardrom-build-v0.35-webview-m150-system-provider.sh
tools/r2-verify-v0.35-webview-m150-system-provider.sh
  WebView M150 system-provider candidate on top of live-verified
  v0.34. The builder installs the source-built stock-carrier
  `com.android.webview` APK into `/system/app/webview/webview.apk`, hides the
  old product public WebView APK behind a non-`.apk` held stock path, bumps the
  package directory mtimes, rebuilds system_b and product_b FEC hashtree
  footers, and rebuilds full super metadata. The verifier checks hashes, fsck,
  FEC metadata, package mtimes, product public absence, held stock product APK,
  dumped provider identity, and donor/bundle audits; `--read-only` is the
  post-flash live gate. The image has been flashed to B slot and passed the
  read-only live gate. User-facing testing then reproduced the stock browser
  white-loading regression, with logs pointing at BrowserChrome's system odex;
  Big Bang remained normal.

tools/r2-hardrom-build-v0.35.1-webview-m150-browserchrome-deodex.sh
  v0.35 follow-up candidate. The builder keeps the M150 system WebView provider
  and stock BrowserChrome APK unchanged, removes
  `/system/app/BrowserChrome/oat/arm64/BrowserChrome.odex` plus `.vdex`,
  removes the empty BrowserChrome oat directories, bumps the BrowserChrome
  package directory mtime, rebuilds system_b FEC, keeps product_b byte-identical
  to v0.35, and rebuilds full super metadata. Manual offline verification
  proves BrowserChrome APK hash remains stock, BrowserChrome oat paths are
  absent, WebView M150 remains present, product public WebView remains absent,
  product held stock WebView remains present, and FEC roots=2 are preserved.
  The image has now been flashed to B slot and live-verified: WebViewUpdateService
  remains clean, BrowserChrome oat paths are absent on device, and stock
  BrowserChrome renders `https://www.example.com` without BrowserChrome-only
  crash markers.

tools/r2-hardrom-build-v0.35.2-webview-m150-clean-product-residue.sh
tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh
  v0.35.1 follow-up candidate. The builder keeps v0.35.1 system_b retained,
  rebuilds product_b only, removes `/product/app/webview` entirely including
  the hidden stock WebView backup and stale oat/vdex tree, rebuilds product_b
  FEC roots=2, and rebuilds full super metadata. Offline verification proves
  retained M150 WebView, absent BrowserChrome oat, product_b slice equality,
  FEC roots=2, and `product_webview_dir=absent`. It has now been flashed to B
  slot and live-verified: WebViewUpdateService selects M150 with relro 2/2 and
  dirty=false, `/product/app/webview` is absent, stock BrowserChrome renders
  example.com, HtmlViewer renders through M150 WebView, Big Bang BOOM_TEXT
  segments text, and WPS loads M150 WebView as a third-party host.

tools/r2-build-smartisax-shell.sh
apps/SmartisaxShell/
tools/r2-hardrom-build-v0.36-smartisax-shell-debloat.sh
tools/r2-verify-v0.36-smartisax-shell-debloat.sh
  Smartisax branch candidate path on top of live-proven v0.35.2. The APK
  project builds `com.smartisax.browser`, a small WebView-backed system shell
  that declares browser and Home intent surfaces without replacing stock
  Launcher or stock `com.android.browser`. The v0.36 builder installs it under
  `/system/app/SmartisaxShell`, removes the user-selected no-projection
  print-preserving debloat set plus SmartisanWallpapers, cleans active sysconfig
  references to removed packages, preserves M150 WebView, BrowserChrome,
  Launcher, print, and TNT/projection, and rebuilds system_b FEC roots=2.
  v0.36 flashed and booted, but PackageManager rejected Smartisax because its
  targetSdk 30 APK did not satisfy Android 11's `resources.arsc` stored/aligned
  rule. v0.36.1 fixes the APK layout, was flashed to B slot, and passed live
  verification: `com.smartisax.browser` registers from `/system/app/SmartisaxShell`,
  the selected hard-debloat paths are absent, and M150 WebView plus stock
  BrowserChrome/Launcher remain healthy. Smartisax functional UX testing also
  passes: default Home, WebView shell rendering, Chrome/150 UA,
  WebGPU/WebGL2/localStorage probes, ACTION_VIEW example.com rendering,
  Back-to-shell, and Settings-to-Home return are all proven by state reports
  plus screenshots.

tools/r2-hardrom-build-v0.37a-textboom-live-system-base.sh
tools/r2-verify-v0.37a-textboom-live-system-base.sh
tools/r2-clean-v0.37a-textboom-data.sh
  TextBoom/OCR groundwork gate on top of live-proven v0.36.1. The builder
  installs the live v3.2.2 `com.smartisanos.textboom` APK byte-for-byte under
  `/system/app/TextBoom` without manifest/code/resource edits, preserving the
  v1/JAR signature and avoiding the known manifest-edit certificate-collection
  failure. Offline verification proves the APK contract, unchanged M150
  WebView/BrowserChrome/Launcher/Smartisax hashes, and system_b/product_b FEC
  roots=2. The cleanup helper is separate and must not be run with `--apply`
  without explicit approval because it mutates the updated-system `/data/app`
  shadow.

tools/r2-hardrom-build-v0.37b-textboom-live-system-libs-deodex.sh
tools/r2-verify-v0.37b-textboom-live-system-libs-deodex.sh
tools/r2-repair-v0.37b-textboom-shadow.sh
  TextBoom/OCR follow-up gate. v0.37b keeps the live v3.2.2 TextBoom APK
  byte-identical under `/system/app/TextBoom`, adds the APK's 13 32-bit native
  libraries to `/system/app/TextBoom/lib/arm`, removes stale TextBoom oat/vdex,
  and rebuilds system_b with FEC roots=2. After separate explicit approval,
  the repair helper rewrites only the TextBoom PackageManager shadow state,
  moves the old `/data/app` updated-system APK out of the scan path, reboots,
  and verifies that TextBoom is served from the system path with no
  `UPDATED_SYSTEM_APP` flag. Big Bang BOOM_TEXT has live functional proof from
  the repaired system package.

tools/r2-language-full-prune-coverage-audit.py
  Read-only audit for the full English/Chinese-only physical prune target. It
  writes a TSV manifest and markdown report counting all non-target language
  resources, so ja/ko progress is not mistaken for complete ROM language
  pruning.

tools/r2-language-next-batch-plan.py
  Read-only batch planner for the full language-prune target. It consumes the
  full-prune coverage TSV and writes a staged P0/P1/P2/P3/P4/P5 plan for image
  rebuilds, existing APK-only promotion, new APK candidates, and gated packages.

tools/r2-language-p1-source-review-audit.py
  Read-only source-review audit for P1 language-prune APK candidates. It joins
  the staged plan with static package/component/permission indexes and source
  marker scans, while separating app-owned source coupling from embedded
  library noise.

tools/r2-language-live-state-audit.sh
  Read-only live-device state capture for English/Chinese-only language pruning.
  It records locale properties, activity configuration, Settings locale keys,
  package code paths, updated-system /data/app shadows, current window/keyguard
  focus, and recent locale/resource logs without rebooting, flashing, writing
  settings, changing packages, or mutating /data.

tools/r2-darkmode-source-coupling-audit.py
  Read-only dark-mode source-coupling audit. It writes a TSV manifest and
  markdown report that map the stock framework backend, Smartisan Settings and
  SystemUI entry points, reusable resources, v0.11 APK/ROM evidence, and the
  remaining behavior live gate.

tools/r2-darkmode-qs-strategy-audit.py
  Read-only QS integration strategy audit for native dark mode. It maps
  SettingsProvider default quick-widget lists, QSTileHost tile creation,
  QuickWidgetFactory editor rendering, SettingsSmt candidate registry,
  backup/restore splitting, and live-state availability so toggleDarkMode is
  not blindly appended to a full 20-entry phone default list.

tools/r2-darkmode-persistence-audit.py
  Read-only audit for whether toggleDarkMode survives SettingsProvider seeding,
  SettingsSmartisan reset/checkValidity, backup/restore normalization, and
  SystemUI first-page truncation. It writes
  `docs/research/darkmode-persistence-audit.md` and the matching TSV manifest.

tools/r2-darkmode-live-state-audit.sh
  Read-only live-device state capture for native dark-mode design. It records
  current UiModeManager state, ui_night_mode settings, Smartisan QS tile
  settings, parsed Settings.System expanded_widget_buttons counts, duplicate
  keys, toggleDarkMode presence, relevant package state, keyguard/window focus,
  and recent logs without rebooting, flashing, writing settings, changing
  packages, or mutating /data. A successful report is required before choosing a
  default tile replacement, SettingsProvider seed, or live QS data migration.

tools/r2-storage-cleanup-candidates.sh
  Read-only storage report for large generated artifacts. It identifies obsolete
  raw super-slice dumps replaced by sparse logical-slice verification and
  separates them from sparse images or partition images still used by active
  gates.

tools/r2-build-native-darkmode-tile-apks.sh
tools/r2-verify-v0.11-native-darkmode-tile-apks.sh
  APK-level native dark-mode integration builder and semantic verifier. Patches
  SmartisanSystemUI to create a native toggleDarkMode tile and patches the same
  SettingsSmartisan APK for the Display/Brightness dark-mode switch,
  quick-widget rendering, and NotificationCustomView candidate injection for
  that key. The verifier confirms only the expected dex files changed, then
  decodes the candidates to temporary smali and checks concrete call sites in
  DarkModeTile, QSTileHost, BrightnessSettingsFragment, QuickWidgetFactory, and
  NotificationCustomView.

tools/r2-hardrom-build-v0.11-native-darkmode.sh
tools/r2-verify-v0.11-native-darkmode.sh
  Combined v0.11 native dark-mode ROM builder and verifier. It starts from the
  live-verified v0.24 sparse, replaces SettingsSmartisan in system_b and
  SmartisanSystemUI in system_ext_b, verifies dumped APK hashes and sparse
  logical slices, and produces the flash candidate
  `hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img`.
  Built, flashed after exact user confirmation, and live read-only verified at
  the boot/package/hash level. Reversible Settings/UiMode/QS functional testing
  remains before the dark-mode goal can be considered complete.

tools/r2-build-systemui-certprobe-noop-apk.sh
tools/r2-verify-systemui-certprobe-noop-apk.sh
tools/r2-hardrom-build-systemui-certprobe-noop.sh
tools/r2-verify-systemui-certprobe-noop.sh
  SmartisanSystemUI no-op gate. Because system_ext_b has shared_blocks and zero
  free blocks, the valid probe is a same-size one-byte patch to the APK v2
  signing block magic, not a new ZIP entry or inode replacement. The current
  dark-mode line uses `SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24`
  on top of the live-verified v0.24 sparse; it has passed live independently.

tools/r2-verify-v0.6-settings-noop.sh
tools/r2-verify-v0.7-locale-filter.sh
tools/r2-verify-v0.8-darkmode-ui.sh
  Post-flash live verification scripts. Run only after explicitly confirmed
  flashing of the matching variant.

apps/SmartisaxControls/
  Minimal APK source used to validate ROM-bundled privileged dark-mode control,
  QS TileService discovery, and `UiModeManager` permission behavior.

hard-rom/inspect/
  Live-device and offline inspection evidence.

reverse/
  Decompiled/raw system components and graph-analysis inputs.

apks/
  Local APK artifacts kept out of the repository root.

third_party/
  External tools used for APatch, APKTool, payload packing, dynamic partitions,
  and AOSP update-engine work.

stock-ota/
  Original OTA package and extracted stock images.

backups/
  Recovery-critical partition captures and root bootstrap artifacts.

dist/, updates/, fake-ota-server/
  Legacy systemless update artifacts and runtime. They remain in place because
  old tools still reference these paths.
```
