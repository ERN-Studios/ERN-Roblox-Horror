-- Level 6 Indoor Playground: hide and seek with the counting child.
--
-- Level6PreviewAccess calls AddPlayer/RemovePlayer as players enter and leave the map.
-- The child is "The Counter", a skinned porcelain doll: its mesh is baked on the server from
-- ServerStorage.Level6CounterSource, its clips and voice lines live in ReplicatedStorage.Level6Counter
-- (pipeline: tools/level6_entity). The server only publishes Anim / AnimSerial / Speed on the model and
-- says which line to speak; the Level 6 Playground Client moves the bones and plays the sound.
-- Each round: the child faces the post and counts to 20 out loud; when it finishes it searches
-- the hide spots and chases anyone it sees. While it is away, players score by touching the post
-- (once per player per round). After three searches in which everyone alive touched it, the post
-- counts down a minute and sinks into the floor: the way out is the shaft under it.
--
-- ARENA_20261006: the map is "the Arena" (tools/level6_playground/build_arena.py): one frame round the
-- post, twelve floors, players arriving through a tunnel and the PLAY ZONE gate. The Counter walks the
-- graph the build writes (model.NavGraph) instead of asking PathfindingService.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local MODEL_NAME = "Level 6 Indoor Playground"
local IN_PREVIEW = "Level6PlaygroundPreview"
local CLEARED = "Level6PlaygroundCleared"

