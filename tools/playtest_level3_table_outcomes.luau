-- Run in a disposable, one-player Studio Server play session. This companion
-- to the natural patrol probe parks the real rig at an engine-cleared inspection
-- point and uses seeded Roblox Random instances to exercise both real outcomes.
-- Production tuning, source, geometry, visibility and release logic stay live.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsRunning(), "Studio Server play session required")
assert(not RunService:IsClient(), "Execute this probe in the Server datamodel")
assert(not _G.Level3TableOutcomeProbe or _G.Level3TableOutcomeProbe.Status ~= "RUNNING",
	"A table outcome probe is already running")

_G.Level3TableOutcomeProbe = {Status = "RUNNING", Phase = "STARTING", Cases = {}}
task.spawn(function()
	local systems = game.ServerScriptService["Level 3 Systems"]
	local Adapter = require(systems["Level 3 Round Adapter"])
	local Manager = require(systems["Level 3 Mall Manager AI Controller"])
	local Hiding = require(systems["Level 3 Hiding Controller"])
	local Music = require(systems["Level 3 Music Sequence Controller"])
	local Configuration = require(systems["Level 3 Configuration"])
	local Players = game:GetService("Players")
	local HttpService = game:GetService("HttpService")
	local oldSeed = workspace:GetAttribute("Level3Seed")
	local results = _G.Level3TableOutcomeProbe.Cases
	local player: Player? = nil
	local oldCharacter: Model? = nil
	local oldPivot: CFrame? = nil
	local oldInRound: any = nil
	local oldEscaped: any = nil

	local function planarDistance(a: Vector3, b: Vector3): number
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function positionData(position: Vector3): any
		return {X = position.X, Y = position.Y, Z = position.Z}
	end
	local function roomAt(manifest: any, position: Vector3): string?
		for _, room in ipairs(manifest.Layout.Rooms) do
			local delta = position - Configuration.WorldOrigin
			if math.abs(delta.X - room.X) <= room.W * .5
				and math.abs(delta.Z - room.Z) <= room.D * .5 then
				return room.Id
			end
		end
		return nil
	end
	local function randomSeedFor(success: boolean): (number, number)
		for seed = 1, 10000 do
			local firstRoll = Random.new(seed):NextNumber()
			if (firstRoll < Configuration.TableCheck.SkillCheckSuccessChance) == success then
				return seed, firstRoll
			end
		end
		error("Could not find a Roblox Random seed for the requested outcome")
	end
	local function freeAnchors(world: Model): {BasePart}
		local cds = {}
		local anchors = {}
		for _, object in ipairs(world:GetDescendants()) do
			if object:IsA("Model") and object:GetAttribute("Level3_CDState") == "WORLD" then
				table.insert(cds, object:GetPivot().Position)
			end
		end
		for _, object in ipairs(world:GetDescendants()) do
			if object:IsA("BasePart") and object:GetAttribute("Level3_HideTableAnchor") == true
				and (tonumber(object:GetAttribute("Level3_HideOccupiedUserId")) or 0) == 0 then
				local clear = true
				for _, cd in ipairs(cds) do
					if planarDistance(object.Position, cd) <= 3 then clear = false break end
				end
				if clear then table.insert(anchors, object) end
			end
		end
		table.sort(anchors, function(a, b)
			return (tonumber(a:GetAttribute("Level3_HideTableIndex")) or 0)
				< (tonumber(b:GetAttribute("Level3_HideTableIndex")) or 0)
		end)
		return anchors
	end
	local function runCase(expected: string): any
		local testPlayer = assert(player)
		_G.Level3TableOutcomeProbe.Phase = expected .. ":BUILDING"
		workspace:SetAttribute("RoundActive", false)
		workspace:SetAttribute("Level3Seed", 7331)
		local world = Adapter.Build()
		local manifest = assert(Adapter.GetManifest(), "Build produced no active manifest")
		assert(manifest.World == world and world.Parent == workspace,
			"Probe must use the adapter's actual generated world")
		local generation = assert(world:GetAttribute("Level3_Generation"))
		local character = testPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			testPlayer:LoadCharacterAsync()
			task.wait(.3)
		end
		character = assert(testPlayer.Character, "Test player has no character")
		humanoid = assert(character:FindFirstChildOfClass("Humanoid"), "Test player has no Humanoid")
		local playerRoot = character:WaitForChild("HumanoidRootPart") :: BasePart
		assert(not playerRoot.Anchored, "Use a living, movable player for this probe")
		testPlayer:SetAttribute("InRound", true)
		testPlayer:SetAttribute("Escaped", false)
		local anchors = freeAnchors(world)
		assert(#anchors > 0, "Generated world has no unoccupied table without a CD")
		-- Give real spawn selection an eligible player inside the current world.
		character:PivotTo(anchors[1].CFrame * CFrame.new(0, 0, 4))
		workspace:SetAttribute("RoundActive", true)
		Music.DebugSetElapsed(181)
		local session = assert(Manager.Start(manifest, generation), "Manager did not start a live hunt")
		Manager.DebugSetMovementPaused(true)
		Manager.DebugSetTableChecksEnabled(false)
		local entityRoot = session.Root
		local entityModel = session.Model
		local anchor: BasePart? = nil
		local inspectionPoint: Vector3? = nil
		local selectedRoom: string? = nil
		for _, candidate in ipairs(anchors) do
			local roomId = roomAt(manifest, candidate.Position)
			if roomId and roomId ~= "Exit" then
				for step = 0, 31 do
					local heading = math.pi * .5 + step * math.pi / 16
					local point = Vector3.new(candidate.Position.X, session.FloorY, candidate.Position.Z)
						+ Vector3.new(math.cos(heading) * 13.5, 0, math.sin(heading) * 13.5)
					if roomAt(manifest, point) == roomId and Manager.DebugNavigationProbe(point).VolumeFits then
						anchor, inspectionPoint, selectedRoom = candidate, point, roomId
						break
					end
				end
			end
			if anchor then break end
		end
		assert(anchor and inspectionPoint and selectedRoom,
			"No table has a production-cleared 13.5-stud inspection point inside its room")
		local hideAnchor = anchor :: BasePart
		local approachPoint = inspectionPoint :: Vector3
		assert(planarDistance(approachPoint, hideAnchor.Position) <= Configuration.TableCheck.StartRange,
			"Inspection fixture exceeds the production table-check range")
		character:PivotTo(hideAnchor.CFrame * CFrame.new(0, 0, 4))
		-- Wait for ordinary character state to settle before recording what the
		-- real hide entry must save and the successful shove must restore.
		task.wait(.15)
		assert(testPlayer.Character == character and humanoid.Health > 0, "Player life changed during setup")
		local controls = {
			RootAnchored = playerRoot.Anchored, AutoRotate = humanoid.AutoRotate,
			WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight, DisplayDistanceType = humanoid.DisplayDistanceType,
		}
		local collisions = {}
		for _, object in ipairs(character:GetDescendants()) do
			if object:IsA("BasePart") then
				table.insert(collisions, {Part = object, CanCollide = object.CanCollide,
					CanTouch = object.CanTouch, CanQuery = object.CanQuery})
			end
		end
		local entered, reason = Hiding.DebugEnter(testPlayer, hideAnchor)
		assert(entered, "Real hide entry refused: " .. tostring(reason))
		assert(Hiding.GetAnchor(testPlayer, generation) == hideAnchor, "Hide entry has no matching server record")
		Manager.DebugForcePatrolRoom(selectedRoom :: string)
		local direction = Vector3.new(hideAnchor.Position.X, session.FloorY, hideAnchor.Position.Z) - approachPoint
		local rootPosition = approachPoint + Vector3.new(0, session.GroundOffset, 0)
		entityRoot.CFrame = CFrame.lookAt(rootPosition, rootPosition + direction.Unit)
		session.Heading = direction.Unit
		session.NextTableCheckAt = 0
		session.AnchorCheckCooldown = {}
		local randomSeed, firstRoll = randomSeedFor(expected == "SUCCESS")
		-- No yield after assigning the fresh real RNG until the engine's next
		-- Heartbeat. Its inspection path runs before the brain's patrol RNG use.
		session.Random = Random.new(randomSeed)
		Manager.DebugSetTableChecksEnabled(true)
		_G.Level3TableOutcomeProbe.Phase = expected .. ":WARNING"
		local function snapshot(): any
			local current = assert(Manager.GetSnapshot(), "Manager vanished during outcome probe")
			assert(current.Model == entityModel and session.Root == entityRoot
				and entityRoot:IsDescendantOf(entityModel) and current.Generation == generation,
				"Manager identity changed during an isolated outcome")
			assert(testPlayer.Character == character and humanoid.Health > 0,
				"Player life changed during an isolated outcome")
			return current
		end
		local start = workspace:GetServerTimeNow()
		local warningStart: number? = nil
		local warningEnd: number? = nil
		local completed: any = nil
		repeat
			local current = snapshot()
			if current.TableCheckActive and not warningStart then
				warningStart = workspace:GetServerTimeNow()
				warningEnd = session.TableCheckEndsAt
				assert(current.State == "TABLE_CHECK" and session.TableCheckAnchor == hideAnchor,
					"Production inspection did not discover the selected hidden player")
				assert(warningEnd - warningStart >= 1.85, "Warning has less than the promised two seconds")
			end
			if current.TableCheckSerial == 1 then completed = current break end
			assert(current.TableCheckSerial == 0, "Isolated outcome completed more than one skill check")
			task.wait(.025)
		until workspace:GetServerTimeNow() - start > 6
		assert(completed and warningStart and warningEnd, "Production inspection did not begin and complete within six seconds")
		assert(workspace:GetServerTimeNow() >= warningEnd, "Skill check completed before its server-time deadline")
		assert(completed.LastTableCheckResult == expected,
			"Real RNG outcome differs from its verified first roll: " .. tostring(completed.LastTableCheckResult))
		local moved = 0
		local collisionRestoreCount = 0
		local immunityExpired = false
		if expected == "SUCCESS" then
			assert(completed.TableCheckFlushCount == 1 and not Hiding.IsHidden(testPlayer),
				"Successful production skill check did not shove its occupant out")
			assert(Hiding.IsFlushImmune(testPlayer), "Successful shove did not grant its protected head start")
			assert(not playerRoot.Anchored and playerRoot.Anchored == controls.RootAnchored
				and humanoid.AutoRotate == controls.AutoRotate and humanoid.WalkSpeed == controls.WalkSpeed
				and humanoid.JumpPower == controls.JumpPower and humanoid.JumpHeight == controls.JumpHeight
				and humanoid.DisplayDistanceType == controls.DisplayDistanceType,
				"Successful shove did not restore saved character controls")
			for _, record in ipairs(collisions) do
				local part = record.Part
				assert(part.Parent and part.CanCollide == record.CanCollide
					and part.CanTouch == record.CanTouch and part.CanQuery == record.CanQuery,
					"Successful shove did not restore collision/query/touch flags for " .. part.Name)
				collisionRestoreCount += 1
			end
			assert(completed.State == "CHASE" and completed.TargetUserId == testPlayer.UserId,
				"Successful shove did not resume the exposed-player chase")
			assert(planarDistance(entityRoot.Position, playerRoot.Position) > Configuration.MallManager.AttackConfirmRange,
				"Paused entity is too close to safely observe immunity expiry")
			_G.Level3TableOutcomeProbe.Phase = expected .. ":IMMUNITY"
			local expiryDeadline = workspace:GetServerTimeNow() + 2
			repeat
				task.wait(.05)
				snapshot()
				immunityExpired = not Hiding.IsFlushImmune(testPlayer)
			until immunityExpired or workspace:GetServerTimeNow() >= expiryDeadline
			assert(immunityExpired, "Shove immunity did not expire after its 1.5-second head start")
		else
			assert(completed.TableCheckFlushCount == 0 and Hiding.IsHidden(testPlayer)
				and not Hiding.IsFlushImmune(testPlayer), "Failed skill check changed its hidden occupant")
			assert(completed.State == "PATROL" and completed.TargetUserId == 0 and completed.FinalGoal,
				"Failed skill check did not choose its next movement goal immediately")
			_G.Level3TableOutcomeProbe.Phase = expected .. ":MOVEMENT"
			Manager.DebugSetMovementPaused(false)
			local failurePosition = completed.Position
			local movementDeadline = workspace:GetServerTimeNow() + 4
			repeat
				task.wait(.05)
				local current = snapshot()
				assert(current.TableCheckSerial == 1 and not current.TableCheckActive,
					"Failed check retried before the production cooldown")
				assert(Hiding.IsHidden(testPlayer), "Failure movement removed the hidden player")
				moved = planarDistance(current.Position, failurePosition)
			until moved > 2 or workspace:GetServerTimeNow() >= movementDeadline
			assert(moved > 2, "Entity remained at the table after its failed skill check")
		end
		return {
			Expected = expected, Outcome = completed.LastTableCheckResult, WorldSeed = 7331,
			Generation = generation, RandomSeed = randomSeed, FirstRandomRoll = firstRoll,
			ConfiguredSuccessChance = Configuration.TableCheck.SkillCheckSuccessChance,
			TableIndex = hideAnchor:GetAttribute("Level3_HideTableIndex"), Room = selectedRoom,
			InspectionPoint = positionData(approachPoint), InspectionDistance = planarDistance(approachPoint, hideAnchor.Position),
			WarningSeconds = warningEnd - warningStart, Flushed = completed.TableCheckFlushCount,
			CollisionPartsRestored = collisionRestoreCount, ImmunityExpired = immunityExpired,
			MovedAfterFailure = moved, PlayerHealth = humanoid.Health, IdentityPreserved = true,
		}
	end

	local ok, problem = xpcall(function()
		assert(Configuration.TableCheck.SkillCheckSuccessChance == .25, "Probe expects the authored 25 percent chance")
		-- Play startup prewarms the shared kit before public admission is ready.
		local kitDeadline = os.clock() + 30
		repeat
			local kit = game.ServerStorage:FindFirstChild("Level6BlenderKit")
			if kit and kit:GetAttribute("Ready") == true then break end
			task.wait(.1)
		until os.clock() >= kitDeadline
		local roster = Players:GetPlayers()
		assert(#roster == 1, "Use a disposable Studio play session with exactly one player")
		player = roster[1]
		oldCharacter = player.Character
		oldPivot = if oldCharacter then oldCharacter:GetPivot() else nil
		oldInRound = player:GetAttribute("InRound")
		oldEscaped = player:GetAttribute("Escaped")
		for _, expected in ipairs({"SUCCESS", "FAILED"}) do
			local caseOK, caseResult = xpcall(function() return runCase(expected) end, debug.traceback)
			local cleanupOK, cleanupProblem = pcall(Adapter.Cleanup)
			workspace:SetAttribute("RoundActive", false)
			assert(caseOK, tostring(caseResult))
			assert(cleanupOK, "World cleanup failed: " .. tostring(cleanupProblem))
			table.insert(results, caseResult)
		end
	end, debug.traceback)
	-- Final cleanup also covers an exception before the per-case cleanup block.
	local cleanupOK, cleanupProblem = pcall(Adapter.Cleanup)
	pcall(Manager.DebugSetTableChecksEnabled, true)
	workspace:SetAttribute("RoundActive", false)
	workspace:SetAttribute("Level3Seed", oldSeed)
	if player and player.Parent == Players then
		player:SetAttribute("InRound", oldInRound)
		player:SetAttribute("Escaped", oldEscaped)
		if oldCharacter and player.Character == oldCharacter and oldPivot and oldCharacter.Parent then
			oldCharacter:PivotTo(oldPivot)
		end
	end
	if not cleanupOK then ok, problem = false, tostring(problem) .. "\nCleanup: " .. tostring(cleanupProblem) end
	_G.Level3TableOutcomeProbe = {
		Status = if ok then "PASSED" else "FAILED", Phase = "DONE", Cases = results,
		Result = if ok then HttpService:JSONEncode(results) else tostring(problem),
	}
	if not ok then warn("Level 3 deterministic table outcome probe: " .. tostring(problem)) end
end)
return "Level 3 deterministic outcome probe started; poll _G.Level3TableOutcomeProbe."
