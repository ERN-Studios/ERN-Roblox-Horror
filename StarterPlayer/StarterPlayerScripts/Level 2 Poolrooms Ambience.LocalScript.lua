-- Poolrooms environmental mix for the approved public map; gameplay cues stay in Level 2 Sound Controller.
-- The authored pack contains cyclic loop masters and one-shots with natural, engineered tails.
-- All emitters are client-only. One frame connection owns loading deadlines, envelopes and session cleanup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
-- AUDIO_SECTIONS_20261010: diagnostics are client-local and publish only value changes.
local function attribute(name, value)
	if player:GetAttribute(name) ~= value then player:SetAttribute(name, value) end
end
local rng = Random.new()
local ENTRY_FADE, EXIT_FADE, SHOT_CANCEL = 3, 2, 1
-- AUDIO_SECTIONS_20261010: authoring bounds are separate from the section's live voice cache.
local LOAD_TIMEOUT, POLL_STEP, MAX_PERSISTENT, MAX_KEYS, MAX_SHOTS, IDLE_RELEASE = 12, .25, 64, 160, 4, 30
local SHOT_ATTACK, SHOT_TAIL, REPEAT_AFTER = .25, 1.5, 70

local folder = ReplicatedStorage:WaitForChild("Level2Poolrooms", 120)
local library = folder and folder:WaitForChild("Sounds", 30)
local value = folder and folder:WaitForChild("Plan", 30)
if not library or not value or not value:IsA("StringValue") then return end
local decoded, plan = pcall(function() return HttpService:JSONDecode(value.Value) end)
if not decoded or type(plan) ~= "table" or type(plan.sections) ~= "table"
	or type(plan.beds) ~= "table" or type(plan.loops) ~= "table" or type(plan.shots) ~= "table"
	or (plan.limits ~= nil and type(plan.limits) ~= "table") then
	warn("[Poolrooms audio] invalid or oversized authored plan; retaining legacy ambience")
	return
end
local function vec(t) return Vector3.new(t[1], t[2], t[3]) end
-- AUDIO_SECTIONS_20261010: reject malformed data before any owned Instances exist.
local function number(n, minimum)
	return type(n) == "number" and n == n and math.abs(n) < math.huge and n >= minimum
end
local function array(t)
	if type(t) ~= "table" then return false end
	local count = 0
	for key in pairs(t) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #t then return false end
		count += 1
	end
	return count == #t
end
local function tuple(t, count, minimum)
	if not array(t) or #t ~= count then return false end
	for _, n in ipairs(t) do if not number(n, minimum) then return false end end
	return true
end
local function range(t, minimum)
	return tuple(t, 2, minimum) and t[2] >= t[1]
end
local function limit(n, maximum, minimum)
	return number(n, minimum) and n % 1 == 0 and n <= maximum
end
local limits = plan.limits or {}
local persistentLimit, keyLimit, shotLimit = limits.persistent or MAX_PERSISTENT, limits.keys or MAX_KEYS, limits.shots or 2
local valid = limit(persistentLimit, MAX_PERSISTENT, 1) and limit(keyLimit, MAX_KEYS, 1)
	and limit(shotLimit, MAX_SHOTS, 0) and (limits.recent == nil or limit(limits.recent, 4, 0))
	and (limits.persistent == nil or limit(limits.persistent, MAX_PERSISTENT, 1))
	and (limits.keys == nil or limit(limits.keys, MAX_KEYS, 1)) and (limits.shots == nil or limit(limits.shots, MAX_SHOTS, 0))
	and #plan.beds + #plan.loops <= persistentLimit and tuple(plan.origin, 3, -math.huge)
	and array(plan.beds) and array(plan.loops) and array(plan.shots)
	and (plan.order == nil or array(plan.order)) and (plan.route == nil or array(plan.route))
if not valid then warn("[Poolrooms audio] invalid or oversized authored plan; retaining legacy ambience"); return end
for id, section in pairs(plan.sections) do
	valid = valid and type(id) == "string" and type(section) == "table"
		and tuple(section.min, 3, -math.huge) and tuple(section.max, 3, -math.huge)
		and (section.passage == nil or type(section.passage) == "boolean")
		and (section.gap == nil or range(section.gap, .001)) and (section.first == nil or range(section.first, 0))
	if valid then for i = 1, 3 do valid = valid and section.min[i] <= section.max[i] end end
