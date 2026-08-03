-- FlashlightSync
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "FlashlightSync"
-- Keeps the server-authoritative FlashlightOn flag on each character,
-- so EntityAI can read it (client BoolValues don't replicate to the server).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local mounts = {}

local function ensureFlag(char)
	local flag = char:FindFirstChild("FlashlightOn")
	if not flag then
		flag = Instance.new("BoolValue")
		flag.Name = "FlashlightOn"
		flag.Parent = char
	end
	return flag
end

local function removeMount(player)
	local mount = mounts[player]
	mounts[player] = nil
	if mount then mount:Destroy() end
end

local function ensureMount(player, char)
	local current = mounts[player]
	if current and current.Parent then return current end
	local mount = Instance.new("Part")
	mount.Name = "ReplicatedFlashlight_" .. player.UserId
	mount.Size = Vector3.new(0.2, 0.2, 0.2)
	mount.Anchored = true
	mount.CanCollide = false
	mount.CanTouch = false
	mount.CanQuery = false
	mount.Transparency = 1

	local core = Instance.new("SpotLight")
	core.Name = "Core"
	core.Brightness = 1.2
	core.Range = 38
	core.Angle = 38
	core.Color = Color3.fromRGB(255, 244, 214)
	core.Shadows = false
	core.Face = Enum.NormalId.Front
	core.Enabled = false
	core.Parent = mount

	local spill = Instance.new("SpotLight")
	spill.Name = "Spill"
	spill.Brightness = 0.3
	spill.Range = 45
	spill.Angle = 75
	spill.Color = Color3.fromRGB(255, 240, 205)
	spill.Shadows = false
	spill.Face = Enum.NormalId.Front
	spill.Enabled = false
	spill.Parent = mount

	local head = char and char:FindFirstChild("Head")
	if head then mount.CFrame = head.CFrame end
	mount.Parent = workspace
	mounts[player] = mount
	return mount
end

local function setMountEnabled(mount, enabled)
	for _, light in ipairs(mount:GetChildren()) do
		if light:IsA("Light") then light.Enabled = enabled end
	end
end

remote.OnServerEvent:Connect(function(player, value, payload)
	local char = player.Character
	if not char then return end
	if type(value) == "boolean" then
		if player:GetAttribute("InRound") ~= true then value = false end
		ensureFlag(char).Value = value
		local mount = ensureMount(player, char)
		setMountEnabled(mount, value)
	elseif value == "aim" and typeof(payload) == "CFrame" then
		if not ensureFlag(char).Value then return end
		local head = char:FindFirstChild("Head")
		if not head then return end
		local requested = payload.Position
		-- Camera origin must stay close to the character. Direction is still the
		-- client's exact view, so looking up/down remains correct in first person.
		local origin = (requested - head.Position).Magnitude <= 6 and requested or head.Position
		local look = payload.LookVector
		if look.Magnitude < 0.9 then return end
		local mount = ensureMount(player, char)
		mount.CFrame = CFrame.lookAt(origin, origin + look.Unit)
	end
end)

Players.PlayerAdded:Connect(function(p)
	p:GetAttributeChangedSignal("InRound"):Connect(function()
		if p:GetAttribute("InRound") == true then return end
		local char = p.Character
		if char then ensureFlag(char).Value = false end
		local mount = mounts[p]
		if mount then setMountEnabled(mount, false) end
	end)
	p.CharacterAdded:Connect(function(char)
		removeMount(p)
		ensureFlag(char)
	end)
end)

-- cover characters that spawned before this script connected
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(char)
		removeMount(p)
		ensureFlag(char)
	end)
	if p.Character then ensureFlag(p.Character) end
end

Players.PlayerRemoving:Connect(removeMount)
