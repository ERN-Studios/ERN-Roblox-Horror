-- Level 4 Round Client: everything the cinema round "Den Sidste Forestilling" shows on one client.
-- The server decides (Level 4 Light Director / Objective Controller / Usher Controller); this only presents:
--   * objective panel, captions, the opening briefing, hidden / carrying chips
--   * zone light rendering: stutters announced by ClientEvent {Type="Zones"} (Brightness + neon, local only, landing
--     on exactly the server's final state; ReduceFlashing fades instead) and a 1 s repair pass for stale local writes
--   * the power-up "woooow": surge flash, a low rumble (none with ReduceCameraShake), the title card
--   * film flicker on running screens, the exit screen and the credits music in the finale
--   * the arcade keypad (KeypadSubmit) and the Usher: a local rig drawn from UsherMotion (interpolated 0.1 s behind
--     server time) and animated from ReplicatedStorage."Level 4 Usher Animations" with procedural overlays
-- Nothing here is authority; a client that drops this script still plays the same round.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
-- MOBILE_QA_20261008: where the card, the keypad and the note stand on a touch screen is asked of UIDevice
-- (see placeForDevice): at their desktop places they lay under the phone's buttons.
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local RoundHud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local MODEL_NAME = "Level 4 Cinema Blender"
local STATE_NAME = "Level 4 State"
local REMOTES_NAME = "Level 4 Remotes"
local USHER_VISUAL = "Level 4 Usher Visual"
local INTERP_DELAY = 0.12
local AUDIO = {   -- asset ids (0 = silent)
	Thunk = 9119716840,        -- ProSoundEffects "Switch Circuit Breaker Clicks 4", one per zone in the power-up wave
	Surge = 156221488,         -- "Lights Turning On" (large lights)
	Credits = 110165881068277, -- "Old Cinema"
	Keypad = 557143012,        -- "smallbeep"
}

local MAGENTA = Color3.fromRGB(255, 70, 200)
local CYAN = Color3.fromRGB(80, 235, 255)
local WHITE = Color3.fromRGB(240, 236, 255)

-- ---------------------------------------------------------------- helpers

local function roundLive()
	return workspace:GetAttribute("Level4RoundActive") == true and workspace:GetAttribute("SelectedLevel") == 4
		and workspace:GetAttribute("RoundActive") == true
end
local function stateFolder() return ReplicatedStorage:FindFirstChild(STATE_NAME) end
local function st(name)
	local folder = stateFolder()
	return folder and folder:GetAttribute(name)
end
local function involved()
	return roundLive() and player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true
end
local function reduceFlashing() return player:GetAttribute("ReduceFlashing") ~= false end
local function reduceShake() return player:GetAttribute("ReduceCameraShake") == true end
local function captionsOn()
	return player:GetAttribute("CaptionsEnabled") ~= false and player:GetAttribute("DisableCaptions") ~= true
end
local function cinema() return workspace:FindFirstChild(MODEL_NAME) end

local function playSound(id, parent, volume)
	if not id or id == 0 then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume or 0.8
	s.Parent = parent or workspace.CurrentCamera
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(15, function() if s.Parent then s:Destroy() end end)
end

local function playAt(id, position, volume)
	if not id or id == 0 then return end
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume or 0.8
	s.RollOffMaxDistance = 140
	s.Parent = a
	s:Play()
	task.delay(8, function() a:Destroy() end)
end

-- ---------------------------------------------------------------- UI

local gui = Instance.new("ScreenGui")
gui.Name = "Level4RoundGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = WHITE
	l.TextStrokeTransparency = 0.6
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

-- B5: all transient level messages share the event feed; Shush uses captions below.
local function say(text, _color, _seconds)
    RoundHud.Feed({Kind = "LEVEL", Detail = tostring(text or "")})
end

local title = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0.9, 0, 0, 60),
	TextSize = 48, Font = Enum.Font.Arcade, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = MAGENTA,
	TextTransparency = 1, TextStrokeTransparency = 1, Text = "" })
local subtitle = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.new(0.9, 0, 0, 24),
	TextSize = 20, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = CYAN,
	TextTransparency = 1, TextStrokeTransparency = 1, Text = "" })
