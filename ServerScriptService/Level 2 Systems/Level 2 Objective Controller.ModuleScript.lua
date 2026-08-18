-- Level 2 Objective Controller
--
-- Level 2's own objective, separate from Level 1's fuse puzzle:
--   1. Three PUMP STATIONS are scattered through the complex and can all be
--      reached freely from the arrival.
--   2. Starting a pump DRAINS the flooded corridor next to it — the water is
--      actually removed from the terrain, so the space physically changes and
--      a new route opens up.
--   3. With all three pumps running, the PRESSURE DOORS into the Grand Slide
--      Hall unseal.
--   4. The exit is at the TOP of that hall: climb the spiral stair to the deck
--      and ride the exit flume out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Terrain = workspace.Terrain

local ObjectiveController = {}
local activeSession

local RUNNING_COLOR = Color3.fromRGB(150, 232, 176)
local OPEN_COLOR = Color3.fromRGB(180, 218, 196)

-- Pump audio is deliberately staged around the authored clip lengths.
local DRAIN_RUSH_DELAY = 10
local DRAIN_RUSH_DURATION = 12

local function state()
	return ReplicatedStorage:FindFirstChild("Level 2 State")
end

local function disconnectAll(session)
	for _, connection in ipairs(session.Connections or {}) do
		connection:Disconnect()
	end
	session.Connections = {}
end

-- One-shot audio cue for the Level 2 Sound Controller. Cue names match the
-- StringValue slots in ReplicatedStorage["Level 2 Sound Library"].
local function fireSound(cue, player)
	local event = ReplicatedStorage:FindFirstChild("Level 2 Sound Event")
	if not event then return end
	if player then event:FireClient(player, cue) else event:FireAllClients(cue) end
end

local function fireStatus(title, subtitle, instruction, holdSeconds)
	local event = ReplicatedStorage:FindFirstChild("Level2AlertEvent")
	if not event then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") then
			event:FireClient(player, title, subtitle, instruction, holdSeconds)
		end
	end
end

-- Level 1 never fires this, so its players only see the result at round end.
-- Level 2 fires it so an escape reads immediately for everyone.
local function fireEscape(player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local status = remotes and remotes:FindFirstChild("RoundStatus")
	if status then
		for _, recipient in ipairs(Players:GetPlayers()) do
			if recipient:GetAttribute("InRound") == true then
				status:FireClient(recipient, "escape", player.Name)
			end
		end
	end
end

local function validSession(session)
	return activeSession == session
		and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and session.Manifest.World.Parent ~= nil
		and session.Manifest.World:GetAttribute("Level2_Generation") == session.Generation
end

local function validPlayer(player, session)
	return validSession(session)
		and player.Parent == Players
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end

local function livingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and character.Parent and humanoid and humanoid.Health > 0 and root) then
		return nil
	end
	return character, humanoid, root
end

local function promptWorldPosition(prompt)
	local parent = prompt and prompt.Parent
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	if parent and parent:IsA("BasePart") then return parent.Position end
	return nil
end

local function canUsePump(player, session, pump)
	if not validPlayer(player, session) then return false end
	if not (pump.Prompt.Enabled and pump.Prompt:IsDescendantOf(session.Manifest.World)) then return false end
	local character, _, root = livingCharacter(player)
	local target = promptWorldPosition(pump.Prompt)
	if not (character and target) then return false end
	if (root.Position - target).Magnitude > pump.Prompt.MaxActivationDistance + 2 then return false end

	if pump.Prompt.RequiresLineOfSight then
		local originPart = character:FindFirstChild("Head") or root
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {character}
		params.IgnoreWater = true
		local result = workspace:Raycast(originPart.Position, target - originPart.Position, params)
		if result and not result.Instance:IsDescendantOf(pump.Model) then return false end
	end
	return true
end

