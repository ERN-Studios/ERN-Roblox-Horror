# BACKROOMS: STAY QUIET [CO-OP HORROR] — working notes for Claude Code

## Where this session is running matters

**Roblox Studio can only be reached from a session running on the owner's Windows
PC.** The bridge is `%LOCALAPPDATA%\Roblox\mcp.bat`, launched through `cmd.exe`
by `tools/sync_from_studio.py`; Studio's plugin talks to it over loopback.

| Session started from | Runs on | Studio reachable? |
|---|---|---|
| VS Code extension, or `claude` in a terminal on the PC | that PC | **yes** |
| claude.ai/code, mobile, or any cloud/web session | Anthropic Linux VM | **no** — no `cmd.exe`, no `%LOCALAPPDATA%`, no route to the desktop |

A cloud session can still do everything else: read and edit the mirrored
scripts, run the analyzers, commit, push, open PRs. It just cannot read from or
write to the live place. Check with `uname -s` — `Linux` means no Studio.
Don't spend time debugging the MCP connection in that case; hand the Studio step
to a local session instead.

## The repo is a one-way mirror of Studio

Studio is the source of truth. Folders mirror the Explorer 1:1 and files are
named `Name.ClassName.lua`. `studio-sync-manifest.json` holds a sha256 per
mirrored script plus a `status`:

- `synced` — repo and Studio agree.
- `pending-studio-push` — the repo copy is NEWER; it is queued for Studio.
  `studioSha256Before` records what Studio should still hold, for conflict
  detection.
- `studio-push-conflict` — a push found Studio had drifted; needs a decision.

**Never run `pull_source_from_studio.py` while entries are pending** — it would
replace those newer repo files with Studio's older source. The tool now skips
them by default (`--force` overrides).

## Syncing

```
python tools/pull_source_from_studio.py --audit   # Studio -> repo: what drifted
python tools/pull_source_from_studio.py           # pull it

python tools/record_pending_push.py               # repo -> Studio: queue edits
python tools/push_repo_to_studio.py --audit       # classify against live Studio
python tools/push_repo_to_studio.py               # apply (two-phase, verified)
```

Writes into Studio must go through `ScriptEditorService:UpdateSourceAsync` —
raw `.Source` writes leave LocalScripts running stale bytecode. Reads must go
through `execute_luau` reading `.Source`, because `script_read` can serve a
stale editor buffer after a programmatic write.

`tools/tests/test_push_repo_to_studio.py` verifies the push tool against a fake
Studio without touching anything real (needs a `luau` binary; see the file).

## There is a code knowledge graph — use it before grepping

`graphify-out/` holds a graph of this codebase: every script, the symbols in it,
and what calls what. It is built by the `graphify` CLI (already on PATH) with no
LLM cost. **Start here instead of grepping blind** — it answers "what touches
this?" and "how does A reach B?" in one call.

```
graphify explain "Level 2 Round Adapter"    # what a node is and what it neighbours
graphify path "GameManager" "Pool Foam Navigator"   # how one reaches the other
graphify update . --force                   # rebuild after code changes
```

`graphify-out/GRAPH_REPORT.md` is the human-readable summary: node and edge
counts, and the named community hubs, which is the fastest map of the project's
actual structure. `graphify-out/graph.html` is an interactive view.

Five things to know:

- **Check freshness first.** The report records the commit it was built from.
  Compare it with `git rev-parse HEAD`; a stale graph will confidently describe
  code that no longer exists. On 2026-09-02 its top community hubs were still
  named after the Slidemouth and Pool Slide encounters, both long deleted.
- **`--force` is required after deletions.** `graphify update` refuses to write a
  graph with fewer nodes than the last one unless forced, which is exactly the
  case after a refactor that removes code.
- **Run it only at the repo root.** Running it inside a service folder leaves a
  nested `graphify-out/` inside the Studio mirror — four of those had accumulated
  by 2026-09-02, 42 MB of stale duplicates. All `graphify-out/` paths are
  gitignored at any depth, so they never reach GitHub, but they do clutter the
  mirror the sync tools walk.
- **`.graphifyignore` keeps retired code out.** `ServerStorage/Archive/` is real,
  parseable Lua, so graphify indexed it: 442 of 2475 nodes (18%), and two of the
  graph's largest communities were named after the retired Slidemouth. The
  archive is now excluded by `.graphifyignore` at the repo root — the files are
  untouched on disk, they just no longer answer searches with dead code. Note
  the file is only consulted on `--force`; a plain `update` leaves old nodes in
  place until you force a rescan.
