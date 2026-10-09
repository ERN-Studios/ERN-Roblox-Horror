# Level 2 Blender preview: where the dev-only button goes, how dev gating works, and how to swap the Level 2 builder

Paths below are relative to `G:\Roblox\MongoTV`. Everything was read from the working copy, which has uncommitted changes from other sessions. `studio-sync-manifest.json` lists every file cited here as `synced`. I did not touch Studio.

## 1. Recommendation

- **What to copy:** the Level 1 pair, `ServerScriptService/Level1BlenderPreviewAccess.Script.lua` and `StarterPlayer/StarterPlayerScripts/Level1BlenderPreviewButton.LocalScript.lua`. It is the only pattern that launches a real GameManager round. It doesn't depend on QueueBridge, and non-developers never get a prompt instance at all.
- **Where:** `Workspace.LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level2`. This is the lobby players actually spawn in. Optionally also `Workspace.ServerLobby.LevelQueueRooms.Level2QueueRoom`, which is the fallback lobby. The Level 1 script hooks both lobbies the same way.
- **Builder swap point:** one line, `Level 2 Round Adapter.ModuleScript.lua:370` (`local manifest = WorldBuilder.Build(layout, generation)`). Branch it on a workspace flag that only the dev launch sets, the same way `Level1BlenderPreviewActive` drives `MazeGenerator.Script.lua:466-468`.

## 2. Old lobby vs `LobbyReimaginedPreview`: which one players see

| | Old `ServerLobby` | `LobbyReimaginedPreview` ("R4") |
|---|---|---|
| Built by | `TunnelLobbyBuilder.Build(LOBBY_CENTER)` (`GameManager:593`, `TunnelLobbyBuilder:2694-3037`) | `LobbyReimaginedPreview/Builder.Build()`, called from `GameManager.buildLobby` (`GameManager:615`) |
| Centre | `(0,30,-760)` (`GameManager:114`) | `(220,30,-760)`, asserted at `GameManager:620` and stored as attribute `PreviewCenter` (`Builder:45`) |
| Built on reserved round servers? | Yes (`GameManager:593`) | No (`GameManager:594` returns first) |
| Queue stations | `LaunchZone1..16`, levels 1–4; Level 2 is `LaunchZone5..8` (`TunnelLobbyBuilder:2249`, `2935-2946`) | `R3QueueId` 101–124, `100+(level-1)*4+displayIndex`; Level 2 is 105–108 (`Builder:159`, `QueueBridge:4`) |

**Players see R4.** After R4 builds, `buildLobby` moves the canonical `ServerLobby.LobbySpawn` onto R4's floor:
- New CFrame looks from `(220,30.4,-860)` toward the centre (`GameManager:621,635`).
- It sets `LobbySpawnFloorModelName="LobbyReimaginedPreview"`, `LobbySpawnRevision=4` and `workspace.LobbySpawnMigrationReady=true` (`636-638`).
- If anything fails, the spawn reverts to the old tunnel and `LobbySpawnMigrationError` is set (`640-645`).

The old `ServerLobby` keeps existing in Workspace, and its 16 stations keep running (`GameManager:3979-3981`). Nothing in source hides it. RoundUI's R4 bounds (`|X|≤100, |Z|≤144` from `PreviewCenter`) say "the original lobby is outside these bounds even at its nearest bay" (`RoundUI.LocalScript:358-362`).

**R4 readiness attributes:**
- `LobbyReimaginedOwned=true`, `Ready` (false while building, true just before parenting to Workspace), `IsolatedDesignPreview=true`, `RealLevelLaunches=true` (`Builder:41-42`, `182-183`).
- `R3QueueRevision=3` (`Builder:43`) is the queue-protocol version. `QueueBridge.IsLobby` and the Level 1 access script require exactly 3 (`QueueBridge:6-10`, `Level1BlenderPreviewAccess:36`).
- `LobbyVisualRevision=4` (`Builder:44`) is the visual revision. `DevBayAccessGuard:15`, `R4DevGateController:44`, `LobbyPolishBays:97` and `RoundUI:353` require it.

**Bootstrap no longer builds anything** (working-copy diff vs HEAD). It only polls for up to 60 s and writes `PreviewReady`, `BuildStatus` and `PreviewError` on itself (`Bootstrap.Script:1-38`). `Builder.allowed()` (`Builder:10-12`) is now dead code: everyone gets R4, not just developers.

