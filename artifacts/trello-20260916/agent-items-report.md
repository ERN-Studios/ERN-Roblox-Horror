# A-ITEMS report — Route Markers and the Speed Potion (#85 / #88)

Baseline `aa40f70`. Nothing committed, nothing pushed, Studio never touched.

## Files touched (exact paths)

| Path | State |
|---|---|
| `ServerScriptService/RouteMarkerService.Script.lua` | NEW mirror file (Script), 300 lines |
| `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua` | edited, +29 lines in four places |
| `tools/tests/test_route_markers.py` | NEW, 189 checks |
| `tools/tests/test_speed_potion.py` | NEW, 498 checks |

Nothing else was written. ZyntraMonetization / ZyntraConfig (A-SERVER), ProtectionHUD /
UIDevice (A-HUD) and the three Codex-owned Level 3 files were read only.

## Verified offline, and how

`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`.

- `luau-compile.exe --binary` passes on both `.lua` files.
- `python tools/tests/test_route_markers.py` → **189 checks**. The WHOLE Script runs under
  a fake DataModel (instances with real parent/child and Destroy semantics, attributes with
  change signals, a scripted downward raycast, `ServerStorage.ZyntraInventory` with a call
  log, the RemoteEvent with capturable `FireClient`, a controllable `os.clock` and
  `GetServerTimeNow`). Vector3/CFrame are real maths; Color3 is a value with no arithmetic,
  as in the engine. It covers: all 13 refusal cases (each also asserting that nothing was
  placed and the durable spend was never reached), the rate limit at 0 s / 1.49 s / 1.51 s,
  `Consume` false → no marker and no attribute change, a missing and an erroring inventory,
  the full happy path (position, floor snap, yaw, three parts, flags, accent colour, chevron
  direction, name tag, raycast params and exclusions), the floor fallback, a vertical look
  vector, the fourth placement retiring the oldest while still spending, `MaxActive` read
  from `ZyntraConfig` (3 / 2 / missing / module absent), two players not sharing a cooldown,
  death and leaving KEEPING the markers, round end destroying all and zeroing every count, a
  destroyed folder being rebuilt, six unknown messages ignored silently, and a forged
  CFrame/Vector3/Instance in arguments 2–4 having no effect on where the marker lands.
- `python tools/tests/test_speed_potion.py` → **498 checks**. The real speed constants, the
  real stamina block, real `movementAvailable`, real `applySpeed`/`speedBoost` and the real
  in-round edge line are lifted out by string marker and run over an 11×14 matrix (walk,
  sprint, exhausted, drained, crouch, lobby, lobby sprint, and the three movement locks ×
  no boost / active / expiring this frame / expired / zero / NaN / string / missing
  multiplier / 9 / "x" / NaN / 0.2 / 1.5 / 1.51). Each cell asserts WalkSpeed, the
  `Level2_DesiredWalkSpeed` restore target and that stamina did not move. Plus both edges
  (start via attribute change, end via the clock passing, each applied exactly once), the
  locked-body cases, the lobby refusing a stale boost, and the four hostile-speed thresholds.
- Regression: `test_controller_input.py` 120, `test_spectator_vitals.py` 14,
  `test_spectate_parity.py` 18 — identical before and after the NoiseReporter edit. The
  marker strings that test extracts (`local function applySpeed()`,
  `local function refreshCrouch()`, `local function sprintRequested()`,
  `RunService.Heartbeat:Connect(function(dt)`, `\tif not inRound() then`) are intact. One
  trap found the hard way: a comment containing the text `local function applySpeed()`
  breaks that extractor, because it matches the FIRST occurrence. The comment was reworded.
- Whole offline suite run. Still failing, all pre-existing and none of them mine:
  `test_level3_run_in_exit`, `test_level3_hidden_chase`, `test_level3_slide_aperture`
  (listed as failing at HEAD in CLAUDE.md), `test_pool_slide_navigation` (its "pre-fix
  navigator" fixture no longer reproduces), `test_daily_rewards_page` (A-REWARDS-UI, in
  flight). `test_full_sync_contract` fails on unlisted new scripts and on three files other
  agents are mid-edit — mine is one of the unlisted ones; see below.

## NOT verified — needs Studio

