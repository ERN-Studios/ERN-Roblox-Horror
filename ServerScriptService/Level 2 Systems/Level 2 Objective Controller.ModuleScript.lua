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
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Terrain = workspace.Terrain

local ObjectiveController = {}
local activeSession

local RUNNING_COLOR = Color3.fromRGB(150, 232, 176)
local OPEN_COLOR = Color3.fromRGB(180, 218, 196)

-- Pump audio is deliberately staged around the authored clip lengths.
local DRAIN_RUSH_DELAY = 10
local DEFAULT_PUMP_START_DURATION = 11.572244897959184

local function state()
	return ReplicatedStorage:FindFirstChild("Level 2 State")
end

-- Resolve the live library slot once per generated round. This keeps the
-- pressure gauge and final pressure-door release synchronized even if the
-- authored pump recording is replaced later; the measured current clip length
-- remains the fallback if an asset cannot be loaded on the server.
local function pumpStartDuration()
	local library = ReplicatedStorage:FindFirstChild("Level 2 Sound Library")
	local slot = library and library:FindFirstChild("Level 2 Pump Start")
	local raw = slot and slot:IsA("StringValue") and tostring(slot.Value) or ""
	raw = raw:gsub("%s", "")
	if raw:match("^%d+$") then raw = "rbxassetid://" .. raw end
	if not raw:match("^rbxassetid://%d+$") then return DEFAULT_PUMP_START_DURATION end

	local probe = Instance.new("Sound")
	probe.Name = "Level 2 Pump Duration Probe"
	probe.SoundId = raw
	probe.Volume = 0
	probe.Parent = SoundService
	local loaded = pcall(function()
		ContentProvider:PreloadAsync({probe})
	end)
	local duration = loaded and probe.IsLoaded and probe.TimeLength > .05
		and probe.TimeLength or DEFAULT_PUMP_START_DURATION
	probe:Destroy()
	return math.clamp(duration, 1, 30)
end

local function disconnectAll(session)
	for _, tween in ipairs(session.GaugeTweens or {}) do tween:Cancel() end
	session.GaugeTweens = {}
	for _, connection in ipairs(session.Connections or {}) do
		connection:Disconnect()
	end
	session.Connections = {}
end

-- One-shot audio cue for the Level 2 Sound Controller. Cue names match the
-- StringValue slots in ReplicatedStorage["Level 2 Sound Library"].
local function fireSound(cue, player, context)
	local event = ReplicatedStorage:FindFirstChild("Level 2 Sound Event")
	if not event then return end
	if player then event:FireClient(player, cue, context) else event:FireAllClients(cue, context) end
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
		assert(pump.GaugeNeedlePivot and pump.GaugeNeedlePivot:IsA("BasePart")
			and typeof(pump.GaugeNeedleZeroCFrame) == "CFrame"
			and typeof(pump.GaugeNeedleFullCFrame) == "CFrame",
			"Level 2 pump is missing its pressure-gauge needle animation")
		assert(pump.GaugePressureValue and pump.GaugePressureValue:IsA("NumberValue")
			and pump.GaugePressureText and pump.GaugePressureText:IsA("TextLabel"),
			"Level 2 pump is missing its pressure-gauge readout")
	end
	assert(type(manifest.PressureDoors) == "table",
		"Level 2 objective manifest is missing its pressure door records")
	assert(type(manifest.Exit) == "table", "Level 2 objective manifest has no exit")
	assert(manifest.Exit.Trigger and manifest.Exit.Trigger:IsA("BasePart")
		and manifest.Exit.Trigger:IsDescendantOf(manifest.World)
		and manifest.Exit.Trigger.Name == "Level 2 Exit Completion Beam"
		and manifest.Exit.Trigger.Material == Enum.Material.Neon
		and manifest.Exit.Trigger:GetAttribute("Level2_ExitCompletionBeam") == true,
		"Level 2 exit completion beam is missing from the generated world")
	assert(manifest.Exit.SafeSpawn and manifest.Exit.SafeSpawn:IsA("BasePart")
		and manifest.Exit.SafeSpawn:IsDescendantOf(manifest.World),
		"Level 2 exit safe spawn is missing from the generated world")
end

local function drain(record)
	if not record or not record.Water or record.Drained then return end
	record.Drained = true
	Terrain:FillBlock(record.Water.CFrame, record.Water.Size, Enum.Material.Air)
end

local function setGaugePressure(pump, pressure)
	local clamped = math.clamp(tonumber(pressure) or 0, 0, 100)
	if pump.Model and pump.Model.Parent then
		pump.Model:SetAttribute("Level2_PressurePercent", clamped)
		pump.Model:SetAttribute("Level2_PressureRestored", clamped >= 100)
	end
	if pump.GaugePressureValue and pump.GaugePressureValue.Parent then
		pump.GaugePressureValue.Value = clamped
	end
	if pump.GaugePressureText and pump.GaugePressureText.Parent then
		pump.GaugePressureText.Text = string.format("%d%%", math.floor(clamped + .5))
	end
end

