-- Engine-boundary mocks only. Production helpers are substituted by the Python runner.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local function signal()
	local records = {}
	local event = {}
	function event:Connect(callback)
		local connection = {Connected = true, Callback = callback}
		function connection:Disconnect() self.Connected = false end
		table.insert(records, connection)
		return connection
	end
	function event:Fire(...)
		for _, connection in ipairs(table.clone(records)) do
			if connection.Connected then connection.Callback(...) end
		end
	end
	function event:Count()
		local total = 0
		for _, connection in ipairs(records) do if connection.Connected then total += 1 end end
		return total
	end
	return event
end
local function character(world, health, withRoot, withHead)
	local model = {Parent = world, Humanoid = {Health = health}}
	function model:FindFirstChildOfClass(class)
		return class == "Humanoid" and self.Humanoid or nil
	end
	function model:FindFirstChild(name)
		return name == "HumanoidRootPart" and self.Root or name == "Head" and self.Head or nil
	end
	function model:WaitForChild(name)
		if name == "Humanoid" then return self.Humanoid end
		return assert(self:FindFirstChild(name), "fixture requested absent child")
	end
	model.Humanoid.Died = signal()
	local function part()
		local item = {Parent = model}
		function item:IsA(class) return class == "BasePart" end
		function item:IsDescendantOf(ancestor) return self.Parent ~= nil and self.Parent.Parent == ancestor end
		return item
	end
	if withRoot ~= false then model.Root = part() end
	if withHead ~= false then model.Head = part() end
	return model
end
local function baseScenario()
	local c = {Now = 0, Roster = {}, Messages = {}, Requests = {}, Tasks = {}, Warnings = {}, inRound = {}}
	c.World = {Attributes = {RoundActive = true, SelectedLevel = 2}, Signals = {}}
	function c.World:GetAttribute(key) return self.Attributes[key] end
	function c.World:GetAttributeChangedSignal(key)
		if not self.Signals[key] then self.Signals[key] = signal() end
		return self.Signals[key]
	end
	c.Players = {PlayerRemoving = signal()}
	function c.Players:GetPlayers() return table.clone(c.Roster) end
	function c.Players:GetPlayerByUserId(id)
		for _, player in ipairs(c.Roster) do
			if player.UserId == id and player.Parent == self then return player end
		end
		return nil
	end
	function c:Player(id, health)
		local player = {UserId = id, Parent = self.Players, Attributes = {InRound = true}, Foci = {}, FocusEvents = {},
			AddCalls = 0, RemoveCalls = 0, Peak = 0, ReplicationFocus = {Own = true}}
		function player:GetAttribute(key) return self.Attributes[key] end
		function player:SetAttribute(key, value) self.Attributes[key] = value end
		function player:AddReplicationFocus(part)
			assert(part:IsA("BasePart") and part:IsDescendantOf(c.World), "focus must be a live server part")
			assert(not self.Foci[part], "focus cannot be installed twice")
			self.Foci[part] = true
			self.AddCalls += 1
			table.insert(self.FocusEvents, {"add", part})
			local total = 0
			for _ in pairs(self.Foci) do total += 1 end
			self.Peak = math.max(self.Peak, total)
		end
		function player:RemoveReplicationFocus(part)
			assert(self.Foci[part], "foreign or already removed focus")
			self.Foci[part] = nil
			self.RemoveCalls += 1
			table.insert(self.FocusEvents, {"remove", part})
		end
		player.Character = character(self.World, health == nil and 100 or health)
		table.insert(self.Roster, player)
		self.inRound[player] = true
		return player
	end
	function c:Foci(player)
		local total = 0
		for _ in pairs(player.Foci) do total += 1 end
		return total
	end
	function c:Leave(player)
		self.Players.PlayerRemoving:Fire(player)
		player.Parent = nil
		self.inRound[player] = nil
	end
	function c:TickTasks()
		for _, thread in ipairs(self.Tasks) do
			if coroutine.status(thread) ~= "dead" then
				local ok, problem = coroutine.resume(thread)
				assert(ok, problem)
			end
		end
	end
	return c
end
