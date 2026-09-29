# Furnished Aero House import — 2026-09-29

Requested: create simple Frutiger Aero furniture, place it in the house and replace the cathedral in the open Roblox Studio experience. The import target was inspected live: place `121672571539226`, universe `10768500985`; this is separate from Backrooms: Stay Quiet.

The furniture revision adds three wardrobes, a rounded TV and low media console, a study bookshelf, and a two-chair terrace group. Fresh Blender/GLB/FBX exports contain 88 visual meshes, 53,128 triangles and 192 primitive collision specifications. Offline topology, UV, GLB roundtrip and analytical walking-route checks passed.

Imported the complete GLB at Stud scale 1, original scene position, scene-origin pivot, anchored, with Merge Meshes off. Studio displayed successful import. Corrected the importer yaw by 180 degrees and elevated the authored origin by one stud. `applied-setup.luau` is the exact setup used, with Studio MCP owning the undo recording. No persistent gameplay scripts were created or edited; Source/editor conflict count is zero.

The old cathedral and all 451 descendants remain intact under `ServerStorage.AeroReplacementArchive.Vesper Cathedral`. `BeforeAeroReplacement.rbxl` is the full native place saved before importing. `AeroHouse_Playable.rbxl` is the full final native place, including the archive. File hashes and cloud-save confirmation are in `import-record.json`. The final place is also copied to `Downloads/AeroHouse_20260929`.

`walk-result.json` records a real spawned R15 avatar completing 73 forward checkpoints with normal gravity, no requested jumps or teleports, and no health loss. The reverse route also passed 72 legs. `client-performance.json` contains a bounded 30-second local maximum-quality sample, including its source and limitations: about 41 render events/second at 2173×1023, p95 render interval 33.93 ms. Whole-process memory is not a house-only allocation. Mobile and multiplayer are unverified. Temporary Play callbacks were cleaned up and Play was stopped.

`verified-studio-manifest.json` was exported from authoritative Studio after the walkthrough and records exact instance paths, classes, attributes, transformations, collision/render properties and asset IDs for all 449 house instances including the root. The full native copy preserves non-script data outside that mirror. Current Studio screenshots are included. The baseplate and global lighting were retained.

Studio confirmed **Saved new changes in "Untitled Experience" to Roblox** at 21:51:08.468. This is a cloud save, not publication. The standing publishing preference names a different Backrooms place and did not authorize publishing this separate experience. No GitHub push was made. The remote history was inspected read-only; no remote baseline was applied to Studio. Unrelated repository changes were preserved.
