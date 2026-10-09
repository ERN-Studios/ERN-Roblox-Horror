# Level 2 v2 kit: Studio runbook (run only after an explicit Studio handback to Level 2)

Everything below is prepared and tested offline (commits 6e89a02, 95e07fb, 244b019). Nothing is in Studio yet.

## 0. Gate
- Read `artifacts/monocode-night-20261003/coordination.md` and `artifacts/level1-quality-20261002/coordination.md`.
  Proceed only after an explicit handback to Level 2 with Studio in EDIT and no Play. Write a dated Level 2
  reservation in both files first. Never publish (owner rule).
- `git status` (foreign untracked/modified files are other sessions' work; keep them).
- `python tools/pull_source_from_studio.py --audit`. Do NOT pull: the working copy holds four Level 2 candidates
  that Studio does not have yet (`Level 2 Round Adapter`, `Level 2 Pool Foam Navigator`, `Level 2 Pool Slide
  Navigator`, `Level 2 Pool Slide Controller`; copies in `drafts/level2-blender/`). Any OTHER drift belongs to
  other sessions: leave it.
- `list_roblox_studios` -> exact studio id (it changes on restart).

## 1. Quick Studio facts (execute_luau, Edit, read-only probes first)
1. MaterialVariant on a MeshPart: does StudsPerTile scale mesh UVs? Create one throwaway MeshPart + variant
   off-tree, read back, destroy. Adjust `import_kit.py` StudsPerTile only if it does.
2. Swim threshold (needs a short Play later, step 6): wading depth 2.0 / 2.5 / 3.0 / 3.5 -> Humanoid state.
   Set the kit generator's `DeepEndMax` to the deepest value that never swims (owner cap 3.5).

## 2. Kit install (tools/level2_blender/import_kit.py)
```
python tools/level2_blender/import_kit.py --plan
python tools/level2_blender/import_kit.py --upload-textures --studio-id "$ID"
python tools/level2_blender/import_kit.py --upload-meshes   --studio-id "$ID"
python tools/level2_blender/import_kit.py --plan
python tools/level2_blender/import_kit.py --install --studio-id "$ID"
python tools/level2_blender/import_kit.py --audit   --studio-id "$ID"
```
Creates `MaterialService` variants `L2K *` and `ServerStorage.Level2BlenderKit` (Ready last). Touches nothing else.

## 3. Scripts
- NEW (create in Studio first via execute_luau + `ScriptEditorService:UpdateSourceAsync`, then add manifest items
  with `tools/studio_source_contract.py` sha256_of/canonical_bytes):
  `ServerScriptService."Level 2 Systems"."Level 2 Kit Layout Generator"` (ModuleScript),
  `ServerScriptService."Level 2 Systems"."Level 2 Kit World Builder"` (ModuleScript),
  `ServerScriptService.Level2BlenderPreviewAccess` (Script),
  `StarterPlayer.StarterPlayerScripts.Level2BlenderPreviewButton` (LocalScript).
- CHANGED live scripts: fresh Studio read of each (execute_luau `.Source`), confirm it still equals HEAD~3's base
  (else merge), then `UpdateSourceAsync` the candidate: Round Adapter, both navigators, Pool Slide Controller.
- GameManager: fresh Studio read -> `git apply`-style apply of `drafts/level2-blender/GameManager.level2-preview.diff`
  onto THAT source (regenerate the diff if Studio moved) -> compile -O0 -> `UpdateSourceAsync`. Never overwrite
  foreign hunks.
- `tools/studio_compile_probe.luau` (or offline `luau-compile -O0` if the probe is sandbox-blocked), then
  `python tools/record_pending_push.py --dry-run` to confirm only Level 2 items differ, and record the manifest
  items for exactly those files.

## 4. Lobby button placement (Play, Server datamodel)
The lobby is rebuilt at play start. Measure the Level 2 room host offsets in BOTH lobbies
(`ServerLobby.LevelQueueRooms.Level2QueueRoom`, `LobbyReimaginedPreview.PreviewQueuePads.QueueBay_Level2`) and set
the two constants in `Level2BlenderPreviewAccess`; confirm a non-developer sees nothing.

## 5. Preview round QA (developer, Studio local round)
Pinned seeds 3x (`Level2Seed`), record: `Level2_WorldDescendants`, `Level2_BuildSeconds`, frame time p50/p95.
Check: arrival spawn; Pool Foam spawn/patrol/chase/kill; Pool Slide spawns after 2 pumps, cannot enter narrow
passages/small rooms, targets only reachable players; pumps/drains/pressure doors; slide rides on all flumes and the
helix; exit flume ride + recycle + `Level 2 Exit Transition Test Suite`; height changes (stair tunnels) walkable for
players and Pool Foam; no holes (walk every tunnel mouth edge); no progression on a preview win; live Level 2 round
unchanged afterwards (flag cleared). Device Simulator phone run.

## 6. Handback
Studio back in EDIT without Play, dated handback in both coordination files, local commit, no publish.
