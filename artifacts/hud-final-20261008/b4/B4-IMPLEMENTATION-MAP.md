# B4 implementation map

Read-only source audit, 2026-10-09. This map follows BUILD-PLAN Â§04/B4 and FRAMEWISP-PIPELINE. Actual current sources and imported fixtures take precedence over historical line counts. The existing graphify graph was consulted first; it contains historical artifact copies, so every contract below was checked in current source. No Studio state, product source, lock, or git operation was changed while preparing this map.

## Ownership and shared contract

The four objective clients retain their gameplay/replication decisions and send the exact plain-table contract to the shared `RoundHud` module:

```lua
RoundHud.SetObjective({
    Level = 3, Eyebrow = nil, Title = "FIND THE CDS",
    Count = 2, Goal = 5, Tag = "CDS IN THE PLAYER",
    Lines = {"Follow the compass to the next CD."},
    Status = {Text = "Main breaker: fuse 42 s", Kind = "warning"},
    Compass = {State = "locked", Target = Vector3.new(0, 0, 0)},
    Done = false,
    OnOrderActivate = nil, -- optional local callback; Level 4 note reopen only
})
```

`Lines` has at most two sentence-case strings. Optional counter, status and compass parts disappear without reserving space. `Status.Kind` needs warning (Amber), danger (Coral) and positive/held (Sage). Compass modes are locked, calibrating, inRoom, locating or nil; arrival applies to exit objectives only. PLAYER is a Level 3 receiver decision, expressed through the normal title/guidance and locked CD-player target. Do not add gameplay fields to this table or change server contracts.

Shared module owns template drawing, semantic state diff, attention, touch expansion, compass rendering, device remount, spectator eyebrow and last-objective snapshot. Invalid/local inactive level publishers must not clear another level's card. Prefer a selected-level gate inside SetObjective, and an owner-scoped clear if needed; global Clear is round teardown, not something all four clients call on their periodic inactive ticks. `LastObjective` must retain the stable latest snapshot through Clear for B8. A live Vector3 target or countdown changing each tick must not extend the six-second attention window forever; semantic changes are title/count/goal/guidance/status-kind/phase, while bearing/distance and timer display refresh independently.

One valid subject rule is needed everywhere: when Spectating is true, resolve SpectateTargetUserId to an alive InRound, non-Escaped watched player; if invalid, do not fall back to a parked escapee's own body. Otherwise use the alive local participant. Compass bearing uses camera look on X/Z; distance uses that subject's root. Level-specific private data (carried fuses, known order) must never be invented for spectators. Update gates immediately on modal/dispatch/round/escape/target changes, not just the next slow timer.

Root owns Round Exit Client/UIRegression/server changes. RoundUI and Spectate belong to another editor. Four objective clients belong to conversation_audit. Shared RoundHud/Round HUD belong to dev_tokens_audit. No concurrent edits to those ownership files.

## Actual imported components

Authoritative fixtures: `tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json`, `framewisp-dump.HUD_Touch.json`; high-fidelity context is in `_local/hud-final/codex-takeover/figma-source/`. Existing scope snapshots are `_local/hud-final/codex-takeover/before/`.

| Bundle/path | Size | Direct fixed parts, in order |
|---|---:|---|
| HUD_PC/ObjectiveCard | 360 x 224 | Head 64, Counter 32, Progress 12, Guide1 24, Guide2 24, StatusRow 24, Compass 44 |
| HUD_Touch/ObjectivePill | 240 x 137 | Bar 40, Progress 24, Guide1 17, Guide2 17, StatusRow 19, Compass 20 |

PC paths: `Head/Eyebrow`, `Head/Title`, `Head/Underbar`; `Counter/Count`, `Counter/CountTag`; `Progress/Track/Fill`; `Guide1/Line`, `Guide2/Line`; `StatusRow/Bar`, `StatusRow/Label`; `Compass/Ticks`, `Compass/Chevron`, `Compass/Readout`. Touch differs: Eyebrow/Title/Count/Underbar are under Bar and CountTag is under Progress. These are the real fixture names, not a guessed common parent tree.

