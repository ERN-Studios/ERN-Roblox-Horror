"""One-off: turn the Level 6 game module's placeholder child into The Counter (doll, clips, recorded voice).

    python3 tools/level6_entity/patch_game_module.py

Applied once on 2026-10-03 to tools/level6_playground/studio/Level 6 Playground Game.ModuleScript.lua;
kept as the record of what changed. Every replacement asserts that its anchor text is present exactly once.
"""
from pathlib import Path

p = Path(__file__).resolve().parents[1] / 'level6_playground' / 'studio' / 'Level 6 Playground Game.ModuleScript.lua'
s = p.read_text()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:80])
    s = s.replace(a, b)


rep('''-- Each round: the child faces Home Base and counts to 20 out loud; when it finishes it searches''',
    '''-- The child is "The Counter", a skinned porcelain doll: its mesh is baked on the server from
-- ServerStorage.Level6CounterSource, its clips and voice lines live in ReplicatedStorage.Level6Counter
-- (pipeline: tools/level6_entity). The server only publishes Anim / AnimSerial / Speed on the model and
-- says which line to speak; the Level 6 Playground Client moves the bones and plays the sound.
-- Each round: the child faces Home Base and counts to 20 out loud; when it finishes it searches''')
rep('''local ReplicatedStorage = game:GetService("ReplicatedStorage")
''', '''local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
''')
rep('''	-- Paused 2026-10-03 on the owner's request: with this false nobody counts, seeks or chases and the
	-- map is a free-roam preview. Set it back to true to bring the hide-and-seek round back.
	EntityEnabled = false,
	CountTo = 20,
	CountSeconds = {20, 16, 13, 10},  -- per round; the last value repeats''', '''	-- With this false nobody counts, seeks or chases and the map is a free-roam preview.
	EntityEnabled = true,
	CountTo = 20,
	-- the recorded count for each round (22.9, 21.2, 19.2, 15.9 s); the last one repeats
	CountLines = {"l6_count_slow", "l6_count_medium", "l6_count_fast", "l6_count_frantic"},''')
rep('''	WalkSpeed = 13, ChaseSpeed = 21, EscapeChaseSpeed = 18,''', '''	WalkSpeed = 9, ChaseSpeed = 20, EscapeChaseSpeed = 18,''')
rep('''LoseSightSeconds = 4, CheckPause = 1.2,''', '''LoseSightSeconds = 4, CheckPause = 3.3,   -- CheckPause = the Search_Look clip''')
rep('''	HipHeight = 3.1,
	VoiceLeadSeconds = 0.6,''', '''	HipHeight = 2.4,   -- root above the soles; replaced by the mesh's own value when the doll is built
	EyeHeight = 1.4,   -- eyes above the root
	SpottedPause = 0.9,''')

a = s.index('-- the child\nlocal SKIN')
b = s.index('-- ---------------------------------------------------------------------------------------\n-- session')
s = s[:a] + '''-- the child
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
}
local lastLine = {}
local function pick(group)
	local list = VOICE[group]
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

''' + s[b:]

rep('''	s.anim = {speed = 0, pose = "walk", t = 0}
	local model, root, motors, glints = buildChild()
	s.child, s.root, s.motors, s.glints = model, root, motors, glints
	local home = info.home''', '''	s.anim = {speed = 0, name = "Idle", serial = 0}
	s.voiceUntil = 0
	local model, root = buildChild()
	s.child, s.root = model, root
	local home = info.home''')

rep('''-- Motor6D.Transform does not replicate, so the limbs are animated by the Level 6 Playground Client.
-- The server only publishes the pose and a rounded speed as attributes on the model.
function Session:animate(dt)
	local a = self.anim
	local speed = math.floor(a.speed + 0.5)
	if self.child:GetAttribute("Pose") ~= a.pose then self.child:SetAttribute("Pose", a.pose) end
	if self.child:GetAttribute("Speed") ~= speed then self.child:SetAttribute("Speed", speed) end
	self.child:SetAttribute("Chasing", self.chase ~= nil)
end''', '''-- Bone.Transform does not replicate, so the Level 6 Playground Client plays the clips. The server only
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
end''')

rep('''			local step = speed * dt
			self.anim.speed = speed''', '''			local step = speed * dt
			self.anim.speed = speed
			self.anim.name = speed >= 15 and "Run_Chase" or "Walk_Wander"''')
rep('''	self:walkTo(stand, CONFIG.WalkSpeed * 1.4, phase)
	self:place(stand, home - stand)
	self.anim.speed = 0''', '''	self:walkTo(stand, CONFIG.WalkSpeed * 1.4, phase)
	self:place(stand, home - stand)
	self:pose("Idle")''')
