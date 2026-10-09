# Level 2 world contract: what the three readers missed, and what they got wrong

I checked the working tree at HEAD `e8e4e7c`, including the uncommitted edits to GameManager and RoundUI. Scope: every live `.lua` under ServerScriptService, StarterPlayer, ReplicatedStorage and Workspace (186 files). I left out ServerStorage/Archive, the CodexBackup and PoolSlideContextDiagnosticBackup folders, TEMP_*, and Project Mirror. Studio was not touched.

**Short answer:** 22 dependencies are missing from the contract and 8 contract items are wrong or imprecise. The three that change the kit design are:
- Pool Foam spawn nodes must be real Parts placed directly in the `Level 2 Entity Nodes` folder (M1). The layout reader's proposal to use Attachments would break this.
- The arrival area must be about 32 studs wide, not 12 (M4).
- The new lobby stays in the world during a Level 2 round, so the kit's footprint and the preview have to avoid it (M5).

**Abbreviations.** Under `ServerScriptService/`:
- GM = GameManager
- RA, WB, LG, CFG, OC, PFC, PSC, SRS, TS = the Level 2 Systems modules (Round Adapter, World Builder, Layout Generator, Configuration, Objective Controller, Pool Foam Controller, Pool Slide Controller, Slide Ragdoll Service, Exit Transition Test Suite)
- RP = ReentryPlacement
- RMS = RouteMarkerService
- L1PA = Level1BlenderPreviewAccess
- TLB = TunnelLobbyBuilder
- L3WB = Level 3 World Builder

Under `StarterPlayer/StarterPlayerScripts/`: RUI (RoundUI), REC (Round Entry Client), SC (SoundController), L2SC (Level 2 Sound Controller), L2SL (Level 2 Slide Controller), L2LC (Level 2 Lighting Controller), L2AC (Level2AlertClient), L2PF (Level 2 Pool Foam Client), ESC (EntityShakeController), FC (FlashlightController), FBC (Friend Boost Client), DC (DevCheats). MC = `ReplicatedStorage/MasterConfiguration`.

---

## A. Dependencies missing from the contract (most important first)

### M1. Spawn and patrol nodes must be Parts directly inside `Level 2 Entity Nodes`
- **What reads it:** PFC:234-252 `collectNodes` looks only at `manifest.EntityNodes:GetChildren()`, keeps only children that are Parts, and sorts them by Name.
  - Anything nested inside a prefab model is ignored, and so is anything that is an Attachment.
- **Pool Slide:** PSC:209-225 `collectAnchors` searches at any depth, but only Parts whose names start with `"Level 2 Entity Den "`, `"Level 2 Entity Patrol Node "` or `"Level 2 Navigation Node "`.
  - With zero matches, `Start` gives up with "manifest has no entity navigation anchors" (PSC:823-824).
  - RA then marks the Pool Slide UNAVAILABLE and only prints a warning (RA:428-440), so the second hostile vanishes without an error.
- **Ambient audio anchors** must also be Parts (L2SC:289-290).
- **What breaks:** with no nodes, Pool Foam spawns at the hall centre + 2 (fatal if that spot fails the floor check), patrols fall back to hall centres, and the Pool Slide is silently disabled.

### M2. Audio anchor names carry more than the prefix
- **Per-corridor suffix:** corridor echoes are grouped by the part's full Name (`nearestByCorridor[anchor.Name]`, L2SC:815-822). WB names each one `"Level 2 Corridor Vault Light " .. corridor.Index` (WB:4933). A kit must keep a unique number per corridor, or every corridor collapses into one echo source.
- **Monster groans have no fallback:** they only play from a real anchor 55-180 studs from the listener (L2SC:570-580). If the kit drops these names, the foreshadowing groans never play.
- **Drain gurgle:** returns nothing without a `"Level 2 Pump Intake Pipe"` inside a Model flagged `Level2_PumpRunning` (L2SC:407-412).
- **The other ambience** (water drops, distant hall sounds) falls back to a random point around the listener (L2SC:396-401), so it degrades rather than disappears.
- **How anchors are found:** on the client, by scanning the world when the session starts and then listening for new descendants (L2SC:312-315). They must be Parts that actually reach the client.

