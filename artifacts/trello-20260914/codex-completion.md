# To Do implementation and verification — 2026-09-14

Codex took over after the owner's instruction to stop Claude. This report supersedes the first Claude handoff and its open implementation findings. Scope is the 13 cards captured in `todo-snapshot.json`; Level 4 and other lists were excluded. The Claude monitor is paused. No production publish, Discord message or payment was performed.

## Delivered in source and Studio

| Card | Result and verification |
|---|---|
| 44 | Token-item research completed in `token-items-research.md`; this card requests proposals, not implementation of new items. |
| 45 | Developer-only player ESP, client-local markers and server replies to the requester only. First Studio test produced the developer marker; ordinary spectators cannot receive another client's GUI. |
| 64 | Developer-only free respawn. Actual Studio respawn restored health without changing tokens, credits or paid re-entry state. |
| 67 | Five ceiling on/off patterns, with restoration on cancellation. Studio exposed and fixed an invalid Color3 multiplication. Actual controller passes 21,940 offline assertions. |
| 68 | Smaller shop and upgrade content on phones/tablets, preserving the tabs. Studio layout matrix: 1,405 checks, zero failures across 11 layouts. |
| 70 | Guide now depends on whether the successful atomic profile load created the record. Leaving before the welcome briefing finishes no longer makes a returning player look new. 33 profile-load checks and 39 guide checks pass. |
| 71 | One-time grant prepared for Kecoalmutt, UserId 10152463945: +1 stamina upgrade, +1 battery upgrade and 10 research tokens. Durable marker prevents repeats; failures retry on a future load. 26 checks pass. **Delivery awaits the player's next successful login after publication.** |
| 73 | Counter contains no names and rejects invalid/self/living reports. Stale counts clear on death, escape, respawn or leaving. Escaped spectators now receive the watched player's audio, exit/objective displays, stamina, battery and read-only protection timer. ESP remains private to the developer client. |
| 74 | Back-to-lobby action integrated. Two real local clients verified both a spectator and living player leaving Level 1, clearing the counter and ending the round. Production Level 2/3 uses the teleport route; Studio cannot exercise that external teleport. |
| 75 | All CDs must be deposited; the first runner entering the final hall starts the entity at the level entrance. Normal hunt/spawn behavior is preserved. Finale approach follows the existing maze navigation and collision sweeps. Once it reaches the hall, speed is fixed using the runner's lead so different maze lengths remain escapable with a tight margin. It does not slow down when the runner hesitates. |
| 76 | Capacity-full party gets a physical ring. In a real two-client walk test the outsider stopped at radius 9.05, outside the 7.41-stud circle; a member could leave, the barrier disappeared, collision group restored to Default and the outsider entered to radius 0.80. |

## Deliberately open

- **18 — Audience reach:** owner confirms no qualifying two-month subscription. Dashboard investigation and current requirements are in `audience-status.md`; age access still depends on Roblox eligibility/evaluation. No payment selected.
- **69 — Discord alerts:** implementation and relay tests pass (97 + 30), but operational setup is explicitly deferred by the owner. It remains disabled. No channel, roles, webhook or deployment was created.
- The build is not published, so live gift delivery and production teleports are not claimed as verified.

## Multiplayer evidence

Evidence is under `multiplayer-results/`. Tests use a real Studio server and two clients, with disposable local-only fixtures controlling the characters.

- `barrier.json`: outsider obstruction, member exit, barrier removal, entry afterward.
- `spectate-after.json`: Player2 (Studio UserId -2) watches Player1 (-1); Player1 sees `1 SPECTATOR WATCHING`.
- `leave.json`: spectator and living player both return to the lobby; counter clears.
- `vitals.json`: actual client shows 37% stamina, two of five battery bars and a `SAFE 3.0s` timer that is not pressable. Deterministic server presentation attributes are used for the nontrivial values; normal client reports were separately observed reaching the server.
- `finale-balanced.json`: final production code, all five CDs deposited with no early entity, then actual running to the escape sensor. 23.75-second escape, health 100; entity roughly 20 studs behind near the exit, hall speed fixed at 29.58. Normal gameplay profile remains 22 / blackout 31.2.
- `finale-balanced-hesitate.json`: same final code on another generated layout. Player pauses at 11 seconds and is caught at 14.55 seconds, health 0, not escaped. Hall speed stays fixed at 31.17 until capture. Spectator again hears custom run asset `133003345144597` at 0.68, while both default `Running` loops remain muted.
- `finale-hesitate.json`: earlier fixed-speed build caught the player after a pause. Its spectator audio snapshot plays our custom running asset `133003345144597` at volume 0.68; both Roblox `Running` loops are muted.
- `finale-run.json` is an **invalid** early fixture run (preparation failed). `finale-run-valid.json` records the old slow/stuck approach. Neither is acceptance evidence. Later files explicitly replace them.

## Focused regression results

All checks run against the mirrored production source: finale 30, navigation 222, Level 3 flashlight timing 322, flashlight input/battery/replication 217, controller inputs 120, first login 33, first-entry guide 39, spectator audio/parity 18 + 18, spectator counts 16, vital validation 14, gift 26, barrier 72, re-entry 37 and round loading 83. Shop sizes pass the phone/tablet/pointer regression. The earlier broad suite also identified pre-existing failures in the run-in exit, hidden chase and slide aperture harnesses, plus the push-tool harness's Luau discovery/version issue; this is not a claim that the entire historical suite is green.

Final Studio cleanup and compile/audit results are recorded in `status.md` once completed. The temporary server/client drivers and temporary HTTP/loadstring settings must not be included in any release.
