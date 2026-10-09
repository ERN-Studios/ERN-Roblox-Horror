# Level 1 Blender facelift: how it works, and what Level 2 has to change to copy it

Line numbers come from the current working copy. GameManager has uncommitted changes, so its line numbers may drift.

## 0. Five things to know first

1. **Level 1's facelift adds geometry on top of the old maze; it does not replace it.** MazeGenerator still builds every original Part, and they keep all collision and query. The renderer makes them invisible (`Transparency=1`) and lays the Blender rooms over them as extra MeshParts.
   - A real preview round measured `meshes: 19625` with V1 (`artifacts/level1-facelift-20261002/runtime-round-1.json`) and `meshes: 20357` with V2 (`artifacts/level1-quality-20261002/runtime-seed1-geometry-final.json`), across 1,600 rooms.
   - One kit room is 15–47 instances (Folders, Models, MeshParts, SurfaceAppearances, collider Parts), measured from `verified-studio/Level1BlenderKit.instances.json`.
   - **If Level 2 copies this literally, its instance count goes up, not down.** The owner's 52k → "far fewer" goal needs the generator to skip building the native visual parts.
2. **Meshes do not go through FBX.** Each component × material becomes a custom binary chunk (base64). That chunk is rebuilt as an EditableMesh in Studio Edit and uploaded with `AssetService:CreateAssetAsync`. The FBX is only for review and interchange.
3. **PBR maps are uploaded with StudioMCP `upload_image`**, served from a loopback HTTP server. The kit gets `SurfaceAppearance "BlenderPBR"` at install time.
4. **The preview is a real round with no progression:** solo, developers only, its own reserved server, gated by the `Level1BlenderPreviewActive` attribute.
5. **The lobby entry position cannot be copied as-is to Level 2.** The host offset is world `(-20, 4.42, 0)` from `ChamberFloor`. Level 2's room sits on the opposite side of the tunnel, so that offset lands in its doorway. The mirrored far-wall spot lands in the "Lobby L2 Tiled Column" (§9).

## 1. How the kit is authored (`tools/level1_blender/build.py`, `build_v2.py`)

**How it runs**
- Headless only: `assert bpy.app.background` (build.py:20). Command is `D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P …` (README:12).
- All geometry is procedural `bmesh`. No hand modelling, no Meshy.
- V2 imports build.py as a module (build_v2.py:12-14) and redirects output to `assets/level1/blender-v2` (build_v2.py:15-16).

**Units and axes**
- `S = 0.28` metres per stud (build.py:15).
- Axis map `C`: Blender (x,y,z) → Roblox (x, z, −y) (build.py:16; manifest `"axis"` at :437).
- Inputs to `place()` are Roblox-local studs (build.py:335-339).

**Materials** (`material()`, build.py:28-61)
- Each is a Principled BSDF, with optional maps `<stem>_albedo/_rough/_normal.png` (non-albedo maps set to Non-Color).
- Custom property `l1_tile_studs`. The manifest records color, roughness, metalness, emission, maps, `tileStuds`, and `robloxMaterial` (`"Neon" if emission else "SmoothPlastic"`).
- V2 `finish_material()` (build_v2.py:33-52) rebuilds prop materials with albedo `prop_<stem>_albedo.png` plus shared `prop_normal/prop_rough.png` and `prop_metal.png` or `prop_paintmetal.png`. It sets `robloxMaterial` to `"Metal"` or `"SmoothPlastic"`.
- V2 Wallpaper uses a MULTIPLY tint `[255,235,150]` over the untouched original albedo (build_v2.py:103-114).
- GreenGlass is `robloxMaterial="Glass"`, `transparency=.38` (build_v2.py:119-125).

**UVs** (`Mesh.finish`, build.py:116-135)
- Per-face planar box projection on the dominant normal axis, `uv = coord / tileStuds`.
- UVs are computed in studs before the `S` scale, so they are physically scaled and textures repeat every N studs.

**Colliders**
- `Mesh.collider(center,size)` (build.py:111-114) stores box colliders already converted to Roblox space.
- Floor, Ceiling, WallHalf, Pillar, WallShort and props get authored boxes.

**The cell contract** (README:25-31; scene props build.py:549-550)
- Cell 24, wall height 14, full wall thickness 2.
- Each room carries only half-walls: `WallHalf` is 24×14×1, placed at ±11.5 (build.py:157-161, 358-361). Two neighbours' half-walls make the 2-stud wall on the shared boundary.
- Room origin is at the floor centre (`floorTop 0`).