### M3. Floating props depend on real terrain water
- **What reads it:** `makeBuoyant` makes props unanchored, collidable, and lighter than water (density 0.14-0.28; WB:4974-4983, called at 5079, 5091, 5664, 5673). They float only because Roblox terrain water lifts them.
- **What breaks:** if the kit replaces terrain water with a mesh water plane, these props sink.
- **Spawn spot check:** `freeWaterSpot` (WB:4987-5004) tests bounding boxes and only ignores parts whose names contain `"Water Floor"`. A big collidable floor mesh with any other name blocks every prop spawn.

### M4. The arrival area must be much wider than the contract says
- **What happens:** RA:381-402 moves every player in the server, not just the party, before it parks the lobby.
  - Up to 8 columns at 4-stud spacing (28 studs between the outer slot centres, about 32 studs of clear width), rows every 4 studs forward, 4 studs up, aimed along `ElevatorSpawn`'s facing.
- **Contract item to fix:** gameplay §3.15 says "about 24×12 studs". That is only GameManager's own placement grid (GM:802-821).
- **Studio side effect:** this also pulls non-party players who are standing in the new lobby (now the live spawn, GM:633-636) into Level 2, even though that lobby is not being removed (see M5).

### M5. The new lobby stays in the world during Level 2
- **What RA parks:** only `workspace.ServerLobby` (RA:61-68). The new lobby, `workspace.LobbyReimaginedPreview`, stays where it is.
- **Where it is:** GameManager asserts its centre is (220, 30, -760) (GM:618-619). Its bounds are ±100 X, ±144 Z, Y -5..45 relative (RUI:358-361), which is X 120..320, Z -904..-616, Y 25..75.
- **Where Level 2 is today:** X -700..700, Z -460..940 (CFG:19, 24-25), plus the flume out to `Bounds.MaxX+60` and the helix down to about Y -428.
- **Requirement:** kit layouts must stay north of about Z -600, and the preview must sit outside both areas. FBC:13-21 and FBC:130-171 also compute "in the lobby" from that lobby model's bounding box.

### M6. Every Level 2 build wipes terrain over a very large area
- **What happens:** RA:348 calls `clearOwnedTerrain(nil)` before generating. That takes the fallback path (RA:205-214) and fills 2100×200×2100 studs centred on (0, -16, 240) with air: X -1050..1050, Y -116..84, Z -810..1290.
- **What that hits:** part of the new lobby's area (Z -810..-616).
- **Consequences for the kit:**
  - Any terrain "hills" inside that box are erased by the next build.
  - Terrain not listed in `manifest.WaterRegions` survives cleanup (RA:196-202). Level 2 is the only code anywhere that writes terrain.
  - Terrain can't serve as walkable floor anyway: the Pool Foam floor check requires an attribute terrain cannot carry (contract), and REC's ground check only accepts parts inside the world model plus `ElevatorSpawn` (REC:41-53).

### M7. A preview must not use the name "Level 2 Generated World"
- **What reads the name:**
  - RA.Cleanup deletes every workspace child with that name in a loop (RA:272-276).
  - The boot clean-up triggers on it (GM:656-662).
  - RoundUI's lighting check keys off it (RUI:425-428, 464).
  - L2AC's dev valve highlight (L2AC:454) and L2PF (398-404) react when it appears or disappears.
- **Consequence:** a walk-around map preview needs a different model name. A preview that runs as a real round goes through RA and keeps the name.

### M8. A walk-around preview gets lobby lighting and a third-person camera
- **Lighting:** the Level 2 lighting controller only turns on when the player is in a round, `SelectedLevel` is 2 and `Level2LightingOwnedByController` is set (L2LC:37-47). Otherwise RoundUI applies lobby lighting (RUI:423-505). Level 4's preview solves this with an early return on `Level4LightingOwned` (RUI:431-437).
- **Camera:** outside rounds, and for dead players, the camera is third person at 8-18 studs (GM:1093-1095, 1129-1133). Inside rounds it is locked first person (GM:1088-1091).
  - CLAUDE.md (Level 4 v3) records that the camera only pulls in for collidable parts with transparency below 0.25.
  - So invisible collision boxes plus non-colliding visual meshes let the preview camera clip through walls.

