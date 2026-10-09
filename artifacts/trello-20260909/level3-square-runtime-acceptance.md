# Level 3 square layout: bounded native runtime acceptance

Prepared 10 September 2026 from the actual Round Adapter, Manager, Objective, Music, Test Suite, Level3Generator and GameManager sources. Commands are for root to run in an already-running normal Play. This agent did not run Studio or change source. Existing 104-seed plan tests and geometry probes need not be repeated here.

## Actual entry and lifecycle APIs

There is **no exported DebugBuild or StartRound** in the current L3 adapter/GameManager. The production route is GameManager's local `ensureWorld()` → `require(ServerScriptService.Level3Generator).Build()` → `Round Adapter.Build()`. The compatibility module exposes only Build/Cleanup. Adapter.Build returns the World model; **Adapter.GetManifest()** returns the live manifest. The adapter also starts Objective/Hiding/Music and binds Manager creation to the hunt authority. A raw WorldBuilder.Build shadow does not exercise these owners.

Use a normal lobby queue with Level 3 selected, after the three updated sources have been pushed and a fresh Play has cleared require caches. A direct Level 3 launch uses the existing seven-second service-elevator countdown. GameManager owns player InRound, RoundActive, loading barriers, win handling and cleanup. Do not manually set those flags or call Adapter.Cleanup while its normal round is active.

Before launching from the lobby, capture the existing suite's restoration baseline:

```lua
local s = game.ServerScriptService["Level 3 Systems"]
_G.TrelloL3QA = {
    Adapter = require(s["Level 3 Round Adapter"]),
    Suite = require(s["Level 3 Test Suite"]),
    Manager = require(s["Level 3 Mall Manager AI Controller"]),
    Objective = require(s["Level 3 Objective Controller"]),
    Music = require(s["Level 3 Music Sequence Controller"]),
    Config = require(s["Level 3 Configuration"]),
}
local q = _G.TrelloL3QA
q.Before = q.Suite.CaptureLifecycleState()
q.OriginalSeedOverride = workspace:GetAttribute("Level3Seed")
-- Optional reproducibility fixture, ONLY before normal launch:
workspace:SetAttribute("Level3Seed", 101)
return "Lifecycle baseline captured; launch the normal Level 3 queue"
```

After normal entry finishes:

```lua
local q = _G.TrelloL3QA
local p = game.Players:GetPlayers()[1]
assert(workspace:GetAttribute("RoundActive") == true and p:GetAttribute("InRound") == true)
q.Manifest = assert(q.Adapter.GetManifest(), "No normal adapter manifest")
assert(q.Manifest.Layout.Version == 2, "Cached/old layout module")
return game.HttpService:JSONEncode({
    World = q.Suite.ValidateWorld(q.Manifest),
    Runtime = q.Suite.ValidateRuntime(0),
    Seed = q.Manifest.Layout.ResolvedSeed,
    Hash = q.Manifest.Layout.LayoutHash,
    PlayerHealth = p.Character:FindFirstChildOfClass("Humanoid").Health,
})
```

`ValidateWorld` scans the actual generated world; `ValidateRuntime(0)` checks objective mirrors, locked portal and Manager presence matching hunt authority. The named structural/navigation seed sweeps are intentionally omitted.

## Gateways, corners and normal Manager pursuit

List the actual two district connectors and available right-angle room junctions from this manifest, without assuming coordinates from a different seed:

