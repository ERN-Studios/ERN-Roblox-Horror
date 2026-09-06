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

local gui = Instance.new("ScreenGui")
gui.Name = "SpectateGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 58
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 1, -20)
label.Size = UDim2.new(0, 420, 0, 30)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.4
label.BorderSizePixel = 0
label.Font = Enum.Font.Gotham
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(220, 220, 220)
label.Visible = false
label.Text = ""
label.Parent = gui
local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 6); lc.Parent = label

-- Touch has no Q/E, and until now had no way to change who it was watching at
-- all: the label simply named bindings that do not exist on a phone. Two arrows
-- sit either side of the caption, inside the same safe band, and are the only
-- spectate affordance a touch player ever sees.
local ARROW_LEFT = utf8.char(0x2039)
local ARROW_RIGHT = utf8.char(0x203A)
local function makeCycleButton(name, glyph)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.BackgroundColor3 = Color3.new(0, 0, 0)
	button.BackgroundTransparency = 0.4
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = glyph
	button.TextColor3 = Color3.fromRGB(220, 220, 220)
	button.TextSize = 22
	button.Visible = false
	button.Active = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end
local applySpectateLayout
local prevButton = makeCycleButton("SpectatePrevious", ARROW_LEFT)
local nextButton = makeCycleButton("SpectateNext", ARROW_RIGHT)

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
end

local function livingOthers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		-- only players still ACTIVE in the maze: alive and not escaped (escapees
		-- sit parked in the safe room — nothing to watch there)
		if p ~= player and p:GetAttribute("Escaped") ~= true then
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
		unhide()
		label.Text = player:GetAttribute("Escaped") == true
			and "You escaped — waiting for the round to end"
			or "Spectating — no survivors left"
		return
	end
	idx = ((i - 1) % #targets) + 1
	if spectated ~= targets[idx] then unhide(); snapCam = true end -- reveal prev body, snap to new POV
	spectated = targets[idx]
	-- The binding half of this caption comes from UIDevice, so a phone sees
	-- only the name and uses the arrows beside it.
	label.Text = UIDevice.Caption("POV: " .. spectated.Name, "(Q / E to switch)", "(D-pad ← / →)")
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
	if profile ~= lastBeamProfile or on ~= lastOn then
		Profiles.Apply(Profiles.Spectate, profile, core, spill)
		core.Enabled = on
		spill.Enabled = on
		lastBeamProfile, lastOn = profile, on
	end
end)

-- The label was a fixed 420px box anchored 20px off the bottom. On a 375-wide
-- portrait screen that ran 45px off both edges, and on any touch device it sat
-- squarely on the movement controls. It now sizes to the safe width and lives
-- in the safe content band, with the arrows flanking it on touch.
local ARROW_WIDTH = 44
applySpectateLayout = function()
	local layout = UIDevice.Layout()
	local touch = layout.IsTouch
	-- Spectating hides the stamina bar, so on touch the caption takes the lane
	-- between the two movement zones -- the only place on a landscape phone with
	-- room for a label plus two arrows. Portrait's corridor is too narrow for
	-- that, so it falls back to the safe band.
	local corridor = layout.Corridor
	local useCorridor = touch and corridor.Width >= 240
	local available = useCorridor and corridor.Width or (layout.SafeRight - layout.SafeLeft)
	local arrowRoom = touch and (ARROW_WIDTH + 8) * 2 or 0
	local width = math.min(420, available - arrowRoom)
	local absoluteBottom = touch
		and (useCorridor and (layout.Display.Bottom - 18) or layout.SafeBottom)
		or (layout.Display.Bottom - 20)
	-- Centre on the SAFE RECT, not on the screen. The safe rect is off-centre
	-- whenever the control column eats the right edge (landscape), and centring
	-- a 420px label on 0.5 pushed it straight back under the controls.
	local absoluteCentre = useCorridor and (corridor.Left + corridor.Right) * .5
		or (touch and (layout.SafeLeft + layout.SafeRight) * .5 or nil)
	-- Both figures are ABSOLUTE and both need converting; the old code passed
	-- them straight in as gui offsets, so X was wrong on any device with a
	-- horizontal safe inset and Y was wrong by the topbar on every device.
	local centre, bottom = nil, select(2, UIDevice.LocalOffset(gui, 0, absoluteBottom))
	if absoluteCentre then
		centre = select(1, UIDevice.LocalOffset(gui, absoluteCentre, 0))
	end
	label.Size = UDim2.new(0, width, 0, 30)
	label.Position = centre and UDim2.fromOffset(centre, bottom)
		or UDim2.new(0.5, 0, 0, bottom)
	for _, entry in ipairs({{prevButton, -1}, {nextButton, 1}}) do
		local button, side = entry[1], entry[2]
		local offset = side * (width * .5 + 8 + ARROW_WIDTH * .5)
		button.Size = UDim2.fromOffset(ARROW_WIDTH, 44)
		button.Position = centre and UDim2.fromOffset(centre + offset, bottom)
			or UDim2.new(0.5, offset, 0, bottom)
	end
	local showArrows = touch and cycleAvailable()
	UIDevice.SetInteractive(prevButton, showArrows)
	UIDevice.SetInteractive(nextButton, showArrows)
end

prevButton.Activated:Connect(function() if cycleAvailable() then watch(idx - 1) end end)
nextButton.Activated:Connect(function() if cycleAvailable() then watch(idx + 1) end end)
UIDevice.OnScreenOwningModalChanged(function() applySpectateLayout() end)
player:GetAttributeChangedSignal("PartyDownCardOpen"):Connect(function() applySpectateLayout() end)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function() applySpectateLayout() end)
UIDevice.Changed:Connect(function()
	applySpectateLayout()
	-- The POV caption carries the Q/E binding on desktop and not on touch,
	-- so a form-factor change has to rebuild it, not just move it.
	if spectating and spectated then watch(idx) end
end)

local function startSpectate()
	if spectating or not workspace:GetAttribute("RoundActive") then return end
	spectating = true
	-- Publish the state. "Spectating" was already being READ by the Level 2
	-- Slidemouth client and (now) by the movement cluster, but nothing had ever
	-- written it, so both checks were dead.
	player:SetAttribute("Spectating", true)
	label.Visible = true
	applySpectateLayout()
	watch(1)
end

local function stopSpectate()
	spectating = false
	player:SetAttribute("Spectating", nil)
	spectated = nil
	label.Visible = false
	UIDevice.SetInteractive(prevButton, false)
	UIDevice.SetInteractive(nextButton, false)
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
