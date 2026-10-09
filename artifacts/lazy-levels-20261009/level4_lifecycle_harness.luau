-- A deliberately small DataModel/scheduler for actual-source lifecycle fragments.
local checks, clock, nextJob = 0, 0, 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local allConnections, jobs = {}, {}
local function signal()
	local callbacks = {}
	local s = {}
	function s:Connect(callback)
		local connection = {Connected = true}
		function connection:Disconnect() self.Connected = false; callbacks[self] = nil end
		callbacks[connection] = callback
		allConnections[#allConnections + 1] = connection
		return connection
	end
	function s:Fire(...)
		local copy = {}
		for connection, callback in pairs(callbacks) do copy[connection] = callback end
		for connection, callback in pairs(copy) do if connection.Connected then callback(...) end end
	end
	function s:DisconnectAll()
		for connection in pairs(callbacks) do connection:Disconnect() end
	end
	return s
end
local function connectionCount()
	local n = 0
	for _, connection in ipairs(allConnections) do if connection.Connected then n += 1 end end
	return n
end
task = {}
function task.spawn(callback)
	local thread = coroutine.create(callback)
	nextJob += 1
	jobs[thread] = {At = clock, Id = nextJob}
	local ok, delay = coroutine.resume(thread)
	assert(ok, delay)
	if coroutine.status(thread) == "dead" then jobs[thread] = nil else jobs[thread].At = clock + (delay or 0) end
	return thread
end
function task.wait(delay) return coroutine.yield(delay or 0) end
function task.cancel(thread) jobs[thread] = nil end
local function jobCount()
	local n = 0
	for _ in pairs(jobs) do n += 1 end
	return n
end
local function advance(seconds)
	local target, passes = clock + seconds, 0
	while true do
		local due, timeAt, id
		for thread, job in pairs(jobs) do
			if job.At <= target and (not due or job.At < timeAt or (job.At == timeAt and job.Id < id)) then
				due, timeAt, id = thread, job.At, job.Id
			end
		end
		if not due then break end
		clock = timeAt
		passes += 1
		assert(passes < 10000, "scheduler did not yield")
		local ok, delay = coroutine.resume(due)
		assert(ok, delay)
		if coroutine.status(due) == "dead" then jobs[due] = nil else jobs[due].At = clock + (delay or 0) end
	end
	clock = target
end
local function colour()
	return {__type = "Color3", Lerp = function(self) return self end}
end
local engineTypeof = typeof
local function typeof(value)
	return type(value) == "table" and value.__type or engineTypeof(value)
end
Color3 = {new = colour, fromRGB = colour}
UDim2 = {new = function(...) return {...} end, fromScale = function(...) return {...} end}
Vector2 = {new = function(...) return {...} end}
Vector3 = {zero = {X = 0, Y = 0, Z = 0}}
Enum = {
	ModelStreamingMode = {Default = "Default", Persistent = "Persistent", PersistentPerPlayer = "PersistentPerPlayer"},
	Material = {Neon = "Neon", SmoothPlastic = "SmoothPlastic"},
	EasingStyle = {Sine = "Sine"}, EasingDirection = {InOut = "InOut"},
	NormalId = {Front = "Front", Back = "Back"},
}
Random = {new = function()
	return {NextNumber = function(self, lo, hi) return lo or 0 end, NextInteger = function(self, lo, hi) return lo end}
end}
TweenInfo = {new = function(...) return {...} end}
local activeTweens = {}
local TweenService = {}
function TweenService:Create(instance, _, goals)
	local tween = {}
	function tween:Play()
		activeTweens[self] = true
		for property, value in pairs(goals) do instance[property] = value end
	end
	function tween:Cancel() activeTweens[self] = nil end
	return tween
end
local function tweenCount()
	local n = 0
	for _ in pairs(activeTweens) do n += 1 end
	return n
end
local allInstances = {}
Instance = {}
function Instance.new(className)
	local fields, attributes, signals, children, tags = {ClassName = className, Name = className}, {}, {}, {}, {}
	local inst, methods
	methods = {}
	function methods:IsA(kind)
		return className == kind or (kind == "BasePart" and (className == "Part" or className == "MeshPart"))
			or (kind == "Light" and className == "PointLight")
	end
	function methods:GetChildren() local list = {} for _, child in ipairs(children) do list[#list + 1] = child end return list end
	function methods:GetDescendants()
		local list = {}
		for _, child in ipairs(children) do
			list[#list + 1] = child
			for _, descendant in ipairs(child:GetDescendants()) do list[#list + 1] = descendant end
		end
		return list
	end
	function methods:FindFirstChild(name)
		for _, child in ipairs(children) do if child.Name == name then return child end end
	end
	function methods:WaitForChild(name) return self:FindFirstChild(name) end
	function methods:FindFirstChildOfClass(kind)
		for _, child in ipairs(children) do if child:IsA(kind) then return child end end
	end
	function methods:FindFirstAncestorWhichIsA(kind)
		local parent = fields.Parent
		while parent do if parent:IsA(kind) then return parent end parent = parent.Parent end
	end
	function methods:IsDescendantOf(parent)
		local current = fields.Parent
		while current do if current == parent then return true end current = current.Parent end
		return false
	end
	function methods:SetAttribute(name, value)
		local previous = attributes[name]
		attributes[name] = value
		if previous ~= value and signals[name] then signals[name]:Fire() end
	end
	function methods:GetAttribute(name) return attributes[name] end
	function methods:GetAttributeChangedSignal(name)
		signals[name] = signals[name] or signal()
		return signals[name]
	end
	function methods:HasTag(tag) return tags[tag] == true end
	function methods:AddTag(tag) tags[tag] = true end
	function methods:AddPersistentPlayer(player)
		assert(fields.ModelStreamingMode == Enum.ModelStreamingMode.PersistentPerPlayer, "invalid persistence mode")
		fields.PersistentPlayers = fields.PersistentPlayers or {}
		fields.PersistentPlayers[player] = true
		fields.AddCalls = (fields.AddCalls or 0) + 1
	end
	function methods:RemovePersistentPlayer(player)
		fields.PersistentPlayers[player] = nil
		fields.RemoveCalls = (fields.RemoveCalls or 0) + 1
	end
	function methods:Destroy()
		self.Destroying:Fire()
		for _, child in ipairs(self:GetChildren()) do child:Destroy() end
		self.Parent = nil
		for _, value in pairs(fields) do
			if type(value) == "table" and value.DisconnectAll then value:DisconnectAll() end
		end
		for _, value in pairs(signals) do value:DisconnectAll() end
		fields.Destroyed = true
	end
	fields.ChildAdded, fields.ChildRemoved = signal(), signal()
	fields.DescendantAdded, fields.DescendantRemoving = signal(), signal()
	fields.AncestryChanged, fields.Destroying = signal(), signal()
	inst = setmetatable({}, {
		__index = function(_, property) return methods[property] or fields[property] end,
		__newindex = function(_, property, value)
			assert(not fields.Destroyed, "write to destroyed " .. className)
			if property == "Parent" then
				local old = fields.Parent
				if old == value then return end
				local descendants = inst:GetDescendants()
				local function fireUp(parent, event)
					while parent do
						parent[event]:Fire(inst)
						for _, descendant in ipairs(descendants) do parent[event]:Fire(descendant) end
						parent = parent.Parent
					end
				end
				fireUp(old, "DescendantRemoving")
				if old then
					for i, child in ipairs(old._Children) do if child == inst then table.remove(old._Children, i); break end end
				end
				fields.Parent = value
				if old then old.ChildRemoved:Fire(inst) end
				if value then
					table.insert(value._Children, inst)
					value.ChildAdded:Fire(inst)
					fireUp(value, "DescendantAdded")
				end
				inst.AncestryChanged:Fire(inst, value)
				for _, descendant in ipairs(descendants) do descendant.AncestryChanged:Fire(descendant, descendant.Parent) end
			else fields[property] = value end
		end,
	})
	fields._Children = children
	allInstances[#allInstances + 1] = inst
	return inst
end
local function object(className, name, parent)
	local item = Instance.new(className)
	item.Name = name
	item.Parent = parent
	return item
end
workspace = object("Workspace", "Workspace")
local ServerStorage = object("ServerStorage", "ServerStorage")
local ReplicatedStorage = object("ReplicatedStorage", "ReplicatedStorage")
local Players = object("Players", "Players")
Players.PlayerAdded, Players.PlayerRemoving = signal(), signal()
function Players:GetPlayers() return self:GetChildren() end
local game = {GetService = function(_, name)
	return ({Players = Players, TweenService = TweenService, ServerStorage = ServerStorage})[name]
end}
local function newPlayer(name)
	local player = object("Player", name, Players)
	Players.PlayerAdded:Fire(player)
	return player
end
local function leavePlayer(player)
	Players.PlayerRemoving:Fire(player)
	player.Parent = nil
end