**Sockets and masks**
- Open-socket bits are N(+Z)=1, E(+X)=2, S(−Z)=4, W(−X)=8 (build.py:437).
- A wall is placed only where its bit is closed (build.py:358-361).
- Names come from the dict at build.py:345-347, e.g. `DeadEndN`, `CornerNE`, `StraightNS`, `JunctionNES`, `Cross`.

**Variants and naming**
- V1, 34 rooms:
  - Every mask 1-15 has `<Name>_Quiet` (variant 0) and `<Name>_ColumnBay` (variant 1, two `Pillar` at (±9.6, ±9.6)) (build.py:348-367).
  - Plus 4 special rooms, variant 2 (build.py:369-398): `MaintenanceAlcove` (mask 1), `OfficeRemnant` (5), `RecordsBay` (3), `ElevatorArrival` (1).
  - Gallery offsets `(index%6)*30` apply to Blender objects only, not to manifest cframes.
- V2, 42 rooms (build_v2.py:246-286):
  - `selectionWeight` is Quiet 16, ColumnBay 1, special 4 (:249). ColumnBay keeps one pillar (:252-257).
  - New `LowWall_%02d` rooms for masks 1,3,5,7,10,11,13,14: variant 3, weight 3, `shortWall=true`, `shortWallHeight=8.5`. One `WallShort` (6×8.5) sits at (7.8,0,9.7) or (9.7,0,7.8) (:259-286).
- Blender collections carry custom props `OpenMask`, `CellSize`, `WallHeight`, `SelectionWeight`, `ShortWall`, `ShortWallHeight` (build.py:354, build_v2.py:251, 265-267). Objects carry `l1_component` and `l1_role`.
- Clear-zone rule (enforced in `check_assets.py:54-56`): details stay out of the central ±8 square and the ±3 cardinal lanes.

**RoomRole values**
- `place(..., role=)` (build.py:332-341) takes one of `SurfaceFloor`, `SurfaceCeiling`, `Fixture`, `ShellWalls`, or `Detail` (default).
- The installer adds `Collider` (import_assets.py:100). README:43-46 documents this.

**Components**
- V1 has 30 (build.py:138-316). V2 has 41 and adds `WallShort`, `RelayShell`, `RelayDoor`, `FuseBoxShell`, `FuseSocket`, `LeverShell`, `LeverShaft`, `LeverKnob`, `FuseCore`, `FuseCap`, `ExitPortal`, `ExitDoor`, plus re-modelled 5-bank `Fluorescent` and `FluorescentDark` (build_v2.py:74-243).
- Aliases are in manifest `aliases`. V2 maps `FloorPanel→Floor`, `CeilingPanel→Ceiling`, `LightFixture/GridFixture→Fluorescent`, `FuseRelay→RelayShell`, `FuseBox→FuseBoxShell`, `ExitFrame→ExitPortal`, and `MetalPanel/ElevatorMetal/ElevatorDoor→ElevatorDoorSkin` (build.py:440-442, build_v2.py:298-299).
- Totals (from the manifests): V1 is 61 chunks / 11,036 tris. V2 is 93 chunks / 22,768 tris. The biggest chunk is Telephone/Dark at 2,456 tris.

**Concept art**
- ImageGen reference sheets and their prompts are in `assets/level1/blender-v2/concept/prompts.json`: puzzle/exit/fixture sheet, exit door, original-grille fixture.
- V1's reference is `concepts/room-direction.png` (build.py:443).
- Renders: `renders/{corridor,maintenance,catalogue,puzzle-detail,exit-detail}.png` (Cycles, AgX) (build.py:469-530, build_v2.py:310-348).

## 2. Export format (build.py:401-446, 559-569)

**Chunk files**
- One chunk per (component, material) is written to `export/chunks/c%05d.b64`. Coordinates are Roblox studs, re-centred on the chunk's bbox centre.
- Binary layout, little-endian:
  - `u32 nv, nn, nu, nf`
  - then `f32` positions ×nv, `f32` normals ×nn, `f32` UVs ×nu
  - then `u32[9]` per triangle: (v, n, u) ×3
- Positions, normals and UVs are de-duplicated with `np.unique`. V is flipped (`1-v`).
- Hard limit: `len(ts) <= 20000 and len(pv) <= 60000` (build.py:422), which are the EditableMesh limits. V2 also asserts ≤150 chunks (build_v2.py:306; check_assets.py:15).

