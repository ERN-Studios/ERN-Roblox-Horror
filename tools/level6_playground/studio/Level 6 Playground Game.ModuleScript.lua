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
	WalkSpeed = 9, ChaseSpeed = 20, EscapeChaseSpeed = 24,   -- it is furious once the exit opens
	SightRange = 75, CatchDistance = 4.2, HideRadius = 4.5, HiddenSpotRange = 6,
	NoiseSpeed = 18, NoiseRange = 45, LoseSightSeconds = 4, CheckPause = 3.3,   -- CheckPause = the Search_Look clip
	ExitRadius = 11, EscapeSeconds = 45, CaughtReturnDelay = 2.2,
	HipHeight = 2.4,   -- root above the soles; replaced by the mesh's own value when the doll is built
	EyeHeight = 1.8,   -- eyes above the root
	SpottedPause = 0.9,
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
local session = nil

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
}
local lastLine = {}
local function pick(group)
	local list = VOICE[group]
	if group == "angry" then
		local voice = ReplicatedStorage:FindFirstChild("Level6Counter")
		voice = voice and voice:FindFirstChild("Voice")
		if not (voice and voice:FindFirstChild(list[1])) then list = VOICE.exit end
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
	local n = 0
	for _ in pairs(self.players) do n += 1 end
	return CONFIG.TagsToWin        -- the same for any party size: three tags on the post open the exit
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
	if not force and os.clock() < self.voiceUntil then return nil end
	local voice = ReplicatedStorage:FindFirstChild("Level6Counter")
	voice = voice and voice:FindFirstChild("Voice")
	local sound = voice and voice:FindFirstChild(key)
	local seconds = sound and sound:GetAttribute("Seconds") or 2
	self.voiceUntil = os.clock() + seconds + 0.5
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
	local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 6, AgentCanJump = true,
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
		-- unreachable by navmesh: glide straight if it is close, otherwise give up on this goal
			if (pos - self:feet()).Magnitude > 24 then return false end
		points = {self:feet(), pos}
	end
	return self:follow(points, speed, phase)
end

function Session:goHome(phase)
	local home = self.info.home
	local stand = home + Vector3.new(0, 0.35 - 3, 4)
	self:walkTo(stand, CONFIG.WalkSpeed * 1.4, phase)
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
		if root and not state.caught then
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
	self.pauseUntil = os.clock() + 1.6
	self.interrupt = true
	self:pose("Catch")
	self:say(pick("found"), true)
	task.delay(CONFIG.CaughtReturnDelay, function()
		if returnHandler and player.Parent == Players and player:GetAttribute(IN_PREVIEW) == true then
			returnHandler(player, "caught")
		end
		Game.RemovePlayer(player)
	end)
	local left = 0
	for _, s in pairs(self.players) do if not s.caught then left += 1 end end
	if left == 0 then
		broadcast(self, "lost")
		self.phase = "over"
		task.delay(1.8, function() broadcast(self, "say", "l6_win") end)
	elseif self.active then
		task.delay(2.0, function() if self.active then self:say("l6_found_other", true) end end)
	end
end