- **The graph under-covers 12 files, and one of them is GameManager.** The
  extractor stops part-way through a file it cannot fully parse and keeps
  whatever it got, reporting only a `syntax errors ... partially extracted`
  warning. Across the mirror it reaches 81% of Lua lines, but the misses are
  concentrated:

  | Script | Lines | Symbols in graph |
  |---|---:|---:|
  | GameManager | 2640 | 4 |
  | Level 3 Test Suite | 3577 | 9 |
  | Level 3 Mall Manager AI Controller | 3586 | 44 |
  | Level 3 Lighting Controller | 896 | 1 |

  So **a graph query that returns nothing about GameManager is not evidence that
  GameManager does not touch the thing** — grep those four directly. The reported
  error line is where the parser gave up, not the cause: the constructs sitting on
  those lines (`export type`, `(): boolean?`, `x.y += 1`) all parse fine in
  isolation, and it is not CRLF or non-ASCII either. graphify ships as a compiled
  binary, so this is a property of the tool, not something to fix here.

## Current state (2026-09-02)

`main` is level with `origin/main` and the manifest has no pending entries.
**Do not copy the script count into prose** — it has been wrong here three
times (114, then 134, then 91, now 101). `studio-sync-manifest.json`'s `counts`
field is the only place it is true; read it there.

Verified 2026-09-02 after the round-start fixes: `studio_compile_probe.luau`
compiles every script in the place, and `pull_source_from_studio.py --audit`
reports 0 drift with every manifest entry `synced`.

**Studio is edited from more than this session.** A Codex session changed 12
scripts in the place on 2026-09-02 that the repo knew nothing about; its own
backups sit in the ServerStorage root as `CodexBackup_20260902_*`. Run the
audit before you edit, not just before you commit.

**Level 2 has exactly one hostile: Pool Foam.** Two others came and went. The
Slidemouth was retired on 2026-08-31 in favour of the Pool Slide; the Pool Slide
was measured on 2026-09-02 to never once spawn successfully on a generated map —
its failing spawn retried forever and cost 78% of the server's frame budget
(13 FPS, 59 with it paused) — and was deleted entirely, backups included.

> **Pool Foam has no test suite.** The only hostile suite this project ever had
> went into the archive with the Slidemouth
> (`ServerStorage.Archive.Level2RetiredSlidemouth_20260831`, 391 checks). The
> Pool Slide was built without one and failed in every round for days without
> anyone noticing, until a frame-time measurement found it. That is the argument
> for writing one.

**Level 3's seed guard was fixed on 2026-09-02** to match Level 2's, and now
publishes `Level3_SeedPinned`.

**Level 1's five runtime scripts moved into `ServerScriptService."Level 1 Systems"`
on 2026-09-02** so all three levels read the same way: MazeGenerator,
PuzzleManager, EntityAI, EntityAnimation, EntityKill.

Two rules follow from that move, and both have already bitten this project once:

- **Look them up recursively.** `ServerScriptService:FindFirstChild(name)` returns
  nil from inside a folder, and all seven call sites that do this fail SILENTLY
  on nil -- their loops simply do nothing. That is how every Level 2/3 round once
  came to start Level 1's fuse puzzle server-side. Pass `true`.
- **`script.Parent` is no longer ServerScriptService** for those five. They reach
  the shared services in the root (`NoiseRegistry`, and anything added later)
  through `game:GetService("ServerScriptService")`. Two `script.Parent` lookups
  were missed on the first pass and yielded forever until the console showed it.

### Added 2026-09-03 (afternoon session)

- **GameManager owns the Level 1 entity outside Level 1 rounds.**
  `setLevelOneEntityActive(false)` at boot and after every cleanup stores
  `Workspace.Entity` in ServerStorage as `Lobby Stored Level 1 Entity` (root
  anchored) and disables EntityAI, EntityAnimation and EntityKill; `ensureWorld`
  brings it back before `GenerateWorld`. The saved place still holds the entity
  in Workspace; that is fine, boot moves it. The Level 2/3 adapters keep their
  own isolate/restore for their rounds.
- **RoundUI sits exactly at Luau 200-register limit.** Its main chunk has 200
  top-level locals; one more fails to compile ("Out of local registers"). Put new
  state in a `do ... end` block (the closure keeps it as an upvalue), and run the
  compile probe after every RoundUI edit.
- **Flashlight beam numbers live in `ReplicatedStorage.FlashlightProfiles`**
  (`Own`, `Mount`, `Mate`, `Spectate` x `BASE` / `L3` / `L3_BLACKOUT`). The sets
  differ on purpose (they are what each script carried); the double-render is
  still an open owner decision.
- **Level 2 remotes** are in `ReplicatedStorage."Level 2 Remotes"` (`Level 2
  Alert Event`, `Level 2 Sound Event`); Pool Foam keeps its own folder.
