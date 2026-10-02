**PASS FOR ACTUAL PLAY** — static review of the supplied fragment only; SHA, compile and runtime are unverified.

**Observed in the code**
- The moved block runs only when `contains()` is true, which already excludes `InRound` and `Level6InRound`, so participants reach the Level 3/2 guards unchanged.
- The Level 4 guard still returns first; the Level 6 guard can never coincide with `inRevisedLobby`.
- A non-participant inside R4 now applies and returns before the global `SelectedLevel` guards, closing the reported stand-down. Given that Level 2/3 controllers need local `InRound` (your stated fact), they will not contest that client's Lighting.
- The `restore()` calls remaining in the Level 3/2 guards are now redundant but idempotent.

**Non-blocking, suggested mock cases**
- A returning Level 2 participant whose first R4 tick precedes the controller's atmosphere restore: `apply()` could save Level 2's density over the pending value. That race predates this change; the new order is no worse.
- Walking out of R4 while another party holds Level 2/3 leaves R4 night values behind under the old stand-down. Pre-existing, now reachable more often, and outside this scope.
