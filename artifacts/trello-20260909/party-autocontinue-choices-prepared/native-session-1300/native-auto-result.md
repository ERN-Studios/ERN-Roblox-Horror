# Actual two-client automatic continuation

Bounded native observation, 2026-09-10. Root entered the ordinary Level 1 queue with actual Player1(-1) and Player2(-2), then set the controlled Play PuzzleWon fixture after round readiness. This is not a completed puzzle, an earned escape or live TeleportService travel.

The collected prefix-only evidence contains **289 complete messages / 849 chunks**, with no missing sequence range, duplicate/incomplete message or parse error. Source hashes and selected exact raw payloads are preserved in native-auto-result.json.

Both clients received session1 with the same server deadline **1789039414.898872**. The unchanged15-second source rule implies a window start of 1789039399.898872; no separately measured callback time is claimed. Both revision1 and revision2 rosters remained deciding, with **0 ActualButtonActivated events** through both ready arrivals. No unanswered player was mislabeled as an explicit click.

| Observation | Player1 / client−1 | Player2 / client−2 |
|---|---:|---:|
| Win receipt time | 1789039399.932570 | 1789039399.903809 |
| Deadline − win receipt, seconds | 14.966302 | 14.995063 |
| First loadinggame receipt | 1789039415.270082 | 1789039415.287174 |
| Loading receipt − deadline, seconds | 0.371210 | 0.388302 |
| Actual entryreleased receipt | 1789039420.112062 | 1789039420.118218 |
| Actual start receipt | 1789039420.112618 | 1789039420.119141 |
| First complete own ready snapshot | 1789039422.360970 | 1789039422.084159 |

Server loading was observed at **1789039415.154598**, deadline+**0.255726s**; L2 ready/active at **1789039420.084045**, and both actual characters were HP100/InRound/unanchored by **1789039421.932333**. Each own-client ready snapshot independently had SelectedLevel2, RoundLoadingState=ready, RoundActive=true, RoundEntryControlsReady=true, HP100, unanchored root, hidden LevelLoading and hidden ending. Both had entry token :entry:2.

**Result:** actual 15-second automatic local continuation and both Level2 arrivals are observed. Event receipt and0.5-second snapshot cadence include replication/scheduling delay; exact callback timing is not inferred. Intermediate old-character replacement states are retained in source logs, so no uninterrupted old-character health claim is made.

Explicit choice replication, mixed-choice destination, six-row native layout/scroll and separate publication are still distinct checks. Historical wait-for-every-player evidence is superseded. No runtime/UI action or Trello write was performed by this evidence reduction.

## Second controlled result: auto, not an accepted click

Serial2 in Level2 had deadline1789039585.709795. Both revision1/2 rosters remained deciding and there were0 ActualButtonActivated events through its L3 start. Clients received loadinggame3 at deadline+0.647855s (A) / +0.640062s (B). The reported attempted mouse click is therefore not evidence of an accepted Continue; its precise miss/deadline cause is not established by these logs. See native-auto-serial2-result.json. The source capture is frozen in native-auto-source-messages.jsonl and native-auto-source-collection-report.json before future collector runs.
