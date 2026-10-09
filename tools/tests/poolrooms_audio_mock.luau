-- Offline behavioral harness. The actual LocalScript is embedded into __RUN_CONTROLLER__ by the Python runner.
-- Engine asset decoding, streaming, audible mix and real performance require a Studio/play verification.
local now, objects, services, heartbeat, sourceScript, plan, currentContext
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
function methods:SetAttribute(name, value) self.attrs[name] = value end
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
	for key, value in pairs(self.props) do
		if key ~= "Parent" and key ~= "attrs" and key ~= "Ended" and key ~= "Stopped" then result[key] = value end
	end
	return result
end
function methods:Play()
	assert(self.IsLoaded, "a sound played before loading")
	assert(self.Volume == 0, "a sound began without its attack envelope")
	self.playedAt, self.engineStartAt = now, now + (currentContext.playDelay or 0)
	self.IsPlaying = self.engineStartAt == now
end
function methods:Stop() self.IsPlaying, self.engineStartAt = false, nil; self.Stopped.Fire() end
Instance = {new = function(class) return object(class) end}
Enum = {RaycastFilterType = {Include = "Include"}, RollOffMode = {InverseTapered = "InverseTapered"}}
RaycastParams = {new = function() return {} end}
Random = {new = function() return {NextNumber = function(_, lo, hi)
	if lo == nil then return .5 end
	return (lo + hi) / 2
end} end}
os = {clock = function() return now end}
local queued
task = {spawn = function(callback)
	local token = {callback = callback}; table.insert(queued, token); return token
end, cancel = function(token) token.cancelled = true end}
warn = function(message) table.insert(currentContext.warnings, message) end
game = {GetService = function(_, name) return services[name] end}

local function runController()
__RUN_CONTROLLER__
end
local function setup(options)
	options = options or {}
	currentContext = {loaded = options.loaded ~= false, warnings = {}, maxClones = 0, raycasts = 0, playDelay = options.playDelay or 0}
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
	local ids = {"bed_hall", "bed_water", "bed_service", "loop_weir", "loop_lion", "shot_drip", "shot_pipe", "shot_splash", "shot_creak"}
	for i, key in ipairs(ids) do
		local sound = object("Sound", key, library)
		sound.SoundId = "rbxassetid://" .. i
		if key:find("shot_", 1, true) then sound.TimeLength = options.shotLength or 8 end
	end
	services.HttpService = {JSONDecode = function() return plan end}
	heartbeat = signal(); services.RunService = {Heartbeat = heartbeat}
	services.ContentProvider = {PreloadAsync = function(_, sounds)
		if ctx.loaded then for _, sound in ipairs(sounds) do sound.IsLoaded = true end end
	end}
	ctx.player = object("Player", "LocalPlayer"); ctx.player.UserId = 1
	ctx.watched = object("Player", "WatchedPlayer"); ctx.watched.UserId = 2
	services.Players = {LocalPlayer = ctx.player, GetPlayerByUserId = function(_, id) return id == 2 and ctx.watched or nil end}
	local function body(player)
		local character = object("Model", "Character", workspace)
		local humanoid = object("Humanoid", "Humanoid", character); humanoid.Health = 100
		local root = object("Part", "HumanoidRootPart", character); root.Position = Vector3.new(1000, 100, 0)
		player.Character = character
		return root, humanoid
	end
	ctx.root, ctx.humanoid = body(ctx.player)
	ctx.watchedRoot, ctx.watchedHumanoid = body(ctx.watched)
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
	sourceScript = object("LocalScript", "Poolrooms Ambience"); sourceScript.Destroying = signal(); script = sourceScript
	runController()
	function ctx:tick(seconds)
		for _ = 1, math.round(seconds / .25) do
			now += .25
			for _, sound in ipairs(objects) do
				if sound:IsA("Sound") and not sound.destroyed and sound.engineStartAt and now >= sound.engineStartAt then
					sound.IsPlaying = true
					if not self.stalled then sound.TimePosition += .25 * sound.PlaybackSpeed end
					if sound.TimePosition >= sound.TimeLength then
						if sound.Looped then sound.TimePosition %= sound.TimeLength else
							sound.TimePosition, sound.IsPlaying, sound.engineStartAt = 0, false, nil
							sound.Ended.Fire()
						end
					end
				end
			end
			local pending = queued; queued = {}
			for _, token in ipairs(pending) do if not token.cancelled then token.callback() end end
			heartbeat.Fire()
			local clones = 0
			for _, candidate in ipairs(objects) do
				if candidate:IsA("Sound") and not candidate.destroyed and candidate ~= self.cascade and not candidate:IsDescendantOf(library) then clones += 1 end
			end
			self.maxClones = math.max(self.maxClones, clones)
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
	function ctx:finish() sourceScript.Destroying.Fire() end
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
assert(shots <= 2 and ctx.maxClones <= 9, "one-shot concurrency exceeded bounds")
assert(ctx.player:GetAttribute("Level2PoolroomsAudioLastShot") ~= nil, "random scheduler never played")
ctx.player:SetAttribute("InRound", false); ctx:tick(1.5)
for _, sound in ipairs(ctx:playing()) do assert(not sound.Name:find("shot_", 1, true), "cancelled shot survived one-second tail") end
ctx:tick(1); assert(#ctx:playing() == 0)
ctx:finish()
print("PASS rare random scheduler, long-clip concurrency cap and cancelled-shot fade")
