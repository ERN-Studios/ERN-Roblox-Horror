# Current DEV gallery: ten-section Studio Edit capture, 2026-09-27

This is a visual QA record for the live Studio gallery source after commit `7a41ccb`. Place `131311258779917` was in Edit mode. Before the isolated build, `ScriptEditorService:GetEditorSource` equalled `Source` on the three live `Level 5 Systems` modules. Exact clones of those modules were put in a tagged temporary `ServerStorage` folder, and the cloned `Level 5 Rework Gallery` built one tagged temporary `Workspace` model at `(77000, 24, 0)`. Cloning matters: an initial build through the already-required Edit module reused a stale `require` cache and produced **8,515 descendants and zero textures**. The fresh clone produced the source-expected **8,526 descendants and 11 candidate `Texture` children**. Counts by section were `1,738 / 348 / 1,095 / 1,195 / 918 / 955 / 340 / 634 / 1,102 / 139`.

All ten captures were taken from each section's stored primary camera position and look vector in the 1677 × 1080 Studio Edit viewport:

| Section | Current gallery capture | First visual blocker |
| --- | --- | --- |
| 01 | [courtyard](gallery-current-ref01.jpg) | Modern flat end grid, broad straight path and cloned porch houses. |
| 02 | [corridor](gallery-current-ref02.jpg) | Near-left composition misses the tall open doorway; the right side reads blank, and cool wall/lighting persists. Candidate carpet renders as long linear stripes rather than alternating ribbed square tiles. |
| 03 | [bright atrium](gallery-current-ref03.jpg) | Blue sky wedges and a rectangular glass tower replace the enclosed, rounded and densely layered reference. |
| 04 | [misty canyon](gallery-current-ref04.jpg) | Equal gabled fronts, broad regular balcony wall and visibly planar haze miss the narrow layered vertical shafts. |
| 05 | [inclined houses](gallery-current-ref05.jpg) | Straight green ramp/white stripe, boxy tilted houses and flat tower walls miss the dominant rounded tower/incline silhouette. |
| 06 | [gabled lawn](gallery-current-ref06.jpg) | Near right wall is mostly bare porch rhythm and the black void is a distant flat rectangle. |
| 07 | [stair cutaway](gallery-current-ref07.jpg) | Frontal stair close-up, brown block treads and straight severed wall columns miss the oblique ripped-open room stack. |
| 08 | [upper walkway](gallery-current-ref08.jpg) | View is handed opposite the reference: the drop is on the left instead of the right. Blank far wall, strip galleries, tiny apartment fronts and dominant ceiling remain. |
| 09 | [skybridge canyon](gallery-current-ref09.jpg) | Continuous dark bands, light blue exposure and tiny identical cottages weaken the dark monumental reference. |
| 10 | [empty rooms](gallery-current-ref10.jpg) | Camera begins inside the room rather than inside the thick white entry portal; left windows collapse to one blue pane and the center door appears small. |

The screenshot tool used the current Studio viewport field of view; it did not set the builders' requested per-section FOVs. The originals are portrait attachments in the conversation, not local files. These captures are therefore qualitative camera-position evidence, **not** aligned or pixel-accurate comparisons. They do not test playable collision, round Lighting, multiplayer, non-DEV access, the seven gates or publication. See the separate [facade](facade-gap-audit-2026-09-27.md) and [anomaly](anomaly-gap-audit-2026-09-27.md) audits for source-level priorities. All ten sections still fail strict 1:1 acceptance.

A separate read-only live Studio check found `Source == GetEditorSource` for `ReplicatedStorage.DevAccess`, `ServerScriptService.Level5PreviewAccess`, and `ServerScriptService.Level6PreviewAccess`. The shared `DevAccess.IsAllowed` returned true for the two configured numeric developer IDs and false for `0` and a string version of an allowed ID. Level 5's preview script is enabled and uses this same server gate; Level 6's preview script was disabled in the observed Edit place. This is a whitelist/source check, **not** a non-developer Play test.

After capture, the temporary root's owner token, ten section children, remote position and **8,526** descendants, and the temporary module folder's owner token and three exact children were checked. Only those two tagged QA objects were destroyed. Studio returned `rootPresent=false` and `folderPresent=false`; the live systems, playable Architecture and active round were not edited by this capture.
