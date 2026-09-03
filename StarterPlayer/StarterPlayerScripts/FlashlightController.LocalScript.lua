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
local UIDevice = require(RS:WaitForChild("UIDevice"))
local Profiles = require(RS:WaitForChild("FlashlightProfiles"))
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local player = Players.LocalPlayer

-- how the torch is held, relative to the eye (horizontal offset + drop)
local HAND_SIDE = 0.25  -- small hand offset: avoids putting the light inside walls
local HAND_DOWN = -0.25
local HAND_FORWARD = 0.3
local SWAY = 14         -- higher = snappier, lower = more lag/sway

local mount, coreLight, spillLight
local on = false
local lastBeamProfile = ""
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

	-- tight bright core: the actual "beam" (numbers live in FlashlightProfiles)
	coreLight = Instance.new("SpotLight")
	coreLight.Color = Color3.fromRGB(255, 244, 214)
	coreLight.Shadows = true -- localized cone stops at walls instead of lighting whole parts through them
	coreLight.Enabled = on
	coreLight.Face = Enum.NormalId.Front
	coreLight.Parent = mount

	-- wide dim spill: what your eye reads as the "cone of light"
	spillLight = Instance.new("SpotLight")
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

local function applyBeamProfile()
	local profile = Profiles.Current()
	if profile == lastBeamProfile then return end
	lastBeamProfile = profile
	Profiles.Apply(Profiles.Own, profile, coreLight, spillLight)
end

buildMount()
applyBeamProfile()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	lastBeamProfile = ""
	buildMount()
	applyBeamProfile()
end)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	lastBeamProfile = ""
	applyBeamProfile()
