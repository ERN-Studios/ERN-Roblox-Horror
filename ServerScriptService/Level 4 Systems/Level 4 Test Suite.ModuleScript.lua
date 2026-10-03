-- Level 4 Test Suite: server-side checks of the cinema round, runnable from a play-session Server probe:
--   require(game.ServerScriptService["Level 4 Systems"]["Level 4 Test Suite"]).Run()
-- Static (no round needed): every required anchor exists, the nav graph is connected and reaches every objective,
-- zones are complete. Live (during a round): the published state is consistent. Returns a report table and prints it.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))

local Suite = {}

local function check(report, ok, name, detail)
	report.Total += 1
	if ok then report.Passed += 1 else table.insert(report.Failures, name .. (detail and (": " .. detail) or "")) end
end

local function tagged(world, tag)
	local list = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsDescendantOf(world) then table.insert(list, inst) end
	end
	return list
end

local function position(inst)
	if inst:IsA("BasePart") then return inst.Position end
	return inst:GetPivot().Position
end

-- Nav coordinates are floor positions. The authored exit-access check uses a
-- standing root three studs above that floor; gameplay accepts this same OBB
-- with X +0.6, Y +3 and Z +3 margins (Objectives.insideBox(..., 3)).
local function exitVolumeReachable(exit, nodes, seen)
	if not exit:IsA("BasePart") then return false end
	local half = exit.Size * 0.5
	for i, node in ipairs(nodes) do
		if seen[i] then
			local root = Vector3.new(node[1], node[2] + 3, node[3])
			local p = exit.CFrame:PointToObjectSpace(root)
			if math.abs(p.X) <= half.X + 0.6 and math.abs(p.Y) <= half.Y + 3
				and math.abs(p.Z) <= half.Z + 3 then return true end
		end
	end
	return false
end

function Suite.Run()
	local report = { Total = 0, Passed = 0, Failures = {} }
	local world = workspace:FindFirstChild(Configuration.ModelName)
	check(report, world ~= nil, "cinema model present")
	if not world then return report end

	-- anchors
	for tag, minimum in pairs(Configuration.Required) do
		local n = #tagged(world, tag)
		check(report, n >= minimum, "anchor " .. tag, ("%d < %d"):format(n, minimum))
	end
	local breakers, keys = tagged(world, "L4Breaker"), {}
	for _, b in ipairs(breakers) do
		local key = tostring(b:GetAttribute("CabinetId")) .. tostring(b:GetAttribute("SwitchIndex"))
		check(report, not keys[key], "breaker key unique " .. key)
		keys[key] = true
		check(report, b:FindFirstChild("Handle", true) ~= nil, "breaker " .. key .. " has a Handle")
	end
	local main = tagged(world, "L4MainBreaker")[1]
	check(report, main == nil or main:FindFirstChild("Lever", true) ~= nil, "main breaker has a Lever")
	local screens = {}
	for _, s in ipairs(tagged(world, "L4Screen")) do screens[s:GetAttribute("Screen") or 0] = true end
	for _, p in ipairs(tagged(world, "L4Projector")) do
		check(report, screens[p:GetAttribute("Screen") or -1] == true, "projector has its screen " .. tostring(p:GetAttribute("Screen")))
	end
	local locked = 0
	for _, r in ipairs(tagged(world, "L4ReelSpot")) do if r:GetAttribute("Locked") then locked += 1 end end
	check(report, locked <= 1, "at most one locked reel spot", tostring(locked))
	check(report, #tagged(world, "L4HideZone") >= 10, "hide zones", tostring(#tagged(world, "L4HideZone")))

	-- zones
	local zoneIds, zoneMarkers = {}, 0
	for _, d in ipairs(world:GetDescendants()) do
		if d:IsA("Light") and d.Parent and d.Parent:GetAttribute("L4Zone") then zoneIds[d.Parent:GetAttribute("L4Zone")] = true end
		if d:IsA("BasePart") and d:HasTag("L4LightZone") then zoneMarkers += 1 end
	end
	local zoneCount = 0
	for _ in pairs(zoneIds) do zoneCount += 1 end
	check(report, zoneCount >= 8, "light zones", tostring(zoneCount))
	for id = 1, zoneCount do check(report, zoneIds[id] == true, "zone ids contiguous " .. id) end
	check(report, zoneMarkers >= zoneCount, "a marker per zone", ("%d markers / %d zones"):format(zoneMarkers, zoneCount))

	-- nav graph
	local navModule = script.Parent:FindFirstChild("Level 4 Usher Nav")
	check(report, navModule ~= nil, "nav module present")
	if navModule then
		local nav = require(navModule)
		local nodes, adj = nav.Nodes, {}
		check(report, #nodes >= 200, "nav nodes", tostring(#nodes))
		for i = 1, #nodes do adj[i] = {} end
		for _, e in ipairs(nav.Edges) do
			if adj[e[1]] and adj[e[2]] then table.insert(adj[e[1]], e[2]); table.insert(adj[e[2]], e[1]) end
		end
		local function nearest(pos)
			local best, bestD
			for i, n in ipairs(nodes) do
				local d = (Vector3.new(n[1], n[2], n[3]) - pos).Magnitude
				if not bestD or d < bestD then best, bestD = i, d end
			end
			return best, bestD
		end
		local spawn = tagged(world, "L4EntrySpawn")[1]
		if spawn and #nodes > 0 then
			local start = nearest(spawn.Position)
			local seen, queue, head = { [start] = true }, { start }, 1
			while head <= #queue do
				local i = queue[head]; head += 1
				for _, j in ipairs(adj[i]) do
					if not seen[j] then seen[j] = true; table.insert(queue, j) end
				end
			end
			check(report, #queue >= #nodes * 0.95, "nav connected from the spawn", ("%d / %d"):format(#queue, #nodes))
			for _, tag in ipairs({ "L4ReelSpot", "L4Projector", "L4MainBreaker", "L4ExitScreen", "L4PowerCabinet" }) do
				for _, inst in ipairs(tagged(world, tag)) do
					if tag == "L4ExitScreen" then
						check(report, exitVolumeReachable(inst, nodes, seen), tag .. " reachable",
							inst.Name .. " has no connected standing-root node inside its gameplay exit volume")
					else
						local i, d = nearest(position(inst))
						check(report, d <= 14 and seen[i] == true, tag .. " reachable", ("%s %.1f studs from a node"):format(inst.Name, d))
					end
				end
			end
		end
	end

	-- live state
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateName)
	if workspace:GetAttribute("Level4RoundActive") == true and state then
		local bits = state:GetAttribute("Level4_ZoneStates")
		check(report, type(bits) == "string" and #bits == (state:GetAttribute("Level4_ZoneCount") or -1), "zone bits match zone count")
		check(report, (state:GetAttribute("Level4_SequenceGoal") or 0) == Configuration.Sequence.Length, "sequence goal published")
		check(report, (state:GetAttribute("Level4_ReelGoal") or 0) == Configuration.Reels.Goal, "reel goal published")
		check(report, world:FindFirstChild(Configuration.RuntimeName) ~= nil, "runtime folder present")
		check(report, workspace:FindFirstChild("ElevatorSpawn") ~= nil and workspace:FindFirstChild("MazeStart") ~= nil, "compat parts present")
	end

	print(("[Level 4 Test Suite] %d/%d passed"):format(report.Passed, report.Total))
	for _, f in ipairs(report.Failures) do warn("[Level 4 Test Suite] FAIL " .. f) end
	return report
end

return Suite
