-- Run through execute_luau on a disposable Studio Server play session.
-- Exercises generated-world patrol and a real 25% entity skill check. Either
-- random outcome is valid; deterministic boundary coverage lives offline.
assert(game:GetService("RunService"):IsStudio(), "Studio only")
assert(game:GetService("RunService"):IsRunning(), "Start a disposable play session first")
local systems = game.ServerScriptService["Level 3 Systems"]
local Adapter = require(systems["Level 3 Round Adapter"])
local Manager = require(systems["Level 3 Mall Manager AI Controller"])
local Hiding = require(systems["Level 3 Hiding Controller"])
local Music = require(systems["Level 3 Music Sequence Controller"])
local Configuration = require(systems["Level 3 Configuration"])
local player = assert(game.Players:GetPlayers()[1], "A test player is required")
local oldSeed = workspace:GetAttribute("Level3Seed")
local results = {}
_G.Level3TableCheckCases = results

-- The admission kit is prewarmed asynchronously at Play startup.
local kitDeadline = os.clock() + 30
repeat
	local kit = game.ServerStorage:FindFirstChild("Level6BlenderKit")
	if kit and kit:GetAttribute("Ready") == true then break end
	task.wait(.1)
until os.clock() >= kitDeadline

local function run(seed: number, hideBeforeSpawn: boolean)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		player:LoadCharacterAsync()
		task.wait(.3)
	end
	player:SetAttribute("InRound", true)
	player:SetAttribute("Escaped", false)
	workspace:SetAttribute("RoundActive", false)
	workspace:SetAttribute("Level3Seed", seed)
	local world = Adapter.Build()
	local cdTables = {}
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("Model") and object:GetAttribute("Level3_CDState") == "WORLD" then
			table.insert(cdTables, object:GetPivot().Position)
		end
	end
	local anchor: BasePart? = nil
	local closest = math.huge
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_HideTableAnchor") == true then
			local clear = true
			for _, at in ipairs(cdTables) do
				local delta = object.Position - at
				if Vector3.new(delta.X, 0, delta.Z).Magnitude <= 3 then clear = false break end
			end
			local distance = (object.Position - player.Character:GetPivot().Position).Magnitude
			if clear and distance < closest then anchor, closest = object, distance end
		end
	end
	assert(anchor, "Generated world has no free hiding anchor without a CD")
	player.Character:PivotTo(anchor.CFrame * CFrame.new(0, 0, 4))
	workspace:SetAttribute("RoundActive", true)
	for _, candidate in ipairs(game.Players:GetPlayers()) do
		assert(candidate == player or candidate:GetAttribute("InRound") ~= true
			or candidate:GetAttribute("Escaped") == true,
			"Use a one-player disposable session for this patrol probe")
	end
	local function enter()
		local entered, reason = Hiding.DebugEnter(player, anchor)
		assert(entered, tostring(reason))
		assert(Hiding.GetAnchor(player, world:GetAttribute("Level3_Generation")) == anchor,
			"Hiding anchor must come from the active server record")
	end
	if hideBeforeSpawn then enter() end
	Music.DebugSetElapsed(181)
	task.wait(.4)
	local initial = assert(Manager.GetSnapshot(), "Manager did not spawn")
	if not hideBeforeSpawn then
		assert(initial.State == "CHASE" and initial.TargetUserId == player.UserId,
			"Expected an exposed-player chase before hiding")
		enter()
	end
	task.wait(.2)
	local hidden = assert(Manager.GetSnapshot(), "Manager vanished on hide entry")
	assert(hidden.TargetUserId == 0 and player:GetAttribute("BeingChased") ~= true,
		"Hiding must release direct chase ownership")
	assert(hidden.State == "PATROL" and hidden.TargetMode == "HIDDEN_PATROL",
		"All-hidden hunt must walk around the occupied table")
	assert(hidden.Speed == Configuration.MallManager.Blackout.PatrolSpeed,
		"Hidden-player patrol must use walking speed")
	if hidden.FinalGoal then
		local delta = hidden.FinalGoal - anchor.Position
		assert(Vector3.new(delta.X, 0, delta.Z).Magnitude >= 10,
			"Patrol goal aims directly into the hidden player's table")
	end
	local startTime = workspace:GetServerTimeNow()
	local checkStarted: number? = nil
	local travelled = 0
	local lastPosition = hidden.Position
	local nextSeek = startTime + 8
	local finished = nil
	local testBudgetSeconds = math.max(75, hidden.PatrolLegSecondsRemaining
		+ Configuration.TableCheck.ReactionWindowSeconds + 8)
	local history = {}
	local lastState = ""
	-- A walk from the authored 90-180-stud spawn plus maze detours can exceed
	-- one 30-second hunt. Studio-only timeline seeks keep this same hunt alive.
	while workspace:GetServerTimeNow() - startTime < testBudgetSeconds do
		local now = workspace:GetServerTimeNow()
		if now >= nextSeek then Music.DebugSetElapsed(181); nextSeek = now + 8 end
		local snapshot = assert(Manager.GetSnapshot(), "Manager vanished during hidden patrol")
		if snapshot.State ~= lastState then
			table.insert(history, {Seconds=now-startTime, State=snapshot.State,
				CheckIndex=snapshot.TableCheckIndex, Result=snapshot.LastTableCheckResult})
			lastState = snapshot.State
		end
		_G.Level3TableCheckProgress = {
			Seed=seed, Seconds=now-startTime, Budget=testBudgetSeconds,
			State=snapshot.State, Path=snapshot.PathStatus,
			TargetTableIndex=snapshot.TableCheckTargetIndex,
			CheckSerial=snapshot.TableCheckSerial, CheckActive=snapshot.TableCheckActive,
			DistanceToTable=Vector3.new(snapshot.Position.X-anchor.Position.X,0,
				snapshot.Position.Z-anchor.Position.Z).Magnitude,
			Goal=tostring(snapshot.FinalGoal), Position=tostring(snapshot.Position), History=history,
		}
		assert(snapshot.SpawnSerial == initial.SpawnSerial, "Timeline extension replaced the test entity")
		travelled += (snapshot.Position - lastPosition).Magnitude
		lastPosition = snapshot.Position
		if snapshot.TableCheckSerial > initial.TableCheckSerial then
			finished = snapshot
			break
		end
		assert(snapshot.TargetUserId == 0 and player:GetAttribute("BeingChased") ~= true,
			"Hidden patrol reacquired a direct chase target")
		assert(Hiding.IsHidden(player), "Player left hiding before a completed skill check")
		assert(not snapshot.Attacking, "Entity attacked through the table")
		if snapshot.TableCheckActive then
			checkStarted = checkStarted or now
			assert(snapshot.State == "TABLE_CHECK", "Table check must own its warning state")
		end
		task.wait(.05)
	end
	assert(finished and checkStarted, "Manager did not patrol near, spot and check the occupied table")
	local warningSeconds = workspace:GetServerTimeNow() - checkStarted
	assert(warningSeconds >= 1.85, "The two-second warning was cut short")
	assert(travelled > 4, "Manager did not walk toward the table before checking it")
	assert(player.Character:FindFirstChildOfClass("Humanoid").Health > 0,
		"Skill check killed the hidden player")
	local movedAfterFailure = 0
	if finished.LastTableCheckResult == "SUCCESS" then
		assert(finished.TableCheckFlushCount == 1 and not Hiding.IsHidden(player),
			"Successful entity skill check did not shove the player out")
		assert(Hiding.IsFlushImmune(player), "A shoved player needs a 1.5-second head start")
		assert(not player.Character.HumanoidRootPart.Anchored,
			"Shove did not restore player movement")
		assert(finished.State == "CHASE" and finished.TargetUserId == player.UserId,
			"Successful shove must resume an exposed-player chase")
	elseif finished.LastTableCheckResult == "FAILED" then
		assert(finished.TableCheckFlushCount == 0 and Hiding.IsHidden(player),
			"Failed entity skill check moved its occupant")
		assert(finished.State == "PATROL" and finished.TargetUserId == 0
			and finished.FinalGoal ~= nil, "Failed check did not choose a patrol goal immediately")
		local failurePosition = finished.Position
		local failureSerial = finished.TableCheckSerial
		local movedDeadline = workspace:GetServerTimeNow() + 4
		repeat
			task.wait(.1)
			local nextSnapshot = assert(Manager.GetSnapshot(), "Manager vanished after failed check")
			assert(not nextSnapshot.TableCheckActive and nextSnapshot.TableCheckSerial == failureSerial,
				"Failed table check ignored the global or per-table cooldown")
			movedAfterFailure = (nextSnapshot.Position - failurePosition).Magnitude
		until movedAfterFailure > 2 or workspace:GetServerTimeNow() >= movedDeadline
		assert(movedAfterFailure > 2, "Entity remained standing at the table after a failed check")
	else
		error("Completed skill check reported no outcome")
	end
	return {
		Seed = seed,
		HideBeforeSpawn = hideBeforeSpawn,
		TableIndex = anchor:GetAttribute("Level3_HideTableIndex"),
		PatrolClearedChase = true,
		TravelledStuds = travelled,
		SecondsToSkillCheck = workspace:GetServerTimeNow() - startTime,
		WarningSeconds = warningSeconds,
		SkillCheckResult = finished.LastTableCheckResult,
		Flushed = finished.TableCheckFlushCount,
		MovedAfterFailure = movedAfterFailure,
	}
end

for _, case in ipairs({{Seed = 7331, Before = true}, {Seed = 101, Before = false}}) do
	local ok, result = pcall(run, case.Seed, case.Before)
	Adapter.Cleanup()
	workspace:SetAttribute("RoundActive", false)
	if not ok then
		workspace:SetAttribute("Level3Seed", oldSeed)
		error(result)
	end
	table.insert(results, result)
end
workspace:SetAttribute("Level3Seed", oldSeed)
return game:GetService("HttpService"):JSONEncode(results)