end)
workspace:GetAttributeChangedSignal("Level3BlackoutActive"):Connect(function()
	lastBeamProfile = ""
	applyBeamProfile()
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Illumination is produced only by localized SpotLights. The removed
-- Highlight adorned the entire hit floor/wall/ceiling part and looked exactly
-- like Studio selection rather than a physical flashlight beam.

-- Cached so the per-frame suppression below skips the name build, the
-- FindFirstChild lookup and GetChildren() once the instance is found.
local REPLICATED_SELF_NAME = "ReplicatedFlashlight_" .. player.UserId
local replicatedSelf, replicatedLights = nil, {}

-- bind AFTER the camera updates, so up/down tracking is exact
-- Level3UnderTableCamera finalizes a hidden player's camera at Camera + 1.
-- Aim one priority later so the torch always originates from that real POV.
RunService:BindToRenderStep("MongoFlashlight", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not (mount and mount.Parent == workspace) then
		lastBeamProfile = ""
		buildMount()
		applyBeamProfile()
		if not mount then return end
	end
	applyBeamProfile()

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
	if not (replicatedSelf and replicatedSelf.Parent == workspace) then
		replicatedSelf = workspace:FindFirstChild(REPLICATED_SELF_NAME)
		replicatedLights = {}
		if replicatedSelf then
			for _, item in ipairs(replicatedSelf:GetChildren()) do
				if item:IsA("Light") then table.insert(replicatedLights, item) end
			end
		end
	end
	for _, item in ipairs(replicatedLights) do
		item.Enabled = false
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
local BATTERY_BASE     = 100
local DRAIN_PER_SEC    = 1.111 -- ~90s of continuous light on a full charge
local RECHARGE_PER_SEC = 3.0  -- full recharge in roughly 33s while switched OFF
local MIN_TO_TURN_ON   = 5    -- can't switch on below this (must recharge a bit)
local function batteryMax()
	return BATTERY_BASE * math.max(1, tonumber(player:GetAttribute("ZyntraBatteryMultiplier")) or 1)
end
local battery = batteryMax()
local warned50, warned25 = false, false

-- bottom-of-screen pop-up (shown when the battery dies)
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "FlashlightPopup"
popupGui.ResetOnSpawn = false
popupGui.DisplayOrder = 60
popupGui.Enabled = player:GetAttribute("InRound") == true
popupGui.Parent = player:WaitForChild("PlayerGui")
local popup = Instance.new("TextLabel")
popup.AnchorPoint = Vector2.new(0.5, 1)
popup.Position = UDim2.new(0.5, 0, 1, -26)
popup.Size = UDim2.new(0, 360, 0, 34)
-- 360px overflows a 375-wide portrait screen once margins are counted, and the
-- bottom edge lands on the movement controls. Both are fixed from the layout.
local function applyPopupLayout()
	local layout = UIDevice.Layout()
	popup.Size = UDim2.new(0, math.min(360, layout.SafeRight - layout.SafeLeft), 0, 34)
	if layout.IsTouch then
		-- SafeBottom is ABSOLUTE. Handing it over as a gui offset put the popup
		-- one topbar below where it was computed to sit.
		local x, y = UIDevice.LocalOffset(popupGui,
			(layout.Safe.Left + layout.Safe.Right) * .5, layout.SafeBottom - 8)
		popup.Position = UDim2.fromOffset(x, y)
	else
		popup.Position = UDim2.new(0.5, 0, 1, -26)
	end
end
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
applyPopupLayout()
UIDevice.Changed:Connect(applyPopupLayout)

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

-- Built up here and parented to the torch art further down, because the layout
-- pass below sizes that drawing to whatever slot the cluster hands it and runs
-- before the art itself exists.
local torchScale = Instance.new("UIScale")
torchScale.Scale = 0.72

-- Whether this frame is currently tagged as part of the movement cluster.
-- C_CONTROL_ZONE_INVALIDATION_20260831: the registration follows the FORM
-- FACTOR rather than being done once at load. On a pointer device this frame is
-- not a movement control at all -- it is a bottom-LEFT battery readout with no
-- touch target over it -- and leaving it tagged put the corner of the screen
-- furthest from the cluster inside the rectangle every HUD dodges. Latched, so a
-- relayout that changes nothing does not churn the zone; and reversible, because
-- a tablet leaving its keyboard case flips the form factor without a restart.
local flashlightRegistered = false

-- The torch used to sit in the bottom-LEFT corner, which on a touch device is
-- entirely inside the dynamic thumbstick's activation region: a fully
-- transparent, Active 72x136 button laid over the movement stick. It only
-- failed to steal the finger because its ScreenGui happened to sit below
-- TouchGui in DisplayOrder -- an accident, and one this rework removes by
-- raising that DisplayOrder. So on touch it takes a slot in the movement
-- cluster. On desktop, where there is no thumbstick and no touch target, it
-- stays exactly where it was.
--
-- C_SHORT_SCREEN_CLUSTER_20260831: the slot is READ from UIDevice's control
-- plan, not re-derived here. This file used to keep its own copy of the edge,
-- button-size and second-column constants and repeat NoiseReporter's arithmetic
-- to arrive at the same corner -- one layout written out three times, in three
-- files, which is exactly the arrangement that cannot survive the cluster
-- reflowing into a row on a short landscape screen.
local function applyFlashlightLayout()
	local layout = UIDevice.Layout()
	if layout.IsTouch ~= flashlightRegistered then
		flashlightRegistered = layout.IsTouch
		if flashlightRegistered then
			UIDevice.RegisterControlRect("FlashlightPower", batBody)
		else
			UIDevice.UnregisterControlRect(batBody)
		end
	end
	if layout.IsTouch then
		local slot = layout.ControlPlan.Slots.FlashlightPower
		batBody.AnchorPoint = Vector2.new(1, 1)
		batBody.Size = UDim2.fromOffset(slot.Width, slot.Height)
		batBody.Position = UDim2.new(1, -slot.Right, 1, -slot.Bottom)
		-- The torch ART is a fixed 160x48 drawing rotated upright, so it is the
		-- SLOT that changes size under it. 0.72 was chosen against the 58px slot
		-- the column gives it: 160 * 0.72 is 115, very nearly twice the slot, and
		-- the overhang is deliberate -- the torch reads as a torch rather than as
		-- a 58px icon. Held to that same proportion, the row's smaller cell keeps
		-- the look instead of hanging a 115px drawing over a 45px button and up
		-- into the readout's headroom. The column is untouched by this:
		-- min(0.72, 58 * 2 / 160) is 0.72, and the tablet's 72px slot likewise.
		torchScale.Scale = math.min(0.72, slot.Height * 2 / 160)
	else
		batBody.AnchorPoint = Vector2.new(0, 1)
		batBody.Size = UDim2.fromOffset(72, 136)
		batBody.Position = UDim2.new(0, 12, 1, -10)
		torchScale.Scale = 0.72
	end
end

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
touchFlashButton.ZIndex = 20
touchFlashButton.Parent = batBody
-- Visible AND Active move together: an invisible-but-Active button keeps
-- swallowing taps, which is exactly how this one competed with the thumbstick.
-- The hit target is fully transparent, so leaving it Active while every other
-- on-screen control has stood down makes it an invisible tap sink over the
-- HUD -- and at the raised DisplayOrder 60 it now wins those taps. It stands
-- down on exactly the states the movement cluster does.
-- C_LIVE_CONTROL_RECTS_20260831: the flashlight's hit target is part of the
-- movement cluster, so it registers its rectangle like the rest of them. It is
-- the BODY that is measured, not the transparent hit box, because the body is
-- what the player sees and reaches for. The registration itself lives in
-- applyFlashlightLayout, which is where the form factor is already known.

-- Keep the production shade itself in the availability predicate. The shared
-- QueueModalOpen attribute remains the fallback contract, but its listener and
-- the shade listener have no guaranteed ordering; relying on the attribute
-- alone leaves an invisible DisplayOrder-60 tap target alive for that gap.
local queueShadeVisible = player:GetAttribute("QueueModalOpen") == true

local function flashlightTargetAvailable()
	if not UIDevice.IsTouch() then return false end
	if player:GetAttribute("InRound") ~= true then return false end
	if player:GetAttribute("Escaped") == true then return false end
	if player:GetAttribute("Spectating") == true then return false end
	if player:GetAttribute("ZyntraStoreOpen") == true then return false end
	if player:GetAttribute("DevPhoneOpen") == true then return false end
	if player:GetAttribute("ZyntraReentryOpen") == true then return false end
	-- The party dialog owns the screen too; this list had three of the four.
	if queueShadeVisible or player:GetAttribute("QueueModalOpen") == true then return false end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function applyFlashlightTouchTarget()
	UIDevice.SetInteractive(touchFlashButton, flashlightTargetAvailable())
end
for _, attribute in ipairs({"InRound", "Escaped", "Level3_Hiding", "Spectating",
	"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		applyFlashlightTouchTarget()
	end)
end
-- QueueModalOpen is derived from QueueHostShade.Visible. Listening only to the
-- derived attribute adds a second deferred signal hop: for two frames the
-- DisplayOrder-60 flashlight target can still sit above a newly opened party
-- modal. Watch production's actual choke point too, so the target stands down
-- on the very next Heartbeat while the attribute remains the shared contract
-- for every other screen-owning modal.
task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local roundGui = playerGui:WaitForChild("RoundGui", 15)
	local queueShade = roundGui and roundGui:WaitForChild("QueueHostShade", 15)
	if not queueShade then return end
	queueShadeVisible = queueShade.Visible
	queueShade:GetPropertyChangedSignal("Visible"):Connect(function()
		queueShadeVisible = queueShade.Visible
		applyFlashlightTouchTarget()
	end)
	applyFlashlightTouchTarget()
end)
player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then humanoid.Died:Connect(applyFlashlightTouchTarget) end
	applyFlashlightTouchTarget()
end)
applyFlashlightTouchTarget()
applyFlashlightLayout()
UIDevice.Changed:Connect(function()
	applyFlashlightTouchTarget()
	applyFlashlightLayout()
end)

local torch = Instance.new("Frame")
torch.Name = "Silhouette"
torch.AnchorPoint = Vector2.new(0.5, 0.5)
torch.Position = UDim2.fromScale(0.5, 0.5)
torch.Size = UDim2.new(0, 160, 0, 48)
torch.BackgroundTransparency = 1
torch.Rotation = -90 -- upright, with the lens/rays at the top
torch.Parent = batBody
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

local function flashlightsSuppressed()
 return workspace:GetAttribute("SelectedLevel") == 3
  and workspace:GetAttribute("Level3FlashlightsSuppressed") == true
end

local function setLights(state)
 if state and flashlightsSuppressed() then state = false end
 on = state
	if coreLight then coreLight.Enabled = state end
	if spillLight then spillLight.Enabled = state end
 lens.BackgroundTransparency = state and 0 or 0.72
 for _, ray in ipairs(lightRays) do ray.Visible = state end
 remote:FireServer(state)
end

workspace:GetAttributeChangedSignal("Level3FlashlightsSuppressed"):Connect(function()
 if flashlightsSuppressed() and on then setLights(false) end
end)

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
	if flashlightsSuppressed() then return end
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
	battery = batteryMax()
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
local lastMateProfile -- last applied profile name; nil forces a re-apply

local function attachMateBeam(char)
	task.spawn(function()
		local head = char:WaitForChild("Head", 30)
		if not head then return end
		if head:FindFirstChild("MateBeamCore") then return end

		local core = Instance.new("SpotLight")
		core.Name = "MateBeamCore"
		core.Color = Color3.fromRGB(255, 244, 214)
		core.Shadows = true
		core.Face = Enum.NormalId.Front -- follows where their head points
		core.Enabled = false
		core.Parent = head

		local spill = Instance.new("SpotLight")
		spill.Name = "MateBeamSpill"
		spill.Color = Color3.fromRGB(255, 240, 205)
		spill.Shadows = false
		spill.Face = Enum.NormalId.Front
		spill.Enabled = false
		spill.Parent = head

		mateBeams[char] = { core = core, spill = spill }
		lastMateProfile = nil -- new beam still has default values; force a re-apply
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
	local profile = Profiles.Current()
	local profileChanged = profile ~= lastMateProfile
	lastMateProfile = profile
	for char, beams in pairs(mateBeams) do
		local flag = char:FindFirstChild("FlashlightOn")
		local hum = char:FindFirstChildOfClass("Humanoid")
		local shine = flag ~= nil and flag.Value == true
			and hum ~= nil and hum.Health > 0
		if profileChanged then Profiles.Apply(Profiles.Mate, profile, beams.core, beams.spill) end
		beams.core.Enabled = shine
		beams.spill.Enabled = shine
	end
end)

-- DevCheats owns the single output confirmation; this listener only applies
-- the battery state so pressing U never prints two messages.
player:GetAttributeChangedSignal("DevUnlimited"):Connect(function()
	local active = player:GetAttribute("DevUnlimited") == true
	if active then battery = batteryMax() end
end)

-- drain while on, recharge while off; die at empty
RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("DevUnlimited") == true then
		battery = batteryMax() -- dev cheat (DevCheats, U key): never drains
	elseif on then
		battery = battery - DRAIN_PER_SEC * dt
		if battery <= 0 then
			battery = 0
			setLights(false) -- (sets `on` false, so this fires once at the drain-out)
			showPopup("Flashlight dead — let it recharge", 3)
		end
	else
		battery = math.min(batteryMax(), battery + RECHARGE_PER_SEC * dt)
	end

	-- re-arm and fire warnings by percentage, so upgrades preserve the same UX.
	local batteryFraction = math.clamp(battery / batteryMax(), 0, 1)
	if batteryFraction > 0.55 then warned50 = false end
	if batteryFraction > 0.30 then warned25 = false end
	if on and batteryFraction <= 0.25 and not warned25 then
		warned25 = true
		warnBlink(3)
	elseif on and batteryFraction <= 0.50 and not warned50 then
		warned50 = true
		warnBlink(1)
	end

	-- battery bars: fill count + colour (white full → red near empty)
	local filled = math.clamp(math.ceil(batteryFraction * 5), 0, 5)
	local col = BAT_FULL:Lerp(BAT_EMPTY, 1 - batteryFraction)
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
