# Native phone live-round follow-up

Current candidates (no Studio calls):

- `ReplicatedStorage/UIRegression.ModuleScript.lua`: physical alive-round gameplay admission; joined compass baseline; passive shared Caption/Feed activation-region check; captures, restores and clears `RoundEndingOpen`. Actual interactive LeaveHiding, Spectate and results checks remain.
- `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`: reserves the visible actual RoundExitGui.LeaveChipTouch through UIDevice coordinate conversion; observes visibility/geometry/new mounts; checks extra obstacle edges after the four authored positions to retain DEV reachability.

Validation: UIRegression shared runtime 87 PASS with unchanged real extracted source/Framewisp fixtures and compile PASS. DEV chip runtime 37 PASS. Store compact suite 777 PASS against all 9 actual modal attributes. ZyntraStore compile PASS. The before-door candidate fails the new actual 44px door-exclusion assertion.

The old logs are different device modes: phone-live-l4 is native touch=true; phone-final-lobby is desktop touch=false after emulator keyboard/mouse changes. Live RunAll's gameplay showed lobby rail while clearing local InRound during a real RoundActive. Four compass failures measured baseline against its joined bearing. Passive caption and feed activation collisions were reported as input collisions although they have no active input descendants. Remaining interactive/real-control findings require product fixes and native retest; they are not exempted.

L4 note after RunAll: the harness switches client-local InRound/SelectedLevel, stopping and restarting L4 client private connections/visuals. It never writes RoundActive. Its restore cannot recreate a previous private note interaction. Actual server note prompt requires SelectedLevel=4, RoundActive=true, InRound=true, Escaped not true, alive root, Enabled prompt and distance <= MaxActivationDistance+2.5 (default 12.5 studs). Server Cleanup destroys runtime and sets Level4RoundActive=false. Check actual server/client flags, root-to-anchor distance and client ProximityPromptService.Enabled before native E; do not infer server stop from missing note alone.

`door-and-live-harness-proof.json` records exact ready hashes. Root owns installs and real native validation.
