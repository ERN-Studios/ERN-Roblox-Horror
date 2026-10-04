-- Lobby DJ Client (2026-10-04). Two jobs.
--   EVERYONE: plays the track the booth has on (workspace.LobbyDJTrack), in step with the server's start time,
--   only in the lobby and only while the player's own lobby music setting is on; the ordinary lobby track is
--   held silent meanwhile. A small line names the DJ and the track when it changes.
--   THE TEAM (DevAccess.IsLevel6PreviewAllowed): E at the console opens the booth: five tracks, STOP, and DJ MODE
--   (headset on, hands on the decks). For everyone else the prompt is switched off locally; the server refuses
--   their requests in any case.
-- This script took over the retired, disabled `Level 6 Table Hiding Client`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("LobbyDJ", 60)
if not remote then return end
local accessModule = ReplicatedStorage:WaitForChild("DevAccess", 10)
local okAccess, team = pcall(function() return accessModule ~= nil and require(accessModule).IsLevel6PreviewAllowed(player) end)
team = okAccess and team == true
local VOLUME = 0.38
local MAGENTA, CYAN, INK, PAPER = Color3.fromRGB(255, 64, 176), Color3.fromRGB(70, 230, 255), Color3.fromRGB(16, 10, 30), Color3.fromRGB(244, 240, 255)

local function tracks()
	local ok, list = pcall(function() return HttpService:JSONDecode(workspace:GetAttribute("LobbyDJTracks")) end)
	return ok and type(list) == "table" and list or {}
end

-- the sound ----------------------------------------------------------------------------------------------
local sound = Instance.new("Sound")
sound.Name = "LobbyDJTrack"
sound.Looped, sound.Volume = true, 0
sound.Parent = SoundService
local ducked = false
local function eligible()
	return workspace:GetAttribute("ReservedRoundServer") ~= true and player:GetAttribute("InRound") ~= true
		and player:GetAttribute("LobbyMusicEnabled") == true
end
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyDJ"
gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = false, false, 30
gui.Parent = player:WaitForChild("PlayerGui")
local toast = Instance.new("TextLabel")
toast.Name = "NowPlaying"
toast.AnchorPoint, toast.Position, toast.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -18), UDim2.new(0, 460, 0, 26)
toast.BackgroundTransparency, toast.Font, toast.TextSize = 1, Enum.Font.GothamMedium, 16
toast.TextColor3, toast.TextTransparency, toast.TextStrokeTransparency = PAPER, 1, 1
toast.Parent = gui
local toastToken = 0
local function announce(text)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	TweenService:Create(toast, TweenInfo.new(0.3), {TextTransparency = 0, TextStrokeTransparency = 0.6}):Play()
	task.delay(4.5, function()
		if token == toastToken then TweenService:Create(toast, TweenInfo.new(0.8), {TextTransparency = 1, TextStrokeTransparency = 1}):Play() end
	end)
end
local refreshPanel = function() end
local lastTrack = 0
local function applyTrack()
	local index = workspace:GetAttribute("LobbyDJTrack") or 0
	local entry = tracks()[index]
	local on = entry ~= nil and entry.Id ~= 0 and eligible()
	local group = SoundService:FindFirstChild("ZyntraLobbyMusic")
	if on then
		local id = "rbxassetid://" .. string.format("%.0f", entry.Id)
		if sound.SoundId ~= id then
			sound.SoundId = id
			sound.TimePosition = 0
		end
		if not sound.IsPlaying then sound:Play() end
		task.spawn(function()                                           -- fall in step with everyone else once it has loaded
			if not sound.IsLoaded then sound.Loaded:Wait() end
			local started = workspace:GetAttribute("LobbyDJStartedAt")
			if sound.SoundId == id and type(started) == "number" and sound.TimeLength > 1 then
				sound.TimePosition = (workspace:GetServerTimeNow() - started) % sound.TimeLength
			end
		end)
		TweenService:Create(sound, TweenInfo.new(0.6), {Volume = VOLUME}):Play()
		if group and group:IsA("SoundGroup") then group.Volume = 0; ducked = true end
	else
		TweenService:Create(sound, TweenInfo.new(0.5), {Volume = 0}):Play()
		task.delay(0.55, function()
			if sound.Volume < 0.01 then sound:Stop() end
		end)
		if ducked and group and group:IsA("SoundGroup") and player:GetAttribute("Level6PlaygroundPreview") ~= true then group.Volume = 1 end
		ducked = false
	end
	if index ~= lastTrack then
		lastTrack = index
		if entry and eligible() then announce(("♪  %s  ·  %s"):format(tostring(workspace:GetAttribute("LobbyDJBy") or "DJ"), entry.Title)) end
	end
	refreshPanel()
