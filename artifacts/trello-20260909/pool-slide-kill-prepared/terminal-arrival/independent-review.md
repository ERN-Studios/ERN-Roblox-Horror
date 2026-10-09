# Independent terminal-arrival review

**9/10 for the prepared code. No blocking finding. Ready for the targeted native corner retest; this is not final feature acceptance.**

Verified frozen sources:

- Navigator: `24507756188f5bd0bf80a94570222b3b77542d1ed44831223d4a88c819e26bd8`.
- Controller: `a9c53bf7c95e7d81b08998c0fcfdfe41c9722801712ca30d5c92ea47c91debd0`.

I read the complete narrow deltas, preparation script and actual-source host and independently reran **61 terminal/placement/tuning checks, 219 combat/Shield checks, five specific negative controls and four whole-file compiles**. The before/after source inverses pass and the runtime hashes remained unchanged during this review's test run.

The optional GoalArrivalDistance inherits the validated waypoint tolerance and is clamped to a positive value no wider than that tolerance. Pool Slide opts into 0.2. Last-waypoint consumption, final reached distance and the nonstable no-waypoint branch use the same final tolerance. Intermediate waypoints retain 1.4; the existing Goal-versus-InstalledGoal identity comparison and vertical gate are unchanged. Attack reach remains 10.5, with the existing windup, facing, LOS, Shield and target-lifecycle gates.

The regression uses the actual recorded failed foot and final waypoint. The actual Step continues beyond the previous early stop, passes through the unchanged full placement code and reaches attack distance. Each travel piece remains bounded by 0.6. Independently rejected floor, body-box and sweep callbacks produce no movement or false arrival. Legacy/default callers, stale and vertically departed goals, blocked-clearance waiting and destroyed/unparented models remain covered. Removing final consumption, reached-state correction or sweep protection causes the expected specific failures.

Floor and collision callbacks are controlled host fixtures; this is not a replacement for native physics. The recorded corner's terminal point is about 10.0 studs from the tester, so its conditional terminal-plus-tolerance bound is 10.2. Native retest must confirm that the actual follower reaches the attack window and that dodge/counterplay and normal cleanup behave correctly. Keep the prior native 11.165-stud ARRIVED failure as historical evidence. Do not infer coverage of arbitrarily blocked goals or enlarge melee range from this review.
