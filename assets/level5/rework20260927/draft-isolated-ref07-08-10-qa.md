# Isolated Studio visual QA: references 7, 8 and 10

Captured in Roblox Studio Edit on 2026-09-27 with the local `qa-test-kit.luau` and a tagged `_L5VisualQA_TEMP` model at X/Z = 75,000. The test used each builder's first `PreviewCameras` position and aim. The Studio camera's 70° field of view was read and left unchanged; these builders provide no FOV setting. The images show isolated draft geometry under the current Edit lighting, not the final integrated level.

| Ref | Draft source SHA-256 | Descendants, including temporary root | Capture | Visual result |
| --- | --- | ---: | --- | --- |
| 7 | `b959771f783e1c1b28d2a457ed002b929e593ea58fe06a37c520a3f2674f305b` | 310 | [draft-isolated-ref07.jpg](draft-isolated-ref07.jpg) | The stacked stair silhouette reads, but large blue-sky gaps, rectangular cut edges, plain rod railings, gray walls and exposed block treads miss the warm beige, carpeted torn stairwell and turned balusters of the reference. |
| 8 | `2ab0c39ec55bd940d9b6228b5db32539f1fe4925f023de6048f06c71fad4643b` | 576 | [draft-isolated-ref08.jpg](draft-isolated-ref08.jpg) | A vast, mostly empty upper plane and small central void dominate. The reference has close cream apartment fronts, windows and projecting balconies, with denser stair/landing detail across a deep drop. The current view's scale and camera composition are wrong. |
| 10 | `2ab0c39ec55bd940d9b6228b5db32539f1fe4925f023de6048f06c71fad4643b` | 131 | [draft-isolated-ref10.jpg](draft-isolated-ref10.jpg) | The central door is distant and the visible windows are on the right. The reference starts at a near, broad white-trimmed opening; its interior-facing balcony windows appear on the left. Ceiling, room depth and floor/wall palette also differ. |

The source changed between captures only in the section 6 and 9 builders; sections 7, 8 and 10 were not edited in that pass. All three builds returned successfully. Before each cleanup, the model tag, source hash, section ID, exact one-child name, descendant count and remote part position were verified; each temporary root was destroyed. The final `_L5VisualQA_TEMP` lookup returned absent.

## Correction priority

1. **Reference 10:** Reorient the room composition so the wide foreground trim frames the shot and the balcony windows read on the left; pull the central six-panel door nearer. Keep the intentionally sparse room.
2. **Reference 8:** Rework the camera/scale first so a cream apartment wall and broad carpeted walkway fill the foreground, the drop remains obvious, and opposite balconies/stairs stay legible. Add facade density only after that framing matches.
3. **Reference 7:** Close the unintended sky openings, shape the torn edge more naturally, and give the stair faces/carpet, baluster profiles and warm wall/ceiling palette the reference's hierarchy.

These isolated renders fail a 1:1 visual match. They do not test gameplay, collision traversal or the final round lighting.
