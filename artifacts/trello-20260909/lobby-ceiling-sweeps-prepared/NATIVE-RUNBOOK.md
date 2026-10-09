# Root installation and native ceiling-light checks

Prepared only; no Studio/UI/production operation was performed. The corrected controller already has independent9/10,111 actual-source checks, three negative controls and a separate64-check reproduction pass. Its final SHA is `235a26d42b0d0ee80de5768bc3da428a1296aa73f9d08967594476ae129f2198` (canonical6847 bytes).

## New-script installation caveat

This is a **new absent** LocalScript. Existing push tooling cannot create unknown scripts (`CLAUDE.md:179` and `record_pending_push.py`). Do not merely copy it into production and run record-pending; that correctly reports an unknown path.

Root's installation targets are exactly:

| Field | Value |
|---|---|
| Studio parent | StarterPlayer.StarterPlayerScripts |
| Instance name/class | LobbyCeilingSweeps / LocalScript |
| Studio manifest path | StarterPlayer.StarterPlayerScripts.LobbyCeilingSweeps |
| Repo file | StarterPlayer/StarterPlayerScripts/LobbyCeilingSweeps.LocalScript.lua |

Check absence in **both** current Studio Edit and current manifest/repo. Preserve the current manifest before mutation. Through the established scoped payload workflow, root creates exactly one LocalScript, writes the reviewed text using ScriptEditorService:UpdateSourceAsync, compiles it and reads its Source back. Only after verified exact/canonical readback may the repo copy and a new `synced` manifest item be recorded using `canonical_bytes`/`sha256_of` from `tools/studio_source_contract.py`. This is the same new-script procedure already used for Protection. `record_synced_source.py` alone also refuses unknown entries and is not a creator.

Manifest fields are the four target identifiers above plus `bytes=6847`, the reviewed SHA and `status="synced"` **only after verified landing**. Count actual script entries again: adding exactly this one source means prior script count+1 (125→126 if no intervening additions), unchanged remote count and total+1. Never reset global counts from an old manifest. Preserve the existing allowed trailing-newline entry; a newly permitted transport newline must be verified and explicitly recorded, never used to bless other drift.

The three files listed as `references` in the preparation manifest are **not installation targets**. The only current Builder reference change was the already reviewed welcome-board CFrame; `reference-drift-reviewed.json` proves its light contract unchanged. Do not install a historical Builder or Party controller.

## Small native acceptance sequence

`native-readonly.luau` takes one snapshot in either Play Client or Play Server: actual28 tagged fixtures, their positions/colors/brightness/enabled/range, Party flag and local gates/controller count. It writes nothing and does not require a module. **Ambient animation is local**, so the Client snapshot is the visual evidence; the server snapshot is an independent baseline/reference. Private active/pattern state is not guessed from these readings.

1. Fresh normal lobby with loaded ReduceFlashing=false, InRound=false and no Party. Confirm exactly one client controller and28 lamps. Capture a quiet baseline, a visible travelling highlight and return to the same quiet values. Observe a natural full six-second sweep and9–16s quiet interval. The ordinary client must not change server lamp values. Judge actual camera exposure, broad smooth movement and no road darkening; a schematic alone does not establish visual quality.
2. Cover all five spatial patterns (near→far, far→near, centre→ends, ends→centre, opposite lanes) with native views/readbacks. Prefer observing the actual random choices. If root needs a bounded deterministic fixture, use a **single Play-only copy with only the Random provider changed**. Destroy the original controller in the actual player's PlayerScripts first so its existing Destroying handler restores its owned lamp values and disconnects its work; merely disabling it is not proof of cleanup. Verify the quiet baseline before starting the one disposable replacement. Keep six-second duration, shape and normal quiet interval. A selector's NextInteger values1,1,2,3,4 yield actual patterns1,2,3,4,5 because the production selector skips the previous pattern. Record the exact fixture delta, separate these views from the natural-random timing sample, and Stop Play afterwards. Do not touch the saved StarterPlayer copy, run two controllers, shorten production timing or publish the fixture.
3. While a sweep is visible, use the actual Party button. Check Party's colors survive, the ambient sweep ceases, the ten-second Party sequence and0.9s restoration complete, then a later ambient sweep may resume after its quiet interval. Also press Party while ambient is quiet once. Capture Client and Server snapshots at matched stages. This is real coexistence evidence, **not proof of a specific network-order interleaving**; the before-flag race remains precisely covered by the independent actual-source regression.
4. Use actual Settings to enable ReduceFlashing during a sweep: local highlight restores and subsequent sweeps stay off; switch back and wait for the quiet interval before resume. The unknown/unloaded preference is already tested offline and need not be fabricated in a live profile. Existing Party accessibility behavior is unchanged by this feature.
5. Enter a normal round and return normally to the lobby. Confirm no continuing old-lobby effect and clean new-generation resumption. The read-only snapshot intentionally returns LampCount0 when the lobby is absent, rather than declaring that absence a failure. This is lifecycle coverage for the new script, not reopening the excluded Level2-spawn/loading Testing cards.

After Play, verify no deterministic copy or temporary overrides exist in Edit, compile all actual sources and run the source audit. Native evidence should identify which patterns were natural versus forced. Obtain the independent final score≥8, then root mouse-publishes this single feature separately.
