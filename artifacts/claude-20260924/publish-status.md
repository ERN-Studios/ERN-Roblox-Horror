# Publish status, 2026-09-24

No new publish was made from this session. Everything built on `claude/trello-20260921` is already
live in **v2036**.

- The friend's Codex session publishes from the same Studio place (`codex/level5-indoor-suburbs`, Level 5).
  It merged this branch at `fd8225e` (up to `655ef9e`) and published **v2036 at 2026-09-23T23:05:12Z**.
  Receipt: `artifacts/level5-mold-20260924/publication-v2036.json` on that branch; its
  `studio-source-verification.json` records 178/178 scripts matching the repo byte for byte.
- `pull_source_from_studio.py --audit` run from a checkout of `origin/codex/level5-indoor-suburbs`
  (59e78e5) on 2026-09-24 reported **178 matched, 0 drift**, so Studio still holds exactly the v2036 source.
- That source contains this branch's markers `CHALLENGES_20260923`, `QUEUE_FULL_FASTSTART_20260923`,
  `NO_LEVEL3_CONTINUE_20260923`, the death-card `overlapsModal` fix, the RECORDS tab and `markRunAided`.
  This branch's only commit after `655ef9e` is `b74883b` (screenshots, no runtime code).
- UIRegression on that build in a play session: **2828 checks, 0 failures, 22/22 scenarios**.

Publishing again would only duplicate v2036, and it would also ship any Level 5 work the other
session had not yet published. Against this branch's working tree the same audit shows 13 scripts
drifted. They are Codex's Level 5 and integration changes (GameManager, RoundUI, Round Completion
Routing, TunnelLobbyBuilder, Round Entry Client, Level 5 systems). They belong to their branch/PR,
not this one.
