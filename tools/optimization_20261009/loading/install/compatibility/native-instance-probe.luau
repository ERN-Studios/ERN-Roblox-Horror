return function()
local checks = 0
local function check(condition, label) assert(condition, label); checks += 1 end
local fixtureRoot = Instance.new("Model")
fixtureRoot.Name = "OptimizationStreamingLifecycleFixture"
local owned = {fixtureRoot}
local function make(class, name, parent)
    local item = Instance.new(class)
    item.Name = name or class
    table.insert(owned, item)
    item.Parent = parent or fixtureRoot
    return item
end
local ambientAnchors = {Corridor = {}, WetHall = {}, PumpPipe = {}}
local ambientAnchorSeen, ambientConnections = {}, {}
local randomSessionActive, ambientWorld, nextCommonAt, lastCommonKey, authoredBusyUntil
local COMMON_FIRST_DELAY_MIN, COMMON_FIRST_DELAY_MAX = 1, 2
local rng = Random.new(1234)
local function resetGroanSession() end
local function clearAmbientEmitters() end
local function clearSpatialCueEmitters() end
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


local litBefore = {}
local exitLamp = {bulb=nil, base=0, dipUntil=0, nextDip=0}
local workspace = {DescendantRemoving = fixtureRoot.DescendantRemoving}
local removalConnection
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
removalConnection = workspace.DescendantRemoving:Connect(forgetFinaleInstance)

local rigs = setmetatable({}, {__mode="k"})
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


local ok, result = xpcall(function()
    local w = make("Model", "FixtureWorld")
    local a = make("Part", "Level 2 Corridor Vault Light Fixture", w)
    local b = make("Part", "Level 2 Navigation Node Fixture", w)
    local c = make("Part", "Level 2 Pump Intake Pipe", w)
    startRandomSession(w)
    check(#ambientAnchors.Corridor == 1 and #ambientAnchors.WetHall == 1 and #ambientAnchors.PumpPipe == 1, "native initial classification")
    a.Parent = nil; task.wait()
    check(ambientAnchorSeen[a] == nil and #ambientAnchors.Corridor == 0, "native individual stream-out signal prunes")
    a.Parent = w; task.wait()
    check(ambientAnchors.Corridor[1] == a and #ambientAnchors.Corridor == 1, "native same replica re-entry")
    for _ = 1, 10 do
        a.Parent = nil; task.wait()
        a.Parent = w; task.wait()
    end
    check(#ambientAnchors.Corridor == 1 and #ambientConnections == 3, "native repeated signals bounded")
    local p = make("Part", "FixtureLamp")
    local lamp = make("SpotLight", "FixtureSpot", p)
    lamp.Color, lamp.Brightness, lamp.Angle = Color3.fromRGB(255, 0, 0), 100, 14
    local originalColor = Color3.fromRGB(180, 220, 255)
    litBefore[lamp] = {originalColor, 2, 70}
    p.Parent = nil; task.wait()
    check(lamp.Color == originalColor and lamp.Brightness == 2 and lamp.Angle == 70 and litBefore[lamp] == nil, "native removed subtree restores cached light")
    p.Parent = fixtureRoot; task.wait()
    local exit = make("PointLight", "FixtureExit", p)
    exit.Brightness = 0.35; exitLamp.bulb, exitLamp.base = exit, 1
    exit.Parent = nil; task.wait()
    check(exit.Brightness == 1 and exitLamp.bulb == nil and exitLamp.base == 0, "native exit lamp stream-out restores")
    local doll = make("Model", "FixtureDoll")
    local function makeBody()
        local body = make("MeshPart", "Body", doll)
        local hips = make("Bone", "Hips", body)
        make("Bone", "Head", hips)
        return body
    end
    local firstBody = makeBody()
    local firstRig = rigOf(doll)
    check(firstRig and firstRig.body == firstBody and firstRig.bones.Head:IsA("Bone"), "native rig captures actual bones")
    firstBody.Parent = nil
    check(rigOf(doll) == nil and rigs[doll] == nil, "native body disappearance releases rig")
    local secondBody = makeBody()
    local secondRig = rigOf(doll)
    check(secondRig and secondRig ~= firstRig and secondRig.body == secondBody and secondRig.bones.Head:IsDescendantOf(secondBody), "native new Body refreshes bone owner")
    w.Parent = nil; task.wait()
    check(ambientWorld == nil and #ambientConnections == 0 and next(ambientAnchorSeen) == nil, "native Improved root removal cleanup")
    return {nativeFixtureChecks=checks, realStreamingGameplayPerformancePass=false}
end, debug.traceback)
stopRandomSession()
if removalConnection then removalConnection:Disconnect() end
table.clear(litBefore); table.clear(rigs); exitLamp.bulb, exitLamp.base = nil, 0
for i = #owned, 1, -1 do pcall(function() owned[i]:Destroy() end) end
assert(ok, result)
return result
end