- **The script does not exist in Studio.** New scripts cannot be pushed by the sync tools;
  the lead must create `ServerScriptService.RouteMarkerService` in Studio via
  `execute_luau` + `UpdateSourceAsync` and then add the manifest item with
  `tools/studio_source_contract.py`. Until then `test_full_sync_contract` reports it as
  unlisted (together with A-NOTES' and A-REWARDS-UI's new files).
- Everything visual: whether the chevron reads as a direction at eye height, whether the
  neon is bright enough on Level 1's yellow carpet and Level 2's water, whether the 60-stud
  BillboardGui cut-off is the right distance, and whether 2.5 studs ahead of the placer ever
  puts a marker inside a wall (the floor probe snaps Y, it does not test lateral clearance).
- Replication: that the marker appears for teammates promptly, and that `RouteMarkersActive`
  reaches ProtectionHUD.
- The real `ZyntraInventory` round trip, its yield duration, and the behaviour when a
  DataStore write is slow (the geometry is captured before the yield, so a slow write can
  only delay the marker, not move it — but the delay itself is unmeasured).
- Touch/PC input: A-HUD owns the X key and the `RouteMarkerPlace` slot; I verified only that
  `ProtectionHUD` fires `markerRemote:FireServer("place")`, which matches this server.
- The Speed Potion boost under real replication: how many frames pass between the server
  writing the attributes and the client's `applySpeed`, and whether Roblox's own character
  controller does anything unexpected at 17.6 / 28.6.

## Death / leave semantics as implemented

- **Markers outlive their placer.** Death does not remove them and neither does leaving.
  The arrow is information the rest of the team is still walking on; deleting it would
  punish the party for the death that made the route worth marking. A dead player cannot
  place a new one (`NoCharacter`).
- **Only the round removes them.** `workspace.RoundActive` going false destroys every marker
  and zeroes every `RouteMarkersActive`. There is no per-marker expiry and no cleanup on
  level change other than that attribute, which GameManager always flips.
- **A leaver keeps nothing to restore.** Their tracking entry and cooldown are dropped on
  `PlayerRemoving`; the models stay. Consequence, accepted and documented: a player who
  leaves and rejoins mid-round starts at 0 active, so up to six of their arrows can stand at
  once. Each was still paid for out of the durable inventory, so it is litter, not an
  exploit. Rebuilding the count from the folder's `Owner` attributes on rejoin is the fix if
  it ever matters.
- **The pack is spent before the cap is applied.** A fourth placement consumes a marker and
  retires the oldest rather than refusing, so a player walking a long corridor keeps a
  moving trail. There is therefore no "limit" refusal at all.
- **Paid means placed.** Geometry is read from the HumanoidRootPart BEFORE `Consume` yields,
  so a player who dies during the durable write still gets the marker they paid for, at the
  spot they asked from. A refused or erroring `Consume` places nothing.

## Two contract mismatches for the lead

1. **Refusal vocabulary.** My brief fixed the set to
   `NotInRound | NoCharacter | Hiding | RateLimited | NoMarkers | Unavailable`, and that is
   what the server sends. `ProtectionHUD.LocalScript.lua:238` guessed a different set
   (`empty`, `limit`, `cooldown`, `blocked`). Its fallback is graceful — an unknown reason is
   uppercased and truncated — so nothing breaks, but players would read "NOMARKERS" instead
   of "NO MARKERS LEFT". A-HUD owns that file; the proposed diff is:
   ```lua
   local REFUSALS = {
    NoMarkers = "NO MARKERS LEFT",
    RateLimited = "TOO SOON",
    Hiding = "NOT NOW",
    NotInRound = "NOT NOW",
    NoCharacter = "NOT NOW",
    Unavailable = "STORE OFFLINE",
   }
   ```
   `limit` can be deleted: the cap never refuses (see above).
2. **`Hiding` covers three locks.** `Level3_Hiding`, `Level2_ForcedSliding` and
   `Level2_RagdollServerActive` all answer `Hiding`, because the reason set has six entries
   and all three mean the same thing to a player: the body is not yours to aim right now.
   If A-HUD wants separate captions, the server needs a seventh reason.

## Balance analysis — numbers out of the code

