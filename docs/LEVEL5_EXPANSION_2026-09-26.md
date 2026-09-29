# Level 5 expansion, first colour lock and map-wide Window Watcher

Implementation handoff for the changes published as **v2128 on 2026-09-26 at 14:28:41 UTC**, from repository baseline **`208ca1d`**. Before work, root verified all **186 Studio scripts** matched that baseline. This document records the published implementation, completed native checks and coverage limits.

## Result and scope

Level 5 now contains eight substantially expanded indoor neighbourhoods: large residential stacks, small enterable homes, green and beige carpet courts, white balcony circuits, sunken floral streets, low domestic passages and an enclosed final descent. Individual rooms, doors and furniture remain human-sized. The larger footprint comes from new clusters, passages and vertical routes rather than uniform scaling.

Four numbered clues in separate houses support the first real colour-lock puzzle. Seven physical sliding gates divide the biomes. Only the first gate has a normal puzzle; later gates remain closed except for the existing allowlisted developers' explicit bypass. The same passive Window Watcher can now select real windows in every biome, with real visibility checks and the existing local gaze/FOV behaviour.

This remains a **developer-only Level 5 preview**. There is no new main entity, chase, damage, dynamic outage/blackout system, later-section puzzle, completion reward or newly implemented final sliding gameplay. `Level5_MapOnly` remains enabled. The existing finale's architecture is retained. Level 4 is outside this change's scope and must remain untouched.

## Geometry dimensions and contracts

Coordinates below are local to Level 5's origin; the current adapter uses `(17000,24,0)`. The eight ground envelopes total **1,078,800 square studs**, approximately **3.2533×** the previous 331,600-square-stud layout. The widest district spans 560 studs. Ground envelopes run from Z=-4 through Z=2636; the enclosed chute continues to Z=2679.

| District/model | Width × length | Local Z | Shared ceiling | Character and playable elevations |
|---|---:|---:|---:|---|
| A_BalconyAtrium | 320 × 200 | -4–196 | 120 | Six asymmetric 4–7-storey house stacks; ground, 14, 28 balconies; four separate ground clue homes |
| B_LowEavesArcade | 280 × 260 | 196–456 | 50 | Deep covered porches, low cross-canopies and offset through-rooms; ground exploration |
| C_PastelVillage | 560 × 480 | 456–936 | 100 | Four pastel carpet courts, outer residential towers and a 14-stud crossing |
| D_FloralTerraces | 320 × 360 | 936–1296 | 88 | Street floor -12, grade-level yellow promenades, pink stairs and floral wall bands |
| E_DomesticLabyrinth | 320 × 300 | 1296–1596 | 44 | Low side-room ceilings at 16, back passages and three stacked central through-houses; ground routes |
| F_BayWindowCanyon | 500 × 480 | 1596–2076 | 156 | Nested house courts, asymmetric towers up to 9 storeys, continuous 14/28 balconies and eight projecting upper bays |
| G_TiltedSubdivision | 480 × 380 | 2076–2456 | 180 | Stacks up to 11 storeys, eight projecting bays, supported tilted homes and 8/16 terraces |
| H_LastHouse | 220 × 180 | 2456–2636 | 70 | Quiet approach, offset final-house vestibule and physically enclosed black descent |

Shared boundaries have centered **22-stud-wide, 14-stud-high** openings at floor 0. Gate planes are Z=196,456,936,1296,1596,2076,2456. Structural side wings and top closures seal the rest of each boundary, including changes in width/ceiling height. D additionally has below-grade portal foundations so its sunken floor cannot lead beneath an adjacent district.

The final house begins at Z=2584. Chute start is `(0,0,2615)`, bend `(0,-11,2647)`, and endpoint `(0,-29,2670)`; the enclosed black landing ends at 2679. The prior final-house interior, dogleg, arrows, pitch collars and black descent are unchanged except for **+1360 Z translation**. An independent normalized source comparison of final-house construction through `PitchSeamsClosed` matched the baseline at 1e-7 numeric precision. The final dogleg and descent were also physically traversed in the native run described below.

Every house has `Enterable`, world `HouseFloorFrame` at its front-floor origin, and `HouseRoomSize=(width,height,depth)`; interior depth follows local +Z. High decorative homes have real `ClosedPanelDoor` parts. The first reachable balcony levels retain detailed interiors; unreachable closed upper homes omit tiny or invisible decoration to control cost. All actual windows remain Glass, RGB(87,102,102), Transparency 0.2. No house-mounted lights or luminous house panes were added.

