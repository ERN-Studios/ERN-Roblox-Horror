# Public Level 3 promotion — verification handoff

Target: existing place `131311258779917`, universe `10559217407`.
Studio is authoritative. This task promotes the revised Level 6 art/layout kit
through the existing public Level 3 round, objective, entity, lighting and reward
contracts. The original Level 6 DEV path and Level 5/6 access remain separate.

## Current status and authoritative records

The initial 14 scoped Source changes passed native Source/editor compare-and-set
at 19:59:36Z. Two accepted review fixes passed fresh Source/editor CAS at
20:23:00Z: GameManager final SHA `ac252224…`, R4 Builder `16d19817…`.
See [initial install](install/install-receipt.json) and
[post-review install](install/post-claude-scoped-install.json).

The expected final 14-path list is
[final install manifest](../../tools/level3_promotion_20261002/install-snapshot/final-manifest.json).
It is an expected source list, **not an authoritative after-export receipt**.
Final source authority is the fresh Edit capture's Source/editor pairs and
`backup/after/source-scope-verification.json`, then
`backup/after/repository-mirror-export.json`. Both receipts passed: 231 Source/editor
pairs read twice, exactly 14 task changes (11 edits and three additions), and
all 22 original Level 6 Sources unchanged. All 14 exported mirrors match exactly.
Earlier candidate/final-named manifests and old draft hashes must
not override those fresh exported sources.

Publication is **not verified**. Saving, installation, export or a commit does
not establish a successful Roblox publish. The native UI automation pipe failed;
the root is handling the remaining capture/publication path.

## Verification actually performed

- Native single-player Studio Play used multiple normal Level 3 queue loadouts.
  Five CDs were collected and inserted using actual E inputs, with character
  repositioning and a temporary Play-only entity pause to isolate objectives.
  No CD/objective/Escaped state was forced. Collection, carried counts and
  five-CD unlock are recorded in [collection](playtest/five-cd-actual-e-collection.json)
  and [unlock](playtest/five-cd-unlock.json).
- The exact hall midpoint did not trigger the finale; actual W input beyond it
  did. That crossing occurred while the entity was paused: the original receipt's
  introductory claim is corrected by [pause correction](playtest/midpoint-pause-correction.md).
  A separate [unpaused movement sample](playtest/actual-finale-unpaused-movement.json)
  recorded CHASE movement at speed 28. This is not an unassisted difficulty run.
- Actual W input reached the escape detector after five native collections and
  insertion; Escaped became true and normal result settlement returned the player
  to R4. The first-clear GUI was observed. Live badge awarding remains unverified.
  See [escape/return](playtest/actual-escape-return-and-board-smoke.json).
- The final-source original supporter-board renderer reacted to temporary row
  attributes and displayed rank `01` / `12,345 R$`; attributes were restored and
  the provider value stayed unchanged. This proves a renderer subscription smoke,
  not DataStore totals, board readability, occlusion or multiplayer replication.
  See [final board smoke](playtest/final-source-live-board-smoke.json).
- Offline exact-source checks passed: eight layout/world syntax compiles,
  1,349 geometry/layout checks and 26 dressing lifecycle checks; four gameplay
  compiles and 18 mocked cases; 27 warmup/admission scenarios with 86 semantic
  checks; final TTL writer regression with 32 checks; R4 guard correction with
  six mocked scenarios. These are mocks/pure-generator fixtures, not native
  multiplayer or performance passes. Receipts are under
  `../../tools/level3_promotion_20261002/{public3,gameplay_boards,admission}`.

## Completed external reviews and fixes

Two actual tools-disabled Claude Opus 5.5 reviews ran at maximum effort. The
gameplay/board review completed in 646.215s; the warmup review in 702.931s.
Their limited-input verdicts were material-fix/uncertain, **not whole-task clearance**.
Earlier attempts timed out and must not be counted as completed reviews.

1. R4 re-entry now restarts its existing access guard before board lookup/transfer;
   transfer errors are protected and rolled back. See
   [board review reconciliation](../../tools/level3_promotion_20261002/gameplay_boards/claude-review/review-status.md)
   and `gameplay_boards/r4-claude-fix/verification-receipt.json`.
2. Public Level 3 final cohort snapshots now last 1,320 seconds so a cold kit wait
   cannot expire the source's final roster. Other levels keep 120 seconds. The
   exact-source mock reproduces old expiry at 130s and verifies final admission
   at 130s, 1200s and 1259s. See
   [warmup reconciliation](../../tools/level3_promotion_20261002/audit/warmup-claude-reconciliation.md)
   and `admission/post-review/cohort-ttl-test-receipt.json`.

## Limits and remaining handoff

Reserved-server transport/multiplayer cohort admission and native Level 2 -> 3
tube continuation were not exercised. Level 2 active CPU/memory/navigation/retry
and distinct pump escalation checks remain unverified. Studio's observed
approximately 15 Hz background throttling is unsuitable for a performance PASS;
no reliable server CPU/memory verdict is claimed.

The actual before native place was saved and verified outside Git at
`/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/before/before.rbxl`.
Its Source/root structure verification is recorded in
[before summary](backup/before/backup-source-structure-summary.json); strict
whole-forest property equality was not claimed. A raw native forest/offline
recovery must be distinguished from an actual Studio-native after Save/Download.
That historical backup directory became unavailable during an external filesystem
change; this task performed no deletion or relocation. Do not claim it is still
present. The complete fresh 231-Source snapshot was recovered and SHA verified in
two independent locations: `/private/tmp/level3-promotion-source-recovery-20261002`
and `/Users/zeanjuul4/Projects/RobloxStudioBackups/20261002-level3-promotion/after/direct-source`.
These Source snapshots are not a full native place backup. The native computer
control pipe failed, MCP HTTP export was denied its Network capability, and the
direct native forest return was truncated by the 100,000-character tool limit.
No final after-native Save or successful publication is established. Explicit
user approval for AppleScript as an alternative UI method is pending.

Inspect the final export, exact staged diff and task-only file list before
committing. Local commits, GitHub pushes and Roblox publication are separate
actions. No index, commit or push was performed by the handoff writer.
