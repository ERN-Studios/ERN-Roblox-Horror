# Three-log collector

Run from `G:\Roblox\MongoTV`:

```powershell
python artifacts/trello-20260909/party-autocontinue-choices-prepared/native-session-1300/collect_chunks.py
```

Reads only the three exact log filenames in `LOGS`, under `%LOCALAPPDATA%\Roblox\logs`. Server identity must be `server|0`, client A `client|-1`, client B `client|-2`. The observer's exact prefix is `[CONTINUE1300|side|userId|8-GUID-characters|sequence|part/total]`, followed immediately by its JSON chunk. Other log channels/content and echoed command source are excluded. No UI, Roblox API, log writes or production changes.

Outputs are confined to this directory and replaced on each collection of the complete available logs:

- `raw-chunks.jsonl`: only matching observation chunks, with exact payload string, native log timestamp, log name/line and header fields.
- `messages.jsonl`: only complete messages with all chunks exactly once, JSON/header identities matching, exact joined `RawPayload`, parsed `Payload`, and first/last log timestamps.
- `collection-report.json`: input success/counts, missing/duplicate/conflicting chunks, invalid JSON/identity/header diagnostics, and missing sequence ranges for each observed run. Even identical duplicate parts are rejected explicitly, never silently deduplicated. Invalid/incomplete messages remain reconstructable from the raw chunk file.

Chunk order may be interleaved; join is by side/UserId/run/sequence then part index, with **no inserted whitespace/newline**. A live observation may be incomplete while the log is still being written; collect again later. Read or decode failures are reported, not silently treated as empty. Missing messages beyond the last observed sequence cannot be inferred: compare actual `Armed`/`Stopped` payloads and their Completed/Error fields. Zero collector errors does not certify observer completion or gameplay success.

`--self-test` runs only in-memory checks for shuffled UTF-8, missing/duplicate/conflicting parts, sequence gaps, JSON/header identity, malformed JSON, excluded unrelated output and invalid indices. It does not read logs or overwrite evidence.

## Second controlled result in Level 2

The current `GameManager.Script.lua` at lines2493–2502 resets PuzzleWon before the normal round and then checks it first in the shared win loop, independent of selected level. The existing guarded Level 1 completion fixture can therefore be reused for Level 2 by requiring SelectedLevel=2. Wait for actual L2 start, RoundLoadingState=ready, both real players alive/InRound/unanchored, no Escaped flags and PostWinIntermissionActive=false **before** setting only the Play `PuzzleWon` attribute. Setting it during entry can be erased by the ordinary reset.

This is controlled objective completion through the real GameManager win path, not a real L2 pump/exit ride or earned escape. Keeping Escaped=false avoids its escaped-player `ZyntraLevelCompleted` reward branch. L2's transition lifecycle is intentionally retained during intermission; the ordinary settlement handles it. The restored 15-second timer and mixed-choice Studio lobby fallback remain the behavior being tested.
