# Geometry preparation, 2026-10-09

**Prepared and tested offline; no Studio geometry or property edits have been applied.** The owner asked to retain the current Play session. Do not stop it, mutate Studio, or publish this preparation while that instruction is active.

## Observations from the live Edit model before Play began

- `ServerStorage.Level2PoolroomsMap` is the current Poolrooms template. `Collision` has 23,475 descendants: 23,474 Parts and one Guards Model.
- There are 22,316 anonymous `Collision.Part` instances, with Anchored=true, Transparency=1, CanCollide=true, CanTouch=false, CanQuery=true, CollisionGroup=Default.
- Named Hazard, Guard, Barrier, Veil and A2ReflectorCollider objects have distinct contracts. None are eligible for the preparation's reduction.
- A read-only interval grouping experiment found 22,020 anonymous block candidates: 11,033 exactly axis aligned and 10,987 oriented. It found 1,395 connected interval groups with 1,518 nominal reductions, before accounting for candidate reuse across axes. **These are not an approved merge count.** New merged box dimensions could round floating point boundaries at the map's roughly 70,000-stud coordinates. The tool therefore does not implement those interval merges.
- `ServerStorage.Level 6 Indoor Playground` is the current parked Level 6 model, identity `1_41645` in that Studio session. Its 6,605 Precise unions are entirely in `Frame_DeckPads` (3,152), `Frame_Decks` (897), and `Frame_DecksDeep` (2,556). The DeckPads are noncolliding/nonquerying; the two deck groups retain their physical/query geometry.
- Sampled unions have CollisionFidelity=Hull, SmoothPlastic material and existing `L6PBR` attributes. The proposed change only sets RenderFidelity=Automatic; it does not change collision, material routes, textures, CFrames, sizes or authoring assets.

These observations are inspection evidence, not a write baseline. `Geometry.Prepare()` must reread authoritative Edit instances and Source/editor pairs after the owner releases the Play hold. The exact number of contained redundant colliders is **unknown**: that read was rejected when Studio entered Play. No guessed count is used by Apply.

## Reduction policy

`GeometryOptimization.luau` exposes a root-operated utility. Loading it does not mutate the DataModel. Its smallest conservative collision reduction archives only an anonymous transparent rectangular collider whose entire occupied volume is already contained in one existing collider with exactly matching physical/query/Area properties. The survivor remains unchanged. Archival preserves the original object and all its properties in `ServerStorage.PoolroomsContainedColliders_20261009`.

The algorithm uses exact signed-permutation rotations and double arithmetic for interval endpoints. It does not use epsilon tolerances, approximate rotated shapes, resize boxes, fill gaps, simplify stairs, or modify cylinders, slides, guard barriers, kill zones, water, markers or the reflector. Each removal has an explicit unchanged survivor. This gives mathematical equality of the occupied union of these rectangular colliders; native physics/query and gameplay behavior still need verification.

Identity-sensitive instances are excluded when explicitly referenced by ObjectValues, JointInstances, WeldConstraints, NoCollisionConstraints, Model.PrimaryPart, UI/Adornment/Highlight.Adornee or Camera.CameraSubject. Sources and editor sources of all executable scripts outside ServerStorage are pinned, including dynamically computed lookups that a literal grep would miss. New/changed sources and explicit references are rescanned before and after Apply. Scoped property snapshots are compared immediately before each write, without a yield between the check and that write.

## Root operation after the Play hold is released