**Geometry comes from data, not source.** R4 is built from a compressed manifest in `ServerStorage.LobbyReimaginedBlenderSource20261001R4`, baked each server into `LobbyReimaginedBlenderKit20261001R4` (`RuntimeBake:8-9`, `38-53`, `101-209`). Exact bay coordinates are not in the repo.

## 3. The Level 2 room in each lobby

### R4: `LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level2` (primary target)

- **Bay model:** created at `Builder:120-124`, with attributes `CircularBayDiameter` and `BayCenter` (= centre + manifest `floorPosition`).
- **`ChamberFloor`:** this is the manifest collider `"Bay Floor"`, renamed and reparented to the nearest bay (`Builder:125-138`). It is invisible, anchored and colliding (`part()`, `Builder:13-17`). Visuals are the separate Blender meshes in `BlenderVisuals`.
- **Stations:** Models `"Level2 Queue 01".."04"` with `HologramBase` and `QueueActive`. Detectors are `QueueZone1..4`: 14.82² parts parented directly to the bay, with `R3QueueId` 105–108, `LevelNumber=2`, `QueueRadius=7.41` and an ObjectValue `QueueRenderOwner` (`Builder:140-162`). They are public queues (`previewOnly = level > 3`, `QueueBridge:45`).
- **Theme:** ribbon "POOLROOMS" and instruction "STEP ON A PAD · CHOOSE 1–6 PLAYERS" (`LobbyPolishBays:8`, `122`).
- **Furniture** (bay-local coordinates, +Z = entrance): VinylBench at (−21,.8,0) and (21,.8,0); WireTrolley at (−14,.8,−20.5) (`LobbyPolishBays:20-22`). The bay frame is built at `112-113`.
- **Bay position:** the Level 1 bay floor was measured at about `(157,30.4,-840)` (`docs/level1-facelift-20261002-preview-plan.md:37`), which mirrors the old layout. That makes the Level 2 bay about **(283, ~30.4, −840)**, east of the centre and entered from −X. **This is inferred**: the manifest lives only in ServerStorage.
- **No server dev guard here.** `DevBayAccessGuard` protects only `{5,6}` (`DevBayAccessGuard:9`), and `R4DevGateController` shutters only 5 and 6 (`R4DevGateController:20,251,291-292`). Ordinary players can walk into the Level 2 bay.

### Old lobby: `ServerLobby.LevelQueueRooms.Level2QueueRoom`

- `addRoom` places it with `side=+1`, `z=-80` (`TunnelLobbyBuilder:2937,2945`). Room centre is `(63,30,-840)`, radius 28, height 22.4 (`2114-2118`).
- `ChamberFloor` is a cylinder at `(63,29.58,-840)`, size `(1.4,59,59)` (`2121-2130`).
- Room attributes: `CircularBayDiameter=56` (`2179`), `LevelNumber=2`, `LevelEnabled=true` (`2284-2285`).
- Pads `LaunchZone5..8` sit at x = 54/72, z = −853.2/−826.8 (offsets `2242-2247`, zone `1174-1189`).
- **The rear of the room is occupied** by the Level 2 decor (`styleLevelTwoBay`, `1528-1668`):
  - basin at outward 19.2 (`1588`);
  - **solid** tiled column 3.6×9.2×3.6 at outward 20.5 (`1619-1622`);
  - solid ladder at outward 14.75 (`1636-1646`);
  - solid lounger at (outward 19, z +9) (`1649-1655`).
- Doorway is `LevelDoorways.Level2DoorPost`/`Level2Information`; no sealed door, because the room is active (`2289-2396`).

### Host placement

Level 1 uses `floor.Position + Vector3.new(-20, 4.42, 0)` (`Level1BlenderPreviewAccess:52`). That −X offset only means "rear wall" for west-side bays. For the east-side Level 2 bay it points at the doorway.

- **R4 bay:** use `floor.Position + outward*20 + (0,4.42,0)`, with `outward = sign(floor.Position.X - PreviewCenter.X)` on X. That is bay-local rear-centre, which is clear of Level 2 furniture. Levels 3 and 4 use the same rear-centre spot for their furniture (`LobbyPolishBays:25,28`).
- **Old room:** a straight mirror, `(83,34,-840)`, lands inside the solid tiled column. Use `floor.Position + (20, 4.42, -8)` = `(83,34,-848)` instead. It is ≥8 studs from the column, basin and ladder, and 12.2 from pad 6.