**`export/manifest.json`**
- Top-level fields: `version`, `build` (`level1-blender-20261002` / `level1-quality-20261002-v2`), `scaleMetresPerStud`, `cellSize`, `wallHeight`, `wallThickness`, `floorTop`, `axis`, `socketBits`.
- `components{chunks, colliders, pivot}`, `materials`, `aliases`.
- `rooms{mask, variant, placements[{component, cf[12], role}], markers{ObjectiveAnchor}, cellSize, clearLane, selectionWeight, shortWall…}`.
- `chunks[{id, component, material, tris, verts, center, size, sha256, wireSha256}]`.
- V2 adds `wallpaperSourceAsset 87947439437597`, `fixture{banks 5, grid [5,5], sourceAsset 135786374638992}`, and `puzzleVisual` flags (build_v2.py:293-305).

**FBX**
- `Level1_ModularKit.fbx` contains only the "L1 Prop Library" (each shared component once) (build.py:559-564).
- Settings: `axis_forward="-Z"`, `axis_up="Y"`, `apply_unit_scale`, `path_mode="RELATIVE"`, `mesh_smooth_type="FACE"`.
- The `.blend` keeps room assembly as collections. sha256 of both files is written to `native-files.json`.
- No `.blend1` backups are written (`save_version = 0`, build.py:554).

**Checks**
- `check_assets.py` (pure Python):
  - binary sizes and indices, finite floats, hashes (:20-33)
  - floor/ceiling counts per room, wall count = 4 − popcount(mask) (:35-41)
  - collider lane/centre clearance via transformed OBBs (:45-56), walls never on open sockets (:57-60), all 15 masks present (:61)
  - PBR files exist; V2 asserts the wallpaper albedo bytes equal the original and its receipt is `rbxassetid://87947439437597` (:68-91)
- `verify_native.py` (headless Blender):
  - relative `//textures/` paths, collections ↔ manifest, a fresh FBX re-import with matching materials
  - writes `native-verification.json` (V2: Blender 5.2.0 LTS, 42 room collections, 41 FBX meshes, `studioGameplayVerified:false`)

## 3. How meshes get into Roblox (`import_assets.py`)

**Default run** writes only a reviewable `export/install.luau` (:198-200). `--upload` and `--install` both require an exact `--studio-id` (:201). Place and group are pinned to `PLACE=131311258779917`, `GROUP=1039373905` (:16-17).

**Upload** (`upload()`, :141-179)
- It reuses the Level 4 binary mesh builder by text-slicing `tools/level4_blender/upload.luau` between `"local function build(b)"` and `"local function run()"` (:142-143).
- That builder (`upload.luau:11-38`) does `AS:CreateEditableMesh()`, `AddVertex`/`AddNormal`/`AddUV`, `AddTriangle`, `SetFaceNormals`, `SetFaceUVs`.
- Level 1 does **not** use Level 4's HTTP-loopback `run()` (upload.luau:40-77). Instead it inlines the base64 chunks into the `execute_luau` source:
  - batches of up to 650,000 chars (:149)
  - `ENC:Base64Decode` → `build` → `AS:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name="L1_ModularKit_<id>", CreatorId=1039373905, CreatorType=Group})` (:156-163)
  - all in `datamodel_type:"Edit"`
- The inlining matches CLAUDE.md 2026-10-02: the MCP sandbox has no HttpService.

**Receipts**
- `export/roblox-assets.json` = `{ "<chunkId>": {assetId, wireSha256, group} }`, written after every batch (:175-177).
- An asset ID is attached only if `rec.wireSha256 == chunk.wireSha256` (:38-40).

**Hash reuse**
- For `blender-v2`, V1 receipts are indexed by `wireSha256` and copied with `reusedFrom:"level1-blender-20261002"` (:23-29).
- Result: 47 reused + 46 new = 93 unique IDs (`artifacts/level1-quality-20261002/assets-upload-parity.json` counts).

## 4. How PBR textures are published

**Upload** (`publish_textures.py`)
- Collects every map named in the manifest and diffs sha256 against `textures/published.json`.
- Serves the folder on `ThreadingHTTPServer(("127.0.0.1",0))` (:34-37), `select_studio(…"BACKROOMS: STAY QUIET…")` (:41), then MCP `upload_image {imagePaths:[http URLs]}` (:43-44).
- Receipt `{name:{assetId:"rbxassetid://…", sha256, file}}` is written per file, so the run is resumable (:49-50).
- The installer also accepts a hand-written `textures/roblox-assets.json` filename→ID map (import_assets.py:30-37).

