-- Run once through the Studio MCP in a fresh Play Server session, after the
-- regular spawn has settled. This is a temporary QA task, not a saved Script.
-- Poll: return game:GetService("HttpService"):JSONEncode(_G.AeroWalkQA)
-- Cancel: _G.AeroWalkQA.cancelRequested = true
-- The importer must set house.AeroAuthoredFrame to the frame mapping authored
-- Roblox coordinates (Blender x,z,-y) into this live model's world position.
-- The test only directs Humanoid:MoveTo; it never teleports or requests jumps.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
assert(RunService:IsRunning() and RunService:IsServer(), "Run in Play Server")
assert(game.PlaceId == 121672571539226, "Unexpected place; inspect before testing")
assert(not _G.AeroWalkQA or _G.AeroWalkQA.done, "Aero QA is already active")

local house = workspace:FindFirstChild("Aero House")
assert(house and house:IsA("Model"), "Aero House model is missing")
local runtime = house:FindFirstChild("AeroRuntime")
assert(runtime, "Apply the verified house collision setup first")
local frame = house:GetAttribute("AeroAuthoredFrame")
assert(typeof(frame) == "CFrame", "Set the verified AeroAuthoredFrame attribute")
local player = Players:GetPlayers()[1]
assert(player and player.Character, "Wait for the ordinary player spawn")
local character = player.Character
local humanoid = character:FindFirstChildOfClass("Humanoid")
local root = character:FindFirstChild("HumanoidRootPart")
assert(humanoid and root and not root.Anchored and humanoid.Health > 0, "Avatar not ready")
assert(humanoid.FloorMaterial ~= Enum.Material.Air, "Wait until the spawn has settled")
assert(math.abs(workspace.Gravity - 196.2) < 0.01, "Normal Roblox gravity is required")

local function vector(v) return {v.X, v.Y, v.Z} end
local startLocal = frame:PointToObjectSpace(root.Position)
assert((Vector2.new(startLocal.X, startLocal.Z) - Vector2.new(0, 49)).Magnitude < 8,
    "Start a fresh Play session at the entry spawn; do not reposition the avatar")
local rootFloorOffset = humanoid.HipHeight + root.Size.Y * 0.5
if humanoid.RigType == Enum.HumanoidRigType.R6 then
    local leg = character:FindFirstChild("Left Leg")
    assert(leg, "R6 leg missing")
    rootFloorOffset += leg.Size.Y
end
assert(rootFloorOffset > 1 and rootFloorOffset < 7, "Unexpected avatar dimensions")

