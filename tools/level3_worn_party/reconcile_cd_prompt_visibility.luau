-- Reconcile the five CD prompts after a real Client pickup/insert Play test.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SNAPSHOT = "eeaa5d1eb197802bb65b31c9a7aaf5da58bbec8da77e121d611245152fd271d4"
local OLD_SHA = "df8f7739863d7db8038618e7d4bbd0a2718629961e178011516affd779cf7139"
local NEW_SHA = "badbf728d6c219f24c7beff2e7b9234633dac51fc0d3d4f3b1338edd94cb2613"
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong experience")
assert(not RS:IsRunning(), "Requires Studio Edit mode")
local systems = assert(SSS:FindFirstChild("Level 3 Systems"), "Missing Level 3 Systems")
local target = assert(systems:FindFirstChild("Level 3 Worn Party Visual Adapter"), "Missing visual adapter")
assert(target:IsA("ModuleScript") and target.Parent == systems, "Wrong visual adapter instance")
assert(target:GetAttribute("Level3WornPartyInstallSnapshot") == SNAPSHOT
    and target:GetAttribute("Level3WornPartySourceSHA256") == OLD_SHA,
    "Visual adapter changed since guarded install")
local wasHttp = HS.HttpEnabled
local fetched, baseline = pcall(function()
    HS.HttpEnabled = true
    return HS:GetAsync("http://127.0.0.1:8881/source/6", true)
end)
HS.HttpEnabled = wasHttp
assert(fetched and #baseline == 18850, "Could not fetch exact prior visual adapter source")
local needle = "        module.PickupParts = {disc, hub}"
local replacement = table.concat({
    needle,
    "        -- The new jewel-case mesh and the existing tabletop can occlude the",
    "        -- original prompt ray. Collection still checks distance and round state.",
    "        module.Prompt.RequiresLineOfSight = false",
}, "\n")
local at = assert(baseline:find(needle, 1, true), "Pickup-parts statement missing")
assert(baseline:find(needle, at + #needle, true) == nil, "Pickup-parts statement is not unique")
local candidate = baseline:sub(1, at-1) .. replacement .. baseline:sub(at+#needle)
assert(#candidate == 19059, "Unexpected candidate byte length")
local function editor()
    local ok, value = pcall(SES.GetEditorSource, SES, target)
    assert(ok and type(value) == "string", "Cannot read visual adapter editor source")
    return value
end
assert(target.Source == baseline and editor() == baseline, "Studio Source/editor changed")
local drift = false
SES:UpdateSourceAsync(target, function(old)
    if target.Parent ~= systems or target.Source ~= baseline or editor() ~= baseline
        or target:GetAttribute("Level3WornPartySourceSHA256") ~= OLD_SHA or old ~= baseline then
        drift = true
        return old
    end
    return candidate
end)
assert(not drift, "Visual adapter changed during source update")
local matched = false
for _ = 1, 100 do
    if target.Parent == systems and target.Source == candidate and editor() == candidate then
        matched = true
        break
    end
    task.wait(.05)
end
assert(matched, "Visual adapter source/editor readback failed")
target:SetAttribute("Level3WornPartySourceSHA256", NEW_SHA)
assert(target.Source == candidate and editor() == candidate, "Visual adapter changed after readback")
return HS:JSONEncode({ok = true, path = target:GetFullName(), newSha256 = NEW_SHA,
    sourceEditorParity = true, httpRestored = HS.HttpEnabled == wasHttp})
