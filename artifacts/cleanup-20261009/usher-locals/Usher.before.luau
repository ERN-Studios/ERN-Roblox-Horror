-- Level 4 Usher Controller: the tall faceless usher of "Den Sidste Forestilling".
-- It only exists in the dark. It walks the nav graph (Level 4 Usher Nav) over dark nodes only, vanishes the moment its
-- spot is lit, and hops to a freshly darkened zone when the neon blinks out near a player. Noise (NoiseRegistry) and
-- the main-breaker holder draw it; hidden players (crouched in an L4HideZone) are invisible to it. A flashlight in its
-- face freezes it (the beamer's battery drains faster, client side); held long enough it gives up and hops away.
-- Before the grab it whispers "shhh" (the windup), then a leased capture on the Jumpscare remote, shaped like
-- Level 1's EntityKill, and DeathAdvice "L4Usher".
-- The server body is an invisible proxy (HumanoidRootPart + Head); every client draws its own rig from UsherMotion
-- (20 Hz, unreliable) so the movement is smooth. Kinematic: nothing here is physics.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))
local NoiseRegistry = require(ServerScriptService:WaitForChild("NoiseRegistry"))
local PlayerProtection = require(ServerScriptService:WaitForChild("PlayerProtection"))
local DeathAdvice = require(ReplicatedStorage:WaitForChild("DeathAdvice"))

local C = Configuration.Usher
local Usher = {}

local ROOT_HEIGHT = 3.8           -- proxy root above the floor (the client rig keeps its own offset)
local BLINK_HOP_MIN_DISTANCE = 12 -- a blink hop may land this close: it is there when the lights come back
local STATES = { Dormant = 0, Stalk = 1, Chase = 2, Hop = 3, Shush = 4, Capture = 5, Stunned = 6, Search = 7, Wait = 8 }

local session = 0
local manifest, objectives, lights
local proxy, root, head
local connections = {}
local nodes, grid = {}, {}
local motionRemote, clientEvent, stateFolder, jumpscare

local active, finale = false, false
local current = nil               -- node index the Usher stands on / last passed
local position = Vector3.zero     -- feet position
local facing = Vector3.new(0, 0, -1)
local path, pathIndex = nil, 1
local state = "Dormant"
local target, targetReason = nil, nil
local lastKnown = nil
local nextHopAt, nextThinkAt, nextReplanAt = 0, 0, 0
local beamTime, stunUntil, stunCooldownUntil = 0, 0, 0
local beamers = {}
local shush = nil                 -- { Player, Character, EndsAt }
local capture = nil               -- leased capture record
local captureSerial = 0
local captureGeneration = HttpService:GenerateGUID(false)
local hidden = true               -- vanished (between hops / dormant)
local hopping = false             -- a hop is in flight (landing scheduled)
local lastMotion = 0
local searchUntil = 0

local function now() return workspace:GetServerTimeNow() end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

local function setState(name)
	if state == name then return end
	state = name
	if stateFolder then stateFolder:SetAttribute("Level4_UsherState", name) end
	if proxy then proxy:SetAttribute("State", name) end
end

-- ---------------------------------------------------------------- nav graph

local CELL = 16
local function cellKey(x, z) return math.floor(x / CELL) .. ":" .. math.floor(z / CELL) end

-- fallback graph from L4UsherNode markers (Zone attribute): edges to neighbours within 12 studs with a clear,
-- level line between them. ponytail: O(n^2) build, fine for a few hundred markers; the exported module is the real graph.
local function navFromMarkers()
	local nav = { Nodes = {}, Edges = {} }
	local CollectionService = game:GetService("CollectionService")
	for _, m in ipairs(CollectionService:GetTagged("L4UsherNode")) do
		if m:IsA("BasePart") and m:IsDescendantOf(manifest.World) then
			local p = m.Position
			table.insert(nav.Nodes, { p.X, p.Y - m.Size.Y * 0.5, p.Z, m:GetAttribute("Zone") })
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { manifest.World:FindFirstChild("Collision") or manifest.World }
	params.RespectCanCollide = true
	for i, a in ipairs(nav.Nodes) do
		for j = i + 1, #nav.Nodes do
			local b = nav.Nodes[j]
			local pa, pb = Vector3.new(a[1], a[2] + 2.5, a[3]), Vector3.new(b[1], b[2] + 2.5, b[3])
			if (pa - pb).Magnitude <= 12 and math.abs(a[2] - b[2]) <= 2.5 and not workspace:Raycast(pa, pb - pa, params) then
				table.insert(nav.Edges, { i, j })
			end
		end
	end
	return nav