PC track is 328 x 4, compass ticks 196 x 10/readout 124 x 18. Touch track is 220 x 2, ticks 124 x 6/readout 88 x 16. Touch Bar is already 240 x 40 and full expanded stack is 137 high: the requested 80% size is baked into the imported template. Do not multiply by 0.8 again. Mount already floors touch text at 12 and left-anchors *Fill. Nine ticks cover -60 to +60 at 15-degree intervals.

Implement `Stack(bundle, path, parent, opts)` as described in the pipeline: copy root appearance into an outer code-owned auto-height container; mount every direct part at original fixed geometry through Mount, return parts by name, and hide unused parts. Do not stretch mounted roots. `Paint` only changes Eyebrow, Underbar, progress Fill and Compass Chevron to level accent; status/done/spectate state paint follows. Templates have a dark root gradient rather than a pre-existing objective Soft node. No image assets, UI redraw fallback, Figma reimport, or product design substitute is required.

PC stays expanded at UIDevice.TopRightPanel(360, height). Touch starts with Bar at 40 high plus a transparent >=44 hit target, expands on semantic change/tap for six seconds, and uses TopRightPanel(240, expandedHeight) above controls. Never solve insufficient space by shrinking text or double-scaling the template. Danger never dims; ordinary state rests at 45%; done counter/fill are RailTeal during attention. IN THIS ROOM is static Coral. ARRIVED is under 8 metres and reads AT THE EXIT. Metres = studs / 3.571.

## Receiver contracts and retirement boundaries

### Level 1 â€” PuzzleUI

Current input is `ReplicatedStorage.Remotes.PuzzleStatus.OnClientEvent`, gated by local InRound. Server `Level 1 Systems/PuzzleManager` emits begin(total fuses, box goal), boxes(done, goal), carry(private count), levers(goal), lever(active, total, seconds, latchMode), exit, escape(player name), private msg and team(actor, kind, detail). Lever timing is legacy: current latched levers stay on and no countdown should be introduced. No server protocol change is needed.

Keep the existing leverPhase/active/total/latchMode state and add ordinary box count/goal variables because the old labels currently store those values. begin/boxes => RESTORE THE POWER, FUSE BOXES a/b, guidance selected by carried count. levers/lever => PULL THE LEVERS, count a/b. exit => GET OUT, no irrelevant box counter, locked target workspace.ExitPos. An escape event names an individual player; do not falsely declare the whole shared objective complete just because another participant escaped. Preserve private refusal and team event behavior for B5 Feed.

Retire `Level1Objectives`, its labels/progress/toggle/layout and the `ExitEnergyDetector` construction/bearing/layout. Remove LevelOneGuideObjectivesOpen reads and signal. Preserve round event receiver, world/team events, private msg behavior and UIRegression probe seam until ported to the shared state. Do not delete PuzzleGui wholesale before its private/team message surface is moved. Add a SelectedLevel == 1 guard against stale cross-level status; preserve intended active-spectator group view without fabricating watched player's private carried count.

### Level 2 â€” Level 2 Objective UI

Current inputs are workspace SelectedLevel, Level2Pumps, Level2PumpGoal (clamp 1..12/default 3), Level2ExitPowered, Level2FoamLethal and Level2_ExitPosition. InRound and Level2AlertOwnsBand plus dispatch/modal currently hide the panel. Powered => GET OUT + exit target; preserve useful top-deck/flume and climb guidance. Unpowered => START THE PUMPS, PUMP STATIONS n/goal, remaining stations guidance. Only a true Level2FoamLethal produces Coral "The water is no longer safe." Keep danger independent of count/powered transitions. Receiver is attr-driven, with .22 s powered bearing refresh.

Retire the entire old Level2ObjectiveGui/panel and its duplicated bearing renderer; keep signals and state publisher. Shared objective and B5 feed replace AlertOwnsBand's old competing-band layout; modal/dispatch suppression still applies. Actual old-kit round controller/adapter continues to publish the pump contract and run Pool Foam; B4 must support that contract rather than edit its server/map.