local function validateManifest(manifest)
	assert(type(manifest) == "table", "Level 2 objective manifest must be a table")
	assert(manifest.World and manifest.World:IsA("Model") and manifest.World.Parent,
		"Level 2 objective manifest is missing its live World model")
	assert(type(manifest.Pumps) == "table" and #manifest.Pumps > 0,
		"Level 2 objective manifest has no pumps")
	local seenIndexes = {}
	for _, pump in ipairs(manifest.Pumps) do
		assert(type(pump) == "table" and type(pump.Index) == "number",
			"Level 2 objective manifest contains an invalid pump record")
		assert(not seenIndexes[pump.Index], "Level 2 objective manifest has a duplicate pump index")
		seenIndexes[pump.Index] = true
		assert(pump.Model and pump.Model:IsA("Model") and pump.Model:IsDescendantOf(manifest.World),
			"Level 2 pump model is missing from the generated world")
		assert(pump.Prompt and pump.Prompt:IsA("ProximityPrompt") and pump.Prompt:IsDescendantOf(pump.Model),
			"Level 2 pump is missing its ProximityPrompt")
		assert(pump.Lamp and pump.Lamp:IsA("BasePart"), "Level 2 pump is missing its status lamp")
	end
	assert(type(manifest.Exit) == "table", "Level 2 objective manifest has no exit")
	assert(manifest.Exit.Trigger and manifest.Exit.Trigger:IsA("BasePart")
		and manifest.Exit.Trigger:IsDescendantOf(manifest.World),
		"Level 2 exit trigger is missing from the generated world")
	assert(manifest.Exit.SafeSpawn and manifest.Exit.SafeSpawn:IsA("BasePart")
		and manifest.Exit.SafeSpawn:IsDescendantOf(manifest.World),
		"Level 2 exit safe spawn is missing from the generated world")
end

local function drain(record)
	if not record or not record.Water or record.Drained then return end
	record.Drained = true
	Terrain:FillBlock(record.Water.CFrame, record.Water.Size, Enum.Material.Air)
end

