-- Offline behavioral harness. The actual LocalScript is embedded into __RUN_CONTROLLER__ by the Python runner.
-- Engine asset decoding, streaming, audible mix and real performance require a Studio/play verification.
local now, objects, services, heartbeat, sourceScript, plan, currentContext
-- AUDIO_SECTIONS_20261010: the runner injects the unchanged live plan and original controller for parity.
local liveV2Plan = __V2_PLAN__
local shippedV3Plan = __V3_PLAN__   -- assets/poolrooms-audio-20261010/plan.json when it exists, else nil
local vector = {}
vector.__index = function(v, key)
	if key == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	return vector[key]
end
vector.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vector.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vector.__mul = function(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
function vector:Dot(b) return self.X * b.X + self.Y * b.Y + self.Z * b.Z end
Vector3 = {new = function(x, y, z) return setmetatable({X = x, Y = y, Z = z}, vector) end}
local nativeTypeof = typeof
typeof = function(value) return getmetatable(value) == vector and "Vector3" or nativeTypeof(value) end
local function signal()
	local callbacks = {}
	return {Connect = function(_, callback)
		local connection = {callback = callback, connected = true}
		function connection:Disconnect() self.connected = false end
		table.insert(callbacks, connection)
		return connection
	end, Fire = function()
		for _, connection in ipairs(callbacks) do if connection.connected then connection.callback(.25) end end
	end}
end
local methods, objectMeta = {}, {}
objectMeta.__index = function(object, key) return methods[key] or object.props[key] end
objectMeta.__newindex = function(object, key, value) object.props[key] = value end
local function object(class, name, parent)
	local result = setmetatable({props = {ClassName = class, Name = name or class, Parent = parent, attrs = {}, Volume = 1,
		IsLoaded = currentContext.loaded, IsPlaying = false, TimeLength = class == "Sound" and 24 or nil,
		TimePosition = 0, PlaybackSpeed = 1, Ended = signal(), Stopped = signal()}}, objectMeta)
	table.insert(objects, result)
	return result
end
function methods:IsA(class) return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part") end
function methods:GetAttribute(name) return self.attrs[name] end
function methods:SetAttribute(name, value)
	-- AUDIO_SECTIONS_20261010: redundant diagnostics writes are observable without mocking client internals.
	if self == currentContext.player and name:find("Level2PoolroomsAudio", 1, true) then
		table.insert(currentContext.attributeWrites, {name = name, value = value, previous = self.attrs[name], at = now})
	end
	self.attrs[name] = value
end
function methods:GetChildren()
	local result = {}
	for _, candidate in ipairs(objects) do if candidate.Parent == self then table.insert(result, candidate) end end
	return result
end
function methods:FindFirstChild(name)
	for _, candidate in ipairs(self:GetChildren()) do if candidate.Name == name then return candidate end end
	return nil
end
methods.WaitForChild = methods.FindFirstChild
function methods:FindFirstChildOfClass(class)
	for _, candidate in ipairs(self:GetChildren()) do if candidate.ClassName == class then return candidate end end
	return nil
end
function methods:IsDescendantOf(ancestor)
	local parent = self.Parent
	while parent do if parent == ancestor then return true end; parent = parent.Parent end
	return false
end
function methods:Destroy()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.IsPlaying, self.Parent, self.destroyed = false, nil, true
end
function methods:Clone()
	local result = object(self.ClassName, self.Name)
	result.owned, result.clone = true, true
	for key, value in pairs(self.props) do
		if key ~= "Parent" and key ~= "attrs" and key ~= "Ended" and key ~= "Stopped" then result[key] = value end
	end
	-- AUDIO_SECTIONS_20261010: clone loading may fail independently of an already loaded template.
	currentContext.cloneCounts[self.Name] = (currentContext.cloneCounts[self.Name] or 0) + 1
	local loading = currentContext.cloneLoads[self.Name]
	if type(loading) == "table" then loading = loading[currentContext.cloneCounts[self.Name]] end
	if loading == false then result.IsLoaded = false
	elseif type(loading) == "number" then result.IsLoaded, result.loadAt = false, now + loading end
	return result
end
function methods:Play()
	assert(self.IsLoaded, "a sound played before loading")
	assert(self.Volume == 0, "a sound began without its attack envelope")
	self.playedAt, self.engineStartAt = now, now + (currentContext.playDelay or 0)
	self.IsPlaying = self.engineStartAt == now
	if self.clone then
		table.insert(currentContext.playLog, {key = self.Name, at = now, looped = self.Looped, sound = self,
			position = self.Parent.Position, pitch = self.PlaybackSpeed})
	end
end
function methods:Stop() self.IsPlaying, self.engineStartAt = false, nil; self.Stopped.Fire() end
Instance = {new = function(class) local result = object(class); result.owned = true; return result end}
Enum = {RaycastFilterType = {Include = "Include"}, RollOffMode = {InverseTapered = "InverseTapered"}}
RaycastParams = {new = function() return {} end}
Random = {new = function() return {NextNumber = function(_, lo, hi)
	if lo == nil then return .5 end
	return (lo + hi) / 2
end, NextInteger = function(_, lo, hi) return math.floor((lo + hi) / 2) end} end}
os = {clock = function() return now end}
local queued
-- AUDIO_SECTIONS_20261010: coroutine preload calls can yield, time out, and be cancelled between batches.
task = {spawn = function(callback)
	local token = {thread = coroutine.create(callback)}; table.insert(queued, token); return token
end, cancel = function(token)
	if not token.cancelled and coroutine.status(token.thread) ~= "dead" then currentContext.cancelledTasks += 1 end
	token.cancelled = true
end}
warn = function(message) table.insert(currentContext.warnings, message) end
game = {GetService = function(_, name) return services[name] end}

local function runController()
__RUN_CONTROLLER__
end
local function runBaseline()
__BASELINE_CONTROLLER__
end
local function setup(options)
	options = options or {}
	currentContext = {loaded = options.loaded ~= false, warnings = {}, maxClones = 0, raycasts = 0, playDelay = options.playDelay or 0,
		cloneLoads = options.cloneLoads or {}, cloneCounts = {}, attributeWrites = {}, playLog = {}, preloadLog = {}, cancelledTasks = 0,
		maxPersistent = 0, maxShots = 0, preloadDelay = options.preloadDelay or 0, preloadStall = options.preloadStall,
		templateLoads = options.templateLoads or {}, quantum = options.quantum or .25}
	local ctx = currentContext
	now, objects, services, queued = 0, {}, {}, {}
	workspace = object("Workspace", "Workspace")
	workspace.SelectedLevel, workspace.attrs = 1, {SelectedLevel = 1, RoundActive = false, WorldGenerated = false}
	function workspace:Raycast()
		ctx.raycasts += 1
		return ctx.hit and {Instance = ctx.hit, Position = ctx.hit.Position} or nil
	end
	services.ReplicatedStorage, services.SoundService = object("Service", "ReplicatedStorage"), object("Service", "SoundService")
	local libraryFolder = object("Folder", "Level2Poolrooms", services.ReplicatedStorage)
	local library = object("Folder", "Sounds", libraryFolder)
	local value = object("StringValue", "Plan", libraryFolder); value.Value = "mock JSON decoded to authored fixture"
	ctx.library = library
	services.HttpService = {JSONDecode = function()
		if options.invalidJson then error("invalid fixture JSON") end
		return plan
	end}
	heartbeat = signal(); services.RunService = {Heartbeat = heartbeat}
	services.ContentProvider = {PreloadAsync = function(_, sounds)
		local keys = {}; for _, sound in ipairs(sounds) do table.insert(keys, sound.Name) end
		local record = {keys = keys, at = now}; table.insert(ctx.preloadLog, record)
		local finishAt = now + ctx.preloadDelay
		while ctx.preloadStall or now < finishAt do coroutine.yield() end
		for _, sound in ipairs(sounds) do
			if ctx.loaded and ctx.templateLoads[sound.Name] ~= false then sound.IsLoaded = true end
		end
		record.completed = now
	end}
	ctx.player = object("Player", "LocalPlayer"); ctx.player.UserId = 1
	ctx.watched = object("Player", "WatchedPlayer"); ctx.watched.UserId = 2
	ctx.other = object("Player", "OtherWatchedPlayer"); ctx.other.UserId = 3
	services.Players = {LocalPlayer = ctx.player, GetPlayerByUserId = function(_, id) return id == 2 and ctx.watched or id == 3 and ctx.other or nil end}
	local function body(player)
		local character = object("Model", "Character", workspace)
		local humanoid = object("Humanoid", "Humanoid", character); humanoid.Health = 100
		local root = object("Part", "HumanoidRootPart", character); root.Position = Vector3.new(1000, 100, 0)
		player.Character = character
		return root, humanoid
	end
	ctx.root, ctx.humanoid = body(ctx.player)
	ctx.watchedRoot, ctx.watchedHumanoid = body(ctx.watched)
	ctx.otherRoot, ctx.otherHumanoid = body(ctx.other)
	ctx.world = object("Model", "Level 2 Generated World", workspace)
	ctx.world.attrs = {Level2NewMap = true, Origin = Vector3.new(1000, 100, 0), Level2_Generation = 1}
	ctx.collision = object("Model", "Collision", ctx.world)
	local water = object("Folder", "Water FX", ctx.world)
	local cascadeOwner = object("Part", "Cascade Sound", water)
	ctx.cascade = object("Sound", "Cascade Water", cascadeOwner); ctx.cascade.Volume = .7
	plan = {origin = {1000, 100, 0}, order = {"P1", "P2", "A1", "A2", "A6", "EXIT"}, sections = {
		P1 = {min = {-30, -40, -10}, max = {30, -20, 10}, passage = true},
		P2 = {min = {90, -10, -10}, max = {130, 10, 10}, passage = true},
		A1 = {min = {-80, -50, -80}, max = {80, 10, 80}, passage = false},
		A2 = {min = {200, -10, -80}, max = {300, 10, 80}, passage = false},
		A6 = {min = {400, -10, -80}, max = {500, 10, 80}, passage = false},
		EXIT = {min = {500, -10, -10}, max = {510, 10, 10}, passage = true}},
		beds = {{key = "bed_hall", volume = .2, sections = {"A1"}},
			{key = "bed_water", volume = .16, sections = {"P2", "A2"}},
			{key = "bed_service", volume = .12, sections = {"P1", "A6", "EXIT"}}},
		loops = {{key = "loop_weir", name = "A1 Pump", position = {0, 0, 0}, volume = .2, min = 8, max = 90, sections = {"A1"}},
			{key = "loop_weir", name = "P2 Cascade", position = {110, 0, 0}, volume = .25, min = 8, max = 90, sections = {"P2"}, replaces = "Cascade Water"},
			{key = "loop_lion", name = "A2 Lions", position = {250, 0, 0}, volume = .2, min = 8, max = 90, sections = {"A2"}},
			{key = "bed_service", name = "A6 Service", position = {450, 0, 0}, volume = .1, min = 8, max = 90, sections = {"A6"}}},
		shots = {}, route = {{section = "A2", a = {250, 0, 0}, b = {350, 0, 0}}}}
	for _, key in ipairs({"shot_drip", "shot_pipe", "shot_splash", "shot_creak"}) do
		table.insert(plan.shots, {key = key, sections = {"*"}, volume = .2, dist = {20, 60}})
	end
	-- AUDIO_SECTIONS_20261010: fixtures use their actual key set, including intentionally absent templates.
	plan = options.plan or plan; ctx.plan = plan
	local keys = {}
	if type(plan) == "table" then
		for _, rows in ipairs({plan.beds or {}, plan.loops or {}, plan.shots or {}}) do
			for _, row in ipairs(rows) do
				if not keys[row.key] then
					keys[row.key] = true
					if not options.missing or not options.missing[row.key] then
						local sound = object("Sound", row.key, library)
						sound.SoundId = (options.invalidIds and options.invalidIds[row.key]) or "rbxassetid://123"
						if ctx.templateLoads[row.key] == false then sound.IsLoaded = false end
						if row.key:find("shot_", 1, true) then sound.TimeLength = options.shotLength or 8 end
					end
				end
			end
		end
	end
	sourceScript = object("LocalScript", "Poolrooms Ambience"); sourceScript.Destroying = signal(); script = sourceScript
	local controller = options.baseline and runBaseline or runController
	controller()
	function ctx:tick(seconds)
		local remaining = seconds
		while remaining > .0000001 do
			local delta = math.min(self.quantum, remaining); remaining -= delta
			now += delta
			for _, sound in ipairs(objects) do if sound.loadAt and now >= sound.loadAt then sound.IsLoaded, sound.loadAt = true, nil end end
			for _, sound in ipairs(objects) do
				if sound:IsA("Sound") and not sound.destroyed and sound.engineStartAt and now >= sound.engineStartAt then
					sound.IsPlaying = true
					if not self.stalled then sound.TimePosition += delta * sound.PlaybackSpeed end
					if sound.TimePosition >= sound.TimeLength then
						if sound.Looped then sound.TimePosition %= sound.TimeLength else
							sound.TimePosition, sound.IsPlaying, sound.engineStartAt = 0, false, nil
							sound.Ended.Fire()
						end
					end
				end
			end
			local pending = queued; queued = {}
			for _, token in ipairs(pending) do
				if not token.cancelled then
					local ok, message = coroutine.resume(token.thread); assert(ok, message)
					if coroutine.status(token.thread) ~= "dead" then table.insert(queued, token) end
				end
			end
			heartbeat.Fire()
			local clones = 0
			for _, candidate in ipairs(objects) do
				if candidate:IsA("Sound") and not candidate.destroyed and candidate ~= self.cascade and not candidate:IsDescendantOf(library) then clones += 1 end
			end
			self.liveClones, self.maxClones = clones, math.max(self.maxClones, clones)
			local persistent, shots = 0, 0
			for _, candidate in ipairs(objects) do
				if candidate.clone and not candidate.destroyed then
					if candidate.Looped then persistent += 1 else shots += 1 end
				end
			end
			self.maxPersistent, self.maxShots = math.max(self.maxPersistent, persistent), math.max(self.maxShots, shots)
		end
	end
	function ctx:enter()
		workspace:SetAttribute("SelectedLevel", 2); workspace:SetAttribute("RoundActive", true); workspace:SetAttribute("WorldGenerated", true)
		self.player:SetAttribute("InRound", true); self:tick(1)
	end
	function ctx:load()
		self.loaded = true
		for _, candidate in ipairs(objects) do if candidate:IsA("Sound") then candidate.IsLoaded = true end end
	end
	function ctx:playing()
		local result = {}
		for _, candidate in ipairs(objects) do if candidate:IsA("Sound") and candidate.IsPlaying then table.insert(result, candidate) end end
		return result
	end
	function ctx:sound(name)
		for _, candidate in ipairs(objects) do if candidate.Name == name and candidate:IsA("Sound") and not candidate.destroyed and not candidate:IsDescendantOf(library) then return candidate end end
		return nil
	end
	function ctx:finish()
		sourceScript.Destroying.Fire()
		for _, candidate in ipairs(objects) do assert(not candidate.owned or candidate.destroyed, "owned instance leaked: " .. candidate.Name) end
		for _, token in ipairs(queued) do assert(token.cancelled or coroutine.status(token.thread) == "dead", "preload task leaked") end
	end
	function ctx:voices()
		local result = {}; for _, candidate in ipairs(objects) do if candidate.clone and not candidate.destroyed and candidate.Looped then table.insert(result, candidate) end end
		return result
	end
	function ctx:shots()
		local result = {}; for _, record in ipairs(self.playLog) do if not record.looped then table.insert(result, record) end end
		return result
	end
	function ctx:section(id)
		if not self.hit then self.hit = object("Part", "Fixture Floor", self.collision) end
		self.hit.Position = self.root.Position; self.hit:SetAttribute("Area", id)
	end
	return ctx
end
local function near(actual, expected) assert(math.abs(actual - expected) < .0001, tostring(actual) .. " != " .. tostring(expected)) end

local ctx = setup()
ctx:tick(1); assert(#ctx:playing() == 0, "lobby leak")
workspace:SetAttribute("SelectedLevel", 2); ctx:tick(1)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == false and #ctx:playing() == 0, "nonparticipant inherited audio")
ctx:enter(); ctx:tick(3)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == "A1")
near(ctx:sound("bed_hall").Volume, .2)
ctx.root.Position = Vector3.new(1000, 70, 0); ctx:tick(1)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == "P1", "stacked passage box priority failed")
ctx.root.Position = Vector3.new(1340, 100, 0); ctx:tick(1)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == "A2", "streamed-floor route fallback failed")
ctx.root.Position = Vector3.new(1110, 100, 0); ctx:tick(4)
near(ctx.cascade.Volume, 0)
ctx.player:SetAttribute("InRound", false); ctx:tick(.25)
assert(#ctx:playing() > 0, "sounds were removed before outgoing fade")
ctx:tick(1); assert(#ctx:playing() > 0, "fade ended early")
ctx:tick(1); assert(#ctx:playing() == 0, "audio remained after outgoing fade")
near(ctx.cascade.Volume, .7); assert(ctx.maxClones <= 9, "persistent/shot budget exceeded")
ctx:finish()
print("PASS lobby entitlement, loaded start, exact entry/exit fades, stacked passage/route fallback, cascade fallback, budget")

ctx = setup({loaded = false}); ctx:enter(); ctx:tick(3)
assert(#ctx:playing() == 0 and ctx.player:GetAttribute("Level2PoolroomsAudioReady") == false, "asset load created dead zone")
ctx:load(); ctx:tick(4); assert(#ctx:playing() > 0 and ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true)
ctx:finish()
print("PASS unloaded pack retains fallback; audio begins only after asset initialization")

ctx = setup(); ctx:enter(); ctx:tick(3)
ctx.player:SetAttribute("Escaped", true); ctx.player:SetAttribute("Spectating", true); ctx.player:SetAttribute("SpectateTargetUserId", 2)
ctx.watched:SetAttribute("InRound", true); ctx.watchedRoot.Position = Vector3.new(1250, 100, 0); ctx:tick(1)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == "A2", "spectator did not follow living subject")
ctx.watchedHumanoid.Health = 0; ctx:tick(2.5)
assert(#ctx:playing() == 0 and ctx.player:GetAttribute("Level2PoolroomsAudioActive") == false, "dead target retained mix")
ctx:finish()
print("PASS escaped spectator follows eligible living subject; no-survivor state fades out")

ctx = setup(); ctx:enter(); ctx:tick(3)
ctx.world:SetAttribute("Origin", Vector3.new(2000, 100, 0)); ctx.world:SetAttribute("Level2_Generation", 2)
ctx.root.Position = Vector3.new(2000, 100, 0); ctx:tick(5)
local pump = ctx:sound("loop_weir"); assert(pump.Parent.Position.X >= 2000, "emitter kept stale origin")
assert(ctx.maxClones <= 9, "generations overlapped persistent budget")
ctx:finish(); assert(#ctx:playing() == 0)
print("PASS generation/origin replacement cleans previous session; controller destruction releases owned state")

ctx = setup(); ctx:enter()
while not ctx.player:GetAttribute("Level2PoolroomsAudioLastShot") do ctx:tick(.25) end
local firstShot = ctx:sound(ctx.player:GetAttribute("Level2PoolroomsAudioLastShot"))
near(firstShot.Volume, 0)
ctx:tick(.25); assert(firstShot.Volume > 0, "one-shot attack never rose")
ctx:tick(7.5); assert(firstShot.Volume < .02 and not firstShot.destroyed, "one-shot did not taper before its natural end")
ctx:tick(.5); assert(firstShot.destroyed, "finished shot emitter was retained")
ctx:finish()
print("PASS one-shot opens at silence and tapers before natural file end")

ctx = setup({playDelay = 4}); ctx:enter()
while not ctx.player:GetAttribute("Level2PoolroomsAudioLastShot") do ctx:tick(.25) end
local delayedShot = ctx:sound(ctx.player:GetAttribute("Level2PoolroomsAudioLastShot"))
ctx:tick(3); assert(not delayedShot.destroyed and delayedShot.TimePosition == 0 and delayedShot.Volume == 0,
	"delayed engine start advanced attack or destroyed the voice")
ctx:tick(5); assert(not delayedShot.destroyed and delayedShot.TimePosition > 0,
	"voice was cut at its wall-clock duration before real audio finished")
ctx.stalled = true
local stalledPosition = delayedShot.TimePosition
ctx:tick(4); assert(not delayedShot.destroyed and delayedShot.TimePosition == stalledPosition,
	"stalled voice was truncated at wall-clock duration")
ctx.stalled = false; ctx:tick(5); assert(delayedShot.destroyed, "resumed voice did not finish naturally")
ctx:finish()
print("PASS delayed engine Play and short stall preserve actual audio until natural completion")

ctx = setup(); ctx:enter()
while not ctx.player:GetAttribute("Level2PoolroomsAudioLastShot") do ctx:tick(.25) end
local failedShot = ctx:sound(ctx.player:GetAttribute("Level2PoolroomsAudioLastShot"))
ctx:tick(.5); ctx.stalled = true
ctx:tick(12); assert(not failedShot.destroyed and failedShot.Volume > 0, "liveness timeout bypassed cancellation fade")
ctx:tick(.5); assert(not failedShot.destroyed and failedShot.Volume > 0, "cancelled stalled voice faded too soon")
ctx:tick(.5); assert(failedShot.destroyed, "stalled voice was not cleaned after cancellation reached zero")
ctx:finish()
print("PASS stalled playback has bounded cleanup through a complete cancellation fade")

ctx = setup({shotLength = 100}); ctx:enter(); ctx:tick(110)
local shots = 0
for _, sound in ipairs(ctx:playing()) do if sound.Name:find("shot_", 1, true) then shots += 1 end end
assert(shots <= 2 and ctx.maxClones <= 66, "one-shot concurrency exceeded bounds")
assert(ctx.player:GetAttribute("Level2PoolroomsAudioLastShot") ~= nil, "random scheduler never played")
ctx.player:SetAttribute("InRound", false); ctx:tick(1.5)
for _, sound in ipairs(ctx:playing()) do assert(not sound.Name:find("shot_", 1, true), "cancelled shot survived one-second tail") end
ctx:tick(1); assert(#ctx:playing() == 0)
ctx:finish()
print("PASS rare random scheduler, long-clip concurrency cap and cancelled-shot fade")

-- AUDIO_SECTIONS_20261010: fixtures retain real row ownership and use collision Area as the primary detector.
local function smallPlan()
	return {origin = {1000, 100, 0}, order = {"A", "B", "C"}, sections = {
		A = {min = {-50, -10, -50}, max = {50, 10, 50}, passage = false},
		B = {min = {100, -10, -50}, max = {150, 10, 50}, passage = false},
		C = {min = {200, -10, -50}, max = {250, 10, 50}, passage = false}},
		beds = {{key = "bed_a", sections = {"A"}, volume = .5},
			{key = "bed_b", sections = {"B"}, volume = .4}, {key = "bed_c", sections = {"C"}, volume = .3}},
		loops = {}, shots = {}, route = {}}
end
local function addShots(fixture, count)
	for i = 1, count do table.insert(fixture.shots, {key = "shot_" .. i, sections = {"*"}, volume = .2, cooldown = 0}) end
end
local function largePlan()
	local fixture = {origin = {1000, 100, 0}, order = {"S", "P0", "A1", "P1", "A3", "P2", "A4", "P3", "A2", "P4", "A5", "P5", "A6", "EXIT"},
		sections = {}, beds = {}, loops = {}, shots = {}, route = {}}
	for i, id in ipairs(fixture.order) do
		fixture.sections[id] = {min = {i * 100, -10, -20}, max = {i * 100 + 50, 10, 20}, passage = id:sub(1, 1) ~= "A", gap = {5, 9}, first = {2, 4}}
		if id ~= "EXIT" then table.insert(fixture.beds, {key = "bed_" .. id, sections = id == "A6" and {"A6", "EXIT"} or {id}, volume = .3}) end
	end
	for i, index in ipairs({3, 5, 6, 7, 8, 9, 11, 13}) do
		table.insert(fixture.loops, {key = "loop_" .. i, sections = {fixture.order[index]}, position = {index * 100, 0, 0}, volume = .2})
	end
	for i = 1, 50 do
		local index = (i - 1) % 13 + 1
		table.insert(fixture.shots, {key = "shot_large_" .. i, sections = {fixture.order[index]}, volume = .2, cooldown = 10})
	end
	return fixture
end
local function wantedKeys(fixture, id)
	local index = table.find(fixture.order, id)
	local result = {}
	for _, rows in ipairs({fixture.beds, fixture.loops}) do
		for _, row in ipairs(rows) do
			if table.find(row.sections, "*") or table.find(row.sections, id)
				or (index and fixture.order[index - 1] and table.find(row.sections, fixture.order[index - 1]))
				or (index and fixture.order[index + 1] and table.find(row.sections, fixture.order[index + 1])) then
				result[row.key] = (result[row.key] or 0) + 1
			end
		end
	end
	return result
end
local function assertWanted(ctx, id)
	local expected, actual = wantedKeys(ctx.plan, id), {}
	for _, sound in ipairs(ctx:voices()) do actual[sound.Name] = (actual[sound.Name] or 0) + 1 end
	for key, count in pairs(expected) do assert(actual[key] == count, "wanted voice missing: " .. key) end
	for key, count in pairs(actual) do assert(expected[key] == count, "unwanted persistent survived: " .. key) end
	assert(ctx.player:GetAttribute("Level2PoolroomsAudioVoices") == #ctx:voices(), "voices diagnostic diverged")
end
local function warningsFor(ctx, key)
	local count = 0; for _, message in ipairs(ctx.warnings) do if message:find(key, 1, true) then count += 1 end end
	return count
end
local function at(ctx, target) ctx:tick(target - now) end

local fixture = largePlan()
assert(#fixture.beds + #fixture.loops == 21 and #fixture.shots == 50)
ctx = setup({plan = fixture, shotLength = 2}); ctx:section("S"); ctx:enter(); ctx:tick(4)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true, "v3 pack rejected more than nine keys/rows")
near(ctx:sound("bed_S").Volume, .3); assertWanted(ctx, "S")
for _, id in ipairs(fixture.order) do
	ctx:section(id); ctx:tick(40)
	assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == id, "walk did not select " .. id)
	assertWanted(ctx, id)
	for _, sound in ipairs(ctx:voices()) do
		if sound.Name:sub(1, 5) == "loop_" and not table.find((function()
			for _, row in ipairs(fixture.loops) do if row.key == sound.Name then return row.sections end end
			return {}
		end)(), id) then assert(not sound.IsPlaying, "neighbour-only spatial loop played") end
	end
end
assert(ctx.maxPersistent <= 8 and ctx.maxClones <= 10, "walk exceeded eight retained persistent + two shot voices")
assert(#ctx:shots() > 20, "large pack randoms never played")
local walkClones, walkPersistent = ctx.maxClones, ctx.maxPersistent
ctx:finish()
print("PASS v3 71-key/21-persistent pack starts; route creates/retires voices; walk live clone bound=10 (observed=" .. walkClones .. ", persistent=" .. walkPersistent .. ")")

fixture = smallPlan(); table.insert(fixture.beds, {key = "bed_missing", sections = {"A"}, volume = .5})
table.insert(fixture.loops, {key = "loop_invalid", sections = {"A"}, volume = .2, position = {0, 0, 0}})
table.insert(fixture.shots, {key = "shot_missing", sections = {"A"}, volume = .2})
ctx = setup({plan = fixture, missing = {bed_missing = true, shot_missing = true}, invalidIds = {loop_invalid = "invalid"}})
ctx:section("A"); ctx:enter(); ctx:tick(4)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and ctx:sound("bed_a").IsPlaying)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSkipped") == "bed_missing,loop_invalid,shot_missing", "skipped keys were not sorted/published")
assert(warningsFor(ctx, "bed_missing") == 1 and warningsFor(ctx, "loop_invalid") == 1 and warningsFor(ctx, "shot_missing") == 1)
local late = object("Sound", "bed_missing", ctx.library); late.SoundId = "rbxassetid://456"; late.IsLoaded = true
ctx:tick(40); assert(not ctx:sound("bed_missing"), "startup-skipped row silently reentered after a late template")
assert(warningsFor(ctx, "bed_missing") == 1)
ctx:finish()
print("PASS missing/invalid templates skip rows, warn once, publish sorted diagnostics; late template stays startup-skipped")

fixture = smallPlan(); table.insert(fixture.beds, {key = "bed_never", sections = {"A"}, volume = .5})
ctx = setup({plan = fixture, cloneLoads = {bed_never = false}}); ctx:section("A"); ctx:enter(); ctx:tick(10)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == false, "current uninitialized row did not gate handover before deadline")
ctx:tick(5)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and ctx:sound("bed_a").IsPlaying, "failed layered bed silenced usable bed")
assert(ctx:sound("bed_never") == nil and ctx.player:GetAttribute("Level2PoolroomsAudioSkipped") == "bed_never")
assert(warningsFor(ctx, "bed_never") == 1); ctx:tick(15); assert(warningsFor(ctx, "bed_never") == 1)
ctx:finish()
fixture = smallPlan()
ctx = setup({plan = fixture, cloneLoads = {bed_a = false}}); ctx:section("A"); ctx:enter(); ctx:tick(20)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == false and ctx.player:GetAttribute("Level2PoolroomsAudioActive") == false,
	"all failed current beds took ambience ownership from legacy")
assert(#ctx:playing() == 0 and ctx.player:GetAttribute("Level2PoolroomsAudioSkipped") == "bed_a")
ctx:section("B"); ctx:tick(4); assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and ctx:sound("bed_b").IsPlaying)
ctx:finish()
print("PASS per-row 12-second load failure releases a usable layered bed; no loaded current bed retains legacy gate")

fixture = smallPlan(); addShots(fixture, 4)
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter()
at(ctx, 24); assert(#ctx:shots() == 0); at(ctx, 24.25); near(ctx:shots()[1].at, 24.25)
ctx:section("B"); ctx:tick(1); at(ctx, 55.75); near(ctx:shots()[2].at, 55.75)
at(ctx, 87.25); near(ctx:shots()[3].at, 87.25); ctx:finish()
fixture = smallPlan(); addShots(fixture, 4); fixture.sections.A.gap, fixture.sections.A.first = {4, 6}, {1, 3}
fixture.sections.B.gap, fixture.sections.B.first = {4, 6}, {1, 3}
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter()
at(ctx, 10); assert(#ctx:shots() == 0, "initial section.first replaced the unchanged session first delay")
ctx:section("B"); ctx:tick(.5); local enteredB = now
at(ctx, enteredB + 1.75); assert(#ctx:shots() == 0)
at(ctx, enteredB + 2); near(ctx:shots()[1].at, enteredB + 2)
ctx:section("C"); ctx:tick(.5); at(ctx, enteredB + 7); near(ctx:shots()[2].at, enteredB + 7)
at(ctx, enteredB + 38.5); near(ctx:shots()[3].at, enteredB + 38.5); ctx:finish()
fixture = smallPlan(); addShots(fixture, 4); fixture.sections.B.first = {40, 60}
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter(); at(ctx, 10); ctx:section("B"); ctx:tick(.5)
at(ctx, 24.25); near(ctx:shots()[1].at, 24.25); ctx:finish()
print("PASS section gap/first pull deadlines earlier only; no-field sections preserve 24-second first/31.5-second default schedule")

fixture = smallPlan(); addShots(fixture, 1); fixture.shots[1].cooldown = 10; fixture.sections.A.gap = {2, 2}
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter(); at(ctx, 35.25)
assert(#ctx:shots() == 2); near(ctx:shots()[1].at, 24.25); near(ctx:shots()[2].at, 35.25); ctx:finish()
fixture = smallPlan(); addShots(fixture, 1); fixture.shots[1].cooldown = nil
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter(); at(ctx, 118.75)
assert(#ctx:shots() == 2); near(ctx:shots()[1].at, 24.25); near(ctx:shots()[2].at, 118.75); ctx:finish()
print("PASS per-key START cooldown and 3-second empty-draw retries for custom gap; no gap retains old failed-draw spacing")

fixture = smallPlan(); addShots(fixture, 1)
fixture.beds[1].fade = {1.2, .8}; fixture.shots[1].dist = {10, 30}
fixture.shots[1].positions, fixture.shots[1].pitch = {{5, 0, 0}, {20, 0, 0}, {40, 0, 0}}, {.8, .9}
ctx = setup({plan = fixture, quantum = .05}); ctx:section("A"); ctx:enter(); ctx:tick(.5); near(ctx:sound("bed_a").Volume, .5)
ctx:section("B"); ctx:tick(1.6); near(ctx:sound("bed_a").Volume, 0)
ctx:section("A"); ctx:tick(2); at(ctx, 25)
local authored = ctx:shots()[1]; near(authored.position.X, 1020); near(authored.position.Y, 100); near(authored.pitch, .85)
ctx:finish()
fixture = smallPlan(); addShots(fixture, 1); fixture.shots[1].dist = {10, 30}; fixture.shots[1].positions = {{100, 0, 0}}
ctx = setup({plan = fixture}); ctx:section("A"); ctx:enter(); at(ctx, 24.25)
local fallback = ctx:shots()[1]; near(fallback.position.X, 980); near(fallback.position.Y, 101.5); near(fallback.position.Z, 0); near(fallback.pitch, 1)
ctx:finish()
fixture = smallPlan(); addShots(fixture, 1); fixture.shots[1].position = {7, 8, 9}
ctx = setup({plan = fixture}); ctx:section("A"); ctx:enter(); at(ctx, 24.25)
local fixed = ctx:shots()[1]; near(fixed.position.X, 1007); near(fixed.position.Y, 108); near(fixed.position.Z, 9)
ctx:finish()
print("PASS bed fade seconds, ranged origin-relative authored positions, random fallback, legacy single position and pitch range")

-- AUDIO_SECTIONS_20261010: compare audible state with the unchanged original, rather than a second implementation of it.
local function v2Trace(baseline)
	local context = setup({plan = liveV2Plan, baseline = baseline})
	context:section("S"); context:enter()
	local trace = {}
	for _, id in ipairs(liveV2Plan.order) do
		context:section(id)
		for _ = 1, 160 do
			context:tick(.25)
			local voices = {}
			for _, sound in ipairs(context:voices()) do
				if sound.IsPlaying and sound.Volume > .000001 then
					local owner = sound.Parent.Position and sound.Parent.Name or "bed"
					table.insert(voices, sound.Name .. "/" .. owner .. "=" .. string.format("%.6f", sound.Volume))
				end
			end
			table.sort(voices)
			table.insert(trace, table.concat(voices, ",") .. ";" .. tostring(context.player:GetAttribute("Level2PoolroomsAudioReady"))
				.. ";" .. tostring(context.player:GetAttribute("Level2PoolroomsAudioActive")) .. ";" .. string.format("%.6f", context.cascade.Volume))
		end
	end
	local shots = {}
	for _, record in ipairs(context:shots()) do
		table.insert(shots, record.key .. "@" .. record.at .. "/" .. record.pitch .. "/"
			.. string.format("%.6f,%.6f,%.6f", record.position.X, record.position.Y, record.position.Z))
	end
	context:finish()
	return trace, shots
end
local originalTrace, originalShots = v2Trace(true)
local newTrace, newShots = v2Trace(false)
assert(#originalTrace == #newTrace and #originalShots == #newShots)
for i, sample in ipairs(originalTrace) do assert(sample == newTrace[i], "live v2 audible state differs at sample " .. i .. ": " .. sample .. " vs " .. newTrace[i]) end
for i, shot in ipairs(originalShots) do assert(shot == newShots[i], "live v2 shot differs at " .. i .. ": " .. shot .. " vs " .. newShots[i]) end
assert(#newShots > 5)
print("PASS actual live v2 plan matches original client across " .. #newTrace .. " quarter-second bed/loop-volume/gate/cascade samples and " .. #newShots .. " shot key/time/position/pitch events")

fixture = smallPlan(); addShots(fixture, 5); fixture.limits = {recent = 4}; fixture.sections.A.gap = {2, 2}
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter(); at(ctx, 32.25)
local played = {}; for _, record in ipairs(ctx:shots()) do assert(not played[record.key], "recent=4 repeated within five-key pool"); played[record.key] = true end
assert(#ctx:shots() == 5); ctx:finish()
fixture = smallPlan(); addShots(fixture, 5); fixture.sections.A.gap = {1, 1}; fixture.limits = {shots = 4}
ctx = setup({plan = fixture, shotLength = 100}); ctx:section("A"); ctx:enter(); ctx:tick(40)
assert(ctx.maxShots == 4 and ctx.maxClones <= 7, "authored four-shot cap diverged"); ctx:finish()
for _, limits in ipairs({{persistent = 2}, {keys = 2}}) do
	fixture = smallPlan(); fixture.limits = limits; ctx = setup({plan = fixture}); ctx:section("A"); ctx:enter(); ctx:tick(4)
	assert(#ctx:playing() == 0 and #ctx:voices() == 0, "lower plan bound ignored"); ctx:finish()
end
ctx = setup({plan = smallPlan(), invalidJson = true}); ctx:enter(); assert(#ctx:voices() == 0); ctx:finish()
fixture = smallPlan(); fixture.beds = {}; ctx = setup({plan = fixture}); ctx:enter(); assert(#ctx:voices() == 0); ctx:finish()
fixture = smallPlan(); ctx = setup({plan = fixture}); ctx:section("A"); ctx:enter(); ctx:tick(4)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioBeds") == "bed_a=0.50")
local writes = #ctx.attributeWrites; ctx:tick(3); assert(#ctx.attributeWrites == writes, "unchanged diagnostics were rebuilt/published")
for _, write in ipairs(ctx.attributeWrites) do
	if write.value ~= nil and write.at > 0 then assert(write.value ~= write.previous, "diagnostic value was set without change: " .. write.name) end
end
ctx:finish()
print("PASS optional limits lower bounds; up to four shots; explicit recent depth; invalid/no-bed startup; diagnostics publish changes only")

-- AUDIO_SECTIONS_20261010: adversarial section and subject churn must settle back to the wanted rows without a clone leak.
fixture = largePlan()
ctx = setup({plan = fixture, quantum = .05, shotLength = 2}); ctx:section("S"); ctx:enter()
for i = 1, 200 do ctx:section(fixture.order[(i - 1) % #fixture.order + 1]); ctx:tick(.3) end
ctx:section("A6"); ctx:tick(36); assertWanted(ctx, "A6")
assert(ctx.maxPersistent <= 21 and ctx.maxClones <= 23, "rapid section churn escaped authored ownership bounds")
ctx:finish()
fixture.limits = {shots = 0}
ctx = setup({plan = fixture, shotLength = 2}); ctx:section("S"); ctx:enter()
for i = 1, 200 do ctx:section(fixture.order[(i - 1) % #fixture.order + 1]); ctx:tick(1) end
ctx:section("S"); ctx:tick(36); assertWanted(ctx, "S")
assert(#ctx:voices() == 2 and ctx.liveClones == 2, "200 section changes did not settle to one initial visit")
ctx:finish()
fixture = smallPlan(); fixture.order = {"A", "C"}
ctx = setup({plan = fixture}); ctx:section("B"); ctx:enter(); ctx:tick(4)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == "B" and ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true)
assertWanted(ctx, "B"); ctx:finish()
fixture = smallPlan(); addShots(fixture, 1); fixture.sections.A.gap = {2, 2}
ctx = setup({plan = fixture}); ctx:section("A")
ctx.player:SetAttribute("Spectating", true); ctx.player:SetAttribute("SpectateTargetUserId", 2); ctx.watched:SetAttribute("InRound", true)
ctx:enter(); at(ctx, 24.5)
local switchingShot = ctx:shots()[1].sound
ctx:section("B"); ctx:tick(1)
assert(ctx:sound("bed_b").Volume > 0 and ctx:sound("bed_b").Volume < .4, "swap fixture was not midway through a bed fade")
ctx.other:SetAttribute("InRound", true); ctx.otherRoot.Position = Vector3.new(1225, 100, 0)
ctx.player:SetAttribute("SpectateTargetUserId", 3); ctx:section("C")
ctx:tick(.5); assert(not switchingShot.destroyed and switchingShot.Volume > 0, "spectate swap bypassed shot cancellation fade")
ctx:tick(.75); assert(switchingShot.destroyed); ctx:tick(3)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSection") == "C" and ctx:sound("bed_c").IsPlaying)
ctx:finish()
print("PASS break attempts: 0.3-second changes for a minute; 200 settled changes; omitted-order collision section; spectate swap during fade; cleanup owns all instances")

fixture = largePlan()
ctx = setup({plan = fixture, preloadDelay = 2, shotLength = 2}); ctx:section("S"); ctx:enter(); ctx:tick(30)
local preloaded = {}; for _, batch in ipairs(ctx.preloadLog) do
	assert(#batch.keys <= 3 and batch.completed, "preload batch unbounded or unfinished")
	for _, key in ipairs(batch.keys) do table.insert(preloaded, key) end
end
assert(preloaded[1] == "bed_S" and preloaded[2] == "bed_P0" and preloaded[3] == "bed_A1", "first three route section beds were not prioritized")
local allowedShots = {S = true, P0 = true}
for _, key in ipairs(preloaded) do
	if key:sub(1, 11) == "shot_large_" then
		local row
		for _, shot in ipairs(fixture.shots) do if shot.key == key then row = shot end end
		assert(row and allowedShots[row.sections[1]], "unvisited shot section was eagerly preloaded")
	end
end
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and #ctx:playing() > 0, "yielding preload blocked heartbeat audio")
ctx:section("A1"); ctx:tick(20)
local reachedA1 = false
for _, batch in ipairs(ctx.preloadLog) do for _, key in ipairs(batch.keys) do
	if key == "shot_large_3" then reachedA1 = true end
end end
assert(reachedA1, "current/neighbour shots were not queued on section change"); ctx:finish()
ctx = setup({plan = largePlan(), preloadStall = true}); ctx:section("S"); ctx:enter(); ctx:tick(30)
assert(#ctx.preloadLog >= 2 and ctx.cancelledTasks >= 2, "stalled batch did not get its own bounded deadline")
assert(ctx.preloadLog[2].at - ctx.preloadLog[1].at >= 12, "preload deadline applied globally instead of per batch")
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true, "stalled preload silenced loaded current beds")
ctx:finish(); assert(ctx.cancelledTasks >= 3, "cleanup did not cancel pending preload")
print("PASS route-priority batches <=3, lazy shot preload, nonblocking yields, per-batch 12-second deadlines and clean cancellation")

-- AUDIO_SECTIONS_20261010: an eligibility exit must finish the old two-second handover even during a longer authored section fade.
fixture = smallPlan(); fixture.beds[1].fade = {1.2, 20}
ctx = setup({plan = fixture}); ctx:section("A"); ctx:enter(); ctx:tick(3)
ctx:section("B"); ctx:tick(1)
local fadingBed = ctx:sound("bed_a"); assert(fadingBed.Volume > .45, "long section fade fixture settled too soon")
local outgoing = fadingBed.Volume
ctx.player:SetAttribute("InRound", false); ctx:tick(.25)
ctx:tick(1); near(fadingBed.Volume, outgoing * .5)
ctx:tick(.75); assert(not fadingBed.destroyed and fadingBed.Volume < .025, "eligibility exit did not reach near silence before cleanup")
ctx:tick(.25); assert(fadingBed.destroyed and #ctx:playing() == 0, "authored long section fade escaped fixed eligibility cleanup")
ctx:finish()
fixture = smallPlan()
ctx = setup({plan = fixture, cloneLoads = {bed_b = false}}); ctx:section("A"); ctx:enter(); ctx:tick(4)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true, "unloaded neighbour gated loaded current section")
ctx:tick(10); assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and ctx.player:GetAttribute("Level2PoolroomsAudioSkipped") == "bed_b")
ctx:finish()
ctx = setup({plan = smallPlan(), cloneLoads = {bed_a = 2}}); ctx:section("A"); ctx:enter()
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == false); ctx:tick(5)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and ctx:sound("bed_a").IsPlaying)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSkipped") == ""); ctx:finish()
print("PASS long authored fade rebases to fixed eligibility exit; neighbour loading cannot gate current; delayed clone loading recovers before deadline")

-- AUDIO_SECTIONS_20261010: one failed clone does not blacklist another persistent row sharing its template key.
fixture = smallPlan(); fixture.beds[1] = {key = "bed_shared", sections = {"A"}, volume = .2}
table.insert(fixture.beds, 2, {key = "bed_shared", sections = {"A"}, volume = .3})
ctx = setup({plan = fixture, cloneLoads = {bed_shared = {false, true}}}); ctx:section("A"); ctx:enter(); ctx:tick(16)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true and ctx:sound("bed_shared").IsPlaying)
near(ctx:sound("bed_shared").Volume, .3)
assert(ctx.player:GetAttribute("Level2PoolroomsAudioSkipped") == "bed_shared" and warningsFor(ctx, "bed_shared") == 1)
ctx:section("B"); ctx:tick(35); ctx:section("A"); ctx:tick(4)
local shared = 0; for _, sound in ipairs(ctx:voices()) do if sound.Name == "bed_shared" then shared += 1 end end
-- Changed on purpose after review (2026-10-10): a row that missed its load deadline is tried ONCE more twenty seconds
-- later, so a slow connection does not leave a section on the legacy ambience for the whole round.
assert(shared == 2, "a row that timed out was not tried once more after twenty seconds")
ctx.player:SetAttribute("InRound", false); ctx:tick(2.5); ctx:enter(); ctx:tick(4)
shared = 0; for _, sound in ipairs(ctx:voices()) do if sound.Name == "bed_shared" then shared += 1 end end
assert(shared == 2, "row failure did not reset for a new session")
assert(ctx.player:GetAttribute("Level2PoolroomsAudioBeds") == "bed_shared=0.50", "shared bed key target volumes did not add up")
ctx:finish()
-- ...and only once: a second miss is final for the session.
fixture = smallPlan(); fixture.beds[1] = {key = "bed_shared", sections = {"A"}, volume = .2}
table.insert(fixture.beds, 2, {key = "bed_shared", sections = {"A"}, volume = .3})
ctx = setup({plan = fixture, cloneLoads = {bed_shared = {false, true, false}}}); ctx:section("A"); ctx:enter(); ctx:tick(16)
ctx:tick(40)
shared = 0; for _, sound in ipairs(ctx:voices()) do if sound.Name == "bed_shared" then shared += 1 end end
assert(shared == 1, "a row that missed its deadline twice was tried a third time")
ctx:tick(60)
shared = 0; for _, sound in ipairs(ctx:voices()) do if sound.Name == "bed_shared" then shared += 1 end end
assert(shared == 1 and ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true, "second failure was not final")
ctx:finish()
print("PASS persistent clone failure is per row/session with one retry after 20 s; shared-key loaded rows play, new sessions retry, duplicate bed targets sum")

-- AUDIO_SECTIONS_20261010: malformed authored collections and hard-cap overrides must retain fallback instead of throwing in a frame.
local invalidPlans = {}
for _, limits in ipairs({{persistent = 65}, {keys = 161}, {shots = 5}, {recent = 5}, {shots = false}}) do
	fixture = smallPlan(); fixture.limits = limits; table.insert(invalidPlans, fixture)
end
fixture = smallPlan(); fixture.limits = false; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.order = false; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.route = false; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.shots = {unexpected = {key = "shot_bad", sections = {"A"}, volume = .2}}; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.beds[2] = nil; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.sections.A.min[1] = 100; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.loops = {{key = "loop_bad", sections = {"A"}, volume = .2, position = {0, 0, 0}, max = 4}}; table.insert(invalidPlans, fixture)
fixture = smallPlan(); addShots(fixture, 1); fixture.shots[1].positions = {unexpected = {0, 0, 0}}; table.insert(invalidPlans, fixture)
fixture = smallPlan(); fixture.beds = {}
for i = 1, 65 do table.insert(fixture.beds, {key = "bed_cap_" .. i, sections = {"A"}, volume = .2}) end
table.insert(invalidPlans, fixture)
fixture = smallPlan(); addShots(fixture, 158); table.insert(invalidPlans, fixture)
for i, invalid in ipairs(invalidPlans) do
	ctx = setup({plan = invalid}); ctx:section("A"); ctx:enter(); ctx:tick(4)
	assert(#ctx:voices() == 0 and #ctx:playing() == 0, "invalid schema/cap plan started: " .. i)
	assert(#ctx.warnings > 0, "invalid schema/cap plan was silent: " .. i); ctx:finish()
end
fixture = smallPlan(); addShots(fixture, 4); fixture.sections.A.gap = {1, 1}; fixture.limits = {shots = 0}
ctx = setup({plan = fixture}); ctx:section("A"); ctx:enter(); ctx:tick(40)
assert(#ctx:shots() == 0 and ctx.player:GetAttribute("Level2PoolroomsAudioReady") == true, "zero shot limit did not keep beds without randoms")
ctx:finish()
print("PASS dense schema/table validation, reversed boxes/rolloff, hard 64/160/4 bounds and optional zero-shot limit retain expected ownership")

-- AUDIO_SECTIONS_20261010: cooldown filtering can shrink a five-key pool to two; recent avoidance must shrink with it.
fixture = {origin = {1000, 100, 0}, order = {"E", "A", "B", "C", "D", "X"}, sections = {},
	beds = {{key = "bed_shared", sections = {"*"}, volume = .2}}, loops = {}, shots = {}, route = {}, limits = {recent = 4}}
for _, id in ipairs(fixture.order) do
	fixture.sections[id] = {min = {-50, -10, -50}, max = {50, 10, 50}, passage = false, first = {0, 0}, gap = {100, 100}}
end
for _, id in ipairs({"D", "A", "B", "C", "E"}) do
	table.insert(fixture.shots, {key = "shot_" .. id, sections = {id, "X"}, volume = .2, cooldown = (id == "A" or id == "D") and 0 or 100})
end
ctx = setup({plan = fixture, shotLength = .25}); ctx:section("E"); ctx:enter(); at(ctx, 24.25)
for _, id in ipairs({"A", "B", "C", "D", "X"}) do ctx:section(id); ctx:tick(.5) end
local narrowed = ctx:shots(); assert(#narrowed == 6)
for i, id in ipairs({"E", "A", "B", "C", "D", "A"}) do assert(narrowed[i].key == "shot_" .. id, "eligible-pool recent cap picked " .. narrowed[i].key .. " at " .. i) end
ctx:finish()
print("PASS explicit recent depth shrinks after cooldown filtering; two eligible keys avoid the latest and play the older key")

-- AUDIO_SECTIONS_20261010: finite authored weights can overflow their sum without making a valid pool silent.
fixture = smallPlan(); addShots(fixture, 2)
fixture.shots[1].weight, fixture.shots[2].weight = 1e308, 1e308
ctx = setup({plan = fixture, shotLength = .5}); ctx:section("A"); ctx:enter(); at(ctx, 24.25)
assert(#ctx:shots() == 1 and ctx:shots()[1].key == "shot_1", "overflowing finite weights silenced the draw")
ctx:finish()
print("PASS finite huge weighted pools draw normally after overflow scaling without changing ordinary v2 choices")

-- The plan that ships (tools/poolrooms_audio_20261010/make_plan.py), walked along its own order with the real client:
-- it is accepted, every section is ready within twenty seconds, a section with a bed of its own plays that bed, one-shots
-- come at the per-section pace, and no key is skipped.
if shippedV3Plan then
	local context = setup({plan = shippedV3Plan})
	context:section(shippedV3Plan.order[1]); context:enter()
	local own = {}
	for _, row in ipairs(shippedV3Plan.beds) do if #row.sections == 1 then own[row.sections[1]] = row.key end end
	for _, id in ipairs(shippedV3Plan.order) do
		context:section(id); context:tick(20)
		assert(context.player:GetAttribute("Level2PoolroomsAudioReady") == true, "shipped plan is not ready in " .. id)
		local playing = context.player:GetAttribute("Level2PoolroomsAudioBeds") or ""
		assert(string.find(playing, own[id], 1, true), id .. " does not play its own bed (" .. tostring(own[id]) .. "): " .. playing)
	end
	assert((context.player:GetAttribute("Level2PoolroomsAudioShots") or 0) >= 8, "the shipped plan played too few one-shots on a walk")
	assert((context.player:GetAttribute("Level2PoolroomsAudioSkipped") or "") == "", "the shipped plan skipped keys")
	context:finish()
	print("PASS shipped v3 plan is accepted; each section plays its own bed; " .. tostring(#shippedV3Plan.shots) .. " one-shot rows; nothing skipped")
end