```lua
local q = _G.TrelloL3QA
local m, output = q.Manifest, {Gateways = {}, Corners = {}}
local function xyz(v) return {v.X, v.Y, v.Z} end
for index, link in ipairs(m.Layout.Links) do
    if link.GatewayKind == "District" then
        local corridor = m.Corridors[index]
        table.insert(output.Gateways, {A=link.A, B=link.B,
            Start=xyz(corridor.StartPoint), Finish=xyz(corridor.EndPoint)})
    end
end
for id, neighbours in pairs(m.Layout.Adjacency) do
    local room = m.Layout.RoomById[id]
    for a=1,#neighbours-1 do for b=a+1,#neighbours do
        local ra, rb = m.Layout.RoomById[neighbours[a]], m.Layout.RoomById[neighbours[b]]
        local da, db = Vector3.new(ra.X-room.X,0,ra.Z-room.Z), Vector3.new(rb.X-room.X,0,rb.Z-room.Z)
        if ra.Id~="Exit" and rb.Id~="Exit" and math.abs(da.Unit:Dot(db.Unit)) < .001 then
            table.insert(output.Corners,{Before=ra.Id, Turn=id, After=rb.Id,
                Centre=xyz(q.Config.WorldOrigin+Vector3.new(room.X,0,room.Z))})
        end
    end end
end
assert(#output.Gateways == 2)
return game.HttpService:JSONEncode(output)
```

Arm the existing production lifecycle through the supported Studio timeline hook; do not create the Manager independently:

```lua
local q = _G.TrelloL3QA
q.Music.DebugSetElapsed(q.Config.MusicSequence.DurationSeconds + .1)
local untilAt = os.clock()+3
repeat task.wait(.1) until q.Manager.GetSnapshot() or os.clock()>=untilAt
assert(q.Manager.GetSnapshot(), "Adapter hunt binding did not create Manager")
return game.HttpService:JSONEncode(q.Suite.ValidateMallManagerRuntime(true))
```

There are roughly 30 seconds before normal hunt recovery. A timeline restart during a trace may destroy/respawn the Manager; such a trace cannot prove continuous pursuit. Root can run two bounded hunt legs to cover the gateways separately. Follow the actual physical route around at least two of the listed right-angle junctions. A gateway counts only after Manager positions pass between its two endpoint rooms without teleporting or changing SpawnSerial/Generation. At least one direction across each district connector plus the independently tested player traversal in both directions is the minimum useful native coverage for this layout change.

Existing focused safety-net command (about six seconds; it temporarily anchors/protects/repositions the tester and restores player state and blackout profile):

```lua
local q = _G.TrelloL3QA
local p = game.Players:GetPlayers()[1]
return game.HttpService:JSONEncode(q.Suite.ProbeChaseForwardProgress(q.Manager,p,6))
```

This verifies real continuous CHASE, target identity, distance travelled, genuine progress, stuck budget, path-compute limits, speed ceiling and absence of attack. It selects a far clear room itself; **it does not guarantee either gateway or two turns**, so retain the separate actual route observations. Do not run the entire RunNavigationRegression wrapper: it also adds unrelated destructive fixtures and long furniture/overlap tests.

For a reproducible starting position only, `Manager.DebugPrepareStraightPatrol(startPoint,destinationPoint)` is the existing relocation API. It requires a ≥12-stud straight segment and validates both volumes and the complete production sweep before moving the Manager. It resets its own navigation state coherently. Use actual clear points in a selected gateway endpoint room; do not replace it with Model:PivotTo. After staging, normal blackout target acquisition should own pursuit again. Label this an initial-position fixture, not unmodified player-driven positioning.

Useful read-only sampling fields from Manager.GetSnapshot(): Position, State, TargetUserId, Generation, SpawnSerial, PathValidated, PathComputesLastSecond, PeakConcurrentPathComputes, GenuineProgressSerial, LastGenuineProgressAgeSeconds, StuckRecoveries, RecoveryRepaths, StrategicIndex, WaypointIndex and LastActualStepDistance. `Suite.ValidateManagerNavigationTelemetry(snapshot,true)` requires a proven path, ≤5 path computes/sec, ≤1 concurrent compute and all furniture exclusions intact. A single good snapshot does not establish movement; capture a short series/visual traversal, requiring unchanged generation/spawn and increasing GenuineProgressSerial. Geometry-only clearance is not pursuit evidence.

## Five CDs, reveal and final hall

