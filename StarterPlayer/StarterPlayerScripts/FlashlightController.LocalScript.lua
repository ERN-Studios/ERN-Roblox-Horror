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
local HAND_SIDE = 0.25  -- small hand offset: avoids putting the light inside walls
local HAND_DOWN = -0.25
local HAND_FORWARD = 0.3
local SWAY = 14         -- higher = snappier, lower = more lag/sway

local mount, coreLight, spillLight
local on = false
local aimCF = nil
local aimSendClock = 0

local function buildMount()
	local camera = workspace.CurrentCamera
	if not camera then return end
	if mount then
		mount:Destroy()
		mount, coreLight, spillLight = nil, nil, nil
	end

	mount = Instance.new("Part")
	mount.Name = "FlashlightMount"
	mount.Size = Vector3.new(0.2, 0.2, 0.2)
	mount.Anchored = true
	mount.CanCollide = false
	mount.CanQuery = false
	mount.Transparency = 1

	-- tight bright core: the actual "beam" (tune Range to taste; ~27–35)
	coreLight = Instance.new("SpotLight")
	coreLight.Brightness = 1.2
	coreLight.Range = 38
	coreLight.Angle = 38
	coreLight.Color = Color3.fromRGB(255, 244, 214)
	coreLight.Shadows = false -- close props/walls must not self-occlude the beam
	coreLight.Enabled = on
	coreLight.Face = Enum.NormalId.Front
	coreLight.Parent = mount

	-- wide dim spill: what your eye reads as the "cone of light"
	spillLight = Instance.new("SpotLight")
	spillLight.Brightness = 0.3
	spillLight.Range = 45
	spillLight.Angle = 75
	spillLight.Color = Color3.fromRGB(255, 240, 205)
	spillLight.Shadows = false
	spillLight.Enabled = on
	spillLight.Face = Enum.NormalId.Front
	spillLight.Parent = mount

	-- A light parented below CurrentCamera can report Enabled while contributing
	-- nothing to world lighting. Keep the invisible local mount in Workspace and
	-- drive its CFrame from the camera instead; it remains client-only.
	mount.Parent = workspace
end

buildMount()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(buildMount)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Roblox's dynamic Lights can contribute very little on the extremely dark
-- prop albedos used by Level 1. A subtle, occluded near-field highlight keeps
-- the aimed surface/prop readable without glowing through walls or flattening
-- the whole maze. It follows the exact camera ray, including up/down.
local nearHighlight = Instance.new("Highlight")
nearHighlight.Name = "FlashlightNearField"
nearHighlight.FillColor = Color3.fromRGB(255, 232, 185)
nearHighlight.FillTransparency = 0.93
nearHighlight.OutlineTransparency = 1
nearHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
nearHighlight.Enabled = false
nearHighlight.Parent = workspace

-- bind AFTER the camera updates, so up/down tracking is exact
RunService:BindToRenderStep("MongoFlashlight", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not (mount and mount.Parent == workspace) then
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
		+ aimCF.LookVector * HAND_FORWARD

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

	-- The server mount lets other players see this flashlight. Suppress only the
	-- local player's replicated copy so their own camera never receives the same
	-- two SpotLights twice; this is a client-local property override.
	local replicatedSelf = workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId)
	if replicatedSelf then
		for _, item in ipairs(replicatedSelf:GetChildren()) do
			if item:IsA("Light") then item.Enabled = false end
		end
	end

	if on then
		local nearHit = workspace:Raycast(eye, aimCF.LookVector * 20, rayParams)
		if nearHit then
			local adornee = nearHit.Instance
			local decor = workspace:FindFirstChild("Decor")
			if decor and adornee:IsDescendantOf(decor) then
				local node = adornee
				while node.Parent and node.Parent ~= decor do node = node.Parent end
				adornee = node
			end
			nearHighlight.Adornee = adornee
			-- Keep the texture-readable near field, but at 30% of its old opacity.
			nearHighlight.FillTransparency = math.clamp(
				0.898 + nearHit.Distance / 500, 0.904, 0.946)
			nearHighlight.Enabled = true
		else
			nearHighlight.Enabled = false
		end
	else
		nearHighlight.Enabled = false
	end
	if on then
		aimSendClock += dt
		if aimSendClock >= 1 / 15 then
			aimSendClock = 0
			remote:FireServer("aim", mount.CFrame)
		end
	else
		aimSendClock = 0
	end
