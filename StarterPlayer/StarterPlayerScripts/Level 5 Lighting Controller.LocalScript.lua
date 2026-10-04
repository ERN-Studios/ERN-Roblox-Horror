-- Level 5, the void rooms: one per-client lighting owner while the local character is inside the map's
-- bounds, with exact restoration of each property it changes.
--
-- The look depends on there being NO light that the level's own lamps do not make: the rooms are lit by
-- PointLights at walkway height and above, and everything below them has to fall to black. So inside the
-- bounds the sky's contribution and the lobby's atmosphere are taken out. RoundUI stands down while
-- `Level5LightingOwned` is set (the same arrangement as the Level 4 cinema).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local MODEL_NAME = "Level 5 Void"
local WANT = {
	ClockTime = 0, Brightness = 0, Ambient = Color3.new(0, 0, 0), OutdoorAmbient = Color3.new(0, 0, 0),
	EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0, ExposureCompensation = 0.3,
	FogColor = Color3.new(0, 0, 0), FogStart = 0, FogEnd = 100000, GlobalShadows = true,
}
local snapshot, airDensity, air = nil, nil, nil
local grade = nil

local function inside()
	local model = workspace:FindFirstChild(MODEL_NAME)
	local centre, size = model and model:GetAttribute("BoundsCenter"), model and model:GetAttribute("BoundsSize")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if typeof(centre) ~= "Vector3" or typeof(size) ~= "Vector3" or not root then return false end
	local offset = root.Position - centre
	return math.abs(offset.X) <= size.X / 2 + 30 and math.abs(offset.Z) <= size.Z / 2 + 30
		and math.abs(offset.Y) <= size.Y / 2 + 200
end

local function restore()
	if snapshot then
		for property, value in pairs(snapshot) do Lighting[property] = value end
		snapshot = nil
	end
	if air and airDensity and air.Parent == Lighting then air.Density = airDensity end
	air, airDensity = nil, nil
	if grade then grade:Destroy(); grade = nil end
	player:SetAttribute("Level5LightingOwned", nil)
end

local function own()
	if not snapshot then
		snapshot = {}
		for property in pairs(WANT) do snapshot[property] = Lighting[property] end
		air = Lighting:FindFirstChildOfClass("Atmosphere")
		airDensity = air and air.Density or nil
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "Level5VoidGrade"
		grade.Saturation, grade.Contrast, grade.Brightness = 0.08, -0.06, 0
		grade.Parent = Lighting
		player:SetAttribute("Level5LightingOwned", true)
	end
	for property, value in pairs(WANT) do
		if Lighting[property] ~= value then Lighting[property] = value end
	end
	if air and air.Parent == Lighting and air.Density ~= 0 then air.Density = 0 end
	local lobby = Lighting:FindFirstChild("LobbyLocalGrade")
	if lobby and lobby:IsA("ColorCorrectionEffect") and lobby.Enabled then lobby.Enabled = false end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.2 then return end
	elapsed = 0
	if inside() then own() elseif snapshot then restore() end
end)
script.Destroying:Connect(restore)


