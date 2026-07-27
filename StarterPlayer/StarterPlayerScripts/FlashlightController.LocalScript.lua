-- FlashlightController  (v4 — pitch-stable handheld beam)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "FlashlightController"
-- REPLACES the old FlashlightController entirely — paste over the old contents.
--
-- F toggles. The beam points exactly where you look (up/down included) while the
-- light source sits beside-and-below your eye like a torch in your hand. The hand
-- position is HORIZONTAL-only, so pitching down never drives the light into the
-- floor (that was the old "beam disappears looking down" bug).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local player = Players.LocalPlayer

UIS.MouseIconEnabled = false -- no cursor

-- how the torch is held, relative to the eye (horizontal offset + drop)
local HAND_SIDE = 0.9   -- studs to the right
local HAND_DOWN = -0.7  -- studs below eye level
local SWAY = 14         -- higher = snappier, lower = more lag/sway

local mount, coreLight, spillLight
local on = false
local aimCF = nil

local function buildMount()
	local camera = workspace.CurrentCamera
	if not camera then return end

	mount = Instance.new("Part")
	mount.Name = "FlashlightMount"
	mount.Size = Vector3.new(0.2, 0.2, 0.2)
	mount.Anchored = true
	mount.CanCollide = false
	mount.CanQuery = false
	mount.Transparency = 1

	-- tight bright core: the actual "beam" (tune Range to taste; ~27–35)
	coreLight = Instance.new("SpotLight")
	coreLight.Brightness = 5
	coreLight.Range = 35
	coreLight.Angle = 32
	coreLight.Color = Color3.fromRGB(255, 244, 214)
	coreLight.Shadows = true
	coreLight.Enabled = on
	coreLight.Face = Enum.NormalId.Front
	coreLight.Parent = mount

	-- wide dim spill: what your eye reads as the "cone of light"
	spillLight = Instance.new("SpotLight")
	spillLight.Brightness = 1
	spillLight.Range = 45
	spillLight.Angle = 75
	spillLight.Color = Color3.fromRGB(255, 240, 205)
	spillLight.Shadows = false
	spillLight.Enabled = on
	spillLight.Face = Enum.NormalId.Front
	spillLight.Parent = mount

	mount.Parent = camera
end

buildMount()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(buildMount)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- bind AFTER the camera updates, so up/down tracking is exact
RunService:BindToRenderStep("MongoFlashlight", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not (mount and mount.Parent == camera) then
		buildMount()
		if not mount then return end
	end

	-- smooth the aim so the beam trails your turn like a held object
	aimCF = aimCF and aimCF:Lerp(camera.CFrame, math.clamp(dt * SWAY, 0, 1))
		or camera.CFrame

	local eye = camera.CFrame.Position

	-- hand position: beside & below the eye, but using a HORIZONTAL-only right
	-- vector + a world-space drop — so pitching up/down never pushes the light
	-- into the floor or ceiling
	local right = aimCF.RightVector
	local rightFlat = Vector3.new(right.X, 0, right.Z)
	rightFlat = (rightFlat.Magnitude > 0.001) and rightFlat.Unit or Vector3.new(1, 0, 0)
	local handPos = eye + rightFlat * HAND_SIDE + Vector3.new(0, HAND_DOWN, 0)

	-- never originate the light inside a wall (kills close-range illumination)
	local filter = { camera }
	if player.Character then table.insert(filter, player.Character) end
	rayParams.FilterDescendantsInstances = filter
	local toHand = handPos - eye
	local hit = workspace:Raycast(eye, toHand, rayParams)
	if hit then
		handPos = eye + toHand.Unit * math.max((hit.Position - eye).Magnitude - 0.3, 0)
	end

	-- position at the hand, but point EXACTLY where the camera looks
	mount.CFrame = aimCF.Rotation + handPos
end)

-- ── battery ───────────────────────────────────────────────
-- No HUD at all. The player is warned the battery is low by the beam itself
-- flickering: one blink at 50%, a few blinks at 25%.
local BATTERY_MAX      = 100
local DRAIN_PER_SEC    = 3.3  -- ~30s of continuous light on a full charge
local RECHARGE_PER_SEC = 1.5  -- slowly recovers while the light is OFF
local MIN_TO_TURN_ON   = 5    -- can't switch on below this (must recharge a bit)
local battery = BATTERY_MAX
local warned50, warned25 = false, false

-- bottom-of-screen pop-up (shown when the battery dies)
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "FlashlightPopup"
popupGui.ResetOnSpawn = false
popupGui.Parent = player:WaitForChild("PlayerGui")
local popup = Instance.new("TextLabel")
popup.AnchorPoint = Vector2.new(0.5, 1)
popup.Position = UDim2.new(0.5, 0, 1, -26)
popup.Size = UDim2.new(0, 360, 0, 34)
popup.BackgroundColor3 = Color3.new(0, 0, 0)
popup.BackgroundTransparency = 0.35
popup.BorderSizePixel = 0
popup.Font = Enum.Font.Gotham
popup.TextScaled = true
popup.TextColor3 = Color3.fromRGB(235, 95, 75)
popup.Text = ""
popup.Visible = false
popup.Parent = popupGui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 6); pc.Parent = popup