**V2 derivation** (`prepare_v2_textures.py`)
- Copies V1 carpet/ceiling maps and reuses their receipts when the hash matches (:28-35).
- Wallpaper albedo is the exact original asset `87947439437597`. Its pixels were pulled by `export_fixture_reference.py` using `CreateEditableImageAsync` and `ReadPixelsBuffer` in 16-row strips (:25, :39), and its receipt points at the original ID (:37-39).
- Normal, rough and height maps are derived with `tools/level4_blender/make_pbr.py` (`make_pbr(... strength=2.2, rough_base=.88 …)`) (:10-13, :41-42).
- Prop finishes are deterministic grain (`default_rng(1039373905)`) plus 7 albedo colours.
- Previous receipts are kept for unchanged pixels (:70-73). `derivation.json` records the result.
- V2 has 20 maps in `textures/published.json`, e.g. carpet albedo `88740987992118`, wallpaper normal `122804131972663`, prop normal `92066611037304`.

**Applied at install** (import_assets.py:83-90)
- Only non-emissive materials that have maps get a `SurfaceAppearance` named `BlenderPBR`.
- Map mapping: `ColorMap`, `NormalMap`, `RoughnessMap`, `MetalnessMap` ← albedo, normal, rough, metal. These are legacy string properties; this is fine in Edit/plugin context.
- `SurfaceAppearance.Color` is the tint for Wallpaper, otherwise white. `part.Color` is set to white.

## 5. Studio install (generated `install.luau`, import_assets.py:47-130)

**Guards**
- `assert(game.PlaceId == 131311258779917)`.
- Every chunk must have an `assetId` and every map a `robloxMaps` entry (:52-55).
- Refuses if `ServerStorage.<kit>` already exists: "no overwrite" (:56).

**Build**
- A `Folder <kit>` is created with attributes `Build`, `ManifestSha256`, `Complete=false`, `Ready=false`. It is assembled off-tree and parented to ServerStorage only after `Complete=true, Ready=true` (:57-62, :128). If anything fails, `pcall` → `kit:Destroy()` (:127).
- `Components/<Name>`: a Model with `BlenderComponent` and `SourceBuild` attributes.
  - One MeshPart per chunk via `AS:CreateMeshPartAsync(Content.fromUri("rbxassetid://id"), {CollisionFidelity=Box, RenderFidelity=Automatic})`, named after its material.
  - Anchored, `CanCollide/CanTouch/CanQuery=false`, `CastShadow=true`, `Size=c.size`, `CFrame=CFrame.new(c.center)`, `Material=Enum.Material[robloxMaterial]`.
  - Attributes `BlenderChunk`, `BlenderSourceSha256`, `BlenderAssetId`, `BlenderMaterial` (:69-91).
- `Colliders` folder: invisible `Part "Collider"` with `CollisionGroup="Decor"` and `RoomRole="Collider"`. It is added for every component **except** Floor, Ceiling and WallHalf, which keep native maze collision (:93-102).
- Aliases are cloned components (:105-107).
- `Rooms/<RoomName>`: a Model with attributes `OpenMask`, `Variant`, `CellSize`, `SourceBuild`, `SelectionWeight`, `ShortWall`, `ShortWallHeight`. Inside are role Folders (`SurfaceFloor` …), each holding a component clone pivoted to `cf`, with `RoomRole` on every MeshPart (:108-125).
- Manifest `markers` are **not** installed.

**Kits in the place**
- V1 `ServerStorage.Level1BlenderKit` (39 component models, 34 rooms; `artifacts/level1-facelift-20261002/publication.json`) and V2 `ServerStorage.Level1BlenderKitV2` both exist.
- V2 was installed with `--kit-name Level1BlenderKitV2`; only those two names are allowed (:193). The renderer uses V2 (`BlenderRoomRenderer:5`).
- MeshParts are created once in Edit and saved with the place. At runtime they are only cloned.

**Installing the scripts** (`install_sources.py`)
- For each changed script it compares the live Studio Source and editor buffer with a recorded baseline (djb2 hash, :34-43). New scripts are created via MCP `multi_edit` with `className` (:118-120).
- Existing scripts are written with `UpdateSourceAsync`, which re-checks inside the write callback (:123-131). The manifest item is then written (:149-158).

## 6. Runtime renderer (`ServerScriptService/Level 1 Systems/BlenderRoomRenderer.ModuleScript.lua`)

**Readiness and room choice**
- `IsReady()` (:11-37) requires: kit `Ready==true`; `Components` and `Rooms` present; every `PROP_NAMES`, `SURFACE_NAMES` and `HARDWARE_NAMES` (:6-9) entry is a Model containing a MeshPart; room models cover masks 1..15.
- `Begin(maze)` (:135) returns nil unless `workspace.Level1BlenderPreviewActive == true`, asserts readiness, and indexes `roomsByMask` (:141-150).
- `PickRoom` uses `SelectionWeight`, clamped 0-100. Fallback weight is Variant 1 → 1, otherwise 16 (:39-55). It is called with unseeded `math.random()` (:189), so the room art does not follow a pinned seed.
- `OpenMask` (:126-133) is computed from MazeGenerator's `wallV/wallH`, so the kit follows the generated topology. The generator's topology code is unchanged; `test_level1_blender_preview.py` asserts the block is byte-identical to the pre-facelift version.

