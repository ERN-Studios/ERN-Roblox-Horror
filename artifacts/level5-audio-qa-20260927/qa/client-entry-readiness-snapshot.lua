-- Run only in the PLAY CLIENT context while the entry cover is visible.
-- Read-only: no remotes sent, attributes changed, assets fetched, or characters moved.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CP = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Requires PLAY CLIENT context, not server/edit mode")
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local selected = workspace:GetAttribute("SelectedLevel")
local report = {
    ServerTime = workspace:GetServerTimeNow(), GameLoaded = game:IsLoaded(),
    SelectedLevel = selected,
    LoadStage = workspace:GetAttribute("LoadStage"),
    LoadingState = workspace:GetAttribute("RoundLoadingState"),
    LoadingDeadline = workspace:GetAttribute("RoundLoadingDeadline"),
    WorldGenerated = workspace:GetAttribute("WorldGenerated"),
    RoundActive = workspace:GetAttribute("RoundActive"),
    Player = {}, Assets = {},
}
for _, key in ipairs({"RoundEntryUIReady", "RoundEntryControlsReady", "DevHoldEntryReady",
    "RoundEntryReadyToken", "RoundLoadingError", "InRound"}) do
    report.Player[key] = player:GetAttribute(key)
end
local world = workspace:FindFirstChild("Level " .. tostring(selected) .. " Generated World")
local pad = workspace:FindFirstChild("ElevatorSpawn")
report.HasWorld, report.HasPad = world ~= nil, pad ~= nil
report.CharacterInWorkspace = character ~= nil and character:IsDescendantOf(workspace)
report.Health = humanoid and humanoid.Health
if root and root:IsA("BasePart") then
    report.RootPosition = tostring(root.Position)
    report.RootAnchored = root.Anchored
    if pad and pad:IsA("BasePart") then report.DistanceToPad = (root.Position - pad.Position).Magnitude end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.IgnoreWater, params.RespectCanCollide = true, true
    local allowed = {}
    if selected == 1 then
        for _, name in ipairs({"Maze", "Elevator"}) do
            local item = workspace:FindFirstChild(name)
            if item then table.insert(allowed, item) end
        end
    elseif world then table.insert(allowed, world) end
    if pad then table.insert(allowed, pad) end
    params.FilterDescendantsInstances = allowed
    local hit = workspace:Raycast(root.Position + Vector3.yAxis * 2,
        Vector3.new(0, selected == 3 and -20 or -14, 0), params)
    report.GroundHit = hit and {Path = hit.Instance:GetFullName(),
        CanCollide = hit.Instance:IsA("BasePart") and hit.Instance.CanCollide,
        NormalY = hit.Normal.Y, Distance = hit.Distance} or false
end
local seen = {}
local function inspect(instance, property)
    local ok, content = pcall(function() return instance[property] end)
    if not ok or type(content) ~= "string" or content == "" or seen[content] then return end
    seen[content] = true
    local fetched, status = pcall(CP.GetAssetFetchStatus, CP, content)
    table.insert(report.Assets, {Path = instance:GetFullName(), Property = property,
        Content = content, Status = fetched and tostring(status) or "Unavailable"})
end
if character then
    for _, item in ipairs(character:GetDescendants()) do
        if item:IsA("MeshPart") then inspect(item, "MeshId"); inspect(item, "TextureID")
        elseif item:IsA("SpecialMesh") then inspect(item, "MeshId"); inspect(item, "TextureId")
        elseif item:IsA("Decal") or item:IsA("Texture") then inspect(item, "Texture") end
    end
end
print(HttpService:JSONEncode(report))
return report