Each district exposes local `ZoneMin`, `ZoneMax`, `CeilingHeight`; the builder returns `Zones` with Name, Model, Min, Max, CeilingHeight. SpawnCFrame, PreviewCameras and Waypoints are world-space; ChuteStart/ChuteEnd remain world CFrames. Root model also exposes world SpawnCFrame for diagnostics independent of a module VM cache.

## First puzzle and progression

Four accessible A homes carry `PuzzleClueIndex=1..4` and an interior-facing `PuzzleClueSurface`. Their front-floor locations are west X=-110 at Z=42/156, then east X=110 at Z=42/156. The doors face inward toward the atrium. Each clue is rendered on the actual interior rear wall; its numbered colour word and shape avoid relying on colour alone.

| Order | Colour and symbol | Uploaded clue image |
|---:|---|---|
|1|RED circle|129034114315469|
|2|YELLOW triangle|82053429341504|
|3|BLUE square|98028147005436|
|4|GREEN diamond|73277763916471|

The first gate has a physical padlock/shackle and four numbered red wheel faces. Players use a four-wheel UI to reproduce the clues. The server validates the answer; the client does not receive a solution packet. An incorrect answer allows an immediate retry, with no countdown, resource cost or puzzle reset. Correct submission opens both physical leaves for everyone once, using a 1.6-second tween and collision removal only on completion.

The server validates alive/active Level 5 participation, nonce, exact four-integer shape, request rate, range and line of sight. Developer bypass is a separate hold prompt with server-side `DevAccess.IsAllowed`; it does not count as solving puzzle 1. Later gates are visibly marked as unsolved developer preview and have no invented normal unlock condition. No client bypass remote or reward is introduced.

The client provides selectable keyboard/gamepad controls, touch buttons, readable colour names/shapes and responsive layout. It owns only its GUI/modal flag and yields appropriately to other screens. It closes on range loss, death, leaving the round, another modal, Roblox menu, non-Custom camera or session timeout. UIDevice includes the new modal flag so gaze/camera/touch consumers respect the puzzle screen. Native interaction/layout results and untested hardware limits are recorded below.

## Window Watcher

The existing mesh, white-eye material, rest pose and official animations remain unchanged. The encounter system reuses one passive rig and three tracks:

- WatchingIdle: 123386867650430.
- SlowWindowLean: 85635358459792.
- GlassTap: 85948818863545.

Eighteen curated windows cover all eight districts. Every anchor lives directly in `world.WindowWatcherAnchors`, references an actual queryable tinted pane and has a supported pane-aligned FloorCFrame. Selected rooms are unfurnished. All clips use a minimum 1.90-stud inward depth; native geometry inspection reports approximately 0.085 stud minimum tap-to-pane clearance from the known authored bound.

Selection requires a living active participant outside the pane, 3–145 studs from the face, generally facing the pane. Server head/root direction is an approximation of body view, not the actual camera. One ray must hit the actual pane first; a second ray verifies pane-to-face clearance. These conditions are checked again after warm-up before reveal. The client gaze path resolves the same active pane and actual animated head; existing FOV ownership, accessibility preferences and local disappearance remain in effect.

First appearance timing remains 2–4 seconds when a valid view is available, visible duration 8–14 seconds and gaps 18–35 seconds. Windows avoid immediate repeats and gestures rotate. Hidden scans are bounded; only one rig appears at once. No combat, movement AI, chase or damage was added.

## Native state observed so far

Root reports the final native static geometry check passed with **zero issues**:

| Metric | Final runtime observation |
|---|---:|
|House models|323|
|Enterable / closed houses|140 / 183|
|Tinted windows|694|
|Actual lights|49|
|House lights / house Neon parts|0 /0|
|Furnished homes|18|
|Runtime BaseParts|20,430|
|World descendants|21,749|
|Adapter instance cap|23,000|

All 140 enterable homes passed sampled native entry/floor/head rays reported by root. This is not a claim that a player physically walked all 140 homes or every point in each interior. The saved native Watcher geometry report validates all 18 anchors across 8 districts: real supporting floor, actual-pane visibility, interior clearance and usable front-side viewpoints. It records 402 rays. These generated viewpoints are candidates, not proof that a character traversed every approach.

`native-watcher-all-biomes.json` confirms an actual single-player client appearance in **all eight districts**. Each case recorded 14–22 rendered samples, an official animation track advancing by approximately 1.44–2.35 seconds, and a visible FOV effect. All three existing gesture assets were represented across the cases. The A case, for example, recorded 15 rendered samples, 1.546 seconds of advancement and FOV 68.52–70.45 degrees.

This was an explicit QA procedure: teleport the real player between separate validated viewpoints and restart only the owned encounter controller at each, then wait for its production startup delays and animations. It used one actual player and no synthetic viewers. It was not a connected traversal of all encounter viewpoints, an uninterrupted natural eight-district schedule, or a two-account/multiplayer test. Local gaze-disappearance, blocked/away cancellation and warm-up edge cases must not be inferred solely from these rendered samples.

