# Level 5 puzzle and section playability — source audit, 2026-09-27

## Scope and conclusion

Read-only review of the repository mirror, the seven puzzle definitions, construction and UI code, and explicitly historical native evidence. Studio remains authoritative; this report does not assert that the mirror matches today's Studio state and does not claim a fresh native playtest. No production files or Studio objects were changed by this audit.

All seven puzzles have one internally consistent answer; their generated indoor clue labels and diagrams use the same server definition. Gates are ordered, answers are server-validated, failures permit free retries, and the current cursor/backdrop fix remains in source. A–G appear suitable for a fresh native playthrough. H is traversable ending architecture but has **no completion or slide gameplay**, so the full level cannot yet be approved as a completable public experience. The existing developer-only preview restriction is deliberate.

## Exact solutions, destinations and clue homes

Positions below are **local to the Level 5 origin**. Current source origin is `(17000,24,0)` (Round Adapter line 20). Add it to get world positions. Read positions are historical supported root positions from the v2139 `final-map-audit.json`, not new walk results. They are useful QA staging locations, not proof of present-day reachability.

| Section / gate | Answer displayed to player | Submission indices | Gate centre | Indoor clue / historical read position |
|---|---|---|---|---|
| A / 1 | RED → YELLOW → BLUE → GREEN | `1,2,3,4` | `(0,0,196)` | `ResidentialAtriumStack_-1_1.ClueHouse_1` `(-128,3,42)`; `ResidentialAtriumStack_-1_3.ClueHouse_2` `(-128,3,156)`; `ResidentialAtriumStack_1_1.ClueHouse_3` `(128,3,42)`; `ResidentialAtriumStack_1_3.ClueHouse_4` `(128,3,156)` |
| B / 2 | LAMP → CUP → KEY | `2,4,1` | `(88,0,456)` | `ArcadeCrossLaneHome_1_0`, `(0,3,288)` |
| C / 3 | RED **2**, BLUE **6**, YELLOW **4** | `3,7,5` | `(-120,0,936)` | Red: `PastelCourt_1.CourtHouse_1_3_0` `(-229,3,545)`; blue: `CrossStreetCottage_-1_2_0` `(-140,3,715)`; yellow: `PastelCourt_4.CourtHouse_4_2_0` `(145,3,909)` |
| D / 4 | UP → DOWN → UP | `2,1,2` | `(120,0,1296)` | `FloralTowerHome_1_1_0`, `(125,3,994)` |
| E / 5 | 3:00 → 9:00 → 6:00 | `2,4,3` | `(-120,0,1596)` | `EastCrossLaneRoom`, `(100,3,1390)` |
| F / 6 | CH04 → CH07 → CH02 | `4,7,2` | `(178,0,2076)` | `WestContinuousDwellings.TelevisionClueResidence`, `(-66,3,1743)` |
| G / 7 | RIGHT → DOWN → UP | `2,3,1` | `(-65,0,2456)` | `OuterGardenResidence_-1_2_0`, `(-232,3,2290)` |
| H | No eighth puzzle | — | — | Final house entrance `(0,0,2584)`, right/forward/left dogleg, descent starts `(0,0,2615)`, enclosed arrival around `(0,-29,2674.5)` |

The C digits are **2/6/4**, not 3/7/5: its option array starts at the label `0`, so numeric submission indices differ from printed values. Catalog lines 10–16 are the source of all seven answers. Architecture lines 615–627 define the four A houses; lines 697–709 define section bounds and all gate frames. Progression lines 305–348 select later clue homes and render answer-derived pictograms, order labels and text.

## Required route and native checks by section

| Section | What the current source intends | Required fresh native checks |
|---|---|---|
| A | Ground-level four-house search around central residence; balcony exploration is optional for the puzzle. | Spawn floor; all four real entrances and clue faces; return to gate without crossing locked boundary; normal wrong/correct colour input. |
| B | Alternating covered side lanes around cross-lane homes. The clue is in the first centre home. | Follow left/right route, enter clue house, read panel, exit without snagging porch geometry; symbols wrong/correct input. |
| C | Large four-court village, three widely separated address clues. | All three distinct homes and return routes; colour + written label readability; enter printed digits 2/6/4; no closed-gate bypass. |
| D | At-grade side promenades and a twelve-stud sunken street connected by stairs; clue on east raised promenade near entry. | Walk between both grades without jump forcing; approach clue from promenade; cross-street rails and exit stair; switches wrong/correct input. |
| E | Turns through and around nested domestic rooms; clue in east cross-lane room. | Clear door lintels, partitions and furniture; clue readable from inside; clock hand/label agreement; wrong/correct input. |
| F | Multi-height atrium main route: west ledge down, cross at −14, east stairs to +14, offset bridge, west stairs to departure. Separate pit-recovery path. | Full 28-point main route; 12-point recovery; clue doorway at local y0; gate5/6 thresholds; no falls trapping player; actual TV inputs. |
| G | Raised west/east terraces connected by stair crossing; arrow clue is in an outer west **ground-level** garden home. | Detour to west garden clue plus route back to gate; terrace ascents/descents; tilted decorative houses remain closed; normal arrows input. |
| H | Quiet court, last house, offset vestibule, four painted direction decals, enclosed two-slope descent; tracking ceiling eyes. | Last gate causes no outage; H/chute stay lit during earlier outage; arrow direction/visibility; actual dogleg and chute traversal; return-to-lobby works. Completion cannot pass until separately implemented. |

