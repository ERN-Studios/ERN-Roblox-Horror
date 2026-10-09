# Level 2 Blender kit: the reusable asset pipeline (Blender, imagegen, Meshy, PBR, Roblox upload)

Repo paths are relative to `G:\Roblox\MongoTV\`. Other paths are absolute. I only read files: nothing was edited, there was no git write, and Studio was not touched. The working tree was dirty at session start (`tools/level4_blender/{ceilings,props_decay,props_lobby,props_rooms,round_assets,usher_nav}.py`, `results.jsonl` modified), so line numbers refer to the working copy.

## 0. Bottom line
- **Two Blender-to-Roblox pipelines exist:**
  - **Level 4 cinema (`tools/level4_blender/`):** a single static model placed once into Workspace, driven by a dump of the old Studio layout.
  - **Level 1 modular kit (`tools/level1_blender/` + `BlenderRoomRenderer`):** Blender components plus room variants keyed by socket masks. It is installed into `ServerStorage` and cloned per maze cell at round start.
- **Level 2 ("random labyrinth at round start") matches the Level 1 shape.** Level 4 supplies the reusable sub-tools: `make_pbr`, `import_meshy`, the chunk binary format, the EditableMesh uploader, SurfaceAppearance styling, the occluder rule and the cull.
- **Level 1 already reuses Level 4 code:**
  - `tools/level1_blender/import_assets.py:142-143` slices `build()` out of `tools/level4_blender/upload.luau`.
  - `tools/level1_blender/prepare_v2_textures.py:10-13` imports `tools/level4_blender/make_pbr.py`.

## 1. Toolchain (checked 2026-10-03)
| Tool | Version / path | How it is driven |
|---|---|---|
| Blender | **5.2.0 LTS**, `D:\Blender\blender.exe`, build 2026-07-14 (`--version`) | headless `-b ... --python-exit-code 1 -P script -- args` |
| Slot runner | `G:\Roblox\_local\l4facelift\v3\blrun.py` | at most 4 concurrent Blender processes (`L4_BLENDER_SLOTS`, ~2 GB each); lock files in `v3\locks` |
| Codex CLI | **codex-cli 0.160.0**, `C:\Users\mikke\AppData\Local\Programs\OpenAI\Codex\bin\codex` (only `--version` was run) | `codex exec` with the built-in `image_gen` tool |
| Meshy | Claude-side MCP `mcp__meshy__*` | No API script exists in the repo |
| Studio MCP | `tools/sync_from_studio.py` `StudioMcpClient` / `find_mcp_batch` / `select_studio` | Raw `tools/call` for `execute_luau`, `upload_image`, `list_roblox_studios` |
| Python | numpy + PIL (make_pbr); scipy + embreex for the cull | pylib at `G:/Roblox/_local/l4facelift/v3/P7/pylib` (`v3\final2\run.sh`) |
| Blender GUI MCP | `localhost:9876` | This is the owner's open Blender. Do not use it (`artifacts/level4-facelift-v3-20261002/BRIEF.md:16`). |

## 2. Steps and exact commands

### 2.1 Image generation (moodboards, tileable texture sources, Meshy reference images)
- **How it runs.** `codex exec` with Codex's built-in image tool. Every prompt contains: "Use your built-in image generation tool. Save every image as PNG in the current working directory with EXACTLY the given file name … Do NOT run git, do NOT commit" (`artifacts/level4-facelift-20260930/textures/prompt.txt:3`).
- **Package launcher** (`G:\Roblox\_local\l4facelift\v3\launch_codex.sh:5`):
  `codex exec -m gpt-6.1-sol -c 'model_reasoning_effort="ultra"' --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox -C "G:/Roblox/MongoTV" "$(cat $D/codex_prompt.txt)" > $D/codex.log 2>&1`
- **Image jobs** run with the working directory set to the output folder and the prompt on stdin (`codex.log:1` "Reading prompt from stdin…").
- **Recorded runs:**
  - 2026-09-30: Codex v0.157.0, `gpt-6-sol`, `approval: never`, `sandbox: danger-full-access`, reasoning `ultra` (`artifacts/level4-facelift-20260930/{moodboard,props,synth,textures}/codex.log:2-10`).
  - The same day `gpt-6.1-sol` failed: "The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account" (`moodboard/codex_failed_gpt61.log`, tail).
  - 2026-10-01: v0.159.3, `gpt-6.1-sol`, reasoning `high` (`G:\Roblox\_local\l4facelift\v3\gen\codex.log:2-9`).
  - Memory note `codex-cli-model-and-usage`: 6.1 was accepted again on 2026-10-02; fall back to `-m gpt-6-sol`. Files land in `~/.codex/generated_images/` and are then copied.
- **Prompt records (Level 4):** one `prompt.txt` per folder.
  - `moodboard/`: 6 directions A–F × hero/carpet/wall.
  - `props/`: 18 Meshy reference images. Rules: one whole object, centred, three-quarter view from slightly above, light-grey seamless background, soft even light, clean silhouette (`props/prompt.txt:1-3`).
  - `textures/`: 26 tileable maps, each with its real-world size in brackets (`textures/prompt.txt:5`).
  - `synth/`: 4.
  - `v3\gen\prompt.txt`: 3 textures + 6 Meshy references.
- **Prompt records (Level 1):** structured JSON registries.
  - `assets/level1/blender/concepts/prompts.json` (`"generator": "built-in image_gen"`).
  - `assets/level1/blender-v2/concept/prompts.json` (`"tool": "image_gen.imagegen (built-in)"`, with a `reference` field for image-conditioned edits).
  - `artifacts/level1-readability-20261002/concepts/{prompts,manifest}.json` (sha256 per output).
- **Sizes and storage:**
  - Generated PNGs are 1254×1254. Roblox stores the uploaded copies at **1024×1024** (`assets/level4/materials/README.md`).
  - The repo keeps JPEG copies. The PNG originals live outside the repo (`tools/level4_blender/make_textures.py:20`; `G:\Roblox\_local\l4facelift\png_originals`).

### 2.2 PBR maps from the generated albedo
- **Current command:** `python tools/level4_blender/make_pbr_all.py [names…]`. It reads `pbr_spec.json` (32 sets) and writes `G:\Blender\Level4_Cinema\textures\pbr\<name>_{albedo,height,normal,rough[,ao]}.png`. When the spec has `metal`, it also writes a constant 64×64 `_metal.png` (`make_pbr_all.py:1-27`).
- **`make_pbr.py`:**
  - Uses only numpy and PIL. Every filter wraps around (FFT/roll), so a seamless input stays seamless (`make_pbr.py:1-13`).
  - Defaults: size 1024, strength 8, `rough_base` .75, `rough_var` .15, `highpass` 64, OpenGL normals (+Y green, as Roblox and Blender expect) (`:18-19`). `--delight` and `--ao` are optional.
  - Self-test: `python make_pbr.py --selftest`.
  - Example spec values: carpets strength 2.5 / rough .95 / blur 1.5; metals `"metal": 1.0` (`pbr_spec.json:3-34`).
- **v1 tool (superseded):** `make_textures.py` produced a 1024 colour map plus a tint-able `_n` map (`make_textures.py:1-3,30`).
- **Level 1 reuse:** keeps the original Studio wallpaper albedo pixels (asset 87947439437597), derives only normal and roughness from them, and generates deterministic procedural prop-grain maps (`prepare_v2_textures.py:36-67`).
- **Measured on disk:**
  - PBR folder: 162 maps at 1024², 4 at 64².
  - Meshy maps: 44 at 1024², 16 at 512² (litter).

### 2.3 Meshy (image to 3D)
- **How it was driven:** Meshy MCP calls from Claude session `C:\Users\mikke\.claude\projects\G--Roblox-MongoTV\2af1996b-3a1e-498a-8e69-804e4ad00a0c.jsonl`. Task ids are in `G:\Roblox\_local\l4meshy\tasks.json`.
- **Batch 1 (2026-09-30 17:17):** 9 × `meshy_image_to_3d` with:
  `{ai_model:"meshy-7", model_type:"standard", should_remesh:true, topology:"triangle", target_polycount:2500–8000, should_texture:true, enable_pbr:true, texture_resolution:"2k", target_formats:["glb"], texture_prompt:<ref text>}`
  Then `meshy_get_task_status`, then `meshy_download_model {format:"glb", save_to:"G:/Roblox/_local/l4meshy/<Asset>/<Asset>.glb"}`.
- **Batch 2 (2026-10-01 16:29):** 6 × `{ai_model:"meshy-6", should_texture, enable_pbr, remove_lighting:true, should_remesh, target_polycount:8000 (lockers)/5000 (litter), target_formats:["glb"]}`, polled with `wait:true, timeout_seconds:300`.
- **2026-10-02 06:22:** `meshy_multi_image_to_3d` for the Usher (front/side/back, meshy-6, `pose_mode:"a-pose"`, 16000 polycount, glb+fbx), plus `meshy_rig`, plus a film canister at 5000.
- **Credits:**
  - Measured: balance **1940** (10-01 16:08) → **1695** (10-02 19:25), a drop of 245 = 6×30 + 30 (multi-image) + 30 (canister) + 5 (rig). This matches the MCP price table exactly.
  - Not measured: batch 1 (9 textured meshy-7 jobs at 30 credits each = 270 by the price table) ran before any balance read.
- **Raw GLB size:** 8.4–17.2 MB each (2k textures embedded).
- **Blender import:**
  - Spec file: `tools/level4_blender/meshy_specs.json:2-17`. Fields: `asset`, `glb`, `dims` (metres, `null` = free axis), `tris`, `sem`, `col_slices`, `col_axis`, `tex_size`, `collide`, `sharp_angle`.
  - Run: `exec(open(import_meshy.py).read(), {"SPEC": spec})`, or through `build_all.meshy()` (`build_all.py:49-54`).
  - What `import_meshy.py` does:
    1. glTF import with `merge_vertices` (`:282`).
    2. Moves the model into a canonical frame: yaw auto-squared, scaled to `dims`, origin at bottom centre, front −Y (`:75-86`).
    3. Decimates in up to 3 passes, ratio `tris/n*.98`, then re-shades with `sharp_angle` (`:304-322`).
    4. Requires exactly **one** textured material; otherwise it stops with "bake to one atlas first" (`:327`).
    5. Resamples the atlas to `tex_size` and splits glTF metallicRoughness into separate rough and metal maps (`:324-345`).
    6. Builds collision as `col_slices` slab AABBs from triangles (`:89-103,349`).
    7. Writes mesh `L4A_<asset>` with `l4_col` JSON and a fake user (`:356-364`). The material is tagged `l4_uv="mesh"` so the exporter keeps Meshy's UVs.
  - Pure-maths self-test: `python import_meshy.py`.
  - QA renders: `G:\Roblox\_local\l4meshy\run_import.py` renders each asset with EEVEE at 640² into `l4meshy\preview\`.

### 2.4 Blender authoring
- **Level 4:**
  - Command: `blender -b G:/Blender/Level4_Cinema/Level4_Cinema.blend -P build_all.py -- <out.blend>` (`README.md:62`).
  - `build_all.py` runs each step in `slots.py`'s namespace, honours `L4_BUILD_KEEP_GOING` / `L4_BUILD_SKIP`, and refuses to overwrite the master blend (`build_all.py:1-20,82-86`).
  - Export conventions are documented in `slots.py:1-24`: `l4_prop`, `l4_collide="bounds"`, `l4_col`, `l4_seat`, `l4_tags`, `l4_marker` + `l4_attributes`, `l4_collision_only`, `l4_model_group/parent/tags/attributes`, `l4_part_name`, `l4_pivot`, `l4_zone`, `l4_occluder`.
  - The slot table (stem, tile metres, rgb, rough, metal, Roblox material, sem) starts at `slots.py:27`.
- **Level 1 kit:**
  - Command: `& D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build.py` (`tools/level1_blender/README.md:12`). It asserts it is running in background mode (`build.py:20`).
  - Components are procedural bmesh, built by a `Mesh` class (box / cylinder / sphere / collider). UVs are box-projected with a physical scale per material (`tileStuds`). Scale is 0.28 m per stud (`build.py:15,64-135`).
  - Rooms use socket masks N(+Z)=1, E(+X)=2, S(−Z)=4, W(−X)=8, a 24-stud cell, 14-stud walls, and half-walls 11.5 studs from centre (`build.py:344-367`; `README.md:23-30`).
  - Outputs: `export/manifest.json` (components, rooms, aliases, materials, chunks with `sha256`/`wireSha256`), an FBX with one copy of each component, Cycles review renders, and `native-files.json` hashes (`build.py:401-446,449-570`).
  - V2 imports `build.py` as a module and replaces components (`build_v2.py:1-15,54-58`). V2 totals: 41 components, 42 rooms, 93 chunks, 22,768 tris.
  - Checks: `python tools/level1_blender/check_assets.py --assets …` and `verify_native.py`.

### 2.5 `cull_hidden.py`: what it does
- **Command** (`cull_hidden.py:3-5`; full form in `v3\final2\run.sh`):
  `python blrun.py in.blend cull_hidden.py out.blend --report r.json --work-dir w --layout layout.json --build-dir build_src --python-path <pylib> --views proof_views.json [--visibility-views …] [--keep keep.json]`
- **Blender side:** gathers triangles, colliders and lights using `export_l4`'s own functions (`:108-117,204-347`), then starts a plain-Python worker (embreex + scipy) (`:533-540`).
- **Worker:**
  1. Voxelises colliders at 1 stud (`:975-1015`).
  2. Marks standable cells: 2×2 footprint, 5 cells of headroom, a floor no more than 1.5 studs below (`:700-720`).
  3. Flood-fills from hard-coded seeds `[[23075,26,110],[23000,27,226]]` (`:341`).
  4. Builds the camera region as standable cells dilated 14 studs (Chebyshev) and masked by occluders (`:1018-1024`).
  5. Enforces at least 3000 sample points and 2048 directions (`:509-510`).
  6. Fires random Embree rays to mark which triangles are seen (`:1185-1214`).
  7. For every unhit polygon, runs exact sightlines from all samples within 40 studs plus the 64 nearest, to the polygon centre and to vertices inset 2%. Any clear or uncertain ray keeps the polygon (`:1285-1347`).
- **Always kept:** doors, gameplay, tagged objects, seats, glass/decals/alpha, and partly visible props (`:243-260,1217-1226`). Any uncertain ray anywhere means nothing is removed (`:1497-1502`).
- **Applying the cut:**
  - Deletes whole faces while preserving custom normals (`:360-394`).
  - Nominates unreachable colliders and lights (`:929-971`).
  - Will not save if colliders, inputs or the tool itself changed during the run (`:543-557`).
- **Proof:** a separate step, using `proof_hidden.py`, `proof_summary.py` and `audit_informative.py` in `G:\Roblox\_local\l4facelift\v3\P7b\proof_tools\`.
- **Measured results:**
  - v3: placed tris 2,249,959 → 2,186,104 (−2.84%); unique export tris 982,835 → 921,332 (−6.26%); objects 4,596 → 4,580; estimated instances 14,190 → 13,924 (−1.87%); 430 render pairs, maximum changed pixels 0.0994% (limit 0.1%) (`artifacts/level4-facelift-v3-20261002/P7b_SAVINGS.txt:3-14`).
  - final4: 964,681 → 939,337 native tris; 926 paired cameras (`G:\Roblox\_local\l4facelift\v5\final4\DONE.txt`).
- **Assessment:** tied to Level 4 (`w_rb` hard-codes the 23000 offset at `:599-603`; the 0.28 scale; the "L4 Cinema" collection; master path `:506`; qa_views path `:328`). It also saves little. It cannot cull a level that is assembled at random per round.

### 2.6 Export
- **Command:** `blender -b <out.blend> -P export_l4.py`. Output goes to `L4_EXPORT_OUT`, default `G:\Roblox\_local\l4blender\export` (`export_l4.py:1-4,61`).
- **Wire format** (shared with Level 1, `build.py:424-425`): base64 of a little-endian blob:
  - u32 `[nv, nn, nu, nf]`
  - f32 positions (studs, centred on the chunk)
  - f32 normals
  - f32 UVs
  - 9 × u32 per face (v, n, uv for each of 3 corners)
  - Source: `export_l4.py:568-577`.
- **Limits:** at most **20,000 tris, 60,000 verts, 1800 studs on any axis** per chunk (MeshPart limit is 2048). Larger sets are split recursively at the median of the longest axis (`export_l4.py:57,67,340-349`).
- **Axes and scale:** Blender (x,y,z) → Roblox (x,z,−y); 1/0.28 studs per metre (`:65-69`).
- **UVs:** `l4_uv="mesh"` keeps the mesh UVs (u, 1−v). Everything else is box-projected in metres divided by `l4_tile` (`:274-285,328-332`).
- **Pooling:** plain meshes are pooled per (material, visual tags, zone) into World chunks (`:593-625,680-681`). `l4_prop` / `l4_door_leaf` objects become one chunk set per asset plus one placement record per object (`:606-678`).
- **Colliders:**
  - Layout parts minus parts that new geometry covers ≥30% (`prune_replaced`, `:212-246`).
  - Scene `l4_col` / `l4_collide` / `l4_occluder` (`:376-418`).
  - Markers (`:156-167`).
  - Per-prop colliders, then `make_place.optimise_prop_colliders` (`:727-729`).
- **Lights:** taken from the "L4 Fixture Lights" collection (`:426-466`).
- **Materials:** `ROBLOX_MAT` maps sem → Roblox Material (`:74-78`).

### 2.7 Texture upload
- **Level 4 path:**
  1. `python make_place.py --tex-requests [export]` copies every missing map to `G:\Roblox\_local\l4blender\tex` and writes `tex_requests.json` in batches of 20 URLs under `http://127.0.0.1:8766/tex/` (`make_place.py:4-9,25-28,292-311`).
  2. Serve with `python -m http.server 8766 -d G:\Roblox\_local\l4blender`.
  3. Call Studio MCP `upload_image {imagePaths:[…]}`.
  4. `python make_place.py --tex-merge answers.json` writes the ids into `textures.json` (209 entries) (`:314-321,400-405`).
