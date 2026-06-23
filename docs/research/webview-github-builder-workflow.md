# WebView GitHub Builder Workflow

Generated: 2026-06-19

This is an off-device execution wrapper for the existing WebView Linux builder
kit. It does not change ROM images, touch the phone, flash, reboot, erase misc,
write settings, or modify `/data`.

## Workflow

```text
.github/workflows/webview-source-build.yml
```

The workflow is manual-only through `workflow_dispatch`. Its default mode is
`preflight`, which checks the runner and stops before fetching Chromium. A full
Chromium build runs only when `mode=build` is selected manually.

The workflow first runs:

```text
python3 tools/r2-webview-linux-builder-kit.py
```

This regenerates `hard-rom/inspect/browser-webview-linux-builder-kit/kit/` on
the runner before any script validation. That matters because `hard-rom/inspect/`
is a local evidence directory and is not expected to be tracked in Git.

## Runner Requirement

Use a large self-hosted Linux x86-64 runner or a GitHub larger Ubuntu runner
with a large disk. Do not use the default standard `ubuntu-latest` runner for
the full build.

Recommended minimums:

```text
disk: 250 GB free or more
RAM: 16 GB or more
arch: x86-64 Linux
build path: no spaces, for example /mnt/webview-build
```

The workflow exposes:

```text
runner_labels_json
build_root
min_free_gb
min_ram_gb
mode
```

The default `runner_labels_json` is:

```json
["self-hosted","linux","x64","webview-builder"]
```

## Preflight

The workflow calls:

```text
hard-rom/inspect/browser-webview-linux-builder-kit/kit/preflight-linux-builder.sh
```

This script checks Linux, x86-64, free disk, RAM, required base commands, and a
space-free build path before any Chromium fetch or build step. If the selected
build root such as `/mnt/webview-build` cannot be created by the runner user,
the script tries a narrow `sudo mkdir` plus `chown` fallback and then verifies
the directory is writable.

## Build Output

When `mode=build` succeeds, the workflow uploads:

```text
hard-rom/inspect/browser-webview-linux-builder-kit/kit/dist/sourcebuilt-system-webview-*
hard-rom/inspect/browser-webview-linux-builder-kit/kit/logs/*.log
```

The returned `sourcebuilt-system-webview-*` dist directory must still be copied
back into this Mac workspace and passed to:

```bash
hard-rom/inspect/browser-webview-linux-builder-kit/kit/local-intake-after-copy.sh \
  /path/to/sourcebuilt-system-webview-150.0.7871.28
```

Local intake validates provenance metadata, records A-SIG-01 evidence, prepares
the stock-cert carrier adaptation path, and runs Route A candidate audits. A
successful GitHub build artifact still does not authorize a donor-backed ROM
image by itself.

## Boundary

This workflow only creates the missing source-built input. ROM image design
remains blocked until the returned artifact passes local provenance validation,
A-SIG-01 signing-transition review, Route A candidate audit, integration plan,
ROM design plan, offline image verification, and explicit live-device
confirmation.
