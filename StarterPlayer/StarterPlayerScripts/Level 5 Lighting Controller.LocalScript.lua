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
	local devFall = nil                                          -- set by the falling block further down
	-- DEV_FALL_20261005 (owner: "dev button that triggers a fall and scream"): a button and the O key, for the
	-- developers and the owner's own account (the Level 6 dev ESP's list). It only asks; the server checks who
	-- is asking and tells every player in the level, so they all see and hear the same body.
	do
		local found, DevAccess = pcall(function() return require(ReplicatedStorage:WaitForChild("DevAccess", 10)) end)
		if found and DevAccess and DevAccess.IsLevel6PreviewAllowed(player) then
			local UserInputService = game:GetService("UserInputService")
			local button = Instance.new("TextButton")
			button.Name = "DevFall"
			button.AnchorPoint = Vector2.new(1, 0)
			button.Position = UDim2.new(1, -14, 0, 64)
			button.Size = UDim2.fromOffset(184, UserInputService.TouchEnabled and 44 or 32)
			button.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
			button.BackgroundTransparency = 0.25
			button.BorderSizePixel = 0
			button.Font = Enum.Font.GothamMedium
			button.TextSize = 13
			button.TextColor3 = Color3.fromRGB(240, 236, 220)
			button.Text = UserInputService.KeyboardEnabled and "DEV  ·  DROP A BODY  [O]" or "DEV  ·  DROP A BODY"
			button.Visible = false
			button.ZIndex = 0                                      -- under the cover: it is not part of a death screen
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = button
			local stroke = Instance.new("UIStroke")
			stroke.Color, stroke.Transparency, stroke.Thickness = Color3.fromRGB(240, 236, 220), 0.7, 1
			stroke.Parent = button
			button.Parent = gui
			local function ask()
				if inLevel() then event:FireServer("devfall") end
			end
			button.Activated:Connect(ask)
			UserInputService.InputBegan:Connect(function(input, processed)
				if not processed and input.KeyCode == Enum.KeyCode.O then ask() end
			end)
			task.spawn(function()
				while true do
					button.Visible = inLevel()
					task.wait(0.5)
				end
			end)
		end
	end
	-- FINALE_20261005: the corridor at the top of the last room. The server moves the block, the gate and the walls
	-- and plays their sounds on them; this is only the listener's share of it, and only for a listener who is
	-- there: the jolt of the block landing, one line, and the corridor's lamps going red while the walls come in.
	local crusher
	do
		local lamps = {}                                          -- PointLight -> {its colour, its brightness}
		local closingUntil = 0
		local function near()
			local model = workspace:FindFirstChild(MODEL_NAME)
			local parts = model and model:FindFirstChild("Finale")
			local block = parts and parts:FindFirstChild("CrusherBlock")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			return inLevel() and block ~= nil and root ~= nil and (block.Position - root.Position).Magnitude < 420, model
		end
		local function jolt(strength, seconds)
			if player:GetAttribute("ReduceCameraShake") == true then return end
			local began = os.clock()
			local name = "Level5Jolt" .. tostring(began)
			RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
				local left = 1 - (os.clock() - began) / seconds
				if left <= 0 then RunService:UnbindFromRenderStep(name) return end
				local camera = workspace.CurrentCamera
				camera.CFrame *= CFrame.new((math.random() - 0.5) * strength * left, (math.random() - 0.5) * strength * left, 0)
			end)
		end
		local function redden(on, model)
			local holders = model and model:FindFirstChild("Lights")
			if on and holders then
				for _, holder in ipairs(holders:GetChildren()) do
					local lamp = holder.Name == "CrusherLight" and holder:FindFirstChildOfClass("PointLight")
					if lamp and not lamps[lamp] then lamps[lamp] = {lamp.Color, lamp.Brightness} end
				end
			end
			for lamp, own in pairs(lamps) do
				if lamp.Parent then
					TweenService:Create(lamp, TweenInfo.new(on and 0.6 or 1.5),
						{Color = on and Color3.fromRGB(255, 52, 40) or own[1], Brightness = on and own[2] * 1.4 or own[2]}):Play()
				end
			end
			if not on then table.clear(lamps) end
		end
		-- the red swells, slowly at first and quicker as the walls come in; still under ReduceFlashing
		RunService.Heartbeat:Connect(function()
			local left = closingUntil - os.clock()
			if left <= 0 or player:GetAttribute("ReduceFlashing") == true then return end
			local swell = 0.5 + 0.5 * math.sin(os.clock() * (4 + 6 * math.clamp(1 - left / 16, 0, 1)))
			for lamp, own in pairs(lamps) do
				if lamp.Parent then lamp.Brightness = own[2] * (1.0 + 0.8 * swell) end
			end
		end)
		crusher = function(what, seconds, all)
			local there, model = near()
			if what == "reset" then
				closingUntil = 0
				redden(false, model)
			elseif not there then
				return
			elseif what == "waiting" then
				-- the gate ahead is shut until the whole party stands in here (`seconds` is how many do)
				say(string.format("WAITING FOR THE OTHERS   ·   %d / %d", tonumber(seconds) or 0, tonumber(all) or 0), 4)
			elseif what == "slam" then
				jolt(0.9, 0.7)
				say("THE WAY BACK IS SHUT", 2.2)
			elseif what == "closing" then
				closingUntil = os.clock() + (tonumber(seconds) or 16) + 1
				redden(true, model)
				say("THE WALLS ARE CLOSING", 3.4)
			elseif what == "shut" then
				closingUntil = 0
				jolt(1.3, 0.9)
			end
		end
	end
	local NAMES = {rose = "ROSE", blue = "BLUE", amber = "AMBER", mint = "MINT", violet = "VIOLET", coral = "CORAL   ·   UP",
		orange = "ORANGE   ·   THE SPIRAL", crimson = "CRIMSON   ·   THE CLIMB", teal = "TEAL   ·   THE PILLARS", ivory = "IVORY   ·   THE TOWER"}
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
			flash(Color3.new(1, 1, 1), 0.7)             -- short: the LEVEL 5 CLEARED screen comes up behind it
		elseif what == "devfall" then
			if devFall then devFall(a, b) end
		elseif what == "crusher" then
			crusher(a, b, c)
		elseif what == "crushed" then
			if fall then fall:Stop() end
			flash(Color3.new(0, 0, 0), 1.8)             -- black for a moment; the party's death screen is RoundUI's
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

	-- FALLING_20261005 (owner: "randomly have objects falling down, not hitting the pathway, just falling from the
	-- ceiling to the pit, and sometimes make sure it is a player ... with a falling scream that comes loud in the
	-- level and fades when they go down, like someone observing a true fall"). Things drop past, out of the dark
	-- above and into the dark below: blocks and balls about every twelve seconds, and about once a minute a body in
	-- a hazmat suit, arms and legs going, with a scream that is close for a moment and then far below. Local parts,
	-- moved here, never colliding. WHAT falls WHERE is drawn from the server's clock and the stretch of the level
	-- the listener is in, so players standing together see and hear the same fall.
	--
	-- PILLAR_HIT_20261005 (owner: "a person can randomly fall and hit that pillar on the top and then ragdoll down
	-- the pit after the hit/bounce"). Where a loose pillar stands near enough, some of the bodies come down ON its
	-- top instead of past it: the scream stops on the stone, the body bounces, goes over the side that faces away
	-- from the path and falls on limp, arms and legs trailing behind it.
	--
	-- DEV_FALL_20261005: a developer's button (Level5PreviewAccess checks who asks and tells the whole level) drops
	-- one on demand; every second one is aimed at a pillar when there is one.
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local HttpService = game:GetService("HttpService")
		local holder = Instance.new("Folder")
		holder.Name = "Level5Falling"
		local route, routeOf = nil, nil
		-- {parts = {{part, offset, swing, phase, dir}}, at, velocity, turn, spin, sound, loud, fadeAt, born, person,
		--  floor, strikeY, away, bounceOut, spinAfter, thudSpeed, hit, holdUntil}
		local things = {}
		local YELLOW, DARK = Color3.fromRGB(232, 190, 40), Color3.fromRGB(16, 16, 18)
		local DOWN = Vector3.new(0, -1, 0)
		local function block(size, colour, shape)
			local part = Instance.new("Part")
			part.Size, part.Color, part.Material = size, colour, Enum.Material.SmoothPlastic
			if shape then part.Shape = shape end
			part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
			part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			part.Parent = holder
			return part
		end
		-- How far (x, z) is from the path in plan, and the direction that leads away from it. The path is the line
		-- through the route's points: measuring to the points alone missed the middle of a long ledge.
		local function pathGap(model, origin, x, z)
			if routeOf ~= model then
				local value = model:FindFirstChild("Route")
				local ok, decoded = pcall(function() return HttpService:JSONDecode(value.Value) end)
				route, routeOf = ok and decoded or {}, model
			end
			local best, awayX, awayZ = math.huge, 1, 0
			local px, pz = x - origin.X, z - origin.Z
			for index = 1, #route - 1 do
				local a, b = route[index], route[index + 1]
				local ex, ez = b.x - a.x, b.z - a.z
				local length = ex * ex + ez * ez
				local t = length > 0 and math.clamp(((px - a.x) * ex + (pz - a.z) * ez) / length, 0, 1) or 0
				local dx, dz = px - (a.x + ex * t), pz - (a.z + ez * t)
				local gap = dx * dx + dz * dz
				if gap < best then best, awayX, awayZ = gap, dx, dz end
			end
			local away = Vector3.new(awayX, 0, awayZ)
			return math.sqrt(best), away.Magnitude > 0.01 and away.Unit or Vector3.xAxis
		end
		local function clearOfPath(model, origin, x, z)
			return (pathGap(model, origin, x, z)) >= 12
		end
		-- A loose pillar whose top the listener can see: not on the path, not right beside them, not far below.
		local function pillarNear(model, origin, rng, near, floorY)
			local geometry = model:FindFirstChild("Geometry")
			if not geometry then return nil end
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = {geometry}
			local found = {}
			for _, part in ipairs(workspace:GetPartBoundsInRadius(Vector3.new(near.X, floorY, near.Z), 80, params)) do
				if part.Name == "Monolith" and math.min(part.Size.X, part.Size.Z) >= 5 then
					local top = part.Position.Y + part.Size.Y / 2
					local flat = Vector3.new(part.Position.X - near.X, 0, part.Position.Z - near.Z).Magnitude
					if flat > 14 and flat < 74 and top > floorY - 64 and top < floorY + 36
						and clearOfPath(model, origin, part.Position.X, part.Position.Z) then
						table.insert(found, part)
					end
				end
			end
			if #found == 0 then return nil end
			-- the same order on every client, whatever order the query answered in
			table.sort(found, function(a, b)
				if a.Position.X ~= b.Position.X then return a.Position.X < b.Position.X end
				return a.Position.Z < b.Position.Z
			end)
			return found[rng:NextInteger(1, #found)]
		end
		-- the rotation that takes a limb's own "down" to `dir`
		local function hang(dir)
			local axis = DOWN:Cross(dir)
			local dot = math.clamp(DOWN:Dot(dir), -1, 1)
			if axis.Magnitude < 1e-4 then return dot > 0 and CFrame.identity or CFrame.Angles(math.pi, 0, 0) end
			return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
		end
		-- `strike`: true = onto a pillar if one stands near, false = never, nil = sometimes
		local function drop(model, origin, rng, person, floorY, near, strike)
			local x, z
			local pillar = nil
			if person and (strike == true or (strike == nil and rng:NextNumber() < 0.45)) then
				pillar = pillarNear(model, origin, rng, near, floorY)
			end
			local away, strikeY
			if pillar then
				-- onto the top, toward the side that faces away from the path, so it goes over that edge
				local _, lead = pathGap(model, origin, pillar.Position.X, pillar.Position.Z)
				local turn = math.rad(rng:NextNumber(20, 65)) * (rng:NextNumber() < 0.5 and -1 or 1)
				away = Vector3.new(lead.X * math.cos(turn) - lead.Z * math.sin(turn), 0, lead.X * math.sin(turn) + lead.Z * math.cos(turn))
				local reach = math.max(0.4, math.min(pillar.Size.X, pillar.Size.Z) / 2 - 1.4)
				local spot = pillar.Position + away * rng:NextNumber(0.3, reach)
				x, z = spot.X, spot.Z
				strikeY = pillar.Position.Y + pillar.Size.Y / 2 + 1.1
			else
				for _ = 1, 10 do                              -- somewhere off the path; a body falls where it can be seen
					if person then
						local angle, far = rng:NextNumber(0, math.pi * 2), rng:NextNumber(16, 42)
						x, z = near.X + math.cos(angle) * far, near.Z + math.sin(angle) * far
					else
						x, z = near.X + rng:NextNumber(-90, 90), origin.Z + rng:NextNumber(-52, 52)
					end
					if math.abs(z - origin.Z) < 58 and clearOfPath(model, origin, x, z) then break end
					x = nil
				end
			end
			if not x then return end
			-- from the ceiling where the room has one, from the dark where it has not
			local params = RaycastParams.new()
			params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Include, {model}
			local from = math.max(floorY + 8, (strikeY or floorY) + 6)
			local roof = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, 420, 0), params)
			local top = (roof and roof.Instance.Name == "Ceiling") and roof.Position.Y - 3 or floorY + 190
			local thing = {parts = {}, at = Vector3.new(x, top, z), velocity = Vector3.new(0, -18, 0), born = os.clock(), person = person,
				turn = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
				spin = Vector3.new(rng:NextNumber(-2.4, 2.4), rng:NextNumber(-2.4, 2.4), rng:NextNumber(-2.4, 2.4)), floor = floorY}
			if person then
				local function limb(size, colour, offset, swing)
					table.insert(thing.parts, {part = block(size, colour), offset = offset, swing = swing, phase = rng:NextNumber(0, 6), dir = DOWN})
				end
				limb(Vector3.new(2, 2, 1), YELLOW, CFrame.new(0, 0, 0))                                   -- torso
				limb(Vector3.new(1.3, 1.3, 1.3), YELLOW, CFrame.new(0, 1.65, 0))                          -- hood
				limb(Vector3.new(1.0, 0.7, 0.2), DARK, CFrame.new(0, 1.7, -0.62))                         -- visor
				limb(Vector3.new(1, 2, 1), YELLOW, CFrame.new(-1.5, 0.6, 0), Vector3.new(0, -0.9, 0))     -- arms, from the shoulder
				limb(Vector3.new(1, 2, 1), YELLOW, CFrame.new(1.5, 0.6, 0), Vector3.new(0, -0.9, 0))
				limb(Vector3.new(1, 2, 1), DARK, CFrame.new(-0.5, -1.1, 0), Vector3.new(0, -0.9, 0))      -- legs, from the hip
				limb(Vector3.new(1, 2, 1), DARK, CFrame.new(0.5, -1.1, 0), Vector3.new(0, -0.9, 0))
				thing.spin *= 0.45
				-- the level's own falling sound, or one of the recorded screams (owner, 2026-10-05); a key that is not
				-- installed yet falls back to the first
				local choice = rng:NextInteger(0, 6)
				if strikeY and choice == 0 then choice = rng:NextInteger(1, 6) end   -- a body that hits has a voice to lose
				local voice = (choice > 0 and clip("l5_fall_scream_" .. choice, false, thing.parts[1].part))
					or clip("l5_player_fall", false, thing.parts[1].part)
				if voice then
					voice.Volume = 0                                   -- it fades in; the Heartbeat below owns the level
					voice.RollOffMode, voice.RollOffMinDistance, voice.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 26, 420
					voice:Play()
					thing.sound = voice
					-- the screams were "a little too loud" (owner, 2026-10-05): 1.1 at the peak, was 1.6, and the
					-- recordings themselves are 2 dB lower. The level's own rush is a far quieter recording and
					-- keeps the level it had
					thing.loud = voice.Name == "l5_player_fall" and 1.6 or 1.1
				end
				thing.fadeAt = strikeY and 5.0 or 3.0                  -- one that hits is still screaming when it does
				if strikeY then
					thing.strikeY, thing.away = strikeY, away
					thing.bounceOut = rng:NextNumber(9, 13)
					local across = Vector3.new(-away.Z, 0, away.X)     -- it rolls over the edge it leaves by
					thing.spinAfter = across * rng:NextNumber(4.5, 7) + Vector3.new(0, rng:NextNumber(-1.5, 1.5), 0)
					thing.thudSpeed = rng:NextNumber(0.86, 1.08)       -- one recording, never quite the same twice
				end
			else
				local kind = rng:NextInteger(1, 4)
				local shade = rng:NextNumber() < 0.5 and Color3.fromRGB(22, 22, 25) or Color3.fromRGB(226, 222, 208)
				local size = kind == 1 and Vector3.one * rng:NextNumber(2, 6)
					or kind == 2 and Vector3.new(rng:NextNumber(5, 12), rng:NextNumber(0.6, 1.4), rng:NextNumber(3, 6))
					or Vector3.new(rng:NextNumber(2, 5), rng:NextNumber(2, 8), rng:NextNumber(2, 5))
				table.insert(thing.parts, {part = block(size, shade, kind == 1 and Enum.PartType.Ball or nil), offset = CFrame.new()})
				if size.Magnitude > 7 then
					local rush = clip("l5_debris_whoosh", false, thing.parts[1].part)
					if rush then
						rush.Volume = 0.7
						rush.RollOffMode, rush.RollOffMinDistance, rush.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 14, 160
						rush:Play()
					end
				end
			end
			table.insert(things, thing)
		end
		-- the stone: the scream stops, a thud and a little dust, a beat of stillness, then over the side
		local function land(thing)
			thing.hit = os.clock()
			thing.holdUntil = thing.hit + 0.09
			local impact = -thing.velocity.Y
			thing.at = Vector3.new(thing.at.X, thing.strikeY, thing.at.Z)
			thing.velocity = thing.away * thing.bounceOut + Vector3.new(0, math.clamp(impact * 0.2, 11, 18), 0)
			thing.spin = thing.spinAfter
			local torso = thing.parts[1].part
			local voice = thing.sound
			if voice then
				thing.sound = nil
				voice.Volume *= 0.2
				task.delay(0.06, function() if voice.Parent then voice:Stop() end end)
			end
			local thud = clip("l5_body_hit_1", false, torso) or clip("l5_amb_thud", false, torso) or clip("l5_land", false, torso)
			if thud then
				thud.Volume = 1.5
				thud.PlaybackSpeed = thing.thudSpeed or 1
				thud.RollOffMode, thud.RollOffMinDistance, thud.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 22, 320
				thud:Play()
			end
			local puff = block(Vector3.one, DARK)
			puff.Transparency = 1
			puff.Position = thing.at - Vector3.new(0, 1, 0)
			local dust = Instance.new("ParticleEmitter")
			dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
			dust.Color = ColorSequence.new(Color3.fromRGB(196, 192, 182))
			dust.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1)})
			dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 4.5)})
			dust.Lifetime, dust.Speed = NumberRange.new(0.5, 1.0), NumberRange.new(3, 9)
			dust.SpreadAngle, dust.Rate, dust.LightEmission = Vector2.new(180, 180), 0, 0
			dust.Parent = puff
			dust:Emit(14)
			task.delay(1.6, function() puff:Destroy() end)
		end
		devFall = function(position, serial)
			local model = workspace:FindFirstChild(MODEL_NAME)
			local origin = model and model:GetAttribute("Origin")
			if not inLevel() or typeof(origin) ~= "Vector3" or typeof(position) ~= "Vector3" or #things >= 8 then return end
			holder.Parent = workspace
			serial = tonumber(serial) or 1
			drop(model, origin, Random.new(serial * 7919 + 13), true, position.Y - 3, position, serial % 2 == 0)
		end
		RunService.Heartbeat:Connect(function(dt)
			for index = #things, 1, -1 do
				local thing = things[index]
				local age = os.clock() - thing.born
				if thing.strikeY and not thing.hit and thing.at.Y <= thing.strikeY then land(thing) end
				if not (thing.holdUntil and os.clock() < thing.holdUntil) then
					local gravity = thing.person and (thing.hit and 96 or 62) or 110
					local terminal = thing.person and (thing.hit and 118 or 92) or 150
					local velocity = thing.velocity
					local drag = thing.hit and math.max(0, 1 - 0.5 * dt) or 1
					thing.velocity = Vector3.new(velocity.X * drag, math.max(velocity.Y - gravity * dt, -terminal), velocity.Z * drag)
					thing.at += thing.velocity * dt
					thing.turn *= CFrame.Angles(thing.spin.X * dt, thing.spin.Y * dt, thing.spin.Z * dt)
				end
				local base = CFrame.new(thing.at) * thing.turn
				for _, piece in ipairs(thing.parts) do
					local frame = base * piece.offset
					if piece.swing then                             -- a limb: hinged at its top
						local hinge = CFrame.new(-piece.swing)
						if thing.hit then
							-- limp: it trails behind the way the body is going, each limb in its own time
							local speed = thing.velocity.Magnitude
							local want = speed > 0.5 and base:VectorToObjectSpace(-thing.velocity / speed) or piece.dir
							local dir = piece.dir + (want - piece.dir) * math.min(1, dt * (3.2 + piece.phase * 0.6))
							piece.dir = dir.Magnitude > 0.01 and dir.Unit or DOWN
							frame = base * piece.offset * hinge * hang(piece.dir) * hinge:Inverse()
						else
							frame = base * piece.offset * hinge * CFrame.Angles(math.sin(age * 9 + piece.phase) * 1.1, 0, math.cos(age * 7 + piece.phase) * 0.7) * hinge:Inverse()
						end
					end
					piece.part.CFrame = frame
				end
				if thing.sound then
					-- in over the first half second, held, and out again as the body goes down: with the distance
					-- roll-off on top, it is loud as it passes and gone before the dark takes it
					thing.sound.PlaybackSpeed = math.clamp(1.04 - age * 0.035, 0.82, 1.04)
					thing.sound.Volume = thing.loud * math.clamp(age / 0.5, 0, 1) * math.clamp(1 - (age - thing.fadeAt) / 2.6, 0, 1)
				end
				if thing.at.Y < thing.floor - 330 or age > (thing.strikeY and 16 or 12) or not inLevel() then
					for _, piece in ipairs(thing.parts) do piece.part:Destroy() end
					table.remove(things, index)
				end
			end
		end)
		local lastSlot = 0
		while true do
			task.wait(0.25)
			local model = workspace:FindFirstChild(MODEL_NAME)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local origin = model and model:GetAttribute("Origin")
			if not inLevel() or not root or not origin then
				holder.Parent = nil
				continue
			end
			holder.Parent = workspace
			local slot = math.floor(workspace:GetServerTimeNow() / 2)
			if slot ~= lastSlot then
				lastSlot = slot
				local cell = math.floor((root.Position.X - origin.X) / 60 + 0.5)   -- players near each other share a stretch
				local rng = Random.new(slot * 977 + cell * 31)
				local dice = rng:NextNumber()
				if dice < 0.17 and #things < 6 then
					-- about the stretch the listener is in: a body falls 16 to 42 studs from its middle, close enough to watch
					local anchor = Vector3.new(origin.X + cell * 60, 0, origin.Z + math.floor((root.Position.Z - origin.Z) / 60 + 0.5) * 60)
					drop(model, origin, rng, dice < 0.03, root.Position.Y - 3, anchor)
				end
			end
		end
	end)

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
