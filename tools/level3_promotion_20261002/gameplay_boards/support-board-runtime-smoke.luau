-- Root-only optional Studio Play smoke; this drafting agent does not execute it.
-- Mutates three runtime display attributes, then restores them under a compare
-- guard. It never calls DataStoreService, monetization modules, or receipt APIs.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
assert(RunService:IsStudio() and RunService:IsRunning() and not RunService:IsClient(),
    "Use only the authorized local Studio Play server")
local folder = assert(ReplicatedStorage:FindFirstChild("ZyntraDonationLeaderboard"), "Provider missing")
local row = assert(folder:FindFirstChild("Row01"), "Provider Row01 missing")
assert(row:IsA("StringValue"), "Wrong provider row class")
local destination = workspace:FindFirstChild("LobbyReimaginedPreview", true)
    or ServerStorage:FindFirstChild("LobbyReimaginedPreview", true)
assert(destination and destination:IsA("Model")
    and destination:GetAttribute("LobbyReimaginedOwned") == true
    and destination:GetAttribute("Ready") == true, "Inspect actual R4 destination")
local board = assert(destination:FindFirstChild("ZyntraDonationLeaderboardBoard", true), "Moved board missing")
local panel = assert(board:FindFirstChild("LeaderboardPanel"), "Panel missing")
local display = assert(panel:FindFirstChild("DonationLeaderboardDisplay"), "Renderer missing")
local background = assert(display:FindFirstChild("Frame"), "Renderer frame missing")
local view = assert(background:FindFirstChild("Rank01"), "Actual renderer row missing")
local keys = {"Rank", "Name", "Robux"}
local injected = {Rank=1, Name="R4 LIVE SMOKE", Robux=12345}
local before, beforeValue = row:GetAttributes(), row.Value
local expected, changed = {}, {}
for _, key in ipairs(keys) do expected[key] = before[key] end
local observed
local ok, problem = xpcall(function()
    for _, key in ipairs(keys) do
        row:SetAttribute(key, injected[key])
        changed[key] = true
        expected[key] = injected[key]
    end
    task.wait(.15)
    observed = {
        Rank=assert(view:FindFirstChild("Rank")).Text,
        Name=assert(view:FindFirstChild("Name")).Text,
        Robux=assert(view:FindFirstChild("Robux")).Text,
    }
    assert(observed.Rank == "01" and observed.Name == injected.Name
        and observed.Robux == "12,345 R$", "Moved renderer did not consume attribute changes")
end, function(message) return tostring(message) end)
-- A provider refresh may run while the smoke yields. Never overwrite new data.
local unchanged = row.Parent ~= nil and row.Value == beforeValue
for _, key in ipairs(keys) do
    if row:GetAttribute(key) ~= expected[key] then unchanged = false end
end
local restored = false
if unchanged then
    for _, key in ipairs(keys) do
        if changed[key] then row:SetAttribute(key, before[key]) end
    end
    restored = true
end
task.wait(.15)
return {
    Passed=ok, Problem=not ok and problem or nil,
    BoardPath=board:GetFullName(), RowPath=row:GetFullName(), Observed=observed,
    RestoredOriginalAttributes=restored,
    ConcurrentProviderChangePreserved=not unchanged,
    ProviderValueUnchanged=row.Value == beforeValue,
    BeforeAttributes=before,
    AfterAttributes=row:GetAttributes(),
    Scope="Runtime renderer subscription smoke only; no DataStore/visibility claim",
}
