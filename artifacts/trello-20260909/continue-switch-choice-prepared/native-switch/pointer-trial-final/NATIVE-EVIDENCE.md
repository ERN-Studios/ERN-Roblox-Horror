# Native Switch evidence — serial7, pending independent final review

**The requested core sequence is now observed through real GUI input and authoritative replication:** Player1 changes Continue → Lobby → Continue in one result window; both actual clients display each latest accepted choice; neither starts the next level early; both subsequently reach Level2 alive and ready. This is evidence for review, not publication or a self-assigned final score.

The frozen collection contains1298 complete messages/3642 chunks, no parse/rejected-message errors and no sequence gaps. `messages.jsonl`, `raw-chunks.jsonl`, `collection-report.json` are preserved; `serial7-source-records.jsonl` is a bounded view of the original records. Exact hashes and structured reduction are in `native-switch-evidence.json`.

## Actual input and acceptance

Player1 observer `7c5df6b7`/-1 and Player2 observer `79a7a591`/-2 are distinct actual local-test clients. The current virtual input source hash is `57dfd9b8b47a434598b18aa1bd3866c8bd84721d2756541a7cdfd320c9bb6c48`. It uses the documented VirtualInput mouse API; it does not fire Activated, call a GUI callback or send a result-choice RemoteEvent itself.

| Step | Actual Activated, server-time DK | Accepted revision | A's displayed row | B's displayed row |
|---|---|---:|---|---|
| Continue |15:50:13.269 |2 |Player1 — CONTINUE |Player1 — CONTINUE |
| Lobby |15:50:14.268 |3 |Player1 — LOBBY |Player1 — LOBBY |
| Continue |15:50:15.267 |4 |Player1 — CONTINUE |Player1 — CONTINUE |

All three steps have their own `BeforeMouseDown`, real UserInputService Begin/End pair, `ActualButtonActivated` and matching server-packet acceptance. The pointer readback matches the intended screen coordinates(226/540,236), with the real58px top inset; each move settles in one observed frame before mouse-down. The final fixture report is `Completed=true`, reason `three server-confirmed choices`, at15:50:15.296. This is automated engine input, not a manual-human timing claim. `virtual-input-events.json` preserves exact matching log lines and JSON payloads.

Both clients receive exactly revisions1–5: initial deciding/open; Continue/open; Return/open; Continue/open; then Closed. Player2 stays deciding throughout. At all three accepted revisions, each actual client snapshot shows the correct visible row (`TextFits=true`) and both original buttons still visible and active. These are actual767×274 client windows; no synthetic peer or fabricated selected row is used.

## Deadline and real arrival

The original shared deadline remains **1789048227.637087 (15:50:27.637DK)** in both win packets and every fixture acceptance. The third choice is accepted more than12 seconds before closure. A receives Closed at deadline+0.367549s; B at +0.386630s. First loading events occur at +0.368747s/+0.388222s. No earlier loading event exists after this win. The actual server line settles window7 as **2 continuing/0 returning/0 departed/0 gone → cohort2**, consistent with A's final Continue and B's automatic default.

A's fully released Level2 snapshot is **2026-09-10T15:50:34.914+02:00**, B's **2026-09-10T15:50:34.799+02:00**. Each own player is100HP/InRound/unanchored with its own RoundEntryControlsReady and RoundEntryUIReady. Both show WorldGenerated/RoundActive, SelectedLevel2, ready, no post-win intermission, and loading/ending UI hidden. The new server observer `2f91be47` also records both real players alive/unanchored in Level2. Server-time payloads are used for deadline comparisons; raw log UTC has a separate offset and is not mixed into that calculation.

## Disclosed setup and limits

The L3-final cycle returned both actual players to the fresh lobby and staged them in the real queue. Its120-second wait expired at13:48:02UTC before root's Create Party at13:48:11; therefore its planned3-second L1 completion did **not** execute. Root used the normal2/Public queue and separately armed a30-second controlled PuzzleWon after normal L1 entry. Those are objective/setup fixtures, not a full puzzle playthrough; no deadline override or fake win/choice packet is claimed.

This trial ends with Continue/default for both. It does not newly cover an eventual final Lobby selection, mixed earlier-level transport, disconnect/late packets, physical devices or a cloud Teleport. Those limits must remain separate from existing actual-source regression evidence and earlier base-feature native results. Root owns final source parity, independent final acceptance and one mouse publication. No observer, production/UI source, Trello or Studio state was changed by this read-only collection/reduction.
