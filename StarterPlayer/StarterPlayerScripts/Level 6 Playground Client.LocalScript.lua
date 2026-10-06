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
-- The round body is a fresh character (entry and every re-entry): a gui that resets on spawn was destroyed
-- there, which is why the post marker stopped showing once Level 6 became a live round.
marker.ResetOnSpawn = false
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
-- Owner, 2026-10-03: the level was far too loud. GENERAL scales every effect and loop; the doll (its voice,
-- its PA copies and its footsteps) is only halved; the music takes the general cut and then half again.
local GENERAL, ENTITY, MUSIC = 0.35, 0.5, 0.5
local SFX = {
	ping = sound("Ping", "rbxasset://sounds/electronicpingshort.wav", 0.8 * GENERAL), -- dunk
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
local HORN_VOLUME, BED_VOLUME, DUCK = 0.18, 0.12, 0.45
-- Owner, 2026-10-04: the music belongs on the PA. (On 2026-10-03 it was taken off the horns because it sounded
-- like an echo: the copies ran up to a quarter of a second apart and the non-positional track played under them.
-- Now the horns are the only thing heard, the plain track is a silent clock for them, and a copy that drifts more
-- than 0.05 s is pulled back.) The tape played backwards in the finale is louder than the music ever is.
local MUSIC_ON_HORNS = true
local REVERSED_GAIN = 2.2
local MUSIC_STAGES = {{speed = 1, octave = 1}, {speed = 1.12, octave = 0.82}, {speed = 1.26, octave = 0.66}}
local music = {key = nil, stage = 1, bed = nil, horns = {}, level = 0, wanted = false, pending = false,
	startedAt = 0, aligned = {}, bus = {}}

-- MUSIC_SMOOTH_20261006 (owner: "the music stutters ... it happens for me every time"). Two things made it hitch:
-- 1. Every copy on a horn was pulled back with a jump whenever it read more than 0.05 s out of step, twenty times a
--    second. Two positions read in one frame differ by that much on their own when the frame rate is low, so on a
--    machine that is not running smoothly the copies were being re-seeked all the time. Now a copy is set once as it
--    comes in (still silent), kept in step by running it 1.5% slower or faster for a moment, and only jumps if it is
--    three quarters of a second out. The reference is the wall clock, not another sound's position.
-- 2. Every copy carried its own equaliser and, from the second tape on, its own pitch shifter: up to five of the
--    most expensive effect there is, at once. The effects now sit once on a sound group per tape.
local function musicBus(stage)
	local bus = music.bus[stage]
	if not bus then
		local st = MUSIC_STAGES[stage] or MUSIC_STAGES[1]
		bus = Instance.new("SoundGroup")
		bus.Name = "Level6MusicBus" .. tostring(stage)
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain, eq.MidGain, eq.HighGain = -3, 0, -4
		eq.Parent = bus
		if st.octave ~= 1 then
			local shift = Instance.new("PitchShiftSoundEffect")
			shift.Octave = st.octave
			shift.Parent = bus
		end
		bus.Parent = game:GetService("SoundService")
		music.bus[stage] = bus
	end
	return bus
end

local function dressMusic(m, stage)
	local st = MUSIC_STAGES[stage] or MUSIC_STAGES[1]
	m.Looped, m.PlaybackSpeed = true, st.speed
	m.SoundGroup = musicBus(stage)
end

local function dropMusic(seconds)
	local old = {music.bed}
	for _, h in pairs(music.horns) do old[#old + 1] = h end
	music.bed, music.horns, music.aligned = nil, {}, {}
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
	music.startedAt = os.clock()
end

local function musicTick(dt)
	local bed = music.bed
	if not bed then return end
	-- duck under any line that is playing
	local talking = speaking ~= nil or next(paCopies) ~= nil
	local goal = talking and DUCK or 1
	if workspace:GetAttribute("Level6Party") == true then goal = 0 end      -- the party room has its own music
	music.level += math.clamp(goal - music.level, -dt * 1.6, dt * 0.7)
	bed.Volume = MUSIC_ON_HORNS and 0 or BED_VOLUME * GENERAL * MUSIC * music.level
	local model = workspace:FindFirstChild(MODEL_NAME)
	local props = model and model:FindFirstChild("Props")
	local cam = workspace.CurrentCamera
	local near = {}
	if props and cam and MUSIC_ON_HORNS then
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
			music.aligned[m] = nil
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
			m:Play()
			music.horns[horn] = m
		end
		if m then
			local gain = music.key == "l6_music_reversed" and REVERSED_GAIN or 1
			-- four horns at this level are about as loud as the single quiet track the owner settled on
			m.Volume += math.clamp(HORN_VOLUME * GENERAL * MUSIC * gain * music.level - m.Volume, -dt * 1.2, dt * 0.35)
			local length = m.TimeLength
			if length > 1 then
				local base = (MUSIC_STAGES[music.stage] or MUSIC_STAGES[1]).speed
				local ref = ((os.clock() - music.startedAt) * base) % length
				local off = m.TimePosition - ref
				if off > length / 2 then off -= length elseif off < -length / 2 then off += length end   -- either side of the loop's end
				local now = os.clock()
				if not music.aligned[m] or (math.abs(off) > 0.75 and now - music.aligned[m] > 6) then
					music.aligned[m] = now           -- set once as it comes in, still silent; after that only if far out
					m.TimePosition = ref
					m.PlaybackSpeed = base
				elseif math.abs(off) > 0.09 then
					m.PlaybackSpeed = base * (off > 0 and 0.985 or 1.015)
				elseif math.abs(off) < 0.03 then
					m.PlaybackSpeed = base
				end
			end
		end
	end
end

-- A sound Roblox has not approved (moderation pending or refused) exists as an instance and plays nothing.
-- The effects are checked once in the background; a refused one reports "not there", so its caller's
-- fallback is heard instead of silence.
local refused = {}
task.spawn(function()
	local voice = counter:WaitForChild("Voice", 30)
	if not voice then return end
	for _, key in ipairs({"l6_chase_shriek", "l6_chase_loop", "l6_rage_scream", "l6_rage_loop", "l6_kill_grab", "l6_kill_breath"}) do
		local sound = voice:FindFirstChild(key)
		if sound then
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({sound}, function(_, status)
					if status ~= Enum.AssetFetchStatus.Success then refused[key] = true end
				end)
			end)
		end
	end
end)

local function oneShot(key, volume)
	local voice = counter:FindFirstChild("Voice")
	local source = AUDIO_ENABLED and not refused[key] and voice and voice:FindFirstChild(key)
	if not source then return end
	local o = source:Clone()
	o.Parent = audio
	o.Ended:Once(function() o:Destroy() end)
	o:Play()
	soft(o, volume * GENERAL)
	return true
end

-- footsteps and room tone: looping sounds made for this level (assets/level6-sfx-elevenlabs)
local function loopOn(parent, key, volume, minDistance, maxDistance)
	local voice = counter:FindFirstChild("Voice")
	local source = AUDIO_ENABLED and voice and voice:FindFirstChild(key)
	if not source then return nil end
	local s = source:Clone()
	volume *= (key == "l6_doll_walk" or key == "l6_doll_run") and ENTITY or GENERAL
	s.Name, s.Looped, s.Volume = "L6Loop_" .. key, true, volume
	if minDistance then
		s.RollOffMode, s.RollOffMinDistance, s.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, minDistance, maxDistance
	end
	s.Parent = parent
	return s
end
local function movementTick(on)
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local s = root:FindFirstChild("L6Loop_l6_step_player")
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if on and (plr:GetAttribute(IN_PREVIEW) == true and plr:GetAttribute("Level5VoidRound") ~= true) and speed > 3 and math.abs(v.Y) < 6 then
				s = s or loopOn(root, "l6_step_player", plr == player and 0.3 or 0.5, 8, 70)
				if s then
					s.PlaybackSpeed = math.clamp(speed / 14, 0.75, 1.7)     -- running sounds like running
					if not s.IsPlaying then s:Play() end
				end
			elseif s and s.IsPlaying then
				s:Stop()
			end
		end
	end
	local child = on and childModel()
	local root = child and child:FindFirstChild("Root")
	if root then
		local anim = child:GetAttribute("Anim")
		local want = (anim == "Run_Chase" and "l6_doll_run") or (anim == "Walk_Wander" and "l6_doll_walk") or nil
		for _, key in ipairs({"l6_doll_walk", "l6_doll_run"}) do
			local s = root:FindFirstChild("L6Loop_" .. key)
			if key == want then
				s = s or loopOn(root, key, key == "l6_doll_run" and 1 or 0.8, 14, 170)
				if s and not s.IsPlaying then s:Play() end
			elseif s and s.IsPlaying then
				s:Stop()
			end
		end
	end
	local tone = audio:FindFirstChild("L6Loop_l6_ambience")
	if on then
		tone = tone or loopOn(audio, "l6_ambience", 0.16)
		if tone and not tone.IsPlaying then tone:Play() end
	elseif tone and tone.IsPlaying then
		tone:Stop()
	end
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
	soft(s, level * ENTITY)
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
			soft(pa, 0.5 * ENTITY)
		end
	end
end
local killCam = function() end   -- assigned below, once the doll's rig code exists
local dunked = false
local horror = {chase = false, rage = false}
local ARRIVAL_HINT = "Go in through the gate."
event.OnClientEvent:Connect(function(kind, a, b)
	if kind == "say" then
		say(a)
	elseif kind == "pa" then
		say(a, true)
		if hintLabel.Text == ARRIVAL_HINT then hintLabel.Text = "" end   -- everyone is in: the welcome has begun
	elseif kind == "dunk" or kind == "escaped" then
		if not oneShot("l6_tag", 0.5) then SFX.ping:Play() end
	elseif kind == "chase" then
		if a and not oneShot("l6_chase_shriek", 0.9) then oneShot("l6_sting_spotted", 0.45) end   -- it has seen you
		horror.chase = a == true
	elseif kind == "caught" then
		if b then
			horror.chase = false
			if not oneShot("l6_kill_grab", 1) then oneShot("l6_catch", 0.8) end
			task.delay(1.3, function() oneShot("l6_kill_breath", 0.9) end)
		else
			oneShot("l6_catch", 0.3)
		end
	elseif kind == "won" then
		oneShot("l6_rage_scream", 1)                      -- it lost, and it is not taking it well
		horror.rage = true
	elseif kind == "left" or kind == "lost" or kind == "escaped" or kind == "joined" then
		horror.chase, horror.rage = false, false
	end
end)
-- The beds under a chase and under the finale. They fade in and out; nothing else in the level loops this loud.
task.spawn(function()
	local beds = {chase = {"l6_chase_loop", 0.55 * GENERAL}, rage = {"l6_rage_loop", 0.5 * GENERAL}}
	while true do
		local dt = task.wait(0.05)
		for name, bed in pairs(beds) do
			local s = audio:FindFirstChild("L6Loop_" .. bed[1])
			local want = horror[name] and (player:GetAttribute(IN_PREVIEW) == true and player:GetAttribute("Level5VoidRound") ~= true)
			if want and not s then
				s = loopOn(audio, bed[1], 0)
				if s then s:Play() end
			end
			if s then
				s.Volume += math.clamp((want and bed[2] or 0) - s.Volume, -dt * 0.6, dt * 0.9)
				if not want and s.Volume <= 0.01 then s:Destroy() end
			end
		end
	end
end)
local function touched(count, target)
	local model = workspace:FindFirstChild(MODEL_NAME)
	local wins, needed = model and model:GetAttribute("Level6Wins") or 0, model and model:GetAttribute("Level6WinsNeeded") or 3
	return string.format("TOUCHED %d / %d   ·   ROUNDS %d / %d", count or 0, target or 0, wins, needed)
end
event.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "paused" then
		countLabel.Text, statusLabel.Text, dunkLabel.Text, timerLabel.Text = "", "", "", ""
		hintLabel.Text = "Free roam: hide and seek is paused."
		objective(nil)
	elseif kind == "joined" then
		dunkLabel.Text = touched(b, c)
		hintLabel.Text = ""
		-- joining (or re-entering) while it is already searching: the post marker is the objective right away
		if d == "seek" then
			dunked = false
			markerMode = "post"
			objective("TOUCH THE POST", "Everyone alive must touch the post in the middle, three searches in a row. Do not let it see you.")
		elseif d == "arrival" then
			-- ARENA_20261006: a party arrives in the tunnel, looking straight at the PLAY ZONE sign; the round starts
			-- when they are through the gate. No card here: it sits exactly where the sign is.
			objective(nil)
			hintLabel.Text = ARRIVAL_HINT
		else
			objective("HIDE!", "It is counting. Find a hiding place.")
		end
		-- the music waits for the first count (the welcome plays in quiet); a late joiner gets it straight away
		music.wanted = (a or 0) >= 2 or d == "seek" or d == "between" or d == "escape"
		if d == "seek" then status("It is already looking. HIDE.", 4, Color3.fromRGB(255, 90, 90)) end
	elseif kind == "round" then
		dunked = false
		countLabel.Text = ""
		dunkLabel.Text = touched(b, c)
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
		objective("TOUCH THE POST", "Everyone alive must touch the post in the middle, three searches in a row. Do not let it see you.")
		task.delay(2.2, function() if countLabel.Text == "READY OR NOT . . ." then countLabel.Text = "" end end)
	elseif kind == "party" then
		if a then status("PARTY MODE  ·  30 SECONDS", 5, Color3.fromRGB(255, 64, 176)) else status("Back to hiding.", 3, Color3.fromRGB(255, 90, 90)) end
	elseif kind == "timer" then
		timerLabel.Text = string.format("%d:%02d", a // 60, a % 60)
	elseif kind == "dunk" then
		dunkLabel.Text = touched(b, c)
	elseif kind == "roundwon" then
		-- every living player touched the post in this search: one of the three it takes. The tape winds up a stage.
		status(string.format("EVERYONE TOUCHED THE POST   ·   %d / %d", a or 0, b or 3), 4, Color3.fromRGB(255, 220, 60))
		if (a or 0) < (b or 3) then changeTrack("l6_music", math.min((a or 0) + 1, 3)) end
		if a == player.DisplayName then
			dunked = true
			markerMode = nil
			objective("TAGGED!", "Hide until everyone alive has touched the post.", Color3.fromRGB(120, 255, 150))
		end
		status(string.upper(a) .. " TAGGED THE POST!", 2.5, Color3.fromRGB(120, 255, 150))
	elseif kind == "chase" then
		vignette.ImageTransparency = a and 0.35 or 1
		if a then status("IT SEES YOU. RUN!", 2, Color3.fromRGB(255, 60, 60)) end
	elseif kind == "caught" then
		if b then
			vignette.ImageTransparency = 1
			countLabel.Text = ""
			objective(nil)
			markerMode = nil            -- nothing floats over its face
			killCam()
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
		local arena = workspace:FindFirstChild(MODEL_NAME)
		if arena and arena:GetAttribute("Arena") == true then
			-- ARENA_20261006: the post counts down a minute; the way out is under it when it reaches zero
			markerMode = nil
			objective("STAY ALIVE", "The post is counting down. At zero the way out opens under it.", Color3.fromRGB(255, 70, 60))
		else
			markerMode = "exit"
			objective("RUN TO THE EXIT!", "The red door inside STAFF ONLY. It is angry and fast.", Color3.fromRGB(255, 70, 60))
			timerLabel.Text = ""
		end
	elseif kind == "hatch" then
		markerMode = "exit"
		timerLabel.Text = ""
		status("THE WAY OUT IS OPEN", 5, Color3.fromRGB(110, 255, 150))
		objective("GO DOWN THE HOLE!", "Where the post stood. Slide to the EXIT.", Color3.fromRGB(110, 255, 150))
	elseif kind == "escaped" then
		-- WIN_SCREEN_20261006: the server sends the round's own "win" next, and RoundUI draws LEVEL 6 CLEARED with
		-- its time, survivors and BACK TO LOBBY, as in every level. Nothing of this HUD stays over it.
		vignette.ImageTransparency = 1
		markerMode = nil
		objective(nil)
		countLabel.Text, statusLabel.Text, hintLabel.Text, timerLabel.Text, dunkLabel.Text = "", "", "", "", ""
	elseif kind == "exittaunt" then
		-- TAUNT_20261006 (owner): everyone is down in the room under the court. It screams after them down the
		-- slide, and ends on a sweet little laugh. Heard from the mouth of the tube in the ceiling; the music ducks.
		local model = workspace:FindFirstChild(MODEL_NAME)
		local lights = model and model:FindFirstChild("ExitLights")
		local mouth = lights and lights:FindFirstChild("L6_ExitRoom_Tube")
		local voice = counter:FindFirstChild("Voice")
		local source = AUDIO_ENABLED and voice and (voice:FindFirstChild("l6_exit_taunt") or voice:FindFirstChild("l6_angry_1"))
		if source then
			local o = source:Clone()
			o.Name = "Level6ExitTaunt"
			o.Looped, o.PlaybackSpeed = false, 1
			o.RollOffMode, o.RollOffMinDistance, o.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 45, 300
			local echo = Instance.new("ReverbSoundEffect")
			echo.DecayTime, echo.Density, echo.Diffusion, echo.DryLevel, echo.WetLevel = 2.4, 0.8, 0.8, 0, -8
			echo.Parent = o
			o.Parent = mouth or audio
			paCopies[o] = true
			o.Ended:Once(function() paCopies[o] = nil; o:Destroy() end)
			task.delay(40, function() paCopies[o] = nil; if o.Parent then o:Destroy() end end)
			o:Play()
			soft(o, 2.0 * ENTITY)
		end
	elseif kind == "lost" then
		countLabel.Text = horror.killing and "" or "EVERYONE WAS FOUND"
		markerMode = nil
		objective(nil)
		timerLabel.Text = ""
	elseif kind == "left" then
		vignette.ImageTransparency = 1
		task.delay(3, function()
			if (player:GetAttribute(IN_PREVIEW) ~= true or player:GetAttribute("Level5VoidRound") == true) then
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
-- ARENA_20261006: measured in play against the concept pictures. At the hall's old exposure the frame was a
-- flat bright toy; at -0.45 the roof goes dark and the lamps read as lamps. The grade takes the primary colours
-- down to worn vinyl and lifts the blacks into dusty air; the level's own fill lights (L6_Fill_*) keep the
-- upper galleries from going black.
local ARENA_LOOK = {ExposureCompensation = -0.45, Contrast = -0.1, Saturation = -0.3, Brightness = -0.02,
	Tint = Color3.fromRGB(244, 240, 226),
	-- the last minute: every lamp red and none of them weaker, the colour back in, the picture a little up
	-- (red light on blue and green vinyl gives almost nothing back, so the same lamps read far darker in red)
	FinaleExposure = 0.15, FinaleSaturation = 0.3, FinaleContrast = 0.16, FinaleFill = 5,
	Red = Color3.fromRGB(255, 56, 40)}
local HALL_TINT = Color3.fromRGB(238, 245, 255)
local function isArena()
	local model = workspace:FindFirstChild(MODEL_NAME)
	return model ~= nil and model:GetAttribute("Arena") == true
end
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
		grade.TintColor = HALL_TINT
		if isArena() then
			grade.Saturation, grade.Contrast, grade.Brightness = ARENA_LOOK.Saturation, ARENA_LOOK.Contrast, ARENA_LOOK.Brightness
			grade.TintColor = ARENA_LOOK.Tint
		end
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
		local arena = isArena()
		for k, v in pairs(LOOK) do
			if k == "ExposureCompensation" and arena then v = ARENA_LOOK.ExposureCompensation end
			if not (k == "ExposureCompensation" and finale > 0) then Lighting[k] = v end
		end
		-- other controllers put the lobby's Atmosphere back; with a black sky it swallows the whole hall
		for _, a in ipairs(Lighting:GetChildren()) do
			if a:IsA("Atmosphere") and a.Density ~= 0 then a.Density = 0 end
		end
	end
end

local function inside()
	return (player:GetAttribute(IN_PREVIEW) == true and player:GetAttribute("Level5VoidRound") ~= true)
end

-- marker, music and the red finale
-- not a pure red: pure red light turns the blue and green floor black
local RED = Color3.fromRGB(255, 40, 28)
-- light or lamp -> {colour, brightness, angle}. A STRONG table on purpose: with weak keys an entry is dropped as soon
-- as Lua holds no other reference to the Instance, even though the Instance is still in the level. The next tick
-- then saved the lamp's already-changed brightness as its "before" and scaled that, again and again: in the arena
-- the fill lights ran away to 200 000 (a white screen) and every other lamp sank to nothing. Cleared by hand below.
local litBefore = {}
local FINALE_FOLDERS = {"Lights", "Ceiling_Fixtures", "Frame_Lamps", "PartyRooms", "StaffOnly", "SnackShack"}
local exitLamp = {bulb = nil, base = 0, dipUntil = 0, nextDip = 0}
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(0.1)
		local now = os.clock()
		local dt = now - last
		last = now
		local model = workspace:FindFirstChild(MODEL_NAME)
		local on = model ~= nil and (player:GetAttribute(IN_PREVIEW) == true and player:GetAttribute("Level5VoidRound") ~= true)
		local target = on and markerMode and model:GetAttribute(markerMode == "post" and "HomePosition" or "ExitPosition")
		local lift = markerMode == "post" and 16 or 9
		-- ARENA_20261006: once you are down the hole, the way out is the green door at the end of the room under the court
		local door = target and markerMode ~= "post" and model:GetAttribute("ExitDoorPosition")
		if door then
			local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if body and body.Position.Y < target.Y - 12 then
				target, lift = door, 5
				if cardTitle.Text == "GO DOWN THE HOLE!" then
					objective("EXIT", "Through the green door.", Color3.fromRGB(110, 255, 150))
				end
			end
		end
		if target then
			markerPart.Position = target + Vector3.new(0, lift, 0)
			markerPart.Parent = workspace
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local dist = root and (root.Position - target).Magnitude or 200
			local px = math.clamp(250 - dist * 0.85, 80, 250)      -- grows as you get close
			marker.Size = UDim2.fromOffset(px, px)
			markerText.Text = (markerMode == "post" and "TOUCH" or "EXIT") .. "  " .. math.floor(dist / 3.6 + 0.5) .. " m"
			markerRing.BackgroundColor3 = markerMode == "post" and Color3.fromRGB(255, 215, 40)
				or (model:GetAttribute("Arena") == true and Color3.fromRGB(90, 255, 140) or Color3.fromRGB(255, 70, 60))
			marker.Enabled = true
		else
			marker.Enabled = false
			markerPart.Parent = nil
		end

		-- ARENA_20261006: the one lamp in the room under the court is on its last legs: it dips for a moment every
		-- few seconds (never with ReduceFlashing)
		local exitLights = on and model:FindFirstChild("ExitLights")
		local exitLampPart = exitLights and exitLights:FindFirstChild("L6_ExitRoom_Lamp")
		local bulb = exitLampPart and exitLampPart:FindFirstChildWhichIsA("Light")
		if bulb then
			if exitLamp.bulb ~= bulb then exitLamp.bulb, exitLamp.base = bulb, bulb.Brightness end
			if player:GetAttribute("ReduceFlashing") == true then
				bulb.Brightness = exitLamp.base
			else
				if now > exitLamp.nextDip then
					exitLamp.dipUntil = now + 0.12 + math.random() * 0.25
					exitLamp.nextDip = now + 2.5 + math.random() * 6
				end
				bulb.Brightness = exitLamp.base * (now < exitLamp.dipUntil and 0.35 or (0.94 + 0.06 * math.noise(now * 3)))
			end
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
		movementTick(on)

		-- the red finale: no red wash over the picture. The hall goes dark and only the ceiling fixtures stay on,
		-- as tight red spotlights; every other lamp fades out. Eases in over about four seconds.
		finale = math.clamp(finale + (enraged and dt / 4 or -dt / 2), 0, 1)
		if model and (finale > 0 or next(litBefore)) then
			local ease = finale * finale * (3 - 2 * finale)
			-- Owner, 2026-10-04: the red comes and goes. It swells up, fades out, and the hall is dark for a moment
			-- before the next swell (about a quarter of each 3.6 s cycle). With ReduceFlashing it only dips halfway.
			local swell = math.clamp((math.sin(os.clock() * 2 * math.pi / 3.6) + 0.75) / 1.75, 0, 1)
			swell = swell * swell * (3 - 2 * swell)
			if player:GetAttribute("ReduceFlashing") == true then swell = 0.5 + 0.5 * swell end
			local pulsedRed = Color3.fromRGB(20, 6, 5):Lerp(RED, swell)
			for _, folderName in ipairs(FINALE_FOLDERS) do
				local folder = model:FindFirstChild(folderName)
				if folder then
					for _, d in ipairs(folder:GetDescendants()) do
						local isLight = d:IsA("Light")
						if isLight or (d:IsA("BasePart") and d.Material == Enum.Material.Neon) then
							local before = litBefore[d]
							if finale > 0 then
								if before == nil then
									before = {d.Color, isLight and d.Brightness or 0, d:IsA("SpotLight") and d.Angle or 0}
									litBefore[d] = before
								end
								if isLight and model:GetAttribute("Arena") == true then
									-- ARENA_20261006: the arena's lamps are its gallery lights: they keep their spread, turn red and
									-- swell from almost nothing to well over their own strength (the owner's pulse: red, then dark
									-- for a moment). The fill lights in the open well come up with them, so at the top of each
									-- swell the whole wall of galleries stands in red.
									local fill = d.Parent.Name:sub(1, 8) == "L6_Fill_" and ARENA_LOOK.FinaleFill or 1
									d.Color = before[1]:Lerp(ARENA_LOOK.Red, ease)
									d.Brightness = before[2] * (1 - ease) + before[2] * fill * (0.12 + 1.25 * swell) * ease
								elseif model:GetAttribute("Arena") == true then
									d.Color = before[1]:Lerp(pulsedRed, ease)  -- every tube in the frame glows red with its light
								elseif d:IsA("SpotLight") then          -- the ceiling fixtures: red cones straight down
									d.Color = before[1]:Lerp(RED, ease)
									d.Angle = before[3] + (85 - before[3]) * ease
									-- low on purpose: the yellow and red padding reflects red far more than the floor does
									d.Brightness = before[2] + (0.2 * swell - before[2]) * ease
								elseif isLight then                     -- room and bar lights go out
									d.Brightness = before[2] * (1 - ease)
								elseif folderName == "Ceiling_Fixtures" then
									d.Color = before[1]:Lerp(pulsedRed, ease)  -- the tubes themselves glow red, and go dark with the light
								else
									d.Color = before[1]:Lerp(Color3.fromRGB(25, 22, 20), ease)
								end
							elseif before ~= nil then
								d.Color = before[1]
								if isLight then d.Brightness = before[2] end
								if d:IsA("SpotLight") then d.Angle = before[3] end
								litBefore[d] = nil
							end
						end
					end
				end
			end
			if finale <= 0 then table.clear(litBefore) end     -- everything still in the level was put back above
			local arena = model:GetAttribute("Arena") == true
			if grade then
				grade.TintColor = arena and ARENA_LOOK.Tint or HALL_TINT   -- never tinted red: the red comes from the lamps only
				-- the grey haze goes, so the dark between the pools is dark
				grade.Contrast = (arena and ARENA_LOOK.Contrast or -0.17) + (arena and ARENA_LOOK.FinaleContrast or 0.22) * ease
				grade.Saturation = arena and ARENA_LOOK.Saturation + ARENA_LOOK.FinaleSaturation * ease or 0.08
			end
			Lighting.ExposureCompensation = (arena and ARENA_LOOK.ExposureCompensation or LOOK.ExposureCompensation)
				+ (arena and ARENA_LOOK.FinaleExposure or -0.2) * ease
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
	-- ARENA_20261006: the way out under the post carries its own direction and pace on every stretch (L6SlideDir,
	-- L6SlideSpeed), so it takes you round the spiral at one speed, eases off over the last turn and lets you out
	-- at a walk, whatever the slope under you is. The funnel above it only sets a pace.
	local way = hit and hit.Instance:GetAttribute("L6SlideDir")
	local slide = hit and hit.Instance:GetAttribute("L6Slide") == true
		and (way ~= nil or (hit.Normal.Y < 0.985 and hit.Normal.Y > 0.2))
	if slide then
		local n = hit.Normal
		local downhill = way or (Vector3.new(0, -1, 0) + n * n.Y).Unit
		local v = root.AssemblyLinearVelocity
		local pace = hit.Instance:GetAttribute("L6SlideSpeed")
		if pace then
			local along = v:Dot(downhill)
			local speed = along > pace and math.max(pace, along - 60 * dt) or math.min(pace, math.max(along, 10) + 55 * dt)
			root.AssemblyLinearVelocity = downhill * speed
		else
			local along = math.max(v:Dot(downhill), 26)
			root.AssemblyLinearVelocity = downhill * math.min(along + 55 * dt, 62)
		end
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
local STRIDE = {Walk_Wander = 7.1, Run_Chase = 16}
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

-- Kill cam (KILL_CHOKE_20261004, owner: "it grabs the person, chokes them and brings them closer to the face
-- until it goes black and that is when the player dies"). The doll plays `Choke` (tools/level6_entity/
-- build_choke.py): both hands shoot out to the throat, it lifts, then folds its arms and leans in. The victim's
-- camera HANGS ON THE TWO HAND BONES, just above and behind them, looking at its face - so the hands are at the
-- bottom of the view the whole time and the pull toward the face is the doll's own arms. Sight goes in pulses
-- and then for good; the screen is black before the server kills the body (`CaughtReturnDelay`).
killCam = function()
	local child = childModel()
	local rig = child and rigOf(child)
	local dollRoot = child and child:FindFirstChild("Root")
	local cam = workspace.CurrentCamera
	local cover = Instance.new("ScreenGui")
	cover.Name, cover.IgnoreGuiInset, cover.ResetOnSpawn, cover.DisplayOrder = "Level6KillCover", true, false, 900
	local black = Instance.new("Frame")
	black.Name, black.Size, black.BorderSizePixel = "KillBlack", UDim2.fromScale(1, 1), 0
	black.BackgroundColor3, black.BackgroundTransparency, black.ZIndex = Color3.new(0, 0, 0), 1, 60
	black.Parent = cover
	cover.Parent = player:WaitForChild("PlayerGui")
	local function blackout()
		black.BackgroundTransparency = 0
		task.spawn(function()
			-- Dead in the level now, not sent home: the cover holds until the spectate view (or the lobby,
			-- for a player who left) owns the screen, and the spectate controller owns the camera from there.
			local t0 = os.clock()
			while (player:GetAttribute(IN_PREVIEW) == true and player:GetAttribute("Level5VoidRound") ~= true) and player:GetAttribute("Spectating") ~= true
				and os.clock() - t0 < 2.5 do task.wait(0.1) end
			task.wait(0.4)
			if player:GetAttribute("Spectating") ~= true then cam.CameraType = Enum.CameraType.Custom end
			pulse(black, "BackgroundTransparency", 0, 1, 1.2)
			task.wait(1.3)
			cover:Destroy()
		end)
	end
	local left, right = rig and rig.bones.LeftHand, rig and rig.bones.RightHand
	if not (rig and dollRoot and cam and left and right) then
		pulse(flash, "BackgroundTransparency", 0, 1, 0.5)
		task.delay(4.2, blackout)
		return
	end
	local DURATION, GRAB, DARK_FROM, DARK_FULL = 4.9, 0.32, 3.0, 4.7
	-- nothing on screen but the doll: the level HUD and the flashlight gauge come back with the lobby
	horror.killing = true
	local shown = {}
	for _, item in ipairs(gui:GetChildren()) do
		if item:IsA("GuiObject") and item ~= flash and item.Visible then
			shown[item] = true
			item.Visible = false
		end
	end
	local gauge = player.PlayerGui:FindFirstChild("FlashlightPopup")
	if gauge then gauge.Enabled = false end
	task.delay(DURATION + 6, function()
		horror.killing = false
		countLabel.Text = ""
		objective(nil)
		for item in pairs(shown) do
			if item ~= card then item.Visible = true end
		end
	end)
	local startCF, startFov = cam.CFrame, cam.FieldOfView
	local calm = player:GetAttribute("ReduceCameraShake") == true
	local steady = player:GetAttribute("ReduceFlashing") == true
	cam.CameraType = Enum.CameraType.Scriptable
	pulse(flash, "BackgroundTransparency", 0.35, 1, 0.5)   -- the hit
	local t0 = os.clock()
	local hushed = {}
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		-- the exit chip and the REC frame belong to other scripts that keep switching themselves on: off, every frame
		local done = t >= DURATION or not child.Parent
		for _, name in ipairs({"RoundExitGui", "FoundFootageHUD"}) do
			local other = player.PlayerGui:FindFirstChild(name)
			if other and other:IsA("ScreenGui") then
				if not done then
					if other.Enabled then other.Enabled = false; hushed[other] = true end
				elseif hushed[other] then
					other.Enabled = true
				end
			end
		end
		if done then
			connection:Disconnect()
			cam.FieldOfView = startFov
			blackout()
			return
		end
		-- a Scriptable camera un-hides the first-person body, and the camera starts inside it
		local own = player.Character
		if own then
			for _, part in ipairs(own:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("Decal") then part.LocalTransparencyModifier = 1 end
			end
		end
		local face = rig.bones.Head.TransformedWorldCFrame.Position + Vector3.new(0, 0.22, 0)   -- its eyes, not its chin
		local hands = (left.TransformedWorldCFrame.Position + right.TransformedWorldCFrame.Position) / 2
		local toward = dollRoot.CFrame.LookVector                   -- from the doll to its victim
		local pull = math.clamp((t - 1.6) / 2.8, 0, 1)
		-- the eyes sit above the throat it is holding, a little behind the hands; less behind as it draws them in
		local eye = hands + Vector3.new(0, 0.62, 0) + toward * (1.0 - 0.6 * pull)
		local grab = math.clamp(t / GRAB, 0, 1)
		grab = 1 - (1 - grab) * (1 - grab)
		local position = startCF.Position:Lerp(eye, grab)
		local tremble = (0.02 + 0.05 * pull) * (calm and 0.2 or 1)
		position += Vector3.new(math.noise(t * 17, 0.5) * tremble, math.noise(0.5, t * 19) * tremble, 0)
		-- the head is forced back and rolls as the air goes
		local aim = CFrame.lookAt(position, face + Vector3.new(0, -0.25 * (1 - pull), 0))
			* CFrame.Angles(0, 0, math.rad((calm and 1.5 or 5) * math.sin(t * 2.3) * (0.3 + 0.7 * pull)))
		cam.CFrame = CFrame.new(position) * startCF.Rotation:Lerp(aim.Rotation, grab)
		cam.FieldOfView = startFov + (78 - startFov) * grab + (62 - 78) * pull
		-- sight: it dims on every heartbeat, a little more each time, and then does not come back
		local dark = math.clamp((t - DARK_FROM) / (DARK_FULL - DARK_FROM), 0, 1)
		dark = dark * dark * (3 - 2 * dark)
		local beat = steady and 0 or math.max(0, math.sin(t * 7.2)) ^ 3 * 0.28 * math.clamp((t - 0.8) / 1.2, 0, 1)
		black.BackgroundTransparency = 1 - math.clamp(dark + beat * (1 - dark), 0, 1)
	end)
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
