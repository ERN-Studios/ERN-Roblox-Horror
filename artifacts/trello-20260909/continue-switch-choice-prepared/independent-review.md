# Independent prepared-code review — 9/10

Card [rLDqjpE4 / #65](https://trello.com/c/rLDqjpE4), reviewed 10 September 2026. **The concrete issue from the initial 7/10 review is resolved. No remaining necessary code correction found.** This approval covers the prepared change; its own native input/transition acceptance and publication remain pending.

| Prepared source | SHA-256 |
| --- | --- |
| GameManager | `3d1b05993778f7640dcea4b51193cfe2cee0224552e8303bfd3dde991933d7db` |
| RoundUI after the final compact correction | `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3` |
| UIRegression | `f2b4699c37ecd54eb98deda4d28fd42b07f3aa3cfb8bb27166432a8a77af3ae4` |

I read the full source deltas, actual Routing decision/partition/cohort methods and unchanged final transport branch. I independently reran **76 server checks, 32 client checks, 19 actual CompletionContract checks, three targeted negatives and four whole compiles**. Separately, I verified all three proposed hashes, forward transformations and exact whole-input inverses, plus the composition over RoundUI `7321e76d…28f5`.

The proposal makes choices provisional until the original 15-second deadline, including solo/all-chosen cases. The server owns membership, level, serial, departure/transfer claims and time; changed choices use existing ClearDecision/RecordDecision without yielding. No early transfer remains in either input handler. The local throttle is supplementary. UI labels and the visible roster reflect accepted server state, not optimistic travel, and closure/deadline cannot be reopened by a newer open snapshot. Noncompact and compact roster layout, original composition, automatic defaults and final transport logic are preserved.

## Resolved finding

My original actual-source reproduction set A.Parent=nil after A chose Continue, delayed its removal callback until after settlement and observed an incorrect cohort of 2. The new synchronous presence reconciliation runs before Closed publication, partition and final cohort creation. It clears only absent members without an owning transfer claim; the existing Routing methods also refuse to alter departed members.

The permanent delayed-callback test now yields only B and cohort 1; removing the fence fails the named assertion. I also reran my separately saved reproduction with only the final actual server code substituted: it now prints `DEFERRED_DEPARTURE cohort=1 continuing=1` and passes. Accepted departed cohort preservation passes. The original failing artifact and initial review remain as history; no native engine ordering is inferred from this controlled test.

The added UIRegression delta is limited to its CompletionContract: replace the obsolete first-click locking assertion with Continue → Lobby → Continue in the same window. The actual contract host verifies all three dispatched commands use the same session serial. This is a relevant contract update for the new requirement, not an unrelated Testing-card task.

## Handoff boundary

Use the compact-composed UI output, not the earlier UI proposal. The GM input remains the earlier `3615b6…` checkpoint; preserve later slide/circle/ESP/dev-respawn changes through the provided narrow composition and rerun the source-override tests. These complete proposal files are not permission to overwrite an unrelated newer checkpoint.

The previous Continue release v1861 is valid evidence for its base layout and original native flows, but it does not certify this new switching behavior. Root's bounded next native pass should demonstrate both switch directions before the same deadline, another real client seeing the latest choice, no early loading, and final partition/cleanup using the last accepted selections. The Studio mixed-party fallback remains a local-session fallback and is not evidence of a real cross-server split or live Teleport retry. No new exhaustive physical matrix is required by this code review.

No runtime, Studio, UI, Teleport or Trello mutation was performed by this review.
