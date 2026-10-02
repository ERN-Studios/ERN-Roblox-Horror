**BLOCKED**, on durability rather than handoff logic. The v2 handoff traces clean against the stated contracts, including the Level 4 snapshot return. But the only copy of the pre-R4 density sits in state the supplied code doesn't show surviving; if lost, Density stays 0 in the original lobby.

**Blocking**

1. **Weak-keyed pending table.** `atmospheres` is weak-keyed by the Atmosphere, and RoundUI holds no strong reference between polls. Roblox may drop such an entry even while the Atmosphere still sits in Lighting (I can't test that here). The next `apply` then sees `saved == nil` and records 0 as the original. Fix: use a plain table; `restore` already clears every entry once unowned.

2. **Respawn can't be established.** Saved state is script-local with no teardown path. If RoundUI persists across respawn, it is clean: a missing root makes `contains` false, so restore runs within one poll. If it re-executes (the find-or-create `LobbyLocalGrade` hints it may), a reset inside R4, or a death during Level 4 with density pending, strands Density 0. Fix: confirm it doesn't reset, or keep the saved density as an Atmosphere attribute and sweep at startup, which also covers item 1.

**Traced clean**

- R4 → Level 4 → original lobby: pending survives ownership and restores on the first unowned poll, in either entry order (assuming Level 4 snapshots and takes ownership together). Returning into R4 instead keeps the saved value.
- R4 → Levels 1/3/6: density and grade restored on the first poll.
- R4 → Level 2: correct in either order, but only because Level 2 restores its startup capture. That needs no spawn inside R4 bounds.
- Bounds: R4 minimum X 120 against original lobby maximum 91 (assuming Y0..39 is centre-relative).

**Lower-risk notes**

- Replacement inside R4 is captured on the next poll. But `Parent == Lighting` drops a parked Atmosphere still at our zero, and one swapped in during Level 4 ownership has no pending entry. Restore our zero regardless of parent.
- Lighting globals are repaired only by the fall-through branch. If a Level 2/3 ownership attribute can be true for a non-participant, walking from R4 to the original lobby strands night values there. Confirm it can't.
- One-poll (0.5 s) transients after Level 4 release or leaving R4 are cosmetic.

With item 1 fixed and item 2 settled, this is SAFE FOR ACTUAL PLAY.
