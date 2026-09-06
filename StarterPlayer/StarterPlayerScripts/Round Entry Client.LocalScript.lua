-- One truthful entry acknowledgement for every level. Cosmetic loading timers
-- and RequestStreamAroundAsync completion never stand in for visible ground.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local active

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function cancel()
	active = nil
	player:SetAttribute("RoundEntryReadyToken", nil)
end

local function current(request)
	return active == request and player.Character == request.Character
		and workspace:GetServerTimeNow() < request.Deadline
end

local function groundReady(request)
	local character = request.Character
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not character:IsDescendantOf(workspace) or not root or not root:IsA("BasePart")
		or not humanoid or humanoid.Health <= 0
		or (root.Position - request.Position).Magnitude > 16
		or workspace:GetAttribute("SelectedLevel") ~= request.Level then return false end
	local allowed = {}
	local function include(instance)
		if instance then table.insert(allowed, instance) end
	end
	if request.Level == 1 then
		include(workspace:FindFirstChild("Maze"))
		include(workspace:FindFirstChild("Elevator"))
	else
		include(workspace:FindFirstChild("Level " .. request.Level .. " Generated World"))
	end
	-- All entry adapters own this compatibility pad at the advertised position.
	-- Including exact entry geometry avoids accepting a player or lobby floor.
	include(workspace:FindFirstChild("ElevatorSpawn"))
	if #allowed == 0 then return false end
	local params = request.Raycast
	params.FilterDescendantsInstances = allowed
	-- Level 3 continuation holds the rig inside the sloped bore until release.
	-- Its floor is about 15 studs below this ray origin, beyond the flat-pad ray.
	local depth = request.Level == 3 and 20 or 14
	local hit = workspace:Raycast(root.Position + Vector3.yAxis * 2, Vector3.new(0, -depth, 0), params)
	return hit ~= nil and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
		and hit.Normal.Y > 0.15
end

local function begin(payload)
	if type(payload) ~= "table" or type(payload.Token) ~= "string"
		or #payload.Token == 0 or #payload.Token > 128 or not finite(payload.Level)
		or payload.Level % 1 ~= 0 or payload.Level < 1 or payload.Level > 3
		or typeof(payload.Character) ~= "Instance" or not payload.Character:IsA("Model")
		or payload.Character ~= player.Character or typeof(payload.Position) ~= "Vector3"
		or not finite(payload.Position.X) or not finite(payload.Position.Y) or not finite(payload.Position.Z)
		or not finite(payload.Deadline)
		or payload.Deadline <= workspace:GetServerTimeNow() then return end
	if active and active.Token == payload.Token and active.Character == payload.Character
		and active.Level == payload.Level and (active.Position - payload.Position).Magnitude < 0.1 then
		active.Deadline = math.min(active.Deadline, payload.Deadline)
		return
	end
	cancel()
	local request = {
		Token = payload.Token, Level = payload.Level, Character = payload.Character,
		Position = payload.Position, Deadline = payload.Deadline,
		AssetsReady = false, Raycast = RaycastParams.new(),
	}
	request.Raycast.FilterType = Enum.RaycastFilterType.Include
	request.Raycast.IgnoreWater = true
	request.Raycast.RespectCanCollide = true
	active = request
	-- Both engine operations may yield. Neither owns the polling task or its
	-- deadline, and their late results are useful only for this same request.
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(request.Position,
				math.max(0.1, math.min(10, request.Deadline - workspace:GetServerTimeNow())))
		end)
	end)
	task.spawn(function()
		local assets = {}
		for _, instance in ipairs(request.Character:GetDescendants()) do
			if instance:IsA("MeshPart") or instance:IsA("SpecialMesh")
				or instance:IsA("Decal") or instance:IsA("Texture") then
				table.insert(assets, instance)
			end
		end
		local failed = false
		local ok = pcall(function()
			ContentProvider:PreloadAsync(assets, function(_, status)
				if status ~= Enum.AssetFetchStatus.Success then failed = true end
			end)
		end)
		if current(request) then request.AssetsReady = ok and not failed end
	end)
	task.spawn(function()
		local stable, lastAck = 0, 0
		while current(request) do
			local ready = game:IsLoaded() and request.AssetsReady
				and player:GetAttribute("RoundEntryUIReady") == true
				and player:GetAttribute("RoundEntryControlsReady") == true
				and groundReady(request)
			-- Local-only failure injection, unavailable in published servers.
			if RunService:IsStudio() and player:GetAttribute("DevHoldEntryReady") == true then ready = false end
			stable = ready and stable + 1 or 0
			if stable >= 3 and os.clock() - lastAck >= 0.5 then
				lastAck = os.clock()
				player:SetAttribute("RoundEntryReadyToken", request.Token)
				remote:FireServer("entryready", {
					Token = request.Token, Level = request.Level, Character = request.Character,
				})
			elseif not ready then
				player:SetAttribute("RoundEntryReadyToken", nil)
			end
			task.wait(0.1)
		end
		if active == request then cancel() end
	end)
end

remote.OnClientEvent:Connect(function(event, payload)
	if event == "entryprepare" then
		begin(payload)
	elseif event == "entryreleased" or event == "entrycancel" then
		if active and type(payload) == "table" and payload.Token == active.Token then cancel() end
	elseif event == "loadfailed" or event == "lobby" or event == "start" or event == "loadinggame" then
		cancel()
	end
end)
player.CharacterAdded:Connect(cancel)