- **Level 1 path (better, automated):** `python tools/level1_blender/publish_textures.py --assets assets/level1/blender-v2`.
  - Starts a loopback server on a temporary port.
  - Calls `select_studio("BACKROOMS: STAY QUIET [CO-OP HORROR]")`, then `upload_image`.
  - Keeps sha256 receipts in `textures/published.json` and only uploads files whose hash changed (`publish_textures.py:22-56`). 20 maps were published this way.
- `upload_image` is its own MCP tool, so it is not affected by `execute_luau`'s missing network access.

### 2.8 Mesh upload
- **Sandbox-safe path:** `python tools/level4_blender/studio_upload.py [export_dir] [--reuse results_vX.jsonl …] [--limit N]`.
  1. Skips chunk ids already in `results.jsonl`; reuses an existing asset when the base64 sha256 matches a `--reuse` file (`studio_upload.py:23-50`).
  2. Inlines up to 900,000 characters of base64 per `execute_luau` call (`:17`).
  3. In Luau: `EncodingService:Base64Decode`, then `build()` creates the EditableMesh (`upload.luau:11-38`).
  4. Uploads with `AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name="L4_Cinema_v3_<id>", CreatorId=1039373905, CreatorType=Group})`, up to 4 attempts with `5*attempt` s waits (`:84-117`).
  5. Picks the Studio whose name contains "BACKROOMS" (`:73`).