end)

-- ── battery ───────────────────────────────────────────────
-- No HUD at all. The player is warned the battery is low by the beam itself
-- flickering: one blink at 50%, a few blinks at 25%.
local BATTERY_MAX      = 100
local DRAIN_PER_SEC    = 1.667 -- ~60s of continuous light on a full charge
local RECHARGE_PER_SEC = 1.5  -- slowly recovers while the light is OFF
local MIN_TO_TURN_ON   = 5    -- can't switch on below this (must recharge a bit)
local battery = BATTERY_MAX
local warned50, warned25 = false, false

-- bottom-of-screen pop-up (shown when the battery dies)
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "FlashlightPopup"
popupGui.ResetOnSpawn = false
popupGui.Enabled = player:GetAttribute("InRound") == true
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

-- Complete flashlight silhouette: black body, battery window in the middle and
-- three yellow rays at the front. The art is centred inside one fixed hit box so
-- rotation cannot make the touch target or visible torch drift off-centre.
local batBody = Instance.new("Frame")
batBody.Name = "FlashlightPower"
batBody.AnchorPoint = Vector2.new(0, 1)
batBody.Position = UDim2.new(0, 12, 1, -10)
batBody.Size = UDim2.new(0, 72, 0, 136)
batBody.BackgroundTransparency = 1
batBody.BorderSizePixel = 0
batBody.Parent = popupGui

-- Touch-only hit target over the existing flashlight symbol. It remains absent
-- from mouse/keyboard devices, so the PC F-key control is unchanged.
local touchFlashButton = Instance.new("TextButton")
touchFlashButton.Name = "TouchFlashlightToggle"
touchFlashButton.Size = UDim2.fromScale(1, 1)
touchFlashButton.BackgroundTransparency = 1
touchFlashButton.Text = ""
touchFlashButton.AutoButtonColor = false
touchFlashButton.Active = true
touchFlashButton.Selectable = false
touchFlashButton.Visible = UIS.TouchEnabled or (RunService:IsStudio() and workspace:GetAttribute("ForceTouchUI") == true)
touchFlashButton.ZIndex = 20
touchFlashButton.Parent = batBody

local torch = Instance.new("Frame")
torch.Name = "Silhouette"
torch.AnchorPoint = Vector2.new(0.5, 0.5)
torch.Position = UDim2.fromScale(0.5, 0.5)
torch.Size = UDim2.new(0, 160, 0, 48)
torch.BackgroundTransparency = 1
torch.Rotation = -90 -- upright, with the lens/rays at the top
torch.Parent = batBody
local torchScale = Instance.new("UIScale")
torchScale.Scale = 0.72
torchScale.Parent = torch

local function outline(frame, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 236, 240)
	stroke.Thickness = 2
	stroke.Parent = frame
end

local tail = Instance.new("Frame")
tail.Position = UDim2.new(0, 3, 0, 13)
tail.Size = UDim2.new(0, 17, 0, 24)
tail.BackgroundColor3 = Color3.fromRGB(8, 9, 11)
tail.BorderSizePixel = 0
tail.Parent = torch
outline(tail, 5)

local handle = Instance.new("Frame")
handle.Position = UDim2.new(0, 14, 0, 10)
handle.Size = UDim2.new(0, 100, 0, 30)
handle.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
handle.BorderSizePixel = 0
handle.Parent = torch
outline(handle, 7)

local batteryWindow = Instance.new("Frame")
batteryWindow.Position = UDim2.new(0, 26, 0, 6)
batteryWindow.Size = UDim2.new(0, 53, 0, 18)
batteryWindow.BackgroundColor3 = Color3.fromRGB(26, 28, 33)
batteryWindow.BorderSizePixel = 0
batteryWindow.Parent = handle
outline(batteryWindow, 4)

