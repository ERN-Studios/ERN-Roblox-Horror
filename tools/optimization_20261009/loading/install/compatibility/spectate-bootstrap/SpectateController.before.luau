-- SpectateController  (v2 — full first-person POV of a teammate + their flashlight)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "SpectateController"
--
-- When you die during a round you FULLY take a living teammate's POV: locked
-- first person from their eyes (no free-look), and you see THEIR flashlight beam
-- (your own is off). Q / E or D-pad left/right cycle survivors. Clears on respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local Profiles = require(ReplicatedStorage:WaitForChild("FlashlightProfiles"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local playerScripts = player:WaitForChild("PlayerScripts")

-- SPECTATOR_COUNT_20260914 (card 73): tell the server who we watch so the
-- watched player can be shown a count. Sent only when the answer changes.
local reportedTarget = false
local function reportTarget(userId)
	if reportedTarget == userId then return end
	reportedTarget = userId
	remote:FireServer("spectatetarget", userId)
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpectateGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 58
gui.Parent = player:WaitForChild("PlayerGui")

-- HUD_B8_SPECTATE: only the presentation changes; this file still owns the POV.
local label, prevButton, nextButton, exitButton = nil, nil, nil, nil
local applySpectateLayout
local band = {who = nil, empty = true, escaped = false}
do
	local Hud = require(ReplicatedStorage:WaitForChild("RoundHud"))
	local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
	function band.mount()
		local layout = UIDevice.Layout()
		local touch = layout.IsTouch
		local width = touch and 420 or 520
		local scale = math.min(1, (layout.Safe.Width - 24) / width)
		if band.root then band.root:Destroy() end
		if exitButton then exitButton:Destroy() end
		band.root, band.attention = Hud.Mount("HUD_Screens", touch and "SpectateBandTouch" or "SpectateBand", gui,
			{Name = "SpectateBand", Scale = scale, Touch = touch, Attention = {Hold = 6, Rest = 0.45}})
		exitButton = Hud.Mount("HUD_Screens", "SpectateBackToLobby", gui,
			{Name = "SpectateBackToLobby", Scale = scale, Touch = touch})
		if not band.root or not exitButton then return end
		for _, node in ipairs(band.root:GetDescendants()) do
			if node:IsA("Frame") then node.BackgroundTransparency = 1 end
			if node:IsA("TextLabel") then
				local stroke = node:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
				stroke.Name = "ContextualTextStroke"
				stroke.Color = Color3.fromRGB(5,9,11)
				stroke.Transparency = 0.35
				stroke.Thickness = 1.5
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				stroke.Parent = node
			end
		end
		prevButton, nextButton = Binder.find(band.root, "Prev"), Binder.find(band.root, "Next")
		prevButton.Name, nextButton.Name = "SpectatePrevious", "SpectateNext"
		if touch then prevButton.Size, nextButton.Size = UDim2.fromOffset(44,44), UDim2.fromOffset(44,44) end
		prevButton.Activated:Connect(function() if band.Cycle then band.Cycle(-1) end end)
		nextButton.Activated:Connect(function() if band.Cycle then band.Cycle(1) end end)
		local prevKey, nextKey = Binder.find(prevButton, "KeyChip"), Binder.find(nextButton, "KeyChip")
		if prevKey then Hud.Keycap(prevKey, Enum.KeyCode.Q, Enum.KeyCode.DPadLeft) end
		if nextKey then Hud.Keycap(nextKey, Enum.KeyCode.E, Enum.KeyCode.DPadRight) end
		label = Binder.find(band.root, "Who")
		band.watching = Binder.find(band.root, "Watching")
		band.initial = Binder.at(band.root, "Initial/Letter")
		Binder.find(exitButton, "Label").Text = "BACK TO LOBBY"
		exitButton.Activated:Connect(function()
			if not exitButton.Active then return end
			local prompt = playerScripts:FindFirstChild("RoundExitPrompt")
			if prompt and prompt:IsA("BindableEvent") then prompt:Fire() end
		end)
	end
	function band.copy(who, escaped)
		band.who, band.escaped = who, escaped
		band.watching.Text = escaped and "YOU GOT OUT \u{B7} WATCHING" or who and "WATCHING" or "SPECTATING"
		label.Text = who and who.DisplayName or "NO ONE LEFT TO WATCH"
		band.initial.Text = who and string.upper(utf8.char(utf8.codepoint(who.DisplayName, 1))) or "?"
		band.attention:Show(who and tostring(who.UserId) or "empty", false)
	end
	band.mount()
end

local SMOOTH = 11     -- how fast the POV eases toward their head — high enough to
-- follow, low enough to filter out the walk/idle head-bob jitter

local spectating = false
local targets = {}
local idx = 1
local spectated = nil -- the player whose POV we're in
local hidden = nil    -- character whose parts we've hidden locally
local hiddenParts = {} -- cached BaseParts of `hidden` (rebuilt on target change)
local hiddenPartsConn = nil
local snapCam = true  -- snap (not ease) on the first frame and whenever we switch target
local lastBeamProfile, lastOn = nil, nil -- cached borrowed-beam state; nil forces the first write

local function cycleAvailable()
	return spectating and not GuiService.MenuIsOpen
		and UIS:GetFocusedTextBox() == nil
		and not UIDevice.ScreenOwningModalOpen()
		and player:GetAttribute("PartyDownCardOpen") ~= true
		and player:GetAttribute("RoundExitPromptOpen") ~= true
end

local function livingOthers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		-- only players still ACTIVE in the maze: alive and not escaped (escapees
		-- sit parked in the safe room — nothing to watch there)
		-- In Level 6 (lobby server) only the others in the level, never somebody standing in the lobby.
		-- Level 5 is a live level on the same server and shares the marker: only the others in the SAME one.
		if p ~= player and p:GetAttribute("Escaped") ~= true
			and (player:GetAttribute("Level6PlaygroundPreview") ~= true
				or (p:GetAttribute("Level6PlaygroundPreview") == true
					and (p:GetAttribute("Level5VoidRound") == true) == (player:GetAttribute("Level5VoidRound") == true))) then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then
				table.insert(list, p)
			end
		end
	end
	return list
end

-- borrowed flashlight: mirrors the spectated player's beam from their viewpoint
-- (their FlashlightOn flag is a replicated BoolValue on their character)
local beamMount = Instance.new("Part")
beamMount.Name = "SpectateBeam"
beamMount.Size = Vector3.new(0.2, 0.2, 0.2)
beamMount.Anchored = true
beamMount.CanCollide = false
beamMount.CanQuery = false
beamMount.Transparency = 1
local core = Instance.new("SpotLight")
core.Color = Color3.fromRGB(255, 244, 214); core.Shadows = true
core.Face = Enum.NormalId.Front; core.Enabled = false; core.Parent = beamMount
local spill = Instance.new("SpotLight")
spill.Color = Color3.fromRGB(255, 240, 205); spill.Shadows = false
spill.Face = Enum.NormalId.Front; spill.Enabled = false; spill.Parent = beamMount

local function unhide()
	if hidden then
		for _, d in ipairs(hidden:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
		hidden = nil
	end
	table.clear(hiddenParts)
	if hiddenPartsConn then
		hiddenPartsConn:Disconnect()
		hiddenPartsConn = nil
	end
end

local function watch(i)
	targets = livingOthers()
	if #targets == 0 then
		spectated = nil
		-- SPECTATE_TARGET_20260914: the one client-local fact every other local
		-- script reads to mirror the watched player's audio and POV-relative UI.
		player:SetAttribute("SpectateTargetUserId", nil)
		reportTarget(nil)
		unhide()
		band.copy(nil, player:GetAttribute("Escaped") == true)
		return
	end
	idx = ((i - 1) % #targets) + 1
	if spectated ~= targets[idx] then unhide(); snapCam = true end -- reveal prev body, snap to new POV
	spectated = targets[idx]
	player:SetAttribute("SpectateTargetUserId", spectated.UserId)
	reportTarget(spectated.UserId)
	band.copy(spectated, player:GetAttribute("Escaped") == true)
end

-- drive the POV camera + borrowed flashlight every frame while spectating
RunService.RenderStepped:Connect(function(dt)
	if not (spectating and spectated) then return end
	local cam = workspace.CurrentCamera
	local char = spectated.Character
	local head = char and char:FindFirstChild("Head")
	if not (cam and head) then return end

	-- lock to their eyes + look direction (no free-look), but EASE toward the head
	-- so their walk/idle head-bob doesn't jitter the whole screen
	cam.CameraType = Enum.CameraType.Scriptable
	if snapCam then
		cam.CFrame = head.CFrame
		snapCam = false
	else
		cam.CFrame = cam.CFrame:Lerp(head.CFrame, math.clamp(dt * SMOOTH, 0, 1))
	end

	-- hide their body locally so it doesn't fill the screen (true first person).
	-- The part list is cached per spectated character: a GetDescendants sweep
	-- every RenderStepped allocated a fresh table 60x per second.
	if hidden ~= char then
		unhide()
		hidden = char
		table.clear(hiddenParts)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then hiddenParts[#hiddenParts + 1] = d end
		end
		if hiddenPartsConn then hiddenPartsConn:Disconnect() end
		hiddenPartsConn = char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				hiddenParts[#hiddenParts + 1] = d
				d.LocalTransparencyModifier = 1
			end
		end)
		for _, d in ipairs(hiddenParts) do
			if d.Parent then d.LocalTransparencyModifier = 1 end
		end
	end

	-- mirror their flashlight from the shared viewpoint
	if beamMount.Parent ~= cam then beamMount.Parent = cam end
	beamMount.CFrame = cam.CFrame
	local fo = char:FindFirstChild("FlashlightOn")
	local on = fo ~= nil and fo.Value
	local profile = Profiles.Current()
	local focused = char:GetAttribute("FlashlightFocused") == true
	local profileKey = profile .. tostring(focused)
	if profileKey ~= lastBeamProfile or on ~= lastOn then
		Profiles.Apply(Profiles.Spectate, profile, core, spill, focused)
		core.Enabled = on
		spill.Enabled = on
		lastBeamProfile, lastOn = profileKey, on
	end
end)

applySpectateLayout = function()
	if not band.root then return end
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch
	local visible = spectating and not UIDevice.ScreenOwningModalOpen()
		and player:GetAttribute("PartyDownCardOpen") ~= true and player:GetAttribute("RoundExitPromptOpen") ~= true
	band.root.AnchorPoint = Vector2.new(0.5, 1)
	band.root.Position = UIDevice.LocalPosition(gui, (layout.Safe.Left + layout.Safe.Right) / 2, layout.Safe.Bottom - 12)
	band.root.Visible = visible
	prevButton.Visible, nextButton.Visible = visible, visible
	prevButton.Active, nextButton.Active = visible and cycleAvailable(), visible and cycleAvailable()
	prevButton.Selectable, nextButton.Selectable = prevButton.Active, nextButton.Active
	exitButton.AnchorPoint = Vector2.new(0.5, 1)
	local exitX = (layout.Safe.Left + layout.Safe.Right) / 2
	local exitBottom = layout.Safe.Bottom - 12 - band.root.Size.Y.Offset - 8
	if touch then
		exitButton.Size = UDim2.fromOffset(math.min(240, layout.Safe.Width - 24), 44)
		local width, height = exitButton.Size.X.Offset, exitButton.Size.Y.Offset
		local zones = layout.Zones or {}
		local function intersects(left, bottom, zone)
			return zone and zone.Right > zone.Left and zone.Bottom > zone.Top
				and left < zone.Right and left + width > zone.Left
				and bottom - height < zone.Bottom and bottom > zone.Top
		end
		local left = exitX - width / 2
		local shifted = left
		for _, name in ipairs({"Thumbstick", "Controls", "Jump"}) do
			local zone = zones[name]
			if intersects(shifted, exitBottom, zone) then shifted = zone.Right + 8 end
		end
		local fits = shifted + width <= layout.Safe.Right - 12
		for _, name in ipairs({"Thumbstick", "Controls", "Jump"}) do
			if intersects(shifted, exitBottom, zones[name]) then fits = false end
		end
		if fits then
			exitX = shifted + width / 2
		else
			for _, name in ipairs({"Thumbstick", "Controls", "Jump"}) do
				local zone = zones[name]
				if intersects(left, exitBottom, zone) then exitBottom = zone.Top - 8 end
			end
		end
	end
	exitButton.Position = UIDevice.LocalPosition(gui, exitX, exitBottom)
	UIDevice.SetInteractive(exitButton, visible and cycleAvailable())
end
band.Cycle = function(delta)
	if cycleAvailable() then watch(idx + delta); applySpectateLayout() end
end
UIDevice.OnScreenOwningModalChanged(function() applySpectateLayout() end)
player:GetAttributeChangedSignal("PartyDownCardOpen"):Connect(function() applySpectateLayout() end)
player:GetAttributeChangedSignal("RoundExitPromptOpen"):Connect(function() applySpectateLayout() end)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function() applySpectateLayout() end)
UIDevice.Changed:Connect(function()
	band.mount()
	if spectating then band.copy(spectated, player:GetAttribute("Escaped") == true) end
	applySpectateLayout()
end)

local function startSpectate()
	if spectating or not (workspace:GetAttribute("RoundActive") or player:GetAttribute("Level6PlaygroundPreview") == true) then return end
	spectating = true
	-- Publish the state. "Spectating" was already being READ by the Level 2
	-- Slidemouth client and (now) by the movement cluster, but nothing had ever
	-- written it, so both checks were dead.
	player:SetAttribute("Spectating", true)
	applySpectateLayout()
	watch(1)
	applySpectateLayout()
end

local function stopSpectate()
	spectating = false
	player:SetAttribute("Spectating", nil)
	player:SetAttribute("SpectateTargetUserId", nil)
	reportTarget(nil)
	spectated = nil
	if band.root then band.attention:Hide(); band.root.Visible = false end
	UIDevice.SetInteractive(prevButton, false)
	UIDevice.SetInteractive(nextButton, false)
	UIDevice.SetInteractive(exitButton, false)
	unhide()
	core.Enabled = false; spill.Enabled = false
	lastBeamProfile, lastOn = nil, nil -- force a fresh write next time spectate resumes
	beamMount.Parent = nil
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		if hum then cam.CameraSubject = hum end
	end
end

local function onChar(char)
	stopSpectate() -- fresh body → back to your own view
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(startSpectate)
end

-- C_ONE_SPECTATE_CAMERA_20260904: this file is now the ONLY writer of the
-- spectate camera -- RoundUI used to fight it with a CameraType.Custom ticker
-- of its own, and that ticker was also the only thing that unlocked the camera
-- when a round ended underneath a dead player. startSpectate already refuses
-- outside an active round; this is the matching exit, so the POV cannot outlive
-- the round while the result screen counts down and nothing has respawned
-- anybody yet. Respawn (onChar) and the Escaped paths still stop it too.
--
-- GUARDED ON `spectating`, because this fires on EVERY client at every round
-- end -- lobby players and living participants included -- and stopSpectate
-- writes CameraType.Custom and CameraSubject unconditionally. JumpscareUI owns
-- a CameraType.Scriptable kill cam, so a player dying on the same frame the
-- round closes out would have had their kill sequence knocked back to the
-- default camera halfway through it.
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if spectating and workspace:GetAttribute("RoundActive") ~= true then stopSpectate() end
end)

if player.Character then onChar(player.Character) end
player.CharacterAdded:Connect(onChar)

-- ESCAPING also puts you in spectate: you're alive but out of play, and the
-- round goes on — watch the teammates still inside until it ends.
--
-- LEVEL2_EXIT_TRANSITION_20260828: not while the exit ride is still happening.
-- A Level 2 escapee keeps physically sliding down the transition flume for the
-- whole decision window, so taking their camera away the instant they cross the
-- completion sensor would hide the very thing they are doing. Spectate waits
-- until the server clears Level2_ExitTransition.
local function syncSpectateForEscape()
	if player:GetAttribute("Escaped") == true then
		-- Still riding the Level 2 exit flume: their own body is the thing worth
		-- watching, so spectate waits for the server to end the transition.
		if player:GetAttribute("Level2_ExitTransition") == true then return end
		startSpectate()
		return
	end
	-- Escaped cleared. In the normal flow that coincides with a fresh character
	-- and onChar stops spectating, but the attribute can also be cleared on its
	-- own (a Zyntra re-entry, a campaign hand-off). Without this the player
	-- stays flagged Spectating for the rest of the round -- which now also
	-- keeps the whole movement cluster disabled, because it gates on that flag.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then stopSpectate() end
end
player:GetAttributeChangedSignal("Escaped"):Connect(syncSpectateForEscape)
player:GetAttributeChangedSignal("Level2_ExitTransition"):Connect(syncSpectateForEscape)

UIS.InputBegan:Connect(function(input, processed)
	-- D-pad belongs to GUI navigation while a selection exists, including
	-- Roblox's own selection mode. Never both navigate and switch the camera.
	if processed or not cycleAvailable() or GuiService.SelectedObject ~= nil then return end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.DPadRight then
		watch(idx + 1)
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.DPadLeft then
		watch(idx - 1)
	end
end)

-- if the teammate you're watching dies, escapes, or leaves, jump to another
task.spawn(function()
	while true do
		task.wait(1)
		if spectating then
			local hum = spectated and spectated.Character
				and spectated.Character:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0)
				or (spectated and spectated:GetAttribute("Escaped") == true) then
				watch(idx)
			end
		end
	end
end)