- **Legacy path (`serve.py` + `upload.luau`):** relies on toggling `HttpEnabled`, `shared` state and a `task.spawn` background loop (`upload.luau:40-91`). It no longer works since the 2026-10-02 sandbox change (`README.md:107-110`).
- **Level 1 path:** `python tools/level1_blender/import_assets.py --assets assets/level1/blender-v2 --kit-name Level1BlenderKitV2 --upload --studio-id <exact>`.
  - Batches of at most 650,000 characters.
  - Asserts place 131311258779917.
  - Receipts keyed by `wireSha256` in `export/roblox-assets.json`. V2 reused 47 of 93 meshes from V1 (`import_assets.py:20-44,141-179`).
- **Ledger and throughput:**
  - `results.jsonl`: 568 rows, 524 unique assets, 389 reused.
  - v3 upload: 389 chunks in 85 calls. final2: 99 uploads across 48 calls (`v3\upload_*.log`).
  - One `CreateAssetResult.UploadFailed` was recorded (`results_v2.jsonl`, id 321).

### 2.9 Placement and installation
- **Level 4:**
  1. `python make_place.py [export]` writes `export\chunks\c99999.b64`. Despite the name it is JSON: styles (Material, Color, Transparency, SurfaceAppearance maps `c/n/r/m` + tint + AlphaMode), chunks, placements, colliders (occluders inset), propColliders, lights × gains, carriers (`make_place.py:253-289`).
  2. `python place_driver.py [export] [--phase templates|placements|rest] [--stage-only]`.
     - Recreates `ServerStorage.L4PlaceStaging`.
     - Stores the packet and asset map as StringValues in 190,000-character pieces, four per call, in long brackets `[========[…]========]` (`place_driver.py:14,60-73`).
     - Runs `place_phases.luau` with helpers spliced in from `place.luau` (`:30-33,76-87`).
  3. The phases (`place_phases.luau`):
     - **templates:** `CreateMeshPartAsync(Content.fromUri(id), {CollisionFidelity=Box (falls back to Default), RenderFidelity=Automatic})`. Parts are anchored, with CanCollide/CanQuery/CanTouch all false (`:61-111`).
     - **placements:** clones the templates into one Model per prop; bare decorative props share Folders. Doors get Hinge + Leaf + a Servo HingeConstraint (`:113-242`).
     - **rest:** `Collision` becomes a Persistent Model (`:41-56`); signage, lights, `UpdateSourceAsync` on the two kept scripts, Bounds attributes; the staging folder is destroyed (`:244-337`).
  - `styleMesh` adds a SurfaceAppearance only when the material is not Neon or Glass (`place.luau:234-253`). `makeCollider` creates occluders with Transparency 0, Color (8,8,8), SmoothPlastic, named "Occluder" (`:264-297`).
