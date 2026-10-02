# Final integration follow-up

This supersedes the 15-test count and two incomplete visual details in `review-notes.md`. Final local syntax compilation passes all four candidates, and `test_scoped_algorithms.luau` passes 18 extracted-function cases with mocked dependencies. No live gameplay/physics/multiplayer/provider/performance pass is claimed.

The revised visual adapter sets `portal.VisualWall` to the separate WallRed carrier with `Reactive=true`. Public Objective now fades that carrier to transparency 1 on five-CD unlock; its reactive listeners forward the fade to every authored chunk. The original full-size wall remains the collision proxy and becomes non-collidable.

All eight revised portal frame carriers carry `Level3_HiddenExitFrame=true`. Public Lighting captures each carrier's blackout baseline and watches/synchronizes its material/color/transparency to all chunks even when it has no child light. The additional tests cover separate wall fade, all eight frame captures and local dark material synchronization.

The final ServiceDoor deliberately stays solid/closed. Fresh World Builder places its authoritative escape detector just in front of those leaves, which preserves the existing root-entry escape contract. Actual escape still requires live verification.

Final hashes are authoritative in `candidate-manifest.json` and were verified from candidate files: Lighting `52033d8e5480398a1e54fe44349c277659e0ea66d97f64e6cf826100a408061b`, Objective `5474b27128d9d48deaa5503f4e340b138a06596534d87bff0a21d695ad2f39e8`. All changed diffs and `local-verification-receipt.json` record these final bodies and 18 cases.