The ordered route is exposed by the Architecture manifest (`RouteWaypoints`, lines 875–925); F replaces only its route span and also exposes `FRescueRouteWaypoints` and `FClueRouteWaypoints`. Do not replay the historical old F ground route as the current route.

## Logic, readability and input findings

- **Ordered, shared progression:** prior gate must be `FullyOpen` (Progression 156–161); physical leaves tween for 1.6 seconds, then disable collision and set `FullyOpen` only after both finish (175–184). A solve updates shared state once and closes other participants' UI for that gate (162–174).
- **Authoritative submissions:** selected level 5, active round, living participant, distance ≤14 and unobstructed ray required (Colour Lock Logic 21–26; Progression 141–154). Session nonce, elapsed time, exact answer shape/range and gate order validated (Catalog 42–76). `Public()` contains presentation and starting values only, not solutions (33–40).
- **Retry behavior:** wrong/malformed answers keep UI and send an error line; other invalid sessions close (Progression 381–400). Client button rate is 0.7 seconds, server 0.65 seconds. Session closes after 120 seconds or moving >14 studs; reopening starts a clean attempt (Client 175–209, 248–263, 294–300). No attempt fee, damage or permanent lockout is implemented.
- **Cursor/backdrop:** UI sets `Level5ColourLockOpen` during opening (Client 255); RoundUI responds to the attribute and maintains free visible mouse while modal is open (RoundUI 913–931, 990–1004). `ModalInputBlocker.BackgroundTransparency=1` (Client 89–94) leaves the world undimmed. The close button is also `Modal=true` (116). Teardown clears the shared flag on death/character replacement/external GUI destruction (175–195, 303–306).
- **Cross-device source behavior:** selectable controls use `Activated`, deliberate navigation links, gamepad focus and B close; E/ButtonX proximity prompt; real native phone/controller validation is still required. UIDevice recognizes `Level5ColourLockOpen` among screen-owning modal attributes (1645), and maintains touch suppression through its modal watcher (1931).
- **Clue interpretation:** all clues show written labels as well as pictograms. Colours include distinct symbols and numbers. Address plaques include RED/BLUE/YELLOW text. Clock faces have numeric times below them. Arrows have textual directions below rotated house diagrams. No colour-only or pictogram-only inference is mandatory.
- **No exterior HOUSE CLUE tags:** current Progression does not construct those signs. Older dense-routes documentation still says it does; `LEVEL5_SURFACE_UI_FIXES_2026-09-26.md` supersedes that historical statement. Indoor clue boards remain intentionally present.
- **Prompt visibility caveat:** prompt `RequiresLineOfSight=false` (Progression 280) allows displaying E through nearby geometry, while server `canUse` correctly blocks obstructed activations. This can look unresponsive from the back/wrong side of a gate. A scoped improvement is to enable prompt LOS if fresh native checks show its decorative lock geometry does not prevent legitimate activation. This is a UX candidate, not an evidenced current softlock.

## Limits and risks to report honestly

1. **Not a complete ending.** Landmark 315–334 and 418–459 explicitly provide geometry only, including `GeometryOnly_NoSlideOrCompletion`; Round Adapter 1–5 says it never sets completion/rewards. Its native Build is developer-only (262–265). This is the principal release limitation, not a puzzle-code defect.
2. **Difficulty is dominated by finding the clue homes.** B/D/E/F/G each require copying three ordered marks, but C spans three homes across 480 studs and G's clue is far to the west away from the raised route. Removing forbidden exterior signs makes this search broader. Subtle local source audio or architectural wear can help discovery without reintroducing signs or automatic solution hints. Only a first-time player walk can establish actual search difficulty.
3. **Very short viewport edge remains.** Client 163 imposes panel height ≥248 pixels; a 320×280 viewport with 36px top inset has only 244px usable. Existing layout test flags this limitation explicitly. Normal modeled portrait/landscape cases pass; don't call every screen size tested.
4. **Map instance budget is tight.** Round Adapter 323–324 has a 30,000-descendant guard; v2143 report records 29,928. Avoid adding hundreds of replicated fixture audio objects inside the generated world. Use a bounded client-owned sound pool and reuse sources, or account explicitly for new descendants.
5. **Performance remains unapproved.** Prior atrium record reports 11.85 FPS in F and 6.56 FPS in unchanged A under heavy 8 GB Mac swap pressure. Neither those poor samples nor older better samples establish current controlled performance. New audio must avoid per-frame scans/creation and overlapping unlimited one-shots.

## Verification performed in this source audit

Executed current repository's existing pure Luau tests on 2026-09-27:

- `artifacts/level5-dense-routes-20260926/tests/test_level5_puzzle_catalog.luau`: **PASS: 6,910 assertions**, exhaustive 2,185 combinations over 7 gates. This verifies definition uniqueness/validation, not Roblox UI or geometry.
- `artifacts/level5-dense-routes-20260926/tests/test_puzzle_layout_math.luau`: **PASS: 2,737 arithmetic assertions**,7 puzzles × 9 modeled viewport/safe-area pairs. Known 244px-height limitation remains; this is not a native font/device test.

Historical evidence reviewed separately: v2133 normal wrong/correct inputs on gates 2–7 and separate gate 1 evidence; v2136 actual TV solve and F route/recovery; v2139 closed-gate 18168-ray map audit, 12 clue panels, 1,134 cursor frames and actual B/F room walks; v2143 outage/eye verification with **developer bypass** gate opening. These cannot be relabelled as today's normal seven-puzzle playthrough.

Report author performed no fresh Studio invocation or native input. Root task owns current Studio source export, live audit, sound import and final verification.
