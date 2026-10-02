# Bounded review of two concurrent authoritative Studio changes

**No known material publication blocker was found in these exact changes. Preserve both current Studio sources.** These were made by another developer during the lobby task; this reviewer only read source/native kit data and wrote local evidence. This is a source/asset-assumption assessment, not a Level 1 gameplay or performance pass.

The exact before/after sources came from `/private/tmp/lobby-access-spawn-20261002/{before,after}/scripts.json`, with source/editor parity recorded in the native captures. Hashes and full diffs are retained beside this report.

`ServerScriptService.Level 1 Systems.MazeGenerator` changes only the Blender-preview lighting presentation: elevator brightness 1 → 1.65; sparse ceiling fixtures .7 → .85; MongoGrade brightness −.02 → .01. The existing original Level 1 path retains its previous values. The light-restoration helper now uses the selected fixture brightness. Cleanup captures the previous ColorCorrection brightness and restores it conditionally if it still equals this preview's .01 value, preserving a subsequently changed value. No lobby spawn, queue, access, round-admission or campaign-routing code changed.

`ServerScriptService.Level 1 Systems.BlenderRoomRenderer` adds a recessed fixture aperture using four cloned ceiling slab pieces per recorded fixture cell, shifts/scales the sparse fixture to that aperture, adjusts fixture casing offsets, reduces the neon lamp/cable visual tint, and removes the SurfaceAppearance only from cloned ObjectiveCable visuals. The active kit itself is not mutated. The new recess-cell table is cleared after room construction and on renderer cleanup.

The principal newly introduced failure assumptions were checked against the current live kit: all **42** `ServerStorage.Level1BlenderKitV2.Rooms` prefabs have exactly one MeshPart marked `BlenderMaterial=Ceiling`, all are **24 × .36 × 24**, and all have identity orientation relative to their room pivot. These satisfy the new missing/ambiguous-slab assertions and align the aperture with the fixture offset. MazeGenerator sets numeric `CELL` and scalar `ORIGIN` before its fixture calls, and calls Rooms afterward, so the new Fixture lookup/recording order is consistent.

Both exact after sources compiled with Lune's Luau compiler. The exact new `CeilingPieces` function was executed at cell sizes 12, 24, 36 and 48: all four pieces have positive dimensions, remain within the original slab, do not overlap, and cover exactly the ceiling area minus the intended square aperture. The native ceiling pieces inherit the noncolliding visual slab state; the authoritative map query/collision grid remains separate.

Remaining limits: the added ceiling mesh count, final light contrast, fixture recess rendering and complete Level 1 runtime have not been playtested by this lobby reviewer. This review does not attribute another developer's gameplay verification to our task. No immediate nil dependency, invalid size, syntax error or current-kit assertion failure was identified.

Current authoritative source pins:

- MazeGenerator: **86,076 bytes**, SHA-256 `5edccd07abf8e670f6459d50abac9324d74fd474a8f1e1c9cf2b38bf5c586a34`.
- BlenderRoomRenderer: **25,881 bytes**, SHA-256 `dabdd59272720c7db6c7cd52c706c2c083c2b0cd9cd06f8689c004098a355a3b`.

Evidence: `concurrent-source-diff-pins.json`, both `*.concurrent.diff` files, `concurrent-ceiling-kit-readonly.json`, `concurrent-ceiling-relative-frames.json`, and the passing `concurrent-source-review-checks.json`.
