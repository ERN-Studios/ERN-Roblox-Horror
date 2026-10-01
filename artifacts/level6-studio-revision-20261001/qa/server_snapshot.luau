-- Read-only. Run in the Studio play SERVER Luau context after each QA milestone.
-- Does not call EnsureWorld, Start, Join, debug helpers, or fire remotes.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local state = ReplicatedStorage:FindFirstChild("Level 6 State")
local world = workspace:FindFirstChild("Level 6 Generated World")
local function value(v)
    if typeof(v) == "Vector3" then return {v.X, v.Y, v.Z} end
    if typeof(v) == "CFrame" then return {v.Position.X, v.Position.Y, v.Position.Z} end
    if typeof(v) == "Color3" then return {v.R, v.G, v.B} end
    if typeof(v) == "Instance" then return v:GetFullName() end
    if type(v) == "table" then
        local o = {}
        for k, x in pairs(v) do o[tostring(k)] = value(x) end
        return o
    end
    if type(v) == "string" or type(v) == "number" or type(v) == "boolean" or v == nil then return v end
    return tostring(v)
end
local out = {
    placeId = game.PlaceId,
    jobId = game.JobId,
    wallClock = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    serverTime = workspace:GetServerTimeNow(),
    workspace = {
        selectedLevel = workspace:GetAttribute("Level6SelectedLevel"),
        roundActive = workspace:GetAttribute("Level6RoundActive"),
        huntActive = workspace:GetAttribute("Level6MallManagerHuntActive"),
        lightingOwned = workspace:GetAttribute("Level6LightingOwnedByController"),
    },
    -- Studio MCP execute_luau has an isolated require cache. Requiring live
    -- modules here would create fresh singleton instances and false zero/idle
    -- snapshots, so rely only on replicated state/instances/attributes.
    moduleSingletons = "not queried: MCP require context is isolated",
    players = {}, state = {}, world = nil, prompts = {},
}
for _, player in ipairs(Players:GetPlayers()) do
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    table.insert(out.players, {
        name = player.Name, userId = player.UserId,
        position = root and value(root.Position) or nil,
        inRound = player:GetAttribute("InRound"),
        level6InRound = player:GetAttribute("Level6InRound"),
        previewActive = player:GetAttribute("Level6PreviewActive"),
        escaped = player:GetAttribute("Level6Escaped"),
        hiding = player:GetAttribute("Level6_Hiding"),
        hideTableIndex = player:GetAttribute("Level6_HideTableIndex"),
    })
end
if state then
    for key, item in pairs(state:GetAttributes()) do
        if string.sub(key, 1, 7) == "Level6_" then out.state[key] = value(item) end
    end
end
local function promptInfo(prompt)
    local parent = prompt.Parent
    local part = if parent and parent:IsA("BasePart") then parent else parent and parent:FindFirstAncestorWhichIsA("BasePart")
    return {
        name = prompt.Name, parent = parent and parent:GetFullName() or nil,
        action = prompt.ActionText, object = prompt.ObjectText,
        enabled = prompt.Enabled, hold = prompt.HoldDuration,
        maxDistance = prompt.MaxActivationDistance,
        position = part and value(part.Position) or nil,
    }
end
local lobby = workspace:FindFirstChild("ServerLobby")
if lobby then
    local doorways = lobby:FindFirstChild("LevelDoorways")
    local door = doorways and doorways:FindFirstChild("Level6SealedDoor")
    local prompt = door and door:FindFirstChild("Level6DeveloperPreviewPrompt")
    if prompt and prompt:IsA("ProximityPrompt") then table.insert(out.prompts, promptInfo(prompt)) end
end
if world then
    local variants, meshCount, propsCount, lights, enabledLights = {}, 0, 0, 0, 0
    local cdStates, cdIndices = {}, {}
    for _, instance in ipairs(world:GetDescendants()) do
        if instance:IsA("MeshPart") then
            meshCount += 1
            local variant = instance.MaterialVariant
            variants[variant == "" and "(none)" or variant] = (variants[variant == "" and "(none)" or variant] or 0) + 1
            if instance.TextureID ~= "" then propsCount += 1 end
        elseif instance:IsA("Light") then
            lights += 1
            if instance.Enabled then enabledLights += 1 end
        elseif instance:IsA("ProximityPrompt") and (#out.prompts < 80) then
            if instance.Name == "CollectPrompt" or instance.Name == "HideUnderTablePrompt"
                or instance.Name == "Level6DeveloperPreviewReturnPrompt"
                or string.find(instance.Name, "Insert", 1, true) then
                table.insert(out.prompts, promptInfo(instance))
            end
        end
        local cdState = instance:GetAttribute("Level6_CDState")
        if cdState ~= nil then
            cdStates[tostring(cdState)] = (cdStates[tostring(cdState)] or 0) + 1
            local index = instance:GetAttribute("Level6_CDIndex")
            if index ~= nil then cdIndices[tostring(index)] = tostring(cdState) end
        end
    end
    out.world = {
        name = world:GetFullName(), attributes = value(world:GetAttributes()),
        meshParts = meshCount, meshVariants = variants, texturedMeshParts = propsCount,
        lights = lights, enabledLights = enabledLights,
        cdStates = cdStates, cdIndices = cdIndices,
    }
end
return HttpService:JSONEncode(out)
