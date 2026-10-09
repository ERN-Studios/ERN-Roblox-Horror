# Independent review — Pool Slide melee reach

**Prepared code / diagnosis score: 9/10. No remaining code blocker found in this bounded proposal. Installation, native acceptance and publication remain pending.**

Reviewed card UmtTK3MA/#62, the complete narrow diff, preparation/inverse proof, actual Controller combat and lifecycle functions, Navigator body/arrival/terminal-route behavior, complete current Shield integration, test host and native acceptance plan. I independently reran `test_combat.py`: **219 checks, four targeted negative controls and three complete compiles passed**. Its six runtime source hashes remained unchanged.

The reviewed Controller proposal is SHA256 **`9f8b259843309d3935644737a462152c1fca54707ac035dff8a4f93b86b01d60`**, against baseline **`f3b7bdff91e751c97f64ddcd2e9efd2dacc3b3d2a26a7ead40e01885e5c48b03`**. Only `ATTACK_DISTANCE` changes from 5.5 to 10.5, with three explanatory comments. Reversing that delta restores the whole baseline after line-ending normalization. Config, Navigator, rig, animations, Foam, Shield and all other Controller behavior remain unchanged.

## Why the calibration is justified

The actual body is a world-axis 14.8-stud box, half-width 7.4. The sampled authored avatar's wall-facing collision extents give a legal side-wall foot-to-HRP gap of approximately 6.173–6.4 studs, already outside 5.5. I independently calculated the perpendicular inner-corner case as `hypot(7.4 - 1.0218505859375, 7.4 - 1.023162841796875) = 9.0191375469`. Controller tuning explicitly overrides the Navigator default with **WaypointArrivalDistance 1.4**. Adding that existing arrival allowance gives **10.4191375469**, below 10.5 by about 0.081 studs. The earlier 8.25 candidate cannot cover this corner; its mutant fails the actual combat predicate.

The host exercises actual `_bodyVolume` and `_reachedGoal` at analytically body-clear wall/corner approaches with 0, 0.7 and 1.4 arrival margins. This is relevant to actual `Step`, which consumes waypoints inside that same tolerance and then recognizes the certified approach. The host does **not** execute native PFS or `_centreRoute` to select those approaches. The real terminal route may retain a farther, body-certified point or wait at an obstacle; 10.5 is not a guarantee for arbitrary blocked paths or every avatar shape.

## Preserved attack contract

Both pre-movement and post-movement attack-start checks use the new range. The unchanged server still stops navigation, fixes facing, waits 0.5 seconds, evaluates one captured target once, and requires current round/character eligibility, XZ range, vertical -1..7, the 140-degree front arc, physical LOS from foot+Y3, and absence of private Entity Shield protection. Recovery remains 0.7 seconds, cooldown 2.4 seconds and damage 100 through `TakeDamage`. The animation marker is not the server damage trigger. No immediate health assignment or loading-protection bypass was introduced.

Actual-source tests cover early/duplicate hits, a nearby teammate, LOS before and at impact, range/arc dodges, exact range/height boundaries, stale round/generation/character, pause/Stop, and complete private Shield activation/expiry with both event and polling cancellation. The four negative controls fail specific assertions for old 5.5, insufficient 8.25, removed LOS and removed impact-facing. Raycasting, movement, Animator and ForceField behavior remain explicitly simulated; these checks are not a new native encounter.

## Required release evidence

The supplied native plan is appropriately bounded: normal queue and actual entity approach on open floor, at a side wall and at one genuine inner corner; relevant counterplay checks and normal cleanup. Use the actual Navigator foot rather than the model pivot, record the real settled approach and attack/health timing, and distinguish Foam damage and existing ForceField/Shield protection. The historical v1839 open-floor kill proves the old code could kill; it does not reproduce this new report or accept the new reach.

**10.5 also applies on open floor.** The maximum-range attack must look connected to its victim in the actual scaled animation. Numerical reach tests do not override a visibly remote hit, and a real corner still indefinitely safe due to a farther PFS endpoint would be an unresolved focused failure. This native visual/approach check is the main remaining acceptance risk. No exhaustive map sweep, unrelated level recertification or further offline framework is needed before those observations.

No Studio interaction, production mutation, Trello mutation or publication was performed for this independent review.
