-- One truthful entry acknowledgement for every level. Cosmetic loading timers
-- and RequestStreamAroundAsync completion never stand in for visible ground.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
-- AUDIT_FIX_20260924: Reset Character is off while an entry is pending. Nothing
-- respawns a placed member during entry, so one reset used to hold the whole
-- party behind the cover until the 60 s deadline sent everyone back.
local function allowReset(on) pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", on) end
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local active
local entryPreloadBusy = false

local CONTENT_PROPERTIES = {
	MeshPart = { "MeshContent", "TextureContent" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" }, Texture = { "Texture" },
	ImageLabel = { "Image" }, ImageButton = { "Image" },
	ParticleEmitter = { "Texture" }, Beam = { "Texture" }, Trail = { "Texture" },
}
local MAP_PROPERTIES = { "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" }

local function contentKey(value)
	if type(value) == "string" then return value ~= "" and value or nil end
	if typeof(value) == "Content" then
		if value.SourceType == Enum.ContentSourceType.Uri then return value.Uri ~= "" and value.Uri or nil end
		if value.SourceType == Enum.ContentSourceType.Opaque then return value end
	end
	return nil
end

local function collectAsset(instance, ids, carriers)
	local added = 0
	local function add(key, imageId, keys)
		if not key or ids[key] then return end
		ids[key] = "pending"
		added += 1
		if imageId then
			table.insert(carriers, {ImageId = imageId, Keys = {key}})
		else
			table.insert(keys, key)
		end
	end
	if instance:IsA("SurfaceAppearance") then
		-- PreloadAsync ignores SurfaceAppearance. Warm URI images through supported
		-- Decals; this cannot certify that the renderer's processed PBR pack is ready.
		for _, property in ipairs(MAP_PROPERTIES) do
			local ok, value = pcall(function() return instance[property] end)
			if ok and typeof(value) == "Content" and value.SourceType == Enum.ContentSourceType.Uri then
				add(contentKey(value), value.Uri)
			end
		end
	else
		local keys = {}
		for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName] or {}) do
			local ok, value = pcall(function() return instance[property] end)
			if ok then
				local key = contentKey(value)
				if typeof(key) == "Content" then
					-- Embedded Opaque content without an asset ID has no remote fetch.
					local legacy = property == "MeshContent" and "MeshId" or "TextureID"
					local readable, id = pcall(function() return instance[legacy] end)
					key = readable and type(id) == "string" and id ~= "" and id or nil
				end
				add(key, nil, keys)
			end
		end
		if #keys > 0 then table.insert(carriers, {Instance = instance, Keys = keys}) end
	end
	return added
end

local function loadCarrier(carrier)
	local instance = carrier.Instance
	local reported, failed = false, false
	local ok = pcall(function()
		if carrier.ImageId then
			instance = Instance.new("Decal")
			instance.Texture = carrier.ImageId
		end
		-- Keep mesh instances: a MeshId string does not necessarily fetch the
		-- same content as the actual MeshPart, especially DataModel-scoped meshes.
		ContentProvider:PreloadAsync({instance}, function(_, fetchStatus)
			reported = true
			if fetchStatus ~= Enum.AssetFetchStatus.Success then failed = true end
		end)
	end)
	if carrier.ImageId and instance then
		local cleaned = pcall(function() instance:Destroy() end)
		if not cleaned then ok = false end
	end
	-- A return or absent callback is not evidence of a successful download.
	return ok and reported and not failed
end



local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function cancel()
	if active then
		for _, connection in ipairs(active.Connections) do connection:Disconnect() end
		table.clear(active.Connections)
	end
	active = nil
	player:SetAttribute("RoundEntryReadyToken", nil)
	allowReset(true)
end

local function current(request)
	return active == request and player.Character == request.Character
		and workspace:GetServerTimeNow() < request.Deadline
end

