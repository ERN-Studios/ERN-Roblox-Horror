The helper `level4_native_qa.luau` only reads native state. Load its text, replace the single `__MODE__` token, and pass the resulting code to Roblox Studio `execute_luau` with the matching `datamodel_type`: `sources` uses Edit, `server` uses Server, and `client` uses Client. Select the existing experience (place 131311258779917, universe 10559217407). This helper never starts/stops Play, moves geometry, requires a generator or modifies scripts. Source hashes are the frozen candidate/unchanged-original hashes; a concurrent source change should fail that guard and be reconciled from fresh Studio, rather than bypassed.

`runtime_level4.py` wraps those observations and the normal player actions in explicit phases with a unique immutable receipt label. Importing it or using `--code-only` performs no native call. It selects the captured Studio session, guards the place/DataModel, and records each result/error separately. Commands use the current selected client; `--expected-player` prevents accidentally accepting observations from a different client. No phase starts or stops Play.

```powershell
python artifacts/lazy-levels-20261009/runtime_level4.py sources q4-before
python artifacts/lazy-levels-20261009/runtime_level4.py lobby-server q4-lobby-server
python artifacts/lazy-levels-20261009/runtime_level4.py lobby-client q4-lobby-client
python artifacts/lazy-levels-20261009/runtime_level4.py position-client q4-first-position
python artifacts/lazy-levels-20261009/runtime_level4.py configure-client q4-first-config
python artifacts/lazy-levels-20261009/runtime_level4.py entry-server q4-first-server
python artifacts/lazy-levels-20261009/runtime_level4.py entry-client q4-first-client
python artifacts/lazy-levels-20261009/runtime_level4.py door-server q4-door-before
python artifacts/lazy-levels-20261009/runtime_level4.py door-touch-client q4-door-touch
python artifacts/lazy-levels-20261009/runtime_level4.py leave-client q4-first-leave
python artifacts/lazy-levels-20261009/runtime_level4.py unmount-server q4-first-unmount
python artifacts/lazy-levels-20261009/runtime_level4.py unmount-client q4-first-client-unmount
```

Use fresh labels for the second position/configuration/entry/touch/leave/unmount sequence, then run the Edit `sources` guard again after the root stops its test session. The touch phase selects a nearby real interior door, moves the actual character into contact for 1.8 seconds, observes hinge opening, and restores borrowed character transform, velocities and movement even if the assertion fails. It never assigns leaf or hinge properties. A failed pre-admission queue trial needs `cancel-client` to cancel normally and restore its still-current borrowed lobby character. In an active round, use `leave-client` instead. All 14 phase definitions compiled offline; their runtime results remain separate native evidence.

Capture `sources` in Edit after installation and again after all runtime probes. Use `server` once Play is running to capture the parked door baselines before first activation. Save the returned JSON locally; compare leaf CFrame, Anchored, CanCollide, hinge Enabled/TargetAngle and speeds after cleanup and the second entry. Do not compare Play object IDs with Edit IDs: Play creates its own DataModel.

The normal Level 4 queue is the revised lobby detector with `R3QueueId` 113–116 and `LevelNumber` 4. QueueBridge maps 113 to the first Level 4 station and marks only levels above 4 as preview queues. GameManager polls the actual character in the circle, offers `RoundStatus("queuehost", stationId, ...)`, and accepts `Remotes.ConfigureQueue:FireServer(stationId, maxPlayers, "public", "trial")` only from that host while still in the zone. A solo 1/1 party naturally uses the existing three-second full-party countdown. No developer access flag, InRound marker, SelectedLevel write, direct Build call or synthetic readiness acknowledgement is needed.

For controlled Studio QA, a Client call can place the current living lobby character at the detector; otherwise walk onto the pad in the viewport:

```luau
local p = game:GetService("Players").LocalPlayer
assert(p and p:GetAttribute("InRound") ~= true)
local lobby = assert(workspace:FindFirstChild("LobbyReimaginedPreview"))
local zone
for _, d in ipairs(lobby:GetDescendants()) do
    if d:IsA("BasePart") and d:GetAttribute("R3QueueId") == 113 then
        assert(not zone and d:GetAttribute("LevelNumber") == 4)
        zone = d
    end
end
assert(zone and p.Character and p.Character:FindFirstChild("HumanoidRootPart"))
p.Character:PivotTo(zone.CFrame * CFrame.new(0, 3, 0))
return "Positioned at normal Level 4 station 113; wait for queuehost"
```

After the real queue host panel arrives, configure a solo round with a separate Client call:

```luau
game:GetService("ReplicatedStorage").Remotes.ConfigureQueue:FireServer(113, 1, "public", "trial")
return "Sent normal ConfigureQueue request"
```

Observe Server and Client after the real entry finishes. Require server SelectedLevel 4, WorldGenerated true, RoundLoadingState ready and RoundActive true; the participant should be InRound true, alive and unanchored. Client floor must name a descendant of `Workspace.Level 4 Cinema Blender.Collision`, rather than the invisible/noncolliding compatibility pad. Confirm Level 5/6 are absent from Workspace. The helper reports actual per-player Collision membership on Server and map/part presence on Client; an entrant-only test cannot establish bystander isolation. In a two-client session keep the second character in the lobby, run Client observations for each actual client, and require the bystander's cinema/floor to remain absent. Do not certify both clients from a single selected Client DataModel.

Walk into an interior door while the round is active, record its actual `CurrentAngle`, collider and leaf CFrame, then use the normal Back to Lobby UI. The equivalent Client request is:

```luau
game:GetService("ReplicatedStorage").Remotes.RoundStatus:FireServer("leaveround")
return "Sent normal leave-round request"
```

GameManager accepts this only from a current participant while its lifecycle is open. With the last participant leaving, its existing loss/return path waits about 5.5 seconds before cleanup. Poll `server` in separate calls, bounded to 20 seconds total; do not force RoundActive, WorldGenerated or Source state. Require InRound false, Level4RoundActive false, cinema parked in ServerStorage, no compatibility runtime/Usher replica on Client and no persistent members. If the last participant remains in an ending/reentry/transfer window, let the ordinary lifecycle settle and report the actual state instead of parking it manually.

Repeat the same queue entry after cleanup. Compare the parked neutral door snapshot and second-entry door state, and push the door again to verify its cached basis/opening direction restarts. Capture the map removal and second arrival on Client, including lights, local film GUIs and fresh Round Entry acknowledgement. Stop and report any actual asset failure, floor failure, ignored cleanup exception, duplicate client visuals or new runtime error. None of these instructions has been executed by the helper author.

Before a failed positioning/queue trial ends, use the ordinary queue Cancel button or `ConfigureQueue:FireServer(113, 0, "cancel")`. Restore a borrowed character transform only if it is still that same living lobby character and InRound remains false; once GameManager owns an entry/round character, use its normal exit path. No native probe objects or Source edits are created by these queue requests.
