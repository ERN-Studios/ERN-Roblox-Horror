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
- The publish click by Codex computer use must be started with the model pinned (`-m gpt-6.1-sol`, Low,
  `service_tier="default"`): `~/.codex/config.toml` on this Mac defaults to ultra/priority, and
  `tools/agents/start-codex.sh` rejects `--enable`. `~/Projects/stayquiet-session-tools/publish_when_idle.sh`.