end

local function loadNav()
	table.clear(nodes); table.clear(grid)
	local navModule = script.Parent:FindFirstChild("Level 4 Usher Nav")
	local nav = navModule and require(navModule) or navFromMarkers()
	assert(#nav.Nodes > 0, "Level 4 Usher has no nav graph (no Level 4 Usher Nav module and no L4UsherNode markers)")
	for i, n in ipairs(nav.Nodes) do
		nodes[i] = { Pos = Vector3.new(n[1], n[2], n[3]), Zone = n[4], Nbr = {} }
		local key = cellKey(n[1], n[3])
		local bucket = grid[key]
		if not bucket then bucket = {}; grid[key] = bucket end
		bucket[#bucket + 1] = i
	end
	for _, e in ipairs(nav.Edges) do
		local a, b = nodes[e[1]], nodes[e[2]]
		if a and b then
			local d = (a.Pos - b.Pos).Magnitude
			a.Nbr[#a.Nbr + 1] = { e[2], d }
			b.Nbr[#b.Nbr + 1] = { e[1], d }
		end
	end
	return #nodes
end

local function nodeDark(i)
	local power = lights.PowerState()
	if power == "Finale" or power == "Off" then return true end
	if power ~= "Failing" then return false end
	local zone = nodes[i].Zone
	return zone == nil or not lights.IsZoneOn(zone)
end
Usher._nodeDark = nodeDark

-- nearest node to a point (optionally dark only), searching the grid outward
local function nearestNode(pos, darkOnly, maxRadius)
	local cx, cz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
	local best, bestD
	local rings = math.ceil((maxRadius or 48) / CELL)
	for r = 0, rings do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					local bucket = grid[(cx + dx) .. ":" .. (cz + dz)]
					if bucket then
						for _, i in ipairs(bucket) do
							local n = nodes[i]
							local d = (n.Pos - pos).Magnitude + math.abs(n.Pos.Y - pos.Y) * 2
							if (not bestD or d < bestD) and (not darkOnly or nodeDark(i)) then best, bestD = i, d end
						end
					end
				end
			end
		end
		if best and r >= 1 then break end
	end
	return best, bestD
end

-- A* over dark nodes (binary heap)
local function findPath(from, to)
	if not from or not to then return nil end
	if from == to then return { from } end
	local goal = nodes[to].Pos
	local open, openN = {}, 0
	local g, came, closed = { [from] = 0 }, {}, {}
	local function push(i, f)
		openN += 1
		local k = openN
		open[k] = { i, f }
		while k > 1 do
			local p = k // 2
			if open[p][2] <= open[k][2] then break end
			open[p], open[k] = open[k], open[p]
			k = p
		end
	end
	local function pop()
		local top = open[1]
		open[1] = open[openN]
		open[openN] = nil
		openN -= 1
		local k = 1
		while true do
			local l, r, m = k * 2, k * 2 + 1, k
			if l <= openN and open[l][2] < open[m][2] then m = l end
			if r <= openN and open[r][2] < open[m][2] then m = r end
			if m == k then break end
			open[m], open[k] = open[k], open[m]
			k = m
		end
		return top[1]
	end
	push(from, (nodes[from].Pos - goal).Magnitude)
	local expanded = 0
	while openN > 0 do
		local i = pop()
		if i == to then
			local out = { i }
			while came[i] do i = came[i]; table.insert(out, 1, i) end
			return out
		end
		if not closed[i] then
			closed[i] = true
			expanded += 1
			if expanded > 6000 then return nil end
			for _, edge in ipairs(nodes[i].Nbr) do
				local j = edge[1]
				if not closed[j] and (j == to or nodeDark(j)) then
					local cost = g[i] + edge[2]
					if not g[j] or cost < g[j] then
						g[j] = cost
						came[j] = i
						push(j, cost + (nodes[j].Pos - goal).Magnitude)
					end
				end
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- players

local function bodyOf(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local r = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and r then return character, humanoid, r end
	return nil
end

local function validRound()
	return active and workspace:GetAttribute("SelectedLevel") == Configuration.Level
		and workspace:GetAttribute("RoundActive") == true and workspace:GetAttribute("EntityPaused") ~= true
end

local function huntable(player)
	if not (player and player.Parent == Players and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true) then return false end
	local character = bodyOf(player)
	if not character or PlayerProtection.IsActive(player, character) then return false end
	return not objectives.IsHidden(player)
end

local rayParams, rayParamsAt = RaycastParams.new(), -1
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local function rayClear(from, to)
	local t = os.clock()
	if t - rayParamsAt > 0.1 then
		rayParamsAt = t
		local ignore = { proxy }
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then ignore[#ignore + 1] = p.Character end end
		rayParams.FilterDescendantsInstances = ignore
	end
	return workspace:Raycast(from, to - from, rayParams) == nil
end

local function eyes() return position + Vector3.new(0, C.Height - 0.6, 0) end
local function chest() return position + Vector3.new(0, C.Height * 0.62, 0) end

-- ---------------------------------------------------------------- proxy + motion

local function buildProxy()
	proxy = Instance.new("Model")
	proxy.Name = "L4Usher"
	root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.1, 1.3, 1.1)
	for _, part in ipairs({ root, head }) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Parent = proxy
	end
	proxy.PrimaryPart = root
	proxy.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	proxy:SetAttribute("UsherHeight", C.Height)
	proxy:SetAttribute("State", state)
	proxy:SetAttribute("ZyntraDetectorLevel", Configuration.Level)
	proxy:SetAttribute("ZyntraDetectorActive", false)
	game:GetService("CollectionService"):AddTag(proxy, "ZyntraDetectableEntity")
	proxy.Parent = manifest.Runtime
end

local function feetCFrame()
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(position, position + flat.Unit)
end

local function syncProxy(force)
	if not root then return end
	local cf = feetCFrame()
	root.CFrame = cf + Vector3.new(0, hidden and -600 or ROOT_HEIGHT, 0)
	local detectable = active and not hidden
	if proxy:GetAttribute("ZyntraDetectorActive") ~= detectable then proxy:SetAttribute("ZyntraDetectorActive", detectable) end
	head.CFrame = cf + Vector3.new(0, hidden and -600 or C.Height - 0.7, 0)
	local t = os.clock()
	if motionRemote and (force or t - lastMotion >= 1 / C.MotionHz) then
		lastMotion = t
		motionRemote:FireAllClients(cf, STATES[state] or 0, hidden, now())
	end
end

local function placeAt(i)
	current = i
	position = nodes[i].Pos
	path, pathIndex = nil, 1
end

-- ---------------------------------------------------------------- hop

local function playerPositions()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local _, _, r = bodyOf(p)
		if r and p:GetAttribute("InRound") == true and p:GetAttribute("Escaped") ~= true then list[#list + 1] = r.Position end
	end
	return list
end

local function minDistance(pos, positions)
	local best = math.huge
	for _, q in ipairs(positions) do best = math.min(best, (q - pos).Magnitude) end
	return best
end

local function playersMinDistance(pos)
	return minDistance(pos, playerPositions())
end


local function hopTo(i, reason, minD)
	if not i then return false end
	hidden = true
	hopping = true
	setState("Hop")
	syncProxy(true)
	if clientEvent then clientEvent:FireAllClients({ Type = "UsherHop", Reason = reason }) end
	local mySession = session
	task.delay(0.55 + math.random() * 0.6, function()
		if session ~= mySession then return end
		hopping = false
		if not active then return end
		if not nodeDark(i) or playersMinDistance(nodes[i].Pos) < (minD or 0) then
			-- the landing got lit, or someone walked onto it while it was gone: try again shortly
			nextHopAt = 0
			return
		end
		placeAt(i)
		hidden = false
		setState(target and "Stalk" or "Search")
		syncProxy(true)
	end)
	nextHopAt = now() + Random.new():NextNumber(C.HopCooldownSeconds[1], C.HopCooldownSeconds[2])
	return true
end

-- a dark node near `around` (within maxD) but at least minD from every player.
-- ponytail: linear scan of the nav nodes per search (a few thousand); searches are cooldown-bounded.
local function pickHopNode(around, minD, maxD, rng)
	rng = rng or Random.new()
	local positions = playerPositions()
	local candidates = {}
	for i, n in ipairs(nodes) do
		if (not around or (n.Pos - around).Magnitude <= maxD) and nodeDark(i) and minDistance(n.Pos, positions) >= minD then
			candidates[#candidates + 1] = i
		end
	end
	if #candidates == 0 then return nil end
	return candidates[rng:NextInteger(1, #candidates)]
end

-- ---------------------------------------------------------------- capture (leased, cancellable)

local function captureValid(record)
	if capture ~= record or record.Session ~= session or not validRound() then return false end
	local player, character = record.Player, record.Character
	if player.Parent ~= Players or player.Character ~= character or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= record.Humanoid or humanoid.Health <= 0 then return false end
	return not PlayerProtection.IsActive(player, character)
end

local function finishCapture(record, cancelled)
	if capture ~= record then return end
	capture = nil
	for _, c in ipairs(record.Connections) do c:Disconnect() end
	local saved = record.Saved
	if saved and record.Root.Parent and record.Humanoid.Parent and record.Humanoid.Health > 0 then
		record.Root.Anchored = saved.Anchored
		record.Humanoid.WalkSpeed = saved.WalkSpeed
		record.Humanoid.JumpPower = saved.JumpPower
		record.Humanoid.AutoRotate = saved.AutoRotate
	end
	if cancelled and not record.Fatal and record.Player.Parent == Players and jumpscare then
		jumpscare:FireClient(record.Player, "cancel", nil, nil, nil, record.Id, record.Character)
	end
	if active then
		-- it melts back into the dark after a kill or a cancelled grab
		local away = pickHopNode(position, 30, 140)
		if away then hopTo(away, "capture", 30) end
	end
end

local function startCapture(player)
	local character, humanoid, r = bodyOf(player)
	if not character or capture then return end
	captureSerial += 1
	local record = {
		Player = player, Character = character, Humanoid = humanoid, Root = r, Session = session,
		Id = captureGeneration .. ":" .. captureSerial, Connections = {},
		Saved = { Anchored = r.Anchored, WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, AutoRotate = humanoid.AutoRotate },
	}
	capture = record
	setState("Capture")
	path = nil
	facing = (r.Position - position) * Vector3.new(1, 0, 1)
	-- the victim is pulled in front of it, facing it
	local front = position + (facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, -1)) * 3.2
	local victimPos = Vector3.new(front.X, r.Position.Y, front.Z)
	r.Anchored = true
	r.AssemblyLinearVelocity = Vector3.zero
	r.CFrame = CFrame.lookAt(victimPos, Vector3.new(position.X, victimPos.Y, position.Z))
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.AutoRotate = 0, 0, false
	syncProxy(true)
	if jumpscare then jumpscare:FireClient(player, "capture", proxy, C.CaptureSeconds, C.DeathAt, record.Id, character) end
	if clientEvent then clientEvent:FireAllClients({ Type = "UsherCapture", Player = player.UserId, At = now() }) end
	local function check() if not record.Fatal and not captureValid(record) then finishCapture(record, true) end end
	for _, name in ipairs({ "InRound", "Escaped" }) do
		table.insert(record.Connections, player:GetAttributeChangedSignal(name):Connect(check))
	end
	table.insert(record.Connections, player.CharacterRemoving:Connect(function(c)
		if c == character then finishCapture(record, true) end
	end))
	table.insert(record.Connections, humanoid.Died:Connect(check))
	task.delay(C.DeathAt, function()
		if not captureValid(record) then finishCapture(record, true); return end
		record.Fatal = true
		if jumpscare then jumpscare:FireClient(player, "death", nil, nil, nil, record.Id, character) end
		DeathAdvice.Mark(player, "L4Usher")
		humanoid.Health = 0
		task.wait(math.max(0, C.CaptureSeconds - C.DeathAt))
		finishCapture(record, false)
	end)
end

-- ---------------------------------------------------------------- flashlight

-- The server's own estimate of every flashlight battery (mirrors FlashlightController: 1.111/s on, +3/s while it is
-- lighting the Usher, recharge 3/s off, full on a battery pack), so a client that keeps FlashlightOn raised past an
-- empty battery cannot hold the Usher back.
local BATTERY_DRAIN, BATTERY_RECHARGE, BATTERY_USHER = 1.111, 3, 3
local battery, refills, batteryBody = {}, {}, {}
local function batteryMax(player)
	return 100 * math.max(1, tonumber(player:GetAttribute("ZyntraBatteryMultiplier")) or 1)
end
local function tickBatteries(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local flag = character and character:FindFirstChild("FlashlightOn")
		local max = batteryMax(player)
		if batteryBody[player] ~= character then batteryBody[player] = character; battery[player] = nil end
		local level = battery[player] or max
		local refill = player:GetAttribute("Level4_BatteryRefill") or 0
		if refill ~= (refills[player] or 0) then
			if type(refill) == "number" and refill > (refills[player] or 0) then level = max end
			refills[player] = type(refill) == "number" and refill or 0
		end
		if player:GetAttribute("DevUnlimited") == true then
			level = max
		elseif flag and flag.Value == true then
			level -= (BATTERY_DRAIN + (beamers[player] and BATTERY_USHER or 0)) * dt
		else
			level += BATTERY_RECHARGE * dt
		end
		battery[player] = math.clamp(level, 0, max)
	end
end

local function beamedBy()
	local list = {}
	local point = chest()
	local cosCone = math.cos(math.rad(C.FlashlightConeDegrees))
	for _, player in ipairs(Players:GetPlayers()) do
		local character = bodyOf(player)
		local flag = character and character:FindFirstChild("FlashlightOn")
		local headPart = character and character:FindFirstChild("Head")
		if flag and flag.Value == true and headPart and (battery[player] or 1) > 0
			and player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then
			local mount = workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId)
			-- the mount must sit at this body's head with nothing between them (no origin pushed through a wall), and
			-- point roughly where the body faces (first person turns the body with the camera: a stale aim does not)
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if mount and rootPart and (mount.Position - headPart.Position).Magnitude <= 5 and rayClear(headPart.Position, mount.Position) then
				local look = mount.CFrame.LookVector
				local flatLook, flatBody = Vector3.new(look.X, 0, look.Z), Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
				local facing = flatLook.Magnitude < 0.2 or flatBody.Magnitude < 0.01 or flatLook.Unit:Dot(flatBody.Unit) >= 0.5
				local from = mount.Position
				-- the light counts if it reaches the head, chest or waist (seat rows hide legs); each point passes
				-- range, cone and line of sight on its own
				if facing then
					for _, target in ipairs({ point, position + Vector3.new(0, C.Height * 0.88, 0), position + Vector3.new(0, C.Height * 0.45, 0) }) do
						local toward = target - from
						local d = toward.Magnitude
						-- a focused (Advanced Equipment) beam throws to the light-range cap
						local range = character:GetAttribute("FlashlightFocused") == true and 58 or C.FlashlightRange
						if d <= range and d > 0.1 and look:Dot(toward / d) >= cosCone and rayClear(from, target) then
							list[#list + 1] = player
							break
						end
					end
				end
			end
		end
	end
	return list
end

local function setBeamers(list)
	local set = {}
	for _, p in ipairs(list) do set[p] = true end
	for p in pairs(beamers) do
		if not set[p] and p.Parent == Players then p:SetAttribute("Level4_BeamingUsher", nil) end
	end
	for p in pairs(set) do
		if not beamers[p] then p:SetAttribute("Level4_BeamingUsher", true) end
	end
	beamers = set
end

-- ---------------------------------------------------------------- targeting

local function chooseTarget()
	-- 1. the breaker holder is always wanted
	local holder = objectives.BreakerHolder and objectives.BreakerHolder()
	if holder and huntable(holder) then return holder, "holder" end
	-- 2. someone it can see (in its sight range, line of sight)
	local best, bestD
	for _, player in ipairs(Players:GetPlayers()) do
		if huntable(player) then
			local _, _, r = bodyOf(player)
			local d = (r.Position - position).Magnitude
			local range = finale and C.SightRange * 1.6 or C.SightRange
			if d <= range and (not bestD or d < bestD) and rayClear(eyes(), r.Position + Vector3.new(0, 1.5, 0)) then
				best, bestD = player, d
			end
		end
	end
	if best then return best, "sight" end
	-- 3. noise
	NoiseRegistry.Prune()
	local noise = NoiseRegistry.GetBest(position, C.HearingRange)
	if noise then
		local source = noise.SourcePlayer
		if source and huntable(source) then return source, "noise" end
		lastKnown = noise.pos
		return nil, "noise"
	end
	-- 4. finale: it knows where everyone is
	if finale then
		for _, player in ipairs(Players:GetPlayers()) do
			if huntable(player) then
				local _, _, r = bodyOf(player)
				local d = (r.Position - position).Magnitude
				if not bestD or d < bestD then best, bestD = player, d end
			end
		end
		if best then return best, "finale" end
	end
	return nil, nil
end

-- ---------------------------------------------------------------- think + move

local function speedFor()
	if finale then return C.FinaleSpeed end
	if state == "Chase" then return C.ChaseSpeed end
	return C.StalkSpeed
end

local function goTowards(goalPos)
	local goal = nearestNode(goalPos, true, 48)
	if not goal then return false end
	local from = (path and path[pathIndex]) or current or nearestNode(position, true, 32)
	local p = findPath(from, goal)
	if p then path, pathIndex = p, 1 end
	if proxy then   -- readback for play-session QA (cheap: once per replan)
		proxy:SetAttribute("DbgPath", p and #p or -1)
		proxy:SetAttribute("DbgFrom", from)
		proxy:SetAttribute("DbgGoal", goal)
	end
	return p ~= nil
end

local function think(elapsed)
	local t = now()
	tickBatteries(elapsed or C.ThinkSeconds)
	if not validRound() or hidden then setBeamers({}) end
	if not validRound() then
		path = nil
		if shush then shush = nil end
		return
	end
	if hidden then
		-- (re)appear: only somewhere dark and away from players
		if t >= nextHopAt and not hopping then
			local r = target and select(3, bodyOf(target))
			local spot = pickHopNode(r and r.Position, C.HopMinPlayerDistance, C.HopMaxTargetDistance)
				or pickHopNode(nil, C.HopMinPlayerDistance, math.huge)
			if spot then hopTo(spot, "appear", C.HopMinPlayerDistance) else nextHopAt = t + 1 end
		end
		return
	end
	-- lit: vanish at once
	if current and not nodeDark(current) then
		local r = target and select(3, bodyOf(target))
		local spot = pickHopNode(r and r.Position or position, BLINK_HOP_MIN_DISTANCE, 90)
			or pickHopNode(nil, C.HopMinPlayerDistance, math.huge)
		hidden = true
		setBeamers({})
		if spot then hopTo(spot, "lit", BLINK_HOP_MIN_DISTANCE) else setState("Hop"); syncProxy(true); nextHopAt = t + 1 end
		shush = nil
		return
	end
	-- flashlight
	local beam = (t >= stunCooldownUntil) and beamedBy() or {}
	setBeamers(beam)
	if #beam > 0 then
		beamTime += C.ThinkSeconds
		shush = nil
		path = nil
		setState("Stunned")
		if beamTime >= C.StunSeconds then
			beamTime = 0
			stunCooldownUntil = t + C.StunCooldownSeconds
			setBeamers({})
			local away = pickHopNode(nil, 50, math.huge)
			if away then hopTo(away, "stunned", 50) end
			if clientEvent then clientEvent:FireAllClients({ Type = "Stun", By = beam[1].UserId }) end
		end
		return
	end
	beamTime = math.max(0, beamTime - C.ThinkSeconds * 0.5)
	-- the windup
	if shush then
		local _, _, r = bodyOf(shush.Player)
		if not r or not huntable(shush.Player) or (r.Position - position).Magnitude > C.AttackRange + 3
			or not rayClear(eyes(), r.Position) then
			shush = nil
			setState("Stalk")
		elseif t >= shush.EndsAt then
			local player = shush.Player
			shush = nil
			startCapture(player)
			return
		else
			facing = (r.Position - position) * Vector3.new(1, 0, 1)
			return
		end
	end
	if capture then return end
	-- targets
	local newTarget, reason = chooseTarget()
	if newTarget ~= target then
		target = newTarget
		nextReplanAt = 0
	end
	targetReason = reason
	if stateFolder then stateFolder:SetAttribute("Level4_UsherTarget", target and target.UserId or 0) end
	if target then
		local _, _, r = bodyOf(target)
		lastKnown = r.Position
		searchUntil = t + 6
		local d = (r.Position - position).Magnitude
		-- attack
		if d <= C.AttackRange and rayClear(eyes(), r.Position) then
			shush = { Player = target, EndsAt = t + C.ShushSeconds }
			path = nil
			setState("Shush")
			facing = (r.Position - position) * Vector3.new(1, 0, 1)
			if clientEvent then clientEvent:FireAllClients({ Type = "Shush", Player = target.UserId, Position = eyes() }) end
			if manifest.Audio.Shush and manifest.Audio.Shush ~= 0 then
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. manifest.Audio.Shush
				s.Volume = 1.4
				s.RollOffMinDistance = 6
				s.RollOffMaxDistance = 60
				s.Parent = head
				s:Play()
				task.delay(4, function() s:Destroy() end)
			end
			return
		end
		setState((reason == "sight" or reason == "holder" or finale) and "Chase" or "Stalk")
		-- too far, or no dark way there: hop closer when allowed
		if t >= nextReplanAt then
			nextReplanAt = t + 0.5
			local ok = d <= C.HopMaxTargetDistance * 1.6 and goTowards(r.Position)
			if proxy then proxy:SetAttribute("DbgHopIn", math.floor(nextHopAt - t)) end
			if not ok and t >= nextHopAt then
				local spot = pickHopNode(r.Position, C.HopMinPlayerDistance, C.HopMaxTargetDistance)
				if spot then hopTo(spot, "close in", C.HopMinPlayerDistance); return end
			end
			if not ok then
				-- wait at the edge of the dark, facing them
				path = nil
				setState("Wait")
				facing = (r.Position - position) * Vector3.new(1, 0, 1)
			end
		end
		return
	end
	-- no target: investigate the last noise, then wander
	if lastKnown and t < searchUntil + 4 then
		setState("Search")
		if t >= nextReplanAt then
			nextReplanAt = t + 1
			if (lastKnown - position).Magnitude < 6 then lastKnown = nil else goTowards(lastKnown) end
		end
		return
	end
	setState("Stalk")
	if (not path or pathIndex > #path) and t >= nextReplanAt then
		nextReplanAt = t + 2
		-- wander toward the living, through the dark
		local living = objectives.LivingParticipants()
		local focus = position
		if #living > 0 then
			local _, _, r = bodyOf(living[math.random(1, #living)])
			if r then focus = r.Position end
		end
		if t >= nextHopAt and math.random() < 0.35 then
			local spot = pickHopNode(focus, C.HopMinPlayerDistance, C.HopMaxTargetDistance)
			if spot then hopTo(spot, "wander", C.HopMinPlayerDistance); return end
		end
		local spot = pickHopNode(position:Lerp(focus, 0.5), 10, 60)
		if spot then goTowards(nodes[spot].Pos) end
	end
end

local function step(dt)
	if hidden or not active or capture or shush or state == "Stunned" or state == "Wait" or not validRound() then
		syncProxy(false)
		return
	end
	if path and pathIndex <= #path then
		local remaining = speedFor() * dt
		while remaining > 0 and path and pathIndex <= #path do
			local nextI = path[pathIndex]
			if not nodeDark(nextI) then path = nil; nextReplanAt = 0; break end
			local goal = nodes[nextI].Pos
			local delta = goal - position
			local d = delta.Magnitude
			if d <= remaining then
				position = goal
				current = nextI
				pathIndex += 1
				remaining -= d
			else
				position += delta / d * remaining
				if Vector3.new(delta.X, 0, delta.Z).Magnitude > 0.05 then facing = facing:Lerp(delta.Unit, math.min(1, dt * 8)) end
				remaining = 0
			end
		end
	end
	syncProxy(false)
end

-- ---------------------------------------------------------------- zone hook: a blink is an opportunity

local function onZoneChanged(zoneId, on)
	if on or not active or hidden or capture or shush or finale then return end
	if now() < nextHopAt or state == "Stunned" then return end
	-- a zone just went dark near its target (or any player): appear in it
	local r = target and select(3, bodyOf(target))
	if not r then return end
	local zoneCandidates = {}
	local positions = playerPositions()
	for i, n in ipairs(nodes) do
		if n.Zone == zoneId and nodeDark(i) then
			local pd = minDistance(n.Pos, positions)
			if pd >= BLINK_HOP_MIN_DISTANCE and (n.Pos - r.Position).Magnitude <= 40 then
				zoneCandidates[#zoneCandidates + 1] = i
			end
		end
	end
	if #zoneCandidates > 0 and math.random() < 0.6 then
		hopTo(zoneCandidates[math.random(1, #zoneCandidates)], "blink", BLINK_HOP_MIN_DISTANCE)
	end
end

-- ---------------------------------------------------------------- player noise intake
-- NoiseReporter fires Remotes.ReportNoise ("walk"/"sprint") at 5 Hz on levels 1, 2 and 4. EntityAI is disabled in
-- this round, so the Usher drains it. Module scope, once (like Pool Foam's intake): a session-scoped connection
-- would leave the remote undrained whenever Start bailed. The server decides position and plausibility.
do
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local report = remotes and remotes:FindFirstChild("ReportNoise")
	if report and report:IsA("RemoteEvent") then
		local lastReport = {}
		report.OnServerEvent:Connect(function(player, stateName)
			if not active or not objectives or (stateName ~= "walk" and stateName ~= "sprint") then return end
			if workspace:GetAttribute("SelectedLevel") ~= Configuration.Level then return end
			local t = os.clock()
			if (lastReport[player] or 0) > t then return end
			lastReport[player] = t + 0.15
			if player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true then return end
			local _, _, r = bodyOf(player)
			if not r or r.AssemblyLinearVelocity.Magnitude < 2 or objectives.IsHidden(player) then return end
			NoiseRegistry.Add(r.Position, stateName, player)
		end)
		Players.PlayerRemoving:Connect(function(player) lastReport[player] = nil end)
	end
end

-- ---------------------------------------------------------------- public API

function Usher.Start(m, generation, lightDirector, objectiveController)
	Usher.Stop()
	session += 1
	manifest = m
	lights = lightDirector
	objectives = objectiveController
	stateFolder = m.State
	clientEvent = m.ClientEvent
	motionRemote = m.UsherMotion
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	jumpscare = remotes and remotes:FindFirstChild("Jumpscare")
	local count = loadNav()
	table.clear(battery); table.clear(refills); table.clear(batteryBody)
	buildProxy()
	active, finale, hidden = false, false, true
	setState("Dormant")
	if stateFolder then
		stateFolder:SetAttribute("Level4_UsherActive", false)
		stateFolder:SetAttribute("Level4_UsherState", "Dormant")
	end
	lights.OnZoneChanged = onZoneChanged
	local accum = 0
	connect(RunService.Heartbeat, function(dt)
		if session == 0 then return end
		step(dt)
		accum += dt
		if accum >= C.ThinkSeconds then
			local elapsed = accum
			accum = 0
			local ok, err = pcall(think, elapsed)
			if not ok then warn("[Level4 Usher] think failed: " .. tostring(err)) end
		end
	end)
	connect(PlayerProtection.Activated, function(player, character)
		if capture and capture.Player == player and capture.Character == character then finishCapture(capture, true) end
		if shush and shush.Player == player then shush = nil end
		if target == player then target = nil end
	end)
	connect(Players.PlayerRemoving, function(player)
		if capture and capture.Player == player then finishCapture(capture, true) end
		beamers[player] = nil
		battery[player], refills[player], batteryBody[player] = nil, nil, nil
		if target == player then target = nil end
	end)
	return count
end

-- called when the lights start failing (after the "woooow")
function Usher.Activate()
	if active then return end
	local mySession = session
	task.delay(C.ActivateGraceSeconds, function()
		if session ~= mySession then return end
		active = true
		hidden = true
		nextHopAt = 0
		if stateFolder then stateFolder:SetAttribute("Level4_UsherActive", true) end
		setState("Hop")
	end)
end

function Usher.Finale()
	finale = true
	nextHopAt = 0
	if not active then
		active = true
		hidden = true
		if stateFolder then stateFolder:SetAttribute("Level4_UsherActive", true) end
		setState("Hop")
	end
end

function Usher.Position()
	return position, hidden, state
end

-- test hook: put it somewhere specific (play-session test suite only)
function Usher.DebugPlace(pos)
	local i = nearestNode(pos, false, 64)
	if i then placeAt(i); hidden = false; setState("Stalk"); syncProxy(true) end
	return i
end

function Usher.Stop()
	session += 1
	active, finale, hopping = false, false, false
	if capture then finishCapture(capture, true) end
	capture, shush, target, path, lastKnown = nil, nil, nil, nil, nil
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	setBeamers({})
	if lights and lights.OnZoneChanged == onZoneChanged then lights.OnZoneChanged = nil end
	if proxy then proxy:Destroy() end
	proxy, root, head = nil, nil, nil
	hidden = true
	state = "Dormant"
	if stateFolder then
		stateFolder:SetAttribute("Level4_UsherActive", false)
		stateFolder:SetAttribute("Level4_UsherState", "Dormant")
		stateFolder:SetAttribute("Level4_UsherTarget", 0)
	end
	beamTime, stunUntil, stunCooldownUntil, nextHopAt = 0, 0, 0, 0
end

return Usher
