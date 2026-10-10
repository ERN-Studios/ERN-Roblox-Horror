# Historical reference: workflow-and-history

Read only the section needed for the current task. This is retained history, not current startup policy.
CLAUDE.md and AGENTS.md supersede old model, ownership, testing and sync commands below.
Never automatically import this file into startup context. Dates and environment limitations may be obsolete.

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
  of attack immunity. **Changed 2026-09-09:** the hunt targets the nearest living
  player even while hidden, approaches their table and starts the check on
  arrival. Targeted checks bypass random sweep bias and patrol cooldowns;
  entering a table does not clear the AI-owned `BeingChased` flag.
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

### Added 2026-09-05

Batch 2 of the deep audit (`docs/AUDIT-2026-09-04.md`); the record is
`HANDOVER-2026-09-05.md`.

- **More than one Claude session works in this checkout and in Studio at the
  same time.** On 2026-09-05 another session patched badge ids into
  `ZyntraConfig` in both the working copy and Studio, left `assets/badges/`
  and `docs/EMERGENCY_REENTRY_VALIDATION_2026-09-05.md` untracked, and pushed
  `EntityAI` / `SoundController` / `RoundUI` edits straight into Studio. Before
  a push: `git status` for foreign untracked files, `pull --audit`, and expect
  the push tool to report a CONFLICT for any script the other session touched —
  merge their Studio change into the working copy first (chunk checksums over
  `execute_luau` find it), never `--overwrite-conflicts` blind.
- **Accessibility contract:** `ZyntraConfig.AccessibilitySettings` lists the
  four keys (`ReduceCameraShake`, `ReduceFlashing`, `CaptionsEnabled`, hidden
  `DisableCaptions`). Key = profile `Settings` field = player attribute name =
  the only payload `ZyntraAction "SetAccessibility" {Key, Enabled}` accepts.
  The Zyntra terminal's SETTINGS tab is the UI and it is lobby-only (the
  terminal opener stands down in rounds), an open product decision.
- **DataStore write discipline in ZyntraMonetization:** a transform that
  returns false now CANCELS `UpdateAsync` (callback returns nil); the session
  copy adopts the profile the callback read. Never write a transform that
  mutates `current` and then returns false. Write-bearing actions have a 1 s
  per-action window; mute and accessibility writes sit behind escalating/6 s
  floors; a pass read that never answers returns nil ("unknown"), never false.
- **Pool Foam has a server proximity latch** (`Observation.ProximityLatch*`:
  8 studs, 7 s, standing still under 3 studs/s) as a backstop against a client
  that never reports a look. It only ever adds a latch. The look-latch is still
  the mechanic; `FreezeWhileObserved` is false and the statue branches never run.
