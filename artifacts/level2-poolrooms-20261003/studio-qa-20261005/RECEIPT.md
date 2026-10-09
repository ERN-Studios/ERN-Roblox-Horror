# Level 2 Poolrooms - 0.5-stud tile revision installed in Studio for the owner's test (2026-10-05)

Place 131311258779917, Studio id 1df8b7bb-00bf-45ee-8a47-1ab3459044a6. NOT published (the owner tests first).

## Installed
- `ServerStorage.Level2BlenderKit`: 202 components, 51 slide templates, 10 SlidesJSON slices; 214 new meshes
  uploaded; `import_kit.py --audit` OK. The previous v2610 kit is kept as `ServerStorage.Level2BlenderKit_Previous_v2610`
  for rollback.
- MaterialVariants: `PR Tile` / `PR Tile Aqua` StudsPerTile 4.0 (0.5-stud tiles on Parts, owner-approved), new twins
  `PR Tile Mesh` / `PR Tile Aqua Mesh` at 4.22 for kit MeshParts (see below). `PR Iron` unchanged.
- Scripts pushed through the CAS push tool, no conflicts: Level 2 Kit World Builder, Level 2 Kit Layout Generator,
  Level 2 Lighting Controller. Pull audit: no Level 2 drift.

## Measured in Studio (Play)
- Roblox lays a MaterialVariant on a MeshPart in the mesh's own space, in studs, NOT through its UVs: tiles are the
  same on an old (4.8-stud UV) and a new (4.0-stud UV) column and on a column stretched to twice its height; they move
  with the mesh; they scale with StudsPerTile. At equal StudsPerTile a mesh's tiles are smaller than a Part's, so the
  meshes get their own variants: at 4.22 a kit column's tiles measure 23.54 px against a Part's 23.57 px at the same
  depth (0.5 stud each).
- Preview lighting: with the lowered ambient (WP6, hall lamps carry the light) the halls measured mean luminance
  45-54 at ExposureCompensation 0 and 141-158 at 0.8, against 81-84 for the owner-approved renders; 0.4 gives 62-83.

## Smoke Play QA (developer preview via the pedestal prompt)
- Three preview rounds built without errors in the console; 12,052 / 12,580 objects in the world folder; MeshParts use
  `PR Tile Mesh` (2,222-2,241), Parts `PR Tile` (3,090-3,525).
- Images 01-07 in this folder (exposure 0.4, final install).

## Known, not yet done
- The builder test's lattice check still reports about 46 small corner steps per map (arrival door vs hall floor,
  chamber ledge T-corners, exit door frame).
- Because Roblox ignores the kit UVs for MaterialVariants, the grout phase on curved kit meshes follows Roblox's
  own mesh-space projection, not the offline UV design; mesh-to-Part grout continuity needs its own Studio check.
- No full gameplay pass (pumps, Pool Foam, exit ride) this time; the owner tests and can order a QA round.
