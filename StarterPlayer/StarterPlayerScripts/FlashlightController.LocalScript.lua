-- FlashlightController  (v3 — handheld feel, fixed up/down tracking)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "FlashlightController"
-- REPLACES the old FlashlightController entirely — paste over the old contents.
--
-- F toggles. The beam comes from a point slightly right-and-below your view —
-- like a torch held in your hand — with a tight bright core inside a wide dim
-- spill, and a slight sway-lag when you turn. Updates AFTER the camera each
-- frame, so looking up/down tracks perfectly.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local player = Players.LocalPlayer

UIS.MouseIconEnabled = false -- no cursor

-- how the torch is held, relative to the camera
local HAND_OFFSET = CFrame.new(1.1, -0.9, 0.2) -- right, down, slightly back
local SWAY = 14 -- higher = snappier, lower = more lag/sway

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

	-- tight bright core: the actual "beam"
	coreLight = Instance.new("SpotLight")
	coreLight.Brightness = 5
	coreLight.Range = 70
	coreLight.Angle = 32
	coreLight.Color = Color3.fromRGB(255, 244, 214)
	coreLight.Shadows = true
	coreLight.Enabled = on
	coreLight.Face = Enum.NormalId.Front
	coreLight.Parent = mount

	-- wide dim spill around it: what your eye reads as "cone of light"
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

-- CRITICAL: bind AFTER the camera update, otherwise the beam lags/sticks when
-- pitching up/down (RenderStepped alone can run before the camera controller)
RunService:BindToRenderStep("MongoFlashlight", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not (mount and mount.Parent == camera) then
		buildMount()
		if not mount then return end
	end
	-- lerp the aim so the torch trails your turn like a real held object
	aimCF = aimCF and aimCF:Lerp(camera.CFrame, math.clamp(dt * SWAY, 0, 1))
		or camera.CFrame

	-- never let the torch end up inside a wall — that's what killed the light
	-- at close range. If the hand position is obstructed, pull it toward the
	-- eye so it stays just in front of the surface.
	local desired = aimCF * HAND_OFFSET
	local filter = { camera }
	if player.Character then table.insert(filter, player.Character) end
	rayParams.FilterDescendantsInstances = filter

	local origin = camera.CFrame.Position
	local offset = desired.Position - origin
	local hit = workspace:Raycast(origin, offset, rayParams)
	if hit then
		local safeDist = math.max((hit.Position - origin).Magnitude - 0.35, 0.05)
		mount.CFrame = aimCF.Rotation + (origin + offset.Unit * safeDist)
	else
		mount.CFrame = desired
	end
end)

local function toggle()
	on = not on
	if coreLight then coreLight.Enabled = on end
	if spillLight then spillLight.Enabled = on end
	remote:FireServer(on)
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then toggle() end
end)

-- flashlight resets to off on respawn
player.CharacterAdded:Connect(function()
	on = false
	if coreLight then coreLight.Enabled = false end
	if spillLight then spillLight.Enabled = false end
	remote:FireServer(false)
end)