The approved new Level 2 map is a separate explore-only preview, not the old pump round: Level2BlenderPreviewButton advertises EXPLORE NEW MAP; Level2BlenderPreviewAccess publishes player.Level2NewMapPreview and disallows normal InRound entry. The model is `Level 2 Poolrooms New (preview)`. It has collision kill zones and an exit slide but no pump-objective contract. `Level2BlenderPreviewActive` selects the old-kit round path and is a different flag. Never invent pumps/entity guidance in the new-map preview, and do not modify the other session's map/server. Gate preview out. No Level 2 chase-edge integration should be added. Root's live Studio baseline remains authoritative if another session changed this recently.

### Level 3 â€” Level 3 Reader Client

`ReplicatedStorage["Level 3 State"]` is authoritative, with selected legacy workspace mirrors. World model is `Level 3 Generated World`. Goal is Level3_ModuleGoal / Level3ModuleGoal, progress is Level3_ModuleProgress / Level3Modules (inserted count, not total ever collected), unlocked is Level3_ExitUnlocked / Level3ExitUnlocked, target is Level3_ExitPosition. Per-CD state/room/position are Level3_CD<n>State/Room/Position, and player room drives same-room detection. WORLD/DROPPED CDs are targets; CARRIED/INSERTED are not. Nearest is planar. Preserve the existing same-room rule and reusable buffers.

Newer work absent from the old BUILD-PLAN is essential: readerTargetMode chooses SCAN, PLAYER when every remaining CD is CARRIED, and EXIT after all inserted/unlocked. PLAYER uses Level3_CDPlayerPosition / Level3CDPlayerPosition and a bounded one-second cached streamed fallback for the DiscPlayerControlPanel marker. Preserve CD PLAYER/INSERT CDS direction after everyone carries the discs. SCAN publishes FIND THE CDS, inserted n/goal, nearest CD target with inRoom state when applicable. EXIT uses calibrating until unlocked, then locked exit; do not reveal precise locked exit bearing early. No blink/pulse survives the shared inRoom rendering.

Retire ReaderPanel/ReaderRestore drawing, R/ButtonY toggle, touch restore chip, old pointer/ticks/noise renderer and old panel-focused probes; retain signal acquisition, generation-guarded ClientEvent (Alert, ModuleCollected, CDInserted, CDDropped, CDTransferred, ExitUnlocked), state helper, nearest-CD/mode logic, streamed player locator, audio/input behavior and idempotent teardown. Existing active gate includes subject Level3_Hiding, dispatch/modal and valid spectator; preserve immediate suppression parity. Shared card supplies objective display/compass, not new gameplay.

Preserve `CD_HINT_20261008` ReaderHint: once per world, 10 seconds; hidden for spectators/loading/toast/modal and fixtures unless DevReaderHintInFixture; stops on inserted progress/unlocked. Adapt its measured anchor to RoundHud.ObjectiveCard's actual AbsolutePosition/AbsoluteSize and local GUI origin. Its `MOBILE_QA_20261008` placement must still measure LeaveChip's actual right edge, use the beside strip down to 170 wide on phones, and move under the chip when no strip fits; it takes no input. Do not retain a hidden legacy ReaderPanel solely as a fake measurement surface.

### Level 4 â€” Level 4 Round Client

World is `Level 4 Cinema Blender`; replicated folder `Level 4 State`; remotes `Level 4 Remotes`. roundLive requires SelectedLevel 4, RoundActive and Level4RoundActive. Preserve render/event startup for a valid spectator as well as own participant; compass and private chips must use the watched subject when spectating.