Player, from `NoiseReporter`: walk 16, sprint 26, crouch 8. Boost ×1.10 for 6 s, once per
round: **17.6 / 28.6 / 8.8**. A boosted sprint gains `(28.6 − 26) × 6 = 15.6 studs` over its
own unboosted self; a boosted walk gains 9.6.

| Level | Hostile | Speed | Boosted sprint 28.6 outruns it? | Over 6 s |
|---|---|---|---|---|
| 1 | EntityAI `SPEED_CHASE` × `EntitySpeedMul` | 27.2 × 1.0 | **yes**, by 1.4 studs/s | +8.4 studs |
| 1 | same, after one fuse (`L1_SpeedPerFuse` 0.06, cap 1.1) | 28.83 … 29.92 | no | −1.4 to −7.9 |
| 1 | same, exit open (`END_SPEED_MUL` 1.3) | 35.36 | no | −40.6 |
| 2 | Pool Foam `MaximumSpeed` / `ChaseMinimumSpeed` | 22 / 13 | yes — already did at 26 | +39.6 (was +24) |
| 2 | Pool Slide `NormalRunSpeed` | 20 | yes — already did at 26 | +51.6 (was +36) |
| 2 | Pool Slide `EnragedSpeed` | 32 | no | −20.4 (was −36) |
| 3 | Mall Manager `Normal.ChaseSpeed` | 22 | yes — already did at 26 | +39.6 (was +24) |
| 3 | Mall Manager `Blackout.ChaseSpeed` | 31.2 | **no** | −15.6 (was −31.2) |

`Level 3 Configuration` states its intent in a comment: `PlayerRunSpeedReference = 26`,
`ChaseSpeedMultiplier = 1.20`, "the blackout Manager must win a straight chase by exactly
twenty percent". The potion does not break that invariant, but for six seconds it softens it
to 9.1 % (31.2 / 28.6) — the Manager's closing rate halves, from 5.2 to 2.6 studs/s. That is
the single most consequential number in this batch and the one to watch.

Level 1 is the only place the potion flips an outcome, and only before the first fuse: the
entity is 27.2 at `EntitySpeedMul = 1`, and one fuse (×1.06 → 28.83) puts it back in front.
The Level 1 finale, which is the level's actual foot race, runs at 35.36 and is untouched.

**Detection thresholds — all still clear:**
- `SoundController` `RUN_WALKSPEED = 22` and `EntityShakeController` `BOB_RUN_WS = 22`:
  boosted walk 17.6 and boosted crouch 8.8 stay under, so no false running audio or camera bob.
- `Level 3 Mall Manager AI Controller:1761` `velocity >= 20 or humanoid.WalkSpeed >= 24`:
  boosted walk is 17.6 on both counts, boosted crouch 8.8. A boosted sprint is already in
  sprint hearing range unboosted (26 ≥ 24), so nothing changes there either.
- The noise the player reports is keyed off `state`, not WalkSpeed, and `state` is chosen
  before the multiply. A boosted walk is exactly as loud as a walk. Pool Foam's hearing,
  `NoiseRegistry` and `LOUDNESS` are untouched.
- `Level 2 Slide Controller` resumes from `Level2_DesiredWalkSpeed`, which carries the
  boosted number while boosted and self-corrects on the expiry edge. Its own validation
  (number, not NaN, not infinite) accepts 17.6.

**Could any exit or finale be trivialised?** No, with one thing to watch:
- Level 2's exit is gated on pumps and door power (`Level2FoamLethal`, `Level2_ExitPosition`
  once the doors are live), not on foot speed; the potion only shortens traversal.
- Level 1's relays, boxes and levers are revalidated server-side by `canUsePrompt` and are
  puzzle-gated; the player has to stand at a prompt either way.
- Level 3's finale spawns the Manager at the level entry (`MazeStart` + 8/12/16/20 studs)
  once the first survivor is 4 studs into the open exit hall — a fixed-length straight race
  against 31.2. Six seconds of 28.6 buys 15.6 studs of that race and no more, and one potion
  per round means spending it earlier means not having it there. That trade is the design,
  not a bug, but it is the run to measure.
- No invulnerability, no teleport: neither feature ever writes Health or a CFrame on a
  player, and all three movement locks still return before any WalkSpeed write.

