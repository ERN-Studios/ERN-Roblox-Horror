-- Read-only. Run in the Studio play CLIENT Luau context, especially after E/B/R input.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer
assert(player, "CLIENT context required")
local state = ReplicatedStorage:FindFirstChild("Level 6 State")
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local world = workspace:FindFirstChild("Level 6 Generated World")
local highlights = {}
for _, ancestor in ipairs({world, player.Character}) do
    if ancestor then
        for _, object in ipairs(ancestor:GetDescendants()) do
            if object:IsA("Highlight") and object.Name == "Level6CDDevESP" then
                table.insert(highlights, {
                    parent = object.Parent and object.Parent:GetFullName() or "",
                    adornee = object.Adornee and object.Adornee:GetFullName() or "",
                    enabled = object.Enabled,
                })
            end
        end
    end
end
local readerGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Level6ReaderGui")
local readerPanel = readerGui and readerGui:FindFirstChild("ReaderPanel", true)
local readerRestore = readerGui and readerGui:FindFirstChild("ReaderRestore", true)
local function property(name)
    local ok, result = pcall(function() return Stats[name] end)
    return if ok and type(result) == "number" then result else nil
end
local attributes = {}
if state then
    for key, item in pairs(state:GetAttributes()) do
        if string.sub(key, 1, 7) == "Level6_" and
            (type(item) == "string" or type(item) == "number" or type(item) == "boolean") then
            attributes[key] = item
        end
    end
end
-- Observe existing fetch state only. This does not preload and cannot by itself
-- prove that a normal map is visible on the mesh; inspect the viewport too.
local assetIds = {
    carpetCityNormal = 80660148568960,
    carpetDefaultNormal = 124245216980517,
    carpetNeonNormal = 77197908678900,
    carpetRedNormal = 82242543701773,
    diamondplateNormal = 119057460725717,
    kitchenTileNormal = 132898202245381,
    orangeAndRedWallNormal = 83563690907279,
    wallpaperNormal = 107064693112194,
    propsAtlas = 119366040096776,
}
local assetFetch = {}
for name, id in pairs(assetIds) do
    local ok, result = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, "rbxassetid://" .. tostring(id))
    assetFetch[name] = if ok then result.Name else "QUERY_ERROR: " .. tostring(result)
end
return HttpService:JSONEncode({
    placeId = game.PlaceId, userId = player.UserId,
    position = root and {root.Position.X, root.Position.Y, root.Position.Z} or nil,
    level6InRound = player:GetAttribute("Level6InRound"),
    previewActive = player:GetAttribute("Level6PreviewActive"),
    hiding = player:GetAttribute("Level6_Hiding"),
    readerGui = readerGui and {
        enabled = readerGui.Enabled, name = readerGui:GetFullName(),
        panelVisible = readerPanel and readerPanel.Visible or false,
        restoreVisible = readerRestore and readerRestore.Visible or false,
    } or nil,
    highlights = highlights,
    assetFetch = assetFetch,
    state = attributes,
    frameTimeSeconds = property("FrameTime"),
    renderCpuFrameTimeSeconds = property("RenderCPUFrameTime"),
    totalMemoryMb = Stats:GetTotalMemoryUsageMb(),
})
