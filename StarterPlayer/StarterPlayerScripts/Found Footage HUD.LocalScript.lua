-- Found Footage HUD -- B6, owner 2026-10-08; Figma via Framewisp (Codex continuation 2026-10-09).
-- This client only renders the engine's visible prompts and the round recording frame.
-- CAMCORDER_20261010: and, in the block at the end, the camcorder look that goes with that frame.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local Hud = require(RS:WaitForChild("RoundHud"))
local Binder = require(RS:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local P = Binder.Palette

local frameGui = Instance.new("ScreenGui")
frameGui.Name = "FoundFootageHUD"
frameGui.ResetOnSpawn = false
frameGui.ScreenInsets = Enum.ScreenInsets.None
frameGui.DisplayOrder = 12
frameGui.Enabled = false
frameGui.Parent = playerGui
local FRAME_SCALE = 0.6
local function softenFrame(root)
	if not root then return end
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			node.TextTransparency = math.max(node.TextTransparency, 0.25)
		elseif node:IsA("UIStroke") then
			node.Transparency = math.max(node.Transparency, 0.45)
		elseif node:IsA("GuiObject") and node.BackgroundTransparency < 1 then
			node.BackgroundTransparency = math.max(node.BackgroundTransparency, node.Name == "Dot" and 0.1 or 0.3)
		end
	end
end
local rec = Hud.Mount("HUD_PC", "RecLine", frameGui, {Scale = FRAME_SCALE})
softenFrame(rec)
local timecode = rec and Binder.text(Binder.at(rec, "Time"))
local watching = rec and Binder.text(Binder.at(rec, "Watching"))
local brackets = {}
for index = 1, 4 do
	local bracket = Hud.Mount("HUD_PC", "Bracket", frameGui, {Name = "Bracket" .. index, Scale = FRAME_SCALE})
	if bracket then
		softenFrame(bracket)
		bracket.AnchorPoint = Vector2.new(0.5, 0.5)
		bracket.Rotation = (index - 1) * 90
		table.insert(brackets, bracket)
	end
end

local function formatTimecode(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(seconds / 3600),
			math.floor(seconds / 60) % 60, seconds % 60)
	end
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function placeFrame()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	if rec then
		rec.Visible = not layout.IsTouch
		rec.Position = UIDevice.LocalPosition(frameGui, safe.Left + 72, safe.Top + 16)
	end
	for index, bracket in ipairs(brackets) do
		bracket.Visible = not layout.IsTouch
		local half = bracket.Size.X.Offset / 2
		local right = index == 2 or index == 3
		local bottom = index == 3 or index == 4
		local x = right and safe.Right - 24 - half or safe.Left + 24 + half
		local y = bottom and safe.Bottom - 24 - half or safe.Top + 16 + half
		bracket.Position = UIDevice.LocalPosition(frameGui, x, y)
	end
end

local function frameWanted()
	return player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true
		and player:GetAttribute("LobbyLoadingOpen") ~= true
		and player:GetAttribute("LuckyWheelOpen") ~= true
end
local function refreshFrame()
	frameGui.Enabled = frameWanted()
	placeFrame()
end
for _, name in ipairs({"InRound", "LobbyLoadingOpen", "LuckyWheelOpen"}) do
	player:GetAttributeChangedSignal(name):Connect(refreshFrame)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(refreshFrame)
UIDevice.Changed:Connect(placeFrame)
refreshFrame()
local previousSecond, previousWatchers = nil, nil
RunService.Heartbeat:Connect(function()
	if not frameGui.Enabled or not rec or not rec.Visible then return end
	local started = workspace:GetAttribute("RoundStartedAt")
	local elapsed = type(started) == "number" and math.max(0, workspace:GetServerTimeNow() - started) or 0
	local second = math.floor(elapsed)
	if timecode and second ~= previousSecond then
		previousSecond = second
		timecode.Text = formatTimecode(second)
	end
	local count = math.max(0, tonumber(player:GetAttribute("SpectatorCount")) or 0)
	if watching and count ~= previousWatchers then
		previousWatchers = count
		watching.Text = count > 0 and ("\u{B7} " .. count .. " WATCHING") or ""
		watching.Visible = count > 0
	end
end)

-- One mounted template per visible prompt; hidden boards are reused on the same input layout.
local shown, pools = {}, {HUD_PC = {}, HUD_Touch = {}}
local function acquire(bundle)
	local pool = pools[bundle]
	local cached = table.remove(pool)
	if cached then return cached end
	local board = Instance.new("BillboardGui")
	board.Name = "InteractionPrompt"
	board.AlwaysOnTop = true
	board.Active = true
	board.ResetOnSpawn = false
	local root = Hud.Mount(bundle, bundle == "HUD_Touch" and "PromptPlateTouch" or "PromptPlate", board)
	if not root then board:Destroy() return nil end
	board.Size = root.Size
	local hit = Binder.button(root, "PromptHit")
	hit.Selectable = false
	return {Board = board, Root = root, Hit = hit, Bundle = bundle,
		Object = Binder.text(Binder.at(root, "ObjectLine")),
		Action = Binder.text(Binder.at(root, "ActionLine")),
		Reason = Binder.text(Binder.at(root, "Reason")),
		Key = Binder.at(root, "KeyChip"),
		HoldBar = Binder.at(root, "HoldBar"),
		Fill = Binder.at(root, "HoldBar/Track/Fill"),
		Ring = Binder.at(root, "RingSlot") and Hud.Ring(Binder.at(root, "RingSlot")) or nil}
end

local function setPromptFill(state, fraction)
	if state.Fill then state.Fill.Size = UDim2.fromScale(fraction, 1) end
	if state.Ring then state.Ring(fraction, P.RailTeal) end
end

local function build(prompt)
	local bundle = Hud.Bundle()
	local state = acquire(bundle)
	if not state then return nil end
	state.Connections, state.Held, state.Input = {}, nil, nil
	local board = state.Board
	board.Adornee = prompt.Parent
	board.SizeOffset = Vector2.new(prompt.UIOffset.X / board.Size.X.Offset, prompt.UIOffset.Y / board.Size.Y.Offset)
	board.MaxDistance = prompt.MaxActivationDistance + 8
	local function connect(signal, callback)
		table.insert(state.Connections, signal:Connect(callback))
	end
	local disabled = false
	local function renderText()
		local reason = prompt:GetAttribute("HudDisabledReason")
		disabled = type(reason) == "string" and reason ~= ""
		if state.Object then
			state.Object.Text = string.upper(prompt.ObjectText)
			state.Object.Visible = not disabled
		end
		if state.Reason then
			state.Reason.Text = disabled and string.upper(reason) or ""
			state.Reason.Visible = disabled
			state.Reason.TextColor3 = P.Amber
		end
		if state.Action then
			state.Action.Text = string.upper(prompt.ActionText ~= "" and prompt.ActionText or "Interact")
			state.Action.TextColor3 = disabled and P.Sage or P.Cream
		end
		if state.Key then
			Hud.Keycap(state.Key, prompt.KeyboardKeyCode, prompt.GamepadKeyCode)
			local key = Binder.text(Binder.at(state.Key, "Key"))
			if key then key.TextColor3 = disabled and P.Sage or P.Cream end
		end
		if state.HoldBar then state.HoldBar.Visible = prompt.HoldDuration > 0 end
		if disabled then state.Held = nil setPromptFill(state, 0) end
	end
	renderText()
	setPromptFill(state, 0)
	connect(prompt:GetPropertyChangedSignal("ActionText"), renderText)
	connect(prompt:GetPropertyChangedSignal("ObjectText"), renderText)
	connect(prompt:GetAttributeChangedSignal("HudDisabledReason"), renderText)
	connect(prompt:GetPropertyChangedSignal("HoldDuration"), renderText)
	connect(state.Hit.InputBegan, function(input)
		if not disabled and (input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1) then
			state.Input = input
			prompt:InputHoldBegin()
		end
	end)
	connect(state.Hit.InputEnded, function(input)
		if state.Input == input then state.Input = nil prompt:InputHoldEnd() end
	end)
	connect(UserInputService.InputEnded, function(input)
		if state.Input == input then state.Input = nil prompt:InputHoldEnd() end
	end)
	connect(prompt.PromptButtonHoldBegan, function()
		if not disabled then state.Held = 0 end
	end)
	connect(prompt.PromptButtonHoldEnded, function()
		state.Held = nil
		setPromptFill(state, 0)
	end)
	connect(RunService.RenderStepped, function(dt)
		if state.Held ~= nil and prompt.HoldDuration > 0 then
			state.Held += dt
			setPromptFill(state, math.clamp(state.Held / prompt.HoldDuration, 0, 1))
		end
	end)
	board.Parent = playerGui
	return state
end

local function hide(prompt)
	local state = shown[prompt]
	if not state then return end
	shown[prompt] = nil
	if state.Input then state.Input = nil prompt:InputHoldEnd() end
	for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	state.Held = nil
	setPromptFill(state, 0)
	state.Board.Parent, state.Board.Adornee = nil, nil
	-- Bound the pool: the template owns no live prompt or connections while parked.
	if #pools[state.Bundle] < 8 then
		table.insert(pools[state.Bundle], state)
	else
		state.Board:Destroy()
	end
end
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	hide(prompt)
	shown[prompt] = build(prompt)
end)
ProximityPromptService.PromptHidden:Connect(hide)
UIDevice.Changed:Connect(function()
	local pending = {}
	for prompt in pairs(shown) do table.insert(pending, prompt) end
	for _, prompt in ipairs(pending) do
		hide(prompt)
		if prompt.Parent then shown[prompt] = build(prompt) end
	end
end)
local function adopt(instance)
	if instance:IsA("ProximityPrompt") then instance.Style = Enum.ProximityPromptStyle.Custom end