end
for _, id in ipairs(plan.order or {}) do valid = valid and type(id) == "string" end
for _, row in ipairs(plan.route or {}) do
	valid = valid and type(row) == "table" and type(row.section) == "string"
		and tuple(row.a, 3, -math.huge) and tuple(row.b, 3, -math.huge)
end
for _, rows in ipairs({plan.beds, plan.loops, plan.shots}) do
	for _, row in ipairs(rows) do
		valid = valid and type(row) == "table" and type(row.key) == "string" and row.key ~= ""
			and number(row.volume, 0) and array(row.sections)
		if valid then
			for _, id in ipairs(row.sections) do valid = valid and type(id) == "string" end
			valid = valid and (row.position == nil or tuple(row.position, 3, -math.huge))
				and (rows ~= plan.loops or row.position ~= nil)
				and (row.min == nil or number(row.min, 0)) and (row.max == nil or number(row.max, 0))
				and (row.fade == nil or tuple(row.fade, 2, 0)) and (row.dist == nil or range(row.dist, 0))
				and (row.pitch == nil or range(row.pitch, .001)) and (row.cooldown == nil or number(row.cooldown, 0))
				and (row.weight == nil or number(row.weight, .001))
				and (row.positions == nil or array(row.positions))
				and (row.name == nil or type(row.name) == "string") and (row.replaces == nil or type(row.replaces) == "string")
			if valid and rows ~= plan.beds then
				valid = (row.max or (rows == plan.loops and 90 or 110)) >= (row.min or (rows == plan.loops and 8 or 10))
			end
			if valid then for _, spot in ipairs(row.positions or {}) do valid = valid and tuple(spot, 3, -math.huge) end end
		end
	end
end
if not valid then warn("[Poolrooms audio] invalid or oversized authored plan; retaining legacy ambience"); return end
local function template(key)
	local sound = library:FindFirstChild(key)
	-- Archivable: Clone() of a template that is not returns nil, and a nil clone would throw on every frame.
	return sound and sound:IsA("Sound") and sound.Archivable ~= false and sound.SoundId:match("^rbxassetid://%d+$") and sound or nil
end
-- AUDIO_SECTIONS_20261010: one missing asset must not discard the usable section beds.
local beds, loops, shots, templates, keys, skipped = {}, {}, {}, {}, {}, {}
local skippedNames, keyCount = {}, 0
attribute("Level2PoolroomsAudioSkipped", "")
local function skip(key, reason)
	if skipped[key] then return end
	skipped[key] = true
	table.insert(skippedNames, key)
	table.sort(skippedNames)
	attribute("Level2PoolroomsAudioSkipped", table.concat(skippedNames, ","))
	warn("[Poolrooms audio] " .. reason .. ": " .. key)
end
for _, rows in ipairs({plan.beds, plan.loops, plan.shots}) do
	for _, row in ipairs(rows) do
		if not keys[row.key] then
			keys[row.key] = true
			keyCount += 1
			templates[row.key] = template(row.key)
			if not templates[row.key] then skip(row.key, "missing asset") end
		end
		if templates[row.key] then table.insert(rows == plan.beds and beds or rows == plan.loops and loops or shots, row) end
	end
end
if keyCount > keyLimit or #beds == 0 then warn("[Poolrooms audio] oversized asset pack or no usable bed; retaining legacy ambience"); return end
local group = Instance.new("SoundGroup")
group.Name, group.Parent = "Level2Poolrooms", SoundService
local session, preloadBatch = nil, nil
local nextPoll = 0
local lastReady, lastActive, lastSection = false, false, nil
local connections = {}

local function diagnostics(ready, active, section)
	if ready ~= lastReady then player:SetAttribute("Level2PoolroomsAudioReady", ready); lastReady = ready end
	if active ~= lastActive then player:SetAttribute("Level2PoolroomsAudioActive", active); lastActive = active end
	if section ~= lastSection then player:SetAttribute("Level2PoolroomsAudioSection", section); lastSection = section end
