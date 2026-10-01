# Exact candidate review

All five candidates were independently read through their diffs and compiled with @lune/luau.compile. Exact hashes/byte counts are pinned in compiled-candidate-review.json. This is source and syntax review; root owns installation and actual Play acceptance.

No blocking issue was identified in these candidate diffs:

- The generator changes only Arrival H from 12 to 30; WorldBuilder's Arrival override matches. Its validator accepts the resulting positive height, and imported ceilings continue to follow room.H-.5. Width/depth and other rooms remain unchanged.
- The west opening is restored to 16×16.1, with copied reference facet/rectangle/wedge geometry and orange wall color. Adapter adds an Arrival-only Orange theme and narrowly preserves descendants of manifest.Elevator only when tagged Level6_ArrivalTube; other legacy rendering stays hidden.
- The tube model, collision metadata and slide-part attributes are namespaced Level6. No shared Level3 safety/drive/ragdoll/PlatformStand or production routing edit was copied. The new rear cap is 17×17 instead of the reference 14.8×14.8, closing reference edge slivers.
- The floor-relative spawn calculation uses the first segment's actual chord/runout plane at mouthX-6. It faces positive X. Existing Runtime exit remains the same marker plus 3.5 vertically; its join-distance and local floor validation agree with the new entry.
- PreviewAccess sends its facing event only after successful Runtime.Join. Client transport handles that trusted server notification separately from streaming ACK, waits for participation/proximity, guards generation and character, and applies camera CFrame once only when its type is Custom. Subsequent stream requests on return/re-entry supersede an outstanding callback.

The authored tube has 778 BaseParts: 672 shell/runout, 62 wear guides, 40 seals, one cap, one sign and two invisible light anchors. The cap makes total collidable parts 673 while the specifically tagged shell/runout count remains 672. It adds two light instances and no recurring task/connection.

Actual Play must still confirm the one-shot camera yaw survives later default-camera frames, mouse control stays free, standing spawn remains supported/no idle drift, forward walking clears the mouth without jumping/snags, wall/seal/imported-ceiling alignment is correct, all tube parts/sign render after adaptation, E return and re-entry work, and production Level3 remains unaffected. Floor validation should hit an owned tube collision surface from inside the bore; normalY alone does not distinguish a ceiling ray from a floor. Atomic streaming helps the complete model, but the client floor ACK alone is not an independent full-part count proof.

Root subsequently reports actual Play camera orientation persisted positive X for four seconds, normal walk-out and opposite-corridor traversal passed with health 100, and sustained side-edge walking stayed grounded. Root's actual floor probe hit the lower fiberglass shell above the runout, so the analytic runout plane is not the highest support surface. Independent saved-image assessment and exact image hashes are in independent-arrival-visual-review.json. Return/re-entry and different seeds remain root-owned acceptance until recorded.