local CONFIG = {
	-- With this false nobody counts, seeks or chases and the map is a free-roam preview.
	EntityEnabled = true,
	CountTo = 20,
	-- the recorded count for each round (22.9, 21.2, 19.2, 15.9 s); the last one repeats
	CountLines = {"l6_count_slow", "l6_count_medium", "l6_count_fast", "l6_count_frantic"},
	SeekSeconds = 75,
	TagsToWin = 3,
	DunkRadius = 7, DunkSafeDistance = 22,
	WalkSpeed = 9, ChaseSpeed = 40, EscapeChaseSpeed = 24,   -- seen = as good as dead (owner, 2026-10-03); furious once the exit opens
	SightRange = 75, CatchDistance = 5.2, HideRadius = 4.5, HiddenSpotRange = 9,
	NoiseSpeed = 18, NoiseRange = 45, LoseSightSeconds = 15, CheckPause = 3.3,   -- CheckPause = the Search_Look clip
	-- Owner, 2026-10-04: the level is won over THREE searches in each of which every living player touches the
	-- post. (For a while one such search was enough: that was a mistake made when the target became 'all alive'.)
	RoundsToWin = 3,
	ExitRadius = 11, CaughtReturnDelay = 5.0,   -- the length of the kill cam (the `Choke` clip)
	PartyDownSeconds = 15,     -- the window after the last player falls, as in every other level
	ReentryGraceSeconds = 8,   -- a re-entered player is not seen for this long
	GrabDistance = 2.3,   -- how far in front of its victim it stands for the kill cam (= Choke.Grab's distance)
	-- CHOKE_20261006: where the victim's NECK is during the kill, in front of the doll. The `Choke` clip is built
	-- round exactly these numbers (tools/level6_entity/build_choke.py prints them: change them there), so its hands
	-- are on the throat for everyone who watches. Each key is {studs the neck rises above where it is when the
	-- victim stands on the doll's floor, studs in front of the doll}; Times are the ends of the grab and the lift
	-- and the start and end of the pull.
	Choke = {Grab = {0.0, 2.30}, Lift = {1.85, 1.78}, Pull = {1.45, 1.62}, Times = {0.30, 1.50, 1.70, 4.30},
		NeckAboveFeet = 4.66},
	HipHeight = 2.4,   -- root above the soles; replaced by the mesh's own value when the doll is built
	EyeHeight = 2.6,   -- eyes above the root
	SpottedPause = 0.7,
	IntroSilence = 5,  -- seconds of quiet after the players arrive, before the PA chime
	-- ARENA_20261006
	ArenaSeekSeconds = 90,      -- twelve floors to come down from
	ArenaDunkSafeDistance = 30, -- it has to be out of the middle of the court
	ArenaWalkSpeed = 11,
	SightCos = 0.17,            -- it sees what it is facing: within about 80 degrees of where it looks
	CloseRange = 14,            -- nearer than this it notices you whichever way it faces
	NetCoverRange = 18,         -- standing still behind netting hides you, unless it is this close
	StillSpeed = 2,
	FinaleSeconds = 60,         -- from the third touch to the post going down (owner, 2026-10-06)
	FinaleChaseSpeed = 22,
	ArrivalWait = 25,           -- after the first player is through the gate, how long it waits for the rest
	ExitDrop = 9,               -- how far under the floor the exit is, at least
	ArenaExitRadius = 6,        -- the exit's mark is in the passage behind the green door: you are out when you step through
	-- HUNT_20261006 (owner): each search it walks calmly toward whoever is nearest, and it is quicker, in its
	-- step and in how soon it notices you have moved, every time it counts again
	ArenaHuntSpeeds = {7, 9.5, 12},     -- studs a second in the first, second and third search (you walk at 16)
	ArenaHuntSpeedStep = 1.5,           -- and this much more for every search after that,
	ArenaHuntSpeedMax = 15,             -- never past this
	ArenaHuntReplan = {1.6, 1.1, 0.7},  -- seconds before it looks again at where you are now
	ArenaHuntReplanMin = 0.5,
	WinChoiceSeconds = 15,              -- LEVEL 6 CLEARED stays up this long, as every level's ending does
}

local arenaSlides = {busy = false, job = false}
local Game = {}
Game.Config = CONFIG

local folder = ReplicatedStorage:FindFirstChild("Level6Playground")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Level6Playground"
	folder.Parent = ReplicatedStorage
end
local event = folder:FindFirstChild("Event")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "Event"
	event.Parent = folder
end

local returnHandler = nil      -- set by Level6PreviewAccess: sends a player back to the lobby
-- The round-status remote every level's death, spectate and re-entry UI listens to (GameManager owns it).
local roundStatus = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local DEATH_CAUSE = "Unknown"
do
	local ok, advice = pcall(function() return require(ReplicatedStorage:WaitForChild("DeathAdvice", 5)) end)
	if ok and type(advice) == "table" and type(advice.Unknown) == "string" then DEATH_CAUSE = advice.Unknown end
end
local session = nil
local lifeWatch = {}       -- player -> the connection that reports their death

-- PARTY_20261004 (owner): the round's clock. Every deadline in this module reads `clock()`, which stands still
-- while the easter-egg party is on, so the round carries on afterwards exactly where it was: the search timer,
-- the voice gaps, a pause the doll was in. `realClock` is the wall clock, for the party itself.
-- ACHIEVEMENTS_20261004: ZyntraMonetization owns the record; this only reports what happened.
local function achieve(player, key)
	local bindable = ServerStorage:FindFirstChild("ZyntraAchievement")
	if bindable and player and player.Parent == Players then bindable:Fire(player, key) end
end
local realClock = os.clock
local pausedAt, pausedTotal = nil, 0
local function clock()
	return (pausedAt or realClock()) - pausedTotal
end

function Game.SetReturnHandler(fn)
	returnHandler = fn
end

-- ---------------------------------------------------------------------------------------
-- map access
local function map()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not model or not model:IsA("Model") then return nil end
	local anchors = model:FindFirstChild("Anchors")
	if not anchors then return nil end
	local home, exit, spawn = anchors:FindFirstChild("L6_Anchor_HomeBase"), anchors:FindFirstChild("L6_Anchor_Exit"),
		anchors:FindFirstChild("L6_Anchor_EntitySpawn")
	if not home or not exit then return nil end
	local spots = {}
	for _, a in ipairs(anchors:GetChildren()) do
		if a:GetAttribute("HideKind") then spots[#spots + 1] = a.Position end
	end
	local origin = model:GetAttribute("Origin")
	local arena = model:GetAttribute("Arena") == true and typeof(origin) == "Vector3"
	local gate = anchors:FindFirstChild("L6_Anchor_Gate")
	local gateRadius = nil
	if arena and gate then
		local d = gate.Position - home.Position
		gateRadius = math.sqrt(d.X * d.X + d.Z * d.Z)
	end
	return {model = model, home = home.Position, exit = exit.Position, spawn = spawn and spawn.Position or home.Position,
		spots = spots, floorY = arena and origin.Y or model:GetPivot().Position.Y,
		arena = arena, gate = gate and gate.Position or nil, gateRadius = gateRadius}
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or humanoid.Health <= 0 then return nil end
	return root, humanoid, character
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- ---------------------------------------------------------------------------------------
-- ARENA_20261006: the Counter's own map of the frame. The build knows every cell, opening and stair and writes
-- them as a graph: one node per cell, one link per way through. The Counter walks along it and nowhere else,
-- so it never meets a net it cannot pass or a floor it has to guess at.
local navCache = setmetatable({}, {__mode = "k"})
local function navOf(model)
	local cached = navCache[model]
	if cached ~= nil then return cached or nil end
	local built = false
	local folder = model:FindFirstChild("NavGraph")
	local origin = model:GetAttribute("Origin")
	if folder and typeof(origin) == "Vector3" then
		local ok, data = pcall(function()
			local pieces = {}
			for i = 1, folder:GetAttribute("Parts") or 0 do
				pieces[i] = folder:FindFirstChild(string.format("Part_%02d", i)).Value
			end
			return HttpService:JSONDecode(table.concat(pieces))
		end)
		if ok and type(data) == "table" and type(data.nodes) == "table" then
			local nodes, links = {}, {}
			for i = 1, #data.nodes, 3 do
				nodes[#nodes + 1] = origin + Vector3.new(data.nodes[i], data.nodes[i + 1], data.nodes[i + 2]) / 10
				links[#nodes] = {}
			end
			for _, e in ipairs(data.edges) do
				local a, b = e[1] + 1, e[2] + 1
				local via, back = {}, {}
				for i = 3, #e, 3 do via[#via + 1] = origin + Vector3.new(e[i], e[i + 1], e[i + 2]) / 10 end
				for i = #via, 1, -1 do back[#back + 1] = via[i] end
				local cost, at = 0, nodes[a]
				for _, point in ipairs(via) do cost += (point - at).Magnitude; at = point end
				cost += (nodes[b] - at).Magnitude
				table.insert(links[a], {to = b, via = via, cost = cost})
				table.insert(links[b], {to = a, via = back, cost = cost})
			end
			local cells, open = {}, {}
			for key, id in pairs(data.cells or {}) do cells[key] = id + 1 end
			for _, id in ipairs(data.open or {}) do open[#open + 1] = id + 1 end
			built = {nodes = nodes, links = links, home = (data.home or 0) + 1, cells = cells, open = open, origin = origin,
				radii = data.radii, sectors = data.sectors, floorHeight = data.floorHeight or 10}
		else
			warn("[Level6] the navigation graph could not be read: " .. tostring(data))
		end
	end
	navCache[model] = built
	return built or nil
end

-- The node of the cell a point is in: floors are ten studs apart, a band is the ring between two radii, a
-- sector is a slice of it. In the court, in the lane and on the bridges it is the nearest node there.
local function navNodeAt(nav, pos)
	local rel = pos - nav.origin
	local r = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
	local openOnly = r < nav.radii[1] or (rel.Z > nav.radii[1] - 4 and math.abs(rel.X) <= 7.6)
	if not openOnly then
		local k = math.max(0, math.floor((rel.Y + 4.5) / nav.floorHeight))
		local band = #nav.radii - 1
		for b = 1, #nav.radii - 1 do
			if r < nav.radii[b + 1] then band = b; break end
		end
		local a = math.deg(math.atan2(-rel.Z, rel.X)) % 360
		local s = nav.sectors[band] == 24 and math.floor(((a + 7.5) % 360) / 15) or (math.floor(a / 7.5) + 1) % 48
		local id = nav.cells[string.format("%d,%d,%d", k, band - 1, s)]
		if id then return id end
	end
	local best, bestD = nil, math.huge
	local list = openOnly and nav.open or nil
	for pass = 1, 2 do
		for i = 1, list and #list or #nav.nodes do
			local id = list and list[i] or i
			local d = nav.nodes[id] - pos
			if pass == 2 or math.abs(d.Y) <= 4.5 then
				local m = d.X * d.X + d.Z * d.Z + (pass == 2 and 4 * d.Y * d.Y or 0)
				if m < bestD then best, bestD = id, m end
			end
		end
		if best then return best end
	end
	return best
end

-- The shortest way over the graph from any of `sources` ({node, cost already spent}) to `goal`: a list of nodes.
local function navRoute(nav, sources, goal)
	local g, from, closed = {}, {}, {}
	local heap, size = {}, 0
	local goalPos = nav.nodes[goal]
	local function push(node, f)
		size += 1
		local i = size
		heap[i] = {node, f}
		while i > 1 do
			local parent = i // 2
			if heap[parent][2] <= heap[i][2] then break end
			heap[parent], heap[i] = heap[i], heap[parent]
			i = parent
		end
	end
	local function pop()
		local top = heap[1]
		heap[1] = heap[size]
		heap[size] = nil
		size -= 1
		local i = 1
		while true do
			local l, r, m = i * 2, i * 2 + 1, i
			if l <= size and heap[l][2] < heap[m][2] then m = l end
			if r <= size and heap[r][2] < heap[m][2] then m = r end
			if m == i then break end
			heap[m], heap[i] = heap[i], heap[m]
			i = m
		end
		return top[1]
	end
	for _, source in ipairs(sources) do
		if g[source[1]] == nil or source[2] < g[source[1]] then
			g[source[1]] = source[2]
			push(source[1], source[2] + (nav.nodes[source[1]] - goalPos).Magnitude)
		end
	end
	while size > 0 do
		local node = pop()
		if node == goal then
			local list = {node}
			while from[node] do
				node = from[node]
				table.insert(list, 1, node)
			end
			return list
		end
		if not closed[node] then
			closed[node] = true
			for _, link in ipairs(nav.links[node]) do
				local cost = g[node] + link.cost
				if not closed[link.to] and (g[link.to] == nil or cost < g[link.to]) then
					g[link.to] = cost
					from[link.to] = node
					push(link.to, cost + (nav.nodes[link.to] - goalPos).Magnitude)
				end
			end
		end
	end
	return nil
end

-- Add the way along a list of nodes to `points`. tags[i] is the node points[i] is, or false for a point on the
-- way between two nodes (the middle of a doorway, the foot and the head of a stair).
local function navExpand(nav, list, points, tags)
	for i = 2, #list do
		local a, b = list[i - 1], list[i]
		local chosen = nil
		for _, link in ipairs(nav.links[a]) do
			if link.to == b and (not chosen or link.cost < chosen.cost) then chosen = link end
		end
		for _, point in ipairs(chosen.via) do
			points[#points + 1] = point
			tags[#points] = false
		end
		points[#points + 1] = nav.nodes[b]
		tags[#points] = b
	end
end

-- ---------------------------------------------------------------------------------------
-- the child
local VOICE = {
	ready = {"l6_ready_1", "l6_ready_2", "l6_ready_3"},
	search = {"l6_search_1", "l6_search_2", "l6_search_3", "l6_search_4", "l6_search_5", "l6_search_6", "l6_search_7", "l6_search_8"},
	check = {"l6_check_1", "l6_check_2", "l6_check_3"},
	spot = {"l6_spot_1", "l6_spot_2", "l6_spot_3"},
	chase = {"l6_chase_1", "l6_chase_2", "l6_chase_3"},
	lost = {"l6_lost_1", "l6_lost_2"},
	found = {"l6_found_1", "l6_found_2", "l6_found_3"},
	dunk = {"l6_dunk_1", "l6_dunk_2", "l6_dunk_3"},
	exit = {"l6_exit_1", "l6_exit_2"},
	-- the lines for when it has lost; until the owner records l6_angry_*, the exit lines stand in
	angry = {"l6_angry_1", "l6_angry_2", "l6_angry_3"},
	sprint = {"l6_sprint_1", "l6_sprint_2"},          -- shrieked as it starts to run at you
	kill = {"l6_kill_1", "l6_kill_2", "l6_kill_3"},   -- whispered in the kill cam
}
local FALLBACK = {angry = "exit", sprint = "spot", kill = "found"}   -- until a group's lines are installed
local lastLine = {}
local function pick(group)
	local list = VOICE[group]
	if FALLBACK[group] then
		local voice = ReplicatedStorage:FindFirstChild("Level6Counter")
		voice = voice and voice:FindFirstChild("Voice")
		if not (voice and voice:FindFirstChild(list[1])) then list = VOICE[FALLBACK[group]] end
	end
	local i = math.random(#list)
	if #list > 1 and i == lastLine[group] then i = i % #list + 1 end
	lastLine[group] = i
	return list[i]
end

-- The doll's mesh cannot be uploaded from a session, so it is rebuilt here once per server from the
-- staged source and baked to session content, the same way the lobby's RuntimeBake does.
local function buildDollTemplate()
	local source = ServerStorage:FindFirstChild("Level6CounterSource")
	if not source then error("ServerStorage.Level6CounterSource is missing") end
	local function load(key)
		local parts, i = {}, 1
		while true do
			local sv = source:FindFirstChild(key .. "_" .. i)
			if not sv then break end
			parts[#parts + 1] = sv.Value; i += 1
		end
		return HttpService:JSONDecode(table.concat(parts))
	end
	local V, UV, N, T, W, bones = load("V"), load("UV"), load("N"), load("T"), load("W"), load("B")
	local em = AssetService:CreateEditableMesh()
	local vid, uid, nid, bid, byName = {}, {}, {}, {}, {}
	for i = 1, #V, 3 do vid[#vid + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]) / 1000) end
	for i = 1, #UV, 2 do uid[#uid + 1] = em:AddUV(Vector2.new(UV[i], UV[i + 1]) / 10000) end
	for i = 1, #N, 3 do nid[#nid + 1] = em:AddNormal(Vector3.new(N[i], N[i + 1], N[i + 2]) / 1000) end
	for i = 1, #T, 9 do
		local f = em:AddTriangle(vid[T[i] + 1], vid[T[i + 1] + 1], vid[T[i + 2] + 1])
		em:SetFaceUVs(f, {uid[T[i + 3] + 1], uid[T[i + 4] + 1], uid[T[i + 5] + 1]})
		em:SetFaceNormals(f, {nid[T[i + 6] + 1], nid[T[i + 7] + 1], nid[T[i + 8] + 1]})
		if i % 18000 == 1 then task.wait() end
	end
	for i, b in ipairs(bones) do
		bid[i] = em:AddBone({Name = b.name, CFrame = CFrame.new(b.pos[1], b.pos[2], b.pos[3]), Virtual = false})
		byName[b.name] = bid[i]
	end
	for i, b in ipairs(bones) do
		if b.parent then em:SetBoneParent(bid[i], byName[b.parent]) end
	end
	local i, v = 1, 1
	while i <= #W do
		local n = W[i]; i += 1
		local ids, ws = {}, {}
		for k = 1, n do ids[k] = bid[W[i] + 1]; ws[k] = W[i + 1] / 1000; i += 2 end
		em:SetVertexBones(vid[v], ids); em:SetVertexBoneWeights(vid[v], ws)
		v += 1
	end
	local ok, result, content = pcall(AssetService.CreateDataModelContentAsync, AssetService, Content.fromObject(em))
	em:Destroy()
	if not ok or result ~= Enum.CreateContentResult.Success then error("doll bake failed: " .. tostring(result)) end
	local body = AssetService:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box})
	body.Name = "Body"
	body.Color, body.Material = Color3.new(1, 1, 1), Enum.Material.SmoothPlastic
	body.TextureID = source:GetAttribute("Texture") or ""
	body.CanCollide, body.CanTouch, body.CanQuery, body.Massless, body.Anchored = false, false, false, true, false
	local made = {}
	for _, b in ipairs(bones) do
		local bone = Instance.new("Bone")
		bone.Name = b.name
		local pos = Vector3.new(b.pos[1], b.pos[2], b.pos[3])
		made[b.name] = {bone = bone, pos = pos}
		if b.parent then
			bone.CFrame = CFrame.new(pos - made[b.parent].pos); bone.Parent = made[b.parent].bone
		else
			bone.CFrame = CFrame.new(pos); bone.Parent = body
		end
	end
	local model = Instance.new("Model")
	model.Name = "Level 6 Counting Child"
	local root = Instance.new("Part")
	root.Name, root.Size, root.Transparency = "Root", Vector3.new(1.5, 1.5, 1.5), 1
	root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = true, false, false, false
	root.Parent = model
	body.CFrame = root.CFrame
	body.Parent = model
	-- a Weld with explicit offsets: a WeldConstraint takes its offset when it first becomes active, which is
	-- after the clone's root has already been moved, and the body then stays at the world origin
	local weld = Instance.new("Weld")
	weld.Part0, weld.Part1, weld.C0, weld.C1 = root, body, CFrame.identity, CFrame.identity
	weld.Parent = root
	local glow = Instance.new("PointLight")   -- just enough to read the face in the dark hall
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = Color3.fromRGB(255, 225, 190), 9, 0.55, false
	glow.Parent = root
	model.PrimaryPart = root
	CONFIG.HipHeight = -(source:GetAttribute("FeetY") or -CONFIG.HipHeight)
	return model
end

local dollTemplate = nil   -- nil = not tried yet, false = the bake failed on this server
local function buildChild()
	if dollTemplate == nil then
		local ok, built = pcall(buildDollTemplate)
		if not ok then warn("[Level6] counting child: " .. tostring(built)) end
		dollTemplate = ok and built or false
	end
	if dollTemplate then
		local model = dollTemplate:Clone()
		return model, model.PrimaryPart
	end
	-- last resort so the round still runs: a plain pale block
	local model = Instance.new("Model")
	model.Name = "Level 6 Counting Child"
	local root = Instance.new("Part")
	root.Name, root.Size, root.Color = "Root", Vector3.new(1.6, 4.8, 1), Color3.fromRGB(225, 215, 205)
	root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = true, false, false, false
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

-- ---------------------------------------------------------------------------------------
-- session
local Session = {}
Session.__index = Session

local function broadcast(s, ...)
	for player in pairs(s.players) do
		if player.Parent == Players then event:FireClient(player, ...) end
	end
end

-- WIN_SCREEN_20261006 (owner: "the map completes like all other maps with the same screen and options"). A player
-- who gets out is taken off the session and sent GameManager's own "win" word on the round remote, so RoundUI draws
-- LEVEL 6 CLEARED with the time, the survivors and BACK TO LOBBY (the last level has no CONTINUE), counting down as
-- in every level. The serials start far from GameManager's and Level 5's, so neither answers for this one.
local winners = {}            -- player -> {serial, deadline}
local winSerial = 600000
local function releaseWinner(player, serial)
	local mine = winners[player]
	if not mine or (serial and mine.serial ~= serial) then return end
	winners[player] = nil
	if player.Parent == Players and returnHandler and player:GetAttribute(IN_PREVIEW) == true then
		returnHandler(player, "escaped")
	end
end
local function sendWin(s, player)
	winSerial += 1
	local mine = {serial = winSerial, deadline = workspace:GetServerTimeNow() + CONFIG.WinChoiceSeconds}
	winners[player] = mine
	roundStatus:FireClient(player, "win", os.clock() - s.startedAt, s.escapedCount, math.max(s.partySize, s.escapedCount, 1),
		mine.deadline, nil, mine.serial)
	task.delay(CONFIG.WinChoiceSeconds + 0.5, function() releaseWinner(player, mine.serial) end)
end
roundStatus.OnServerEvent:Connect(function(player, message, serial)
	local mine = winners[player]
	if message == "returntolobby" and mine and tonumber(serial) == mine.serial then
		roundStatus:FireClient(player, "returnpending", mine.serial)
		releaseWinner(player, mine.serial)
	end
end)
Players.PlayerRemoving:Connect(function(player) winners[player] = nil end)

local function newSession(info)
	local s = setmetatable({}, Session)
	s.info = info
	s.players = {}           -- player -> {dunked = bool}
	s.active = true
	s.round = 0
	s.dunks = 0
	s.wins = 0               -- searches in which every living player touched the post
	s.startedAt, s.partySize, s.escapedCount = os.clock(), 0, 0
	info.model:SetAttribute("Level6Wins", 0)
	info.model:SetAttribute("Level6WinsNeeded", CONFIG.RoundsToWin)
	s.phase = "starting"
	s.checked = {}
	s.anim = {speed = 0, name = "Idle", serial = 0}
	s.voiceUntil = 0
	local model, root = buildChild()
	s.child, s.root = model, root
	local home = info.home
	root.CFrame = CFrame.lookAt(home + Vector3.new(0, CONFIG.HipHeight - 3 + 0.35, 4), home + Vector3.new(0, CONFIG.HipHeight - 3 + 0.35, 0))
	model.Parent = info.model
	-- ARENA_20261006: where it is on the graph. It starts on the node it counts from.
	s.nav = info.arena and navOf(info.model) or nil
	if s.nav then
		s.navLast, s.navBehind, s.navLoose = s.nav.home, {}, false
		local stand = s.nav.nodes[s.nav.home]
		root.CFrame = CFrame.lookAt(stand + Vector3.new(0, CONFIG.HipHeight, 0), Vector3.new(home.X, stand.Y + CONFIG.HipHeight, home.Z))
	elseif info.arena then
		warn("[Level6] the arena has no navigation graph: the Counter falls back to PathfindingService")
	end
	s.heartbeat = RunService.Heartbeat:Connect(function(dt) s:animate(dt) end)
	return s
end

function Session:target()
	-- Owner, 2026-10-03: the objective is that EVERY living player touches the post in the same search.
	-- The target is therefore the number of players still alive, and a tag only lasts for its round.
	return math.max(1, self:living())
end

function Session:count()
	local n = 0
	for _ in pairs(self.players) do n += 1 end
	return n
end

-- Bone.Transform does not replicate, so the Level 6 Playground Client plays the clips. The server only
-- publishes which clip, a serial that restarts it, and a rounded speed, as attributes on the model.
function Session:animate(dt)
	local a = self.anim
	local child = self.child
	local speed = math.floor(a.speed + 0.5)
	if child:GetAttribute("Anim") ~= a.name then child:SetAttribute("Anim", a.name) end
	if child:GetAttribute("AnimSerial") ~= a.serial then child:SetAttribute("AnimSerial", a.serial) end
	if child:GetAttribute("Speed") ~= speed then child:SetAttribute("Speed", speed) end
	child:SetAttribute("Chasing", self.chase ~= nil)
end

-- Stand still and play a clip from its first frame.
function Session:pose(name)
	self.anim.name = name
	self.anim.serial += 1
	self.anim.speed = 0
end

-- Speak one recorded line (ReplicatedStorage.Level6Counter.Voice). Chatter gives way to a line that is
-- still playing; `force` cuts it off. Returns the line's length in seconds, or nil when it was skipped.
function Session:say(key, force)
	if not force and clock() < self.voiceUntil then return nil end
	local voice = ReplicatedStorage:FindFirstChild("Level6Counter")
	voice = voice and voice:FindFirstChild("Voice")
	local sound = voice and voice:FindFirstChild(key)
	local seconds = sound and sound:GetAttribute("Seconds") or 2
	self.voiceUntil = clock() + seconds + 0.5
	broadcast(self, "say", key)
	return seconds
end

function Session:place(pos, face)
	local p = Vector3.new(pos.X, pos.Y + CONFIG.HipHeight, pos.Z)
	local look = flat(face or self.root.CFrame.LookVector)
	if look.Magnitude < 0.01 then look = self.root.CFrame.LookVector end
	self.root.CFrame = CFrame.lookAt(p, p + look.Unit)
end

function Session:feet()
	return self.root.Position - Vector3.new(0, CONFIG.HipHeight, 0)
end

function Session:path(to)
	local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 8, AgentCanJump = true,
		AgentCanClimb = false, WaypointSpacing = 5})
	local ok = pcall(function() path:ComputeAsync(self:feet(), to) end)
	if not ok or path.Status ~= Enum.PathStatus.Success then return nil end
	local points = {}
	for _, w in ipairs(path:GetWaypoints()) do points[#points + 1] = w.Position end
	return points
end

-- Move along points until done, interrupted (self.interrupt) or the phase changes. Returns true on arrival.
function Session:follow(points, speed, phase)
	for i = 2, #points do
		local goal = points[i]
		while true do
			if not self.active or self.phase ~= phase or self.interrupt then return false end
			local dt = RunService.Heartbeat:Wait()
			if self.partyOn then self:hold(); continue end
			-- A catch can land during that wait. Without this check the loop took one more step: it moved the doll
			-- off the spot catch() had just stood it on and put the run clip back over the grab, so every catch
			-- that ended a chase played the kill in the running pose.
			if not self.active or self.phase ~= phase or self.interrupt then return false end
			local feet = self:feet()
			local delta = goal - feet
			local dist = delta.Magnitude
			local step = speed * dt
			self.anim.speed = speed
			self.anim.name = speed >= 15 and "Run_Chase" or "Walk_Wander"
			if dist <= step then
				self:place(goal, flat(delta))
				break
			end
			self:place(feet + delta.Unit * step, flat(delta))
		end
	end
	return true
end

-- ARENA_20261006: the way over the graph from where it stands to `target`. It may be part-way along a link
-- when it is asked (called off by a noise, or planning again in a chase): then the way starts with whichever end
-- of that link is the shorter way round, along the link, never across the cell. With `approach` the way ends
-- with the last few studs to the target itself, inside the target's own cell.
function Session:routeTo(target, approach)
	local nav = self.nav
	local feet = self:feet()
	local goal = navNodeAt(nav, target)
	if not goal then return nil end
	local points, tags = {feet}, {false}
	local sources = {}
	local last = self.navLast
	local behind, ahead, nextNode = {}, {}, nil
	if self.navLoose or not last then
		local here = navNodeAt(nav, feet)
		sources[1] = {here, (nav.nodes[here] - feet).Magnitude}
		last = nil
	else
		behind = self.navBehind or {}
		local route = self.navRoute
		if route then
			for j = (self.navIndex or 1) + 1, #route.points do
				local tag = route.tags[j]
				if tag == "off" then break end
				ahead[#ahead + 1] = route.points[j]
				if tag then nextNode = tag; break end
			end
		end
		local cost, at = 0, feet
		for i = #behind, 1, -1 do cost += (behind[i] - at).Magnitude; at = behind[i] end
		sources[1] = {last, cost + (nav.nodes[last] - at).Magnitude}
		if nextNode then
			cost, at = 0, feet
			for _, point in ipairs(ahead) do cost += (point - at).Magnitude; at = point end
			sources[2] = {nextNode, cost}
		end
	end
	local list = navRoute(nav, sources, goal)
	if not list then return nil end
	local first = list[1]
	local state = nil                    -- what it will have behind it once it sets off this way
	if nextNode and first == nextNode then
		for i, point in ipairs(ahead) do
			points[#points + 1] = point
			tags[#points] = i == #ahead and first or false
		end
	elseif last and first == last then
		for i = #behind, 1, -1 do
			points[#points + 1] = behind[i]
			tags[#points] = false
		end
		points[#points + 1] = nav.nodes[first]
		tags[#points] = first
		if nextNode then
			-- turning back: the node it was heading for is the one behind it now
			local passed = {}
			for i = #ahead - 1, 1, -1 do passed[#passed + 1] = ahead[i] end
			state = {last = nextNode, behind = passed}
		end
	else
		points[#points + 1] = nav.nodes[first]
		tags[#points] = first
	end
	navExpand(nav, list, points, tags)
	if approach then
		local node = nav.nodes[goal]
		if math.abs(target.Y - node.Y) < 4.5 and flat(target - node).Magnitude < 16 then
			points[#points + 1] = Vector3.new(target.X, node.Y, target.Z)
			tags[#points] = "off"
		end
	end
	return {points = points, tags = tags, goal = goal, state = state}
end

-- The first `count` points of a way: a chase plans again before it has gone further than that. The whole way is
-- kept beside it, because the next plan has to know which node lies ahead even when the cut falls half-way up a
-- stair (without that it only knew the node behind it, turned back every time, and stood jittering on the steps).
local function clipRoute(route, count)
	if #route.points <= count then return route end
	local points, tags = {}, {}
	for i = 1, count do points[i], tags[i] = route.points[i], route.tags[i] end
	return {points = points, tags = tags, goal = route.goal, state = route.state, whole = route}
end

-- Walk a way from routeTo, keeping track of the node behind it and the points passed since.
function Session:travel(route, speed, phase)
	local points, tags = route.points, route.tags
	if route.state then self.navLast, self.navBehind = route.state.last, route.state.behind end
	self.navRoute, self.navIndex = route.whole or route, 1
	for i = 2, #points do
		local goal = points[i]
		if tags[i] == "off" then self.navLoose = true end
		while true do
			if not self.active or self.phase ~= phase or self.interrupt then return false end
			local dt = RunService.Heartbeat:Wait()
			if self.partyOn then self:hold(); continue end
			if not self.active or self.phase ~= phase or self.interrupt then return false end
			local feet = self:feet()
			local delta = goal - feet
			local dist = delta.Magnitude
			local step = speed * dt
			self.anim.speed = speed
			self.anim.name = speed >= 15 and "Run_Chase" or "Walk_Wander"
			if dist <= step then
				self:place(goal, flat(delta))
				break
			end
			self:place(feet + delta.Unit * step, flat(delta))
		end
		self.navIndex = i
		local tag = tags[i]
		if type(tag) == "number" then
			self.navLast, self.navBehind, self.navLoose = tag, {}, false
		elseif tag == false and not self.navLoose then
			table.insert(self.navBehind, goal)
		end
	end
	return true
end

function Session:walkTo(pos, speed, phase)
	if self.nav then
		local route = self:routeTo(pos, false)
		if not route then return false end
		return self:travel(route, speed, phase)
	end
	local points = self:path(pos)
	if not points then
		-- the 8-stud doll cannot get into a playhouse or behind a counter: go and stand next to it instead
		for _, off in ipairs({Vector3.new(0, 0, 7), Vector3.new(7, 0, 0), Vector3.new(-7, 0, 0), Vector3.new(0, 0, -7)}) do
			points = self:path(pos + off)
			if points then break end
		end
	end
	if not points then
		-- unreachable by navmesh: glide straight if it is close, otherwise give up on this goal
			if (pos - self:feet()).Magnitude > 24 then return false end
		points = {self:feet(), pos}
	end
	return self:follow(points, speed, phase)
end

-- The visible surface under a point. Home base is a raised disc, so the hall's floor height put the
-- doll's feet inside it while it counted.
function Session:surface(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {self.child}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	for _ = 1, 6 do
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), params)
		if not hit then break end
		if hit.Instance.Transparency < 0.9 and hit.Normal.Y > 0.7 then
			return Vector3.new(pos.X, hit.Position.Y, pos.Z)
		end
		table.insert(ignore, hit.Instance)
	end
	return pos
end

function Session:walkSpeed()
	return self.info.arena and CONFIG.ArenaWalkSpeed or CONFIG.WalkSpeed
end

-- ARENA_20261006: through the gate and inside the hall (the tunnel a party arrives in is outside it).
function Session:inside(pos)
	local radius = self.info.gateRadius
	if not radius then return true end
	return flat(pos - self.info.home).Magnitude < radius - 1
end

function Session:goHome(phase)
	local home = self.info.home
	local stand = home + Vector3.new(0, 0.35 - 3, 4)
	self:walkTo(stand, self:walkSpeed() * 1.4, phase)
	stand = self:surface(stand)
	self:place(stand, home - stand)
	self:pose("Idle")
end

-- ---------------------------------------------------------------------------------------
-- perception
function Session:rayParams()
	local exclude = {self.child}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then exclude[#exclude + 1] = p.Character end
	end
	local model = self.info.model
	for _, name in ipairs({"Frame_Nets", "Frame_BridgeNets", "Frame_RoofNet", "BallOcean_Nets", "Signs", "BallOcean_Balls",
		"Toddler_Balls", "Lights", "Anchors", "Frame_Rollers", "Frame_Lamps", "Ceiling_Fixtures"}) do
		local f = model:FindFirstChild(name)
		if f then exclude[#exclude + 1] = f end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	-- ARENA_20261006: a second look that only meets netting, for "is there a net between us"
	local nets = {}
	for _, name in ipairs({"Frame_Nets", "Frame_BridgeNets"}) do
		local f = model:FindFirstChild(name)
		if f then nets[#nets + 1] = f end
	end
	local netParams = RaycastParams.new()
	netParams.FilterType = Enum.RaycastFilterType.Include
	netParams.FilterDescendantsInstances = nets
	self.netParams = netParams
	return params
end

function Session:hidden(pos)
	for _, spot in ipairs(self.info.spots) do
		local d = flat(spot - pos).Magnitude
		if d <= CONFIG.HideRadius and math.abs(spot.Y - pos.Y) < 4.5 then return true end
	end
	return false
end

function Session:sees(root, params, hunted)
	local eye = self.root.Position + Vector3.new(0, CONFIG.EyeHeight, 0)
	local to = root.Position + Vector3.new(0, 1.5, 0)
	local delta = to - eye
	local dist = delta.Magnitude
	if dist > CONFIG.SightRange then return false, dist end
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if self:hidden(root.Position) and dist > CONFIG.HiddenSpotRange and not (speed > 10 and dist < 25) then
		return false, dist
	end
	local arena = self.info.arena and not hunted       -- whoever it is already after gets none of this
	if arena and dist > CONFIG.CloseRange and not self.lookingRound then
		-- ARENA_20261006: it sees what it is facing. From the post it would otherwise look into every gallery at once.
		if self.root.CFrame.LookVector:Dot(delta.Unit) < CONFIG.SightCos then return false, dist end
	end
	if workspace:Raycast(eye, delta, params) then return false, dist end
	if arena and dist > CONFIG.NetCoverRange and root.AssemblyLinearVelocity.Magnitude < CONFIG.StillSpeed
		and self.netParams and workspace:Raycast(eye, delta, self.netParams) then
		return false, dist              -- standing still behind netting: it looks straight past you
	end
	return true, dist
end

function Session:perceive()
	local params = self:rayParams()
	local best, bestDist = nil, math.huge
	for player, state in pairs(self.players) do
		local root = rootOf(player)
		if root and self.info.arena then
			-- ARENA_20261006: a player still in the tunnel has not come in; one under the floor is on the way out
			if not state.entered and self:inside(root.Position) then state.entered = true end
			if state.entered and not self:inside(root.Position) and root.Position.Y > self.info.floorY - 3
				and flat(root.Position - self.info.home).Magnitude > self.info.gateRadius + 2 then
				-- no way back out: the gate lets you in, not out
				local inward = flat(self.info.home - self.info.gate).Unit
				local at = self.info.gate + inward * 7
				root.AssemblyLinearVelocity = Vector3.zero
				root.Parent:PivotTo(CFrame.lookAt(Vector3.new(at.X, self.info.floorY + 4.4, at.Z), Vector3.new(self.info.home.X, self.info.floorY + 4.4, self.info.home.Z)))
			end
			if not state.entered or root.Position.Y < self.info.floorY - 3 then root = nil end
		end
		if root and not state.caught and clock() >= (state.graceUntil or 0) then
			local seen, dist = self:sees(root, params, self.chase == player)
			if seen and dist < bestDist then best, bestDist = player, dist end
			local speed = flat(root.AssemblyLinearVelocity).Magnitude
			if not seen and speed >= CONFIG.NoiseSpeed and dist <= CONFIG.NoiseRange and not self.chase then
				self.noise = root.Position
			end
			if dist <= CONFIG.CatchDistance and math.abs(root.Position.Y - self.root.Position.Y) < 5 then
				self:catch(player)
				-- a caught player must not be handed back as the next chase target
				if best == player then best, bestDist = nil, math.huge end
			end
		end
	end
	return best
end

-- CHOKE_20261006: the victim's neck t seconds into the kill, as a point in the doll's own frame (its Root).
local function chokeNeck(t)
	local c = CONFIG.Choke
	local function ease(a, b)
		local u = math.clamp((t - a) / (b - a), 0, 1)
		return u * u * (3 - 2 * u)
	end
	local lift, pull = ease(c.Times[1], c.Times[2]), ease(c.Times[3], c.Times[4])
	local rise = c.Grab[1] + (c.Lift[1] - c.Grab[1]) * lift + (c.Pull[1] - c.Lift[1]) * pull
	local away = c.Grab[2] + (c.Lift[2] - c.Grab[2]) * lift + (c.Pull[2] - c.Lift[2]) * pull
	return Vector3.new(0, -CONFIG.HipHeight + c.NeckAboveFeet + rise, -away)
end

function Session:catch(player)
	local state = self.players[player]
	if not state or state.caught then return end
	state.caught = true
	if self.chase == player then self.chase = nil end
	event:FireClient(player, "caught", player.DisplayName, true)
	for other in pairs(self.players) do
		if other ~= player then event:FireClient(other, "caught", player.DisplayName, false) end
	end
	-- The kill cam: the victim is held where they stand, the doll squares up in front of them with its
	-- arms out, and their client pulls the camera into its face. They leave when the screen cuts to black.
	local held = rootOf(player)
	if held then
		held.AssemblyLinearVelocity = Vector3.zero
		held.Anchored = true
		local feet = self:feet()
		-- at chase speed it is usually standing on top of them by now: back off the way it came
		local to = flat(held.Position - feet)
		if to.Magnitude < 0.5 then to = flat(self.root.CFrame.LookVector) end
		if to.Magnitude < 0.1 then to = Vector3.zAxis end
		local stand = Vector3.new(held.Position.X, feet.Y, held.Position.Z) - to.Unit * CONFIG.GrabDistance
		self:place(self:surface(stand), to)
	end
	self.pauseUntil = clock() + CONFIG.CaughtReturnDelay
	self.killUntil = clock() + CONFIG.CaughtReturnDelay + 0.5
	self.interrupt = true
	self.navLoose = true          -- it left the graph to stand in front of them
	self:pose("Choke")
	self:say(pick("kill"), true)
	-- What the others see (CHOKE_20261006): the victim is turned to face it and their neck is carried along
	-- chokeNeck, the path the clip's hands are solved to: taken by the throat where they stand, lifted off the
	-- floor at arm's length, then drawn down to its face.
	if held then
		local from, started = held.CFrame, os.clock()
		local doll = self.root.CFrame
		local head = held.Parent and held.Parent:FindFirstChild("Head")
		local attach = head and head:FindFirstChild("NeckRigAttachment")
		local neckLocal = from:PointToObjectSpace(attach and attach.WorldPosition or (from.Position + Vector3.new(0, 1.06, 0)))
		local facing = CFrame.lookAt(Vector3.zero, flat(doll.Position - from.Position).Magnitude > 0.1
			and flat(doll.Position - from.Position) or -doll.LookVector)
		local grabTime = CONFIG.Choke.Times[1]
		task.spawn(function()
			while held.Parent and held.Anchored and os.clock() - started < CONFIG.CaughtReturnDelay do
				local t = os.clock() - started
				local target = CFrame.new(doll:PointToWorldSpace(chokeNeck(t))) * facing * CFrame.new(-neckLocal)
				local grab = math.clamp(t / grabTime, 0, 1)
				held.CFrame = from:Lerp(target, grab * grab * (3 - 2 * grab))     -- from where they stood, in the time its arms take
				task.wait()
			end
		end)
	end
	task.delay(CONFIG.CaughtReturnDelay, function()
		if held and held.Parent then held.Anchored = false end
		-- "then you die": the body drops where it was held and the round's usual death flow takes over
		-- (spectate, the PARTY DOWN card, Emergency Re-entry). playerDied runs off the humanoid.
		local humanoid = held and held.Parent and held.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then humanoid.Health = 0 else self:playerDied(player) end
		achieve(player, "L6Caught")          -- after the kill cam: its toast would sit over the doll's face
	end)
	if self:living() > 0 and self.active then
		task.delay(CONFIG.CaughtReturnDelay + 0.4, function() if self.active then self:say("l6_found_other", true) end end)
	end
end

-- Living players who have touched the post in this search.
function Session:tagged()
	local n = 0
	for _, state in pairs(self.players) do
		if state.dunked and not state.caught and not state.escaped then n += 1 end
	end
	return n
end

-- Players still on their feet: neither caught nor out through the exit.
function Session:living()
	local n = 0
	for _, state in pairs(self.players) do
		if not state.caught and not state.escaped then n += 1 end
	end
	return n
end

-- Every death in the level lands here once, whether the doll did it or the player reset. Same events on the
-- same remote GameManager uses for its own rounds, so RoundUI, the spectate band and the store behave as in
-- any level: "death" to the party, and "partydown" with its 15 seconds when nobody is left standing.
function Session:playerDied(player)
	local state = self.players[player]
	if not state or state.dead then return end
	state.caught, state.dead = true, true
	if self.chase == player then self.chase = nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for other in pairs(self.players) do
		if other.Parent == Players then
			roundStatus:FireClient(other, "death", player.Name, root and root.Position or nil, DEATH_CAUSE)
		end
	end
	if self:living() == 0 and not self.wipedAt then
		self.wipedAt = clock()
		self.interrupt = true
		for other in pairs(self.players) do
			if other.Parent == Players then
				roundStatus:FireClient(other, "partydown", CONFIG.PartyDownSeconds, player.Name, DEATH_CAUSE)
			end
		end
	end
end

-- The 15 seconds after the last player falls. True when somebody re-entered and the round goes on.
function Session:wipeWindow()
	self:pose("Idle")
	while self.active and self.wipedAt and clock() - self.wipedAt < CONFIG.PartyDownSeconds do
		self.anim.speed = 0
		task.wait(0.2)
		if self:count() == 0 then break end
	end
	if self.active and not self.wipedAt and self:living() > 0 then return true end
	broadcast(self, "lost")
	broadcast(self, "say", "l6_win")
	return false
end

-- Emergency Re-entry (ServerStorage.Level6Reentry, reached through GameManager's ZyntraReentry): one per
-- player per round, back in the round body at the level's entrance with a few seconds the doll cannot see.
function Session:reenter(player, free)
	local state = self.players[player]
	if not self.active or not state or not state.dead or state.reentering then return false end
	if not free and player:GetAttribute("ZyntraReentryUsed") == true then return false end
	state.reentering = true
	local load = ServerStorage:FindFirstChild("LoadGameplayCharacter")
	local previous = player.Character
	local ok, loaded = pcall(function() return load ~= nil and load:Invoke(player) end)
	state.reentering = nil
	local character = player.Character
	if not ok or loaded ~= true or not character or character == previous
		or not self.active or self.players[player] ~= state then return false end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root then return false end
	root.AssemblyLinearVelocity = Vector3.zero
	-- the level's entrance, where a party arrives: not home base, where the doll counts
	local entrance = self.info.model:FindFirstChild("Level6Exit", true)
	local at = entrance and entrance:IsA("BasePart") and entrance.Position or self.info.spawn
	character:PivotTo(CFrame.new(at + Vector3.new(0, 3.5, 0)))
	state.caught, state.dead, state.dunked = false, false, false
	state.graceUntil = clock() + CONFIG.ReentryGraceSeconds
	if not free then player:SetAttribute("ZyntraReentryUsed", true) end
	local wasWiped = self.wipedAt ~= nil
	self.wipedAt = nil
	for other in pairs(self.players) do
		if other.Parent == Players then
			roundStatus:FireClient(other, "reentry", player.Name)
			if wasWiped then roundStatus:FireClient(other, "partydownclear") end
		end
	end
	event:FireClient(player, "joined", self.round, self.dunks, self:target(), self.phase)
	return true
end

-- ---------------------------------------------------------------------------------------
-- phases
-- ARENA_20261006: a party arrives in the tunnel and walks in through the PLAY ZONE gate. The Counter stands at
-- the post with its back to them and does nothing until they are in: everyone, or whoever is in after a wait.
function Session:arrivalPhase()
	self.phase = "arrival"
	self:pose("Idle")
	local started, firstIn = clock(), nil
	while self.active and self:count() > 0 do
		local everyone, anyone = true, false
		for player, state in pairs(self.players) do
			local root = rootOf(player)
			if root and self:inside(root.Position) then state.entered = true end
			if state.entered then anyone = true elseif root then everyone = false end
		end
		if anyone and not firstIn then firstIn = clock() end
		if (anyone and everyone) or (firstIn and clock() - firstIn > CONFIG.ArrivalWait) or clock() - started > 120 then break end
		task.wait(0.2)
	end
end

function Session:countPhase()
	self.phase = "count"
	self.round += 1
	self.checked = {}
	for _, state in pairs(self.players) do state.dunked = false end
	self.dunks = 0
	self:goHome("count")
	if not self.active then return end
	self.phase = "count"
	if self.round == 1 then
		-- the welcome: quiet for a few seconds once everyone is in, the PA chime, then its announcement
		task.wait(CONFIG.IntroSilence)
		for _, key in ipairs({"l6_pa_chime", "l6_intro", "l6_pa_off"}) do
			local voice = ReplicatedStorage:FindFirstChild("Level6Counter")
			local sound = voice and voice:FindFirstChild("Voice") and voice.Voice:FindFirstChild(key)
			if sound and self.active and self.phase == "count" then
				broadcast(self, "pa", key)
				task.wait((sound:GetAttribute("Seconds") or 3) + 0.4)
			end
		end
		if not self.active or self.phase ~= "count" then return end
	end
	self:pose("Count_Start")
	task.wait(0.8)                        -- hands go up before the first number
	if not self.active or self.phase ~= "count" then return end
	self:pose("Count_Loop")
	local seconds = self:say(CONFIG.CountLines[math.min(self.round, #CONFIG.CountLines)], true) or 20
	broadcast(self, "round", self.round, self.dunks, self:target(), seconds)
	if self.round >= 3 then
		for player in pairs(self.players) do achieve(player, "L6Survivor") end
	end
	local beat = seconds / CONFIG.CountTo   -- the numbers on the HUD keep pace with the recording
	for n = 1, CONFIG.CountTo do
		if not self.active or self.phase ~= "count" then return end
		broadcast(self, "count", n, CONFIG.CountTo)
		task.wait(beat)
	end
	self:pose("Count_End")
	local ready = self:say(pick("ready"), true) or 2
	broadcast(self, "go")
	task.wait(math.min(ready, 1.6))       -- it sets off while it is still talking
	self:pose("Idle")
end

-- HUNT_20261006: whoever is nearest of those still standing inside (a straight line, floors included).
function Session:nearestPlayer()
	local feet, best, bestD = self:feet(), nil, nil
	for player, state in pairs(self.players) do
		local root = rootOf(player)
		if root and not state.caught and not state.escaped and state.entered and root.Position.Y > self.info.floorY - CONFIG.ExitDrop then
			local d = (root.Position - feet).Magnitude
			if not bestD or d < bestD then best, bestD = root.Position, d end
		end
	end
	return best, bestD
end

function Session:huntPace()
	local n = math.max(self.round, 1)
	local speeds, plans = CONFIG.ArenaHuntSpeeds, CONFIG.ArenaHuntReplan
	local speed = speeds[n] or math.min(speeds[#speeds] + (n - #speeds) * CONFIG.ArenaHuntSpeedStep, CONFIG.ArenaHuntSpeedMax)
	local again = plans[n] or math.max(plans[#plans] - (n - #plans) * 0.1, CONFIG.ArenaHuntReplanMin)
	return speed, again
end

function Session:chooseSpot()
	local feet = self:feet()
	local options = {}
	-- ARENA_20261006: twelve floors is a lot to search blind. One time in three it has a feeling about where
	-- somebody is and looks near them; it does not know which spot, or that anyone is in one.
	local hunch = nil
	if self.info.arena and math.random() < 0.34 then
		local living = {}
		for player, state in pairs(self.players) do
			local root = rootOf(player)
			if root and not state.caught and state.entered then living[#living + 1] = root.Position end
		end
		if #living > 0 then hunch = living[math.random(#living)] end
	end
	for i, spot in ipairs(self.info.spots) do
		if not self.checked[i] then
			local d = (spot - (hunch or feet)).Magnitude
			if hunch then d = math.max(d - 14, 0) * 2 end
			options[#options + 1] = {i = i, spot = spot, w = 1 / (8 + d) ^ 1.3}
		end
	end
	if #options == 0 then self.checked = {}; return self:chooseSpot() end
	local total = 0
	for _, o in ipairs(options) do total += o.w end
	local r = math.random() * total
	for _, o in ipairs(options) do
		r -= o.w
		if r <= 0 then return o end
	end
	return options[#options]
end

function Session:seekBrain(deadline)
	while self.active and self.phase == "seek" and clock() < deadline do
		self:hold()
		self.interrupt = false
		if self.pauseUntil and clock() < self.pauseUntil then
			self.anim.speed = 0             -- holding a Spotted or Catch pose
			task.wait(0.1)
		elseif self.chase then
			local player = self.chase
			local root = rootOf(player)
			if not root or not self.players[player] or self.players[player].caught then
				self.chase = nil
			else
				if clock() > (self.nextChaseLine or 0) then
					self.nextChaseLine = clock() + 6 + math.random() * 4
					self:say(pick("chase"))
				end
				local target = root.Position - Vector3.new(0, 3, 0)
				if self.nav then
					-- ARENA_20261006: over the graph, planning again every third of a second
					local route = self:routeTo(target, true)
					if route then
						local started = clock()
						self.interrupt = false
						task.delay(0.35, function() if clock() - started >= 0.3 then self.interrupt = true end end)
						self:travel(clipRoute(route, 6), CONFIG.ChaseSpeed, "seek")
					else
						task.wait(0.2)
					end
					continue
				end
				local direct = (target - self:feet()).Magnitude < 28 and clock() - (self.lastSeen or 0) < 0.4
				-- no route is no obstacle: it comes straight through whatever is in the way
				local points = direct and {self:feet(), target} or self:path(target) or {self:feet(), target}
				if points then
					-- re-plan often while chasing; only the first stretch of the route is used
					local short = {points[1]}
					for i = 2, math.min(#points, 5) do short[#short + 1] = points[i] end
					local started = clock()
					self.interrupt = false
					task.delay(0.35, function() if clock() - started >= 0.3 then self.interrupt = true end end)
					self:follow(short, CONFIG.ChaseSpeed, "seek")
				else
					task.wait(0.2)
				end
			end
		elseif self.noise then
			local at = self.noise
			self.noise = nil
			self:walkTo(at - Vector3.new(0, 3, 0), self:walkSpeed() * 1.25, "seek")
		elseif self.info.arena then
			-- HUNT_20261006 (owner): it does not go looking in hiding places. It walks, calmly, toward whoever is
			-- nearest, keeps coming, and looks again at where they are now every second or so; quicker each search.
			if clock() > (self.nextSearchLine or 0) then
				self.nextSearchLine = clock() + 9 + math.random() * 8
				self:say(pick("search"))
			end
			local target, distance = self:nearestPlayer()
			local speed, again = self:huntPace()
			local route = target and self:routeTo(target - Vector3.new(0, 3, 0), true)
			if route and distance > 9 then
				local started = clock()
				self.interrupt = false
				task.delay(again, function() if self.phase == "seek" and clock() - started >= again - 0.05 then self.interrupt = true end end)
				self:travel(clipRoute(route, 8), speed, "seek")
			elseif target then
				-- as near as it can get, and it has not seen them: it stands and looks all round
				self:pose("Search_Look")
				self.lookingRound = true
				local untilT = clock() + 1.4
				while clock() < untilT and not self.chase and self.phase == "seek" do task.wait(0.1) end
				self.lookingRound = false
			else
				self:pose("Idle")
				task.wait(0.3)
			end
		else
			local option = self:chooseSpot()
			if clock() > (self.nextSearchLine or 0) then
				self.nextSearchLine = clock() + 9 + math.random() * 8
				self:say(pick("search"))
			end
			local arrived = self:walkTo(option.spot - Vector3.new(0, 0.5, 0), self:walkSpeed(), "seek")
			self.checked[option.i] = true
			if arrived and self.active and self.phase == "seek" and not self.chase then
				self:pose("Search_Look")
				self.lookingRound = true        -- it turns its head: for these seconds it sees all round
				local untilT = clock() + CONFIG.CheckPause
				while clock() < untilT and not self.chase and self.phase == "seek" do task.wait(0.1) end
				self.lookingRound = false
				if not self.chase and self.phase == "seek" and math.random() < 0.55 then self:say(pick("check")) end
			elseif not arrived and not self.chase then
				self:pose("Idle")
				task.wait(0.2)
			end
		end
	end
end

function Session:seekPhase()
	self.phase = "seek"
	local deadline = clock() + (self.info.arena and CONFIG.ArenaSeekSeconds or CONFIG.SeekSeconds)
	local safeDistance = self.info.arena and CONFIG.ArenaDunkSafeDistance or CONFIG.DunkSafeDistance
	local result = "timeup"
	local brain = task.spawn(function() self:seekBrain(deadline) end)
	local lastTimer = -1
	while self.active and self.phase == "seek" do
		task.wait(0.15)
		if self.partyOn then self:hold(); continue end
		if self:count() == 0 then result = "empty"; break end
		if self.wipedAt then result = "wiped"; break end
		local seen = self:perceive()
		if self.phase ~= "seek" then result = "lost"; break end
		if seen then
			if self.chase ~= seen then
				local first = self.chase == nil
				self.chase = seen
				self.interrupt = true
				event:FireClient(seen, "chase", true)
				if first and not (self.pauseUntil and clock() < self.pauseUntil) then
					-- it stops dead, points and says so before it runs: the player's head start
					self.pauseUntil = clock() + CONFIG.SpottedPause
					self:pose("Spotted")
					local feet = self:feet()
					local to = rootOf(seen)
					if to then self:place(feet, flat(to.Position - feet)) end
					self:say(pick("sprint"), true)
					self.nextChaseLine = clock() + 4
				end
			end
			self.lastSeen = clock()
		elseif self.chase and clock() - (self.lastSeen or 0) > CONFIG.LoseSightSeconds then
			local lost = self.chase
			self.chase = nil
			local root = rootOf(lost)
			if root then self.noise = root.Position end
			if lost.Parent == Players then event:FireClient(lost, "chase", false); achieve(lost, "L6Escaped") end
			self:say(pick("lost"), true)
		end
		-- dunks
		local feet = self:feet()
		local home = self.info.home
		local allDunked = true
		for player, state in pairs(self.players) do
			local root = rootOf(player)
			if not state.caught and not state.dunked then
				allDunked = false
				if root and flat(root.Position - home).Magnitude <= CONFIG.DunkRadius and math.abs(root.Position.Y - home.Y) < 9
					and flat(feet - home).Magnitude >= safeDistance then
					state.dunked = true
					self.dunks = self:tagged()
					broadcast(self, "dunk", player.DisplayName, self.dunks, self:target())
					achieve(player, "L6HomeFree")
					self.noise = home
					-- the winning tag belongs to the angry line alone
					if self.dunks < self:target() or (self.wins or 0) + 1 < CONFIG.RoundsToWin then self:say(pick("dunk"), true) end
				end
			end
		end
		-- Studio only: setting Level6DevTag on the map model scores one tag, to play the finale through in a test
		if RunService:IsStudio() and self.info.model:GetAttribute("Level6DevTag") then
			self.info.model:SetAttribute("Level6DevTag", nil)
			for _, state in pairs(self.players) do
				if not state.caught and not state.escaped then state.dunked = true end
			end
			self.dunks = self:tagged()
			broadcast(self, "dunk", "TEST", self.dunks, self:target())
		end
		-- a player caught after tagging no longer counts either way: the tally is always of the living
		self.dunks = self:tagged()
		if self:living() > 0 and self.dunks >= self:target() then
			self.wins = (self.wins or 0) + 1
			self.info.model:SetAttribute("Level6Wins", self.wins)
			broadcast(self, "roundwon", self.wins, CONFIG.RoundsToWin)
			result = self.wins >= CONFIG.RoundsToWin and "won" or "alldunked"
			break
		end
		local left = math.max(0, math.ceil(deadline - clock()))
		if left ~= lastTimer then lastTimer = left; broadcast(self, "timer", left) end
		if left <= 0 then result = "timeup"; break end
	end
	if self.chase and self.chase.Parent == Players then event:FireClient(self.chase, "chase", false) end
	self.chase = nil
	if self.phase == "seek" then self.phase = "between" end
	self.interrupt = true
	pcall(task.cancel, brain)
	return result
end

-- ARENA_20261006 (owner): the third touch starts a countdown on the post. For a minute the Counter hunts; then
-- the post sinks into the floor, green light comes up out of the hole, and the way out is down it: the shaft, the
-- slide under the court, the room with the EXIT door. The model is put back as it was when the session ends.
local function finaleParts(model)
	local post, dial, lid = model:FindFirstChild("Finale_Post"), model:FindFirstChild("Finale_Dial"), model:FindFirstChild("Finale_Lid")
	local home = model:GetAttribute("HomePosition")
	if not (post and dial and lid and typeof(home) == "Vector3") then return nil end
	local marks = {}
	for _, part in ipairs(dial:GetChildren()) do
		if part:IsA("BasePart") then
			local d = part.Position - home
			-- clockwise from the top of the dial (north), seen from above
			marks[#marks + 1] = {part = part, angle = math.atan2(d.X, -d.Z) % (2 * math.pi), color = part.Color, material = part.Material}
		end
	end
	table.sort(marks, function(a, b) return a.angle < b.angle end)
	local moving, tallest = {}, nil
	for _, folder in ipairs({post, lid}) do
		for _, part in ipairs(folder:GetChildren()) do
			if part:IsA("BasePart") then
				moving[#moving + 1] = {part = part, frame = part.CFrame, collide = part.CanCollide, lid = folder == lid}
				if folder == post and (not tallest or part.Size.X > tallest.Size.X) then tallest = part end
			end
		end
	end
	return {marks = marks, moving = moving, post = tallest, glow = model:FindFirstChild("Finale_Glow")}
end

local function finaleReset(model)
	local f = finaleParts(model)
	if not f then return end
	local gui = f.post and f.post:FindFirstChild("L6Countdown")
	if gui then gui:Destroy() end
	if model:GetAttribute("Level6FinaleStarted") then
		-- the build's own values travel with the parts as attributes, so a later session finds them too
		for _, mark in ipairs(f.marks) do
			local c, m = mark.part:GetAttribute("RestColor"), mark.part:GetAttribute("RestMaterial")
			if c then mark.part.Color = c end
			if m then mark.part.Material = Enum.Material[m] end
		end
		for _, item in ipairs(f.moving) do
			local frame = item.part:GetAttribute("RestFrame")
			if frame then item.part.CFrame = frame end
			item.part.CanCollide = item.part:GetAttribute("RestCollide") ~= false
		end
	end
	if f.glow then
		for _, light in ipairs(f.glow:GetDescendants()) do
			if light:IsA("Light") then light.Enabled, light.Brightness = false, 0 end
		end
	end
	model:SetAttribute("Level6FinaleStarted", nil)
	model:SetAttribute("Level6FinaleEndsAt", nil)
	model:SetAttribute("Level6HatchOpen", nil)
end

function Session:finalePhase()
	self.phase = "escape"
	local model = self.info.model
	local f = finaleParts(model)
	local total = CONFIG.FinaleSeconds
	broadcast(self, "won", self.dunks, total)
	model:SetAttribute("Level6Enraged", true)             -- the client turns every light deep red
	self:say(pick("angry"), true)
	local label = nil
	if f then
		for _, mark in ipairs(f.marks) do
			mark.part:SetAttribute("RestColor", mark.color)
			mark.part:SetAttribute("RestMaterial", mark.material.Name)
			mark.part.Material, mark.part.Color = Enum.Material.Neon, Color3.fromRGB(255, 246, 220)
		end
		for _, item in ipairs(f.moving) do
			item.part:SetAttribute("RestFrame", item.frame)
			item.part:SetAttribute("RestCollide", item.collide)
		end
		model:SetAttribute("Level6FinaleStarted", true)
		if f.post then
			local gui = Instance.new("BillboardGui")
			gui.Name, gui.Adornee = "L6Countdown", f.post
			gui.Size, gui.StudsOffsetWorldSpace = UDim2.fromScale(11, 4.4), Vector3.new(0, 7.4, 0)
			gui.LightInfluence, gui.MaxDistance, gui.AlwaysOnTop, gui.Brightness = 0, 700, false, 2
			label = Instance.new("TextLabel")
			label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
			label.Font, label.TextScaled, label.TextColor3 = Enum.Font.Arcade, true, Color3.fromRGB(255, 250, 235)
			label.TextStrokeTransparency, label.TextStrokeColor3 = 0.35, Color3.fromRGB(120, 10, 5)
			label.Text = string.format("%d:%02d", total // 60, total % 60)
			label.Parent = gui
			gui.Parent = f.post
		end
	end
	model:SetAttribute("Level6FinaleEndsAt", workspace:GetServerTimeNow() + total)
	local deadline = clock() + total
	local open, lastShown = false, nil
	local exit = self.info.exit
	self.pauseUntil = nil
	local brain = task.spawn(function()
		while self.active and self.phase == "escape" do
			-- frenzy: it goes for whoever is nearest, over the graph, and knows where they are
			self.interrupt = false
			if self.pauseUntil and clock() < self.pauseUntil then
				self.anim.speed = 0
				task.wait(0.1)
				continue
			end
			local nearest, nd = nil, math.huge
			for player, state in pairs(self.players) do
				local root = rootOf(player)
				if root and not state.caught and not state.escaped and state.entered and root.Position.Y > self.info.floorY - 3 then
					local d = (root.Position - self.root.Position).Magnitude
					if d < nd then nearest, nd = root, d end
				end
			end
			local route = nearest and self.nav and self:routeTo(nearest.Position - Vector3.new(0, 3, 0), true)
			if route then
				local started = clock()
				task.delay(0.4, function() if clock() - started >= 0.35 then self.interrupt = true end end)
				self:travel(clipRoute(route, 6), CONFIG.FinaleChaseSpeed, "escape")
			else
				self:pose("Idle")
				task.wait(0.3)
			end
		end
	end)
	while self.active and self.phase == "escape" do
		task.wait(0.15)
		if self:count() == 0 then break end
		if self.wipedAt then
			if not self:wipeWindow() then break end
		elseif self:living() == 0 then
			break
		end
		local left = math.max(0, math.ceil(deadline - clock()))
		if f and left ~= lastShown then
			lastShown = left
			if label then label.Text = string.format("%d:%02d", left // 60, left % 60) end
			if not open then broadcast(self, "timer", left) end
			local dark = math.floor((total - left) / total * #f.marks + 0.5)
			for i, mark in ipairs(f.marks) do
				if i <= dark and mark.part.Material == Enum.Material.Neon then
					mark.part.Material, mark.part.Color = Enum.Material.SmoothPlastic, Color3.fromRGB(26, 24, 22)
				end
			end
		end
		if left <= 0 and not open then
			open = true
			if f then
				for _, item in ipairs(f.moving) do
					item.part.CanCollide = false
					if item.lid then
						TweenService:Create(item.part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{CFrame = item.frame * CFrame.new(0, -20, 0)}):Play()
					else
						TweenService:Create(item.part, TweenInfo.new(3.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
							{CFrame = item.frame + Vector3.new(0, -18.5, 0)}):Play()
					end
				end
				if f.glow then
					for _, light in ipairs(f.glow:GetDescendants()) do
						if light:IsA("Light") then
							-- the green you see from the galleries: a pool on the court round the hole (Pool, hung unseen
							-- over it), the padded wall of the shaft (Rim), the way down (Down) and the undersides of
							-- the ledges above (Up). Lit at once, then brought up.
							local level = ({Up = 2.5, Rim = 3.2, Down = 3, Pool = 2.2})[light.Name] or 3
							light.Enabled, light.Brightness = true, level * 0.2
							TweenService:Create(light, TweenInfo.new(1.6), {Brightness = level}):Play()
						end
					end
				end
				task.delay(2.2, function()
					local gui = f.post and f.post:FindFirstChild("L6Countdown")
					if gui then gui:Destroy() end
				end)
			end
			model:SetAttribute("Level6HatchOpen", true)
			broadcast(self, "hatch")
			self:say(pick("exit"), true)
		end
		self:perceive()
		-- TAUNT_20261006 (owner): the second everyone still standing is down in the room under the court, it screams
		-- after them from above, and ends on a sweet little laugh. Once.
		if open and not self.taunted then
			local anchors = model:FindFirstChild("Anchors")
			local room = anchors and anchors:FindFirstChild("L6_Anchor_ExitRoom")
			local standing, down = 0, 0
			for player, state in pairs(self.players) do
				local root = rootOf(player)
				if root and room and not state.caught and not state.escaped then
					standing += 1
					local d = root.Position - room.Position
					if math.abs(d.X) <= 16.5 and math.abs(d.Z) <= 13.5 and d.Y > -4.5 and d.Y < 11 then down += 1 end
				end
			end
			if standing > 0 and down == standing then
				self.taunted = true
				broadcast(self, "exittaunt")
			end
		end
		if open then
			for player, state in pairs(self.players) do
				local root = rootOf(player)
				if root and not state.caught and not state.escaped and (root.Position - exit).Magnitude <= CONFIG.ArenaExitRadius then
					state.escaped = true
					player:SetAttribute(CLEARED, true)
					self.escapedCount += 1
					event:FireClient(player, "escaped", player.DisplayName, true); achieve(player, "FirstClearLevel6")
					-- out of the session (it goes on for whoever is still inside) and onto the ending every level has
					self.players[player] = nil
					if lifeWatch[player] then lifeWatch[player]:Disconnect(); lifeWatch[player] = nil end
					-- LEVEL_LEADERBOARDS_20261008: the time of the player who really reached the way out (the fallen get
					-- the same ending further down, but no time)
					do
						local board = game:GetService("ServerStorage"):FindFirstChild("LevelTimeReported")
						if board then board:Fire(player, 6, os.clock() - self.startedAt) end
					end
					sendWin(self, player)
				end
			end
		end
	end
	self.phase = "over"
	pcall(task.cancel, brain)
end

function Session:escapePhase()
	if self.info.arena then return self:finalePhase() end
	self.phase = "escape"
	broadcast(self, "won", self.dunks)
	self.info.model:SetAttribute("Level6Enraged", true)   -- the client turns every light deep red
	self:say(pick("angry"), true)
	local exit = self.info.exit
	local beacon = Instance.new("Part")
	beacon.Name, beacon.Anchored, beacon.CanCollide, beacon.CanQuery, beacon.CanTouch = "ExitBeacon", true, false, false, false
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(0.4, 14, 14)
	beacon.CFrame = CFrame.new(exit.X, self.info.floorY + 0.6, exit.Z) * CFrame.Angles(0, 0, math.rad(90))
	beacon.Color, beacon.Material, beacon.Transparency = Color3.fromRGB(60, 255, 120), Enum.Material.Neon, 0.35
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(80, 255, 130), 40, 3
	light.Parent = beacon
	beacon.Parent = self.info.model
	-- No time limit (owner, 2026-10-04): the level is only cleared by walking out through the exit. The phase lasts
	-- until every player still standing is out or caught; the furious doll is what ends it for someone who waits.
	self.pauseUntil = nil
	local brain = task.spawn(function()
		while self.active and self.phase == "escape" do
			-- frenzy: the child goes straight for whoever is nearest
			self.interrupt = false          -- seekPhase and catch() leave this set, and follow() will not move while it is
			local nearest, nd = nil, math.huge
			for player, state in pairs(self.players) do
				local root = rootOf(player)
				if root and not state.caught then
					local d = (root.Position - self.root.Position).Magnitude
					if d < nd then nearest, nd = root, d end
				end
			end
			if nearest then
				local goal = nearest.Position - Vector3.new(0, 3, 0)
				local close = nd < 30 and math.abs(nearest.Position.Y - self.root.Position.Y) < 5
				local points = self:path(goal)
				if not points and close then points = {self:feet(), goal} end   -- no route on the navmesh: go straight at them
				if points then
					-- only the first stretch, then plan again, so it keeps up with a running player
					local short = {points[1]}
					for i = 2, math.min(#points, 4) do short[#short + 1] = points[i] end
					self:follow(short, CONFIG.EscapeChaseSpeed, "escape")
				else
					self:pose("Idle")
					task.wait(0.25)
				end
			else
				task.wait(0.3)
			end
		end
	end)
	while self.active and self.phase == "escape" do
		task.wait(0.15)
		if self:count() == 0 then break end
		if self.wipedAt then
			if not self:wipeWindow() then break end
		elseif self:living() == 0 then
			break                                   -- the last one standing is out; only watchers are left
		end
		self:perceive()
		for player, state in pairs(self.players) do
			local root = rootOf(player)
			if root and not state.caught and not state.escaped and flat(root.Position - exit).Magnitude <= CONFIG.ExitRadius then
				state.escaped = true
				player:SetAttribute(CLEARED, true)
				event:FireClient(player, "escaped", player.DisplayName, true); achieve(player, "FirstClearLevel6")
				event:FireClient(player, "say", "l6_escaped")
				task.delay(1.5, function()
					if returnHandler and player.Parent == Players and player:GetAttribute(IN_PREVIEW) == true then
						returnHandler(player, "escaped")
					end
					Game.RemovePlayer(player)
				end)
			end
		end
	end
	self.phase = "over"
	pcall(task.cancel, brain)
	beacon:Destroy()
end

-- PARTY_20261004 (owner's easter egg). A hidden button behind one of the counters. Pressed while it is searching
-- (once per session, never during a chase), everything stops for 30 seconds: every living player is stood round
-- the table in the dark party room, the door is shut, a disco ball turns, the eurodance track plays and the
-- Counter breakdances on the table (clips Dance_* from tools/level6_entity/build_dance.py). Then every player
-- and the doll are put back exactly where they were and the search goes on from the same second: `clock()`
-- stood still meanwhile, and the loops that move the doll or look for players wait in `hold`.
local PARTY = {Seconds = 30, Track = "rbxassetid://129281139879903", RoomX = -193,
	Routine = {{"Dance_Toprock", 4}, {"Dance_Windmill", 7}, {"Dance_Headspin", 7}, {"Dance_Freeze", 4}, {"Dance_Windmill", 4}, {"Dance_Finale", 4}},
	Slots = {Vector3.new(12.5, 0, 0), Vector3.new(-12.5, 0, 0), Vector3.new(7, 0, 13), Vector3.new(-7, 0, 13), Vector3.new(7, 0, -13), Vector3.new(-7, 0, -13)},
	Colours = {Color3.fromRGB(255, 64, 176), Color3.fromRGB(70, 230, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(90, 255, 130)}}

function Session:hold()
	while self.partyOn and self.active do task.wait(0.1) end
end

local function partyTable(model)
	local rooms = model:FindFirstChild("PartyRooms")
	local originX = model:GetPivot().Position.X
	local best, bestGap = nil, 6
	for _, d in ipairs(rooms and rooms:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Name == "paper" and d.Size.X > 12 then
			local gap = math.abs(d.Position.X - (math.floor(originX / 1000 + 0.5) * 1000 + PARTY.RoomX))
			if gap < bestGap then best, bestGap = d, gap end
		end
	end
	return best
end

function Session:party(by)
	if not self.active or self.phase ~= "seek" or self.chase or self.partyUsed or self.partyOn or self.wipedAt
		or clock() < (self.killUntil or 0) then return false end
	local model = self.info.model
	-- ARENA_20261006: there is no party room any more. The party is on the court, the Counter dancing beside the post.
	local anchors = model:FindFirstChild("Anchors")
	local stage = self.info.arena and anchors and anchors:FindFirstChild("L6_Anchor_PartyStage") or nil
	local top = not stage and partyTable(model) or nil
	if not stage and not top then return false end
	self.partyUsed, self.partyOn = true, true
	pausedAt = realClock()
	local tableTop = stage and Vector3.new(stage.Position.X, self.info.floorY + 0.95, stage.Position.Z)
		or (top.Position + Vector3.new(0, top.Size.Y / 2, 0))
	local floorY = stage and tableTop.Y or tableTop.Y - 3.6
	local made, dimmed, back = {}, {}, {}
	local saved = {frame = self.root.CFrame, name = self.anim.name, speed = self.anim.speed}
	local function part(name, size, cf, colour, material)
		local item = Instance.new("Part")
		item.Name, item.Size, item.CFrame, item.Color, item.Material = name, size, cf, colour, material
		item.Anchored, item.CanTouch = true, false
		item.Parent = model
		table.insert(made, item)
		return item
	end
	local ok, problem = pcall(function()
		-- the players, round the table and facing it
		local slot = 0
		for player in pairs(self.players) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if root and humanoid.Health > 0 then
				slot += 1
				back[player] = {character = character, frame = character:GetPivot()}
				local at = Vector3.new(tableTop.X, floorY + 3.2, tableTop.Z) + PARTY.Slots[(slot - 1) % #PARTY.Slots + 1]
				root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				character:PivotTo(CFrame.lookAt(at, Vector3.new(tableTop.X, at.Y, tableTop.Z)))
			end
		end
		-- the door, shut
		local door = part("L6PartyDoor", Vector3.new(8.2, 10.6, 1.2),
			CFrame.new(tableTop.X - 0.25, floorY + 5.3, tableTop.Z + 36), Color3.fromRGB(28, 40, 110), Enum.Material.SmoothPlastic)
		if stage then door.Transparency, door.CanCollide = 1, false end      -- the court has no door to shut
		local lock = Instance.new("SurfaceGui")
		lock.Enabled = stage == nil
		lock.Face, lock.CanvasSize, lock.LightInfluence = Enum.NormalId.Front, Vector2.new(400, 520), 0
		local word = Instance.new("TextLabel")
		word.Size, word.BackgroundTransparency, word.Text = UDim2.fromScale(1, 0.3), 1, "LOCKED"
		word.Position, word.Font, word.TextScaled, word.TextColor3 = UDim2.fromScale(0, 0.3), Enum.Font.Arcade, true, PARTY.Colours[1]
		word.Parent = lock
		lock.Parent = door
		-- the room's own lamps down, the disco ball up
		local lights = model:FindFirstChild("Lights")
		for _, d in ipairs(lights and lights:GetDescendants() or {}) do
			if d:IsA("Light") then
				local host = d.Parent
				local at = host and host:IsA("BasePart") and host.Position
				if at and math.abs(at.X - tableTop.X) < 22 and math.abs(at.Z - (tableTop.Z + 6)) < 32 then
					dimmed[d] = d.Brightness
					d.Brightness *= 0.12
				end
			end
		end
		local hang = Vector3.new(tableTop.X, floorY + 14.6, tableTop.Z)
		part("L6DiscoRod", Vector3.new(0.2, 1.6, 0.2), CFrame.new(hang + Vector3.new(0, 1.9, 0)), Color3.fromRGB(20, 20, 24), Enum.Material.Metal).CanCollide = false
		local ball = part("L6DiscoBall", Vector3.new(2.4, 2.4, 2.4), CFrame.new(hang), Color3.fromRGB(210, 214, 226), Enum.Material.Metal)
		ball.Shape, ball.Reflectance, ball.CanCollide, ball.CastShadow = Enum.PartType.Ball, 0.75, false, false
		local glow = Instance.new("PointLight")
		glow.Range, glow.Brightness, glow.Shadows = 26, 0.9, false
		glow.Parent = ball
		local beams = {}
		for i, colour in ipairs(PARTY.Colours) do
			for _, tilt in ipairs({-38, -68}) do
				local holder = Instance.new("Attachment")
				holder.CFrame = CFrame.Angles(0, math.rad(i * 90 + (tilt == -68 and 45 or 0)), 0) * CFrame.Angles(math.rad(tilt), 0, 0)
				holder.Parent = ball
				local spot = Instance.new("SpotLight")
				spot.Face, spot.Angle, spot.Range, spot.Brightness, spot.Color, spot.Shadows = Enum.NormalId.Front, 24, 46, 6, colour, false
				spot.Parent = holder
				table.insert(beams, spot)
			end
		end
		local music = Instance.new("Sound")
		music.Name, music.SoundId, music.Volume, music.Looped = "L6PartyMusic", PARTY.Track, 1.4, true
		music.RollOffMode, music.RollOffMinDistance, music.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 40, 160
		music.Parent = ball
		music:Play()
		workspace:SetAttribute("Level6Party", true)
		broadcast(self, "party", true, by and by.DisplayName or nil)
		for player in pairs(back) do achieve(player, "L6Party") end
		-- the Counter, on the table
		self:place(tableTop, Vector3.new(0, 0, 1))
		local began = realClock()
		local spin = RunService.Heartbeat:Connect(function()
			local t = realClock() - began
			ball.CFrame = CFrame.new(hang) * CFrame.Angles(0, t * 1.9, 0)
			local beat = t * 142 / 60
			glow.Color = PARTY.Colours[math.floor(beat / 2) % #PARTY.Colours + 1]
		end)
		for _, step in ipairs(PARTY.Routine) do
			if not self.active then break end
			self.anim.name, self.anim.speed = step[1], 0
			self.anim.serial += 1
			local untilT = realClock() + step[2]
			while self.active and realClock() < untilT do task.wait(0.1) end
		end
		spin:Disconnect()
		music:Stop()
	end)
	if not ok then warn("[Level6] party: " .. tostring(problem)) end
	-- everything back where it was
	for _, item in ipairs(made) do item:Destroy() end
	for light, brightness in pairs(dimmed) do
		if light.Parent then light.Brightness = brightness end
	end
	for player, was in pairs(back) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if self.players[player] and character == was.character and humanoid and humanoid.Health > 0 and humanoid.RootPart then
			humanoid.RootPart.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(was.frame)
		end
	end
	self.navLoose = true           -- it was lifted off the graph for the dance
	if self.root.Parent then
		self.root.CFrame = saved.frame
		self.anim.name, self.anim.speed = saved.name, saved.speed
		self.anim.serial += 1
	end
	workspace:SetAttribute("Level6Party", nil)
	broadcast(self, "party", false)
	pausedTotal += realClock() - pausedAt
	pausedAt = nil
	self.partyOn = false
	return true
end

-- The button: small, red, on the floor behind a counter where a hider would crouch.
local function ensurePartyButton(info)
	local model = info.model
	if model:FindFirstChild("L6PartyButton") then return end
	local anchors = model:FindFirstChild("Anchors")
	local spot = anchors and (anchors:FindFirstChild("L6_Anchor_PartyButton") or anchors:FindFirstChild("L6_Hide_counter_05")
		or anchors:FindFirstChild("L6_Hide_counter_01"))
	if not spot then return end
	local base = Instance.new("Part")
	base.Name = "L6PartyButton"
	base.Size, base.Color, base.Material = Vector3.new(0.9, 0.25, 0.9), Color3.fromRGB(18, 18, 22), Enum.Material.Metal
	base.Anchored, base.CanCollide, base.CanTouch = true, false, false
	base.CFrame = CFrame.new(spot.Position.X, info.floorY + 0.2, spot.Position.Z)
	local hit = workspace:Raycast(spot.Position + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0))
	if hit then base.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.12, 0)) end
	local cap = Instance.new("Part")
	cap.Name, cap.Shape = "Cap", Enum.PartType.Cylinder
	cap.Size, cap.Color, cap.Material = Vector3.new(0.22, 0.6, 0.6), Color3.fromRGB(210, 30, 40), Enum.Material.SmoothPlastic
	cap.Anchored, cap.CanCollide, cap.CanTouch = true, false, false
	cap.CFrame = base.CFrame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	cap.Parent = base
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "PRESS", "?"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0.6, 7, false
	prompt.Parent = base
	prompt.Triggered:Connect(function(player)
		local s = session
		if s and s.active and s.players[player] then
			task.spawn(function() s:party(player) end)
		end
	end)
	base.Parent = model
end

function Session:run()
	if self.info.arena then self:arrivalPhase() end
	while self.active do
		self:countPhase()
		if not self.active or self:count() == 0 then break end
		local result = self:seekPhase()
		if result == "won" then self:escapePhase(); break end
		if result == "wiped" then
			if self:wipeWindow() then continue end   -- somebody re-entered: it counts again
			break
		end
		if result == "empty" or result == "lost" or self.phase == "over" then break end
		broadcast(self, "roundover", result)
		-- let whatever it is saying finish; "I'll count again" only when the time simply ran out
		if clock() < self.voiceUntil then task.wait(math.min(self.voiceUntil - clock(), 4)) end
		if result == "timeup" then
			local seconds = self:say("l6_round_again", true)
			task.wait((seconds or 2) + 0.3)
		end
	end
	-- a kill cam is looking at the doll: it stays until that is over
	while clock() < (self.killUntil or 0) do task.wait(0.1) end
	self:finish()
end

function Session:finish()
	self.active = false
	self.phase = "over"
	for player in pairs(self.players) do
		if player.Parent == Players then
			roundStatus:FireClient(player, "partydownclear")
			if self.info.arena and self.escapedCount > 0 then
				sendWin(self, player)          -- the party got out: whoever fell sees the same ending, as in every level
			elseif returnHandler and player:GetAttribute(IN_PREVIEW) == true then
				task.spawn(returnHandler, player, "over")
			end
			event:FireClient(player, "left")
		end
	end
	table.clear(self.players)
	if self.heartbeat then self.heartbeat:Disconnect() end
	if self.child then self.child:Destroy() end
	self.info.model:SetAttribute("Level6Enraged", nil)
	if self.info.arena then pcall(finaleReset, self.info.model) end
	if session == self then session = nil end
end

-- ---------------------------------------------------------------------------------------
-- public API
-- Level 6 is played like every other round: locked first person. GameManager only does this for
-- its own rounds, so the level sets it on entry and hands the lobby camera back on the way out.
local cameraWatch = {}
local function setRoundCamera(player, inLevel)
	if player.Parent ~= Players then return end
	if inLevel then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance, player.CameraMaxZoomDistance = 0.5, 0.5
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 18 -- max first: a minimum above the old maximum is refused
		player.CameraMinZoomDistance = 8
	end
end
local function ownRoundCamera(player)
	setRoundCamera(player, true)
	if cameraWatch[player] then return end
	local function release()
		for _, connection in ipairs(cameraWatch[player] or {}) do connection:Disconnect() end
		cameraWatch[player] = nil
	end
	cameraWatch[player] = {
		player:GetAttributeChangedSignal(IN_PREVIEW):Connect(function()
			if player:GetAttribute(IN_PREVIEW) ~= true then
				setRoundCamera(player, false)
				release()
			end
		end),
		-- A respawn inside the level runs GameManager's onCharacter, which resets to the lobby camera.
		player.CharacterAdded:Connect(function()
			task.defer(function()
				if player:GetAttribute(IN_PREVIEW) == true then setRoundCamera(player, true) end
			end)
		end),
		player.AncestryChanged:Connect(function()
			if player.Parent ~= Players then release() end
		end),
	}
end

-- Deaths are read off the humanoid, so a reset or a fall counts the same as the doll's catch.
-- (lifeWatch is declared at the top: the finale uses it too)
local function watchLife(player)
	if lifeWatch[player] then return end
	local function hook(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then return end
		humanoid.Died:Connect(function()
			local s = session
			if s and s.players[player] and player.Character == character then s:playerDied(player) end
		end)
	end
	lifeWatch[player] = player.CharacterAdded:Connect(function(character) task.spawn(hook, character) end)
	if player.Character then task.spawn(hook, player.Character) end
end

do
	local old = ServerStorage:FindFirstChild("Level6Reentry")
	if old then old:Destroy() end
	local reentry = Instance.new("BindableFunction")
	reentry.Name = "Level6Reentry"
	reentry.OnInvoke = function(player, free)
		-- Level 5 is a live level too and its players carry the same marker, so GameManager sends them here:
		-- they go on to their own level's re-entry (the small room at the end of its last corridor).
		if typeof(player) == "Instance" and player:IsA("Player") and player:GetAttribute("Level5VoidRound") == true then
			local theirs = ServerStorage:FindFirstChild("Level5Reentry")
			if theirs and theirs:IsA("BindableFunction") then return theirs:Invoke(player, free) end
			return false, "UNAVAILABLE"
		end
		local s = session
		if not s or typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "UNAVAILABLE" end
		if free == true then
			local ok, DevAccess = pcall(function() return require(ReplicatedStorage:WaitForChild("DevAccess", 5)) end)
			if not ok or not DevAccess.IsAllowed(player) then return false, "UNAVAILABLE" end
		end
		if s:reenter(player, free == true) then return true end
		return false, "UNAVAILABLE"
	end
	reentry.Parent = ServerStorage
end

function Game.AddPlayer(player)
	local info = map()
	if not info then return false, "MAP_NOT_READY" end
	ownRoundCamera(player)
	watchLife(player)
	player:SetAttribute("ZyntraReentryUsed", false)
	if not CONFIG.EntityEnabled then
		event:FireClient(player, "paused")
		return true
	end
	ensurePartyButton(info)
	if not session or not session.active then
		if info.arena then pcall(finaleReset, info.model) end     -- whatever a session that broke off left behind
		session = newSession(info)
		session.players[player] = {dunked = false}
		session.partySize += 1
		task.spawn(function() session:run() end)
	else
		session.players[player] = {dunked = false}
		session.partySize += 1
	end
	winners[player] = nil
	local s = session
	event:FireClient(player, "joined", s.round, s.dunks, s:target(), s.phase)
	return true
end

function Game.RemovePlayer(player)
	local s = session
	if not s or not s.players[player] then return end
	s.players[player] = nil
	if lifeWatch[player] then lifeWatch[player]:Disconnect(); lifeWatch[player] = nil end
	if player.Parent == Players then event:FireClient(player, "left") end
	if s:count() == 0 then
		s.active = false
		s.interrupt = true
	elseif s:living() == 0 and not s.wipedAt and s.active then
		-- the last one standing LEFT rather than fell: the watchers still get their window, with no name on it
		s.wipedAt = clock()
		s.interrupt = true
		for other in pairs(s.players) do
			if other.Parent == Players then roundStatus:FireClient(other, "partydown", CONFIG.PartyDownSeconds, nil, DEATH_CAUSE) end
		end
	end
end

function Game.State()
	local s = session
	if not s then return {phase = arenaSlides.busy and "preparing" or "idle"} end
	local list = {}
	for player, state in pairs(s.players) do
		list[#list + 1] = {name = player.Name, caught = state.caught == true, dunked = state.dunked == true}
	end
	return {phase = s.phase, round = s.round, dunks = s.dunks, target = s:target(), players = list,
		child = s.root and s.root.Position, chasing = s.chase and s.chase.Name or nil}
end

Players.PlayerRemoving:Connect(function(player) Game.RemovePlayer(player) end)

-- ---------------------------------------------------------------------------------------
-- The Level 6 queue bay in the lobby is dressed like the level: the Playland sign, the rules, a playhouse,
-- soft blocks, ball bags and loose balls. Added to the bay, nothing of the lobby is moved or removed; the
-- lobby is built at run time, so this waits for it (and dresses it again if the lobby is rebuilt).
local function dressLobbyBay(lobby)
	local pads = lobby:FindFirstChild("PreviewQueuePads")
	local bay = pads and pads:FindFirstChild("QueueBay_Level6")
	local floor = bay and bay:FindFirstChild("ChamberFloor")
	local signs = lobby:FindFirstChild("LevelGateSigns")
	local header = signs and signs:FindFirstChild("LEVEL 6 Door Header")
	if not floor or not header or bay:FindFirstChild("Level6BayDressing") then return end
	local folder = Instance.new("Folder")
	folder.Name = "Level6BayDressing"
	local top = floor.Position.Y + math.min(floor.Size.X, floor.Size.Y, floor.Size.Z) / 2
	local C = Vector3.new(floor.Position.X, top, floor.Position.Z)
	local f = Vector3.new(C.X - header.Position.X, 0, C.Z - header.Position.Z).Unit   -- from the door into the bay
	local r = Vector3.new(-f.Z, 0, f.X)
	local kit = ReplicatedStorage:FindFirstChild("Level6PropKit")
	local function at(a, b, y) return C + f * a + r * b + Vector3.new(0, y or 0, 0) end
	local function face(pos, yaw) return CFrame.lookAt(pos, pos - f) * CFrame.Angles(0, math.rad(yaw or 0), 0) end
	local function prop(name, a, b, yaw, size)
		local template = kit and kit:FindFirstChild(name)
		if not template then return end
		local m = template:Clone()
		m.Size = m.Size * (size / math.max(m.Size.X, m.Size.Y, m.Size.Z))
		m.Anchored, m.CanCollide, m.CanTouch = true, true, false
		m.CFrame = face(at(a, b, m.Size.Y / 2), (yaw or 0) + 180)
		m.Parent = folder
	end
	local function block(a, b, size, color, yaw)
		local p = Instance.new("Part")
		p.Anchored, p.Size, p.Color, p.Material = true, size, color, Enum.Material.SmoothPlastic
		p.CFrame = face(at(a, b, size.Y / 2), yaw)
		for _, side in ipairs({Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top}) do
			local tx = Instance.new("Texture")
			tx.Texture, tx.Face, tx.StudsPerTileU, tx.StudsPerTileV, tx.Color3 = "rbxassetid://107384724475398", side, 7, 7, color
			tx.Parent = p
		end
		p.Parent = folder
	end
	local function ball(a, b, color)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored, p.CanCollide, p.Size, p.Color, p.Material = true, false, Vector3.one * 1.2, color, Enum.Material.SmoothPlastic
		p.Position = at(a, b, 0.6)
		p.Parent = folder
	end
	local function board(a, b, y, w, h, image)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.Size, p.Color = true, false, Vector3.new(w, h, 0.25), Color3.fromRGB(30, 30, 30)
		p.CFrame = face(at(a, b, y), 0)
		local gui = Instance.new("SurfaceGui")
		gui.Face, gui.SizingMode, gui.PixelsPerStud, gui.LightInfluence = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 40, 1
		local img = Instance.new("ImageLabel")
		img.Size, img.BackgroundTransparency, img.Image = UDim2.fromScale(1, 1), 1, image
		img.Parent = gui
		gui.Parent = p
		p.Parent = folder
	end
	local RED, YEL, BLU, GRN = Color3.fromRGB(190, 40, 35), Color3.fromRGB(235, 175, 25), Color3.fromRGB(35, 70, 190), Color3.fromRGB(45, 150, 60)
	board(25.6, 0, 10.5, 18, 6, "rbxassetid://134636294375228")      -- FUN FACTORY PLAYLAND on the back wall
	board(22.5, -14, 7.5, 5, 7.5, "rbxassetid://94808318000202")     -- play rules
	board(22.5, 14, 7.5, 6, 6, "rbxassetid://97061078157196")        -- home base
	prop("playhouse", 21, 0, 0, 9)
	prop("fake_plant", -21, -8.5, 30, 7)
	prop("fake_plant", -21, 8.5, 200, 7)
	prop("ball_bag", 17, -19.5, 40, 6)
	prop("ball_bag", 17, 19.5, 150, 6.5)
	block(20, -9, Vector3.new(4, 3, 4), RED, 15)
	block(20, -9.2, Vector3.new(3, 6, 3), BLU, 40)
	block(20, 9, Vector3.new(5, 3, 4), YEL, -20)
	block(16.5, 11, Vector3.new(3, 3, 3), GRN, 30)
	local cols = {RED, YEL, BLU, GRN}
	for i, pos in ipairs({{-14, -3}, {-6, 2.5}, {2, -1.5}, {9, 3}, {14, -2}, {23, -5}, {24, 5}, {-17, 4}, {12, -23}, {12, 23},
		{-12, 24}, {-12, -24}, {0, 0.5}, {19, -15}}) do
		ball(pos[1], pos[2], cols[i % 4 + 1])
	end
	folder.Parent = bay
end
task.spawn(function()
	while true do
		local lobby = workspace:FindFirstChild("LobbyReimaginedPreview")
		if lobby and lobby:GetAttribute("Ready") == true then
			local ok, err = pcall(dressLobbyBay, lobby)
			if not ok then warn("[Level6] lobby bay dressing: " .. tostring(err)) end
		end
		task.wait(5)
	end
end)

-- ARENA_20261006: the slide under the post is two moulded meshes that are not assets. Roblox's in-session upload
-- (AssetService:CreateAssetAsync) answered "not available yet" when they were made, so their data is kept in
-- ServerStorage.Level6ArenaSlideSource and they are built once per server, the way the Counter's own mesh is.
-- What you ride is the unseen trough the import made; these are only what you see. A mesh of the same name that
-- already stands in the level (an uploaded asset placed by the import) is left alone.
function arenaSlides.build()
	local model = workspace:FindFirstChild(MODEL_NAME)
	local source = ServerStorage:FindFirstChild("Level6ArenaSlideSource")
	local slides = model and model:FindFirstChild("Slides")
	local origin = model and model:GetAttribute("Origin")
	if arenaSlides.busy or not (source and slides and typeof(origin) == "Vector3") then return false end
	arenaSlides.busy = true
	local missing = 0
	for _, item in ipairs(source:GetChildren()) do
		if model.Parent ~= workspace then arenaSlides.busy = false; return false end
		if not slides:FindFirstChild(item.Name) then
			local ok, why = pcall(function()
				local text = {}
				for i = 1, item:GetAttribute("Parts") do
					text[i] = item:FindFirstChild(string.format("Part_%02d", i)).Value
				end
				local data = HttpService:JSONDecode(table.concat(text))
				local em = assert(AssetService:CreateEditableMesh(), "no EditableMesh budget")
				local V, N, C, T = data.verts, data.normals, data.colours, data.tris
				local vid, nid, cid = {}, {}, {}
				for i = 1, #V, 3 do
					vid[#vid + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]) / 1000)
					nid[#nid + 1] = em:AddNormal(Vector3.new(N[i], N[i + 1], N[i + 2]) / 1000)
					cid[#cid + 1] = em:AddColor(Color3.fromRGB(C[i], C[i + 1], C[i + 2]), 1)
				end
				for i = 1, #T, 3 do
					local a, b, c = T[i] + 1, T[i + 1] + 1, T[i + 2] + 1
					local face = em:AddTriangle(vid[a], vid[b], vid[c])
					em:SetFaceNormals(face, {nid[a], nid[b], nid[c]})
					em:SetFaceColors(face, {cid[a], cid[b], cid[c]})
					if i % 6000 == 1 then task.wait() end
				end
				local baked, result, content = pcall(AssetService.CreateDataModelContentAsync, AssetService, Content.fromObject(em))
				em:Destroy()
				if not baked or result ~= Enum.CreateContentResult.Success then error("bake: " .. tostring(result)) end
				local part = AssetService:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box})
				part.Name = item.Name
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
				-- moulded plastic: the colour, its highlights and its dirt are painted into the mesh's vertex colours
				part.Material, part.Reflectance, part.Color = Enum.Material.SmoothPlastic, 0.06, Color3.new(1, 1, 1)
				-- PBR_20261006: the scuffed moulded-plastic skin the other slides wear (tools/level6_playground/pbr). The
				-- vertex colours show through it; if that variant is not in the place this is plain plastic, as before
				part.MaterialVariant = "L6 Slide Plastic"
				part.CFrame = CFrame.new(origin + item:GetAttribute("Centre"))
				if model.Parent ~= workspace then part:Destroy(); error("Level 6 was parked during slide bake") end
				part.Parent = slides
			end)
			if not ok then
				missing += 1
				warn("[Level6] slide mesh " .. item.Name .. " was not built: " .. tostring(why))
			end
		end
	end
	arenaSlides.busy = false
	return missing == 0
end
local function prepareSlides(model)
	if arenaSlides.job or not model or model.Name ~= MODEL_NAME or model.Parent ~= workspace then return end
	arenaSlides.job = true
	task.spawn(function()
		local ok, problem = pcall(function()
			for _ = 1, 40 do
				if model.Parent ~= workspace then break end
				if arenaSlides.build() then break end
				task.wait(6)
			end
		end)
		if not ok then warn("[Level6] slide preparation: " .. tostring(problem)) end
		arenaSlides.busy, arenaSlides.job = false, false
	end)
end
workspace.ChildAdded:Connect(prepareSlides)
prepareSlides(workspace:FindFirstChild(MODEL_NAME))

return Game
