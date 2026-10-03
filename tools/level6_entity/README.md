# Level 6 entity: The Counter

A porcelain doll in a party hat that counts with its hands over its eyes, then searches. Concept images are in
`artifacts/level6-playground-20261002/concepts/entity/` (08 and 09 are the approved look); everything built
from them is in `artifacts/level6-entity-20261003/`.

## Pipeline (repo root, Studio open on the place)

1. **Meshy** (MCP server `meshy`): T-pose reference image -> `image_to_3d` (meshy-7, 10k triangles, PBR, 2K)
   -> `rig` (24-bone humanoid, 1.3 m). Downloads are in `meshy/`.
2. `Blender -b --python tools/level6_entity/build_base.py` cleans the rig (metres, 4 bone influences per
   vertex) and keeps Meshy's walk and run as source actions for the legs.
3. `Blender -b --python tools/level6_entity/build_animations.py -- [--no-video] [--only=Idle,Catch]` writes
   the ten clips, contact sheets and preview videos (`renders/`), FBX files (`export/`) and
   `blend/counter_animated.blend`. Poses are written as rotations in rest axes, so `Rx(+)` on the head nods
   whatever the body below is doing; arms over the eyes and the lunge's feet use a two-bone IK.
4. `Blender -b --python tools/level6_entity/export_roblox.py` writes `export/roblox_mesh.json` and
   `export/roblox_clips.json`: Blender (x, y, z) becomes Roblox (-x, z, y) * 3.7 studs, facing -Z.
5. `python3 tools/level6_entity/import_to_studio.py mesh [--probe]` stages the mesh as StringValue chunks in
   `ServerStorage.Level6CounterSource`. The clips are StringValues in `ReplicatedStorage.Level6Counter.Clips`
   and the 38 voice lines are Sounds in `ReplicatedStorage.Level6Counter.Voice` (attribute `Seconds`).

## Clips

Idle, Count_Start, Count_Loop, Count_End, Walk_Wander (head scans and twitches), Search_Look, Spotted,
Run_Chase, Catch, Head_Twitch (head and neck only, layered at random over Idle, walk and run).
`export/animations.json` lists length, loop flag and purpose.

## How it runs in the game

- `AssetService:CreateAssetAsync` is not available from a Studio session, so the mesh cannot become an asset.
  The game module rebuilds it once per server as a skinned EditableMesh (`AddBone` needs `Virtual = false`),
  bakes it with `CreateDataModelContentAsync` and adds the Bone instances by hand. The result replicates.
- A SurfaceAppearance does not render on that baked mesh; the colour map goes in `TextureID`.
- No Animation assets: the server publishes `Anim`, `AnimSerial` and `Speed` on the model and the client
  writes `Bone.Transform` from the clip data each frame, with a 0.16 s crossfade.
- Weld the body to the root with a `Weld`, not a `WeldConstraint` (that left the body at the world origin).
- Audio uploads: Studio's Asset Manager > Import (File dialog: Cmd+Shift+G, paste the path). Asset names over
  50 characters are rejected. Select the rows > Insert Selection > Insert at Camera drops Sound instances
  into the place, which is how the ids were read.
- The textures were uploaded with the MCP `upload_image` tool and needed "Share access" once.
