-- Level 6 Indoor Playground, client side: hide-and-seek HUD, the counting child's limb animation,
-- the hall's lighting while you are inside, and the slide ride.
-- Server side: ServerScriptService."Level 6 Playground Game" (events on ReplicatedStorage.Level6Playground.Event).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

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

local countLabel = label("Count", UDim2.fromScale(0.7, 0.18), UDim2.fromScale(0.5, 0.2), 110, Color3.fromRGB(255, 235, 120))
local statusLabel = label("Status", UDim2.fromScale(0.8, 0.07), UDim2.fromScale(0.5, 0.33), 44, Color3.fromRGB(255, 255, 255))
local hintLabel = label("Hint", UDim2.fromScale(0.8, 0.045), UDim2.fromScale(0.5, 0.9), 28, Color3.fromRGB(230, 230, 230))
local dunkLabel = label("Dunks", UDim2.fromScale(0.24, 0.05), UDim2.fromScale(0.86, 0.08), 32, Color3.fromRGB(120, 255, 150))
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
-- audio: the child's voice is Roblox text-to-speech (one request per count, so the per-experience
-- request budget is never an issue); the stings reuse sounds the experience already owns.
local SoundService = game:GetService("SoundService")
local audio = Instance.new("Folder")
audio.Name = "Level6PlaygroundAudio"
audio.Parent = SoundService
-- Paused 2026-10-03 on the owner's request while new sounds are made: with this false every Level 6
-- sound is created silent and the child's voice is never requested. Set it back to true to restore them.
local AUDIO_ENABLED = false
local function sound(name, id, volume, looped)
	local s = Instance.new("Sound")
	s.Name, s.SoundId, s.Volume, s.Looped = name, AUDIO_ENABLED and id or "", AUDIO_ENABLED and volume or 0, looped == true
	s.Parent = audio
	return s
end
local SFX = {
	hum = sound("Hum", "rbxassetid://92576512092725", 0.25, true),          -- fluorescent hum
	spot = sound("Spot", "rbxassetid://82272419363488", 0.9),               -- it has seen you
	chase = sound("Chase", "rbxassetid://79246919959914", 0.7, true),       -- while it is after you
	caught = sound("Caught", "rbxassetid://140233243543479", 1),            -- you were found
	otherCaught = sound("OtherCaught", "rbxassetid://113822157484898", 0.5),
	alarm = sound("Alarm", "rbxassetid://118863512220494", 0.35, true),     -- exit open
	ping = sound("Ping", "rbxasset://sounds/electronicpingshort.wav", 0.8), -- dunk
}
local voice = Instance.new("AudioTextToSpeech")
voice.Name, voice.VoiceId, voice.Pitch, voice.Volume = "ChildVoice", "1", 7, 1.4
voice.Parent = audio
local voiceOut = Instance.new("AudioDeviceOutput")
voiceOut.Parent = audio
local voiceWire = Instance.new("Wire")
voiceWire.SourceInstance, voiceWire.TargetInstance = voice, voiceOut
voiceWire.Parent = audio
local voiceToken = 0
-- Speak `text`; when `seconds` is given the speech is stretched or squeezed to last about that long.
local function say(text, seconds)
	if not AUDIO_ENABLED then return end
	voiceToken += 1
	local token = voiceToken
	task.spawn(function()
		pcall(function() voice:Pause() end)
		voice.Text = text
		local ok, status = pcall(function() return voice:LoadAsync() end)
		if token ~= voiceToken or not ok or status ~= Enum.AssetFetchStatus.Success then return end
		local length = voice.TimeLength
		voice.PlaybackSpeed = (seconds and length > 0) and math.clamp(length / seconds, 0.7, 1.6) or 1
		voice.TimePosition = 0
		voice:Play()
	end)
end
-- Roblox's text filter rejects long runs of numbers (they read as personal information), and every
-- utterance is one request against a per-minute budget, so the child says the count in a few short
-- bursts and mouths the rest. Key = the number the burst starts on; value = text, numbers covered.
local COUNT_BURSTS = {
	[1] = {"one, two, three, four, five.", 5},
	[6] = {"six, seven, eight, nine, ten.", 5},
	[13] = {"thirteen, fourteen, fifteen.", 3},
	[19] = {"nineteen, twenty!", 2},
}
local countBeat = 1
local function stopEncounterAudio()
	SFX.chase:Stop(); SFX.alarm:Stop()
end

local dunked = false
event.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "round" then
		countBeat = (d or 20) / 20
	elseif kind == "count" then
		local burst = COUNT_BURSTS[a]
		if burst then say(burst[1], burst[2] * countBeat) end
	elseif kind == "go" then
		say("Ready or not. Here I come!")
	elseif kind == "chase" then
		if a then SFX.spot:Play(); SFX.chase:Play() else SFX.chase:Stop() end
	elseif kind == "caught" then
		stopEncounterAudio()
		if b then SFX.caught:Play(); say("Found you!") else SFX.otherCaught:Play() end
	elseif kind == "dunk" then
		SFX.ping:Play()
	elseif kind == "won" then
		SFX.alarm:Play()
	elseif kind == "escaped" or kind == "left" or kind == "lost" or kind == "roundover" then
		stopEncounterAudio()
		if kind == "escaped" then SFX.ping:Play() end
	end