end
attribute("Level2PoolroomsAudioReady", false)
attribute("Level2PoolroomsAudioActive", false)
attribute("Level2PoolroomsAudioSection", nil)
-- AUDIO_SECTIONS_20261010: strings are rebuilt on membership/target changes, never on every fade frame.
attribute("Level2PoolroomsAudioBeds", "")
attribute("Level2PoolroomsAudioShots", 0)
attribute("Level2PoolroomsAudioVoices", 0)
local function mixDiagnostics(s)
	attribute("Level2PoolroomsAudioVoices", s and s.liveVoices or 0)
	attribute("Level2PoolroomsAudioShots", s and s.shotCount or 0)
	if not s then attribute("Level2PoolroomsAudioBeds", ""); return end
	if not s.bedsDirty then return end
	s.bedsDirty = false
	local levels, names = {}, {}
	for _, entry in ipairs(s.entries) do
		if entry.bed and entry.audible then levels[entry.row.key] = (levels[entry.row.key] or 0) + entry.target end
	end
	for key, target in pairs(levels) do table.insert(names, key .. "=" .. string.format("%.2f", target)) end
	table.sort(names)
	attribute("Level2PoolroomsAudioBeds", table.concat(names, ","))
end

-- AUDIO_SECTIONS_20261010: preload distinct persistent keys in route order, then only nearby shot pools.
local preloadQueue, queuedKeys, orderIndex, preloadNext = {}, {}, {}, 1
local function queueKey(key)
	if queuedKeys[key] then return end
	queuedKeys[key] = true
	table.insert(preloadQueue, templates[key])
end
local function applies(row, section)
	return section ~= nil and (table.find(row.sections, section) ~= nil or table.find(row.sections, "*") ~= nil)
end
for index, id in ipairs(plan.order or {}) do
	if not orderIndex[id] then orderIndex[id] = index end
	for _, rows in ipairs({beds, loops}) do
		for _, row in ipairs(rows) do if applies(row, id) then queueKey(row.key) end end
	end
end
for _, rows in ipairs({beds, loops}) do for _, row in ipairs(rows) do queueKey(row.key) end end
local function cancelPreload()
	if preloadBatch then
		preloadBatch.cancelled = true
		if not preloadBatch.done then pcall(task.cancel, preloadBatch.thread) end
		preloadBatch = nil
	end
end
local function preload(now)
	if workspace:GetAttribute("SelectedLevel") ~= 2 then cancelPreload(); return end
	if preloadBatch then
		if preloadBatch.done then preloadBatch = nil
		elseif now >= preloadBatch.deadline then
			cancelPreload()
			warn("[Poolrooms audio] preload batch deadline reached")
		else return end
	end
	if preloadNext > #preloadQueue then return end
	local batch = {sounds = {}, deadline = now + LOAD_TIMEOUT, done = false}
	for _ = 1, 3 do
		if preloadNext > #preloadQueue then break end
		table.insert(batch.sounds, preloadQueue[preloadNext])
		preloadNext += 1
	end
	preloadBatch = batch
	batch.thread = task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync(batch.sounds) end)
		batch.done = true
	end)
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
-- AUDIO_SECTIONS_20261010: section polls reuse their filter and traversal lists.
local collisionFilter, passageOrder, sectionOrder, route = {}, {true, false}, plan.order or {}, plan.route or {}
local params = RaycastParams.new()
params.FilterType, params.IgnoreWater = Enum.RaycastFilterType.Include, true
local function sectionAt(s, position)
	local collision = s.world:FindFirstChild("Collision")
	if collision then
		collisionFilter[1] = collision
		params.FilterDescendantsInstances = collisionFilter
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
	for _, passage in ipairs(passageOrder) do
		for _, id in ipairs(sectionOrder) do
			local box = plan.sections[id]
			if box and box.passage == passage and within(p, box, 2) then return id end
		end
	end
	-- Route segments preserve the section while its floor has not streamed in, including vertically stacked stairs.
	local chosen, nearest = nil, 55
	for _, row in ipairs(route) do
		local point = segmentPoint(p, vec(row.a), vec(row.b))
		local distance = (p - point).Magnitude
		if distance < nearest and plan.sections[row.section] then chosen, nearest = row.section, distance end
	end
	if chosen then return chosen end
	if player:GetAttribute("Level2_ExitTransition") == true then return "EXIT" end
	return nil
end
local function envelope(entry, target, now, duration)
	if entry.target ~= target then
		entry.from, entry.target, entry.changed, entry.fade = entry.level, target, now, duration
	end
	-- AUDIO_SECTIONS_20261010: a zero authored fade is an immediate transition.
	local t = entry.fade == 0 and 1 or math.clamp((now - entry.changed) / entry.fade, 0, 1)
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
	local sound = templates[key]:Clone()
	sound.Volume, sound.Looped, sound.PlayOnRemove, sound.SoundGroup = 0, looped, false, group
	sound.Parent = parent
	return sound
