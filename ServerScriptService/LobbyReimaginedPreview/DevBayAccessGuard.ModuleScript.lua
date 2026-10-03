-- Authoritative, bounded Level 5/6 lobby bay access; client shutters are presentation.
-- No character collision groups, other levels, campaign progression or map geometry change.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local Module = {}
local states = setmetatable({}, {__mode = "k"})
local INTERVAL = .2
local LEVELS = {5, 6}

local function ownedReady(model)
	return typeof(model) == "Instance" and model:IsA("Model")
		and model.Name == "LobbyReimaginedPreview" and model.Parent == workspace
		and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("LobbyVisualRevision") == 4
		and model:GetAttribute("Ready") == true
end

local function allowed(player)
	local ok, result = pcall(DevAccess.IsLevel6PreviewAllowed, player)
	return ok and result == true
end

local function insideProtectedBay(record, position)
	-- Circular chamber floor and actual portal transform are the only protected volumes.
	-- The rectangle is just the narrow connector/aperture, never the tunnel or sidewalk.
	local gate = record.header.CFrame * CFrame.new(0, -17.2, -1.42)
	local localPoint = gate:PointToObjectSpace(position)
	if math.abs(localPoint.X) <= 10 and localPoint.Y >= -2 and localPoint.Y <= 18
		and localPoint.Z < -.12 and localPoint.Z >= -14 then return true, gate end
	local floor = record.floor
	local delta = position - floor.Position
	local halfThickness = math.min(floor.Size.X, floor.Size.Y, floor.Size.Z) * .5
	local top = floor.Position.Y + halfThickness
	local radius = record.radius
	return delta.X * delta.X + delta.Z * delta.Z <= radius * radius
		and position.Y >= top - 2 and position.Y <= top + 24, gate
end

local function stop(state)
	if state.stopped then return end
	state.stopped = true
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	table.clear(state.connections)
	if states[state.model] == state then states[state.model] = nil end
end

function Module.Start(model)
	assert(not RunService:IsClient(), "Developer bay guard is server-only")
	assert(ownedReady(model), "Developer bay guard requires the exact ready owned R4 lobby")
	if states[model] then return states[model] end
	local pads = assert(model:FindFirstChild("PreviewQueuePads"), "Missing queue bay folder")
	local signs = assert(model:FindFirstChild("LevelGateSigns"), "Missing gate signs")
	local records = {}
	for _, level in ipairs(LEVELS) do
		local bay = pads:FindFirstChild("QueueBay_Level" .. level)
		local floor = bay and bay:FindFirstChild("ChamberFloor")
		local header = signs:FindFirstChild("LEVEL " .. level .. " Door Header")
		local diameter = bay and bay:GetAttribute("CircularBayDiameter")
		assert(bay and bay:IsA("Model") and floor and floor:IsA("BasePart")
			and floor.Anchored and floor.CanCollide and floor.Parent == bay
			and header and header:IsA("BasePart") and header.Parent == signs
			and header:GetAttribute("Level") == level
			and type(diameter) == "number" and diameter > 40 and diameter < 65,
			"Wrong Level " .. level .. " bay guard geometry")
		table.insert(records, {level = level, bay = bay, floor = floor, header = header,
			radius = diameter * .5 + .5})
	end
	local state = {model = model, records = records, connections = {}, stopped = false, elapsed = 0}
	states[model] = state
	model:SetAttribute("DevBayAccessGuardVersion", 1)
	model:SetAttribute("DevBayProtectedLevels", "5,6")
	model:SetAttribute("DevBayGuardInterval", INTERVAL)
	if model:GetAttribute("DevBayDeniedEntryCount") == nil then model:SetAttribute("DevBayDeniedEntryCount", 0) end
	table.insert(state.connections, model.Destroying:Connect(function() stop(state) end))
	table.insert(state.connections, model.AncestryChanged:Connect(function()
		if model.Parent ~= workspace then stop(state) end
	end))
	table.insert(state.connections, RunService.Heartbeat:Connect(function(deltaTime)
		if state.stopped then return end
		state.elapsed += deltaTime
		if state.elapsed < INTERVAL then return end
		state.elapsed = 0 -- One sweep, never accumulated catch-up work after a long frame.
		if not ownedReady(model) or workspace:GetAttribute("ReservedRoundServer") == true then return end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Parent ~= Players or allowed(player) then continue end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if not root or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then continue end
			for _, record in ipairs(records) do
				if record.bay.Parent ~= pads or record.floor.Parent ~= record.bay
					or record.header.Parent ~= signs then continue end
				if record.level == 6 and DevAccess.IsLevel6Allowed(player) then continue end   -- Level 6 is public
				local inside, gate = insideProtectedBay(record, root.Position)
				if not inside then continue end
				-- Let the seat release before moving so a welded chair is never moved with a player.
				if humanoid.SeatPart then humanoid.Sit = false; break end
				local target = (gate * CFrame.new(0, 3, 3.75)).Position
				local outward = Vector3.new(gate.ZVector.X, 0, gate.ZVector.Z)
				local safe = CFrame.lookAt(target, target - outward)
				-- Move the exact live character, preserving its pivot relative to the root.
				character:PivotTo(safe * root.CFrame:ToObjectSpace(character:GetPivot()))
				root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				model:SetAttribute("DevBayDeniedEntryCount", model:GetAttribute("DevBayDeniedEntryCount") + 1)
				break
			end
		end
	end))
	return state
end

return Module