## 4. How `DevAccess` decides who is a developer

`ReplicatedStorage/DevAccess.ModuleScript.lua` has three checks, all by UserId:

| Function | Who passes | Lines |
|---|---|---|
| `IsAllowed` | 40920547 (mikkelczar), 9488575949 (LaverSneglen) | `5-8`, `13-21` |
| `IsLevel6PreviewAllowed` | `IsAllowed`, plus 11374988579 (ZenMeister02) | `24-30` |
| `IsLevel3TimelineOwner` | 9488575949 only | `32-40` |

There is no Studio bypass. Studio multi-client test players have negative UserIds and fail every check (`GameManager:1437-1439`).

Other dev-only gates in the project:

| Gate | Server or client | Check | Location |
|---|---|---|---|
| `DevControl` remote: fastQueue, pauseEntity, immunePush, noclip, playerEsp, freeRespawn, level2PumpPair, level3PreBlackout | Server | `IsAllowed` plus 12/s rate limit; level3PreBlackout uses `IsLevel3TimelineOwner` | `GameManager:173-191`, `273-338` |
| `DevTuning` remote | Server | `IsAllowed` | `GameManager:350-368` |
| Dev cheat UI | Client | Exits early if not `IsAllowed` | `DevCheats.LocalScript:22-23`, `MasterTuningClient:18-23` |
| Level 4 round | Server | Whole party must pass `IsAllowed` while `LEVEL4_PUBLIC=false`; ceiling `Routing.DevMaxLevel=4` | `GameManager:148-171`, `Round Completion Routing:47-50` |
| R4 bays 5/6 entry and preview queues | Server | `IsLevel6PreviewAllowed`; preview queues also need `bridge.AllowsPreview` | `GameManager:1250-1257` |
| `DevBayAccessGuard` | Server | Heartbeat every 0.2 s ejects non-allowed players from bays 5/6; counts `DevBayDeniedEntryCount` | `DevBayAccessGuard:79-108` |
| `R4DevGateController` | Client, cosmetic | Local shutters and hidden labels/prompts for bays 5/6 | `R4DevGateController:248-314` |
| `Level4PreviewPrompt` | Client, cosmetic | Disables named Level 4/5/6 preview prompts for non-devs; fails closed | `Level4PreviewPrompt:6-25` |
| Level 4/5 preview boundary | Server | 0.5 s sweep teleports non-devs out of model bbox + (8,20,8) | `Level4V4PreviewAccess:258-285`, `Level5PreviewAccess:250-277` |
| Free respawn | Server | `IsAllowed` | `GameManager:2804,2822` |
| Level 2 dev pump | Server | `IsAllowed` | `Level 2 Objective Controller:244-252`, `970-972` |
| Reserved-server arrival | Server | `Level1BlenderPreview` packet honoured only if level 1, the kit is ready, and every participant passes `IsAllowed` | `GameManager:3939-3955` |

## 5. The four preview-access scripts compared

| | **Level1BlenderPreviewAccess** + Button | **Level4V4PreviewAccess** | **Level5PreviewAccess** | **Level6PreviewAccess** |
|---|---|---|---|---|
| Destination | **Real GameManager round** via `ServerStorage.Level1BlenderPreviewLaunch` (BindableFunction, `GameManager:3359-3365`). Studio runs it locally; published servers teleport to a reserved server with `packet.Level1BlenderPreview=true` (`3314-3358`) | Teleport into static `Workspace."Level 4 Cinema Blender"` (`:7`), landing at `Level4V4Exit` | Teleport into static `"Level 5 Quiet Suburbs"` / `Level5Exit` (`:7-8`) | Functional runtime outside GameManager: `"Level 6 Preview Runtime".EnsureWorld/Join/Leave` (`:6`, `178`, `190`, `217`) |
| Entry point | Invisible server Part `Level1BlenderPreviewEntry` (1×1×1, T=1, no collide/touch/query, attribute `Level1BlenderPreviewHost`) in both Level 1 rooms (`:40-72`); the prompt is created **only on dev clients** (`Button:6-8`, `26-34`) | Server prompt on old `LevelDoorways.Level4SealedDoor`, plus R4 queue cohorts via `QueueBridge.RegisterPreviewLauncher(4)` (`:183-226`) | Same, with `Level5SealedDoor` and launcher 5 | Same, with `Level6SealedDoor` and launcher 6 |
| Auth | `IsAllowed`, not `InRound`/`Level6InRound`/`ReservedRoundServer`, exact host/room/floor, living unanchored unseated avatar, ≤12 studs, 2 s cooldown (`:74-113`); GameManager rechecks (`3304-3313`) | `IsAllowed`; refuses while `Level4RoundActive` (`:68-71`) | `IsLevel6PreviewAllowed` (`:66`) | `IsLevel6PreviewAllowed` plus a nonce/ack stream handshake on `Level6PreviewTransport` (`:87-103`) |
| Return | Round end → `returnGroupToLobby` | `RETURN TO LOBBY` prompt → `LobbySpawn` | Same | Return-anchor attachment (`:124-166`) |
| Party | Solo (`participants={player}`, `GameManager:3318`) | Solo by door, 1–6 via queue | Same | Same |
| Size | 133 + 70 lines | 301 | 293 | 306 |