local popupToken = 0
local function showPopup(text, seconds)
	popup.Text = text
	popup.Visible = true
	popupToken += 1
	local mine = popupToken
	task.delay(seconds or 2.5, function()
		if popupToken == mine then popup.Visible = false end
	end)
end

-- battery icon (5 bars, each = 20%; bars empty as it drains and the remaining
-- ones shift white → red), bottom-left corner
local batBody = Instance.new("Frame")
batBody.Name = "Battery"
batBody.AnchorPoint = Vector2.new(0, 1)
batBody.Position = UDim2.new(0, 16, 1, -16)
batBody.Size = UDim2.new(0, 78, 0, 28)
batBody.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
batBody.BackgroundTransparency = 0.35
batBody.BorderSizePixel = 0
batBody.Parent = popupGui
local batStroke = Instance.new("UIStroke")
batStroke.Color = Color3.fromRGB(225, 225, 230); batStroke.Thickness = 2; batStroke.Parent = batBody
local batCorner = Instance.new("UICorner"); batCorner.CornerRadius = UDim.new(0, 4); batCorner.Parent = batBody
-- positive terminal nub on the right
local nub = Instance.new("Frame")
nub.AnchorPoint = Vector2.new(0, 0.5)
nub.Position = UDim2.new(1, 2, 0.5, 0)
nub.Size = UDim2.new(0, 4, 0, 12)
nub.BackgroundColor3 = Color3.fromRGB(225, 225, 230); nub.BorderSizePixel = 0
nub.Parent = batBody
local nubCorner = Instance.new("UICorner"); nubCorner.CornerRadius = UDim.new(0, 2); nubCorner.Parent = nub
-- 5 bar cells laid out left→right
local barHolder = Instance.new("Frame")
barHolder.Size = UDim2.new(1, -8, 1, -8)
barHolder.Position = UDim2.new(0, 4, 0, 4)
barHolder.BackgroundTransparency = 1
barHolder.Parent = batBody
local barList = Instance.new("UIListLayout")
barList.FillDirection = Enum.FillDirection.Horizontal
barList.Padding = UDim.new(0, 3)
barList.HorizontalAlignment = Enum.HorizontalAlignment.Left
barList.VerticalAlignment = Enum.VerticalAlignment.Center
barList.Parent = barHolder
local batBars = {}
for i = 1, 5 do
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 10, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	bar.BorderSizePixel = 0
	bar.Parent = barHolder
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 2); bc.Parent = bar
	batBars[i] = bar
end

local BAT_FULL  = Color3.fromRGB(245, 245, 245) -- white at full
local BAT_EMPTY = Color3.fromRGB(235, 60, 50)   -- red near empty

local function setLights(state)
	on = state
	if coreLight then coreLight.Enabled = state end
	if spillLight then spillLight.Enabled = state end
	remote:FireServer(state)
end

-- a low-battery WARNING flicker: briefly drop the beam `times` times then
-- restore it. Purely visual — doesn't change the real on/off state, so it
-- doesn't spam the server or affect the entity's sight bonus.
local function warnBlink(times)
	if not on then return end
	task.spawn(function()
		for _ = 1, times do
			if not on then break end
			if coreLight then coreLight.Enabled = false end
			if spillLight then spillLight.Enabled = false end
			task.wait(0.08)
			if coreLight then coreLight.Enabled = on end
			if spillLight then spillLight.Enabled = on end
			task.wait(0.14)
		end
	end)
end

local function alive()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function toggle()
	if not alive() then return end -- dead / spectating: no flashlight of your own
	if on then
		setLights(false)
	elseif battery > MIN_TO_TURN_ON then
		setLights(true)
	end
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then toggle() end
end)

-- on (re)spawn: light off, battery back to FULL (so it refills each round reset),
-- and kill the beam the instant you die so a dead spectator isn't shining it
player.CharacterAdded:Connect(function(char)
	setLights(false)
	battery = BATTERY_MAX
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function() setLights(false) end)
end)

-- drain while on, recharge while off; die at empty
RunService.Heartbeat:Connect(function(dt)
	if on then
		battery = battery - DRAIN_PER_SEC * dt
		if battery <= 0 then
			battery = 0
			setLights(false) -- (sets `on` false, so this fires once at the drain-out)
			showPopup("Flashlight dead — let it recharge", 3)
		end
	else
		battery = math.min(BATTERY_MAX, battery + RECHARGE_PER_SEC * dt)
	end

	-- re-arm the warnings once it recharges back up (small hysteresis)
	if battery > 55 then warned50 = false end
	if battery > 30 then warned25 = false end
	-- fire each warning once as the battery falls past the threshold
	if on and battery <= 25 and not warned25 then
		warned25 = true
		warnBlink(3)
	elseif on and battery <= 50 and not warned50 then
		warned50 = true
		warnBlink(1)
	end

	-- battery bars: fill count + colour (white full → red near empty)
	local filled = math.clamp(math.ceil(battery / 20), 0, 5)
	local col = BAT_FULL:Lerp(BAT_EMPTY, math.clamp(1 - battery / 100, 0, 1))
	for i, bar in ipairs(batBars) do
		if i <= filled then
			bar.BackgroundTransparency = 0
			bar.BackgroundColor3 = col
		else
			bar.BackgroundTransparency = 0.7
			bar.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
		end
	end
end)