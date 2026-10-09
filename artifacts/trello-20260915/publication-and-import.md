# Publication and live sales import

- Creator Dashboard version history, Show published only checked:
  **version1906,15September2026 23:55 Copenhagen**, newest published version.
- Live Roblox client joined a new public server of the game at21:57:44UTC.
  New physical textured shop was visible.
- Creator DataStore manager, ZyntraPlayerData_v1, key
  `salesimport_sales_20260915`: **Done=true, Applied=44, Failed=0**.
- SHA matches owner's CSV exactly:
  `97fb4a8d30be0e2e2da18e6bed3a626446bb35336a61a25d99847ce8f6b95edc`.
- Claim JobId matches the live client's joining-server ID (stored privately in
  the platform record/client log); At1789509515.
- Final native compilation before publish:122/122,0errors, including the
  temporary server-only import module.

## Completed profile audit

All 39 live profiles were read back from Creator Dashboard after import:
44 row markers, donation20 + utility1068 + pass/private-server20119 =
**21207 Robux**. All40 original receipt IDs remain. No changes to tokens,
upgrades, grants, protection quantities, re-entry credits, colors or completion
records (missing empty/default fields were normalized).

The live Done=true/Failed=0 claim also covers successful ordered leaderboard
writes for every buyer: syncSupportTotal failure increments Failed before Done
is set. A separate direct ordered-store read from Studio was unavailable because
Studio API access is disabled; no security setting was changed. The live game's
new lobby/shop loaded successfully. No paid purchase was made during QA.

Temporary ServerStorage.ZyntraSalesBackfill removed from Edit after the successful
audit. Cleanup **version1907** published16September2026 00:10 Copenhagen;
Creator Dashboard Show published only confirms1907.