CD collection and insertion hooks call the **same production handlers**, including living/InRound/untouched-session, prompt Enabled, actual distance and optional LOS checks. Collecting five is insufficient: all five must be **inserted at the Signal Hall TV/VCR**.

After physically approaching each actual `manifest.Modules[index].Prompt`:

```lua
local q = _G.TrelloL3QA
local p = game.Players:GetPlayers()[1]
assert(q.Objective.DebugCollectCD(p, 1)) -- use the actual module's Index; repeat for all five
return game.HttpService:JSONEncode(q.Objective.GetSnapshot())
```

Use the actual prompts normally for physical interaction evidence. The debug hook checks the server handler but does not prove a keyboard/touch prompt activated. Before collection, `manifest.Modules[index].Index` is the authoritative ID; do not assume array order if choosing modules spatially.

Near `manifest.DiscPlayer.Prompt`, insert four first and verify `Suite.ValidateRuntime(4)` and locked wall, then collect/insert the fifth:

```lua
local q = _G.TrelloL3QA
local p = game.Players:GetPlayers()[1]
local count = q.Objective.DebugInsertHeldCDs(p)
assert(count==5)
task.wait(.8) -- permit reveal tweens and the .05-second music tick
return game.HttpService:JSONEncode({Runtime=q.Suite.ValidateRuntime(5), Objective=q.Objective.GetSnapshot()})
```

Once inserted progress reaches five, Music's ordinary tick moves its phase to DONE and clears the ordinary hunt. Do not fake RoomSongPhase or final-hall attributes. The concealed wall should unseal and the final exit should power; no old objective guide or obsolete exit button should appear.

The final hall contract is unchanged: StartPoint→EndPoint is exactly560 studs along +X, spawn marker at40% (224 studs), trigger threshold50% (280 studs). Place/run the living test character just before49% and then just beyond51%, using `hall.StartPoint + hall.Forward*hall.Length*fraction + Vector3.new(0,3,0)` only if using a clearly labeled positional fixture. `Objective.DebugEvaluateFinalHallChase()` can evaluate immediately but the normal Heartbeat does it every .1 seconds. Check no chase before threshold and one chase after it, with Manager.FinalHallChase=true and spawn at the authored40% marker. Once triggered, repeated evaluations must retain the same Manager SpawnSerial. **Every living, InRound, nonescaped participant must have crossed halfway**; a second idle test client prevents the trigger legitimately. A single-client run does not certify this multiplayer quorum.

Continue down the actual hall and run into EscapeTrigger. No button is required. Escape must set Escaped=true and place the character at ExitSafeSpawn. The server accepts only a living character whose root is inside the detector; Touched is only a wakeup and the .1-second scan provides a fallback. A one-shot session guard plus Escaped blocks duplicates. For user-visible once-only evidence, count the local client's `Remotes.RoundStatus.OnClientEvent` with kind `"escape"` and this player's name; expect one event during the crossing and normal result delay. Do not synthesize the event or toggle Escaped. In a single-player party the normal GameManager can declare the win within .5 seconds, so a late repeated-entry command would be testing a completed round instead.

## Normal cleanup and fresh lobby

Let GameManager finish its normal Level 3 win/result return. Then:

```lua
local q = _G.TrelloL3QA
local report = q.Suite.ValidateCleanup(q.Before)
assert(q.Adapter.GetManifest()==nil and q.Manager.GetSnapshot()==nil)
workspace:SetAttribute("Level3Seed",q.OriginalSeedOverride)
return game.HttpService:JSONEncode(report)
```

This checks no generated world/compatibility markers/tagged Manager, restored original lobby/entity/script states, cleared state/lighting/hunt/objective attributes and no stored leftovers. Restore the seed fixture before a fresh normal lobby launch; otherwise an intentionally pinned map is not a seed-randomness test. A new queue/entry should still yield a living 100-HP character, released root and ready controls. All temporary telemetry connections must be disconnected before stopping Play/publication.
