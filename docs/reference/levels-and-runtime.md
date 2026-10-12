# Historical reference: levels-and-runtime

Read only the section needed for the current task. This is retained history, not current startup policy.
CLAUDE.md and AGENTS.md supersede old model, ownership, testing and sync commands below.
Never automatically import this file into startup context. Dates and environment limitations may be obsolete.

# BACKROOMS: STAY QUIET [CO-OP HORROR] — working notes for Claude Code

### Changed 2026-09-29 — levels renumbered (supersedes the Level 4/5 notes above)

- The old Level 4 (Neighbour suburb) and the old Level 5 (Indoor Suburbs) are **deleted** from Studio and
  the repo, code and data. Rounds stop at `Routing.MaxLevel` 3 for everyone; `DevCeiling`,
  `HighestDevLevel`, `Level4DevStart`/`Level5DevStart` and the `Level4/5DevEnabled` flags are gone.
- **Level 4 is the cinema** (formerly Level 6): every `Level6*`/"Level 6" name, attribute, tag and string
  was renamed to Level 4. `Level4V4PreviewAccess` hooks the lobby's `Level4SealedDoor`.
- **Level 5 is `Workspace."Level 5 Quiet Suburbs"`**, imported from the Blender scene
  (`tools/level5_import/`), ~12.5k MeshParts at x=40000. `Level5PreviewAccess` gives it the cinema's
  dev-only door -> `Level5Exit` -> RETURN TO LOBBY method; `Level4PreviewPrompt` hides both levels'
  prompts from non-developers. Neither level is a round.
- The lobby was deliberately not touched (its Level 5 queue room still carries the old residential decor).

### Added 2026-10-01 - Level 4 facelift v2 + LightingStyle Realistic

- **The place runs LightingStyle Realistic** (was Soft) since the Level 4 facelift: owner decision after a
  Studio comparison (artifacts/level4-facelift-20260930/lighting/). Levels 1-3 were checked in real rounds:
  L2/L3 look the same, Level 1 is darker and more contrasty (real light falloff), not broken.
- **`Workspace."Level 4 Cinema Blender"` is now the facelift build** (Synthwave Grid 80s-90s cinema lost in
  the Backrooms): PBR SurfaceAppearances, Meshy props, split double doors, ~300 local lights with flicker and
  dead stretches. Pipeline: tools/level4_blender/README.md "Facelift v2". The Blender master is
  G:\Blender\Level4_Cinema\Level4_Cinema.blend (v1 kept as Level4_Cinema_v1.blend).
- **`StarterPlayerScripts."Level 4 Lighting Controller"`** grades the interior while the local character is
  inside the model's BoundsCenter/BoundsSize and sets the client attribute `Level4LightingOwned`;
  **RoundUI's applyPlayerLighting returns early on it** (no new top-level local; RoundUI is at the 200-register
  limit).
- Normal maps DO work on EditableMesh-uploaded meshes (tested 2026-09-30 against an imported mesh).

### Added 2026-10-02 - Level 4 facelift v3 (owner's 15 points)

- `Workspace."Level 4 Cinema Blender"` is the v3 build: starlight ceilings + neon light (gains in
  `tools/level4_blender/make_place.py`, grade in the Level 4 Lighting Controller), one theme wallpaper, Cinema 1's west
  side removed, single arcade/service doors, boarded street entrance, 3D litter. Details: tools/level4_blender/README.md
  "Facelift v3" and `artifacts/level4-facelift-v3-20261002/`.
- **Poppercam only occludes on CanCollide parts with transparency < 0.25**: the cinema's occluder colliders are now
  black and opaque, inset 0.1 stud inside the visual walls. A client-side `LocalTransparencyModifier` on them (e.g. a
  debug "hide occluders" toggle) silently turns camera occlusion off again.
- **Studio MCP sandbox (2026-10-02)**: `execute_luau` has no Network capability (no HttpService, no HttpEnabled),
  no `shared`/`_G` between calls, background `task.spawn` work dies with the call, and Scripts cannot be created or
  reparented under Workspace/ServerStorage; `UpdateSourceAsync` on existing scripts and `AssetService:CreateAssetAsync`
  still work, and a 1.2 MB code payload is accepted. Level 4 imports use `studio_upload.py` + `place_driver.py`.

### Added 2026-10-03 - Level 6 is the Indoor Playground (hide and seek)

- **Level 6 is no longer the Level 3 copy.** `Workspace."Level 6 Indoor Playground"` (x=52000, native Parts) is
  the Level 6 developer preview; `Level6PreviewAccess` no longer launches `Level 6 Generated World`. The round is
  `ServerScriptService."Level 6 Systems"."Level 6 Playground Game"`, the client is
  `StarterPlayerScripts."Level 6 Playground Client"`; the old Level 6 client scripts are disabled, not deleted.
  Pipeline, rules and attributes: `tools/level6_playground/README.md`.
- **The Studio sandbox also refuses new scripts under ServerScriptService and StarterPlayerScripts** (not only
  Workspace/ServerStorage). New scripts have to take over an obsolete existing one (rename + `UpdateSourceAsync`).
- **Studio also runs on the Mac.** `StudioMCP` lives at `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`;
  a Python MCP client can drive it directly (`tools/level6_playground/import_to_studio.py`). With Studio in front,
  macOS `screencapture` shows the viewport when the MCP `screen_capture` returns white, and Studio's File menu
  (Save to Roblox, Publish to Roblox) can be clicked through `osascript`/System Events.
- **Real mouse clicks reach Qt widgets that System Events cannot.** `osascript -l JavaScript` with
  `ObjC.import('CoreGraphics')` and `CGEventPost` clicks Studio's toolbar dropdowns (test mode "Server & Clients",
  client count), the Output filter and its "Click to share access" lines. A Server & Clients session shows up as
  extra MCP studios: one answers `Server`, the others `Client` (Player1, Player2).
- **Images from `upload_image` belong to the user, not the group.** The experience cannot use them (nor
  `generate_material` output) until "Share access" is clicked for them; `CreateAssetAsync` for images is unavailable.
  Public Creator Store decals work once resolved to their image id with `game:GetObjects("rbxassetid://<decal>")`.

### Added 2026-10-03 (later) - Level 6 entity: The Counter

- **The Level 6 child is a skinned doll now** (Meshy model and rig, ten Blender clips, 38 recorded voice
  lines), and the hide-and-seek round is switched back on. Pipeline and the reasons behind each workaround:
  `tools/level6_entity/README.md`. Data lives in `ServerStorage.Level6CounterSource` (mesh, rebuilt and baked
  once per server by the game module) and `ReplicatedStorage.Level6Counter` (`Clips`, `Voice`).
- **`AssetService:CreateAssetAsync` answered "not available yet" from this Mac session** (2026-10-03), for
  plain and skinned meshes alike. `CreateDataModelContentAsync` works and keeps skinning.
- **Level 6 must not reuse another level's sounds.** The owner rejected the Level 1 spot, chase, jumpscare
  and alert sounds there on 2026-10-03.
- **A Studio play test is audible to the owner.** They hear it while they work.

### Added 2026-10-03 (evening) - Lobby loading screen

- **`ReplicatedFirst."Lobby Loading Screen"`** (LocalScript, the only thing in ReplicatedFirst) covers the join
  until the lobby is really there: `ReservedRoundServer` known (true = stand down, the round's cover owns the
  join), `LobbySpawnMigrationReady`/`...Error`, the lobby model with `Ready`, no new descendants for 0.75 s,
  ground under the character, then `ContentProvider:PreloadAsync` over every content id in
  `LobbyReimaginedPreview` + `ServerLobby` + PlayerGui, re-censused until nothing new arrives. Failed ids get
  one retry and then let the player in with an honest line. 15 s without progress shows RETRY / ENTER ANYWAY /
  REJOIN. Client attributes `LobbyLoadingOpen` / `LobbyLoadingDone`; RoundUI's `lobbyBriefing.trySendReady`
  waits on the first. Studio-only workspace attributes `DevLobbyLoadStall` and `DevLobbyLoadBadAsset` inject
  a stall and a broken asset. Push with `python3 tools/push_loading_screen.py`.
- **The MCP sandbox cannot create scripts in ReplicatedFirst either; Studio's command bar can** (click it,
  paste, Cmd+Return; plain Return only adds a line).
- **The Roblox player's asset cache is `$TMPDIR/Roblox/rbx-storage`** (plus `~/Library/Caches/com.roblox.RobloxPlayer`);
  moving both aside gives a cold-cache join. `~/Library/Roblox/rbx-storage.db` is Studio's and is held open by it.