- **`Level4PreviewAccess` (legacy) is disabled** in Studio (`"enabled": false`, `artifacts/level1-readability-20261002/progression-inventory-before.json:1606`). It reuses the same prompt name on the same door.
- **R4 door prompts for levels 4–6 are gone.** The working-copy Builder removed the `R3DeveloperPreviewEntry` markers that HEAD had (git diff on `Builder.ModuleScript.lua`). `GetPreviewEntries` now returns nothing, so in R4 those previews are reachable only through the dev queue pads.
- **QueueBridge only accepts levels 4–6** (`IsPreviewEntry`, `QueueBridge:57-62`; `EXPECTED_CONTROLLERS`, `77-79`). Using it for Level 2 would mean editing it and converting the public 105–108 pads. Avoid that.

**Copy the Level 1 pair.** It is the cleanest pattern, launches a real round, and keeps the non-dev client free of any prompt. The adaptation:

- New names:
  - `Level2BlenderPreviewEntry` / `Level2BlenderPreviewHost`
  - Remote `Level2BlenderPreviewRequest`
  - Bindable `ServerStorage.Level2BlenderPreviewLaunch`
  - Prompt `Level2DeveloperPreviewPrompt`
- Room checks: `Level2QueueRoom` with `LevelNumber==2`, and `QueueBay_Level2` with the same R4 checks as `Level1BlenderPreviewAccess:24-38`.
- Use the outward-signed host offset from §3.
- Update the `observe` name list at `:126-129`.

## 6. How GameManager picks the Level 2 generator, and the swap

**The production chain:**
1. `LEVEL_GENERATORS = {[2]="Level2Generator",[3]="Level3Generator",[4]="Level4RoundGenerator"}` (`GameManager:139-143`).
2. `ensureWorld` runs `require(script.Parent:WaitForChild(generatorName)).Build()` (`1631-1641`), then waits for workspace `Elevator`, `MazeStart` and `ElevatorSpawn` (`1660-1667`).
3. `Level2Generator` is a 14-line wrapper that forwards to `"Level 2 Round Adapter"` `Build`/`Cleanup` (`Level2Generator.ModuleScript:1-14`).
4. `Adapter.Build` (`Round Adapter:314-461`):
   - `Cleanup()`
   - `Master.ApplyInto(Configuration,"L2")`
   - seed (pinned only when `Level2Seed ≥ 1`)
   - `LayoutGenerator.Generate` (`356`)
   - **`WorldBuilder.Build(layout, generation)` (`370`)**
   - readback `Level2_WorldDescendants` in `ReplicatedStorage."Level 2 State"` (`374-375`), which is useful for counting instances in the Blender world
   - moves **all** players to `manifest.Arrival.ElevatorSpawn`, then parks `ServerLobby` (`382-403`)
   - starts `ObjectiveController`, `PoolFoamController` (failure throws when enabled), and `PoolSlideController` (`410-445`; `Pool Slide Configuration.Enabled=true`)
5. Cleanup runs `cleanupActiveWorld` → `LEVEL_GENERATORS[activeLevel].Cleanup()` (`GameManager:1735-1753`). `sanitizePersistedLevelState` does the same for a saved stale world (`653-689`).

