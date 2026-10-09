# Continue choices — final native feature review: 9/10

Reviewed 10 September 2026 for card `zlI8Rmto`: preserve the original result-screen composition and its 15-second automatic continuation, while showing accepted player choices. **No remaining release blocker found for this bounded version.** Publication was still pending when this review was written.

Final checked source:

- GameManager: `3615b6a3ca5eb8dde3acdcc7c4f03ed674b5cc84641bce6ed07670e67c3e5d58`.
- RoundUI: `7321e76dfb3a035cd72b0a03fc81f50b7388f1ec58353f8f8f03836bf08f28f5`.

I verified the final RoundUI disk hash. Root reported that the exact source was installed, the Play session was stopped, all 125 scripts compiled and the source audit matched 125/125 with zero drift. I did not operate Studio or independently rerun that Studio audit. The small presentation correction was authored by this reviewer and separately reviewed by `/root/audio_readiness` at 9/10, including an independent 418-check run and exact inverse proof; see `compact-single-column/independent-code-review.md`.

## Actual two-client behavior

The preserved observer/collector evidence uses two actual local clients, Player1(-1) and Player2(-2), from normal party queues. Root triggered controlled objective-completion fixtures after readiness. These were not full puzzle playthroughs, earned escapes or live cross-server TeleportService tests.

`native-session-1300/native-auto-result.md` and its frozen raw source show the unchanged 15-second automatic flow with no button activations: both clients remained deciding, then both entered Level 2. Their win receipts were 14.966302 and 14.995063 seconds before the shared deadline. The server was observed loading at deadline +0.255726 seconds. Both clients reached the real start/entry-release events and their own ready snapshots had HP100, InRound, unanchored roots, controls ready and hidden loading/result screens. Receipt and snapshot timing includes scheduling/replication delay.

`compact-correction/native-choice-serial5-6-source.json` and its summary preserve later successful physical button input separately from earlier missed clicks:

| Observed case | Input and accepted choice | Result |
| --- | --- | --- |
| Serial 5, Level 2 | Player1's actual Continue activation at `1789040217.945330`; accepted revision 2 at `1789040217.993760`, also observed by Player2 at `1789040218.004726` | Player1 shown CONTINUE; Player2 remained deciding; both received Level 3 entry and real start events |
| Serial 6, final Level 3 | Player2's actual Back activation at `1789040401.830249`; accepted revision 2 at `1789040401.878175`, also observed by Player1 at `1789040401.886708` | Player2 shown LOBBY; final-level routing returned both players to the lobby |

The final snapshots independently showed each client's own restored controls, both actual players at HP100 and out of round, unanchored lobby bodies, RoundActive/PostWin false and hidden result/choice UI. This does **not** establish a mixed Continue/Lobby destination split on an earlier level: the Back case occurred in the final level, where automatic continuation also returns to the lobby.

## Native display correction and final result

Both genuine failures remain in the artifacts. The first native 767×274 result had a 27-pixel list window containing 32-pixel two-line rows; the choice line was clipped despite the label's own TextFits=true. The first compact correction then exposed a second real failure in the Studio custom device: actual viewport **567×270**, no synthetic viewport attributes, 20-W name plus ` — CONTINUE` measured **291×11** inside a **259.5×25** row, TextFits=false. Neither failed version is counted as final acceptance.

The final source uses one column only when the list is too short for two text lines. `compact-single-column/native-568-top.json/.jpg` and `native-568-bottom.json/.jpg` show the actual 567×270 device viewport, a 543×25 list and **531×25** rows. I read both complete reports and viewed both screenshots. All six labels have TextFits=true. The long name is completely visible at the top; actual mouse scrolling changes CanvasPosition from 0 to 125 and makes the last row completely visible. The measured six 25-pixel rows occupy a 150-pixel canvas, so all six have a mathematically reachable full-row position. The two screenshots directly demonstrate the first and last positions, not a separate stopped screenshot for each intermediate row.

The already recorded 1407×533 desktop native view displays all six original two-line rows. The 666×374 Studio phone simulator view demonstrated actual top-to-bottom scrolling, and 374×665 portrait showed rows 2–6 with retained scroll 32. The incorrectly named `native-iphone7-portrait-top.json` also retained scroll 32 and is not counted as a top observation. Noncompact behavior is byte-preserved by the final one-hunk correction and covered by resize regression checks.

`compact-single-column/native-568-reset-sequence.json` confirms identical original title/divider/stats/countdown/button geometry on clear/restore, stale packets ignored, a new session hiding all rows and resetting scroll to zero, old-session packets unable to restore them, and lobby reset hiding the ending and choices. The empty current-session packet hides the parent list; retained child data cannot render while it is hidden. The new-session/reset paths explicitly clear visibility and old scroll.

## Scope limits

Six displayed names were synthetic display fixtures, not six actual players. The phone/device tests ran in Studio with mouse input; no physical-phone touch gesture is claimed. Existing source tests cover the server snapshot/serial behavior and layouts, while actual two-client evidence covers auto continuation, accepted Continue/Back replication and real local arrivals/cleanup. The observed 25-pixel extreme-short-screen list intentionally shows one complete row at a time to preserve the user's original composition.

The new `rLDqjpE4` request to switch Continue/Lobby choices until transition is a separate subsequent feature and is **not installed or delivered by these sources**. Historical wait-for-every-player behavior was superseded before publication and is not part of this approval.
