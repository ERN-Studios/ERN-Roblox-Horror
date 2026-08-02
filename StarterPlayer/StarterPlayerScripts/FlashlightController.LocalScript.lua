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
local DRAIN_PER_SEC    = 1.667 -- ~60s of continuous light on a full charge
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

-- simple angled flashlight silhouette with live power bars in the handle
local batBody = Instance.new("Frame")
batBody.Name = "FlashlightPower"
batBody.AnchorPoint = Vector2.new(0, 1)
batBody.Position = UDim2.new(0, 26, 1, -22)
batBody.Size = UDim2.new(0, 72, 0, 110)
batBody.BackgroundTransparency = 1
batBody.BorderSizePixel = 0
batBody.Rotation = 0
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

-- one broad lamp head: no stacked razor-like layers
local flashHead = Instance.new("Frame")
flashHead.Position = UDim2.new(0, 8, 0, 0)
flashHead.Size = UDim2.new(0, 52, 0, 34)
flashHead.BackgroundColor3 = Color3.fromRGB(12, 13, 15)
flashHead.BorderSizePixel = 0
flashHead.Parent = batBody
local headCorner = Instance.new("UICorner")
headCorner.CornerRadius = UDim.new(0, 7)
headCorner.Parent = flashHead
local headStroke = Instance.new("UIStroke")
headStroke.Color = Color3.fromRGB(238, 238, 240)
headStroke.Thickness = 2
headStroke.Parent = flashHead

-- three tiny light rays: one centered and two angled
local rayColor = Color3.fromRGB(255, 238, 150)
local lightRays = {}
local function makeRay(x, y, rotation, height)
 local ray = Instance.new("Frame")
 ray.AnchorPoint = Vector2.new(0.5, 1)
 ray.Position = UDim2.new(0, x, 0, y)
 ray.Size = UDim2.new(0, 3, 0, height)
 ray.BackgroundColor3 = rayColor
 ray.BorderSizePixel = 0
 ray.Rotation = rotation
 ray.Visible = on -- off by default; becomes visible with the real beam
 ray.Parent = batBody
 local rc = Instance.new("UICorner")
 rc.CornerRadius = UDim.new(1, 0)
 rc.Parent = ray
 lightRays[#lightRays + 1] = ray
end
makeRay(34, -8, 0, 10)
makeRay(21, -6, -32, 8)
makeRay(47, -6, 32, 8)

-- short neck flowing directly into the grip
local neck = Instance.new("Frame")
neck.Position = UDim2.new(0, 22, 0, 31)
neck.Size = UDim2.new(0, 24, 0, 12)
neck.BackgroundColor3 = Color3.fromRGB(12, 13, 15)
neck.BorderSizePixel = 0
neck.Parent = batBody
local neckStroke = Instance.new("UIStroke")
neckStroke.Color = Color3.fromRGB(238, 238, 240)
neckStroke.Thickness = 2
neckStroke.Parent = neck

local handle = Instance.new("Frame")
handle.Position = UDim2.new(0, 20, 0, 40)
handle.Size = UDim2.new(0, 28, 0, 70)
handle.BackgroundColor3 = Color3.fromRGB(12, 13, 15)
handle.BorderSizePixel = 0
handle.Parent = batBody
local handleCorner = Instance.new("UICorner")
handleCorner.CornerRadius = UDim.new(0, 7)
handleCorner.Parent = handle
local handleStroke = Instance.new("UIStroke")
handleStroke.Color = Color3.fromRGB(238, 238, 240)
handleStroke.Thickness = 2
handleStroke.Parent = handle

local barHolder = Instance.new("Frame")
barHolder.Size = UDim2.new(1, -10, 1, -12)
barHolder.Position = UDim2.new(0, 5, 0, 6)
barHolder.BackgroundTransparency = 1
barHolder.Parent = handle
local barList = Instance.new("UIListLayout")
barList.FillDirection = Enum.FillDirection.Vertical
barList.Padding = UDim.new(0, 3)
barList.HorizontalAlignment = Enum.HorizontalAlignment.Center
barList.VerticalAlignment = Enum.VerticalAlignment.Center
barList.Parent = barHolder
local batBars = {}
for i = 1, 5 do
 local bar = Instance.new("Frame")
 bar.Size = UDim2.new(1, 0, 0, 8)
 bar.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
 bar.BorderSizePixel = 0
 bar.LayoutOrder = 6 - i
 bar.Parent = barHolder
 local bc = Instance.new("UICorner")
 bc.CornerRadius = UDim.new(0, 3)
 bc.Parent = bar
 batBars[i] = bar
end

local BAT_FULL  = Color3.fromRGB(245, 245, 245)
local BAT_EMPTY = Color3.fromRGB(235, 60, 50)

local function setLights(state)
 on = state
 if coreLight then coreLight.Enabled = state end
 if spillLight then spillLight.Enabled = state end
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
player.CharacterAdded:Connect(function(char)
	setLights(false)
	battery = BATTERY_MAX
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function() setLights(false) end)
end)

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
		core.Brightness = 4
		core.Range = 32
		core.Angle = 30
		core.Color = Color3.fromRGB(255, 244, 214)
		core.Shadows = true
		core.Face = Enum.NormalId.Front -- follows where their head points
		core.Enabled = false
		core.Parent = head

		local spill = Instance.new("SpotLight")
		spill.Name = "MateBeamSpill"
		spill.Brightness = 0.8
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
