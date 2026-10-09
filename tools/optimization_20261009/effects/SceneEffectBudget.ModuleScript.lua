-- Local decorative effects only. The server/author owns SceneBudgetWantedEnabled.
-- Do not opt in objectives, emergency lights, characters or gameplay beams.
-- A separate desired-state attribute avoids the same-value Enabled=false race.
local Budget = {}
Budget.__index = Budget

local WANTED = "SceneBudgetWantedEnabled"
local INFLUENCE = "SceneBudgetInfluenceRadius"

local function supported(instance)
	return instance:IsA("Light") or instance:IsA("ParticleEmitter")
end

local function mount(instance)
	local parent = instance.Parent
	if parent and parent:IsA("BasePart") then return parent, parent end
	if parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
		return parent.Parent, parent
	end
	return nil, nil
end

local function position(origin)
	return origin:IsA("Attachment") and origin.WorldPosition or origin.Position
end

local function distanceSquared(a, b)
	local x, y, z = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return x * x + y * y + z * z
end

local function keyAt(p, size)
	-- Columns keep lookup bounded in the long, narrow maps; distance still includes height.
	return math.floor(p.X / size) .. ":" .. math.floor(p.Z / size)
end

function Budget.new(root, options)
	assert(root and options, "SceneEffectBudget needs a root and options")
	assert(options.ActiveDistance >= 128, "ActiveDistance must preserve neighboring rooms")
	assert(options.Hysteresis >= 1, "Hysteresis must be positive")
	local self = setmetatable({
		root = root, options = options, records = {}, watchers = {}, sectors = {}, near = {},
		pending = {}, pendingHead = 1, pendingTail = 0, connections = {}, destroyed = false, tracked = 0,
		lastChecks = 0, lastWrites = 0, cellSize = options.CellSize or 128,
		maxInfluence = options.MaxInfluence or 120, pendingLimit = options.PendingLimit or 128,
	}, Budget)
	assert(self.cellSize >= 64 and self.maxInfluence >= 0 and self.pendingLimit >= 1, "Invalid effect budget")
	table.insert(self.connections, root.DescendantAdded:Connect(function(instance) self:_watch(instance) end))
	table.insert(self.connections, root.DescendantRemoving:Connect(function(instance) self:_forget(instance) end))
	-- One initial scan; later additions/removals use streaming signals.
	local descendants = {}
	if options.ScanRoots then
		for _, name in ipairs(options.ScanRoots) do
			local container = root:FindFirstChild(name)
			if container then
				for _, instance in ipairs(container:GetDescendants()) do table.insert(descendants, instance) end
			end
		end
	else
		descendants = root:GetDescendants()
	end
	for i, instance in ipairs(descendants) do
		if self.destroyed then break end
		if instance:IsDescendantOf(root) then self:_watch(instance) end
		if options.YieldEvery and i % options.YieldEvery == 0 then task.wait() end
	end
	return self
end

function Budget:_desired(record)
	local wanted = record.instance:GetAttribute(WANTED)
	if type(wanted) == "boolean" then record.wanted = wanted end
	return record.wanted
end

function Budget:_write(record, enabled)
	if record.instance.Parent and record.instance.Enabled ~= enabled then
		record.instance.Enabled = enabled
		self.lastWrites += 1
	end
end

function Budget:_unindex(record)
	if not record.sector then return end
	local sector = self.sectors[record.sector]
	if sector then
		sector[record] = nil
		if next(sector) == nil then self.sectors[record.sector] = nil end
	end
	record.sector = nil
end

function Budget:_index(record)
	self:_unindex(record)
	record.position = position(record.origin)
	record.sector = keyAt(record.position, self.cellSize)
	local sector = self.sectors[record.sector]
	if not sector then sector = {}; self.sectors[record.sector] = sector end
	sector[record] = true
	self:_queue(record)
end

function Budget:_queue(record)
	if not record.pending then
		record.pending = true
		self.pendingTail += 1
		self.pending[self.pendingTail] = record
	end
end

function Budget:_remove(record)
	if record.removed then return end
	record.removed = true
	self:_write(record, self:_desired(record))
	self:_unindex(record)
	self.near[record] = nil
	self.records[record.instance] = nil
	self.tracked -= 1
	for _, connection in ipairs(record.connections) do connection:Disconnect() end
	table.clear(record.connections)
end