- **New scripts cannot be pushed by the tools.** Create them in Studio first via
  `execute_luau` + `UpdateSourceAsync`, then add the manifest item with
  `sha256_of` / `canonical_bytes` from `tools/studio_source_contract.py`.
- **`require` inside `execute_luau` is a separate module instance**, even on a
  play session Server datamodel: module-local session state is invisible there.
  Read attributes and instances instead.

### Added 2026-09-04

- **Discord -> Trello bot** lives in `tools/discord_trello_bot/` (Python, discord.py,
  run by hand on the owner's PC for now; a Render Background Worker is the
  planned host, see its README). A forum post in #bugs becomes a card in
  *To Do* with label Bug; one in #feedback becomes a card in *Ideas* with label
  Feedback. The bot reacts with eyes when the card exists and with a tick, a reply
  and a *Fixed* forum tag when the card reaches *Done* (polled every minute);
  its own reactions are its only state. Setup steps and env vars are in its README. Zapier was rejected because
  its Discord forum trigger fires on every reply and does not deliver the post body.

Afternoon batch (see `HANDOVER-2026-09-04.md` for the verification record):

- **PARTY DOWN contract on `RoundStatus`.** When the last living player dies,
  GameManager fires `"partydown", 15, lastDeathName` once (name is nil when the
  party emptied by a *leave*), and `"partydownclear"` when a re-entry raises
  `aliveCount` or the round is torn down under the window; `"lose"` is its own
  clear. RoundUI renders the card in a `do ... end` block (register limit) and
  reads the store's credit/price/product id from client-local player attributes
  `ZyntraReentryCredits` / `ZyntraReentryPrice` / `ZyntraReentryProductId` that
  ZyntraStore publishes -- never trust those server-side. `PartyDownCardOpen`
  (card drawn) and `PartyDownWindowOpen` (window owns the purchase) are two
  different facts; ZyntraStore's own re-entry modal stands down on the second.