- **Level 1:** `import_assets.py … --install --studio-id <exact>` runs one `execute_luau` call.
  - Builds `ServerStorage.<Kit>/Components`: MeshParts with Box fidelity, a SurfaceAppearance named "BlenderPBR", and invisible colliders in collision group `Decor` except for Floor/Ceiling/WallHalf.
  - Builds `Rooms` with attributes `OpenMask`, `Variant`, `CellSize`, `SelectionWeight`, `RoomRole`.
  - Refuses to overwrite an existing kit and sets `Ready` only at the end (`import_assets.py:47-130`).

### 2.10 Runtime and the developer preview button (Level 1 template)
- **Runtime:** `BlenderRoomRenderer.IsReady` requires the kit's `Ready` attribute and all 15 masks (`ServerScriptService/Level 1 Systems/BlenderRoomRenderer.ModuleScript.lua:11-37`). `Begin` clones a weighted room per cell by OpenMask (`:135-235`). It is a "developer-preview skin over the live Level 1 query/collision grid" (`:1`).
- **Server entry:** `ServerScriptService/Level1BlenderPreviewAccess.Script.lua:1-40`.
  - RemoteEvent `Level1BlenderPreviewRequest`, gated by DevAccess.
  - Host part `Level1BlenderPreviewEntry` sits in `Level1QueueRoom` or `LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level1`.
  - Skipped on reserved servers.