Phase Dark => RESTORE THE POWER; Level4_SequenceProgress/Goal (default 4), player.Level4_NoteOrder optional. Known order line reopens the existing note through optional OnOrderActivate. Reels => LOAD THE PROJECTORS, Level4_ReelsLoaded/ReelGoal (default 3); player.Level4_ReelsCarried => "You carry n reels."; retain Level4_ReelRooms pipe parsing, stable first occurrence order and duplicate x2. Status priority: Level4_BreakerHolder => DisplayName/Sage; else Level4_FuseUntil minus server time => warning Amber; else off in service room => danger Coral. Finale => GET OUT, Level4_ExitPosition at Cinema 2 screen and shared metre distance. Keep collected and loaded counters distinct.

Only replace old ObjectiveFrame/labels, HIDDEN/CARRYING chip surface and refreshPanel's drawing output. Do not touch TORCH_GLINT_20261008, REEL_ROOMS_20261008 state, zone lighting/screens/films, reduced-flashing/shake logic, title events, usher pose/interpolation/buffers, flashlight checks, camera/audio timers, or round start/stop. Preserve MOBILE_QA keypad/note safe placement and Level4CardOpen publishing; remove only old objective placement hunk. B7 later restyles the same note/keypad instance interactions through imported templates without replacing their gameplay callbacks.

## Required companion retirements (other owners)

RoundUI: remove objectivesButton construction (~2322..2408), ObjectivesPanel/title/close/divider/body/layout/objectiveCopy (~2411..2583), objectivesAvailable/refreshObjectivesButton/setObjectivesAvailable (~2699..2758), toggleObjectives/OBJECTIVES_ACTION and H/DPadUp binding (~3001..3035), help-specific layout (~3131..3230), and all setObjectivesAvailable callers. Keep LevelOneGuideGui/Sounds/subtitle functions. Its dispatch inputBlocked/refresh no longer reads LevelOneGuideObjectivesOpen. Preserve subtitle sizing intertwined in the old layout. Later caption placement and listeners currently inspect Level1Objectives/ReaderPanel (~3307,3804..3810,3942..3954); move to measured shared ObjectiveCard, not obsolete GUI waits.

Round Exit Client: remove LevelOneGuideObjectivesOpen gate/signal and all PuzzleGui/Level1Objectives coupling. Retain Level4CardOpen/PartyDown/modal/gamepad/hold behavior. UIRegression must port obsolete help/reader hidden/restore rows and objectiveColumn to one shared RoundHud.ObjectiveCard; preserve LevelOneGuideGui where it still represents subtitles. Actual GUI state is test oracle: execute_luau's separate module context is not the player's cached module.

## Verification plan

Shared module owner: extract real semantic-diff/compass helpers into offline Luau tests; cover clamp Â±60, behind edges, metre conversion, exit-only <8 arrival, watched origin and invalid-target no fallback; warning fades, danger never fades, done tint; six-second auto/tap expansion; imported fixed part widths/heights and touch >=12, Hit >=44; accent path differences PC/touch; stale inactive publisher cannot erase selected objective; Clear preserves LastObjective; device remount leaves one card/one hit/subscription.

Client owner: use real receiver/helper code where feasible, not a mirrored implementation. Level1 begin/carry/boxes/levers/lever/exit/reset and team refusal; Level2 goal bounds, zero/partial/complete and lethal independent status, preview gate; Level3 WORLD/DROPPED/CARRIED/INSERTED nearest/mode progression, no-CD locating, exact player marker with streamed fallback, same room static, exit calibrating/unlocked, generation filter and hint measured placement; Level4 Dark known order callback, Reels loaded-vs-collected/carry/room duplicate formatter, held/fuse/off priority, Finale watched target, retained glint/round handling. Compile all touched Lua and run meaningful existing regression tests.

Existing test seams: test_level1_team_prompts.py and test_level3_first_cd.py touch receiver helpers; test_round_exit_hold.py and test_ui_style.py need old GUI needles ported by their owner. test_spectate_parity.py tests audio only, so do not claim it verifies objective compass. test_level3_first_cd_prompt.py tests server hide-table prompt, unrelated to ReaderHint. UIRegression old Level1/Level2/Level3 measurement/probe rows must move with B4. Live QA per level on PC/touch/pad, active plus watched subject, status and template geometry remains required after root installs; this audit does not claim live QA completion.
