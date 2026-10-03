-- Level 6 Indoor Playground, client side: hide-and-seek HUD, the counting child's animation and voice,
-- the hall's lighting while you are inside, and the slide ride.
-- Server side: ServerScriptService."Level 6 Playground Game" (events on ReplicatedStorage.Level6Playground.Event).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local IN_PREVIEW = "Level6PlaygroundPreview"
local LIGHTING_OWNED = "Level6PlaygroundLightingOwned"   -- RoundUI stands down while this is true
local MODEL_NAME = "Level 6 Indoor Playground"
local event = ReplicatedStorage:WaitForChild("Level6Playground"):WaitForChild("Event")

-- ---------------------------------------------------------------------------------------
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "Level6PlaygroundHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(name, size, pos, textSize, color)
	local l = Instance.new("TextLabel")
	l.Name, l.Size, l.Position = name, size, pos
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.35
	l.Text = ""
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = textSize
	limit.Parent = l
	l.Parent = gui
	return l
end

local countLabel = label("Count", UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.5, 0.215), 60, Color3.fromRGB(255, 235, 120))
local statusLabel = label("Status", UDim2.fromScale(0.8, 0.05), UDim2.fromScale(0.5, 0.285), 32, Color3.fromRGB(255, 255, 255))
local hintLabel = label("Hint", UDim2.fromScale(0.8, 0.045), UDim2.fromScale(0.5, 0.9), 28, Color3.fromRGB(230, 230, 230))
local dunkLabel = label("Dunks", UDim2.fromScale(0.24, 0.05), UDim2.fromScale(0.86, 0.08), 32, Color3.fromRGB(120, 255, 150))

-- the objective card: one big instruction and one short line under it, like the other levels' objective panels
local card = Instance.new("Frame")
card.Name = "Objective"
card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 58), UDim2.fromScale(0.34, 0.1)
card.BackgroundColor3, card.BackgroundTransparency, card.BorderSizePixel = Color3.fromRGB(12, 12, 16), 0.25, 0
card.Visible = false
card.Parent = gui
do
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = card
	local stroke = Instance.new("UIStroke"); stroke.Thickness, stroke.Color = 2, Color3.fromRGB(255, 205, 40); stroke.Name = "Edge"; stroke.Parent = card
	local limit = Instance.new("UISizeConstraint"); limit.MinSize, limit.MaxSize = Vector2.new(280, 74), Vector2.new(560, 110); limit.Parent = card
end
local function cardLabel(name, y, h, size, color)
	local l = Instance.new("TextLabel")
	l.Name, l.BackgroundTransparency = name, 1
	l.Position, l.Size = UDim2.fromScale(0.04, y), UDim2.fromScale(0.92, h)
	l.Font, l.TextScaled, l.TextColor3, l.Text = Enum.Font.FredokaOne, true, color, ""
	local limit = Instance.new("UITextSizeConstraint"); limit.MaxTextSize = size; limit.Parent = l
	l.Parent = card
	return l
end
local cardTitle = cardLabel("Title", 0.08, 0.5, 40, Color3.fromRGB(255, 220, 60))
local cardLine = cardLabel("Line", 0.58, 0.34, 22, Color3.fromRGB(235, 235, 235))
local function objective(title, line, color)
	card.Visible = title ~= nil
	cardTitle.Text, cardLine.Text = title or "", line or ""
	cardTitle.TextColor3 = color or Color3.fromRGB(255, 220, 60)
	card.Edge.Color = color or Color3.fromRGB(255, 205, 40)
end

-- the marker you can see through walls: on the post while you still have to tag it, on the exit once it is open
local markerPart = Instance.new("Part")
markerPart.Name, markerPart.Anchored, markerPart.CanCollide, markerPart.CanQuery, markerPart.CanTouch = "Level6Marker", true, false, false, false
markerPart.Transparency, markerPart.Size = 1, Vector3.new(1, 1, 1)
local marker = Instance.new("BillboardGui")
marker.Name, marker.AlwaysOnTop, marker.LightInfluence, marker.MaxDistance = "Level6MarkerGui", true, 0, 2000
marker.Size, marker.Enabled, marker.Adornee = UDim2.fromOffset(90, 90), false, markerPart
marker.Parent = player:WaitForChild("PlayerGui")
local markerRing = Instance.new("Frame")
markerRing.AnchorPoint, markerRing.Position, markerRing.Size = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(0.62, 0.62)
markerRing.BackgroundColor3, markerRing.BackgroundTransparency = Color3.fromRGB(255, 215, 40), 0.15
markerRing.Parent = marker
do
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = markerRing
	local stroke = Instance.new("UIStroke"); stroke.Thickness, stroke.Color = 3, Color3.new(1, 1, 1); stroke.Parent = markerRing
