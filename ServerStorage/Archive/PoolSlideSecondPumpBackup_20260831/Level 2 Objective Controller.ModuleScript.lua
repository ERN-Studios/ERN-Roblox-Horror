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

-- LEVEL2_EXIT_TRANSITION_20260828
-- After crossing the completion sensor a rider keeps physically sliding for the
-- whole post-win decision window. GameManager's POST_WIN_SECONDS is 15; at the
-- one-way soft speed cap of 105 studs/s that is 1575 studs of tube, so the
-- builder is required to lay down a comfortable margin beyond it. Nothing here
-- reads GameManager, so the number is asserted rather than assumed.
local MINIMUM_TRANSITION_LENGTH = 2000

-- Recovery tuning. Coming off the path and stalling on it are separate faults
-- with separate graces, because they read differently in a server-side copy of
-- a client-owned character: leaving the bore is unambiguous, whereas "stopped"
-- has to be told apart from ordinary replication jitter.
local TRANSITION_OFFPATH_GRACE = 1.5
local TRANSITION_STALL_GRACE = 3
-- Movement below this per quarter-second sample is not riding. The transition
-- grade never produces anything near it — the ride settles around 20-25 studs
-- per sample — so the margin against jitter is an order of magnitude.
local TRANSITION_STALL_DISTANCE = 2
-- Speed a recovered rider resumes at: immediately moving, but well under the
-- one-way soft cap so a recovery never reads as a launch.
local TRANSITION_RECOVERY_SPEED = 70

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
	-- LEVEL2_EXIT_TRANSITION_20260828
	-- The completion sensors are permanently invisible and unlit. Assert that
	-- here rather than trusting the builder: a sensor that renders is an instant
	-- tell, and it has regressed before by way of a well-meaning tween.
	for _, entry in ipairs({
		{Part = manifest.Exit.Trigger, Label = "completion sensor"},
		{Part = manifest.Exit.Backstop, Label = "completion backstop"},
	}) do
		local sensor = entry.Part
		assert(sensor and sensor:IsA("BasePart") and sensor:IsDescendantOf(manifest.World)
			and sensor:GetAttribute("Level2_ExitCompletionBeam") == true,
			"Level 2 exit " .. entry.Label .. " is missing from the generated world")
		assert(sensor.Transparency == 1 and sensor.CastShadow == false
			and sensor.CanCollide == false,
			"Level 2 exit " .. entry.Label .. " must be invisible and non-colliding")
		-- Roblox parents a TouchTransmitter to any part with a live .Touched
		-- connection, so "no children" is the wrong question. What must never
		-- come back is emissive decoration: this sensor is invisible, forever.
		for _, child in ipairs(sensor:GetChildren()) do
			assert(not child:IsA("Light") and not child:IsA("ParticleEmitter")
				and not child:IsA("Beam") and not child:IsA("Decal")
				and not child:IsA("SurfaceGui") and not child:IsA("BillboardGui"),
				"Level 2 exit " .. entry.Label .. " must carry no lights or decoration ("
					.. child.ClassName .. ")")
		end
		local thickness = sensor:GetAttribute("Level2_ExitCompletionSensorThickness")
		assert(type(thickness) == "number" and thickness >= 8,
			"Level 2 exit " .. entry.Label .. " is too thin to catch a fast slider")
	end
	assert(manifest.Exit.SafeSpawn and manifest.Exit.SafeSpawn:IsA("BasePart")
		and manifest.Exit.SafeSpawn:IsDescendantOf(manifest.World),
		"Level 2 exit recovery spawn is missing from the generated world")
	assert(typeof(manifest.Exit.TransitionEnd) == "Vector3"
		and type(manifest.Exit.TransitionLength) == "number"
		and manifest.Exit.TransitionLength >= MINIMUM_TRANSITION_LENGTH,
		string.format("Level 2 exit transition must run at least %d studs past completion",
			MINIMUM_TRANSITION_LENGTH))
	assert(typeof(manifest.Exit.FlumeBoundsCenter) == "Vector3"
		and typeof(manifest.Exit.FlumeBoundsSize) == "Vector3",
		"Level 2 exit is missing the flume envelope the recovery watchdog needs")
	assert(type(manifest.Exit.PathPoints) == "table" and #manifest.Exit.PathPoints >= 2,
		"Level 2 exit is missing the authored path the recovery watchdog measures against")
	assert(type(manifest.Exit.BoreRadius) == "number" and manifest.Exit.BoreRadius > 0,
		"Level 2 exit is missing its bore radius")
	local recycle = manifest.Exit.Recycle
	assert(type(recycle) == "table"
		and type(recycle.TriggerY) == "number" and type(recycle.DeltaY) == "number"
		and type(recycle.LandingY) == "number" and type(recycle.Radius) == "number"
		and type(recycle.CenterX) == "number" and type(recycle.CenterZ) == "number",
		"Level 2 exit is missing the recycle geometry that makes the ride endless")
	assert(recycle.DeltaY > 0 and recycle.Turns and recycle.Turns >= 3,
		"Level 2 exit recycle needs at least three turns so a recycled rider keeps a full turn of margin")
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
	-- Arming the exit is a pure CanTouch change. The sensors stay at
	-- Transparency 1 with no lights forever; the only thing the player ever sees
	-- change is the flume mouth on the top deck, which is the actual signpost.
	for _, sensor in ipairs({exit and exit.Trigger, exit and exit.Backstop}) do
		if sensor and sensor.Parent then sensor.CanTouch = true end
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
		Transitioning = {},
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
	-- The sensors are invisible for the whole round; only this live objective
	-- session may arm their touch signal. Transparency is re-asserted rather
	-- than merely left alone so a hot-reload or a stale saved place cannot leave
	-- a visible slab hanging in the bore.
	for _, sensor in ipairs({manifest.Exit.Trigger, manifest.Exit.Backstop}) do
		sensor.CanTouch = false
		sensor.Transparency = 1
		sensor.CastShadow = false
	end

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
				local pumpSequence = session.StartedCount
				level2State:SetAttribute("Level2_PumpStartedAt" .. tostring(pumpSequence),
					workspace:GetServerTimeNow())
				level2State:SetAttribute("Level2_PumpActivatorUserId" .. tostring(pumpSequence), player.UserId)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				level2State:SetAttribute("Level2_PumpActivatorPosition" .. tostring(pumpSequence),
					root and root.Position or pump.Model:GetPivot().Position)
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

	-- LEVEL2_EXIT_TRANSITION_20260828
	-- Completion no longer ends the ride. The player is marked Escaped for the
	-- round result, but their momentum is left completely alone: no velocity
	-- zeroing, no PivotTo. Level2_ExitTransition is the companion flag that
	-- tells the slide controller, the ragdoll service and the UI that this
	-- Escaped player is still physically inside the tube, so the ride continues
	-- straight through the 15-second decision window and into Level 3.
	local function completeFor(player, character)
		if session.Escaping[player] then return end
		local liveCharacter = livingCharacter(player)
		if liveCharacter ~= character then return end
		session.Escaping[player] = true
		session.Transitioning[player] = {
			StartedAt = os.clock(),
			LastPosition = nil,
			Travelled = 0,
			OffPathFor = 0,
			StalledFor = 0,
			Recoveries = 0,
		}
		session.ExitSweepPrevious[player] = nil
		player:SetAttribute("Level2_ExitServerRecycleCount", nil)
		player:SetAttribute("Level2_ExitRecoveryCount", nil)
		player:SetAttribute("Escaped", true)
		player:SetAttribute("Level2_ExitTransition", true)
		fireSound("Level 2 Slide Rush", player)
		fireEscape(player)
	end

	for _, sensor in ipairs({manifest.Exit.Trigger, manifest.Exit.Backstop}) do
		local escapeConnection = sensor.Touched:Connect(function(hit)
			if activeSession ~= session or not session.DoorsOpen then return end
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			-- Touch fires for several character parts, and both sensors fire for
			-- the same pass; completeFor latches so only the first one counts.
			if not player or not validPlayer(player, session) then return end
			completeFor(player, character)
		end)
		table.insert(session.Connections, escapeConnection)
	end

	-- .Touched is retained as the cheap common path, but a client-owned rider can
	-- cross even a thick sensor between two server physics samples. Sweep the
	-- HumanoidRootPart segment through each sensor's oriented box as the authority
	-- backstop. Large unrelated teleports are rejected using the replicated
	-- velocity plus a generous hitch margin, so placing a player elsewhere in the
	-- world cannot accidentally complete the level.
	local function segmentIntersectsSensor(fromWorld, toWorld, sensor)
		local from = sensor.CFrame:PointToObjectSpace(fromWorld)
		local to = sensor.CFrame:PointToObjectSpace(toWorld)
		local delta = to - from
		local half = sensor.Size * .5 + Vector3.new(3, 3, 3)
		local minimum, maximum = 0, 1
		local function clip(origin, direction, extent)
			if math.abs(direction) < 1e-6 then
				return math.abs(origin) <= extent
			end
			local near = (-extent - origin) / direction
			local far = (extent - origin) / direction
			if near > far then near, far = far, near end
			minimum = math.max(minimum, near)
			maximum = math.min(maximum, far)
			return minimum <= maximum
		end
		return clip(from.X, delta.X, half.X)
			and clip(from.Y, delta.Y, half.Y)
			and clip(from.Z, delta.Z, half.Z)
	end

	session.ExitSweepPrevious = {}
	local sweepConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if activeSession ~= session then return end
		if not session.DoorsOpen then
			table.clear(session.ExitSweepPrevious)
			return
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local character, _, root = livingCharacter(player)
			if not character or not root or not validPlayer(player, session) then
				session.ExitSweepPrevious[player] = nil
				continue
			end
			local position = root.Position
			local previous = session.ExitSweepPrevious[player]
			session.ExitSweepPrevious[player] = position
			if not previous then continue end
			local distance = (position - previous).Magnitude
			local plausibleDistance = math.max(80,
				root.AssemblyLinearVelocity.Magnitude * math.max(deltaTime, 1 / 60) * 4 + 24)
			if distance > plausibleDistance then continue end
			for _, sensor in ipairs({manifest.Exit.Trigger, manifest.Exit.Backstop}) do
				if sensor.Parent and segmentIntersectsSensor(previous, position, sensor) then
					completeFor(player, character)
					break
				end
			end
		end
	end)
	table.insert(session.Connections, sweepConnection)

	-- ── keeping a rider on the ride ───────────────────────────────────
	-- A bounding box around a helix proves nothing: the box contains the whole
	-- cylinder the helix sweeps, so a rider who falls down the middle of the drum
	-- satisfies it the entire way to the floor. This measures the two things that
	-- actually decide whether someone is still riding:
	--
	--   ON PATH  — distance to the authored polyline, within the bore plus a
	--              tolerance for the server/client position gap.
	--   PROGRESS — ground actually covered. A rider sitting still on the path is
	--              stuck, and stuck is a fault even though containment is happy.
	--
	-- The answer to either failing is to put the rider BACK ON the ride, at the
	-- recycle landing point with the tangent's momentum. Ending the transition is
	-- reserved for someone who cannot be recovered at all.
	local pathPoints = manifest.Exit.PathPoints
	local recycle = manifest.Exit.Recycle
	local pathTolerance = manifest.Exit.BoreRadius + 14

	local function distanceToPath(position)
		local best = math.huge
		for index = 1, #pathPoints - 1 do
			local a = pathPoints[index]
			local ab = pathPoints[index + 1] - a
			local lengthSquared = ab:Dot(ab)
			local t = lengthSquared > 1e-6
				and math.clamp((position - a):Dot(ab) / lengthSquared, 0, 1) or 0
			local distance = (position - (a + ab * t)).Magnitude
			if distance < best then
				best = distance
				if best <= pathTolerance then return best end
			end
		end
		return best
	end

	-- The recycle landing point sits on the helix at the entry angle, one turn
	-- above the trigger, with a full turn of bore still below it. The tangent is
	-- the direction of travel there: the helix winds with DECREASING angle, so it
	-- is the derivative with respect to -angle, plus the descent.
	local landingAngle = math.pi * .5
	local recycleLanding = Vector3.new(
		recycle.CenterX + math.cos(landingAngle) * recycle.Radius,
		recycle.LandingY,
		recycle.CenterZ + math.sin(landingAngle) * recycle.Radius)
	local recycleTangent = (Vector3.new(
		math.sin(landingAngle) * recycle.Radius,
		-recycle.DeltaY / (2 * math.pi),
		-math.cos(landingAngle) * recycle.Radius)).Unit

	-- The recycle itself normally happens on the CLIENT, which owns the
	-- character's physics; a server PivotTo would fight its prediction and the
	-- slide controller's own teleport guard. The ride must not DEPEND on a client
	-- script running, though, so the server performs the identical one-turn lift
	-- as a backstop once a rider has fallen well past the point the client should
	-- have acted at -- half a turn, about three seconds of margin before the
	-- bottom of the drum. For a server-owned character (the probe rig, or a rider
	-- whose ownership has been taken) this is the only recycle there is.
	local recycleFloorY = recycle.TriggerY - recycle.DeltaY * .5

	local function serverRecycle(character, root)
		local position = root.Position
		if position.Y > recycleFloorY then return false end
		local offset = Vector3.new(position.X - recycle.CenterX, 0, position.Z - recycle.CenterZ)
		-- Only a rider actually in the drum wall may be lifted. Someone falling
		-- down the middle is a recovery case, not a recycle case.
		if math.abs(offset.Magnitude - recycle.Radius) > manifest.Exit.BoreRadius + 6 then
			return false
		end
		local velocity = root.AssemblyLinearVelocity
		local spin = root.AssemblyAngularVelocity
		character:PivotTo(character:GetPivot() + Vector3.new(0, recycle.DeltaY, 0))
		root.AssemblyLinearVelocity = velocity
		root.AssemblyAngularVelocity = spin
		return true
	end

	local function placeBackOnRide(character, root)
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(CFrame.lookAt(recycleLanding + Vector3.new(0, 3, 0),
			recycleLanding + Vector3.new(0, 3, 0) + recycleTangent))
		root.AssemblyLinearVelocity = recycleTangent * TRANSITION_RECOVERY_SPEED
	end

	local recoveryAccumulator = 0
	local recoveryConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if activeSession ~= session then return end
		recoveryAccumulator += deltaTime
		if recoveryAccumulator < .25 then return end
		local step = recoveryAccumulator
		recoveryAccumulator = 0
		for player, record in pairs(session.Transitioning) do
			local character, humanoid, root = livingCharacter(player)
			if not character or not root or not humanoid then
				-- Dead, or between characters. The latch is deliberately KEPT: the
				-- round has not resolved and this player is still a rider, so their
				-- transition has to survive the respawn. Re-entry happens on
				-- CharacterAdded below, not here.
				record.OffPathFor = 0
				record.StalledFor = 0
				record.LastPosition = nil
			else
				if serverRecycle(character, root) then
					-- The lift is exactly one helix turn, so the rider lands back
					-- on the authored path travelling in the same direction. It is
					-- not movement, so it must not be counted as progress and must
					-- not be measured as a jump off the path.
					record.LastPosition = nil
					record.OffPathFor = 0
					record.StalledFor = 0
					record.ServerRecycles = (record.ServerRecycles or 0) + 1
					player:SetAttribute("Level2_ExitServerRecycleCount", record.ServerRecycles)
					continue
				end
				local position = root.Position
				local moved = record.LastPosition
					and (position - record.LastPosition).Magnitude or nil
				record.LastPosition = position
				record.Travelled += moved or 0

				if distanceToPath(position) <= pathTolerance then
					record.OffPathFor = 0
				else
					record.OffPathFor += step
				end
				-- Nil moved means this is the first sample since a respawn or since
				-- completion; there is nothing to compare against yet, so it counts
				-- as movement rather than as a stall.
				if not moved or moved > TRANSITION_STALL_DISTANCE then
					record.StalledFor = 0
				else
					record.StalledFor += step
				end

				if record.OffPathFor > TRANSITION_OFFPATH_GRACE
					or record.StalledFor > TRANSITION_STALL_GRACE then
					record.OffPathFor = 0
					record.StalledFor = 0
					record.LastPosition = nil
					record.Recoveries += 1
					player:SetAttribute("Level2_ExitRecoveryCount", record.Recoveries)
					-- The ride is intentionally unbounded. A finite lifetime recovery
					-- budget eventually parked a valid early finisher simply because
					-- their teammates took longer. Keep repairing seam/replication
					-- faults until GameManager causally clears the transition for a
					-- Return Lobby choice or the next level.
					placeBackOnRide(character, root)
				end
			end
		end
	end)
	table.insert(session.Connections, recoveryConnection)

	-- A rider who dies mid-transition keeps the latch, so when their character
	-- comes back they are put straight back on the ride instead of being stranded
	-- somewhere with Escaped set and nothing left to do. The same watcher handles
	-- the opposite decision: GameManager clears Level2_ExitTransition when a rider
	-- presses RETURN TO LOBBY, and that has to stop the ride rather than leave it
	-- looping under someone who has already opted out.
	local function watchRespawn(player)
		table.insert(session.Connections,
			player:GetAttributeChangedSignal("Level2_ExitTransition"):Connect(function()
				if activeSession ~= session then return end
				if player:GetAttribute("Level2_ExitTransition") == true then return end
				if not session.Transitioning[player] then return end
				session.Transitioning[player] = nil
				player:SetAttribute("Level2_ExitServerRecycleCount", nil)
				player:SetAttribute("Level2_ExitRecoveryCount", nil)
				local character, _, root = livingCharacter(player)
				if character and root then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					character:PivotTo(manifest.Exit.SafeSpawn.CFrame * CFrame.new(0, 3, 0))
				end
			end))
		local connection = player.CharacterAdded:Connect(function(character)
			if activeSession ~= session then return end
			if not session.Transitioning[player] then return end
			local root = character:WaitForChild("HumanoidRootPart", 10)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid then return end
			-- Let the spawn placement everything else does settle first, otherwise
			-- it lands on top of this one.
			task.wait(.35)
			local record = session.Transitioning[player]
			if activeSession ~= session or not record or not root.Parent then return end
			placeBackOnRide(character, root)
			record.LastPosition = nil
			record.OffPathFor = 0
			record.StalledFor = 0
		end)
		table.insert(session.Connections, connection)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watchRespawn(player)
	end
	table.insert(session.Connections, Players.PlayerAdded:Connect(watchRespawn))

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

