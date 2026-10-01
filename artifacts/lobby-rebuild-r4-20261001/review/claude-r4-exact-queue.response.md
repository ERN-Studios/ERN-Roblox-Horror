Read-only; nothing was run.

**Holds up as supplied:** pre-commit cancel is fail-closed (a closed context makes Lock/Prepare/Commit refuse, so an abandoned `EnsureWorld` cannot move anyone). World, exit, return prompt and floor are rechecked after streams and again before pivot.

**1. Commit window is not atomic** (definite race; Level 6, needs `Join` to yield)
- Observed: while `committing`, the poll loop can still close the context and return failure (cancel, death, leave). If that lands during the last member's `Join`, nothing rechecks afterwards. The cohort stays joined in Level 6 while the pad shows FAILED and locks are released, which is a ghost entry. Mid-loop, rollback hits already-released players and calls `Runtime.Leave` for members never joined.
- Fix: while committing, only set `state.active=false` and wait for `done` before finalizing. Revalidate cohort and `ready()` after the last `commit`, and call `Leave` only for attempted joins.

**2. Cancel/epoch wiring not shown** (definite if absent)
- Observed: the bridge reads `station.cancelRequested` and `admissionEpoch`, but no supplied GameManager hunk sets, bumps or clears either. The cancel hunk only lets the legacy leave-queue body run while `busy` and outside config, states it never ran in.
- Fix: on busy preview cancel, set the flag, bump the epoch and return. Clear the flag when preview `launchStation` starts, and do the legacy reset after the bridge returns.

**3. Abandoned preparation is per-pad; the world is per-level** (definite gap, theoretical harm)
- Observed: after a cancel, that pad rejects everyone for up to 1260 s with nothing on it saying why. Sibling pads can still call `EnsureWorld` concurrently.
- Fix: confirm `EnsureWorld` is single-flight, and expose a "preparing" state for the pad display.

**4. Lock release fragility** (theoretical)
- Observed: `pcall(finalize)` swallows errors. If `release` throws or doesn't rewrite `nextUse`, `math.huge` persists and the player is locked out of the queue and original E. Acquisition checks only `nextUse`/`queueLocks`, not an original-E in-flight nonce.
- Fix: per-player pcall with warn, write a finite `nextUse` before `release`, and pass an `isPending(player)` predicate into `LockPreviewController`.

**5. Unshown contracts to verify first** (theoretical)
- `stream`/`streamReady` must return literal `true`.
- `readyPlayer`/`playerReady` must hold the allowlist (4/5 commit is `return true`), have no door-reach test, and not reject `Level6InRound` (polled after `Join`).
- `hookExit`, `release` etc. must be declared above the inserted blocks; compiling won't catch nil globals.
- An unwrapped `RegisterPreviewLauncher` assert aborts the controller before `hookDoor()`; wrap it in pcall.
- `launchStation` may now block ~1400 s; if its caller isn't spawned per station, pads 1–3 stall.

**Verdict:** not ready as supplied. Only item 1 is definite on the text given; 2 is definite if the unshown lines don't write those fields; 3–5 are theoretical. Fix 1, wire or confirm 2, and run the item 5 checks. Studio Play is then the right next step, run as a multi-client local server, since solo Play cannot exercise cohort slots, locks or cancel races. Mobile and multiplayer stay unverified.