**Swap without touching production rounds** (mirroring Level 1). Production behaviour is unchanged while the flag is false:

1. **Adapter:** at `Round Adapter:370`:
   `local builder = workspace:GetAttribute("Level2BlenderPreviewActive") == true and require(script.Parent:WaitForChild("Level 2 Blender World Builder")) or WorldBuilder`
   Precedent for workspace-attribute switches in this code: `Level2ArchMeshRibs` (`World Builder:1628-1633`).
2. **Do not swap `LEVEL_GENERATORS[2]`.** Cleanup and sanitize use the same table, so a per-round swap can be cleaned up by the wrong module.
3. **GameManager:**
   - Generalise `launchBlenderPreview` / `canLaunchBlenderPreview` (`3296-3358`) to take a level. Use a Level 2 ready-check on its own kit; `blenderPreviewReady` is Level 1-only (`3297-3303`).
   - Set and clear `Level2BlenderPreviewActive` around `prepareGroupLoading(attempt,{player},2,false)`, as Level 1 does at `3321`/`3339`.
   - **Add the flag to both progression guards**: `2449` (no Continue to Level 3) and `3086` (no `zyntraLevelCompleted` / records / `FirstClearLevel2` badge). Without this, a preview win continues into Level 3 and awards progress.
   - Add a `packet.Level2BlenderPreview` arm next to `3939-3955` with `selectedLevel == 2`.
   - Clear the flag in `cleanupActiveWorld`. Only the Level 1 cleanup clears its flag today (`1683`).
4. **What the Blender builder must return** (`World Builder:6334-6355`):
   - `World`, which **must keep the name `"Level 2 Generated World"`**. Cleanup and sanitize look it up by name (`Round Adapter:272-276`, `GameManager:657`), as do eight client scripts and RoundUI (Pool Foam Client `:364`, Sound Controller `:326`, Slide Controller `:571`, Level2AlertClient `:420`, RoundUI `:379,425`, …).
   - `Layout`; `Pumps`; `PressureDoors`; `Drains`; `Corridors`.
   - `Exit{Trigger, SafeSpawn, BoreRadius, Backstop, PathPoints, TransitionLength, TransitionEnd, Recycle, FlumeBoundsSize/Center}`, used by the Objective controller.
   - `Arrival` from `makeCompatibilityArrival`: Workspace `Elevator` with `DoorL`/`DoorR`, plus `MazeStart`, `ElevatorSpawn` and `EntityStart`, all with `Level2_CompatibilityMarker` (`5824-5886`).
   - `EntityDen`; `EntityNodes` (containing `"Level 2 Pool Foam Spawn n"` with `Level2_PoolFoamSpawn`); `Navigation`; `WaterRegions`, `PreviousWaterAppearance`, `TerrainCenter`, `TerrainSize`; optionally `BuoyantProps`.
   - Pumps, pressure doors, the exit flume and the arrival are built by **local** functions inside the 6,400-line World Builder (`makePumpStation`, `makeCorridor`, `makeExitFlume`, `makeCompatibilityArrival`). The Blender builder has to either export and reuse those or reimplement them.

## 7. Things to know before building it

- **Published preview rounds run in a reserved server**, where `LobbyReimaginedPreview` is never built. The lobby access script has to live in the public lobby, exactly like Level 1 (`Level1BlenderPreviewAccess:15`).
- **A Studio Level 2 round parks `ServerLobby`**, including `LobbySpawn`, in ServerStorage (`Round Adapter:61-68`). It also teleports every connected player to the arrival platform (`387-402`). "Back to lobby" during such a round answers `leavefailed` (`GameManager:2908-2913`).
- **Prompt exclusivity:** ProximityPrompt's default OnePerButton exclusivity applies. Neither Level 2 room has another E-prompt today.
- **Concurrent sessions:** `GameManager.Script.lua` and the `LobbyReimaginedPreview/*` files have uncommitted edits from other sessions. Per `artifacts/level1-quality-20261002/coordination.md`, the Level 4 session currently holds Studio. Every one of these edits needs that coordination first.
- **The 52k figure is unverified:** the brief's "52,000 objects" isn't in source; the World Builder comment says about 71,000 instances (`World Builder:6311`). Measure with `Level2_WorldDescendants` instead of trusting either number.