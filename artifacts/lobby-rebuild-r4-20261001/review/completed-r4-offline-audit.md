# Completed R4 Blender package: independent offline review

Reviewed the rebuilt `assets/models/lobby-reimagined-r4-20261001/LobbyReimaginedPreview.blend`, SHA256 `165712df68a47fe4811264f3e4801d09e5a876a4a8108a1a758b53e876c02259`, and its serialized prefab/collider/sign package using isolated Blender 5.2.0 LTS. This did not open, change or save the user's Blender scene or write to Studio.

The final package has 54 reusable families, 71 material-aware chunks, 300 placements, 830 colliders and 77 light specifications. It contains 66,872 unique / 217,804 instantiated triangles. These are authoring counts, not measured Studio performance.

## Results

- All six doorway center routes are visually open. A static 3 × 5 × 3 stud body clears the serialized wall/roof/prop colliders on all six center entrance routes. Floors and low queue podiums were excluded from that static wall-clearance test; actual Humanoid stepping remains a Studio check.
- All 72 sampled floor points cross the sidewalk, threshold, connector and bay without an open seam. Floors remain at 0.8 studs; the sidewalk's visible grout detail is 0.0245 studs higher.
- All six main signs face the tunnel exactly, with glyph centers at 18 studs above the package origin. They sit on the authored lintels rather than covering the doorway. The 12 hanging blade faces have unobstructed sightlines from 35 studs away at a 5.8 stud eye height, on both approaches. The blade face normals run along the tunnel; their arrows point toward their gate doorway.
- Both tunnel shell types and the arch rib retain the exact radial custom normals in the serialized chunks. Maximum measured radial error is below 0.065 degrees, including all six bay walls. Hard caps, jambs, lower straight walls and floor rims are deliberately excluded from the radial-normal metric. Checked shell triangles have no normal/winding disagreement. Closed gate, connector, threshold, road, sidewalk, stage, monitor and shell family geometry has positive signed volume.
- Distinct bay compositions are present: yellow office / filing furniture; pale tiled poolroom; orange party room and confetti carpet; worn cinema / red seats and posters; indoor suburb facades; semi-dirty mall party / balloons and arcade silhouettes. All preserve the original four world-aligned queue positions and 7.41 stud radius. Queue text is native runtime content and therefore absent from the Blender monitor render.

## Findings corrected during this review

1. Material partitioning initially lost smooth bay-wall normals. Root extended radial normal reconstruction to the tagged bay shells; the final exported chunk test confirms it.
2. Connector and threshold fill floors originally overlapped the sidewalk and bay surfaces at precisely the same height. Root lowered the hidden fill geometry by 0.02 / 0.01 studs while retaining safe collider heights, avoiding coplanar z-fighting.
3. Bounding-box stacking originally placed a vinyl bench on a narrow chair/backrest and visibly floated its legs. Root replaced the support sequence with broad desks, copier tops and stacked filing cabinets, keeping seating grounded. The refreshed stage close-up no longer shows that floating bench.

## Evidence and remaining runtime checks

`completed-r4-offline-audit.json` records exact source hashes, sampled floor hits, sightlines, static collision clearances, radial errors and signed volumes. `audit-completed-r4.py` reproduces those checks. `audit-dj-stage-close.png` is regenerated from the final rebuilt blend; the three bay close-ups were produced before the minor floor/support corrections and document the unchanged bay compositions.

Actual Studio import asset permissions, material appearance, native queue text, camera views, Humanoid movement, original/revised queue routing, hologram fade, vinyl animation with fixed needles, source/editor parity, multiplayer cancellation/streaming and runtime performance are outside this offline receipt. A Play test is required for those claims.

The queue source peer review separately found a final-member yielding `Runtime.Join` cancellation race. The queue author reports it fixed in Bridge v5 by validating admission and destination again after every commit return; the explicit solo final-Join cancellation test now passes. This receipt does not substitute those mocked lifecycle tests for a Studio multiplayer test.