**Stale-state robustness.** `speedBoost()` returns 1 whenever `inRound()` is false, so a
boost attribute the server forgets to clear cannot leak into the lobby, into a respawn, or
across a level change — the lobby branch of `applySpeed` never multiplies at all. Proven in
`test_speed_potion.py` ("a stale boost cannot speed up the lobby").

**What the lead should watch in the native playtest**, in priority order:
1. A Level 3 blackout chase with the potion drunk mid-chase. Does 2.6 studs/s of closing
   rate still feel like being hunted, or does it read as an escape? This is the number to
   change if it feels wrong, and it is one constant (`SpeedMultiplier` in `ZyntraConfig`).
2. The Level 3 finale run with and without the potion, timed.
3. A Level 1 pre-fuse chase: the boost genuinely outruns the entity there. Is 6 s of it
   too strong that early, given the entity re-acquires immediately after?
4. Whether 17.6 walking reads as "faster" at all, or whether players only ever notice the
   sprint. If nobody notices the walk, the 6 s window is effectively a sprint-only item.
5. Route markers in a real maze: do three arrows plus a 60-stud name tag actually help a
   party, or become visual noise in Level 3's mall?

## Open questions

- Should the 4th marker retire the oldest (what I built, per brief) or refuse? Retiring
  spends a marker the player may not have meant to spend. A HUD that shows `placed/3` and
  `stored` — which ProtectionHUD already does — makes it readable either way.
- No cleanup runs on a level change WITHIN a campaign other than `RoundActive` going false.
  I believe GameManager always flips it between levels; worth one Studio confirmation.
- A rejoining player can exceed three active markers (see above). Leave it, or rebuild the
  count from `Owner` attributes on `PlayerAdded`?
- `Unavailable` is currently indistinguishable to the player from a real outage and a
  5-second `WaitForChild` timeout. If A-SERVER's bindable is created late at boot, the first
  placement of a server could see it; the timeout was chosen to cover that.

## Artwork needed from Codex

**None.** The marker is three anchored Parts (Neon + SmoothPlastic) and a Code-font
BillboardGui — no textures, no decals, no invented asset IDs. If the owner later wants a
textured arrow decal instead of the chevron, that would be a 512×512 transparent PNG used as
a `Decal` on the top face of the base plate, but nothing depends on it today.

## Trello draft — card #85 "Explore more token-purchasable items, including a Speed Boost Potion"

> **Speed Potion and Route Marker Pack — implemented, pending Studio verification**
>
> Two token items, both stored consumables, both using the existing durable profile
> transaction. No new Robux products and no price changes.
>
> **Speed Potion — 3 tokens.** +10 % movement speed for 6 seconds, one use per round, no
> stacking and no stamina change. It scales the single existing speed writer in
> NoiseReporter rather than adding a competing WalkSpeed loop, so crouch/walk/sprint all
> scale together (8 → 8.8, 16 → 17.6, 26 → 28.6) and hiding, the Level 2 slide and the
> ragdoll lock still own the body completely. The boost ends on a server clock, so the
> client restores the normal speed on the first frame after it expires; a stale attribute
> can never follow a player into the lobby.
>
> **Route Marker Pack — 2 tokens for 3 markers.** Press X (or the new touch slot) to drop a
> neon arrow pointing wherever you are facing. Up to 3 of yours stand at once — a fourth
> retires your oldest — and your whole team sees them, with your name above each one. The
> direction is entirely the player's choice; nothing computes the route. Markers survive
> your death and your leaving, because the team is still walking on that information, and
> they are cleared when the round ends. The server reads the position from its own copy of
> your character: the remote carries the word "place" and nothing else, so there is no CFrame
> or parent to forge, and the markers have no collision and no effect on any hazard.
>
> **Balance:** a boosted sprint (28.6) still loses to the Level 3 blackout Manager (31.2) and
> to an enraged Pool Slide (32), and to the Level 1 entity from the first fuse onwards
> (28.83+) including its finale (35.36). It out-paces the Level 1 entity only before the
> first fuse, by 1.4 studs/s. Boosted walking (17.6) stays under every "this player is
> running" threshold in the game, so the potion never makes you louder or more visible.
>
> Offline: 189 checks on the marker server and 498 on the speed path, running the real Lua.
> Still to do: create the Script in Studio, add its manifest item, and run a native playtest
> on all three levels.
