**Verdict: material fix (small) on the R4 re-entry path; nothing confirmed broken in the startup-once flow. Level 3 excerpts: uncertain, no confirmed defect.**

Scope: four supplied excerpts only; hashes not checked. Reported tests taken as stated, not re-run. Findings are source inference, not gameplay evidence.

**R4 Builder**

1. **Medium: `Module.Build`, existing-model path.** Trigger: re-entry when `PreviewCenter` is absent, the board is in neither R4 nor `ServerLobby` (mid lobby rebuild), or two lobby boards exist. Effect: the new asserts run outside the `pcall` and before `DevBayAccessGuard.Start(existing)`, which previously always ran; Build throws and the guard is not restarted. Fix: call `Start(existing)` first, then transfer under its own `pcall` and `warn`.
2. **Medium, conditional: `PreviewCenter`.** The diff reads it but adds no write, and unchanged lines between hunks were not supplied. If nothing sets it, every re-entry fails. Fix: set it in the fresh path, or fall back to `vec(Bake.GetManifest().previewCenter)`.
3. **Low: fresh path.** Any board assert destroys the whole R4 model, and startup builds once. Fix: make the transfer non-fatal, or confirm fail-closed is intended.
4. **Low, uncertain: lobby rebuild while R4 persists.** `installed` short-circuits, so a board created by the rebuild stays in `ServerLobby` (two live renderers). If the rebuild recreates the `ZyntraDonationLeaderboard` values, R4's board goes silently stale and is never swapped. Fix: when both exist, destroy R4's copy and transfer the lobby's.

**Level 3**

5. **Medium, conditional: `configureRuntimeDiscPart(part, false, …)`.** Trigger: unanchoring a clone of a disc placed without `Dynamic=true`. Effect: chunks stay anchored and unwelded, so the 0.05 carrier moves or falls without its visuals. Fix: require Dynamic placement, or set chunk `Anchored` and create welds there.
6. **Low: `setDiscVisualCFrame`.** Offsets are recomputed from live CFrames each call: allocation plus cumulative float drift if run per frame. Fix: cache offsets once per clone.

**Consistent in source**

- Given the stated unrotated panel, the transfer lands it at (190, 37.15, -795) facing +X toward X=220, with a 0.5-stud gap between board back (-33.05) and wall face (-33.55).
- Direct reparent never trips the renderer's nil-ancestry teardown, even while the model is unparented (connected clients would likely see remove/re-add).
- Rollback order (restore, then destroy) is correct; polish passes run before the transfer.
- `portal.Light` stays valid after reparenting; `unlockExit` tweens reach chunks only if `centered`'s last argument means Reactive.

**Unverified**

- Client call sites for `tryWatchKitFixture`, baseline capture and `clearKitFixtureWatchers`.
- Any non-Reactive Light-bearing diffuser: first client sync hides its chunks.
- Transparency or Size writes on disc clones; cloned collision proxies if discs are Collidable; `queryable` covers only a 0.05 cube.
- Consumers of "Mounted Revision Notice"; whether `DevBayAccessGuard.Start` touches board descendants; exact name `ServerLobby`.
- R4 occlusion, readability, replication.
