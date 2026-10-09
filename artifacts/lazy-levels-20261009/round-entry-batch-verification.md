Round Entry batched preloading
=============================

Level 4 normal queue entry stayed covered and anchored with the cinema, collidable
floor, UI and controls already present. The existing loader called PreloadAsync
once for each typed carrier. A bounded native control submitted 315 actual mesh
and image carriers together, including 119 owned URI Decals: it returned in
3.032873 seconds with 331 real callbacks, zero failed callbacks, and all owned
Decals destroyed after return. That control recorded aggregate callback counts,
not every callback ID; it did not send an entry acknowledgement.

The scoped Round Entry patch batches pending carriers in one engine call per
pass. Every required key must receive an actual Success callback; missing or
failed callbacks still prevent entry. Roblox asset URI and URL aliases match
the same numeric ID. A failed additional dependency rejects the batch. Two
attempts remain the limit. Dynamic arrivals clear readiness and need a later
pass. Cancellation retains the shared owner through the engine call and owned
Decal cleanup, and stale requests cannot update entry readiness.

The exact fresh Studio source/editor baseline was captured in
`lazy-levels-baseline-v2`: Round Entry SHA-256
`a5026683f092bccc1eb106bdc1df56b42b49e18eafddbd8b1c4919010bab9bc5`.
The candidate SHA-256 is
`ff730eb9216f3376e17766ec6b19abaa68f3fa106ba91bfe558c25ef88cb7adb`.
No census, opaque-content rule, floor check, UI/control gate, acknowledgement,
deadline, or server contract was changed by this patch.

Portable offline verification after the verified Studio export:

```powershell
python artifacts/lazy-levels-20261009/test_round_entry_batch.py --mutations --luau <path-to-luau.exe>
```

The default command reads the canonical Round Entry mirror. Before promotion,
an explicit `--candidate` selects the local generated candidate. The helper
`build_round_entry_batch_candidate.py` is an optional local reconstruction from
the exact uncommitted Studio capture; neither the capture nor a generated full
source duplicate is needed by the default regression test.

The full selected source runs inside a coroutine-controlled service fixture.
124 checks and nine mutation rejections passed. They cover real-callback
contract behavior, retry limits, cancellation/drain ownership, late arrivals,
stale readiness, alias matching, and owned Decal cleanup after preparation or
engine errors. This is an offline contract result, not a native performance,
streaming, renderer, multiplayer, or gameplay pass.

Native verification must use the normal Level 4 queue, with the actual installed
source hash guarded, and observe real entry release with a living unanchored
character on the cinema's collidable floor. The per-required-key production
callback checks remain active during this run. Verify leave/unmount, neutral
doors and a second normal entry. Record any unavailable multiplayer bystander
or physical-door checks. Preserve originals through staging and cleanup; do
not force an acknowledgement or change readiness attributes to pass a probe.

`round_entry_diagnostic.py` provides census/start/batch-start/status/stop/release
phases without source or acknowledgement writes. Use a fresh session label.
`start --count 315 --budget 120` permits a bounded between-request serial pass;
`batch-start --count 315` submits the same actual typed carriers together.
Each start returns while its single engine owner may still be waiting. Stop
marks cancellation without canceling the engine call. Release is refused until
the owner and temporary carrier cleanup have drained. Deferred Destroying
notifications are observed after a scheduler step; destroyed-Parent locking is
the immediate cleanup proof. Individual phase receipts are immutable.
