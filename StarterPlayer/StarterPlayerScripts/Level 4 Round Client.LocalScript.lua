-- Level 4 Round Client: everything the cinema round "Den Sidste Forestilling" shows on one client.
-- The server decides (Level 4 Light Director / Objective Controller / Usher Controller); this only presents:
--   * objective panel, captions, the opening briefing, hidden / carrying chips
--   * zone light rendering: stutters announced by ClientEvent {Type="Zones"} (Brightness + neon, local only, landing
--     on exactly the server's final state; ReduceFlashing fades instead) and a 1 s repair pass for stale local writes
--   * the power-up "woooow": surge flash, a low rumble (none with ReduceCameraShake), the title card
--   * film flicker on running screens, the glowing exit screen and the credits roll in the finale
--   * the arcade keypad (KeypadSubmit) and the Usher: a local rig drawn from UsherMotion (interpolated 0.1 s behind
--     server time) and animated from ReplicatedStorage."Level 4 Usher Animations" with procedural overlays
-- Nothing here is authority; a client that drops this script still plays the same round.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
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
gui.DisplayOrder = 6
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

local panel = Instance.new("Frame")
panel.Name = "Objective"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -18, 0, 110)
panel.Size = UDim2.fromOffset(300, 96)
panel.BackgroundColor3 = Color3.fromRGB(10, 6, 18)
panel.BackgroundTransparency = 0.35
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = MAGENTA
stroke.Transparency = 0.4
stroke.Thickness = 1.5
local pad = Instance.new("UIPadding", panel)
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 8)
local titleLine = label(panel, { Size = UDim2.new(1, 0, 0, 14), Text = "THE LAST SHOW", TextSize = 12, TextColor3 = MAGENTA })
local mainLine = label(panel, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 22), TextSize = 18, Text = "" })
local subLine = label(panel, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 18), TextSize = 14,
	Font = Enum.Font.Gotham, TextColor3 = CYAN, Text = "" })
local extraLine = label(panel, { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 18), TextSize = 13,
	Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(200, 190, 220), Text = "" })

local caption = label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.66, 0),
	Size = UDim2.new(0.8, 0, 0, 30), TextSize = 22, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center,
	TextTransparency = 1, TextStrokeTransparency = 1, Text = "" })
local captionSerial = 0
local function say(text, color, seconds)
	captionSerial += 1
	local mine = captionSerial
	caption.Text = text
	caption.TextColor3 = color or WHITE
	caption.TextTransparency, caption.TextStrokeTransparency = 0, 0.5
	task.delay(seconds or 3.5, function()
		if captionSerial ~= mine then return end
		TweenService:Create(caption, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
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

local function chip(text, color, y)
	local c = label(gui, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, y), Size = UDim2.fromOffset(150, 26),
		TextSize = 15, Text = text, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
		BackgroundTransparency = 0.35, BackgroundColor3 = Color3.fromRGB(10, 6, 18) })
	Instance.new("UICorner", c).CornerRadius = UDim.new(0, 6)
	return c
end
local hiddenChip = chip("HIDDEN", Color3.fromRGB(150, 255, 170), -170)
local carryChip = chip("", Color3.fromRGB(255, 220, 140), -200)

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

local function refreshPanel()
	local phase = st("Level4_Phase")
	if phase == "Dark" then
		mainLine.Text = "RESTORE THE POWER"
		subLine.Text = ("Find the note.  Breakers %d/%d"):format(st("Level4_SequenceProgress") or 0, st("Level4_SequenceGoal") or 4)
		extraLine.Text = "Service room: POWER A and POWER B"
	elseif phase == "Reels" then
		local goal = st("Level4_ReelGoal") or 3
		mainLine.Text = "LOAD THE PROJECTORS"
		subLine.Text = ("Reels found %d/%d   loaded %d/%d"):format(st("Level4_ReelsCollected") or 0, goal, st("Level4_ReelsLoaded") or 0, goal)
		local holder = nameOf(st("Level4_BreakerHolder"))
		local fuse = (st("Level4_FuseUntil") or 0) - workspace:GetServerTimeNow()
		if holder then
			extraLine.Text = "Main breaker: held by " .. holder
		elseif fuse > 0 then
			extraLine.Text = ("Main breaker: fuse %ds"):format(math.ceil(fuse))
		else
			extraLine.Text = "Main breaker: OFF (service room)"
		end
	elseif phase == "Finale" then
		mainLine.Text = "GET OUT"
		subLine.Text = "The screen in Cinema 2 is the exit"
		local exit = st("Level4_ExitPosition")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		extraLine.Text = (typeof(exit) == "Vector3" and root) and ("%d studs"):format(math.floor((exit - root.Position).Magnitude)) or ""
	else
		mainLine.Text, subLine.Text, extraLine.Text = "", "", ""
	end
	hiddenChip.Visible = player:GetAttribute("Level4_Hidden") == true
	local carried = player:GetAttribute("Level4_ReelsCarried") or 0
	carryChip.Visible = carried > 0
	carryChip.Text = carried == 1 and "CARRYING 1 REEL" or ("CARRYING %d REELS"):format(carried)
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