- The repo copy of RoundUI was about 8 KB behind Studio on 2026-10-03 (another session's edits); the loading
  gate was applied to both, the drift itself was left alone.

### Added 2026-10-03 (night) - Level 6 plays as a live round

- **Level 6 still runs outside GameManager, on the lobby server, but its players are in round state.**
  `Level6PreviewAccess.Runtime.Suit` sets `InRound = true` and loads the hazmat StarterCharacter through
  `ServerStorage.LoadGameplayCharacter`; `Runtime.Leave` clears it and reloads the lobby avatar through
  `ServerStorage.LoadLobbyCharacter`. Both are BindableFunctions GameManager exposes over its own serialized
  loaders (never call `LoadCharacterAsync` beside them: the lobby load parks StarterCharacter). The queue
  validates the lobby character through its commit, so the suit goes on after `CommitPreviewGroup` returns.
- `workspace.RoundActive` stays false and `SelectedLevel` stays 1 there, so anything that needs a round
  feature for Level 6 checks the player attribute `Level6PlaygroundPreview` (hazmat skin visuals, crouch,
  GameManager's onCharacter camera/scatter), and anything Level 1 keyed on `InRound` alone excludes it
  (Level 1 Sound Controller, SoundController's round footsteps, NoiseReporter's noise reports).
  All edits are in `tools/level6_playground/make_live.py` (counted, re-runnable).
- Order matters: `Level6PlaygroundPreview` is set before `InRound` on entry and cleared before it on exit.
- Not wired for Level 6: shields (the catch ignores PlayerProtection), glowsticks, re-entry, spectating,
  the back-to-lobby chip. The C third-person toggle is DevCheats and therefore developers only, as in
  every level; ZenMeister02 is not a developer in `DevAccess.IsAllowed`.
- The doll stands on the surface it finds under its counting spot (`Session:surface`); home base is a
  raised disc 0.6 studs above the hall floor.

### Added 2026-10-03 (late) - Level 6 horror pass

- **Seen = dead.** `ChaseSpeed` 40, `LoseSightSeconds` 15, a chase with no navmesh route goes straight through
  whatever is in the way. The doll shrieks a `sprint` line when it spots you.
- **Kill cam** (`Session:catch` + the client's `killCam`): the victim's root is anchored, the doll backs off to
  `GrabDistance` 3.6 facing them (at chase speed it is otherwise standing ON them and has no direction), the
  client's Scriptable camera is dragged into the Head bone over 3.7 s, then a black `Level6KillCover` until the
  lobby has them. `CaughtReturnDelay` 4.3 is the kill cam's length; the session keeps the doll until
  `killUntil`. A Scriptable camera un-hides the first-person body: the kill cam sets `LocalTransparencyModifier`.
- **14 new sounds** (ElevenLabs via Codex, `assets/level6-horror-pass-20261003/`): `l6_chase_loop`,
  `l6_chase_shriek`, `l6_rage_scream`, `l6_rage_loop`, `l6_kill_grab`, `l6_kill_breath`, lines `l6_angry_1..3`,
  `l6_kill_1..3`, `l6_sprint_1..2` in the voice "Demonic child for level 6". Uploaded through Asset Manager >
  Import; `pick()` falls back to older groups (`FALLBACK`) when a group's first key is missing.
- **Prize shelf is real geometry** (`prize_shelves` in `build_playground.py`: about 100 toys from balls, boxes
  and cylinders, materials `plush_*`, Fabric, non-colliding). The `prize_wall` photo board is gone.
- **Claw machine glass** is fitted to the mesh (84% x 94% of the bounding box, 40%..86% of the height) with a
  dark frame; the first version used 90% of the full width.
- Studio's viewport does not redraw in Edit mode while Studio is in the background; screenshots there need a
  play session. GUI steps (upload, publish) wait for `HIDIdleTime`: the owner often uses the Mac meanwhile.

### Added 2026-10-03 (night) - UI overhaul, first pass (concepts in `artifacts/ui-concepts-20261003/`)

Owner's decision: direction A's layout for the shop, direction B (found footage) for the gameplay HUD, C's type
weight and button size on phones, no noise meter.

- **Shop is a card grid on every tier** (`SHOP_GRID_20261003` in ZyntraStore): art tile, name, price chip per card;
  ONE detail pane (`ShopDetail`) with the description and the only purchase button (`DetailBuy`). The pane is beside
  the grid at `ContentWidth >= 500` and under it on a portrait phone, and has a compact layout (short = under
  150px tall drops the kind and price lines). The card's `Buy` chip still exists and is still the card's tagged
  action (the fit matrix requires one per card) but SELECTS while `shopDetail.PaneOpen`; `ProductDescription` is
  hidden on the card. `ZyntraShopBuy` / `productPurchase` are unchanged.
- **Equipment is a four-slot hotbar on pointer devices** (`HOTBAR_20261003` in ProtectionHUD): shield Q, potion T,
  marker X, detector Z as slots in a strip at the list's old anchor (x98, 92px up); unowned items still do not
  draw. Touch keeps the control-plan slots, with a 12px label where the slot is 56px or wider.
- **`StarterPlayerScripts."Found Footage HUD"`** (new script, created from the command bar): `FoundFootageHUD`
  (DisplayOrder 4, on while `InRound`) draws 1px corner brackets 4px inside the safe area and, on pointer
  devices, a REC dot with the round's timecode (steady under `ReduceFlashing`); and it renders EVERY
  ProximityPrompt as a plate next to its object (`InteractionPrompt` BillboardGui in PlayerGui: key, action,
  object, hold bar; a press on the plate holds the prompt, which is how touch uses it). It sets
  `Style = Custom` client-side on every prompt and only draws what `PromptShown` reports, so per-prompt
  `Enabled` and `ProximityPromptService.Enabled` are obeyed.
- **UIRegression's overlap scan counts every visible frame more than 1px in both directions**, including ones in
  a new ScreenGui: the first brackets (2px, overlapping at the corner and crossing the torch gauge) failed the
  `party-down-card` scenario. Decorative rules are 1px.
- **Run the suite from a Client `execute_luau`**: `require(ReplicatedStorage.UIRegression).RunAllSummary(3000)`
  (about 220 s; calls that long do return) or `.Compact("ZyntraTerminalFitMatrix")`. Device fixtures are
  `workspace.UIRegressionViewport` (Vector2) + `ForceTouchUI`; the store probe is
  `PlayerGui.ZyntraStore.UIRegressionZyntraStoreProbe:Invoke("open" | "tab:Shop" | "relayout" | "close")`.
  Baseline on 2026-10-03: 2836 checks, 2 failing in `ExclusionTimingMatrix` (terminal / dev phone "takes the
  reader down within 2 heartbeats"); they fail on the previous ZyntraStore too.
- Not done in this pass: the objective panels, stamina bar and torch gauge keep their green look (they draw from
  `ReplicatedStorage.UIStyle`, which the lobby UIs share); no REC mark on touch.
- `tools/mac_pull_from_studio.py` / `tools/mac_push_script.py` are the Mac-side sync (the Windows bridge tools
  do not run here); the push refuses when Studio holds neither HEAD's nor the working copy's byte length.

### Added 2026-10-03 (late night) - Level 6 deaths follow the round death flow

- **A Level 6 death keeps the player in the level.** The catch ends the kill cam with `Health = 0`;
  `Session:playerDied` (hooked on every humanoid, so a reset counts too) fires GameManager's own `RoundStatus`
  words to the level's players: `"death"`, `"partydown", 15, name` when nobody is left, `"partydownclear"`,
  `"reentry"`. RoundUI's PARTY DOWN card, the death advice and the spectate band therefore behave as in Level 1.
  `wipeWindow` holds the session for 15 s; without a re-entry `finish` sends everyone home (`Runtime.Leave`
  fires `"lobby"`).
- **Emergency Re-entry reaches Level 6 through GameManager's idle `ZyntraReentry.OnInvoke`** (all six idle
  assignments delegate to `ServerStorage.Level6Reentry` for a player with `Level6PlaygroundPreview`); the paid
  path, its credit reservation and refund in ZyntraMonetization are unchanged. `Session:reenter` loads the round
  body, stands it at `Level6Exit` (the entrance), gives `ReentryGraceSeconds` 8 and sets `ZyntraReentryUsed`.
- **`workspace.RoundActive` must stay false on the lobby server**: Daily Rewards and the Lucky Wheel close on
  it, the Friend Boost chip hides, and RoundUI's Mimic loop keys on it. Every gate that needed it for Level 6
  accepts the player attribute instead (`tools/level6_playground/make_death_parity.py`: SpectateController,
  ZyntraStore `updateReentry`, RoundUI `pd.refresh`, Round Exit Client, ZyntraMonetization `reentryEligible`,
  GameManager's Died handler). Spectating in Level 6 only lists players who are in Level 6.
- `Remotes.RoundStatus "leaveround"` from a Level 6 player is answered by Level6PreviewAccess (`leaveack`, then
  the lobby).
- **The song is one non-positional track** (`MUSIC_ON_HORNS = false`): copies on several horns sounded like an echo.
- **`l6_chase_shriek` (134572728354839) is not approved by Roblox** ("Asset is not approved for the requester");
  the client preloads the six effects once and treats a refused one as missing, so the old spotted sting plays.

### Added 2026-10-04 - Level 5 is the void rooms

- **`Workspace."Level 5 Quiet Suburbs"` is removed** (owner, 2026-10-03; re-importable from `tools/level5_import/`).
  **Level 5 is `Workspace."Level 5 Void"`**: five single-colour rooms in a row (Rose, Blue, Amber, Mint, Violet) over
  a black drop, joined by dark corridors, 1160 studs long at x=40000, y=600. Built by
  `Blender -b --python tools/level5_void/build_level5.py` (saves `artifacts/level5-void-20261003/blend/Level5_Void.blend`
  and `build/level5.json`), imported as native Parts by `tools/level5_void/import_level5.py`. Still developer-only
  through `Level5PreviewAccess` (now `MODEL_NAME = "Level 5 Void"`); the lobby's Level 5 bay is untouched.
- **Jumps are computed against the real body**: walk 16, JumpPower 50, gravity 196.2, flat reach 8.15 studs
  (`reach(dy)`). Every gap is asserted to be a capped share of that (Blue up to 61%, Amber 71%, Mint 74%, Violet
  72% with drops), paths are asserted to stay inside their room and clear of the wall folds, and a scripted player
  walked the whole route at walking speed: 23 of 23 jumps (the client snippet reads `model.Route`).
- **Never start a jump from a descending stair**: the body is airborne half the time on the way down steps and a
  jump pressed in the air does nothing. Violet's gaps each have a flat take-off tread and a flat landing tread.
- **Lighting**: `StarterPlayerScripts."Level 5 Lighting Controller"` (took over the obsolete, disabled
  `Level 6 Mall Manager Visual Smoother`) removes sky and atmosphere inside the model's bounds and sets
  `Level5LightingOwned`, which RoundUI stands down on. The rooms are lit only by PointLights at walkway height and
  above (brightness 0.2, two rows near the middle, one row under the ceiling); brightness 1 blew out to white.
  Nothing lights the walls below, which is what makes the drop black.
- **A fall is not a death**: Level5PreviewAccess stands a body that drops 45 studs below a section's lowest
  walkway back up at that section's entrance (`model.Checkpoints`), and `Level5Finish` (the lit doorway at the
  bottom of Violet) returns the player to the lobby spawn.

### Added 2026-10-04 - Level 5 Void published, lobby furniture collides (v2621)

- **Level 5 is `Workspace."Level 5 Void"`** (x=40000, y=600; five colour rooms over a black drop), built in Blender
  by `tools/level5_void/build_level5.py` and imported by `import_level5.py`. The build asserts every gap against
  the flat jump reach (8.15 studs at WalkSpeed 16 / JumpPower 50) and never starts a jump from a descending stair.
  Developer-only through `Level5PreviewAccess`; no entity; the lobby's Level 5 bay is untouched.
- **Lobby furniture collides** (`LOBBY_COLLISION_20261004` at the end of `LobbyReimaginedPreview.Builder`):
  `BayDecorLevel4`, `Reference End Furniture Piles` and `Theme Furniture` get `CanCollide` (Box fidelity, 239
  parts), and the cinema seat row moves 1.5 studs toward its bay centre so its corners (28.89 from centre) no
  longer show through the round wall (inner radius 27.84). The atlas decor of the Level 3/5/6 bays, the
  `EntryConnector` and the Level 6 bay boards are single atlas meshes and still have no collision.

### Added 2026-10-04 (later) - Level 5 v2, public; Levels 4 and 5 open to everyone (v2627)

- **Level 5 Void v2**: 2922 studs, 81 jumps (v1: 1160 / 23), caps per room in `SHARE` (Rose 50%, Blue 64%, Amber 74%,
  Mint 80%, Violet 86% of the walking reach). Walked in Studio at walking speed in the round body: 81 of 81.
  **Nothing floats**: every walkable piece is the top of a block that runs to `BOTTOM` (`solid`), so the route may
  never cross itself in plan (`no_crossing`); lamps hang on rods; loose `Monolith`s are non-colliding (a body that
  landed on one was stranded). `mirror=-1` on a room lays it mirrored when its zig-zag drifts into a wall.
- **Plaster with a bump map**: `MaterialService."L5 Void Plaster"` (base Plaster; colour/normal/roughness PNGs made in
  the Blender build, ids in `tools/level5_void/texture_ids.json`). Part Color tints the near-white colour map.
- **Level 5 is a live level on the lobby server, like Level 6.** `Level5PreviewAccess` (`Void.Join/Suit/Leave`) puts
  the player in the round body and sets `Level5VoidRound` NEXT TO the shared `Level6PlaygroundPreview` marker (every
  off-GameManager round feature keys on that). The Level 6 client excludes `Level5VoidRound`; SoundController gives
  Level 5 the round footsteps. Either script may answer `leaveround`; the other finds it done.
- **Plates**: the door out of a room opens while every member of a PARTY (one queue launch) who has not passed it
  stands on the room's plate; the plate's radius is 3.2 + 0.9 per player in the room. Gate sinks 13.4 studs, holds 8 s.
- **Checkpoints** are the wide landings (`model.Checkpoints`, 19, route order); a fall (40 below the stretch after the
  last checkpoint) or a Reset stands the body back on it. **Balls** are unanchored (density 0.35); one that leaves its
  ledge is anchored 1.6 s later, still far above `FallenPartsDestroyHeight` (-500 deletes it for good: at 5 s it was
  already gone), and put back on `Home` after 35 s.
- **Sounds**: 15 ElevenLabs clips (`assets/level5-void-20261004/`, ids in `sound_ids.json`, installed by
  `install_sounds.py` into `ReplicatedStorage.Level5Void.Sounds`). Server plays plate/gate/ball-fall on the parts;
  the Level 5 Lighting Controller plays the listener's own (room tone, wind, fall, rolling balls, beam creak).
- **`hum.Jump = true` from `execute_luau` does nothing on a player-controlled round body** (the control module
  writes Jump every frame); a scripted walker uses `ChangeState(Jumping)`. Lighting needs several seconds to settle
  after a camera jump under streaming: a screenshot taken sooner is black.
- **Lobby Level 5 bay** is a small void room (`LEVEL5_BAY_20261004` in Builder; set generated by
  `tools/level5_void/build_bay.py`): five-colour plaster lining, black floor, the stair to the lit doorway. The suburb
  house fronts are hidden (Transparency 1), the sofa/bench/carpet props removed from `LobbyPolishBays`.
- **Every level is public**: `DevAccess.Level4Public/Level5Public/Level6Public` and `LEVEL4_PUBLIC = true` in
  GameManager (a non-developer hosts the real Level 4 round with CREATE PARTY; the Level 4 MAP PREVIEW stays a
  developer tool). No developer wording is left in the new lobby. The old `ServerLobby` (not reachable by players)
  still carries its COMING SOON boards; it was not touched.
- **Level 5 has its own steps and random ambience (2026-10-04, v-next after 2627)**: `l5_steps_walk` / `l5_steps_run`
  loops and `l5_land` in the Level 5 Lighting Controller (`FOOTSTEPS_20261004`; run = WalkSpeed over 20, silent in the
  air), so SoundController's round footsteps exclude Level 5 again. `AMBIENT_20261004` plays one of ten `l5_amb_*`
  one-shots every 14-34 s from a random point 45-115 studs from the listener. 28 sounds in `sound_ids.json`.

### Added 2026-10-04 (night run, v2632)

- **Level 5 has a sixth room, Coral: the shaft.** A 140-stud square well with nothing in the middle; the stair climbs
  once round its four walls (14 jumps, cap 88%, most with a rise) to the lit doorway above the door you came in by.
  `close(..., shaft=True)` skips the folds/monoliths and hangs the lamps along the route. Violet now ends in a plate
  and gate like the others (5 plates, 25 checkpoints, 95 jumps, 3108 studs). No entity in Level 5 (owner decision).
- **Level 5 footsteps are single recorded steps** (`l5_step_1..6`, `l5_stepr_1..4`), one per stride covered on the
  ground (6.4 studs walking, 7.8 running), never the same twice running. The owner rejected the looped version.
- **Lobby (Builder)**: `LOBBY_COLLISION_20261004b` makes the DJ console, speaker towers, subwoofers, stage rail and
  the loose office furniture solid; `END_PILES_20261004` clones every end-pile piece twice more, higher and further
  back (438 non-colliding parts), so no wall shows behind the piles; `BAY_DRESSING_20261004` dresses bay 5 (void
  room) and bay 4 (synthwave cinema foyer: navy lining, cyan/magenta neon bands, NOW SHOWING marquee, poster
  cases, rope posts) from the sets `tools/level5_void/build_bay.py` writes between the `LEVELn_BAY_SET` markers.
- **Lobby DJ** (`ServerScriptService."Lobby DJ"`, `StarterPlayerScripts."Lobby DJ Client"`; they took over the retired
  `Level4RenovationBoot` and `Level 6 Table Hiding Client`): E at the console opens the booth for
  `DevAccess.IsLevel6PreviewAllowed`. Five tracks (`assets/lobby-dj-20261004`), published as workspace attributes
  `LobbyDJTrack` / `LobbyDJStartedAt` / `LobbyDJTracks`; every client plays the track itself, in step, only in the
  lobby and only with its own lobby music on, and silences the `ZyntraLobbyMusic` group meanwhile. DJ MODE stands
  the caller behind the console and welds a headset to the Head (server); the pose is done on EVERY CLIENT for
  whoever carries `LobbyDJMode`: in `RunService.Stepped` each limb joint's `Transform` is turned a little further
  (no animation assets). Current avatars have `AnimationConstraint` joints, not Motor6D; a server-side C0 or
  attachment change, and Attachment0/Attachment1 edits, do not move such a limb. Transform in Stepped does.
- **Welcome card**: `First Entry Guide` (was empty) shows one card to a first-time player (`ZyntraFirstLogin`) after
  the briefing has finished typing: three steps, device-specific controls, the two-person-team line.
  `workspace.DevShowWelcome = true` shows it in Studio.
- **Loading screen** holds for textures: after the preload it waits for `ContentProvider.RequestQueueSize == 0` for
  1.2 s (cap 5 s) plus 1 s (`TEXTURE_SETTLE_20261004`).
- **Bug run, Level 6**: caught -> kill cam -> PARTY DOWN -> lobby, and post -> exit beacon (`L6_Anchor_Exit`, not
  `Level6Exit`) -> LEVEL 6 CLEARED -> lobby, both clean in one session, console clean.
- **Gallery**: `artifacts/gallery-20261004/` holds the competitor research and the raw in-game captures of all six
  levels; the finished 1920x1080 images are in `~/Desktop/Backrooms Stay Quiet - Gallery/`. `/tmp/shots.sh`-style
  capture needs the luau and the shell to agree on a wall-clock time (`DateTime.now()`), not on a sleep.
- **Lobby party lights** (`PARTY_LIGHTS_20261004` in Lobby DJ Client): while `LobbyDJTrack` is on, every Light in the
  lobby model takes a colour from the track's palette and the pattern steps every second beat of the track's `Bpm`
  (in the server's TRACKS), counted from `LobbyDJStartedAt`; brightness swells on the beat. Colours glide, and
  `ReduceFlashing` slows it to one step per eight beats with no pulse. Stopping restores every lamp exactly.

### Added 2026-10-04 (late night)

- **Level 6 Dev ESP** (`StarterPlayerScripts."Level 6 Dev ESP"`; took over the dead `Level 2 Pool Slide Dev ESP`): for
  `DevAccess.IsLevel6PreviewAllowed`, an always-on-top outline and a name/distance label on the Counter and on every
  other player in Level 6. Follows `DevEspEnabled` (the terminal's ESP switch); K toggles it inside the level.
- **Tunnel ends** (`END_PILES_20261004b`): a grid over the whole arch behind each pile (400 clones, two layers), not a
  taller mound. The first version left the wall showing at the sides.
- **Level 6 party easter egg** (`PARTY_20261004` in the game module): a small red button on the floor behind a
  counter (`L6_Hide_counter_05`). Pressed while it is searching (once per session, not during a chase): every living
  player is stood round the table of the dark party room (x -193), the door is shut, a disco ball with coloured
  spots turns, "Hands Up Arcade" plays and the Counter breakdances on the table for 30 s (`Dance_Toprock`,
  `Windmill`, `Headspin`, `Freeze`, `Finale`: `tools/level6_entity/build_dance.py`, procedural, same clip format,
  with a `hips` track). Then everyone and the doll are put back and the search resumes on the same second.
  **Every deadline in the module reads `clock()`**, which stands still during the party; loops that move the doll
  or look for players call `Session:hold()`. Use `realClock()` for anything that must run during it.
- **Level 4 bay posters**: four generated one-sheets (`assets/lobby-posters-20261004`), two standing in front of the
  decor mesh's own poster texture, two by the entrance; `img` rows in the bay set become a Decal plus a picture light.
- **Level 5 audio**: the two always-on beds were denoised (`*_clean.mp3`, 17.6 dB and 28.6 dB less energy above
  6 kHz) and replace the originals under the same keys; eight darker `l5_amb_*` one-shots joined the random set (18).
- **Level 5 doors carry no counter** (owner, 2026-10-04): only the first room's door says EVERYONE ON THE PLATE; the plates still scale with the players.

### Added 2026-10-04 - Achievements

- **An achievement is a key of `ZyntraConfig.Badges`**; the display list (name, text, icon, `Secret`) is
  `ZyntraConfig.Achievements` (20). ZyntraMonetization records unlocks in the profile field `Achievements`
  (`achievementApi.unlock`), publishes them as the replicated player attribute `ZyntraAchievements` (comma-joined
  keys) and then tries the Roblox badge, which does nothing while the key's id is 0. `AwardedBadges` stays the
  narrower record of badges really handed out; a badge created later is awarded on the player's next join.
  Old profiles get what they had already earned (badges held, levels cleared) at load.
- **Other server scripts unlock with `ServerStorage.ZyntraAchievement:Fire(player, key)`** (a BindableEvent: no
  client can reach it). Level5PreviewAccess and the Level 6 game module report through it.
- **`StarterPlayerScripts."Achievements Client"`** (took over the disabled `Level 6 Lighting Controller`): unlock
  toast, a BADGES button under the lobby's left rail and the panel. Its ScreenGui respects the top inset, so
  "off screen" for the toast is y -170, not -90.
- **Badge art is drawn, not generated**: `tools/badges/build_badges.py` writes flat SVG pictograms in the store
  icons' palette (#161D20 ground; cream F3ECDA, teal 4FADAA, amber EDA827, coral F2725D) and renders them with
  headless Chrome to `assets/badges/icons-512` and `~/Desktop/Backrooms Stay Quiet - Badges`. The owner rejected
  a generated set as AI slop; keep new badges in this style.
- **Still to do by hand**: the 16 new Roblox badges have to be created on the Creator Dashboard (5 free per day,
  then 100 Robux each) and their ids pasted over the 0s in `Badges`.
- **Level 6, 2026-10-04 (owner corrections)**: the level is won over `RoundsToWin = 3` searches in each of which every
  living player touches the post (`self.wins`, model attributes `Level6Wins` / `Level6WinsNeeded`, event
  `roundwon`; a completed search that is not the third ends as `alldunked` and it counts again). One search had
  been enough since the target became "all alive": that was a regression. The music is on the PA horns again
  (`MUSIC_ON_HORNS = true`): the plain track is a silent clock, copies are resynced past 0.05 s, horn volume is
  `HORN_VOLUME * GENERAL * MUSIC`, and the reversed tape plays at `REVERSED_GAIN` 2.2. The red finale light swells
  and goes dark for about a quarter of each 3.6 s cycle (halved dip under `ReduceFlashing`).
- **Level 5 hanging lamps dimmed** (owner, 2026-10-04: "blinding"): a 3-stud dull grey neon globe (was 5, white) and a PointLight of 0.45 over 30 studs (was 2.6 over 46). The room lighting itself is unchanged.
- **Tunnel-end furniture removed** (owner, 2026-10-04, `END_PILES_REMOVED_20261004` in Builder): both EndBlockades piles (219 MeshParts), the 400-piece fill and the loose office furniture at the south end are destroyed at build time (652 parts; the lobby went from about 2800 to 2149 BaseParts). The stage, speakers and DJ console stay; the end walls are bare. EndBlockades still runs and its folder is kept empty.

### Added 2026-10-04 (afternoon) - Level 5 smooth again, plate, party button ESP

- **Level 5 is SmoothPlastic again** (owner: "forget this bump map"): `part()` defaults to SmoothPlastic, the importer
  maps any Plaster row to SmoothPlastic and no longer sets `MaterialVariant`, Builder's bay 5 pieces do the same.
  `MaterialService."L5 Void Plaster"` and `texture_ids.json` still exist but nothing uses them.
- **A Level 5 plate only goes down (and sounds) when a whole party stands on it**: `movePlate(record, radius,
  complete, complete)`. One of several players standing on it changes nothing visible.
- **Level 6 Dev ESP also marks `L6PartyButton`** (yellow, "PARTY BUTTON"). The button is at model-local (-3, -150):
  on the floor behind `L6_Hide_counter_05`, on the arcade carpet, the far side of the hall from the entrance.
- **The DJ booth lists every track the server publishes** (`TRACK_LIST_20261004`: a ScrollingFrame, rows made on
  demand), no longer five fixed rows.
- **GUI automation must guard every keystroke, not only the clicks.** On 2026-10-04 an upload ran while the owner
  was in Discord and the Roblox player: `gk.sh` aborted, the bare `osascript` keystrokes did not. `HIDIdleTime` is
  not enough either (a spectating player is idle). `/tmp/dj_upload.sh` shows the guarded form: check the front
  process before each step and wait while `RobloxPlayer` is in front.
- **Lobby DJ has eight tracks** (2026-10-04): Electric Blue 131426415207915 / 128 bpm, Round the Planet
  87330961422570 / 132, Plastic Roses 136491273182208 / 138 joined the five (`dj_eurodance_3..5.mp3`).
- **The Mac may be on the 2560x1440 display**: the Asset Manager click positions in older notes were for the
  smaller screen. Set the Studio window to {0,25} full size, take a screenshot and read positions from it
  (screenshot pixels x 1.829 = points at 1400 px wide).
- **Level 6's exit phase has no time limit** (owner, 2026-10-04): `EscapeSeconds` and the "anyone still inside
  made it too" block are gone. After the third search the level is cleared only by reaching the exit beacon; the
  phase ends when every standing player is out or caught (or the party-down window runs out).
- **Prompt plates fill a ring, not a bar** (`HOLD_RING_20261004` in Found Footage HUD): the key is a round badge;
  `Plate.Hold` holds a dim circle and two clipped half-windows (`First`, `Second`) whose UIStroke carries a
  UIGradient that is rotated (0..180, then 180..360). Keep the ring's size even or the halves show a seam.
- **Level 5 has no checkpoints; a fall is a death** (owner, 2026-10-04, supersedes the "a fall is not a death"
  notes above). A body 40 studs below its stretch gets `Health = 0`; any death (a Reset too) fires `"died"` to
  the client (black cover, YOU FELL) and `Void.Leave` returns the player to the lobby 3 s later. `model.Checkpoints`
  and `record.cp` remain only to know which room a player has reached (plates, room names); `"checkpoint"` is sent
  for a new room only. There is no spectating or re-entry in Level 5.
- **Roblox badges, 2026-10-04**: the four old badges were renamed and re-pictured in place (Office Hours, Out of
  the Deep End, Party's Over, Three Doors Down) and five were created free: FirstClearLevel4 1275875713593023,
  FirstClearLevel5 174274361107994, FirstClearLevel6 2830428358398761, AllSix 2321372450692958, Welcome
  1036919688053942. Eleven keys are still 0 (BetterTogether, L5*, L6*). Creation on the dashboard has NO price
  confirmation: it is free for the first five per day and otherwise charges 100 Robux silently, so create at most
  five a day unless the owner approves the spend. Done through `codex exec --enable computer_use`.
- **Level 6 party rooms rebuilt** (`PARTY_TABLES_20261004` in `build_playground.py`): a two-tier cake with
  candles, a plate and cup per seat, real chairs (seat, back, legs). The dark room 3, where the easter egg's doll
  dances, has a completely clear table top, its cake on a side table by the wall and no chairs (the party stands
  its players there). `import_to_studio.py --only <Group>` rebuilds one group's parts in the live model and
  leaves the rest alone; check first that the export differs only in that group.
- **No RETURN TO LOBBY prompt at the Level 6 start** (owner, 2026-10-04): `hookExit` still mounts the prompt (the
  queue's `ready` check needs it present and Enabled) but sets `MaxActivationDistance = 0`. The `HOLD L - LOBBY`
  chip of Round Exit Client is untouched.

### Added 2026-10-04 (evening) - Level 6 kill cam: the choke

- **`Choke` clip** (`tools/level6_entity/build_choke.py`, 5 s, not looping): both hands to the throat, lift, then
  the elbows fold and the body leans in. `Session:catch` plays it (`CaughtReturnDelay` 5.0, `GrabDistance` 2.7)
  and lifts and draws in the anchored victim for onlookers. The client's `killCam` (`KILL_CHOKE_20261004`) hangs
  the camera on the two hand bones (0.62 above, 1.0 -> 0.4 behind), looking at the face; sight dims in pulses
  and is black from 4.7 s; the body dies at 5.0. The marker, the exit chip, the REC frame and the dev ESP stand
  down for it, and the `L6Caught` achievement fires after the death so its toast is not over the face.
- **`Session:follow` rechecks `interrupt` after its Heartbeat wait.** Before, a catch that landed during the wait
  was followed by one more step: the doll moved off the spot `catch` put it on and `Run_Chase` replaced the grab
  pose, so every catch that ended a chase (all of them, since "seen = dead") played the kill in the running pose.
- **ZyntraMonetization's late badge award** called the local `awardBadge` 800 lines above its definition (nil at
  that point: "attempt to call a nil value" on every profile load with achievements). It goes through
  `achievementApi.award` now.
- **Studio crashed once on 2026-10-04** (`RBXCRASH` in the log); it reopens on the place with
  `open "roblox-studio:1+launchmode:edit+task:EditPlace+placeId:131311258779917+universeId:10559217407"` and
  comes back with a NEW MCP studio id (`list_roblox_studios`). An `execute_luau` call that is still running
  when a script switches the camera to Scriptable gets the camera type reset when the call ends.
- **Timed screenshots**: `screencapture -R x,y,w,h` of just the viewport takes about 0.4 s; the full 2560x1440
  screen takes about 2 s, too slow to catch a 5 s sequence.

### Added 2026-10-05 - Level 5 v3: harder, ten rooms

- **Every existing room is harder**: caps (`SHARE`) rose 62%, blue 74%, amber 82%, mint 87%, violet 90%, coral 92% of
  the walking reach, every gap longer (`LONGER`) and every ledge narrower (`WIDER`, beams never under 2 studs).
  Plazas keep their size (`'Plaza'`).
- **Coral is a pass-through room now** (west wall, north wall, half the east side, to a ledge and door high in the
  east wall), and four rooms follow, each a different shape:
  **ORANGE** the double spiral (one arm in to an island, its twin out again, climbing all the way; spaced by arc
  length, not by angle, or the middle knots up), **CRIMSON** the ring (17 single blocks half round a 60-stud
  pillar, up and down; the other half of the ring is there with a piece missing), **TEAL** the field (only the
  tops of 2.8-stud pillars, `dense=3` monoliths around them), **IVORY** the tower (a stair fixed to a column,
  three times round, three treads missing in every six; `STACKED` exempts it from `no_crossing`; the finish is
  the doorway in the column at the top). 10 rooms, 9 plates, 4130 studs, 171 jumps.
- **Walked at walking speed, 171 of 171**: `python3 tools/level5_void/run_walk.py rose blue ...` runs
  `walker.luau` one room per call (a call longer than about two minutes answers "Request timeout" but keeps
  running). Rooms must be walked in order in one life: the server kills a body 40 studs under the lowest point
  of the room it last reached. `Humanoid:MoveTo` stops about a stud short of its target, so the walker's arrival
  tolerance is 1.25 studs (0.75 produced timeouts that looked like stuck steps).
- Server `SECTION` and the client's `NAMES` list the four new rooms; nothing else in the scripts changed.
- **The DJ end is real tunnel now** (`TUNNEL_BEYOND_20261005`, owner: the picture "doesn't work"): the flat
  `TunnelBeyond` image is gone. The end wall (`EndBackstop` at the DJ end) is hidden and the lobby's last 40-stud
  section (PlainShell, ArchRib, CableTray, ConduitSection, Fluorescent, RoadSection, SidewalkSection) is cloned
  five times beyond it (`Beyond*`, 90 parts, no collision, no shadows, lights removed); six black sheets
  (`BeyondDark`, transparency 0.82 down to 0.14) take it to nothing and `BeyondEnd` caps it at 176 studs. A flat
  image only lines up from one spot; from the stage it read as a poster. The fence and signs are unchanged.

### Added 2026-10-05 (later) - Level 5 finish screen, open rooms, things falling; lobby ends seen in play

- **Level 5 ends on RoundUI's LEVEL CLEARED screen**: at the finish the server fires `RoundStatus "win", seconds,
  done, total` (the party is one queue launch: `group.total` / `group.done`; `began` on the member record) and
  leaves 7 s later. No serial, so the screen has no buttons. RoundUI says 5 for a player with `Level5VoidRound`
  (SelectedLevel is 1 on the lobby server).
- **Only Rose, Blue and Amber have a ceiling** (`ROOFED` in build_level5.py). The other rooms' walls carry on
  `RISE` 320 studs with no ceiling part and no top lamp row; the crimson pillar and the ivory column go up too.
- **Things fall** (`FALLING_20261005` in the Level 5 Lighting Controller, local parts in `workspace.Level5Falling`):
  a block, slab or ball about every 12 s and a hazmat body about once a minute, never within 12 studs of the
  route, from under the ceiling in a roofed room and from 190 studs up elsewhere. What and where is drawn from
  `Random.new(slot * 977 + cell * 31)` (2 s slots of server time, 60-stud cells), so players standing together
  see the same fall. The body's sound is one of `l5_player_fall` and `l5_fall_scream_1..6` (ElevenLabs,
  `assets/level5-void-20261005`, ids in sound_ids.json), on the body, InverseTapered 26..420, faded in over 0.5 s
  and out from 3 s, pitch sliding down; `l5_debris_whoosh` on large debris.
- **A closed mesh shell is black under Realistic lighting without lamps inside it.** The lobby's tunnel extension
  showed nothing until the lobby's own lamps (`PreviewLighting`, last section) were cloned with it, weaker each
  section (`FADE` 0.8 .. 0.05); the black sheets now start 70 studs in and the cap is at 190.
- **Arrival gate force field**: Transparency 0.62, SurfaceLight 0.32 (0.25 was a solid mint wall, 0.82 invisible).
- **With the owner's go-ahead the Mac's screen is usable**: `screencapture -x -R 2,176,1412,572` is the Studio
  viewport on the 1440x900 display with the window at {0,25,1440,821}; Asset Manager: tab (46,761), Import
  (1380,601), a file in the dialog (477,236), Start Import (1364,319), Confirm (819,597), close (1401,289) and
  (1401,571).

### Added 2026-10-05 (morning) - Level 5 fall screams cleaned and turned down (v2704)

- **Owner: the screams were "a little too loud and have that ai static".** The six ElevenLabs screams and the
  level's fall rush were re-uploaded cleaned; the ids sit under the ORIGINAL keys in `sound_ids.json`
  (`l5_fall_scream_1..6`, `l5_player_fall`), so no script names changed. Sources and `*_clean.mp3` are side by
  side in `assets/level5-void-20261005` (the rush in `...20261004`).
- **What the static was, measured**: a hiss band from about 5 kHz to the MP3 edge where the voice has nothing, and
  noise BETWEEN the voice's harmonics that rises and falls with it (a tenth to almost half of the 2-5 kHz energy
  in screams 3, 4 and 6). A fixed noise print (`afftdn`) cannot take the second kind.
  `assets/level5-void-20261005/audio-engineering/clean_screams.py` does: mono, a per-frame gate that turns
  whatever does not stand clear of the local floor down 12 dB, a steep low-pass at 4.8 kHz, -18 LUFS. Above
  6 kHz the screams went from about -48 to -88 dBFS. It needs numpy; the only one on this Mac is Blender's
  (`/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13`).
- **Run generated audio through a cleaner BEFORE uploading it.** This is the second time the owner heard static in
  raw ElevenLabs output (the Level 5 beds on 2026-10-04 were the first).
- **Level**: a falling body peaks at 1.1 for a scream (was 1.6; `thing.loud`), and the files are 2 dB lower, so
  about 5.5 dB quieter in all. The rush is a far quieter recording (-26 LUFS) and keeps 1.6 and its loudness.
- **A mono file reads 3 LU lower than the same sound in stereo**: measure with `ebur128=dualmono=true`, or a
  "-18 LUFS" mono file comes out 3 dB louder than meant.
- **ffmpeg cannot replace a file in place from a session's shell here** ("Operation not permitted" on the second
  write); delete the output first. New files and deletes are fine.
- **Nobody but the owner has heard the result**: a session cannot listen. It was checked by band measurements,
  before/after spectrograms, a look at what the gate removed (noise only, no harmonic lines) and a play test in
  which a body fell with the new `l5_fall_scream_1` at peak volume 1.10.
- **A person-fall can be predicted for a test**: `Random.new(slot * 977 + cell * 31):NextNumber() < 0.03` for
  `slot = floor(GetServerTimeNow() / 2)` and the rose room's cells 0..13; stand on a route point of that cell
  before the slot starts and read the Sound under `workspace.Level5Falling`.

### Added 2026-10-05 (midday) - Level 3 finale: the Manager starts at the hall's entrance (v2706)

- **Owner: "he spawns in the end and make the level impossible to complete".** Since the 2026-10-02 rebuild the
  finale Manager was placed on the exit hall's `EndPoint`: the Exit-room mouth, between the runners and the
  freight door, coming at them at 28 in a 14-stud tunnel. The hall runs from the Signal Hall's false wall
  (`StartPoint`) 560 studs to the Exit room (`EndPoint`); the escape sensor is another 53 studs on.
- **Now**: one fixed marker at `Configuration.MallManager.FinalHallSpawnProgress` = .02, 11.2 studs inside the
  entrance (clear of the false wall, which is still solid at 0 and 6 studs until the exit unlocks). The builder
  reads the config and asserts the marker is behind `FinalHallHalfwayProgress`; `chooseFinalHallSpawn` lerps to
  `hall.SpawnProgress`. The trigger (every living survivor past 50%) and the speed (`FinaleApproachSpeed` 28,
  against walk 16 and sprint 26) are unchanged. This supersedes the 2026-09-14 note above (spawn at the level
  entry); that design went with the rebuild.
- **Measured in a Studio round** (five real pickups, insertion, then walking across the halfway line at 16 and
  never sprinting): the Manager appeared 270 studs behind, the gap went 275 -> 56 over 20 s and the player
  reached the sensor with about 33 studs in hand; LEVEL 3 CLEARED. Walking is enough, stopping is not. Not
  tested: a runner who is caught, and more than one player.
- **`Level 3 Test Suite.ValidateConfiguration()` passes again**: it had asserted `.40` against a config of `.97`
  since the rebuild. The suite cannot be required in Edit (`PlayerProtection` insists on the server); call it
  from a play session's Server datamodel.
- **Driving a Level 3 round from `execute_luau`**: Client `Remotes.ConfigureQueue:FireServer(queueId, 1,
  "public", "normal")` on the Level 3 zone starts the round in Studio. Pick up a CD by standing 3.5 studs beside
  it, a Scriptable camera on it, then `prompt:InputHoldBegin()` / `InputHoldEnd()`; the disc player the same way.
  Do NOT anchor the root for this: the server never sees the move and refuses the prompt.

### Added 2026-10-05 (afternoon) - Level 5: red spiral, tower, the closing corridor, choices at the finish (v2712)

- **Doors stay down** (owner): a plate's gate is `locked` once a party has opened it and comes back up only when
  `members` is empty, so the next party finds every door shut. Two parties in the level at once share open doors.
- **Dev fall** (owner: "dev button that triggers a fall and scream"): `Level5VoidHud.DevFall` (top right) and the
  O key, for `DevAccess.IsLevel6PreviewAllowed` (the owner's account, ZenMeister02, is NOT on `IsAllowed`, so it
  has no DevCheats and no DEV tab). The client only asks (`Event "devfall"`); the server tells every member, so all
  see the same body. Every second serial is aimed at a pillar. The terminal also has a `level5Fall` row
  (`LiveAttribute`: a live level cannot be recognised by `SelectedLevel`/`RoundActive`).
- **Pillar hits** (`PILLAR_HIT_20261005`, client): about 45% of bodies, where a loose `Monolith` stands near, land
  on its top: the scream stops, `land()` bounces it over the side that faces away from the path, and it falls on
  limp (each limb trails the velocity). All kinematic and seeded: nothing collides. `pathGap` measures to the
  route's SEGMENTS; the old test measured to its points and missed the middle of a long ledge.
- **`spiral()` in build_level5.py**: a stair fixed to a round column. It asserts every gap edge to edge against
  the room's cap and 15 studs between a tread and the turn above. A wide tread on a tight column fans out, so
  each box is long enough to meet its neighbour at the OUTER edge. Anything solid to the bottom (a `plat`, a
  `plaza`) would cut through the lower turns: the bridge off a spiral is a plain part.
- **CRIMSON** is the spiral: 4.5 turns round the great pillar, +131 studs, 25 jumps (93%). **IVORY** is the tower:
  7.5 turns, treads 10 wide at the foot and 2.2 at the top, steps of 1.25, +151 studs, 19 jumps; the column's top
  is the platform, a pier leads to a 14 x 16 doorway. Walked at walking speed: crimson 25/25, ivory 19/19. The
  first seven rooms are byte-identical and TEAL only moved (-28.8 x, +131 y).
- **THE CORRIDOR** (`FINALE_20261005`): 226 studs, 26 wide, beyond the tower's east wall. The map carries
  `Finale` (`CrusherWall` x2 with `Side`, `CrusherBlock` hidden in the wall over the doorway, `CrusherGate` 28 studs
  in), `FinaleData` (JSON, relative to `Origin`), `Level5Reentry`, lamps named `CrusherLight`. The server's
  `runCrusher` starts when every walking member of a party is inside and one of them is in front of the gate
  (so nobody walking back out of the room can start it): block down, gate down, walls in for `CLOSE_SECONDS`
  15.5 to `SHUT_GAP` 5, then shut; a body between them under `KILL_GAP` 3, or inside a wall, dies. It reopens 4 s
  later. Measured: walking in without stopping reaches the room at 15.3 s with the walls 8.5 apart; standing
  still dies at 18.6 s. The small room at the end has the exit door and two glass windows back into the corridor.
- **Deaths between the walls stay in the level** (`finaleDeath`): the party gets "death" (cause `L5Crusher` in
  DeathAdvice), "partydown" when nobody is walking and nobody finished, then "lose"; the dead of a party that
  did finish get "win". `ZyntraReentryUsed` is TRUE from `Void.Join` (a fall must not offer a re-entry) and
  false only after such a death. `ServerStorage.Level5Reentry` stands the player up in the small room;
  GameManager reaches it through `Level6Reentry`, which hands on every player carrying `Level5VoidRound`.
- **The finish has the two choices**: "win" now carries a deadline, next level 6 and a serial (from 500001, far
  from GameManager's); RoundUI answers "continuenow" / "returntolobby" on the same remote; no choice continues.
  `Void.Continue` calls `ServerStorage.Level6EnterFromLevel` twice: "prepare" streams the place, "enter" loads
  the round body there and THEN joins the round.
- **Two traps on the way from one live level into the next.** A living round body torn down by
  `LoadCharacterAsync` reports `Humanoid.Died`: both levels' death hooks counted it (hence body first, join
  second, and `record.continuing` in Level 5's hook). And the new body in Level 6 is 500 studs "under" Level 5,
  so Level 5's fall rule killed it while the player was still on its list: the loop skips `record.continuing`.
- **Loading cover on continue**: the shared marker never drops, so the cover rises for Level 6 on
  `Level5VoidRound` going false while the marker is still true. **Spectating** lists only players of the same
  live level (both carry the marker).
- **Five new sounds** (ElevenLabs via Codex, `assets/level5-void-20261005b`, cleaned by `clean_finale.py`):
  `l5_body_hit_1`, `l5_crusher_slam`, `l5_crusher_groan`, `l5_crusher_grind`, `l5_crusher_shut`. The grind is a
  loop: levelled (`steady`, it came in surges with two seconds of near silence), cross-faded and uploaded as OGG.
  The second body hit was not usable (its scrape was louder than its thud and 1.5 s late).
- **Tool facts.** Two tool calls sent together run one after the other: to capture the viewport WHILE a luau call
  holds a Scriptable camera, start the capture as a background shell job first. The Mac was on the 2560x1440
  display: Studio's dialogs open centred on the DISPLAY, not on its window (file dialog at {830,241}, File Import
  at {470,749} with Confirm at (820,1137)); capture only the window's rectangle. A client-side `PivotTo` of a
  standing body once took 6 s to reach the server; a server-side one is seen at once.
- **Not tested**: more than one player (the party gathering at the gate and its "WAITING FOR THE OTHERS" line, a
  dead player watching the rest, "win" for the dead), the store's own paid re-entry button (the
  `ZyntraReentry:Invoke(player)` hook was used), and the dev button on a touch screen.

### Added 2026-10-06 (morning) - Level 6 is the Arena: built, in Studio, NOT yet published

- **Owner on concept v5**: "I like the new concept photos. Remake the whole map, make sure it matches that vibe 1:1,
  adjust gameplay so it matches the level, make sure the entity is perfect at pathfinding in the structure", then
  "the hole where the post was is the opening to a slide ... a rather long spiral, they slow down, and the end looks
  like the picture" (the exit room, `artifacts/level6-concept-20261006b`, picture 16), "a small room, dirty and worn
  out", and "when you are done make a QA of the map and fix any visual or playable bugs".
- **What stands in Studio**: `Workspace."Level 6 Indoor Playground"` is the arena (`tools/level6_playground/
  build_arena.py` -> `import_arena.py`; everything about it is in `tools/level6_playground/README.md`, "The Arena").
  The game module and client carry the arena's round (`ARENA_20261006`). The old hall is gone from the place and
  can be re-imported from `import_to_studio.py` and the committed `prims.json`.
- **Smaller than the concept's numbers, on purpose**: hall radius 156 (the drawings said 274), lane 112 studs, about
  2 800 cells and 11 100 parts. The drawings' 18 400 cells as loose parts were never possible.
- **Tested in Studio, solo**: arrival through the gate, three searches, the one-minute countdown with the Counter
  hunting across floors (400 studs up to floor 9 in 20 s, no stall), the hatch, nine drops into the funnel from every
  side (12 to 14 s to standing in the exit room), out through the green door (cleared), all four big slides walked
  into from their ledges, a bridge crossed on foot, a stair flight climbed, a chase and catch, the sight rule
  (standing still behind netting: not seen in 38 s; moving: seen). `check_nav.luau`: 0 blocked, 0 without floor,
  0 low roof. **Not tested**: more than one player, a phone, the frame rate on real hardware, the party easter egg in
  the new map, re-entry in the new map.
- **QA found and fixed five real faults**, all of my own making and none visible in a still picture: the funnel's
  side panels were skewed (a flat part needs its two edges at right angles in its own plane) and left a ledge that
  trapped a body; two bridge ends landed on a stairwell's hole; slides never took hold of a walking player at their
  almost level mouths; three slide mouths stood half a degree from a sector's edge and ran into a post; the two tall
  slides doubled back on themselves and jammed the rider in the hairpins. Lesson: **ride and walk every way a player
  can go; the Counter's route check does not cover players**, and it sampled too coarsely to see the bridge fault
  (now every 1.5 studs).
- **A weak-keyed table lost lamps' saved brightness** in the client's red finale (`litBefore`): an Instance key with
  no other Lua reference is collected while the Instance still exists, so the next tick saved the already-changed
  value as "before" and scaled that. In the arena the fill lights ran away to 200 000 (a white screen). Strong table,
  cleared by hand.
- **`AssetService:CreateAssetAsync` comes and goes.** It worked from this Mac session in the small hours of
  2026-10-06 (nine slide meshes became group assets, no GUI), and answered "not available yet" after Studio was
  restarted the same morning. Do not build a pipeline that needs it on the day: meshes without a current asset are
  kept as numbers in ServerStorage and built per server (`Level6ArenaSlideSource`).
- **Studio dropped its Team Create connection once** (02:40, "Connection error 279"); the MCP then lists the old
  process as a studio with no place. Reopen with the `roblox-studio:` URL (`open -g` keeps it in the background) and
  take the new id from `list_roblox_studios`.
- **MCP `screen_capture` works in a play session** and takes a camera position; it shows the client's own lighting
  and HUD. Calls sent together return the same frame: send them one at a time. A camera far from the player sees
  lights arrive late (the engine's coarse far-light grid), which looked like missing light twice.
- **Publishing was NOT possible from this session at the end**: `osascript` had lost its accessibility permission
  ("not allowed assistive access", `UI elements enabled` false under MonoCode), so the File > Publish click was
  refused, and the owner was at the Mac, so no other GUI route was used. Until someone presses File > Publish to
  Roblox, the live game still has the old hall; the arena is saved in the Team Create place.
- `ZyntraConfig`'s L6Party hint said "behind the arcade counter"; that one line was changed in Studio and in the repo
  copy ("at a dead end in the frame"). The rest of that script's foreign drift was left alone.

### Added 2026-10-06 (afternoon) - Level 6 kill cam: the choke is built round the victim's neck

- **Owner, with ten frames from the live game**: "the choke effect with the hands looks awful ... fix this right away,
  so the entity is choking the player visually." The 2026-10-04 clip held both arms straight out, palms down, wrists
  0.13 studs apart (the forearms crossed), and the camera sat just behind the fingertips: two fans of fingers.
- **Now** (`CHOKE_20261006`): `tools/level6_entity/build_choke.py` defines `neck(t)`, where the victim's neck is in the
  doll's own space for the five seconds, and solves both arms to it every frame: a hand either side of the neck,
  palms in, thumbs up, the rigid fingers round the back, elbows out. It takes the throat where the victim stands
  (0.3 s), lifts them 1.85 studs at arm's length (to 1.5 s), then folds its arms and brings them down to its face
  (1.7 to 4.3 s). The server's `chokeNeck(t)` (`CONFIG.Choke`) carries the victim's body along the same path, turned
  to face the doll, and the client's camera is where the victim's eyes are: 0.57 above the neck the two palms are
  clamped on (table `CHOKE`). The three share their numbers; the build prints them.
- **`tools/level6_entity/rig_math.py`**: forward kinematics and a two-bone arm solver for the Counter's rig in plain
  Python. The rig has identity bone frames, so the maths is exact: checked against `TransformedWorldCFrame` to a
  thousandth of a stud. The doll has NO finger bones: a hand is a rigid paddle 0.84 long with the fingers spread,
  the thumb on its front edge. Any pose that points the hands at a camera shows the fan.
- **Measured in a real catch in Studio**: the victim's actual neck stayed within 0.06 studs (mean 0.02) of the grip
  for the whole kill, wrists 1.29 apart. Seen: the frames at about 1 s and 2 s (its face, both arms running to the
  bottom corners of the view). Not seen in the game: the last second (it is going dark by then), and the kill from
  another player's screen (the pose was checked from the side on a test rig with a copy of the suit).
- **A test rig for a pose**: in a play session, clone the doll (and the suit) on the CLIENT while a Level 6 session
  exists, leave the level, and write `Bone.Transform` on the copy yourself: nothing else animates it, so a pose
  holds still for `screen_capture` from any side. Stand the player near it (lights far from the player do not
  draw) and hide the PlayerGui. The suit's visible mesh is `ZyntraHazmatSkinVisual.Scene.char1`, one skinned
  MeshPart on the same bone names; the R15 parts are all transparent. A real kill lasts 5 s and a capture takes
  2 to 3 s to arrive: return from the server poll on the doll's `Spotted` pose to get an early frame.
- The hazmat body, for anything that has to touch it: neck attachment 4.66 above the feet (1.06 above the root),
  first-person eye 0.57 above that, collar about 1.2 across.
- Studio had been closed by the owner; `open -g "roblox-studio:..."` reopened it in the background (it came to the
  front once; MonoCode was put back). In Studio at the end and compiled, NOT published: this session still cannot
  click Studio's menus.


### Added 2026-10-06 (night) - The Reach: an easter egg behind the lobby's fence

- **Owner**: at the DJ end of the lobby you can get over the fence; once you are over there, big glowing eyes open in
  the dark and long clammy arms "made in Blender" creep toward the nearest player; whoever does not jump back is
  grabbed, pulled into the dark, killed and respawned in the lobby. Everything about it (what a player meets, where
  the code is, how to build the meshes, how to test) is in `tools/lobby_reach/README.md`. Marker
  `TUNNEL_REACH_20261006`.
- **Two new scripts**: `ServerScriptService."Lobby Tunnel Reach"` (who is over the fence, where each hand is, the
  kill; publishes attributes on `ReplicatedStorage.LobbyTunnelReach`) and `StarterPlayerScripts."Lobby Tunnel Reach
  Client"` (draws the eyes, the four arms and the victim's screen from those attributes, all local parts). The
  place for it is a block in `LobbyReimaginedPreview.Builder`.
- **The fence was three walls deep.** Its own collision was a sheet 30 studs high, the retired furniture pile's
  blockers (`FurnitureEndBlocker`, in `PreviewCollisions`) still stood in the fence's plane right up to the arch, and
  the end wall kept its `Opaque End Cap`. The Builder now makes the fence's collision as tall as the fence you see
  (14.9) and switches the other two off at the DJ end. Getting over needs the two road cases on the stage's back
  corner; the way back is three crates behind the fence. There is unseen ground for 64 studs behind the wall.
- **The session COULD create scripts on 2026-10-06** (`Instance.new("Script")` parented to ServerScriptService and
  StarterPlayerScripts, source through `UpdateSourceAsync`): the refusal noted on 2026-10-03 was not there in this
  Studio process. Try it before taking over an old script. `CreateAssetAsync` was still refused the same evening.
- **The meshes are baked per server** from `ServerStorage.LobbyTunnelReachSource` (nine pieces, about a second), as
  the Level 6 slides are. Vertex colours work on a Neon MeshPart (the irises).
- **A cap wound the wrong way is a hole in the game**: Blender shows both sides of a face, Roblox culls the back.
  `build_reach.py` asserts every edge is used once in each direction.
- **A lobby avatar's standing jump is 7.3 studs** (JumpPower 50, measured), not the 6.4 of v squared over 2g.
- **Writing the camera from a `RenderStepped` connection loses to the default camera** when the type is Custom; use
  `BindToRenderStep` after `Enum.RenderPriority.Camera`. The lobby respawn (3 s after a death) lands in the middle
  of the victim's last shot, so that shot holds `CameraType = Scriptable` every frame.
- **Tested in Studio, solo**: over the cases and the fence on foot, back over the crates on foot, the arms drawing
  back after an escape, a taking from start to respawn (19 s standing by the fence), the victim's screen. **Not
  tested**: two or more players, phones. **No sound** (not asked for; an upload needs the owner's hands).
- **Studio drift seen that evening** (other sessions, left alone): 21 scripts differ from the repo, among them
  `ZyntraMonetization`, `LunaTribute`, the Level 2 kit generator and builder, `MazeGenerator`, `QueueBridge` and
  three Level 4 modules. `python3 tools/mac_pull_from_studio.py --audit` lists them.
- **Published state at the end of 2026-10-06**: the owner published v2743 at 14:14 (Studio's log; it carries the
  Level 6 choke). The Reach came after that: it is in Studio (Team Create) and in the repo (`be7ffd8`) and was NOT
  published when the session ended. `osascript` still had no accessibility permission that evening ("UI elements
  enabled" false), so the session could not press File > Publish; Studio was left open on the place for the owner.

### Added 2026-10-07 (small hours) - Level 6 in PBR: seven texture sets, applied to the arena

- **Owner**: "recreate level 6 with PBR textures for every texture where it makes sense, and the floor ... almost
  everything would look much better with a detailed, extensive PBR look." Everything is in
  `tools/level6_playground/pbr/README.md`. Marker `PBR_20261006`.
- **What exists**: seven tiling sets (colour, normal, roughness, 1024 px) from `make_pbr.py` in
  `assets/level6-pbr-20261006/` (foam-mat floor with the blue/green check and jigsaw joints, quilted vinyl, plain
  vinyl, mouldy vinyl, painted block, roof deck, slide plastic) and a knotted net picture; a Blender render of
  them (`artifacts/level6-pbr-20261006/preview`); `upload_pbr.py`; `apply_pbr.py`, which makes the MaterialVariants and dresses the
  arena (3566 floor parts, 3152 new pads under the decks, 2052 padded parts, 10 340 overlay Textures removed);
  `collect_ids.py` (the fallback: an Asset Manager import). The game module gives its five runtime-baked slides `L6 Slide Plastic`.
- **APPLIED to the place on 2026-10-07 (about 01:00), NOT published by the session** (it still cannot click
  Studio's menus). `Workspace."Level 6 Indoor Playground"` carries the attribute `PBR = "PBR_20261006"`, seven
  `L6 ...` MaterialVariants are in MaterialService, and `Frame_DeckPads` holds 3152 pads. Three rounds of tuning
  were looked at in play sessions first (`apply_pbr.py --play`); what the engine taught is in the README.
- **Why `CreateAssetAsync` came and went: it is a Studio Beta Feature** (File > Beta Features; the binary names
  `CreateAssetAsyncBetaFeature`). The owner switched it on that night and restarted Studio, and since then a
  session uploads images itself: `tools/level6_playground/pbr/upload_pbr.py` (22 pictures in two minutes; the
  transport through StringValues, zstd and `EncodingService` is described there and is reusable for any image).
  If it answers "not available yet" again: `defaults read com.roblox.RobloxStudio BetaFeatureInformation`.
- **Studio asked for a new sign-in after that restart** ("Reauthorization required" in its log, a Quick Sign-In
  code on screen): only the owner can do that. A studio the MCP lists with `name: null` has no place open.
- **A normal map shows nothing where no lamp reaches** (no bounce light in Roblox): shading that must be seen on
  ambient-lit surfaces has to be painted into the colour map as well.
- **`upload_image` (MCP) uploads to the USER**, and a picture the experience has not been given access to fails
  even in a Studio play session (fetch status Failure; Output: "Click to share access"). The old overlay pictures
  work because access was shared for each. One stray test picture of that kind exists: 71070358744357.
- **A MaterialVariant lies correctly on blocks, cylinders and UV-less meshes, but does not draw from an
  EditableImage** (`ColorMapContent = Content.fromObject(image)` shows the base material; a SurfaceAppearance fed
  the same way showed nothing either). There is no in-engine preview of a texture that is not an asset.
- **A client-side write to a replicated property hides later server writes of the same value** (the server sees
  no change, so nothing is sent): a test that set `MaterialVariant` on the client kept showing the client's
  choice. Reset it on the client.
- **The owner published v2758 at 23:29 on 2026-10-06** (Studio's log): the lobby easter egg is live.

### Added 2026-10-07 (morning) - Level 6 on a phone: the HUD is placed by UIDevice (in Studio, NOT published)

- **Owner**: "Test level 6 on Mobile view and tell if you find any bugs, for example the hide box is over the
  counting text." Confirmed on 844x390: the objective card (x 279..565, y 58..132) lay over the count and the
  status line, the timer lay on Roblox's own top-bar buttons, and the hint ran toward the thumb zones. The Level 6
  HUD was laid out in screen fractions, made for a desktop.
- **Fix** (`MOBILE_HUD_20261007` in Level 6 Playground Client, `placeHud`): on touch the card takes
  `UIDevice.TopRightPanel`, count/status/hint are a column between the LOBBY chip and the card (stacked under both
  when that gap is under 140 px: portrait), timer and the TOUCHED line sit in the free part of Roblox's top bar
  (`UIDevice.InsetArea(TopbarSafeInsets)`). Pointer devices get the old numbers back, number for number. Round
  Exit Client lists `Level6PlaygroundHUD.Objective` as an obstacle; Achievements Client holds a toast while
  `PartyDownCardOpen` (the "Found You" toast was drawn under the PARTY DOWN card).
- **`tools/level6_playground/mobile_audit.py W H`** (and `off`): on the Client of a play session it sets the
  fixtures (`ForceTouchUI`, `UIRegressionViewport`), COPIES every enabled ScreenGui into a frame of the phone's
  size (real GUIs keep hanging on the real screen's edges under the fixture) and reports OVERLAP / THUMB / OFF /
  SMALL / CUT in the phone's pixels. It is a still: run it again for a new moment. Studio's Device Emulator
  cannot be driven from a session (`StudioDeviceEmulatorService` is nil). THUMB findings on a full-screen modal
  (LEVEL CLEARED, PARTY DOWN) mean nothing.
- **Audited clean** (Level 6's own HUD): arrival, count (844x390, 667x375, 568x320, 390x844), search, after a
  touch, the finale countdown, LEVEL 6 CLEARED. Pictures: `artifacts/level6-mobile-20261007`.
- **Found and NOT changed** (shared HUD, the owner's call): `TouchDropGlowstick` is shown in Level 6 and does
  nothing (GameManager's handler wants `inRound[player]`; UIRegression's fixtures expect the button);
  FlashlightPower's "HOLD WIDE" is 10 px high and the gauge stands half behind JUMP; on 568x320 the LOBBY chip
  is 15 px inside the thumbstick zone; the lobby's left rail reports cut labels (UPGRADES, REWARDS, MUTE).
- **Not tested**: a real phone, real touch input (Studio has no thumbstick), the kill cam and the re-entry modal
  at phone size, more than one player.
- **A driver for a whole Level 6 round from the Server** (a play session keeps `task.spawn`ed threads alive after
  the call): step into the lane, stand on a floor-11 `Frame_DecksDeep` deck, set `Level6DevTag` every 1.5 s until
  `Level6Wins` is 3, sit the minute out in the exit room (the Counter reaches floor 11 in 30 s in the finale),
  then go to `ExitDoorPosition`. LEVEL CLEARED has a deadline: measure it at once.

### Added 2026-10-07 (late morning) - The Reach: dark all the way, and no shot of the eyes after the kill (in Studio, NOT published)

- **Owner, with two pictures from the live game**: a few steps behind the fence "you can see the built monster and
  that it's not complete, make sure it is dark all the way down to the entity", and of the picture the victim got
  after the kill (the two eyes from below, the arms in front): "no kill cam like that looking at the entity
  please, just black screen and then respawn in lobby". Marker `REACH_DARK_20261007`; the how and why are in
  `tools/lobby_reach/README.md` ("How the dark is made").
- **It took three things, because `Lighting.Ambient` is (30, 32, 30) in the lobby**: an unlit part is still a
  visible grey. The Builder fades the copied lamps by their own depth (none from 70 studs behind the wall) and
  shades the five copied tunnel sections 1, 0.78, 0.45, 0.12, 0; the client blacks out every piece of the
  creature by depth (all colour to 34 studs, none from 72; a piece near the camera keeps some); the eyes' two
  PointLights (range 52, orange) are gone. The black sheets at 70, 100 and 128 are gone as well.
- **A Color3 factor is not an amount of light**: 0.5 on a section (part Color and SurfaceAppearance.Color both)
  was black on screen and drew a hard line across the road.
- **The victim's screen**: closes in from the grab, black thirty studs into the pull, black until the lobby has
  stood them up, then fades in. The `stare` phase, its Scriptable camera and `DevTunnelReachStare` are deleted;
  phases are `pull`, `wait`, `back`.
- **Tested in Studio, solo**: a taking from 14 studs behind the wall and one from 50 (the eyes were never nearer
  than about 45 studs to the camera while anything showed; camera stayed Custom; new body 3.5 s after the death;
  22 screens back; console clean), and the look from the lobby, from 4 studs behind the wall and from 58.
  Pictures: `artifacts/lobby-reach-20261007`. **Not tested**: two or more players, a phone, the live game.
- **Parking the camera for a look**: `BindToRenderStep` at `Camera.Value + 5` writing `CameraType = Scriptable`
  and a CFrame from a workspace attribute every frame; nil hands the camera back. Stand the body near the place
  first: lamps far from the body do not draw, and the lobby is black for some seconds after a teleport.
- **One play session drew the creature's bones but none of its palms, fingers, claws or eyes** (all in the data
  model, Transparency 0); the next session drew everything. Not explained. Restart play before believing it.
- **A push right after stopping play can take two minutes** (the first try answered "Edit datamodel is not
  available in Play mode", the second sat until Studio was back); it did land.

### Added 2026-10-07 (midday) - The Reach, second round: the daylight behind the fence was RoundUI's (in Studio, NOT published)

- **The owner published the first fix (10:55) and sent a picture: the tunnel behind the fence still fully lit,
  the arms black cut-outs in it, the eyes two balls of light. "You be the judge."** Not good: the morning's fix
  treated a symptom.
- **The cause: RoundUI's `revisedLobbyLighting.contains` only counted a body inside the lobby's box**, which ended
  5 studs behind the DJ end wall (`PreviewCenter` z + 144; the wall is at + 139). Past that the client was handed
  the old lobby's preset: ClockTime 14, Brightness 1.35, Ambient 76/69/45. The copied tunnel sections cast no
  shadow, so the sun lit them from end to end. `contains` now also accepts the stretch behind the wall, measured
  in `InfiniteTunnelEnd.ReachFrame` (x within 40, z from -10 to 215). Logged through a whole taking afterwards:
  ClockTime 0 and Ambient 0.12 from the fence to the kill at 151 studs and back to the spawn.
- **Why the morning's tests did not show it**: every picture was taken with a parked camera behind the fence and
  the body in front of it, so the lobby's lighting stayed on. Lighting goes by the BODY. The two real takings of
  the morning had the body there, but only numbers were logged, no picture.
- **The eyes keep 55% of their colour** (`EYE_GLOW`): at full colour the bloom ate the iris and the slit. Only
  visible at full graphics quality; Studio's play window at `Automatic` drew them fine.
- **Studio can be put at the player's quality**: `settings().Rendering.QualityLevel = Enum.QualityLevel.Level21`
  from a Client `execute_luau`. It is a Studio setting and persists: it was set back to `Automatic`.
- **A script over 200 000 characters cannot be written to a probe's `.Source`** ("greater than or equal to max
  length"): RoundUI's compile probe is a ModuleScript parented to ServerStorage and filled with
  `UpdateSourceAsync`, then required and destroyed. RoundUI in Studio and in the repo are the same 272 478 bytes.
- **Rule from this**: before reporting a visual fix, look at it as the player (body there, own camera, HUD on,
  full quality), not through a parked camera.

### Added 2026-10-07 (afternoon) - Level 6: nothing lies over anything any more, and the overpass (in Studio, NOT published)

- **Owner, with ten pictures from the live game**: "we have overlapping textures several places, fix that, and
  the entity gets stuck in the middle of the overpass in the top of the map." The pictures: the yellow ring round
  the post, the lid inside it, a patch of floor where the lane meets the court, and the Counter standing on the
  hub of the two bridges while the player stood on one of them.
- **The overlaps were mine and a day old in their effect**: none of the geometry was new, but the PBR pass of
  the night before printed a pattern on every surface, and wherever two parts shared a plane or one lay on
  another a flat colour had hidden it. `tools/level6_playground/check_overlaps.py` finds such places in the
  export: 1 276 in sight before, `RESULT 0` now. **Run it after every geometry change, and before dressing any
  level with printed materials.** What changed is in `tools/level6_playground/README.md` ("No two surfaces in
  one plane"): decks cut to the shape of their cells, a new lid and ring, the lane, the top step of every
  flight, the tunnel's wall, the exit room's collar. Marker `MATS_20261007`.
- **The decks are `UnionOperation`s now** (3453, and their 3152 pads): a mat between two radii and two sector
  lines is not a shape Studio has, so the importer cuts one block per shape (16) with
  `GeometryService:SubtractAsync` and clones it. That call works from an Edit `execute_luau` (0.1 s a cut); the
  result takes a non-uniform `Size`, a MaterialVariant and ray queries like a part; set `UsePartColor`. Cut near
  the world's origin, not at x = 52 000.
- **Mats that meet edge to edge leave a seam a ray can fall through**: `check_nav.luau` reported "no floor" at
  the top of 10 stair flights, exactly on the line between two mats. The top step reaches 0.4 under the mat now.
- **The overpass** (`OVERPASS_20261007`): the Counter is only sent to a node of its graph and walks at most 16
  studs on from it. Each arm of the bridge was one link, so the hub was the only node on the crossing: a player
  anywhere else on a bridge had it walk to the hub and stand there. Four nodes per arm now. Tested: with the
  player 30 studs out on an arm it climbed to floor 8, ran down the arm and caught them there.
- **The same card-over-count bug existed on desktop** in any window 768 pixels high or less (the card is at
  least 74 pixels high and hangs 58 from the top; the count is placed by the window's height). The count and
  status lines move down by what is missing, and `placeHud` also runs when the viewport changes.
- **Tested in Studio at full quality, solo, as a player**: the court, the lane's mouth, a gallery (floor and
  ceiling), the tunnel, the exit room; three stair flights climbed on foot; the lid's seven pieces drop and come
  back; six of six entries into the hole reached the exit room (two walked in, four dropped at the edge; a
  seventh was cut short by the Counter); `check_nav.luau` three zeros; console clean. Pictures:
  `artifacts/level6-overlaps-20261007`. **Not tested**: more than one player, a phone, frame rate (3453 unions
  instead of 3453 parts: same triangle count, not measured).
- **A drop test and the Counter**: it ignores a body under the floor and catches one that comes back up beside
  the post. Open the hatch by hand during the count (`CanCollide = false` on `Finale_Lid` and `Finale_Post`) and
  expect about four drops before the hunt reaches the court.
- **Studio was closed when this began; `open -g "roblox-studio:..."` reopened it and it took the front for a
  moment** (Chrome was put back with `tell application ... to activate`). The MCP studio id changes with every
  restart. 23 scripts differ between Studio and the repo from other sessions (ZyntraStore, three new `Zyntra *
  L4` clients, the Level 2 kit, GameManager...): left alone.

### Added 2026-10-08 (later) - The game's icon on Roblox is I01 (live)

- **Owner**: "Upload them to icons". **Roblox has one icon per game** (the Icon page has a single slot; there is
  no set and no testing as with thumbnails). So: all ten icons were uploaded to the group as Image assets (named
  `BSQ icon I01 shh` ... `BSQ icon I10 poolrooms`), all ten were approved, and I01 (the "shh" with the Entity in
  both lenses) was set as the icon. Confirmed from Roblox's public icon service. The other nine are shown nowhere.
  Ids: `artifacts/promo-20261007/store-upload.json` (`icon.assets`, `icon.live`, `icon.before`).
- **The old icon** is image `139988603985474`; `store_pictures.set_icon(139988603985474)` puts it back, and
  `set_icon(<another id from the record>)` switches to one of the nine.
- **How the Icon page works** (read from its own script, now in `tools/promo/store_pictures.py`): it creates an
  Image asset (`POST apis.roblox.com/assets/user-auth/v1/assets`, form fields `request`, `fileContent`,
  `additionalParameters = {"AssetPrivacy": "OpenUse"}`) and then points the place asset's `icon` field at it
  (`PATCH .../assets/<place>?updateMask=icon`). Doing the two steps apart lets the picture be approved BEFORE it
  becomes the icon, so the game never shows one that is in moderation: the ten took about a minute to go from
  `Reviewing` to `Approved`, and the public icon was `Pending` for under ten seconds after the switch.

### Added 2026-10-08 (small hours) - Levels 5 and 6 take ONE PARTY AT A TIME (in Studio; live once the owner publishes)

- **Owner, from the live game, furious**: "everyone ends up in the same server in Level 6. If one queues with at
  most 2 and another queues later with 3, they all join the same one. Fix it NOW and make sure it does not happen
  with Level 5 either." True, and it was so from the day these became live levels (2026-10-03/04): each is ONE map
  on the lobby server, `Level 6 Playground Game.AddPlayer` puts every later arrival into the session already
  running, and Level 5's two parties shared doors and plates. Every note above lists "more than one player" as
  not tested; this is what that hid.
- **The fix (`PARTY_LOCK_20261008` in `Level6PreviewAccess` and `Level5PreviewAccess`)**: a lock per level. A party
  is a token: the queue's context (Level 6), the launch's `group` table (Level 5), a fresh table for an E entry,
  Level 5's group for CONTINUE (`Level6EnterFromLevel:Invoke(player, step, group)`). `claim` is taken before
  anything is streamed and again inside `Runtime.Join` / `Void.Join`, so no entry path gets round it. Refused
  players get a card on screen ("LEVEL n IS IN USE ...", a server-made ScreenGui `LiveLevelBusyNotice`, 7 s) and
  the pad's own "PREVIEW ENTRY FAILED" from GameManager. The level is free the moment its last player is out;
  a party still streaming in keeps its hold for 90 s (`entered` tells the two apart). Level 6's occupants are the
  players with `Level6PlaygroundPreview` and without `Level5VoidRound`; Level 5's are its `members`.
- **Replicated flags** `workspace.Level5InUse` / `Level6InUse` (1 s), and `Level5PartyLock` / `Level6PartyLock`
  carry the marker. Nothing shows them at the gates yet.
- **Level 5 sends a living member home after 5 minutes without moving** (four studs): with one party at a time an
  idle body would close the level to the whole server. Not while an ending is up. Level 6 has no such rule (the
  Counter finds a body that stands still; a dead player watching is supposed to stand still).
- **THIS IS A STOPGAP, and the owner was told so.** What they expect is what Levels 1 to 4 do: a reserved server per
  party. That means carrying a "live level" launch through GameManager's reserved-server path (no lobby is built
  there, a dozen scripts stand down on `ReservedRoundServer`, the way home is a teleport) and it cannot be tested
  in Studio (no TeleportService). Not started; it needs the owner's go and a live test.
- **Tested in Studio, solo**: Level 6 through the pad; a second party (another token through
  `Level6EnterFromLevel`) refused on "prepare" and "enter" with the card shown; free 0.9 s after leaving; a new
  launch in; Level 5 through the pad, flag up, free 0.8 s after leaving; the Level 5 lock's lines run against a
  stand-in member list (nine cases). **Not tested**: two real parties on two pads (needs two clients, which needs
  clicks in Studio's toolbar), the CONTINUE from Level 5 into a busy Level 6, the idle rule's five minutes.
- `execute_luau` has no `loadstring`. Studio updated itself on launch that night (0.741 to 0.742) and reopened
  the place by itself; `open -g` did not take the front from the Roblox player.
- **The owner published it at 02:26 (v2798).** Servers that were already running keep the old code until they empty.

### Added 2026-10-08 (small hours, later) - A maintenance board in front of the Level 2 gate (in Studio, NOT published)

- **Owner**: a sign at the entrance to the Level 2 poolrooms: this level is under maintenance, the real poolrooms
  level is live within 24 hours, please go on to another level, thank you for your patience; "in very simple
  language everyone can understand, and in several languages, the ones our players speak".
- **`LEVEL2_MAINTENANCE_20261008`, the last block of `LobbyReimaginedPreview.Builder`** (folder
  `Level2Maintenance`, 9 parts, no Light): a barrier board 16 x 10.1 studs on the sidewalk 5.6 studs in front of the
  gate, lettered on both faces. UNDER MAINTENANCE, four English lines ("We are fixing this level. / The real
  Poolrooms open within 24 hours. / Please play another level. / Thank you for your patience!"), then ES, RU, PT,
  DE, ID, FR in two columns. Board and posts collide; the way in is round either end. **Take the block out the day
  the new Level 2 is what the queue starts.** The gate, pads and queue are untouched: the old round still starts.
- **The languages are the game's own players**: `POST apis.roblox.com/analytics-query-gateway/v1/metrics/resource/
  RESOURCE_TYPE_UNIVERSE/id/<universe>` with `{resourceType, resourceId, query: {metric: "DailyActiveUsers",
  granularity: "METRIC_GRANULARITY_ONE_DAY", startTime, endTime, breakdown: [{dimensions: ["Locale"]}]}}`, sent
  through the dashboard tab (`Country` works too, `Language` does not; a first answer can be 202 with no result:
  ask again; `dashboard.call` cuts answers at 20 000 characters, so sum inside the page). Last 28 days: en 55%,
  es 9.7, ru 9.2, pt 3.6, de 3.4, id 2.9, fr 2.5; by country US 14.6%, PH 12.0, RU 5.6, DE 4.9, GB 4.1.
- **SurfaceGui facts**: 100 is the largest text size, with `TextScaled` too, so `PixelsPerStud` decides how tall
  letters can be (75 gives 1.33 studs). Cyrillic renders in the Gotham faces. A `UIGradient` turned 45 degrees does
  NOT run corner to corner on a wide tile: its ends clamp, so ten hard bands came out as a block, four thin
  stripes and a gap. It reads as hazard tape and was kept.
- **Tested in Studio at full quality, as a player**: built by the Builder at boot; readable from the spawn (the
  Level 1 and 2 gates are the first a new player sees); a straight walk at the door is stopped by the board; round
  the spawn-side end into the bay and out round the far end on foot; console clean. Pictures:
  `artifacts/lobby-level2-maintenance-20261008`. **Not tested**: a phone (the six translations are 0.33 studs
  high: readable from about eight studs on a desktop, closer on a phone), more than one player.
- **A play test can be muted from the client**: set `Volume = 0` on every Sound and SoundGroup and hold it there
  with `GetPropertyChangedSignal("Volume")`, plus `DescendantAdded`. `UserGameSettings.MasterVolume` is out of an
  `execute_luau` call's reach (RobloxScript capability).

### Added 2026-10-08 (before dawn) - Level 3: the way out is lit, exit signs, the slide's board, a pointer at the CD reader (in Studio, NOT published)

- **Owner**: "when the CDs are put into the CD player the pathway doorframe should have a visible blue light so
  people know they have to walk through there and down the corridor. Put very subtle lit exit signs down the
  corridor", then: the signs "are to be made in Blender, the light effect is yours to work out"; at the Level 3
  spawn "remove that NO EXIT sign at the end of the slide, just make sure one slides out of it if one tries to go
  in"; and "a message and an arrow that points at the wayfinder with how to find the CDs, shown for a short while".
  Markers `EXIT_WAY_20261008`, `SLIDE_MOUTH_20261008`, `CD_HINT_20261008`.
- **Why the door was dark**: the blue frame WAS revealed at the unlock, but the unlock also starts the completion
  blackout, and the Level 3 Lighting Controller paints every part in `blackoutParts` (the frame is one) dark and
  switches every Light in the world off, on each client. The frame was also an eighth of a stud wide and its one
  light was disabled by the server on purpose (`LEVEL3_COMPLETION_ESCAPE_GUIDE_DISABLED_20260824`: "the finale is
  deliberately lightless"). The owner's request overrides that for the doorway and the corridor only.
- **Now**: the frame is .34 wide and .16 proud with a strip of plain blue Neon set into its posts and head
  (`WayGlow`, six parts) and three PointLights of its own (`WayLights`: hall side 7/34, mouth 6/30, 15 studs in
  4/26; set by eye from 26 studs out in the blackout: 2.2 was invisible under exposure -0.85). The Objective
  Controller brings both up in `unlockExit` and puts them out at session start and cleanup. **`Level3_ExitWay`
  (attribute) is what the Lighting Controller never records, sweeps or fades, and what the Visual Adapter does not
  hide.** The kit skin on the frame (`FluorescentDiffuser`) stays Neon blue once the exit is unlocked.
- **The Visual Adapter hides EVERY part the World Builder made** (`legacy`, Transparency 1) except the arrival tube
  and the waiting room, then dresses the level from the Blender kit. Anything the builder adds as a final look
  needs `Level3_ExitWay` (or its own exemption), or it is built and never seen: the first exit signs were.
- **Exit signs**: `tools/level3_exit_signs/build_sign.py` (Blender, headless: a box on two rods with ceiling roses,
  a lens, the word EXIT and an arrow as flat geometry, vertex colours; saves the .blend, the numbers and a render
  under `artifacts/level3-exit-signs-20261008`) and `install_sign.py` (uploads both meshes to the group, builds
  `ServerStorage.Level3Assets.ExitSign`). `makeFinalHallExitSigns` hangs one every 56 studs from 24 studs in (ten in
  the 560-stud hall), lettered toward the walkers. Light effect: the lens smoulders, the letters are a dim green
  Neon, each lit sign has a faint green PointLight (1.1 over 16 studs, no shadows), signs 1, 4 and 8 are at half
  strength and sign 5 is dead (`(n * 5 + 3) % 7`). With the finale's fog ending at 115 studs a runner has the next
  one or two in sight. Nothing collides.
- **`AssetService:CreateAssetAsync` worked that night** (the Beta Feature is on): mesh assets 111578488616320
  (housing) and 139159946781572 (glow). One stray probe mesh exists in the group: 80879822235454 "BSQ upload probe".
- **The slide**: the yellow NO EXIT / ONE-WAY ARRIVAL board over the mouth is gone. Nothing else was needed: the
  slip loop already lays down anybody more than ten studs up the bore and carries them out (measured: a walker got
  14.5 studs in and was slid back).
- **The pointer** is in `Level 3 Reader Client`: a card `ReaderHint` beside the CD reader (under it where there is
  no room beside it), "FIND THE 5 CDs / This reader points to the nearest CD. Turn until the mark is in the middle,
  then walk." with arrows that drift toward the panel. Ten seconds, once per round, gone at the first CD, a toast,
  a modal or the reader being put away; not under UIRegression's viewport fixture.
- **Tested in Studio at full quality, as a player**: two rounds; five CDs collected and inserted through the real
  prompts; the doorway from 26 studs in first person; through the door on foot and 103 studs down the corridor
  (14.4 studs/s, nothing in the way); the signs in the dark; the card at round start; the slide; the test suite
  loads and `ValidateConfiguration` passes; console clean. Pictures: `artifacts/level3-exit-way-20261008`.
  **Not tested**: the run to the freight door with the Manager behind, more than one player, a phone (the card's
  under-the-panel layout was not seen), the rest of the test suite (`ValidateRuntime` has new way-light checks).
- **Driving a round**: a CD pickup from 3.5 studs on +X failed once behind furniture; try four sides
  (`/tmp/l2sign/l3_server_rest.lua` did). In locked first person, write `camera.CFrame` for twenty frames to turn
  the player's own view; one write does not stick.
- **Another session had been in Studio**: `Routing.MaxLevel` is 4 since 2026-10-05 (a Level 3 clear offers CONTINUE
  into the cinema) and the Level 4 bays are ordinary pads (`QueueBridge`: `previewOnly = level > 4`), so a Level 4
  party gets a reserved server like Levels 1 to 3. Their GameManager, Routing and QueueBridge were pulled into the
  repo with `tools/mac_pull_one.py` (named scripts only). Nothing of theirs was changed.
- **Continue at the end of a level, as it stands**: 1 to 2, 2 to 3, 3 to 4 (GameManager, each player's choice shown
  in the PartyChoices list) and 5 to 6 (in the same server). **4 to 5 does not exist**: Level 4 ends on a reserved
  round server and Level 5 runs on a lobby server. It needs the same change as giving Levels 5 and 6 a server per
  party; the owner was asked for a go and for what "vote" should mean (today each player chooses for themselves).
- **The Level 2 sign "was not there"** for the owner because their client joined its server 13 seconds before
  their own publish finished (the player's log has the join time, Studio's log the publish). The lobby is built
  once per server: a new server shows it.


### Added 2026-10-08 (night) - A server per party for Levels 5 and 6 (developer parties first); CONTINUE 4 -> 5

- **Owner**: "Whatever is the case for the other levels like level 1, 2 and 3" (a server per party), and on the vote:
  "let them decide for themselves. No majority decide. People can leave if they want without stopping the
  continue" (that is how the result window already works: nothing changed there).
- **How it works** (`SERVER_KIND_20261008`, `LIVE_LEVEL_SERVERS_20261008`). Levels 5 and 6 still run on a lobby
  server, one map and one game per server; a party now gets a LOBBY SERVER OF ITS OWN:
  1. `ServerScriptService.ServerKind` (new ModuleScript) answers what a reserved server is: a GameManager round
     (`IsRoundServer()`), or one party's own lobby for a level (`LiveLevel()` = 5 or 6). The lobby that reserves the
     server registers its `PrivateServerId` in the MemoryStore hash map `LiveLevelServersV1` (15 minutes) BEFORE
     anybody is sent; the new server reads its own id in the module body (it yields, on reserved servers only).
     If MemoryStore does not answer at all, the first arrival's teleport data decides (`LiveLevel` in it).
     **GameManager's `IS_RESERVED_ROUND_SERVER` is `ServerKind.IsRoundServer()` now**: on a party's own lobby it
     is false, so the lobby is built and every script that reads `workspace.ReservedRoundServer` behaves as in
     a lobby. `workspace.LiveLevelServer` (replicated) is 5, 6 or nil.
  2. `launchStation` (GameManager): for a Level 5/6 pad it calls `ServerKind.Reserve(level, players, token)`;
     with a code it shows the round loading cover and teleports the party with `{LiveLevel, LiveSession, Expected}`.
     Without one (Studio, the gate, Roblox refusing, a server that already is a party's own) it enters on the spot
     as before, where `PARTY_LOCK_20261008` still keeps parties apart.
  3. `ServerScriptService."Live Level Server"` (new Script, ends at once on any other server): groups arrivals by
     session, waits for each client's "ready" on `ReplicatedStorage.LiveLevelArrival` (35 s cap) and for the party
     (12 s for a pad launch, the decision deadline + 8 s for a continuation), then invokes
     `ServerStorage.Level5LaunchParty` / `Level6LaunchParty(players, token)` (new, in the two access scripts: the
     pad's checks, streaming, `QueueBridge.PartyLandings` for the arrival slots, join, round body). Player
     attribute `LiveLevelPending` is true until the launch has been tried. OUT: a player who has been in the
     level and is back in lobby state gets a black cover and is teleported to the public lobby with
     `{ReturnToLobby = true}`; players who come out in the same tick travel in one teleport; four tries.
  4. `Lobby Loading Screen`: on such a server `run()` returns `"live"` (no lobby assets fetched), the lobby cover
     stays until `coverArrival` has raised the LEVEL's cover under it, fires "ready", holds until the level's
     marker (or `LiveLevelPending` false, or 90 s) and hands on to `coverLive(level, cover)`.
  5. **CONTINUE from Level 4 into Level 5**: `runPostWinIntermission` reserves and registers the Level 5 server
     BEFORE "win" is fired (no server, no button; at most 4 s), sets `nextLevel = Routing.MaxLevel + 1` and
     `session.NextServerCode`; `teleportPlayersToNextLevel` adds the three live fields to the packet. The round
     packet's own `Level` is clamped to 4 and ignored by the lobby there.
- **THE GATE: `ServerKind.OwnServers = "developers"`.** Only a party whose EVERY member passes
  `DevAccess.IsLevel6PreviewAllowed` (mikkelczar, LaverSneglen, ZenMeister02) gets its own server or the 4 -> 5
  button; everybody else plays exactly as before this change. Reserved servers, MemoryStore and teleports do not
  exist in Studio, so none of the cross-server path has run yet. **To do with the owner: queue for Level 6 and
  Level 5 on the live game with one of those accounts (alone, then two of them together), clear Level 4 and press
  CONTINUE; then set the one word to "everyone" and publish.** `"off"` switches the whole thing off.
- **Tested in Studio**: a normal boot (public lobby, `ReservedRoundServer` false, both launch hooks present, the
  level-server script standing down); `Level6LaunchParty` and `Level5LaunchParty` called directly (in the level
  in 6 s, round body, leave works); a SIMULATED party server (`workspace.DevLiveLevelServer = 5 | 6`, honoured in
  Studio only) for both levels: arrival, the level's cover from the first frame ("[LobbyLoading] live in 0.8 s",
  "[LevelLoading] level 6 covered for 24.3 s"), launch, leave, the teleport home refused by Studio and the cover
  taken down again. **Not tested**: everything that needs a real reserved server (the reservation and
  registration, the arrival of several players, a latecomer, the trip home, the 4 -> 5 continue), two parties.
- **Left on the raw `PrivateServerId` test** (they stand down on a party's own lobby too, which only matters to
  somebody whose trip home failed four times): `Lobby Tunnel Reach`, `LunaTribute`, the Level 1 and 2 Blender
  preview scripts, and ZyntraAnalytics' `RESERVED` (right as it is: such a join is the same session going on).
- **`workspace.DevLiveLevelServer` must never be left set in the place**: every Studio play would be a simulated
  party server. It was set when Studio's Team Create link dropped and was still 5 after the restart; cleared.
- **Studio hung on 2026-10-08 at about 03:46**: an `execute_luau` that read `.Source` of every script under four
  services timed out, the Team Create heartbeat failed, the owner's publish at 03:47 timed out after four minutes
  ("Internal server error") and every later MCP call timed out. `tell application "RobloxStudio" to quit` answered
  "User cancelled"; the process was killed and the place reopened with the `roblox-studio:` URL. Everything pushed
  before the hang was in the Team Create copy. Use `script_grep` (MCP) to search Studio's scripts, not a loop
  over `.Source` in one call.

### Added 2026-10-08 (night) - Token-earner upgrade passes off sale; Entity Detector: large screen, 30 s live, 10 s cooldown

- **Owner**: remove the three "upgrade" passes (2x to 3x, 3x to 5x, 2x to 5x) from the store, keep 2x, 3x and 5x.
  Done on Roblox, no publish needed: `isForSale` false on passes 1994282418, 1995812369, 1994252411
  (`tools/store/token_earner_passes.py read | off`; before and after in `artifacts/store-passes-20261008`).
  Prices and regional pricing are untouched, so switching one on again restores it as it was. **Owners keep
  their tier** (`TokenEarner.Tier` still counts an upgrade on top of its prerequisite), and both in-game shops
  only ever offer a pass whose product info says `IsForSale`, so a 2x owner is now offered the direct 3x or 5x.
- **Game-pass calls from the dashboard tab** (signed-in page, `dashboard.TAB = 'create.roblox.com/dashboard'`):
  `GET apis.roblox.com/game-passes/v1/universes/<u>/game-passes/<id>/creator`, the list
  `.../universes/<u>/game-passes/creator?pageSize=50`, and `PATCH .../universes/<u>/game-passes/<id>` with form
  fields (`isForSale`, `description`, ...; only what is sent changes; answers 204). The public view is
  `.../universes/<u>/game-passes?passView=Full&pageSize=100` (no sign-in). The older `/game-passes/<id>/details`
  answers "Failed to fetch" from the page. Chrome's scripting bridge dropped out several times that night
  ("Application isn't running", -600): read first, retry, never write on top of a failed call.
- **Entity Detector** (`DETECTOR_LIVE_20261008`, `DETECTOR_BIG_SCREEN_20261008`; owner: "a much larger screen when
  used and demoed and also last for 30 seconds and have a cooldown of 10 seconds and change all info"):
  - `ZyntraConfig.Detector = {Cooldown = 10, ReadingSeconds = 30, RefreshSeconds = .5, ...}`. The server keeps
    the band LIVE for the thirty seconds (a loop per scan republishes `ZyntraDetectorReading`), and the cooldown
    counts from the moment it switches off: `ZyntraDetectorReadyAt` = scan + 40 s, or now + 10 s when it is cut
    short (death, exit, round end). Still only a band; nothing else leaves the server.
  - `ZyntraDetectorVisual`: the generated face picture (screen opening 61% x 29% of the housing) is no longer
    applied. `Build` makes a face of parts with a screen of `Visual.Screen` (86% x 64%); `Preview` projects the
    readout onto that glass (`viewHeight()`), with a rim and a status lamp in the band's colour.
    `Visual.ScreenBottom` (.724) is where the screen ends in a preview frame. The demo panel may grow to
    1040 x 780. Readout at Studio's 1250 x 595: 119 x 133 px in a run (was about 100 x 73), 151 x 168 in the demo.
  - `ZyntraDetectorClient`: device height 70% of the safe height (240 to 600, never wider than half the
    screen), held low so the screen ends above the status line and the grip runs off the bottom edge.
  - `ProtectionHUD`: while it is on, the detector's control is enabled and reads HIDE / SHOW; pressing it toggles
    the client-local `ZyntraDetectorStowed` (the device goes, the status line stays). My addition, not asked for:
    thirty seconds of a large device in the middle of a first-person view needed a way to put it down.
  - Wording: the two descriptions in `ZyntraConfig.Passes.EntityDetector`, the demo's texts in the visual
    module, and the pass's description on Roblox (changed after the publish, see below).
  - Tested in a Studio Level 1 round: on for 30 s, band LOW / MEDIUM / HIGH / LOW as the body was moved to and
    from the entity, gone at 30 s, ready 10 s later, Z scans again, Z hides, Z shows; the demo from the lobby.
    **Not tested**: touch (the SCAN control on a phone), a gamepad, Levels 2 to 4, UIRegression.
- **MCP `user_keyboard_input`** presses real game keys in a play session (Client): the way to test a key binding.

### Added 2026-10-08 (before dawn) - Advanced Equipment is +100% on both capacities; a leaderboard board at every gate

- **Advanced Equipment** (`ADVANCED_100_20261008`; owner: "100% for both stamina and battery cap", and the wording
  everywhere). `ZyntraConfig.Passes.AdvancedEquipment.StaminaBonus` 0.50 -> 1.00 and a new `BatteryBonus` 1.00, both
  additive on top of bought upgrades; `advancedStaminaBonus(player, field)` in ZyntraMonetization feeds both
  multipliers (`ZyntraStaminaMultiplier`, `ZyntraBatteryMultiplier`) and `BatteryPercent`. The pass used to hand
  one +5% upgrade LEVEL to each on purchase: that grant is gone for new buyers (the once-only flag and message
  stay), old owners keep their levels. My reading of "100% for both": it replaces the +50% stamina, it is not added
  to it. Measured in Studio on an owner with no upgrades: stamina x2, battery x2. The wording lives in the two
  config descriptions, the purchase message, and the pass's description on Roblox.
- **Level leaderboards** (`LEVEL_LEADERBOARDS_20261008`, new Script `ServerScriptService."Level Leaderboards"`;
  owner: a tall sign out from each level's entrance with the usernames that cleared it fastest, in the lobby's
  style, top 3 each with their own colour and size; "it is when YOU reach the exit ... somebody who died has none").
  - RECORD (every server): one OrderedDataStore per level, `LevelBestTimes_v1_L<n>`, key = UserId, value = the
    player's own time in whole milliseconds, only ever lowered (`UpdateAsync` returns nil for a slower time).
    Levels 1-4: the script listens to `ServerStorage.ZyntraLevelCompleted` (fired once per escapee; `run.Seconds`
    is round start to that player's own escape) and skips `run.DevTouched`. Levels 5 and 6 fire the new
    `ServerStorage.LevelTimeReported(player, level, seconds)` at their finish lines, and only for the player who
    really got out (both levels also send the "win" screen to the fallen: no time for them). Times under 10 s or
    over 6 h are refused. Studio never writes. Re-entries count; developers are not excluded in Levels 5 and 6.
  - SHOW (lobby servers, also a party's own): `LobbyReimaginedPreview."Level <n> Leaderboard"`, a 5.6 x 13.2 stud
    board at right angles to the wall, 15 studs along it from the gate's middle (under the "LEVEL n" arrow blade;
    at Level 4 on the other side, where the blade's side is the shop's last box), solid, lettered on both faces
    at 50 px per stud: LEVEL n / FASTEST ESCAPES, three cards (gold 255,205,84; silver 206,222,232; bronze
    230,152,92; name sizes .52 / .44 / .39 studs), ranks 4 to 10 as rows. One level is read every 20 s
    (`GetSortedAsync(true, 10, 10000)`), names through `GetNameFromUserIdAsync` (cached). No Light instances.
  - `workspace.DevLeaderboardDemo = true` (Studio only) fills the boards with sample rows. Never leave it set.
  - **Seen in Studio** with the sample rows: all six boards, the Level 3 board close up, the Level 2 gate with its
    maintenance board beside it. **Not tested**: a real time being saved and read back (Studio writes nothing),
    names of real accounts, the boards on a phone.
- **Gate geometry, measured** (gate frame: X along the wall, Y up from the sidewalk, -Z into the tunnel): header
  22.8 x 2.68 at y 17.2; arrow blade .86 x 2.95 x 9.2 at (15, 17.0, -3.7); the sidewalk is clear on both sides of
  every gate from the wall to 6.6 studs out. Gates stand at lobby x = +-27.2, z = -80, 0, +80 (left wall 1, 3, 5).
- **Studio hangs when the Mac is out of memory.** Second hang of the night (03:33 UTC+2 ... the play session's stop
  never reached `StopPlaySoloEnd`, then the Team Create heartbeat failed): Studio held 6 GB and swap was 7.5 of
  8 GB. Before a play test on this 8 GB Mac check `sysctl vm.swapusage`; restart Studio when it is nearly full.
  A stop that hangs shows in the log as `StopPlaySoloStart` with no `StopPlaySoloEnd`.
- **Published as v2809 on 2026-10-08 at 05:04** (Studio's log: "Place published", "Published new changes"). It
  carries the Level 3 batch, the party servers (gate on "developers"), the detector, Advanced Equipment at +100%
  and the leaderboards, plus whatever other sessions had in Studio. The owner's own publish at 03:47 had failed on
  the hung Studio; they went to bed with "you have to publish on your own ... open codex on my pc and have that do
  it". With the Mac idle for 17 minutes, `codex exec --enable computer_use -s read-only` was given one job (File >
  Publish to Roblox, type nothing, touch no other app, stop at any other dialog) and did it in about 80 seconds;
  `/tmp/live/publish_when_idle.sh` waited for three minutes of `HIDIdleTime` first. It needs exactly one Studio
  process and a Studio that answers.
- **After the publish the two passes' descriptions on Roblox were changed** to the new numbers
  (`tools/store/pass_text.py`; old and new texts in `artifacts/store-passes-20261008/pass-descriptions.json`).

### Added 2026-10-08 (morning) - Level 5: a death keeps you in the level; the Level 4 bay's posters in lightboxes

- **Owner**: "For Level 5 there is no kill cam like all the other maps. You just die and are thrown back to the
  lobby; there has to be spectating, buying a re-entry or using a banked one, and you spawn at the start of the
  section you have reached. So like the other levels", a DEV cheat button that re-enters all dead players in the
  level, and the DEV re-entry option for developers who die. This supersedes "a fall is a death, no spectating or
  re-entry in Level 5" (2026-10-04). Markers `DEATH_PARITY_20261008`, `FALL_CAM_20261008`, `DEV_REVIVE_20261008`.
- **Server (`Level5PreviewAccess`)**: the corridor's stay-dead flow (`finaleDeath`, `record.dead`, the party tally
  with its 15 s window) now takes EVERY death. `ZyntraReentryUsed` is false from `Void.Join` and true after a paid
  re-entry: one per run, as in every level (the corridor no longer re-arms it). A fall (40 studs under the stretch
  reached) is first SHOWN: `record.fallingAt`, event `"falling", 2.4`, and only 2.4 s later `Health = 0`. Causes for
  the death card: `L5Fall` (new in `DeathAdvice`), `L5Crusher`, `Unknown`. `reenter(player, free, forced)` stands a
  player at the FIRST checkpoint of the section they had reached and sets `record.cp` back to it (the fall line is
  measured from the checkpoint held: a later one's would kill the body where it stands); a death past the
  corridor's doorway (`record.deadInFinale`) still stands up in the small room. A dead member is no longer waited
  for on a plate. `living()` also refuses a humanoid in the Dead state: the body's own Health script heals a
  corpse (0, 1, 2, 3 ... measured), and a corpse now stays in the level.
- **Developers**: the free re-entry is the one every level has (PARTY DOWN card and the store's re-entry modal,
  `DevAccess.IsAllowed`, through `ZyntraReentry` -> `Level6Reentry` -> `Level5Reentry`). New: `Level5VoidHud.DevRevive`
  ("DEV · REVIVE THE DEAD", the U key) under the DROP A BODY button, for `DevAccess.IsLevel6PreviewAllowed` (which
  has the owner's own account on it): `Event "devrevive"` stands every dead player in the level up, free, the asker
  included, and answers `"devrevived", count`.
- **Client (`Level 5 Lighting Controller`)**: `fallCam` (bound after the camera at `Camera.Value + 6`): the camera
  stays where it was, 1.5 studs up, turns down after the body with a small light on it, the cover closes to black
  from half way and the line says YOU FELL. `"died"` now only blacks out for 1.8 s (the death screen, spectating
  and the re-entry are RoundUI's); `"reentered"` clears it.
- **Tested in Studio, solo** (entered through `Level5LaunchParty`): a drop off Rose: camera Scriptable, cover
  closing, dead at 2.5 s, still in the level, `PartyDownCardOpen`, the store's EMERGENCY RE-ENTRY modal (29 R$ / BUY
  CREDIT, SPECTATE), then NO ONE MADE IT OUT and home after the window; the revive button (alive at Rose's first
  checkpoint, card gone); the paid path through `ZyntraReentry:Invoke` (alive, `ZyntraReentryUsed` true) and a
  second one refused; two checkpoints into Amber, dropped, revived at Amber's FIRST checkpoint. **Not tested**:
  two or more players (a dead one watching the living, the plate without the dead, revive of somebody else), a
  real purchase, the FREE RESPAWN // DEV button itself (the Studio test account is not on `IsAllowed`), a phone.
- **A test that waits past the 15 s window finds the player back in the lobby** and then moves a lobby avatar
  about: check `Level5VoidRound` before driving a body.
- **Level 4 bay posters** (`POSTER_CASE_20261008` in `tools/level5_void/build_bay.py`; owner, with a picture: "they
  are placed on top of the old ones and it looks like shit"). The two old poster cases on the bay's back wall are
  baked into the decor mesh `BayDecorLevel4` (one mesh, one texture). The 2026-10-04 one-sheets stood 0.25 studs
  in front of them, a whole stud to one side and 1.7 taller, so the old gold frames showed round them. Each sheet
  (5.2 x 7.8, 2:3) now sits on a dark housing `PosterCase` (5.7 x 8.25 x 0.86) that swallows the old case and is
  0.13 proud of its face. The two posters further round the wall have no old case behind them and are unchanged.
- **Reading a baked kit mesh**: the lobby kit has no mesh assets (`RuntimeBake` builds it per server), so
  `CreateEditableMeshAsync` on the placed part fails. Its source is `ServerStorage.LobbyReimaginedBlenderSource
  20261001R4`: `ManifestJSON` and `Meshes/<chunk id>` are folders of StringValue pieces (base64 of zstd); a raw
  mesh is `u32 magic, nv, nn, nu, nf` then `nv` float32 triples. Decoding it in an Edit `execute_luau` and listing
  the distinct coordinates per axis gave the old case's rectangle: x 5.4..10.6, y -1.6..5.4, z -2.24..-1.61 about
  the part's centre, which the Builder stands at bay (0, 5.4, -21.99) since the seat row's 1.5 stud move.
- **Seen while checking the posters (2026-10-08, 08:10)**: with the play session at 7 GB and swap full, the client
  drew the lobby kit's baked atlas on NOTHING (seat row, desk and furniture plain beige) although every part's
  `TextureContent` was the opaque baked content on server and client; the session before it drew them. A
  memory artefact of this Mac, not a fault in the place: do not chase it, restart Studio. `TextureID` is empty
  for such parts, so "has a texture" has to be read from `TextureContent.SourceType`.
- **`Level Leaderboards` asks no data store in Studio**: Studio has no API access here and the engine itself
  prints every refused `GetSortedAsync`, pcall or not (six lines every few seconds).
- **The poster fix and the Level 5 death flow went into Studio at 08:13 and were waiting for a publish** when this
  was written (`/tmp/live/publish_when_idle.sh`: three minutes of idle, then Codex clicks File > Publish).

### Added 2026-10-08 (later in the morning) - Passes count on TOP SUPPORTERS; a warning behind the fence (in Studio, NOT published)

- **The owner published v2813 at 08:30** (Studio's log): the Level 5 death flow and the Level 4 poster cases are
  live. They wrote "I will publish on my own" while the idle-wait publish job was pending; it was cancelled.
- **Owner**: "make sure the TOP SUPPORTERS leaderboard is updated with the latest buys and such".
  **What was wrong**: the board is `recordedSupportRobux` = `DonationRobux + UtilityRobux + PassRobux`, synced to the
  ordered store `ZyntraDonationLeaderboard_v2`. Developer products have always been added at their receipt. A GAME
  PASS never was: `PassRobux` had no live writer, only the one sales import of 2026-09-15
  (`artifacts/trello-20260915/agent-36-report.md`; its module `ServerStorage.ZyntraSalesBackfill` is no longer in
  the place). So every pass sold since (detector, Advanced Equipment, the token earners, skins) was missing.
- **Now** (`PASS_SPEND_20261008`, a block at the end of `refreshPasses` in ZyntraMonetization): each pass a player
  owns (`ZyntraOwns<Key>` true: `Config.Passes`, game-pass donations, Robux skins, the six token earners) is added
  ONCE, at its listed price, under the marker that import prescribed for a pass: `pass:<pass id>` in
  `data.SalesImport.Rows`, so neither path can count one twice. It runs at every profile load (which also picks up
  passes bought on the website or before this existed) and right after a purchase in the game; then
  `queueSupportTotalSync`. Not in Studio (GrantAllPasses) and not for LaverSneglen's unpaid Advanced Equipment.
  **Limits, said to the owner**: a buyer is counted when they are next in the game, not before; the amount is the
  listed price, so a regionally priced sale reads a little high; the 20K support pass (1978617781) is not in the
  config and stays as imported.
- **ZyntraMonetization is at about 195 of Luau's 200 top-level locals**: the new code is a block inside
  `refreshPasses`. Count before adding a `local` at the top level of that script.
- **Tested**: the transform against stand-in profiles (six cases: two new passes, the same again, one already
  imported, nothing owned, a pass listed twice, the safe limit); the script boots and loads a profile in Studio.
  **Not tested**: the real write (Studio skips it by design) and the board changing on the live game.
- **Owner**: when players hop over the fence and the eyes start shining, a couple of seconds later a text on their
  screen, "You are in danger, get back to safezone", blinking in red, not in a big font.
  `REACH_WARNING_20261008`, a block at the end of `Lobby Tunnel Reach Client`: ScreenGui `TunnelReachWarning`, one
  line (GothamMedium 16, red 255/64/56, 16% from the top), shown to the player who is over the fence (the server's
  own test, from `LobbyTunnelReach.Fence`) once they have stood there 2.5 s with `Awake` and the eyes more than half
  open; it blinks once a second (steady under `ReduceFlashing`) and goes when they are back or taken.
  Tested in Studio: off in the lobby, on and blinking behind the fence, off again 1 s after stepping back.

### Added 2026-10-08 (morning, later) - "Being Kind to Luna": an achievement with a gift (in Studio, NOT published)

- **Owner**: the first time somebody pets Luna in the lobby, a little achievement pops up, "Being Kind to Luna", with
  "+5 gifted tokens for being kind to Luna", and the 5 tokens are theirs at once; and: "people that have pet Luna
  before will get it on the next pet". Marker `LUNA_KIND_20261008`.
- **An achievement row may carry a gift**: `Tokens = n` and `Reward = "<line for the toast>"` on its row of
  `ZyntraConfig.Achievements`. `achievementApi.unlock` adds the tokens in the SAME write that records the unlock,
  behind the same "already has it" check, so it is paid exactly once per profile; an unlock whose write failed is
  not shown (the next pet tries again). Rows without `Tokens` behave as before. Nothing recorded earlier pets, so
  every player earns it on their first pet from this build on.
- **Key `LunaKind`** (`Badges.LunaKind = 0`: no Roblox badge yet). `LunaTribute.playerPlays` fires
  `ServerStorage.ZyntraAchievement` for it: that function is both the pet and the belly rub.
- **Achievements Client**: the toast has a third line (`Reward`, teal, 86 px high instead of 76); the panel's grid is
  `max(5, ceil(count / 4))` columns, so 21 to 24 badges are six narrower tiles a row and never a fifth row (it
  would run over the footer).
- **Icon**: a paw with a heart, drawn in `tools/badges/build_badges.py` like the other twenty (21 now);
  `tools/badges/upload_icon.py <Key>` uploads a badge icon to the group through Studio (`CreateAssetAsync`; it reads
  any 8-bit PNG, Chrome's included) and keeps ids in `icon_ids.json`. Image 75034771348605.
- **Headless Chrome hung once** in `build_badges.py` (normally 3 s a picture) AFTER the script had emptied the
  Desktop badge folder; `shot()` now gives up after 40 s and asks again.
- **Tested in Studio, solo**: pet through the real prompt: `LunaKind` unlocked, tokens 35 to 40, the toast with icon
  and both lines, the lobby's token counter at 40; a second pet (walked up to her, she sat and followed): tokens
  still 40, no toast; BADGES panel 2 / 21, the new tile lit, nothing over the footer; console clean.
  **Not tested**: the saved write (Studio keeps profiles in the session only), the belly rub (same function), a phone.
- **`/tmp/l2sign/run.py` must be run from the repo root** (it imports the Studio client by relative path). A play
  test started before the mute call is audible for those seconds: start play and mute in one command.

### Added 2026-10-08 (midday) - Phone and tablet QA; own servers for everyone; the board says 12 hours (in Studio, NOT published)

- **Owner**: "test the game on phone and tablet and make sure it all plays, all levels, all UI", then, mid-run:
  own servers for Levels 5 and 6 "from now on" (no developer test first: "same setup as the other levels"), the
  Level 2 board to say under 12 hours, and the four shared HUD faults from the Level 6 phone audit fixed.
  The record, with every picture, is `artifacts/mobile-qa-20261008/README.md`. Marker `MOBILE_QA_20261008`.
- **`ServerKind.OwnServers = "everyone"`.** Every Level 5/6 party gets its own lobby server and a Level 4 clear
  offers CONTINUE into Level 5. The cross-server path has still never run (it cannot in Studio); a refused
  reservation falls back to the lobby server behind the one-party lock; `"off"` is the way back.
- **Level 2 board**: "within 12 hours" in all seven languages (`LEVEL2_MAINTENANCE_20261008`).
- **`tools/mobile_qa/qa.py`** drives a session: `play` (starts and mutes in one go), `audit <state> [WxH ...]
  [--shot] [--as <ScreenGui>]`, `run`, `shot`, `stop`; `digest.py <state>` folds the reports; `known.txt` holds
  findings that are not faults; `read_studio.py` copies a drifted script to a scratch folder without touching
  the repo. Helpers for standing in each level are described in the artifacts README's sources (`/tmp/qa`).
- **What the audit taught**:
  - Positions must come from `UIDevice.Layout()` (`Safe`, `ModalViewport`, `Zones`, `TopBand`), never from
    `workspace.CurrentCamera.ViewportSize`: the camera counts Roblox's top bar, a ScreenGui's own space does not.
    That one mistake put two lobby buttons off the bottom of every phone.
  - A lobby window belongs in `UIDevice.SCREEN_OWNING_MODALS` AND in `ZyntraStore.RAIL_WINDOWS` (with a
    `Close...` BindableFunction in PlayerScripts): the first docks the token pill and raises the rail, the second
    lets a rail press close it. The L4 windows refuse to open over somebody else's modal.
  - **Do not make an in-round panel a screen-owning modal.** With movement suppressed the touch cluster does not
    go away, it re-forms as a column (tried for Level 4's keypad: SNEAK/RUN/JUMP landed on the objective card).
    Publish a plain attribute and let the chip and slots opt out (`Level4CardOpen`, `LevelOneGuideObjectivesOpen`).
  - The suite's scenario setups (`UIRegression.Scenarios()[n].Setup`) stage panels in the LOBBY; called inside a
    real round they corrupt the client's round state. Use them in a lobby session only.
  - The Lucky Wheel disables every ScreenGui but three, by name: the phone view survives it as
    `--as FriendBoostGui`.
  - Scale-laid-out pieces (the wheel's grafted title) cannot be judged under the fixture: the real ScreenGui
    keeps the host's size. Their rules were checked by arithmetic for a real phone, not seen.
  - `#Source` counts bytes, the Mac audit tool characters: a script with box-drawing comments "changes size"
    between the two. It was not another session.
- **ZyntraStore, Zyntra Shop L4 and RoundUI in the repo were brought level with Studio** before editing (another
  session's rewrite of the store: 201 KB to 58 KB, the shop in its own script).
- **Memory on this Mac decides the pace.** Studio holds 5.7 GB in Edit mode with this place open; a play session
  adds a server and a client. The desktop app's own WebKit process grew to 5 GB over the session as pictures
  were read. Short sessions, a Studio restart every few, few pictures read.
- **Owed**: the portrait decision (lock to landscape, or portrait layouts for the L4 windows), a real phone, and
  watching the first public parties on their own Level 5/6 servers after the publish.

### Added 2026-10-08 (afternoon) - No more jumping in the air on touch; Level 5's fall is judged by the route (in Studio, NOT published)

- **Owner**: "People can double jump and some infinity hop, fix that ASAP", and in Level 5 "after the green section
  the player goes into third person without clicking and then it just fades to black"; then: "I was noclipping in
  the level but stayed above ground".
- **The double jump was the touch JUMP button** (`TOUCH_JUMP_GROUNDED_20261008` in NoiseReporter). It forces
  `ChangeState(Jumping)` because the control module overwrites `Humanoid.Jump` every frame, and a forced state does
  not ask for ground: every tap in the air was another jump, tapping on was flying. It now jumps only from
  Running / Landed / GettingUp with a floor under the feet, or from a ladder or water, and not twice within 0.4 s.
  Keyboard and gamepad go through Roblox's own jump and never had it. Measured with real taps on the button
  (`user_mouse_input` on `PlayerGui.StaminaGui.TouchJump` under `ForceTouchUI`): 18 taps gave 9 jumps, each from the
  ground, the body never more than 7.8 studs up (one jump is 7.3).
- **The Level 5 fade was the fall camera on a body that had not fallen** (`FALL_TRUTH_20261008`). A fall was judged
  only against the last checkpoint a body had TOUCHED: 40 studs under that stretch's lowest tread. Violet is the
  first room that goes down (65 to -3), so anybody who had passed Violet's first two landings without touching
  them (the owner noclipping over them; a phone player hopping over them with the jump bug) was "40 under Mint"
  while standing on Violet's own treads. The camera let go, the screen closed, and if the body touched a later
  landing inside the 2.4 s there was no death and NOTHING ever opened the screen again.
  - Server (`Level5PreviewAccess`): before a fall is called, `routeAhead` looks for the route segment the body is
    on or over (within 14 studs in plan, feet from 3 under to 12 over it) and reaches the checkpoints up to there.
    A fall has to BEGIN as one (vertical speed under -25) and is taken back (`"fallover"`) the moment the body is
    on the route or over the line again. A body in the `DevNoclip` collision group (GameManager's
    `setServerNoclip`) is never falling. An honest player always holds the right checkpoint, so nothing changes
    for a real fall.
  - Client (`Level 5 Lighting Controller`): `fallCam.open()` on `"fallover"`, and by itself 4 s after the fall
    time if nothing followed: the screen may never stay closed on the fall camera's account.
  - **The fall camera broke Roblox's own camera script on the way out.** It ends looking straight down, and
    `BaseCamera` takes asin of the look vector's Y: a hair past -1 is NaN and it then threw on EVERY frame
    ("BaseCamera:686 ... max must be greater than or equal to min") with the view left where the fall camera had
    put it. This was live since v2813. The view is now handed back with the direction it had before the fall
    (pitch held within 60 degrees). **Any Scriptable camera that may look straight up or down must do the same
    before it sets `CameraType = Custom`.**
- **Tested in Studio, solo** (two sessions): Mint's last landing touched, then stood on a Violet tread between
  landings 17 and 18: no fall, checkpoint 17 reached, alive; a fall sent and taken back: camera and screen back
  at once; a fall sent with nothing after it: screen open 6.4 s later; a body in `DevNoclip` dropping 280 studs:
  no fall; a real step off the tread: fall camera, dead after 3.5 s, death card, 0 camera-script errors.
  **Not tested**: a whole honest walk of Violet after the change (nothing in it runs unless a body is under its
  line), a real phone, more than one player.
- **Open**: times set by hopping or noclipping may already stand on the Level 5 board (developers are not
  excluded in Levels 5 and 6, and a hopper could skip everything). Not looked at.
- `user_mouse_input` (MCP) clicks a GuiButton by instance path in a play session and fires its `Activated`:
  the way to test a touch button without a phone.

### Added 2026-10-08 (afternoon, later still) - The game's own numbers: reach is not the bottleneck

- **Owner**: "How can we make it go viral otherwise?" Read first (snapshot:
  `artifacts/promo-20261007/game-metrics-20261008.json`): 16 to 84 daily players over the last two weeks (50 on
  2026-10-06), about 12 500 monthly, so nearly everybody who came in the last month came once; an average session
  of about 6 minutes; next-day return between 0 and 12%; return after a week 0% on every day read. The game's tile
  was shown to 2 000 to 8 000 people a day. The answer given: more reach into this funnel does not compound; find
  where the first session ends, then the invite loop, clips of the moments worth filming, and a Halloween update.
- **Metric names the analytics gateway takes** (same call as the locale query of 2026-10-08, breakdown empty,
  `METRIC_GRANULARITY_ONE_DAY`): `DailyActiveUsers`, `MonthlyActiveUsers`, `Visits`, `D1Retention`, `D7Retention`,
  `D30Retention`, `ForwardD1Retention`, `AverageSessionLengthMinutes`, `AveragePlayTimeMinutesPerDAU`,
  `TotalPlayTimeHours`, `DauMauStickiness`, `UniqueUsersWithImpressions`, `RFYPlayThroughRate`, `PayingUsers`,
  `AverageRevenuePerUser`. Not available for this universe: the `SessionDurationSeconds*` percentiles and
  `PeakConcurrentPlayers`; `Visits` cannot be broken down by `AcquisitionSource`. The dashboard's scripts name
  about 200 more (funnels, share links, thumbnails); `Revenue` did not answer in 90 s.

### Added 2026-10-08 (afternoon) - Developers are off the TOP SUPPORTERS board (in Studio, NOT published)

- **Owner, with a picture of the board**: "Why is MikkelCzar and LaverSneglen on the supporter board?" (MikkelCzar
  first with 21 942 R$, LaverSneglen third with 149 R$).
- **Cause: `PASS_SPEND_20261008` of the same morning.** It credits every pass an account OWNS at its listed price,
  and Roblox answers "owns" for the account that created a pass. 21 942 is exactly the four passes of
  `Config.Passes` (496), the six token earners (1 347), the 20 000 R$ support pass and one 99 R$ skin: MikkelCzar
  paid none of it. LaverSneglen's 149 is one 149 R$ pass that account owns (which, and whether it was bought, was
  not looked up). I had also written that the 20K pass "is not in the config": it is (`Donation20K`, a game pass).
- **Fix (`SUPPORT_BOARD_NO_DEVS_20261008`, four places in ZyntraMonetization)**: the three developer accounts
  (`DevAccess.IsLevel6PreviewAllowed`: mikkelczar, LaverSneglen, ZenMeister02) are never shown
  (`publishSupportRows`), never written (`syncSupportTotal`), their rows are REMOVED from the ordered store when a
  refresh meets them (it reads three rows more than it shows; the store only ever raises a total, so a wrong row
  has to be removed), and `PASS_SPEND` no longer runs for them. Their own profiles still hold the credited
  `PassRobux` and markers: not reset.
- **Tested**: thirteen stand-in rows with the three developers among them gave the ten others in order; the
  script boots, loads a profile and publishes the board in Studio, no errors. **Not tested**: the real store (Studio
  does not touch it): the removal and the live board after the publish.
- **Owning is not buying for a pass's creator.** Any future "count what they own" rule has to leave the developer
  accounts out, or ask the purchase history instead of ownership.


### Added 2026-10-02 - Level 4 round "Den Sidste Forestilling" (developer-only)

- **Level 4 is a round now, for DevAccess parties only** (`GameManager` `LEVEL4_PUBLIC = false`, `devCeiling` /
  `canAccessLevel` check every member; `Routing.DevMaxLevel = 4` lets the explicit ceiling through, `NextLevel` still
  stops at 3). `LEVEL_GENERATORS[4] = "Level4RoundGenerator"`; the old `Level4Generator` module is the unrelated
  preview builder. The old lobby's Level 4 stations (LaunchZone13-16) launch it. **The new lobby's Level 4 bays
  (revised ids 113-116) offer the host TWO launches** (owner decision 2026-10-02, `LEVEL4_QUEUE_CHOICE_20261002`):
  TRIAL ROUND (the real round) and MAP PREVIEW (the dev map preview, no entity). `queuehost` carries the offered modes
  ("trial,preview"), `ConfigureQueue` takes the mode as a 4th argument, the choice flips `station.previewQueue` for
  one session (`resetStation` restores it); an unavailable explicit choice is refused and re-offered, never swapped.
  RoundUI shows the split row through the shade attribute `QueueLaunchModes`. QueueBridge is unchanged.
- Systems, contracts and the QA harness: `tools/level4_blender/README.md` "Level 4 round". Round Entry Client accepts
  Level 4 and grounds it on the cinema.
- **`Workspace."Level 4 Cinema Blender".Collision` must stay a Persistent Model** - a streamed client drops the
  755 x 480 stud floor part and players fall through it.
- **A Level 4 clear is a tracked clear** (owner decision 2026-10-02): `LevelsCleared["4"]`, the daily Clear goal,
  records/challenges (`Challenges.Levels` has 4, goal 12:00) and `Badges.FirstClearLevel4` (0 until the badge exists).
  CampaignComplete still names 1-3. Literal 4 at both Monetization sites: offline harnesses copy only parts of the
  file. RECORDS hides the Level 4 card until the profile has Level 4 progress (`Challenges.HiddenUntilPlayed`).
  Publish with "Migrate To Latest Update": an old-build server would strip Level 4 entries on its next profile write.
- **ProximityPrompt's default Exclusivity (OnePerButton) only shows the CLOSEST prompt for a key**: prompts stacked
  close together (the three switches in a POWER cabinet) are unreachable except the nearest. The switch prompts sit at
  eye height in front of the cabinet, 3.5 studs apart (`placeSwitchAnchor`).
- The POWER cabinets are 10-stud wall boxes mounted 7 studs up (handles 8-15 studs above the floor): a visual/asset
  question for the owner (moving props needs a decision); gameplay works through the eye-height prompts.


### Added 2026-10-08 - the new Level 2 map after the owner's feedback (published v2838)

- `Workspace."Level 2 Poolrooms New (preview)"` was rebuilt from the Blender feedback build (F1..F22 in
  `G:\Blender\Level2_Poolrooms_New_20261006\docs\OWNER_FEEDBACK_2026-10-07_ROBLOX.md`; log `docs/ROBLOX_IMPORT.md`).
- **It writes Roblox Terrain water** for its 9 pools in recorded regions (model attribute `L2NTerrainRegions`) at x~70000.
  The Terrain water LOOK stays place-wide on the server; the preview client sets its own look while inside the map.
- **Preview body:** EXPLORE NEW MAP sets the server-owned player attribute `Level2NewMapPreview` and loads the round body
  through `ServerStorage.LoadGameplayCharacter`. GameManager, DevCheats, HazmatSkinVisuals/Driver and FlashlightSync/
  Controller treat the flag like a round: first person, hazmat skin, round torch. It is cleared on RETURN TO LOBBY, the exit
  slide, death and leaving.
- **Death holes:** `Collision` parts named `Hazard` with `KillZone=true` (the 5 A3a pits and the A3b drain); the server loop
  in `Level2BlenderPreviewAccess` kills on entry. Owner 2026-10-08: the Level 2 round will have no entity; death = falling into
  a hole (the HUD session's `DeathAdvice` "L2Hole" key is meant for that round).
- **Colliders are all invisible.** Guards and fall barriers sit in `Collision.Guards`: exclude it from gameplay raycasts.
- **Owner tweak, published v2850 (2026-10-08 evening):** the preview arrives at marker `SPAWN` (the kiosk, in front of
  Level 1's door, top of the stairs, facing +Z down the stair core); RETURN TO LOBBY sits on SPAWN, P0_00 and EXIT. The
  client grade is a touch lighter (Brightness 0.9, Ambient 20,24,25, Exposure -0.05). Record:
  `G:\Blender\Level2_Poolrooms_New_20261006\docs\ROBLOX_IMPORT.md` "Owner tweak".
- **Roblox draws Terrain water low where a column borders Air.** A Terrain water column next to an Air column, sideways
  or at the end of a pool, is drawn 0.5-1.2 studs below its voxel surface. A column with water on every side sits on its
  occupancy height. So a narrow channel (P2's is 10 studs on the 4-stud grid) needs its water body to reach one voxel
  into hidden space (under the walkway, behind a wall). Judge water by Play raycasts of the drawn surface (`IgnoreWater =
  false`, Terrain only), never by `ReadVoxels` or occupancy maths: the occupancy model passed a version that failed in Play.
- **Owner asks, installed 2026-10-09 (not yet published):** the A2 lion rotunda has a skylight (server-built `A2 Skylight`
  Beams + the moved spot A2_BeamCone on the gold disc; the developer client's grade puts the sun over the oculus only
  inside the rotunda: ClockTime 12 at GeographicLatitude 23.5, the place's own 0 elsewhere). The exit slide is a whole ride
  (World Builder builders at EXIT_SLIDE) and its finish fires RoundUI's own `"win"` (LEVEL 2 CLEARED, no buttons) then the
  lobby. **`Level 2 Slide Controller` rides any body with `Level2NewMapPreview`** (its Level 3 continuation branch needs
  InRound), and **RoundUI's win title says LEVEL 2 for that flag** (one operand, no new local). Record: the Blender
  project's `docs/ROBLOX_IMPORT.md` "Owner asks".


### Changed 2026-10-09 - approved Poolrooms is the normal public Level 2

- The owner's "live Level 2" request promotes the six-area authored Poolrooms into the ordinary queue/campaign path. `DevAccess.Level2Public = true`; the Level 2 maintenance builder block, physical queue barrier and both developer preview entry controls are removed. Existing R3 queue ids 105-108 remain normal party queues.
- `ServerStorage.Level2PoolroomsMap` is adopted as `Workspace."Level 2 Generated World"` by the replacement `Level 2 Round Adapter`; Cleanup stores the same model again. Its 30,869 descendants, nine Terrain-water regions (74,987 occupied water voxels), six measured arrival slots, fitted A2 reflector and reflected lion light remain intact. Old kit/map versions are archived. The old preview access/client names and kit/layout generator modules are retired; `Level 2 World Builder` remains for its exported slide helpers, while its old Build entry point refuses procedural generation.
- `Level 2 Poolrooms Runtime` owns hole deaths (`L2Hole`) and the native finite exit slide. There is no enemy or pump objective. Completion keeps `Level2_ExitTransition` for GameManager's normal rewards, post-win Continue and Level 3 tube arrival, while finite runout motion/ragdoll stops and transition respawns recover to its safe floor.
- `Level2PoolroomsPresentation` applies the approved client lighting/water/flicker/camera behavior to ordinary Level 2 players; no developer allowlist or preview body flag is needed. `Level2NewMapLightingOwned` continues to make RoundUI yield the grade and releases on lobby/Level 3 arrival.
- Native Studio QA passed two actual queue starts, hazard death and native reentry, physical exit rides, transition death/recovery, Return Lobby, and Continue into a healthy active Level 3. Fresh Edit source/editor/mirror/candidate/manifest parity passed for eleven installed sources and five retired names. Shared regression checks: queue 283; loading host 98; Level 4 bays 469; routing 15 module + three source assertions. Single-player Studio QA does not claim production TeleportService transport or real multi-client replication coverage.
- `Level 2 Pool Foam Client` now rejects the authored no-entity map before its legacy report loop sends anything. Actual handler coverage passed 2,078 assertions (2,048 authored-map ticks, zero reports; old handler fails). A third actual queue run counted zero `ClientReport` events over 30.0155 seconds with Level 2 active and the player in the round, without Foam queue warnings or engine errors. Scoped receipt, original source and exact installed readback are under `clientreport-fix/`.
- Record: `artifacts/level2-live-20261009/README.md`, `final-verification.json`, `verified-installation.json`, `scene-verification.json` and `qa/`. **Published v2883 on 2026-10-09 at 13:56:34.612 UTC / 15:56:34.612 Copenhagen**, following the owner's live promotion request. Studio Output explicitly confirms publication and names v2883; evidence is `publication-output.txt`, `qa/published-v2883.jpg` and `public-receipt.json`. The pre-publish backup is `backup/BACKROOMS-Level2-public-20261009T1553.rbxl` (45,411,778 bytes; SHA-256 `a4ee0f0bd51016f6e672db0ced72fc7b8706ce449b55afb264c9eaf7b84690cd`). Historical preview notes above describe their earlier versions and are superseded by this promotion.

### Added 2026-10-10 - Level 2 water turned down; Level 1 streamer feedback; Level 6 post ring (published v2935)

**Where this work is.** Branch `codex/poolrooms-audio-20261009`, worktree `/Users/zeanjuul4/Projects/stayquiet-poolrooms-audio-20261009`
(sparse; based on origin/main `46073662`). It is NOT merged into `main` and NOT pushed: the checkout at
`~/Projects/Roblox Horror REPO` is one commit behind origin/main, carries the owner's undecided deletions and has untracked
files this branch tracks, so a merge there needs the owner's word. A session that starts in that checkout reads STALE
scripts: read and edit the mirror in the worktree.

- **Level 2 water** (owner: the wave sounds "right down to a very low level", then the wade strides too). The lapping bed
  `bed_water` 0.55 -> 0.06 and `shot_splash` 0.6 -> 0.3 in `ReplicatedStorage.Level2Poolrooms.Plan` (revision v2; measured
  in play: 0.060 in A1); `LEVEL2_WADE_CORE_VOLUME` 0.49 -> 0.16 and the resistance loop 0.095 -> 0.03 in SoundController
  (`WADE_QUIETER_20261010`; NOT measured in play: the test character would not walk). Which master was "the waves" was
  settled by measuring the nine files, not by listening: `bed_water` is the only one with a rise-and-fall lapping pattern.
- **Level 1 is 32 x 32 cells** (`MAZE_SMALLER_20261010`, was 40): side -20%, floor -36%. `floor(GRID/2)` must stay even
  (the two guaranteed lamps at the elevator). Pit zones keep 3 cells off the Entity's corner; the forced plaza is re-rolled
  off the elevator. NOT changed, owner's call: the Level 1 time goal (480 s) and the leaderboard times set on the big map.
- **Fuse puzzle** (`RELAY_OPEN_20261010`, `RELAY_FINDABLE_20261010`, `LEVER_PATH_20261010`): the relay's glass door
  (`RelayDoor`, `ReleaseHandle`) is gone; each relay has a black FUSE sign with a pictogram (`RelaySign`), a dark
  `FuseBacking` plate behind the fuse, an amber lamp bar and an amber ceiling cluster; one relay is guaranteed 4-6 cells
  from the elevator; the fuse box says INSERT FUSE / POWERED and then FOLLOW CABLE / TO THE LEVER; the lever has a sign
  (LEVER / PULL / ON), a cool-white beacon, a ping and the attribute `LeverState`; the cable current is a bead about every
  40 studs while powered. Light levels were LOWERED after looking from the player's own view: the first values washed
  the cabinet and the lever wall out to white. Under the Blender skin the visible cabinet is a kit mesh: recolouring the
  proxy parts (`InnerPanel`...) changes nothing, a NEW part is skinned as a metal panel in its own colour.
- **Mimic** (`MIMIC_DARK_20261010`, RoundUI, no new top-level local): nothing rolls until the ambient luma has been 0.16
  or under for 20 s (two thirds of the relays out, or the red alert) and the spot must be out of every working lamp's
  throw. Studio readbacks on the player: `MimicGate`, and `DevMimicProbe` -> `DevMimicProbeResult`.
- **Entity** (`ENTITY_UNSTUCK_20261010`, `ENTITY_SCREAM_20261010`): nav knows the elevator, holds at the nearest
  reachable cell instead of walking at walls, parks its body clear of walls, a watchdog replans / re-seats / gives up
  (`workspace.EntityStuckCount`, `EntityReseatCount`), the lunge cannot end in a wall. The scream is one positional sound
  for everybody in reach: the server sets `EntityHowlPos` then bumps `EntityHowl`; reach is 1.25 cells to 0.30 x GRID
  cells (230 studs at 32). The Entity model is Persistent. Its visible body is 8 studs wide on a 2-stud collider: arms
  still pass through wall corners in a chase.
- **Entity motion** (`ENTITY_MOTION_20261010`): see `tools/level1_entity/README.md`. Six clips as data in
  `ReplicatedStorage.Level1EntityMotion.Clips`, played by the new LocalScript `"Level 1 Entity Motion"` over the server
  Animator. `SoundController` now follows each round's new Entity for its growl and steps (`watchEntityRoot`).
- **Exit compass** (`EXIT_COMPASS_20261010`, RoundHud): "EXIT 163 m" in the door's green; reaches Level 3 and 4's GET OUT.
- **Camcorder look** (`CAMCORDER_20261010`, Found Footage HUD): a grade under `workspace.CurrentCamera` (it composes with
  each level's own grade in Lighting: compared on and off), a tape date stamp and a soft vignette (`FoundFootageLens`,
  DisplayOrder -1 is valid). It never lifts black and the stamp shows the tape's clock, not the player's. Default on;
  the only off switch is the player attribute `CamcorderFilterEnabled == false` (a settings row is the follow-up).
- **Level 6** (`POST_RING_20261010`): `model.Finale_PostRing`, 32 cord segments and a lamp on the post, built by the game
  module per session: dim red when a touch would not count, red when it would, green for 2 s on a counted touch; stepping
  inside 8.8 studs is the touch (was 7); the lamp sinks with the post.

**How it was done, worth repeating.**
- Mapping and two of the implementation groups ran on Claude subagents, which hit the 5-hour session limit at 00:45 with
  nothing written. The rest went to **Codex 6.1 Sol at effort ultra**: `codex exec -m gpt-6.1-sol -c
  'model_reasoning_effort="ultra"' --skip-git-repo-check -C <dir> -o last.txt "$(cat prompt.md)" < /dev/null`. Each job got
  a plain COPY of the mirror (no git, so nothing can be committed or swept up), a design brief on disk, the files it
  owned, and a second Codex job reviewed it adversarially. A code group took 7 to 9 minutes; the Blender animation job 46.
- **Enter a round from a session now**: the pad must hold the player first. Server: `PivotTo` onto the level's
  `QueueZone1` (a part with attributes `LevelNumber`, `QueueDisplayIndex` 1, `R3QueueId` 101 / 105 / ... / 121); 2.5 s later
  Client: `Remotes.ConfigureQueue:FireServer(<id>, 1, "public", "normal")`. Firing the remote alone does nothing.
- **A 12 x 12 test maze**: Server, before queueing, `ReplicatedStorage.MasterTuning:SetAttribute("L1_Grid", 12)` (dies with
  the session; check in Edit that it is not saved). The Entity then sees the player at once: set
  `workspace.TestEntityBlind = true` BEFORE the round starts. Its touch still kills while blind.
  `workspace.TestForceEntityLunge = true` only gives a real dash during a sighted chase.
- **Silence a play test without touching `Sound.Volume`**: move every SoundGroup under a group of volume 0 and give
  group-less Sounds that group. `qa.py play` forces volumes to 0, which hides every level a test wants to read.
- **`tools/mac_merge_push.py`**: repo -> Studio with a three-way merge against what Studio holds NOW, a compare-and-swap
  and a full readback. Another session edited GameManager and PuzzleManager in Studio during this work; both merged.
- `Humanoid:MoveTo` from a Client `execute_luau` and `user_keyboard_input` W both failed to walk the round body in Level 2.
- Continuing from Level 1 into Level 2 inside Studio leaves `workspace.WorldGenerated` false, so the Poolrooms pack never
  starts there. Entering Level 2 from its pad is fine. Not checked on live (a real continue is a new server).
- Studio's play client ran at about 12 frames a second under memory pressure; two timing faults in the lunge only showed
  because of it.

**Not verified in this batch**: more than one player anywhere, phones, how any sound sounds, a real stuck Entity and its
recovery, a natural lunge by eye, the camcorder look in Levels 2 to 6 and on the kill cams, the TAGGED card in Level 6.

### Added 2026-10-10 (evening) - Hip height, Level 2 lamps/brightness/audio, Level 6 feedback, developers off the time boards

- **"Gliding in the floor, almost cannot move" (Level 1 and 2) was one bug: `Humanoid.HipHeight` computed from half a
  body.** The round body (StarterCharacter, R15 with AnimationConstraints) reaches the owning client in pieces and the
  engine, with `AutomaticScalingEnabled`, worked the hip height out of what had arrived (0, -0.097, 0.936 instead of
  2.605). The body sank; in Level 2 it then found the shallow Terrain water and swam. Fix in three places: the place's
  `StarterCharacter.Humanoid` has automatic scaling off and `HipHeight = 2.605` (attribute `HipHeightFix`; a place
  edit, no mirror file); GameManager measures root-to-sole after loading and publishes `ZyntraHipHeight`;
  NoiseReporter (`HIP_HEIGHT_20261010`) holds the humanoid to it. 4 of 4 fresh rounds broken before, 11 of 11 good
  after. Measure HipHeight on a FRESH round start before believing any other theory about slow walking.
- Same push: `POOL_EXIT_20261010` (a swimmer pressed against a pool edge is lifted out) and `CROUCH_LATCH_20261010`.
- **Level 2**: +10% on screen is `ExposureCompensation 0.24` in Level2PoolroomsPresentation (measured +10.4% mean
  pixel value). 360 pit lamps (12 rows down each wall of the five A3 death pits, fading with depth) and `A6 Exit Lamp`
  live in `Level2PoolroomsMap."Owner Props"`; `tools/level2_props/`. Mesh vertex colours MULTIPLY the part colour:
  upload lamp meshes with white vertex colours. Audio: `docs/workflow/next-level2-audio.md`.
- **Level 6** (game module): `AIR_WALK_20261010` (going home between rounds is a real, uninterruptible walk; an
  off-graph approach point needs floor under it), `CHASE_LETGO_20261010` (60 studs for 1.5 s ends a chase, then calm
  pathfinding to the nearest player, 6 s grace), `ARRIVAL_ALL_20261010` (the game and announcements start when
  everyone has passed the Play Zone sign; 90 s wait, 240 s cap). Client: PA and entity volumes halved. Arena: a narrow
  framed way in on the right 9.6 studs past the gate (no nav change), and uprights/posts/hub ring tying the top
  walkways' railings to their decks. `import_arena.py` and `pbr/apply_pbr.py` now find the model in Workspace OR
  ServerStorage (LevelWorldStorage parks maps 4/5/6 in ServerStorage in Edit). Solo play: 0 of about 700 samples in
  the air over rounds 2 and 3. Geometry seen only in a Blender render
  (`~/Projects/stayquiet-session-tools/l6render/`), not in game: Studio's viewport was a 1250x116 strip.
- **Lobby**: `BOARD_NO_DEVS_20261010` in Level Leaderboards: developers (DevAccess) are not submitted, and their stored
  rows are skipped and removed on read. Not testable in Studio (no DataStore there).
- **Shadow entity for Level 2**: concept pictures only, `~/Desktop/Level 2 entity concept/` (13 pictures, five
  directions). Nothing built; the owner picks a direction first.
- Not done by anybody: listening to the new sounds; two players; a phone; the look of the Level 6 changes in game.
- **Not published by this session**: the owner took publishing over that evening (AGENTS.md, Publishing preference).
  Waiting in Studio after v2943: Level 2 audio, the Level 6 changes, the leaderboard change.
- If the Codex computer-use publish is ever wanted again, it must be started with the model pinned (`-m gpt-6.1-sol`, Low,
  `service_tier="default"`): `~/.codex/config.toml` on this Mac defaults to ultra/priority, and
  `tools/agents/start-codex.sh` rejects `--enable`. `~/Projects/stayquiet-session-tools/publish_when_idle.sh`.

### Added 2026-10-10 (night) - Level 2 has an entity: the Shade (in Studio, switch on, NOT published by this session)

- **This replaces "Level 2 has no entity" (owner, 2026-10-08).** Owner, 2026-10-10: a shadow seen on walls and pillars
  for a second, that comes closer from behind and, unwatched, becomes real, comes out of the floor and drags you down
  with its hands; ElevenLabs whispers heard from where it is. Commit `08c2bd4a`.
- **Rule**: it hunts one player at a time from behind (46 studs down to 4.5 in 17 s, 22 s the first time). The hunted
  player holding it on screen for 0.3 s sends it away. The first time it reaches a player in a round it only scares
  (`FirstIsWarning`); after that it kills (`DeathAdvice` `L2Shade`). Nothing in the arrival room, its stairs or the
  first 45 s; never a protected player. Numbers: `Shade.Config` at the top of `Level 2 Shade`. These are my choices.
- **Parts**: server `ServerScriptService."Level 2 Systems"."Level 2 Shade"` (started and stopped by the Poolrooms
  Runtime inside pcall), client `StarterPlayerScripts."Level 2 Shade Client"`, assets `ReplicatedStorage.Level2Shade`
  (`Meshes` 9, `Sounds` 21) built by `tools/level2_shade/install_shade.py`. **Switch: that folder's attribute
  `Enabled`**; false or no folder = Level 2 exactly as before.
- **A mesh uploaded from numbers (EditableMesh -> CreateAssetAsync) keeps its own origin**: the MeshPart's CFrame is
  the mesh's (0,0,0), not its box centre, and resizing scales about that point. Placing by box centre stood the figure
  5.5 studs up the wall. The lamps of the same day never showed it (their offsets are centimetres).
- **A shadow on a pool floor is invisible through a stud of water**: floor shadows and the kill's dark pool are drawn
  on the water surface (client `onWater`).
- **Studio's viewport was 1250x116 all evening.** What worked: roll the camera 90 degrees so the tall thing lies
  along the strip, capture, rotate and crop (`~/Projects/stayquiet-session-tools/l2shade/rshot.sh`, `cam.lua`). A
  strip also clamps the horizontal field of view, so a non-rolled capture is far more zoomed than its FieldOfView says.
- `execute_luau` on the Server gets its OWN copy of a ModuleScript (like the command bar): the test drove a second
  instance of the entity through `_G`. Long waits inside one call (27 s) hang the bridge: poll with short calls.
- Play-test knobs left in the client, all local player attributes: `Level2ShadeTestGlimpse` (true = one glimpse now),
  `Level2ShadeTestSlow` (stretch the kill), `Level2ShadeTestRoll`, `Level2ShadeTestCamera`. Server: `Shade.ForceStalk`.
- `master_v3.py` only takes keys that start `bed_`/`loop_`/`shot_` and paths inside its own folder: the Shade's
  sounds were mastered under aliased keys in `~/Projects/stayquiet-l2-shade/audio` (raw takes and logs are there).
  `shade_hands` (the finger loop) failed the loop-envelope gate in all four takes and is not in the game.
- **Not done**: anyone listening; two players (only the hunted player's look counts, teammates just see it); a phone;
  the kill from the victim's own eyes at full frame; Shade_Reach and Shade_Claw seen in game (the A3 pillars are too
  narrow for them, so every test glimpse was Shade_Stand); whether 32 to 58 s between stalks is the right pressure.

### Added 2026-10-10 (late night) - The Shade: standing still brings it; the face in the dark

- **Owner after playing it**: "Shadow entity er fed, men den skal konsekvent komme efter en bagved en hvis man står
  stille for længe. Står man stille i mere end 10 sek så kommer den efter en og andre spillere kan godt se den, det
  er spilleren den chaser der skal kigge rundt." `STILL_20261010` in `Level 2 Shade`: a player who has not left a
  four-stud circle for `StillSeconds` (10) is hunted at once, every time, with ten new seconds after each hunt. The
  timed hunts (32 to 58 s) stay beside it; that they stay is my reading, the owner did not say either way.
- **Owner**: "via blender animere et meget klamt shadow figure ansigt, som vises når man er blevet trukket ned i det
  shadow realm ... omridset af hovedet og hvide lysende øjne og ingen mund, rigtig ulækkert." After the drag the
  victim's screen is black for `RealmSeconds` (3.4) before the death is counted, and a 36-frame Blender animation
  plays as a flipbook: `tools/level2_shade/build_face.py` (Codex; the first pass at Medium was a clean egg with two
  ovals, the second at High has a skull, sockets, veined eyes and skin drawn in strands over the mouth),
  `artifacts/level2-shade-face-20261010/`, sheets uploaded by `upload_face.py` (ids in `face_ids.json`), published to
  the client as the folder's `FaceSheets`/`FaceFrames`/`FaceFps`/`FaceGrid`/`FaceFrame` attributes by
  `install_shade.py`, which only swaps them in when all four sheets are approved. Without sheets two eyes open.
- `ProtectionHUD` (the Q/Z item keys) has DisplayOrder 1001: a full-screen black has to go above it.
- An ImageLabel that has never been visible reports `IsLoaded = false`; the sheets are preloaded on entering the level.
- The dashboard upload route needs a `create.roblox.com` tab in Chrome. With no Chrome window, `make new window` and
  setting its URL by AppleScript left the game in front (the owner was playing).
- Test knob: local player attribute `Level2ShadeTestFace = true` plays the face alone on black.
- Not done: anybody watching the face at full size in game (seen at 116 px in the letterbox viewport, and as the
  contact sheet); the sounds under it are three of the Shade's existing ones, nothing new was made.

### Changed 2026-10-10 (late night) - The Shade's face in the dark is REMOVED

- **Owner, after playing it**: "The kill cam is horrible. So the last pov with the shadow face and white eyes should be
  removed right now!" Removed within the hour: `RealmSeconds = 0` on the server (the death is counted when the drag
  ends), the client forces `realm = 0` and no longer loads or plays the flipbook (or the two-eyes fallback), and
  `install_shade.py` clears the folder's `Face*` attributes and no longer publishes the sheets. A normal round played
  to a kill afterwards: death 3.6 s after the grab, no face pictures exist on the client, death card as before.
- The Blender work stays in the repo (`tools/level2_shade/build_face.py`, `artifacts/level2-shade-face-20261010/`,
  `face_ids.json`) and the eight uploaded sheets stay in the group's assets, unused. **Do not bring a face back
  unless the owner asks.** They asked for it on the same night and rejected it on sight: a description they approve
  is not the picture they will accept; show a still before building the next thing like it.
- "The kill cam is horrible" may mean more than the face. Only the face was ordered out, so only the face went; the
  drag itself (pool, figure rising, arms, sinking, fade to black) is unchanged and its verdict is still owed.

### Added 2026-10-10 (late night) - New players: a free re-entry, a sleeping Entity, no cabin poster; where phone players go

- **Owner**: "giv alle nye spillere 1 gratis banked reentry og informer dem om ved første død at de har 1 gratis
  reentry de kan bruge. ... entity i level 1 først spawner efter den første fuse relay er taget ud. ... fjerne den der
  board i elevatoren ... Find ud af hvad der gør at telefon og tablet spillere skrider så hurtigt."
- `WELCOME_REENTRY_20261010` (ZyntraMonetization): a first login banks one Emergency Re-entry credit, once
  (profile field `WelcomeReentry` "granted" then "used"; public profile `FreeReentry`; client attribute
  `ZyntraFreeReentry`). Both death screens name it: the PARTY DOWN card's button reads "YOU HAVE 1 FREE RE-ENTRY ·
  USE IT", the store's modal the same. The HUD feed is stood down under a death card, so the button carries it.
  Accounts from before get nothing (the owner said new players). Test in Studio: `workspace.DevSimulateFirstLogin`.
- `SPAWN_AFTER_RELAY_20261010` (EntityAI): from round start until `workspace.Level1RelaysExtracted` leaves 0 the
  Entity is anchored 600 studs up (`workspace.EntityDormant`); the first extraction stands it on EntityStart and it
  screams once. GameManager's own placement at round start is put back up by the same loop.
- `CABIN_POSTER_REMOVED_20261010` (MazeGenerator): the cable-routing poster in the elevator cabin and its refresher
  are gone. GameManager still publishes `Level1ActiveCircuitCount`; nothing reads it for a poster now.
- **Where the bought players go (8 Oct, by device; first rounds = round starts minus relaunches):** phone 1,472
  players, about 176 first rounds (12%); tablet 729, about 183 (25%); computer 366, about 181 (49%). Of those who
  played, a first objective was reached by 68, 44 and 88. `zq_round_start` is logged after the elevator ride, so
  "never started" includes people who left in the queue, the teleport, the loading and the 20-second ride.
- **Code review of the touch experience** (Codex, High, read-only): `docs/reference/mobile-review-20261010.md`. Every
  round action has a touch control. Its ranked reasons: the first round is behind a physical pad and a party dialog
  with nothing that starts it for you; the tutorial card shrinks to 10-12 px text on a phone; on touch the
  objective's directions collapse after six seconds; four waits (queue 10 s, teleport, loading, 20 s lift) come
  before the first task; fixed 620-700 px status labels overflow a phone. Unmeasured: frame rate on a real phone.
- Seen in Studio play as a simulated new player: credit banked, free button text, Entity at y=600 until the counter
  went to 1, then on its mark and a kill, the free re-entry spent (credits 0, alive). Not seen: any of it on a phone.

### Changed 2026-10-10 (late night) - Level 5 is rebuilt for phones (v4): short gaps, checkpoints in the rooms, a fall is not a death, jump assist (in Studio, NOT published by this session)

Owner: "Jeg ved at level 5 er fuldkommen umuligt på telefon" and then "Bare fix og lave hele level 5 om. Gør det
nemmere på telefon og tablet som du siger". This replaces v3 ("much harder", 2026-10-05) and two earlier rules:
"a fall is a death" (2026-10-04) and the fall half of DEATH_PARITY_20261008.

- **The map** (`tools/level5_void/build_level5.py`, v4; the room-by-room rewrite is Codex's, High). 50 gaps (187
  before), every one 40 to 54% of the 8.15-stud walking reach (60 to 95% before), straight (no turn at a gap), with a
  landing at least 7 wide and 14 long (10 x 10 tops in Teal). Walkways are 5 to 8 wide, Mint's beams 4.4. 2,700
  studs long in x (4,373 before), 3,883 studs of route. Ten rooms, same colours, shells, lamps, plates and doors:
  Rose four practice jumps, the first over a pit 2.5 deep that cannot kill; Blue L-ledges and the nested frames;
  Amber touching blocks that step up and down with two +3 hops and one gap; Mint beams, with a guarded no-jump way
  round each of its two forks; Violet terraces you walk off and drop; Coral a stair with no gap; Orange a flat
  square coil in and out; Crimson a square stair two and a half turns round a square pillar; Teal a grid of big
  tops with a second chain; Ivory a square stair five and a half turns round a square column, 10 wide at the foot
  and 5 at the top. The corridor and the end room are unchanged.
- **New in the json:** 161 checkpoints (32 before; one at least every three gaps and 90 studs) with `yaw`; `alts`
  (second routes: two in Mint, one in Teal); parts named `Guard` (946, invisible side walls 8 high along every
  narrow walkway and across each gap's sides; outer side only on Crimson's stair, both sides on Ivory's, which
  narrows away from its column) and `Edge` (100 neon strips on each take-off and landing edge); `hop` on a route
  point that is a jump up onto a touching block. The script asserts all of it. `plan_level5.py` draws one plan and
  side elevation per room into `artifacts/level5-void-20261003/plan/` (needs PIL: `/usr/local/bin/python3`).
- **`import_level5.py`** removes the old model from Workspace AND ServerStorage, builds in Workspace and parks the
  result in ServerStorage (LevelWorldStorage keeps a map nobody is in there). Guards and edges get
  `CanQuery = false`.
- **Server** (`Level5PreviewAccess`, EASY_PHONE_20261010): a fall runs for `FALL_BACK` 0.8 s under the same fall
  camera and the body is stood on the LAST CHECKPOINT it reached, alive, facing along the route (word to the
  client: "returned", frame, count). The old rule is one attribute away: `ReplicatedStorage.Level5Void` attribute
  `FallKills = true`. A body standing on the route BEHIND its checkpoint is never falling. The checkpoint box is
  8 x 8 (11 x 13 reached a later lane's checkpoint from an earlier lane in Orange). The corridor's walls take 21 s
  (15.5). Death in the corridor, a Reset, spectating and the re-entry are as before.
- **Client, jump assist** (the block at the end of `Level 5 Lighting Controller`, Level 5 only): a jump asked for up
  to 0.2 s after the floor is lost is still made; one asked for in the air is kept 0.2 s for the landing; and on
  touch (`UIDevice.IsTouch()`) the body jumps by itself at an edge when a landing is ahead within its reach, and
  hops onto a block up to 4.6 high that it walks into. A step down is walked off. NoiseReporter's touch JUMP
  button fires `PlayerScripts.Level5JumpTap` on every tap. `workspace.Level5AutoJumpAll` (client side, true or
  false) forces auto-jump on or off for a test. On arrival a touch player reads "WALK AT A GAP AND YOU JUMP BY
  YOURSELF"; the first-entry guide's Level 5 line no longer says a fall is death.
- **What the engine taught:** `Humanoid.MoveDirection` stays zero under `MoveTo`, so a test has to give the assist
  the body's velocity (that is what `Level5AutoJumpAll = true` also does). The floor is lost when the body's middle
  is 0.8 past an edge and the state stays Running for another 0.1 s. At sprint speed a 3.7-stud gap is simply run
  across. A forced Jumping state sets the upward speed to 50 whatever the body was doing. After a teleport of a
  thousand studs the room stays black for up to a minute in a Studio capture (the lights are there; a walking
  player does not see this).
- **Tested in Studio play** with a walker that takes each room's route (`tools/level5_void/qa/walk.py`; modes
  manual, early = 1 to 2 studs before the edge, late = a tap 2.5 studs past it, auto = no press at all): all 48
  jumps and hops in all ten rooms in every mode at walking speed, auto also at sprint speed, both of Mint's ways
  round and Teal's second chain; a fall from the tower returned to the checkpoint just passed, facing along the
  stair, 1.5 to 2.2 s after it began; the corridor walked at 12 studs/s reached the end room 3.7 s before the walls
  shut, and the finish gave LEVEL 5 CLEARED. NOT tested: a real phone or tablet, two players, any sound.
  `tools/tests/test_level5_access.py` and `test_death_advice.py` fail as they did before this change (a marker
  missing from GameManager; the known hud_b8 caption check).
- **Left out:** 2-3 layouts per room chosen per round (my own idea in the list given to the owner). The rooms differ
  from each other, and Mint and Teal offer a choice, but a room is the same every round.

### Changed 2026-10-11 (just after midnight) - Level 5: the invisible side walls are gone (in Studio, NOT published by this session)

Owner, after v4 went live in v2979: "Du skal lige fjerne de der usynlige vægge i siderne i level 5, som du tilføjede".

- `build_level5.py` v4.2: `GUARDS_ON = False`. No `Guard` part is made (946 before); the code that lays and checks
  them stays behind the switch. Everything else of v4 is as it was: the short straight gaps, the wide landings, the
  lit edges, the 161 checkpoints, the fall that puts you back, the jump assist.
- Without them a body can walk off the side of a walkway again (they are 5 to 8 wide; Mint's beams 4.4 never had
  walls). A fall costs a few steps, not a life.
- Ivory's stair narrows away from its square column, which left a slot of up to 2.1 studs on the inside near the top.
  The walls used to cover it; now 148 flush stone bands (`Fill`) close it, so the pale stair still narrows to the
  eye and nobody drops through or wedges.
- Re-imported (1,284 geometry parts, 0 guards). Walked with auto-jump in Rose, Mint, Crimson and Ivory: every jump
  made. Not tested: a real phone.
- **Do not add invisible walls to a level again without being asked.**

### Changed 2026-10-11 (night) - Level 1 Entity: the run comes AT you and springs out of the stride; Level 4 reels shine; the lobby creature is heard by distance (in Studio, NOT published by this session)

Owner: "Du skal seriøst fikse entity run/chase animation, som du lavede analyse af en video af tidligere"; "De der
filmruller man skal finde skal lyse langt mere op, så være tydelig når man spotter dem. Der skal også være et hint til
hvor de befinder sig i guide teksten"; "Monsteret efter hegnet, når den bliver vækket kan alle i lobby høre dens lyde,
få det til at fade ud og være næsten helt mute når man er i den anden ende ved spawn".

- **The run (RUN_HUNT_20261011, `tools/level1_entity/work/build_clips.py`).** The owner's film of a live chase, frame
  by frame: head on, RUN_FRONT was a gorilla's waddle (arms out to the sides, feet 1.8 apart, ten degrees of
  side-rock), and just before the spring the Entity stood up straight and stopped coming for half a second. Now:
  track .58 (feet 1.2 apart), hips 3.62, lean 43, list 4, sway .16, yaw 15, bob .66; both hands stay IN FRONT of the
  body below the shoulders and reach at the prey in turn (`run_arm`). A hand reaching forward at shoulder height read,
  from the player's low eye, as an arm waved over the head: that is why they are below the shoulders.
- **The wind-up is the last stride of the run (LUNGE_GATHER_20261011).** `Lunge_Windup` is gait phases .84 to 1.30 at
  the run's speed: the leading foot lands, the body sinks to 3.22 with the swinging foot carried lower, both arms
  swing down and back on an arc, and it ends at that foot's push-off, which is `Lunge_Flight`'s first key
  (`WIND_END`, `windup_end_feet`). EntityAI no longer freezes the body for it: it keeps running at SPEED_CHASE
  straight at the player (it still stops if a wall or a pit comes between). Writing the root's CFrame every frame
  (`faceFlat`) braked it from 26 to 12 studs/s within the stride, so that is only done when it stands.
- **Two things the spring needed once it left from a run (18 to 22 studs away instead of 22 to 28):** its horizontal
  speed is now distance over the arc's own flight time (`lungeSpeed`, 30 to 62) so the arc comes DOWN at the player
  (at 62 it reached them at the top and a catch held the Entity 2.7 studs in the air); and "landed" is being back at
  the launch height coming down, not `FloorMaterial`, which stays stale in the air and called every spring landed
  at 0.28 s, two studs up and seven short.
- Measured in Studio play: 23 to 32 studs/s through the wind-up, then the spring, down on the floor 3 to 4 studs
  (flat) from the player; the client plays Run, windup, flight, moving_land, Run. `workspace.TestLungeAlways`
  (Studio only) makes the lunge roll certain. Judged on the real body from the player's view
  (`render_real.py --views player --dark`); videos in `~/Desktop/Level 1 entity - nyt loeb` ("v3 ...").
  NOT seen: the new run moving in the live game with my own eyes; the owner's verdict.
- **Level 4 reels (REEL_GLOW_20261011, REEL_HINTS_20261011).** Studio already had a reel light from 2026-10-10 that
  was not in this checkout (2.5 over 12 studs, `glow`); my first push put a second `Glow` key in the configuration
  and would have broken the reels: found by the merge conflict, fixed before any test. Now `Reels.Glow` is 3.5
  breathing to 6.0 over 22 studs, with an `Occluded` Highlight (an outline only where the reel is in view) and a
  glint of 20 a second at size 1.4 (`reelShine`). The guide lines put the places first: "Reels: Cafe, Cinema 1
  seats, Women's room" (`Reels.SpotHints`, where in the room; a dropped reel is named by its room), then what is
  carried; a list over 44 characters runs on into the second line (a guide line is one unwrapped line).
- **Lobby creature (REACH_HEARING_20261011).** The comment's distances were wrong: the spawn is 238 studs from the end
  wall and 386 from the eyes, inside the deep emitter's 400. Every sound of the creature (not the kill the taken
  player hears) is now in a SoundGroup whose volume follows the LISTENER's distance into the lobby from the fence:
  1.0 at the fence, 0.85 at 30 studs from the end wall, 0.51 at 70, 0.21 at 120, 0.03 from 180 to the spawn
  (measured in play through the group's `Want` attribute; nobody has listened).
- **The Mac ran out of memory during this** (swap 8.8 of 9.2 GB after about ten play sessions and several Blender
  renders): Studio stopped answering, was killed by pid and reopened with the `roblox-studio:` URL; everything pushed
  was still there. `/tmp/l1batch` had been cleared by the system: it is a link to
  `~/Projects/stayquiet-session-tools/l1batch` now. A backgrounded shell that still holds a `qa.py stop` will stop
  the NEXT play session when it gets there.

### Changed 2026-10-11 (night) - Phone and tablet: a PLAY button in the lobby, an objective that stays, a party dialog and a welcome card that fit (in Studio, NOT published by this session)

Owner, after the UI review (`docs/reference/ui-review-20261011.md`): "Fix alle phone og tablet issues her."

- **PLAY_ROUTE_20261011 (`First Entry Guide`).** The lobby's screen had no way to the game. A PLAY LEVEL 1 button
  stands at the top of the screen in the lobby on every device (not near a pad, in a round, or under a window);
  pressing it sets the player on the nearest LEVEL 1 pad nobody stands on, where the party dialog opens as for
  anyone who walks there. A "START HERE / LEVEL 1" marker hangs over that pad. The welcome card's third page and the
  Help now say so. For a test: `PlayerGui.PlayRoute` attribute `Go`.
- **TOUCH_OBJECTIVE_20261011 (`RoundHud`).** The touch objective is mounted at 1.3 of its design on a tablet and 1.0
  on a phone 780 px wide or more (0.8 before); collapsed, it keeps the first guide line (the next action); a tablet
  does not collapse; the count rides in the eyebrow ("LEVEL 1 . 0/1"). The module must stay ASCII
  (`test_round_hud.py`).
- **Party dialog (`RoundUI`).** TABLET_PARTY: on a tablet the touch dialog is drawn up to 1.4 times larger (a
  `UIScale` named TabletScale). SOLO_WORDING: "MAX PLAYERS . YOU CAN PLAY ALONE". TOUCH_STATUS_FITS: the queue's
  status label is never wider than the safe screen and its text shrinks to its box (it was 620 and 700 px fixed).
- **PHONE_WELCOME_20261011.** On a phone the welcome card is laid out 340 high (452 elsewhere) with the same text
  sizes, so an 844 x 390 phone shows it at about full size instead of 0.8. The card waits for any window that owns
  the screen to close, and stands touch movement down while it is up.
- **TOUCH_TARGETS_20261011.** Help and Badges are 44 px high on touch (30); the first-clear card's GOT IT has a 44 px
  hit strip; Level 4's keypad and note may draw up to 1.25 times their design on touch (they were held to 0.91, the
  keys 34.5 px high).
- **BUY_IS_REENTER_20261011.** Both death offers say BUY RE-ENTRY (one said BUY CREDIT, the other REVIVE), and a
  re-entry bought from either is used the moment the credit arrives; it used to be banked for a second press.
- **Help texts:** items on touch are SHIELD and KIT (it said every item has its own button); hold LIGHT to focus;
  starting a round names PLAY and playing alone; the first re-entry is free.
- **NOT done, on purpose:** the friend line's "INVITE" label. `test_friend_boost.py` holds the owner's own words for
  that line (2026-10-07: "very subtle", one short line 104 px wide), so my change was taken back.
- **Tested in Studio** with `tools/mobile_qa/ui_audit.py` at 568 x 320, 844 x 390 and 1024 x 768: no overlap and
  nothing off-screen from the new button; PLAY moved the test player 53 studs onto pad 102 and the dialog opened;
  the round HUD kept "Find a fuse relay under the amber lights." on the phone and both lines on the tablet. The
  welcome card has to be started AS a phone to be judged (`workspace.ForceTouchUI` and `UIRegressionViewport` set
  in Edit before play, removed after): it reads its device once, when it opens. Tests: round HUD 185, HUD B8 1228
  (its old purchase-caption failure is gone with the new wording), re-entry 37 + 5, friend boost 933, queue 100.
  `test_first_entry_guide.py` fails as before (its fake game has no TweenService). NOT tested: a real phone or
  tablet, a real purchase, two players.

### Added 2026-10-11 (night) - Dancing while the DJ plays (in Studio, NOT published by this session)

Owner: "Kan du tilføje en dance funktion til alle spillere, når DJ musik er i gang? De kan toggle, så en toggle knap
der kommer op på deres skærm, en knap til mobile og tablet og en knap der viser hvilken tast den er koblet til på
computer".

- **DANCE_20261011, in `Lobby DJ Client`** (no server part). While `workspace.LobbyDJTrack` names a track, every
  player in the lobby has a DANCE button: on a computer it reads "DANCE  [H]" and H toggles it (H was the one letter
  no script in the game used); on touch it reads "DANCE" (`UIDevice.Caption` leaves the key out). On, it turns
  magenta and reads DANCING, and the player's avatar plays one of Roblox's three stock dances (R15 507771019 /
  507776043 / 507777268, R6 182435998 / 182436842 / 182436935), the next one each time it is switched on, at the
  track's tempo (Bpm / 120, held to 0.8 to 1.25). Walking pauses it, standing still picks it up again; switching
  off, entering a round, DJ mode or the end of the music stops it. The client plays the animation on its own
  character, which replicates: the server's Animator listed the track in the test.
- **Where it sits:** on a computer at the bottom centre over the NOW PLAYING line; on touch between the thumbstick
  and the buttons (`Layout().Corridor`), and where that is too narrow (a 568 px phone) under the PLAY button, clear
  of the thumbstick's ground. It hides under any window that owns the screen and under the welcome card.
- **For a test:** `PlayerGui.LobbyDJ` attribute `DanceToggle` (any change presses it); the state is the player
  attribute `LobbyDancing`; a track is put on from the server with `workspace.LobbyDJTrack` (and `LobbyDJStartedAt`).
- **Tested in Studio play:** button shown with a track on and gone with it off; on, off and on again (the next
  dance); paused while walking and resumed; no overlap at 1366 x 768, 1024 x 768, 844 x 390 or 568 x 320. NOT tested:
  two players watching each other, an R6 avatar, a real phone. The DJ booth itself is still for the team only, so
  the button only ever shows while one of the team has a track on.

### Added 2026-10-11 (morning) - New players start with 5 tokens and get a card about them (in Studio, NOT published by this session)

Owner: "Måske skal nye spillere starte med et par tokens, og en pop up guide til hvordan man bruger dem og til hvad?"
and, to a proposal of 10, "Hvad med bare 5?".

- **What was wrong before:** a live new player started with 0 tokens. The welcome card said "You start with 25",
  which was `Config.Studio.StartingTokens`, Studio's own test balance. Nothing could be bought before three cleared
  levels.
- **NEW_PLAYER_TOKENS_20261011.** `ZyntraConfig.NewPlayerTokens = 5` (one number; 0 switches it off). At a first
  login `ZyntraMonetization` banks it in the SAME save as the free re-entry, behind its own marker
  `Grants.WelcomeTokens`, so it can never be banked twice and a failed save is retried (three tries, as before).
  Accounts that already existed get nothing. 5 buys one Entity Shield, or a Speed Potion and a Route Marker Pack.
- **The card (TOKEN_CARD_20261011, in `First Entry Guide`).** The server publishes the player attribute
  `ZyntraTokenGuide` while the card is owed (tokens given, `Settings.TokenGuideSeen` not yet true). It comes once, in
  the lobby, after three quiet seconds: after the player's first round in a first visit, or on arrival at a later
  visit. Never in a round, on a round server, over the welcome card, the briefing or any window that owns the screen.
  It names the three items with price and effect, how they are used (the key on a computer, "tap" on touch), and
  where more tokens come from. OPEN SHOP (Enter) opens the shop; LATER (Esc) closes it; both send
  `MarkTokenGuideSeen`. A round that starts under it closes it unanswered and it comes back afterwards. It raises
  `WelcomeCardOpen` while it is up, so PLAY, DANCE and the thumbstick stand down as for the welcome card. The
  REWARDS/WHEEL note after a first clear (`ZyntraStore`) now waits until this card has been answered.
- **Wording corrected:** the welcome card's token page says "You start with 5"; Help says "New players are given 5";
  "SHOPS" is "SHOP" in this script's texts, which is what the button on the rail reads.
- **For a test:** `workspace.DevSimulateFirstLogin = true` in Edit now also starts the Studio profile at 0 tokens
  instead of 25 (Studio still adds the Supporter pass's 10); `workspace.DevShowTokenCard = true` shows the card
  regardless; `PlayerGui.TokenCard` attribute `Press` = "shop" / "later" answers it. Remove the attributes after.
- **Tested:** `tools/tests/test_welcome_tokens.py` runs the real save code and the real first-login block against a
  fake DataStore (once only, one write, retry after a failure, nothing for a returning player, 0 switches it off).
  In Studio play: a simulated first login held 5 tokens and a free re-entry, the welcome card said 5, the card did
  not come before a round and came after one, OPEN SHOP opened the shop and LATER closed it, neither came back; all
  text fits at 844 x 390 touch and 1366 x 768 computer (`artifacts/ui-review-20261011/screen_tokencard_*`). NOT
  tested: a real first login against the live DataStore (Studio does not use it), a real phone, and the last two
  small edits after the pictures (the card is 10 px taller on a computer, "the SHOP").

### Read 2026-10-11 (11:40 local) - What is live and what waits in Studio

Owner: "Fortæl mig lige alle ændringer ved publicering her, fordi tidligere ting du har lavet i studio har jeg heller
ikke publiceret endnu". Read from the place's saved versions and from Studio's own log on the Mac:

- **Live is v2985** (saved 2026-10-10 23:10:47 UTC, published 23:51:07 UTC = 01:51 local on 2026-10-11, from Studio on
  this Mac while this session stood interrupted; before it v2980 at 22:00 UTC and v2979 at 20:52 UTC). So the
  sections above that say "in Studio, NOT published" for the Level 5 side walls, the Level 1 run and spring, the
  Level 4 reels and the lobby creature's hearing are out of date: all four are live.
- **Waiting in Studio (v2986 to v2992):** the phone and tablet fixes (commit c1c81957, written 23:54 to 00:04 UTC),
  the DANCE switch (53b6f628) and the new players' 5 tokens with their card (f8193124).

### Changed 2026-10-11 (midday) - Level 1: the loud sound at the grab is removed (in Studio, NOT published by this session)

Owner: "Fjern den høje lyd som spiller når man er blevet fanget af entity". It was `JUMPSCARE_SOUND`
(rbxassetid://140233243543479, volume 0.82) in `SoundController`, played 2D to the caught player the instant the
Entity's capture fired. The id is now empty (CAPTURE_SOUND_REMOVED_20261011), which the existing guard treats as "play
nothing". Left as they were: the scream the OTHER living players hear at the place of a death (`DEATH_SOUND`, 0.5) and
the Entity's own howls. Not played in a round after the change; the guard was read, not exercised.

### Added 2026-10-11 (afternoon) - Level 1 kill "the stranglehold" (Kill_Choke): built and in Studio, SWITCHED OFF until the owner approves

Owner picked idea 10 of ten: "Kvælertaget: den løfter dig i struben med én arm, så dine fødder slipper gulvet.
Kameraet ryster, synet snævrer ind fra kanterne, den vipper hovedet på skrå som et nysgerrigt dyr, og så slipper
lyset" (= the victim's screen goes black). The one-off Codex Ultra job he ordered for it authored the clip.

- **The clip (Codex, gpt-6.1-sol ultra; `tools/level1_entity/out/KILL_REPORT.md`):** `Kill_Choke`, a seventh entry of
  the motion layer's `clips.json`: 5.4 s, 162 frames at 30, with `marks` (grab 0.30, lifted 1.30, tilt 2.90, squeeze
  3.40, dark 4.10, release 4.20) and `tracks` in the Entity's root space (`grip` = the throat in the hand, `head`,
  `eyes`). The six old clips are byte for byte unchanged. Rebuild and renders: see the report.
- **The switch:** `ReplicatedStorage.Level1EntityMotion` attribute `KillStyle = "Choke"`. It is NOT set in the place:
  the ground-pin kill runs as before (played once after the change: same camera, death at 4.13 s, no errors). To
  switch the stranglehold on after the owner's yes: set that attribute in Edit. To go back: remove it.
- **KILL_CHOKE_20261011, three scripts.** `EntityKill` (server): with the switch on and the clip sound, it takes its
  timing from the marks, does not play the old Animator clip, and carries the victim from the `grip` track every
  Heartbeat (upright, throat in the hand, turned to the Entity's head; PlatformStand from the grab; unanchored at
  `release` so the body falls); it publishes `workspace.EntityKillStyle` and `EntityKillStartedAt` (server time).
  `Level 1 Entity Motion` (every client): plays `Kill_Choke` on the bones for the length of the kill, clocked from
  `EntityKillStartedAt`, with a 0.12 s cross-fade in. `JumpscareUI` (the victim): the camera rides the `grip` track
  (0.5 above, 0.25 back) and looks at the `eyes` track, shake grows with the hold (off with ReduceCameraShake), the
  lens goes 70 to 64, the victim's own body is hidden, and vision closes through a round soft-edged hole (13 rings
  of UIStroke; 1.25 of the screen's width down to 0.5 at the squeeze and 0.14 at the dark); the black is the ordinary
  death fade.
- **Measured in Studio play, switch set at runtime only (four kills):** the clip on the real bones is within 0.001
  stud of the authored head track at the moment of drawing (read in a render step after the layer; a Heartbeat read
  shows the Animator's pose and is useless), head roll 28 degrees in the tilt, feet 4.4 studs off the floor, the
  victim's throat 0.1 to 0.3 studs from the grip, camera 3.2 studs from the eyes in the hold and 2.0 in the squeeze,
  dead at the dark, the body falls at release, no script errors. Screenshots of the real view:
  `artifacts/level1-entity-kill-20261011/live_in_game_sheet.jpg`. The Entity's real eye attachments (`EyeL`, `EyeR`
  under the Head bone) lie 0.28 stud from the point Codex measured on the mesh: about 5 degrees at that distance, left.
- **NOT tested:** an Entity Shield pressed during the hold (the cancel path is the old one), a second player watching,
  R6 or very tall or small avatars (the neck offset is measured per avatar, held to 0.6 to 1.8), a phone, and the
  last change to the narrowing's timing (numbers only). The hand-off into the walk afterwards was not judged by eye.
  The HUD stays on screen during the kill, as it did in the old one.

### Changed 2026-10-11 (afternoon) - The stranglehold: red eyes for the whole kill (in Studio, NOT published by this session)

Owner: "Du skal sørge for at den har røde øjne når den kvæler en". The eyes were already red while it hunts (ALERT,
CHASE, TRACK, YELL) and amber otherwise, so a catch out of any other state kept them amber. CHOKE_RED_EYES_20261011
in `EntityAI.refreshEyes`: red (the hunt colour, with its brighter light) whenever `EntityKillActive` is true and
`EntityKillStyle` is "Choke"; back to the state's own colour when the kill ends. Played once: amber before, red at
0.4, 2.0 and 3.8 s out of LURK, amber after (`artifacts/level1-entity-kill-20261011/live_red_eyes.jpg`). The old
ground-pin kill is unchanged. Behind each red dot a little amber shows from the side: the eyes painted on the body's
own texture.

### Fixed 2026-10-11 (afternoon) - Level 2: water in the stair tunnel's ceiling and inside four pit shafts (in Studio, NOT published by this session)

Owner: "I level 2 er der vand i loftet når man går ned af trapperne til sektion 2" and "Water is also clipping in some
of the pits in sektion 2". The owner's "sektion 2" is A3, the pit hall, the second hall on the route (SPAWN, P0, A1,
P1, A3, ...); the stair is P1.

- **Cause.** The map's water is nine blocks of Terrain water (`L2NTerrainRegions` on the world model). Two are slabs
  under a whole hall with only a film showing over the floor: A1 `[69072,224,-4 .. 69440,232,640]` (floor top 231.36,
  water top 231.80) and A3 `[69468,164,152 .. 69900,176,392]` (floor 171.3). (1) P1 is a closed concrete tunnel that
  leaves A1 through a stairwell at x 69244..69272 and runs on UNDER A1's floor; the slab had never been cut out of it,
  so for the first 50 studs of the stair a sheet of water hung across the tunnel's top. (2) Pits 1, 2, 3 and 5 of A3
  (shaft walls 0.7 stud) had slab water 0.8 to 2.0 studs from their inner faces, and Terrain water bulges about 2: it
  showed inside the shafts at y 164..170. Pit 4 had 2.4 to 3.9 and was clean.
- **Fix: `tools/level2_poolrooms/fix_water_20261011.luau`, run once in Edit** (marker attribute `L2WaterFix20261011` on
  Terrain; one undo point before it). Tunnel: Air for x 69264..69324, y 200..232, z 256..288, and the hall's film put
  back above the floor as a thin sheet (row 232..236, occupancy 0.06) over x 69272..69332, z 248..296. Pits: Air for
  each shaft plus 3 studs (3.3 for pit 5) at y 158..180, which stays inside the 4.2-stud curb.
- **How Terrain water is drawn (measured in Play; this is why a plain cut was not enough):** a water cell is drawn as
  a sheet centred on the grid plane UNDER it, about 8 x occupancy thick; a full column therefore hangs 4 studs below
  its lowest cell (the A1 slab's underside is at y 220, not 224); a single full row left over a void still hangs 3.8
  studs under its plane. So a film that must stay above a floor with nothing below it has to be a thin sheet in the
  row ABOVE (0.06 gives 231.77..232.23), and it must overlap the ordinary water round it by two cells: without the
  overlap its edge shows from the hall as a bright dry band four studs wide.
- **Visual meshes cannot be raycast** (`Visual` parts have CanQuery off): a ray test of "can water be seen" passes
  through walls and over-reports. It is good for proving water is NOT there; whether something is visible needs a
  picture.
- **Checked in a fresh Play session after the fix:** from the stair, no ray up from a player's eyes meets water for
  the first 90 studs (24 of 40 did before at the worst step) and six pictures along the stair show concrete only; the
  hall's film over the tunnel shows no edge or patch; no ray from the middle of any of the five shafts meets water
  before a wall (was 10, 31, 19, 0 and 47 of 384). Pictures: `artifacts/level2-water-20261011/`. NOT checked: the
  other seven water blocks, a walk of the whole level, a phone.

### Changed 2026-10-11 (14:35 local) - The stranglehold is SWITCHED ON in Studio (not published by this session)

The owner published v2999 at 14:17 local (12:17 UTC) with the stranglehold still switched off, and then asked "Er du
sikker på den nye kill animation for entity i level 1 er live?". It was not: v2999 carries the code and the clip but
plays the old ground-pin kill, because `KillStyle` was unset. Taken as the go: `ReplicatedStorage.Level1EntityMotion`
now has `KillStyle = "Choke"` in the saved place (one undo point). Played once with the saved switch and no test
attribute: the stranglehold ran to the end, the narrowing went 1.16 to 0.14 of the width (the timing changed last),
dead at the dark, no errors. It goes live with the owner's next publish; servers on v2999 keep the old kill until
they are restarted. Back to the old kill: remove the attribute.

### Added 2026-10-11 (afternoon) - Level 1 kill "the slam" (Kill_Slam), panic vision and a skull-crunch sound: SWITCHED ON in Studio (not published by this session)

Owner: "Kan du lave en ny med tager fat, smasher ned i jorden og loader hånd op og smadre ind i ansigtet på spilleren,
de skal have panik syn imens det sker og især når de ligger på jorden. Brug elevenlabs til at lave et skull crunch lyd
når den smasker dem i ansigtet."

- **The clip (Codex, gpt-6.1-sol MEDIUM through the launcher; `tools/level1_entity/out/KILL_SLAM_REPORT.md`):**
  `Kill_Slam`, the eighth entry of `clips.json`: 5.4 s, marks grab 0.30, lifted 0.80, slam 1.07, windup 2.95, strike
  3.12, release 3.49, and tracks `grip`, `head`, `eyes`, `fist` (the left fist) plus `vup` / `vfront` (unit x 1000:
  the victim's attitude, since it ends on its back, head away from the Entity). 37 of 38 of its checks pass; the one
  that fails is that the gripping claw is 0.22 stud from the victim's eyes, which a hand on a throat always is. The
  seven older clips are byte for byte unchanged.
- **`KillStyle = "Slam"`** on `ReplicatedStorage.Level1EntityMotion` is SET in the place (it was "Choke" since 14:35;
  the owner asked for the new one). "Choke" brings the stranglehold back, no attribute the old ground-pin kill.
- **KILL_SLAM_20261011 in the scripts.** `EntityKill`: `KILL_CLIPS` maps the style to its clip; the slam's dark frame
  is `strike`; the victim's CFrame is built from `grip`, `vup` and `vfront`; `workspace.EntityKillVictim` names the
  victim. `Level 1 Entity Motion`: plays whichever kill clip the style names, and gives the OTHER players the blow's
  sound from the Entity's root at `strike`. `EntityAI`: red eyes for any kill style. `JumpscareUI`: the victim's camera
  rides the body (eyes at `grip + 0.55 vup + 0.35 vfront`, camera up = `vup`), looks at the Entity's eyes, half way to
  the fist while the hand is loaded and at the fist for the last quarter second; PANIC VISION is a heartbeat (2.3 a
  second in the air, 3.1 rising to 4.3 on the floor) that closes the tunnel, blurs (BlurEffect), drains and reddens
  (ColorCorrectionEffect) and kicks the lens on every beat, with the slam itself as a flash, a 26-size blur, a lens
  kick of 14 and two blinks; ReduceCameraShake removes the shake and softens the rest. The tunnel is now 25 rings (13
  showed as bands on a bright ceiling; the stranglehold uses the same).
- **The sound.** ElevenLabs through Codex: the connector no longer has a text-to-sound-effects tool; sound effects
  are generated through its `elevenlabs_creative_*` flow tools (a flow "stayquiet l1 crunch"; nine takes in
  `~/Projects/stayquiet-l1-kill/audio/raw`). The master is two takes layered, a low thud and a sharp crack, picked on
  measurements (single hit, onset, spectrum), NOT by ear: `assets/level1-kill-20261011/l1_skull_crunch.ogg`, group
  audio asset 103835120253894, named to the game by the folder attribute `KillCrunchSound`, played at volume 1.6
  0.03 s before `strike` (2D for the victim).
- **Played in Studio (three kills, the last with the saved switch only):** up 2 studs, on its back 0.5 over the floor
  from 1.2 s, camera lying and looking up, blur 18 and lens 79 at the slam, the tunnel pulsing 0.56 to 0.68 on the
  floor, the crunch playing at 3.11 s and loaded, dead and black at the strike, effects removed after, no errors.
  Pictures of the real view: `artifacts/level1-entity-kill-slam-20261011/live_in_game_*.jpg`.
- **Weak or NOT tested:** the loaded fist rises only to head height (the body stays on all fours), so "loader hånd op"
  is modest; from below, the red eye dots sit at the top edge of the head; nobody has listened to the crunch; a
  shield pressed mid-kill, a second player (and so the positional crunch), R6 and odd-sized avatars, a phone (25
  full-screen strokes and a blur) were not run.

### Asked 2026-10-11 (evening) - An exclusive skin for content creators: six ideas drawn, nothing built

Owner: "Der skal laves et exclusive skin [til] content creators som spiller vores spil og er supporter. Kom med idéer
til hvordan det skin kan se ud ingame ... Det skal være sådan vi DEVs kan give dem det" and then "Lav billeder af
idéerne". Six concept pictures (front and back of the real suit; Codex's image tool at Medium from the suit's own
reference renders, no lettering; captions set with Pillow) are in `artifacts/creator-skin-20261011/` and in
`~/Desktop/Creator skin - ideer`: Field Recorder (my recommendation: it matches the game's REC camcorder HUD), Found
Footage, Live Unit, Night Operator, Director's Cut, Spotlight. They are concepts, not the game's model: in 01 the
hood came out white and the camera sits on the shoulder. Proposed, NOT built: a skin of a new kind that cannot be
bought, given and taken back from the developers' menu beside GIVE RESEARCH TOKENS (a player on the server or a
UserId; a saved list so it also reaches someone offline at their next join), with the menu showing whether the
player owns Supporter. Open: which idea, and whether Supporter is a hard requirement.

### Streamers' feedback, 2026-10-11 (evening): the PLAY button is gone; store pictures and the lobby are open work

Owner, passing on streamers: "Our pictures look too much like AI, so we have to create pictures inspired by other semi
big and big backrooms games but made for our game. The lobby doesn't give off the liminal space vibe. How can we fix
that? Remove the 'Play level 1 alone or with friends' but keep the visible through walls 'Start level 1 here'."

- **Done (in Studio, not published): PLAY_BUTTON_REMOVED_20261011** in `First Entry Guide`: the top-of-screen PLAY
  button and its teleport are removed; the through-walls marker stays and now reads "START LEVEL 1 / HERE"; welcome
  page 3 and Help name the marker instead of the button. Checked in play: no `PlayRoute` gui, marker enabled on a
  free Level 1 pad.
- **Store pictures (research done, pictures NOT made).** The twelve biggest backrooms games on Roblox by players
  online (public search and thumbnail APIs, read 2026-10-11: Unseen Liminality 8.8k, M.E.G. Endless Reality 5.2k,
  Backrooms Company 4.8k, Backrooms 4.2k, The Backrooms 1.9k, Apeirophobia 0.9k, The Shadow Network, The Exit 8, The
  Complex, The Backrooms [REDACTED], Survive the Backrooms, Backrooms Motion) all use IN-ENGINE scenes: the game's
  own rooms and models, a posed player in the foreground and the entity behind or round a corner, or an empty room
  alone; the fluorescent yellow palette with one red variant; and ONE small logo lock-up in the same corner of every
  picture. None is painted or generated. So ours are to be staged and photographed inside the game (HUD off,
  scripted camera, the Entity frozen in a clip pose with `L1EntityMotionDebug`), then lettered. First raw captures of
  Level 2's pillared hall are in `artifacts/mobile-qa-20261011/th2_l2_*.jpg`; two HUD chips (the item slots) survive
  disabling every ScreenGui under PlayerGui and still have to be found. A level's own lighting needs about a minute
  after arrival before a capture.
- **Lobby (a question, answered with a proposal, nothing built):** it reads as a clean sci-fi transit hub (black
  ribbed arches, teal light strips, a road line, many signs, a DJ stage), which is the opposite of liminal. Proposed:
  rebuild its surfaces as a dead shopping-mall concourse at night (shop = shuttered storefronts, level gates = store
  entrances, leaderboards = mall directory boards, the DJ stage = an abandoned event stage), flat sickly fluorescent
  light with a few dead panels, far fewer signs, a hum instead of music by default. Through Blender, as every map.

### Made 2026-10-11 (evening) - Ten store pictures with the in-game look (delivered to the Desktop, NOT uploaded)

Owner, after the streamers' "too much like AI": "Lav først billederne og du bruger codex 6.1 sol ultra til det."
One Codex job at ULTRA (his word for this job; 19:19 to 19:46), brief `artifacts/promo-20261011-ingame/brief.md`: the
image tool, fed the real screenshots of 2026-10-07 and today's captures as content and two sheets of the twelve
biggest Roblox backrooms games' own pictures as style, told to make pictures that look taken INSIDE a Roblox game
(plain rooms, game lighting, no haze, grain or poster drama) and never to copy another game's content. Eight
thumbnails (Level 1 round the corner, Level 1 it sees you, Level 1 caught in red, Levels 2 to 6 one each) and two
icons, all accepted on the first to third try; `prompts.json` has each prompt and what is still off. Cropped to
1920 x 1080 and lettered by `tools/promo/finish_ingame.py`: ONE small lock-up, BACKROOMS over STAY QUIET, in the
bottom-left corner of every thumbnail; icons 1024 x 1024 without lettering. Delivered:
`~/Desktop/Backrooms Stay Quiet - Store-billeder 2026-10-11` (with logo, without logo, icons, overview); finals in
`artifacts/promo-20261011-ingame/final/`. They are GENERATED from real references, not photographs of the game: the
Level 2 water is bluer than the game's dark teal, Level 5's blocks and Level 6's galleries are tidier than the real
ones, the Level 1 Entity's red eyes are small in "it sees you". Nothing was uploaded to Roblox.

### Drawn 2026-10-11 (evening) - The lobby as a dead shopping mall: floor plan and twelve section pictures (a proposal, nothing built)

Owner, after my proposal for the streamers' "the lobby doesn't give off the liminal space vibe": "Efter det kan du
lave billeder af hvordan lobbyen kan se ud med den idé, billeder af alle sektioner og plantegning." The plan
(`artifacts/lobby-mall-20261011/plan.png`, drawn with Pillow on the real lobby's measurements read in play: concourse
x 180..260, z -900..-621, six bays at x 149..172 and 268..291, stage z -655..-632, fence z -621, shop wall z -800)
keeps every position, so a rebuild changes surfaces, light and furniture only. Twelve concept pictures (Codex Medium,
image tool, brief in the same folder): arrival, concourse with the dry fountain, the six level stores (1 OFFICE,
2 POOL & SPA, 3 PARTY WORLD, 4 CINEMA, 5, 6 SOFT PLAY: roll shutters half down, the level's own look glowing inside),
the SUPPLIES kiosk with vending machines (the shop), the DIRECTORY board (leaderboards), the GRAND OPENING event stage
(DJ) and the fenced CLOSED FOR RENOVATION wing (the creature's dark). Delivered with captions to
`~/Desktop/Lobby - forladt indkoebscenter (forslag)`. They are concepts: planters and benches differ from the plan
from picture to picture. To build: through Blender, as every map; the owner's yes is owed.

### Drawn 2026-10-11 (late evening) - The mall lobby, second round: open shops with level showcases and queue bays, the Zyntra stand, tape and the dark wing

Owner on round one: "Stabilt koncept med det der mall. Butikkerne skal dog være mere åbne så det ikke er en rulledør
der næsten er nede, og rigtig fint hvis det showcaser hvordan levelet nogenlunde ser ud, og så skal der være queue up
bays ligesom i vores. Elsker slutningen der hvor der er mørkt, der må du meget gerne lave noget crime scene tape med
nogle pæle som skal signalere at her stopper lobbyen, og efter det, hvis man så fortsætter ind i den mørke og
fortsættende lobbygang, så bliver lobby-monsteret vækket og kommer stille og roligt tættere på og griber en med dens
arme, som allerede er i den nuværende lobby, men åbn facaden. Lad der være en lille mall shop i midten ... det kan
være Zyntra-shoppen med alle vores ting. Kom med nye konceptbilleder."

Plan v2 (`artifacts/lobby-mall-20261011/plan_v2.png`) and twelve pictures (`raw_v2/`, brief `brief_v2.md`, Codex
Medium): each level shop is a fully open front with the level's look as a showcase in the back two thirds and three
round queue pads with STATION posts in front; a freestanding ZYNTRA kiosk island stands where the fountain was and is
the shop (the wall kiosk is gone); the fence is replaced by CRIME SCENE DO NOT CROSS tape on striped poles that a
player can walk under; beyond it the same concourse runs on unlit, and the Reach (two eyes, four long arms, as it
exists today) wakes for whoever goes in. Delivered with captions to
`~/Desktop/Lobby - forladt indkoebscenter (forslag)/v2`. Off in the pictures: the cinema's seats are oversized, the
overview shows the tape too near, one distant shutter is down in the stand's picture. What this means for the game's
rules when built: the Reach's trigger changes from "over the fence" to "past the tape", and the way out is simply to
walk back. Still a proposal; nothing built.

### Drawn 2026-10-11 (night) - The mall lobby, third round: 1990s Backrooms look, the hexagonal Shop & Supplies unit, the levels' names, the danger tape

Owner on round two: "Okay bedre, men det ser for moderne ud. Behold 90 backrooms stilen hele vejen igennem i mallets
udseende. Den der Zyntra shop ligner noget fra Dubai Mall. Det skal være ... sådan hexagon-formet lille shop ligesom
de der 90s jewelry shops der er i midten af sådan en gang, men med 90 stil, og kald den Shop & Supplies. De
forskellige levels skal hedde: 1. Office 2. Poolrooms 3. Mall Party 4. Cinema 5. The Void 6. Play Zone. Drop det der
med crime scene tekst og skriv i stedet for på det tape 'DANGER: DO NO GO PAST THIS POINT' hele vejen hen." (The
tape says DO NOT GO: his "NO" read as a slip, and he was told.) Then, with a reference picture
(`artifacts/lobby-mall-20261011/refs/owner_rmu_reference.png`): "For the shop like this but 90s liminal backrooms
style and a hexagon. They are called Retail Merchandising Units."

- **These names are now the levels' names for the lobby:** 1 OFFICE, 2 POOLROOMS, 3 MALL PARTY, 4 CINEMA, 5 THE VOID,
  6 PLAY ZONE. The shop is SHOP & SUPPLIES.
- **The look that was accepted as direction ("THE LOOK" in `brief_v3.md`):** flat warm green-yellow light from old
  fluorescent troffers, a yellow cast over everything, stained 2x2 ceiling tiles, MATTE worn floor, yellowed plaster
  or damask wallpaper with the teal-and-mauve stripe, oak-effect laminate fascias, dull brass, cream backlit plastic
  sign boxes with chunky dark-red 1990s capitals. Nothing glossy, no black fascias with white type, no LED look.
- **The stand:** a hexagonal island counter in oak laminate with round stools, a hexagonal display tower rising from
  its middle (pegboard, small cabinets, a CRT, a rail of suits), a ring of opal globe lamps, a hexagonal sign box, and
  a short side counter with a till: the reference's arrangement in 1990s finishes.
- Thirteen pictures in `raw_v3/` (twelve sections, the stand also from above; the round-three kiosk and a misspelt
  overview are kept beside them), plan `plan_v3.png` from `tools/lobby_reach/mall_plan.py`, delivered with captions to
  `~/Desktop/Lobby - forladt indkoebscenter (forslag)/v3`. Off: a slight floor sheen in three pictures, the stand
  from above has four stools and its side counter on the other side. Still a proposal; nothing built.

### Started 2026-10-11 (22:25) - BUILDING the mall lobby: Blender build by Codex Ultra, then Claude's QA, import beside the old lobby, and wiring

Owner: "Amazing. Use blender to make a lobby exactly like those pictures with the layout following the blue print,
import it to the game, make it fully functional like our current lobby and place it out and beside the existing
lobby so we as DEVs can noclip out and look at it. Make sure the layout of the signs follow layout, color and font
as the level 2 example attached as a photo [a crop of round two's sign: pale cream-yellow backlit box, thin dark
frame, DARK GREY CONDENSED BOLD SANS, one centred line]. Use Claude to do the groundwork, but make Codex 6.1 sol
ultra do the heavy lifting with rendering and all that stuff, and make sure Claude QAs its work before importing
anything."

- **Sign style is the owner's crop** (`artifacts/lobby-mall-20261011/refs/owner_sign_reference.png`), NOT round
  three's dark-red chunky lettering. Every sign box in the build follows it.
- **Phases.** A (running): Codex Ultra writes `tools/lobby_mall/build_mall.py` (the whole design as code: Blender
  scene, `artifacts/lobby-mall-20261011/build/mall.json` for the importer, generated tiling textures),
  `check_mall.py` and `render_mall.py` (the thirteen views of W01..W13 plus a plan and a lit dark wing), brief
  `artifacts/lobby-mall-20261011/build/BRIEF.md`. B: Claude QAs renders, data and checks BEFORE anything is imported.
  C: Claude writes `tools/lobby_mall/import_mall.py` (native Parts, MaterialVariants from the textures, SurfaceGui
  signs in a condensed bold face, lights) and builds the model beside the present lobby (an offset on x, same z and
  floor). D: wiring it like the present lobby (queue pads, shop, leaderboards, DJ, the Reach past the tape), then a
  walk on foot.
- **Groundwork measured in play (the present lobby):** concourse x 180..260, z -900..-621; six bays x 149..172 and
  268..291 at z -869..-811, -789..-731, -709..-651; 24 queue pads, FOUR per level in a 2 x 2 grid (x 148/166 or
  274/292, z = bay centre -/+ 13.2; Parts 14.8 x 1 x 14.8 with attributes `R3QueueId` 101..124, `LevelNumber`,
  `QueueDisplayIndex` 1..4, `QueueRadius` 7.41, `QueueDetectorShape` Circle, `LobbyReimaginedOwned`); shop display on
  the east wall at z -800 with ten pressure plates (`PreviewShopPressurePlates`: Supporter, AdvancedEquipment,
  Tokens4, Tokens20, EmergencyReentry, ExpeditionPack, CosmeticEquipment, SpeedPotion, RouteMarker, EntityDetector);
  seven leaderboards; stage deck x 205..235, z -655..-632; spawn (220, 30.4, -860); the Reach's frame at z -621.
- **Queue pads: THREE a shop, the owner's decision.** I had changed the build to four because
  `LobbyReimaginedPreview.QueueBridge` is built on exactly 24 zones, ids 101..124, four a level
  (`level = floor((id - 101) / 4) + 1`), each a direct child of a bay Model with a `ChamberFloor` and a
  `CircularBayDiameter`, with a `QueueRenderOwner` ObjectValue. Told so, the owner answered: "fuck that lav 3 plader,
  det passer bedre til dette map". So: three pads of radius 7.4 at z = shop centre -19, 0, +19 (x 166 or 274),
  STATION 1..3, as in the pictures, and the queue bridge (and whatever in GameManager counts four) is to be changed
  to three stations a level when the new lobby takes over. Two Codex runs were stopped by process id over this.
- **What "fully functional beside the old lobby" can and cannot mean:** the queue, the spawn and the Reach belong to
  the ONE model named `LobbyReimaginedPreview` that GameManager, RoundUI and the queue controller look up by name.
  A second lobby standing beside it can carry the same structure and attributes, ready to take over, and its own
  lights, signs and furniture; its pads cannot admit players at the same time as the live ones without changing
  GameManager. The switch-over is one step later, on the owner's word.
- **The shop is enlarged (owner, 22:50, while the build was starting):** "Du skal sørge for at shoppen er rigtig fed
  og du skal showcase hvert skin man kan købe for tokens og for robux, så shoppen må gerne udvides til at det passer i
  størrelsen til at showcase de skins og items der som det mest tydelige. Gør vores pakker som advanced equipment og
  sådan noget tydeligt og lækkert showcased i shoppen der." In the brief ("THE SHOP"): carpet hexagon of radius 20,
  a closed ring of six display counters (Advanced Equipment as the flagship facing the entrance, Entity Detector,
  Items, Packs, Research Tokens, Supporter and Glowstick Customizer), six skin plinths at the corners with life-size
  mannequins (Baseline Yellow, Pool Service 25 tokens, Suburb Survey 75, Blacksite Director 300, Static Wraith 99
  Robux, False Sun 149 Robux) lit brighter than everything else, the tower with the sign in the middle. Data for
  the importer: `anchors.shop_spots` (eleven buy spots) and `anchors.skin_plinths` (the game's real suit models are
  to stand there). Prices on the plates are today's config values and must be bound to the config when wired. The
  build job was stopped and restarted a third time for this.

## 2026-10-12 - the mall lobby stands in Studio beside the present lobby, and works

`Workspace.LobbyMallPreview` (marker `MALL_LOBBY_20261012`) is the Blender build, 300 studs EAST of the present lobby
(same z, same floor y 30; lit concourse x 480..560, z -900..-621, dark wing to z -421). The present lobby is
untouched and stays the one players spawn in; developers noclip over. Nothing here is published by me.

**Rebuild it:** `/usr/local/bin/python3 tools/lobby_mall/import_mall.py` (Studio in Edit). It DESTROYS the model and
builds it again from `artifacts/lobby-mall-20261011/build/mall.json`, so anything placed in the model by hand is lost;
change `build_mall.py` or the importer instead. Order after a change to the design: `build_mall.py` (Blender) ->
`check_mall.py` -> `make_pbr.py` -> `upload_textures.py` (only maps whose file changed) -> `import_mall.py`.

**What the import adds to Codex's build** (found in my QA of it):
- every normal and roughness map the build wrote was flat (44 maps, zero variation): `make_pbr.py` derives real ones
  from the colour maps into `build/textures_pbr/` (not in git; seed 611, byte-identical on a rerun). 16 surfaces are
  MaterialVariants `Mall <key>` (ids in `tools/lobby_mall/texture_ids.json`); the ceiling's colour map lost its
  stain (one on every 2 x 2 tiles read as polka dots down the hall); terrazzo tiles at 10 studs, not 16.
- signs are SurfaceGuis in the owner's sign style: cream face (236,226,160) drawn by the gui at LightInfluence 0,
  Oswald Bold in (72,66,54), one line. Two engine facts: TextScaled never draws above 100 px, so PixelsPerStud is
  chosen to put the label near 145 px; and one line is forced with no-break spaces (TextWrapped = false together
  with TextScaled draws the text as a dot).
- lights: the build's lamp colours pulled 60 % toward warm white and brightness = 0.42 x sqrt(Blender's), panels
  1.0, plus a small `CeilingWash` PointLight under each lit panel (a panel only throws down, and the ceiling was
  black). Judge the light IN PLAY: Edit's lighting is not the lobby's. RoundUI's enclosed-lobby pass now also holds
  inside the mall's `BoundsMin`/`BoundsMax`.
- the game's own suit models (`ServerStorage.HazmatSkin_<id>_20260924`, 5.4 studs) stand on the six plinths; the
  build's stand-in mannequins are hidden (`StandIn`), not deleted.
- a station's pole and plate do not collide (on foot the character walked into the pole and stopped).

**Wiring (all in existing scripts; no new script):**
- QUEUES: 18 pads = stations **201-218** of the same engine (`QueueBridge.IsMall` / `BuildMall`, id = 200 +
  (level-1)*3 + station; GameManager's `bindR3` binds both models). Each pad is its own bay Model under
  `Anchors.QueueBays` (`ChamberFloor`, `CircularBayDiameter` 26, zone attribute `MallQueueId`), its render owner a
  hanging dot-matrix board carrying `QueueTitle`/`QueueSubtitle`. Clearing the model's `MallQueuesReady` takes all
  18 out of service. The party dialog shows a mall pad's own number 1-3 (`stationLabel` in RoundUI). The present
  lobby's 24 stations (101-124) are unchanged and both sets run at once.
- SHOP: `LobbyShopDisplay.mallSpotUnder` gives the item card to whoever stands within 1.9 studs of a spot under
  `Anchors.ShopSpots` (attribute `ShopItemKey`, a pale ring on the carpet). `EntityShield` has a spot and a
  counter but is not for sale in the config, so no card opens there. Each skin plinth carries a ProximityPrompt
  `MallSkinPrompt`; Shop Display Client opens the shop window's Skins page at that skin.
- BOARDS: `Level Leaderboards` pins each level's list to `Anchors.Boards.level<N>` as a printed sheet (`PAPER`
  look of `buildFace`) and a paper copy of TOP SUPPORTERS to `directory` (a clone of `DonationLeaderboardDisplay`
  whose text is kept in step every 5 s).
- DJ: `Lobby DJ` knows two desks (`consoles()`); the nearest one to the player is used. `Anchors.DJConsole`
  reaches down to the deck because the DJ is stood at the desk part's foot.
- THE CREATURE: one creature, two dark ends. The model's `ReachFrame` (at the tape), `ReachFence` 1 and
  `ReachGround` 200 are a second place for `Lobby Tunnel Reach`; asleep with every hand home it moves to whichever
  end somebody has walked into, and the client follows the republished `Frame`. The tape does not collide.

**Tested in Studio play (one player):** party dialog on a mall pad; a Level 1 round started from station 202; the
item card at the Advanced Equipment spot; DJ mode behind the mall's desk; past the tape the hands crept out, took the
player and the lobby respawned them; a walk on foot over 19 legs (every shop, the stand, the stage, the tape) with
no stop that was not a planter, the chairs or a pole. NOT tested: two players, a phone, Levels 5 and 6 from a
mall pad, a real purchase, the skin prompt pressed with a key (its route was not exercised), the leaderboards with
real data (Studio shows the demo rows).

**Known differences from the concept pictures:** the showcases are sparse blockouts (The Void is a pink room with
black slabs, Mall Party a table and balloons), the suits stand in a T-pose, the dark wing is dim rather than black,
and there is no flicker on the one dim panel (its `Flicker` attribute is set, nothing reads it yet). Tests
`test_lobby_shop_display` and `test_spectator_count` fail, and failed the same way on the commit before this work.

## 2026-10-12 (later) - the first lobby is removed, the mall is parked and previewed by E, ESP shows players

Owner's batch after seeing the mall. All of it is in Studio and unpublished.

**THE FIRST LOBBY IS GONE AT RUNTIME (`FIRST_LOBBY_REMOVED_20261012`, GameManager `buildLobby`).** Three lobbies
were loading: `ServerLobby` (TunnelLobbyBuilder's, the very first, 2,593 parts), `LobbyReimaginedPreview` (the
tunnel lobby players stand in) and the mall. `ServerLobby` is still BUILT at startup, because the tunnel lobby takes
its shop boxes and the supporters board from it, and it still EXISTS as a Model holding only `LobbySpawn`, because
about a dozen scripts read "this server has a lobby" and the spawn from exactly that name. Everything else in it is
destroyed before any character loads (attribute `FirstLobbyRemovedParts`, 2,592 in Studio), and it returns no queue
stations. If the tunnel lobby fails to build, the first lobby is the fallback and is kept whole.
`workspace.KeepFirstLobby = true` keeps it. What went with it and is not replaced: the first lobby's own pads, its
party button and ceiling sweeps, the Level 5/6 sealed doors (`LevelDoorways`), its shop wall. `LobbyShopDisplay`'s
focus pass used to end when that wall was destroyed; it now runs while any of the three shops stands.
Tested in play: spawn, the tunnel lobby's shop card, pad 101's dialog, a Level 1 round from pad 101, seven boards,
the DJ prompt, the creature ready. Workspace went from about 7,100 parts to 2,590 with the mall parked.

**THE MALL IS PARKED (`MALL_PREVIEW_20261012`, new script `ServerScriptService/Lobby Mall Preview`).** At server
start the mall model is moved to ServerStorage (a round server deletes it): no client receives it and its 18 queue
stations do not run. `MallPreviewPrompt` (E, "MALL PREVIEW (DEV) / SEE THE NEW LOBBY") stands six studs in front of
the lobby's spawn pad and follows the pad; it is for `DevAccess.IsMallPreviewAllowed` only (LaverSneglen,
ZenMeister02, mikkelczar; everybody else's client disables the prompt in Shop Display Client, and the server checks
again). Pressing it brings the mall into Workspace, HOLDS the visitor anchored at the mall's spawn while their client
streams the hall (a stream request with a time limit alone let them fall out of the world once), then lets go.
`MallReturnPrompt` by the mall's dead doors goes back. With nobody within 60 studs for 45 s it is parked again
(`workspace.MallPreviewStay = true` keeps it out). GameManager binds stations 201-218 when it comes out and retires
them when it goes; the leaderboard sheets and shop crates live in the model and are built wherever it is.
Two engine facts met here: a part's `CFrame` raises no property-changed signal (the prompt polls the pad), and the
game's prompt plate (Found Footage HUD) is a BillboardGui with MaxDistance = MaxActivationDistance + 8 measured from
the CAMERA, which rides 12 studs behind the body, so a prompt further than about 8 studs ahead shows no plate. The
plates do not appear on `qa.py shot` pictures at all (the DJ booth's neither).

**MALL CHANGES.**
- Boards: each level's "Fastest escapes" board stands flat against the pier beside its own shop's opening
  (levels 1/2 south of it, 3/4 north, 5/6 south, so the passage past the stage stays 20 wide).
- Showcases rebuilt after the v3 pictures (`build_mall.py`): Poolrooms dark teal with twelve white columns in dark
  water; Mall Party with the staff door and boxes; Cinema with a pink line over a cyan line round three walls and a
  framed screen; The Void rose from the hall's edge to the back wall with a flush black strip (the first build's
  five-stud pit had no way out), a low wall, two blocks and one globe; Play Zone a soft-play frame (21 posts, bars
  post to post, decks, netting, a red tube slide, a cube, rollers) on a four-colour mat. `check_mall.py` refuses
  solid overlaps, so bars and the slide are built in lengths end to end.
- Shop crates (`MALL_CRATES_20261012`, LobbyShopDisplay): one copy of each product box hovers 5.74 studs above its
  buy ring (the owner lowered it 30 % from 8.2), 2.5 studs, no lamp, no bob, with the item's name on a cream sign.
  A ring with nothing for sale (Entity Shield) is switched off.
- Floor (owner, with three photographs): big pale glazed tiles with dark joints (`floor_tile`, four by four on the
  sheet, 2 studs a tile; it was terrazzo), the wall band the same tile in tan. `make_pbr.py` sinks the joints in the
  normal map and makes tile glossy, joint matt. The engine draws no reflection of a lamp in a floor here whatever
  the roughness, so every lit panel lays a soft sheen on the tiles under it (`PanelSheen`, picture `sheen`).
  Codex's REPORT.md still describes the terrazzo and the first showcases.
- Light and load (`MALL_LIGHT_20261012`): the hall is lit by AMBIENT light (RoundUI, `mallLight`: Ambient 196,187,154
  in the hall, fading to the lobby pass's dark over 30 studs at the tape), because Studio's graphics level is
  Automatic and at a low level the engine drops local lamps: the lamp-lit first version went black-ceilinged. Lamps
  went from 73 to 38 (one PointLight a panel, none for product lamps or globes). No part casts a shadow or answers a
  query unless it collides; the stand-in mannequins are deleted, not hidden; signs have a MaxDistance; the tape's
  gui is 70 px a stud (it was a 15,840 px canvas a face); the dark wing is dark by its own colour (x 0.14).
  Model: 1,935 parts, 38 lights, 127 guis. In Studio on this Mac: 12 fps at the lobby spawn with the mall parked,
  14 fps standing in the mall (the machine was swapping; these compare the two places, nothing more).

**ESP (`PLAYER_ESP_GLOBAL_20261012`, DevCheats).** On every map the ESP switch (B, or the DEV terminal) now also
shows every other player: a blue outline through walls where the client has their body, and a label with the name
and the distance in studs from server positions (so it works beyond streaming range). It was a separate switch,
off by default. Level 6 Dev ESP no longer draws players for an account that has this. NOT tested with a second
player: Studio had one.

## 2026-10-12 (evening) - the mall's floor: four-stud tiles and the patterns of 1990s malls

Owner on the first tile floor: "Gulvet ligner lidt et badeværelses gulv nu, gør tiles større og lav de her grimme
random pattern fra ref billeder" (six photographs). `tools/lobby_mall/floor_tiles.py` now draws every floor sheet's
colour, bump and gloss map from one description (128 px a tile, thin grey joint, glazed tile 0.10 / grout 0.86);
`build_mall.py` writes them and lays the lit hall in rows (`Concourse_Floor<row>_<cell>`), every edge on a multiple
of 4 studs. A tile is 4 studs (it was 2). From the entrance: plain, HARLEQUIN diamonds (teal, tan, cream, slate;
z -880..-848, the spawn stands on it), plain, stepped green/pink BANDS (-824..-808), black and white CHECKER round
the stand (x 192..248, z -800..-740), two terracotta INLAYS (-736..-720), a black row, RED/GREY checker under the
chairs (-696..-664), a black row, plain to the tape. Tan band along both walls; shop queue floors and the dark wing
are plain.
ENGINE FACT, measured in play: a MaterialVariant's sheet is laid from the WORLD's origin, not from the part (joints
of separate floor parts run through each other, and a 16-stud part standing on a multiple of 16 shows one whole
sheet). So pattern edges only have to stand on tile multiples, and the importer's OFFSET must stay a multiple of 4
(the inlays need x 496 and 528: OFFSET 300). `upload_textures.py` reuses an id when two maps are the same picture
(plain, checker and red/grey share bump and gloss). The lamps' sheen plates are unchanged.

## 2026-10-12 (night) - mall: four pads two by two, a 30 % higher hall, the Robux skins in front

Owner: "Ryk alle queue up bays indad ... så der er 4 pads som er placeret 2x2 lige som i den nuværende lobby med gå
afstand i midten"; "placer 2 af de skins der koster robux i fronten"; "højere til loftet. 30% højere".
- Every shop is 15 studs deeper (x 112..180 and 260..328; model bounds x 110..330 before the importer's 300): the
  queue zone is 42 deep and holds FOUR pads, rows 10 and 32 studs in from the shop front, 12 either side of the
  middle: a cross of floor 9.2 wide down the middle and 7.2 between the rows. Stations 1 and 2 are the front row;
  each post stands 9.6 out on its pad's outer side. The showcase behind is unchanged.
- Queue ids are 201-224, four a level (`QueueBridge` MALL_PER 4, MALL_COUNT 24; RoundUI `stationLabel`; importer).
  Tested in play: 24 stations registered, the dialog on station 3 of Level 1.
- The hall (and the dark wing) is 20.8 studs high (it was 16): `CEIL = 50.8` in build_mall.py. The shops keep
  their 14-stud ceilings behind a bulkhead over each front; model bounds top y 56. I read "højere til loftet" as
  the hall's ceiling; the shops' own were not asked for.
- Shop & Supplies: Static Wraith and False Sun stand on the two corners that face the entrance; the other four
  round the back as before.

## 2026-10-12 (night) - the creator skin, "Creator Gold" (`CREATOR_SKIN_20261012`)

Owner: "Lav det her skin som vi DEVs kan give til streamers" (their pick "7 GOLD + CAMCORDER": black suit, gold sash,
gold lenses, a 1990s camcorder on a pole pointing forward, an aerial). In Studio, unpublished.
- ART, no Meshy and nothing generated (`tools/creator_skin`): `build_creator_skin.py` (Blender) loads the game's one
  suit from git (`assets/hazmat/baseline-rigged.glb`), `paint_creator.py` recolours its baseline map BY POSITION ON
  THE BODY read through the UVs (the baseline's yellow is the fabric mask; sash = a band about the line from the left
  shoulder to the right hip, front and back; lenses by position), and the topper is modelled from plain solids in
  studs about the wearer's UpperTorso (x right, y up, z behind). Output `artifacts/creator-skin-20261012/` (map,
  `topper.json`, previews, `card.png`, `.blend`). `install_creator_skin.py` uploads map, card and MESH
  (`AssetService:CreateAssetAsync` with an EditableMesh worked on 2026-10-12) and makes
  `ServerStorage.HazmatSkin_CreatorGold_20260924` (a copy of a suit template with the new ColorMap) and
  `HazmatCreatorGoldTopper_20261012` (one MeshPart, RenderFidelity Precise: at Automatic the aerial's rod was not
  drawn at eight studs; attribute `Centre` = where its middle sits). Ids: `tools/creator_skin/creator_skin_ids.json`.
- GAME: `ZyntraSkins.CreatorGold` (Kind "Creator", `Skins.SetCreator`); `HazmatSkinVisuals` (topper entry;
  `topperOffset` reads the template's `Centre`); `ZyntraMonetization` RemoteFunction `ZyntraGrantCreatorSkin`
  (userId, give): DevAccess, the token gift's cooldown and serialized profile write; the recipient must be on the
  same server and it is saved in their profile. `Zyntra Shop L4`: a Creator Gold card for whoever owns it (and for
  developers), "CREATOR EXCLUSIVE" otherwise hidden. `Zyntra Dev L4`: GIVE CREATOR SKIN / TAKE CREATOR SKIN in the
  ECONOMY page's header, for the player chosen in the picker (desktop only, like token gifts).
- NO Supporter requirement is enforced: the owner never answered whether "og er supporter" is a hard rule, so a
  developer decides who gets it.
- Tested in Studio play with one account: given to myself, equipped, shown on the shop's skin page, worn in a
  Level 1 round (third-person camera, front and back). Not tested: giving to ANOTHER player, taking back, a real
  server (Studio does not save), phones, how it looks on other clients.
- Tool quirk: `mac_merge_push.py` with LUAU_COMPILE_BIN set fails on `Zyntra Dev L4` (luau-compile's output is not
  UTF-8 for that file); push that file with the variable unset after compiling it by hand.

## 2026-10-13 - THE MALL IS THE LOBBY (`MALL_IS_LOBBY_20261013`), and its last four additions

Owner: "Begynd at bytte lobby, den nuværende med den nye mall lobby ... Lav fuld replacement til den nye lobby når alt
det er gjort." In Studio, unpublished.

**The swap.** `GameManager.buildLobby` stands the spawn pad on the mall's spawn (`LobbySpawnFloorModelName =
"LobbyMallPreview"`) and does NOT build the tunnel lobby (no mesh bake at server start; the lobby is on screen in
about 11-20 s in Studio). The first lobby is still built for its shop boxes and supporters board and then emptied;
the supporters board's live renderer is kept out of sight under the mall and copied to the directory board.
`workspace.LobbyUseTunnel = true` brings the tunnel lobby back (the mall is then parked and previewed by E, as
before); a missing or unready mall model also falls back to it. `Lobby Mall Preview` now only deletes the mall on
round servers unless that switch is set. The mall model is static and saved in the place: a publish carries it.
Adapted to the mall as lobby: `ReplicatedFirst/Lobby Loading Screen` (it waited for the tunnel lobby's `Ready` for
ever: "STREAMING THE LOBBY ... taking longer"), `Bootstrap` monitor, `Level Leaderboards`, `Lobby Tunnel Reach`
(server and client), `First Entry Guide` (camera aim and the START LEVEL 1 HERE marker find mall pads),
`Friend Boost Client` and `UIRegression` (lobby bounds), `Level6PreviewAccess` and `Level6PreviewTransport` (the
floor model a returning body lands on), `Lobby DJ Client` (lamps), `LunaTribute` (Luna's bed and plate stand against
the east wall between Poolrooms and Cinema; her strolls are in the hall).
NOT carried over, because they belong to the tunnel lobby's own build: its ceiling sweeps and party button, the
Level 3 gate flicker, the Level 6 bay dressing, the dev gates (R4DevGateController), the fence and road cases.
Tested in Studio play, one player: spawn in the mall, 24 stations, a Level 1 round from station 201, Level 6 from
station 221, shop card, DJ prompt, seven board sheets, the creature past the tape, Luna in her bed. NOT tested:
coming BACK to the lobby after a round or from Levels 5/6, Level 5 from a mall pad, two players, a phone, a live
server.
The loading screen in Studio differed from git (another session's edit, MeshContent-based census); the working file
is now Studio's text plus the mall change.

**Before the swap (`MALL_FINISH_20261013`).**
- LEVEL SIGNS seen through walls: `Anchors.LevelMarkers.Level1..6`, one over each shop front; `Lobby Mall Client`
  (new LocalScript) hangs a BillboardGui on each (AlwaysOnTop) in the L4 UI style: tile #161D20 plate, line stroke,
  rail-teal bar, "LEVEL n" in Montserrat Heavy cream, the level's name in Roboto Mono teal.
- CRATES bob (0.32 studs, each out of step; attributes `MallCrateOrigin` / `MallCratePhase`).
- DYING LAMPS: of the hall's panels the importer makes six more dead and five more flicker (seeded draw: 11 lit,
  6 flickering, 6 dead); the client stutters lamp and lens. ReduceFlashing = steady dim lamps and still crates.
- THE TAPE: `Anchors.TapeBlocker`, one unseen block wall to wall, 3.5 studs high: a walk stops at it (measured
  z -622.0), a jump clears it (reached -600.7) and the creature wakes.
`qa.py shot` does not capture always-on-top BillboardGuis (the signs were photographed with AlwaysOnTop off).
Checkout gotcha: `git sparse-checkout add <dir>` reapplies the cone and REMOVES tracked files that were added with
`git add --sparse` outside it (they stay in git; add their folders to the cone to get them back), and deletes
ignored folders inside them (`textures_pbr`: rerun `make_pbr.py`).

**2026-10-13, later: the level signs seen through walls are REMOVED** (owner: "Fjern: Level-skilte gennem vægge").
`Lobby Mall Client` no longer draws them and the importer no longer makes `Anchors.LevelMarkers`; the crates' bob,
the dying lamps and the tape's blocker stay. The shops' own name signs ("1 OFFICE" ...) are what says where a level is.


## 2026-10-13 - lobby feedback: no numbers on the shop signs, no START LEVEL 1 HERE, boards the shape of their sheets

Owner's three points, all in Studio (unpublished):
- The shop signs read `OFFICE`, `POOLROOMS`, `MALL PARTY`, `CINEMA`, `THE VOID`, `PLAY ZONE` (they were "1 OFFICE" ...).
  The pads' STATION 1-4 plates keep their numbers: they are how a pad is told from its neighbour.
- `START_MARKER_REMOVED_20261013`: the "START LEVEL 1 HERE" marker seen through walls is gone from First Entry Guide.
  The welcome card's row is now "PICK A LEVEL" and the Help text no longer names the marker.
- Every notice board is exactly the shape of what is pinned to it (level list 4.24 x 10, supporters 17.14 x 12) with
  the 0.2-stud oak frame round it; `Level Leaderboards` fills the board (no margin). It was a narrow sheet on a wide
  black board. The Level 3 and 4 boards moved 0.4 along the wall (z -728.4) for `check_mall.py`'s 20-wide corridor proof.

## 2026-10-13 - mall: the tunnel lobby's DJ booth, a hall 27 studs high, a wing that fades to dark

Owner's three points, in Studio (unpublished).
- `BOOTH_FROM_TUNNEL_20261013`: the mall's own deck, steps, folding table, console and speakers are no longer put in
  the place (`REPLACED` in import_mall.py; the banner and chairs stay; `mall.blend` still holds them). In their place
  stands the tunnel lobby's booth: stage deck with six steps, rear rail, DJ console, two speaker towers, two
  subwoofers and the two records, on the spot it had in the tunnel (the mall was laid out on the same centre).
  `tools/lobby_mall/install_booth.py` made it permanent: the booth only existed as numbers in
  `ServerStorage.LobbyReimaginedBlenderSource20261001R4` that RuntimeBake turned into session content; the script
  reads them in Edit and uploads the 1024 atlas and seven meshes as group assets (`booth_ids.json`). The console is
  `Anchors.DJConsole` (the desk Lobby DJ uses); deck, steps and rail collide through unseen blocks in `Anchors`;
  `Lobby Mall Client` turns the records. Tested in play: up the steps (y 37.7 on the deck), DJ mode behind the desk.
  The speaker towers stand beside the deck at x 499 and 541 and are 22 studs tall.
- The hall is 27.04 studs high (`CEIL = 57.04`; it was 20.8, and 16 before that). I read "30% higher to the
  ceiling" as the hall again; the shops' own ceilings are still 14 studs.
- `DARK_FADE_20261013`: the importer cuts the wing's long parts into lengths of 20 studs or less and shades each by
  its depth past the tape ((1 - depth/150)^1.5: two thirds at 40 studs, a third at 80, black from 150); five
  surface-mounted panels over the first 80 studs all flicker (lamp 1.3); RoundUI's ambient for a player walking in
  falls to the dark pass over 140 studs (it was 30). The glossy tile floor mirrors what is ahead, so from the tape
  the wing's floor reads dark at once while its walls and ceiling fade.

**2026-10-13, later (`FLICKER_ONLY_PAST_TAPE_20261013`).** Owner: "The lights in the lobby should only flicker past
the do not cross point". In the hall every lit panel is steady (17 lit, 6 dead, none flickering); only the dark
wing's five panels flicker. Measured in play: over 4 s no hall lamp changed brightness, all five wing lamps did.


## 2026-10-13 - a creator on the gift list: Epicwizrdcat (`CREATOR_GIFT_LIST_20261013`)

Owner: "Make sure that this person has the new skin: Epicwizrdcat ... toggled on from now so if he wants to switch
back then he has to do it from the skins tab". `ZyntraSkins.CreatorGifts = {[1931934638] = "CreatorGold"}` (the
account's UserId, looked up from the name on users.roblox.com): on the account's first profile load after this is
published, ZyntraMonetization gives the suit AND equips it in one saved write with the marker
`Grants.CreatorGift_CreatorGold`. Once only: switching away in the Skins tab sticks, and so does a developer's TAKE.
No production data was touched from here; it happens on a live server when he next joins. Tested in Studio play
with the Studio account put on the list for one session (then removed): the suit was on at load, and EquipSkin back
to the default worked. Add further creators as lines in that table.

## 2026-10-13 - a hold ring that can be seen; the mall's light 30 % down with five tired panels

- `HOLD_RING_20261013` (owner, of the ring that fills while E is held, e.g. EXTRACT FUSE: "meget mere tydelig og
  tykkere ... en lysere farve"). `RoundHud.Ring`: stroke 4 px (it was 2) and the circle is inset by the stroke's
  thickness. A UIStroke lies OUTSIDE its frame and each half of the ring sits in a clipping mask, so the old ring, on
  a circle the size of the slot, showed only its inner edge. `Found Footage HUD` paints it pale mint (170,255,240;
  it was rail teal). The ring is shared with the round's exit chip (Round Exit Client), which gets the thickness and
  keeps its teal. Looked at as four test rings drawn on screen in play (25/50/75/100 %); a prompt plate itself
  cannot be photographed by `qa.py shot`.
- `DIMMER_20261013` (owner: "dim the lights down by 30% in the lobby and make some light be even darker"). Measured
  on two fixed views of the hall, mean luminance fell from 161 to 109 and from 174 to 122 (-32 % and -30 %).
  RoundUI's ambient in the mall is 150,143,118 (it was 196,187,154); a lit hall panel is now a SpotLight cone down
  from the ceiling (brightness 1.5, angle 125, range 60: a PointLight 27 studs up gave the floor almost nothing, so
  the hall was all ambient); five of the seventeen lit panels (seeded draw) are tired: 0.4, a duller lens, a faint
  sheen, steady. Shop washes and skin spots are 30 % down. On a device that drops local lamps the hall is evenly
  lit at the new ambient.
  Importer gotcha, met again: a `%` in a comment inside a Luau template is a Python format error, and it fails
  AFTER the model has been destroyed and half rebuilt. Rerun the importer at once when it stops.

## 2026-10-13 - is the mall lobby heavier than the tunnel lobby it replaced? Measured: no

Owner: "make sure that the new lobby doesn't fuck with load speed or client FPS". Same Mac, same Studio session,
standing at the lobby spawn (client `Stats`, five seconds each; the tunnel lobby brought back for the comparison
with `workspace.LobbyUseTunnel`, then cleared):

| at the spawn | mall lobby | tunnel lobby |
|---|---|---|
| lobby on screen (LobbyLoading) | 10.9 s, 23 assets | 18.0 s, 35 assets |
| scene draw calls | 181 | 195 |
| triangles | 131,000 | 163,000 |
| parts on the client | 2,114 | 2,605 |
| lights | 41 | 120 |
| frames a second | 15.1 | 14.9 |

The frame rate is this Mac's ceiling in Studio, not the lobby's cost: it was 14.9 with 41 draw calls on screen (mid
hall) and 14.2 with 324 (at Shop & Supplies, the heaviest view: six suit models and ten product crates). Server side
nothing was added that runs per frame; the mall has 24 queue stations, as the tunnel lobby had, and no mesh bake at
server start. Nothing needed changing. Not measured: a phone, a live server with several players.

## 2026-10-13 - mall: every queue area wears its level's floor; MALL PARTY the city car carpet (`CITY_CARPET_20261013`)

Owner: "Make sure the floor at every level queue up area matches some of the floor of the level and not tiles, the
tiles stop right at the entry to the level. Of course the poolrooms can have tiles, but the tiles that match the
level. For the level 3 I specifically want the city car carpet on the floor."

- `build_mall.py`: `Shop<n>_QueueFloor` no longer takes the hall's tile. Per shop: OFFICE `beige_carpet`,
  POOLROOMS `small_tile` (the level's own small pool tile), MALL PARTY `road_carpet`, CINEMA `triangle_carpet`,
  THE VOID `rose`, PLAY ZONE `puzzle_mat`. The hall's tile ends on the shop's front line.
- `import_mall.py`: in MALL PARTY the queue floor and the showcase floor are merged into ONE part, `Shop3_Floor`,
  and it wears Level 3's real city carpet as a `Texture` on the top face (slot
  `ReplicatedStorage["Level 3 Assets"].CityPlayCarpetTexture`, else `rbxassetid://75635502248205`; 52 studs a
  repeat, Carpet coloured 190,188,166, as in the level). One part so the roads run unbroken from the entry to the
  back wall; a material variant would have been laid from the world origin and cut differently.
- Checked in play from each entry (pictures `fl2_*` in `artifacts/mobile-qa-20261012`): six different floors, tile
  ends at each entry, the city carpet covers the whole MALL PARTY shop under all four pads. `check_mall.py` passes
  (1969 parts, 0 errors); the model in Studio has 2107 parts. Not published (the owner publishes).

## 2026-10-13 - picture set 2: 26 store pictures in the in-game look (`artifacts/promo-20261013-ingame`)

Owner: a complete new set (icons, thumbnails, gallery, covers) "exactly like we did before", slightly better, still
in-game photographs with a slight edit that pops; POV torch pictures at the Level 1 Entity; Level 1 only in the dim
setting or with the lights off; Level 3 with the Mall Manager and Level 6 with the Counter.

- Generated by Codex (gpt-6.1-sol, Medium) with its image tool from the game's own references (`refs_new/`, brief in
  `brief.md`, one prompt a picture in `prompts.json`); the job stopped once on "Selected model is at capacity" after
  four pictures and was resumed. All 26 exist in `raw/`; Codex's own notes on each are in `logs/`.
- Finished by `tools/promo/finish_ingame2.py`: crop to 1920x1080 or 1024x1024, a light contrast/colour/sharpen edit,
  the small lock-up on thumbnails, the title on covers, icons also at 512. New on this run: pictures whose mean
  brightness is under 9 % get their shadows lifted (gamma, at most 0.70), because three thumbnails and a cover were
  too black to read as a small tile.
- Delivered to `~/Desktop/Backrooms Stay Quiet - Nye billeder 2026-10-13` (48 files, two overview sheets). Nothing
  uploaded to Roblox. Weakest: the Level 2 hall (reads as a render more than as the game), the red-eyes icon (two dots
  and a patch of carpet at small size).

## 2026-10-13 - the mall lobby dressed for Halloween, with a sale (`LOBBY_HALLOWEEN_20261013`, `HALLOWEEN_SALE_20261013`)

Owner: "Via blender I want you to make the lobby be halloween decorated 90s middle class mall style, with jack o
lanterns, and such, before you do it make some pictures on how the lobby can have that halloween vibe, and also make
halloween sale signs around the lobby and at the shop saying 66,6 halloween discount on everything. Og en reentry
package med 3 reentry til ens pris."

**Pictures first.** `artifacts/lobby-halloween-20261013/`: `brief.md`, nine real screenshots in `refs/`, seven concept
pictures in `concepts/` (Codex, gpt-6.1-sol Medium, built-in image tool; H01 hall, H02 stand, H03 entry, H04 stage,
H05 planter, H06 dark wing, H07 prop sheet). The build follows them.

**The dressing** (`tools/lobby_mall/build_halloween.py`, Blender; `install_halloween.py`, Studio in Edit).
- A kit of 20 low-polygon meshes with a colour per vertex, modelled from plain solids: jack-o'-lantern (212
  triangles) and its glowing face (a second Neon mesh a hair outside the painted one), hay bale, corn stalks, two
  pots of mums, scarecrow, bedsheet ghost, bat, pail, balloon and balloon bunch, crepe swag (orange one side, black
  the other), two pennant strings, cardboard skeleton / cat / bat, corner cobweb, price burst.
- 216 props in the hall: corn stalks or a skeleton on every pier with pumpkins at its foot (never in front of a
  board or a planter), swags pier to pier, a pennant string under each shop sign and seven across the hall, ghosts and
  bats on lines, both planters as a seasonal display with a scarecrow, pumpkins on the stage edge, a row of lanterns
  on the tape and five alone in the dark wing. 27 signs: a banner over the hall, on three walls, over the stage and
  round the stand's top; six danglers and six counter bursts at the stand; four A-frame standees (two
  `HALLOWEEN SALE / 66.6% OFF EVERYTHING`, two `RE-ENTRY / 3 FOR 1 / HALLOWEEN ONLY`).
- `check_halloween()` stops the build if a prop stands on a queue pad, a shop spot, the spawn or in the walking
  lane, hangs into head height, or a sign carries other lettering than the sale's.
- In Studio: `Workspace.LobbyMallPreview.Halloween` (354 parts, 22 PointLights without shadows, 38 sign faces). It
  lives inside the mall's model, so a round server drops it with the mall, and `import_mall.py` now carries it over
  when the mall is rebuilt. Mesh ids: `tools/lobby_mall/halloween_ids.json`. Remove it after Halloween with
  `install_halloween.py --remove`.
- Cost, measured at the spawn in one sitting: draw calls 175 -> 219, triangles 131,000 -> 163,000, parts 2,113 ->
  2,467, lights 41 -> 63; frames a second unchanged (13.9 without, 14.7 with: this Mac's ceiling). The loading screen
  does not wait for the dressing (`Lobby Loading Screen`: the census skips `Halloween`), so the gate is 24 assets with
  or without it; the time to open was 19.4 s without and 14.8 s with in back-to-back runs, i.e. the Mac's own noise.
- Walked on foot (a 24-point route through both sides, the stand, the stage and the tape): no prop blocks a path.

**The sale** (takes effect when published; the lobby's signs promise it).
- `ZyntraConfig.HalloweenSale = {Enabled = true, EndsAt = 1793577600 (2026-11-02 00:00 UTC), PercentOff = 66.6,
  ReentryGrant = 3}`, `HalloweenSaleActive()`, `SaleTokens(n)`. While it runs, at module load: every token price is
  cut and rounded, never under 1 (Entity Shield 5 -> 2, Speed Potion 3 -> 1, Route Marker Pack 2 -> 1; upgrade levels
  1,1,1,1,2,2,2,3,3,3 instead of 1..10; `ZyntraSkins` cuts the token suits 25/75/300 -> 8/25/100), descriptions that
  quote a price are rewritten, and one Emergency Re-entry purchase banks THREE credits (product name
  "Emergency Re-entry x3", the store button and the death card say "BUY 3 RE-ENTRIES"; `ZyntraReentryGrant` attribute).
- `Lobby Mall Preview` (server) rewrites the stand's printed price plates once per lobby server from what is true
  (token prices from the config, Robux prices from `MarketplaceService:GetProductInfo`), adding "(WAS n)" when lower,
  and takes the sale SIGNS down when the sale is over (the pumpkins stay until removed).
- **Robux prices are not touched.** They live on Roblox; the game shows whatever Roblox charges. Regular prices read
  2026-10-13: passes 149 (Entity Detector, Advanced Equipment), 99 (Supporter, Glowstick Customizer), skins 149 / 99,
  products 149 / 49 (tokens), 69 (Expedition Pack), 29 (Emergency Re-entry). Until the owner lowers them (or says
  go), "66.6% off everything" is true for token prices only.
- Not tested: a real re-entry purchase (Studio cannot take Robux), the end of the sale on a live server (a server
  that started before EndsAt keeps sale prices until it closes), phones, two players. Nothing is published.

## 2026-10-13 - Halloween sale: the Robux prices cut on Roblox (the owner's go)

Owner: "66,6% på alt så gå ind og ændre prisen på aaalt i vores butik undtagen domstol selvfølgelig" ("domstol" read
as "donationer": the donations keep their prices). Done with `tools/promo/halloween_prices.py --apply`, from the
owner's signed-in Creator Dashboard tab (one Chrome window opened for it and closed again, no keys or clicks); every
price read back. Records: `artifacts/store-prices-halloween-20261013/before.json` and `after.json`.

| item | regular | sale |
|---|---|---|
| Entity Detector, Advanced Equipment, False Sun (passes), 20 Research Tokens, Token Earner 2x | 149 | 50 |
| Zyntra Supporter, Glowstick Customizer, Static Wraith | 99 | 33 |
| Token Earner 3x / 5x | 299 / 399 | 100 / 133 |
| Expedition Pack | 69 | 23 |
| 4 Research Tokens | 49 | 16 |
| Emergency Re-entry | 29 | 10 |

- LIVE AT ONCE, publish or not: the published game charges these prices from this moment. Until the Halloween build
  is published it has no sale signs, still grants ONE re-entry a purchase and still shows regular token prices.
- Not touched: the nine donation entries (eight products and the 20K pass) and the three Token Earner upgrade passes,
  which have been off sale since 2026-10-08.
- In the build waiting in Studio the listed `Price` fields follow while the sale runs (`RegularPrice` keeps the old
  one; `ZyntraSkins` does the same for the two Robux suits), because the server credits a newly seen pass to the
  supporters' board at its listed price. The stand's plates read "50 ROBUX (WAS 149)" from Roblox itself.
- **To end the sale:** `python3 tools/promo/halloween_prices.py --restore` (needs a signed-in Creator Dashboard tab in
  Chrome) puts the regular prices back from `before.json`. The switch in `ZyntraConfig` ends the token prices and the
  3-for-1 by itself on 2026-11-02 00:00 UTC; it cannot restore prices on Roblox.

## 2026-10-13 - Halloween dusk: the dressed lobby is dimmer so the lanterns carry it (`HALLOWEEN_DUSK_20261013`)

Owner: "Can you make it a bit darker in the lobby to give it that spooky, cozy halloween vibe so the jack o lanterns
pop". Only while `LobbyMallPreview.Halloween` exists, and only on the client (nothing on the server changes, so
`install_halloween.py --remove` puts the old light back):
- `RoundUI`: the hall's ambient light goes from 150,143,118 to a cool dusk, 76,68,94 (`revisedLobbyLighting.mallDusk`).
- `Lobby Mall Client`: the 17 hall panels burn at 30 % in a cool white (196,200,236), their lenses go grey-violet and
  the sheen they lay on the floor drops to 0.25. The wing's dying lamps, the shops' own lamps and the backlit shop
  signs are untouched, so the shops and the signs now glow out of the gloom.
- `build_halloween.py` / `install_halloween.py`: every big lantern carries a PointLight (36 instead of 22), brightness
  1.5, range 8 + 4 x its size, no shadows; the sale signs take 40 % of the room's light instead of all of it, so they
  still read.
- Measured in play: the hall's picture is 45 % darker (mean brightness 133 -> 72 from the spawn, 134 -> 76 at the
  stand). A first try with WARM dim panels made the whole hall amber and the lanterns vanished in it: the room has to
  be cool for the orange to pop.
- Frame rate, compared inside one session by switching the dressing and its lights off and on: 14.8 / 15.0 / 14.5 /
  13.7 with, 15.0 / 13.2 / 14.5 / 15.1 without: no difference this Mac can show. Not measured on a phone.
- Later the same day the owner had the scarecrow at the spawn removed ("remove the scarecrow at spawn"): the arrival
  planter keeps its mums, hay bales, pumpkins and pails; the north planter keeps its scarecrow (215 props, 353 parts).
- Then, from the live game (owner, with a screenshot from the spawn): "remove this bench and flower bed here it
  blocks the shop". The arrival planter with its two benches is out of the mall itself (`build_mall.py`: only
  `PlanterNorth` is built; 1933 parts, check 0 errors, imported: the model has 2424 parts) and its Halloween display
  is out of `build_halloween.py` (201 props, 333 parts, 33 lantern lights). From the spawn the stand is in plain view.

## 2026-10-13 - less sale in the hall, cartons at the shop, suits at ease and turning

Owner: "Der er gået lidt for meget salg i den med de der banner over det hele med halloween 66,6% off. bare lad de
skilte være ved shoppen og lad banner være men der skal bare stå Happy Halloween i stedet for. Kasserne med items
passer ikke længere til vores nye lobby stil ... Kan du også gøre sådan at de der skins ... ikke står i t pose men
med armene naturligt nede og så sørge for at de spinner stille og roligt på den runde [plade] de står på".

- **Banners** (`build_halloween.py`): the hall banner, the three wall banners and the one over the stage read
  `HAPPY HALLOWEEN`. The sale's lettering is left at the stand only (its band, danglers, counter bursts, four
  standees); `check_halloween()` now fails a sale sign further than 26 studs from the stand's middle.
- **Cartons** (`MALL_CARTON_20261013`): the crates over the buy spots were copies of the first lobby's holograms (a
  glowing see-through cube with a lit edge). Now each is a shipping carton: `tools/lobby_mall/build_carton.py`
  (Blender: kraft cardboard, packing tape over the top and a hand's width down two sides, 120 triangles),
  `install_carton.py` (group mesh, `ServerStorage.MallShopCarton`, id in `carton_ids.json`), and
  `LobbyShopDisplay` prints a label on its four sides: cream paper, the mall's teal/pink/purple stripe band, the
  product's own picture in a dark frame, its name in the sign font. Same size, place, bob and name sign as before;
  without the mesh a plain cardboard block wears the label.
- **Suits** (`SKINS_AT_EASE_20261013`, `import_mall.py`): each suit on a plinth has its upper arms turned about the
  shoulder bones until they hang 13 degrees out from the body, forearms 5 (the rig's bind pose is a T). `Lobby Mall
  Client` turns each suit about its plinth's middle, one turn in 26 seconds, for everybody (a slow turn is no
  flashing); the VIEW SKIN prompt stays on the plinth. Checked in play: arms down on all six, front then back seven
  seconds apart, no console errors. Not published.