-- LEVEL5_VOID_20261004: what the level sounds like, and the two lines of text it ever shows.
-- The plates, gates and falling balls are played by the server on the parts themselves (everyone near hears
-- them in place); this is only what belongs to the listener: the room tone, the wind out of the drop, the
-- listener's own fall, the balls rolling near them, and a narrow beam creaking under their feet.
task.spawn(function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local SoundService = game:GetService("SoundService")
	local TweenService = game:GetService("TweenService")
	local folder = ReplicatedStorage:WaitForChild("Level5Void", 60)
	local library = folder and folder:WaitForChild("Sounds", 60)
	local event = folder and folder:WaitForChild("Event", 60)
	if not library or not event then return end
	local AMBIENCE, WIND, EFFECT = 0.13, 0.09, 0.42
	local bank = Instance.new("Folder")
	bank.Name = "Level5VoidSounds"
	bank.Parent = SoundService
	local function clip(name, looped, parent)
		local template = library:FindFirstChild(name)
		if not template then return nil end
		local copy = template:Clone()
		copy.Looped, copy.Volume = looped == true, 0
		copy.Parent = parent or bank
		return copy
	end
	local function oneShot(name, volume)
		local copy = clip(name)
		if not copy then return end
		copy.Volume = volume or EFFECT
		copy:Play()
		copy.Ended:Once(function() copy:Destroy() end)
	end
	local function inLevel() return player:GetAttribute("Level5VoidRound") == true end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Level5VoidHud"
	gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = false, true, 6
	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Parent = gui
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 1)
	line.Position = UDim2.new(0.5, 0, 0.84, 0)
	line.Size = UDim2.new(0.8, 0, 0, 26)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamMedium
	line.TextSize = 20
	line.TextColor3 = Color3.fromRGB(244, 244, 238)
	line.TextStrokeTransparency = 0.6
	line.TextTransparency = 1
	line.Text = ""
	line.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	local shown = 0
	local function say(text, seconds)
		shown += 1
		local token = shown
		line.Text = text
		TweenService:Create(line, TweenInfo.new(0.3), {TextTransparency = 0.05, TextStrokeTransparency = 0.6}):Play()
		task.delay(seconds or 2.6, function()
			if token == shown then TweenService:Create(line, TweenInfo.new(0.8), {TextTransparency = 1, TextStrokeTransparency = 1}):Play() end
		end)
	end
	local function flash(colour, hold)
		cover.BackgroundColor3 = colour
		cover.BackgroundTransparency = 0
		TweenService:Create(cover, TweenInfo.new(hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
	end

	local ambience, wind, fall = clip("l5_ambience", true), clip("l5_depth_wind", true), clip("l5_player_fall")
	local NAMES = {rose = "ROSE", blue = "BLUE", amber = "AMBER", mint = "MINT", violet = "VIOLET", coral = "CORAL   ·   UP",
		orange = "ORANGE   ·   THE SPIRAL", crimson = "CRIMSON   ·   THE RING", teal = "TEAL   ·   THE PILLARS", ivory = "IVORY   ·   THE TOWER"}
	event.OnClientEvent:Connect(function(what, a, b, c, d)
		if what == "died" then
			-- no checkpoints (owner, 2026-10-04): a fall or any other death ends the run; black until the lobby
			if fall then fall:Stop() end
			flash(Color3.new(0, 0, 0), 4.5)
			say("YOU FELL", 3)
		elseif what == "checkpoint" then
			if d then
				oneShot("l5_section_tone", 0.4)
				say(NAMES[c] or "", 3.2)
			end
		elseif what == "arrive" then
			say("ROSE   ·   STAY ON THE LEDGES", 4)
		elseif what == "finish" then
			oneShot("l5_finish", 0.5)
			flash(Color3.new(1, 1, 1), 2.4)
		end
	end)

	-- FOOTSTEPS_20261004: the level's own steps (boots on plaster). The first version was two loops and the owner
	-- rejected it; a loop never lines up with the feet. Each step is now ONE recorded step, played when the body
	-- has covered a stride on the ground: six walking steps and four running ones, never the same twice in a row,
	-- each a little different in pitch and level. A landing sounds after every jump.
	local STRIDE_WALK, STRIDE_RUN = 6.4, 7.8
	local WALK_STEPS = {"l5_step_1", "l5_step_2", "l5_step_3", "l5_step_4", "l5_step_5", "l5_step_6"}
	local RUN_STEPS = {"l5_stepr_1", "l5_stepr_2", "l5_stepr_3", "l5_stepr_4"}
	local covered, lastStep = 0, nil
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not inLevel() then covered = 0 return end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local body = humanoid and humanoid.RootPart
		if not body or humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then return end
		local velocity = body.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if flat < 2 then covered = STRIDE_WALK * 0.6 return end       -- the first step comes soon after setting off
		covered += flat * dt
		local running = humanoid.WalkSpeed > 20
		if covered < (running and STRIDE_RUN or STRIDE_WALK) then return end
		covered = 0
		local list = running and RUN_STEPS or WALK_STEPS
		local name
		repeat name = list[math.random(#list)] until name ~= lastStep
		lastStep = name
		local step = clip(name)
		if not step then return end
		-- owner, 2026-10-04: 70% quieter than the first mix (was 0.42 running / 0.3 walking, landing 0.32)
		-- and again the same day, "by a lot": another 70% off (now 0.038 running / 0.027 walking, landing 0.03)
		step.Volume = (running and 0.038 or 0.027) * (0.85 + math.random() * 0.3) * math.clamp(flat / 12, 0.5, 1)
		step.PlaybackSpeed = 0.94 + math.random() * 0.12
		step:Play()
		step.Ended:Once(function() step:Destroy() end)
	end)
	local landed = setmetatable({}, {__mode = "k"})
	local function hookLanding(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or landed[humanoid] then return end
		landed[humanoid] = true
		humanoid.StateChanged:Connect(function(_, state)
			if state == Enum.HumanoidStateType.Landed and inLevel() then oneShot("l5_land", 0.03) end
		end)
	end
	-- AMBIENT_20261004: now and then something far off in the hall. Each plays once from a random point well
	-- away from the listener, so it has a direction and never the same one twice.
	local AMBIENT = {"l5_amb_knock", "l5_amb_door", "l5_amb_groan", "l5_amb_gust", "l5_amb_ball", "l5_amb_steps",
		"l5_amb_chime", "l5_amb_drip", "l5_amb_hum", "l5_amb_breath",
		-- the darker set (2026-10-04): something dragged far below, a whisper, a giggle, an impact in the pit,
		-- the structure bending, a cry falling away, a heartbeat in the walls, a dissonant swell
		"l5_amb_scrape", "l5_amb_whisper", "l5_amb_laugh", "l5_amb_thud", "l5_amb_metal", "l5_amb_fallaway",
		"l5_amb_heartbeat", "l5_amb_tone"}
	local nextAmbient, lastAmbient = os.clock() + 10 + math.random() * 10, nil
	local function ambientAt(position)
		local name
		repeat name = AMBIENT[math.random(#AMBIENT)] until name ~= lastAmbient
		lastAmbient = name
		local angle, distance = math.random() * math.pi * 2, 45 + math.random() * 70
		local holder = Instance.new("Part")
		holder.Name = "Level5Ambient"
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Position = position + Vector3.new(math.cos(angle) * distance, -30 + math.random() * 50, math.sin(angle) * distance)
		holder.Parent = workspace
		local sound = clip(name, false, holder)
		if not sound then holder:Destroy() return end
		sound.Volume = 0.45 + math.random() * 0.3
		sound.PlaybackSpeed = 0.92 + math.random() * 0.16
		sound.RollOffMode, sound.RollOffMinDistance, sound.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 30, 260
		sound:Play()
		sound.Ended:Once(function() holder:Destroy() end)
		task.delay(12, function() if holder.Parent then holder:Destroy() end end)
	end

	local rolling = setmetatable({}, {__mode = "k"})
	local nextCreak = os.clock() + 8
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Include
	while true do
		task.wait(0.1)
		local on = inLevel()
		for bed, level in pairs({[ambience or false] = AMBIENCE, [wind or false] = WIND}) do
			if bed then
				local target = on and level or 0
				bed.Volume += (target - bed.Volume) * 0.12
				if on and not bed.IsPlaying then bed:Play() elseif not on and bed.IsPlaying and bed.Volume < 0.005 then bed:Stop() end
			end
		end
		local model = workspace:FindFirstChild(MODEL_NAME)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not on or not model or not root or not humanoid then
			if fall and fall.IsPlaying then fall:Stop() end
			continue
		end
		hookLanding(character)
		if os.clock() > nextAmbient then
			nextAmbient = os.clock() + 14 + math.random() * 20
			ambientAt(root.Position)
		end
		-- the listener's own fall: the rush starts once the drop is real, and the server's "died" cuts it
		if fall then
			if root.AssemblyLinearVelocity.Y < -70 then
				if not fall.IsPlaying then fall.Volume = 0.45; fall:Play() end
			elseif fall.IsPlaying and root.AssemblyLinearVelocity.Y > -5 then
				fall:Stop()
			end
		end
		local balls = model:FindFirstChild("Balls")
		for _, ball in ipairs(balls and balls:GetChildren() or {}) do
			if not ball:IsA("BasePart") then continue end
			local near = (ball.Position - root.Position).Magnitude < 90 and ball.Transparency < 1
			local state = rolling[ball]
			if near and not state then
				local roll = clip("l5_ball_roll", true, ball)
				if roll then
					roll.RollOffMode, roll.RollOffMinDistance, roll.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 8, 90
					roll:Play()
					state = {roll = roll, speed = 0}
					rolling[ball] = state
				end
			end
			if state then
				local velocity = ball.AssemblyLinearVelocity
				local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				local target = (near and math.abs(velocity.Y) < 4) and math.clamp(flat / 14, 0, 1) * 0.5 or 0
				state.roll.Volume += (target - state.roll.Volume) * 0.45
				state.roll.PlaybackSpeed = 0.8 + math.clamp(flat / 30, 0, 0.5)
				if near and flat - state.speed > 3.5 and os.clock() > (state.hit or 0) then      -- kicked into motion
					state.hit = os.clock() + 0.5
					local hit = clip("l5_ball_hit", false, ball)
					if hit then
						hit.Volume = 0.4
						hit.RollOffMode, hit.RollOffMinDistance, hit.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 8, 90
						hit:Play()
						hit.Ended:Once(function() hit:Destroy() end)
					end
				end
				state.speed = flat
				if not near and state.roll.Volume < 0.01 then state.roll:Destroy(); rolling[ball] = nil end
			end
		end
		-- a beam one body wide complains now and then
		if os.clock() > nextCreak then
			nextCreak = os.clock() + 7 + math.random() * 9
			down.FilterDescendantsInstances = {model}
			local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), down)
			if hit and hit.Instance.Name == "Walk" and hit.Instance.Size.Z <= 3.7
				and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 4 then
				oneShot("l5_edge_creak", 0.3)
			end
		end
	end
end)
