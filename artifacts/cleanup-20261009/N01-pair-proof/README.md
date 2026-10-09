# Historical N01 pair and touch inputs

These five files are exact archival copies of the task's original local probe
inputs. They are historical QA sources, not an authoritative runtime or
deployment baseline. `index.json` records raw/LF byte counts, hashes, original
local paths and the matching historical receipt for each executed probe.
Scoped Git attributes preserve archive/index bytes across Windows checkouts.

Four source hashes match saved native receipts. The exact
`touch-probe-current` source has no saved native probeSha256 receipt; it is
preserved as an input only. This archive does not create a native pass for it.
Before/current comparisons used the same current gameplay owner and therefore
do not establish a complete runtime-before/after-place comparison. Actual
gameplay, hardware, multiplayer and streaming limitations remain those recorded
in the original N01 results.

Read-only offline verification:

`python artifacts/cleanup-20261009/verify_N01_pair_proofs.py --compiler <luau-compile-0.737>`

This verifies all five pinned inputs and four receipt hashes, rejects altered
inputs in an OS-temp copy, parses the Python tool, and compiles each full probe
and its actual generated wrapper. It makes no Studio call, writes no production
source or manifest, and does not regenerate any historical receipt.

`run_N01_pair_probe.py` now loads only the portable hash-guarded inputs. Its
native main is a separate, explicitly authorized workflow: it stages a new
ModuleScript, requires historical QA code, borrows live client context and
produces a new receipt. Do not run it against an owner's active Play session or
interrupt that session without explicit authorization. Before future native use,
review the current source/editor baselines, probe lifecycle and borrowed-state
restoration against AGENTS.md, and use a controlled test session. This archive
repair performed no native replay and does not certify all wrapper error paths.

Historical receipt names are protected. A later authorized replay must choose
a separate unused `--receipt-label`; output uses exclusive creation, and raw
results are checkpointed before any receipt-name collision can fail. Existing
receipts and original `.git` inputs are not rewritten by the offline port.
