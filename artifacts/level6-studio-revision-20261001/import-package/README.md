# Level 6 Studio import package — 2026-10-01

This package comes from the 24×24-stud, 14-stud-portal Blender derivative
`../StudioImport_Portal14_Full_Seed101.blend`. The original 2026-09-30 Blender
source and export remain available unchanged. The 61 reusable families contain
279 per-material mesh chunks; the three new room families include their child
fixtures in the visual meshes and child collision boxes in metadata. Runtime
must not place those same child fixtures or colliders a second time.

`manifest.json` is the complete offline geometry/material/provenance record.
`runtime-manifest.json` is the compact source payload read by RuntimeBake.
`Level 6 Kit Metadata.v2.ModuleScript.luau` carries family bounds, collision,
anchors, room lights, and portal details for the live Visual Adapter.
`materials-runtime.json` has uploaded props-atlas and PBR MaterialVariant routes.
`chunks/cNNN.b64` stores centered LVM6 binary geometry as base64. Blender UVs
remain 0–1; RuntimeBake flips V once for Roblox.

The local package server is launched with:

```sh
python3 tools/level6_build/import/serve.py artifacts/level6-studio-revision-20261001/import-package --port 8890
```

The additive Edit-mode installer is
`tools/level6_build/import/install_revision_runtime_source.luau`. It creates
`ServerStorage.Level6BlenderSourceRevision20261001` with compressed raw chunks,
leaving the earlier source intact. The v2 RuntimeBake then reconstructs a
server-session `ServerStorage.Level6BlenderKit` Folder of 61 Models, each with
named MeshPart children at family-local centers. Uploaded `MaterialVariant`
maps use fixed `StudsPerTile`; prop chunks use the uploaded atlas `TextureID`.
No external HTTP is needed during gameplay. The raw source must be present in
the saved place for every new server to reconstruct the kit.

`verification.json` records the offline binary/hash/geometry/12-stud center
lane checks. It is not a Studio Play, replication, performance, or publish
result. Run `python3 tools/level6_build/import/verify_revision_import_package.py`
after any regeneration. The source installer refuses an existing revision
namespace; live source and editor baselines must be checked before application.
