# Ad and thumbnail source shots (Trello kydyBl7u)

Captured 2026-09-24 in Studio play mode (single player, Test mode) from the place as it stood
on branch `claude/trello-20260921` (last publish v2018). These are the six moments that
`docs/CODEX_ASSET_ORDER_2026-09-23.md` section 4 asks for. They are raw captures of the viewport
at 1534x803, with the real HUD on screen and no retouching.

| File | Moment | Setup |
|---|---|---|
| `01-lobby-level1-guide.png` | Lobby, Level 1 gate and the "LEVEL 1 START HERE" guide | The guide runs only on a brand-new profile; Studio's profile had already been briefed, so `ZyntraFirstLogin` was set client-side and the real `First Entry Guide` script was started again. |
| `02-level1-elevator-opens.png` | Level 1, elevator doors open onto the first corridor | Solo Level 1 round, captured right after `start`. |
| `03-level1-entity-23-studs.png` | Level 1 entity at 23 studs, red eyes, flashlight on | `EntityPaused` on, entity placed at the corridor end facing the camera, `EntityState = CHASE` for the hunting eye colour. |
| `04-level2-vaulted-corridor-seed1182081016.png` | Level 2 vaulted corridor 1 | `Level2Seed = 1182081016`. **Part-built ribs:** `Performance.ArchMeshRibs` is still `false`, so this is what players see today, not the uploaded mesh ribs. |
| `05-level2-pool-foam-in-view.png` | Pool Foam at 23.6 studs in a pool hall | Same seed. The foam closed from about 20 studs to 4.4 before the camera turned to it (the look-latch rule working), then `EntityPaused` was used to stage it at a distance. |
| `06-level3-first-cd-on-table-seed1154781618.png` | Level 3, Party Mix CD 01 on its table in `L3_S1_R05` | `Level3Seed = 1154781618`, Mall Manager paused. The E prompt on the table is COLLECT CD, not HIDE, as `FIRST_CD_PROMPT_20260922` intends. |

What was hidden, client-side only and for the capture only: the developer's own dev overlays
(`DevESP` highlights, the Pool Slide dev status panel), the Developer/Supporter nameplate over the
avatar in shot 1, and the Valve Vision pass highlight in shot 5. Nothing was changed on the server
or in the saved place.

Variants, test setup and measuring spend, plays, CPP, playtime and D1 still belong to the owner
and Codex; the card becomes Done only after a controlled test.
