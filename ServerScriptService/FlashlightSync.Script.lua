-- FlashlightSync
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "FlashlightSync"
-- Keeps the server-authoritative FlashlightOn flag on each character,
-- so EntityAI can read it (client BoolValues don't replicate to the server).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")
local Profiles = require(RS:WaitForChild("FlashlightProfiles"))
local mounts = {}
local lastAim = {}
local lastToggle = {}

local function finiteVector(vector)
	return vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
		and math.abs(vector.X) < 1e6 and math.abs(vector.Y) < 1e6 and math.abs(vector.Z) < 1e6
end

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
	core.Color = Color3.fromRGB(255, 244, 214)
	core.Shadows = false
	core.Face = Enum.NormalId.Front
	core.Enabled = false
	core.Parent = mount

	local spill = Instance.new("SpotLight")
	spill.Name = "Spill"
	spill.Color = Color3.fromRGB(255, 240, 205)
	spill.Shadows = false
	spill.Face = Enum.NormalId.Front
	spill.Enabled = false
	spill.Parent = mount
	Profiles.Apply(Profiles.Mount, "BASE", core, spill)

	local head = char and char:FindFirstChild("Head")
	if head then mount.CFrame = head.CFrame end
	mount.Parent = workspace
	mounts[player] = mount
	return mount
end

local function applyMountProfile(mount)
	Profiles.Apply(Profiles.Mount, Profiles.Current(), mount:FindFirstChild("Core"), mount:FindFirstChild("Spill"))
end

local function setMountEnabled(mount, enabled)
	applyMountProfile(mount)
	for _, light in ipairs(mount:GetChildren()) do
		if light:IsA("Light") then light.Enabled = enabled end
	end
end

remote.OnServerEvent:Connect(function(player, value, payload)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local now = os.clock()
	if type(value) == "boolean" then
		if now - (lastToggle[player] or -math.huge) < 0.08 then
			-- An off signal is always safe and must win even if death followed an
			-- on signal immediately; never leave a replicated corpse beam lit.
			if value == false then
				local flag = char:FindFirstChild("FlashlightOn")
				if flag and flag:IsA("BoolValue") then flag.Value = false end
				local existingMount = mounts[player]
				if existingMount then setMountEnabled(existingMount, false) end
			end
			return
		end
		lastToggle[player] = now
		if value and workspace:GetAttribute("SelectedLevel") == 3
			and workspace:GetAttribute("Level3FlashlightsSuppressed") == true then value = false end
		if value and (not humanoid or humanoid.Health <= 0) then return end
		if player:GetAttribute("InRound") ~= true then value = false end
		ensureFlag(char).Value = value
		local mount = value and ensureMount(player, char) or mounts[player]
		if mount then setMountEnabled(mount, value) end
	elseif value == "aim" and typeof(payload) == "CFrame" then
		if workspace:GetAttribute("SelectedLevel") == 3
			and workspace:GetAttribute("Level3FlashlightsSuppressed") == true then return end
		if not humanoid or humanoid.Health <= 0 then return end
		if now - (lastAim[player] or -math.huge) < 1 / 30 then return end
		lastAim[player] = now
		if not ensureFlag(char).Value then return end
		local head = char:FindFirstChild("Head")
		if not head then return end
		local requested = payload.Position
		local look = payload.LookVector
		if not finiteVector(requested) or not finiteVector(look) then return end
		-- Camera origin must stay close to the character. Direction is still the
		-- client's exact view, so looking up/down remains correct in first person.
		local origin = (requested - head.Position).Magnitude <= 6 and requested or head.Position
		if look.Magnitude < 0.9 then return end
		local mount = ensureMount(player, char)
		applyMountProfile(mount)
		mount.CFrame = CFrame.lookAt(origin, origin + look.Unit)
	end
end)

-- One wiring path for both joins and the startup catch-up loop, so neither
-- can drift (the old copies diverged: pre-existing players never got the
-- InRound watcher and kept a lit mount after their round ended).
local function forceLightOff(p)
	local char = p.Character
	if char then ensureFlag(char).Value = false end
	local mount = mounts[p]
	if mount then setMountEnabled(mount, false) end
end

workspace:GetAttributeChangedSignal("Level3FlashlightsSuppressed"):Connect(function()
	if workspace:GetAttribute("SelectedLevel") == 3
		and workspace:GetAttribute("Level3FlashlightsSuppressed") == true then
		for _, player in ipairs(Players:GetPlayers()) do forceLightOff(player) end
	end
end)

local function hookPlayer(p)
	p:GetAttributeChangedSignal("InRound"):Connect(function()
		if p:GetAttribute("InRound") ~= true then forceLightOff(p) end
	end)
	p.CharacterAdded:Connect(function(char)
		removeMount(p)
		ensureFlag(char)
	end)
	if p.Character then ensureFlag(p.Character) end
end

Players.PlayerAdded:Connect(hookPlayer)
-- cover characters that spawned before this script connected
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

Players.PlayerRemoving:Connect(function(player)
	lastAim[player] = nil
	lastToggle[player] = nil
	removeMount(player)
end)
