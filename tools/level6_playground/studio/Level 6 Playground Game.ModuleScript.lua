-- Level 6 Indoor Playground: hide and seek with the counting child.
--
-- Level6PreviewAccess calls AddPlayer/RemovePlayer as players enter and leave the map.
-- Each round: the child faces Home Base and counts to 20 out loud; when it finishes it searches
-- the hide spots and chases anyone it sees. While it is away, players score by "dunking" the home
-- post (once per player per round). Enough dunks opens the emergency exit; reaching it clears the
-- level. A caught player is sent back to the lobby; if everyone is caught the party has lost.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MODEL_NAME = "Level 6 Indoor Playground"
local IN_PREVIEW = "Level6PlaygroundPreview"
local CLEARED = "Level6PlaygroundCleared"

local CONFIG = {
	-- Paused 2026-10-03 on the owner's request: with this false nobody counts, seeks or chases and the
	-- map is a free-roam preview. Set it back to true to bring the hide-and-seek round back.
	EntityEnabled = false,
	CountTo = 20,
	CountSeconds = {20, 16, 13, 10},  -- per round; the last value repeats
	SeekSeconds = 75,
	DunksPerPlayer = 2, MinDunks = 3, MaxDunks = 8,
	DunkRadius = 7, DunkSafeDistance = 22,
	WalkSpeed = 13, ChaseSpeed = 21, EscapeChaseSpeed = 18,
	SightRange = 75, CatchDistance = 4.2, HideRadius = 4.5, HiddenSpotRange = 6,
	NoiseSpeed = 18, NoiseRange = 45, LoseSightSeconds = 4, CheckPause = 1.2,
	ExitRadius = 11, EscapeSeconds = 45, CaughtReturnDelay = 2.2,
	HipHeight = 3.1,
	VoiceLeadSeconds = 0.6,
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
local SKIN = Color3.fromRGB(205, 190, 178)
local function newPart(model, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
	p.Anchored = false
	if shape then p.Shape = shape end
	p.Parent = model
	return p
end

local function joint(part0, part1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Part0, m.Part1, m.C0, m.C1 = part0, part1, c0, c1 or CFrame.new()
	m.Parent = part0
	return m
end

local function buildChild()
	local model = Instance.new("Model")
	model.Name = "Level 6 Counting Child"
	local root = Instance.new("Part")
	root.Name, root.Size, root.Transparency = "Root", Vector3.new(1.5, 1.5, 1.5), 1
	root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = true, false, false, false
	root.Parent = model
	model.PrimaryPart = root

	local torso = newPart(model, "Torso", Vector3.new(2.1, 2.5, 1.3), Color3.fromRGB(240, 200, 70))
	local stripe = newPart(model, "Stripe", Vector3.new(2.15, 0.5, 1.35), Color3.fromRGB(210, 40, 60))
	local head = newPart(model, "Head", Vector3.new(3.5, 3.5, 3.5), SKIN, Enum.PartType.Ball)
	local hat1 = newPart(model, "Hat1", Vector3.new(0.5, 1.9, 1.9), Color3.fromRGB(220, 40, 60), Enum.PartType.Cylinder)
	local hat2 = newPart(model, "Hat2", Vector3.new(0.6, 1.2, 1.2), Color3.fromRGB(250, 210, 40), Enum.PartType.Cylinder)
	local hat3 = newPart(model, "Hat3", Vector3.new(0.7, 0.55, 0.55), Color3.fromRGB(40, 120, 230), Enum.PartType.Cylinder)
	local eyeL = newPart(model, "EyeL", Vector3.new(0.75, 0.75, 0.75), Color3.new(0, 0, 0), Enum.PartType.Ball)
	local eyeR = newPart(model, "EyeR", Vector3.new(0.55, 0.55, 0.55), Color3.new(0, 0, 0), Enum.PartType.Ball)
	local glintL = newPart(model, "GlintL", Vector3.new(0.18, 0.18, 0.18), Color3.new(1, 1, 1), Enum.PartType.Ball)
	local glintR = newPart(model, "GlintR", Vector3.new(0.16, 0.16, 0.16), Color3.new(1, 1, 1), Enum.PartType.Ball)
	glintL.Material, glintR.Material = Enum.Material.Neon, Enum.Material.Neon
	local mouth = newPart(model, "Mouth", Vector3.new(1.9, 0.32, 0.4), Color3.fromRGB(25, 5, 5))
	local teeth = newPart(model, "Teeth", Vector3.new(1.7, 0.12, 0.42), Color3.fromRGB(235, 230, 210))
	local armL = newPart(model, "ArmL", Vector3.new(0.45, 5.8, 0.45), SKIN)
	local armR = newPart(model, "ArmR", Vector3.new(0.45, 6.3, 0.45), SKIN)
	local legL = newPart(model, "LegL", Vector3.new(0.65, 2.6, 0.65), Color3.fromRGB(40, 60, 140))
	local legR = newPart(model, "LegR", Vector3.new(0.65, 2.6, 0.65), Color3.fromRGB(40, 60, 140))

	local m = {}
	-- hunched: the torso leans forward and the head hangs out in front of it
	m.torso = joint(root, torso, CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(-22), 0, 0))
	joint(torso, stripe, CFrame.new(0, 0.3, 0))
	m.head = joint(torso, head, CFrame.new(0, 2.6, -0.5))
	joint(head, hat1, CFrame.new(0.3, 1.6, 0) * CFrame.Angles(0, 0, math.rad(80)))
	joint(head, hat2, CFrame.new(0.42, 2.1, 0) * CFrame.Angles(0, 0, math.rad(80)))
	joint(head, hat3, CFrame.new(0.55, 2.55, 0) * CFrame.Angles(0, 0, math.rad(80)))
	joint(head, eyeL, CFrame.new(-0.65, 0.35, -1.55))
	joint(head, eyeR, CFrame.new(0.7, 0.2, -1.6))
	joint(eyeL, glintL, CFrame.new(0.1, 0.1, -0.33))
	joint(eyeR, glintR, CFrame.new(0.08, 0.08, -0.25))
	joint(head, mouth, CFrame.new(0, -0.75, -1.5) * CFrame.Angles(0, 0, math.rad(4)))
	joint(mouth, teeth, CFrame.new(0, 0.1, -0.02))
	m.armL = joint(torso, armL, CFrame.new(-1.35, 1.0, 0), CFrame.new(0, 2.8, 0))
	m.armR = joint(torso, armR, CFrame.new(1.35, 1.0, 0), CFrame.new(0, 3.05, 0))
	m.legL = joint(root, legL, CFrame.new(-0.55, 0, 0), CFrame.new(0, 1.2, 0))
	m.legR = joint(root, legR, CFrame.new(0.55, 0, 0), CFrame.new(0, 1.2, 0))
	return model, root, m, {glintL, glintR}
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
	s.anim = {speed = 0, pose = "walk", t = 0}
	local model, root, motors, glints = buildChild()
	s.child, s.root, s.motors, s.glints = model, root, motors, glints
	local home = info.home
	root.CFrame = CFrame.lookAt(home + Vector3.new(0, CONFIG.HipHeight - 3 + 0.35, 4), home + Vector3.new(0, CONFIG.HipHeight - 3 + 0.35, 0))
	model.Parent = info.model
	s.heartbeat = RunService.Heartbeat:Connect(function(dt) s:animate(dt) end)
	return s
end

function Session:target()
	local n = 0
	for _ in pairs(self.players) do n += 1 end
	return math.clamp(n * CONFIG.DunksPerPlayer, CONFIG.MinDunks, CONFIG.MaxDunks)
end

function Session:count()
	local n = 0
	for _ in pairs(self.players) do n += 1 end
	return n
end

-- Motor6D.Transform does not replicate, so the limbs are animated by the Level 6 Playground Client.
-- The server only publishes the pose and a rounded speed as attributes on the model.
function Session:animate(dt)
	local a = self.anim
	local speed = math.floor(a.speed + 0.5)
	if self.child:GetAttribute("Pose") ~= a.pose then self.child:SetAttribute("Pose", a.pose) end
	if self.child:GetAttribute("Speed") ~= speed then self.child:SetAttribute("Speed", speed) end
	self.child:SetAttribute("Chasing", self.chase ~= nil)
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
	self.anim.speed = 0
end

-- ---------------------------------------------------------------------------------------
-- perception
function Session:rayParams()
	local exclude = {self.child}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then exclude[#exclude + 1] = p.Character end
	end
	local model = self.info.model
	for _, name in ipairs({"Frame_Nets", "Frame_BridgeNets", "Frame_RoofNet", "Signs", "BallPit_Balls", "Stray_Balls",
		"Toddler_Balls", "Lights", "Anchors", "Frame_Rollers"}) do
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
	local eye = self.root.Position + Vector3.new(0, 3.2, 0)
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
	self.anim.pose = "count"
	self.anim.speed = 0
	local seconds = CONFIG.CountSeconds[math.min(self.round, #CONFIG.CountSeconds)]
	broadcast(self, "round", self.round, self.dunks, self:target(), seconds)
	task.wait(CONFIG.VoiceLeadSeconds)   -- a breath before the first number
	local beat = seconds / CONFIG.CountTo
	for n = 1, CONFIG.CountTo do
		if not self.active or self.phase ~= "count" then return end
		broadcast(self, "count", n, CONFIG.CountTo)
		-- a child's counting: uneven, with a held breath before the last few
		local wait = beat * (0.75 + math.random() * 0.5) + ((n >= CONFIG.CountTo - 2) and beat * 0.6 or 0)
		task.wait(wait)
	end
	broadcast(self, "go")
	self.anim.pose = "walk"
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
			self.anim.speed = 0
			task.wait(0.1)
		elseif self.chase then
			local player = self.chase
			local root = rootOf(player)
			if not root or not self.players[player] or self.players[player].caught then
				self.chase = nil
			else
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
			self.anim.pose = "walk"
			self:walkTo(at - Vector3.new(0, 3, 0), CONFIG.WalkSpeed * 1.25, "seek")
		else
			local option = self:chooseSpot()
			self.anim.pose = "walk"
			self:walkTo(option.spot - Vector3.new(0, 0.5, 0), CONFIG.WalkSpeed, "seek")
			self.checked[option.i] = true
			if self.active and self.phase == "seek" and not self.chase then
				self.anim.pose = "look"
				self.anim.speed = 0
				local untilT = os.clock() + CONFIG.CheckPause
				while os.clock() < untilT and not self.chase and self.phase == "seek" do task.wait(0.1) end
				self.anim.pose = "walk"
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
				self.chase = seen
				self.interrupt = true
				event:FireClient(seen, "chase", true)
			end
			self.lastSeen = os.clock()
		elseif self.chase and os.clock() - (self.lastSeen or 0) > CONFIG.LoseSightSeconds then
			local lost = self.chase
			self.chase = nil
			local root = rootOf(lost)
			if root then self.noise = root.Position end
			if lost.Parent == Players then event:FireClient(lost, "chase", false) end
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
	end
	self:finish()
end

function Session:finish()
	self.active = false
	self.phase = "over"
	if self.heartbeat then self.heartbeat:Disconnect() end
	if self.child then self.child:Destroy() end
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