end)
event.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "paused" then
		countLabel.Text, statusLabel.Text, dunkLabel.Text, timerLabel.Text = "", "", "", ""
		hintLabel.Text = "Free roam: hide and seek is paused."
	elseif kind == "joined" then
		dunkLabel.Text = string.format("DUNKS %d / %d", b or 0, c or 0)
		hintLabel.Text = "It counts at HOME BASE. Hide before it reaches twenty."
		if d == "seek" then status("It is already looking. HIDE.", 4, Color3.fromRGB(255, 90, 90)) end
	elseif kind == "round" then
		dunked = false
		countLabel.Text = ""
		dunkLabel.Text = string.format("DUNKS %d / %d", b, c)
		status("ROUND " .. tostring(a) .. "  ·  HIDE!", 3, Color3.fromRGB(255, 230, 90))
		hintLabel.Text = "Hide anywhere: houses, tubes, under tables, in the balls. Stay still."
		timerLabel.Text = ""
	elseif kind == "count" then
		countLabel.Text = childSays(a)
		countLabel.Rotation = math.random(-4, 4)
		pulse(countLabel, "TextTransparency", 0, 0.25, 0.8)
	elseif kind == "go" then
		countLabel.Text = "READY OR NOT . . ."
		status("HERE I COME!", 2.5, Color3.fromRGB(255, 70, 70))
		hintLabel.Text = "While it is away, run and touch HOME BASE to dunk. One dunk each per round."
		task.delay(2.2, function() if countLabel.Text == "READY OR NOT . . ." then countLabel.Text = "" end end)
	elseif kind == "timer" then
		timerLabel.Text = string.format("0:%02d", a)
	elseif kind == "dunk" then
		dunkLabel.Text = string.format("DUNKS %d / %d", b, c)
		if a == player.DisplayName then dunked = true end
		status(string.upper(a) .. " DUNKED!", 2.5, Color3.fromRGB(120, 255, 150))
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
		status(a == "alldunked" and "Everyone dunked! It is counting again . . ." or "Time's up. It goes back to count . . .", 3)
	elseif kind == "won" then
		countLabel.Text = ""
		status("THE EXIT IS OPEN! RUN TO THE GREEN LIGHT!", 6, Color3.fromRGB(120, 255, 150))
		hintLabel.Text = "Emergency exit: far corner, by the arcade. It is angry now."
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
			end
		end)
	end
end)

-- ---------------------------------------------------------------------------------------
-- lighting: dim warehouse night, cold fluorescent pools, a little haze
local LOOK = {
	Ambient = Color3.fromRGB(34, 34, 44), OutdoorAmbient = Color3.fromRGB(0, 0, 0), Brightness = 0,
	ClockTime = 0, FogColor = Color3.fromRGB(12, 12, 18), FogStart = 40, FogEnd = 330,
	ColorShift_Top = Color3.new(0, 0, 0), ColorShift_Bottom = Color3.new(0, 0, 0), ExposureCompensation = 0.25,
}
local saved = nil
local grade = nil
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
		grade.Saturation, grade.Contrast, grade.Brightness = -0.12, 0.18, 0.02
		grade.TintColor = Color3.fromRGB(235, 240, 255)
		grade.Parent = Lighting
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
		player:SetAttribute(LIGHTING_OWNED, nil)
	end
	if on then
		for k, v in pairs(LOOK) do Lighting[k] = v end
	end
end

local function inside()
	return player:GetAttribute(IN_PREVIEW) == true
end

local function refresh()
	local on = inside()
	gui.Enabled = on
	applyLighting(on)
	if on then
		if not SFX.hum.IsPlaying then SFX.hum:Play() end
	else
		vignette.ImageTransparency = 1
		SFX.hum:Stop()
		stopEncounterAudio()
		voiceToken += 1
		pcall(function() voice:Pause() end)
	end
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
-- the counting child's limbs (server publishes Pose/Speed attributes on the model)
local function motorsOf(child)
	local m = {}
	for _, d in ipairs(child:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 then m[d.Part1.Name] = d end
	end
	return m
end
local rigs = setmetatable({}, {__mode = "k"})
local clock = 0
RunService.Heartbeat:Connect(function(dt)
	clock += dt
	local model = workspace:FindFirstChild(MODEL_NAME)
	local child = model and model:FindFirstChild("Level 6 Counting Child")
	if not child then return end
	local m = rigs[child]
	if not m then m = motorsOf(child); rigs[child] = m end
	if not (m.ArmL and m.ArmR and m.LegL and m.LegR and m.Head) then rigs[child] = nil; return end
	local pose = child:GetAttribute("Pose") or "walk"
	local speed = child:GetAttribute("Speed") or 0
	if pose == "count" then
		m.ArmL.Transform = CFrame.Angles(math.rad(150), 0, math.rad(25))
		m.ArmR.Transform = CFrame.Angles(math.rad(135), 0, math.rad(-35))
		m.Head.Transform = CFrame.Angles(math.rad(30), 0, math.sin(clock * 1.7) * 0.08)
		m.LegL.Transform, m.LegR.Transform = CFrame.new(), CFrame.new()
		return
	end
	local swing = math.clamp(speed / 14, 0, 1.6)
	local phase = clock * (5 + speed * 0.45)
	m.ArmL.Transform = CFrame.Angles(math.sin(phase) * 0.7 * swing - 0.15, 0, math.rad(6))
	m.ArmR.Transform = CFrame.Angles(-math.sin(phase) * 0.8 * swing - 0.1, 0, math.rad(-8))
	m.LegL.Transform = CFrame.Angles(-math.sin(phase) * 0.6 * swing, 0, 0)
	m.LegR.Transform = CFrame.Angles(math.sin(phase) * 0.6 * swing, 0, 0)
	local twitch = (math.noise(clock * 3, 1.7) > 0.42) and math.noise(clock * 40, 3.1) * 0.6 or 0
	if pose == "look" then
		m.Head.Transform = CFrame.Angles(0, math.sin(clock * 2.4) * 0.9, 0.25 + twitch)
	else
		m.Head.Transform = CFrame.Angles(math.sin(phase * 0.5) * 0.05, 0, math.rad(12) + twitch)
	end
end)
