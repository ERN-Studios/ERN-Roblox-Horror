-- Read-only bounded 10-second ACTIVE-ROUND server sample. Studio play SERVER context.
-- HeartbeatTime is server scheduler compute time, not whole-process CPU utilization.
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "SERVER context required")
local function read(name)
    local ok, result = pcall(function() return Stats[name] end)
    return if ok and type(result) == "number" then result else nil
end
local samples = {heartbeatMs = {}, physicsStepMs = {}, memoryMb = {}}
local function add(key, v)
    if v then table.insert(samples[key], v) end
end
local started = os.clock()
for _ = 1, 50 do
    local heartbeat = read("HeartbeatTime")
    local physics = read("PhysicsStepTime")
    if heartbeat then add("heartbeatMs", heartbeat * 1000) end
    if physics then add("physicsStepMs", physics * 1000) end
    add("memoryMb", Stats:GetTotalMemoryUsageMb())
    task.wait(0.2)
end
local function summary(values)
    if #values == 0 then return nil end
    table.sort(values)
    return {count = #values, min = values[1], p50 = values[math.ceil(#values * .50)],
        p95 = values[math.ceil(#values * .95)], max = values[#values]}
end
return HttpService:JSONEncode({
    placeId = game.PlaceId, elapsedSeconds = os.clock() - started,
    selectedLevel = workspace:GetAttribute("Level6SelectedLevel"),
    roundActive = workspace:GetAttribute("Level6RoundActive"),
    heartbeatMs = summary(samples.heartbeatMs),
    physicsStepMs = summary(samples.physicsStepMs),
    memoryMb = summary(samples.memoryMb),
})
