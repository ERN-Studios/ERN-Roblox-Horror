# Full-board comparison before the square-button release

Root snapshot at **2026-09-10 19:04:20.038 Europe/Copenhagen**, compared with our **18:18:34** snapshot: **71 cards (66 Development + 5 starter), 0 new, 0 removed, 0 renamed**. Both `pageInfo.hasNextPage` values are false.

Exactly three cards have changed in the compared common fields:

| Card | Expected change |
|---|---|
| [tnnPzDyn — exit compass](https://trello.com/c/tnnPzDyn) | To Do → Done, complete=true, v1871 description/activity update. |
| [pCSeWVcQ — shorter upgrade copy](https://trello.com/c/pCSeWVcQ) | To Do → Done, complete=true, v1872 description/activity update. |
| [lXtjnc8N — ceiling sweeps](https://trello.com/c/lXtjnc8N) | To Do → Done, complete=true, v1873 description/activity update. |

All other compared names, list/status/archived fields, descriptions and activity timestamps are unchanged. The different connector snapshot shapes were normalized for these fields; this is not a claim of byte-identical raw JSON or re-fetching every dedicated checklist endpoint. No Trello mutation was performed.

The only active final implementation is the **square-button card Nn65pxPk**; its native phone-caption correction/retest is still pending. PLAYER ESP and free DEV-respawn remain explicitly deferred, regardless of their unchanged To Do status. Testing, pricing, token research, owner/friend ElevenLabs audio, Level4 idea, and the two documented external blockers are preserved. After the last confirmed release, root commits/pushes the curated final mirror and stops.

Machine-readable field deltas: `trello-final-delta-before-square.json`. Root's source snapshot: `trello-final-boards-before-square.json`. No Git/UI/Studio/source action was performed during the comparison.