local function entryWorlds(level)
	local allowed = {}
	local function include(instance)
		if instance then table.insert(allowed, instance) end
	end
	if level == 1 then
		include(workspace:FindFirstChild("Maze"))
		include(workspace:FindFirstChild("Elevator"))
	elseif level == 4 then
		-- the authored cinema (developer-only round, GameManager devCeiling)
		include(workspace:FindFirstChild("Level 4 Cinema Blender"))
	else
		include(workspace:FindFirstChild("Level " .. level .. " Generated World"))
	end
	-- All entry adapters own this compatibility pad at the advertised position.
	-- Including exact entry geometry avoids accepting a player or lobby floor.
	include(workspace:FindFirstChild("ElevatorSpawn"))
	return allowed
end

local function groundReady(request)
	local character = request.Character
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not character:IsDescendantOf(workspace) or not root or not root:IsA("BasePart")
		or not humanoid or humanoid.Health <= 0
		or (root.Position - request.Position).Magnitude > 16
		or workspace:GetAttribute("SelectedLevel") ~= request.Level then return false end
	local allowed = entryWorlds(request.Level)
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
		or payload.Level % 1 ~= 0 or payload.Level < 1 or payload.Level > 4
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
		AssetsReady = false, Raycast = RaycastParams.new(), Connections = {},
	}
	request.Raycast.FilterType = Enum.RaycastFilterType.Include
	request.Raycast.IgnoreWater = true
	request.Raycast.RespectCanCollide = true
	active = request
	allowReset(false)
	-- Both engine operations may yield. Neither owns the polling task or its
	-- deadline, and their late results are useful only for this same request.
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(request.Position,
				math.max(0.1, math.min(10, request.Deadline - workspace:GetServerTimeNow())))
		end)
	end)
	task.spawn(function()
		local ids, carriers, watched, queued = {}, {}, {}, {}
		local lastArrival = os.clock()
		local cursor = 1
		local function nearby(instance)
			local part = instance:IsA("BasePart") and instance or instance:FindFirstAncestorWhichIsA("BasePart")
			-- Room art has CanQuery=false, so spatial overlap queries omit its ceiling.
			return part and part.Transparency < 1
				and (part.Position - request.Position).Magnitude <= 80 + part.Size.Magnitude * 0.5
		end
		local function enqueue(instance, character)
			if not current(request) then return end
			if not CONTENT_PROPERTIES[instance.ClassName] and not instance:IsA("SurfaceAppearance") then return end
			if character or nearby(instance) then
				table.insert(queued, instance)
				lastArrival = os.clock()
				request.AssetsReady = false
			end
		end
		local function watch(root, character)
			if not root or watched[root] then return end
			local connection = root.DescendantAdded:Connect(function(instance) enqueue(instance, character) end)
			watched[root] = true
			table.insert(request.Connections, connection)
			for index, instance in ipairs(root:GetDescendants()) do
				if not current(request) then return end
				enqueue(instance, character)
				if index % 200 == 0 then task.wait() end
			end
		end
		watch(request.Character, true)
		while current(request) do
			local roots = entryWorlds(request.Level)
			for _, root in ipairs(roots) do watch(root, false) end
			local checks = 0
			while cursor <= #queued and current(request) do
				collectAsset(queued[cursor], ids, carriers)
				cursor += 1
				checks += 1
				if checks % 200 == 0 then task.wait() end
			end
			if cursor > #queued then table.clear(queued) cursor = 1 end
			local ready = #roots > 0
			for _, carrier in ipairs(carriers) do
				if carrier.Loaded ~= true and (carrier.Attempts or 0) < 2 then
					while entryPreloadBusy and current(request) do task.wait(0.1) end
					if not current(request) then break end
					entryPreloadBusy = true
					carrier.Attempts = (carrier.Attempts or 0) + 1
					carrier.Loaded = loadCarrier(carrier)
					entryPreloadBusy = false
					if not carrier.Loaded and carrier.Attempts == 2 then
						warn("[RoundEntry] could not fetch nearby visual: " .. tostring(carrier.Keys[1]))
					end
				end
				if carrier.Loaded ~= true then ready = false end
			end
			if current(request) then
				request.AssetsReady = ready and #queued == 0 and os.clock() - lastArrival >= 0.35
			end
			task.wait(0.1)
		end
		for _, connection in ipairs(request.Connections) do connection:Disconnect() end
		table.clear(request.Connections)
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
