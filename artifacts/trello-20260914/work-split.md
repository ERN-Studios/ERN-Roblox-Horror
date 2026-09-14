# To Do work split — 2026-09-14
Scope: ONLY the 13 cards in todo-snapshot.json, captured directly from To Do. Do not open other lists or linked completed cards. Level 4 deferred entirely.
Claude owns cards 45, 64, 68, 69, 70, 73, 74, 76. Codex owns 18, 44, 67, 71, 75.
Claude is primary implementer for all shared game/player/UI/profile/queue systems and purchase alert workflow. Delegate independent workflows to Opus 5 agents where available, then personally quality-check the complete result using Fable 5.1 Max already configured.
Codex owns lobby ceiling pattern implementation (locate its dedicated controller) and Level 3 finish-entity fix (Level 3 AI/objective/controller files). Coordinate via ownership before editing those. Codex also handles token-item research, audience eligibility investigation, gift identity and execution.
Claude: read CLAUDE.md, inspect git status (many existing untracked artifacts), audit Studio before editing. Preserve existing work. Own the Studio bridge exclusively while implementing; Codex will avoid bridge use until screenshot shows you done.
Do not read cards outside snapshot. Existing implementation may already cover older ESP/free-respawn requests: verify and fix gaps instead of duplicating it.
Implement real features, tests and review. Follow repo source contract and compare live hashes; no blind overwrites. Prefer existing files/modules. Do not publish production or spend funds. Purchase alert infrastructure can be prepared and locally tested, but external Discord sends or channel permission changes need the user's concrete authorization. No actual gift grant by Claude.
For #73, use explicit safe gameplay audio/UI state rather than generic GUI replication, and never expose dev ESP to spectators.
For #68, retain tab button size but reduce content and check phone/tablet and PC.
For #69, preserve ProcessReceipt grant + permanent dedupe; best-effort notifications off the grant critical path, actual CurrencySpent, secrets server-only, mock retry/failure tests. Document operational prerequisites honestly.
For #70, persist first-login status safely; no guide reappearing on every join.
For #74, player-local return-to-lobby without ending other players' rounds.
For #76, full-party visible physical barrier must admit existing members and let them leave; reopen when capacity frees.
Ask questions in the Claude chat if anything truly needs a product decision. Continue independent work. Write artifacts/trello-20260914/claude-handoff.md with per-card status, files, tests, Studio parity, open questions and exact blockers. End chat with an easily visible DONE / NEEDS INPUT heading. Codex monitors only by one screenshot every 10 minutes.