**Skinning the cells** (`state:Rooms`, :179-245)
- One clone per cell, placed in `Maze.BlenderRooms`.
- Position and size are scaled by `cell/24` in **X and Z only**, which stretches the physical UVs if `L1_Cell ≠ 24`.
- Collision: only `RoomRole=="Collider"` parts collide (`CollisionGroup "Decor"`, which the entity passes through per MazeGenerator:36-37). Everything else has `CanCollide/CanQuery/CanTouch=false`.
- Hidden by `Transparency=1`: all `Fixture` art; pit cells except `SurfaceCeiling` and `ShellWalls`; the elevator cell except `SurfaceCeiling` (:208-212).
- Recessed ceiling: in fixture cells the `Ceiling` slab is replaced by 4 pieces with a hole the size of one tile (`CeilingPieces`, :72-80, :215-233).
- Rooms are named `Room_%02d_%02d` with attributes `OpenMask`, `CellX`, `CellZ`, `PitCell`, `ElevatorCell`.
- It yields `task.wait()` every 2 columns. At the end it sets `workspace.Level1BlenderRoomCount = grid²` (:241-244).

**What happens to the native parts**
- `state:Hide(part)` sets the part and its Texture/Decal children to transparency 1 (:168-173). The part stays parented, collidable and queryable.
- `state:Skin(part, comp, dynamic, tint)` (:287-361):
  - Clones a kit component and fits it to the proxy's size (`SkinLayout`, :57-69).
  - Dynamic parts get unanchored, Massless MeshParts with a `WeldConstraint`. Colour and Material follow the proxy (`GetPropertyChangedSignal`).
  - The proxy keeps its prompts and collision ("never contributes a second collider").
- `SkinGroup` (:248-284) replaces a set of casing parts with one mesh fitted to their combined bounds.
- `Fixture` (:362-371) **moves and resizes the native light panel** into one 4-stud tile.
- `Watch` / `WatchPuzzle` (:478-522) skin `workspace.PuzzleItems` through `DescendantAdded`.
- `ExitAperture` (:372-477) cuts a 7-wide opening in the outer boundary wall. It clones the native wall into side and header collision pieces, sets `Level1ExitQueryWall`, adds an 8/24-scale vestibule with its own colliders, and sets `ExitApertureReady/Frame`.

**Cleanup**
- `Cleanup` runs on `maze.Destroying` (:156-167). `BlenderRooms` lives under `Maze`, so GameManager's `cleanupLevelOneWorld` destroy loop removes it.

## 7. MazeGenerator call sites

| Line | What it does |
|---|---|
| 465-468 | `blender = require(BlenderRoomRenderer).Begin(maze)` only when the attribute is true |
| 584-586 | `wallPart`: maze walls are hidden; elevator-shell walls (`parent` set) are skinned with `WallHalf` |
| 593-595 | Full-cell floor tiles hidden; other sizes skinned with `FloorPanel` |
| 739 | Pit walkways hidden |
| 791 | Pit depth bands skinned with `WallHalf`, tinted |
| 873 | The single ceiling slab is hidden |
| 964-974 | Elevator watched: Neon → `LightFixture` (dynamic), else `MetalPanel`; door SurfaceGuis disabled |
| 1077 | Elevator lamp brightness 1.65 in preview (else 1) |
| 1292 | Fixture brightness .85 in preview (else .7) |
| 1339-1342 | `blender:Fixture(panel, "GridFixture"/"Fluorescent")` |
| 1527-1532 | `DECOR_BUILDERS[name]` replaced by `blender:Prop(name)`; `prep()` still sets the `Decor` group and `CanQuery=false` (1539-1545) |
| 1883 | `blender:Rooms(wallV, wallH, GRID, CELL, O, pitCellSet, ELEV_X, ELEV_Y)`, called just before `maze.Parent = workspace` |
| 1931-1941 | Grading `Saturation .08` / `Brightness .01`, restored on `maze.Destroying` |

PuzzleManager also has preview branches:
- `SkinCarriedFuse` at 540-541.
- Exit sign `CanCollide`, `"EXIT LOCKED"` text and `MakeExitAperture` at 1203-1224.
- Preview cable routing around every colliding maze/decor box (`previewWireObstacles`, 191-212) at 1776-1778 and 2130-2144.