subtitle.Position = UDim2.new(0.5, 0, 0.45, 44)
local function showTitle(text, sub, seconds)
	title.Text, subtitle.Text = text, sub or ""
	for _, l in ipairs({ title, subtitle }) do
		l.TextTransparency, l.TextStrokeTransparency = 1, 1
		TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	end
	task.delay(seconds or 3, function()
		for _, l in ipairs({ title, subtitle }) do
			TweenService:Create(l, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(255, 245, 255)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 20
flash.Parent = gui

-- ---------------------------------------------------------------- objective panel

local function nameOf(userId)
	local p = type(userId) == "number" and userId ~= 0 and Players:GetPlayerByUserId(userId)
	return p and p.DisplayName or nil
end

-- TORCH_GLINT_20261008 (owner: the reels must be easier to find): a loose reel caught in this player's flashlight
-- beam flashes (sparkles + a short warm light, a gentler swell with ReduceFlashing). Client-local: only the torch holder
-- sees it, and the instances never replicate.
local glintReels
do
	local nextGlint = setmetatable({}, { __mode = "k" })   -- reel model -> os.clock() it may glint again
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local CONE, RANGE, WARM = math.cos(math.rad(16)), 55, Color3.fromRGB(255, 230, 175)
	local function burst(part, distance)
		local emitter = part:FindFirstChild("L4TorchGlint")
		if not emitter then
			emitter = Instance.new("ParticleEmitter")
			emitter.Name = "L4TorchGlint"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(WARM)
			emitter.LightEmission, emitter.LightInfluence, emitter.Brightness = 1, 0, 3
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			emitter.Lifetime = NumberRange.new(0.45, 0.8)
			emitter.Speed = NumberRange.new(1, 3)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Rate = 0
			emitter.Parent = part
		end
		-- the sparkles grow with distance, so a reel 45 studs down a corridor still reads as a flash
		local grow = math.clamp(distance / 15, 1, 3)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2 * grow), NumberSequenceKeypoint.new(0.3, 1.3 * grow),
			NumberSequenceKeypoint.new(1, 0) })
		emitter:Emit(8)
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Shadows = WARM, 8, false
		local gentle = reduceFlashing()
		light.Brightness = gentle and 0 or 2.5
		light.Parent = part
		if gentle then
			TweenService:Create(light, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Brightness = 1.4 }):Play()
			task.delay(0.35, function()
				if light.Parent then TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Brightness = 0 }):Play() end
			end)
		else
			TweenService:Create(light, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
		end
		task.delay(1.1, function() light:Destroy() end)
	end
	function glintReels()
		local character = player.Character
		local flag = character and character:FindFirstChild("FlashlightOn")
		local model = cinema()
		local runtime = model and model:FindFirstChild("Level 4 Round Runtime")
		if not (flag and flag.Value and runtime) then return end
		local camera = workspace.CurrentCamera
		local origin, look = camera.CFrame.Position, camera.CFrame.LookVector
		-- walls (Collision) and the door leaves (Doors: a closed door hides the reel behind it) block the beam
		params.FilterDescendantsInstances = { model:FindFirstChild("Collision") or model, model:FindFirstChild("Doors") }
		local now = os.clock()
		for _, reel in ipairs(runtime:GetChildren()) do
			if reel:IsA("Model") and reel.Name:match("^L4FilmReel") and (nextGlint[reel] or 0) <= now then
				local part = reel.PrimaryPart or reel:FindFirstChildWhichIsA("BasePart", true)
				local to = part and part.Position - origin
				local distance = to and to.Magnitude or 0
				if part and distance > 1 and distance < RANGE and to.Unit:Dot(look) >= CONE then
					local hit = workspace:Raycast(origin, to, params)
					if not hit or (hit.Position - origin).Magnitude >= distance - 1.5 then
						nextGlint[reel] = now + 1.1
						burst(part, distance)
					end
				end
			end
		end
	end
end

local reopenNote -- filled beside the note's existing close/open interaction
local function objectiveSubject()
    if player:GetAttribute("Spectating") == true then
        local id = player:GetAttribute("SpectateTargetUserId")
        local watched = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
        if not watched or watched:GetAttribute("InRound") ~= true or watched:GetAttribute("Escaped") == true then return nil end
        local hum = watched.Character and watched.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health > 0 and watched or nil
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    return involved() and hum and hum.Health > 0 and player or nil
end
-- B4_LEVEL4_STATE_BEGIN
local function reelRooms(text)
    -- REEL_ROOMS_20261008: retain stable first occurrence and duplicate counts.
    local order, count = {}, {}
    for room in string.gmatch(text or "", "[^|]+") do
        if not count[room] then order[#order + 1] = room end
        count[room] = (count[room] or 0) + 1
    end
    for i, room in ipairs(order) do
        if count[room] > 1 then order[i] = room .. " x" .. count[room] end
    end
    return #order > 0 and ("Reels: " .. table.concat(order, ", ")) or nil
end
local function breakerStatus(holder, fuse)
    if holder then return {Text = "Main breaker: held by " .. holder, Kind = "positive"} end
    if fuse > 0 then return {Text = ("Main breaker: fuse %d s"):format(math.ceil(fuse)), Kind = "warning"} end
    return {Text = "Main breaker: off, in the service room", Kind = "danger"}
end
-- B4_LEVEL4_STATE_END
local function refreshPanel()
    local subject = objectiveSubject()
    if not roundLive() or not subject then return end
    local phase = st("Level4_Phase")
    local state = {Level = 4, Lines = {}, Done = false}
    if phase == "Dark" then
        state.Title, state.Tag = "RESTORE THE POWER", "BREAKERS"
        state.Count, state.Goal = st("Level4_SequenceProgress") or 0, st("Level4_SequenceGoal") or 4
        local order = subject:GetAttribute("Level4_NoteOrder")
        state.Lines = {type(order) == "string" and ("Order: " .. order) or "Find the note with the breaker order.",
            "Service room: POWER A and POWER B."}
        if type(order) == "string" and subject == player then state.OnOrderActivate = reopenNote end
        state.Done = state.Count >= state.Goal
    elseif phase == "Reels" then
        state.Title, state.Tag = "LOAD THE PROJECTORS", "PROJECTORS LOADED"
        state.Count, state.Goal = st("Level4_ReelsLoaded") or 0, st("Level4_ReelGoal") or 3
        local carried = math.max(0, tonumber(subject:GetAttribute("Level4_ReelsCarried")) or 0)
        state.Lines = {("You carry %d reel%s."):format(carried, carried == 1 and "" or "s")}
        local rooms = reelRooms(st("Level4_ReelRooms"))
        if rooms then state.Lines[2] = rooms end
        state.Status = breakerStatus(nameOf(st("Level4_BreakerHolder")),
            (st("Level4_FuseUntil") or 0) - workspace:GetServerTimeNow())
        state.Done = state.Count >= state.Goal
    elseif phase == "Finale" then
        state.Title, state.Lines, state.Done = "GET OUT", {"The screen in Cinema 2 is the exit."}, true
        local target = st("Level4_ExitPosition")
        state.Compass = {State = typeof(target) == "Vector3" and "locked" or "locating", Target = target}
    else return end
    RoundHud.SetObjective(state)
end

-- ---------------------------------------------------------------- zone rendering

local zoneLights, zoneNeon = {}, {}     -- zone id -> { Light } / { BasePart }
local roundToken = 0                    -- bumped on every local start/stop; stale stutters stand down
local tracked = {}
local stutterUntil = {}                 -- zone id -> time a local stutter owns it

local function track(d)
	if tracked[d] then return end
	if d:IsA("Light") then
		local holder = d.Parent
		local id = holder and holder:GetAttribute("L4Zone")
		if id and d:GetAttribute("L4Brightness") then
			tracked[d] = id
			zoneLights[id] = zoneLights[id] or {}
			table.insert(zoneLights[id], d)
		end
	elseif d:IsA("BasePart") then
		local id = d:GetAttribute("L4Zone")
		if id and typeof(d:GetAttribute("L4OnColor")) == "Color3" then
			tracked[d] = id
			zoneNeon[id] = zoneNeon[id] or {}
			table.insert(zoneNeon[id], d)
		end
	end
end

local modelConnections = {}
local function watchModel()
	for _, c in ipairs(modelConnections) do c:Disconnect() end
	table.clear(modelConnections)
	table.clear(zoneLights); table.clear(zoneNeon); table.clear(tracked)
	local model = cinema()
	if not model then return end
	for _, d in ipairs(model:GetDescendants()) do track(d) end
	table.insert(modelConnections, model.DescendantAdded:Connect(track))
	table.insert(modelConnections, model.DescendantRemoving:Connect(function(d)
		local id = tracked[d]
		if not id then return end
		tracked[d] = nil
		for _, list in ipairs({ zoneLights[id] or {}, zoneNeon[id] or {} }) do
			local i = table.find(list, d)
			if i then table.remove(list, i) end
		end
	end))
end

local function zoneOn(id)
	local bits = st("Level4_ZoneStates")
	if type(bits) ~= "string" then return true end
	return bits:sub(id, id) ~= "0"
end

local function setNeon(part, on, dim)
	local lit = part:GetAttribute("L4OnColor")
	if typeof(lit) ~= "Color3" then return end
	local material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	local color = on and lit or lit:Lerp(Color3.new(0, 0, 0), dim or 0.82)
	if part.Material ~= material then part.Material = material end
	if part.Color ~= color then part.Color = color end
end

local function setZoneLocal(id, on, fraction)
	for _, l in ipairs(zoneLights[id] or {}) do
		local b = l:GetAttribute("L4Brightness") or l.Brightness
		l.Brightness = on and b * (fraction or 1) or 0
	end
	for _, p in ipairs(zoneNeon[id] or {}) do setNeon(p, on) end
end

local function settleZone(id)
	local on = zoneOn(id)
	for _, l in ipairs(zoneLights[id] or {}) do
		local b = l:GetAttribute("L4Brightness")
		if b and l.Brightness ~= b then l.Brightness = b end
	end
	for _, p in ipairs(zoneNeon[id] or {}) do setNeon(p, on) end
end

-- the server switches at `at`; until then the zone stutters here, then lands on its final state
local function stutter(id, on, at)
	local now = workspace:GetServerTimeNow()
	local lead = math.max(0.05, at - now)
	stutterUntil[id] = at + 0.1
	local token = roundToken
	task.spawn(function()
		if reduceFlashing() then
			local steps = 6
			for i = 1, steps do
				local f = on and (i / steps) or (1 - i / steps)
				for _, l in ipairs(zoneLights[id] or {}) do
					l.Brightness = (l:GetAttribute("L4Brightness") or 0) * f
				end
				task.wait(lead / steps)
				if token ~= roundToken then return end
			end
		else
			local rng = Random.new()
			local t0 = os.clock()
			local state = not on
			while os.clock() - t0 < lead - 0.03 do
				state = not state
				setZoneLocal(id, state, state and rng:NextNumber(0.4, 1) or nil)
				task.wait(rng:NextNumber(0.03, 0.12))
				if token ~= roundToken then return end
			end
		end
		task.wait(math.max(0, at - workspace:GetServerTimeNow()))
		if token ~= roundToken then return end
		setZoneLocal(id, on)
		task.wait(0.15)
		if token ~= roundToken then return end
		stutterUntil[id] = nil
		settleZone(id)
	end)
end

local function repairZones()
	if not roundLive() then return end
	local now = workspace:GetServerTimeNow()
	for id in pairs(zoneNeon) do
		if not stutterUntil[id] or stutterUntil[id] < now then settleZone(id) end
	end
	for id in pairs(zoneLights) do
		if not zoneNeon[id] and (not stutterUntil[id] or stutterUntil[id] < now) then settleZone(id) end
	end
end

-- ---------------------------------------------------------------- the woooow

local function rumble(seconds, strength)
	if reduceShake() then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds and humanoid.Parent do
			local k = strength * (1 - (os.clock() - t0) / seconds)
			humanoid.CameraOffset = Vector3.new(math.noise(os.clock() * 13, 1) * k, math.noise(os.clock() * 11, 2) * k, 0)
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

local function powerUp(payload)
	local at = payload.At or workspace:GetServerTimeNow()
	task.delay(math.max(0, at - workspace:GetServerTimeNow()), function()
		if not roundLive() then return end
		playSound(AUDIO.Surge, nil, 1)
		rumble((payload.Wave or 4.5) + 0.6, 0.18)
		if not reduceFlashing() then
			flash.BackgroundTransparency = 0.55
			TweenService:Create(flash, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		end
		task.wait((payload.Wave or 4.5) * 0.6)
		showTitle("THE POWER IS BACK", "Three film reels. Three projectors. One last show.", 4.5)
	end)
end

-- ---------------------------------------------------------------- screens: film, exit

local screenGuis = {}
local function screenGui(part, name)
	local list = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui")
		g.Name = name
		g.Face = face
		g.LightInfluence = 0
		g.Brightness = 2.5
		g.CanvasSize = Vector2.new(800, 340)
		g.Parent = part
		table.insert(list, g)
		table.insert(screenGuis, g)
	end
	return list
end

local filmRunning = {}
local function startFilm(part)
	if filmRunning[part] then return end
	local frames = {}
	for _, g in ipairs(screenGui(part, "L4Film")) do
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(200, 205, 220)
		f.Parent = g
		local scratch = Instance.new("Frame")
		scratch.Size = UDim2.new(0, 3, 1, 0)
		scratch.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		scratch.BorderSizePixel = 0
		scratch.Parent = f
		table.insert(frames, { f, scratch })
	end
	filmRunning[part] = true
	task.spawn(function()
		local rng = Random.new()
		while filmRunning[part] and part.Parent do
			local v = reduceFlashing() and 0.85 or rng:NextNumber(0.6, 1)
			for _, pair in ipairs(frames) do
				pair[1].BackgroundColor3 = Color3.fromRGB(200, 205, 220):Lerp(Color3.fromRGB(70, 75, 95), 1 - v)
				pair[2].Position = UDim2.fromScale(rng:NextNumber(), 0)
				pair[2].Visible = not reduceFlashing() and rng:NextNumber() < 0.5
			end
			task.wait(reduceFlashing() and 0.6 or 0.07)
		end
	end)
end

-- owner 2026-10-04: the white exit screen bloomed so hard the word could not be read -> a dark panel with cream
-- letters (the TICKETS sign's look), a dimmer surface and a pulse that never fades the word out
local function exitScreen(part)
	for _, g in ipairs(screenGui(part, "L4Exit")) do
		g.Brightness = 1.2
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(10, 8, 24)
		f.Parent = g
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.Arcade
		t.Text = "EXIT"
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(235, 228, 205)
		t.Parent = f
		task.spawn(function()
			while f.Parent do
				local low = reduceFlashing() and 0 or 0.3
				TweenService:Create(t, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { TextTransparency = low }):Play()
				task.wait(0.9)
				TweenService:Create(t, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
				task.wait(0.9)
			end
		end)
	end
end

-- ---------------------------------------------------------------- note and keypad (B7 imported screens)
-- MOBILE_QA_20261008: the cards stay left of the touch control cluster and publish Level4CardOpen.
-- Their mounted artwork retains fixed template geometry; a device change remounts at the measured scale.
local keypad, noteCard, display, keypadStatus, closeButton
local keypadOrigin, noteOrigin = nil, nil
local entered, noteCopy = "", ""
local keypadKeys, previousSelection = {}, nil
local cursorForced = false
local function syncCursor()
    if not UserInputService.MouseEnabled then return end
    if (noteCard and noteCard.Visible) or (keypad and keypad.Visible) then
        UserInputService.MouseIconEnabled = true
        cursorForced = true
    elseif cursorForced then
        cursorForced = false
        UserInputService.MouseIconEnabled = player:GetAttribute("InRound") ~= true
    end
end
local function restoreSelection()
    local selected = GuiService.SelectedObject
    if selected and keypad and selected:IsDescendantOf(keypad) then GuiService.SelectedObject = previousSelection end
    previousSelection = nil
end
local function renderEntry()
    if display then display.Text = entered .. string.rep("-", 4 - #entered) end
    if keypadStatus then keypadStatus.Visible = false end
end
local function closeKeypad()
    restoreSelection()
    if keypad then keypad.Visible = false end
    entered, keypadOrigin = "", nil
    renderEntry()
    syncCursor()
end
local function closeNote()
    if noteCard then noteCard.Visible = false end
    noteOrigin = nil
    syncCursor()
end
local function publishCard()
    local open = gui.Enabled and ((keypad and keypad.Visible) or (noteCard and noteCard.Visible)) and UIDevice.IsTouch()
    if (player:GetAttribute("Level4CardOpen") == true) ~= (open == true) then
        player:SetAttribute("Level4CardOpen", open and true or nil)
    end
end
local function submit()
    local remotes = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
    local remote = remotes and remotes:FindFirstChild("KeypadSubmit")
    if remote and #entered == 4 then remote:FireServer(entered) end
end
-- B7_KEYPAD_LOGIC_BEGIN
local function focusNeighbours(index)
    local col, row = (index - 1) % 3, math.floor((index - 1) / 3)
    return row * 3 + (col + 2) % 3 + 1, row * 3 + (col + 1) % 3 + 1,
        ((row + 3) % 4) * 3 + col + 1, ((row + 1) % 4) * 3 + col + 1
end
local function press(key)
    if key == "C" then entered = ""
    elseif key == "OK" then submit(); return
    elseif #entered < 4 then entered ..= key end
    renderEntry()
    playSound(AUDIO.Keypad, nil, 0.5)
end
local function noteLines(text, order)
    local lines = {}
    for line in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
        if #lines >= 4 then break end
        lines[#lines + 1] = line
    end
    if #lines < 2 or lines[2] == "" then lines = {"POWER", tostring(order or ""), "", "in this order"} end
    lines[2] = string.gsub(lines[2], "%s*>%s*", " \u{203A} ")
    lines[4] = "in this order"
    return lines
end
-- B7_KEYPAD_LOGIC_END
local function renderNote()
    if not noteCard then return end
    local lines = noteLines(noteCopy, player:GetAttribute("Level4_NoteOrder"))
    for index = 1, 4 do
        local line = Binder.at(noteCard, "Body/Items/BodyLine" .. index)
        if line then
            line.Font = Enum.Font.PatrickHand
            line.TextScaled = false
            line.Text = lines[index] or ""
        end
    end
end
local function openKeypad()
    if not keypad then return end
    closeNote()
    previousSelection = GuiService.SelectedObject
    keypad.Visible = true
    entered = ""
    renderEntry()
    if not UIDevice.IsTouch() and (UIDevice.IsGamepadOnly() or UIDevice.LastInput() == "Gamepad") then GuiService.SelectedObject = keypadKeys[1] end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    keypadOrigin = root and root.Position
    syncCursor()
end
local function openNote(text, pickedUp)
    if not noteCard then return end
    closeKeypad()
    if type(text) == "string" then noteCopy = text end
    renderNote()
    noteCard.Visible = true
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    noteOrigin = pickedUp and root and root.Position or nil
    syncCursor()
end
reopenNote = function()
    if objectiveSubject() ~= player or type(player:GetAttribute("Level4_NoteOrder")) ~= "string"
        or UIDevice.ScreenOwningModalOpen() or player:GetAttribute("ZyntraDispatchClientActive") == true then return end
    -- A reread has no world-note distance leash; the original pickup retains it.
    openNote(nil, false)
end
local function gamepadInput()
    return not UIDevice.IsTouch() and (UIDevice.IsGamepadOnly() or UIDevice.LastInput() == "Gamepad")
end
local keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"}
local function focusRing(button)
    local ring = Instance.new("Frame")
    ring.Name = "FocusRing"
    ring.BackgroundTransparency = 1
    ring.Size = UDim2.fromScale(1, 1)
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness = Binder.Palette.RailTeal, 2
    stroke.Parent = ring
    button.SelectionImageObject = ring
    button.Destroying:Once(function() ring:Destroy() end)
end
local function cardPlacement(root, width, height, down)
    if not root then return end
    local layout = UIDevice.Layout()
    local safe = layout.Safe
    root.AnchorPoint = Vector2.new(.5, .5)
    if layout.IsTouch then
        local half = width * .5
        local x = math.max(safe.Left + half + 8,
            math.min((safe.Left + safe.Right) * .5, layout.Zones.Controls.Left - 8 - half))
        local y = math.clamp(safe.Top + safe.Height * down, safe.Top + height * .5 + 8, safe.Bottom - height * .5 - 8)
        root.Position = UIDevice.LocalPosition(gui, x, y)
    else root.Position = UIDevice.LocalPosition(gui, (safe.Left + safe.Right) * .5, safe.Top + safe.Height * down) end
end
local function placeForDevice()
    local layout = UIDevice.Layout()
    local touch = layout.IsTouch
    local keypadOpen, noteOpen = keypad and keypad.Visible, noteCard and noteCard.Visible
    local selected = GuiService.SelectedObject
    local selectionIndex
    for i, key in ipairs(keypadKeys) do if selected == key then selectionIndex = i end end
    if keypad then keypad:Destroy() end
    if noteCard then noteCard:Destroy() end
    local keypadScale = math.min(touch and 300/330 or 1, (layout.Safe.Height - 16)/330, (layout.Safe.Width - 16)/240)
    local noteScale = math.min(touch and 340/380 or 1, (layout.Safe.Height - 16)/270, (layout.Safe.Width - 16)/380)
    keypad = RoundHud.Mount("HUD_Screens", "Keypad", gui, {Name = "Keypad", Scale = keypadScale, Touch = touch})
    noteCard = RoundHud.Mount("HUD_Screens", "Level4Note", gui, {Name = "NoteCard", Scale = noteScale, Touch = touch})
    -- Missing imported components disable only these optional interactions; world rendering still starts.
    if keypad then
        keypad.Visible = keypadOpen == true
        display, keypadStatus = Binder.at(keypad, "DisplayBox/Display"), Binder.at(keypad, "Status")
        closeButton = Binder.at(keypad, "Close")
        if closeButton then
            closeButton.Modal = true
            closeButton.Activated:Connect(closeKeypad)
            if touch then
                local hit = Instance.new("TextButton")
                hit.Name = "CloseHit"
                hit.AnchorPoint, hit.Position = closeButton.AnchorPoint, closeButton.Position
                hit.Size = UDim2.fromOffset(44, 44)
                hit.BackgroundTransparency, hit.Text, hit.AutoButtonColor = 1, "", false
                hit.ZIndex, hit.Modal = closeButton.ZIndex + 1, true
                hit.Parent = keypad
                hit.Activated:Connect(closeKeypad)
            end
        end
        table.clear(keypadKeys)
        for i, key in ipairs(keys) do
            local button = Binder.at(keypad, "Key" .. key)
            if button then
                keypadKeys[i] = button
                button.Selectable = true
                focusRing(button)
                button.Activated:Connect(function() press(key) end)
            end
        end
        for i, button in ipairs(keypadKeys) do
            local left, right, up, down = focusNeighbours(i)
            button.NextSelectionLeft, button.NextSelectionRight = keypadKeys[left], keypadKeys[right]
            button.NextSelectionUp, button.NextSelectionDown = keypadKeys[up], keypadKeys[down]
        end
        local pressHint, closeHint = Binder.at(keypad, "PressHint"), Binder.at(keypad, "CloseHint")
        if pressHint then pressHint.Visible = gamepadInput(); RoundHud.Keycap(Binder.at(pressHint, "KeyChip"), nil, Enum.KeyCode.ButtonA) end
        if closeHint then closeHint.Visible = not touch; RoundHud.Keycap(Binder.at(closeHint, "KeyChip"), Enum.KeyCode.Escape, Enum.KeyCode.ButtonB) end
        renderEntry()
        cardPlacement(keypad, 240*keypadScale, 330*keypadScale, .5)
        keypad:GetPropertyChangedSignal("Visible"):Connect(publishCard)
        if keypadOpen and gamepadInput() then GuiService.SelectedObject = keypadKeys[selectionIndex or 1] end
    else
        table.clear(keypadKeys)
        display, keypadStatus, closeButton = nil, nil, nil
    end
    if noteCard then
        noteCard.Visible = noteOpen == true
        noteCard.Modal, noteCard.AutoButtonColor, noteCard.Selectable = true, false, false
        noteCard.Activated:Connect(closeNote)
        local hint, tap = Binder.at(noteCard, "CloseHint"), Binder.at(noteCard, "TapToClose")
        if hint then hint.Visible = not touch; RoundHud.Keycap(Binder.at(hint, "KeyChip"), Enum.KeyCode.E, Enum.KeyCode.ButtonB) end
        if tap then tap.Visible = touch end
        renderNote()
        cardPlacement(noteCard, 380*noteScale, 270*noteScale, .48)
        noteCard:GetPropertyChangedSignal("Visible"):Connect(publishCard)
    end
    publishCard()
    syncCursor()
end
placeForDevice()
UIDevice.Changed:Connect(placeForDevice)
gui:GetPropertyChangedSignal("Enabled"):Connect(publishCard)
player:SetAttribute("Level4CardOpen", nil)
local function typingInChat()
    if UserInputService:GetFocusedTextBox() then return true end
    local bar = game:GetService("TextChatService"):FindFirstChildOfClass("ChatInputBarConfiguration")
    return bar ~= nil and bar.IsFocused
end
UserInputService.InputBegan:Connect(function(input)
    if not keypad or not keypad.Visible or typingInChat() then return end
    local code = input.KeyCode
    local digit = code.Value >= Enum.KeyCode.Zero.Value and code.Value <= Enum.KeyCode.Nine.Value and tostring(code.Value - Enum.KeyCode.Zero.Value)
        or (code.Value >= Enum.KeyCode.KeypadZero.Value and code.Value <= Enum.KeyCode.KeypadNine.Value and tostring(code.Value - Enum.KeyCode.KeypadZero.Value))
    if digit then press(digit)
    elseif code == Enum.KeyCode.Return or code == Enum.KeyCode.KeypadEnter then press("OK")
    elseif code == Enum.KeyCode.Backspace then press("C")
    elseif code == Enum.KeyCode.Escape then closeKeypad() end
end)
ContextActionService:BindActionAtPriority("Level4CloseCard", function(_, state, input)
    if state ~= Enum.UserInputState.Begin or typingInChat() or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
    if noteCard and noteCard.Visible then closeNote(); return Enum.ContextActionResult.Sink end
    if keypad and keypad.Visible and input.KeyCode == Enum.KeyCode.ButtonB then closeKeypad(); return Enum.ContextActionResult.Sink end
    return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.E, Enum.KeyCode.ButtonB)
ContextActionService:BindActionAtPriority("Level4ReopenNote", function(_, state)
    if state ~= Enum.UserInputState.Begin or typingInChat() or GuiService.MenuIsOpen
        or objectiveSubject() ~= player or type(player:GetAttribute("Level4_NoteOrder")) ~= "string"
        or UIDevice.ScreenOwningModalOpen() or player:GetAttribute("ZyntraDispatchClientActive") == true then return Enum.ContextActionResult.Pass end
    reopenNote()
    return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.N, Enum.KeyCode.DPadUp)

-- ---------------------------------------------------------------- the Usher (local rig)

local Anim = nil
local usher = { Model = nil, Root = nil, Motors = {}, RootHeight = 3.8, Buffer = {}, Hidden = true, State = 0,
	Visible = 0, Phase = 0, LastPos = nil, Speed = 0, Beam = nil }

local function placeholderRig()
	local m = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = m
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.6, 5.6, 1)
	body.Color = Color3.fromRGB(14, 10, 16)
	body.Material = Enum.Material.Fabric
	body.CFrame = root.CFrame * CFrame.new(0, 0.9, 0)
	body.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.3, 1.3, 1.3)
	head.Color = Color3.fromRGB(205, 200, 190)
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = root.CFrame * CFrame.new(0, 4.3, 0)
	head.Parent = m
	for _, part in ipairs({ body, head }) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, part
		w.Parent = part
	end
	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Size = Vector3.new(0.3, 0.3, 0.3)
	lens.Color = Color3.fromRGB(255, 30, 30)
	lens.Material = Enum.Material.Neon
	lens.CFrame = root.CFrame * CFrame.new(1, 0.6, -0.6)
	lens.Parent = m
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = root, lens
	w.Parent = lens
	local beam = Instance.new("SpotLight")
	beam.Name = "TicketBeam"
	beam.Color = Color3.fromRGB(255, 30, 30)
	beam.Range = 26
	beam.Angle = 40
	beam.Brightness = 3
	beam.Face = Enum.NormalId.Front
	beam.Parent = lens
	m.PrimaryPart = root
	return m
end

local function buildUsher()
	if usher.Model then usher.Model:Destroy() end
	local template = ReplicatedStorage:FindFirstChild(USHER_VISUAL)
	local model = template and template:Clone() or placeholderRig()
	model.Name = "Level4UsherLocal"
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	model.PrimaryPart = root
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Anchored = d == root
			d.Massless = true
			d.CastShadow = d ~= root
		end
	end
	local cf, size = model:GetBoundingBox()
	usher.RootHeight = root.Position.Y - (cf.Position.Y - size.Y / 2)
	usher.Motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then usher.Motors[d.Name] = d end
	end
	usher.Beam = model:FindFirstChild("TicketBeam", true)
	usher.Model, usher.Root = model, root
	usher.Visible = 0
	model.Parent = workspace
	local ok, module = pcall(function()
		local m = ReplicatedStorage:FindFirstChild("Level 4 Usher Animations")
		return m and require(m)
	end)
	Anim = ok and module or nil
end

local function destroyUsher()
	if usher.Model then usher.Model:Destroy() end
	usher.Model, usher.Root = nil, nil
	table.clear(usher.Buffer)
end

local function setUsherAlpha(alpha)
	if not usher.Model then return end
	for _, d in ipairs(usher.Model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= usher.Root then d.LocalTransparencyModifier = 1 - alpha end
	end
	if usher.Beam then usher.Beam.Enabled = alpha > 0.5 end
end

local function quat(q)
	return CFrame.new(0, 0, 0, q[1], q[2], q[3], q[4])
end

-- pose: walk/run clip by speed, then procedural overlays per server state
local STATE_SHUSH, STATE_CAPTURE, STATE_STUNNED = 4, 5, 6
local function animate(dt)
	local speed = usher.Speed
	local clip = Anim and Anim.Clips and (speed > 12 and Anim.Clips.Run or Anim.Clips.Walk)
	local moving = speed > 0.8
	local transforms = {}
	if clip and moving then
		local ref = speed > 12 and 17 or 9
		usher.Phase = (usher.Phase + dt * (speed / ref) * (Anim.Fps or 30)) % #clip.Frames
		local frame = clip.Frames[math.floor(usher.Phase) + 1]
		for j, name in ipairs(Anim.Joints) do
			local q = frame[j]
			if q then transforms[name] = quat(q) end
		end
		local hips = clip.HipsOffset and clip.HipsOffset[math.floor(usher.Phase) + 1]
		if hips and transforms.Hips then transforms.Hips = CFrame.new(hips[1], hips[2], hips[3]) * transforms.Hips end
	end
	local t = os.clock()
	local state = usher.State
	local spine, neck = CFrame.identity, CFrame.identity
	if state == STATE_SHUSH then
		spine = CFrame.Angles(math.rad(-22), 0, 0)
		neck = CFrame.Angles(math.rad(-18), 0, math.rad(12 * math.sin(t * 2)))
	elseif state == STATE_CAPTURE then
		spine = CFrame.Angles(math.rad(-38), 0, 0)
		neck = CFrame.Angles(math.rad(-25), 0, 0)
	elseif state == STATE_STUNNED then
		spine = CFrame.Angles(math.rad(14), math.rad(8 * math.sin(t * 25)), 0)
		neck = CFrame.Angles(math.rad(20), math.rad(25), 0)
	elseif not moving then
		neck = CFrame.Angles(0, math.rad(25 * math.sin(t * 0.7)), math.rad(6 * math.sin(t * 0.4)))
	end
	for name, motor in pairs(usher.Motors) do
		local base = transforms[name] or CFrame.identity
		if name == "Spine" or name == "Spine01" then base = base * spine end
		if name == "neck" or name == "Neck" then base = base * neck end
		motor.Transform = base
	end
	if usher.Beam then
		-- stunned: it sputters (a slow dim with ReduceFlashing, never a strobe)
		usher.Beam.Brightness = state ~= STATE_STUNNED and 3
			or (reduceFlashing() and 1.2 + 0.6 * math.sin(t * 3) or (math.random() < 0.5 and 0 or 3))
	end
end

local function sampleAt(renderTime)
	local buffer = usher.Buffer
	if #buffer == 0 then return nil end
	if renderTime <= buffer[1].T then return buffer[1].CF, buffer[1] end
	for i = 1, #buffer - 1 do
		local a, b = buffer[i], buffer[i + 1]
		if renderTime >= a.T and renderTime <= b.T then
			local alpha = (renderTime - a.T) / math.max(b.T - a.T, 1e-3)
			if a.H ~= b.H then return (alpha < 0.5 and a or b).CF, (alpha < 0.5 and a or b) end
			return a.CF:Lerp(b.CF, alpha), b
		end
	end
	local last = buffer[#buffer]
	return last.CF, last
end

local function stepUsher(dt)
	if not usher.Model then return end
	local cf, sample = sampleAt(workspace:GetServerTimeNow() - INTERP_DELAY)
	if not cf then setUsherAlpha(0); return end
	usher.State = sample.S
	local hidden = sample.H
	local target = hidden and 0 or 1
	usher.Visible += math.clamp(target - usher.Visible, -dt / 0.25, dt / 0.35)
	setUsherAlpha(usher.Visible)
	if usher.Visible <= 0 then usher.LastPos = nil; usher.Speed = 0; return end
	local pos = cf.Position
	if usher.LastPos and dt > 0 then
		local flat = Vector3.new(pos.X - usher.LastPos.X, 0, pos.Z - usher.LastPos.Z).Magnitude
		usher.Speed += (flat / dt - usher.Speed) * math.min(1, dt * 6)
	end
	usher.LastPos = pos
	usher.Root.CFrame = cf + Vector3.new(0, usher.RootHeight, 0)
	animate(dt)
end

-- ---------------------------------------------------------------- events

local function onClientEvent(payload)
	if type(payload) ~= "table" or not roundLive() then return end
	local kind = payload.Type
	if kind == "Zones" then
		for _, change in ipairs(payload.Changes or {}) do
			stutter(change[1], change[2], payload.At or workspace:GetServerTimeNow())
		end
		if st("Level4_PowerState") == "PoweringUp" then
			for _, change in ipairs(payload.Changes or {}) do
				local lights = zoneLights[change[1]]
				local holder = lights and lights[1] and lights[1].Parent
				if holder and holder:IsA("BasePart") then playAt(AUDIO.Thunk, holder.Position, 0.9) end
			end
		end
	elseif kind == "PowerUp" then
		powerUp(payload)
	elseif kind == "Wrong" then
		say("Wrong order. The breakers reset.", Color3.fromRGB(255, 120, 100))
		rumble(0.4, 0.12)
	elseif kind == "Hint" then
		say(tostring(payload.Text or ""), Color3.fromRGB(255, 230, 160), 4)
	elseif kind == "FuseBlown" then
		say("The fuse blew. The breaker dropped.", Color3.fromRGB(255, 160, 90))
	elseif kind == "BreakerReleased" then
		say("You let go of the breaker.", Color3.fromRGB(255, 200, 140))
	elseif kind == "ProjectorStart" then
		say(("Projector %d is running."):format(payload.Screen or 0), CYAN)
	elseif kind == "Shush" then
		if captionsOn() then
			local me = payload.Player == player.UserId
			local subject = objectiveSubject()
			local character = subject and subject.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local near = root and typeof(payload.Position) == "Vector3" and (payload.Position - root.Position).Magnitude < 60
			if me or near then RoundHud.Caption("USHER", "Shhh...") end
		end
	elseif kind == "Stun" then
		if payload.By == player.UserId then say("It recoils from your light.", Color3.fromRGB(255, 240, 200), 2.5) end
	elseif kind == "UsherCapture" then
		local victim = payload.Player ~= player.UserId and nameOf(payload.Player)
		if victim then say(victim .. " was shushed.", Color3.fromRGB(255, 110, 130)) end
	elseif kind == "Note" then
        openNote(tostring(payload.Text or ""), true)
    elseif kind == "Keypad" then
        openKeypad()
	elseif kind == "KeypadResult" then
		if payload.Ok then
			closeKeypad()
			say("Access granted. The prize case opens.", Color3.fromRGB(140, 255, 170))
		else
			if keypadStatus then keypadStatus.Text = "WRONG CODE"; keypadStatus.Visible = true end
			entered = ""
			task.delay(0.8, renderEntry)
		end
	elseif kind == "Finale" then
		showTitle("THE LAST SHOW", "Run. The screen in Cinema 2 is the way out.", 5)
		playSound(AUDIO.Credits, nil, 0.6)   -- the credits roll itself was removed (owner 2026-10-04); its music stays
		local model = cinema()
		if model then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:HasTag("L4ExitScreen") then exitScreen(d) end
			end
		end
	end
end

local function briefing()
	task.spawn(function()
		task.wait(1.2)
		local lines = {
			"The last show ended decades ago. The power is out.",
			"Find the note with the breaker order. Your flashlight is all you have.",
			"Something tall still works here. Keep quiet.",
		}
		for _, line in ipairs(lines) do
			if not involved() then return end
			say(line, Color3.fromRGB(225, 215, 245), 3.6)
			task.wait(3.9)
		end
	end)
end

-- ---------------------------------------------------------------- lifecycle

local roundConnections = {}
local active = false

local function startRound()
	if active then return end
	active = true
	roundToken += 1
	gui.Enabled = true
	watchModel()
	buildUsher()
	local remotes = ReplicatedStorage:WaitForChild(REMOTES_NAME, 10)
	if remotes then
		local event = remotes:WaitForChild("ClientEvent", 10)
		local motion = remotes:WaitForChild("UsherMotion", 10)
		if event then table.insert(roundConnections, event.OnClientEvent:Connect(onClientEvent)) end
		if motion then
			table.insert(roundConnections, motion.OnClientEvent:Connect(function(cf, stateCode, hidden, t)
				if typeof(cf) ~= "CFrame" or type(t) ~= "number" then return end
				local buffer = usher.Buffer
				table.insert(buffer, { CF = cf, S = stateCode, H = hidden == true, T = t })
				while #buffer > 24 do table.remove(buffer, 1) end
			end))
		end
	end
	-- screens whose projector is running (late join / re-entry included)
	local model = cinema()
	if model then
		local function check(d)
			if d:IsA("BasePart") and d:GetAttribute("L4FilmRunning") == true then startFilm(d) end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:HasTag("L4Screen") then
				check(d)
				table.insert(roundConnections, d:GetAttributeChangedSignal("L4FilmRunning"):Connect(function() check(d) end))
			end
		end
	end
	local accum, glintAccum = 0, 0
	table.insert(roundConnections, RunService.RenderStepped:Connect(function(dt)
		stepUsher(dt)
		glintAccum += dt
		if glintAccum >= 0.1 then
			glintAccum = 0
			glintReels()
		end
		accum += dt
		if accum >= 0.25 then
			accum = 0
			-- escapees spectate (world rendering stays on) but the objective HUD is not theirs any more
			gui.Enabled = involved() or objectiveSubject() ~= nil
			refreshPanel()
			if keypad and keypad.Visible and keypadOrigin then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - keypadOrigin).Magnitude > 10 then closeKeypad() end
			end
			if noteCard and noteCard.Visible and noteOrigin then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - noteOrigin).Magnitude > 12 then closeNote() end
			end
			syncCursor()   -- also hands the pointer back after the keypad closes itself
		end
	end))
	table.insert(roundConnections, task.spawn(function()
		while active do
			repairZones()
			task.wait(1)
		end
	end))
end

local function stopRound()
	if not active then return end
	active = false
	roundToken += 1
	gui.Enabled = false
	for _, c in ipairs(roundConnections) do
		if typeof(c) == "RBXScriptConnection" then c:Disconnect() elseif type(c) == "thread" then pcall(task.cancel, c) end
	end
	table.clear(roundConnections)
	for _, c in ipairs(modelConnections) do c:Disconnect() end
	table.clear(modelConnections)
	destroyUsher()
	closeKeypad()
	closeNote()
	table.clear(filmRunning)
	for _, g in ipairs(screenGuis) do g:Destroy() end
	table.clear(screenGuis)
	-- hand every light back to the replicated (restored) values
	for d in pairs(tracked) do
		if d:IsA("Light") then
			local b = d:GetAttribute("L4Brightness")
			if b then d.Brightness = b end
		end
	end
	table.clear(tracked); table.clear(zoneLights); table.clear(zoneNeon); table.clear(stutterUntil)
end

local function sync()
	if involved() or (roundLive() and player:GetAttribute("Spectating") == true) then startRound() else stopRound() end
end
workspace:GetAttributeChangedSignal("Level4RoundActive"):Connect(sync)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(sync)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(sync)
player:GetAttributeChangedSignal("InRound"):Connect(sync)
player:GetAttributeChangedSignal("Spectating"):Connect(sync)
player:GetAttributeChangedSignal("Escaped"):Connect(sync)
player:GetAttributeChangedSignal("SpectateTargetUserId"):Connect(function() sync(); refreshPanel() end)
player:GetAttributeChangedSignal("Level4_NoteOrder"):Connect(refreshPanel)
player:GetAttributeChangedSignal("Level4_ReelsCarried"):Connect(refreshPanel)
sync()

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local roundStatus = remotes:WaitForChild("RoundStatus")
roundStatus.OnClientEvent:Connect(function(ev)
	if ev == "level4access" then
		sync()
		briefing()
	end
end)