local route = {}
local function waypoint(label, x, y, floor)
    route[#route + 1] = {label = label, x = x, y = y, floor = floor}
end
local function points(label, values, floor)
    for i, p in ipairs(values) do waypoint(label .. " " .. i, p[1], p[2], floor) end
end
waypoint("front approach", 0, -48, 0.18)
waypoint("entry first step", 0, -46, 0.18)
waypoint("entry middle step", 0, -45.6, 0.36)
waypoint("entry upper step", 0, -44.7, 0.82)
points("entry and lounge", {{0,-43},{0,-40},{0,-30},{-12,-30},{-29,-30}}, 1)
points("guest bedroom", {{-12,-30},{-12,12},{-29,12},{-29,20},{-29,12},{-12,12}}, 1)
points("dry bathroom", {{-12,18.5},{0,18.5},{0,24},{0,26},{0,18.5}}, 1)
points("study", {{13,18.5},{13,12},{29,12},{29,20},{29,12},{15,12}}, 1)
points("kitchen and dining circulation", {{15,-6},{26,-6},{42,-6},{42,-28},{37,-30},{15,-30}}, 1)
points("stair approach", {{6.5,-30},{6.5,-18}}, 1)
for _, y in ipairs({-14.5,-11.5,-8.5,-5.5,-2.5,0.5,3.5,4.5}) do
    waypoint("first stair flight", 6.5, y, 1 + 0.5 * math.ceil((y + 16) / 21 * 13))
end
for i = 0, 7 do
    local theta = (i + 0.5) * math.pi / 8
    waypoint("curved stair turn " .. (i + 1), 1 + 5.5 * math.cos(theta),
        5 + 5.5 * math.sin(theta), 8 + 0.5 * i)
end
for _, y in ipairs({4.5,1.5,-1.5,-4.5,-7.5,-8.7}) do
    waypoint("second stair flight", -4.5, y, 11.5 + 0.5 * math.ceil((5 - y) / 14 * 13))
end
points("upper landing and terrace", {{-4.5,-11},{0,-30},{28.5,-34},{28.5,-48}}, 18)
points("reading room and lime bedroom", {{28.5,-34},{20,-34},{20,-5},{29,-5},
    {29,8},{29,19},{29,24}}, 18)
points("gallery and cyan bedroom", {{29,19},{29,8},{18,8},{18,19.25},
    {-29,19.25},{-29,24}}, 18)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {runtime}
params.RespectCanCollide = true
local out = {
    done = false, passed = false, cancelRequested = false, route = {},
    placeId = game.PlaceId, userId = player.UserId, character = character.Name,
    start = vector(root.Position), initialHealth = humanoid.Health,
    gravity = workspace.Gravity, walkSpeed = humanoid.WalkSpeed,
    rootFloorOffset = rootFloorOffset, waypoints = #route,
    requestedJumps = 0, teleports = 0, observedJumpStates = 0,
    rigType = tostring(humanoid.RigType), arrivalRadius = 2,
    legTimeoutSeconds = 7, overallTimeoutSeconds = 180,
    performance = {
        scope = "Local Studio Play Server during an actual avatar walk; not a device or multiplayer benchmark",
        cpu = "Unverified: Heartbeat event intervals are not server CPU time or CPU utilization",
        clientRendering = "Unverified by this server-context sampler",
    },
}
_G.AeroWalkQA = out
local connections, stepTimes, memorySamples = {}, {}, {}
local started = os.clock()
local ownershipChanged = false
local previousAuto = root:GetNetworkOwnershipAuto()
local previousOwner = root:GetNetworkOwner()
local cancelledReason

local function progress()
    workspace:SetAttribute("AeroWalkQAProgress", HttpService:JSONEncode({
        done = out.done, passed = out.passed, completed = #out.route,
        total = #route, current = out.current, error = out.error,
        seconds = os.clock() - started,
    }))
end
local function checkActive()
    assert(not out.cancelRequested, "Test cancelled by operator")
    assert(not cancelledReason, cancelledReason or "Test cancelled")
    assert(player.Character == character and character:IsDescendantOf(workspace), "Character reset or removed")
    assert(humanoid.Health > 0 and root.Parent == character, "Avatar died or root disappeared")
    assert(house:IsDescendantOf(workspace) and house:GetAttribute("AeroAuthoredFrame") == frame,
        "House changed or was removed during the test")
    assert(os.clock() - started < 180, "Overall 180-second timeout")
end
local function sampleMemory()
    local ok, value = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
    if ok and type(value) == "number" and value == value then
        memorySamples[#memorySamples + 1] = value
    elseif not out.performance.memoryError then
        out.performance.memoryError = tostring(value)
    end
end
local function summarize(values)
    if #values == 0 then return {samples = 0} end
    table.sort(values)
    local sum = 0
    for _, value in ipairs(values) do sum += value end
    return {samples = #values, minimum = values[1], maximum = values[#values],
        average = sum / #values, p95 = values[math.max(1, math.ceil(#values * 0.95))]}
end

task.spawn(function()
    local ok, problem = xpcall(function()
        root:SetNetworkOwner(nil)
        ownershipChanged = true
        connections[#connections + 1] = character.AncestryChanged:Connect(function()
            if not character:IsDescendantOf(workspace) then cancelledReason = "Character removed" end
        end)
        connections[#connections + 1] = player.CharacterRemoving:Connect(function(removed)
            if removed == character then cancelledReason = "Character reset" end
        end)
        connections[#connections + 1] = humanoid.StateChanged:Connect(function(_, state)
            if state == Enum.HumanoidStateType.Jumping then out.observedJumpStates += 1 end
        end)
        local lastMemory = -math.huge
        connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
            if dt > 0 and #stepTimes < 20000 then stepTimes[#stepTimes + 1] = dt end
            if os.clock() - lastMemory >= 1 then
                lastMemory = os.clock()
                sampleMemory()
            end
        end)
        for index, p in ipairs(route) do
            checkActive()
            out.current = {index = index, label = p.label}
            progress()
            local expectedFloor = frame:PointToWorldSpace(Vector3.new(p.x, p.floor, -p.y))
            -- Probe from close to the intended floor, avoiding ceilings and
            -- furniture tops. Stair proxies may overlap by one half-stud riser.
            local hit = workspace:Raycast(expectedFloor + Vector3.yAxis * 0.60,
                -Vector3.yAxis * 1.25, params)
            assert(hit and hit.Normal.Y > 0.95 and math.abs(hit.Position.Y - expectedFloor.Y) <= 0.56,
                "Missing or incorrect support at waypoint " .. index .. " (" .. p.label .. ")")
            local target = hit.Position + Vector3.yAxis * rootFloorOffset
            local legStarted = os.clock()
            humanoid:MoveTo(target)
            local reached = false
            repeat
                task.wait(0.05)
                checkActive()
                local delta = root.Position - target
                reached = Vector2.new(delta.X, delta.Z).Magnitude <= 2
                    and math.abs(delta.Y) <= 0.9 and humanoid.FloorMaterial ~= Enum.Material.Air
            until reached or os.clock() - legStarted >= 7
            local delta = root.Position - target
            out.route[#out.route + 1] = {
                index = index, label = p.label, reached = reached,
                authored = {p.x, p.y, p.floor}, support = hit.Instance:GetFullName(),
                target = vector(target), actual = vector(root.Position),
                horizontalError = Vector2.new(delta.X, delta.Z).Magnitude,
                verticalError = math.abs(delta.Y), seconds = os.clock() - legStarted,
                health = humanoid.Health, floor = tostring(humanoid.FloorMaterial),
                state = tostring(humanoid:GetState()),
            }
            assert(reached, "Timed out at waypoint " .. index .. " (" .. p.label .. ")")
        end
        out.passed = #out.route == #route and humanoid.Health == out.initialHealth
        assert(out.passed, "Route completed with avatar health loss")
    end, debug.traceback)

    -- Cleanup runs on success, timeout, cancellation, reset, and runtime error.
    for _, connection in ipairs(connections) do connection:Disconnect() end
    if root.Parent == character then
        pcall(function() humanoid:MoveTo(root.Position) end)
        if ownershipChanged then
            local restored, restoreError = pcall(function()
                if previousAuto then root:SetNetworkOwnershipAuto()
                else root:SetNetworkOwner(previousOwner) end
            end)
            if not restored then out.cleanupError = tostring(restoreError) end
        end
    end
    sampleMemory()
    out.performance.heartbeatIntervalSeconds = summarize(stepTimes)
    local interval = out.performance.heartbeatIntervalSeconds.average
    if interval and interval > 0 then out.performance.heartbeatEventsPerSecond = 1 / interval end
    out.performance.processMemoryMb = summarize(memorySamples)
    out.connectionsDisconnected = #connections
    out.seconds = os.clock() - started
    out.finalHealth = humanoid.Health
    out.finalPosition = vector(root.Position)
    if not ok then out.passed = false; out.error = tostring(problem) end
    if out.cleanupError then out.passed = false end
    out.done = true
    progress()
end)
return HttpService:JSONEncode({started = true, waypoints = #route,
    rootFloorOffset = rootFloorOffset, start = out.start,
    poll = "return game:GetService('HttpService'):JSONEncode(_G.AeroWalkQA)"})
