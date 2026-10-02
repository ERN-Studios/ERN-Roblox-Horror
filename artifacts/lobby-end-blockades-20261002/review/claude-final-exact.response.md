## Verdict: PASS — source and measured geometry only

Applies to the three exact candidates (hashes as supplied, not recomputed) for source security, lifecycle, integration and measured geometry. Appearance, gameplay, performance, multiplayer and publication are not assessed and stay pending root's Studio Play verification. No images were reviewed.

**Material blockers:** none found.

### Verified from the supplied source
- **Scope:** The supplied Builder diff is only the stated change. EndBlockades only adds under BlenderVisuals, PreviewCollisions and PreviewLighting, and sets Tunnel Lamp `Preview Fill` to .55. New parts carry no `R3QueueId` or `R3DeveloperPreviewEntry`, so QueueBridge and the L5/L6 callbacks are unaffected. An `Add` error is caught by the existing pcall, which destroys the unpublished model.
- **PLAN vs emitter:** Every field the emitter reads exists: 179 placements (93 South, 86 NorthDJ) and 66 colliders. My recount (FilingCabinet 40, Sofa 30, Desk 47, VinylBench 28, CRTMonitor 12, Photocopier 3, WireTrolley 3, StackChair 16) gives exactly 180,840 triangles; 217,804 + 180,840 = 398,644.
- **Offsets:** `cf * source.CFrame` reproduces `bboxCenter` on sampled yaw-only, Z-roll and compound-rotation pieces, so the Euler order matches `CFrame.Angles`. Recomputed bounds match the receipt (South z −137.050 / −127.159, North z 130.247 / 136.808, crown top 34.09).
- **Colliders:** Every top equals 1 + √(33.8² − (|x| + 1.04)²); overlaps are 0.08; outer top is 8.1273.
- **Client gate:** Predicates mirror the server (L5 `IsAllowed`, L6 `IsLevel6PreviewAllowed`, so Zen gets L6 only). It fails closed on a missing or erroring DevAccess, fires no remotes and sets nothing the server reads, so it grants nothing. Reentrancy is guarded and all per-model connections are released on cleanup. The gate frame correctly inverts the header offset; the shutter is 20 × 15.6 against a 19.9 × 15.6 aperture.

### Non-blocking findings
1. **Install order:** `WaitForChild("EndBlockades")` sits after the Builder's concurrency assert. If the module is absent, `Build` yields forever, and a later resume would publish without re-checking. Install EndBlockades as a sibling ModuleScript in the same guarded write. Proposal for a later revision: hoist the require beside `Bake`.
2. **South foreground is walk-through:** All placed furniture is non-colliding, and the South foreground row sits road-side of the curtain. Pile front is z −127.159 against a blocker face at −131.5, so players can walk 4.34 studs into it (North: 1.25). Proposal if unwanted: move the South curtain forward in a re-frozen revision.
3. **Side slivers:** A 0.76-stud gap remains each side at sidewalk level between the outer column edge (33.04) and the wall (33.8), closing at Y 8.13.
4. **Receipt arithmetic:** 130.2466 − 128.4 = 1.8466, not 1.7566. Clearance is positive either way.
5. **Unenforced values:** `baseManifestSHA256`, `previewCenter`, `instances` and the lens count of 28 are never asserted. The lens long axis is fixed to world X because light hosts have no rotation.
6. **LocalScript location:** It has no teardown on its own destruction, so it must be a single copy in StarterPlayerScripts; a respawned copy would refuse its predecessor's folder and stop managing it. Its prompt suppression is currently inert: this Builder sets no `R3DeveloperPreviewEntry`.
7. **Subtitle and mounts:** The subtitle top is at lobby-local Y 20.775, 0.175 above `connectorRoofTopY`. The Status Mounts sit 0.13 behind the subtitle and 0.095 above the header host.

### Pending checks (root, Studio Play)
- Installed shell against the radius-33.8, centre-Y-1 arc; end-cap plane against the pile rear (|z| up to 137.05); DJ guard face z.
- Exactly 28 lenses, with orientation and fit against the fixture undersides.
- Walk test of both side slivers, the South foreground and the curtain behind the DJ guard.
- Shutter fit, subtitle and mount backing, and a player inside a bay when the gate mounts.
- Developer, Zen (L5 shut, L6 open) and ordinary accounts; server denial with the shutter bypassed.
- Authorized players visibly passing through another viewer's client-only shutter.
- Cost of 179 more Precise, double-sided, shadow-casting MeshParts on low-end devices.