local function startPumpGauge(session, pump)
	local duration = session.PumpSoundDuration
	pump.GaugeNeedlePivot.CFrame = pump.GaugeNeedleZeroCFrame
	setGaugePressure(pump, 0)

	local pressureConnection = pump.GaugePressureValue:GetPropertyChangedSignal("Value"):Connect(function()
		if activeSession == session and pump.Model.Parent
			and pump.GaugePressureText and pump.GaugePressureText.Parent then
			local pressure = math.clamp(pump.GaugePressureValue.Value, 0, 100)
			pump.GaugePressureText.Text = string.format("%d%%", math.floor(pressure + .5))
		end
	end)
	table.insert(session.Connections, pressureConnection)

	local gaugeInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local needleTween = TweenService:Create(
		pump.GaugeNeedlePivot,
		gaugeInfo,
		{CFrame = pump.GaugeNeedleFullCFrame}
	)
	local pressureTween = TweenService:Create(
		pump.GaugePressureValue,
		gaugeInfo,
		{Value = 100}
	)
	table.insert(session.GaugeTweens, needleTween)
	table.insert(session.GaugeTweens, pressureTween)
	local completedConnection = pressureTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed
			and validSession(session)
			and pump.Model.Parent then
			setGaugePressure(pump, 100)
		end
	end)
	table.insert(session.Connections, completedConnection)
	needleTween:Play()
	pressureTween:Play()
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

	local doorPositions = {}
	for _, record in ipairs(session.Manifest.PressureDoors) do
		if record.Door and record.Door.Parent then
			table.insert(doorPositions, record.Door.Position)
		end
	end
	-- Fire the authored opening cue in the same server frame that the gates
	-- begin moving. Explicit positions keep it audible when distant doors have
	-- not streamed into a particular client yet.
	fireSound("Level 2 Pressure Door", nil, {DoorPositions = doorPositions})

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
	if exit and exit.Trigger and exit.Trigger.Parent then
		exit.Trigger.CanTouch = true
		TweenService:Create(exit.Trigger,
			TweenInfo.new(.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = .18}
		):Play()
		for _, glow in ipairs(exit.BeamLights or {}) do
			if glow and glow.Parent then glow.Enabled = true end
		end
	end

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
		GaugeTweens = {},
		DebugActivators = {},
		Started = {},
		StartedCount = 0,
		DoorsOpen = false,
		Escaping = {},
		PumpSoundDuration = pumpStartDuration(),
	}
	activeSession = session

	local goal = #manifest.Pumps
	workspace:SetAttribute("Level2Pumps", 0)
	workspace:SetAttribute("Level2PumpGoal", goal)
	workspace:SetAttribute("Level2ExitPowered", false)
	local level2State = state()
	if level2State then
		level2State:SetAttribute("Level2_PumpSoundDuration", session.PumpSoundDuration)
	end
	-- Build leaves the green curtain visible as a destination marker, but only
	-- this live objective session may arm its touch signal.
	manifest.Exit.Trigger.CanTouch = false
	manifest.Exit.Trigger.Transparency = .72
	for _, glow in ipairs(manifest.Exit.BeamLights or {}) do glow.Enabled = false end

	for _, pump in ipairs(manifest.Pumps) do
		local function activate(player)
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
				-- The Slidemouth schedules its post-pump scream from this exact
				-- timestamp (it previously fell back to "whenever I noticed").
				level2State:SetAttribute("Level2_PumpStartedAt" .. tostring(session.StartedCount),
					workspace:GetServerTimeNow())
			end

			-- Start the authored pump motor cue as soon as the lever engages.
			fireSound("Level 2 Pump Start", player)
			startPumpGauge(session, pump)

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

			end)

			-- The final gates release exactly when the third pump's authored motor
			-- clip and its matching 0-to-100 pressure sweep have completed.
			if isFinalPump then
				task.delay(session.PumpSoundDuration, function()
					if not validSession(session) or session.StartedCount < goal then return end
					openPressureDoors(session)
				end)
			end

			fireStatus(
				string.format("PUMP STATION %02d ONLINE", pump.Index),
				string.format("%d OF %d STATIONS RUNNING", session.StartedCount, goal),
				isFinalPump
					and "EQUALIZING PRESSURE"
					or (drained and "DRAINING LOCAL SECTION" or "LOCATE REMAINING STATIONS"),
				1.7
			)
			return true
		end
		session.DebugActivators[pump.Index] = activate
		local connection = pump.Prompt.Triggered:Connect(activate)
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

	-- RoundUI now delivers the full Command Center briefing with radio cue and
	-- subtitles. Keep this controller focused on pump and door progress alerts.
	return session
end

function ObjectiveController.DebugActivatePump(index, player)
	assert(RunService:IsStudio(), "DebugActivatePump is Studio-only")
	local session = assert(activeSession, "Level 2 objective is not running")
	local activate = assert(session.DebugActivators[tonumber(index)], "unknown Level 2 pump index")
	return activate(player)
end

function ObjectiveController.DebugOpenExit()
	assert(RunService:IsStudio(), "DebugOpenExit is Studio-only")
	local session = assert(activeSession, "Level 2 objective is not running")
	session.StartedCount = #session.Manifest.Pumps
	openPressureDoors(session)
	local trigger = session.Manifest.Exit.Trigger
	return {
		DoorsOpen = session.DoorsOpen,
		CanTouch = trigger.CanTouch,
		Transparency = trigger.Transparency,
		Position = trigger.Position,
	}
end

function ObjectiveController.Stop()
	if not activeSession then return end
	disconnectAll(activeSession)
	activeSession = nil
end

return ObjectiveController
