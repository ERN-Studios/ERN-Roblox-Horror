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