The native movement log `native-main-routes-first-pass.json` records a real player's Humanoid walking the main route through all eight districts, all four clue-house interiors, G's raised terrace loop and the final house/dogleg/chute. Movement used normal MoveTo, without teleporting, jumping, changing WalkSpeed or altering gates inside the movement helper. Two initially supplied A waypoints struck a stair-side railing or column; the route was corrected around the existing architecture and continued successfully, with no geometry edit. An approximate G stair waypoint exceeded the initial four-stud height tolerance by 0.105 stud because the actual tread was 0.5 stud above its assumed height. The run continued with a five-stud tolerance and completed. The saved log retains those unsuccessful first attempts; it must not be described as thirteen uniformly passing runs or every optional side route being walked.

A later optional-route run found a real A obstruction: the rear railing of the first cross-bridge crossed the approach to the upper flight at X65/Z106. The Architecture module now leaves a sixteen-stud opening from X57 to 73 while preserving the remaining railing. After rebuilding, `native-atrium-balconies-final.json` passed **15/15 waypoints** over approximately 598 studs with normal Humanoid movement, including both balcony levels. This fix removes four net BaseParts, producing the final counts above.

F's initial optional crossing targeted a visible structural column. Detouring its waypoints around the column required no geometry change; the continuation passed **19/19 waypoints** over approximately 745 studs through the upper/lower balcony circuit. `native-optional-routes-before-railing-fix.json` retains the initial A/F failures and the successful F continuation. These are sampled traversal routes, not full-volume coverage of every room or all optional paths.

Root exercised the actual first-gate E prompt and wheel UI: RED/RED/RED/RED returned retry feedback and left the gate closed; real wheel clicks then set the correct order and produced shared SOLVED state with both leaves noncolliding. All six later gates were opened with the actual held F developer-bypass prompt. This establishes these normal and developer flows. Pure puzzle tests cover malformed answers and participation/range/line-of-sight predicates. Puzzle nonce/expiry/rate checks and idempotent gate handling were source-reviewed but not separately fault-injected; the mocked lifecycle tests below cover the Watcher.

The first native UI inspector found a small three-pixel overlap between the help area and Close control. The client layout was corrected. `native-final-ui-layouts.json` then reports **PASS with zero issues in all five native simulated viewports**: desktop 1053×678, iPhone portrait 401×777, iPhone landscape 749×361, Galaxy landscape 705×338 and iPad landscape 1375×1030. Text-fit, control bounds and overlap checks passed; mobile simulations reported touch enabled. These are Studio device-layout results, not physical phone/tablet or full gamepad play sessions. `native-clue-images-final.json` also confirms all four actual client clue ImageLabels had `IsLoaded=true` and `BackgroundTransparency=1`.

`native-performance-canyon.json` records a 15.01-second native Studio-client sample at an F viewpoint, quality level 10 and viewport 1053×678: **57.60 FPS**, median 16.66 ms, p95 **18.21 ms**, p99 21.53 ms across 867 frames. Three intervals exceeded 33.3 ms and one exceeded 100 ms; the single maximum interval was 599.92 ms and root associates it with screenshot capture. Whole-client memory was 5491.94–5496 MB. The client reported 18,924 streamed instances at this view, which is distinct from the full server world count. These are observed render intervals including Studio/OS/capture load, not GPU-only timings, a published-server benchmark or a physical-mobile result. The A sample below supplies a second view; other unvisited views and multiplayer load remain unmeasured.

`native-performance-atrium.json` adds a second 15.01-second Studio-client sample at the A arrival view, quality level 10 and viewport 1053×678: **59.99 FPS**, median 16.65 ms, p95 **18.93 ms**, p99 20.51 ms and maximum 22.98 ms across 901 frames. No interval exceeded 33.3 ms. Whole-client memory was 5425.30–5424.47 MB; 8,068 client-streamed instances were present. The same Studio/OS, viewport, streaming and physical-mobile limitations apply to both measurements.

A fresh round reset `Puzzle1Solved` to false. Native source compilation passed **189/189 scripts with zero failures**. After a real lobby return, the 5.5-second observation showed player `InRound=false`, puzzle modal false and FOV restored to 70 while the world/remotes were still awaiting the existing GameManager cleanup delay. The settled **10-second** result in `native-lobby-cleanup-settled.json` then confirmed world absent, remotes absent, RoundActive=false, InRound=false, Level5 phase IDLE and recorded world descendants 0. The server's new-entry hook was true. Delayed retention at 5.5 seconds was therefore not the final cleanup state.