local function openPressureDoors(session)
	if session.DoorsOpen or not validSession(session) then return end
	session.DoorsOpen = true
	workspace:SetAttribute("Level2ExitPowered", true)

	local level2State = state()
	if level2State then
		level2State:SetAttribute("Level2_Phase", "EXIT_OPEN")
		level2State:SetAttribute("Level2_LightingMode", "EXIT_OPEN")
	end

	for _, record in ipairs(session.Manifest.PressureDoors) do
		local door = record.Door
		if door and door.Parent then
			-- Slide the heavy vertical door up into the roof void, matching its
			-- sound cue. The old treatment (pale Neon at .72 transparency) left
			-- a glowing white film across the whole doorway instead of opening
			-- it. Collision drops immediately so nobody rides the door up.
			door.CanCollide = false
			local rise = Vector3.new(0, door.Size.Y + 6, 0)
			local slideInfo = TweenInfo.new(3.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			local doorTween = TweenService:Create(door, slideInfo, {CFrame = door.CFrame + rise})
			doorTween.Completed:Connect(function()
				if door.Parent then door.Transparency = 1 end
			end)
			doorTween:Play()
			local stripe = record.Stripe
			if stripe and stripe.Parent then
				stripe.Color = OPEN_COLOR
				local stripeTween = TweenService:Create(stripe, slideInfo, {CFrame = stripe.CFrame + rise})
				stripeTween.Completed:Connect(function()
					if stripe.Parent then stripe.Transparency = 1 end
				end)
				stripeTween:Play()
			end
		end
		-- The grand hall's approach corridors KEEP their water — only each
		-- pump's own announced "DRAINING LOCAL SECTION" corridor ever drains.
		-- Bulk-draining every pressure corridor here silently emptied half the
		-- tunnel network at once.
	end

	local exit = session.Manifest.Exit
	if exit and exit.Mouth then
		exit.Mouth.Color = OPEN_COLOR
		exit.Mouth.Transparency = .35
	end

	fireSound("Level 2 Pressure Door")
	fireStatus(
		"PRESSURE EQUALIZED",
		"GRAND HALL UNSEALED",
		"CLIMB TO THE TOP DECK AND TAKE THE FLUME OUT"
	)
end

function ObjectiveController.Start(manifest, generation)
	ObjectiveController.Stop()
	validateManifest(manifest)
	local session = {
		Manifest = manifest,
		Generation = generation,
		Connections = {},
		Started = {},
		StartedCount = 0,
		DoorsOpen = false,
		Escaping = {},
	}
	activeSession = session

	local goal = #manifest.Pumps
	workspace:SetAttribute("Level2Pumps", 0)
	workspace:SetAttribute("Level2PumpGoal", goal)
	workspace:SetAttribute("Level2ExitPowered", false)

	for _, pump in ipairs(manifest.Pumps) do
		local connection = pump.Prompt.Triggered:Connect(function(player)
			if session.Started[pump.Index] or not canUsePump(player, session, pump) then return end
			session.Started[pump.Index] = true
			session.StartedCount += 1

			pump.Prompt.Enabled = false
			pump.Lamp.Color = RUNNING_COLOR
			if pump.LampGlow and pump.LampGlow.Parent then
				pump.LampGlow.Color = RUNNING_COLOR
				pump.LampGlow.Brightness = 1.1
				pump.LampGlow.Range = 20
			end
			if pump.LeverStatusRing and pump.LeverStatusRing.Parent then
				pump.LeverStatusRing.Color = RUNNING_COLOR
				pump.LeverStatusRing.Material = Enum.Material.Neon
			end
			if pump.Lever and pump.Lever.Parent then
				local rest = pump.LeverRestCFrame or pump.Lever.CFrame
				local target = rest * CFrame.Angles(math.rad(76), 0, 0)
				local tween = TweenService:Create(
					pump.Lever,
					TweenInfo.new(.58, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
					{ CFrame = target }
				)
				tween:Play()
			end
			pump.Model:SetAttribute("Level2_PumpRunning", true)

			workspace:SetAttribute("Level2Pumps", session.StartedCount)
			local level2State = state()
			if level2State then
				level2State:SetAttribute("Level2_PumpProgress", session.StartedCount)
			end

			-- Start the 12-second pump motor cue as soon as the lever engages.
			fireSound("Level 2 Pump Start", player)

			local drained = manifest.Drains and manifest.Drains[pump.Index]
			local isFinalPump = session.StartedCount >= goal

			-- Ten seconds into the pump motor, start the 12-second drain surge and
			-- remove this pump's water at the same moment so audio and world match.
			task.delay(DRAIN_RUSH_DELAY, function()
				if not validSession(session) then return end
				if drained then
					fireSound("Level 2 Drain Rush")
					drain(drained)
				end

				-- The third pump's pressure doors stay sealed until the complete
				-- drain-surge clip has finished: 10 + 12 = 22 seconds after pull.
				if isFinalPump then
					task.delay(DRAIN_RUSH_DURATION, function()
						if not validSession(session) or session.StartedCount < goal then return end
						openPressureDoors(session)
					end)
				end
			end)

			fireStatus(
				string.format("PUMP STATION %02d ONLINE", pump.Index),
				string.format("%d OF %d STATIONS RUNNING", session.StartedCount, goal),
				isFinalPump
					and "EQUALIZING PRESSURE"
					or (drained and "DRAINING LOCAL SECTION" or "LOCATE REMAINING STATIONS"),
				1.7
			)
		end)
		table.insert(session.Connections, connection)
	end

	local escapeConnection = manifest.Exit.Trigger.Touched:Connect(function(hit)
		if activeSession ~= session or not session.DoorsOpen then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or not validPlayer(player, session) or session.Escaping[player] then return end
		local liveCharacter, _, root = livingCharacter(player)
		if liveCharacter ~= character then return end
		-- Touch fires for several character parts.  Lock the player before moving
		-- them so crossing the doorway can only complete the level once.
		session.Escaping[player] = true
		player:SetAttribute("Escaped", true)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		liveCharacter:PivotTo(manifest.Exit.SafeSpawn.CFrame * CFrame.new(0, 3, 0))
		fireSound("Level 2 Slide Rush", player)
		fireEscape(player)
	end)
	table.insert(session.Connections, escapeConnection)

	-- Build() runs before anyone has InRound, so an immediate intro would reach
	-- no one. Fire it once the round actually starts (or shortly after, if the
	-- round was already live when this session started).
	local function fireIntro()
		if activeSession ~= session then return end
		-- The opening briefing holds noticeably longer than in-round alerts.
		fireStatus(
			"SUNKEN LEISURE COMPLEX",
			string.format("%d PUMP STATIONS OFFLINE", goal),
			"START ALL PUMPS TO UNSEAL THE EXIT",
			3
		)
	end
	if workspace:GetAttribute("RoundActive") == true then
		task.delay(2, fireIntro)
	else
		local introConnection
		introConnection = workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
			if workspace:GetAttribute("RoundActive") ~= true then return end
			introConnection:Disconnect()
			task.delay(4, fireIntro)
		end)
		table.insert(session.Connections, introConnection)
	end
	return session
end

function ObjectiveController.Stop()
	if not activeSession then return end
	disconnectAll(activeSession)
	activeSession = nil
end

return ObjectiveController