- **Client button:** `StarterPlayerScripts/Level1BlenderPreviewButton.LocalScript.lua:1-25`. The prompt reads "ENTER LEVEL 1 FACELIFT PREVIEW", exists only for DevAccess players, and is disabled while `InRound`.
- **Script install:** `tools/level1_blender/install_sources.py:22-27` (plan for creating new scripts).

## 3. Budgets used
| Item | Value | Source |
|---|---|---|
| Per chunk / MeshPart | ≤20k tris, ≤60k verts, ≤1800 studs | `export_l4.py:57` |
| Level 4 whole level | ~1.0M unique tris; new instanced props ≤2.5k tris; lights ≤260; shadows on at most 6 hero lights | `BRIEF.md:33,180` |
| Meshy request | meshy-7: 2.5k–8k; meshy-6: 5k (litter) / 8k (lockers); Usher 16k | transcript |
| Meshy after Blender decimation | arcade 6–8k, toilet 3k, urinal 2.5k, popcorn/projector 8k, soda 6k, lockers 3k, litter 1.2k | `meshy_specs.json` |
| Maps | architecture 1024²; Meshy 1024² (litter 512²); constant metal 64²; Roblox stores 1024² | `make_pbr.py:18`, `import_meshy.py:33`, `make_pbr_all.py:26` |
| Level 1 kit | ≤150 chunks, ≥30 rooms, cell 24 / wall 14 / thickness 2 | `check_assets.py:14-15` |
| Usher | 8,171 + 660 (torch) tris | `final4\DONE.txt` |

