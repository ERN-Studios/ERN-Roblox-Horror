-- Read-only bounded 10-second ACTIVE-ROUND client sample. Studio play CLIENT context.
-- Actual local frame-time/FPS sample; does not claim multiplayer capacity.
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")
assert(RunService:IsClient(), "CLIENT context required")
local samples = {fps = {}, frameMs = {}, renderCpuMs = {}, memoryMb = {}}
local function read(name)
    local ok, result = pcall(function() return Stats[name] end)
    return if ok and type(result) == "number" then result else nil
end
local started = os.clock()
for _ = 1, 50 do
    local frame = read("FrameTime")
    if frame and frame > 0 then
        table.insert(samples.frameMs, frame * 1000)
        table.insert(samples.fps, 1 / frame)
    end
    local render = read("RenderCPUFrameTime")
    if render then table.insert(samples.renderCpuMs, render * 1000) end
    table.insert(samples.memoryMb, Stats:GetTotalMemoryUsageMb())
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
    level6InRound = game:GetService("Players").LocalPlayer:GetAttribute("Level6InRound"),
    fps = summary(samples.fps), frameMs = summary(samples.frameMs),
    renderCpuMs = summary(samples.renderCpuMs), memoryMb = summary(samples.memoryMb),
})
