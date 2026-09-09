# Pool Slide regression fixtures

These isolated, table-only Luau fixtures test the actual production source without
changing a Studio DataModel. It needs Roblox value types and Edit-time
`loadstring`/`setfenv`; do not enable server LoadStringEnabled to run it.

Compile `controller-fixture.luau` and call the returned function with the source
string from `ServerScriptService/Level 2 Systems/Level 2 Pool Slide Controller.ModuleScript.lua`.
Compile `navigation-fixture.luau` and call its returned function with the source
string from `ServerScriptService/Level 2 Systems/Level 2 Pool Foam Navigator.ModuleScript.lua`.
Both return Passed, Total and per-case results. Run each against the exact source
installed in Edit Studio; native compilation alone is not a behavior test.
The current second-pump source passes43/43 navigator,41/41 controller,
15/15 audio and27/27 dev-pump checks:126/126. The earlier navigation-only
revision was published as version1699; see SECOND_PUMP_VERIFICATION.md and
studio-sync-manifest.json for this update's publication.

Current controller coverage includes second-distinct-pump latching, no first-pump
spawn, no third-pump duplicate, activator focus, count jumps, cancelled async
spawns, generation replacement, private-candidate cleanup, minimum participant
distance, nearby-visible candidate priority, strict body-route certification,
24-stud visible spawn approaches, paused-spawn discovery, pause/resume and server attack eligibility,
5.5-stud reach, vertical separation and line of sight.

Navigation coverage includes route retention, target hysteresis, delayed async
results, safe live-foot joins, long dense routes, full-body-certified shortcuts,
internal loop removal, necessary wall detours, failed replacement retention,
certification budgets, different-floor targets, partial reachable approaches,
three-second obstruction rechecks, cleared-obstacle resumption, timeout recovery,
Stop cancellation, legacy navigator compatibility, and actual Step at30/60FPS.
Controller cases also check slow planning versus watchdog recovery and safe waits.

Additional fixtures: compile `audio-fixture.luau` and call with the Level 2 Sound
Controller source; compile `dev-pump-fixture.luau` and call with Objective
Controller source. The audio fixture runs the real LocalScript with mocked audio
services. The dev fixture exercises the real public method and pump actuator
using a minimal test-only session initializer, not unrelated flume construction.
See SECOND_PUMP_VERIFICATION.md for the current run counts and live integration.

`live-navigation-probe.luau` is an opt-in disposable **Play-only** Script for the
requested seed202/resolved2199511 generated world. Build that world through the
normal Round Adapter first. It clones the unchanged entity, uses real geometry,
real pathfinding and Heartbeat, runs six measured paths, and records JSON in its
Result attribute. Stop Play afterward; never persist this test Script to Edit or
publish its isolated test setup. For seed101, use nodes1/2 and30/31 plus same-hall
offsets; node41 does not exist on all layouts. This probe is not a production
controller test; the separately recorded third-pump integration provides that.

Live integration was additionally checked through the authentic Level2 queue and
production-valid pump interactions. See the asset folder's IMPLEMENTATION_STATUS.md.
For the pathfinding investigation, results and physical-clearance limits, see
`assets/level2/poolslide/NAVIGATION_VERIFICATION.md`.
Single-client Studio tests are not a multiplayer or device load test.