## 4. Level 4 end state
**In Studio** (last `place_phases` return, 2026-10-02 10:00, transcript `2af1996b…`):
| Item | Count |
|---|---:|
| World (pooled MeshParts) | 341 |
| Props children (Models + shared decorative Folders) | 1,578 |
| Doors | 25 |
| Collision parts | 1,665 (805 of them black occluders) |
| Prop colliders | 2,852 |
| Signage | 74 |
| Lights | 260 |
| **Total descendants** | **14,563** |

The total MeshPart count was not recorded.

**Export** (`final4\DONE.txt`): 956,315 tris, 570 chunks, 1,893 placements, 7,272 collider records (5,607 of them `L4UsherNode` markers, which are filtered out of the import), 2,852 prop colliders.

Earlier v3: 13,925–14,190 descendants with World = 233.

**Proven ways to cut instances:**
- Pool architecture per material.
- Put bare decorative props in shared Folders. In v3 this saved 252 net Models: 257 decorative MeshParts were placed in 5 shared folders (`P7b_SAVINGS.txt:10`).
- Run the prop-collider containment/merge pass.
- Each textured MeshPart costs one extra SurfaceAppearance instance. Neon and Glass parts get none.

## 5. Reusable vs Level-4-specific
| Reusable as-is or with path/constant edits | Level-4-specific |
|---|---|
| `make_pbr.py` (pure; Level 1 already imports it) | `l4_dump.json`, `layout_edits.py`, `l4_layout.json`, `build_base.py` |
| `make_pbr_all.py` + spec (hard-coded OUT, `:10`) | `props*.py`, `arch_detail.py`, `ceilings.py`, `doors*.py`, `round_assets.py`, `usher_nav.py`, `lights_and_camera.py` |
| `import_meshy.py` (hard-coded TEX dir `:32`, `L4A_` prefix, "L4 Meshy Assets") | `export_l4.py` module scope: loads layout + dump on import (`:70-72`), `OX=23000` (`:66`), "L4 Cinema" collection, DOOR_PARTS, prune/carriers/legacy lights, usher_nav zone import (`:595-601`) |
| `upload.luau` `build()`; `studio_upload.py` (name prefix, paths, GROUP `:14-20,92`) | `make_place.py` light gains, AUD_BOX, REMOVED_ZONES, LEGACY_CEILING, CARRIER_MOVE, STYLE_OVERRIDES (`:35-60`) |
| `export_l4.py` functions `box_cf`, `box_uv`, `tris`, `split`, `emit`, `object_colliders`, `export_lights`, `mat_info` | `place.luau` / `place_phases.luau`: NAME/OLD_NAME/SHIFT/ORIGIN (`place.luau:38-44`), lookups into the old preview, flicker + PushDoors, exit pad, model attributes (`place_phases.luau:22-26,298-328`) |
| `make_place.py` `style`, `collider`, `optimise_prop_colliders`, `bare_props`, `tex_requests`, `tex_merge` | `cull_hidden.py` (coordinates, seeds, paths) |
| `place.luau` `styleMesh` / `makeCollider` / `makeLight` + the StringValue staging pattern | `build_all.py` step list and MASTER path (the pattern itself is reusable) |
| `blrun.py`; Level 1 `build.py` Mesh class + `export_chunks` + manifest, `check_assets`, `verify_native`, `import_assets`, `publish_textures` | Level 1 tools hard-assert "Only Level 1 … directories" (`import_assets.py:192`, `publish_textures.py:24`), whitelist kit names (`:193`) and the 24/14/2 grid (`check_assets.py:14`) |

