# Store and seven-control layout review

Artifact-only review and corrections. Store and UIDevice runtime bytes still match
their exact saved baselines. Both preparation scripts now refuse a changed runtime
baseline before regenerating, preserving the original copies for later merging.

The Store proposal passes **178 actual-source checks**: real card construction,
measured layout hook, SetEnabled and complete shared ProtectionClient execute in
the host. The card costs five tokens, displays charge count, refuses four tokens,
stays outside Marketplace purchase/price lookup, preserves pending identity, and
can retry an unknown HUD use without converting it into another buy. Seven cards
participate in the existing scroll/layout contract. At six content widths, the
actual stacking arithmetic keeps copy and the 44px action apart. Text measurements
are deterministic host values; native glyph fitting is still required.

Independent Store code review: **9/10**, with no necessary Store implementation
correction found. The change to its preparation script protects the baseline only.

The initial seventh UIDevice slot introduced one reproduced small-viewport
regression. At **568×270 with a 58px topbar**, the old six controls fit one row. The
seventh required two rows, whose width-driven 56px cells left too little objective
space. Selection fell back to a column, putting SNEAK at **y28 above safeTop58**.

The correction makes row sizing account for available height as well as width.
That fixture now uses **51px cells and 56px objective headroom**, retaining the
44px minimum. The six existing column slots keep their exact sizes/positions.
The independent critic read the diff, repeated all tests and assigned **9/10**.

`test_device_slots.py` passes **1,151 checks across 18 fixtures**, executing the
actual column/row functions and plan-selection code. It checks seven slots,
44px targets, safe bounds, no pairwise slot overlap, landscape thumbstick
clearance, objective headroom and empty control zones during modals. Normal small
phone/tablet orientations, asymmetric cutouts and translated origins are included,
alongside the deliberately short regression fixtures. They are geometry fixtures,
not claims about a physical device. Both complete Store and UIDevice files compile.

Commands:

```text
python artifacts/trello-20260909/protection-prepared/client/test_store_card.py
python artifacts/trello-20260909/protection-prepared/client/test_device_slots.py
```

Native rendering, all seven actual registered rectangles, text bounds, modal
transitions and mouse/touch/controller input remain root acceptance work. No
runtime source, Studio instance, DataStore, account purchase or publish was changed.
Exact hashes and totals are in `store-device-validation.json`.

Root then authorized a separate two-line regression inventory update:
`UIRegression.proposed.lua` adds `ProtectionUse` to the existing
`MOVEMENT_CONTROLS` and QueueModalMatrix `expectedControlKeys` tables. The new
control receives the same classification as its six peers; it remains subject
to onscreen, target-size and pairwise overlap checks. **30 actual-table checks**
pass and the complete module compiles (271 KB). All other regression source is
unchanged. `prepare_regression.py` preserves/guards the exact runtime baseline;
`test_regression_controls.py` checks the inventories and unchanged remainder.

The independent critic repeated all 30 inventory checks, read the exact two-line
diff and verified unchanged runtime hashes: **9/10** for this bounded artifact.