### M9. Network streaming
- **Current state:** no Level 2 code sets the world's streaming mode. Only the Pool Slide model is made Persistent (PSC:498).
- **Client readers that depend on Models being present at any distance:**
  - L2AC:420-424: pump Models directly under `"Level 2 Objectives"`.
  - L2SC:362-371: walking up to the Model with `Level2_PumpRunning`.
  - L2SL:568-580: scanning the whole world for `Level2_RecycleActive` (one full-world scan per call until it is found).
- **Risk 1:** if kit rooms are cloned as Atomic models (the new lobby's Builder.ModuleScript.lua:40 does this), those containers are missing on distant clients.
- **Risk 2:** huge single collision parts. CLAUDE.md's Level 4 note: a client dropped a streamed 755×480 floor part and players fell through it, so Level 4's `Collision` model has to be Persistent. Level 2 halls reach about 277×269 studs, so the same risk applies.
- OC:592-594 and L2SC:759 and 910 already send positions with sound cues because pump and door parts may not be streamed in.

### M10. Re-entry placement details
- **Water counts as floor:** RP:19-22 never sets `IgnoreWater`, and the default is false. In flooded halls the floor ray stops on the terrain water surface (terrain counts as anchored, surface faces straight up). Safe positions and revive points therefore sit at water-surface height, about 1.5-2 studs above the tiles.
- **Bounding-box check:** the clear-space check (RP:65) uses bounding boxes, not mesh shape. One collidable room-shell or hill mesh makes every point "occupied", so every revive falls back to `ElevatorSpawn` (GM:2834-2840).
- **Anchored floor only** (RP:50, 61), so floating props never count as floor.
- **Name to avoid:** RP reads `workspace.PitZones` (RP:30-41). Level 1's clean-up also deletes workspace children named `PuzzleItems`, `Decor`, `PitZones`, `Maze`, `Elevator`, `ElevatorSpawn`, `MazeStart`, `EntityStart` (GM:1685-1695, via GM:1747). Kit and preview roots should avoid these names.

### M11. Route markers land on the collision floor, not the visible one
- **What reads it:** RMS:103-123. The marker's height is the first collidable hit (water ignored) within 12 studs below a point 2.5 studs in front of the player. If nothing is hit, it uses root height minus 2.6.
- **Shape:** a flat 2.6×3.6 plate that only turns left and right (RMS:149-161).
- **Requirement:** collision tops must line up with the visual floor. On slopes the marker floats on one side and clips on the other.
- Markers live in `workspace.RouteMarkers`, outside the world, and are cleared only when `RoundActive` goes false (RMS:290-292).

### M12. Slide detection uses the first collidable part under the player
- **Client:** L2SL:38-41 and 524-541. **Server:** SRS:209-224, which also requires the floor to be inside the world model (`IsDescendantOf(world)`, SRS:224).
- **Requirement:** any collidable kit part over a slide surface, within HipHeight + half the root + 4-6 studs, hides `Level2_SlideFloor`. Slide collision must sit inside `"Level 2 Generated World"`.

### M13. Pump line-of-sight blocks on anything queryable
- **What reads it:** OC:233-241 casts from the head to the prompt with CanCollide ignored (queryable parts count) and excludes only the player's own character.
- **What breaks:** a queryable visual mesh, or another player standing in between, stops the pump silently.
- A prompt hosted on an Attachment is supported (OC:215-221).

### M14. Wading audio needs nothing queryable above the water
- **What reads it:** SC:1379-1386 and 1481-1486. The ray excludes only the player's own character and does not respect CanCollide, so the first queryable hit from foot +1.5 down 6.5 must be terrain Water.
- **What breaks:** a queryable kit water-surface plane or rim mesh makes every step sound like dry tile. WB's kids water sheet sets `CanQuery = false` for exactly this reason (WB:1112-1121, `Level2_WaterVisual`).

### M15. The roof-by-name rule can disable walkable floors
- **What reads it:** WB:6322-6331 tags every part whose name contains `"Ceiling"`, `"Skylight"` or `"Roof"` as not walkable for the AI, and adds the Level2Roof pathfinding cost.
- **Hazard:** "Skylight Hall" is an existing room type (LG:603-617). A kit floor named, say, "Skylight Hall Floor" would become unwalkable for both hostiles.

### M16. Builder assets and settings not listed in contract §3.16 and §3.7
These matter for the decision to keep or retire them:
- **Asset folders:**
  - `ReplicatedStorage["Level 2 Assets"]` texture slots: kids tile textures per palette (WB:154-160) and `"Level 2 Pump Machinery Texture"` (WB:4271-4272).
  - `ServerStorage["Level 2 Kids Round Skylight Templates"]` (WB:535, 543).
  - `ServerStorage["Level 2 Slide Assets"]["Level 2 Slide Templates"]` (`"Level 2 Slide Open Segment"` / `"Closed Segment"`, WB:2291-2296).
  - `ServerStorage["Level 2 Column Tile Surface Template"]` (WB:36, 1242).
  - `"Level 2 Arch Rib Mesh <key>"` templates (WB:1736).
- **Workspace attributes:** `Level2ArchMeshRibs` (read at WB:1629) and `Level2ArchMeshRibsAllowEditable` (read at WB:1735, written at WB:6374).
- **Wading sound overrides:** `ReplicatedStorage.Level2Audio`, ReplicatedStorage, or workspace, as `Level2WadeCore1..3`, `Level2WadeResistance`, `Level2UnderwaterMovement` (SC:1056-1148).

### M17. Developer tuning values that already break the current generator
These Master overrides need removing or remapping for the kit:
- **`L2_SlideHallCount` = 0** (MC:131-133). Validation requires the slide-hall list length to equal this count, but `chooseSpread` with a count of 0 always returns at least the exit hall (LG:206-219, 396-399, 715-717). Every attempt fails; the build errors after 640 attempts.
- **`L2_KidsAreaRoomCount` = 0 or 1** (MC:137-139). There is no dry kids room left for pump 1 (LG:438-448), so every attempt is rejected.
- **`L2_DeepPoolDepth` up to 6** (MC:142-144) breaks the "≤ 2 studs, no swimming" assumption.

### M18. Level 3's continuation tube has to match Level 2's flume
- **Level 3 side:** L3WB:1620 hard-codes radius 8, the shell is colour (218, 226, 211) SmoothPlastic (L3WB:1665-1700), and riders resume at speed 62 (L3WB:1738-1739).
- **Level 2 side:** the flume radius is 8 (WB:3229) and the exit speed cap is 105 (L2SL:28-29).
- A restyled kit flume must update L3WB `"Level 2 Exit Slide Continuation"` too, or the seam shows. TS:396-450 checks the Level 3 side.

### M19. Pacing and height thresholds tied to the current map
- **Challenge time:** `TimeGoalSeconds["2"] = 600` (ZyntraConfig:316) assumes today's map size.
- **Pool Slide:**
  - It cannot attack a player more than 7 studs above or below it (`ATTACK_VERTICAL_DISTANCE`, PSC:43).
  - Its 100-stud minimum spawn distance is measured flat, ignoring height (PSC:47-49, 247).

### M20. Hook points the lobby preview button needs
- **The Level 1 pattern** (L1PA:24-63) attaches to:
  - `ServerLobby.LevelQueueRooms.Level1QueueRoom` in the old lobby;
  - `LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level1` in the new lobby;
  - each must have a collidable `ChamberFloor`.
  The Level 2 versions exist already (TLB:2111 builds `"Level"..level.."QueueRoom"`; Builder:121 builds `"QueueBay_Level"..level`).
- **Button position:** the Level 1 host part sits at ChamberFloor + (-20, 4.42, 0) (L1PA:45). In the old lobby's Level 2 room the basin sits at roomCenter + outward×19.2 and the column at ×20.5 (TLB:1588, 1618). Check for overlap.
- **Keeping the preview out of progression:** Level 1's preview uses the `Level1BlenderPreviewActive` flag to skip:
  - continuing to the next level (GM:2449);
  - records (GM:3086);
  - normal handling when it arrives on a reserved server (GM:3942-3954).
  A Level 2 preview round needs its own flag. Without one, a win continues to Level 3 through the exit tube (GM:3103-3142), records a Level 2 clear, and awards the `FirstClearLevel2` badge (ZyntraConfig:292).
- **Who sees the prompt:** the Level 1 client script creates the prompt only for developers (Level1BlenderPreviewButton:5-8). `Level4PreviewPrompt:6-13` hides only Level 4/5/6 prompt names, so a new Level 2 prompt name is not covered.

### M21. Listeners that run once per new world instance
- Each fires for every instance the build adds, so cost grows with instance count:
  - Server: SRS:559, LobbyPartyModeController:245, L1PA:131, Level4PreviewAccess:273, Level4V4PreviewAccess:244, Level5PreviewAccess:236, Level6PreviewAccess:285.
  - Client: DC:302, Level1BlenderPreviewButton:69, Level4PreviewPrompt:39, ZyntraStore:4039, Level 6 CD Dev ESP:148, plus L2SC:315.
- **Names kit prompts must avoid:** `ZyntraShopPrompt`, `ZyntraPartyPrompt`, `Level{4,5,6}DeveloperPreview*Prompt`, `Level1BlenderPreviewEntry`.

### M22. Areas I checked that have no world dependency
- **Ambience zones keyed to rooms:** none exist. Level 2 audio uses only the name-matched anchors in M2.
- **SpectateController:** reads only attributes, the head camera and `RoundActive` (SPC:343, 399, 418).
- **UIRegression:** UI only (`Level2ObjectiveGui`, `Level2AlertGui`, `UIRegressionLevel2AlertProbe`).
- **TeamObjectives:** builds its text from `pump.Index` (OC:570-571).
- **ZyntraDetectorSensing:** straight-line distance to models tagged `Level2HostileEntity` (lines 21, 34-35).
- **DevCheats:** tag-based ESP (DC:324), noclip, and `level2PumpPair` → `OC.DevActivatePumpPair`. The latter needs only `manifest.Pumps`, each prompt enabled and inside the world (OC:245-253, 994-999).
- **Collision groups:** none set by any Level 2 code.
- **Tags:** WB applies none.

---

## B. Contract items that are wrong or imprecise

| # | Contract claim | What the code shows |
|---|---|---|
| W1 | gameplay §3.14: "Every gameplay ray ignores water" | RP:19-22 doesn't. The SC wade ray deliberately hits water (SC:1381). FC's rays leave the default too (FC:119-120, 715-716). See M10. |
| W2 | gameplay §3.15: arrival needs "about 24×12 studs" | RA:387-401 places all server players up to 8 wide at 4 studs, so about 32 studs wide (M4). |
| W3 | gameplay §3.8: `BeingChased` / `Level2_PoolFoamTargeted` read by "NR, EntityShakeController" | ESC reads `BeingChased` only inside its `workspace.Entity` (Level 1) branch (ESC:85-99), so it has no Level 2 effect. Nothing outside PFC reads `Level2_PoolFoamTargeted` (PFC:690-2143 only). |
| W4 | layout §6: Pool Slide "spawns at pump 2" | It spawns once `Level2Pumps` reaches 2, at the best-scoring anchor (PSC:228-263): at least 100 flat studs from every player, a bonus of 30 if no player can see it, and preferring anchors near 140 studs from where the pump-2 activator stood. |
| W5 | layout §9.6: "Use Attachments in the prefab for … PoolFoamSpawn" | Conflicts with PFC:236-237 (Parts directly in the folder) and PSC:209-213 (Parts with the right name prefix). Attachments must be turned into Parts during the build (M1). |
| W6 | foam §10 rule 1: plain invisible Part colliders everywhere | Breaks camera pull-in for any non-round preview (M8), and very large collider parts risk streaming out (M9). |
| W7 | gameplay §3.8: list of `Level2_ExitTransition` readers | Missing RMS:201. Level 3's table-hiding client also reads `Level2_ForcedSliding` (Level 3 Table Hiding Client:101-102). |
| W8 | Instance count "≈52k" (task) and "≈56k" (CFG:175-176) | WB:6310-6311, SRS:546-547 and PFC:772-777 still say ~71,000, which predates the arch-mesh ribs. Measure with `Level2_WorldDescendants` (RA:374-375). |

Everything else I spot-checked held up: the seed path, `validSession`, the manifest checks in OC:263-342, the PFC spawn failure being fatal, the corridor-snapping claims, the name prefixes, and the full list of water-ignoring rays elsewhere (OC, PFO, PFN, L2SL, REC, SRS, PSC:197-198).