end
workspace.DescendantAdded:Connect(adopt)
for _, instance in ipairs(workspace:GetDescendants()) do adopt(instance) end

-- CAMCORDER_20261010 (owner: "Consider a 90s-inspired camera filter when you are in a level, in first person
-- and as a spectator."). Stage 1, no image assets: a mild grade on the 3D picture, a date stamp under the
-- timecode and a soft vignette under every HUD. On by default; the player attribute CamcorderFilterEnabled
-- == false is the off switch for now (a row on the settings page is the follow-up).
-- Static on purpose: nothing here flashes, blinks or moves the camera, so ReduceFlashing and
-- ReduceCameraShake have nothing to turn down, and there is no grain or scanline for a stream encoder to
-- fight. Nothing is parented to a character; no Lighting property and no level's own grade is touched.
-- It is the last thing in this script so that a fault in it can never take the prompt plates down.
-- Play-test readback: PlayerGui.FoundFootageLens attributes CamcorderOn and CamcorderLevel (0 while off).
do
	local CAM = {
		Setting = "CamcorderFilterEnabled",
		-- The look at strength 1. It composes with each level's own grade, so it is weaker where a level has
		-- a colour identity of its own. A level set to 0 gets no look at all; one without a row gets Fallback.
		-- No lift: Brightness stays 0 and Contrast is never negative, so a black pixel stays black. Level 3's
		-- blackout, Level 5's drop and Level 1 after the power-down are tuned to be black, and a lifted
		-- grade would lay a grey veil over all three.
		Saturation = -0.10, Contrast = 0.03, Brightness = 0, Tint = Color3.fromRGB(246, 250, 244),
		Strength = {[1] = 1, [2] = 0.7, [3] = 1, [4] = 0.6, [5] = 0.6, [6] = 0.7},
		Fallback = 0.6,
		-- The tape's own date and clock. NOT the player's: a recording must not show a streamer's local time.
		StampDate = "OCT.13 1996", StampStartMinutes = 23 * 60 + 41,
		-- Vignette depth as a share of the screen, and its transparency at the very edge (1 draws nothing).
		VignetteSide = 0.12, VignetteTopBottom = 0.16, VignetteEdge = 0.7,
		-- STAGE 2: the image of a 64 x 64 scanline tile (2 px black lines every 4 px on transparent), as
		-- "rbxassetid://<id>". "" draws nothing.
		ScanlineImage = "",
		-- Level 6's kill cam puts a ScreenGui of this name up when it starts; the Frame of the second name
		-- inside it is the black the kill ends in (BackgroundTransparency 1 = clear, 0 = black).
		KillCover = "Level6KillCover",
		KillBlack = "KillBlack",
	}

	-- The lens gui sits under every other gui (DisplayOrder -1): the HUD stays crisp over the darkened
	-- edges, as an on-screen display sits over tape. It exists on every device because it carries the
	-- readback attributes; refresh() only ever ENABLES it on a pointer device.
	local lens = Instance.new("ScreenGui")
	lens.Name = "FoundFootageLens"
	lens.DisplayOrder = -1
	lens.ResetOnSpawn = false
	lens.IgnoreGuiInset = true
	lens.ScreenInsets = Enum.ScreenInsets.None -- full screen, as Round HUD's chase edge
	lens.Enabled = false
	-- Four black bands built like that chase edge: each gradient runs from its screen edge inward. Two
	-- bands meet in every corner, which is where a lens is darkest. The CamVignette* names are what
	-- UIRegression's FULLSCREEN_OVERLAYS has to list, as it lists ChaseEdge*: the bands are MEANT to lie
	-- over every rect near a screen edge, and are too shallow for its 92 % rule.
	local side, flat = UDim2.fromScale(CAM.VignetteSide, 1), UDim2.fromScale(1, CAM.VignetteTopBottom)
	-- Name, AnchorPoint, Position, Size, gradient Rotation.
	for _, spec in ipairs({
		{"CamVignetteLeft", Vector2.new(0, 0), UDim2.new(), side, 0},
		{"CamVignetteRight", Vector2.new(1, 0), UDim2.fromScale(1, 0), side, 180},
		{"CamVignetteTop", Vector2.new(0, 0), UDim2.new(), flat, 90},
		{"CamVignetteBottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), flat, 270},
	}) do
		local band = Instance.new("Frame")
		band.Name = spec[1]
		band.AnchorPoint, band.Position, band.Size = spec[2], spec[3], spec[4]
		band.BackgroundColor3 = Color3.new(0, 0, 0)
		band.BorderSizePixel = 0
		band.Active = false
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new(CAM.VignetteEdge, 1)
		gradient.Rotation = spec[5]
		gradient.Parent = band
		band.Parent = lens
	end
	if CAM.ScanlineImage ~= "" then
		local scan = Instance.new("ImageLabel")
		scan.Name = "CamScan"
		scan.Size = UDim2.fromScale(1, 1)
		scan.BackgroundTransparency = 1
		scan.BorderSizePixel = 0
		scan.Active = false
		scan.Image = CAM.ScanlineImage
		scan.ImageTransparency = 0.93
		scan.ScaleType = Enum.ScaleType.Tile
		scan.TileSize = UDim2.fromOffset(64, 64)
		scan.ResampleMode = Enum.ResamplerMode.Pixelated
		scan.Parent = lens
	end
	lens.Parent = playerGui

	-- The date stamp is a second mount of the REC line with everything but its Time hidden, so it takes the
	-- template's own Roboto Mono Bold and Binder's fit pass widens the box for the longer text. Hidden, not
	-- destroyed: the fit pass only measures against visible siblings, and the mount stays the template's.
	local stamp = Hud.Mount("HUD_PC", "RecLine", frameGui, {Name = "StampLine", Scale = FRAME_SCALE})
	softenFrame(stamp)
	local stampLabel = nil
	if stamp then
		local node = Binder.at(stamp, "Time")
		stampLabel = Binder.text(node)
		local keep = {}
		while node and node ~= stamp do
			keep[node] = true
			node = node.Parent
		end
		for _, child in ipairs(stamp:GetChildren()) do
			if child:IsA("GuiObject") then child.Visible = keep[child] == true end
		end
		stamp.Visible = false
	end
	local tapeStartedAt = os.clock() -- reset each time the stamp comes up: every round is a fresh tape
	local function writeStamp()
		if not (stampLabel and stamp.Visible) then return end
		local minutes = CAM.StampStartMinutes + math.floor((os.clock() - tapeStartedAt) / 60)
		local text = string.format("%s  %02d:%02d", CAM.StampDate, math.floor(minutes / 60) % 24, minutes % 60)
		if stampLabel.Text ~= text then stampLabel.Text = text end
	end
	-- The timecode's text changes once a second while the frame is drawn. That change is the stamp's clock,
	-- so the stamp costs nothing per frame and nothing while the frame is hidden.
	if timecode then timecode:GetPropertyChangedSignal("Text"):Connect(writeStamp) end

	-- The grade lives under the CAMERA, not in Lighting: Level 4 and the new Level 2 map switch off every
	-- foreign ColorCorrection that is a child of Lighting, and no level's sweep looks under the camera
	-- (Level 4 keeps its own DepthOfField there). A camera effect is also this player's alone by
	-- construction, and it composes with the level's grade instead of replacing it.
	local grade = nil
	local function mountGrade()
		local camera = workspace.CurrentCamera
		if not camera or (grade and grade.Parent == camera) then return end
		-- Replacing CurrentCamera destroys the old camera with everything under it, and a destroyed effect
		-- cannot be parented again: the new camera gets a new effect.
		local old = grade
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "CamcorderGrade"
		grade.Enabled = false
		grade.Parent = camera
		if old then old:Destroy() end
	end

	local function gradedLevel()
		-- Levels 5 and 6 run on a lobby server, where SelectedLevel stays 1: their player markers say which
		-- (Level 5 carries its own marker next to the shared one).
		if player:GetAttribute("Level5VoidRound") == true then return 5 end
		if player:GetAttribute("Level6PlaygroundPreview") == true then return 6 end
		return tonumber(workspace:GetAttribute("SelectedLevel")) or 1
	end
	-- The REC frame's gate, widened by the live-level marker (RoundActive is false on a lobby server). It
	-- does not look at Spectating: a dead or escaped participant keeps InRound, and the spectate view is the
	-- same camera, so the spectator gets the same look.
	local function wanted()
		return player:GetAttribute("InRound") == true
			and (workspace:GetAttribute("RoundActive") == true
				or player:GetAttribute("Level6PlaygroundPreview") == true)
			and player:GetAttribute(CAM.Setting) ~= false
			and player:GetAttribute("LobbyLoadingOpen") ~= true
			and player:GetAttribute("LuckyWheelOpen") ~= true
	end
	-- A script that switches the REC frame off under this one (Level 6's kill cam does, by name, every
	-- frame) wants its own picture: the look stands down with the frame. That is the frame off while THIS
	-- script wants it on. In Levels 5 and 6 the frame is off for the whole level (RoundActive is false), so
	-- there the kill cam cannot be seen that way and is recognised by its cover instead.
	-- killCover is that cover while the kill is still being SHOWN. The cover itself lives longer: it goes
	-- black, waits for the spectate view, fades out over it and is destroyed a tenth of a second later.
	-- Standing down until then would switch the vignette and the grade on in one frame, in full view, just
	-- after the picture has faded up; so the look comes back under the black instead (see the watch below).
	local killCover = nil
	local function hushed()
		-- A cover that left PlayerGui without being destroyed is over too.
		if killCover and killCover.Parent ~= playerGui then killCover = nil end
		return killCover ~= nil or (frameWanted() and not frameGui.Enabled)
	end

	local function refresh()
		mountGrade()
		local level = gradedLevel()
		local k = CAM.Strength[level] or CAM.Fallback
		local on = k > 0 and wanted() and not hushed()
		if grade then
			grade.Saturation, grade.Contrast = CAM.Saturation * k, CAM.Contrast * k
			grade.Brightness = CAM.Brightness * k
			local tint = CAM.Tint -- white toward the tint by k
			grade.TintColor = Color3.new(1 + (tint.R - 1) * k, 1 + (tint.G - 1) * k, 1 + (tint.B - 1) * k)
			grade.Enabled = on
		end
		-- Stamp and vignette on pointer devices only, like REC and the brackets. The vignette is also never
		-- up under UIRegression's viewport fixture: its bands hang on the REAL screen's edges there, and
		-- tools/mobile_qa copies every enabled ScreenGui into its phone-sized frame.
		local layout = UIDevice.Layout()
		local drawn = on and not layout.IsTouch
		local veil = drawn and workspace:GetAttribute("UIRegressionViewport") == nil
		if lens.Enabled ~= veil then lens.Enabled = veil end
		if stamp then
			-- 20 px under the REC line's top: clear of REC (16..34) above and the exit notice (from 64) below.
			stamp.Position = UIDevice.LocalPosition(frameGui, layout.Safe.Left + 72, layout.Safe.Top + 36)
			local show = drawn and stampLabel ~= nil
			if stamp.Visible ~= show then
				stamp.Visible = show
				if show then tapeStartedAt = os.clock() end
				writeStamp() -- right when it appears; from then on the timecode's tick keeps it
			end
		end
		local graded = on and level or 0
		if lens:GetAttribute("CamcorderOn") ~= on then lens:SetAttribute("CamcorderOn", on) end
		if lens:GetAttribute("CamcorderLevel") ~= graded then lens:SetAttribute("CamcorderLevel", graded) end
	end
	-- Signals only: nothing here runs per frame. UIDevice.Changed carries the form factor and the safe area.
	for _, name in ipairs({"InRound", CAM.Setting, "Level5VoidRound", "Level6PlaygroundPreview",
		"LobbyLoadingOpen", "LuckyWheelOpen"}) do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	for _, name in ipairs({"RoundActive", "SelectedLevel", "UIRegressionViewport"}) do
		workspace:GetAttributeChangedSignal(name):Connect(refresh)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refresh)
	frameGui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	UIDevice.Changed:Connect(refresh)
	playerGui.ChildAdded:Connect(function(child)
		if child.Name ~= CAM.KillCover then return end
		killCover = child
		local function over()
			if killCover == child then killCover = nil end
			refresh()
		end
		-- The kill is over for the picture the moment its black is whole (the kill cam's blackout writes a
		-- literal 0): from there on nothing of the 3D view shows until the cover fades out, and by then the
		-- look has to be back. The black only changes on frames of the kill and of that fade (some six
		-- seconds a death), so this compare runs then and at no other time. A cover without that Frame is
		-- only over when it is destroyed.
		local black = child:FindFirstChild(CAM.KillBlack)
		if black and black:IsA("GuiObject") then
			black:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
				if killCover == child and black.BackgroundTransparency <= 0 then over() end
			end)
		end
		child.Destroying:Connect(over)
		refresh()
	end)
	refresh()
end