local barHolder = Instance.new("Frame")
barHolder.Position = UDim2.new(0, 4, 0, 4)
barHolder.Size = UDim2.new(1, -8, 1, -8)
barHolder.BackgroundTransparency = 1
barHolder.Parent = batteryWindow
local barList = Instance.new("UIListLayout")
barList.FillDirection = Enum.FillDirection.Horizontal
barList.Padding = UDim.new(0, 3)
barList.HorizontalAlignment = Enum.HorizontalAlignment.Center
barList.VerticalAlignment = Enum.VerticalAlignment.Center
barList.Parent = barHolder
local batBars = {}
for i = 1, 5 do
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 7, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	bar.BorderSizePixel = 0
	bar.LayoutOrder = i
	bar.Parent = barHolder
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 2)
	bc.Parent = bar
	batBars[i] = bar
end

local neck = Instance.new("Frame")
neck.Position = UDim2.new(0, 109, 0, 8)
neck.Size = UDim2.new(0, 11, 0, 34)
neck.BackgroundColor3 = Color3.fromRGB(9, 10, 12)
neck.BorderSizePixel = 0
neck.Parent = torch
outline(neck, 4)

local flashHead = Instance.new("Frame")
flashHead.Position = UDim2.new(0, 116, 0, 4)
flashHead.Size = UDim2.new(0, 27, 0, 42)
flashHead.BackgroundColor3 = Color3.fromRGB(8, 9, 11)
flashHead.BorderSizePixel = 0
flashHead.Parent = torch
outline(flashHead, 6)

local lens = Instance.new("Frame")
lens.Position = UDim2.new(1, -7, 0, 5)
lens.Size = UDim2.new(0, 8, 1, -10)
lens.BackgroundColor3 = Color3.fromRGB(255, 218, 82)
lens.BackgroundTransparency = on and 0 or 0.7
lens.BorderSizePixel = 0
lens.Parent = flashHead
local lensCorner = Instance.new("UICorner")
lensCorner.CornerRadius = UDim.new(0, 4)
lensCorner.Parent = lens

local lightRays = {}
for index, spec in ipairs({ { 146, 8, -10 }, { 149, 22, 0 }, { 146, 36, 10 } }) do
	local ray = Instance.new("Frame")
	ray.Name = "PowerRay" .. index
	ray.Position = UDim2.new(0, spec[1], 0, spec[2])
	ray.Size = UDim2.new(0, index == 2 and 18 or 14, 0, 4)
	ray.BackgroundColor3 = Color3.fromRGB(255, 215, 72)
	ray.BorderSizePixel = 0
	ray.Rotation = spec[3]
	ray.Visible = on
	ray.Parent = torch
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = ray
	lightRays[#lightRays + 1] = ray
end

local BAT_FULL  = Color3.fromRGB(245, 245, 245)
local BAT_EMPTY = Color3.fromRGB(235, 60, 50)

local function setLights(state)
 on = state
	if coreLight then coreLight.Enabled = state end
	if spillLight then spillLight.Enabled = state end
 lens.BackgroundTransparency = state and 0 or 0.72
 for _, ray in ipairs(lightRays) do ray.Visible = state end
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
	if player:GetAttribute("InRound") ~= true then return end
	if not alive() then return end -- dead / spectating: no flashlight of your own
	if on then
		setLights(false)
	elseif battery > MIN_TO_TURN_ON then
		setLights(true)
	end
end

local lastTouchToggle = 0
touchFlashButton.InputBegan:Connect(function(input)
 local touch = input.UserInputType == Enum.UserInputType.Touch
 local studioMouse = RunService:IsStudio() and workspace:GetAttribute("ForceTouchUI") == true
  and input.UserInputType == Enum.UserInputType.MouseButton1
 if not (touch or studioMouse) or os.clock() - lastTouchToggle < 0.2 then return end
 lastTouchToggle = os.clock()
 toggle()
end)

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then toggle() end
end)

