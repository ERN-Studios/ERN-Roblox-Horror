# Short native capture plan — unchanged natural timing

This supplements `NATIVE-RUNBOOK.md`; it does not install or execute anything. Use the reviewed controller `235a26d42b0d0ee80de5768bc3da428a1296aa73f9d08967594476ae129f2198` and existing `native-readonly.luau` (`759a2114213e504c13335e81a76ae461aa64458f83b1b3f2942481919d7faed7`). Installation remains the separate reviewed new-script bootstrap; never install a historical Builder/Party source.

1. Start a normal lobby with exactly one `PlayerScripts.LobbyCeilingSweeps`, actual `InRound=false`, loaded `ReduceFlashing=false`, no Party and no reserved-round gate. The probe reads the 28 tagged fixtures under `Workspace.ServerLobby.TunnelLighting`, sorted by actual Z then X. Save Client and Server quiet snapshots. Only Client receives this ambient animation.
2. Keep a broad view of both ceiling rows. Observe natural sweeps, preferably in one 120–180 s bounded capture. Reuse the existing probe repeatedly on the actual Client (around 0.2–0.25 s requested spacing if root wraps its unchanged body), retaining its actual `At` times and lamp rows. Do not modify the controller's random provider, `DURATION=6`, 9–16 s waits or TICK=.05. The observer should not bind itself as another controller or write attributes/lamp properties. A sampled gap is recorded honestly; requested spacing is not guaranteed timing.
3. Save a short early/middle/late visual sequence for each observed pattern, plus quiet restoration. Classify the **visible trajectory**, not a supposed private pattern ID. One still near the middle cannot distinguish every pattern:

| Pattern in source | Actual progression to recognize |
|---|---|
| 1 | Both rows: increasing Z |
| 2 | Both rows: decreasing Z |
| 3 | Centre Z outward to both ends |
| 4 | Both Z ends inward to centre |
| 5 | Opposite directions on the two X lanes |

The normal selector excludes the immediately previous pattern, but 120–180 s does not guarantee all five. Record the ones actually seen; continue another bounded natural window only for missing patterns. Do not claim complete coverage from five arbitrary clips. The existing deterministic-copy option is a separately labelled fallback in `NATIVE-RUNBOOK.md`, not required for this natural plan.

4. During one visible sweep, use the actual orange wall Party control beyond Level 6 near the far/right end. Actual Builder path: `Workspace.ServerLobby.TunnelDetails.ZyntraDispatchConcourse.ZyntraPartyButton.PartyButton`, with `ZyntraPartyPrompt` (E, range 9, zero hold) / `ZyntraPartyClick` (range 12). Save Client/Server snapshots around Party start, restoration and later ambient return. Normal Party lasts 10 s plus .9 s restoration; the ambient controller must yield to its actual colors and then wait normally. This demonstrates coexistence, not a certified network-message ordering.
5. Use the actual terminal Settings row `PlayerGui.ZyntraStore.Terminal.TerminalContent.Settings.AccessibilityRows.ReduceFlashing.Toggle`. Capture the real preference becoming true, the local highlight restoring and no later sweep while true. Restore the user's original preference through the same UI when done. No synthetic nil preference is needed. Complete one normal lobby→round→lobby lifecycle and read the probe again; lamp absence during a round is a state observation, not itself a cleanup failure.

Interpretation limits: the full private sweep lasts 6 s, but soft pulse edges and sampling mean the visible first/last brightness changes need not be exactly six seconds apart. Compare quiet colors/brightness with the same generation's baseline. Record actual brightness increases without demanding a sampled frame hit the mathematical maximum 1.45×; enabled/range should remain unchanged. Snapshot tuples alone do not establish appealing motion, lack of distracting flashes or complete timing coverage: root's native view supplies those judgments.

No new helper, test framework, random forcing, UI input or source mutation was created for this plan. Preserve the five natural-pattern clips, the sampled data and the Party/accessibility/lifecycle evidence, then obtain the final independent native review before the separate publication.
