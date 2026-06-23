# Static ROM Knowledge Base

The static knowledge base lives at `reverse/smartisan-8.5.3-rom-static/` and is generated from OTA-extracted ROM partition images only. It intentionally excludes live `/data/app` updated-system packages. Use it for source, manifest, component, permission, overlay, resource, and modification-risk questions about the stock ROM layer.
Paths are repo-root-relative unless explicitly described otherwise.


## Entry Points

- `reverse/smartisan-8.5.3-rom-static/README.md` - generated KB overview.
- `reverse/smartisan-8.5.3-rom-static/indexes/summary.md` - corpus and component counts.
- `reverse/smartisan-8.5.3-rom-static/indexes/knowledge-map.md` - system construction map.
- `reverse/smartisan-8.5.3-rom-static/indexes/build-modification-map.md` - image modification and build map.
- `reverse/smartisan-8.5.3-rom-static/modification-confidence-map.md` - package/resource/framework modification gate.
- `reverse/smartisan-8.5.3-rom-static/graph-corpus/modification-critical/` - focused graphify corpus for high-risk system modification analysis.
- `reverse/smartisan-8.5.3-rom-static/graph-corpus/feature-control/` - focused graphify corpus for feature-control surfaces.
- `reverse/smartisan-8.5.3-rom-static/review/` - completion audit and independent Q&A review pack.

## Generated Indexes

- `indexes/packages.tsv` - package-level manifest index.
- `indexes/components.tsv` - activity/service/receiver/provider index.
- `indexes/intent-filters.tsv` - manifest intent-filter index.
- `indexes/uses-permissions.tsv` - package permission index.
- `indexes/privapp-permissions.tsv` - priv-app permission config index.
- `indexes/sysconfig-packages.tsv` - sysconfig package references.
- `indexes/overlays.tsv` - static/resource overlay targets.
- `indexes/signatures.tsv` - APK signer certificate digest index.
- `indexes/classes.tsv` - Java class lookup index.
- `indexes/resources-public.tsv` - public resource ID lookup.
- `indexes/resources-overlayable.tsv` - overlayable resource declarations.

## Use Rules

- Treat the KB as static ROM evidence, not live-device truth. Re-check `/data/app` shadows, package cache, and current slot state on the device when a live mutation matters.
- Use graphify as an impact navigator, then confirm with manifests, decoded resources, source paths, generated manifests, and verifier outputs.
- For any new delete, replacement, framework/resource change, or package-cache-sensitive change, run `tools/r2-rom-mod-preflight.py` and read the relevant `docs/research/*` gate before building.
