-- NoiseReporter
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "NoiseReporter"
-- Shift = sprint (loud), Ctrl = crouch (silent), walking = quiet.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ReportNoise")
local player = Players.LocalPlayer

local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16, 26, 8

-- loudness per movement state, 0..1 (server owns the real values)
local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }

local state = "walk"
local sprinting, crouching = false, false
local shiftSprintHeld, touchSprintHeld = false, false

-- stamina: sprint is limited, drains while sprinting, recovers otherwise
local STAMINA_MAX      = 100
local SPRINT_DRAIN     = 16   -- ~6s of sprint on a full bar
local STAMINA_RECHARGE = 10   -- recovers while not sprinting
local STAMINA_RECOVER  = 25   -- must reach this after exhaustion before sprinting again
local stamina, exhausted = STAMINA_MAX, false

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

local function currentChar()
	local char = player.Character
	return char, char and char:FindFirstChild("Humanoid")
end

local function applySpeed()
	local _, hum = currentChar()
	if not hum then return end

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
	if input.KeyCode == Enum.KeyCode.LeftShift then
		shiftSprintHeld = true; refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = true; applySpeed()
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
local BAR_W, BAR_H  = 230, 9
local STA_FULL      = Color3.fromRGB(235, 235, 235) -- fill at full stamina
local STA_EMPTY     = Color3.fromRGB(230, 80, 60)   -- fill near empty / exhausted
local BAR_BG_ALPHA  = 0.6   -- backdrop transparency when shown
local BAR_FADE      = 5     -- how fast the bar fades in / out

local gui = Instance.new("ScreenGui")
gui.Name = "StaminaGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Touch-only tap-to-toggle sprint. Keyboard Shift remains the only desktop path.
local touchRunButton = Instance.new("TextButton")
touchRunButton.Name = "TouchRunHold"
touchRunButton.AnchorPoint = Vector2.new(1, 1)
touchRunButton.Position = UDim2.new(1, -28, 1, -130)
touchRunButton.Size = UDim2.fromOffset(76, 76)
touchRunButton.BackgroundColor3 = Color3.fromRGB(8, 10, 9)
touchRunButton.BackgroundTransparency = 0.52
touchRunButton.BorderSizePixel = 0
touchRunButton.AutoButtonColor = false
touchRunButton.Font = Enum.Font.GothamBold
touchRunButton.Text = "RUN  »"
touchRunButton.TextColor3 = Color3.fromRGB(235, 238, 232)
touchRunButton.TextSize = 18
touchRunButton.Visible = UIS.TouchEnabled or (RunService:IsStudio() and workspace:GetAttribute("ForceTouchUI") == true)
touchRunButton.ZIndex = 20
touchRunButton.Parent = gui
local runCorner = Instance.new("UICorner")
runCorner.CornerRadius = UDim.new(1, 0)
runCorner.Parent = touchRunButton
local runStroke = Instance.new("UIStroke")
runStroke.Color = Color3.fromRGB(220, 228, 218)
runStroke.Transparency = 0.48
runStroke.Thickness = 1.5
runStroke.Parent = touchRunButton

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
player.CharacterAdded:Connect(function()
 touchSprintToggled = false
 touchSprintHeld = false
 showRunEnabled(false)
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
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local moving = root
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 2

	if devUnlimited() then
		stamina = STAMINA_MAX -- dev cheat: never drains
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
		stamina = math.min(STAMINA_MAX, stamina + STAMINA_RECHARGE * dt)
		if exhausted and stamina >= STAMINA_RECOVER then
			exhausted = false
			applySpeed() -- sprint available again if shift still held
		end
	end

	local frac = stamina / STAMINA_MAX
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
