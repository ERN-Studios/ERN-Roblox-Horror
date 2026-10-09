# Level 2 Poolrooms - Studio install, QA and publish receipt (2026-10-03)

Place 131311258779917 (universe 10559217407), Studio id 86f22f6f-aafa-4af2-b2dc-cf471bf0e3a4. Local commits d7d6b6a, a157fe6.

## Published
- Version **v2610** (Team Create save 2026-10-03 20:04:38 UTC; games API `updated` = 2026-10-03T20:04:38.825Z),
  taken 26 s after the last Level 2 change in Studio (Lighting Controller + button push, 20:04:12 UTC).
- Studio Output (`publish-proof-output-v2610.jpg`): `22:19:36.785 Published new changes in "BACKROOMS: STAY QUIET
  [CO-OP HORROR]" to Roblox.`, then `22:24:25.792 Place published. Eligible players can now play this place in
  Roblox.` with `Add publish notes to v2610`, `22:24:25.877 Published new changes ...` (CEST = UTC+2).
- Version history (`version-history-v2610.jpg`): v2610 marked Published; v2607 (ZenMeister02, 19:48 UTC) Previously
  Published. The publish ships the whole place, including other sessions' finished Studio work.

## Installed
- `ServerStorage.Level2BlenderKit`: 106 components, 44 slide templates, 10 SlidesJSON slices; 189 meshes,
  13 PBR textures; audit OK (incl. every component MeshPart `DoubleSided`).
- New scripts: Level 2 Kit Layout Generator, Level 2 Kit World Builder, Level2BlenderPreviewAccess,
  Level2BlenderPreviewButton. Updated: Level 2 Round Adapter, Pool Foam Navigator, Pool Slide Navigator,
  Pool Slide Controller, GameManager (preview patch merged onto the live source), Level 2 Lighting Controller.
- Final drift audit: every Level 2 script and GameManager equal to the repo.

## Play QA
- Button: prompt `ENTER LEVEL 2 POOLROOMS PREVIEW` + visible pedestal/label, developers only, in the reimagined
  lobby's Level 2 bay (host 303, 34.8, -840) and the old Level2QueueRoom. Triggered by E (desktop) and by a touch
  on the Found Footage HUD plate in the iPhone 17 Pro simulator (touch -> hold -> Triggered -> server accepted).
- Round: build 1.95-2.26 s, 47-51 halls, 7,866-8,317 world objects. Pool Foam active (Foreshadow -> Pressure,
  lethal after the second pump). Pool Slide spawned after two pumps and chased (CHASE/MOVING, no error).
  ~48 fps in Studio (server+client in one process), p95 40 ms.
- Three pumps -> EXIT_OPEN -> flume ride 670,72 -> 777,5 in 2 s -> Escaped -> lobby; preview flag cleared, world
  and terrain water removed, water colour restored, no progression.
- Found and fixed in Studio: tunnel barrels/coves/chamber walls were culled (sky visible through tunnels,
  `01_` vs `02_`). Kit MeshParts are now DoubleSided.
- Live Level 2 (queue pad, CREATE PARTY) still builds its old world (50,607 objects), entities ready, no errors.

## Not covered
- The reserved-server teleport path of the preview (TeleportService) cannot run in Studio; it mirrors Level 1's.
- Offline visual leak check (HOLE-C) needs a backface-aware rewrite; its collision flood fill reported 0 leaks.