end
local markerIcon = Instance.new("TextLabel")
markerIcon.BackgroundTransparency, markerIcon.Size = 1, UDim2.fromScale(1, 1)
markerIcon.Font, markerIcon.TextScaled, markerIcon.TextColor3, markerIcon.Text = Enum.Font.FredokaOne, true, Color3.fromRGB(30, 20, 0), "!"
markerIcon.Parent = markerRing
local markerText = Instance.new("TextLabel")
markerText.BackgroundTransparency, markerText.Position, markerText.Size = 1, UDim2.fromScale(0, 0.64), UDim2.fromScale(1, 0.36)
markerText.Font, markerText.TextScaled, markerText.TextColor3, markerText.TextStrokeTransparency = Enum.Font.FredokaOne, true, Color3.new(1, 1, 1), 0.2
markerText.Parent = marker
local markerMode = nil     -- nil, "post" or "exit"
local timerLabel = label("Timer", UDim2.fromScale(0.16, 0.045), UDim2.fromScale(0.14, 0.08), 30, Color3.fromRGB(255, 255, 255))

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 0
flash.Parent = gui

local vignette = Instance.new("ImageLabel")
vignette.Name = "ChaseVignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.Image = "rbxasset://textures/ui/TopBar/WhiteOverlayAsset.png"
vignette.ImageColor3 = Color3.fromRGB(200, 0, 0)
vignette.ImageTransparency = 1
vignette.ZIndex = 0
vignette.Parent = gui

local WORDS = {"one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
	"thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"}
local function childSays(n)
	local w = string.upper(WORDS[n] or tostring(n))
	local r = math.random()
	if r < 0.25 then
		w = string.sub(w, 1, 1) .. "-" .. w                                    -- s-seven
	elseif r < 0.45 then
		local last = string.sub(w, -1)
		w = w .. string.rep(last, 2 + math.random(0, 2))                       -- tennnn
	end
	return ". . . " .. w .. " . . ."
end

local statusToken = 0
local function status(text, seconds, color)
	statusToken += 1
	local token = statusToken
	statusLabel.Text = text
	statusLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	if seconds then
		task.delay(seconds, function() if statusToken == token then statusLabel.Text = "" end end)
	end
end

local function pulse(frame, prop, from, to, seconds)
	frame[prop] = from
	TweenService:Create(frame, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {[prop] = to}):Play()
end

-- ---------------------------------------------------------------------------------------
-- audio: the child's voice is the recorded lines in ReplicatedStorage.Level6Counter.Voice, played from
-- the doll itself so you can hear where it is. Nothing here may reuse another level's sounds: the first
-- version borrowed Level 1's spot scream, chase loop, jumpscare and alert, and the owner rejected that.
local SoundService = game:GetService("SoundService")
local audio = Instance.new("Folder")
audio.Name = "Level6PlaygroundAudio"
audio.Parent = SoundService
-- With this false every Level 6 sound is created silent and the child never speaks.
local AUDIO_ENABLED = true
local function sound(name, id, volume, looped)
	local s = Instance.new("Sound")
	s.Name, s.SoundId, s.Volume, s.Looped = name, AUDIO_ENABLED and id or "", AUDIO_ENABLED and volume or 0, looped == true
	s.Parent = audio
	return s
end
local SFX = {
	ping = sound("Ping", "rbxasset://sounds/electronicpingshort.wav", 0.8), -- dunk
}
local counter = ReplicatedStorage:WaitForChild("Level6Counter")
local function childModel()
	local model = workspace:FindFirstChild(MODEL_NAME)
	return model and model:FindFirstChild("Level 6 Counting Child")
end
local speaking = nil      -- the line the doll is saying now
local paCopies = {}       -- and its copies on the ceiling horns
local function stopVoice()
	if speaking then speaking:Destroy(); speaking = nil end
	for pa in pairs(paCopies) do pa:Destroy() end
	table.clear(paCopies)
