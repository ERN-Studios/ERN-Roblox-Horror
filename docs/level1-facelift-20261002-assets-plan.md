# Level 1 Blender facelift — asset pipeline

The live Studio game is authoritative. This plan does not authorize running any
Level 4 import script or replacing the active Level 1 generator from a repository
copy. The new art belongs in a separate developer preview until gameplay and
access checks pass.

## Confirmed tools (2 October 2026)

- Blender `D:/Blender/blender.exe`: **5.2.0 LTS**. An isolated, read-only headless
  probe confirmed FBX, glTF and OBJ exporters. The user's running Blender process
  was left alone. No MCP bridge is listening on port 9876.
- The Level 4 pipeline already proves the useful import contract: Blender mesh
  vertices, corner normals and UVs become group-owned Roblox mesh assets through
  `AssetService:CreateAssetAsync`, then MeshParts with SurfaceAppearance maps.
  See `tools/level4_blender/export_l4.py`, `upload.luau`, `studio_upload.py` and
  `make_place.py`. Group ownership in those tools is `1039373905`; confirm the
  destination's ownership before an upload.
- `tools/level4_blender/make_pbr.py` already produces wrap-aware albedo, OpenGL
  tangent normal, roughness and optional AO/height maps. Reuse it, including its
  runnable self-check. These are derived detail maps, not measured scans.
- Studio's current MCP import environment has no Network capability or persistent
  `shared` between calls. Inline chunk payloads and staged StringValues are the
  existing solution. Scripts must be installed through ScriptEditorService,
  rather than created under Workspace by the asset placement code.
- The Studio-owned mesh upload path requires no separate Open Cloud credential.
  No credential contents were read or printed.

## Smallest compatible asset design

Keep the live maze grid, objective placement, enemy navigation and round reset
contract. Replace the visual layer with a Blender-authored room catalogue whose
walkable sockets match that grid exactly. Room choice can vary by seed without
changing which connections are open.

Use one consistent yellow Backrooms kit: worn loop-pile carpet, aged patterned
wallpaper, dirty acoustic ceiling tiles, restrained cream/beige trim, fluorescent
troffers and occasional dark fixtures. Source the visual brief and texture art
from newly generated image references before modelling. Carpet/wall/ceiling PBR
sets must have the same physical repeat scale in Blender and Roblox.

Author reusable floor, ceiling, closed wall, doorway wall, baseboard, pillar and
light meshes in Blender. Assemble room templates for straight passages, corners,
T junctions, cross junctions, dead ends and broader spaces. Use socket-mask
metadata; rotate only in exact quarter-turns. Decorative variants must preserve
the same safe walkable corridor. Blender-authored props should share the kit's
materials and include explicit, simple collision boxes where needed.

Do not bake one entire random level into a mesh. Export the reusable meshes once
and clone their imported templates. The random generator assembles them in
Roblox. This preserves generation, navigation, objective and reset behaviour
while satisfying the Blender-built visual requirement.

## Deliverables and validation

- New native `.blend` master in a dedicated Level 1 directory, plus FBX
  interchange export; keep relative texture references. The owner explicitly
  declined backup files; the independent project leaves the running scene alone.
- Repository build script, PBR source/maps and a manifest with scale, axes,
  materials, socket masks, collider boxes, triangle/vertex counts, file hashes
  and Roblox asset IDs after verified upload. Record native file checksums.
- Roblox mesh export uses the existing binary layout: four little-endian uint32
  counts (positions, normals, UVs, triangles), float32 attributes, followed by
  nine uint32 indices per triangle. Coordinates convert Blender metres to
  Roblox studs using **1 stud = 0.28 m** and `(x, y, z) -> (x, z, -y)`.
- Each mesh stays below the existing conservative ceiling of 20,000 triangles,
  60,000 vertices and 1,800 studs per axis. Room meshes should be far smaller.
- Validate every socket pairing, floor/ceiling/wall seam, unobstructed objective
  marker, corridor clearance, light budget and reset cleanup across multiple
  seeds. Live gameplay, multiplayer and performance checks need actual Studio
  play sessions; source checks cannot certify them.

## Remaining inputs and blockers

Live Level 1 dimensions were verified: cell spacing 24, wall height 14,
full wall thickness 2 studs, floor top at Y=0. North is Roblox Z+. Half walls
inside each room join at shared closed boundaries and match the existing full
wall colliders. Also inspect the
existing Level 4/5/6 developer preview access contract. These dimensions are not
inferred from old asset records. The absence of Blender MCP is not a blocker:
isolated headless builds are available. Asset upload and texture loading remain
unverified for this new kit until tested in the correct current Studio session.