end
-- AUDIO_SECTIONS_20261010: descriptors are cheap; only nearby rows own a Sound and optional emitter.
local function persistent(row, bed)
	return {row = row, bed = bed, level = 0, target = 0, from = 0, started = false, audible = false}
end
local function createVoice(s, entry, now)
	local row, parent = entry.row, s.bank
	if not entry.bed then
		entry.owner = emitter(s.emitters, row.name or row.key, s.origin + vec(row.position))
		parent = entry.owner
	end
	entry.sound = soundCopy(row.key, parent, true)
	if not entry.bed then
		entry.sound.RollOffMode = Enum.RollOffMode.InverseTapered
		entry.sound.RollOffMinDistance, entry.sound.RollOffMaxDistance = row.min or 8, row.max or 90
	end
	entry.changed, entry.fade, entry.deadline = now, ENTRY_FADE, now + LOAD_TIMEOUT
	entry.level, entry.target, entry.from, entry.started, entry.idleAt = 0, 0, 0, false, nil
	s.liveVoices += 1
end
local function destroyVoice(s, entry)
	if entry.owner then entry.owner:Destroy(); entry.owner = nil else entry.sound:Destroy() end
	entry.sound, entry.started = nil, false
	if entry.audible then entry.audible, s.bedsDirty = false, true end
	s.liveVoices -= 1
end
local function nearby(row, section, before, after)
	return applies(row, section) or applies(row, before) or applies(row, after)
end
local function refreshVoices(s, now)
	local index = orderIndex[s.section]
	local before = index and plan.order[index - 1] or nil
	local after = index and plan.order[index + 1] or nil
	local initialized, loadedBed = s.section ~= nil, false
	for _, entry in ipairs(s.entries) do
		-- A slow connection is not a broken asset: a row that missed its twelve seconds is tried once more twenty
		-- seconds later, so a bed that was merely late does not leave its section on the old ambience all round.
		if entry.failed and not entry.retried and now >= (entry.retryAt or math.huge) then
			entry.failed, entry.retried = false, true
		end
		entry.wanted = not entry.failed and nearby(entry.row, s.section, before, after)
		if entry.wanted and not entry.sound then createVoice(s, entry, now) end
		if entry.sound and not entry.sound.IsLoaded and now >= entry.deadline then
			entry.failed, entry.wanted, entry.retryAt = true, false, now + 20
			skip(entry.row.key, "asset initialization timed out")
			destroyVoice(s, entry)
		end
		if not entry.failed and applies(entry.row, s.section) then
			if not entry.sound or not entry.sound.IsLoaded then initialized = false
			elseif entry.bed then loadedBed = true end
		end
	end
	for _, row in ipairs(shots) do if nearby(row, s.section, before, after) then queueKey(row.key) end end
	s.ready = initialized and loadedBed
end
local function changeSection(s, found, now)
	if found == s.section then return end
	s.section = found
	local section = found and plan.sections[found]
	if section and section.first then s.nextShot = math.min(s.nextShot, now + rng:NextNumber(section.first[1], section.first[2])) end
end
local function newSession(world, subject, now)
	local s = {world = world, generation = world:GetAttribute("Level2_Generation"), origin = originOf(world), subject = subject, created = now,
		entries = {}, shots = {}, recent = {}, lastPlayed = {}, failedShots = {}, liveVoices = 0, shotCount = 0, bedsDirty = true,
		nextShot = now + rng:NextNumber(18, 30)}
	s.bank, s.emitters = Instance.new("Folder"), Instance.new("Folder")
	s.bank.Name, s.bank.Parent = "Level2PoolroomsBeds", SoundService
	s.emitters.Name, s.emitters.Parent = "Level2PoolroomsEmitters", workspace
	s.emitters:SetAttribute("Level2_ClientOnlyAudio", true)
	for _, row in ipairs(beds) do table.insert(s.entries, persistent(row, true)) end
	for _, row in ipairs(loops) do table.insert(s.entries, persistent(row, false)) end
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
	-- AUDIO_SECTIONS_20261010: eligibility loss keeps the existing bounded two-second cleanup.
	for _, entry in ipairs(s.entries) do
		if entry.sound then
			if entry.target == 0 and entry.fade ~= EXIT_FADE then
				entry.from, entry.changed, entry.fade = entry.level, now, EXIT_FADE
			end
			envelope(entry, 0, now, EXIT_FADE)
		end
	end
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
	-- AUDIO_SECTIONS_20261010: session counters never describe clones already destroyed.
	mixDiagnostics(nil)
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
		if entry.sound and entry.started and entry.sound.IsLoaded and entry.row.replaces == "Cascade Water" then
			replacement = math.max(replacement, math.clamp(entry.level / math.max(entry.row.volume, .001), 0, 1))
		end
	end
	c.written = c.original * (1 - replacement)
	c.sound.Volume = c.written
