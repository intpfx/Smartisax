# Current Route Index

This file was split out of `docs/README.md`; it points to the current hard-ROM evidence, rollback, and static source routes.
Paths are repo-root-relative unless explicitly described otherwise.


## Primary Route Files

```text
docs/hard-rom-ota-trust.md
  Chronological project log, build evidence, flashing records, failures, and
  rollback notes. Treat this as the primary evidence trail.

docs/v0.5-debloat-candidates.md
  Current live v0.4 package and overlay inventory plus next debloat tiers.

docs/rom-archive.md
  Large image retention map. Current local stable image plus SSDUSB cold
  archives for v0.2 rollback and the pre-hard-ROM raw super backup.

reverse/smartisan-8.5.3-rom-static/
  ROM static source knowledge base generated from OTA-extracted partition
  images only. Excludes `/data/app`; use this for source/manifest/component
  questions about the stock ROM layer.

reverse/smartisan-8.5.3-rom-static/modification-confidence-map.md
  Current gate for deciding whether a requested package, overlay, resource, or
  framework change is ready for build/flash.

reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/
  Focused graphify corpus for package-manager, resource, overlay, permission,
  keyguard, launcher, SystemUI, Settings, PackageInstaller, PermissionController,
  BrowserChrome, and WebView modification-risk analysis.

reverse/smartisan-8.5.3-rom-static/review/completion-audit-v1.1.md
  Current evidence pack for independent review and the later ten-round
  nontrivial Q&A completion gate.

reverse/smartisan-8.5.3-rom-static/review/qa-v1.1-answers.md
  Formal answers to Hooke's first ten nontrivial static-ROM source questions.

reverse/smartisan-8.5.3-rom-static/review/qa-v1.1-hooke-score.md
  Hooke's formal score for the V1.1 Q&A: 10/10 PASS, final judgment COMPLETE.
```
