-- Poolrooms environmental mix for the approved public map; gameplay cues stay in Level 2 Sound Controller.
-- The small authored pack contains cyclic loop masters and one-shots with natural, engineered tails.
-- All emitters are client-only. One frame connection owns loading deadlines, envelopes and session cleanup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local rng = Random.new()
local ENTRY_FADE, EXIT_FADE, SHOT_CANCEL = 3, 2, 1
local LOAD_TIMEOUT, POLL_STEP, MAX_PERSISTENT, MAX_SHOTS = 12, .25, 9, 2
local SHOT_ATTACK, SHOT_TAIL, REPEAT_AFTER = .25, 1.5, 70

local folder = ReplicatedStorage:WaitForChild("Level2Poolrooms", 120)
local library = folder and folder:WaitForChild("Sounds", 30)
local value = folder and folder:WaitForChild("Plan", 30)
if not library or not value or not value:IsA("StringValue") then return end
local decoded, plan = pcall(function() return HttpService:JSONDecode(value.Value) end)
if not decoded or type(plan) ~= "table" or type(plan.sections) ~= "table"
	or type(plan.beds) ~= "table" or type(plan.loops) ~= "table" or type(plan.shots) ~= "table"
	or #plan.beds + #plan.loops > MAX_PERSISTENT then
	warn("[Poolrooms audio] invalid or oversized authored plan; retaining legacy ambience")
	return
end
local function vec(t) return Vector3.new(t[1], t[2], t[3]) end
local function template(key)
	local sound = library:FindFirstChild(key)
	return sound and sound:IsA("Sound") and sound.SoundId:match("^rbxassetid://%d+$") and sound or nil
end
local critical, pack, keys = {}, {}, {}
for _, rows in ipairs({plan.beds, plan.loops, plan.shots}) do
	for _, row in ipairs(rows) do
		if not keys[row.key] then
			local sound = template(row.key)
			if not sound then warn("[Poolrooms audio] missing asset " .. tostring(row.key)); return end
			keys[row.key] = true
			table.insert(pack, sound)
		end
		if rows ~= plan.shots then critical[row.key] = template(row.key) end
	end
end
if #pack > 9 then warn("[Poolrooms audio] oversized asset pack; retaining legacy ambience"); return end
local group = Instance.new("SoundGroup")
group.Name, group.Parent = "Level2Poolrooms", SoundService
local session, preloadThread, preloadDeadline, preloadStarted = nil, nil, 0, false
local nextPoll, retryAfter = 0, 0
local lastReady, lastActive, lastSection = false, false, nil
local connections = {}

local function diagnostics(ready, active, section)
	if ready ~= lastReady then player:SetAttribute("Level2PoolroomsAudioReady", ready); lastReady = ready end
	if active ~= lastActive then player:SetAttribute("Level2PoolroomsAudioActive", active); lastActive = active end
	if section ~= lastSection then player:SetAttribute("Level2PoolroomsAudioSection", section); lastSection = section end
end
player:SetAttribute("Level2PoolroomsAudioReady", false)
player:SetAttribute("Level2PoolroomsAudioActive", false)
player:SetAttribute("Level2PoolroomsAudioSection", nil)