**Third reference, `tools/level5_import`:**
- `export_l5.py`: objects placed 2 or more times become one asset per material; everything else is pooled; `MAX_EDGE` 500 forces subdivision.
- `make_place.py`: maps material names to Roblox materials with a regex `RULES` table plus a `NO_COLLIDE` regex; no PBR.
- Result: 851 assets.
- Afterwards a single-sided ceiling plane had to be flipped 180° in Studio (`tools/level5_import/README.md`).

## 6. Studio MCP sandbox and the workarounds
- **The limits** (`CLAUDE.md:524-527`):
  - `execute_luau` has no Network capability (no HttpService, no HttpEnabled).
  - No `shared` or `_G` between calls.
  - `task.spawn` work dies when the call ends.
  - Scripts cannot be created or reparented under Workspace or ServerStorage.
  - Still works: `UpdateSourceAsync`, `CreateAssetAsync`, and a 1.2 MB code payload.
- **Workarounds:**
  - **No HTTP:** chunk base64 is embedded in the code payload (`studio_upload.py:1-3,17`).
  - **No shared state:** state lives in instances — `ServerStorage.L4PlaceStaging` StringValues plus `STAGE.Templates` between synchronous phases (`place_phases.luau:2-22`; `place_driver.py:60-87`).
  - **No new scripts:** the model must already exist. The templates phase destroys everything except BaseScripts (`:65-74`); the rest phase updates the two kept scripts with `UpdateSourceAsync` (`:298-305`). For brand-new scripts: create them in Studio first, then add the manifest entry (`CLAUDE.md:179-182`).
  - **Textures** go through the separate `upload_image` MCP tool.
  - **MCP timeouts:** the templates phase can time out on the MCP side while Studio finishes. Check the counts, then run `--phase placements` / `--phase rest` separately (`README.md:152-153`).
  - **No privileged calls:** `execute_luau` cannot `require(DevAccess)`, Invoke bindables, or FireServer (memory `level4-round-qa`).

## 7. Known pitfalls
1. **Camera clipping.** Poppercam only stops at CanCollide parts with Transparency < 0.25. With invisible colliders under non-colliding visual meshes, the camera passes through every wall. Fix: opaque black colliders inset 0.1 stud (`CLAUDE.md:521`; `make_place.py:47,106-118`). A client-side `LocalTransparencyModifier` on them silently disables occlusion again.
2. **Streaming drops big floors.** A huge collider inside a Folder under a Default-streamed model gets dropped on the client and players fall through. The collision container must be a Persistent Model (`CLAUDE.md:542`; `place_phases.luau:41-56`).
3. **Lighting.** The place runs LightingStyle Realistic (`CLAUDE.md:502`). Blender light values come out far too dim, so gains live in `make_place.py:35-45`. Client-side light tweaks during play are undone by streaming; tune on the Server datamodel. Neon behind poster decals blooms the decal away (fixed via `STYLE_OVERRIDES`). Alpha decals need `AlphaMode` Transparency plus part Transparency 0.02 (`make_place.py:91-93`).
4. **Stale styles.** Always rerun `make_place.py` after `--tex-merge`; a style exported before the ids existed ships without maps (memory `level4-blender-cinema`). On v3, 33 texture mappings were still missing (`P7b_SAVINGS.txt`).
5. **Upload ledger trap.** `studio_upload.py` treats any id already in `results.jsonl` as done. Archive the file before an export whose chunk ids overlap the last one, then pass the archive to `--reuse` (`README.md:150-151`).
6. **Codex prompts must say "do NOT run git".** On 2026-09-30 a Codex image batch committed its PNGs on its own (commits 3d7f70e, 5eae851). `gpt-6.1-sol` was rejected that day.
7. **Don't fan out heavy work to Claude agents.** 10 parallel Claude agents burned ~2.3M tokens and hit the session limit with nothing done. Heavy package work went to parallel `codex exec` jobs instead (memory `level4-blender-cinema`).
8. **Blender hygiene:**
   - Never save over the master blend (`build_all.py:82-86`; `cull_hidden.py:506-508`).
   - The owner keeps the `.blend` open in the GUI, and an old session once saved over a finished file.
   - Cap concurrent Blender processes at 4.
   - Headless gotchas: an EEVEE world volume blacks out the render; camera-bound timeline markers override `scene.camera` (memory `blender-headless-gotchas`).
   - Blender 5.2's FBX exporter warns about linked duplicate material slots (`build.py:558`).
