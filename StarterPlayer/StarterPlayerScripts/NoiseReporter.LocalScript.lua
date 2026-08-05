-- NoiseReporter
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "NoiseReporter"
-- Shift = sprint (loud), Ctrl = crouch (silent), walking = quiet.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ReportNoise")
local glowstickRemote = RS:WaitForChild("Remotes"):WaitForChild("DropGlowstick")
local player = Players.LocalPlayer
local DevAccess = require(RS:WaitForChild("DevAccess"))
local devAllowed = DevAccess.IsAllowed(player)
local function inRound() return player:GetAttribute("InRound") == true end

local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16, 26, 8

-- loudness per movement state, 0..1 (server owns the real values)
local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }

local state = "walk"
local sprinting, crouching = false, false
local shiftSprintHeld, touchSprintHeld = false, false
local GLOWSTICK_COOLDOWN = 5
local lastGlowstickDrop = -math.huge
local currentChar

local function dropGlowstick()
	if not inRound() or os.clock() - lastGlowstickDrop < GLOWSTICK_COOLDOWN then return end
	local char, hum = currentChar()
	if not (char and hum and hum.Health > 0) then return end
	lastGlowstickDrop = os.clock()
	glowstickRemote:FireServer()
end

-- stamina: sprint is limited, drains while sprinting, recovers otherwise
local STAMINA_BASE     = 100
local SPRINT_DRAIN     = 16   -- ~6s of sprint on a full bar
local STAMINA_RECHARGE = 10   -- recovers while not sprinting
local STAMINA_RECOVER  = 25   -- must reach this after exhaustion before sprinting again
local function staminaMax()
	return STAMINA_BASE * math.max(1, tonumber(player:GetAttribute("ZyntraStaminaMultiplier")) or 1)
end
local stamina, exhausted = staminaMax(), false

-- ADRENALINE: while the Entity is on YOU (chasing, or blindly tracking you for
-- the few seconds after it loses sight — the server marks you "BeingChased"),
-- your stamina lasts ADRENALINE_MUL times longer, lingering a moment after.
local ADRENALINE_MUL    = 3
local ADRENALINE_LINGER = 4   -- seconds the boost outlives the chase itself
local adrenalineUntil = 0
player:GetAttributeChangedSignal("BeingChased"):Connect(function()
	if player:GetAttribute("BeingChased") ~= true then
		adrenalineUntil = os.clock() + ADRENALINE_LINGER -- chase just ended → linger
	end
end)
local function adrenalized()
	return player:GetAttribute("BeingChased") == true or os.clock() < adrenalineUntil
end

-- dev cheat (DevCheats toggles the local DevUnlimited attribute): stamina never drains
local function devUnlimited() return player:GetAttribute("DevUnlimited") == true end

currentChar = function()
	local char = player.Character
	return char, char and char:FindFirstChild("Humanoid")
end

local function applySpeed()
	local _, hum = currentChar()
	if not hum then return end
	if not inRound() then
		state = "walk"
		hum.WalkSpeed = WALK_SPEED
		return
	end

	if crouching then
		state = "crouch"
		hum.WalkSpeed = CROUCH_SPEED
	elseif sprinting and stamina > 0 and not exhausted then
		state = "sprint"
		hum.WalkSpeed = SPRINT_SPEED
	else
		state = "walk"
		hum.WalkSpeed = WALK_SPEED
	end
end

local function refreshSprint()
	sprinting = shiftSprintHeld or touchSprintHeld
	applySpeed()
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not inRound() then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftSprintHeld = true; refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = true; applySpeed()
	elseif input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.ButtonX then
		dropGlowstick()
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftSprintHeld = false; refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = false; applySpeed()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	shiftSprintHeld, touchSprintHeld = false, false
	sprinting, crouching = false, false
	applySpeed()
end)

-- report at 5Hz, only while actually moving
task.spawn(function()
	while task.wait(0.2) do
		if not inRound() then continue end
		local char, hum = currentChar()
		if not (char and hum and hum.Health > 0) then continue end

		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		-- only make noise if actually in motion
		if root.AssemblyLinearVelocity.Magnitude < 2 then continue end

		local loud = LOUDNESS[state]
		if loud > 0 then
			remote:FireServer(state)
		end
	end
end)

