# Editable end-of-level selection — prepared only

[rLDqjpE4/#65](https://trello.com/c/rLDqjpE4) asks players to be able to switch between Continue and Return to Lobby until the transition starts, with the displayed choices updating. The dedicated card read is saved in `card-readback.json` (revision 2026-09-10T11:43:26.875Z; To Do; no comments or checklists).

This is a separate feature after the original Continue display release. The new requirement supersedes its first-click lock. Root confirmed that choices should remain editable through the **original 15-second deadline**, with the existing automatic default. No time is added. Only artifact copies were written; no runtime, Studio, UI, Teleport or Trello mutation occurred here.

## Concrete change

The existing client set `completion.pending=true` on its first click and disabled both buttons. The existing server also allowed only `Deciding → Continuing/Returning` and started a live Teleport at that first click. Merely unlocking the client would therefore fail to make switching possible.

The proposed two handlers now record a provisional choice without yielding or starting travel. A changed choice uses the existing routing module's `ClearDecision` and `RecordDecision` consecutively; membership and departure restrictions remain in that module. The server broadcasts the updated frozen roster. It rejects stale/invalid serials, wrong round/level, nonmembers, departed players, players with an existing transfer claim, aborted/closed windows and calls at or after the deadline. Accepted changes are limited to one per 0.15 seconds per player; identical choices do not mutate or broadcast.

The result window stays open until its original deadline even when everybody has chosen, including a solo player. If everybody disconnects, it may finish earlier because nobody can edit. At the deadline, the server marks the session closed and broadcasts that fact before returning the final partition to the **unchanged final transport/Studio fallback**. Players who never choose still continue automatically when a next level exists; the endpoint still returns to lobby. Existing reservation/entry-mode/cohort/transfer retry and teardown functions are preserved. Obsolete early-transfer handlers and their private reservation helpers are removed.

A pre-commit disconnect clears its provisional choice before the existing `NoteDeparture`, so a disconnected Continue selection cannot inflate the final expected cohort. The same presence check runs synchronously immediately before final closure/partition, because Roblox's `PlayerRemoving` callback may still be queued. The critic reproduced that ordering against the actual-source harness and initially scored it 7/10; the final-presence fence and its permanent regression now fix it. Already accepted/claimed transfers retain the old departure semantics. Frozen membership is never replaced with a client-provided roster.

The client keeps both original buttons active and their original captions. It displays only the server's accepted roster, so a rejected or still unacknowledged click does not pretend to change a selection or start travel. Local 0.15-second throttling reduces duplicate input, but the server is authoritative. A synchronous activation deadline check and the unchanged RenderStepped expiry prevent late clicks; a closed snapshot is sticky until a fresh result reset/start. No extra remotes, attributes, prompts, timer or UI layout are introduced.

The third file updates only the existing `UIRegression.CompletionContract` expectations that previously required a first-click lock. Its test presses Continue → Lobby → Continue in the same preview window and checks the retained captions and active controls. This is verification of the new feature, not work on an excluded Testing card; no other regression lane is changed.

## Frozen source and compositions

`before/` retains GameManager **3615b6a3…5d58** and RoundUI **eaf4053b…f7de**. Root installed the independently reviewed single-column correction while preparation was underway; that exact **7321e76d…28f5** input is frozen separately as `compact-input.lua`. **Use `after-compact.lua` for the current RoundUI checkpoint**, not the earlier uncomposed UI proposal. `manifest.json` records all full hashes.

`prepare.py` exposes a narrow `transform(source, kind)` that applies unique anchors and returns an inverse. The inverse must exactly restore the canonical source input. Root must compose the GM transform with later circle/slide/ESP/dev-respawn changes rather than overwriting those with the older whole-file proposal. No loader/slide/queue region is changed by this feature. The separate compact list columns remain byte-identical in the composed UI output.

## Bounded checks

```
python artifacts/trello-20260909/continue-switch-choice-prepared/prepare.py
python artifacts/trello-20260909/continue-switch-choice-prepared/test_switch.py
```

**76 server + 32 client + 19 CompletionContract checks pass**, using the actual full routing module and extracted actual GameManager handlers/intermission/PlayerRemoving body and RoundUI choice/input/countdown code. Four whole-file compiles pass (GM, both UI compositions and UIRegression). Three negative controls restore the old immediate-transfer handlers, the old first-click client lock, and remove the new final-presence fence; each fails its specific behavior assertion. The actual CompletionContract runs against the actual completion functions at the existing developer-preview boundary, and the host also verifies that its three switch commands were really dispatched with the same serial.

Checks include both switch directions, repeated/rate-limited input, exact deadline before the timer coroutine or next render tick, final selected partition, solo/all-chosen editing, unchanged no-choice defaults, new session/stale packet lifecycle, server closure, last level, authoritative identity and claim/departure guards, and provisional disconnect cohort accounting. The complete final transfer branch, next-level transport function, old layout and countdown code are also compared against the before source. Tests do not claim a real Teleport or native font/input result.

For root's actual composed sources, `test_switch.py --gm-source <merged.lua> --ui-source <merged-roundui.lua>` runs the same checks and writes **`validation-merged.json`**, preserving the reviewed standalone `validation.json`. Each run records source paths and verifies that it did not change the actual runtime files.

## Short native acceptance after the base Continue release

Use the existing normal two-client setup and observers under `party-autocontinue-choices-prepared/native-session-1300`; retain their raw chunk logs. This feature needs no new automatic input helper.

1. Open a normal end-of-level window, using the already documented controlled `PuzzleWon` event only if necessary and labeling it as a fixture. In client A, click Continue, then Lobby, then Continue before the unchanged deadline. Client B must see each latest accepted name/choice, while A's two buttons remain usable and neither client begins loading early. A single-player pass also must leave the first choice editable until the deadline.
2. Leave B unanswered. At the original deadline both should use the unchanged automatic/final route and controls should lock. A separate window with A's last choice Lobby and B Continue proves that the latest choices drive partitioning. Studio's existing mixed split returns the local session to lobby; it does not prove a real cross-server split. A live reserved-server check is needed for actual Teleport behavior.
3. Disconnect a provisionally continuing player before the deadline. The remaining roster must no longer count them as continuing; no late selection/old serial may revive them. Verify countdown expiry/cleanup/new window, actual button/touch/controller input, and that the independently accepted compact roster remains unclipped.

Independent review is **9/10 after the initial 7/10 finding was fixed**; see `independent-review.md`. The critic independently repeated all 127 checks, three negatives, four compiles, the source-preservation proofs and the original delayed-departure reproduction against the corrected source. No code blocker remains. This new feature's separate native acceptance/publication and exact later-feature composition are pending. Do not infer completion from the earlier Continue card's release or from offline mock counts.