rep('''	for _, name in ipairs({"Frame_Nets", "Frame_BridgeNets", "Frame_RoofNet", "Signs", "BallPit_Balls", "Stray_Balls",
		"Toddler_Balls", "Lights", "Anchors", "Frame_Rollers"}) do''', '''	for _, name in ipairs({"Frame_Nets", "Frame_BridgeNets", "Frame_RoofNet", "BallOcean_Nets", "Signs", "BallOcean_Balls",
		"Toddler_Balls", "Lights", "Anchors", "Frame_Rollers", "Frame_Lamps", "Ceiling_Fixtures"}) do''')
rep('''	local eye = self.root.Position + Vector3.new(0, 3.2, 0)''', '''	local eye = self.root.Position + Vector3.new(0, CONFIG.EyeHeight, 0)''')
rep('''	self.pauseUntil = os.clock() + 1.6
	task.delay(CONFIG.CaughtReturnDelay, function()''', '''	self.pauseUntil = os.clock() + 1.6
	self.interrupt = true
	self:pose("Catch")
	self:say(pick("found"), true)
	task.delay(CONFIG.CaughtReturnDelay, function()''')
rep('''	if left == 0 then
		broadcast(self, "lost")
		self.phase = "over"
	end''', '''	if left == 0 then
		broadcast(self, "lost")
		self.phase = "over"
		task.delay(1.8, function() broadcast(self, "say", "l6_win") end)
	elseif self.active then
		task.delay(2.0, function() if self.active then self:say("l6_found_other", true) end end)
	end''')
rep('''	self.phase = "count"
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
	self.anim.pose = "walk"''', '''	self.phase = "count"
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
	self:pose("Idle")''')
rep('''		if self.pauseUntil and os.clock() < self.pauseUntil then
			self.anim.speed = 0
			task.wait(0.1)''', '''		if self.pauseUntil and os.clock() < self.pauseUntil then
			self.anim.speed = 0             -- holding a Spotted or Catch pose
			task.wait(0.1)''')
rep('''				local target = root.Position - Vector3.new(0, 3, 0)
				local direct''', '''				if os.clock() > (self.nextChaseLine or 0) then
					self.nextChaseLine = os.clock() + 6 + math.random() * 4
					self:say(pick("chase"))
				end
				local target = root.Position - Vector3.new(0, 3, 0)
				local direct''')
rep('''			local at = self.noise
			self.noise = nil
			self.anim.pose = "walk"
			self:walkTo''', '''			local at = self.noise
			self.noise = nil
			self:walkTo''')
rep('''			local option = self:chooseSpot()
			self.anim.pose = "walk"
			self:walkTo(option.spot - Vector3.new(0, 0.5, 0), CONFIG.WalkSpeed, "seek")
			self.checked[option.i] = true
			if self.active and self.phase == "seek" and not self.chase then
				self.anim.pose = "look"
				self.anim.speed = 0
				local untilT = os.clock() + CONFIG.CheckPause
				while os.clock() < untilT and not self.chase and self.phase == "seek" do task.wait(0.1) end
				self.anim.pose = "walk"
			end''', '''			local option = self:chooseSpot()
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
			end''')
rep('''				self.chase = seen
				self.interrupt = true
				event:FireClient(seen, "chase", true)''', '''				local first = self.chase == nil
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
				end''')
rep('''			if root then self.noise = root.Position end
			if lost.Parent == Players then event:FireClient(lost, "chase", false) end''', '''			if root then self.noise = root.Position end
			if lost.Parent == Players then event:FireClient(lost, "chase", false) end
			self:say(pick("lost"), true)''')
rep('''					broadcast(self, "dunk", player.DisplayName, self.dunks, self:target())
					self.noise = home''', '''					broadcast(self, "dunk", player.DisplayName, self.dunks, self:target())
					self.noise = home
					self:say(pick("dunk"), true)''')
rep('''	self.phase = "escape"
	broadcast(self, "won", self.dunks)''', '''	self.phase = "escape"
	broadcast(self, "won", self.dunks)
	self:say(pick("exit"), true)''')
rep('''				event:FireClient(player, "escaped", player.DisplayName, true)
				task.delay(1.5, function()''', '''				event:FireClient(player, "escaped", player.DisplayName, true)
				event:FireClient(player, "say", "l6_escaped")
				task.delay(1.5, function()''')
rep('''		broadcast(self, "roundover", result)''', '''		broadcast(self, "roundover", result)
		self:say("l6_round_again", true)''')
p.write_text(s)
print(len(s.splitlines()), 'lines written')
