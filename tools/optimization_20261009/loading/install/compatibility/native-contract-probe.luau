return function()
local checks = 0
local function check(condition, label)
    assert(condition, label)
    checks += 1
end
local function signal()
    local records = {}
    return {
        Connect = function(_, callback)
            local connection = {Connected = true, Callback = callback}
            function connection:Disconnect() self.Connected = false end
            table.insert(records, connection)
            return connection
        end,
        Fire = function(_, ...)
            for _, connection in ipairs(table.clone(records)) do
                if connection.Connected then connection.Callback(...) end
            end
        end,
        Count = function()
            local count = 0
            for _, connection in ipairs(records) do if connection.Connected then count += 1 end end
            return count
        end,
    }
end
local function instance(class, name, attributes)
    local item = {Name = name or class, Attributes = attributes or {}}
    function item:IsA(wanted)
        return wanted == class or (wanted == "BasePart" and (class == "Part" or class == "MeshPart"))
            or (wanted == "Light" and (class == "PointLight" or class == "SpotLight"))
    end
    function item:GetAttribute(key) return self.Attributes[key] end
    return item
end
local function world(items)
    local item = instance("Model", "world")
    item.Parent = {}
    item.DescendantAdded, item.DescendantRemoving, item.AncestryChanged = signal(), signal(), signal()
    item.Items = items or {}
    function item:GetDescendants() return self.Items end
    return item
end

do
local ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
local ambientAnchorSeen = {}
local ambientConnections = {}
local randomSessionActive, ambientWorld, nextCommonAt, lastCommonKey, authoredBusyUntil
local COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX = 1, 2
local rng = {NextNumber = function() return 1.5 end}
local resets, emitterClears, cueClears = 0, 0, 0
local function resetGroanSession() resets += 1 end
local function clearAmbientEmitters() emitterClears += 1 end
local function clearSpatialCueEmitters() cueClears += 1 end
local function disconnectAmbientConnections()
    for _, connection in ipairs(ambientConnections) do connection:Disconnect() end
    ambientConnections = {}
end
local function stopRandomSession()
	resetGroanSession()
	disconnectAmbientConnections()
	clearAmbientEmitters()
	clearSpatialCueEmitters()
	ambientWorld = nil
	randomSessionActive = false
	ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
	ambientAnchorSeen = {}
	nextCommonAt = math.huge
	lastCommonKey = nil
	authoredBusyUntil = 0
end

local function classifyAmbientAnchor(instance)
	if not (instance:IsA("BasePart") and not ambientAnchorSeen[instance]) then return end
	local name = instance.Name
	if name:find("Level 2 Corridor Vault Light", 1, true) == 1 then
		ambientAnchorSeen[instance] = "Corridor"
		table.insert(ambientAnchors.Corridor, instance)
	elseif name:find("Level 2 Navigation Node ", 1, true) == 1
		and instance:GetAttribute("Level2_Role") ~= "Kids Area" then
		ambientAnchorSeen[instance] = "WetHall"
		table.insert(ambientAnchors.WetHall, instance)
	elseif name == "Level 2 Pump Intake Pipe" then
		ambientAnchorSeen[instance] = "PumpPipe"
		table.insert(ambientAnchors.PumpPipe, instance)
	end
end

-- Streaming removes individual anchors while the world's Model can remain.
local function forgetAmbientAnchor(instance)
	local category = ambientAnchorSeen[instance]
	if not category then return end
	ambientAnchorSeen[instance] = nil
	local list = ambientAnchors[category]
	local index = table.find(list, instance)
	if index then table.remove(list, index) end
end

local function startRandomSession(world)
	stopRandomSession()
	randomSessionActive = true
	ambientWorld = world
	nextCommonAt = os.clock() + rng:NextNumber(COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX)
	-- Monster groans have their own source-aware scheduler below. Environmental
	-- water drops, pump drains and ordinary building-pressure groans stay intact.
	for _, instance in ipairs(world:GetDescendants()) do
		classifyAmbientAnchor(instance)
	end
	table.insert(ambientConnections, world.DescendantAdded:Connect(classifyAmbientAnchor))
	table.insert(ambientConnections, world.DescendantRemoving:Connect(forgetAmbientAnchor))
	table.insert(ambientConnections, world.AncestryChanged:Connect(function(_, parent)
		if not parent and ambientWorld == world then stopRandomSession() end
	end))
end