end
for _, name in ipairs({"LobbyDJTrack", "LobbyDJStartedAt", "LobbyDJTracks"}) do workspace:GetAttributeChangedSignal(name):Connect(applyTrack) end
for _, name in ipairs({"InRound", "LobbyMusicEnabled"}) do player:GetAttributeChangedSignal(name):Connect(applyTrack) end
task.defer(applyTrack)

-- party lights ------------------------------------------------------------------------------------------------
-- PARTY_LIGHTS_20261004 (owner): while a track is on, the lobby's own lamps go to party mode, in time with it.
-- Every Light in the lobby model takes a colour from the track's palette (synthwave: magenta, cyan, violet;
-- eurodance adds yellow, green and red), neighbours get different ones, and the whole pattern steps on every
-- second beat of the track's tempo, counted from the server's start time so all clients agree. Brightness swells
-- gently on the beat. Colours glide (no hard cuts: at most about 1.2 changes a second), and with ReduceFlashing
-- the pattern steps once every eight beats with no pulse. Stopping the music puts every lamp back exactly.
do
	local RunService = game:GetService("RunService")
	local PALETTES = {
		SYNTHWAVE = {Color3.fromRGB(255, 64, 176), Color3.fromRGB(70, 230, 255), Color3.fromRGB(150, 90, 255), Color3.fromRGB(255, 120, 60)},
		EURODANCE = {Color3.fromRGB(255, 64, 176), Color3.fromRGB(70, 230, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(90, 255, 130),
			Color3.fromRGB(255, 70, 70), Color3.fromRGB(150, 90, 255)},
	}
	local lamps, lampsFor = nil, nil
	local function collect()
		local lobby = workspace:FindFirstChild("LobbyReimaginedPreview")
		if not lobby or lobby:GetAttribute("Ready") ~= true then return nil end
		if lamps and lampsFor == lobby then return lamps end
		lamps, lampsFor = {}, lobby
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Light") and d.Enabled and d.Brightness > 0 then
				local host = d.Parent
				local at = host and host:IsA("BasePart") and host.Position or (host and host:IsA("Attachment") and host.WorldPosition) or Vector3.zero
				table.insert(lamps, {light = d, colour = d.Color, brightness = d.Brightness,
					slot = math.floor(at.Z / 22) + math.floor(at.X / 30) * 3})
			end
		end
		return lamps
	end
	local function restore()
		for _, lamp in ipairs(lamps or {}) do
			if lamp.light.Parent then lamp.light.Color, lamp.light.Brightness = lamp.colour, lamp.brightness end
		end
		lamps, lampsFor = nil, nil
	end
	local active, elapsed = false, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 / 20 then return end
		elapsed = 0
		local entry = tracks()[workspace:GetAttribute("LobbyDJTrack") or 0]
		local on = entry ~= nil and workspace:GetAttribute("ReservedRoundServer") ~= true and player:GetAttribute("InRound") ~= true
		if not on then
			if active then active = false; restore() end
			return
		end
		local list = collect()
		if not list then return end
		active = true
		local calm = player:GetAttribute("ReduceFlashing") == true
		local palette = PALETTES[entry.Genre] or PALETTES.SYNTHWAVE
		local beats = (workspace:GetServerTimeNow() - (workspace:GetAttribute("LobbyDJStartedAt") or 0)) * (entry.Bpm or 110) / 60
		local stride = calm and 8 or 2                               -- beats per colour step
		local step, within = math.floor(beats / stride), (beats / stride) % 1
		local glide = math.clamp(within / 0.35, 0, 1)                 -- the first third of a step is the change
		local pulse = calm and 1 or 0.86 + 0.24 * (0.5 + 0.5 * math.cos((beats % 1) * math.pi * 2))
		for _, lamp in ipairs(list) do
			local light = lamp.light
			if light.Parent then
				local from = palette[(lamp.slot + step - 1) % #palette + 1]
				local to = palette[(lamp.slot + step) % #palette + 1]
				light.Color = from:Lerp(to, glide)
				light.Brightness = lamp.brightness * pulse
			end
		end
	end)
end

-- the DJ's hands ----------------------------------------------------------------------------------------------
-- Whoever is marked LobbyDJMode is posed here, on every client: arms out over the decks, the right hand
-- scratching in bursts, the left riding a fader, the head nodding. There are no animation assets. Each frame,
-- after the Animate script has written the joints and before physics reads them (RunService.Stepped), each limb
-- joint's Transform is turned a little further. Motor6D (older rigs) and AnimationConstraint (current avatars)
-- both have Transform, and the animator rewrites it every frame, so there is nothing to put back afterwards.
-- What did NOT work on 2026-10-04: a server-side C0/attachment change (replicates, does not move a limb the
-- client owns), Attachment0 or Attachment1 of an AnimationConstraint (the rig is kinematic), PreAnimation.
do
	local RunService = game:GetService("RunService")
	local posed = setmetatable({}, {__mode = "k"})        -- character -> {joints, started}
	local NAMES = {rightShoulder = {"RightShoulder", "Right Shoulder"}, leftShoulder = {"LeftShoulder", "Left Shoulder"},
		rightElbow = {"RightElbow"}, leftElbow = {"LeftElbow"}, neck = {"Neck"}, waist = {"Waist"}}
	local function find(character, names)
		for _, name in ipairs(names) do
			for _, found in ipairs(character:GetDescendants()) do
				if found.Name == name and (found:IsA("Motor6D") or found:IsA("AnimationConstraint")) then return found end
			end
		end
	end
	RunService.Stepped:Connect(function()
		for _, other in ipairs(Players:GetPlayers()) do
			local character = other.Character
			if not character or other:GetAttribute("LobbyDJMode") ~= true then
				if character then posed[character] = nil end
				continue
			end
			local state = posed[character]
			if not state then
				state = {started = os.clock(), r6 = character:FindFirstChild("UpperTorso") == nil}
				for key, names in pairs(NAMES) do state[key] = find(character, names) end
				posed[character] = state
			end
			local t = os.clock() - state.started
			local beat = t * math.pi * 2 * 2
			local scratch = math.sin(t * 9) * (math.sin(t * 0.9) > 0.2 and 1 or 0.15)
			local slide = math.sin(t * 1.3)
			local function pose(key, turn)
				local found = state[key]
				if found and found.Parent then found.Transform = found.Transform * turn end
			end
			if state.r6 then
				pose("rightShoulder", CFrame.Angles(0, 0, math.rad(62 + scratch * 9)))
				pose("leftShoulder", CFrame.Angles(0, 0, math.rad(-58 - slide * 7)))
				pose("neck", CFrame.Angles(math.rad(8 + math.sin(beat) * 6), 0, 0))
			else
				pose("rightShoulder", CFrame.Angles(math.rad(60 + scratch * 5), math.rad(-scratch * 10), math.rad(-6)))
				pose("leftShoulder", CFrame.Angles(math.rad(56), math.rad(slide * 8), math.rad(6 + slide * 5)))
				pose("rightElbow", CFrame.Angles(math.rad(24 + scratch * 8), 0, 0))
				pose("leftElbow", CFrame.Angles(math.rad(28), 0, 0))
				pose("neck", CFrame.Angles(math.rad(-6 - math.sin(beat) * 6), math.rad(math.sin(t * 0.7) * 10), 0))
				pose("waist", CFrame.Angles(math.rad(-6 - math.sin(beat) * 2), 0, 0))
			end
		end
	end)
end

-- the prompt: the team only ------------------------------------------------------------------------------
local function watchPrompt(instance)
	if instance.Name ~= "LobbyDJPrompt" or not instance:IsA("ProximityPrompt") or team then return end
	instance.Enabled = false
	instance:GetPropertyChangedSignal("Enabled"):Connect(function()
		if instance.Enabled then instance.Enabled = false end
	end)
end
workspace.DescendantAdded:Connect(watchPrompt)
for _, d in ipairs(workspace:GetDescendants()) do watchPrompt(d) end
if not team then return end

-- the booth ------------------------------------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.Name = "Booth"
panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(420, 430)
panel.BackgroundColor3, panel.BackgroundTransparency, panel.BorderSizePixel = INK, 0.04, 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local edge = Instance.new("UIStroke", panel)
edge.Color, edge.Thickness = MAGENTA, 2
local scale = Instance.new("UIScale", panel)
local function fit()
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min((view.X - 24) / 420, (view.Y - 24) / 430), 0.55, 1.25)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
local function label(parent, text, size, colour, position, dimensions, font)
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency, item.Text, item.TextSize, item.TextColor3 = 1, text, size, colour
	item.Font = font or Enum.Font.GothamBold
	item.Position, item.Size = position, dimensions
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end
local function button(parent, name, text, position, dimensions, colour)
	local item = Instance.new("TextButton")
	item.Name, item.Text, item.TextSize, item.Font = name, text, 15, Enum.Font.GothamBold
	item.TextColor3, item.BackgroundColor3, item.AutoButtonColor = PAPER, colour, true
	item.Position, item.Size, item.BorderSizePixel = position, dimensions, 0
	item.Parent = parent
	Instance.new("UICorner", item).CornerRadius = UDim.new(0, 8)
	return item
end
label(panel, "DJ BOOTH", 26, PAPER, UDim2.fromOffset(22, 14), UDim2.fromOffset(260, 32), Enum.Font.GothamBlack)
label(panel, "LOBBY  ·  EVERYONE HEARS THIS", 12, CYAN, UDim2.fromOffset(22, 46), UDim2.fromOffset(300, 16), Enum.Font.Code)
local close = button(panel, "Close", "×", UDim2.new(1, -52, 0, 12), UDim2.fromOffset(40, 40), Color3.fromRGB(46, 28, 74))
close.TextSize = 24
-- TRACK_LIST_20261004: a scrolling list with one row per track the server publishes (it was five fixed rows)
local rows = {}
local trackList = Instance.new("ScrollingFrame")
trackList.Name = "Tracks"
trackList.Position, trackList.Size = UDim2.fromOffset(18, 74), UDim2.new(1, -30, 0, 258)
trackList.BackgroundTransparency, trackList.BorderSizePixel = 1, 0
trackList.ScrollBarThickness, trackList.ScrollBarImageColor3 = 6, CYAN
trackList.ScrollingDirection = Enum.ScrollingDirection.Y
trackList.CanvasSize = UDim2.new()
trackList.Parent = panel
local function trackRow(index)
	local row = Instance.new("Frame")
	row.Name = "Track" .. index
	row.Position, row.Size = UDim2.fromOffset(2, 2 + (index - 1) * 52), UDim2.new(1, -16, 0, 46)
	row.BackgroundColor3, row.BorderSizePixel = Color3.fromRGB(30, 18, 54), 0
	row.Parent = trackList
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", row)
	stroke.Color, stroke.Thickness, stroke.Transparency = CYAN, 1.5, 1
	local title = label(row, "", 16, PAPER, UDim2.fromOffset(14, 5), UDim2.new(1, -120, 0, 20))
	local genre = label(row, "", 11, CYAN, UDim2.fromOffset(14, 26), UDim2.new(1, -120, 0, 14), Enum.Font.Code)
	local play = button(row, "Play", "PLAY", UDim2.new(1, -98, 0, 7), UDim2.fromOffset(88, 32), Color3.fromRGB(176, 40, 124))
	play.Activated:Connect(function() remote:FireServer("play", index) end)
	rows[index] = {title = title, genre = genre, play = play, stroke = stroke}
end
local stop = button(panel, "Stop", "STOP MUSIC", UDim2.fromOffset(18, 342), UDim2.new(0.5, -24, 0, 44), Color3.fromRGB(58, 36, 92))
local mode = button(panel, "DJMode", "DJ MODE", UDim2.new(0.5, 6, 0, 342), UDim2.new(0.5, -24, 0, 44), Color3.fromRGB(24, 120, 150))
local hint = label(panel, "DJ MODE: headset on, hands on the decks. Press it again to step away.", 12, Color3.fromRGB(190, 180, 220),
	UDim2.fromOffset(22, 394), UDim2.new(1, -44, 0, 30), Enum.Font.Gotham)
hint.TextWrapped = true
stop.Activated:Connect(function() remote:FireServer("stop") end)
mode.Activated:Connect(function() remote:FireServer("dj", player:GetAttribute("LobbyDJMode") ~= true) end)
refreshPanel = function()
	local list, current = tracks(), workspace:GetAttribute("LobbyDJTrack") or 0
	for index = #rows + 1, #list do trackRow(index) end
	trackList.CanvasSize = UDim2.fromOffset(0, #list * 52 + 2)
	for index, row in ipairs(rows) do
		local entry = list[index]
		row.title.Text = entry and entry.Title or "—"
		row.genre.Text = entry and (entry.Genre .. (entry.Id == 0 and "  ·  NOT UPLOADED" or "")) or ""
		row.play.Text = current == index and "PLAYING" or "PLAY"
		row.play.BackgroundColor3 = current == index and Color3.fromRGB(24, 120, 150) or Color3.fromRGB(176, 40, 124)
		row.stroke.Transparency = current == index and 0 or 1
	end
	local on = player:GetAttribute("LobbyDJMode") == true
	mode.Text = on and "LEAVE THE DECKS" or "DJ MODE"
	mode.BackgroundColor3 = on and Color3.fromRGB(176, 40, 124) or Color3.fromRGB(24, 120, 150)
end
player:GetAttributeChangedSignal("LobbyDJMode"):Connect(refreshPanel)
local function show(open)
	panel.Visible = open
	player:SetAttribute("LobbyDJOpen", open or nil)
	if open then refreshPanel() end
end
close.Activated:Connect(function() show(false) end)
remote.OnClientEvent:Connect(function(what)
	if what == "open" then show(not panel.Visible) end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if panel.Visible and not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then show(false) end
end)
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") == true then show(false) end
end)