end
-- One line at a time: a new line cuts the old one off, as the server only sends a line that should win.
-- Every one-shot fades in over a few hundredths of a second and out over its last 0.15 s, so nothing clicks
-- or sounds cut off.
local function soft(s, volume)
	local length = s:GetAttribute("Seconds") or s.TimeLength
	s.Volume = 0
	TweenService:Create(s, TweenInfo.new(0.06), {Volume = volume}):Play()
	if length and length > 0.4 then
		task.delay(length - 0.18, function()
			if s.Parent then TweenService:Create(s, TweenInfo.new(0.16), {Volume = 0}):Play() end
		end)
	end
end

-- The hall's music comes out of the PA: a copy on each of the nearest ceiling horns, kept in step with a very
-- quiet bed that is heard everywhere. It drops right down while the doll is talking. Every tag on the post
-- restarts the tape a little faster and lower (MUSIC_STAGES); the finale plays it backwards.
local HORN_VOLUME, BED_VOLUME, DUCK = 1.2, 0.45, 0.45    -- owner could not hear it at 0.5 / 0.14; the horns hang 30+ studs up
local MUSIC_STAGES = {{speed = 1, octave = 1}, {speed = 1.12, octave = 0.82}, {speed = 1.26, octave = 0.66}}
local music = {key = nil, stage = 1, bed = nil, horns = {}, level = 0, wanted = false, pending = false}

local function dressMusic(m, stage)
	local st = MUSIC_STAGES[stage] or MUSIC_STAGES[1]
	m.Looped, m.PlaybackSpeed = true, st.speed
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain, eq.MidGain, eq.HighGain = -3, 0, -4
	eq.Parent = m
	if st.octave ~= 1 then
		local shift = Instance.new("PitchShiftSoundEffect")
		shift.Octave = st.octave
		shift.Parent = m
	end
end