1. Inspect repository status/remote history; preserve a recoverable dirty/diverged checkout checkpoint. Confirm the live place and that Studio is in Edit.
2. Save and verify a full native place backup. Retain that concrete path and receipt. A source mirror does not contain union geometry, terrain or visual assets.
3. Stage this utility in a **fresh** `Instance.new("ModuleScript")` with a verified empty Source/editor baseline, using the root's guarded ScriptEditorService workflow. Never stage through a cloned LuaSourceContainer. Verify authoritative original scripts both during staging and after success/failure.
4. Call `Geometry.Prepare()`, review `Geometry.Summary(plan)`, and persist all `Geometry.Manifest(plan, index, 250)` pages. Every page includes exact original paths, classes, debug identities, parent identities, properties, attributes, tags and full fingerprints; collision rows also include the unchanged survivor and occupied bounds. Compute SHA-256 of serialized baseline files locally if desired. Preserve `plan.Sources` Source/editor evidence through the root's verified exporter.
5. Review live sources for collision identity assumptions. Current inspected Poolrooms Runtime performs floor raycasts with the Collision model as the include filter, reads hazards by Name=Hazard plus KillZone=true, and specially changes named Guards.Barrier during slide preparation. Those objects remain untouched. Treat new conflicting source as a blocker, never as permission to apply older repository code.
6. Apply only the reviewed plan via `Geometry.Apply(plan, verifiedNativeBackupReceipt)`. It is gated to Edit, place `131311258779917`, universe `10559217407`, and an unused archive name. Archive writes batch at 250 objects; LOD writes batch at 500. A stale baseline or failure triggers rollback, preserving concurrent unrelated property/source edits. Cleanup leaves the empty task-created archive receipt rather than deleting authoritative objects.
7. Run `Geometry.Verify(plan)`. Its result distinguishes exact static containment checks from native gameplay and performance. Save the fresh post-apply state and native backup. Then run actual map/round probes and visual/performance checks below before publishing.

If fewer or no redundant colliders qualify, report that actual count. Do not broaden the scope silently to approximate all 23,000 colliders. The fuller Poolrooms reduction needs authoring/topology-specific work with a fresh export and gameplay verification.

## Verification still required in Studio

- Native before/after raycasts and overlap queries on actual colliders, comparing hit positions/normals and Area semantics rather than anonymous Part identity. Include every marker's floor, passage thresholds, staircase landings and slide exit/runout; preserve six kill zones, Guards/Barrier contracts, collision group flags and the reflector collider.
- Actual Level 2 traversal through all six areas, side passages, water/cascade stair route, slide and safe spawn/runout. Recheck the repository's owner-required living-participant safe distance/second pump/third pump behavior where those entity systems are applicable. Synthetic box contracts do not satisfy that requirement.
- Actual Level 6 native visuals from close and distant views on every platform and deck seam. Inspect for LOD silhouette/occlusion/padding artifacts. Automatic rendering leaves native collision unchanged, but a close-geometry expectation must still be visually checked.
- Measure server CPU/memory and query/navigation/retry behavior under an active round, client frame time/triangles/draw calls/graphics memory at consistent camera positions and graphics settings, and reset cleanup. Test streaming/teleport and multiplayer separately. No FPS, RAM, server CPU or gameplay improvement has yet been measured.
- Resolve any material blocker before publication. Commit task-owned verified mirror/manifests/test records after reviewing the exact staged diff, and distinguish the commit from a GitHub push and Roblox publish.

## Offline verification

Run:

```powershell
python tools/optimization_20261009/geometry/test_geometry_preparation.py
```

The runner executes the actual utility in official portable Luau 0.741 against synthetic fixtures. It currently verifies 36 contracts, including containment/duplicate occupancy, signed permutation rotations, tiny-gap preservation, exclusion of identity/Area/hazard/physical differences, stale Source/editor/property/root-attribute/folder refusal, a newly inserted source during a yielding scan, temporary subscription cleanup, explicit Play refusal, partial-write exception rollback, and preservation of unrelated concurrent property edits. These tests are not a native gameplay, streaming, multiplayer or actual-asset performance pass.

Roblox explicitly recommends reducing excessive Precise render fidelity through Automatic/Performance and reusing underlying asset identities for instancing. Reusing geometry with different appearances, collision hulls or UVs cannot be inferred from equal names/bounding boxes; this preparation does not replace an asset ID without content identity proof. Sources: [RenderFidelity](https://create.roblox.com/docs/reference/engine/enums/RenderFidelity), [Improve performance](https://create.roblox.com/docs/performance-optimization/improve).