## 8. The developer preview button, end to end

**1. Lobby host** (`ServerScriptService/Level1BlenderPreviewAccess.Script.lua`)
- Exits on reserved round servers (`PrivateServerId~="" and PrivateServerOwnerId==0`, :15).
- Creates or reuses `ReplicatedStorage.Level1BlenderPreviewRequest` (RemoteEvent, :16-22).
- `activeRoom` (:24-38) accepts exactly one of:
  - `Workspace.ServerLobby.LevelQueueRooms.Level1QueueRoom` with `LevelNumber==1`
  - `Workspace.LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level1`, where the preview model has `LobbyReimaginedOwned==true`, `R3QueueRevision==3`, `Ready==true`
- `ensureHost` (:40-63) needs a colliding `ChamberFloor`. It creates `Part "Level1BlenderPreviewEntry"`:
  - 1×1×1, `CFrame = floor.Position + (-20, 4.42, 0)` (world axes)
  - Anchored, `Transparency 1`, no collide/touch/query, `CastShadow false`
  - attribute `Level1BlenderPreviewHost=true`, parented to the room
  - ownership tracked in the strong table `hosts`, because weak keys lost it (:9-11)
- Re-hooks through `workspace.DescendantAdded` when an instance with one of these names appears: `ServerLobby`, `LevelQueueRooms`, `Level1QueueRoom`, `PreviewQueuePads`, `QueueBay_Level1`, `ChamberFloor`, `LobbyReimaginedPreview`. Also re-hooks on the preview's `Ready` change (:116-133).

**2. Client prompt** (`StarterPlayer/StarterPlayerScripts/Level1BlenderPreviewButton.LocalScript.lua`)
- Returns early unless `DevAccess.IsAllowed(LocalPlayer)` (:5-8). Non-developers get no UI.
- Builds a client-local `ProximityPrompt "Level1DeveloperPreviewPrompt"`:
  - ActionText `"ENTER LEVEL 1 FACELIFT PREVIEW"`, ObjectText `"DEVELOPER PREVIEW"`
  - `HoldDuration .5`, `MaxActivationDistance 10`, `RequiresLineOfSight false` (:22-34)
- Enabled only when not `InRound`, not `Level6InRound`, and not `ReservedRoundServer` (:15-20).
- 2 s debounce, then `FireServer(host)` (:44-48). Rejections show `ROUND BUSY · TRY AGAIN` or `PREVIEW ASSETS NOT READY` for 3 s (:56-65).

**3. Server gate** (`readyPlayer`, access script :74-93)
- Player must be a developer (`DevAccess.IsAllowed`, which allows only UserIds 40920547 and 9488575949 — `ReplicatedStorage/DevAccess.ModuleScript.lua:5-8`) and must not be `InRound` or `Level6InRound`.
- The host must still be owned, invisible and non-colliding inside the active room, and the floor must be unchanged.
- The character must be alive, unseated, not anchored, and within `RANGE=12` studs.
- The player's cooldown is set to `math.huge` before invoking (:101). The script re-checks, then invokes `ServerStorage.Level1BlenderPreviewLaunch` (a BindableFunction), sets a 2 s cooldown, and replies with `FireClient(accepted, reason)` (:95-113).

**4. GameManager launch** (`ServerScriptService/GameManager.Script.lua`)
- The BindableFunction is created at 3359-3365 with `OnInvoke = launchBlenderPreview`.
- `canLaunchBlenderPreview` (3304-3313) checks DevAccess, not a reserved server, `roundBusy`, an open `activeEntry`, `developerPreviewLaunching`, `InRound`, alive. `blenderPreviewReady()` (3297-3303) requires `Level 1 Systems.BlenderRoomRenderer` with `.IsReady()`.
- **Studio** (3319-3344): local round. Sets `Level1BlenderPreviewActive=true`, then `fireGroup "loadinggame"`, `beginGroupLoading`, `prepareGroupLoading(attempt,{player},1,false)`, `playRound`. Recovers via `returnGroupToLobby` on error. Sets the attribute back to false afterwards.
- **Published** (3345-3357): `TeleportAsync(game.PlaceId, {player}, options)` with `ShouldReserveServer=true`. The packet is `Routing.ArrivalPacket({Ceiling=Routing.MaxLevel, Level=1, SessionId=JobId..":level1blender:"..UserId..":"..os.clock(), Expected=1, Final=true, GlowstickSlots={[UserId]=1}})` plus `packet.Level1BlenderPreview = true`. `ArrivalPacket` is defined at `Round Completion Routing.ModuleScript.lua:464-486`.
- **Solo only**: participants is always `{player}`.

