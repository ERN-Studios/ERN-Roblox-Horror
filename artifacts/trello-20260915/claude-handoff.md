# Claude handoff — 2026-09-15 overnight batch (living document)

Resume point for whoever continues (Codex or a new Claude session). `claude-status.md`
holds the live partition; this file holds what is DONE, what is in flight, and the exact
next step. Updated after each milestone.

## Milestone 1 (22:05) — batch launched, #81 code complete offline

Done:
- Baseline recorded (git `d17fa28`, PlaceVersion 1894, manifest 129 → 131 after pulling
  another session's Level 2 audio scripts; that audio is preserved per owner answer #79).
- Six Opus 5 agents running (A36, A86, A80, A88, A7890, A82); Studio held by A80.
- #81 implemented in `ZyntraStore` (re-entry modal) and `RoundUI` (PARTY DOWN card),
  offline tests green (`tools/tests/test_dev_free_respawn_offer.py`, 52 checks;
  `test_reentry_dismissal.py` 37 still green). Not yet in Studio.
- #16 offline regression green: `test_round_loading_host` 83, `test_round_loading_notice`
  96, `test_round_entry_client` 57.

In flight: every agent (reports land at `agent-<card>-report.md`).

## Milestone 2 (23:00) — three agents landed offline, all lead-reviewed

- **#36 (A36)**: `ZyntraMonetization` import job + `PassRobux` stream + markers; footer in
  ZyntraStore; generator and 85-check test; generated backfill module under `_local/`
  (never commit). Live procedure = `agent-36-report.md` §4 (create
  `ServerStorage.ZyntraSalesBackfill` from the `_local` file via `execute_luau` +
  `UpdateSourceAsync`, no manifest item, delete it after `Status = done`).
- **#86 (A86, phase 1)**: Pool Slide Navigator/Controller wall-clock deadline + bounded
  clearance probes; 7-check test (3 fail on HEAD); probes in `probes/86-*.luau`. Needs a
  Studio session (see its report §3 for the seed plan). Resume A86 by SendMessage once
  Studio is free.
- **#78/#90 (A7890)**: TunnelLobbyBuilder board layout + `LOBBY_SATURATION`; 763-check
  test; capture plan in `agent-7890-report.md`. Lead corrected the board's scope footer
  and `RankingScope` attribute to match the import.
- Compile: all five touched scripts pass `luau-compile`. Baselines still green
  (support receipts 236, re-entry 37, free-respawn 52).

## Milestone 3 (23:15) — A80 landed; six reviewed scripts pushed into Studio

- A80 (#80) done and Studio-verified (see status). Studio released to the lead.
- Pushed with `--file` (backups `.studio-push-backups/20260915-200524`): RoundUI, ZyntraStore,
  ZyntraMonetization, TunnelLobbyBuilder, Pool Slide Controller, Pool Slide Navigator.
  `pull --audit`: those six match Studio; remaining drift = A82/A98 in-progress files +
  4 new scripts not yet created.
- Compile proof tonight = offline `luau-compile` 135/135 (the Studio probe is blocked by the
  sandboxed assistant thread; see status). Runtime proof per change = play sessions.
- Next in Studio (lead): #81 play verification (die in Level 1 → PARTY DOWN card → FREE
  RESPAWN // DEV), #16 L1/L2/L3 starts, then grant Studio to A86.

**Push list (historical — done 23:05)** (always `record_pending_push.py` first, then
`push_repo_to_studio.py --audit`, then `push_repo_to_studio.py --file <path>` per file):
`RoundUI`, `ZyntraStore`, `ZyntraMonetization`, `TunnelLobbyBuilder`,
`Level 2 Pool Slide Navigator`, `Level 2 Pool Slide Controller`. Expect the manifest to
show these as `pending-studio-push` already (an agent ran the record tool; the tool keeps
the original Studio hash on re-record, so conflicts are still detected). Then
`tools/studio_compile_probe.luau` in Edit mode.

## Exact next steps (in order)

1. When A80 reports: read `agent-80-report.md`, review its diff (`git diff` on its three
   files), confirm it left Studio in Edit mode with no temp instances.
2. Lead takes Studio: `python tools/record_pending_push.py` + `python tools/push_repo_to_studio.py --audit`
   + `python tools/push_repo_to_studio.py` for `RoundUI` and `ZyntraStore` (#81), then a
   play session: die in Level 1 as the owner account → PARTY DOWN card shows FREE RESPAWN //
   DEV → press → `DevRespawnStatus = RESPAWNED`, new character, tokens/credits unchanged;
   also the ZyntraStore modal path (die while a teammate is alive needs a second client —
   use `DevPartyDown` seam only for layout). Run `UIRegression.Compact("ZyntraTerminalFitMatrix")`
   (or the party-down row) to confirm the fit matrix still passes with the third button.
3. #16 Studio half: start L1, L2, L3 rounds solo, confirm loading cover lifts and the
   round starts; note that cross-server teleports are NOT provable in Studio.
4. Grant Studio to A86 (SendMessage: "Studio granted, proceed with your probe plan"),
   then A82 / A88 / A7890 for visual QA; create the new scripts in Studio first
   (`LobbyShopDisplay`, `Shop Display Client`, `Level 1 Cable Current`) via
   `execute_luau` + `ScriptEditorService:UpdateSourceAsync`, then manifest items.
5. After each agent lands: review diff, run its tests, push, compile probe
   (`studio_compile_probe.luau`), `pull --audit` = 0 drift, update this file.
6. proposal-input.md for Codex (economy constraints, persistence, anti-AFK, UI limits).
7. Ready-to-publish milestone: parity 0 drift, compile 100%, runtime evidence per card,
   Trello reflection drafted (Codex posts), export place locally, then Codex publishes.

## If this session dies

- Working copy is the truth for repo-side edits; `git status` shows every touched file.
  Nothing is committed; do not commit `_local/` or any buyer data.
- Studio may hold A80's pushed files (check `.studio-push-backups/` and
  `python tools/pull_source_from_studio.py --audit`).
- Agents cannot be resumed by another session; their reports and code on disk are the
  handover.