function Budget:_admit(instance)
	if self.records[instance] or self.destroyed or not instance:IsDescendantOf(self.root) then return end
	local wanted = instance:GetAttribute(WANTED)
	if type(wanted) ~= "boolean" then return end
	local part, origin = mount(instance)
	if not part or not part.Anchored then return end
	local influence = instance:IsA("Light") and instance.Range or instance:GetAttribute(INFLUENCE)
	-- Particles require an explicit bound including lifetime, speed and holder size.
	if type(influence) ~= "number" or influence < 0 or influence > self.maxInfluence then return end
	local record = {instance = instance, part = part, origin = origin, wanted = wanted,
		influence = influence, nearby = true, connections = {}, removed = false}
	self.records[instance] = record
	self.tracked += 1
	self:_index(record)
	table.insert(record.connections, instance:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not record.removed then self:_write(record, self:_desired(record) and record.nearby) end
	end))
	local function moved()
		if record.removed then return end
		if not part.Anchored or not instance:IsDescendantOf(self.root) then self:_remove(record); return end
		self:_index(record)
	end
	table.insert(record.connections, part:GetPropertyChangedSignal("CFrame"):Connect(moved))
	table.insert(record.connections, part:GetPropertyChangedSignal("Anchored"):Connect(moved))
	if origin ~= part then table.insert(record.connections, origin:GetPropertyChangedSignal("Position"):Connect(moved)) end
	if instance:IsA("Light") then
		table.insert(record.connections, instance:GetPropertyChangedSignal("Range"):Connect(function()
			if record.removed then return end
			if instance.Range > self.maxInfluence or instance.Range < 0 then self:_remove(record); return end
			record.influence = instance.Range
			self:_queue(record)
		end))
	else
		table.insert(record.connections, instance:GetAttributeChangedSignal(INFLUENCE):Connect(function()
			if record.removed then return end
			local bound = instance:GetAttribute(INFLUENCE)
			if type(bound) ~= "number" or bound < 0 or bound > self.maxInfluence then self:_remove(record); return end
			record.influence = bound
			self:_queue(record)
		end))
	end
end

function Budget:_watch(instance)
	if self.destroyed or self.watchers[instance] or not supported(instance) then return end
	self.watchers[instance] = instance:GetAttributeChangedSignal(WANTED):Connect(function()
		local record = self.records[instance]
		if type(instance:GetAttribute(WANTED)) ~= "boolean" then
			if record then self:_remove(record) end
		elseif record then
			self:_write(record, self:_desired(record) and record.nearby)
		else
			self:_admit(instance)
		end
	end)
	self:_admit(instance)
end

function Budget:_forget(instance)
	local record = self.records[instance]
	if record then self:_remove(record) end
	local watcher = self.watchers[instance]
	if watcher then watcher:Disconnect(); self.watchers[instance] = nil end
end

function Budget:_evaluate(record, views, considered)
	if record.removed or considered[record] then return end
	considered[record] = true
	self.lastChecks += 1
	local threshold = self.options.ActiveDistance + record.influence
		+ (record.nearby and self.options.Hysteresis or 0)
	local close = false
	for _, view in ipairs(views) do
		if distanceSquared(record.position, view) <= threshold * threshold then close = true; break end
	end
	record.nearby = close
	self.near[record] = close and true or nil
	self:_write(record, self:_desired(record) and close)
end

function Budget:Step(views)
	if self.destroyed then return end
	self.lastChecks, self.lastWrites = 0, 0
	local considered = {}
	if #views == 0 then
		-- No camera/body during respawn: release suppression rather than leave a dark scene.
		for _, record in pairs(self.records) do
			record.nearby = true
			self.near[record] = true
			self:_write(record, self:_desired(record))
		end
		return
	end
	-- Pending initial/streamed instances are processed in bounded batches.
	local tail = self.pendingTail
	local finish = math.min(tail, self.pendingHead + self.pendingLimit - 1)
	for i = self.pendingHead, finish do
		local record = self.pending[i]
		self.pending[i] = nil
		record.pending = false
		self:_evaluate(record, views, considered)
	end
	self.pendingHead = finish + 1
	if self.pendingHead > tail then self.pendingHead, self.pendingTail = 1, 0 end
	-- Grid lookup visits only candidate sectors around the camera and local body.
	local radius = self.options.ActiveDistance + self.maxInfluence + self.options.Hysteresis
	local size = self.cellSize
	for _, view in ipairs(views) do
		for x = math.floor((view.X - radius) / size), math.floor((view.X + radius) / size) do
			for z = math.floor((view.Z - radius) / size), math.floor((view.Z + radius) / size) do
				local sector = self.sectors[x .. ":" .. z]
				if sector then for record in pairs(sector) do self:_evaluate(record, views, considered) end end
			end
		end
	end
	-- The former neighboring sectors must still be switched off after leaving.
	local previouslyNear = {}
	for record in pairs(self.near) do table.insert(previouslyNear, record) end
	for _, record in ipairs(previouslyNear) do self:_evaluate(record, views, considered) end
end

function Budget:Stats()
	local sectors = 0
	for _ in pairs(self.sectors) do sectors += 1 end
	return {Tracked = self.tracked, Sectors = sectors, Checks = self.lastChecks, Writes = self.lastWrites}
end

function Budget:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	for _, watcher in pairs(self.watchers) do watcher:Disconnect() end
	local records = {}
	for _, record in pairs(self.records) do table.insert(records, record) end
	for _, record in ipairs(records) do self:_remove(record) end
	table.clear(self.connections); table.clear(self.watchers); table.clear(self.pending)
	table.clear(self.sectors); table.clear(self.near)
end

return Budget
