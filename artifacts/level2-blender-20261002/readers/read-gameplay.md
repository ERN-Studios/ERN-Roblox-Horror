# Level 2 gameplay contract with the generated world

Read from the working tree at HEAD `e8e4e7c`. GameManager and RoundUI have uncommitted edits, and those edited copies are what I read. Line references are `file:line`.

**File legend** (all under `G:\Roblox\MongoTV\`)
- GM = `ServerScriptService\GameManager.Script.lua`
- L2G = `ServerScriptService\Level2Generator.ModuleScript.lua`
- RLR = `ServerScriptService\Round Loading Runtime.ModuleScript.lua`
- RP = `ServerScriptService\ReentryPlacement.ModuleScript.lua`
- Under `ServerScriptService\Level 2 Systems\`:
  - OC = `Level 2 Objective Controller.ModuleScript.lua`
  - RA = `Level 2 Round Adapter.ModuleScript.lua`
  - TS = `Level 2 Exit Transition Test Suite.ModuleScript.lua`
  - WB = `Level 2 World Builder.ModuleScript.lua`
  - LG = `Level 2 Layout Generator.ModuleScript.lua`
  - CFG = `Level 2 Configuration.ModuleScript.lua`
  - PFC / PFN / PFO / PFCFG = `Level 2 Pool Foam Controller / Navigator / Observer / Configuration.ModuleScript.lua`
  - PSC / PSN / PSCFG = `Level 2 Pool Slide Controller / Navigator / Configuration.ModuleScript.lua`
  - SRS = `Level 2 Slide Ragdoll Service.Script.lua`
- Under `StarterPlayer\StarterPlayerScripts\`:
  - REC = `Round Entry Client.LocalScript.lua`
  - RUI = `RoundUI.LocalScript.lua`
  - L2SC = `Level 2 Sound Controller.LocalScript.lua`
  - L2OUI = `Level 2 Objective UI.LocalScript.lua`
  - L2AC = `Level2AlertClient.LocalScript.lua`
  - L2LC = `Level 2 Lighting Controller.LocalScript.lua`
  - L2SL = `Level 2 Slide Controller.LocalScript.lua`
  - L2PF = `Level 2 Pool Foam Client.LocalScript.lua`
  - L2EA = `Level 2 Entity Audio.LocalScript.lua`
  - ESP = `Level 2 Pool Slide Dev ESP.LocalScript.lua`
  - SPC = `SpectateController.LocalScript.lua`
  - NR = `NoiseReporter.LocalScript.lua`
  - DC = `DevCheats.LocalScript.lua`
  - SC = `SoundController.LocalScript.lua`
  - ZS = `ZyntraStore.LocalScript.lua`

---

## 0. Where the code disagrees with the docs, and other surprises

1. **Level 2 has two hostiles in code, not one.**
   - `PSCFG:4` has `Enabled = true`, and `RA:425-445` starts the Pool Slide on every build. Its failure is only a warning.
   - Pool Foam failing to start is fatal when its `Enabled` is true (`RA:413-420`). The whole build errors.
   - CLAUDE.md says Level 2 has exactly one hostile; that is out of date.
2. **The loading cover is no longer held by Level 2's own timeouts.**
   - All levels now use one shared token barrier: `entryprepare` → `entryready` → `entryreleased`, with a 60 s limit (`RLR:5`).
   - `poolaccess` now only shows the text "POOL ACCESS READY" (`RUI:4692-4695`). It does not lift the cover.
   - These are stale: README:345-362 (the 15 s / 35 s / 16 s caps) and the GM:556-561 comment about RoundUI's "35 s absolute cover lift".
3. **`SelectedLevel` reads 1 for the whole of generation.**
   - GM sets it to 2 (`GM:1629`).
   - The first thing `RA.Build` does is `Cleanup()` (`RA:315`), which resets 2 → 1 (`RA:292-294`).
   - It becomes 2 again only at `RA:447`.
4. **Every build clears a large block of terrain.**
   - `Build` calls `clearOwnedTerrain(nil)` (`RA:348`), which takes the fallback branch.
   - That clears 2100×200×2100 studs centred on (0,-16,240) and logs the "[Level 2] no recorded water regions" warning (`RA:205-214`).
5. **The Pool Slide reads a manifest field that doesn't exist.**
   - `PSC:191` reads `manifest.BuoyantProps`.
   - The builder's manifest has no such field (`WB:6334-6355`), so floating props are not excluded from the Pool Slide's spawn sight-line rays.
6. **The exit "safe spawn" recovery path looks unreachable in real rounds.**
   - It only runs when `Level2_ExitTransition` is cleared while the rider is still tracked (`OC:924-939`).
   - GM clears that attribute only in four places: `GM:1147` (player setup), `1760` (after cleanup), `2206` (next entry) and `2819` (re-entry, which refuses escaped players at `GM:2806`).
   - The safe spawn is still required by the manifest check (`OC:320-322`) and the test suite (`TS:361-383`).
7. **Two round attributes survive cleanup.**
   - `Level2FoamLethal` and `Level2_ExitPosition` are reset only by `OC.Start` (`OC:523-524`). `RA.Cleanup` does not clear them (`RA:285-289`).
   - This is harmless today because every reader also checks SelectedLevel == 2.

---

## 1. How GameManager reaches Level 2

**Build and cleanup routing**
- GM maps `LEVEL_GENERATORS[2] = "Level2Generator"` (`GM:139-143`).
- `L2G` is a 14-line shim: `Build` and `Cleanup` call `Adapter.Build` and `Adapter.Cleanup`.
- GM judges success only by whether `Build` throws (`GM:1639-1646`).
- GM also calls `Cleanup()`:
  - from `cleanupActiveWorld` (`GM:1735-1753`);
  - at boot, from `sanitizePersistedLevelState` (`GM:653-664`), when any of these is found: `workspace.PoolroomsLevel2`, `workspace["Level 2 Generated World"]`, `ServerStorage.StoredLevel1Entity`, `ServerStorage["Level 2 Stored Level 1 Entity"]`, `ServerStorage.StoredServerLobby`, `ServerStorage["Level 2 Stored Server Lobby"]`, or `SelectedLevel == 2`.

**What `ensureWorld` waits for after Build** (`GM:1598-1602`, `1660-1669`)
- `workspace.Elevator`, waited 180 s.
- Its `DoorL` and `DoorR`, waited with **no timeout**.
- `workspace.MazeStart`, waited 30 s.
- `EntityStart` and `Entity` only for level 1 (`GM:1663-1665`).
- Elevator doors are opened only for levels 1 and 3. Level 2 calls only `elevatorApi.close()`: on a wipe (`GM:2956`) and after a win (`GM:3124`).

---

## 2. The round loop as it actually runs

1. **Launch.**
   - Station or reserved-server arrival: `prepareGroupLoading(attempt, group, 2, false)` (`GM:3249`, `GM:3973`).
   - Sets `InRound=true`, clears `Escaped` and `Level2_ExitTransition` (`GM:2201-2208`).
   - Sends `RoundStatus "loadinggame", 2` (`GM:2209`). RoundUI paints the cover in Level 2's palette (`RUI:1156-1169`, `4626-4660`) and starts a cosmetic sequence that takes at least 7.0 s (4×1.35 s + 1.6 s, `RUI:1958-1986`).
2. **`ensureWorld(2)`** (`GM:1621-1670`). Sets `SelectedLevel=2`, `WorldGenerated=false`, `LoadStage="ENTERING_DRY_POOLROOMS"`, then runs `RA.Build` (`RA:314-461`), which does the following in order:
   1. `Cleanup()`, then `generation += 1`.
   2. `Master.ApplyInto(Configuration,"L2")`, which applies the L2_* keys from `MasterConfiguration:113-145`.
   3. Picks the seed: pinned only when 1 ≤ `workspace.Level2Seed` < 2147483647 (`RA:35-45`).
   4. Writes the state attributes, `LoadStage="LEVEL_2_GENERATING_LAYOUT"` and `Level2LightingOwnedByController=true`.
   5. `isolateLevelOneRuntime`:
      - disables EntityAI, EntityAnimation, EntityKill and PuzzleManager, found recursively;
      - moves `workspace.Entity` to ServerStorage as "Level 2 Stored Level 1 Entity" (`RA:131-151`).
   6. Runs `LayoutGenerator.Generate`, then `WorldBuilder.Build`. The world model is parented to workspace before it is filled in (`WB:5924`).
   7. Pivots **every** player onto an 8-column, 4-stud grid at `manifest.Arrival.ElevatorSpawn` plus 4 studs up (`RA:381-402`).
   8. Parks `workspace.ServerLobby` in ServerStorage as "Level 2 Stored Server Lobby" (`RA:61-68`).
   9. Sets `Level2_Phase=READY`, then calls `ObjectiveController.Start` (`RA:410`), `PoolFoamController.Start` (`RA:413`) and `PoolSlideController.Start` (`RA:428`).
   10. Sets `SelectedLevel=2`, `LoadStage=READY`, `WorldGenerated=true` (`RA:447-449`).
   11. On any error: Cleanup, `LoadStage=WORLD_ERROR`, `Level2_Phase=ERROR`, then rethrow (`RA:453-459`).
3. **Placement.** For each player (`GM:2220-2246`):
   - Load the gameplay character, then `placeSafelyInElevator` (`GM:823-876`).
   - That function sets `ElevatorSpawn.CanCollide=true`, picks a free slot (`GM:802-821`), anchors the root, pivots, starts a stream-around and adds an invisible "LobbyTransferShield" ForceField.
   - **Level 2 only:** the unanchor waits until `RoundActive==true`, up to 30 s (`GM:861-866`).
   - Then `attempt:Prepare` sends `"entryprepare" {Token, Level=2, Character, Position, Deadline}` (`GM:2175-2180`).
4. **Client readiness** (`REC:66-138`).
   - Requests streaming around the placement and preloads the character's assets.
   - Polls every 0.1 s until all of these hold for three polls in a row: `game:IsLoaded()`, assets loaded, `RoundEntryUIReady` (`RUI:6234`), `RoundEntryControlsReady` (`NR:991`), and `groundReady`.
   - `groundReady`: a ray from root+2 down 14 studs must hit a CanCollide part inside "Level 2 Generated World" or `ElevatorSpawn` with `Normal.Y > .15`. The root must be within 16 studs of the placement and SelectedLevel must be 2 (`REC:31-64`).
   - Then it fires `"entryready" {Token, Level, Character}`, at most every 0.5 s.
5. **Server barrier.**
   - `Acknowledge` checks the token, character and level. `Validate` checks InRound, alive, and root within 20 studs of the placement (`GM:2166-2174`, `RLR:86-94`).
   - `AwaitReady` needs every member acknowledged within the last 2 s. A member who dies fails the attempt (`RLR:95-125`). The timeout is 60 s → `recoverFailedEntry` (`GM:2117-2160`).
   - On commit: `RoundLoadingState="ready"` and `"entryreleased"` (`GM:2247-2256`). RoundUI lifts the cover (`RUI:4667-4674`, `1949-1952`).
6. **`playRound`.**
   - Level 2 branch: sends `"poolaccess"` (`GM:2964-2970`).
   - Sets `PuzzleWon=false`, `PostWinIntermissionActive=false`, `RoundActive=true` (`GM:3020-3022`). This lets the held unanchor finish.
   - Sends `"start"` (`GM:3026`), which starts the Level 2 radio briefing 2.5 s after the cover clears (`RUI:4733-4735`, `2058-2060`).
   - Pool Foam stays Dormant until 15 s after round start, then goes to Foreshadow. Before the first pump it only targets players inside the Kids Area (`PFC:666-670`, `843-848`).
7. **Pumps.** A player holds the prompt 1.6 s; the server rechecks with `canUsePump` (`OC:225-243`). Activation (`OC:540-654`) then:
   - disables the prompt and sets the lamp, lamp glow and status ring to the running colour;
   - tweens the lever 76°;
   - sets `Level2_PumpRunning=true` on the pump model;
   - posts `TeamObjectives.Announce`;
   - increments `workspace.Level2Pumps` and sets these state attributes for pump number n: `Level2_PumpStartedAt<n>`, `Level2_PumpActivatorUserId<n>`, `Level2_PumpActivatorPosition<n>`;
   - fires sound `"Level 2 Pump Start" {Position=pivot}` to everyone;
   - tweens the gauge over `PumpSoundDuration` (default 11.572 s, clamped 1–30, `OC:128-148`);
   - adds a "pump" noise to NoiseRegistry every 2 s for that duration;
   - 10 s later: fires "Level 2 Drain Rush" and fills the drained corridor's water region with Air (`OC:615-621`, `345-349`);
   - at 2 pumps or more: sets `workspace.Level2FoamLethal=true` and shows "THE WATER IS NO LONGER SAFE" (`OC:640-652`).

   Pool Foam phase by pump count: 1 = Foreshadow (no attacks), 2 = Pressure (attacks on), 3 = Finale (`PFCFG:286-312`, `PFC:639-671`). The Pool Slide spawns at 2 pumps and enrages at 3 (`PSC:24-25`, `172-186`).
8. **Doors.** On the final pump, after `PumpSoundDuration`, `openPressureDoors` runs (`OC:404-495`):
   - `Level2ExitPowered=true`, `Level2FoamLethal=true`, `Level2_Phase` and `Level2_LightingMode` = `EXIT_OPEN`;
   - sound "Level 2 Pressure Door" with `{DoorPositions}`;
   - each door: `CanCollide=false`, rises by Size.Y+6 over 3.4 s, then `Transparency=1`;
   - the stripes follow; the exit mouth turns the open colour at 0.35 transparency;
   - `Level2_ExitPosition` = Mouth position, or `PathPoints[1]` if there is no mouth;
   - both sensors get `CanTouch=true`;
   - alert "PRESSURE EQUALIZED".

   Pool Foam's route graph unblocks the PressureDoor corridors at the same moment (`PFN:227-231`).
9. **Exit ride.**
   - The player climbs to the Grand Slide Hall deck and enters the flume mouth. The client starts sliding on any `Level2_SlideFloor` with a downhill grade of at least 0.20 (`L2SL:669-671`) and fires `Level2SlideRagdoll "Begin"`. The server re-validates the floor (`SRS:198-252`, `333-433`).
   - Completion triggers on sensor `.Touched` or on a Heartbeat segment sweep through the sensor boxes, padded by 3 studs, with a teleport-plausibility guard (`OC:689-764`).
   - `completeFor` (`OC:667-687`): `Escaped=true`, `Level2_ExitTransition=true`, "Level 2 Slide Rush" to the rider, and `RoundStatus "escape", name` to every player in the round.
10. **Transition.**
    - The client lifts the rider one helix turn whenever `Y < Level2_RecycleTriggerY` (`L2SL:582-614`).
    - Server backstops:
      - a lift once the rider is half a turn below the trigger (`OC:823-840`);
      - an off-path / stall watchdog, off path > 1.5 s or stalled > 3 s, which puts the rider back at the landing at 70 studs/s (`OC:842-916`).
    - A rider who dies is reloaded by `scheduleTransitionRespawn` (`GM:2675-2710`). OC puts them back on the ride 0.35 s after `CharacterAdded` (`OC:940-955`), and GM skips its own elevator placement for them (`GM:1110-1112`).
11. **Win.**
    - The loop wins when every living participant is Escaped (`GM:3052-3056`). `PuzzleWon` is not used by Level 2.
    - A wipe opens a 15 s `partydown` window, then `lose` (`GM:3035-3047`).
    - On a win: `RoundActive=false`, `PostWinIntermissionActive=true`. The round lifecycle stays open on a Level 2 win so riders keep respawning onto the ride (`GM:3073-3076`).
    - `entryMode = "level2-exit-tube"` if anyone rode out (`GM:2737-2742`, `3111-3112`).
    - Then a 15 s result window (`Routing.PostWinSeconds`, `GM:2445-2551`).
    - The Level 2 audio, lighting and slide controllers stay on during that window because `Level2_ExitTransition` is still true (`L2SC:203-209`, `L2LC:37-47`, `L2SL:95-106`).
12. **Continue or return.**
    - Published: teleport to Level 3 carrying `EntryMode` (`GM:3132-3142`). The destination resumes riders in Level 3's continuation bore (`GM:948-1059`, `3970-3973`).
    - Studio: `continueStudioCampaign` runs `cleanupActiveWorld` (which ends in `RA.Cleanup`), then enters Level 3 with slide resume (`GM:2553-2574`).
    - Returning to the lobby goes through `returnGroupToLobby`. In Studio, mid-round `leaveround` answers `leavefailed`, because the lobby is parked (`GM:2908-2913`).

---

## 3. The contract

### 3.1 Workspace-root instances (outside the world model)

**`workspace.Elevator`**
- What it is: a Model with `Level2_CompatibilityMarker`, containing a shell part plus `DoorL` and `DoorR` parts, all invisible with Can* off (`WB:5840-5859`).
- Read by (server): `connectElevator` (`GM:1598-1619`), and `close()` on wipe and win.
- If missing: the 180 s wait, or an infinite wait on DoorL/DoorR, outlasts the 60 s entry timeout → `LOADING_TIMEOUT`.

**`workspace.MazeStart`**
- What it is: a 4×0.2×4 invisible Part with the marker (`WB:5871-5872`).
- Read by (server): `ensureWorld` (`GM:1661`).
- If missing: `worldReady=false` → `WORLD_LOAD_FAILED`.

**`workspace.ElevatorSpawn`**
- What it is: a 7×0.2×7 Part with the marker, `CFrame = lookAt(spawn, spawn+roomDirection)`, Y = arrival floor + 0.1 (`WB:5873-5875`).
- Read by:
  - server: player placement (`GM:825-839`), re-entry fallback (`GM:2839-2840`), Adapter arrival grid (`RA:382-402`, via the manifest);
  - client: REC ground ray (`REC:54`).
- Its LookVector and RightVector define the slot grid.
- If missing: `ENTRY_PLACEMENT_FAILED`; Build errors (nil index at `RA:383`).

**`workspace.EntityStart`**
- What it is: a marker Part moved to the den centre + 4 (`WB:5876`, `6293`).
- Read by: no Level 2 reader (GM uses it for level 1 only, `GM:1663`). Destroyed at cleanup.
- If missing: nothing.

**`workspace["Level 2 Temporary Audio"]`, `workspace["Level 2 Temporary Spatial Cues"]`**
- Client-only Folders created by L2SC (`L2SC:428-435`, `760-767`). Not part of the world.

Cleanup removes all four markers only when they carry `Level2_CompatibilityMarker` (`RA:121-129`).

### 3.2 The world model `workspace["Level 2 Generated World"]`

The name is load-bearing. It is matched by REC:50, RUI:379/425, L2SC:326/330/801, L2SL:571, SRS:202, L2PF:364/398-404, L2EA:422, ESP:53/174, L2AC:420/455, RA:250/272-276 and GM:657.

**World-model attributes**
- `Level2_Generation`. Must equal the session generation:
  - OC `validSession` (`OC:198`) — pumps and the exit go dead without it;
  - PSC Start and alive check (`PSC:90`, `813`);
  - L2SC groan generation (`L2SC:588`, `672`);
  - PFC accepts nil (`PFC:166-167`).
- `Level2_Seed`, `Level2_GenerationAttempt`, `Level2_Theme`, `Level2_Spiral*`, `Level2_TerrainCenter/Size`, `Level2_HallCount/CorridorCount/KidsRoomCount/SlideHallCount`, `Level2_ArchRibMesh*`: readbacks only (`WB:5920-5923`, `5986-5988`, `6244-6246`, `6297-6302`).
- `Level2_ExitTransitionProbeConsumed`: written by TS (`TS:549-559`).

**Folders created** (`WB:5926-5935`)
- "Level 2 Geometry", containing "Level 2 Halls", "Level 2 Corridors", "Level 2 Kids Wing", "Level 2 Slide Halls", and the exit flume / arrival concourse.
- "Level 2 Objectives", containing the pump station Models and "Level 2 Pressure Doors".
- "Level 2 Lighting".
- **"Level 2 Navigation"**: the hall centre nodes, excluded from AI rays (`PFN:357`, `PFO:196`, `PSN:362`).
- **"Level 2 Entity Nodes"**: patrol nodes, Pool Foam spawns and dens.
- Runtime additions: "Level 2 Pool Foam Runtime" (`PFCFG:12`) and "Level 2 Pool Slide Runtime" (`PSC:21`), parented into the world.

### 3.3 The manifest (a server-only Lua table returned by `WorldBuilder.Build`)

Missing items marked "assert" throw inside `RA.Build`, which ends in `WORLD_ERROR` and a failed entry.

**World**
- Type and consumers: Model parented in workspace. Used by OC, PFC, PFN, PFO, PSC, PSN, RA cleanup.
- Missing: assert (`OC:265`, `PFC:2000`, `PSC:811`).

**Layout**
- Type and consumers: table; see 3.4. Used by PFC, PFN, PSC, PSN.
- Missing: Pool Foam start fails, which is fatal (`RA:416-418`).

**Pumps[i]**
- Required by assert (`OC:270-286`):
  - `Index`: a unique number;
  - `Model`: a Model under World;
  - `Prompt`: a ProximityPrompt under Model;
  - `Lamp`: a BasePart;
  - `GaugeNeedlePivot` (BasePart), `GaugeNeedleZeroCFrame` and `GaugeNeedleFullCFrame` (CFrames);
  - `GaugePressureValue` (NumberValue) and `GaugePressureText` (TextLabel).
- Optional: `LampGlow`, `LeverStatusRing`, `Lever`, `LeverRestCFrame` (`OC:550-568`).
- `#Pumps` is the pump goal (`OC:516`).

**PressureDoors[]**
- Required: must be a table, but may be empty (`OC:288`).
- Per record: `.Door` BasePart, `.Stripe` optional (`OC:433-457`).
- PFN does not read these records; it reads `Layout.Corridors[].Kind`.

**Drains[pumpIndex]**
- Optional (`OC:610`). Each is a record with `.Water = {CFrame, Size}` and is drained with Air (`OC:345-349`).

**Exit.Trigger, Exit.Backstop**
- Assert (`OC:295-319`; `TS:101-150`):
  - two distinct BaseParts under World;
  - attribute `Level2_ExitCompletionBeam=true`;
  - attribute `Level2_ExitCompletionSensorThickness` ≥ 8, and TS also requires ≥ 4×105/60 = 7;
  - `Transparency=1`, `CastShadow=false`, `CanCollide=false`, Material not Neon;
  - no Light, ParticleEmitter, Beam, Decal, Texture, SurfaceGui or BillboardGui children.
- Runtime: OC toggles only `CanTouch` (false at start, `OC:533-537`; true on open, `OC:486-488`).

**Exit.SafeSpawn**
- Assert: a BasePart under World (`OC:320-322`). TS also wants attribute `Level2_ExitRecoverySpawn` (`TS:364`).
- Used at `OC:937`.

**Exit.TransitionEnd, Exit.TransitionLength**
- Assert: a Vector3, and a length ≥ `MINIMUM_TRANSITION_LENGTH` 2000 (`OC:104`, `323-327`).
- TS checks the declared length is within 35% of the measured length (`TS:209-215`).

**Exit.FlumeBoundsCenter / FlumeBoundsSize**
- Assert: Vector3s (`OC:328-330`). No runtime reader.

**Exit.PathPoints, Exit.BoreRadius**
- Assert: at least 2 points, radius > 0 (`OC:331-334`). TS wants more than 32 points (`TS:295`).
- Used by `distanceToPath` with tolerance BoreRadius+14 (`OC:782-799`).

**Exit.Recycle**
- Assert (`OC:335-342`): `{TriggerY, DeltaY>0, LandingY, Radius, CenterX, CenterZ, Turns≥3}`; TS also wants `TopY` and `BottomY` (`TS:290-358`).
- Invariant: lifting any path point in the recycled span by DeltaY must land within 0.5 studs of another path point (`TS:324-343`).

**Exit.Mouth**
- Optional, not asserted. Colour and transparency change on open, and its position becomes `Level2_ExitPosition` (`OC:465-482`).

**Exit.FlumeModel**
- TS needs exactly one descendant with `Level2_ExitTransitionEndStop`, CanCollide, overlapping `TransitionEnd` (`TS:236-257`).

**Arrival.ElevatorSpawn**
- BasePart (`RA:382`). Missing → Build error.

**EntityNodes**
- A folder of BaseParts carrying `Level2_HallId` and `Level2_PoolFoamSpawn` (`PFC:234-254`).
- Pool Foam needs at least one node in each Kids hall, or falls back to the hall centre + 2. The spawn must pass the floor check, or the build fails (`PFC:538-542`, `2104-2109`).

**Navigation**
- Folder, excluded from rays (`PFC:780-781`, `PFO:195`). PSC uses its nodes as spawn anchors (`PSC:219`).

**EntityDen**
- BasePart "Level 2 Entity Den A Spawn" (`WB:6277`). PSC anchors.

**WaterRegions, PreviousWaterAppearance, TerrainCenter, TerrainSize**
- Read by cleanup (`RA:196-235`).

**BuoyantProps**
- Not built (see §0 item 5).

### 3.4 `manifest.Layout` fields read by gameplay

**`Halls[i]`** (`PFN:163-208`, `PFC:192-232`)
- `{Index, Id, MinX, MaxX, MinZ, MaxZ, Center (Vector3, Y=0), Connections{indices}, Role, KidsIndex, …}`
- Hall lookup is by axis-aligned rectangle; an off-hall position falls back to the nearest centre.

**`Corridors[i]`** (`PFN:210-314`)
- `{Index, A, B, Axis "X"|"Z", Cross, From, To, Kind "Open"|"PressureDoor"|"SharedWall", DrainGroup}`

**`CorridorByPair["min:max"]`** (`PFN:211-215`)

**`KidsArea`**
- Must hold at least 1 hall, or Pool Foam start fails (`PFC:2008-2012`). The generator makes 5 (`CFG:86`), so 5 foams spawn.

**`PumpHalls`**
- Three halls. `[1]` is a dry Kids hall; `[2]` and `[3]` are ≥ 300 studs away (`LG:435-472`).

**`Arrival`, `EntityDen`, `EntityDenB`, `SlideHalls`, `GrandSlideHall`, `Bounds`, `Seed` (PFC RNG, `PFC:2054`), `Attempt`**

**Generator invariants that gameplay depends on**
- Every corridor into the grand hall is a PressureDoor, and the rest of the map must stay reachable without them (`LG:549-565`).
- Each pump gets the nearest non-kids corridor of length ≥ 40 as its drain (`LG:578-599`).

### 3.5 Per-part attributes the geometry must carry (all read server-side unless noted)

**`Level2_EntityGround=true`**
- Applies to: every CanCollide surface Pool Foam or the Pool Slide may stand on.
- Readers: PFN:377-393, 537; PSN:360, 627.
- Missing: the AI can't walk there; a Pool Foam spawn failing its floor check makes the build fatal.

**`Level2_NoEntityGround=true`**
- Applies to: roofs, slide floors.
- Readers: PFN:141, 538; PSN:146, 628.
- Missing: the AI may plan over roofs or slides.

**PathfindingModifier `Label="Level2Roof"`, `PassThrough=false`**
- Applies to: any part whose name contains "Ceiling", "Skylight" or "Roof" (`WB:6317-6332`, applied **by name**).
- Readers: Path `Costs {Level2Roof = math.huge}` (PFN:1936, PSN:2127).
- Missing: paths may run over roofs.

**`Level2_BuoyantProp=true`**
- Applies to: floating props.
- Readers: PFN:365-367, PSN:361 (excluded from body checks).
- Missing: props block AI routes.

**`Level2_SlideFloor=true` + `Level2_SlideDirection` (Vector3) [+ `Level2_OneWayExit`]**
- Applies to: slide and flume collision floors and chamfers (`WB:2517-2549`).
- Readers: client L2SL:524-541; server SRS:220-243; TS:165-191, 580.
- Missing: no slide or ragdoll. Note that **any** floor with grade ≥ 0.20 and this flag ragdolls the player.

**Flume Model attributes**
- `Level2_RecycleActive`, `Level2_RecycleTriggerY`, `Level2_RecycleDeltaY`, `Level2_HelixCenterX/Z`, `Level2_HelixRadius`, `Level2_FlumeBoreRadius` (`WB:3348-3356`).
- Reader: client L2SL:568-602.
- Missing: no client recycle; the server backstop still works.

**Pump Model `Level2_PumpRunning`**
- Reader: client L2SC:362-371 ("Drain Gurgle" anchor).
- Missing: no gurgle ambience.

**Pump Model `Level2_LeverHandleColorValue`**
- Reader: client L2AC:427 (dev "valve vision").
- Missing: generic colour.

**Navigation Node `Level2_Role`**
- Reader: client L2SC:296 (Kids Area nodes excluded from the WetHall anchors).

**Entity node `Level2_HallId` / `Level2_PoolFoamSpawn`**
- Reader: PFC:239-246.

**`Level2_CompatibilityMarker`**
- On Elevator, MazeStart, ElevatorSpawn, EntityStart. Readers: RA:124, GM:803.

**Written by the builder but no runtime reader found:**
- `Level2_FloorY`, `Level2_PumpIndex`, `Level2_Archetype`, `Level2_KidsColor`, `Level2_HallIndex`, `Level2_KidsIndex`, `Level2_DenAPosition`
- `Level2_PressurePercent`, `Level2_PressureRestored` (written by OC:354-355)
- `Level2_StoryOnly`, `Level2_WaterVisual`, `Level2_KidsFoam`, `Level2_SlideEntry`, `Level2_ColumnCollision`, `Level2_CorridorIndex`, `Level2_ClosedTube`, `Level2_SmoothSlide`

### 3.6 Names that code matches as strings

- `"Level 2 Corridor Vault Light"` prefix. Client L2SC:292: corridor ambience and pressure-door echo anchors.
- `"Level 2 Navigation Node "` prefix. Client L2SC:295 (WetHall anchors); server PSC:215 (spawn anchors).
- `"Level 2 Entity Patrol Node "` and `"Level 2 Entity Den "` prefixes. Server PSC:213-214.
- `"Level 2 Pump Intake Pipe"` exact. Client L2SC:299; must be a descendant of the pump Model.
- `^Level 2 Pressure Door %d+$`. Client L2SC:805; the fallback when a cue arrives without positions.
- `^Level 2 Pump Station` Models directly under `"Level 2 Objectives"`. Client L2AC:421-424.
- Model `"Level 2 Exit Flume"`, with descendants named `…Collision Floor NNN`, ordered by trailing digits. TS:57-80.
- `"Recovery Chamber"` in at least 6 part names (floor, ceiling, four walls), and at least 40 studs from every flume floor. TS:367-381.
- Floating-prop name prefixes such as `"Level 2 Lounger Seat "`, `"Level 2 Beach Ball "`, `"Level 2 Pool Noodle "`, `"Level 2 Pool Raft "`, `"Level 2 Pool Float Ring "`.
  - The server texturer adds **6 Texture instances** to every workspace BasePart with these prefixes (SRS:497-562).
  - Avoid these names on kit props unless that is wanted.

### 3.7 Workspace attributes

**`SelectedLevel`** (server)
- Writers: GM:1629, 1751; RA:292-294, 447.
- Readers: almost every L2 script; must equal 2.

**`WorldGenerated`** (server)
- Writers: RA:285, 343, 449; GM:1630.
- Readers: OC:249, 975; L2SC:207, 324; PSC:96; ESP:204.

**`LoadStage`** (server)
- Writers: RA:344, 368, 448, 455; GM:1638, 1668.
- Values: LEVEL_2_GENERATING_LAYOUT, LEVEL_2_BUILDING_WORLD, READY, WORLD_ERROR.

**`RoundActive`** (server)
- Writers: GM:3022, 3066.
- Readers: OC:196; PFC:173; PSC:95; L2SC:205; L2PF:147; RUI:4081; SPC:343, 399; GM:863.

**`Level2Pumps` / `Level2PumpGoal`** (server)
- Writers: OC:517-518, 573; RA:286-287.
- Readers: L2OUI:223-224; PFC:641-642, 2076; PSC:100; ESP:202.

**`Level2ExitPowered`** (server)
- Writers: OC:407, 519; RA:288.
- Readers: L2OUI:225, 275; PFC:646; PFN:230; PSN:235.

**`Level2FoamLethal`** (server)
- Writers: OC:414, 524, 642.
- Reader: L2OUI:241.

**`Level2_ExitPosition`** (server)
- Writers: OC:481, 523.
- Reader: L2OUI:181-207 (8-point bearing; adds "CLIMB" when more than 15 studs higher; no bearing within 12 studs flat).

**`Level2LightingOwnedByController`** (server)
- Writers: RA:345, 289.
- Readers: L2LC:46; RUI:380, 464.

**`Level2Seed`** (manual input)
- Reader: RA:36.

**`EntityPaused`** (server)
- Writers: RA:262; PFC:1993, 2134.
- Readers: L2SC:586, 692; L2EA:350; PSC:508, 540, 785.

**`Level2_PoolSlideActive`** (server)
- Writer: PSC:64-66.
- Readers: L2SC:549; L2EA:55; ESP:201.

**`TestLevel2PoolFoamEnabled`** (Studio only)
- Reader: PFC:1998.

**`RoundLoadingState/Token/Deadline`, `PuzzleWon`, `PostWinIntermissionActive`** (server)
- Writers: GM:2187-2189, 2255, 3020-3022, 3065.

### 3.8 Player and character attributes

**`InRound` (Player)**
- Writer: GM:2204 (server). Read everywhere.

**`Escaped` (Player)**
- Writer: OC:683 (server).
- Readers: the GM win loop (3054), SPC:415, L2SL:99, SRS:329.

**`Level2_ExitTransition` (Player)**
- Writer: OC:684 (server); cleared at OC:1148, GM:1147/1760/2206/2819.
- Readers: GM:1110, 2662, 2676-2701, 2738-2740; SPC:418; RUI:1876, 4415; L2SL; SRS:445-472; L2SC:199; L2LC:45; L2EA:35; PSC:110; PlayerProtection; ZyntraDetectorService; ZyntraMonetization; ProtectionHUD; Round Exit Client.

**`Level2_ExitServerRecycleCount`, `Level2_ExitRecoveryCount` (Player)**
- Writer: OC:876, 905 (server). Reader: TS:854-855.

**`DevLevel2PumpBusy/Status/Serial` (Player)**
- Writers: OC:255-261; GM:320-323 (server).
- Readers: ZS:1071, 1315-1316.

**`BeingChased`, `Level2_PoolFoamTargeted` (Player)**
- Writer: PFC:684-696, reference counted across foams (server).
- Readers: NR (adrenaline), EntityShakeController.

**`Level2_PoolSlideChased` (Player)**
- Writer: PSC:151-154 (server). Reader: NR:82-83.

**`Spectating`, `SpectateTargetUserId` (Player, client-local)**
- Writer: SPC:348, 358.
- Readers: L2SC:170-182; L2OUI:166-178; L2EA:28-33.

**`RoundEntryUIReady`, `RoundEntryControlsReady`, `RoundEntryReadyToken` (Player, client)**
- Writers: RUI:6234, NR:991, REC:127.
- Reader: REC:118-121.

**`Level2AlertOwnsBand`, `LevelTwoBriefingActive` (Player, client)**
- Writers: L2AC, RUI:4147.
- Reader: L2OUI:219.

**`Level2_ForcedSliding` (Character)**
- Writer: L2SL:463 (client).
- Readers: NR, SC:1469, DC:438, Crouch State Server, RouteMarkerService, EntityShakeController.

**`Level2_RagdollServerActive` (Character)**
- Writer: SRS:432 (server).
- Readers: NR, Crouch State Server, TS:666.

**`Level2_DesiredWalkSpeed` (Character)**
- Writer: NR:175, 203 (client).
- Readers: L2SL:116, 435; SC:1512.

### 3.9 `ReplicatedStorage["Level 2 State"]`

A Folder created by `RA:97-105`. It must be a Folder: any other class is destroyed and recreated.

- `Level2_Phase`: GENERATING_LAYOUT, BUILDING_WORLD, READY, EXIT_OPEN, CLEANING, IDLE or ERROR.
- `Level2_LightingMode`: NORMAL, EXIT_OPEN or OFF. Read by L2LC:90 to pick the grade (`L2LC:104-124`).
- Seed readbacks: `Level2_Generation`, `Level2_Seed`, `Level2_RequestedSeed`, `Level2_SeedPinned`, `Level2_RandomRecoverySeed`, `Level2_ResolvedSeed`, `Level2_GenerationAttempt`, `Level2_UsedFallback`, `Level2_FallbackBaseSeed`, `Level2_Error`.
- Timing and size readbacks: `Level2_LayoutSeconds`, `Level2_BuildSeconds`, `Level2_WorldDescendants` (the instance-count readback, `RA:374-375`), `Level2_HallCount`.
- Pump progress: `Level2_PumpProgress`, `Level2_PumpSoundDuration`.
- Per pump n (1–3): `Level2_PumpStartedAt<n>`, `Level2_PumpActivatorUserId<n>`, `Level2_PumpActivatorPosition<n>`. PSC reads pump 2's (`PSC:228-236`).
- Encounter state: `Level2_PoolFoam*` (`PFC:151-162`) and `Level2_PoolSlide*` (PSC `publish`).

### 3.10 Remotes

**`Remotes.RoundStatus`**
- Server → client: `loadinggame(level)`, `entryprepare{Token,Level,Character,Position,Deadline}`, `entryreleased{Token}`, `entrycancel`, `loadfailed`, `poolaccess`, `start`, `escape(name)`, `death`, `partydown`, `partydownclear`, `win`, `postwinchoices`, `lobby`, `leaveack`, `leavefailed`.
- Client → server: `entryready{Token,Level,Character}`, `returntolobby`, `continuenow`, `leaveround`, `spectatetarget`, `spectatevital` (`GM:1481-1505`).

**`"Level 2 Remotes"."Level 2 Sound Event"`** (authored)
- Server → client: `(cue, context)`.
- Allowed cues: Pump Start, Drain Rush, Pressure Door, Slide Rush (`L2SC:48-53`, `968-1008`).
- `context.Position` → a 3D cue with 60/600 rolloff (`L2SC:924-965`); `context.DoorPositions` → the door cue (`L2SC:836-907`).

**`"Level 2 Remotes"."Level 2 Alert Event"`** (authored)
- Server → client: `(title, subtitle, instruction, hold)`, sent only to InRound players (`OC:168-177`, `L2AC:585-597`).

**`"Level 2 Pool Foam Remotes".ClientReport`, `.ClientEvent`**
- Client → server: camera reports at 8 Hz, gated by the folder's `Generation` attribute (`L2PF:370-385`).
- Server → client: events, including the target-only `AttackHit`.

**`Remotes.Level2SlideRagdoll`**
- Client → server: "Begin" / "End". SRS creates it if missing (`SRS:14-24`); L2SL waits 15 s for it (`L2SL:16`).

**`Remotes.ReportNoise`**
- Client → server: "walk" / "sprint" at 5 Hz on levels 1, 2 and 4 (`NR:392-415`). Drained at module scope by PFC (`PFC:1958-1987`).

**`Remotes.DevControl`**
- Client → server: `"level2PumpPair"` (`DC:650-652`, `ZS:1064-1072`, `GM:311-324`).

**`Remotes.Level3SlideStream`**
- Level 3 side of the transition (`GM:918-946`, `L2SL:52-72`).

### 3.11 CollectionService tags

- **The World Builder applies no tags**; the generated world has no tag contract.
- Runtime tags:
  - `Level2HostileEntity` (`PFCFG:13`, `PSC:511`). Readers: DC:324, ZyntraDetectorSensing:21.
  - `Level2PoolFoamEntity` (`PFC:437`). Readers: L2PF:29, L2EA:220.
  - `Level2EntityRuntime`, `Level2EntityDecoy`, `Level2EntityTrail` (`PFC:50-52`).
  - `Level2PoolSlideEntity` (`PSC:512`). Reader: ESP:170.

### 3.12 Collision groups

- No Level 2 code sets a collision group.
- GM registers `DevNoclip` and makes it non-collidable with **every group registered at boot** (`GM:193-198`).
- A collision group a kit registers later will still collide with dev-noclip players unless it is also paired with DevNoclip.
- The lobby-only groups are QueueBarrier and QueueMember (`GM:207-214`).

### 3.13 ProximityPrompts

There is exactly one per pump (`WB:4601-4608`, `4626`):
- Name "Level 2 Pump Prompt", ActionText "START PUMP", ObjectText "Pump station N".
- HoldDuration 1.6, RequiresLineOfSight true.
- MaxActivationDistance 12, set to 10 after `ScaleTo(.34)`.
- Parent: the lever grip BasePart.

Server recheck (`OC:225-243`):
- the prompt is Enabled and under World;
- the root is within MaxActivationDistance + 2 of the prompt's parent position;
- a ray from Head to the grip (ignoring water and the character) hits nothing outside `pump.Model`.

Default exclusivity is OnePerButton, so no other E-prompt should sit near a pump.

### 3.14 Terrain contract

- **All water is Terrain Water.**
  - `addWater` is the only terrain writer, and each region it fills is recorded (`WB:349-354`).
  - Water surfaces sit at Y = 0.1 (`WB:371`, `393`, `4950`).
  - Global water look is set at `WB:5907-5911`; cleanup restores the previous values and clears each recorded region plus an 8-stud margin (`RA:196-235`).
- **A drain replaces one corridor region with Air** (`OC:348`).
- **What depends on real terrain water:**
  - SC wading audio: the ray hit must have `Material == Water`, with the root 0.6–4.25 studs above the surface (`SC:1481-1506`). Otherwise the dry-tile footsteps play.
  - Path costs `{Water = 1}` (`PFN:1936`, `PSN:2127`).
- **Every gameplay ray ignores water:** OC:238, PFN:347, PFO:203, L2SL:40, REC:87, SRS:213.
- **Depths stay below swimming level:** at most 2 studs (`CFG:108-121`).

### 3.15 Spatial and numeric assumptions

**Arrival**
- Needs dry, flat, collidable floor under "Level 2 Generated World".
- Slot grid: 7 rows × 4 studs along ElevatorSpawn.LookVector, columns at ±2 and ±6 along RightVector, 4 studs up (`GM:802-821`). That means at least about 24×12 studs clear in front of the spawn.
- ElevatorSpawn is forced collidable as the emergency floor (`GM:833`).
- REC ray: 14 studs, `Normal.Y > .15`; server drift tolerance 20 studs.

**Pumps**
- About 6.78 studs tall after the 0.34 scale (`WB:4612-4619`), placed at the hall centre plus the floor Y (`WB:4313`).
- Reach 10 (+2) studs, with clear line of sight from head to grip.

**Pressure doors**
- Part "Level 2 Pressure Door N", DiamondPlate, 2.2 × 36 × 34, centred at Y = 14 at the corridor's `To` end (`WB:4956-4966`).
- Opens by rising Size.Y + 6 = 42 studs (`OC:441`), so it needs that much clear space overhead.

**Grand Slide Hall and exit**
- Every entrance is a PressureDoor corridor.
- The flume starts at (hall.MaxX − 14, deckY + 9.3, deckZ) (`WB:3232`) and exits east past Bounds.MaxX + 60 (`WB:3231`).
- The exit hall must be at least 210×200 and within 80 studs of the east shell (`CFG:78-84`).

**Exit flume and transition** (`WB:3229`, `3258-3272`)
- Bore radius 8.
- Grade 0.21, which must stay above the release slope of 0.12 (`TS:192-194`).
- 250-stud transfer, then a helix of radius 96 with 3 turns: about 126.7 studs of descent per turn.
- Bottom at about Y −428; it must stay at least 40 studs above `FallenPartsDestroyHeight` (`TS:223-230`, `313-322`).
- Floors must overlap with no holes (`TS:195-197`).
- From the trigger onward, every floor needs `Level2_OneWayExit` (`TS:189-191`).
- The ride must last more than 15 s at 105 studs/s (`TS:201-204`).
- Sensors are 9 thick, at path X = plungeEnd.X − 26 and − 6 (`WB:3570-3607`).

**Slides**
- Entry slope 0.20, release 0.12 (`L2SL:19-20`).
- Soft speed caps: 88 studs/s on open slides, 105 on the exit (`L2SL:28-29`).
- Collision friction 0.05 (`CFG:144`).

**Pool Foam navigation**
- A surface counts as walkable when it is CanCollide, has `Level2_EntityGround`, has a normal with Y ≥ 0.57 (about 55°), and is within a 3.5-stud step.
- Probes 12 studs above and 80 below (`PFN:515-559`, `PFCFG:173-176`).
- Agent radius 2.2, height 6; no jumping or climbing (`PFN:1930-1936`).
- Kill distance 5.5 (`PFCFG:167`).
- The route graph runs hall centre → doorway "spokes" → next hall centre, with waypoint Y fixed at the start height (`PFN:274-313`). Keep each hall's centre axes and door spokes clear.

**Sight**
- Observer and kill sight rays do **not** respect CanCollide, so every CanQuery part blocks a "look" or a kill (`PFO:173-179`, `199-203`; `PFC:764-786`).
- Proximity latch: within 8 studs, for 7 s, while the player moves under 3 studs/s (`PFCFG:111-115`).

**Pool Slide**
- Spawns at an anchor at least 100 studs from every participant, preferring hidden anchors about 140 studs from the second-pump activator (`PSC:228-263`).
- The template's corridor fit was verified against 30×30 doorways and 34-wide corridors (`PSC:265-281`, `CFG:57`, `98-99`).

**Re-entry**
- Needs an anchored floor with `Normal.Y ≥ .85` (no steeper than about 31.8°) under all four footprint corners, plus a clear box of 2.8 × at least 4.8 × 2.8 (`RP:43-69`).
- Otherwise it falls back to ElevatorSpawn.
- The safe-position sampler records a position every 0.5 s while the player is grounded with |vertical speed| < 2 (`GM:2756-2771`).

### 3.16 Authored assets outside the world

- `ReplicatedStorage["Level 2 Sound Library"]`: StringValue slots (`CFG:215-232`). Not mirrored to the repo.
  - Readers: OC:129-131 (the pump clip length), L2SC:109, SC:1413, L2EA:232.
- `ReplicatedStorage["Level 2 Pool Foam Audio"]`, kept in sync by PFC.
- `ReplicatedStorage["Level 2 Entity Audio Bank"]`.
- `ServerStorage.Level2Assets`: the Pool Foam templates and "Level 2 Pool Slide Template".
- The loose MeshPart templates in the ServerStorage root (arch ribs, slide meshes).
- `MasterConfiguration` L2_* keys (`MasterConfiguration:113-145`): ComplexExtent, MinimumLeafSize, MaximumLeafSize, MinimumHallCount, CorridorWidth, WallHeight, SlideHallCount, SlidesPerHall, KidsAreaRoomCount, ShallowPoolDepth, DeepPoolDepth, CeilingPanelBrightness. All are tied to the current BSP generator.

---

## 4. What a kit rebuild must reproduce

### Build and manifest
1. A Model named exactly "Level 2 Generated World", with `Level2_Generation` set.
2. The four root markers. Elevator must contain DoorL and DoorR.
3. A manifest with the same field names and types, including the exit sub-table that passes `validateManifest` and `ValidateExitGeometry`.
4. A Layout that keeps hall rectangles, Connections, and corridor `Cross/From/To/Kind`. The Pool Foam and Pool Slide route graphs are built from it, not from the geometry.

### Geometry
5. `Level2_EntityGround` on every walkable collidable surface; the roof label on roofs (applied by name today); `Level2_SlideFloor` and `SlideDirection` only on slides.
6. Terrain water: recorded per region, with each pump's drain corridor as its own region.
7. Hills: the safe limits are re-entry's ≤ 31.8° and the AI's 3.5-stud steps at ≤ 55°.
8. Kit meshes need correct CanQuery and collision fidelity, because AI sight rays ignore CanCollide.

### Instance count
- The Pool Slide's context build (PSN:346-376) and the server water-texturer (SRS:542-561) both scale with world size.
- Measure the change with the `Level2_WorldDescendants` readback.

### Test cost
These offline tests encode the current builder and will need rework:
- `tools/tests/test_level2_tunnel_height.py`
- `test_level2_tile_face_culling.py`
- `test_pool_foam_navigation.py`
- `test_pool_slide_navigation.py`
- `test_level2_pool_slide_release.py`