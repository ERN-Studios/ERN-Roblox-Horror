# Initial independent review — 7/10, one required correction

Reviewed 10 September 2026 against GameManager `bdfea44176c68c06cb3f3fecb58dce0c5be24397727a3bca9031823fb3c8475c` and the compact-composed RoundUI `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3`.

I read the complete deltas, actual routing decision/partition/cohort functions, final transport path and both hosts. The supplied 68 server and 32 client checks, two named negative controls and three whole compiles independently passed. Server authority, the unchanged deadline, provisional switching without early transfer, client accepted-state display and compact-source preservation are coherent.

## Required final-presence fence

The new design makes a Continue provisional until the deadline, but its final partition still relies exclusively on an earlier PlayerRemoving handler to clear disconnected selections. `Routing.Partition` and `ExpectedContinuers` retain a `Continuing` member even when the supplied `stillHere` predicate is false.

`independent-deferred-departure-negative.luau` reuses the generated actual-source harness and reproduces this order: A selects Continue; A.Parent becomes nil; deadline settlement runs before the removal callback; that callback runs afterwards. The actual result is `2 continuing / cohort 2` although only B remains. Settlement has already cleared `activePostWin`, so late handler delivery cannot correct either the returned cohort or the queued final snapshot.

This is a deterministic source-order reproduction, not a claim that the engine timing was reproduced in Studio. A small final reconciliation of absent, unclaimed, not-yet-departed provisional members before closure/partition is necessary. Reuse `ClearDecision` and `NoteDeparture`; preserve the established semantics of genuinely claimed/departed transfers. Add this exact delayed-handler case and a claimed/departed preservation control. No new routing service, timeout or test framework is needed.

Final prepared score and native acceptance remain pending this correction. No runtime, Studio or UI action was performed.
