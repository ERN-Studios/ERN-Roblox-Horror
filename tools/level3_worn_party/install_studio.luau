-- Execute only in the authoritative Roblox Studio Edit DataModel.
-- Generated from the frozen local native backup and reviewed Level 3 candidates.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local BASE = "http://127.0.0.1:8881"
local SNAPSHOT = "eeaa5d1eb197802bb65b31c9a7aaf5da58bbec8da77e121d611245152fd271d4"
local PATHS = {
    [1] = "ServerScriptService.Level 3 Systems.Level 3 Configuration",
    [2] = "ServerScriptService.Level 3 Systems.Level 3 Layout Generator",
    [3] = "ServerScriptService.Level 3 Systems.Level 3 Objective Controller",
    [4] = "ServerScriptService.Level 3 Systems.Level 3 Test Suite",
    [5] = "ServerScriptService.Level 6 Systems.Level6BlenderRuntimeBake",
    [6] = "ServerScriptService.Level 3 Systems.Level 3 Worn Party Room Dressing",
    [7] = "ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter",
    [8] = "ServerScriptService.Level 3 Systems.Level 3 Round Adapter",
}
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong experience")
assert(not RS:IsRunning(), "Studio must be in Edit mode")
assert(SSS:FindFirstChild("Level 3 Systems") and SSS:FindFirstChild("Level 6 Systems"), "Missing systems folder")
local source = assert(SS:FindFirstChild("Level6BlenderSource"), "Blender source missing")
assert(source:GetAttribute("Ready") == true, "Blender source is incomplete")
local kitMetadata = assert(SSS["Level 6 Systems"]:FindFirstChild("Level 6 Kit Metadata"), "Kit metadata missing")
assert(kitMetadata:IsA("ModuleScript") and kitMetadata:GetAttribute("Level6SourceSha256")
    == "c141f4c5246ece81288d1cefdedd8243057149d4844f8fea7c14ee428ff66f4b",
    "Kit metadata is not the verified v2 source")
local oldHttp = HS.HttpEnabled
local fetched, package = pcall(function()
    HS.HttpEnabled = true
    local m = HS:JSONDecode(HS:GetAsync(BASE .. "/manifest", true))
    assert(m.schema == "level3-worn-party-studio-install-v1" and m.snapshotSha256 == SNAPSHOT
        and m.placeId == game.PlaceId and m.universeId == game.GameId and #m.items == #PATHS,
        "Candidate snapshot differs from reviewed install")
    local p = {}
    for i, item in ipairs(m.items) do
        assert(item.id == i-1 and item.path == PATHS[i] and item.class == "ModuleScript", "Unexpected target " .. i)
        local candidate = HS:GetAsync(BASE .. "/source/" .. item.id, true)
        assert(#candidate == item.bytes, "Truncated source " .. item.path)
        local baseline
        if item.create then
            assert(item.baselineBytes == nil and item.baselineSha256 == nil, "Unexpected new-script baseline")
        else
            baseline = HS:GetAsync(BASE .. "/baseline/" .. item.id, true)
            assert(#baseline == item.baselineBytes and baseline ~= candidate, "Invalid baseline " .. item.path)
        end
        p[i] = {meta = item, candidate = candidate, baseline = baseline}
    end
    return p
end)
HS.HttpEnabled = oldHttp
assert(fetched, "Could not fetch reviewed local install: " .. tostring(package))
local function editorSource(target)
    local ok, value = pcall(SES.GetEditorSource, SES, target)
    assert(ok and type(value) == "string", "Cannot read current editor source: " .. target:GetFullName())
    return value
end
local folders = {
    ["Level 3 Systems"] = assert(SSS:FindFirstChild("Level 3 Systems")),
    ["Level 6 Systems"] = assert(SSS:FindFirstChild("Level 6 Systems")),
}
-- Full preflight before the first write, including unsaved editor buffers.
for _, entry in ipairs(package) do
    local item = entry.meta
    local folder = folders[item.folder]
    assert(folder and folder:IsA("Folder"), "Wrong parent: " .. item.path)
    local target = folder:FindFirstChild(item.name)
    if item.create then
        assert(target == nil, "New script already exists: " .. item.path)
    else
        assert(target and target:IsA("ModuleScript") and target.Parent == folder,
            "Wrong live instance: " .. item.path)
        assert(target.Source == entry.baseline and editorSource(target) == entry.baseline,
            "Studio Source/editor drift: " .. item.path)
    end
end
local results = {}
for _, entry in ipairs(package) do
    local item, candidate, baseline = entry.meta, entry.candidate, entry.baseline
    local folder = folders[item.folder]
    local target = folder:FindFirstChild(item.name)
    if item.create then
        assert(target == nil, "New target appeared during install: " .. item.path)
        target = Instance.new("ModuleScript")
        target.Name = item.name
        target.Source = candidate
        target.Parent = folder
    else
        assert(target and target:IsA("ModuleScript") and target.Parent == folder
            and target.Source == baseline and editorSource(target) == baseline,
            "Studio changed during install: " .. item.path)
        local drift = false
        SES:UpdateSourceAsync(target, function(old)
            if target.Parent ~= folder or old ~= baseline or target.Source ~= baseline
                or editorSource(target) ~= baseline then
                drift = true
                return old
            end
            return candidate
        end)
        assert(not drift, "Studio changed inside source update: " .. item.path)
    end
    local matched = false
    for _ = 1, 100 do
        if target.Parent == folder and target.Source == candidate
            and editorSource(target) == candidate then matched = true; break end
        task.wait(.05)
    end
    assert(matched, "Source/editor readback failed: " .. item.path)
    if item.name == "Level6BlenderRuntimeBake" then
        target:SetAttribute("Level6SourceSha256", item.sha256)
    end
    target:SetAttribute("Level3WornPartySourceSHA256", item.sha256)
    target:SetAttribute("Level3WornPartyInstallSnapshot", SNAPSHOT)
    table.insert(results, {path = item.path, sha256 = item.sha256, created = item.create, editorParity = true})
end
return HS:JSONEncode({ok = true, snapshotSha256 = SNAPSHOT,
    httpRestored = HS.HttpEnabled == oldHttp, results = results})
