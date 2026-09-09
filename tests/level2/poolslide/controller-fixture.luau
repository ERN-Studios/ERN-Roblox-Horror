-- Read-only regression fixture: loadstring this file, call the returned
-- function with the controller source string. All instances, services, tasks,
-- navigation and world state are local TABLES. It never edits a DataModel.
-- Requires Roblox value types Vector3/CFrame/Enum plus loadstring/setfenv.
return function(controllerSource)
	local results = {}
	local function signal()
		local self = {Connections = {}}
		function self:Connect(callback)
			local connection = {Connected = true, Callback = callback}
			function connection:Disconnect() self.Connected = false end
			table.insert(self.Connections, connection)
			return connection
		end
		function self:Fire(...)
			for _, connection in ipairs(table.clone(self.Connections)) do
				if connection.Connected then connection.Callback(...) end
			end
		end
		return self
	end
	local function harness()
		local h = {Clock = 100, Queue = {}, Flags = {}, ModelsCloned = 0, Navigators = {}, Warnings = {}}
		local methods = {}
		local function object(className, name)
			return setmetatable({_class = className, Name = name or className,
				_children = {}, _attributes = {}, Archivable = true}, {
				__index = function(self, key)
					if key == "Parent" then return rawget(self, "_parent") end
					return methods[key]
				end,
				__newindex = function(self, key, value)
					if key ~= "Parent" then rawset(self, key, value) return end
					local old = rawget(self, "_parent")
					if old then
						local index = table.find(old._children, self)
						if index then table.remove(old._children, index) end
					end
					rawset(self, "_parent", value)
					if value then table.insert(value._children, self) end
				end,
			})
		end
		function methods:IsA(className)
			return self._class == className
				or className == "BasePart" and (self._class == "Part" or self._class == "MeshPart")
		end
		function methods:GetAttribute(name) return self._attributes[name] end
		function methods:SetAttribute(name, value) self._attributes[name] = value end
		function methods:GetDescendants()
			local result = {}
			local function walk(parent)
				for _, child in ipairs(parent._children) do table.insert(result, child) walk(child) end
			end
			walk(self)
			return result
		end
		function methods:FindFirstChild(name)
			for _, child in ipairs(self._children) do if child.Name == name then return child end end
		end
		function methods:FindFirstChildOfClass(className)
			for _, child in ipairs(self._children) do if child:IsA(className) then return child end end
		end
		function methods:IsDescendantOf(parent)
			local current = self.Parent
			while current do if current == parent then return true end current = current.Parent end
			return false
		end
		function methods:Destroy()
			for _, child in ipairs(table.clone(self._children)) do child:Destroy() end
			self.Parent = nil
			self.Destroyed = true
		end
		function methods:GetBoundingBox() return CFrame.new(0, 8, 0), Vector3.new(14, 16, 4) end
		function methods:GetPivot() return self.Pivot or CFrame.new(0, 8, 0) end
		function methods:PivotTo(value) self.Pivot = value end
		function methods:Clone()
			h.ModelsCloned += 1
			local clone = object("Model", self.Name)
			local mesh = object("MeshPart", "Pool Slide Mesh")
			mesh.Parent = clone
			clone.PrimaryPart = mesh
			for name, value in pairs(self._attributes) do clone:SetAttribute(name, value) end
			return clone
		end
		h.Workspace = object("Workspace")
		for name, value in pairs({SelectedLevel = 2, RoundActive = true, WorldGenerated = true,
			Level2Pumps = 0, EntityPaused = false}) do h.Workspace:SetAttribute(name, value) end
		function h.Workspace:GetServerTimeNow() return h.Clock end
		function h.Workspace:Raycast(origin, direction)
			if h.Flags.Raycast then return h.Flags.Raycast(origin, direction) end
			return h.Flags.Wall and {Instance = {}} or nil
		end
		h.ServerStorage = object("ServerStorage")
		local assets = object("Folder", "Level2Assets")
		assets.Parent = h.ServerStorage
		local template = object("Model", "Level 2 Pool Slide Template")
		template.Parent = assets
		template.PrimaryPart = object("MeshPart", "Source Mesh")
		template.PrimaryPart.Parent = template
		template:SetAttribute("AgentRadius", 7.1)
		template:SetAttribute("AgentHeight", 16)
		template:SetAttribute("GroundOffset", 8)
		local replicated = object("ReplicatedStorage")
		h.State = object("Folder", "Level 2 State")
		h.State.Parent = replicated
		local world = object("Model", "Level 2 Generated World")
		world.Parent = h.Workspace
		world:SetAttribute("Level2_Generation", 1)
		local anchors = object("Folder", "Navigation")
		anchors.Parent = world
		for index = 1, 6 do
			local anchor = object("Part", "Level 2 Navigation Node " .. index)
			anchor.Position = Vector3.new(120 + index * 30, 0, 0)
			anchor.Parent = anchors
		end
		h.Manifest = {World = world, Layout = {}, Navigation = anchors}
		h.Players = object("Players")
		h.Players.PlayerRemoving = signal()
		function h.Players:GetPlayers() return table.clone(self._children) end
		h.Player = object("Player", "Player One")
		h.Player.UserId = 101
		h.Player.Parent = h.Players
		h.Player:SetAttribute("InRound", true)
		local character = object("Model", "Character")
		character.Parent = h.Workspace
		h.Player.Character = character
		h.Root = object("Part", "HumanoidRootPart")
		h.Root.Position = Vector3.new(0, 3, 0)
		h.Root.Parent = character
		h.Humanoid = object("Humanoid")
		h.Humanoid.Health = 100
		h.Humanoid.Parent = character
		h.State:SetAttribute("Level2_PumpActivatorUserId2", 101)
		h.State:SetAttribute("Level2_PumpActivatorPosition2", h.Root.Position)
		local runService = {Heartbeat = signal()}
		local navigator = {}
		function navigator.new(model, manifest, tuning)
			assert(tuning.AgentHeight == 16 and tuning.AgentRadius == 7.1)
			assert(tuning.StableRoutes == true and tuning.PathRequestTimeout == 8)
			local nav = {Model = model, HasGrounded = false, Position = Vector3.zero, Status = "IDLE",
				Computing = false, RequestStartedAt = -math.huge, Reached = false,
				GoalCalls = 0, GraphCalls = 0, ForcedGraphCalls = 0}
			table.insert(h.Navigators, nav)
			function nav:WarpTo(position)
				assert(not self.Destroyed and not self.HasGrounded, "must use fresh navigator for retry anchor")
				if h.Flags.BlockSpawn then return false end
				self.Position = position
				self.HasGrounded = true
				return true
			end
			function nav:_fallbackWaypoints(goal)
				if h.Flags.OnRoute then h.Flags.OnRoute(h, self) end
				if h.Flags.NoRoute or h.Flags.RejectFirstAnchor and self.Position.X == 150 then
					return {}, "NO_PATH"
				end
				return {goal}, "GRAPH"
			end
			function nav:_clearAdvance() return not h.Flags.BlockEscape end
			function nav:_centreRoute(points, shouldAbort)
				if h.Flags.OnCentre then h.Flags.OnCentre(h, self) end
				return points, {
					Aborted = shouldAbort(), Unwalkable = h.Flags.Unwalkable and 1 or 0,
					Unresolved = h.Flags.Unresolved and 1 or 0,
					Queries = h.Flags.ExhaustedBudget and 72000 or 200,
					GoalFallback = h.Flags.DistantApproach and self.Position
						or h.Flags.ObstructedApproach and (points[#points] + Vector3.new(4, -3, 0))
						or h.Flags.ApproachDistance and (points[#points] + Vector3.new(h.Flags.ApproachDistance, -3, 0)) or nil,
				}
			end
			function nav:GetPosition() return self.Position end
			function nav:GetStatus() return self.Status end
			function nav:GetDebugSnapshot()
				return {Position = self.Position, Status = self.Status, Computing = self.Computing,
					RequestStartedAt = self.RequestStartedAt, Reached = self.Reached}
			end
			function nav:SetGoal(goal)
				self.GoalCalls += 1
				self.Goal = goal self.Status = "PATH" return true
			end
			function nav:SetGraphGoal(goal, force)
				self.GraphCalls += 1
				if force then
					self.ForcedGraphCalls += 1
					self.Computing = true
					self.RequestStartedAt = h.Clock
				end
				return self:SetGoal(goal)
			end
			function nav:Stop() self.Goal = nil self.Status = "IDLE" end
			function nav:Destroy() self.Destroyed = true self:Stop() end
			function nav:Step(dt, speed)
				if h.Flags.StepReached then return true end
				if self.Reached then return false end
				if not self.Goal or h.Flags.FreezeMovement then return end
				local difference = self.Goal - self.Position
				local flat = Vector3.new(difference.X, 0, difference.Z)
				if flat.Magnitude > .001 then self.Position += flat.Unit * math.min(flat.Magnitude, dt * speed) end
			end
			return nav
		end
		local services = {Players = h.Players, ReplicatedStorage = replicated,
			ServerStorage = h.ServerStorage, RunService = runService,
			CollectionService = {AddTag = function(_, instance, tagName)
				instance._tags = instance._tags or {}
				instance._tags[tagName] = true
			end}}
		local environment = setmetatable({
			game = {GetService = function(_, name) return assert(services[name], name) end},
			workspace = h.Workspace,
			script = {Parent = {WaitForChild = function() return "fake navigator module" end}},
			require = function() return navigator end,
			Instance = {new = object}, RaycastParams = {new = function() return {} end},
			os = {clock = function() return h.Clock end},
			task = {defer = function(callback) table.insert(h.Queue, callback) end,
				wait = function() if h.Flags.OnWait then h.Flags.OnWait(h) end end},
			warn = function(message) table.insert(h.Warnings, message) end,
		}, {__index = getfenv()})
		local chunk = assert(loadstring(controllerSource, "PoolSlideControllerUnderTest"))
		setfenv(chunk, environment)
		h.Controller = chunk()
		function h:Start(generation)
			self.Manifest.World:SetAttribute("Level2_Generation", generation or 1)
			local session, failure = self.Controller.Start(self.Manifest, generation or 1)
			assert(session, failure)
			return session
		end
		function h:Step(dt)
			self.Clock += dt or .016
			runService.Heartbeat:Fire(dt or .016)
		end
		function h:Flush()
			local queued = self.Queue
			self.Queue = {}
			for _, callback in ipairs(queued) do callback() end
		end
		function h:Spawn()
			self:Start()
			self.Workspace:SetAttribute("Level2Pumps", 2)
			self:Step()
			self:Flush()
			assert(self.Controller.GetDebugSnapshot().Spawned)
			return self.Navigators[#self.Navigators]
		end
		function h:AssertNoResidue()
			assert(not self.Manifest.World:FindFirstChild("Level 2 Pool Slide Runtime"))
			for _, child in ipairs(self.ServerStorage._children) do assert(child.Name ~= "Level 2 Pool Slide") end
			assert(self.State:GetAttribute("Level2_PoolSlideActive") == false)
			assert(self.Player:GetAttribute("Level2_PoolSlideChased") == nil)
			for _, nav in ipairs(self.Navigators) do assert(nav.Destroyed) end
		end
		return h
	end
	local function test(name, callback)
		local ok, failure = xpcall(callback, debug.traceback)
		table.insert(results, {Name = name, Passed = ok, Error = not ok and tostring(failure) or nil})
	end
	test("second distinct count only; third and repeated edges cannot duplicate", function()
		local h = harness()
		h:Start()
		for count = 0, 1 do h.Workspace:SetAttribute("Level2Pumps", count) h:Step() h:Flush() end
		assert(h.ModelsCloned == 0)
		h.Workspace:SetAttribute("Level2Pumps", 2)
		h:Step() h:Step() h:Step()
		assert(#h.Queue == 1)
		h:Flush()
		for _, count in ipairs({2, 2, 3, 0, 2, 3}) do h.Workspace:SetAttribute("Level2Pumps", count) h:Step() h:Flush() end
		assert(h.ModelsCloned == 1 and h.Controller.GetDebugSnapshot().SpawnCount == 1)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("repeated first-pump updates cannot impersonate a second distinct pump", function()
		local h = harness()
		h:Start()
		-- Activator metadata or a station's own ordinal is not the count of
		-- distinct started pumps published by the production objective system.
		h.State:SetAttribute("Level2_PumpActivatorUserId2", h.Player.UserId)
		h.State:SetAttribute("Level2_PumpActivatorPosition2", h.Root.Position)
		h.Workspace:SetAttribute("Level2Pumps", 1)
		for _ = 1, 20 do h:Step(1) h:Flush() end
		assert(h.ModelsCloned == 0 and #h.Queue == 0)
		assert(not h.Controller.GetDebugSnapshot().Spawned)
		h.Workspace:SetAttribute("Level2Pumps", 1.99)
		h:Step() h:Flush()
		assert(h.ModelsCloned == 0, "fractional count below two incorrectly spawned giant")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	for _, count in ipairs({2, 3, 4}) do
		test("count jump directly to " .. count .. " starts exactly one second-pump encounter", function()
			local h = harness()
			h:Start()
			h.Workspace:SetAttribute("Level2Pumps", count)
			h:Step() h:Step() h:Step()
			assert(#h.Queue == 1, "count jump queued zero or duplicate spawn tasks")
			h:Flush()
			assert(h.ModelsCloned == 1 and h.Controller.GetDebugSnapshot().SpawnCount == 1)
			for _, later in ipairs({count, 3, 4, 2, 0, 2}) do
				h.Workspace:SetAttribute("Level2Pumps", later)
				h:Step() h:Flush()
			end
			assert(h.ModelsCloned == 1 and h.Controller.GetDebugSnapshot().SpawnCount == 1,
				"later pump progress duplicated the second-pump giant")
			h.Controller.Stop() h:AssertNoResidue()
		end)
	end
	test("spawn focus uses second activator and ignores poisoned third-pump payload", function()
		local h = harness()
		h.State:SetAttribute("Level2_PumpActivatorUserId3", -999)
		h.State:SetAttribute("Level2_PumpActivatorPosition3", Vector3.new(1000, 3, 0))
		h:Spawn()
		assert(h.State:GetAttribute("Level2_PoolSlideSpawnAnchor") == "Level 2 Navigation Node 1",
			"second-pump spawn was ranked around future third-pump metadata")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("missing second activator uses second captured position, not third activator", function()
		local h = harness()
		h.State:SetAttribute("Level2_PumpActivatorUserId2", -999)
		h.State:SetAttribute("Level2_PumpActivatorPosition2", Vector3.new(1000, 3, 0))
		h.State:SetAttribute("Level2_PumpActivatorUserId3", h.Player.UserId)
		h.State:SetAttribute("Level2_PumpActivatorPosition3", h.Root.Position)
		h:Spawn()
		assert(h.State:GetAttribute("Level2_PoolSlideSpawnAnchor") == "Level 2 Navigation Node 6",
			"spawn fallback ignored captured second-pump position")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("second-pump count withdrawn before deferred work cancels, later second count retries", function()
		local h = harness()
		h:Start()
		h.Workspace:SetAttribute("Level2Pumps", 2)
		h:Step()
		h.Workspace:SetAttribute("Level2Pumps", 1)
		h:Flush()
		assert(h.ModelsCloned == 0 and not h.Controller.GetDebugSnapshot().Spawned,
			"cancelled second-pump request committed below threshold")
		h.Workspace:SetAttribute("Level2Pumps", 2)
		h:Step(2.1) h:Flush()
		assert(h.ModelsCloned == 1 and h.Controller.GetDebugSnapshot().SpawnCount == 1)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("new generation resets second-pump latch without spawning on its first pump", function()
		local h = harness()
		local oldNav = h:Spawn()
		h.Workspace:SetAttribute("Level2Pumps", 0)
		h:Start(2)
		assert(oldNav.Destroyed and oldNav.Model.Parent == nil)
		h.Workspace:SetAttribute("Level2Pumps", 1)
		h:Step() h:Flush()
		assert(h.ModelsCloned == 1 and not h.Controller.GetDebugSnapshot().Spawned)
		h.Workspace:SetAttribute("Level2Pumps", 2)
		h:Step() h:Flush()
		local snapshot = h.Controller.GetDebugSnapshot()
		assert(h.ModelsCloned == 2 and snapshot.Generation == 2 and snapshot.SpawnCount == 1)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("cleanup before deferred spawn; no late clone", function()
		local h = harness()
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step()
		h.Controller.Stop() h:Flush()
		assert(h.ModelsCloned == 0) h:AssertNoResidue()
	end)
	test("cleanup while yielding validation; private clone cleaned", function()
		local h = harness()
		h.Flags.BlockSpawn = true
		h.Flags.OnWait = function() h.Controller.Stop() end
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		assert(h.ModelsCloned == 1) h:AssertNoResidue()
	end)
	test("new generation survives previous deferred task", function()
		local h = harness()
		h.Flags.BlockSpawn = true
		h.Flags.OnWait = function()
			h.Flags.OnWait = nil
			h.Workspace:SetAttribute("Level2Pumps", 0)
			h:Start(2)
		end
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		local snapshot = h.Controller.GetDebugSnapshot()
		assert(snapshot.Running and snapshot.Generation == 2 and not snapshot.Spawned)
		assert(h.State:GetAttribute("Level2_PoolSlideGeneration") == 2)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("grounded rejected candidate gets fresh navigator", function()
		local h = harness()
		h.Flags.RejectFirstAnchor = true
		h:Spawn()
		assert(#h.Navigators == 2 and h.Navigators[1].Destroyed)
		assert(h.State:GetAttribute("Level2_PoolSlideSpawnAnchor") == "Level 2 Navigation Node 2")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("nearby visible anchor precedes distant hidden hall routes", function()
		local h = harness()
		h.Manifest.Navigation:FindFirstChild("Level 2 Navigation Node 1").Position = Vector3.new(80, 0, 0)
		h.Manifest.Navigation:FindFirstChild("Level 2 Navigation Node 3").Position = Vector3.new(50, 0, 0)
		h.Flags.Raycast = function(origin, direction)
			return (origin + direction).X >= 180 and {Instance = {}} or nil
		end
		local certifications = 0
		h.Flags.OnCentre = function() certifications += 1 end
		h:Spawn()
		assert(h.State:GetAttribute("Level2_PoolSlideSpawnAnchor") == "Level 2 Navigation Node 1")
		assert(h.State:GetAttribute("Level2_PoolSlideSpawnDistance") == 80)
		assert(h.State:GetAttribute("Level2_PoolSlideSpawnHidden") == false)
		assert(#h.Navigators == 1 and certifications == 1, "ranked anchor must still pass body certification")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("failed route retries without candidate leak", function()
		local h = harness()
		h.Flags.NoRoute = true
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		assert(not h.Controller.GetDebugSnapshot().Spawned)
		for _, child in ipairs(h.ServerStorage._children) do assert(child.Name ~= "Level 2 Pool Slide") end
		h.Flags.NoRoute = false
		h:Step(2.1) h:Flush()
		assert(h.Controller.GetDebugSnapshot().SpawnCount == 1)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("commit-time player proximity closes ranking race", function()
		local h = harness()
		h.Flags.OnRoute = function(_, nav) h.Root.Position = nav:GetPosition() + Vector3.new(0, 3, 0) end
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		assert(not h.Controller.GetDebugSnapshot().Spawned)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("pause after spawn request permits commit, freezes motion and damage, resume uses same model", function()
		local h = harness()
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step()
		h.Workspace:SetAttribute("EntityPaused", true) h:Flush()
		assert(h.ModelsCloned == 1 and h.Controller.GetDebugSnapshot().State == "PAUSED")
		local nav = h.Navigators[#h.Navigators]
		local model = nav.Model
		assert(model:IsDescendantOf(h.Workspace) and model._tags.Level2HostileEntity
			and model._tags.Level2PoolSlideEntity, "paused spawn must be replicated and ESP-discoverable")
		local before = nav:GetPosition()
		h.Root.Position = before + Vector3.new(1, 3, 0)
		for _ = 1, 8 do h:Step(.1) h:Flush() end
		assert(nav:GetPosition() == before and h.Controller.GetDebugSnapshot().State == "PAUSED")
		assert(h.State:GetAttribute("Level2_PoolSlideMoving") == false)
		assert(h.Humanoid.Health == 100 and h.Player:GetAttribute("Level2_PoolSlideChased") == nil)
		h.Root.Position = Vector3.new(0, 3, 0)
		h.Workspace:SetAttribute("EntityPaused", false) h:Step(.1)
		assert(nav:GetPosition() ~= before and h.Controller.GetDebugSnapshot().State ~= "PAUSED")
		assert(nav.Model == model and h.ModelsCloned == 1 and h.Controller.GetDebugSnapshot().SpawnCount == 1)
		local resumedPosition = nav:GetPosition()
		h.Workspace:SetAttribute("EntityPaused", true) h:Step(.1)
		assert(nav:GetPosition() == resumedPosition and h.Controller.GetDebugSnapshot().State == "PAUSED")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("second pump while already paused produces one visible tagged model; first count does not", function()
		local h = harness()
		h.Workspace:SetAttribute("EntityPaused", true)
		h:Start()
		for count = 0, 1 do h.Workspace:SetAttribute("Level2Pumps", count) h:Step() h:Flush() end
		assert(h.ModelsCloned == 0)
		h.Workspace:SetAttribute("Level2Pumps", 2)
		h:Step() h:Step() h:Step()
		assert(#h.Queue == 1)
		h:Flush()
		local nav = h.Navigators[#h.Navigators]
		local before = nav:GetPosition()
		for _, count in ipairs({2, 0, 2, 3, 3}) do h.Workspace:SetAttribute("Level2Pumps", count) h:Step() h:Flush() end
		local snapshot = h.Controller.GetDebugSnapshot()
		assert(snapshot.Spawned and snapshot.SpawnCount == 1 and snapshot.State == "PAUSED")
		assert(h.ModelsCloned == 1 and nav.Model:IsDescendantOf(h.Workspace))
		assert(nav.Model._tags.Level2HostileEntity and nav.Model._tags.Level2PoolSlideEntity)
		assert(nav:GetPosition() == before and h.Humanoid.Health == 100)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("pause during body certification commits directly in paused state", function()
		local h = harness()
		h.Flags.OnCentre = function() h.Workspace:SetAttribute("EntityPaused", true) end
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		assert(h.Controller.GetDebugSnapshot().Spawned and h.Controller.GetDebugSnapshot().State == "PAUSED")
		assert(h.ModelsCloned == 1 and h.Humanoid.Health == 100)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("paused spawn still cancels on round end before deferred work", function()
		local h = harness()
		h.Workspace:SetAttribute("EntityPaused", true)
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step()
		h.Workspace:SetAttribute("RoundActive", false) h:Flush()
		assert(h.ModelsCloned == 0 and not h.Controller.GetDebugSnapshot().Spawned)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("paused validation still cancels and cleans private model on Stop", function()
		local h = harness()
		h.Workspace:SetAttribute("EntityPaused", true)
		h.Flags.OnCentre = function() h.Controller.Stop() end
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		assert(h.ModelsCloned == 1)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	for _, kind in ipairs({"Unwalkable", "Unresolved", "ExhaustedBudget", "DistantApproach", "ObstructedApproach"}) do
		test("uncertified route rejected: " .. kind, function()
			local h = harness()
			h.Flags[kind] = true
			if kind == "ObstructedApproach" then h.Flags.Wall = true end
			h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
			assert(not h.Controller.GetDebugSnapshot().Spawned)
			h.Controller.Stop() h:AssertNoResidue()
		end)
	end
	test("cleanup during body certification cancels commit", function()
		local h = harness()
		h.Flags.OnCentre = function() h.Controller.Stop() end
		h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
		h:AssertNoResidue()
	end)
	test("watchdog allows slow bounded planning beyond two seconds", function()
		local h = harness()
		local nav = h:Spawn()
		h.Flags.FreezeMovement = true
		nav.Computing = true
		nav.RequestStartedAt = h.Clock
		for _ = 1, 3 do h:Step(2.1) end
		assert(nav.ForcedGraphCalls == 0, "watchdog cancelled a valid in-flight route before its deadline")
		assert(nav.Computing and h.Clock - nav.RequestStartedAt > 6)
		h.Controller.Stop() h:AssertNoResidue()
	end)
	test("watchdog retries an expired request once, then allows the replacement to finish", function()
		local h = harness()
		local nav = h:Spawn()
		h.Flags.FreezeMovement = true
		nav.Computing = true
		nav.RequestStartedAt = h.Clock
		h:Step(8.1)
		assert(nav.ForcedGraphCalls == 1, "expired request did not enter graph recovery")
		assert(nav.RequestStartedAt == h.Clock)
		h:Step(2.1)
		assert(nav.ForcedGraphCalls == 1, "replacement request was cancelled at the next progress sample")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	for _, source in ipairs({"Step", "Snapshot"}) do
		test("watchdog leaves certified approach arrival idle via " .. source, function()
			local h = harness()
			local nav = h:Spawn()
			h.Flags.FreezeMovement = true
			if source == "Step" then h.Flags.StepReached = true else nav.Reached = true end
			local before = nav:GetPosition()
			for _ = 1, 6 do h:Step(2.1) end
			assert(nav.ForcedGraphCalls == 0, "certified approach was treated as a stuck creature")
			assert(nav:GetPosition() == before and h.Humanoid.Health == 100)
			h.Controller.Stop() h:AssertNoResidue()
		end)
	end
	test("watchdog recovers a stationary noncomputing route", function()
		local h = harness()
		local nav = h:Spawn()
		h.Flags.FreezeMovement = true
		h:Step(2.1)
		assert(nav.ForcedGraphCalls == 1, "a real noncomputing stall was ignored")
		h.Controller.Stop() h:AssertNoResidue()
	end)
	for _, scenario in ipairs({
		{Name = "certified visible17-stud approach admitted", Distance = 17, Accepted = true},
		{Name = "approach beyond24-stud spawn bound rejected", Distance = 24.1, Accepted = false},
		{Name = "17-stud approach acrosswall rejected", Distance = 17, Wall = true, Accepted = false},
	}) do
		test(scenario.Name, function()
			local h = harness()
			h.Flags.ApproachDistance = scenario.Distance
			h.Flags.Wall = scenario.Wall
			h:Start() h.Workspace:SetAttribute("Level2Pumps", 2) h:Step() h:Flush()
			assert(h.Controller.GetDebugSnapshot().Spawned == scenario.Accepted)
			assert(h.Humanoid.Health == 100, "spawn approach is not attack reach")
			h.Controller.Stop() h:AssertNoResidue()
		end)
	end
	for _, kind in ipairs({"Wall", "HighFloor", "Escaped", "OutOfRound", "Dead", "CloseHit"}) do
		test("server attack gate: " .. kind, function()
			local h = harness()
			local nav = h:Spawn()
			h.Flags.FreezeMovement = true
			nav.Position = Vector3.new(4, 0, 0)
			if kind == "Wall" then h.Flags.Wall = true end
			if kind == "HighFloor" then h.Root.Position = Vector3.new(0, 12, 0) end
			if kind == "Escaped" then h.Player:SetAttribute("Escaped", true) end
			if kind == "OutOfRound" then h.Player:SetAttribute("InRound", false) end
			if kind == "Dead" then h.Humanoid.Health = 0 end
			h:Step()
			if kind == "CloseHit" or kind == "Dead" then assert(h.Humanoid.Health == 0)
			else assert(h.Humanoid.Health == 100) end
			assert(h.Player:GetAttribute("BeingChased") == nil)
			h.Controller.Stop() h:AssertNoResidue()
		end)
	end
	local passed = 0
	for _, result in ipairs(results) do if result.Passed then passed += 1 end end
	return {Passed = passed, Total = #results, Results = results}
end
