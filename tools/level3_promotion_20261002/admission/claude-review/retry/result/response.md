**Verdict: uncertain.** No proven blocker; kit wait precedes the fresh 60s Begin on all three paths. Static reading only; reported tests not re-run.

**Depends on unreviewed code**
- **Reserved warm ignores departures.** A member leaving mid-wait leaves the rest waiting out the bake before full-cohort staging rejects. Fix: add departure evidence to `warmAllowed`.
- **Nil owner token.** At reserved boot `entryOwner` is nil, so a `failedReservedEntry` cancel calls recovery, possibly twice. Fix: compare a generation counter bumped by Begin and recover.
- **Unconditional station cleanup.** After an epoch-change cancel, the stale thread clears `kitWarming`/`busy` and fires `lobbycancel` over any newer admission. Fix: release only if `admissionEpoch == epoch`; confirm `cancelRequested` resets.
- **L3-only session pin.** A non-L3 target that later stages as Level 3 skips the kit wait. Fix: abandon that case.

**Direct from helper**
- **Latched failure.** One `Ensure()` error fails every later Level 3 request on that server, despite "TRY AGAIN". Fix: bounded retry.
- `Level3KitError` replicates raw server error text to clients; publish a code instead.

**Unverified:** MemoryStore cohort expiry must outlast the ~1300s worst case.