end
local function updatePersistent(s, now)
	for _, entry in ipairs(s.entries) do
		-- AUDIO_SECTIONS_20261010: silent distant rows retain no engine work after their idle grace.
		if not entry.sound then continue end
		local target = not s.exiting and s.ready and applies(entry.row, s.section) and entry.row.volume or 0
		if target > 0 and not entry.started then
			if entry.sound.IsLoaded then
				entry.started = true
				entry.sound.TimePosition = rng:NextNumber() * math.max(0, entry.sound.TimeLength - .1)
				entry.sound:Play()
				entry.changed, entry.from, entry.target = now, 0, 0
			end
		end
		if not entry.started then target = 0 end
		-- AUDIO_SECTIONS_20261010: short passages can rise quickly without changing loop/exit envelopes.
		local fadeIn = entry.bed and entry.row.fade and entry.row.fade[1] or ENTRY_FADE
		local fadeOut = entry.bed and entry.row.fade and entry.row.fade[2] or EXIT_FADE
		envelope(entry, target, now, s.exiting and EXIT_FADE or target > entry.level and fadeIn or fadeOut)
		if entry.started and entry.target == 0 and entry.level <= .00001 then
			entry.sound.Volume = 0
			entry.sound:Stop()
			entry.started = false
		end
		local audible = entry.bed and entry.started and entry.sound.IsPlaying and entry.level > .01
		if entry.audible ~= audible or (audible and entry.diagTarget ~= entry.target) then
			entry.audible, entry.diagTarget, s.bedsDirty = audible, entry.target, true
		end
		if not entry.wanted and entry.level <= .00001 and not entry.started then
			if not entry.idleAt then entry.idleAt = now
			elseif now - entry.idleAt >= IDLE_RELEASE then destroyVoice(s, entry) end
		else entry.idleAt = nil end
	end
	updateCascade(s)
