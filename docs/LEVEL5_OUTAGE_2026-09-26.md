# Level 5 gate-triggered power outages

Published to existing place **131311258779917**, universe **10559217407**, as **v2129** at **2026-09-26 15:01:45 UTC**. Baseline: `668e305`. Level 5 remains a developer preview; this change adds the requested outage to the existing seven section gates.

## Player behavior

When both leaves of a section gate finish opening, one shared server schedule begins. Ceiling fixtures fail in a wave originating in the current section and moving through nearby sections, with a distinct order within each section. Standard settings include a brief dim reflash before each fixture dies. The complete cascade lasts **5 seconds**, followed by **60 full seconds of blackout** and a **1.5-second smooth recovery**.

The wave covers all 421 authored ceiling fixtures in all eight sections, including glowing panels that do not contain a Roblox Light. Original broken/off tubes remain off; dim tubes recover to their original colour/output. The client also removes Level 5 ambient/daylight fill during the blackout. Flashlights, player equipment and Watcher eyes are outside the fixture set.

`ReduceFlashing=true`, or an unloaded preference, replaces the reflash with a smooth monotonic shutdown. The same server deadlines apply. Opening another unique gate while the cycle is active extends the blackout without restarting the wave or flashing lights back on. Opening one during recovery returns to darkness and extends the hold. A new full wave begins only after the preceding cycle is fully restored.

## Implementation and ownership

Four scoped sources: new `ReplicatedStorage/Level5OutageLogic` and `Level 5 Power Outage`; existing `Level 5 Section Progression` and `Level 5 Lighting Controller`.

The server owns a single JSON schedule attribute on the current generated world and deterministic per-fixture section/order attributes. It does not change global runtime Lighting or fixture visual properties. Triggering requires an active Level 5 world and the actual gate's `FullyOpen` attribute; each gate can trigger only once per round. Both normal puzzle and developer-bypass openings use the same completion callback. No client trigger remote was added.

The existing client lighting owner composes the outage with its normal profile and caches original fixture Material/Color and Light.Enabled/Brightness. It handles streamed parts and later Light children, restores exact originals on detach, and cancels listeners/deferred work on destruction. Existing dead-tube metadata is preserved. All **187 unrelated existing scripts**, including all twelve Level 4 sources, match the fresh pretask Studio export.

## Verification and limits

- **191/191 native scripts compile**, and final Source/editor/repository bytes match. No editor conflicts, runtime world or enabled HTTP setting remained in Edit mode.
- Native keyboard input on the developer account opened gates 1, 2 and 3 and triggered the production controller. QA teleported the player to each lock; it was not a walking-route test.
- The full first cycle produced **626 client samples** across 186 initially streamed fixtures. The schedule allocated exactly 5 seconds to shutdown and 60 seconds to full darkness. All sampled ceiling Neon and enabled lights were zero during the settled blackout; ambient and brightness were zero. **Zero failures and zero original-versus-restored property mismatches** were recorded. Initially off fixtures remained unchanged.
- The second gate used reduced flashing: 201 native samples across 36 active section-2 fixtures showed **zero brightness increases** during shutdown. The third gate preserved the current start/blackout times and extended restoration from `1790434552.107086` to `1790434599.794841`, remaining dark.
- A native temporary server Script verified duplicate gate and still-closed gate rejection, with unchanged schedule. The probe was removed. An initial MCP-side require did not share the running module session, so that exploratory result was not used as authorization evidence.
- A ceiling fixture cloned on the server during blackout appeared dark on the client. This is a controlled late-arrival check, not exhaustive StreamingEnabled race coverage.
- Actual gamepad flashlight input left two non-map SpotLights enabled at brightness 1.2 and 0.3; the native viewport showed their illumination while ceiling lights stayed off.
- Holding L returned to the lobby during the extended blackout. The world was removed, ownership released, and lobby Lighting restored. Re-entry created a new normal-lit world with no schedule; the observed time was past the old cycle's restore deadline.
- The first native attempt found unsupported `Color3 * number` arithmetic. Explicit RGB scaling fixed it before the successful full-cycle rerun and publication.
- **346,385 standalone timing assertions** cover every gate/section wave, exact phase boundaries, reduced/standard behavior, malformed schedules and overlap/recovery rules. They do not substitute for native interaction tests.

The full cycle used one native Studio client. Physical mobile performance, two-account synchronization, every later gate through real input, and all streaming races were not tested. The shared seven-gate callback and all-section timing have source/pure-test coverage. Geometry, later puzzles, main entity and final slide/completion gameplay were not changed.

## Delivery records

- `artifacts/level5-outage-20260926/qa/`: final cycle, overlap/reduced/cleanup, source parity, additional native observations and independent source review.
- `artifacts/level5-outage-20260926/tests/`: portable pure timing test.
- `artifacts/level5-outage-20260926/after.rbxl`: full native backup, **9,776,013 bytes**, SHA256 `ff28e430f8a879890112e48924e6efe5c5357dbc2233bbf7dcd42c67f3bbeabd`.
- `publication-v2129.json` and `publication-log.txt`: verified native publish receipt. No active servers were restarted.
- [PR #10](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/10) and [Level 5 Trello card](https://trello.com/c/Y2xXThBN). The outage checklist item is completed with this delivery; the overall level remains In Progress for future gameplay.