Root's final rebuilt geometry check again reported zero issues and a **0.39-second build**, with 20,430 BaseParts/21,749 world descendants. The initial unoptimized isolated build took 1.538 seconds and contained 23,080 descendants; that earlier timing is retained only as development context, not substituted for the final measurement. These build durations are observations on this Studio machine, not a hardware-independent guarantee.

Local logic checks reported by the contributing agents:

- Colour-lock logic: 328 assertions, including all 256 candidate sequences and malformed/inactive/range cases.
- Watcher scheduler: 1,031 assertions across 200 cycles.
- Watcher selection: 31 assertions plus 1,000 deterministic weighted choices.
- Mocked Watcher lifecycle: 42 assertions including failure rollback and cleanup.
- Native compilation: 189/189 scripts, zero failures. These checks do not establish physical mobile usability or multiuser play.

## QA coverage limits and delivery receipts

Completed acceptance covers the native structural checks, the main route through eight districts, four actual clue-house visits, A/F balcony circuits, G terraces, final dogleg/chute, real wrong/correct puzzle interactions, six later developer bypasses, fresh-round first-lock reset, all eight staged Watcher appearances, five simulated UI layouts, two desktop performance views and settled lobby cleanup described above.

Coverage limits remain explicit:

- All 140 enterable homes had sampled structural rays; only the named traversal routes and clue interiors were physically walked. Unvisited side paths and full-volume interior coverage are not established.
- Watcher cases used one actual player, QA teleporting between viewpoints and restarting the owned controller. They are not a continuous natural traversal/schedule or full two-account multiplayer acceptance. Warm-up/blocked/away/local-disappearance edge cases are not proven solely by rendered sample counts.
- Phone/tablet checks used Studio device simulation. Physical hardware, mobile performance and a full gamepad session were not tested.
- Performance samples cover A/F at quality 10 on this Studio desktop. Other views, real published-server load and multiplayer performance are not established.
- Malformed answer and participation/range/line-of-sight predicates have pure-test coverage. Puzzle nonce/expiry/rate checks and idempotent gate handling were source-reviewed, not separately fault-injected. The mocked lifecycle tests are Watcher-specific.

Release records:

- **189/189 scripts** freshly exported with exact Source/editor/repository parity; ten scoped sources include three new scripts. All 179 unrelated existing sources, including all twelve Level 4 sources, match the pre-task baseline exactly.
- Final native compile after the railing fix: **189/189**, no failure or unstaged source.
- Published to place **131311258779917**, universe **10559217407**, as **v2128** at **2026-09-26T14:28:41.849Z**. Native Studio reported PublishSuccessful, Place published and the v2128 notes link. See `artifacts/level5-expansion-20260926/publication-v2128.json` and `publication-log.txt`.
- Full native before/after backup receipts are in `artifacts/level5-expansion-20260926/native-backups.json`. The after binary is committed as `after.rbxl` (9,771,701 bytes; SHA256 `5dcf3faf4ec3d9fdfd6e7d5a3c10cdd833a57014632d375365e435bafdd6c0d4`). The fresh before-copy matched the prior `after-gaze.rbxl` byte for byte, avoiding a duplicate binary.
- Review branch: `codex/level5-window-watcher`; [PR #10](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/10), stacked on the existing QA branch. The commit containing this handoff records the release sources and evidence.
- [Level 5 Trello card](https://trello.com/c/Y2xXThBN): current expansion/colour-lock/Watcher checklist; the overall level remains In Progress for later puzzles, the main entity, outage, controlled sliding and completion.

## Files and evidence

Geometry sources: Level 5 Architecture, Neighbourhood Districts and Landmark Districts. Gameplay additions/updates: Colour Lock Logic, Section Progression, ColourLockClient, Round Adapter integration, Window Watcher Encounters, WindowWatcherGazeClient and the single UIDevice modal-list addition. The existing furniture module and native rig assets are reused.

Committed evidence is under `artifacts/level5-expansion-20260926/qa/`; portable pure tests are in its `tests/` directory. This includes native movement (with unsuccessful initial attempts retained), all-eight-biome Watcher appearances, five UI layouts, loaded clue assets, performance samples, fresh-round/cleanup records and the complete source comparison. Run the `.luau` tests with a Luau CLI; the Python lifecycle harness takes that CLI's path as its first argument. QA inspection modules are opt-in native Studio helpers and are not installed in the live game.

The four original RGBA clue drawings and upload/alpha/hash receipts are in `assets/level5/colour-lock-20260926/`. The runtime sources are mirrored in their normal Roblox service directories. Temporary localhost bridge payloads, duplicate complete source exports, caches and task-only installers are excluded from the release.