-- on (re)spawn: light off, battery back to FULL (so it refills each round reset),
-- and kill the beam the instant you die so a dead spectator isn't shining it
local boundCharacter
local function bindCharacter(char)
	if boundCharacter == char then return end
	boundCharacter = char
	setLights(false)
	battery = BATTERY_MAX
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function() setLights(false) end)
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then task.spawn(bindCharacter, player.Character) end

local function updateRoundVisibility()
	local inRound = player:GetAttribute("InRound") == true
	popupGui.Enabled = inRound
	if not inRound and on then setLights(false) end
	if not inRound then
		nearHighlight.Enabled = false
		popup.Visible = false
	end
end
player:GetAttributeChangedSignal("InRound"):Connect(updateRoundVisibility)
updateRoundVisibility()

-- ── teammates' flashlights (visible to YOU) ───────────────
-- Your own beam lives on your camera, so others can't see it — but everyone's
-- on/off flag replicates (FlashlightSync's FlashlightOn BoolValue). Attach a
-- beam to every OTHER character's head that follows their flag, so you see
-- teammates' lights sweeping around the maze.
local mateBeams = {} -- [character] = { core = ..., spill = ... }

local function attachMateBeam(char)
	task.spawn(function()
		local head = char:WaitForChild("Head", 30)
		if not head then return end
		if head:FindFirstChild("MateBeamCore") then return end

		local core = Instance.new("SpotLight")
		core.Name = "MateBeamCore"
		core.Brightness = 1.2
		core.Range = 32
		core.Angle = 30
		core.Color = Color3.fromRGB(255, 244, 214)
		core.Shadows = true
		core.Face = Enum.NormalId.Front -- follows where their head points
		core.Enabled = false
		core.Parent = head

		local spill = Instance.new("SpotLight")
		spill.Name = "MateBeamSpill"
		spill.Brightness = 0.24
		spill.Range = 40
		spill.Angle = 70
		spill.Color = Color3.fromRGB(255, 240, 205)
		spill.Shadows = false
		spill.Face = Enum.NormalId.Front
		spill.Enabled = false
		spill.Parent = head

		mateBeams[char] = { core = core, spill = spill }
		char.AncestryChanged:Connect(function(_, parent)
			if not parent then mateBeams[char] = nil end -- character gone
		end)
	end)
end

local function hookMate(p)
	if p == player then return end -- your own beam is the camera torch above
	if p.Character then attachMateBeam(p.Character) end
	p.CharacterAdded:Connect(attachMateBeam)
end
Players.PlayerAdded:Connect(hookMate)
for _, p in ipairs(Players:GetPlayers()) do hookMate(p) end
Players.PlayerRemoving:Connect(function(p)
	if p.Character then mateBeams[p.Character] = nil end
end)

-- drive every mate beam from its owner's replicated flag EVERY frame — no
-- one-shot event binding to go stale, and it works exactly the same whether
-- you're alive, dead, or spectating (the beams live on THEIR heads, not yours)
RunService.Heartbeat:Connect(function()
	for char, beams in pairs(mateBeams) do
		local flag = char:FindFirstChild("FlashlightOn")
		local hum = char:FindFirstChildOfClass("Humanoid")
		local shine = flag ~= nil and flag.Value == true
			and hum ~= nil and hum.Health > 0
		beams.core.Enabled = shine
		beams.spill.Enabled = shine
	end
end)

-- dev cheat confirmation (also proves this script version is the one running)
player:GetAttributeChangedSignal("DevUnlimited"):Connect(function()
	local active = player:GetAttribute("DevUnlimited") == true
	if active then battery = BATTERY_MAX end
	print("[Flashlight] unlimited battery " .. (active and "ON" or "OFF"))
end)

-- drain while on, recharge while off; die at empty
RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("DevUnlimited") == true then
		battery = BATTERY_MAX -- dev cheat (DevCheats, U key): never drains
	elseif on then
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