-- ── stamina bar ───────────────────────────────────────────
-- Matches the rest of the HUD: near-black translucent backdrop, rounded corners,
-- white fill that blushes red as it empties (same white→red as the battery).
-- Bottom-centre, slim; fades IN when you spend stamina, fades OUT when full.
local BAR_W, BAR_H  = 300, 14
local STA_FULL      = Color3.fromRGB(235, 235, 235) -- fill at full stamina
local STA_EMPTY     = Color3.fromRGB(230, 80, 60)   -- fill near empty / exhausted
local BAR_BG_ALPHA  = 0.6   -- backdrop transparency when shown
local BAR_FADE      = 5     -- how fast the bar fades in / out

local gui = Instance.new("ScreenGui")
gui.Name = "StaminaGui"
gui.ResetOnSpawn = false
gui.Enabled = inRound()
gui.Parent = player:WaitForChild("PlayerGui")

-- Compact touch control cluster. Keyboard/controller paths remain unchanged.
-- RUN and JUMP form the right column; POV sits above the upright flashlight
-- immediately to their left, keeping the camera-dragging area clear.
local touchControlsVisible = UIS.TouchEnabled
	or (RunService:IsStudio() and workspace:GetAttribute("ForceTouchUI") == true)

local function makeTouchButton(name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(8, 10, 9)
	button.BackgroundTransparency = 0.52
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 238, 232)
	button.TextSize = 17
	button.TextWrapped = true
	button.Visible = touchControlsVisible
	button.ZIndex = 20
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 228, 218)
	stroke.Transparency = 0.48
	stroke.Thickness = 1.5
	stroke.Parent = button
	return button, stroke
end

local touchRunButton, runStroke = makeTouchButton("TouchRunHold", "RUN  »")
local touchJumpButton = makeTouchButton("TouchJump", "JUMP  ↑")
local touchPOVButton, povStroke = makeTouchButton("TouchPOV", "POV\n1ST")
local touchGlowButton = makeTouchButton("TouchDropGlowstick", "DROP\nGLOW")
touchPOVButton.TextSize = 13
touchPOVButton.Visible = touchControlsVisible and devAllowed
touchGlowButton.TextSize = 12

local lastControlViewport = Vector2.new(-1, -1)
local function applyTouchControlLayout()
	if not touchControlsVisible then return end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if viewport == lastControlViewport then return end
	lastControlViewport = viewport

	local phone = viewport.Y < 700
	local edge = phone and 22 or 28
	local buttonSize = phone and 64 or 76
	local gap = phone and 14 or 18
	local leftColumn = edge + buttonSize + (phone and 16 or 18)
	local flashlightHeight = phone and 106 or 128

	touchJumpButton.Position = UDim2.new(1, -edge, 1, -edge)
	touchJumpButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
	touchRunButton.Position = UDim2.new(1, -edge, 1, -(edge + buttonSize + gap))
	touchRunButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
	touchPOVButton.Position = UDim2.new(1, -leftColumn, 1, -(edge + flashlightHeight + (phone and 12 or 14)))
	touchPOVButton.Size = UDim2.fromOffset(phone and 58 or 72, phone and 48 or 54)
	touchGlowButton.Position = UDim2.new(1, -leftColumn, 1, -(edge + flashlightHeight + buttonSize + gap))
	touchGlowButton.Size = UDim2.fromOffset(phone and 58 or 72, phone and 58 or 72)
	touchRunButton.TextSize = phone and 16 or 18
	touchJumpButton.TextSize = phone and 15 or 17
end

applyTouchControlLayout()
RunService.RenderStepped:Connect(applyTouchControlLayout)

local touchSprintToggled = false
local function showRunEnabled(enabled)
	touchRunButton.BackgroundTransparency = enabled and 0.25 or 0.52
	touchRunButton.TextColor3 = enabled and Color3.fromRGB(125, 255, 175) or Color3.fromRGB(235, 238, 232)
	runStroke.Color = enabled and Color3.fromRGB(125, 255, 175) or Color3.fromRGB(220, 228, 218)
	touchRunButton.Text = enabled and "RUN  ON" or "RUN  »"
end

-- Tap once to sprint, tap again to stop. A held GUI touch no longer steals
-- the phone/tablet camera finger, so players can steer and look around freely.
touchRunButton.Activated:Connect(function()
	if not inRound() then return end
	touchSprintToggled = not touchSprintToggled
	touchSprintHeld = touchSprintToggled
	showRunEnabled(touchSprintToggled)
	refreshSprint()
end)