local a = instance("Part", "Level 2 Corridor Vault Light 1")
local b = instance("Part", "Level 2 Navigation Node 2")
local c = instance("Part", "Level 2 Pump Intake Pipe")
local kids = instance("Part", "Level 2 Navigation Node 3", {Level2_Role="Kids Area"})
local unrelated = instance("Folder", "Level 2 Pump Intake Pipe")
local oldWorld = world({a,b,c,kids,unrelated})
startRandomSession(oldWorld)
check(randomSessionActive and ambientWorld == oldWorld, "session attached")
check(#ambientAnchors.Corridor == 1 and #ambientAnchors.WetHall == 1 and #ambientAnchors.PumpPipe == 1, "classified streamed initial anchors")
check(ambientAnchorSeen[a] == "Corridor" and ambientAnchorSeen[b] == "WetHall" and ambientAnchorSeen[c] == "PumpPipe", "category ownership")
check(ambientAnchorSeen[kids] == nil and ambientAnchorSeen[unrelated] == nil, "classification exclusions retained")
check(#ambientConnections == 3 and oldWorld.DescendantRemoving.Count() == 1, "one bounded removal connection")
oldWorld.DescendantAdded:Fire(a)
check(#ambientAnchors.Corridor == 1, "duplicate add idempotent")
oldWorld.DescendantRemoving:Fire(a)
check(#ambientAnchors.Corridor == 0 and ambientAnchorSeen[a] == nil, "individual removal releases anchor and seen ownership")
check(#ambientAnchors.WetHall == 1 and #ambientAnchors.PumpPipe == 1 and randomSessionActive, "removal preserves other anchors and session")
oldWorld.DescendantRemoving:Fire(a)
oldWorld.DescendantRemoving:Fire(unrelated)
check(#ambientAnchors.Corridor == 0, "duplicate/unowned removal harmless")
oldWorld.DescendantAdded:Fire(a)
check(#ambientAnchors.Corridor == 1, "same replica re-entry recognized")
oldWorld.DescendantRemoving:Fire(b)
local b2 = instance("Part", "Level 2 Navigation Node 2")
oldWorld.DescendantAdded:Fire(b2)
check(#ambientAnchors.WetHall == 1 and ambientAnchors.WetHall[1] == b2 and not ambientAnchorSeen[b], "replacement replica has no retained old reference")
for _ = 1, 400 do
    oldWorld.DescendantRemoving:Fire(a)
    oldWorld.DescendantAdded:Fire(a)
end
check(#ambientAnchors.Corridor == 1 and #ambientConnections == 3, "400 cycles stay bounded")
local secondWorld = world({})
startRandomSession(secondWorld)
check(oldWorld.DescendantAdded.Count() == 0 and oldWorld.DescendantRemoving.Count() == 0 and oldWorld.AncestryChanged.Count() == 0, "world replacement disconnects all old session signals")
check(#ambientAnchors.Corridor == 0 and #ambientAnchors.WetHall == 0 and #ambientAnchors.PumpPipe == 0 and next(ambientAnchorSeen) == nil, "replacement clears all old references")
oldWorld.DescendantAdded:Fire(a)
check(next(ambientAnchorSeen) == nil, "retired world cannot append")
secondWorld.DescendantAdded:Fire(c)
check(ambientAnchors.PumpPipe[1] == c, "new world can append")
secondWorld.Parent = nil
secondWorld.AncestryChanged:Fire(secondWorld, nil)
check(not randomSessionActive and ambientWorld == nil and next(ambientAnchorSeen) == nil, "Improved root stream-out stops session")
check(#ambientConnections == 0 and secondWorld.DescendantRemoving.Count() == 0, "stream-out root disconnects removal watcher")
check(resets == 3 and emitterClears == 3 and cueClears == 3, "all three session cleanup paths retained")
startRandomSession(world({a}))
stopRandomSession()
check(#ambientAnchors.Corridor == 0 and next(ambientAnchorSeen) == nil and #ambientConnections == 0, "explicit round end clears every cache and connection")

end
do
local litBefore = {}
local exitLamp = {bulb = nil, base = 0, dipUntil = 0, nextDip = 0}
local workspace = {DescendantRemoving = signal()}
local function forgetFinaleInstance(item)
	local before = litBefore[item]
	litBefore[item] = nil
	if before then
		pcall(function()
			item.Color = before[1]
			if item:IsA("Light") then item.Brightness = before[2] end
			if item:IsA("SpotLight") then item.Angle = before[3] end
		end)
	end
	if exitLamp.bulb == item then
		local base = exitLamp.base
		exitLamp.bulb, exitLamp.base = nil, 0
		pcall(function() item.Brightness = base end)
	end
end
workspace.DescendantRemoving:Connect(forgetFinaleInstance)

local lamp = instance("SpotLight")
lamp.Color, lamp.Brightness, lamp.Angle = "red", 100, 14
litBefore[lamp] = {"white", 2, 70}
workspace.DescendantRemoving:Fire(lamp)
check(lamp.Color == "white" and lamp.Brightness == 2 and lamp.Angle == 70, "spot lamp restores pre-finale values")
check(litBefore[lamp] == nil, "removed lamp released")
workspace.DescendantRemoving:Fire(lamp)
check(lamp.Brightness == 2, "repeat removal does not rescale")
local point = instance("PointLight")
point.Color, point.Brightness = "red", 0.1
litBefore[point] = {"yellow", 0.55, 0}
point.Parent = nil
workspace.DescendantRemoving:Fire(point)
check(point.Color == "yellow" and point.Brightness == 0.55, "deferred callback restores nil-parent light")
local neon = instance("Part")
neon.Color = "dark"
litBefore[neon] = {"blue", 0, 0}
workspace.DescendantRemoving:Fire(neon)
check(neon.Color == "blue" and neon.Brightness == nil, "neon restoration only owns color")
local exit = instance("PointLight")
exit.Brightness = 0.35
exitLamp.bulb, exitLamp.base = exit, 1
workspace.DescendantRemoving:Fire(exit)
check(exit.Brightness == 1 and exitLamp.bulb == nil and exitLamp.base == 0, "exit flicker replica restores and releases cache")
check(exitLamp.dipUntil == 0 and exitLamp.nextDip == 0, "removal leaves timing contract unchanged")
local other = instance("SpotLight")
other.Color, other.Brightness, other.Angle = "green", 6, 48
workspace.DescendantRemoving:Fire(other)
check(other.Color == "green" and other.Brightness == 6 and other.Angle == 48, "unowned lights unchanged")
for _ = 1, 400 do
    litBefore[lamp] = {lamp.Color, lamp.Brightness, lamp.Angle}
    lamp.Color, lamp.Brightness, lamp.Angle = "red", lamp.Brightness * 5, 12
    workspace.DescendantRemoving:Fire(lamp)
end
check(lamp.Color == "white" and lamp.Brightness == 2 and lamp.Angle == 70 and next(litBefore) == nil, "400 stream cycles never save already-scaled finale brightness")
local live = instance("SpotLight")
litBefore[live] = {"white", 3, 45}
check(getmetatable(litBefore) == nil and litBefore[live][2] == 3, "live baseline remains strong")
workspace.DescendantRemoving:Fire(live)
local readOnly = setmetatable({IsA = lamp.IsA}, {__newindex = function() error("disposed fixture") end})
litBefore[readOnly] = {"white", 2, 70}
exitLamp.bulb, exitLamp.base = readOnly, 4
workspace.DescendantRemoving:Fire(readOnly)
check(litBefore[readOnly] == nil and exitLamp.bulb == nil and exitLamp.base == 0, "restore error still releases removed references")
check(workspace.DescendantRemoving.Count() == 1, "single lifetime light removal connection")

end
do
local rigs = setmetatable({}, {__mode = "k"})
local function bodyOf(child, includeHead)
    local body = instance("MeshPart", "Body")
    body.Parent = child
    body.Bones = {instance("Bone", "Hips")}
    if includeHead then table.insert(body.Bones, instance("Bone", "Head")) end
    function body:GetDescendants() return self.Bones end
    child.Body = body
    return body
end
local doll = {}
function doll:FindFirstChild(name) return name == "Body" and self.Body or nil end
local function rigOf(child)
	local body = child:FindFirstChild("Body")
	local rig = rigs[child]
	if rig and rig.body == body and body.Parent == child then return rig end
	rigs[child] = nil
	if not body then return nil end
	local bones = {}
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("Bone") then bones[d.Name] = d end
	end
	if not bones.Hips or not bones.Head then return nil end   -- still streaming in
	rig = {body = body, bones = bones, last = {}, from = {}, fade = 1, t = 0, name = nil, serial = nil,
		nextTwitch = os.clock() + 3, twitchT = nil}
	rigs[child] = rig
	return rig
end


check(rigOf(doll) == nil and rigs[doll] == nil, "no streamed Body stands down")
local body1 = bodyOf(doll, true)
local first = rigOf(doll)
check(first and first.body == body1 and first.bones.Head == body1.Bones[2], "fresh rig owns current mesh bones")
first.t = 4
check(rigOf(doll) == first and first.t == 4, "live rig keeps animation continuity")
doll.Body = nil
body1.Parent = nil
check(rigOf(doll) == nil and rigs[doll] == nil, "partial Body removal releases cached bones")
doll.Body, body1.Parent = body1, doll
local returned = rigOf(doll)
check(returned ~= first and returned.body == body1, "same Body returning after observed stream-out rebuilds")
local body2 = bodyOf(doll, true)
body1.Parent = nil
local replaced = rigOf(doll)
check(replaced ~= returned and replaced.body == body2 and replaced.bones.Head == body2.Bones[2], "Body replacement refreshes visible bone targets")
local partial = bodyOf(doll, false)
check(rigOf(doll) == nil and rigs[doll] == nil, "incomplete returning bone tree waits instead of stale cache")
table.insert(partial.Bones, instance("Bone", "Head"))
local complete = rigOf(doll)
check(complete and complete.body == partial and complete.bones.Head == partial.Bones[2], "late head completes rig retry")
for _ = 1, 400 do
    doll.Body = nil
    check(rigOf(doll) == nil, "cycle stream-out stands down")
    bodyOf(doll, true)
    local current = rigOf(doll)
    check(current and current.body == doll.Body and current.bones.Head == doll.Body.Bones[2], "cycle animates only current visible bones")
end
check(getmetatable(rigs).__mode == "k", "existing rig cache weak ownership retained")
print("STREAMING_LIFECYCLE_CHECKS=" .. checks)

end

return true
end