end
-- AUDIO_SECTIONS_20261010: default history stays exactly two; an authored limit opts into a deeper pool-aware history.
local function recentKey(s, key, depth)
	for i = math.max(1, #s.recent - depth + 1), #s.recent do
		if s.recent[i] == key then return true end
	end
	return false
end
local function pickShot(s, now)
	local candidates, fresh, total = {}, {}, 0
	for _, row in ipairs(shots) do
		if applies(row, s.section) and not s.failedShots[row.key] then
			if now - (s.lastPlayed[row.key] or -1e9) >= (row.cooldown or REPEAT_AFTER) then table.insert(candidates, row) end
		end
	end
	local depth = limits.recent ~= nil and math.min(limits.recent, math.max(0, #candidates - 1)) or 2
	for _, row in ipairs(candidates) do if not recentKey(s, row.key, depth) then table.insert(fresh, row) end end
	if #fresh > 0 then candidates = fresh end -- history never permanently silences a section with one eligible clip
	for _, row in ipairs(candidates) do total += row.weight or 1 end
	-- AUDIO_SECTIONS_20261010: rescale only overflowing totals, leaving ordinary/v2 draws unchanged.
	local scale = 1
	if total == math.huge then
		for _, row in ipairs(candidates) do scale = math.max(scale, row.weight or 1) end
		total = 0
		for _, row in ipairs(candidates) do total += (row.weight or 1) / scale end
	end
	local roll = rng:NextNumber() * total
	for _, row in ipairs(candidates) do
		roll -= (row.weight or 1) / scale
		if roll <= 0 then return row end
	end
	return nil
end
local function fireShot(s, row, listener, now)
	-- AUDIO_SECTIONS_20261010: the cap includes loading/cancelled shots, so those voices cannot accumulate.
	if #s.shots >= shotLimit then return end
	local distance = rng:NextNumber((row.dist or {18, 65})[1], (row.dist or {18, 65})[2])
	local angle = rng:NextNumber() * math.pi * 2
	local position = listener + Vector3.new(math.cos(angle) * distance, rng:NextNumber(-1, 4), math.sin(angle) * distance)
	-- AUDIO_SECTIONS_20261010: authored spots are filtered by actual listener distance, including height.
	if row.positions then
		local count, chosen = 0, nil
		local minimum, maximum = row.dist and row.dist[1] or 18, row.dist and row.dist[2] or 65
		for _, spot in ipairs(row.positions) do
			local candidate = s.origin + vec(spot)
			local separation = (candidate - listener).Magnitude
			if separation >= minimum and separation <= maximum then count += 1 end
		end
		if count > 0 then
			local choice = math.min(count, math.floor(rng:NextNumber() * count) + 1)
			for _, spot in ipairs(row.positions) do
				local candidate = s.origin + vec(spot)
				local separation = (candidate - listener).Magnitude
				if separation >= minimum and separation <= maximum then
					choice -= 1
					if choice == 0 then chosen = candidate; break end
				end
			end
		end
		position = chosen or position
	elseif row.position then position = s.origin + vec(row.position) end
	local owner = emitter(s.emitters, "Poolrooms " .. row.key, position)
	local sound = soundCopy(row.key, owner, false)
	-- AUDIO_SECTIONS_20261010: pitch ranges use PlaybackSpeed, preserving the existing audio-position envelope.
	sound.PlaybackSpeed = rng:NextNumber(row.pitch and row.pitch[1] or .98, row.pitch and row.pitch[2] or 1.02)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance, sound.RollOffMaxDistance = row.min or 10, row.max or 110
	table.insert(s.shots, {key = row.key, owner = owner, sound = sound, deadline = now + LOAD_TIMEOUT,
		cooldown = row.cooldown or REPEAT_AFTER, volume = row.volume * rng:NextNumber(.9, 1.05)})
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
			-- AUDIO_SECTIONS_20261010: a delayed clone cannot start inside its key's cooldown.
			if now - (s.lastPlayed[record.key] or -1e9) < record.cooldown then remove = true
			elseif record.sound.IsLoaded and record.sound.TimeLength > 0 then
				record.started, record.progressAt, record.lastPosition = now, now, 0
				record.ended = record.sound.Ended:Connect(function() record.finished = true end)
				record.stopped = record.sound.Stopped:Connect(function() record.interrupted = true end)
				record.sound:Play()
				s.lastPlayed[record.key] = now
				table.insert(s.recent, record.key)
				-- AUDIO_SECTIONS_20261010: count actual Play calls, not draws or loading voices.
				if #s.recent > (limits.recent ~= nil and limits.recent or 2) then table.remove(s.recent, 1) end
				s.shotCount += 1
				attribute("Level2PoolroomsAudioLastShot", record.key)
			elseif now >= record.deadline then
				-- AUDIO_SECTIONS_20261010: one failed shot leaves the rest of its pool usable this session.
				s.failedShots[record.key] = true
				skip(record.key, "one-shot load timed out")
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
					-- AUDIO_SECTIONS_20261010: only an accepted section change can pull its shot deadline earlier.
					if session.pendingCount >= 2 or not session.section then changeSection(session, found, now) end
				else session.pending, session.pendingCount = nil, 0 end
			end
		end
		-- AUDIO_SECTIONS_20261010: loading distant sections no longer gates the participant's session.
		if not session and world then
			session = newSession(world, subject, now)
			session.section = sectionAt(session, root.Position)
		end
		if session and not session.exiting then
			refreshVoices(session, now)
			diagnostics(session.ready, session.ready, session.section)
			if session.ready and not session.exiting and root and now >= session.nextShot and workspace:GetAttribute("RoundActive") == true then
				-- AUDIO_SECTIONS_20261010: failed draws retry soon only in sections that opt into a gap.
				local section = plan.sections[session.section]
				local gap = section and section.gap
				session.nextShot = now + rng:NextNumber(gap and gap[1] or 18, gap and gap[2] or 45)
				local shot = pickShot(session, now)
				if shot then fireShot(session, shot, root.Position, now) end
				if not shot and gap then session.nextShot = now + rng:NextNumber(2, 4) end
			end
		end
	end
	if session then
		updatePersistent(session, now)
		updateShots(session, now)
		-- AUDIO_SECTIONS_20261010: changed membership/targets and counters publish after envelope updates.
		mixDiagnostics(session)
		if session.exiting and now - session.exiting >= EXIT_FADE then destroySession(session) end
	end
end
table.insert(connections, RunService.Heartbeat:Connect(step))
table.insert(connections, script.Destroying:Connect(function()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	-- AUDIO_SECTIONS_20261010: no preload task may outlive its controller.
	cancelPreload()
	if session then destroySession(session) end
	diagnostics(false, false, nil)
	mixDiagnostics(nil)
	group:Destroy()
end))
