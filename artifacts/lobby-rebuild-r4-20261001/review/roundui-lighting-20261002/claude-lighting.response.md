**Verdict: safe to run in Play as a test, not ready as the final pass.** Failures are client-local and session-scoped, but `Atmosphere.Density` can strand at 0, breaking the exact-baseline requirement.

**Holds up**
- Clients that never enter R4 run the old path unchanged; `restore()` returns early.
- All nine Lighting properties `apply` writes are rewritten by both normal branches, so lobby return and maze entry recover within one poll.
- Grade props are restored before every guard returns; guard priority is unchanged.

**Material risks, all on Atmosphere**

1. **Saved density dies with the script (death/respawn).** The find-or-create on `LobbyLocalGrade` suggests RoundUI re-runs, as under a ResetOnSpawn ScreenGui. Dying inside R4 then discards the table while Density is 0. The new instance records 0 as the original (respawn in R4) or never restores (respawn in the old lobby); lobby haze is gone for the session. If the script persists, respawn restores correctly, bar a brief daylight flash while the root is missing.

2. **A reparented Atmosphere is abandoned.** `restore` skips anything not parented to Lighting, then clears the table. An Atmosphere swapped out while zeroed and later returned comes back at 0 with no record.

3. **`Density == 0` is ambiguous at handoff.** R4 state stays live for up to 0.5 s after a controller takes ownership. A controller that deliberately zeroes density gets the lobby value written over it on the next poll. One that snapshots Atmosphere at takeover captures 0 and restores it later, after the table is gone. This only bites if a level controller touches Atmosphere, which the fragment doesn't show; confirm none does.

**Verify**
- **Y anchor.** The −5..45 window needs `PreviewCenter.Y` to be floor level. If it is mid-height, or Y0..39 is world space, a standing root fails the test and R4 never activates (fails safe to baseline).
- **No hysteresis.** The Z bound sits 4 studs past the tube ends. If those ends are walkable, lingering there flips ClockTime 0/14 and density every poll.

**Proposed fix for 1 and 2**
Keep the saved value on the instance instead of in script state: a client-local `R4SavedDensity` attribute set when zeroing. On any non-R4 tick, if the current Atmosphere carries it, restore if still 0 and clear it. That survives script resets and reparenting and adds no lighting writes to the baseline path.
