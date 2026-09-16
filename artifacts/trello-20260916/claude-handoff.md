# Claude handoff — 2026-09-16 batch (living document)

Resume point for whoever continues (Codex or a new Claude session). `claude-status.md` holds
the live agent table; `claude-contracts.md` is the interface every agent built against;
`shared-coordination.md` is ownership. This file holds what is DONE, what is in flight, and the
exact next step. Updated at each milestone.

## Milestone 0 (06:22 UTC) — batch launched

Done:
- Baseline: git `aa40f70`, clean tracked tree, Studio v1907, manifest 135 scripts / 149 items.
- Owner decisions folded into the contract (milestones 5/15/35 = token/potion/shield; wheel
  45/20/20/5/10 = 1 token / 3 tokens / 1 potion / 2 potions / 1 shield; casings + results
  frame rejected; no paid spins; square shop button; #16 skipped).
- Nine Opus 5 agents running with exclusive file ownership (table in shared-coordination.md).
  Reports land at `artifacts/trello-20260916/agent-<id>-report.md`.

In flight: everything. No file has been reviewed by the lead yet. Nothing is in Studio.

## Milestone 1 (06:52 UTC) — Studio is Claude's; first three agents landed

- Codex handed Studio over at 06:35 (codex-animation-handoff.md); its two Level 3 files and
  the manifest entries are synced — never pull over them.
- Landed + lead-reviewed: A-BOARD (#100), A-REWARDS-UI (Daily Rewards page), A-EXIT (#74).
  Details in claude-status.md.
- `ReplicatedStorage.ZyntraDailyRewardsPage` CREATED in Studio with
  `python tools/install_new_scripts.py <mirror path>` (new generalised installer; dry-run with
  `--dry-run`; verified byte for byte; manifest item added as synced). Use it for the other
  five new scripts as they land.
- PUSH RULE for this batch: `record_pending_push.py` marks EVERY drifted file pending
  (including agents' half-done files), so ONLY ever push with
  `push_repo_to_studio.py --file <mirror path>` for files the lead has reviewed. Never a bare
  push. Studio's compile probe is sandbox-blocked; run the offline loop
  (`luau-compile.exe --binary` over every .lua under the mirror roots) instead.

## Milestone 2 (07:05 UTC) — four agents landed; three Studio writes

- Landed + reviewed: A-BOARD, A-REWARDS-UI, A-EXIT, A-ITEMS (claude-status.md has the detail).
- In Studio now: `ReplicatedStorage.ZyntraDailyRewardsPage` (new), `ServerScriptService.RouteMarkerService`
  (new), `Round Exit Client` and `NoiseReporter` (pushed). Manifest 137 scripts / 151 items.
  Backups: `.studio-push-backups/20260916-064222`, `20260916-064336`.
- Still to land: A-SERVER (ZyntraMonetization/ZyntraConfig), A-NOTES (4 new files), A-HUD
  (ProtectionHUD/UIDevice/UIRegression allow-lists), A-SHOP-UI (ZyntraStore/UIRegression),
  A-SHOP-WALL (LobbyShopDisplay/Shop Display Client/TunnelLobbyBuilder kiosk).
- Cross-agent strings already reconciled by the lead: marker refusal reasons (server ->
  HUD), disabled captions (rewards page -> UIRegression), ExpectedActive.Upgrades 2 -> 4.

## Milestone 3 (07:18 UTC) — server side in Studio

- A-SERVER reviewed and pushed: `ZyntraMonetization` (164995 B) + `ZyntraConfig` (with the two
  Codex crate IconIds added by the lead). Backup `.studio-push-backups/20260916-065018`.
- In Studio now: RouteMarkerService, ZyntraDailyRewardsPage (new); Round Exit Client,
  NoiseReporter, ZyntraConfig, ZyntraMonetization (pushed). Remaining: A-NOTES (4 new files),
  A-HUD (ProtectionHUD, UIDevice, UIRegression allow-lists), A-SHOP-UI (ZyntraStore,
  UIRegression terminal rows), A-SHOP-WALL (LobbyShopDisplay, Shop Display Client,
  TunnelLobbyBuilder kiosk + board already reviewed).
- Lead is running an early Play-session probe of the server side (console clean, accrual
  loop, ZyntraInventory, os.date UTC, attributes) before the UI lands.

## Exact next steps (in order)

1. As each agent lands: read its report, `git diff -- <its files>`, run its tests with
   `LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`, run the existing
   suites that load the same files (grep tools/tests for the file name), and compile every
   touched .lua with `luau-compile.exe --binary`. Fix or send back.
2. Cross-agent reconciliation the lead owns: (a) the disabled-caption strings the page agents
   use vs `UIRegression.Fit.ZyntraDisabledCaptions` (A-SHOP-UI adds them); (b) ctx fields the
   page modules read vs what ZyntraStore passes; (c) A-ITEMS/A-HUD/A-NOTES read attributes and
   bindables that A-SERVER creates — names are fixed in the contract, verify by grep;
   (d) A-SHOP-WALL needs TunnelLobbyBuilder after A-BOARD reports "released" (lead sends the
   message "Builder released" to A-SHOP-WALL).
3. When Codex releases Studio (shared-coordination.md): `pull_source_from_studio.py --audit`
   first (Codex's Level 3 files are expected to differ; pull THEIR files only), then create the
   six new scripts in Studio (execute_luau + ScriptEditorService:UpdateSourceAsync, pattern in
   tools/install_trello_new_scripts.py — adapt its FILES list), add manifest items, then
   `record_pending_push.py`, `push_repo_to_studio.py --audit`, push per file, compile probe
   `tools/studio_compile_probe.luau` (or offline luau-compile 100% if the assistant thread is
   sandboxed again), `pull --audit` = 0 drift.
4. Native QA in play sessions, per card: rewards tab (claim/spin/countdown/phone), wheel
   replay, potion in each level, markers, equipment HUD touch slots, hold-L leave (click alone
   must NOT leave), board columns, shop terminal desktop+phone, wall shop clearance walk,
   UIRegression.RunAllSummary(), Round Completion Test Suite.RunAll().
5. Release checklist (README "Before the next publish") + this batch's evidence; then publish
   to the same game; Codex saves backup/reports and shuts down (never the lead).

## If this session dies

- The working copy is the truth for repo-side edits; `git status` shows every touched file.
  Nothing is committed; do not commit `_local/`.
- Agents cannot be resumed by another session; their reports and code on disk are the
  handover. A half-finished agent leaves a partially edited file: diff it against HEAD.
- Studio has not been touched by Claude in this batch.
