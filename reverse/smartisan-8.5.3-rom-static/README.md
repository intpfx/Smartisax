# Smartisan OS 8.5.3 ROM Static Knowledge Base

This directory is generated from OTA-extracted partition images only. It is the
ROM static layer and intentionally excludes `/data/app` live updated-system
packages.

Generated path:

```text
reverse/smartisan-8.5.3-rom-static
```

Initial inventory:

```text
partition files: 8332
APK/JAR/APEX targets: 430
config targets: 402
```

Main files:

```text
manifest/partition-files.tsv      all files listed from static partition images
manifest/decompile-targets.tsv    APK/JAR/APEX targets from ROM partitions
manifest/config-targets.tsv       build/init/permission/SELinux config targets
manifest/extracted-targets.tsv    extracted raw artifacts with SHA256
manifest/jadx-status.tsv          decompile status and source file counts
indexes/packages.tsv              package-level manifest index
indexes/components.tsv            activity/service/receiver/provider index
indexes/uses-permissions.tsv      package permission index
indexes/intent-filters.tsv        manifest intent-filter index
indexes/overlays.tsv              static/resource overlay target index
indexes/privapp-permissions.tsv   priv-app permission config index
indexes/sysconfig-packages.tsv    sysconfig package allowlist/reference index
indexes/signatures.tsv            APK signer certificate digest index
indexes/classes.tsv               Java class lookup index
indexes/resources-public.tsv      public resource ID lookup index
indexes/resources-overlayable.tsv overlayable resource declaration lookup
indexes/summary.md                generated source knowledge summary
indexes/knowledge-map.md          system construction map
indexes/build-modification-map.md image modification and build map
modification-confidence-map.md    modification risk gate and playbooks
graph-corpus/modification-critical/
                                  focused graphify corpus for modification
                                  impact analysis
review/completion-audit-v1.1.md   current independent-review evidence pack
review/qa-v1.1-answers.md         formal Q&A answers
review/qa-v1.1-hooke-score.md     Hooke reviewer score: 10/10 PASS, COMPLETE
```
