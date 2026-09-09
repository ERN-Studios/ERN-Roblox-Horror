-- Read-only regression fixture. Compile with Edit-time loadstring, then call
-- the returned function with the production Pool Foam Navigator source.
-- No Instances are created: Model, services, world and async scheduler are local
-- tables. Roblox Vector3/CFrame/Enum value types are used without a DataModel.
-- Production constructor, request lifecycle, route installation and Step run;
-- only path service, centring and spatial predicates are controlled test seams.
return function(navigatorSource)
	local results = {}
	local function v(x, z) return Vector3.new(x, 0, z or 0) end
	local function near(a, b) return (a - b).Magnitude < .001 end
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
	local function harness(stable)
		local h = {Clock = 100, Queue = {}, Flags = {}, Paths = {}, Requests = {},
			CentreInputs = {}, EdgeProbes = {}, Placements = {}}
		local pathService = {}
		function pathService:CreatePath(options)
			local path = {Status = Enum.PathStatus.Success, Blocked = signal(), Options = options}
			table.insert(h.Paths, path)
			function path:ComputeAsync(from, goal)
				table.insert(h.Requests, {From = from, Goal = goal, At = h.Clock})
				self.Points = table.clone(h.Flags.RawPoints or {from, goal})
				if h.Flags.OnCompute then h.Flags.OnCompute(h, self, from, goal) end
				if h.Flags.ComputeError then error("controlled path-service failure") end
				if h.Flags.NoPath then self.Status = Enum.PathStatus.NoPath end
			end
			function path:GetWaypoints()
				local points = {}
				for _, point in ipairs(self.Points) do table.insert(points, {Position = point}) end
				return points
			end
			return path
		end
		local environment = setmetatable({
			game = {GetService = function(_, name)
				if name == "PathfindingService" then return pathService end
				if name == "Players" then return {GetPlayers = function() return {} end} end
				error("unexpected service: " .. tostring(name))
			end},
			workspace = {},
			RaycastParams = {new = function() return {} end},
			OverlapParams = {new = function() return {} end},
			os = {clock = function() return h.Clock end},
			task = {spawn = function(callback) table.insert(h.Queue, callback) end,
				defer = function(callback) table.insert(h.Queue, callback) end,
				wait = function() if h.Flags.OnWait then h.Flags.OnWait(h) end return 0 end},
		}, {__index = getfenv()})
		local chunk = assert(loadstring(navigatorSource, "PoolFoamNavigatorUnderTest"))
		setfenv(chunk, environment)
		local Navigator = chunk()
		local root = {IsA = function(_, name) return name == "BasePart" end}
		local model = {Parent = {}, PrimaryPart = root, Pivot = CFrame.new(0, 8, 0)}
		function model:IsA(name) return name == "Model" end
		function model:GetAttribute(name) return name == "GroundOffset" and 8 or nil end
		function model:GetPivot() return self.Pivot end
		function model:GetBoundingBox() return self.Pivot, Vector3.new(14, 16, 4) end
		function model:GetDescendants() return {} end
		function model:PivotTo(pivot)
			self.Pivot = pivot
			table.insert(h.Placements, pivot.Position - v(0) - Vector3.new(0, 8, 0))
		end
		local world = {GetDescendants = function() return {} end, FindFirstChild = function() return nil end}
		local tuning = {StableRoutes = stable ~= false, PathRequestTimeout = 8,
			AgentRadius = 7.1, PathAgentRadius = 7.1, AgentHeight = 16,
			WaypointSpacing = 5, WaypointArrivalDistance = 2, RepathDistance = 6,
			RepathInterval = .65, FootClearance = 0, FloorProbeAbove = 18,
			FloorProbeDepth = 80, MaxStepHeight = 3.5, MaxTravelStep = .9,
			SteerAngles = {20, 35, 50}}
		local nav = Navigator.new(model, {World = world, Layout = {Halls = {}, Corridors = {}}}, tuning)
		h.Nav = nav
		nav.FootPosition = v(0)
		nav.Facing = v(1)
		nav.HasGrounded = true
		function nav:_positionAllowed(point)
			return not h.Flags.PositionAllowed or h.Flags.PositionAllowed(point)
		end
		function nav:_pathPointsAllowed() return true end
		function nav:_fallbackWaypoints(goal)
			if h.Flags.NoGraph then return {}, "NO_PATH" end
			return table.clone(h.Flags.GraphPoints or {self.FootPosition, goal}), "GRAPH"
		end
		function nav:_centreRoute(points, shouldAbort)
			table.insert(h.CentreInputs, table.clone(points))
			if h.Flags.OnCentre then h.Flags.OnCentre(h, points, shouldAbort) end
			if h.Flags.MissingStats then return points, nil end
			local stats = {Unwalkable = 0, Unresolved = 0, Queries = 100,
				Aborted = shouldAbort and shouldAbort() or false}
			for key, value in pairs(h.Flags.Stats or {}) do stats[key] = value end
			return table.clone(h.Flags.CentredPoints or points), stats
		end
		function nav:_surfaceAt() return 0 end
		function nav:_bodyBoxClear(point)
			return not h.Flags.Standable or h.Flags.Standable(point)
		end
		function nav:_bodySweepClear(from, to)
			return not h.Flags.EdgeClear or h.Flags.EdgeClear(from, to)
		end
		function nav:_standableAt(point)
			local foot = v(point.X, point.Z)
			return self:_bodyBoxClear(foot), foot
		end
		function nav:_walkingEdgeClear(from, to)
			table.insert(h.EdgeProbes, {From = from, To = to, At = h.Clock})
			if h.Flags.WalkingEdge then return h.Flags.WalkingEdge(from, to) end
			local ok = self:_bodyBoxClear(to) and self:_bodySweepClear(from, to)
			return ok, ok and v(to.X, to.Z) or from, 3
		end
		function h:FlushOne()
			local callback = table.remove(self.Queue, 1)
			assert(callback, "expected queued navigation request")
			callback()
		end
		function h:Flush()
			local count = 0
			while #self.Queue > 0 do
				count += 1
				assert(count <= 20, "request loop exceeded bounded fixture flush")
				self:FlushOne()
			end
		end
		function h:Plan(goal, graph)
			if graph then self.Nav:SetGraphGoal(goal) else self.Nav:SetGoal(goal) end
			self:Flush()
		end
		function h:Step(dt, speed)
			self.Clock += dt
			return self.Nav:Step(dt, speed)
		end
		function h:CurrentWaypoint() return self.Nav.Waypoints[self.Nav.WaypointIndex] end
		function h:SeedRoute(points, goal, position)
			self.Nav.FootPosition = position or v(0)
			self.Nav.Waypoints = table.clone(points)
			self.Nav.WaypointIndex = 1
			self.Nav.Goal = goal
			self.Nav.LastRequestedGoal = goal
			self.Nav.LastPathAt = self.Clock
			self.Nav.Status = "PATH"
			return self.Nav.Waypoints
		end
		function h:BlockAt(x)
			self.Flags.RawPoints = {v(0), v(20), v(40), v(60), v(100)}
			self.Flags.GraphPoints = table.clone(self.Flags.RawPoints)
			self.Flags.Stats = {Unwalkable = 1}
			self.Flags.EdgeClear = function(_, to) return to.X <= x + .001 end
			self.Flags.WalkingEdge = function(from, to)
				if to.X <= x + .001 then return true, to, 3 end
				return false, from.X <= x and v(x) or from, 3
			end
		end
		return h
	end
	local function test(name, callback)
		local ok, failure = xpcall(callback, debug.traceback)
		table.insert(results, {Name = name, Passed = ok, Error = not ok and tostring(failure) or nil})
	end
	test("stable tuning reaches production constructor", function()
		local h = harness()
		assert(h.Nav.Tuning.StableRoutes == true, "StableRoutes was silently discarded")
		assert(h.Nav.Tuning.PathRequestTimeout == 8, "PathRequestTimeout was silently discarded")
	end)
	test("stationary target keeps its route after timer expiry", function()
		local h = harness()
		h:Plan(v(100))
		local requestId = h.Nav.RequestId
		for _ = 1, 12 do
			h.Clock += 1
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
		end
		assert(h.Nav.RequestId == requestId and #h.Requests == 1,
			"unchanged goal caused timer-only replacement requests")
	end)
	test("moving target is throttled by request interval", function()
		local h = harness()
		h:Plan(v(100))
		h.Clock += .1
		h.Nav:SetGoal(v(112))
		assert(#h.Queue == 0, "moved target bypassed minimum request interval")
		h.Clock += .56
		h.Nav:SetGoal(v(112))
		assert(#h.Queue == 1, "material target movement did not request after interval")
		h:Flush()
		assert(#h.Requests == 2)
	end)
	test("sub-threshold target drift does not replace route", function()
		local h = harness()
		h:Plan(v(100))
		h.Clock += 2
		h.Nav:SetGoal(v(103))
		assert(#h.Queue == 0, "minor target drift needlessly replaced a valid route")
	end)
	test("delayed ComputeAsync result cannot send entity back to old start", function()
		local h = harness()
		h.Flags.RawPoints = {v(0), v(5), v(10), v(30), v(60), v(100)}
		h.Flags.OnCompute = function(state)
			state.Clock += .4
			state.Nav.FootPosition = v(20)
		end
		h:Plan(v(100))
		local waypoint = h:CurrentWaypoint()
		assert(waypoint and waypoint.X >= 20, "installed a stale prefix behind current foot")
		local before = h.Nav.FootPosition
		h:Step(1 / 60, 24)
		assert(h.Nav.FootPosition.X >= before.X, "real Step reversed after delayed route")
	end)
	test("movement while centring is rebased again at installation", function()
		local h = harness()
		h.Flags.RawPoints = {v(0), v(10), v(30), v(60), v(100)}
		h.Flags.OnCentre = function(state)
			state.Clock += .4
			state.Nav.FootPosition = v(35)
		end
		h:Plan(v(100))
		local waypoint = h:CurrentWaypoint()
		assert(waypoint and waypoint.X >= 35, "centring yield reintroduced a stale waypoint")
	end)
	test("long delayed dense route rejoins beyond its first sixteen points", function()
		local h = harness()
		local points = {}
		for x = 0, 200 do table.insert(points, v(x)) end
		h.Flags.RawPoints = points
		h.Flags.OnCentre = function(state)
			state.Clock += 1
			state.Nav.FootPosition = v(180)
		end
		h:Plan(v(200))
		local waypoint = h:CurrentWaypoint()
		assert(waypoint and waypoint.X >= 180,
			"bounded join inspected only stale leading points of a dense route")
		h:Step(1 / 60, 24)
		assert(h.Nav.FootPosition.X >= 180, "dense delayed route caused reverse movement")
	end)
	test("graph hub behind entity is skipped through a certified join", function()
		local h = harness()
		h.Nav.FootPosition = v(20)
		h.Flags.GraphPoints = {v(0), v(50), v(100)}
		h:Plan(v(100), true)
		local waypoint = h:CurrentWaypoint()
		assert(waypoint and waypoint.X >= 20, "graph route revisits room hub behind entity")
		local certified = false
		for _, edge in ipairs(h.EdgeProbes) do
			if near(edge.From, v(20)) and near(edge.To, waypoint) then certified = true end
		end
		assert(certified, "prefix skip did not use production walking-edge certification")
	end)
	test("prefix rebasing cannot shortcut a wall", function()
		local h = harness()
		h.Nav.FootPosition = v(20)
		h.Flags.GraphPoints = {v(0), v(0, 20), v(40, 20), v(40)}
		h.Flags.EdgeClear = function(from, to)
			if near(from, v(20)) then return near(to, v(0)) end
			return true
		end
		h:Plan(v(40), true)
		local waypoint = h:CurrentWaypoint()
		assert(not waypoint or near(waypoint, v(0)), "uncertified wall-cutting suffix was installed")
		if waypoint then
			h:Step(1 / 60, 24)
			assert(h.Nav.FootPosition.X <= 20, "Step took forbidden wall shortcut")
		end
	end)
	test("certified internal walk-back loop is removed without changing its goal", function()
		local h = harness()
		h.Flags.RawPoints = {v(0), v(10), v(20), v(30), v(20), v(40), v(60), v(100)}
		-- The entry corner prevents commit-time prefix joining directly to the
		-- goal. The unnecessary reversal is deeper in the route, beyond it.
		h.Flags.EdgeClear = function(from, to)
			return not near(from, v(0)) or to.X <= 10.001
		end
		h:Plan(v(100))
		local previous = h.Nav.FootPosition
		for _, point in ipairs(h.Nav.Waypoints) do
			assert(point.X >= previous.X - .001, "certified route kept unnecessary internal walk-back")
			previous = point
		end
		assert(near(previous, v(100)), "route smoothing changed or truncated the requested goal")
		for _ = 1, 300 do
			local before = h.Nav.FootPosition
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
			assert(h.Nav.FootPosition.X >= before.X - .001,
				"real Step still reverses inside one unchanged certified route")
		end
		assert(h.Nav.FootPosition.X >= 98, "smoothed loop route lost arrival progress")
	end)
	test("internal route smoothing preserves a necessary wall detour", function()
		local h = harness()
		h.Flags.RawPoints = {v(0), v(10), v(10, 20), v(40, 20), v(40), v(60)}
		local function hitsWall(from, to)
			local enter, leave = 0, 1
			for _, axis in ipairs({{from.X, to.X, 20, 30}, {from.Z, to.Z, -5, 15}}) do
				local start, finish, low, high = table.unpack(axis)
				local delta = finish - start
				if math.abs(delta) < .000001 then
					if start < low or start > high then return false end
				else
					local a, b = (low - start) / delta, (high - start) / delta
					enter = math.max(enter, math.min(a, b))
					leave = math.min(leave, math.max(a, b))
					if enter > leave then return false end
				end
			end
			return true
		end
		h.Flags.EdgeClear = function(from, to) return not hitsWall(from, to) end
		h:Plan(v(60))
		local previous, retainedDetour = h.Nav.FootPosition, false
		for _, point in ipairs(h.Nav.Waypoints) do
			assert(not hitsWall(previous, point), "smoothing replaced required detour with wall shortcut")
			retainedDetour = retainedDetour or point.Z > 15
			previous = point
		end
		assert(retainedDetour and near(previous, v(60)), "necessary obstacle-avoidance shape disappeared")
		for _ = 1, 300 do
			local before = h.Nav.FootPosition
			h.Nav:SetGoal(v(60))
			h:Step(1 / 60, 24)
			h:Flush()
			assert(not hitsWall(before, h.Nav.FootPosition), "actual smoothed Step crossed solid wall")
		end
		assert((h.Nav.FootPosition - v(60)).Magnitude <= 2.01, "preserved detour did not reach goal")
	end)
	for _, scenario in ipairs({
		{Name = "unresolved", Stats = {Unresolved = 1}},
		{Name = "unwalkable", Stats = {Unwalkable = 1}},
		{Name = "exhausted 72000-query budget", Stats = {Queries = 72000}},
		{Name = "over-budget", Stats = {Queries = 72001}},
		{Name = "aborted", Stats = {Aborted = true}},
	}) do
		test(scenario.Name .. " replacement retains incumbent route", function()
			local h = harness()
			local incumbent = h:SeedRoute({v(30), v(60), v(100)}, v(100), v(10))
			h.Flags.Stats = scenario.Stats
			h.Clock += 1
			h.Nav:SetGoal(v(120))
			h:Flush()
			assert(h.Nav.Waypoints == incumbent, "unsafe replacement overwrote incumbent")
			assert(not h.Nav.Computing, "rejected candidate left request stuck computing")
		end)
	end
	test("failed path and graph preserve incumbent", function()
		local h = harness()
		local incumbent = h:SeedRoute({v(30), v(60), v(100)}, v(100), v(10))
		h.Flags.NoPath = true
		h.Flags.NoGraph = true
		h.Clock += 1
		h.Nav:SetGoal(v(120))
		h:Flush()
		assert(h.Nav.Waypoints == incumbent, "failed request erased known route")
		assert(not h.Nav.Computing)
	end)
	test("missing certification stats fail closed", function()
		local h = harness()
		local incumbent = h:SeedRoute({v(30), v(60), v(100)}, v(100), v(10))
		h.Flags.MissingStats = true
		h.Clock += 1
		h.Nav:SetGoal(v(120))
		h:Flush()
		assert(h.Nav.Waypoints == incumbent and not h.Nav.Computing,
			"missing stats installed or wedged a candidate")
	end)
	test("replacement with no certified live-foot join is rejected", function()
		local h = harness()
		local incumbent = h:SeedRoute({v(40), v(80), v(100)}, v(100), v(20))
		h.Flags.RawPoints = {v(20), v(70, 20), v(120)}
		h.Flags.EdgeClear = function(from, to)
			return not near(from, v(20)) or near(to, v(40))
		end
		h.Clock += 1
		h.Nav:SetGoal(v(120))
		h:Flush()
		assert(h.Nav.Waypoints == incumbent, "uncertified join replaced safe incumbent")
	end)
	test("target changed during compute cannot install incompatible result", function()
		local h = harness()
		local incumbent = h:SeedRoute({v(30), v(60), v(100)}, v(100), v(10))
		h.Flags.OnCentre = function(state)
			state.Nav:SetGoal(v(-100))
		end
		h.Clock += 1
		h.Nav:SetGoal(v(120))
		h:Flush()
		local waypoint = h:CurrentWaypoint()
		assert(h.Nav.Waypoints == incumbent or not waypoint
			or waypoint.X < h.Nav.FootPosition.X,
			"old positive route installed for new opposite target")
		-- Discarding an incompatible incumbent is a legitimate safe outcome.
		-- The next ordinary request must then recover toward the new target.
		h.Flags.OnCentre = nil
		h.Clock += .66
		h.Nav:SetGoal(v(-100))
		h:Flush()
		waypoint = h:CurrentWaypoint()
		assert(waypoint and waypoint.X < h.Nav.FootPosition.X,
			"discarded stale route never recovered toward the new target")
		local before = h.Nav.FootPosition
		h:Step(1 / 60, 24)
		assert(h.Nav.FootPosition.X < before.X, "recovered route did not follow new opposite target")
	end)
	test("arrived body approach does not restart route endlessly", function()
		local h = harness()
		h.Flags.Standable = function(point) return not near(point, v(100)) end
		h.Flags.CentredPoints = {v(90), v(100)}
		h.Flags.Stats = {GoalFallback = v(90)}
		h:Plan(v(100))
		assert(near(h.Nav.GoalApproach, v(90)), "did not preserve body-clear goal approach")
		h.Nav.FootPosition = v(90)
		h:Step(1 / 60, 24)
		local requestId = h.Nav.RequestId
		for _ = 1, 10 do
			h.Clock += 1
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
		end
		assert(h.Nav.RequestId == requestId, "arrived stand-in caused repeating path requests")
	end)
	test("failed same-goal replacement preserves installed goal and body approach", function()
		local h = harness()
		h.Flags.Standable = function(point) return not near(point, v(100)) end
		h.Flags.CentredPoints = {v(90), v(100)}
		h.Flags.Stats = {GoalFallback = v(90)}
		h:Plan(v(100))
		assert(near(h.Nav.InstalledGoal, v(100)) and near(h.Nav.GoalApproach, v(90)))
		local incumbent = h.Nav.Waypoints
		h.Flags.CentredPoints = {v(70), v(100)}
		h.Flags.Stats = {GoalFallback = v(70), Queries = 72000}
		h.Clock += 1
		h.Nav:SetGoal(v(100), true)
		h:Flush()
		assert(h.Nav.Waypoints == incumbent, "failed forced replacement erased incumbent")
		assert(near(h.Nav.InstalledGoal, v(100)), "failed candidate changed installed-goal ownership")
		assert(near(h.Nav.GoalApproach, v(90)), "failed candidate leaked its uninstalled approach")
		h.Nav.FootPosition = v(90)
		h:Step(1 / 60, 24)
		h.Clock += 1
		h.Nav:SetGoal(v(100))
		assert(#h.Queue == 0, "preserved arrival incorrectly launched another request")
	end)
	test("Path.Blocked validates actual current segment without losing returned foot", function()
		local h = harness()
		h:Plan(v(100))
		local incumbent = h.Nav.Waypoints
		assert(h.Nav:HasBlockedConnection(), "successful engine path lacks Blocked binding")
		h.Flags.EdgeClear = function(from, to)
			assert(typeof(from) == "Vector3" and typeof(to) == "Vector3",
				"Blocked callback discarded second return from _standableAt")
			return true
		end
		h.Paths[#h.Paths].Blocked:Fire(1)
		assert(h.Nav.Waypoints == incumbent and h.Nav:HasBlockedConnection(),
			"raw path signal erased an actually clear installed segment")
	end)
	test("Path.Blocked clears a truly blocked installed segment for replanning", function()
		local h = harness()
		h:Plan(v(100))
		h.Flags.EdgeClear = function() return false end
		h.Paths[#h.Paths].Blocked:Fire(1)
		assert(#h.Nav.Waypoints == 0 and h.Nav.Status == "BLOCKED",
			"real obstruction did not invalidate the installed segment")
		h.Nav:SetGoal(v(100))
		assert(#h.Queue == 1, "blocked stationary target could not request a replacement")
	end)
	test("unresolved engine candidate is replaced by a fully certified graph route", function()
		local h = harness()
		h.Flags.RawPoints = {v(0), v(10), v(100)}
		h.Flags.GraphPoints = {v(0), v(40), v(100)}
		local passes = 0
		h.Flags.OnCentre = function(state)
			passes += 1
			state.Flags.Stats = passes == 1 and {Unresolved = 1, Unwalkable = 0}
				or {Unresolved = 0, Unwalkable = 0}
		end
		h:Plan(v(100))
		assert(passes >= 2, "Unresolved-only engine failure never tried certified graph fallback")
		assert(h.Nav.LastCentring and h.Nav.LastCentring.Unresolved == 0,
			"unresolved engine candidate won over certified graph route")
		assert(h:CurrentWaypoint() and h.Nav.Status == "GRAPH", "safe graph route was not installed")
	end)
	test("inaccessible full route walks only its certified partial approach", function()
		local h = harness()
		h:BlockAt(40)
		h:Plan(v(100))
		assert(h:CurrentWaypoint(), "safe reachable prefix was discarded with blocked full route")
		for _, point in ipairs(h.Nav.Waypoints) do
			assert(point.X <= 40.001, "partial route includes a point beyond real obstruction")
		end
		for _ = 1, 180 do
			local before = h.Nav.FootPosition
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
			assert(h.Nav.FootPosition.X >= before.X - .001, "partial approach reversed/shuffled")
			assert(h.Nav.FootPosition.X <= 40.001, "partial approach crossed obstruction")
		end
		assert(h.Nav.FootPosition.X >= 38, "entity did not reach certified obstruction approach")
		local snapshot = h.Nav:GetDebugSnapshot()
		assert(snapshot.WaitingForClearance == true, "blocked approach not reported as waiting")
		assert(snapshot.Reached == false, "blocked approach falsely claims actual goal reached")
		assert(near(h.Nav.InstalledGoal, v(100)), "partial route lost requested-goal ownership")
	end)
	test("stationary blocked target waits without shuffling or repeated requests", function()
		local h = harness()
		h:BlockAt(40)
		h:Plan(v(100))
		for _ = 1, 180 do h:Step(1 / 60, 24) end
		local stoppedAt = h.Nav.FootPosition
		local requestId = h.Nav.RequestId
		for _ = 1, 300 do
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
			assert(near(h.Nav.FootPosition, stoppedAt), "blocked waiting entity shuffled")
		end
		assert(h.Nav.RequestId == requestId, "same unreachable target caused repeated route requests")
		assert(h.Nav:GetDebugSnapshot().Reached == false)
	end)
	test("unchanged obstruction is probed on its failed edge at bounded low frequency", function()
		local h = harness()
		h:BlockAt(40)
		h:Plan(v(100))
		for _ = 1, 180 do h:Step(1 / 60, 24) end
		assert(h.Nav:GetDebugSnapshot().WaitingForClearance == true)
		local stoppedAt = h.Nav.FootPosition
		local firstProbe = #h.EdgeProbes + 1
		local requestId = h.Nav.RequestId
		for _ = 1, 420 do
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
		end
		local probes = #h.EdgeProbes - firstProbe + 1
		assert(probes >= 2 and probes <= 3,
			"seven-second wait must make two or three bounded probes, not one per Heartbeat")
		local previousAt
		for index = firstProbe, #h.EdgeProbes do
			local edge = h.EdgeProbes[index]
			assert(near(edge.From, v(40)) and near(edge.To, v(60)),
				"clearance retry probed arbitrary direction instead of actual failed route edge")
			if previousAt then assert(edge.At - previousAt >= 2.9, "clearance probes ran too frequently") end
			previousAt = edge.At
		end
		assert(near(h.Nav.FootPosition, stoppedAt), "clearance probes moved a waiting entity")
		assert(h.Nav.RequestId == requestId and #h.Requests == 1,
			"unchanged obstruction triggered blind full path requests")
	end)
	test("removed obstruction resumes pursuit of the same unchanged target", function()
		local h = harness()
		h:BlockAt(40)
		h:Plan(v(100))
		for _ = 1, 180 do h:Step(1 / 60, 24) end
		assert(h.Nav:GetDebugSnapshot().WaitingForClearance == true)
		local requestId = h.Nav.RequestId
		h.Flags.EdgeClear = function() return true end
		h.Flags.WalkingEdge = function(_, to) return true, to, 3 end
		h.Flags.Stats = nil
		for _ = 1, 360 do
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
		end
		assert(h.Nav.RequestId > requestId, "cleared failed edge never requested a new route")
		assert(near(h.Nav.Goal, v(100)), "clearance recovery mutated the unchanged target")
		assert(h.Nav.FootPosition.X > 50, "cleared obstruction did not resume real forward Step")
		assert(h.Nav:GetDebugSnapshot().WaitingForClearance ~= true,
			"stale blocked wait survived a newly traversable edge")
		assert(h.Nav.BlockedGoalApproach == nil, "certified replacement retained blocked approach")
	end)
	test("Stop clears blocked-edge retry state and stops later clearance probes", function()
		local h = harness()
		h:BlockAt(40)
		h:Plan(v(100))
		for _ = 1, 180 do h:Step(1 / 60, 24) end
		assert(h.Nav:GetDebugSnapshot().WaitingForClearance == true)
		h.Nav:Stop()
		assert(h.Nav.BlockedGoalApproach == nil and h.Nav.InstalledGoal == nil,
			"Stop retained blocked goal ownership")
		assert(h.Nav.BlockedProbeFrom == nil and h.Nav.BlockedProbeTarget == nil,
			"Stop retained failed-edge retry geometry")
		assert(h.Nav.NextClearanceProbeAt == nil or h.Nav.NextClearanceProbeAt == 0,
			"Stop retained active clearance-probe deadline")
		local probes = #h.EdgeProbes
		for _ = 1, 600 do h:Step(1 / 60, 24) end
		assert(#h.EdgeProbes == probes, "stopped navigator continued probing clearance")
		assert(#h.Queue == 0 and h.Nav:GetDebugSnapshot().WaitingForClearance ~= true)
	end)
	test("materially moved target clears blocked waiting and resumes pursuit", function()
		local h = harness()
		h:BlockAt(40)
		h:Plan(v(100))
		for _ = 1, 180 do h:Step(1 / 60, 24) end
		assert(h.Nav:GetDebugSnapshot().WaitingForClearance == true)
		local before = h.Nav.FootPosition
		h.Flags.RawPoints = nil
		h.Flags.GraphPoints = nil
		h.Flags.Stats = nil
		h.Clock += 1
		h.Nav:SetGoal(v(20))
		h:Flush()
		assert(h:CurrentWaypoint(), "moved reachable target did not resume a route")
		assert(h.Nav.BlockedGoalApproach == nil, "obsolete blocked approach survived new certified goal")
		assert(h.Nav:GetDebugSnapshot().WaitingForClearance ~= true,
			"entity still claims blocked waiting after goal became accessible")
		h:Step(1 / 60, 24)
		assert(h.Nav.FootPosition.X < before.X, "entity did not move toward accessible target")
	end)
	test("no reachable prefix waits safely without inventing movement", function()
		local h = harness()
		h:BlockAt(0)
		h:Plan(v(100))
		local requestId = h.Nav.RequestId
		for _ = 1, 180 do
			h.Nav:SetGoal(v(100))
			h:Step(1 / 60, 24)
			h:Flush()
		end
		assert(near(h.Nav.FootPosition, v(0)), "fully obstructed entity invented an unsafe stride")
		assert(h.Nav.RequestId == requestId, "zero-prefix obstruction caused a replan storm")
		assert(h.Nav:GetDebugSnapshot().Reached == false, "obstruction was mistaken for arrival")
	end)
	test("goal directly above on another floor is not reached", function()
		local h = harness()
		local goal = Vector3.new(0, 20, 0)
		h:SeedRoute({}, goal, v(0))
		h.Nav.InstalledGoal = goal
		assert(h.Nav:GetDebugSnapshot().Reached == false, "same XZ on different floor counts as arrival")
		h:Step(1 / 60, 24)
		assert(h.Nav:GetDebugSnapshot().Reached == false, "Step erased vertical arrival constraint")
	end)
	test("old-floor body approach cannot satisfy a new goal on another floor", function()
		local h = harness()
		h:SeedRoute({}, Vector3.new(100, 20, 0), v(90))
		h.Nav.InstalledGoal = v(100)
		h.Nav.GoalApproach = v(90)
		assert(h.Nav:GetDebugSnapshot().Reached == false,
			"horizontal-only ownership reused old-floor approach for elevated target")
	end)
	test("partial scan budget cannot masquerade as a proven physical obstruction", function()
		local h = harness()
		local points = {}
		for x = 0, 200 do table.insert(points, v(x)) end
		h.Flags.RawPoints = points
		h.Flags.GraphPoints = points
		h.Flags.Stats = {Unwalkable = 1}
		-- Full centring reported an unresolved obstacle farther down this route,
		-- but the short prefix scan sees only clear edges before its work cap.
		-- It must not label that arbitrary cap as the entity's blocked endpoint.
		h:Plan(v(200))
		assert(h.Nav.BlockedGoalApproach == nil,
			"sixteen-point work cap invented a permanent obstacle wait point")
	end)
	test("real target reversal may turn entity around", function()
		local h = harness()
		h:Plan(v(100))
		h.Nav.FootPosition = v(20)
		h.Clock += 1
		h.Nav:SetGoal(v(-100))
		h:Flush()
		local waypoint = h:CurrentWaypoint()
		assert(waypoint and waypoint.X < 20, "anti-backtracking incorrectly forbids genuine U-turn")
		h:Step(1 / 60, 24)
		assert(h.Nav.FootPosition.X < 20, "real Step did not follow changed target behind it")
	end)
	test("stationary target graph route also remains stable", function()
		local h = harness()
		h.Flags.GraphPoints = {v(20), v(60), v(100)}
		h:Plan(v(100), true)
		local requestId = h.Nav.RequestId
		h.Clock += 3
		h.Nav:SetGraphGoal(v(100))
		assert(h.Nav.RequestId == requestId and #h.Queue == 0,
			"stable graph route was replaced just because timer expired")
	end)
	test("legacy navigator retains timer-driven refresh semantics", function()
		local h = harness(false)
		h:Plan(v(100))
		h.Clock += 1
		h.Nav:SetGoal(v(100))
		h:Flush()
		assert(#h.Requests == 2, "opt-in fix silently changed legacy users")
	end)
	test("request timeout invalidates old queued work and permits replacement", function()
		local h = harness()
		h.Nav:SetGoal(v(100))
		local originalId = h.Nav.RequestId
		assert(h.Nav.Computing)
		h.Clock += 8.01
		h.Nav:SetGoal(v(120))
		assert(h.Nav.RequestId > originalId, "timed-out request blocked future path work")
		h:Flush()
		assert(not h.Nav.Computing and near(h.Nav.Goal, v(120)), "replacement never completed")
		local final = h.Nav.Waypoints[#h.Nav.Waypoints]
		assert(final and near(final, v(120)), "stale timed-out route won installation race")
	end)
	test("explicit forced repath still bypasses target throttle", function()
		local h = harness()
		h:Plan(v(100))
		h.Clock += .1
		h.Nav:SetGoal(v(100), true)
		assert(#h.Queue == 1, "explicit recovery force was swallowed by stable-route throttle")
		h:Flush()
		assert(#h.Requests == 2)
	end)
	test("Stop invalidates delayed work before it can reinstall movement", function()
		local h = harness()
		h.Nav:SetGoal(v(100))
		h.Nav:Stop()
		h:Flush()
		assert(not h.Nav.Computing and #h.Nav.Waypoints == 0 and h.Nav.Goal == nil,
			"stopped navigator accepted a stale pending route")
	end)
	for _, fps in ipairs({30, 60}) do
		test("actual Step remains forward and speed-bounded at " .. fps .. " FPS", function()
			local h = harness()
			h:Plan(v(100))
			local dt = 1 / fps
			for _ = 1, fps * 2 do
				local before = h.Nav.FootPosition
				h.Nav:SetGoal(v(100))
				h:Step(dt, 24)
				h:Flush()
				local moved = h.Nav.FootPosition - before
				assert(moved.X >= -.001, "unnecessary reverse stride")
				assert(moved.Magnitude <= 24 * dt + .001, "frame exceeded speed budget")
			end
			assert(h.Nav.FootPosition.X >= 47.9, "lost forward progress in clear hall")
			assert(#h.Requests == 1, "clear traversal replaced stationary target route")
		end)
	end
	local passed = 0
	for _, result in ipairs(results) do if result.Passed then passed += 1 end end
	return {Passed = passed, Total = #results, Results = results,
		Scope = "production navigator with controlled geometry; no DataModel mutation"}
end
