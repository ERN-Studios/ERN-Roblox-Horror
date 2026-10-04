# Codex integration handoff — 2026-09-14

User clarifications are in owner-clarifications.md. Claude's 15:59 UTC screenshot reports the initial Studio audit matched all 126 scripts. Codex has prepared the following changes independently without using the bridge.

## Ready for live parity review and integration

- Card 67: ceiling-proposed/ contains LobbyCeilingSweeps, with five real on/off patterns, fixture emission off, ownership-aware restoration and unchanged ReduceFlashing/Party/round guards. Compiles. test_ceiling.py executes all five patterns plus accessibility/party/round/destroy restoration in a fake engine. Source baselines/hashes in ceiling-basis.json.
- Card 75: finale-proposed/ contains Level 3 Objective Controller and Mall Manager AI Controller. User explicitly asked for normal gameplay unchanged; after all CDs/DONE, first survivor four studs into the final exit hall triggers the finale, entity spawns at MazeStart + a clear 8/12/16/20-stud forward position. Normal chase profile is unchanged. It follows normal room navigation until reaching the final hall, then the direct opened-hall path. Compiles. test_finale.py verifies trigger cases, mode-before-hunt ordering, one-shot latch, entry spawn clearance/retry, and unchanged normal hunt/spawn implementation. finale-basis.json records baselines. Physical chase pacing, collision and multiplayer escape still require Studio playtest; don't claim verified tightness from local tests.
- Card 71: user supplied @Kecoalmutt; official API resolved exact match AdminNBCRxAria, user ID 10152463945. gift-integration.luau is ready for YOU to insert into the shared ZyntraMonetization refreshPasses after sessions guard. It uses the existing serialized mutate and a separate persistent grant marker, +1 StaminaLevel, +1 BatteryLevel, +10 Tokens. Please integrate and add real retry/dedup/profile persistence validation as part of your Zyntra work. This gift has not been awarded yet. No fabricated pass ownership or receipt change. Check and report whether delivered vs merely queued for next successful profile load.

Codex prepared copies remain outside the mirror to avoid manifest/write races while Claude owns the bridge. You may integrate these three source files once their live and repo hashes match the recorded baselines, queue manifest entries, push using UpdateSourceAsync, verify parity, and run the relevant Studio smoke tests after your own eight cards. If the basis differs, preserve current work and merge carefully. This integration extends your work, not a request to read new Trello cards. Include it in your final quality check.

## Completed investigation, no game edits

- Card 44: token-items-research.md has six concrete candidates, proposed prices, constraints and recommendation. The card requests research/proposals, not automatic implementation.
- Card 18: audience-status.md records live dashboard 16+, warning persists, 175/250 graph updated September 12, fee not submitted. Account Manage says all ages / checks Done. Precise publishing-risk cause still unconfirmed; no payments or account changes. Optional expedited fee is now 50,000. Remains blocked by owner subscription status + Roblox engagement/evaluation.

Do not inspect other Trello lists or Level 4. Do not mark untested changes Done. Do not send Discord notifications externally without the user's concrete authorization. Continue with your planned Opus workflows and final Fable quality check.
