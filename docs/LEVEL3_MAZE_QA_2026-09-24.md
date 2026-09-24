# Level 3 core maze — 24 September 2026

Owner decision: preserve the scripted 560-stud finale corridor; enlarge and interrupt sightlines in the core maze only. The change is commit `7710853` on `claude/trello-20260921` (cherry-picked from isolated worktree commit `34d659b`). It changes only Level 3 Configuration, Layout Generator and Test Suite. The new `tools/tests/test_level3_core_sightlines.py` guards the structural bound.

## Result

The layout still generates 26 rooms, 31 links, six loops, five CDs and 24 hide tables. Mean room-floor area over 40 seeds is 18.7% larger. On those same 40 seeds, the longest structural clear sightline falls from 814 to 433.5 studs; 39 of 40 improve. The four named seeds improve from 514–541 to 400.5–421.5 studs. The latter figures model the structural chain; they are not rendered-world raycasts.

The three changed scripts were pushed to the current Studio place through the scoped compare-and-swap tool after a 182/182 Source audit and exact Source/editor equality. All three compiled. In a disposable Studio Play session, the World Builder constructed the following worlds. `ValidateWorld` passed on each, including its room, corridor, CD, prompt and structural contracts. `MeasureCoreSightlines` raycast between aligned room centres at five-stud eye height against the built opaque parts, including furniture; the Exit room and intentional finale were excluded.

| Seed | Built parts | Ray pairs | Longest clear centre ray | Final hall |
| ---: | ---: | ---: | ---: | ---: |
| 101 | 2,858 | 100 | 312 studs | 560 studs |
| 7,331 | 2,966 | 100 | 339.5 studs | 560 studs |
| 65,537 | 2,882 | 100 | 338.5 studs | 560 studs |
| 1,900,813 | 2,916 | 100 | 322.5 studs | 560 studs |

The first disposable build passed but left three Level 3 compatibility markers outside its world model; a second build's duplicate-marker assertion caught this test-harness cleanup error. Studio Play was restarted, then each of the four reported builds passed with explicit marker and world cleanup. No failed game build was counted as a pass. Studio returned to Edit, and the post-test read-only audit again matched all 182 scripts.

A separate solo Studio round was launched through the Level 3 lobby station's normal queue with a one-player party. GameManager reached `SelectedLevel=3`, `WorldGenerated=true`, `LoadStage=READY`, `RoundActive=true`, and the Level 3 state `SEARCH`; the player had full health. Its actual active world (seed 1,418,248,411, layout hash `L3-2-39e38f38`) held 26 rooms, 31 links and the 560-stud finale. The same room-centre raycast found 338 studs as its longest clear core sightline. A Client `ProximityPrompt:InputHoldBegin` probe did not activate the first CD, so no pickup or completion assertion is made from that attempt. The only Studio console error was from our earlier invalid manifest probe, not a game script. The disposable round ended by stopping Play.

A second normal solo Level 3 round launched from lobby station 9 and reached `READY/SEARCH` at 100 HP. Ordinary movement and the normal E-hold interaction picked up CD02 at 8.9 studs and CD01 at 8.55 studs; both changed `WORLD→CARRIED`, and the server showed `HeldCDCount=2` and `CDCollectedProgress=2/5` with 100 HP. The Mall Manager correctly remained OFF at 2/5. The CD02 prompt was hidden when the player stood about 4.8 studs behind its table, but appeared after backing to about 8.9 studs, allowing the pickup; this is a usability observation to check in the full route. The character-navigation helper failed to path through the generated maze, whereas ordinary movement crossed rooms and corridors. There were no game-script errors; the only console error came from a test-only invalid state-folder lookup. Play was stopped, Studio returned to Edit, the generated Level 3 world and CDs were absent, and the script count remained 182. No clear, reward or persistent profile write was triggered.

Offline guards passed: 247 sightline checks on 40 seeds, 9,976 square/navigation checks on 232 seeds, and 7,937 first-CD checks on 240 seeds. All 182 mirrored scripts compile with the Studio-matching Luau 0.737 `-O0` guard. The raycast sample covers room centres, not every possible player position; it cannot establish camera feel or the Manager's line of sight in a chase.

## Remaining acceptance

Run a genuine solo Level 3 round from the Level 2 transition through all five CD pickups, CD reader, exit and Mall Manager chase; the normal direct Level 3 round above reached only 2/5. Check actual navigation, prompt visibility beside CD tables, hiding, music and loading under gameplay timing. Record physical phone/tablet streaming, FPS, memory and visible pop-in; a friend has the device checklist in Trello. Publish the verified Studio place and record a Roblox version receipt. Until those checks, [Trello 3hEkFVUe](https://trello.com/c/3hEkFVUe) remains in Testing, not Done. Current published version at this check is v2083; it does not contain this new maze code.
