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
local UIDevice = require(RS:WaitForChild("UIDevice"))
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
	local character, hum = currentChar()
	if not hum then return end
	local desiredSpeed
	if not inRound() then
		-- Lobby sprint is unlimited: it uses the regular sprint speed without
		-- touching the level stamina/exhaustion state.
		state = sprinting and "sprint" or "walk"
		desiredSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
		character:SetAttribute("Level2_DesiredWalkSpeed", desiredSpeed)
		hum.WalkSpeed = desiredSpeed
		return
	end

	if crouching then
		state = "crouch"
		desiredSpeed = CROUCH_SPEED
	elseif sprinting and stamina > 0 and not exhausted then
		state = "sprint"
		desiredSpeed = SPRINT_SPEED
	else
		state = "walk"
		desiredSpeed = WALK_SPEED
	end
	-- Publish the intended speed separately from WalkSpeed. Deferred property
	-- signals can observe the slide controller's re-zero instead of this write;
	-- the attribute gives every movement lock an unambiguous restore target.
	character:SetAttribute("Level2_DesiredWalkSpeed", desiredSpeed)
	hum.WalkSpeed = desiredSpeed
end

local function refreshSprint()
	sprinting = shiftSprintHeld or touchSprintHeld
	applySpeed()
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftSprintHeld = true; refreshSprint()
	elseif inRound() and input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = true; applySpeed()
	elseif inRound() and (input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.ButtonX) then
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
		if not inRound() or workspace:GetAttribute("SelectedLevel") ~= 1 then continue end
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
-- Roblox's TouchGui sits at DisplayOrder 5. This cluster used to sit at the
-- default 0, which put our JUMP button UNDERNEATH Roblox's own -- two jump
-- buttons stacked to within nine pixels, with the ungated default one taking
-- every tap. We now own the jump control outright and draw above the default.
gui.DisplayOrder = 60
-- Keep the container alive in the lobby for the mobile RUN button. The actual
-- stamina bar remains fully hidden there, and the level-only controls are
-- hidden explicitly by updateRoundState().
gui.Enabled = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Compact touch control cluster. Keyboard/controller paths remain unchanged.
-- RUN and JUMP form the right column; POV sits above the upright flashlight
-- immediately to their left, keeping the camera-dragging area clear.
-- Form factor, not last input, and re-read on every UIDevice.Changed rather
-- than captured once at load.
local function touchControls() return UIDevice.IsTouch() end

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
	button.Visible = touchControls()
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
touchPOVButton.Visible = touchControls() and devAllowed
touchGlowButton.TextSize = 12

-- The whole cluster is laid out from UIDevice's reserved control column, so
-- every other HUD element in the game can avoid exactly the rectangle these
-- buttons actually occupy. The flashlight toggle joins this column too (it used
-- to sit bottom-left, inside the movement thumbstick's activation region).
local FLASHLIGHT_SLOT_HEIGHT = 58
local function applyTouchControlLayout()
	if not touchControls() then return end
	local layout = UIDevice.Layout()
	local tablet = layout.Class == "tablet"
	local edge = tablet and 26 or 22
	local buttonSize = tablet and 76 or 64
	local gap = tablet and 18 or 14
	local secondColumn = edge + buttonSize + (tablet and 18 or 16)
	local bottom = edge + (layout.Height - layout.SafeBottom > edge and 0 or 0)

	touchJumpButton.Position = UDim2.new(1, -edge, 1, -bottom)
	touchJumpButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
	-- In a round our JUMP owns the bottom-right slot and Roblox's is suppressed,
	-- so RUN sits directly above it. In the LOBBY the default jump is restored
	-- (it is the only jump there), and it occupies roughly the slot ours would
	-- have -- so RUN lifts clear of the engine's own button rather than sitting
	-- on top of it.
	local runStack = bottom + buttonSize + gap
	if not inRound() then
		local jumpZone = layout.Zones.Jump
		runStack = math.max(runStack, layout.Height - jumpZone.Top + gap)
	end
	touchRunButton.Position = UDim2.new(1, -edge, 1, -runStack)
	touchRunButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
	-- Second column: GLOW on top of POV, both clear of the jump/run column and
	-- of the flashlight slot that FlashlightController now occupies below them.
	touchPOVButton.Position = UDim2.new(1, -secondColumn,
		1, -(bottom + FLASHLIGHT_SLOT_HEIGHT + (tablet and 14 or 12)))
	touchPOVButton.Size = UDim2.fromOffset(tablet and 72 or 58, tablet and 54 or 48)
	touchGlowButton.Position = UDim2.new(1, -secondColumn,
		1, -(bottom + FLASHLIGHT_SLOT_HEIGHT + buttonSize + gap))
	touchGlowButton.Size = UDim2.fromOffset(tablet and 72 or 58, tablet and 72 or 58)
	touchRunButton.TextSize = tablet and 18 or 16
	touchJumpButton.TextSize = tablet and 17 or 15
end

applyTouchControlLayout()
UIDevice.Changed:Connect(applyTouchControlLayout)

-- This game draws its own JUMP, with round/death/hiding gating the default
-- control knows nothing about, so Roblox's is suppressed while ours is the
-- owner. Ownership is per-round, NOT permanent: the cluster deliberately
-- provides no jump in the lobby, and suppressing the default there as well
-- would leave a touch player in the tunnel hub with no way to jump at all.
-- updateRoundState below re-evaluates this on every state change.

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
	touchSprintToggled = not touchSprintToggled
	touchSprintHeld = touchSprintToggled
	showRunEnabled(touchSprintToggled)
	refreshSprint()
end)