-- ---------------------------------------------------------------------------------------
-- phases
function Session:countPhase()
	self.phase = "count"
	self.round += 1
	self.checked = {}
	for _, state in pairs(self.players) do state.dunked = false end
	self:goHome("count")
	if not self.active then return end
	self.phase = "count"
	self:pose("Count_Start")
	task.wait(0.8)                        -- hands go up before the first number
	if not self.active or self.phase ~= "count" then return end
	self:pose("Count_Loop")
	local seconds = self:say(CONFIG.CountLines[math.min(self.round, #CONFIG.CountLines)], true) or 20
	broadcast(self, "round", self.round, self.dunks, self:target(), seconds)
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
	while self.active and self.phase == "seek" and os.clock() < deadline do
		self.interrupt = false
		if self.pauseUntil and os.clock() < self.pauseUntil then
			self.anim.speed = 0             -- holding a Spotted or Catch pose
			task.wait(0.1)
		elseif self.chase then
			local player = self.chase
			local root = rootOf(player)
			if not root or not self.players[player] or self.players[player].caught then
				self.chase = nil
			else
				if os.clock() > (self.nextChaseLine or 0) then
					self.nextChaseLine = os.clock() + 6 + math.random() * 4
					self:say(pick("chase"))
				end
				local target = root.Position - Vector3.new(0, 3, 0)
				local direct = (target - self:feet()).Magnitude < 28 and os.clock() - (self.lastSeen or 0) < 0.4
				local points = direct and {self:feet(), target} or self:path(target)
				if points then
					-- re-plan often while chasing; only the first stretch of the route is used
					local short = {points[1]}
					for i = 2, math.min(#points, 5) do short[#short + 1] = points[i] end
					local started = os.clock()
					self.interrupt = false
					task.delay(0.6, function() if os.clock() - started >= 0.55 then self.interrupt = true end end)
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
			if os.clock() > (self.nextSearchLine or 0) then
				self.nextSearchLine = os.clock() + 9 + math.random() * 8
				self:say(pick("search"))
			end
			local arrived = self:walkTo(option.spot - Vector3.new(0, 0.5, 0), CONFIG.WalkSpeed, "seek")
			self.checked[option.i] = true
			if arrived and self.active and self.phase == "seek" and not self.chase then
				self:pose("Search_Look")
				local untilT = os.clock() + CONFIG.CheckPause
				while os.clock() < untilT and not self.chase and self.phase == "seek" do task.wait(0.1) end
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
	local deadline = os.clock() + CONFIG.SeekSeconds
	local result = "timeup"
	local brain = task.spawn(function() self:seekBrain(deadline) end)
	local lastTimer = -1
	while self.active and self.phase == "seek" do
		task.wait(0.15)
		if self:count() == 0 then result = "empty"; break end
		local seen = self:perceive()
		if self.phase ~= "seek" then result = "lost"; break end
		if seen then
			if self.chase ~= seen then
				local first = self.chase == nil
				self.chase = seen
				self.interrupt = true
				event:FireClient(seen, "chase", true)
				if first and not (self.pauseUntil and os.clock() < self.pauseUntil) then
					-- it stops dead, points and says so before it runs: the player's head start
					self.pauseUntil = os.clock() + CONFIG.SpottedPause
					self:pose("Spotted")
					local feet = self:feet()
					local to = rootOf(seen)
					if to then self:place(feet, flat(to.Position - feet)) end
					self:say(pick("spot"), true)
					self.nextChaseLine = os.clock() + 4
				end
			end
			self.lastSeen = os.clock()
		elseif self.chase and os.clock() - (self.lastSeen or 0) > CONFIG.LoseSightSeconds then
			local lost = self.chase
			self.chase = nil
			local root = rootOf(lost)
			if root then self.noise = root.Position end
			if lost.Parent == Players then event:FireClient(lost, "chase", false) end
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
					self.dunks += 1
					broadcast(self, "dunk", player.DisplayName, self.dunks, self:target())
					self.noise = home
					self:say(pick("dunk"), true)
				end
			end
		end
		if self.dunks >= self:target() then result = "won"; break end
		if allDunked then result = "alldunked"; break end
		local left = math.max(0, math.ceil(deadline - os.clock()))
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
	local deadline = os.clock() + CONFIG.EscapeSeconds
	local brain = task.spawn(function()
		while self.active and self.phase == "escape" do
			-- frenzy: the child goes straight for whoever is nearest
			local nearest, nd = nil, math.huge
			for player, state in pairs(self.players) do
				local root = rootOf(player)
				if root and not state.caught then
					local d = (root.Position - self.root.Position).Magnitude
					if d < nd then nearest, nd = root, d end
				end
			end
			if nearest then
				local points = self:path(nearest.Position - Vector3.new(0, 3, 0))
				if points then
					local short = {points[1]}
					for i = 2, math.min(#points, 5) do short[#short + 1] = points[i] end
					self:follow(short, CONFIG.EscapeChaseSpeed, "escape")
				else
					task.wait(0.3)
				end
			else
				task.wait(0.3)
			end
		end
	end)
	while self.active and self.phase == "escape" and os.clock() < deadline do
		task.wait(0.15)
		if self:count() == 0 then break end
		self:perceive()
		for player, state in pairs(self.players) do
			local root = rootOf(player)
			if root and not state.caught and not state.escaped and flat(root.Position - exit).Magnitude <= CONFIG.ExitRadius then
				state.escaped = true
				player:SetAttribute(CLEARED, true)
				event:FireClient(player, "escaped", player.DisplayName, true)
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
	-- anyone still inside when the exit window closes made it too: the dunks were the real test
	for player, state in pairs(self.players) do
		if not state.caught and not state.escaped and player.Parent == Players then
			state.escaped = true
			player:SetAttribute(CLEARED, true)
			event:FireClient(player, "escaped", player.DisplayName, true)
			if returnHandler and player:GetAttribute(IN_PREVIEW) == true then returnHandler(player, "escaped") end
		end
	end
	self.phase = "over"
	pcall(task.cancel, brain)
	beacon:Destroy()
end

function Session:run()
	while self.active do
		self:countPhase()
		if not self.active or self:count() == 0 then break end
		local result = self:seekPhase()
		if result == "won" then self:escapePhase(); break end
		if result == "empty" or result == "lost" or self.phase == "over" then break end
		broadcast(self, "roundover", result)
		self:say("l6_round_again", true)
	end
	self:finish()
end

function Session:finish()
	self.active = false
	self.phase = "over"
	if self.heartbeat then self.heartbeat:Disconnect() end
	if self.child then self.child:Destroy() end
	self.info.model:SetAttribute("Level6Enraged", nil)
	if session == self then session = nil end
end

-- ---------------------------------------------------------------------------------------
-- public API
function Game.AddPlayer(player)
	local info = map()
	if not info then return false, "MAP_NOT_READY" end
	if not CONFIG.EntityEnabled then
		event:FireClient(player, "paused")
		return true
	end
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
	if player.Parent == Players then event:FireClient(player, "left") end
	if s:count() == 0 then
		s.active = false
		s.interrupt = true
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

return Game