-- Completion is deliberately once-per-player-per-round: session.Escaping latches
-- so both sensors and every touching limb collapse into a single escape. That
-- makes the exit un-retestable inside one generated round, so the transition
-- suite clears the latch between probes. Studio-only, like every other Debug*.
function ObjectiveController.DebugResetCompletion(player)
	assert(RunService:IsStudio(), "DebugResetCompletion is Studio-only")
	local session = assert(activeSession, "Level 2 objective is not running")
	if player then
		session.Escaping[player] = nil
		session.Transitioning[player] = nil
		-- A Studio probe repositions the character before launching it. Retaining
		-- the pre-reset sweep endpoint can turn that placement into a synthetic
		-- segment through the completion beam, completing before the ride starts.
		session.ExitSweepPrevious[player] = nil
		player:SetAttribute("Escaped", nil)
		player:SetAttribute("Level2_ExitTransition", nil)
		player:SetAttribute("Level2_ExitServerRecycleCount", nil)
		player:SetAttribute("Level2_ExitRecoveryCount", nil)
	else
		-- Clear Escaped too. Without it the exit can never re-fire (validPlayer
		-- rejects an Escaped player) and any rider still mid-transition is left
		-- flagged Escaped with the transition already torn down.
		for tracked in pairs(session.Escaping) do
			if tracked.Parent then
				tracked:SetAttribute("Escaped", nil)
				tracked:SetAttribute("Level2_ExitTransition", nil)
				tracked:SetAttribute("Level2_ExitServerRecycleCount", nil)
				tracked:SetAttribute("Level2_ExitRecoveryCount", nil)
			end
		end
		for tracked in pairs(session.Transitioning) do
			if tracked.Parent then
				tracked:SetAttribute("Level2_ExitTransition", nil)
				tracked:SetAttribute("Level2_ExitServerRecycleCount", nil)
				tracked:SetAttribute("Level2_ExitRecoveryCount", nil)
			end
		end
		session.Escaping = {}
		session.Transitioning = {}
		table.clear(session.ExitSweepPrevious)
	end
	return true
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
	-- The transition flag is a live-ride marker. It must never outlive the
	-- session that set it, or a later round would start with a player the slide
	-- controller still believes is mid-transition.
	for player in pairs(activeSession.Transitioning or {}) do
		if player.Parent then
			player:SetAttribute("Level2_ExitTransition", nil)
			player:SetAttribute("Level2_ExitServerRecycleCount", nil)
			player:SetAttribute("Level2_ExitRecoveryCount", nil)
		end
	end
	disconnectAll(activeSession)
	activeSession = nil
end

return ObjectiveController
