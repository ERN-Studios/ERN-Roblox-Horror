-- Level 6 Indoor Playground: hide and seek with the counting child.
--
-- Level6PreviewAccess calls AddPlayer/RemovePlayer as players enter and leave the map.
-- The child is "The Counter", a skinned porcelain doll: its mesh is baked on the server from
-- ServerStorage.Level6CounterSource, its clips and voice lines live in ReplicatedStorage.Level6Counter
-- (pipeline: tools/level6_entity). The server only publishes Anim / AnimSerial / Speed on the model and
-- says which line to speak; the Level 6 Playground Client moves the bones and plays the sound.
-- Each round: the child faces Home Base and counts to 20 out loud; when it finishes it searches
-- the hide spots and chases anyone it sees. While it is away, players score by "dunking" the home
-- post (once per player per round). Enough dunks opens the emergency exit; reaching it clears the
-- level. A caught player is sent back to the lobby; if everyone is caught the party has lost.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

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
	GrabDistance = 2.7,   -- how far in front of its victim it stands for the kill cam: its arms reach 2 studs
	HipHeight = 2.4,   -- root above the soles; replaced by the mesh's own value when the doll is built
	EyeHeight = 2.6,   -- eyes above the root
	SpottedPause = 0.7,
	IntroSilence = 5,  -- seconds of quiet after the players arrive, before the PA chime
}

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
	return {model = model, home = home.Position, exit = exit.Position, spawn = spawn and spawn.Position or home.Position,
		spots = spots, floorY = model:GetPivot().Position.Y}
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

local function newSession(info)
	local s = setmetatable({}, Session)
	s.info = info
	s.players = {}           -- player -> {dunked = bool}
	s.active = true
	s.round = 0
	s.dunks = 0
	s.wins = 0               -- searches in which every living player touched the post
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

function Session:walkTo(pos, speed, phase)
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

function Session:goHome(phase)
	local home = self.info.home
	local stand = home + Vector3.new(0, 0.35 - 3, 4)
	self:walkTo(stand, CONFIG.WalkSpeed * 1.4, phase)
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
	return params
end

function Session:hidden(pos)
	for _, spot in ipairs(self.info.spots) do
		local d = flat(spot - pos).Magnitude
		if d <= CONFIG.HideRadius and math.abs(spot.Y - pos.Y) < 4.5 then return true end
	end
	return false
end

function Session:sees(root, params)
	local eye = self.root.Position + Vector3.new(0, CONFIG.EyeHeight, 0)
	local to = root.Position + Vector3.new(0, 1.5, 0)
	local delta = to - eye
	local dist = delta.Magnitude
	if dist > CONFIG.SightRange then return false, dist end
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if self:hidden(root.Position) and dist > CONFIG.HiddenSpotRange and not (speed > 10 and dist < 25) then
		return false, dist
	end
	local hit = workspace:Raycast(eye, delta, params)
	return hit == nil, dist
end

function Session:perceive()
	local params = self:rayParams()
	local best, bestDist = nil, math.huge
	for player, state in pairs(self.players) do
		local root = rootOf(player)
		if root and not state.caught and clock() >= (state.graceUntil or 0) then
			local seen, dist = self:sees(root, params)
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
	self:pose("Choke")
	self:say(pick("kill"), true)
	-- what the others see: the body is lifted off the floor by the throat and drawn in to its face
	if held then
		local from, started = held.CFrame, os.clock()
		local inward = flat(self.root.Position - held.Position)
		inward = inward.Magnitude > 0.1 and inward.Unit or Vector3.zero
		task.spawn(function()
			while held.Parent and held.Anchored and os.clock() - started < CONFIG.CaughtReturnDelay do
				local t = os.clock() - started
				local lift = math.clamp((t - 0.3) / 1.3, 0, 1)
				local pull = math.clamp((t - 1.6) / 2.8, 0, 1)
				held.CFrame = from + Vector3.new(0, 1.4 * lift * lift * (3 - 2 * lift), 0) + inward * (1.1 * pull * pull * (3 - 2 * pull))
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

function Session:chooseSpot()
	local feet = self:feet()
	local options = {}
	for i, spot in ipairs(self.info.spots) do
		if not self.checked[i] then
			local d = (spot - feet).Magnitude
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
			self:walkTo(at - Vector3.new(0, 3, 0), CONFIG.WalkSpeed * 1.25, "seek")
		else
			local option = self:chooseSpot()
			if clock() > (self.nextSearchLine or 0) then
				self.nextSearchLine = clock() + 9 + math.random() * 8
				self:say(pick("search"))
			end
			local arrived = self:walkTo(option.spot - Vector3.new(0, 0.5, 0), CONFIG.WalkSpeed, "seek")
			self.checked[option.i] = true
			if arrived and self.active and self.phase == "seek" and not self.chase then
				self:pose("Search_Look")
				local untilT = clock() + CONFIG.CheckPause
				while clock() < untilT and not self.chase and self.phase == "seek" do task.wait(0.1) end
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
	local deadline = clock() + CONFIG.SeekSeconds
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
				if root and flat(root.Position - home).Magnitude <= CONFIG.DunkRadius
					and flat(feet - home).Magnitude >= CONFIG.DunkSafeDistance then
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

function Session:escapePhase()
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
	local top = partyTable(model)
	if not top then return false end
	self.partyUsed, self.partyOn = true, true
	pausedAt = realClock()
	local tableTop = top.Position + Vector3.new(0, top.Size.Y / 2, 0)
	local floorY = tableTop.Y - 3.6
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
		local lock = Instance.new("SurfaceGui")
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
	local spot = anchors and (anchors:FindFirstChild("L6_Hide_counter_05") or anchors:FindFirstChild("L6_Hide_counter_01"))
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
			if returnHandler and player:GetAttribute(IN_PREVIEW) == true then
				task.spawn(returnHandler, player, "over")
			end
			event:FireClient(player, "left")
		end
	end
	table.clear(self.players)
	if self.heartbeat then self.heartbeat:Disconnect() end
	if self.child then self.child:Destroy() end
	self.info.model:SetAttribute("Level6Enraged", nil)
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
local lifeWatch = {}
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
		session = newSession(info)
		session.players[player] = {dunked = false}
		task.spawn(function() session:run() end)
	else
		session.players[player] = {dunked = false}
	end
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
	if not s then return {phase = "idle"} end
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


return Game
