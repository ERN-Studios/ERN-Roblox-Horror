# Circle session started 10 September 2026, 16:26 Denmark

Run from `G:\Roblox\MongoTV`:

```powershell
python artifacts/trello-20260909/full-lobby-circle-prepared/native-session-1626/collect_circle.py
```

This imports the unchanged reviewed parser (`33b66578…f4626`) and changes only `LOGS` and its artifact output directory. Optional `--self-test` runs the original bounded in-memory parser checks. No Studio, UI, source or gameplay access is used.

Actual logs under `%LOCALAPPDATA%\Roblox\logs`:

| Role | Filename |
|---|---|
| Server | `0.738.0.7381393_20260910T142616Z_Studio_9B2A4_last.log` |
| Client A, actual -1 | `0.738.0.7381393_20260910T142623Z_Studio_04FC9_last.log` |
| Client B, actual -2 | `0.738.0.7381393_20260910T142624Z_Studio_5D83E_last.log` |

Their process records share `playTestSessionGuid 77DA0ACA-0F20-46A2-852C-F1CB5E7C7AF5`, correct place/universe and StartServer/StartClient roles. Client identities are also verified from emitted headers/JSON, rather than inferred from startup order. All server/client run IDs are retained, including expired or failed observer attempts.

Each collection updates only this session's `raw-chunks.jsonl`, `messages.jsonl` and `collection-report.json`; older Continue evidence is untouched. The existing exact header, UTF-8 assembly, duplicate rejection, missing chunks/sequence detection and JSON/header identity checks remain unchanged. Once a trial is complete, freeze/copy these artifacts before another trial if separate immutable evidence is needed.

Interpretation: a collector success means complete parsing only. Look for the actual server `CircleFixtureStage`, `CircleSample`, `CircleExclusionChecks`, `CircleVacant`, `CircleReopened`, `CircleCancelReset` and final `Stopped` with its error/completion field. Correlate A/B real queue packets and UI snapshots in the same time interval. Old `Stopped.Completed=true` after 240 seconds only means that observer expired normally; it does not certify a circle test. A `queuefull` packet can be brief before the next `lobby` feedback, so preserve both. The fixture's explicit movement stages are test setup, not mouse/keyboard movement evidence.

First observed runs `dcf1aaac` (-1) and `66d27934` (-2) expired at 16:32:32 and 16:34:18 respectively with only initial Snapshot/Armed/Stopped and no queue activity. These remain historical setup runs, not passed tests; new observers must cover the actual intrusion/reopen/cancel window.
