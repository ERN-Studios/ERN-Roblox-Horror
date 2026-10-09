# Continue — minimal native two-client test

Read-only feasibility investigation, 2026-09-10. No UI input, mode switch or Studio mutation was performed by the critic. Root owns execution.

**Observed root execution:** the top-left dropdown did not open in this build. Root successfully used the native **Test menu → Start Test Session → Server and Clients** instead. That session started with zero clients; **Test → Add Clients** in the server window was used once for each client. Actual Player1(-1) and Player2(-2) joined. These test windows did not advertise additional MCP IDs, so root used native client windows and their Luau Command Bars. Activate the exact intended native window before each input/readback: a screenshot can reflect another foreground window even if a previously saved server window ID still exists. This observed route supersedes the generic documented dropdown instruction below for this installed Studio build.

## Start and identify the actual sessions

In the top-left mode dropdown currently labelled **Test**, select **Server & Clients**, choose **2**, then click **Play** (or F7). This creates a server and two client sessions. **End Session** from any test session closes the complete simulation. This is the current documented interface, rather than the old ribbon's Local Server instructions. [Roblox testing modes](https://create.roblox.com/docs/studio/testing-modes#multi-client-simulation)

The existing MCP `start_stop_play` accepts only `is_start` and `studio_id`; it has no player-count parameter. Roblox documents it as a single Play Client start, and documents `StudioTestService:ExecuteMultiplayerTestAsync(2, args)` as the plugin-side alternative. That method yields until the test ends; it has not been called here. For this manual test, the documented UI start is sufficient. [StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)

Before starting, the read-only inventory returned only Studio ID `a3ecf1be-0797-4a53-a223-4885b1299aad`, place `131311258779917`, Edit mode. After starting, run `list_roblox_studios` again and inspect each returned ID with `get_studio_state`. MCP supports multiple connected Studio IDs. It does **not** provide a client-number field inside `execute_luau`; automatic registration of these particular simulated windows is still unverified. Do not assume the original ID now refers to a specific client. [Studio MCP instance targeting](https://create.roblox.com/docs/studio/mcp#use-multiple-studio-instances)

For each candidate client datamodel, this is a read-only identity query:

```lua
local Players = game:GetService("Players")
local list = {}
for _, player in ipairs(Players:GetPlayers()) do
    list[#list + 1] = {Name = player.Name, UserId = player.UserId}
end
local localPlayer = Players.LocalPlayer
return {LocalName = localPlayer and localPlayer.Name,
    LocalUserId = localPlayer and localPlayer.UserId, Players = list,
    ControlsReady = localPlayer and localPlayer:GetAttribute("RoundEntryControlsReady")}
```

Record two distinct actual LocalPlayers, and confirm the server sees both. Local test identities must be read, not presumed to be the signed-in account. If simulated windows do not expose independent MCP IDs, native window selection and ordinary mouse clicks remain sufficient for the two client actions; use the server's Command Bar for the small completion fixture and client Command Bars for readbacks. This is a tooling fallback, not a reason to substitute fake Players. Root should inventory windows before sending input. Do not change Assistant/MCP settings merely to try to force registration without first inspecting the available sessions.

## Enter the real completion path

Use the normal Level 1 station and queue UI with party size **2** (four DecreasePlayers clicks from the normal default of six), join the other actual client to that same station, and let the normal queue/loading/elevator finish. Verify both are present, InRound, alive and entry-ready. No need to solve the whole level: the production `playRound` loop's first win predicate is `workspace:GetAttribute("PuzzleWon")`; it then sets RoundActive=false and calls the actual intermission with the actual participants.

Root may execute this **explicit objective-completion fixture**, only in the native test's server datamodel:

```lua
assert(game:GetService("RunService"):IsStudio(), "Studio test only")
local Players = game:GetService("Players")
local participants = Players:GetPlayers()
assert(#participants == 2, "Expected two actual local-test players")
assert(workspace:GetAttribute("SelectedLevel") == 1, "Expected normal Level 1")
assert(workspace:GetAttribute("RoundActive") == true, "Wait for real round start")
assert(workspace:GetAttribute("RoundLoadingState") == "ready", "Wait for entry ready")
assert(workspace:GetAttribute("PostWinIntermissionActive") ~= true, "Already completing")
local before = {}
for _, player in ipairs(participants) do
    local character = assert(player.Character)
    local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
    local root = assert(character:FindFirstChild("HumanoidRootPart"))
    assert(player:GetAttribute("InRound") == true and humanoid.Health > 0)
    assert(not root.Anchored, "Wait for normal entry release")
    assert(player:GetAttribute("Escaped") ~= true, "This fixture does not simulate an escape/reward")
    before[#before + 1] = {Name = player.Name, UserId = player.UserId, Health = humanoid.Health}
end
workspace:SetAttribute("PuzzleWon", true)
return {Setup = "Controlled objective completion; not a level playthrough", Participants = before}
```

This intentionally changes just one Play attribute. It does not edit production, call the Continue handlers directly, fake Player instances, spoof button events, or fire the unrelated `ServerStorage.ZyntraLevelCompleted` reward event. With Escaped left false, the result's survivor count is a fixture limitation, and the normal reward loop does not report an actual escape. Preserve that label in the evidence.

`RoundEntryControlsReady` is set by the actual **client** NoiseReporter, so check it on each client's LocalPlayer using the identity query; do not assert that client-only attribute from the server. The server's ready state and released roots are the server-side entry evidence.

## Minimal acceptance

1. **Real replicated choice and barrier:** both real clients show the two actual usernames as WAITING. Click A's actual Continue. A shows READY with Back enabled; B shows A's CONTINUE and B's WAITING. Wait at least 16 seconds. Both remain on the same Level 1 result, no new round/loading starts, and B's choice remains unanswered. The interval specifically disproves the removed 15-second auto-choice behaviour.
2. **Joint continuation:** click B's actual Continue. The server settles one cohort containing both. Both clients enter the same normal next-level loading flow and reach Level 2 ready/InRound, with no stranded first client, duplicate launch or split roster. Record both client identities/readbacks and the server count; this is real local replication and local campaign continuation.
3. **Ready can change to Lobby:** in a second normal two-player result, click A Continue, then A Back while B is still waiting. Both clients must display A's LOBBY choice, A's actions stay locked, and B remains able to choose. When B chooses, Studio's **existing mixed-choice local fallback returns the group to the lobby**. That editor behaviour is deliberate; it cannot prove a live reserved-server split or rejected teleport recovery. Those paths retain independent actual-source tests.

If a disconnect case is inexpensive during the second run, an actual client departure while it is waiting/ready should become LEFT on its peer and cease contributing to the next cohort. Use an actual client leave, not End Session (which closes the whole simulation). The documented `StudioTestService:LeaveTest()` is a client-side test departure option; it is not needed for the two primary cases. No general network-failure framework is requested.

Save one view/readback from each client after A's choice and one after the 16-second wait, plus server/each-client final level and roster. Observe all six rows with a clearly labelled display fixture only if the two real names cannot expose the layout bounds; never call that six-player gameplay. Finish with **End Session**, verify the authoring Studio is Edit, no Play fixture remains, and the installed source hashes/whole-file compiles match the intended Continue+spawn merge.

**Limit:** local Studio does not perform real `TeleportService` reserved-server travel. Passing this plan supports the actual replicated buttons/barrier and local shared continuation, while live transport still relies on the preserved routing implementation and its focused source tests. Do not describe local mixed-return behaviour as a verified live split.
