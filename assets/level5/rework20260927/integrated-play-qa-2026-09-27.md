# Integrated Level 5 DEV Play QA — 2026-09-27

Place `131311258779917`, Studio instance `e7dbf962-5b02-4de6-9494-ef440fb543aa`. The five scoped Studio script writes and source/editor parity checks are recorded in [studio-manifest.md](studio-manifest.md). `Level5DevEnabled=true`; public preview remains false.

## Verified in Studio Play

- Owner UserId `9488575949` saw the E gallery prompt and new F gameplay prompt on `Workspace.ServerLobby.LevelDoorways.Level5SealedDoor`. F was enabled, required a 0.5-second hold and accepted an interaction 3.9 studs from the door.
- F started Level 5 for the owner: `SelectedLevel=5`, `RoundActive=true`, player `InRound=true`, and character position approximately `(17002,24,5)` within the generated world.
- `Workspace.Level 5 Generated World` contained 26,889 descendants, including 18 Window Watcher anchors and a `Level5SectionProgression` folder with seven closed gates. The Studio output showed the normal TunnelLobbyBuilder startup line and no Level 5 errors during this run.
- A player-camera capture at spawn showed generated houses, turf, path and overhead balconies under runtime lighting. The large black playable-preview notice intrudes into the spawn view. The foreground path and facade shapes remain much simpler than reference 01.
- Play was stopped normally; the five live sources still matched their editor sources and their recorded byte lengths and hashes in Edit. The two temporary QA payload folders were absent.

## Integrated geometry QA

An Edit-time integrated build of the same architecture and district sources had 26,194 descendants, eight gameplay zones, ten distinct reference submodels, 134 route waypoints, 18 Watcher anchors and seven gates. Ray checks at 134 waypoints and 201 interpolated positions found no unsupported floor points. These checks do not prove player traversal.

[S06 final foreground](proposal-final-fg-s06.jpg) and [S09 final foreground](proposal-final-fg-s09.jpg) record the latest Edit camera geometry. They are development captures, not acceptance evidence. The ten supplied images have different scenes and must remain separate sections. Major gaps remain in facade detail and proportion, stair cutaway 07, dark opening 06, grass/lighting 09, and spawn framing 01. **The map fails strict 1:1 visual acceptance; publication is blocked.**

## Remaining checks after map fidelity work

Walk and solve all seven section gates in Play, including wrong answers, reset and multiplayer; confirm clue homes remain reachable after facade changes. Then revise the Level 5 queue bay from its current flat fronts to the finished map language, preserve its four stations and DEV routing, and retest lobby passage. Finally obtain a post-change full native place backup, verify source/editor and repository mirror parity, save/publish the existing place, and confirm Roblox reports success. No publication is claimed here.