**5. Reserved server** (GameManager 3939-3955)
- After `stageArrivingParty` admits the group, it looks for an arrival entry with `RoundSessionId==group.SessionId and Level1BlenderPreview==true`.
- It then requires `selectedLevel == 1 and blenderPreviewReady()` and that **every** participant passes DevAccess. Otherwise `attempt:Fail("LEVEL_ACCESS_DENIED")`.
- Only then does it set `workspace.Level1BlenderPreviewActive=true`, so a spoofed TeleportData flag cannot open the preview.

**6. No progression**
- 2449: `nextLevel = nil` while the preview flag is set, so there is no Continue.
- 3086: `zyntraLevelCompleted:Fire` is skipped (tokens, LevelsCleared, badges, records, FriendBoost).
- `Analytics.Outcome` still fires (3083). `Analytics.Launch` does not (it is only called on the station path, 3288).

**7. Reset**
- `cleanupLevelOneWorld` sets `Level1BlenderPreviewActive=false` and `Level1BlenderRoomCount=nil` (1683-1684) and destroys `Maze` and the other generated folders (1686-1695).
- The game boots with the flag false (120).

## 9. What the Level 2 queue room needs

**Names and sites to duplicate or parameterise**
- New names: `Level2BlenderPreviewEntry`, `Level2BlenderPreviewHost`, `ReplicatedStorage.Level2BlenderPreviewRequest`, `ServerStorage.Level2BlenderPreviewLaunch`, `workspace.Level2BlenderPreviewActive`, `packet.Level2BlenderPreview`, and the prompt name and text.
- `activeRoom` targets: `ServerLobby.LevelQueueRooms.Level2QueueRoom` with `LevelNumber==2` (the name comes from `TunnelLobbyBuilder.ModuleScript.lua:2111`, the attribute from :2284), and `LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level2` (`LobbyReimaginedPreview/Builder.ModuleScript.lua:121-124`; `ChamberFloor` is the renamed `"Bay Floor"` collider, :134).
- The `observe()` name list must include `Level2QueueRoom` and `QueueBay_Level2`.

**Host position: the Level 1 offset does not transfer**
- In the old lobby, Level 1 has `side=-1` and Level 2 has `side=1`, both at z=-80 (TunnelLobbyBuilder:2936-2937).
- Room radius is 28 (`20*1.4`, :2114-2115). `roomCenter = center + side*(35+28)` (:2118). `ChamberFloor` is a cylinder at `roomCenter + (0,-0.42,0)` (:2121-2129), so the host ends up at `roomCenter + (-20, 4, 0)`.
- For Level 1, −X points away from the tunnel, toward the far wall. For Level 2 (`side=+1`), −X points **toward the doorway**: the vestibule is at `roomCenter.x - 25` (:2206-2224), so the host would sit 5 studs inside the entrance.
- The mirrored far-wall spot (+20) is occupied by Level 2 bay decor (`styleLevelTwoBay`, :1528-1668). Positions are along `outward=(side,0,0)`:

  | Decor | Position | Size / note |
  |---|---|---|
  | `Lobby L2 Tiled Column` | +20.5 | 3.6×9.2×3.6, solid; flares 5.2 wide (:1619-1633) |
  | Basin | +19.2 | 12.8-stud apron (:1588-1615) |
  | Ladder rails | +14.75, z ±1.35 | solid (:1636-1646) |
  | Lounger | (+19, z+9) | :1649-1655 |
  | Ball | (+19.2, z+3.05) | :1656-1659 |

- Queue pads are at `(±9, ±13.2)` (:2242-2247).
- The offset therefore needs to be per level, ideally expressed relative to `outward`/`side` rather than world −X. It must stay within the prompt's 10 studs and the server's 12-stud `RANGE`.
- The reimagined bay's geometry comes from a Studio-only manifest (`ServerStorage.LobbyReimaginedBlenderSource20261001R4`, `RuntimeBake.ModuleScript.lua:8,38-52`). Its Level 2 bay layout is **not in the repo**, so the `-20` X spot has to be measured in Studio.

**GameManager sites hard-wired to Level 1**
- Readiness check through `Level 1 Systems.BlenderRoomRenderer` (3297-3303).
- `Level = 1` in the packet (3348) and in the Studio path `prepareGroupLoading(…, 1, …)` (3329).
- `selectedLevel == 1` (3945).
- Only `Level1BlenderPreviewActive` is checked at 2449 and 3086.
- The flag is reset only in `cleanupLevelOneWorld` (1683). Level 2 cleans up through `LEVEL_GENERATORS[2]="Level2Generator"` → `.Cleanup()` (139-143, 1738-1743), so a Level 2 flag needs resetting there.
- Level 2 wins keep the round lifecycle alive through the result window for the tube continuation (3076). With the preview's `nextLevel=nil`, that path should be checked.

