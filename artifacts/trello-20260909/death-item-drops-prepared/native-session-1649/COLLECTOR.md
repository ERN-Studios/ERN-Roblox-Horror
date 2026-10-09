# Death-drop session — 10 September, 16:49 Denmark

Run from `G:\Roblox\MongoTV`:

```powershell
python artifacts/trello-20260909/death-item-drops-prepared/native-session-1649/collect_logs.py
```

Only the root-confirmed server `144927Z_Studio_93522`, client A `144934Z_Studio_633C4` (actual -1) and client B `144935Z_Studio_FC595` (actual -2) logs are read. Their full paths are retained in `collection-report.json`. Outputs stay in this artifact directory; each collection refreshes `records.jsonl` and the report.

Every retained event includes exact log/line/UTC, assigned side/identity and unmodified CreatorOutput message. Recognized death-drop markers are decoded as JSON; incomplete or malformed output remains visible as an issue, never a passed empty snapshot. Command Bar echo lines beginning `>` and non-CreatorOutput continuation/source lines are excluded. JSON `UserId` values on client evidence must match that actual client. Plain setup/AI-pause/view messages remain attributable text rather than invented structured state.

Keep both clocks: CreatorOutput timestamps are native log UTC; `StartedAt`/`TriggeredAt`/`FinishedAt` are the recorded `GetServerTimeNow()` values. Do not mix them to derive subsecond timings. Scripted view, approach, AI pause and death are explicit fixtures; successful key dispatch alone is not prompt acceptance or inventory transfer. First E with `ActualTriggered=0`/carry0 remains a failed input setup. More death, other-player pickup and cleanup evidence is required before feature acceptance.

Local helper hashes are recorded as provenance only; root separately verifies what was executed. No Studio/UI/production/Trello actions occur in this collector. It does not read or change bot state.