- **Level 1 prompts are revalidated server-side** by `canUsePrompt` in
  PuzzleManager (shaped like Level 2's `canUsePump`); a dead or escaped
  participant can no longer trigger relays, boxes or levers.
- **Level 3 blackout scream strobe** runs at `BLACKOUT_FLICKER_INTERVAL` 0.17 s
  (under 3 whole-scene flashes/s; 0.15 is the arithmetic floor, do not go
  below); with `ReduceFlashing` the strobe becomes a cosine swell. The
  blackout sweep is 2/s, not event-driven, because the server flips Lights
  inside the world when CDs go in.
- **Level 2 cues:** `workspace.Level2FoamLethal` flips true at the pump that
  enables attacks; the pump motor is a 3D cue at the pump for everyone
  (`Level 2 Sound Controller.playPositionalCue`); `workspace.Level2_ExitPosition`
  drives the objective panel's bearing once the doors are powered.
- **UIRegression:** `Fit.ZyntraDisabledCaptions` now recognises `LEVEL n ONLY`
  (the 22 Dev-tab rows), the objectives-panel row forbids `QueueHostPanel`,
  and the terminal fit matrix covers the SETTINGS tab. Configuring a queue over
  the remote instead of the CreateParty button leaves the host panel open and
  fails that row — restart play before measuring.
- **`HANDOFF-LEVEL2.md` is deleted**; README's "How a Level 2 round runs" holds
  what was still true. `docs/AUDIT-2026-09-04.md` lists what remains open
  (robustness, controller and Pool Foam audio are Trello cards).

### Added 2026-09-14 (Trello To Do batch; record in `artifacts/trello-20260914/claude-handoff.md`)

- **Three new scripts**, created in Studio first and then given manifest items:
  `ServerScriptService.PurchaseAlerts` (ModuleScript), and the LocalScripts
  `StarterPlayerScripts."First Entry Guide"` and `"Round Exit Client"`.
- **Dev cheats (cards 45/64).** `DevControl` gained `playerEsp` (the server
  answers ONLY the requesting developer with a position snapshot on the same
  remote; markers live in that client's `PlayerGui.DevPlayerESP` and never
  replicate) and `freeRespawn` (`ServerStorage.ZyntraReentry:Invoke(player,
  true)`; readbacks `DevRespawnBusy/Status/Serial`). `ZyntraReentry.OnInvoke`
  is now one body for both paths: paid reserves the credit in Monetization as
  before, free needs DevAccess + a dead InRound body; one request in flight per
  player. DEV rows FREE RESPAWN and PLAYER ESP sit in the terminal.
- **Back to lobby (card 74).** Client `RoundStatus "leaveround"` → GameManager
  `handleLeaveRoundRequest` (assigned inside playRound, nil outside a
  lifecycle) removes only that player from `alive`, `participantSet` and the
  `participants` roster, answers `leaveack`, then `teleportPlayersToLobby` on a
  reserved server or `returnPlayersToLocalLobby` in Studio. Studio Level 2/3
  park the lobby, so there it answers `leavefailed`. UI: `Round Exit Client`
  (chip top-left of the safe area while alive; the spectate band's button fires
  `PlayerScripts.RoundExitPrompt`); `RoundExitPromptOpen` while the card is up.
- **Spectator parity (card 73).** SpectateController publishes the
  client-local `SpectateTargetUserId` next to `Spectating` and reports
  `RoundStatus "spectatetarget", userId`; the server publishes the replicated
  `SpectatorCount` on the watched Player (only dead/escaped participants count,
  only towards living participants; cleared when the lifecycle closes).
  SoundController, both level sound controllers, Level 2 Objective UI, Level 3
  Reader Client and PuzzleUI resolve their audio/UI subject from those two
  attributes. Breathing stays own-only (stamina is client-local); ProtectionHUD
  is untouched. Dev ESP is client-local by construction.
- **Full-party barrier (card 76).** Collision groups `QueueBarrier` and
  `QueueMember` (mutually non-collidable, both clear of `DevNoclip`).
  `enforceStationCapacity` raises `Station<N>FullBarrier` (24 ForceField
  segments, `CanQuery = false` so the push-out's overlap checks ignore it) when
  a configured party is full and moves accepted members' parts to
  `QueueMember`; it drops the wall and restores `Default` when capacity frees,
  on cancel or on an unconfigured station. The Heartbeat push-out is still the
  authority. `tools/tests/test_queue_barrier.py`.
- **First entry guide (card 70).** Latches once at `ZyntraProfileLoaded` on
  `ZyntraLobbyBriefingPlayed ~= true` (a brand-new profile), no new DataStore
  field. Pathfinding beam chain to the nearest Level 1 `LaunchZone` plus a
  "LEVEL 1 START HERE" billboard; ends on pad arrival, InRound or a queue
  event. A `BeamTexture` string attribute on the script auditions a texture.
- **Purchase alerts (card 69).** `PurchaseAlerts.Notify` runs from
  ProcessReceipt only on a first-time grant (`changed`), pcall'd, never
  yielding. Config is Roblox Secrets `ZYNTRA_PURCHASE_ALERT_URL` /
  `ZYNTRA_PURCHASE_ALERT_TOKEN`, or `ServerStorage.PurchaseAlertConfig`
  attributes `Endpoint`/`Token` for Studio. Roblox cannot post to discord.com,
  so `tools/purchase_alert_relay/relay.py` forwards. NOT operational until the
  owner completes the relay README's prerequisites (channel, webhook, host,
  Secrets, HttpEnabled). `tools/tests/test_purchase_alerts.py`,
  `test_purchase_alert_relay.py`.
- **Shop/Upgrades tiers (card 68).** ZyntraStore content has phone
  (`fit.Compact and fit.Touch`), tablet (`fit.Touch`) and pointer tiers; the
  tab bar is unchanged and the pointer tier is the authored card to the pixel.
  `tools/tests/test_zyntra_store_compact.py`.
- **Feedback gift (card 71, Codex).** `refreshPasses` grants UserId
  10152463945 once (`Grants.FeedbackThanks20260914`: +1 stamina, +1 battery,
  +10 tokens); it lands on that player's next successful profile load on a
  server running this build. `tools/tests/test_feedback_gift.py`.
- **Codex's cards 67/75** landed from `artifacts/trello-20260914/
  {ceiling,finale}-proposed` after canonical-hash verification: five on/off
  ceiling patterns; the Level 3 finale spawns at the level entry (`MazeStart`
  + 8/12/16/20 studs forward) once the first survivor is 4 studs into the open
  exit hall. Physical chase pacing was not measured.
- **Offline test hygiene.** `test_support_product_receipts.py` and
  `test_token_grants.py` carried stale markers (fixed). `test_level3_run_in_exit`,
  `test_level3_hidden_chase` and `test_level3_slide_aperture` already failed at
  HEAD before this batch and were left alone.

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
  seed stays unreachable. Details and the measured numbers are in README.md
  under "How a Level 2 round runs", and in the comments around
  `GenerationAttempts` in `Level 2 Configuration`.
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
  unchanged.** README.md's "How a Level 2 round runs" carries the rest,
  including the three independent timeouts that stop the cover ever trapping a
  player.

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
- Testing vs production values are documented in README.md; every one of them is
  currently at its production setting.

### Added 2026-09-16 (evening; record in `artifacts/wheel-shop-refresh-20260916/`)

- **Lucky Wheel is a full-screen takeover** (`Lucky Wheel Client`): while `LuckyWheelOpen` is
  true every OTHER ScreenGui in PlayerGui is disabled, kept disabled if it re-enables itself
  (NoiseReporter's StaminaGui does, on every layout pass) and restored on close/respawn. The disc
  is the texture `rbxassetid://86770264881525` with five EQUAL 72-degree fields, config order
  Token1 (12 o'clock), Token3, Potion1, Potion2, Shield1; the server weights are only the odds
  text. SPIN is the hub button; a tap while spinning skips.
- **Shop v4** (`LobbyShopDisplay`): eight 3.4-stud six-face hologram boxes at relative z
  -66 + 52/7·i along the right wall between the Level 2 and Level 4 gates (post edges rel z
  -69.45 / -10.55), centre x 30.2, y 7.0 (4.65 studs of headroom), invisible plates at x 27.78.
  The `ZyntraSupplyKiosk`, shopkeeper, access terminal, `ZyntraShopPrompt`, deck, sign, nameplates,
  projectors and the Daily Rewards plaque are GONE; the ZyntraStore terminal opens only from the
  left rail. The client keeps re-collecting boxes until it holds `ShopItemCount` of them (the model
  replicates before its children). Bob stands still under ReduceFlashing/ReduceCameraShake.
- **Friend Boost** (`ServerScriptService.FriendBoost`, `Friend Boost Client`): +10% completion
  tokens per verified Roblox friend (`IsFriendsWith`, pair cache, only definitive answers cached)
  who was a participant of the SAME round; `zyntraLevelCompleted:Fire(player, level, friendCount)`;
  ZyntraMonetization keeps the unpaid fraction as profile `FriendBoostTenths` (0..9). GameManager
  `WaitForChild`s the module: install it before pushing GameManager to a place that lacks it.
  Replicated Player attributes `FriendBoostFriends` / `FriendBoostPercent` drive the lobby chip.
- **Daily Rewards** page/client redesigned around Codex's four images (gift 117126194981100,
  token 93116899475472, potion 120211340805188, shield 126728249949579); milestones and claims
  unchanged. Studio's Device Simulator still reports a mouse and keyboard, so touch tiers only
  show there with `workspace:SetAttribute("ForceTouchUI", true)`.

### Added 2026-09-30 — Level 4 rebuilt in Blender

- **`Workspace."Level 4 Cinema Blender"` is the Level 4 preview now** (x=29000, same layout as the
  original +6000 X). `Level4V4PreviewAccess.MODEL_NAME` points at it; the old `"Level 4 Cinema Preview"`
  is kept untouched. Pipeline and model structure: `tools/level4_blender/README.md`; blend:
  `G:\Blender\Level4_Cinema\Level4_Cinema.blend`.
- Visual MeshParts never collide; `Collision` holds the original layout's collidable parts invisibly.
  Doors are their own Models, pushed open by `Doors.PushDoors` (street doors welded shut).
- Owner edits applied in `layout_edits.py`: flat walls above openings, Concessions opening 8 studs taller.
- Publishing from a session: Studio has no scriptable publish and synthetic clicks on File > Publish did
  nothing; Codex computer use (`codex exec --enable computer_use`) published it. The public asset
  `Updated` timestamp does not move on publish — trust Studio's "Published" toast.

### Added 2026-10-08 (late afternoon) - Local place backups removed (the Mac was out of disk)

- **Owner**: "I am getting storage problems on my computer. Please remove every local backup of any roblox game on
  my pc." The 228 GB disk had under 7 GB free. Removed, about 6.2 GB:
  - the untracked contents of every `artifacts/*/native-*` folder (4.1 GB: `*-AuthoritativeStudio.rbxl`,
    `all-service-children.rbxm`, `native-part-*.bin`, `scripts.json`, their chunk files). **Those folders now hold
    only the tracked records** (`source-manifest.json`, `backup-file-hashes.json`, `backup-metadata-summary.json`,
    receipts): the snapshots they describe are gone, so the one-off tools that read them
    (`tools/lobby_access_spawn_20261002/verify_backup.py`, `recovery/assemble_native_backup.py`, the
    `level3_finale_player_20261002` native checks) cannot run any more;
  - `.git/premerge-untracked-backup-20261002` (918 MB), after all 1589 of its files hashed to blobs git already has;
  - the 11 place files git tracked under `artifacts/` (55 MB; still in history, `git show d06cf72:<path>`);
  - `~/Projects/RobloxStudioBackups`, Studio's `AutoSaves` (seven recovery copies from September and 6 October),
    97 place files in Codex's project folders, three in Downloads.
- **Do not write whole-place snapshots to this Mac again.** Team Create keeps the place's version history, git
  keeps the scripts; a before/after `.rbxl` per change is what filled the disk (about 100 to 320 MB a time).
- **Removed a little later on the owner's word** ("Delete that"): the 23 `output/level5-*` entries in Codex's
  project folder (4.8 GB: the old suburbs Level 5's working copies, among them the clone `level5-audit/repository`
  and its two worktrees; every ref in it was on GitHub first). I had given the owner 5.5 GB for that row: the
  figure wrongly included `work/` (810 MB, Level 2 entity work and an sfx build from September), which is not
  Level 5 and was left.
- **Left for the owner to decide** (reported, not removed): Codex's old clones of this repo
  (`~/.codex/.chatgpt-projects/.../github`, 3.8 GB; three branches there, 7 commits and 0.9 MB, exist nowhere
  else), `work/`, Codex's own session logs (36 GB, 12 GB of them from this repo), the Roblox player's asset cache
  (`$TMPDIR/Roblox`, 1.6 GB), old asset sources in Downloads. The old repo copies in `~/Documents` are in iCloud
  only and take no space on the Mac.
- **27 tracked concept pictures left the working tree at 16:00:37-44 that day, and no session of mine did it** (my
  last command before was at 15:50, my next at 16:03; no Codex job logged it): 9 in
  `artifacts/level5-void-20261003/final`, 7 in its `concepts`, 5 in
  `artifacts/level6-playground-20261002/concepts/entity`, 6 in `assets/concepts/level3-sections-20260929`
  (44.6 MB). They show as ` D` in `git status` and are whole in git. Not restored and not committed: do not
  `git add -A` them away, and do not put them back, before the owner says which they meant.
- `mdfind` plus `find ~` for `.rbxl/.rbxlx/.rbxm/.rbxmx` is the whole search; `stat -f %b` (blocks) tells a file
  that is really on disk from one iCloud has evicted (`du` and `ls` sizes do not agree for those).

### Added 2026-10-08 (16:30) - Restarting servers, and how to know what is really published

- **Owner**: "How do we shut down the server and on again so we can push an update?" The page is Creator Hub >
  the experience > **Server management** (left menu, under Configure):
  `create.roblox.com/dashboard/creations/experiences/10559217407/server-management`. Tabs `Server Browser` and
  `Server Restart Status`; the button **Restart Servers** opens a dialog with "Restart only servers with outdated
  versions", "Delay server restart" and "Set custom payload". The owner ran one at 16:31 (Completed, 100%, within
  a minute). The three-dots menus on the experience's header and on its Creations tile do NOT hold it.
- **What is published is `isPublished` on the place's saved versions, not Studio's toast or log**:
  `GET https://develop.roblox.com/v1/assets/131311258779917/saved-versions?sortOrder=Desc&limit=25` through the
  dashboard tab (`dashboard.call`). Every Team Create save is a row; the newest row with `isPublished: true` is
  the live build. On 2026-10-08 Studio said "publish failed" at 15:16 ("server publish request timed out", as at
  03:47) and Roblox had published it all the same: v2838, saved 14:59, after the landscape lock and the
  supporter-board fix went in. I had told the owner those two were not live on the strength of the log alone.
- **Rows v2839 to v2841 (16:00, 16:09, 16:25) were saved while Studio on this Mac was closed**: somebody else was
  editing the place. They were not published when this was written.

<!-- End of preserved original sections. -->