local function dropMusic(seconds)
	local old = {music.bed}
	for _, h in pairs(music.horns) do old[#old + 1] = h end
	music.bed, music.horns = nil, {}
	for _, o in ipairs(old) do
		TweenService:Create(o, TweenInfo.new(seconds), {Volume = 0}):Play()
		task.delay(seconds + 0.1, function() o:Destroy() end)
	end
end

local function setMusic(key, stage)
	stage = stage or 1
	if music.key == key and music.stage == stage then return end
	music.key, music.stage = key, stage
	dropMusic(1.2)
	local voice = counter:FindFirstChild("Voice")
	local source = key and AUDIO_ENABLED and voice and voice:FindFirstChild(key)
	if not source then return end
	local bed = source:Clone()
	dressMusic(bed, stage)
	bed.Volume = 0
	bed.Parent = audio
	bed:Play()
	music.bed, music.level = bed, 0          -- the tick below fades it up and hangs copies on the horns
end

local function musicTick(dt)
	local bed = music.bed
	if not bed then return end
	-- duck under any line that is playing
	local talking = speaking ~= nil or next(paCopies) ~= nil
	local goal = talking and DUCK or 1
	music.level += math.clamp(goal - music.level, -dt * 1.6, dt * 0.7)
	bed.Volume = BED_VOLUME * music.level
	local model = workspace:FindFirstChild(MODEL_NAME)
	local props = model and model:FindFirstChild("Props")
	local cam = workspace.CurrentCamera
	local near = {}
	if props and cam then
		local all = {}
		for _, h in ipairs(props:GetChildren()) do
			if h.Name == "pa_speaker" then all[#all + 1] = h end
		end
		table.sort(all, function(x, y) return (x.Position - cam.CFrame.Position).Magnitude < (y.Position - cam.CFrame.Position).Magnitude end)
		for i = 1, math.min(#all, 4) do near[all[i]] = true end
	end
	for horn, m in pairs(music.horns) do
		if not near[horn] or not horn.Parent then
			music.horns[horn] = nil
			TweenService:Create(m, TweenInfo.new(0.8), {Volume = 0}):Play()
			task.delay(0.9, function() m:Destroy() end)
		end
	end
	local voice = counter:FindFirstChild("Voice")
	local source = voice and voice:FindFirstChild(music.key)
	for horn in pairs(near) do
		local m = music.horns[horn]
		if not m and source then
			m = source:Clone()
			dressMusic(m, music.stage)
			m.Volume = 0
			m.RollOffMode, m.RollOffMinDistance, m.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 55, 220
			m.Parent = horn
			m.TimePosition = bed.TimePosition
			m:Play()
			music.horns[horn] = m
		end
		if m then
			m.Volume += math.clamp(HORN_VOLUME * music.level - m.Volume, -dt * 1.2, dt * 0.35)
			if math.abs(m.TimePosition - bed.TimePosition) > 0.25 then m.TimePosition = bed.TimePosition end
		end
	end
end

local function oneShot(key, volume)
	local voice = counter:FindFirstChild("Voice")
	local source = AUDIO_ENABLED and voice and voice:FindFirstChild(key)
	if not source then return end
	local o = source:Clone()
	o.Parent = audio
	o.Ended:Once(function() o:Destroy() end)
	o:Play()
	soft(o, volume)
end

-- A tag on the post: the tape stops with the CD-change sound and starts again, faster and lower each time.
local function changeTrack(key, stage)
	music.key, music.pending = nil, true
	dropMusic(0.25)
	oneShot("l6_track_change", 0.2)
	task.delay(2.4, function()
		music.pending = false
		if music.wanted and music.key == nil then setMusic(key, stage) end
	end)
end

-- `paOnly`: a hall announcement (the chime, the welcome): the ceiling horns and a quiet copy everywhere,
-- not the doll's own mouth
local function say(key, paOnly)
	if not AUDIO_ENABLED then return end
	local voice = counter:FindFirstChild("Voice")
	local source = voice and voice:FindFirstChild(key)
	if not source then return end
	stopVoice()
	local child = childModel()
	local s = source:Clone()
	local level = s.Volume
	if paOnly then
		level = 0.35
		s.Parent = audio                      -- heard wherever you are, under the horns
	else
		s.Parent = (child and child:FindFirstChild("Root")) or audio
	end
	speaking = s
	s.Ended:Once(function()
		if speaking == s then speaking = nil end
		s:Destroy()
	end)
	s:Play()
	soft(s, level)
	-- the same line over the hall's PA: the nearest ceiling horns, thin and echoing
	local model = workspace:FindFirstChild(MODEL_NAME)
	local props = model and model:FindFirstChild("Props")
	local cam = workspace.CurrentCamera
	if props and cam then
		local horns = {}
		for _, h in ipairs(props:GetChildren()) do
			if h.Name == "pa_speaker" then horns[#horns + 1] = h end
		end
		table.sort(horns, function(x, y) return (x.Position - cam.CFrame.Position).Magnitude < (y.Position - cam.CFrame.Position).Magnitude end)
		for i = 1, math.min(#horns, 5) do
			local pa = source:Clone()
			pa.RollOffMode, pa.RollOffMinDistance, pa.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 30, 190
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain, eq.MidGain, eq.HighGain = -22, 2, -8
			eq.Parent = pa
			local echo = Instance.new("ReverbSoundEffect")
			echo.DecayTime, echo.WetLevel, echo.DryLevel = 2.6, -4, -2
			echo.Parent = pa
			pa.Parent = horns[i]
			paCopies[pa] = true
			pa.Ended:Once(function() paCopies[pa] = nil; pa:Destroy() end)
			task.delay(32, function() paCopies[pa] = nil; if pa.Parent then pa:Destroy() end end)
			pa:Play()
			soft(pa, 0.5)
		end
	end
end
local dunked = false
event.OnClientEvent:Connect(function(kind, a)
	if kind == "say" then
		say(a)
	elseif kind == "pa" then
		say(a, true)
	elseif kind == "dunk" or kind == "escaped" then
		SFX.ping:Play()
	end
end)
event.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "paused" then
		countLabel.Text, statusLabel.Text, dunkLabel.Text, timerLabel.Text = "", "", "", ""
		hintLabel.Text = "Free roam: hide and seek is paused."
		objective(nil)
	elseif kind == "joined" then
		dunkLabel.Text = string.format("TAGS %d / %d", b or 0, c or 0)
		hintLabel.Text = ""
		objective("HIDE!", "It is counting. Find a hiding place.")
		-- the music waits for the first count (the welcome plays in quiet); a late joiner gets it straight away
		music.wanted = (a or 0) >= 2 or d == "seek" or d == "between" or d == "escape"
		if d == "seek" then status("It is already looking. HIDE.", 4, Color3.fromRGB(255, 90, 90)) end
	elseif kind == "round" then
		dunked = false
		countLabel.Text = ""
		dunkLabel.Text = string.format("TAGS %d / %d", b, c)
		markerMode = nil
		music.wanted = true
		objective("HIDE!", "It is counting. Find a hiding place.")
		status("ROUND " .. tostring(a) .. "  ·  HIDE!", 3, Color3.fromRGB(255, 230, 90))
		hintLabel.Text = ""
		timerLabel.Text = ""
	elseif kind == "count" then
		countLabel.Text = childSays(a)
		countLabel.Rotation = math.random(-4, 4)
		pulse(countLabel, "TextTransparency", 0, 0.25, 0.8)
	elseif kind == "go" then
		countLabel.Text = "READY OR NOT . . ."
		status("HERE I COME!", 2.5, Color3.fromRGB(255, 70, 70))
		hintLabel.Text = ""
		markerMode = "post"
		objective("TOUCH THE POST", "Sneak to the yellow post. Do not let it see you.")
		task.delay(2.2, function() if countLabel.Text == "READY OR NOT . . ." then countLabel.Text = "" end end)
	elseif kind == "timer" then
		timerLabel.Text = string.format("%d:%02d", a // 60, a % 60)
	elseif kind == "dunk" then
		dunkLabel.Text = string.format("TAGS %d / %d", b, c)
		if (b or 0) < (c or 3) then changeTrack("l6_music", (b or 0) + 1) end
		if a == player.DisplayName then
			dunked = true
			markerMode = nil
			objective("TAGGED!", "Hide again until it goes back to count.", Color3.fromRGB(120, 255, 150))
		end
		status(string.upper(a) .. " TAGGED THE POST!", 2.5, Color3.fromRGB(120, 255, 150))
	elseif kind == "chase" then
		vignette.ImageTransparency = a and 0.35 or 1
		if a then status("IT SEES YOU. RUN!", 2, Color3.fromRGB(255, 60, 60)) end
	elseif kind == "caught" then
		if b then
			pulse(flash, "BackgroundTransparency", 0, 1, 2)
			countLabel.Text = "FOUND YOU!"
			status("You were found. Back to the lobby . . .", 3, Color3.fromRGB(255, 80, 80))
		else
			status("It found " .. tostring(a) .. ".", 3, Color3.fromRGB(255, 120, 120))
		end
	elseif kind == "roundover" then
		vignette.ImageTransparency = 1
		status(a == "alldunked" and "Everyone tagged the post! It is counting again . . ." or "Time's up. It goes back to count . . .", 3)
	elseif kind == "won" then
		countLabel.Text = ""
		status("IT LOST. NOW IT IS ANGRY.", 5, Color3.fromRGB(255, 70, 60))
		hintLabel.Text = ""
		markerMode = "exit"
		objective("RUN TO THE EXIT!", "The red door inside STAFF ONLY. It is angry and fast.", Color3.fromRGB(255, 70, 60))
		timerLabel.Text = ""
	elseif kind == "escaped" then
		vignette.ImageTransparency = 1
		countLabel.Text = "LEVEL 6 CLEARED"
		status("You got out.", 4, Color3.fromRGB(120, 255, 150))
	elseif kind == "lost" then
		countLabel.Text = "EVERYONE WAS FOUND"
	elseif kind == "left" then
		vignette.ImageTransparency = 1
		task.delay(3, function()
			if player:GetAttribute(IN_PREVIEW) ~= true then
				countLabel.Text, statusLabel.Text, hintLabel.Text, timerLabel.Text = "", "", "", ""
				markerMode = nil
				objective(nil)
			end
		end)
	end
end)

-- ---------------------------------------------------------------------------------------
-- lighting: dim warehouse night, cold fluorescent pools, a little haze
local finale = 0      -- 0 = normal hall, 1 = fully red; eases over a few seconds (the tick near the end drives it)
local LOOK = {
	Ambient = Color3.fromRGB(74, 76, 82), OutdoorAmbient = Color3.fromRGB(0, 0, 0), Brightness = 0,
	ClockTime = 0, FogColor = Color3.fromRGB(62, 66, 68), FogStart = 0, FogEnd = 520,   -- a grey haze, not black
	ColorShift_Top = Color3.new(0, 0, 0), ColorShift_Bottom = Color3.new(0, 0, 0), ExposureCompensation = 0.4,
}
local saved = nil
local grade, bloom = nil, nil
local function applyLighting(on)
	if on and not saved then
		saved = {}
		for k in pairs(LOOK) do saved[k] = Lighting[k] end
		saved.atmospheres = {}
		for _, a in ipairs(Lighting:GetChildren()) do
			if a:IsA("Atmosphere") then saved.atmospheres[a] = a.Density; a.Density = 0 end
		end
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "Level6PlaygroundGrade"
		-- Ambient and Fog do nothing visible under this place's Realistic lighting: the dusty grey air is
		-- exposure up plus a grade that lifts the blacks
		grade.Saturation, grade.Contrast, grade.Brightness = 0.08, -0.17, -0.01
		grade.TintColor = Color3.fromRGB(238, 245, 255)
		grade.Parent = Lighting
		bloom = Instance.new("BloomEffect")       -- the tubes glow into the haze
		bloom.Name = "Level6PlaygroundBloom"
		bloom.Intensity, bloom.Size, bloom.Threshold = 0.3, 24, 2.0
		bloom.Parent = Lighting
		player:SetAttribute(LIGHTING_OWNED, true)
	elseif not on and saved then
		for k, v in pairs(saved) do
			if k ~= "atmospheres" then Lighting[k] = v end
		end
		for a, density in pairs(saved.atmospheres) do
			if a.Parent then a.Density = density end
		end
		saved = nil
		if grade then grade:Destroy(); grade = nil end
		if bloom then bloom:Destroy(); bloom = nil end
		player:SetAttribute(LIGHTING_OWNED, nil)
	end
	if on then
		for k, v in pairs(LOOK) do
			if not (k == "ExposureCompensation" and finale > 0) then Lighting[k] = v end
		end
		-- other controllers put the lobby's Atmosphere back; with a black sky it swallows the whole hall
		for _, a in ipairs(Lighting:GetChildren()) do
			if a:IsA("Atmosphere") and a.Density ~= 0 then a.Density = 0 end
		end
	end
end

local function inside()
	return player:GetAttribute(IN_PREVIEW) == true
end

-- marker, music and the red finale
local RED = Color3.fromRGB(255, 14, 8)
local litBefore = setmetatable({}, {__mode = "k"})     -- light or lamp -> {colour, brightness}
local FINALE_FOLDERS = {"Lights", "Ceiling_Fixtures", "Frame_Lamps", "PartyRooms", "StaffOnly", "SnackShack"}
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(0.1)
		local now = os.clock()
		local dt = now - last
		last = now
		local model = workspace:FindFirstChild(MODEL_NAME)
		local on = model ~= nil and player:GetAttribute(IN_PREVIEW) == true
		local target = on and markerMode and model:GetAttribute(markerMode == "post" and "HomePosition" or "ExitPosition")
		if target then
			markerPart.Position = target + Vector3.new(0, markerMode == "post" and 16 or 9, 0)
			markerPart.Parent = workspace
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local dist = root and (root.Position - target).Magnitude or 200
			local px = math.clamp(250 - dist * 0.85, 80, 250)      -- grows as you get close
			marker.Size = UDim2.fromOffset(px, px)
			markerText.Text = (markerMode == "post" and "TOUCH" or "EXIT") .. "  " .. math.floor(dist / 3.6 + 0.5) .. " m"
			markerRing.BackgroundColor3 = markerMode == "post" and Color3.fromRGB(255, 215, 40) or Color3.fromRGB(255, 70, 60)
			marker.Enabled = true
		else
			marker.Enabled = false
			markerPart.Parent = nil
		end

		local enraged = on and model:GetAttribute("Level6Enraged") == true
		-- music: the tape, the tape backwards in the finale, nothing outside a round
		if not (on and music.wanted) then
			setMusic(nil)
		elseif enraged then
			if music.key == "l6_music" then changeTrack("l6_music_reversed", 1)
			elseif music.key == nil and not music.pending then setMusic("l6_music_reversed", 1) end
		elseif music.key == nil and not music.pending then
			setMusic("l6_music", music.stage)
		end
		musicTick(dt)

		-- the red finale: the white tubes die down and come back deep red over about four seconds, then throb
		finale = math.clamp(finale + (enraged and dt / 4 or -dt / 2), 0, 1)
		if model and (finale > 0 or next(litBefore)) then
			local dip = math.sin(math.min(finale, 1) * math.pi)            -- 0 -> 1 -> 0: the lights sag in the middle of the change
			local throb = 1 + 0.22 * math.sin(now * 2.2) * finale
			local strength = (1 - 0.75 * dip) * throb
			local colour = function(c) return c:Lerp(RED, finale * finale) end
			for _, folderName in ipairs(FINALE_FOLDERS) do
				local folder = model:FindFirstChild(folderName)
				if folder then
					for _, d in ipairs(folder:GetDescendants()) do
						local isLight = d:IsA("Light")
						if isLight or (d:IsA("BasePart") and d.Material == Enum.Material.Neon) then
							local before = litBefore[d]
							if finale > 0 then
								if before == nil then
									before = {d.Color, isLight and d.Brightness or 0}
									litBefore[d] = before
								end
								d.Color = colour(before[1])
								if isLight then d.Brightness = before[2] * strength * (1 + 0.6 * finale) end
							elseif before ~= nil then
								d.Color = before[1]
								if isLight then d.Brightness = before[2] end
								litBefore[d] = nil
							end
						end
					end
				end
			end
			if grade then
				grade.TintColor = Color3.fromRGB(238, 245, 255):Lerp(Color3.fromRGB(255, 96, 84), finale)
				grade.Contrast = -0.17 + 0.3 * finale          -- the grey haze goes; blacks come back
				grade.Saturation = 0.08 - 0.2 * finale
			end
			Lighting.ExposureCompensation = LOOK.ExposureCompensation - 0.55 * finale
		end
	end
end)

local function refresh()
	local on = inside()
	gui.Enabled = on
	applyLighting(on)
	if on then
	else
		vignette.ImageTransparency = 1
		stopVoice()
		markerMode = nil
		music.wanted = false
		setMusic(nil)
		music.stage = 1
		objective(nil)
	end
	-- the lobby track must not follow the player in here (LobbyMusicController only knows real rounds)
	local lobbyMusic = SoundService:FindFirstChild("ZyntraLobbyMusic")
	if lobbyMusic and lobbyMusic:IsA("SoundGroup") then lobbyMusic.Volume = on and 0 or 1 end
end
player:GetAttributeChangedSignal(IN_PREVIEW):Connect(refresh)
refresh()
task.spawn(function()
	while true do
		task.wait(0.5)
		if inside() then applyLighting(true) end   -- keep the night if anything else re-grades
	end
end)

-- ---------------------------------------------------------------------------------------
-- slides: anything tagged L6Slide carries you downhill
local sliding, offSince, stalledSince = false, 0, nil
RunService.RenderStepped:Connect(function(dt)
	if not inside() then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not root or not model then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -5, 0), params)
	local slide = hit and hit.Instance:GetAttribute("L6Slide") == true and hit.Normal.Y < 0.985 and hit.Normal.Y > 0.2
	if slide then
		local n = hit.Normal
		local downhill = (Vector3.new(0, -1, 0) + n * n.Y).Unit
		local v = root.AssemblyLinearVelocity
		local along = math.max(v:Dot(downhill), 26)
		root.AssemblyLinearVelocity = downhill * math.min(along + 55 * dt, 62)
		if not sliding then sliding = true; humanoid.Sit = true end
		offSince = os.clock()
		-- wedged on a seam: stand up so the player can walk off instead of sitting stuck
		if v.Magnitude < 4 then
			stalledSince = stalledSince or os.clock()
			if os.clock() - stalledSince > 0.5 then
				humanoid.Sit = false
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				stalledSince = nil
			end
		else
			stalledSince = nil
		end
	elseif sliding and os.clock() - offSince > 0.3 then
		sliding = false
		stalledSince = nil
		humanoid.Sit = false
	end
end)

-- ---------------------------------------------------------------------------------------
-- the counting child: the server publishes Anim / AnimSerial / Speed on the model, the clips are JSON in
-- ReplicatedStorage.Level6Counter.Clips (one quaternion per bone per frame, written by tools/level6_entity).
local clips = {}
local function clip(name)
	local c = clips[name]
	if c == nil then
		c = false
		local folder = counter:FindFirstChild("Clips")
		local value = folder and folder:FindFirstChild(name)
		local ok, data = pcall(function() return HttpService:JSONDecode(value.Value) end)
		if ok and data then
			local tracks = {}
			for bone, q in pairs(data.bones) do
				local frames = table.create(data.frames)
				for f = 0, data.frames - 1 do
					local i = f * 4
					frames[f + 1] = CFrame.new(0, 0, 0, q[i + 1] / 10000, q[i + 2] / 10000, q[i + 3] / 10000, q[i + 4] / 10000)
				end
				tracks[bone] = frames
			end
			local hips = nil
			if data.hips then
				hips = table.create(data.frames)
				for f = 0, data.frames - 1 do
					local i = f * 3
					hips[f + 1] = Vector3.new(data.hips[i + 1], data.hips[i + 2], data.hips[i + 3]) / 1000
				end
			end
			c = {frames = data.frames, fps = data.fps, loop = data.loop, tracks = tracks, hips = hips}
		end
		clips[name] = c
	end
	return c or nil
end

-- studs per second at which each travelling clip's feet match the floor
local STRIDE = {Walk_Wander = 5.1, Run_Chase = 11.5}
local TWITCH_OVER = {Idle = true, Walk_Wander = true, Run_Chase = true}
local FADE = 0.16
local rigs = setmetatable({}, {__mode = "k"})

local function rigOf(child)
	local rig = rigs[child]
	if rig then return rig end
	local body = child:FindFirstChild("Body")
	if not body then return nil end
	local bones = {}
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("Bone") then bones[d.Name] = d end
	end
	if not bones.Hips or not bones.Head then return nil end   -- still streaming in
	rig = {bones = bones, last = {}, from = {}, fade = 1, t = 0, name = nil, serial = nil,
		nextTwitch = os.clock() + 3, twitchT = nil}
	rigs[child] = rig
	return rig
end

-- frame position -> two frame indices and the blend between them
local function at(c, t)
	local f = t * c.fps
	local last = c.frames - 1
	if c.loop then f = f % last else f = math.min(f, last) end
	local i = math.floor(f)
	return i + 1, math.min(i + 2, c.frames), f - i
end

RunService.RenderStepped:Connect(function(dt)
	local child = childModel()
	local rig = child and rigOf(child)
	if not rig then return end
	local name = child:GetAttribute("Anim") or "Idle"
	local serial = child:GetAttribute("AnimSerial") or 0
	if name ~= rig.name or serial ~= rig.serial then
		rig.from = table.clone(rig.last)
		rig.fade = 0
		rig.name, rig.serial, rig.t = name, serial, 0
	end
	local c = clip(name)
	if not c then return end
	local stride = STRIDE[name]
	local rate = stride and math.clamp((child:GetAttribute("Speed") or 0) / stride, 0.6, 2.1) or 1
	rig.t += dt * rate
	rig.fade = math.min(1, rig.fade + dt / FADE)
	local i0, i1, a = at(c, rig.t)

	-- the extra head twitch, at uneven moments, over the clips that leave the head free
	local twitch, t0, t1, ta = nil, nil, nil, nil
	if TWITCH_OVER[name] then
		if rig.twitchT == nil and os.clock() > rig.nextTwitch then rig.twitchT = 0 end
		if rig.twitchT ~= nil then
			twitch = clip("Head_Twitch")
			rig.twitchT += dt
			if not twitch or rig.twitchT * twitch.fps >= twitch.frames - 1 then
				twitch, rig.twitchT = nil, nil
				rig.nextTwitch = os.clock() + 1.5 + math.random() * 4.5
			else
				t0, t1, ta = at(twitch, rig.twitchT)
			end
		end
	else
		rig.twitchT = nil
	end

	for boneName, bone in pairs(rig.bones) do
		local frames = (twitch and twitch.tracks[boneName]) or c.tracks[boneName]
		local target
		if twitch and twitch.tracks[boneName] then
			target = frames[t0]:Lerp(frames[t1], ta)
		elseif frames then
			target = frames[i0]:Lerp(frames[i1], a)
		else
			target = CFrame.identity
		end
		if boneName == "Hips" and c.hips then
			target = CFrame.new(c.hips[i0]:Lerp(c.hips[i1], a)) * target
		end
		if rig.fade < 1 then
			local from = rig.from[boneName]
			if from then target = from:Lerp(target, rig.fade) end
		end
		bone.Transform = target
		rig.last[boneName] = target
	end
end)
