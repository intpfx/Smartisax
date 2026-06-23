# Agent Memory, Skills, And Evidence Map

This project has several layers of context. Keep them separate so future work does not confuse remembered history with current proof.

## Layers

- Codex memory: machine-level notes outside this repository. Use as a hint about prior decisions or local environment behavior, then verify against repo files or live state. Do not edit global memory files directly from this workspace unless the user explicitly asks for a memory update.
- `AGENTS.md`: short repository operating rules for agents. It should stay quick to read.
- `.agents/skills/smartisan-r2-hardrom/SKILL.md`: short project skill router for recurring ROM work.
- `.agents/skills/smartisan-r2-hardrom/references/`: long skill reference material split by topic.
- `docs/`: human and agent documentation, research notes, and indexes.
- `docs/hard-rom-ota-trust.md`: chronological evidence log. Treat it as source of truth for experiment history.
- `reverse/smartisan-8.5.3-rom-static/`: generated static source knowledge base. Treat it as stock-ROM evidence only.
- `hard-rom/inspect/`: concrete verifier, live-device, screenshot, benchmark, and audit outputs.

## Freshness Rules

- Memory can explain why a rule exists, but it does not prove the current phone, package, image, or disk state.
- Static KB evidence can prove stock ROM structure, but not live `/data/app` shadows or PackageManager cache state.
- A built APK or image is not a live result. Use offline verifier evidence plus explicit live proof before calling a ROM state stable.
- If the user asks for device work, use escalated USB/ADB/fastboot execution and ask for confirmation before mutating actions.

## Update Rules

- Put recurring operational knowledge in the project skill or its references.
- Put generated reports and research conclusions under `docs/research/`.
- Put navigation-only material under `docs/index/`.
- Append experiment evidence to `docs/hard-rom-ota-trust.md`; update `docs/index/hard-rom-log-toc.md` when the log grows substantially.
- Do not duplicate long status ledgers across README, skill, and docs index; link to the source instead.