-- ---------------------------------------------------------------- screens: film, exit, credits

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

local function exitScreen(part)
	for _, g in ipairs(screenGui(part, "L4Exit")) do
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.Parent = g
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), CYAN)
		grad.Rotation = 90
		grad.Parent = f
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.Arcade
		t.Text = "EXIT"
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(20, 10, 40)
		t.Parent = f
		task.spawn(function()
			while f.Parent do
				TweenService:Create(t, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { TextTransparency = 0.5 }):Play()
				task.wait(0.9)
				TweenService:Create(t, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
				task.wait(0.9)
			end
		end)
	end
end

local credits = Instance.new("Frame")
credits.Name = "Credits"
credits.AnchorPoint = Vector2.new(1, 1)
credits.Position = UDim2.new(1, -24, 1, -40)
credits.Size = UDim2.fromOffset(260, 300)
credits.BackgroundTransparency = 1
credits.ClipsDescendants = true
credits.Visible = false
credits.Parent = gui
local creditsText = label(credits, { Size = UDim2.new(1, 0, 0, 1400), TextSize = 16, Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	TextColor3 = Color3.fromRGB(230, 225, 245), TextTransparency = 0.15, Text = "" })

local function rollCredits(seconds)
	local cast = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InRound") == true then table.insert(cast, p.DisplayName) end
	end
	creditsText.Text = table.concat({
		"THE LAST SHOW", "", "", "THE USHER", "as himself", "", "THE AUDIENCE", table.concat(cast, "\n"), "",
		"PROJECTION", "three reels, one breaker", "", "FILMED ON LOCATION", "somewhere in the Backrooms", "", "",
		"No ushers were harmed.", "Some audience members were.", "", "", "Please exit through the screen.",
	}, "\n")
	credits.Visible = true
	creditsText.Position = UDim2.fromOffset(0, 300)
	TweenService:Create(creditsText, TweenInfo.new(seconds or 75, Enum.EasingStyle.Linear), { Position = UDim2.fromOffset(0, -900) }):Play()
	playSound(AUDIO.Credits, nil, 0.6)
end

-- ---------------------------------------------------------------- keypad

local keypad = Instance.new("Frame")
keypad.Name = "Keypad"
keypad.AnchorPoint = Vector2.new(0.5, 0.5)
keypad.Position = UDim2.fromScale(0.5, 0.5)
keypad.Size = UDim2.fromOffset(240, 330)
keypad.BackgroundColor3 = Color3.fromRGB(12, 8, 24)
keypad.Visible = false
keypad.ZIndex = 10
keypad.Parent = gui
Instance.new("UICorner", keypad).CornerRadius = UDim.new(0, 10)
local kStroke = Instance.new("UIStroke", keypad)
kStroke.Color = CYAN
local display = label(keypad, { Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -62, 0, 44), TextSize = 34,
	Font = Enum.Font.Arcade, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = CYAN, Text = "----", ZIndex = 11,
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(2, 4, 10) })
local entered = ""
local keypadOrigin = nil
local function renderEntry() display.Text = (entered .. string.rep("-", 4 - #entered)) end
local function closeKeypad() keypad.Visible = false; entered = ""; renderEntry(); keypadOrigin = nil end
local function submit()
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
	local remote = remotes and remotes:FindFirstChild("KeypadSubmit")
	if remote and #entered == 4 then remote:FireServer(entered) end
end
local function press(key)
	if key == "C" then entered = ""
	elseif key == "OK" then submit(); return
	elseif #entered < 4 then entered ..= key end
	renderEntry()
	playSound(AUDIO.Keypad, nil, 0.5)
end
local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK" }
for i, key in ipairs(keys) do
	local b = Instance.new("TextButton")
	b.Name = "Key" .. key
	local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
	b.Position = UDim2.fromOffset(16 + col * 72, 70 + row * 58)
	b.Size = UDim2.fromOffset(64, 50)
	b.BackgroundColor3 = Color3.fromRGB(30, 22, 52)
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBold
	b.TextSize = 22
	b.Text = key
	b.ZIndex = 11
	b.Parent = keypad
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.Activated:Connect(function() press(key) end)
end
local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 21)
closeButton.Size = UDim2.fromOffset(30, 30)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 18
closeButton.TextColor3 = WHITE
closeButton.BackgroundColor3 = Color3.fromRGB(60, 20, 40)
closeButton.ZIndex = 11
closeButton.Parent = keypad
closeButton.Activated:Connect(closeKeypad)
UserInputService.InputBegan:Connect(function(input, processed)
	if not keypad.Visible or processed then return end
	local code = input.KeyCode
	local digit = code.Value >= Enum.KeyCode.Zero.Value and code.Value <= Enum.KeyCode.Nine.Value and tostring(code.Value - Enum.KeyCode.Zero.Value)
		or (code.Value >= Enum.KeyCode.KeypadZero.Value and code.Value <= Enum.KeyCode.KeypadNine.Value and tostring(code.Value - Enum.KeyCode.KeypadZero.Value))
	if digit then press(digit)
	elseif code == Enum.KeyCode.Return or code == Enum.KeyCode.KeypadEnter then press("OK")
	elseif code == Enum.KeyCode.Backspace then press("C")
	elseif code == Enum.KeyCode.Escape then closeKeypad() end
end)

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
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local near = root and typeof(payload.Position) == "Vector3" and (payload.Position - root.Position).Magnitude < 60
			if me or near then say(me and "[ a whisper, right behind you: \"shhh...\" ]" or "[ \"shhh...\" ]", Color3.fromRGB(220, 200, 255), 2.5) end
		end
	elseif kind == "Stun" then
		if payload.By == player.UserId then say("It recoils from your light.", Color3.fromRGB(255, 240, 200), 2.5) end
	elseif kind == "UsherCapture" then
		local victim = payload.Player ~= player.UserId and nameOf(payload.Player)
		if victim then say(victim .. " was shushed.", Color3.fromRGB(255, 110, 130)) end
	elseif kind == "Keypad" then
		keypad.Visible = true
		entered = ""
		renderEntry()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		keypadOrigin = root and root.Position
	elseif kind == "KeypadResult" then
		if payload.Ok then
			closeKeypad()
			say("ACCESS GRANTED. The prize case opens.", Color3.fromRGB(140, 255, 170))
		else
			display.Text = "DENY"
			entered = ""
			task.delay(0.8, renderEntry)
		end
	elseif kind == "Finale" then
		showTitle("THE LAST SHOW", "Run. The screen in Cinema 2 is the way out.", 5)
		rollCredits(payload.Credits)
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
	local accum = 0
	table.insert(roundConnections, RunService.RenderStepped:Connect(function(dt)
		stepUsher(dt)
		accum += dt
		if accum >= 0.25 then
			accum = 0
			-- escapees spectate (world rendering stays on) but the objective HUD is not theirs any more
			gui.Enabled = player:GetAttribute("Escaped") ~= true
			refreshPanel()
			if keypad.Visible and keypadOrigin then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - keypadOrigin).Magnitude > 10 then closeKeypad() end
			end
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
	credits.Visible = false
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
sync()

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local roundStatus = remotes:WaitForChild("RoundStatus")
roundStatus.OnClientEvent:Connect(function(ev)
	if ev == "level4access" then
		sync()
		briefing()
	end
end)
