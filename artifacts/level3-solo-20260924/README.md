# Level 3 genuine solo route and finale fix — 24 September 2026 (Claude)

Studio Play on the owner's PC, place 131311258779917 in Edit (saved-only content; the published place is still v2083,
checked through Open Cloud place-version history at 20:42 UTC: v2083 isPublished, v2084–v2091 saves only).

## How the rounds were driven

- Start: lobby station 9 (`LaunchZone9`), host panel `DecreasePlayers` ×5 then `CreateParty` via Studio MCP mouse input,
  the normal 3 s countdown, the normal loading/elevator entry.
- Movement: `bot-client.luau` — client PathfindingService (radius 2, height 6) and `Humanoid:MoveTo` at the game's own
  WalkSpeed. No CFrame, speed or health writes, no dev cheats.
- Prompts: `ProximityPrompt:InputHoldBegin/End` with the camera aimed at the prompt; the server's own `canUsePrompt`
  (distance + head ray) accepted every pickup/insert/hide. Leaving a table fires `Level3HideRequest "EXIT"`, which is what
  the E / LEAVE HIDING handler sends.
- Sprint in the finale: the game's touch RUN toggle (`workspace.ForceTouchUI` for the UI only, then a click on
  `StaminaGui.TouchRunHold`). A LeftShift held through Studio MCP does not register (NoiseReporter reads the physical key).
- Evidence: a read-only server attribute recorder (`recorder-server.luau`; later rounds added keys) and a 10 Hz Mall Manager
  telemetry sampler.

## Results

| Round | Seed / layout | What it shows |
| --- | --- | --- |
| 1 | 1427802098 / L3-2-64ca1bce | Genuine to the reader: 5/5 CDs, forced hide under table 14 through a real hunt with TABLE_CHECK, reader 5/5. **Finale is not evidence**: the console shows `Third-person ON` and `Noclip fly ON/OFF` from keystrokes this session never sent (a parallel Codex computer-use session, since stopped by the owner). |
| 2 | 1428587057 / L3-2-b0507a65 | **Genuine full route** (`round2-server-recorder.txt`): 5/5 CDs in 137 s after the first pickup, self-chosen hide under table 18, hunt TABLE_CHECK survived at 100 HP, reader 5/5, exit, `Escaped=true`. **Defect found**: the finale Manager froze in L3_S2_R05 (PHYSICAL_WAYPOINT_REJECTED loop) and the player walked the whole hall untouched. |
| 3 | same (pinned) | Deterministic reproduction with telemetry (`round3-manager-telemetry.txt`). Also contaminated by foreign `Unlimited ON/OFF`, so no stamina figures are used from it. |
| 4–5 | same | Room geometry capture; first fix attempt (waypoint reach from actual speed) only moved the freeze to the doorway (6337, 379.5). That edit was reverted. |
| 6 | 1431515537 / L3-2-415996d8 (random) | **Genuine full clear with a working finale chase** (`round6-genuine-clear-random-seed.txt`): 5/5 CDs, reader, Manager reached the hall and closed from 131 to 29 studs; escaped at x 7282 with 14 % stamina (×1.55). |
| 7 | 1428587057 (pinned) | **Final code** on the freeze seed (`round7-final-code-base-stamina.txt`): Manager crossed R05 with ROOM_AISLE (13.2 ms search) and chased; with base stamina ×1.0 the runner escaped with the Manager in ATTACK_WINDUP 3–5 studs behind. Prompt-distance probe: 24/24 COLLECT prompts shown at CD1/CD2, including 3.6–4.2 studs from the long sides. |

## The defect and the fix

On seed 1428587057 the only S2→S3 gateway is L3_S2_R05's south door. That BirthdayCenter room has four structural columns
and two table envelopes that leave the Manager's centre a single 1.7-stud aisle (x 6305.9–6307.6) between its east and south
doors. PathfindingService (agent radius 4, 4-stud voxels) routes through an 8.6-stud column/wall gap that the 10.5-stud body
sweep rejects; both room-perimeter repair rings cross an envelope or a column; every repath returns the same route. The finale
Manager therefore froze for the rest of the round (a free finale). Three independent read-only investigations and two
adversarial verifiers agreed on the mechanism; the verifiers also showed that a door-axis ring variant fails from the doorway
pose and in the reverse direction.

Fix (Manager AI Controller, `LEVEL3_MANAGER_ROOM_AISLE_REPAIR_20260924`): a third fallback inside `installRoomPerimeterPath`.
`buildRoomAislePath` runs a one-stud grid BFS over the current room with the unchanged `volumeFits` contract, string-pulls with
the unchanged `volumeClear` sweep, reuses the perimeter repair's doorway/inset rules, publishes PathStatus `ROOM_AISLE` and
`Level3_MallManagerAisleRepairMs`, and runs at most once per second per Manager. Every leg still passes the full physical and
furniture sweep, so the body cannot clip anything the old code avoided. Live search cost: 7.2–15.9 ms.
After an adversarial review (three read-only reviewers) the search was hardened before commit: the doorway leg into the next
room is mandatory (as in the perimeter repair), the BFS stops after 2,000 cells, it refuses to start when the body does not fit
where it stands, and failed searches back off 1 → 2 → 4 → 8 s. Rounds 6 and 7 ran the pre-hardening version; the hardened
187,862-byte source was pushed and compiled in Studio (182/182) but not played again.
Offline: `tools/tests/test_level3_room_aisle_repair.py` (29 checks on the measured R05 geometry, from the doorway and both
live freeze poses, blocked doorway leg, backoff; mutants for each guard killed). `test_level3_steering` 222, `test_level3_hidden_chase` 57,
`test_studio_compile_limits` 182/182 at -O0 all pass.

## Still open (not claimed)

- The card's "Level 2 → 3" leg: these rounds started Level 3 from its lobby station, not from a Level 2 exit transition.
- Listening: cues fired (PowerDown, ExitUnlocked, Escape; room-song speakers playing), but nobody listened.
- Publication of the maze/prompt/aisle changes (owner), physical devices (waived by the owner).
- Finale tuning with base stamina (owner decision, measured above).