- **Emergency Re-entry reserves the credit before it respawns** (`useReentry` in
  ZyntraMonetization): reserve -> Invoke `ServerStorage.ZyntraReentry` -> refund
  keyed on a per-attempt token, three retries then a `[Zyntra] Re-entry refund
  FAILED` warn. `ProcessReceipt` auto-uses a fresh credit when the buyer is
  dead in a live round (`reentryEligible`, a superset of OnInvoke's refusals).
- **Badges** are keyed in `ReplicatedStorage.ZyntraConfig.Badges`
  (`FirstClearLevel1/2/3`, `CampaignComplete`); 0 = disabled. The profile now
  carries `LevelsCleared` (string keys) and `AwardedBadges`. `AwardBadge`
  RETURNS false rather than throwing for a wrong/disabled id -- read the return,
  never record an award on pcall's ok alone.
- **Pool Foam hears `NoiseRegistry`** (config block `Hearing` in its
  Configuration). The `Remotes.ReportNoise` intake is module-scope in the
  controller (EntityAI is disabled for the whole of Level 2, so nothing else
  drains that remote there); NoiseReporter reports on levels 1 and 2. Hearing
  only steers `bestTarget`/`choosePatrolPosition`; the look-latch is untouched.
  `BeingChased` / `Level2_PoolFoamTargeted` are reference-counted across the
  five entities (`markChased`) and cleared to false in `Controller.Stop`.
- **Level 3 hiding holds two per table** (`Hiding.HideOccupantCap`, lanes at
  ±`HideOccupantLateralOffset` in anchor space); the Table Hiding Client sets
  `ProximityPromptService.Enabled = false` while hidden so E cannot re-trigger
  a prompt. **The Mall Manager checks tables** (`Configuration.TableCheck`):
  state `TABLE_CHECK`, `Level3_MallManagerTableCheckIndex/EndsAt` in the state
  folder (server time), 2 s reaction window, flush through
  `HidingController.FlushAnchor` to the far side with `FlushImmunitySeconds`
  of attack immunity, per-anchor and global cooldowns, and a mid-hunt detour
  only toward a table closer than the nearest exposed player.
- **Gamepad:** L2 (hold) sprints, R1 toggles the flashlight; `sprintRequested()`
  in NoiseReporter is the one definition of "asking to sprint".
- **RoundUI no longer writes the spectate camera**; SpectateController is the
  only writer and stops itself when `RoundActive` goes false (guarded on its own
  `spectating` flag so JumpscareUI's kill cam is not knocked back).
- **Playtest hooks that bypass the DevAccess remote gate:**
  `ServerStorage.ZyntraReentry:Invoke(player)`,
  `ServerStorage.Level3DevSkipToPreBlackout:Invoke()`, and a ProximityPrompt only
  shows/triggers while inside the camera frustum (point a Scriptable camera at it
  first). The station recipe is in the project memory (`mongotv-playtest-recipe`).

### History — the 2026-08-19 audit (done, kept for context)

Branch `claude/roblox-code-audit-di6qxi`, PR #1 (merged): a project-wide audit of ~45k
lines — real bugs, dead code, removed-feature leftovers, duplicate work and
optimizations. **All 37 queued scripts were pushed into Studio on 2026-08-19
and verified byte-for-byte; the manifest holds no pending entries.** The PR
body is the full report.

Landing them turned up three faults in the sync tooling, all now fixed:
`select_studio` only retried one obsolete wording of StudioMCP's cold-start
error and compared place names before Studio began appending `(placeId: N)`;
the post-write verification could read stale metadata against fresh chunks and
report a failed push that had in fact landed; and the staging buffer could not
carry a source of 200k characters or more, which is why Level 2 World Builder
(235,839 B) needed the buffer to spill into numbered child parts.

Deliberately left alone and awaiting a decision from the owner: teammate
flashlights render twice (client MateBeam + FlashlightSync mounts); Level 3
room wall-art tables are keyed to retired room ids so generated rooms get no
drawings. ~~The Slidemouth controller is complete but nothing starts it~~ —
settled 2026-08-31 by retiring it in favour of the Pool Slide, which left the
open question above: the replacement has no test suite.

Also landed 2026-08-19 (Studio first, then mirrored, manifest updated):

- **`Level2Seed = 0` no longer pins the map.** The guard was
  `type(requestedSeed) ~= "number"`, and 0 is a number, so a zeroed attribute
  silently rebuilt seed 0's layout every round. 0, negatives, NaN and
  non-numbers now all mean "pick a random seed"; only a number ≥ 1 pins.
  `Level2_SeedPinned` in the state folder shows which mode a round used.
  **`Level 3 Round Adapter` carried the identical bug** at its own seed read —
  latent, because no `Level3Seed` attribute was set. Fixed 2026-09-02 with the
  same `pinnedSeedOverride` helper, plus a `Level3_SeedPinned` readback and a
  random path that lands in [1, MAX_SEED - 1] so it cannot produce the 0 the
  guard rejects.
- The exit-bearing Grand Slide Hall now has its own size floor
  (`ExitHallMinimumWidth`/`Depth` = 210×200) plus `ExitHallMaximumShellGap`
  = 80, and `GenerationAttempts` went 40 → 300 so the deterministic recovery
  seed stays unreachable. Details and the measured numbers are in
  `HANDOFF-LEVEL2.md`.
- **The Level 1 Mimic clones the source player's character wholesale**
  (`RoundUI.LocalScript`, `mimicBuild`), so anything parented to a character
  rides onto the apparition. The Zyntra Supporter pass parents a BillboardGui to
  the Head, and the Mimic was wearing it — a purchase badge over a monster, and
  an instant tell. The clone now strips every `BillboardGui`. Remember this
  before attaching anything new to a player character.
- **Level 2 now holds a loading cover while the client streams in.** The screen
  is shared (`RoundUI.LocalScript`), not per level; it is coloured by
  `LOADING_PALETTES` and Level 2's is the water blue. `poolaccess` no longer
  uncovers — the client reports `entryready` on the `RoundStatus` remote once
  there is real ground under it, and GameManager holds the round until then,
  the way the elevator ride holds Level 1. **Level 1 and Level 3 are
  unchanged.** See `HANDOFF-LEVEL2.md` §2b, including the three independent
  timeouts that stop the cover ever trapping a player.

## House rules

- Do not remove or move in-game objects (walls, props, world geometry) unless
  asked. When asked, list what you propose to remove and get a decision per
  item first — never delete on your own judgement.
- **`ServerStorage.Archive` holds every retired backup**, gathered there on
  2026-09-02 so the root stays readable. Do not audit, clean or "tidy" its
  contents. Two folders were deleted that day by explicit decision
  (`LobbyBackup_20260731`, `Level2Backup_20260805`); both are recoverable from
  git history at `c2b7527`.
- **The loose MeshPart templates in the ServerStorage root are generated, not
  authored.** `Level 2 World Builder` builds them through
  `AssetService:CreateMeshPartAsync` and parents them there. Its Lua cache is
  module-local and dies with the VM while the MeshPart is saved with the place,
  so it used to leak one copy per Studio session — 21 duplicates had built up
  by 2026-09-02. Both template loaders now adopt an existing copy by name and
  MeshId first. If duplicates reappear, that adoption has been broken.
- `ServerStorage.Project Mirror` is an unused third-party free-model asset
  (credits Dragonfire1710, boatbomber), not project code and not a backup.
- Testing vs production values are documented in README.md; both are currently
  at production settings.