local function preload(now)
	if preloadStarted or workspace:GetAttribute("SelectedLevel") ~= 2 then return end
	preloadStarted, preloadDeadline = true, now + LOAD_TIMEOUT
	-- Nine templates, three at a time; this never blocks the round or a frame callback.
	preloadThread = task.spawn(function()
		for first = 1, #pack, 3 do
			local batch = {}
			for i = first, math.min(first + 2, #pack) do table.insert(batch, pack[i]) end
			pcall(function() ContentProvider:PreloadAsync(batch) end)
		end
		preloadThread = nil
	end)
end
local function packReady()
	for _, sound in pairs(critical) do if not sound.IsLoaded then return false end end
	return next(critical) ~= nil
end
local function mapModel()
	local world = workspace:FindFirstChild("Level 2 Generated World")
	return world and world:IsA("Model") and world:GetAttribute("Level2NewMap") == true and world or nil
end
local function listenerRoot()
	if player:GetAttribute("InRound") ~= true then return nil end
	local subject = player
	if player:GetAttribute("Spectating") == true then
		local id = player:GetAttribute("SpectateTargetUserId")
		subject = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
		if not subject or subject:GetAttribute("InRound") ~= true or subject:GetAttribute("Escaped") == true then return nil end
	elseif player:GetAttribute("Escaped") == true and player:GetAttribute("Level2_ExitTransition") ~= true then
		return nil
	end
	local body = subject.Character
	local humanoid = body and body:FindFirstChildOfClass("Humanoid")
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and root:IsDescendantOf(workspace) then
		return root, subject.UserId
	end
	return nil
end
local function eligible()
	if workspace:GetAttribute("SelectedLevel") ~= 2 or workspace:GetAttribute("WorldGenerated") ~= true
		or (workspace:GetAttribute("RoundActive") ~= true and player:GetAttribute("Level2_ExitTransition") ~= true) then return nil end
	local root, subject = listenerRoot()
	local world = root and mapModel()
	return world, root, subject
end
local function originOf(world)
	local origin = world:GetAttribute("Origin")
	return typeof(origin) == "Vector3" and origin or vec(plan.origin)
end
local function within(p, box, margin)
	return p.X >= box.min[1] - margin and p.X <= box.max[1] + margin
		and p.Y >= box.min[2] - margin and p.Y <= box.max[2] + margin
		and p.Z >= box.min[3] - margin and p.Z <= box.max[3] + margin
end
local function segmentPoint(p, a, b)
	local line = b - a
	local t = line:Dot(line) > .001 and math.clamp((p - a):Dot(line) / line:Dot(line), 0, 1) or 0
	return a + line * t
end
local SKIP = {Barrier = true, Guard = true, Veil = true, Hazard = true}
local params = RaycastParams.new()
params.FilterType, params.IgnoreWater = Enum.RaycastFilterType.Include, true
local function sectionAt(s, position)
	local collision = s.world:FindFirstChild("Collision")
	if collision then
		params.FilterDescendantsInstances = {collision}
		local from = position + Vector3.new(0, 2, 0)
		for _ = 1, 4 do
			local hit = workspace:Raycast(from, Vector3.new(0, -70, 0), params)
			if not hit then break end
			local area = hit.Instance:GetAttribute("Area")
			if not SKIP[hit.Instance.Name] and type(area) == "string" and plan.sections[area] then return area end
			from = hit.Position - Vector3.new(0, .1, 0)
		end
	end
	local p = position - s.origin
	for _, passage in ipairs({true, false}) do
		for _, id in ipairs(plan.order or {}) do
			local box = plan.sections[id]
			if box and box.passage == passage and within(p, box, 2) then return id end
		end
	end
	-- Route segments preserve the section while its floor has not streamed in, including vertically stacked stairs.
	local chosen, nearest = nil, 55
	for _, row in ipairs(plan.route or {}) do
		local point = segmentPoint(p, vec(row.a), vec(row.b))
		local distance = (p - point).Magnitude
		if distance < nearest and plan.sections[row.section] then chosen, nearest = row.section, distance end
	end
	if chosen then return chosen end
	if player:GetAttribute("Level2_ExitTransition") == true then return "EXIT" end
	return nil
end
local function applies(row, section)
	return section ~= nil and (table.find(row.sections or {}, section) ~= nil or table.find(row.sections or {}, "*") ~= nil)
end
local function envelope(entry, target, now, duration)
	if entry.target ~= target then
		entry.from, entry.target, entry.changed, entry.fade = entry.level, target, now, duration
	end
	local t = math.clamp((now - entry.changed) / entry.fade, 0, 1)
	local ease = t * t * (3 - 2 * t)
	entry.level = entry.from + (entry.target - entry.from) * ease
	entry.sound.Volume = entry.level
end
local function emitter(parent, name, position)
	local part = Instance.new("Part")
	part.Name, part.Position, part.Size, part.Transparency = name, position, Vector3.new(.2, .2, .2), 1
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Parent = parent
	return part
end
local function soundCopy(key, parent, looped)
	local sound = template(key):Clone()
	sound.Volume, sound.Looped, sound.PlayOnRemove, sound.SoundGroup = 0, looped, false, group
	sound.Parent = parent
	return sound
end
local function persistent(row, sound, now, owner)
	return {row = row, sound = sound, owner = owner, level = 0, target = 0, from = 0,
		changed = now, fade = ENTRY_FADE, deadline = now + LOAD_TIMEOUT, started = false}
end
local function newSession(world, subject, now)
	local s = {world = world, generation = world:GetAttribute("Level2_Generation"), origin = originOf(world), subject = subject, created = now,
		entries = {}, shots = {}, recent = {}, lastPlayed = {}, nextShot = now + rng:NextNumber(18, 30)}
	s.bank, s.emitters = Instance.new("Folder"), Instance.new("Folder")
	s.bank.Name, s.bank.Parent = "Level2PoolroomsBeds", SoundService
	s.emitters.Name, s.emitters.Parent = "Level2PoolroomsEmitters", workspace
	s.emitters:SetAttribute("Level2_ClientOnlyAudio", true)
	for _, row in ipairs(plan.beds) do table.insert(s.entries, persistent(row, soundCopy(row.key, s.bank, true), now)) end
	for _, row in ipairs(plan.loops) do
		local owner = emitter(s.emitters, row.name or row.key, s.origin + vec(row.position))
		local sound = soundCopy(row.key, owner, true)
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance, sound.RollOffMaxDistance = row.min or 8, row.max or 90
		table.insert(s.entries, persistent(row, sound, now, owner))
	end
	return s
end
local function cancelShots(s, now)
	for _, record in ipairs(s.shots) do
		if not record.cancelled then record.cancelled, record.cancelVolume = now, record.sound.Volume end
	end
end
local function exitSession(s, now)
	if s.exiting then return end
	s.exiting = now
	cancelShots(s, now)
	for _, entry in ipairs(s.entries) do envelope(entry, 0, now, EXIT_FADE) end
	diagnostics(false, false, nil)
end
local function restoreCascade(s)
	local c = s.cascade
	if c and c.sound.Parent and c.sound:IsDescendantOf(s.world) and math.abs(c.sound.Volume - c.written) < .0001 then
		c.sound.Volume = c.original
	end
	s.cascade = nil
end
local function destroySession(s)
	restoreCascade(s)
	s.bank:Destroy()
	s.emitters:Destroy()
	if session == s then session = nil end
end
local function updateCascade(s)
	-- The server's library sound remains a fallback. Only this client crossfades it against its loaded P2 replacement.
	local c = s.cascade
	if c and (not c.sound.Parent or not c.sound:IsDescendantOf(s.world)) then s.cascade, c = nil, nil end
	if not c and not s.exiting then
		local fx = s.world:FindFirstChild("Water FX")
		local owner = fx and fx:FindFirstChild("Cascade Sound")
		local sound = owner and owner:FindFirstChild("Cascade Water")
		if sound and sound:IsA("Sound") then
			c = {sound = sound, original = sound.Volume, written = sound.Volume}
			s.cascade = c
		end
	end
	if not c then return end
	local replacement = 0
	for _, entry in ipairs(s.entries) do
		if entry.started and entry.sound.IsLoaded and entry.row.replaces == "Cascade Water" then
			replacement = math.max(replacement, math.clamp(entry.level / math.max(entry.row.volume, .001), 0, 1))
		end
	end
	c.written = c.original * (1 - replacement)
	c.sound.Volume = c.written
end
local function updatePersistent(s, now)
	for _, entry in ipairs(s.entries) do
		local target = not s.exiting and s.ready and applies(entry.row, s.section) and entry.row.volume or 0
		if target > 0 and not entry.started then
			if entry.sound.IsLoaded then
				entry.started = true
				entry.sound.TimePosition = rng:NextNumber() * math.max(0, entry.sound.TimeLength - .1)
				entry.sound:Play()
				entry.changed, entry.from, entry.target = now, 0, 0
			elseif now >= entry.deadline then
				warn("[Poolrooms audio] asset initialization timed out: " .. entry.row.key)
				retryAfter = now + 20
				exitSession(s, now)
				target = 0
			end
		end
		if not entry.started then target = 0 end
		envelope(entry, target, now, target > entry.level and ENTRY_FADE or EXIT_FADE)
		if entry.started and entry.target == 0 and entry.level <= .00001 then
			entry.sound.Volume = 0
			entry.sound:Stop()
			entry.started, entry.deadline = false, now + LOAD_TIMEOUT
		end
	end
	updateCascade(s)
end
local function pickShot(s, now)
	local candidates, fresh, total = {}, {}, 0
	for _, row in ipairs(plan.shots) do
		if applies(row, s.section) and now - (s.lastPlayed[row.key] or -1e9) >= REPEAT_AFTER then
			table.insert(candidates, row)
			if not table.find(s.recent, row.key) then table.insert(fresh, row) end
		end
	end
	if #fresh > 0 then candidates = fresh end -- history never permanently silences a section with one eligible clip
	for _, row in ipairs(candidates) do total += row.weight or 1 end
	local roll = rng:NextNumber() * total
	for _, row in ipairs(candidates) do
		roll -= row.weight or 1
		if roll <= 0 then return row end
	end
	return nil
end
local function fireShot(s, row, listener, now)
	if #s.shots >= MAX_SHOTS then return end
	local distance = rng:NextNumber((row.dist or {18, 65})[1], (row.dist or {18, 65})[2])
	local angle = rng:NextNumber() * math.pi * 2
	local position = listener + Vector3.new(math.cos(angle) * distance, rng:NextNumber(-1, 4), math.sin(angle) * distance)
	if row.position then position = s.origin + vec(row.position) end
	local owner = emitter(s.emitters, "Poolrooms " .. row.key, position)
	local sound = soundCopy(row.key, owner, false)
	sound.PlaybackSpeed = rng:NextNumber(.98, 1.02)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance, sound.RollOffMaxDistance = row.min or 10, row.max or 110
	table.insert(s.shots, {key = row.key, owner = owner, sound = sound, deadline = now + LOAD_TIMEOUT,
		volume = row.volume * rng:NextNumber(.9, 1.05)})
end
local function updateShots(s, now)
	for i = #s.shots, 1, -1 do
		local record = s.shots[i]
		local remove = false
		if record.cancelled then
			local amount = math.clamp((now - record.cancelled) / SHOT_CANCEL, 0, 1)
			record.sound.Volume = record.cancelVolume * (1 - amount) ^ 2
			remove = not record.started or amount == 1
		elseif not record.started then
			if record.sound.IsLoaded and record.sound.TimeLength > 0 then
				record.started, record.progressAt, record.lastPosition = now, now, 0
				record.ended = record.sound.Ended:Connect(function() record.finished = true end)
				record.stopped = record.sound.Stopped:Connect(function() record.interrupted = true end)
				record.sound:Play()
				s.lastPlayed[record.key] = now
				table.insert(s.recent, record.key)
				if #s.recent > 2 then table.remove(s.recent, 1) end
				player:SetAttribute("Level2PoolroomsAudioLastShot", record.key)
			elseif now >= record.deadline then
				warn("[Poolrooms audio] one-shot load timed out: " .. record.key)
				remove = true
			end
		else
			-- Asset initialization and engine pauses can delay playback independently of wall time.
			-- The attack/tail follow actual audio position; elapsed wall time only detects a stalled voice.
			local position = record.sound.TimePosition
			if position > record.lastPosition + .001 then record.lastPosition, record.progressAt = position, now end
			local elapsed = position / record.sound.PlaybackSpeed
			local attack = math.clamp(elapsed / SHOT_ATTACK, 0, 1)
			local remaining = (record.sound.TimeLength - position) / record.sound.PlaybackSpeed
			local release = math.clamp(remaining / SHOT_TAIL, 0, 1)
			record.sound.Volume = record.volume * math.sin(attack * math.pi / 2) ^ 2 * math.sin(release * math.pi / 2) ^ 2
			remove = record.finished or (remaining <= 0 and position > 0)
			if not remove and (record.interrupted or now - record.progressAt >= LOAD_TIMEOUT) then
				-- A bounded failure exit still finishes its one-second fade before any emitter is destroyed.
				record.cancelled, record.cancelVolume = now, record.sound.Volume
			end
		end
		if remove then
			record.sound.Volume = 0
			if record.ended then record.ended:Disconnect() end
			if record.stopped then record.stopped:Disconnect() end
			record.owner:Destroy()
			table.remove(s.shots, i)
		end
	end
end
local function step()
	local now = os.clock()
	if now >= nextPoll then
		nextPoll = now + POLL_STEP
		preload(now)
		if preloadThread and now >= preloadDeadline then
			pcall(task.cancel, preloadThread)
			preloadThread = nil
			if not packReady() then warn("[Poolrooms audio] preload deadline reached; retaining legacy ambience") end
		end
		local world, root, subject = eligible()
		if session and not session.exiting then
			if world ~= session.world or not world or world:GetAttribute("Level2_Generation") ~= session.generation
				or originOf(world) ~= session.origin then
				exitSession(session, now)
			else
				if session.subject ~= subject then cancelShots(session, now); session.subject = subject end
				local found = sectionAt(session, root.Position)
				if found ~= session.section then
					if found == session.pending then session.pendingCount += 1 else session.pending, session.pendingCount = found, 1 end
					if session.pendingCount >= 2 or not session.section then session.section = found end
				else session.pending, session.pendingCount = nil, 0 end
			end
		end
		if not session and world and packReady() and now >= retryAfter then
			session = newSession(world, subject, now)
			session.section = sectionAt(session, root.Position)
		end
		if session and not session.exiting then
			local initialized = true
			for _, entry in ipairs(session.entries) do if not entry.sound.IsLoaded then initialized = false end end
			session.ready = initialized and session.section ~= nil
			if not initialized and now - session.created >= LOAD_TIMEOUT then
				warn("[Poolrooms audio] pack initialization timed out; retaining legacy ambience")
				retryAfter = now + 20
				exitSession(session, now)
			else
				diagnostics(session.ready, session.ready, session.section)
			end
			if session.ready and not session.exiting and root and now >= session.nextShot and workspace:GetAttribute("RoundActive") == true then
				session.nextShot = now + rng:NextNumber(18, 45)
				local shot = pickShot(session, now)
				if shot then fireShot(session, shot, root.Position, now) end
			end
		end
	end
	if session then
		updatePersistent(session, now)
		updateShots(session, now)
		if session.exiting and now - session.exiting >= EXIT_FADE then destroySession(session) end
	end
end
table.insert(connections, RunService.Heartbeat:Connect(step))
table.insert(connections, script.Destroying:Connect(function()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	if preloadThread then pcall(task.cancel, preloadThread) end
	if session then destroySession(session) end
	diagnostics(false, false, nil)
	group:Destroy()
end))