9. **Meshy GLBs.** Each GLB must have one textured atlas. Decimation drops the GLB normals, so `sharp_angle` re-shading is needed. Meshy's front direction varies; use `yaw_deg` (the projector needed −90°, `props_lobby.py:1290`). Restroom fixtures were scaled ×1.15 for character scale (`props_rooms.py:669`).
10. **Mesh build.** Use `CreateMeshPartAsync` with Box collision fidelity and a Default fallback (`place_phases.luau:83-86`). `CreateAssetAsync` can return `UploadFailed`, hence the retry loop.
11. **Template leaks.** Level 2 World Builder's runtime `CreateMeshPartAsync` templates once leaked 21 duplicates into the ServerStorage root. Adopt an existing copy by name + MeshId (`CLAUDE.md:450`).
12. **Prompt exclusivity.** ProximityPrompt OnePerButton only shows the closest prompt per key; keep pump and lever prompts apart.
13. **Layout indexing.** Layout parts must stay index-aligned with `l4_dump.json`: delete by tombstone, add by append.
14. **Publishing.** Studio has no scriptable publish. `codex exec --enable computer_use` published the place; trust Studio's toast, not the asset's Updated timestamp (`CLAUDE.md:496`).

## 8. Existing Level 2 assets
- **`assets/level2/`:** three Luau EditableMesh generators for already-published meshes:
  - `column-flare-9-stud-uv-v1.luau`: column flares 4.5 / 5.5 / 9 → ids 90304501186271, 118916035196716, 111134467625970; `TILE_STUDS=9` (`:10-16`).
  - `slide-closed-end-cap-v1.luau` → 107409495820821.
  - `slide-cradle-continuous-u-v1.luau` → 132916619634128.
- **`assets/level2/poolslide/`:** the Pool Slide recovery pack (reconstruct script, recovery bundle, keyframes, source-pack, a native `.rbxm` from 2026-09-09, navigation/second-pump verification). It belongs to the retired hostile.
- **`tools/level2_arch_rib_obj.py`:** exports a corridor arch rib as OBJ. Its key format matches the World Builder's `ArchRibMeshKeyFor`; texture 113211706146395 at 7 studs per tile (`:31`). The OBJ is meant for upload through Creator Hub or Import 3D into `Level 2 Configuration.Performance.ArchMeshRibAssets[key]` (`:17-20`). Collision note: PreciseConvexDecomposition (`:126`).

## 9. What this means for a Level 2 kit
- **Copy Level 1's architecture:** build components + room/tunnel variants with socket masks → manifest → `publish_textures` → `import_assets --upload` / `--install` into `ServerStorage.<Kit>` → a renderer that clones per cell.
  - Generalise the Level-1-only asserts and the 24/14/2 grid.
  - Bring in Level 4's `make_pbr`, `import_meshy`, `style()` / SurfaceAppearance rules, the occluder rule and the collider merge.
  - Skip `cull_hidden` (randomised layout, ~2–6% yield). Delete hidden backfaces at authoring time instead.
- **Slopes and hills:** the exporter's scene colliders are rotated boxes (OBBs). Only layout parts can become `WedgePart` (`export_l4.py:701`; `place.luau:271-272`). A sloped floor therefore needs rotated `l4_col` boxes, or visual MeshParts with their own collision.
- **Instance budget anchor:** the whole cinema is ~14.6k instances. Live Level 2 is ~52k (per the brief).

## Key files (absolute)
- `G:\Roblox\MongoTV\tools\level4_blender\` — README.md, build_all.py, slots.py, import_meshy.py, meshy_specs.json, make_pbr.py, make_pbr_all.py, pbr_spec.json, make_textures.py, cull_hidden.py, export_l4.py, make_place.py, studio_upload.py, place_driver.py, place_phases.luau, place.luau, upload.luau, serve.py, results*.jsonl, textures.json
- `G:\Roblox\MongoTV\tools\level1_blender\` — README.md, build.py, build_v2.py, prepare_v2_textures.py, check_assets.py, verify_native.py, publish_textures.py, import_assets.py, install_sources.py
- `G:\Roblox\MongoTV\tools\level5_import\`
- `G:\Roblox\MongoTV\tools\level2_arch_rib_obj.py`
- `G:\Roblox\MongoTV\assets\level2\`
- `G:\Roblox\MongoTV\assets\level1\blender-v2\`
- `G:\Roblox\MongoTV\artifacts\level4-facelift-20260930\{moodboard,props,synth,textures}\prompt.txt` and `codex.log`
- `G:\Roblox\MongoTV\artifacts\level4-facelift-v3-20261002\BRIEF.md` and `P7b_SAVINGS.txt`
- `G:\Roblox\_local\l4facelift\v3\` — launch_codex.sh, blrun.py, gen\prompt.txt, final2\run.sh
- `G:\Roblox\_local\l4facelift\v5\final4\DONE.txt`
- `G:\Roblox\_local\l4meshy\` — tasks.json, run_import.py, GLBs
- `G:\Roblox\MongoTV\ServerScriptService\Level1BlenderPreviewAccess.Script.lua`
- `G:\Roblox\MongoTV\StarterPlayer\StarterPlayerScripts\Level1BlenderPreviewButton.LocalScript.lua`
- `G:\Roblox\MongoTV\ServerScriptService\Level 1 Systems\BlenderRoomRenderer.ModuleScript.lua`