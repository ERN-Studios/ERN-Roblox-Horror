# Level 3 protection integration — prepared source only

Prepared against the accepted navigation Manager **173969 bytes / e1332968cf1cd4e5e216381d5d6b5ed5492734213845c66151f6c33c455b2884**. The exact Manager and Hiding baselines are saved under `before/` and in `baseline-sha256.json`. Runtime and Studio remain unchanged. `proposed/` contains the two complete modules; the adjacent `.diff` files contain only the protection changes.

Both modules require the existing reviewed server module `ServerScriptService.PlayerProtection`. No client attribute authorizes targeting or damage. The integration adds no price handling, inventory, timer, navigation algorithm or additional effect service.

Manager's common participant predicate and independent spawn grouping exclude the exact protected character. Vision, hearing, nearest-player blackout/finale pursuit and impact confirmation reuse this predicate. The four existing player-derived memory writes now retain player and character identity, including the initial hunt seed; independent CD noise explicitly clears that identity. One existing-session connection and a defensive check before the table-check early return remove only the protected player's target, suspicion, memory, attack token and owned route. A delayed impact also verifies the original character and original Humanoid before capture feedback or Health=0. Cancelled attacks cannot resume when protection expires.

Hiding keeps its normal eligibility, occupancy, capacity, hidden state, voluntary exit and full restoration path. Its two occupancy queries accept an optional AI-only `excludeProtected` argument. Flush checks each current authoritative hiding record before changing its exit position or immunity: a mixed table releases only its unprotected occupant. A protected-only table cannot be selected, and an ongoing warning with no eligible occupants is cancelled. Normal cleanup still releases everyone.

`test_level3_protection.py` executes the actual reviewed private protection service plus actual proposed Manager/Hiding functions in a deterministic host. **119 checks pass**, covering:

- Private 5.00-second expiry and forged display attributes; vision/hearing/nearest/spawn selection with two participants.
- Visible/heard/blackout/initial-seed memory, targetless search cancellation, teammate pursuit and independent CD noise.
- Normal capture and protection before/during windup, deferred activation, independent impact guard, replacement character/Humanoid, stopped session and expiry after cancellation.
- Mixed and protected-only table occupancy, actual flush and movement/collision restoration, targeted/untargeted warnings, voluntary exit and round cleanup.

Four deliberately broken versions fail their expected behavioral assertion: removed acquisition gate, removed impact identity fence, unfiltered mixed flush, and retained memory from the same player’s retired avatar. Both full proposed modules compile with Luau 0.737. The host controls sensory line visibility, navigation destinations and geometry rather than retesting the separately accepted navigation implementation. Native rendered behavior, actual scheduler ordering, complete hunt bootstrap, real multi-client hiding and UI/transaction integration are not certified by this host.

No changes are proposed to Objective, Music or Round Adapter. Protected players can keep using CD and exit interactions through their existing eligibility paths; escape invalidates protection through the shared service. At integration, root must install the already reviewed service before either consumer, merge only these diffs if navigation changes, run the combined feature checks and perform bounded native activation/expiry and mixed-occupant validation. No publication is claimed here.

An additional replacement-life fixture found that retaining only exact old-character memory could restart tracking after the new avatar activated protection. Cancellation now removes all memory owned by that Player, including a retired avatar; the activation itself still requires private protection on the current exact character. Both immediate and deferred delivery cases pass. Impact retains its original character and Humanoid fences.

Independent critic re-review: **9/10** for Manager `b8befd31131e49fb37dc5812906be5378ad90e6c6433f5d884c75d1f114b2f2d` and Hiding `5eae5ad31bbfd20570fb3908e1fc04f9727a73a1cd78c177244168ba13e8d232`. The critic independently reran all119 checks, four negative controls, both complete compiles and runtime parity. See `independent-review.md`; native scheduler/cleanup and combined integration remain pending.