touchJumpButton.Activated:Connect(function()
	if not inRound() then return end
	local character, hum = currentChar()
	if character and character:GetAttribute("Level2_ForcedSliding") == true then return end
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
-- The fixed 300px bar overflowed a 375-wide portrait screen and sat on top of
-- the movement zone. It is now capped to the safe width and lifted into the
-- content band on touch.
local function applyStaminaLayout()
	local layout = UIDevice.Layout()
	staBg.AnchorPoint = Vector2.new(0.5, 1)
	if not layout.IsTouch then
		staBg.Size = UDim2.new(0, BAR_W, 0, BAR_H)
		staBg.Position = UDim2.new(0.5, 0, 1, -22)
		return
	end
	-- On touch the bar lives in the lane BETWEEN the two movement zones. A
	-- landscape phone leaves only about 65 vertical pixels clear above the
	-- controls -- not enough to share with the alert banner -- but the corridor
	-- down the middle is free at any height.
	local corridor = layout.Corridor
	if corridor.Width >= 120 then
		local width = math.min(BAR_W, corridor.Width)
		staBg.Size = UDim2.new(0, width, 0, BAR_H)
		staBg.Position = UDim2.new(0, (corridor.Left + corridor.Right) * .5,
			1, -UIDevice.BottomOffsetFor(gui, layout.Height - 18))
	else
		-- Portrait: the corridor is narrow, so fall back to the safe band.
		staBg.Size = UDim2.new(0, math.min(BAR_W, layout.SafeRight - layout.SafeLeft), 0, BAR_H)
		staBg.Position = UDim2.new(0.5, 0,
			1, -UIDevice.BottomOffsetFor(gui, layout.SafeBottom - 10))
	end
end
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
applyStaminaLayout()
UIDevice.Changed:Connect(applyStaminaLayout)

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
	elseif state == "sprint" and moving
		and not (char and char:GetAttribute("Level2_ForcedSliding") == true) then
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

-- Every state in which the movement cluster must not be usable. Hiding alone is
-- not enough: a TextButton left Active keeps swallowing taps through a
-- transparent background, so all four go through UIDevice.SetInteractive, which
-- clears Active/Selectable/Modal as well as Visible.
local function controlsAvailable()
	if not touchControls() then return false end
	if not inRound() then return false end
	if player:GetAttribute("Escaped") == true then return false end
	if player:GetAttribute("Level3_Hiding") == true then return false end
	if player:GetAttribute("Spectating") == true then return false end
	-- A modal owns the screen: the store terminal, the dev phone, the Zyntra
	-- re-entry prompt, or the post-round panel.
	if player:GetAttribute("ZyntraStoreOpen") == true then return false end
	if player:GetAttribute("DevPhoneOpen") == true then return false end
	if player:GetAttribute("ZyntraReentryOpen") == true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	return true
end

local function updateRoundState()
	local active = inRound()
	local usable = controlsAvailable()
	gui.Enabled = true
	-- RUN stays available in the lobby (it is how a player sprints to a station)
	-- but is gated on every other unavailable state once a round starts.
	UIDevice.SetInteractive(touchRunButton, touchControls() and (usable or not active))
	UIDevice.SetInteractive(touchJumpButton, usable)
	UIDevice.SetInteractive(touchPOVButton, usable and devAllowed)
	UIDevice.SetInteractive(touchGlowButton, usable)
	-- Own the jump control only while in a round. In the lobby the default
	-- touch jump comes back, because that is the only jump there is there.
	UIDevice.SuppressDefaultJump(touchControls() and active)
	-- The RUN slot depends on whether the engine's jump button is showing.
	applyTouchControlLayout()
	-- Stamina is only meaningful while the player is the one running. Dead,
	-- escaped or spectating, the bar is stale information sitting in the same
	-- band as the spectate caption, so it stands down with the controls.
	staBg.Visible = active
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Spectating") ~= true
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
for _, attribute in ipairs({"Escaped", "Level3_Hiding", "Spectating",
	"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(updateRoundState)
end
UIDevice.Changed:Connect(updateRoundState)
local function bindLife(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then humanoid.Died:Connect(updateRoundState) end
	updateRoundState()
end
if player.Character then task.spawn(bindLife, player.Character) end
player.CharacterAdded:Connect(bindLife)
updateRoundState()