touchJumpButton.Activated:Connect(function()
	if not inRound() then return end
	local _, hum = currentChar()
	if hum and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

touchGlowButton.Activated:Connect(dropGlowstick)

local function firstPersonEnabled()
	return player:GetAttribute("DevCheatThirdPerson") ~= true
end

local function refreshPOVButton()
	local firstPerson = firstPersonEnabled()
	touchPOVButton.Text = firstPerson and "POV\n3RD" or "POV\n1ST"
	touchPOVButton.TextColor3 = firstPerson and Color3.fromRGB(130, 220, 255)
		or Color3.fromRGB(235, 238, 232)
	povStroke.Color = firstPerson and Color3.fromRGB(130, 220, 255)
		or Color3.fromRGB(220, 228, 218)
end

touchPOVButton.Activated:Connect(function()
	if not (devAllowed and inRound()) then return end
	local command = player:WaitForChild("PlayerScripts"):FindFirstChild("DevCheatCommand")
	if command and command:IsA("BindableEvent") then
		command:Fire("thirdPerson")
	end
end)
player:GetAttributeChangedSignal("DevCheatThirdPerson"):Connect(refreshPOVButton)
refreshPOVButton()

player.CharacterAdded:Connect(function()
	touchSprintToggled = false
	touchSprintHeld = false
	showRunEnabled(false)
	task.delay(0.75, refreshPOVButton)
end)

local staBg = Instance.new("Frame")
staBg.AnchorPoint = Vector2.new(0.5, 1)
staBg.Position = UDim2.new(0.5, 0, 1, -22)
staBg.Size = UDim2.new(0, BAR_W, 0, BAR_H)
staBg.BackgroundColor3 = Color3.new(0, 0, 0)
staBg.BackgroundTransparency = 1 -- starts hidden (full stamina)
staBg.BorderSizePixel = 0
staBg.Parent = gui
local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0, 5); bgc.Parent = staBg

local staFill = Instance.new("Frame")
staFill.AnchorPoint = Vector2.new(0, 0.5)
staFill.Position = UDim2.new(0, 2, 0.5, 0)
staFill.Size = UDim2.new(1, -4, 1, -4)
staFill.BackgroundColor3 = STA_FULL
staFill.BackgroundTransparency = 1
staFill.BorderSizePixel = 0
staFill.Parent = staBg
local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 4); fc.Parent = staFill

local barShown = 0 -- eased 0–1 visibility

RunService.Heartbeat:Connect(function(dt)
	if not inRound() then
		stamina = staminaMax()
		exhausted = false
		state = "walk"
		player:SetAttribute("Stamina", 1)
		barShown = 0
		staBg.BackgroundTransparency = 1
		staFill.BackgroundTransparency = 1
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local moving = root
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 2

	if devUnlimited() then
		stamina = staminaMax() -- dev cheat: never drains
		exhausted = false
	elseif state == "sprint" and moving then
		-- adrenaline: the Entity is (or was just) on you → stamina lasts 3x longer
		stamina = stamina - (SPRINT_DRAIN / (adrenalized() and ADRENALINE_MUL or 1)) * dt
		if stamina <= 0 then
			stamina = 0
			exhausted = true
			applySpeed() -- drop out of sprint
		end
	else
		stamina = math.min(staminaMax(), stamina + STAMINA_RECHARGE * dt)
		if exhausted and stamina >= STAMINA_RECOVER then
			exhausted = false
			applySpeed() -- sprint available again if shift still held
		end
	end

	local frac = stamina / staminaMax()
	-- publish stamina (0–1) so SoundController can drive the winded-breathing sound
	player:SetAttribute("Stamina", frac)

	-- bar: width + white→red colour (solid red while exhausted), fade with use
	staFill.Size = UDim2.new(frac, -4, 1, -4)
	staFill.BackgroundColor3 = exhausted and STA_EMPTY
		or STA_FULL:Lerp(STA_EMPTY, math.clamp(1 - frac, 0, 1) * 0.85)
	local wantShown = (frac < 0.999) and 1 or 0
	barShown = barShown + (wantShown - barShown) * math.clamp(dt * BAR_FADE, 0, 1)
	staBg.BackgroundTransparency = 1 - barShown * (1 - BAR_BG_ALPHA)
	staFill.BackgroundTransparency = 1 - barShown
end)

local function updateRoundState()
	local active = inRound()
	gui.Enabled = active
	if not active then
		lastGlowstickDrop = -math.huge
		shiftSprintHeld, touchSprintHeld = false, false
		sprinting, crouching = false, false
		touchSprintToggled = false
		showRunEnabled(false)
		applySpeed()
	end
end
player:GetAttributeChangedSignal("InRound"):Connect(updateRoundState)
updateRoundState()
