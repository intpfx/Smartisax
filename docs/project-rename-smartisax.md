# Smartisax Rename And Open-Source Prep

## Name

The project name is now Smartisax. New source, docs, scripts, package names, and
agent-facing text should use Smartisax naming.

The planned local repository path after the directory rename is:

```text
~/Documents/Smartisax
```

During the transition, an existing Codex session may still be running from the
pre-rename checkout path. Treat both paths as the same project until the folder
move is complete.

## Memory And Agent Association

Codex project memory should map the previous checkout path and the new checkout
path to the same Smartisax project. The live-device rule does not change:
anything that touches the R2 over USB, ADB, fastboot, screenshots, package
queries, or log capture must run escalated/non-sandboxed.

The project skill remains:

```text
.agents/skills/smartisan-r2-hardrom/SKILL.md
```

Future agent sessions should read `AGENTS.md`, `README.md`, and that skill file
before ROM, root, fastboot, system app, overlay, framework, Browser/WebView,
TextBoom/OCR, Portal, or Smartisax app work.

## GitHub Scope

Commit source, scripts, project docs, and small reproducible fixtures.

Do not publish generated ROM images, extracted OTA payloads, private keys,
device backups, inspection dumps, or live-device logs that can contain private
state. These paths are intentionally local/ignored:

```text
hard-rom/build/
hard-rom/work/
hard-rom/inspect/
hard-rom/keys/
stock-ota/
backups/
reports/
third_party/
.apatch-superkey
```

Some ignored manifests and inspection files may contain the checkout's absolute
path until they are regenerated after the folder rename. Do not treat those
local path strings as open-source content.

Keep at least the latest successful sparse image locally for rollback before
removing any generated artifact from the machine.

## Local Rename Checklist

1. Finish or pause active ROM work and record the latest stable image.
2. Confirm tracked files no longer contain the old project spelling.
3. Ensure ignored local key filenames match the new Smartisax script defaults.
4. Close tooling that has the checkout directory open.
5. Rename the folder to the planned local path.
6. Reopen Codex from the renamed folder and verify `git status`, docs, and skill
   routing still resolve.
