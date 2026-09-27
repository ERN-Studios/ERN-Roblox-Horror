# Single-script compare-and-swap payloads

OUTPUT ONLY. None of these payloads has been executed in Studio.

Each numbered `.apply.luau` file targets exactly one existing script. `manifest.json` retains exact instance name components/classes, baseline and expected lengths, djb2 values, SHA-256 records and draft paths. It also lists context fragment line spans. Only changed fragments plus three context lines are serialized; GameManager's full 165 KB source is not in its install payload.

## Execution contract

Run one payload at a time through execute_luau using the currently confirmed cloud Studio instance and Edit datamodel, after the root's remaining review/QA. Studio instance IDs may change after recovery/reopening and are intentionally not baked into these scripts. A native recovery file reporting place/universe 0 is refused.

Before calling UpdateSourceAsync the payload:

1. Confirms place 131311258779917, universe 10559217407 and Edit mode.
2. Resolves unique name components and the recorded class; it creates no scripts.
3. Requires Source == GetEditorSource and the baseline byte length + djb2.
4. Finds each exact old fragment once, rejects overlap and builds new text from the current source.
5. Checks the complete result's expected byte length + djb2.

The UpdateSourceAsync callback requires its supplied old text to equal the captured current text, the instance path to still resolve to the same object, and Source to remain unchanged. It returns nil on any drift, which cancels the operation according to [Roblox's ScriptEditorService documentation](https://create.roblox.com/docs/reference/engine/classes/ScriptEditorService#UpdateSourceAsync).

Only `APPLIED_VERIFIED` means both Source and editor text equal the entire intended result. A post-write parity warning is not success: run the corresponding read-only `.verify.luau` in a new tool call. Do not normalize, retry a write against changed text, or roll back concurrent work. Re-read Studio and prepare new scoped fragments when the baseline changed.

No Instance creation, buffer staging, attributes, properties, runtime rebuild, require(), Play run, save or publication is part of an apply payload.

## Files and validation

- 01: GameManager
- 02: Level 5 Round Adapter
- 03: Window Watcher Encounters
- 04: TunnelLobbyBuilder
- 05: Level 5 Power Outage
- 06: Level 5 Section Progression — B clue lighting only

All six complete draft sources and all twelve apply/verify payloads compile at -O0. Each exact apply payload passes 15 mocked scenarios / 60 assertions: unchanged baseline, altered baseline, Source/editor conflict, callback drift and retry, source-only drift, path rename, wrong place/mode/class, ambiguous/missing path, read/update error and post-write editor/Source mismatch. Successful output equals the complete draft byte-for-byte. Totals: 90 scenarios and 360 assertions.

These tests exercise content guards and cancellation, not Studio UI or gameplay. See the individual draft validation records for feature tests.

The raw baseline remains unchanged. Local checks contain full source strings for offline test mocks; only numbered `.apply.luau` and `.verify.luau` files are intended for individual Studio calls.

## Known integration boundaries

- Lobby payload must be regenerated if the lobby agent changes its draft; compare its current draft-manifest hash with this manifest before execution.
- Native gate opening/restyling, six-script source installation, audio import and publishing are separate actions.
- Preview notices now use “Use the lobby control to return.” The visible hold chip and confirmation retain their existing behavior.
- B clue keeps title, answers and layout; only its generated SurfaceGui LightInfluence becomes .25. AlwaysOnTop remains false and no Light object is added.