**Tests to copy**
- `tools/tests/test_level1_blender_preview_access.py`: real gate, host lifecycle and client prompt run in Luau with fake services.
- `tools/tests/test_level1_blender_preview.py`: launch gate, sockets, readiness, topology unchanged. It reads **`drafts/level1-facelift-20261002/*`** by default, which is stale relative to the mirror; point the Level 2 copy at the mirror.

## 10. Lessons and bugs recorded

**Instance cost and memory**
- The skin roughly doubles what is built: about 12 MeshParts per cell × 1,600 cells (§0).
- Studio memory went from 4,769 MB (V1 preview) to 6,168–6,771 MB (V2 preview). These are Studio figures, not server ones (runtime JSONs).
- Bounded desktop frame sample: median 16.735 ms, p95 18.376 ms over 90 frames (`level1-light-polish-20261002/qa-summary.md`).

**Never verified**
- Multiplayer, mobile/GPU, server CPU, and the published reserved-server transfer end to end (`level1-facelift-20261002/publication.json` `unverified`; `current-qa-summary.md`).

**Entity teardown**
- Repeated preview resets left 40 runtime Animation children (8 per round) under EntityAnimation. GameManager parked the entity and disabled the controller before the deferred teardown callbacks ran.
- Fix: invoke the controller's `ReleaseAnimations` BindableFunction synchronously first (`coordination.md`; GameManager:707).

**Parallel sessions**
- Level 4's `pull_source_from_studio.py` copied Level 1's half-finished Studio edits into the working copy.
- The note "Do not publish this intermediate place state" was needed. Publish only with **Migrate To Latest Update** (`coordination.md`).

**Studio writes and transport**
- After `UpdateSourceAsync`, the editor commit can land before the replicated Source: verify, never re-write (install_sources.py:133-134).
- `execute_luau` has a text-size cap, so the image read-back was done in 16-row strips (export_fixture_reference.py:39). The MCP sandbox has no HTTP, so meshes were inlined into the code rather than loopback-served.
- Level 1 import depends on text markers inside Level 4's `upload.luau` (import_assets.py:143). If either marker is renamed, the Level 1 import breaks.

**Blender quirks**
- Blender 5.2's FBX exporter warns on linked duplicate material slots even though re-import is valid (build.py:558).
- Blender saves Windows separators after `//` (verify_native.py:20).
- Catalogue instances take the unsuffixed object names, so FBX re-import names get `.001`-style suffixes (verify_native.py:46).

**Light polish pass**
- Caught a build-order bug and unsupported `Color3` arithmetic before QA.
- A cable-light experiment was replaced by native Neon emission at no extra light cost.
- CharacterNavigation found no lobby route to the entry, so QA placed the actor by script (`qa-summary.md`).

**Readability pass** (`level1-readability-20261002/README.md`)
- Still too dark: the client (RoundUI) reapplies the dark baseline, so a server-only ambient change is overridden.
- The renderer multiplies elevator PBR by proxy colours (shell 197/180/116, frame 14/14/17, doors 70/75/80). `MetalPanel` is a shared alias, so an elevator-only fix must not change puzzle props or cables.

**Original assets preserved**
- The original wallpaper pixels and the 5-bank / 5×5 grille fixture were kept on purpose (prompts.json, `derivation.json`).

**Unseeded art**
- `PickRoom` uses `math.random()` (:189). For Level 2's pinned seeds (`Level2Seed`), variant choice should come from the round's seeded RNG.

## 11. What changes for Level 2 (inference, not recorded anywhere)

- **Keep:** the bmesh kit, the chunk binary format, the Level 4 `build()` uploader with wireSha256 reuse, `publish_textures`, the off-tree `Ready` install, and the preview button/packet plumbing.
- **Instance count:** for "far fewer instances", the Level 2 generator must not build its native visual parts. Keep a merged, invisible collision set instead of hiding thousands of parts. Flatten room clones: no role Folder → component Model nesting, which costs about 3 instances per placement.
- **Slopes and hills:** the Level 1 contract is flat (`floorTop 0`, Y never scaled, `CollisionFidelity.Box` everywhere). Height variation needs height-aware sockets and real slope colliders.
- **Different shape of maze:** sockets are a 4-bit mask on a 24-stud grid. Level 2 is rooms joined by tunnels, so the socket contract has to be redesigned, not copied.